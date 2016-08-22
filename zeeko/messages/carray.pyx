import numpy as np
cimport numpy as np

from .utils cimport check_rc, check_ptr
cimport zmq.backend.cython.libzmq as libzmq
np.import_array()

from libc.time cimport time_t, time
from libc.stdlib cimport free, malloc
from libc.string cimport strndup, memcpy

cdef int new_array(carray_message * message) nogil except -1:
    """
    Initialize the messages required for sending and receiving a new array.
    """
    cdef int rc = 0
    
    message.metadata = <libzmq.zmq_msg_t *>malloc(sizeof(libzmq.zmq_msg_t))
    rc = libzmq.zmq_msg_init(message.metadata)
    check_rc(rc)
    
    message.data = <libzmq.zmq_msg_t *>malloc(sizeof(libzmq.zmq_msg_t))
    rc = libzmq.zmq_msg_init(message.data)
    check_rc(rc)
    return rc
    
cdef int new_named_array(carray_named * message) nogil except -1:
    """
    Initialize the messages required for sending and receiving a named array.
    """
    cdef int rc = 0
    message.name = <libzmq.zmq_msg_t *>malloc(sizeof(libzmq.zmq_msg_t))
    rc = libzmq.zmq_msg_init(message.name)
    check_rc(rc)
    
    return new_array(&message.array)

cdef int empty_array(carray_message * message) nogil except -1:
    """
    Initialize the messages required for sending and receiving a new array.
    """
    cdef int rc = 0
    message.metadata = <libzmq.zmq_msg_t *>malloc(sizeof(libzmq.zmq_msg_t))
    rc = libzmq.zmq_msg_init_size(message.metadata, 0)
    check_rc(rc)
    
    message.data = <libzmq.zmq_msg_t *>malloc(sizeof(libzmq.zmq_msg_t))
    rc = libzmq.zmq_msg_init_size(message.data, 0)
    check_rc(rc)
    return rc

cdef int empty_named_array(carray_named * message) nogil except -1:
    """
    Initialize the messages required for sending and receiving a named array.
    """
    cdef int rc = 0
    message.name = <libzmq.zmq_msg_t *>malloc(sizeof(libzmq.zmq_msg_t))
    rc = libzmq.zmq_msg_init_size(message.name, 0)
    check_rc(rc)
    return empty_array(&message.array)
    
cdef int close_named_array(carray_named * message) nogil except -1:
    """
    Initialize the messages required for sending and receiving a named array.
    """
    cdef int rc = 0
    rc = libzmq.zmq_msg_close(message.name)
    check_rc(rc)
    free(message.name)
    return close_array(&message.array)

cdef int close_array(carray_message * message) nogil except -1:
    """
    Initialize the messages required for sending and receiving a named array.
    """
    cdef int rc = 0
    rc = libzmq.zmq_msg_close(message.metadata)
    check_rc(rc)
    free(message.metadata)
    
    rc = libzmq.zmq_msg_close(message.data)
    check_rc(rc)
    free(message.data)
    
    return rc

cdef int copy_array(carray_message * dest, carray_message * src) nogil except -1:
    """
    Perform the necessary ZMQ copies.
    """
    cdef int rc = 0
    rc = libzmq.zmq_msg_copy(dest.metadata, src.metadata)
    check_rc(rc)
    rc = libzmq.zmq_msg_copy(dest.data, src.data)
    check_rc(rc)
    return rc

cdef int copy_named_array(carray_named * dest, carray_named * src) nogil except -1:
    """
    Perform the necessary ZMQ copies.
    """
    cdef int rc = 0
    rc = libzmq.zmq_msg_copy(dest.name, src.name)
    check_rc(rc)
    return copy_array(&dest.array, &src.array)

cdef int send_array(carray_message * message, void * socket, int flags) nogil except -1:
    """
    Send a numpy array over a ZMQ socket.
    Requires an array prepared with a carray_message."""
    cdef int rc = 0
    cdef libzmq.zmq_msg_t zmessage, zmetadata
    rc = libzmq.zmq_msg_init(&zmetadata)
    check_rc(rc)
    libzmq.zmq_msg_copy(&zmetadata, message.metadata)
    rc = libzmq.zmq_msg_send(&zmetadata, socket, flags|libzmq.ZMQ_SNDMORE)
    check_rc(rc)
    rc = libzmq.zmq_msg_init(&zmessage)
    check_rc(rc)
    libzmq.zmq_msg_copy(&zmessage, message.data)
    rc = libzmq.zmq_msg_send(&zmessage, socket, flags)
    check_rc(rc)
    
    return rc

cdef int send_named_array(carray_named * message, void * socket, int flags) nogil except -1:
    """
    Send a numpy array and name over a ZMQ socket.
    Requires an array prepared with a carray_named.
    """
    
    cdef int rc = 0
    cdef libzmq.zmq_msg_t zmessage
    rc = libzmq.zmq_msg_init(&zmessage)
    check_rc(rc)
    
    libzmq.zmq_msg_copy(&zmessage, message.name)
    rc = libzmq.zmq_msg_send(&zmessage, socket, flags|libzmq.ZMQ_SNDMORE)
    check_rc(rc)
    
    return send_array(&message.array, socket, flags)
    
cdef int receive_array(carray_message * message, void * socket, int flags) nogil except -1:
    """
    Receive a known, already allocated message object. Ensures that the message will
    be received entirely.
    """
    cdef int rc
    
    # Recieve the metadata message
    rc = libzmq.zmq_msg_recv(message.metadata, socket, flags)
    check_rc(rc)
    
    # Recieve the array data.
    rc = libzmq.zmq_msg_recv(message.data, socket, flags)
    check_rc(rc)
    return rc
    
cdef int receive_named_array(carray_named * message, void * socket, int flags) nogil except -1:
    """
    Receive a known, already allocated message object. Ensures that the message will
    be received entirely.
    """
    cdef int rc
    
    # Recieve the metadata message
    rc = libzmq.zmq_msg_recv(message.name, socket, flags)
    check_rc(rc)
        
    return receive_array(&message.array, socket, flags)