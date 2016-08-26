
from posix.types cimport time_t

cdef extern from "mclock.h" nogil:
    struct timespec:
        time_t tv_sec
        long   tv_nsec
    void current_utc_time(timespec *ts)
    
cdef inline double current_time() nogil:
    cdef timespec ts
    current_utc_time(&ts)
    return <double>(ts.tv_nsec * 1e-9) + <double>ts.tv_sec