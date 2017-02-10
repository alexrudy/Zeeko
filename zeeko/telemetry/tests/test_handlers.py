# -*- coding: utf-8 -*-

import pytest
import time
import functools
import zmq
from ..handlers import RClient, WClient
from zeeko.conftest import assert_canrecv
from ...handlers.tests.test_base import SocketInfoTestBase

class TestRClient(SocketInfoTestBase):
    """Test the client socket."""
    
    cls = RClient
    
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
        socketinfo.recorder.receive(socketinfo.socket)
        Publisher.publish(push)
        assert_canrecv(socketinfo.socket)
        socketinfo.recorder.receive(socketinfo.socket)
        Publisher.publish(push)
        assert_canrecv(socketinfo.socket)
        socketinfo.recorder.receive(socketinfo.socket)
        time.sleep(0.1)
        print(socketinfo.recorder.last_message)
        assert socketinfo.recorder.counter != 0
        assert len(socketinfo.recorder) == 3
        socketinfo.close()
    
    def test_callback(self, ioloop, socketinfo, Publisher, push):
        """Test client without using the loop."""
        time.sleep(0.01)
        for n in range(3):
            Publisher.publish(push)
            assert_canrecv(socketinfo.socket)
            socketinfo(socketinfo.socket, socketinfo.socket.poll(timeout=100), ioloop.worker._interrupt)
        print(socketinfo.recorder.last_message)
        assert socketinfo.recorder.counter != 0
        assert len(socketinfo.recorder) == 3
        socketinfo._close()
        
    def test_attached(self, ioloop, socketinfo, Publisher, push):
        """Test explicitly without the options manager."""
        ioloop.attach(socketinfo)
        
        n = 3
        self.run_loop_safely(ioloop, functools.partial(Publisher.publish, push), n)
        assert socketinfo.recorder.counter != 0
        assert socketinfo.recorder.counter == n * len(Publisher)
        print(socketinfo.recorder.last_message)
        assert len(socketinfo.recorder) == len(Publisher)
        
    # def test_suicidal_snail(self, ioloop, socketinfo, Publisher, push):
    #     """Test the suicidal snail pattern."""
    #
    #     ioloop.attach(socketinfo)
    #     socketinfo.use_reconnections = False
    #     self.run_loop_snail_test(ioloop, socketinfo.snail,
    #                              lambda : socketinfo.recorder.counter,
    #                              functools.partial(Publisher.publish, push),
    #                              n = 3, narrays = len(Publisher))
    #     assert socketinfo.receiver.framecount != 0
    #     print(socketinfo.receiver.last_message)
    #     assert len(socketinfo.receiver) == 3
    
    def test_pubsub(self, ioloop, address, context, Publisher, pub):
        """Test the pub/sub algorithm."""
        client = self.cls.at_address(address, context, kind=zmq.SUB)
        ioloop.attach(client)
        n = 3
        self.run_loop_safely(ioloop, functools.partial(Publisher.publish, pub), n)
        assert client.recorder.counter != 0
        print(client.recorder.last_message)
        assert len(client.recorder) == 3
