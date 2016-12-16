
from .clock cimport current_time

cdef class Stopwatch:
    
    cdef double _time
    
    def start(self):
        self._time = current_time()
    
    def stop(self):
        return current_time() - self._time