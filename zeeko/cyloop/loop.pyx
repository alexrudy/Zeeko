
ctypedef cyloop_callback int (*_cyloop_callback)(void * handle, short events, void * data)

cdef struct socketinfo:
    void * handle
    short events
    cyloop_callback callback
    void * data
    
cdef class SocketInfo:
    
    cdef socketinfo info
    cdef Socket socket
    
    def __cinit__(self, Socket socket, int events):
        self.info.handle = socket.handle
        self.info.events = events
        self.info.callback = NULL
        self.info.data = NULL
    

cdef class IOLoop:
    """An I/O loop, using ZMQ's poller internally."""
    
    
    