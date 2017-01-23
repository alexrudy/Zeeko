# Inline implementations of important ZMQ problems
cimport zmq.backend.cython.libzmq as libzmq
from cpython cimport PyExc_OSError, PyErr_SetFromErrno

cdef inline int check_zmq_rc(int rc) nogil except -1:
    if rc == -1:
        with gil:
            from zmq.error import _check_rc
            _check_rc(rc)
    return 0

cdef inline int check_zmq_ptr(void * ptr) nogil except -1:
    if ptr == NULL:
        with gil:
            from zmq.error import ZMQError
            raise ZMQError()
    return 0
    
cdef inline int check_generic_ptr(void *ptr) nogil except -1:
    if ptr == NULL:
        with gil:
            PyErr_SetFromErrno(PyExc_OSError)
            return -1
    return 0

cdef inline int check_generic_rc(int rc) nogil except -1:
    if rc == -1:
        with gil:
            PyErr_SetFromErrno(PyExc_OSError)
            return -1
    return 0

