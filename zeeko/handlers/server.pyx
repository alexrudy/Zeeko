#cython: embedsignature=True
cimport zmq.backend.cython.libzmq as libzmq
from zmq.backend.cython.socket cimport Socket
from zmq.backend.cython.context cimport Context

import struct as s
import datetime as dt
import zmq

from ..utils.rc cimport check_zmq_rc
from ..utils.msg cimport zmq_init_recv_msg_t, zmq_recv_sized_message, zmq_recv_more
from ..utils.msg import internal_address
from ..utils.clock cimport current_time

from ..messages.publisher cimport Publisher

from .base cimport SocketMutableMapping
from .snail cimport Snail

cdef int server_callback(void * handle, short events, void * data, void * interrupt_handle) nogil except -1:
    cdef int rc = 0
    cdef int flags = 0
    rc = (<Server>data).publisher._publish(handle, flags)
    return rc

cdef class Server(SocketMutableMapping):
    """Stream array data over ZeroMQ Sockets.
    
    Servers send array data over a ZeroMQ socket
    operating in an event loop managed by 
    :class:`~zeeko.cyloop.loop.IOLoop`. The event
    loop triggers the server to stream arrays with
    a specified period given by the :attr:`throttle`.
    
    The server can been indexed like a dictionary,
    where dictionary keys provide the array names
    to stream, and dictionary values are the array
    values::
        
        server = Server.at_address("inproc://test")
        server['my_array'] = np.zeros((12,12))
    
    Servers are designed to be used with the 
    :class:`~zeeko.cyloop.loop.IOLoop`, but they can
    be used independently with the :meth:`publish`
    method::
        
        server = Server.at_address("inproc://test")
        server['my_array'] = np.zeros((12,12))
        server.publish()
    
    Servers are thread-safe objects, so it is possible
    to update the arrays being served while the server
    is operating. You can either update the arrays
    in-place, or provide a new array.
    """
    
    
    cdef Publisher publisher
    
    def __cinit__(self):
        from ..messages import Publisher
        self.publisher = self.target = Publisher()
        self.callback = server_callback
    
    def __repr__(self):
        parts = ["{0}".format(self.__class__.__name__)]
        if self.loop is not None:
            parts.append("{0}".format(self.loop.state.name))
        if len(self):
            parts.append("framecount={0}".format(self.framecount))
            parts.append("keys=[{0}]".format(",".join("'{0!s}'".format(key) for key in self.keys())))
        else:
            parts.append("keys=[]")
        return "<{0}>".format(" ".join(parts))
    
    @classmethod
    def at_address(cls, str address, Context ctx = None, int kind = zmq.PUB):
        """Create a server which is already bound to a specified address.
        
        :param str address: The ZeroMQ address to connect to.
        :param Context ctx: The ZeroMQ context to use for creating sockets.
        :param int kind: The ZeroMQ socket kind.
        :returns: :class:`Server` object wrapping a socket connected to `address`.
        """
        ctx = ctx or zmq.Context.instance()
        socket = ctx.socket(kind)
        socket.bind(address)
        return cls(socket, zmq.POLLERR)
    
    def publish(self, Socket socket = None, int flags = 0):
        """Publish all registered arrays.
        
        By default, this publish command happens over the wrapped
        socket that the :class:`zeeko.cyloop.loop.IOLoop` would use,
        but you can provide a different socket if desired. This is useful
        when the I/O Loop is running, as ZeroMQ sockets are *not* thread
        safe, but the underlying publisher is thread-safe.
        
        :param zmq.Socket socket: (optional) The ZeroMQ socket for publishing
        :param int flags: (optional) The flags for the ZeroMQ socket send operation.
        """
        if socket is None:
            socket = self.socket
        self.publisher.publish(socket, flags)
        
    property framecount:
        """The current framecounter for this server object.
        
        The framecounter is incremented once for each batch of messages published,
        and is used by clients to determine the absolute ordering of messages from
        the server."""
        def __get__(self):
            return self.publisher.framecount
        
        def __set__(self, value):
            self.publisher.framecount = int(value)
        
    property last_message:
        """The last time a message was sent from this server."""
        def __get__(self):
            return dt.datetime.fromtimestamp(self.publisher.last_message)
        