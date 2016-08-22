# -*- coding: utf-8 -*-

import pytest
import numpy as np
import json

from ..array import send_array, recv_array, generate_array_message
from ..publisher import PublishedArray
from ..receiver import ReceivedArray

def test_array_message(array):
    """Test generating an array message."""
    metadata, _ = generate_array_message(array)
    meta = json.loads(metadata)
    assert tuple(meta['shape']) == array.shape
    assert meta['dtype'] == array.dtype.str
    
def test_array_roundtrip(req, rep, array):
    """Test that an array can go round-trip."""
    send_array(req, array)
    rep_array = recv_array(rep)
    np.testing.assert_allclose(array, rep_array)
    send_array(rep, rep_array)
    req_array = recv_array(req)
    np.testing.assert_allclose(array, req_array)
    
def test_carray_roundtrip(req, rep, array, name):
    """Test c-array round-trip."""
    pub = PublishedArray(name, array)
    pub.send(req)
    rec = ReceivedArray.receive(rep)
    np.testing.assert_allclose(rec.array, array)
    np.testing.assert_allclose(rec.array, pub.array)
    assert rec.name == name
    assert rec.name == pub.name