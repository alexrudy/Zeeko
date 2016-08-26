# -*- coding: utf-8 -*-
from __future__ import absolute_import

import glob
import os
import copy

from distutils.core import Extension

def get_zmq_include_path():
    """Get the ZMQ include path in an import-safe manner."""
    try:
        import zmq
        return zmq.get_includes()
    except ImportError as e:
        return []

def get_extensions(**kwargs):
    """Get the Cython extensions"""
    
    this_directory = os.path.dirname(__file__)
    this_name = __name__.split(".")[:-1]
    
    extension_args = {
        'include_dirs' : [this_directory] + ['numpy'] + get_zmq_include_path(),
        'libraries' : [],
        'sources' : []
    }
    extension_args.update(kwargs)
    
    
    extensions = []
    
    for component in glob.iglob(os.path.join(this_directory, "*.pyx")):
        # Component name and full module name.
        this_extension_args = copy.deepcopy(extension_args)
        cname = os.path.splitext(os.path.basename(component))[0]
        if cname.startswith("_"):
            cname = cname[1:]
            name = ".".join(this_name + ["_{0:s}".format(cname)])
        else:
            name = ".".join(this_name + [cname])
        this_extension_args['sources'].append(component)
        
        # Extension object.
        extension = Extension(name, **this_extension_args)
        extensions.append(extension)
    
    return extensions