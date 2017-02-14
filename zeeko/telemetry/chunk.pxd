
cimport numpy as np
from libc.string cimport memcpy
cimport zmq.backend.cython.libzmq as libzmq
from zmq.backend.cython.message cimport Frame

from ..messages.carray cimport carray_named

ctypedef np.int32_t DINT_t

ctypedef struct array_chunk:
    size_t chunksize
    size_t stride
    size_t last_index
    libzmq.zmq_msg_t mask
    libzmq.zmq_msg_t data
    libzmq.zmq_msg_t metadata
    libzmq.zmq_msg_t name

cdef int chunk_init(array_chunk * chunk) nogil except -1
cdef int chunk_init_array(array_chunk * chunk, carray_named * array, size_t chunksize) nogil except -1
cdef int chunk_copy(array_chunk * dest, array_chunk * src) nogil except -1
cdef int chunk_append(array_chunk * chunk, carray_named * array, size_t index) nogil except -1
cdef int chunk_send(array_chunk * chunk, void * socket, int flags) nogil except -1
cdef int chunk_recv(array_chunk * chunk, void * socket, int flags) nogil except -1
cdef int chunk_close(array_chunk * chunk) nogil except -1

cdef class Chunk:
    
    cdef array_chunk _chunk
    cdef tuple _shape
    cdef object _dtype
    cdef str _name
    cdef Frame _data_frame
    cdef Frame _mask_frame
    
    @staticmethod
    cdef Chunk from_chunk(array_chunk * chunk)


