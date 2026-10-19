# Karar Defteri - sunucu sözleşmesi

Modül kodu `decision_book` (katalogda `available`, `core:false`, varsayılan KAPALI; süper açar, yönetici modül talep eder). Kapalıyken yönetim uçları `403 MODULE_DISABLED` (`module: "decision_book"`); sakin listesi `site_code`suz ise o siteyi atlar. Yönetim kurulu, genel kurul ve denetim kurulu kararları taslak olarak yazılır, kesinleştirilince (site, yıl) içinde sıra numarası alır ("2026/3") ve bir daha DEĞİŞTİRİLEMEZ / SİLİNEMEZ. Hata gövdesi her yerde `{ error, code, ...ek }`; kimlik `Authorization: Bearer`.

> **Bu kayıt noter onaylı karar defterinin yerine geçmez; resmî karar defterine işlenmesi gerekir.**
> (Kat Mülkiyeti Kanunu kapsamındaki resmî karar defteri noter onaylıdır; bu modül yalnız sitenin dijital kaydıdır. API bu uyarı için özel bir alan döndürmez: istemci uyarıyı karar ekranlarında sabit metin olarak gösterir.)

## Veri modeli (migration 050)
- `board_decisions`: id, site_code (site silinince CASCADE), year (= toplantı tarihinin yılı; DB kısıtı), decision_no? (kesinleştirmede verilir), meeting_type (`yonetim_kurulu|genel_kurul|denetim_kurulu|diger`), meeting_date (DATE), title (1-160, tek satır), body (1-10000, çok satırlı düz yazı), attendees? (≤2000, çok satırlı), vote_result (`kabul|ret|ertelendi|bilgi`), votes_for? / votes_against? / votes_abstain? (≥0), visibility (`yonetim|sakinler`, varsayılan `yonetim`), status (`taslak|kesin`, varsayılan `taslak`), finalized_at?, finalized_by? (users, SET NULL), supersedes_id?, created_by? (users, SET NULL), created_at, updated_at.
- Kısıtlar: `status = 'kesin'` ⇔ `decision_no` dolu ⇔ `finalized_at` dolu (iki yönlü); `decision_no > 0`; `UNIQUE (site_code, year, decision_no) WHERE decision_no IS NOT NULL`; `supersedes_id <> id`.
- `supersedes_id` BİLEŞİK yabancı anahtardır: `(site_code, supersedes_id) -> board_decisions(site_code, id)` (`UNIQUE (site_code, id)` üzerinden). Değiştirilen karar veritabanı düzeyinde de AYNI sitede olmak zorundadır; sunucu ayrıca hedefin KESİN olduğunu denetler.
- İndeksler: `uq_board_decisions_number`, `idx_board_decisions_drafts (site_code, year DESC, id DESC) WHERE status='taslak'`, `idx_board_decisions_supersedes (site_code, supersedes_id)`, `created_by` ve `finalized_by` (kısmi).
- Şema iki yoldan AYNI kurulur: `migrations/050_decision_book.sql` ve `src/modules/decision_book_schema.js` (`ensureDecisionBookSchema`, db.js açılışında dev blok BİTTİKTEN sonra, katalog kontrolüyle yalnız eksikler; her şey varsa hiçbir DDL gönderilmez). Eşitlik birim testiyle (`test/decision_book_schema.test.js`) ve gerçek PostgreSQL'de zincir / canlı şema kataloğu karşılaştırmasıyla (`board_decisions` + iki tetikleyici + iki işlev katalogdadır) zorlanır.

## Değişmezlik (veritabanı tetikleyicisi)
`trg_board_decisions_immutable` (BEFORE UPDATE OR DELETE, satır başına) ve `trg_board_decisions_no_truncate` (BEFORE TRUNCATE). Finans değişmez tablolarıyla (`trg_finance_immutable`) aynı yaklaşım:
- Taslak satır serbestçe güncellenir / silinir (kesinleştirme = taslağın `kesin`e güncellenmesi).
- `kesin` satır UPDATE edilemez. TEK istisna: `created_by` ya da `finalized_by` sütunlarından BİRİ NULL'a iner, o kullanıcı artık `users` tablosunda YOKTUR ve başka hiçbir sütun değişmez (users satırı silinince `ON DELETE SET NULL` eylemi; aynı kullanıcı iki sütunda da olabilir, eylemler sırayla tek sütun değiştirir).
- `kesin` satır DELETE edilemez. TEK istisna: üst `sites` satırı artık YOK (site silme CASCADE; `deleteSitePermanently` ve ham `DELETE FROM sites` ikisi de çalışır; bileşik supersedes FK'si `NO ACTION` olduğundan aynı ifadede silinen zincir engel olmaz).
- TRUNCATE her durumda reddedilir. Hata metinleri: `final board decisions are immutable`, `board decisions cannot be truncated`.
- İşlev gövdeleri sürüm işareti (`-- dbk:1`) taşır; işaret değişirse ensure işlevi yeniler.

## Numaralama
Kesinleştirme işleminde (`POST .../finalize`): karar satırı `FOR UPDATE` kilitlenir; zaten kesinse AYNEN döner. Değilse `pg_advisory_xact_lock(hashtext('board_decisions_no:<site>:<yıl>'))` alınır, `COALESCE(MAX(decision_no), 0) + 1` hesaplanır ve satır `kesin` yapılır (`finalized_at = NOW()`, `finalized_by = çağıran`). Yıl, toplantı tarihinin yılıdır (her yıl 1'den başlar). Kesin karar silinemediği için numarada boşluk oluşmaz; `uq_board_decisions_number` yedek korumadır. Eşzamanlı kesinleştirme yarışı gerçek PostgreSQL'de sınanır (26 eşzamanlı istek, iki yıl: 1..N boşluksuz; aynı taslağa 10 eşzamanlı istek: tek numara, tek audit satırı).

## Uçlar
Yönetim tabanı: `/manager/sites/:siteCode/decisions`. Gövde JSON (≤64 KB; üstü `413 BODY_TOO_LARGE`). Bilinmeyen gövde alanları (`status`, `decision_no`, `site_code` ...) YOK SAYILIR.

| Uç | Gövde / sorgu | Yanıt |
|---|---|---|
| GET `.../decisions` | `year?` (4 hane), `status?` (`all` varsayılan / `taslak` / `kesin`), `meeting_type?`, `q?` (başlık ve metinde Türkçe / büyük-küçük harf duyarsız; "2026/3" biçimi karar numarasını da bulur), `cursor?` ya da `before_id?`, `limit` (50, en çok 200) | `{ items:[Decision], next_before_id, next_cursor, years:[int] }` |
| GET `.../decisions/:id` | - | `{ decision }` |
| POST `.../decisions` (201) | `meeting_type, meeting_date ("YYYY-MM-DD"), title, body, vote_result` zorunlu; `attendees?, votes_for?, votes_against?, votes_abstain?, visibility? ("yonetim"), supersedes_id?` | `{ decision }` (taslak) |
| PATCH `.../decisions/:id` | yalnız gönderilen alanlar (aynı küme); isteğe bağlılar `null` ile temizlenir, zorunlular (`visibility` dahil) `null` olamaz; boş gövde ya da aynı değerler = değişiklik yok (200, audit yazılmaz); `meeting_date` değişirse `year` da değişir | `{ decision }`; kesin karar `409 DECISION_FINAL` |
| DELETE `.../decisions/:id` | - | `{ deleted: true }`; kesin karar `409 DECISION_FINAL` |
| POST `.../decisions/:id/finalize` | - | `{ decision }` (numaralı). İdempotent: zaten kesin karar 200 ile AYNEN döner (numara / zaman değişmez, audit yazılmaz) |
| GET `/app/decisions` | `site_code?`, `year?`, `cursor?` ya da `before_id?`, `limit` (50, en çok 200) | `{ items:[Decision (sakin)], next_before_id, next_cursor, years:[int] }` |
| GET `/app/decisions/:id` | - | `{ decision }` (sakin görünümü) |

**Alan kuralları:** `meeting_date` gerçek bir gün olmalı, 1950-01-01 ile (bugün İstanbul + 366 gün) arasında; oy sayıları 0-100000 tam sayı (metin "12" de kabul); `supersedes_id` bu sitenin KESİN kararı olmalı (taslak / olmayan / başka sitenin kararı `400 INVALID_FIELD { field: "supersedes_id" }`). Site başına en çok 5000 karar (taslak + kesin; aşılırsa `409 DECISION_LIMIT_REACHED { limit: 5000 }`).

**Decision** (yönetim görünümü): `id, site_code, year, decision_no|null, number_label ("2026/3")|null, meeting_type, meeting_date ("YYYY-MM-DD"), title, body, attendees|null, vote_result, votes_for|null, votes_against|null, votes_abstain|null, visibility, status, supersedes_id|null, supersedes_label|null, superseded_by:[{ id, number_label }], created_by_name, finalized_by_name|null, finalized_at|null, created_at, updated_at` (zamanlar ISO-8601 UTC).
- `superseded_by`: bu kararı değiştiren KESİN kararlar (yıl, numara artan); taslaklar listelenmez, bu yüzden `number_label` her zaman doludur.
- `created_by_name` / `finalized_by_name`: hesabı silinmiş ya da bağı kopmuş kullanıcı için `"Silinmiş Kullanıcı"`; `finalized_by_name` yalnız taslakta `null`.

**Decision** (sakin görünümü): aynı alanlar, ancak `status`, `visibility` ve `created_by_name` YOK. Sakin yalnız `kesin` + `sakinler` kararları görür; `superseded_by` yalnız sakine de görünen (sakinler) kararları listeler; değiştirilen karar sakine görünmüyorsa (`yonetim`) `supersedes_id` ve `supersedes_label` `null` döner (iç kararın varlığı sızmaz).

**Sıralama ve sayfalama:** yönetim listesinde önce taslaklar (toplantı yılı azalan, sonra en yeni), ardından kesin kararlar (yıl ve karar numarası azalan). Sakin listesinde yalnız kesin kararlar (yıl, numara azalan; birden çok sitede kimlik azalan). İki sayfa yöntemi de desteklenir:
- `next_cursor` -> sonraki istekte `cursor` (ÖNERİLEN; opak metin, sıralama anahtarını taşır; karar silinse / kesinleşse de sayfa kopmaz).
- `next_before_id` -> sonraki istekte `before_id` (önceki sayfanın son kararının kimliği; o karar artık yoksa ya da çağırana görünmüyorsa sayfa BOŞ döner). İkisi birlikte gelirse `cursor` geçerlidir.
- `years`: yıl seçicisi için (süzgeçlerden bağımsız): yönetimde sitenin tüm karar yılları, sakinde görünür kararların yılları (`site_code` verilmişse o site); azalan.

## Yetki matrisi
| Rol | GET liste / ayrıntı | POST / PATCH / DELETE / finalize | /app uçları |
|---|---|---|---|
| Süper / Yönetici | evet (taslaklar dahil) | evet | (sakinse) görünür kararlar |
| Kurul (BOARD_MEMBER) | evet (taslaklar DAHİL tümü, salt okur) | 403 FORBIDDEN_ROLE | (sakinse) görünür kararlar |
| Görevli (STAFF) | 403 FORBIDDEN_ROLE | 403 FORBIDDEN_ROLE | (sakinse) görünür kararlar |
| Sakin / ilgisiz | 403 FORBIDDEN_ROLE | 403 FORBIDDEN_ROLE | sakini olduğu sitelerin `kesin` + `sakinler` kararları |
| Başka sitenin yöneticisi / kurulu | 403 FORBIDDEN_SITE | 403 FORBIDDEN_SITE | - |

Denetim sırası: biçim (400 `INVALID_SITE_CODE`) -> yetki (403) -> site varlığı (404 `SITE_NOT_FOUND`) -> modül (403 `MODULE_DISABLED`). Her sorguda `site_code` vardır (IDOR yok): başka sitenin kararı kendi site yolundan `404 DECISION_NOT_FOUND`. Yazma işlemleri `sites FOR KEY SHARE -> users FOR KEY SHARE (silinmiş hesap yazamaz: 401 ACCOUNT_DELETED) -> [site danışma kilidi (oluşturma, 5000 sınırı)] -> board_decisions FOR UPDATE -> [numara danışma kilidi] -> değiştirilen karar FOR KEY SHARE` sırasıyla; nadir 40P01'de işlem tek sefer yeniden denenir.

**"Sitenin sakini"** (canlı değerlendirilir; site `approved` olmalı): o sitede aktif dairede aktif `apartment_memberships`, ya da aktif `site_people` kaydı + aktif dairede güncel `apartment_residencies` ilişkisi (malik DAHİL: kat malikleri kurulu kararları malike de açıktır; kiracı varken de), ya da eski `apartments.resident_user_code` bağı, ya da aktif `site_memberships` RESIDENT kaydı. Sakin ayrıntısında görünmeyen / taslak / `yonetim` / başka site / modül kapalı -> `404 DECISION_NOT_FOUND`. Sakin listesinde `site_code` verilmiş ve çağıran o sitenin sakini değilse boş liste döner (modül durumu yalnız sakine söylenir); sakini olduğu sitede modül kapalıysa `403 MODULE_DISABLED`.

## Hata kodları
400: `INVALID_FIELD` (`{ field }`: gövde anahtarı, ör. `title`, `meeting_date`, `supersedes_id`), `INVALID_QUERY`, `INVALID_SITE_CODE`. 401 `ACCOUNT_DELETED`. 403: `MODULE_DISABLED`, `FORBIDDEN_ROLE`, `FORBIDDEN_SITE`. 404: `DECISION_NOT_FOUND`, `SITE_NOT_FOUND`. 409: `DECISION_FINAL`, `DECISION_LIMIT_REACHED` (`{ limit }`). 413 `BODY_TOO_LARGE`. 429: hız sınırı (`Retry-After`; yazma 120/saat kullanıcı başına + 1200/saat IP başına, okuma 1200/saat + 12000/saat).

## Audit ve gizlilik
Audit eylemleri (hedef `board_decision`): `board_decision.created` (details: status, year, meeting_type, visibility, supersedes_id), `board_decision.updated` (details: `fields` = değişen sütun adları), `board_decision.deleted` (status, year), `board_decision.finalized` (year, decision_no, number_label). Karar başlığı, metni ve katılımcılar audit `details` alanına ve sunucu günlüğüne YAZILMAZ.

## Hesap silme, site silme ve dışa aktarma
- Yönetici hesabı silinince (kimliksizleştirme) kararlar SİLİNMEZ: karar siteye aittir; `created_by` / `finalized_by` tombstone kullanıcıyı göstermeye devam eder, ad "Silinmiş Kullanıcı" görünür (kesin karar satırı değişmez). `users` satırı gerçekten silinirse FK `SET NULL` olur (tetikleyicinin tek UPDATE istisnası). QA hesap silme politika tablosunda (A6) iki FK `TOMBSTONE` olarak kayıtlıdır.
- Site silinince taslak ve kesin tüm kararlar CASCADE ile silinir.
- Kişisel veri dışa aktarmasına (`/me/data-export`) bu modülden bölüm EKLENMEZ (kararlar sitenin kurumsal kaydıdır).

## Doğrulama
- Birim: `test/decision_book_schema.test.js`, `test/decision_book_common.test.js`, `test/decision_book_routes.test.js`.
- Gerçek PostgreSQL: `QA_ONLY=chain,live,decision_book node scripts/qa_platform_pg.mjs` (bölüm gövdesi `scripts/qa_decision_book_section.mjs`): şema, modül kapısı, yetki matrisi, IDOR, numaralama yarışı, supersedes kuralları, doğrudan SQL ile UPDATE / DELETE / TRUNCATE reddi, kullanıcı silmede FK SET NULL, kesin kararlı site silme, sakin görünürlüğü ve sayfalama, 5000 sınırı, hesap silme, audit gizliliği, eşzamanlı karışık yük (40P01 = 0).
