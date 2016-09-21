from . cimport pthread

ctypedef struct event:
    bint _own_pthread
    bint * _setting
    pthread.pthread_cond_t * cond
    pthread.pthread_mutex_t * mutex

cdef int event_trigger(event * src) nogil except -1    
cdef int event_init(event * src) nogil except -1
cdef int event_destroy(event * src) nogil except -1

cdef class Event:
    cdef bint * _setting
    cdef bint _own_pthread
    cdef pthread.pthread_mutex_t * mutex
    cdef pthread.pthread_cond_t * cond
    
    cdef void _destroy(self) nogil
    
    @staticmethod
    cdef Event _from_event(event * evt)
    
    cdef event _get_event(self) nogil
    cdef int _clear(self) nogil except -1
    cdef int _set(self) nogil except -1
    cdef int _wait(self) nogil except -1
    cdef int _timedwait(self, double seconds) nogil except -1
    cdef int _is_set(self) nogil except -1
    cdef int lock(self) nogil except -1
    cdef int unlock(self) nogil except -1
    