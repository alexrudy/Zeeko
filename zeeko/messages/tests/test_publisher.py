# -*- coding: utf-8 -*-
"""
Test the publisher class
"""

import pytest
import numpy as np

from ..publisher import PublishedArray

def test_publisher_init():
    """PublishedArray object __init__"""
    p = PublishedArray("array", np.ones((10,)))
    
def test_publisher_update(req, rep):
    """Test update array items."""
    pub = PublishedArray("array", np.ones((10,)))
    
    pub.array = np.ones((20,))
    assert pub.array.shape == (20,)
    
    pub.name = "Other Array"
    assert pub.name == "Other Array"