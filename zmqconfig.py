# -*- coding: utf-8 -*-

import os
import sys
import distutils
import errno
import platform
from itertools import chain
import functools

from glob import glob

import subprocess
from subprocess import Popen, check_call, CalledProcessError

from os.path import exists, join as pjoin

import distutils
from distutils import log
warn = log.warn
info = log.info

HERE = os.path.dirname(__file__)

def get_zmq_config():
    """Get ZeroMQ config"""
    try:
        import zmq
    except ImportError as e:
        pass
    else:
        compiler_json = pjoin(os.path.dirname(zmq.__file__), 'utils', 'compiler.json')
        try:
            import json
            with open(compiler_json, 'r') as f:
                config = json.loads(f.read())
        except (ValueError, IOError, OSError):
            pass
    return {}
    
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
        if len(glob(pjoin(ZMQDIR, 'libzmq.*'))):
            return [ZMQDIR]
        elif os.path.exists(pjoin(ZMQDIR,".libs")):
            return [pjoin(ZMQDIR,".libs")+os.path.sep]
    return []

def unix_libname(name):
    if name.startswith("lib"):
        return name[3:]
    return name

def bundled_settings(debug, libzmq_name='libzmq'):
    """settings for linking extensions against bundled libzmq"""
    settings = {}
    settings['libraries'] = []
    settings['library_dirs'] = get_zmq_library_path()
    settings['include_dirs'] = get_zmq_include_path()
    settings['runtime_library_dirs'] = get_zmq_library_path()
    # add pthread on freebsd
    # is this necessary?
    if sys.platform.startswith('freebsd'):
        settings['libraries'].append(unix_libname(libzmq_name))
        settings['libraries'].append('pthread')
    elif sys.platform.startswith('win'):
        suffix = ''
        if sys.version_info >= (3,5):
            # Python 3.5 adds EXT_SUFFIX to libs
            ext_suffix = distutils.sysconfig.get_config_var('EXT_SUFFIX')
            suffix = os.path.splitext(ext_suffix)[0]

        if debug:
            suffix = '_d' + suffix

        settings['libraries'].append(libzmq_name + suffix)
    else:
        settings['libraries'].append(unix_libname(libzmq_name))
    return settings

def check_pkgconfig(libzmq_name='libzmq'):
    """ pull compile / link flags from pkg-config if present. """
    pcfg = None
    zmq_config = None
    try:
        check_call(['pkg-config', '--exists', 'libzmq'])
        # this would arguably be better with --variable=libdir /
        # --variable=includedir, but would require multiple calls
        pcfg = Popen(['pkg-config', '--libs', '--cflags', 'libzmq'],
                     stdout=subprocess.PIPE)
    except OSError as osexception:
        if osexception.errno == errno.ENOENT:
            info('pkg-config not found')
        else:
            warn("Running pkg-config failed - %s." % osexception)
    except CalledProcessError:
        info("Did not find libzmq via pkg-config.")

    if pcfg is not None:
        output, _ = pcfg.communicate()
        output = output.decode('utf8', 'replace')
        bits = output.strip().split()
        zmq_config = {'library_dirs':[], 'include_dirs':[], 'libraries':[]}
        for tok in bits:
            if tok.startswith("-L"):
                zmq_config['library_dirs'].append(tok[2:])
            if tok.startswith("-I"):
                zmq_config['include_dirs'].append(tok[2:])
            if tok.startswith("-l"):
                zmq_config['libraries'].append(tok[2:])
        info("Settings obtained from pkg-config: %r" % zmq_config)

    return zmq_config

def settings_from_prefix(prefix=None, bundle_libzmq_dylib=False, libzmq_name='libzmq'):
    """load appropriate library/include settings from ZMQ prefix"""
    settings = {}
    settings['libraries'] = []
    settings['library_dirs'] = get_zmq_library_path()
    settings['include_dirs'] = get_zmq_include_path()
    settings['runtime_library_dirs'] = get_zmq_library_path()
    settings['extra_link_args'] = [] 
    
    if sys.platform.startswith('win'):
        settings['libraries'].append(libzmq_name)
        
        if prefix:
            settings['include_dirs'] += [pjoin(prefix, 'include')]
            settings['library_dirs'] += [pjoin(prefix, 'lib')]
    else:
        # add pthread on freebsd
        if sys.platform.startswith('freebsd'):
            settings['libraries'].append('pthread')

        if sys.platform.startswith('sunos'):
          if platform.architecture()[0] == '32bit':
            settings['extra_link_args'] += ['-m32']
          else:
            settings['extra_link_args'] += ['-m64']

        if prefix:
            settings['libraries'].append(unix_libname(libzmq_name))

            settings['include_dirs'] += [pjoin(prefix, 'include')]
            if not bundle_libzmq_dylib:
                if sys.platform.startswith('sunos') and platform.architecture()[0] == '64bit':
                    settings['library_dirs'] += [pjoin(prefix, 'lib/amd64')]
                settings['library_dirs'] += [pjoin(prefix, 'lib')]
        else:
            # If prefix is not explicitly set, pull it from pkg-config by default.
            # this is probably applicable across platforms, but i don't have
            # sufficient test environments to confirm
            pkgcfginfo = check_pkgconfig()
            if pkgcfginfo is not None:
                # we can get all the zmq-specific values from pkgconfg
                for key, value in pkgcfginfo.items():
                    settings[key].extend(value)
            else:
                settings['libraries'].append(unix_libname(libzmq_name))

                if sys.platform == 'darwin' and os.path.isdir('/opt/local/lib'):
                    # allow macports default
                    settings['include_dirs'] += ['/opt/local/include']
                    settings['library_dirs'] += ['/opt/local/lib']
                if os.environ.get('VIRTUAL_ENV', None):
                    # find libzmq installed in virtualenv
                    env = os.environ['VIRTUAL_ENV']
                    settings['include_dirs'] += [pjoin(env, 'include')]
                    settings['library_dirs'] += [pjoin(env, 'lib')]

        if bundle_libzmq_dylib:
            # bdist should link against bundled libzmq
            settings['library_dirs'].append(unix_libname(libzmq_name))
            if sys.platform == 'darwin':
                pass
                # unused rpath args for OS X:
                # settings['extra_link_args'] = ['-Wl,-rpath','-Wl,$ORIGIN/..']
            else:
                settings['runtime_library_dirs'] += ['$ORIGIN/..']
        elif sys.platform != 'darwin':
            info("%r" % settings)
            settings['runtime_library_dirs'] += [
                os.path.abspath(x) for x in settings['library_dirs']
            ]
    
    return settings

_libzmq_settings = {}
def libzmq_settings(debug=False, libzmq_name='libzmq', zmq_prefix=None):
    """Return libzmq settings"""
    global _libzmq_settings
    try:
        return _libzmq_settings[(debug, libzmq_name, zmq_prefix)]
    except KeyError:
        settings = get_zmq_config()
        if settings:
            return settings
        if any(chain(glob(pjoin(p, 'libzmq.*')) for p in get_zmq_library_path())):
            settings = bundled_settings(debug)
        else:
            settings = settings_from_prefix(zmq_prefix, bundle_libzmq_dylib=False, libzmq_name=libzmq_name)
        _libzmq_settings[(debug, libzmq_name, zmq_prefix)] = settings
        return settings