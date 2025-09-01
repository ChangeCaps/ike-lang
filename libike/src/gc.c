#include <ike/gc.h>

#include <stdlib.h>

void *ike_alloc(size_t size) {
    ike_alloc_t *alloc = malloc((sizeof *alloc) + size);
    alloc->rc          = 0;
    return &alloc->data;
}

void ike_copy(void *object) {
    ike_alloc_t *alloc = IKE_ALLOC(object);
    __atomic_fetch_add(&alloc->rc, 1, __ATOMIC_SEQ_CST);
}

bool ike_free(void *object) {
    ike_alloc_t *alloc = IKE_ALLOC(object);
    size_t       rc    = __atomic_fetch_sub(&alloc->rc, 1, __ATOMIC_SEQ_CST);

    if (rc == 0) {
        free(alloc);
    }

    return rc == 0;
}
