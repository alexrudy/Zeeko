
from ..messages.receiver cimport Receiver, zmq_recv_sized_message
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
    'START': 1,
    'PAUSE': 2,
    'STOP': 3,
}

cdef inline int zmq_recv_sentinel(void * socket, int * dest, int flags) nogil except -1:
    return zmq_recv_sized_message(socket, dest, sizeof(int), flags)

cdef class Client:
    
    def __cinit__(self, Context ctx, str address):
        self.log = logging.getLogger(".".join([__name__,"Client"]))
        self.context = ctx or zmq.Context.instance()
        self.thread = threading.Thread(target=self._work)
        self.receiver = Receiver()
        self._inbound = ctx.socket(zmq.SUB)
        self._internal = ctx.socket(zmq.PULL)
        self.counter = 0
        self._snail_deaths = 0
        self.timeout = 10
        self.maxlag = 10
        self.address = address
        self._internal_address = ""
        self.subscriptions = []
        self._state = PAUSE
        
    def __init__(self, ctx, address):
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
        while True:
            self.log.debug("State transition: {:s}.".format(self.state))
            if self._state == START:
                
                self._inbound.connect(self.address)
                if len(self.subscriptions):
                    for s in self.subscriptions:
                        self._inbound.subscribe(s)
                else:
                    self._inbound.subscribe("")
                
                with nogil:
                    self._run()
                
                self._inbound.disconnect(self.address)
                self.log.debug("Ended _run, accumulated {:d} snail deaths.".format(self._snail_deaths))
            
            elif self._state == PAUSE:
                with nogil:
                    self._pause()
            
            elif self._state == STOP:
                break
        try:
            self._internal.disconnect(self._internal_address)
            self._internal.close()
            self._inbound.close()
        except zmq.ZMQError as e:
            self.log.warning("Exception in Client Shutdown: {!r}".format(e))
        
    cdef int _pause(self) nogil except -1:
        cdef void * internal = self._internal.handle
        cdef int sentinel
        cdef libzmq.zmq_pollitem_t items[1]
        items[0].socket = internal
        items[0].events = libzmq.ZMQ_POLLIN
        self.counter = 0
        while True:
            rc = libzmq.zmq_poll(items, 1, self.timeout)
            check_rc(rc)
            if (items[0].revents & libzmq.ZMQ_POLLIN):
                rc = zmq_recv_sentinel(internal, &sentinel, 0)
                self._state = sentinel
                return 0
            
        
        
    cdef int _run(self) nogil except -1:
        cdef void * inbound = self._inbound.handle
        cdef void * internal = self._internal.handle
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
                self.receiver._receive(inbound, 0)
                self.counter = self.counter + 1
                self.delay = current_time() - self.receiver.last_message
                if self.delay > self.maxlag:
                    self._state = PAUSE
                    self._snail_deaths = self._snail_deaths + 1
                    return self.counter
            
        
    def __getitem__(self, key):
        return self.receiver.__getitem__(key)
    
    def __len__(self):
        return self.receiver.__len__()

    def keys(self):
        return self.receiver.keys()
        
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
    