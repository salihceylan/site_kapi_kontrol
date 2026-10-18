# Rezervasyon ve Konsiyerj - sunucu sözleşmesi

Modül kodu `reservation` (katalogda `available`, varsayılan KAPALI; süper açar, yönetici modül talep eder). Tek modül iki özellik taşır: ortak alan rezervasyonu ve konsiyerj talebi. Kapalıyken tüm uçlar `403 MODULE_DISABLED` (`module: "reservation"`; sakin listesi `site_code`suz ise o siteyi atlar, tek kayıt 404; `site_code` verilmiş listede modül durumu yalnız siteyle bağı olana söylenir: alan listesi önce sakinlik denetler (`403 NOT_A_RESIDENT`), rezervasyon/talep listesi bağı yoksa boş 200 döner). Ücret/ödeme, e-posta, push YOK (yalnız uygulama içi). Hata gövdesi her yerde `{ error, code, ...ek }`; kimlik `Authorization: Bearer`; JSON gövde ≤16 KB (413 `BODY_TOO_LARGE`).

## Zaman kuralları
Tüm gün/saat hesabı Europe/Istanbul takvimine göredir (sunucuda tek modül: `reservation_time.js`); saklama UTC `timestamptz`. API'de tarih `YYYY-MM-DD`, saat `HH:MM` (yerel), zaman damgası UTC ISO (`starts_at`, `ends_at`). "Bugün" = İstanbul günü. Hafta Pazartesi-Pazar; `weekday` 1=Pazartesi ... 7=Pazar.

## Veri modeli (migration 043)
- `reservation_areas` (Alan): id, site_code, name (1-80, sitede tekil), description? (≤500), capacity (1-100: aynı anda en çok rezervasyon), slot_minutes (15-480, 5'in katı), min_slots/max_slots (1-48), max_days_ahead (1-180), approval_mode (`otomatik|yonetici_onayli`), cancel_cutoff_hours (0-168), per_user_daily_limit (1-20), per_user_weekly_limit (günlükten küçük olamaz, ≤100), weekly_hours `[{weekday, start, end}]` (günde ≤3 aralık, çakışmaz, `end` en çok "24:00", her aralık ≥1 dilim; boş dizi = kapalı), is_active. Alan SİLİNMEZ, pasife alınır.
- `reservations`: id, site_code, area_id, user_code?, apartment_id?, starts_at, ends_at, slot_count, status (`beklemede|onaylandi|reddedildi|iptal`), note? (≤200), decision_note? (≤300), decided_by?, decided_at?, cancelled_by_kind (`resident|management|system`)?, cancelled_at?, idempotency_key.
- `concierge_requests`: id, site_code, user_code?, apartment_id?, category, note? (≤500; `diger` için zorunlu), requested_for?, status, staff_note? (≤300), closed_at?, idempotency_key.
- Sabit değerler: konsiyerj category `paket_teslim|misafir_hazirlik|temizlik|tasima|diger`; status `yeni|hazirlaniyor|tamamlandi|iptal`.
- Hesap silinince kayıtlar KALIR (sakin "Silinmiş Kullanıcı"); GELECEKTEKİ `beklemede/onaylandi` rezervasyonlar ve açık (`yeni/hazirlaniyor`) konsiyerj talepleri AYNI işlemde iptal edilir (`cancelled_by:"system"`). Site silinince hepsi silinir. Notlar ve daire bilgisi de kayıtla birlikte kalır. Dışa aktarmada yalnız kullanıcının kendi kayıtları: `reservations_made` (alan, zaman, durum, not) ve `concierge_requests_made` (kategori, not, durum, tarih).

## Rezervasyon kuralları
- Slot ızgarası her açık aralığın başlangıcından `slot_minutes` adımlıdır; rezervasyon TEK aralıkta ardışık `slots` (min_slots..max_slots) dilimdir. Başlangıç ızgarada ve aralık içinde değilse `409 OUTSIDE_OPEN_HOURS`; dilim sayısı sınır dışıysa `409 INVALID_SLOT_COUNT {min_slots,max_slots}`.
- Başlangıç şimdiden sonra ve tarih ≤ bugün + max_days_ahead olmalı (`409 OUTSIDE_BOOKING_WINDOW`). Pasif alan `409 AREA_INACTIVE`.
- Kapasite: aralığın herhangi bir anında çakışan (`beklemede` + `onaylandi`) sayısı < capacity, yoksa `409 SLOT_FULL`. `beklemede` de yer tutar. Kontrol site+alan advisory kilidi altındadır (eşzamanlı istekte kapasite aşılmaz).
- Kişi limitleri alan başınadır, HESAP (kullanıcı) başınadır (aynı dairede çok hesap kotayı katlar; ürün kararı) ve yalnız `beklemede/onaylandi` sayar: başlangıç gününde per_user_daily_limit (`409 RESERVATION_DAILY_LIMIT`), aynı haftada per_user_weekly_limit (`409 RESERVATION_WEEKLY_LIMIT`). Aynı kişi aynı alanda çakışan iki rezervasyon yapamaz (`409 ALREADY_BOOKED`).
- Site geneli (`RESERVATIONS_MAX_ACTIVE_PER_SITE`) ve kişi başı geçerli rezervasyon sınırları YUMUŞAK sayılır: farklı alanlara eşzamanlı istekte birkaç kayıt sınırı aşabilir (kapasite ve kişi limitleri kesindir).
- `approval_mode=otomatik` -> `onaylandi`; `yonetici_onayli` -> `beklemede`.
- Sakin iptali: yalnız KENDİ kaydı, `beklemede/onaylandi`, başlangıca ≥ cancel_cutoff_hours saat varken; aksi `409 CANCEL_WINDOW_CLOSED {cancel_cutoff_hours}`.
- Durumlar: `beklemede -> onaylandi | reddedildi | iptal`, `onaylandi -> iptal`; `tamamlandi` = `onaylandi` ve `ends_at` geçmiş (YANITTA türetilir, tabloda yok); `reddedildi`, `iptal`, `tamamlandi` SONDUR (`409 INVALID_TRANSITION {from,to}`).

## Uçlar
Sayfalama: `limit` (1-100, varsayılan 30). Sakin listeleri `before_id` (id azalan) + `next_before_id`; yönetim takvimi `cursor` + `next_cursor` (starts_at, id artan). Yazan uçlar `idempotency_key` (8-64 karakter `[A-Za-z0-9_.:-]`, istemci üretir) ister: aynı anahtar + AYNI içerik aynı kaydı döner (`replayed:true`), FARKLI içerik (farklı `apartment_id` dahil) `409 IDEMPOTENCY_CONFLICT`. Tekrar oynatma zaman denetiminden (ör. `requested_for` aralığı) ÖNCE döner; zaman denetimi yalnız yeni kayıtta yapılır.

| Uç | Gövde / sorgu | Yanıt |
|---|---|---|
| GET `/app/reservation-areas` | `site_code?` | `{ items:[Area+site_name] }` yalnız aktif alanlar |
| GET `/app/reservation-areas/:id/availability` | `from?`,`to?` (YYYY-MM-DD, ≤14 gün, varsayılan bugün+6; rezerve edilebilir aralığa kırpılır) | `{ area, days:[{date,weekday,slots:[{start,end,starts_at,ends_at,booked,capacity,available}]}], bookable_until }` (geçmiş dilimler yok) |
| POST `/app/reservations` (201) | `site_code, area_id, date, start("HH:MM"), slots, note?, apartment_id?, idempotency_key` | `{ reservation:MyReservation, replayed }` |
| GET `/app/reservations` | `site_code?`, `scope=upcoming\|past\|all` (varsayılan `all`; upcoming = beklemede/onaylandi ve bitmemiş), `before_id`, `limit` | `{ items:[MyReservation], next_before_id }` |
| GET `/app/reservations/:id` | - | `{ reservation }` |
| POST `/app/reservations/:id/cancel` | - | `{ reservation }` |
| GET `/app/concierge-requests` | `site_code?`, `status=open\|closed\|all`, `before_id`, `limit` | `{ items:[MyRequest], next_before_id }` |
| POST `/app/concierge-requests` (201) | `site_code, category, note?, requested_for?(ISO, şimdi..+90 gün), apartment_id?, idempotency_key` | `{ request:MyRequest, replayed }` |
| POST `/app/concierge-requests/:id/cancel` | - | `{ request }` (yalnız `yeni`) |
| GET `/manager/sites/:siteCode/reservation-areas` | - | `{ items:[Area], active_count }` (pasifler dahil) |
| POST `.../reservation-areas` (201) | alan alanları (`name, capacity, slot_minutes, weekly_hours` zorunlu; diğerleri varsayılanlı: min 1, max 4, 14 gün, otomatik, iptal 2 saat, günlük 2, haftalık 5, aktif) | `{ area }` |
| PATCH `.../reservation-areas/:id` | en az bir alan | `{ area }` (mevcut rezervasyonlar etkilenmez) |
| GET `.../reservations` | `area_id?`, `status` (virgüllü: `beklemede,onaylandi,reddedildi,iptal,tamamlandi`), `from?` (varsayılan bugün), `to?`, `cursor`, `limit` | `{ items:[Reservation], next_cursor, pending_count }` |
| GET `.../reservations/:id` | - | `{ reservation }` |
| POST `.../reservations/:id/decision` | `action: approve\|reject\|cancel`, `note` (reject/cancel için ZORUNLU, onayda isteğe bağlı) | `{ reservation, changed }` (aynı karar tekrarı 200 `changed:false`) |
| GET `.../concierge-requests` | `status=open\|closed\|all` ya da virgüllü, `category?`, `before_id`, `limit` | `{ items:[Request], next_before_id, counts:{yeni,hazirlaniyor,tamamlandi,iptal} }` |
| GET `.../concierge-requests/:id` | - | `{ request, next_statuses }` |
| PATCH `.../concierge-requests/:id` | `status?`, `note?` (sakine görünür kısa not; `null` siler); en az biri | `{ request, next_statuses, changed }` |

Konsiyerj geçişleri: `yeni -> hazirlaniyor | tamamlandi | iptal`, `hazirlaniyor -> tamamlandi | iptal`; `tamamlandi/iptal` SONDUR (`409 CONCIERGE_CLOSED`); geçersiz geçiş `409 INVALID_TRANSITION`. Sakin yalnız KENDİ `yeni` talebini iptal eder.

## Yanıt şekilleri
- **Area**: id, site_code, name, description, capacity, slot_minutes, min_slots, max_slots, max_days_ahead, approval_mode, cancel_cutoff_hours, per_user_daily_limit, per_user_weekly_limit, weekly_hours, is_active, created_at, updated_at.
- **MyReservation** (sakin): id, site_code, site_name, area{id,name}, starts_at, ends_at, date, start, end, slot_count, status (türetilmiş), note, decision_note, cancelled_by?, apartment{id,label}?, `can_cancel`, `cancel_deadline`?, created_at.
- **Reservation** (yönetim): MyReservation alanları (can_cancel yok) + `requester{user_code,name,phone?}`, `decided_by{user_code,name}?`, `can_decide` (beklemede ve başlangıç geçmemiş), `can_cancel`. KURUL için `requester` yalnız `{name}`, `decided_by` yalnız `{name}`.
- **MyRequest**: id, site_code, site_name, category, note, requested_for, status, staff_note, apartment?, `can_cancel`, created_at, updated_at, closed_at?. **Request** (yönetim): + `requester{user_code,name,phone?}` (kurulda yalnız `{name}`).

## Yetki matrisi
| Rol | Alan tanımla/düzenle | Takvim / talep listesi | Onay, red, iptal, konsiyerj durumu | Kendi rezervasyon / talep |
|---|---|---|---|---|
| Sakin (aktif daire sakini) | hayır | YALNIZ kendi kayıtları + aktif alanlar, boş dilimler | hayır | evet (/app) |
| Görevli (STAFF) | 403 (alanları okur) | sitenin tümü | evet | (sakinse /app) |
| Yönetici / Süper | evet | sitenin tümü | evet | (sakinse /app) |
| Kurul (BOARD_MEMBER) | 403 | sitenin tümü, SALT OKUR (telefon/kullanıcı kodu yok) | 403 | (sakinse /app) |
| Başka site / ilgisiz | 403 `FORBIDDEN_SITE` / `FORBIDDEN_ROLE` | - | - | - |

Yönetim sakin adına rezervasyon/talep AÇMAZ. Başkasının kaydı (sakin) ve başka sitenin alanı/kaydı 404 (`RESERVATION_NOT_FOUND`, `CONCIERGE_NOT_FOUND`, `AREA_NOT_FOUND`). Sakin YAZMA (rezervasyon/talep AÇMA) için sitede HÂLÂ aktif daire sakini olmalı (taşınan: `403 NOT_A_RESIDENT`); taşınan sakin kendi geçmişini okur ve kendi gelecekteki rezervasyonunu / `yeni` talebini İPTAL edebilir (iptal yolunda sakinlik şartı yok).

## Hata kodları
400: `INVALID_BODY` (alan Türkçe etiketle), `INVALID_QUERY`, `INVALID_SITE_CODE`, `INVALID_LOCATION` (daire kişinin kendi dairesi değil). 401 `ACCOUNT_DELETED`. 403: `MODULE_DISABLED`, `FORBIDDEN_ROLE`, `FORBIDDEN_SITE`, `NOT_A_RESIDENT`. 404: `SITE_NOT_FOUND`, `AREA_NOT_FOUND`, `RESERVATION_NOT_FOUND`, `CONCIERGE_NOT_FOUND`. 409: `AREA_NAME_TAKEN`, `AREA_LIMIT` (sitede en çok 50 alan), `AREA_INACTIVE`, `OUTSIDE_BOOKING_WINDOW`, `OUTSIDE_OPEN_HOURS`, `INVALID_SLOT_COUNT`, `SLOT_FULL`, `ALREADY_BOOKED`, `RESERVATION_DAILY_LIMIT`, `RESERVATION_WEEKLY_LIMIT`, `RESERVATION_USER_LIMIT` (`active_limit`), `RESERVATION_SITE_LIMIT`, `CANCEL_WINDOW_CLOSED`, `RESERVATION_PAST` (geçmiş rezervasyon onaylanamaz), `INVALID_TRANSITION`, `CONCIERGE_CLOSED`, `CONCIERGE_USER_LIMIT` (`user_open_limit`), `CONCIERGE_SITE_LIMIT`, `IDEMPOTENCY_CONFLICT`. 413 `BODY_TOO_LARGE`. 429: `RESERVATION_RATE_LIMITED`, `CONCIERGE_RATE_LIMITED` (`Retry-After`; kullanıcı saatte 20 rezervasyon / 10 talep, siteler arası toplam) ve genel hız sınırı (yazma 120/saat, okuma 1200/saat).

## Sınırlar (ortam değişkeni) ve audit
`RESERVATIONS_MAX_PER_USER_PER_HOUR` (20), `RESERVATIONS_MAX_ACTIVE_PER_USER` (30; sitede gelecekteki beklemede/onaylandi), `RESERVATIONS_MAX_ACTIVE_PER_SITE` (5000), `CONCIERGE_MAX_PER_USER_PER_HOUR` (10), `CONCIERGE_MAX_OPEN_PER_USER` (10), `CONCIERGE_MAX_OPEN_PER_SITE` (1000). Audit: `reservation_area.created|updated`, `reservation.created|approved|rejected|cancelled`, `concierge.created|updated|cancelled` (not/açıklama metni yazılmaz).
