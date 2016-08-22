# Inline implementations of important ZMQ problems
cdef inline void check_rc(int rc) nogil:
    if rc == -1:
        with gil:
            from zmq.error import ZMQError
            raise ZMQError()

cdef inline void check_ptr(void * ptr) nogil:
    if ptr == NULL:
        with gil:
            from zmq.error import ZMQError
            raise ZMQError()
