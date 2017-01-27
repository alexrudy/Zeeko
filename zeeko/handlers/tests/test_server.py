import pytest
import time
import functools
import zmq
from ..server import Server
from zeeko.conftest import assert_canrecv
from .test_base import SocketInfoTestBase

class TestServer(SocketInfoTestBase):
    """Test the client socket."""
    
    cls = Server
    
    @pytest.fixture
    def socketinfo(self, pull, push, arrays):
        """Socket info"""
        c = self.cls(push, zmq.POLLIN)
        for k, v in arrays:
            c.publisher[k] = v
        yield c
        c.close()
        
    def test_serve(self, ioloop, socketinfo, arrays, pull, Receiver):
        """docstring for test_serve"""
        socketinfo.attach(ioloop)
        socketinfo.throttle.frequency = 100
        socketinfo.throttle.active = True
        ioloop.start()
        c = 0
        try:
            while pull.poll(100) and c < 3 * len(arrays):
                Receiver.receive(pull)
                c += 1
        finally:
            ioloop.stop()
            
        
    def test_throttle(self, ioloop, socketinfo, arrays, pull, Receiver):
        """Test the throttle"""
        socketinfo.attach(ioloop)
        socketinfo.throttle.period = 100
        socketinfo.throttle.active = True
        ioloop.start()
        c = 0
        try:
            for i in range(3):
                if pull.poll(100) and c < 3 * len(arrays):
                    Receiver.receive(pull)
                    c += 1
                time.sleep(0.01)
        finally:
            ioloop.stop()
        assert c <= 1