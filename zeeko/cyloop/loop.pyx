#cython: embedsignature=True

cimport zmq.backend.cython.libzmq as libzmq
from libc.stdlib cimport free, malloc, realloc, calloc
from libc.string cimport memcpy

from ..utils.rc cimport check_zmq_rc, check_zmq_ptr, check_memory_ptr, check_generic_ptr
from ..utils.clock cimport current_time
from ..utils.condition cimport Event
from ..handlers.base cimport SocketInfo, socketinfo

import threading
import zmq
import logging
import warnings
import weakref
import struct as s
from .statemachine import StateError, STATE
from .statemachine cimport *

__all__ = ['IOLoop']

cdef inline str address_of(void * ptr):
    return hex(<size_t>ptr)

class _RunningLoopContext(object):

    def __init__(self, ioloop, timeout=None):
        super(_RunningLoopContext, self).__init__()
        self.ioloop = ioloop
        self.timeout = timeout

    def __enter__(self):
        self.ioloop.start()

    def __exit__(self, *exc):
        self.ioloop.stop(timeout=self.timeout)
        

cdef class IOLoopWorker:
    """The running part of the I/O loop."""
    
    cdef object __weakref__
    cdef object thread
    cdef object log
    cdef object _manager
    
    cdef Socket _internal
    cdef Context context
    cdef readonly Socket _interrupt
    cdef void * _interrupt_handle
    
    cdef str _internal_address_interrupt
    cdef str _next_address_interrupt
    cdef Event _next_address_started
    cdef list _sockets
    cdef void ** _socketinfos
    
    cdef libzmq.zmq_pollitem_t * _pollitems
    cdef int _n_pollitems
    
    cdef readonly StateMachine state
    cdef readonly Throttle throttle
    cdef Lock _lock # Lock
    cdef Event _started
    
    def __cinit__(self):
        self._socketinfos = NULL
        self._pollitems = <libzmq.zmq_pollitem_t *>calloc(1, sizeof(libzmq.zmq_pollitem_t))
        check_memory_ptr(self._pollitems)
        self._n_pollitems = 1
        self.throttle = Throttle()
        self.throttle.timeout = 0.1
        self._started = Event()
        self._manager = lambda : None
        
    def __init__(self, manager, ctx, state, index):
        self._sockets = []
        self.state = state or StateMachine()        
        self._lock = Lock()
        self.context = ctx or zmq.Context.instance()
        self.log = logging.getLogger(".".join([self.__class__.__module__,self.__class__.__name__]))
        self._internal_address_interrupt = "inproc://{0:s}-interrupt".format(hex(id(self)))
        self.thread = threading.Thread(target=self._work, name='IOLoopWorker-{0:d}'.format(index))
        self._manager = weakref.ref(manager)
        
    def __dealloc__(self):
        if self._socketinfos != NULL:
            free(self._socketinfos)
        if self._pollitems != NULL:
            free(self._pollitems)
            
        
    @property
    def manager(self):
        return self._manager()
        
    @property
    def _chain_address(self):
        return self._internal_address_interrupt
    
    # Allow chaining workers
    def set_chained_address(self, address, event):
        self._next_address_interrupt = address
        self._next_address_started = event
    
    # Proxy certain threading.Thread methods
    def is_alive(self):
        return self.thread.is_alive()
    
    def join(self, timeout=None):
        try:
            return self.thread.join(timeout=timeout)
        except RuntimeError:
            pass
    
    def start(self):
        return self.thread.start()
        
    # Thread management functions
    def _signal_state(self, state, timeout=100):
        """Signal a state change."""
        self._not_done()
        self.log.debug("state.signal({0})".format(state))
        self.state.signal(state, self._internal_address_interrupt, context=self.context, timeout=timeout)
        self.log.debug("state.signal({0}) [DONE]".format(state))
    
    def _not_done(self):
        if self.state._check(STOP):
            return
        if not self.is_alive():
            self.log.debug("thread.start()")
            try:
                self.start()
            except RuntimeError:
                pass
            self.log.debug("state.deselected(START).wait()")
            self._started.wait(timeout=0.1)
            self.log.debug("state.deselected(START).wait() [DONE]")
    
    def _add_socketinfo(self, SocketInfo sinfo):
        """Add a socket info object to the underlying structures."""
        if not self.state.check(INIT):
            raise StateError("Can't add sockets after INIT.")
        sinfo.check()
        self._sockets.append(sinfo)
        with self._lock:
    
            self._socketinfos = <void **>check_memory_ptr(realloc(self._socketinfos, sizeof(socketinfo *) * len(self._sockets)))
            self._socketinfos[len(self._sockets) - 1] = <void *>sinfo
    
            self._pollitems = <libzmq.zmq_pollitem_t *>realloc(self._pollitems, (len(self._sockets) + 1) * sizeof(libzmq.zmq_pollitem_t))
            check_memory_ptr(self._pollitems)
            sinfo.bind(&self._pollitems[len(self._sockets)])
            # address = address_of(self._pollitems[len(self._sockets)].socket)
            # print("{:d}) {:s} connected".format(len(self._sockets), address))
            self._n_pollitems = len(self._sockets) + 1

    def _remove_socketinfo(self, SocketInfo sinfo):
        """Remove a socektinfo object from the eventloop."""
        pass
    
    def _close(self):
        """Ensure that the IOLoop is done and closes down properly.
    
        This method should only be called from the internal worker thread.
        """
        self.log.debug("Closing {0}".format(self.thread.name))
        
        try:
            self._internal.disconnect(self._internal_address_interrupt)
        except (zmq.ZMQError, zmq.Again) as e:
            if e.errno == zmq.ENOTCONN or e.errno == zmq.EAGAIN:
                # Ignore errors that signal that we've already disconnected.
                pass
            else:
                self.log.warning("Exception in Worker disconnect: {0!r}".format(e))
    
        for si in self._sockets:
            si._close()
    
        for socket in (self._interrupt, self._internal):
            try:
                socket.close(linger=0)
            except (zmq.ZMQError, zmq.Again) as e:
                self.log.warning("Ignoring exception in worker shutdown: {0!r}".format(e))
            
        
    def _start(self):
        """Thread initialization function."""
        self.state.set(START)
        self.log.debug("Starting {0}".format(self.thread.name))
        self._internal = self.context.socket(zmq.PULL)
        self._internal.bind(self._internal_address_interrupt)

        with self._lock:
            self._pollitems[0].socket = self._internal.handle
            self._pollitems[0].events = libzmq.ZMQ_POLLIN
            rc = self._check_pollitems(self._n_pollitems)

        self._interrupt = self.context.socket(zmq.PUSH)
        self._interrupt.connect(self._internal_address_interrupt)
        self._interrupt_handle = <void *>self._interrupt.handle


        with self._lock:
            for si in self._sockets:
                si._start()

        self.throttle.reset()
        self._started.set()
        self.log.debug("Paused {0}".format(self.thread.name))
        self.state.set(PAUSE)
    
    def _work(self):
        """Thread Worker Function"""
        self._start()
        try:
            with nogil:
                while True:
                    if self.state.check(STOP):
                        break
                    elif self.state.check(RUN):
                        self._run()
                    elif self.state.check(PAUSE):
                        self._pause()
                    
                    #NOTE: It is important that this call happen *last*
                    # so that we don't send the initial state of the loop
                    # onwards. It will still propogate the STOP command
                    # becasue that will happen on exiting _run() or _pause().
                    self._propogate()
        except Exception as e:
            self.log.exception("Exception in worker thread {0}.".format(self.thread.name))
            raise
        finally:
            self._close()

    cdef long _get_timeout(self) nogil:
        """Compute the appropriate timeout."""
        cdef int i
        cdef long si_timeout = 0
        cdef double now = current_time()
        cdef long timeout = self.throttle.get_timeout_at(now, 0)
        for i in range(1, self._n_pollitems):
            if (<SocketInfo>self._socketinfos[i-1]).throttle.active:
                si_timeout = (<SocketInfo>self._socketinfos[i-1]).throttle.get_timeout_at(now, 0)
                if si_timeout < timeout:
                    timeout = si_timeout
        return timeout
    
    cdef int _propogate(self) nogil except -1:
        if self._next_address_interrupt != None:
            with gil:
                if self._next_address_started != None:
                    self._next_address_started.wait(timeout=0.1)
                self.log.debug("{0} -> {1} {2}".format(self.thread.name, self._next_address_interrupt, self.state.name))
                self.state.signal(self.state.name, self._next_address_interrupt, context=self.context, timeout=100)
        return 0
    
    cdef int _pause(self) nogil except -1:
        cdef int rc = 0
        cdef int i
        
        with gil:
            self.log.debug("{0} paused".format(self.thread.name))
        self._lock._acquire()
        try:
            for i in range(1, self._n_pollitems):
                rc = (<SocketInfo>self._socketinfos[i-1]).paused()
        finally:
            self._lock._release()

        while self.state.check(PAUSE):
            self._lock._acquire()
            try:
                rc = check_zmq_rc(libzmq.zmq_poll(self._pollitems, 1, self.throttle.get_timeout()))
                self.throttle.start()
                rc = self.state.sentinel(&self._pollitems[0])
                if rc == 1:
                    with gil:
                        self.log.debug("{0} -> {1}".format(self.thread.name, self.state.name))
            finally:
                self.throttle.mark()
                self._lock._release()
        return rc

    cdef int _run(self) nogil except -1:
        cdef size_t i
        cdef int rc = 0
        cdef double now = current_time()
        with gil:
            self.log.debug("{0} run".format(self.thread.name))

        self._lock._acquire()
        try:
            for i in range(1, self._n_pollitems):
                rc = (<SocketInfo>self._socketinfos[i-1]).resumed()
        finally:
            self._lock._release()

        while self.state.check(RUN):
            self._lock._acquire()
            try:
                rc = check_zmq_rc(libzmq.zmq_poll(self._pollitems, self._n_pollitems, self._get_timeout()))
                now = current_time()
                self.throttle.start_at(now)
                for i in range(1, self._n_pollitems):
                    rc = (<SocketInfo>self._socketinfos[i-1]).throttle.start_at(now)
                if self.state.sentinel(&self._pollitems[0]) != 1:
                    for i in range(1, self._n_pollitems):
                        rc = (<SocketInfo>self._socketinfos[i-1]).fire(&self._pollitems[i], self._interrupt_handle)
                else:
                    with gil:
                        self.log.debug("{0} -> {1}".format(self.thread.name, self.state.name))
                now = current_time()
                self.throttle.mark_at(now)
            finally:
                self._lock._release()
        return rc

    cdef int _check_pollitems(self, int n) except -1:
        cdef int i
        for i in range(n):
            address = address_of(self._pollitems[i].socket)
            if self._pollitems[i].socket == NULL and self._pollitems[i].fd == 0:
                raise ValueError("No socket or fd set for pollitem {0:d}".format(i))
            if i > 0:
                if self._socketinfos[i - 1] == NULL:
                    raise ValueError("No callback set for pollitem {0:d}".format(i))
                if (<Socket>self._sockets[i - 1].socket).handle != self._pollitems[i].socket:
                    raise ValueError("Socket mismatch for item {0:d}, expected handle {1:s}, got {2:s}".format(i,
                            address, address_of((<Socket>self._sockets[i - 1].socket).handle)))
        return 0

cdef class IOLoop:
    """An I/O loop manager which relies on polling via ZMQ."""
    
    def __init__(self, ctx):
        self.state = StateMachine()        
        self.workers = []
        self.context = ctx or zmq.Context.instance()
        self.log = logging.getLogger(".".join([self.__class__.__module__,self.__class__.__name__]))
        self.add_worker()
    
    def __repr__(self):
        return "<{0} n={1} {2}>".format(self.__class__.__name__, len(self.workers), self.state.name)
    
    def add_worker(self):
        """Add a new worker to this I/O Loop.
        
        Each I/O loop by default has a single worker thread. This adds an additional
        worker thread which can run an addtional polling loop."""
        cdef IOLoopWorker worker
        if len(self.workers):
            worker = IOLoopWorker(self, self.context, StateMachine(), len(self.workers))
            prev_worker = self.workers[-1]
            prev_worker.set_chained_address(worker._chain_address, worker._started)
        else:
            worker = IOLoopWorker(self, self.context, self.state, len(self.workers))
        self.workers.append(worker)
        
    def attach(self, socketinfo, index=0):
        """Attach a socket to the I/O Loop.
        
        :param socketinfo: The socket info object to attach to the loop.
        :param index: The index of the worker to attach.
        """
        socketinfo._attach(self.workers[index])
    
    def configure_throttle(self, **kwargs):
        """Apply a configuration to worker throttles.
        
        The keyword arguments are applied to each worker's
        :class:`~zeeko.cyloop.throttle.Throttle` object.
        """
        for worker in self.workers:
            worker.throttle.configure(**kwargs)
    
    def signal(self, state, timeout=100):
        """Signal a specific state to each worker.
        
        :param str state: The name of the state for signaling.
        """
        cdef IOLoopWorker worker
        for worker in self.workers:
            if not worker._started.is_set():
                worker.start()
        for worker in self.workers:
            worker._started.wait(timeout=timeout)
        if len(self.workers):
            self.workers[0]._signal_state(state, timeout=timeout)
            self.workers[-1].state.selected(state).wait(timeout=timeout)
    
    def start(self, timeout=1.0):
        """Start the workers."""
        self.signal(b"RUN", timeout=timeout)
        
    def resume(self, timeout=1.0):
        """Resume the workers"""
        self.state.guard(INIT)
        self.signal(b"RUN", timeout=timeout)
    
    def pause(self, timeout=1.0):
        """Pause all workers"""
        self.signal(b"PAUSE", timeout=timeout)

    def stop(self, timeout=1.0, join=True):
        """Stop the workers.
        
        :param timeout: Seconds to wait for workers to join.
        :param bool join: Whether to join worker threads, or leave them dangling.
        """
        self.signal(b"STOP", timeout=timeout)
        if join:
            self.join(timeout=timeout)
        
    def join(self, timeout=None):
        """Join worker threads.
        
        :param timeout: Seconds to wait for workers to join.
        """
        for worker in self.workers:
            worker.join(timeout=timeout)
    
    def cancel(self, timeout=1.0, join=True):
        """Cancel the loop operations.
        
        :param timeout: Seconds to wait for workers to join.
        :param bool join: Whether to join worker threads, or leave them dangling.
        """
        try:
            self.signal(b"STOP", timeout=timeout)
        except StateError:
            pass
        self.join(timeout=timeout)
    
    def is_alive(self):
        """Return whether any worker thread is alive."""
        return any(worker.is_alive() for worker in self.workers)
    
    def running(self, timeout=None):
        """Produce a context manager to ensure the shutdown of this worker.
        
        :param timeout: Seconds to wait for workers to join when exiting the context manager.
        """
        return _RunningLoopContext(self, timeout=timeout)
  
cdef class DebugIOLoop(IOLoop):
    """Python method access to IOLoop functionality."""
    
    def run(self, once=True):
        """Trigger the core run-loop for this IOLoop instance."""
        if once:
            self.signal(PAUSE)
        for worker in self.workers:
            (<IOLoopWorker>worker)._run()
            
    def get_timeout(self):
        return (<IOLoopWorker>self.worker)._get_timeout()
        
    property worker:
        def __get__(self):
            assert len(self.workers) == 1
            return self.workers[0]