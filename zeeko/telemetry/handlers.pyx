
cimport zmq.backend.cython.libzmq as libzmq
from zmq.backend.cython.socket cimport Socket
from zmq.backend.cython.context cimport Context

import zmq
import h5py
import itertools
import datetime as dt

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
    
    cdef Recorder recorder
    cdef readonly Snail snail
    """A :class:`~zeeko.handlers.snail.Snail` interface.
    
    The snail maintains the algorithm for properly handling
    lag between the server and the client. When too much lag
    occurs, the client will disconnect, drop intervenening
    messages, and then reconnect."""
    
    cdef str address
    cdef public bint use_reconnections
    """Whether the client should reconnect each time the I/O loop resumes processing messages."""
    
    cdef readonly str notifications_address
    """Address that chunk notification messages are sent over."""
    
    cdef readonly Socket notify
    """ZeroMQ socket used for outgoing notifications."""
    
    cdef readonly TelemetryWriter writer
    """:class:`~zeeko.telemetry.handlers.TelemetryWriter` object associated with this Telemetry reader."""
    
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
        """Enable the reconnect/disconnect on pause.
    
        :param str address: The address to use for reconnections.
        """
        self.address = address
        self.use_reconnections = True
        
    def enable_notifications(self, Context ctx, str address not None, str filename = None):
        """Enable notifications of full chunks.
        
        :param zmq.Context ctx: The ZeroMQ context for this pipeline.
        :param str address: The address to use for notifications.
        :param str filename: The HDF5 filename, possibly a new-style template which can be incremented.
        :returns: :class:`~zeeko.telemetry.handlers.TelemetryWriter`
        """
        self.notifications_address = address
        self.notify = ctx.socket(zmq.PUSH)
        self.notify.bind(self.notifications_address)
        self.notify_handle = self.notify.handle
        writer = self.writer = TelemetryWriter.from_recorder(filename, self, self.use_reconnections)
        return writer
    
    @classmethod
    def at_address(cls, str address, Context ctx, int kind = zmq.SUB, 
                   str filename = None, int chunksize = 1024,
                   enable_reconnections=True, enable_notifications=True):
        """Create a client which is already connected to a specified address.

        :param str address: The ZeroMQ address to connect to.
        :param Context ctx: The ZeroMQ context to use for creating sockets.
        :param int kind: The ZeroMQ socket kind.
        :param str filename: The HDF5 filename, possibly a new-style template which can be incremented.
        :param int chunksize: The size of telemetry chunks to record.
        :param bool enable_reconnections: Whether to enable reconnection on pause for this socket.
        :param bool enable_reconnections: Whether to enable notifications for full chunks.

        :returns: :class:`Telemetry` object wrapping a socket connected to `address`.
        """
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
        
    
    def receive(self, Socket socket = None, int flags = 0):
        """Receive a single message.
    
        By default, this receive command happens over the wrapped
        socket that the :class:`zeeko.cyloop.loop.IOLoop` would use,
        but you can provide a different socket if desired. This is useful
        when the I/O Loop is running, as ZeroMQ sockets are *not* thread
        safe, but the underlying publisher is thread-safe.
    
        :param zmq.Socket socket: (optional) The ZeroMQ socket for receiving
        :param int flags: (optional) The flags for the ZeroMQ socket receive operation.
        """
        if socket is None:
            socket = self.socket
        self.recorder.receive(socket, flags)
    
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
        
    property framecounter:
        """The current framecounter for this client object.

        The framecounter is incremented once for each batch of messages published,
        and is used by clients to determine the absolute ordering of messages from
        the server."""
        def __get__(self):
            return self.recorder.counter

    property last_message:
        """A datetime object representing the last message received."""
        def __get__(self):
            return dt.datetime.fromtimestamp(self.recorder.last_message)
            
    @property
    def pushed(self):
        """An event which is set when telemetry data is pushed to the writer."""
        return self.recorder.pushed
        
    @property
    def complete(self):
        """Whether the contained chunks are currently in a compelte state."""
        return self.recorder.complete
    

cdef class TelemetryWriter(SocketMapping):

    cdef Writer writer
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
