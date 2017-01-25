from ..utils.rc cimport check_zmq_rc, check_zmq_ptr, check_memory_ptr, check_generic_ptr

cimport zmq.backend.cython.libzmq as libzmq
from libc.stdlib cimport free, malloc, realloc, calloc
from libc.string cimport memcpy
from libc.stdio cimport printf
from posix.time cimport timespec, nanosleep

from ..utils.clock cimport current_time
from ..utils.lock cimport Lock
from ..utils.condition cimport Event

import threading
import zmq
import logging
import warnings
import struct as s
from ._state import StateError, STATE

cdef inline str address_of(void * ptr):
    return hex(<size_t>ptr)

cdef class SocketInfo:
    """Information about a socket and it's callbacks."""
    
    def __cinit__(self, Socket socket, int events):
        self.socket = socket # Retain reference.
        self.events = events
        
    def check(self):
        """Check this socketinfo"""
        assert isinstance(self.socket, zmq.Socket), "Socket is None"
        assert self.socket.handle != NULL, "Socket handle is null"
        assert self.callback != NULL, "Callback must be set."
        
    def _start(self):
        """Python function run as the loop starts."""
        pass
        
    def _close(self):
        """Close this socketinfo."""
        self.socket.close(linger=0)
    
    cdef int bind(self, libzmq.zmq_pollitem_t * pollitem) nogil except -1:
        cdef int rc = 0
        pollitem.events = self.events
        pollitem.socket = self.socket.handle
        pollitem.fd = 0
        pollitem.revents = 0
        return rc
        
    cdef int fire(self, libzmq.zmq_pollitem_t * pollitem, void * interrupt) nogil except -1:
        cdef int rc = 0
        if pollitem.socket != self.socket.handle:
            with gil:
                raise ValueError("Poll socket does not match socket owned by this object.")
        if ((self.events & pollitem.revents) or (not self.events)):
            return self.callback(self.socket.handle, pollitem.revents, self.data, interrupt)
        else:
            return -2
    
    def __call__(self, Socket socket, int events, Socket interrupt_socket):
        """Run the callback from python"""
        cdef libzmq.zmq_pollitem_t pollitem
        cdef int rc 
        
        pollitem.socket = socket.handle
        pollitem.revents = events
        pollitem.events = self.events
        rc = self.fire(&pollitem, interrupt_socket.handle)
        return rc

class _RunningLoopContext(object):

    def __init__(self, ioloop):
        super(_RunningLoopContext, self).__init__()
        self.ioloop = ioloop

    def __enter__(self):
        self.ioloop.start()

    def __exit__(self, *exc):
        self.ioloop.stop()

cdef class IOLoop:
    """An I/O loop, using ZMQ's poller internally."""
    
    def __cinit__(self, ctx):
        self._socketinfos = NULL
        self._pollitems = <libzmq.zmq_pollitem_t *>calloc(1, sizeof(libzmq.zmq_pollitem_t))
        check_memory_ptr(self._pollitems)
        self._n_pollitems = 1
    
    def __init__(self, ctx):
        self._state = StateMachine()
        self.timeout = 10
        self.mintime = 10
        
        self.thread = threading.Thread(target=self._work)
        self._lock = Lock()
        
        self.context = ctx or zmq.Context.instance()
        self.log = logging.getLogger(".".join([self.__class__.__module__,self.__class__.__name__]))
        self._internal_address_interrupt = "inproc://{:s}-interrupt".format(hex(id(self)))
        
        # Internal items for the I/O Loop
        self._sockets = []
        
    def __dealloc__(self):
        if self._socketinfos != NULL:
            free(self._socketinfos)
        if self._pollitems != NULL:
            free(self._pollitems)
        
    def _add_socketinfo(self, SocketInfo sinfo):
        """Add a socket info object to the underlying structures."""
        if not self._state.check(INIT):
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
        try:
            self._internal.disconnect(self._internal_address_interrupt)
        except (zmq.ZMQError, zmq.Again) as e:
            if e.errno == zmq.ENOTCONN or e.errno == zmq.EAGAIN:
                # Ignore errors that signal that we've already disconnected.
                pass
            else:
                self.log.warning("Exception in Worker disconnect: {!r}".format(e))
        
        for si in self._sockets:
            si._close()
        
        for socket in (self._interrupt, self._internal):
            try:
                socket.close(linger=0)
            except (zmq.ZMQError, zmq.Again) as e:
                self.log.warning("Ignoring exception in worker shutdown: {!r}".format(e))
    
    def _signal_state(self, state):
        """Signal a state change."""
        self._assert_not_done()
        self._state.signal(state, self._internal_address_interrupt, self.context)
    
    def _assert_not_done(self):
        self._state.guard(STOP)
        if self._state.check(INIT):
            self.thread.start()
            self._state.deselected(START).wait(timeout=1.0)
    
    def start(self):
        self._signal_state(b"RUN")
    
    def pause(self):
        self._signal_state(b"PAUSE")

    def stop(self, timeout=None, join=True):
        self._signal_state(b"STOP")
        if self.thread.is_alive() and join:
            self.thread.join(timeout=timeout)
    
    def cancel(self, timeout=None, join=True):
        """Cancels the loop operations."""
        try:
            self._signal_state(b"STOP")
        except StateError:
            pass
        if self.thread.is_alive() and join:
            self.thread.join(timeout=timeout)
    
    def running(self):
        """Produce a context manager to ensure the shutdown of this worker."""
        return _RunningLoopContext(self)
    
    def _work(self):
        """Thread Worker Function"""
        self._state.set(START)
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
            for sinfo in self._sockets:
                sinfo._start()
        
        self._state.set(PAUSE)
        try:
            with nogil:
                while True:
                    if self._state.check(RUN):
                        self._run()
                    elif self._state.check(PAUSE):
                        self._pause()
                    elif self._state.check(STOP):
                        break
        finally:
            self._close()
    
    cdef int _pause(self) nogil except -1:
        self._lock._acquire()
        try:
            rc = check_zmq_rc(libzmq.zmq_poll(self._pollitems, 1, self.timeout))
            return self._state.sentinel(&self._pollitems[0])
        finally:
            self._lock._release()
        
    
    cdef int _wait(self, double waittime) nogil except -1:
        cdef long timeout
        cdef timespec wait_ts
    
        if waittime < 1.0:
            # waiting less than one ms, don't poll.
            wait_ts.tv_nsec = <int>(waittime * 1e6)
            wait_ts.tv_sec = 0
            nanosleep(&wait_ts, NULL)
            return 0
    
        timeout = <long>waittime
        if waittime > 0:
            rc = check_zmq_rc(libzmq.zmq_poll(self._pollitems, 1, timeout))
            return self._state.sentinel(&self._pollitems[0])
        return 0

    cdef int _run(self) nogil except -1:
        cdef size_t i
        cdef int rc = 0
        cdef double start = current_time()
        cdef double duration = 0.0
        self._lock._acquire()
        try:
            rc = check_zmq_rc(libzmq.zmq_poll(self._pollitems, self._n_pollitems, self.timeout))
            if self._state.sentinel(&self._pollitems[0]) != 1:
                for i in range(1, self._n_pollitems):
                    rc = (<SocketInfo>self._socketinfos[i-1]).fire(&self._pollitems[i], self._interrupt_handle)            
            duration = current_time() - start
            if duration < self.mintime:
                self._wait(self.mintime - duration)
        finally:
            self._lock._release()
        return rc
    
    cdef int _check_pollitems(self, int n) except -1:
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
    
    property state:
        def __get__(self):
            return self._state.name
            
    def is_alive(self):
        return self.thread.is_alive()
    