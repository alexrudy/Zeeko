# -*- coding: utf-8 -*-
"""
ZMQ support for serializing numpy arrays.

This file defines the protocol for sending a numpy array over a ZMQ socket.
"""

import numpy as np
import zmq
import json
import struct
import time
import itertools

from .. import ZEEKO_PROTOCOL_VERSION

def generate_array_message(A):
    """
    Generate an array message from an array. The generated message is a list.
    
    Parameters
    ----------
    A : array_like, bufferable
        The array to send over the ZMQ socket.
    
    """
    md = dict(
        dtype = A.dtype.str,
        shape = A.shape,
        version = ZEEKO_PROTOCOL_VERSION,
    )
    return [json.dumps(md), A]
    
def generate_info_packet(framecount, timestamp=None):
    """Generate an info packet."""
    if timestamp is None:
        timestamp = time.time()
    return struct.pack("Ld", framecount, timestamp)

def unpack_info_packet(packet):
    """Unpack an informational packet."""
    return struct.unpack("Ld", packet)

def send_array(socket, A, framecount=0, flags=0, copy=True, track=False):
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
    metadata, _ = generate_array_message(A)
    socket.send(generate_info_packet(framecount), flags|zmq.SNDMORE)
    socket.send(metadata, flags|zmq.SNDMORE)
    return socket.send(A, flags, copy=copy, track=track)
    
def send_named_array(socket, name, A, framecount=0, flags=0, copy=True, track=False):
    """Send an array in the named-array format.
    
    Parameters
    ----------
    socket : zmq Socket
        The ZMQ socket used for sending the array.
    
    A : array_like, bufferable
        The array to send over the ZMQ socket.
    
    name : string
        The name of the array to send.
    
    flags : int
        ZMQ Send flags to be used with the socket.
    
    copy : bool, optional
        Copy on send?
    
    track : bool, optional
        Track the message
    
    """
    socket.send(name, flags|zmq.SNDMORE)
    return send_array(socket, A, framecount=framecount, flags=flags, copy=copy, track=track)

def recv_array(socket, flags=0, copy=True, track=False):
    """Receive a numpy array.
    
    Parameters
    ----------
    socket : zmq Socket
        The ZMQ socket used for sending the array.
    
    flags : int
        ZMQ Send flags to be used with the socket.
    
    copy : bool, optional
        Copy on send?
    
    track : bool, optional
        Track the message
    
    Returns
    -------
    A : array_like
        The received array.
    
    """
    fc, timestamp = unpack_info_packet(socket.recv(flags=flags))
    md = socket.recv_json(flags=flags)
    msg = socket.recv(flags=flags, copy=copy, track=track)
    try:
        buf = buffer(msg)
    except NameError:
        buf = memoryview(msg)
    A = np.frombuffer(buf, dtype=md['dtype'])
    return A.reshape(md['shape'])

def recv_named_array(socket, flags=0, copy=True, track=False):
    """Receive an array in the named-array format.
    
    Parameters
    ----------
    socket : zmq Socket
        The ZMQ socket used for sending the array.
    
    flags : int
        ZMQ Send flags to be used with the socket.
    
    copy : bool, optional
        Copy on send?
    
    track : bool, optional
        Track the message
    
    Returns
    -------
    name : string
        The name of the array, a string.
    
    A : array_like
        The received array.
    
    
    """
    name = socket.recv(flags=flags, copy=copy, track=track)
    A = recv_array(socket, flags=flags, copy=copy, track=track)
    return (name, A)
        
def send_array_packet(socket, framecount, arrays, flags=0, copy=True, track=False):
    """Send a packet of arrays."""
    for name, array in arrays[:-1]:
        send_named_array(socket, name, array, flags=flags|zmq.SNDMORE, copy=copy, track=track)
    name, array = arrays[-1]
    return send_named_array(socket, name, array, flags=flags, copy=copy, track=track)