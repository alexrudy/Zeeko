
from ..messages.publisher cimport Publisher
from zmq.backend.cython.socket cimport Socket
from zmq.backend.cython.context cimport Context
from .state cimport *

cdef class Server:
    cdef object thread
    cdef Publisher publisher
    cdef readonly Context context
    cdef Socket _internal
    cdef Socket _outbound
    cdef str address
    cdef str _internal_address
    cdef list subscriptions
    cdef readonly int counter
    cdef readonly double wait_time
    cdef public long timeout
    cdef double interval
    cdef double last_message
    cdef int _state
    cdef object log
    cdef str _last_state
    
    cdef int _pause(self) nogil except -1
    cdef int _run(self) nogil except -1
    cdef int _wait(self, long waittime) nogil except -1