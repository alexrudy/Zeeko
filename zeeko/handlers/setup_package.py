# -*- coding: utf-8 -*-
from __future__ import absolute_import

import os

from zeeko._build_helpers import get_utils_extension_args, get_zmq_extension_args, _generate_cython_extensions, pxd, get_package_data
from astropy_helpers import setup_helpers

utilities = [pxd("..utils.rc"), 
             pxd("..utils.msg"), 
             pxd("..utils.pthread"), 
             pxd("..utils.lock"), 
             pxd("..utils.condition"), 
             pxd("..utils.clock")]

dependencies = {
    'base'    : utilities + [ pxd("..cyloop.throttle") ],
    'snail'   : utilities + [ pxd("..cyloop.throttle"), pxd("..cyloop.statemachine") ],
    'client'  : utilities + [ pxd("..cyloop.throttle"), pxd("..cyloop.statemachine"), pxd(".snail"), pxd(".base") ],
    'server'  : utilities + [ pxd("..cyloop.throttle"), pxd("..cyloop.statemachine"), pxd(".snail"), pxd(".base") ],
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