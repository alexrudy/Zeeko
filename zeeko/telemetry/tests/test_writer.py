import pytest
import numpy as np
import zmq
import struct
import itertools

from ..writer import Writer
from .. import chunk_api
from ...messages import array as array_api
from .conftest import assert_chunk_allclose, assert_h5py_allclose
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
    
@pytest.fixture
def filename(tmpdir):
    """Filename for telemetry recording."""
    return str(tmpdir.join("telemetry.hdf5"))
    
@pytest.fixture
def chunks(n, name, chunk_array, chunk_mask):
    """Return a list of chunks"""
    return [chunk_api.PyChunk("{0:s}{1:d}".format(name, i), np.random.randn(*chunk_array.shape), chunk_mask) for i in range(n)]

def test_writer_construction(filename):
    """Test construction"""
    w = Writer(filename)
    
class TestWriter(object):
    """Test case for recorders."""
    
    _framecount = itertools.count()
    
    pytestmark = pytest.mark.usefixtures("rnotify")
    
    @pytest.fixture
    def writer(self, push, pull, notify, filename):
        """Return a receiver"""
        self._pull = pull
        self._push = push
        self._notify = notify
        w = Writer(filename)
        w._setup_file()
        yield w
        w._teardown_file()
    
    @pytest.fixture
    def framecount(self):
        """Reutrn the framecount."""
        return next(self._framecount)
    
    def recv(self, writer):
        """Receive writer."""
        assert_canrecv(self._pull)
        while self._pull.poll(timeout=1):
            rc = writer.receive(self._pull, self._notify)
        return rc
    
    def send(self, chunks, framecount):
        """Send chunks via the chunk_api"""
        array_api.send_array_packet_header(self._push, "arrays", len(chunks), framecount, flags=zmq.SNDMORE)
        for chunk in chunks[:-1]:
            chunk.send(self._push, flags=zmq.SNDMORE)
        chunks[-1].send(self._push, flags=0)
    
    def test_once(self, chunks, framecount, writer):
        """Test the writer system with a single message."""
        self.send(chunks, framecount)
        self.recv(writer)
        assert len(writer) == len(chunks)
        cdict = {chunk.name:chunk for chunk in chunks}
        for key in writer.keys():
            chunk = writer[key]
            print(chunk)
            assert_chunk_allclose(chunk, cdict[key])
        writer.file.flush()
        for key in writer.keys():
            assert_h5py_allclose(writer.file[key], cdict[key])
        
    def test_sentinel(self, writer, rnotify):
        """Test the shutdown sentinel"""
        array_api.send_array_packet_header(self._push, "done", 0, 0, flags=0)
        rc = self.recv(writer)
        assert rc == -2
        assert_canrecv(rnotify)
        struct.unpack("i",rnotify.recv()) == (2,)
        
