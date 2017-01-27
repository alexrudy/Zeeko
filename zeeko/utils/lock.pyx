from . cimport pthread

from libc.stdlib cimport free, malloc, realloc

from posix.types cimport time_t
from .clock cimport current_utc_time, timespec

# Internal pthread functions.
cdef inline int pthread_mutex_alloc_init(pthread.pthread_mutex_t * mutex) nogil except -1:
    """Initialize and allocate a single mutex"""
    cdef int rc
    mutex = <pthread.pthread_mutex_t *>realloc(mutex, sizeof(pthread.pthread_mutex_t))
    rc = pthread.pthread_mutex_init(mutex, NULL)
    pthread.check_rc(rc)
    return rc

cdef inline int pthread_mutex_release(pthread.pthread_mutex_t * mutex) nogil except -1:
    """Release a mutex"""
    cdef int rc
    rc = pthread.pthread_mutex_unlock(mutex)
    pthread.check_rc(rc)
    return rc
    
cdef inline int pthread_mutex_acquire(pthread.pthread_mutex_t * mutex) nogil except -1:
    """Acquire a mutex"""
    cdef int rc
    rc = pthread.pthread_mutex_lock(mutex)
    pthread.check_rc(rc)
    return rc

cdef int lock_acquire(lock * src) nogil except -1:
    """Acquire the lock without holding the GIL."""
    cdef int rc
    rc = pthread_mutex_acquire(src._internal)
    try:
        if src._owned[0]:
            with gil:
                raise ValueError("Can't acquire lock")
        src._owned[0] = 1
        rc = pthread_mutex_acquire(src.mutex)
    finally:
        rc = pthread_mutex_release(src._internal)
    return rc
    
cdef int lock_release(lock * src) nogil except -1:
    """Release the lock."""
    cdef int rc
    rc = pthread_mutex_acquire(src._internal)
    try:
        rc = pthread_mutex_release(src.mutex)
        src._owned[0] = 0
    finally:
        rc = pthread_mutex_release(src._internal)
    return rc

cdef int lock_init(lock * src) nogil except -1:
    """Initialize the lock structure"""
    cdef int rc
    src._own_pthread = True
    src._owned = <bint *>realloc(src._owned, sizeof(bint))
    
    rc = pthread_mutex_alloc_init(src.mutex)
    pthread.check_rc(rc)
    
    rc = pthread_mutex_alloc_init(src._internal)
    pthread.check_rc(rc)
    
    return rc
    

cdef int lock_destroy(lock * src) nogil except -1:
    """Destroy an event structure"""
    cdef int rc = 0
    if src._own_pthread:
        if src.mutex is not NULL:
            pthread.pthread_mutex_destroy(src.mutex)
            free(src.mutex)
        if src._owned is not NULL:
            free(src._owned)
    return rc

cdef class Lock:
    """A cython implementation of a GIL-free Lock object
    which should mimic the python lock object."""
    
    def __cinit__(self):
        self.mutex = NULL
        self._own_pthread = True
        self._owned = <bint *>malloc(sizeof(bint))
        self._owned[0] = 0
        self.mutex = <pthread.pthread_mutex_t *>malloc(sizeof(pthread.pthread_mutex_t))
        rc = pthread.pthread_mutex_init(self.mutex, NULL)
        pthread.check_rc(rc)
        
        self._internal = <pthread.pthread_mutex_t *>malloc(sizeof(pthread.pthread_mutex_t))
        rc = pthread.pthread_mutex_init(self._internal, NULL)
        pthread.check_rc(rc)
        
    
    def __dealloc__(self):
        self._destroy()
    
    cdef void _destroy(self) nogil:
        if self._owned is not NULL and self._own_pthread:
            free(self._owned)
        if self.mutex is not NULL and self._own_pthread:
            pthread.pthread_mutex_destroy(self.mutex)
            free(self.mutex)
        if self._internal is not NULL and self._own_pthread:
            pthread.pthread_mutex_destroy(self._internal)
            free(self._internal)
        self._own_pthread = False
    
    cdef lock _get_lock(self) nogil:
        cdef lock lck
        lck._own_pthread = False
        lck._owned = self._owned
        lck.mutex = self.mutex
        lck._internal = self._internal
        return lck
        
    @staticmethod
    cdef Lock _from_lock(lock * lck):
        cdef Lock obj = Lock()
        obj._destroy()
        obj.mutex = lck.mutex
        obj._owned = lck._owned
        obj._internal = lck._internal
        return obj
        
    property locked:
        def __get__(self):
            cdef bint _locked
            rc = pthread_mutex_acquire(self._internal)
            try:
                _locked = self._owned[0]
            finally:
                rc = pthread_mutex_release(self._internal)
            return _locked
        
    def copy(self):
        """Copy this event by reference"""
        cdef lock lck
        lck = self._get_lock()
        return Lock._from_lock(&lck)
    
    cdef int _acquire(self) nogil except -1:
        cdef int rc
        
        rc = pthread_mutex_acquire(self.mutex)
        rc = pthread_mutex_acquire(self._internal)
        try:
            self._owned[0] = 1
        finally:
            rc = pthread_mutex_release(self._internal)

        return rc
        
    def acquire(self):
        """Acquire the lock"""
        with nogil:
            self._acquire()

    cdef int _release(self) nogil except -1:
        cdef int rc
        rc = pthread_mutex_acquire(self._internal)
        try:
            self._owned[0] = 0
        finally:
            rc = pthread_mutex_release(self._internal)
        rc = pthread_mutex_release(self.mutex)
        return rc
        
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
