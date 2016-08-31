# -*- coding: utf-8 -*-

import os
import glob
import copy
import sys

from distutils.core import Extension

from astropy_helpers import setup_helpers

def get_zmq_include_path():
    """Get the ZMQ include path in an import-safe manner."""
    try:
        import zmq
        return zmq.get_includes()
    except ImportError as e:
        return []

def get_zmq_library_path():
    """Get the ZMQ include path in an import-safe manner."""
    try:
        import zmq
        return [os.path.dirname(zmq.__file__)]
    except ImportError as e:
        return []

def get_zmq_extension_args():
    """Get the ZMQ Distutils Extension Args"""
    cfg = setup_helpers.DistutilsExtensionArgs()
    cfg['include_dirs'] = get_zmq_include_path()
    cfg['library_dirs'] = get_zmq_library_path()
    cfg['libraries'] = ['zmq']
    if not sys.platform.startswith(('darwin', 'freebsd')):
        cfg['libraries'].append("rt")
    
    if sys.platform.startswith('darwin'):
        cfg['extra_compile_args'] = ['-fsanitize=address', '-fsanitize=bounds', '-fsanitize-undefined-trap-on-error']
        cfg['extra_link_args'] = ['-fsanitize=address', '-fsanitize=bounds', '-fsanitize-undefined-trap-on-error']
    return cfg
    
def get_utils_extension_args():
    """Get utility module extension arguments"""
    directory = os.path.dirname(__file__)
    name = __name__.split(".")[:-1]
    cfg = setup_helpers.DistutilsExtensionArgs()
    cfg['include_dirs'] = [os.path.normpath(os.path.join(directory, "utils"))]
    return cfg
    
def _generate_cython_extensions(extension_args, directory, package_name):
    """Generate cython extensions"""
    
    for component in glob.iglob(os.path.join(directory, "*.pyx")):
        # Component name and full module name.
        cfg = setup_helpers.DistutilsExtensionArgs(copy.deepcopy(dict(**extension_args)))
        cname = os.path.splitext(os.path.basename(component))[0]
        cfg['sources'].append(component)
        
        pxd = os.path.splitext(component)[0] + ".pxd"
        
        if cname.startswith("_"):
            cname = cname[1:]
            name = ".".join(package_name + ["_{0:s}".format(cname)])
        else:
            name = ".".join(package_name + [cname])
        # Extension object.
        yield Extension(name, **cfg)
    