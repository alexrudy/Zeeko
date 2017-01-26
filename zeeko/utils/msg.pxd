# Message tools for working with ZMQ
cimport zmq.backend.cython.libzmq as libzmq
from .rc cimport check_zmq_rc, check_memory_ptr


cdef int zmq_recv_sized_message(void * socket, void * dest, size_t size, int flags) nogil except -1
cdef int zmq_init_recv_msg_t(void * socket, int flags, libzmq.zmq_msg_t * zmessage) nogil except -1
cdef libzmq.zmq_msg_t * zmq_recv_new_msg_t(void * socket, int flags) nogil except NULL
cdef object zmq_convert_sockopt(int option, libzmq.zmq_msg_t * message)

cdef inline int zmq_recv_more(void * socket) nogil except -1:
    cdef int rc, value
    cdef size_t optsize = sizeof(int)
    rc = check_zmq_rc(libzmq.zmq_getsockopt(socket, libzmq.ZMQ_RCVMORE, &value, &optsize))
    return value