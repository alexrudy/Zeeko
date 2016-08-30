from ..messages.receiver cimport zmq_recv_sized_message

cdef enum zeeko_state:
    RUN=1
    PAUSE=2
    STOP=3
    
cdef inline int zmq_recv_sentinel(void * socket, int * dest, int flags) nogil except -1:
    return zmq_recv_sized_message(socket, dest, sizeof(int), flags)