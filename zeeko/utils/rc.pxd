# Inline implementations of important ZMQ problems
cimport zmq.backend.cython.libzmq as libzmq
from cpython.exc cimport PyErr_SetFromErrno

cdef inline int check_zmq_rc(int rc) nogil except -1:
    if rc == -1:
        with gil:
            from zmq.error import _check_rc
            _check_rc(rc)
    return rc

cdef inline void * check_zmq_ptr(void * ptr) nogil except NULL:
    if ptr == NULL:
        with gil:
            from zmq.error import ZMQError
            raise ZMQError()
    return ptr
    
cdef inline void * check_generic_ptr(void *ptr) nogil except NULL:
    if ptr == NULL:
        with gil:
            PyErr_SetFromErrno(OSError)
            return NULL
    return ptr

cdef inline void * check_memory_ptr(void * ptr) nogil except NULL:
    if ptr == NULL:
        with gil:
            raise MemoryError()
    return ptr

cdef inline int check_generic_rc(int rc) nogil except -1:
    if rc == -1:
        with gil:
            PyErr_SetFromErrno(OSError)
            return -1
    return rc

