# Anket ve Oylama - sunucu sözleşmesi

Modül kodu `survey` (F11.01; katalogda `available`, varsayılan KAPALI; süper açar, yönetici "Modül Talep Et" ile ister). Kapalıyken tüm yönetim uçları ve `site_code` verilmiş sakin listesi `403 MODULE_DISABLED` (`module: "survey"`); sakin listesi site_code'suz ise o siteyi atlar, tek anket 404. Zamanlayıcı YOK: `closes_at` geçmiş `open` anket okumada `closed` gibi davranır (`effective_status`), satır yönetici kapatınca değişir. Hata gövdesi her yerde `{ error, code, ...ek }`; kimlik `Authorization: Bearer`.

## Veri modeli (migration 044)
- `surveys`: id, site_code, title (1-120), question (1-1000), options (JSONB, 2-10 metin, her biri 1-80, birbirinden farklı), status (`draft|open|closed`, varsayılan draft), target_type (`site|blocks|apartments`, varsayılan site), target_block_ids BIGINT[], target_apartment_ids BIGINT[] (en çok 500), anonymous (varsayılan TRUE), one_vote_per_apartment (varsayılan FALSE), closes_at?, opened_at?, closed_at?, created_by?, created_at, updated_at. İndeks (site_code, status, id DESC).
- `survey_votes`: id, survey_id, user_code? (hesap silinince NULL = anonimleşir), apartment_id? (FK'sız; daire silinse de kayıt kalır), option_index (0-9), voted_at. Kısmi tekil (survey_id, user_code) WHERE user_code IS NOT NULL; indeks (survey_id, apartment_id).
- Silme politikası: site silinince anket + oylar CASCADE; hesap silinince oylar KALIR ve hesap bağı koparılır (anonimleşir), açtığı anketlerde `created_by` NULL ("Silinmiş Kullanıcı"). Dışa aktarmada yalnız kullanıcının kendi oyları: `survey_votes_cast: [{ survey_title, option_text, voted_at }]`.

## Kurallar
- Etkin (oy verilebilir) durum: `status = 'open'` ve (`closes_at IS NULL` ya da `closes_at > now()`).
- Hedef kitle = hedef dairelerdeki (site: tüm aktif daireler; blocks: blok daireleri; apartments: verilen daireler) AKTİF `apartment_memberships` sakinleri. Hedef kimlikler o siteye ait olmalı, yoksa `400 INVALID_TARGET`. `eligible_count` = kitledeki farklı kullanıcı sayısı.
- Durum geçişleri: draft -> open (`POST :id/open`, opened_at), open -> closed (`POST :id/close`, closed_at); başka geçiş `409 INVALID_STATE` ({from,to}). PATCH: draft her alan; open yalnız `title` ve `closes_at` (diğer alan 409, `fields`); closed 409. DELETE yalnız draft (aksi 409).
- Oy (`POST /app/surveys/:id/vote {option_index}`): kapalı / taslak / süresi geçmiş `409 SURVEY_CLOSED`; kitlede değil `403 NOT_ELIGIBLE`; aynı kullanıcı ikinci oy `409 ALREADY_VOTED`; `one_vote_per_apartment` ve aynı dairede başka hesap oy vermişse `409 APARTMENT_ALREADY_VOTED` (apartment_id = kullanıcının hedefteki aktif dairesi; birden çoksa en küçük id). Oy değiştirilemez. Anket satırı FOR UPDATE ile kilitlenir (yarış yok).
- Sonuç: `counts[]` (seçenek başına), `total_votes`, `eligible_count`. Yönetici / süper / kurul sonucu her zaman görür; `anonymous = false` ise yönetici / süper ayrıca `GET :id/voters` görür, kurul GÖREMEZ (403 FORBIDDEN_ROLE); anonim ankette voters `409 INVALID_STATE`. Sakin sonucu yalnız oy verdikten sonra ya da anket kapanınca görür; aksi hâlde `results: null`.

## Uçlar
Yönetim tabanı `/manager/sites/:siteCode/surveys` (yetki `hasSiteManagementAccess` / süper; BOARD_MEMBER yalnız GET; STAFF ve sakin `403 FORBIDDEN_ROLE`; başka sitenin yöneticisi `403 FORBIDDEN_SITE`). Tüm yazan uçlar JSON gövde (≤16 KB).

| Uç | Gövde / sorgu | Yanıt |
|---|---|---|
| GET `.../surveys` | `status=draft\|open\|closed\|all` (varsayılan all), `limit` (1-100, varsayılan 30), `offset` | `{ items:[Summary], total }` |
| POST `.../surveys` (201) | `title, question, options[], target:{type, block_ids?, apartment_ids?}, anonymous?, one_vote_per_apartment?, closes_at?, publish:'draft'\|'now'` | Detail |
| GET `.../surveys/:id` | - | Detail |
| PATCH `.../surveys/:id` | en az bir alan (durum kuralına göre) | Detail |
| POST `.../surveys/:id/open` / `/close` | - | Detail |
| DELETE `.../surveys/:id` | - (yalnız draft) | `{ ok:true }` |
| GET `.../surveys/:id/voters` | `limit`, `offset` | `{ items:[{ user_code, full_name, apartment_label, option_index, voted_at }], total }` |
| GET `/app/surveys` | `site_code?`, `limit`, `before_id` | `{ items:[MyItem], next_before_id }` |
| GET `/app/surveys/:id` | - | MyItem |
| POST `/app/surveys/:id/vote` | `option_index` | MyItem (my_vote dolu, results görünür) |

Sakin yalnız hedef kitlesinde olduğu `open` / `closed` anketleri görür (draft ASLA); görünmeyen / yok / başka site `404 SURVEY_NOT_FOUND` (varlık sızmaz).

## Yanıt şekilleri
- **Summary**: id, title, status, effective_status, target_type, anonymous, one_vote_per_apartment, closes_at, opened_at, closed_at, total_votes, eligible_count, created_at, created_by_name ("Silinmiş Kullanıcı" olabilir).
- **Detail** = Summary + question, options[], results{counts[], total_votes, eligible_count}, target{type, block_ids[], apartment_ids[], labels[]}.
- **MyItem** (sakin): id, site_code, site_name, title, question, options, effective_status, closes_at, my_vote (option_index|null), results (null | {counts, total_votes}). Açan kişi, hedef ve oy verenler sakine GÖSTERİLMEZ.

## Hata kodları
400: `INVALID_BODY` (alan Türkçe etiketle), `INVALID_TARGET`, `INVALID_QUERY`, `INVALID_SITE_CODE`. 401 `ACCOUNT_DELETED`. 403: `MODULE_DISABLED`, `FORBIDDEN_ROLE`, `FORBIDDEN_SITE`, `NOT_ELIGIBLE`. 404: `SURVEY_NOT_FOUND`, `SITE_NOT_FOUND`. 409: `INVALID_STATE`, `SURVEY_CLOSED`, `ALREADY_VOTED`, `APARTMENT_ALREADY_VOTED`. 413 `BODY_TOO_LARGE`. 429 genel hız sınırı (yazma 120/saat/kullanıcı, oy 60/saat, okuma 1200/saat; `Retry-After`).

## Audit ve gizlilik
Eylemler `survey.created|updated|opened|closed|deleted` (target_type `survey`; details yalnız durum / hedef türü / sayı / alan adları). Başlık, soru, seçenek metni ve OY İÇERİĞİ ASLA yazılmaz; oy için audit satırı YOKTUR (aktör kaydı anonim ankette kimin oy verdiğini sızdırırdı).
