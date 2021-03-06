#cython: linetrace=True, boundscheck=False
import numpy as np
cimport numpy as np

from ..utils.rc cimport check_zmq_rc, check_zmq_ptr
from ..utils.msg cimport zmq_msg_hard_copy
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
    
    rc = libzmq.zmq_msg_init(&message.info)
    check_zmq_rc(rc)
    
    rc = libzmq.zmq_msg_init(&message.metadata)
    check_zmq_rc(rc)
    
    rc = libzmq.zmq_msg_init(&message.data)
    check_zmq_rc(rc)
    return rc
    
cdef int new_named_array(carray_named * message) nogil except -1:
    """
    Initialize the messages required for sending and receiving a named array.
    """
    cdef int rc = 0
    rc = libzmq.zmq_msg_init(&message.name)
    check_zmq_rc(rc)
    
    return new_array(&message.array)

cdef int empty_array(carray_message * message) nogil except -1:
    """
    Initialize the messages required for sending and receiving a new array.
    """
    cdef int rc = 0
    
    rc = libzmq.zmq_msg_init_size(&message.info, sizeof(carray_message_info))
    check_zmq_rc(rc)
    
    rc = libzmq.zmq_msg_init_size(&message.metadata, 0)
    check_zmq_rc(rc)
    
    rc = libzmq.zmq_msg_init_size(&message.data, 0)
    check_zmq_rc(rc)
    return rc

cdef int empty_named_array(carray_named * message) nogil except -1:
    """
    Initialize the messages required for sending and receiving a named array.
    """
    cdef int rc = 0
    rc = libzmq.zmq_msg_init_size(&message.name, 0)
    check_zmq_rc(rc)
    return empty_array(&message.array)
    
cdef int close_named_array(carray_named * message) nogil except -1:
    """
    Initialize the messages required for sending and receiving a named array.
    """
    cdef int rc = 0
    rc = libzmq.zmq_msg_close(&message.name)
    check_zmq_rc(rc)
    return close_array(&message.array)

cdef int close_array(carray_message * message) nogil except -1:
    """
    Initialize the messages required for sending and receiving a named array.
    """
    cdef int rc = 0
    rc = libzmq.zmq_msg_close(&message.info)
    check_zmq_rc(rc)
    rc = libzmq.zmq_msg_close(&message.metadata)
    check_zmq_rc(rc)
    rc = libzmq.zmq_msg_close(&message.data)
    check_zmq_rc(rc)
    return rc
    
cdef int copy_array_hard(carray_message * dst, carray_message * src) nogil except -1:
    """
    Make a hard copy of a carray structure.
    """
    cdef int rc = 0
    rc = zmq_msg_hard_copy(&dst.info, &src.info)
    rc = zmq_msg_hard_copy(&dst.metadata, &src.metadata)
    rc = zmq_msg_hard_copy(&dst.data, &src.data)
    return rc
    

cdef int copy_array(carray_message * dest, carray_message * src) nogil except -1:
    """
    Perform the necessary ZMQ copies.
    """
    cdef int rc = 0
    rc = libzmq.zmq_msg_copy(&dest.info, &src.info)
    check_zmq_rc(rc)
    rc = libzmq.zmq_msg_copy(&dest.metadata, &src.metadata)
    check_zmq_rc(rc)
    rc = libzmq.zmq_msg_copy(&dest.data, &src.data)
    check_zmq_rc(rc)
    return rc

cdef int copy_named_array(carray_named * dest, carray_named * src) nogil except -1:
    """
    Perform the necessary ZMQ copies.
    """
    cdef int rc = 0
    rc = libzmq.zmq_msg_copy(&dest.name, &src.name)
    check_zmq_rc(rc)
    return copy_array(&dest.array, &src.array)

cdef int copy_named_array_hard(carray_named * dst, carray_named * src) nogil except -1:
    """
    Hard copy a ZMQ named array message.
    """
    rc = zmq_msg_hard_copy(&dst.name, &src.name)
    return copy_array_hard(&dst.array, &src.array)

cdef int send_copy_zmq_msq(libzmq.zmq_msg_t * msg, void * socket, int flags) nogil except -1:
    """
    Send a ZMQ message by copying the message structure, and sending the copy, such that the
    original message will be retained.
    """
    
    cdef int rc = 0
    cdef libzmq.zmq_msg_t zmessage
    rc = libzmq.zmq_msg_init(&zmessage)
    check_zmq_rc(rc)
    rc = libzmq.zmq_msg_copy(&zmessage, msg)
    check_zmq_rc(rc)
    rc = libzmq.zmq_msg_send(&zmessage, socket, flags)
    check_zmq_rc(rc)
    return rc

cdef int send_array(carray_message * message, void * socket, int flags) nogil except -1:
    """
    Send a numpy array over a ZMQ socket.
    Requires an array prepared with a carray_message."""
    cdef int rc = 0
    rc = send_copy_zmq_msq(&message.info, socket, flags|libzmq.ZMQ_SNDMORE)
    rc = send_copy_zmq_msq(&message.metadata, socket, flags|libzmq.ZMQ_SNDMORE)
    rc = send_copy_zmq_msq(&message.data, socket, flags)
    return rc

cdef int send_named_array(carray_named * message, void * socket, int flags) nogil except -1:
    """
    Send a numpy array and name over a ZMQ socket.
    Requires an array prepared with a carray_named.
    """
    
    cdef int rc = 0
    rc = send_copy_zmq_msq(&message.name, socket, flags|libzmq.ZMQ_SNDMORE)
    return send_array(&message.array, socket, flags)
    
cdef int should_recv_more(void * socket) nogil except -1:
    cdef int rc, value
    cdef size_t optsize = sizeof(int)
    rc = libzmq.zmq_getsockopt(socket, libzmq.ZMQ_RCVMORE, &value, &optsize)
    check_zmq_rc(rc)
    if value != 1:
        with gil:
            raise ValueError("Protocol Error: ZMQ Socket was expecting more messages.")
    return rc
    
cdef int receive_array(carray_message * message, void * socket, int flags) nogil except -1:
    """
    Receive a known, already allocated message object. Ensures that the message will
    be received entirely.
    """
    cdef int rc
    rc = libzmq.zmq_msg_recv(&message.info, socket, flags)
    check_zmq_rc(rc)
    rc = should_recv_more(socket)
    # Recieve the metadata message
    rc = libzmq.zmq_msg_recv(&message.metadata, socket, flags)
    check_zmq_rc(rc)
    rc = should_recv_more(socket)
    # Recieve the array data.
    rc = libzmq.zmq_msg_recv(&message.data, socket, flags)
    check_zmq_rc(rc)
    return rc
    
cdef int receive_named_array(carray_named * message, void * socket, int flags) nogil except -1:
    """
    Receive a known, already allocated message object. Ensures that the message will
    be received entirely.
    """
    cdef int rc
    
    # Recieve the metadata message
    rc = libzmq.zmq_msg_recv(&message.name, socket, flags)
    check_zmq_rc(rc)
    rc = should_recv_more(socket)
    return receive_array(&message.array, socket, flags)