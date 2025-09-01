#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

typedef struct ike_alloc {
    size_t  rc;
    uint8_t data[];
} ike_alloc_t;

#define IKE_ALLOC(object)                                                      \
    ((ike_alloc_t *)(object - offsetof(ike_alloc_t, data)))

void *ike_alloc(size_t size);
void  ike_copy(void *object);
bool  ike_free(void *object);
