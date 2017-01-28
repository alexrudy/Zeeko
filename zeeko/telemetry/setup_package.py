# -*- coding: utf-8 -*-
from __future__ import absolute_import

import os

from zeeko._build_helpers import get_utils_extension_args, get_zmq_extension_args, _generate_cython_extensions
from astropy_helpers import setup_helpers


HERE = os.path.dirname(__file__)

pjoin = os.path.join
pyx = lambda *path : os.path.relpath(pjoin(HERE, *path) + ".pyx")
pxd = lambda *path : os.path.relpath(pjoin(HERE, *path) + ".pxd")

base = pxd("..","workers","base")
state = pxd("..","workers","state")
clock = pxd("..","utils","clock")
client = [base, state, clock, pxd("..","workers","client")]
mutils = pxd("..","messages","utils")

receiver = [clock, mutils, pxd("..","messages","receiver")]
publisher = [clock, mutils, pxd("..","messages","publisher")]


dependencies = {
    'recorder' : client + receiver + publisher + [pxd('..',"messages","carray"), pxd("chunk"), pxd("..","utils","hmap")],
    'chunk' :  [pxd("..","messages","utils"), pxd("..","messages","carray"),pxd("..","messages","message")],
    'writer' : [base, state, pxd('chunk')] + receiver
}


def get_extensions(**kwargs):
    """Get the Cython extensions"""
    extension_args = setup_helpers.DistutilsExtensionArgs()
    extension_args.update(get_utils_extension_args())
    extension_args.update(get_zmq_extension_args())
    extension_args['include_dirs'].append('numpy')
    
    package_name = __name__.split(".")[:-1]
    extensions = [e for e in _generate_cython_extensions(extension_args, os.path.dirname(__file__), package_name)]
    for extension in extensions:
        name = extension.name.split(".")[-1]
        if name in dependencies:
            extension.depends.extend(dependencies[name])
    return extensions