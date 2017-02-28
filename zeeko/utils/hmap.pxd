# Hash map implementation.
ctypedef unsigned long hashvalue

cdef object unsandwich_unicode(char * value, size_t length)
cdef bytes sandwich_unicode(object value)

ctypedef struct hashentry:
    hashvalue value
    char * data
    size_t length

cdef class HashMap:
    cdef size_t n
    cdef hashentry * hashes
    
    cdef int clear(self) nogil
    cdef int _realloc(self) nogil except -1
    cdef int _allocate(self, size_t n) nogil except -1
    cdef void * reallocate(self, void * ptr, size_t sz) nogil except NULL
    cdef int get(self, char * data, size_t length) nogil
    cdef int insert(self, char * data, size_t length) nogil except -1
    cdef int lookup(self, char * data, size_t length) nogil except -1
    cdef int remove(self, char * data, size_t length) nogil