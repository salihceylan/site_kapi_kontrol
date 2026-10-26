# Platform — Toplu Yükleme ve Dışa Aktarma (Faz 2b) sözleşmesi

Bu belge sunucu (`server/`) ve uygulama (`lib/`) için BAĞLAYICIDIR. Öncül belgeler: `docs/PLATFORM_KISILER.md` (CRM: kişi/daire/araç; özellikle sondaki "Faz 2a inceleme kararları" ve kilit sırası, madde 16), `docs/PLATFORM_FINANS.md` (önizleme + `preview_hash` + `idempotency_key` + parmak izi + kilit sırası kalıpları), `docs/PLATFORM_MODUL_SISTEMI.md` (hata biçimi, audit), `docs/PLATFORM_SATISA_HAZIRLIK.md` (§0 ortak kurallar; **migration 038 bu faza ayrılmıştır**). Bu belge `PLATFORM_KISILER.md`'deki kısa "Faz 2b" bölümünün (şablon/önizleme/commit/export taslağı) YERİNE GEÇER; çelişkide bu belge önceliklidir. O taslaktaki uçlar (`people/import/*`, `people/export`) kodda hiç uygulanmadı, geriye dönük uyum sorunu yoktur. Deneme listesi: `tools/deneme_listesi/platform.json` F13 (eski planlı F2.08/F2.09 maddeleri yerine geçer) ve `SAHA_KONTROL_LISTESI.md` 72. bölüm (AGENTS.md kural 5).

## Kapsam

**Faz 2b (bu belge):** (a) Excel (.xlsx) ve CSV ile toplu yükleme: **daireler** (var olan dairelerin kat/tip/arsa payı/sorumlu taraf alanlarını doldurma; m² (brüt/net) alanları 2026-10-25'te sistemden kaldırıldı), **kişiler** (+ daire ilişkisi + araç plakası), **yalnız araçlar**; site kurulumunun hemen ardından ve sonradan; (b) dışa aktarma: kişiler, daireler, araçlar (CSV ve XLSX); (c) ortak **dışa aktarma zarfı** (`ExportEnvelope`) ve istemci dışa aktarma altyapısı. Faz 4b finans raporları (F4.11) aynı zarfı ve aynı "Dışa Aktar" arayüzünü kullanır; arayüz burada tanımlıdır.
**Kapsam dışı (bilinçli):** daire/blok OLUŞTURMA, silme, yeniden adlandırma (yapı, mevcut sayı tabanlı "Site Yapısı" akışında kalır; Karar 3); davet e-postası, kapı erişimi verme (hesap açma yalnız `people` ve `all_in_one` türlerinde ve yalnız bu yüklemede daire ilişkisi eklenen kişiler için vardır, bkz. son bölüm «Hesap açma»; o kişilere dairenin üyeliği dışında kapıya özel bir yetki yazılmaz); var olan kişi alanlarını ezen "güncelleme modu"; toplu geri alma (Karar 9); .xls/.ods/.xlsm/.xlsb; tek istekte çok sayfa; PDF; finans raporu dışa aktarma (4b).

## Mimari karar: dosya nerede ayrıştırılır?

| Seçenek | Artı | Eksi | Sonuç |
|---|---|---|---|
| A. Dosya sunucuya (multipart), sunucuda XLSX ayrıştırma (`xlsx`/`exceljs`) | tek ayrıştırıcı, istemciden bağımsız | yeni sunucu bağımlılığı + `multer`; SheetJS `xlsx` npm 0.18.5 için kamuya açık danışma notları (CVE-2023-30533 prototype pollution, CVE-2024-22363 ReDoS; düzeltmeler npm'e yayımlanmıyor); zip-bomb/bellek tüketimi PM2+PG+MQTT'nin aynı makinede çalıştığı VPS'te tüm API'yi düşürebilir; kişisel veri içeren ham dosya sunucu belleğine/diskine girer | REDDEDİLDİ |
| B. Sunucu yalnız CSV ayrıştırır (JSON içinde metin) | zip yok | XLSX yok (Excel kullanıcısı için sürtünme); Windows-1254 kodlama sunucuya ham bayt taşımayı gerektirir; ayrıştırıcı yine sunucuda | REDDEDİLDİ |
| **C. İstemci ayrıştırır, sunucuya yalnız JSON satırları gider** | sunucuya yeni bağımlılık YOK; ham dosya sunucuya hiç girmez (KVKK); saldırı yüzeyi yöneticinin kendi cihazı ve kendi dosyasıdır; sunucu aynı veriyi `POST people` ile zaten alabilir | CSV+XLSX okuyucu istemcide yazılıp sınanmalı; sunucu her hücreyi yeniden doğrulamalı | **SEÇİLDİ** |

Güvenlik varsayımı: sunucu istemciden gelen HER hücreyi güvenilmez sayar; istemci ayrıştırması yalnız kolaylıktır. Toplu uç, tek tek uçlardan (`POST people`, `POST vehicles`, `PATCH apartments`) FAZLA yetki vermez: hesap, davet e-postası, kapı/uygulama erişimi, rol ve silme yoktur. (Tek istisna: `people` ve `all_in_one` türlerinde commit'in son aşamasında, bu yüklemede daire ilişkisi eklenen kişiler için hesap ve daire üyeliği açılır; bkz. son bölüm «Hesap açma». `apartments`, `vehicles` ve `opening_balances` hâlâ hiçbir hesap/erişim yazmaz.)

## İlkeler

1. **Eklemeli şema:** `migrations/038_bulk_imports.sql` ile `ensureDbSchema` (server/src/db.js) AYNI idempotent DDL. Var olan tablolara sütun eklenmez.
2. **Dosya saklanmaz:** istek gövdesi (JSON satırlar) yalnız bellekte işlenir; ne dosya ne ham satırlar yazılır. `bulk_import_runs` kişisel veri taşımaz (yalnız sayılar, özetler). Gövde loglanmaz (`request_logger` zaten gövde yazmaz; hata yanıtları sabit mesajdır). Önizleme/dışa aktarma yanıtları `Cache-Control: no-store`.
3. **Doğruluk kaynağı sunucudur:** sütun şeması (`GET imports/spec`), tüm değer ayrıştırıcıları ve eşleşme kuralları yalnız sunucuda; istemci ham hücreyi (metin/sayı/null) iletir.
4. **İki adım zorunlu:** önizleme (YAZMAZ) → onay (commit). Commit önizlemeyi kilit altında YENİDEN hesaplar; `expected_hash` uyuşmazsa 409 `PREVIEW_STALE` ve hiçbir şey yazılmaz.
5. **Koruyucu ve eklemeli:** hiçbir kayıt silinmez/pasifleştirilmez; hesaplı kişinin alanlarına dokunulmaz; hesapsız kişinin DOLU alanı ezilmez (yalnız boşlar dolar); varsayılan olarak dairenin DOLU alanı da ezilmez (`allow_overwrite`, yalnız `apartments`).
6. **Satır bazlı sonuç:** satır `error` (hiç uygulanmaz) ya da `warning` (uygulanır, bir kısmı atlandı/uyarı) olur; yarım satır yazılmaz (plaka gibi ek öğeler için bkz. kurallar).
7. **İdempotans:** aynı dosya ikinci kez yüklenirse (yeni anahtarla bile) tüm satırlar "değişiklik yok" olur; çift tıklama/yeniden deneme `idempotency_key` ile tek kayıt üretir.
8. **Yetki:** yalnız site yöneticisi/süper kullanıcı; kurul, görevli, sakin yok (matris aşağıda).
9. **Kilit sırası** (PLATFORM_KISILER madde 16 + PLATFORM_FINANS madde 6 ile uyumlu): `sites KEY SHARE` → `bulk_import:<site>` (try-lock) → `people_sync:<site>` → (yalnız `apartments` türü) `finance_post:<site>` → `apartments` (id sırasıyla) → `users` (işlemi yapan, `FOR KEY SHARE`) → CRM satırları → `bulk_import_runs`/`audit_log`. Yeni kilit çatışması yaratılmaz; 40P01'de tek yeniden deneme.
10. **Ortam anahtarları (isteğe bağlı):** `BULK_IMPORT_DISABLED=1` (tüm toplu uçlar 503 `IMPORT_DISABLED`), `BULK_IMPORT_MAX_ROWS` (varsayılan 5000, üst sınır 5000).

## Veritabanı (migration `038_bulk_imports.sql`)

- `bulk_import_runs(id BIGSERIAL PK, site_code BIGINT NOT NULL, kind TEXT NOT NULL CHECK (apartments|people|vehicles), idempotency_key TEXT NOT NULL (8–64), request_fingerprint TEXT NOT NULL (64), preview_hash TEXT NOT NULL (64), strict BOOLEAN NOT NULL DEFAULT FALSE, allow_overwrite BOOLEAN NOT NULL DEFAULT FALSE, row_count INTEGER NOT NULL (≥ 0), counts JSONB NOT NULL DEFAULT '{}' (nesne), created_by INTEGER NULL, created_at TIMESTAMPTZ NOT NULL DEFAULT NOW())`. Yabancı anahtarlar tabloda SATIR İÇİ DEĞİLDİR, ayrı ifadelerle eklenir: `fk_bulk_import_runs_site` (`site_code → sites(site_code) ON DELETE CASCADE`) ve `fk_bulk_import_runs_created_by` (`created_by → users(user_code) ON DELETE SET NULL`). İndeksler: tekil `uq_bulk_import_runs_key (site_code, idempotency_key)`; `idx_bulk_import_runs_site (site_code, id DESC)`; kısmi `idx_bulk_import_runs_created_by (created_by) WHERE created_by IS NOT NULL` (kullanıcı kalıcı silinirken `ON DELETE SET NULL` taramasının sıralı taramaya düşmemesi için). Ad, e-posta, telefon, plaka, hücre değeri ASLA saklanmaz. Kayıtlar silinmez (site silinince CASCADE).
- **Açılış DDL tasarımı** (`server/src/modules/bulk_import_schema.js` `BULK_IMPORT_DDL`; `migrations/038_bulk_imports.sql` ile AYNI ifadeler, test: birebir eşitlik): (1) DDL `ensureDbSchema`'nın büyük bloğunun İÇİNDE değil, blok BİTTİKTEN sonra `ensureBulkImportSchema(client)` ile çalışır; tek bir katalog sorgusu (`to_regclass`, `pg_constraint`, `pg_indexes`) eksik nesneleri belirler ve YALNIZ eksikler için DDL çalışır — normal açılışta hiç DDL/kilit yoktur (`CREATE … IF NOT EXISTS` nesne VARKEN bile kilit alabilir ve yazıcılarla 40P01 üretir). (2) Satır içi `REFERENCES sites` + `REFERENCES users` içeren `CREATE TABLE`, iki tabloda `ShareRowExclusive` kilidini ardışık alır; `UPDATE sites … UPDATE users` yapan bir yazıcıyla ters sırada kesişince QA'da 18 denemenin 15'inde 40P01 üretti. Bu yüzden tablo FK'SIZ oluşturulur, iki FK ayrı ifadelerle (`DO $$ … IF NOT EXISTS (pg_constraint) … ALTER TABLE ADD CONSTRAINT`) eklenir; her ifade TEK başvurulan tabloyu kilitler, kilit döngüsü kurulamaz (sıcak FK'ler ayrı adım). (3) Her ifade kendi otomatik onaylı çağrısında `SET lock_timeout = '3s'` ile çalışır (sonra `RESET lock_timeout`); 55P03 (kilit zaman aşımı) ya da 40P01'de `200 ms × deneme` bekleyip en çok 6 kez yeniden dener. Migration çalıştırıcısı (`migrate.js`) tek işlemde, bilinçli ve bir kez uyguladığı için aynı ifadeler orada doğrudan yazılıdır.
- Başka şema değişikliği YOK: kişi/ilişki/araç/daire tabloları aynen kullanılır. Toplu yazılan ilişkiler `origin = 'manual'` (eşitleme bunları sessizce bitirmez, bkz. Faz 2a madde 4).

## Şablon ve sütun sözleşmesi

`GET /manager/sites/:siteCode/imports/spec` → `{ "spec_version": 1, "max_rows": 5000, "max_body_bytes": 5242880, "kinds": { "<kind>": { "columns": [ { "key", "label", "required", "type": "text|number|date|enum", "max_length", "aliases": ["…"], "hint" } ], "relation_words": {…} } } }`. İstemci başlık eşlemesini bu `label` ve `aliases` ile yapar (Türkçe katlama: Ç→c, Ğ→g, İ/I/ı→i, Ö→o, Ş→s, Ü→u, küçük harf, noktalama/boşluk sadeleştirme; sunucudaki `foldText` ile aynı). Sunucu `spec_version` farklıysa 409 `IMPORT_SPEC_MISMATCH` ("Uygulamayı güncelleyin"). **Başlık satırı** = ilk 10 satırda ≥ 2 tanınan sütun içeren ilk satır; yoksa "Başlık satırı bulunamadı". Tanınmayan sütunlar "yok sayıldı" listelenir (dışa aktarılan dosyanın salt okunur sütunları bu yüzden yeniden yüklenebilir). `max_body_bytes` sunucunun kabul ettiği JSON gövde sınırıdır (5 MiB = 5242880); istemci satırların UTF-8 JSON boyutuna 1 KB pay ekleyip bununla karşılaştırır ve aşıyorsa istek GÖNDERİLMEDEN «Dosyadaki veriler gönderilemeyecek kadar büyük (X MB; sınır 5 MB). Satırları iki ya da daha fazla parçaya bölüp sırayla yükleyin…» der (sunucu 413'ü gövdesiz de gelebilir; bkz. "Gövde sınırı").

| `apartments` (yalnız MEVCUT daireleri günceller) | zorunlu | kural |
|---|---|---|
| `blok` ("Blok") | evet | Eşleşme: önce katlanmış TAM ad; yoksa baştaki/sondaki "blok" sözcüğü atılmış hâl ("A", "A Blok", "Blok A" aynı). Birden çok blok eşleşirse `BLOCK_AMBIGUOUS` |
| `daire_no` ("Daire No") | evet | "5", "05", "Daire 5", "D5", "No: 5" → sitedeki `unit_label` ("Daire 5") ile eşleşir (mevcut etiketler hep "Daire N") |
| `kat` | hayır | tamsayı −20..500; "zemin"/"giriş"=0, "bodrum"=−1, "3. kat"=3 |
| `tip` | hayır | ≤ 40 karakter (`category`) |
| `brut_m2`, `net_m2` (KALDIRILDI) | — | Şablonda, spec'te ve dışa aktarmada YOK. Eski bir dosyada bu sütunlar dolu gelirse istek reddedilmez; değerler yok sayılır ve dosya başına BİR kez `AREA_COLUMN_IGNORED` uyarısı verilir |
| `arsa_payi_pay`, `arsa_payi_payda` | hayır | tamsayılar; payda 1..10⁹, 0 ≤ pay ≤ payda; **iki ayrı sütun** (tek hücrede "35/1000" Excel tarafından tarihe çevrilir). İndirilen şablonda gösterilmez (istemcide `kExcludedTemplateKeys`), ancak dosyada bu sütunlar varsa okunur |
| `sorumlu` ("Borç Sorumlusu") | hayır | Malik / Kiracı / İkisi → `owner|tenant|both` |

| `people` | zorunlu | kural |
|---|---|---|
| `ad_soyad` | evet | 2–100 karakter (`normalizePersonName`) |
| `kullanici_adi` ("Kullanıcı Adı") | hayır | ≤ 50 karakter; boşsa ad-soyaddan üretilir, çakışmada `_2`, `_3` … eklenir (bkz. son bölüm «Hesap açma») |
| `telefon` | hayır | `normalizePersonPhone`; Excel'in baştaki sıfırı attığı 10 haneli numara da kabul |
| `e_posta` | hayır | `normalizePersonEmail`; `@ahbu.local` `EMAIL_INTERNAL` |
| `sifre` ("Başlangıç Şifresi") | hayır | ≤ 30 karakter; boşsa `1234` (şablonda her satırda `1234` hazır gelir); ilk girişte değiştirilmesi zorunludur |
| `blok`, `daire_no` | birlikte | ikisi de dolu ya da ikisi de boş (`APARTMENT_REQUIRED`) |
| `iliski` | hayır | malik/mal sahibi/ev sahibi → owner; kiracı/kiraci → tenant; aile/aile üyesi/eş/çocuk → family_member; sakin/oturan/boş → resident. Bilinmeyen → `RELATION_INVALID`. Daire yokken yok sayılır (uyarı yok) |
| `giris_tarihi` | hayır | GG.AA.YYYY, G.A.YYYY, GG/AA/YYYY, GG-AA-YYYY, YYYY-AA-GG; 2 haneli yıl reddedilir; 1900..bugün+366 gün (gelecek tarih `FUTURE_DATE` uyarı; ötesi `DATE_RANGE`). Boşsa bugün (İstanbul) |
| `plaka` | hayır | hücrede en çok 5 plaka; ayırıcı `,` `;` `/` `\|` satır sonu; `normalizePlate` |
| `not` | hayır | ≤ 500 karakter; indirilen şablonda gösterilmez, dosyada varsa okunur |

| `vehicles` | zorunlu | kural |
|---|---|---|
| `plaka` | evet | `people` ile aynı |
| `e_posta` | kişiyi bulmak için | önce e-posta; yoksa `blok`+`daire_no`: dairenin güncel sakini TEK ise o, çoksa `ad_soyad` (katlanmış tam eşleşme); çözülemezse `PERSON_AMBIGUOUS`/`PERSON_NOT_FOUND` |
| `blok`, `daire_no`, `ad_soyad`, `not` | hayır | yukarıdaki gibi |

## Değer kuralları (sunucu, tek modülde: `bulk_import_parsers.js`; ileti metinleri `bulk_import_messages.js`)

1. **Metin:** NFC; kontrol karakterleri ve görünmez/çift yönlü kontrol karakterleri (U+200B–200F, U+202A–202E, U+2066–2069, U+FEFF) silinir; NBSP boşluğa, ardışık boşluklar tekile; kırpılır; boş = yok. Hücre > 600 karakter `TOO_LONG` satır hatasıdır (alanın kendi sınırı daha küçükse o geçerlidir: `ad_soyad` 100, `tip` 40, `not` 500; ileti «… çok uzun (en çok N karakter).»). Bunun ÖNÜNDE sert bir sınır vardır: gövdede tek bir metin hücresi > 5000 karakter (Unicode kod noktası) ise TÜM istek 400 `INVALID_BODY` ile reddedilir («rows[i].cells.<anahtar> çok uzun.»; `CELL_HARD_LIMIT`). Bu yüzden istemci okuyucusu hücre metnini 601 karakterde keser: fazlası isteği düşürmez, o satırda `TOO_LONG` hatası olur.
2. **Formül önekli hücre (içe aktarma):** kırpılmış metin `=`, `@`, TAB ya da CR ile başlıyorsa HER metin alanında `FORMULA_LIKE` (satır hatası); `+`/`-` ile başlıyorsa `ad_soyad`, `e_posta`, `blok`, `tip`, `plaka`'da hata; `not` ile sayı/telefon/tarih alanlarında izinli (kendi ayrıştırıcılarından geçer; `not` her dışa aktarmada kaçışlanır, bkz. Dışa aktarma). Sessiz "temizleme" YOK: kullanıcı neyin reddedildiğini görür.
3. **Sayı (m²) — KALDIRILDI (2026-10-25):** hiçbir sütun m² okumaz; m² ayrıştırıcısı (`readArea`) kaynaktan çıkarıldı, `AREA_UNUSUAL` ve `NET_GT_GROSS` uyarıları üretilmez. Eski şablondan kalan dolu `brut_m2`/`net_m2` hücreleri yok sayılır (`AREA_COLUMN_IGNORED`, dosya başına bir uyarı). Eski kural (tarihçe): JSON number olduğu gibi; metinde boşluk/NBSP silinir, sondaki `m2`/`m²`/`㎡` atılır; hem `.` hem `,` varsa SONUNCUSU ondalık, öbürü binlik; yalnız `,` → ondalık; yalnız `.`: ondalık ya da tam 3 rakamlı gruplarla binlik; 2'den fazla ondalık yuvarlanır.
4. **Arsa payı:** `mergeLandShare` kuralı (yalnız biri verilirse DB'deki diğeriyle birleştirilip doğrulanır). Önizlemede `checks.land_share` (yalnız `apartments`; diğer türlerde `null`): dosyada arsa payı hücresi olan en az bir satır varsa VE sitenin TÜM daireleri (dosyadaki değişiklikler uygulanmış hâliyle) tek paydada ve hepsinin payı doluysa `{ "sum": 987, "denominator": 1000, "complete": false, "message": "987/1000: eksik olabilir" }` döner. `message` sunucuda üretilir: tam eşitlikte `"1000/1000 ✓"`, `sum < denominator` iken `"S/D: eksik olabilir"`, `sum > denominator` iken `"S/D: fazla olabilir"` (S = pay toplamı, D = payda). Paydalar farklıysa, bir dairenin payı boşsa ya da dosyada arsa payı yoksa `land_share: null` (kontrol yapılmaz). Engellemez, yalnız bilgilendirir; istemci `message`'ı olduğu gibi gösterir (yoksa `sum`/`denominator`/`complete` alanlarından aynı metni kurar).
5. **Daire etiketi eşleşmesi** `foldText` ile; bulunamayan blok için yanıt sitedeki blok adlarını sayar; bulunamayan daire için "Daire sayısını Site Yapısı'ndan artırın" ipucu verir.

## Eşleşme / yinelenen kayıt politikası

**Daireler:** anahtar (blok, daire no). Dosyada aynı daire ikinci kez → ikinci satır `DUPLICATE_IN_FILE` hatası (ilk satır geçerli). Boş hücre HİÇBİR ZAMAN değeri silmez. Dolu hücre: DB'de NULL ise yazılır; DB'deki değerle aynıysa "değişiklik yok"; farklıysa `allow_overwrite:false` iken korunur (`VALUE_KEPT` uyarı), `true` iken yazılır (`overwritten_cells` sayısı onayda gösterilir). Mali kaydı (`ledger_entries`) olan dairede `arsa payı/tip/sorumlu` değişirse `FINANCE_RECORDS` uyarısı (geçmiş defter satırları anlık görüntüdür, değişmez; yalnız sonraki borçlandırma etkilenir).

**Kişiler** (satır → kişi), sırayla:
1. `e_posta` varsa: sitenin kişi kayıtlarında e-posta eşleşmesi (hesapsızın e-postası ya da hesaplı kişinin hesap/iletişim e-postası; `findPersonByEmail` ile AYNI kural; başka sitenin kaydı görünmez, hesap var/yok bilgisi sızmaz). Pasif kişi de bulunur.
2. e-posta yoksa/eşleşmediyse ve daire varsa: dairenin GÜNCEL sakinleri arasında katlanmış adı aynı olan TEK kişi.
3. e-posta ve daire yoksa: katlanmış ad + normalize telefon aynı olan TEK aktif kişi. Üçü de yoksa `NO_IDENTIFIER` hatası (tekrar yüklemede çift kayıt doğmasın).
4. Aksi: yeni (hesapsız) kişi. Birden çok adayda `PERSON_AMBIGUOUS` (satır hatası; tahmin edilmez).

**Telefon TEK BAŞINA eşleştirme anahtarı değildir** (aile üyeleri/işyeri numarası paylaşır; yanlış birleştirme başkasına dairesini, borcunu ve araçlarını görünür kılar).

Eşleşen kişiye yazma kuralları:
- **Hesaplı kişi** (`has_account`): ad/telefon/e-posta/not'a dokunulmaz; o dairede mevcut ilişki `resident` ise dosyadaki açık ilişkiye YÜKSELTİLİR; plaka eklenir; bu dairede ilişkisi yoksa YENİ ilişki eklenmez (`ACCOUNT_NEW_APARTMENT` uyarı: hesaplı kişiye yanlış bir daire eklemek finansını ve kayıtlarını o kişiye açar; kişi kartından elle eklenir).
- **Hesapsız aktif kişi:** boş telefon/e-posta/not dosyadan doldurulur, doluya dokunulmaz; ilişki yoksa eklenir; `resident` → açık ilişkiye yükseltilir; açık ilişki farklıysa değişmez (`RELATION_DIFFERS` uyarı); plaka eklenir.
- **Pasif kişi** (yalnız e-posta ile bulunur): yeniden etkinleştirilir, ad ve (varsa) telefon dosyadan yazılır, geçmiş korunur (`createPerson` yeniden kullanım kuralı; `REACTIVATE_PERSON` uyarı).
- **Yeni kişi:** hesapsız oluşturulur (`created_by` = yönetici); bu adımda hesap OLUŞTURULMAZ, e-posta GÖNDERİLMEZ, `apartment_memberships`/`site_memberships` YAZILMAZ (`people` ve `all_in_one` türlerinde hesap ve üyelik, commit'in AYRI bir son aşamasında açılır; bkz. son bölüm «Hesap açma». E-posta o aşamada da gönderilmez). Aynı e-postalı kullanıcı sonradan siteye katılırsa mevcut `syncSitePeople` LINK adımı onu bağlar (bu yüzden commit, eşleşmeden ÖNCE `runSyncSteps` çalıştırır; aksi halde hesaplı kişi için ikinci, hayalet kayıt doğardı).

**İlişki kuralı:** bir dairede en çok bir güncel malik ve bir kiracı (Faz 2a). Dosyada ya da DB'de ikinci malik/kiracı → `RELATION_TAKEN` satır hatası ("Eş/hissedar için «aile» yazın"). Aynı kişi+daire için dosyada çelişen ilişki → ikinci satır `CONFLICTING_ROWS`; aynı ilişki tekrarı → `DUPLICATE_IN_FILE` uyarısıyla birleştirilir (plakalar birleşir). Aynı ad+daire, farklı ilişki, iletişim bilgisi yok → baba/oğul ayrımı yapılamaz; hata mesajı "farklı kişiyseniz e-posta ya da telefon ekleyin" der.

**Plaka:** satırın ek öğesidir: geçersiz (`PLATE_INVALID`), sitede başkasında aktif (`PLATE_EXISTS`), dosyada başka kişide (`PLATE_DUP_IN_FILE`) plaka ATLANIR, kişi/ilişki yazılır, satır `warning` olur (düzeltilmiş dosya tekrar yüklenince idempotans sayesinde yalnız eksik plaka eklenir). Aynı kişide mevcut plaka "değişiklik yok". **Satır kuralı (yalnız `vehicles` türü):** araç satırının tek amacı plakadır; satırdaki HER plaka atlandıysa ve eklenecek ya da zaten kayıtlı plaka kalmadıysa (`eklenen + değişmeyen = 0` ve en az bir atlanan) o satırın plaka uyarıları (`PLATE_INVALID`, `PLATE_EXISTS`, `PLATE_DUP_IN_FILE`) HATAYA yükseltilir ve satırdan hiçbir şey yüklenmez (satır `error`). `people` türünde bu yükseltme YOKTUR: kişi/ilişki yazılır, plaka atlanır, satır `warning` kalır.

## Uçlar (`/manager/sites/:siteCode/…`, hata gövdesi `{ error, code }`, Türkçe)

Yetki: `resolvePeopleAccess(write:true)` — süper kullanıcı ve o sitenin yöneticisi; BOARD_MEMBER/STAFF/sakin 403 `FORBIDDEN_ROLE`; başka sitenin yöneticisi 403 `FORBIDDEN_SITE`. `:kind` ∈ `apartments|people|vehicles` (aksi 404 `IMPORT_KIND_NOT_FOUND`).

- `GET imports/spec` → yukarıdaki spec. Hız: 1200/saat/kullanıcı + 12000/saat/IP.
- `POST imports/:kind/preview` (YAZMAZ) gövde:
  ```json
  { "spec_version": 1, "allow_overwrite": false,
    "rows": [ { "n": 2, "cells": { "ad_soyad": "Ahmet Yılmaz", "blok": "A", "daire_no": 3, "iliski": "Malik", "giris_tarihi": "2021-03-15", "plaka": "34 ABC 123, 06 XY 789" } } ] }
  ```
  `rows` 1..5000; `n` = dosyadaki satır numarası (başlık 1, ilk veri 2; kullanıcı Excel'de ne görüyorsa), artan ve tekil; `cells` anahtarları spec anahtarlarından olmalı (bilinmeyen anahtar 400 `INVALID_BODY`; nesneler `Object.create(null)`/Map ile kurulur, `__proto__`/`constructor` anahtarı reddedilir); değer: string (≤ 600) | sonlu number | null (boolean/nesne/dizi reddedilir). `allow_overwrite` yalnız `apartments`'ta geçerli (diğerlerinde `true` → 400). Yanıt 200:
  ```json
  { "kind": "people", "spec_version": 1, "preview_hash": "<sha256 hex>",
    "totals": { "rows": 318, "ok": 290, "unchanged": 12, "error": 10, "with_warnings": 9 },
    "plan": { "people_create": 150, "people_link": 120, "people_reactivate": 2, "people_filled": 8, "residency_add": 240,
              "residency_upgrade": 30, "residency_unchanged": 20, "vehicle_add": 190, "vehicle_unchanged": 4 },
    "issues": [ { "n": 14, "severity": "error|warning", "field": "e_posta", "code": "EMAIL_INVALID", "message": "E-posta biçimi geçersiz." } ],
    "issues_truncated": false,
    "samples": [ { "n": 2, "action": "create|link|update|unchanged", "summary": "Ahmet Yılmaz → A Blok - Daire 3 (Malik)" } ],
    "checks": { "land_share": null } }
  ```
  `apartments` planı: `apartment_update`, `cells_set`, `overwritten_cells`, `cells_kept`. `issues` EN ÇOK 4000 öğedir (`MAX_ISSUES_IN_RESPONSE`; sıra `n`). Daha fazla sorun varsa `issues_truncated: true` olur: HATALAR önce korunur, kalan yer uyarılarla doldurulur (fazla uyarılar listeden atılır); `totals` ve `plan` sayıları kesilmeden TAMDIR. `samples` eylem başına en çok 5 satırdır (`SAMPLES_PER_ACTION`). İstemci hata raporunu `issues` listesinden üretir (kesilmişse rapor da kesiktir); ekranda «Çok sayıda sorun var: yalnızca ilk 4.000 tanesi listelenir (hatalar öncelikli). Dosyayı düzeltip yeniden yükleyin; kalan sorunlar sonraki önizlemede görünür.» uyarısı çıkar. Önizleme veritabanını tek bir `REPEATABLE READ READ ONLY` işlemde okur (tutarlı anlık görüntü); öncesinde `syncSitePeople(site, {wait:true})` çalışır (kilit bekleme üst sınırı 8 sn; aşılırsa 409 `SITE_BUSY`). `preview_hash` = sha256(`v1`, `kind`, `n` sırasıyla `n|eylem|hedef kimlikleri (daire/kişi/ilişki/araç)|yazılacak değerlerin özeti|sorun kodları`); ileti metinleri hash'e girmez. Hız: 30/saat/kullanıcı + 120/saat/IP.
- `POST imports/:kind/commit` gövde: preview gövdesi + `expected_hash` (ZORUNLU), `idempotency_key` (ZORUNLU, 8–64, `[a-z0-9-]`), `strict` (varsayılan false), `acknowledged` (`people`/`vehicles` için ZORUNLU true, aksi 400 `ACK_REQUIRED`: "Kişi verilerini işlemek için gerekli yasal dayanağa sahip olduğunuzu onaylayın"). Akış, kilit sırası ve uyuşmazlıklar aşağıda. Yanıt 201:
  ```json
  { "replayed": false, "run": { "id": 41, "kind": "people", "created_at": "ISO", "row_count": 318 },
    "result": { "rows": { "applied": 290, "unchanged": 12, "skipped": 10 }, "counts": { "people_create": 150, "…": 0 }, "issues": [ … ] } }
  ```
  Aynı anahtar + aynı parmak izi → 200 `{ "replayed": true, "run": {…}, "result": { "rows": {…}, "counts": {…}, "issues": null } }` (satır ayrıntıları saklanmadığı için `issues` null; önizleme yeniden çalıştırılabilir). Aynı anahtar + farklı parmak izi → 409 `IDEMPOTENCY_CONFLICT`. Parmak izi = sha256(`kind`, `spec_version`, `strict`, `allow_overwrite`, kanonik `rows`); `expected_hash` parmak izine GİRMEZ. Hız: 10/saat/kullanıcı + 60/saat/IP.
- `GET exports/:kind` → `ExportEnvelope` (Dışa aktarma bölümü). Hız: 30/saat/kullanıcı + 300/saat/IP.

Gövde sınırı: `preview` ve `commit` POST uçları için `express.json({ limit: '5mb' })`, `server.js`'te genel 1 MB'lık ayrıştırıcıdan ÖNCE ve YALNIZ `authRequired` + yetki + hız sınırlayıcıdan SONRA bağlanır (anonim istek 5 MB okutamaz; `labeled-devices` kalıbı). 5 MB aşılırsa uygulama JSON `413 { "error": "Dosya çok büyük. Bir seferde en çok 5 MB gönderilebilir.", "code": "PAYLOAD_TOO_LARGE" }` döner (ayrıştırıcı `entity.too.large`; diğer ayrıştırma hataları 400 `INVALID_BODY` «İstek gövdesi geçersiz.»). nginx (`client_max_body_size`) isteği uygulamaya ulaşmadan keserse 413 GÖVDESİZ (ya da HTML) gelir: istemci her iki durumda da (gövdede `code` yoksa `PAYLOAD_TOO_LARGE` varsayar) «Dosya çok büyük. Satırları parçalara bölüp ayrı ayrı yükleyin.» gösterir. İstemci ayrıca `max_body_bytes` ile gövde boyutunu göndermeden önce denetler (bkz. spec).

## Commit akışı (tek transaction, hepsi bir arada)

1. `BEGIN`; `sites FOR KEY SHARE` (yoksa 404); `pg_try_advisory_xact_lock('bulk_import:<site>')` (alınamazsa 409 `IMPORT_IN_PROGRESS`; ayrıca süreç başına en çok 2 eşzamanlı commit); `SET LOCAL lock_timeout = '8s'` (aşılırsa 409 `SITE_BUSY`: "Site kayıtları şu an başka bir işlemde, biraz sonra tekrar deneyin"); `pg_advisory_xact_lock(people_sync:<site>)`; `apartments` türünde `finance_post:<site>`.
2. Replay denetimi: `(site_code, idempotency_key)` var mı → parmak izi eşleşirse replay, değilse 409.
3. İlgili daireler id sırasıyla kilitlenir (`apartments`: `FOR NO KEY UPDATE`; `people/vehicles`: `FOR KEY SHARE`), sonra işlemi yapan `users` satırı `FOR KEY SHARE`.
4. `people/vehicles`: `runSyncSteps` (üyelikleri CRM'e yansıtır). Sonra DB anlık görüntüsü yüklenir (daireler, aktif kişiler, güncel ilişkiler, aktif araçlar: sabit sayıda sorgu), plan yeniden hesaplanır, `preview_hash` karşılaştırılır → fark varsa 409 `PREVIEW_STALE` (+ güncel `totals`, `plan`, `preview_hash`). `strict:true` ve `error` > 0 ise 409 `IMPORT_HAS_ERRORS` (+ sayılar).
5. Yazma, **küme tabanlı** (`unnest` dizileriyle), 1000'lik parçalarla: kişi kimlikleri `nextval` ile önceden ayrılır (RETURNING sırasına güvenilmez) → kişi INSERT/UPDATE → ilişki INSERT (`origin='manual'`) / UPDATE → araç INSERT → toplu audit INSERT (`unnest`, SAVEPOINT'siz) → `bulk_import_runs` satırı. Beklenmeyen 23505 (yarış) → ROLLBACK + 409 `PREVIEW_STALE`; 40P01 → tek yeniden deneme.
6. `COMMIT`. Erişim anahtarı döndürme/rotasyon GEREKMEZ (hiçbir erişim KAPANMAZ; `people` ve `all_in_one` türlerinde yalnız yeni hesaplara daire üyeliği VERİLİR, bkz. son bölüm «Hesap açma»).

**Ölçek hedefi** (5000 satır, 5000 daireli site, ~15.000 kişi; gerçek-PG QA'da ölçülür): önizleme ≤ 3 sn, commit ≤ 6 sn, commit başına ≤ 40 sorgu (satır sayısından bağımsız), yanıt ≤ 1 MB, sunucu bellek sıçraması ≤ 100 MB, `EXPLAIN`'de büyük tablolarda seq scan yok (mevcut indeksler: `idx_apartment_residencies_apartment`, `uq_vehicles_plate`, `idx_site_people_site`, `uq_site_people_email`). Daha büyük dosya parçalara bölünür (eşleşme kuralları parçalı yüklemeyi güvenli yapar). Commit süresince `people_sync` kilidi tutulur: aynı sitenin diğer CRM yazmaları bekler (≤ 8 sn sonra `SITE_BUSY`), okuma uçları etkilenmez (eşitleme atlanır).

## Önizleme → onay, "hepsi ya da hiçbiri", geri alma

- **Varsayılan: "geçerli olanları al"** (satır atomik). Gerekçe: eşleşme kuralları idempotenttir; düzeltilmiş dosya yeniden yüklenince önceki satırlar "değişiklik yok" olur ve yalnız eksikler eklenir. Hepsi-ya-da-hiçbiri, yapısı gereği çözülemeyen tek bir satır (ör. sitede olmayan daire) yüzünden yüzlerce doğru satırı bekletir. İsteyen için `strict:true` (arayüz: "Hatalı satır varsa hiçbirini aktarma" anahtarı, varsayılan KAPALI).
- **Onay penceresi** (özet): kaç kişi/ilişki/araç eklenecek, kaçı mevcut kayda bağlanacak, kaç satır atlanacak, uyarı sayısı, `apartments`'ta üzerine yazılacak hücre sayısı; KVKK onay kutusu; "Hatalı satır raporunu indir".
- **Toplu geri alma YOK (Karar 9).** Gerekçe: Faz 2 ilkesi "kayıtlar silinmez"; geri alma silme/pasifleştirme anlamına gelir ve yazımdan dakikalar sonra veriler başka akışlarca kullanılmış olur (eşitleme hesaba bağlar, duyuru kitle anlık görüntüsü kişi kimliğini tutar, sakin "Borcum"/"Kayıtlarım" ekranları görür). Koruyucu tedbirler: zorunlu önizleme, `preview_hash` ile bayatlık denetimi, yalnız eklemeli/boş-doldurmalı yazma, erişim/hesap/e-posta yazmama, idempotans. Yanlış yükleme için mevcut tekil yollar (kişiyi pasifleştir/"Taşındı", araç kaldır, daire alanı düzenle) kullanılır; `person.created` vb. audit satırları `via:'import'` + `run_id` taşıdığı için ayıklanacak kayıtlar tespit edilebilir. Gerekirse Faz 2c'de "son yüklemenin dokunulmamış kayıtlarını pasifleştir" eklenebilir.

## Audit

Tek `import.committed` (`target_type:'import'`, `target_id:<run_id>`, `site_code` dolu; `details`: `kind`, `run_id`, `rows`, `counts`, `strict`, `allow_overwrite`, `acknowledged`, `preview_hash` — **ad/e-posta/telefon/plaka/hücre değeri YOK**) + etkilenen kayıt başına küme INSERT'li satırlar, hepsinde `details.via:'import'`, `run_id`: `person.created`, `person.updated` (alan adları: telefon/e-posta/not için yalnız `{field, changed:true}`; yeniden etkinleştirme `is_active`), `residency.added`, `residency.updated`, `vehicle.added` (tekil yolla uyum için `plate` taşır; plaka mevcut `vehicle.added` kaydında da vardır, `import.committed` satırında YOKTUR), `apartment.updated` (`changes: [{field, from, to}]`, mevcut sözleşmedeki gibi sayı/kategori). Böylece F2.11 geçmişi (`history`) toplu kayıtları da gösterir. Dışa aktarma: `export` (`target_type:'export'`, `target_id:<kind>`; `details`: `kind`, `row_count`, `format`, süzgeç adları ve değerleri (arama metni YOK, yalnız `has_q:true`), `include_notes`). Süper denetim ekranına etiketler: `import.committed` "Toplu yükleme", `export` "Dışa aktarma" (`PEOPLE_ACTIONS_SQL` ikisini zaten kapsar).

## Dışa aktarma

`GET exports/:kind?status=active|inactive|all&relation=&q=&apartment_id=&block_id=&person_id=&include_notes=&format=csv|xlsx` (süzgeçler ilgili liste uçlarıyla AYNI sorgu mantığını yeniden kullanır: `peopleWhere` vb.; liste uçlarındaki gibi `syncSitePeopleSafe`). Yalnız yönetici/süper (kurul, mevcut listeleri OKUR ama toplu veri çıkışı yapamaz: KVKK ölçülülük; Karar 12). `format` yalnız audit içindir (dosyayı istemci üretir). Yanıt `Cache-Control: no-store`:
```json
{ "kind": "people", "spec_version": 1, "generated_at": "ISO", "filename_base": "kisiler_gul-sitesi_20261016",
  "columns": [ { "key": "ad_soyad", "label": "Ad Soyad", "type": "text" }, { "key": "giris_tarihi", "label": "Giriş Tarihi", "type": "date" },
               { "key": "sakin_sayisi", "label": "Sakin Sayısı", "type": "number", "scale": 0 } ],
  "rows": [ [ "Ahmet Yılmaz", "0 (555) 123 45 67", … ] ], "row_count": 318 }
```
- Sütun tipleri: `text`, `number` (JSON sayı, `scale` ondalık), `date` (ISO `YYYY-MM-DD`), **`money`** (TAMSAYI KURUŞ; çıktıda yalnız tamsayı/metin aritmetiğiyle 2 ondalık, kayan nokta YOK; Faz 4b için). Hücre ham değerdir (sunucu `'` öneki eklemez); kaçış istemci üreticisinin işidir (tek geçiş noktası).
- `people`: bir satır = bir (kişi, güncel ilişki); ilişkisi olmayan kişi tek satır. Sütunlar içe aktarma şablonuyla AYNI başlıklar (gidiş-dönüş mümkün) + salt okunur `Hesap` (Var/Yok), `Durum` (Aktif/Pasif). `telefon` `0 (555) 123 45 67` biçiminde (baştaki 0 ve parantez/boşluk: Excel sayıya çevirip sıfırı atmaz; içe aktarma geri okur). `plaka`: kişinin tüm aktif plakaları `, ` ile. `not` yalnız `include_notes=true` iken (varsayılan false).
- `apartments`: `Blok`, `Daire No`, `Kat`, `Tip`, `Arsa Payı (Pay)`, `Arsa Payı (Payda)`, `Borç Sorumlusu` + salt okunur `Malik`, `Kiracı`, `Sakin Sayısı`. `vehicles`: `Plaka`, `Ad Soyad`, `Blok`, `Daire No`, `İlişki`, `Not` (opsiyonel).
- Üst sınır 20.000 satır; aşılırsa 422 `EXPORT_TOO_LARGE` ("Süzgeç kullanarak daraltın"). `daire_no` etiketi "Daire N" ise yalnız N yazılır.
- **Faz 4b:** finans raporları aynı `ExportEnvelope` ile yeni `kind`'lar ekler (kendi modül/yetki kuralıyla; `MODULE_DISABLED` korunur); Flutter tarafı değişmez.

**İstemci üretici kuralları (normatif):**
- **CSV:** UTF-8 + BOM (`EF BB BF`), ayırıcı `;`, satır sonu CRLF, `;`, `"`, CR/LF içeren ya da baş/son boşluklu hücre `"…"` içine alınır (`"` → `""`); sayı ondalık VİRGÜL ve binlik ayırıcısız; tarih `GG.AA.YYYY`; boş = boş hücre; ilk satır başlık.
- **XLSX:** tüm metin hücreleri `t="inlineStr"` (formül olarak yorumlanamaz); başlık kalın + dondurulmuş; `telefon/plaka/blok/daire_no` sütunları metin biçimli (`@`); tarih gerçek tarih hücresi (`gg.aa.yyyy`); sayı gerçek sayı; sayfa adı ≤ 31 karakter, `[]:*?/\` yok; XML'de geçersiz karakterler (U+0000–0008, 000B, 000C, 000E–001F, FFFE, FFFF) atılır.
- **Formül enjeksiyonu (CSV hücre kaçışı):** metin hücrenin ilk karakteri (baştaki boşluklar atlanarak) `=`, `+`, `-`, `@`, TAB veya CR ise hücrenin önüne `'` eklenir; İSTİSNA yalnız saf sayı kalıbı (`^[+-]?\d+([.,]\d+)?$`, ör. kat "-1"). XLSX'te kaçış GEREKMEZ (metin hücresi) ve eklenmez (ekranda görünür kesme işareti olmasın). Özellikle `ad_soyad` (hesaplı kişide kullanıcının kendi yazdığı ad), `e_posta` (`=x@y.com` doğrulamadan geçer), `not`, `tip` kaçışlanır.

## Yetki matrisi

| Rol | spec | preview | commit | export |
|---|---|---|---|---|
| Süper kullanıcı | evet | evet | evet | evet |
| Site yöneticisi (kendi sitesi) | evet | evet | evet | evet |
| Yönetim kurulu (`BOARD_MEMBER`) | 403 `FORBIDDEN_ROLE` | 403 | 403 | 403 |
| Görevli (`STAFF`) / sakin | 403 `FORBIDDEN_ROLE` | 403 | 403 | 403 |
| Başka sitenin yöneticisi | 403 `FORBIDDEN_SITE` | 403 | 403 | 403 |
| Kimliksiz | 401 | 401 | 401 | 401 |

Modül: `people` çekirdektir, `MODULE_DISABLED` yok. IDOR: her sorgu `site_code` ile sınırlıdır; gövdedeki hiçbir kimlik (daire/kişi) kullanılmaz — yalnız ad/etiket eşleşmeleri, bunlar da yalnız o sitenin kayıtlarında aranır.

## Hata kodları

Uç düzeyi (`{ error, code }`): 400 `INVALID_BODY` (alan adıyla), 400 `IMPORT_EMPTY`, 400 `IMPORT_TOO_MANY_ROWS` (> 5000), 400 `ACK_REQUIRED`, 404 `IMPORT_KIND_NOT_FOUND`, 409 `IMPORT_SPEC_MISMATCH`, 409 `PREVIEW_STALE` (+ yeni `totals/plan/preview_hash`), 409 `IMPORT_HAS_ERRORS` (`strict`), 409 `IDEMPOTENCY_CONFLICT`, 409 `IMPORT_IN_PROGRESS`, 409 `SITE_BUSY`, 413 `PAYLOAD_TOO_LARGE` (nginx keserse gövdesiz gelebilir), 422 `EXPORT_TOO_LARGE`, 429 hız sınırı (mevcut gövde), 503 `IMPORT_DISABLED`, 403 `FORBIDDEN_ROLE`/`FORBIDDEN_SITE`.
Satır düzeyi (`issues[].code`): **error** — `REQUIRED`, `TOO_LONG`, `FORMULA_LIKE`, `NAME_INVALID`, `EMAIL_INVALID`, `EMAIL_INTERNAL`, `PHONE_INVALID`, `DATE_INVALID`, `DATE_RANGE`, `FLOOR_INVALID`, `LAND_SHARE_INVALID`, `RELATION_INVALID`, `RESPONSIBLE_INVALID`, `NO_IDENTIFIER`, `APARTMENT_REQUIRED`, `BLOCK_NOT_FOUND`, `BLOCK_AMBIGUOUS`, `APARTMENT_NOT_FOUND`, `DUPLICATE_IN_FILE`, `CONFLICTING_ROWS`, `RELATION_TAKEN`, `PERSON_AMBIGUOUS`, `PERSON_NOT_FOUND`, `TOO_MANY_PLATES`, `PLATE_REQUIRED`; **warning** — `PLATE_INVALID`, `PLATE_EXISTS`, `PLATE_DUP_IN_FILE`, `ACCOUNT_NEW_APARTMENT`, `RELATION_DIFFERS`, `REACTIVATE_PERSON`, `VALUE_KEPT`, `FINANCE_RECORDS`, `ROUNDED`, `AREA_COLUMN_IGNORED` (eski m² sütunu yok sayıldı), `FUTURE_DATE`, `NO_VALUES`. İleti: Türkçe, alan etiketiyle, < 140 karakter; hücre değeri en çok 40 karakter yankılanır; teknik ifade yok.

## Flutter

**Paketler** (`flutter pub add` KULLANILMADI; sürümler pub.dev API'si ve repo `pubspec.lock`'unun bir kopyası üzerinde `flutter pub get --dry-run` ile 2026-10-16'da doğrulandı):

| Paket | Karar | Gerekçe |
|---|---|---|
| `file_picker ^13.1.0` | EKLE | MIT; pub.dev 160/160 puan; ≈4,5 milyon indirme/30 gün; Android, iOS, Windows, macOS, Linux, web; `saveFile` ile masaüstü/web "kaydet". Çözümleme temiz: `file_picker` + 7 yeni geçişli paket (android_file_picker, file_picker_darwin/linux/web/platform_interface, windows_file_picker, dbus); HİÇBİR mevcut paket gerilemez veya yükselmez. Uyarı: 13.x genç büyük sürüm (13.0.0 ve 13.1.0 2026-09-14/15) — sürüm sabitlenir, API 13.x README'sine göre (`pickFile` + `PlatformFile.readAsBytes()`). Alternatif: `file_selector 1.1.0` (flutter.dev, BSD-3) — Android uyarlaması düşük benimsenme (≈7 bin/30 gün, 0.5.x) |
| `archive`, `xml` | doğrudan bağımlılığa TERFİ (`pubspec.yaml`: `archive ^4.5.2`, `xml ^7.1.0`; kilitte 4.5.2 / 7.1.0; yeni paket yok) | XLSX okuma/yazma bunlarla kendi kodumuzda |
| `excel 4.0.6` | EKLEME | son sürüm 2024-08-20 (≈26 ay); `archive ^3`/`xml <7` zorlar: çözümleme `archive 4.0.9→3.6.1`, `xml 7.0.1→6.6.1`, `image 4.10.1→4.3.0`, `pdf 3.13.0→3.12.0`, `printing 5.15.0→5.14.3` GERİLEMESİ gösterdi (mevcut PDF yığınını etkiler); tüm çalışma kitabını belleğe alır, zip koruması yok |
| `csv 8.0.0` | EKLEME | MIT, bağımlılıksız ama 2026'da iki büyük sürüm (7.0.0 Şubat, 8.0.0 Mart); ayırıcı/kodlama sezgisi ve hücre sertleştirmesi zaten özel; ~80 satırlık RFC 4180 ayrıştırıcı yeterli ve tam sınanır |
| `share_plus ^13.3.0`, `crypto` | MEVCUT | mobil paylaşım (dosya: Android/iOS/macOS/Windows; web'de indirme yedeği; **Linux'ta dosya paylaşımı yok** → `saveFile`); SHA-256 imza |

macOS: `macos/Runner/*.entitlements` içine `com.apple.security.files.user-selected.read-write` (seçme ve kaydetme). Linux masaüstü `zenity`/`kdialog` gerektirir (birincil hedef değil). Mobilde Android 13+ ek izin gerekmez.

**Dosyalar (gerçekleşen, `lib/`):** `services/` { `bulk_text_decoder.dart`, `bulk_csv_codec.dart`, `bulk_xlsx_reader.dart`, `bulk_xlsx_writer.dart`, `bulk_header_mapper.dart`, `bulk_cell_safety.dart`, `bulk_export_renderer.dart`, `bulk_file_parser.dart` (isolate'ta ayrıştırma), `bulk_file_picker.dart`, `bulk_file_delivery.dart`, `bulk_template.dart`, `bulk_formatting.dart`, `bulk_sheet_types.dart` (`SheetLimits`), `bulk_api.dart` (`BulkApi` HTTP + `BulkService` oturumlu sarmalayıcı: `getImportSpec`, `previewImport`, `commitImport`, `exportData`) }; `models/bulk_import.dart` (`ImportSpec`, `ImportColumn`, `ImportPreview`, `ImportIssue`, `ImportResult`, `ExportEnvelope`); `ui/views/bulk_import_view.dart` + `bulk_import_controller.dart`; `ui/widgets/bulk_*.dart` (adım başlığı, tür/dosya/eşleme/önizleme/sonuç adımları, onay penceresi, giriş düğmeleri, `bulk_export_sheet.dart` = `ExportSheet`); `ui/dialogs/export_sheet.dart` yalnız sözleşme adını `bulk_export_sheet.dart`'a yeniden aktarır.

**Okuyucular (istemci):**
- **Kodlama:** BOM varsa uygula (UTF-8; UTF-16LE/BE — Excel "Unicode Metin" sekmeli UTF-16LE üretir); yoksa KATI UTF-8 dene; başarısızsa **Windows-1254** (Latin-1 + Ğ/İ/Ş/ğ/ı/ş farkları + 0x80–0x9F tablosu; Türkçe Excel'in "CSV (Noktalı virgülle ayrılmış)" çıktısı). Kodlama sonucu kullanıcıya bildirilir ("Windows-1254 olarak okundu").
- **CSV:** ayırıcı ilk 20 satırda `;`, `,`, TAB, `|` içinde tutarlı sütun sayısı veren/en sık olan (eşitlikte `;`); `sep=;` ilk satırı atlanır; tırnak içinde satır sonu/`""`; CR/LF/CRLF; boş satırlar atlanır (`n` korunur); dosya ≤ 5 MB; ≤ 5000 veri satırı (okuyucu başlık araması payıyla 5011 dolu satırda DURUR; aşılırsa «Dosyada 5000 satırdan fazla veri var…» iletisi, `FILE_LIMIT`); ≤ 40 sütun; hücre metni 601 karakterde kesilir (bkz. Değer kuralları 1).
- **XLSX:** dosya ≤ 10 MB (sıkıştırılmış; CSV sınırı 5 MB'tır, ancak XLSX zaten sıkıştırılmıştır ve görseller büyütebilir, bu yüzden 10 MB'a izin verilir; AÇILMIŞ boyut ayrıca sınırlıdır); önce sihirli bayt (`PK\x03\x04`; `D0CF11E0` = eski .xls → "Eski .xls desteklenmez, .xlsx ya da CSV olarak kaydedin"); `.xlsm/.xlsb/.ods` reddedilir. **Zip koruması (iki aşama):** (1) **Ön tarama** (`inspectZipDirectory`, `lib/services/bulk_xlsx_reader.dart`): `ZipDecoder` çalışmadan ÖNCE merkezi dizin kendi kodumuzla taranır ve tehlikeli dosya HİÇBİR ŞEY AÇILMADAN reddedilir. Gerekçe: `archive` 4.5.2, Unix sembolik bağ bayraklı girdiyi decode sırasında hemen açar; bu yüzden decode SONRASI boyut/oran denetimi o yolda işe yaramazdı (300 KB'lık dosya 300 MB, 1 MB'lık dosya 2 GB bellek). Reddedilenler: zip64 işaretleri; 300'den çok girdi (`FILE_LIMIT`); sembolik bağ girdisi; parola (şifreli) bayrağı ya da store/deflate dışı sıkıştırma (bzip2/zstd/AES; `FILE_TYPE`); girdi başına bildirilen açılmış boyut > 25 MB ya da toplam > 50 MB (`FILE_TOO_LARGE`); 64 KB'tan büyük girdide sıkıştırma oranı > 100:1 (`FILE_LIMIT`, «olağandışı biçimde sıkıştırılmış»); bozuk/uyuşmayan dizin. (2) **Decode sonrası** (`XlsxReader._build`): girdi sayısı, girdi/toplam boyut ve oran yeniden denetlenir; `xl/vbaProject.bin` varsa .xlsm gibi reddedilir; yalnız beş girdi okunur (`xl/workbook.xml`, `xl/_rels/workbook.xml.rels`, `xl/sharedStrings.xml`, `xl/styles.xml`, seçilen sayfa); diske ASLA çıkarılmaz (zip-slip yok); sharedStrings ≤ 200.000 öğe; XML'de `DOCTYPE` reddedilir (varlık genişletme saldırısı yok); sayfa XML'i `xml` olay akışıyla okunur, 5011 dolu satırdan sonra DURUR (`SheetTable.truncated`). Sayfa seçimi: ad eşleşmesi (`Daireler`/`Kişiler`/`Araçlar`, katlamalı) yoksa kullanıcıya liste. Değerler: paylaşılan/inline/zengin metin, sayı, mantıksal, hata (boş), formülün ÖNBELLEKLİ sonucu (formül hiç hesaplanmaz), 1900/1904 tarih sistemi; tarih sütunları (eşlemeyle bilinir) sayısal hücreyi ISO tarihe çevirir. Okuma bir isolate'ta yapılır (web'de ana iş parçacığı; ilerleme göstergesi + iptal).
- **Sunucuya gidenler:** yalnız eşlenmiş sütunlar, kırpılmış metin/sayı/null; satır başına `n`; tamamen boş satırlar atılır.

**Ekranlar:**
1. **Girişler:** Kişiler ekranı (yalnız `canWrite`; kurulda GİZLİ) sekme çubuğunun altında "Toplu Yükle" ve "Dışa Aktar" düğmeleri (dar ekranda `Wrap`); yalnız BOŞ Kişiler sekmesinde (arama/süzgeç yokken) `EmptyCard` içinde «Daire ve kişi bilgilerini şimdi toplu yükleyin.» + «Excel'den yükle» (`BulkEmptyImportAction`; sihirbaz Kişiler türü önseçili açılır). **Henüz YAPILMADI (sonraki iş):** boş Daireler/Araçlar sekmelerinde kısayol YOKTUR; `SetupSiteDialog` başarı ekranında ve başvuru onayından sonra yöneticinin ilk girişinde de kısayol YOKTUR — site kurulduktan sonra yönetici Kişiler sekmesindeki boş durum kısayolunu ya da «Toplu Yükle» düğmesini kullanır. Sunucu tarafında ayrı kurulum ucu yoktur (Karar 23).
2. **Toplu Yükle sihirbazı** (`BulkImportView`, tam sayfa; adım göstergesi «Adım N / 5 · Tür | Dosya | Sütunlar | Önizleme | Sonuç»; 320×640 ×2,0'da taşma yok): **(1) Ne yükleyeceksiniz?** Daireler / Kişiler / Araçlar kartları (önerilen sıra: Daireler → Kişiler → Araçlar; hepsi isteğe bağlı), site özeti ("3 blok, 120 daire"), "Şablonu indir" (XLSX: `Daireler` sayfası sitenin MEVCUT blok/daire numaralarıyla ön dolu — `exports/apartments` zarfından —, `Kişiler`, `Araçlar` yalnız başlık satırı, `Açıklama` sayfası: sütunlar, kurallar, örnekler, ilişki sözlüğü; CSV: yalnız seçilen türün dosyası (`toplu_yukleme_sablonu_daireler.csv` / `_kisiler.csv` / `_araclar.csv`), başlık satırı, `;`+BOM; Daireler CSV'si de mevcut dairelerle ön doludur; XLSX'te seçilen türün sayfası İLK sıradadır ve mevcut daireler alınamazsa «Mevcut daire numaraları alınamadığı için daire sayfası boş hazırlandı.» notuyla yalnız başlık verilir; veri sayfalarına örnek satır KONMAZ, yanlışlıkla yüklenmesin). **(2) Dosya seç** (`.xlsx`, `.csv`; boyut/biçim hataları açık). **(3) Sütunlar:** otomatik eşleşme özeti, zorunlu sütun eksikse engel, iki sütun aynı alana düşerse düzeltme, tanınmayanlar "yok sayılacak". **(4) Önizleme:** sayı çipleri (Eklenecek / Bağlanacak / Değişmeyecek / Hatalı / Uyarılı), "Sorunlu satırlar" listesi (satır no, alan, neden; hata/uyarı süzgeci; sayfalı), `apartments` için "Dolu alanların üzerine yaz" anahtarı (kapalı) ve arsa payı toplamı kontrolü, "Hatalı satır varsa hiçbirini aktarma" anahtarı (kapalı), "Hata raporunu indir" (CSV: satır;alan;kod;ileti — hücre değeri YOK), örnek satırlar. **Onay** (Önizleme adımından açılan `BulkConfirmDialog`: sayılar + KVKK onay kutusu; adım göstergesinde AYRI adım değildir) → commit: ilerleme, `PopScope` ile çıkış engeli, çift gönderim koruması; `IdempotencyKeys` (imza = tür + satır özeti sha256 + bayraklar) ile yanıt kaybında aynı anahtarla yeniden deneme; `PREVIEW_STALE` → önizleme otomatik yenilenir ve "Veriler siz bakarken değişti, özet güncellendi" gösterilir; `IMPORT_IN_PROGRESS`/`SITE_BUSY` → yeniden dene düğmesi. **(5) Sonuç:** sayılar, hata raporu, "Kişilere git"; Kişiler/Daireler/Araçlar sekmeleri "bayat" işaretlenip otomatik yenilenir (AGENTS.md kural 7). Sonraki tür için "Sıradakini yükle".
3. **Dışa Aktar** (`ExportSheet`, alt sayfa; Faz 4b yeniden kullanır — kaynağı `ExportSource { label; Future<ExportEnvelope> fetch(format); }` arayüzüdür): tür (açık sekmeden önseçili), biçim (Excel .xlsx önerilir | CSV (Excel uyumlu)), açık sekmenin süzgeçleri ("Aktif kişiler, Malik" özeti; TÜM sayfalar, yalnız yüklenenler değil), `people` için "Yönetici notlarını da ekle" (kapalı), uyarı satırı "Bu dosya kişisel veri içerir; güvenli saklayın ve yetkisiz kişilerle paylaşmayın.", **Kaydet** (web/masaüstü: `saveFile`; mobil: paylaşım sayfası `share_plus`). Hata/boş/422 durumları dürüst; çift dokunma koruması.
4. **Hata kodu eşlemeleri** (`messageForErrorCode`, her biri < 140 karakter, `_` yok): `PREVIEW_STALE` "Veriler değişti. Önizleme yenilendi, tekrar inceleyin." · `IMPORT_HAS_ERRORS` "Hatalı satırlar var. Düzeltip yeniden yükleyin." · `IMPORT_TOO_MANY_ROWS` "Bir seferde en çok 5.000 satır yüklenebilir." · `IMPORT_IN_PROGRESS` "Bu site için başka bir yükleme sürüyor." · `SITE_BUSY` "Site kayıtları şu an meşgul, biraz sonra deneyin." · `IMPORT_SPEC_MISMATCH` "Uygulamayı güncelleyin." · `ACK_REQUIRED` "Devam etmek için onay kutusunu işaretleyin." · `EXPORT_TOO_LARGE` "Çok fazla kayıt var. Süzgeçle daraltın." · `IMPORT_DISABLED` "Toplu işlemler geçici olarak kapalı." · `IDEMPOTENCY_CONFLICT` (mevcut eşleme).

## Güvenlik ve gizlilik (özet)

KVKK: dosya sunucuya girmez; gövde loglanmaz, çalıştırma kaydı/audit kişisel veri taşımaz; yükleme anında yönetici yasal dayanağı onaylar (onay metnini hukuk onaylar, `legal` belgeleri kvkk_notice/dpa ile uyumlu; kayıt `acknowledged:true`); dışa aktarma yalnız yönetici, audit'li, hız sınırlı, `no-store`, notlar varsayılan hariç; sunucu dışa aktarılan dosyayı hiç saklamaz. Enjeksiyon: tüm değerler parametreli dizilerle (SQL'e metin birleştirilmez); XSS: değerler düz metin gösterilir (duyuru e-postaları zaten kaçışlar); CSV/XLSX formül enjeksiyonu hem içe (`FORMULA_LIKE`) hem dışa (kaçış) kapalı; prototype pollution: sunucuda anahtar beyaz listesi + Map; XLSX: istemci yalnız kendi cihazında, sınırlı ve diske yazmadan okur. Yetki yükseltme sınırlıdır: `apartments`, `vehicles` ve `opening_balances` hiçbir erişim/rol/hesap yazmaz; `people` ve `all_in_one` yalnız bu yüklemede daire ilişkisi eklenen kişiler için hesap ve daire üyeliği açar (başka siteye ya da yöneticiye ait bir hesaba bağlanmaz; bkz. son bölüm «Hesap açma»). Kötüye kullanım: hız sınırları, 5000 satır/5 MB, site başına tek commit, süreç başına 2 commit.

## Doğrulama (kabul)

- **Sunucu:** `npm test` + `npm run lint` yeşil; saf birim testleri (sayı/tarih/telefon/plaka/kat/ilişki/formül ayrıştırıcıları; özellik testleri: rastgele metin hiç özel hata fırlatmaz; `foldText` eşitliği); strict sahte-DB testleri (yetki matrisi, gövde doğrulama, prototip anahtarları, hız sınırı, loglarda kişisel veri yok); **gerçek PG** (`qa_platform_pg.mjs`, yeni `bulk_import` bölümü): migrate zinciri = `ensureDbSchema` (CHECK/indeks, ikinci çalıştırma no-op); 5000 satırlık sentetik dosya süre/sorgu sayısı/bellek hedefleri; **idempotans** (aynı dosya ikinci kez = 0 değişiklik, aynı anahtar replay, aynı anahtar farklı gövde 409); `PREVIEW_STALE` (önizleme ile commit arasında kişi/plaka eklenir); hepsi-ya-da-hiçbiri; eşleşme matrisi (e-posta/daire+ad/ad+telefon, telefon tek başına eşleşmez, hesaplı kişi alanları ezilmez, hesaplı kişiye yeni daire eklenmez, `resident`→`owner` yükseltme, pasif yeniden etkinleştirme, ikinci malik `RELATION_TAKEN`, baba/oğul belirsizliği); eşitleme etkileşimi (içe aktarma sonrası kullanıcı katılır → `syncSitePeople` LINK tek kayıt, ikinci hayalet kayıt YOK; `origin='manual'` ilişkiler eşitlemede bitmez); kapı yetkisi/`apartment_memberships` satırları ve `my-doors` AYNI; kilit turları (commit × `createPerson` × "Taşındı" × kullanıcı silme × daire azaltma × finans `post` × eşzamanlı ikinci commit; **40P01 = 0**); site silinince CASCADE; `export` süzgeç eşdeğerliği (liste ile aynı sonuç kümesi), kurul/görevli/sakin 403, 20.000 sınırı, audit.
- **Uygulama:** `flutter analyze` temiz, `flutter test` yeşil; kodlama (UTF-8 BOM'lu/BOM'suz, UTF-16LE sekmeli, Windows-1254 altın dosyalar), CSV (`;` `,` TAB, tırnaklı satır sonu, `sep=`, 5000'den fazla veri satırı sınırı), XLSX (Excel 365 TR, LibreOffice, Google E-Tablolar, Numbers'tan üretilmiş küçük örnek dosyalar `test/fixtures/spreadsheet/`; paylaşılan/inline/zengin metin, tarih/1904, boşluklu hücreler, birleşik hücre, formül önbelleği, >40 sütun, zip-bomb örneği HIZLI reddedilir, `.xls`/`.xlsm`); yazıcı çıktısı kendi okuyucumuzla gidiş-dönüş; kaçış özellik testleri (`= + - @ TAB CR`, boşluklu önek, saf sayı istisnası); sihirbaz adımları, STALE/replay/çift dokunma, kurulda düğmelerin yokluğu, dar ekran (320×640 ×2,0 ve 360×640 ×1,5, açık/koyu, strict), büyük yazı, ekran okuyucu etiketleri, `flutter build web`.
- **El ile (kullanıcı: `tools/deneme_listesi/platform.json` F13 ve `SAHA_KONTROL_LISTESI.md` 72. bölüm; F2.08/F2.09 eski planlı maddelerdir):** gerçek Excel TR ile şablon doldur → yükle (bilerek hatalı satırlar) → önizleme → onay → sonuç; aynı dosyayı tekrar yükle (değişiklik yok); dışa aktarılan XLSX/CSV'yi Excel TR'de aç (Türkçe karakterler, telefon, plaka, `=` ile başlayan ad), yeniden yükle.
- **Süreç:** Faz 2/3/4a'daki gibi en az iki bağımsız inceleme turu (yetki/gizlilik/formül; veri/yarış/şema); gerçek PG şart; yedek + şema provası + canlı doğrulama (AGENTS.md kural 8).

## Dağıtım notları

038 ekleyicidir (tek yeni tablo). nginx: API sunucu bloğunda `client_max_body_size` varsayılan 1 MB ise `/manager/sites/` için en az 6 MB yapılmalı (aksi halde 5 MB'lık gövde nginx'te 413 alır; sunucudaki ayar repo'da değil, `/etc/nginx/sites-available/api.gudeteknoloji.com.tr`). PM2 yeniden başlatma sonrası `/health` ve örnek önizleme (küçük dosya) canlıda doğrulanır. Modül anahtarı yoktur (`people` çekirdek); acil durumda `BULK_IMPORT_DISABLED=1`.

## Açık sorular (kullanıcı kararı gerekir)

1. **Çoklu malik (hissedar/eş):** model bir dairede en çok BİR güncel malik tutar; dosyada iki malik varsa ikincisi `RELATION_TAKEN` olur (ikinciyi «aile» yazmak önerilir). Çoklu malik istenirse Faz 2a veri modeli (tekil indeks `uq_apartment_residencies_owner`) ve finans `responsible_party` mantığı değişir.
2. **Gerçek kapı numaraları:** sitedeki daire etiketleri hep "Daire 1…N" (blok başına); B Blok'ta fiili numara 21–40 ise dosyadaki `daire_no` eşleşmez. Daire yeniden adlandırma/yapıyı dosyadan kurma (Faz 2c) istenir mi?
3. **Kişi alanları için güncelleme (ezme) modu:** v1'de yok (telefon değişikliği tekil düzenlemeyle). Excel'de düzeltip toplu güncelleme istenir mi?
4. **Kurul dışa aktarması:** kurul listeleri okur ama dışa aktaramaz (ölçülülük). Denetçi/kurul için salt okunur dışa aktarma isteniyorsa "yalnız daire listesi" gibi kısıtlı bir izin düşünülebilir.
5. **Yüklenen kişilere toplu davet** (uygulama hesabı/QR bağlantısı e-postası): bu fazda yok; Faz 3b duyuru e-postası altyapısıyla ayrı bir iş olarak planlanabilir.

## Kararlar

1. **İstemci ayrıştırma + sunucuya JSON** (yukarıdaki tablo): sunucuda zip/XLSX bağımlılığı, bellek/CVE riski ve ham kişisel veri dosyası alınmaz.
2. **XLSX/CSV okuyucu ve yazıcı kendi kodumuz** (`archive`+`xml`, zaten kilitte): `excel` paketi eski, mevcut PDF yığınını geriletiyor ve zip koruması yok; `csv` paketi 2026'da iki büyük sürüm geçirdi ve ihtiyacımız (sezgi, sertleştirme) zaten özel.
3. **Yapı (blok/daire) dosyadan kurulmaz:** `syncSiteStructureCounts` blok adlarını her düzenlemede `A Blok, B Blok…` olarak yeniden yazar ve daireleri `Daire N` + `sort_order` ile sayı tabanlı yönetir; dosyadan oluşturulan blok/etiket bir sonraki yapı düzenlemesinde sessizce bozulur ve `sites.block_apartment_counts` ile çelişir. Daire importu bu yüzden "mevcut daireyi doldur"dur; ön dolu şablon eşleşme sorununu çözer.
4. **Çıktı sadece ekleyici/boş-doldurucu:** CRM ilkesi (kayıt silinmez, hesaplı kişinin verisi `users`'ta). Daire alanları için ezme `allow_overwrite` ile açık onaylıdır.
5. **Hesaplı kişiye toplu yoluyla YENİ daire eklenmez:** yazım hatası o kişinin finans/kayıtlarını başka daireye açardı; kişi kartından elle eklenir.
6. **Telefon tek başına eşleştirme anahtarı değil;** e-posta → (daire+ad) → (ad+telefon) sırası; eşleşme yoksa kişi YENİ, belirsizse hata (tahmin yok).
7. **Hesap/e-posta/erişim yok:** toplu yükleme erişim yetkisi vermez; sonradan katılım mevcut LINK adımıyla bağlanır. (Sonradan değişti: `people` ve `all_in_one` türlerinde hesap ve daire üyeliği açılır, e-posta hâlâ GÖNDERİLMEZ; bkz. son bölüm «Hesap açma».)
8. **"Geçerli olanları al" varsayılan, `strict` isteğe bağlı:** idempotans düzeltilmiş dosyanın tekrar yüklenmesini güvenli kılar.
9. **Toplu geri alma yok:** "kayıt silinmez" ilkesi + yazım sonrası hızlı bağımlılık (eşitleme, duyuru kitlesi, sakin ekranları); tedbir olarak önizleme+hash+idempotans+audit'te `run_id`.
10. **Satır numarası = dosyadaki numara (`n`):** kullanıcı Excel'de neye bakıyorsa hata raporu odur.
11. **Plaka ek öğedir (uyarı):** kişi/ilişki yazılır, sorunlu plaka atlanır; tekrar yükleme eksik plakayı tamamlar.
12. **Dışa aktarma yalnız yönetici/süper:** toplu kişisel veri çıkışı yönetim kurulu için de ölçülülük ilkesine takılır; audit + `no-store` + hız sınırı; notlar varsayılan hariç.
13. **Zarf + istemci üretici:** biçimlendirme ve formül kaçışı TEK yerde (istemci üreticisi); sunucu ham veri verir; Faz 4b yalnız yeni `kind` ekler. `money` tipi kuruşu tamsayı aritmetiğiyle yazar.
14. **CSV kaçışı `'` öneki, XLSX'te yok:** OWASP kalıbı; XLSX metin hücresi formül olamaz.
15. **Telefon dışa aktarımı `0 (555) 123 45 67`:** Excel `+90…` değerini sayıya çevirip `+`'yı atar ve `+` formül öneki sayılır; bu biçim hem güvenli hem metin kalır hem geri okunur.
16. **Stateless commit (satırlar yeniden gönderilir):** sunucuda geçici veri/kimlik yok, IDOR yüzeyi yok; yük 2×1–5 MB.
17. **`preview_hash` DB bağımlı planı kapsar:** önizleme ile onay arasında kayıt değişirse sessiz farklı sonuç yerine 409.
18. **Kilit zinciri sabit ve fail-fast:** `bulk_import:<site>` try-lock + 8 sn `lock_timeout` + süreç başına 2 commit; havuz ve kullanıcılar uzun beklemez.
19. **KVKK onay kutusu** `people`/`vehicles` commit'inde zorunlu: veri sorumlusu yönetici; metin hukuk onayına tabi.
20. **Gövde sınırı 5 MB yalnız yetki sonrası;** nginx ayarı dağıtım kontrol listesindedir.
21. **Dosya türü:** yalnız .xlsx ve CSV; .xls/.xlsm/.xlsb/.ods reddedilir (makro ve eski ikili biçim yüzeyi yok).
22. **Linux masaüstünde `saveFile`, mobilde `share_plus`:** share_plus Linux'ta dosya paylaşmaz; web'de indirme yedeği vardır.
23. **Kurulum için ayrı sunucu ucu yok:** site yapısı sayı tabanlı kurulur (`createSiteWithStructure`: «Daire 1…N»); kurulum bittikten sonra (anlık kurulumda ve başvuru onayı sonrası yöneticinin ilk girişinde) AYNI toplu uçlarla ön dolu şablon kullanılır. Kurulum transaction'ına dosya verisi sokulmaz (başvuru onayı süper kullanıcı akışıdır, yönetici verisi orada yoktur). **Uygulama durumu:** kurulum ekranına/başvuru onayı sonrasına kısayol henüz YOKTUR; yalnız boş Kişiler sekmesindeki kısayol ve «Toplu Yükle» düğmesi vardır.

## Hepsi bir arada ve devir bakiyesi (Dalga 2, N6 / F4; yukarıdaki metne göre ÖNCELİKLİDİR)

İki yeni tür; uçlar aynıdır: `imports/:kind/preview|commit`. Tür beyaz listesi kodda (`BULK_KINDS`), `bulk_import_runs.kind` CHECK'i biçim denetimidir
(`^[a-z][a-z_]{2,39}$`, migration 055). Modül kapısı gereken türler `KIND_MODULE` tablosundadır (devir -> `finance`; kapalıysa 403 `MODULE_DISABLED`).
`exports/opening_balances` ve `exports/all_in_one` yoktur (404).

- **`all_in_one`** (N6): sütunlar daire türü + kişi türünün birleşimi; `blok` ve `daire_no` her satırda zorunlu; «Taşınma Tarihi» = Giriş Tarihi. Mevcut
  planlayıcılar değişmeden kullanılır (`bulk_import_plan_all_in_one.js`): dairenin ilk satırı «taşıyıcı» olur, daire bilgisi dairenin satırlarındaki ilk dolu
  değerlerden birleşir, farklı değer `APARTMENT_VALUES_CONFLICT` (satır hatası). Daire bölümü hatalı satır kişi planına girmez; satır atomiktir (kişi bölümü
  hatalı taşıyıcının daire alanı güncellemesi de düşer, düzeltilip yeniden yüklenir). KVKK onayı (`acknowledged`) ve `allow_overwrite` (daire alanları)
  geçerlidir. Kilit sırası: bulk_import -> people_sync -> finance_post -> apartments (FOR NO KEY UPDATE) -> users.
- **`opening_balances`** (F4): sütunlar `blok*`, `daire_no*`, `hesap` (Ev sahibi/Malik/Mal sahibi/Kiracı; boş = ev sahibi), `tutar*` (TL; `1.250,50`, `1250.5`,
  `₺`, `TL`; kuruşa metin aritmetiğiyle), `vade` (boş = devir tarihi), `aciklama` (<= 200). Gövdede `options.cutover_date` (bugün ya da önce, en çok 5 yıl geri,
  ayı açık) ve commit'te `options.expected_total_minor` zorunludur; ikisi de parmak izine, devir tarihi `preview_hash`'e girer. Toplam uyuşmazsa 409
  `TOTAL_MISMATCH`. KVKK onayı yerine istemcide tutar onayı kutusu vardır.
- Satır kuralları: eksi tutar `OPENING_CREDIT_UNSUPPORTED` (v1'de alacaklı devir yok), 0 -> `OPENING_ZERO` uyarısı (atlanır), aynı daire+hesap dosyada ikinci kez
  `DUPLICATE_IN_FILE`; etkin devir varsa aynı tutar/vade/açıklama «değişiklik yok», farklıysa `OPENING_EXISTS`; kiracı hesabı ama güncel kiracı yok `NO_TENANT`
  uyarısı; devirden başka mali kayıt `OPENING_LEDGER_EXISTS` uyarısı; pasif daire `APARTMENT_INACTIVE`; kapalı ay `PERIOD_CLOSED`.
- Yazım: satır başına bir `charge` (`source_kind='opening'`, `source_id` = çalıştırma, `definition_name='Devir bakiyesi'`, `payer_party = account_party` = hesap,
  `period` = devir ayı). Audit `finance.opening.imported`. Gelir-gider `charged` toplamı devri saymaz (`source_kind IS DISTINCT FROM 'opening'`).
- Geri alma ve liste uçları: `docs/PLATFORM_FINANS.md` «Devir bakiyesi». Şablonlar tür grubuna göre ayrı dosyadır (klasik üçlü / hepsi bir arada / devir),
  mevcut dairelerle ön doludur.
- Yakında: `opening_minor` rapor alanı, «Bu ay yazılan» devir ayrımı, alacaklı (eksi) devir, `HOLDER_AFTER_DUE` uyarısı.

## Liste arama ve Excel'e aktarma, sade finans dili (paket 3E)

- Yeni yardımcı `lib/ui/helpers/list_export.dart`: `localExportSource` + `ListExportButton`. Dosyayı istemci üretir (mevcut `ExportSheet`, CSV/XLSX üreticisi ve formül kaçışı); sunucu ucu, tablo ya da migration YOK.
- Düğme liste başlığında: duyurular, iş talepleri, ziyaretçi/kargo, konsiyerj, rezervasyonlar, anket sonuçları, firmalar, sözleşmeler, kararlar, belgeler. Yalnız ekranda yüklü (süzgeç/aramaya uyan) kayıtlar yazılır.
- Anket listesine yerel başlık araması eklendi. Konsiyerj ve rezervasyon listeleri sunucu imleçli olduğundan aramaları "Yakında".
- Finans dili: tahakkuk -> "Yazılan borç", mutabakat -> "Banka / kasa kontrolü". Rapor adları: Aylık özet, Yıllık hesap (kurul özeti), Daire ekstresi, İcra dökümü, Gecikmiş borçlar.


---

## 📑 Hesap açma: kullanıcı adı, başlangıç şifresi ve daire admini (`provisionImportedResidents`)

Bu bölüm son kullanıcı gereksinimleri ve saha operasyonları doğrultusunda eklenmiştir. Kod: `server/src/modules/bulk_import_writer.js` (`provisionImportedResidents`, `slugifyLoginName`), `bulk_import_service.js` (commit akışı), `server/src/services/apartment_service.js` (`ensureUniqueLoginName`), `server/src/modules/people_service.js` (`grantApartmentAccess`). 2026-10-26'da koddan doğrulandı; bu bölüm üstteki metinle çeliştiği yerde ÖNCELİKLİDİR.

1. **Kapsam:**
   - Hesap yalnız `people` ve `all_in_one` türlerinde açılır (`ACCOUNT_KINDS`). `apartments`, `vehicles` (araç yüklemesi) ve `opening_balances` hesap AÇMAZ.
   - Hesap adayı yalnız BU çalıştırmada daire ilişkisi (`apartment_residencies`) EKLENEN kişilerdir (yeni kişi ya da hesapsız mevcut kişi). Sitedeki diğer hesapsız sakinlere dokunulmaz; ad/e-posta/telefon ile ayrıca eşleştirme yapılmaz.
   - Kişi başına TEK hesap açılır: aynı kişiye iki dairede ilişki eklendiyse iki daire aynı hesaba bağlanır.

2. **Sütun tanımları (`kullanici_adi`, `sifre`; yalnız `people` ve `all_in_one` şemalarında):**
   - `kullanici_adi`: İsteğe bağlı (en çok 50 karakter). Boş bırakıldığında kişinin ad-soyadından üretilir. Üretim kuralı sunucuda `slugifyLoginName`, istemcide `generateUsernameFromFullName` (AYNI kural): Türkçe harfler sadeleşir, küçük harf, `[a-z0-9]` dışındaki her öbek tek nokta, baştaki/sondaki nokta atılır, en çok 36 karakter (örn. `ahmet.yilmaz`).
   - Çakışmada ek `_2`, `_3` … olur (örn. `ahmet.yilmaz_2`; `ahmet.yilmaz2` DEĞİL). Sunucu `ensureUniqueLoginName` ile adı tüm kullanıcılar arasında büyük/küçük harf duyarsız benzersizleştirir (en çok 100 deneme).
   - `sifre`: İsteğe bağlı (en çok 30 karakter). Excel ve CSV şablonlarında her satırda hazır `1234` dolu gelir. Boş bırakılsa dahi `1234` kabul edilir (`DEFAULT_ACCOUNT_PASSWORD`).

3. **Önizleme tablosu ve canlı teklik doğrulaması (`BulkEditableTable`):**
   - Excel yüklenince `BulkImportController` her satır için kullanıcı adını üretir (tablodaki başka satırlarla çakışırsa `_2`, `_3` … ekler) ve tabloda gösterir.
   - Yönetici hücreye tıklayarak kullanıcı adını değiştirebilir. Değiştirme penceresinde yazılan ad sunucudaki kuralla sadeleştirilip tablodaki DİĞER satırlarla karşılaştırılır; aynı ad başka satırda varsa «Bu kullanıcı adı başka bir satırda zaten var!» denir ve kaydedilmez.
   - Bu denetim yalnız dosyadaki satırları kapsar. Veritabanında zaten var olan bir kullanıcı adıyla çakışırsa sunucu commit sırasında ek koyar; kesin ad sonuç ekranından öğrenilir (madde 6).

4. **Commit ve hesap açma (`provisionImportedResidents`):**
   - Aşama, kişi/ilişki yazımından SONRA ve AYNI transaction'dadır. Her kişi kendi `SAVEPOINT`'inde işlenir: veri sorunu olursa yalnız o kişinin hesabı geri alınır (kişi kaydı yazılmış kalır) ve `skipped_items` içinde nedeniyle bildirilir. Kilitlenme, kilit zaman aşımı ve bağlantı hataları yutulmaz; commit geri alınır.
   - **E-posta kuralı:** kişinin gerçek e-postası varsa (`@ahbu.local` dışında) ve bu e-postayla kayıtlı bir kullanıcı bulunursa, yalnız şu hesaba bağlanır: silinmemiş, `super_user`/`site_manager` OLMAYAN ve bu sitede zaten bağı olan (`siteTiePredicate`) hesap (`status: linked`; mevcut şifre ve kullanıcı adı değişmez). Başka siteye ya da yöneticiye ait e-postaya BAĞLANMAZ: hesap açılmaz, `EMAIL_IN_USE` («Bu e-posta başka bir hesaba ait; hesap açılmadı. Kişi kaydı yapıldı, hesabı kişi kartından açabilirsiniz.») bildirilir. Hesap bu sitede zaten başka bir kişiye bağlıysa `ACCOUNT_ALREADY_LINKED`.
   - **Yeni hesap:** `users` satırı rol `apartment_owner`, aktif, e-postası doğrulanmış, `approval_status = 'approved'`, `must_change_password = TRUE`; şifre (`1234` ya da tablodaki) bcrypt ile özetlenir (her hesap kendi tuzuyla, özetler transaction dışında hesaplanır). Kişinin e-postası yoksa dahili bir daire e-postası üretilir. `users.login_name` madde 2'deki nihai ad olur.
   - Kişi kaydı hesaba bağlanır (`site_people.user_code`; ad/telefon/e-posta bundan sonra `users`'tan okunur).
   - **Daire admini:** daire erişimi `grantApartmentAccess` ile verilir (daire kilitli; `apartment_memberships`, boşsa `apartments.resident_user_code`, site düzeyinde `RESIDENT`). Dairede TEK `APARTMENT_ADMIN` olur: dairede başka aktif admin yoksa kişi `APARTMENT_ADMIN`, varsa `FAMILY_MEMBER` yazılır. Adaylar en iyi ilişkiye göre sıralanır (`RELATION_RANK`: **kiracı, malik**, sakin, aile üyesi; admin önceliği kiracı > malik > diğerleri, kullanıcı kararı 2026-10-26), bu yüzden aynı dairede önce kiracının hesabı açılır ve kiracı admin olur. Dosyada kiracı varsa admin HER ZAMAN kiracıdır: dairede mevcut admin malik olsa bile, hesaplar açıldıktan sonra commit sonunda kiracı eklenen / kiracıya yükseltilen daireler için `ensureTenantIsAdmin` çalışır (eski «mevcut admin korunur» kuralı kiracı lehine değişti; kiracının hesabı yoksa ya da açılamadıysa hesap bağlanınca geçer). Ayrıntı: `docs/PLATFORM_DAIRE_YONETIMI.md` «Kiracı her zaman daire admini».
   - Yeni açılan hesapta, hesabın daire göstergesi (`resident_user_code`) olduğu dairelerde `apartments.resident_pin_issued = TRUE` ve `is_active = TRUE` işaretlenir.
   - Audit: kişi başına `person.account_created` (`details`: `user_code`, `status` created|linked, `via:'import'`, `run_id`; kullanıcı adı/şifre YOK); `import.committed` sayıları `accounts_created`, `accounts_linked`, `accounts_skipped` taşır.

5. **İlk giriş ve zorunlu şifre değişimi:**
   - Sakin `1234` (ya da tablodaki şifre) ile girer. `users.must_change_password` iken sunucu (`auth_middleware.js`) şu uçlar dışındaki TÜM kimlik doğrulamalı isteklere `403 PASSWORD_CHANGE_REQUIRED` döner: `GET /me`, `PATCH /me`, `GET|POST /me/consents`, daire sakininin kendi şifresini değiştirme ucu ve telefon bildirimi cihaz kaydını silme.
   - Uygulama bu durumda `ForceChangePasswordDialog` açar. Yeni şifre kaydedilince `must_change_password = FALSE` olur.

6. **Sonuçta nihai kullanıcı adları:** commit yanıtı `result.accounts` taşır: `{ created, linked, skipped, items: [{ n, login_name, status }], skipped_items: [{ n, code, message }] }`. `login_name` sunucunun yazdığı NİHAİ addır (çakışmada ek konmuş olabilir). Sonuç adımı en çok 30 hesabı listeler (`kMaxListedAccounts`); fazlası için «Kullanıcı adlarını kişi kartlarında görebilirsiniz» der. Hesabı açılmayan kişiler satır numarası ve nedenle gösterilir.
