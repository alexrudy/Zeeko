# -*- coding: utf-8 -*-
"""
A tool to grab the ZMQ headers, if they aren't present.
"""

import os
import zmq
import tarfile
import shutil
import stat
import sys
import glob
from subprocess import Popen, PIPE

# logging
import logging
logger = logging.getLogger()
if os.environ.get('DEBUG'):
    logger.setLevel(logging.DEBUG)
else:
    logger.setLevel(logging.INFO)
logger.addHandler(logging.StreamHandler(sys.stderr))
info = logger.info
warn = logger.warn
debug = logger.debug

try:
    # py2
    from urllib2 import urlopen
except ImportError:
    # py3
    from urllib.request import urlopen

pjoin = os.path.join

HERE = os.path.dirname(__file__)
ROOT = os.path.dirname(HERE)

def get_libzmq_info(version):
    """Get libzmq download info from a libzmq version number."""
    vs = '%i.%i.%i' % version
    libzmq = "zeromq-%s.tar.gz" % vs
    libzmq_url = "https://github.com/zeromq/zeromq{major}-{minor}/releases/download/v{vs}/{libzmq}".format(
        major=version[0],
        minor=version[1],
        vs=vs,
        libzmq=libzmq,
    )
    return (libzmq, libzmq_url)

def fetch_archive(savedir, url, fname, force=False):
    """download an archive to a specific location"""
    dest = pjoin(savedir, fname)
    
    if os.path.exists(dest) and not force:
        info("already have %s" % dest)
        return dest
    
    info("fetching %s into %s" % (url, savedir))
    if not os.path.exists(savedir):
        os.makedirs(savedir)
    req = urlopen(url)
    with open(dest, 'wb') as f:
        f.write(req.read())
    return dest

def fetch_libzmq(savedir, libzmq, libzmq_url):
    """download and extract libzmq"""
    dest = pjoin(savedir, 'zeromq')
    if os.path.exists(dest):
        info("removing old %s" % dest)
        shutil.rmtree(dest)
    path = fetch_archive(savedir, libzmq_url, fname=libzmq)
    tf = tarfile.open(path)
    with_version = pjoin(savedir, tf.firstmember.path)
    tf.extractall(savedir)
    tf.close()
    # remove version suffix:
    shutil.move(with_version, dest)
    
def check_version():
    """Check that this ZMQ version requires additional headers."""
    #TODO: When pyzmq release includes headers
    return True

def main():
    """Grab ZMQ Headers"""
    if not check_version():
        return
    version = zmq.zmq_version_info()
    libzmq, libzmq_url = get_libzmq_info(version)    
    bundledir = pjoin(HERE,'bundled')
    if not os.path.exists(bundledir):
        os.makedirs(bundledir)
    fetch_libzmq(bundledir, libzmq, libzmq_url)
    
    includedir = pjoin(HERE, 'zeeko', 'include')
    for header in glob.iglob(pjoin(bundledir, 'zeromq', 'include', '*.h')):
        shutil.copy(header, includedir)
    info("put zmq headers in %s" % includedir)

if __name__ == '__main__':
    main()