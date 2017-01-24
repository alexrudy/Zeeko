# Message tools for working with ZMQ
cimport zmq.backend.cython.libzmq as libzmq
from libc.stdlib cimport free, calloc, malloc, realloc
from libc.string cimport memcpy

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
    
def internal_address(self, *parts):
    """Construct an internal address for zmq."""
    protocol = 'inproc'
    return "{0:s}://{1:s}-{2:s}".format(protocol, hex(id(self)), "-".join(parts))