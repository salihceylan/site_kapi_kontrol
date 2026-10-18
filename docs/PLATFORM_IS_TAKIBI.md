# İş Takibi (arıza, bakım, talep) - sunucu sözleşmesi

Modül kodu `work_tracking` (katalogda `available`, varsayılan KAPALI; süper açar, yönetici modül talep eder). Kapalıyken tüm uçlar `403 MODULE_DISABLED` (`module: "work_tracking"`; sakin listesi site_code'suz ise o siteyi atlar, tek talep 404). Fotoğraf/dosya eki bu sürümde YOK; e-posta/push YOK (yalnız uygulama içi `unread`). Hata gövdesi her yerde `{ error, code, ...ek }`; kimlik `Authorization: Bearer`.

## Veri modeli (migration 042)
- `work_items`: id, site_code, category, location_type, title (1-120), description (1-2000), apartment_id?, block_id?, status, priority, resident_urgent, assigned_to?, due_date?, created_by?, created_at, updated_at, closed_at?, requester_seen_at, resident_updated_at.
- `work_item_events` (değişmez günlük, yalnız eklenir): work_item_id, event_type, visibility (`public|internal`), actor_user_code?, actor_kind (`resident|staff|manager`), from_value?, to_value?, body? (yorum, 1-1000).
- Sabit değerler: category `ariza|bakim|sikayet_oneri|diger`; location_type `ortak_alan|daire`; status `yeni|islemde|beklemede|cozuldu|kapandi|iptal`; priority `dusuk|normal|acil`.
- Hesap silinince talep/olaylar/yorum metinleri KALIR; açan/yazan adı "Silinmiş Kullanıcı"; silinen görevlinin AÇIK talepleri atamasız kalır (kapalı talepler geçmiş olarak atanmış kalır). Site silinince hepsi silinir. Dışa aktarmada yalnız kullanıcının kendi talepleri (`work_items_created`: başlık/açıklama/durum/tarih) ve kendi yazdığı yorumlar (`work_item_comments`: work_item_id, created_at, body, visibility) bulunur.

## Durum geçişleri (sunucuda doğrulanır; `next_statuses` yönetim detayında hazır gelir)
yeni -> islemde, beklemede, cozuldu, iptal | islemde -> beklemede, cozuldu, iptal | beklemede -> islemde, cozuldu, iptal | cozuldu -> kapandi, islemde (yeniden aç) | kapandi, iptal SONDUR (değişiklik/yorum yok: 409 WORK_ITEM_CLOSED). Sakin yalnız KENDİ `yeni` talebini `iptal` eder.

## Uçlar
Sayfalama: `before_id` imleci + `limit` (1-100, varsayılan 30); yanıttaki `next_before_id` doluysa sonraki sayfa. Sıra id azalan. Tüm yazan uçlar JSON gövde (≤16 KB).

| Uç | Gövde / sorgu | Yanıt |
|---|---|---|
| GET `/app/work-items` | `site_code?`, `status=open\|closed\|all`, `before_id`, `limit` | `{ items:[MyItem], next_before_id, unread_updates }` |
| POST `/app/work-items` (201) | `site_code, category, location_type, title, description, apartment_id?, block_id?, urgent?(bool), idempotency_key` | `{ item:MyItem, replayed }` |
| GET `/app/work-items/:id` | - | `{ item:MyItem, events:[Event] }` (yalnız public) |
| POST `/app/work-items/:id/cancel` | - | `{ item }` |
| POST `/app/work-items/:id/comments` (201) | `body, idempotency_key` (public) | `{ event, replayed }` |
| POST `/app/work-items/:id/seen` | - | `{ id, unread:false }` |
| GET `/manager/sites/:siteCode/work-items` | `status` (virgüllü ya da `open`), `category`, `priority`, `assigned=me\|none\|<user_code>`, `q`, `before_id`, `limit` | `{ items:[Item], next_before_id, counts:{yeni,...,iptal} }` |
| GET `.../work-items/:id` | - | `{ item:Item, events:[Event], next_statuses:[] }` |
| PATCH `.../work-items/:id` | en az biri: `status, priority, assigned_to(user_code\|"me"\|null), due_date("YYYY-MM-DD"\|null)` | detay (GET ile aynı); değişiklik yoksa 200, olay yazılmaz |
| POST `.../work-items/:id/comments` (201) | `body, visibility("internal"\|"public"), idempotency_key` | `{ event, replayed }` |
| GET `.../work-items/assignees` | - | `{ items:[{ user_code, name, role:"manager"\|"staff" }] }` (görevli yalnız kendini görür) |

`idempotency_key`: 8-64 karakter `[A-Za-z0-9_.:-]`, istemci üretir; aynı anahtar + AYNI içerik (talep: başlık/açıklama/kategori/konum/urgent; yorum: body+visibility) yeni satır açmaz, aynı kaydı döner (`replayed:true`); aynı anahtar + FARKLI içerik `409 IDEMPOTENCY_CONFLICT`. Sakin daire yalnız KENDİ güncel dairesi olabilir; `ortak_alan` talebinde daire gönderilemez; blok sitenin bloğu olmalı.

## Yanıt şekilleri
- **MyItem** (sakin): id, site_code, site_name, category, location_type, title, description, status, `urgent`, apartment{id,label}?, block{id,name}?, `has_assignee`(bool), due_date?, created_at, updated_at, closed_at?, `unread`, `can_cancel`, `can_comment`. Öncelik, atanan adı ve iç olaylar sakine GÖSTERİLMEZ.
- **Item** (yönetim; sakin görünümünden FARKLI alanlar): id, site_code, category, location_type, title, description, status, priority, resident_urgent, apartment?, block?, `requester{user_code,name,phone?}`, `assigned_to{user_code,name}?`, due_date?, created_at, updated_at, closed_at?. KURUL için `requester` yalnız `{name}` (telefon ve kullanıcı kodu yok).
- **Event**: id, type (`created|status_changed|assigned|priority_changed|due_date_changed|comment`), visibility, actor_kind, from, to, body, created_at. Yönetim görünümünde `actor{user_code,name}` ve `assigned` olaylarında `from_label/to_label` da gelir; sakin/kurul görünümünde `actor_kind` yalnız `resident|management`, iç (internal) olaylar (atama, öncelik, iç yorum) HİÇ gelmez. `unread`: yönetim sizin görmediğiniz bir durum/hedef tarih/herkese açık yorum yazdıysa true; detayı açınca `.../seen` çağrılır.

## Yetki matrisi
| Rol | Talep aç | Kendi talebi | Liste/detay | Durum/öncelik/hedef tarih | Atama | Yorum |
|---|---|---|---|---|---|---|
| Sakin (aktif daire sakini) | evet (/app) | iptal (yalnız yeni), public yorum | YALNIZ kendi talepleri + public olaylar | hayır | hayır | public (kendi talebine) |
| Görevli (STAFF) | (sakinse /app) | - | kendine atanmış, atanmamış VEYA ataması yetim (atanan silinmiş / görevden alınmış) olanlar; diğeri 404 | evet | yalnız kendine al / kendini bırak | internal + public |
| Yönetici / Süper | (sakinse /app) | - | sitenin tümü | evet | sitenin yöneticisi/görevlisi (süper: kendine de) | internal + public |
| Kurul (BOARD_MEMBER) | (sakinse /app) | - | sitenin tümü, SALT OKUR; iç olay/telefon yok | hayır (403) | hayır (403) | hayır (403) |
| Başka site / ilgisiz | 403 NOT_A_RESIDENT | - | 403 FORBIDDEN_SITE / FORBIDDEN_ROLE | - | - | - |

Başkasının talebi (sakin) ve görünmeyen talep (görevli) `404 WORK_ITEM_NOT_FOUND`; varlık sızmaz. Sakin YAZMA (talep aç, iptal, yorum) için sitede HÂLÂ aktif daire sakini olmalıdır (taşınan/pasifleşen: `403 NOT_A_RESIDENT`); kendi geçmiş taleplerini okur ve `seen` çağırabilir.

## Hata kodları
400: `INVALID_BODY` (alan Türkçe etiketle), `INVALID_QUERY`, `INVALID_SITE_CODE`, `INVALID_ASSIGNEE`, `INVALID_LOCATION`. 401 `ACCOUNT_DELETED`. 403: `MODULE_DISABLED`, `FORBIDDEN_ROLE`, `FORBIDDEN_SITE`, `NOT_A_RESIDENT`. 404: `WORK_ITEM_NOT_FOUND`, `SITE_NOT_FOUND`. 409: `INVALID_TRANSITION` ({from,to}), `WORK_ITEM_CLOSED`, `WORK_ITEM_LIMIT` (sitede açık talep üst sınırı, `open_limit`), `WORK_ITEM_USER_LIMIT` (kişinin o sitede açık talebi, `user_open_limit`), `WORK_ITEM_COMMENT_LIMIT` (sakin 100, yönetim/görevli 200 yorum; ayrı sayılır), `IDEMPOTENCY_CONFLICT`. 413 `BODY_TOO_LARGE`. 429: `WORK_ITEM_RATE_LIMITED` (`Retry-After`; kullanıcı saatte 20 talep, siteler arası toplam) ve genel hız sınırı (yazma 120/saat, okuma 1200/saat).

## Sınırlar (ortam değişkeni)
`WORK_ITEMS_MAX_OPEN_PER_SITE` (2000; kapandi/iptal dışı talepler), `WORK_ITEMS_MAX_PER_USER_PER_HOUR` (20; siteler arası), `WORK_ITEMS_MAX_OPEN_PER_USER` (30; kişinin tek sitede açık talebi). Audit eylemleri: `work_item.created|status_changed|assigned|updated|commented|cancelled` (başlık/açıklama/yorum metni yazılmaz).
