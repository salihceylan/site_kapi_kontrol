# Geçiş Kontrol Genişlemesi (F10) - sunucu sözleşmesi ve tasarım notu

Bu dilim YALNIZ sunucu altyapısıdır: kartlı geçiş kayıt/iptal/listeleme uçları, cihaz yolu için saf doğrulama yardımcısı ve katalog girişleri. Donanım, firmware, MQTT köprüsü ve uygulama ekranı bu dilimde YOKTUR (sonraki adımlar aşağıda).

## Katalog (dört yeni modül, listenin SONUNDA)
| Kod | Ad | Durum | Varsayılan |
|---|---|---|---|
| `card_access` | Kartlı Geçiş | `available` | KAPALI (süper açar, yönetici modül talep eder) |
| `plate_recognition` | Plaka Tanıma | `coming_soon` | KAPALI (açılamaz, `409 MODULE_COMING_SOON`) |
| `hgs_access` | HGS Geçişi | `coming_soon` | KAPALI |
| `cctv_link` | Kamera (CCTV) Bağlantısı | `coming_soon` | KAPALI |

`card_access` kapalıyken tüm yönetim uçları `403 MODULE_DISABLED` (`module: "card_access"`); sakin listesi modülü kapalı siteyi sessizce atlar. Mevcut `door_control` (SmartKeyPass) modülüne ve `door_access_policy`ye DOKUNULMAZ; kart doğrulaması `door_control`dan bağımsız, kendi modül anahtarıyla çalışır.

## Veri modeli (migration 046, `access_cards`)
`id BIGSERIAL`, `site_code` (sites, silinince CASCADE), `person_id` (site_people, silinince CASCADE: kart KİŞİYE bağlıdır, kullanıcı hesabına değil), `card_uid TEXT` (kanonik: ayraçlar atılmış, BÜYÜK harf, `^[A-Z0-9]{4,32}$`), `label` (1-60, isteğe bağlı), `is_active` (varsayılan TRUE), `revoked_at` (`is_active = (revoked_at IS NULL)` kısıtı), `created_by` (users, silinince SET NULL), `created_at`, `updated_at`.
- Kısmi tekil indeks `(site_code, card_uid) WHERE is_active`: aynı sitede aynı UID yalnız BİR aktif kişide olur; iptal edilen UID yeniden verilebilir (sitede kart havuzu). Farklı sitelerde aynı UID serbesttir.
- İndeksler: `idx_access_cards_person (person_id)`, `idx_access_cards_site (site_code, is_active, id DESC)`.
- Şema db.js'te `ensureCardAccessSchema` ile (ensureReservationSchema'dan SONRA), migration 046 ile birebir aynı DDL (test: `card_access_schema`). Tablo FK'sız oluşturulur, her FK ayrı katalog korumalı ifadedir (R11 F1 açılış 40P01 dersi).
- UID normalizasyonu (`normalizeCardUid`): okuyucu biçimleri `04:A3 B2-C1` -> `04A3B2C1`; 4-32 dışı / ASCII dışı / alt çizgi -> geçersiz.

## Uçlar
Kimlik `Authorization: Bearer`; hata gövdesi `{ error, code, ...ek }` (Türkçe, alt çizgisiz mesaj); JSON gövde ≤4 KB (`413 BODY_TOO_LARGE`). Yönetim uçlarında sıra: biçim (400) -> yetki (403) -> site varlığı (404) -> modül (403).

| Uç | Gövde / sorgu | Yanıt |
|---|---|---|
| GET `/manager/sites/:siteCode/access-cards` | `person_id?`, `q?` (kişi adı Türkçe katlanmış / UID), `status=active\|revoked\|all` (varsayılan `active`), `limit` (1-200, varsayılan 50), `offset` | `{ items:[Card], total }` (aktifler önce, id azalan) |
| POST `.../access-cards` (201) | `person_id` (zorunlu), `card_uid` (zorunlu, normalize edilir), `label?` | `{ item:Card }` |
| POST `.../access-cards/:id/revoke` | - | `{ item:Card }` (kayıt KALIR: `is_active=false`, `revoked_at`) |
| GET `/app/access-cards` | `site_code?` | `{ items:[MyCard] }` yalnız çağıranın kişi kayıtlarına bağlı kartlar, en çok 200 |

- **Card** (yönetim; kurul dahil): `id, person_id, person_name, apartment_labels[] (kişinin güncel daireleri), card_uid (AÇIK), label, is_active, revoked_at, created_at`.
- **MyCard** (sakin): `id, site_code, site_name, masked_uid (yalnız son 4 karakter açık: "******C1D5"), label, is_active, revoked_at, created_at`. Tam UID, kişi kimliği ve başkasının kartı ASLA dönmez; iptal edilen kartlar da görünür.
- Kart tanımlama transaction'ı kilit sırası: `sites FOR KEY SHARE -> users (deleted_at IS NULL) FOR KEY SHARE -> site_people FOR KEY SHARE -> INSERT`; çakışmada (23505) `409 CARD_EXISTS`. İptal `access_cards FOR UPDATE`. 40P01'de tek sefer baştan denenir.

## Yetki matrisi
| Rol | Liste (GET) | Kart tanımla / iptal | Kendi kartları (/app) |
|---|---|---|---|
| Yönetici / Süper | evet (UID açık) | evet | (sakinse) |
| Kurul (BOARD_MEMBER) | evet, SALT OKUR | 403 `FORBIDDEN_ROLE` | (sakinse) |
| Görevli (STAFF) | 403 `FORBIDDEN_ROLE` | 403 `FORBIDDEN_ROLE` | (sakinse) |
| Sakin / ilgisiz | 403 `FORBIDDEN_ROLE` | 403 `FORBIDDEN_ROLE` | evet (maskeli) |
| Başka sitenin yöneticisi / kurulu | 403 `FORBIDDEN_SITE` | 403 `FORBIDDEN_SITE` | - |

Yetki her sorguda `site_code` ile; başka sitenin kartı ya da kişisi varlık sızdırmaz (404).

## Hata kodları
400: `INVALID_BODY`, `CARD_UID_INVALID`, `INVALID_QUERY`, `INVALID_SITE_CODE`. 401 `ACCOUNT_DELETED`. 403: `MODULE_DISABLED`, `FORBIDDEN_ROLE`, `FORBIDDEN_SITE`. 404: `SITE_NOT_FOUND`, `PERSON_NOT_FOUND` (kişi bu sitede yok ya da pasif), `CARD_NOT_FOUND`. 409: `CARD_EXISTS` (aynı sitede aktif UID), `INVALID_STATE` (zaten iptal). 413 `BODY_TOO_LARGE`. 429 genel hız sınırı: yazma 120/saat, okuma 1200/saat (kullanıcı başına; `Retry-After`).

## Audit, hesap silme, dışa aktarma
- Audit: `access_card.created`, `access_card.revoked` (`target_type: access_card`, `details: { person_id, uid_suffix }`); tam UID audit'e ve sunucu günlüğüne YAZILMAZ.
- Hesap silme: kartlar `site_people`ye bağlıdır, kullanıcıya değil; hesap silinince (kimliksizleştirme) kartlar KALIR, yönetim listesinde görünmeye devam eder. Kişi kaydı silinince kartlar silinir.
- Dışa aktarma (`/me/data-export`): `"access_cards": [{ label, masked_uid, is_active }]` (kendi kişi kayıtları üzerinden, maskeli); `excluded` notu tam UID'nin neden verilmediğini açıklar.

## Cihaz yolu (bu dilimde: yalnız saf yardımcı)
`card_access_verify.js` -> `verifyCardForDoor({ siteCode, cardUid, now, db }) -> { ok, reason, person_id }`:
- Salt okunur iki sorgu (modül satırı + kart/kişi); kilit almaz, yazmaz, MQTT'ye ve `door_access_policy`ye BAĞLI DEĞİLDİR.
- Karar sırası: modül kapalı / satır yok -> `module_disabled`; UID geçersiz ya da kart yok -> `card_unknown`; kart iptal -> `card_revoked`; kişi pasif ya da o sitede güncel `apartment_residencies` (is_current) veya aktif `apartment_memberships` yok -> `person_inactive`; aksi halde `ok: true` + `person_id`. `now` ileride geçerlilik aralığı için ayrılmıştır (şimdilik zaman bağımsız).

### Protokol önerisi (SONRAKİ adım: firmware + köprü; bu dilimde KOD YOK)
- Okuyucu (RFID/NFC, Wiegand ya da UART) kart UID'sini okur, mevcut `qr_verify` akışının aynısıyla ister: `device/<device_uid>/card_verify` konusuna `{ "card_uid": "04A3B2C1", "request_id": 17 }` (QoS 1, retain YOK; `request_id` negatif olmayan güvenli tamsayı, yanıta aynen geri konur).
- Sunucu `verifyCardForDoor` ile karar verir ve `device/<device_uid>/card_result` konusuna `qr_result` ile AYNI biçimde yanıt yazar: `{ "allowed": true|false, "reason": "OK"|"MODULE_DISABLED"|"CARD_UNKNOWN"|"CARD_REVOKED"|"PERSON_INACTIVE"|"ERROR", "timestamp": ISO, "request_id": 17 }`. Cihaz `allowed` değilse röleyi AÇMAZ; `request_id` eşleşmeyen yanıtı atar; yanıt 2 sn gelmezse geçişi reddeder (çevrimdışı kart listesi bu dilimde yoktur; ileride `allowed` kartların UID özetini cihaza senkronlamak ayrı bir iştir).
- Cihaz kimlikleri DEĞİŞMEZ: aynı `device_uid`, aynı MQTT kimlik bilgileri, aynı `X-AHBU-*` başlıkları (ör. `X-AHBU-Device-UID`); ACL'ye yalnız `device/<uid>/card_verify` (yazma) ve `device/<uid>/card_result` (okuma) eklenir (`mqtt_acl_sync.js`, QR ile aynı desen).
- Köprüde site çözümü QR ile aynıdır (cihaz -> bağlı kapı -> site); kapı günlüğüne `card` türüyle giriş yazılır (`door_logs`, `person_id` ile; tam UID günlüğe yazılmaz, yalnız son 4). Kapının `door_access_policy` kuralları (saat, misafir vb.) AYNEN uygulanır; kart yalnız kimliklendirme yöntemidir.
- Firmware (`cihaz_kontrol`): okuyucu sürücüsü, UID normalizasyonu (büyük harf hex, ayraçsız), `card_verify` yayını, `card_result` beklemesi ve LED/buzzer geri bildirimi SONRAKİ dilimdir.

## Plaka tanıma, HGS, CCTV için tasarım notu (kod YOK; katalogda `coming_soon`)
Ortak ilke: bu üç özellik dış sistemlerden (plaka kamerası / OCR servisi, HGS sağlayıcısı, NVR/VMS) olay alır; sunucu bu olayları site bazında doğrular ve mevcut kapı/geçiş kayıtlarına bağlar. Kendi görüntü işleme, kendi HGS okuma ya da video saklama YAPILMAZ.
- **Site başına entegrasyon anahtarı**: `site_integrations (site_code, provider: plate|hgs|cctv, key_hash, enabled, created_by, rotated_at)`. Anahtar yalnız oluşturulurken bir kez gösterilir, hash saklanır; yönetici döndürebilir, süper kapatabilir. Anahtar sitenin modülü açıkken geçerlidir (`MODULE_DISABLED` ile aynı kapı).
- **Webhook ucu (öneri)**: `POST /integrations/:provider/events` başlıkları `X-AHBU-Integration-Key` (site anahtarı) + `X-AHBU-Signature` (gövdenin HMAC-SHA256'sı, anahtarla) + `X-AHBU-Event-Id` (idempotans, sağlayıcı olay kimliği; tekrar 200 `replayed:true`). Gövde sağlayıcıdan bağımsız normalize edilir: `{ occurred_at, gate_id?, plate? | tag_id?, camera_id?, clip_ref?, raw_ref? }`. Hız sınırı site başına (ör. 600/dakika), gövde ≤16 KB, saat sapması ±5 dk.
- **Plaka tanıma**: `plate_registrations (site_code, person_id, plate (normalizePlate ile kanonik), apartment_id?, is_active)`; webhook plakayı eşler, `verifyPlateForGate` kart doğrulamasıyla aynı karar şekline (`ok, reason, person_id`) döner; eşleşirse kapı komutu mevcut `door_control` yolundan verilir. Kişi listesi ve sakin görünümü kart modülüyle aynı maskeleme ilkesine (`masked_plate`) uyar.
- **HGS geçişi**: sağlayıcı sözleşmesi site başına; `hgs_tags (site_code, person_id, tag_id_hash, is_active)` — HGS etiketi kimliği HAM saklanmaz (hash + son 4). Geçiş olayı yalnız kayıt ve raporlama içindir (bariyer komutu sağlayıcıda kalır).
- **Kamera (CCTV) bağlantısı**: `cctv_links (site_code, door_id, camera_id, clip_url_template, provider)`; kapı olayına (`door_logs`) zaman penceresiyle (`occurred_at ± 10 sn`) klip bağlantısı eklenir (`clip_ref`); video sunucuda SAKLANMAZ, yalnız imzalı/kısa ömürlü bağlantı. KVKK: klip erişimi yalnız yönetici/süper, audit'li.
- Hepsi için ortak: hata gövdesi `{ error, code }`, modül kapalıyken `403 MODULE_DISABLED`, olaylar `audit_log`'a yalnız kimlik/son 4 ile yazılır, hesap silmede kişiye bağlı kayıtlar (plaka/etiket) kişi kaydıyla yaşar.

## Açık işler (bu dilimin dışı)
- Uygulama (Flutter) ekranı: yönetici kart listesi/tanımlama/iptal, sakin "Kartlarım" (maskeli) — yok.
- Firmware okuyucu + `card_verify/card_result` köprüsü + ACL girişleri; çevrimdışı kart listesi kararı.
- Deneme listesi F10 maddeleri ve gerçek PostgreSQL QA bölümü (`QA_ONLY=card_access`) koşusu.
