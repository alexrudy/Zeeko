# -*- coding: utf-8 -*-

import pytest
import time
import functools
from ..loop import IOLoop
from zeeko.conftest import assert_canrecv

@pytest.fixture
def loop(context):
    l = IOLoop(context)
    yield l
    l.cancel()

def test_loop_attrs(loop, address, context):
    """Test loop attributes."""
    assert loop.context == context
    
    with pytest.raises(AttributeError):
        loop.context = 1
    
def test_loop_start_stop(loop):
    """Test loop start stop."""
    loop.start()
    assert loop.is_alive()
    loop.stop()
    assert not loop.is_alive()
    
def test_loop_context(loop):
    """Test worker start stop."""
    with loop.running():
        assert loop.is_alive()
    assert not loop.is_alive()

def test_loop_states(loop):
    """Test worker states."""
    assert loop.state == "INIT"
    assert not loop.is_alive()
    loop.start()
    assert loop.is_alive()
    time.sleep(0.01)
    assert loop.state == "RUN"
    loop.pause()
    time.sleep(0.01)
    assert loop.state == "PAUSE"
    loop.start()
    time.sleep(0.01)
    assert loop.state == "RUN"
    assert loop.is_alive()
    loop.stop()
    time.sleep(0.01)
    assert not loop.is_alive()
    assert loop.state == "STOP"

def test_loop_multistop(loop):
    """Test loop multistop"""
    loop.start()
    loop.stop()
    
    with pytest.raises(ValueError):
        loop.stop()
    

