from posix.time cimport timespec, nanosleep
from libc.math cimport floor
from ..utils.clock cimport current_time

cdef class Throttle:
    """A class for tracking and maintaining a rate limit.
    
    This is a simple integrating controller to maintain a rate
    limit for some process that has an unknown overhead time.
    """
    
    # Internal units for this class are always in seconds.
    # The return type for get_timeout() is a long integer,
    # in milliseconds so as to be compatible with ZMQ.
    
    def __cinit__(self):
        self._last_event = 0.0
        self._next_event = 0.0
        self.period = 0.01
        self._wait_time = 0.0
        self._gain = 0.2
        self._c = 1e-4
        self.timeout = 0.01
        self.active = False
        
    property frequency:
        """Frequency, in Hz."""
        def __get__(self):
            return 1.0 / self.period
        
        def __set__(self, double value):
            self.period = 1.0 / value
            
    
    property gain:
        """Integrator gain"""
        def __get__(self):
            return self._gain
        
        def __set__(self, double value):
            if 0.0 <= value <= 1.0:
                self._gain = value
            else:
                raise ValueError("Gain must be between 0.0 and 1.0.")
    
    property leak:
        """Integrator leak"""
        def __get__(self):
            return 1.0 - self._c
        
        def __set__(self, double value):
            self.c = 1.0 - value
    
    property c:
        """Integrator constant."""
        def __get__(self):
            return self._c
        
        def __set__(self, double value):
            if 0.0 <= value <= 1.0:
                self._c = value
            else:
                raise ValueError("C must be between 0.0 and 1.0.")
    
    def __repr__(self):
        if self.active:
            reprstr = "@{0:.0f}Hz".format(self.frequency)
        else:
            reprstr = "timeout={0:.3f}s".format(self.timeout)
        return "<{0:s} {1:s}>".format(self.__class__.__name__, reprstr)
    
    def _reset_at(self, last_event):
        """Reset integrator from python."""
        cdef double _last_event = last_event
        with nogil:
            self.reset_at(_last_event)
    
    cdef int reset(self) nogil:
        """Reset the integrator memory.
        
        This method assumes that the initial overhead is the full period.
        """
        return self.reset_at(current_time())
        
    cdef int reset_at(self, double last_event) nogil:
        """Reset the integrator at a specific time."""
        self._wait_time = 0.0
        self._last_event = last_event
        return 0
    
    def _mark_at(self, now):
        """Mark the event."""
        cdef int rc
        cdef double _now = now
        with nogil:
            rc = self.mark_at(_now)
        return rc
    
    cdef int mark_at(self, double now) nogil except -1:
        """Mark the operation as done at a specific time., preparing for the next event time."""
        self._next_event = now + self.period
        self._last_event = now
        return 0
        
    cdef int mark(self) nogil except -1:
        """Mark the operation as done, preparing for the next event time."""
        cdef double now = current_time()
        return self.mark_at(now)
        
    def _get_timeout_at(self, now, compute=True):
        """Get timeout from python."""
        cdef double _now = now
        cdef bint _compute = compute
        cdef long timoeut
        with nogil:
            timeout = self.get_timeout_at(_now, _compute)
        return timeout
        
    cdef int _compute(self, double now) nogil:
        cdef double error = 0.0
        cdef double memory = 0.0
        
        error = self._next_event - now
        memory = self._wait_time + (self._gain * error)
        self._wait_time =  memory - (memory * self._c)
        return 0
        
    cdef long get_timeout_at(self, double now, bint compute) nogil:
        """Get a timeout at a specific time."""
        cdef double wait_time = 0.0
        cdef timespec wait_ts
        if compute:
            self._compute(now)
        
        if not self.active:
            return <long>floor(self.timeout * 1e3)
        if self._wait_time < 0.0:
            return 0
        elif self._wait_time < 1e-3:
            wait_ts.tv_nsec = <int>floor(self._wait_time * 1e6)
            wait_ts.tv_sec = 0
            nanosleep(&wait_ts, NULL)
            return 0
        else:
            return <long>floor(self._wait_time * 1e3)
    
    cdef long get_timeout(self, bint compute) nogil:
        """Return the ZMQ timeout duration in milliseconds"""
        cdef double now = current_time()
        return self.get_timeout_at(now, compute)
    
