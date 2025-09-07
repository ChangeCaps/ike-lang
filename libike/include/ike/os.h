#pragma once

#include <ike/gc.h>
#include <ike/string.h>
#include <ike/types.h>

#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>

typedef struct {
    ike_int    code;
    ike_string output;
} *ike_os_status;

typedef struct {
    ike_int discriminant;

    union {
        ike_os_status status;
        ike_string    error;
    };
} *ike_os_execute_result;

inline static void ike_os_exit(ike_int code) { exit(code); }

inline static ike_os_execute_result ike_os_execute(ike_list args) {
    ike_os_execute_result result = ike_alloc(sizeof *result);

    size_t args_length           = 0;

    ike_list it                  = args;
    while (it) {
        ike_string head = *(ike_string *)it->head;
        it              = it->tail;

        args_length += head->length + 1;
    }

    char  *command = malloc(args_length);
    size_t offset  = 0;

    it             = args;
    while (it) {
        ike_string head = *(ike_string *)it->head;
        it              = it->tail;

        memcpy(command + offset, head->contents, head->length);

        if (it) {
            command[offset + head->length] = ' ';
        }

        offset += head->length + 1;
    }

    command[args_length] = '\0';

    FILE *pipe           = popen(command, "r");

    free(command);

    if (!pipe) {
        result->discriminant = 1;
        result->error        = ike_string_new("failed to run command");
        return result;
    }

    size_t size     = 0;
    size_t capacity = 1024;
    char  *output   = malloc(capacity);
    output[0]       = '\0';

    char buffer[256];
    while (fgets(buffer, (sizeof buffer), pipe)) {
        size_t len = strlen(buffer);

        if (size + len + 1 > capacity) {
            capacity *= 2;
            output = realloc(output, capacity);
        }

        memcpy(output + size, buffer, len);
        size += len;
        output[size] = '\0';
    }

    ike_int code           = pclose(pipe);

    result->discriminant   = 0;
    result->status         = ike_alloc(sizeof *result->status);
    result->status->output = ike_string_new(output);
    result->status->code   = code;

    free(output);

    return result;
}
