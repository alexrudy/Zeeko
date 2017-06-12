#cython: embedsignature=True

# Standard C imports
from libc.stdlib cimport free, malloc
from libc.string cimport memcpy

# External cimports
from cpython.bytes cimport PyBytes_FromStringAndSize
cimport numpy as np
import numpy as np

# ZMQ Imports
from zmq.backend.cython.socket cimport Socket
from zmq.utils import jsonapi

# Internal cimports
from .carray cimport new_named_array, close_named_array
from .carray cimport copy_named_array, send_named_array, receive_named_array
from .carray cimport carray_named, carray_message_info

# Utilities
from .utils cimport check_rc, check_ptr
from ..utils.clock cimport current_time
from ..utils.sandwich import sandwich_unicode, unsandwich_unicode
from .. import ZEEKO_PROTOCOL_VERSION

__all__ = ['ArrayMessage']

#TODO: Deprecate these
cdef int zmq_msg_from_str(libzmq.zmq_msg_t * zmsg, char[:] src):
    """Construct a ZMQ message from a string."""
    cdef int rc
    cdef void * zmsg_data
    rc = libzmq.zmq_msg_init_size(zmsg, len(src))
    check_rc(rc)
    
    zmsg_data = libzmq.zmq_msg_data(zmsg)
    memcpy(zmsg_data, &src[0], len(src))
    return rc

cdef str zmq_msg_to_str(libzmq.zmq_msg_t * msg):
    """Construct a string from a ZMQ message."""
    return unsandwich_unicode(PyBytes_FromStringAndSize(<char *>libzmq.zmq_msg_data(msg), <Py_ssize_t>libzmq.zmq_msg_size(msg)))

cdef class ArrayMessage:
    """A single array which is sent or received over a streaming socket.

    This class exposes the collection of ZMQ messages for this array
    as python objects.

    It exposes the buffer interface, which can be used to access the
    memory used for array data. As well, properties represent different
    message components.
    """

    def __cinit__(self):
        # Initialize only C variables here.
        new_named_array(&self._message)
        self._shape = ()
        self._dtype = None
        self._readonly = True
    
    def __dealloc__(self):
        close_named_array(&self._message)
        
    
    def __init__(self, name, data):
        # Initialize with new values.
        self._construct_name(bytearray(sandwich_unicode(name)))
        data = np.asarray(data)
        self._frame = Frame(data=data)
        self._readonly = False
        self._construct_metadata(data)
        self._construct_data()
        self._construct_info()
        
    def __repr__(self):
        return "<{0:s} {1:s} ({2:s}) at {3:d}>".format(
            self.__class__.__name__, self.name, "x".join(["{0:d}".format(s) for s in self.shape]),
            self.framecount) 
        
    def _construct_name(self, char[:] name):
        cdef int rc
        
        rc = libzmq.zmq_msg_close(&self._message.name)
        check_rc(rc)
        
        rc = zmq_msg_from_str(&self._message.name, name)
        check_rc(rc)
        
    def _construct_metadata(self, np.ndarray data):
        """Construct the metadata message."""
        cdef int rc
        cdef char[:] metadata
        cdef bytes metadata_str
        cdef void * msg_data
        A = <object>data
        
        metadata = bytearray(sandwich_unicode(jsonapi.dumps(dict(shape=A.shape, dtype=A.dtype.str, version=ZEEKO_PROTOCOL_VERSION))))
        
        rc = libzmq.zmq_msg_close(&self._message.array.metadata)
        check_rc(rc)
        
        rc = zmq_msg_from_str(&self._message.array.metadata, metadata)
        check_rc(rc)
        self._parse_metadata()
        
    def _construct_data(self):
        """Construct the data message."""
        cdef int rc
        rc = libzmq.zmq_msg_copy(&self._message.array.data, &self._frame.zmq_msg)
        check_rc(rc)
        
    def _construct_info(self):
        """Construct informational message"""
        cdef int rc
        cdef carray_message_info * info
        rc = libzmq.zmq_msg_close(&self._message.array.info)
        check_rc(rc)
        
        rc = libzmq.zmq_msg_init_size(&self._message.array.info, sizeof(carray_message_info))
        check_rc(rc)
        
        info = <carray_message_info *>libzmq.zmq_msg_data(&self._message.array.info)
        info.framecount = 0
        info.timestamp = current_time()

    # Implement buffer interface
    # These four methods handle both the old-style (buffer)
    # and new-style (memoryview) buffer interface for python.
    
    def __getbuffer__(self, Py_buffer* buffer, int flags):
        buffer.buf = libzmq.zmq_msg_data(&self._message.array.data)
        buffer.len = libzmq.zmq_msg_size(&self._message.array.data)

        buffer.obj = self
        buffer.readonly = <int>self._readonly
        buffer.format = "B"
        buffer.ndim = 1
        buffer.shape = &(buffer.len)
        buffer.strides = NULL
        buffer.suboffsets = NULL
        buffer.itemsize = 1
        buffer.internal = NULL
        
    def __releasebuffer__(self, Py_buffer *buffer):
        pass
        
    def __getsegcount__(self, Py_ssize_t *lenp):
        # required for getreadbuffer
        if lenp != NULL:
            lenp[0] = libzmq.zmq_msg_size(&self._message.array.data)
        return 1

    def __getreadbuffer__(self, Py_ssize_t idx, void **p):
        # old-style (buffer) interface
        cdef void *data = NULL
        cdef Py_ssize_t data_len_c
        if idx != 0:
            raise SystemError("accessing non-existent buffer segment")
        # read-only, because we don't want to allow
        # editing of the message in-place
        data_len_c = libzmq.zmq_msg_size(&self._message.array.data)
        if p != NULL:
            p[0] = libzmq.zmq_msg_data(&self._message.array.data)
        return data_len_c
    
    def __getwritebuffer__(self, Py_ssize_t idx, void **p):
        cdef void *data = NULL
        cdef Py_ssize_t data_len_c
        if self._readonly:
            raise TypeError("This message only supports readonly buffers.")
        if idx != 0:
            raise SystemError("accessing non-existent buffer segment")
        # read-only, because we don't want to allow
        # editing of the message in-place
        data_len_c = libzmq.zmq_msg_size(&self._message.array.data)
        if p != NULL:
            p[0] = libzmq.zmq_msg_data(&self._message.array.data)
        return data_len_c
    
    property array:
        """The numpy array underneath this message."""
        def __get__(self):
            view = np.frombuffer(self, dtype=self.dtype)
            return view.reshape(self.shape)
    
    property name:
        """The name of this array for messaging."""
        def __get__(self):
            return zmq_msg_to_str(&self._message.name)

    property metadata:
        """JSON-formatted array metadata."""
        def __get__(self):
            return zmq_msg_to_str(&self._message.array.metadata)
            
    property md:
        """JSON loaded metadata"""
        def __get__(self):
            return jsonapi.loads(self.metadata)
    
    def _parse_metadata(self):
        """Internal function to parse the JSON metadata."""
        try:
            meta = jsonapi.loads(self.metadata)
        except ValueError as e:
            raise ValueError("Can't decode JSON in {!r}".format(self.metadata))
        self._shape = tuple(meta['shape'])
        self._dtype = np.dtype(meta['dtype'])

    property shape:
        """The shape of the array in this message."""
        def __get__(self):
            self._parse_metadata()
            return self._shape

    property dtype:
        """The datatype of the array in this message."""
        def __get__(self):
            self._parse_metadata()
            return self._dtype

    property framecount:
        """The message framecount."""
        def __get__(self):
            cdef carray_message_info * info
            info = <carray_message_info *>libzmq.zmq_msg_data(&self._message.array.info)
            return info.framecount

    property timestamp:
        """The message timestamp."""
        def __get__(self):
            cdef carray_message_info * info
            info = <carray_message_info *>libzmq.zmq_msg_data(&self._message.array.info)
            return info.timestamp
    
    cdef int update_info(self, unsigned long framecount) nogil except -1:
        """Update the info structure with a new framecount."""
        cdef int rc
        cdef carray_message_info * info
        info = <carray_message_info *>libzmq.zmq_msg_data(&self._message.array.info)
        info.framecount = framecount
        info.timestamp = current_time()
        return 0
    
    cdef int tick(self) nogil except -1:
        """Tick the framecount up one, and set the send time."""
        cdef int rc = 0
        cdef carray_message_info * info
    
        info = <carray_message_info *>libzmq.zmq_msg_data(&self._message.array.info)
        check_ptr(info)
        info.framecount = info.framecount + 1
        info.timestamp = current_time()
        return rc
    
    def send(self, Socket socket, int flags = 0):
        """Send the array over a ZMQ socket."""
        cdef void * handle = socket.handle
        with nogil:
            rc = self.tick()
            rc = send_named_array(&self._message, handle, flags)
        check_rc(rc)
    
    @staticmethod
    cdef ArrayMessage from_message(carray_named * message):
        cdef ArrayMessage obj = ArrayMessage.__new__(ArrayMessage)
        copy_named_array(&obj._message, message)
        return obj
    
    @classmethod
    def receive(cls, Socket socket, int flags = 0):
        """Receive an array over a ZMQ socket."""
        cdef carray_named * message
        cdef int rc
        cdef void * handle = socket.handle
    
        message = <carray_named *>malloc(sizeof(carray_named))
    
        if message is NULL:
            raise MemoryError("Couldn't allocate named array message.")
    
        rc = new_named_array(message)
        rc = receive_named_array(message, handle, flags)
        obj = ArrayMessage.from_message(message)
        close_named_array(message)
        free(message)
        return obj