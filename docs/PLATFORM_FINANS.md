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
  > **İP-1A (2026-10-21) ile değişti:** her dairenin iki hesabı vardır (ev sahibi / kiracı); borç tanımın "kim öder" (`charge_party`) değeri ve borç tarihindeki kiracı durumuna göre bu hesaplardan BİRİNE yazılır. `payer_party` anlık görüntü olarak yazılmaya devam eder. Bkz. **İki hesap (2026-10-21)**.
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
  > **İP-1A (2026-10-21) ile değişti:** sakin dairenin KENDİ HESABINI görür (malik -> ev sahibi hesabı, kiracı -> kiracı hesabı, ilişkisi belirtilmemiş -> dairede güncel kiracı varsa kiracı, yoksa ev sahibi hesabı; `family_member` hiçbirini); borç sorumlusu `both` ise malik kiracı hesabını SALT OKUNUR da görür. Malik ve kiracı için yedek kural kalktı (her biri kendi hesabını görür). İlişkisi belirtilmemiş kişi için yukarıdaki koşul AYNEN kalır (bağımsız inceleme): yalnız sorumlu `both` iken ya da sorumlu tarafın güncel kişisi yokken görür. Bkz. **İki hesap (2026-10-21)**.
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
    (`docs/PLATFORM_YOL_HARITASI.md`, P0). **İP-1A (2026-10-21):** mahsup, tazminat ve hatırlatma artık HESAP bazındadır ve
    "kim ödedi" sorusu hesapla yanıtlanır (kiracının ödemesi kiracı hesabına); (1) daire bazlı mahsup notu iki hesap için geçerli
    değildir. Bkz. **İki hesap (2026-10-21)**.
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

## İki hesap (2026-10-21; İP-1A, karar G12 — yukarıdaki metne göre ÖNCELİKLİDİR)

Kaynak: `docs/PLATFORM_YOL_HARITASI.md` "Karar kaydı (2026-10-21)" G12; alt plan `docs/superpowers/plans/2026-10-21-ip-1a.md`. Migration **052**
(`052_finance_parties.sql`; `finance_parties_schema.js` aynı adımları `ensureDbSchema` sonunda katalog korumalı, her adım kendi işleminde uygular).

### Kurallar

1. **Her dairenin iki hesabı vardır:** "Ev sahibi hesabı" (`owner`) ve "Kiracı hesabı" (`tenant`). Bakiyeler KARIŞMAZ: bir hesabın tahsilatı ya da
   alacağı diğer hesabın borcuna mahsup edilmez. Mahsup (vadesi en eski borçtan, TBK 102) her hesabın kendi içindedir.
2. **Kim öder** (`fee_definitions.charge_party`): `owner` ⇒ ev sahibi hesabı; `occupant` ("dairede oturan") ⇒ dairenin `responsible_party` değeri
   `owner` ise ev sahibi; `tenant` / `both` ise BORÇ TARİHİNDE dairenin etkin kiracısı varsa kiracı, yoksa ev sahibi hesabı. Borç tarihi: aylık aidatta
   dönemin ilk günü, ek borçta kayıt günü. Etkin kiracı: `relation = tenant` ilişkisi tarihi kapsar (başlangıç `move_in_date`, boşsa ilişki kaydının
   günü, İstanbul; güncel ilişkide kişi etkin; bitmiş ilişkide `move_out_date >= tarih`, çıkış günü dahil). NULL = türe göre varsayılan: aylık aidat
   `occupant`, tek seferlik ek borç `owner`. Değişiklik yalnız SONRAKİ borçlandırmaları etkiler (borçlandırılmış tanımda da değişebilir).
3. **Kişinin kendi hesabı:** `owner` ⇒ ev sahibi; `tenant` ⇒ kiracı; `resident` (ilişki belirtilmemiş) ⇒ dairede güncel kiracı varsa kiracı, yoksa ev
   sahibi; `family_member` ⇒ hesap yok (borç görmez).
4. **Kim görür:** sakin YALNIZ kendi hesabını görür. Borç sorumlusu `both` ise malik kiracı hesabını SALT OKUNUR da görür (müteselsil sorumluluk; bu
   tutar malikin kendi bakiyesine eklenmez). Malik ve kiracı için eski "eşleşen kişi yoksa yedek" kuralı kalktı. **İlişkisi belirtilmemiş kişi
   (`resident`) için eski F2.05 koşulu korunur (bağımsız inceleme):** kendi hesabını (kural 3) yalnız borç sorumlusu `both` iken ya da sorumlu tarafın
   (`owner` ⇒ malik, `tenant` ⇒ kiracı) güncel ve etkin kişisi YOKKEN görür (`finance_parties.visiblePartyOfRelation`, `responsiblePersonSql`). Böylece
   yönetici "borç ve bildirimler kime gitsin: malik / kiracı" demişken ve o kişi kayıtlıyken belirtilmemiş ilişkili kişiye (ör. hane üyesi) borç
   gösterilmez; borç hatırlatma alıcısı da aynı kuraldır. 052 öncesinde borcu kimler görüyorsa yine onlar görür (görünürlük genişlemez).
   `resolvePersonParty` (hesap yönlendirmesi, sözleşme 2.1) bu koşuldan etkilenmez.
5. **Tahsilat:** seçilen hesaba yazılır. Hesap verilmezse (eski istemci) vadesi en eski AÇIK borcu olan hesap (eşitlikte ev sahibi); iki hesapta da açık
   borç yoksa tahsilat tarihindeki oturanın hesabı (kural 2, `occupant`). Yönetici ekranında aynı değer `default_payment_account` ile gelir.
6. **Ters kayıt ve düzeltme:** ters kayıt HER ZAMAN asılın hesabındadır (DB tetikleyicisi de zorlar). Düzeltmede `account_party` verilirse yeni tahsilat o
   hesaba yazılır (yanlış hesaba girilen tahsilatın düzeltilmesi); verilmezse asılın hesabı korunur.
7. **Hesap bazında hesaplananlar:** bakiye, vadesi geçen, mahsup (M1), yaşlandırma, ekstre, gecikme tazminatı, borç hatırlatma (alıcı = hesabın sahibi),
   makbuz ödeyeni (kiracı hesabı -> güncel kiracı, ev sahibi hesabı -> güncel malik) ve dışa aktarma ("Hesap" sütunu).

### Veri (052)

- `ledger_entries.account_party` (NULL | `owner` | `tenant`), `source_kind` (NULL | `manual` | `payment_notice` | `bank_line` | `opening` | `card`),
  `source_id` (BIGINT; kaynak türü olmadan dolu olamaz). CHECK'ler `NOT VALID` eklenip ayrı adımda `VALIDATE` edilir. Kısmi indeks
  `idx_ledger_entries_source (site_code, source_kind, source_id) WHERE source_id IS NOT NULL`. Yönetici tahsilatı `manual`; borç / tazminat / ters kayıt
  satırlarında kaynak NULL (izleri `run_id` / `late_fee_run_id` / `reverses_entry_id`).
- `trg_ledger_entries_account_party` (BEFORE INSERT, yalnız hedefli ters kayıt): hesap boşsa asılın (türetilmiş) hesabıyla DOLDURULUR, farklıysa P0001
  `finance reversal must keep the account of its original entry`. 052'yi bilmeyen eski sürümün dağıtım sırasında yazdığı ters kayıt da doğru hesaba düşer.
- `fee_definitions.charge_party` (NULL | `occupant` | `owner`).
- `late_fee_run_lines.account_party` + `trg_late_fee_run_lines_account` (boşsa defter satırının hesabıyla doldurur, farklıysa reddeder); birincil anahtar
  `(run_id, apartment_id)` -> `(run_id, ledger_entry_id)` ve kısmi tekil `(run_id, apartment_id, account_party) WHERE account_party IS NOT NULL`. Bu,
  "yalnız ekleyici" kuralının GEREKÇELİ tek istisnasıdır: aynı dairenin iki hesabı aynı çalıştırmada iki satır olmalıdır; kısıt yalnız gevşer, veri
  değişmez, eski kod aynen çalışır; tablo eklemeli ve küçüktür (özellik hukuk onayına kadar kapalı).
- Yeni kod HER yeni satıra hesabı açıkça yazar (borçlandırma, ek borç, tahsilat, düzeltme, ters kayıt, tazminat ve iptali).

### Var olan satırlar nasıl atanır (geri doldurma YOK)

Defter eklemelidir: 052 öncesi satırlarda `account_party` NULL KALIR ve hesap OKUMADA türetilir:
`COALESCE(account_party, CASE WHEN payer_party = 'tenant' THEN 'tenant' ELSE 'owner' END)` (`finance_parties.accountPartySql`). Yani:

| Eski satırın `payer_party` değeri | Hesabı |
|---|---|
| `tenant` (kayıt anında daire sorumlusu kiracı) | Kiracı hesabı |
| `owner` | Ev sahibi hesabı |
| `both` | Ev sahibi hesabı (makbuzdaki "both => malik" kuralıyla aynı) |

Sonuç: sorumlusu kiracı olan dairelerin eski borç ve tahsilatları kiracı hesabında, `both` ve malik dairelerinin eski kayıtları ev sahibi hesabındadır;
aynı hesaptaki eski borç ve tahsilat kendi içinde mahsup edilir (bakiye değişmez). 052'den sonra `both` dairede kiracı varken yazılan aidat kiracı
hesabına gider. Yanlış hesapta görünen eski bir tahsilat yönetici tarafından **Düzelt** ile diğer hesaba taşınabilir (ters kayıt eski hesapta kalır).

### Uçlar (yalnız EKLENEN alanlar; eski alanlar KALDIRILMADI)

- Tanım: `POST/PATCH …/definitions` gövdede `charge_party` (borçlandırılmış tanımda da `PATCH` edilebilir); `Definition.charge_party` (etkin değer).
- Ek borç `POST …/charges` ve `…/charges/preview`: `charge_party` (varsayılan `owner`; istek parmak izine yalnız `owner` değilse girer).
- Önizleme satırı: `account_party`; `preview_hash` satırın hesabını içerir (önizleme ile onay arasında hesabı değiştiren CRM değişikliği, örneğin kiracının
  taşınması, 409 `PREVIEW_STALE` verir).
- `POST …/payments`: isteğe bağlı `account_party` -> yanıt `entry.account_party`, `balance_minor` (eski: dairenin iki hesabının toplamı) ve
  `account_balance_minor` (yeni: tahsilatın yazıldığı hesabın bakiyesi). Aynı `idempotency_key` + farklı hesap 409 `IDEMPOTENCY_CONFLICT`; hesapsız
  tekrar (eski istemci) aynı kaydı döndürür.
- `POST …/entries/:id/correct`: isteğe bağlı `account_party` (kural 6) -> `account_balance_minor`.
- `GET …/balances`: satırda `debt_minor`, `credit_minor` ve `accounts: { owner: { balance_minor, overdue_minor }, tenant: {…} }`. `balance_minor` iki
  hesabın toplamı (eski alan), `overdue_minor` hesapların vadesi geçenlerinin toplamıdır (bir hesabın alacağı diğerinin vadesi geçenini düşürmez).
  `status=debtor` en az bir hesabı borçlu, `status=credit` en az bir hesabı alacaklı daireleri verir (aynı daire iki listede olabilir); `totals` hesap başına.
- `GET …/apartments/:id/account?account_party=owner|tenant`: satırlar ve bakiye yalnız o hesabın; verilmezse eski davranış (iki hesap birlikte). Yeni
  alanlar: `account_party`, `accounts: { owner|tenant: { balance_minor, overdue_minor, entry_count } }`, `show_tenant_account` (kiracısı olmuş, güncel
  kiracısı olan ya da kiracı hesabında satırı olan daire), `has_current_tenant`, `default_payment_account`.
- `GET …/summary`: borç / alacak toplamları hesap başına (pozitif / negatif hesap bakiyeleri); `debtor_count` en az bir hesabı borçlu daire sayısıdır.
- `Entry`: `account_party` (türetilmiş), `source_kind`, `source_id` (sakin uçlarında `source_id` null).
- `GET /app/my-finance`: eski alanlar (`balance_minor`, `overdue_minor`, `next_due_*`, `visible_from`, `offset_note`, `recent`) kişinin KENDİ hesabıdır;
  yeni `account_party` (kendi hesabı) ve `accounts: [{ account_party, role: own | read_only, balance_minor, overdue_minor, next_due_date, next_due_minor,
  visible_from, offset_note, recent }]` (ilki kendi hesabı). Kişisel veri dışa aktarması yalnız kendi hesabını içerir (salt okunur hesap başkasının verisidir).
- Sakin kapsamı HESAP başınadır: başlangıç kişinin bu dairedeki güncel ilişkisinin başlangıcıdır; kesintisiz önceki ilişki zinciri yalnız AYNI hesaba düşen
  ilişkiyse başı öne çeker (kiracıyken satın alan kişi eski kiracı kayıtlarını salt okunur kiracı hesabında görür; önceki malikin ev sahibi hesabı kayıtları
  yeni malike görünmez).
- Faz 4b uçları (makbuz, sakin ekstresi, yaşlandırma, dışa aktarma, gecikme tazminatı, hatırlatma): `docs/PLATFORM_FINANS_4B.md` "İki hesap" bölümü.

### Sözleşme modülü (program planı 2.1; adlar SABİT, dalga 2 çağırır)

`server/src/modules/finance_parties.js`: `ACCOUNT_PARTIES`, `resolveChargeParty(client, { siteCode, apartmentId, chargeParty, onDate })`,
`resolvePersonParty(client, { siteCode, apartmentId, userCode })`, `accountBalances(db, { siteCode, apartmentId })` ve
`postPayment(client, { siteCode, apartmentId, accountParty, amountMinor, paidOn, method, description, sourceKind, sourceId, idempotencyKey, actor })`
-> `{ entryId, receiptId, … }`. `postPayment` TEK tahsilat giriş noktasıdır (yönetici tahsilatı ve düzeltmenin yeni tahsilatı da bunu kullanır); çağıran
`withFinanceTransaction` içinde olmalıdır (sites KEY SHARE -> `finance_post` advisory), daire ve işlemi yapan `postPayment` içinde kilitlenir (apartments ->
users -> finans satırları); çağıranın kendi satırları (dekont, banka satırı) `postPayment`'tan SONRA yazılır. Kaynak izi `source_kind` / `source_id`; aynı
anahtar = aynı kayıt, farklı daire / tutar / tarih / yöntem / hesap / kasa hesabı / kaynak 409.

### Eski istemci uyumu

Eski istemci `account_party` göndermez ve yeni alanları okumaz: tahsilatı sunucunun varsayılan hesabına yazılır; "Borcum" ve panel vitrini eski alanlardan
kişinin KENDİ hesabını görür; yönetici ekstresi süzgeçsiz (iki hesap birlikte) eski görünümdedir. Toplu yükleme (Excel) daire sütunları DEĞİŞMEDİ.

### Uygulama (Flutter)

Ekstre penceresinde iki sekme [Kiracı hesabı] [Ev sahibi hesabı] (`show_tenant_account` ise; ilk sekme `default_payment_account`, bakiye ve hareketler
yalnız seçili hesabın); tahsilat / düzeltme penceresinde "Daire hesabı" seçimi (ekstrenin sekmesiyle başlar; pencere ekstre dışından açılırsa daire
seçilince sunucuya sorulur ve yanıt gelene kadar kayıt gönderilmez: seçim sonradan çıkıp işlem anahtarını değiştirmesin; tek hesaplı dairede çizilmez); tanım ve ek borç formunda "Kim öder" (Dairede oturan / Ev sahibi; varsayılansa gövdede
gönderilmez); önizleme satırında hesap; bakiye listesinde kiracı hesabında tutar varsa iki hesap ayrı rozet; yaşlandırma ve daire ekstresi raporunda hesap
süzgeci (dışa aktarma dahil); "Borcum"da "Kendi hesabınız: …" ve salt okunur kiracı hesabı bölümü (kendi ekstresi ayrı); panel vitrini borç kartı yalnız
kendi hesabı (tek dairede hesabın adı); gecikme tazminatında aynı dairenin iki satırı ayrı anahtarla (muaf tutulan daire "N daire muaf tutuldu" sayısında bir
kez sayılır, öğeleri hesap adıyla); hatırlatma önizlemesinde hesap sayısı; yardım metni.

### Doğrulama

- Sunucu birim: `finance_parties*.test.js` (şema, sözleşme modülü, borçlandırma, görünümler, raporlar, tazminat / hatırlatma) + güncellenen 4a / 4b testleri.
- Gerçek PG: `QA_ONLY=chain,live,parties` (`scripts/qa_finance_parties_section.mjs`; 052 veri varken yükseltme, şema, "kim öder", hesap başına mahsup,
  görünüm matrisi + IDOR, düzeltme / ters kayıt, tazminat iki satır, hatırlatma alıcısı, `postPayment` kaynak izi, eşzamanlı tahsilat x borçlandırma x CRM
  ile 40P01 = 0) + `finance` + `finance4b` + `finance_upgrade` + `qa_finance4b_upgrade.mjs` ("ensure" yolları artık 001..son zinciriyle karşılaştırılır).
- G12'nin BİLEREK değiştirdiği eski beklentiler (gerekçeleri betiklerde): sakin matrisi (I1, I1b: her kişi kendi boş hesabını görür), denetim
  `finance.payment.recorded` ayrıntısına `account_party` + `source_kind` kodları (G8, N4), bakiye sorgusu planında `acc` CTE'si (L5), hatırlatma alıcısı =
  hesabın sahibi (G2-G5, R6/R6b), sakin kapsamı fikstürlerinde kiracı senaryolarının satırları kiracı hesabında (S2, S3b, S11), makbuz dışa aktarmasında
  son sütun "Hesap" (E8c).

### Bilinen sınırlar

1. Hatırlatma sıklık kaydı (`finance_reminder_apartments`) daire başına kalır (temkinli: iki hesaptan birine giden hatırlatma dairenin aralığını başlatır);
   ardışık sayaç hesabın son tahsilatına göredir. Şema değişikliği yapılmadı.
2. Gecikme tazminatında `apartment_count` artık satır (HESAP) sayısıdır; muafiyet daire başınadır (iki hesabı birlikte muaf tutar).
3. Etkin kiracı tarihi `move_in_date` boşsa ilişki kaydının günüdür; geç kaydedilen kiracının taşınma tarihi girilmezse ilk ay aidatı ev sahibi hesabına
   yazılabilir (yönetici düzeltme / ters kayıtla düzeltir).
4. 052 öncesi `both` dairelerinde kiracının yaptığı eski ödemeler ev sahibi hesabındadır (anlık görüntü yalnız sorumluyu tutuyordu); bakiye değişmez.

### Bağımsız inceleme (2026-10-21; yukarıdaki metne göre ÖNCELİKLİDİR)

1. **Belirtilmemiş ilişkili kişinin görünürlüğü (orta, düzeltildi):** ilk sürümde `resident` her durumda oturanın hesabını görüyor ve hatırlatma alıyordu;
   sorumlu malik / kiracı ve o kişi kayıtlıyken bu, 052 öncesinde borcu GÖRMEYEN kişilere (ör. hane üyesi, ev arkadaşı) yeni bir ifşaydı ve yöneticinin
   "borç ve bildirimler kime gitsin" ayarıyla çelişiyordu. Kural 4'teki koşul eklendi (Borcum, sakin ekstresi / makbuzu / tazminat açıklaması ve
   hatırlatma alıcısı aynı işlevi kullanır). Gerçek PG: `finance` I1 (R1 yeniden 052 öncesi gibi görmez), `parties` P5 (RA2 görmez, RA6 yedekle görür, P5d 404),
   P8 (sorumlu malik dairede belirtilmemiş kişiye ileti gitmez).
2. **Düzeltme tekrarı (düşük, düzeltildi):** `POST …/entries/:id/correct` aynı anahtarla tekrarlanınca yanıt `account_balance_minor` taşımıyordu; artık
   ilk yanıtla aynı alanlar. Gerçek PG `parties` P4k (varsayılan tahsilat hesabı diğer hesapken hesapsız düzeltme asılın hesabını korur), P4l (toplamı eksi
   ama bir hesabı borçlu daire borçlu listesinde).
3. **052 adım sırası (düşük, düzeltildi):** `trg_late_fee_run_lines_account` işlevi `ledger_entries.account_party`'yi okur; tetikleyici artık ledger
   sütunlarından SONRA (en son adım) kurulur. Açılış iki adım arasında kalsa ya da ledger adımı düşüp eski sürüme dönülse tazminat satırı yazımı bozulmaz.
4. **İstemci (düşük, düzeltildi):** gecikme tazminatı önizlemesinde muaf daire sayısı hesap öğesi sayısı değil daire sayısıdır; tahsilat penceresi daire
   hesapları yüklenirken kayıt göndermez (çift tahsilat koruması).
5. **Açık / kabul edilen:** eski yönetici uygulaması hesap göndermez; tahsilat vadesi en eski açık borcun hesabına düşer (ör. `both` dairede 052 öncesi ev
   sahibi hesabındaki eski borç kiracının yeni ödemesini alabilir) ve eski uygulama düzeltmede hesap değiştiremez: G12 canlıya alınmadan önce yeni sürüm
   yayılmalıdır. Hatırlatma sıklık kaydı daire başınadır (kabul, kural 1 "Bilinen sınırlar").
