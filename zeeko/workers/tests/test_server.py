# -*- coding: utf-8 -*-

import pytest
import time
import functools
import zmq
import numpy as np
from ..server import Server
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

def test_server_attributes(context, address):
    """Test client attributes defaults."""
    s = Server(context, address)
    assert s.counter == 0
    assert s.wait_time == 0.0
    
def test_server_run(context, address, Receiver, sub, arrays):
    """Test that the server runs properly."""
    s = Server(context, address, zmq.PUB)
    s.frequency = 100
    for k, v in arrays:
        s[k] = v
    s.pause()
    sub.connect(address)
    sub.subscribe("")
    s.start()
    c = 0
    try:
        while sub.poll(100) and c < 3 * len(arrays):
            Receiver.receive(sub, zmq.NOBLOCK)
            c += 1
    finally:
        s.stop()
    assert s.counter >= 3
    assert len(s) == 3
    
@pytest.mark.skip
def test_server_rate(context, address, Receiver, sub, arrays):
    """Test that the server trends to the right rate properly."""
    s = Server(context, address, zmq.PUB)
    s.frequency = 100000
    for k, v in arrays:
        s[k] = v
    s.pause()
    sub.connect(address)
    sub.subscribe("")
    count = 0
    s.start()
    try:
        time.sleep(0.1)
        start_rate = (s.counter - count) / 0.1
        assert_canrecv(sub)
        Receiver.receive(sub, zmq.NOBLOCK)
        assert_canrecv(sub)
        Receiver.receive(sub, zmq.NOBLOCK)
        assert_canrecv(sub)
        Receiver.receive(sub, zmq.NOBLOCK)
        time.sleep(0.1)
        count = s.counter
        time.sleep(0.1)
        next_rate = (s.counter - count) / 0.1
        sub.unsubscribe("")
    finally:
        s.stop()
    assert abs(start_rate - s.frequency) >= abs(next_rate - s.frequency), "Rate is not converging."
