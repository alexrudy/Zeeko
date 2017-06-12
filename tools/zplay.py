#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
Replay telemetry data from an HDF5 file.
"""
import click
import logging
import logging.handlers
import zmq
import time
import sys
import numpy as np
import h5py

from zutils import zmain, ioloop, MessageLine

log = logging.getLogger()
main = zmain()

@main.command()
@click.argument("telemetry", type=click.Path(exists=True, dir_okay=False))
@click.option("--path", type=str, help="HDF5 path to data.", default="telemetry")
@click.option("--frequency", type=float, help="Publish frequency for server.", default=1000)
@click.pass_context
def replay(ctx, telemetry, path, frequency):
    """Replay data from an HDF5 file."""
    from zeeko.handlers import Server
    server = Server.at_address(ctx.obj.primary.addr(prefer_bind=True), 
                               ctx.obj.zcontext, 
                               bind=ctx.obj.primary.did_bind(prefer_bind=True))
    server.throttle.frequency = frequency
    server.throttle.active = True
    with h5py.File(telemetry, 'r') as f:
        group = f[path]
        ntosend = float('inf')
        for dataset in group.values():
            server[dataset.name] = dataset['data'][0,...]
            if dataset['data'].shape[0] < ntosend:
                ntosend = dataset['data'].shape[0]
        click.echo("Publishing {:d} array(s) to '{:s}' at {:.0f}Hz".format(len(server), 
                   ctx.obj.primary.addr(prefer_bind=True), server.throttle.frequency))
        click.echo("^C to stop.")
        while True:
            server()
            fc = server.framecount % ntosend
            for dataset in group.values():
                server[dataset.name] = dataset['data'][fc,...]
        
    

class Namespace(object):
    pass

if __name__ == '__main__':
    main(obj=Namespace())