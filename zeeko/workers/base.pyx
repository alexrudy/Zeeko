
from ..messages.receiver cimport Receiver
from ..messages.utils cimport check_rc, check_ptr

cimport zmq.backend.cython.libzmq as libzmq
from libc.stdlib cimport free, malloc, realloc, calloc
from libc.string cimport memcpy
from libc.stdio cimport printf
from posix.time cimport timespec, nanosleep

from ..utils.clock cimport current_time

import threading
import zmq
import logging
import warnings
import struct as s

STATE = {
    'RUN': 1,
    'PAUSE': 2,
    'STOP': 3,
    'INIT': 4,
}

class _RunningWorkerContext(object):
    
    def __init__(self, worker):
        super(_RunningWorkerContext, self).__init__()
        self.worker = worker
    
    def __enter__(self):
        self.worker.start()
        
    def __exit__(self, *exc):
        self.worker.stop()

cdef class Worker:
    
    def __init__(self, ctx, address):
        
        self._state = INIT
        self.timeout = 10
        
        self.log = logging.getLogger(__name__)
        self.thread = threading.Thread(target=self._work)
        
        self.context = ctx or zmq.Context.instance()
        self.address = address
        self.log = logging.getLogger(".".join([self.__class__.__module__,self.__class__.__name__]))
        self._internal_address = "inproc://{:s}-interrupt".format(hex(id(self)))
        
    def _close(self):
        """Ensure that the worker is done and closes down properly."""
        try:
            self._internal.disconnect(self._internal_address)
        except zmq.ZMQError as e:
            if e.errno == zmq.ENOTCONN:
                pass
            else:
                self.log.warning("Exception in Worker disconnect: {!r}".format(e))
        try:
            self._internal.close(linger=0)
            self._py_post_work()
        except zmq.ZMQError as e:
            self.log.warning("Exception in Worker Shutdown: {!r}".format(e))
        
    def _signal_state(self, state):
        """Signal a state change."""
        self._not_done()
        signal = self.context.socket(zmq.PUSH)
        signal.connect(self._internal_address)
        signal.send(s.pack("i", STATE[state]))
        signal.close(linger=1000)
        
    def _not_done(self):
        if self._state == STOP:
            raise ValueError("Can't change state once the client is stopped.")
        elif self._state == INIT:
            self.thread.start()
        
    def start(self):
        self._signal_state("RUN")
        
    def pause(self):
        self._signal_state("PAUSE")
    
    def stop(self, timeout=None):
        self._signal_state("STOP")
        if self.thread.is_alive():
            self.thread.join(timeout=timeout)
        
    def running(self):
        """Produce a context manager to ensure the shutdown of this worker."""
        return _RunningWorkerContext(self)
        
    def _py_pre_run(self):
        """Hook for actions to take when the worker starts, while holding the GIL."""
        pass
        
    def _py_post_run(self):
        """Hook for actions to take after the worker is done running, while holding the GIL."""
        pass
        
    def _py_post_work(self):
        """Hook for actions to take after the worker is done, while holding the GIL."""
        pass
    
    def _py_pre_work(self):
        """Hook for actions to take before the worker starts, while holding the GIL."""
        pass
    
    def _py_run(self):
        """Hook for the run apperatus"""
        self._py_pre_run()
        with nogil:
            self._pre_run()
            self._run()
            self._post_run()
        self._py_post_run()
    
    def _work(self):
        """Thread Worker Function"""
        self._internal = self.context.socket(zmq.PULL)
        self._internal.bind(self._internal_address)
        self._state = PAUSE
        self._py_pre_work()
        while True:
            self.log.debug("State transition: {:s}.".format(self.state))
            if self._state == RUN:
                self._py_run()
            
            elif self._state == PAUSE:
                with nogil:
                    self._pause()
            
            elif self._state == STOP:
                break
        self._close()
        
    cdef int _pause(self) nogil except -1:
        cdef void * internal = self._internal.handle
        cdef int sentinel
        cdef libzmq.zmq_pollitem_t items[1]
        items[0].socket = internal
        items[0].events = libzmq.ZMQ_POLLIN
        while True:
            rc = libzmq.zmq_poll(items, 1, self.timeout)
            check_rc(rc)
            if (items[0].revents & libzmq.ZMQ_POLLIN):
                rc = zmq_recv_sentinel(internal, &sentinel, 0)
                self._state = sentinel
                return 0
            
        
    cdef int _wait(self, double waittime) nogil except -1:
        cdef void * internal = self._internal.handle
        cdef int sentinel
        cdef long timeout
        cdef libzmq.zmq_pollitem_t items[1]
        cdef timespec wait_ts
        
        if waittime < 1.0:
            # waiting less than one ms, don't poll.
            wait_ts.tv_nsec = <int>(waittime * 1e6)
            wait_ts.tv_sec = 0
            nanosleep(&wait_ts, NULL)
            return 0
        
        timeout = <long>waittime
        items[0].socket = internal
        items[0].events = libzmq.ZMQ_POLLIN
        if waittime > 0:
            rc = libzmq.zmq_poll(items, 1, timeout)
            check_rc(rc)
            if (items[0].revents & libzmq.ZMQ_POLLIN):
                rc = zmq_recv_sentinel(internal, &sentinel, 0)
                self._state = sentinel
                return 1
        return 0
    
    cdef int _post_receive(self) nogil except -1:
        return 0
    
    cdef int _post_run(self) nogil except -1:
        return 0
    
    cdef int _pre_run(self) nogil except -1:
        return 0
    
    cdef int _run(self) nogil except -1:
        self._pause()
        
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
    