# -*- coding: utf-8 -*-
"""
This is a pure-python implementation of the Chunk API for consistency.
"""

import numpy as np
import zmq
from zmq.utils import jsonapi

from .. import ZEEKO_PROTOCOL_VERSION

class PyChunk(object):
    """A pure python chunk."""
    def __init__(self, name, array, mask):
        super(PyChunk, self).__init__()
        array = np.asarray(array)
        mask = np.asarray(mask)
        if array.shape[0] != mask.shape[0]:
            raise ValueError("Shape mismatch between data and mask.")
        self.array = array
        self.mask = mask
        self.name = str(name)
        
    @property
    def chunksize(self):
        """Size of this chunk."""
        return self.mask.shape[0]
        
    @property
    def shape(self):
        """Shape"""
        return self.array.shape[1:]
        
    @property
    def dtype(self):
        """Datatype"""
        return self.array.dtype
        
    @property
    def lastindex(self):
        """The last filled-in index."""
        return np.argmax(self.mask) + 1
        
    @property
    def md(self):
        """The metadata dictionary for this chunk."""
        md = dict(
            dtype = self.array.dtype.str,
            shape = self.shape,
            version = ZEEKO_PROTOCOL_VERSION,
        )
        return md
        
    @property
    def metadata(self):
        """The JSON-encoded metadata for this chunk"""
        return jsonapi.dumps(self.md)
    
    def append(self, data):
        """Append data to the chunk"""
        index = np.argmax(self.mask) + 1
        self.mask[index] = index
        self.array[...,index] = data
    
    def send(self, socket, flags=0):
        """Send this chunk over a ZMQ socket."""
        socket.send(self.name, flags=flags|zmq.SNDMORE)
        socket.send_json(self.md, flags=flags|zmq.SNDMORE)
        socket.send(self.array, flags=flags|zmq.SNDMORE)
        socket.send(self.mask, flags=flags)
    
    @classmethod
    def recv(cls, socket, flags=0):
        """Recieve a chunk from a socket."""
        name = socket.recv(flags=flags)
        md = socket.recv_json(flags=flags)
        msg = socket.recv(flags=flags)
        try:
            buf = buffer(msg)
        except NameError: #pragma: py3
            buf = memoryview(msg)
        data = np.frombuffer(buf, dtype=md['dtype'])
        data.shape = tuple([-1] + md['shape'])
        
        msg = socket.recv(flags=flags)
        try:
            buf = buffer(msg)
        except NameError: #pragma: py3
            buf = memoryview(msg)
        mask = np.frombuffer(buf, dtype=np.int32)
        
        return cls(name, data, mask)
    