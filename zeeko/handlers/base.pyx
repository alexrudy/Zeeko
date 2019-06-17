#cython: embedsignature=True

# Cython Imports
# --------------
from zmq.backend.cython.message cimport Frame
from zmq.backend.cython.context cimport Context

from libc.string cimport strlen, memcpy
from ..utils.rc cimport check_zmq_rc, malloc, free, calloc
from ..utils.msg cimport zmq_init_recv_msg_t, zmq_recv_sized_message, zmq_recv_more
from ..utils.msg cimport zmq_convert_sockopt, zmq_invert_sockopt, zmq_size_sockopt

from cpython cimport PyBytes_FromStringAndSize

# Python Imports
# --------------
import zmq
import errno
import collections
import weakref
import logging
import struct as s
from ..utils.msg import internal_address
from ..utils.sandwich import sandwich_unicode

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
    CON = 4

# Bitmask flag to control connection modes.
# BIND = we should bind this socket to an address.
# BIND & DROP = we should unbind this socket.
# CONNECT = we should connect this socket to an address.
# CONNECT & DROP = we should disconnect this socket from
# an address.
cdef enum sockconn_kind:
    BIND = 1
    CONNECT = 2
    DROP = 4

cdef int connect(void * handle, void * target) nogil except -1:
    # Callback which handles connect() control messages.
    #
    # When this function starts, *handle is the controlling socket,
    # which has just recieved the first control flag, which must
    # have been a CON signal (from sockopt_kind).
    #
    # CON control messages have the following form:
    # [CON, sockconn_kind, connection_string]
    # 
    # *target is the socket which is being controlled by this callback,
    # and so will be connected or disconnected.

    # return values:
    # -1 = ZMQ Library Error
    # -2 = Protocol error (e.g. the message didn't conform to the expected format).
    # -3 = Memory allocation error

    cdef int rc = 0
    cdef int flags = 0
    cdef int reply = CON
    cdef int connection = 0
    cdef int errno
    cdef size_t sz = 255
    cdef char * endpoint
    cdef libzmq.zmq_msg_t zmessage
    
    # Recieve the connection kind: sockconn_kind
    # This is an int which serves as a bitflag for connections.
    rc = check_zmq_rc(zmq_recv_sized_message(handle, &connection, sizeof(int), flags))
    if not zmq_recv_more(handle) == 1:
        return -2
    
    # Recieve the connection string.
    # Ensure that the endpoint is null-terminated by copying into a new buffer.
    rc = check_zmq_rc(zmq_init_recv_msg_t(handle, flags, &zmessage))
    endpoint = <char *>calloc(libzmq.zmq_msg_size(&zmessage) + 1, sizeof(char))
    if endpoint == NULL:
        return -3
    memcpy(endpoint, libzmq.zmq_msg_data(&zmessage), libzmq.zmq_msg_size(&zmessage))

    # Handle the actual connection method.
    if (connection & CONNECT) and not (connection & DROP):
        rc = libzmq.zmq_connect(target, endpoint)
    elif (connection & CONNECT) and (connection & DROP):
        rc = libzmq.zmq_disconnect(target, endpoint)
    elif (connection & BIND) and not (connection & DROP):
        rc = libzmq.zmq_bind(target, endpoint)
    elif (connection & BIND) and (connection & DROP):
        rc = libzmq.zmq_unbind(target, endpoint)
    else:
        rc = -2

    # Reply on the control socket with either success or failure.
    if rc == 0:

        # Send back the success flag and the connection string
        rc = check_zmq_rc(libzmq.zmq_sendbuf(handle, &reply, sizeof(int), flags|libzmq.ZMQ_SNDMORE))
        rc = check_zmq_rc(libzmq.zmq_msg_send(&zmessage, handle, flags))
    else:
        reply = ERR
        errno = libzmq.zmq_errno()

        # Send back the error control flag and errono.
        rc = check_zmq_rc(libzmq.zmq_sendbuf(handle, &reply, sizeof(int), flags|libzmq.ZMQ_SNDMORE))
        rc = check_zmq_rc(libzmq.zmq_sendbuf(handle, &errno, sizeof(int), flags))

        # Close the message with the endpoint because we don't want to orphan it.
        rc = check_zmq_rc(libzmq.zmq_msg_close(&zmessage))
    
    # We allocated the endpoint with calloc above.
    free(endpoint)
    return rc

cdef int getsockopt(void * handle, void * target) nogil except -1:
    # Callback which handles getsockopt() control messages.
    #
    # When this function starts, *handle is the controlling socket,
    # which has just recieved the first control flag, which must
    # have been a GET signal (from sockopt_kind).
    #
    # GET control messages have the following form:
    # [GET, sockopt, size]
    # 
    # *target is the socket which is being controlled by this callback,
    # and so will inspected for options.

    # return values:
    # -1 = ZMQ Library Error
    # -2 = Protocol error (e.g. the message didn't conform to the expected format).
    # -3 = Memory allocation error
    
    cdef int rc = 0
    cdef int flags = 0
    cdef int sockopt = 0
    cdef int reply = GET
    cdef int errno
    cdef size_t sz = 255
    cdef void * optval

    # First part of the message is the constant which represents the socket option.
    rc = check_zmq_rc(zmq_recv_sized_message(handle, &sockopt, sizeof(int), flags))
    if not zmq_recv_more(handle) == 1:
        return -2
    
    # Second part of the message is the size of the option.
    rc = check_zmq_rc(zmq_recv_sized_message(handle, &sz, sizeof(size_t), flags))

    # Allocate a value to recieve the option.
    optval = malloc(sz)
    if optval == NULL:
        # Memory Error
        return -3

    rc = libzmq.zmq_getsockopt(target, sockopt, &optval, &sz)

    # Reply on the control socket with success or failure.
    if rc == 0:

        # Success replies contain the control code (GET) and the option value.
        rc = check_zmq_rc(libzmq.zmq_sendbuf(handle, &reply, sizeof(int), flags|libzmq.ZMQ_SNDMORE))
        rc = check_zmq_rc(libzmq.zmq_sendbuf(handle, &optval, sz, flags))
        #TODO: zmq_sendbuf should take care of freeing the buffer?
    
    else:

        # Error replies contain the control code (ERR) and the errno from ZMQ
        reply = ERR
        errno = libzmq.zmq_errno()
        rc = check_zmq_rc(libzmq.zmq_sendbuf(handle, &reply, sizeof(int), flags|libzmq.ZMQ_SNDMORE))
        rc = check_zmq_rc(libzmq.zmq_sendbuf(handle, &errno, sizeof(int), flags))
        
        # In the error case, we need to manulaly free the value buffer.
        free(optval)
    
    return rc

cdef int setsockopt(void * handle, void * target) nogil except -1:
    # Callback which handles setsockopt() control messages.
    #
    # When this function starts, *handle is the controlling socket,
    # which has just recieved the first control flag, which must
    # have been a SET signal (from sockopt_kind).
    #
    # SET control messages have the following form:
    # [SET, sockopt, value]
    # 
    # *target is the socket which is being controlled by this callback,
    # and so will inspected for options.

    # return values:
    # -1 = ZMQ Library Error
    # -2 = Protocol error (e.g. the message didn't conform to the expected format).
    # -3 = Memory allocation error

    cdef int rc = 0
    cdef int flags = 0
    cdef int sockopt = 0
    cdef int reply = SET
    cdef int errno
    cdef libzmq.zmq_msg_t zmessage
    
    # Receive the socket option specifier
    rc = check_zmq_rc(zmq_recv_sized_message(handle, &sockopt, sizeof(int), flags))
    if not zmq_recv_more(handle) == 1:
        return -2
    
    # Recieve the socket value
    rc = check_zmq_rc(zmq_init_recv_msg_t(handle, flags, &zmessage))

    # Set the option
    rc = libzmq.zmq_setsockopt(target, sockopt, 
                                libzmq.zmq_msg_data(&zmessage), 
                                libzmq.zmq_msg_size(&zmessage))
    
    # Reply with the result
    if rc == 0:
        
        # In the success case, the reply is just [SET, sockopt]
        rc = check_zmq_rc(libzmq.zmq_sendbuf(handle, &reply, sizeof(int), flags|libzmq.ZMQ_SNDMORE))
        rc = check_zmq_rc(libzmq.zmq_sendbuf(handle, &sockopt, sizeof(int), flags))
    else:
        # In the error case, the reply is [ERR, errno]
        reply = ERR
        errno = libzmq.zmq_errno()
        rc = check_zmq_rc(libzmq.zmq_sendbuf(handle, &reply, sizeof(int), flags|libzmq.ZMQ_SNDMORE))
        rc = check_zmq_rc(libzmq.zmq_sendbuf(handle, &errno, sizeof(int), flags))
    rc = check_zmq_rc(libzmq.zmq_msg_close(&zmessage))
    return rc

cdef int cbsockopt(void * handle, short events, void * data, void * interrupt_handle) nogil except -1:
    # Callback for socket option management.
    # The void*data pointer is a pointer to the client socket.
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
            elif kind == CON:
                rc = connect(handle, client_socket)
        else:
            pass
    return rc

class SocektOptionBase(Exception):
    """Base exception for socket options"""
    pass

class SocketOptionError(SocektOptionBase):
    """Error raised when something goes terribly wrong
    while setting a socket option."""
    pass

class SocketOptionTimeout(SocektOptionBase):
    """Error raised when a socket option times out."""
    pass

cdef class SocketInfo:
    """Information about a socket and it's callbacks."""
    
    def __cinit__(self, Socket socket, int events, **kwargs):
        self.socket = socket # Retain reference.
        self.events = events
        self.fired = Event()
        self.opt = None
        self.throttle = Throttle()
        self.data = <void *>self
        self._bound = False
        self._inuse = Lock()
        self._loop_ref = lambda : None
        self._loop_worker = lambda : None
        self.log = logging.getLogger(".".join([__name__, self.__class__.__name__]))
        
    def __init__(self, socket, events, **kwargs):
        super().__init__()
    
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
        self._inuse.acquire()
        
    def _close(self):
        """Close this socketinfo."""
        self.socket.close(linger=0)
        self._inuse.release()
        
    def close(self, linger=1):
        """Safely close this socket wrapper"""
        with self._inuse.timeout(linger):
            if not self.socket.closed:
                self.socket.close(linger=1)
            if self.opt is not None:
                self.opt.close()
        
            
    cdef int paused(self) nogil except -1:
        """Function called when the loop has paused."""
        return 0
    
    cdef int resumed(self) nogil except -1:
        """Function called when the loop is resumed."""
        return 0
    
    cdef int _bind(self, libzmq.zmq_pollitem_t * pollitem) nogil except -1:
        cdef int rc = 0
        pollitem.events = self.events
        pollitem.socket = self.socket.handle
        pollitem.fd = 0
        pollitem.revents = 0
        return rc
        
    cdef int _fire(self, libzmq.zmq_pollitem_t * pollitem, void * interrupt) nogil except -1:
        cdef int rc = 0
        if pollitem.socket != self.socket.handle:
            with gil:
                raise ValueError("Poll socket does not match socket owned by this object.")
        if not self.throttle.should_fire():
            return -3
        if ((self.events & pollitem.revents) or (self.events & libzmq.ZMQ_POLLERR)) or self.throttle.active:
            rc = self.callback(self.socket.handle, pollitem.revents, self.data, interrupt)
            rc = self.throttle.mark()
            self.fired._set()
            return rc
        else:
            return -2
    
    def __call__(self, Socket socket = None, events = None, Socket interrupt_socket = None, int timeout = 100):
        """Run the callback from python"""
        cdef libzmq.zmq_pollitem_t pollitem
        cdef void * interrupt_handle = NULL
        cdef int rc
        
        if socket is None:
            socket = self.socket
        if events is None:
            events = socket.poll(flags=self.events, timeout=timeout)
        
        if interrupt_socket is None:
            worker = self._loop_worker()
            if worker is not None:
                interrupt_socket = worker._interrupt
        
        if interrupt_socket is not None:
            interrupt_handle = interrupt_socket.handle
        
        pollitem.socket = socket.handle
        pollitem.revents = events
        pollitem.events = self.events
        with nogil:
            rc = self._fire(&pollitem, interrupt_handle)
        return rc
        
    def support_options(self):
        """Enable a thread-safe socket option support inside the IOLoop.
        
        Socket options can then be managed with the :attr:`opt` attribute, 
        an instance of :class:`SocketOptions` 
        """
        if self._bound:
            raise ValueError("Can't add option support when the socket is already bound.")
        self.opt = SocketOptions.wrap_socket(self.socket)
        
    def create_ioloop(self, **kwargs):
        """This is a shortcut method to create an I/O Loop to manage this object.
        
        :param zmq.Context ctx: The ZeroMQ context to use for sockets in this loop.
        :returns: The :class:`~zeeko.cyloop.loop.IOLoop` object.
        """
        from ..cyloop.loop import IOLoop
        loop = IOLoop(self.socket.context, **kwargs)
        loop.attach(self)
        self._loop = loop
        return loop
        
    def _register(self, ioloop_worker):
        """Register ownership of an IOLoop"""
        self._loop_ref = weakref.ref(ioloop_worker.manager)
        self._loop_worker = weakref.ref(ioloop_worker)
        self._bound = True
        
        
    def _attach(self, ioloop_worker):
        """Attach this object to an ioloop.
        
        This method must be called before the IO loop
        starts, but after any call to :meth:`support_options`.
        
        :param ioloop: The IO Loop worker that should manage this socket.
        """
        self._register(ioloop_worker)
        ioloop_worker._add_socketinfo(self)
        if self.opt is not None:
            self.opt._register(ioloop_worker)
            ioloop_worker._add_socketinfo(self.opt)
        
    @property
    def loop(self):
        """The :class:`~zeeko.cyloop.loop.IOLoop` object which manages this socket."""
        return self._loop_ref()
        
    def _is_loop_running(self):
        if self.loop is None:
            return False
        self.loop.state.deselected("INIT").wait(timeout=0.1)
        return self.loop.is_alive() and self.loop.state.deselected("INIT").is_set()
        
    cdef int _disconnect(self, str url) except -1:
        try:
            self.socket.set(zmq.LINGER, 100)
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
        else:
            if self.opt is not None:
                self.opt._resubscribe()
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
        
    def check(self):
        """Check this socketinfo object for safe c values.
        """
        assert isinstance(self.socket, zmq.Socket), "Socket is None"
        assert self.socket.handle != NULL, "Socket handle is null"
        assert self.callback != NULL, "Callback must be set."
        assert isinstance(self.client, zmq.Socket), "Client must best."
        assert self.data == self.client.handle, "Hanlde must be set"
    
    property context:
        def __get__(self):
            return self.client.context
        
    
    def _preflight_call(self, function, int timeout, *args, **kwargs):
        if not self._is_loop_running():
            with self._inuse.timeout(timeout):
                return_value = function(*args, **kwargs)
            return True, return_value
        else:
            return False, None
    
    def _optmessage(self, int control, list message, int timeout):
        """Refactor to handle sending an option message."""
        cdef bytes optctl = PyBytes_FromStringAndSize(<char *>&control, sizeof(int))
        
        sink = self.context.socket(zmq.REQ)
        sink.linger = 10
        with sink:
            sink.connect(self.address)
            sink.send(optctl, flags=zmq.SNDMORE)
            sink.send_multipart(message)
            if sink.poll(timeout=timeout, flags=zmq.POLLIN):
                result = s.unpack("i", sink.recv())[0]
                if result == control:
                    return sink.recv(copy=False)
                elif result == ERR:
                    errno = s.unpack("i", sink.recv())[0]
                    raise zmq.ZMQError(errno)
                else:
                    raise SocketOptionError("Reply mode did not match request mode. Sent {0} got {1}".format(control, result))
            else:
                raise SocketOptionTimeout("Socket setoption timed out after {0} ms.".format(timeout))
    
    def _connection(self, int connection_kind, str endpoint, int timeout):
        """Extracted method to handle connection tools."""
        cdef bytes connection_c = PyBytes_FromStringAndSize(<char *>&connection_kind, sizeof(int))
        return self._optmessage(CON, [connection_c, sandwich_unicode(endpoint)], timeout)
        
    def bind(self, str endpoint, int timeout=1000):
        """Bind this socket to a ZMQ endpoint in a threadsafe manner."""
        called, return_value = self._preflight_call(self.client.bind, timeout, endpoint)
        if called:
            return return_value
        else:
            self._connection(BIND, endpoint, timeout)
    
    def unbind(self, str endpoint, int timeout=1000):
        """Unbind this socket from a ZMQ endpoint in a threadsafe manner."""
        called, return_value = self._preflight_call(self.client.unbind, timeout, endpoint)
        if called:
            return return_value
        else:
            return self._connection(BIND | DROP, endpoint, timeout)
    
    def connect(self, str endpoint, int timeout=1000):
        """Connect this socket to a ZMQ endpoint in a threadsafe manner."""
        # Handle the case where the loop isn't running yet.
        called, return_value = self._preflight_call(self.client.connect, timeout, endpoint)
        if called:
            return return_value
        else:
            return self._connection(CONNECT, endpoint, timeout)
    
    def disconnect(self, str endpoint, int timeout=1000):
        """Disconnect this socket from a ZMQ endpoint in a threadsafe manner."""
        called, return_value = self._preflight_call(self.client.disconnect, timeout, endpoint)
        if called:
            return return_value
        else:
            self._connection(CONNECT | DROP, endpoint, timeout)
    
    def set(self, int option, object optval, int timeout=1000):
        """Set a specific socket option.
        
        :param int option: The option to set.
        :param key: The option value.
        :param int timeout: Response timeout, in milliseconds.
        
        """
        cdef bytes optval_c
        cdef bytes option_c
        
        if not self._is_loop_running():
            with self._inuse.timeout(timeout):
                return self.client.setsockopt(option, optval)
            # raise SocketOptionError("Can't set a socket option. The underlying I/O Loop is not running.")
        
        option_c = PyBytes_FromStringAndSize(<char *>&option, sizeof(int))
        optval_c = zmq_invert_sockopt(option, optval)
        
        result = self._optmessage(SET, [option_c, optval_c], timeout)
        reply_option = s.unpack("i", result)[0]
        if reply_option != option:
            raise SocketOptionError("Reply did not match requested socket option.")
        return
    
    def get(self, int option, int timeout=1000):
        """Get a socket option.
        
        :param int option: The socket option to set.
        :param int timeout: Response timeout, in milliseconds.
        
        """
        cdef bytes optval_c
        cdef bytes optsize_c
        cdef size_t optsize
        
        if not self._is_loop_running():
            with self._inuse.timeout(timeout):
                return self.client.getsockopt(option)
            # raise SocketOptionError("Can't get a socket option. The underlying I/O Loop is not running.")
        
        option_c = PyBytes_FromStringAndSize(<char *>&option, sizeof(int))
        
        optsize = zmq_size_sockopt(option)
        optsize_c = PyBytes_FromStringAndSize(<char *>&optsize, sizeof(size_t))
        
        result = self._optmessage(GET, [option_c, optsize_c], timeout)
        response = zmq_convert_sockopt(option, &(<Frame>result).zmq_msg)
        return response
    
    def subscribe(self, key):
        """Subscribe to a channel"""
        assert_socket_is_sub(self.client)
        key = sandwich_unicode(key)
        if key in self.subscriptions:
            return
        self.subscriptions.add(key)
        self.set(zmq.SUBSCRIBE, key)

    def unsubscribe(self, key):
        """Unsubscribe from a specific channel."""
        assert_socket_is_sub(self.client)
        key = sandwich_unicode(key)
        if key not in self.subscriptions:
            raise ValueError("Can't unsubscribe from {0:s}, not subscribed.".format(key.encode('utf-8')))
        self.set(zmq.UNSUBSCRIBE, key)
        self.subscriptions.discard(key)    
    
    def unsubscribe_all(self):
        """Unsubscribe from all subscriptions"""
        assert_socket_is_sub(self.client)
        for key in list(self.subscriptions):
            self.unsubscribe(key)
    
    def _start(self):
        """Start the socket with subscriptions"""
        super(SocketOptions, self)._start()
        self._resubscribe()

    
    cdef int paused(self) nogil except -1:
        """Function called when the loop has paused."""
        return 0

    cdef int resumed(self) nogil except -1:
        """Function called when the loop is resumed."""
        with gil:
            self._resubscribe()
        
    def _resubscribe(self):
        if self.client.type == zmq.SUB:
            if self.subscriptions:
                for s in self.subscriptions:
                    self.client.subscribe(s)
            elif self.autosubscribe:
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
        return collections.MutableMapping.pop(self.target, key, default)
    
    def popitem(self):
        """Remove and return an arbitrary `(key, value)` pair from the dictionary."""
        return collections.MutableMapping.popitem(self.target)
    
    def setdefault(self, key, value):
        """If `key` is in the dictionary, return its `value`. If not, insert `key` with a value of `default` and return `default`. `default` defaults to `None`."""
        return collections.MutableMapping.setdefault(self.target, key, value)
    
    def update(self, other):
        """Update the dictionary with the key/value pairs from `other`, overwriting existing keys. Return `None`."""
        return collections.MutableMapping.update(self.target, other)
    
    def clear(self):
        """Remove all values from the dictionary."""
        return collections.MutableMapping.clear(self.target)
