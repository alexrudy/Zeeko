
import pytest
import numpy as np
import json
import zmq
import h5py
import struct

from .. import chunk_api
from .. import chunk as chunk_capi
from .. import io

@pytest.fixture(params=[chunk_api.PyChunk, chunk_capi.Chunk])
def chunk_cls(request):
    """The chunk class in use."""
    return request.param

@pytest.fixture
def chunk(chunk_cls, name, chunk_array, chunk_mask):
    """A fixture object for chunks"""
    return chunk_cls(name, chunk_array, chunk_mask)

@pytest.fixture
def filename(tmpdir):
    """The filename"""
    return str(tmpdir.join("chunk.h5py"))
    
def assert_chunk_allclose(chunka, chunkb):
    """Assert that two chunks are essentially the same."""
    np.testing.assert_allclose(chunka.array, chunkb.array)
    np.testing.assert_allclose(chunka.mask, chunkb.mask)
    assert chunka.metadata == chunkb.metadata
    assert chunka.chunksize == chunkb.chunksize
    assert chunka.lastindex == chunkb.lastindex
    assert chunka._lastindex == chunkb._lastindex
    assert chunka.name == chunkb.name
    assert repr(chunka).lstrip("<Py") == repr(chunkb).lstrip("<Py")

def test_chunk_message(chunk_cls, name, chunk_array, chunk_mask, lastindex):
    """Test generating an array message."""
    chunk = chunk_cls(name, chunk_array, chunk_mask)
    meta = chunk.md
    assert tuple(meta['shape']) == chunk_array.shape[1:]
    assert meta['dtype'] == chunk_array.dtype.str
    assert name == chunk.name
    assert (lastindex - 1) == chunk.lastindex
    assert np.max(chunk.mask) == lastindex
    assert np.argmax(chunk.mask) == chunk.lastindex
    assert chunk._lastindex == chunk.lastindex
    assert np.may_share_memory(chunk.array, chunk_array)
    assert np.may_share_memory(chunk.mask, chunk_mask)
    
def test_chunk_roundtrip(req, rep, chunk):
    """Test that an array can go round-trip."""
    chunk.send(req)
    rep_chunk = chunk_api.PyChunk.recv(rep.can_recv())
    assert_chunk_allclose(chunk, rep_chunk)
    rep_chunk.send(rep)
    req_chunk = chunk_api.PyChunk.recv(req.can_recv())
    assert_chunk_allclose(chunk, req_chunk)
    
def test_chunk_append(chunk, lastindex, array):
    """Append to a chunk."""
    assert (lastindex - 1) == chunk.lastindex
    chunk.append(array)
    assert lastindex == chunk.lastindex
    assert np.max(chunk.mask) == lastindex + 1
    assert np.argmax(chunk.mask) == chunk.lastindex
    np.testing.assert_allclose(chunk.array[chunk.lastindex], array)
    
def assert_h5py_allclose(group, chunk):
    """docstring for assert_h5py_allclose"""
    assert group.name.endswith(chunk.name)
    assert "data" in group
    assert "mask" in group
    findex = chunk.chunksize
    np.testing.assert_allclose(group['mask'][-findex:], (chunk.mask != 0).astype(np.int))
    np.testing.assert_allclose(group['data'][-findex:,...], chunk.array)
    
def test_chunk_write(chunk, lastindex, filename):
    """Try writing a chunk to a new h5py file"""
    with h5py.File(filename, 'w') as f:
        io.write(chunk, f)
    with h5py.File(filename, 'r') as f:
        assert chunk.name in f
        g = f[chunk.name]
        assert_h5py_allclose(g, chunk)
    
def test_chunk_copy(chunk):
    """Copy a chunk"""
    ochunk = chunk.copy()
    assert_chunk_allclose(chunk, ochunk)
    assert np.may_share_memory(chunk.array, ochunk.array)
    assert np.may_share_memory(chunk.mask, ochunk.mask)

