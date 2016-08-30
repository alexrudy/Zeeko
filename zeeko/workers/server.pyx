
from ..messages.publisher cimport Publisher
from ..messages.utils cimport check_rc, check_ptr

cimport zmq.backend.cython.libzmq as libzmq
from libc.stdlib cimport free, malloc, realloc, calloc
from libc.string cimport memcpy
from libc.stdio cimport printf
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
}


cdef class Server(Worker):
    
    def __init__(self, ctx, address):
        super(Server, self).__init__(ctx, address)
        self.publisher = Publisher()
        self._outbound = self.context.socket(zmq.PUB)
        self.counter = 0
        self.interval = 1.0
        self.thread.start()
        
    def _py_pre_work(self):
        """Bind the outbound socket as soon as work starts."""
        self._outbound.bind(self.address)
    
    def _py_post_work(self):
        """Work here is done, close up shop."""
        self._outbound.disconnect(self.address)
        self._outbound.close()
        
        
    cdef int _run(self) nogil except -1:
        cdef void * outbound = self._outbound.handle
        cdef void * internal = self._internal.handle
        cdef libzmq.zmq_pollitem_t items[2]
        cdef int sentinel
        
        cdef:
            double overhead = 0.0
            double error = 0.0
            double interval = self.interval # Full loop interval
            double gain = 0.2
            double leak = 1.0 - 1e-4
            double now = 0.0
        
        
        # initial settings
        self.wait_time = self.interval
        self.last_message = current_time()
        self.counter = 0
        
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
            elif (items[0].revents & libzmq.ZMQ_POLLOUT):
                self.publisher._publish(outbound, 0)
                now = current_time()
                overhead = now - self.last_message
                error = (interval - overhead)
                self.wait_time = (self.wait_time + (gain * error)) * leak
                self.last_message = now
                self.counter = self.counter + 1
                rc = self._wait(self.wait_time * 1e3)
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
        
    property frequency:
        def __get__(self):
            return 1.0 / self.interval
        def __set__(self, value):
            self.interval = 1.0 / value
    
    