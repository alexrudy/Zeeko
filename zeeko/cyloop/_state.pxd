# State/Sentinels for ioloop
cimport zmq.backend.cython.libzmq as libzmq
from ..utils.msg cimport zmq_recv_sized_message
from ..utils.rc cimport check_zmq_rc

cdef enum zeeko_state:
    RUN=1
    PAUSE=2
    STOP=3
    INIT=4
    START=5
    
cdef inline int zmq_recv_sentinel(void * socket, int * dest, int flags) nogil except -1:
    return zmq_recv_sized_message(socket, dest, sizeof(int), flags)
    
cdef inline int zmq_send_sentinel(void * socket, int sentinel, int flags) nogil except -1:
    return check_zmq_rc(libzmq.zmq_sendbuf(socket, <void *>&sentinel, sizeof(int), flags))