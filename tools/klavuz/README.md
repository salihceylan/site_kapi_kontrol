# Arıza klavuzu üreticisi (`tools/klavuz`)

`docs/ARIZA_KLAVUZU.md` ve `docs/ARIZA_KLAVUZU_HATA_MESAJLARI.md` bu araçla **koddan** üretilir. Elle yazılmış satır numarası
yoktur: her giriş yalnızca **dosya + aranacak kod parçası** taşır, satırı araç çözer. Parça kodda yoksa ya da birden fazla
yerde varsa üretim HATA verir (klavuz sessizce yanlış satırı göstermez).

```bash
node tools/klavuz/build.mjs                          # belgeleri üret
node tools/klavuz/build.mjs --check                  # girişler kodda hâlâ var mı (dosya yazmaz)
node tools/klavuz/build.mjs --check --fresh          # + diskteki belgeler güncel mi
node tools/klavuz/build.mjs --check --only 10-sunucu-api   # tek alan
node tools/klavuz/build.mjs --where "Giris bilgileri hatali"  # depoda metin ara (dosya:satır)
node tools/klavuz/build.mjs --explain sunucu-giris-401        # girişin bağlantılarını koddan satır bağlamıyla göster
node --test "tools/klavuz/*.test.mjs"                # aracın testleri (+ gerçek girişlerin --check'i)
```

## Alan dosyası biçimi — `tools/klavuz/entries/<NN-ad>.mjs`

Dosya adındaki sayı bölüm sırasıdır; `_` ile başlayan dosyalar yüklenmez.

```js
export default {
  title: 'Sunucu API — giriş, oturum, yetki',          // bölüm başlığı
  intro: 'Bu bölüm ... (1-3 cümle: kapsam + ilk bakılacak yer)',
  files: [                                              // dosya haritası (dosya VAR olmalı)
    { file: 'server/src/routes/auth_routes.js', note: 'Giriş/kayıt/doğrulama/şifre sıfırlama uçları' },
  ],
  entries: [
    {
      id: 'sunucu-giris-401',                           // kebab-case, TÜM alanlarda benzersiz
      symptom: 'Doğru parolaya rağmen giriş "Giris bilgileri hatali" (401) veriyor',  // kullanıcının GÖRDÜĞÜ belirti
      keywords: ['giriş', '401', 'parola', 'login'],   // arama sözcükleri
      refs: [                                           // en az 1; HER biri not taşır
        { file: 'server/src/routes/auth_routes.js',
          find: "authRouter.post('/auth/login'",        // satırdan AYNEN alınmış, ayırt edici parça
          note: 'Giriş uç noktası: kullanıcıyı bulur, bcrypt ile parolayı karşılaştırır' },
        { file: 'server/src/middlewares/login_throttle.js',
          find: { regex: 'recordFailure\\(' }, nth: 1,   // regex ya da nth ile belirsizlik giderilir
          note: '5 hatalı denemede hesap kilitlenir (429)' },
      ],
      causes: ['Parola gerçekten yanlış', 'Hesap kilitli (LOGIN_LOCKED, Retry-After)'],   // olası nedenler
      checks: ['Günlükte isteği bulun', 'Kullanıcı satırı var mı: SELECT ...'],           // adım adım
      logs: ['[API] POST /auth/login -> 401'],                                            // KODDA GERÇEKTEN geçen metinler
      commands: ['ssh -p 22667 salihceylan@178.210.161.55 "pm2 logs kapi-api --lines 100 --nostream | grep -a /auth/login"'],
      tests: ['server/test/core_auth_routes.test.js'],                                    // dosya VAR olmalı
      related: ['sunucu-hesap-kilitli'],                                                  // başka giriş id'leri
    },
  ],
};
```

### Ref alanları
- `find`: **string** (satırda aranan düz metin) ya da `{ regex: '...' }`. Satırdan kopyalayın; tahmin etmeyin.
- Aynı parça birden fazla satırda geçiyorsa araç hata verir: daha ayırt edici parça seçin, `nth` (1 tabanlı) verin ya da
  bilerek ilkini istiyorsanız `any: true`.
- `until`: aralık göstermek için bitiş parçası (başlangıçtan sonraki ilk eşleşme) → `dosya:100-160`.
- `note`: bu satırın BU arıza için neden önemli olduğu (tek cümle).

## Kalite kuralları (zorunlu)

1. **Uydurma yok.** Yazdığınız her nedeni/akışı ilgili kodu okuyarak yazın. Emin olmadığınız nedeni yazmayın.
2. **Belirti odaklı:** `symptom` kullanıcının/operatörün gördüğü şeydir ("Kapı açılmıyor", "Cihaz çevrimdışı görünüyor",
   "Ekranda X hatası"), dosya adı değil.
3. **Günlük ifadeleri gerçek olmalı:** `logs` içindeki her metin kodda geçmeli
   (`node tools/klavuz/build.mjs --where "metin"` ile doğrulayın).
4. **Komutlar gerçek ve güvenli:** sır basmayın (`.env`, `pm2 env/jlist`, parola, anahtar yazdırma YOK); canlıda
   salt-okunur komutlar (günlük, `/health`). Sunucu: `178.210.161.55`, SSH 22667, kullanıcı `salihceylan`, PM2 `kapi-api`.
5. **Dar ve ayırt edici** `find`; satır numarası yazmayın; kod değişince `--check` uyarır.
6. Proje kuralları için `AGENTS.md`'ye bakın (geriye uyumluluk, ESP32-C3 saha cihazı, taşma yasağı).
