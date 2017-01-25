import zmq

cdef class SocketInfo:
    """Information about a socket and it's callbacks."""
    
    def __cinit__(self, Socket socket, int events):
        self.socket = socket # Retain reference.
        self.events = events
        
    def check(self):
        """Check this socketinfo"""
        assert isinstance(self.socket, zmq.Socket), "Socket is None"
        assert self.socket.handle != NULL, "Socket handle is null"
        assert self.callback != NULL, "Callback must be set."
        
    def _start(self):
        """Python function run as the loop starts."""
        pass
        
    def _close(self):
        """Close this socketinfo."""
        self.socket.close(linger=0)
        
    def close(self):
        """Safely close this socket wrapper"""
        if not self.socket.closed:
            self.socket.close()
    
    cdef int bind(self, libzmq.zmq_pollitem_t * pollitem) nogil except -1:
        cdef int rc = 0
        pollitem.events = self.events
        pollitem.socket = self.socket.handle
        pollitem.fd = 0
        pollitem.revents = 0
        return rc
        
    cdef int fire(self, libzmq.zmq_pollitem_t * pollitem, void * interrupt) nogil except -1:
        cdef int rc = 0
        if pollitem.socket != self.socket.handle:
            with gil:
                raise ValueError("Poll socket does not match socket owned by this object.")
        if ((self.events & pollitem.revents) or (not self.events)):
            return self.callback(self.socket.handle, pollitem.revents, self.data, interrupt)
        else:
            return -2
    
    def __call__(self, Socket socket, int events, Socket interrupt_socket):
        """Run the callback from python"""
        cdef libzmq.zmq_pollitem_t pollitem
        cdef int rc 
        
        pollitem.socket = socket.handle
        pollitem.revents = events
        pollitem.events = self.events
        rc = self.fire(&pollitem, interrupt_socket.handle)
        return rc
