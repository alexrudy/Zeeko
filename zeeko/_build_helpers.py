# -*- coding: utf-8 -*-

import os
import glob
import copy
import sys

from distutils.core import Extension

from astropy_helpers import setup_helpers

pjoin = os.path.join
HERE = os.path.dirname(__file__)

# ASAN_PATH = '/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/clang/8.0.0/lib/darwin/libclang_rt.asan_osx_dynamic.dylib'
# if os.path.exists(ASAN_PATH):
#     os.environ.setdefault('SHADY_USE_ASAN', 'yes')
#     os.environ.setdefault('DYLD_INSERT_LIBRARIES', ASAN_PATH)

def get_zmq_include_path():
    """Get the ZMQ include path in an import-safe manner."""
    try:
        import zmq
        includes = zmq.get_includes()
    except ImportError as e:
        includes = []
    if os.path.exists(pjoin(HERE, 'include')):
        return includes + [ pjoin(HERE, 'include') ]
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
    cfg['libraries'] = ['zmq']
    if not (sys.platform.startswith('darwin') or sys.platform.startswith('freebsd')):
        cfg['libraries'].append("rt")
    
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
    
    if sys.platform == 'darwin' and os.environ.get("SHADY_USE_ASAN","") == 'yes':
        extension_args['extra_compile_args'].extend(['-fsanitize=address', '-fno-omit-frame-pointer'])
        extension_args['extra_link_args'].extend(['-fsanitize=address'])
    
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
        yield Extension(name, **cfg)
    