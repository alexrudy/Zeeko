import numpy as np
cimport numpy as np

np.import_array()

from .carray cimport carray_named, carray_message, receive_named_array

from libc.stdlib cimport free, malloc
from cpython.string cimport PyString_FromStringAndSize
from zmq.utils import jsonapi

cdef class ReceivedArray:
    
    def __init__(self):
        raise TypeError("Cannot instantiate ReceivedArray from Python")
    
    def __dealloc__(self):
        if self._message.array.data is not NULL:
            free(self._message.array.data)
    
    def __getbuffer__(self, Py_buffer* buffer, int flags):
        # new-style (memoryview) buffer interface
        buffer.buf = self._message.array.data
        buffer.len = self._message.array.n

        buffer.obj = self
        buffer.readonly = 1
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
            lenp[0] = self._message.array.n
        return 1

    def __getreadbuffer__(self, Py_ssize_t idx, void **p):
        # old-style (buffer) interface
        cdef void *data = NULL
        cdef Py_ssize_t data_len_c
        if idx != 0:
            raise SystemError("accessing non-existent buffer segment")
        # read-only, because we don't want to allow
        # editing of the message in-place
        data_len_c = self._message.array.n
        if p != NULL:
            p[0] = self._message.array.data
        return data_len_c
    
    property array:
        def __get__(self):
            buf = buffer(self)
            view = np.frombuffer(buf, dtype=self.dtype)
            return view.reshape(self.shape)
        
    property name:
        def __get__(self):
            return PyString_FromStringAndSize(self._message.name, <Py_ssize_t>self._message.nm)
    
    property metadata:
        def __get__(self):
            return PyString_FromStringAndSize(self._message.array.metadata, <Py_ssize_t>self._message.array.nm)
            
    def _parse_metadata(self):
        meta = jsonapi.loads(self.metadata)
        self._shape = tuple(meta['shape'])
        self._dtype = np.dtype(meta['dtype'])
    
    property shape:
        def __get__(self):
            self._parse_metadata()
            return self._shape
    
    property dtype:
        def __get__(self):
            self._parse_metadata()
            return self._dtype
        
            
    @staticmethod
    cdef ReceivedArray from_message(carray_named * message):
        cdef ReceivedArray obj = ReceivedArray.__new__(ReceivedArray)
        obj._message = message
        return obj
        
    @classmethod
    def receive(cls, Socket socket):
        cdef carray_named * message
        cdef void * handle = socket.handle
        cdef int rc
        
        message = <carray_named *>malloc(sizeof(carray_named))
        message.nm = 0
        message.array.n = 0
        message.array.nm = 0
        
        if message is NULL:
            raise MemoryError("Couldn't allocate named array message.")
        
        rc = receive_named_array(handle, message, 0)
        return ReceivedArray.from_message(message)

cdef class Receiver:
    
    def __cinit__(self, int n, int framecount):
        self._n = n
        self._framecount = framecount
    