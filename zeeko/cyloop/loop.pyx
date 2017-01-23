from ..messages.utils cimport check_rc, check_ptr

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

STATE = {
    b'RUN': 1,
    b'PAUSE': 2,
    b'STOP': 3,
    b'INIT': 4,
}

cdef class SocketInfo:
    """Information about a socket and it's callbacks."""
    
    def __cinit__(self, Socket socket, int events):
        self.socket = socket # Retain reference.
        self.info.handle = socket.handle
        self.info.events = events
        
    def check(self):
        """Check this socketinfo"""
        assert self.info.handle is not NULL, "Socket handle is null."
        assert self.info.events, "Events must be some integer flag."
        assert self.info.callback is not NULL, "Callback must be set."
        
    def _close(self):
        """Close this socketinfo."""
        self.socket.close(linger=0)
    

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
        self._pollitems = <libzmq.zmq_pollitem_t *>calloc(1, sizeof(libzmq.zmq_pollitem_t *))
        self._n_pollitems = 1
    
    def __init__(self, ctx):
        self._state = INIT
        self.timeout = 10
        
        self.thread = threading.Thread(target=self._work)
        self._ready = Event()
        self._lock = Lock()
        
        self.context = ctx or zmq.Context.instance()
        self.log = logging.getLogger(".".join([self.__class__.__module__,self.__class__.__name__]))
        self._internal_address_interrupt = "inproc://{:s}-interrupt".format(hex(id(self)))
        self._internal_address_notify = "inproc://{:s}-interrupt-notify".format(hex(id(self)))
        
        # Internal items for the I/O Loop
        self._sockets = []
        
    def __dealloc__(self):
        if self._socketinfos is not NULL:
            free(self._socketinfos)
        if self._pollitems is not NULL:
            free(self._pollitems)
        
    def _add_socketinfo(self, SocketInfo sinfo):
        """Add a socket info object to the underlying structures."""
        sinfo.check()
        self._sockets.append(sinfo)
        with self._lock:
            
            self._socketinfos = <socketinfo **>realloc(self._socketinfos, sizeof(socketinfo *) * len(self._sockets))
            self._socketinfos[len(self._sockets) - 1] = &sinfo.info
            
            self._pollitems = <libzmq.zmq_pollitem_t *>realloc(self._pollitems, (len(self._sockets) + 1) * sizeof(libzmq.zmq_pollitem_t *))
            self.pollitems = &self._pollitems[1]
            
            self.pollitems[len(self._sockets) - 1].socket = sinfo.info.handle
            self.pollitems[len(self._sockets) - 1].events = sinfo.info.events
            self._n_pollitems = len(self._sockets) + 1
    
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
        try:
            self._internal.close(linger=0)
            self._notify.close(linger=0)
        except (zmq.ZMQError, zmq.Again) as e:
            self.log.warning("Ignoring exception in worker shutdown: {!r}".format(e))
    
    def _signal_state(self, state):
        """Signal a state change."""
        self._assert_not_done()
        signal = self.context.socket(zmq.PUSH)
        signal.connect(self._internal_address_interrupt)
        signal.send(s.pack("i", STATE[state]))
        signal.close(linger=1000)
    
    def _assert_not_done(self):
        if self._state == STOP:
            raise ValueError("Can't change state once the client is stopped.")
        elif self._state == INIT:
            self.thread.start()
            self._ready.wait(timeout=1.0)
    
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
        except ValueError:
            pass
        if self.thread.is_alive() and join:
            self.thread.join(timeout=timeout)
    
    def running(self):
        """Produce a context manager to ensure the shutdown of this worker."""
        return _RunningLoopContext(self)
    
    def _work(self):
        """Thread Worker Function"""
        self._internal = self.context.socket(zmq.PULL)
        self._internal.bind(self._internal_address_interrupt)
        self._pollitems[0].socket = self._internal.handle
        self._pollitems[0].events = libzmq.ZMQ_POLLIN
        
        self._notify = self.context.socket(zmq.PUB)
        self._notify.bind(self._internal_address_notify)
        self._state = PAUSE
        self._ready.set()
        try:
            while True:
                self._notify.send("notify:{:s}".format(self.state), zmq.NOBLOCK)
                with nogil:
                    if self._state == RUN:
                        self._run()
                    elif self._state == PAUSE:
                        self._pause()
                    elif self._state == STOP:
                        break
        finally:
            self._notify.send("notify:{:s}".format(self.state), zmq.NOBLOCK)
            self._close()
    
    cdef int _pause(self) nogil except -1:
        cdef int sentinel
        while True:
            self._lock._acquire()
            try:
                rc = libzmq.zmq_poll(self._pollitems, 1, self.timeout)
                check_rc(rc)
                if (self._pollitems[0].revents & libzmq.ZMQ_POLLIN):
                    rc = zmq_recv_sentinel(self._pollitems[0].socket, &sentinel, 0)
                    self._state = sentinel
                    return 0
            finally:
                self._lock._release()
        
    
    cdef int _wait(self, double waittime) nogil except -1:
        cdef int sentinel
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
            rc = libzmq.zmq_poll(self._pollitems, 1, timeout)
            check_rc(rc)
            if (self._pollitems[0].revents & libzmq.ZMQ_POLLIN):
                rc = zmq_recv_sentinel(self._pollitems[0].socket, &sentinel, 0)
                self._state = sentinel
                return 1
        return 0

    cdef int _run(self) nogil except -1:
        cdef int sentinel
        cdef socketinfo * s
        cdef libzmq.zmq_pollitem_t * p
        cdef size_t i
        
        while True:
            self._lock._acquire()
            try:
                rc = libzmq.zmq_poll(self._pollitems, self._n_pollitems, self.timeout)
                check_rc(rc)
            finally:
                self._lock._release()
            if (self._pollitems[0].revents & libzmq.ZMQ_POLLIN):
                rc = zmq_recv_sentinel(self._pollitems[0].socket, &sentinel, 0)
                self._state = sentinel
                return 0
            self._lock._acquire()
            try:
                for i in range(self._n_pollitems - 1):
                    if (self.pollitems[i].revents != 0 and self._socketinfos[i] is not NULL):
                        p = &self.pollitems[i]
                        s = self._socketinfos[i]
                        if s.callback is not NULL:
                            s.callback(p.socket, p.revents, s.data)
            finally:
                self._lock._release()
        
    
    property state:
        def __get__(self):
            if self._state == PAUSE:
                return "PAUSE"
            elif self._state == RUN:
                return "RUN"
            elif self._state == STOP:
                return "STOP"
            elif self._state == INIT:
                return "INIT"
            else:
                return "UNKNOWN"
            
        
    def is_alive(self):
        return self.thread.is_alive()
    
    def wsocket(self):
        """Wait on the underlying thread, listening for a state change."""
        socket = self.context.socket(zmq.SUB)
        socket.connect(self._internal_address_notify)
        socket.subscribe(b"notify")
        return socket