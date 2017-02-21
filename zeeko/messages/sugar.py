# Python-level sugar for cdef classes.

import collections
from .publisher import Publisher as _Publisher
from .receiver import Receiver as _Receiver

class Publisher(_Publisher, collections.MutableMapping):
    pass

class Receiver(_Receiver, collections.Mapping):
    pass