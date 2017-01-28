# -*- coding: utf-8 -*-
"""
Test the publisher class
"""

import pytest
import numpy as np
import struct
import zmq

from ..message import ArrayMessage
from ..publisher import Publisher
from .. import array as array_api
from .test_base import BaseContainerTests

class TestArrayMessage(object):
    """Test an array message object."""
    
    cls = ArrayMessage
    
    def test_init(self):
        """PublishedArray object __init__"""
        p = self.cls("array", np.ones((10,)))
    
    def test_update(self):
        """Test update array items."""
        pub = self.cls("array", np.ones((10,)))
        with pytest.raises(ValueError):
            pub.array[:] = np.ones((20,))
        pub.array[:] = np.ones((10,))
        assert pub.array.shape == (10,)
        assert pub.name == "array"
    

class TestPublisher(BaseContainerTests):
    """Test the publisher."""
    
    cls = Publisher
    
    @pytest.fixture
    def obj(self, name, n, shape):
        """Return the publisher, with arrays."""
        publishers = [("{:s}{:d}".format(name, i), np.random.randn(*shape)) for i in range(n)]
        pub = Publisher([])
        for name, array in publishers:
            pub[name] = array
        return pub
        
    def test_publish(self, obj, push, pull, name):
        """Test the array publisher."""
        obj.publish(push)
        for i, key in enumerate(obj.keys()):
            recvd_name, A = array_api.recv_named_array(pull)
            assert "{:s}{:d}".format(name, i) == recvd_name
            np.testing.assert_allclose(A, obj[key].array)
        
    def test_unbundled(self, obj, push, pull, name):
        """Test publisher in unbundled mode."""
        obj.publish(push)
        for i, key in enumerate(obj.keys()):
            recvd_name, A = array_api.recv_named_array(pull)
            assert "{:s}{:d}".format(name, i) == recvd_name
            np.testing.assert_allclose(A, obj[key].array)
            assert not pull.getsockopt(zmq.RCVMORE)

@pytest.fixture
def n():
    """Number of arrays to publish."""
    return 3

