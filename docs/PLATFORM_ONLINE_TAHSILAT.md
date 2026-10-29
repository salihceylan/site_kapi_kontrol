# Online Tahsilat ve Banka Bağlantısı (altyapı)

Durum (2026-10-29): bağlantı ekranları ve sunucu altyapısı hazır; **hiçbir ödeme kuruluşu sürücüsü etkin değil, ödeme alınmaz.** Sahte "ödendi" akışı yoktur ve eklenmemelidir.

## Parçalar
- Tablo `payment_provider_connections` (migration 116, site başına tek satır): sağlayıcı, mod (`test`/`live`), gizli olmayan alanlar (`public_config`), şifreli sırlar (`secrets_enc`), son sınama. `payment_provider_settings` (komisyon notu, 065/083) DEĞİŞMEDİ.
- Sırlar AES-256-GCM ile şifrelenir (anahtar: sunucu `.env` `PAYMENT_SECRET_KEY`, en az 32 karakter; şifreli değer site koduna bağlanır). Anahtar yoksa GET/PUT/POST uçları 503 `PAYMENT_NOT_CONFIGURED` döner (DELETE anahtarsız da çalışır). Sırlar API yanıtında, günlükte ve denetim kaydında yoktur; yanıt yalnız "kayıtlı mı" bilgisini taşır.
- Uçlar (yönetici/süper yazar, kurul okur; yazmalar `audit_log`a işlenir: `finance.online_collection_saved|tested|removed`): `GET|PUT|DELETE /manager/sites/:siteCode/payment-provider`, `POST .../payment-provider/test`. Kod: `server/src/modules/payment_connection_*.js`.
- Sakin: `GET /app/my-finance/payment-info` her kalemde `online_payment_available` taşır; yalnız **canlı mod + son sınama `ok` + sürücü `enabled`** iken true. Uygulamada `PayContent` bu bayrak true değilse Online Öde için hiçbir şey çizmez.
- Uygulama: Finans > **Online Tahsilat** (`finance_online_collection_dialog.dart`); alan formu sunucudaki sağlayıcı tanımından üretilir.

## Sürücü ekleme rehberi (sözleşme gelince)
`server/src/modules/payment_providers.js` içindeki `PROVIDERS` kaydına bir sürücü nesnesi eklenir (yeni migration gerekmez, `provider` sütunu serbest metindir):

```js
{ code, name, enabled, fields: [{ key, label, secret, required, min, max, pattern, hint }],
  validate?(values, mode) -> string[],              // ek biçim denetimi (ör. canlıda sandbox anahtarı yasak)
  testConnection?({ values, mode, siteCode }) -> { ok, message } }   // GERÇEK sağlayıcı çağrısı
```
- `enabled` yalnız gerçek sürücü yazılıp sağlayıcı test ortamında denendikten sonra `true` yapılır. `false` iken sınama "sürücü etkin değil" der, sakine Online Öde çıkmaz.
- `secret:true` alanlar şifreli saklanır ve forma geri yazılmaz. Alan listesi sağlayıcının sözleşme belgesine göre kesinleştirilmelidir (iyzico: API anahtarı + gizli anahtar; diğer sağlayıcılar için ilgili belgeye bakılır).
- `testConnection` başarıyı yalnız sağlayıcı doğrularsa `ok:true` döndürür; başarı uydurulmaz.
- Ödeme başlatma (checkout oturumu) ve sonuç geri çağrısı sürücüyle birlikte yazılır: "ödendi" kaydı YALNIZ imzası doğrulanmış sağlayıcı geri çağrısından ve mevcut tahsilat/makbuz yolu üzerinden (tek kaynaklı defter) oluşturulur; istemciden gelen hiçbir "ödedim" bildirimi tahsilat sayılmaz. `PayContent.onOnlinePay` geri çağrısı bu akışa bağlanır.

## Bilinçli bırakılanlar
Ödeme başlatma ucu, sağlayıcı geri çağrısı ve ikinci/üçüncü sağlayıcı alan şemaları (paratika/param/PayTR) sözleşme ve sürücüyle birlikte eklenir.
