# -*- coding: utf-8 -*-
"""
A telemetry recording pipeline.
"""

import zmq

from ..cyloop.loop import IOLoop
from ..utils.msg import internal_address
from .handlers import RClient, WClient

def create_pipeline(address, context=None, chunksize=1024, filename="telemetry.{0:d}.hdf5", kind=zmq.SUB):
    """Create a telemetry writing pipeline."""
    context = context or zmq.Context.instance()
    ioloop = IOLoop(context)
    ioloop.add_worker()
    record = RClient.at_address(address, context, kind=kind, chunksize=chunksize)
    ioloop.attach(record, 0)
    write = WClient.from_recorder(filename, record)
    ioloop.attach(write, 1)
    return ioloop

    