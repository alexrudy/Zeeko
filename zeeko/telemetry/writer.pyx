# -----------------
# Cython imports

cimport numpy as np
cimport zmq.backend.cython.libzmq as libzmq
from zmq.backend.cython.socket cimport Socket
from libc.stdlib cimport free
from ..utils.rc cimport check_zmq_rc, check_zmq_ptr
from ..utils.hmap cimport HashMap

# from ..handlers.client cimport Client
# I'd have to expose the client class?

from .chunk cimport Chunk, array_chunk, chunk_init, chunk_recv, chunk_close, chunk_copy
from ..messages.receiver cimport receive_header
from ..cyloop.statemachine cimport zmq_send_sentinel, PAUSE


# -----------------
# Python imports

import zmq
import h5py
import logging

cdef class Writer:
    
    def __cinit__(self):
        
        # Internal objects
        self.map = HashMap()
        self._chunks = NULL
        
        self.counter = 0
        self.last_message = 0.0
        
        self.file = None
        self.metadata_callback = None
        self.log = logging.getLogger(".".join([__name__, self.__class__.__name__]))

    def __dealloc__(self):
        self._release_arrays()

    def __len__(self):
        return self.map.n

    def __getitem__(self, bytes key):
        i = self.map[key]
        return Chunk.from_chunk(&self._chunks[i])
    
    def keys(self):
        return self.map.keys()

    def clear(self):
        """Clear the chunk recorder object."""
        self._release_arrays()

    cdef int _release_arrays(self) nogil except -1:
        """Release ZMQ messages held for chunks."""
        cdef size_t i
        if self._chunks != NULL:
            for i in range(self.map.n):
                chunk_close(&self._chunks[i])
            free(self._chunks)
            self._chunks = NULL
            self.map.clear()
    
    def receive(self, Socket socket not None, Socket notify not None, int flags = 0):
        """Receive a full message"""
        cdef int rc
        cdef void * handle = socket.handle
        cdef void * notify_handle = notify.handle
        with nogil:
            rc = self._receive(handle, flags, notify_handle)
        return rc
    
    cdef int _receive(self, void * socket, int flags, void * interrupt) nogil except -1:
        cdef int rc = 0
        cdef int value = 1
        cdef size_t optsize = sizeof(int)
        cdef unsigned int fc = 0
        cdef int nm = 0
        cdef double tm = 0.0
        cdef libzmq.zmq_msg_t topic
        
        rc = check_zmq_rc(libzmq.zmq_msg_init(&topic))
        try:
            rc = receive_header(socket, &topic, &fc, &nm, &tm, flags)
        finally:
            rc = check_zmq_rc(libzmq.zmq_msg_close(&topic))
        
        if nm == 0:
            zmq_send_sentinel(interrupt, PAUSE, 0)
            return -2
        
        if self.last_message < tm:
            self.last_message = tm
            
        while value == 1:
            rc = self._receive_chunk(socket, flags, interrupt)
            rc = check_zmq_rc(libzmq.zmq_getsockopt(socket, libzmq.ZMQ_RCVMORE, &value, &optsize))
        return rc
    
    cdef int _receive_chunk(self, void * socket, int flags, void * interrupt) nogil except -1:
        cdef int rc = 0
        cdef int i
        cdef unsigned int fc = 0
        cdef array_chunk chunk
        
        rc = chunk_init(&chunk)
        chunk_recv(&chunk, socket, flags)
        i = self.map.get(<char *>libzmq.zmq_msg_data(&chunk.name), libzmq.zmq_msg_size(&chunk.name))
        if i == -1:
            i = self.map.insert(<char *>libzmq.zmq_msg_data(&chunk.name), libzmq.zmq_msg_size(&chunk.name))
            self._chunks = <array_chunk *>self.map.reallocate(self._chunks, sizeof(array_chunk))
            rc = chunk_init(&self._chunks[i])
            
        chunk_copy(&self._chunks[i], &chunk)
        
        with gil:
            pychunk = Chunk.from_chunk(&self._chunks[i])
            if self.metadata_callback is None:
                md = {}
            else:
                md = self.metadata_callback()
            pychunk.write(self.file, metadata=md)
            self.log.debug("Wrote chunk {0} to {1}".format(pychunk.name , self.file.name))
        
        return rc
    
    