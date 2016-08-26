"""
Output arrays by publishing them over ZMQ.
"""
import numpy as np
cimport numpy as np

np.import_array()

from libc.stdlib cimport free, malloc, realloc
from libc.string cimport strndup, memcpy

import zmq
from zmq.utils import jsonapi
from zmq.backend.cython.socket cimport Socket
cimport zmq.backend.cython.libzmq as libzmq
from zmq.backend.cython.message cimport Frame


from .carray cimport send_named_array, empty_named_array, close_named_array
from .utils cimport check_rc, check_ptr
from ..utils.clock cimport current_time

cdef int MAXFRAMECOUNT = (2**30)

cdef int send_header(void * socket, unsigned int fc, int nm, int flags) nogil except -1:
    """Send the message header for a publisher. Sent as:
    [\0, fc, nm]
    """
    cdef int rc = 0
    cdef double now = current_time()
    
    rc = libzmq.zmq_sendbuf(socket, <void *>&fc, sizeof(unsigned int), flags|libzmq.ZMQ_SNDMORE)
    check_rc(rc)
    
    rc = libzmq.zmq_sendbuf(socket, <void *>&nm, sizeof(int), flags|libzmq.ZMQ_SNDMORE)
    check_rc(rc)
    
    rc = libzmq.zmq_sendbuf(socket, <void *>&now, sizeof(double), flags)
    check_rc(rc)
    
    return rc
    
cdef inline int zmq_msg_from_chars(libzmq.zmq_msg_t * message, char[:] data):
    """
    Initialize and fill a message from a bytearray.
    """
    cdef int rc
    rc = libzmq.zmq_msg_init_size(message, <size_t>len(data))
    check_rc(rc)
    memcpy(libzmq.zmq_msg_data(message), &data[0], libzmq.zmq_msg_size(message))
    return rc

cdef class Publisher:
    """A collection of arrays which are published for consumption as a telemetry stream."""
    
    def __cinit__(self):
        cdef int rc
        rc = pthread.pthread_mutex_init(&self._mutex, NULL)
        pthread.check_rc(rc)
        self._n_messages = 0
        self._framecount = 0
        
    def __init__(self, publishers=list()):
        self._publishers = dict()
        for publisher in publishers:
            if isinstance(publisher, PublishedArray):
                self._publishers[publisher.name] = publisher
            else:
                raise TypeError("Publisher can only contain PublishedArray instances, got {!r}".format(publisher))
        self._update_messages()
    
    def __dealloc__(self):
        if self._messages is not NULL:
            free(self._messages)
    
    def __setitem__(self, key, value):
        try:
            pub = self._publishers[key]
        except KeyError:
            self._publishers[key] = PublishedArray(key, np.asarray(value))
            self._update_messages()
        else:
            pub.array = value
        
    def __getitem__(self, key):
        return self._publishers[key]
    
    cdef int lock(self) nogil except -1:
        cdef int rc
        rc = pthread.pthread_mutex_lock(&self._mutex)
        pthread.check_rc(rc)
        return rc
    
    cdef int unlock(self) nogil except -1:
        cdef int rc
        rc = pthread.pthread_mutex_unlock(&self._mutex)
        pthread.check_rc(rc)
        return rc
    
    cdef int _update_messages(self) except -1:
        """Function to update the messages array."""
        
        self.lock()
        try:

            self._messages = <carray_named **>realloc(<void *>self._messages, sizeof(carray_named *) * len(self._publishers))
            if self._messages is NULL:
                raise MemoryError("Could not allocate messages array for Publisher {!r}".format(self))
            for i, key in enumerate(sorted(self._publishers.keys())):
                self._messages[i] = &(<PublishedArray>self._publishers[key])._message
            self._n_messages = len(self._publishers)
        finally:
            self.unlock()
        return 0
        
    cdef int _publish(self, void * socket, int flags) nogil except -1:
        """Inner-loop message sender."""
        cdef int i, rc
        self._framecount = (self._framecount + 1) % MAXFRAMECOUNT
        rc = send_header(socket, self._framecount, self._n_messages, flags|libzmq.ZMQ_SNDMORE)
        for i in range(self._n_messages-1):
            rc = send_named_array(self._messages[i], socket, flags|libzmq.ZMQ_SNDMORE)
        rc = send_named_array(self._messages[self._n_messages-1], socket, flags)
        return rc
        
    def publish(self, Socket socket, int flags = 0):
        """Publish all registered arrays."""
        cdef void * handle = socket.handle
        with nogil:
            self.lock()
            try:
                self._publish(handle, flags)
            finally:
                self.unlock()

cdef class PublishedArray:
    """A single array publisher.
    
    You must retain a reference to this publisher for as long as it will be published.
    """
    
    def __cinit__(self, name, data):
        self._failed_init = True
        self._data = np.asarray(data, dtype=np.float)
        self._name = bytearray(name)
        empty_named_array(&self._message)
        self._update_message()
        self._failed_init = False
        
    def __dealloc__(self):
        if not self._failed_init:
            close_named_array(&self._message)
        
    cdef int _update_message(self) except -1:
        cdef int rc = 0
        
        # First, update array metadata, in case it has changed.
        A = <object>self._data
        metadata = jsonapi.dumps(dict(shape=A.shape, dtype=A.dtype.str))
        self._metadata = bytearray(metadata)
        
        # Close the old message.
        rc = close_named_array(&self._message)
        check_rc(rc)
        
        # Then update output structure for NOGIL function.
        self._data_frame = Frame(data=self._data)
        rc = libzmq.zmq_msg_init(&self._message.array.data)
        rc = libzmq.zmq_msg_copy(&self._message.array.data, &self._data_frame.zmq_msg)
        check_rc(rc)
        
        rc = zmq_msg_from_chars(&self._message.array.metadata, self._metadata)
        check_rc(rc)
        
        rc = zmq_msg_from_chars(&self._message.name, self._name)
        check_rc(rc)
        return rc
        
    def send(self, Socket socket, int flags = 0):
        """Send the array."""
        cdef void * handle = socket.handle
        with nogil:
            rc = send_named_array(&self._message, handle, flags)
        check_rc(rc)
    
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
    