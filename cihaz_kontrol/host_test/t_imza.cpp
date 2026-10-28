// Ana makine testi: GERCEK include/ota_ed25519.h + include/ota_imza.h (+ ota_public_key.h). Arduino/ESP32 sahtesi GEREKMEZ (saf C++).
// Kapsam:
//   A  SHA-512 (OpenSSL vektorleri, sinir uzunluklari, 1.000.000 x 'a', akisli besleme rastgele parcalarla)
//   B  Ed25519 RFC 8032 7.1 vektorleri (yalniz genel anahtar / ileti / imza; gizli anahtar yok) + her bit degisikligi reddi
//   C  Ed25519 Node crypto (OpenSSL) imzali 200 rastgele vektor + test imzalayicisinin OpenSSL ile BAYT-BAYT ayni imzayi uretmesi
//   D  imza bicim esnekligi (S >= L), sifir/kisa/uzun imza, rastgele cop imzalar
//   E  genel anahtar gecerliligi: yer tutucu, tum-sifir, kanonik olmayan, 8 bilinen kucuk mertebeli nokta; zayif anahtarla sahtecilik kapisi
//   F  imza yuku bicimi (BIREBIR beklenen metin), alan dogrulama (satir ekleme / karisim), tampon tasmasi
//   G  imza dosyasi cozumleme (ham 64 / hex 128 / base64 88) ve bozuk girdiler
//   H  otaImzaDogrula uctan uca: alan alan degisiklik, yanlis anahtar, alan ayirici, hedef capraz, izinli dusurme (rollback_max)
//   I  Node imzali OTA imza yuku vektorleri (60) - C++ yuk kurucusu ile bagimsiz JS kurucusu BAYT-BAYT ayni olmali
//   J  teslim edilen ota_public_key.h: yer tutucu ise hicbir imza gecmez (kapali kalir), gercek anahtar ise gecerli nokta
// Vektor dosyasi: imza_vectors.txt (gen_imza_vectors.mjs; her calistirmada rastgele TEST anahtarlari; git'e girmez).
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#include <algorithm>
#include <map>
#include <string>
#include <vector>

#include "ota_imza.h"
#include "ed25519_test_imzalayici.h"

static int g_pass = 0, g_fail = 0;
#define CHECK(cond, msg) do { if (cond) { g_pass++; } else { g_fail++; printf("  FAIL: %s  (satir %d)\n", msg, __LINE__); } } while (0)
#define CHECKF(cond, ...) do { if (cond) { g_pass++; } else { g_fail++; printf("  FAIL (satir %d): ", __LINE__); printf(__VA_ARGS__); printf("\n"); } } while (0)

typedef std::vector<uint8_t> Bytes;

static Bytes hexten(const std::string& s) {
  Bytes v;
  if (s == "-") return v;
  for (size_t i = 0; i + 1 < s.size(); i += 2) {
    v.push_back(static_cast<uint8_t>(strtoul(s.substr(i, 2).c_str(), nullptr, 16)));
  }
  return v;
}
static std::string hexe(const uint8_t* d, size_t n) {
  static const char H[] = "0123456789abcdef";
  std::string r;
  for (size_t i = 0; i < n; i++) { r += H[d[i] >> 4]; r += H[d[i] & 15]; }
  return r;
}
static Bytes bayt(const std::string& s) { return Bytes(s.begin(), s.end()); }
static const uint8_t* P(const Bytes& b) { return b.empty() ? reinterpret_cast<const uint8_t*>("") : b.data(); }
static std::vector<std::string> boluk(const std::string& satir) {
  std::vector<std::string> r;
  size_t i = 0;
  while (i < satir.size()) {
    while (i < satir.size() && satir[i] == ' ') i++;
    size_t j = i;
    while (j < satir.size() && satir[j] != ' ') j++;
    if (j > i) r.push_back(satir.substr(i, j - i));
    i = j;
  }
  return r;
}

// ---- RFC 8032 7.1 (Ed25519) - gizli anahtar ALINMADI ----------------------------------------------------------------------------
struct RfcVektor { const char* ad; const char* genel; const char* ileti; const char* imza; };
static const RfcVektor RFC[] = {
  {"TEST 1", "d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a",
   "",
   "e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e065224901555fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b"},
  {"TEST 2", "3d4017c3e843895a92b70aa74d1b7ebc9c982ccf2ec4968cc0cd55f12af4660c",
   "72",
   "92a009a9f0d4cab8720e820b5f642540a2b27b5416503f8fb3762223ebdb69da085ac1e43e15996e458f3613d0f11d8c387b2eaeb4302aeeb00d291612bb0c00"},
  {"TEST 3", "fc51cd8e6218a1a38da47ed00230f0580816ed13ba3303ac5deb911548908025",
   "af82",
   "6291d657deec24024827e69c3abe01a30ce548a284743a445e3680d7db5ac3ac18ff9b538d16f290ae67f760984dc6594a7c15e9716ed28dc027beceea1ec40a"},
  {"TEST 1024", "278117fc144c72340f67d0f2316e8386ceffbf2b2428c9c51fef7c597f1d426e",
   "08b8b2b733424243760fe426a4b54908632110a66c2f6591eabd3345e3e4eb98fa6e264bf09efe12ee50f8f54e9f77b1"
   "e355f6c50544e23fb1433ddf73be84d879de7c0046dc4996d9e773f4bc9efe5738829adb26c81b37c93a1b270b20329d"
   "658675fc6ea534e0810a4432826bf58c941efb65d57a338bbd2e26640f89ffbc1a858efcb8550ee3a5e1998bd177e93a"
   "7363c344fe6b199ee5d02e82d522c4feba15452f80288a821a579116ec6dad2b3b310da903401aa62100ab5d1a36553e"
   "06203b33890cc9b832f79ef80560ccb9a39ce767967ed628c6ad573cb116dbefefd75499da96bd68a8a97b928a8bbc10"
   "3b6621fcde2beca1231d206be6cd9ec7aff6f6c94fcd7204ed3455c68c83f4a41da4af2b74ef5c53f1d8ac70bdcb7ed1"
   "85ce81bd84359d44254d95629e9855a94a7c1958d1f8ada5d0532ed8a5aa3fb2d17ba70eb6248e594e1a2297acbbb39d"
   "502f1a8c6eb6f1ce22b3de1a1f40cc24554119a831a9aad6079cad88425de6bde1a9187ebb6092cf67bf2b13fd65f270"
   "88d78b7e883c8759d2c4f5c65adb7553878ad575f9fad878e80a0c9ba63bcbcc2732e69485bbc9c90bfbd62481d9089b"
   "eccf80cfe2df16a2cf65bd92dd597b0707e0917af48bbb75fed413d238f5555a7a569d80c3414a8d0859dc65a46128ba"
   "b27af87a71314f318c782b23ebfe808b82b0ce26401d2e22f04d83d1255dc51addd3b75a2b1ae0784504df543af8969b"
   "e3ea7082ff7fc9888c144da2af58429ec96031dbcad3dad9af0dcbaaaf268cb8fcffead94f3c7ca495e056a9b47acdb7"
   "51fb73e666c6c655ade8297297d07ad1ba5e43f1bca32301651339e22904cc8c42f58c30c04aafdb038dda0847dd988d"
   "cda6f3bfd15c4b4c4525004aa06eeff8ca61783aacec57fb3d1f92b0fe2fd1a85f6724517b65e614ad6808d6f6ee34df"
   "f7310fdc82aebfd904b01e1dc54b2927094b2db68d6f903b68401adebf5a7e08d78ff4ef5d63653a65040cf9bfd4aca7"
   "984a74d37145986780fc0b16ac451649de6188a7dbdf191f64b5fc5e2ab47b57f7f7276cd419c17a3ca8e1b939ae49e4"
   "88acba6b965610b5480109c8b17b80e1b7b750dfc7598d5d5011fd2dcc5600a32ef5b52a1ecc820e308aa342721aac09"
   "43bf6686b64b2579376504ccc493d97e6aed3fb0f9cd71a43dd497f01f17c0e2cb3797aa2a2f256656168e6c496afc5f"
   "b93246f6b1116398a346f1a641f3b041e989f7914f90cc2c7fff357876e506b50d334ba77c225bc307ba537152f3f161"
   "0e4eafe595f6d9d90d11faa933a15ef1369546868a7f3a45a96768d40fd9d03412c091c6315cf4fde7cb68606937380d"
   "b2eaaa707b4c4185c32eddcdd306705e4dc1ffc872eeee475a64dfac86aba41c0618983f8741c5ef68d3a101e8a3b8ca"
   "c60c905c15fc910840b94c00a0b9d0",
   "0aab4c900501b3e24d7cdf4663326a3a87df5e4843b2cbdb67cbf6e460fec350aa5371b1508f9f4528ecea23c436d94b5e8fcd4f681e30a6ac00a9704a188a03"},
  {"TEST SHA(abc)", "ec172b93ad5e563bf4932c70e1245034c35467ef2efd4d64ebf819683467e2bf",
   "ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a2192992a274fc1a836ba3c23a3feebbd"
   "454d4423643ce80e2a9ac94fa54ca49f",
   "dc2a4459e7369633a52b1bf277839a00201009a3efbf3ecb69bea2186c26b58909351fc9ac90b3ecfdfbc7c66431e0303dca179c138ac17ad9bef1177331a704"},
};

// Grup mertebesi L (kucuk uclu) + 256 bit toplama (S + L)
static void sPlusL(const uint8_t s[32], uint8_t out[32]) {
  unsigned c = 0;
  for (int i = 0; i < 32; i++) {
    const unsigned t = static_cast<unsigned>(s[i]) + ota_ed25519::ic::kL[i] + c;
    out[i] = static_cast<uint8_t>(t & 255);
    c = t >> 8;
  }
}

static uint64_t g_rng = 0x1234567890ABCDEFULL;
static uint32_t rnd() {
  g_rng ^= g_rng >> 12; g_rng ^= g_rng << 25; g_rng ^= g_rng >> 27;
  return static_cast<uint32_t>((g_rng * 2685821657736338717ULL) >> 32);
}

int main() {
  // ---- vektor dosyasi --------------------------------------------------------------------------------------------------------------
  std::vector<std::vector<std::string>> H, E, O, Mm, K;
  {
    FILE* f = fopen("imza_vectors.txt", "r");
    if (!f) {
      printf("HATA: imza_vectors.txt yok (node gen_imza_vectors.mjs)\n");
      return 2;
    }
    std::string satir;
    int ch;
    while ((ch = fgetc(f)) != EOF) {
      if (ch != '\n' && ch != '\r') { satir += static_cast<char>(ch); continue; }
      if (satir.empty()) continue;
      auto t = boluk(satir);
      satir.clear();
      if (t.empty() || t[0][0] == '#') continue;
      if (t[0] == "H") H.push_back(t);
      else if (t[0] == "E") E.push_back(t);
      else if (t[0] == "O") O.push_back(t);
      else if (t[0] == "M") Mm.push_back(t);
      else if (t[0] == "K") K.push_back(t);
    }
    fclose(f);
  }
  printf("vektorler: H=%zu M=%zu E=%zu O=%zu K=%zu\n", H.size(), Mm.size(), E.size(), O.size(), K.size());
  CHECK(H.size() >= 30 && Mm.size() == 1 && E.size() == 200 && O.size() == 60 && K.size() >= 350, "vektor dosyasi tam (H>=30, M=1, E=200, O=60, K>=350)");

  // ------------------------------------------------------------------------------------------------ A SHA-512
  { printf("A SHA-512: OpenSSL vektorleri (sinir uzunluklari), akisli rastgele parcalama, 1.000.000 x 'a'\n");
    int hata = 0;
    for (const auto& t : H) {
      const Bytes m = hexten(t[1]);
      uint8_t d[64];
      ota_ed25519::sha512(P(m), m.size(), d);
      if (hexe(d, 64) != t[2]) hata++;
      // akisli: rastgele parcalar
      ota_ed25519::ic::Sha512 s;
      s.baslat();
      size_t i = 0;
      while (i < m.size()) {
        const size_t k = std::min<size_t>(1 + rnd() % 150, m.size() - i);
        s.ekle(m.data() + i, k);
        i += k;
      }
      uint8_t d2[64];
      s.bitir(d2);
      if (memcmp(d, d2, 64) != 0) hata++;
    }
    CHECKF(hata == 0, "SHA-512 uyusmazligi: %d", hata);
    // bilinen: bos ve "abc" (FIPS 180-4)
    uint8_t d[64];
    ota_ed25519::sha512(nullptr, 0, d);
    CHECK(hexe(d, 64) == "cf83e1357eefb8bdf1542850d66d8007d620e4050b5715dc83f4a921d36ce9ce47d0d13c5d85f2b0ff8318d2877eec2f63b931bd47417a81a538327af927da3e", "SHA-512('') FIPS vektoru");
    ota_ed25519::sha512(reinterpret_cast<const uint8_t*>("abc"), 3, d);
    CHECK(hexe(d, 64) == "ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f", "SHA-512('abc') FIPS vektoru");
    // 1.000.000 x 'a'
    ota_ed25519::ic::Sha512 s;
    s.baslat();
    uint8_t a1000[1000];
    memset(a1000, 'a', sizeof(a1000));
    for (int i = 0; i < 1000; i++) s.ekle(a1000, sizeof(a1000));
    s.bitir(d);
    CHECK(Mm.size() == 1 && hexe(d, 64) == Mm[0][3], "SHA-512(1.000.000 x 'a') OpenSSL ile ayni");
  }

  // ------------------------------------------------------------------------------------------------ B RFC 8032
  { printf("B RFC 8032 7.1 vektorleri: dogrulama + her bit degisikligi reddi (imza 512 bit, ileti, anahtar)\n");
    for (const auto& v : RFC) {
      const Bytes pk = hexten(v.genel), msg = hexten(v.ileti), sig = hexten(v.imza);
      CHECKF(pk.size() == 32 && sig.size() == 64, "%s: boyutlar", v.ad);
      CHECKF(ota_ed25519::dogrula(sig.data(), P(msg), msg.size(), pk.data()), "%s: gecerli imza KABUL", v.ad);
      CHECKF(ota_ed25519::anahtarGecerliMi(pk.data()), "%s: genel anahtar gecerli", v.ad);
      int kabulEdilen = 0;
      for (int bit = 0; bit < 512; bit++) {
        Bytes s2 = sig;
        s2[bit / 8] ^= static_cast<uint8_t>(1 << (bit % 8));
        if (ota_ed25519::dogrula(s2.data(), P(msg), msg.size(), pk.data())) kabulEdilen++;
      }
      CHECKF(kabulEdilen == 0, "%s: bozulmus imza (512 tek-bit) KABUL EDILMEDI (kabul=%d)", v.ad, kabulEdilen);
      int kabulMsg = 0;
      for (size_t i = 0; i < msg.size() && i < 64; i++) {
        Bytes m2 = msg;
        m2[i] ^= 1;
        if (ota_ed25519::dogrula(sig.data(), P(m2), m2.size(), pk.data())) kabulMsg++;
      }
      CHECKF(kabulMsg == 0, "%s: bozulmus ileti reddedildi", v.ad);
      Bytes m3 = msg; m3.push_back(0);
      CHECKF(!ota_ed25519::dogrula(sig.data(), m3.data(), m3.size(), pk.data()), "%s: eklenmis bayt reddedildi", v.ad);
      int kabulPk = 0;
      for (int bit = 0; bit < 256; bit++) {
        Bytes k2 = pk;
        k2[bit / 8] ^= static_cast<uint8_t>(1 << (bit % 8));
        if (ota_ed25519::dogrula(sig.data(), P(msg), msg.size(), k2.data())) kabulPk++;
      }
      CHECKF(kabulPk == 0, "%s: bozulmus genel anahtar reddedildi", v.ad);
    }
    CHECK(hexten(RFC[3].ileti).size() == 1023, "TEST 1024 iletisi 1023 bayt");
  }

  // ------------------------------------------------------------------------------------------------ C Node/OpenSSL
  { printf("C Node crypto (OpenSSL) ile imzalanan 200 rastgele vektor: dogrulama, test imzalayicisi ile bayt-bayt esitlik\n");
    int dogrulanamayan = 0, imzaFarki = 0, anahtarFarki = 0, bozukKabul = 0;
    for (const auto& t : E) {
      const Bytes pk = hexten(t[1]), msg = hexten(t[2]), sig = hexten(t[3]), tohum = hexten(t[4]);
      if (!ota_ed25519::dogrula(sig.data(), P(msg), msg.size(), pk.data())) dogrulanamayan++;
      uint8_t pk2[32], sig2[64];
      ed_test::genelAnahtar(tohum.data(), pk2);
      if (memcmp(pk2, pk.data(), 32) != 0) anahtarFarki++;
      ed_test::imzala(tohum.data(), P(msg), msg.size(), sig2);
      if (memcmp(sig2, sig.data(), 64) != 0) imzaFarki++;
      // tek bit bozma (rastgele bir bit)
      Bytes s3 = sig;
      const int bit = static_cast<int>(rnd() % 512);
      s3[bit / 8] ^= static_cast<uint8_t>(1 << (bit % 8));
      if (ota_ed25519::dogrula(s3.data(), P(msg), msg.size(), pk.data())) bozukKabul++;
    }
    CHECKF(dogrulanamayan == 0, "OpenSSL imzalari dogrulanamadi: %d / 200", dogrulanamayan);
    CHECKF(anahtarFarki == 0, "test imzalayicisinin genel anahtari OpenSSL ile ayni (fark=%d)", anahtarFarki);
    CHECKF(imzaFarki == 0, "test imzalayicisinin imzasi OpenSSL ile BAYT-BAYT ayni (fark=%d)", imzaFarki);
    CHECKF(bozukKabul == 0, "rastgele tek-bit bozulmus imza kabul edilmedi (kabul=%d)", bozukKabul);
  }

  // ------------------------------------------------------------------------------------------------ D imza esnekligi / cop
  { printf("D imza bicim esnekligi (S >= L), sifir imzalar, rastgele cop imzalar\n");
    int s0 = 0, s1 = 0;
    for (size_t i = 0; i < 40 && i < E.size(); i++) {
      const Bytes pk = hexten(E[i][1]), msg = hexten(E[i][2]), sig = hexten(E[i][3]);
      Bytes esnek = sig;
      sPlusL(sig.data() + 32, esnek.data() + 32);   // S' = S + L : esitlik [S']B == [S]B (esnek imza), RFC 8032 5.1.7 reddeder
      if (ota_ed25519::dogrula(esnek.data(), P(msg), msg.size(), pk.data())) s0++;
      Bytes sL = sig;
      memcpy(sL.data() + 32, ota_ed25519::ic::kL, 32);   // S == L
      if (ota_ed25519::dogrula(sL.data(), P(msg), msg.size(), pk.data())) s1++;
    }
    CHECKF(s0 == 0, "S+L (esnek) imza reddedildi (kabul=%d)", s0);
    CHECKF(s1 == 0, "S==L imza reddedildi (kabul=%d)", s1);
    const Bytes pk = hexten(E[0][1]), msg = hexten(E[0][2]);
    uint8_t sifir[64] = {0};
    CHECK(!ota_ed25519::dogrula(sifir, P(msg), msg.size(), pk.data()), "tum-sifir imza reddedildi");
    uint8_t ff[64]; memset(ff, 0xff, sizeof(ff));
    CHECK(!ota_ed25519::dogrula(ff, P(msg), msg.size(), pk.data()), "tum-0xFF imza reddedildi (S >= L)");
    int cop = 0;
    for (int i = 0; i < 300; i++) {
      uint8_t r[64];
      for (int j = 0; j < 64; j++) r[j] = static_cast<uint8_t>(rnd());
      r[63] &= 0x0f;   // S < L olsun (esnekligi degil asil denklemi sinayalim)
      if (ota_ed25519::dogrula(r, P(msg), msg.size(), pk.data())) cop++;
    }
    CHECKF(cop == 0, "300 rastgele cop imza kabul edilmedi (kabul=%d)", cop);
  }

  // ------------------------------------------------------------------------------------------------ E anahtar gecerliligi
  { printf("E genel anahtar gecerliligi: yer tutucu / sifir / kanonik olmayan / kucuk mertebeli noktalar; zayif anahtarla sahtecilik kapisi\n");
    CHECK(otaImzaAnahtarDurumuHesapla(ed_test::YER_TUTUCU_DUZ) == OTA_ANAHTAR_YER_TUTUCU, "yer tutucu metni YER_TUTUCU durumunda");
    CHECK(memcmp(ed_test::YER_TUTUCU_DUZ, "OTA-PUBLIC-KEY-NOT-SET-REPLACE!!", 32) == 0, "yer tutucu = ASCII 'OTA-PUBLIC-KEY-NOT-SET-REPLACE!!'");
    CHECK(!ota_ed25519::anahtarGecerliMi(ed_test::YER_TUTUCU_DUZ), "yer tutucu gecerli Ed25519 anahtari DEGIL (hicbir imza ona gore uretilemez)");
    { // firmware'de acik metin yer tutucu YOK: XOR'lu tablo acik metne cozulur; tek bayt farki yer tutucu SAYILMAZ
      bool tablo = true;
      for (int i = 0; i < 32; i++) if (static_cast<uint8_t>(OTA_IMZA_YER_TUTUCU_XOR[i] ^ OTA_IMZA_YER_TUTUCU_MASKE) != ed_test::YER_TUTUCU_DUZ[i]) tablo = false;
      CHECK(tablo, "XOR'lu tanima tablosu acik metin yer tutucuya cozulur");
      CHECK(otaImzaYerTutucuMu(ed_test::YER_TUTUCU_DUZ) && !otaImzaYerTutucuMu(nullptr), "otaImzaYerTutucuMu: yer tutucu evet, nullptr hayir");
      int yanlis = 0;
      for (int i = 0; i < 32; i++) { uint8_t k[32]; memcpy(k, ed_test::YER_TUTUCU_DUZ, 32); k[i] ^= 0x01; if (otaImzaYerTutucuMu(k)) yanlis++; }
      CHECKF(yanlis == 0, "yer tutucudan tek bayt/bit farkli anahtar yer tutucu SAYILMAZ (yanlis=%d)", yanlis);
      CHECK(!otaImzaYerTutucuMu(hexten(E[0][1]).data()), "gercek anahtar yer tutucu degil"); }
    uint8_t sifir[32] = {0};
    CHECK(otaImzaAnahtarDurumuHesapla(sifir) == OTA_ANAHTAR_GECERSIZ, "tum-sifir anahtar GECERSIZ");
    CHECK(otaImzaAnahtarDurumuHesapla(nullptr) == OTA_ANAHTAR_GECERSIZ, "nullptr anahtar GECERSIZ");
    // 8 bilinen kucuk mertebeli nokta kodlamasi (mertebe 1, 2, 4, 4, 8, 8, 8, 8)
    const char* kucuk[] = {
      "0100000000000000000000000000000000000000000000000000000000000000",
      "ecffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff7f",
      "0000000000000000000000000000000000000000000000000000000000000080",
      "0000000000000000000000000000000000000000000000000000000000000000",
      "c7176a703d4dd84fba3c0b760d10670f2a2053fa2c39ccc64ec7fd7792ac037a",
      "c7176a703d4dd84fba3c0b760d10670f2a2053fa2c39ccc64ec7fd7792ac03fa",
      "26e8958fc2b227b045c3f489f2ef98f0d5dfac05d3c63339b13802886d53fc05",
      "26e8958fc2b227b045c3f489f2ef98f0d5dfac05d3c63339b13802886d53fc85",
    };
    int kabul = 0;
    for (const char* h : kucuk) {
      const Bytes k = hexten(h);
      if (ota_ed25519::anahtarGecerliMi(k.data())) kabul++;
    }
    CHECKF(kabul == 0, "8 kucuk mertebeli nokta REDDEDILDI (kabul edilen=%d)", kabul);
    // kanonik olmayan y (y >= p): ed ff..ff 7f (= p) ve ee ff..ff 7f (= p+1 -> y=1)
    CHECK(!ota_ed25519::anahtarGecerliMi(hexten("edffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff7f").data()), "kanonik olmayan y (=p) reddedildi");
    CHECK(!ota_ed25519::anahtarGecerliMi(hexten("eeffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff7f").data()), "kanonik olmayan y (=p+1) reddedildi");
    // BAGIMSIZ capraz dogrulama: tools/ota_anahtar.mjs (JS BigInt) ile C++ (TweetNaCl) ayni karari vermeli - yapisal adaylar + rastgele 32 bayt
    { int uyusmayan = 0, kabulJs = 0, redJs = 0;
      for (const auto& t : K) {
        const Bytes k = hexten(t[1]);
        const bool beklenen = t[2] == "1";
        if (beklenen) kabulJs++; else redJs++;
        if (ota_ed25519::anahtarGecerliMi(k.data()) != beklenen) { uyusmayan++; printf("    uyusmazlik: %s js=%d\n", t[1].c_str(), beklenen ? 1 : 0); }
      }
      CHECKF(uyusmayan == 0, "genel anahtar gecerliligi C++ ve bagimsiz JS gerceklemesiyle AYNI (%zu aday; uyusmayan=%d)", K.size(), uyusmayan);
      CHECKF(kabulJs > 50 && redJs > 50, "aday kumesi iki sonucu da iceriyor (kabul=%d red=%d)", kabulJs, redJs); }
    // gercek anahtarlar gecerli
    int gecerli = 0;
    for (const auto& t : E) if (ota_ed25519::anahtarGecerliMi(hexten(t[1]).data())) gecerli++;
    CHECKF(gecerli == 200, "200 OpenSSL anahtari gecerli (%d)", gecerli);
    // KAPI: kucuk mertebeli anahtarla Ed25519 dogrulamasi SAHTE imzayi kabul eder (cofactorless denklem) - bu yuzden otaImzaDogrula once
    // anahtar durumunu denetler. Kimlik noktasi (y=1) + R=kimlik, S=0 imzasi ham dogrulamadan gecer; kapi bunu keser.
    uint8_t kimlik[32] = {1};
    uint8_t sahte[64] = {0};
    sahte[0] = 1;   // R = kimlik noktasi, S = 0
    const char* sha = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef";
    char yuk[OTA_IMZA_YUK_MAX];
    const size_t n = otaImzaYukuOlustur(yuk, sizeof(yuk), "esp32-c3", "4.4.1", 1000, sha, nullptr);
    CHECK(n > 0, "(yuk kuruldu)");
    CHECK(ota_ed25519::dogrula(sahte, reinterpret_cast<const uint8_t*>(yuk), n, kimlik), "BILINEN TEHLIKE belgelendi: ham dogrulama kimlik-noktali anahtarda sahte imzayi kabul eder");
    CHECK(otaImzaDogrula(sahte, kimlik, "esp32-c3", "4.4.1", 1000, sha, nullptr) == OTA_IMZA_ANAHTAR_YOK, "otaImzaDogrula kucuk mertebeli anahtarda sahte imzayi KESER (ANAHTAR_YOK)");
    CHECK(otaImzaDogrula(sahte, sifir, "esp32-c3", "4.4.1", 1000, sha, nullptr) == OTA_IMZA_ANAHTAR_YOK, "tum-sifir anahtarda da kapali");
  }

  // ------------------------------------------------------------------------------------------------ F imza yuku
  { printf("F imza yuku bicimi (birebir metin), alan dogrulama, tampon sinirlari\n");
    const std::string sha = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef";
    char tampon[OTA_IMZA_YUK_MAX];
    size_t n = otaImzaYukuOlustur(tampon, sizeof(tampon), "esp32-c3", "4.4.1", 1234567, sha.c_str(), nullptr);
    const std::string beklenen = "SKP-OTA-V1\ntarget=esp32-c3\nversion=4.4.1\nsize=1234567\nsha256=" + sha + "\n";
    CHECK(n == beklenen.size() && std::string(tampon, n) == beklenen, "yuk birebir: etiket, target, version, size, sha256, her satir \\n ile biter");
    n = otaImzaYukuOlustur(tampon, sizeof(tampon), "esp32-wroom", "5.3.0", 4294967295u, sha.c_str(), "5.2.9");
    const std::string beklenen2 = "SKP-OTA-V1\ntarget=esp32-wroom\nversion=5.3.0\nsize=4294967295\nsha256=" + sha + "\nrollback_max=5.2.9\n";
    CHECK(n == beklenen2.size() && std::string(tampon, n) == beklenen2, "izinli dusurme: rollback_max satiri sha256'dan SONRA, \\n ile biter");
    n = otaImzaYukuOlustur(tampon, sizeof(tampon), "esp32-c3", "4.4.1", 0, sha.c_str(), "");
    CHECK(n > 0 && std::string(tampon, n).find("rollback_max") == std::string::npos, "bos rollbackMax = satir YOK");
    CHECK(otaImzaYukuOlustur(tampon, sizeof(tampon), "esp32-c3", "4.4.1", 0, sha.c_str(), nullptr) > 0 && std::string(tampon, 60).find("size=0\n") != std::string::npos, "boyut 0 yazilir (karar ust katmanda)");

    // gecersiz alanlar -> 0
    struct G { const char* ad; const char* hedef; const char* surum; const char* sha; const char* rb; };
    const std::string shaBuyuk = "0123456789ABCDEF0123456789abcdef0123456789abcdef0123456789abcdef";
    const std::vector<G> gv = {
      {"bos surum", "esp32-c3", "", sha.c_str(), nullptr},
      {"surumde satir sonu (alan ekleme)", "esp32-c3", "4.4.1\nsize=1", sha.c_str(), nullptr},
      {"surumde bosluk", "esp32-c3", "4.4 1", sha.c_str(), nullptr},
      {"surumde esittir", "esp32-c3", "4=4", sha.c_str(), nullptr},
      {"surum 25 karakter", "esp32-c3", "1234567890123456789012345", sha.c_str(), nullptr},
      {"surum nokta ile baslar", "esp32-c3", ".4.1", sha.c_str(), nullptr},
      {"hedefte buyuk harf", "ESP32-C3", "4.4.1", sha.c_str(), nullptr},
      {"hedefte satir sonu", "esp32-c3\n", "4.4.1", sha.c_str(), nullptr},
      {"hedef bos", "", "4.4.1", sha.c_str(), nullptr},
      {"hedef 17 karakter", "esp32-wroom-xxxxx", "4.4.1", sha.c_str(), nullptr},
      {"hedef tireyle baslar", "-esp32", "4.4.1", sha.c_str(), nullptr},
      {"sha256 63 hane", "esp32-c3", "4.4.1", "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcde", nullptr},
      {"sha256 65 hane", "esp32-c3", "4.4.1", "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef0", nullptr},
      {"sha256 buyuk harf", "esp32-c3", "4.4.1", shaBuyuk.c_str(), nullptr},
      {"sha256 hex degil", "esp32-c3", "4.4.1", "g123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef", nullptr},
      {"sha256 nullptr", "esp32-c3", "4.4.1", nullptr, nullptr},
      {"hedef nullptr", nullptr, "4.4.1", sha.c_str(), nullptr},
      {"surum nullptr", "esp32-c3", nullptr, sha.c_str(), nullptr},
      {"rollback_max satir ekleme", "esp32-c3", "4.4.1", sha.c_str(), "4.4.9\nx=1"},
      {"rollback_max gecersiz karakter", "esp32-c3", "4.4.1", sha.c_str(), "4.4 9"},
    };
    for (const auto& g : gv) {
      CHECKF(otaImzaYukuOlustur(tampon, sizeof(tampon), g.hedef, g.surum, 100, g.sha, g.rb) == 0, "gecersiz alan reddedildi: %s", g.ad);
    }
    // tampon sinirlari: tam sigan ve 1 bayt eksik
    const size_t tam = beklenen.size();
    char kucuk[256];
    CHECK(otaImzaYukuOlustur(kucuk, tam, "esp32-c3", "4.4.1", 1234567, sha.c_str(), nullptr) == tam, "tam sigan tampon (cap == uzunluk) calisir");
    CHECK(otaImzaYukuOlustur(kucuk, tam - 1, "esp32-c3", "4.4.1", 1234567, sha.c_str(), nullptr) == 0, "1 bayt eksik tampon -> 0 (tasma yok)");
    CHECK(otaImzaYukuOlustur(kucuk, 5, "esp32-c3", "4.4.1", 1234567, sha.c_str(), nullptr) == 0, "5 baytlik tampon -> 0");
    CHECK(otaImzaYukuOlustur(nullptr, 100, "esp32-c3", "4.4.1", 1, sha.c_str(), nullptr) == 0, "nullptr tampon -> 0");
    // en uzun yuk tampona sigar
    n = otaImzaYukuOlustur(tampon, sizeof(tampon), "esp32-wroom-xxxxx", "123456789012345678901234", 4294967295u, sha.c_str(), "123456789012345678901234");
    CHECK(n == 0, "(hedef 17 > 16 -> 0)");
    n = otaImzaYukuOlustur(tampon, sizeof(tampon), "esp32-wroom-xxxx", "123456789012345678901234", 4294967295u, sha.c_str(), "123456789012345678901234");
    CHECKF(n > 0 && n < OTA_IMZA_YUK_MAX, "en uzun gecerli yuk (%zu bayt) %zu baytlik tampona sigar", n, OTA_IMZA_YUK_MAX);
    // surum yazimlari
    CHECK(otaImzaSurumGecerliMi("4.4.1") && otaImzaSurumGecerliMi("v4.4.1") && otaImzaSurumGecerliMi("4.4.1-rc1") && otaImzaSurumGecerliMi("4.4.1+b7") && otaImzaSurumGecerliMi("9"), "gecerli surum yazimlari");
    CHECK(!otaImzaSurumGecerliMi(nullptr) && !otaImzaSurumGecerliMi("") && !otaImzaSurumGecerliMi("4.4.1 ") && !otaImzaSurumGecerliMi("4/4") && !otaImzaSurumGecerliMi("-1"), "gecersiz surum yazimlari");
  }

  // ------------------------------------------------------------------------------------------------ G imza cozumleme
  { printf("G imza dosyasi cozumleme: ham 64 / hex 128 / base64 88; bozuk girdiler\n");
    const Bytes sig = hexten(RFC[1].imza);
    uint8_t out[64];
    auto cozulen = [&](const std::string& s) { memset(out, 0xAA, 64); return otaImzaCozumle(reinterpret_cast<const uint8_t*>(s.data()), s.size(), out) && memcmp(out, sig.data(), 64) == 0; };
    // ham
    memset(out, 0, 64);
    CHECK(otaImzaCozumle(sig.data(), 64, out) && memcmp(out, sig.data(), 64) == 0, "ham 64 bayt");
    // ham, NUL ve satir sonu baytlari iceren imza (metin sanilmamali)
    uint8_t ham[64]; for (int i = 0; i < 64; i++) ham[i] = static_cast<uint8_t>(i % 3 == 0 ? 0 : (i % 5 == 0 ? '\n' : i));
    CHECK(otaImzaCozumle(ham, 64, out) && memcmp(out, ham, 64) == 0, "ham 64 bayt (NUL / \\n / bosluk baytlari iceren) aynen alinir");
    const std::string hexKucuk = hexe(sig.data(), 64);
    std::string hexBuyuk = hexKucuk; for (auto& c : hexBuyuk) c = static_cast<char>(toupper(static_cast<unsigned char>(c)));
    CHECK(cozulen(hexKucuk), "hex kucuk harf");
    CHECK(cozulen(hexBuyuk), "hex BUYUK harf");
    CHECK(cozulen(hexKucuk + "\n"), "hex + LF");
    CHECK(cozulen(hexKucuk + "\r\n"), "hex + CRLF");
    CHECK(cozulen("  \t" + hexKucuk + " \r\n\r\n"), "hex, bas/son bosluk");
    // base64 (standart, dolgulu)
    static const char B[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    std::string b64;
    for (size_t i = 0; i + 2 < 64; i += 3) {
      const uint32_t v = (sig[i] << 16) | (sig[i + 1] << 8) | sig[i + 2];
      b64 += B[(v >> 18) & 63]; b64 += B[(v >> 12) & 63]; b64 += B[(v >> 6) & 63]; b64 += B[v & 63];
    }
    { const uint32_t v = sig[63] << 16; b64 += B[(v >> 18) & 63]; b64 += B[(v >> 12) & 63]; b64 += "=="; }
    CHECK(b64.size() == 88, "(base64 88 karakter)");
    CHECK(cozulen(b64), "base64 dolgulu");
    CHECK(cozulen(b64 + "\n"), "base64 + LF");
    // bozuk
    CHECK(!cozulen(hexKucuk.substr(0, 126)), "hex 126 hane");
    CHECK(!cozulen(hexKucuk + "00"), "hex 130 hane");
    { std::string h = hexKucuk; h[7] = 'g'; CHECK(!cozulen(h), "hex icinde hex olmayan karakter"); }
    { std::string h = hexKucuk; h[7] = ' '; CHECK(!cozulen(h), "hex icinde bosluk"); }
    { std::string b = b64; b[10] = '*'; CHECK(!cozulen(b), "base64 gecersiz karakter"); }
    { std::string b = b64; b[86] = 'A'; CHECK(!cozulen(b), "base64 dolgu eksik ('A=' )"); }
    { std::string b = b64; b[87] = 'A'; CHECK(!cozulen(b), "base64 dolgu eksik ('=A')"); }
    { std::string b = b64; b[85] = (b[85] == 'B' ? 'C' : 'B'); CHECK(!cozulen(b), "base64 kanonik olmayan son 4 bit / farkli deger"); }
    CHECK(!cozulen(b64.substr(0, 87)), "base64 87 karakter");
    CHECK(!cozulen(b64 + "AAAA"), "base64 92 karakter");
    CHECK(!cozulen(""), "bos girdi");
    CHECK(!cozulen("   \n"), "yalniz bosluk");
    CHECK(!cozulen(std::string(63, 'a')), "63 karakter");
    CHECK(!cozulen(std::string(65, 'a')), "65 karakter");
    CHECK(!otaImzaCozumle(nullptr, 64, out), "nullptr girdi");
    // 64 bayt DEGIL ama 65 bayt ham (sonda LF) metin sayilir ve reddedilir
    Bytes ham65(sig.begin(), sig.end()); ham65.push_back('\n');
    CHECK(!otaImzaCozumle(ham65.data(), ham65.size(), out), "ham 64 + LF (65 bayt) metin sayilir ve reddedilir");
  }

  // ------------------------------------------------------------------------------------------------ H uctan uca otaImzaDogrula
  { printf("H otaImzaDogrula uctan uca: alan alan degisiklik, yanlis anahtar, alan ayirici, hedef capraz, izinli dusurme\n");
    const ed_test::Anahtar yayinci = ed_test::anahtarCifti("yayinci");
    const ed_test::Anahtar saldirgan = ed_test::anahtarCifti("saldirgan");
    const std::string sha = hexe(reinterpret_cast<const uint8_t*>("0123456789abcdef0123456789abcdef"), 32);
    char yuk[OTA_IMZA_YUK_MAX];
    auto imzaUret = [&](const ed_test::Anahtar& k, const char* hedef, const char* surum, uint32_t boyut, const std::string& shaX, const char* rb) {
      Bytes sig(64);
      const size_t n = otaImzaYukuOlustur(yuk, sizeof(yuk), hedef, surum, boyut, shaX.c_str(), rb);
      ed_test::imzala(k.tohum, reinterpret_cast<const uint8_t*>(yuk), n, sig.data());
      return sig;
    };
    const Bytes imza = imzaUret(yayinci, "esp32-c3", "4.4.1", 1800000, sha, nullptr);
    CHECK(otaImzaDogrula(imza.data(), yayinci.genel, "esp32-c3", "4.4.1", 1800000, sha.c_str(), nullptr) == OTA_IMZA_TAMAM, "dogru imza KABUL");
    CHECK(otaImzaDogrula(imza.data(), yayinci.genel, "esp32-c3", "4.4.1", 1800000, sha.c_str(), "") == OTA_IMZA_TAMAM, "bos rollbackMax = yok");
    CHECK(otaImzaDogrula(imza.data(), saldirgan.genel, "esp32-c3", "4.4.1", 1800000, sha.c_str(), nullptr) == OTA_IMZA_GECERSIZ, "yanlis anahtar (saldirgan) RED");
    CHECK(otaImzaDogrula(imzaUret(saldirgan, "esp32-c3", "4.4.1", 1800000, sha, nullptr).data(), yayinci.genel, "esp32-c3", "4.4.1", 1800000, sha.c_str(), nullptr) == OTA_IMZA_GECERSIZ, "saldirganin kendi anahtariyla attigi imza RED");
    CHECK(otaImzaDogrula(imza.data(), yayinci.genel, "esp32-wroom", "4.4.1", 1800000, sha.c_str(), nullptr) == OTA_IMZA_GECERSIZ, "HEDEF CAPRAZ: C3 imzali paket WROOM'da RED");
    CHECK(otaImzaDogrula(imza.data(), yayinci.genel, "esp32-c3", "4.4.2", 1800000, sha.c_str(), nullptr) == OTA_IMZA_GECERSIZ, "surum degisti (4.4.2) RED");
    CHECK(otaImzaDogrula(imza.data(), yayinci.genel, "esp32-c3", "4.3.9", 1800000, sha.c_str(), nullptr) == OTA_IMZA_GECERSIZ, "SURUM SAHTELEME: imzali paket eski surum diye sunulursa RED");
    CHECK(otaImzaDogrula(imza.data(), yayinci.genel, "esp32-c3", "4.4.1", 1800001, sha.c_str(), nullptr) == OTA_IMZA_GECERSIZ, "boyut degisti RED");
    { std::string s2 = sha; s2[0] = (s2[0] == '0' ? '1' : '0');
      CHECK(otaImzaDogrula(imza.data(), yayinci.genel, "esp32-c3", "4.4.1", 1800000, s2.c_str(), nullptr) == OTA_IMZA_GECERSIZ, "sha256 degisti (baska ikili) RED"); }
    CHECK(otaImzaDogrula(imza.data(), yayinci.genel, "esp32-c3", "4.4.1", 1800000, sha.c_str(), "4.4.1") == OTA_IMZA_GECERSIZ, "DUSURME IZNI EKLEME: imza rollback_max icermiyorsa, sonradan eklenen rollback RED");
    for (int bit = 0; bit < 512; bit += 7) {
      Bytes s2 = imza; s2[bit / 8] ^= static_cast<uint8_t>(1 << (bit % 8));
      CHECKF(otaImzaDogrula(s2.data(), yayinci.genel, "esp32-c3", "4.4.1", 1800000, sha.c_str(), nullptr) == OTA_IMZA_GECERSIZ, "bozulmus imza biti %d RED", bit);
    }
    // etiket (alan ayirici): ayni govdeyi baska etiketle imzala -> RED
    { const std::string govde = std::string("target=esp32-c3\nversion=4.4.1\nsize=1800000\nsha256=") + sha + "\n";
      for (const char* etiket : {"SKP-OTA-V2\n", "SKP-OTA-V1\n\n", "skp-ota-v1\n", ""}) {
        const std::string yukX = std::string(etiket) + govde;
        Bytes sig(64);
        ed_test::imzala(yayinci.tohum, reinterpret_cast<const uint8_t*>(yukX.data()), yukX.size(), sig.data());
        CHECKF(otaImzaDogrula(sig.data(), yayinci.genel, "esp32-c3", "4.4.1", 1800000, sha.c_str(), nullptr) == OTA_IMZA_GECERSIZ, "farkli etiketle imzalanan yuk RED (etiket=%s)", etiket); }
      // sondaki satir sonu olmadan / CRLF ile imzalanan yuk RED (tek bicimli yuk)
      std::string eksikLf = std::string("SKP-OTA-V1\n") + govde; eksikLf.pop_back();
      Bytes s1(64); ed_test::imzala(yayinci.tohum, reinterpret_cast<const uint8_t*>(eksikLf.data()), eksikLf.size(), s1.data());
      CHECK(otaImzaDogrula(s1.data(), yayinci.genel, "esp32-c3", "4.4.1", 1800000, sha.c_str(), nullptr) == OTA_IMZA_GECERSIZ, "sondaki LF'siz yuk RED");
      std::string crlf; for (char c : std::string("SKP-OTA-V1\n") + govde) { if (c == '\n') crlf += '\r'; crlf += c; }
      Bytes s2(64); ed_test::imzala(yayinci.tohum, reinterpret_cast<const uint8_t*>(crlf.data()), crlf.size(), s2.data());
      CHECK(otaImzaDogrula(s2.data(), yayinci.genel, "esp32-c3", "4.4.1", 1800000, sha.c_str(), nullptr) == OTA_IMZA_GECERSIZ, "CRLF'li yuk RED"); }
    // alan gecerliligi
    CHECK(otaImzaDogrula(imza.data(), yayinci.genel, "esp32-c3", "4.4.1\nx", 1800000, sha.c_str(), nullptr) == OTA_IMZA_ALAN_GECERSIZ, "satir iceren surum ALAN_GECERSIZ");
    CHECK(otaImzaDogrula(imza.data(), yayinci.genel, "esp32-c3", "4.4.1", 1800000, "xyz", nullptr) == OTA_IMZA_ALAN_GECERSIZ, "gecersiz sha256 ALAN_GECERSIZ");
    // anahtar hazir degil
    CHECK(otaImzaDogrula(imza.data(), ed_test::YER_TUTUCU_DUZ, "esp32-c3", "4.4.1", 1800000, sha.c_str(), nullptr) == OTA_IMZA_ANAHTAR_YOK, "yer tutucu anahtar: ANAHTAR_YOK");

    // izinli surum dusurme: imza rollback_max icerir
    const Bytes dus = imzaUret(yayinci, "esp32-c3", "4.3.0", 1700000, sha, "4.4.1");
    CHECK(otaImzaDogrula(dus.data(), yayinci.genel, "esp32-c3", "4.3.0", 1700000, sha.c_str(), "4.4.1") == OTA_IMZA_TAMAM, "izinli dusurme: rollback_max imzali -> KABUL");
    CHECK(otaImzaDogrula(dus.data(), yayinci.genel, "esp32-c3", "4.3.0", 1700000, sha.c_str(), nullptr) == OTA_IMZA_GECERSIZ, "rollback_max'siz sunulursa RED (izin yok sayilir)");
    CHECK(otaImzaDogrula(dus.data(), yayinci.genel, "esp32-c3", "4.3.0", 1700000, sha.c_str(), "4.9.9") == OTA_IMZA_GECERSIZ, "KAPSAM GENISLETME: imzadaki rollback_max'i buyutmek RED");
    CHECK(otaImzaDogrula(dus.data(), yayinci.genel, "esp32-c3", "4.3.0", 1700000, sha.c_str(), "4.4.0") == OTA_IMZA_GECERSIZ, "kapsam degistirme RED");
  }

  // ------------------------------------------------------------------------------------------------ I Node imzali OTA yukleri
  { printf("I Node (JS) imzali 60 OTA imza yuku: C++ yuk kurucusu ile BAYT-BAYT ayni olmali\n");
    int ok = 0, kotu = 0, rb = 0;
    for (const auto& t : O) {
      const Bytes pk = hexten(t[1]);
      const std::string hedef = t[3], surum = t[4], boyutS = t[5], sha = t[6], rollback = t[7];
      const Bytes sig = hexten(t[8]);
      const uint32_t boyut = static_cast<uint32_t>(strtoul(boyutS.c_str(), nullptr, 10));
      const char* r = rollback == "-" ? nullptr : rollback.c_str();
      if (r) rb++;
      const OtaImzaSonuc s = otaImzaDogrula(sig.data(), pk.data(), hedef.c_str(), surum.c_str(), boyut, sha.c_str(), r);
      if (s == OTA_IMZA_TAMAM) ok++; else { kotu++; printf("    ret: %s %s %u rb=%s -> %d\n", hedef.c_str(), surum.c_str(), boyut, rollback.c_str(), static_cast<int>(s)); }
      // ayni imza baska rollback_max ile (varsa kaldirilarak / yoksa eklenerek) gecerli OLMAMALI
      const OtaImzaSonuc s2 = otaImzaDogrula(sig.data(), pk.data(), hedef.c_str(), surum.c_str(), boyut, sha.c_str(), r ? nullptr : "9.9.9");
      if (s2 == OTA_IMZA_TAMAM) kotu++;
    }
    CHECKF(ok == 60 && kotu == 0, "60 OTA yuku dogrulandi (ok=%d, kotu=%d; %d tanesi rollback_max'li)", ok, kotu, rb);
  }

  // ------------------------------------------------------------------------------------------------ J teslim edilen anahtar
  { printf("J teslim edilen ota_public_key.h: yer tutucu ise OTA KAPALI kalir; gercek anahtar yerlestirildiyse gecerli nokta olmali\n");
    const OtaAnahtarDurumu d = otaImzaAnahtarDurumuHesapla(otaImzaAnahtari());
    CHECK(sizeof(OTA_IMZA_GENEL_ANAHTAR) == 32, "gomulu anahtar 32 bayt");
    CHECK(d == OTA_ANAHTAR_YER_TUTUCU || d == OTA_ANAHTAR_HAZIR, "gomulu anahtar ya yer tutucu ya GECERLI anahtar (gecersiz/zayif olamaz)");
    if (d == OTA_ANAHTAR_YER_TUTUCU) {
      printf("  (bilgi) ota_public_key.h hala YER TUTUCU: uretim derlemesi oncesi cihaz_kontrol/tools/ota_anahtar.mjs yaz ile gercek anahtar yazilmali\n");
      const ed_test::Anahtar k = ed_test::anahtarCifti("teslim");
      const std::string sha(64, 'a');
      char yuk[OTA_IMZA_YUK_MAX];
      const size_t n = otaImzaYukuOlustur(yuk, sizeof(yuk), "esp32-c3", "4.4.1", 10, sha.c_str(), nullptr);
      uint8_t imza[64];
      ed_test::imzala(k.tohum, reinterpret_cast<const uint8_t*>(yuk), n, imza);
      CHECK(otaImzaDogrula(imza, otaImzaAnahtari(), "esp32-c3", "4.4.1", 10, sha.c_str(), nullptr) == OTA_IMZA_ANAHTAR_YOK, "yer tutucuyla HICBIR imza gecmez (fail-closed)");
      CHECK(memcmp(OTA_IMZA_GENEL_ANAHTAR, ed_test::YER_TUTUCU_DUZ, 32) == 0 && otaImzaYerTutucuMu(OTA_IMZA_GENEL_ANAHTAR), "teslim edilen anahtar baytlari = yer tutucu ve ota_imza.h tanima tablosu bunu yer tutucu sayar");
    } else {
      printf("  (bilgi) gercek OTA imza anahtari gomulu\n");
    }
  }

  // bilgi: bir dogrulamanin masaustu suresi
  { const Bytes pk = hexten(E[0][1]), msg = hexten(E[0][2]), sig = hexten(E[0][3]);
    const clock_t t0 = clock();
    for (int i = 0; i < 20; i++) ota_ed25519::dogrula(sig.data(), P(msg), msg.size(), pk.data());
    printf("(bilgi) tek Ed25519 dogrulamasi masaustunde ~%.1f ms\n", 1000.0 * (clock() - t0) / CLOCKS_PER_SEC / 20);
  }

  printf("\nSONUC: %d dogrulama gecti, %d basarisiz\n", g_pass, g_fail);
  return g_fail == 0 ? 0 : 1;
}
