import numpy as np
cimport numpy as np

from .utils cimport check_rc, check_ptr
cimport zmq.backend.cython.libzmq as libzmq
np.import_array()

from libc.time cimport time_t, time
from libc.stdlib cimport free, malloc
from libc.string cimport strndup, memcpy

cdef int send_array(void * socket, carray_message * message, int flags) nogil except -1:
    """
    Send a numpy array over a ZMQ socket.
    Requires an array prepared with a carray_message."""
    cdef int rc = 0
    
    rc = libzmq.zmq_sendbuf(socket, message.metadata, message.nm, flags|libzmq.ZMQ_SNDMORE)
    check_rc(rc)
    
    rc = libzmq.zmq_sendbuf(socket, message.data, message.n, flags)
    check_rc(rc)
    
    return rc

cdef int send_named_array(void * socket, carray_named * message, int flags) nogil except -1:
    """
    Send a numpy array and name over a ZMQ socket.
    Requires an array prepared with a carray_named.
    """
    
    cdef int rc = 0
    
    rc = libzmq.zmq_sendbuf(socket, message.name, message.nm, flags|libzmq.ZMQ_SNDMORE)
    check_rc(rc)
    
    return send_array(socket, &message.array, flags)
    
cdef int receive_array(void * socket, carray_message * message, int flags) nogil except -1:
    """
    Receive a known, already allocated message object. Ensures that the message will
    be received entirely.
    """
    cdef int nm, n, rc
    cdef libzmq.zmq_msg_t zmessage
    cdef void * raw
    
    # Recieve the metadata message
    libzmq.zmq_msg_init(&zmessage)
    try:
        rc = libzmq.zmq_msg_recv(&zmessage, socket, flags)
        check_rc(rc)
        nm = libzmq.zmq_msg_size(&zmessage)
        check_rc(nm)
        message.nm = <size_t>nm
        
        raw = libzmq.zmq_msg_data(&zmessage)
        check_ptr(raw)
        message.metadata = strndup(<char *>raw, message.nm)
    finally:
        libzmq.zmq_msg_close(&zmessage)
    
    
    # Recieve the array data.
    libzmq.zmq_msg_init(&zmessage)
    try:
        rc = libzmq.zmq_msg_recv(&zmessage, socket, flags)
        check_rc(rc)
        n = libzmq.zmq_msg_size(&zmessage)
        check_rc(n)
        
        if n > message.n:
            message.data = malloc(n)
        
        message.n = n
        raw = libzmq.zmq_msg_data(&zmessage)
        check_ptr(raw)
        
        check_ptr(message.data)
        memcpy(message.data, raw, n)
    finally:
        libzmq.zmq_msg_close(&zmessage)
    
    return rc
    
cdef int receive_named_array(void * socket, carray_named * message, int flags) nogil except -1:
    """
    Receive a known, already allocated message object. Ensures that the message will
    be received entirely.
    """
    cdef int nm, rc
    cdef libzmq.zmq_msg_t zmessage
    cdef void * raw
    
    # Recieve the metadata message
    libzmq.zmq_msg_init(&zmessage)
    try:
        rc = libzmq.zmq_msg_recv(&zmessage, socket, flags)
        check_rc(rc)
        nm = libzmq.zmq_msg_size(&zmessage)
        check_rc(nm)
        message.nm = <size_t>nm
        
        raw = libzmq.zmq_msg_data(&zmessage)
        check_ptr(raw)
        message.name = strndup(<char *>raw, message.nm)
    finally:
        libzmq.zmq_msg_close(&zmessage)
        
    return receive_array(socket, &message.array, flags)