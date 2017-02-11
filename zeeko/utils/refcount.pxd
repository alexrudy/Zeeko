# Reference counting semantics for Cython

from . cimport pthread

cdef struct refcount_t:
    size_t counter
    pthread.pthread_mutex_t mutex
    
cdef inline int refcount_init(refcount_t * ref) nogil except -1:
    ref.counter = 0
    return pthread.mutex_init(&ref.mutex, NULL)

cdef inline int refcount_destroy(refcount_t * ref) nogil except -1:
    pthread.mutex_lock(&ref.mutex)
    if ref.counter == 0:
        pthread.mutex_unlock(&ref.mutex)
        pthread.mutex_destroy(&ref.mutex)
        return 1
    elif ref.counter > 0:
        ref.counter -= 1
        return pthread.mutex_unlock(&ref.mutex)
    else:
        pthread.mutex_unlock(&ref.mutex)
        with gil:
            raise ValueError("Can't decrease refcount below 0.")
    
cdef inline int refcount_increment(refcount_t * ref) nogil except -1:
    pthread.mutex_lock(&ref.mutex)
    ref.counter += 1
    pthread.mutex_unlock(&ref.mutex)
    
cdef inline int refcount_decrement(refcount_t * ref) nogil except -1:
    cdef int rc
    rc = pthread.mutex_lock(&ref.mutex)
    try:
        if ref.counter > 0:
            ref.counter -= 1
        else:
            with gil:
                raise ValueError("Can't decrease refcount below 0.")
    finally:
        rc = pthread.mutex_unlock(&ref.mutex)
    return rc

cdef inline int refcount_get(refcount_t * ref) nogil except -1:
    cdef int rc, refcount
    rc = pthread.mutex_lock(&ref.mutex)
    refcount = <int>ref.counter
    rc = pthread.mutex_unlock(&ref.mutex)
    return refcount
    