"""
Definition of the array message structure.
"""

cimport zmq.backend.cython.libzmq as libzmq
from libc.time cimport time_t

ctypedef struct carray_message:
    libzmq.zmq_msg_t data
    libzmq.zmq_msg_t metadata
    libzmq.zmq_msg_t framecounter

ctypedef struct carray_named:
    carray_message array
    libzmq.zmq_msg_t name
    

cdef int new_array(carray_message * message) nogil except -1
cdef int new_named_array(carray_named * message) nogil except -1
cdef int empty_array(carray_message * message) nogil except -1
cdef int empty_named_array(carray_named * message) nogil except -1

cdef int close_array(carray_message * message) nogil except -1
cdef int close_named_array(carray_named * message) nogil except -1

cdef int copy_array(carray_message * dest, carray_message * src) nogil except -1
cdef int copy_named_array(carray_named * dest, carray_named * src) nogil except -1

cdef int send_array(carray_message * message, void * socket, int flags) nogil except -1
cdef int send_named_array(carray_named * msg, void * socket, int flags) nogil except -1
cdef int receive_array(carray_message * message, void * socket, int flags) nogil except -1
cdef int receive_named_array(carray_named * message, void * socket, int flags) nogil except -1