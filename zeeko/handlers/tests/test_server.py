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
        c = self.cls(push, 0)
        for k, v in arrays:
            c.publisher[k] = v
        yield c
        c.close()
        
    @pytest.fixture
    def pubinfo(self, pub, sub, arrays):
        """A publishign socket info class."""
        c = self.cls(pub, 0)
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
        with ioloop.running():
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
        ioloop.throttle.frequency = 100
        ioloop.throttle.active = True
        start = time.time()
        with ioloop.running():
            ioloop.state.selected("RUN").wait()
            while pubinfo.publisher.framecount < 100 and (time.time() - start) < 1.1:
                assert_canrecv(sub)
                Receiver.receive(sub)
                # time.sleep(0.01)
        stop = time.time()
        assert pubinfo.publisher.framecount == approx(100, abs=5)
        framerate = (pubinfo.publisher.framecount / (stop - start))
        print(pubinfo.publisher.framecount, (stop-start))
        assert framerate == approx(100, abs=5)
        
    def test_server_framerate(self, ioloop, pubinfo, arrays, sub, Receiver):
        """Test that the server approximately handles a given framerate."""
        sub.subscribe("")
        pubinfo.attach(ioloop)
        pubinfo.throttle.frequency = 100
        pubinfo.throttle.active = True
        start = time.time()
        with ioloop.running():
            ioloop.state.selected("RUN").wait()
            while pubinfo.publisher.framecount < 100 and (time.time() - start) < 1.1:
                Receiver.receive(sub)
                # time.sleep(0.01)
        stop = time.time()
        assert pubinfo.publisher.framecount == approx(100, abs=5)
        framerate = (pubinfo.publisher.framecount / (stop - start))
        print(pubinfo.publisher.framecount, (stop-start))
        assert framerate == approx(100, abs=5)
        
    def test_throttle(self, ioloop, socketinfo, arrays, pull, Receiver):
        """Test the throttle"""
        socketinfo.attach(ioloop)
        socketinfo.throttle.period = 100
        socketinfo.throttle.active = True
        ioloop.start()
        c = 0
        try:
            ioloop.state.selected("RUN").wait()
            for i in range(3):
                if pull.poll(100) and c < 3 * len(arrays):
                    Receiver.receive(pull)
                    c += 1
                time.sleep(0.01)
        finally:
            ioloop.stop()
        assert c <= len(arrays)
        assert Receiver.framecount == 1