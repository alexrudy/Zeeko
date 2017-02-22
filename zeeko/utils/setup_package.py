# -*- coding: utf-8 -*-
from __future__ import absolute_import

import glob
import os
import copy

from zeeko._build_helpers import get_utils_extension_args, get_zmq_extension_args, _generate_cython_extensions, pxd, h, get_package_data
from astropy_helpers import setup_helpers

utilities = [pxd("..utils.rc"), 
             pxd("..utils.msg"), 
             pxd("..utils.pthread"), 
             pxd("..utils.lock"), 
             pxd("..utils.condition"), 
             pxd("..utils.clock")]

clock = [ pxd(".clock"), h(".mclock") ]
pthread = [ pxd(".rc"), pxd(".pthread") ] + clock
refcount = [ pxd(".rc"), pxd(".refcount") ] + clock

dependencies = {
    'msg'       : [ pxd(".rc") ],
    'condition' : refcount + pthread,
    'hmap'      : [ pxd(".rc") ],
    'lock'      : refcount + pthread,
    'stopwatch' : clock
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
    