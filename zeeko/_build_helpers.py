# -*- coding: utf-8 -*-

import os
import glob
import copy
import sys
import inspect

from distutils.core import Extension

from astropy_helpers import setup_helpers

pjoin = os.path.join
HERE = os.path.dirname(__file__)
BASE = pjoin("..", HERE)

def get_parent_module():
    """Get parent filename."""
    frame = inspect.currentframe()
    module = inspect.getmodule(frame)
    
    while module.__name__ == __name__:
        if frame.f_back is None:
            raise ValueError("Fell off the top of the stack.")
        frame = frame.f_back
        module = inspect.getmodule(frame)
    return module

def get_parent_filename():
    """Get parent module filename."""
    return os.path.relpath(get_parent_module().__file__)

def get_package_data():
    """A basic get-package-data."""
    package = ".".join(get_parent_module().__name__.split(".")[:-1])
    return {package:['*.pxd', '*.h']}

def module_to_path(module):
    """docstring for module_to_path"""
    base = BASE
    if module.startswith("."):
        base = os.path.relpath(os.path.dirname(get_parent_filename()))
        
    updirs = len(module) - len(module.lstrip(".")) - 1
    parts = ([ ".." ] * updirs) + module.lstrip(".").split(".")
    
    path = os.path.abspath(pjoin(base, *parts))
    return path

def pxd(module):
    """Return the path to a PXD file for a particular module."""
    return module_to_path(module) + ".pxd"
    
def pyx(module):
    """Return the path to a PYX file for a particular module."""
    return module_to_path(module) + ".pyx"

def h(module):
    """Return the path to an h file."""
    return module_to_path(module) + ".h"

def get_zmq_include_path():
    """Get the ZMQ include path in an import-safe manner."""
    try:
        import zmq
        includes = zmq.get_includes()
    except ImportError as e:
        includes = []
        if os.path.exists(pjoin(HERE, 'include')):
            includes += [ pjoin(HERE, 'include') ]
    return includes

def get_zmq_library_path():
    """Get the ZMQ include path in an import-safe manner."""
    try:
        import zmq
    except ImportError as e:
        pass
    else:
        ZMQDIR = os.path.dirname(zmq.__file__)
        if len(glob.glob(pjoin(ZMQDIR, 'libzmq.*'))):
            return [ZMQDIR]
        elif os.path.exists(pjoin(ZMQDIR,".libs")):
            return [pjoin(ZMQDIR,".libs")+os.path.sep]
    return []

def get_zmq_extension_args():
    """Get the ZMQ Distutils Extension Args"""
    cfg = setup_helpers.DistutilsExtensionArgs()
    cfg['include_dirs'] = get_zmq_include_path()
    cfg['library_dirs'] = get_zmq_library_path()
    cfg['runtime_library_dirs'] = get_zmq_library_path()
    cfg['libraries'] = ['zmq']
    if not (sys.platform.startswith('darwin') or sys.platform.startswith('freebsd')):
        cfg['libraries'].append("rt")
        cfg['libraries'].append("pthread")
    
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
    try:
        from Cython.Distutils import Extension as CyExtension
    except ImportError:
        extcls = Extension
    else:
        extcls = CyExtension
        extension_args['cython_directives'] = [("embedsignature", True)]
        extension_args['cython_directives'].append(("linetrace", True))
        extension_args['cython_directives'].append(("profile", True))
    
    if sys.platform == 'darwin' and os.environ.get("USE_ASAN","") == 'yes':
        extension_args['extra_compile_args'].extend(['-fsanitize=address', '-fno-omit-frame-pointer'])
        extension_args['extra_link_args'].extend(['-fsanitize=address'])
    
    if 'test' in sys.argv and ('-c' in sys.argv or '--coverage' in sys.argv):
        extension_args['define_macros'].append(("CYTHON_TRACE",1))
        # extension_args['define_macros'].append(("CYTHON_TRACE_NOGIL",1))
    
    for component in glob.iglob(os.path.join(directory, "*.pyx")):
        # Component name and full module name.
        cfg = setup_helpers.DistutilsExtensionArgs(copy.deepcopy(dict(**extension_args)))
        cname = os.path.splitext(os.path.basename(component))[0]
        cfg['sources'].append(component)
        
        component_pxd = os.path.splitext(component)[0] + ".pxd"
        
        if cname.startswith("_"):
            cname = cname[1:]
            name = ".".join(package_name + ["_{0:s}".format(cname)])
        else:
            name = ".".join(package_name + [cname])
        # Extension object.
        yield extcls(name, **cfg)
    