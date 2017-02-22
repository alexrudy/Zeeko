import pytest
from pytest import approx
import time

from ..stopwatch import Stopwatch

def test_stopwatch():
    """docstring for test_stopwatch"""
    s = Stopwatch()
    s.start()
    time.sleep(0.1)
    assert s.stop() == approx(0.1, rel=0.5)