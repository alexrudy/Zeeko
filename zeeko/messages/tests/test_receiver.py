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
    
def test_receiver_multiple(push, pull, shape, name, n):
    """Test receive multiple messages."""
    arrays = [("{:s}{:d}".format(name, i), np.random.randn(*shape)) for i in range(n)]
    arrays2 = [("{:s}{:d}".format(name, i), np.random.randn(*shape)) for i in range(n)]
    
    framecount = 5
    array_api.send_array_packet(push, framecount, arrays)
    framecount = 6
    array_api.send_array_packet(push, framecount, arrays2)
    
    rcv = Receiver()
    rcv.receive(pull)
    assert len(rcv) == n
    for i in range(len(rcv)):
        np.testing.assert_allclose(rcv["{:s}{:d}".format(name, i)].array, arrays[i][1])
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
    rcv.receive(pull)
    assert len(rcv) == n
    for i in range(len(rcv)):
        np.testing.assert_allclose(rcv["{:s}{:d}".format(name, i)].array, arrays[i][1])
    refd_array = rcv[1].array
    rcv.receive(pull)
    for i in range(len(rcv)):
        np.testing.assert_allclose(rcv["{:s}{:d}".format(name, i)].array, arrays2[i][1])
    refd_array2 = rcv[1].array
    assert (refd_array != refd_array2).any()