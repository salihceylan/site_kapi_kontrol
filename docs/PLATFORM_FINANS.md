# Platform — Aidat ve Finans (Faz 4a) sözleşmesi

Bu belge sunucu (`server/`) ve uygulama (`lib/`) için BAĞLAYICIDIR. Öncül belgeler: `docs/PLATFORM_MODUL_SISTEMI.md` (modül kataloğu, modül açma/talep akışı, `MODULE_DISABLED`), `docs/PLATFORM_KISILER.md` (daire alanları: `gross_area_m2`, `net_area_m2`, `land_share_*`, `category`, `responsible_party`; kişi/ilişki; kilit sırası kuralları), `docs/PLATFORM_DUYURU.md` (hız sınırı, e-posta, strict testler, gerçek-PG betiği kalıpları). Kalıplar Faz 2/3'teki gibi aynen örnek alınır.

## Kapsam

**Faz 4a (bu belge):** aidat tanımı (4 dağıtım yöntemi), aylık borçlandırma (önizleme + onay), tek seferlik ek borç, daire hesabı (ekstre), sakin "Borcum", elle tahsilat kaydı, düzeltme (silme YOK, ters kayıt), ay kapatma, yönetim kurulu salt okunur, modül açma/kapama.
**Faz 4b (sonra):** makbuz PDF (F4.07), gecikme tazminatı (F4.08), gider kaydı + belge fotoğrafı (F4.09; dosya yükleme bağımlılığı), kasa/banka hesapları ve aktarım (F4.10), raporlar + Excel/PDF (F4.11), borç hatırlatma (F4.14). **Online kart ödemesi ve banka bağlantısı YOK ("Yakında…", F8).**

## İlkeler (para bütünlüğü)

1. **Para = tamsayı kuruş** (`*_minor`, `BIGINT`); JSON'da tamsayı. HİÇBİR yerde kayan nokta ile para hesabı yapılmaz (sunucu ve uygulama). Para birimi `TRY` (sütun `currency`, bugün hep TRY). Uygulama girişi "1.234,56" biçimini kesin olarak kuruşa çevirir (yuvarlama yok, ≥3 ondalık reddedilir).
2. **Defter eklemelidir (append-only):** `ledger_entries` satırı oluşturulduktan sonra DEĞİŞTİRİLEMEZ ve SİLİNEMEZ (DB tetikleyicisi `BEFORE UPDATE OR DELETE` hata verir; tek istisna: üst `sites` satırı artık yoksa CASCADE silmeye izin). Yanlış kayıt **ters kayıtla** düzeltilir.
3. **Bakiye = satırların işaretli toplamı:** `amount_minor > 0` borç (daire borçlu), `< 0` tahsilat/alacak. `balance_minor = SUM(amount_minor)`; pozitif = borç, negatif = alacak.
4. **Atomiklik ve idempotans:** borçlandırma, tahsilat ve düzeltme tek işlemde; çift tıklama/yeniden deneme çift kayıt YARATMAZ (kısmi tekil indeksler + `idempotency_key`).
5. **Dönem (muhasebe ayı):** `period DATE` = ayın ilk günü (Europe/Istanbul). Kapatılmış döneme kayıt eklenemez; düzeltme AÇIK dönemde ters kayıtla yapılır.
6. **Yetki:** yazma = yönetici/süper (`hasSiteManagementAccess`); okuma = yönetici/süper + `BOARD_MEMBER` (salt okunur; tüm daire bakiyelerini görür); `STAFF` 403; sakin yalnız KENDİ dairesini (`/app/my-finance`). Başka site 403/404. `finance` modülü site için KAPALIYSA tüm finans uçları 403 `MODULE_DISABLED` (`module: 'finance'`).
7. **Eklemeli şema:** `migrations/034_finance.sql` ile `ensureDbSchema` (server/src/db.js) AYNI idempotent DDL (prod'da yalnız `ensureDbSchema` çalışır, DDL hatası = sunucu açılmaz). Mevcut tablo/akış değişmez; tek istisna: `catalog.js` `finance` → `available` (varsayılan KAPALI, `toggleable`, süper açar; yönetici modül talep eder) ve daire azaltmada mali kaydı olan dairenin silinmesinin engellenmesi (aşağıda).
8. Kilit sırası Faz 2/3 kuralı: apartments (id sırasıyla) → users → site_people/… → finans tabloları. Borçlandırma `pg_advisory_xact_lock(finance_post:<site>)` alır; yeni kilit çatışması yaratma. 40P01'de tek yeniden deneme.

## Veritabanı (migration `034_finance.sql`)

- `fee_definitions(id BIGSERIAL PK, site_code BIGINT NOT NULL REFERENCES sites ON DELETE CASCADE, name TEXT NOT NULL (1–80), kind TEXT NOT NULL CHECK (recurring|one_time), distribution TEXT NOT NULL CHECK (fixed|equal|category|land_share|area), area_basis TEXT NULL CHECK (gross|net) (yalnız distribution='area'), amount_minor BIGINT NULL CHECK (amount_minor > 0) (fixed: daire başı tutar; equal/land_share/area: TOPLAM tutar; category: NULL), category_amounts JSONB NULL ({ "<kategori>": <daire başı kuruş> }, yalnız category), due_day SMALLINT NULL CHECK (1..28) (aylık vade günü; one_time için vade tarihi ayrı), start_period DATE NOT NULL, end_period DATE NULL, target_type TEXT NOT NULL DEFAULT 'site' CHECK (site|blocks|apartments), target_block_ids BIGINT[] NOT NULL DEFAULT '{}', target_apartment_ids BIGINT[] NOT NULL DEFAULT '{}', is_active BOOLEAN NOT NULL DEFAULT TRUE, created_by INTEGER NULL REFERENCES users ON DELETE SET NULL, created_at, updated_at)`. Tutarlılık CHECK'leri dağıtım yöntemine göre (ör. `category` ⇒ `category_amounts` dolu ve `amount_minor` NULL; `fixed|equal|land_share|area` ⇒ `amount_minor` dolu; `kind='recurring'` ⇒ `due_day` dolu).
- `fee_runs(id BIGSERIAL PK, site_code, definition_id BIGINT NOT NULL REFERENCES fee_definitions, period DATE NOT NULL, total_minor BIGINT NOT NULL, apartment_count INTEGER NOT NULL, posted_by INTEGER NULL REFERENCES users ON DELETE SET NULL, posted_at TIMESTAMPTZ NOT NULL DEFAULT NOW())`; `UNIQUE (definition_id, period)` ("aynı ay ikinci kez borçlandırılamaz"). Tek seferlik ek borç da bir `fee_runs` satırıdır (period = vade/kayıt ayı; `kind='one_time'` tanımı yalnız bir kez çalışır).
- `ledger_entries(id BIGSERIAL PK, site_code BIGINT NOT NULL REFERENCES sites ON DELETE CASCADE, apartment_id BIGINT NOT NULL REFERENCES apartments ON DELETE RESTRICT, kind TEXT NOT NULL CHECK (charge|payment|reversal), amount_minor BIGINT NOT NULL CHECK (amount_minor <> 0) (charge > 0, payment < 0 CHECK'le; reversal karşı işaret), currency TEXT NOT NULL DEFAULT 'TRY', period DATE NOT NULL, entry_date DATE NOT NULL (tahsilat/borç tarihi), due_date DATE NULL, definition_id BIGINT NULL REFERENCES fee_definitions, run_id BIGINT NULL REFERENCES fee_runs, payer_party TEXT NOT NULL CHECK (owner|tenant|both) (kayıt anında dairenin `responsible_party`'si), method TEXT NULL CHECK (cash|transfer|cheque) (yalnız payment), description TEXT NULL (≤200), reverses_entry_id BIGINT NULL REFERENCES ledger_entries, reversal_reason TEXT NULL (≤200), idempotency_key TEXT NULL (≤64), created_by INTEGER NULL REFERENCES users ON DELETE SET NULL, created_at TIMESTAMPTZ NOT NULL DEFAULT NOW())`. Kısmi tekil indeksler: `(reverses_entry_id) WHERE reverses_entry_id IS NOT NULL` (bir kaydın tek ters kaydı olur); `(site_code, idempotency_key) WHERE idempotency_key IS NOT NULL`. İndeksler: `(site_code, apartment_id, entry_date, id)`, `(site_code, period)`, `(run_id)`. `BEFORE UPDATE OR DELETE` tetikleyicisi (`CREATE OR REPLACE FUNCTION` + pg_trigger kontrollü): hata `finance ledger is append-only`; DELETE yalnız `NOT EXISTS (SELECT 1 FROM sites WHERE site_code = OLD.site_code)` iken serbest.
- `finance_period_closures(site_code BIGINT NOT NULL REFERENCES sites ON DELETE CASCADE, period DATE NOT NULL, closed_by INTEGER NULL REFERENCES users ON DELETE SET NULL, closed_at TIMESTAMPTZ NOT NULL DEFAULT NOW(), PRIMARY KEY (site_code, period))`. Dönemler SIRAYLA kapanır: bir ayı kapatmak için önceki ay kapalı olmalı (siteye ilk kapatmada serbest); yalnız EN SON kapatılan ay yeniden açılabilir ve yalnız süper kullanıcı açar.
- Daire azaltma: `syncSiteStructureCounts` (site_service.js) silinecek dairelerden birinin `ledger_entries` kaydı varsa işlemi **geri alır ve 409 `APARTMENT_HAS_FINANCE`** ("Mali kaydı olan daire silinemez") döner; mevcut daire azaltma davranışı mali kaydı olmayan dairelerde AYNEN kalır; site silme (CASCADE) çalışır.

## Dağıtım ve yuvarlama

- Dahil edilen daireler: hedefteki (`target_*`) **aktif** daireler. Tutar payları **en büyük kalan** yöntemiyle kuruşa bölünür (toplam payların toplamına BİREBİR eşit olmalı; eşitlikte `apartment_id` küçük olan önce): `equal` (ağırlık 1), `land_share` (ağırlık = `numerator/denominator`, tam sayı aritmetiği: ortak payda ile), `area` (ağırlık = seçili m² × 100 tamsayı). `fixed`: her daireye `amount_minor`. `category`: dairenin `category`'sine karşılık gelen daire başı tutar.
- Eksik veri (arsa payı/m²/kategori tanımsız ya da kategori haritada yok): önizlemede `missing_data` listesi; `commit` bu durumda 409 `PREVIEW_INCOMPLETE` döner (varsayılan), yönetici `skip_missing: true` ile o daireleri hariç tutarak devam edebilir (hariç tutulanlar audit `details`'ında sayı olarak yazılır).
- **Kim öder:** her daire için `payer_party = apartments.responsible_party` (kayıt anındaki değer kopyalanır, sonradan değişse de eski kayıt değişmez). Borç tek daire hesabına yazılır; kimin GÖRECEĞİ `responsible_party`'ye uyar (aşağıda).
- Vade: aylık tanımda `due_date = period + (due_day-1) gün`; ek borçta istekteki `due_date` (yoksa kayıt günü).

## Yönetici uçları (`/manager/sites/:siteCode/finance/…`)

Hata gövdesi `{ error, code }` (Türkçe). Tutarlar kuruş tamsayı. Yazmalar 120/saat/kullanıcı, okuma 1200/saat.

**Tanımlar**
- `GET …/definitions?kind=&active=` → `{ items: [Definition] }`; `Definition`: tüm alanlar + `last_posted_period`.
- `POST …/definitions` gövde `{ name, kind, distribution, area_basis?, amount, category_amounts?, due_day?, start_period, end_period?, target }` (`amount`/`category_amounts` TL değil KURUŞ: `amount_minor`, `category_amounts`) → 201 `Definition`. `PATCH …/definitions/:id` (yalnız henüz hiç borçlandırılmamış tanımın tutar/dağıtımı değişir; borçlandırılmışta yalnız `name`, `end_period`, `is_active`, `due_day` — geçmiş kayıtlar zaten değişmez). Silme YOK (`is_active:false`).
- `POST …/definitions/:id/preview` gövde `{ period }` (recurring) ya da `{ due_date? }` (one_time) → `{ period, definition_id, total_minor, apartment_count, lines: [{ apartment_id, label, block_name, payer_party, amount_minor }], missing_data: [{ apartment_id, label, reason }], already_posted: bool, closed: bool }` — YAZMAZ.
- `POST …/definitions/:id/post` gövde `{ period?, due_date?, expected_total_minor, expected_apartment_count, skip_missing?, idempotency_key? }` → önizlemeyle aynı hesabı yeniden yapar; toplam/daire sayısı beklenenle UYUŞMAZSA 409 `PREVIEW_STALE` (ve hiçbir şey yazılmaz); aynı (tanım, dönem) için 409 `PERIOD_ALREADY_POSTED`; dönem kapalıysa 409 `PERIOD_CLOSED`; tanım pasif/süresi dışıysa 409 `DEFINITION_INACTIVE` → 201 `{ run, entries_count }`.
- `POST …/charges` (**ek borç**) gövde `{ name, amount_minor, distribution, area_basis?, category_amounts?, target, due_date?, expected_total_minor, expected_apartment_count, skip_missing?, idempotency_key? }` → tek işlemde tek seferlik tanım + önizleme doğrulaması + borçlandırma (önizleme için `POST …/charges/preview` aynı gövde) → 201.

**Hesaplar**
- `GET …/balances?status=debtor|credit|all&q=&limit=50&offset=0` → `{ items: [{ apartment_id, label, block_name, balance_minor, overdue_minor, owner_name, tenant_name }], total, totals: { debt_minor, credit_minor } }` (`q`: daire etiketi, sakin adı).
- `GET …/apartments/:apartmentId/account?from=&to=&limit=50&before_id=` → `{ apartment: {id,label,block_name,responsible_party}, balance_minor, overdue_minor, items: [Entry], next_before_id }`; `Entry`: `{ id, kind, amount_minor, period, entry_date, due_date, description, method, payer_party, definition_name, reverses_entry_id, reversed_by_entry_id, reversal_reason, created_by_name, created_at }` (sıra `entry_date DESC, id DESC`).

**Tahsilat ve düzeltme**
- `POST …/payments` gövde `{ apartment_id, amount_minor (>0, KURUŞ; tahsilat tutarı pozitif girilir, defter −), entry_date, method, description?, idempotency_key }` → 201 `{ entry, balance_minor }`. Fazla ödeme alacak olarak görünür (bakiye negatif). Dönem = `entry_date`'in ayı; kapalıysa 409 `PERIOD_CLOSED`. Gelecek tarih 400. Aynı `idempotency_key` ile tekrar = aynı kayıt (200).
- `POST …/entries/:id/reverse` gövde `{ reason? (≤200), idempotency_key? }` → karşı işaretli `reversal` kaydı (dönem = bugünün AÇIK ayı; gerekirse en erken açık ay); zaten ters kayıtlı ya da kendisi ters kayıt ise 409 `ENTRY_ALREADY_REVERSED` / `ENTRY_NOT_REVERSIBLE`; 201 `{ entry, balance_minor }`.
- `POST …/entries/:id/correct` (yalnız `payment`) gövde `{ amount_minor, entry_date, method, description?, idempotency_key }` → TEK işlemde ters kayıt + yeni tahsilat → 201 `{ reversal, entry, balance_minor }`.

**Dönemler**
- `GET …/periods` → `{ closed_through: 'YYYY-MM'|null, items: [{ period, closed_at, closed_by_name }], open_period: 'YYYY-MM' }`. `POST …/periods/:period/close` (sıralı; gelecek ay kapatılamaz: 409 `PERIOD_NOT_CLOSABLE`); `POST …/periods/:period/reopen` (yalnız süper, yalnız en son kapalı ay).

**Okuma özeti** `GET …/summary` → `{ currency, open_period, balance_total_minor, debt_total_minor, credit_total_minor, debtor_count, this_period: { charged_minor, collected_minor } }`.

**Yetki:** kurul (`BOARD_MEMBER`) yalnız `GET` uçlarına erişir (balances, account, definitions, periods, summary); tüm POST/PATCH 403 `FORBIDDEN_ROLE`. `STAFF`/sakin 403. Modül kapalı 403 `MODULE_DISABLED`.

## Sakin ucu

- `GET /app/my-finance` (`authRequired`) → `{ items: [{ site_code, site_name, apartment_id, label, block_name, currency, balance_minor, overdue_minor, next_due_date, next_due_minor, payer_party, visible_from, offset_note, recent: [Entry (son 30; yönetici kimliği/notu YOK)] }] }`: yalnız çağıranın **güncel** (aktif) kişisinin ilişkili olduğu daireler, **modülü açık ve onaylı** siteler.
- **Kim görür (F2.05 `responsible_party` kuralı):** `owner` ise dairenin güncel `owner` ilişkisi olanlar; `tenant` ise `tenant`; `both` ise `owner` + `tenant` + `resident` (belirsiz ilişki). `family_member` HİÇBİR durumda borç görmez. Eşleşen güncel kişi yoksa güvenli yedek: dairenin güncel `resident`/`owner`/`tenant` ilişkili kişileri görür (borç sahipsiz kalmasın); bu yedek davranış sözleşme notu olarak raporlanır. Başkasının dairesi asla.
- Sakin ucu yönetici notlarını/oluşturan adını/diğer dairelerin verisini içermez; `recent` yalnız kendi dairesi.
- **Sakin kapsamı (2026-10-19, KVKK ölçülülük + doğru bakiye; `finance_resident_view.residentView`):**
  - **Başlangıç:** sakinin bu dairedeki güncel ilişkisinin taşınma ayı (`move_in_date`; boşsa ilişki kaydının günü, İstanbul).
    Aynı kişinin aynı dairedeki kesintisiz önceki ilişkisi (ör. kiracıyken satın aldı) zincirin başını öne çeker; yalnız borcu
    görebileceği bir ilişkiyse (malik sorumluyken kiracılık dönemi sayılmaz). Değer okunamazsa sınır kalkmaz, bu ay esas alınır.
  - **Dayanak ayı:** gecikme tazminatı kalemi ve ters kaydı için HESAPLANAN ay (`late_fee_runs.period`), ters kayıt için asıl
    kaydın ayı, diğerlerinde `period` (`residentAnchorSql`). Önceki döneme ait bir kaydın sonradan yazılan iptali ya da
    tazminatı yeni sakine görünmez.
  - **Bakiye (mahsup kuralı, makbuzdaki "vadesi en eski borçtan"):** ters kaydı olmayan borçlar (tazminat dahil) (vade, kimlik)
    sırasıyla, tahsilatlar ve asıl kaydı henüz deftere girmemiş ileri tarihli borçların ters kayıtları (tarih, kimlik) sırasıyla
    dökülür. Sakinin bakiyesi = kapsam içi borçların ödenmemiş kalanı − görünen alacakların artan kısmı. Vadesi boş borçta vade
    yerine kayıt tarihi (M1 ile aynı). Vadesi geçmiş ve sıradaki vade de kapsam içi kalanlardan. Böylece önceki sakinin geç ödemesi
    yeni sakinin borcunu kapatmaz, geçmiş aya yazılan borç ödendiğinde sahte alacak doğmaz. Kapsam yoksa (malik 2020'den beri
    vb.) sonuç dairenin defter toplamıyla aynıdır.
  - **Görünen satırlar:** kapsam içi borç ve ters kayıtlar; tahsilat kapsam içiyse ya da hiçbir kısmı kapsam dışı bir borca mahsup
    edilmediyse (ör. taşınmadan önce peşin ödeme; artanı alacak sayılır). Makbuz, bağlı tahsilatı görünüyorsa görünür; sakinin bu
    dairedeki ilişki kaydından ÖNCE düzenlenmiş makbuzda ödeyen adı sakine gösterilmez (`relation_since_at`). Gecikme açıklaması
    kalemin dayanak ayına göre.
  - **Yanıt alanları:** `visible_from: "YYYY-MM"` yalnız kapsam dışında kayıt VARSA dolar ("Kayıtlar … ayından itibaren"
    notu). `offset_note: true`: görünen satırların toplamı bakiyeye eşit değil (bir tahsilat ya da alacak önceki dönem
    kayıtlarıyla mahsup edildi); istemci mahsup notunu yazar. Sakin ekstresi (`computeResidentStatement`): açılış, kapanış ve
    satır başına kayan bakiye aynı kuralla, satırın tarihindeki duruma göre; `offset_note` aynı anlamda. Sakin ekstresi dairenin
    tüm defterinden hesaplandığı için en çok 2000 defter satırı (aşarsa `STATEMENT_TOO_LARGE`).
  - **Kapsam dışı uçlar:** yönetici ve kurul uçları (`computeStatement`, bakiye listesi, dışa aktarma) dairenin tüm defterini
    görür.
  - **Gerçek PG:** `QA_ONLY=finance4b QA_PART=resident_scope` (S0-S13). Birim: `test/finance_resident_view.test.js`.
  - **Bilinen sınırlar:** (1) kimin ödediği defterde tutulmadığından önceki sakinin taşınmadan SONRA yaptığı ödeme yeni sakine
    satır olarak görünür (bakiyesini etkilemez; makbuzu, yeni sakinin kaydından önce düzenlendiyse adsız). Mahsup daire bazındadır:
    yeni sakinin ödemesi önceki dönemin açık borcuna da gidebilir (TBK 100-102 aynı borçlu içindir; kişi bazlı tahsilat yol haritasında).
    Aynı kişinin önceki ilişki zinciri tek adımdır (güvenli taraf). (2) Taşınma tarihi girilmezse kayıt günü esas alınır; uzun süredir oturan
    biri sonradan kaydedildiyse eski borcu Borcum'da görünmez. Kişi eklerken uyarı ve yönetici ekranında gösterge yol
    haritasında. (3) Gecikme tazminatı ve borç hatırlatma hâlâ daire bazında hesaplanır; açılmadan önce aynı kapsam uygulanacak
    (`docs/PLATFORM_YOL_HARITASI.md`, P0).
- Hız sınırı: 600/saat/kullanıcı.

## Audit

`finance.definition.created|updated|deactivated`, `finance.run.posted`, `finance.charge.posted`, `finance.payment.recorded`, `finance.entry.reversed`, `finance.entry.corrected`, `finance.period.closed|reopened` (`target_type: 'finance'`, `target_id`, `site_code` dolu; `details`: toplamlar/sayılar/dönem — **açıklama/neden metni ve kişi adı yok**). Süper denetim ekranına etiketler eklenir.

## Uygulama (Flutter)

Yeni bağımlılık YOK. Para girişi/gösterimi: ortak yardımcı (`lib/ui/helpers/money.dart`): kuruşa/kuruştan tam biçimleme "1.234,56 ₺", giriş doğrulama (virgül/nokta, ≥3 ondalık red, negatif/boş/aşırı büyük red), kod noktası/erişilebilirlik ("bin iki yüz otuz dört lira elli altı kuruş" semantik etiketi). Faz 2/3 kalıpları: `paged_loader`/`cursor_loader`, `dialog_guard`, `CrmFormError`, `form_validation`, `retry_lock`, `istanbul_time`, `a11y_announce`, sahte sunucu fixture'ları, 320×640 ×2,0 ve 360×640 ×1,5 açık/koyu, strict.
1. **Yönetici — "Finans" (çekmece öğesi; yalnız modül AÇIKKEN):** sekmeler: **Daireler** (bakiye listesi: arama, borçlu/alacaklı süzgeci, toplam kartı, daireye dokununca ekstre), **Tanımlar** (aidat/ek borç tanımları; "Yeni Tanım", düzenle, pasifleştir), **Dönemler** (açık/kapalı aylar, "Ayı Kapat", süperde "Yeniden Aç"). Eylemler: **Borçlandır** (tanım→dönem→ÖNİZLEME listesi [daire, kim öder, tutar] + toplam + eksik veri uyarısı → onay; `PREVIEW_STALE` olursa önizlemeyi yenile), **Ek Borç Ekle** (ad, toplam tutar, dağıtım, hedef, vade → önizleme → onay), **Tahsilat Ekle** (daire seçici, tutar, tarih, yöntem, açıklama; çift gönderim koruması + `idempotency_key`), **Düzelt / İptal Et** (tahsilat için; borç için yalnız iptal; neden), daire **Ekstre** penceresi (bakiye, hareketler, ters kayıtlar işaretli, sayfalama). Kapalı dönem hataları açık Türkçe.
2. **Sakin — "Borcum" (çekmece; yalnız alıcısı olabilecek ve modülü açık sitelerde):** toplam borç/alacak, vadesi gelen tutar, sıradaki vade, hareketler; çok daireli kullanıcıda daire seçici/kartlar; boş durum "Borcunuz yok" yalnız gerçekten sıfırken (hata asla "borç yok" demez).
3. **Kurul:** yalnız okuma (yazma düğmeleri/menüsü yok, "yalnızca görüntüleyebilirsiniz" notu).
4. **Modül kapalıyken** Finans/Borcum menüsü görünmez; Modüller ekranında `finance` kartı "Aidat ve Finans" artık `available` (kapalı, yönetici "Modül Talep Et").
5. **Hata kodları** Türkçe eşlenir: `MODULE_DISABLED`, `PREVIEW_STALE`, `PREVIEW_INCOMPLETE`, `PERIOD_ALREADY_POSTED`, `PERIOD_CLOSED`, `PERIOD_NOT_CLOSABLE`, `DEFINITION_INACTIVE`, `ENTRY_ALREADY_REVERSED`, `ENTRY_NOT_REVERSIBLE`, `APARTMENT_HAS_FINANCE`, `INVALID_BODY`.
6. Süper denetim ekranı: yeni eylem etiketleri/süzgeçleri.

## Doğrulama (kabul)

- Sunucu: `npm test` + `npm run lint` yeşil; strict sahte-DB testleri; **gerçek PG** (`qa_platform_pg.mjs`, yeni `finance` bölümü): migrate zinciri = `ensureDbSchema` (CHECK/indeks/tetikleyici dahil, ikinci çalıştırma no-op); dağıtım matematiği (eşit/sabit/kategori/arsa payı/m²; **toplam payların toplamı = tutar**, rastgele girdilerle özellik testi; yuvarlama deterministik; eksik veri); defter değişmezliği (UPDATE/DELETE tetikleyici hatası, site silinince CASCADE geçer); bakiye = toplam; borçlandırma önizleme≠yazma, `PREVIEW_STALE`, aynı dönem ikinci kez 409, eşzamanlı çift `post` tek kayıt, `idempotency_key` tekrarı; tahsilat (fazla ödeme alacak, gelecek tarih 400, kapalı dönem 409); ters kayıt (çift ters 409, ters kaydın tersi 409, bakiye düzelir, düzeltme tek işlem ve yarım kalmaz); ay kapatma sırası/kuralları; yetki matrisi (yönetici yazar, kurul yalnız okur, STAFF/sakin 403, başka site 403/404, IDOR); modül kapalı 403; sakin ucu `responsible_party` matrisi + `family_member` görmez + yedek kural + başka daire sızmaz; daire azaltma `APARTMENT_HAS_FINANCE`; 3000 daireli sitede borçlandırma süresi makul (<3 sn) ve `EXPLAIN` seq scan yok; kilit turları (borçlandırma × tahsilat × ters kayıt × daire azaltma × kullanıcı silme; 40P01 = 0).
- Uygulama: `flutter analyze` temiz, `flutter test` yeşil; para yardımcısı özellik testleri (tam kuruş, hiç kayan nokta), ekran/diyalog testleri, dar ekran + büyük yazı + ekran okuyucu.
- Süreç: Faz 2/3'teki gibi en az iki bağımsız inceleme turu (yetki/gizlilik/para bütünlüğü; veri/yarış/şema), düzeltmeler, canlıya alma (yedek + şema provası + doğrulama + modül varsayılan KAPALI), kontrol listesi güncellemesi (claude.ai + `SAHA_KONTROL_LISTESI.md`).

## Faz 4a inceleme kararları (bağımsız incelemeler sonrası; yukarıdaki metne göre ÖNCELİKLİDİR)

1. **Kapalı dönem = `period <= MAX(kapalı dönem)`.** Bir ay kapatılınca ondan ÖNCEKİ tüm aylar da kapalı sayılır ve hiçbir yazma yolunda (aylık borçlandırma, ek borç, tahsilat `entry_date`, düzeltmenin yeni tahsilatı) yazılamaz → 409 `PERIOD_CLOSED`. Kapatma: ilk kapatmada herhangi bir ay (≤ bu ay, en fazla 5 yıl öncesi), sonra yalnız `closed_through + 1 ay` (≤ bu ay). `GET …/periods` → `{ closed_through, closable: ['YYYY-MM',…] (en yeni önce, ≤ 12; kapanış yoksa bu ay + önceki 11 ay; varsa yalnız closed_through+1), items, open_period }`. Yeniden açma yalnız süper kullanıcı ve yalnız EN SON kapatma satırı; **ilk kapatma satırı açılınca ona bağlı örtük kapalı geçmiş de açılır** (kasıtlı; arayüz uyarmalı). Tarih alt sınırı: `entry_date`/`due_date`/`period` bugünden 5 yıl öncesinden eski olamaz (400 `INVALID_BODY`).
2. **Ek borç tekrar/çift koruması.** `POST …/charges` için `idempotency_key` ZORUNLU; `fee_runs.request_fingerprint` (ad, tutar, dağıtım, alan esası, kategori tutarları, hedef, vade, `skip_missing`) ile aynı anahtar + farklı gövde → 409 `IDEMPOTENCY_CONFLICT`; ayrıca son 24 saatte aynı site/ad(normalize)/tutar/dağıtım/hedef/vade ile ek borç varsa 409 `DUPLICATE_CHARGE` (+ `existing_run_id`, `posted_at`) — bilinçli tekrar için `allow_duplicate: true` (parmak izine ve doğal anahtara GİRMEZ; aynı anahtarla tekrar yine replay'dir). Aylık `post` replay'i için de parmak izi. `expected_*` alanları parmak izine girmez (aynı anahtar + farklı `expected_total_minor` replay döner).
3. **`preview_hash`.** Önizleme yanıtları `preview_hash` (sha256 hex; `v1` + sıralı `apartment_id:amount_minor:payer_party` + eksik veri kümesi) döndürür; `post` ve `charges` gövdesinde `expected_hash` ZORUNLU (`expected_total_minor`/`expected_apartment_count` da kalır); uyuşmazlık → 409 `PREVIEW_STALE` (+ güncel `total_minor`, `apartment_count`, `preview_hash`). Önizleme ek alanları: `redistributed`, `skipped_count`, `duplicate_of_run_id` (ek borç), `zero_amount_count`, `missing_data[].block_name`.
4. **Dağıtım.** Arsa payı 0 (payda > 0) olan daire eksik veri DEĞİL (ağırlık 0, satır yok, `zero_amount_count`); yalnız pay/payda NULL eksiktir. `skip_missing` ile hariç tutulanların payı `equal`/`land_share`/`area` yöntemlerinde kalan dairelere yeniden dağıtılır (`redistributed: true`; toplam birebir korunur); `fixed`/`category`'de dağıtılmaz.
5. **Defter koruması (DB).** `trg_ledger_entries_append_only` (`created_by → NULL` yalnız ilgili kullanıcı ARTIK yoksa), `BEFORE TRUNCATE` (ledger_entries, fee_runs), ters kayıt aynası kontrolü (`BEFORE INSERT`: aynı site/daire, `amount_minor = -asıl`, asıl ters kayıt olamaz, hata P0001), `fee_runs` append-only (site silme ve `posted_by` SET NULL istisnası), `finance_period_closures` UPDATE yasağı (DELETE serbest: yeniden açma satırı siler). `ledger_entries.definition_name` borçlandırma anındaki ANLIK GÖRÜNTÜDÜR (tanım yeniden adlandırılınca geçmiş değişmez; ters kayıt asıldan kopyalar).
6. **Kilit sırası:** `sites KEY SHARE → finance_post advisory → apartments(id) → users(işlemi yapan) FOR KEY SHARE → finans satırları`. Tanım listesi `GET …/definitions?limit=&offset=` → `{ items, total }` (≤ 500; aylık tanımlar önce).
7. **Kabul edilen riskler (Faz 4b'de gözden geçirilecek):** bakiye listesi ve özet her istekte sitenin tüm defterini toplar (≈1M satırda ~350 ms); çok satırlı (≈200k+) kullanıcı/site silme 30 sn `statement_timeout`'a yaklaşır (rollback güvenli); bir sitenin toplam bakiyesi 2^53'ü aşarsa özet 500 verir (gerçekçi değil); `definition_name` anlık görüntüsü sonradan düzeltilemez; ~~sakin dairenin tüm geçmişini (önceki kiracı dönemi dahil) görür~~ (2026-10-19 giderildi: "Sakin kapsamı"). **Dağıtım notu:** 034 DDL'i sert yazma yükü altında `ensureDbSchema` içinde 40P01 alabilir (açılış DDL'inin doğası); `pm2 restart` ile idempotent yeniden denenir, trafiksiz uygulamak güvenlidir. Canlıya almadan önce `site_modules`'ta `finance` için `enabled = TRUE` satırı OLMADIĞI doğrulanır (aksi halde dağıtımda modül sessizce açılır). `finance` varsayılan KAPALIDIR.

## Altın veri seti (F5, 2026-10-21)

Karar F5: gerçekçi bir site için ELLE hesaplanmış tablo; dağıtım, yuvarlama, gecikme tazminatı ve mahsup kodu bu tabloyla kuruşu kuruşuna
karşılaştırılır, tutmazsa test düşer. Beklenen değerlerin hiçbiri kod çalıştırılarak üretilmedi; her birinin hesap adımları fikstürde yazılıdır.
Cenk'in gerçek tablosu gelince ikinci set olarak eklenecek.

- Fikstür (site, senaryolar, adım adım hesap): `server/test/fixtures/finance_golden_site.js`
- Test: `server/test/finance_golden_dataset.test.js` (gerçek `buildDistributionPlan`, `lateFeeForApartment` + gün gün kaba kuvvet tanımı, `m1Remainders`).
- Sapma çıkarsa önce fikstürdeki elle hesap iki kez yeniden yapılır; hesap doğruysa hata raporlanır, hesap kodu fikstüre uydurulmaz.
  İlk koşu (2026-10-21): 21 kontrolün hepsi ilk seferde tuttu (sapma yok).

**Site ("Altın Veri Sitesi"):** A Blok 12 daire (2 dükkan + 10 adet 3+1), B Blok 12 daire (4 adet 1+1 + 8 adet 2+1); daire kimliği sıradır
(A-1 = 1 ... B-12 = 24; eşit kalanda kimliği küçük olan önce kuruş alır).

| Daire | Kategori | Brüt m² | Net m² | Arsa payı |
| --- | --- | --- | --- | --- |
| A-1 | Dükkan | 85,50 | 68,75 | 50/1200 |
| A-2 | Dükkan | 64,25 | 54,50 | 40/1200 |
| A-3..A-7 | 3+1 | 120,00 | 100,00 | 62/1200 |
| A-8..A-12 | 3+1 | 118,25 | 98,75 | 61/1200 |
| B-1..B-4 | 1+1 | 62,40 | 52,00 | 54/2400 |
| B-5..B-8 | 2+1 | 101,20 | 84,50 | 97/2400 |
| B-9, B-10 | 2+1 | 101,15 | 84,25 | 96/2400 |
| B-11, B-12 | 2+1 | 101,15 | 84,25 | 97/2400 |
| **Toplam** | | **2.400,00** | **2.000,00** | **2400/2400** |

Dağıtım kuralı: `pay = taban(T x w / W)`; artan kuruşlar en büyük kalan (`T x w mod W`) sırasıyla birer birer; eşitlikte küçük kimlik.

| Senaryo | Tutar (T) | Ağırlık toplamı (W) | Artan kuruş | Sonuç (kuruş) |
| --- | --- | --- | --- | --- |
| D1 eşit | 8.500.000 (85.000,00 TL) | 24 | 16 | A-1..B-4: 354.167; B-5..B-12: 354.166 |
| D2 brüt m² | 1.000.000 (10.000,00 TL) | 240.000 | 11 | A-1 35.625; A-2 26.771; A-3..A-7 50.000; A-8..A-12 49.271; B-1..B-4 26.000; B-5 42.167; B-6..B-8 42.166; B-9..B-12 42.146 |
| D3 net m² | 500.003 (5.000,03 TL) | 200.000 | 8 | A-1 17.187; A-2 13.625; A-3..A-7 25.000; A-8..A-12 24.688; B-1..B-4 13.000; B-5..B-8 21.125; B-9..B-11 21.063; B-12 21.062 |
| D4 arsa payı | 3.600.019 (36.000,19 TL) | 2.400 (1200'lük paylar x2) | 19 | A-1 150.001; A-2 120.000; A-3..A-7 186.001; A-8..A-12 183.001; B-1..B-4 81.000; B-5..B-8 145.501; B-9, B-10 144.001; B-11, B-12 145.501 |
| D5 kategori | daire başı | — | — | Dükkan 150.000; 3+1 125.000; 2+1 100.000; 1+1 75.000 (toplam 2.650.000; "DÜKKAN" yazımı "Dükkan" ile eşleşir) |
| D6 sabit | daire başı 50.000 | — | — | her daire 50.000 (toplam 1.200.000) |

Yuvarlama örnekleri: D2'de 11 kuruşun 10'u kalanı 200.000 olan 10 daireye, 1'i kalanı 160.000 olan dört daireden kimliği küçük B-5'e gider;
D3'te kalanı eşit dört daireden (B-9..B-12) yalnız ilk üçü artan kuruşu alır; D4'te kalanı en küçük A-2 ve B-1..B-4 artan kuruş almaz.

**Gecikme tazminatı** (aylık %5 = 500 bp; `fee = taban((2 x S x R + 10.000 x D) / (20.000 x D))`, S = kuruş x gün; vade günü ve ödeme günü
gecikme sayılmaz; tazminat kalemleri tabana girmez ama vadesine göre ödemeyi önce tüketir):

| Senaryo | Defter | Dönem | S (kuruş x gün) | Tazminat |
| --- | --- | --- | --- | --- |
| L1 (A-3) | Eylül aidatı 125.000 (vade 05.09) ödenmedi | Ekim 2026 (31 gün) | 31 x 125.000 = 3.875.000 | daily_30: 6.458 (%5 x 31/30); daily_actual: 6.250 (tam %5) |
| L2 (A-4) | Ağu/Eyl/Eki aidatı 125.000'er; ödeme 20.09'da 150.000, 15.10'da 100.000 | Ekim 2026 | 5 x 100.000 + 9 x 225.000 + 17 x 125.000 = 4.650.000 | daily_30: 7.750 |
| L3 (B-5) | Ekim aidatı 100.000 (vade 10.10) + önceki tazminat kalemi 2.000 (01.10); ödeme 25.10'da 50.000 | Ekim 2026 | ek gün 5: 9 x 100.000 + 7 x 52.000 = 1.264.000; ek gün 0: 14 x 100.000 + 7 x 52.000 = 1.764.000 | daily_30: 2.107 (ek gün 5), 2.940 (ek gün 0) |
| L4 (A-7) | 100.000 (vade 05.01.2027) ödenmedi | Şubat 2027 (28 gün) | 28 x 100.000 = 2.800.000 | daily_30: 4.667 (%5 x 28/30); daily_actual: 5.000 (tam %5) |

Aylık %5 sınırı: ayın tamamı gecikmedeyken `daily_actual` tam %5 verir (L1, L4); `daily_30` 31 günlük ayda %5'in 31/30'u, 28 günlük ayda 28/30'u
kadardır ("geciktiği günler için aylık yüzde beş hesabıyla" yorumu) `[AVUKAT DOĞRULASIN]`. Oran 500 bp'yi aşamaz: ayar 501'i reddeder, kurallar
tablosuna daha yüksek değer yazılsa bile üst sınır 500'e kırpılır (`docs/PLATFORM_KURALLAR.md`).

**Mahsup (M1, vadesi en eski borçtan; vade eşitse kayıt sırası):**

| Senaryo | Borçlar (vade sırasıyla) | Ödenen | Kalanlar | Alacak |
| --- | --- | --- | --- | --- |
| M1 (A-5) | Eylül 125.000 (05.09); çatı payı 186.001 (20.09, 02.10'da yazıldı); Ekim 125.000 (05.10) | 200.000 | 0; 111.001; 125.000 | 0 |
| M2 (B-1) | Eylül 75.000; Ekim 75.000 | 200.000 | 0; 0 | 50.000 |
| M3 (B-6) | aynı vade (05.10): aidat 100.000 (kimlik 601), ortak gider payı 42.166 (kimlik 602) | 120.000 | 0; 22.166 | 0 |
