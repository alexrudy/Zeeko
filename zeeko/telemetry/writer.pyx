cimport numpy as np

import zmq
import h5py

from zmq.utils import jsonapi

from ..workers.base cimport Worker
from ..workers.state cimport *

from .chunk cimport Chunk, array_chunk, chunk_append, chunk_init, chunk_send, chunk_close, chunk_recv

from ..messages.utils cimport check_rc, check_ptr
from ..messages.receiver cimport receive_header

cimport zmq.backend.cython.libzmq as libzmq
from zmq.backend.cython.socket cimport Socket

from libc.stdlib cimport free, malloc, realloc
from libc.string cimport memcpy
from libc.stdio cimport printf

cdef class Writer(Worker):
    
    cdef int _n_arrays
    cdef array_chunk ** _chunks
    cdef str filename
    cdef readonly str notify_address
    cdef readonly int counter
    cdef Socket _inbound
    cdef Socket _outbound
    
    def __init__(self, ctx, address, filename):
        self._n_arrays = 0
        self.counter = 0
        ctx = ctx or zmq.Context.instance()
        self.filename = filename
        self._inbound = ctx.socket(zmq.PULL)
        self._outbound = ctx.socket(zmq.PUSH)
        self.notify_address = "inproc://{:s}-notify".format(hex(id(self)))
        super(Writer, self).__init__(ctx, address)
        self.thread.start()
    
    def __dealloc__(self):
        if self._chunks is not NULL:
            for i in range(self._n_arrays):
                if self._chunks[i] is not NULL:
                    free(self._chunks[i])
            free(self._chunks)
    
    cdef int _run(self) nogil except -1:
        cdef void * inbound = self._inbound.handle
        cdef void * internal = self._internal.handle
        cdef int sentinel
        cdef double delay = 0.0
        cdef int rc
        cdef libzmq.zmq_pollitem_t items[2]
        items[0].socket = inbound
        items[1].socket = internal
        items[0].events = libzmq.ZMQ_POLLIN
        items[1].events = libzmq.ZMQ_POLLIN
        self.counter = 0
        while True:
            rc = libzmq.zmq_poll(items, 2, self.timeout)
            check_rc(rc)
            if (items[1].revents & libzmq.ZMQ_POLLIN):
                rc = zmq_recv_sentinel(internal, &sentinel, 0)
                self._state = sentinel
                return self.counter
            elif (items[0].revents & libzmq.ZMQ_POLLIN):
                rc = self._receive(inbound, 0)
                if rc < 0:
                    return rc
                rc = self._post_receive()
                if rc != 0:
                    return rc
    
    cdef int _receive(self, void * socket, int flags) nogil except -1:
        cdef int rc = 0
        cdef int i
        cdef unsigned int fc = 0
        cdef int nm = 0
        cdef double tm = 0.0
        cdef libzmq.zmq_msg_t topic
        rc = libzmq.zmq_msg_init(&topic)
        check_rc(rc)
        try:
            rc = receive_header(socket, &topic, &fc, &nm, &tm, flags)
            check_rc(rc)
        finally:
            rc = libzmq.zmq_msg_close(&topic)
            check_rc(rc)
        if nm == 0:
            self._state = PAUSE
            return -2
        self._update_arrays(nm)
        for i in range(self._n_arrays):
            rc = chunk_recv(self._chunks[i], socket, flags)
        return rc
    
    cdef int _release_arrays(self) nogil except -1:
        if self._chunks is not NULL:
            for i in range(self._n_arrays):
                if self._chunks[i] is not NULL:
                    chunk_close(self._chunks[i])
                    free(self._chunks[i])
            free(self._chunks)
            self._chunks = NULL
            self._n_arrays = 0
    
    cdef int _update_arrays(self, int nm) nogil except -1:
        cdef int i, rc
        cdef array_chunk * chunk
        if nm < self._n_arrays:
            return 0
        self._chunks = <array_chunk **>realloc(<void *>self._chunks, sizeof(array_chunk *) * nm)
        check_ptr(self._chunks)
        for i in range(self._n_arrays, nm):
            chunk = <array_chunk *>malloc(sizeof(array_chunk))
            check_ptr(chunk)
            rc = chunk_init(chunk)
            check_rc(rc)
            self._chunks[i] = chunk
        self._n_arrays = nm
        return 0
    
    cdef int _write(self) except -1:
        cdef int rc = 0
        cdef int i
        cdef Chunk chunk
        with h5py.File(self.filename) as f:
            index = 0
            data = {}
            for i in range(self._n_arrays):
                chunk = Chunk.from_chunk(self._chunks[i])
                chunk.write(f)
                data[chunk.name] = f[chunk.name].attrs['index']
        self._outbound.send_json({'event':'write', 'filename':self.filename, 'data':data})
    
    cdef int _post_receive(self) nogil except -1:
        with gil:
            self._write()
        self._release_arrays()
        
    def _py_post_run(self):
        self._outbound.send_json({'event':'post_run', 'state':self.state})
        
        
    def _py_pre_work(self):
        super(Writer, self)._py_pre_work()
        self._inbound.connect(self.address)
        self._outbound.bind(self.notify_address)
    
    def _py_post_work(self):
        super(Writer, self)._py_post_work()
        self._outbound.unbind(self.notify_address)
        self._inbound.disconnect(self.address)
        self._inbound.close()
        self._outbound.close()

    