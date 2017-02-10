# -*- coding: utf-8 -*-

import pytest
import time
import functools
from ..loop import IOLoop, DebugIOLoop
from .._state import StateError
from zeeko.conftest import assert_canrecv

@pytest.fixture
def loop(context):
    l = DebugIOLoop(context)
    yield l
    l.cancel()

def test_loop_attrs(loop, address, context):
    """Test loop attributes."""
    assert loop.context == context
    
    with pytest.raises(AttributeError):
        loop.context = 1
    
def test_loop_start_stop(loop):
    """Test loop start stop."""
    print(".start()")
    loop.start()
    print(".is_alive()")
    assert loop.is_alive()
    print(".stop()")
    loop.stop(timeout=0.1)
    print(".is_alive()")
    assert not loop.is_alive()
    
def test_loop_context(loop):
    """Test worker start stop."""
    print(".running()")
    with loop.running(timeout=0.1):
        print(".is_alive()")
        print(".running().__exit__()")
        assert loop.is_alive()
    print(".is_alive()")
    assert not loop.is_alive()

def test_loop_states(loop):
    """Test worker states."""
    assert loop.state.ensure("INIT")
    assert not loop.is_alive()
    loop.start()
    assert loop.is_alive()
    time.sleep(0.01)
    assert loop.state.ensure("RUN")
    loop.pause()
    time.sleep(0.01)
    assert loop.state.ensure("PAUSE")
    loop.start()
    time.sleep(0.01)
    assert loop.state.ensure("RUN")
    assert loop.is_alive()
    loop.stop(timeout=0.1)
    time.sleep(0.01)
    assert not loop.is_alive()
    assert loop.state.ensure("STOP")

def test_loop_multistop(loop):
    """Test loop multistop"""
    loop.start()
    print("First stop")
    loop.stop(timeout=1.0)
    
    with pytest.raises(StateError):
        print("Second stop")
        loop.stop(timeout=1.0)
    
def test_loop_throttle(loop):
    """Test the loop's throttle."""
    assert loop.get_timeout() == 100
