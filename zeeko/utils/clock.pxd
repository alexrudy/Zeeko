#cython: cdivision=True
from posix.types cimport time_t
from posix.time cimport clock_gettime, timespec, CLOCK_REALTIME

cdef enum:
    MICROSECONDS = 1000000
    NANOSECONDS =  1000000000

cdef inline void current_utc_time(timespec *ts) nogil:
    clock_gettime(CLOCK_REALTIME, ts)

cdef inline double timespec_to_microseconds(timespec * ts) nogil:
    cdef double microseconds
    return (<double>(ts.tv_sec) * MICROSECONDS) + ((<double>ts.tv_nsec) / 1000.0)
    
cdef inline double current_time() nogil:
    cdef timespec ts
    current_utc_time(&ts)
    return timespec_to_microseconds(&ts) / MICROSECONDS

cdef inline timespec microseconds_offset(long microseconds) nogil:
    cdef timespec ts
    current_utc_time(&ts)
    ts.tv_nsec = ts.tv_nsec + (microseconds % MICROSECONDS) * 1000
    ts.tv_sec  = ts.tv_sec + (microseconds / MICROSECONDS)
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