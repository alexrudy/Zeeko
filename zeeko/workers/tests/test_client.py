# -*- coding: utf-8 -*-

import pytest
import time
import functools
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
    
def test_client_run(context, address, pub, Publisher):
    """Test a client."""
    c = Client(context, address)
    c.start()
    try:
        time.sleep(0.01)
        Publisher.publish(pub)
        time.sleep(0.01)
    finally:
        c.stop()
    assert c.counter == 1
    assert len(c) == 3