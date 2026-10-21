# Kamera (CCTV) Bağlantısı (`cctv_link`)

Migration 072 (`server/migrations/072_cctv_link.sql` = `server/src/modules/cctv_schema.js`, ekleyici ve idempotent). Modül: `cctv_link` (Kamera (CCTV) Bağlantısı); `available`, çekirdek değil, varsayılan KAPALI (süper açar, yönetici modül talep eder).

## Tasarım (kameralar sitenin yerel ağındadır)
VPS kameralara ulaşamaz ve video SAKLANMAZ. Sunucu yalnız kamera kaydını, kayıt sistemi (NVR) **bağlantı şablonunu** ve kapı eşlemesini tutar; olay anında şablon doldurulup kullanıcının cihazında açılır (kullanıcı site ağındaysa NVR arayüzü oynatır). Anlık görüntü yalnız kamera/NVR herkese açık bir https adresinden görüntü veriyorsa sunucudan çekilebilir; olmazsa "Bu kameraya sunucudan ulaşılamıyor; kayıt bağlantısını kullanın."

## Tablolar
- `cctv_cameras`: ad (1-80), konum (≤160), tür (`ip_camera` | `nvr_channel`), kanal (≤40, harf/rakam/`.`/`-`/`_`), `clip_url_template` (≤1000), `snapshot_url` (≤500), `username`, `password_enc` (AES-256-GCM, `device_integrations_service.encryptSecret`; anahtar `CAMERA_SECRET_KEY`, yoksa `JWT_SECRET`), `is_active`. En az biri dolu olmalı: şablon ya da anlık görüntü adresi. Parola için kullanıcı adı gerekir.
- `cctv_camera_doors (camera_id, door_id, site_code)`: kamera - kapı eşlemesi (bir kamera ≤20 kapı). Kapı aynı sitede olmalıdır.
- Kapı günlüğü (`door_access_logs`) SALT OKUNUR kullanılır; kapı açma, MQTT, BLE, firmware ve kapı servisine dokunulmaz. Site silinince her şey CASCADE; kamera silinirse eşlemeleri de gider (silme gerçek silmedir; denetim kaydı kalır).

## Uçlar (hepsi `/manager/sites/:siteCode/cctv` altında)
| Uç | Açıklama |
|---|---|
| `GET meta`, `GET doors` | türler, yer tutucular, KVKK notu, sınırlar; eşlenebilir aktif kapılar |
| `GET cameras` | liste; kimlik bilgisi ASLA dönmez (`has_credentials`); `clip_url_template` / `snapshot_url` yalnız yazma yetkisinde |
| `POST cameras` (201), `PATCH cameras/:id`, `DELETE cameras/:id` | yalnız site yöneticisi ve süper; PATCH'te `clear_credentials: true` kimlik bilgisini siler |
| `GET cameras/:id/snapshot` | `image/jpeg` ya da `image/png` (önbelleğe alınmaz) ya da `424 SNAPSHOT_UNAVAILABLE`; her deneme denetim kaydı |
| `GET events?limit&door_id` | son kapı olayları (≤100) + olayın kapısına eşlenmiş AKTİF kameralar; kişi adı / daire yalnız yazma yetkisinde |
| `POST clip-link` `{ log_id, camera_id }` | kayıt bağlantısı `{ url, start, end }`; kamera olayın kapısına eşli ve aktif olmalı; denetim kaydı |

Yetki: site yöneticisi + süper yazar; kurul üyesi ve görevli görüntüler (liste, olaylar, anlık görüntü, kayıt bağlantısı); sakin ve ilgisiz `403 FORBIDDEN_ROLE`; başka site `403 FORBIDDEN_SITE`; modül kapalıyken `403 MODULE_DISABLED`. Sakine açık uç yoktur. Hız sınırı: okuma 600/saat/kullanıcı, yazma 120, görüntü ve kayıt bağlantısı 90.

## Bağlantı şablonu
`https://` ile başlar, kullanıcı bilgisi içermez, ana bilgisayar kısmında yer tutucu olamaz. Yer tutucular: `{start}` `{end}` (ISO 8601 UTC, saniye çözünürlüğü), `{start_unix}` `{end_unix}` (epoch saniye), `{channel}`, `{camera}` (kamera adı). Değerler adres kodlamasından geçer. Pencere: olay zamanı -30 sn / +30 sn.

## SSRF koruması (anlık görüntü)
Yalnız https; `user:pass@` yok; `localhost`, tek etiketli ve yerel sonekli (`.local`, `.internal` ...) adlar ve özel / yerel / link-local / paylaşımlı / yayın / eşlenmiş IP'ler engel; ad çözümlemesinden SONRA tüm adresler doğrulanır (biri bile özelse engel) ve bağlantı doğrulanan adrese sabitlenir; yönlendirme izlenmez; toplam 5 sn; gövde ≤2 MB; yalnız `image/jpeg` | `image/png` ve sihirli baytlar da doğrulanır. Kayıt sırasında yerel adres `400 INVALID_FIELD` ile reddedilir. Kimlik bilgisi varsa yalnız bu adrese HTTP Basic gönderilir.

## Denetim kaydı (`audit_log`)
`cctv.camera_created` / `camera_updated` / `camera_deleted`, `cctv.snapshot_viewed` (`delivered`, hata nedeni), `cctv.clip_opened` (`log_id`). Ayrıntılara adres, şablon, kullanıcı adı ve parola YAZILMAZ.

## KVKK
Kamera görüntüsü kişisel veridir; aydınlatma ve saklama sorumluluğu site yönetimindedir (ekranda bilgi notu). [AVUKAT DOĞRULASIN] Aydınlatma metni, saklama süresi ve görüntüye erişim yetkisi hukuk onayına sunulacaktır.

## Sınırlar
- Kayıt bağlantısı yalnız https; yalnız http sunan eski NVR'lar için sitede https geçidi gerekir.
- Anlık görüntü yalnız herkese açık https adresinden ve HTTP Basic ile çekilir (Digest, RTSP, ONVIF yok); yerel ağdaki kameralar için yalnız kayıt bağlantısı kullanılır.
- Süper kullanıcının uygulama menüsünde kamera ekranı yoktur (diğer site modülleriyle aynı); uçlar süper için açıktır.
- Sayfalama yok (son 100 olay); kamera sınırı site başına 50.
