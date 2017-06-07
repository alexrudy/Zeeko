#!/usr/bin/env python

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
@click.pass_context
def receiver(ctx):
    """Memory-test the receiver."""
    from zeeko.messages import Receiver
    
    socket = ctx.obj.zcontext.socket(zmq.SUB)
    socket.connect(ctx.obj.primary.addr())
    socket.subscribe("")
    receiver = Receiver()
    
    with MessageLine(sys.stdout) as msg:
        ctx.obj.mem.calibrate()
        while True:
            if socket.poll():
                receiver.receive(socket)
                msg("m = {:d}MB r = {!r}".format(ctx.obj.mem.usage(), receiver))
            if ctx.obj.mem.usage() > 100:
                click.echo("")
                click.secho("Memory leak detected. Giving up.", fg='red')
                click.echo("At the end, m = {:d}MB".format(ctx.obj.mem.usage()))
                raise click.Abort()

@main.command()
@click.option("--hardcopy/--no-hardcopy", default=True, help="Enable hardcopy on send.")
@click.option("--hwm", default=0, type=int, help="Set the high water mark.")
@click.pass_context
def publisher(ctx, hardcopy, hwm):
    """Memory-test the publisher."""
    from zeeko.messages import Publisher
    
    socket = ctx.obj.zcontext.socket(zmq.PUB)
    socket.bind(ctx.obj.primary.bind)
    publisher = Publisher()
    if hardcopy:
        publisher.enable_hardcopy()
    if hwm:
        socket.set(zmq.SNDHWM, int(hwm))
    publisher['image'] = np.random.randn(180,180)
    publisher['grid'] = np.random.randn(32, 32)
    publisher['array'] = np.random.randn(52)
    
    with MessageLine(sys.stdout) as msg:
        ctx.obj.mem.calibrate()
        while True:
            
            publisher.publish(socket)
            msg("m = {:d}MB r = {!r}".format(ctx.obj.mem.usage(), publisher))
            if ctx.obj.mem.usage() > 100:
                click.echo("")
                click.secho("Memory leak detected. Giving up.", fg='red')
                click.echo("At the end, m = {:d}MB".format(ctx.obj.mem.usage()))
                raise click.Abort()
            time.sleep(0.1)


class Namespace(object):
    pass

if __name__ == '__main__':
    main(obj=Namespace())