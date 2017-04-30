
from .clock cimport current_utc_time, timespec_to_microseconds, timespec

cdef double MICROSECONDS = 1000000.0

cdef class Stopwatch:

    cdef timespec start_time
    
    def start(self):
        current_utc_time(&self.start_time)
    
    def stop(self):
        cdef timespec end_time
        cdef timespec delta_time
        current_utc_time(&end_time)
        delta_time.tv_nsec = (end_time.tv_nsec - self.start_time.tv_nsec)
        delta_time.tv_sec = (end_time.tv_sec - self.start_time.tv_sec)
        return timespec_to_microseconds(&delta_time) / MICROSECONDS
    

def _gettime():
    cdef timespec now
    current_utc_time(&now)
    return timespec_to_microseconds(&now) / MICROSECONDS