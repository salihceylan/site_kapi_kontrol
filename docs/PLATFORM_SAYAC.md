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
- `heat` (yalnız ısı): `heat.measured_share_pct` (varsayılan 70) ölçüme, kalan (`heat.area_share_pct`, 30) "alan payı" olarak dağıtılır. m² sistemden kaldırıldığı için alan payının TABANINI KOD SEÇMEZ, YÖNETİM seçer (karar K5, 2026-10-29): istekte isteğe bağlı `area_basis` = `equal` (VARSAYILAN: eşit) | `land_share` (arsa payı) | `person_count` (dairedeki güncel kişi sayısı; `apartment_residencies.is_current`); diğer yöntemlerde `area_basis` verilirse 400 `INVALID_BODY`, bilinmeyen değer 400. Eski «hepsinde arsa payı varsa arsa payı, yoksa eşit» kod kuralı KALDIRILDI: arsa payı tanımlı olsa bile taban seçilmediyse EŞİT dağıtılır. Seçilen tabanın verisi eksik daire (`land_share_missing` / `person_count_missing`) sessizce eşit paya DÜŞÜRÜLMEZ: okuması eksik daire gibi `missing` listesine girer; `skip_missing` ile atlanırsa daire bu faturalandırmaya HİÇ dahil edilmez (ölçüm payı dahil; payı kalan dairelere dağılır, toplam birebir; atlama kararı yöneticinindir ve arayüzde açıkça yazılır), atlanmazsa yazma 409 `AREA_BASIS_INCOMPLETE`. Karma dağıtım yapılmaz (`metering_calc.areaShareItems` / `areaShareGaps`). Seçilen taban önizleme yanıtında `area_basis` ve `params.area_basis`, audit `metering.billing.posted` ayrıntısında yazılır (alan payı %0 ise taban önemsizdir, yazılmaz). Arsa payı paydaları ortak paydaya getirilemeyecek kadar farklıysa 409 `LAND_SHARE_UNSUPPORTED`; seçilen arsa payı tabanında tüm paylar 0 ise 409 `AREA_BASIS_UNUSABLE` (sessizce eşit paya düşülmez). Alan nedeniyle eksik daire (`area_missing`) artık oluşmaz. İstemci: Faturalandır sekmesinde yöntem «Isı payı» iken «Alan payı tabanı» seçicisi (varsayılan Eşit).
- Eksik daire varsa kayıt 409 `READINGS_INCOMPLETE`; `skip_missing: true` ile eksikler atlanır.

## Deftere yazma

`POST meter-billings`: önizleme özeti (`expected_total_minor`, `expected_count`, `expected_hash`) ve `idempotency_key` zorunlu; okumalar değiştiyse 409 `PREVIEW_STALE`. Aynı anahtar + aynı istek tekrar gönderimde çift borç yazmaz; farklı istek 409. Aynı türde çakışan tarih aralığı 409 `BILLING_OVERLAP`. Borç satırı `ledger_entries`'e `charge` olarak, dairenin OTURANIN hesabına (`occupantAccount`) ve açık finans dönemine yazılır (kapalı dönemde 409). Düzeltme Finans ekranından ters kayıtla yapılır; tahsilat yalnız `finance_parties.postPayment` ile.

## Fotoğrafla okuma (4C, migration 070)

Uçlar (`/sites/:siteCode/meter-field/...`; yönetici, süper ve o sitenin etkin görevlisi STAFF; kurul/sakin 403 `FORBIDDEN_ROLE`; `metering` kapalıysa 403 `MODULE_DISABLED`):

- `GET meters?kind=` etkin sayaçlar, daire sırasıyla (son okuma dahil).
- `POST readings` `{ meter_id, date, value, photo_b64?, photo_mime? }` mevcut okuma kurallarıyla (tarih ileri olamaz, sıra, aynı gün farklı değer 409) okuma ekler; aynı sayaç+tarih+değer tekrarı `replayed: true` (çevrimdışı kuyruk güvenle yeniden dener, fotoğraf tekrar eklenmez). Yanıt `photo.storage`: `drive` | `server` | `none`.
- `GET photos/:id/content` sunucuda tutulan fotoğraf.

Fotoğraf: istemci uzun kenarı 1280 px, JPEG kalite 70'e küçültür (EXIF/GPS atılır); sunucu en çok 600 KB kabul eder, içeriği türle eşleştirir. `drive_storage` açık ve bağlıysa Drive'a, değilse (ya da Drive hata verirse) `meter_reading_photos` tablosuna (site başına en çok 5000). Dosya adı `AB_D13_201026` (A blok, daire 13, 20.10.2026), klasör `suEkim_26` / `elektrikEkim_26` / `isiEkim_26` (sıcak su `su`). Tablo `meter_reading_photos` (okuma silinince CASCADE).

İstemci: kamera açık kalır, üstte sıradaki daire, metin tanıma telefonda (ML Kit; yalnız Android/iOS, web'de elle giriş), görevli onaylar/düzeltir. Okuma önce cihaz kuyruğuna yazılır (SharedPreferences + belgeler klasöründe fotoğraf), sonra gönderilir; ağ/sunucu hatasında kuyruk durur ve 30 sn'de bir / uygulama öne gelince / okuma sonrası yeniden dener. Sunucunun kalıcı reddi (4xx) kayda yazılır, görevli düzeltene ya da silene dek denenmez.

## Yakında

Okunan değerin yönetici tarafından sonradan düzeltilmesinin ayrı kaydı, fotoğraf görüntüleme ekranı, sayaç değişimi (eski sayacı kapatıp yenisini açmak: şimdilik pasife alıp yeni sayaç eklenir), ortak alan sayaçları, süper kullanıcı için site seçmeli sayaç ekranı.
