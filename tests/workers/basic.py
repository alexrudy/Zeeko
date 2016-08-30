#!/usr/bin/env python

import click
import zmq
import logging
import socket
import urlparse
import time
import h5py


def to_bind(address):
    """Parse an address to a bind address."""
    parsed = urlparse.urlparse(address)
    hostname = socket.gethostbyname(parsed.hostname)
    return "{0.scheme}://{hostname}:{0.port:d}".format(parsed, hostname=hostname)

@click.group()
@click.option("--port", type=int, help="Port number.", default=7654)
@click.option("--host", type=str, help="Host name.", default="localhost")
@click.option("--scheme", type=str, help="ZMQ Protocol.", default="tcp")
@click.pass_context
def main(ctx, port, host, scheme):
    """ZMQ Client-Server Pair."""
    
    h = logging.StreamHandler()
    f = logging.Formatter("--> %(message)s [%(name)s]")
    h.setLevel(logging.DEBUG)
    h.setFormatter(f)
    ctx.obj.log=logging.getLogger()
    ctx.obj.zcontext=zmq.Context()
    ctx.obj.log.addHandler(h)
    ctx.obj.log.setLevel(logging.DEBUG)
    ctx.obj.addr = "{scheme}://{hostname}:{port:d}".format(port=port, scheme=scheme, hostname=host)
    ctx.obj.bind = to_bind(ctx.obj.addr)

@main.command()
@click.option("--interval", type=int, help="Polling interval for client status.", default=3)
@click.pass_context
def client(ctx, interval):
    """Make a client"""
    from zeeko.workers.client import Client
    c = Client(ctx.obj.zcontext, ctx.obj.addr)
    c.start()
    count = c.counter
    try:
        while True:
            time.sleep(interval)
            ctx.obj.log.info("Receiving {:.1f} msgs per second. Delay: {:.3g}".format((c.counter - count) / float(interval), c.delay))
            count = c.counter
    finally:
        c.stop()
    
@main.command()
@click.option("--interval", type=int, help="Polling interval for server status.", default=3)
@click.option("--frequency", type=float, help="Publish frequency for server.", default=100)
@click.pass_context
def server(ctx, frequency, interval):
    """The server."""
    from zeeko.workers.server import Server
    import numpy as np
    
    s = Server(ctx.obj.zcontext, ctx.obj.bind)
    s.frequency = frequency
    s['wfs'] = np.random.randn(180,180)
    s['tweeter'] = np.random.randn(32, 32)
    s['woofer'] = np.random.randn(52)
    
    click.echo("Publishing {:d} array(s) to '{:s}' at {:.0f}Hz".format(len(s), ctx.obj.bind, s.frequency))
    click.echo("^C to stop.")
    s.start()
    count = s.counter
    try:
        while True:
            s['wfs'] = np.random.randn(180,180)
            s['tweeter'] = np.random.randn(32, 32)
            s['woofer'] = np.random.randn(52)
            ctx.obj.log.info("Sending {:.1f} msgs per second. N={:d}, w={:.4f}".format((s.counter - count) / float(interval),s.counter, s.wait_time * 1e3))
            count = s.counter
            time.sleep(interval)
    finally:
        s.stop()
    

@main.command()
@click.option("--interval", type=float, help="Polling interval for client status.", default=3)
@click.option("--filename", type=click.Path(), default="zeeko.test.hdf5")
@click.option("--chunk", type=int, help="Set chunk size.", default=10)
@click.pass_context
def telemetry(ctx, interval, filename, chunk):
    """Make a client"""
    from zeeko.telemetry.pipeline import Pipeline
    p = Pipeline(ctx.obj.addr, filename, ctx.obj.zcontext, chunk)    
    click.echo("Receiving on '{:s}'".format(ctx.obj.addr))
    
    p.start()
    count = p.counter
    try:
        while True:
            event = p.event()
            if event:
                ctx.obj.log.info("Got notification: {!r}".format(event))
            time.sleep(interval)
            ctx.obj.log.info("Receiving {:.1f} msgs per second.".format((p.counter - count) / float(interval)))
            count = p.counter
    finally:
        print(p.finish(timeout=5.0))
        p.stop()
        hdf5info(filename)

def hdf5visiotr(name, obj):
    """HDF5 Visitor."""
    if isinstance(obj, h5py.Dataset):
        print("{name:s} : {shape!r} {dtype:s}".format(name=obj.name, shape=obj.shape, dtype=obj.dtype.str))
    else:
        print("{name:s} ->".format(name=name))
    
def hdf5info(filename):
    """Get information about an HDF5 file."""
    print("HDF5 INFO: {:s}".format(filename))
    with h5py.File(filename, 'r') as f:
        f.visititems(hdf5visiotr)
            
    
class Namespace(object):
    pass
    
if __name__ == '__main__':
    main(obj=Namespace())