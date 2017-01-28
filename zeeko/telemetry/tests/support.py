import pytest
import numpy as np

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
    
def assert_chunk_array_allclose(chunk, array, index=None):
    """Assert that a chunk and an array are all close."""
    if index is None:
        index = chunk.lastindex
    assert chunk.metadata == array.metadata
    assert chunk.name == array.name
    assert np.max(chunk.mask) >= index + 1
    assert chunk.mask[index] == index + 1
    np.testing.assert_allclose(chunk.array[index], array.array)