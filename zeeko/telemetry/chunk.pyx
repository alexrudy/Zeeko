
cimport numpy as np
import numpy as np

from libc.string cimport memcpy, memcmp, memset
from zmq.backend.cython.socket cimport Socket
from ..messages.utils cimport check_rc, check_ptr
from ..messages.message cimport zmq_msg_to_str, zmq_msg_from_str, ArrayMessage
from cpython.string cimport PyString_FromStringAndSize
from zmq.utils import jsonapi
cimport zmq.backend.cython.libzmq as libzmq
from zmq.utils.buffers cimport viewfromobject_r
from zmq.backend.cython.message cimport Frame
from .. import ZEEKO_PROTOCOL_VERSION

cdef int chunk_init(array_chunk * chunk) nogil except -1:
    """
    Initialize empty messages required for handling chunks.
    """
    cdef int rc = 0
    chunk.chunksize = 0
    chunk.stride = 0
    rc = libzmq.zmq_msg_init(&chunk.mask)
    check_rc(rc)
    
    rc = libzmq.zmq_msg_init(&chunk.data)
    check_rc(rc)
    
    rc = libzmq.zmq_msg_init(&chunk.metadata)
    check_rc(rc)
    
    rc = libzmq.zmq_msg_init(&chunk.name)
    check_rc(rc)
    
    return rc


cdef int chunk_init_array(array_chunk * chunk, carray_named * array, size_t chunksize) nogil except -1:
    """
    Initialize the messages required for handling chunks.
    """
    cdef int rc = 0
    cdef size_t size = 0
    cdef void * src
    cdef void * dst
    chunk.chunksize = chunksize
    rc = libzmq.zmq_msg_init_size(&chunk.mask, chunksize * sizeof(DINT_t))
    check_rc(rc)
    dst = libzmq.zmq_msg_data(&chunk.mask)
    memset(dst, 0, chunksize * sizeof(DINT_t))
    
    size = libzmq.zmq_msg_size(&array.array.data)
    chunk.stride = size
    rc = libzmq.zmq_msg_init_size(&chunk.data, chunksize * size)
    check_rc(rc)
    
    size = libzmq.zmq_msg_size(&array.array.metadata)
    rc = libzmq.zmq_msg_init_size(&chunk.metadata, size)
    check_rc(rc)
    
    src = libzmq.zmq_msg_data(&array.array.metadata)
    dst = libzmq.zmq_msg_data(&chunk.metadata)
    memcpy(dst, src, size)
    
    size = libzmq.zmq_msg_size(&array.name)
    rc = libzmq.zmq_msg_init_size(&chunk.name, size)
    check_rc(rc)
    
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
    rc = libzmq.zmq_msg_copy(&dest.mask, &src.mask)
    check_rc(rc)
    rc = libzmq.zmq_msg_copy(&dest.data, &src.data)
    check_rc(rc)
    rc = libzmq.zmq_msg_copy(&dest.metadata, &src.metadata)
    check_rc(rc)
    rc = libzmq.zmq_msg_copy(&dest.name, &src.name)
    check_rc(rc)
    
    return rc

cdef int chunk_append(array_chunk * chunk, carray_named * array, size_t index) nogil except -1:
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
            raise ValueError("Metadata size is different. {!r} -> {!r}".format(
                zmq_msg_to_str(&chunk.metadata), zmq_msg_to_str(&array.array.metadata)))
    rc = memcmp(libzmq.zmq_msg_data(&chunk.metadata), libzmq.zmq_msg_data(&array.array.metadata), size)
    if rc != 0:
        with gil:
            raise ValueError("Metadata does not match! {!r} -> {!r}".format(
                zmq_msg_to_str(&chunk.metadata), zmq_msg_to_str(&array.array.metadata)))
    
    size = libzmq.zmq_msg_size(&array.array.data)
    if index >= chunk.chunksize:
        with gil:
            raise IndexError("Trying to append beyond end of chunk. {:d} > {:d}".format(index, chunk.chunksize))
    if size > chunk.stride:
        with gil:
            raise IndexError("Trying to append an array larger than the stride. {:d} > {:d}".format(size, chunk.stride))
    
    
    data = libzmq.zmq_msg_data(&chunk.data)
    memcpy(&data[index * chunk.stride], libzmq.zmq_msg_data(&array.array.data), size)
    mask = <DINT_t *>libzmq.zmq_msg_data(&chunk.mask)
    mask[index] = <DINT_t>(index + 1)
    return 0
    
cdef int chunk_close(array_chunk * chunk) nogil except -1:
    """
    Close chunk messages, making the chunk ready for garbage collection.
    """
    cdef int rc = 0
    rc = libzmq.zmq_msg_close(&chunk.data)
    check_rc(rc)
    rc = libzmq.zmq_msg_close(&chunk.mask)
    check_rc(rc)
    rc = libzmq.zmq_msg_close(&chunk.name)
    check_rc(rc)
    rc = libzmq.zmq_msg_close(&chunk.metadata)
    check_rc(rc)
    return rc

cdef int chunk_send(array_chunk * chunk, void * socket, int flags) nogil except -1:
    """
    Send a numpy array chunk a ZMQ socket.
    Requires an array prepared with as an array_chunk.
    """
    cdef int rc = 0
    cdef libzmq.zmq_msg_t zmessage, zmetadata, zname, zmask
    
    rc = libzmq.zmq_msg_init(&zname)
    check_rc(rc)
    libzmq.zmq_msg_copy(&zname, &chunk.name)
    rc = libzmq.zmq_msg_send(&zname, socket, flags|libzmq.ZMQ_SNDMORE)
    check_rc(rc)
    
    rc = libzmq.zmq_msg_init(&zmetadata)
    check_rc(rc)
    libzmq.zmq_msg_copy(&zmetadata, &chunk.metadata)
    rc = libzmq.zmq_msg_send(&zmetadata, socket, flags|libzmq.ZMQ_SNDMORE)
    check_rc(rc)
    
    rc = libzmq.zmq_msg_init(&zmessage)
    check_rc(rc)
    libzmq.zmq_msg_copy(&zmessage, &chunk.data)
    rc = libzmq.zmq_msg_send(&zmessage, socket, flags|libzmq.ZMQ_SNDMORE)
    check_rc(rc)
    
    rc = libzmq.zmq_msg_init(&zmask)
    check_rc(rc)
    libzmq.zmq_msg_copy(&zmask, &chunk.mask)
    rc = libzmq.zmq_msg_send(&zmask, socket, flags)
    check_rc(rc)

    return rc

cdef int chunk_recv(array_chunk * chunk, void * socket, int flags) nogil except -1:
    """
    Receive a known, already allocated message object. Ensures that the message will
    be received entirely.
    """
    cdef int rc
    
    # Recieve the name message
    rc = libzmq.zmq_msg_recv(&chunk.name, socket, flags)
    check_rc(rc)
    
    # Recieve the metadata message
    rc = libzmq.zmq_msg_recv(&chunk.metadata, socket, flags)
    check_rc(rc)

    # Recieve the array data.
    rc = libzmq.zmq_msg_recv(&chunk.data, socket, flags)
    check_rc(rc)
    
    # Recieve the mask
    rc = libzmq.zmq_msg_recv(&chunk.mask, socket, flags)
    check_rc(rc)
    
    return rc

cdef class Chunk:
    
    def __cinit__(self):
        chunk_init(&self._chunk)
    
    def __init__(self, str name, np.ndarray data, mask):
        cdef int stride = np.prod((<object>data).shape[1:])
        cdef int chunksize = data.shape[0]
        cdef int rc = 0
        
        #Initialize the chunk structure.
        self._chunk.chunksize = chunksize
        self._chunk.stride = data.dtype.itemsize * stride
        self._data_frame = Frame(data=np.asanyarray(data))
        rc = libzmq.zmq_msg_copy(&self._chunk.data, &self._data_frame.zmq_msg)
        check_rc(rc)
        
        self._mask_frame = Frame(data=np.asanyarray(mask))
        rc = libzmq.zmq_msg_copy(&self._chunk.mask, &self._mask_frame.zmq_msg)
        check_rc(rc)
        
        self._construct_metadata(np.asarray(data))
        
        
    def _construct_metadata(self, np.ndarray data):
        """Construct the metadata message."""
        cdef int rc
        cdef char[:] metadata
        cdef void * msg_data
        A = <object>data
        metadata = bytearray(jsonapi.dumps(dict(shape=A.shape[1:], dtype=A.dtype.str, version=ZEEKO_PROTOCOL_VERSION)))
        
        rc = libzmq.zmq_msg_close(&self._chunk.metadata)
        check_rc(rc)
        
        rc = zmq_msg_from_str(&self._chunk.metadata, metadata)
        check_rc(rc)
        self._parse_metadata()
        
    def __dealloc__(self):
        chunk_close(&self._chunk)
    
    
    @staticmethod
    cdef Chunk from_chunk(array_chunk * chunk):
        cdef Chunk obj = Chunk.__new__(Chunk)
        chunk_copy(&obj._chunk, chunk)
        return obj

    property array:
        def __get__(self):
            cdef Frame msg = Frame()
            libzmq.zmq_msg_copy(&msg.zmq_msg, &self._chunk.data)
            view = np.frombuffer(msg, dtype=self.dtype)
            return view.reshape((self.chunksize,) + self.shape)
    
    property name:
        def __get__(self):
            return zmq_msg_to_str(&self._chunk.name)

    property metadata:
        def __get__(self):
            return zmq_msg_to_str(&self._chunk.metadata)
            
    property mask:
        def __get__(self):
            cdef Frame mask = Frame()
            libzmq.zmq_msg_copy(&mask.zmq_msg, &self._chunk.mask)
            return np.frombuffer(mask, dtype=np.int32)
            
    property chunksize:
        def __get__(self):
            return self.mask.shape[0]
        
    def _parse_metadata(self):
        try:
            meta = jsonapi.loads(self.metadata)
        except ValueError as e:
            raise ValueError("Can't decode JSON in {!r}".format(self.metadata))
        self._shape = tuple(meta['shape'])
        self._dtype = np.dtype(meta['dtype'])
    
    property md:
        def __get__(self):
            return dict(shape=self.shape, dtype=self.dtype.str, version=ZEEKO_PROTOCOL_VERSION)
            

    property shape:
        def __get__(self):
            self._parse_metadata()
            return self._shape

    property dtype:
        def __get__(self):
            self._parse_metadata()
            return self._dtype
            
    property stride:
        def __get__(self):
            return np.prod(self.shape)
            
    property lastindex:
        def __get__(self):
            return np.argmax(self.mask)
        
    def send(self, Socket socket, int flags=0):
        cdef void * handle = socket.handle
        with nogil:
            rc = chunk_send(&self._chunk, handle, flags)
        check_rc(rc)
    
    def append(self, array):
        """Append a numpy array to the chunk."""
        cdef size_t index = self.lastindex + 1
        msg = ArrayMessage(self.name, array)
        with nogil:
            chunk_append(&self._chunk, &msg._message, index)
        
    cdef int extend(self, g) except -1:
        """Extend an existing H5PY dataset with the new chunk.
    
        :param d: h5py Dataset object to extend.
        :param int chunk: The chunk number to write.
        :param int index: The ending index in the chunk to write.
    
        """
    
        cdef:
            int dstart = 0
            int dstop = 0
            int cstart = 0
            int cstop = 0
            int ndim = 0
        
        d = g['data']
        m = g['mask']
        
        cstop = np.argmax(self.mask) + 1
        
        if self.stride != 0:
            
            
            dstart = d.shape[0]
            dstop = dstart + cstop
            d.resize(dstart+self.chunksize, axis=0)
            d[dstart:dstop] = self.array[0:cstop,...]
            d[dstop:dstart+self.chunksize] = 0.0
            m.resize(dstart+self.chunksize, axis=0)
            m[dstart:dstop] = 1.0
            m[dstop:] = 0.0
        
        else:
            dstart = g.attrs['index']
        g.attrs['index'] = dstart + self.chunksize
        return 0
    
    cdef int write(self, g) except -1:
        """
        Write a dataset to HDF5, either by extending an exisitng dataset or creating a new one.
    
        Note that empty datasets will be created as a group.
        """
        cdef int cstop = np.argmax(self.mask) + 1
        if self.name in g:
            d = g[self.name]
            self.extend(d)
        elif self.stride != 0:
            g_sub = g.create_group(self.name)
            d = g_sub.create_dataset("data", 
                shape=(self.chunksize,) + self.shape, 
                maxshape=(None,) + self.shape, 
                chunks=(self.chunksize,) + self.shape, 
                dtype=self.dtype,
                fillvalue=0.0)
            m = g_sub.create_dataset("mask",
                shape=(self.chunksize,),
                maxshape=(None,),
                chunks=(self.chunksize,),
                dtype=np.int32,
                fillvalue=0)
            d[0:cstop,...] = self.array[0:cstop,...]
            m[0:cstop] = 1.0
            m[cstop:] = 0.0
            g_sub.attrs['index'] = self.chunksize
        else:
            d = g.create_group(self.name)
            d.attrs['index'] = self.chunksize
        return 0
    

    