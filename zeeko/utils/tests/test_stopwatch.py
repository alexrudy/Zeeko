import pytest
from pytest import approx
import time
import datetime as dt

from ..stopwatch import Stopwatch, _gettime

def test_stopwatch():
    """docstring for test_stopwatch"""
    s = Stopwatch()
    s.start()
    time.sleep(0.1)
    assert s.stop() == approx(0.1, rel=0.5)

def test_gettime():
    """Test gettime."""
    now = dt.datetime.now()
    gettime_now = dt.datetime.fromtimestamp(_gettime())
    assert gettime_now < now + dt.timedelta(seconds=10)
    assert now - dt.timedelta(seconds=10) < gettime_now
    