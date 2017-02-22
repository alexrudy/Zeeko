from . cimport pthread
from . cimport refcount

ctypedef struct event:
    refcount.refcount_t * refcount
    bint * _setting
    pthread.pthread_cond_t * cond
    pthread.pthread_mutex_t * mutex

cdef int event_trigger(event * src) nogil except -1    
cdef int event_init(event * src) nogil except -1
cdef int event_destroy(event * src) nogil except -1
cdef int event_clear(event * src) nogil except -1
cdef int event_copy(event * dst, event * src) nogil except -1
cdef int event_timedwait(event * src, long timeout) nogil except -1
cdef int event_wait(event * src) nogil except -1

cdef class Event:
    cdef event evt
    
    cdef void _destroy(self) nogil
    
    @staticmethod
    cdef Event _from_event(event * evt)
    
    cdef event _get_event(self) nogil
    cdef int _clear(self) nogil except -1
    cdef int _set(self) nogil except -1
    cdef int _wait(self) nogil except -1
    cdef int _timedwait(self, long microseconds) nogil except -1
    cdef int _is_set(self) nogil except -1
    cdef int lock(self) nogil except -1
    cdef int unlock(self) nogil except -1
    