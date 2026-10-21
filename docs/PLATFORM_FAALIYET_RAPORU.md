# Faaliyet Raporu (R2) - modul `annual_report` (varsayilan KAPALI)

Yonetici bir yil secer; sistem dokuz bolumu kayitlardan doldurur, yonetici her bolumu duzenler, taslak saklanir, PDF alinir.

## Tablo (migration 069, db.js ile ayni DDL, idempotent)
`annual_reports(site_code, year, edits JSONB, growth_bp, updated_by, ...)`, `UNIQUE(site_code, year)`. Yalniz yonetici duzenlemeleri saklanir; sistem verisi her okumada hesaplanir (defter, gider vb. tablolara yazilmaz).

## Uclar (yonetici/super yazar, kurul salt okur; kapaliysa 403 MODULE_DISABLED)
- `GET /manager/sites/:siteCode/annual-report?year=&growth_bp=` -> `{ year, draft{edits, growth_bp, saved}, sections{...} }`; yil yoksa gecen yil.
- `PUT /manager/sites/:siteCode/annual-report/:year` `{ edits:{bolum:metin}, growth_bp }` (kurul 403).

## Bolumler ve kaynaklar
general (sites, site_blocks, apartments) / finance (computeIncomeExpense + butce karsilastirmasi, `budget` acikken) / collections (ledger_entries: tahakkuk, tahsilat, yil sonu acik borc) / works (work_items, work_item_attachments) / maintenance (bakim kayitlari + bakim sozlesmeleri; ekipman envanteri "Yakinda...") / contracts (site_contracts) / decisions (board_decisions, yalniz `kesin`) / announcements (yayimlanan) / forecast (yilin gideri x (1 + artis); sonraki yil butcesi varsa gosterilir).
Ilgili modul kapaliysa bolum `available:false`. Para tamsayi kurus. Duzenleme metni en fazla 4000 karakter; gunluge metin yazilmaz.

## Uygulama
`lib/ui/views/annual_report_view.dart` (menu: Faaliyet Raporu, Site hizmetleri), PDF `lib/services/pdf_annual_report_service.dart`. Sistem taslagindan farkli olmayan bolum saklanmaz.
