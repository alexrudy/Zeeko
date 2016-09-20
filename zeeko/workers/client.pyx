
from ..messages.receiver cimport Receiver
from ..messages.utils cimport check_rc, check_ptr

cimport zmq.backend.cython.libzmq as libzmq
from libc.stdlib cimport free, malloc, realloc, calloc
from libc.string cimport memcpy
from libc.stdio cimport printf
from ..utils.clock cimport current_time
from .base cimport Worker

import threading
import zmq
import logging
import warnings
import struct as s

cdef class Client(Worker):
    
    def __init__(self, ctx, address, kind=zmq.SUB):
        super(Client, self).__init__(ctx, address)
        self.receiver = Receiver()
        self.counter = 0
        self.snail_deaths = 0
        self.maxlag = 10
        self.subscriptions = []
        self.kind = kind
        self._notify_address = "inproc://{:s}-notify".format(hex(id(self)))
    
    def subscribe(self, key):
        """Add a subscription key"""
        if self.kind == zmq.SUB:
            self.subscriptions.append(key)
        else:
            raise ValueError("Client is not a subscriber.")
        
    def _py_pre_work(self):
        """When work starts, allocate the first socket."""
        self._inbound = self.context.socket(self.kind)
        self.notify = self.context.socket(zmq.PUSH)
        
    def _py_pre_run(self):
        """On worker run, connect and subscribe."""
        self._inbound.connect(self.address)
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
        self._inbound.disconnect(self.address)
        self.log.debug("Ended 'RUN', accumulated {:d} snail deaths.".format(self.snail_deaths))
        
    def _py_post_work(self):
        """On worker done, close socket."""
        self._inbound.close()
        self._notify.close()
        
    cdef int _post_receive(self) nogil except -1:
        self.counter = self.counter + 1
        self.delay = current_time() - self.receiver.last_message
        if self.delay > self.maxlag:
            self._state = PAUSE
            self.snail_deaths = self.snail_deaths + 1
            return self.counter
        return 0
    
    cdef int _post_run(self) nogil except -1:
        return 0
    
    cdef int _pre_run(self) nogil except -1:
        return 0
    
    cdef int _run(self) nogil except -1:
        cdef void * inbound = self._inbound.handle
        cdef void * internal = self._internal.handle
        cdef void * notify = self.notify.handle
        cdef int sentinel
        cdef double delay = 0.0
        cdef libzmq.zmq_pollitem_t items[2]
        items[0].socket = inbound
        items[1].socket = internal
        items[0].events = libzmq.ZMQ_POLLIN
        items[1].events = libzmq.ZMQ_POLLIN
        self.counter = 0
        while True:
            rc = libzmq.zmq_poll(items, 2, self.timeout)
            check_rc(rc)
            if (items[1].revents & libzmq.ZMQ_POLLIN):
                rc = zmq_recv_sentinel(internal, &sentinel, 0)
                self._state = sentinel
                return self.counter
            elif (items[0].revents & libzmq.ZMQ_POLLIN):
                self.receiver._receive(inbound, 0, NULL)
                rc = self._post_receive()
                if rc != 0:
                    return rc
        
    def __getitem__(self, key):
        return self.receiver.__getitem__(key)
    
    def __len__(self):
        return self.receiver.__len__()

    def keys(self):
        return self.receiver.keys()
        