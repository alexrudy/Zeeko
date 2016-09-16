# Inline implementations of important ZMQ problems
cimport zmq.backend.cython.libzmq as libzmq
from zmq.error import _check_rc

cdef inline int check_rc(int rc) nogil except -1:
    if rc == -1:
        with gil:
            _check_rc(rc)
    return 0

cdef inline int check_ptr(void * ptr) nogil except -1:
    if ptr == NULL:
        with gil:
            from zmq.error import ZMQError
            raise ZMQError()
    return 0
