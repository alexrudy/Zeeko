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

@pytest.fixture
def outbound_address():
    """Return the outbound address."""
    return "inproc://test-outbound"

@pytest.fixture
def server(context, address, arrays):
    """Make a server object."""
    s = Server(context, address)
    s.frequency = 100
    for k, v in arrays:
        s[k] = v
    s.start()
    yield s
    s.stop()

def test_throttle_attributes(context, address, outbound_address):
    """Test client attributes defaults."""
    t = Throttle(context, address, outbound_address)
    assert t.counter == 0
    assert t.wait_time == 0.0
    assert t.counter == 0
    assert t.delay == 0
    assert t.maxlag == 10.0
    t.frequency = 10.0
    assert t.frequency == 10.0
    t.maxlag = 20
    assert t.maxlag == 20.0
    
def test_throttle_noop(context, address, outbound_address, server, sub):
    """Test full throttle"""
    t = Throttle(context, address, outbound_address)
    t.frequency = 10.0
    t.pause()
    try:
        t.start()
    finally:
        t.stop()

def test_throttle(context, address, outbound_address, server, sub):
    """Test full throttle"""
    t = Throttle(context, address, outbound_address)
    t.frequency = 10.0
    t.pause()
    try:
        sub.connect(outbound_address)
        sub.subscribe("")
        t.start()
        time.sleep((1.0/t.frequency) + 0.1)
        assert_canrecv(sub)
        sub.recv_multipart()
    finally:
        t.stop()
    

