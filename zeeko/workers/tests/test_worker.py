# -*- coding: utf-8 -*-

import pytest
import time
import functools
from ..base import Worker
from zeeko.conftest import assert_canrecv

def test_worker_attrs(address, context):
    """Test worker attributes."""
    w = Worker(context, address)
    assert w.context == context
    
    with pytest.raises(AttributeError):
        w.context = 1
    
    assert w.address == address
    with pytest.raises(AttributeError):
        w.address = "something-else"
    
def test_worker_start_stop(address, context):
    """Test worker start stop."""
    w = Worker(context, address)
    w.start()
    assert w.is_alive()
    w.stop()
    assert not w.is_alive()
    
def test_worker_context(address, context):
    """Test worker start stop."""
    w = Worker(context, address)
    with w.running():
        assert w.is_alive()
    assert not w.is_alive()

def test_worker_states(address, context):
    """Test worker states."""
    w = Worker(context, address)
    assert w.state == "INIT"
    assert not w.is_alive()
    w.start()
    assert w.is_alive()
    time.sleep(0.01)
    assert w.state == "RUN"
    w.pause()
    time.sleep(0.01)
    assert w.state == "PAUSE"
    w.start()
    time.sleep(0.01)
    assert w.state == "RUN"
    assert w.is_alive()
    w.stop()
    time.sleep(0.01)
    assert not w.is_alive()
    assert w.state == "STOP"


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

def test_worker_py_hooks(address, context):
    """Test worker python hooks."""
    w = WorkerWithPyHook(context, address)
    assert w.state == "INIT"
    assert w.hooks_run == []
    w.pause()
    time.sleep(0.01)
    assert "_py_pre_work" in w.hooks_run
    assert len(w.hooks_run) == 1
    
    w.start()
    time.sleep(0.01)
    assert "_py_pre_run" in w.hooks_run
    
    w.pause()
    time.sleep(0.01)
    assert "_py_post_run" in w.hooks_run
    
    w.stop()
    time.sleep(0.01)
    assert "_py_post_work" in w.hooks_run
    assert not w.is_alive()

def test_worker_multistop(address, context):
    """Test worker multistop"""
    w = Worker(context, address)
    w.start()
    w.stop()
    
    with pytest.raises(ValueError):
        w.stop()
    

