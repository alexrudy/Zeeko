
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
    
    def __cinit__(self):
        
        # Initialize basic client functions
        self.receiver = Receiver()
        self.callback = client_callback
        self.data = <void *>self
        
        # Delay management
        self.snail = Snail()
    
    def __init__(self, *args, **kwargs):
        super().__init__(self, *args, **kwargs)
        # Retain the context here for future use.
        if self.socket.type == zmq.SUB:
            self.support_options()
        
    
    @classmethod
    def at_address(cls, str address, Context ctx, int kind = zmq.SUB):
        socket = ctx.socket(kind)
        socket.connect(address)
        return cls(socket, zmq.POLLIN)
        
    def subscribe(self, key):
        """Subscribe"""
        self.opt.subscribe(key)
    
    def unsubscribe(self, key):
        """Unsubscribe"""
        self.opt.unsubscribe(key)
