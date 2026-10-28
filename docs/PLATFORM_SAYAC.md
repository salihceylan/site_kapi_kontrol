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
- `heat` (yalnız ısı): `heat.measured_share_pct` (varsayılan 70) ölçüme, kalan (`heat.area_share_pct`, 30) "alan payı" olarak dağıtılır. m² sistemden kaldırıldığı için alan payı, katılan dairelerin HEPSİNDE arsa payı tanımlıysa arsa payına göre, tek bir daire bile eksikse herkese EŞİT dağıtılır (karma dağıtım yapılmaz; `metering_calc.areaShareItems`). Seçilen taban (`land_share` | `equal`) önizleme parametrelerine `area_basis` olarak yazılır. Arsa payı paydaları ortak paydaya getirilemeyecek kadar farklıysa 409 `LAND_SHARE_UNSUPPORTED` (sessizce eşit paya düşülmez). Alan nedeniyle eksik daire (`area_missing`) artık oluşmaz.
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

## Saha akışı ve sıçrama uyarısı (P1-6, P1-7; karar K12)

Görevli akışı: **blok seç → dairelerin çekilen / çekilmeyen listesi → eksikleri sırayla çek → yanlış çekileni listeden seçip yeniden çek**. Olağan dışı tüketim görevliye
sıradaki daireye geçmeden sorulur; sunucu da aynı kuralı uygular. Yeni alanların hepsi isteğe bağlıdır: eski istemci yeni sunucuyla, yeni istemci eski sunucuyla çalışır.

**Liste** `GET /sites/:siteCode/meter-field/meters?kind=&date=` (`date` YYYY-AA-GG, yoksa İstanbul bugünü) -> `{ items, jump_factor, date }`. Her sayaç eski alanlara ek olarak:

- `block_name`, `unit_label` — blok süzgeci için (eski sunucuda yoksa istemci "Blok - No" etiketinden türetir);
- `previous_reading { value, date }` — `date`ten ÖNCEKİ son okuma (o güne okuma girilmişse ondan öncekisi: yeniden çekimin tabanı), yoksa null;
- `jump { median, limit, factor }` — son 3 dönem tüketim tabanı: `median` = ortanca tüketim, `limit` = `median x factor`; yeterli veri yoksa null (cihaz uyarmaz).

**Dönem** = aynı sayacın iki ardışık okuması arası; tüketim = sonraki okuma - önceki okuma. Yeni okumadan önce EN AZ 4 okuma (3 dönem) gerekir; daha azında uyarı YOK. Ortanca tüketim 0 ise
(üç dönemin en az ikisinde tüketim yok) ölçek bulunamaz: uyarı YOK. Bir dönem tüketimi negatifse (veri tutarsız) uyarı yok. Tüketim `limit`i AŞARSA uyarı (eşitlik uyarmaz).
Hesap milli (BigInt) tam sayıyla yapılır; kayan nokta yoktur (`metering_jump.js`).

**K (eşik çarpanı)** = kurallar tablosu anahtarı `metering.jump_factor` (`docs/PLATFORM_KURALLAR.md`): varsayılan 5, sınır 2..100, birim kat, sitede değişebilir (site değerini süper kullanıcı
"Kurallar" ekranından verir; site yöneticisi salt okur). Kural okunamazsa 5 kullanılır (okuma girişi engellenmez). Migration gerekmez.

**Okuma** `POST /sites/:siteCode/meter-field/readings` gövdesine iki isteğe bağlı alan eklenir (`meter_id`, `date`, `value`, `photo_b64?`, `photo_mime?` aynen):

| Alan | Anlam |
| --- | --- |
| `confirm_jump` | `false` / `true` (boolean) ise sıçrama denetimi YAPILIR. `false`: eşik aşılırsa **409 `READING_JUMP`** döner ve okuma kaydedilmez; `true`: görevli onayladı, okuma kaydedilir ve onay izi yazılır. Alan YOKSA (eski istemci) denetim yapılmaz, okuma eskisi gibi kaydolur. |
| `replace` | `true`: **yeniden çekim**. O gün bu sayaç için FARKLI değerli okuma varsa değeri değişir (aynı kayıt, aynı id); yoksa normal eklenir. `replace` olmadan farklı değer 409 `READING_EXISTS` (eski davranış). |

- 409 `READING_JUMP` gövdesi: `{ error, code, jump: { previous_value, consumption, median, limit, factor } }` (değerler 3 ondalıklı metin).
- Yanıt (200/201) eski alanlara ek olarak: `retaken` (yeniden çekimle değişti), `jump_confirmed` (sıçrama onaylanarak kaydedildi). Aynı sayaç + tarih + AYNI değer yine `replayed: true` (çevrimdışı kuyruk güvenle yeniden dener; uyarı, denetim ve fotoğraf yok).
- Sıra kuralı sıçrama uyarısından ÖNCE denetlenir (önceki okumadan küçük değer `READING_OUT_OF_ORDER`).
- Yeniden çekim yalnız **bugünkü ve dünkü** okuma için (409 `RETAKE_WINDOW`; eski okumayı yönetici düzeltir) ve **faturalandırılmamış** dönemde (409 `READING_RETAKE_LOCKED`: okumanın tarihini kapsayan `period_to >=` faturalandırma varsa). Yeniden çekimde sıçrama tabanı, DEĞİŞTİRİLEN okumayı dışarıda bırakır (`reading_date < tarih`).
- Denetim kaydı (`audit_log`; okunan DEĞER yazılmaz): `metering.reading.added` (yeni), `metering.reading.retaken` (`{ meter_id, source: 'field' }`), `metering.reading.jump_confirmed` (`{ meter_id, factor, ratio_pct }`; `ratio_pct` = tüketimin ortancaya oranı, yüzde: 510 = 5,1 katı). Onay izi, sıçramanın gerçekten saptandığı kayıtta yazılır.

**İstemci** (`MeterFieldView`):

- Birden çok blok varsa üstte blok seçici ("Tümü (okunan/toplam)", "A Blok (3/12)"); sıradaki daire seçili bloktan gelir. Tek blokta seçici çizilmez.
- Banner'daki **Liste** düğmesi dairelerin durumunu açar: *Sorunlu* (sunucu kabul etmedi / onay bekliyor), *Çekilmeyenler* (çekilmedi / atlandı), *Çekilenler* (gönderildi / gönderilmeyi bekliyor). Satıra dokunmak o daireyi seçer: çekilmemişse sıradaki yerine o okunur, çekilmişse **yeniden çekim** başlar (banner "Yeniden çekim", düğme "Onayla ve değiştir", "Vazgeç" seçimi bırakır). Atlanan daire listeden geri çekilebilir; sıra bitince "Atlananlara dön".
- Sıçrama: değer girilince, sıradaki daireye GEÇMEDEN, sunucunun gönderdiği tabana göre cihazda kontrol edilir ("Olağan dışı tüketim": tüketim, ortanca, eşik). **Değeri düzelt** kaydetmez; **Doğru, kaydet** kuyruğa `confirm_jump: true` ile alır. Önceki okumadan küçük değer cihazda engellenir. Taban eskiyse / yoksa sunucu yine denetler (`false` gönderilir): 409 `READING_JUMP` alan kayıt kuyrukta **onay bekler** (engel değil; "Bekleyen" listesinde **Doğru, onayla ve gönder** / değeri düzelt / sil), diğer sunucu redleri gibi kırmızı rozetle sayılır.
- Yeniden çekim ve gönderilmemiş bekleyen kayıt: aynı dairenin bugünkü bekleyen/reddedilmiş kaydı varsa yenisi onun yerine geçer (iki kayıt birbirini ezmez); yeniden çekim kaydı `replace: true` taşır.
- Reddedilen kayıtlar anında bildirilir (ekranın altında "N okuma sunucuya kabul edilmedi" / "N okuma olağan dışı tüketim nedeniyle onayınızı bekliyor") ve üst çubuktaki Bekleyen düğmesinde kırmızı rozetle görünür.
- Kuyruğu okuyup değiştirip yazan tüm işler sıraya girer: sürmekte olan gönderim turu, araya giren yeni bir okumayı ezip kaybetmez; tur sürerken silinen kayıt gönderilmez.

**Tarih düzeltmesi:** sunucu saat dilimi Europe/Istanbul olduğundan pg'nin DATE -> yerel gece yarısı `Date` dönüşümü `toISOString()` ile okunduğunda tarihi bir gün geri kaydırıyordu (28 Ekim okuması
`last_reading.date` olarak 27 Ekim dönerdi; "bugün okundu" tanınmazdı). `metering_service.dateOnly` artık yerel gün/ay/yıl okur; saha listesinin geçmiş sorgusu tarihi `to_char` ile metin alır.

**Denemeler:** DB'siz birim testleri `server/test/metering_jump.test.js` (medyan / eşik, 3 dönemden az veri, K kuralı, sahte havuzla okuma servisi ve liste) ve istemci `test/meter_field_test.dart`,
`test/screens/meter_field_view_test.dart` (uyarı onay akışı, blok, liste, yeniden çekim, rozet). Gerçek PostgreSQL: `server/scripts/qa_metering_field.mjs` (`ALLOW_DEV_SCRIPTS=1`, kendi geçici sitesini kurup siler).

**Bu sürümde yok:** yönetici elle okuma girişi (`POST .../meters/:id/readings`) ve dosya aktarımı sıçrama denetimi yapmaz (yalnız saha ucu); sıçrama onayını okuma satırında gösteren işaret (onay izi denetim kaydındadır).

## Yakında

Okunan değerin yönetici tarafından sonradan düzeltilmesinin ayrı kaydı, fotoğraf görüntüleme ekranı, sayaç değişimi (eski sayacı kapatıp yenisini açmak: şimdilik pasife alıp yeni sayaç eklenir), ortak alan sayaçları, süper kullanıcı için site seçmeli sayaç ekranı.
