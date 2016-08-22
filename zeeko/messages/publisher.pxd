"""
Publish numpy arrays over ZeroMQ sockets.
"""
import numpy as np
cimport numpy as np

np.import_array()

from carray cimport carray_named
from ..utils cimport pthread


cdef class Publisher:
    
    cdef int _n_messages, _framecount
    cdef carray_named ** _messages
    cdef pthread.pthread_mutex_t _mutex
    
    cdef int lock(self) except -1
    cdef int unlock(self) except -1
    cdef int _update_messages(self) except -1
    cdef int _publish(self, void * socket, int flags) nogil except -1

cdef class PublishedArray:
    
    cdef np.ndarray _data
    cdef carray_named _message
    cdef char[:] _name
    cdef char[:] _metadata
    
    cdef void _update_message(self)
    