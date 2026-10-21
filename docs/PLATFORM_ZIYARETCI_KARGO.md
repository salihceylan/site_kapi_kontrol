# Ziyaretçi ve Kargo (F11.03) - sunucu sözleşmesi

Modül kodu `visitor_log` (katalogda `available`, `core:false`, varsayılan KAPALI; süper açar, yönetici modül talep eder). Kapalıyken tüm uçlar `403 MODULE_DISABLED` (`module: "visitor_log"`; sakin listesi `site_code`suz ise o siteyi atlar). Kapıcı / güvenlik görevlisi (STAFF) gelen ziyaretçiyi ve kargoyu kaydeder; sakin kendi dairesine gelenleri uygulama içinde görür. E-posta / telefon bildirimi bu sürümde YOK ("Yakında"): bildirim yalnız uygulama içi `unread` sayacı ve listedir. Hata gövdesi her yerde `{ error, code, ...ek }`; kimlik `Authorization: Bearer`.

## Veri modeli (migration 045)
- `visitor_entries`: id, site_code, kind (`visitor|cargo`), apartment_id? (daire silinince NULL), visitor_name (1-120; kargoda kargo firması / gönderen), company? (≤120), note? (≤500), status, arrived_at (varsayılan NOW), completed_at?, recorded_by? (kaydeden görevli / yönetici), completed_by? (sonlandıran), resident_seen_at? (sakin gördü), created_at, updated_at.
- İndeksler: `(site_code, status, arrived_at DESC)`, `(apartment_id, arrived_at DESC)`.
- Durumlar: `bekliyor | iceride | teslim_edildi | ayrildi | iptal`. DB kısıtı: sonlanmış durumlarda (`teslim_edildi/ayrildi/iptal`) `completed_at` dolu, açık durumlarda boş.
- Kayıt daire olmadan da açılabilir (ortak alan ziyaretçisi, yönetim ofisine gelen kargo); dairesiz kayıt hiçbir sakine gösterilmez.
- Site silinince kayıtlar silinir (CASCADE). Kullanıcı silinince kayıt KALIR; `recorded_by` / `completed_by` FK ile NULL olur ya da tombstone'u gösterir, ad "Silinmiş Kullanıcı" görünür.

## Durum kuralları (sunucuda hesaplanır / doğrulanır)
- Başlangıç durumu istemciden ALINMAZ: `cargo -> bekliyor`, `visitor -> iceride`.
- Geçişler: `bekliyor -> teslim_edildi | iptal`; `iceride -> ayrildi | iptal`; `teslim_edildi`, `ayrildi`, `iptal` SONDUR (geçiş isteği `409 INVALID_TRANSITION { from, to }`). Aynı duruma istek değişiklik yapmaz (200, audit yazılmaz).
- Sonlanırken `completed_at = NOW()` ve `completed_by = çağıran` yazılır. Not (`note`) her durumda düzenlenebilir; `null` / boş not siler.
- `next_statuses` yönetim yanıtında hazır gelir (sakin görünümünde boş).

## Uçlar
Yönetim tabanı: `/manager/sites/:siteCode/visitor-entries`. DELETE YOK (kayıt `iptal` ile kapatılır). Gövde JSON (≤8 KB; üstü `413 BODY_TOO_LARGE`).

| Uç | Gövde / sorgu | Yanıt |
|---|---|---|
| GET `.../visitor-entries` | `kind?`, `status?` (tek durum ya da `open` / `closed`), `apartment_id?`, `q?` (ad / firma / daire etiketi "Blok - Daire"; Türkçe ve büyük-küçük harf duyarsız, `total` aynı süzgeçle), `from?`, `to?` (`YYYY-MM-DD` ya da ISO), `limit` (50, en çok 200), `offset` (0) | `{ items:[Entry], total }` (arrived_at azalan) |
| POST `.../visitor-entries` (201) | `kind, apartment_id?, visitor_name, company?, note?` | `Entry` (durum türe göre hesaplanır) |
| PATCH `.../visitor-entries/:id` | en az biri: `status?, note?` | `Entry` |
| GET `.../visitor-entries/apartments` (kayıt formunun daire seçicisi; okuyan herkes, görevli dahil) | `q?` (yalnız "Blok - Daire" etiketinde), `limit` (50, en çok 200), `offset` (0) | `{ items:[{ id, apartment_label, block_name, label }], total }` (blok, daire sırası). YALNIZ kimlik + etiket: malik / kiracı / sakin adı ne yanıtta ne aramada vardır (Kişiler > Daireler ucu görevliye 403'tür) |
| GET `/app/visitor-entries` | `site_code?`, `limit` (50, en çok 200), `before_id?` imleci | `{ items:[Entry + site_code, site_name, unread], next_before_id }` |
| GET `/app/visitor-entries/summary` | `site_code?` | `{ unread }` (kendi dairelerinde `resident_seen_at` NULL olan kayıt sayısı) |
| POST `/app/visitor-entries/:id/seen` | - | `{ ok:true }` (idempotent; ikinci çağrı yazmaz) |

**Entry** (yönetim): `id, kind, apartment_id, apartment_label, block_name, visitor_name, company, note, status, next_statuses[], arrived_at, completed_at, recorded_by_name, completed_by_name, resident_seen_at`. `apartment_id` verildiyse o siteye ait olmalıdır (`404 APARTMENT_NOT_FOUND`).
**Entry** (sakin): aynı alanlar ARTI `site_code, site_name, unread`; `recorded_by_name` / `completed_by_name` sakine GÖSTERİLMEZ, `next_statuses` boştur. Sakin yalnız KENDİ dairelerine (aktif `apartment_memberships` ya da güncel `apartment_residencies`) ait kayıtları görür; başkasının dairesi / dairesiz kayıt / yok `404 VISITOR_ENTRY_NOT_FOUND` (varlık sızmaz).
- **Zaman sınırı (önceki sakin):** sakin yalnız o daireye bağlandığı andan SONRA gelen kayıtları görür (`arrived_at >= since`; üyelikte `apartment_memberships.created_at`, ilişkide `COALESCE(move_in_date, created_at)`; iki yol birden varsa erken olanı). Önceki sakinin kayıtları yeni sakinin listesine, `unread` sayısına girmez; `seen` 404 döner.
- **Malik / kiracı:** malik (`owner`) ilişkisi dairede GÜNCEL kiracı (`tenant`) varken o daireyi vermez (kiracının ziyaretçi ve kargosu malike gösterilmez). Kiracı yokken malik, son biten kiracılığın kapanışından (`updated_at` ile `move_out_date` ertesi günün geç olanı) SONRAKİ kayıtları görür. `tenant`, `resident` ve `family_member` ilişkileri kendi başlangıçlarından itibaren görür.
- Erişim üyeliği (`apartment_memberships`, kapı yetkisi) hane üyeliği sayılır; ilişki türüne bakılmaz. Bilinen sınır: aynı daireye yeniden etkinleştirilen üyelik ilk `created_at`ini korur (taşınıp aynı daireye geri dönen hesapta aradaki dönem görünür).

## Yetki matrisi
| Rol | GET liste | POST kayıt | PATCH durum / not | /app uçları |
|---|---|---|---|---|
| Süper / Yönetici | evet | evet | evet | (sakinse) kendi dairesi |
| Görevli (STAFF: kapıcı / güvenlik) | evet | evet | evet | (sakinse) kendi dairesi |
| Kurul (BOARD_MEMBER) | evet (salt okur) | 403 FORBIDDEN_ROLE | 403 FORBIDDEN_ROLE | (sakinse) kendi dairesi |
| Sakin / ilgisiz | 403 FORBIDDEN_ROLE | 403 | 403 | kendi dairesi |
| Başka sitenin yöneticisi / kurulu | 403 FORBIDDEN_SITE | 403 FORBIDDEN_SITE | 403 FORBIDDEN_SITE | - |

Denetim sırası: biçim (400 `INVALID_SITE_CODE`) -> yetki (403) -> site varlığı (404 `SITE_NOT_FOUND`) -> modül (403 `MODULE_DISABLED`). Yazma işlemleri `sites FOR KEY SHARE -> users FOR KEY SHARE (silinmiş hesap yazamaz: 401 ACCOUNT_DELETED) -> visitor_entries FOR UPDATE` kilit sırasıyla, her sorguda `site_code` ile (IDOR yok). STAFF yetkisi `work_tracking_access` kalıbıyla `site_memberships(role='STAFF', is_active)` üzerinden kurulur.

## Hata kodları
400: `INVALID_BODY` (alan Türkçe etiketle), `INVALID_QUERY`, `INVALID_SITE_CODE`. 401 `ACCOUNT_DELETED`. 403: `MODULE_DISABLED`, `FORBIDDEN_ROLE`, `FORBIDDEN_SITE`. 404: `VISITOR_ENTRY_NOT_FOUND`, `APARTMENT_NOT_FOUND`, `SITE_NOT_FOUND`. 409: `INVALID_TRANSITION` (`{ from, to }`). 413 `BODY_TOO_LARGE`. 429: genel hız sınırı (`Retry-After`; yazma 240/saat kullanıcı başına — görevli çok kayıt girer; okuma 1200/saat).

## Audit ve gizlilik
Audit eylemleri: `visitor_entry.created` (details: kind, apartment_id, status) ve `visitor_entry.updated` (details: `from`, `to` durum geçişi; `note_changed`). Ziyaretçi adı, firma ve not audit `details` alanına ve günlüğe YAZILMAZ.

## Hesap silme ve dışa aktarma
- Görevli / yönetici hesabı silinince girdiği ya da sonlandırdığı kayıtlar SİLİNMEZ (kayıtlar siteye aittir: kimin ne zaman geldiği sitenin güvenlik kaydıdır); `recorded_by` / `completed_by` FK ile NULL olur ya da tombstone kalır, ad "Silinmiş Kullanıcı" görünür. Silme önizlemesinde `will_keep` listesine bu sayıyla bir not eklenir.
- Kişisel veri dışa aktarmasına (`/me/data-export`) bu modülden bir bölüm EKLENMEZ: sakin bu modülde kayıt üretmez (kaydı görevli girer); kayıttaki ziyaretçi adı / kargo firması sakinin kişisel verisi değil, sitenin ziyaret kaydıdır; `resident_seen_at` yalnız bir okundu işaretidir. Görevlinin kaydettiği satırlar da görevlinin değil sitenin verisidir.

## Sakin bildirimi
Uygulama içi: liste + `summary.unread` + `seen`. 063 ile ek olarak (`cargo_notify.js`, en iyi çaba, kayıt akışını bozmaz): dairesi dolu KARGO kaydı açılınca dairenin güncel sakinlerine (üyelik + CRM ilişkisi; kiracılıyken malik hariç) e-posta, kayıtlı telefon cihazlarına FCM (push açıksa) ve tarayıcı bildirimi gider. Metin yalnız "kargo geldi" + daire etiketi (firma/ad yok). `cargo_notify_log` (entry_id PK) kayıt başına tek bildirim sağlar.

## Bildirim kanalları (063): SMS girişi, tarayıcı bildirimi
Tablolar (FK'siz, ekleyici): `sms_login_codes`, `web_push_subscriptions`, `cargo_notify_log`; DDL `migrations/063_notify_channels.sql` = `notify_channels_schema.js`. Hesap silmede web abonelikleri `deletePushDataForUser` içinde silinir.
- SMS sağlayıcı arayüzü `sms_provider.js` (adaptör: Netgsm). `.env`: `SMS_PROVIDER=netgsm`, `NETGSM_USERCODE`, `NETGSM_PASSWORD`, `NETGSM_HEADER`. Anahtar yoksa kapalı: `GET /auth/sms/status` -> `enabled:false`, istemci "Yakında…".
- `POST /auth/sms/request {phone}` (503 SMS_UNAVAILABLE / 429 SMS_RATE_LIMITED; kayıtlı olsun olmasın aynı 200) ve `POST /auth/sms/verify {phone, code}` -> `{token,user}`. 6 hane, 5 dk, kod başına 5 deneme, telefon başına 15 dk'da 3 kod, IP başına 20/60 istek/saat. Kod yalnız HMAC özeti (`SMS_CODE_PEPPER` ya da `JWT_SECRET`). Telefon birden çok hesapta varsa gönderilmez.
- Tarayıcı bildirimi (Firebase'siz VAPID): `.env` `WEB_PUSH_VAPID_PUBLIC`, `WEB_PUSH_VAPID_PRIVATE`, `WEB_PUSH_SUBJECT` (mailto:/https:); `npx web-push generate-vapid-keys`. Uçlar: `GET /app/web-push/config`, `PUT|DELETE /app/web-push/subscriptions`. Kullanıcı başına en çok 10 abonelik; 404/410 abonelik otomatik silinir. İstemci: `web/push_sw.js`, `web/web_push_helper.js`.
- WhatsApp yalnız arayüz ("Yakında…").
