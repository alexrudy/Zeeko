"""
Publish numpy arrays over ZeroMQ sockets.
"""
import numpy as np
cimport numpy as np

np.import_array()

from zmq.backend.cython.message cimport Frame
from carray cimport carray_named
from ..utils cimport pthread
cimport zmq.backend.cython.libzmq as libzmq

cdef int send_header(void * socket, libzmq.zmq_msg_t * topic, unsigned int fc, int nm, int flags) nogil except -1

cdef class Publisher:
    
    cdef int _n_messages, _framecount
    cdef carray_named ** _messages
    cdef pthread.pthread_mutex_t _mutex
    cdef libzmq.zmq_msg_t _topic
    cdef object _publishers
    cdef bint _failed_init
    cdef public bint bundled
    
    
    cdef int lock(self) nogil except -1
    cdef int unlock(self) nogil except -1
    cdef int _update_messages(self) except -1
    cdef int _publish(self, void * socket, int flags) nogil except -1

cdef class PublishedArray:
    
    cdef np.ndarray _data
    cdef carray_named _message
    cdef Frame _data_frame
    cdef char[:] _name
    cdef char[:] _metadata
    cdef bint _failed_init
    
    cdef int _update_message(self) except -1
    