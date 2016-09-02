
from ..messages.receiver cimport Receiver
from zmq.backend.cython.socket cimport Socket
from .state cimport *
from .base cimport Worker

cdef class Client(Worker):
    cdef Receiver receiver
    cdef Socket _inbound
    cdef list subscriptions
    cdef readonly int counter
    cdef public double maxlag
    cdef readonly double delay
    cdef int _snail_deaths
    cdef int kind
    
