import pytest
from ..statemachine import StateMachine, StateError

def test_state_init():
    """Initializer"""
    sm = StateMachine()
    assert sm.name == "INIT"
    assert repr(sm) == "StateMachine('INIT')"
    sm = StateMachine("RUN")
    assert sm.name == "RUN"
    assert repr(sm) == "StateMachine('RUN')"
    
def test_state_modify():
    """Modify state."""
    sm = StateMachine()
    assert sm.name == "INIT"
    sm._set('RUN')
    assert sm.name == "RUN"
    assert sm._check("RUN")
    with pytest.raises(StateError):
        sm.guard("RUN")
    sm.guard("STOP")
    sm.ensure("RUN")
    with pytest.raises(StateError):
        sm.ensure("STOP")

def test_state_events():
    """Test state events."""
    sm = StateMachine()
    assert sm.selected("INIT").is_set()
    assert not sm.deselected("INIT").is_set()
    for state in sm:
        assert not sm.deselected(state).is_set()
        assert (not sm.selected(state).is_set()) or state == "INIT"
    sm._set("RUN")
    assert sm.deselected("INIT").is_set()
    assert sm.selected("RUN").is_set()
    assert not sm.deselected("RUN").is_set()
    assert not sm.selected("INIT").is_set()
    