# -*- coding: utf-8 -*-
from __future__ import absolute_import

import os

from zeeko._build_helpers import get_utils_extension_args, get_zmq_extension_args, _generate_cython_extensions
from astropy_helpers import setup_helpers

HERE = os.path.dirname(__file__)
PACKAGE = ".".join(__name__.split(".")[:-1])

pjoin = os.path.join
pyx = lambda *path : os.path.relpath(pjoin(HERE, *path) + ".pyx")
pxd = lambda *path : os.path.relpath(pjoin(HERE, *path) + ".pxd")

dependencies = {
    'carray' : [pxd("utils")],
    'message' : [pxd("carray"), pxd("utils"), pxd("..","utils","clock")],
    'receiver' : [pxd("carray"), pxd("..", "utils", "pthread"), pxd("utils"), pxd("..", "utils", "condition")],
    'publisher' : [pxd("carray"), pxd("receiver"), pxd("..", "utils", "pthread"), pxd("..","utils","clock")]
}

def get_package_data():
    """Return package data."""
    return {PACKAGE:['*.pxd', '*.h']}

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