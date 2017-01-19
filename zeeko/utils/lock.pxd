from . cimport pthread

ctypedef struct lock:
    bint _own_pthread
    bint * _owned
    pthread.pthread_mutex_t * mutex
    pthread.pthread_mutex_t * _internal

cdef int lock_acquire(lock * src) nogil except -1    
cdef int lock_release(lock * src) nogil except -1    
cdef int lock_init(lock * src) nogil except -1
cdef int lock_destroy(lock * src) nogil except -1

cdef class Lock:
    cdef bint _own_pthread
    cdef bint * _owned
    cdef pthread.pthread_mutex_t * mutex
    cdef pthread.pthread_mutex_t * _internal
    
    cdef void _destroy(self) nogil
    
    @staticmethod
    cdef Lock _from_lock(lock * lck)
    
    cdef lock _get_lock(self) nogil
    
    cdef int _acquire(self) nogil except -1
    cdef int _release(self) nogil except -1
        