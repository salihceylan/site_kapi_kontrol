# Site Kapı Kontrol — Arıza Bulma Klavuzu

> Bu klavuz **elle yazılmış satır numarası içermez**: her `dosya:satır` bağlantısı `tools/klavuz/build.mjs` tarafından koddan çözülür; kod parçası bulunamazsa ya da belirsizse üretim hata verir. Kod değişince belgeleri yenileyin: `node tools/klavuz/build.mjs` (denetim: `node tools/klavuz/build.mjs --check --fresh`).

Kapsam: 11 bölüm, **454 arıza girişi**, 2585 kod bağlantısı + otomatik ekler.

## Nasıl kullanılır (kişi ya da ajan için)

1. **Belirtiyi bulun:** [ARIZA_KLAVUZU_INDEKS.md](ARIZA_KLAVUZU_INDEKS.md) — her satır "belirti → ilk bakılacak dosya:satır". `Ctrl+F` ile anahtar sözcük arayın.
2. **Ekranda hata mesajı gördüyseniz:** [ARIZA_KLAVUZU_HATA_MESAJLARI.md](ARIZA_KLAVUZU_HATA_MESAJLARI.md) içinde mesajın bir parçasını arayın (mesaj → dosya:satır).
3. **Girişi açın:** indeksteki "giriş" bağlantısı bölüm dosyasına gider: bağlantılar + "ne işe yarar", olası nedenler, adım adım kontrol, günlükte aranacak ifadeler, komutlar, testler.
4. **Uçtan uca akış gerekiyorsa** "Uçtan uca akış haritaları" bölümlerine bakın (uygulama → sunucu → veritabanı → MQTT → cihaz).
5. **Bulamazsanız:** `node tools/klavuz/build.mjs --where "aranan metin"` (depoda arar), `--explain <giriş-id>` (girişin koddaki satırlarını bağlamıyla yazdırır), [ARIZA_KLAVUZU_EKLER.md](ARIZA_KLAVUZU_EKLER.md) (tüm uç noktalar, uygulama çağrıları, ortam değişkenleri, tablolar, dosya kapsamı).

**Ajanlar için (dosyalar büyük: baştan okumayın, arayın):**

```bash
rg -i "kapı açma" docs/ARIZA_KLAVUZU_INDEKS.md          # belirtiyi bul -> ilk dosya:satır + giriş kimliği
rg -n "^### sunucu-giris-401" docs/ariza-klavuzu/        # girişin bulunduğu bölüm dosyası ve satırı (sonra o satırdan okuyun)
node tools/klavuz/build.mjs --explain sunucu-giris-401   # girişin tüm bağlantıları için KODDAN satır bağlamı
rg -i "Giris bilgileri hatali" docs/ARIZA_KLAVUZU_HATA_MESAJLARI.md   # ekranda görülen mesaj -> kaynak
```

## Doğrulama durumu

**Mekanik (otomatik) denetim her çalıştırmada:** her bağlantı gerçek ve tekil bir kod satırı; testler/dosyalar var; giriş kimlikleri benzersiz ve `related` bağlantıları geçerli; günlük ifadeleri kodda geçiyor; komutlar sır basmıyor ve değiştiriciler etiketli.

**Bağımsız çürütücü inceleme (içeriğin doğruluğu):** 0/11 bölüm geçti. Bağımsız çürütücü doğrulama, süre/kullanım sınırı nedeniyle kullanıcı kararıyla (2026-10-02) atlandı; yalnız mekanik denetimler (bağlantılar, günlük ifadeleri, komut güvenliği) uygulandı. Geçmeyen bölümler "⚠ doğrulanmadı" etiketlidir: açıklamayı bağlantıdaki koda bakarak teyit edin.

## Bölümler

| Bölüm | Giriş | Bağlantı | İçerik doğrulaması |
| --- | --- | --- | --- |
| [Sunucu API — giriş, oturum, yetki, kayıt, kapı açma, site yönetimi](ariza-klavuzu/10-sunucu-api.md) | 82 | 438 | ⚠ doğrulanmadı |
| [Sunucu altyapısı ve yayın — açılış, veritabanı şeması, MQTT, OTA, dağıtım](ariza-klavuzu/20-sunucu-altyapi-ve-yayin.md) | 59 | 327 | ⚠ doğrulanmadı |
| [Flutter uygulama çekirdeği — kök, oturum, HTTP istemcisi, yerel kapı, konum, ses, BLE, widget, tema, PDF](ariza-klavuzu/30-uygulama-cekirdek.md) | 51 | 328 | ⚠ doğrulanmadı |
| [Flutter uygulama arayüzü — ana panel, kapı kartları, diyaloglar, giriş/kayıt, tema](ariza-klavuzu/31-uygulama-arayuz.md) | 56 | 318 | ⚠ doğrulanmadı |
| [Flutter bileşenler, tasarım sistemi ve stiller](ariza-klavuzu/32-uygulama-bilesenler.md) | 49 | 178 | ⚠ doğrulanmadı |
| [Flutter veri modelleri (lib/models) — JSON ayrıştırma](ariza-klavuzu/33-uygulama-modeller.md) | 22 | 105 | ⚠ doğrulanmadı |
| [Cihaz yazılımı — ESP32 firmware, ekran, OTA, GM60, yerel kontrol](ariza-klavuzu/40-cihaz-yazilimi.md) | 44 | 252 | ⚠ doğrulanmadı |
| [Ekran yazılımı — ST7789 ekran, CST816D dokunmatik, QR, UART protokolü](ariza-klavuzu/41-ekran-yazilimi.md) | 20 | 103 | ⚠ doğrulanmadı |
| [Araçlar, test altyapısı, süreç/kurallar ve derleme/sürüm](ariza-klavuzu/50-arac-test-ve-surec.md) | 49 | 297 | ⚠ doğrulanmadı |
| [Uçtan uca akış haritaları (uygulama -> sunucu -> veritabanı -> MQTT -> cihaz)](ariza-klavuzu/60-akislar.md) | 11 | 132 | ⚠ doğrulanmadı |
| [Uçtan uca akış haritaları 2/2 (kurulum, OTA, katılım, abonelik, envanter, yetki, PDF)](ariza-klavuzu/61-akislar-devam.md) | 11 | 107 | ⚠ doğrulanmadı |

## İlgili belgeler ve kurallar

- Proje kuralları: [AGENTS.md](../AGENTS.md) (geriye uyumluluk, ESP32-C3 saha cihazı, taşma yasağı, canlı sunucu güncelleme).
- [PROJE_TEKNIK_NOTLAR.md](../PROJE_TEKNIK_NOTLAR.md), [SAHA_KONTROL_LISTESI.md](../SAHA_KONTROL_LISTESI.md), [BEKLEYEN_ISLER.md](../BEKLEYEN_ISLER.md)
- [docs/codebase/](codebase/), [deploy/README.md](../deploy/README.md), [docs/EPOSTA_DOGRULAMA.md](EPOSTA_DOGRULAMA.md)
- Araç ve giriş biçimi: [tools/klavuz/README.md](../tools/klavuz/README.md)

