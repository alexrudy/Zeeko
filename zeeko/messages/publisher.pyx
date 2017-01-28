"""
Output arrays by publishing them over ZMQ.
"""
import numpy as np
cimport numpy as np

np.import_array()

from libc.stdlib cimport free, malloc, realloc
from libc.string cimport strndup, memcpy

import collections
import zmq
from zmq.utils import jsonapi
from zmq.backend.cython.socket cimport Socket
cimport zmq.backend.cython.libzmq as libzmq
from zmq.backend.cython.message cimport Frame


from .carray cimport send_named_array, empty_named_array, close_named_array, carray_message_info
from .message cimport ArrayMessage, zmq_msg_to_str
from .utils cimport check_rc, check_ptr
from ..utils.clock cimport current_time
from .. import ZEEKO_PROTOCOL_VERSION

cdef int MAXFRAMECOUNT = (2**30)

cdef int send_header(void * socket, libzmq.zmq_msg_t * topic, unsigned int fc, int nm, int flags) nogil except -1:
    """Send the message header for a publisher. Sent as:
    [fc, nm, now]
    """
    cdef int rc = 0
    cdef double now = current_time()
    cdef libzmq.zmq_msg_t zmessage
    
    rc = libzmq.zmq_msg_init(&zmessage)
    check_rc(rc)
    libzmq.zmq_msg_copy(&zmessage, topic)
    rc = libzmq.zmq_msg_send(&zmessage, socket, flags|libzmq.ZMQ_SNDMORE)
    check_rc(rc)
    
    rc = libzmq.zmq_sendbuf(socket, <void *>&fc, sizeof(unsigned int), flags|libzmq.ZMQ_SNDMORE)
    check_rc(rc)
    
    rc = libzmq.zmq_sendbuf(socket, <void *>&nm, sizeof(int), flags|libzmq.ZMQ_SNDMORE)
    check_rc(rc)
    
    rc = libzmq.zmq_sendbuf(socket, <void *>&now, sizeof(double), flags)
    check_rc(rc)
    
    return rc
    

cdef class Publisher:
    """A collection of arrays which are published for consumption as a telemetry stream."""
    
    def __cinit__(self):
        cdef int rc
        cdef unsigned int * _framecounter
        self._failed_init = True
        rc = pthread.pthread_mutex_init(&self._mutex, NULL)
        pthread.check_rc(rc)
        rc = libzmq.zmq_msg_init_size(&self._infomessage, sizeof(carray_message_info))
        check_rc(rc)
        self._set_framecounter_message(0)
        self._n_messages = 0
        self._failed_init = False
        
    def __init__(self, publishers=list()):
        self._publishers = collections.OrderedDict()
        self._active_publishers = []
        for publisher in publishers:
            if isinstance(publisher, ArrayMessage):
                self._publishers[publisher.name] = publisher
            else:
                raise TypeError("Publisher can only contain ArrayMessage instances, got {!r}".format(publisher))
        self._update_messages()
    
    def __dealloc__(self):
        if self._messages is not NULL:
            free(self._messages)
        if not self._failed_init:
            rc = libzmq.zmq_msg_close(&self._infomessage)
            rc = pthread.pthread_mutex_destroy(&self._mutex)
    
    def __repr__(self):
        return "<Publisher frame={:d} keys=[{:s}]>".format(self._framecount, ",".join(self.keys()))
    
    def __setitem__(self, key, value):
        try:
            pub = self._publishers[key]
        except KeyError:
            self._publishers[key] = ArrayMessage(key, np.asarray(value))
            self._update_messages()
        else:
            pub.array[:] = value
        
    def __getitem__(self, key):
        return self._publishers[key]
    
    def __len__(self):
        return len(self._publishers)
    
    def keys(self):
        return self._publishers.keys()
    
    property framecount:
        def __get__(self):
            return self._framecount
        def __set__(self, int fc):
            if fc < 0:
                raise ValueError("Frame count must be positive")
            self._framecount = fc
    
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
        
    cdef int _set_framecounter_message(self, unsigned long framecount) nogil except -1:
        """Set the framecounter value."""
        cdef carray_message_info * info
        cdef size_t size = libzmq.zmq_msg_size(&self._infomessage)
        info = <carray_message_info *>libzmq.zmq_msg_data(&self._infomessage)
        check_ptr(info)
        info.framecount = framecount
        info.timestamp = current_time()
        return 0
        
    cdef int _update_messages(self) except -1:
        """Update the internal array of message structures."""
        cdef int rc
        self.lock()
        try:

            self._messages = <carray_named **>realloc(<void *>self._messages, sizeof(carray_named *) * len(self._publishers))
            if self._messages is NULL:
                raise MemoryError("Could not allocate messages array for Publisher {!r}".format(self))
            for i, key in enumerate(self._publishers.keys()):
                self._messages[i] = &(<ArrayMessage>self._publishers[key])._message
                rc = libzmq.zmq_msg_copy(&self._messages[i].array.info, &self._infomessage)
                
            # This array is used to retain references to the publishers
            # Setting the values here will cause the old publishers to
            # fall out of scope.
            self._active_publishers = list(self._publishers.values())
            self._n_messages = len(self._publishers)
        finally:
            self.unlock()
        return 0
        
    cdef int _publish(self, void * socket, int flags) nogil except -1:
        """Send all messages/arrays once via the provided socket."""
        cdef int i, rc
        self.lock()
        try:
            self._framecount = (self._framecount + 1) % MAXFRAMECOUNT
            self._set_framecounter_message(self._framecount)
            for i in range(self._n_messages):
                rc = libzmq.zmq_msg_copy(&self._messages[i].array.info, &self._infomessage)
                rc = send_named_array(self._messages[i], socket, flags)
        finally:
            self.unlock()
        return rc
        
    def publish(self, Socket socket, int flags = 0):
        """Publish all registered arrays."""
        cdef void * handle = socket.handle
        with nogil:
            self._publish(handle, flags)