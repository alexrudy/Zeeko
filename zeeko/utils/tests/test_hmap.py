# -*- coding: utf-8 -*-
import pytest

from ..hmap import HashMap

@pytest.fixture(params=[0,1,5,9])
def n(request):
    """Number of items"""
    return request.param

@pytest.fixture
def items(n):
    """A list of strings."""
    return ["item{0:d}".format(i) for i in range(n)]


