# This file is used to configure the behavior of pytest when using the Astropy
# test infrastructure.


import zmq
import functools
import threading
import warnings
import struct
import numpy as np
import pytest

from astropy.version import version as astropy_version

if astropy_version < "3.0":
    # With older versions of Astropy, we actually need to import the pytest
    # plugins themselves in order to make them discoverable by pytest.
    from astropy.tests.pytest_plugins import *
else:
    # As of Astropy 3.0, the pytest plugins provided by Astropy are
    # automatically made available when Astropy is installed. This means it's
    # not necessary to import them here, but we still need to import global
    # variables that are used for configuration.
    from astropy.tests.plugins.display import PYTEST_HEADER_MODULES, TESTED_VERSIONS

from astropy.tests.helper import enable_deprecations_as_exceptions

## Uncomment the following line to treat all DeprecationWarnings as
## exceptions. For Astropy v2.0 or later, there are 2 additional keywords,
## as follow (although default should work for most cases).
## To ignore some packages that produce deprecation warnings on import
## (in addition to 'compiler', 'scipy', 'pygments', 'ipykernel', and
## 'setuptools'), add:
##     modules_to_ignore_on_import=['module_1', 'module_2']
## To ignore some specific deprecation warning messages for Python version
## MAJOR.MINOR or later, add:
##     warnings_to_ignore_by_pyver={(MAJOR, MINOR): ['Message to ignore']}
# enable_deprecations_as_exceptions()

## Uncomment and customize the following lines to add/remove entries from
## the list of packages for which version numbers are displayed when running
## the tests. Making it pass for KeyError is essential in some cases when
## the package uses other astropy affiliated packages.
try:
    PYTEST_HEADER_MODULES["astropy"] = "astropy"
    PYTEST_HEADER_MODULES["zmq"] = "zmq"
    PYTEST_HEADER_MODULES["h5py"] = "h5py"
    PYTEST_HEADER_MODULES.pop("Scipy", None)
    PYTEST_HEADER_MODULES.pop("Matplotlib", None)
    PYTEST_HEADER_MODULES.pop("Pandas", None)
except NameError:  # needed to support Astropy < 1.0
    pass


## Uncomment the following lines to display the version number of the
## package rather than the version number of Astropy in the top line when
## running the tests.
import os

#
## This is to figure out the package version, rather than
## using Astropy's
try:
    from .version import version
except ImportError:
    version = "dev"
    #
    # try:
    packagename = os.path.basename(os.path.dirname(__file__))
    TESTED_VERSIONS[packagename] = version
except NameError:  # Needed to support Astropy <= 1.0.0
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

    if (not _pytest_get_option(config, "capturelog", default=True)) or (
        _pytest_get_option(config, "capture", default="no") == "no"
    ):
        try:
            import lumberjack

            lumberjack.setup_logging("", mode="stream", level=1)
            lumberjack.setup_warnings_logger("")
        except:
            pass
    else:
        try:
            import lumberjack

            lumberjack.setup_logging("", mode="none", level=1)
            lumberjack.setup_warnings_logger("")
        except:
            pass


## FIXTURES START HERE
# The code below sets up useful ZMQ fixtures for various tests.

# def pytest_report_header(config):
#     import astropy.tests.pytest_plugins as astropy_pytest_plugins

#     s = astropy_pytest_plugins.pytest_report_header(config)
#     s += "libzmq: {0:s}\n".format(zmq.zmq_version())
#     return s


def try_term(context):
    """Try context term."""
    t = threading.Thread(target=context.term)
    t.daemon = True
    t.start()
    t.join(timeout=2)
    if t.is_alive():
        zmq.sugar.context.Context._instance = None
        raise RuntimeError("ZMQ Context failed to terminate.")


def check_garbage(fail=True):
    """Check for garbage."""
    # Check for cycles.
    import gc

    for i in range(4):
        gc.collect()
    if len(gc.garbage):
        warnings.warn("There are {0:d} pieces of garbage".format(len(gc.garbage)))
        for garbage in gc.garbage:
            warnings.warn("Garbage: {0!r}".format(garbage))
        if fail:
            raise RuntimeError("Garbage remains!")


def check_threads(ignore_daemons=True):
    """Check for dangling threads."""
    # Check for zombie threads.
    import threading, time

    if threading.active_count() > 1:
        time.sleep(0.1)  # Allow zombies to die!
    count = 0
    for thread in threading.enumerate():
        if not thread.isAlive():
            continue
        if ignore_daemons and getattr(thread, "daemon", False):
            continue
        if thread not in check_threads.seen:
            count += 1
            warnings.warn("Zombie thread: {0!r}".format(thread))
            check_threads.seen.add(thread)

    # If there are new, non-daemon threads, cause an error.
    if count > 1:
        threads_info = []
        for thread in threading.enumerate():
            # referers = ",".join(type(r).__name__ for r in gc.get_referrers(thread))
            referers = "\n   ".join(repr(r) for r in gc.get_referrers(thread))
            threads_info.append("{0}:\n   {1}".format(repr(thread), referers))
        threads_str = "\n".join(threads_info)
        raise ValueError(
            "{0:d} {3:s}thread{1:s} left alive!\n{2!s}".format(
                count - 1,
                "s" if (count - 1) > 1 else "",
                threads_str,
                "non-deamon " if ignore_daemons else "",
            )
        )


check_threads.seen = set()


class Socket(zmq.Socket):
    def can_recv(self):
        """Return self, but check that we can recv."""
        assert_canrecv(self)
        return self

    def recv(self, *args, **kwargs):
        """Do everything for receive, but possibly timeout."""
        assert_canrecv(self, kwargs.pop("timeout", 5000))
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
    ctx = Context(io_threads=0)
    t = threading.Timer(10.0, try_term, args=(ctx,))
    t.start()
    yield ctx
    t.cancel()
    try_term(ctx)
    check_threads()
    check_garbage()


def socket_pair(context, left, right):
    """Given a context, make a socket."""
    lsocket = context.socket(left)
    rsocket = context.socket(right)
    yield (lsocket, rsocket)
    rsocket.close()
    lsocket.close()


@pytest.fixture
def address():
    """The ZMQ address for connections."""
    return "inproc://test"


@pytest.fixture
def address2():
    """The ZMQ address for connections."""
    return "inproc://test-2"


@pytest.fixture
def reqrep(context):
    """Return a bound pair."""
    for sockets in socket_pair(context, zmq.REQ, zmq.REP):
        yield sockets


@pytest.fixture
def req(reqrep, address, rep):
    """The REQ socket."""
    req, rep = reqrep
    req.connect(address)
    return req


@pytest.fixture
def rep(reqrep, address):
    """The REQ socket."""
    req, rep = reqrep
    rep.bind(address)
    return rep


@pytest.fixture
def pushpull(context):
    """Return a bound pair."""
    for sockets in socket_pair(context, zmq.PUSH, zmq.PULL):
        yield sockets


@pytest.fixture
def push(pushpull, address):
    """The reply socket."""
    push, pull = pushpull
    push.bind(address)
    return push


@pytest.fixture
def pull(pushpull, address, push):
    """The reply socket."""
    push, pull = pushpull
    pull.connect(address)
    return pull


@pytest.fixture
def subpub(context):
    """Return a bound pair."""
    for sockets in socket_pair(context, zmq.SUB, zmq.PUB):
        yield sockets


@pytest.fixture
def pub(subpub, address):
    """The reply socket."""
    sub, pub = subpub
    pub.bind(address)
    return pub


@pytest.fixture
def sub(subpub, address, pub):
    """The SUB socket."""
    sub, pub = subpub
    sub.connect(address)
    return sub


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


@pytest.fixture
def arrays(name, n, shape):
    """A fixture of named arrays to publish."""
    return [("{0:s}{1:d}".format(name, i), np.random.randn(*shape)) for i in range(n)]


def assert_canrecv(socket, timeout=100):
    """Check if a socket is ready to receive."""
    if not socket.poll(timeout=timeout):
        pytest.fail("ZMQ Socket {0!r} was not ready to receive.".format(socket))


def recv(socket, method="", **kwargs):
    """Receive, via poll, in such a way as to fail when no message is ready."""
    assert_canrecv(socket, kwargs.pop("timeout", 5000))
    recv = getattr(socket, "recv_{0:s}".format(method)) if method else socket.recv
    return recv(**kwargs)


@pytest.fixture
def ioloop(context):
    """A cython I/O loop."""
    from .cyloop.loop import DebugIOLoop

    loop = DebugIOLoop(context)
    yield loop
    loop.cancel()


@pytest.fixture
def n():
    """Number of arrays"""
    return 3


@pytest.fixture
def framecount():
    """Return the framecounter value."""
    return 2 ** 22 + 35


from .messages import Publisher as _Publisher


class MockPublisher(_Publisher):
    """docstring for MockPublisher"""

    def update(self):
        """Update all keys to this publisher."""
        for key in self.keys():
            array = self[key]
            array.array[...] = np.random.randn(*array.shape)


@pytest.fixture
def Publisher(name, n, shape, framecount):
    """Make an array publisher."""
    p = MockPublisher([])
    p.framecount = framecount
    for i in range(n):
        p["{0:s}{1:d}".format(name, i)] = np.random.randn(*shape)
    return p


@pytest.fixture
def Receiver():
    """Receiver"""
    from .messages import Receiver as _Receiver

    return _Receiver()
