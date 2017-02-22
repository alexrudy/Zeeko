from . cimport pthread
from . cimport refcount

from libc.math cimport floor, fmod
from libc.stdlib cimport free
from libc cimport errno

from posix.types cimport time_t
from .clock cimport timespec, microseconds_to_ts
from .rc cimport check_generic_rc, realloc, malloc

class TimeoutError(Exception):
    pass

cdef int event_trigger(event * src) nogil except -1:
    """Trigger the event without holding the GIL."""
    cdef int rcl = 0, rcu = 0, rcc = 0
    rcl = pthread.pthread_mutex_lock(src.mutex)
    if rcl == 0:
        src._setting[0] = True
        rcc = pthread.pthread_cond_broadcast(src.cond)
        rcu = pthread.pthread_mutex_unlock(src.mutex)
    else:
        pthread.check_rc(rcl)
    pthread.check_rc(rcc)
    pthread.check_rc(rcu)
    return rcc
    
cdef int event_incref(event * src) nogil except -1:
    return refcount.refcount_increment(src.refcount)

cdef int event_clear(event * src) nogil except -1:
    """Clear an event, without the GIL."""
    rc = pthread.mutex_lock(src.mutex)
    src._setting[0] = False
    rc = pthread.mutex_unlock(src.mutex)
    return rc
    
cdef int event_init(event * src) nogil except -1:
    """Initialize an empty event without holding the GIL"""
    cdef int rc
    src.refcount = <refcount.refcount_t *>realloc(src.refcount, sizeof(refcount.refcount_t))
    rc = refcount.refcount_init(src.refcount)
    
    src.mutex = <pthread.pthread_mutex_t *>realloc(src.mutex, sizeof(pthread.pthread_mutex_t))
    rc = pthread.mutex_init(src.mutex, NULL)
    
    src.cond = <pthread.pthread_cond_t *>realloc(src.cond, sizeof(pthread.pthread_cond_t))
    rc = pthread.cond_init(src.cond, NULL)
    
    src._setting = <bint *>realloc(src._setting, sizeof(bint))
    src._setting[0] = False
    return rc
    
cdef int event_destroy(event * src) nogil except -1:
    """Destroy an event structure"""
    cdef int rc
    if src.refcount is NULL:
        # Things are so boggled, we can't handle this case.
        return -2
    rc = refcount.refcount_destroy(src.refcount)
    if rc == 1:
        free(src.refcount)
        src.refcount = NULL 
        if src.mutex is not NULL:
            pthread.mutex_destroy(src.mutex)
            free(src.mutex)
            src.mutex = NULL
        if src.cond is not NULL:
            pthread.cond_destroy(src.cond)
            free(src.cond)
            src.cond = NULL
        if src._setting is not NULL:
            free(src._setting)
            src._setting = NULL
    return 0

cdef int event_copy(event * dst, event * src) nogil except -1:
    dst.refcount = src.refcount
    dst._setting = src._setting
    dst.cond = src.cond
    dst.mutex = src.mutex
    event_incref(dst)
    return 0

cdef int event_timedwait(event * src, int timeout) nogil except -1:
    cdef timespec ts
    pthread.mutex_lock(src.mutex)
    ts = microseconds_to_ts(timeout)
    pthread.cond_timedwait(src.cond, src.mutex, &ts)
    return pthread.mutex_unlock(src.mutex)

cdef int event_wait(event * src) nogil except -1:
    pthread.mutex_lock(src.mutex)
    pthread.cond_wait(src.cond, src.mutex)
    return pthread.mutex_unlock(src.mutex)

cdef class Event:
    """A cython implementation of a GIL-free Event object
    which should mimic the python event object."""
    
    def __cinit__(self):
        event_init(&self.evt)
    
    def __dealloc__(self):
        self._destroy()
    
    cdef void _destroy(self) nogil:
        event_destroy(&self.evt)
    
    cdef event _get_event(self) nogil:
        cdef event evt
        event_copy(&evt, &self.evt)
        return evt
        
    @staticmethod
    cdef Event _from_event(event * evt):
        cdef Event obj = Event()
        obj._destroy()
        event_copy(&obj.evt, evt)
        return obj
        
    def copy(self):
        """Copy this event by reference"""
        cdef event evt
        evt = self._get_event()
        obj = Event._from_event(&evt)
        event_destroy(&evt) # Decrements refcount.
        return obj
    
    cdef int lock(self) nogil except -1:
        return pthread.mutex_lock(self.evt.mutex)

    cdef int unlock(self) nogil except -1:
        return pthread.mutex_unlock(self.evt.mutex)
    
    property _reference_count:
        def __get__(self):
            return refcount.refcount_get(self.evt.refcount)
    
    def clear(self):
        """Clear the event"""
        with nogil:
            self._clear()
    
    cdef int _clear(self) nogil except -1:
        cdef int rc = 0
        rc = self.lock()
        self.evt._setting[0] = False
        rc = self.unlock()
        return rc
    
    def set(self):
        """Set the event"""
        with nogil:
            self._set()
    
    cdef int _set(self) nogil except -1:
        cdef int _rc, rc = 0
        _rc = self.lock()
        self.evt._setting[0] = True
        rc = pthread.pthread_cond_broadcast(self.evt.cond)
        _rc = self.unlock()
        return pthread.check_rc(rc)
        
    def wait(self, timeout = None):
        """Wait for the event to get set."""
        cdef int to, rc
        if timeout is None:
            with nogil:
                self._wait()
        else:
            to = <int>((<double>timeout) * 100000.0)
            with nogil:
                rc = self._timedwait(to)
        return bool(self._is_set())
        
    cdef int _wait(self) nogil except -1:
        cdef int rc = 0, _rc
        _rc = self.lock()
        if not self.evt._setting[0]:
            rc = pthread.pthread_cond_wait(self.evt.cond, self.evt.mutex)
        _rc = self.unlock()
        return pthread.check_rc(rc)
    
    cdef int _timedwait(self, int microseconds) nogil except -1:
        cdef int rc = 0, _rc
        cdef timespec ts
        _rc = self.lock()
        if not self.evt._setting[0]:
            ts = microseconds_to_ts(microseconds)
            rc = pthread.pthread_cond_timedwait(self.evt.cond, self.evt.mutex, &ts)
        _rc = self.unlock()
        if errno.ETIMEDOUT == rc:
           return rc
           #with gil:
           #    raise TimeoutError("Event.wait() timed out.")
        return pthread.check_rc(rc)
    
    def is_set(self):
        cdef int rc
        with nogil:
            rc = self._is_set()
        return bool(rc)
    
    cdef int _is_set(self) nogil except -1:
        cdef int rc
        cdef int is_set = 0
        rc = self.lock()
        is_set = <int>self.evt._setting[0]
        rc = self.unlock()
        return is_set
    