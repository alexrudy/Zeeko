#cython: cdivision=True
from posix.types cimport time_t

cdef enum:
    MICROSECONDS = 1000000
    NANOSECONDS =  1000000000

cdef extern from "mclock.h" nogil:
    
    struct timespec:
        time_t tv_sec
        long   tv_nsec
    
    struct timeval:
        time_t tv_sec
        long   tv_usec
    
    void current_utc_time(timespec *ts)
    int gettimeofday(timeval *tv, void *tzp)
    
cdef inline double timespec_to_microseconds(timespec * ts) nogil:
    cdef double microseconds
    return (<double>(ts.tv_sec) * MICROSECONDS) + ((<double>ts.tv_nsec) / 1000.0)
    
cdef inline double current_time() nogil:
    cdef timespec ts
    current_utc_time(&ts)
    return (<double>ts.tv_nsec / <double>NANOSECONDS) + <double>ts.tv_sec

cdef inline timespec microseconds_offset(long microseconds) nogil:
    cdef timespec ts
    cdef timeval tv
    gettimeofday(&tv, NULL)
    ts.tv_nsec = (tv.tv_usec * 1000) + (microseconds % MICROSECONDS) * 1000
    ts.tv_sec = (tv.tv_sec) + (microseconds / MICROSECONDS)
    ts.tv_sec += ts.tv_nsec / NANOSECONDS
    ts.tv_nsec %= NANOSECONDS
    return ts

cdef inline timespec microseconds_to_ts(long microseconds) nogil:
    cdef timespec ts
    current_utc_time(&ts)
    ts.tv_nsec += (microseconds % MICROSECONDS) * 1000
    ts.tv_sec += microseconds / MICROSECONDS
    ts.tv_sec += ts.tv_nsec / NANOSECONDS
    ts.tv_nsec %= NANOSECONDS
    return ts