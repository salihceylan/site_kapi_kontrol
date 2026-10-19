# Firma ve Sözleşme Takibi - sunucu sözleşmesi

Modül kodu `contracts` (katalogda `available`, `core:false`, varsayılan KAPALI; süper açar, yönetici modül talep eder). Kapalıyken tüm uçlar `403 MODULE_DISABLED` (`module: "contracts"`). Site yönetimi hizmet aldığı firmaları (asansör, güvenlik, temizlik, bahçe, havuz, teknik bakım, yazılım, sigorta...) ve bu firmalarla yaptığı sözleşmeleri kaydeder; bitiş tarihi ve fesih bildirimi son günü yaklaşınca site yöneticilerine günlük e-posta hatırlatması gider. Sakine açık uç YOKTUR. Hata gövdesi her yerde `{ error, code, ...ek }`; kimlik `Authorization: Bearer`; JSON alan adları snake_case.

## Veri modeli (migration 049)
- `contract_vendors`: id, site_code, name (1-120; sitede büyük/küçük harf duyarsız TEKİL), category, contact_name? (≤120), phone? (≤32), email? (≤254), tax_no? (≤20), note? (≤1000), is_active (varsayılan TRUE), created_by?, created_at, updated_at. Tekil indeks `(site_code, lower(name))`.
- `site_contracts`: id, site_code, vendor_id (firma; RESTRICT), title (1-160), category, start_date, end_date? (>= start_date), notice_days (0-365, varsayılan 30), remind_before_days (0-180, varsayılan 30), amount? (NUMERIC(14,2), >= 0), currency (`TRY`), period? (`aylik|yillik|tek_sefer|diger`), auto_renew (varsayılan FALSE), status (`aktif|feshedildi`), terminated_at? (DB kısıtı: `feshedildi` ⇔ dolu), note? (≤2000), created_by?, updated_by?, created_at, updated_at. İndeksler `(site_code, end_date)`, `(site_code, vendor_id)`.
- `contract_reminders`: id, contract_id (sözleşme silinirse CASCADE), site_code, kind (`bitis|fesih_bildirim`), due_date, claimed_at (talep anı, turun saati), sent_at? (ilk başarılı gönderim), recipients. TEKİL `(contract_id, kind, due_date)` = hatırlatma idempotansı. İndeks `(site_code, sent_at)` (günde tek e-posta denetimi).
- Kategoriler: `asansor, guvenlik, temizlik, bahce, havuz, teknik_bakim, yazilim, sigorta, diger`.
- Sınırlar: site başına en çok **500 firma**, **2000 sözleşme** (aşılınca `409 LIMIT_REACHED { limit }`; eşzamanlı eklemelerde de aşılmaz: site başına işlem kilidi).
- Silme politikası: site silinince firmalar, sözleşmeler ve hatırlatma kayıtları CASCADE. Kullanıcı silinince kayıt KALIR; `created_by` / `updated_by` tombstone'u gösterir ya da FK ile NULL olur, ad "Silinmiş Kullanıcı" görünür. Sözleşmesi olan firma veritabanında silinemez (RESTRICT); API'de silme YOK (firma pasife alınır, sözleşme feshedilir).
- Şema db.js'te dev blokta DEĞİL: `ensureContractsSchema` katalog kontrolüyle yalnız eksikleri, her biri kendi ifadesiyle kurar (açılış 40P01 dersi); FK'ler ayrı, katalog korumalı ifadelerdir. migration 049 = `contracts_schema.js` (test: birebir eşitlik, aynı sıra).

## Hesaplanan alanlar (sunucuda, Europe/Istanbul takvim günü)
- `days_left` = `end_date − bugün` (gün; bitişsizde `null`; geçmişte negatif).
- `state`: `feshedildi` (status feshedildi) > `sona_erdi` (end_date < bugün) > `yaklasiyor` (end_date − bugün <= remind_before_days; bitiş günü dahil) > `aktif` (bitişsiz sözleşme her zaman `aktif`).
- `notice_deadline` = `end_date − notice_days`; YALNIZ `auto_renew` ve `end_date` doluysa, aksi `null` (fesih bildirimi bu günden sonra yapılırsa sözleşme kendiliğinden yenilenir).
- "Bugün" İstanbul takvimine göredir (UTC 21:00 = İstanbul gece yarısı; liste süzgeci, özet ve yanıt alanları aynı günü kullanır).

## Uçlar
Taban: `/manager/sites/:siteCode`. DELETE YOK. Gövde JSON (≤16 KB; üstü `413 BODY_TOO_LARGE`). Bilinmeyen gövde alanları yok sayılır.

| Uç | Gövde / sorgu | Yanıt |
|---|---|---|
| GET `.../contract-vendors` | `active?` (`all` varsayılan, `1`, `0`), `q?` (ad / yetkili kişi / telefon; Türkçe ve büyük-küçük harf duyarsız; aramada en az 3 rakam varsa telefon yalnız rakamlarıyla da karşılaştırılır: "02124445566" -> "0212 444 55 66") | `{ items:[Vendor] }` (ada göre; sayfalama yok, en çok 500) |
| POST `.../contract-vendors` (201) | `name, category, contact_name?, phone?, email?, tax_no?, note?` | `{ vendor }` |
| PATCH `.../contract-vendors/:id` | en az biri: aynı alanlar + `is_active` (boş / null isteğe bağlı alan siler) | `{ vendor }` |
| GET `.../contracts` | `state?` (`all` varsayılan, `aktif`, `yaklasiyor`, `sona_erdi`, `feshedildi`), `vendor_id?`, `category?`, `q?` (başlık / firma adı), `cursor?`, `limit?` (50, en çok 200) | `{ items:[Contract], next_cursor }` |
| GET `.../contracts/summary` | - | `{ active, expiring_soon, expired, terminated }` |
| GET `.../contracts/:id` | - | `{ contract }` |
| POST `.../contracts` (201) | `vendor_id, title, category?, start_date, end_date?, notice_days?, remind_before_days?, amount?, period?, auto_renew?, note?` | `{ contract }` |
| PATCH `.../contracts/:id` | en az biri: aynı alanlar + `status` (`feshedildi` -> terminated_at = şimdi; `aktif` -> yeniden etkin, terminated_at temizlenir) | `{ contract }` |

**Vendor**: `{ id, name, category, contact_name, phone, email, tax_no, note, is_active, contract_count, created_at, updated_at }` (`contract_count`: firmanın bu sitedeki TÜM sözleşmeleri, feshedilenler dahil).

**Contract**: `{ id, vendor_id, vendor_name, title, category, start_date "YYYY-MM-DD", end_date "YYYY-MM-DD"|null, notice_days, remind_before_days, amount "1250.00"|null (METİN), currency "TRY", period|null, auto_renew, status "aktif"|"feshedildi", state, days_left int|null, notice_deadline "YYYY-MM-DD"|null, terminated_at ISO|null, note|null, created_by_name|null, created_at, updated_at }`. `created_by_name` silinmiş / bağı kopmuş kullanıcıda "Silinmiş Kullanıcı".

Kurallar ve ayrıntılar:
- **Sıralama ve sayfalama (sözleşmeden sapma):** liste `end_date ARTAN, bitişsizler EN SONDA, sonra id` sırasıyladır. Bu sırada `before_id` imleci çalışmadığı için sayfalama **opak `cursor`** iledir: ilk istek `cursor`suz; yanıttaki `next_cursor` (metin) bir sonraki isteğe `?cursor=` olarak AYNEN verilir; son sayfada `next_cursor: null`. İmleç istemci için anlamsız bir metindir (içeriğine güvenilmemeli); bozuk imleç `400 INVALID_FIELD { field: "cursor" }`. `next_before_id` alanı YOKTUR; `before_id` gönderilirse `400 INVALID_FIELD { field: "before_id" }` (sessizce yok sayılıp hep ilk sayfa dönmesin).
- **Özet** sayıları `state` ile AYNI kuralla hesaplanır ve AYRIKTIR: `active` = state `aktif`, `expiring_soon` = `yaklasiyor`, `expired` = `sona_erdi`, `terminated` = `feshedildi`; toplamları sitedeki sözleşme sayısıdır ("aktif + yaklaşan" isteyen istemci ikisini toplar).
- POST'ta `category` verilmezse firmanın kategorisi kullanılır. Varsayılanlar: `notice_days` 30, `remind_before_days` 30, `auto_renew` false, `currency` TRY (istemciden alınmaz).
- `amount`: sayı (`1250.5`) ya da metin (`"1250.50"`, `"1250,50"`); 0 ya da pozitif, en çok 12 tam ve 2 ondalık basamak; yanıtta her zaman 2 ondalıklı METİN.
- Tarihler yalnız `YYYY-MM-DD` (1990-2100, gerçek gün). `end_date >= start_date`; PATCH'te yalnız biri değişse bile kayıttaki diğeriyle birlikte denetlenir (`400 INVALID_FIELD { field: "end_date" }`).
- Telefon serbest biçimdir (santral, 444, sabit hat): rakam, boşluk ve `+ ( ) - . /`; 3-20 rakam; olduğu gibi saklanır. E-posta küçük harfe çevrilir. Vergi no: harf, rakam, boşluk, tire (≤20).
- Pasif firmaya yeni sözleşme eklenemez ve sözleşme pasif firmaya taşınamaz (`409 VENDOR_INACTIVE`); pasife alma mevcut sözleşmeleri DEĞİŞTİRMEZ. Firma adı sitede tekildir (`409 VENDOR_NAME_TAKEN`; büyük/küçük harf duyarsız; kendi adını değiştirmek serbest).
- Aynı değerlere PATCH değişiklik yapmaz (200, audit yazılmaz, `updated_by` değişmez). Feshedilmiş sözleşme de düzenlenebilir (not, tarih...).

## Yetki matrisi
| Rol | GET (firma, liste, özet, ayrıntı) | POST / PATCH |
|---|---|---|
| Süper / Yönetici (site_manager_sites, etkin SITE_OWNER / SITE_ADMIN) | evet | evet |
| Kurul (BOARD_MEMBER) | evet (salt okur) | 403 FORBIDDEN_ROLE |
| Görevli (STAFF) | evet (salt okur; firmanın telefonuna ulaşabilmeli) | 403 FORBIDDEN_ROLE |
| Sakin / ilgisiz | 403 FORBIDDEN_ROLE | 403 FORBIDDEN_ROLE |
| Başka sitenin yöneticisi / kurulu | 403 FORBIDDEN_SITE | 403 FORBIDDEN_SITE |

Denetim sırası: biçim (400 `INVALID_SITE_CODE`) -> yetki (403) -> site varlığı (404 `SITE_NOT_FOUND`) -> modül (403 `MODULE_DISABLED`). Her sorguda `site_code` vardır (IDOR yok): başka sitenin firması / sözleşmesi `404 VENDOR_NOT_FOUND` / `404 CONTRACT_NOT_FOUND` (varlık sızmaz). Yazma kilit sırası: `sites FOR KEY SHARE -> users FOR KEY SHARE (silinmiş hesap yazamaz: 401 ACCOUNT_DELETED) -> site işlem kilidi contracts:<site> (ekleme sınırı / ad tekilliği) -> contract_vendors -> site_contracts`.

## Hata kodları
400: `INVALID_FIELD` (`{ field }`: gövde alanı ya da sorgu parametresi adı; gövde nesne değilse / boşsa `field: "body"`), `INVALID_SITE_CODE`. 401 `ACCOUNT_DELETED`. 403: `MODULE_DISABLED`, `FORBIDDEN_ROLE`, `FORBIDDEN_SITE`. 404: `CONTRACT_NOT_FOUND`, `VENDOR_NOT_FOUND`, `SITE_NOT_FOUND`. 409: `VENDOR_NAME_TAKEN`, `VENDOR_INACTIVE`, `LIMIT_REACHED` (`{ limit }`: 500 ya da 2000). 413 `BODY_TOO_LARGE`. 429 hız sınırı (`Retry-After`; yazma 120/saat, okuma 1200/saat, kullanıcı başına).

## Hatırlatmalar (günlük iş)
- Saatte bir tik; İstanbul saatiyle 09:00 ve sonrasında çalışır. Süreçler arası TEK çalışan (oturum advisory kilidi; kilit başkasındaysa tik atlanır).
- Yalnız modülü AÇIK sitelerde; feshedilmemiş sözleşmeler. Kalemler:
  - `bitis`: `end_date − remind_before_days <= bugün <= end_date` (due_date = end_date);
  - `fesih_bildirim`: otomatik yenilenen sözleşmede `notice_deadline − 7 <= bugün <= notice_deadline` (due_date = notice_deadline).
- Her kalem bir kez gider (`contract_reminders` tekilliği); bitiş tarihi değişirse (uzatma) yeni tarih için yeniden hatırlatılır. Site başına günde EN ÇOK BİR e-posta: o gün e-posta almış sitenin yeni kalemleri ertesi güne kalır.
- Alıcılar: sitenin yöneticileri (site_manager_sites + etkin SITE_OWNER / SITE_ADMIN); hesap etkin, silinmemiş, e-postası DOĞRULANMIŞ, dahili adres değil. Her yöneticiye AYRI e-posta (birbirinin adresini görmez). Alıcı yoksa site atlanır (kalem işaretlenmez, sonra alıcı eklenirse pencere içindeyse gider). Kurul / görevli / sakin almaz.
- İçerik (Türkçe, düz metin + HTML): konu `[Site Adı] Sözleşme hatırlatması`; site adı, firma adı, sözleşme başlığı, bitiş tarihi / fesih bildirimi son günü ve kaç gün kaldığı. TUTAR, telefon, not YOKTUR. En çok 50 kalem listelenir, fazlası sayıyla belirtilir.
- Gönderim: kalemler önce işaretlenir (`claimed_at`), sonra e-postalar gider; İLK başarılı gönderimden HEMEN sonra `sent_at` yazılır (süreç bundan sonra ölse bile yeniden gönderilmez), tur sonunda `recipients` (başarılı alıcı sayısı) yazılır. Hiçbir yöneticiye gitmediyse işaret geri alınır (sonraki tikte yeniden denenir).
- Yarıda kalan tur (süreç ölümü / DB hatası, gönderim ile `sent_at` arası): o günün gönderilmemiş talebi "gönderilmiş olabilir" sayılır ve site o gün yeniden e-posta ALMAZ; önceki günlerden kalan gönderilmemiş talepler tur başında bırakılır ve kalem ertesi gün bir kez daha denenir (en kötü durumda bir yönetici aynı hatırlatmayı ertesi gün ikinci kez alır; hiçbir gün iki e-posta gitmez).
- Kilit sırası: `contract_reminders`'a her yazma (talep, `sent_at`, `recipients`, geri alma, eski talep silme) site başına kısa bir işlemdir ve ilk ifadesi `SELECT 1 FROM sites ... FOR KEY SHARE`dir (diğer yazıcılarla aynı sıra; site silme ile 40P01 olmaz). Site tur sırasında silinirse kalan yöneticilere gönderilmez. Zaman damgaları DB saati yerine turun saatinden yazılır.
- SMTP yapılandırılmamışsa iş hiç başlamaz; `CONTRACT_REMINDERS_DISABLED=1` (ya da `ANNOUNCEMENT_SCHEDULER_DISABLED=1`) ile kapatılır. Günlüğe yalnız sayılar yazılır.

## Audit ve gizlilik
Audit eylemleri: `contract_vendor.created` (details: category), `contract_vendor.updated` (details: `fields` + değiştiyse `is_active`, `category`), `contract.created` (details: vendor_id, category, auto_renew, has_end_date), `contract.updated` (details: `fields` + durum değiştiyse `from` / `to`, firma değiştiyse `vendor_id`). Firma adı, yetkili kişi, telefon, e-posta, vergi no, başlık, tutar ve not audit `details` alanına ve günlüğe YAZILMAZ.

## Hesap silme ve dışa aktarma
- Yönetici hesabı silinince eklediği / güncellediği firmalar ve sözleşmeler SİLİNMEZ (siteye aittir); `created_by` / `updated_by` tombstone'u gösterir ya da FK ile NULL olur, ad "Silinmiş Kullanıcı" görünür. users FK politika tablosunda (qa_platform_pg.mjs A6) üç FK de TOMBSTONE olarak kayıtlıdır.
- Kişisel veri dışa aktarmasına (`/me/data-export`) bu modülden bölüm EKLENMEZ: kayıtlar kullanıcının değil sitenin verisidir (firma kayıtları tüzel kişiler / site sözleşmeleridir).

## Doğrulama
- Birim testleri: `test/contracts_schema.test.js`, `test/contracts_common.test.js`, `test/contracts_routes.test.js`, `test/contracts_reminders.test.js`.
- Gerçek PostgreSQL: `QA_ONLY=chain,live,contracts node scripts/qa_platform_pg.mjs` (şema, yetki matrisi, IDOR, eşzamanlı sınırlar, İstanbul gün sınırı, imleç, hatırlatma idempotansı / modül kapalı / SMTP yok, site silme CASCADE, hesap silme; 40P01 = 0).
