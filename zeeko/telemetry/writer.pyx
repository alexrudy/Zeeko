# -----------------
# Cython imports

cimport numpy as np
cimport zmq.backend.cython.libzmq as libzmq
from zmq.backend.cython.socket cimport Socket
from libc.stdlib cimport free
from libc.string cimport memset
from ..utils.rc cimport check_zmq_rc, check_zmq_ptr
from ..utils.hmap cimport HashMap, hashentry, HASHINIT, HASHWRITE

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

cdef int dealloc_chunks(void * chunk, void * data) nogil except -1:
    return chunk_close(<array_chunk *>chunk)


cdef class Writer:
    
    def __cinit__(self):
        
        # Internal objects
        self.map = HashMap(sizeof(array_chunk))
        self.map._dcb = dealloc_chunks
        
        self._event_map = EventMap()
        
        self.counter = 0
        self._framecount = 0
        self.last_message = 0.0
        
        self.file = None
        self.metadata_callback = None
        self.log = logging.getLogger(".".join([__name__, self.__class__.__name__]))

    def __dealloc__(self):
        self.map.clear()

    def __len__(self):
        return self.map.n

    def __getitem__(self, key):
        cdef hashentry * h = self.map.pyget(key)
        if not (h.flags & HASHINIT):
            raise KeyError(key)
        return Chunk.from_chunk(<array_chunk *>(h.value))
    
    def __iter__(self):
        return iter(self.map.keys())
    
    @property
    def framecount(self):
        """The count of frames received by this object."""
        return self._framecount

    def clear(self):
        """Clear the chunk recorder object."""
        self._release_arrays()
    
    def event(self, name):
        """Return an event for receipt of a message named."""
        return self._event_map.event(name)
    
    cdef int _release_arrays(self) nogil except -1:
        """Release ZMQ messages held for chunks."""
        self.map.clear()
    
    def receive(self, Socket socket not None, Socket notify = None, int flags = 0):
        """Receive a full message"""
        cdef int rc
        cdef void * handle = socket.handle
        cdef void * notify_handle = NULL
        cdef hashentry * entry
        if notify is not None:
            notify_handle = notify.handle
        
        with nogil:
            rc = self._receive(handle, flags, notify_handle)
        
        for key in self.map:
            entry = self.map.pyget(key)
            if not (entry.flags & HASHWRITE):
                raise ValueError("Missed a chunk {0}".format(key))
        
        return rc
    
    cdef int _receive(self, void * socket, int flags, void * interrupt) nogil except -1:
        cdef int i = 0
        cdef int rc = 0
        cdef int value = 1
        cdef size_t optsize = sizeof(int)
        cdef unsigned long fc = 0
        cdef int nm = 0
        cdef double tm = 0.0
        cdef libzmq.zmq_msg_t topic
        cdef hashentry * entry
        
        for i in range(self.map.n):
            entry = self.map.index_get(i)
            entry.flags = entry.flags & (~HASHWRITE)
        
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
            rc = self._receive_chunk(socket, flags)
            rc = check_zmq_rc(libzmq.zmq_getsockopt(socket, libzmq.ZMQ_RCVMORE, &value, &optsize))
        self._framecount = fc
        
        for i in range(self.map.n):
            entry = self.map.index_get(i)
            if not (entry.flags & HASHWRITE):
                with gil:
                    self.log.warning("Missed a chunk write! {0:s}".format(self.map[i]))
        
        return rc
    
    cdef int _receive_chunk(self, void * socket, int flags) nogil except -1:
        cdef int rc = 0
        cdef int i
        cdef unsigned int fc = 0
        cdef array_chunk chunk
        cdef hashentry * entry
        
        rc = chunk_init(&chunk)
        chunk_recv(&chunk, socket, flags)
        
        entry = self.map.get(<char *>libzmq.zmq_msg_data(&chunk.name), libzmq.zmq_msg_size(&chunk.name))
        if not (entry.flags & HASHINIT):
            rc = chunk_init(<array_chunk * >entry.value)
            entry.flags = entry.flags | HASHINIT
        chunk_copy(<array_chunk * >entry.value, &chunk)
        
        with gil:
            pychunk = Chunk.from_chunk(<array_chunk * >entry.value)
            try:
                md = self.metadata_callback()
            except Exception:
                if self.metadata_callback is not None:
                    self.log.exception("Problem generating metadata:")
                md = {}
                self.log.warning("Using empty metadata attributes.")
            pychunk.write(self.file, metadata=md)
            self.log.debug("Wrote chunk {0} to {1}".format(pychunk.name , self.file.name))
            self.file.file.flush()
            self.counter += 1
        entry.flags = entry.flags | HASHWRITE
        
        self._event_map._trigger_event(<char *>libzmq.zmq_msg_data(&chunk.name), libzmq.zmq_msg_size(&chunk.name))
        chunk_close(&chunk)
        
        return rc
    
    