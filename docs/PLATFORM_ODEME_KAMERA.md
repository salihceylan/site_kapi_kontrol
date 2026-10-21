# Kart Ödemesi Arayüzü ve Kamera / Plaka Bağdaştırıcıları (F6 + T8)

Migration 065 (`server/migrations/065_device_integrations.sql` = `server/src/modules/device_integrations_schema.js`, ekleyici ve idempotent).
Modüller: `card_payments` (Kart Ödemesi) ve `plate_cameras` (Kamera ve Plaka); ikisi de varsayılan KAPALI, çekirdek değil.

## Kart ödemesi (yalnız arayüz)
- Sağlayıcılar kodda sabit: `iyzico`, `paytr`. İkisi de boş adaptör, `status: 'soon'`, `enabled: false`; tahsilat YAPILMAZ, `finance_parties.postPayment` çağrılmaz.
- Tablo `payment_provider_settings (site_code, provider, commission_info, ...)`; tek yazılan alan komisyon bilgi notu (en çok 300 karakter).
- Kural metni: komisyon ödemeyi yapana (ev sahibi / kiracı) yansıtılır.
- Uçlar: `GET /manager/sites/:siteCode/card-payments`, `PUT .../card-payments/:provider` ({ commission_info }).

## Kamera / plaka
- `camera_devices`: marka (`hikvision` | `tiandy` | `onvif`), ad, IP/adres, port, kullanıcı adı, parola (AES-256-GCM, anahtar `CAMERA_SECRET_KEY`, yoksa `JWT_SECRET`; yanıtlarda ASLA dönmez, `has_password` döner), `token_hash` (SHA-256).
- `plate_events`: site, kamera, plaka (normalize), `matched`, `vehicle_id`, `seen_at`.
- Uçlar (yönetici/süper yazar, kurul salt okur, diğerleri 403, modül kapalıysa 403 `MODULE_DISABLED`):
  `GET|POST /manager/sites/:siteCode/cameras`, `POST .../cameras/:id/rotate-token`, `POST .../cameras/:id/deactivate`, `GET .../plate-events`.
- Olay ucu (oturumsuz, belirteçli): `POST /camera-events/plate` gövde `{ plate, seen_at? }`, `Authorization: Bearer <id>.<gizli>` ya da `X-Camera-Token`. Belirteç kayıtta/yenilemede bir kez gösterilir. Plaka sitenin aktif `vehicles` listesiyle karşılaştırılıp KAYDEDİLİR; kapı açma / geçiş YOKTUR. Pasif kamera veya kapalı modül reddedilir.
- Kamera ürün yazılımını (Hikvision ISAPI, Tiandy, ONVIF) çağırmak ya da çekmek bu sürümde YOKTUR; kamera/NVR olayı HTTP ile belirtece gönderecek şekilde ayarlanır.

## Arayüz
Menü "Ödeme ve Kamera" (Site hizmetleri; modülü açık sitenin yöneticisi/kurulu). Ödeme kartında sağlayıcılar "Yakında…"; kamera kartında cihaz ekleme, belirteç, plaka kayıtları; "Plakayla otomatik kapı açma" "Yakında…".
