# İşletme Projesi (Bütçe) - F7

Modül kodu `budget` (varsayılan KAPALI; süper açar, yönetici talep eder). Migration 059, kod: `server/src/modules/budget_*.js`, istemci: `lib/ui/views/budget_view.dart`.
Hukuki süreler ve adımlar KMK m.37 (7579 sayılı Kanun ile değişik) ve karar F7'ye dayanır. [AVUKAT DOĞRULASIN]

## Tablolar (059, ekleyici)

- `budget_projects`: site, yıl, başlık, `status` (`taslak` -> `teblig` -> `kesin`), geçici proje (`is_provisional`, `provisional_start`, `provisional_until`), tebliğ (`notified_at`, `objection_days`, `objection_ends`), kesinleşme (`finalized_at/by`). (site, yıl) başına tek KESİN proje (kısmi tekil indeks).
- `budget_items`: proje, `category_id` (finansın `expense_categories`), kategori adı (anlık), `annual_minor` (kuruş, 0..1e12), proje başına kategori tekil.
- Silme: site silinince CASCADE; kullanıcı silinince SET NULL; kullanımdaki gider kategorisi RESTRICT.

## Durum makinesi

| Eylem | Kural |
| --- | --- |
| Taslak | Başlık, not ve kalemler serbestçe değişir; silinebilir. |
| `notify` Taslak -> Tebliğ | En az bir kalem; tebliğ tarihi bugünden ileri olamaz (varsayılan bugün). `budget.objection_days` kurulu değeri projeye yazılır; `objection_ends = tebliğ + gün`. |
| `revert` Tebliğ -> Taslak | İtiraz üzerine revize; tebliğ bilgileri silinir. |
| `finalize` Tebliğ -> Kesin | `bugün > objection_ends` olmadan 409 `BUDGET_OBJECTION_OPEN`; aynı yıl başka kesin proje 409 `BUDGET_YEAR_FINAL_EXISTS`. Kesin proje değişmez, silinmez. |

Geçici proje: oluştururken `provisional_until = başlangıç + budget.provisional_max_days` (varsayılan 90, üst sınır 90). Kesin olmayan geçici projede kalan gün = `provisional_until - bugün` (0'da kalır). Kalan gün `getBudgetAttention(siteCode)` (budget_service.js) ile verilir: `{ provisional: { project_id, year, title, remaining_days, until } | null }`; yönetici ana sayfasının dikkat özeti (2F) bu işlevi çağırır. Liste ucu da aynı değeri `attention` alanında döner.

## Uçlar (`/manager/sites/:siteCode/budget-projects`)

`GET` (liste + attention), `POST` (201), `GET /:id`, `PATCH /:id` (başlık/not), `PUT /:id/items` (`{items:[{category_id, annual_minor}]}` toptan), `POST /:id/notify|revert|finalize`, `DELETE /:id` (yalnız taslak), `GET /:id/comparison`.
Yetki: yönetici/süper yazar; BOARD_MEMBER salt okur; STAFF ve sakin 403 `FORBIDDEN_ROLE`; başka site 403 `FORBIDDEN_SITE`; modül kapalıysa 403 `MODULE_DISABLED`. Taslak dışı yazma 409 `BUDGET_WRONG_STATUS`.

## Planlanan - gerçekleşen

`comparison`: kalemler planlanan; aynı yılın (1 Ocak - 31 Aralık, `expense_date`) iptal edilmemiş (`expense_voids` olmayan) giderleri kategori bazında gerçekleşen. Kalemi olmayan ama gideri olan kategori planlanan 0 ile gelir. `variance_minor = gerçekleşen - planlanan` (artı = aşım), `used_pct` planlanan 0 ise null.

## PDF ve ekran

PDF istemcide üretilir (`pdf_budget_service.dart`, gömülü Roboto, karar defteri ile aynı teslim yolu). Ekran: menü "İşletme Projesi" (Site hizmetleri); gider kategorileri finans ucundan (`expense-categories`) gelir, bu yüzden kalem girişi için finans modülü de açık olmalıdır.

## Yakında

Teblig için belge ekleme, tebliğ edilen bütçenin sakinlere duyurulması, aidatın bütçeden otomatik hesaplanması, bütçenin e-postayla gönderimi henüz yok.
