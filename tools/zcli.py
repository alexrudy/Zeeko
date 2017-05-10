#!/usr/bin/env python
"""
Command-line interface for various Zeeko components
"""

import click
import logging
import logging.handlers
import zmq
import time
import sys
import numpy as np

from zutils import zmain, ioloop, MessageLine


log = logging.getLogger()

main = zmain()

@main.command()
@click.option("--interval", type=int, help="Polling interval for client status.", default=1)
@click.option("--guess", "bind", default=True, help="Try to bind the connection.", flag_value='guess')
@click.option("--bind", "bind", help="Try to bind the connection.", flag_value='bind')
@click.option("--connect", "bind", help="Try to use connect to attach the connection", flag_value='connect')
@click.pass_context
def proxy(ctx, interval, bind):
    """A proxy object for monitoring traffic between two sockets"""
    proxylog = log.getChild("proxy")
    h = logging.handlers.RotatingFileHandler("zcli-proxy.log", mode='w', maxBytes=10 * (1024 ** 2), backupCount=0, encoding='utf-8')
    h.setFormatter(logging.Formatter(fmt='%(message)s,%(created)f'))
    proxylog.addHandler(h)
    proxylog.propagate = False
    xpub = ctx.obj.zcontext.socket(zmq.XPUB)
    xsub = ctx.obj.zcontext.socket(zmq.XSUB)
    
    if bind == 'connect':
        xpub.connect(ctx.obj.secondary.url)
        xsub.connect(ctx.obj.primary.url)
        click.echo("XPUB at {0}".format(ctx.obj.secondary.url))
        click.echo("XSUB at {0}".format(ctx.obj.primary.url))
    else:
        xpub.bind(ctx.obj.secondary.bind)
        xsub.bind(ctx.obj.primary.bind)
        click.echo("XPUB at {0}".format(ctx.obj.secondary.bind))
        click.echo("XSUB at {0}".format(ctx.obj.primary.bind))
    
    poller = zmq.Poller()
    poller.register(xpub, zmq.POLLIN)
    poller.register(xsub, zmq.POLLIN)
    
    rate = 0.0
    last_message = time.time()
    
    with MessageLine(sys.stdout) as printer:
        while True:
            start = time.time()
            while last_message + interval > start:
                data = 0
                sockets = dict(poller.poll(timeout=10))
                if sockets.get(xpub, 0) & zmq.POLLIN:
                    msg = xpub.recv_multipart()
                    if len(msg) == 1 and msg[0][0] in "\x00\x01":
                        if msg[0][0] == '\x00':
                            printer.echo("[BROKER]: unsubscribe '{0}'".format(msg[0][1:]))
                            proxylog.info("unsubscribe,'{0}'".format(msg[0][1:]))
                        elif msg[0][0] == '\x01':
                            printer.echo("[BROKER]: subscribe '{0}'".format(msg[0][1:]))
                            proxylog.info("subscribe,'{0}'".format(msg[0][1:]))
                        ratemsg = "Rate = {:.2f} Mb/s".format(rate / (1024 ** 2))
                        proxylog.info("rate,{:.2f}".format(rate / 1024 ** 2))
                        printer(ratemsg)
                    xsub.send_multipart(msg)
                    data += sum(len(m) for m in msg)
                if sockets.get(xsub, 0) & zmq.POLLIN:
                    msg = xsub.recv_multipart()
                    xpub.send_multipart(msg)
                    data += sum(len(m) for m in msg)
                end = time.time()
                rate = (rate * 0.9) + (data / (end - start)) * 0.1
                start = time.time()
            ratemsg = "Rate = {:.2f} Mb/s".format(rate / (1024 ** 2))
            proxylog.info("rate,{:.2f}".format(rate / 1024 ** 2))
            printer(ratemsg)
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
        click.echo("Memory usage at start: {:d}MB".format(ctx.obj.mem.poll()))
        with MessageLine(sys.stdout) as msg:
            count = c.framecount
            time.sleep(0.1)
            msg.echo("Client connected to {0:s} (bind={1})".format(ctx.obj.primary.addr(), ctx.obj.primary.did_bind()))
            while True:
                time.sleep(interval)
                msg("Receiving {:10.1f} msgs per second. Delay: {:4.3g} Mem: {:d}MB".format((c.framecount - count) / float(interval), c.snail.delay, ctx.obj.mem.usage()))
                count = c.framecount

@main.command()
@click.option("--interval", type=int, help="Polling interval for client status.", default=3)
@click.option("--subscribe", type=str, default="", help="Subscription value.")
@click.option("--chunksize", type=int, default=1024, help="Telemetry chunk size")
@click.pass_context
def telemetry(ctx, interval, subscribe, chunksize):
    """Run a telemetry pipeline."""
    from zeeko.telemetry import PipelineIOLoop
    memory_logger = log.getChild("telemetry")
    h = logging.handlers.RotatingFileHandler("zcli-telemetry.log", mode='w', maxBytes=10 * (1024 ** 2), backupCount=0, encoding='utf-8')
    h.setFormatter(logging.Formatter(fmt='%(message)s,%(created)f'))
    memory_logger.addHandler(h)
    memory_logger.propagate = False
    
    p = PipelineIOLoop(ctx.obj.primary.addr(), ctx.obj.zcontext, chunksize=chunksize)
    c = p.record
    with p.running() as loop:
        ctx.obj.mem.calibrate()
        click.echo("Memory usage at start: {:d}MB".format(ctx.obj.mem.poll()))
        with MessageLine(sys.stdout) as msg:
            count = c.framecount
            time.sleep(0.1)
            msg.echo("Client connected to {0:s} (bind={1})".format(ctx.obj.primary.addr(), ctx.obj.primary.did_bind()))
            while True:
                time.sleep(interval)
                msg("Receiving {:10.1f} msgs per second. Delay: {:4.3g} Mem: {:d}MB".format((c.framecount - count) / float(interval), c.snail.delay, ctx.obj.mem.usage()))
                memory_logger.info("{0},{1},{2}".format(c.chunkcount, p.write.counter, ctx.obj.mem.usage()))
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
        click.echo("Memory usage at start: {:d}MB".format(ctx.obj.mem.poll()))
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
                    (ncount - count) / float(interval) * len(s), ncount, max(s.throttle._delay,0.0), ctx.obj.mem.usage()))
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