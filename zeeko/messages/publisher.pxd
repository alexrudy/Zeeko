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
from .utils cimport check_rc, check_ptr
from libc.string cimport strndup, memcpy

cdef int send_header(void * socket, libzmq.zmq_msg_t * topic, unsigned int fc, int nm, int flags) nogil except -1
cdef inline int zmq_msg_from_chars(libzmq.zmq_msg_t * message, char[:] data):
    """
    Initialize and fill a message from a bytearray.
    """
    cdef int rc
    rc = libzmq.zmq_msg_init_size(message, <size_t>len(data))
    check_rc(rc)
    memcpy(libzmq.zmq_msg_data(message), &data[0], libzmq.zmq_msg_size(message))
    return rc

cdef inline int zmq_msg_from_unsigned_int(libzmq.zmq_msg_t * message, unsigned int data) nogil except -1:
    """Set an unsigned int value."""
    cdef unsigned int * msg_buffer
    cdef size_t size = libzmq.zmq_msg_size(message)
    msg_buffer = <unsigned int *>libzmq.zmq_msg_data(message)
    check_ptr(msg_buffer)
    msg_buffer[0] = data
    return 0

cdef class Publisher:
    
    cdef int _n_messages, _framecount
    cdef carray_named ** _messages
    cdef pthread.pthread_mutex_t _mutex
    cdef libzmq.zmq_msg_t _infomessage
    cdef object _publishers
    cdef list _active_publishers
    cdef bint _failed_init
    
    
    cdef int lock(self) nogil except -1
    cdef int unlock(self) nogil except -1
    cdef int _update_messages(self) except -1
    cdef int _publish(self, void * socket, int flags) nogil except -1
    cdef int _set_framecounter_message(self, unsigned long framecount) nogil except -1

    