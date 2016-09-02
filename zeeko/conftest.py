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
import functools
import threading
import struct
import numpy as np

def pytest_report_header(config):
    import astropy.tests.pytest_plugins as astropy_pytest_plugins
    s = astropy_pytest_plugins.pytest_report_header(config)
    s += 'libzmq: {:s}\n'.format(zmq.zmq_version())
    return s

def try_term(context):
    """Try context term."""
    t = threading.Thread(target=context.term)
    t.daemon = True
    t.start()
    t.join(timeout=2)
    if t.is_alive():
        zmq.sugar.context.Context._instance = None
        raise RuntimeError("ZMQ Context failed to terminate.")
    

class Socket(zmq.Socket):
    
    def recv(self, *args, **kwargs):
        """Do everything for receive, but possibly timeout."""
        assert_canrecv(self, kwargs.pop('timeout', 5000))
        return super(Socket, self).recv(*args, **kwargs)
        
    def recv_struct(self, fmt, *args, **kwargs):
        """Receive and unpack a struct message."""
        msg = self.recv(*args, **kwargs)
        return struct.unpack(fmt, msg)
        
class Context(zmq.Context):
    _socket_class = Socket
        

@pytest.fixture
def context(request):
    """The ZMQ context."""
    ctx = Context()
    request.addfinalizer(functools.partial(try_term, ctx))
    return ctx
    
def socket(request, context, kind, address, bind=False):
    """Given a context, make a socket."""
    socket = context.socket(kind)
    if bind:
        socket.bind(address)
    else:
        socket.connect(address)
    yield socket
    socket.close(linger=0)
    # request.addfinalizer(functools.partial(socket.close, linger=0))

@pytest.fixture
def address():
    """The ZMQ address for connections."""
    return "inproc://test"

@pytest.fixture
def req(request, context, address):
    """The REQ socket."""
    for s in socket(request, context, zmq.REQ, address):
        yield s
    

@pytest.fixture
def rep(request, context, address):
    """The reply socket."""
    for s in socket(request, context, zmq.REP, address, bind=True):
        yield s

@pytest.fixture
def push(request, context, address):
    """The reply socket."""
    for s in socket(request, context, zmq.PUSH, address):
        yield s

@pytest.fixture
def pull(request, context, address):
    """The reply socket."""
    for s in socket(request, context, zmq.PULL, address, bind=True):
        yield s
    
@pytest.fixture
def pub(request, context, address):
    """The reply socket."""
    for s in socket(request, context, zmq.PUB, address, bind=True):
        yield s

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
    """An array dtype for testing."""
    return np.dtype(request.param)

@pytest.fixture
def array(shape, dtype):
    """An array to send over the wire"""
    return (np.random.rand(*shape)).astype(dtype)

def assert_canrecv(socket, timeout=5000):
    """Check if a socket is ready to receive."""
    if not socket.poll(timeout=5000):
        pytest.fail("ZMQ Socket {!r} was not ready to receive.".format(socket))
    
def recv(socket, method='', **kwargs):
    """Receive, via poll, in such a way as to fail when no message is ready."""
    assert_canrecv(socket, kwargs.pop('timeout', 5000))
    recv = getattr(socket, 'recv_{:s}'.format(method)) if method else socket.recv
    return recv(**kwargs)
    

    