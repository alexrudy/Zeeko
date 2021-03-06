#cython: embedsignature=True

cimport zmq.backend.cython.libzmq as libzmq
from zmq.backend.cython.socket cimport Socket
from zmq.backend.cython.context cimport Context

import zmq
import datetime as dt

from .base cimport SocketMapping
from .snail cimport Snail
from ..messages.receiver cimport Receiver

cdef int client_callback(void * handle, short events, void * data, void * interrupt_handle) nogil except -1:
    cdef int rc = 0
    cdef int flags = 0
    if (events & libzmq.ZMQ_POLLIN):
        rc = (<Client>data).receiver._receive(handle, flags, NULL)
        rc = (<Client>data).snail._check(interrupt_handle, (<Client>data).receiver.last_message)
    return rc

cdef class Client(SocketMapping):
    """Receive arrays streamed over ZeroMQ Sockets.
    
    The client listens on a ZeroMQ socket for arrays
    streamed to it, and then makes those arrays available
    to your python code. The receiving is managed by an
    :class:`~zeeko.cyloop.loop.IOLoop` which does the work
    in threads behind the scenes, so that arrays you access
    from the Client are always as up to date as possible.
    
    The Client behaves like a python dictionary of received
    messages, with a few sugar-methods on top specific
    for handling messages not-yet-received, and ensuring
    that the client keeps up with whatever server is streaming
    data.
    
    To use a simple client, with default settings, use :meth:`at_address`::
        
        >>> client = Client.at_address("inproc://my-server")
        >>> client.create_loop()
        <IOLoop n=1 INIT>
        >>> client.loop.start()
        >>> client.loop.stop(timeout=1.0)
        
    """
    
    cdef Receiver receiver
    
    cdef readonly Snail snail
    """A :class:`~zeeko.handlers.snail.Snail` interface.
    
    The snail maintains the algorithm for properly handling
    lag between the server and the client. When too much lag
    occurs, the client will disconnect, drop intervenening
    messages, and then reconnect."""
    
    cdef str address
    
    cdef public bint use_reconnections
    """Whether the client should reconnect each time the I/O loop resumes processing messages."""
    
    def __cinit__(self):
        from ..messages import Receiver
        # Initialize basic client functions
        self.receiver = self.target = Receiver()
        self.callback = client_callback
        
        # Delay management
        self.snail = Snail()
        self.address = ""
        self.use_reconnections = False
    
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        if self.socket.type == zmq.SUB:
            self.support_options()
    
    def __repr__(self):
        parts = ["{0}".format(self.__class__.__name__)]
        if self.address:
            parts.append("address='{0}'".format(self.address))
        if self.loop is not None:
            parts.append("{0}".format(self.loop.state.name))
        if len(self):
            parts.append("last message at {0:%H%M%S}".format(self.last_message))
            parts.append("keys=[{0}]".format(",".join(self.keys())))
        return "<{0}>".format(" ".join(parts))
    
    def enable_reconnections(self, str address not None):
        """Enable the reconnect/disconnect on pause.
        
        :param str address: The address to use for reconnections.
        """
        self.address = address
        self.use_reconnections = True
    
    @classmethod
    def at_address(cls, str address, Context ctx = None, int kind = zmq.SUB, bind = False, enable_reconnections = True):
        """Create a client which is already connected to a specified address.
    
        :param str address: The ZeroMQ address to connect to.
        :param Context ctx: The ZeroMQ context to use for creating sockets.
        :param int kind: The ZeroMQ socket kind.
        :param bool enable_reconnections: Whether to enable reconnection on pause for this socket.
        :returns: :class:`Server` object wrapping a socket connected to `address`.
        """
        ctx = ctx or zmq.Context.instance()
        socket = ctx.socket(kind)
        if bind:
            socket.bind(address)
        else:
            socket.connect(address)
        obj = cls(socket, zmq.POLLIN)
        if enable_reconnections:
            obj.enable_reconnections(address)
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
        """Subscribe to a specific key."""
        self.opt.subscribe(key)
    
    def unsubscribe(self, key):
        """Unsubscribe from a specific key."""
        self.opt.unsubscribe(key)
        
    def reconnect(self):
        """Trigger a reconnection"""
        if not self.use_reconnections:
            raise ValueError("Reconnections are not enabled!")
        try:
            self.opt.disconnect(self.address)
        except zmq.ZMQError as e:
            pass # Swallow errors which arise due to disconnections.
        self.opt.connect(self.address)
    
    def event(self, key):
        """Return an event which will be set once a value is received for a specific key.
        
        Events can be waited on to determine when a key is available.
        """
        return self.receiver.event(key)
        
    def ready(self, key):
        """Check whether the given key has been received and is ready for use."""
        return self.__contains__(key)
    
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
        self.receiver.receive(socket, flags)
    
    property framecount:
        """The current framecounter for this client object.
    
        The framecounter is incremented once for each batch of messages published,
        and is used by clients to determine the absolute ordering of messages from
        the server."""
        def __get__(self):
            return self.receiver.framecount
        
    property last_message:
        """A datetime object representing the last message received."""
        def __get__(self):
            return dt.datetime.fromtimestamp(self.receiver.last_message)