# -*- coding: utf-8 -*-
import numpy as np
import pytest

@pytest.fixture
def shape():
    """An array shape."""
    return (100, 100)
    
@pytest.fixture
def name():
    """Array name"""
    return "test_array"

@pytest.fixture(params=(float, int))
def dtype(request):
    """docstring for dtype"""
    return np.dtype(request.param)

@pytest.fixture
def array(shape, dtype):
    """An array to send over the wire"""
    return (np.random.rand(*shape)).astype(dtype)
