# Plaka Tanıma: kenar istemci sözleşmesi (A1 + A3, sürüm 2)

Güvenlik kulübesindeki Windows PC (kenar istemci, Aşama A2) ile sunucu arasındaki sözleşme. Karar KENARDA verilir (offline-first), kayıt SUNUCUDA tutulur. Sunucu kapı AÇMAZ: kapıyı yerel ağdan SmartKeyPass cihazına "aç" komutu göndererek kenar açar; "kapat" komutu asla gönderilmez.

Kaynak: `server/src/modules/plate_edge_routes.js`, `plate_edge_service.js`, `plate_gates_common.js` (doğrulayıcılar, saf kural işlevleri), `plate_gates_schema.js` (migration 120). Gerçek PG uçtan uca test: `server/test/plate_gates_pg.test.js` (`PLATE_GATES_PG_URL`).

## Sürümleme ve genişletme
- Her istek / yanıt `schema_version` taşır (şimdi `2`). Sunucu desteklemediği sürümü `400 UNSUPPORTED_SCHEMA` (`supported: [1, 2]`) ile reddeder; `schema_version` yoksa 1 sayılır.
- **Sürüm 2 (A3, migration 121)**: olay karar türü `kara_liste` eklendi. Yalnız sürüm 2 isteği `kara_liste` gönderebilir (sürüm 1 / sürümsüz istek `400`); diğer her şey sürüm 1 ile aynıdır, sürüm 1 istemcileri çalışmaya devam eder. Kara liste kümesi (`blacklist`) ilk günden sync yanıtındadır (tablo `plate_blacklist`, 073); sürüm 2 bu listenin KARARINI sözleşmeye bağlar (aşağıda).
- Bilinmeyen EK alanlar yok sayılır: yeni alan eklemek eski sunucuyu bozmaz. Yeni sürüm = `SUPPORTED_SCHEMA_VERSIONS` listesine eklemek.
- Yön modu (`giris|cikis|cift`), kamera yönü (`giris|cikis|auto`), karar türü (`acildi|red|tanimsiz|kara_liste`), misafir kuralı (`tum_bos|en_az_bir_bos`), "içeride" türü (`resident|guest|other`) DB `CHECK` listesidir: yeni değer = tek migration (`DROP CONSTRAINT` + `ADD CONSTRAINT`) + `plate_gates_common.js` sabitine satır; `plate_gates.test.js` / `plate_alerts.test.js` eşleşmeyi bekçiler.
- Kapı / kamera / kenar PC sayısı, kalp atışı eşikleri, misafir kuralı, "içeride" rapor / zaman aşımı saatleri, uyarı sıklığı koda GÖMÜLÜ DEĞİL: `plate_gates`, `plate_gate_cameras`, `plate_edge_clients`, `plate_site_settings` kayıtları.

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
- `decision`: `acildi` (kenar kapıyı açtı), `red`, `tanimsiz` (listede yok; kapı plakayla açılmaz, sürücü SmartKeyPass yollarını kullanır), `kara_liste` (v2: plaka site kara listesinde; kenar kapıyı ASLA açmaz, sunucu "içeride" durumunu değiştirmez, eski Olaylar akışında `DENIED` / `blacklist` görünür).
- Kara liste kenar kararı: giriş şeridinde `kara_liste` ASLA açılmaz. Çıkış şeridinde de varsayılan açılmaz; içeride kalan araç için yönetici kenar ayarıyla (`karar.kara_liste_cikis_acilir`) çıkışa izin verebilir (iç mekânda hapsetme riski). Kara liste, sakin kaydından ve misafir izninden ÖNCE değerlendirilir.
- Yön: kapı modu kesinse (`giris`/`cikis`) o; kamera bağı yönü kesinse o; çift yönde bildirilen `direction`; yoksa "içeride mi" durumundan (içerideyse çıkış, değilse giriş).
- "İçeride": giriş yalnız `acildi` ile işaretler; çıkış `acildi` ya da `tanimsiz` ile düşürür; `red` durumu değiştirmez. Sıra dışı gelen daha eski olay yeni durumu bozmaz (`since_at` karşılaştırması). Yönetici yanlış kalan satırı "İçeriden düşür" ile düzeltir.
- Kamera dairesi olmayan plaka (tanımsız) "içeride" listesine alınmaz; kayıtlı araç `resident`, geçerli misafir izni `guest` (daireye bağlı) olarak işaretlenir.

## Misafir kuralı (kenarın yerelde uygulayacağı)
Park yeri sayısı >= 1 VE kural sağlanıyorsa kabul. `tum_bos` (varsayılan, sahibin sözü): dairenin `inside_count` değeri 0. `en_az_bir_bos`: `inside_count < parking_slots`. 2 park yerli dairede 1 araç içerideyse varsayılan kuralda misafir REDDEDİLİR. Referans uygulama: `evaluateGuestAdmission` (`plate_gates_common.js`); kenar, kendi yerel "içeride" sayısını `apartments[].inside_count` + işlenmemiş yerel olaylarla birleştirerek hesaplar.

## Kalp atışı ve durum rozetleri
Kenar `intervals.heartbeat_seconds` aralığında `POST /heartbeat` gönderir (kamera başına son kare / son okuma). Yönetici ekranı gecikmeyi site ayarındaki eşiklerle (varsayılan 180 sn sarı, 600 sn kırmızı) rozete çevirir: çalışıyor (yeşil) / gecikmeli (sarı) / koptu (kırmızı) / hiç bağlanmadı (gri). Kamera rozeti `last_frame_at`'e, kenar PC rozeti son kalp atışına, SmartKeyPass rozeti cihazın MQTT çevrimiçi durumuna dayanır.

## Bildirimler ve raporlar (A3, sunucu tarafı; kenarın yapacağı bir şey yok)
- **Kopukluk uyarısı**: kenar PC ya da (kapıya bağlı, etkin) bir kamera en az bir kez haber verdikten sonra KIRMIZI eşiği (`heartbeat_crit_seconds`) aşarsa site yöneticilerine uyarı düşer: site denetim kaydı (`plate.edge_disconnected`) + anlık bildirim. Aynı site için en çok `alert_interval_minutes` (varsayılan 60) dakikada bir (kalıcı sınırlayıcı `plate_alert_state`; yeniden başlatma ya da çift süreç tekrar göndermez). Zamanlayıcı 5 dakikada bir koşar (`PLATE_HEALTH_DISABLED=1` ile kapalı).
- **Sakin bildirimi**: kayıtlı aracın "içeride" durumu gerçekten değiştiğinde (kenar `acildi` bildirdi) ve olay `resident_notify_max_age_minutes` (varsayılan 15) dakikadan tazeyse, aracın sahibine "Aracınız 18:32'de giriş yaptı" (Türkçe ek uyumlu, İstanbul saati, plakasız). Kişi bazında aç/kapa, **varsayılan KAPALI** (`plate_notify_prefs`; sakin uygulaması Plaka Tanıma sayfasından açar). Sahip: araç kaydına bağlı kişinin hesabı, kişi yoksa dairenin güncel sakinleri.
- **Çıkışı olmayan girişler**: yönetici "İçeride" listesi `inside_report_hours` (varsayılan 12) saatten uzun içeride görünen araçları ayrı bölümde gösterir.
- **İçeride zaman aşımı**: `inside_timeout_hours` (varsayılan 24, rapor eşiğinden büyük olmalı) saati aşan "içeride" kaydı bakım rutininde otomatik düşer (kenara bir sonraki senkronda `inside:false` gider) ve denetim kaydına `plate.inside_timeout` izi (adet + maskeli plakalar) bırakılır.
- Sync yanıtı `config.settings` yeni eşiklerle genişlemedi: kenar bu eşikleri bilmek zorunda değildir.
