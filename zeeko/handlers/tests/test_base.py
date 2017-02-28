import pytest
import zmq
import time

from pytest import approx


from ...cyloop.throttle import Throttle
from ...utils.stopwatch import Stopwatch
from ..base import SocketInfo, SocketOptions
from ...tests.test_helpers import ZeekoTestBase


class SocketInfoTestBase(ZeekoTestBase):
    """Base class for socket info tests."""
    
    cls = None
    
    @pytest.fixture
    def socketinfo(self):
        """Return a socket info class."""
        return self.cls()
    
    def test_socket(self, socketinfo):
        """Test the basics of socketinfo."""
        assert isinstance(socketinfo, self.cls)
        assert isinstance(socketinfo.socket, zmq.Socket)
        assert socketinfo.events in [0, zmq.POLLIN, zmq.POLLOUT, zmq.POLLIN & zmq.POLLOUT, zmq.POLLERR]
        assert isinstance(socketinfo.throttle, Throttle)
        
    def run_loop_throttle_test(self, ioloop, throttle, counter_callback, callback, frequency=100, nevents=100, timeout=0.1):
        """Test the throttle"""
        throttle.frequency = frequency
        throttle.active = True
        timelimit = (1.1 * nevents / frequency)
        
        duration = self.run_loop_counter(ioloop, counter_callback, callback, timelimit=timelimit, nevents=nevents, timeout=timeout)
        
        assert counter_callback() == approx(nevents, abs=5)
        framerate = (counter_callback() / duration)
        print(counter_callback(), duration)
        assert framerate == approx(frequency, abs=5)
        
    def run_loop_snail_test(self, ioloop, snail, counter_callback, callback, n, narrays, timeout=0.1, force=False):
        """Run a snail test against the loop."""
        snail.nlate_max = 2 * narrays
        snail.delay_max = 0.1 * timeout * (-1.0 if force else 1.0)
        callback()
        time.sleep(timeout)
        
        with self.running_loop(ioloop, timeout):
            
            # Wait on the first message to come in.
            ioloop.state.selected("RUN").wait(timeout=timeout)
            time.sleep(0.1 * timeout)
            assert counter_callback() == 1
            assert snail.nlate == narrays
            
            # Pause, so we can send the second message with a delay.
            ioloop.pause()
            ioloop.state.selected("PAUSE").wait(timeout=timeout)
            callback()
            time.sleep(0.1 * timeout)
            
            # Resume, and receive the second message.
            ioloop.resume()
            ioloop.state.selected("RUN").wait(timeout=timeout)
            time.sleep(0.1 * timeout)
            assert snail.nlate == 2 * narrays
            
            # Again, pause and wait.
            ioloop.pause()
            ioloop.state.selected("PAUSE").wait(timeout=timeout)
            
            # Send more late messages.
            # This should trigger the snail death.
            for i in range(n):
                callback()
            time.sleep(0.1 * timeout)
            
            # Check that the snail actually dies.
            ioloop.resume()
            ioloop.state.selected("RUN").wait(timeout=timeout)
            time.sleep(0.1 * timeout)
            assert snail.deaths == 1
        
    def run_loop_snail_reconnect_test(self, ioloop, snail, counter_callback, callback, n, narrays, timeout=0.1, force=False):
        """Run a snail test against the loop."""
        snail.nlate_max = 2 * narrays
        snail.delay_max = 0.1 * timeout * (-1.0 if force else 1.0)
        callback()
        time.sleep(timeout)
        with ioloop.running(timeout=timeout):
            
            # Wait on the first message to come in.
            ioloop.state.selected("RUN").wait(timeout=timeout)
            time.sleep(0.1 * timeout)
            assert counter_callback() == 0
            assert snail.nlate == 0
            
            # Again, pause and wait.
            ioloop.pause()
            print("Waiting on PAUSE")
            ioloop.state.selected("PAUSE").wait(timeout=timeout)
            
            ioloop.resume()
            print("Waiting on RUN")
            ioloop.state.selected("RUN").wait(timeout=timeout)
            
            # Send more late messages.
            # This should trigger the snail death.
            for i in range(n):
                callback()
            time.sleep(0.1 * timeout)
            
            # Check that the snail actually dies.
            ioloop.pause()
            print("Waiting on PAUSE")
            ioloop.state.selected("PAUSE").wait(timeout=timeout)
            time.sleep(0.1 * timeout)
            assert counter_callback() == n + 1
            
    
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
        ioloop.attach(socketinfo)
        assert not socketinfo._is_loop_running()
        with self.running_loop(ioloop, timeout=0.1):
            assert socketinfo._is_loop_running()
        assert not socketinfo._is_loop_running()
        
    def test_getsocketoptions(self, ioloop, socketinfo):
        """Test socket options."""
        if socketinfo.opt is None:
            socketinfo.support_options()
        affinity = socketinfo.opt.get(zmq.AFFINITY)
        assert isinstance(affinity, int)
        ioloop.attach(socketinfo)
        recvmore = socketinfo.opt.get(zmq.RCVMORE)
        assert isinstance(recvmore, int)
        
        with self.running_loop(ioloop, timeout=0.1):
            # This should test against the REP/REQ pair
            # which impelments live socket options
            hwm = socketinfo.opt.get(zmq.RCVHWM)
            assert isinstance(hwm, int)
        
    
    def test_setsocketoptions(self, ioloop, socketinfo):
        """Test set socket options"""
        if socketinfo.opt is None:
            socketinfo.support_options()
        socketinfo.opt.set(zmq.RCVHWM, 10)
        ioloop.attach(socketinfo)
        hwm = socketinfo.opt.get(zmq.RCVHWM)
        assert hwm == 10
        
        print("Starting setsocketoptions loop test")
        with self.running_loop(ioloop, timeout=0.1):
            # This should test against the REP/REQ pair
            # which impelments live socket options
            socketinfo.opt.set(zmq.RCVHWM, 100)
            
            hwm = socketinfo.opt.get(zmq.RCVHWM)
            assert isinstance(hwm, int)
            assert hwm == 100
        
        print("Finished setsocketoptions loop test")
        
    
    def test_create_ioloop(self, socketinfo):
        """Test creating an IOLoop instance"""
        ioloop = socketinfo.create_ioloop()
        with self.running_loop(ioloop, timeout=0.1):
            assert socketinfo._is_loop_running()
    
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
        
    def test_create_ioloop(self, socketinfo):
        """Socketinfo shouldn't work."""
        with pytest.raises(AssertionError):
            super(TestSocketInfo, self).test_create_ioloop(socketinfo)
        
        
    def test_setsocketoptions(self, ioloop, socketinfo):
        """Sockopts shouldn't work."""
        with pytest.raises(AssertionError):
            super(TestSocketInfo, self).test_setsocketoptions(ioloop, socketinfo)
        
    def test_getsocketoptions(self, ioloop, socketinfo):
        """Sockopts shouldn't work."""
        with pytest.raises(AssertionError):
            super(TestSocketInfo, self).test_getsocketoptions(ioloop, socketinfo)
        
    def test_attach(self, ioloop, socketinfo):
        """Test attach this socket to an event loop."""
        with pytest.raises(AssertionError):
            ioloop.attach(socketinfo)
            
    def test_check(self, socketinfo):
        """Check the socket."""
        with pytest.raises(AssertionError):
            socketinfo.check() # Should assert some internal stuff.
            

class TestSocketOptions(SocketInfoTestBase):
    """Test the client socket."""
    
    cls = SocketOptions
    
    @pytest.fixture
    def socketinfo(self, pull):
        """Socket information."""
        si = self.cls.wrap_socket(pull)
        yield si
        si.close()
    
    