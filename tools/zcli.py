#!/usr/bin/env python
"""
Command-line interface for various Zeeko components
"""

import click
import logging
import zmq
import socket
import urlparse
import contextlib
import time

log = logging.getLogger()

@contextlib.contextmanager
def ioloop(context, *sockets):
    """Render a running IOLoop"""
    from zeeko.cyloop.loop import DebugIOLoop
    loop = DebugIOLoop(context)
    for socket in sockets:
        loop.attach(socket)
    with loop.running():
        yield loop
    

def to_bind(address):
    """Parse an address to a bind address."""
    parsed = urlparse.urlparse(address)
    if parsed.hostname == "*":
        hostname = "*"
    else:
        hostname = socket.gethostbyname(parsed.hostname)
    return "{0.scheme}://{hostname}:{0.port:d}".format(parsed, hostname=hostname)

def setup_logging():
    """Initialize logging."""
    h = logging.StreamHandler()
    f = logging.Formatter("%(levelname)-8s --> %(message)s [%(name)s]")
    h.setLevel(logging.DEBUG)
    h.setFormatter(f)
    
    l = logging.getLogger()
    l.addHandler(h)
    l.setLevel(logging.DEBUG)

@click.group()
@click.option("--port", type=int, help="Port number.", default=7654)
@click.option("--host", type=str, help="Host name.", default="localhost")
@click.option("--scheme", type=str, help="ZMQ Protocol.", default="tcp")
@click.pass_context
def main(ctx, port, host, scheme):
    """Command line interface for the Zeeko library."""
    setup_logging()
    ctx.obj.log = logging.getLogger(ctx.invoked_subcommand)
    ctx.obj.zcontext = zmq.Context()
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
    from zeeko.handlers.client import Client
    c = Client.at_address(ctx.obj.addr, ctx.obj.zcontext)
    with ioloop(ctx.obj.zcontext, c) as loop:
        count = c.framecount
        while True:
            time.sleep(interval)
            ctx.obj.log.info("Receiving {:.1f} msgs per second. Delay: {:.3g}".format((c.framecount - count) / float(interval), c.snail.delay))
            count = c.framecount

@main.command()
@click.option("--interval", type=int, help="Polling interval for server status.", default=3)
@click.option("--frequency", type=float, help="Publish frequency for server.", default=100)
@click.pass_context
def server(ctx, frequency, interval):
    """Serve some random data."""
    from zeeko.handlers.server import Server
    import numpy as np
    
    s = Server.at_address(ctx.obj.bind, ctx.obj.zcontext)
    s.throttle.frequency = frequency
    s.throttle.active = True
    s['image'] = np.random.randn(180,180)
    s['grid'] = np.random.randn(32, 32)
    s['array'] = np.random.randn(52)
    
    click.echo("Publishing {:d} array(s) to '{:s}' at {:.0f}Hz".format(len(s), ctx.obj.bind, s.throttle.frequency))
    click.echo("^C to stop.")
    with ioloop(ctx.obj.zcontext, s) as loop:
        count = s.framecount
        while loop.is_alive():
            time.sleep(interval)
            s['image'] = np.random.randn(180,180)
            s['grid'] = np.random.randn(32, 32)
            s['array'] = np.random.randn(52)
            ncount = s.framecount
            ctx.obj.log.info("Sending {:.1f} msgs per second. N={:d}, to={:.4f}".format(
                            (ncount - count) / float(interval) * len(s), ncount, s.throttle._delay))
            count = s.framecount
    

@main.command()
@click.option("--frequency", type=float, help="Publish frequency for server.", default=100)
@click.pass_context
def sprofile(ctx, frequency):
    """Profile the throttle/server."""
    from zeeko.handlers.server import Server
    import numpy as np
    interval = 1.0
    s = Server.at_address(ctx.obj.bind, ctx.obj.zcontext)
    # s.throttle.frequency = frequency
    # s.throttle.active = True
    s['image'] = np.random.randn(180,180)
    s['grid'] = np.random.randn(32, 32)
    s['array'] = np.random.randn(52)
    
    click.echo("Publishing {:d} array(s) to '{:s}' at {:.0f}Hz".format(len(s), ctx.obj.bind, s.throttle.frequency))
    click.echo("^C to stop.")
    start = time.time()
    with ioloop(ctx.obj.zcontext, s) as loop:
        count = s.framecount
        throttle = loop.worker.throttle
        throttle.frequency = frequency
        throttle.active = True
        while loop.is_alive() and s.framecount < 1000:
            time.sleep(interval)
            s['image'] = np.random.randn(180,180)
            s['grid'] = np.random.randn(32, 32)
            s['array'] = np.random.randn(52)
            ncount = s.framecount
            ctx.obj.log.info("Sending {:.1f} msgs per second. N={:d}, to={:.4f}".format(
                            (ncount - count) / float(interval) * len(s), ncount, throttle._delay))
            count = s.framecount
        end = time.time()
    click.echo("Effective Framerate = {0:.1f}Hz".format(s.framecount / (end - start)))
    import matplotlib.pyplot as plt
    plt.plot(throttle._history)
    plt.xlabel("Timestep")
    plt.ylabel("Timeout")
    plt.show()

class Namespace(object):
    pass

if __name__ == '__main__':
    main(obj=Namespace())