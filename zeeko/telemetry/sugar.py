# Python-level sugar for cdef classes.

import collections
from .recorder import Recorder as _Recorder
from .writer import Writer as _Writer

class Recorder(_Recorder, collections.MutableMapping):
    pass

class Writer(_Writer, collections.Mapping):
    pass