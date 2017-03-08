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
        while not pipeline.record.pushed.is_set():
            Publisher.update()
            Publisher.publish(pub)
            time.sleep(0.1)
        pipeline.record.pushed.wait(timeout=3.0)
        pipeline.write.fired.wait(timeout=3.0)
    pipeline.state.selected("STOP").wait(timeout=1.0)
    print(pipeline.record.complete)
    for chunk in pipeline.record:
        print("{0}: {1}".format(chunk, pipeline.record[chunk].lastindex))
    assert pipeline.record.pushed.is_set()
    assert pipeline.write.fired.is_set()
    assert pipeline.record.framecounter == len(Publisher) * chunksize
    with h5py.File(filename, 'r') as f:
        assert 'telemetry' in f
        mg = f['telemetry']
        for name in Publisher.keys():
            assert name in mg
            g = mg[name]
            assert g['data'].shape[0] == (chunksize)
            # Compute the last index
            print(np.arange(g['mask'].shape[0])[g['mask'][...] == 1])
            li = (np.arange(g['mask'].shape[0])[g['mask'][...] == 1]).max()
            print(g['mask'][...])
            assert li == g['mask'].shape[0] - 1
            np.testing.assert_allclose(g['data'][li], Publisher[name].array)
    