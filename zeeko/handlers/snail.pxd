cdef class Snail:
    cdef readonly int deaths
    cdef readonly int nlate
    cdef readonly double delay
    cdef public int nlate_max
    cdef public double delay_max
    
    cdef int reset(self) nogil
    cdef int check_at(self, void * handle, double now, double last_message) nogil
    cdef int _check(self, void * handle, double last_message) nogil