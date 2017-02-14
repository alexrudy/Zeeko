cimport zmq.backend.cython.libzmq as libzmq
from zmq.backend.cython.socket cimport Socket
from zmq.backend.cython.context cimport Context

from .statemachine cimport StateMachine
from .throttle cimport Throttle
from ..utils.lock cimport Lock

cdef class IOLoop:
    cdef list workers
    cdef readonly Context context
    
    cdef readonly StateMachine state
    cdef readonly Throttle throttle
    
    cdef object log
    