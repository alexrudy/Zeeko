cimport zmq.backend.cython.libzmq as libzmq
from zmq.backend.cython.socket cimport Socket
from zmq.backend.cython.context cimport Context
from ..utils.lock cimport Lock
from ..utils.condition cimport Event
from .state cimport *

ctypedef int (*cyloop_callback)(void * handle, short events, void * data) nogil

ctypedef struct socketinfo:
    void * handle
    short events
    cyloop_callback callback
    void * data
    
cdef class SocketInfo:
    
    cdef socketinfo info
    cdef Socket socket

cdef class IOLoop:
    cdef object thread
    cdef readonly Context context
    
    cdef Socket _internal
    cdef Socket _notify
    
    cdef str _internal_address_interrupt
    cdef str _internal_address_notify
    
    cdef list _sockets
    
    cdef socketinfo ** _socketinfos
    cdef libzmq.zmq_pollitem_t * _pollitems
    cdef int _n_pollitems
    
    cdef public long timeout
    cdef int _state
    
    cdef object log
    
    cdef Event _ready # Ready event from threading.
    cdef Lock _lock # Lock
    
    cdef int _pause(self) nogil except -1
    cdef int _run(self) nogil except -1
    cdef int _wait(self, double waittime) nogil except -1
    
    
