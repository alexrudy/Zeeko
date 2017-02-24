# Licensed under a 3-clause BSD style license - see LICENSE.rst

"""
Zeeko is a ZeroMQ messaging protocol for numpy arrays.
"""

# Affiliated packages may add whatever they like to this file, but
# should keep this content at the top.
# ----------------------------------------------------------------------------
from ._astropy_init import *
# ----------------------------------------------------------------------------

# This integer shall be incremented when the format of the ZEEKO protocol changes.
ZEEKO_PROTOCOL_VERSION = 1

# For egg_info test builds to pass, put package imports here.
if not _ASTROPY_SETUP_:
    from .zmq_check import check_zeromq
    check_zeromq()