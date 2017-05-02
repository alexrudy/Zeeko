# -*- coding: utf-8 -*-

import sys

PY2 = (sys.version_info[0] == 2)

__all__ = ['sandwich_unicode', 'unsandwich_unicode']

def sandwich_unicode(value, encoding='utf-8'):
    """Sandwich unicode values.
    
    This function always returns bytes.
    """
    if isinstance(value, bytes):
        return value
    else:
        return value.encode(encoding)

def unsandwich_unicode(value, encoding='utf-8'):
    """Unsandwich a bytestirng value, returning
    the appropriate native string value."""
    if isinstance(value, bytes) and not PY2:
        return value.decode(encoding)
    return value