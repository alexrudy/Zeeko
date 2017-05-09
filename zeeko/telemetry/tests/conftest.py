import pytest
import numpy as np

from ...messages import ArrayMessage

from zmq.utils import jsonapi
jsonify = lambda data : jsonapi.loads(jsonapi.dumps(data))

@pytest.fixture
def array(shape, dtype):
    """An array to send over the wire"""
    return (np.random.rand(*shape)).astype(dtype)
    
@pytest.fixture
def chunksize():
    """The size of chunks."""
    return 20
    
@pytest.fixture
def lastindex():
    """The last index filled in."""
    return 17
    
@pytest.fixture
def filename(tmpdir):
    """Filename for telemetry recording."""
    return str(tmpdir.join("telemetry_{0:02d}.hdf5"))
    
@pytest.fixture
def chunk_array(shape, dtype, chunksize, lastindex):
    """Return an array appropriate for the chunksize."""
    data = (np.random.rand(*((chunksize,) + shape))).astype(dtype)
    data[...,lastindex:] = 0.0
    return data

@pytest.fixture
def chunk_mask(chunksize, lastindex):
    """docstring for mask"""
    mask = -1*np.ones((chunksize,), dtype=np.int64)
    mask[:lastindex] = np.arange(lastindex)
    return mask
    
def assert_chunk_allclose(chunka, chunkb):
    """Assert that two chunks are essentially the same."""
    np.testing.assert_allclose(chunka.array, chunkb.array)
    np.testing.assert_allclose(chunka.mask, chunkb.mask)
    assert jsonify(chunka.md) == jsonify(chunkb.md)
    assert chunka.chunksize == chunkb.chunksize
    assert chunka.lastindex == chunkb.lastindex
    assert chunka.name == chunkb.name
    assert repr(chunka).lstrip("<Py") == repr(chunkb).lstrip("<Py")
    
def assert_chunk_array_allclose(chunk, array, index=None):
    """Assert that a chunk and an array are all close."""
    if isinstance(array, np.ndarray):
        array = ArrayMessage(chunk.name, array)
    
    if index is None:
        index = chunk.lastindex
    assert jsonify(chunk.md) == jsonify(array.md)
    assert chunk.name == array.name
    assert np.argmax(chunk.mask) >= index
    assert chunk.mask[index] >= 0
    np.testing.assert_allclose(chunk.array[index], array.array)

def assert_h5py_allclose(group, chunk):
    """Assert that an HDF5 group is close."""
    assert group.name.endswith(chunk.name)
    assert "data" in group
    assert "mask" in group
    findex = chunk.chunksize
    np.testing.assert_allclose(group['mask'][-findex:], chunk.mask.astype(np.int))
    np.testing.assert_allclose(group['data'][-findex:,...], chunk.array)
