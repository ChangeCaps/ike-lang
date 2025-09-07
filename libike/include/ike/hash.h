#pragma once

#include <ike/types.h>

inline static ike_int ike_hash_int(ike_int x) {
    x = ((x >> 16) ^ x) * 0x45d9f3b;
    x = ((x >> 16) ^ x) * 0x45d9f3b;
    x = (x >> 16) ^ x;
    return x;
}

inline static ike_int ike_hash_string(ike_string string) {
    uint64_t       hash  = 14695981039346656037ULL; // offset basis
    const uint64_t prime = 1099511628211ULL;        // FNV prime

    for (size_t i = 0; i < string->length; ++i) {
        hash *= prime;
        hash ^= string->contents[i];
    }

    return hash;
}
