# Yönetim Firması, Deneme Süresi ve Ortaklık Payı (Y1 + Y2, İP-5A)

Temel yapı: çalışan şema + uçlar + ekran. Fiyat depoda YOKTUR; aylık bedeli süper kullanıcı girer. Pay dökümü yalnız bilgi amaçlıdır (fatura/ödeme üretmez).

## Tablolar (migration 062; `db.js` `ensureManagementCompanySchema` ile aynı DDL, ekleyici ve idempotent)

- `management_companies(id, name, partner_share_bp 0..10000, is_active, created_by, created_at)`.
- `management_company_members(company_id, user_code, role owner|staff)`: firma sahibi ve personel.
- `management_company_sites(site_code PK, company_id, monthly_fee_minor NULL, linked_at)`: bir site en çok bir firmaya bağlıdır.
- `site_subscriptions.trial_ends_at` (yeni sütun) + `platform_settings` anahtarı `subscription.trial_days` (`{"days":60}` tohum).

## Uçlar (`management_company_routes.js`, `platformServicesRouter`)

| Uç | Kim | Not |
|---|---|---|
| `GET /companies`, `GET /companies/:id` | üye / süper | Üye değilse 404. Personel bedeli görmez. |
| `GET /companies/:id/sites-table` | firma sahibi / süper | Site başına dört sayı: daire sayısı, bu ay tahsilat oranı (baz puan), açık borç (kuruş), borçlu daire sayısı. En düşük oran üstte; oransız site sonda. |
| `GET /companies/:id/share-statement?month=YYYY-MM` | firma sahibi / süper | Pay = aylık bedel x pay oranı. Ay sonunda deneme sürüyorsa pay 0. `informational: true`. |
| `POST /companies/:id/members`, `DELETE .../members/:userCode` | firma sahibi (personel) / süper (sahip de) | Kayıtlı e-postayla eklenir; son sahip çıkarılamaz (409). |
| `POST /admin/companies`, `PATCH /admin/companies/:id` | süper | Ad, ortaklık payı, aktiflik. |
| `POST/DELETE /admin/companies/:id/sites[/:siteCode]` | süper | Siteyi bağlar (başka firmadaysa 409) ve aylık bedeli yazar. |
| `GET/PUT /admin/trial-settings` | süper | Varsayılan deneme süresi (0-365 gün; 0 = deneme yok). |
| `PUT /admin/sites/:siteCode/trial` | süper | `{days}` ya da `{trial_ends_at:null}`. |

## Kurallar

- Yeni açılan her site (`site_service.js`, `site_setup_core.js`) abonelik satırıyla birlikte deneme alır: durum `trial`, bitiş = bugün + ayar günü. Hata siteyi açmayı engellemez (SAVEPOINT). Mevcut sitelere dokunulmaz.
- Deneme bitiminde otomatik işlem YOK ("Yakında…"): durum değişmez, tahsilat/erişim kesilmez.
- Tablo okuması yalnız toplulaştırılmış sayılardır; firma sahibine sitenin kişi/daire ayrıntısı verilmez. Finans modülü kapalı/boş sitede oran null, borç 0.
- Denetim kaydı: `management_company.*`, `subscription.trial_days_updated`, `subscription.site_trial_updated`.

## İstemci

`lib/ui/views/management_company_view.dart` (Ayarlar paneli > "Yönetim Firması": süper kullanıcıda her zaman, firma üyesinde görünür), `lib/services/management_company_api.dart`. Yardım konusu `management_company`.

## Yakında…

Bireysel yöneticiye aynı fiyat listesi, deneme bitişinde otomatik işlem, komisyon faturası, banka anlaşması (kod yok), firma sahibinin kendi sitesini bağlaması (şimdilik süper).
