# Hash map implementation.
ctypedef unsigned long hashvalue
ctypedef int (*dealloc_callback)(void * ptr, void * data) nogil except -1

cdef object unsandwich_unicode(char * value, size_t length)
cdef bytes sandwich_unicode(object value)

cdef enum hashflags:
    HASHINIT = 1
    HASHWRITE = 2

ctypedef struct hashentry:
    hashvalue hvalue
    size_t length
    char * key
    void * value
    int flags

cdef class HashMap:
    cdef size_t n
    cdef size_t itemsize
    cdef hashentry * hashes
    cdef dealloc_callback _dcb
    cdef void * _dcb_data
    
    cdef int clear(self) nogil
    cdef int _clear_hashentry(self, hashentry * entry) nogil except -1
    cdef int _realloc(self) nogil except -1
    cdef int _allocate(self, size_t n) nogil except -1
    cdef hashentry * index_get(self, size_t index) nogil
    cdef hashentry * pyget(self, object keyv) except NULL
    cdef hashentry * get(self, char * data, size_t length) nogil except NULL
    cdef hashentry * insert(self, char * data, size_t length) nogil except NULL
    cdef int remove(self, char * data, size_t length) nogil except -1