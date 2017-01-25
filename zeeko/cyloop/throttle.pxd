"""
Rate limiting and scheduling for the CyLoop event loop
"""

cdef class Throttle:
    
    cdef bint active
    cdef double _last_event
    cdef double _next_event
    cdef readonly double period
    cdef public double timeout
    cdef double _wait_time
    cdef public double gain
    cdef public double leak
    
    cdef int reset(self) nogil
    cdef int mark(self) nogil except -1
    cdef long get_timeout(self) nogil