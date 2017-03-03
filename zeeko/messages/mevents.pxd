# An event container for Zeeko

# Cython Imports
# --------------
from ..utils.hmap cimport HashMap
from ..utils.condition cimport event

cdef class EventMap:
    cdef HashMap _map
    cdef event * _events
    
    cdef int _trigger_event(self, char * name, size_t sz) nogil except -1
    cdef int _get_event_index(self, char * name, size_t sz) nogil except -1
    cdef event * _get_event(self, char * name, size_t sz) nogil except NULL