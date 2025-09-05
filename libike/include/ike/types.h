#pragma once

#include <ike/gc.h>

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <string.h>

typedef int64_t ike_int;
typedef bool    ike_bool;

typedef struct {
    size_t  length;
    uint8_t contents[];
} *ike_string;

typedef struct {
} ike_unit;

#define IKE_LIST(item)                                                         \
    struct {                                                                   \
        item  head;                                                            \
        void *tail;                                                            \
    } *

typedef struct {
    const void (*call)(void *input, void *output);
} ike_function_vtable;

typedef struct {
    const ike_function_vtable *vtable;

    size_t  remaining;
    void   *end;
    uint8_t input[];
} *ike_function;

inline static ike_string ike_string_new(const char *str) {
    size_t     length = strlen(str);
    ike_string output = ike_alloc((sizeof *output) + length + 1);
    memcpy(output->contents, str, length + 1);
    return output;
}

inline static void
ike_call(ike_function function, const void *input, size_t size, void *output) {
    function->end -= size;
    function->remaining--;
    memcpy(function->end, input, size);

    if (function->remaining == 0) {
        function->vtable->call(function->input, output);
    } else {
        *(ike_function *)output = function;
    }
}
