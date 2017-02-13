import pytest
import h5py
import time
import numpy as np
from ..pipeline import create_pipeline

@pytest.fixture
def chunksize():
    """The size of chunks."""
    return 10

@pytest.fixture
def pipeline(address, context, chunksize, filename):
    """Pipeline"""
    ioloop = create_pipeline(address, context, chunksize, filename)
    yield ioloop
    ioloop.cancel()

def test_create_pipeline(address, context, chunksize, filename):
    """Test creating a pipeline."""
    ioloop = create_pipeline(address, context, chunksize, filename)
    print("Created")
    ioloop.cancel(timeout=0.1)
    print("Canceled")

def test_run_pipeline(pipeline, Publisher, pub, filename, chunksize):
    """Test running the pipeline."""
    with pipeline.running(timeout=0.1):
        pipeline.state.selected("RUN").wait(timeout=0.1)
        for i in range(10):
            Publisher.update()
            Publisher.publish(pub)
            time.sleep(0.1)
    pipeline.state.selected("STOP").wait(timeout=0.1)
    assert pipeline.record.recorder.chunkcount == 1
    with h5py.File(filename, 'r') as f:
        for name in Publisher.keys():
            assert name in f
            g = f[name]
            assert g['data'].shape[0] == chunksize
            np.testing.assert_allclose(g['data'][-1], Publisher[name].array)
    