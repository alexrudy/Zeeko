# Message tools for working with ZMQ
cimport zmq.backend.cython.libzmq as libzmq
from .rc cimport check_zmq_rc
from libc.stdlib cimport free, malloc, realloc
from libc.string cimport memcpy

cdef inline int zmq_recv_sized_message(void * socket, void * dest, size_t size, int flags) nogil except -1:
    cdef int rc = 0
    cdef libzmq.zmq_msg_t zmessage
    rc = check_zmq_rc(libzmq.zmq_msg_init(&zmessage))
    try:
        rc = check_zmq_rc(libzmq.zmq_msg_recv(&zmessage, socket, flags))
        memcpy(dest, libzmq.zmq_msg_data(&zmessage), size)
    finally:
        rc = check_zmq_rc(libzmq.zmq_msg_close(&zmessage))
    return rc