# -*- coding: utf-8 -*-
import pytest

from .condition import Event


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
    evt2 = evt.copy()
    assert not evt2.is_set()
    evt.set()
    assert evt2.is_set()