# Message tools for working with ZMQ
cimport zmq.backend.cython.libzmq as libzmq
from libc.stdlib cimport free, calloc, malloc, realloc
from libc.string cimport memcpy

from cpython cimport PyBytes_FromStringAndSize
import zmq

cdef int zmq_recv_sized_message(void * socket, void * dest, size_t size, int flags) nogil except -1:
    cdef int rc = 0
    cdef libzmq.zmq_msg_t zmessage
    cdef size_t zsize
    rc = check_zmq_rc(libzmq.zmq_msg_init(&zmessage))
    try:
        rc = check_zmq_rc(libzmq.zmq_msg_recv(&zmessage, socket, flags))
        zsize = libzmq.zmq_msg_size(&zmessage)
        if zsize < size:
            size = zsize
        memcpy(dest, libzmq.zmq_msg_data(&zmessage), size)
    finally:
        rc = check_zmq_rc(libzmq.zmq_msg_close(&zmessage))
    return rc
    
cdef int zmq_init_recv_msg_t(void * socket, int flags, libzmq.zmq_msg_t * zmessage) nogil except -1:
    cdef int rc = 0
    rc = check_zmq_rc(libzmq.zmq_msg_init(zmessage))
    rc = check_zmq_rc(libzmq.zmq_msg_recv(zmessage, socket, flags))
    return rc
    
cdef libzmq.zmq_msg_t * zmq_recv_new_msg_t(void * socket, int flags) nogil except NULL:
    cdef libzmq.zmq_msg_t * zmessage
    zmessage = <libzmq.zmq_msg_t *>check_memory_ptr(calloc(1, sizeof(libzmq.zmq_msg_t)))
    rc = zmq_init_recv_msg_t(socket, flags, zmessage)
    return zmessage
    
cdef object zmq_convert_sockopt(int option, libzmq.zmq_msg_t * message):
    cdef libzmq.int64_t optval_int64_c
    cdef int optval_int_c
    cdef libzmq.fd_t optval_fd_c
    cdef char * identity_str_c
    cdef size_t sz
    cdef int rc
    
    if option in zmq.constants.bytes_sockopts:
        sz = libzmq.zmq_msg_size(message)
        identity_str_c = <char *>libzmq.zmq_msg_data(message)
        # strip null-terminated strings *except* identity
        if option != libzmq.ZMQ_IDENTITY and sz > 0 and (<char *>identity_str_c)[sz-1] == b'\0':
            sz -= 1
        result = PyBytes_FromStringAndSize(<char *>identity_str_c, sz)
    elif option in zmq.constants.int64_sockopts:
        sz = sizeof(libzmq.int64_t)
        memcpy(<void *>&optval_int64_c, libzmq.zmq_msg_data(message), sz)
        result = optval_int64_c
    elif option in zmq.constants.fd_sockopts:
        sz = sizeof(libzmq.fd_t)
        memcpy(<void *>&optval_fd_c, libzmq.zmq_msg_data(message), sz)
        result = optval_fd_c
    else:
        # default is to assume int, which is what most new sockopts will be
        # this lets pyzmq work with newer libzmq which may add constants
        # pyzmq has not yet added, rather than artificially raising. Invalid
        # sockopts will still raise just the same, but it will be libzmq doing
        # the raising.
        sz = sizeof(int)
        memcpy(<void *>&optval_int_c, libzmq.zmq_msg_data(message), sz)
        result = optval_int_c
    return result
    
def internal_address(self, *parts):
    """Construct an internal address for zmq."""
    protocol = 'inproc'
    return "{0:s}://{1:s}-{2:s}".format(protocol, hex(id(self)), "-".join(parts))