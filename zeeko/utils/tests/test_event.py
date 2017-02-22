# -*- coding: utf-8 -*-
import pytest
import time
from ..stopwatch import Stopwatch
from ..condition import Event, TimeoutError


def test_event_init():
    """Test event init"""
    evt = Event()
    
def test_event_signal():
    """Test the signal mechanism."""
    evt = Event()
    assert not evt.is_set()
    evt.set()
    assert evt.is_set()

def test_event_copy():
    """Test copy event."""
    evt = Event()
    assert evt._reference_count == 0
    evt2 = evt.copy()
    assert not evt2.is_set()
    evt.set()
    assert evt2.is_set()
    assert evt._reference_count == 1
    assert evt2._reference_count == 1
    
def test_event_wait():
    """Test waiting for an event."""
    evt = Event()
    assert not evt.is_set()
    s = Stopwatch()
    s.start()
    evt.wait(timeout=1.5)
    duration = s.stop()
    assert 2.0 > duration >= 0.1
    assert not evt.is_set()
    