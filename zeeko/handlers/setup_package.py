# -*- coding: utf-8 -*-
from __future__ import absolute_import

import os

from zeeko._build_helpers import get_utils_extension_args, get_zmq_extension_args, _generate_cython_extensions
from astropy_helpers import setup_helpers

HERE = os.path.dirname(__file__)

pjoin = os.path.join
pyx = lambda *path : os.path.relpath(pjoin(HERE, *path) + ".pyx")
pxd = lambda *path : os.path.relpath(pjoin(HERE, *path) + ".pxd")

rc = pxd("..", "utils", "rc")
msg = pxd("..","utils","msg")
clock = pxd("..","utils","clock")
lock = pxd("..","utils","lock")
event = pxd("..","utils","condition")


receiver = pxd("..","messages","receiver")
publisher = pxd("..","messages","publisher")

dependencies = {
    'base' : [],
    'client': [rc, msg, receiver, pxd('base')],
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