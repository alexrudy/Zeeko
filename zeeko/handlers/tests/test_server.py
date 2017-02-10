import pytest
import time
import functools
import zmq
from pytest import approx
from ..server import Server
from zeeko.conftest import assert_canrecv
from .test_base import SocketInfoTestBase

class TestServer(SocketInfoTestBase):
    """Test the client socket."""
    
    cls = Server
    
    @pytest.fixture
    def socketinfo(self, pull, push, arrays):
        """Socket info"""
        c = self.cls(push, zmq.POLLERR)
        for k, v in arrays:
            c.publisher[k] = v
        yield c
        c.close()
        
    @pytest.fixture
    def pubinfo(self, pub, sub, arrays):
        """A publishign socket info class."""
        c = self.cls(pub, zmq.POLLERR)
        for k, v in arrays:
            c.publisher[k] = v
        yield c
        c.close()
        
    def test_serve(self, ioloop, socketinfo, arrays, pull, Receiver):
        """Test running the server."""
        socketinfo.attach(ioloop)
        socketinfo.throttle.frequency = 100
        socketinfo.throttle.active = True
        start = time.time()
        with ioloop.running(timeout=0.1):
            c = 0
            ioloop.state.selected("RUN").wait()
            while pull.poll(1000) and c < 3 * len(arrays):
                assert_canrecv(pull)
                Receiver.receive(pull)
                c += 1
        stop = time.time()
        assert c > 0
        assert socketinfo.publisher.framecount >= c / len(arrays)
        
    def test_framerate(self, ioloop, pubinfo, arrays, sub, Receiver):
        """Test that the server approximately handles a given framerate."""
        sub.subscribe("")
        pubinfo.attach(ioloop)
        def callback():
            assert_canrecv(sub)
            Receiver.receive(sub)
        self.run_loop_throttle_test(ioloop, ioloop.throttle, lambda : pubinfo.publisher.framecount, callback)
        
    @pytest.mark.xfail
    def test_server_framerate(self, ioloop, pubinfo, arrays, sub, Receiver):
        """Test that the server approximately handles a given framerate."""
        sub.subscribe("")
        pubinfo.attach(ioloop)
        def callback():
            assert_canrecv(sub)
            Receiver.receive(sub)
        self.run_loop_throttle_test(ioloop, pubinfo.throttle, lambda : pubinfo.publisher.framecount, callback)
        