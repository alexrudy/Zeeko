# -*- coding: utf-8 -*-

import pytest
import time
import functools
from ..base import Worker
from zeeko.conftest import assert_canrecv

@pytest.fixture
def worker(address, context):
    w = Worker(context, address)
    yield w
    if w.is_alive():
        w.stop()

def test_worker_attrs(worker, address, context):
    """Test worker attributes."""
    assert worker.context == context
    
    with pytest.raises(AttributeError):
        worker.context = 1
    
    assert worker.address == address
    with pytest.raises(AttributeError):
        worker.address = "something-else"
    
def test_worker_start_stop(worker):
    """Test worker start stop."""
    worker.start()
    assert worker.is_alive()
    worker.stop()
    assert not worker.is_alive()
    
def test_worker_context(worker):
    """Test worker start stop."""
    with worker.running():
        assert worker.is_alive()
    assert not worker.is_alive()

def test_worker_states(worker):
    """Test worker states."""
    assert worker.state == "INIT"
    assert not worker.is_alive()
    worker.start()
    assert worker.is_alive()
    time.sleep(0.01)
    assert worker.state == "RUN"
    worker.pause()
    time.sleep(0.01)
    assert worker.state == "PAUSE"
    worker.start()
    time.sleep(0.01)
    assert worker.state == "RUN"
    assert worker.is_alive()
    worker.stop()
    time.sleep(0.01)
    assert not worker.is_alive()
    assert worker.state == "STOP"


def worker_py_hook(f):
    
    @functools.wraps(f)
    def worker_wrapped_hook(self, *args, **kwargs):
        self.hooks_run.append(f.__name__)
        return f(self, *args, **kwargs)
    
    return worker_wrapped_hook
    

class WorkerWithPyHook(Worker):
    """Worker with py-hooks."""
    def __init__(self, *args):
        super(WorkerWithPyHook, self).__init__(*args)
        self.hooks_run = []
    
    @worker_py_hook
    def _py_pre_run(self):
        pass
    
    @worker_py_hook
    def _py_post_run(self):
        pass
    
    @worker_py_hook
    def _py_pre_work(self):
        pass
        
    @worker_py_hook
    def _py_post_work(self):
        pass
        
@pytest.fixture
def hooked_worker(address, context):
    """A worker with hooks."""
    w = WorkerWithPyHook(context, address)
    yield w
    if w.is_alive():
        w.stop()

def test_worker_py_hooks(hooked_worker):
    """Test worker python hooks."""
    assert hooked_worker.state == "INIT"
    assert hooked_worker.hooks_run == []
    hooked_worker.pause()
    time.sleep(0.01)
    assert "_py_pre_work" in hooked_worker.hooks_run
    assert len(hooked_worker.hooks_run) == 1
    
    hooked_worker.start()
    time.sleep(0.01)
    assert "_py_pre_run" in hooked_worker.hooks_run
    
    hooked_worker.pause()
    time.sleep(0.01)
    assert "_py_post_run" in hooked_worker.hooks_run
    
    hooked_worker.stop()
    time.sleep(0.01)
    assert "_py_post_work" in hooked_worker.hooks_run
    assert not hooked_worker.is_alive()

def test_worker_multistop(worker):
    """Test worker multistop"""
    worker.start()
    worker.stop()
    
    with pytest.raises(ValueError):
        worker.stop()
    

