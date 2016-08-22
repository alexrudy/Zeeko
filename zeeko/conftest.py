from __future__ import absolute_import

# this contains imports plugins that configure py.test for astropy tests.
# by importing them here in conftest.py they are discoverable by py.test
# no matter how it is invoked within the source tree.
from astropy.tests.pytest_plugins import *

## Uncomment the following line to treat all DeprecationWarnings as
## exceptions
# enable_deprecations_as_exceptions()

## Uncomment and customize the following lines to add/remove entries
## from the list of packages for which version numbers are displayed
## when running the tests
try:
    PYTEST_HEADER_MODULES['astropy'] = 'astropy'
    PYTEST_HEADER_MODULES['zmq'] = 'zmq'
    PYTEST_HEADER_MODULES.pop('h5py', None)
    PYTEST_HEADER_MODULES.pop('Scipy', None)
    PYTEST_HEADER_MODULES.pop('Matplotlib', None)
    PYTEST_HEADER_MODULES.pop('Pandas', None)
except NameError:  # needed to support Astropy < 1.0
    pass

## Uncomment the following lines to display the version number of the
## package rather than the version number of Astropy in the top line when
## running the tests.
import os

## This is to figure out the affiliated package version, rather than
## using Astropy's
from . import version
#
try:
    packagename = os.path.basename(os.path.dirname(__file__))
    TESTED_VERSIONS[packagename] = version.version
except NameError:   # Needed to support Astropy <= 1.0.0
    pass

def _pytest_get_option(config, name, default):
    """Get pytest options in a version independent way, with allowed defaults."""
    
    try:
        value = config.getoption(name, default=default)
    except Exception:
        try:
            value = config.getvalue(name)
        except Exception:
            return default
    return value
    

def pytest_configure(config):
    """Activate log capturing if appropriate."""

    if (not _pytest_get_option(config, 'capturelog', default=True)) or (_pytest_get_option(config, 'capture', default="no") == "no"):
        try:
            import lumberjack
            lumberjack.setup_logging("", mode='stream', level=1)
            lumberjack.setup_warnings_logger("")
        except:
            pass
    else:
        try:
            import lumberjack
            lumberjack.setup_logging("", mode='none', level=1)
            lumberjack.setup_warnings_logger("")
        except:
            pass
            

## FIXTURES START HERE
# The code below sets up useful ZMQ fixtures for various tests. 

import zmq

@pytest.fixture
def context(request):
    """The ZMQ context."""
    ctx = zmq.Context()
    request.addfinalizer(ctx.destroy)
    return ctx

@pytest.fixture
def address():
    """The ZMQ address for connections."""
    return "inproc://test"

@pytest.fixture
def req(context, address):
    """The REQ socket."""
    socket = context.socket(zmq.REQ)
    socket.connect(address)
    return socket

@pytest.fixture
def rep(context, address):
    """The reply socket."""
    socket = context.socket(zmq.REP)
    socket.bind(address)
    return socket