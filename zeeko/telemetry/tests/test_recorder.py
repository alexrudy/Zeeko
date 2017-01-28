import pytest
import numpy as np
import zmq

from ..recorder import Recorder
from ...messages import array as array_api
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
    
    pytestmark = pytest.mark.usefixtures("rnotify")

    def test_once(self, push, pull, notify, rnotify, shape, name, n, chunksize):
        """Test the receiver system."""
        arrays = [("{:s}{:d}".format(name, i), np.random.randn(*shape)) for i in range(n)]
    
        framecount = 5
        array_api.send_array_packet(push, framecount, arrays)
    
        rcv = Recorder(chunksize)
        assert_canrecv(pull)
        while pull.poll(timeout=1):
            rcv.receive(pull, notify)
        assert len(rcv) == n
        for i in range(len(rcv)):
            chunk = rcv["{:s}{:d}".format(name, i)]
            print(chunk)
            print(np.allclose(chunk.array, 0.0))
            np.testing.assert_allclose(chunk.array[0,...], arrays[i][1])
        

    def test_recorder_unbundled(self, push, pull, notify, shape, name, n, chunksize):
        """Test the receiver system."""
        arrays = [("{:s}{:d}".format(name, i), np.random.randn(*shape)) for i in range(n)]
    
        for _name, array in arrays:
            array_api.send_named_array(push, _name, array)
    
        rcv = Recorder(chunksize)
        for i in range(n):
            assert_canrecv(pull)
            rcv.receive(pull, notify)
        assert len(rcv) == n
        print(rcv.keys())
        for i in range(len(rcv)):
            key = "{:s}{:d}".format(name, i)
            source = arrays[i][1]
            target = rcv[key].array[0,...]
            np.testing.assert_allclose(target, source)
    
    def test_receiver_multiple(self, push, pull, notify, shape, name, n, chunksize):
        """Test receive multiple messages."""
        arrays = [("{:s}{:d}".format(name, i), np.random.randn(*shape)) for i in range(n)]
        arrays2 = [("{:s}{:d}".format(name, i), np.random.randn(*shape)) for i in range(n)]
    
        framecount = 5
        array_api.send_array_packet(push, framecount, arrays)
        framecount = 6
        array_api.send_array_packet(push, framecount, arrays2)
    
        rcv = Recorder(chunksize)
        # event = rcv.event("{:s}{:d}".format(name, 0))
        # assert not event.is_set()
        assert_canrecv(pull)
        rcv.receive(pull, notify)
        assert len(rcv) == n
        # assert event.is_set()
        for i in range(len(rcv)):
            print(rcv["{:s}{:d}".format(name, i)])
            np.testing.assert_allclose(rcv["{:s}{:d}".format(name, i)].array[0,...], arrays[i][1])
        assert_canrecv(pull)
        rcv.receive(pull, notify)
        for i in range(len(rcv)):
            print(rcv["{:s}{:d}".format(name, i)])
            np.testing.assert_allclose(rcv["{:s}{:d}".format(name, i)].array[1,...], arrays2[i][1])
    
    def test_retain_multiple(self, push, pull, notify, shape, name, n, chunksize):
        """Test retaining multiple references to a given array."""
        arrays = [("{:s}{:d}".format(name, i), np.random.randn(*shape)) for i in range(n)]
        arrays2 = [("{:s}{:d}".format(name, i), np.random.randn(*shape)) for i in range(n)]
    
        framecount = 5
        array_api.send_array_packet(push, framecount, arrays)
        framecount = 6
        array_api.send_array_packet(push, framecount, arrays2)
    
        rcv = Recorder(chunksize)
        assert_canrecv(pull)
        rcv.receive(pull, notify)
        assert len(rcv) == n
        for i in range(len(rcv)):
            np.testing.assert_allclose(rcv["{:s}{:d}".format(name, i)].array[0,...], arrays[i][1])
        refd_array = rcv["{:s}{:d}".format(name, 1)].array
        assert_canrecv(pull)
        rcv.receive(pull, notify)
        for i in range(len(rcv)):
            np.testing.assert_allclose(rcv["{:s}{:d}".format(name, i)].array[1,...], arrays2[i][1])
        refd_array2 = rcv["{:s}{:d}".format(name, 1)].array
        np.testing.assert_allclose(refd_array, refd_array2)