
from ..messages.publisher cimport Publisher
from ..messages.utils cimport check_rc, check_ptr

cimport zmq.backend.cython.libzmq as libzmq
from libc.stdlib cimport free, malloc, realloc, calloc
from libc.string cimport memcpy
from posix.time cimport timespec, nanosleep
from libc.stdio cimport printf
from ..utils.clock cimport current_time

import threading
import zmq
import logging
import warnings
import struct as s

STATE = {
    'START': 1,
    'PAUSE': 2,
    'STOP': 3,
}


cdef class Server:
    
    def __cinit__(self, Context ctx, str address, double frequency = 1.0):
        self.log = logging.getLogger(".".join([__name__,"Client"]))
        self.context = ctx or zmq.Context.instance()
        self.thread = threading.Thread(target=self._work)
        self.publisher = Publisher()
        self._outbound = ctx.socket(zmq.PUB)
        self._internal = ctx.socket(zmq.PULL)
        self.counter = 0
        self.timeout = 10
        self.interval = 1.0 / frequency
        self.address = address
        self._internal_address = ""
        self.subscriptions = []
        self._state = PAUSE
        self._last_state = "INIT"
        
    def __init__(self, ctx, address, frequency = 1.0):
        self._internal_address = "inproc://{:s}-interrupt".format(hex(id(self)))
        self.thread.start()
        
    def _signal_state(self, state):
        """Signal a state change."""
        self._not_done()
        signal = self.context.socket(zmq.PUSH)
        signal.connect(self._internal_address)
        signal.send(s.pack("i", STATE[state]))
        signal.close()
        
    def _not_done(self):
        if self._state == STOP:
            raise ValueError("Can't change state once the client is stopped.")
        
    def start(self):
        self._signal_state("START")
        
    def pause(self):
        self._signal_state("PAUSE")
    
    def stop(self):
        self._signal_state("STOP")
        self.thread.join()
        
    def subscribe(self, key):
        """Add a subscription key"""
        self.subscriptions.append(key)
        
    def _work(self):
        """Thread Worker Function"""
        self._internal.bind(self._internal_address)
        self._outbound.bind(self.address)
        while True:
            self.log.debug("State transition: {:s} -> {:s}.".format(self._last_state, self.state))
            self._last_state = self.state
            if self._state == START:
                
                with nogil:
                    self._run()
            
            elif self._state == PAUSE:
                with nogil:
                    self._pause()
            
            elif self._state == STOP:
                break
        try:
            self._outbound.disconnect(self.address)
            self._internal.disconnect(self._internal_address)
            self._internal.close()
            self._outbound.close()
        except zmq.ZMQError as e:
            self.log.warning("Exception in Client Shutdown: {!r}".format(e))
        
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
            
        
    cdef int _wait(self, long waittime) nogil except -1:
        cdef void * internal = self._internal.handle
        cdef int sentinel
        cdef libzmq.zmq_pollitem_t items[1]
        items[0].socket = internal
        items[0].events = libzmq.ZMQ_POLLIN
        if waittime > 0:
            rc = libzmq.zmq_poll(items, 1, waittime)
            check_rc(rc)
            if (items[0].revents & libzmq.ZMQ_POLLIN):
                rc = zmq_recv_sentinel(internal, &sentinel, 0)
                self._state = sentinel
                return 1
        return 0
        
    cdef int _run(self) nogil except -1:
        cdef void * outbound = self._outbound.handle
        cdef void * internal = self._internal.handle
        cdef int sentinel
        
        cdef:
            double overhead = 0.0
            double error = 0.0
            double interval = self.interval # Full loop interval
            double gain = 0.2
            double leak = 1.0 - 1e-4
            double now = 0.0
        
        cdef timespec wait_ts
        cdef libzmq.zmq_pollitem_t items[2]
        self.wait_time = self.interval
        self.last_message = current_time()
        items[0].socket = outbound
        items[1].socket = internal
        items[0].events = libzmq.ZMQ_POLLOUT
        items[1].events = libzmq.ZMQ_POLLIN
        while True:
            rc = libzmq.zmq_poll(items, 2, self.timeout)
            check_rc(rc)
            if (items[1].revents & libzmq.ZMQ_POLLIN):
                rc = zmq_recv_sentinel(internal, &sentinel, 0)
                self._state = sentinel
                return self.counter
            #elif (items[0].revents & libzmq.ZMQ_POLLOUT):
            self.publisher._publish(outbound, 0)
            now = current_time()
            overhead = now - self.last_message
            error = (interval - overhead)
            self.wait_time = (self.wait_time + (gain * error)) * leak
            self.last_message = now
            self.counter = self.counter + 1
            if (1e3*self.wait_time) < 1.0:
                wait_ts.tv_nsec = <int>(self.wait_time * 1e9)
                wait_ts.tv_sec = 0
                nanosleep(&wait_ts, NULL)
            else:
                rc = self._wait(<int>(self.wait_time * 1e3))
                if rc == 1:
                    return self.counter
    
    def __getitem__(self, key):
        return self.publisher.__getitem__(key)
        
    def __setitem__(self, key, value):
        self.publisher.__setitem__(key, value)
    
    def __len__(self):
        return self.publisher.__len__()

    def keys(self):
        return self.publisher.keys()
        
    property state:
        def __get__(self):
            if self._state == PAUSE:
                return "PAUSE"
            elif self._state == START:
                return "START"
            elif self._state == STOP:
                return "STOP"
            else:
                return "UNKNOWN"
        
    property frequency:
        def __get__(self):
            return 1.0 / self.interval
        def __set__(self, value):
            self.interval = 1.0 / value
    
    