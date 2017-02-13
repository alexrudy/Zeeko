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
    return PipelineIOLoop(address, context, chunksize, filename, kind)

class PipelineIOLoop(IOLoop):
    """Expose pipeline parts at IOLoop top level."""
    def __init__(self, address, context=None, chunksize=1024, filename="telemetry.{0:d}.hdf5", kind=zmq.SUB):
        context = context or zmq.Context.instance()
        super(PipelineIOLoop, self).__init__(context)
        self.add_worker()
        self.record = RClient.at_address(address, context, kind=kind, chunksize=chunksize)
        self.attach(self.record, 0)
        self.write = WClient.from_recorder(filename, self.record)
        self.attach(self.write, 1)
        
    
        