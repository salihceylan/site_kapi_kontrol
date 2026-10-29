#ifndef OTA_ED25519_H
#define OTA_ED25519_H

// Ed25519 (RFC 8032) IMZA DOGRULAMA - SmartKeyPass OTA, cihaz tarafi.
//
// ARDUINO BAGIMSIZ: yalniz <stddef.h> / <stdint.h> / <string.h>. Ana makinede (cihaz_kontrol/host_test) AYNEN derlenir; RFC 8032 vektorleri
// ve Node crypto (OpenSSL) ile uretilen rastgele imzalarla capraz dogrulanir. GIZLI ANAHTAR ISLEMI (imzalama) CIHAZDA YOKTUR: bu dosyada
// yalniz dogrulama vardir; imzalayici yalnizca testlerdedir (host_test/ed25519_test_imzalayici.h) ve firmware'e girmez.
//
// KAYNAK VE LISANS
//   Alan aritmetigi (GF(2^255-19), 16 x 16 bit uzuv), Edwards egrisi nokta islemleri, mod L indirgeme ve SHA-512 cekirdegi
//   TweetNaCl'den (Daniel J. Bernstein, Wesley Janssen, Tanja Lange, Peter Schwabe; https://tweetnacl.cr.yp.to/ , surum 20140427)
//   uyarlanmistir. TweetNaCl PUBLIC DOMAIN'dir (telif/lisans kisiti yok); bu uyarlama da kisitsiz kullanilabilir.
//   Uyarlamada yapilanlar: C++17 ve <stdint.h> tipleri; yalniz dogrulama + testlerin imzalayici icin ihtiyac duydugu temel islemler;
//   SHA-512 AKISLI (R || A || M parcalar halinde beslenir, birlestirme tamponu yok); negatif degerlerin sola kaydirilmasi (tanimsiz
//   davranis) carpmaya cevrildi; RFC 8032 5.1.7 geregi S < L denetimi (imza bicim esnekligi/malleability kapatildi); kanonik olmayan
//   ya da kucuk mertebeli (zayif) genel anahtarin reddi eklendi.
//
// Zamanlama notu: dogrulama yalnizca HERKESE ACIK veriyi (imza, genel anahtar, ileti) isler; sabit zamanli olmasi gerekmez.
// Bellek: calisma alani (~1,9 KB: 3 nokta + SHA-512 baglami) malloc ile ayrilir (ayrilamazsa dogrulama BASARISIZ sayilir); en derin yigin
// zinciri ~1,7 KB (nktEkle 9 gf = 1,2 KB + gfM 0,3 KB) - ESP32 loop gorevinin 8 KB'lik yigini TLS indirme zinciriyle zaten derindir.
// Sure: ESP32 / ESP32-C3'te bir dogrulama ~0,3-1,5 sn (2 skaler carpim); cagiran watchdog'u besler.

#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

namespace ota_ed25519 {

inline constexpr size_t IMZA_BOYUT = 64;
inline constexpr size_t ANAHTAR_BOYUT = 32;

// ---------------------------------------------------------------------------------------------------------------------------------
// Dahili cekirdek (TweetNaCl uyarlamasi). `ic` = dahili; yalniz test imzalayicisi disaridan kullanir.
// ---------------------------------------------------------------------------------------------------------------------------------
namespace ic {

typedef int64_t gf[16];

inline constexpr int64_t kGf0[16] = {0};
inline constexpr int64_t kGf1[16] = {1};
inline constexpr int64_t kD[16] = {0x78a3, 0x1359, 0x4dca, 0x75eb, 0xd8ab, 0x4141, 0x0a4d, 0x0070,
                                   0xe898, 0x7779, 0x4079, 0x8cc7, 0xfe73, 0x2b6f, 0x6cee, 0x5203};
inline constexpr int64_t kD2[16] = {0xf159, 0x26b2, 0x9b94, 0xebd6, 0xb156, 0x8283, 0x149a, 0x00e0,
                                    0xd130, 0xeef3, 0x80f2, 0x198e, 0xfce7, 0x56df, 0xd9dc, 0x2406};
inline constexpr int64_t kX[16] = {0xd51a, 0x8f25, 0x2d60, 0xc956, 0xa7b2, 0x9525, 0xc760, 0x692c,
                                   0xdc5c, 0xfdd6, 0xe231, 0xc0a4, 0x53fe, 0xcd6e, 0x36d3, 0x2169};
inline constexpr int64_t kY[16] = {0x6658, 0x6666, 0x6666, 0x6666, 0x6666, 0x6666, 0x6666, 0x6666,
                                   0x6666, 0x6666, 0x6666, 0x6666, 0x6666, 0x6666, 0x6666, 0x6666};
inline constexpr int64_t kKok1[16] = {0xa0b0, 0x4a0e, 0x1b27, 0xc4ee, 0xe478, 0xad2f, 0x1806, 0x2f43,
                                      0xd7a7, 0x3dfb, 0x0099, 0x2b4d, 0xdf0b, 0x4fc1, 0x2480, 0x2b83};  // sqrt(-1)

// Grup mertebesi L = 2^252 + 27742317777372353535851937790883648493 (kucuk uclu)
inline constexpr uint8_t kL[32] = {0xed, 0xd3, 0xf5, 0x5c, 0x1a, 0x63, 0x12, 0x58, 0xd6, 0x9c, 0xf7, 0xa2, 0xde, 0xf9, 0xde, 0x14,
                                   0,    0,    0,    0,    0,    0,    0,    0,    0,    0,    0,    0,    0,    0,    0,    0x10};

// Esitse 0, degilse -1 (32 bayt)
inline int esitDegil32(const uint8_t* x, const uint8_t* y) {
  uint32_t d = 0;
  for (int i = 0; i < 32; i++) {
    d |= static_cast<uint32_t>(x[i] ^ y[i]);
  }
  return static_cast<int>(1 & ((d - 1) >> 8)) - 1;
}

inline void set25519(gf r, const int64_t* a) {
  for (int i = 0; i < 16; i++) {
    r[i] = a[i];
  }
}

inline void car25519(gf o) {
  for (int i = 0; i < 16; i++) {
    o[i] += static_cast<int64_t>(1) << 16;
    const int64_t c = o[i] >> 16;
    o[(i + 1) * (i < 15)] += c - 1 + 37 * (c - 1) * (i == 15);
    o[i] -= c * 65536;  // (c << 16): negatif c icin tanimsiz davranis olmasin diye carpma
  }
}

inline void sel25519(gf p, gf q, int b) {
  const int64_t c = ~static_cast<int64_t>(b - 1);
  for (int i = 0; i < 16; i++) {
    const int64_t t = c & (p[i] ^ q[i]);
    p[i] ^= t;
    q[i] ^= t;
  }
}

inline void pack25519(uint8_t* o, const int64_t* n) {
  int i, j, b;
  gf m, t;
  for (i = 0; i < 16; i++) {
    t[i] = n[i];
  }
  car25519(t);
  car25519(t);
  car25519(t);
  for (j = 0; j < 2; j++) {
    m[0] = t[0] - 0xffed;
    for (i = 1; i < 15; i++) {
      m[i] = t[i] - 0xffff - ((m[i - 1] >> 16) & 1);
      m[i - 1] &= 0xffff;
    }
    m[15] = t[15] - 0x7fff - ((m[14] >> 16) & 1);
    b = static_cast<int>((m[15] >> 16) & 1);
    m[14] &= 0xffff;
    sel25519(t, m, 1 - b);
  }
  for (i = 0; i < 16; i++) {
    o[2 * i] = static_cast<uint8_t>(t[i] & 0xff);
    o[2 * i + 1] = static_cast<uint8_t>(t[i] >> 8);
  }
}

inline int neq25519(const int64_t* a, const int64_t* b) {
  uint8_t c[32], d[32];
  pack25519(c, a);
  pack25519(d, b);
  return esitDegil32(c, d);
}

inline uint8_t par25519(const int64_t* a) {
  uint8_t d[32];
  pack25519(d, a);
  return static_cast<uint8_t>(d[0] & 1);
}

inline void unpack25519(gf o, const uint8_t* n) {
  for (int i = 0; i < 16; i++) {
    o[i] = n[2 * i] + (static_cast<int64_t>(n[2 * i + 1]) << 8);
  }
  o[15] &= 0x7fff;
}

inline void gfA(gf o, const int64_t* a, const int64_t* b) {
  for (int i = 0; i < 16; i++) {
    o[i] = a[i] + b[i];
  }
}

inline void gfZ(gf o, const int64_t* a, const int64_t* b) {
  for (int i = 0; i < 16; i++) {
    o[i] = a[i] - b[i];
  }
}

inline void gfM(gf o, const int64_t* a, const int64_t* b) {
  int64_t t[31];
  for (int i = 0; i < 31; i++) {
    t[i] = 0;
  }
  for (int i = 0; i < 16; i++) {
    for (int j = 0; j < 16; j++) {
      t[i + j] += a[i] * b[j];
    }
  }
  for (int i = 0; i < 15; i++) {
    t[i] += 38 * t[i + 16];
  }
  for (int i = 0; i < 16; i++) {
    o[i] = t[i];
  }
  car25519(o);
  car25519(o);
}

inline void gfS(gf o, const int64_t* a) {
  gfM(o, a, a);
}

inline void inv25519(gf o, const int64_t* in) {
  gf c;
  for (int a = 0; a < 16; a++) {
    c[a] = in[a];
  }
  for (int a = 253; a >= 0; a--) {
    gfS(c, c);
    if (a != 2 && a != 4) {
      gfM(c, c, in);
    }
  }
  for (int a = 0; a < 16; a++) {
    o[a] = c[a];
  }
}

inline void pow2523(gf o, const int64_t* in) {
  gf c;
  for (int a = 0; a < 16; a++) {
    c[a] = in[a];
  }
  for (int a = 250; a >= 0; a--) {
    gfS(c, c);
    if (a != 1) {
      gfM(c, c, in);
    }
  }
  for (int a = 0; a < 16; a++) {
    o[a] = c[a];
  }
}

// ---- SHA-512 (FIPS 180-4), akisli ------------------------------------------------------------------------------------------------
inline constexpr uint64_t kK512[80] = {
  0x428a2f98d728ae22ULL, 0x7137449123ef65cdULL, 0xb5c0fbcfec4d3b2fULL, 0xe9b5dba58189dbbcULL, 0x3956c25bf348b538ULL,
  0x59f111f1b605d019ULL, 0x923f82a4af194f9bULL, 0xab1c5ed5da6d8118ULL, 0xd807aa98a3030242ULL, 0x12835b0145706fbeULL,
  0x243185be4ee4b28cULL, 0x550c7dc3d5ffb4e2ULL, 0x72be5d74f27b896fULL, 0x80deb1fe3b1696b1ULL, 0x9bdc06a725c71235ULL,
  0xc19bf174cf692694ULL, 0xe49b69c19ef14ad2ULL, 0xefbe4786384f25e3ULL, 0x0fc19dc68b8cd5b5ULL, 0x240ca1cc77ac9c65ULL,
  0x2de92c6f592b0275ULL, 0x4a7484aa6ea6e483ULL, 0x5cb0a9dcbd41fbd4ULL, 0x76f988da831153b5ULL, 0x983e5152ee66dfabULL,
  0xa831c66d2db43210ULL, 0xb00327c898fb213fULL, 0xbf597fc7beef0ee4ULL, 0xc6e00bf33da88fc2ULL, 0xd5a79147930aa725ULL,
  0x06ca6351e003826fULL, 0x142929670a0e6e70ULL, 0x27b70a8546d22ffcULL, 0x2e1b21385c26c926ULL, 0x4d2c6dfc5ac42aedULL,
  0x53380d139d95b3dfULL, 0x650a73548baf63deULL, 0x766a0abb3c77b2a8ULL, 0x81c2c92e47edaee6ULL, 0x92722c851482353bULL,
  0xa2bfe8a14cf10364ULL, 0xa81a664bbc423001ULL, 0xc24b8b70d0f89791ULL, 0xc76c51a30654be30ULL, 0xd192e819d6ef5218ULL,
  0xd69906245565a910ULL, 0xf40e35855771202aULL, 0x106aa07032bbd1b8ULL, 0x19a4c116b8d2d0c8ULL, 0x1e376c085141ab53ULL,
  0x2748774cdf8eeb99ULL, 0x34b0bcb5e19b48a8ULL, 0x391c0cb3c5c95a63ULL, 0x4ed8aa4ae3418acbULL, 0x5b9cca4f7763e373ULL,
  0x682e6ff3d6b2b8a3ULL, 0x748f82ee5defb2fcULL, 0x78a5636f43172f60ULL, 0x84c87814a1f0ab72ULL, 0x8cc702081a6439ecULL,
  0x90befffa23631e28ULL, 0xa4506cebde82bde9ULL, 0xbef9a3f7b2c67915ULL, 0xc67178f2e372532bULL, 0xca273eceea26619cULL,
  0xd186b8c721c0c207ULL, 0xeada7dd6cde0eb1eULL, 0xf57d4f7fee6ed178ULL, 0x06f067aa72176fbaULL, 0x0a637dc5a2c898a6ULL,
  0x113f9804bef90daeULL, 0x1b710b35131c471bULL, 0x28db77f523047d84ULL, 0x32caab7b40c72493ULL, 0x3c9ebe0a15c9bebcULL,
  0x431d67c49c100d4cULL, 0x4cc5d4becb3e42b6ULL, 0x597f299cfc657e2aULL, 0x5fcb6fab3ad6faecULL, 0x6c44198c4a475817ULL};

inline constexpr uint64_t kIv512[8] = {0x6a09e667f3bcc908ULL, 0xbb67ae8584caa73bULL, 0x3c6ef372fe94f82bULL, 0xa54ff53a5f1d36f1ULL,
                                       0x510e527fade682d1ULL, 0x9b05688c2b3e6c1fULL, 0x1f83d9abfb41bd6bULL, 0x5be0cd19137e2179ULL};

inline uint64_t sagaDondur64(uint64_t x, int c) {
  return (x >> c) | (x << (64 - c));
}
inline uint64_t shaCh(uint64_t x, uint64_t y, uint64_t z) {
  return (x & y) ^ (~x & z);
}
inline uint64_t shaMaj(uint64_t x, uint64_t y, uint64_t z) {
  return (x & y) ^ (x & z) ^ (y & z);
}
inline uint64_t shaSigma0(uint64_t x) {
  return sagaDondur64(x, 28) ^ sagaDondur64(x, 34) ^ sagaDondur64(x, 39);
}
inline uint64_t shaSigma1(uint64_t x) {
  return sagaDondur64(x, 14) ^ sagaDondur64(x, 18) ^ sagaDondur64(x, 41);
}
inline uint64_t shaKucukSigma0(uint64_t x) {
  return sagaDondur64(x, 1) ^ sagaDondur64(x, 8) ^ (x >> 7);
}
inline uint64_t shaKucukSigma1(uint64_t x) {
  return sagaDondur64(x, 19) ^ sagaDondur64(x, 61) ^ (x >> 6);
}

inline uint64_t buyukUcluOku64(const uint8_t* x) {
  uint64_t u = 0;
  for (int i = 0; i < 8; i++) {
    u = (u << 8) | x[i];
  }
  return u;
}

inline void buyukUcluYaz64(uint8_t* x, uint64_t u) {
  for (int i = 7; i >= 0; i--) {
    x[i] = static_cast<uint8_t>(u);
    u >>= 8;
  }
}

struct Sha512 {
  uint64_t h[8];
  uint8_t tampon[128];
  uint32_t dolu;     // tamponda bekleyen bayt sayisi (0..127)
  uint64_t toplam;   // islenen toplam bayt

  void baslat() {
    for (int i = 0; i < 8; i++) {
      h[i] = kIv512[i];
    }
    dolu = 0;
    toplam = 0;
  }

  // Tek 128 baytlik blok (TweetNaCl crypto_hashblocks'un 16 kelimelik kayan pencereli bicimi)
  void blok(const uint8_t* m) {
    uint64_t b[8], a[8], w[16], t;
    int i, j;
    for (i = 0; i < 8; i++) {
      a[i] = h[i];
    }
    for (i = 0; i < 16; i++) {
      w[i] = buyukUcluOku64(m + 8 * i);
    }
    for (i = 0; i < 80; i++) {
      for (j = 0; j < 8; j++) {
        b[j] = a[j];
      }
      t = a[7] + shaSigma1(a[4]) + shaCh(a[4], a[5], a[6]) + kK512[i] + w[i % 16];
      b[7] = t + shaSigma0(a[0]) + shaMaj(a[0], a[1], a[2]);
      b[3] += t;
      for (j = 0; j < 8; j++) {
        a[(j + 1) % 8] = b[j];
      }
      if (i % 16 == 15) {
        for (j = 0; j < 16; j++) {
          w[j] += w[(j + 9) % 16] + shaKucukSigma0(w[(j + 1) % 16]) + shaKucukSigma1(w[(j + 14) % 16]);
        }
      }
    }
    for (i = 0; i < 8; i++) {
      h[i] += a[i];
    }
  }

  void ekle(const uint8_t* d, size_t n) {
    toplam += n;
    while (n > 0) {
      size_t al = 128 - dolu;
      if (al > n) {
        al = n;
      }
      memcpy(tampon + dolu, d, al);
      dolu += static_cast<uint32_t>(al);
      d += al;
      n -= al;
      if (dolu == 128) {
        blok(tampon);
        dolu = 0;
      }
    }
  }

  void bitir(uint8_t out[64]) {
    const uint64_t bitUst = toplam >> 61;  // 128 bitlik uzunlugun ust yarisi (toplam < 2^61 bayt ise 0)
    const uint64_t bitAlt = toplam << 3;
    const uint8_t pad = 0x80;
    ekle(&pad, 1);
    const uint8_t sifir = 0;
    while (dolu != 112) {
      ekle(&sifir, 1);
    }
    uint8_t uzunluk[16];
    buyukUcluYaz64(uzunluk, bitUst);
    buyukUcluYaz64(uzunluk + 8, bitAlt);
    ekle(uzunluk, 16);
    for (int i = 0; i < 8; i++) {
      buyukUcluYaz64(out + 8 * i, h[i]);
    }
  }
};

// ---- Edwards egrisi (genisletilmis koordinatlar) ---------------------------------------------------------------------------------
inline void nktEkle(gf p[4], gf q[4]) {
  gf a, b, c, d, t, e, f, g, h;

  gfZ(a, p[1], p[0]);
  gfZ(t, q[1], q[0]);
  gfM(a, a, t);
  gfA(b, p[0], p[1]);
  gfA(t, q[0], q[1]);
  gfM(b, b, t);
  gfM(c, p[3], q[3]);
  gfM(c, c, kD2);
  gfM(d, p[2], q[2]);
  gfA(d, d, d);
  gfZ(e, b, a);
  gfZ(f, d, c);
  gfA(g, d, c);
  gfA(h, b, a);

  gfM(p[0], e, f);
  gfM(p[1], h, g);
  gfM(p[2], g, f);
  gfM(p[3], e, h);
}

inline void nktTakas(gf p[4], gf q[4], uint8_t b) {
  for (int i = 0; i < 4; i++) {
    sel25519(p[i], q[i], b);
  }
}

inline void nktPaketle(uint8_t* r, gf p[4]) {
  gf tx, ty, zi;
  inv25519(zi, p[2]);
  gfM(tx, p[0], zi);
  gfM(ty, p[1], zi);
  pack25519(r, ty);
  r[31] = static_cast<uint8_t>(r[31] ^ (par25519(tx) << 7));
}

// p = [s]q (s: 32 bayt kucuk uclu skaler; q bu cagrida degistirilir)
inline void skalerCarp(gf p[4], gf q[4], const uint8_t* s) {
  set25519(p[0], kGf0);
  set25519(p[1], kGf1);
  set25519(p[2], kGf1);
  set25519(p[3], kGf0);
  for (int i = 255; i >= 0; --i) {
    const uint8_t b = static_cast<uint8_t>((s[i / 8] >> (i & 7)) & 1);
    nktTakas(p, q, b);
    nktEkle(q, p);
    nktEkle(p, p);
    nktTakas(p, q, b);
  }
}

// p = [s]B (B: taban nokta); q = cagirandan gelen 4 noktalik gecici alan (icerigi yok edilir)
inline void skalerTaban(gf p[4], gf q[4], const uint8_t* s) {
  set25519(q[0], kX);
  set25519(q[1], kY);
  set25519(q[2], kGf1);
  gfM(q[3], kX, kY);
  skalerCarp(p, q, s);
}

inline void skalerTaban(gf p[4], const uint8_t* s) {
  gf q[4];
  skalerTaban(p, q, s);
}

// 64 bayt x'i mod L indirger; sonuc r[0..31], r[32..63] sifirlanir.
inline void modL(uint8_t* r, int64_t x[64]) {
  int64_t carry;
  int64_t i, j;
  for (i = 63; i >= 32; --i) {
    carry = 0;
    for (j = i - 32; j < i - 12; ++j) {
      x[j] += carry - 16 * x[i] * static_cast<int64_t>(kL[j - (i - 32)]);
      carry = (x[j] + 128) >> 8;
      x[j] -= carry * 256;
    }
    x[j] += carry;
    x[i] = 0;
  }
  carry = 0;
  for (j = 0; j < 32; j++) {
    x[j] += carry - (x[31] >> 4) * static_cast<int64_t>(kL[j]);
    carry = x[j] >> 8;
    x[j] &= 255;
  }
  for (j = 0; j < 32; j++) {
    x[j] -= carry * static_cast<int64_t>(kL[j]);
  }
  for (i = 0; i < 32; i++) {
    x[i + 1] += x[i] >> 8;
    r[i] = static_cast<uint8_t>(x[i] & 255);
  }
}

// r[0..63] (SHA-512 ciktisi) -> r[0..31] = deger mod L, r[32..63] = 0
inline void indirge(uint8_t* r) {
  int64_t x[64];
  for (int i = 0; i < 64; i++) {
    x[i] = static_cast<int64_t>(r[i]);
  }
  for (int i = 0; i < 64; i++) {
    r[i] = 0;
  }
  modL(r, x);
}

// Genel anahtari -A noktasi olarak acar (TweetNaCl unpackneg). 0 = basarili, -1 = nokta egride degil.
inline int unpackneg(gf r[4], const uint8_t p[32]) {
  gf t, chk, num, den, den2, den4, den6;
  set25519(r[2], kGf1);
  unpack25519(r[1], p);
  gfS(num, r[1]);
  gfM(den, num, kD);
  gfZ(num, num, r[2]);
  gfA(den, r[2], den);

  gfS(den2, den);
  gfS(den4, den2);
  gfM(den6, den4, den2);
  gfM(t, den6, num);
  gfM(t, t, den);

  pow2523(t, t);
  gfM(t, t, num);
  gfM(t, t, den);
  gfM(t, t, den);
  gfM(r[0], t, den);

  gfS(chk, r[0]);
  gfM(chk, chk, den);
  if (neq25519(chk, num)) {
    gfM(r[0], r[0], kKok1);
  }

  gfS(chk, r[0]);
  gfM(chk, chk, den);
  if (neq25519(chk, num)) {
    return -1;
  }

  if (par25519(r[0]) == (p[31] >> 7)) {
    gfZ(r[0], kGf0, r[0]);
  }

  gfM(r[3], r[0], r[1]);
  return 0;
}

// S < L mi? (RFC 8032 5.1.7: S >= L olan imza reddedilir)
inline bool sKanonikMi(const uint8_t s[32]) {
  for (int i = 31; i >= 0; i--) {
    if (s[i] < kL[i]) {
      return true;
    }
    if (s[i] > kL[i]) {
      return false;
    }
  }
  return false;  // S == L
}

// y < p = 2^255 - 19 mu? (sign bit atilir)
inline bool yKanonikMi(const uint8_t k[32]) {
  if ((k[31] & 0x7f) != 0x7f) {
    return true;
  }
  for (int i = 30; i >= 1; i--) {
    if (k[i] != 0xff) {
      return true;
    }
  }
  return k[0] < 0xed;
}

// dogrula / anahtarGecerliMi calisma alani: YIGIN YERINE BELLEKTE (malloc). ESP32 loop gorevinin yigini 8 KB'tir ve OTA indirmesinin
// TLS zinciri zaten derindir; ~1,9 KB'lik noktalar/SHA-512 baglami yigina binmesin. Bellek ayrilamazsa dogrulama BASARISIZ sayilir (guvenli taraf).
struct Alan {
  gf p[4];
  gf q[4];
  gf r[4];
  Sha512 s;
  uint8_t h[64];
  uint8_t t[32];
};

}  // namespace ic

// ---------------------------------------------------------------------------------------------------------------------------------
// Genel arayuz
// ---------------------------------------------------------------------------------------------------------------------------------

inline void sha512(const uint8_t* m, size_t n, uint8_t out[64]) {
  ic::Sha512 s;
  s.baslat();
  s.ekle(m, n);
  s.bitir(out);
}

// Genel anahtar kullanilabilir mi? Kanonik kodlama + egride nokta + KUCUK MERTEBELI DEGIL ([8]A != O).
// Tum-sifir, "yer tutucu" metinler ve bilinen zayif noktalar burada elenir (zayif anahtarla imza sahteciligi kolaylasirdi).
inline bool anahtarGecerliMi(const uint8_t anahtar[32]) {
  if (anahtar == nullptr || !ic::yKanonikMi(anahtar)) {
    return false;
  }
  ic::Alan* w = static_cast<ic::Alan*>(malloc(sizeof(ic::Alan)));
  if (w == nullptr) {
    return false;
  }
  bool gecerli = false;
  if (ic::unpackneg(w->q, anahtar) == 0) {
    ic::nktEkle(w->q, w->q);
    ic::nktEkle(w->q, w->q);
    ic::nktEkle(w->q, w->q);  // [8]A
    ic::nktPaketle(w->t, w->q);
    const uint8_t kimlik[32] = {1};  // etkisiz eleman: y = 1, x = 0
    gecerli = ic::esitDegil32(w->t, kimlik) != 0;
  }
  free(w);
  return gecerli;
}

// Ed25519 dogrulama (RFC 8032 5.1.7, cofactorless): [S]B == R + [h]A, h = SHA-512(R || A || ileti) mod L.
// imza = R (32) || S (32). true = imza bu anahtar ve ileti icin gecerli. UYARI: kucuk mertebeli anahtarla sahte imza uretmek kolaydir;
// cagiran anahtarGecerliMi() ile anahtari sinamalidir (ota_imza.h otaImzaDogrula bunu zorunlu kilar).
inline bool dogrula(const uint8_t imza[64], const uint8_t* ileti, size_t n, const uint8_t anahtar[32]) {
  if (!ic::sKanonikMi(imza + 32)) {
    return false;
  }
  ic::Alan* w = static_cast<ic::Alan*>(malloc(sizeof(ic::Alan)));
  if (w == nullptr) {
    return false;
  }
  bool gecerli = false;
  if (ic::unpackneg(w->q, anahtar) == 0) {
    w->s.baslat();
    w->s.ekle(imza, 32);
    w->s.ekle(anahtar, 32);
    w->s.ekle(ileti, n);
    w->s.bitir(w->h);
    ic::indirge(w->h);
    ic::skalerCarp(w->p, w->q, w->h);       // p = [h](-A)   (q bu cagrida bozulur: gecici alan olarak yeniden kullanilir)
    ic::skalerTaban(w->r, w->q, imza + 32);  // r = [S]B
    ic::nktEkle(w->p, w->r);                // p = [S]B - [h]A
    ic::nktPaketle(w->t, w->p);
    gecerli = ic::esitDegil32(imza, w->t) == 0;
  }
  free(w);
  return gecerli;
}

}  // namespace ota_ed25519

#endif
