# -----------------
# Cython imports

from ..utils.hmap cimport HashMap
from ..utils.condition cimport Event
from .chunk cimport array_chunk


# This class should match the API of the Receiver, but should return chunks
# instead of single messages.
cdef class Recorder:
    
    cdef HashMap map
    cdef readonly size_t counter
    cdef unsigned int _chunkcount
    cdef array_chunk * _chunks
    
    cdef readonly Event pushed
    """Event which is set once messages have been pushed to the writer."""
    
    cdef long offset
    cdef readonly int chunksize
    cdef readonly double last_message
    
    cdef object log
    
    cdef int _release_arrays(self) nogil except -1
    cdef int _receive(self, void * socket, int flags, void * notify, int notify_flags) nogil except -1
    cdef int _receive_message(self, void * socket, int flags, void * notify, int notify_flags) nogil except -1
    cdef int _check_for_completion(self) nogil except -1
    cdef int _notify_completion(self, void * socket, int flags) nogil except -1
    cdef int _notify_close(self, void * socket, int flags) nogil except -1
