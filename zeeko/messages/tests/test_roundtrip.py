# -*- coding: utf-8 -*-
import pytest
import numpy as np
from zmq.backend.cython.utils import Stopwatch

from ..receiver import ReceivedArray, Receiver
from ..publisher import PublishedArray, Publisher
from zeeko.conftest import assert_canrecv

@pytest.mark.xfail
def test_roundtrip_speed(push, pull):
    """Check roundtrip speed"""
    pub = Publisher()
    pub['array1'] = np.random.randn(200,200)
    rec = Receiver()
    n = 100
    w = Stopwatch()
    total = 0.0
    t = 0.0
    for i in range(n):
        w.start()
        pub.publish(push)
        pub['array1'] = np.random.randn(200, 200)
        assert_canrecv(pull)
        rec.receive(pull)
        total += rec['array1'].array[1,1]
        t += w.stop()
    
    total = 0.0
    to = 0.0
    for i in range(n):
        w.start()
        total += np.random.randn(200, 200)[1,1]
        to += w.stop()
    speed = n/float(t-to)
    
    assert speed > 0.005
