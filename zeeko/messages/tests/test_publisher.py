# -*- coding: utf-8 -*-
"""
Test the publisher class
"""

import pytest
import numpy as np
import struct
import zmq

from ..publisher import PublishedArray, Publisher
from .. import array as array_api

@pytest.fixture
def n():
    """Number of arrays to publish."""
    return 3

def test_publisher_single_init():
    """PublishedArray object __init__"""
    p = PublishedArray("array", np.ones((10,)))
    
def test_publisher_single_update():
    """Test update array items."""
    pub = PublishedArray("array", np.ones((10,)))
    
    with pytest.raises(ValueError):
        pub.array = np.ones((20,))
    pub.array = np.ones((10,))
    assert pub.array.shape == (10,)
    
    assert pub.name == "array"

def test_publisher(push, pull, shape, name, n):
    """Test the array publisher."""
    publishers = [("{:s}{:d}".format(name, i), np.random.randn(*shape)) for i in range(n)]
    pub = Publisher([])
    for name_, array_ in publishers:
        pub[name_] = array_
    pub.publish(push)
    
    for i in range(n):
        recvd_name, A = array_api.recv_named_array(pull)
        assert "{:s}{:d}".format(name, i) == recvd_name
        np.testing.assert_allclose(A, publishers[i][1])
    
def test_publisher_unbundle(push, pull, shape, name, n):
    """Test publisher in unbundled mode."""
    publishers = [("{:s}{:d}".format(name, i), np.random.randn(*shape)) for i in range(n)]
    pub = Publisher([])
    for name_, array_ in publishers:
        pub[name_] = array_
    pub.publish(push)
    
    for i in range(n):
        recvd_name, A = array_api.recv_named_array(pull)
        assert "{:s}{:d}".format(name, i) == recvd_name
        np.testing.assert_allclose(A, publishers[i][1])
        assert not pull.getsockopt(zmq.RCVMORE)
