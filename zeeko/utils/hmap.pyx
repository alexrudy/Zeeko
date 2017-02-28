# Re-usable hash map for char * pointers.
import sys

from .rc cimport realloc, malloc
from libc.stdlib cimport free
from libc.string cimport strncpy, memcpy
from cpython.bytes cimport PyBytes_FromStringAndSize

cdef hashvalue hash_data(char * data, size_t length) nogil except -1:
    cdef hashvalue value = 5381
    cdef int i, c
    for i in range(length):
        c = <int>data[i]
        value = ((value << 5) + value) + c
    return value
    
cdef bytes sandwich_unicode(object value):
    if not isinstance(value, bytes):
         return value.encode('utf-8')
    return value
    
cdef object unsandwich_unicode(char * value, size_t length):
    cdef bytes pyvalue = PyBytes_FromStringAndSize(value, length)
    if sys.version_info[0] < 3:
        return pyvalue
    else:
        return pyvalue.decode('utf-8')
    
cdef class HashMap:
    """A slow, simple hash map for binary data to integer indicies"""
    
    def __cinit__(self):
        self.n = 0
        self.hashes = NULL
        
    def __dealloc__(self):
        self.clear()
        
    def __len__(self):
        return self.n
    
    def __iter__(self):
        for i in range(self.n):
            yield unsandwich_unicode(self.hashes[i].data, self.hashes[i].length)
        
    def keys(self):
        return list(self)
        
    def add(self, keyv):
        cdef bytes key = sandwich_unicode(keyv)
        cdef size_t length = len(key)
        cdef int rc = self.get(<char *>key, length)
        if rc == -1:
            rc = self.insert(<char *>key, length)
        return rc
    
    def __repr__(self):
        return "HashMap({0!r})".format(self.keys())
        
    def __getitem__(self, keyv):
        """Get the index for a single name."""
        cdef bytes key = sandwich_unicode(keyv)
        cdef size_t length = len(key)
        return self.lookup(<char *>key, length)
        
    def __contains__(self, keyv):
        cdef bytes key = sandwich_unicode(keyv)
        cdef size_t length = len(key)
        return self.get(key, length) >= 0
    
    def __delitem__(self, keyv):
        cdef bytes key = sandwich_unicode(keyv)
        cdef size_t length = len(key)
        cdef int rc = self.remove(key, length)
        if rc == -1:
            raise KeyError(keyv)
            
    cdef int _realloc(self) nogil except -1:
        cdef size_t i,j, n = 0
        cdef hashentry * old_hashes = self.hashes
        cdef hashentry * new_hashes = NULL
        
        for i in range(self.n):
            if old_hashes[i].value != 0:
                n += 1
        
        j = 0
        new_hashes = <hashentry *>realloc(<void*>new_hashes, sizeof(hashentry) * n)
        for i in range(self.n):
            if old_hashes[i].value != 0:
                new_hashes[j] = old_hashes[i]
                j += 1
        self.hashes = new_hashes
        self.n = n
        return self.n
        
    cdef int clear(self) nogil:
        if self.hashes != NULL:
            for i in range(self.n):
                if self.hashes[i].data != NULL:
                    free(self.hashes[i].data)
            free(self.hashes)
        self.hashes = NULL
        self.n = 0
        return 0
        
    cdef int _allocate(self, size_t n) nogil except -1:
        self.hashes = <hashentry *>realloc(<void*>self.hashes, sizeof(hashentry) * n)
        self.n = n
        return 0
        
    cdef void * reallocate(self, void * ptr, size_t sz) nogil except NULL:
        return realloc(ptr, sz * self.n)
        
    cdef int lookup(self, char * data, size_t length) nogil except -1:
        cdef hashvalue value = hash_data(data, length)
        cdef size_t i
        for i in range(self.n):
            if self.hashes[i].value == value:
                return i
        else:
            with gil:
                raise KeyError("Can't find a key with value {0}".format(
                    PyBytes_FromStringAndSize(data, length).decode('utf-8', 'backslashreplace')
                ))
        
    cdef int get(self, char * data, size_t length) nogil:
        cdef hashvalue value = hash_data(data, length)
        cdef int i
        for i in range(self.n):
            if self.hashes[i].value == value:
                return i
        return -1
        
    cdef int insert(self, char * data, size_t length) nogil except -1:
        cdef hashvalue value = hash_data(data, length)
        cdef int rc = 0
        cdef size_t i = self.n
        rc = self._allocate(self.n + 1)
        self.hashes[i].value = value
        self.hashes[i].data = <char *>malloc(length)
        self.hashes[i].length = length
        strncpy(self.hashes[i].data, data, length)
        return i
        
    cdef int remove(self, char * data, size_t length) nogil:
        cdef int i = self.get(data, length)
        if i == -1:
            return i
        self.hashes[i].value = 0
        self._realloc()
        return i
        