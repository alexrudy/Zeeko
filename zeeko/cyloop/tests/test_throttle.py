import pytest
from pytest import approx
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

def test_activate_throttle():
    """Test an active throttle."""
    t = Throttle()
    t.period = 1.0
    assert t.active
    t._reset_at(0.0)
    t._start_at(0.0)
    t._mark_at(1.0)
    assert t._get_timeout_at(1.0) == 0
    
def test_active_throttle():
    """Test an active throttle."""
    t = Throttle()
    t.active = True
    t.period = 1.0
    t._reset_at(0.0)
    t._start_at(0.0)
    t._mark_at(0.5)
    assert t._get_timeout_at(0.5) == approx(500 * 0.2, rel=1e-2)
    t._start_at(0.6)
    t._mark_at(1.1)
    assert t._get_timeout_at(1.1) == approx(180, rel=1e-2)
    

def test_integrator_throttle():
    """Test the throttle integration over many iterations."""
    t = Throttle()
    t.active = True
    t.period = 1.0
    t._reset_at(0.0)
    to = t._get_timeout_at(0.0)
    ti = 0
    n = 1000
    for i in range(n):
        t._start_at(ti)
        ti += 0.5 + (to * 1e-3)
        t._mark_at(ti)
        to = t._get_timeout_at(ti)
    print(t._history[-10:])
    assert t._delay == approx(0.5, rel=1e-2)
    assert t._get_timeout_at(ti) == 499
    assert t._get_timeout_at(ti + 0.25) == 499 - 250
    