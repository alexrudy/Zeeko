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
    
@pytest.fixture
def pull(context, address):
    """Pull socket."""
    socket = context.socket(zmq.PUSH)
    socket.connect(address)
    yield socket
    socket.close(linger=0)
    
@pytest.fixture
def client(address, context):
    """docstring for client"""
    return Client.at_address(address, context, kind=zmq.PULL)

def test_client_attributes(address, context):
    """Test client attributes defaults."""
    c = Client.at_address(address, context)
    #TODO include client addresses.
    
def test_client_add_to_loop(ioloop, client):
    """Test client add to a loop."""
    ioloop._add_socketinfo(client)
    ioloop.start()
    try:
        time.sleep(0.01)
    finally:
        ioloop.stop()
    
def test_client_run(ioloop, client, Publisher, push):
    """Test a client."""    
    ioloop._add_socketinfo(client)
    ioloop.start()
    try:
        time.sleep(0.01)
        Publisher.publish(push)
        Publisher.publish(push)
        Publisher.publish(push)
        time.sleep(0.1)
    finally:
        ioloop.stop()
    assert client.receiver.framecount != 0
    print(client.receiver.last_message)
    assert len(client.receiver) == 3
