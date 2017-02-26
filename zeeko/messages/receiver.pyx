#cython: embedsignature=True

# Cython imports
# --------------
cimport numpy as np
np.import_array()

from .message cimport ArrayMessage, zmq_msg_to_str
from .carray cimport carray_named, carray_message, carray_message_info
from .carray cimport new_named_array, close_named_array, copy_named_array
from .carray cimport receive_named_array

from libc.stdlib cimport free
from libc.string cimport memcpy, memset

from cpython.string cimport PyString_FromStringAndSize
cimport zmq.backend.cython.libzmq as libzmq

from zmq.utils.buffers cimport viewfromobject_r

from ..utils.rc cimport check_zmq_rc, check_generic_rc, malloc, realloc
from ..utils.condition cimport event_init, event_trigger, event_destroy

# Python imports
# --------------
import numpy as np
import collections
from zmq.utils import jsonapi
from ..utils.sandwich import sandwich_unicode

cdef unsigned long hash_name(char * name, size_t length) nogil except -1:
    cdef unsigned long hashvalue = 5381
    cdef int i, c
    for i in range(length):
        c = <int>name[i]
        hashvalue = ((hashvalue << 5) + hashvalue) + c
    return hashvalue

cdef int receive_header(void * socket, libzmq.zmq_msg_t * topic, unsigned int * fc, int * nm, double * ts, int flags) nogil except -1:
    cdef int rc = 0
    
    # Receive topic message.
    rc = libzmq.zmq_msg_recv(topic, socket, flags)
    check_zmq_rc(rc)
    
    rc = zmq_recv_sized_message(socket, fc, sizeof(unsigned int), flags)
    check_zmq_rc(rc)
    
    rc = zmq_recv_sized_message(socket, nm, sizeof(int), flags)
    check_zmq_rc(rc)
    
    rc = zmq_recv_sized_message(socket, ts, sizeof(double), flags)
    check_zmq_rc(rc)
    return rc
    
cdef int zmq_recv_sized_message(void * socket, void * dest, size_t size, int flags) nogil except -1:
    cdef int rc = 0
    cdef libzmq.zmq_msg_t zmessage
    rc = libzmq.zmq_msg_init(&zmessage)
    check_zmq_rc(rc)
    try:
        rc = libzmq.zmq_msg_recv(&zmessage, socket, flags)
        check_zmq_rc(rc)
        memcpy(dest, libzmq.zmq_msg_data(&zmessage), size)
    finally:
        rc = libzmq.zmq_msg_close(&zmessage)
        check_zmq_rc(rc)
    return rc

cdef class Receiver:
    
    def __cinit__(self):
        self._failed_init = True
        self._n_messages = 0
        self._n_events = 0
        self._events = NULL
        self._framecount = 0
        self._name_cache = {}
        self._name_cache_valid = 1
        rc = pthread.mutex_init(&self._mutex, NULL)
        self._failed_init = False
        self.last_message = 0.0
    
    cdef int lock(self) nogil except -1:
        cdef int rc
        rc = pthread.pthread_mutex_lock(&self._mutex)
        return rc

    cdef int unlock(self) nogil except -1:
        cdef int rc
        rc = pthread.pthread_mutex_unlock(&self._mutex)
        return rc
    
    cdef int _update_messages(self, int nm) nogil except -1:
        cdef int i
        cdef carray_named * message
        if nm < self._n_messages:
            return 0
        self._name_cache_valid = 0
        self._messages = <carray_named **>realloc(<void *>self._messages, sizeof(carray_named *) * nm)
        self._hashes = <unsigned long *>realloc(<void*>self._hashes, sizeof(unsigned long) * nm)
        for i in range(self._n_messages, nm):
            message = <carray_named *>malloc(sizeof(carray_named))
            rc = new_named_array(message)
            self._messages[i] = message
            self._hashes[i] = 0
        self._n_messages = nm
        return nm
        
    def __dealloc__(self):
        if self._messages is not NULL:
            for i in range(self._n_messages):
                if self._messages[i] is not NULL:
                    free(self._messages[i])
            free(self._messages)
            self._messages = NULL
        if self._hashes is not NULL:
            free(self._hashes)
        if self._events is not NULL:
            for i in range(self._n_events):
                event_destroy(&self._events[i].evt)
            free(self._events)
            self._events = NULL
            self._n_events = 0
        if not self._failed_init:
            pthread.pthread_mutex_destroy(&self._mutex)
    
    cdef int _receive(self, void * socket, int flags, void * notify_socket) nogil except -1:
        cdef int rc
        cdef int value = 1
        cdef size_t optsize = sizeof(int)
        while value == 1:
            rc = self._receive_unbundled(socket, flags, notify_socket)
            rc = libzmq.zmq_getsockopt(socket, libzmq.ZMQ_RCVMORE, &value, &optsize)
            check_zmq_rc(rc)
        return rc
    
    cdef int get_message_index(self, libzmq.zmq_msg_t * name) nogil except -1:
        """Return the message index."""
        cdef int rc, idx
        cdef int size
        cdef unsigned long hashvalue
        cdef char * data
        
        size = libzmq.zmq_msg_size(name)
        data = <char *>libzmq.zmq_msg_data(name)
        hashvalue = hash_name(data, size)
        
        self.lock()
        try:
            for i in range(self._n_messages):
                if self._hashes[i] == hashvalue:
                     idx = i
                     break
            else:
                idx = -1
        finally:
            self.unlock()
        return idx
    
    cdef int _receive_unbundled(self, void * socket, int flags, void * notify_socket) nogil except -1:
        cdef int rc, i, j
        cdef unsigned long hashvalue, framecount
        cdef double timestamp
        cdef carray_named message
        cdef carray_message_info * info
        cdef libzmq.zmq_msg_t notification
        
        rc = new_named_array(&message)
        check_zmq_rc(rc)
        rc = receive_named_array(&message, socket, flags)
        check_zmq_rc(rc)
        
        hashvalue = hash_name(<char *>libzmq.zmq_msg_data(&message.name), libzmq.zmq_msg_size(&message.name))
        
        info = <carray_message_info *>libzmq.zmq_msg_data(&message.array.info)
        if self.last_message < info.timestamp:
            self.last_message = info.timestamp
        
        self.lock()
        try:
            for i in range(self._n_messages):
                if self._hashes[i] == hashvalue:
                    break
            else:
                self._name_cache_valid = 0
                i = self._update_messages(self._n_messages + 1) - 1
                j = self._get_event(hashvalue)
                rc = event_trigger(&self._events[j].evt)
            
            self._hashes[i] = hashvalue
            copy_named_array(self._messages[i], &message)
            framecount = (<carray_message_info *>libzmq.zmq_msg_data(&self._messages[i].array.info)).framecount
            if framecount > self._framecount:
                self._framecount = framecount
            
        finally:
            self.unlock()
        
        if notify_socket != NULL:
            rc = libzmq.zmq_msg_init(&notification)
            check_zmq_rc(rc)
            rc = libzmq.zmq_msg_copy(&notification, &message.name)
            check_zmq_rc(rc)
            rc = libzmq.zmq_msg_send(&notification, notify_socket, 0)
            check_zmq_rc(rc)
        
        return rc
        
    cdef int reset(self) nogil except -1:
        if self._messages is not NULL:
            for i in range(self._n_messages):
                if self._messages[i] is not NULL:
                    free(self._messages[i])
            free(self._messages)
            self._messages = NULL
            self._n_messages = 0
            self._name_cache_valid = 0
        if self._events is not NULL:
            for i in range(self._n_events):
                event_destroy(&self._events[i].evt)
            free(self._events)
            self._events = NULL
            self._n_events = 0
    
    cdef int _get_event(self, unsigned long hashvalue) nogil except -1:
        cdef int j, rc
        for j in range(self._n_events):
            if self._events[j].hash == hashvalue:
                return j
        else:
            j = self._n_events
            self._events = <msg_event *>realloc(<void *>self._events, sizeof(msg_event) * (j + 1))
            memset(&self._events[j], 0, sizeof(msg_event))
            rc = event_init(&self._events[j].evt)
            self._events[j].hash = hashvalue
            self._n_events = j + 1
        return j
        
    def event(self, name):
        """Get the event which corresponds to a particular name"""
        cdef unsigned long hashvalue
        cdef char[:] _name
        cdef int j
        _name = bytearray(sandwich_unicode(name))
        hashvalue = hash_name(&_name[0], len(_name))
        j = self._get_event(hashvalue)
        return Event._from_event(&self._events[j].evt)
        
    def receive(self, Socket socket, int flags = 0, Socket notify = None):
        """Receive a full message"""
        cdef void * handle = socket.handle
        cdef void * notify_handle = NULL
        if notify is not None:
            notify_handle = notify.handle
        with nogil:
            self._receive(handle, flags, notify_handle)
    
    cdef int _build_namecache(self):
        cdef int i
        cdef str name
        if self._name_cache_valid == 1:
            return 0
        
        self._name_cache.clear()
        self.lock()
        try:
            for i in range(self._n_messages):
                name = zmq_msg_to_str(&self._messages[i].name)
                self._name_cache[name] = i
        finally:
            self.unlock()
        self._name_cache_valid = 1
        return 0
        
    def _get_by_index(self, i):
        self.lock()
        try:
            if i < self._n_messages:
                return ArrayMessage.from_message(self._messages[i])
            else:
                raise IndexError("Index to messages out of range.")
        finally:
            self.unlock()
    
    def __iter__(self):
        """Iterate over the keys (names of arrays) in the recorder."""
        self._build_namecache()
        return iter(self._name_cache)
    
    def __len__(self):
        return self._n_messages
    
    def __repr__(self):
        return "<Receiver frame={:d} keys=[{:s}]>".format(self._framecount, ",".join(self.keys()))
    
    property framecount:
        """Counter which increments for each message sent-or-received."""
        def __get__(self):
            return int(self._framecount)
    
    def __getitem__(self, key):
        """Get a single message"""
        if isinstance(key, int):
            return self._get_by_index(key)
        self._build_namecache()
        index = self._name_cache[key]
        obj = self._get_by_index(index)
        while obj.name != key:
            self._name_cache_valid = 0
            self._build_namecache()
            index = self._name_cache[key]
            obj = self._get_by_index(index)
        return obj
            