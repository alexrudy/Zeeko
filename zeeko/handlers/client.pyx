
cimport zmq.backend.cython.libzmq as libzmq
from zmq.backend.cython.socket cimport Socket
from zmq.backend.cython.context cimport Context

import zmq

from ..cyloop.loop cimport SocketInfo, socketinfo
from ..messages.receiver cimport Receiver

cdef int client_callback(void * handle, short events, void * data) nogil:
    cdef int rc, flags = 0
    rc = (<Receiver>data)._receive(handle, flags, NULL)
    with gil:
        print("Got it!")
    return rc

cdef class Client(SocketInfo):
    
    cdef list subscriptions
    cdef readonly Receiver receiver
    
    def __cinit__(self):
        self.subscriptions = []
        self.receiver = Receiver()
        self.info.callback = client_callback
        self.info.data = <void *>self.receiver
    
    @classmethod
    def at_address(cls, str address, Context ctx, int kind = zmq.SUB):
        socket = ctx.socket(kind)
        socket.connect(address)
        return cls(socket, zmq.POLLIN)
        
    def subscribe(self, str key):
        """Subscribe to a channel"""
        self.subscriptions.append(key)