# -----------------
# Cython imports

from ..utils.hmap cimport HashMap
from ..utils.condition cimport Event, event
from ..messages.mevents cimport EventMap
from .chunk cimport array_chunk

# This class should match the API of the Receiver, but should return chunks
# instead of single messages.
cdef class Recorder:
    
    cdef HashMap map
    
    cdef size_t counter_at_done
    cdef readonly size_t counter
    """Number of messages received by the Recorder."""
    
    cdef EventMap _event_map
    
    cdef unsigned int _chunkcount
    cdef array_chunk * _chunks
    
    cdef readonly Event pushed
    """Event which is set once messages have been pushed to the writer."""
    
    cdef long offset
    cdef int _chunksize
    
    cdef readonly int framecount
    """Current frame counter value for recorded messages"""
    
    cdef readonly double last_message
    """Float timestamp for when the last message was sent."""
    
    cdef object log
    
    cdef int _release_arrays(self) nogil except -1
    cdef int _receive(self, void * socket, int flags, void * notify, int notify_flags) nogil except -1
    cdef int _receive_message(self, void * socket, int flags, void * notify, int notify_flags) nogil except -1
    cdef int _check_for_completion(self) nogil except -1
    cdef int _notify_partial_completion(self, void * socket, int flags) nogil except -1
    cdef int _notify_completion(self, void * socket, int flags) nogil except -1
    cdef int _notify_close(self, void * socket, int flags) nogil except -1
    cdef void _log_state(self) nogil
