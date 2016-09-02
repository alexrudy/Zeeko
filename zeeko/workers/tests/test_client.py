# -*- coding: utf-8 -*-

import pytest
import time
import functools
import zmq
from ..client import Client
from zeeko.conftest import assert_canrecv

def test_client_attributes(context, address):
    """Test client attributes defaults."""
    c = Client(context, address)
    assert c.counter == 0
    assert c.delay == 0
    assert c.maxlag == 10.0
    c.maxlag = 20
    assert c.maxlag == 20.0
    
def test_client_run(context, address, push, Publisher):
    """Test a client."""
    c = Client(context, address, zmq.PULL)
    c.start()
    try:
        time.sleep(0.1)
        Publisher.publish(push)
        Publisher.publish(push)
        Publisher.publish(push)
        time.sleep(0.1)
    finally:
        c.stop()
    assert c.counter == 1
    assert len(c) == 3
