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
from ..messages.publisher cimport Publisher

cdef int server_callback(void * handle, short events, void * data, void * interrupt_handle) nogil except -1:
    cdef int rc = 0
    cdef int flags = 0
    rc = (<Server>data).publisher._publish(handle, flags)
    return rc

cdef class Server(SocketInfo):
    
    cdef readonly Publisher publisher
    
    def __cinit__(self):
        self.publisher = Publisher()
        self.callback = server_callback
    
    @classmethod
    def at_address(cls, str address, Context ctx, int kind = zmq.PUB):
        socket = ctx.socket(kind)
        socket.bind(address)
        return cls(socket, zmq.POLLIN)
    