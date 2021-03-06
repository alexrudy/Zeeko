"""Definitions from pthread"""

from libc.string cimport strerror
from libc cimport errno
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
    
cdef inline int check_rc(int rc) nogil except -1:
    if rc == errno.ETIMEDOUT:
        # Parent should handle timeouts.
        return rc
    elif rc != 0:
        raise_oserror(rc)
    return rc

cdef inline int raise_oserror(int rc) nogil except -1:
    with gil:
       message = bytes(strerror(rc))
       raise OSError("PThread Error: {0} ({1})".format(message, rc))

# Mutexes
cdef inline int mutex_init(pthread_mutex_t * mutex, pthread_mutexattr_t * mutexattr) nogil except -1:
    return check_rc(pthread_mutex_init(mutex, mutexattr))

cdef inline int mutex_lock(pthread_mutex_t * mutex) nogil except -1:
    return check_rc(pthread_mutex_lock(mutex))

cdef inline int mutex_unlock(pthread_mutex_t * mutex) nogil except -1:
    return check_rc(pthread_mutex_unlock(mutex))

cdef inline int mutex_destroy(pthread_mutex_t * mutex) nogil except -1:
    return check_rc(pthread_mutex_destroy(mutex))

# Conditions
cdef inline int cond_init(pthread_cond_t * cond, pthread_condattr_t * condattr) nogil except -1:
    return check_rc(pthread_cond_init(cond, condattr))

cdef inline int cond_destroy(pthread_cond_t * cond) nogil except -1:
    return check_rc(pthread_cond_destroy(cond))

cdef inline int cond_wait(pthread_cond_t * cond, pthread_mutex_t * mutex) nogil except -1:
    return check_rc(pthread_cond_wait(cond, mutex))

cdef inline int cond_timedwait(pthread_cond_t * cond, pthread_mutex_t * mutex, timespec * ts) nogil except -1:
    return check_rc(pthread_cond_timedwait(cond, mutex, ts))

cdef inline int cond_signal(pthread_cond_t * cond) nogil except -1:
    return check_rc(pthread_cond_signal(cond))

cdef inline int cond_broadcast(pthread_cond_t * cond) nogil except -1:
    return check_rc(pthread_cond_broadcast(cond))