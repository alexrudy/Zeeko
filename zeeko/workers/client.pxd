
from ..messages.receiver cimport Receiver
from zmq.backend.cython.socket cimport Socket
from zmq.backend.cython.context cimport Context

cdef enum zeeko_client_state:
    START=1
    PAUSE=2
    STOP=3

cdef class Client:
    cdef object thread
    cdef Receiver receiver
    cdef readonly Context context
    cdef Socket _internal
    cdef Socket _inbound
    cdef str address
    cdef str _internal_address
    cdef list subscriptions
    cdef readonly int counter
    cdef public long timeout
    cdef public long maxlag
    cdef readonly double delay
    cdef int _snail_deaths
    cdef int _state
    cdef object log
    
    cdef int _pause(self) nogil except -1
    cdef int _run(self) nogil except -1