from . cimport pthread

from libc.math cimport floor, fmod
from libc.stdlib cimport free, malloc, realloc

from posix.types cimport time_t
from .clock cimport current_utc_time, timespec
from .rc cimport check_generic_rc

cdef int event_trigger(event * src) nogil except -1:
    """Trigger the event without holding the GIL."""
    cdef int rc
    
    rc = pthread.pthread_mutex_lock(src.mutex)
    pthread.check_rc(rc)
    try:
        src._setting[0] = True
        rc = pthread.pthread_cond_broadcast(src.cond)
        pthread.check_rc(rc)
    finally:
        rc = pthread.pthread_mutex_unlock(src.mutex)
        pthread.check_rc(rc)
    return rc
    
cdef int event_incref(event * src) nogil except -1:
    cdef int rc, refcount
    rc = pthread.pthread_mutex_lock(src.mutex)
    pthread.check_rc(rc)
    refcount = src._refcount[0]
    src._refcount[0] = refcount + 1
    rc = pthread.pthread_mutex_unlock(src.mutex)
    pthread.check_rc(rc)
    return rc

cdef int event_clear(event * src) nogil except -1:
    """Clear an event, without the GIL."""
    rc = pthread.pthread_mutex_lock(src.mutex)
    pthread.check_rc(rc)
    try:
        src._setting[0] = False
    finally:
        rc = pthread.pthread_mutex_unlock(src.mutex)
        pthread.check_rc(rc)
    return rc
    
cdef int event_init(event * src) nogil except -1:
    """Initialize an empty event without holding the GIL"""
    cdef int rc
    src.mutex = <pthread.pthread_mutex_t *>realloc(src.mutex, sizeof(pthread.pthread_mutex_t))
    rc = pthread.pthread_mutex_init(src.mutex, NULL)
    pthread.check_rc(rc)
    
    src.cond = <pthread.pthread_cond_t *>realloc(src.cond, sizeof(pthread.pthread_cond_t))
    rc = pthread.pthread_cond_init(src.cond, NULL)
    pthread.check_rc(rc)
    
    src._setting = <bint *>realloc(src._setting, sizeof(bint))
    src._setting[0] = False
    src._refcount = <int *>realloc(src._refcount, sizeof(int))
    src._refcount[0] = 0
    return rc
    
cdef int event_destroy(event * src) nogil except -1:
    """Destroy an event structure"""
    cdef int rc, refcount
    if src.mutex is NULL:
        # Things are so boggled, we can't handle this case.
        return -2
    rc = pthread.pthread_mutex_lock(src.mutex)
    pthread.check_rc(rc)
    refcount = src._refcount[0]    
    if refcount == 0:
        rc = pthread.pthread_mutex_unlock(src.mutex)
        pthread.check_rc(rc)
        pthread.pthread_mutex_destroy(src.mutex)
        free(src.mutex)
        if src.cond is not NULL:
            pthread.pthread_cond_destroy(src.cond)
            free(src.cond)
        if src._setting is not NULL:
            free(src._setting)
    else:
        src._refcount[0] = refcount - 1
        rc = pthread.pthread_mutex_unlock(src.mutex)
        pthread.check_rc(rc)
    return 0

cdef class Event:
    """A cython implementation of a GIL-free Event object
    which should mimic the python event object."""
    
    def __cinit__(self):
        self._setting = <bint *>malloc(sizeof(bint))
        self._setting[0] = False
        self._refcount = <int *>malloc(sizeof(int))
        self._refcount[0] = 0
        
        self.mutex = <pthread.pthread_mutex_t *>malloc(sizeof(pthread.pthread_mutex_t))
        rc = pthread.pthread_mutex_init(self.mutex, NULL)
        pthread.check_rc(rc)
        self.cond = <pthread.pthread_cond_t *>malloc(sizeof(pthread.pthread_cond_t))
        rc = pthread.pthread_cond_init(self.cond, NULL)
        pthread.check_rc(rc)        
    
    def __dealloc__(self):
        self._destroy()
    
    cdef void _destroy(self) nogil:
        cdef int refcount
        if self.mutex is NULL:
            # State is so boggled, we'll throw away some meory.
            return
        pthread.pthread_mutex_lock(self.mutex)
        refcount = self._refcount[0]
        if refcount == 0:
            pthread.pthread_mutex_unlock(self.mutex)
            pthread.pthread_mutex_destroy(self.mutex)
            free(self.mutex)
            if self.cond is not NULL:
                pthread.pthread_cond_destroy(self.cond)
                free(self.cond)
            free(self._setting)
            free(self._refcount)
        else:
            self._refcount[0] = refcount - 1
            pthread.pthread_mutex_unlock(self.mutex)
    
    cdef event _get_event(self) nogil:
        cdef event evt
        evt._refcount = self._refcount
        evt.mutex = self.mutex
        evt.cond = self.cond
        evt._setting = self._setting
        event_incref(&evt)
        return evt
        
    @staticmethod
    cdef Event _from_event(event * evt):
        cdef Event obj = Event()
        obj._destroy()
        obj.mutex = evt.mutex
        obj.cond = evt.cond
        obj._setting = evt._setting
        obj._refcount = evt._refcount
        event_incref(evt)
        return obj
        
    def copy(self):
        """Copy this event by reference"""
        cdef event evt
        evt = self._get_event()
        obj = Event._from_event(&evt)
        event_destroy(&evt) # Decrements refcount.
        return obj
    
    cdef int lock(self) nogil except -1:
        cdef int rc
        rc = pthread.pthread_mutex_lock(self.mutex)
        pthread.check_rc(rc)
        return rc

    cdef int unlock(self) nogil except -1:
        cdef int rc
        rc = pthread.pthread_mutex_unlock(self.mutex)
        pthread.check_rc(rc)
        return rc
    
    property _reference_count:
        def __get__(self):
            self.lock()
            refcount = self._refcount[0]
            self.unlock()
            return refcount
    
    def clear(self):
        """Clear the event"""
        with nogil:
            self._clear()
    
    cdef int _clear(self) nogil except -1:
        cdef int rc
        rc = self.lock()
        try:
            self._setting[0] = False
        finally:
            rc = self.unlock()
        return rc
    
    def set(self):
        """Set the event"""
        with nogil:
            self._set()
    
    cdef int _set(self) nogil except -1:
        cdef int rc
        rc = self.lock()
        try:
            self._setting[0] = True
            rc = pthread.pthread_cond_broadcast(self.cond)
            pthread.check_rc(rc)
        finally:
            rc = self.unlock()
        return rc
        
    def wait(self, timeout = None):
        """Wait for the event to get set."""
        cdef double to
        if timeout is None:
            with nogil:
                self._wait()
        else:
            to = <double>timeout
            with nogil:
                self._timedwait(to)
        return bool(self._is_set())
        
    cdef int _wait(self) nogil except -1:
        cdef int rc
        rc = self.lock()
        try:
            if not self._setting[0]:
                rc = pthread.pthread_cond_wait(self.cond, self.mutex)
                pthread.check_rc(rc)
        finally:
            rc = self.unlock()
        return rc
    
    cdef int _timedwait(self, double seconds) nogil except -1:
        cdef int rc
        cdef timespec ts
        rc = self.lock()
        try:
            if not self._setting[0]:
                current_utc_time(&ts)
                ts.tv_sec += <time_t>floor(seconds)
                ts.tv_nsec += <long>floor(fmod(seconds,1)*1e9)
                rc = pthread.pthread_cond_timedwait(self.cond, self.mutex, &ts)
                pthread.check_rc(rc)
        finally:
            rc = self.unlock()
        return rc
    
    def is_set(self):
        cdef int rc
        with nogil:
            rc = self._is_set()
        return bool(rc)
    
    cdef int _is_set(self) nogil except -1:
        cdef int rc
        cdef int is_set = 0
        rc = self.lock()
        try:
            is_set = <int>self._setting[0]
        finally:
            rc = self.unlock()
        return is_set
    