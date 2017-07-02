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
@click.pass_context
def subdebug(ctx):
    """Subscription debugger"""
    sub = ctx.obj.zcontext.socket(zmq.SUB)
    sub.connect(ctx.obj.primary.addr())
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
    """Pull socket debugger"""
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
    
class Namespace(object):
    pass

if __name__ == '__main__':
    main(obj=Namespace())
