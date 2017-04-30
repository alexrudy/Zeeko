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

class Namespace(object):
    pass

if __name__ == '__main__':
    main(obj=Namespace())