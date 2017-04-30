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

from ..utils.sandwich import sandwich_unicode, unsandwich_unicode

class zmq_ndarray(np.ndarray):
    pass

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
    return [sandwich_unicode(json.dumps(md)), A]
    
def generate_info_packet(framecount, timestamp=None):
    """Generate an info packet."""
    if timestamp is None:
        timestamp = time.time()
    return struct.pack("Ld", framecount, timestamp)

def unpack_info_packet(packet):
    """Unpack an informational packet."""
    return struct.unpack("Ld", packet)

def send_array(socket, A, framecount=None, flags=0, copy=True, track=False):
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
    if framecount is None:
        framecount = getattr(A, 'framecount', 0)
    metadata, _ = generate_array_message(A)
    socket.send(generate_info_packet(framecount), flags|zmq.SNDMORE)
    socket.send(metadata, flags|zmq.SNDMORE)
    return socket.send(A, flags, copy=copy, track=track)
    
def send_named_array(socket, name, A, framecount=None, flags=0, copy=True, track=False):
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
    socket.send(sandwich_unicode(name), flags|zmq.SNDMORE)
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
    except NameError: #pragma: py3
        buf = memoryview(msg)
    A = np.frombuffer(buf, dtype=md['dtype'])
    A = A.reshape(md['shape']).view(zmq_ndarray)
    A.framecount = fc
    A.timestamp = timestamp
    return A

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
    name = unsandwich_unicode(socket.recv(flags=flags, copy=copy, track=track))
    A = recv_array(socket, flags=flags, copy=copy, track=track)
    return (name, A)
    

def send_array_packet_header(socket, topic, narrays, framecount=0, timestamp=None, flags=0, copy=True):
    """Send an array packet header which identifies the contents of the coming array messages."""
    bflags = flags|zmq.SNDMORE
    if topic is None:
        topic = "{:d} Arrays".format(len(arrays))
    if timestamp is None:
        timestamp = time.time()
    
    m1 = socket.send(sandwich_unicode(topic), flags=bflags, copy=copy, track=False)
    m2 = socket.send(struct.pack("L", framecount), flags=bflags, copy=copy, track=False)
    m3 = socket.send(struct.pack("i", narrays), flags=bflags, copy=copy, track=False)
    m4 = socket.send(struct.pack("d", timestamp), flags=flags, copy=copy, track=False)
    return [m1, m2, m3, m4]

def send_array_packet(socket, framecount, arrays, flags=0, copy=True, track=False, header=False, timestamp=None, bundle=True, topic=None):
    """Send a packet of arrays."""
    bflags = flags|zmq.SNDMORE if bundle else flags
    ms = []
    if header:
        ms.extend(send_array_packet_header(socket, topic, len(arrays), framecount=framecount, timestamp=timestamp, flags=flags, copy=copy, track=track))
    for name, array in arrays[:-1]:
        ms.append(send_named_array(socket, name, array, framecount=framecount, flags=bflags, copy=copy, track=track))
    name, array = arrays[-1]
    ms.append(send_named_array(socket, name, array, framecount=framecount, flags=flags, copy=copy, track=track))
    return ms