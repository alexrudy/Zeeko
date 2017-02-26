# -*- coding: utf-8 -*-

import sys

PY2 = (sys.version_info[0] == 2)

__all__ = ['sandwich_unicode', 'unsandwich_unicode']

def sandwich_unicode(value):
    """Sandwich unicode values"""
    if isinstance(value, bytes):
        return value
    else:
        return value.encode('utf-8')

def unsandwich_unicode(value):
    """Unsandwich a bytestirng value."""
    if isinstance(value, bytes) and not PY2:
        return value.decode("utf-8")
    return value