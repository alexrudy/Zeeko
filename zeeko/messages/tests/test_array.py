# -*- coding: utf-8 -*-

import pytest
import numpy as np
import json
import zmq
import struct

from .. import array as array_api
from ..publisher import PublishedArray
from ..receiver import ReceivedArray

def test_array_message(array):
    """Test generating an array message."""
    metadata, _ = array_api.generate_array_message(array)
    meta = json.loads(metadata)
    assert tuple(meta['shape']) == array.shape
    assert meta['dtype'] == array.dtype.str
    
def test_array_roundtrip(req, rep, array):
    """Test that an array can go round-trip."""
    array_api.send_array(req, array)
    rep_array = array_api.recv_array(rep)
    np.testing.assert_allclose(array, rep_array)
    array_api.send_array(rep, rep_array)
    req_array = array_api.recv_array(req)
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
    pub = PublishedArray(name, array)
    pub.send(req)
    name, rep_array = array_api.recv_named_array(rep)
    np.testing.assert_allclose(rep_array, array)
    np.testing.assert_allclose(rep_array, pub.array)
    assert pub.name == name
    
    array_api.send_named_array(rep, name, rep_array)
    
    rec = ReceivedArray.receive(req)
    assert rec.name == name
    np.testing.assert_allclose(rec.array, array)
    np.testing.assert_allclose(rec.array, pub.array)
    
def test_packets(push, pull, shape, name):
    """Test the receiver system."""
    n = 4
    arrays = [("{:s}{:d}".format(name, i), np.random.randn(*shape)) for i in range(n)]
    
    framecount = 5
    array_api.send_array_packet(push, framecount, arrays)
    print("Sent Header: NULL fc={:d} nm={:d} time=?".format(framecount, len(arrays)))
    topic = pull.recv()
    fc = struct.unpack("I",pull.recv())[0]
    nm = struct.unpack("i",pull.recv())[0]
    tm = struct.unpack("d",pull.recv())[0]
    print("Got Header: fc={:d} nm={:d} time={:f}".format(fc, nm, tm))
    assert fc == framecount
    assert nm == len(arrays)
    count = 0
    for i in range(nm):
        name, array = array_api.recv_named_array(pull)
        assert name == arrays[i][0]
        np.testing.assert_allclose(array, arrays[i][1])
        print("Got Array: {:s}={!r}".format(name, array))
        count += 1
    assert count == len(arrays)
    