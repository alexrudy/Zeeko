import pytest
from pytest import approx

from ..snail import Snail
from zeeko.conftest import assert_canrecv

def test_snail_attributes():
    """Test snail attributes."""
    s = Snail()
    assert s.nlate == 0
    assert s.deaths == 0
    assert s.nlate_max == -1
    assert not s.active
    assert s.delay_max == 0.0
    assert s.delay == 0.0
    
@pytest.fixture
def snail():
    """Snail with some default settings."""
    s = Snail()
    s.nlate_max = 2
    s.delay_max = 2.0
    return s
    
def test_snail_check(snail, push, pull):
    """Test check snail."""
    snail.check(push, 1.0, 0.0)
    assert snail.delay == approx(1.0)
    assert snail.nlate == 0
    snail.check(push, 3.0, 0.0)
    assert snail.delay == approx(3.0)
    assert snail.nlate == 1
    snail.check(push, 3.0, 0.0)
    assert snail.delay == approx(3.0)
    assert snail.nlate == 2
    snail.check(push, 3.0, 0.0)
    assert snail.delay == approx(3.0)
    assert snail.deaths == 1
    assert pull.recv_struct('i') == (2,)
    