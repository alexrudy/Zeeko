# -*- coding: utf-8 -*-

import pytest
import time
import functools
import zmq
from ..client import Client
from zeeko.conftest import assert_canrecv

@pytest.fixture
def push(context, address):
    """Push socket."""
    socket = context.socket(zmq.PUSH)
    socket.bind(address)
    yield socket
    socket.close(linger=0)

@pytest.fixture
def pub(context, address):
    """Push socket."""
    socket = context.socket(zmq.PUB)
    socket.bind(address)
    yield socket
    socket.close(linger=0)

def test_client_attributes(context, address):
    """Test client attributes defaults."""
    c = Client(context, address)
    assert c.counter == 0
    assert c.delay == 0
    assert c.maxlag == 10.0
    c.maxlag = 20
    assert c.maxlag == 20.0
    
def test_client_run(context, address, Publisher, push):
    """Test a client."""    
    c = Client(context, address, zmq.PULL)
    c.start()
    try:
        time.sleep(0.01)
        Publisher.publish(push)
        Publisher.publish(push)
        Publisher.publish(push)
        time.sleep(0.1)
    finally:
        c.stop()
    assert c.counter == 3 * len(Publisher)
    assert len(c) == 3

def test_client_snail_death(context, address, Publisher, pub):
    """Test client snail death."""
    c = Client(context, address, zmq.SUB)
    c.maxlag = 0.0
    c.start()
    time.sleep(0.01)
    try:
        # First message gets recieved
        Publisher.publish(pub, zmq.NOBLOCK)
        # Nth one should get dropped, b/c other side disconnects.
        Publisher.publish(pub, zmq.NOBLOCK)
        Publisher.publish(pub, zmq.NOBLOCK)
        time.sleep(0.01)
        assert c.state == 'PAUSE'
        assert c.snail_deaths == 1
    finally:
        c.stop()
