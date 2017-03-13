# -*- coding: utf-8 -*-
from __future__ import absolute_import

import os

from zeeko._build_helpers import get_utils_extension_args, get_zmq_extension_args, _generate_cython_extensions, pxd, get_package_data
from astropy_helpers import setup_helpers

condition = [pxd("..utils.pthread"), pxd("..utils.condition")]
carray = [pxd(".carray"), pxd(".utils")]
message = [pxd('.message')] + carray

dependencies = {
    'carray'    : [ pxd(".utils") ],
    'mevents'   : [ pxd("..utils.hmap") ] + condition,
    'message'   : carray + [ pxd("..utils.clock")],
    'receiver'  : message + [ pxd('.mevents') ] + condition,
    'publisher' : message + [ pxd("..utils.clock"), pxd(".receiver") ] + condition
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