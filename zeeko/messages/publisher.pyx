"""
Output arrays by publishing them over ZMQ.
"""
import numpy as np
cimport numpy as np

np.import_array()

from libc.stdlib cimport free, malloc
from libc.string cimport strndup, memcpy

cimport zmq.backend.cython.libzmq as libzmq
import zmq
from zmq.utils import jsonapi
from zmq.backend.cython.socket cimport Socket

from .carray cimport send_named_array
from .utils cimport check_rc, check_ptr

cdef int MAXFRAMECOUNT = (2**30)

cdef int send_header(void * socket, unsigned int fc, int nm, int flags) nogil except -1:
    """Send the message header for a publisher. Sent as:
    [\0, fc, nm]
    """
    cdef int rc = 0
    rc = libzmq.zmq_sendbuf(socket, NULL, 0, flags|libzmq.ZMQ_SNDMORE)
    check_rc(rc)
    
    rc = libzmq.zmq_sendbuf(socket, <void *>&fc, sizeof(unsigned int), flags|libzmq.ZMQ_SNDMORE)
    check_rc(rc)
    
    rc = libzmq.zmq_sendbuf(socket, <void *>&nm, sizeof(int), flags)
    check_rc(rc)
    
    return rc

cdef class Publisher:
    """A collection of arrays which are published for consumption as a telemetry stream."""
    
    def __cinit__(self):
        cdef int rc
        rc = pthread.pthread_mutex_init(&self._mutex, NULL)
        pthread.check_rc(rc)
        self._n_messages = 0
        self._framecount = 0
        
    def __init__(self, publishers):
        self._publishers = list()
        for publisher in publishers:
            if isinstance(publisher, PublishedArray):
                self._publishers.append(publisher)
            else:
                raise TypeError("Publisher can only contain PublishedArray instances, got {!r}".format(publisher))
        self._update_messages()
    
    def __dealloc__(self):
        if self._messages is not NULL:
            free(self._messages)
    
    cdef int lock(self) except -1:
        cdef int rc
        rc = pthread.pthread_mutex_lock(&self._mutex)
        pthread.check_rc(rc)
        return rc
    
    cdef int unlock(self) except -1:
        cdef int rc
        rc = pthread.pthread_mutex_unlock(&self._mutex)
        pthread.check_rc(rc)
        return rc
    
    cdef int _update_messages(self) except -1:
        """Function to update the messages array."""
        
        self.lock()
        try:
            if self._messages is not NULL:
                free(self._messages)
            self._messages = <carray_named **>malloc(sizeof(carray_named *) * len(self._publishers))
            if self._messages is NULL:
                raise MemoryError("Could not allocate messages array for Publisher {!r}".format(self))
            for i, publisher in enumerate(self._publishers):
                self._messages[i] = &(<PublishedArray>publisher)._message
            self._n_messages = len(self._publishers)
        finally:
            self.unlock()
        return 0
        
    cdef int _publish(self, void * socket, int flags) nogil except -1:
        """Inner-loop message sender."""
        cdef int i, rc
        self._framecount = (self._framecount + 1) % MAXFRAMECOUNT
        rc = send_header(socket, self._framecount, self._n_messages, flags)
        for i in range(self._n_messages):
            rc = send_named_array(socket, self._messages[i], flags)
        return rc
        
    def publish(self, Socket socket, int flags = 0):
        """Publish all registered arrays."""
        cdef void * handle = socket.handle
        with nogil:
            self._publish(handle, flags)

cdef class PublishedArray:
    """A single array publisher"""
    
    def __cinit__(self, str name, np.ndarray data):
        
        self._data = np.asarray(data, dtype=np.float)
        self._name = bytearray(name)
        self._update_message()
        
    cdef void _update_message(self):
        # First, update array metadata, in case it has changed.
        A = <object>self._data
        metadata = jsonapi.dumps(dict(shape=A.shape, dtype=A.dtype.str))
        self._metadata = bytearray(metadata)
        
        # Then update output structure for NOGIL function.
        self._message.array.n = <size_t>np.PyArray_NBYTES(self._data)
        self._message.array.data = <double *>np.PyArray_DATA(self._data)
        self._message.array.nm = len(self._metadata)
        self._message.array.metadata = <char *>&self._metadata[0]
        self._message.nm = len(self._name)
        self._message.name = <char *>&self._name[0]
        
    def send(self, Socket socket, int flags = 0):
        """Send the array."""
        cdef void * handle = socket.handle
        with nogil:
            send_named_array(handle, &self._message, flags)
    
    property array:
        def __get__(self):
            return self._data
        
        def __set__(self, value):
            self._data = np.asarray(value, dtype=np.float)
            self._update_message()
    
    property name:
        def __get__(self):
            return bytes(bytearray(self._name))
            
        def __set__(self, value):
            self._name = bytearray(value)
            self._update_message()
    