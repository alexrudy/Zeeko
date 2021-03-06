# -*- coding: utf-8 -*-
from __future__ import absolute_import

import glob
import os
import copy

from zeeko._build_helpers import get_zmq_extension_args, _generate_cython_extensions, pxd, h, get_package_data
from astropy_helpers import setup_helpers

def get_extensions(**kwargs):
    """Get the Cython extensions"""
    
    extension_args = setup_helpers.DistutilsExtensionArgs()
    extension_args.update(get_zmq_extension_args())    
    package_name = __name__.split(".")[:-1]
    extensions = [e for e in _generate_cython_extensions(extension_args, os.path.dirname(__file__), package_name)]
    return extensions
    