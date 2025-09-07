#pragma once

#include <ike/gc.h>
#include <ike/types.h>

#include <stdio.h>

inline static ike_string ike_string_new(const char *str) {
    size_t     length = strlen(str);
    ike_string output = ike_alloc((sizeof *output) + length + 1);
    output->length    = length;
    memcpy(output->contents, str, length + 1);
    return output;
}

inline static ike_string ike_string_append(ike_string lhs, const char *rhs) {
    size_t     rhs_length = strlen(rhs);
    size_t     length     = lhs->length + rhs_length;
    ike_string output     = ike_alloc((sizeof *output) + length + 1);
    output->length        = length;
    memcpy(output->contents, lhs->contents, lhs->length);
    memcpy(output->contents + lhs->length, rhs, rhs_length);
    output->contents[length] = '\0';
    return output;
}

inline static ike_string ike_string_concat(ike_string lhs, ike_string rhs) {
    size_t     length = lhs->length + rhs->length;
    ike_string output = ike_alloc((sizeof *output) + length + 1);
    output->length    = length;
    memcpy(output->contents, lhs->contents, lhs->length);
    memcpy(output->contents + lhs->length, rhs->contents, rhs->length);
    output->contents[length] = '\0';

    ike_free(lhs);
    ike_free(rhs);

    return output;
}

inline static ike_string ike_string_concat_n(ike_string strings[], size_t n) {
    size_t length = 0;

    for (size_t i = 0; i < n; i++) {
        length += strings[i]->length;
    }

    ike_string output = ike_alloc((sizeof *output) + length + 1);
    output->length    = length;

    size_t offset     = 0;

    for (size_t i = 0; i < n; i++) {
        memcpy(
            output->contents + offset,
            strings[i]->contents,
            strings[i]->length
        );

        offset += strings[i]->length;

        ike_free(strings[i]);
    }

    output->contents[length] = '\0';

    return output;
}

inline static ike_string ike_format_int(ike_int value) {
    size_t     length = snprintf(NULL, 0, "%li", value);
    ike_string output = ike_alloc((sizeof *output) + length + 1);
    output->length    = length;
    sprintf((char *)output->contents, "%li", value);
    return output;
}

inline static ike_string ike_format_bool(ike_bool value) {
    if (value) {
        return ike_string_new("true");
    } else {
        return ike_string_new("false");
    }
}
