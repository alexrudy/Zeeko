import pytest
import h5py
import time
import zmq
import numpy as np
from ...tests.test_helpers import ZeekoTestBase
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
    
class TestPipeline(ZeekoTestBase):
    """Tests for the pipeline."""
    
    def check_filename(self, filename, n, chunksize, nchunks, publisher):
        """docstring for check_filename"""
        with h5py.File(filename.format(n), 'r') as f:
            assert 'telemetry' in f
            mg = f['telemetry']
            for name in publisher.keys():
                assert name in mg
                g = mg[name]
                assert g['data'].shape[0] == (chunksize * nchunks)
                assert (g['mask'][...] > 0).sum() == (chunksize * nchunks)
    
    def publish_chunks(self, publisher, pub, chunksize, n=1):
        """Publish chunks."""
        for i in range(n):
            for j in range(chunksize):
                publisher.update()
                publisher.publish(pub, flags=zmq.NOBLOCK)
                time.sleep(0.01)
    
    def run_n_chunks(self, pipeline, publisher, pub, chunksize, n, groups=1):
        """Run a pipeline through n chunks"""
        with self.running_loop(pipeline):
            for i in range(groups):
                self.publish_chunks(publisher, pub, chunksize, n=n)
                # Pause and resume to roll over files.
                pipeline.pause()
                self.publish_chunks(publisher, pub, chunksize, n=n)
                pipeline.resume()
    
    def test_multiple_pipeline_writes(self, pipeline, filename, pub, Publisher, chunksize):
        """Test the multi-write ability of the pipeline."""
        self.run_n_chunks(pipeline, Publisher, pub, chunksize, 6, 2)
        for n in range(2):
            self.check_filename(filename, n, chunksize, 6, Publisher)
    
    def test_multiple_pipeline_writes_change_items(self, pipeline, filename, pub, Publisher, chunksize):
        """Test the multi-write ability of the pipeline."""
        with self.running_loop(pipeline):
            
            self.publish_chunks(Publisher, pub, chunksize, n=3)
            pipeline.pause()
            pipeline.resume()
            
            # Consume and remove a single item.
            Publisher.popitem()
            
            self.publish_chunks(Publisher, pub, chunksize, n=3)
            
        for n in range(2):
            self.check_filename(filename, n, chunksize, 3, Publisher)

def test_create_pipeline(address, context, chunksize, filename):
    """Test creating a pipeline."""
    ioloop = create_pipeline(address, context, chunksize, filename)
    print("Created")
    ioloop.cancel(timeout=0.1)
    print("Canceled")

def test_run_pipeline(pipeline, Publisher, pub, filename, chunksize):
    """Test running the pipeline."""
    with pipeline.running(timeout=0.1):
        print("Waiting on start.")
        pipeline.state.selected("RUN").wait(timeout=0.1)
        for i in range(chunksize * 2):
            if pipeline.record.pushed.is_set():
                break
            Publisher.update()
            Publisher.publish(pub, flags=zmq.NOBLOCK)
            time.sleep(0.1)
        print("Waiting on publishing events")
        pipeline.record.pushed.wait(timeout=3.0)
        pipeline.write.fired.wait(timeout=3.0)
        
    pipeline.state.selected("STOP").wait(timeout=1.0)
    print("Finished loop work.")
    print(pipeline.record.complete)
    for chunk in pipeline.record:
        print("{0}: {1}".format(chunk, pipeline.record[chunk].lastindex))
    assert pipeline.write.fired.is_set()
    assert pipeline.record.framecounter == len(Publisher) * (chunksize)
    with h5py.File(filename.format(0), 'r') as f:
        assert 'telemetry' in f
        mg = f['telemetry']
        for name in Publisher.keys():
            assert name in mg
            g = mg[name]
            assert g['data'].shape[0] == (chunksize)
            # Compute the last index
            print(np.arange(g['mask'].shape[0])[g['mask'][...] > 0])
            li = (np.arange(g['mask'].shape[0])[g['mask'][...] > 0]).max()
            print(g['mask'][...])
            assert li == g['mask'].shape[0] - 1
            np.testing.assert_allclose(g['data'][li], Publisher[name].array)
            
    
def test_final_write(pipeline, Publisher, pub, filename, chunksize):
    """Test running the pipeline."""
    with pipeline.running(timeout=0.1):
        pipeline.state.selected("RUN").wait(timeout=0.1)
        for i in range(chunksize * 2):
            if pipeline.record.pushed.is_set():
                break
            Publisher.update()
            Publisher.publish(pub, flags=zmq.NOBLOCK)
            time.sleep(0.1)
        pipeline.record.pushed.wait(timeout=3.0)
        pipeline.write.fired.wait(timeout=3.0)
        
        assert pipeline.record.pushed.is_set()
        pipeline.record.pushed.clear()
        
        for i in range(3):
            Publisher.update()
            Publisher.publish(pub, flags=zmq.NOBLOCK)
            time.sleep(0.1)
        pipeline.pause()
        pipeline.record.pushed.wait(timeout=3.0)
        
    pipeline.state.selected("STOP").wait(timeout=1.0)
    assert pipeline.state.selected("STOP").is_set()
    assert pipeline.write.fired.is_set()
    assert pipeline.record.framecounter == len(Publisher) * (chunksize + 3)
    with h5py.File(filename.format(0), 'r') as f:
        assert 'telemetry' in f
        mg = f['telemetry']
        for name in Publisher.keys():
            assert name in mg
            g = mg[name]
            assert g['data'].shape[0] == (chunksize * 2)
            assert np.max(g['mask']) == pipeline.record.framecount

    