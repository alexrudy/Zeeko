# -*- coding: utf-8 -*-

import pytest
import time
import functools
import zmq
from ..handlers import Telemetry, TelemetryWriter
from zeeko.conftest import assert_canrecv
from ...handlers.tests.test_base import SocketInfoTestBase
from ...tests.test_helpers import ZeekoMappingTests
from .test_recorder import RecorderTests

class TestClientMapping(ZeekoMappingTests):
    """Test client mapping"""
    cls = Telemetry
    
    @pytest.fixture
    def mapping(self, pull, push, Publisher):
        """A client, set up for use as a mapping."""
        c = self.cls(pull, zmq.POLLIN)
        Publisher.publish(push)
        while pull.poll(timeout=100, flags=zmq.POLLIN):
            c.receive(pull)
        yield c
        c.close()
        
    @pytest.fixture
    def keys(self, Publisher):
        """Return keys which should be availalbe."""
        return Publisher.keys()

class TestClientReceiver(RecorderTests):
    """Tests for telemetry client."""
    cls = Telemetry
    
    @pytest.fixture
    def receiver(self, pull, push, chunksize):
        """The receiver object"""
        return self.cls(pull, zmq.POLLIN, chunksize=chunksize)

class TestRClient(SocketInfoTestBase):
    """Test the client socket."""
    
    cls = Telemetry
    
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
        socketinfo.receive()
        Publisher.publish(push)
        assert_canrecv(socketinfo.socket)
        socketinfo.receive()
        Publisher.publish(push)
        assert_canrecv(socketinfo.socket)
        socketinfo.receive(socketinfo.socket)
        time.sleep(0.1)
        print(socketinfo.last_message)
        assert socketinfo.framecounter != 0
        assert len(socketinfo) == 3
        socketinfo.close()
    
    def test_callback(self, ioloop, socketinfo, Publisher, push):
        """Test client without using the loop."""
        time.sleep(0.01)
        for n in range(3):
            Publisher.publish(push)
            assert_canrecv(socketinfo.socket)
            socketinfo(socketinfo.socket, socketinfo.socket.poll(timeout=100), ioloop.worker._interrupt)
        print(socketinfo.last_message)
        assert socketinfo.framecounter != 0
        assert len(socketinfo) == 3
        socketinfo._close()
        
    def test_attached(self, ioloop, socketinfo, Publisher, push):
        """Test explicitly without the options manager."""
        ioloop.attach(socketinfo)
        
        n = 3
        self.run_loop_safely(ioloop, functools.partial(Publisher.publish, push), n)
        assert socketinfo.framecounter == n * len(Publisher)
        print(socketinfo.last_message)
        assert len(socketinfo) == len(Publisher)
        
    @pytest.mark.skip
    def test_suicidal_snail(self, ioloop, socketinfo, Publisher, push):
        """Test the suicidal snail pattern."""

        ioloop.attach(socketinfo)
        socketinfo.use_reconnections = False
        self.run_loop_snail_test(ioloop, socketinfo.snail,
                                 lambda : socketinfo.recorder.counter,
                                 functools.partial(Publisher.publish, push),
                                 n = 3, narrays = len(Publisher))
        assert socketinfo.framecounter != 0
        print(socketinfo.last_message)
        assert len(socketinfo.receiver) == 3
    
    def test_pubsub(self, ioloop, address, context, Publisher, pub):
        """Test the pub/sub algorithm."""
        client = self.cls.at_address(address, context, kind=zmq.SUB, enable_notifications=False)
        ioloop.attach(client)
        n = 3
        self.run_loop_safely(ioloop, functools.partial(Publisher.publish, pub), n)
        assert client.framecounter != 0
        print(client.last_message)
        assert len(client) == 3
