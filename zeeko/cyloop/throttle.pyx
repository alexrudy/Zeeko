from posix.time cimport timespec, nanosleep
from ..utils.clock cimport current_time

cdef class Throttle:
    """A class for tracking and maintaining a rate limit.
    
    This is a simple integrating controller to maintain a rate
    limit for some process that has an unknown overhead time.
    """
    
    def __cinit__(self):
        self._last_event = 0.0
        self._next_event = 0.0
        self.period = 0.01
        self._wait_time = 0.0
        self.gain = 0.2
        self.leak = 0.9999
        self.timeout = 0.01
        self.active = False
    
    cdef int reset(self) nogil:
        self._wait_time = 0.0
        self._last_event = current_time()
        return 0
        
    cdef int mark(self) nogil except -1:
        cdef double now = current_time()
        cdef double error = 0.0
        cdef double overhead = 0.0
        overhead = now - self._last_event
        error = (self.period - overhead)
        self._wait_time = (self._wait_time + (self.gain * error)) * self.leak
        self._last_event = now
        self._next_event = now + self.period
        return 0
        
    cdef long get_timeout(self) nogil:
        cdef double now = current_time()
        cdef double next_event = self._last_event + self._wait_time
        cdef double wait_time = (next_event - now)
        cdef timespec wait_ts
        if not self.active:
            return <long>(self.timeout * 1e3)
        if wait_time < 0.0:
            return 0
        elif wait_time < 1.0:
            wait_ts.tv_nsec = <int>(wait_time * 1e6)
            wait_ts.tv_sec = 0
            nanosleep(&wait_ts, NULL)
            return 0
        else:
            return <long>(wait_time * 1e3)