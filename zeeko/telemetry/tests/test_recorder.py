import pytest
import numpy as np
import zmq
import itertools

from .. import Recorder
from ...messages import array as array_api
from ...messages import Publisher
from .conftest import assert_chunk_array_allclose, assert_chunk_allclose
from zeeko.conftest import assert_canrecv

@pytest.fixture
def notify(address2, context):
    """Notification socket"""
    s = context.socket(zmq.PUSH)
    s.bind(address2)
    with s:
        yield s
    
@pytest.fixture
def rnotify(address2, context, notify):
    """Recieve notifications."""
    s = context.socket(zmq.PULL)
    s.connect(address2)
    with s:
        yield s

@pytest.fixture
def n():
    """Number of arrays to publish."""
    return 3

@pytest.fixture(params=[10, 1024])
def chunksize(request):
    """Chunksize"""
    return request.param

def test_recorder_construction(chunksize):
    """Test construction"""
    r = Recorder(chunksize)
    
class TestRecorder(object):
    """Test case for recorders."""
    
    _framecount = itertools.count()
    
    pytestmark = pytest.mark.usefixtures("rnotify")
    
    @pytest.fixture
    def recorder(self, push, pull, notify, chunksize):
        """Return a receiver"""
        self._pull = pull
        self._notify = notify
        return Recorder(chunksize)
    
    @pytest.fixture
    def framecount(self):
        """Reutrn the framecount."""
        return next(self._framecount)
    
    @pytest.fixture
    def arrays(self, name, shape, n):
        """Arrays to send over the socket."""
        return [("{0:s}{1:d}".format(name, i), np.random.randn(*shape)) for i in range(n)]
    
    @pytest.fixture
    def publisher(self, push, arrays, framecount):
        """Create a publisher."""
        self._push = push
        p = Publisher()
        for name, array in arrays:
            p[name] = array
        p.framecount = framecount
        return p
        
    def publisher2(self, publisher):
        """Update the publisher."""
        p2 = Publisher()
        p2.framecount = publisher.framecount + 1
        for key in publisher.keys():
            p2[key] = np.random.randn(*publisher[key].shape)
        return p2
    
    def recv(self, recorder):
        """Receive recorder."""
        assert_canrecv(self._pull)
        while self._pull.poll(timeout=1):
            recorder.receive(self._pull, self._notify)
    
    def send(self, publisher):
        """Publish"""
        publisher.publish(self._push)
    
    def test_once(self, publisher, recorder):
        """Test the receiver system with a single message."""
        self.send(publisher)
        self.recv(recorder)
        assert len(recorder) == len(publisher)
        for key in recorder.keys():
            chunk = recorder[key]
            print(chunk)
            assert_chunk_array_allclose(chunk, publisher[key])
    
    def test_multiple(self, publisher, recorder):
        """Test receive multiple messages."""
        publisher2 = self.publisher2(publisher)
        
        #TODO: Re-enable events?
        # event = rcv.event("{:s}{:d}".format(name, 0))
        # assert not event.is_set()
        self.send(publisher)
        self.send(publisher2)
        self.recv(recorder)
        assert len(recorder) == len(publisher)
        for key in publisher.keys():
            assert_chunk_array_allclose(recorder[key], publisher[key], 0)
            assert_chunk_array_allclose(recorder[key], publisher2[key], 1)
    
    @pytest.mark.xfail
    def test_retain_multiple(self, publisher, recorder):
        """Test retaining multiple references to a given array."""
        publisher2 = self.publisher2(publisher)
        
        self.send(publisher)
        self.recv(recorder)
        arrays = {}
        for key in recorder.keys():
            arrays[key] = recorder[key] 
        self.send(publisher2)
        self.recv(recorder)
        arrays2 = {}
        for key in recorder.keys():
            arrays2[key] = recorder[key] 
        assert len(recorder) == len(publisher)
        for key in publisher.keys():
            assert_chunk_allclose(arrays[key], arrays2[key])
            assert_chunk_array_allclose(recorder[key], publisher[key], 0)
            assert_chunk_array_allclose(recorder[key], publisher2[key], 1)