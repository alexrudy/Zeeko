
# -----------------------------------------------------------------------------
# Cython Imorts
cimport numpy as np

from libc.string cimport memcpy, memcmp, memset

# ZMQ Cython imports
cimport zmq.backend.cython.libzmq as libzmq
from zmq.backend.cython.socket cimport Socket
from zmq.backend.cython.message cimport Frame
from zmq.utils.buffers cimport viewfromobject_r

from ..utils.rc cimport check_zmq_rc, check_zmq_ptr
from ..utils.msg cimport zmq_msg_to_str, zmq_msg_from_str

from ..messages.message cimport ArrayMessage

# -----------------------------------------------------------------------------
# Python Imorts
import numpy as np
from zmq.utils import jsonapi
from .. import ZEEKO_PROTOCOL_VERSION
from . import io
from ..utils.sandwich import sandwich_unicode, unsandwich_unicode

__all__ = ['Chunk']

cdef int chunk_init(array_chunk * chunk) nogil except -1:
    """
    Initialize empty messages required for handling chunks.
    """
    cdef int rc = 0
    chunk.chunksize = 0
    chunk.stride = 0
    chunk.last_index = 0
    rc = libzmq.zmq_msg_init(&chunk.mask)
    check_zmq_rc(rc)
    
    rc = libzmq.zmq_msg_init(&chunk.data)
    check_zmq_rc(rc)
    
    rc = libzmq.zmq_msg_init(&chunk.metadata)
    check_zmq_rc(rc)
    
    rc = libzmq.zmq_msg_init(&chunk.name)
    check_zmq_rc(rc)
    
    return rc


cdef int chunk_init_array(array_chunk * chunk, carray_named * array, size_t chunksize) nogil except -1:
    """
    Initialize the messages required for handling chunks.
    """
    cdef int rc = 0
    cdef size_t size = 0
    cdef void * src
    cdef void * dst
    chunk.last_index = 0
    chunk.chunksize = chunksize
    rc = libzmq.zmq_msg_init_size(&chunk.mask, chunksize * sizeof(DINT_t))
    check_zmq_rc(rc)
    dst = libzmq.zmq_msg_data(&chunk.mask)
    memset(dst, <DINT_t>-1, chunksize * sizeof(DINT_t))
    
    size = libzmq.zmq_msg_size(&array.array.data)
    chunk.stride = size
    rc = libzmq.zmq_msg_init_size(&chunk.data, chunksize * size)
    check_zmq_rc(rc)
    
    size = libzmq.zmq_msg_size(&array.array.metadata)
    rc = libzmq.zmq_msg_init_size(&chunk.metadata, size)
    check_zmq_rc(rc)
    
    src = libzmq.zmq_msg_data(&array.array.metadata)
    dst = libzmq.zmq_msg_data(&chunk.metadata)
    memcpy(dst, src, size)
    
    size = libzmq.zmq_msg_size(&array.name)
    rc = libzmq.zmq_msg_init_size(&chunk.name, size)
    check_zmq_rc(rc)
    
    src = libzmq.zmq_msg_data(&array.name)
    dst = libzmq.zmq_msg_data(&chunk.name)
    memcpy(dst, src, size)
    
    
    return rc
    
cdef int chunk_copy(array_chunk * dest, array_chunk * src) nogil except -1:
    """
    Copy a chunk and chunk info to a new structure.
    """
    cdef int rc = 0
    dest.chunksize = src.chunksize
    dest.stride = src.stride
    dest.last_index = src.last_index
    rc = libzmq.zmq_msg_copy(&dest.mask, &src.mask)
    check_zmq_rc(rc)
    rc = libzmq.zmq_msg_copy(&dest.data, &src.data)
    check_zmq_rc(rc)
    rc = libzmq.zmq_msg_copy(&dest.metadata, &src.metadata)
    check_zmq_rc(rc)
    rc = libzmq.zmq_msg_copy(&dest.name, &src.name)
    check_zmq_rc(rc)
    
    return rc

cdef int chunk_append(array_chunk * chunk, carray_named * array, size_t index, DINT_t framecount) nogil except -1:
    """
    Append data to a chunk at a given index position.
    """
    cdef int rc = 0
    cdef size_t size = 0
    cdef void * data
    cdef DINT_t * mask
    
    size = libzmq.zmq_msg_size(&chunk.metadata)
    if libzmq.zmq_msg_size(&array.array.metadata) != size:
        with gil:
            raise ValueError("Metadata size is different. ({0:s}) {1!r} -> {2!r}".format(
                zmq_msg_to_str(&chunk.name), zmq_msg_to_str(&chunk.metadata), zmq_msg_to_str(&array.array.metadata)))
    rc = memcmp(libzmq.zmq_msg_data(&chunk.metadata), libzmq.zmq_msg_data(&array.array.metadata), size)
    if rc != 0:
        with gil:
            raise ValueError("Metadata does not match! ({0:s}) {1!r} -> {2!r}".format(
                zmq_msg_to_str(&chunk.name), zmq_msg_to_str(&chunk.metadata), zmq_msg_to_str(&array.array.metadata)))
    
    size = libzmq.zmq_msg_size(&array.array.data)
    if index >= chunk.chunksize:
        with gil:
            raise IndexError("Trying to append beyond end of chunk ({0:s}). {1:d} > {2:d} (l={3:d})".format(
                             zmq_msg_to_str(&chunk.name), index, chunk.chunksize, chunk.last_index))
    if size > chunk.stride:
        with gil:
            raise IndexError("Trying to append an array larger than the stride ({0:s}). {1:d} > {2:d}".format(
                             zmq_msg_to_str(&chunk.name), size, chunk.stride))
    
    
    data = libzmq.zmq_msg_data(&chunk.data)
    memcpy(&data[index * chunk.stride], libzmq.zmq_msg_data(&array.array.data), size)
    mask = <DINT_t *>libzmq.zmq_msg_data(&chunk.mask)
    mask[index] = framecount
    chunk.last_index = index
    return 0
    
cdef int chunk_close(array_chunk * chunk) nogil except -1:
    """
    Close chunk messages, making the chunk ready for garbage collection.
    """
    cdef int rc = 0
    if &chunk.data is not NULL:
        rc = libzmq.zmq_msg_close(&chunk.data)
        check_zmq_rc(rc)
    if &chunk.mask is not NULL:
        rc = libzmq.zmq_msg_close(&chunk.mask)
        check_zmq_rc(rc)
    if &chunk.name is not NULL:
        rc = libzmq.zmq_msg_close(&chunk.name)
        check_zmq_rc(rc)
    if &chunk.metadata is not NULL:
        rc = libzmq.zmq_msg_close(&chunk.metadata)
        check_zmq_rc(rc)
    return rc

cdef int chunk_send(array_chunk * chunk, void * socket, int flags) nogil except -1:
    """
    Send a numpy array chunk a ZMQ socket.
    Requires an array prepared with as an array_chunk.
    """
    cdef int rc = 0
    cdef libzmq.zmq_msg_t zmessage, zmetadata, zname, zmask
    
    rc = libzmq.zmq_msg_init(&zname)
    check_zmq_rc(rc)
    libzmq.zmq_msg_copy(&zname, &chunk.name)
    rc = libzmq.zmq_msg_send(&zname, socket, flags|libzmq.ZMQ_SNDMORE)
    check_zmq_rc(rc)
    
    rc = libzmq.zmq_msg_init(&zmetadata)
    check_zmq_rc(rc)
    libzmq.zmq_msg_copy(&zmetadata, &chunk.metadata)
    rc = libzmq.zmq_msg_send(&zmetadata, socket, flags|libzmq.ZMQ_SNDMORE)
    check_zmq_rc(rc)
    
    rc = libzmq.zmq_msg_init(&zmessage)
    check_zmq_rc(rc)
    libzmq.zmq_msg_copy(&zmessage, &chunk.data)
    rc = libzmq.zmq_msg_send(&zmessage, socket, flags|libzmq.ZMQ_SNDMORE)
    check_zmq_rc(rc)
    
    rc = libzmq.zmq_msg_init(&zmask)
    check_zmq_rc(rc)
    libzmq.zmq_msg_copy(&zmask, &chunk.mask)
    rc = libzmq.zmq_msg_send(&zmask, socket, flags)
    check_zmq_rc(rc)

    return rc

cdef int chunk_recv(array_chunk * chunk, void * socket, int flags) nogil except -1:
    """
    Receive a known, already allocated message object. Ensures that the message will
    be received entirely.
    """
    cdef int rc
    
    # Recieve the name message
    rc = libzmq.zmq_msg_recv(&chunk.name, socket, flags)
    check_zmq_rc(rc)
    
    # Recieve the metadata message
    rc = libzmq.zmq_msg_recv(&chunk.metadata, socket, flags)
    check_zmq_rc(rc)

    # Recieve the array data.
    rc = libzmq.zmq_msg_recv(&chunk.data, socket, flags)
    check_zmq_rc(rc)
    
    # Recieve the mask
    rc = libzmq.zmq_msg_recv(&chunk.mask, socket, flags)
    check_zmq_rc(rc)
    
    return rc

cdef class Chunk:
    """A chunk is a record of contiguous array messages.
    
    Array messages are collected together to form a single bundle,
    which can be writen to disk."""
    
    def __cinit__(self):
        chunk_init(&self._chunk)
    
    def __init__(self, str name, np.ndarray data, mask):
        cdef int stride = np.prod((<object>data).shape[1:])
        cdef int chunksize = data.shape[0]
        cdef int rc = 0
        
        #Initialize name
        self._construct_name(bytearray(sandwich_unicode(name)))
        
        #Initialize the chunk structure.
        self._chunk.chunksize = chunksize
        self._chunk.stride = data.dtype.itemsize * stride
        self._data_frame = Frame(data=np.asanyarray(data), copy=False)
        rc = libzmq.zmq_msg_copy(&self._chunk.data, &self._data_frame.zmq_msg)
        check_zmq_rc(rc)
        
        self._mask_frame = Frame(data=np.asanyarray(mask), copy=False)
        rc = libzmq.zmq_msg_copy(&self._chunk.mask, &self._mask_frame.zmq_msg)
        check_zmq_rc(rc)
        
        self._construct_metadata(np.asarray(data))
        self._chunk.last_index = self.lastindex
        
    def _construct_name(self, char[:] name):
        cdef int rc
        rc = libzmq.zmq_msg_close(&self._chunk.name)
        check_zmq_rc(rc)
    
        rc = zmq_msg_from_str(&self._chunk.name, name)
        check_zmq_rc(rc)
        
    def _construct_metadata(self, np.ndarray data):
        """Construct the metadata message."""
        cdef int rc
        cdef char[:] metadata
        cdef void * msg_data
        A = <object>data
        metadata = bytearray(sandwich_unicode(jsonapi.dumps(dict(shape=A.shape[1:], dtype=A.dtype.str, version=ZEEKO_PROTOCOL_VERSION))))
        
        rc = libzmq.zmq_msg_close(&self._chunk.metadata)
        check_zmq_rc(rc)
        
        rc = zmq_msg_from_str(&self._chunk.metadata, metadata)
        check_zmq_rc(rc)
        self._parse_metadata()
        
    def __dealloc__(self):
        chunk_close(&self._chunk)
    
    def __repr__(self):
        return "<{0:s} ({1:s})x({2:d}) at {3:d}>".format(
            self.__class__.__name__, "x".join(["{0:d}".format(s) for s in self.shape]),
            self.chunksize, self.lastindex + 1) 
    
    @staticmethod
    cdef Chunk from_chunk(array_chunk * chunk):
        cdef Chunk obj = Chunk.__new__(Chunk)
        chunk_copy(&obj._chunk, chunk)
        return obj
        
    def copy(self):
        """Make a shallow copy of this chunk object."""
        cdef Chunk obj = Chunk.__new__(Chunk)
        chunk_copy(&obj._chunk, &self._chunk)
        return obj

    property array:
        """The array of chunk data."""
        def __get__(self):
            cdef Frame msg = Frame()
            libzmq.zmq_msg_copy(&msg.zmq_msg, &self._chunk.data)
            view = np.frombuffer(msg, dtype=self.dtype)
            return view.reshape((self.chunksize,) + self.shape)
    
    property name:
        """Name of the chunk."""
        def __get__(self):
            return zmq_msg_to_str(&self._chunk.name)

    property metadata:
        """Metadata, as a JSON-encoded string, for the chunk."""
        def __get__(self):
            return zmq_msg_to_str(&self._chunk.metadata)
            
    property mask:
        """Mask, identifying valid parts of the array."""
        def __get__(self):
            cdef Frame mask = Frame()
            libzmq.zmq_msg_copy(&mask.zmq_msg, &self._chunk.mask)
            return np.frombuffer(mask, dtype=np.int64)
            
    property chunksize:
        """Number of array messages in a single chunk."""
        def __get__(self):
            return self.mask.shape[0]
        
    def _parse_metadata(self):
        try:
            meta = jsonapi.loads(self.metadata)
        except ValueError as e:
            raise ValueError("Can't decode JSON in {0!r}".format(self.metadata))
        self._shape = tuple(meta['shape'])
        self._dtype = np.dtype(meta['dtype'])
    
    property md:
        """The metadata dictionary."""
        def __get__(self):
            return dict(shape=self.shape, dtype=self.dtype.str, version=ZEEKO_PROTOCOL_VERSION)
            

    property shape:
        """Shape of the input array message."""
        def __get__(self):
            self._parse_metadata()
            return self._shape

    property dtype:
        """Array datatype."""
        def __get__(self):
            self._parse_metadata()
            return self._dtype
            
    property stride:
        """Array stride."""
        def __get__(self):
            return np.prod(self.shape)
            
    property lastindex:
        """The highest valid index in the array."""
        def __get__(self):
            return self.mask.shape[0] - np.argmax(self.mask[::-1] >= 0) - 1
            
    property _lastindex:
        def __get__(self):
            return self._chunk.last_index
        
    def send(self, Socket socket, int flags=0):
        """Send this entire chunk over a ZeroMQ Socket."""
        cdef void * handle = socket.handle
        with nogil:
            rc = chunk_send(&self._chunk, handle, flags)
        check_zmq_rc(rc)
    
    def append(self, array, framecount=None):
        """Append a numpy array to the chunk."""
        cdef DINT_t fc
        cdef size_t index = self.lastindex + 1
        msg = ArrayMessage(self.name, array)
        if framecount is None:
            framecount = msg.framecount
        fc = <DINT_t> framecount
        with nogil:
            chunk_append(&self._chunk, &msg._message, index, fc)
    
    def write(self, g, **kwargs):
        """
        Write a dataset to HDF5, either by extending an exisitng dataset or creating a new one.
    
        Note that empty datasets will be created as a group.
        """
        io.write(self, g, **kwargs)
    

    