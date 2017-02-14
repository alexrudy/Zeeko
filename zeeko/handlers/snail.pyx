from zmq.backend.cython.socket cimport Socket

from ..utils.clock cimport current_time
from ..cyloop.statemachine cimport zmq_send_sentinel, PAUSE

cdef class Snail:

    def __cinit__(self):
        self.deaths = 0
        self.nlate = 0
        self.nlate_max = -1
        self.delay_max = 0.0
        self.delay = 0.0
        
    def __init__(self, **kwargs):
        self.configure(**kwargs)
        
    def __repr__(self):
        return "Snail(delay={0:.2g},deaths={1:d},late={2:d},active={3})".format(self.delay, self.deaths, self.nlate, self.active)
        
    property active:
        def __get__(self):
            return (self.nlate_max >= 0)
    
    cdef int reset(self) nogil:
        self.nlate = 0
        self.delay = 0.0
    
    cdef int check_at(self, void * handle, double now, double last_message) nogil:
        """Check the delay at some given time."""
        self.delay = now - last_message
        if (self.delay > self.delay_max):
            self.nlate = self.nlate + 1
            if (self.nlate_max >= 0) and (self.nlate > self.nlate_max):
                zmq_send_sentinel(handle, PAUSE, 0)
                self.deaths = self.deaths + 1
                self.nlate = 0
        else:
            self.nlate = 0
        return 0
    
    cdef int _check(self, void * handle, double last_message) nogil:
        """Check for delays right now."""
        cdef double now = current_time()
        return self.check_at(handle, now, last_message)
    
    def check(self, Socket socket, now=None, last_message=None):
        cdef double _last_message, _now
        if now is None:
            _now = current_time()
        else:
            _now = <double>now
        if last_message is None:
            _last_message = _now
        else:
            _last_message = <double>last_message
        with nogil:
            self.check_at(socket.handle, _now, _last_message)
    
    def configure(self, **kwargs):
        """Configure the snail."""
        self.delay_max = kwargs.pop('delay', self.delay_max)
        self.nlate_max = kwargs.pop('nlate', self.nlate_max)
        
        