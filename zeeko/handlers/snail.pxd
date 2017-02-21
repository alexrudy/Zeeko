cdef class Snail:
    
    cdef readonly int deaths
    """Number of times the snail has expired for being too slow."""
    
    cdef readonly int nlate
    """Number of late messages received in a row."""
    
    cdef readonly double delay
    """The receive delay of the latest message."""
    
    cdef public int nlate_max
    """The maximum number of late messages this snail will tolerate."""
    
    cdef public double delay_max
    """The longest delay that this snail will tolerate."""
    
    cdef int reset(self) nogil
    cdef int check_at(self, void * handle, double now, double last_message) nogil
    cdef int _check(self, void * handle, double last_message) nogil