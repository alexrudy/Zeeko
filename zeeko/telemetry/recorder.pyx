cimport numpy as np

import zmq
from ..workers.client cimport Client
from ..workers.state cimport *

from .chunk cimport Chunk, array_chunk, chunk_append, chunk_init_array, chunk_send, chunk_close
from ..messages.utils cimport check_rc, check_ptr
from ..messages.publisher cimport send_header
from ..messages.carray cimport carray_message_info
from ..utils.clock cimport current_time

cimport zmq.backend.cython.libzmq as libzmq
from zmq.backend.cython.socket cimport Socket
from libc.stdlib cimport free, malloc, realloc
from libc.string cimport memcpy
#from libc.stdio cimport printf

cdef class Recorder(Client):
    
    cdef int _n_arrays
    cdef size_t * _indexes
    cdef unsigned int _chunkcount
    cdef array_chunk ** _chunks
    cdef str writer_address
    cdef Socket _writer
    
    cdef long offset
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
            free(self._indexes)
    
    cdef int _release_arrays(self) nogil except -1:
        """Release ZMQ messages held for chunks."""
        if self._chunks is not NULL:
            for i in range(self._n_arrays):
                if self._chunks[i] is not NULL:
                    chunk_close(self._chunks[i])
                    free(self._chunks[i])
            free(self._chunks)
            self._chunks = NULL
            free(self._indexes)
            self._indexes = NULL
            self._n_arrays = 0
    
    cdef int _update_arrays(self) nogil except -1:
        """Generate new chunks to correspond to input arrays."""
        cdef int i, rc
        cdef array_chunk * chunk
        
        # If we have enough chunks, do nothing.
        if self.receiver._n_messages < self._n_arrays:
            return 0
        
        # Reallocate and initialize chunks.
        self._chunks = <array_chunk **>realloc(<void *>self._chunks, sizeof(array_chunk *) * self.receiver._n_messages)
        check_ptr(self._chunks)
        self._indexes = <size_t *>realloc(<void *>self._indexes, sizeof(size_t) * self.receiver._n_messages)
        check_ptr(self._indexes)
        
        for i in range(self._n_arrays, self.receiver._n_messages):
            chunk = <array_chunk *>malloc(sizeof(array_chunk))
            check_ptr(chunk)
            rc = chunk_init_array(chunk, self.receiver._messages[i], self.chunksize)
            check_rc(rc)
            self._chunks[i] = chunk
            self._indexes[i] = 0
        
        self._n_arrays = self.receiver._n_messages
        return 0
    
    cdef int _post_receive(self) nogil except -1:
        cdef long index = 0
        cdef long last_index = 0
        cdef unsigned long framecount
        cdef int i, rc, n_done = 0
        
        # Accounting: Increment number of messages,
        # and ensure that we aren't too slow.
        self.counter = self.counter + 1
        self.delay = current_time() - self.receiver.last_message
        if self.delay > self.maxlag:
            self._state = PAUSE
            self.snail_deaths = self.snail_deaths + 1
            return self.counter
        
        for i in range(self._n_arrays):
            if self._indexes[i] >= (self.chunksize - 1):
                n_done = n_done + 1
        
        if n_done != 0:
            if n_done == self._n_arrays:
                self._send_for_output(self._writer.handle, 0)
        
        # Determine the next index to set.
        if (self.offset == -1):
            self.offset = self.receiver._framecount
        elif (self.receiver._framecount < self.offset):
        
            #TODO: Handle out of order messages more gracefully.
            self._state = PAUSE
            return self.counter
        
        self._update_arrays()
        
        for i in range(self._n_arrays):
            framecount = (<carray_message_info *>libzmq.zmq_msg_data(&self.receiver._messages[i].array.info)).framecount
            index = (<long>framecount - <long>self.offset)
            if index >= 0 and ((self._indexes[i] < (<size_t>index)) or (self._indexes[i] == 0 and index == 0)):
                rc = chunk_append(self._chunks[i], self.receiver._messages[i], <size_t>index)
                self._indexes[i] = index
                
        return 0
        
    cdef int _send_for_output(self, void * socket, int flags) nogil except -1:
        cdef int i, rc
        cdef libzmq.zmq_msg_t topic
        if self.offset != -1:
            self._chunkcount += 1
            rc = libzmq.zmq_msg_init_size(&topic, 0)
            check_rc(rc)
            try:
                rc = send_header(socket, &topic, self._chunkcount, self._n_arrays, flags|libzmq.ZMQ_SNDMORE)
                check_rc(rc)
            finally:
                rc = libzmq.zmq_msg_close(&topic)
                check_rc(rc)
            for i in range(self._n_arrays - 1):
                rc = chunk_send(self._chunks[i], socket, flags|libzmq.ZMQ_SNDMORE)
            rc = chunk_send(self._chunks[self._n_arrays - 1], socket, flags)
        else:
            # Sentinel to turn off writer.
            rc = libzmq.zmq_msg_init_size(&topic, 0)
            check_rc(rc)
            try:
                rc = send_header(socket, &topic, 0, 0, 0)
                check_rc(rc)
            finally:
                rc = libzmq.zmq_msg_close(&topic)
                check_rc(rc)
        self._release_arrays()
        self.offset = -1
        return 0
        
    def _py_pre_work(self):
        super(Recorder, self)._py_pre_work()
        self._writer.bind(self.writer_address)
    
    def _py_post_work(self):
        super(Recorder, self)._py_post_work()
        self._writer.unbind(self.writer_address)
        self._writer.close(linger=0)
    
    def _complete(self):
        """Handler for when the buffer is complete and should be pushed to the writer."""
        cdef void * handle = self._writer.handle
        with nogil:
            self._send_for_output(handle, 0)
    
    def _py_run(self):
        try:
            self.log.debug("OFFSET: {:d}".format(self.offset))
            super(Recorder, self)._py_run()
        except (IndexError, ValueError) as e:
            self.log.info("RESET: Message changed while receiving: {0.__class__.__name__:s}:{0:s}".format(e))
            self.log.debug("OFFSET: {:d}".format(self.offset))
            self._complete()
        else:
            self.log.info("RUN: Finished, notifying writer.")
            self._complete()
        
    