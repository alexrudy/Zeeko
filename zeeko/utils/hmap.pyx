# Re-usable hash map for char * pointers.
import sys

from .rc cimport realloc, malloc, calloc
from libc.stdlib cimport free
from libc.string cimport strncpy, memcpy, memset
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
    
    def __cinit__(self, size_t itemsize):
        self.n = 0
        self.hashes = NULL
        self._dcb = NULL
        self._dcb_data = NULL
        self.itemsize = itemsize
        
    def __dealloc__(self):
        self.clear()
        
    def __len__(self):
        return self.n
    
    def __iter__(self):
        for i in range(self.n):
            yield unsandwich_unicode(self.hashes[i].key, self.hashes[i].length)
        
    def keys(self):
        return list(self)
        
    def add(self, keyv):
        cdef bytes key = sandwich_unicode(keyv)
        cdef size_t length = len(key)
        cdef hashentry * h = self.get(<char *>key, length)
        return
    
    def __repr__(self):
        return "HashMap({0!r})".format(self.keys())
        
    def __contains__(self, keyv):
        cdef bytes key = sandwich_unicode(keyv)
        cdef size_t length = len(key)
        cdef hashentry * h = self.get(key, length)
        return (h != NULL)
    
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
            if old_hashes[i].hvalue != 0:
                n += 1
            else:
                self._clear_hashentry(&old_hashes[i])
        
        j = 0
        new_hashes = <hashentry *>realloc(<void*>new_hashes, sizeof(hashentry) * n)
        for i in range(self.n):
            if old_hashes[i].hvalue != 0:
                new_hashes[j] = old_hashes[i]
                j += 1
        
        self.hashes = new_hashes
        self.n = n
        return self.n
        
    cdef int clear(self) nogil:
        cdef int i = 0
        if self.hashes != NULL:
            for i in range(self.n):
                self._clear_hashentry(&self.hashes[i])
            free(self.hashes)
        self.hashes = NULL
        self.n = 0
        return 0
    
    cdef int _clear_hashentry(self, hashentry * entry) nogil except -1:
        cdef int rc = 0
        entry.hvalue = 0
        if entry.key != NULL:
            free(entry.key)
        if entry.value != NULL:
            if self._dcb != NULL and (entry.flags & HASHINIT):
                self._dcb(entry.value, self._dcb_data)
            free(entry.value)
        return rc
        
    cdef int _allocate(self, size_t n) nogil except -1:
        cdef int i
        if n > self.n:
            self.hashes = <hashentry *>realloc(<void*>self.hashes, sizeof(hashentry) * n)
            for i in range(self.n, n):
                memset(&self.hashes[i], 0, sizeof(hashentry))
            self.n = n
        return 0
    
    cdef hashentry * index_get(self, size_t index) nogil:
        return &self.hashes[index]
    
    cdef hashentry * pyget(self, object keyv) except NULL:
        cdef bytes key = sandwich_unicode(keyv)
        cdef size_t length = len(key)
        return self.get(key, length)
    
    cdef hashentry * get(self, char * data, size_t length) nogil except NULL:
        cdef hashvalue value = hash_data(data, length)
        cdef int i
        for i in range(self.n):
            if self.hashes[i].hvalue == value:
                return &self.hashes[i]
        return self.insert(data, length)
        
    cdef hashentry * insert(self, char * data, size_t length) nogil except NULL:
        cdef hashvalue value = hash_data(data, length)
        cdef int rc = 0
        cdef size_t i = self.n
        rc = self._allocate(self.n + 1)
        
        self.hashes[i].hvalue = value
        
        self.hashes[i].key = <char *>calloc(length, sizeof(char))
        self.hashes[i].length = length
        strncpy(self.hashes[i].key, data, length)
        
        self.hashes[i].value = calloc(1, self.itemsize)
        self.hashes[i].flags = 0
        return &self.hashes[i]
        
    cdef int remove(self, char * data, size_t length) nogil except -1:
        cdef hashentry * h = self.get(data, length)
        if h == NULL:
            return -1
        self._realloc()
        return 0
        