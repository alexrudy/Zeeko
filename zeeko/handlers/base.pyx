#cython: embedsignature=True

# Cython Imports
# --------------
from zmq.backend.cython.message cimport Frame
from libc.string cimport strlen
from ..utils.rc cimport check_zmq_rc
from ..utils.msg cimport zmq_init_recv_msg_t, zmq_recv_sized_message, zmq_recv_more
from ..utils.msg cimport zmq_convert_sockopt

# Python Imports
# --------------
import zmq
import errno
import collections
import struct as s
from ..utils.msg import internal_address

__all__ = ['SocketInfo', 'SocketOptions', 'SocketOptionError']

cdef extern from *:
    ctypedef char* const_char_ptr "const char*"

def assert_socket_is_sub(socket, msg="Socket is not a ZMQ_SUB socket."):
    """Ensure a socket is a subscriber"""
    if socket.type != zmq.SUB:
        raise TypeError(msg)
        

cdef enum sockopt_kind:
    SET = 1
    GET = 2
    ERR = 3

cdef int getsockopt(void * handle, void * target) nogil except -1:
    cdef int rc = 0
    cdef int flags = 0
    cdef int sockopt = 0
    cdef int reply = GET
    cdef int errno
    cdef size_t sz = 255
    cdef const char str_o [255]

    rc = zmq_recv_sized_message(handle, &sockopt, sizeof(int), flags)
    rc = libzmq.zmq_getsockopt(target, sockopt, &str_o, &sz)
    if rc == 0:
        rc = check_zmq_rc(libzmq.zmq_sendbuf(handle, &reply, sizeof(int), flags|libzmq.ZMQ_SNDMORE))
        rc = check_zmq_rc(libzmq.zmq_sendbuf(handle, &str_o, sz, flags))
    else:
        reply = ERR
        errno = libzmq.zmq_errno()
        rc = check_zmq_rc(libzmq.zmq_sendbuf(handle, &reply, sizeof(int), flags|libzmq.ZMQ_SNDMORE))
        rc = check_zmq_rc(libzmq.zmq_sendbuf(handle, &errno, sizeof(int), flags))
    return rc

cdef int setsockopt(void * handle, void * target) nogil except -1:
    cdef int rc = 0
    cdef int flags = 0
    cdef int sockopt = 0
    cdef int reply = SET
    cdef int errno
    cdef libzmq.zmq_msg_t zmessage
    
    rc = zmq_recv_sized_message(handle, &sockopt, sizeof(int), flags)
    if zmq_recv_more(handle) == 1:
        rc = zmq_init_recv_msg_t(handle, flags, &zmessage)
        rc = libzmq.zmq_setsockopt(target, sockopt, 
                                    libzmq.zmq_msg_data(&zmessage), 
                                    libzmq.zmq_msg_size(&zmessage))
        if rc == 0:
            rc = check_zmq_rc(libzmq.zmq_sendbuf(handle, &reply, sizeof(int), flags|libzmq.ZMQ_SNDMORE))
            rc = check_zmq_rc(libzmq.zmq_sendbuf(handle, &sockopt, sizeof(int), flags))
        else:
            reply = ERR
            errno = libzmq.zmq_errno()
            rc = check_zmq_rc(libzmq.zmq_sendbuf(handle, &reply, sizeof(int), flags|libzmq.ZMQ_SNDMORE))
            rc = check_zmq_rc(libzmq.zmq_sendbuf(handle, &errno, sizeof(int), flags))
        rc = check_zmq_rc(libzmq.zmq_msg_close(&zmessage))
        return rc
    else:
        return -2

cdef int cbsockopt(void * handle, short events, void * data, void * interrupt_handle) nogil except -1:
    cdef int rc = 0
    cdef int flags = 0
    cdef int kind = 0
    cdef void * client_socket = data
    if (events & libzmq.ZMQ_POLLIN):
        rc = zmq_recv_sized_message(handle, &kind, sizeof(int), flags)
        if zmq_recv_more(handle) == 1:
            if kind == SET:
                rc = setsockopt(handle, client_socket)
            elif kind == GET:
                rc = getsockopt(handle, client_socket)
        else:
            pass
    return rc

class SocketOptionError(Exception):
    """Error raised when something goes terribly wrong
    while setting a socket option."""
    pass

cdef class SocketInfo:
    """Information about a socket and it's callbacks."""
    
    def __cinit__(self, Socket socket, int events, **kwargs):
        self.socket = socket # Retain reference.
        self.events = events
        self.opt = None
        self.throttle = Throttle()
        self.data = <void *>self
        self._bound = False
        
    def check(self):
        """Check this socketinfo object for safe c values.
        """
        assert isinstance(self.socket, zmq.Socket), "Socket is None"
        assert self.socket.handle != NULL, "Socket handle is null"
        assert self.callback != NULL, "Callback must be set."
    
    def __repr__(self):
        return "<{0:s} socket={1!r} events={2:s}>".format(self.__class__.__name__,
                self.socket, bin(self.events)[2:])
        
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
            
    cdef int paused(self) nogil except -1:
        """Function called when the loop has paused."""
        return 0
    
    cdef int resumed(self) nogil except -1:
        """Function called when the loop is resumed."""
        return 0
    
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
        if not self.throttle.should_fire():
            return -3
        if ((self.events & pollitem.revents) or (self.events & libzmq.ZMQ_POLLERR)) or self.throttle.active:
            rc = self.callback(self.socket.handle, pollitem.revents, self.data, interrupt)
            rc = self.throttle.mark()
            return rc
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
        
    def support_options(self):
        """Enable a thread-safe socket option support inside the IOLoop.
        
        Socket options can then be managed with the :attr:`opt` attribute, 
        an instance of :class:`SocketOptions` 
        """
        if self._bound:
            raise ValueError("Can't add option support when the socket is already bound.")
        self.opt = SocketOptions.wrap_socket(self.socket)
        
    def attach(self, ioloop):
        """Attach this object to an ioloop.
        
        This method must be called before the IO loop
        starts, but after any call to :meth:`support_options`.
        
        :param ioloop: The IO Loop
        """
        ioloop._add_socketinfo(self)
        if self.opt is not None:
            ioloop._add_socketinfo(self.opt)
        self._bound = True
        
    cdef int _disconnect(self, str url) except -1:
        try:
            self.socket.disconnect(url)
        except zmq.ZMQError as e:
            if e.errno in (zmq.ENOTCONN, zmq.EAGAIN, errno.ENOENT):
                # Ignore errors that signal that we've already disconnected.
                pass
            else:
                raise
        return 0
    
    cdef int _reconnect(self, str url) except -1:
        try:
            self.socket.connect(url)
        except zmq.ZMQError as e:
            if e.errno == zmq.EAGAIN:
                # Ignore errors that signal that we've already disconnected.
                pass
            else:
                raise
        return 0

cdef class SocketOptions(SocketInfo):
    """Manage the socket options on a ZeroMQ socket."""
    
    @classmethod
    def wrap_socket(cls, Socket socket):
        """Wrap a socket with the socket options protocol."""
        context = socket.context
        option_socket = context.socket(zmq.REP)
        obj = cls(option_socket, zmq.POLLIN)
        obj._set_client_socket(socket)
        return obj
    
    def __cinit__(self):
        self.autosubscribe = True
        self.callback = cbsockopt
    
        self.subscriptions = set()
        self.address = internal_address(self, 'sockopt')
        self.socket.bind(self.address)
    
    def _set_client_socket(self, Socket client_socket):
        self.client = client_socket
        self.data = client_socket.handle
    
    property context:
        def __get__(self):
            return self.client.context
    
    def set(self, int option, str key):
        """Set a specific socket option.
        
        :param int option: The option to set.
        :param str key: The option value, as a bytestring.
        """
        sink = self.context.socket(zmq.REQ)
        sink.linger = 10
        with sink:
            sink.connect(self.address)
            sink.send(s.pack("i", SET), flags=zmq.SNDMORE)
            sink.send(s.pack("i", option), flags=zmq.SNDMORE)
            sink.send(key)
            
            result = s.unpack("i",sink.recv())[0]
            if result == SET:
                reply_option = s.unpack("i",sink.recv())[0]
                if reply_option != option:
                    raise SocketOptionError("Reply did not match requested socket option.")
            else:
                errno = s.unpack("i",sink.recv())[0]
                raise zmq.ZMQError(errno)
        return
    
    def get(self, int option):
        """Get a socket option."""
        sink = self.context.socket(zmq.REQ)
        sink.linger = 10
        with sink:
            sink.connect(self.subscription_address)
            sink.send(s.pack("i", GET), flags=zmq.SNDMORE)
            sink.send(s.pack("i", option))
            
            result = s.unpack("i",sink.recv())[0]
            if result == GET:
                frame = <Frame>sink.recv(copy=False)
                response = zmq_convert_sockopt(option, &frame.zmq_msg)
            else:
                errno = s.unpack("i",sink.recv())[0]
                raise zmq.ZMQError(errno)
        return response
    
    def subscribe(self, str key):
        """Subscribe to a channel"""
        assert_socket_is_sub(self.client)
        if key in self.subscriptions:
            return
        self.subscriptions.add(key)
        self.set(zmq.SUBSCRIBE, key)

    def unsubscribe(self, str key):
        """Unsubscribe from a specific channel."""
        assert_socket_is_sub(self.socket)
        if key not in self.subscriptions:
            raise ValueError("Can't unsubscribe from {0:s}, not subscribed.".format(key))
        self.set(zmq.UNSUBSCRIBE, key)
        self.subscriptions.discard(key)    
    
    def _start(self):
        """Start the socket with subscriptions"""
        if self.client.type == zmq.SUB:
            if self.autosubscribe:
                self.client.subscribe("")
    

cdef class SocketMapping(SocketInfo):
    
    # Abstract methods provdied by the target.
    def __getitem__(self, key):
        return self.target.__getitem__(key)
    
    def __len__(self):
        return self.target.__len__()
    
    def __iter__(self):
        return self.target.__iter__()
        
    # Mixin methods provided by collections.
    def __contains__(self, key):
        return collections.Mapping.__contains__(self.target, key)
    
    def keys(self):
        """Return a new view of the dictionary’s keys"""
        return collections.Mapping.keys(self.target)
    
    def items(self):
        """Return a new view of the dictionary’s items (``(key, value)`` pairs)."""
        return collections.Mapping.items(self.target)
    
    def values(self):
        """Return a new view of the dictionary’s values."""
        return collections.Mapping.values(self.target)
    
    def get(self, key, default):
        """Get a value from the mapping, with a default."""
        return collections.Mapping.get(self.target, key, default)
    
    #def __eq__(self, other):
    #    return collections.Mapping.__eq__(self.target, other)
    #
    #def __ne__(self, other):
    #    return collections.Mapping.__ne__(self.target, other)

cdef class SocketMutableMapping(SocketMapping):
    
    def __setitem__(self, key, value):
        self.target.__setitem__(key, value)
    
    def __delitem__(self, key):
        self.target.__delitem__(key)
    
    def pop(self, key, default=None):
        """If `key` is in the dictionary, remove it and return its `value`, else return `default`. If `default` is not given and `key` is not in the dictionary, a `KeyError` is raised."""
        return collections.Mapping.pop(self.target, key, default)
    
    def popitem(self):
        """Remove and return an arbitrary `(key, value)` pair from the dictionary."""
        return collections.Mapping.popitem(self.target)
    
    def setdefault(self, key, value):
        """If `key` is in the dictionary, return its `value`. If not, insert `key` with a value of `default` and return `default`. `default` defaults to `None`."""
        return collections.Mapping.setdefault(self.target, key, value)
    
    def update(self, other):
        """Update the dictionary with the key/value pairs from `other`, overwriting existing keys. Return `None`."""
        return collections.Mapping.update(self.target, other)
    
    def clear(self):
        """Remove all values from the dictionary."""
        return collections.Mapping.clear(self.target)
