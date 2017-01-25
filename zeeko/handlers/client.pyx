
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
    
cdef int client_setsockopt(void * handle, short events, void * data, void * interrupt_handle) nogil except -1:
    cdef int rc = 0
    cdef int flags = 0
    cdef int sockopt = 0
    cdef void * client_socket = data
    cdef libzmq.zmq_msg_t zmessage
    if (events & libzmq.ZMQ_POLLIN):
        rc = zmq_recv_sized_message(handle, &sockopt, sizeof(int), flags)
        if zmq_recv_more(handle) == 1:
            rc = zmq_init_recv_msg_t(handle, flags, &zmessage)
            try:
                rc = check_zmq_rc(libzmq.zmq_setsockopt(client_socket, sockopt, 
                                                        libzmq.zmq_msg_data(&zmessage), 
                                                        libzmq.zmq_msg_size(&zmessage)))
            finally:
                rc = check_zmq_rc(libzmq.zmq_msg_close(&zmessage))
        else:
            #TODO Handle a malformed message here?
            pass
    return rc

def assert_socket_is_sub(socket, msg="Socket is not a ZMQ_SUB socket."):
    """Ensure a socket is a subscriber"""
    if socket.type != zmq.SUB:
        raise TypeError(msg)

cdef class _ClientSubscriber(SocketInfo):
    """A minimal class to handle subscriptions within the I/O Loop for client sockets."""
    
    def __cinit__(self):
        self.callback = client_setsockopt
    
    def _set_client_socket(self, Socket client_socket):
        self.data = client_socket.handle


cdef class Client(SocketInfo):
    
    cdef Context context
    cdef public bint autosubscribe
    cdef set subscriptions
    cdef _ClientSubscriber subscriber
    cdef str subscription_address
    cdef readonly Receiver receiver
    cdef readonly Snail snail
    
    def __cinit__(self):
        
        # Initialize basic client functions
        self.receiver = Receiver()
        self.callback = client_callback
        self.data = <void *>self
        
        # Subscription management.
        self.subscriptions = set()
        self.subscription_address = internal_address(self, 'client', 'subscriptions')
        self.autosubscribe = True
        
        # Delay management
        self.snail = Snail()
    
    def __init__(self, *args, **kwargs):
        super().__init__(self, *args, **kwargs)
        # Retain the context here for future use.
        self.context = self.socket.context
    
    @classmethod
    def at_address(cls, str address, Context ctx, int kind = zmq.SUB):
        socket = ctx.socket(kind)
        socket.connect(address)
        return cls(socket, zmq.POLLIN)
        
    def attach(self, ioloop):
        """Attach this object to an ioloop"""
        ioloop._add_socketinfo(self)
        if self.socket.type == zmq.SUB:
            subscription_socket = self.context.socket(zmq.PULL)
            subscription_socket.bind(self.subscription_address)
            self.subscriber = _ClientSubscriber(subscription_socket, zmq.POLLIN)
            self.subscriber._set_client_socket(self.socket)
            self.subscriber.check()
            ioloop._add_socketinfo(self.subscriber)
        
    def subscribe(self, str key):
        """Subscribe to a channel"""
        assert_socket_is_sub(self.socket)
        if key in self.subscriptions:
            return
        sink = self.context.socket(zmq.PUSH)
        try:
            self.subscriptions.add(key)
            sink.connect(self.subscription_address)
            sink.send(s.pack("i", zmq.SUBSCRIBE), flags=zmq.SNDMORE)
            sink.send(key)
        finally:
            sink.close(linger=10)
    
    def unsubscribe(self, str key):
        assert_socket_is_sub(self.socket)
        if key not in self.subscriptions:
            raise ValueError("Can't unsubscribe from {0:s}, not subscribed.".format(key))
        sink = self.context.socket(zmq.PUSH)
        try:
            sink.connect(self.subscription_address)
            sink.send(s.pack("i", zmq.UNSUBSCRIBE), flags=zmq.SNDMORE)
            sink.send(key)
            self.subscriptions.discard(key)
        finally:
            sink.close(linger=10)
        
    
    def _start(self):
        """Start the socket with subscriptions"""
        if self.socket.type == zmq.SUB:
            if len(self.subscriptions):
                for s in self.subscriptions:
                    if not isinstance(s, bytes):
                        s = s.encode("utf-8")
                    self.socket.subscribe(s)
            elif self.autosubscribe:
                self.subscriptions.add("")
                self.socket.subscribe("")