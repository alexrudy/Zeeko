import pytest
import numpy as np

@pytest.fixture
def array(shape, dtype):
    """An array to send over the wire"""
    return (np.random.rand(*shape)).astype(dtype)
    
@pytest.fixture
def chunksize():
    """The size of chunks."""
    return 1024
    
@pytest.fixture
def lastindex():
    """The last index filled in."""
    return 512
    
@pytest.fixture
def chunk_array(shape, dtype, chunksize, lastindex):
    """Return an array appropriate for the chunksize."""
    data = (np.random.rand(*((chunksize,) + shape))).astype(dtype)
    data[...,lastindex:] = 0.0
    return data

@pytest.fixture
def chunk_mask(chunksize, lastindex):
    """docstring for mask"""
    mask = np.zeros((chunksize,), dtype=np.int32)
    mask[:lastindex] = np.arange(lastindex) + 1.0
    return mask