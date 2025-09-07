#pragma once

#include <ike/gc.h>
#include <ike/string.h>
#include <ike/types.h>

#include <stdio.h>
#include <stdlib.h>

typedef struct {
    ike_int discriminant;

    union {
        ike_string contents;
        ike_string error;
    };
} *ike_fs_read_result;

typedef struct {
    ike_int discriminant;

    union {
        ike_unit   unit;
        ike_string error;
    };
} *ike_fs_write_result;

inline static ike_fs_read_result ike_fs_read(ike_string path) {
    ike_fs_read_result result = ike_alloc(sizeof *result);

    FILE *file                = fopen((const char *)path->contents, "r");

    if (!file) {
        result->discriminant = 1;
        result->error        = ike_string_new("failed to read file");
    }

    size_t size     = 0;
    size_t capacity = 1024;
    char  *output   = malloc(capacity);
    output[0]       = '\0';

    char buffer[256];
    while (fgets(buffer, (sizeof buffer), file)) {
        size_t len = strlen(buffer);

        if (size + len + 1 > capacity) {
            capacity *= 2;
            output = realloc(output, capacity);
        }

        memcpy(output + size, buffer, len);
        size += len;
        output[size] = '\0';
    }

    fclose(file);

    result->discriminant = 0;
    result->contents     = ike_string_new(output);

    free(output);

    return result;
}

inline static ike_fs_write_result
ike_fs_write(ike_string path, ike_string contents) {
    ike_fs_write_result result = ike_alloc(sizeof *result);

    FILE *file                 = fopen((const char *)path->contents, "r");

    if (!file) {
        result->discriminant = 1;
        result->error        = ike_string_new("failed to read file");
    }

    fwrite(contents->contents, sizeof(char), contents->length, file);

    result->discriminant = 0;

    return result;
}
