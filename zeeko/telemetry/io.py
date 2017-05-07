# -*- coding: utf-8 -*-
"""
Functions to handle HDF5 I/O for Chunks.

Since these all happen in python with the GIL (a limitation of H5py, they are implemented once here.)
"""

import numpy as np

class AxisSlicer(object):
    """A helper to slice along a single axis."""
    
    __slots__ = ('array', 'axis')
    
    def __init__(self, array, axis):
        super(AxisSlicer, self).__init__()
        self.array = array
        self.axis = axis
    
    def __getitem__(self, key):
        sl = [slice(None)] * self.array.ndim
        sl[self.axis] = key
        return self.array[tuple(sl)]
        
    def __setitem__(self, key, value):
        sl = [slice(None)] * self.array.ndim
        sl[self.axis] = key
        self.array[tuple(sl)] = value
    
    def __getattr__(self, attr):
        """Return attributes of the underlying array."""
        return getattr(self.array, attr)
        

def _append_from_array(h5dataset, array, cstop, truncate=False, axis=0):
    """Append to a dataset from an array."""
    dstart = h5dataset.shape[0]
    dstop = dstart + cstop
    h5dataset.resize(dstop, axis=axis)
    h5dataset[dstart:dstop] = array[0:cstop]
    if not truncate:
        h5dataset[dstart+cstop:] = 0.0
    

def _extend_ndim(chunk, h5group, truncate=False, axis=0):
    """Impelemntation for n-dimensional data."""
    
    h5data = h5group['data']
    h5mask = h5group['mask']
    
    if truncate:
        cstop = np.argmax(chunk.mask) + 1
    else:
        cstop = chunk.chunksize
    
    _append_from_array(AxisSlicer(h5data, axis), AxisSlicer(chunk.array, axis), cstop, truncate=truncate, axis=0)
    _append_from_array(h5mask, (chunk.mask != 0).astype(np.int), cstop, truncate=truncate, axis=0)
    
    return h5data.shape[0]

def extend(chunk, h5group, truncate=False, axis=0):
    """Extend the given dataset in the HDF5 file.
    
    :param chunk: The Chunk-api compliant object.
    :param h5group: The HDF5 group to target.
    :param truncate: Whether to truncate the dataset to only the filled items.
    """
    
    cstop = np.argmax(chunk.mask) + 1
    
    # We special case things when there is no size to the dataset.
    # TODO: There is a magic incantation to describe this special case in HDF5 natively. Do that.
    h5group.attrs['index'] = _extend_ndim(chunk, h5group, truncate=False, axis=axis)
    return 0

def initialize_group(chunk, h5group, axis=0):
    """Initialize groups to write this chunk"""
    shape = list(chunk.shape)
    shape.insert(axis, 0)
    shape = tuple(shape)
    
    maxshape = list(chunk.shape)
    for i,s in enumerate(chunk.shape):
        if s == 0:
            maxshape[i] = None
    maxshape.insert(axis, None)
    maxshape = tuple(maxshape)
    
    if any(s == 0 for s in chunk.shape):
        chunks = True
    else:
        chunks = list(chunk.shape)
        chunks.insert(axis, chunk.chunksize)
        chunks = tuple(chunks)
    
    # print("Shape: {0} Maxshape: {1} Chunks: {2}".format(shape, maxshape, chunks))
    
    d = h5group.create_dataset("data", 
        shape=shape,
        maxshape=maxshape,
        chunks=chunks,
        dtype=chunk.dtype,
        fillvalue=0.0)
        
    d.attrs['TAXIS'] = axis
    
    m = h5group.create_dataset("mask",
        shape=(0,),
        maxshape=(None,),
        chunks=(chunk.chunksize,),
        dtype=chunk.mask.dtype,
        fillvalue=0)
    
    m.attrs['TAXIS'] = 0
    h5group.attrs['index'] = 0

def write(chunk, h5group, truncate=False, axis=0, metadata=dict()):
    """Write the chunk to the given HDF5 group.
    
    :param chunk: The Chunk-api compliant object.
    :param h5group: The HDF5 group to target.
    :param truncate: Whether to truncate the dataset to only the filled items.
    """
    cstop = np.argmax(chunk.mask) + 1
    if chunk.name in h5group:
        g_sub = h5group[chunk.name]
    else:
        g_sub = h5group.create_group(chunk.name)
        initialize_group(chunk, g_sub, axis=axis)
    extend(chunk, g_sub, truncate=truncate, axis=axis)
    g_sub.attrs.update(metadata)
    