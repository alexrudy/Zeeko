from ..messages.utils cimport check_rc, check_ptr
from ..messages.receiver cimport Receiver
from ..messages.publisher cimport Publisher
from zmq.backend.cython.socket cimport Socket
from .base cimport Worker

cimport zmq.backend.cython.libzmq as libzmq
from libc.stdlib cimport free, malloc, realloc, calloc
from libc.string cimport memcpy
from libc.stdio cimport printf
from ..utils.clock cimport current_time
from .state cimport *

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

cdef class Throttle(Worker):
    
    cdef Publisher publisher
    cdef Receiver receiver
    cdef Socket _outbound
    cdef Socket _inbound
    cdef list subscriptions
    cdef str outbound_address
    cdef str inbound_address
    
    cdef readonly int counter
    cdef int kind
    
    cdef readonly double wait_time
    cdef double interval
    cdef readonly double last_message
    cdef public double maxlag
    cdef readonly double delay
    cdef readonly int snail_deaths
    cdef readonly int send_counter
    
    
    def __init__(self, ctx, inbound_address, outbound_address, kind=zmq.SUB):
        super(Throttle, self).__init__(ctx, inbound_address)
        self.publisher = Publisher()
        self.publisher.bundled = False
        self.receiver = Receiver()
        self.outbound_address = outbound_address
        self.inbound_address = inbound_address
        self.maxlag = 10.0
        self.interval = 1.0
        self.wait_time = 0.0
        self.last_message = 0.0
        self.send_counter = 0
        self.kind = kind
        self.subscriptions = []
    
    def subscribe(self, key):
        """Add a subscription key"""
        if self.kind == zmq.SUB:
            self.subscriptions.append(key)
        else:
            raise ValueError("Client is not a subscriber.")
    
    def __dealloc__(self):
        if self.publisher is not None:
            self.publisher._messages = NULL
    
    cdef int _run(self) nogil except -1:
        cdef void * outbound = self._outbound.handle
        cdef void * inbound = self._inbound.handle
        cdef void * internal = self._internal.handle
        cdef libzmq.zmq_pollitem_t items[3]
        cdef int sentinel
    
        cdef:
            double overhead = 0.0
            double error = 0.0
            double interval = self.interval # Full loop interval
            double gain = 0.2
            double leak = 1.0 - 1e-4
            double now = 0.0
            double next = 0.0
            double wait = 0.0
            int timeout = 0
            int n_poll = 3
    
    
        # initial settings
        self.wait_time = self.interval
        self.last_message = current_time()
        self.counter = 0
    
        items[0].socket = inbound
        items[1].socket = internal
        items[2].socket = outbound
        items[0].events = libzmq.ZMQ_POLLIN
        items[1].events = libzmq.ZMQ_POLLIN
        items[2].events = libzmq.ZMQ_POLLOUT
        
        while True:
            
            now = current_time()
            wait = (next - now) * 1e3
            if wait < self.timeout and wait > 1.0:
                timeout = <int>wait
                n_poll = 2
            elif wait < self.timeout and wait > 0.0:
                rc = self._wait(wait)
                if rc == 1:
                    return self.counter
            elif wait < 0:
                n_poll = 3
                timeout = self.timeout
            else:
                timeout = self.timeout
                n_poll = 2
            
            rc = libzmq.zmq_poll(items, n_poll, timeout)
            check_rc(rc)
            now = current_time()
            if (items[1].revents & libzmq.ZMQ_POLLIN):
                rc = zmq_recv_sentinel(internal, &sentinel, 0)
                self._state = sentinel
                return self.counter
            elif (items[0].revents & libzmq.ZMQ_POLLIN):
                self.receiver._receive(inbound, 0)
                rc = self._post_receive()
                if rc != 0:
                    return rc
            elif (items[2].revents & libzmq.ZMQ_POLLOUT) and ((next - now) * 1e3 < 1.0):
                if self.receiver._n_messages > 0:
                    self.publisher._messages = self.receiver._messages
                    self.publisher._n_messages = self.receiver._n_messages
                    self.publisher._publish(outbound, 0)
                    now = current_time()
                    overhead = now - self.last_message
                    error = (interval - overhead)
                    self.wait_time = (self.wait_time + (gain * error)) * leak
                    self.last_message = now
                    self.send_counter = self.send_counter + 1
                    next = now + self.wait_time
            
    cdef int _post_receive(self) nogil except -1:
        self.counter = self.counter + 1
        self.delay = current_time() - self.receiver.last_message
        if self.delay > self.maxlag:
            self._state = PAUSE
            self.snail_deaths = self.snail_deaths + 1
            return self.counter
        return 0
    
    def _py_pre_work(self):
        """When work starts, allocate the first socket."""
        self._inbound = self.context.socket(self.kind)
        self._outbound = self.context.socket(zmq.PUB)
        self._outbound.bind(self.outbound_address)

    def _py_pre_run(self):
        """On worker run, connect and subscribe."""
        self._inbound.connect(self.inbound_address)
        if self.kind == zmq.SUB:
            if len(self.subscriptions):
                for s in self.subscriptions:
                    self._inbound.subscribe(s)
                    self.log.debug("Subscribed to {:s}".format(s))

            else:
                self._inbound.subscribe("")
                self.log.debug("Subscribed to :all:")

    def _py_post_run(self):
        """On worker stop run, disconnect."""
        self._inbound.disconnect(self.inbound_address)
        self.log.debug("Ended 'RUN', accumulated {:d} snail deaths.".format(self.snail_deaths))

    def _py_post_work(self):
        """On worker done, close socket."""
        self._outbound.close()
        self._inbound.close()
    
    property frequency:
        def __get__(self):
            return 1.0 / self.interval
        def __set__(self, value):
            self.interval = 1.0 / value
    
