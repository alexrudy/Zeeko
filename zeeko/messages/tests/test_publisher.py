# -*- coding: utf-8 -*-
"""
Test the publisher class
"""

import pytest
import numpy as np
import struct
import zmq

from ..message import ArrayMessage
from ..sugar import Publisher
from .. import array as array_api
from .test_base import BaseContainerTests
from ...tests.test_helpers import ZeekoMutableMappingTests, ZeekoTestBase

class TestArrayMessage(ZeekoTestBase):
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
        assert pub.dtype == np.float
        assert pub.framecount == 0
        assert pub.md == {'shape':[10], 'dtype':'<f8', 'version': 1}
        assert isinstance(pub.metadata, str)
        assert pub.timestamp > 0
    
class TestPublisherMapping(ZeekoMutableMappingTests):
    """Test mapping characterisitics of the publisher"""
    
    cls = Publisher
    
    @pytest.fixture
    def mapping(self, name, n, shape):
        """Return the publisher, with arrays."""
        publishers = [("{0:s}{1:d}".format(name, i), np.random.randn(*shape)) for i in range(n)]
        pub = Publisher([])
        for name, array in publishers:
            pub[name] = array
        return pub

    
    @pytest.fixture
    def keys(self, name, n):
        """Return the keys"""
        return ["{0:s}{1:d}".format(name, i) for i in range(n)]
    

class BasePublisherTests(BaseContainerTests):
    """Base tests for publishers."""
    
    def test_publish(self, obj, push, pull, name):
        """Test the array publisher."""
        obj.publish(push)
        for i, key in enumerate(obj.keys()):
            recvd_name, A = array_api.recv_named_array(pull)
            assert "{0:s}{1:d}".format(name, i) == recvd_name
            np.testing.assert_allclose(A, obj[key].array)
        
    def test_unbundled(self, obj, push, pull, name):
        """Test publisher in unbundled mode."""
        obj.publish(push)
        for i, key in enumerate(obj.keys()):
            recvd_name, A = array_api.recv_named_array(pull)
            assert "{0:s}{1:d}".format(name, i) == recvd_name
            np.testing.assert_allclose(A, obj[key].array)
            assert not pull.getsockopt(zmq.RCVMORE)

class TestPublisher(BasePublisherTests):
    """Test the publisher."""
    
    cls = Publisher
    
    @pytest.fixture
    def obj(self, name, n, shape):
        """Return the publisher, with arrays."""
        publishers = [("{0:s}{1:d}".format(name, i), np.random.randn(*shape)) for i in range(n)]
        pub = Publisher([])
        pub.framecount = 2**18
        for name, array in publishers:
            pub[name] = array
        return pub

@pytest.fixture
def n():
    """Number of arrays to publish."""
    return 3

