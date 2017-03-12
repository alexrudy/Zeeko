# -*- coding: utf-8 -*-

"""
Test the receiver class
"""

import pytest
import numpy as np
import time
import zmq
import itertools

from ..message import ArrayMessage
from .. import Receiver
from .. import array as array_api
from ...utils.condition import Event

import struct

from zeeko.conftest import assert_canrecv
from ...tests.test_helpers import ZeekoMappingTests, ZeekoTestBase, OrderedDict

@pytest.fixture
def n():
    """Number of arrays to publish."""
    return 3
    

construct_name = "{0:s}{1:d}".format

class ReceiverTestBase(ZeekoTestBase):
    """Tests for the basic recorder object."""
    
    cls = Receiver
    
    _framecount = itertools.count(2**18)
    
    @pytest.fixture
    def framecount(self):
        """Reutrn the framecount."""
        return next(self._framecount)
    
    @pytest.fixture
    def receiver(self):
        """The receiver object"""
        return self.cls()
    
    @pytest.fixture
    def arrays(self, shape, name, n):
        """Arrays"""
        return OrderedDict((construct_name(name, i), np.random.randn(*shape)) for i in range(n))
        
    @pytest.fixture
    def framecount(self):
        """A fixture for the framecount."""
        return 5
        
    def make_modified_arrays(self, arrays):
        """Return modified arrays, where values have been multiplied by two."""
        return OrderedDict((key, data * 2.0) for key, data in arrays.items())
        
    def send_arrays(self, socket, arrays, framecount):
        """Send arrays."""
        assert socket.poll(timeout=100, flags=zmq.POLLOUT)
        array_api.send_array_packet(socket, framecount, list(arrays.items()), flags=zmq.NOBLOCK)
        
    def recv_arrays(self, receiver, socket, arrays, flags=zmq.NOBLOCK):
        """Wrapper around receiving arrays."""
        assert_canrecv(socket)
        receiver.receive(socket, flags=flags)
        for key in arrays:
            assert receiver.event(key).is_set()
        assert len(receiver) == len(arrays)
    
    def send_unbundled_arrays(self, socket, arrays):
        """Send arrays as individual messages."""
        for name, array in arrays.items():
            assert socket.poll(timeout=100, flags=zmq.POLLOUT)
            array_api.send_named_array(socket, name, array, flags=zmq.NOBLOCK)
        
    def recv_unbundled_arrays(self, receiver, socket, arrays, flags=zmq.NOBLOCK):
        """Receive unbundled arrays"""
        count = 0
        while socket.poll(timeout=100, flags=zmq.POLLIN):
            assert_canrecv(socket)
            receiver.receive(socket, flags=flags)
            count += 1
        for key in arrays:
            assert receiver.event(key).is_set()
        assert count == len(arrays)
    
    def assert_receiver_arrays_allclose(self, receiver, arrays):
        """Assert receiver and arrays are all close."""
        assert len(receiver) == len(arrays)
        assert set(receiver.keys()) == set(arrays.keys())
        for i, key in enumerate(receiver):
            data = receiver[key].array
            np.testing.assert_allclose(data, arrays[key])
    
class ReceiverTests(ReceiverTestBase):
    """Test methods for the receiver"""
    
    def test_receiver_attrs(self, receiver):
        """Test receiver attributes after init"""
        assert receiver.framecount == 0
        last_message = receiver.last_message
        if isinstance(last_message, float):
            assert last_message == 0.0
        else:
            assert time.mktime(last_message.timetuple()) == 0.0
        evt = receiver.event("my_key")
        assert isinstance(evt, Event)
    
    def test_receiver_packet(self, receiver, push, pull, arrays, framecount):
        """Test receive a single message."""
        self.send_arrays(push, arrays, framecount)
        for key in arrays:
            assert not receiver.event(key).is_set()
        self.recv_arrays(receiver, pull, arrays)
        self.assert_receiver_arrays_allclose(receiver, arrays)
        assert receiver.framecount == framecount
        
    def test_unbundled(self, receiver, push, pull, arrays):
        """Test an unbundled send."""
        self.send_unbundled_arrays(push, arrays)
        for key in arrays:
            assert not receiver.event(key).is_set()
        self.recv_unbundled_arrays(receiver, pull, arrays)
        self.assert_receiver_arrays_allclose(receiver, arrays)
        
    def test_multiple(self, receiver, push, pull, arrays, framecount):
        """Test multiple consecutive packets."""
        self.send_arrays(push, arrays, framecount)
        arrays_2 = self.make_modified_arrays(arrays)
        self.send_arrays(push, arrays_2, framecount + 1)
        for key in arrays:
            assert not receiver.event(key).is_set()
        self.recv_arrays(receiver, pull, arrays)
        self.assert_receiver_arrays_allclose(receiver, arrays)
        assert receiver.framecount == framecount
        self.recv_arrays(receiver, pull, arrays)
        self.assert_receiver_arrays_allclose(receiver, arrays_2)
        assert receiver.framecount == framecount + 1
    
    def test_retain_multiple(self, receiver, push, pull, arrays, framecount):
        """Test retain against multiple receiver array bodies."""
        self.send_arrays(push, arrays, framecount)
        arrays_2 = self.make_modified_arrays(arrays)
        self.send_arrays(push, arrays_2, framecount + 1)
        for key in arrays:
            assert not receiver.event(key).is_set()
        self.recv_arrays(receiver, pull, arrays)
        self.assert_receiver_arrays_allclose(receiver, arrays)
        akey = set(receiver.keys()).pop()
        reference = receiver[akey]
        self.recv_arrays(receiver, pull, arrays)
        self.assert_receiver_arrays_allclose(receiver, arrays_2)
        reference2 = receiver[akey]
        assert reference.name == reference2.name
        assert not np.allclose(reference.array, reference2.array)
        
    def test_repr(self, receiver, push, pull, arrays, framecount):
        """Test representation."""
        assert self.cls.__name__ in repr(receiver)
        self.send_arrays(push, arrays, framecount)
        self.recv_arrays(receiver, pull, arrays)
        assert self.cls.__name__ in repr(receiver)
    
class TestReceiver(ReceiverTests):
    """Concrete implementation of tests for receivers."""
    pass
    
class TestReceiverMapping(ZeekoMappingTests, ReceiverTestBase):
    """Test client mappings."""
    
    cls = Receiver
    
    @pytest.fixture
    def mapping(self, pull, push, arrays, framecount):
        """A client, set up for use as a mapping."""
        receiver = self.cls(pull, zmq.POLLIN)
        self.send_arrays(push, arrays, framecount)
        self.recv_arrays(receiver, pull, arrays)
        yield receiver
        
    @pytest.fixture
    def keys(self, arrays):
        """Return keys which should be availalbe."""
        return arrays.keys()
