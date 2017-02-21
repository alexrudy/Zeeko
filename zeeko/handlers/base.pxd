cimport zmq.backend.cython.libzmq as libzmq
from zmq.backend.cython.socket cimport Socket

from ..cyloop.throttle cimport Throttle

ctypedef int (*cyloop_callback)(void * handle, short events, void * data, void * interrupt_handle) nogil except -1

ctypedef struct socketinfo:
    cyloop_callback callback
    void * data
    
cdef class SocketInfo:
    
    cdef socketinfo info
    """Internal informational structure tracking this socket."""
    
    cdef bint _bound
    """Flag determines whether this SocketInfo is bound to a loop."""
    
    cdef readonly Socket socket
    """The wrapped ZeroMQ :class:`~zmq.Socket` from PyZMQ."""
    
    cdef readonly int events
    """The event mask used for polling this socket."""
    
    cdef cyloop_callback callback
    cdef void * data
    
    # Timing management
    cdef readonly Throttle throttle
    """A socket specific :class:`~zeeko.cyloop.throttle.Throttle` object"""
    
    # Spot for options management.
    cdef readonly object opt
    """The socket option manager, an instance of :class:`~zeeko.handlers.base.SocketOptions`"""
    
    cdef readonly object _loop
    """The :class:`~zeeko.cyloop.loop.IOLoop` object which manages this socket."""
    
    cdef int paused(self) nogil except -1    
    cdef int resumed(self) nogil except -1
    cdef int bind(self, libzmq.zmq_pollitem_t * pollitem) nogil except -1
    cdef int fire(self, libzmq.zmq_pollitem_t * pollitem, void * interrupt) nogil except -1
    cdef int _disconnect(self, str url) except -1
    cdef int _reconnect(self, str url) except -1

cdef class SocketOptions(SocketInfo):

    cdef readonly set subscriptions
    """The set of subscription keys."""
    
    cdef str address
    
    cdef public bint autosubscribe
    """Flag which tells the underlying socket to subscribe when it starts."""
    
    cdef Socket client

cdef class SocketMapping(SocketInfo):
    cdef object target

cdef class SocketMutableMapping(SocketMapping):
    pass