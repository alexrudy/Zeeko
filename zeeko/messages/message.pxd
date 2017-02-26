# Internal cimports
from .carray cimport carray_named

# ZMQ cimports
cimport zmq.backend.cython.libzmq as libzmq
from zmq.backend.cython.message cimport Frame

cdef int zmq_msg_from_str(libzmq.zmq_msg_t * zmsg, char[:] src)
cdef str zmq_msg_to_str(libzmq.zmq_msg_t * msg)

cdef class ArrayMessage:
    
    cdef tuple _shape
    cdef object _dtype
    
    # Outbound array data references
    cdef bint _readonly
    cdef Frame _frame
    
    # Array message structure.
    cdef carray_named _message
    
    @staticmethod
    cdef ArrayMessage from_message(carray_named * message)
    
    cdef int update_info(self, unsigned long framecount) nogil except -1
    cdef int tick(self) nogil except -1