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
def pull(context, address, push):
    """Pull socket."""
    socket = context.socket(zmq.PUSH)
    socket.connect(address)
    yield socket
    socket.close(linger=0)
    
@pytest.fixture
def client(address, context, push):
    """docstring for client"""
    return Client.at_address(address, context, kind=zmq.PULL)

def test_client_attributes(address, context):
    """Test client attributes defaults."""
    c = Client.at_address(address, context)
    #TODO include client addresses.
    
def test_client_no_loop(ioloop, client, Publisher, push):
    """Test client without using the loop."""
    time.sleep(0.01)
    Publisher.publish(push)
    client.receiver.receive(client.socket)
    Publisher.publish(push)
    client.receiver.receive(client.socket)
    Publisher.publish(push)
    client.receiver.receive(client.socket)
    time.sleep(0.1)
    print(client.receiver.last_message)
    assert client.receiver.framecount != 0
    assert len(client.receiver) == 3
    client._close()
    
def test_client_callback(ioloop, client, Publisher, push):
    """Test client without using the loop."""
    time.sleep(0.01)
    Publisher.publish(push)
    client(client.socket, client.socket.poll(timeout=100), ioloop._interrupt)
    Publisher.publish(push)
    client(client.socket, client.socket.poll(timeout=100), ioloop._interrupt)
    Publisher.publish(push)
    client(client.socket, client.socket.poll(timeout=100), ioloop._interrupt)
    time.sleep(0.1)
    print(client.receiver.last_message)
    assert client.receiver.framecount != 0
    assert len(client.receiver) == 3
    client._close()
    
def test_client_no_sub(ioloop, client, Publisher, push):
    """docstring for test_client_no_sub"""
    ioloop._add_socketinfo(client)
    
    Publisher.publish(push)
    assert_canrecv(client.socket)
    client.receiver.receive(client.socket)
    
    ioloop.start()
    try:
        time.sleep(0.01)
        Publisher.publish(push)
        time.sleep(0.1)
        Publisher.publish(push)
        time.sleep(0.1)
        Publisher.publish(push)
        time.sleep(0.1)
    finally:
        ioloop.stop()
    print(client.receiver.last_message)
    assert client.receiver.framecount != 0
    assert len(client.receiver) == 3
    
def test_client_add_to_loop(ioloop, client):
    """Test client add to a loop."""
    client.attach(ioloop)
    ioloop.start()
    try:
        time.sleep(0.01)
    finally:
        ioloop.stop()
    
def test_client_run(ioloop, client, Publisher, push):
    """Test a client in the IOLoop."""
    client.attach(ioloop)
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
    
def test_client_pubsub(ioloop, address, context, Publisher, pub):
    """docstring for test_client_pubsub"""
    client = Client.at_address(address, context, kind=zmq.SUB)
    client.attach(ioloop)
    ioloop.start()
    try:
        time.sleep(0.01)
        Publisher.publish(pub)
        Publisher.publish(pub)
        Publisher.publish(pub)
        time.sleep(0.1)
    finally:
        ioloop.stop()
    assert client.receiver.framecount != 0
    print(client.receiver.last_message)
    assert len(client.receiver) == 3
