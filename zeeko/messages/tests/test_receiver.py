# -*- coding: utf-8 -*-

"""
Test the receiver class
"""

import pytest
import numpy as np
import time
import zmq

from ..receiver import ReceivedArray, Receiver
from .. import array as array_api
import struct
from zeeko.conftest import assert_canrecv


@pytest.fixture
def n():
    """Number of arrays to publish."""
    return 3

def test_receiver_array_init():
    """Can't raw init."""
    with pytest.raises(TypeError):
        ReceivedArray()
    
    
def test_receiver_array(req, rep, array, name):
    """Test update array items."""
    array_api.send_named_array(req, name, array)
    
    reply = ReceivedArray.receive(rep)
    np.testing.assert_allclose(reply.array, array)
    assert reply.name == name
    

def test_receiver(push, pull, shape, name, n):
    """Test the receiver system."""
    arrays = [("{:s}{:d}".format(name, i), np.random.randn(*shape)) for i in range(n)]
    
    framecount = 5
    array_api.send_array_packet(push, framecount, arrays)
    
    rcv = Receiver()
    rcv.receive(pull)
    assert len(rcv) == n
    for i in range(len(rcv)):
        np.testing.assert_allclose(rcv["{:s}{:d}".format(name, i)].array, arrays[i][1])
        

def test_receiver_unbundled(push, pull, shape, name, n):
    """Test the receiver system."""
    arrays = [("{:s}{:d}".format(name, i), np.random.randn(*shape)) for i in range(n)]
    
    for _name, array in arrays:
        array_api.send_named_array(push, _name, array)
    
    rcv = Receiver()
    rcv.bundled = False
    for i in range(n):
        assert_canrecv(pull)
        rcv.receive(pull)
    assert len(rcv) == n
    print(rcv.keys())
    for i in range(len(rcv)):
        key = "{:s}{:d}".format(name, i)
        source = arrays[i][1]
        target = rcv[key].array
        np.testing.assert_allclose(target, source)
    
def test_receiver_multiple(push, pull, shape, name, n):
    """Test receive multiple messages."""
    arrays = [("{:s}{:d}".format(name, i), np.random.randn(*shape)) for i in range(n)]
    arrays2 = [("{:s}{:d}".format(name, i), np.random.randn(*shape)) for i in range(n)]
    
    framecount = 5
    array_api.send_array_packet(push, framecount, arrays)
    framecount = 6
    array_api.send_array_packet(push, framecount, arrays2)
    
    rcv = Receiver()
    assert_canrecv(pull)
    rcv.receive(pull)
    assert len(rcv) == n
    for i in range(len(rcv)):
        np.testing.assert_allclose(rcv["{:s}{:d}".format(name, i)].array, arrays[i][1])
    assert_canrecv(pull)
    rcv.receive(pull)
    for i in range(len(rcv)):
        np.testing.assert_allclose(rcv["{:s}{:d}".format(name, i)].array, arrays2[i][1])
    
def test_retain_multiple(push, pull, shape, name, n):
    """Test retaining multiple references to a given array."""
    arrays = [("{:s}{:d}".format(name, i), np.random.randn(*shape)) for i in range(n)]
    arrays2 = [("{:s}{:d}".format(name, i), np.random.randn(*shape)) for i in range(n)]
    
    framecount = 5
    array_api.send_array_packet(push, framecount, arrays)
    framecount = 6
    array_api.send_array_packet(push, framecount, arrays2)
    
    rcv = Receiver()
    assert_canrecv(pull)
    rcv.receive(pull)
    assert len(rcv) == n
    for i in range(len(rcv)):
        np.testing.assert_allclose(rcv["{:s}{:d}".format(name, i)].array, arrays[i][1])
    refd_array = rcv[1].array
    assert_canrecv(pull)
    rcv.receive(pull)
    for i in range(len(rcv)):
        np.testing.assert_allclose(rcv["{:s}{:d}".format(name, i)].array, arrays2[i][1])
    refd_array2 = rcv[1].array
    assert (refd_array != refd_array2).any()