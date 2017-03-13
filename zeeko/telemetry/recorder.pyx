
# -----------------
# Cython imports

cimport numpy as np
cimport zmq.backend.cython.libzmq as libzmq
from zmq.backend.cython.socket cimport Socket
from libc.stdlib cimport free
from libc.string cimport memset

from ..utils.rc cimport check_zmq_rc, check_zmq_ptr
from ..utils.clock cimport current_time
from ..utils.hmap cimport HashMap, hashentry
from ..utils.condition cimport event_init, event_trigger, event_destroy

# from ..handlers.client cimport Client
# I'd have to expose the client class?

from .chunk cimport Chunk, array_chunk, chunk_append, chunk_init_array, chunk_send, chunk_close
from ..messages.publisher cimport send_header
from ..messages.carray cimport carray_message_info, carray_named, new_named_array, receive_named_array


# -----------------
# Python imports

import zmq
import logging
from ..utils.sandwich import sandwich_unicode

cdef int dealloc_chunks(void * chunk, void * data) nogil except -1:
    return chunk_close(<array_chunk *>chunk)

# This class should match the API of the Receiver, but should return chunks
# instead of single messages.
cdef class Recorder:
    """A recorder receives messages, and coalesces them into chunks."""
    
    def __cinit__(self):
        
        # Internal objects
        self.map = HashMap(sizeof(array_chunk))
        self.map._dcb = dealloc_chunks
        
        self._event_map = EventMap()
        
        # Indicate that no offset has been detected.
        self.offset = -1
        self.counter = 0
        self.framecount = 0
        self.counter_at_done = 0
        
        # Accounting objects
        self._chunkcount = 0
        self._chunksize = -1 # Will be re-initialized by __init__
        self.pushed = Event()
        self.log = logging.getLogger(".".join([__name__, self.__class__.__name__]))
        
    
    def __init__(self, chunksize):
        if not int(chunksize) >= 0:
            raise ValueError("Chunksize must be non-negative.")
        self.chunksize = chunksize
    
    def __dealloc__(self):
        self._release_arrays()
        
    def __repr__(self):
        return "<Recorder frame={0:d} count={1:d} offset={2:d} keys=[{3:s}]>".format(self.framecount, self.counter, self.offset, ",".join(self.keys()))
    
    def __len__(self):
        return self.map.n
    
    def __getitem__(self, key):
        cdef hashentry * h = self.map.pyget(key)
        if h.vinit == 0:
            raise KeyError(key)
        return Chunk.from_chunk(<array_chunk *>(h.value))
        
    def __iter__(self):
        return iter(self.map.keys())
        
    def __setitem__(self, key, value):
        raise NotImplementedError("Can't mutate recorder dictionary.")
    
    def __delitem__(self, key):
        raise NotImplementedError("Can't mutate recorder dictionary.")
    
    def clear(self):
        """Clear the chunk recorder object."""
        self._release_arrays()
    
    def event(self, name):
        """Return the event details"""
        return self._event_map.event(name)
    
    cdef int _release_arrays(self) nogil except -1:
        """Release ZMQ messages held for chunks."""
        self.offset = -1
        self.counter_at_done = 0
        self.map.clear()
        return 0
    
    def receive(self, Socket socket not None, Socket notify = None, int flags = 0):
        """Receive a full message"""
        cdef void * handle = socket.handle
        cdef void * notify_handle = NULL
        if notify is not None:
            notify_handle = notify.handle
        with nogil:
            self._receive(handle, flags, notify_handle, libzmq.ZMQ_NOBLOCK)
    
    def notify(self, Socket notify = None, int flags = 0):
        """Perform a partial notification."""
        cdef void * notify_handle = NULL
        if notify is not None:
            notify_handle = notify.handle
        with nogil:
            self._notify_partial_completion(notify_handle, flags)
    
    cdef int _receive(self, void * socket, int flags, void * notify, int notify_flags) nogil except -1:
        cdef int rc = 0
        cdef int value = 1
        cdef size_t optsize = sizeof(int)
        while value == 1:
            rc = self._receive_message(socket, flags, notify, notify_flags)
            rc = check_zmq_rc(libzmq.zmq_getsockopt(socket, libzmq.ZMQ_RCVMORE, &value, &optsize))
        return rc
        
    cdef int _receive_message(self, void * socket, int flags, void * notify, int notify_flags) nogil except -1:
        cdef int rc = 0
        cdef int i # Index in the message list.
        cdef int j # Index in the event list
        cdef long index
        cdef bint valid_index, initial_index
        cdef carray_named message
        cdef carray_message_info * info
        cdef hashentry * entry
        cdef libzmq.zmq_msg_t notification
        
        # Increment the message counter.
        self.counter += 1
        
        # Recieve the message
        rc = new_named_array(&message)
        rc = receive_named_array(&message, socket, flags)
        
        # Record the received time.
        info = <carray_message_info *>libzmq.zmq_msg_data(&message.array.info)
        if self.last_message < info.timestamp:
            self.last_message = info.timestamp
        
        if self.offset == -1:
            # Handle initial state of the offset.
            self.offset = info.framecount
        elif self.offset > info.framecount:
            # Handle a framecounter which has cycled back to 0, or which
            # indicates that a message was received out of order.
            self._notify_completion(notify, notify_flags)
            self.offset = info.framecount
        
        self.framecount = info.framecount
        
        # Update the chunk array
        entry = self.map.get(<char *>libzmq.zmq_msg_data(&message.name), libzmq.zmq_msg_size(&message.name))
        if not entry.vinit:
            rc = chunk_init_array(<array_chunk * >entry.value, &message, self._chunksize)
            entry.vinit = 1
        chunk = <array_chunk * >entry.value
        # Save the message to the chunk array, initializing if necessary.
        index = (<long>info.framecount - <long>self.offset)
        valid_index = (index > 0 and ((chunk.last_index < (<size_t>index))))
        initial_index = (chunk.last_index == 0 and index == 0)
        if valid_index or initial_index:
            if index < chunk.chunksize:
                rc = chunk_append(chunk, &message, <size_t>index)
        
        # Trigger the event
        self._event_map._trigger_event(<char *>libzmq.zmq_msg_data(&message.name), libzmq.zmq_msg_size(&message.name))
        
        # Handle the case where this is the last message we needed to be done.
        if self._check_for_completion() == 1:
            self._notify_completion(notify, notify_flags)
        
        return rc
        
    property chunksize:
        """The number of array messages to coalesce into a single chunk."""
        def __get__(self):
            return self._chunksize
        
        def __set__(self, value):
            if not self.counter == 0:
                raise ValueError("Can't set chunk size after receiver has allocated chunks.")
            self._chunksize = value
        
    property complete:
        def __get__(self):
            return self._check_for_completion() == 1
        
    property chunkcount:
        def __get__(self):
            return self._chunkcount
    
    cdef int _check_for_completion(self) nogil except -1:
        """This method checks to see if the chunks have completed."""
        cdef int rc = 0
        cdef size_t i, n = 0
        if self.map.n == 0:
            return 0
        
        # Complete if all arrays are full.
        for i in range(self.map.n):
            if (<array_chunk *>(self.map.index_get(i).value)).last_index < (self._chunksize - 1):
                n += 1
            else:
                with gil:
                    self.log.debug("{0:s} done".format(self.map.keys()[i]))
                if self.counter_at_done == 0:
                    self.counter_at_done = self.counter
                elif (self.counter_at_done + (2 * self.map.n) < self.counter):
                    return 1
        if n != 0:
            if n < self.map.n:
                with gil:
                    self.log.debug(",".join(self.map.keys()))
                    self.log.debug("n={0:d} nn={1:d} {2:s} not finished.".format(n, self.map.n, ",".join(key for i,key in enumerate(self.map.keys()) if (<array_chunk *>(self.map.index_get(i).value)).last_index < (self._chunksize - 1))))
                    self.log.debug("n={0:d} {1:s} finished.".format(n, ",".join(key for i,key in enumerate(self.map.keys()) if (<array_chunk *>(self.map.index_get(i).value)).last_index >= (self._chunksize - 1))))
                    
            return 0
        else:
            return 1
            
    cdef int _notify_partial_completion(self, void * socket, int flags) nogil except -1:
        if self.offset == -1:
            return 0
        return self._notify_completion(socket, flags)
    
    cdef int _notify_completion(self, void * socket, int flags) nogil except -1:
        """Message the writer to output chunks."""
        cdef int i, rc
        cdef libzmq.zmq_msg_t topic
        
        # Increment the counter of chunks.
        self._chunkcount += 1
        
        if socket is not NULL:
            # Send the topic message.
            rc = check_zmq_rc(libzmq.zmq_msg_init_size(&topic, 0))
            try:
                rc = check_zmq_rc(send_header(socket, &topic, self._chunkcount, self.map.n, flags|libzmq.ZMQ_SNDMORE))
            finally:
                rc = check_zmq_rc(libzmq.zmq_msg_close(&topic))
            
            # Send individual messages as a single packet.
            for i in range(self.map.n - 1):
                rc = chunk_send(<array_chunk *>(self.map.index_get(i).value), socket, flags|libzmq.ZMQ_SNDMORE)
            rc = chunk_send(<array_chunk *>(self.map.index_get(self.map.n - 1).value), socket, flags)
        
        with gil:
            self.log.debug("Sent chunks after completion")
        
        # Notify listeners that something was sent.
        self.pushed._set()
        
        # Release the memory held by the sent chunks
        self._release_arrays()
        return rc
        
    cdef int _notify_close(self, void * socket, int flags) nogil except -1:
        """Message the writer to notify that the stream is done."""
        cdef int i, rc
        cdef libzmq.zmq_msg_t topic
        
        if socket is not NULL:
            # Send a sentinel method to tell the writer this recorder is closed.
            rc = check_zmq_rc(libzmq.zmq_msg_init_size(&topic, 0))
            try:
                rc = check_zmq_rc(send_header(socket, &topic, 0, 0, flags))
            finally:
                rc = check_zmq_rc(libzmq.zmq_msg_close(&topic))
            
        # Notify listeners that something was sent.
        self.pushed._set()
        
        # Release the memory held by arrays
        self._release_arrays()
        return rc
    

        
    