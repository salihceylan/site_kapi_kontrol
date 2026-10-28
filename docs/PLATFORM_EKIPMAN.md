# Ekipman, Bakım ve Teklifler (`equipment` modülü)

Migration 068 (`server/migrations/068_equipment.sql` = `server/src/modules/equipment_schema.js`). TEMEL modül (2026-10-28, AGENTS.md Kural 25): `equipment` her sitede hep açıktır; talep edilmez, kapatılamaz (`site_modules` satırı kurulumda yazılır, `migrations/082` mevcut siteleri doldurur).

Teklif eklemeleri (yalnız `equipment_quotes`; yeni tablo yok, mevcut satırlar değişmez): **098** karşılaştırma alanları (`migrations/098_equipment_quote_compare.sql`), **099** onaylı teklif revizyonu + değişmezlik (`migrations/099_equipment_quote_revisions.sql`). İkisinin tek kaynağı `server/src/modules/equipment_quote_schema.js` (`QUOTE_STEPS`; migration dosyaları adımların birleşimidir, `db.js` `ensureQuoteSchema` ile katalog kontrollü uygular). Gerçek PostgreSQL sınaması: `server/scripts/qa_equipment_quotes_pg.mjs`.

## Tablolar (hepsi ekleyici, FK korumalı; site silinince CASCADE)

| Tablo | İçerik |
|---|---|
| `equipment_items` | ekipman: tür (serbest metin; varsayılanlar asansor, interkom, kamera, bariyer, yangin_algilama, hidrofor, jenerator, kazan, havuz), ad, konum, firma, seri no, kurulum tarihi, aktif |
| `equipment_plans` | bakım planı: başlık, sıklık (1/3/6/12 ay), `legal` (yasal kontrol), `next_due`, `last_done` |
| `equipment_maintenance_logs` | bakım kaydı (YALNIZ EKLEME): tarih, firma adı, maliyet (kuruş), gider no, not |
| `equipment_expense_links` | gider -> ekipman bağlantısı (gider satırı değişmez olduğundan yan tablo; bir gider tek ekipmana) |
| `equipment_quotes` | teklif: konu, firma, tutar (kuruş), geçerlilik, belge notu, durum (open/accepted/rejected), kabul biçimi, oluşan gider / sözleşme no; **098:** `delivery_days` (teslim süresi, gün 0-1095), `note` (kapsam / not, ≤ 500), `vat_included` (NULL belirtilmedi, TRUE KDV dahil, FALSE KDV hariç); **099:** `revision_no` (1 = ilk sürüm), `previous_id` (önceki sürüm; `(site_code, previous_id) -> (site_code, id)` bileşik FK = aynı site), `revision_reason` (değişiklik gerekçesi) |

## Uçlar (`/manager/sites/:siteCode/...`)

`GET equipment/meta`, `GET equipment`, `POST equipment`, `GET|PATCH equipment/:id`, `POST equipment/:id/plans`, `PATCH equipment/plans/:planId`, `POST equipment/:id/logs`,
`GET equipment/due?days=60` (yaklaşan / geciken bakım ve yasal kontroller), `POST|DELETE equipment/:id/expense-links[/:expenseId]`,
`GET equipment/expense-breakdown?from=YYYY-AA&to=YYYY-AA`, `GET|POST quotes`, `POST quotes/:id/reject`, `POST quotes/:id/accept`,
`PATCH quotes/:id` (açık teklifi yerinde düzenle), `POST quotes/:id/revise` (onaylı teklifte yeni sürüm, 201), `GET quotes/:id/history` (tüm sürümler).

## Kurallar

- Yetki: yönetici / süper yazar; kurul ve görevli salt okur; sakin ve ilgisiz `403 FORBIDDEN_ROLE`; başka site `403 FORBIDDEN_SITE`; modül kapalıysa `403 MODULE_DISABLED`. Sakine açık uç yoktur.
- Planlı bakım kaydı (`plan_id`) planın `last_done` değerini ve `next_due = bakım tarihi + sıklık` değerini ilerletir. Gelecek tarihli bakım kaydı reddedilir. Kayıt silinmez ya da değiştirilmez.
- Asansör, yangın algılama ve kazan için istemci yıllık yasal kontrol planı önerir (`legal = true`).
- Gider kırılımı (2E): net gider = gider - iptal (gider analiziyle aynı birleşim), ekipman bazında; ayrıca "bağlanmamış" ve toplam. `GET finance/reports/expense-analysis` yanıtına `equipment_breakdown` alanı (analiz penceresi) eklenir; modül kapalıysa alan yoktur.
- Teklif kabulü: `as: "expense"` -> `createExpense` (kategori + hesap istemciden; `idempotency_key = quote-<id>`; teklifte ekipman varsa gider ekipmana bağlanır; Finans modülü açık olmalı), `as: "contract"` -> `createContract` (firma + başlangıç tarihi istemciden; tutar tekliften; Sözleşmeler modülü açık olmalı). Kabul atomik "claim" ile yapılır (çift kabul `409 QUOTE_NOT_OPEN`), başarısızlıkta teklif açık kalır; aynı konudaki diğer açık teklifler reddedilir. Süresi dolan teklif `409 QUOTE_EXPIRED`.
- **Teklif karşılaştırma alanları (P2-10, 098):** teklif `delivery_days`, `note`, `vat_included` taşır (hepsi opsiyonel; eski istemci göndermez ve görmez). Liste yanıtı her teklife `lowest` (en düşük), `fastest` (en kısa teslim; en az iki tekliften süre girilmişse) ve `basis_mixed` ekler. İşaretler yalnız aynı konudaki AÇIK, süresi dolmamış, ilk sürüm tekliflerden hesaplanır (bekleyen revizyon rakip değil değişikliktir). Konudaki teklifler FARKLI KDV esasındaysa (dahil / hariç / belirtilmedi karışık) tutarlar kıyaslanamaz: hiçbiri `lowest` olmaz, `basis_mixed = true` döner. İstemci: aynı konuda iki ya da daha çok teklif varsa yan yana karşılaştırma tablosu (tutar, KDV, geçerlilik, teslim süresi, kapsam / not, durum). Doğrulama: `delivery_days` 0..1095 tam sayı, `note` ≤ 500, `vat_included` boolean ya da null (`400 INVALID_FIELD { field }`).
- **Onaylı teklif revizyonu (P2-9, karar K14: yeni sürüm + önceki sürüme bağ; zeyilname değil, 099):**
  - Kabul edilmiş (onaylı) teklif YERİNDE DEĞİŞMEZ: servis `PATCH` onaylı / reddedilmiş teklifte `409 QUOTE_LOCKED` döner ve veritabanı tetikleyicisi (`trg_equipment_quotes_locked`) SQL ile de UPDATE / DELETE'i reddeder. Tek istisnalar kabul akışının kendi adımlarıdır: gider / sözleşme bağlantısının bir kez yazılması, gider / sözleşme oluşmadıysa kabulün geri alınması, `created_by` SET NULL (kullanıcı silme) ve site silinirken CASCADE.
  - Değişiklik `POST quotes/:id/revise { reason, amount_kurus?, valid_until?, delivery_days?, note?, vat_included?, document_note? }` ile YENİ SÜRÜM satırı olur: konu / firma / ekipman ve gönderilmeyen alanlar önceki sürümden kopyalanır, `previous_id` önceki sürümü gösterir, `revision_no` artar, `reason` (zorunlu, 3-300 karakter) saklanır. Yeni sürüm AÇIKTIR ve yeniden yönetici kararı bekler; reddedilirse önceki onay geçerli kalır. Hiçbir alan değişmediyse `400 NO_CHANGE`.
  - Revize edilebilenler: onaylı son sürüm ve onaylı bir sürümden türemiş reddedilmiş son revizyon (`revisable`). Açık teklif revize edilmez, `PATCH quotes/:id` ile yerinde düzenlenir (`409 QUOTE_NOT_REVISABLE`); ilk sürümü reddedilmiş teklif revize edilemez (yeni teklif girilir). Bir sürümün en çok BİR halefi olur: önceki sürümden ikinci revizyon ya da eşzamanlı çift istek `409 QUOTE_NOT_LATEST` (site başına advisory kilit + `FOR UPDATE` + benzersiz `previous_id` dizini). Bir teklif en çok 50 sürüm alır; sürümler site başına 3000 teklif sınırına dahildir.
  - Liste yalnız EN SON sürümleri döner; her teklife `revision_no`, `previous_id`, `revision_reason`, `version_count`, `has_history`, `editable`, `revisable` ve (son sürüm onaylı değilse) zincirdeki en yakın onaylı sürümün özeti `approved_version` eklenir. `GET quotes/:id/history` zincirin tüm sürümlerini eskiden yeniye (`items`, `latest_id`, `approved_id`) verir; zincirdeki herhangi bir sürümün kimliği yeter, başka sitenin teklifi `404 NOT_FOUND`.
  - Revizyonun kabulü gider / sözleşmeyi DEĞİŞTİRMEZ, AYRI bir kayıt üretir. Zincirde gider / sözleşmeye dönüşmüş onaylı bir önceki sürüm varsa kabul `acknowledge_previous: true` ile bilerek onaylanmalıdır, aksi hâlde `409 PREVIOUS_VERSION_RECORDED { previous_quote_id, previous_revision_no, previous_expense_id, previous_contract_id }` (çift sayım koruması; önceki kaydı gerekirse Finans / Sözleşmeler bölümünden siz iptal edin ya da feshedin). Oluşan gider / sözleşme başlığına "(revizyon N)" eklenir.
  - Kabulde gider / sözleşme, kabul anında kilitlenen satırdan okunan tutar ve konuyla oluşur (arada yerinde düzenleme olsa bile tutarsızlık olmaz); geçerlilik de aynı atomik ifadede denetlenir (`409 QUOTE_EXPIRED`).
  - Eski onaylı fiyat "tarihli fiyattır, güncel fiyat değildir": istemci onaylı teklifte bu etiketi gösterir.
  - Denetim kaydı: `quote.updated`, `quote.revised`, `quote.accepted` yalnız alan adlarını ve (tutar değiştiyse) eski / yeni tutarı (kuruş) taşır; kapsam, not ve gerekçe metni günlüğe YAZILMAZ (gerekçe teklif satırındadır).
- Para tamsayı kuruştur. Tahsilat / defter yazılmaz.

## Yakında…

Telefon / e-posta ile otomatik bakım ve yasal kontrol hatırlatması, teklife dosya (belge) yükleme, teklif PDF çıktısı.
