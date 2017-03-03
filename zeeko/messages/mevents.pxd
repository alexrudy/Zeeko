# An event container for Zeeko

# Cython Imports
# --------------
from ..utils.hmap cimport HashMap
from ..utils.condition cimport event

cdef class EventMap:
    cdef HashMap _map    
    
    cdef int _trigger_event(self, char * name, size_t sz) nogil except -1
    cdef event * _get_event(self, char * name, size_t sz) nogil except NULL