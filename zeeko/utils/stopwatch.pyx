
from .clock cimport current_utc_time, timespec_to_microseconds, timespec

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
        print(self.start_time.tv_sec, self.start_time.tv_nsec)
        print(end_time.tv_sec, end_time.tv_nsec)
        print(delta_time.tv_sec, delta_time.tv_nsec)
        return timespec_to_microseconds(&delta_time) / 1000000