"""
Receive arrays published by a publisher.
"""

import numpy as np
cimport numpy as np

np.import_array()

from .carray cimport carray_named

import zmq
from zmq.backend.cython.socket cimport Socket

cdef class ReceivedArray:
    
    cdef tuple _shape
    cdef object _dtype
    cdef carray_named _message
    
    @staticmethod
    cdef ReceivedArray from_message(carray_named * message)
    
cdef class Receiver:
    cdef int _n, _framecount

    