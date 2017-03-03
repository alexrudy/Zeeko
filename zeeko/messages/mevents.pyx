# Events Map

# Cython Imports
# --------------
from libc.stdlib cimport free
from libc.string cimport memset

from ..utils.condition cimport Event, event_init, event_trigger, event_destroy

# Python Imports
# --------------

from ..utils.sandwich import sandwich_unicode

cdef class EventMap:
    """A mapping of message events."""
    
    def __cinit__(self):
        self._map = HashMap()
        self._events = NULL
        
    def __dealloc__(self):
        cdef int i
        if not (self._events == NULL):
            for i in range(len(self._map)):
                event_destroy(&self._events[i])
            free(self._events)
    
    def event(self, name):
        """Return the event details"""
        cdef char[:] bname = bytearray(sandwich_unicode(name))
        return Event._from_event(self._get_event(&bname[0], len(bname)))
    
    cdef int _trigger_event(self, char * name, size_t sz) nogil except -1:
        cdef int i
        i = self._get_event_index(name, sz)
        event_trigger(&self._events[i])
        return i
    
    cdef event * _get_event(self, char * name, size_t sz) nogil except NULL:
        cdef int i, rc
        i = self._get_event_index(name, sz)
        return &self._events[i]
    
    cdef int _get_event_index(self, char * name, size_t sz) nogil except -1:
        cdef int i, rc
        i = self._map.get(name, sz)
        if i == -1:
            i = self._map.insert(name, sz)
            self._events = <event *>self._map.reallocate(self._events, sizeof(event))
            memset(&self._events[i], 0, sizeof(event))
            rc = event_init(&self._events[i])
        return i
    