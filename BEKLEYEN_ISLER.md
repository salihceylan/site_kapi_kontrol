# 📌 AHBU & SİTE KAPI KONTROL - BEKLEYEN İŞLER VE YOL HARİTASI (ROADMAP)

**Son Güncelleme:** 2026-09-08  
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
  - Dinamik QR rotasyon süresi ayarı (15s, 30s, 60s), Misafir geçiş kodu yetkilendirme açma/kapama ve GPS Geofencing (enlem, boylam, yarıçap) parametreleri entegre edildi.

### 2.2 Kullanıcı & Yönetici Uygulaması (`ahbu`)
- [ ] **Daire Sakini (`apartment_owner`) Giriş ve Aktivasyon Akışı:**
  - Yönetici veya süper kullanıcı tarafından oluşturulan daire sakinlerinin kullanıcı adı / PIN veya e-posta ile şifre belirleme akışının `ahbu` arayüzünde pürüzsüzleştirilmesi.
- [x] **Çevrimdışı Kapı Geçiş Log Senkronizasyon İstemcisi:**
  - Cihaz çevrimdışıyken hafızaya aldığı geçiş kayıtlarının, yetkili kullanıcının Bluetooth veya yerel UDP ile bağlanması sonrası API'ye aktarımı için `syncDeviceLogs` (`POST /device/sync-logs`) istemci metotları `auth_api.dart` ve `auth_service.dart` katmanlarına eklendi.

---

## 3. 🌐 Backend & Sunucu (Node.js API & PostgreSQL)

### 3.1 Canlı Sunucu (VPS) Deployment
- [ ] **Modüler Yapının Canlıya Alınması:**
  - 6.600 satırdan 75 satıra düşürülen modüler `server.js` ve servis/router katmanlarının VPS üzerinde `git pull` edilip PM2 üzerinden yeniden başlatılması:
    ```bash
    cd /var/www/site_kapi_kontrol
    git pull origin main
    cd server
    npm install
    pm2 restart kapi-api --update-env
    curl http://127.0.0.1:8080/health
    ```
- [ ] **Canlı Sağlık & Veritabanı Kontrolü:**
  - `/health` endpoint'i üzerinden veritabanı bağlantısı ve MQTT köprüsü kontrol edilecek.

### 3.2 Veritabanı & Şema Yönetimi
- [x] **Migration Standardizasyonu:**
  - `server/migrations/008_guest_passes_and_door_logs.sql` ve `009_site_feature_and_access_policies.sql` oluşturularak `server/src/db.js` içindeki `ensureDbSchema()` fonksiyonunun son şeması ile birebir senkronize edildi.
- [ ] **Detaylı Audit Log Altyapısı:**
  - Yetki değişiklikleri, kapı atamaları, uzaktan açma ve token rotasyonları için veritabanında saklanan audit log tablosunun raporlama ekranı.

---

## 4. 🧪 Test & Kalite Güvencesi (QA)
- [x] Mobil uygulama statik analizi (`flutter analyze` - 0 sorun).
- [x] Mobil widget & servis testleri (32 test başarılı).
- [x] Backend modül import ve runtime kontrolü (tüm servis ve router'lar doğrulandı).
- [x] Backend için otomatik birim testlerinin (`node:test`) eklenmesi (`helpers.test.js`, `validators.test.js`, `npm test` - 19 test başarılı).

---

## 5. 📦 Tamamlanan Önemli Kilometre Taşları (Referans)
- ✅ `server.js` monolitik yapısının tamamen servis ve router katmanlarına ayrılması (75 satırlık ana orkestratör).
- ✅ Çift donanım hedefli (ESP32-C3 ve ESP32-WROOM) izole OTA manifest ve firmware dağıtım sistemi.
- ✅ Siteye özel geçiş modelleri: Süper kullanıcı kontrollü Sadece QR, Sadece Uygulama veya Hibrit geçiş modu + Geofence + Dinamik QR rotasyonu.
- ✅ GM60 QR / barkod okuyucunun UART üzerinden firmware'e entegre edilmesi.
- ✅ Misafir geçiş sistemi: Dinamik süre/tek kullanımlık linkler, mobil kartlar ve `/guest/:token` web açılış sayfası.
- ✅ Yerel UDP fallback ve dinamik token rotasyon sistemi (internet kesintisinde kapı kontrolü).
- ✅ Mobil uygulamada açılır-kapanır (akordeon) kapı telemetri ve log kartları tasarımı.

