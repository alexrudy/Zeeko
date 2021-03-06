# State/Sentinels for ioloop
cimport zmq.backend.cython.libzmq as libzmq
from ..utils.msg cimport zmq_recv_sized_message
from ..utils.rc cimport check_zmq_rc
from ..utils.lock cimport Lock
from ..utils.condition cimport event

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
    
cdef class StateMachine:

    cdef long _state
    cdef int _n
    cdef Lock _lock
    cdef dict _name_to_long
    cdef dict _long_to_name
    cdef dict _long_to_event

    cdef long * _event_to_long
    cdef event * _select_events
    cdef event * _deselect_events
    
    cdef int _event_index(self, long state) nogil except -1
    cdef int set(self, long state) nogil except -1
    cdef bint check(self, long state) nogil
    cdef int sentinel(self, libzmq.zmq_pollitem_t * pollitem) nogil except -1