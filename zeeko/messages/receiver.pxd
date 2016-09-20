"""
Receive arrays published by a publisher.
"""

import numpy as np
cimport numpy as np

np.import_array()

from .carray cimport carray_named
import zmq
cimport zmq.backend.cython.libzmq as libzmq
from zmq.backend.cython.socket cimport Socket
from ..utils cimport pthread

cdef int zmq_recv_sized_message(void * socket, void * dest, size_t size, int flags) nogil except -1
cdef str zmq_msg_to_str(libzmq.zmq_msg_t * msg)
cdef int receive_header(void * socket, libzmq.zmq_msg_t * topic, unsigned int * fc, int * nm, double * ts, int flags) nogil except -1

cdef class ReceivedArray:
    
    cdef tuple _shape
    cdef object _dtype
    cdef carray_named _message
    
    @staticmethod
    cdef ReceivedArray from_message(carray_named * message)
    
cdef class Receiver:
    cdef int _n_messages
    cdef unsigned int _framecount
    cdef double last_message
    cdef carray_named ** _messages
    cdef unsigned long * _hashes
    cdef dict _name_cache
    cdef int _name_cache_valid
    cdef pthread.pthread_mutex_t _mutex
    cdef bint _failed_init
    
    cdef int lock(self) nogil except -1
    cdef int unlock(self) nogil except -1
    cdef int reset(self) nogil except -1
    cdef int _build_namecache(self)
    cdef int get_message_index(self, libzmq.zmq_msg_t * name) nogil except -1
    cdef int _update_messages(self, int nm) nogil except -1
    cdef int _receive(self, void * socket, int flags, void * notify) nogil except -1
    cdef int _receive_unbundled(self, void * socket, int flags, void * notify) nogil except -1
    

    