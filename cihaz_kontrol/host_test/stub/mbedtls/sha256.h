#pragma once
#include <stddef.h>
#include <stdint.h>
#include "../../ref_crypto.h"

typedef struct { refcrypto::Sha256 s; } mbedtls_sha256_context;
inline void mbedtls_sha256_init(mbedtls_sha256_context* c) { c->s.init(); }
inline int mbedtls_sha256_starts_ret(mbedtls_sha256_context* c, int) { c->s.init(); return 0; }
inline int mbedtls_sha256_update_ret(mbedtls_sha256_context* c, const unsigned char* d, size_t n) { c->s.update(d, n); return 0; }
inline int mbedtls_sha256_finish_ret(mbedtls_sha256_context* c, unsigned char out[32]) { c->s.final(out); return 0; }
inline void mbedtls_sha256_free(mbedtls_sha256_context*) {}
