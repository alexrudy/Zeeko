import click
import logging
import zmq
import socket
import urlparse
import contextlib
import time
import attr
import sys
import os
import psutil

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

@attr.s
class MemoryUsage(object):
    """A class to record memory usage"""
    
    zeropoint = attr.ib(default=0.0, init=False)
    
    @staticmethod
    def poll():
        """Poll for memory usage, in bytes."""
        process = psutil.Process(os.getpid())
        return process.memory_info().rss / (1024 ** 2)
        
    def calibrate(self):
        """Set the zeropoint for calibration."""
        self.zeropoint = self.poll()
        
        
    def usage(self):
        """Return memory usage, in MB."""
        return (self.poll() - self.zeropoint)
    
class MessageLine(object):
    """A single line message"""
    def __init__(self, stream):
        super(MessageLine, self).__init__()
        self.stream = stream
        self.active = False
        self.last_message_length = 0
        
    def echo(self, message):
        """Delegate to click.echo, then continue."""
        self.__call__(message)
        self.stream.write("\n")
        self.stream.flush()
        self.last_message_length = 0
        
    def __enter__(self):
        """Start messages."""
        if not self.active:
            self.active = True
            self.stream.write("\n")
            self.stream.flush()
            self.last_message_length = 0
        return self
        
    def __exit__(self, exc_cls, exc, tb):
        """End messages."""
        self.active = False
        self.stream.write("\n")
        self.stream.flush()
        return
        
    def __call__(self, msg):
        """Call messages"""
        self.stream.write("\r")
        self.stream.write(msg)
        if self.last_message_length > len(msg):
            self.stream.write(" " * (self.last_message_length - len(msg)))
        self.stream.flush()
        self.last_message_length = len(msg)

@attr.s
class AddressInfo(object):
    """Address info for zeromq"""
    
    scheme = attr.ib(validator=attr.validators.instance_of((str, unicode)))
    hostname = attr.ib(validator=attr.validators.instance_of((str, unicode)))
    port = attr.ib(validator=attr.validators.instance_of(int))
    url = attr.ib(init=False)
    bind = attr.ib(init=False, repr=False)
    is_bind = attr.ib(default=None)
    
    def __attrs_post_init__(self):
        if self.scheme in ('inproc', 'unix'):
            self.url = "{scheme}://{hostname:s}-{port:d}".format(port=self.port, scheme=self.scheme, hostname=self.hostname)
        else:
            self.url = "{scheme}://{hostname:s}:{port:d}".format(port=self.port, scheme=self.scheme, hostname=self.hostname)
        if self.scheme in ('inproc', 'unix'):
            self.bind = self.url
        else:
            self.bind = to_bind(self.url)
    
    def addr(self, prefer_bind=False):
        """Address, if bind."""
        if self.is_bind or (self.bind is None and prefer_bind):
            return self.bind
        else:
            return self.url
    
    def did_bind(self, prefer_bind=False):
        """docstring for fname"""
        if self.is_bind or (self.bind is None and prefer_bind):
            return True
        else:
            return False
def zmain(docs=None):
    """Generate a main command group."""
    @click.group()
    @click.option("--port", type=int, help="Port number.", default=7654)
    @click.option("--secondary-port", type=int, help="Port number.", default=None)
    @click.option("--host", type=str, help="Host name.", default="localhost")
    @click.option("--scheme", type=str, help="ZMQ Protocol.", default="tcp")
    @click.option("--guess", "bind", default=True, help="Try to bind the connection.", flag_value='guess')
    @click.option("--bind", "bind", help="Try to bind the connection.", flag_value='bind')
    @click.option("--connect", "bind", help="Try to use connect to attach the connection", flag_value='connect')
    @click.pass_context
    def main(ctx, port, secondary_port, host, scheme, bind):
        """Command line interface for the Zeeko library."""
        setup_logging()
        ctx.obj.log = logging.getLogger(ctx.invoked_subcommand)
        ctx.obj.zcontext = zmq.Context()
        ctx.obj.is_bind = bind
        ctx.obj.primary = AddressInfo(scheme, host, port)
        if secondary_port is None:
            secondary_port = port + 1
        ctx.obj.secondary = AddressInfo(port=secondary_port, scheme=scheme, hostname=host)
        if bind != "guess":
            click.echo("Bind = {0}".format(bind))
            ctx.obj.primary.is_bind = True if bind == 'bind' else False
        ctx.obj.mem = MemoryUsage()
        ctx.obj.mem.calibrate()
    if docs is not None:
        main.__doc__ = docs
    return main
