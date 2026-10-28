// TEST ANAHTARI IMZALAYICISI - YALNIZ ANA MAKINE TESTLERI; uretimde kullanilmaz, firmware'e (include/) GIRMEZ.
// Ed25519 imzalama (RFC 8032 5.1.6), include/ota_ed25519.h'deki dahili cekirdek uzerine. Gizli anahtar islemi cihazda yoktur;
// bu dosya yalniz testlerin gecerli imza uretebilmesi icindir. Testler anahtarlari CALISMA ZAMANINDA bir etiketten turetir
// (anahtarCifti("etiket") -> SHA-256) ya da Node'un rastgele urettigi gecici tohumlari (imza_vectors.txt, git'e girmez) kullanir;
// depoda hicbir gizli anahtar bulunmaz.
#pragma once

#include <stdint.h>
#include <string.h>

#include <string>

#include "ota_ed25519.h"
#include "ref_crypto.h"

namespace ed_test {

// ota_public_key.h'in teslim edilen YER TUTUCU anahtari (ASCII, acik metin). Firmware'in ota_imza.h'inde bu acik metin BULUNMAZ (XOR'lu tablo
// tutulur; yayin oncesi ikili taramasi yanlis alarm vermesin diye) - testlerin karsilastirma/giris olarak kullanabilmesi icin burada.
inline const uint8_t YER_TUTUCU_DUZ[32] = {
  'O', 'T', 'A', '-', 'P', 'U', 'B', 'L', 'I', 'C', '-', 'K', 'E', 'Y', '-', 'N',
  'O', 'T', '-', 'S', 'E', 'T', '-', 'R', 'E', 'P', 'L', 'A', 'C', 'E', '!', '!',
};

// Tohum (32 bayt) -> genel anahtar (32 bayt)
inline void genelAnahtar(const uint8_t tohum[32], uint8_t genel[32]) {
  using namespace ota_ed25519::ic;
  uint8_t d[64];
  ota_ed25519::sha512(tohum, 32, d);
  d[0] &= 248;
  d[31] &= 127;
  d[31] |= 64;
  gf p[4];
  skalerTaban(p, d);
  nktPaketle(genel, p);
}

// Ed25519 imzasi (deterministik): imza = R || S
inline void imzala(const uint8_t tohum[32], const uint8_t* ileti, size_t n, uint8_t imza[64]) {
  using namespace ota_ed25519::ic;
  uint8_t d[64], h[64], r[64], genel[32];
  genelAnahtar(tohum, genel);
  ota_ed25519::sha512(tohum, 32, d);
  d[0] &= 248;
  d[31] &= 127;
  d[31] |= 64;

  Sha512 s;
  s.baslat();
  s.ekle(d + 32, 32);
  s.ekle(ileti, n);
  s.bitir(r);
  indirge(r);  // r = H(prefix || M) mod L
  gf p[4];
  skalerTaban(p, r);
  nktPaketle(imza, p);  // R = [r]B

  s.baslat();
  s.ekle(imza, 32);
  s.ekle(genel, 32);
  s.ekle(ileti, n);
  s.bitir(h);
  indirge(h);  // h = H(R || A || M) mod L

  int64_t x[64];
  for (int i = 0; i < 64; i++) {
    x[i] = 0;
  }
  for (int i = 0; i < 32; i++) {
    x[i] = static_cast<int64_t>(r[i]);
  }
  for (int i = 0; i < 32; i++) {
    for (int j = 0; j < 32; j++) {
      x[i + j] += static_cast<int64_t>(h[i]) * static_cast<int64_t>(d[j]);
    }
  }
  modL(imza + 32, x);  // S = (r + h*a) mod L
}

// Etiketten TEST anahtari: tohum = SHA-256("skp-ota-test-anahtari/" + etiket). Gizli degildir, rastgele degildir; yalniz testler icindir.
struct Anahtar {
  uint8_t tohum[32];
  uint8_t genel[32];
};

inline Anahtar anahtarCifti(const std::string& etiket) {
  Anahtar a;
  const std::string girdi = "skp-ota-test-anahtari/" + etiket;
  refcrypto::sha256(reinterpret_cast<const uint8_t*>(girdi.data()), girdi.size(), a.tohum);
  genelAnahtar(a.tohum, a.genel);
  return a;
}

}  // namespace ed_test
