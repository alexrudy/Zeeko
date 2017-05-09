# -*- coding: utf-8 -*-
"""
Test the publisher class
"""

import pytest
import numpy as np
import struct
import zmq
import time
import datetime as dt

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
    
    @pytest.fixture(params=[2**18, 0, 50])
    def framecount(self, request):
        """Fixture for the framecount."""
        return request.param
    
    def get_last_message(self, receiver):
        """Get the value of the last message."""
        last_message = receiver.last_message
        assert isinstance(last_message, (float, dt.datetime))
        if isinstance(last_message, dt.datetime):
            last_message = time.mktime(last_message.timetuple())
        assert isinstance(last_message, float)
        return last_message
    
    def test_publisher_attrs(self, obj, framecount):
        """Test attributes"""
        assert obj.framecount == framecount
        last_message = self.get_last_message(obj)
        now = dt.datetime.now()
        last_timestamp = dt.datetime.fromtimestamp(last_message)
        assert now - dt.timedelta(seconds=10) < last_timestamp
        assert last_timestamp < now + dt.timedelta(seconds=10)
    
    def test_publish(self, obj, push, pull, name, framecount):
        """Test the array publisher."""
        obj.publish(push)
        for i, key in enumerate(obj.keys()):
            recvd_name, A = array_api.recv_named_array(pull)
            assert "{0:s}{1:d}".format(name, i) == recvd_name
            np.testing.assert_allclose(A, obj[key].array)
            assert A.framecount == framecount + 1
            
        
    def test_unbundled(self, obj, push, pull, name, framecount):
        """Test publisher in unbundled mode."""
        obj.publish(push)
        for i, key in enumerate(obj.keys()):
            recvd_name, A = array_api.recv_named_array(pull)
            assert "{0:s}{1:d}".format(name, i) == recvd_name
            np.testing.assert_allclose(A, obj[key].array)
            assert not pull.getsockopt(zmq.RCVMORE)
            assert A.framecount == framecount + 1

class TestPublisher(BasePublisherTests):
    """Test the publisher."""
    
    cls = Publisher
    
    @pytest.fixture(params=[True, False], ids=['hardcopy', 'softcopy'])
    def hardcopy(self, request):
        """Whether to hardcopy or not."""
        return request.param
    
    @pytest.fixture
    def obj(self, name, n, shape, hardcopy, framecount):
        """Return the publisher, with arrays."""
        publishers = [("{0:s}{1:d}".format(name, i), np.random.randn(*shape)) for i in range(n)]
        pub = Publisher([])
        if hardcopy:
            pub.enable_hardcopy()
        pub.framecount = framecount
        for name, array in publishers:
            pub[name] = array
        return pub

@pytest.fixture
def n():
    """Number of arrays to publish."""
    return 3

