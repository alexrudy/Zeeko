
cimport zmq.backend.cython.libzmq as libzmq
from zmq.backend.cython.socket cimport Socket
from zmq.backend.cython.context cimport Context

import zmq
import h5py
import itertools
from ..utils.msg import internal_address

from ..handlers.base cimport SocketMutableMapping, SocketMapping
from ..handlers.snail cimport Snail
from .recorder cimport Recorder
from .writer cimport Writer

__all__ = ['Telemetry', 'TelemetryWriter']

cdef int recorder_callback(void * handle, short events, void * data, void * interrupt_handle) nogil except -1:
    cdef int rc = 0
    cdef int flags = 0
    if (events & libzmq.ZMQ_POLLIN):
        rc = (<Telemetry>data).recorder._receive(handle, flags, (<Telemetry>data).notify_handle, 0)
        rc = (<Telemetry>data).snail._check(interrupt_handle, (<Telemetry>data).recorder.last_message)
    return rc

cdef int writer_callback(void * handle, short events, void * data, void * interrupt_handle) nogil except -1:
    cdef int rc = 0
    cdef int flags = 0
    if (events & libzmq.ZMQ_POLLIN):
        rc = (<TelemetryWriter>data).writer._receive(handle, flags, NULL)
        rc = (<TelemetryWriter>data).snail._check(interrupt_handle, (<TelemetryWriter>data).writer.last_message)
    return rc

cdef class Telemetry(SocketMutableMapping):
    
    cdef readonly Recorder recorder
    cdef readonly Snail snail
    cdef str address
    cdef public bint use_reconnections
    
    cdef readonly str notifications_address
    cdef readonly Socket notify
    cdef readonly TelemetryWriter writer
    cdef void * notify_handle
    
    def __cinit__(self):
        
        # Initialize basic client functions
        from .sugar import Recorder
        self.recorder = self.target = Recorder(1024)
        self.callback = recorder_callback
        
        # Delay management
        self.snail = Snail()
        self.address = ""
        self.use_reconnections = False
        self.notify = None
        self.notify_handle = NULL
        self.writer = None
    
    def __init__(self, *args, **kwargs):
        from .sugar import Recorder
        chunksize = kwargs.pop('chunksize', 1024)
        self.recorder = self.target = Recorder(chunksize)
        super().__init__(self, *args, **kwargs)
        if self.socket.type == zmq.SUB:
            self.support_options()
    
    def enable_reconnections(self, str address not None):
        """Enable the reconnect/disconnect on pause."""
        self.address = address
        self.use_reconnections = True
        
    def enable_notifications(self, Context ctx, str address not None, str filename = None):
        self.notifications_address = address
        self.notify = ctx.socket(zmq.PUSH)
        self.notify.bind(self.notifications_address)
        self.notify_handle = self.notify.handle
        self.writer = TelemetryWriter.from_recorder(filename, self, self.use_reconnections)
    
    @classmethod
    def at_address(cls, str address, Context ctx, int kind = zmq.SUB, 
                   str filename = None, int chunksize = 1024,
                   enable_reconnections=True, enable_notifications=True):
        socket = ctx.socket(kind)
        socket.connect(address)
        obj = cls(socket, zmq.POLLIN, chunksize=chunksize)
        if enable_reconnections:
            obj.enable_reconnections(address)
        if enable_notifications:
            obj.enable_notifications(ctx, internal_address(obj, 'notify'), filename)
        return obj
        
    cdef int paused(self) nogil except -1:
        """Function called when the loop has paused."""
        if not self.use_reconnections:
            return 0
        with gil:
            self._disconnect(self.address)
        return 0
    
    cdef int resumed(self) nogil except -1:
        """Function called when the loop is resumed."""
        if not self.use_reconnections:
            return 0
        with gil:
            self._reconnect(self.address)
        return 0
        
    def subscribe(self, key):
        """Subscribe"""
        self.opt.subscribe(key)
    
    def unsubscribe(self, key):
        """Unsubscribe"""
        self.opt.unsubscribe(key)
        
    def _close(self):
        """Close this socketinfo."""
        self.socket.close(linger=0)
        if self.notify is not None:
            self.notify.close(linger=0)
    
    def close(self):
        """Safely close this socket wrapper"""
        if not self.socket.closed:
            self.socket.close()
        if self.notify is not None and not self.notify.closed:
            self.notify.close()
        if self.writer is not None:
            self.writer.close()
    

cdef class TelemetryWriter(SocketMapping):

    cdef readonly Writer writer
    cdef readonly Snail snail
    cdef str address
    cdef object counter
    cdef public str filename
    cdef public bint use_reconnections

    def __cinit__(self):

        # Initialize basic client functions
        from .sugar import Writer
        self.writer = self.target = Writer()
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
        if filename is not None:
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
    
    def _close(self):
        """Close this socketinfo."""
        self.socket.close(linger=0)
        if self.writer.file is not None: 
            self.writer.file.close()
            self.writer.file = None
