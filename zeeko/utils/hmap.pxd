# Hash map implementation.
ctypedef unsigned long hashvalue

ctypedef struct hashentry:
    hashvalue value
    char * data
    size_t length

cdef class HashMap:
    cdef size_t n
    cdef hashentry * hashes
    
    cdef int clear(self) nogil
    cdef int _allocate(self, size_t n) nogil except -1
    cdef void * reallocate(self, void * ptr, size_t sz) nogil except NULL
    cdef int get(self, char * data, size_t length) nogil except -1
    cdef int insert(self, char * data, size_t length) nogil except -1
    cdef int lookup(self, char * data, size_t length) nogil except -1
