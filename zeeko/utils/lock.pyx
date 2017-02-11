from . cimport pthread
from .rc cimport malloc, realloc
from libc.stdlib cimport free
from libc.string cimport memset
from .clock cimport current_utc_time, timespec

from posix.types cimport time_t

cdef int lock_acquire(lock * src) nogil except -1:
    """Acquire the lock without holding the GIL."""
    cdef int rc
    rc = pthread.mutex_lock(src.mutex)
    try:
        if src._owned[0]:
            pthread.pthread_cond_wait(src.condition, src.mutex)
        src._owned[0] = 1
    finally:
        rc = pthread.mutex_unlock(src.mutex)
    return rc
    
cdef int lock_release(lock * src) nogil except -1:
    """Release the lock."""
    cdef int rc
    rc = pthread.mutex_lock(src.mutex)
    try:
        src._owned[0] = 0
        rc = pthread.check_rc(pthread.pthread_cond_signal(src.condition))
    finally:
        rc = pthread.mutex_unlock(src.mutex)
    return rc

cdef int lock_init(lock * src) nogil except -1:
    """Initialize the lock structure"""
    cdef int rc
    src.refcount = <refcount.refcount_t *>realloc(src.refcount, sizeof(refcount.refcount_t))
    rc = refcount.refcount_init(src.refcount)
    
    src._owned = <bint *>realloc(src._owned, sizeof(bint))
    src._owned[0] = 0
    src.mutex = <pthread.pthread_mutex_t *>realloc(src.mutex, sizeof(pthread.pthread_mutex_t))
    rc = pthread.mutex_init(src.mutex, NULL)
    src.condition = <pthread.pthread_cond_t *>realloc(src.condition, sizeof(pthread.pthread_cond_t))
    rc = pthread.check_rc(pthread.pthread_cond_init(src.condition, NULL))
    return rc
    

cdef int lock_destroy(lock * src) nogil except -1:
    """Destroy an event structure"""
    cdef int rc
    if src.refcount is NULL:
        # Things are so boggled, we can't handle this case.
        return -2
    rc = refcount.refcount_destroy(src.refcount)
    if rc == 1:
        if src.mutex is not NULL:
            pthread.mutex_destroy(src.mutex)
            free(src.mutex)
        if src.condition is not NULL:
            pthread.pthread_cond_destroy(src.condition)
            free(src.condition)
        if src._owned is not NULL:
            free(src._owned)
    return rc

cdef class Lock:
    """A cython implementation of a GIL-free Lock object
    which should mimic the python lock object."""
    
    def __cinit__(self):
        cdef int rc
        memset(&self._lock, 0, sizeof(lock))
        rc = lock_init(&self._lock)
        assert self._lock.mutex is not NULL, "mutex was not initialized."
        assert self._lock.condition is not NULL, "condition was not initialized."
    
    def __dealloc__(self):
        self._destroy()
    
    cdef void _destroy(self) nogil:
        lock_destroy(&self._lock)
    
    cdef lock _get_lock(self) nogil:
        cdef lock lck
        lck.refcount = self._lock.refcount
        lck._owned = self._lock._owned
        lck.mutex = self._lock.mutex
        lck.condition = self._lock.condition
        refcount.refcount_increment(lck.refcount)
        return lck
        
    @staticmethod
    cdef Lock _from_lock(lock * lck):
        cdef Lock obj = Lock()
        obj._destroy()
        obj._lock.refcount = lck.refcount
        obj._lock.mutex = lck.mutex
        obj._lock._owned = lck._owned
        obj._lock.condition = lck.condition
        refcount.refcount_increment(obj._lock.refcount)
        return obj
        
    property locked:
        def __get__(self):
            cdef bint _locked
            assert self._lock.mutex is not NULL, "mutex was not initialized."
            rc = pthread.mutex_lock(self._lock.mutex)
            try:
                _locked = self._lock._owned[0]
            finally:
                rc = pthread.mutex_unlock(self._lock.mutex)
            return _locked
        
    def copy(self):
        """Copy this event by reference"""
        cdef lock lck
        lck = self._get_lock()
        return Lock._from_lock(&lck)
    
    cdef int _acquire(self) nogil except -1:
        cdef int rc
        return lock_acquire(&self._lock)
        
    def acquire(self):
        """Acquire the lock"""
        with nogil:
            self._acquire()

    cdef int _release(self) nogil except -1:
        cdef int rc
        return lock_release(&self._lock)
        
    def release(self):
        """Release the lock"""
        with nogil:
            self._release()
            
    def __enter__(self):
        self.acquire()
        return
    
    def __exit__(self, t, v, tb):
        self.release()
        return
