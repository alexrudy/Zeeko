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
        socketinfo.receive(socketinfo.socket)
        Publisher.publish(push)
        assert_canrecv(socketinfo.socket)
        socketinfo.receive(socketinfo.socket)
        Publisher.publish(push)
        assert_canrecv(socketinfo.socket)
        socketinfo.receive(socketinfo.socket)
        time.sleep(0.1)
        print(socketinfo.last_message)
        assert socketinfo.framecount != 0
        assert len(socketinfo) == 3
        socketinfo.close()
    
    def test_callback(self, ioloop, socketinfo, Publisher, push):
        """Test client without using the loop."""
        time.sleep(0.01)
        for i in range(3):
            Publisher.publish(push)
            assert_canrecv(socketinfo.socket)
            socketinfo(socketinfo.socket, socketinfo.socket.poll(timeout=100), ioloop.worker._interrupt)
        time.sleep(0.1)
        print(socketinfo.last_message)
        assert socketinfo.framecount != 0
        assert len(socketinfo) == 3
        socketinfo._close()
        
    def test_attached(self, ioloop, socketinfo, Publisher, push):
        """Test explicitly without the options manager."""
        ioloop.attach(socketinfo)
        nloop = 3
        self.run_loop_safely(ioloop, functools.partial(Publisher.publish, push), nloop)
        assert socketinfo.framecount != 0
        print(socketinfo.last_message)
        assert len(socketinfo) == 3
    
    def test_suicidal_snail(self, ioloop, socketinfo, Publisher, push):
        """Test the suicidal snail pattern."""
        
        ioloop.attach(socketinfo)
        socketinfo.use_reconnections = False
        self.run_loop_snail_test(ioloop, socketinfo.snail, 
                                 lambda : socketinfo.framecount, 
                                 functools.partial(Publisher.publish, push),
                                 n = 3, narrays = len(Publisher))
        assert socketinfo.framecount != 0
        print(socketinfo.last_message)
        assert len(socketinfo) == 3
    
    @pytest.mark.skip
    def test_suicidal_snail_reconnections(self, ioloop, context, Publisher, pub, address):
        """Ensure that reconnections prevent receiving during pauses."""
        socketinfo = self.cls.at_address(address, context, kind=zmq.SUB)
        ioloop.attach(socketinfo)
        socketinfo.enable_reconnections(address)
        self.run_loop_snail_reconnect_test(ioloop, socketinfo.snail, 
                                           lambda : socketinfo.framecount, 
                                           functools.partial(Publisher.publish, pub),
                                           n = 3, narrays = len(Publisher), force=True)
        assert socketinfo.framecount != 0
        print(socketinfo.last_message)
        assert len(socketinfo) == 3
            
    def test_pubsub(self, ioloop, address, context, Publisher, pub):
        """Test the pub/sub algorithm."""
        client = self.cls.at_address(address, context, kind=zmq.SUB)
        ioloop.attach(client)
        nloop = 3
        self.run_loop_safely(ioloop, functools.partial(Publisher.publish, pub), nloop)
        assert client.framecount != 0
        print(client.last_message)
        assert len(client) == nloop
