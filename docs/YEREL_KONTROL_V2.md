# Yerel kontrol protokolü v2 (challenge'a bağlı HMAC)

Cihaz (ESP32-C3 / ESP32-WROOM), mobil uygulama ve cihaz simülatörü bu sözleşmeyi birlikte uygular. Cihaz çekirdeği: `cihaz_kontrol/include/yerel_kontrol_cekirdek.h` (Arduino'dan bağımsız; ana makinede test edilir), entegrasyon: `cihaz_kontrol/include/yerel_kapi_kontrol.h`. Uygulama: `lib/services/local_door_service.dart`.

**Amaç:** v1'de yerel UDP/HTTP açma sabit `token`'ı düz metin taşıyordu; ağı dinleyen veya sahte beacon yayan biri token'ı çalıp kalıcı açma yetkisi kazanabilir, yakalanan paket yeniden oynatılabilirdi. v2'de **token ağa asla çıkmaz**; her açma isteği, cihazın o an duyurduğu tek kullanımlık `ch` (challenge) değerine bağlı HMAC-SHA256 imzası taşır. Sunucu, MQTT ve token üretimi/dağıtımı DEĞİŞMEDİ (token `local_control_config` ile cihaza, `/app/my-doors` ile uygulamaya gelir; üyelik/izin kalkınca döndürülür).

## Mesajlar (UDP, port 8765, JSON, < 512 B)

- **Beacon** (cihaz → alt ağ broadcast, ~5 sn): `{"device_uid","ip","port":8765,"rssi","hw":"c3|wroom","ch":"<16 hex>"}`
- **Discover** isteği `{"action":"discover","target_uid":"<UID>|*|boş","nonce":"<≤32>"}` → `{"ok":true,"device_uid","ip","port","ch":"<16 hex>","local_control_available":true|false[,"nonce"]}`
- **Açma/pulse** isteği (uygulama → cihaz, unicast):
  `{"action":"open"|"pulse","target_uid":"<UID>","device_uid":"<UID>","ch":"<16 hex>","sig":"<64 hex>","nonce"?}`
  `sig = lowerhex( HMAC-SHA256( key = UTF-8(token), msg = UTF-8( action + "|" + UID_BÜYÜK_HARF + "|" + ch ) ) )`
  Pakette `token` alanı **yoktur**.
- **Yanıtlar** (hepsi `device_uid` ve varsa `nonce` yankılar):
  - Başarı: `{"ok":true,"message":"yerel_kapi_acma_komutu_alindi"}`
  - Yinelenen paket (aynı `ch`+`sig`, son 3 sn içinde kabul edilmiş): `{"ok":true,"duplicate":true}` — röle tekrar tetiklenmez
  - `ch` yok/eski/geçersiz: `{"ok":false,"error":"challenge","ch":"<güncel>"}` — istemci tek kez güncel `ch` ile yeniden dener
  - İmza yanlış: `{"ok":false,"error":"unauthorized","local_control_available":true}`
  - Cihazda token yok: `{"ok":false,"error":"unauthorized","local_control_available":false}`
  - Röle meşgul: `{"ok":false,"error":"role_mesgul"}` (challenge **tüketilmez**)
- **HTTP:** `POST /ahbu/open` kaldırıldı (404 `route_bulunamadi`); `GET /ahbu/status` kalır ve sır içermez.

## Cihaz davranışı

- Güncel (`ch`) ve bir önceki challenge: 8 rastgele bayt (`esp_random()`) → 16 küçük hex. Her 10 sn'de döner; başarılı açmadan sonra ikisi de yeniden üretilir. Zamanlayıcılar `{başlangıç, süre}` + işaretsiz fark kalıbıyla yazılır (millis taşması/işaret taşması yok).
- Karar sırası: token yok → `unauthorized` · yinelenen → `duplicate` · `ch` bilinmiyor → `challenge` · imza (sabit zamanlı karşılaştırma) yanlış → `unauthorized` · röle meşgul → `role_mesgul` · başarı → yanıt + yan etkiler + challenge yenileme + son-kabul kaydı.
- Açılışta HMAC bilinen-cevap öz-testi: uyuşmazsa yerel açma KAPALI kalır (fail-closed) ve `local_control_selftest_failed` olayı yayınlanır.
- Seriye token/imza/challenge yazılmaz.

## Uygulama davranışı

- Beacon/discover'dan `ch` önbelleğe alınır (12 sn'den eskiyse boş gönderilir; cihaz güncel değeri `challenge` hatasıyla döndürür → TEK yeniden deneme, her denemede 150 ms bekleme penceresi). Kesin ret (`unauthorized`, `role_mesgul`) yeniden denenmez; bulut yoluna düşülür.
- Hedef adres yalnızca özel ağ (RFC1918, link-local) olabilir; token yoksa yerel paket hiç gönderilmez.
- Günlüklere token/imza/challenge yazılmaz.

## Bilinen-cevap test vektörü (cihaz, uygulama ve simülatör testleri aynı değerleri doğrular)

- token = `AbCdEfGhIjKlMnOpQrStUvWxYz0123456789_-AbCdE` (43 karakter; GERÇEK token değildir), UID = `240AC4E2E001`, ch = `0123456789abcdef`
- `open|240AC4E2E001|0123456789abcdef` → `92f22b8a741bcc00b1aec15ff573b6ee4d48edea1bba959807489eb3c6fed5f4`
- `pulse|240AC4E2E001|0123456789abcdef` → `3bb6390fa9c7a2135232000306e9a6293e38fabd736edcf7400ecd55c597b881`

## Sınırlar

Trafik LAN'da şifreli değildir (imza token'ı gizler ama istek/yanıt içeriği okunabilir); aynı LAN'daki saldırgan bir isteği yalnızca o isteğin kendi `ch`'si ve 3 sn'lik pencere içinde iletebilir. Sahada cihaz doğrulaması için `SAHA_KONTROL_LISTESI.md` bölüm 51 ve F2A1 adımlarına bakın.
