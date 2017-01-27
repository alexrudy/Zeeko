"""
Rate limiting and scheduling for the CyLoop event loop
"""

cdef class Throttle:
    
    cdef public bint active
    cdef readonly double _delay
    cdef readonly double _last_start
    cdef readonly double _last_event
    cdef readonly double _next_event
    
    cdef public double period
    cdef public double timeout
    cdef double _gain
    cdef double _c
    
    cdef int reset(self) nogil
    cdef int reset_at(self, double last_event) nogil
    cdef int mark(self) nogil
    cdef int mark_at(self, double now) nogil
    cdef int start(self) nogil
    cdef int start_at(self, double now) nogil
    cdef bint should_fire(self) nogil
    cdef long get_timeout(self) nogil
    cdef long get_timeout_at(self, double now, bint mark) nogil
    