#!/usr/bin/env python

import click
import zmq
import logging
import socket
import urlparse
import time
import h5py
import os


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
    logger = logging.getLogger()
    logger.addHandler(h)
    logger.setLevel(logging.DEBUG)
    
    ctx.obj.log=logging.getLogger(ctx.invoked_subcommand)
    ctx.obj.zcontext=zmq.Context()
    ctx.obj.addr = "{scheme}://{hostname}:{port:d}".format(port=port, scheme=scheme, hostname=host)
    ctx.obj.bind = to_bind(ctx.obj.addr)
    ctx.obj.host = host
    ctx.obj.scheme = scheme
    ctx.obj.port = port
    ctx.obj.extra_addr = "{scheme}://{hostname}:{port:d}".format(port=port+1, scheme=scheme, hostname=host)
    ctx.obj.extra_bind = to_bind(ctx.obj.extra_addr)
    

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
    with s.wsocket() as poller:
        try:
            while s.is_alive():
                s['wfs'] = np.random.randn(180,180)
                s['tweeter'] = np.random.randn(32, 32)
                s['woofer'] = np.random.randn(52)
                ctx.obj.log.info("Sending {:.1f} msgs per second. N={:d}, w={:.4f}".format((s.counter - count) / float(interval),s.counter, s.wait_time * 1e3))
                count = s.counter
                if poller.poll(interval*1000):
                    ctx.obj.log.debug("State transition notification: {!r}".format(poller.recv()))
                
        finally:
            s.stop()
    

@main.command()
@click.option("--frequency", type=float, help="Publish frequency for server.", default=100)
@click.pass_context
def incrementer(ctx, frequency):
    """Make a ramping incrementer server."""
    from zeeko.messages.publisher import Publisher
    import numpy as np
    
    s = ctx.obj.zcontext.socket(zmq.PUB)
    s.bind(ctx.obj.bind)
    p = Publisher()
    p['wfs'] = np.zeros((180,180))
    p['tweeter'] = np.zeros((32, 32))
    p['woofer'] = np.zeros((52,))
    
    click.echo("Publishing {:d} array(s) to '{:s}' at {:.0f}Hz".format(len(p), ctx.obj.bind, frequency))
    click.echo("^C to stop.")
    count = 0
    try:
        while True:
            p['wfs'] = count
            p['tweeter'] = count
            p['woofer'] = count
            count += 1
            p.publish(s)
            time.sleep(1.0 / frequency)
    finally:
        s.close(linger=0)

@main.command()
@click.option("--interval", type=int, help="Polling interval for server status.", default=3)
@click.option("--frequency", type=float, help="Publish frequency for server.", default=100)
@click.pass_context
def throttle(ctx, frequency, interval):
    """The server."""
    from zeeko.workers.throttle import Throttle
    
    t = Throttle(ctx.obj.zcontext, ctx.obj.addr, ctx.obj.extra_bind)
    t.frequency = frequency
    click.echo("Throttling from '{:s}' to '{:s}' at {:.0f}Hz".format(ctx.obj.addr, ctx.obj.extra_bind, t.frequency))
    click.echo("^C to stop.")
    t.start()
    count = t.send_counter
    try:
        while True:
            ctx.obj.log.info("Sending {:.1f} msgs per second. N={:d}, w={:.4f}".format((t.send_counter - count) / float(interval),t.send_counter, t.wait_time * 1e3))
            count = t.send_counter
            time.sleep(interval)
    finally:
        t.stop()

@main.command()
@click.option("--interval", type=float, help="Polling interval for client status.", default=3)
@click.option("--filename", type=click.Path(), default="zeeko.test.hdf5")
@click.option("--chunk", type=int, help="Set chunk size.", default=10)
@click.pass_context
def telemetry(ctx, interval, filename, chunk):
    """Make a client"""
    from zeeko.telemetry.pipeline import Pipeline
    
    if os.path.exists(filename):
        os.remove(filename)
        click.echo("Removed old {:s}".format(filename))
    
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
            ctx.obj.log.info("Receiving {:.1f} msgs per second. Delay: {:.3g}".format((p.counter - count) / float(interval), p.delay))
            count = p.counter
    finally:
        print("Waiting for pipeline to finish.")
        print(p.finish(timeout=5.0))
        p.stop()
        hdf5info(filename)

@main.command()
@click.option("--interval", type=float, help="Polling interval for client status.", default=3)
@click.option("--chunk", type=int, help="Set chunk size.", default=10)
@click.pass_context
def recorder(ctx, interval, chunk):
    """Recorder"""
    from zeeko.telemetry.recorder import Recorder
    writer = "{0.scheme:s}://{0.host:s}:{port:d}".format(ctx.obj, port=ctx.obj.port+1)
    r = Recorder(ctx.obj.zcontext, ctx.obj.addr, to_bind(writer), chunk)
    click.echo("Receiving on '{:s}'".format(ctx.obj.addr))
    click.echo("Recording to '{:s}'".format(writer))
    r.start()
    count = r.counter
    try:
        while True:
            time.sleep(interval)
            ctx.obj.log.info("Receiving {:.1f} msgs per second. Delay: {:.3g}".format((r.counter - count) / float(interval), r.delay))
            count = r.counter
    finally:
        r.stop()

@main.command()
@click.pass_context
def subdebug(ctx):
    """Subscription debugger"""
    sub = ctx.obj.zcontext.socket(zmq.SUB)
    sub.connect(ctx.obj.addr)
    sub.subscribe("")
    while True:
        if sub.poll(timeout=1000):
            msg = sub.recv_multipart()
            for i,part in enumerate(msg):
                rpart = repr(part)
                if len(rpart) > 100:
                    rpart = rpart[:100] + "..."
                print("{:d}) {:s}".format(i+1, rpart))
                
    
@main.command()
@click.pass_context
def pulldebug(ctx):
    """Subscription debugger"""
    pull = ctx.obj.zcontext.socket(zmq.PULL)
    pull.connect(ctx.obj.addr)
    while True:
        if pull.poll(timeout=1000):
            msg = pull.recv_multipart()
            for i,part in enumerate(msg):
                rpart = repr(part)
                if len(rpart) > 100:
                    rpart = rpart[:100] + "..." + " [{:d}]".format(len(part))
                print("{:d}) {:s}".format(i+1, rpart))

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