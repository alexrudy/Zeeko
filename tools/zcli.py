#!/usr/bin/env python
"""
Command-line interface for various Zeeko components
"""

import click
import logging
import zmq
import time
import sys
import numpy as np

from zutils import zmain, ioloop, MessageLine


log = logging.getLogger()

main = zmain()

@main.command()
@click.option("--interval", type=int, help="Polling interval for client status.", default=3)
@click.pass_context
def proxy(ctx, interval):
    """A proxy object for monitoring traffic between two sockets"""
    xpub = ctx.obj.zcontext.socket(zmq.XPUB)
    xsub = ctx.obj.zcontext.socket(zmq.XSUB)
    
    xpub.bind(ctx.obj.secondary.bind)
    xsub.bind(ctx.obj.primary.bind)
    
    click.echo("XPUB at {0}".format(ctx.obj.secondary.bind))
    click.echo("XSUB at {0}".format(ctx.obj.primary.bind))
    
    poller = zmq.Poller()
    poller.register(xpub, zmq.POLLIN)
    poller.register(xsub, zmq.POLLIN)
    
    rate = 0.0
    last_message = time.time()
    
    while True:
        start = time.time()
        while last_message + interval > start:
            data = 0
            sockets = dict(poller.poll(timeout=10))
            if sockets.get(xpub, 0) & zmq.POLLIN:
                msg = xpub.recv_multipart()
                click.echo("[BROKER]: SUB {0!r}".format(msg))
                xsub.send_multipart(msg)
                data += sum(len(m) for m in msg)
            if sockets.get(xsub, 0) & zmq.POLLIN:
                msg = xsub.recv_multipart()
                xpub.send_multipart(msg)
                data += sum(len(m) for m in msg)
            end = time.time()
            rate = (rate * 0.9) + (data / (end - start)) * 0.1
            start = time.time()
        click.echo("Rate = {:.2f} Mb/s".format(rate / (1024 ** 2)))
        last_message = time.time()

@main.command()
@click.option("--interval", type=int, help="Polling interval for client status.", default=3)
@click.option("--subscribe", type=str, default="", help="Subscription value.")
@click.pass_context
def client(ctx, interval, subscribe):
    """Make a client"""
    from zeeko.handlers.client import Client
    
    c = Client.at_address(ctx.obj.primary.addr(), ctx.obj.zcontext, bind=ctx.obj.primary.did_bind())
    if subscribe:
        c.opt.subscribe(subscribe.encode('utf-8'))
    with ioloop(ctx.obj.zcontext, c) as loop:
        ctx.obj.mem.calibrate()
        click.echo("Memory usage at start: {:d}MB".format(ctx.obj.mem.poll() / (1024**2)))
        with MessageLine(sys.stdout) as msg:
            count = c.framecount
            time.sleep(0.1)
            sys.stdout.write("Client connected to {0:s}".format(ctx.obj.primary.addr()))
            sys.stdout.flush()
            while True:
                time.sleep(interval)
                msg("Receiving {:10.1f} msgs per second. Delay: {:4.3g} Mem: {:d}MB".format((c.framecount - count) / float(interval), c.snail.delay, ctx.obj.mem.usage() / (1024**2)))
                count = c.framecount

@main.command()
@click.option("--interval", type=int, help="Polling interval for server status.", default=3)
@click.option("--frequency", type=float, help="Publish frequency for server.", default=100)
@click.pass_context
def server(ctx, frequency, interval):
    """Serve some random data."""
    from zeeko.handlers.server import Server
    import numpy as np
    
    s = Server.at_address(ctx.obj.primary.addr(prefer_bind=True), ctx.obj.zcontext, bind=ctx.obj.primary.did_bind(prefer_bind=True))
    s.throttle.frequency = frequency
    s.throttle.active = True
    s['image'] = np.random.randn(180,180)
    s['grid'] = np.random.randn(32, 32)
    s['array'] = np.random.randn(52)
    
    click.echo("Publishing {:d} array(s) to '{:s}' at {:.0f}Hz".format(len(s), ctx.obj.primary.addr(prefer_bind=True), s.throttle.frequency))
    click.echo("^C to stop.")
    with ioloop(ctx.obj.zcontext, s) as loop:
        ctx.obj.mem.calibrate()
        click.echo("Memory usage at start: {:d}MB".format(ctx.obj.mem.poll() / (1024**2)))
        count = s.framecount
        with MessageLine(sys.stdout) as msg:
            sys.stdout.write("\n")
            sys.stdout.flush()
            while loop.is_alive():
                time.sleep(interval)
                s['image'] = np.random.randn(180,180)
                s['grid'] = np.random.randn(32, 32)
                s['array'] = np.random.randn(52)
                ncount = s.framecount
                msg("Sending {:5.1f} msgs per second. N={:6d}, to={:.4f}, mem={:d}MB".format(
                    (ncount - count) / float(interval) * len(s), ncount, max(s.throttle._delay,0.0), ctx.obj.mem.usage() / (1024**2)))
                count = ncount
    

@main.command()
@click.option("--frequency", type=float, help="Publish frequency for server.", default=100)
@click.pass_context
def sprofile(ctx, frequency):
    """Profile the throttle/server."""
    from zeeko.handlers.server import Server
    import numpy as np
    interval = 1.0
    s = Server.at_address(ctx.obj.primary.addr(prefer_bind=True), ctx.obj.zcontext, bind=ctx.obj.primary.did_bind(prefer_bind=True))
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