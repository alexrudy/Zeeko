import pytest
import numpy as np
import zmq

from ..recorder import Recorder

def test_recorder_construction(context):
    """Test construction"""
    r = Recorder(None, "a", "b", 1024)
    r = Recorder(context, "a", "b", 1024)
    with pytest.raises(ValueError):
        r = Recorder(None, "a", "b", -1)
    with pytest.raises(ValueError):
        r = Recorder(True, "a", "b", 1024)
    r = Recorder(context, "", "", 1024)

