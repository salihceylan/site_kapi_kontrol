# Plaka Tanıma (modül `plate_recognition`)

Migration 073 (`server/migrations/073_plate_recognition.sql` = `server/src/modules/plate_recognition_schema.js`, ekleyici ve idempotent, 6B tablolarına FK yok).
Katalog: `plate_recognition` "Plaka Tanıma", `available`, çekirdek değil, varsayılan KAPALI (süper açar, yönetici modül talep eder).

## Bu sürümde ne var, ne yok
- VAR: kameradan gelen plakanın karar kaydı (izinli / engelli / bilinmiyor + neden), sakin ve yönetici için geçici misafir plaka izni, kara liste, kapı-kamera eşlemesi ve ayarları.
- YOK: **kapı açma**. Kapı komutları, MQTT ve firmware koduna dokunulmadı. Kapı açma mantığı yalnız `/app/doors/:id/open` yol işleyicisinin içindedir (kapı bulma, politika, geofence, MQTT yayını bir arada); dışarıya açık, çağrılabilir bir servis işlevi yoktur. Çağırmak o kodu değiştirmeyi gerektirdiğinden otomatik açma YAPILMADI: `auto_open` açık kapıda ALLOWED + güven eşiği sağlanırsa karar `auto_action = would_open` ("açılırdı") diye kaydedilir ve arayüzde "Kapı açma: Yakında…" yazar. Kapı servisi dışa açıldığında yalnız `plate_recognition_service.handlePlateEvent` içindeki `would_open` dalına bir çağrı eklenir.

## Olay alma (6B'yi yeniden kullanır)
Kamera, 6B'nin belirteçli ucuna gönderir: `POST /camera-events/plate` (`Authorization: Bearer <kamera_id>.<gizli>`), gövde `{ plate, seen_at?, confidence? }`. 6B olayı `plate_events`'e yazar (modül `plate_cameras` AÇIK olmalı; kameralar "Kamera ve Plaka" modülünden kaydedilir). Ardından `plate_recognition` modülü o sitede AÇIKSA karar hesaplanıp `plate_decisions`'a yazılır; karar hatası olayı ve kameranın aldığı yanıtı ETKİLEMEZ. `confidence` 0-1 (ya da yüzde); kamera göndermezse karar yine verilir ama otomatik açma planı `none` kalır.

## Karar sırası
1. Plaka biçimi: boşluk / tire / nokta atılır, büyük harf, Türkçe harfler ASCII'ye iner; `34ABC123` biçimi (il kodu 01-81 + 1-3 harf + 2-4 rakam). Geçersiz -> UNKNOWN `invalid_plate`.
2. Okuma güveni eşiğin altında (varsayılan 0,85; kapıya eşli kameranın ayarındaki eşik) -> UNKNOWN `low_confidence`.
3. Kara liste -> DENIED `blacklist` (araç listesi ve misafir izninden ÖNCE).
4. Sitenin AKTİF araç listesinde (araç aktif; bağlı kişi ve daire aktif) -> ALLOWED `vehicle`.
5. Geçerli misafir izni (iptal edilmemiş, süresi dolmamış, dairesi aktif) -> ALLOWED `guest_permit`.
6. Aksi -> UNKNOWN `not_registered`.

Otomatik açma planı (`planAutoOpen`): ayar yok / `auto_open` kapalı / karar ALLOWED değil / güven bilinmiyor ya da kapıdaki eşiğin altı -> `none`; aynı plaka `cooldown_seconds` (varsayılan 30) içinde bir daha `would_open` almaz -> `suppressed_cooldown`; kapı son 60 saniyede 6 `would_open`'a ulaştıysa -> `suppressed_rate`. Sayım kapı başına danışma kilidi altında yapılır (art arda gelen kareler sınırı atlatmaz).

## Tablolar (073)
- `plate_guest_permits` (site_code, apartment_id, plate, valid_from, valid_until, note, created_by, created_at, revoked_at, revoked_by): en çok 30 gün (CHECK), plaka biçimi CHECK.
- `plate_blacklist` (site_code, plate, reason, created_by, created_at, removed_at, removed_by): kısmi tekil indeks (site, plate) WHERE removed_at IS NULL.
- `plate_gate_settings` (site_code, door_id, device_id [eşli kamera], auto_open DEFAULT FALSE, min_confidence DEFAULT 0.85, cooldown_seconds DEFAULT 30): (site, door) tekil; bir kamera tek kapıya eşlenir.
- `plate_decisions` (site_code, event_id [plate_events.id, tekil], device_id, door_id, plate, confidence, decision, reason, vehicle_id, permit_id, auto_action, decided_at).

## Uçlar
Yönetim (`/manager/sites/:siteCode/plate-recognition/...`): `GET events?limit&before_id&decision`, `GET|POST permits`, `POST permits/:id/revoke`, `GET apartments?q=`, `GET|POST blacklist`, `POST blacklist/:id/remove`, `GET settings`, `PUT settings/:doorId`.
Sakin: `GET /app/plate-permits?site_code=`, `POST /app/plate-permits`, `POST /app/plate-permits/:id/revoke`.

## Yetki ve sınırlar
- Yönetici / süper: tam. Kurul üyesi ve görevli: olayları, izinleri, kara listeyi, ayarları GÖRÜR, değiştirmez (403 `FORBIDDEN_ROLE`). Sakin: yalnız kendi dairesinin misafir izinlerini görür / verir / iptal eder (başkasının dairesi 403 `FORBIDDEN_APARTMENT`; bağlı olmadığı site 404). Başka sitenin yöneticisi 403 `FORBIDDEN_SITE`. Modül kapalıyken 403 `MODULE_DISABLED`.
- Misafir izni: 1 gün, 1 hafta ya da özel (1-30 gün); aynı plakanın geçerli izni varsa 409 `PERMIT_EXISTS`; sakin başına günlük 5 izin (429 `DAILY_LIMIT`, iptaller dahil sayılır).
- `auto_open` yalnız yönetici / süper açabilir; açarken kamera eşlemesi ve `confirm_risk: true` şarttır (400 `RISK_CONFIRM_REQUIRED`). Arayüz uyarısı: "Plakayla otomatik açma, sahte/kopya plakayla aldatılabilir. Yüksek güvenlik gerekiyorsa kapalı tutun."
- Hız sınırı: yönetim yazma 120/saat/kullanıcı, sakin yazma 30/saat/kullanıcı, okuma 1200/saat/kullanıcı. Gövde 4 KB.
- Denetim (`audit_log`): `plate.permit_created`, `plate.permit_revoked`, `plate.blacklist_added`, `plate.blacklist_removed`, `plate.settings_changed`, `plate.auto_open` (sistem; `executed:false`). Plaka denetime MASKELİ yazılır (`34***23`).
- Sınırlar: yalnız Türkiye plakası (diplomatik / yabancı plaka UNKNOWN kalır); plaka saklama süresi için otomatik silme yok; kamera bağlantısını sunucu çekmez, kamera / NVR olayı HTTP ile gönderecek şekilde ayarlanır; tek kamera = tek kapı.

## KVKK
Plaka kişisel veridir. Yalnız site güvenliği amacıyla işlenir, sakinlerle paylaşılmaz (sakin yalnız kendi misafir plakalarını görür); denetim kaydında maskelenir. Aydınlatma metni, saklama süresi ve hukuki dayanak: [AVUKAT DOĞRULASIN].

## Arayüz
Menü "Plaka Tanıma" (Site hizmetleri). Yönetici sekmeleri: Olaylar | Misafir izinleri | Kara liste | Ayarlar. Sakin: sade "Misafir plakası" ekranı. "Yetkili araçlar Araçlar ekranından yönetilir" notu Olaylar ve Misafir izinleri sekmelerinde.
