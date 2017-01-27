import pytest
import numpy as np
import zmq

@pytest.fixture
def n():
    """Number of arrays"""
    return 3

@pytest.fixture
def Publisher(name, n, shape):
    """Make an array publisher."""
    from ...messages.publisher import Publisher as _Publisher
    publishers = [("{:s}{:d}".format(name, i), np.random.randn(*shape)) for i in range(n)]
    p = _Publisher([])
    for name_, array_ in publishers:
        p[name_] = array_
    return p

@pytest.fixture
def Receiver():
    """Receiver"""
    from ...messages.receiver import Receiver as _Receiver
    return _Receiver()