# Plaka Tanıma: kenar istemci sözleşmesi (A1, sürüm 1)

Güvenlik kulübesindeki Windows PC (kenar istemci, Aşama A2) ile sunucu arasındaki sözleşme. Karar KENARDA verilir (offline-first), kayıt SUNUCUDA tutulur. Sunucu kapı AÇMAZ: kapıyı yerel ağdan SmartKeyPass cihazına "aç" komutu göndererek kenar açar; "kapat" komutu asla gönderilmez.

Kaynak: `server/src/modules/plate_edge_routes.js`, `plate_edge_service.js`, `plate_gates_common.js` (doğrulayıcılar, saf kural işlevleri), `plate_gates_schema.js` (migration 120). Gerçek PG uçtan uca test: `server/test/plate_gates_pg.test.js` (`PLATE_GATES_PG_URL`).

## Sürümleme ve genişletme
- Her istek / yanıt `schema_version` taşır (şimdi `1`). Sunucu desteklemediği sürümü `400 UNSUPPORTED_SCHEMA` (`supported: [1]`) ile reddeder; `schema_version` yoksa 1 sayılır.
- Bilinmeyen EK alanlar yok sayılır: yeni alan eklemek eski sunucuyu bozmaz. Yeni sürüm = `SUPPORTED_SCHEMA_VERSIONS` listesine eklemek.
- Yön modu (`giris|cikis|cift`), kamera yönü (`giris|cikis|auto`), karar türü (`acildi|red|tanimsiz`), misafir kuralı (`tum_bos|en_az_bir_bos`), "içeride" türü (`resident|guest|other`) DB `CHECK` listesidir: yeni değer = tek migration (`DROP CONSTRAINT` + `ADD CONSTRAINT`) + `plate_gates_common.js` sabitine satır; `plate_gates.test.js` eşleşmeyi bekçiler.
- Kapı / kamera / kenar PC sayısı, kalp atışı eşikleri, misafir kuralı koda GÖMÜLÜ DEĞİL: `plate_gates`, `plate_gate_cameras`, `plate_edge_clients`, `plate_site_settings` kayıtları.

## Kimlik
`Authorization: Bearer <id>.<48 onaltılık>` ya da `X-Edge-Key`. Anahtarı site yöneticisi / süper, Plaka Tanıma → Geçiş noktaları → Kenar istemci bölümünden üretir (bir kez gösterilir; DB'de yalnız SHA-256 özeti). Kapsam anahtarın bağlı olduğu site; `plate_recognition` modülü kapalıysa `403 MODULE_DISABLED`; geçersiz / iptal / yenilenmiş eski anahtar `401 INVALID_EDGE_KEY`. 4xx (401/403 dışı) KALICI hatadır: aynı isteği yeniden deneme; 429/5xx geçicidir.

## Uçlar (`/edge/plate/v1`)
| Uç | Gövde / sorgu | Yanıt |
|---|---|---|
| `POST /claim` | `{schema_version?, app_version?}` | `client`, `site`, `intervals {heartbeat_seconds, sync_seconds}`, `supported_schema_versions` |
| `GET /sync` | `updated_since?` (ISO), `vehicles_rev?`, `permits_rev?`, `blacklist_rev?` | `config {settings {guest_rule, ...}, gates[{id,name,direction_mode,device_uid,is_active,cameras[{camera_id,direction,...}]}]}`, `vehicles`, `guest_permits`, `blacklist` (her biri `{rev, items}` ya da `{rev, unchanged:true}`), `apartments[{id, parking_slots, inside_count}]`, `presence {full, items[{plate, apartment_id, kind, inside, since_at}]}`, `server_time`, `full` |
| `POST /events` | `{schema_version, event_id (8-64, [A-Za-z0-9_-]), camera_id, plate, decision, seen_at (ISO), direction?, gate_id?, confidence?, reason?}` | `{ok, duplicate, event_id, direction, inside}` |
| `POST /heartbeat` | `{schema_version, app_version?, queue_depth?, cameras[{camera_id, last_frame_at?, last_read_at?}]}` | `{ok, server_time, intervals}` |

Delta: ilk senkronda yalnız `GET /sync`; sonrakinde önceki yanıttaki `server_time`'ı `updated_since` olarak ve bölüm `rev`'lerini geri gönderin. Bölüm `unchanged` ise yerel kopya geçerlidir. `presence.items` `updated_since`'ten sonra değişen satırlardır (çıkış `inside:false` ile gelir); `presence.full` doğruysa yerel "içeride" kopyasını değiştirin. `updated_since` 7 günden eskiyse ya da yoksa tam senkron döner. Sunucu 2 sn çakışma payı uygular (aynı satır tekrar gelebilir; uygulama idempotenttir).

## Olay kuralları
- `event_id` istemci tarafından üretilir ve olay başına SABİT kalır (SQLite kuyruğundan yeniden gönderimde aynı kimlik): ikinci gönderim `duplicate:true` döner, hiçbir şey yazılmaz.
- `decision`: `acildi` (kenar kapıyı açtı), `red`, `tanimsiz` (listede yok; kapı plakayla açılmaz, sürücü SmartKeyPass yollarını kullanır).
- Yön: kapı modu kesinse (`giris`/`cikis`) o; kamera bağı yönü kesinse o; çift yönde bildirilen `direction`; yoksa "içeride mi" durumundan (içerideyse çıkış, değilse giriş).
- "İçeride": giriş yalnız `acildi` ile işaretler; çıkış `acildi` ya da `tanimsiz` ile düşürür; `red` durumu değiştirmez. Sıra dışı gelen daha eski olay yeni durumu bozmaz (`since_at` karşılaştırması). Yönetici yanlış kalan satırı "İçeriden düşür" ile düzeltir.
- Kamera dairesi olmayan plaka (tanımsız) "içeride" listesine alınmaz; kayıtlı araç `resident`, geçerli misafir izni `guest` (daireye bağlı) olarak işaretlenir.

## Misafir kuralı (kenarın yerelde uygulayacağı)
Park yeri sayısı >= 1 VE kural sağlanıyorsa kabul. `tum_bos` (varsayılan, sahibin sözü): dairenin `inside_count` değeri 0. `en_az_bir_bos`: `inside_count < parking_slots`. 2 park yerli dairede 1 araç içerideyse varsayılan kuralda misafir REDDEDİLİR. Referans uygulama: `evaluateGuestAdmission` (`plate_gates_common.js`); kenar, kendi yerel "içeride" sayısını `apartments[].inside_count` + işlenmemiş yerel olaylarla birleştirerek hesaplar.

## Kalp atışı ve durum rozetleri
Kenar `intervals.heartbeat_seconds` aralığında `POST /heartbeat` gönderir (kamera başına son kare / son okuma). Yönetici ekranı gecikmeyi site ayarındaki eşiklerle (varsayılan 180 sn sarı, 600 sn kırmızı) rozete çevirir: çalışıyor (yeşil) / gecikmeli (sarı) / koptu (kırmızı) / hiç bağlanmadı (gri). Kamera rozeti `last_frame_at`'e, kenar PC rozeti son kalp atışına, SmartKeyPass rozeti cihazın MQTT çevrimiçi durumuna dayanır.
