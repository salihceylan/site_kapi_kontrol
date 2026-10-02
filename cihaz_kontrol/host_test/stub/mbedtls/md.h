// Ana makine sahtesi: mbedtls/md.h (yalniz yerel_kontrol_cekirdek.h'in kullandigi API). Gercek HMAC yerine referans uygulama
// (ref_crypto.h) calisir; testler g_hmac_mode ile bozuk davranislari (hata / yanlis cikti / md_info yok) benzetebilir ve son cagrinin
// anahtar/mesaj baytlarini inceleyebilir (cagri bicimi: arguman sirasi, anahtar = token baytlari, mesaj = "action|UID|ch").
#pragma once
#include <stddef.h>
#include <stdint.h>
#include <string>

typedef struct mbedtls_md_info_t {
  int id;
} mbedtls_md_info_t;

typedef enum {
  MBEDTLS_MD_NONE = 0,
  MBEDTLS_MD_SHA256 = 6,
} mbedtls_md_type_t;

extern int g_hmac_mode;              // 0 dogru | 1 hata kodu dondur | 2 ciktinin son bitini boz | 3 md_info bulunamadi
extern int g_hmac_calls;
extern std::string g_hmac_last_key;  // son cagridaki anahtar baytlari
extern std::string g_hmac_last_msg;  // son cagridaki mesaj baytlari
extern int g_hmac_last_md_type;

const mbedtls_md_info_t* mbedtls_md_info_from_type(mbedtls_md_type_t md_type);
int mbedtls_md_hmac(const mbedtls_md_info_t* md_info, const unsigned char* key, size_t keylen, const unsigned char* input, size_t ilen,
                    unsigned char* output);
