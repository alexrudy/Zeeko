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
from ..utils.lock cimport Lock
from ..utils.condition cimport Event, event
from .mevents cimport EventMap


cdef int zmq_recv_sized_message(void * socket, void * dest, size_t size, int flags) nogil except -1
cdef int receive_header(void * socket, libzmq.zmq_msg_t * topic, unsigned long * fc, int * nm, double * ts, int flags) nogil except -1

ctypedef struct msg_event:
    event evt
    unsigned long hash

cdef class Receiver:
    cdef int _n_messages
    cdef unsigned long _framecount
    cdef readonly double last_message
    cdef int _n_events
    cdef EventMap _events
    cdef carray_named ** _messages
    cdef unsigned long * _hashes
    cdef dict _name_cache
    cdef int _name_cache_valid
    cdef Lock lock
    cdef bint _failed_init
    
    cdef int reset(self) nogil except -1
    cdef int _build_namecache(self)
    cdef int get_message_index(self, libzmq.zmq_msg_t * name) nogil except -1
    cdef int _update_messages(self, int nm) nogil except -1
    cdef int _receive(self, void * socket, int flags, void * notify) nogil except -1
    cdef int _receive_unbundled(self, void * socket, int flags, void * notify) nogil except -1
    
