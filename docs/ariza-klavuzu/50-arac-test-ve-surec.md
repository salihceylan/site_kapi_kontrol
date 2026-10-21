# Araçlar, test altyapısı, süreç/kurallar ve derleme/sürüm

[← Ana sayfa](../ARIZA_KLAVUZU.md) · [İndeks](../ARIZA_KLAVUZU_INDEKS.md) · [Ekler](../ARIZA_KLAVUZU_EKLER.md) · [Hata mesajları](../ARIZA_KLAVUZU_HATA_MESAJLARI.md)

> ⚠ **Doğrulanmadı:** bu bölümün açıklamaları (olası nedenler, adımlar) ajanlarca kodu okuyarak yazıldı ama bağımsız çürütücü incelemeden GEÇMEDİ. `dosya:satır` bağlantıları ise koddan çözülür ve her çalıştırmada denetlenir (güvenilir). Açıklamayı uygulamadan önce bağlantıdaki koda bakarak teyit edin.

Bu bölüm sunucu/uygulama/firmware kodunun DIŞINDAKİ arıza yerlerini toplar: Windows şirket aracı (company_qr_tool) ve cihaz_dene, "hangi testi nerede bulurum / test neden kırıldı", AGENTS.md kuralları ve saha/bekleyen iş belgeleri, ve derleme/sürüm ayarları (pubspec, app_config, Gradle JDK, git index). Önce belirtiye en yakın girişi bulun; testler ve komutlar her girişin altındadır.

## Dosya haritası

| Dosya | Rol |
| --- | --- |
| [company_qr_tool/app.py](../../company_qr_tool/app.py) | Tk masaüstü aracı: QR/etiket üretimi, UID okuma, firmware derle/sürümle/yükle, sunucuya kayıt, PDF, Cihaz Dene, Ekran firmware |
| [company_qr_tool/README.md](../../company_qr_tool/README.md) | Aracın kullanım adımları, COMPANY_API_KEY ve known_hosts kurulumu |
| [company_qr_tool/env.example](../../company_qr_tool/env.example) | .env örneği (COMPANY_API_KEY, AHBU_API_URL, SSH_* ayarları); gerçek .env git dışıdır |
| [company_qr_tool/launch_company_qr_tool.bat](../../company_qr_tool/launch_company_qr_tool.bat) | Çift tıkla başlatma: .venv oluşturur, requirements kurar, pythonw ile açar |
| [company_qr_tool/requirements.txt](../../company_qr_tool/requirements.txt) | qrcode, Pillow, pyserial, esptool, paramiko |
| [cihaz_dene/app.py](../../cihaz_dene/app.py) | Bağımsız (eski/yalın) seri port deneme aracı; aynı işlevin büyük sürümü company_qr_tool içindeki DeviceTesterWindow |
| [server/package.json](../../server/package.json) | npm test (node --test) ve npm run lint betikleri; Node >= 20.19 |
| [server/eslint.config.js](../../server/eslint.config.js) | no-undef = ERROR (eksik import canlıda ReferenceError olmasın) |
| [server/scripts/qa_pending_registration_pg.mjs](../../server/scripts/qa_pending_registration_pg.mjs) | Gerçek PostgreSQL üzerinde bekleyen kayıt akışının 15 adımlık uçtan uca doğrulaması |
| [test/design/harness.dart](../../test/design/harness.dart) | pumpAt / taşma matrisi (320/360/412/820 x 1.0/1.5/2.0 x açık/koyu) |
| [test/screens/dialog_layout_harness.dart](../../test/screens/dialog_layout_harness.dart) | layoutMatrix / openDialogAt: ekran ve diyalog taşma testlerinin ortak düzeneği |
| [test/support/rebuild_probe.dart](../../test/support/rebuild_probe.dart) | Widget yeniden kurma sayacı (performans gerileme testleri) |
| [integration_test/support/e2e_env.dart](../../integration_test/support/e2e_env.dart) | E2E ortam değişkenleri ve yalnız-yerel-API emniyeti |
| [test_driver/perf_driver.dart](../../test_driver/perf_driver.dart) | flutter drive sürücüsü: kare süresi JSON özeti yazar |
| [cihaz_kontrol/host_test/run_all.py](../../cihaz_kontrol/host_test/run_all.py) | Firmware ana makine testlerini (MSVC) derleyip çalıştıran koşucu |
| [cihaz_kontrol/host_test/README.md](../../cihaz_kontrol/host_test/README.md) | Host test tablosu (719 doğrulama) ve gereksinimler |
| [tools/klavuz/build.mjs](../../tools/klavuz/build.mjs) | Arıza klavuzu üreticisi / denetleyicisi |
| [tools/klavuz/build.test.mjs](../../tools/klavuz/build.test.mjs) | Klavuz aracının testleri + gerçek girişlerin --check denetimi |
| [.github/workflows/ci.yml](../../.github/workflows/ci.yml) | CI: server lint+test, Flutter analyze+test, gitleaks (deploy YOK) |
| [AGENTS.md](../../AGENTS.md) | 12 çalışma/kodlama kuralı |
| [SAHA_KONTROL_LISTESI.md](../../SAHA_KONTROL_LISTESI.md) | Sahada/uygulamada elle doğrulama adımları (bölüm 1-87; Panel modül vitrini 87) |
| [BEKLEYEN_ISLER.md](../../BEKLEYEN_ISLER.md) | Yol haritası, kod inceleme planı fazları, ertelenen işler, iptal edilen Faz 4 |
| [PROJE_TEKNIK_NOTLAR.md](../../PROJE_TEKNIK_NOTLAR.md) | Genel teknik özet: canlı dizin, güncelleme sırası, build/test notları |
| [docs/codebase/TESTING.md](../../docs/codebase/TESTING.md) | Test yığını, düzen, kapsam matrisi, komutlar |
| [docs/YEREL_KONTROL_V2.md](../../docs/YEREL_KONTROL_V2.md) | Yerel UDP kapı kontrol protokolü v2 sözleşmesi |
| [docs/EPOSTA_DOGRULAMA.md](../../docs/EPOSTA_DOGRULAMA.md) | E-posta doğrulama tasarımı, parametreler, "kod gelmiyor" teşhisi |
| [README.md](../../README.md) | Kısa başlangıç: yerel API, Flutter, firmware komutları |
| [pubspec.yaml](../../pubspec.yaml) | Uygulama sürümü (version: 1.0.0+1) ve bağımlılıklar |
| [analysis_options.yaml](../../analysis_options.yaml) | flutter_lints + analiz dışı klasörler |
| [lib/config/app_config.dart](../../lib/config/app_config.dart) | Ekranda görünen sürüm ve API_BASE_URL varsayılanı |
| [android/gradle.properties](../../android/gradle.properties) | Gradle JDK (org.gradle.java.home) ve bellek ayarı |
| [android/app/build.gradle.kts](../../android/app/build.gradle.kts) | applicationId, Java 17 hedefi, release imzası |
| [.vscode/settings.json](../../.vscode/settings.json) | VS Code çalışma alanı ayarları (git.autorefresh, izleyici hariç tutma) |

## Bu bölümdeki girişler (49)

- [arac-sunucu-401](#arac-sunucu-401) — Şirket aracında "Sunucu yetkilendirmeyi reddetti (HTTP 401)" çıkıyor (Cihazı Sunucuya Kaydet, kayıtlı cihaz listesi, silme)
- [arac-anahtar-tanimli-degil](#arac-anahtar-tanimli-degil) — Şirket aracı "COMPANY_API_KEY tanimli degil" uyarısı veriyor; sunucuya kayıt/liste/silme hiç denenmiyor (yalnız yerel kayıt yapılıyor)
- [arac-http-anahtar-gonderilmiyor](#arac-http-anahtar-gonderilmiyor) — Yerel/test API adresine (http://...) bağlanınca şirket aracı 401 alıyor, oysa COMPANY_API_KEY tanımlı
- [arac-sftp-known-hosts](#arac-sftp-known-hosts) — Şirket aracı "Guncelleme Dosyasini Sunucuya gonder" sırasında "Sunucu kimligi dogrulanamadi ... known_hosts" ya da "UYUSMUYOR" uyarısı veriyor
- [arac-sftp-kimlik](#arac-sftp-kimlik) — Sunucuya gönderirken "SSH_KEY_FILE bulunamadi", "SSH anahtari parola ile korunuyor" veya şifre soruyor / "Sunucu yukleme hatasi"
- [arac-uid-okunamadi](#arac-uid-okunamadi) — Şirket aracında "Secili cihaz UID oku" → "Cihaz Unique ID okunamadi!" hatası ya da çip "ESP32" (belirsiz) görünüyor
- [arac-kayit-http-400-donanim](#arac-kayit-http-400-donanim) — "Cihazı Sunucuya Kaydet" hata veriyor (HTTP 400 "device_uid 12 haneli hex", HTTP 500, 429) ya da kayıttan sonra WROOM kart OTA'da 403 alıyor
- [arac-usb-yukleme-hata](#arac-usb-yukleme-hata) — Şirket aracında "USB ile karta yükle" hata veriyor: "portu meşgul (Erişim engellendi)" veya "Bağlantı / Yazma Zaman Aşımı"
- [arac-usb-yukleme-sessiz-basarisizlik](#arac-usb-yukleme-sessiz-basarisizlik) — USB yükleme "TMM: Yazılım yükleme tamamlandı" ("TMM · Yükleme tamamlandı") dedi ama cihaz hâlâ eski sürümde / açılmıyor
- [arac-surum-derleme](#arac-surum-derleme) — Şirket aracında "Derle" / "Sürüm oluştur" başarısız ya da düğmeler pasif ("Once derleme ve surum olusturma adimlarini basariyla tamamlayin")
- [arac-ota-basligi-degisti](#arac-ota-basligi-degisti) — git durumunda cihaz_kontrol/include/ota_guncelleme.h kendiliğinden değişmiş görünüyor (sürüm numarası farklı)
- [arac-zip-hatasi](#arac-zip-hatasi) — Şirket aracında "Çalışma arkadaşı için ZIP" hata veriyor ("ZIP icin gerekli arac klasoru yok" / "Guncelleme dosyasi yok" / "Surum gerekli")
- [arac-qr-etiket](#arac-qr-etiket) — Üretilen QR etiketi okunmuyor / etiket altındaki "Unique ID" cihazın gerçek UID'sinden farklı / "Logo bulunamadi"
- [arac-kayitli-cihazlar-pdf](#arac-kayitli-cihazlar-pdf) — Kayıtlı Cihazlar listesi eksik/farklı, silme "Kısmi Silme" diyor ya da PDF raporu yazıları bozuk / "PDF Hatası"
- [arac-cihaz-dene-durum-bos](#arac-cihaz-dene-durum-bos) — Cihaz Dene (cihaz_dene/app.py ya da şirket aracındaki "Cihaz testi" sayfası): bilgi alanları "-" kalıyor veya Role Pin HIGH/LOW/Pin Bulma tepki vermiyor
- [arac-cihaz-dene-beacon-wan](#arac-cihaz-dene-beacon-wan) — Cihaz testi sayfasında "Yerel Beacon (UDP)" ya da "Genel IP (WAN)" alanı dolmuyor ("-" kalıyor)
- [arac-ekran-firmware](#arac-ekran-firmware) — Şirket aracı "Ekran yazılımı" sayfası: ekran bulunamıyor / derleme-sürüm-yükleme hata veriyor
- [arac-baslatma-bat](#arac-baslatma-bat) — launch_company_qr_tool.bat ile araç açılmıyor ("Python sanal ortam olusturulamadi" / "Kutuphane kurulumu basarisiz") ya da pencere hiç açılmadan kapanıyor
- [test-nerede-sunucu](#test-nerede-sunucu) — Sunucuda bu özellik/uç hangi testle korunuyor? Testi nerede bulurum, nasıl çalıştırırım?
- [test-nerede-flutter](#test-nerede-flutter) — Flutter tarafında bu ekran/özellik hangi testle korunuyor? Testler nerede, hangisi neyi ölçüyor?
- [test-nerede-firmware](#test-nerede-firmware) — Firmware mantığı (yerel kontrol, PIN, GM60, MQTT/OTA) hangi testle korunuyor? Donanımsız test nasıl çalışır?
- [test-sunucu-npm-test-lint](#test-sunucu-npm-test-lint) — "npm test" ya da "npm run lint" kırıldı (no-undef, import smoke, core_startup, Node sürümü)
- [test-sunucu-kaynak-korumalari](#test-sunucu-kaynak-korumalari) — Sunucu testi "... bulunamadi" ile ya da kaynak metni iddiasıyla kırıldı; kodu yeniden adlandırınca/taşıyınca regresyon koruması düştü
- [test-ops-migration-zinciri](#test-ops-migration-zinciri) — ops_migration_chain / ops_migrate_runner testi kırıldı: yeni migration "tablo bu migration'dan önce hiçbir migration'da oluşturulmuyor" ya da numara çakışması
- [test-gercek-pg-qa](#test-gercek-pg-qa) — qa_pending_registration_pg.mjs "REDDEDILDI" ile çıkıyor (çıkış kodu 3) ya da gerçek PostgreSQL adımlarından biri düşüyor
- [test-flutter-tasma-matrisi](#test-flutter-tasma-matrisi) — Widget/ekran testi "A RenderFlex overflowed by X pixels" ile kırıldı (taşma matrisi: 320/360/412/820 x 1.0/1.5/2.0 x açık/koyu)
- [test-flutter-ahem](#test-flutter-ahem) — Taşma testi yalnız testte kırılıyor (uzun etiket/eylem 320 px x 1.5-2.0 ölçekte taşıyor) ama gerçek cihazda sorun yok gibi; "Ahem" yazı tipi
- [test-flutter-kontrast-tema](#test-flutter-kontrast-tema) — contrast_test / tema testleri kırıldı: metin-zemin kontrastı 4.5:1 altında, rol vurgusu uyuşmuyor, gölge/hareket bütçesi aşıldı
- [test-flutter-yeniden-kurma-yoklama](#test-flutter-yeniden-kurma-yoklama) — Performans gerileme testi kırıldı: yeniden kurma sayısı arttı, yoklama (3 sn / 800 ms) durmuyor ya da saat tüm sayfayı yeniden kuruyor
- [test-flutter-widget-ortam](#test-flutter-widget-ortam) — Widget testi ağa çıkmaya çalışıyor, "A Timer is still pending" veriyor, SharedPreferences/güvenli depo hatası alıyor ya da pumpAndSettle hiç bitmiyor
- [test-e2e-integration](#test-e2e-integration) — integration_test (E2E menü yürüyüşü) çalışmıyor: "E2E_USERS bos", "E2E yalnizca yerel arka uca baglanir" ya da sonuçlara güvenip güvenemeyeceğim belirsiz
- [test-perf-kare](#test-perf-kare) — Kare süresi / takılma (jank) ölçümü nasıl alınır; "perf_frames verisi gelmedi" ya da hedefin (build/raster p90 <= 8 ms, jank <= %2) tutup tutmadığı
- [test-firmware-host-derleme](#test-firmware-host-derleme) — Firmware host testi "CALISMADI / DERLENMEDI" ya da "ArduinoJson bulunamadi" diyor; run_all.py derleyemiyor
- [test-yerel-kontrol-v2](#test-yerel-kontrol-v2) — Yerel (LAN/UDP) kapı kontrol testleri ya da bilinen-cevap vektörü kırıldı; yerel açma "challenge"/"unauthorized" hatası veriyor: sözleşme ve testler nerede?
- [test-klavuz-araci](#test-klavuz-araci) — Arıza klavuzu üretimi/denetimi hata veriyor: "BELİRSİZ", "bulunamadı (kod değişmiş olabilir)", "yinelenen id" veya "related id yok"
- [test-ci-kirmizi](#test-ci-kirmizi) — GitHub Actions CI kırmızı: "Server (lint + test)", "Flutter (analyze + test)" ya da "Secret scan (gitleaks)" işi başarısız
- [surec-kurallar-hangisi](#surec-kurallar-hangisi) — Bir değişiklik yapacağım: AGENTS.md'nin hangi kuralı bu durumda geçerli? (backend, arayüz, firmware, yeni özellik, git)
- [surec-saha-listesi-ekleme](#surec-saha-listesi-ekleme) — Yeni özelliği bitirdim: saha kontrol listesine test adımı nasıl eklenir? (kural 5) / listedeki madde numarası klavuzda kayboldu
- [surec-git-index-bozuldu](#surec-git-index-bozuldu) — git/VS Code "fatal: .git/index: index file smaller than expected" ya da "Unable to create .git/index.lock" veriyor; commit/push öncesi indeks kontrolü nasıl yapılır?
- [surec-eposta-dogrulama-dok](#surec-eposta-dogrulama-dok) — E-posta doğrulama (bekleyen kayıt) sorununda docs/EPOSTA_DOGRULAMA.md'nin hangi bölümüne bakmalıyım? (kod gelmiyor, süre, 503/429, pre-hijacking, geri alma)
- [surec-bekleyen-isler](#surec-bekleyen-isler) — Gördüğüm eksik/davranış bilinen bir ertelenmiş iş mi, yoksa yeni hata mı? Hangi iş kullanıcı kararı, hangisi yapıldı? (BEKLEYEN_ISLER.md)
- [surec-canliya-alma-kural8](#surec-canliya-alma-kural8) — Sunucu kodu değişti ama canlıda eski davranış sürüyor; canlıya nasıl alınır, geri nasıl alınır? (AGENTS.md kural 8)
- [test-klavuz-yeni-giris](#test-klavuz-yeni-giris) — Arıza klavuzuna yeni giriş nasıl eklenir, hangi komutla doğrulanır; klavuz belgeleri nasıl güncellenir (--check / --fresh / --coverage / --explain)?
- [arac-cihaz-dene-baglanti](#arac-cihaz-dene-baglanti) — Bağımsız cihaz_dene aracı açılmıyor ("No module named serial") ya da "Baglan" sonrası "Hata" / port listesi boş / butonlar "Baglanti yok" diyor
- [surec-surum-gosterimi](#surec-surum-gosterimi) — Uygulamada görünen sürüm ("v1.0.0 (Build 1)") APK/pubspec sürümüyle uyuşmuyor ya da sürüm numarası nereden geliyor?
- [surec-android-gradle-jdk](#surec-android-gradle-jdk) — flutter build apk / flutter run Android'de Gradle hatası veriyor (Java sürümü, "org.gradle.java.home ... geçersiz", problems-report.html, bellek)
- [test-flutter-analyze](#test-flutter-analyze) — "flutter analyze" hata/uyarı veriyor ya da bir klasör (android/ios/web) analiz edilmiyor; CI Flutter işi kırmızı
- [surec-teknik-notlar-bayat](#surec-teknik-notlar-bayat) — PROJE_TEKNIK_NOTLAR.md ile kod/gerçek durum çelişiyor (komut, sayı, güncelleme sırası); hangi belgeye güvenmeliyim?
- [test-codebase-belgeleri](#test-codebase-belgeleri) — Mimari, modül sınırları, risk, entegrasyon veya test düzeni sorusu: docs/codebase altındaki hangi belgeye bakmalıyım?

## Girişler

<a id="arac-sunucu-401"></a>
### arac-sunucu-401 · Şirket aracında "Sunucu yetkilendirmeyi reddetti (HTTP 401)" çıkıyor (Cihazı Sunucuya Kaydet, kayıtlı cihaz listesi, silme)

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [company_qr_tool/app.py:152](../../company_qr_tool/app.py#L152) | <code>def _company_http_error_text(code: int, body: bytes &#124; None = None) -&gt; str:</code> | 401/403 gelince "Sunucu yetkilendirmeyi reddetti (HTTP ...)" metnini üretir |
| [company_qr_tool/app.py:140](../../company_qr_tool/app.py#L140) | <code>headers["X-Company-Key"] = key</code> | Anahtar yalnız doluysa ve adres güvenliyse başlığa eklenir; aksi halde başlık hiç gitmez |
| [server/src/middlewares/company_auth.js:16](../../server/src/middlewares/company_auth.js#L16) | <code>export function hasValidCompanyKey(req, env = process.env) {</code> | Sunucu tarafı: x-company-key başlığını COMPANY_API_KEY ile sabit zamanlı karşılaştırır; sunucuda anahtar tanımsızsa her zaman false |
| [server/src/middlewares/company_auth.js:43](../../server/src/middlewares/company_auth.js#L43) | <code>return res.status(401).json({ error: 'Yetkisiz erisim.' });</code> | Anahtar da super_user JWT de yoksa 401; ayrıca company_access_denied denetim kaydı yazılır |
| [server/src/config/env.js:325](../../server/src/config/env.js#L325) | <code>warnings.push('COMPANY_API_KEY tanimli degil; /api/company/* yalnizca super_user JWT ile …</code> | Sunucuda anahtar tanımsızsa açılışta bu uyarı yazılır (başlık işlemez) |
| [company_qr_tool/env.example:12](../../company_qr_tool/env.example#L12) | <code>COMPANY_API_KEY=</code> | İstemcide anahtarın yazılacağı satır (değer sunucudaki server/.env ile AYNI olmalı) |

**Olası nedenler**
- Bu bilgisayardaki COMPANY_API_KEY, sunucudaki server/.env değerinden farklı (eski/yenilenmiş anahtar, fazladan boşluk)
- Sunucuda COMPANY_API_KEY tanımsız: başlık hiç işlemez, yalnız super_user JWT geçer
- Adres düz http (AHBU_API_URL): güvenlik gereği anahtar gönderilmez (bkz. arac-http-anahtar-gonderilmiyor)
- Sunucuda anahtar değiştirildi ama araçtaki .env güncellenmedi

**Adım adım kontrol**
- Araç klasöründe .env var mı ve COMPANY_API_KEY satırı dolu mu (değeri EKRANA/GÜNLÜĞE YAZMAYIN; yalnız uzunluğu karşılaştırın)
- Sunucu günlüğünde "company_access_denied" kaydı ve açılış uyarısı "[ENV] UYARI: COMPANY_API_KEY tanimli degil" var mı
- Aracı kapatıp yeniden açın (.env yalnız açılışta okunur)

**Günlükte aranacak ifadeler**
- `company_access_denied`
- `[ENV] UYARI: COMPANY_API_KEY tanimli degil`

**Komutlar**
```bash
ssh -p 22667 salihceylan@178.210.161.55 "pm2 logs kapi-api --lines 200 --nostream | grep -a company_access_denied"
```

**İlgili testler:** [server/test/core_company_auth.test.js](../../server/test/core_company_auth.test.js), [server/test/core_company_routes_http.test.js](../../server/test/core_company_routes_http.test.js)

**Bkz.:** [arac-anahtar-tanimli-degil](#arac-anahtar-tanimli-degil), [arac-http-anahtar-gonderilmiyor](#arac-http-anahtar-gonderilmiyor)

<a id="arac-anahtar-tanimli-degil"></a>
### arac-anahtar-tanimli-degil · Şirket aracı "COMPANY_API_KEY tanimli degil" uyarısı veriyor; sunucuya kayıt/liste/silme hiç denenmiyor (yalnız yerel kayıt yapılıyor)

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [company_qr_tool/app.py:60](../../company_qr_tool/app.py#L60) | <code>def _load_local_env_file() -&gt; None:</code> | .env yalnız aracın kendi klasöründeki BASE_DIR/.env dosyasından okunur (açılışta bir kez) |
| [company_qr_tool/app.py:80](../../company_qr_tool/app.py#L80) | <code>if key and key.replace("_", "").isalnum() and key not in os.environ:</code> | Ortamda ZATEN tanımlı değişken (boş değer bile) .env değerini ezmez; anahtar adı yalnız harf/rakam/_ olabilir |
| [company_qr_tool/app.py:119](../../company_qr_tool/app.py#L119) | <code>def get_company_api_key() -&gt; str:</code> | Anahtarı ortamdan okur; boşsa "tanımlı değil" sayılır |
| [company_qr_tool/app.py:108](../../company_qr_tool/app.py#L108) | <code>COMPANY_KEY_MISSING_MESSAGE = (</code> | Kullanıcıya gösterilen uyarı metni ve çözüm adımları |
| [company_qr_tool/app.py:2023](../../company_qr_tool/app.py#L2023) | <code>error_msg = COMPANY_KEY_MISSING_MESSAGE</code> | Kayıt işçisi anahtar yokken ağ isteği yapmaz; yalnız yerel kayıt tamamlanır |
| [company_qr_tool/app.py:544](../../company_qr_tool/app.py#L544) | <code>return [], f"{COMPANY_KEY_ENV} tanimli degil: sunucu listesi alinamadi, yalnizca yerel ka…</code> | Liste/PDF/Kayıtlı Cihazlar penceresi anahtar yokken yalnız yerel kayıtları gösterir |
| [company_qr_tool/README.md:125](../../company_qr_tool/README.md#L125) | <code>### Sunucu yetkisi (COMPANY_API_KEY)</code> | Anahtarın nereye yazılacağı (.env veya setx) ve davranışı |

**Olası nedenler**
- company_qr_tool/.env yok ya da app.py ile aynı klasörde değil
- .env içinde satır boş (COMPANY_API_KEY=) ya da başında # var
- Windows kullanıcı ortam değişkeni COMPANY_API_KEY boş değerle tanımlı: .env okunur ama ortamdaki (boş) değer önceliklidir
- setx yapıldı ama uygulama yeniden açılmadı (ortam değişkeni yalnız yeni süreçlere geçer)

**Adım adım kontrol**
- env.example dosyasını .env adıyla kopyalayıp COMPANY_API_KEY değerini doldurun (sır git dışında kalır)
- PowerShell ile yalnız VAR/YOK kontrolü (değeri yazdırmayın): if ([Environment]::GetEnvironmentVariable("COMPANY_API_KEY","User")) { "tanimli" } else { "yok" }
- Uygulamayı kapatıp launch_company_qr_tool.bat ile yeniden açın

**Günlükte aranacak ifadeler**
- `COMPANY_API_KEY tanimli degil`

**Bkz.:** [arac-sunucu-401](#arac-sunucu-401)

<a id="arac-http-anahtar-gonderilmiyor"></a>
### arac-http-anahtar-gonderilmiyor · Yerel/test API adresine (http://...) bağlanınca şirket aracı 401 alıyor, oysa COMPANY_API_KEY tanımlı

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [company_qr_tool/app.py:123](../../company_qr_tool/app.py#L123) | <code>def _is_key_safe_url(url: str) -&gt; bool:</code> | Anahtar yalnız https veya localhost/127.0.0.1/::1 üzerindeki http ile gönderilir |
| [company_qr_tool/app.py:134](../../company_qr_tool/app.py#L134) | <code>def company_request_headers(url: str, extra: dict &#124; None = None) -&gt; dict:</code> | Adres güvenli değilse X-Company-Key eklenmez → sunucu 401 döner |
| [company_qr_tool/app.py:101](../../company_qr_tool/app.py#L101) | <code>PUBLIC_API_URL = _env_str("AHBU_API_URL", "https://api.gudeteknoloji.com.tr").rstrip("/")</code> | Varsayılan https://api.gudeteknoloji.com.tr; AHBU_API_URL ile değiştirilir |
| [company_qr_tool/app.py:104](../../company_qr_tool/app.py#L104) | <code>API_FALLBACK_URL = _env_str("AHBU_API_FALLBACK_URL", "").rstrip("/")</code> | Düz http yedek uç varsayılan KAPALI (boş) |
| [company_qr_tool/env.example:17](../../company_qr_tool/env.example#L17) | <code># AHBU_API_FALLBACK_URL=http://127.0.0.1:3000</code> | Yerel geliştirme için örnek; yalnız localhost http güvenli sayılır |

**Olası nedenler**
- AHBU_API_URL http://192.168.x.x:... gibi LAN adresi: localhost olmadığı için anahtar gönderilmez
- Yedek uç düz http IP ile tanımlandı

**Adım adım kontrol**
- Canlı için AHBU_API_URL tanımsız bırakın (https varsayılan)
- Yerel denemede API'yi aynı bilgisayarda çalıştırıp http://127.0.0.1:<port> kullanın

**Bkz.:** [arac-sunucu-401](#arac-sunucu-401)

<a id="arac-sftp-known-hosts"></a>
### arac-sftp-known-hosts · Şirket aracı "Guncelleme Dosyasini Sunucuya gonder" sırasında "Sunucu kimligi dogrulanamadi ... known_hosts" ya da "UYUSMUYOR" uyarısı veriyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [company_qr_tool/app.py:191](../../company_qr_tool/app.py#L191) | <code>def known_hosts_setup_help() -&gt; str:</code> | İlk kurulum adımlarını ve known_hosts yolunu yazan yardım metni |
| [company_qr_tool/app.py:215](../../company_qr_tool/app.py#L215) | <code>client.set_missing_host_key_policy(paramiko.RejectPolicy())</code> | Bilinmeyen sunucuya otomatik güvenilmez (AutoAddPolicy YOK) |
| [company_qr_tool/app.py:238](../../company_qr_tool/app.py#L238) | <code>except paramiko.BadHostKeyException as exc:</code> | Kayıtlı anahtar ile sunucunun anahtarı uyuşmazsa "UYUSMUYOR" hatası |
| [company_qr_tool/app.py:2529](../../company_qr_tool/app.py#L2529) | <code>if not known_hosts_path().is_file():</code> | Sunucuya gönder düğmesi known_hosts dosyası yoksa hiç bağlanmadan bu uyarıyı gösterir |
| [company_qr_tool/README.md:136](../../company_qr_tool/README.md#L136) | <code>### SFTP ile firmware gonderme: sunucu kimligi dogrulamasi</code> | İlk kurulum ve sunucu yeniden kurulursa yapılacaklar |

**Olası nedenler**
- known_hosts dosyasında 178.210.161.55:22667 kaydı yok (ilk kurulum yapılmamış)
- VPS yeniden kuruldu / anahtar değişti: kayıtlı eski anahtar uyuşmuyor (önce parmak izini sunucudan doğrulayın)
- SSH_KNOWN_HOSTS başka bir dosyayı gösteriyor

**Adım adım kontrol**
- Sunucudaki parmak izini öğrenin, bu bilgisayardaki kayıtla karşılaştırın; eşleşmiyorsa kaydı silip yeniden ekleyin
- Eski kayıt silme: ssh-keygen -R "[178.210.161.55]:22667"

**Günlükte aranacak ifadeler**
- `Sunucu kimligi dogrulanamadi`
- `UYUSMUYOR`

**Komutlar**
```bash
ssh -p 22667 salihceylan@178.210.161.55 "ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub"
ssh-keyscan -p 22667 -H 178.210.161.55 >> %USERPROFILE%\.ssh\known_hosts
ssh-keygen -lf %USERPROFILE%\.ssh\known_hosts
ssh-keygen -R "[178.210.161.55]:22667"
```

**Bkz.:** [arac-sftp-kimlik](#arac-sftp-kimlik)

<a id="arac-sftp-kimlik"></a>
### arac-sftp-kimlik · Sunucuya gönderirken "SSH_KEY_FILE bulunamadi", "SSH anahtari parola ile korunuyor" veya şifre soruyor / "Sunucu yukleme hatasi"

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [company_qr_tool/app.py:222](../../company_qr_tool/app.py#L222) | <code>key_file = os.environ.get("SSH_KEY_FILE", "").strip()</code> | Anahtar tanımlıysa anahtarla, değilse parolayla bağlanır |
| [company_qr_tool/app.py:226](../../company_qr_tool/app.py#L226) | <code>raise RuntimeError(f"SSH_KEY_FILE bulunamadi: {key_path}")</code> | Anahtar dosyası yolu yanlış |
| [company_qr_tool/app.py:245](../../company_qr_tool/app.py#L245) | <code>except paramiko.PasswordRequiredException as exc:</code> | Anahtar parolalıysa SSH_KEY_PASSPHRASE gerekir |
| [company_qr_tool/app.py:2536](../../company_qr_tool/app.py#L2536) | <code>password = os.environ.get("AHBU_VPS_PASSWORD", "").strip()</code> | Anahtar yoksa parola: önce AHBU_VPS_PASSWORD, yoksa diyalog; boş bırakılırsa işlem sessizce iptal olur |
| [company_qr_tool/app.py:2573](../../company_qr_tool/app.py#L2573) | <code>import paramiko</code> | paramiko burada tembel içe alınır: kurulu değilse "Sunucu yukleme hatasi" ile düşer |
| [company_qr_tool/app.py:2577](../../company_qr_tool/app.py#L2577) | <code>vps_target_dir = f"{VPS_FIRMWARE_BASE_DIR}/{target}"</code> | Dosyalar donanım hedef klasörüne (esp32-c3 / esp32-wroom) gider: AGENTS.md kural 4 izolasyonu |
| [company_qr_tool/requirements.txt:5](../../company_qr_tool/requirements.txt#L5) | <code>paramiko&gt;=3.4.0</code> | SFTP için gerekli paket |

**Olası nedenler**
- SSH_KEY_FILE yolu yanlış / dosya yok
- Anahtar parola korumalı ama SSH_KEY_PASSPHRASE tanımsız
- Anahtar tanımsız ve VPS şifresi boş girildi ya da yanlış
- .venv içinde paramiko kurulu değil (launch .bat pip install adımı başarısız olmuş)
- Yanlış env seçili: dosyalar yanlış donanım klasörüne gider (c3 / wroom ayrımı env adından çıkar)

**Adım adım kontrol**
- README "Kimlik dogrulama" bölümü: önerilen yol SSH_KEY_FILE
- Sunucuda dosyalar: /var/www/site_kapi_kontrol/server/firmware/<hedef>/firmware.bin ve manifest.json

**Bkz.:** [arac-sftp-known-hosts](#arac-sftp-known-hosts), [arac-surum-derleme](#arac-surum-derleme)

<a id="arac-uid-okunamadi"></a>
### arac-uid-okunamadi · Şirket aracında "Secili cihaz UID oku" → "Cihaz Unique ID okunamadi!" hatası ya da çip "ESP32" (belirsiz) görünüyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [company_qr_tool/app.py:833](../../company_qr_tool/app.py#L833) | <code>def read_mac(port: str) -&gt; tuple[str, str]:</code> | Önce çalışan firmware'den seri komutla UID okur; olmazsa esptool ile MAC okur |
| [company_qr_tool/app.py:861](../../company_qr_tool/app.py#L861) | <code>m_uid = re.search(r"Cihaz Unique ID:\s*([0-9A-Fa-f]{6,20})", buf)</code> | Firmware çıktısındaki "Cihaz Unique ID:" satırı beklenir |
| [company_qr_tool/app.py:875](../../company_qr_tool/app.py#L875) | <code>return "ESP32", uid_found</code> | Eski firmware "Hardware Target" yazmazsa çip belirsiz kalır (sunucu donanım türünü tahmin ETMEZ) |
| [company_qr_tool/app.py:423](../../company_qr_tool/app.py#L423) | <code>def mac_to_firmware_uid(mac: str) -&gt; str:</code> | esptool yolunda MAC baytları TERS çevrilip 12 haneli UID yapılır |
| [company_qr_tool/app.py:900](../../company_qr_tool/app.py#L900) | <code>"Cihaz Unique ID okunamadi!\n\n"</code> | Hata iletisi: port meşgul / CH340 BOOT-EN adımları / kablo |
| [company_qr_tool/app.py:820](../../company_qr_tool/app.py#L820) | <code>def find_esptool_python() -&gt; str:</code> | esptool'u çalıştıracak Python: önce kendi, sonra PlatformIO penv |
| [company_qr_tool/app.py:1856](../../company_qr_tool/app.py#L1856) | <code>def _read_uid_worker(self, port: str, dev: EspDevice) -&gt; None:</code> | UID okumadan önce Cihaz Dene penceresinin seri bağlantısını keser |

**Olası nedenler**
- Port meşgul: Cihaz Dene, VS Code seri monitörü veya başka program portu tutuyor
- Harici CH340/USB-TTL ile kart otomatik indirme moduna geçemiyor: BOOT basılı + EN bas-bırak + BOOT bırak
- Kablo/sürücü sorunu (CH340 / CP210x)
- Boş flash veya eski firmware: seri yanıt yok, esptool yoluna düşülür (esptool kurulu/çalışır olmalı)

**Adım adım kontrol**
- Kapalı olduğundan emin olun: Cihaz Dene penceresi, serial monitor
- USB kablosunu çıkarıp takın, tekrar "Bagli cihazlari tara" → "Secili cihaz UID oku"
- Çip "ESP32" kalıyorsa firmware'i güncelleyip UID'yi yeniden okuyun (kayıtta donanım türü boş gitmesin)

**Günlükte aranacak ifadeler**
- `Cihaz Unique ID okunamadi!`

**Bkz.:** [arac-kayit-http-400-donanim](#arac-kayit-http-400-donanim), [arac-cihaz-dene-durum-bos](#arac-cihaz-dene-durum-bos)

<a id="arac-kayit-http-400-donanim"></a>
### arac-kayit-http-400-donanim · "Cihazı Sunucuya Kaydet" hata veriyor (HTTP 400 "device_uid 12 haneli hex", HTTP 500, 429) ya da kayıttan sonra WROOM kart OTA'da 403 alıyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [company_qr_tool/app.py:1983](../../company_qr_tool/app.py#L1983) | <code>hardware_type = chip_to_hardware_type(d.chip)</code> | Çipten donanım türü çıkarılır; belirsizse alan hiç gönderilmez |
| [company_qr_tool/app.py:175](../../company_qr_tool/app.py#L175) | <code>def chip_to_hardware_type(chip: str) -&gt; str:</code> | C3 → esp32_c3; WROOM/WROVER/D0WD → esp32_wroom; diğeri boş |
| [company_qr_tool/app.py:2013](../../company_qr_tool/app.py#L2013) | <code>def _server_device_save_worker(self, dev: EspDevice, payload: dict) -&gt; None:</code> | POST /api/company/labeled-devices çağrısı; hata metni _company_http_error_text ile gösterilir |
| [server/src/routes/company_routes.js:326](../../server/src/routes/company_routes.js#L326) | <code>return res.status(400).json({ error: 'device_uid 12 haneli hex (0-9, A-F) olmalidir.' });</code> | Sunucu UID'yi 12 haneli büyük harf hex ister (":" ve "-" ayırıcıları tolere edilir) |
| [server/src/routes/company_routes.js:110](../../server/src/routes/company_routes.js#L110) | <code>export function resolveCompanyHardwareType(body) {</code> | hardware_type/hardware_target/chip alanlarından türü çıkarır; çıkaramazsa null |
| [server/src/routes/company_routes.js:127](../../server/src/routes/company_routes.js#L127) | <code>const DEFAULT_COMPANY_HARDWARE_TYPE = 'esp32_c3';</code> | Tür belirlenemezse varsayılan esp32_c3 yazılır; cihaz MQTT bildirimi sonradan düzeltir |
| [server/src/server.js:92](../../server/src/server.js#L92) | <code>app.post('/api/company/labeled-devices', companyAccessLimiter, requireCompanyAccess, expr…</code> | Bu uca özel 5 MB JSON limiti (QR PNG base64); hız sınırı yetkiden ÖNCE çalışır |

**Olası nedenler**
- UID 12 haneli değil (ör. eski firmware farklı uzunlukta UID bildiriyor) → 400
- Çip "ESP32" kaldı → hardware_type gönderilmedi → varsayılan esp32_c3 yazıldı; WROOM kartın OTA'sı hedef uyuşmazlığıyla 403 olabilir
- Çok sık istek: 15 dakikada 300 istek sınırı → 429
- Veritabanı hatası → 500 (kayıt dosyaya yazılmadan önce kesilir; aynı UID ile tekrar deneme güvenlidir)

**Adım adım kontrol**
- Hata iletisindeki "Hata kodu" (errorId) ile sunucu günlüğünü eşleştirin
- Çipin "ESP32-WROOM" ya da "ESP32-C3" okunduğundan emin olun (UID oku adımı)
- Sunucuda cihazın hardware_type değeri: SELECT device_uid, hardware_type FROM devices WHERE device_uid = '<UID>'

**İlgili testler:** [server/test/fix_sx1_company_ota.test.js](../../server/test/fix_sx1_company_ota.test.js), [server/test/core_company_routes_http.test.js](../../server/test/core_company_routes_http.test.js), [server/test/core_company_auth.test.js](../../server/test/core_company_auth.test.js)

**Bkz.:** [arac-uid-okunamadi](#arac-uid-okunamadi), [arac-sunucu-401](#arac-sunucu-401)

<a id="arac-usb-yukleme-hata"></a>
### arac-usb-yukleme-hata · Şirket aracında "USB ile karta yükle" hata veriyor: "portu meşgul (Erişim engellendi)" veya "Bağlantı / Yazma Zaman Aşımı"

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [company_qr_tool/app.py:2395](../../company_qr_tool/app.py#L2395) | <code>def _upload_worker(self, dev: EspDevice, rel: dict) -&gt; None:</code> | USB yükleme işçisi: esptool write_flash ile bootloader + partitions + firmware yazar |
| [company_qr_tool/app.py:2461](../../company_qr_tool/app.py#L2461) | <code>f"{dev.port} portu meşgul (Erişim engellendi).\n\n"</code> | PermissionError / "port is busy" için çözüm adımları |
| [company_qr_tool/app.py:2467](../../company_qr_tool/app.py#L2467) | <code>if "write timeout" in err_lower or "failed to connect" in err_lower or "timed out waiting…</code> | Zaman aşımı/bağlanamama için BOOT+EN adımlarını anlatan hata |
| [company_qr_tool/app.py:263](../../company_qr_tool/app.py#L263) | <code>def bootloader_offset_for_env(env: str) -&gt; str:</code> | Bootloader ofseti hedefe göre: WROOM 0x1000, C3 0x0 (yanlış env = bozuk yazım) |
| [company_qr_tool/app.py:256](../../company_qr_tool/app.py#L256) | <code>def target_for_env(env: str) -&gt; str:</code> | Env adından hedef çıkarır: "wroom" veya "esp32dev" içeriyorsa esp32-wroom, aksi halde esp32-c3 |
| [company_qr_tool/app.py:1095](../../company_qr_tool/app.py#L1095) | <code>def suggest_env_for_chip(chip: str, envs: list[str]) -&gt; str &#124; None:</code> | Çipe göre env önerisi: C3 → *c3*, WROOM/ESP32 → *wroom*/esp32dev; çip bilinmiyorsa lolin_c3_mini |
| [company_qr_tool/app.py:2416](../../company_qr_tool/app.py#L2416) | <code>if "v5." in (ver_res.stdout + ver_res.stderr):</code> | esptool v5 ise komut write-flash, değilse write_flash kullanılır |
| [company_qr_tool/app.py:2492](../../company_qr_tool/app.py#L2492) | <code>"erase_region",</code> | Yazımdan sonra OTA seçim bölgesi (0xe000, 0x2000) silinir ki yeni sürüm açılsın |

**Olası nedenler**
- Port meşgul: "Cihaz testi" sayfasındaki bağlantı, VS Code seri monitörü veya başka program portu tutuyor
- Harici CH340/USB-TTL: kart kendiliğinden indirme moduna geçemez (BOOT basılı + EN bas-bırak + BOOT bırak)
- Yanlış env seçili (C3 kartına WROOM env'i): bootloader ofseti ve ikili dosya uyumsuz olur
- Kablo yalnız şarj kablosu / sürücü yok

**Adım adım kontrol**
- "Cihaz testi" sayfasında "Bağlantıyı kes"e basın, serial monitor terminalini kapatın
- Env, UID okununca çipe göre seçilir (suggest_env_for_chip); UID OKUNMADAN cihaz seçilirse lolin_c3_mini önerilir: WROOM kartı için önce UID okuyun ya da env'i elle düzeltin
- Önce "Derle" → "Sürüm oluştur" tamamlanmış olmalı (yoksa "Surum gerekli" uyarısı)

**Günlükte aranacak ifadeler**
- `portu meşgul (Erişim engellendi)`
- `Bağlantı / Yazma Zaman Aşımı`

**Bkz.:** [arac-usb-yukleme-sessiz-basarisizlik](#arac-usb-yukleme-sessiz-basarisizlik), [arac-surum-derleme](#arac-surum-derleme)

<a id="arac-usb-yukleme-sessiz-basarisizlik"></a>
### arac-usb-yukleme-sessiz-basarisizlik · USB yükleme "TMM: Yazılım yükleme tamamlandı" ("TMM · Yükleme tamamlandı") dedi ama cihaz hâlâ eski sürümde / açılmıyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [company_qr_tool/app.py:2455](../../company_qr_tool/app.py#L2455) | <code>rc, tail = self._run_stream(cmd, DEVICE_PROJECT_DIR, on_line=on_line)</code> | esptool çıkış kodu burada alınır |
| [company_qr_tool/app.py:2457](../../company_qr_tool/app.py#L2457) | <code>raw_err = "\n".join(tail[-8:]) if tail else "Yukleme hatasi."</code> | rc != 0 bloğunda YALNIZ iki hata kalıbı (port meşgul, zaman aşımı) exception fırlatır; başka bir esptool hatası fırlatılmaz |
| [company_qr_tool/app.py:2496](../../company_qr_tool/app.py#L2496) | <code>self._run_stream(cmd_erase_ota, DEVICE_PROJECT_DIR)</code> | OTA bölgesi silme sonucu denetlenmez; hata sessizce yutulur |
| [company_qr_tool/app.py:2502](../../company_qr_tool/app.py#L2502) | <code>self.root.after(0, lambda: self.set_status(f"TMM: Yazılım yükleme tamamlandı ({dev.port},…</code> | Önceki adımlar hata fırlatmadıysa (rc != 0 olsa bile) başarı mesajı ve "TMM · Yükleme tamamlandı" bildirimi gösterilir |

**Olası nedenler**
- Kodda: rc != 0 olup hata metni "permissionerror/port is busy/erişim engellendi" ya da "write timeout/failed to connect/timed out waiting/no serial data" kalıplarına uymazsa hata fırlatılmaz ve "TMM" gösterilir (araç kusuru; gerçek durum esptool çıktısındadır)
- Yazım gerçekten başarılı ama cihaz yanlış donanım hedefi için derlenmiş bir sürümle açılmıyor

**Adım adım kontrol**
- Durum çubuğu/ilerleme çıktısında son esptool satırlarına bakın ("Hash of data verified." görülmeli)
- "Cihaz testi" sayfasında bağlanıp "Yazılım sürümü" ve "OTA durumu" alanlarını okuyun (cihaz resetlenir)
- Şüphede aynı sürümü bir kez daha yükleyin ya da "Çalışma arkadaşı için ZIP" paketindeki flash_smartkeypass_usb.bat'ı çalıştırın

**Bkz.:** [arac-usb-yukleme-hata](#arac-usb-yukleme-hata), [arac-cihaz-dene-durum-bos](#arac-cihaz-dene-durum-bos)

<a id="arac-surum-derleme"></a>
### arac-surum-derleme · Şirket aracında "Derle" / "Sürüm oluştur" başarısız ya da düğmeler pasif ("Once derleme ve surum olusturma adimlarini basariyla tamamlayin")

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [company_qr_tool/app.py:817](../../company_qr_tool/app.py#L817) | <code>raise FileNotFoundError("PlatformIO bulunamadi.")</code> | platformio PATH'te ve ~/.platformio/penv altında yoksa derleme başlamaz |
| [company_qr_tool/app.py:277](../../company_qr_tool/app.py#L277) | <code>SEMVER_RE = re.compile(r"^\d+\.\d+\.\d+$")</code> | Sürüm yalnız X.Y.Z biçiminde olabilir |
| [company_qr_tool/app.py:2159](../../company_qr_tool/app.py#L2159) | <code>def _apply_fw_button_state(self) -&gt; None:</code> | "Sürüm oluştur" yalnız derleme hazırsa, yükle/sunucuya gönder/ZIP yalnız sürüm hazırsa açılır; env ya da sürüm değişince hazırlık sıfırlanır |
| [company_qr_tool/app.py:2151](../../company_qr_tool/app.py#L2151) | <code>def _on_fw_input_changed(self) -&gt; None:</code> | Env veya sürüm kutusu değişince derleme/sürüm "hazır" bayrakları düşer |
| [company_qr_tool/app.py:2311](../../company_qr_tool/app.py#L2311) | <code>raise FileNotFoundError(f"Build ciktilari eksik: {', '.join(missing)}")</code> | Derleme çıktıları (.pio/build/<env>/firmware.bin, bootloader.bin, partitions.bin) yoksa sürüm oluşmaz |
| [company_qr_tool/app.py:956](../../company_qr_tool/app.py#L956) | <code>def save_releases(releases: list[dict]) -&gt; None:</code> | Sürüm kaydı cihaz_kontrol/firmware_releases/index.json dosyasına yazılır |
| [company_qr_tool/app.py:912](../../company_qr_tool/app.py#L912) | <code>def parse_envs(path: Path) -&gt; tuple[list[str], dict[str, int]]:</code> | Env listesi cihaz_kontrol/platformio.ini içindeki [env:...] bölümlerinden okunur |

**Olası nedenler**
- PlatformIO kurulu değil / PATH dışında
- Sürüm biçimi X.Y.Z değil
- Derleme hata verdi (PlatformIO çıktısının son 8 satırı hata penceresinde gösterilir)
- Env/sürüm değiştirildi: önceki derleme geçersiz sayılır, adımlar baştan yapılmalı
- platformio.ini bulunamadı → env listesi boş

**Adım adım kontrol**
- Adım sırası: Derle → Sürüm oluştur → (USB ile karta yükle | Sunucuya gönder (OTA) | Çalışma arkadaşı için ZIP)
- cihaz_kontrol klasöründe elle derleme: pio run -e lolin_c3_mini (ya da esp32_relay_wroom)

**Komutlar**
```bash
pio run -d cihaz_kontrol -e lolin_c3_mini
pio run -d cihaz_kontrol -e esp32_relay_wroom
```

**Bkz.:** [arac-ota-basligi-degisti](#arac-ota-basligi-degisti), [arac-usb-yukleme-hata](#arac-usb-yukleme-hata), [arac-sftp-kimlik](#arac-sftp-kimlik)

<a id="arac-ota-basligi-degisti"></a>
### arac-ota-basligi-degisti · git durumunda cihaz_kontrol/include/ota_guncelleme.h kendiliğinden değişmiş görünüyor (sürüm numarası farklı)

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [company_qr_tool/app.py:983](../../company_qr_tool/app.py#L983) | <code>def write_firmware_source_version(version: str, env: str &#124; None = None) -&gt; bool:</code> | Seçili env'e göre ota_guncelleme.h içindeki OTA_VERSION_C3 / OTA_VERSION_WROOM / OTA_CURRENT_VERSION değerini yeniden yazar |
| [company_qr_tool/app.py:2228](../../company_qr_tool/app.py#L2228) | <code># Otomatik versiyon senkronizasyonu: ota_guncelleme.h dosyasini guncelle</code> | "Derle" düğmesi derlemeden ÖNCE başlığı günceller |
| [company_qr_tool/app.py:961](../../company_qr_tool/app.py#L961) | <code>def read_firmware_source_version(env: str &#124; None = None) -&gt; str &#124; None:</code> | Sürüm kutusunun başlangıç değeri başlıktan okunur (yoksa son sürüm + 1) |
| [company_qr_tool/app.py:278](../../company_qr_tool/app.py#L278) | <code>OTA_VERSION_C3_RE = re.compile(r'OTA_VERSION_C3\[\]\s*=\s*"(\d+\.\d+\.\d+)"')</code> | Başlıkta aranan desen: OTA_VERSION_C3[] = "x.y.z" |
| [cihaz_kontrol/include/ota_guncelleme.h:27](../../cihaz_kontrol/include/ota_guncelleme.h#L27) | <code>inline constexpr char OTA_VERSION_C3[] = "4.3.3";</code> | Araç bu satırı değiştirir; C3 hedef sürümü |
| [cihaz_kontrol/include/ota_guncelleme.h:28](../../cihaz_kontrol/include/ota_guncelleme.h#L28) | <code>inline constexpr char OTA_VERSION_WROOM[] = "5.2.2";</code> | WROOM hedef sürümü (hedefler birbirinden bağımsız: AGENTS.md kural 4) |

**Olası nedenler**
- Şirket aracında "Derle" veya "Sürüm oluştur" kullanıldı: başlık seçilen sürüme eşitlenir (tasarım gereği)
- WROOM env'i seçiliyken C3 sürümü değişmez, tersi de (hedef başına ayrı sabit)

**Adım adım kontrol**
- git diff cihaz_kontrol/include/ota_guncelleme.h ile yalnız sürüm satırlarının değiştiğini doğrulayın
- İstenmeyen sürüm yazıldıysa OTA hedefleri karışmasın diye ilgili sabiti elle eski değerine alın (başka satırlara dokunmayın)

**Komutlar**
```bash
git diff -- cihaz_kontrol/include/ota_guncelleme.h
```

**Bkz.:** [arac-surum-derleme](#arac-surum-derleme)

<a id="arac-zip-hatasi"></a>
### arac-zip-hatasi · Şirket aracında "Çalışma arkadaşı için ZIP" hata veriyor ("ZIP icin gerekli arac klasoru yok" / "Guncelleme dosyasi yok" / "Surum gerekli")

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [company_qr_tool/app.py:2617](../../company_qr_tool/app.py#L2617) | <code>def start_coworker_zip(self) -&gt; None:</code> | Düğme yalnız derleme + sürüm hazırken (aynı env ve sürüm) çalışır, yoksa "Surum gerekli"; kayıt yeri sorulur |
| [company_qr_tool/app.py:2644](../../company_qr_tool/app.py#L2644) | <code>def _coworker_zip_worker(self, rel: dict, target: Path) -&gt; None:</code> | ZIP işçisi: firmware, manifest, flash_smartkeypass_usb.bat, README ve PlatformIO araçlarını paketler |
| [company_qr_tool/app.py:2649](../../company_qr_tool/app.py#L2649) | <code>raise FileNotFoundError(f"Guncelleme dosyasi yok: {p}")</code> | Sürümün bootloader / partitions / firmware / manifest dosyalarından biri yoksa ZIP yapılmaz |
| [company_qr_tool/app.py:2650](../../company_qr_tool/app.py#L2650) | <code>required_tool_dirs = [</code> | ~/.platformio altında python3, packages/tool-esptoolpy ve penv/Lib/site-packages/serial klasörleri bulunmalı |
| [company_qr_tool/app.py:2663](../../company_qr_tool/app.py#L2663) | <code>hw_target = target_for_env(env)</code> | Donanım hedefi ve bootloader ofseti sürümün env'inden çıkarılır; bat dosyasına ve README'ye yazılır |
| [company_qr_tool/app.py:2761](../../company_qr_tool/app.py#L2761) | <code>zf.writestr("flash_smartkeypass_usb.bat", bat)</code> | Pakete konan bat dosyası: otomatik COM port bulur, esptool ile yazar |

**Olası nedenler**
- ~/.platformio/python3, packages/tool-esptoolpy veya penv/Lib/site-packages/serial yok (PlatformIO bu bilgisayarda kurulmamış/farklı konumda)
- Sürüm dosyaları eksik (firmware_releases altındaki dosyalar silinmiş/taşınmış): "Guncelleme dosyasi yok"
- Derleme / sürüm adımları tamamlanmadı ya da env veya sürüm sonradan değişti: "Surum gerekli"
- Seçilen kayıt yerine yazılamıyor (izin, dolu disk): "ZIP hatası" penceresi nedeni yazar

**Adım adım kontrol**
- Hata penceresindeki eksik klasör / dosya yolunu kontrol edin
- ZIP olmadan da yüklenebilir: "USB ile karta yükle"

**Bkz.:** [arac-surum-derleme](#arac-surum-derleme), [arac-usb-yukleme-hata](#arac-usb-yukleme-hata)

<a id="arac-qr-etiket"></a>
### arac-qr-etiket · Üretilen QR etiketi okunmuyor / etiket altındaki "Unique ID" cihazın gerçek UID'sinden farklı / "Logo bulunamadi"

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [company_qr_tool/app.py:449](../../company_qr_tool/app.py#L449) | <code>def generate_qr(unique_id: str, logo_path: Path) -&gt; Image.Image:</code> | QR içeriği yalnızca büyük harfe çevrilmiş UID; hata düzeltme H, ortada logo rozeti (assets/smartkeypass_logo.png); altına "Unique ID: <UID>" yazılır |
| [company_qr_tool/app.py:412](../../company_qr_tool/app.py#L412) | <code>def ensure_logo() -&gt; Path:</code> | Logo assets/smartkeypass_logo.png dosyasından alınır; dosya yoksa FileNotFoundError ("Logo bulunamadi: <yol>") fırlatılır |
| [company_qr_tool/app.py:41](../../company_qr_tool/app.py#L41) | <code>LOGO_PATH = ASSETS_DIR / "smartkeypass_logo.png"</code> | Karekod ve rapor logosu: company_qr_tool/assets/smartkeypass_logo.png |
| [company_qr_tool/app.py:423](../../company_qr_tool/app.py#L423) | <code>def mac_to_firmware_uid(mac: str) -&gt; str:</code> | esptool yolunda UID = MAC baytlarının tersi (firmware UID biçimiyle aynı) |
| [company_qr_tool/app.py:1913](../../company_qr_tool/app.py#L1913) | <code>def save_qr(self) -&gt; None:</code> | PNG output/ klasörüne zaman damgalı adla kaydedilir (git dışı) |
| [company_qr_tool/app.py:1924](../../company_qr_tool/app.py#L1924) | <code>def print_qr(self) -&gt; None:</code> | Yazdırma yalnız Windows'ta os.startfile(..., "print") ile yapılır |

**Olası nedenler**
- Etiket yanlış cihazdan okunan UID ile üretilmiş (listeden başka port seçili)
- Logo dosyası yok (assets/smartkeypass_logo.png bulunamadı)
- QR çok küçük basıldı (QR 1200 px; etiket yazıcısı ölçeklemesi)

**Adım adım kontrol**
- QR'ı üretmeden önce "Secili cihaz UID oku" ile UID'nin göründüğünü doğrulayın
- Aynı UID'li kaydı "Kayıtlı Cihazlar & Karekodlar" penceresinde karşılaştırın

**Bkz.:** [arac-uid-okunamadi](#arac-uid-okunamadi), [arac-kayitli-cihazlar-pdf](#arac-kayitli-cihazlar-pdf)

<a id="arac-kayitli-cihazlar-pdf"></a>
### arac-kayitli-cihazlar-pdf · Kayıtlı Cihazlar listesi eksik/farklı, silme "Kısmi Silme" diyor ya da PDF raporu yazıları bozuk / "PDF Hatası"

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [company_qr_tool/app.py:2937](../../company_qr_tool/app.py#L2937) | <code>def _fetch_worker(self) -&gt; None:</code> | Liste = sunucu kayıtları + yerelde olup sunucuda olmayanlar (UID ile birleştirilir; sunucu önceliklidir) |
| [company_qr_tool/app.py:541](../../company_qr_tool/app.py#L541) | <code>def fetch_server_labeled_devices_with_status() -&gt; tuple[list[dict], str]:</code> | Sunucu listesi alınamazsa neden döner (anahtar yok / 401 / ağ) ve yalnız yerel kayıtlar kalır |
| [company_qr_tool/app.py:40](../../company_qr_tool/app.py#L40) | <code>LABELED_DEVICES_FILE = OUTPUT_DIR / "labeled_devices.json"</code> | Yerel indeks: company_qr_tool/output/labeled_devices.json (git dışı) |
| [company_qr_tool/app.py:3026](../../company_qr_tool/app.py#L3026) | <code>def _delete_selected_device(self) -&gt; None:</code> | Önce yerel kayıt + PNG silinir, sonra sunucudan silinir; sunucu hatası "Kısmi Silme" uyarısı verir |
| [company_qr_tool/app.py:585](../../company_qr_tool/app.py#L585) | <code>def delete_server_labeled_device(device_uid: str) -&gt; tuple[bool, str]:</code> | DELETE /api/company/labeled-devices/<UID>; anahtar yoksa sunucudan silinmez |
| [company_qr_tool/app.py:648](../../company_qr_tool/app.py#L648) | <code>def generate_devices_catalog_pdf(</code> | A4 2480x3508 (300 DPI), sayfa başına 6 kart; QR'lar her kart için yeniden üretilir |
| [company_qr_tool/app.py:483](../../company_qr_tool/app.py#L483) | <code>def load_regular_font(size: int) -&gt; ImageFont.FreeTypeFont &#124; ImageFont.ImageFont:</code> | Yazı tipi C:/Windows/Fonts altından aranır (segoeui/arial/calibri); yoksa Pillow varsayılanı (küçük/Türkçe karakter sorunu) |
| [server/src/routes/company_routes.js:407](../../server/src/routes/company_routes.js#L407) | <code>companyRouter.delete('/api/company/labeled-devices/:deviceUid', async (req, res) =&gt; {</code> | Sunucu silme ucu (cihaz, kapı bağı ve MQTT ACL senkronu) |

**Olası nedenler**
- COMPANY_API_KEY yok/yanlış: yalnız yerel kayıtlar listelenir
- Aynı cihaz iki makinede etiketlendi: yerel indeksler birbirinden bağımsızdır
- Sunucudan silme başarısız (401/ağ): kayıt yerelden silinmiş olur, sunucuda kalır
- Windows yazı tipleri bulunamadı (başka işletim sistemi)

**Adım adım kontrol**
- Durum çubuğundaki sunucu uyarısını okuyun
- Yerel ve sunucu kayıtlarını karşılaştırın: output/labeled_devices.json ↔ /api/company/labeled-devices

**İlgili testler:** [server/test/fix_sx1_company_ota.test.js](../../server/test/fix_sx1_company_ota.test.js)

**Bkz.:** [arac-sunucu-401](#arac-sunucu-401), [arac-anahtar-tanimli-degil](#arac-anahtar-tanimli-degil)

<a id="arac-cihaz-dene-durum-bos"></a>
### arac-cihaz-dene-durum-bos · Cihaz Dene (cihaz_dene/app.py ya da şirket aracındaki "Cihaz testi" sayfası): bilgi alanları "-" kalıyor veya Role Pin HIGH/LOW/Pin Bulma tepki vermiyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [cihaz_dene/app.py:17](../../cihaz_dene/app.py#L17) | <code>STATUS_START = "----- CIHAZ DURUMU -----"</code> | Bağımsız araç ESKİ başlığı bekler; güncel firmware "--- ESP32 SISTEM BILGISI ---" yazar (bu araçta alanlar dolmaz) |
| [company_qr_tool/app.py:3113](../../company_qr_tool/app.py#L3113) | <code>STATUS_START = "--- ESP32 SISTEM BILGISI ---"</code> | Şirket aracındaki "Cihaz testi" sayfası güncel başlığı tanır (eski başlığı da: STATUS_START_ALT) |
| [company_qr_tool/app.py:3404](../../company_qr_tool/app.py#L3404) | <code>if line.strip().startswith("---") and self._collecting_status and len(self._status_lines)…</code> | Blok, ilk "---" ile başlayan satırda (en az 3 satır sonra) kapanır ve alanlara işlenir |
| [company_qr_tool/app.py:3429](../../company_qr_tool/app.py#L3429) | <code>key_map = {</code> | Firmware anahtarlarını arayüz alanlarına çevirir (Cihaz Unique ID → Cihaz UID vb.) |
| [cihaz_kontrol/src/main.cpp:355](../../cihaz_kontrol/src/main.cpp#L355) | <code>Serial.println("--- ESP32 SISTEM BILGISI ---");</code> | Firmware durum bloğu; "?" (ve s/u/i) komutuyla yazılır |
| [cihaz_kontrol/src/main.cpp:191](../../cihaz_kontrol/src/main.cpp#L191) | <code>Serial.println("Atolye modu kapali (Wi-Fi sifirlayin veya reset butonu 3 sn)");</code> | h/l/p seri komutları yalnız ATÖLYE MODUNDA çalışır; r ve k her derlemede açık |
| [company_qr_tool/app.py:367](../../company_qr_tool/app.py#L367) | <code># DTR/RTS MUTLAKA open() oncesinde False yapilmali!</code> | Seri bağlantıda DTR/RTS kontrolü (CH340 kartı indirme moduna sokmasın) |
| [cihaz_dene/app.py:71](../../cihaz_dene/app.py#L71) | <code>self._serial = serial.Serial(self.port, BAUD_RATE, timeout=0.2)</code> | Bağımsız araç portu DTR/RTS ayarlamadan açar (yukarıdaki yorumdaki risk geçerli olabilir) |

**Olası nedenler**
- Bağımsız cihaz_dene/app.py kullanılıyor: eski durum başlığı güncel firmware ile eşleşmez
- Bağlantı kuruldu ama cihaz durum bloğu yazmadı: "?" komutu hiç gitmedi ya da yanlış port
- h/l/p butonları: cihaz atölye modunda değil (günlükte "Atolye modu kapali ...")
- Port başka programda açık (bağlanamaz, "[hata]" görünür)

**Adım adım kontrol**
- Şirket aracındaki "Cihaz testi" sayfasını kullanın (güncel başlık + anahtar eşlemesi)
- Seri günlüğünde "--- ESP32 SISTEM BILGISI ---" bloğu görünüyor mu
- Atölye modu: Wi-Fi sıfırlama veya reset butonu 3 sn (firmware mesajı)

**Günlükte aranacak ifadeler**
- `Atolye modu kapali (Wi-Fi sifirlayin veya reset butonu 3 sn)`
- `--- ESP32 SISTEM BILGISI ---`

**Bkz.:** [arac-cihaz-dene-beacon-wan](#arac-cihaz-dene-beacon-wan), [arac-uid-okunamadi](#arac-uid-okunamadi)

<a id="arac-cihaz-dene-beacon-wan"></a>
### arac-cihaz-dene-beacon-wan · Cihaz testi sayfasında "Yerel Beacon (UDP)" ya da "Genel IP (WAN)" alanı dolmuyor ("-" kalıyor)

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [company_qr_tool/app.py:3305](../../company_qr_tool/app.py#L3305) | <code>def _start_beacon_listener(self) -&gt; None:</code> | UDP 8765 dinleyicisi (yayın kabul eder); soket açılamazsa (port başka uygulamada, izin yok) hata sessizce yutulur ve alan "-" kalır |
| [company_qr_tool/app.py:3338](../../company_qr_tool/app.py#L3338) | <code>if "Yerel Beacon (UDP)" in self.status_vars:</code> | Beacon yalnız bağlı kartın kimliğiyle eşleşirse (ya da kimlik henüz okunmadıysa) "ip:port (rssi dBm) · canlı" yazılır |
| [docs/YEREL_KONTROL_V2.md:9](../../docs/YEREL_KONTROL_V2.md#L9) | <code>- **Beacon** (cihaz → alt ağ broadcast, ~5 sn): `{"device_uid","ip","port":8765,"rssi","h…</code> | Cihazın yayınladığı beacon biçimi (UDP 8765) |
| [company_qr_tool/app.py:617](../../company_qr_tool/app.py#L617) | <code>def fetch_device_public_ip(device_uid: str) -&gt; str:</code> | Genel IP sunucudan okunur: GET /api/company/devices/<UID>/runtime (X-Company-Key, yalnız HTTPS ya da yerel makine, 4 sn zaman aşımı); anahtar yoksa ya da hata olursa boş döner, hata penceresi açmaz |
| [company_qr_tool/app.py:3456](../../company_qr_tool/app.py#L3456) | <code>def _request_public_ip(self, uid: str) -&gt; None:</code> | Kartın durum bloğu her geldiğinde istenir (başarıdan sonra 120 sn, hatada 30 sn arayla); COMPANY_API_KEY yoksa hiç sorulmaz |
| [server/src/routes/company_routes.js:478](../../server/src/routes/company_routes.js#L478) | <code>companyRouter.get('/api/company/devices/:deviceUid/runtime', async (req, res) =&gt; {</code> | Salt okunur uç: yalnız { device_uid, public_ip, last_seen_at }; geçersiz kimlik 400, kayıtlı olmayan kart 404 |
| [server/src/routes/company_routes.js:219](../../server/src/routes/company_routes.js#L219) | <code>export function companyDeviceRuntimeBody(deviceUid, row) {</code> | public_ip kartın OTA manifest isteğinin kaynak adresidir (açılışta Wi-Fi oturduktan ~1,5-2,5 dk sonra, sonra 24 saatte bir); henüz istek yoksa ya da adres Cloudflare kenarıysa null |

**Olası nedenler**
- Beacon: kart ve bilgisayar aynı alt ağda değil, Windows güvenlik duvarı UDP 8765'i engelliyor ya da port başka bir uygulamada
- Genel IP: COMPANY_API_KEY bu bilgisayarda tanımlı değil (anahtar ancak araç yeniden açılınca okunur) ya da sunucuya ulaşılamıyor
- Genel IP: kart sunucuda kayıtlı değil (404) ya da henüz OTA manifest isteği yapmadı (yeni kurulan kartta Wi-Fi bağlantısından sonra yaklaşık 2 dk)
- Genel IP: API Cloudflare turuncu bulut arkasında ve TRUST_PROXY Cloudflare'i kapsamıyor: kaydedilen adres kartın değil, sunucu bu yüzden boş döner

**Adım adım kontrol**
- Beacon'ı doğrudan görmek için uygulamanın yerel kontrol akışını (docs/YEREL_KONTROL_V2.md) kullanın
- COMPANY_API_KEY'in company_qr_tool/.env dosyasında ya da kullanıcı ortam değişkeninde tanımlı olduğunu doğrulayıp aracı yeniden açın
- Kartı ilk kez bağladıysanız birkaç dakika bekleyin; alan 30 sn arayla yeniden sorulur (saha denemesi: SAHA_KONTROL_LISTESI.md 86.18)

**İlgili testler:** [cihaz_kontrol/host_test/t_udp.cpp](../../cihaz_kontrol/host_test/t_udp.cpp)

**Bkz.:** [arac-cihaz-dene-durum-bos](#arac-cihaz-dene-durum-bos)

<a id="arac-ekran-firmware"></a>
### arac-ekran-firmware · Şirket aracı "Ekran yazılımı" sayfası: ekran bulunamıyor / derleme-sürüm-yükleme hata veriyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [company_qr_tool/app.py:3514](../../company_qr_tool/app.py#L3514) | <code>class ScreenFirmwarePage:</code> | Ekran (ESP32-C3 + TFT) için ayrı sayfa (yan menüde "Ekran yazılımı", Ctrl+5): ekranı bul, sürüm oluştur, yükle |
| [company_qr_tool/app.py:3728](../../company_qr_tool/app.py#L3728) | <code>s.write(b"\r\nDISP_PING\r\n")</code> | "Ekranı bul": her porta DISP_PING gönderir |
| [company_qr_tool/app.py:3731](../../company_qr_tool/app.py#L3731) | <code>if "AHBU_DEVICE:DISPLAY" in buf or "Display Controller" in buf:</code> | Ekranın yanıtı; gelmezse esptool chip_id ile ESP32-C3 aranır ("ESP32-C3 ekran modülü bulundu (yazılım yanıt vermedi)" der) |
| [ekran_yazilimi/src/main.cpp:86](../../ekran_yazilimi/src/main.cpp#L86) | <code>if (pcSerialBuffer == "?" &#124;&#124; pcSerialBuffer == "IDENT" &#124;&#124; pcSerialBuffer == "DISP_PING") {</code> | Ekran yazılımının kimlik yanıtı (PC USB seri) |
| [company_qr_tool/app.py:56](../../company_qr_tool/app.py#L56) | <code>DISPLAY_CONFIG_H_PATH = DISPLAY_PROJECT_DIR / "include" / "config.h"</code> | Sürüm ekran projesindeki config.h içindeki DISPLAY_FIRMWARE_VERSION satırına yazılır |
| [company_qr_tool/app.py:4093](../../company_qr_tool/app.py#L4093) | <code>"esp32c3",</code> | Ekran yüklemesi her zaman --chip esp32c3, 0x0 bootloader ofseti ve 460800 baud ile yapılır |

**Olası nedenler**
- Ekran farklı bir seri portta / başka program portu tutuyor
- Ekran boş flash: DISP_PING yanıtsız → yalnızca esptool ile C3 olarak tespit edilir
- PlatformIO yok / derleme hatası (ekran_yazilimi, env esp32c3_display)
- BOOT+RST adımı gerekir (hata penceresi aynı yönergeyi verir)

**Adım adım kontrol**
- Ekranı doğrudan USB ile bağlayın; seri monitörü kapatın
- Elle derleme: pio run -d ekran_yazilimi -e esp32c3_display

**Komutlar**
```bash
pio run -d ekran_yazilimi -e esp32c3_display
```

**Bkz.:** [arac-surum-derleme](#arac-surum-derleme), [arac-usb-yukleme-hata](#arac-usb-yukleme-hata)

<a id="arac-baslatma-bat"></a>
### arac-baslatma-bat · launch_company_qr_tool.bat ile araç açılmıyor ("Python sanal ortam olusturulamadi" / "Kutuphane kurulumu basarisiz") ya da pencere hiç açılmadan kapanıyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [company_qr_tool/launch_company_qr_tool.bat:7](../../company_qr_tool/launch_company_qr_tool.bat#L7) | <code>py -3 -m venv .venv</code> | İlk çalıştırmada sanal ortam oluşturur (Windows py başlatıcısı + Python 3.10+ gerekir) |
| [company_qr_tool/launch_company_qr_tool.bat:17](../../company_qr_tool/launch_company_qr_tool.bat#L17) | <code>".venv\Scripts\python.exe" -m pip install -r requirements.txt</code> | Bağımlılıkları kurar; ağ/proxy yoksa "Kutuphane kurulumu basarisiz" |
| [company_qr_tool/launch_company_qr_tool.bat:24](../../company_qr_tool/launch_company_qr_tool.bat#L24) | <code>start "" ".venv\Scripts\pythonw.exe" app.py</code> | pythonw konsolsuz çalışır: açılış hataları (ör. içe aktarma/Tk) görünmez |
| [company_qr_tool/requirements.txt:1](../../company_qr_tool/requirements.txt#L1) | <code>qrcode[pil]&gt;=7.4.2</code> | QR üretimi (Pillow ile) |
| [company_qr_tool/app.py:4180](../../company_qr_tool/app.py#L4180) | <code>def main() -&gt; None:</code> | Giriş noktası: App().run() |

**Olası nedenler**
- Python 3 / py başlatıcısı kurulu değil
- pip kurulumu ağ/proxy nedeniyle başarısız
- Tk/Pillow/pyserial içe aktarma hatası: pythonw hatayı göstermez, pencere açılmaz
- Logo dosyası yok (App başlarken ensure_logo hata verir)

**Adım adım kontrol**
- Hatayı görmek için konsoldan çalıştırın (pencere kapanmaz): company_qr_tool\.venv\Scripts\python.exe company_qr_tool\app.py
- .venv bozulduysa klasörü silip .bat dosyasını yeniden çalıştırın

**Komutlar**
```bash
company_qr_tool\.venv\Scripts\python.exe company_qr_tool\app.py
```

**Bkz.:** [arac-qr-etiket](#arac-qr-etiket)

<a id="test-nerede-sunucu"></a>
### test-nerede-sunucu · Sunucuda bu özellik/uç hangi testle korunuyor? Testi nerede bulurum, nasıl çalıştırırım?

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [server/package.json:9](../../server/package.json#L9) | <code>"test": "node --test",</code> | npm test = Node yerleşik test koşucusu (server/test altındaki *.test.js) |
| [docs/codebase/TESTING.md:40](../../docs/codebase/TESTING.md#L40) | <code>- Backend: `server/test/*.test.js`; file name prefix groups the area (`core_*` auth/middl…</code> | Dosya adı öneki alanı belirtir: core_ (kimlik/ara katman/posta/başlangıç), devices_, doors_, members_, sites_, ops_, fix_ (sözleşme denetimi regresyonları) |
| [server/test/doors_policy.test.js:26](../../server/test/doors_policy.test.js#L26) | <code>describe('assertDoorOpenAllowed (C2) - kanal x bayrak matrisi', () =&gt; {</code> | Kapı açma politikası (kanal x site politikası matrisi) |
| [server/test/core_auth_routes.test.js:59](../../server/test/core_auth_routes.test.js#L59) | <code>describe('auth_routes (C1/C8/C12, enumeration, sizinti)', () =&gt; {</code> | Giriş/kayıt/doğrulama uçları (HTTP, DB'siz) |
| [server/test/devices_firmware_manifest.test.js:105](../../server/test/devices_firmware_manifest.test.js#L105) | <code>describe('devices: GET /firmware/:target/manifest.json', () =&gt; {</code> | OTA manifest ucu (hedef izolasyonu) |
| [server/test/members_pending_registration.test.js:46](../../server/test/members_pending_registration.test.js#L46) | <code>describe('bekleyen kayıt: kayıt / doğrulama / yeniden gönderme', () =&gt; {</code> | Bekleyen kayıt akışı (users satırı doğrulamadan önce oluşmaz) |

**Olası nedenler**
- Her test dosyası kendi sahte nesnelerini kurar (ortak global kurulum yok); çoğu DB/MQTT'ye bağlanmaz

**Adım adım kontrol**
- Özellik -> test eşlemesi: giriş/kayıt/oturum = core_auth_routes, core_auth_middleware, core_jwt, fix_sx2_auth, password_reset
- Şirket uçları = core_company_auth, core_company_routes_http, fix_sx1_company_ota; CORS/hız sınırı/hata/günlük maskeleme = core_cors, core_rate_limiter, core_error_handler, core_log_mask
- Kapı açma/geofence = doors_policy, doors_geofence, geofence; QR = doors_qr_access, doors_screen_qr; MQTT köprüsü = doors_mqtt, devices_mqtt_acl, fix_sx1_bridge_logs
- Cihaz/OTA = devices_firmware_manifest, devices_device_service, device_assignment, ops_ota_check_retry; cihaz günlükleri = devices_door_log_service, devices_sync_logs_route
- Üyelik/e-posta = members_*, mailer, core_mailer_*; site/misafir/politika = sites_*; migration = ops_migrate_runner, ops_migration_chain; başlangıç/dayanıklılık = core_startup, core_robustness, import_smoke
- Tek dosya çalıştırma: cd server && node --test test/doors_policy.test.js

**Komutlar**
```bash
cd server && npm test
cd server && node --test test/doors_policy.test.js
```

**İlgili testler:** [server/test/doors_policy.test.js](../../server/test/doors_policy.test.js), [server/test/core_auth_routes.test.js](../../server/test/core_auth_routes.test.js), [server/test/devices_firmware_manifest.test.js](../../server/test/devices_firmware_manifest.test.js), [server/test/members_pending_registration.test.js](../../server/test/members_pending_registration.test.js), [server/test/core_company_auth.test.js](../../server/test/core_company_auth.test.js), [server/test/doors_mqtt.test.js](../../server/test/doors_mqtt.test.js)

**Bkz.:** [test-sunucu-npm-test-lint](#test-sunucu-npm-test-lint), [test-nerede-flutter](#test-nerede-flutter), [test-nerede-firmware](#test-nerede-firmware)

<a id="test-nerede-flutter"></a>
### test-nerede-flutter · Flutter tarafında bu ekran/özellik hangi testle korunuyor? Testler nerede, hangisi neyi ölçüyor?

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [docs/codebase/TESTING.md:37](../../docs/codebase/TESTING.md#L37) | <code>### 2) Test Layout</code> | Test düzeni: test/ (birim+widget), test/design (tasarım sistemi), test/screens (her ekran/diyalog taşma), test/support (yeniden kurma sayacı) |
| [test/design/harness.dart:33](../../test/design/harness.dart#L33) | <code>Future&lt;void&gt; pumpAt(</code> | Ortak düzenek: boyut/ölçek/tema/hareket azaltma ile kurar, taşma dahil çerçeve hatası arar |
| [test/screens/dialog_layout_harness.dart:26](../../test/screens/dialog_layout_harness.dart#L26) | <code>void layoutMatrix(</code> | Diyalog/ekran taşma testlerinin matris kaydedicisi |
| [test/support/rebuild_probe.dart:8](../../test/support/rebuild_probe.dart#L8) | <code>class RebuildProbe {</code> | Yeniden kurma sayacı (performans gerileme testleri) |
| [test/widget_test.dart:11](../../test/widget_test.dart#L11) | <code>await tester.pumpWidget(const MyApp(networkCheckEnabled: false));</code> | Uygulama kökü testi: ağ yoklaması kapalı |

**Olası nedenler**
- Test dosyası adı _test.dart ile bitmezse (harness.dart, *_support.dart, list_fixtures.dart) tek başına test olarak çalışmaz; yalnız yardımcıdır

**Adım adım kontrol**
- Tasarım sistemi (kontrast, taşma matrisi, hareket azaltma): test/design/*  -  her ekran ve diyalog taşması: test/screens/*_layout_test.dart
- Oturum/API: auth_service_session_test, auth_api_policy_test, auth_api_offload_test, fix_fx1_session_test
- Yerel kapı kontrolü: local_door_service_v2_test, local_door_service_security_test, local_door_service_battery_test, local_door_access_test
- Yoklama/performans: adaptive_poller_test, home_polling_test, qr_modal_polling_test, clock_rebuild_scope_test, home_scroll_paint_test, cold_start_test, pdf_background_test
- Geofence/site politikası: geofence_and_site_policy_test; tema: theme_service_test + test/design/theme_toggle_button_test; derin bağlantı/hızlı eylem: deep_link_service_test, quick_actions_service_test
- Sesli komut: voice_door_service_test, voice_live_banner_test; BLE/Wi-Fi: ble_wifi_provision_service_test, wifi_qr_parser_test, wifi_provision_page_layout_test; modeller: model_parsing_test, fix_fx2_models_test

**Komutlar**
```bash
flutter test
flutter test test/design test/screens
flutter test test/local_door_service_v2_test.dart
```

**İlgili testler:** [test/design/contrast_test.dart](../../test/design/contrast_test.dart), [test/screens/login_layout_test.dart](../../test/screens/login_layout_test.dart), [test/home_polling_test.dart](../../test/home_polling_test.dart), [test/auth_service_session_test.dart](../../test/auth_service_session_test.dart), [test/local_door_service_v2_test.dart](../../test/local_door_service_v2_test.dart), [test/widget_test.dart](../../test/widget_test.dart)

**Bkz.:** [test-flutter-tasma-matrisi](#test-flutter-tasma-matrisi), [test-flutter-yeniden-kurma-yoklama](#test-flutter-yeniden-kurma-yoklama), [test-flutter-widget-ortam](#test-flutter-widget-ortam), [test-nerede-sunucu](#test-nerede-sunucu)

<a id="test-nerede-firmware"></a>
### test-nerede-firmware · Firmware mantığı (yerel kontrol, PIN, GM60, MQTT/OTA) hangi testle korunuyor? Donanımsız test nasıl çalışır?

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [cihaz_kontrol/host_test/README.md:9](../../cihaz_kontrol/host_test/README.md#L9) | <code>&#124; `t_core.cpp` &#124; `yerel_kontrol_cekirdek.h`: HMAC bilinen-cevap vektörleri, Node `crypto`…</code> | Test tablosu: hangi başlık hangi test dosyasıyla, kaç doğrulama |
| [cihaz_kontrol/host_test/run_all.py:29](../../cihaz_kontrol/host_test/run_all.py#L29) | <code>TESTS = [</code> | Koşucunun test listesi (t_core, t_udp, t_pin, t_gm60, t_mqtt WROOM + C3) |
| [SAHA_KONTROL_LISTESI.md:1028](../../SAHA_KONTROL_LISTESI.md#L1028) | <code>## 51. 🔌 Firmware — ESP32-C3, ESP32-WROOM ve Ekran Yazılımı (F1, F2A1, F2A2, F2B)</code> | Donanımdaki gerçek davranış host testleriyle doğrulanmış SAYILMAZ; saha adımları burada (ve 42-52) |
| [docs/codebase/TESTING.md:12](../../docs/codebase/TESTING.md#L12) | <code>- Firmware: host tests in `cihaz_kontrol/host_test/` (719 checks: local control v2 core, …</code> | Firmware test kapsamı ve CI dışında olduğu notu |

**Olası nedenler**
- Host testleri gerçek firmware başlıklarını (cihaz_kontrol/include/*.h) sahte donanım katmanıyla (stub/) çalıştırır; RAM/Flash/ağ zamanlaması ölçülmez
- CI'da koşmaz (MSVC + PlatformIO bağımlılığı): firmware başlığını değiştirince elle çalıştırın

**Adım adım kontrol**
- Yerel kontrol çekirdeği/HMAC/zaman farkı = t_core; UDP/HTTP uçtan uca = t_udp; yönetici PIN = t_pin; QR okuyucu korumaları = t_gm60; MQTT+OTA durum makineleri = t_mqtt (WROOM ve C3 ayrı)
- Her test "SONUC: N dogrulama gecti, M basarisiz" yazar; çıkış kodu 0 = hepsi geçti
- Boyut/bellek için pio run, davranış için saha listesi

**Komutlar**
```bash
cd cihaz_kontrol/host_test && python run_all.py
cd cihaz_kontrol/host_test && python run_all.py --fuzz
```

**İlgili testler:** [cihaz_kontrol/host_test/t_core.cpp](../../cihaz_kontrol/host_test/t_core.cpp), [cihaz_kontrol/host_test/t_udp.cpp](../../cihaz_kontrol/host_test/t_udp.cpp), [cihaz_kontrol/host_test/t_pin.cpp](../../cihaz_kontrol/host_test/t_pin.cpp), [cihaz_kontrol/host_test/t_gm60.cpp](../../cihaz_kontrol/host_test/t_gm60.cpp), [cihaz_kontrol/host_test/t_mqtt.cpp](../../cihaz_kontrol/host_test/t_mqtt.cpp)

**Bkz.:** [test-firmware-host-derleme](#test-firmware-host-derleme), [test-yerel-kontrol-v2](#test-yerel-kontrol-v2)

<a id="test-sunucu-npm-test-lint"></a>
### test-sunucu-npm-test-lint · "npm test" ya da "npm run lint" kırıldı (no-undef, import smoke, core_startup, Node sürümü)

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [server/package.json:10](../../server/package.json#L10) | <code>"lint": "eslint src",</code> | npm run lint yalnız src/ (CI bunu çalıştırır); lint:all test ve betikleri de kapsar |
| [server/eslint.config.js:43](../../server/eslint.config.js#L43) | <code>'no-undef': 'error',</code> | Tanımsız değişken/eksik import HATA (canlıda ReferenceError olacak sınıf) |
| [server/test/import_smoke.test.js:1](../../server/test/import_smoke.test.js#L1) | <code>// Import smoke testi.</code> | src/ altındaki her modülü ayrı süreçte yükler: sözdizimi, olmayan export, döngüsel import yakalanır |
| [server/test/core_startup.test.js:12](../../server/test/core_startup.test.js#L12) | <code>const emptyCwd = fs.mkdtempSync(path.join(os.tmpdir(), 'kapi-startup-test-'));</code> | Gerçek server.js ayrı süreçte başlatılır; JWT_SECRET yer tutucu/boşsa çıkış 1 beklenir |
| [server/package.json:17](../../server/package.json#L17) | <code>"node": "&gt;=20.19.0"</code> | Gereken Node sürümü |
| [.nvmrc:1](../../.nvmrc#L1) | <code>24</code> | CI ve yerel için Node sürüm dosyası |
| [.github/workflows/ci.yml:42](../../.github/workflows/ci.yml#L42) | <code>run: npm run lint</code> | CI sunucu işi: önce lint, sonra npm test |

**Olası nedenler**
- Yeni kodda eksik import / yazım hatası → lint no-undef hatası ve import_smoke düşer
- Var olmayan bir export içe aktarıldı ("does not provide an export named ...")
- Node sürümü < 20.19 ya da npm ci yapılmadı
- core_startup: JWT_SECRET doğrulaması değişti (yer tutucu reddi, 20 karakter uyarısı) — test mesajları [ENV] HATA / UYARI ile eşleşir
- Lint yalnız UYARI verenler (kullanılmayan değişken) CI'yı kırmaz

**Adım adım kontrol**
- Hata dosyasını tek başına çalıştırın: cd server && node --test test/import_smoke.test.js
- Lint ayrıntısı: cd server && npx eslint src/<dosya>

**Günlükte aranacak ifadeler**
- `[ENV] HATA: JWT_SECRET`
- `[ENV] UYARI: JWT_SECRET 20 karakter`

**Komutlar**
```bash
cd server && npm ci
cd server && npm run lint
cd server && npm test
```

**İlgili testler:** [server/test/import_smoke.test.js](../../server/test/import_smoke.test.js), [server/test/core_startup.test.js](../../server/test/core_startup.test.js)

**Bkz.:** [test-ci-kirmizi](#test-ci-kirmizi), [test-sunucu-kaynak-korumalari](#test-sunucu-kaynak-korumalari)

<a id="test-sunucu-kaynak-korumalari"></a>
### test-sunucu-kaynak-korumalari · Sunucu testi "... bulunamadi" ile ya da kaynak metni iddiasıyla kırıldı; kodu yeniden adlandırınca/taşıyınca regresyon koruması düştü

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [server/test/sites_source_guards.test.js:14](../../server/test/sites_source_guards.test.js#L14) | <code>function sliceFunction(source, startMarker) {</code> | Kaynakta işaretçi metni arar; işaretçi (fonksiyon başlığı) değişirse "bulunamadi" ile düşer |
| [server/test/sites_source_guards.test.js:12](../../server/test/sites_source_guards.test.js#L12) | <code>const read = (relative) =&gt; readFileSync(path.join(srcRoot, relative), 'utf8').replace(/\r…</code> | Testler src/ dosyalarını METİN olarak okur (import etmez) |
| [server/test/members_maintenance.test.js:95](../../server/test/members_maintenance.test.js#L95) | <code>describe('members: db.js yalnızca additive şema değişikliği içerir', () =&gt; {</code> | db.js yalnızca ekleyici (additive) şema değişikliği içermeli; yıkıcı ifade eklenince düşer |
| [server/test/members_maintenance.test.js:23](../../server/test/members_maintenance.test.js#L23) | <code>describe('members: maintenance_service yıkıcı işlem yapmaz', () =&gt; {</code> | Bakım servisi kullanıcı silmez / tablo düşürmez iddiası |

**Olası nedenler**
- Korunan güvenlik düzeltmesi (atomik SQL, transaction, ID doğrulama, hata sızıntısı) geri alındı ya da yeniden yazıldı
- İşaretçi olarak kullanılan fonksiyon/metin adı değiştirildi (testin işaretçisi de güncellenmeli)
- db.js'e DROP/DELETE gibi yıkıcı ifade eklendi (AGENTS.md kural 2: geriye uyumluluk)

**Adım adım kontrol**
- Hata iletisindeki işaretçiyi kaynakta arayın; gerçekten silinen bir koruma mı, yalnız yeniden adlandırma mı karar verin
- Yeniden adlandırma ise testin işaretçisini güncelleyin; koruma silindiyse düzeltmeyi geri getirin (iddiayı gevşetmeyin)

**İlgili testler:** [server/test/sites_source_guards.test.js](../../server/test/sites_source_guards.test.js), [server/test/members_maintenance.test.js](../../server/test/members_maintenance.test.js)

**Bkz.:** [test-sunucu-npm-test-lint](#test-sunucu-npm-test-lint), [surec-kurallar-hangisi](#surec-kurallar-hangisi)

<a id="test-ops-migration-zinciri"></a>
### test-ops-migration-zinciri · ops_migration_chain / ops_migrate_runner testi kırıldı: yeni migration "tablo bu migration'dan önce hiçbir migration'da oluşturulmuyor" ya da numara çakışması

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [server/test/ops_migration_chain.test.js:25](../../server/test/ops_migration_chain.test.js#L25) | <code>it('her ALTER TABLE, aynı veya önceki bir migration\'da oluşturulmuş tabloyu hedefler', (…</code> | Her ALTER TABLE aynı veya önceki migration'da oluşturulmuş bir tabloyu hedeflemeli (IF EXISTS olmadıkça) |
| [server/test/ops_migration_chain.test.js:20](../../server/test/ops_migration_chain.test.js#L20) | <code>assert.ok(files.length &gt;= 27, `beklenenden az migration: ${files.length}`);</code> | En az 27 migration; numaralar tekrarlanamaz (NNN_ad.sql) |
| [server/test/ops_migrate_runner.test.js:1](../../server/test/ops_migrate_runner.test.js#L1) | <code>// scripts/migrate.js birim testleri.</code> | Migration koşucusu sahte DB istemcisiyle test edilir (gerçek DB'ye bağlanmaz) |
| [SAHA_KONTROL_LISTESI.md:921](../../SAHA_KONTROL_LISTESI.md#L921) | <code>- [ ] **47.6.** VPS: `node scripts/migrate.js --status` (salt okunur) → schema_migrations…</code> | Canlıda migrate.js --status / --baseline / --apply adımları (saha doğrulaması) |

**Olası nedenler**
- Yeni migration, yalnızca src/db.js'te oluşan bir tabloyu ALTER ediyor (boş veritabanında docker initdb ve migrate.js bu satırda düşer)
- İki migration aynı numarayı taşıyor
- Dosya adı /^\d{3}_.+\.sql$/ desenine uymuyor (zincire girmez)

**Adım adım kontrol**
- Tabloyu önce bir migration'da CREATE edin ya da ALTER TABLE IF EXISTS kullanın
- Boş yerel veritabanında zinciri deneyin (kendi PG'nizde): node scripts/migrate.js --apply --yes

**Komutlar**
```bash
cd server && node --test test/ops_migration_chain.test.js test/ops_migrate_runner.test.js
cd server && node scripts/migrate.js --status
```

**İlgili testler:** [server/test/ops_migration_chain.test.js](../../server/test/ops_migration_chain.test.js), [server/test/ops_migrate_runner.test.js](../../server/test/ops_migrate_runner.test.js)

**Bkz.:** [test-gercek-pg-qa](#test-gercek-pg-qa)

<a id="test-gercek-pg-qa"></a>
### test-gercek-pg-qa · qa_pending_registration_pg.mjs "REDDEDILDI" ile çıkıyor (çıkış kodu 3) ya da gerçek PostgreSQL adımlarından biri düşüyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [server/scripts/qa_pending_registration_pg.mjs:18](../../server/scripts/qa_pending_registration_pg.mjs#L18) | <code>console.error('REDDEDILDI: DB_HOST yalnizca 127.0.0.1 veya localhost olabilir (tek kullan…</code> | DB_HOST yalnız 127.0.0.1/localhost olabilir (üretim DB'sine karşı çalışmaz) |
| [server/scripts/qa_pending_registration_pg.mjs:21](../../server/scripts/qa_pending_registration_pg.mjs#L21) | <code>if (process.env.QA_CONFIRM_DISPOSABLE_DB !== 'yes') {</code> | Tek kullanımlık veritabanı onayı zorunlu: QA_CONFIRM_DISPOSABLE_DB=yes |
| [server/scripts/qa_pending_registration_pg.mjs:87](../../server/scripts/qa_pending_registration_pg.mjs#L87) | <code>ok('ensureDbSchema iki kez calisti (idempotent); pending_registrations mevcut');</code> | Adım 0: şema idempotent; tablolar yoksa (migration uygulanmamış boş DB) burada düşer |
| [server/scripts/qa_pending_registration_pg.mjs:65](../../server/scripts/qa_pending_registration_pg.mjs#L65) | <code>if (Date.now() - start &gt; timeoutMs) throw new Error('waitFor zaman asimi');</code> | Eşzamanlı/sıra dışı gönderim adımlarında bekleme zaman aşımı |
| [docs/EPOSTA_DOGRULAMA.md:68](../../docs/EPOSTA_DOGRULAMA.md#L68) | <code>## Doğrulama kanıtı</code> | 15 adımın kapsamı ve çalıştırma komutu |

**Olası nedenler**
- DB_HOST 127.0.0.1/localhost değil ya da QA_CONFIRM_DISPOSABLE_DB=yes verilmemiş (güvenlik reddi)
- Veritabanı boş: önce node scripts/migrate.js --apply --yes uygulanmalı (ensureDbSchema yalnız migration uygulanmış DB'de çalışır)
- Bakım adımı pending_registrations içindeki 2 günden eski TÜM satırları siler: üretim DB'sinde ASLA çalıştırmayın
- Kod/sema değişti: kayıt, doğrulama veya bakım akışı (membership_service.js, maintenance_service.js) betiğin beklentisiyle uyuşmuyor

**Adım adım kontrol**
- Kendi yerel PostgreSQL'inizi (ör. 55432 portu) boş bir veritabanıyla hazırlayın, migrate edin, sonra betiği çalıştırın
- Çıktı "OK NN ..." satırlarıyla ilerler; düşen adımın numarasına bakın

**Komutlar**
```bash
cd server && node scripts/migrate.js --apply --yes
cd server && DB_HOST=127.0.0.1 DB_PORT=55432 DB_NAME=kapi_qa DB_USER=postgres DB_PASSWORD=x QA_CONFIRM_DISPOSABLE_DB=yes node scripts/qa_pending_registration_pg.mjs
```

**İlgili testler:** [server/test/members_pending_registration.test.js](../../server/test/members_pending_registration.test.js)

**Bkz.:** [test-ops-migration-zinciri](#test-ops-migration-zinciri), [surec-eposta-dogrulama-dok](#surec-eposta-dogrulama-dok)

<a id="test-flutter-tasma-matrisi"></a>
### test-flutter-tasma-matrisi · Widget/ekran testi "A RenderFlex overflowed by X pixels" ile kırıldı (taşma matrisi: 320/360/412/820 x 1.0/1.5/2.0 x açık/koyu)

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [test/design/harness.dart:11](../../test/design/harness.dart#L11) | <code>const List&lt;double&gt; kHarnessWidths = &lt;double&gt;[320, 360, 412, 820];</code> | Matris genişlikleri: 320, 360, 412, 820 |
| [test/design/harness.dart:14](../../test/design/harness.dart#L14) | <code>const List&lt;double&gt; kHarnessScales = &lt;double&gt;[1.0, 1.5, 2.0];</code> | Yazı ölçekleri: 1.0, 1.5, 2.0 (uygulama kökü 2.0 ile sınırlar; düzenekte bu sınır YOK) |
| [test/design/harness.dart:62](../../test/design/harness.dart#L62) | <code>expect(t.takeException(), isNull); // RenderFlex overflow dahil</code> | Taşma dahil her çerçeve hatası testi düşürür |
| [test/screens/dialog_layout_harness.dart:18](../../test/screens/dialog_layout_harness.dart#L18) | <code>const List&lt;(double, double, double)&gt; kLayoutCells = &lt;(double, double, double)&gt;[</code> | Ekran/diyalog hücreleri: 320x640 x2.0, 360x640 x1.5 (zorunlu) + 640x360 yatay + 820x1180 tablet |
| [test/design/pump_at_test.dart:13](../../test/design/pump_at_test.dart#L13) | <code>group('pumpAt', () {</code> | Düzeneğin kendi doğrulaması ve negatif kontroller (taşan widget TestFailure fırlatmalı) |
| [AGENTS.md:29](../../AGENTS.md#L29) | <code>6. **Mobil ve Arayüz Tasarımlarında Taşma (Overflow) Kesinlikle Yasaktır:**</code> | Kural 6: hiçbir ekranda yatay/dikey taşma olamaz; Flexible/Expanded/maxLines/ellipsis/Wrap kullanılır |

**Olası nedenler**
- Yeni Row/Column içinde sabit genişlik ya da sarmayan dinamik metin/rozet
- Yazı ölçeği 2.0 veya 320 px genişlikte uzun etiket/eylem satırı
- Test düzeneği gövdeyi SingleChildScrollView içine koyar ve çocuğu kendi genişliğine sarar: tam genişlik isteyen widget'ı SizedBox(width: double.infinity) ile sarmayan test dar ekran taşmasını gizleyebilir

**Adım adım kontrol**
- Test adı hangi hücrenin düştüğünü söyler (genişlik x ölçek, açık/koyu); o hücreyi elle pumpAt ile deneyin
- Çözüm: Flexible/Expanded, maxLines + TextOverflow.ellipsis ya da Wrap; testin iddiasını GEVŞETMEYİN (kural 2)
- Aynı widget için Ahem etkisini ayırt edin (bkz. test-flutter-ahem)

**Komutlar**
```bash
flutter test test/design test/screens
flutter test test/screens/login_layout_test.dart
```

**İlgili testler:** [test/design/pump_at_test.dart](../../test/design/pump_at_test.dart), [test/screens/login_layout_test.dart](../../test/screens/login_layout_test.dart), [test/design/app_card_test.dart](../../test/design/app_card_test.dart)

**Bkz.:** [test-flutter-ahem](#test-flutter-ahem), [test-nerede-flutter](#test-nerede-flutter), [surec-kurallar-hangisi](#surec-kurallar-hangisi)

<a id="test-flutter-ahem"></a>
### test-flutter-ahem · Taşma testi yalnız testte kırılıyor (uzun etiket/eylem 320 px x 1.5-2.0 ölçekte taşıyor) ama gerçek cihazda sorun yok gibi; "Ahem" yazı tipi

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [test/design/app_snack_test.dart:486](../../test/design/app_snack_test.dart#L486) | <code>// Not: flutter test'in Ahem yazı tipinde her harf 1 em genişliğindedir (gerçek yazı tipl…</code> | Ahem: her harf 1 em genişlikte (gerçek yazı tiplerinin ~2 katı); matris bilerek kötü durumu sınar |
| [test/screens/login_layout_test.dart:10](../../test/screens/login_layout_test.dart#L10) | <code>// Not: widget testleri Ahem yazı tipiyle çalışır (her harf 1 em genişliğinde): satır sar…</code> | Geçen taşma testi gerçek yazı tipinde de geçer; satır sarma testte gerçek cihazdan serttir |
| [test/screens/home_shell_layout_test.dart:848](../../test/screens/home_shell_layout_test.dart#L848) | <code>// 400 dp x1,3: test yazı tipinde (Ahem: harf = punto) uzun etiket sığmaz; gerçek yazı ti…</code> | 400 dp x1.3'te uzun etiket testte sığmaz, gerçek yazı tipinde sığar (iddia buna göre yazılmış) |
| [test/design/app_dialog_test.dart:453](../../test/design/app_dialog_test.dart#L453) | <code>// Test yazı tipi (Ahem) gerçek yazı tipinden ~2 kat geniştir: 320 x 2,0'da yalnız üst sı…</code> | 320 x 2.0'da yalnız üst sınır sınanır |
| [test/voice_live_banner_test.dart:596](../../test/voice_live_banner_test.dart#L596) | <code>// Ahem'de her harf 1 em: gerçek yazı tiplerinden ~2 kat geniş; yalnız taşma/hata olmamas…</code> | Yalnız taşma/hata olmaması sınanır |

**Olası nedenler**
- Flutter test ortamı Ahem yazı tipini kullanır: satır sarma/genişlik gerçekten daha kötüdür
- Gerçek taşma da olabilir: önce widget'ı Flexible/ellipsis/Wrap ile esnek yapın

**Adım adım kontrol**
- Matriste kısa etiketli eylem, uzun etiket ayrı testte gerçekçi genişlikte denenir (app_snack_test örneği)
- Testi yalnız Ahem yüzünden geçirmek için taşmayı yok sayan bir gevşetme eklemeyin (AGENTS.md kural 2 ve 6)

**İlgili testler:** [test/design/app_snack_test.dart](../../test/design/app_snack_test.dart), [test/screens/login_layout_test.dart](../../test/screens/login_layout_test.dart), [test/screens/home_shell_layout_test.dart](../../test/screens/home_shell_layout_test.dart)

**Bkz.:** [test-flutter-tasma-matrisi](#test-flutter-tasma-matrisi)

<a id="test-flutter-kontrast-tema"></a>
### test-flutter-kontrast-tema · contrast_test / tema testleri kırıldı: metin-zemin kontrastı 4.5:1 altında, rol vurgusu uyuşmuyor, gölge/hareket bütçesi aşıldı

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [test/design/contrast_test.dart:1](../../test/design/contrast_test.dart#L1) | <code>// FAZ 5 / A0: tasarım tokenlarının HAKEM testi.</code> | Tüm metin/zemin çiftleri >= 4.5:1, QR halka renkleri >= 3.0:1; AppTone.hue == role.accentColor; gölge/hareket bütçesi |
| [test/design/contrast_test.dart:21](../../test/design/contrast_test.dart#L21) | <code>double contrast(Color foreground, Color background) {</code> | WCAG oranı hesabı (saydam ön plan arka plana bindirilir; arka plan opak olmalı) |
| [test/theme_service_test.dart:1](../../test/theme_service_test.dart#L1) | <code>// Tema tercihi: sistem (varsayılan) / aydınlık / karanlık; cihazda saklanır (SharedPrefe…</code> | Tema tercihi (sistem/aydınlık/karanlık) ve kalıcılığı |
| [test/design/theme_toggle_button_test.dart:44](../../test/design/theme_toggle_button_test.dart#L44) | <code>testWidgets('kapsam yoksa düğme hiç görünmez (mevcut ekranlar değişmez)', (t) async {</code> | Ay/güneş geçiş düğmesi testleri (dosyada group yok; her senaryo ayrı testWidgets: kapsamsız görünmez, ikon/ipucu, kalıcılık, sistem modu, 44 dp, 320 dp x 2,0 taşma) |
| [docs/codebase/CONCERNS.md:54](../../docs/codebase/CONCERNS.md#L54) | <code>&#124; `lib/ui/design/` (tokens, palette, components) &#124; A palette or token change restyles ~60…</code> | Palet/token değişikliği ~60 ekranı etkiler: değişiklik öncesi ve sonrası test/design + test/screens çalıştırılmalı |
| [SAHA_KONTROL_LISTESI.md:1146](../../SAHA_KONTROL_LISTESI.md#L1146) | <code>## 55. 🌗 Aydınlık / Karanlık Tema Geçiş Düğmesi (2026-10-02)</code> | Tema geçiş düğmesinin saha adımları |

**Olası nedenler**
- Palet/token (lib/styles, lib/ui/design/tokens.dart) değişti: bir metin-zemin çifti 4.5:1 altına düştü
- Yeni bir AppTone/rol rengi eklendi ve rol vurgusuyla (accentColor) eşlenmedi
- Karanlık temada yeni bir yüzeyde soluk metin

**Adım adım kontrol**
- Hata iletisindeki çifti (ön plan/zemin) bulun; rengi minimum değişiklikle koyulaştırın/açın
- Düzeltme sonrası tüm tasarım ve ekran testlerini çalıştırın (widget türlerini - ElevatedButton, AlertDialog, ListTile - değiştirmeyin: testler ve yürüyüş düzeneği bunlara dayanır)

**Komutlar**
```bash
flutter test test/design test/screens
flutter test test/theme_service_test.dart
```

**İlgili testler:** [test/design/contrast_test.dart](../../test/design/contrast_test.dart), [test/theme_service_test.dart](../../test/theme_service_test.dart), [test/design/theme_toggle_button_test.dart](../../test/design/theme_toggle_button_test.dart)

**Bkz.:** [test-flutter-tasma-matrisi](#test-flutter-tasma-matrisi)

<a id="test-flutter-yeniden-kurma-yoklama"></a>
### test-flutter-yeniden-kurma-yoklama · Performans gerileme testi kırıldı: yeniden kurma sayısı arttı, yoklama (3 sn / 800 ms) durmuyor ya da saat tüm sayfayı yeniden kuruyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [test/support/rebuild_probe.dart:18](../../test/support/rebuild_probe.dart#L18) | <code>debugOnRebuildDirtyWidget = (Element element, bool builtOnce) {</code> | Her Element yeniden kurulduğunda tür başına sayaç artar |
| [test/support/rebuild_probe.dart:25](../../test/support/rebuild_probe.dart#L25) | <code>static void stop() {</code> | tearDown'da çağrılmazsa debug geri çağrısı diğer testlere sızar |
| [test/home_polling_test.dart:3](../../test/home_polling_test.dart#L3) | <code>// Yoklama (3 sn): yalnız kapı paneli görünürken ve uygulama ön plandayken çalışır; ardış…</code> | Kapı durumu yoklaması: yalnız panel görünürken ve ön plandayken; hatada üstel geri çekilme (tavan 30 sn); üst üste binmez |
| [test/adaptive_poller_test.dart:1](../../test/adaptive_poller_test.dart#L1) | <code>// FAZ 5 / P-c: AdaptivePoller (yoklama zamanlayıcısı) birim testleri.</code> | Poller'ın sanal zamanlı birim testleri |
| [test/clock_rebuild_scope_test.dart:1](../../test/clock_rebuild_scope_test.dart#L1) | <code>// FAZ 5 / P-d: DigitalClockWidget'ın saniyelik güncellemesi yalnız saat metnini yeniden …</code> | Saniyelik güncelleme yalnız saat metnini yeniden kurar |
| [test/qr_modal_polling_test.dart:1](../../test/qr_modal_polling_test.dart#L1) | <code>// FAZ 5 / P-c, P-d: DynamicQrPassModal durum yoklaması (800 ms) yaşam döngüsü ve geri sa…</code> | QR modalı yoklama yaşam döngüsü ve geri sayım halkası kapsamı |
| [test/home_scroll_paint_test.dart:2](../../test/home_scroll_paint_test.dart#L2) | <code>// (RepaintBoundary) yoksa her kaydırma karesinde yüzlerce kartın tümü baştan boyanır.</code> | Uzun sayfada kaydırma: sınır yoksa her karede yüzlerce kart baştan boyanır |
| [SAHA_KONTROL_LISTESI.md:1102](../../SAHA_KONTROL_LISTESI.md#L1102) | <code>- [ ] **52.16.** Sunucu erişim günlüğünden yoklama trafiği: Kapılar sayfası (kapı kartı) …</code> | Sunucu erişim günlüğünde yoklama trafiğinin saha doğrulaması |

**Olası nedenler**
- Geniş kapsamlı setState / üst widget güncellemesi yeni eklendi (yalnız ilgili alt ağaç yeniden kurulmalı)
- Poller dispose edilmedi ya da arka plana/örtüldüğünde durdurulmadı
- Test sanal zaman kullanıyor: tester.pump(duration) olmadan Timer ilerlemez
- RebuildProbe.start() sonrası stop() unutuldu

**Adım adım kontrol**
- Hangi tür kaç kez kuruldu: RebuildProbe.snapshot() çıktısını testte yazdırın
- Yoklama: panel gizlenince/uygulama arka plana alınınca isteklerin kesildiğini home_polling_test iddialarıyla karşılaştırın

**Komutlar**
```bash
flutter test test/home_polling_test.dart test/adaptive_poller_test.dart test/clock_rebuild_scope_test.dart test/qr_modal_polling_test.dart
```

**İlgili testler:** [test/home_polling_test.dart](../../test/home_polling_test.dart), [test/adaptive_poller_test.dart](../../test/adaptive_poller_test.dart), [test/clock_rebuild_scope_test.dart](../../test/clock_rebuild_scope_test.dart), [test/qr_modal_polling_test.dart](../../test/qr_modal_polling_test.dart), [test/home_scroll_paint_test.dart](../../test/home_scroll_paint_test.dart)

**Bkz.:** [test-perf-kare](#test-perf-kare), [test-nerede-flutter](#test-nerede-flutter)

<a id="test-flutter-widget-ortam"></a>
### test-flutter-widget-ortam · Widget testi ağa çıkmaya çalışıyor, "A Timer is still pending" veriyor, SharedPreferences/güvenli depo hatası alıyor ya da pumpAndSettle hiç bitmiyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [test/widget_test.dart:8](../../test/widget_test.dart#L8) | <code>SharedPreferences.setMockInitialValues(&lt;String, Object&gt;{});</code> | Her uygulama kökü testi SharedPreferences'ı sahte değerle başlatır |
| [test/widget_test.dart:9](../../test/widget_test.dart#L9) | <code>FlutterSecureStorage.setMockInitialValues(&lt;String, String&gt;{});</code> | Güvenli depo da sahtelenir (oturum anahtarı) |
| [lib/app.dart:36](../../lib/app.dart#L36) | <code>const MyApp({super.key, this.networkCheckEnabled = true, this.themeService});</code> | MyApp(networkCheckEnabled: false) ağ sağlık yoklamasını kapatır; testlerde verilmezse gerçek ağa çıkılır |
| [test/screens/dialog_layout_harness.dart:50](../../test/screens/dialog_layout_harness.dart#L50) | <code>/// girişi (~450 ms) bitene kadar ilerletilir. `pumpAndSettle` KULLANILMAZ: yüklenirken d…</code> | Yüklenirken dönen göstergeler bitmeyen animasyondur: sabit süreli pump kullanılır |
| [test/screens/login_layout_test.dart:33](../../test/screens/login_layout_test.dart#L33) | <code>class _FakeAuth extends AuthService {</code> | Ağa çıkmayan sahte kimlik servisi örneği |
| [integration_test/support/e2e_driver.dart:15](../../integration_test/support/e2e_driver.dart#L15) | <code>//  - pumpAndSettle KULLANMAZ (uygulamada 3 sn'lik yoklamalar var): sabit aralikli pump d…</code> | Uygulamada 3 sn'lik yoklamalar olduğundan yürüyüş düzeneği de sabit aralıklı pump döngüsü kullanır |

**Olası nedenler**
- MyApp networkCheckEnabled:false verilmedi (NetworkService gerçek yoklama yapar)
- Mock başlangıç değerleri setUp'ta verilmedi
- Sonsuz animasyon/yoklama varken pumpAndSettle kullanıldı
- AuthService yerine gerçek servis kullanıldı (ağ çağrısı)

**Adım adım kontrol**
- pumpAndSettle yerine tester.pump(const Duration(milliseconds: 450)) kullanın
- Sahte AuthService alt sınıfı yazın (login_layout_test örneği)

**İlgili testler:** [test/widget_test.dart](../../test/widget_test.dart), [test/screens/login_layout_test.dart](../../test/screens/login_layout_test.dart)

**Bkz.:** [test-nerede-flutter](#test-nerede-flutter), [test-flutter-tasma-matrisi](#test-flutter-tasma-matrisi)

<a id="test-e2e-integration"></a>
### test-e2e-integration · integration_test (E2E menü yürüyüşü) çalışmıyor: "E2E_USERS bos", "E2E yalnizca yerel arka uca baglanir" ya da sonuçlara güvenip güvenemeyeceğim belirsiz

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [integration_test/support/e2e_env.dart:67](../../integration_test/support/e2e_env.dart#L67) | <code>static void assertLocalApi() {</code> | Üretime bağlanmayı engeller: yalnız 127.0.0.1, localhost, 10.0.2.2, ::1 |
| [integration_test/support/e2e_env.dart:82](../../integration_test/support/e2e_env.dart#L82) | <code>'E2E_USERS bos: --dart-define-from-file=&lt;E2E&gt;/dart_defines.json verin '</code> | Kullanıcılar --dart-define-from-file ile gelir; dosya yoksa bu hata |
| [integration_test/tool/make_defines.mjs:30](../../integration_test/tool/make_defines.mjs#L30) | <code>console.error('Hata: --e2e &lt;E2E harness dizini&gt; (veya E2E_DIR) gerekli.');</code> | dart_defines.json üreticisi; seed.json gerekir (repoya yazılmaz, sır içerir) |
| [integration_test/support/e2e_driver.dart:5](../../integration_test/support/e2e_driver.dart#L5) | <code>// Calistirma (proje kokunden; ayni anda YALNIZ BIR `flutter test -d windows`):</code> | Çalıştırma komutu ve kuralı: aynı anda tek `flutter test -d windows` |
| [test/e2e_harness_collector_test.dart:1](../../test/e2e_harness_collector_test.dart#L1) | <code>// E2E altyapisinin (integration_test/support) hata toplayicisini dogrular: "0 tasma" son…</code> | "0 taşma" sonucunun yanlış negatif olmadığını gerçek taşma yakalayarak kanıtlar |
| [BEKLEYEN_ISLER.md:122](../../BEKLEYEN_ISLER.md#L122) | <code>**Faz 4 – Emülatörlerde uçtan uca test, menü gezme ve düzeltme döngüsü** (**İPTAL EDİLDİ …</code> | Faz 4 İPTAL edildi: E2E yürüyüşü kullanıcı tarafından yapılır; kısmi sonuçlar ve bilinen ortam sorunu burada |
| [docs/codebase/TESTING.md:8](../../docs/codebase/TESTING.md#L8) | <code>- Flutter integration tests: `integration_test` (dev dependency) under `integration_test/…</code> | Bu testler flutter test/CI kapsamında DEĞİL |

**Olası nedenler**
- dart_defines.json üretilmedi veya --dart-define-from-file verilmedi
- API_BASE_URL yerel değil: güvenlik emniyeti çalışmayı reddeder
- Aynı anda ikinci bir flutter test -d windows ya da pencere simge durumunda/küçük (Faz 4 notu: site yöneticisi/süper kullanıcı turları pencere küçüldüğü için tamamlanamadı)
- E2E, CI ve rutin doğrulamada koşmaz; sonuç yoksa "çalıştırılmadı" demektir

**Adım adım kontrol**
- Önce altyapı öz-testi: harness_selftest_test.dart (uygulamaya/arka uca bağlanmaz)
- Filtreler: E2E_ONLY (kullanıcı), E2E_SCREENS (ekran), E2E_COMBOS (görünüm/yazı ölçeği)

**Komutlar**
```bash
node integration_test/tool/make_defines.mjs --e2e "<E2E dizini>"
flutter test integration_test/walk_super_user_test.dart -d windows --dart-define=API_BASE_URL=http://127.0.0.1:18080 --dart-define-from-file=<E2E dizini>/dart_defines.json
```

**İlgili testler:** [test/e2e_harness_collector_test.dart](../../test/e2e_harness_collector_test.dart), [integration_test/harness_selftest_test.dart](../../integration_test/harness_selftest_test.dart)

**Bkz.:** [test-perf-kare](#test-perf-kare), [surec-bekleyen-isler](#surec-bekleyen-isler)

<a id="test-perf-kare"></a>
### test-perf-kare · Kare süresi / takılma (jank) ölçümü nasıl alınır; "perf_frames verisi gelmedi" ya da hedefin (build/raster p90 <= 8 ms, jank <= %2) tutup tutmadığı

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [integration_test/perf_frames_test.dart:14](../../integration_test/perf_frames_test.dart#L14) | <code>// ÇALIŞTIRMA (koordinatör; yerel yığın ayakta, E2E kullanıcıları tohumlanmış, pencere GÖ…</code> | Önkoşullar ve komut: yerel yığın, tohumlanmış E2E kullanıcıları, pencere görünür |
| [integration_test/perf_frames_test.dart:164](../../integration_test/perf_frames_test.dart#L164) | <code>await _phase(recorder, tester, 'vitrin_bosta', () async {</code> | Aşama sırası: acilis_giris → vitrin_bosta (Panel vitrini boşta, kapı yoklaması yok) → kapilar_gecis → kapilar_bosta (Kapılar boşta: 3 sn durum yoklaması + saat) → kapi_karti → gecis_loglari → site_yonetimi_liste |
| [integration_test/perf_frames_test.dart:74](../../integration_test/perf_frames_test.dart#L74) | <code>Future&lt;void&gt; _openDoorsFromShowcase(WidgetTester tester) async {</code> | kapilar_gecis: vitrindeki "Kapılar" kartına dokunur; kart yoksa ya da kapı paneli (AdminDoorStatusCard) açılmazsa koşu durur (kapı aşamaları boşuna "hızlı" ölçülmesin) |
| [test_driver/perf_driver.dart:28](../../test_driver/perf_driver.dart#L28) | <code>final out = Platform.environment['PERF_OUT'] ?? 'build${Platform.pathSeparator}perf';</code> | Çıktı dizini: PERF_OUT ortam değişkeni (yoksa build/perf); dosya perf_frames.json |
| [test_driver/perf_driver.dart:25](../../test_driver/perf_driver.dart#L25) | <code>print('PERF~ sürücü: perf_frames verisi gelmedi (test hata verdi mi?).');</code> | Test hata verdiyse sürücüye özet gelmez |
| [test/perf_frame_stats_test.dart:1](../../test/perf_frame_stats_test.dart#L1) | <code>// FAZ 5 / P: kare süresi ölçüm düzeneğinin (integration_test/support/perf_frames.dart) ö…</code> | Ölçüm düzeneğinin yüzdelik/jank hesabının birim testi |
| [SAHA_KONTROL_LISTESI.md:1106](../../SAHA_KONTROL_LISTESI.md#L1106) | <code>- [ ] **52.20.** (Geliştirici) Windows profil kare ölçümü: `flutter drive --profile -d wi…</code> | Komut, taban/faz5 karşılaştırması ve hedefler |

**Olası nedenler**
- Yerel API/E2E kullanıcıları hazır değil ya da pencere simge durumunda
- Başka bir flutter koşusu aynı anda çalışıyor
- Üretime bağlanma denemesi: bootApp yalnız yerel API'ye izin verir
- PERF_USER kapı panelini açamayan bir hesap (vitrinde "Kapılar" kartı yok ya da kapı paneli açılmıyor): koşu bilerek durur; kapı yetkili bir yönetici seçin (varsayılan manager_1)

**Adım adım kontrol**
- Aynı komutu taban ve çalışma kopyasında (PERF_LABEL=taban / faz5) çalıştırıp perf_frames.json dosyalarını kıyaslayın
- İzlenecek aşamalar: vitrin_bosta, kapilar_bosta, kapi_karti, site_yonetimi_liste (site_yonetimi_liste PERF_SKIP_SITES=true ile atlanır)
- Panel modül vitrinine geçmeden önceki bir sürümün taban JSON'unda vitrin_bosta / kapilar_bosta yerine ana_panel_bosta vardır: onun karşılığı kapilar_bosta'dır; vitrin_bosta yeni aşamadır ve ana_panel_bosta ile kıyaslanmaz (vitrinde kapı yoklaması olmadığından sahte iyileşme gösterir)

**Günlükte aranacak ifadeler**
- `PERF~ sürücü: perf_frames verisi gelmedi (test hata verdi mi?).`
- `PERF: Panel vitrininde "Kapılar" kartı yok; kapı paneli açılamadı`
- `PERF: kapı paneli (AdminDoorStatusCard) açılmadı`

**Komutlar**
```bash
flutter drive --profile -d windows --driver=test_driver/perf_driver.dart --target=integration_test/perf_frames_test.dart --dart-define=API_BASE_URL=<yerel API> --dart-define=PERF_USER=<kullanıcı> --dart-define=PERF_SITE=<site> --dart-define=PERF_OUT=<çıktı klasörü> --dart-define=PERF_LABEL=faz5
```

**İlgili testler:** [test/perf_frame_stats_test.dart](../../test/perf_frame_stats_test.dart)

**Bkz.:** [test-e2e-integration](#test-e2e-integration), [test-flutter-yeniden-kurma-yoklama](#test-flutter-yeniden-kurma-yoklama)

<a id="test-firmware-host-derleme"></a>
### test-firmware-host-derleme · Firmware host testi "CALISMADI / DERLENMEDI" ya da "ArduinoJson bulunamadi" diyor; run_all.py derleyemiyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [cihaz_kontrol/host_test/run_all.py:22](../../cihaz_kontrol/host_test/run_all.py#L22) | <code>VCVARS = os.environ.get(</code> | vcvars64.bat yolu (varsayılan Visual Studio 18 Community); farklıysa VCVARS ortam değişkeni verilir |
| [cihaz_kontrol/host_test/run_all.py:21](../../cihaz_kontrol/host_test/run_all.py#L21) | <code>ARDUINOJSON = os.path.normpath(os.path.join(HERE, '..', '.pio', 'libdeps', 'lolin_c3_mini…</code> | ArduinoJson cihaz_kontrol/.pio/libdeps/lolin_c3_mini altında aranır (önce bir kez pio run gerekir) |
| [cihaz_kontrol/host_test/run_all.py:72](../../cihaz_kontrol/host_test/run_all.py#L72) | <code>print('UYARI: ArduinoJson bulunamadi (%s). Once `pio run -e lolin_c3_mini` ile cihaz_kont…</code> | Uyarı metni ve çözüm: pio run -e lolin_c3_mini |
| [cihaz_kontrol/host_test/run_all.py:74](../../cihaz_kontrol/host_test/run_all.py#L74) | <code>subprocess.run(['node', 'gen_vectors.mjs'], cwd=HERE, check=True)</code> | t_core için rastgele HMAC vektörleri Node ile üretilir (Node gerekir) |
| [cihaz_kontrol/host_test/run_all.py:98](../../cihaz_kontrol/host_test/run_all.py#L98) | <code>print('%-78s CALISMADI / DERLENMEDI (cikis=%d)' % (ad, r.returncode))</code> | Derleme/çalıştırma hatası çıktısı; test mantık hatasında "FAIL" satırları ve basarisiz sayısı basılır |
| [cihaz_kontrol/host_test/README.md:19](../../cihaz_kontrol/host_test/README.md#L19) | <code>## Gereksinimler</code> | Windows + Visual Studio, Python 3, Node.js, PlatformIO ile bir kez derlenmiş cihaz_kontrol |

**Olası nedenler**
- Visual Studio kurulu değil ya da yolu farklı (VCVARS)
- cihaz_kontrol bir kez PlatformIO ile derlenmedi: ArduinoJson başlıkları yok
- Node.js yok: vectors.txt üretilemez
- Firmware başlığı değişti ve gerçek bir doğrulama düştü (FAIL satırlarına bakın)

**Adım adım kontrol**
- Derleme hatası çıktısının son 1500 karakteri ekrana basılır; cl.exe hatasını okuyun
- HMAC vektörlerini yeniden üretmek için --new-vectors

**Günlükte aranacak ifadeler**
- `CALISMADI / DERLENMEDI`
- `UYARI: ArduinoJson bulunamadi`

**Komutlar**
```bash
pio run -d cihaz_kontrol -e lolin_c3_mini
cd cihaz_kontrol/host_test && python run_all.py
cd cihaz_kontrol/host_test && python run_all.py --new-vectors
```

**İlgili testler:** [cihaz_kontrol/host_test/t_core.cpp](../../cihaz_kontrol/host_test/t_core.cpp), [cihaz_kontrol/host_test/t_mqtt.cpp](../../cihaz_kontrol/host_test/t_mqtt.cpp)

**Bkz.:** [test-nerede-firmware](#test-nerede-firmware), [test-yerel-kontrol-v2](#test-yerel-kontrol-v2)

<a id="test-yerel-kontrol-v2"></a>
### test-yerel-kontrol-v2 · Yerel (LAN/UDP) kapı kontrol testleri ya da bilinen-cevap vektörü kırıldı; yerel açma "challenge"/"unauthorized" hatası veriyor: sözleşme ve testler nerede?

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [docs/YEREL_KONTROL_V2.md:7](../../docs/YEREL_KONTROL_V2.md#L7) | <code>## Mesajlar (UDP, port 8765, JSON, &lt; 512 B)</code> | Beacon, discover, open/pulse mesajları ve yanıt kodları |
| [docs/YEREL_KONTROL_V2.md:13](../../docs/YEREL_KONTROL_V2.md#L13) | <code>`sig = lowerhex( HMAC-SHA256( key = UTF-8(token), msg = UTF-8( action + "&#124;" + UID_BÜYÜK_H…</code> | İmza formülü: HMAC-SHA256(token, action\|UID_BÜYÜK\|ch); pakette token yok |
| [docs/YEREL_KONTROL_V2.md:37](../../docs/YEREL_KONTROL_V2.md#L37) | <code>## Bilinen-cevap test vektörü (cihaz, uygulama ve simülatör testleri aynı değerleri doğru…</code> | Cihaz, uygulama ve simülatör testlerinin aynı değerleri doğruladığı vektör |
| [test/local_door_service_v2_test.dart:17](../../test/local_door_service_v2_test.dart#L17) | <code>const String kSigOpen = '92f22b8a741bcc00b1aec15ff573b6ee4d48edea1bba959807489eb3c6fed5f4…</code> | Uygulama tarafı vektör testi |
| [cihaz_kontrol/host_test/t_core.cpp:120](../../cihaz_kontrol/host_test/t_core.cpp#L120) | <code>CHECK(strcmp(imza, "92f22b8a741bcc00b1aec15ff573b6ee4d48edea1bba959807489eb3c6fed5f4") ==…</code> | Firmware çekirdeği vektör testi (+ Node crypto ile 600 rastgele vektör çapraz doğrulama) |

**Olası nedenler**
- v1 ile v2 karışımı: eski firmware/uygulama v1 ile konuşamaz; firmware ve APK birlikte güncellenmeli
- Vektör ya da imza biçimi değişti: belge, t_core.cpp, uygulama testi ve simülatör AYNI ANDA güncellenmeli
- UID büyük harfe çevrilmeden imzalandı ya da ch 12 sn'den eski
- Hedef adres özel ağ (RFC1918/link-local) değil: uygulama paket göndermez

**Adım adım kontrol**
- Önce iki vektör testini çalıştırın: Flutter local_door_service_v2_test, firmware t_core
- Belgedeki "Karar sırası" (token yok, yinelenen, ch bilinmiyor, imza, röle meşgul) ile cihaz yanıtını karşılaştırın

**Komutlar**
```bash
flutter test test/local_door_service_v2_test.dart test/local_door_service_security_test.dart
cd cihaz_kontrol/host_test && python run_all.py
```

**İlgili testler:** [test/local_door_service_v2_test.dart](../../test/local_door_service_v2_test.dart), [test/local_door_service_security_test.dart](../../test/local_door_service_security_test.dart), [cihaz_kontrol/host_test/t_core.cpp](../../cihaz_kontrol/host_test/t_core.cpp), [cihaz_kontrol/host_test/t_udp.cpp](../../cihaz_kontrol/host_test/t_udp.cpp)

**Bkz.:** [test-nerede-firmware](#test-nerede-firmware), [arac-cihaz-dene-beacon-wan](#arac-cihaz-dene-beacon-wan)

<a id="test-klavuz-araci"></a>
### test-klavuz-araci · Arıza klavuzu üretimi/denetimi hata veriyor: "BELİRSİZ", "bulunamadı (kod değişmiş olabilir)", "yinelenen id" veya "related id yok"

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [tools/klavuz/build.mjs:92](../../tools/klavuz/build.mjs#L92) | <code>export function resolveRef(ref, io) {</code> | Bir girişin dosya+parça bağlantısını satıra çözer; bulunamaz/belirsizse hata |
| [tools/klavuz/build.mjs:127](../../tools/klavuz/build.mjs#L127) | <code>return { ok: false, error: `${rel}: ${label} bulunamadı (kod değişmiş olabilir; girişi gü…</code> | Kod değişince eski parça yok olur: girişteki find değeri güncellenmeli |
| [tools/klavuz/build.mjs:219](../../tools/klavuz/build.mjs#L219) | <code>export function crossCheck(areas, { only = null } = {}) {</code> | Alanlar arası: id'ler benzersiz, related geçerli olmalı |
| [tools/klavuz/build.test.mjs:488](../../tools/klavuz/build.test.mjs#L488) | <code>describe('gerçek depo: klavuz girişleri kodla uyumlu mu?', () =&gt; {</code> | Gerçek girişlerin --check'i testin parçasıdır: kod kayarsa test de kırılır |
| [tools/klavuz/README.md:90](../../tools/klavuz/README.md#L90) | <code>## Kalite kuralları (giriş yazarken)</code> | Uydurma yok, belirti odaklı, günlük metni kodda geçmeli, komutlar güvenli |
| [tools/klavuz/render.mjs:321](../../tools/klavuz/render.mjs#L321) | <code>export function renderAll(areas, scans, messages, status = { verified: [], note: '' }) {</code> | Tüm belgeleri (ana sayfa, indeks, bölüm dosyaları, ekler, hata mesajları) üretir; "doğrulanmadı" etiketi burada basılır |
| [tools/klavuz/lint.mjs:92](../../tools/klavuz/lint.mjs#L92) | <code>export function lintEntries(areas, io, corpus = buildCorpus(io)) {</code> | Mekanik denetim: kodda geçmeyen günlük ifadesi ve etiketsiz/sır basan komut için UYARI üretir |
| [tools/klavuz/README.md:83](../../tools/klavuz/README.md#L83) | <code>## Doğrulama durumu (`durum.json`)</code> | Bölümün "doğrulandı/doğrulanmadı" etiketi tools/klavuz/durum.json içindeki dogrulananAlanlar listesinden gelir |

**Olası nedenler**
- Kod değişti: find parçası artık yok (güncelleyin) ya da birden fazla satırda geçiyor (daha ayırt edici parça, nth veya any)
- İki alan dosyasında aynı id
- related içinde var olmayan id ya da tests içinde var olmayan dosya
- UYARI (hata değil): logs içindeki ifade kodda geçmiyor (dinamik değerliyse başına ~ koyun) ya da komut sır basıyor / değiştirici komut "# DEĞİŞTİRİR" etiketsiz
- README başlığı yeniden adlandırıldı: ona bağlı girişin find değeri bulunamaz (üretim bunu hata olarak yakalar)

**Adım adım kontrol**
- Metnin kodda nerede geçtiğini bulun: node tools/klavuz/build.mjs --where "metin"
- Tek alanı denetleyin: --check --only 50-arac-test-ve-surec; belgeler güncel mi: --check --fresh
- Giriş içeriğini koddaki hâliyle görün: node tools/klavuz/build.mjs --explain <giriş-id>

**Günlükte aranacak ifadeler**
- `kod değişmiş olabilir; girişi güncelleyin`

**Komutlar**
```bash
node tools/klavuz/build.mjs --check
node tools/klavuz/build.mjs --check --only 50-arac-test-ve-surec
node tools/klavuz/build.mjs --where "metin"
node --test "tools/klavuz/*.test.mjs"
```

**İlgili testler:** [tools/klavuz/build.test.mjs](../../tools/klavuz/build.test.mjs)

**Bkz.:** [test-ci-kirmizi](#test-ci-kirmizi)

<a id="test-ci-kirmizi"></a>
### test-ci-kirmizi · GitHub Actions CI kırmızı: "Server (lint + test)", "Flutter (analyze + test)" ya da "Secret scan (gitleaks)" işi başarısız

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [.github/workflows/ci.yml:41](../../.github/workflows/ci.yml#L41) | <code>- name: Lint (no-undef = hata)</code> | Sunucu işi: npm ci, lint (no-undef = hata), npm test (import smoke dahil) |
| [.github/workflows/ci.yml:69](../../.github/workflows/ci.yml#L69) | <code>run: flutter analyze --no-fatal-infos</code> | Hata ve uyarılar CI'yı kırar; yalnız "info" düzeyi kırmaz |
| [.github/workflows/ci.yml:84](../../.github/workflows/ci.yml#L84) | <code>- name: Run gitleaks</code> | Tam geçmiş taranır: eski ifşa olmuş sırlar kırmızıya neden olur |
| [.github/workflows/ci.yml:91](../../.github/workflows/ci.yml#L91) | <code>GITLEAKS_LICENSE: ${{ secrets.GITLEAKS_LICENSE }}</code> | Kuruluma (organization) ait depolarda lisans secret'ı gerekir |
| [.github/workflows/ci.yml:4](../../.github/workflows/ci.yml#L4) | <code># NOT: Bu dosyada DEPLOY YOKTUR (canli dagitim kullanici karari; AGENTS.md kural 8 elle y…</code> | CI canlıya dağıtım yapmaz (AGENTS.md kural 8 elle yürütülür) |
| [SAHA_KONTROL_LISTESI.md:923](../../SAHA_KONTROL_LISTESI.md#L923) | <code>- [ ] **47.8.** GitHub: PR'da Actions "Server", "Flutter", "Secret scan" çalışır (gitleak…</code> | gitleaks geçmişteki parola yüzünden kırmızı çıkabilir; parolayı döndürme notu |
| [docs/codebase/CONCERNS.md:9](../../docs/codebase/CONCERNS.md#L9) | <code>&#124; high &#124; Production credentials were exposed in the past (repository history, firmware bi…</code> | Geçmişte ifşa olan üretim sırları riski (döndürme ve geçmiş temizliği kullanıcı kararı) |

**Olası nedenler**
- Sunucu: lint hatası (no-undef) ya da kırılan sunucu testi (bkz. test-sunucu-npm-test-lint)
- Flutter: analyze uyarısı/hatası ya da kırılan widget testi (CI kararlı kanal kullanır; yerel Flutter sürümü farklı olabilir)
- gitleaks: depo geçmişinde bulunan sır (koddaki güncel dosya temiz olsa bile)
- Firmware host testleri ve integration_test CI'da KOŞMAZ; kırmızıya neden olmaz ama doğrulama da sağlamaz

**Adım adım kontrol**
- Hangi iş kırmızı: ilgili adımın günlüğünü açın
- Yerelde aynı komutlar: cd server && npm ci && npm run lint && npm test; flutter analyze --no-fatal-infos; flutter test

**Komutlar**
```bash
cd server && npm ci && npm run lint && npm test
flutter analyze --no-fatal-infos
flutter test
```

**Bkz.:** [test-sunucu-npm-test-lint](#test-sunucu-npm-test-lint), [test-nerede-flutter](#test-nerede-flutter)

<a id="surec-kurallar-hangisi"></a>
### surec-kurallar-hangisi · Bir değişiklik yapacağım: AGENTS.md'nin hangi kuralı bu durumda geçerli? (backend, arayüz, firmware, yeni özellik, git)

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [AGENTS.md:11](../../AGENTS.md#L11) | <code>2. **Geçmiş Özellikleri ve Geriye Dönük Uyumluluğu Asla Bozma:**</code> | Her değişiklik: mevcut uç nokta/parametre/iş mantığı bozulmaz; eski istemci ve sahadaki cihaz kesintiye uğramaz |
| [AGENTS.md:15](../../AGENTS.md#L15) | <code>3. **ESP32-C3 Süper Mini Sahada Aktif - Çalışmasını Asla Bozma:**</code> | Firmware/MQTT/BLE/pin değişikliği: C3 sahada çalışıyor; flash ve RAM sınırı gözetilir |
| [AGENTS.md:25](../../AGENTS.md#L25) | <code>5. **Saha Kontrol Listesini Güncel Tut:**</code> | Yeni özellik tamamlanınca SAHA_KONTROL_LISTESI.md'ye "- [ ]" test adımı eklenir (bkz. surec-saha-listesi-ekleme) |
| [AGENTS.md:29](../../AGENTS.md#L29) | <code>6. **Mobil ve Arayüz Tasarımlarında Taşma (Overflow) Kesinlikle Yasaktır:**</code> | Arayüz değişikliği: Flexible/Expanded/ellipsis/Wrap; taşma matrisi testi bunu doğrular (bkz. test-flutter-tasma-matrisi) |
| [AGENTS.md:39](../../AGENTS.md#L39) | <code>8. **Sunucuyu (Backend VPS) Her Zaman Güncelle ve Canlı Doğrula (Zorunlu):**</code> | Backend değişikliği: canlıya al, PM2 günlüğü + /health doğrula (bkz. surec-canliya-alma-kural8) |
| [AGENTS.md:48](../../AGENTS.md#L48) | <code>10. **Git Yüklemeleri ve `.git/index` Bütünlüğü (Index Temizliği &amp; Hata Engelleme):**</code> | Commit/push öncesi .git/index bütünlüğü (bkz. surec-git-index-bozuldu) |

**Olası nedenler**
- Backend (services/routes/db.js/migration/MQTT köprüsü) değişti -> kural 8: canlıya al ve uçtan uca doğrula; kural 2: ekleyici şema, eski istemci uyumu
- Flutter arayüzü değişti -> kural 6 (taşma yok) ve kural 7 (işlem sonrası otomatik yenileme, RefreshIndicator)
- Firmware değişti -> kural 3 (C3 bozulmaz) ve kural 4 (C3 ve WROOM hedefleri ayrı derleme/manifest/sürüm)
- Yeni özellik bitti -> kural 5 (saha listesi); kural 1 (modüler yapı: services/routes/utils, modeller/servisler/widget, .h/.cpp)
- Kullanıcıya "değiştireyim mi?" diye sorma: kural 9 doğrudan uygulamayı ister

**Adım adım kontrol**
- Backend + arayüz birlikte değiştiyse kural 8, 6 ve 7 birlikte uygulanır; testleri (npm test, flutter test) çalıştırmadan bitirmeyin
- Kural 4 ve 7 için: OTA manifestleri /firmware/esp32-c3/ ve /firmware/esp32-wroom/ ayrıdır; yenileme için ilgili sayfada refresh()/loadData() çağrısına bakın
- Kural 11 ve 12 durum bildirimidir (tamamlanmış aşamalar); davranış kuralı değildir
- company_qr_tool/.agents/rules/proje-kurallari.md aracın kendi çalışma kurallarıdır (aynı ruh: çalışan davranışı koru, kapsam dışı refactor yapma)

**Bkz.:** [surec-saha-listesi-ekleme](#surec-saha-listesi-ekleme), [surec-canliya-alma-kural8](#surec-canliya-alma-kural8), [surec-git-index-bozuldu](#surec-git-index-bozuldu), [test-flutter-tasma-matrisi](#test-flutter-tasma-matrisi)

<a id="surec-saha-listesi-ekleme"></a>
### surec-saha-listesi-ekleme · Yeni özelliği bitirdim: saha kontrol listesine test adımı nasıl eklenir? (kural 5) / listedeki madde numarası klavuzda kayboldu

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [AGENTS.md:25](../../AGENTS.md#L25) | <code>5. **Saha Kontrol Listesini Güncel Tut:**</code> | Kural: yeni özellik kodlanıp tamamlanınca "- [ ]" adımı; nasıl test edileceği ve beklenen sonuç net yazılır |
| [SAHA_KONTROL_LISTESI.md:1146](../../SAHA_KONTROL_LISTESI.md#L1146) | <code>## 55. 🌗 Aydınlık / Karanlık Tema Geçiş Düğmesi (2026-10-02)</code> | Örnek bölüm: başlık "## NN. emoji Konu (tarih)"; en yeni bölüm dosyanın SONUNDA |
| [SAHA_KONTROL_LISTESI.md:1148](../../SAHA_KONTROL_LISTESI.md#L1148) | <code>- [ ] **55.1. Giriş Ekranında Tema Geçişi:**</code> | Madde biçimi: "- [ ] **NN.M. Başlık:**" + alt satırlarda "**Nasıl Test Edilir:**" ve "**Beklenen Sonuç:**" |
| [SAHA_KONTROL_LISTESI.md:6](../../SAHA_KONTROL_LISTESI.md#L6) | <code>&gt; ℹ️ **Not:** Talep ettiğiniz her yeni özellik tamamlandığında bu listeye otomatik olarak…</code> | Listenin başındaki söz: her yeni özellik buraya yeni adım olarak eklenir |
| [SAHA_KONTROL_LISTESI.md:921](../../SAHA_KONTROL_LISTESI.md#L921) | <code>- [ ] **47.6.** VPS: `node scripts/migrate.js --status` (salt okunur) → schema_migrations…</code> | Klavuz girişleri bu tür madde numaralarına (ör. 47.6, 52.16) find ile bağlıdır: mevcut numaraları yeniden numaralamayın |

**Olası nedenler**
- Yeni özellik için madde eklenmedi (kural 5 unutuldu)
- Mevcut bölümler yeniden numaralandı/silindi: klavuzdaki "**NN.M.**" çıpaları bulunamaz (--check HATA verir)
- Madde "Nasıl/Beklenen" içermiyor: saha ekibi sonucu doğrulayamaz

**Adım adım kontrol**
- Yeni bölümü dosyanın sonuna ekleyin (sonraki numara); eski bölüm numaralarına dokunmayın
- Her maddede somut ekran yolu/komut ve gözlenecek sonucu yazın; donanım davranışı için "host testiyle doğrulanmış sayılmaz" notunu (bölüm 51) unutmayın
- Ekledikten sonra: node tools/klavuz/build.mjs --check (numara çıpaları bozulduysa hata verir)

**Komutlar**
```bash
node tools/klavuz/build.mjs --where "**55.1."
node tools/klavuz/build.mjs --check
```

**Bkz.:** [surec-kurallar-hangisi](#surec-kurallar-hangisi), [test-klavuz-yeni-giris](#test-klavuz-yeni-giris)

<a id="surec-git-index-bozuldu"></a>
### surec-git-index-bozuldu · git/VS Code "fatal: .git/index: index file smaller than expected" ya da "Unable to create .git/index.lock" veriyor; commit/push öncesi indeks kontrolü nasıl yapılır?

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [AGENTS.md:48](../../AGENTS.md#L48) | <code>10. **Git Yüklemeleri ve `.git/index` Bütünlüğü (Index Temizliği &amp; Hata Engelleme):**</code> | Kural 10: commit/push öncesi indeks doğrulanır; kilit/bozulma varsa temizlenir |
| [AGENTS.md:50](../../AGENTS.md#L50) | <code>- `fatal: .git/index: index file smaller than expected` hatasının oluşması kesinlikle eng…</code> | Bozuk indeks bulunursa otomatik onarım uygulanır (çalışma ağacı dosyalarına dokunmadan) |
| [.vscode/settings.json:17](../../.vscode/settings.json#L17) | <code>"git.autorefresh": true,</code> | VS Code git durumunu kendiliğinden tazeler (son commit d79075e bu ayarı açtı); eski ayar kapalı kalırsa durum bayat görünür |
| [.vscode/settings.json:19](../../.vscode/settings.json#L19) | <code>"git.openRepositoryInParentFolders": "always"</code> | Çalışma alanı depo kökünün altındaysa üst klasördeki depoyu açar |
| [.gitattributes:4](../../.gitattributes#L4) | <code>* text=auto</code> | Satır sonu normalizasyonu: Windows'ta LF/CRLF uyarıları bu dosyadan gelir (hata değildir) |

**Olası nedenler**
- Önceki git işlemi (VS Code arka plan yenilemesi dahil) yarıda kesildi: indeks dosyası eksik yazılmış
- Eski bir git işlemi .git/index.lock bıraktı (çalışan git süreci yoksa güvenle kaldırılır)
- Aynı anda iki git istemcisi (terminal + VS Code + ajanlar) indeksi yazıyor

**Adım adım kontrol**
- Çalışan git süreci olmadığından emin olun, sonra .git/index.lock dosyasının varlığına bakın
- Onarım (kural 10): bozuk .git/index dosyası silinir ve git reset ile yeniden kurulur; çalışma ağacı dosyaları ve commit geçmişi etkilenmez, yalnız hazırlık alanı (staged) sıfırlanır
- Ardından git status temiz çalışmalı; commit/push öncesi bu kontrolü tekrarlayın

**Komutlar**
```bash
git status --short
Test-Path .git\index.lock
```

**Bkz.:** [surec-kurallar-hangisi](#surec-kurallar-hangisi)

<a id="surec-eposta-dogrulama-dok"></a>
### surec-eposta-dogrulama-dok · E-posta doğrulama (bekleyen kayıt) sorununda docs/EPOSTA_DOGRULAMA.md'nin hangi bölümüne bakmalıyım? (kod gelmiyor, süre, 503/429, pre-hijacking, geri alma)

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [docs/EPOSTA_DOGRULAMA.md:11](../../docs/EPOSTA_DOGRULAMA.md#L11) | <code>## Akış (referans: OWASP Authentication Cheat Sheet / ASVS V2 yaklaşımı)</code> | Adım adım: register-individual -> verify-code -> resend-code -> login(403) -> bakım; 503/429 anlamları |
| [docs/EPOSTA_DOGRULAMA.md:33](../../docs/EPOSTA_DOGRULAMA.md#L33) | <code>## Parametreler (`membership_rules.js`)</code> | Süre (30 dk), deneme sayıları, bekleme (30 sn), saatlik tavan, SMTP zaman aşımları |
| [docs/EPOSTA_DOGRULAMA.md:47](../../docs/EPOSTA_DOGRULAMA.md#L47) | <code>## Bilinen kalıntı riskler ve sınırlamalar</code> | Pre-hijacking (belirteçli çözüm onay bekliyor), kaba kuvvet tavanı, sent_at eksikliği, bellek içi hız sınırı |
| [docs/EPOSTA_DOGRULAMA.md:75](../../docs/EPOSTA_DOGRULAMA.md#L75) | <code>## İşletim: "kod gelmiyor / geç geliyor" teşhisi</code> | Günlükte "Mail Gönderim", SMTP verify, DNS (SPF/DKIM/DMARC), alıcı/gönderen kuyruğu |
| [docs/EPOSTA_DOGRULAMA.md:88](../../docs/EPOSTA_DOGRULAMA.md#L88) | <code>## Geri alma</code> | Şema ekleyicidir; kod geri alınırsa pending_registrations kullanılmadan kalır |
| [server/src/services/membership_rules.js:29](../../server/src/services/membership_rules.js#L29) | <code>export const VERIFICATION_CODE_TTL_MINUTES = 30;</code> | Kod süresinin kodda geçtiği tek yer; belgedeki 30 dk bununla uyumlu olmalı |

**Olası nedenler**
- Belge ile kod ayrıştı (parametre değişti, belge güncellenmedi): önce membership_rules.js sabitlerine bakın, belgeyi kodla düzeltin
- Teşhis adımları SMTP kabulüne kadar sunucuyu, sonrasını gönderen/alıcı kuyruğunu ilgilendirir; gecikme çoğunlukla kabulden sonradır
- Pre-hijacking riski bilinen ve onay bekleyen bir iştir (sözleşme değişikliği: uygulama + sunucu birlikte yayınlanmalı)

**Adım adım kontrol**
- Belirti "kod gelmiyor" ise: sunucu günlüğünde "[Mail Gönderim Hatası]" kaydı ve code/responseCode alanları (bkz. sunucu-kayit-kod-gelmiyor)
- Belirti 503 ise sunucu-kayit-503-eposta-gonderilemedi; 429 ise sunucu-kayit-429-bekleme-sinir; yanlış kod ise sunucu-dogrulama-kod-hatali-400
- Gerçek PostgreSQL ile akış doğrulaması için test-gercek-pg-qa

**Günlükte aranacak ifadeler**
- `[Mail Gönderim Hatası]:`
- `SMTP ayarlari eksik`

**Komutlar**
```bash
ssh -p 22667 salihceylan@178.210.161.55 "pm2 logs kapi-api --lines 300 --nostream | grep -a 'Mail G'"
```

**İlgili testler:** [server/test/members_pending_registration.test.js](../../server/test/members_pending_registration.test.js)

**Bkz.:** [sunucu-kayit-kod-gelmiyor](10-sunucu-api.md#sunucu-kayit-kod-gelmiyor), [sunucu-kayit-503-eposta-gonderilemedi](10-sunucu-api.md#sunucu-kayit-503-eposta-gonderilemedi), [akis-kayit-eposta-dogrulama](60-akislar.md#akis-kayit-eposta-dogrulama), [test-gercek-pg-qa](#test-gercek-pg-qa)

<a id="surec-bekleyen-isler"></a>
### surec-bekleyen-isler · Gördüğüm eksik/davranış bilinen bir ertelenmiş iş mi, yoksa yeni hata mı? Hangi iş kullanıcı kararı, hangisi yapıldı? (BEKLEYEN_ISLER.md)

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [BEKLEYEN_ISLER.md:88](../../BEKLEYEN_ISLER.md#L88) | <code>## 6. 🛠️ Kod İnceleme Düzeltme Planı (2026-10-01)</code> | Kod inceleme planı: Faz 0-6 ve her fazın durumu ([x] yapıldı / [ ] bekliyor) |
| [BEKLEYEN_ISLER.md:122](../../BEKLEYEN_ISLER.md#L122) | <code>**Faz 4 – Emülatörlerde uçtan uca test, menü gezme ve düzeltme döngüsü** (**İPTAL EDİLDİ …</code> | Faz 4 (emülatörde uçtan uca gezme) İPTAL: denemeleri kullanıcı yapar; kısmi sonuçlar ve ortam sorunu yazılı |
| [BEKLEYEN_ISLER.md:133](../../BEKLEYEN_ISLER.md#L133) | <code>**Faz 6 – Canlıya dağıtım (AGENTS.md kural 8)**</code> | Canlıya dağıtım durumu: 2026-10-01 sunucu dağıtımı, COMPANY_API_KEY, APK/firmware dağıtımının kullanıcı kararı olduğu |
| [BEKLEYEN_ISLER.md:139](../../BEKLEYEN_ISLER.md#L139) | <code>**Ertelenen düşük öncelikli işler (ajan raporlarından)**</code> | Bilinen ve bilerek ertelenen eksikler (çift kayıt, bellek içi hız sınırı, BLE bonding, MQTT bloklama vb.) |
| [BEKLEYEN_ISLER.md:147](../../BEKLEYEN_ISLER.md#L147) | <code>**Bilinçli olarak bu turun dışında (kullanıcı kararı veya ayrı iş gerektirir)**</code> | Kullanıcı kararı gerektirenler: parola döndürme/git geçmişi temizliği, OTA kod imzalama, release imzası, canlı .env değerleri |
| [BEKLEYEN_ISLER.md:10](../../BEKLEYEN_ISLER.md#L10) | <code>## 1. 🔌 Donanım &amp; Firmware (ESP32)</code> | WROOM röle kartı pin doğrulaması ve sahadaki C3 3.0.3 takibi (açık maddeler) |

**Olası nedenler**
- Davranış "Ertelenen" ya da "Bilinçli olarak dışında" listesindeyse yeni hata değil, bilinen sınırlamadır; önce buraya bakın
- Dosya bayatlayabilir: son güncelleme tarihi başlıktadır; kodla çelişirse kod doğrudur, dosyayı güncelleyin
- Faz 4 iptal olduğundan emülatör/pencere turu sonucu yok: "çalıştırılmadı" demektir, "geçti" değil

**Adım adım kontrol**
- Belirtiyi ertelenen listelerinde arayın (ör. "çift kayıt", "bellek içi", "BLE")
- Madde [ ] ise açık iştir; "kullanıcı yapacak" yazan işleri ajan kendi başına tamamlanmış saymaz
- Yeni ertelenen bir iş çıkarsanız bu dosyaya ekleyin (başlıktaki tarihi güncelleyin)

**Bkz.:** [test-e2e-integration](#test-e2e-integration), [surec-kurallar-hangisi](#surec-kurallar-hangisi), [surec-canliya-alma-kural8](#surec-canliya-alma-kural8)

<a id="surec-canliya-alma-kural8"></a>
### surec-canliya-alma-kural8 · Sunucu kodu değişti ama canlıda eski davranış sürüyor; canlıya nasıl alınır, geri nasıl alınır? (AGENTS.md kural 8)

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [AGENTS.md:39](../../AGENTS.md#L39) | <code>8. **Sunucuyu (Backend VPS) Her Zaman Güncelle ve Canlı Doğrula (Zorunlu):**</code> | Backend değişikliği canlıya alınmadan iş bitmiş sayılmaz; PM2 günlüğü ve /health doğrulanır |
| [deploy/README.md:7](../../deploy/README.md#L7) | <code>## Adımlar</code> | Sıra: yerel test -> paket + sha256 -> yükleme -> prepare -> (ACL kuru çalıştırma) -> activate -> (kapi-mqtt-sync) -> doğrulama |
| [deploy/remote_deploy.sh:58](../../deploy/remote_deploy.sh#L58) | <code>activate() {</code> | Canlıya alır: kodu yerleştirir, node_modules değiştirir, pm2 restart kapi-api --update-env, /health bekler |
| [deploy/remote_deploy.sh:93](../../deploy/remote_deploy.sh#L93) | <code>echo "SAGLIK KONTROLU BASARISIZ"</code> | Sağlık gelmezse günlükten son 40 satırı basar ve otomatik rollback çalıştırır (çıkış 4) |
| [deploy/remote_deploy.sh:59](../../deploy/remote_deploy.sh#L59) | <code>[ -d "$STAGE/node_modules" ] &#124;&#124; { echo "HATA: hazirlik (prepare) yapilmamis"; exit 2; }</code> | activate, prepare yapılmadan çalışmaz (çıkış 2) |
| [PROJE_TEKNIK_NOTLAR.md:514](../../PROJE_TEKNIK_NOTLAR.md#L514) | <code>## 15. Sunucuda Guncelleme Sirasi</code> | Eski/kısa anlatım (git pull + pm2 restart); yedekli ve sağlık denetimli güncel yol deploy/README.md'dedir |

**Olası nedenler**
- Değişiklik yalnız yerelde kaldı (kural 8 uygulanmadı); canlıda eski kod çalışıyor
- prepare yapılmadı ya da paket özeti (sha256) yerel ile uzak arasında farklı
- activate sonrası /health başarısız: betik otomatik geri aldı, canlı eski sürümde kalır (günlükteki son 40 satıra bakın)
- .env değişikliği için restart yeterli değildir: pm2 restart ... --update-env gerekir (bkz. altyapi-env-degisikligi-etkisiz)
- Cihaz konuları değişti ama MQTT ACL senkronu (kapi-mqtt-sync) çalıştırılmadı

**Adım adım kontrol**
- Canlı sürüm: günlükte son başlangıç satırları ve /health (database connected, mqtt connected)
- Hazırlık dizini ve yedek: ~/backups/kapi_<TS>/ (server_code.tgz, db.sql.gz) var mı
- Şema değişiklikleri ekleyicidir: geri alma kodu döndürür, veritabanını döndürmez
- Betikler sır içermez; .env paketine girmez (sır yazdırmayın)

**Günlükte aranacak ifadeler**
- `ACTIVATE_OK`
- `SAGLIK KONTROLU BASARISIZ`
- `GERI ALMA TAMAM: /health ok`

**Komutlar**
```bash
curl -fsS https://api.gudeteknoloji.com.tr/health
ssh -p 22667 salihceylan@178.210.161.55 "pm2 logs kapi-api --lines 40 --nostream"
ssh -p 22667 salihceylan@178.210.161.55 'bash -s' < deploy/remote_verify.sh
```

**Bkz.:** [altyapi-env-degisikligi-etkisiz](20-sunucu-altyapi-ve-yayin.md#altyapi-env-degisikligi-etkisiz), [altyapi-api-acilmiyor-pm2-dongu](20-sunucu-altyapi-ve-yayin.md#altyapi-api-acilmiyor-pm2-dongu), [surec-kurallar-hangisi](#surec-kurallar-hangisi), [test-ci-kirmizi](#test-ci-kirmizi)

<a id="test-klavuz-yeni-giris"></a>
### test-klavuz-yeni-giris · Arıza klavuzuna yeni giriş nasıl eklenir, hangi komutla doğrulanır; klavuz belgeleri nasıl güncellenir (--check / --fresh / --coverage / --explain)?

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [tools/klavuz/README.md:30](../../tools/klavuz/README.md#L30) | <code>## Alan dosyası biçimi — `tools/klavuz/entries/&lt;NN-ad&gt;.mjs`</code> | Giriş biçimi: id, symptom, keywords, refs {file, find, note}, causes, checks, logs, commands, tests, related |
| [tools/klavuz/README.md:65](../../tools/klavuz/README.md#L65) | <code>### Ref alanları</code> | find: düz metin ya da {regex}; belirsizse nth/any/until; satır numarası yazılmaz |
| [tools/klavuz/build.mjs:591](../../tools/klavuz/build.mjs#L591) | <code>else if (a === '--coverage') opts.coverage = true;</code> | --coverage: hiçbir girişe bağlı olmayan kaynak dosyaları büyükten küçüğe listeler |
| [tools/klavuz/build.mjs:595](../../tools/klavuz/build.mjs#L595) | <code>else if (a === '--explain') opts.explain = argv[++i] ?? null;</code> | --explain <id>: girişin her bağlantısı için koddan satır bağlamını yazdırır |
| [tools/klavuz/build.mjs:592](../../tools/klavuz/build.mjs#L592) | <code>else if (a === '--fresh') opts.fresh = true;</code> | --check --fresh: diskteki docs/ARIZA_KLAVUZU*.md üretilenle aynı mı (belge güncel mi) |
| [tools/klavuz/build.test.mjs:488](../../tools/klavuz/build.test.mjs#L488) | <code>describe('gerçek depo: klavuz girişleri kodla uyumlu mu?', () =&gt; {</code> | Giriş eklerken/kod değiştirirken bu test de --check yapar |

**Olası nedenler**
- Yeni giriş yazıldı ama find satırdan aynen kopyalanmadı (aranan parça bulunamaz)
- Aynı parça birden fazla satırda (BELİRSİZ): daha özgül parça, nth ya da any:true
- related/tests/files içinde var olmayan id ya da yol
- Belgeler elle düzenlendi: belgeler koddan ÜRETİLİR (build), elle yazılan değişiklik --fresh ile fark çıkarır

**Adım adım kontrol**
- Alan dosyasına giriş ekleyin (tools/klavuz/entries/NN-ad.mjs) -> --check --only <alan> -> --explain <id> ile satır bağlamını gözle doğrulayın
- Kapsam: --coverage çıktısında kendi önekinizdeki bağlı olmayan dosyaları girişe ref olarak ya da files haritasına rolüyle ekleyin
- Belge üretimi (bayraksız build) yalnızca tek kişi/tek süreçte, tüm alanlar bitince çalıştırılır; paralel çalışmada yarışır
- Metin kodda var mı: --where "metin" (logs içindeki her metin için)

**Komutlar**
```bash
node tools/klavuz/build.mjs --check --only 50-arac-test-ve-surec
node tools/klavuz/build.mjs --coverage
node tools/klavuz/build.mjs --explain test-klavuz-araci
node tools/klavuz/build.mjs --check --fresh
```

**İlgili testler:** [tools/klavuz/build.test.mjs](../../tools/klavuz/build.test.mjs)

**Bkz.:** [test-klavuz-araci](#test-klavuz-araci), [surec-saha-listesi-ekleme](#surec-saha-listesi-ekleme)

<a id="arac-cihaz-dene-baglanti"></a>
### arac-cihaz-dene-baglanti · Bağımsız cihaz_dene aracı açılmıyor ("No module named serial") ya da "Baglan" sonrası "Hata" / port listesi boş / butonlar "Baglanti yok" diyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [cihaz_dene/requirements.txt:1](../../cihaz_dene/requirements.txt#L1) | <code>pyserial&gt;=3.5</code> | Tek bağımlılık pyserial; kurulu değilse "import serial" açılışta düşer (tkinter Python ile gelir) |
| [cihaz_dene/app.py:12](../../cihaz_dene/app.py#L12) | <code>import serial</code> | Açılışta içe alınır: eksik pyserial, pencere açılmadan konsolda hata verir |
| [cihaz_dene/app.py:16](../../cihaz_dene/app.py#L16) | <code>BAUD_RATE = 115200</code> | Sabit baud; firmware seri hızıyla aynı olmalı (farklıysa çıktı çöp karakter olur) |
| [cihaz_dene/app.py:214](../../cihaz_dene/app.py#L214) | <code>def refresh_ports(self) -&gt; None:</code> | Port listesi serial.tools.list_ports ile alınır; sürücü (CH340/CP210x) yoksa liste boş |
| [cihaz_dene/app.py:221](../../cihaz_dene/app.py#L221) | <code>def toggle_connection(self) -&gt; None:</code> | Port seçilmediyse "Port gerekli"; bağlanınca düğme "Kes" olur, hatada durum "Hata" yazar |
| [cihaz_dene/app.py:245](../../cihaz_dene/app.py#L245) | <code>messagebox.showinfo("Baglanti yok", "Once cihaza seri porttan baglanin.")</code> | h/l/r düğmeleri bağlı değilken komut göndermez, yalnız bu uyarıyı gösterir |
| [cihaz_dene/app.py:83](../../cihaz_dene/app.py#L83) | <code>self.on_error(str(exc))</code> | Port açma hatası (meşgul/erişim yok) "[hata] ..." olarak günlüğe düşer |

**Olası nedenler**
- pyserial kurulu değil (pip install -r cihaz_dene/requirements.txt)
- Port başka programda açık (VS Code seri monitörü, şirket aracı Cihaz Dene penceresi): bağlanma hatası günlükte [hata] olarak görünür
- USB sürücüsü yok ya da kablo yalnız şarj kablosu: port listede çıkmaz
- Bağlandıktan sonra bilgi alanları boş: eski durum başlığı beklentisi (bkz. arac-cihaz-dene-durum-bos)

**Adım adım kontrol**
- Konsoldan çalıştırıp hata metnini görün: python cihaz_dene/app.py
- Port listesini yenileyin (refresh_ports) ve başka seri araçları kapatın
- Güncel firmware ile tam özellik için şirket aracındaki Cihaz Dene penceresini kullanın

**Komutlar**
```bash
python -m pip install -r cihaz_dene/requirements.txt
python cihaz_dene/app.py
```

**Bkz.:** [arac-cihaz-dene-durum-bos](#arac-cihaz-dene-durum-bos), [arac-uid-okunamadi](#arac-uid-okunamadi)

<a id="surec-surum-gosterimi"></a>
### surec-surum-gosterimi · Uygulamada görünen sürüm ("v1.0.0 (Build 1)") APK/pubspec sürümüyle uyuşmuyor ya da sürüm numarası nereden geliyor?

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [pubspec.yaml:4](../../pubspec.yaml#L4) | <code>version: 1.0.0+1</code> | APK sürümü (versionName/versionCode) buradan gelir: flutter.versionName/versionCode |
| [lib/config/app_config.dart:7](../../lib/config/app_config.dart#L7) | <code>static const String appVersion = '1.0.0';</code> | Ekrandaki sürüm AYRI, elle yazılı sabittir: pubspec ile otomatik senkron değildir |
| [lib/config/app_config.dart:8](../../lib/config/app_config.dart#L8) | <code>static const int buildNumber = 1;</code> | Ekrandaki "Build" numarası da elle yazılıdır |
| [lib/config/app_config.dart:16](../../lib/config/app_config.dart#L16) | <code>static String get versionDisplay =&gt; 'v$appVersion (Build $buildNumber)';</code> | Giriş sayfası ve yan menü bu metni gösterir |
| [lib/config/app_config.dart:13](../../lib/config/app_config.dart#L13) | <code>defaultValue: _defaultApiBaseUrl,</code> | API adresi derlemede --dart-define=API_BASE_URL ile değişir; varsayılan canlı API |
| [android/app/build.gradle.kts:49](../../android/app/build.gradle.kts#L49) | <code>versionName = flutter.versionName</code> | Android sürümü pubspec'ten türetilir |

**Olası nedenler**
- pubspec.yaml sürümü artırıldı ama app_config.dart sabitleri güncellenmedi (ya da tersi): ekran ile APK farklı sürüm söyler
- Eski APK kurulu: yeni sürüm yüklenene kadar eski istemci kalır (BEKLEYEN_ISLER: APK dağıtımı kullanıcı kararı)
- Test/yerel derlemede API_BASE_URL değiştirilmiş: ekrandaki sürüm aynı, backend farklı

**Adım adım kontrol**
- İki yeri birlikte güncelleyin: pubspec.yaml version ve lib/config/app_config.dart (appVersion, buildNumber)
- Ekranda sürümün göründüğü yerler: lib/ui/pages/login_page.dart ve lib/ui/widgets/yan_menu.dart
- Firmware sürümü ayrıdır (cihaz_kontrol/include/ota_guncelleme.h; bkz. arac-ota-basligi-degisti)

**Bkz.:** [arac-ota-basligi-degisti](#arac-ota-basligi-degisti), [cekirdek-api-adresi-yanlis](30-uygulama-cekirdek.md#cekirdek-api-adresi-yanlis), [surec-android-gradle-jdk](#surec-android-gradle-jdk)

<a id="surec-android-gradle-jdk"></a>
### surec-android-gradle-jdk · flutter build apk / flutter run Android'de Gradle hatası veriyor (Java sürümü, "org.gradle.java.home ... geçersiz", problems-report.html, bellek)

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [android/gradle.properties:8](../../android/gradle.properties#L8) | <code>org.gradle.java.home=C:\\Program Files\\Android\\Android Studio\\jbr</code> | Gradle JDK, Android Studio jbr klasörüne SABİTLENMİŞ (Windows yolu); başka makinede/yolda bu klasör yoksa Gradle başlamaz |
| [android/gradle.properties:1](../../android/gradle.properties#L1) | <code>org.gradle.jvmargs=-Xmx8G -XX:MaxMetaspaceSize=4G -XX:ReservedCodeCacheSize=512m -XX:+Hea…</code> | Gradle JVM belleği 8 GB istenir: az RAM'li makinede bellek hatası verebilir |
| [android/app/build.gradle.kts:35](../../android/app/build.gradle.kts#L35) | <code>sourceCompatibility = JavaVersion.VERSION_17</code> | Uygulama kodu Java 17 hedefler (derleyici JDK'si 17 veya üstü olmalı) |
| [android/app/build.gradle.kts:84](../../android/app/build.gradle.kts#L84) | <code>signingConfig = signingConfigs.getByName("debug")</code> | android/key.properties yoksa release derleme DEBUG anahtarıyla imzalanır (uyarı basılır; mağazaya yüklenemez) |
| [android/app/build.gradle.kts:44](../../android/app/build.gradle.kts#L44) | <code>applicationId = "tr.com.gudeteknoloji.siteyonetim"</code> | Kalıcı uygulama kimliği (mağaza kaydından sonra değiştirilemez; iOS paket kimliğiyle aynıdır) |
| [SAHA_KONTROL_LISTESI.md:1115](../../SAHA_KONTROL_LISTESI.md#L1115) | <code>- [ ] **53.2. Android Gradle JDK 21 Uyumluluğu:**</code> | Doğrulama adımı: gradle.properties'teki Android Studio JDK ile hatasız derleme |

**Olası nedenler**
- Android Studio farklı yola kurulu ya da jbr klasörü yok: org.gradle.java.home yolunu bu makineye göre düzeltin (yalnız yerel; depodaki değer geliştirici makinesindir)
- Gradle varsayılan (eski) Java ile çalışıyor: problems-report.html hatası (bu ayar bunu önlemek için eklendi)
- RAM yetersiz: org.gradle.jvmargs değerini düşürmek gerekebilir
- android/key.properties yoksa Release APK debug imzalıdır: mağazaya yüklenemez / güncelleme imzası farklıdır (derleme çıktısında UYARI görünür)

**Adım adım kontrol**
- Hata metnindeki Java yolunu gradle.properties ile karşılaştırın; klasörün varlığını kontrol edin
- Doğrulama: flutter build apk --debug (bölüm 53.2)
- CI Gradle çalıştırmaz (yalnız analyze + test): bu hata CI'da değil yerelde görülür

**Komutlar**
```bash
flutter build apk --debug
flutter doctor -v
```

**Bkz.:** [surec-surum-gosterimi](#surec-surum-gosterimi), [test-ci-kirmizi](#test-ci-kirmizi)

<a id="test-flutter-analyze"></a>
### test-flutter-analyze · "flutter analyze" hata/uyarı veriyor ya da bir klasör (android/ios/web) analiz edilmiyor; CI Flutter işi kırmızı

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [analysis_options.yaml:19](../../analysis_options.yaml#L19) | <code>include: package:flutter_lints/flutter.yaml</code> | Varsayılan Flutter lint seti; özel kural geçersiz kılmaları yorum satırında (kapalı) |
| [analysis_options.yaml:13](../../analysis_options.yaml#L13) | <code>- android/**</code> | build, android, ios, web, windows, macos, linux klasörleri analiz dışıdır: oradaki kodu analyze görmez |
| [pubspec.yaml:46](../../pubspec.yaml#L46) | <code>flutter_lints: ^6.0.0</code> | Lint paketi sürümü (sürüm yükselince yeni kurallar yeni uyarı çıkarabilir) |
| [.github/workflows/ci.yml:69](../../.github/workflows/ci.yml#L69) | <code>run: flutter analyze --no-fatal-infos</code> | CI hata ve uyarıda kırılır, yalnız info düzeyi kırmaz |
| [docs/codebase/CONVENTIONS.md:14](../../docs/codebase/CONVENTIONS.md#L14) | <code>### 2) Formatting and Linting</code> | Linter/biçimlendirici kuralları ve çalıştırma komutları |

**Olası nedenler**
- Yeni kodda kullanılmayan içe aktarma/değişken, eski API ya da BuildContext async boşluk uyarısı
- flutter_lints sürümü/Flutter SDK sürümü değişti: aynı kod yeni uyarı verir (CI kararlı kanal; yerel sürüm farklı olabilir)
- Sorun analiz dışı klasördedir (ör. android/): analyze temiz görünür ama derleme kırılır

**Adım adım kontrol**
- Yerelde CI ile aynı komut: flutter analyze --no-fatal-infos
- Uyarıyı susturmak yerine kodu düzeltin; ignore yalnız tek satır ve gerekçeyle (AGENTS.md kural 2: mevcut davranışı bozmayın)

**Komutlar**
```bash
flutter analyze --no-fatal-infos
flutter pub get
```

**Bkz.:** [test-ci-kirmizi](#test-ci-kirmizi), [test-nerede-flutter](#test-nerede-flutter)

<a id="surec-teknik-notlar-bayat"></a>
### surec-teknik-notlar-bayat · PROJE_TEKNIK_NOTLAR.md ile kod/gerçek durum çelişiyor (komut, sayı, güncelleme sırası); hangi belgeye güvenmeliyim?

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [PROJE_TEKNIK_NOTLAR.md:483](../../PROJE_TEKNIK_NOTLAR.md#L483) | <code>## 14. Build ve Test Notlari</code> | Build/test komutları ve test sayısı (örn. "2357 test"): sayı zamanla eskir |
| [PROJE_TEKNIK_NOTLAR.md:514](../../PROJE_TEKNIK_NOTLAR.md#L514) | <code>## 15. Sunucuda Guncelleme Sirasi</code> | Kısa anlatım: git pull + npm install + pm2 restart; yedekli/denetimli güncel yol deploy/README.md |
| [PROJE_TEKNIK_NOTLAR.md:393](../../PROJE_TEKNIK_NOTLAR.md#L393) | <code>### 11.2 company_qr_tool</code> | Şirket aracının amacı ve firmware çıktı klasörleri (derleme .pio/build, sürüm firmware_releases) |
| [PROJE_TEKNIK_NOTLAR.md:320](../../PROJE_TEKNIK_NOTLAR.md#L320) | <code>## 9. E-Posta Dogrulama</code> | E-posta doğrulama özeti; ayrıntı ve güncel parametreler docs/EPOSTA_DOGRULAMA.md'dedir |
| [PROJE_TEKNIK_NOTLAR.md:549](../../PROJE_TEKNIK_NOTLAR.md#L549) | <code>## 17. Acik Tasarim Kararlari / Sonraki Adimlar</code> | Açık kararlar; güncel yapılacaklar için BEKLEYEN_ISLER.md |
| [deploy/README.md:31](../../deploy/README.md#L31) | <code>## Geri alma</code> | Canlı dağıtım için doğru kaynak: yedek + sağlık denetimi + otomatik geri alma |

**Olası nedenler**
- Belge bir önceki tur sonrası güncellenmedi: kod ve testler (npm test / flutter test) belgeden önceliklidir
- Aynı konunun iki anlatımı var (teknik notlar ve ayrıntılı belge): ayrıntılı ve tarihli olan (deploy/README.md, docs/EPOSTA_DOGRULAMA.md, BEKLEYEN_ISLER.md) esas alınır

**Adım adım kontrol**
- Çelişkiyi kodda doğrulayın (--where ile) ve belgeyi düzeltin; sayıları güncel test çıktısından alın
- Dosya adları ve komutlar ASCII-yazım (Turkce karaktersiz) başlıklar taşır: arama yaparken "Guncelleme", "Dogrulama" biçimini kullanın

**Bkz.:** [surec-canliya-alma-kural8](#surec-canliya-alma-kural8), [surec-bekleyen-isler](#surec-bekleyen-isler), [surec-eposta-dogrulama-dok](#surec-eposta-dogrulama-dok)

<a id="test-codebase-belgeleri"></a>
### test-codebase-belgeleri · Mimari, modül sınırları, risk, entegrasyon veya test düzeni sorusu: docs/codebase altındaki hangi belgeye bakmalıyım?

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [docs/codebase/ARCHITECTURE.md:26](../../docs/codebase/ARCHITECTURE.md#L26) | <code>### 3) Layer/Module Responsibilities</code> | Katman/modül sorumlulukları ve sistem akışı |
| [docs/codebase/STRUCTURE.md:33](../../docs/codebase/STRUCTURE.md#L33) | <code>### 3) Module Boundaries</code> | Dizin haritası, giriş noktaları, modül sınırları |
| [docs/codebase/CONCERNS.md:5](../../docs/codebase/CONCERNS.md#L5) | <code>### 1) Top Risks (Prioritized)</code> | Öncelikli riskler (ifşa olmuş sırlar, firmware donanımda çalıştırılmadı, .env zayıflığı, bellek içi sınırlayıcılar) |
| [docs/codebase/INTEGRATIONS.md:5](../../docs/codebase/INTEGRATIONS.md#L5) | <code>### 1) Integration Inventory</code> | PostgreSQL, Express API, SMTP, MQTT: amaç, kimlik doğrulama modeli, kanıt dosyaları |
| [docs/codebase/TESTING.md:43](../../docs/codebase/TESTING.md#L43) | <code>### 3) Test Scope Matrix</code> | Hangi alan hangi testle korunuyor (kapsam matrisi) |
| [docs/codebase/CONVENTIONS.md:5](../../docs/codebase/CONVENTIONS.md#L5) | <code>### 1) Naming Rules</code> | Adlandırma ve biçim kuralları; STACK.md sürümler ve komutlar |

**Olası nedenler**
- Belgeler İngilizcedir ve koddan türetilmiştir; kodla ayrışırsa kod doğrudur
- Aradığınız bilgi belgenin kapsamı dışında: önce klavuzun ilgili alan girişini ve --where aramasını deneyin

**Adım adım kontrol**
- Hangi belge: yapı/modül = STRUCTURE, katman ve akış = ARCHITECTURE, dış sistemler = INTEGRATIONS, riskler = CONCERNS, test = TESTING, kod stili = CONVENTIONS, sürümler/komutlar = STACK
- Test belgesinin satır bilgisi için test-nerede-sunucu, test-nerede-flutter, test-nerede-firmware girişleri

**Bkz.:** [test-nerede-sunucu](#test-nerede-sunucu), [test-nerede-flutter](#test-nerede-flutter), [test-nerede-firmware](#test-nerede-firmware)

