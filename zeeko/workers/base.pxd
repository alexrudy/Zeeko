
from zmq.backend.cython.socket cimport Socket
from zmq.backend.cython.context cimport Context
from .state cimport *

cdef class Worker:
    cdef object thread
    cdef readonly Context context
    cdef Socket _internal
    cdef readonly str address
    cdef str _internal_address
    cdef public long timeout
    cdef int _state
    cdef object log
    
    cdef int _pause(self) nogil except -1
    cdef int _run(self) nogil except -1
    cdef int _wait(self, double waittime) nogil except -1
    
    # These are hook-functions for cython subclasses.
    cdef int _post_receive(self) nogil except -1    
    cdef int _post_run(self) nogil except -1
    cdef int _pre_run(self) nogil except -1
