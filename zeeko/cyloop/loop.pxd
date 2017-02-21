cimport zmq.backend.cython.libzmq as libzmq
from zmq.backend.cython.socket cimport Socket
from zmq.backend.cython.context cimport Context

from .statemachine cimport StateMachine
from .throttle cimport Throttle
from ..utils.lock cimport Lock

cdef class IOLoop:
    cdef list workers
    
    cdef readonly Context context
    """The :class:`~zmq.Context` object associated with this loop."""
    
    cdef readonly StateMachine state
    """The loop state manager, a :class:`~zeeko.cyloop.statemachine.StateMachine`."""
    
    cdef object log
    