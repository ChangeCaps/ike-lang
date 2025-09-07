#pragma once

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

typedef struct ike_list *ike_list;

struct ike_list {
    ike_list tail;
    uint8_t  head[];
};

typedef void (*ike_function_vtable_call)(void *input, void *output);

typedef struct {
    const ike_function_vtable_call call;
    const size_t                   input_size;
} ike_function_vtable;

typedef struct {
    const ike_function_vtable *vtable;

    size_t  remaining;
    size_t  size;
    uint8_t input[];
} *ike_function;
