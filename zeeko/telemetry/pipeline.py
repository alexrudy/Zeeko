# -*- coding: utf-8 -*-
"""
A telemetry recording pipeline.
"""

import zmq

from ..cyloop.loop import IOLoop
from ..utils.msg import internal_address
from .handlers import Telemetry, TelemetryWriter

__all__ = ['PipelineIOLoop', 'create_pipeline']

def create_pipeline(address, context=None, chunksize=1024, filename="telemetry.{0:d}.hdf5", kind=zmq.SUB):
    """Create a telemetry writing pipeline."""
    return PipelineIOLoop(address, context, chunksize, filename, kind)

class PipelineIOLoop(IOLoop):
    """Expose pipeline parts at IOLoop top level."""
    def __init__(self, address, context=None, chunksize=1024, filename="telemetry.{0:d}.hdf5", kind=zmq.SUB):
        context = context or zmq.Context.instance()
        super(PipelineIOLoop, self).__init__(context)
        self.add_worker()
        self.record = Telemetry.at_address(address, context, kind=kind, chunksize=chunksize, filename=filename)
        self.attach(self.record, 0)
        self.attach(self.record.writer, 1)
        self.write = self.record.writer
        
    
        