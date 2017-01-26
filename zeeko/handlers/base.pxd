cimport zmq.backend.cython.libzmq as libzmq
from zmq.backend.cython.socket cimport Socket

ctypedef int (*cyloop_callback)(void * handle, short events, void * data, void * interrupt_handle) nogil except -1

ctypedef struct socketinfo:
    cyloop_callback callback
    void * data
    
cdef class SocketInfo:
    
    cdef socketinfo info
    cdef readonly Socket socket
    cdef readonly int events
    cdef cyloop_callback callback
    cdef void * data
    cdef object opt
    
    cdef int bind(self, libzmq.zmq_pollitem_t * pollitem) nogil except -1
    cdef int fire(self, libzmq.zmq_pollitem_t * pollitem, void * interrupt) nogil except -1
    
cdef class SocketOptions(SocketInfo):

    cdef readonly set subscriptions
    cdef str address
    cdef public bint autosubscribe

    cdef Socket client