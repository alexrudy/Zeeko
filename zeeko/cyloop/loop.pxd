cimport zmq.backend.cython.libzmq as libzmq
from zmq.backend.cython.socket cimport Socket
from zmq.backend.cython.context cimport Context

from ._state cimport StateMachine
from .throttle cimport Throttle
from ..utils.lock cimport Lock

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
    cdef readonly StateMachine state
    cdef readonly Throttle throttle
    
    cdef object log
    
    cdef Lock _lock # Lock
    
    cdef int _pause(self) nogil except -1
    cdef int _run(self) nogil except -1
    cdef int _check_pollitems(self, int n) except -1
