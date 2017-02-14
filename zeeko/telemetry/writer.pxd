# -----------------
# Cython imports

from ..utils.hmap cimport HashMap
from .chunk cimport array_chunk

cdef class Writer:
    
    cdef HashMap map
    cdef readonly size_t counter
    cdef array_chunk * _chunks

    cdef readonly int chunksize
    cdef readonly double last_message
    
    cdef public object file
    cdef object log
    cdef public object metadata_callback
    
    cdef int _release_arrays(self) nogil except -1
    cdef int _receive(self, void * socket, int flags, void * interrupt) nogil except -1
    cdef int _receive_chunk(self, void * socket, int flags, void * interrupt) nogil except -1

    