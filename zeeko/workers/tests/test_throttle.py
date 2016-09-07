# -*- coding: utf-8 -*-

import pytest
import time
import functools
import zmq
import numpy as np
from ..server import Server
from ..throttle import Throttle
from zeeko.conftest import assert_canrecv

@pytest.fixture
def pull(context):
    """Pull socket."""
    socket = context.socket(zmq.PULL)
    yield socket
    socket.close(linger=0)
    
@pytest.fixture
def sub(context):
    """Pull socket."""
    socket = context.socket(zmq.SUB)
    yield socket
    socket.close(linger=0)
    
    
@pytest.fixture
def arrays(name, n, shape):
    """The arrays to publish."""
    return [("{:s}{:d}".format(name, i), np.random.randn(*shape)) for i in range(n)]

def test_throttle_attributes(context, address):
    """Test client attributes defaults."""
    t = Throttle(context, address, address + "-outbound")
    assert t.counter == 0
    assert t.wait_time == 0.0
    assert t.counter == 0
    assert t.delay == 0
    assert t.maxlag == 10.0
    t.maxlag = 20
    assert t.maxlag == 20.0
    


