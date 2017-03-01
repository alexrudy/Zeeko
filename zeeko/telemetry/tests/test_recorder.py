import pytest
import numpy as np
import zmq
import itertools

from .. import Recorder
from ...messages import array as array_api
from ...messages import Publisher, ArrayMessage
from .conftest import assert_chunk_array_allclose, assert_chunk_allclose
from zeeko.conftest import assert_canrecv
from ...tests.test_helpers import ZeekoTestBase, ZeekoMappingTests, OrderedDict
from ...messages.tests.test_receiver import ReceiverTests, ReceiverTestBase

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
    
class RecorderTests(ReceiverTests):
    """Test case for recorders."""
    
    @pytest.fixture
    def receiver(self, chunksize):
        """The receiver object"""
        return self.cls(chunksize)
    
    @pytest.fixture
    def recorder(self, receiver):
        """Return a receiver"""
        return receiver
        
    def assert_receiver_arrays_allclose(self, receiver, arrays):
        """Assert receiver and arrays are all close."""
        assert len(receiver) == len(arrays)
        assert set(receiver.keys()) == set(arrays.keys())
        for i, key in enumerate(receiver):
            chunk = receiver[key]
            assert_chunk_array_allclose(chunk, arrays[key])
    
    def test_once(self, recorder, push, pull, arrays, framecount):
        """Test the receiver system with a single message."""
        self.send_arrays(push, arrays, framecount)
        self.recv_arrays(recorder, pull, arrays)
        self.assert_receiver_arrays_allclose(recorder, arrays)
    
    def test_multiple(self, recorder, push, pull, arrays, framecount):
        """Test receive multiple messages."""
        self.send_arrays(push, arrays, framecount)
        arrays_2 = OrderedDict((key, data * 2.0) for key, data in arrays.items())
        self.send_arrays(push, arrays_2, framecount + 1)
        
        self.recv_arrays(recorder, pull, arrays)
        self.recv_arrays(recorder, pull, arrays)
        assert len(recorder) == len(arrays)
        for key in arrays:
            assert_chunk_array_allclose(recorder[key], ArrayMessage(key, arrays[key]), 0)
            assert_chunk_array_allclose(recorder[key], ArrayMessage(key, arrays[key] * 2.0), 1)
    
    def test_retain_multiple(self, recorder, push, pull, arrays, framecount):
        """Test retaining multiple references to a given array."""
        self.send_arrays(push, arrays, framecount)
        arrays_2 = OrderedDict((key, data * 2.0) for key, data in arrays.items())
        self.send_arrays(push, arrays_2, framecount + 1)
        
        self.recv_arrays(recorder, pull, arrays)
        got_arrays_1 = dict(recorder.items())
        self.recv_arrays(recorder, pull, arrays)
        got_arrays_2 = dict(recorder.items())
        assert len(recorder) == len(arrays)
        for key in arrays:
            assert_chunk_allclose(got_arrays_1[key], got_arrays_2[key])
            assert_chunk_array_allclose(got_arrays_1[key], ArrayMessage(key, arrays[key]), 0)
            assert_chunk_array_allclose(got_arrays_2[key], ArrayMessage(key, arrays_2[key]), 1)
        
class TestRecorder(RecorderTests):
    """Tests for just the recorder."""
    pytestmark = pytest.mark.usefixtures("rnotify")
    cls = Recorder
        
class TestRecorderMapping(ZeekoMappingTests, ReceiverTestBase):
    """Test recorder behavior as a mapping."""
    
    cls = Recorder
    
    @pytest.fixture
    def mapping(self, chunksize, push, pull, arrays, framecount):
        """A client, set up for use as a mapping."""
        recorder = self.cls(chunksize)
        self.send_arrays(push, arrays, framecount)
        self.recv_arrays(recorder, pull, arrays)
        yield recorder
        
    @pytest.fixture
    def keys(self, arrays):
        """Return keys which should be availalbe."""
        return arrays.keys()
        