# Licensed under a 3-clause BSD style license - see LICENSE.rst

"""
Zeeko is a ZeroMQ messaging protocol for numpy arrays.
"""

# Packages may add whatever they like to this file, but
# should keep this content at the top.
# ----------------------------------------------------------------------------
from ._astropy_init import *  # noqa

# ----------------------------------------------------------------------------

# Enforce Python version check during package import.
# This is the same check as the one at the top of setup.py
import sys
from distutils.version import LooseVersion

__minimum_python_version__ = "3.6"

__all__ = ["ZEEKO_PROTOCOL_VERSION"]


# This integer shall be incremented when the format of the ZEEKO protocol changes.
ZEEKO_PROTOCOL_VERSION = 1


class UnsupportedPythonError(Exception):
    pass


if LooseVersion(sys.version) < LooseVersion(__minimum_python_version__):
    raise UnsupportedPythonError(
        "packagename does not support Python < {}".format(__minimum_python_version__)
    )

if not _ASTROPY_SETUP_:  # noqa
    from .zmq_check import check_zeromq

    check_zeromq()
