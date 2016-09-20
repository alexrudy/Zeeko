import numpy as np
cimport numpy as np

np.import_array()

from .carray cimport carray_named, carray_message, receive_named_array, new_named_array, close_named_array, copy_named_array, carray_message_info

from libc.stdlib cimport free, malloc, realloc
from libc.string cimport memcpy
from cpython.string cimport PyString_FromStringAndSize
from zmq.utils import jsonapi
cimport zmq.backend.cython.libzmq as libzmq
from zmq.utils.buffers cimport viewfromobject_r
from .utils cimport check_rc, check_ptr

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
    check_rc(rc)
    
    rc = zmq_recv_sized_message(socket, fc, sizeof(unsigned int), flags)
    check_rc(rc)
    
    rc = zmq_recv_sized_message(socket, nm, sizeof(int), flags)
    check_rc(rc)
    
    rc = zmq_recv_sized_message(socket, ts, sizeof(double), flags)
    check_rc(rc)
    return rc
    
cdef int zmq_recv_sized_message(void * socket, void * dest, size_t size, int flags) nogil except -1:
    cdef int rc = 0
    cdef libzmq.zmq_msg_t zmessage
    rc = libzmq.zmq_msg_init(&zmessage)
    check_rc(rc)
    try:
        rc = libzmq.zmq_msg_recv(&zmessage, socket, flags)
        check_rc(rc)
        memcpy(dest, libzmq.zmq_msg_data(&zmessage), size)
    finally:
        rc = libzmq.zmq_msg_close(&zmessage)
        check_rc(rc)
    return rc
    
cdef str zmq_msg_to_str(libzmq.zmq_msg_t * msg):
    return PyString_FromStringAndSize(<char *>libzmq.zmq_msg_data(msg), <Py_ssize_t>libzmq.zmq_msg_size(msg))

cdef class ReceivedArray:
    
    def __cinit__(self):
        new_named_array(&self._message)
    
    def __init__(self):
        raise TypeError("Cannot instantiate ReceivedArray from Python")
        
    def __dealloc__(self):
        close_named_array(&self._message)
    
    def __getbuffer__(self, Py_buffer* buffer, int flags):
        # new-style (memoryview) buffer interface
        buffer.buf = libzmq.zmq_msg_data(&self._message.array.data)
        buffer.len = libzmq.zmq_msg_size(&self._message.array.data)

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
    
    property array:
        def __get__(self):
            view = np.frombuffer(self, dtype=self.dtype)
            return view.reshape(self.shape)
        
    property name:
        def __get__(self):
            return zmq_msg_to_str(&self._message.name)
    
    property metadata:
        def __get__(self):
            return zmq_msg_to_str(&self._message.array.metadata)
            
    def _parse_metadata(self):
        try:
            meta = jsonapi.loads(self.metadata)
        except ValueError as e:
            raise ValueError("Can't decode JSON in {!r}".format(self.metadata))
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
        
    property framecount:
        def __get__(self):
            cdef carray_message_info * info
            info = <carray_message_info *>libzmq.zmq_msg_data(&self._message.array.info)
            return info.framecount
    
    property timestamp:
        def __get__(self):
            cdef carray_message_info * info
            info = <carray_message_info *>libzmq.zmq_msg_data(&self._message.array.info)
            return info.timestamp
            
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
        free(message)
        return obj

cdef class Receiver:
    
    def __cinit__(self):
        self._failed_init = True
        self._n_messages = 0
        self._framecount = 0
        self._name_cache = {}
        self._name_cache_valid = 1
        rc = pthread.pthread_mutex_init(&self._mutex, NULL)
        pthread.check_rc(rc)
        self._failed_init = False
        self.last_message = 0.0
    
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
    
    cdef int _update_messages(self, int nm) nogil except -1:
        cdef int i
        cdef carray_named * message
        if nm < self._n_messages:
            return 0
        self._name_cache_valid = 0
        self._messages = <carray_named **>realloc(<void *>self._messages, sizeof(carray_named *) * nm)
        self._hashes = <unsigned long *>realloc(<void*>self._hashes, sizeof(unsigned long) * nm)
        check_ptr(self._messages)
        for i in range(self._n_messages, nm):
            message = <carray_named *>malloc(sizeof(carray_named))
            check_ptr(message)
            rc = new_named_array(message)
            check_rc(rc)
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
        if not self._failed_init:
            pthread.pthread_mutex_destroy(&self._mutex)
    
    cdef int _receive(self, void * socket, int flags, void * notify_socket) nogil except -1:
        cdef int rc
        cdef int value = 1
        cdef size_t optsize = sizeof(int)
        while value == 1:
            rc = self._receive_unbundled(socket, flags, notify_socket)
            rc = libzmq.zmq_getsockopt(socket, libzmq.ZMQ_RCVMORE, &value, &optsize)
            check_rc(rc)
        return rc
    
    cdef int get_message_index(self, libzmq.zmq_msg_t * name) nogil except -1:
        """Return the message index."""
        cdef int rc, idx
        cdef int size
        cdef unsigned long hashvalue
        cdef char * data
        
        size = libzmq.zmq_msg_size(name)
        check_rc(size)
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
        cdef int rc, i
        cdef unsigned long hashvalue
        cdef double timestamp
        cdef carray_named message
        cdef carray_message_info * info
        cdef libzmq.zmq_msg_t notification
        
        rc = new_named_array(&message)
        check_rc(rc)
        rc = receive_named_array(&message, socket, flags)
        check_rc(rc)
        
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
            
            self._hashes[i] = hashvalue
            copy_named_array(self._messages[i], &message)
            
        finally:
            self.unlock()
        
        if notify_socket != NULL:
            rc = libzmq.zmq_msg_init(&notification)
            check_rc(rc)
            rc = libzmq.zmq_msg_copy(&notification, &message.name)
            check_rc(rc)
            rc = libzmq.zmq_msg_send(&notification, notify_socket, 0)
            check_rc(rc)
        
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
                return ReceivedArray.from_message(self._messages[i])
            else:
                raise IndexError("Index to messages out of range.")
        finally:
            self.unlock()
    
    def keys(self):
        self._build_namecache()
        return self._name_cache.keys()
    
    def __len__(self):
        return self._n_messages
    
    def __repr__(self):
        return "<Receiver frame={:d} keys=[{:s}]>".format(self._framecount, ",".join(self.keys()))
    
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
            