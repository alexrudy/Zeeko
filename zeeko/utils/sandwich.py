# -*- coding: utf-8 -*-

import sys

__all__ = ['sandwich_unicdoe', 'unsandwich_unicode']

def sandwich_unicdoe(value):
    """Sandwich unicode values"""
    if isinstance(value, bytes):
        return value
    else:
        return value.encode('utf-8')

def unsandwich_unicode(value):
    """Unsandwich a bytestirng value."""
    if isinstance(value, bytes) and sys.version_info[0] > 2:
        return value.decode("utf-8")
    return value