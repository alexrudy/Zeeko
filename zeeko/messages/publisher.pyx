#cython: embedsignature=True

"""
Output arrays by publishing them over ZMQ.
"""
import numpy as np
cimport numpy as np

np.import_array()

from libc.string cimport strndup, memcpy

import collections
try:
    from collections import OrderedDict
except ImportError:
    from astropy.utils.compat.odict import OrderedDict

import zmq
from zmq.utils import jsonapi
from zmq.backend.cython.socket cimport Socket
cimport zmq.backend.cython.libzmq as libzmq
from zmq.backend.cython.message cimport Frame


from .carray cimport send_named_array, empty_named_array, close_named_array, carray_message_info
from .carray cimport copy_named_array_hard, copy_named_array
from .message cimport ArrayMessage, zmq_msg_to_str
from ..utils.clock cimport current_time
from ..utils.lock cimport Lock
from ..utils.rc cimport check_zmq_rc, check_zmq_ptr, free, malloc, realloc
from .. import ZEEKO_PROTOCOL_VERSION

__all__ = ['Publisher']

cdef long MAXFRAMECOUNT = (2**15)

cdef int send_header(void * socket, libzmq.zmq_msg_t * topic, unsigned int fc, int nm, int flags) nogil except -1:
    """Send the message header for a publisher. Sent as:
    [fc, nm, now]
    """
    cdef int rc = 0
    cdef double now = current_time()
    cdef libzmq.zmq_msg_t zmessage
    
    rc = libzmq.zmq_msg_init(&zmessage)
    check_zmq_rc(rc)
    libzmq.zmq_msg_copy(&zmessage, topic)
    rc = libzmq.zmq_msg_send(&zmessage, socket, flags|libzmq.ZMQ_SNDMORE)
    check_zmq_rc(rc)
    
    rc = libzmq.zmq_sendbuf(socket, <void *>&fc, sizeof(unsigned int), flags|libzmq.ZMQ_SNDMORE)
    check_zmq_rc(rc)
    
    rc = libzmq.zmq_sendbuf(socket, <void *>&nm, sizeof(int), flags|libzmq.ZMQ_SNDMORE)
    check_zmq_rc(rc)
    
    rc = libzmq.zmq_sendbuf(socket, <void *>&now, sizeof(double), flags)
    check_zmq_rc(rc)
    
    return rc
    

cdef class Publisher:
    """A collection of arrays which are published for consumption as a telemetry stream."""
    
    def __cinit__(self):
        cdef int rc
        self._failed_init = True
        self._hard_copy_on_send = False
        rc = libzmq.zmq_msg_init_size(&self._infomessage, sizeof(carray_message_info))
        check_zmq_rc(rc)
        self._set_framecounter_message(0)
        self._n_messages = 0
        self.lock = Lock()
        self._failed_init = False
        
    def __init__(self, publishers=list()):
        self._publishers = OrderedDict()
        self._active_publishers = []
        for publisher in publishers:
            if isinstance(publisher, ArrayMessage):
                self._publishers[publisher.name] = publisher
            else:
                raise TypeError("Publisher can only contain ArrayMessage instances, got {!r}".format(publisher))
        self._update_messages()
        self.framecount = 0
    
    def __dealloc__(self):
        if self._messages is not NULL:
            free(self._messages)
        if not self._failed_init:
            rc = libzmq.zmq_msg_close(&self._infomessage)
    
    def __repr__(self):
        return "<Publisher frame={0:d} keys=[{1:s}]>".format(self._framecount, ",".join(self.keys()))
    
    def __setitem__(self, key, value):
        try:
            pub = self._publishers[key]
        except KeyError:
            self._publishers[key] = ArrayMessage(key, np.asarray(value))
            self._update_messages()
        else:
            pub.array[:] = value
            
    def __delitem__(self, key):
        self._publishers.__delitem__(key)
        self._update_messages()
        
    def __getitem__(self, key):
        return self._publishers[key]
    
    def __len__(self):
        return len(self._publishers)
    
    def __iter__(self):
        """Iterate over the publisher."""
        return iter(self._publishers)
        
    def enable_hardcopy(self):
        """Enable hardcopy on send."""
        self._hard_copy_on_send = True
    
    property framecount:
        """A counter incremented each time a message is sent by this publisher."""
        def __get__(self):
            return self._framecount
        def __set__(self, int fc):
            if fc < 0:
                raise ValueError("Frame count must be positive")
            self._framecount = fc
            # self._set_framecounter_message(self._framecount)
    
    property last_message:
        """Return the raw timestamp for the last message"""
        def __get__(self):
            cdef carray_message_info * info
            cdef size_t size = libzmq.zmq_msg_size(&self._infomessage)
            info = <carray_message_info *>libzmq.zmq_msg_data(&self._infomessage)
            check_zmq_ptr(info)
            return info.timestamp
        
    cdef int _set_framecounter_message(self, unsigned long framecount) nogil except -1:
        """Set the framecounter value."""
        cdef carray_message_info * info
        cdef size_t size = libzmq.zmq_msg_size(&self._infomessage)
        info = <carray_message_info *>libzmq.zmq_msg_data(&self._infomessage)
        check_zmq_ptr(info)
        info.framecount = framecount
        info.timestamp = current_time()
        return 0
        
    cdef int _update_messages(self) except -1:
        """Update the internal array of message structures."""
        cdef int rc
        self.lock.acquire()
        try:

            self._messages = <carray_named **>realloc(<void *>self._messages, sizeof(carray_named *) * len(self._publishers))
            if self._messages is NULL and len(self._publishers):
                raise MemoryError("Could not allocate messages array for Publisher {0!r}".format(self))
            for i, key in enumerate(self._publishers.keys()):
                self._messages[i] = &(<ArrayMessage>self._publishers[key])._message
                rc = libzmq.zmq_msg_copy(&self._messages[i].array.info, &self._infomessage)
                
            # This array is used to retain references to the publishers
            # Setting the values here will cause the old publishers to
            # fall out of scope.
            self._active_publishers = list(self._publishers.values())
            self._n_messages = len(self._publishers)
        finally:
            self.lock.release()
        return 0
        
    cdef int _publish(self, void * socket, int flags) nogil except -1:
        """Send all messages/arrays once via the provided socket."""
        cdef int i, rc
        cdef carray_named message
        self.lock._acquire()
        try:
            self._framecount = (self._framecount + 1) % MAXFRAMECOUNT
            self._set_framecounter_message(self._framecount)
            for i in range(self._n_messages):
                rc = libzmq.zmq_msg_copy(&self._messages[i].array.info, &self._infomessage)
                if self._hard_copy_on_send:
                    copy_named_array_hard(&message, self._messages[i])
                else:
                    empty_named_array(&message)
                    copy_named_array(&message, self._messages[i])
                rc = send_named_array(&message, socket, flags)
        finally:
            self.lock._release()
        return rc
        
    def publish(self, Socket socket, int flags = 0):
        """Publish all registered arrays."""
        cdef void * handle = socket.handle
        with nogil:
            self._publish(handle, flags)