import numpy as np
cimport numpy as np

np.import_array()

from .carray cimport carray_named, carray_message, receive_named_array, new_named_array, close_named_array, copy_named_array

from libc.stdlib cimport free, malloc
from cpython.string cimport PyString_FromStringAndSize
from zmq.utils import jsonapi
cimport zmq.backend.cython.libzmq as libzmq

cdef class ReceivedArray:
    
    def __cinit__(self):
        new_named_array(&self._message)
    
    def __init__(self):
        raise TypeError("Cannot instantiate ReceivedArray from Python")
        
    def __dealloc__(self):
        close_named_array(&self._message)
    
    def __getbuffer__(self, Py_buffer* buffer, int flags):
        # new-style (memoryview) buffer interface
        buffer.buf = libzmq.zmq_msg_data(self._message.array.data)
        buffer.len = libzmq.zmq_msg_size(self._message.array.data)

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
            lenp[0] = libzmq.zmq_msg_size(self._message.array.data)
        return 1

    def __getreadbuffer__(self, Py_ssize_t idx, void **p):
        # old-style (buffer) interface
        cdef void *data = NULL
        cdef Py_ssize_t data_len_c
        if idx != 0:
            raise SystemError("accessing non-existent buffer segment")
        # read-only, because we don't want to allow
        # editing of the message in-place
        data_len_c = libzmq.zmq_msg_size(self._message.array.data)
        if p != NULL:
            p[0] = libzmq.zmq_msg_data(self._message.array.data)
        return data_len_c
    
    property array:
        def __get__(self):
            buf = buffer(self)
            view = np.frombuffer(buf, dtype=self.dtype)
            return view.reshape(self.shape)
        
    property name:
        def __get__(self):
            return PyString_FromStringAndSize(<char *>libzmq.zmq_msg_data(self._message.name), <Py_ssize_t>libzmq.zmq_msg_size(self._message.name))
    
    property metadata:
        def __get__(self):
            return PyString_FromStringAndSize(<char *>libzmq.zmq_msg_data(self._message.array.metadata), <Py_ssize_t>libzmq.zmq_msg_size(self._message.array.metadata))
            
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
        copy_named_array(&obj._message, message)
        return obj
        
    @classmethod
    def receive(cls, Socket socket, int flags = 0):
        cdef carray_named * message
        cdef void * handle = socket.handle
        cdef int rc
        
        message = <carray_named *>malloc(sizeof(carray_named))
        
        if message is NULL:
            raise MemoryError("Couldn't allocate named array message.")
        
        rc = new_named_array(message)
        rc = receive_named_array(message, handle, flags)
        obj = ReceivedArray.from_message(message)
        close_named_array(message)
        return obj

cdef class Receiver:
    
    def __cinit__(self, int n, int framecount):
        self._n = n
        self._framecount = framecount
    