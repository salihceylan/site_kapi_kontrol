# Mesaj sürücüleri: site başına SMS ve WhatsApp bağlantısı

Yönetici, Duyurular ekranının altındaki "SMS ve WhatsApp bağlantısı" kartından kendi sağlayıcı hesabını bağlar. Sunucu tarafı: `server/src/modules/messaging_*.js`, tablo `site_messaging_connections` (migration 117).

## Uçlar
`/manager/sites/:siteCode/messaging` (GET durum), `/sms` (PUT kaydet, DELETE `?confirm=true`), `/sms/test` (POST), `/whatsapp` (PUT, DELETE), `/whatsapp/test` (POST).
Yazma yalnız yönetici/süper; okuma ayrıca yönetim kurulu üyesi (`people_access`). Her yazma/sınama `audit_log`'a düşer (`messaging.*`).

## Sırlar
Kullanıcı kodu, şifre ve erişim belirteci AES-256-GCM ile şifreli saklanır; anahtar `.env` içindeki `MESSAGING_SECRET_KEY` (en az 32 karakter, değer depoya yazılmaz). Anahtar yoksa kayıt 503 `MESSAGING_NOT_CONFIGURED` verir. Yanıtlarda yalnız maskeli ipucu döner. Telefon numarası ve mesaj metni saklanmaz ya da günlüğe yazılmaz.

## Gönderim önceliği
`getSiteSmsProvider(siteCode)`: site ayarı varsa o, yoksa global `.env` (`SMS_PROVIDER` ...). Site ayarı var ama çözülemiyorsa (anahtar eksik/bozuk) `null` döner: başka hesaptan ücretlendirmemek için gönderim kapalı kalır. Mevcut telefonla giriş kodu (`sms_login`) site bağlamı olmadığı için global kalır; site bağlamlı yeni göndericiler bu işlevi çağırmalıdır.

## Yeni SMS sağlayıcısı eklemek
1. `messaging_common.js` içindeki `SMS_DRIVERS` nesnesine bir girdi ekleyin: `id`, `label`, `secretFields`, `configFields`, `validate(input)`, `createAdapter({config, secrets}, fetchImpl)` (sözleşme: `{ name, send(phone, text) }`, bkz. `sms_provider.js`) ve `check({config, secrets}, fetchImpl)`.
2. `check` yalnız kimlik/bakiye sorgusu yapmalı; GERÇEK SMS göndermemeli (ücret riski).
3. Ekran sürücü listesini sunucudan okur; şimdilik ilk sürücüyü gösterir, ikinci sürücü gelince seçici eklenir.

## WhatsApp (Meta Cloud API)
`WHATSAPP_DRIVER` bir iskelettir (`active: false`): alanlar (`phone_number_id`, `access_token`, `business_name`) doğrulanıp kaydedilir, "Sına" yalnız alan doğrulaması yapar ve `VALIDATION_ONLY` döner. Sahte bağlantı/gönderim yoktur. Etkinleştirmek için: gerçek `check` (Graph API `GET /{phone_number_id}`) ve gönderici eklenir, `active: true` yapılır; bildirim kanalı tercihinde WhatsApp seçeneği ancak o zaman gösterilir (`GET .../messaging` yanıtındaki `whatsapp.driver.active`).
