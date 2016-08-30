cimport numpy as np

import zmq
from ..workers.client cimport Client
from ..workers.state cimport *

from .chunk cimport Chunk, array_chunk, chunk_append, chunk_init_array, chunk_send, chunk_close
from ..messages.utils cimport check_rc, check_ptr
from ..messages.publisher cimport send_header
from ..utils.clock cimport current_time

cimport zmq.backend.cython.libzmq as libzmq
from zmq.backend.cython.socket cimport Socket
from libc.stdlib cimport free, malloc, realloc
from libc.string cimport memcpy
from libc.stdio cimport printf

cdef class Recorder(Client):
    
    cdef int _n_arrays
    cdef unsigned int _chunkcount
    cdef array_chunk ** _chunks
    cdef str writer_address
    cdef Socket _writer
    
    cdef int offset
    cdef readonly int chunksize
    
    def __init__(self, ctx, address, writer_address, chunksize):
        self.offset = -1
        self._n_arrays = 0
        self._chunkcount = 0
        self.chunksize = chunksize
        ctx = ctx or zmq.Context.instance()
        self.writer_address = writer_address
        self._writer = ctx.socket(zmq.PUSH)
        super(Recorder, self).__init__(ctx, address)
    
    def __dealloc__(self):
        if self._chunks is not NULL:
            for i in range(self._n_arrays):
                if self._chunks[i] is not NULL:
                    free(self._chunks[i])
            free(self._chunks)
    
    cdef int _release_arrays(self) nogil except -1:
        if self._chunks is not NULL:
            for i in range(self._n_arrays):
                if self._chunks[i] is not NULL:
                    chunk_close(self._chunks[i])
                    free(self._chunks[i])
            free(self._chunks)
            self._chunks = NULL
            self._n_arrays = 0
    
    cdef int _update_arrays(self) nogil except -1:
        cdef int i, rc
        cdef array_chunk * chunk
        if self.receiver._n_messages < self._n_arrays:
            return 0
        self._chunks = <array_chunk **>realloc(<void *>self._chunks, sizeof(array_chunk *) * self.receiver._n_messages)
        check_ptr(self._chunks)
        for i in range(self._n_arrays, self.receiver._n_messages):
            chunk = <array_chunk *>malloc(sizeof(array_chunk))
            check_ptr(chunk)
            rc = chunk_init_array(chunk, self.receiver._messages[i], self.chunksize)
            check_rc(rc)
            self._chunks[i] = chunk
        self._n_arrays = self.receiver._n_messages
        return 0
    
    cdef int _post_receive(self) nogil except -1:
        cdef int index = self.receiver._framecount
        cdef int i, rc
        self.counter = self.counter + 1
        self.delay = current_time() - self.receiver.last_message
        if self.delay > self.maxlag:
            self._state = PAUSE
            self._snail_deaths = self._snail_deaths + 1
            return self.counter
        
        if (self.offset == -1) or (self.receiver._framecount < self.offset):
            self.offset = self.receiver._framecount
            index = 0
        else:
            index = self.receiver._framecount - self.offset
        
        self._update_arrays()
        for i in range(self._n_arrays):
            rc = chunk_append(self._chunks[i], self.receiver._messages[i], index)
        if index == (self.chunksize - 1):
            self._send_for_output(self._writer.handle)
        
    cdef int _send_for_output(self, void * socket) nogil except -1:
        cdef int i, rc
        if self.offset != -1:
            self._chunkcount += 1
            send_header(socket, self._chunkcount, self._n_arrays, libzmq.ZMQ_SNDMORE)
            for i in range(self._n_arrays - 1):
                rc = chunk_send(self._chunks[i], socket, libzmq.ZMQ_SNDMORE)
            rc = chunk_send(self._chunks[self._n_arrays - 1], socket, 0)
        else:
            # Sentinel to turn off writer.
            printf("Requesting stop\n")
            send_header(socket, 0, 0, 0)
        self._release_arrays()
        self.offset = -1
        
    def _py_pre_work(self):
        super(Recorder, self)._py_pre_work()
        self._writer.bind(self.writer_address)
    
    def _py_post_work(self):
        super(Recorder, self)._py_post_work()
        self._writer.unbind(self.writer_address)
        self._writer.close()
    
    def _complete(self):
        """Handler for when the buffer is complete and should be pushed to the writer."""
        cdef void * handle = self._writer.handle
        with nogil:
            self._send_for_output(handle)
    
    def _py_run(self):
        try:
            super(Recorder, self)._py_run()
        except (IndexError, ValueError) as e:
            self._complete()
            self.log.info("RESET: Message changed while receiving: {0.__class__.__name__:s}:{0:s}".format(e))
        else:
            self.log.info("RUN: Finished, notifying writer.")
            self._complete()
        
    