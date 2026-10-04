# Arıza klavuzu üreticisi (`tools/klavuz`)

`docs/ARIZA_KLAVUZU*.md` ve `docs/ariza-klavuzu/` bu araçla **koddan** üretilir. Elle yazılmış satır numarası yoktur: her giriş
yalnızca **dosya + aranacak kod parçası** taşır, satırı araç çözer. Parça kodda yoksa ya da birden fazla yerde varsa üretim HATA
verir (klavuz sessizce yanlış satırı göstermez).

| Dosya | Görevi |
| --- | --- |
| `build.mjs` | Komut satırı, giriş yükleme/çözümleme/çapraz kontrol, koddan otomatik taramalar (uç noktalar, uygulama çağrıları, ortam değişkenleri, tablolar, mesajlar, kapsam), `--where` / `--explain` / `--coverage` |
| `render.mjs` | Belge üretimi (saf fonksiyonlar): ana sayfa, indeks, bölüm dosyaları, ekler, hata mesajı dizini |
| `lint.mjs` | Mekanik içerik denetimi: günlük ifadeleri kodda geçiyor mu, komutlar sır basıyor/yıkıcı mı |
| `entries/NN-ad.mjs` | Klavuzun İÇERİĞİ: bölüm başına arıza girişleri (belirti → dosya + kod parçası + nedenler + adımlar) |
| `durum.json` | Hangi bölümler bağımsız çürütücü incelemeden geçti (`dogrulananAlanlar`); geçmeyenler belgede "⚠ doğrulanmadı" etiketlenir |
| `build.test.mjs` | Aracın testleri + gerçek girişlerin `--check` ve belge bağlantı bütünlüğü testleri |

```bash
node tools/klavuz/build.mjs                          # belgeleri üret (docs/ARIZA_KLAVUZU*.md, docs/ariza-klavuzu/)
node tools/klavuz/build.mjs --check                  # girişler kodda hâlâ var mı + mekanik denetim (dosya yazmaz)
node tools/klavuz/build.mjs --check --fresh          # + diskteki belgeler koddan üretilenle aynı mı (satır kayması)
node tools/klavuz/build.mjs --check --only 10-sunucu-api   # tek bölüm (çapraz related dahil)
node tools/klavuz/build.mjs --where "Giris bilgileri hatali"  # depoda metin ara (dosya:satır)
node tools/klavuz/build.mjs --explain sunucu-giris-401        # girişin bağlantılarını koddan satır bağlamıyla göster
node tools/klavuz/build.mjs --coverage               # hiçbir girişe bağlı olmayan kaynak dosyalar
node --test "tools/klavuz/*.test.mjs"                # aracın testleri
```

Kod değişince (özellikle girişlerin işaret ettiği dosyalar) `--check` bozulan girişi gösterir; düzeltip `node tools/klavuz/build.mjs` ile
belgeleri yenileyin. Belgeler deterministiktir (zaman damgası yok), `--fresh` yalnızca gerçek kayma varsa başarısız olur.

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
      logs: ['Giris bilgileri hatali', '~[API] POST /auth/login -> 401'],                // KODDA geçen metinler (~ = dinamik)
      commands: ['ssh -p 22667 salihceylan@178.210.161.55 "pm2 logs kapi-api --lines 100 --nostream | grep -a /auth/login"'],
      tests: ['server/test/core_auth_routes.test.js'],                                    // dosya VAR olmalı
      related: ['sunucu-hesap-kilitli'],                                                  // başka giriş id'leri (VAR olmalı)
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

## Mekanik denetim (`--check` içinde, `lint.mjs`)

Uyarılar hata sayılmaz (çıkış kodu 0) ama test paketi uyarısız olmasını ister:

- **`logs`:** her ifade kodda geçmeli. "Önek + mesaj" biçiminde ayrı yerlerde birleşen metinler (`[ENV] UYARI: ...`) parçalı aranır.
  Değeri dinamik olanları `~` ile başlatın (`~[ENV] UYARI: JWT_SECRET 20 karakter`): denetlenmez, belgede `~` görünmez.
- **`commands`:** sır basanlar ASLA (`pm2 env/jlist`, `.env` okuma, `printenv`; `pm2 describe` yalnız `| grep` ile süzülürse).
  Değiştiriciler (`rm -rf`, `DROP/DELETE/UPDATE` SQL, `git reset`, `pm2 restart/delete`, `docker stop` ...) yalnızca komutta
  `# DEĞİŞTİRİR: ...` etiketi varsa kabul edilir.

## Doğrulama durumu (`durum.json`)

`--check` yalnızca **bağlantıları ve mekanik kuralları** garanti eder. Açıklamaların (nedenler, adımlar, "ne işe yarar") kodla
uyuştuğunu bir insan ya da AYRI bir ajan koda karşı çürütmeye çalışarak doğrulamalıdır (`--explain <id>` her girişin kod bağlamını
verir). Bir bölümün tüm girişleri böyle doğrulanınca bölüm anahtarını `dogrulananAlanlar` listesine ekleyin; belge o bölümü "✓
doğrulandı" diye işaretler. Listede olmayan bölümler "⚠ doğrulanmadı" etiketli kalır.

## Kalite kuralları (giriş yazarken)

1. **Uydurma yok.** Yazdığınız her neden/adım/akış için ilgili kodu okuyun; emin olmadığınızı yazmayın.
2. **Belirti odaklı:** `symptom` kullanıcının/operatörün gördüğü şeydir ("Kapı açılmıyor", "Ekranda X hatası"), dosya adı değil.
3. **Dar ve ayırt edici** `find`; satır numarası yazmayın; kod değişince `--check` uyarır.
4. **Komutlar güvenli:** sır basmayın; canlıda salt-okunur komutlar (günlük, `/health`, `SELECT`). Sunucu: `178.210.161.55`, SSH 22667,
   kullanıcı `salihceylan`, PM2 `kapi-api`.
5. Proje kuralları için `AGENTS.md`'ye bakın (geriye uyumluluk, ESP32-C3 saha cihazı, taşma yasağı).
