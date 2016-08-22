"""
Definition of the array message structure.
"""

from libc.time cimport time_t

ctypedef struct carray_message:
    size_t n, nm
    void * data
    char * metadata

ctypedef struct carray_named:
    carray_message array
    char * name
    size_t nm
    

cdef int send_array(void * socket, carray_message * message, int flags) nogil except -1
cdef int send_named_array(void * socket, carray_named * msg, int flags) nogil except -1
cdef int receive_array(void * socket, carray_message * message, int flags) nogil except -1
cdef int receive_named_array(void * socket, carray_named * message, int flags) nogil except -1