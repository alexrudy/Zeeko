
import pytest
import numpy as np
import json
import zmq
import struct

from .. import chunk_api
from .. import chunk as chunk_capi

@pytest.fixture(params=[chunk_api.PyChunk, chunk_capi.Chunk])
def chunk_cls(request):
    """The chunk class in use."""
    return request.param

@pytest.fixture
def chunk(chunk_cls, name, chunk_array, chunk_mask):
    """A fixture object for chunks"""
    return chunk_cls(name, chunk_array, chunk_mask)
    
def assert_chunk_allclose(chunka, chunkb):
    """Assert that two chunks are essentially the same."""
    np.testing.assert_allclose(chunka.array, chunkb.array)
    np.testing.assert_allclose(chunka.mask, chunkb.mask)
    assert chunka.metadata == chunkb.metadata
    assert chunka.chunksize == chunkb.chunksize
    assert chunka.lastindex == chunkb.lastindex

def test_chunk_message(chunk_cls, name, chunk_array, chunk_mask, lastindex):
    """Test generating an array message."""
    chunk = chunk_cls(name, chunk_array, chunk_mask)
    meta = chunk.md
    assert tuple(meta['shape']) == chunk_array.shape[1:]
    assert meta['dtype'] == chunk_array.dtype.str
    assert (lastindex - 1) == chunk.lastindex
    assert np.max(chunk.mask) == lastindex
    assert np.argmax(chunk.mask) == chunk.lastindex
    assert np.may_share_memory(chunk.array, chunk_array)
    assert np.may_share_memory(chunk.mask, chunk_mask)
    
def test_chunk_roundtrip(req, rep, chunk):
    """Test that an array can go round-trip."""
    chunk.send(req)
    rep_chunk = chunk_api.PyChunk.recv(rep)
    assert_chunk_allclose(chunk, rep_chunk)
    rep_chunk.send(rep)
    req_chunk = chunk_api.PyChunk.recv(req)
    assert_chunk_allclose(chunk, req_chunk)
    
def test_chunk_append(chunk, lastindex, array):
    """Append to a chunk."""
    assert (lastindex - 1) == chunk.lastindex
    chunk.append(array)
    assert lastindex == chunk.lastindex
    assert np.max(chunk.mask) == lastindex + 1
    assert np.argmax(chunk.mask) == chunk.lastindex
    np.testing.assert_allclose(chunk.array[chunk.lastindex], array)
    
