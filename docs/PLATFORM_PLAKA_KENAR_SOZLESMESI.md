# Plaka Tanıma: kenar istemci sözleşmesi (A1 + A3 + uygulama entegrasyonu, sürüm 3)

Güvenlik kulübesindeki Windows PC (kenar istemci, Aşama A2) ile sunucu arasındaki sözleşme. Karar KENARDA verilir (offline-first), kayıt SUNUCUDA tutulur. Sunucu kapı AÇMAZ: kapıyı yerel ağdan SmartKeyPass cihazına "aç" komutu göndererek kenar açar; "kapat" komutu asla gönderilmez.

**Sürüm 3 ilkesi**: yönetici HER ŞEYİ web / mobil uygulamadan yapar; kenar uygulama görünmez MOTORdur. Sunucu yerel ağı taramaz ve RTSP izlemez, kenar KÖPRÜDÜR: yönetici uygulamada komut verir (ağda kamera ara, kamerayı sına), sunucu komutu kuyruğa koyar, kenar bir sonraki yoklamada alır, yerelde çalıştırır ve sonucu geri gönderir. Kenar PC çevrimdışıysa uygulama bunu dürüstçe söyler; sahte başarı yoktur.

Kaynak: `server/src/modules/plate_edge_routes.js`, `plate_edge_service.js`, `plate_edge_commands.js` (komut kuyruğu), `plate_cameras_service.js` (kamera yönetimi + görüntü karoları), `plate_gates_common.js` (doğrulayıcılar, saf kural işlevleri), `plate_gates_schema.js` (migration 120), `plate_alerts_schema.js` (121), `plate_cameras_schema.js` (122). Gerçek PG uçtan uca test: `server/test/plate_gates_pg.test.js` (`PLATE_GATES_PG_URL`).

## Sürümleme ve genişletme
- Her istek / yanıt `schema_version` taşır (şimdi `3`). Sunucu desteklemediği sürümü `400 UNSUPPORTED_SCHEMA` (`supported: [1, 2, 3]`) ile reddeder; `schema_version` yoksa 1 sayılır.
- **Sürüm 2 (A3, migration 121)**: olay karar türü `kara_liste` eklendi. Yalnız sürüm 2+ isteği `kara_liste` gönderebilir (sürüm 1 / sürümsüz istek `400`).
- **Sürüm 3 (migration 122)**: yalnız EKLEYİCİDİR. Yeni uçlar (komutlar, görüntü karosu), olaya isteğe bağlı kimlik / kapı komutu alanları, kalp atışına tanıma hazırlığı, senkron yanıtına kamera tanımları + kimlik etiketleri. Sürüm 1 / 2 istemcileri çalışmaya devam eder (yeni alanları yok sayılır / göndermez). Olay gövdesindeki sürüm 3 alanları yalnız `schema_version >= 3` iken okunur.
- Bilinmeyen EK alanlar yok sayılır: yeni alan eklemek eski sunucuyu bozmaz. Yeni sürüm = `SUPPORTED_SCHEMA_VERSIONS` listesine eklemek.
- Yön modu (`giris|cikis|cift`), kamera yönü (`giris|cikis|auto`), karar türü (`acildi|red|tanimsiz|kara_liste`), misafir kuralı (`tum_bos|en_az_bir_bos`), "içeride" türü (`resident|guest|other`), komut türü (`discover|probe`), komut durumu (`pending|running|done|failed|expired`), kamera sınama durumu (`none|pending|ok|failed`), kapı komutu (`accepted|failed`), kimlik türü (`resident|guest`) DB `CHECK` listesidir: yeni değer = tek migration + `plate_gates_common.js` sabitine satır; test bekçileri eşleşmeyi doğrular.
- Kapı / kamera / kenar PC sayısı, kalp atışı eşikleri, misafir kuralı, "içeride" rapor / zaman aşımı saatleri, uyarı sıklığı, komut ömrü, görüntü aralığı koda GÖMÜLÜ DEĞİL: `plate_gates`, `plate_gate_cameras`, `plate_edge_clients`, `plate_site_settings` kayıtları.

## Kimlik
`Authorization: Bearer <id>.<48 onaltılık>` ya da `X-Edge-Key`. Anahtarı site yöneticisi / süper, Plaka Tanıma → Geçiş noktaları → Kenar istemci bölümünden üretir (bir kez gösterilir; DB'de yalnız SHA-256 özeti). Kapsam anahtarın bağlı olduğu site; `plate_recognition` modülü kapalıysa `403 MODULE_DISABLED`; geçersiz / iptal / yenilenmiş eski anahtar `401 INVALID_EDGE_KEY`. 4xx (401/403 dışı) KALICI hatadır: aynı isteği yeniden deneme; 429/5xx geçicidir.

## Kenar uçları (`/edge/plate/v1`)
| Uç | Gövde / sorgu | Yanıt |
|---|---|---|
| `POST /claim` | `{schema_version?, app_version?}` | `client`, `site`, `intervals {heartbeat_seconds, sync_seconds}`, `supported_schema_versions` |
| `GET /sync` | `updated_since?` (ISO), `vehicles_rev?`, `permits_rev?`, `blacklist_rev?` | `config {settings {guest_rule, ..., snapshot_interval_seconds, snapshot_idle_interval_seconds}, gates[...], cameras[...]}`, `vehicles`, `guest_permits`, `blacklist` (her biri `{rev, items}` ya da `{rev, unchanged:true}`), `apartments[{id, parking_slots, inside_count}]`, `presence {full, items[...]}`, `server_time`, `full` |
| `POST /events` | `{schema_version, event_id (8-64, [A-Za-z0-9_-]), camera_id, plate, decision, seen_at (ISO), direction?, gate_id?, confidence?, reason?, apartment_id?, kind?, gate_command?}` | `{ok, duplicate, event_id, direction, inside}` |
| `POST /heartbeat` | `{schema_version, app_version?, queue_depth?, cameras[{camera_id, last_frame_at?, last_read_at?}], recognition?{ready, note?}}` | `{ok, server_time, intervals, commands[...]}` |
| `GET /commands` | yok | `{schema_version, server_time, commands[{id, kind, created_at, payload}]}` |
| `POST /commands/:id/result` | `{schema_version, status: "done"\|"failed", message?, result?}` | `{ok}` |
| `PUT /cameras/:cameraId/snapshot` | gövde = ham JPEG (`Content-Type: image/jpeg`); üstbilgi `X-Captured-At?` (ISO), `X-Frame-Width?`, `X-Frame-Height?` | `{ok, watched, next_seconds}` |

Delta: ilk senkronda yalnız `GET /sync`; sonrakinde önceki yanıttaki `server_time`'ı `updated_since` olarak ve bölüm `rev`'lerini geri gönderin. Bölüm `unchanged` ise yerel kopya geçerlidir. `presence.items` `updated_since`'ten sonra değişen satırlardır (çıkış `inside:false` ile gelir); `presence.full` doğruysa yerel "içeride" kopyasını değiştirin. `updated_since` 7 günden eskiyse ya da yoksa tam senkron döner. Sunucu 2 sn çakışma payı uygular (aynı satır tekrar gelebilir; uygulama idempotenttir).

## Olay kuralları
- `event_id` istemci tarafından üretilir ve olay başına SABİT kalır (SQLite kuyruğundan yeniden gönderimde aynı kimlik): ikinci gönderim `duplicate:true` döner, hiçbir şey yazılmaz.
- `decision`: `acildi` (kenar kapıyı açma komutunu verdi ve SmartKeyPass komutu KABUL ETTİ), `red`, `tanimsiz` (listede yok; kapı plakayla açılmaz, sürücü SmartKeyPass yollarını kullanır), `kara_liste` (v2: plaka site kara listesinde; kenar kapıyı ASLA açmaz, sunucu "içeride" durumunu değiştirmez, eski Olaylar akışında `DENIED` / `blacklist` görünür).
- Kara liste kenar kararı: giriş şeridinde `kara_liste` ASLA açılmaz. Çıkış şeridinde de varsayılan açılmaz; içeride kalan araç için yönetici kenar ayarıyla (`karar.kara_liste_cikis_acilir`) çıkışa izin verebilir (iç mekânda hapsetme riski). Kara liste, sakin kaydından ve misafir izninden ÖNCE değerlendirilir.
- Yön: kapı modu kesinse (`giris`/`cikis`) o; kamera bağı yönü kesinse o; çift yönde bildirilen `direction`; yoksa "içeride mi" durumundan (içerideyse çıkış, değilse giriş).
- "İçeride": giriş yalnız `acildi` ile işaretler; çıkış `acildi` ya da `tanimsiz` ile düşürür; `red` durumu değiştirmez. Sıra dışı gelen daha eski olay yeni durumu bozmaz (`since_at` karşılaştırması). Yönetici yanlış kalan satırı "İçeriden düşür" ile düzeltir.
- Kamera dairesi olmayan plaka (tanımsız) "içeride" listesine alınmaz; kayıtlı araç `resident`, geçerli misafir izni `guest` (daireye bağlı) olarak işaretlenir.

### Sürüm 3 olay alanları (hepsi isteğe bağlı)
- `apartment_id` (tam sayı): kenarın yerel izin deposundan bulduğu daire. Sunucu kaydı KENDİ araç / izin aramasından türetir; yalnız o bulunamazsa (araç bu arada silindi) ve daire bu siteye aitse bu ipucunu kullanır.
- `kind` (`resident` | `guest`): kenarın yerelde tanıdığı kimlik türü (kayıtlı araç / misafir izni). Tanımsız plakada gönderilmez.
- `gate_command` (`accepted` | `failed`): kapı açma komutu denendiyse sonucu. `accepted` = SmartKeyPass komutu KABUL ETTİ (fiziksel açılma kanıtı DEĞİLDİR; cihaz kapının açıldığını bildirmez); `failed` = komut kabul edilmedi / cihaz yanıt vermedi (`reason` nedeni taşır). Açma denenmediyse alan yoktur. Uygulama dili: "Kapı tetiklendi ✓" / "Kapı yanıt vermedi ✗"; "açıldı" yazılmaz (P1-15).
- Sunucu olay kaydına `apartment_id`, `person_id` (kayıtlı araçtan), `identity_kind`, `gate_command` yazar. Kişi adı olay satırında KOPYALANMAZ; okuma anında `site_people` ile birleştirilir ("Ali Yılmaz" → "Ali Y.").
- **Kapı günlüğü**: `acildi` olayı (komut reddedilmediyse) SmartKeyPass kapı günlüğüne (`door_access_logs`) `trigger_type = 'plate'` ile düşer: `user_name` = "34 ABC 123 · Ali V." (misafirde "34 ABC 123 · Misafir", bilinmeyende yalnız plaka), `apartment_label` = daire etiketi, `door_name` = geçiş noktası adı, `door_id` = geçiş noktasına bağlı kapı. Mevcut kapı günlüğü ekranlarında "Plaka ile" olarak kendiliğinden görünür. `gate_command = failed` olaylar günlüğe yazılmaz (kapı açılmadı).

## Senkron yanıtına sürüm 3 eklemeleri
- `config.settings`: `snapshot_interval_seconds` (izleyen varken görüntü aralığı), `snapshot_idle_interval_seconds` (izleyen yokken).
- `config.cameras[]` (yalnız etkin, RTSP adresi tanımlı, uygulamadan eklenmiş kameralar; her senkronda tam liste, delta DEĞİL): `{camera_id, name, brand, host, port, rtsp_url, username, password, gate_id, direction}`. `rtsp_url` kimliksizdir; `username` / `password` ayrıdır (parola sunucuda AES-256-GCM ile şifreli saklanır, yalnız bu yanıtta TLS üzerinden açık iner ve `Cache-Control: no-store` taşır). Kenar bu satırları `ayarlar.json` > `kameralar` içine `kaynak: "sunucu"` işaretiyle birleştirir: sunucudan gelmeyen sunucu-kaynaklı satır silinir, yerelde elle eklenen (işaretsiz) satırlar KORUNUR; aynı `sunucu_id`'li yerel satır varsa yerel kazanır. `gate_id`, yerelde `sunucu_id`'si eşleşen kapıya bağlanır; eşleşen yerel kapı yoksa kamera görüntü / sınama için çalışır ama kapı açamaz (kenar uyarı yazar).
- `vehicles.items[]`: `apartment_label` ve `person_label` ("Ali Y."); `guest_permits.items[]`: `apartment_label`. Kenar bunları mozaik karosunda ve olay şeridinde "Daire A - 5 · Ali Y." / "Misafir — Daire A - 5" olarak gösterir; tanımsız plakada yalnız plaka. Etiketler `rev` hesabına girer.

## Kalp atışı ve durum rozetleri
Kenar `intervals.heartbeat_seconds` aralığında `POST /heartbeat` gönderir (kamera başına son kare / son okuma; v3: `recognition {ready, note?}` = okuma modelinin onaylı olup olmadığı, kalibrasyon modunda `ready:false`). Yönetici ekranı gecikmeyi site ayarındaki eşiklerle (varsayılan 180 sn sarı, 600 sn kırmızı) rozete çevirir: çalışıyor (yeşil) / gecikmeli (sarı) / koptu (kırmızı) / hiç bağlanmadı (gri). Kamera rozeti `last_frame_at`'e, kenar PC rozeti son kalp atışına, SmartKeyPass rozeti cihazın MQTT çevrimiçi durumuna dayanır.

**Plakayla otomatik kapı açma durumu** (uygulamadaki satır, "Yakında…" yerine): sunucu hesaplar. Etkin = en az bir kenar istemci çevrimiçi (yeşil / sarı) VE okuma hazır (`recognition.ready`) VE en az bir kapıya bağlı etkin kamera. Değilse nedeni yazılır: `no_edge_client` (kenar uygulama tanımlı değil), `edge_offline` (kenar PC çevrimdışı), `model_not_approved` (okuma modeli onaylanmadı / kalibrasyon modu), `no_camera` (kapıya bağlı kamera yok). Kapı yine de yalnız kenarın yerel kararıyla (model onayı kilidi) açılır; sunucu hiçbir koşulda kapı açmaz.

## Uzaktan komutlar (sürüm 3)
Yönetici uygulamadan komut verir; sunucu `plate_edge_commands` kuyruğuna yazar (site + kenar istemci hedefli). Kenar komutu `GET /commands` (hızlı yoklama, ayarlı; varsayılan 5 sn) ya da kalp atışı yanıtındaki `commands` ile alır — ikisi de aynı atomik talebi kullanır (bir komut iki kez verilmez): talep edilen komut `running` olur. Sonucu `POST /commands/:id/result` ile bildirir. Komut `command_ttl_seconds` (site ayarı, varsayılan 600) içinde alınmazsa / tamamlanmazsa `expired` olur ve uygulama bunu söyler. Hedef kenar PC çevrimdışıysa komut yine kuyruğa girer; uygulama "kenar PC çevrimdışı (son görülme …)" der ve komutun ne zamana kadar bekleyeceğini yazar.
- `discover` ("Ağda kamera ara"): `payload {}`. Kenar mevcut keşfi (ONVIF WS-Discovery + yerel alt ağ TCP taraması) çalıştırır. Sonuç: `{devices[{ip, ports[int], name, model, source ("onvif"|"onvif+tarama"|"tarama"), label, rtsp_port}], summary, onvif_count, scan_count, interfaces[ip]}`.
- `probe` ("Kamerayı sına"): `payload {camera_id, name, brand, host, port, rtsp_url|null, username|null, password|null}` (parola kuyruğa DÜZ yazılmaz; sunucu komutu verirken şifreyi çözüp yanıta koyar). Kenar RTSP'ye bağlanıp bir kare alır. `rtsp_url` boşsa ONVIF `GetStreamUri` ile çözmeyi dener. Sonuç: `{ok, width?, height?, reason?, message?, rtsp_url?}` (`rtsp_url` kimliksiz, yalnız ONVIF ile çözüldüyse; sunucu kamerada boşsa kaydeder). Sunucu sonucu `camera_devices.probe_*` sütunlarına yazar: uygulamada satır rozeti ("RTSP sınandı 1920x1080" / "Başarısız: …").
- Kamera eklenir ya da adres / kimlik bilgisi değişirse sunucu kendiliğinden bir `probe` komutu kuyruğa alır (kenar tanımlıysa).

## Görüntü karoları (sürüm 3)
Kenar, etkin her kameradan küçük bir JPEG (yaklaşık 360p, kalite ayarlı) gönderir: aralık sunucudan gelir (`snapshot_interval_seconds`; izleyen yoksa `snapshot_idle_interval_seconds`; yanıttaki `next_seconds` uygulanır, yerel `goruntu_gonderim` ayarı alt sınırdır). `watched`: son süre içinde bir yönetici görüntüleri istedi. Gönderici `ayarlar.json` > `goruntu_gonderim.etkin` ile kapatılabilir (varsayılan açık).
- **KVKK**: sunucuda her kameranın yalnız SON karesi tutulur (üzerine yazılır); tarihçe YOKTUR. Kare `snapshot_keep_minutes` (site ayarı, varsayılan 30) dakikadan eskiyse ya da kamera pasifleşmişse bakım turu siler. Görüntüyü yalnız site yöneticisi / süper kendi sitesinde görür (kurul / görevli 403); denetim kaydına görüntü yazılmaz.
- Yönetici ucu: `GET /manager/sites/:siteCode/plate-recognition/cameras/:id/snapshot` → `image/jpeg`, `Cache-Control: no-store`, `X-Captured-At`, `ETag` (`If-None-Match` ile 304). Kare yoksa / bayatsa `404 NO_SNAPSHOT`.

## Yönetici uçları (uygulama; `/manager/sites/:siteCode/plate-recognition/...`)
Yetki: kamera listesi okuma = yönetici / süper / kurul / görevli; ekleme / değiştirme / sınama / keşif / görüntü = yönetici / süper. Modül `plate_recognition` kapalıysa `403 MODULE_DISABLED`.
| Uç | Gövde | Yanıt |
|---|---|---|
| `GET cameras` | yok | `{server_time, cameras[...], gates[...], edge {clients[...], online, count}, auto_open {state, reason, message}, snapshot {...}, brands[...]}` |
| `POST cameras` | `{name, brand (hikvision\|tiandy\|onvif), host, port?, rtsp_url?, rtsp_path?, username?, password?, gate_id?, direction?}` | 201 `{camera, probe_command_id, edge}` |
| `PUT cameras/:id` | aynı alanlar kısmi + `is_active` (parola: gönderilmezse korunur, `""` ise silinir) | `{camera, probe_command_id}` |
| `POST cameras/:id/probe` | yok | 202 `{command}` |
| `GET cameras/:id/snapshot` | yok | `image/jpeg` |
| `POST discovery` | `{edge_client_id?}` | 202 `{command, reused}` |
| `GET discovery` | yok | `{command\|null, edge\|null}` (son keşif komutu: durum + sonuç) |

`rtsp_url` verilmişse o; yoksa `rtsp_path` `rtsp://host:port` ardına eklenir; yoksa markanın varsayılan yolu (`brands[].default_rtsp_path`: Hikvision `/Streaming/Channels/101`, Tiandy `/1/1`); ONVIF markasında yol boş kalır ve kenar ONVIF ile çözer. `host` / `port` RTSP adresinden de türetilebilir. Kamera satırı: `{id, name, brand, brand_label, host, port, rtsp_url, username, has_password, is_active, managed, gate {id, name, direction_mode}|null, direction, status {state, color}, last_frame_at, last_read_at, probe {status, message, width, height, at}, snapshot {available, captured_at}}`; PAROLA hiçbir yanıtta dönmez. Komut: `{id, kind, status, created_at, picked_at, completed_at, message, result, edge {id, name, online, last_seen_at}, waiting_offline}`.
Hedef kenar: `edge_client_id` yoksa tek etkin kenar istemci varsa o, yoksa `400 EDGE_CLIENT_REQUIRED`, hiç yoksa `409 NO_EDGE_CLIENT`. Aynı kenara bekleyen / çalışan aynı türde komut varsa yenisi açılmaz, mevcut döner (`reused:true`).

Canlı akış satırları (`GET events?live=1`) v3'te: `identity {kind (resident|guest), apartment_label, person_label}` (yalnız yazma yetkisi olana; aksi `null`) ve `gate_state` (`triggered` = komut kabul edildi | `no_response` = yanıt yok | `null`).

## Misafir kuralı (kenarın yerelde uygulayacağı)
Park yeri sayısı >= 1 VE kural sağlanıyorsa kabul. `tum_bos` (varsayılan, sahibin sözü): dairenin `inside_count` değeri 0. `en_az_bir_bos`: `inside_count < parking_slots`. 2 park yerli dairede 1 araç içerideyse varsayılan kuralda misafir REDDEDİLİR. Referans uygulama: `evaluateGuestAdmission` (`plate_gates_common.js`); kenar, kendi yerel "içeride" sayısını `apartments[].inside_count` + işlenmemiş yerel olaylarla birleştirerek hesaplar.

## Bildirimler ve raporlar (A3, sunucu tarafı; kenarın yapacağı bir şey yok)
- **Kopukluk uyarısı**: kenar PC ya da (kapıya bağlı, etkin) bir kamera en az bir kez haber verdikten sonra KIRMIZI eşiği (`heartbeat_crit_seconds`) aşarsa site yöneticilerine uyarı düşer: site denetim kaydı (`plate.edge_disconnected`) + anlık bildirim. Aynı site için en çok `alert_interval_minutes` (varsayılan 60) dakikada bir (kalıcı sınırlayıcı `plate_alert_state`; yeniden başlatma ya da çift süreç tekrar göndermez). Zamanlayıcı 5 dakikada bir koşar (`PLATE_HEALTH_DISABLED=1` ile kapalı).
- **Sakin bildirimi**: kayıtlı aracın "içeride" durumu gerçekten değiştiğinde (kenar `acildi` bildirdi) ve olay `resident_notify_max_age_minutes` (varsayılan 15) dakikadan tazeyse, aracın sahibine "Aracınız 18:32'de giriş yaptı" (Türkçe ek uyumlu, İstanbul saati, plakasız). Kişi bazında aç/kapa, **varsayılan KAPALI** (`plate_notify_prefs`; sakin uygulaması Plaka Tanıma sayfasından açar). Sahip: araç kaydına bağlı kişinin hesabı, kişi yoksa dairenin güncel sakinleri.
- **Çıkışı olmayan girişler**: yönetici "İçeride" listesi `inside_report_hours` (varsayılan 12) saatten uzun içeride görünen araçları ayrı bölümde gösterir.
- **İçeride zaman aşımı**: `inside_timeout_hours` (varsayılan 24, rapor eşiğinden büyük olmalı) saati aşan "içeride" kaydı bakım rutininde otomatik düşer (kenara bir sonraki senkronda `inside:false` gider) ve denetim kaydına `plate.inside_timeout` izi (adet + maskeli plakalar) bırakılır.
- **Görüntü bakımı (v3)**: aynı bakım turu `snapshot_keep_minutes`'ten eski ya da pasif kameranın karesini siler; süresi dolan komutları `expired` yapar.
- Sync yanıtı `config.settings` yeni eşiklerle genişlemedi (A3): kenar bu eşikleri bilmek zorunda değildir; v3'te yalnız görüntü aralıkları eklendi.
