"""
Receive arrays published by a publisher.
"""

import numpy as np
cimport numpy as np

np.import_array()

from .carray cimport carray_named
from libc.time cimport time_t
import zmq
from zmq.backend.cython.socket cimport Socket

cdef class ReceivedArray:
    
    cdef tuple _shape
    cdef object _dtype
    cdef carray_named _message
    
    @staticmethod
    cdef ReceivedArray from_message(carray_named * message)
    
cdef class Receiver:
    cdef int _n_messages
    cdef unsigned int _framecount
    cdef time_t last_message
    cdef carray_named ** _messages
    cdef dict _name_cache
    cdef int _name_cache_valid
    
    cdef int _build_namecache(self)
    cdef int _update_messages(self, int nm) nogil except -1
    cdef int _receive(self, void * socket, int flags) nogil except -1

    