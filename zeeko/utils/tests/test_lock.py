# -*- coding: utf-8 -*-
import pytest

from ..lock import Lock


def test_lock_init():
    """Test event init"""
    lck = Lock()
    
def test_lock_acquire_release():
    """Test the lock mechanism."""
    lck = Lock()
    assert not lck.locked
    lck.acquire()
    assert lck.locked
    lck.release()

def test_lock_context():
    """Test the lock context."""
    lck = Lock()
    assert not lck.locked
    with lck:
        assert lck.locked
    assert not lck.locked

def test_lock_copy():
    """Test copy lock."""
    lck = Lock()
    lck2 = lck.copy()
    assert not lck2.locked
    lck.acquire()
    assert lck2.locked
    lck2.release()
    assert not lck.locked
    