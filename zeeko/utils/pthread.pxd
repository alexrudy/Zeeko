"""Definitions from pthread"""

from libc.string cimport strerror
from libc.errno cimport errno
from .clock cimport timespec

cdef extern from "pthread.h" nogil:
    
    ctypedef struct pthread_mutex_t:
        pass
    ctypedef struct pthread_mutexattr_t:
        pass
    
    cdef int pthread_mutex_init(pthread_mutex_t *, const pthread_mutexattr_t *)
    cdef int pthread_mutex_lock(pthread_mutex_t *)
    cdef int pthread_mutex_unlock(pthread_mutex_t *)
    cdef int pthread_mutex_destroy(pthread_mutex_t *)
    
    ctypedef struct pthread_cond_t:
        pass
    
    ctypedef struct pthread_condattr_t:
        pass
    
    cdef int pthread_cond_init(pthread_cond_t *, const pthread_condattr_t *)
    cdef int pthread_cond_destroy(pthread_cond_t *)
    
    cdef int pthread_cond_wait(pthread_cond_t *, pthread_mutex_t *)
    cdef int pthread_cond_timedwait(pthread_cond_t *, pthread_mutex_t *, timespec *)
    
    cdef int pthread_cond_signal(pthread_cond_t *)
    cdef int pthread_cond_broadcast(pthread_cond_t *)
    
    ctypedef struct pthread_rwlock_t:
        pass
    ctypedef struct pthread_rwlockattr_t:
        pass
    
    cdef int pthread_rwlock_init(pthread_rwlock_t *, const pthread_rwlockattr_t *)
    cdef int pthread_rwlock_rdlock(pthread_rwlock_t *)
    cdef int pthread_rwlock_wrlock(pthread_rwlock_t *)
    cdef int pthread_rwlock_unlock(pthread_rwlock_t *)
    cdef int pthread_rwlock_destroy(pthread_rwlock_t *)
    
cdef inline void check_rc(int rc) nogil:
    if rc != 0:
        with gil:
            message = bytes(strerror(rc))
            raise RuntimeError("PThread Error {0} ({1})".format(message, rc))