# Events Map

# Cython Imports
# --------------
from libc.stdlib cimport free
from libc.string cimport memset

from ..utils.hmap cimport hashentry
from ..utils.condition cimport Event, event, event_init, event_trigger, event_destroy

# Python Imports
# --------------

from ..utils.sandwich import sandwich_unicode

cdef int dealloc_event(void * ptr, void * data) nogil except -1:
    return event_destroy(<event *>ptr)

cdef class EventMap:
    """A mapping of message events."""
    
    def __cinit__(self):
        self._map = HashMap(sizeof(event))
        self._map._dcb = dealloc_event
        
    def __dealloc__(self):
        self._map.clear()
    
    def event(self, name):
        """Return the event details"""
        cdef char[:] bname = bytearray(sandwich_unicode(name))
        return Event._from_event(self._get_event(&bname[0], len(bname)))
    
    cdef int _trigger_event(self, char * name, size_t sz) nogil except -1:
        return event_trigger(self._get_event(name, sz))
    
    cdef event * _get_event(self, char * name, size_t sz) nogil except NULL:
        cdef hashentry * h = self._map.get(name, sz)
        if h.vinit == 0:
            event_init(<event *>h.value)
            h.vinit = 1
        return <event *>h.value
    
    