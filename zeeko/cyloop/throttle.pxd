"""
Rate limiting and scheduling for the CyLoop event loop
"""

cdef class Throttle:
    
    cdef public bint active
    cdef readonly double _last_event
    cdef readonly double _next_event
    cdef readonly double _wait_time
    
    cdef public double period
    cdef public double timeout
    cdef double _gain
    cdef double _c
    
    cdef int reset(self) nogil
    cdef int reset_at(self, double last_event) nogil
    cdef int mark(self) nogil except -1
    cdef int mark_at(self, double now) nogil except -1
    cdef int _compute(self, double now) nogil
    cdef long get_timeout(self, bint compute) nogil
    cdef long get_timeout_at(self, double now, bint compute) nogil
    