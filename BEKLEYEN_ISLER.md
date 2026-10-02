# 📌 AHBU & SİTE KAPI KONTROL - BEKLEYEN İŞLER VE YOL HARİTASI (ROADMAP)

**Son Güncelleme:** 2026-10-01  
**Proje:** Site Kapı Kontrol Ekosistemi (`site_kapi_kontrol`, `ahbu`, `cihaz_kontrol`, `company_qr_tool`)

Bu dosya; daha önce konuşulan, planlanan, geliştirme sürecinde bekleyen veya sahada test edilecek tüm teknik işleri tek bir merkezi noktada takip etmek için oluşturulmuştur.

---

## 1. 🔌 Donanım & Firmware (ESP32)

### 1.1 Yeni Donanım Desteği (ESP32-WROOM-32E Röle Kartı)
- [ ] **Kart Ulaştığında Pin Doğrulaması:**
  - AliExpress üzerinden tedarik edilen ESP32-WROOM-32E röle modülü fiziki olarak geldiğinde:
    - Röle tetik pini (varsayılan: `GPIO 16` veya `GPIO 23`) test edilecek ve `cihaz_kontrol/include/role_kontrol.h` içerisinde kesinleştirilecek.
    - Wi-Fi durum ve hata LED pinleri (varsayılan: `GPIO 2`) kart üzerinde doğrulanacak.
    - GM60 barkod/QR okuyucu UART2 bağlantı pinleri (`GPIO 18 RX`, `GPIO 17 TX`) yeni kart ile test edilecek.
- [x] **PlatformIO Çoklu Mimari Desteği:**
  - `cihaz_kontrol/platformio.ini` dosyasında hem `[env:lolin_c3_mini]` hem de `[env:esp32_relay_wroom]` hedefleri tanımlandı.
- [x] **Modüler ve İzole OTA Mimarisi:**
  - Sahadaki ESP32-C3 Süper Mini cihazlar: `/firmware/esp32-c3/manifest.json` (v3.0.x)
  - Yeni ESP32-WROOM cihazlar: `/firmware/esp32-wroom/manifest.json` (v1.0.x)
  - Hedefler tamamen izole edildi, cihazların birbirinin yazılımını çekme riski sıfırlandı.

### 1.2 Sahada Çalışan ESP32-C3 Cihazları
- [ ] Sahada aktif çalışan ESP32-C3 cihazların `3.0.3` firmware sürümü ile kararlılık ve Wi-Fi yeniden bağlanma testleri takip edilecek.
- [ ] BLE Wi-Fi provisioning akışının sahadaki yeni kurulumlarda sürekliliği izlenecek.

---

## 2. 📱 Mobil Uygulamalar (`site_kapi_kontrol` & `ahbu`)

### 2.1 Şirket Yönetim Uygulaması (`site_kapi_kontrol`)
- [x] **API & İstemci Güvenliği:**
  - `lib/config/app_config.dart` içerisindeki API ve bağlantı bilgilerinin derleme zamanı argümanları (`--dart-define=API_BASE_URL=...`) ile güvenli yapılandırılması tamamlandı.
- [x] **Gelişmiş Cihaz Detay & Telemetri Görünümü:**
  - Admin panelinde cihazın anlık Wi-Fi sinyal gücü (dBm / yüzde), son IP'si, donanım hedefi (`ESP32-C3` / `ESP32-WROOM` rozeti) ve anlık MQTT durumu kart detayında sunuldu.
- [x] **Site Bazlı Giriş Yetkilendirme & Geçiş Politikaları (Süper Kullanıcı Kontrolü):**
  - Süper kullanıcı tarafından her siteye özel olarak "Sadece Mobil Uygulama", "Sadece QR Kod" veya "Hibrit (Uygulama + QR)" erişim kuralı belirleme.
  - Sadece QR seçili sitelerde resident kartında otomatik QR açılışı ve uzaktan butona basma engeli (sunucu + istemci seviyesinde 403 kontrolü).
- [x] **Karanlık Mod (Dark Theme) Kontrast ve Arayüz Düzeltmeleri:**
  - `ListTile background color or ink splashes may be invisible` framework uyarısı `yan_menu.dart` içerisinde `ListTile` bileşeni `Material` ile sarılarak çözüldü.
  - Karanlık modda silik kalan metinler (`AppColors.textMutedLight` -> Slate-300 `#CBD5E1`), dialog arka planları, tersine dönmüş renk koşulları (`login_page`, `yan_menu`, `admin_door_status_card`, `hands_free_settings_dialog`, `site_security_policy_dialog`) düzeltilerek yüksek kontrast ve net okunabilirlik sağlandı.

### 2.2 Kullanıcı & Yönetici Uygulaması (`ahbu`)
- [x] **Daire Sakini (`individual` / `resident`) Self-Service Kayıt ve Aktivasyon Akışı:**
  - Bireysel kullanıcı kayıt formu, 6 haneli e-posta doğrulama kodu, site katılım QR'ı ile başvuru ve yönetici onay/ret paneli tamamlandı.
- [x] **Çevrimdışı Kapı Geçiş Log Senkronizasyon İstemcisi:**
  - Cihaz çevrimdışıyken hafızaya aldığı geçiş kayıtlarının, yetkili kullanıcının Bluetooth veya yerel UDP ile bağlanması sonrası API'ye aktarımı için `syncDeviceLogs` (`POST /device/sync-logs`) istemci metotları `auth_api.dart` ve `auth_service.dart` katmanlarına eklendi.

---

## 3. 🌐 Backend & Sunucu (Node.js API & PostgreSQL)

### 3.1 Canlı Sunucu (VPS) Deployment
- [x] **Modüler Yapının Canlıya Alınması:**
  - 6.600 satırdan 75 satıra düşürülen modüler `server.js` ve servis/router katmanları VPS üzerinde (`178.210.161.55`) PM2 ile devreye alındı.
- [x] **Canlı Sağlık & Veritabanı Kontrolü:**
  - `/health` endpoint'i üzerinden veritabanı bağlantısı (`connected`) ve MQTT köprüsü (`connected`) canlı doğrulandı.

### 3.2 Veritabanı & Şema Yönetimi
- [x] **Migration Standardizasyonu:**
  - `server/migrations/008_guest_passes_and_door_logs.sql`'den `020_qr_security_and_geofence.sql`'ye kadar tüm migrasyonlar tamamlandı ve VPS veritabanına uygulandı.
- [ ] **Detaylı Audit Log Altyapısı Raporlama Arayüzü (Opsiyonel / İsteğe Bağlı):**
  - Yetki değişiklikleri, kapı atamaları, uzaktan açma ve token rotasyonları için veritabanında saklanan audit log tablosunun yönetici panelinde filtrelenip raporlanması.

---

## 4. 🧪 Test & Kalite Güvencesi (QA)
- [x] Mobil uygulama statik analizi (`flutter analyze` - 0 sorun).
- [x] Mobil widget & servis testleri (`flutter test`; tümü başarılı).
- [x] Backend modül import ve runtime kontrolü (tüm servis ve router'lar doğrulandı).
- [x] Backend için otomatik birim testleri (`node:test`; `cd server && npm test`; tümü başarılı) ve ESLint (`npm run lint`).

---

## 5. 📦 Tamamlanan Önemli Kilometre Taşları (Referans)
- ✅ `server.js` monolitik yapısının tamamen servis ve router katmanlarına ayrılması (75 satırlık ana orkestratör).
- ✅ Çift donanım hedefli (ESP32-C3 ve ESP32-WROOM) izole OTA manifest ve firmware dağıtım sistemi.
- ✅ Siteye özel geçiş modelleri: Süper kullanıcı kontrollü Sadece QR, Sadece Uygulama veya Hibrit geçiş modu + Geofence + Dinamik QR rotasyonu.
- ✅ GM60 QR / barkod okuyucunun UART üzerinden firmware'e entegre edilmesi.
- ✅ Misafir geçiş sistemi: Dinamik süre/tek kullanımlık linkler, mobil kartlar ve `/guest/:token` web açılış sayfası.
- ✅ Yerel UDP fallback ve dinamik token rotasyon sistemi (internet kesintisinde kapı kontrolü).
- ✅ Mobil uygulamada açılır-kapanır (akordeon) kapı telemetri ve log kartları tasarımı.

---

## 6. 🛠️ Kod İnceleme Düzeltme Planı (2026-10-01)

Kapsamlı kod incelemesi (sunucu, Flutter, ESP32 firmware, ekran yazılımı, altyapı) sonrası bulunan kritik/mantık/güvenlik hatalarının düzeltilmesi. Kaynak: 4 uzman incelemesi + canlı sunucu salt-okunur kontrolü. Durum işaretleri bu bölümde güncellenir.

**Faz 0 – Hazırlık ve ölçüm**
- [x] Çalışma ağacı geri dönüş noktası alındı (değişmiş + izlenmeyen 174 dosya, `pre_fix_snapshot.tar.gz`).
- [x] Taban test sonucu: `server` 55/55 geçti.
- [x] Canlı sunucu salt-okunur kontrolü (PM2, .env maskeli, DB tabloları, nginx, certbot, kod farkı).

**Faz 1 – Paralel düzeltmeler (dosya sahipliği ayrık 9 iş paketi)**
- [x] S1 Sunucu çekirdeği: CORS allowlist, global hata/çökme koruması, JWT sertleştirme, rate limit, auth uçları, `/api/company/*` yetkilendirme.
- [x] S2 Üyelik/kullanıcı/DB: global pasifleştirme açığı, doğrulama kodu (6 hane, atomik sayaç), claim yarışı, `@ahbu.local` silme temizliği ve tek seferlik silme bloğunun kaldırılması, migration 025 kolonları.
- [x] S3 Cihaz/OTA/log: admin eksik import'ları, cihaz güncelleme SQL'i, `/device/sync-logs` kimlik doğrulama + idempotency, ACL (`logs`), betiklerde sır temizliği.
- [x] S4a Kapı açma çekirdeği: tek `assertDoorOpenAllowed` politikası, geofence tek kaynak, ekran QR tek kullanımlık, `replace-device` sahiplik, MQTT köprüsü (log ack, request_id).
- [x] S4b Yönetici/misafir: ID doğrulama, davet akışı, misafir geçişi XSS + atomik tek kullanım, güvenlik politikası PATCH.
- [x] M1 Android/servisler: widget receiver `exported=false`, yedekleme, deep link onayı, sesli komut, yerel UDP güvenliği ve tek örnek.
- [x] M2 Flutter oturum/UI: token saklama, `/me` ile rol tazeleme, merkezî 401/403, geofence istemcisi, çok-siteli yarışlar, retry politikası.
- [x] F1 Firmware + ekran: MQTT TLS doğrulaması, açılış röle testi kaldırma, yerel kontrol token'ı, yönetici PIN'i, OTA doğrulama/rollback, offline log teslimi, UART protokolü.
- [x] D1 Altyapı: `.gitattributes`/`.gitignore`, docker-compose sertleştirme, ESLint (`no-undef`), import smoke testi, migration runner, CI, `company_qr_tool` yetkilendirme.
- [x] Sözleşme denetimi ve düzeltme turu (SX1/SX2 sunucu, FX1/FX2 Flutter/firmware): donanım tipi zinciri (`hardware_type`/OTA kilitlenmesi), `replace-device` sahiplik kimliği, güvenlik politikası alias'ı, parola değiştirme kilidi, kapı yetki modeli anahtarları, site düzenleme veri kaybı (blok daire sayıları), boş veritabanında migration zinciri.

**Faz 2 – Entegrasyon ve doğrulama**
- [x] Tüm server dosyalarında `node --check` + ESLint (0 hata) + `npm test` (tümü geçti); boş veritabanında `migrate.js --apply` (27 migration) hatasız.
- [x] `flutter analyze` (temiz) + `flutter test` (tümü geçti); Android debug/release APK manifest birleştirmesi ve Windows debug derlemesi doğrulandı.
- [x] Firmware derlemeleri: ESP32-C3, ESP32-WROOM ve ekran yazılımı derleniyor (donanımda ÇALIŞTIRILMADI; yalnız derleme + cihaz simülatörü ile protokol testi).
- [x] Bağımsız sözleşme denetimi (C1–C12) ve regresyon düzeltmeleri (SX/FX turu).
- [x] Firmware için bağımsız kod incelemesi tamamlandı; bulgular (MQTT millis kilitlenmesi, OTA, offline log, Wi-Fi geri çekilme, yerel kontrol/PIN/UART/ekran) F2A2/F2A1/F2B turlarında düzeltildi. Ana makine testleri 719/719, C3/WROOM/ekran derlemeleri başarılı; donanımda ÇALIŞTIRILMADI.
- [x] **Yerel kontrol v2** (challenge'a bağlı HMAC imza; HTTP `/ahbu/open` kaldırıldı): firmware + uygulama (`lib/services/local_door_service.dart`) + cihaz simülatörü (selftest 231/231) + sözleşme belgesi `docs/YEREL_KONTROL_V2.md`. Eski firmware/uygulama sürümleri v1 ile konuşamaz: firmware (C3 4.3.0, WROOM 5.2.0, ekran 1.1.1) ve APK birlikte güncellenmelidir.

**Faz 3 – Dokümantasyon**
- [x] `SAHA_KONTROL_LISTESI.md`: uygulama ajanlarının saha adımları (toplam 232 madde) bölüm 42–52'ye (sunucu, üyelik, cihaz/OTA, kapı/geofence/QR, site/davet, operasyon, sözleşme denetimi, Android, Flutter, firmware + yerel kontrol v2, arayüz/akıcılık) aktarıldı; eski bölümlerdeki bayat ifadeler düzeltildi (6 haneli kod, `GEOFENCE_*` kodları ve 60 sn / 100 m sınırları, üyelik menüsü, bakım servisinin hesap silmemesi).
- [x] `OTA_KURULUM.txt` (sha256 zorunlu, artan sürüm, hedef klasörleri, rollback), `MQTT_kurulum.txt` (topic/ACL listesi kodla aynı), `sunucu_kurulum.txt` (.env), `docs/codebase/TESTING.md` ve `PROJE_TEKNIK_NOTLAR.md` (roller) kodla doğrulanarak güncellendi.
- [x] Yeni davranışlar için saha adımları eklendi: yerel kontrol v2 / PIN / QR firmware (bölüm 51) ve arayüz yenileme + akıcılık (bölüm 52). Uçtan uca (emülatör) tur yapılmadı (Faz 4 iptal), bu adımları kullanıcı sahada/cihazda dener.

**Faz 4 – Emülatörlerde uçtan uca test, menü gezme ve düzeltme döngüsü** (**İPTAL EDİLDİ — 2026-10-02, kullanıcı kararı: denemeleri kullanıcı yapacak; kod doğrulaması yalnız analiz + birim/widget testi + derleme ile yapılır**)
- [x] Üretime dokunmadan yerel test ortamı kuruldu: yerel Postgres + MQTT (TLS) + sahte SMTP + API, ESP32 cihaz simülatörü (sözleşme C4-C7, C10), 11 kullanıcılı tohum verisi; tohumlama 0 hatayla çalışıyor.
- [x] (Kısmen çalıştırıldı, sonra iptal) Windows masaüstünde yürüyüş düzeneği: bireysel ×5 ve daire sakini ×3 yürüyüşleri 5 kombinasyonda 0 hata / 0 taşma verdi (46 senaryo). Site yöneticisi / süper kullanıcı matrisleri uygulama penceresi küçüldüğü için tamamlanmadı (ortam sorunu), kayıt-formu yürüyüşündeki 3 hata, betiğin "Kayıt Ol" başlığına dokunmasından (metin sayfada başlık + düğme olarak 2 kez geçer) kaynaklanıyordu; betik düzeltildi (`index: 1`), analiz temiz, yeniden KOŞULMADI. Düzenek `integration_test/` altında duruyor; çalıştırmak kullanıcıya kalmıştır.
- [ ] Android emülatörü / Windows / Chrome / Edge üzerinde rol bazlı menü gezme ve hata günlüğü toplama: **kullanıcı yapacak** (kontrol listesi bölüm 42–52).

**Faz 5 – Akıcılık, kilitlenmeme ve görsel cila**
- [x] Takılma/donma kaynakları kod ve birim testiyle ölçüldü (ana izole boşluğu, yeniden kurma sayaçları, boyama sayıları, istek sayıları; önce/sonra değerleri ajan raporunda). Kare süresi ölçüm düzeneği hazır (`integration_test/perf_frames_test.dart`, `test_driver/perf_driver.dart`; çalıştırma komutu `SAHA_KONTROL_LISTESI.md` bölüm 52'nin son maddesinde) — **çalıştırılmadı**, profil ölçümünü kullanıcı yapar.
- [x] Akıcılık / kilitlenmeme: PDF üretimi ve ≥64 KB JSON ayrıştırma arka plan izolesinde; yoklamalar `AdaptivePoller` ile (arka planda/örtülüyken durur, hatada üstel geri çekilme, üst üste binmez); yoklama sonucu yalnız ilgili paneli yeniden kurar; GET zaman aşımı 20 sn; soğuk açılış okumaları eşzamanlı; logo gösterim boyutunda çözülür. Sunucuda DB havuzu/sorgu/istek zaman aşımları ve SIGTERM ile düzgün kapanma önceki turlarda yapılmıştı; firmware tarafında watchdog ve dayanıklılık düzeltmeleri F1/F2A2/F2B ile yapıldı (MQTT bağlantı denemesinin ana döngüyü ≤~15 sn bloklaması ertelenenler listesinde).
- [x] Görsel yenileme ("Cilalı Safir" tasarım sistemi, `lib/ui/design/`): AppPalette/AppTone belirteçleri, açık temada ≥4,5:1 metin kontrastı, tek `DoorOpenButton`, `CountdownRing`, iskelet yükleyiciler, boş durum ekranları, durum rozetleri, çekmece gradyan başlığı, sayfa geçişleri, hareket azaltma desteği; ~60 ekran/diyalog/bileşen taşındı. AGENTS.md kural 6 (taşma yok: 320x640 ×2,0 dahil 534 tasarım + 1281 ekran testi), 7 (canlı yenileme) ve 2 (mevcut özellikleri bozmama: mevcut test iddiaları gevşetilmedi) korundu. `flutter analyze` temiz, `flutter test` 2357/2357, APK debug/release ve Windows debug derlemeleri başarılı.
- [ ] Görsel doğrulama (gerçek cihaz/emülatör ekran incelemesi, koyu tema dahil): **kullanıcı yapacak** — kontrol listesi bölüm 52. Ertelenen akıcılık işleri: PDF günlük raporu 20 sayfa sınırı (ürün kararı), sakin ağacı penceresinde tembel yükleme, `AllUsersView`/`CompanyDevicesView` sliver dönüşümü, `listMyDoors` widget senkronu, `IndividualHomeView` anında yenileme, `HomePage`'de kalan `setState` daraltması.

**Faz 6 – Canlıya dağıtım (AGENTS.md kural 8)**
- [x] **Sunucu (API) 2026-10-01 canlıya alındı** (`deploy/` betikleriyle): uzak yedek (`~/backups/kapi_<TS>/`: kod+.env+data, `pg_dump`, mosquitto acl/passwd) → hazırlık (paket sha256 doğrulandı, `node --check`, aşamalı `npm ci --omit=dev`; nodemailer 9.0.5 → 10.0.13) → etkinleştirme (PM2 `kapi-api` yeniden başlatıldı) → `/health` ok (DB + MQTT bağlı), `ensureDbSchema` ekleyici şema (users.updated_at, door_access_logs.client_log_id + tekil indeks, geofence varsayılanı 100) uygulandı, MQTT ACL'ye `logs` konuları eklendi (`kapi-mqtt-sync`), 3 cihazın `hardware_type` değeri cihaz bildirimine göre düzeldi (2 cihaz esp32_c3, 1 cihaz esp32_wroom).
- [x] Canlı `.env`: yeni kod için `COMPANY_API_KEY` tanımlandı (48 karakter) ve aynı değer `company_qr_tool/.env` dosyasına (gitignore'da) yazıldı; şirket aracı bu anahtarla çalışır. `JWT_SECRET` (20 karakter), `JWT_EXPIRES_IN=365d` ve `NODE_ENV` DEĞİŞTİRİLMEDİ (kullanıcı kararı; sunucu yalnız uyarı yazar).
- [x] Faz 5 sunucuda değişiklik yapmadı (istemci tarafı); Faz 4 iptal olduğundan ek sunucu dağıtımı gerekmedi. Sonraki sunucu değişikliğinde aynı `deploy/` betikleriyle yeniden dağıtılır.
- [ ] Uygulama (APK) ve firmware dağıtımı kullanıcı kararıdır (uygulama yeni sürüm kurulana kadar eski istemciler 6 haneli doğrulama kodunu giremeyebilir; yerel kontrol v2 için firmware + APK birlikte güncellenmelidir).

**Ertelenen düşük öncelikli işler (ajan raporlarından)**
- Sunucu: yerel UDP açmada cihaz offline logu ile uygulama bildirimi çift kayıt üretebilir (door-open#1); misafir geçişi link tabanı önceliği canlı `.env` doğrulanmadan değiştirilmedi (guest-pass#2); `site_rules.js` DEVICE_* hata `code` alanı; `generateQrTokenForDoor` erişilemeyen kapıda 403 yerine 404 (mevcut testi kırar); `ensureDbSchema` yalnız migration uygulanmış veritabanında çalışır (boş veritabanında açık hata verir).
- Sunucu tasarım kararı: koordinatsız sitede C3 statik QR için geofence kontrolü atlanır (fail-open; sahadaki C3 cihazlarını bloklamamak için korundu).
- Sunucu: hız sınırlayıcılar ve giriş kilidi bellek içidir (PM2 cluster'da Redis/DB gerekir); refresh-token/iptal listesi yok (`pv` yalnız parola değişimini iptal eder).
- Firmware: BLE eşleştirme/PIN (bonding); MQTT bağlantı denemesi ana döngüde ≤ ~15 sn bloklayabilir (röle `esp_timer` ile bağımsız bırakılır); yerel kontrol HTTP/UDP düz metin (token LAN'da dinlenebilir); süre bazlı zorla rollback yok; sunucudan PIN üretimi/arayüzü yok.
- Android: `com.example` applicationId ve debug imza (yayın kararı); biyometrik onay yok; iOS widget kaynağı depoda yok.
- Kapı geçiş kayıtlarında cihaz saati yoksa (epoch=0) kayıtlar saat gelince düzeltilir.

**Bilinçli olarak bu turun dışında (kullanıcı kararı veya ayrı iş gerektirir)**
- Canlı parolaların (VPS SSH, MQTT, DB, SMTP) değiştirilmesi ve git geçmişinin temizlenmesi (`git filter-repo`); commit/push. **Not:** bir VPS parolası sohbette düz metin paylaşıldı ve depo geçmişinde/firmware ikililerinde de bulundu; ACİLEN DÖNDÜRÜLMELİ (parola bu dosyaya yazılmaz).
- OTA firmware **kod imzalama** (anahtar yönetimi gerekir); bu turda SHA256 doğrulama + artan sürüm + rollback yapılır.
- Sunucudan cihaz başına yönetici PIN'i üretimi ve arayüzü; BLE provisioning eşleştirmesi (donanım/RAM etkisi ölçülerek).
- `firmware_releases/` klasörünün git izlemesinden çıkarılması, kök dizindeki artık dosyaların temizlenmesi, release imzası/applicationId (mağaza kararı).
- Canlı `.env` değerleri (`JWT_EXPIRES_IN=365d` → öneri 30d, `NODE_ENV=production`, `COMPANY_API_KEY`, `CORS_ORIGINS`).

