import pytest
import time
import functools
import zmq
from pytest import approx
from ..server import Server
from zeeko.conftest import assert_canrecv
from .test_base import SocketInfoTestBase

from ...tests.test_helpers import ZeekoMutableMappingTests
from ...messages.tests.test_publisher import BasePublisherTests

class TestServerMutableMapping(ZeekoMutableMappingTests):
    """Test the server as a mutable mapping."""
    
    cls = Server
    
    @pytest.fixture
    def mapping(self, pull, push, arrays):
        """A client, set up for use as a mapping."""
        c = self.cls(push, zmq.POLLIN)
        for k, v in arrays:
            c[k] = v
        yield c
        c.close()
        
    @pytest.fixture
    def keys(self, arrays):
        """Return keys which should be availalbe."""
        return [k for k,v in arrays]
    

class TestServerPublisher(BasePublisherTests):
    """Tests for the Server conforming to the publisher interface."""
    
    cls = Server
    
    @pytest.fixture
    def obj(self, pull, push, arrays):
        """Return the publisher, with arrays."""
        c = self.cls(push, zmq.POLLERR)
        for k, v in arrays:
            c[k] = v
        yield c
        c.close()
    

class TestServer(SocketInfoTestBase):
    """Test the client socket."""
    
    cls = Server
    
    @pytest.fixture
    def socketinfo(self, pull, push, arrays):
        """Socket info"""
        c = self.cls(push, zmq.POLLERR)
        for k, v in arrays:
            c[k] = v
        yield c
        c.close()
        
    @pytest.fixture
    def pubinfo(self, pub, sub, arrays):
        """A publishign socket info class."""
        c = self.cls(pub, zmq.POLLERR)
        for k, v in arrays:
            c[k] = v
        yield c
        c.close()
        
    def test_serve(self, ioloop, socketinfo, arrays, pull, Receiver):
        """Test running the server."""
        ioloop.attach(socketinfo)
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
        assert socketinfo.framecount >= c / len(arrays)
        
    def test_framerate(self, ioloop, pubinfo, arrays, sub, Receiver):
        """Test that the server approximately handles a given framerate."""
        sub.subscribe("")
        ioloop.attach(pubinfo)
        def callback():
            assert_canrecv(sub)
            Receiver.receive(sub)
        self.run_loop_throttle_test(ioloop, ioloop.worker.throttle, lambda : pubinfo.framecount, callback)
        
    @pytest.mark.xfail
    def test_server_framerate(self, ioloop, pubinfo, arrays, sub, Receiver):
        """Test that the server approximately handles a given framerate."""
        sub.subscribe("")
        ioloop.attach(pubinfo)
        def callback():
            assert_canrecv(sub)
            Receiver.receive(sub)
        self.run_loop_throttle_test(ioloop, pubinfo.throttle, lambda : pubinfo.framecount, callback)
        