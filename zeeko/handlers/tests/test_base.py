import pytest
import zmq
import time

from ...cyloop.throttle import Throttle
from ..base import SocketInfo


class SocketInfoTestBase(object):
    """Base class for socket info tests."""
    
    cls = None
    
    @pytest.fixture
    def socketinfo(self):
        """Return a socket info class."""
        return self.cls()
    
    def test_socket(self, socketinfo):
        """docstring for test_"""
        assert isinstance(socketinfo, self.cls)
        assert isinstance(socketinfo.socket, zmq.Socket)
        assert socketinfo.events in [0, zmq.POLLIN, zmq.POLLOUT, zmq.POLLIN & zmq.POLLOUT, zmq.POLLERR]
        assert isinstance(socketinfo.throttle, Throttle)
    
    def test_repr(self, socketinfo):
        """Get the repr"""
        r = repr(socketinfo)
        assert r[1:].startswith(self.cls.__name__)
        assert r[-1] == ">"
    
    def test_close(self, socketinfo):
        """Test the close function."""
        socketinfo.close()
        assert socketinfo.socket.closed
            
    def test_attach(self, ioloop, socketinfo):
        """Test client add to a loop."""
        socketinfo.attach(ioloop)
        ioloop.start()
        try:
            ioloop.state.selected("RUN").wait(timeout=1)
            time.sleep(0.01)
        finally:
            ioloop.stop()
            
        
    def test_check(self, socketinfo):
        """Test check should not raise"""
        socketinfo.check()
        

class TestSocketInfo(SocketInfoTestBase):
    
    cls = SocketInfo
    
    @pytest.fixture
    def socketinfo(self, context):
        """Socket information."""
        s = context.socket(zmq.PULL)
        si = self.cls(s, zmq.POLLIN)
        yield si
        si.close()
        
    def test_attach(self, ioloop, socketinfo):
        """Test attach this socket to an event loop."""
        with pytest.raises(AssertionError):
            socketinfo.attach(ioloop)
            
    def test_check(self, socketinfo):
        """Check the socket."""
        with pytest.raises(AssertionError):
            socketinfo.check() # Should assert some internal stuff.
    