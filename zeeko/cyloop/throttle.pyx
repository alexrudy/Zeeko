import numpy as np
from posix.time cimport timespec, nanosleep
from libc.math cimport floor, fmod
from ..utils.clock cimport current_time

__all__ = ['Throttle']

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
        self._last_start = 0.0
        self._delay = 0.0
        
        self.period = 0.01
        self._gain = 0.2
        self._c = 1e-4
        self._adjustment = 0.25e-3
        self.timeout = 0.01
        self.active = False
        
        self._history = np.zeros((1000,), dtype=np.float)
        self._i = 0
        
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
        
    property overhead:
        """Estimate of the amount of time spent doing work."""
        def __get__(self):
            return self.period - self._delay
    
    def __repr__(self):
        if self.active:
            reprstr = "@{0:.0f}Hz".format(self.frequency)
        else:
            reprstr = "timeout={0:.3f}s".format(self.timeout)
        return "<{0:s} {1:s}>".format(self.__class__.__name__, reprstr)
    
    def configure(self, **kwargs):
        """Configure the throttle.
        
        Accepted keyword arguments are any of the exposed
        throttle properties. Unknown arguments are ignored.
        """
        if "frequency" in kwargs:
            self.frequency = kwargs.pop("frequency")
        elif "period" in kwargs:
            self.period = kwargs.pop("period")
        if "gain" in kwargs:
            self.gain = kwargs.pop("gain")
        if "leak" in kwargs:
            self.leak = kwargs.pop("leak")
        elif "c" in kwargs:
            self.c = kwargs.pop("c")
        if "active" in kwargs:
            self.active = kwargs.pop("active")
        if "timeout" in kwargs:
            self.timeout = kwargs.pop("timeout")
    
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
        self._delay = 0.0
        self._last_event = last_event
        return 0
    
    def _mark_at(self, now):
        """Mark the event."""
        cdef int rc
        cdef double _now = now
        with nogil:
            rc = self.mark_at(_now)
        return rc
    
    cdef int mark_at(self, double now) nogil:
        """Mark the operation as done at a specific time., preparing for the next event time."""
        cdef double delay_i = now - self._last_event
        #cdef double delay_i = self.period - now + self._last_event
        cdef double error = self.period - delay_i# - self._delay
        cdef double memory = self._delay + (self._gain * error)
        self._delay = memory - (memory * self._c) #- self._adjustment
        self._next_event = now + self.period
        self._last_event = now
        
        # Record history
        if self._i < self._history.shape[0]:
            with gil:
                self._history[self._i] = self._delay
                self._i += 1
        return 0
        
    cdef int mark(self) nogil:
        """Mark the operation as done, preparing for the next event time."""
        cdef double now = current_time()
        return self.mark_at(now)
        
    def _get_timeout(self):
        cdef long timoeut
        with nogil:
            timeout = self.get_timeout()
        return timeout
        
    def _get_timeout_at(self, now, mark=False):
        """Get timeout from python."""
        cdef double _now = now
        cdef bint _mark = mark
        cdef long timoeut
        with nogil:
            timeout = self.get_timeout_at(_now, _mark)
        return timeout
        
    def _start_at(self, now=None):
        cdef int rc
        cdef double _now = now
        with nogil:
            rc = self.start_at(_now)
        return rc
        
    cdef int start_at(self, double now) nogil:
        """Start work. Can infer overhead here."""
        self._last_start = now
    
    cdef int start(self) nogil:
        return self.start_at(current_time())
        
    cdef bint should_fire(self) nogil:
        cdef double now = current_time()
        return (not self.active) or (now >= self._delay + self._last_event)
        
    cdef long get_timeout_at(self, double now, bint mark) nogil:
        """Get a timeout at a specific time."""
        cdef double wait_time = 0.0
        cdef timespec wait_ts
        if mark:
            self.mark_at(now)
        
        wait_time = self._last_event + self._delay - now
        if not self.active:
            return <long>floor(self.timeout * 1e3)
        if wait_time < 0.0:
            return 0
        elif wait_time < 2e-3:
            wait_ts.tv_nsec = <int>floor(fmod(wait_time  * 1e6, 1e3))
            wait_ts.tv_sec = 0
            nanosleep(&wait_ts, NULL)
            return <long>floor(wait_time * 1e3)
        else:
            return <long>floor(wait_time * 1e3)
    
    cdef long get_timeout(self) nogil:
        """Return the ZMQ timeout duration in milliseconds"""
        cdef double now = current_time()
        return self.get_timeout_at(now, 0)
    
