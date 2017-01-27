
cimport zmq.backend.cython.libzmq as libzmq
from zmq.backend.cython.socket cimport Socket
from zmq.backend.cython.context cimport Context

import struct as s
import zmq

from ..utils.rc cimport check_zmq_rc
from ..utils.msg cimport zmq_init_recv_msg_t, zmq_recv_sized_message, zmq_recv_more
from ..utils.msg import internal_address
from ..utils.clock cimport current_time

from .base cimport SocketInfo
from .snail cimport Snail
from ..messages.receiver cimport Receiver

cdef int client_callback(void * handle, short events, void * data, void * interrupt_handle) nogil except -1:
    cdef int rc = 0
    cdef int flags = 0
    if (events & libzmq.ZMQ_POLLIN):
        rc = (<Client>data).receiver._receive(handle, flags, NULL)
        rc = (<Client>data).snail._check(interrupt_handle, (<Client>data).receiver.last_message)
    return rc

cdef class Client(SocketInfo):
    
    cdef readonly Receiver receiver
    cdef readonly Snail snail
    cdef str address
    cdef public bint use_reconnections
    
    def __cinit__(self):
        
        # Initialize basic client functions
        self.receiver = Receiver()
        self.callback = client_callback
        self.data = <void *>self
        
        # Delay management
        self.snail = Snail()
        self.address = ""
        self.use_reconnections = False
    
    def __init__(self, *args, **kwargs):
        super().__init__(self, *args, **kwargs)
        if self.socket.type == zmq.SUB:
            self.support_options()
    
    def enable_reconnections(self, str address not None):
        """Enable the reconnect/disconnect on pause."""
        self.address = address
        self.use_reconnections = True
    
    @classmethod
    def at_address(cls, str address, Context ctx, int kind = zmq.SUB, enable_reconnections=True):
        socket = ctx.socket(kind)
        socket.connect(address)
        obj = cls(socket, zmq.POLLIN)
        if enable_reconnections:
            obj.enable_reconnections(address)
        return obj
        
    cdef int paused(self) nogil except -1:
        """Function called when the loop has paused."""
        if not self.use_reconnections:
            return 0
        with gil:
            try:
                self.socket.disconnect(self.address)
            except zmq.ZMQError as e:
                if e.errno == zmq.ENOTCONN or e.errno == zmq.EAGAIN:
                    # Ignore errors that signal that we've already disconnected.
                    pass
                else:
                    raise
        return 0
    
    cdef int resumed(self) nogil except -1:
        """Function called when the loop is resumed."""
        if not self.use_reconnections:
            return 0
        with gil:
            try:
                self.socket.connect(self.address)
            except zmq.ZMQError as e:
                if e.errno == zmq.ENOTCONN or e.errno == zmq.EAGAIN:
                    # Ignore errors that signal that we've already disconnected.
                    pass
                else:
                    raise
        return 0
        
    def subscribe(self, key):
        """Subscribe"""
        self.opt.subscribe(key)
    
    def unsubscribe(self, key):
        """Unsubscribe"""
        self.opt.unsubscribe(key)
