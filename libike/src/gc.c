#include <ike/gc.h>

#include <stdlib.h>

void *ike_alloc(size_t size) {
    ike_alloc_t *alloc = malloc((sizeof *alloc) + size);
    alloc->rc          = 0;
    return &alloc->data;
}

void ike_copy(void *ptr) {
    ike_alloc_t *alloc = IKE_ALLOC(ptr);
    __atomic_fetch_add(&alloc->rc, 1, __ATOMIC_SEQ_CST);
}

bool ike_is_unique(void *ptr) {
    ike_alloc_t *alloc = IKE_ALLOC(ptr);
    size_t       rc    = __atomic_load_n(&alloc->rc, __ATOMIC_SEQ_CST);

    return rc == 0;
}

bool ike_free(void *ptr) {
    ike_alloc_t *alloc = IKE_ALLOC(ptr);
    size_t       rc    = __atomic_fetch_sub(&alloc->rc, 1, __ATOMIC_SEQ_CST);

    if (rc == 0) {
        free(alloc);
    }

    return rc == 0;
}
