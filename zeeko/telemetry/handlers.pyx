
cimport zmq.backend.cython.libzmq as libzmq
from zmq.backend.cython.socket cimport Socket
from zmq.backend.cython.context cimport Context

import zmq
import h5py
import itertools

from ..handlers.base cimport SocketInfo
from ..handlers.snail cimport Snail
from .recorder cimport Recorder
from .writer cimport Writer

cdef int recorder_callback(void * handle, short events, void * data, void * interrupt_handle) nogil except -1:
    cdef int rc = 0
    cdef int flags = 0
    if (events & libzmq.ZMQ_POLLIN):
        rc = (<RClient>data).recorder._receive(handle, flags, (<RClient>data).notify_handle, 0)
        rc = (<RClient>data).snail._check(interrupt_handle, (<RClient>data).recorder.last_message)
    return rc

cdef int writer_callback(void * handle, short events, void * data, void * interrupt_handle) nogil except -1:
    cdef int rc = 0
    cdef int flags = 0
    if (events & libzmq.ZMQ_POLLIN):
        rc = (<WClient>data).writer._receive(handle, flags, NULL)
        rc = (<WClient>data).snail._check(interrupt_handle, (<WClient>data).writer.last_message)
    return rc

cdef class RClient(SocketInfo):
    
    cdef readonly Recorder recorder
    cdef readonly Snail snail
    cdef str address
    cdef public bint use_reconnections
    
    cdef readonly str notifications_address
    cdef readonly Socket notify
    cdef void * notify_handle
    
    def __cinit__(self):
        
        # Initialize basic client functions
        self.recorder = Recorder(1024)
        self.callback = recorder_callback
        
        # Delay management
        self.snail = Snail()
        self.address = ""
        self.use_reconnections = False
        self.notify = None
        self.notify_handle = NULL
    
    def __init__(self, *args, **kwargs):
        chunksize = kwargs.pop('chunksize', 1024)
        self.recorder = Recorder(chunksize)
        super().__init__(self, *args, **kwargs)
        if self.socket.type == zmq.SUB:
            self.support_options()
    
    def enable_reconnections(self, str address not None):
        """Enable the reconnect/disconnect on pause."""
        self.address = address
        self.use_reconnections = True
        
    def enable_notifications(self, Context ctx, str address not None):
        self.notifications_address = address
        self.notify = ctx.socket(zmq.PUSH)
        self.notify.connect(self.notifications_address)
        self.notify_handle = self.notify.handle
    
    @classmethod
    def at_address(cls, str address, Context ctx, int kind = zmq.SUB, enable_reconnections=True, chunksize=1024):
        socket = ctx.socket(kind)
        socket.connect(address)
        obj = cls(socket, zmq.POLLIN, chunksize=chunksize)
        if enable_reconnections:
            obj.enable_reconnections(address)
        return obj
        
    cdef int paused(self) nogil except -1:
        """Function called when the loop has paused."""
        if not self.use_reconnections:
            return 0
        with gil:
            try:
                self.socket.disconnect(self.address)
            except zmq.ZMQError as e:
                if e.errno == zmq.ENOTCONN or e.errno == zmq.EAGAIN:
                    # Ignore errors that signal that we've already disconnected.
                    pass
                else:
                    raise
        return 0
    
    cdef int resumed(self) nogil except -1:
        """Function called when the loop is resumed."""
        if not self.use_reconnections:
            return 0
        with gil:
            try:
                self.socket.connect(self.address)
            except zmq.ZMQError as e:
                if e.errno == zmq.ENOTCONN or e.errno == zmq.EAGAIN:
                    # Ignore errors that signal that we've already disconnected.
                    pass
                else:
                    raise
        return 0
        
    def subscribe(self, key):
        """Subscribe"""
        self.opt.subscribe(key)
    
    def unsubscribe(self, key):
        """Unsubscribe"""
        self.opt.unsubscribe(key)
    

cdef class WClient(SocketInfo):

    cdef readonly Writer writer
    cdef readonly Snail snail
    cdef str address
    cdef object counter
    cdef public str filename
    cdef public bint use_reconnections

    def __cinit__(self):

        # Initialize basic client functions
        self.writer = Writer()
        self.callback = writer_callback
        
        # Delay management
        self.snail = Snail()
        self.address = ""
        self.filename = "telemetry.{0:04d}.hdf5"
        self.counter = itertools.count()
        self.use_reconnections = False

    def __init__(self, *args, **kwargs):
        super().__init__(self, *args, **kwargs)
        if self.socket.type == zmq.SUB:
            self.support_options()

    def enable_reconnections(self, str address not None):
        """Enable the reconnect/disconnect on pause."""
        self.address = address
        self.use_reconnections = True
        
    @classmethod
    def from_recorder(cls, str filename, rclient, enable_reconnections=True):
        obj = cls.at_address(rclient.notifications_address, 
                             rclient.notify.context, kind=zmq.PULL,
                             enable_reconnections=enable_reconnections)
        obj.filename = filename
        return obj
    
    @classmethod
    def at_address(cls, str address, Context ctx, int kind = zmq.PULL, enable_reconnections=True):
        socket = ctx.socket(kind)
        socket.connect(address)
        obj = cls(socket, zmq.POLLIN)
        if enable_reconnections:
            obj.enable_reconnections(address)
        return obj

    cdef int paused(self) nogil except -1:
        """Function called when the loop has paused."""
        if self.writer.file is not None: 
            with gil:
                self.writer.file.close()
                self.writer.file = None
        
        if not self.use_reconnections:
            return 0
        with gil:
            try:
                self.socket.disconnect(self.address)
            except zmq.ZMQError as e:
                if e.errno == zmq.ENOTCONN or e.errno == zmq.EAGAIN:
                    # Ignore errors that signal that we've already disconnected.
                    pass
                else:
                    raise
        return 0

    cdef int resumed(self) nogil except -1:
        """Function called when the loop is resumed."""
        if self.writer.file is None:
            with gil:
                self.writer.file = h5py.File(self.filename.format(next(self.counter)))
        
        if not self.use_reconnections:
            return 0
        with gil:
            try:
                self.socket.connect(self.address)
            except zmq.ZMQError as e:
                if e.errno == zmq.ENOTCONN or e.errno == zmq.EAGAIN:
                    # Ignore errors that signal that we've already disconnected.
                    pass
                else:
                    raise
        return 0

