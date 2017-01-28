# -*- coding: utf-8 -*-

import pytest
import numpy as np
import json
import zmq
import struct

from .. import array as array_api
from ..message import ArrayMessage

@pytest.fixture(params=[0,1,6])
def framecount(request):
    """The framecount to be sent as the message."""
    return request.param

def test_array_message(array):
    """Test generating an array message."""
    metadata, _ = array_api.generate_array_message(array)
    meta = json.loads(metadata)
    assert tuple(meta['shape']) == array.shape
    assert meta['dtype'] == array.dtype.str
    
def test_array_roundtrip(req, rep, array, framecount):
    """Test that an array can go round-trip."""
    array_api.send_array(req, array, framecount=framecount)
    rep_array = array_api.recv_array(rep)
    np.testing.assert_allclose(array, rep_array)
    assert rep_array.framecount == framecount
    array_api.send_array(rep, rep_array)
    req_array = array_api.recv_array(req)
    assert req_array.framecount == framecount
    np.testing.assert_allclose(array, req_array)
    
def test_named_array_roundtrip(req, rep, array, name):
    """Test that an array can go round-trip."""
    array_api.send_named_array(req, name, array)
    name, rep_array = array_api.recv_named_array(rep)
    np.testing.assert_allclose(array, rep_array)
    array_api.send_named_array(rep, name, rep_array)
    name, req_array = array_api.recv_named_array(req)
    np.testing.assert_allclose(array, req_array)
    
def test_carray_roundtrip(req, rep, array, name):
    """Test c-array round-trip."""
    pub = ArrayMessage(name, array)
    pub.send(req)
    name, rep_array = array_api.recv_named_array(rep)
    np.testing.assert_allclose(rep_array, array)
    np.testing.assert_allclose(rep_array, pub.array)
    assert pub.name == name
    
    array_api.send_named_array(rep, name, rep_array)
    
    rec = ArrayMessage.receive(req)
    assert rec.name == name
    np.testing.assert_allclose(rec.array, array)
    np.testing.assert_allclose(rec.array, pub.array)
    
def test_packets(push, pull, shape, name):
    """Test the receiver system."""
    n = 4
    arrays = [("{:s}{:d}".format(name, i), np.random.randn(*shape)) for i in range(n)]
    
    framecount = 5
    array_api.send_array_packet(push, framecount, arrays)
    count = 0
    while pull.poll(timeout=0.01):
        name, array = array_api.recv_named_array(pull)
        assert name == arrays[count][0]
        np.testing.assert_allclose(array, arrays[count][1])
        print("Got Array: {:s}={!r}".format(name, array))
        count += 1
    assert count == len(arrays)
    