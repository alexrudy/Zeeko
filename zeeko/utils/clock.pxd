
from posix.types cimport time_t

cdef enum:
    MICROSECONDS = 100000
    MICROTONANO = 1000
    NANOTOSEC = (100000 * 1000)

cdef extern from "mclock.h" nogil:
    struct timespec:
        time_t tv_sec
        long   tv_nsec
    void current_utc_time(timespec *ts)
    
cdef inline double current_time() nogil:
    cdef timespec ts
    current_utc_time(&ts)
    return <double>(ts.tv_nsec * 1e-9) + <double>ts.tv_sec

cdef inline timespec microseconds_to_ts(int microseconds) nogil:
    cdef timespec ts
    current_utc_time(&ts)
    ts.tv_nsec += (microseconds * MICROTONANO) % NANOTOSEC
    ts.tv_sec += microseconds / MICROSECONDS
    ts.tv_sec += ts.tv_nsec / NANOTOSEC
    ts.tv_nsec %= NANOTOSEC
    return ts