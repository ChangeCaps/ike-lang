#pragma once

#include <ike/gc.h>
#include <ike/types.h>

inline static void
ike_call(ike_function function, const void *input, size_t size, void *output) {
    ike_function copy = ike_alloc((sizeof *copy) + function->size + size);

    copy->vtable      = function->vtable;
    copy->remaining   = function->remaining - 1;
    copy->size        = function->size + size;

    memcpy(copy->input, function->input, function->size);
    memcpy(copy->input + function->size, input, size);

    if (copy->remaining == 0) {
        copy->vtable->call(copy->input, output);
    } else {
        *(ike_function *)output = copy;
    }
}
