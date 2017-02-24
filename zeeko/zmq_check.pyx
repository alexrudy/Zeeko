#cython: embedsignature=True

import zmq
cimport zmq.backend.cython.libzmq as libzmq
from zmq.backend.cython.socket cimport Socket
from libc.stdint cimport uint64_t

class ZMQLinkingError(Exception):
    pass

def check_zeromq():
    """Check that zeromq is correctly installed."""
    cdef void * handle
    cdef uint64_t affinity
    cdef size_t sz = sizeof(uint64_t)
    cdef int rc, errno
    with zmq.Context.instance() as ctx:
        with ctx.socket(zmq.REQ) as socket:
            handle = (<Socket>socket).handle
            rc = libzmq.zmq_getsockopt(handle, libzmq.ZMQ_AFFINITY, &affinity, &sz)
            if rc != 0:
                errno = libzmq.zmq_errno()
                if errno == libzmq.EINVAL:
                    raise ZMQLinkingError("Something has gone wrong with ZMQ Linking")
                raise zmq.ZMQError()

    