# -*- coding: utf-8 -*-
"""
A telemetry recording pipeline.
"""

import zmq
import collections

from .recorder import Recorder
from .writer import Writer

class Pipeline(object):
    """A telemetry recording pipeline."""
    def __init__(self, address, filename, ctx=None, chunksize=1024):
        super(Pipeline, self).__init__()
        self.address = address
        self.filename = filename
        self.ctx = ctx or zmq.Context.instance()
        self._writer_address = "inproc://{:s}-writer".format(hex(id(self)))
        
        self.recorder = Recorder(self.ctx, self.address, self._writer_address, chunksize)
        self.writer = Writer(self.ctx, self._writer_address, self.filename)
        self._events = collections.deque()
        self._notify = self.ctx.socket(zmq.PULL)
        self._notify.connect(self.writer.notify_address)
    
    def _get_events(self):
        """Socket for notifications."""
        while self._notify.poll(timeout=100):
            self._events.append(self._notify.recv_json())
    
    def event(self):
        """Retrun the latest event."""
        self._get_events()
        if self._events:
            return self._events.popleft()
    
    @property
    def delay(self):
        """Running message delay."""
        return self.recorder.delay
    
    @property
    def counter(self):
        """Return a counter of received frames."""
        return self.recorder.counter
    
    def start(self):
        """Start the pipeline."""
        self.recorder.start()
        self.writer.start()
        
    def stop(self):
        """Stop the pipeline. This is a hard stop."""
        self.recorder.stop()
        self.writer.stop()
    
    def pause(self):
        """Pause the pipeline."""
        self.recorder.pause()
    
    def finish(self, timeout=1000):
        """Finish the pipeline."""
        self._get_events()
        self.recorder.pause()
        self._notify.poll(timeout=timeout)
        meta = self.event()
        self.writer.pause()
        return meta
    
    
    