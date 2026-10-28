# Ekipman, Bakım ve Teklifler (`equipment` modülü)

Migration 068 (`server/migrations/068_equipment.sql` = `server/src/modules/equipment_schema.js`). TEMEL modül (2026-10-28, AGENTS.md Kural 25): `equipment` her sitede hep açıktır; talep edilmez, kapatılamaz (`site_modules` satırı kurulumda yazılır, `migrations/082` mevcut siteleri doldurur).

## Tablolar (hepsi ekleyici, FK korumalı; site silinince CASCADE)

| Tablo | İçerik |
|---|---|
| `equipment_items` | ekipman: tür (serbest metin; varsayılanlar asansor, interkom, kamera, bariyer, yangin_algilama, hidrofor, jenerator, kazan, havuz), ad, konum, firma, seri no, kurulum tarihi, aktif |
| `equipment_plans` | bakım planı: başlık, sıklık (1/3/6/12 ay), `legal` (yasal kontrol), `next_due`, `last_done` |
| `equipment_maintenance_logs` | bakım kaydı (YALNIZ EKLEME): tarih, firma adı, maliyet (kuruş), gider no, not |
| `equipment_expense_links` | gider -> ekipman bağlantısı (gider satırı değişmez olduğundan yan tablo; bir gider tek ekipmana) |
| `equipment_quotes` | teklif: konu, firma, tutar (kuruş), geçerlilik, belge notu, durum (open/accepted/rejected), kabul biçimi, oluşan gider / sözleşme no |

## Uçlar (`/manager/sites/:siteCode/...`)

`GET equipment/meta`, `GET equipment`, `POST equipment`, `GET|PATCH equipment/:id`, `POST equipment/:id/plans`, `PATCH equipment/plans/:planId`, `POST equipment/:id/logs`,
`GET equipment/due?days=60` (yaklaşan / geciken bakım ve yasal kontroller), `GET equipment/:id/work-history?before_id&limit` (servis geçmişi: ekipmana bağlı iş kayıtları, migration 096), `POST|DELETE equipment/:id/expense-links[/:expenseId]`,
`GET equipment/expense-breakdown?from=YYYY-AA&to=YYYY-AA`, `GET|POST quotes`, `POST quotes/:id/reject`, `POST quotes/:id/accept`.

## Kurallar

- Yetki: yönetici / süper yazar; kurul ve görevli salt okur; sakin ve ilgisiz `403 FORBIDDEN_ROLE`; başka site `403 FORBIDDEN_SITE`; modül kapalıysa `403 MODULE_DISABLED`. Sakine açık uç yoktur.
- Planlı bakım kaydı (`plan_id`) planın `last_done` değerini ve `next_due = bakım tarihi + sıklık` değerini ilerletir. Gelecek tarihli bakım kaydı reddedilir. Kayıt silinmez ya da değiştirilmez.
- Asansör, yangın algılama ve kazan için istemci yıllık yasal kontrol planı önerir (`legal = true`).
- Gider kırılımı (2E): net gider = gider - iptal (gider analiziyle aynı birleşim), ekipman bazında; ayrıca "bağlanmamış" ve toplam. `GET finance/reports/expense-analysis` yanıtına `equipment_breakdown` alanı (analiz penceresi) eklenir; modül kapalıysa alan yoktur.
- Teklif kabulü: `as: "expense"` -> `createExpense` (kategori + hesap istemciden; `idempotency_key = quote-<id>`; teklifte ekipman varsa gider ekipmana bağlanır; Finans modülü açık olmalı), `as: "contract"` -> `createContract` (firma + başlangıç tarihi istemciden; tutar tekliften; Sözleşmeler modülü açık olmalı). Kabul atomik "claim" ile yapılır (çift kabul `409 QUOTE_NOT_OPEN`), başarısızlıkta teklif açık kalır; aynı konudaki diğer açık teklifler reddedilir. Süresi dolan teklif `409 QUOTE_EXPIRED`.
- Para tamsayı kuruştur. Tahsilat / defter yazılmaz.

## Servis geçmişi (iş kayıtları)

`GET /manager/sites/:siteCode/equipment/:id/work-history?before_id&limit` (migration 096): ekipmana bağlanmış İş Takibi kayıtları (docs/PLATFORM_IS_TAKIBI.md "Ekipman bağı"), en yeni üstte. Yetki ekipman uçlarıyla aynıdır (yönetici / süper / kurul / görevli okur; sakin ve ilgisiz `403 FORBIDDEN_ROLE`; başka site `403 FORBIDDEN_SITE`). İş kaydı görünürlüğü iş takibinin kuralıdır: görevli yalnız kendine atanmış, atanmamış ya da yetim atamalı kayıtları görür; talebi açanın kimliği / telefonu bu uçta HİÇ yoktur. Başka sitenin / olmayan / geçersiz kimlikli ekipman `404 NOT_FOUND`; geçersiz `before_id` / `limit` `400 INVALID_QUERY`.
Yanıt: `{ equipment:{id,kind,name,is_active}, work_tracking_enabled, items:[{ id, title, category, status, priority, created_at, updated_at, closed_at, resolved_at, attachment_count, before_count, after_count }], next_before_id, counts:{ total, open } }`. `resolved_at` = ilk `-> cozuldu` durum olayının anı; fotoğraf sayıları yalnız HAZIR olanlardır (önce / sonra / toplam); `counts.open` = durumu cozuldu / kapandi / iptal DIŞINDA olanlar. İş Takibi modülü kapalıysa 403 değil, `work_tracking_enabled: false` + boş liste döner (ekipman kartı bozulmasın). Sayfalama `before_id` imleci + `limit` (1-100, varsayılan 30).
Uygulamada ekipman kartında "Servis geçmişi (iş kayıtları)" bölümü olarak görünür ("Bakım kayıtları" ayrı bölümdür).

## Yakında…

Telefon / e-posta ile otomatik bakım ve yasal kontrol hatırlatması, teklife dosya (belge) yükleme, teklif PDF çıktısı.
