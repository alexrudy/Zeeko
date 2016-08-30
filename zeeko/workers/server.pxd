
from ..messages.publisher cimport Publisher
from zmq.backend.cython.socket cimport Socket
from zmq.backend.cython.context cimport Context
from .state cimport *
from .base cimport Worker

cdef class Server(Worker):
    cdef Publisher publisher
    cdef Socket _outbound
    cdef readonly int counter
    cdef readonly double wait_time
    cdef double interval
    cdef double last_message
    