import pytest
import numpy as np
import zmq
import h5py
import struct
import itertools

from .. import Writer
from .. import chunk_api
from ...messages import array as array_api
from .conftest import assert_chunk_allclose, assert_h5py_allclose
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

@pytest.fixture
def metadata_callback():
    """Return a metadata callback."""
    def callback():
        return {'meta':'data', 'n':5}
    return callback


def test_writer_construction(filename):
    """Test construction"""
    w = Writer(filename)
    
class WriterTestsBase(ReceiverTestBase):
    """Base class items for Writers."""
    
    pytestmark = pytest.mark.usefixtures("rnotify")
    cls = Writer
    
    @pytest.fixture
    def arrays(self, n, name, chunk_array, chunk_mask):
        """Return a list of chunks"""
        cs = OrderedDict()
        for i in range(n):
            c = chunk_api.PyChunk("{0:s}{1:d}".format(name, i), np.random.randn(*chunk_array.shape), chunk_mask)
            cs[c.name] = c
        return cs
    
    @pytest.fixture
    def receiver(self, filename, metadata_callback):
        """The receiver object"""
        obj = self.cls()
        obj.metadata_callback = metadata_callback
        with h5py.File(filename) as obj.file:
            yield obj
    
    @pytest.fixture
    def writer(self, receiver):
        """Return a receiver"""
        return receiver
        
    def send_arrays(self, socket, arrays, framecount):
        """Send arrays."""
        assert socket.poll(timeout=100, flags=zmq.POLLOUT)
        array_api.send_array_packet_header(socket, "arrays", len(arrays), framecount, flags=zmq.SNDMORE)
        chunks = list(arrays.values())
        for chunk in chunks[:-1]:
            chunk.send(socket, flags=zmq.SNDMORE)
        chunks[-1].send(socket)
        
    def recv_arrays(self, receiver, socket, arrays, flags=zmq.NOBLOCK):
        """Wrapper around receiving arrays."""
        assert_canrecv(socket)
        receiver.receive(socket, flags=flags)
        for key in arrays:
            assert receiver.event(key).is_set()
        assert len(receiver) == len(arrays)
    
    def send_unbundled_arrays(self, socket, arrays):
        """Send arrays as individual messages."""
        array_api.send_array_packet_header(socket, "arrays", len(arrays), flags=zmq.SNDMORE)
        chunks = list(arrays.values())
        for chunk in chunks[:-1]:
            chunk.send(socket, flags=zmq.SNDMORE)
        chunks[-1].send(socket)
        
    def recv_unbundled_arrays(self, receiver, socket, arrays, flags=zmq.NOBLOCK):
        """Receive unbundled arrays"""
        count = 0
        while socket.poll(timeout=100, flags=zmq.POLLIN):
            assert_canrecv(socket)
            receiver.receive(socket, flags=flags)
            count += 1
        for key in arrays:
            assert receiver.event(key).is_set()
        # assert count == len(arrays)
        
    def make_modified_arrays(self, arrays):
        """Make modified arrays."""
        return OrderedDict((cs.name, chunk_api.PyChunk(cs.name, cs.array * 2.0, cs.mask)) for cs in arrays.values())
    
    def assert_receiver_arrays_allclose(self, receiver, arrays):
        """Assert receiver and arrays are all close."""
        assert len(receiver) == len(arrays)
        assert set(receiver.keys()) == set(arrays.keys())
        for i, key in enumerate(receiver):
            chunk = receiver[key]
            assert_chunk_allclose(chunk, arrays[key])
        

class TestWriter(ReceiverTests, WriterTestsBase):
    """Test case for recorders."""
    pass
    
    
class TestWriterMapping(ZeekoMappingTests, WriterTestsBase):
    """Test recorder behavior as a mapping."""
    
    cls = Writer
    
    @pytest.fixture
    def mapping(self, chunksize, push, pull, arrays, framecount, filename, metadata_callback):
        """A client, set up for use as a mapping."""
        obj = self.cls()
        obj.metadata_callback = metadata_callback
        with h5py.File(filename) as obj.file:
            self.send_arrays(push, arrays, framecount)
            self.recv_arrays(obj, pull, arrays)
            yield obj
        
    @pytest.fixture
    def keys(self, arrays):
        """Return keys which should be availalbe."""
        return arrays.keys()
