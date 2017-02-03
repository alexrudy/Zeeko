# -*- coding: utf-8 -*-

import pytest
import time
import functools
import zmq
from ..client import Client
from zeeko.conftest import assert_canrecv
from .test_base import SocketInfoTestBase

class TestClient(SocketInfoTestBase):
    """Test the client socket."""
    
    cls = Client
    
    @pytest.fixture
    def socketinfo(self, pull, push):
        """Socket info"""
        c = self.cls(pull, zmq.POLLIN)
        yield c
        c.close()
    
    def test_no_loop(self, socketinfo, Publisher, push):
        """Test client without using the loop."""
        time.sleep(0.01)
        Publisher.publish(push)
        assert_canrecv(socketinfo.socket)
        socketinfo.receiver.receive(socketinfo.socket)
        Publisher.publish(push)
        assert_canrecv(socketinfo.socket)
        socketinfo.receiver.receive(socketinfo.socket)
        Publisher.publish(push)
        assert_canrecv(socketinfo.socket)
        socketinfo.receiver.receive(socketinfo.socket)
        time.sleep(0.1)
        print(socketinfo.receiver.last_message)
        assert socketinfo.receiver.framecount != 0
        assert len(socketinfo.receiver) == 3
        socketinfo.close()
    
    def test_callback(self, ioloop, socketinfo, Publisher, push):
        """Test client without using the loop."""
        time.sleep(0.01)
        Publisher.publish(push)
        assert_canrecv(socketinfo.socket)
        socketinfo(socketinfo.socket, socketinfo.socket.poll(timeout=100), ioloop._interrupt)
        Publisher.publish(push)
        assert_canrecv(socketinfo.socket)
        socketinfo(socketinfo.socket, socketinfo.socket.poll(timeout=100), ioloop._interrupt)
        Publisher.publish(push)
        assert_canrecv(socketinfo.socket)
        socketinfo(socketinfo.socket, socketinfo.socket.poll(timeout=100), ioloop._interrupt)
        time.sleep(0.1)
        print(socketinfo.receiver.last_message)
        assert socketinfo.receiver.framecount != 0
        assert len(socketinfo.receiver) == 3
        socketinfo._close()
        
    def test_attached(self, ioloop, socketinfo, Publisher, push):
        """Test explicitly without the options manager."""
        socketinfo.attach(ioloop)
        ioloop.start()
        try:
            ioloop.state.selected("RUN").wait(timeout=1)
            Publisher.publish(push)
            Publisher.publish(push)
            Publisher.publish(push)
            time.sleep(0.1)
        finally:
            ioloop.stop()
            ioloop.state.selected("STOP").wait(timeout=1)
        assert socketinfo.receiver.framecount != 0
        print(socketinfo.receiver.last_message)
        assert len(socketinfo.receiver) == 3
    
    def test_suicidal_snail(self, ioloop, socketinfo, Publisher, push):
        """Test the suicidal snail pattern."""
    
        socketinfo.attach(ioloop)
        socketinfo.snail.nlate_max = 2 * len(Publisher)
        socketinfo.snail.delay_max = 0.01
        socketinfo.use_reconnections = False
        Publisher.publish(push)
        time.sleep(0.1)
        ioloop.start()
        try:
            ioloop.state.selected("RUN").wait()
            time.sleep(0.01)
            assert socketinfo.receiver.framecount == 1
            assert socketinfo.snail.nlate == len(Publisher)
            ioloop.pause()
            ioloop.state.selected("PAUSE").wait()
            Publisher.publish(push)
            time.sleep(0.01)
            ioloop.resume()
            ioloop.state.selected("RUN").wait()
            assert socketinfo.snail.nlate == len(Publisher)
            ioloop.pause()
            ioloop.state.selected("PAUSE").wait()
            Publisher.publish(push)
            Publisher.publish(push)
            Publisher.publish(push)
            time.sleep(0.01)
            ioloop.resume()
            ioloop.state.selected("RUN").wait()
            time.sleep(0.1)
            assert socketinfo.snail.deaths == 1
        finally:
            ioloop.stop()
        assert socketinfo.receiver.framecount != 0
        print(socketinfo.receiver.last_message)
        assert len(socketinfo.receiver) == 3
    
    def test_suicidal_snail_reconnections(self, ioloop, socketinfo, Publisher, push, address):
        """Ensure that reconnections prevent receiving during pauses."""
        socketinfo.attach(ioloop)
        socketinfo.snail.nlate_max = 2 * len(Publisher)
        socketinfo.snail.delay_max = 0.01
        socketinfo.enable_reconnections(address)
        Publisher.publish(push)
        time.sleep(0.1)
        ioloop.start()
        try:
            ioloop.state.selected("RUN").wait()
            time.sleep(0.01)
            assert socketinfo.receiver.framecount == 0
            ioloop.resume()
            ioloop.state.selected("RUN").wait()
            Publisher.publish(push)
            Publisher.publish(push)
            Publisher.publish(push)
            time.sleep(0.01)
            ioloop.resume()
            ioloop.state.selected("RUN").wait()
            time.sleep(0.1)
            assert socketinfo.receiver.framecount == 4
        finally:
            ioloop.stop()
        assert socketinfo.receiver.framecount != 0
        print(socketinfo.receiver.last_message)
        assert len(socketinfo.receiver) == 3
    
    def test_pubsub(self, ioloop, address, context, Publisher, pub):
        """Test the pub/sub algorithm."""
        client = self.cls.at_address(address, context, kind=zmq.SUB)
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
