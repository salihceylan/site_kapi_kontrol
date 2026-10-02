// mbedtls/md.h sahtesinin TANIMLARI (tek cevirim biriminde bir kez include edilir).
#pragma once
#include "ref_crypto.h"
#include <mbedtls/md.h>

int g_hmac_mode = 0;
int g_hmac_calls = 0;
std::string g_hmac_last_key;
std::string g_hmac_last_msg;
int g_hmac_last_md_type = -1;

static mbedtls_md_info_t g_sha256_info = {MBEDTLS_MD_SHA256};

const mbedtls_md_info_t* mbedtls_md_info_from_type(mbedtls_md_type_t md_type) {
  g_hmac_last_md_type = static_cast<int>(md_type);
  if (g_hmac_mode == 3) {
    return nullptr;
  }
  return md_type == MBEDTLS_MD_SHA256 ? &g_sha256_info : nullptr;
}

int mbedtls_md_hmac(const mbedtls_md_info_t* md_info, const unsigned char* key, size_t keylen, const unsigned char* input, size_t ilen,
                    unsigned char* output) {
  g_hmac_calls += 1;
  g_hmac_last_key.assign(reinterpret_cast<const char*>(key), keylen);
  g_hmac_last_msg.assign(reinterpret_cast<const char*>(input), ilen);
  if (md_info == nullptr || md_info->id != MBEDTLS_MD_SHA256) {
    return -0x5100;  // MBEDTLS_ERR_MD_BAD_INPUT_DATA
  }
  if (g_hmac_mode == 1) {
    return -0x5080;  // MBEDTLS_ERR_MD_FEATURE_UNAVAILABLE
  }
  refcrypto::hmac_sha256(key, keylen, input, ilen, output);
  if (g_hmac_mode == 2) {
    output[31] ^= 0x01;
  }
  return 0;
}
