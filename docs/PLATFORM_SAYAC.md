# Sayaç Okuma ve Faturalandırma (`metering`, migration 061)

Modül varsayılan KAPALI; yönetici modül talep eder, süper kullanıcı açar. Sakine açık uç yoktur. Borçlandırma ayrıca `finance` modülünü ister.

## Tablolar (hepsi ekleyici; defter şemasına dokunulmaz)

- `meters` (site, daire, `kind` water/electricity/heat/hot_water, `serial_no`, `is_active`). (site, tür, küçük harf seri no) tekil.
- `meter_readings` (sayaç, tarih, `value NUMERIC(14,3)`, `source` manual/file). (sayaç, tarih) tekil. Okuma önceki tarihli okumadan küçük, sonraki tarihli okumadan büyük olamaz.
- `meter_billings` (tür, yöntem, `period_from`/`period_to`, toplam kuruş, `params`, `preview_hash`, `idempotency_key`, parmak izi) ve `meter_billing_lines` (daire, tüketim, tutar, hesap, `ledger_entry_id` FK'siz bilgi alanı).

## Uçlar (`/manager/sites/:siteCode/...`; yönetici/süper yazar, kurul salt okur, diğerleri 403)

`meter-apartments`, `meters` (GET/POST, PATCH `:id`), `meters/:id/readings` (GET/POST, DELETE `:readingId`), `meter-readings/import`, `meter-billings/preview`, `meter-billings` (POST/GET, GET `:id`).

- Okuma silme: okumanın tarihini kapsayan (`period_to >=` tarih) faturalandırma varsa 409 `READING_LOCKED`.
- Dosya aktarımı: istemci CSV/XLSX'i okur, sunucuya `{kod, değer}` satırları gider (en çok 5000). Kod önce sayaç seri no'su, sonra `Blok - No` ya da yalnız kapı no eşleşir (dairenin o türde TEK etkin sayacı olmalı). `dry_run: true` yazmaz. Gerçek aktarımda hatasız satırlar yazılır, hatalılar raporlanır. Aynı değer zaten kayıtlıysa `same`; farklıysa `READING_EXISTS`.

## Dağıtım kuralları

Tüketim = kapanış okuması (tarih <= dönem sonu) - açılış okuması (tarih <= dönem başı); kapanış açılıştan sonra olmalı, azalan okuma eksik sayılır. Bir dairenin herhangi bir sayacı eksikse daire eksiktir.

- `unit_price`: tutar = tüketim x birim fiyat (kuruş/birim), en yakın kuruşa yuvarlanır.
- `invoice`: fatura tutarı tüketime orantılı, en büyük kalan yöntemiyle (toplam birebir).
- `heat` (yalnız ısı): `heat.measured_share_pct` (varsayılan 70) ölçüme, kalan (`heat.area_share_pct`, 30) brüt m²'ye göre. Alanı olmayan daire alan payı almaz (eksik listesinde `area_missing`).
- Eksik daire varsa kayıt 409 `READINGS_INCOMPLETE`; `skip_missing: true` ile eksikler atlanır.

## Deftere yazma

`POST meter-billings`: önizleme özeti (`expected_total_minor`, `expected_count`, `expected_hash`) ve `idempotency_key` zorunlu; okumalar değiştiyse 409 `PREVIEW_STALE`. Aynı anahtar + aynı istek tekrar gönderimde çift borç yazmaz; farklı istek 409. Aynı türde çakışan tarih aralığı 409 `BILLING_OVERLAP`. Borç satırı `ledger_entries`'e `charge` olarak, dairenin OTURANIN hesabına (`occupantAccount`) ve açık finans dönemine yazılır (kapalı dönemde 409). Düzeltme Finans ekranından ters kayıtla yapılır; tahsilat yalnız `finance_parties.postPayment` ile.

## Yakında

Fotoğrafla okuma (4C), sayaç değişimi (eski sayacı kapatıp yenisini açmak: şimdilik pasife alıp yeni sayaç eklenir), ortak alan sayaçları, süper kullanıcı için site seçmeli sayaç ekranı.
