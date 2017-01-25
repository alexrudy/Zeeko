import pytest

from ..throttle import Throttle

def test_throttle_init():
    """Test the throttle."""
    t = Throttle()
    assert t.period == 0.01
    assert t.frequency == 100.0
    assert t.gain == 0.2
    assert t.leak == 0.9999
    assert t.c == 1e-4
    assert t.timeout == 0.01
    assert not t.active
    
def test_inactive_throttle():
    """Test an inactive throttle."""
    t = Throttle()
    assert not t.active
    assert t._get_timeout_at(0.0) == 10

def test_active_throttle():
    """Test an active throttle."""
    t = Throttle()
    t.active = True
    t.period = 1.0
    t._reset_at(0.0)
    t._mark_at(1.0)
    assert t._get_timeout_at(1.0) == 199
    
def test_integration_throttle():
    """Test throttle with integration."""
    t = Throttle()
    t.active = True
    t.period = 1.0
    t.c = 0.1
    t._reset_at(0.0)
    t._mark_at(0.5)
    assert t._get_timeout_at(0.5) == 180
    
    t._mark_at(1.5)
    assert t._get_timeout_at(2.0) == 252

    