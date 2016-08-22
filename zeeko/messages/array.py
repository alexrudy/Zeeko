# -*- coding: utf-8 -*-
"""
ZMQ support for serializing numpy arrays.

This file defines the protocol for sending a numpy array over a ZMQ socket.
"""

import numpy as np
import zmq
import json

def generate_array_message(A):
    """docstring for generate_message"""
    md = dict(
        dtype = A.dtype.str,
        shape = A.shape,
    )
    return [json.dumps(md), A]

def send_array(socket, A, flags=0, copy=True, track=False):
    """Send a numpy array with metadata.
    
    Parameters
    ----------
    socket : zmq Socket
        The ZMQ socket used for sending the array.
    
    A : array_like, bufferable
        The array to send over the ZMQ socket.
    
    flags : int
        ZMQ Send flags to be used with the socket.
    
    copy : bool, optional
        Copy on send?
    
    track : bool, optional
        Track the message
    
    """
    metadata, A = generate_array_message(A)
    socket.send(metadata, flags|zmq.SNDMORE)
    return socket.send(A, flags, copy=copy, track=track)

def recv_array(socket, flags=0, copy=True, track=False):
    """Recieve a numpy array."""
    md = socket.recv_json(flags=flags)
    msg = socket.recv(flags=flags, copy=copy, track=track)
    buf = buffer(msg)
    A = np.frombuffer(buf, dtype=md['dtype'])
    return A.reshape(md['shape'])