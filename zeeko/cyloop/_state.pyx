
from zmq.backend.cython.socket cimport Socket
from ..utils.condition cimport Event, event, event_trigger, event_init, event_clear, event_destroy
from ..utils.rc cimport check_memory_ptr, check_zmq_rc
from libc.stdlib cimport free, calloc

import struct as s
import zmq

STATE = {
    b'RUN': 1,
    b'PAUSE': 2,
    b'STOP': 3,
    b'INIT': 4,
    b'START': 5,
}

class StateError(Exception):
    """An error raised due to a state problem"""
    
cdef class StateMachine:
    
    def __cinit__(self):
        self._state = INIT
        self._lock = Lock()
        self._name_to_long = {}
        self._long_to_name = {}
        self._long_to_event = {}
        
        self._n = len(STATE)
        self._event_to_long = <long *>check_memory_ptr(calloc(self._n, sizeof(long)))
        self._select_events = <event *>check_memory_ptr(calloc(self._n, sizeof(event)))
        self._deselect_events = <event *>check_memory_ptr(calloc(self._n, sizeof(event)))
        
        for i, (name, value) in enumerate(STATE.items()):
            self._name_to_long[name] = value
            self._long_to_name[value] = name
            self._long_to_event[value] = i
            self._event_to_long[i] = value
            rc = event_init(&self._select_events[i])
            rc = event_init(&self._deselect_events[i])
        
    
    def __init__(self, state=INIT):
        self._set(state)
        
    
    def __iter__(self):
        return iter(self._name_to_long)
    
    def __dealloc__(self):
        if self._select_events != NULL:
            for i in range(self._n):
                event_destroy(&self._select_events[i])
            free(self._select_events)
        if self._deselect_events != NULL:
            for i in range(self._n):
                event_destroy(&self._deselect_events[i])
            free(self._deselect_events)
        if self._event_to_long != NULL:
            free(self._event_to_long)
    
    def name_to_state(self, name):
        return self._name_to_long[name]
        
    def state_to_name(self, state):
        return self._long_to_name[state]
        
    def selected(self, state):
        """Return an event which is triggered when this state is selected."""
        state = self._convert(state)
        i = self._event_index(state)
        return Event._from_event(&self._select_events[i])
        
    def deselected(self, state):
        """Return an event which is triggered when this state is deselected"""
        state = self._convert(state)
        i = self._event_index(state)
        return Event._from_event(&self._deselect_events[i])
        
    def __repr__(self):
        return "StateMachine('{0:s}')".format(self.name)
        
    property name:
        
        def __get__(self):
            cdef long state
            with self._lock:
                return self.state_to_name(self._state)
        
    cdef int _event_index(self, long state) nogil except -1:
        cdef int i
        for i in range(self._n):
            if self._event_to_long[i] == state:
                return i
        
    cdef int set(self, long state) nogil except -1:
        cdef int rc, i
        self._lock._acquire()
        try:
            i = self._event_index(self._state)
            rc = event_trigger(&self._deselect_events[i])
            rc = event_clear(&self._select_events[i])
            self._state = state
            i = self._event_index(state)
            rc = event_trigger(&self._select_events[i])
            rc = event_clear(&self._deselect_events[i])
        finally:
            self._lock._release()
        return 0
    
    def _check(self, state):
        """Check against a specific state."""
        cdef long s = self._convert(state)
        cdef bint r
        with nogil:
            r = self.check(s)
        return r
        
    def _set(self, state):
        """Set the state machine to a specific state."""
        cdef long s = self._convert(state)
        with nogil:
            self.set(s)
    
    cdef bint check(self, long state) nogil:
        cdef bint rc
        self._lock._acquire()
        try:
            if (self._state == state):
                rc = True
            else:
                rc = False
        finally:
            self._lock._release()
        return rc
    
    def _convert(self, state):
        try:
            value = int(state)
        except ValueError:
            value = self.name_to_state(state)
        return value
        
    def _get_state(self):
        with self._lock:
            rv = self._state
        return rv
        
    def ensure(self, state):
        state = self._convert(state)
        if state != self._get_state():
            raise StateError("Expected state {0} got {1}".format(self.state_to_name(state), self.name))
        return True
        
    def guard(self, state):
        state = self._convert(state)
        if state == self._get_state():
            raise StateError("Expected state to not be {0}".format(self.state_to_name(state)))
        return True
             
    
    def recv(self, Socket socket, long timeout = -1):
        """Recieve a sentinel on the given socket."""
        cdef libzmq.zmq_pollitem_t pollitem
        cdef int rc = 0
        pollitem.socket = socket.handle
        pollitem.events = libzmq.ZMQ_POLLIN
        pollitem.fd = 0
        with nogil:
            rc = check_zmq_rc(libzmq.zmq_poll(&pollitem, 1, timeout))
            self.sentinel(&pollitem)
    
    cdef int sentinel(self, libzmq.zmq_pollitem_t * pollitem) nogil except -1:
        cdef int rc, value = 0
        if (pollitem.revents & libzmq.ZMQ_POLLIN):
            rc = zmq_recv_sentinel(pollitem.socket, &value, 0)
            self.set(value)
            return 1
        return 0
        
    def signal(self, state, address, context = None):
        """Signal a state change."""
        self.guard(STOP)
        context = context or zmq.Context.instance()
        signal = context.socket(zmq.PUSH)
        signal.linger = 1000
        with signal:
            signal.connect(address)
            signal.poll(timeout=100, flags=zmq.POLLOUT)
            try:
                signal.send(s.pack("i", self._convert(state)), zmq.NOBLOCK)
            except zmq.Again:
                # We swallow EAGAIN here, becasue it usually means that the
                # socket would block.
                pass
        
