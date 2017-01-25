cimport zmq.backend.cython.libzmq as libzmq
from zmq.backend.cython.socket cimport Socket
from zmq.backend.cython.context cimport Context
from ..utils.lock cimport Lock
from ..utils.condition cimport Event
from ._state cimport *

ctypedef int (*cyloop_callback)(void * handle, short events, void * data, void * interrupt_handle) nogil except -1

ctypedef struct socketinfo:
    cyloop_callback callback
    void * data
    
cdef class SocketInfo:
    
    cdef socketinfo info
    cdef readonly Socket socket
    cdef readonly int events
    cdef cyloop_callback callback
    cdef void * data
    
    cdef int bind(self, libzmq.zmq_pollitem_t * pollitem) nogil except -1
    cdef int fire(self, libzmq.zmq_pollitem_t * pollitem, void * interrupt) nogil except -1
    
cdef class Throttle:
    
    cdef bint active
    cdef double _last_event
    cdef readonly double period
    cdef public double timeout
    cdef double _wait_time
    cdef public double gain
    cdef public double leak
    
    cdef int reset(self) nogil
    cdef int mark(self) nogil except -1
    cdef long get_timeout(self) nogil

cdef class IOLoop:
    cdef object thread
    cdef readonly Context context
    
    cdef Socket _internal
    cdef readonly Socket _interrupt
    cdef void * _interrupt_handle
    
    cdef str _internal_address_interrupt
    
    cdef list _sockets
    
    cdef void ** _socketinfos
    
    cdef libzmq.zmq_pollitem_t * _pollitems
    cdef int _n_pollitems
    
    cdef public long timeout
    cdef public double mintime
    cdef StateMachine _state
    cdef Throttle throttle
    
    cdef object log
    
    cdef Lock _lock # Lock
    
    cdef int _pause(self) nogil except -1
    cdef int _run(self) nogil except -1
    cdef int _check_pollitems(self, int n) except -1
