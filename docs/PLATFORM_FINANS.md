# Platform — Aidat ve Finans (Faz 4a) sözleşmesi

Bu belge sunucu (`server/`) ve uygulama (`lib/`) için BAĞLAYICIDIR. Öncül belgeler: `docs/PLATFORM_MODUL_SISTEMI.md` (modül kataloğu, modül açma/talep akışı, `MODULE_DISABLED`), `docs/PLATFORM_KISILER.md` (daire alanları: `land_share_*`, `category`, `responsible_party`; m² alanları (`gross_area_m2`, `net_area_m2`) 2026-10-25'te KALDIRILDI; kişi/ilişki; kilit sırası kuralları), `docs/PLATFORM_DUYURU.md` (hız sınırı, e-posta, strict testler, gerçek-PG betiği kalıpları). Kalıplar Faz 2/3'teki gibi aynen örnek alınır.

## Kapsam

**Faz 4a (bu belge):** aidat tanımı (dağıtım yöntemi YÖNETİMİN seçimi: eşit [varsayılan], sabit, kategori, arsa payı, kişi sayısı; m² yok), aylık borçlandırma (önizleme + onay), tek seferlik ek borç, daire hesabı (ekstre), sakin "Borcum", elle tahsilat kaydı, düzeltme (silme YOK, ters kayıt), ay kapatma, yönetim kurulu salt okunur, modül açma/kapama.
**Faz 4b (sonra):** makbuz PDF (F4.07), gecikme tazminatı (F4.08), gider kaydı + belge fotoğrafı (F4.09; dosya yükleme bağımlılığı), kasa/banka hesapları ve aktarım (F4.10), raporlar + Excel/PDF (F4.11), borç hatırlatma (F4.14). **Online kart ödemesi ve banka bağlantısı YOK ("Yakında…", F8).**

## İlkeler (para bütünlüğü)

1. **Para = tamsayı kuruş** (`*_minor`, `BIGINT`); JSON'da tamsayı. HİÇBİR yerde kayan nokta ile para hesabı yapılmaz (sunucu ve uygulama). Para birimi `TRY` (sütun `currency`, bugün hep TRY). Uygulama girişi "1.234,56" biçimini kesin olarak kuruşa çevirir (yuvarlama yok, ≥3 ondalık reddedilir).
2. **Defter eklemelidir (append-only):** `ledger_entries` satırı oluşturulduktan sonra DEĞİŞTİRİLEMEZ ve SİLİNEMEZ (DB tetikleyicisi `BEFORE UPDATE OR DELETE` hata verir; tek istisna: üst `sites` satırı artık yoksa CASCADE silmeye izin). Yanlış kayıt **ters kayıtla** düzeltilir.
3. **Bakiye = satırların işaretli toplamı:** `amount_minor > 0` borç (daire borçlu), `< 0` tahsilat/alacak. `balance_minor = SUM(amount_minor)`; pozitif = borç, negatif = alacak.
4. **Atomiklik ve idempotans:** borçlandırma, tahsilat ve düzeltme tek işlemde; çift tıklama/yeniden deneme çift kayıt YARATMAZ (kısmi tekil indeksler + `idempotency_key`).
5. **Dönem (muhasebe ayı):** `period DATE` = ayın ilk günü (Europe/Istanbul). Kapatılmış döneme kayıt eklenemez; düzeltme AÇIK dönemde ters kayıtla yapılır.
6. **Yetki:** yazma = yönetici/süper (`hasSiteManagementAccess`); okuma = yönetici/süper + `BOARD_MEMBER` (salt okunur; tüm daire bakiyelerini görür); `STAFF` 403; sakin yalnız KENDİ dairesini (`/app/my-finance`). Başka site 403/404. `finance` 2026-10-26'dan beri TEMEL modüldür (AGENTS.md Kural 25): her sitede açık, kapatılamaz ve talep edilmez; uçlardaki modül denetimi (`MODULE_DISABLED`) temel modülde hiç tetiklenmez.
7. **Eklemeli şema:** `migrations/034_finance.sql` ile `ensureDbSchema` (server/src/db.js) AYNI idempotent DDL (prod'da yalnız `ensureDbSchema` çalışır, DDL hatası = sunucu açılmaz). Mevcut tablo/akış değişmez; tek istisna: `catalog.js` `finance` → `available` (Faz 4a'da varsayılan KAPALI ve talep edilirdi; 2026-10-26'dan beri `core`, hep açık, bkz. Kural 25 ve `migrations/079_finance_core_module.sql`) ve daire azaltmada mali kaydı olan dairenin silinmesinin engellenmesi (aşağıda).
8. Kilit sırası Faz 2/3 kuralı: apartments (id sırasıyla) → users → site_people/… → finans tabloları. Borçlandırma `pg_advisory_xact_lock(finance_post:<site>)` alır; yeni kilit çatışması yaratma. 40P01'de tek yeniden deneme.

## Veritabanı (migration `034_finance.sql`)

- `fee_definitions(id BIGSERIAL PK, site_code BIGINT NOT NULL REFERENCES sites ON DELETE CASCADE, name TEXT NOT NULL (1–80), kind TEXT NOT NULL CHECK (recurring|one_time), distribution TEXT NOT NULL CHECK (fixed|equal|category|land_share|area), area_basis TEXT NULL CHECK (gross|net) (yalnız distribution='area'; 2026-10-25'ten beri `area` ve `area_basis` yalnız ESKİ satırlar için CHECK'te kalır, yeni giriş kabul edilmez, bkz. «Dağıtım ve yuvarlama»), amount_minor BIGINT NULL CHECK (amount_minor > 0) (fixed: daire başı tutar; equal/land_share/area: TOPLAM tutar; category: NULL), category_amounts JSONB NULL ({ "<kategori>": <daire başı kuruş> }, yalnız category), due_day SMALLINT NULL CHECK (1..28) (aylık vade günü; one_time için vade tarihi ayrı), start_period DATE NOT NULL, end_period DATE NULL, target_type TEXT NOT NULL DEFAULT 'site' CHECK (site|blocks|apartments), target_block_ids BIGINT[] NOT NULL DEFAULT '{}', target_apartment_ids BIGINT[] NOT NULL DEFAULT '{}', is_active BOOLEAN NOT NULL DEFAULT TRUE, created_by INTEGER NULL REFERENCES users ON DELETE SET NULL, created_at, updated_at)`. Tutarlılık CHECK'leri dağıtım yöntemine göre (ör. `category` ⇒ `category_amounts` dolu ve `amount_minor` NULL; `fixed|equal|land_share|area` ⇒ `amount_minor` dolu; `kind='recurring'` ⇒ `due_day` dolu).
- `fee_runs(id BIGSERIAL PK, site_code, definition_id BIGINT NOT NULL REFERENCES fee_definitions, period DATE NOT NULL, total_minor BIGINT NOT NULL, apartment_count INTEGER NOT NULL, posted_by INTEGER NULL REFERENCES users ON DELETE SET NULL, posted_at TIMESTAMPTZ NOT NULL DEFAULT NOW())`; `UNIQUE (definition_id, period)` ("aynı ay ikinci kez borçlandırılamaz"). Tek seferlik ek borç da bir `fee_runs` satırıdır (period = vade/kayıt ayı; `kind='one_time'` tanımı yalnız bir kez çalışır).
- `ledger_entries(id BIGSERIAL PK, site_code BIGINT NOT NULL REFERENCES sites ON DELETE CASCADE, apartment_id BIGINT NOT NULL REFERENCES apartments ON DELETE RESTRICT, kind TEXT NOT NULL CHECK (charge|payment|reversal), amount_minor BIGINT NOT NULL CHECK (amount_minor <> 0) (charge > 0, payment < 0 CHECK'le; reversal karşı işaret), currency TEXT NOT NULL DEFAULT 'TRY', period DATE NOT NULL, entry_date DATE NOT NULL (tahsilat/borç tarihi), due_date DATE NULL, definition_id BIGINT NULL REFERENCES fee_definitions, run_id BIGINT NULL REFERENCES fee_runs, payer_party TEXT NOT NULL CHECK (owner|tenant|both) (kayıt anında dairenin `responsible_party`'si), method TEXT NULL CHECK (cash|transfer|cheque) (yalnız payment), description TEXT NULL (≤200), reverses_entry_id BIGINT NULL REFERENCES ledger_entries, reversal_reason TEXT NULL (≤200), idempotency_key TEXT NULL (≤64), created_by INTEGER NULL REFERENCES users ON DELETE SET NULL, created_at TIMESTAMPTZ NOT NULL DEFAULT NOW())`. Kısmi tekil indeksler: `(reverses_entry_id) WHERE reverses_entry_id IS NOT NULL` (bir kaydın tek ters kaydı olur); `(site_code, idempotency_key) WHERE idempotency_key IS NOT NULL`. İndeksler: `(site_code, apartment_id, entry_date, id)`, `(site_code, period)`, `(run_id)`. `BEFORE UPDATE OR DELETE` tetikleyicisi (`CREATE OR REPLACE FUNCTION` + pg_trigger kontrollü): hata `finance ledger is append-only`; DELETE yalnız `NOT EXISTS (SELECT 1 FROM sites WHERE site_code = OLD.site_code)` iken serbest.
- `finance_period_closures(site_code BIGINT NOT NULL REFERENCES sites ON DELETE CASCADE, period DATE NOT NULL, closed_by INTEGER NULL REFERENCES users ON DELETE SET NULL, closed_at TIMESTAMPTZ NOT NULL DEFAULT NOW(), PRIMARY KEY (site_code, period))`. Dönemler SIRAYLA kapanır: bir ayı kapatmak için önceki ay kapalı olmalı (siteye ilk kapatmada serbest); yalnız EN SON kapatılan ay yeniden açılabilir ve yalnız süper kullanıcı açar.
- Daire azaltma: `syncSiteStructureCounts` (site_service.js) silinecek dairelerden birinin `ledger_entries` kaydı varsa işlemi **geri alır ve 409 `APARTMENT_HAS_FINANCE`** ("Mali kaydı olan daire silinemez") döner; mevcut daire azaltma davranışı mali kaydı olmayan dairelerde AYNEN kalır; site silme (CASCADE) çalışır.

## Dağıtım ve yuvarlama

- **Dağıtım tabanı (K5, P1-5; 2026-10-29):** tahakkuk (aidat tanımı, ek borç / gider payı) ve ısı payının alan payı kısmı AYNI tabanlardan beslenir ve tabanı YÖNETİM açıkça seçer; **varsayılan EŞİT**,
  **kod formül seçmez** (veri tanımlı diye kendiliğinden arsa payına ya da kişi sayısına geçmez). Seçilebilen tabanlar: `equal` (eşit; varsayılan), `fixed` (daire başı sabit), `category` (kategori başına tutar),
  `land_share` (arsa payı), `person_count` (kişi sayısı). **m² tabanı YOKTUR** (daire alanı sistemde tutulmuyor, migration 078; alan verisi olmayan taban seçenek olarak sunulmaz).
  `person_count`: kişi sayısı = `apartment_residencies.is_current` kayıtları (Kişiler ekranı; hesapsız çocuk / yaşlı dahil, taşınmış kişi sayılmaz). Kişi kaydı olmayan (0) daire EŞİT paya DÜŞÜRÜLMEZ: «eksik veri»dir
  (`missing_data`, `reason_code: person_count_missing`; arsa payı için `land_share_missing`): `commit` 409 `PREVIEW_INCOMPLETE` verir, yönetici veriyi tamamlar ya da `skip_missing` ile atlar (payı kalanlara dağılır; `redistributed: true`).
  Önizleme satırı `basis_value` taşır (arsa payı kesri ya da kişi sayısı; yalnız gösterim, `preview_hash`'e girmez). DB: `fee_definitions.chk_fee_definitions_distribution` migration 091 ile `person_count` içerir
  (`src/modules/finance_distribution_schema.js`); API'de `distribution` zorunlu kalır (sunucu varsayılan taban UYDURMAZ), varsayılan seçim arayüzde «Eşit bölüş»tür.
  **Isı payı** (`POST meter-billings/preview|post`, yalnız `method: 'heat'`): isteğe bağlı `area_basis` = `equal` (varsayılan) | `land_share` | `person_count`; eskiden «hepsinde arsa payı varsa arsa payı, yoksa eşit» kod kuralı KALDIRILDI.
  Seçilen tabanın verisi eksik daire `missing` listesine `land_share_missing` / `person_count_missing` ile girer (okuması eksik daire gibi); onaysız yazma 409 `AREA_BASIS_INCOMPLETE`, `skip_missing` ile atlanır.
  Seçilen taban `params.area_basis`, yanıt `area_basis` ve audit'te yazılır; alan payı %0 ise (ölçüm %100) taban önemsizdir. Bkz. `docs/PLATFORM_SAYAC.md`.
- Dahil edilen daireler: hedefteki (`target_*`) **aktif** daireler. Tutar payları **en büyük kalan** yöntemiyle kuruşa bölünür (toplam payların toplamına BİREBİR eşit olmalı; eşitlikte `apartment_id` küçük olan önce): `equal` (ağırlık 1), `land_share` (ağırlık = `numerator/denominator`, tam sayı aritmetiği: ortak payda ile), `person_count` (K5; ağırlık = dairedeki GÜNCEL kişi sayısı, bkz. aşağıdaki «Dağıtım tabanı»), `area` (KALDIRILDI 2026-10-25: eski ağırlık = seçili m² × 100; artık hesaplanmaz, aşağıdaki nota bakın). `fixed`: her daireye `amount_minor`. `category`: dairenin `category`'sine karşılık gelen daire başı tutar.
- Eksik veri (arsa payı/kategori tanımsız ya da kategori haritada yok): önizlemede `missing_data` listesi; `commit` bu durumda 409 `PREVIEW_INCOMPLETE` döner (varsayılan), yönetici `skip_missing: true` ile o daireleri hariç tutarak devam edebilir (hariç tutulanlar audit `details`'ında sayı olarak yazılır).
- **m² (`area`) dağıtımı KALDIRILDI (2026-10-25; `finance_common.js`, `finance_service.js`).** Geçerli dağıtımlar `fixed`, `equal`, `category`, `land_share`. Yeni tanım, ek borç ya da dağıtım değişikliğinde `distribution: 'area'` 400 `AREA_DISTRIBUTION_REMOVED` ile reddedilir; `area_basis` gönderilirse 400 `INVALID_BODY` («Alan esası (m²) kaldırıldı; gönderilmemelidir.»). Mevcut (eski) `area` tanımında önizleme ve borçlandırma 409 `AREA_DISTRIBUTION_REMOVED` verir (daire alanı artık tutulmadığından her daire eksik çıkardı); çıkış: tanımı pasifleştirmek (borçlandırılmadıysa dağıtım yöntemini değiştirmek) ve eşit, arsa payı, sabit tutar ya da kategori dağıtımlı yeni tanım açmak. Eski `area` tanımlarının adı / aktifliği / vade günü güncellenebilir.
- **Kim öder:** her daire için `payer_party = apartments.responsible_party` (kayıt anındaki değer kopyalanır, sonradan değişse de eski kayıt değişmez). Borç tek daire hesabına yazılır; kimin GÖRECEĞİ `responsible_party`'ye uyar (aşağıda).
  > **İP-1A (2026-10-21) ile değişti:** her dairenin iki hesabı vardır (ev sahibi / kiracı); borç tanımın "kim öder" (`charge_party`) değeri ve borç tarihindeki kiracı durumuna göre bu hesaplardan BİRİNE yazılır. `payer_party` anlık görüntü olarak yazılmaya devam eder. Bkz. **İki hesap (2026-10-21)**.
- Vade: aylık tanımda `due_date = period + (due_day-1) gün`; ek borçta istekteki `due_date` (yoksa kayıt günü).

## Yönetici uçları (`/manager/sites/:siteCode/finance/…`)

Hata gövdesi `{ error, code }` (Türkçe). Tutarlar kuruş tamsayı. Yazmalar 120/saat/kullanıcı, okuma 1200/saat.

**Tanımlar**
- `GET …/definitions?kind=&active=` → `{ items: [Definition] }`; `Definition`: tüm alanlar + `last_posted_period`.
- `POST …/definitions` gövde `{ name, kind, distribution, amount, category_amounts?, due_day?, start_period, end_period?, target }` (`amount`/`category_amounts` TL değil KURUŞ: `amount_minor`, `category_amounts`) → 201 `Definition`. `PATCH …/definitions/:id` (yalnız henüz hiç borçlandırılmamış tanımın tutar/dağıtımı değişir; borçlandırılmışta yalnız `name`, `end_period`, `is_active`, `due_day` — geçmiş kayıtlar zaten değişmez). Silme YOK (`is_active:false`).
- `POST …/definitions/:id/preview` gövde `{ period }` (recurring) ya da `{ due_date? }` (one_time) → `{ period, definition_id, total_minor, apartment_count, lines: [{ apartment_id, label, block_name, payer_party, amount_minor }], missing_data: [{ apartment_id, label, reason }], already_posted: bool, closed: bool }` — YAZMAZ.
- `POST …/definitions/:id/post` gövde `{ period?, due_date?, expected_total_minor, expected_apartment_count, skip_missing?, idempotency_key? }` → önizlemeyle aynı hesabı yeniden yapar; toplam/daire sayısı beklenenle UYUŞMAZSA 409 `PREVIEW_STALE` (ve hiçbir şey yazılmaz); aynı (tanım, dönem) için 409 `PERIOD_ALREADY_POSTED`; dönem kapalıysa 409 `PERIOD_CLOSED`; tanım pasif/süresi dışıysa 409 `DEFINITION_INACTIVE` → 201 `{ run, entries_count }`.
- `POST …/charges` (**ek borç**) gövde `{ name, amount_minor, distribution, category_amounts?, target, due_date?, expected_total_minor, expected_apartment_count, skip_missing?, idempotency_key? }` → tek işlemde tek seferlik tanım + önizleme doğrulaması + borçlandırma (önizleme için `POST …/charges/preview` aynı gövde) → 201.

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
4. **Temel modül (2026-10-26):** Finans/Borcum menüsü her sitede görünür; Modüller ekranında "Aidat ve Finans" kartı temel modül olarak hep açıktır, talep düğmesi yoktur.
   **Kart Ödemesi Finans'ın içindedir (2026-10-28):** eski ayrı `card_payments` modülü kaldırıldı; Finans ekranındaki **Kart Ödemesi** düğmesi (yönetici düzenler, kurul salt okur) iyzico / PayTR "Yakında…" listesini ve komisyon notunu gösterir. Online tahsilat hâlâ YOKTUR (tahsilat yapılmaz; yalnız komisyon bilgi notu saklanır). Uçlar (`GET /manager/sites/:siteCode/card-payments`, `PUT .../card-payments/:provider`) ve `payment_provider_settings` tablosu aynı kalır; kapısı `finance` temel modülüdür (bkz. `docs/PLATFORM_MODUL_SISTEMI.md`, migration 083, `docs/PLATFORM_ODEME_KAMERA.md`).
5. **Hata kodları** Türkçe eşlenir: `MODULE_DISABLED`, `PREVIEW_STALE`, `PREVIEW_INCOMPLETE`, `PERIOD_ALREADY_POSTED`, `PERIOD_CLOSED`, `PERIOD_NOT_CLOSABLE`, `DEFINITION_INACTIVE`, `ENTRY_ALREADY_REVERSED`, `ENTRY_NOT_REVERSIBLE`, `APARTMENT_HAS_FINANCE`, `INVALID_BODY`.
6. Süper denetim ekranı: yeni eylem etiketleri/süzgeçleri.

## Doğrulama (kabul)

- Sunucu: `npm test` + `npm run lint` yeşil; strict sahte-DB testleri; **gerçek PG** (`qa_platform_pg.mjs`, yeni `finance` bölümü): migrate zinciri = `ensureDbSchema` (CHECK/indeks/tetikleyici dahil, ikinci çalıştırma no-op); dağıtım matematiği (eşit/sabit/kategori/arsa payı; m² dağıtımı kaldırıldı; **toplam payların toplamı = tutar**, rastgele girdilerle özellik testi; yuvarlama deterministik; eksik veri); defter değişmezliği (UPDATE/DELETE tetikleyici hatası, site silinince CASCADE geçer); bakiye = toplam; borçlandırma önizleme≠yazma, `PREVIEW_STALE`, aynı dönem ikinci kez 409, eşzamanlı çift `post` tek kayıt, `idempotency_key` tekrarı; tahsilat (fazla ödeme alacak, gelecek tarih 400, kapalı dönem 409); ters kayıt (çift ters 409, ters kaydın tersi 409, bakiye düzelir, düzeltme tek işlem ve yarım kalmaz); ay kapatma sırası/kuralları; yetki matrisi (yönetici yazar, kurul yalnız okur, STAFF/sakin 403, başka site 403/404, IDOR); modül kapalı 403; sakin ucu `responsible_party` matrisi + `family_member` görmez + yedek kural + başka daire sızmaz; daire azaltma `APARTMENT_HAS_FINANCE`; 3000 daireli sitede borçlandırma süresi makul (<3 sn) ve `EXPLAIN` seq scan yok; kilit turları (borçlandırma × tahsilat × ters kayıt × daire azaltma × kullanıcı silme; 40P01 = 0).
- Uygulama: `flutter analyze` temiz, `flutter test` yeşil; para yardımcısı özellik testleri (tam kuruş, hiç kayan nokta), ekran/diyalog testleri, dar ekran + büyük yazı + ekran okuyucu.
- Süreç: Faz 2/3'teki gibi en az iki bağımsız inceleme turu (yetki/gizlilik/para bütünlüğü; veri/yarış/şema), düzeltmeler, canlıya alma (yedek + şema provası + doğrulama + modül varsayılan KAPALI), kontrol listesi güncellemesi (claude.ai + `SAHA_KONTROL_LISTESI.md`).

## Faz 4a inceleme kararları (bağımsız incelemeler sonrası; yukarıdaki metne göre ÖNCELİKLİDİR)

1. **Kapalı dönem = `period <= MAX(kapalı dönem)`.** Bir ay kapatılınca ondan ÖNCEKİ tüm aylar da kapalı sayılır ve hiçbir yazma yolunda (aylık borçlandırma, ek borç, tahsilat `entry_date`, düzeltmenin yeni tahsilatı) yazılamaz → 409 `PERIOD_CLOSED`. Kapatma isteğe bağlıdır ve sırasızdır (N4): ilk kapatmada herhangi bir ay (≤ bu ay, en fazla 5 yıl öncesi), sonra `closed_through`tan sonraki herhangi bir ay (≤ bu ay); seçilen aya kadar açık aylar birlikte kapanır (her ay için ayrı satır, audit `finance.period.closed {period, from, months}`). `GET …/periods` → `{ closed_through, closable: ['YYYY-MM',…] (en yeni önce, ≤ 12; kapanış yoksa bu ay + önceki 11 ay; varsa closed_through+1’den bu aya kadar bütün aylar), items, open_period }`. Yeniden açma yalnız süper kullanıcı ve yalnız EN SON kapatma satırı; **ilk kapatma satırı açılınca ona bağlı örtük kapalı geçmiş de açılır** (kasıtlı; arayüz uyarmalı). Tarih alt sınırı: `entry_date`/`due_date`/`period` bugünden 5 yıl öncesinden eski olamaz (400 `INVALID_BODY`).
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

### İkinci bağımsız inceleme (2026-10-21; Dalga 1 tümleşik dalında, İP-1B / 1C / 1D ile birlikte)

1. **Mutasyonla bulunan test boşlukları (kod doğruydu, kanıt yoktu):** 40 mutasyonun 24'ü birim testlerinden sağ çıktı; 24'ü de gerçek PG'ye karşı
   denendi, 17'si orada yakalandı, 7'si orada da sağ çıktı. Kapatılanlar (her yeni test ilgili mutasyonla düştü): kişisel veri dışa aktarması YALNIZ kendi hesabı (Borcum +
   makbuzlar; `parties` P5g, birim `finance_parties_views`), `postPayment` aynı anahtar + yalnız kaynak TÜRÜ farklı 409 (P10, birim), hesap süzgeçli
   ekstrenin açılış bakiyesi (P6f, birim), ekstre penceresinin kiracı sekmesi kuralı `show_tenant_account` (P4m, birim), ardışık hatırlatma sayacı
   hesabın son tahsilatına göre (P8d, birim SQL yapısı). Altın veri setine İL2 eklendi: kurallar tablosu üst sınırı iki hesaplı planda hesabın
   tazminatına uygulanır.
2. **Hatırlatma önizlemesi (düşük, düzeltildi):** hariç tutma ve elden takip sayıları hesap başına iken ekranda "daire" yazıyor, aynı dairenin iki hesabı
   elden takip listesinde aynı etiketle iki kez görünüyordu. Sunucu `hand_follow_up_accounts` ekler; istemci "daire hesabı" ve "A Blok - 5 (Kiracı hesabı)"
   yazar (`docs/PLATFORM_FINANS_4B.md` "İki hesap" Ö6).
3. **Geri alma provası (gerçek PG, kendi örnek):** eski sürüm (5660a7e) 051 şemasıyla kuruldu, eski satırlar ve eski tahsilat yazıldı; yeni sürüm 052 + 053'ü
   uyguladı ve iki hesaplı satırlar yazdı; sonra ESKİ kod `ensureDbSchema`'yı iki kez hatasız çalıştırdı (052 / 053 sütun, kısıt, indeks, tetikleyici ve
   işlevleri değişmedi), eski kodla tahsilat, ters kayıt ve düzeltme yapıldı ve okundu; yeni kodun yeniden açılışı no-op oldu, hesap bakiyeleri defterin hesap
   toplamlarına birebir, her ters kayıt asılın hesabında. **Geri alma süresince bilinen sonuç:** eski kodun yazdığı satırlar hesapsızdır (NULL) ve
   `payer_party`'den türetilir: `both` dairede eski kodun tahsilatı, düzeltmenin yeni tahsilatı ve aidatı ev sahibi hesabına düşer (ters kayıtlar tetikleyiciyle
   asılın hesabındadır). Yeniden yayından sonra yönetici bu satırları "Düzelt" ile doğru hesaba taşır.
4. **Açık / kabul edilen:** sıklık kaydı daire başına olduğu için ardışık sayaç, dairenin DİĞER hesabı için gönderilmiş hatırlatmaları da sayar (o hesabın son
   tahsilatından sonrakileri): bir hesap ilk kez gecikmeye düştüğünde, diğer hesap için sınır kadar hatırlatma gönderilmişse doğrudan elden takibe düşer (e-posta
   gitmez; temkinli taraf). Hesap başına hatırlatma geçmişi şema değişikliği ister.

## Altın veri seti (F5, 2026-10-21)

Karar F5: gerçekçi bir site için ELLE hesaplanmış tablo; dağıtım, yuvarlama, gecikme tazminatı ve mahsup kodu bu tabloyla kuruşu kuruşuna
karşılaştırılır, tutmazsa test düşer. Beklenen değerlerin hiçbiri kod çalıştırılarak üretilmedi; her birinin hesap adımları fikstürde yazılıdır.
Cenk'in gerçek tablosu gelince ayrı bir set olarak eklenecek (Dalga B kurallarını kapsayan ikinci set: aşağıda «Altın veri seti 2»).

- Fikstür (site, senaryolar, adım adım hesap): `server/test/fixtures/finance_golden_site.js`
- Test: `server/test/finance_golden_dataset.test.js` (gerçek `buildDistributionPlan`, `lateFeeForApartment` + gün gün kaba kuvvet tanımı, `m1Remainders`;
  iki hesap için gerçek `accountForCharge`, `computeLateFeePlan` (katı sahte DB) ve hesap başına `m1Remainders`).
- Sapma çıkarsa önce fikstürdeki elle hesap iki kez yeniden yapılır; hesap doğruysa hata raporlanır, hesap kodu fikstüre uydurulmaz.
  İlk koşu (2026-10-21): 21 kontrolün hepsi ilk seferde tuttu (sapma yok). Dalga 1 tümleştirmesi (İP-1A ile): iki hesaplı 7 kontrol eklendi, ilk
  seferde tuttu; dört bozma denemesi (tazminatta hesapları karıştırma, kiracı durumunu yok sayma, dağıtım satırından hesabı düşürme, satırın hesabını
  yok sayma) testlerce yakalandı.

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
| D2 brüt m² (KALDIRILDI 2026-10-25: m² dağıtımı artık reddedilir; tarihçe) | 1.000.000 (10.000,00 TL) | 240.000 | 11 | A-1 35.625; A-2 26.771; A-3..A-7 50.000; A-8..A-12 49.271; B-1..B-4 26.000; B-5 42.167; B-6..B-8 42.166; B-9..B-12 42.146 |
| D3 net m² (KALDIRILDI 2026-10-25; tarihçe) | 500.003 (5.000,03 TL) | 200.000 | 8 | A-1 17.187; A-2 13.625; A-3..A-7 25.000; A-8..A-12 24.688; B-1..B-4 13.000; B-5..B-8 21.125; B-9..B-11 21.063; B-12 21.062 |
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

**İki hesap (İP-1A, karar G12):** dairelerin "kim öder" durumu fikstürde elle seçildi (`ACCOUNT_PROFILE`: A-1, A-2 ve B-1..B-4 sorumlu kiracı +
kiracı var; A-3..A-7 sorumlu malik, kiracı yok; A-8..A-10 sorumlu malik + kiracı var; A-11, A-12 "malik ve kiracı" + kiracı var; B-5..B-8 sorumlu
kiracı, kiracı yok; B-9..B-12 "malik ve kiracı", kiracı yok). Borcun hesabı `accountForCharge` kuralıyla; mahsup ve tazminat hesap bazında. Tek
hesaplı senaryolar (D1-D6, L1-L4, M1-M3) iki hesaplı kodla da aynı sonucu verir (L1-L4 hesap bazlı planda ev sahibi ve kiracı hesabında ayrı ayrı
sınanır).

| Senaryo | Durum | Sonuç (kuruş) |
| --- | --- | --- |
| İD1 | D1 aidatı, "kim öder" = dairede oturan | tutarlar D1 ile aynı; kiracı hesabı A-1, A-2, A-11, A-12, B-1..B-4: 8 x 354.167 = 2.833.336; ev sahibi hesabı A-3..A-10 8 x 354.167 + B-5..B-12 8 x 354.166 = 5.666.664 |
| İD2 | D4 çatı yalıtımı, "kim öder" = ev sahibi | 24 dairenin hepsi ev sahibi hesabı (kiracılı dairede de); toplam 3.600.019 |
| İL1 (B-2) | ev sahibi hesabı: çatı payı 81.000 (vade 20.09) ödenmedi; kiracı hesabı: Ekim aidatı 75.000 (vade 05.10) 03.10'da ödendi; Ekim 2026, ek gün 0 | ev sahibi hesabı S = 31 x 81.000 = 2.511.000: daily_30 4.185, daily_actual 4.050; kiracı hesabında tazminat satırı yok. Tek hesapta karışsaydı S = 2 x 81.000 + 3 x 6.000 + 26 x 81.000 = 2.286.000 ve daily_30 3.810 olurdu (zamanında ödenen aidat gecikmiş sayılırdı) |
| İM1 (B-3) | ev sahibi hesabı: çatı payı 81.000 (vade 20.09); kiracı hesabı: Eylül ve Ekim aidatı 75.000'er; kiracı 100.000 ödedi | kiracı hesabı kalanları 0; 50.000; ev sahibi hesabı 81.000. Tek hesapta karışsaydı 0; 56.000 (çatı); 75.000: kiracının 25.000'i ev sahibinin borcuna giderdi |
| İL2 (B-2; ikinci inceleme) | İL1'in satırları; kurallar tablosunda aylık üst sınır 300 bp, sitenin saklı oranı 500 bp (etkin oran = min = 300) | ev sahibi hesabı S = 2.511.000: daily_30 (1.506.600.000 + 300.000) / 600.000 = 2.511, daily_actual (1.506.600.000 + 310.000) / 620.000 = 2.430 (= 81.000 x %3); kiracı hesabında satır yok |

**K5 / K16 ek senaryoları (2026-10-29; elle hesaplandı, adımlar fikstürde):**

| Senaryo | Girdi | Beklenen |
| --- | --- | --- |
| D7 (kişi sayısı) | ortak gider 10.000,00 TL; kişi sayıları `PERSON_COUNTS` (59 kişi, 22 daire); A-1 / A-2 dükkân kişi kaydı yok | A-1 ve A-2 EKSİK VERİ (eşit paya düşmez); kalan 22 daire tutarın tamamını paylaşır: 1 kişi 16.949, 2 kişi 33.898, 3 kişi 50.847 (A-4, A-8, B-5: 50.848), 4 kişi 67.797, 5 kişi 84.746; toplam 1.000.000 |
| D8-D11 (eşit, kuruş artıkları) | 7 kuruş / 24 daire; yalnız A Blok 10.000,00 TL; 85.000,01 TL / 24; 1 kuruş / 24 | kalanlar eşit olduğundan artan kuruşlar kimliği KÜÇÜK dairelere gider: A-1..A-7 birer kuruş (17 daire 0); A-1..A-4 = 83.334; ilk 17 daire 354.167 (B-6..B-12 354.166); yalnız A-1 1 kuruş. Hepsinde toplam tutara birebir |
| OC1 (A-6) | devir alacağı 500,00 TL + Ekim / Kasım aidatı 354.167'şer (vade 05.10 / 05.11) | Ekim 304.167, Kasım 354.167 açık; alacak 0; bakiye 658.334 |
| OC2 (B-12) | devir alacağı 8.000,00 TL + iki aidat 354.166 | ikisi de kapanır; artan 91.668 ALACAK kalır; bakiye -91.668 |
| OC3 (A-7) | devir alacağı 1.250,00 TL (= bir aidat) | o aidat kapanır, sonrakine dokunmaz |
| OC4 (B-3) | ev sahibi hesabı alacağı 500,00 TL; kiracı hesabı Ekim aidatı 750,00 TL | kiracı borcu 75.000 AÇIK kalır (mahsup hesap bazında); tek hesapta karışsaydı 25.000 |
| OC5 (A-6) | Ekim aidatı 1.250,00 TL (vade 05.10) + 01.10 devir alacağı 500,00 TL; Ekim 2026, daily_30 | S = 26 x 75.000 = 1.950.000, tazminat 3.250 (alacaksız 5.417); 20.10'da alacak iptal edilirse S = 2.550.000, tazminat 4.250 |
| OC6 (site) | D1 eşit aidat + A-6 500,00 ve B-12 8.000,00 TL devir alacağı | A-6 304.167 borçlu, B-12 -445.834 alacaklı; borçlu toplamı 8.095.834, alacak toplamı 445.834, net 7.650.000 |

## Altın veri seti 2 (Dalga B, P2-5; 2026-10-29)

Birinci set çekirdeği (dağıtım, yuvarlama, tazminat, mahsup) kuruşu kuruşuna sınar; ikinci set **Dalga B kurallarını küçük bir sitede uçtan uca** sınar ve örnek site olarak kurulabilir. Cenk'in gerçek tablosu gelince üçüncü set olarak eklenecek.
Beklenen değerlerin hiçbiri kod çalıştırılarak üretilmedi; adım adım elle hesap fikstürdedir (sapma çıkarsa önce elle hesap iki kez yeniden yapılır). İlk koşuda gerçek PostgreSQL dahil bütün kontroller tuttu; sabitlenen davranışlar aşağıda.

- Fikstür (senaryo + beklenen + elle hesap): `server/test/fixtures/finance_golden_site_2.js`. Çalıştırıcı (gerçek servisler, HTTP yok, sabit saat 2026-10-20): `server/scripts/lib/golden2_runner.mjs`.
- Saf test (veritabanı yok, 23 kontrol): `server/test/finance_golden_dataset_2.test.js` (gerçek `buildDistributionPlan`, `accountForCharge`, `m1Remainders`, `planLiabilityTransfer` / `transferWrites` / `planTransferReversal`, `allocateFunds`, `lateFeeForApartment` + gün gün kaba kuvvet).
- Gerçek PostgreSQL: `server/scripts/qa_finance_golden2_pg.mjs` (tek kullanımlık yerel veritabanı; `--runs 2` AYRI sitelerde iki koşu, gözlemler kimliksiz kanonik JSON olarak birebir aynı olmalı, `GOLDEN2_DIGEST` yazar; iki ayrı süreç koşusunun özeti de aynı).
- Örnek site tohumu: `tools/demo_seed/golden_site.mjs` (hedef koruması + `demo_seed_registry` geri alma; `tools/demo_seed/README.md` "Altin veri seti 2 ornek sitesi").

**Site:** `A Blok`, 6 daire; A-2, A-4, A-6 kiracılı (oturan kiracı, sorumlu = kiracı), A-1, A-3, A-5 malik oturan. Arsa payları 12 / 14 / 16 / 18 / 20 / 20 (payda 100); kategoriler 1+1, 2+1, 2+1, 3+1, 3+1, 3+1.

| Adım | Girdi | Elle hesap / beklenen |
| --- | --- | --- |
| Devir alacağı (K16) | A-5, `-500,00` (2026-09-01) | A-5 ev sahibi hesabı −50.000; tahsilat sayılmaz; M1 ile aidattan düşer |
| Aylık aidat, **kategori** tabanı (2026-09, 2026-10) | 1+1 120.000, 2+1 150.000, 3+1 180.000 | dönem toplamı 960.000; oturanın hesabı: kiracılı daireler kiracı hesabı |
| Asansör bakım payı, **daire başı sabit** | 25.000, oturan, vade 11-10 | toplam 150.000; vadesi gelecek: devredilmez, gecikmez |
| Çatı onarımı, **arsa payı** | 1.000.003, ev sahibi (Fon), vade 11-20 | 120.000 / 140.000 / 160.000 / 180.001 / 200.001 / 200.001 (artan 3 kuruş en büyük kalanlara A-5, A-6, A-4); kiracılı dairede de ev sahibi hesabı |
| Ödemeler | A-1 2 x 120.000; A-2 kiracı 200.000; A-3 600.000; A-5 400.000; A-6 kiracı 2 x 180.000 | bakiye sonrası: A-3 −115.000 (alacak), A-5 135.001, A-2 kiracı 125.000 |
| Mahsup | A-2 kiracı; A-5 | A-2: Eylül 0, Ekim 100.000, asansör 25.000 açık. A-5: çatı 135.001 açık (devir alacağı olmasaydı 185.001) |
| K17 adayları | saat 2026-10-20 | A-4 (2 kalem, 360.000, en eski vade 09-05) ve A-2 (1 kalem, 100.000); A-6 aday DEĞİL (yalnız gelecek vadeli borç); toplam 460.000 |
| A-2 devir + geri alma (K1) | Ekim aidatı 150.000, ödenmiş kısım 50.000 | devir: kiracı 125.000 → 25.000, ev sahibi 140.000 → 240.000, 3 satır; geri alma: tam eski değerler, 6 satır kalır |
| A-4 "kiracı vermezse malik öder" (K17 + K3) | 360.000 ödenmemiş | seçimsiz ödeme 400 `FUND_CHOICE_REQUIRED` (açık: İşletme 360.000, Fon 180.001); bayat toplam 409; devir: kiracı 385.000 → 25.000, ev sahibi 180.001 → 540.001; malik İşletme 360.000 + Fon 180.001 öder → 0; geri alma 409 `LIABILITY_TRANSFER_OWNER_PAID` |
| A-3 iade (K4) | alacak 115.000 | 120.000 talebi 409 `REFUND_EXCEEDS_CREDIT`; 100.000 iade onayı: bakiye −15.000, Kasa 1.800.000 → 1.700.000, makbuz sıra 1 |
| Kasa değişmezi | — | İşletme tahsilatı 1.820.000 + Fon 405.001 + avans 15.000 = hesaplar 2.240.001 (Kasa 1.700.000 + Banka 540.001) |

**Gecikme tazminatı (Ekim 2026, `daily_30`, ek gün 0, %5) — devrin tabana etkisi:** A-2 kiracı 2.500.000 kuruş·gün → **4.167**; A-3 ev sahibi 1.950.000 → **3.250**; A-4 kiracı 5.940.000 → **9.900**; A-5 ev sahibi (devir alacağıyla) 1.270.000 → **2.117**; toplam **19.434**.
Sabitlenen iki davranış (kod değişirse test bunu söyler, kararı sahibi verir):
- **Devir günü tabandan düşer.** Devrin yazdığı kalemler kayıt günüyle (10-20) yazılır ve «geç kaydedilen kalem kayıt gününden önce gecikmeye girmez» kuralıyla ertesi günden gecikir; kiracıdaki asıl kalem ters kayıt gününden itibaren sayılmaz. Sonuç: devir (ve geri alma) ile
  gecikme tabanı **bir gün eksik** hesaplanır (A-2: devir olmasaydı 2.600.000 → 4.333; A-4 devir olmasaydı kiracı hesabında 10.260.000 → 17.100, devirle kiracıda 5.940.000 + ev sahibinde 0 çünkü aynı gün ödedi).
- **Devir alacağı tabanı düşürür** (A-5: 1.620.000 → 1.270.000, 2.700 → 2.117) ve iade sonradan yazılan borçla (kayıt günü 10-20) önceki günlerin tabanını değiştirmez.

**Bozma denemeleri (2026-10-29):** tazminat eşiğinde kayıt gününü yok sayma ve devirde malik borcunu kalan yerine asıl tutarla yazma değişiklikleri saf testte VE gerçek PostgreSQL betiğinde yakalandı (ikisi de geri alındı).

## Devir bakiyesi (F4, 2026-10-21)

Eski yazılımdan devreden daire borçları toplu yükleme altyapısıyla yüklenir (`docs/PLATFORM_TOPLU_ISLEMLER.md` «Hepsi bir arada ve devir bakiyesi»).
Arayüz: Finans > Daireler > «Devir bakiyesi» (yalnız yazma yetkisi) -> «Excel'den yükle», yüklemeler listesi, «Geri al». Finans temel modül olduğundan her sitede açıktır.

Tablolar (migration 055): `finance_opening_reverts(run_id PK -> bulk_import_runs, site_code, reversed_count, reversed_total_minor, idempotency_key, reverted_by, reverted_at)`,
tekil `(site_code, idempotency_key)`. Defter kayıtları `ledger_entries.source_kind='opening'`, `source_id` = yükleme.

Uçlar (`/manager/sites/:siteCode/finance/opening-balances`, yetki: finans yönetici/süper + kurul okur):
- `GET` yüklemeler ve durumları. `GET /:runId` geri alma önizlemesi (ters kaydı yazılacak satır sayısı ve tutarı, tek tek iptal edilmiş satırlar, devirden sonra
  tahsilatı olan daire sayısı, sonradan hesaplanmış gecikme tazminatı kaydı sayısı).
- `POST /:runId/revert {reason, idempotency_key, expected_count, expected_total_minor}` (`withFinanceTransaction`): ters kaydı olmayan devir satırlarına açık ayda,
  bugünün tarihiyle `reversal` yazılır (hesap asıl kayıttan); ters kayıtlar da `source_kind='opening'` taşır. Aynı anahtarla tekrar 200; başka anahtarla 409
  `OPENING_ALREADY_REVERTED`; sayı/tutar değiştiyse 409 `OPENING_CHANGED`; başka sitenin yüklemesi 404. Audit `finance.opening.reverted`.

Kurallar: defter yalnız eklemelidir (geri alma ters kayıtladır); gecikme tazminatı açılırsa devir kalemi ana borç gibi işler, eski yazılımdaki
tazminat tutara katılmışsa faiz üstüne faiz riski vardır [AVUKAT DOĞRULASIN]. Önceki kiracının borcu kiracı hesabına yazılırsa yeni kiracı görür (NO_TENANT uyarısı azaltır).

### Alacaklı devir (K16, P2-4; 2026-10-29)

Daire önceki yazılımdan ALACAKLI geliyorsa (peşin ödenmiş aidat vb.) dosyada tutar EKSİ yazılır (`-500,00`). `OPENING_CREDIT_UNSUPPORTED` hatası KALKTI.

- **Defter modeli:** alacak, fazla ödemeyle AYNI yoldur: `ledger_entries` satırı `kind='payment'` (tutar negatif), `source_kind='opening'`, `source_id` = yükleme, `due_date` NULL
  (alacağın vadesi yok), `definition_name='Devir alacağı'`, `account_party` = seçilen hesap, `fund` NULL (kasa kısıtı yok). `method` şemada tahsilat için zorunlu olduğundan `'transfer'` yazılır;
  bu gerçek bir havale DEĞİLDİR: istemci kaynak izinden (`LedgerEntry.isOpeningCredit`) «Devir alacağı» etiketler. Borçlar (`kind='charge'`) eskisi gibidir. Şema DEĞİŞMEDİ (migration yok).
- **Mahsup:** alacak, sonraki borçlara M1 ile düşer (`finance_m1.js`: vadesi en eski borçtan başlayarak; mahsup HESAP bazındadır: ev sahibi hesabının devir alacağı kiracı hesabının borcunu kapatmaz);
  artan alacak kalır; gecikme tazminatı tabanı ve yaşlandırma alacağı da bu mantıkla düşer (hepsi `kind='payment'` toplamını kullanır; kod değişmedi).
- **Tahsilat DEĞİLDİR (kaynak izi `opening` ile ayrılır):** gelir-gider ve yönetici ana sayfası «tahsilat» toplamlarına (`finance_reports.computeIncomeExpense`, `finance_home`), «son hareketler» listesine,
  kasaya eşlenmemiş tahsilat denetimine (ay kapatma engeli, `finance_accounts.UNASSIGNED_WHERE`, `cash-position`) ve devir geri alma önizlemesindeki «sonradan tahsilat» sayımına GİRMEZ;
  makbuz düzenlenmez (409 `RECEIPT_NOT_APPLICABLE`); tahsilat düzeltmesi yapılmaz (409 `ENTRY_NOT_CORRECTABLE`); tek tek iptal (ters kayıt) mümkündür (ters kayıt da `source_kind` taşır).
  (Mevcut davranış korunur: `finance_read_service` özetindeki ve yönetim şirketi tablosundaki «borçlandırılan / tahsil edilen» dönem toplamları devir kayıtlarını, borç ve alacak olarak, simetrik içerir.)
- **Yükleme:** satır tutarı işaretlidir (`-` ya da parantez); `0` atlanır. Alacakta `Vade` hücresi yok sayılır (`OPENING_CREDIT_DUE_IGNORED` uyarısı). Aynı daire + hesapta etkin devir (borç ya da alacak) varsa:
  aynı değer «değişiklik yok», farklı değer ya da borç↔alacak çakışması `OPENING_EXISTS`. Önizleme sayıları: `opening_add` (yazılacak kayıt = borç + alacak), `total_minor` (BORÇ toplamı), `opening_credit_add`,
  `credit_total_minor` (ALACAK toplamı, büyüklük).
- **Onay toplamları AYRI:** commit gövdesi `options.expected_total_minor` (borç) + `options.expected_credit_total_minor` (alacak; yoksa 0). Biri uyuşmazsa 409 `TOTAL_MISMATCH` ve hiçbir şey yazılmaz.
  Alacaklı bir dosyayı eski istemci (alacak toplamını göndermeyen) onaylayamaz: güvenli taraf.
- **Geri alma:** `ACTIVE_SQL` borç + alacak kayıtlarını birlikte tersler. `GET /:runId` → `revert.credit_entries_to_reverse`, `revert.credit_total_minor` (ve `run.credit_entry_count/credit_total_minor`);
  `POST /:runId/revert` gövdesi `expected_credit_total_minor` (isteğe bağlı, varsayılan 0); uyuşmazsa 409 `OPENING_CHANGED`. `finance_opening_reverts.reversed_total_minor` BORÇ toplamını tutar (CHECK >= 0 korunur);
  yanıt ve audit `reversed_credit_total_minor` taşır. Audit `finance.opening.imported` ayrıca `credit_rows` / `credit_total_minor` yazar.
- **Altın veri seti:** `server/test/fixtures/finance_golden_site.js` OC1-OC6 (alacak + eşit aidat mahsubu, alacağın aidatlardan büyük olduğu durum, hesap bazlı mahsup, gecikme tazminatına etkisi, site toplamları);
  gerçek PostgreSQL doğrulaması: `server/scripts/qa_finance_distribution_pg.mjs` (S3).

## Yönetici ana sayfası "Bu ay" (G5) — PANELDEN KALDIRILDI (2026-10-21, kullanıcı isteği)

**Durum:** Panel'deki "Bu ay" başlığı, dört sayı kartı, "Aylık döngü" tablosu ve son hareketler KALDIRILDI (yöneticiler ne olduğunu anlamadı). Panel'de yalnız koyu dikkat barı kalır (`ManagerAttentionBar`, `lib/ui/widgets/manager_attention_bar.dart`): `home` ucunun `attention` alanından, sayısı > 0 olan iş varsa çizilir; iş yoksa, veri alınamazsa ya da yüklenirken hiçbir şey çizilmez; birden çok sitede her sitenin işi ayrı satırdır. Aylara göre rakamlar artık Finans > Grafikler sekmesindedir (`docs/PLATFORM_FINANS_4B.md` "Grafikler"). Aşağıdaki sunucu ucu (`home`) DEĞİŞMEDİ ve dikkat barı için kullanılır; `numbers`, `steps`, `recent` alanlarını bugün hiçbir istemci ekranı göstermez.

Eski tasarım notu (tarihî):

`GET /manager/sites/:siteCode/finance/home?month=YYYY-AA` (varsayılan bu ay, İstanbul; yetki: finans okuma; modül kapalı 403 `MODULE_DISABLED`; no-store; tek REPEATABLE READ READ ONLY işlem). Gövde: `month`, `numbers` (`charged_minor` devir ve tazminat hariç, `late_fee_minor`, `collected_minor`, `collection_rate_bp` null olabilir, `overdue_apartment_count` hesap bazlı vadesi geçen, `apartment_count`, `cash_total_minor` hesap yoksa null, `cash_account_count`), `steps` (charge, notify, match, expense, report; durum done/partial/todo/setup/unavailable), `attention` (kayıt defteri `server/src/modules/attention_registry.js`: modül `registerAttentionSource({key, module, run(db, siteCode) -> {count, total_minor?}|null})` ile satır ekler; bugün `unassigned_payments`), `recent` (son 3 ayda tahsilat, tahsilat iptali, gider, gider iptali; en yeni 5; kişi adı ve açıklama yok). "Rapor al" adımı: gelir-gider ve kurul özeti rapor uçları yönetici/süper için `finance.report.viewed {report, from, to}` audit satırı yazar; finans dışa aktarma (`export`) da sayılır. Gecikme tazminatının "kapalı ay" şartı değişmedi. İstemci: `ManagerMonthPanel` (yalnız yönetici kitlesi, yazma yetkili ve finans açık site; hata "Bu ayın özeti alınamadı." + Tekrar dene).

## Kiracı borcunun malike devri (K1 / P1-1, 2026-10-28; migration 089)

Sahip sözü: «Kiracı ödemezse daire borçlu olduğu için mal sahibi öder» ve «Kiracı çıkmadan önce borcu varsa mal sahibi bilgilendirilir». Hesap modeli (ev sahibi / kiracı ayrı hesap) **bozulmaz**;
devir yazılımın kendiliğinden verdiği bir karar DEĞİLDİR: **açık, yönetici onaylı, izli ve geri alınabilir** bir eylemdir.

**Devredilebilir kalem:** kiracı hesabında M1 mahsubu (`finance_m1.m1Remainders`: ödemeler vadesi en eski borçtan başlayarak düşer) sonrasında kalanı > 0 olan, **vadesi bugün ve öncesi** olan,
**gecikme tazminatı ve alacak iadesi OLMAYAN** `charge`. Gecikme tazminatı kalemleri devredilmez (kiracıda kalır; önizlemede ayrı listelenir). Planlama SAFTIR: `finance_liability_plan.js`.

**Defter (eklemeli, kalem bazlı ters kayıt).** Her devredilen kalem D (tutar A, kalan R) için, hepsi `source_kind='liability_transfer'`, `source_id` = devir kaydı:
- kiracı hesabında D'nin TERSİ (`reversal`, asılın tersi; DB tetikleyicileri aynalamayı / hesabı / kasayı zorlar);
- D kısmen ödenmişse (R < A) kiracı hesabında ödenen kısım (A − R) için AYNI vadeyle YENİ borç (kiracının ödemesi o kısmı kapatmaya devam eder);
- malik hesabında R tutarında YENİ borç (aynı ad, aynı vade, **aynı kasa**: Fon borcu Fon borcu olarak devredilir; kasa AÇIK yazılır; `run_id` ve tanım bağı yoktur).
Net: kiracı −R, malik +R, iki hesabın toplamı DEĞİŞMEZ. Satırlar açık dönemde ve bugünün tarihiyle yazılır (kapalı dönemde de çalışır; vade korunur). Tahakkuk raporlarında (`charged`) devir satırları
sayılmaz (net 0); raporlar `COALESCE(source_kind,'') NOT IN ('opening','refund','liability_transfer')` ile süzer.

**İz:** tablo `finance_liability_transfers` (kim / ne zaman / kaç kalem / toplam / neden + önizleme özeti; değişmez; geri alma YENİ satırdır, `reverses_transfer_id`, yönler yer değiştirir); denetim kaydı
`finance.liability_transfer.created|reversed` (tutar / kalem sayısı / daire / dönem; **neden metni ASLA**); malike uygulama içi bildirim. Devir ekstrede açık etiketlidir
(`source_kind`: `liability_transfer`; açıklama «Kiracı hesabından devreden borç» / «Devir sonrası kalan borç (ödenmiş kısım)» / «Devir geri alındı: borç kiracı hesabına döndü»).

**Uçlar** (`/manager/sites/:siteCode/finance/…`; yazma = yönetici / süper, okuma = + kurul adsız, görevli / sakin 403, başka site 403):
| Uç | Açıklama |
|---|---|
| `GET liability-transfer/candidates` | **K17 (gecikmede öneri).** `{ items[{apartment_id, unit_label, block_name, reason: 'overdue'|'exited', tenant_present, has_owner, can_transfer, item_count, total_minor, oldest_due_date}], count, total_minor, truncated }` (en çok 500 daire; büyük tutar önce; kişi adı yok). Yazmaz. |
| `GET apartments/:id/liability-transfer/preview` | `{ has_owner, can_transfer, items[{entry_id, name, due_date, original_minor, remaining_minor, paid_minor, fund}], excluded_late_fee[], item_count, total_minor, preview_hash, tenant_balance_minor, owner_balance_minor }`. Yazmaz. |
| `POST apartments/:id/liability-transfer` | `{ expected_total_minor, expected_hash, reason, idempotency_key }` -> 201 `{ transfer, tenant_balance_minor, owner_balance_minor }`. Tutar / özet değiştiyse 409 `LIABILITY_TRANSFER_CHANGED`; malik kaydı yoksa 409 `NO_OWNER`; kalem yoksa 409 `NOTHING_TO_TRANSFER`; aynı anahtar = aynı kayıt (200), farklı gövde 409 `IDEMPOTENCY_CONFLICT`. |
| `GET apartments/:id/liability-transfers` | devirler ve geri almalar (`reversible`: geri alınabilir mi). |
| `POST liability-transfers/:id/reverse` | `{ reason, idempotency_key }`. Malik hesabındaki devir borçları ve kiracıdaki «ödenmiş kısım» borçları TERS çevrilir, kiracıya her kalemin TAM tutarı yeniden yazılır (ters kaydın tersi olmadığı için); bakiyeler devirden önceki değerlere döner, satırlar KALIR. Bir devrin tek geri alması (409 `LIABILITY_TRANSFER_ALREADY_REVERSED`); geri alma kaydı geri alınamaz (409 `LIABILITY_TRANSFER_NOT_REVERSIBLE`); **devrin yazdığı bir borç satırı sonradan başka bir devirle ters çevrilmişse de 409 `LIABILITY_TRANSFER_NOT_REVERSIBLE` (hiçbir satır yazılmaz; çift sayım koruması, geçmişte `reversible=false`)**; **devirden sonra malik hesabına ödeme girildiyse 409 `LIABILITY_TRANSFER_OWNER_PAID`.** |
Genel «kaydı iptal et» ucu (`entries/:id/reverse`) devir / iade satırını reddeder (409 `ENTRY_MANAGED_BY_FLOW`).

**Çıkış öncesi malik bildirimi (S4).** Kiracılık biterken (kiracı «çıkış», «Daireden ayrıl», yönetici «Taşındı»; hepsi `people_service.closeResidency`) kiracı hesabında ödenmemiş borç varsa, çıkış TAMAMLANMADAN
önce malik(ler)e uygulama içi bildirim gider (`finance_exit_notice.js`; tutar + «kiracının hesabında kalır; site yönetimi onaylarsa hesabınıza devredilebilir»). Çıkış **ENGELLENMEZ**, bildirim hatası çıkışı bozmaz
(SAVEPOINT). Çıkıştan sonraki genel malik bildirimi borçlu / borçsuz ayrılır. Yöneticiye dikkat kaydı: `tenant_debt_pending_transfer` (kiracısı ayrılmış, kiracı hesabı borçlu daire sayısı + toplam).

**Gecikmede de öneri (K17, 2026-10-29).** Sahibin eki: «Borç mutlaka tahsil edilir; kiracı vermezse mal sahibi öder.» Devir yalnız kiracı ÇIKIŞINDA değil GECİKMEDE de yönetici önüne açıkça önerilir; yazma yine aynı desendedir
(önizleme + onay + neden + iz + geri alma; yazılım kendiliğinden devretmez). Aday = kiracı hesabında `planLiabilityTransfer`in devredilebilir saydığı en az bir kalemi olan daire (`GET liability-transfer/candidates`):
`reason='overdue'` kiracı hâlâ oturuyorsa (borç gecikmiş), `reason='exited'` güncel kiracı yoksa; `can_transfer` dairede güncel malik kaydı varsa (yoksa daire listelenir, devredilemez: önce malik kaydı eklenir).
Yönetici dikkat kaydı (`attention_registry`): `tenant_debt_overdue_transfer` = kiracısı OTURAN + devredilebilir gecikmiş borcu olan + malik kaydı bulunan daire sayısı ve toplamı; çıkış satırı
`tenant_debt_pending_transfer` ayrı kalır. Aday listesi KESİLMEDEN ÖNCE süzülür (dalga B inceleme düzeltmesi): SQL, kiracı hesabında M1 kalanı > 0 ve vadesi bugün ve öncesi olan, tazminat olmayan kalemi bulunan daireleri seçer, 500 sınırı bundan SONRA
uygulanır (kesilirse en büyük tutarlar kalır); dikkat satırı kesilmiş listeden sayıldıysa `at_least: true` taşır ve istemci «En az N» yazar. **İstemci (dalga B):** yönetici dikkat barı iki anahtarı açık etiketle yazar
(«N dairede kiracının borcu gecikti; ev sahibine devredilebilir» / «… kiracı ayrıldı …») ve «Devri İncele» ile «Malike Devredilebilir Borçlar» penceresini açar; Daireler sekmesinin üstünde aynı öneri şeridi bulunur (yalnız yazma yetkisi
olana); aday satırına dokunmak daire için «Kiracı Borcunu Malike Devret» penceresini açar (önizleme + devir geçmişi; devir nedenli ayrı onay penceresiyle yapılır, 409 `LIABILITY_TRANSFER_CHANGED` olursa önizleme yenilenir; «Geri Al» yalnız
sunucu `reversible` derse görünür). Aynı pencere dairenin hesap ekstresinden de açılır (iki hesaplı dairede «Kiracı Borcunu Malike Devret»). Sözleşme dosyaları: `lib/models/finance_liability.dart`, `lib/services/finance_4b_api.dart`.

Metin ve hukuki zemin: **avukat onayı bekler** (`docs/yasal/AVUKAT_KONTROL_LISTESI.md` madde 42).

## Alacak iadesi (K4 / P1-4, 2026-10-28; migration 088)

Sahip sözü: «Fazla ödeme yapan isterse parasını geri alır; almazsa gelecek borcundan düşer». **Fazla ödeme VARSAYILAN olarak ALACAK kalır** (mevcut M1 / mahsup davranışı DEĞİŞMEDİ). İade **isteğe bağlı** ve **yönetici onaylıdır**.

**Akış.** Sakin «Fazla ödememi iade et» (tutar ≤ alacak) ya da yönetici sakin adına talep açar (`requested`) → yönetici ödeme hesabını (kasa / banka) seçip **onaylar** ya da gerekçeyle **reddeder**; sakin onaydan önce
**geri çekebilir** (`cancelled`). Onayda TEK işlemde: (1) defterde avansı tüketen `charge` (`source_kind='refund'`, `source_id` = iade, kasa YOK), (2) seçilen hesaptan ÇIKIŞ hareketi
(`account_movements.kind='refund'`, negatif; nakit hesapta bakiye yetmiyorsa 409 `CASH_INSUFFICIENT`), (3) iade makbuzu `IA-yıl-sıra` (boşluksuz sayaç `finance_refund_counters`, değişmez anlık görüntü +
doğrulama kodu; tahsilat makbuzu `MK` dizisinden AYRI), (4) denetim kaydı `finance.refund.approved` (tutar / hesap / makbuz no; not ve ret nedeni ASLA), (5) sakine bildirim. Yanlış onay **geri alınır**
(ters kayıt + ayna hareket; makbuz iptal sayılır; `finance.refund.reversed`).

**Kurallar.** Tutar onayda daire kilidi altında `max(0, −hesap bakiyesi)` ile sınanır (409 `REFUND_EXCEEDS_CREDIT`); talep anında bekleyen talepler de düşülür (en çok 5 bekleyen). Tutar onayda değiştirilemez. İade tarihi
HER ZAMAN bugündür; ayı kapalıysa 409 `PERIOD_CLOSED`. Sakin yalnız KENDİ hesabı için talep açar (başka daire 404). Hesapta onaylı iade varken o hesabın **ödemesi iptal / düzeltilemez** (409
`REFUND_BLOCKS_PAYMENT_CHANGE`; önce iade geri alınır). Durum makinesi DB tetikleyicisiyle de korunur (çekirdek sütunlar değişmez; onay için hareket ve defter satırı DB'de doğrulanır; silinemez).

**Kasa (fon) değişmezi.** `allocateFunds`'a isteğe bağlı `refund` bayrağı eklendi (`toAllocatorEntry`: `source_kind='refund'` olan `charge`): iade YALNIZ avansı tüketir (önce genel avans, sonra kasa kısıtlı avanslar),
hiçbir kasaya tahsilat YAZMAZ; ödemenin dağılımına `refunded` eklenir (yalnız iade varken; iadesiz girdide çıktı birebir aynıdır — rastgele özellik testi). İşletme + Fon + avans = hesapların toplamı **korunur**: iade fiziksel
hesabı VE avansı eşit azaltır.

**Raporlar.** İade tahakkuk (`charged`) sayılmaz; gelir-gider ve özetlerde iade **net tahsilatı düşürür** (`collected` = ödemeler − iadeler); «Kasa durumu»nda iade hareketi **Giderler (çıkış) sütunundadır**
(gider raporu — `expenses` tablosu — iadeyi içermez). Hesap hareket listesinde etiket «Alacak iadesi: {daire}».

**Uçlar.** Sakin: `POST /app/my-finance/refund-requests` `{ apartment_id, amount_minor, note?, idempotency_key }`, `GET …`, `POST …/:id/cancel`. Yönetici (`/manager/sites/:siteCode/finance/refunds`; yazma = yönetici / süper,
okuma = + kurul adsız, görevli / sakin 403): `GET` (süzgeç `status`, `apartment_id`, `before_id`), `GET /:id`, `POST` (sakin adına talep: + `account_party`), `POST /:id/approve { pay_account_id, idempotency_key }`,
`POST /:id/reject { reason, idempotency_key }`, `POST /:id/reverse { reason, idempotency_key }`. Dikkat kaydı: `refund_requests` (bekleyen talep sayısı + toplamı). Makbuz PDF'i istemcide üretilir (sunucu anlık görüntü + kod verir).

**İstemci (Dalga B ekranları).** Yönetici: Daireler sekmesinde onay bekleyen talep varsa uyarı kartı (sayı + toplam, «İadeleri İncele») ve her durumda «İade talepleri» düğmesi (kurul listeyi açar, eylem görmez);
dikkat barı `refund_requests` satırı «N iade talebi onayınızı bekliyor, toplam …» + «İadeleri İncele» (pencereyi doğrudan açar). «İade Talepleri» penceresi: süzgeç (Bekleyen / İade edilen / Tümü), «Onayla» (ödeme hesabı
YÖNETİCİ seçer; nakit hesapta bakiye yetmezse onaydan önce uyarı + sunucu 409), «Reddet» (gerekçe zorunlu, sakine gösterilir), onaylı iadede «Geri Al» (nedenli) ve «Makbuzu Gör» (IA-yıl-sıra, hesap, yöntem, doğrulama kodu; geri
alınan iadenin makbuzu «İptal edildi»; iade makbuzu şimdilik yalnız ekranda görüntülenir, PDF / yazdır YOK). Sakin: Borcum kartında alacak varsa «Fazla ödememi iade et» (tutar = alacak − bekleyen talepler; sınır sunucuda da sınanır), talep listesi (Onay bekliyor / İade edildi + makbuz /
Reddedildi + neden / Geri çekildi / İade geri alındı), bekleyen talep için «Talebi Geri Çek». Alacak ve talep yoksa bölüm çizilmez. Dosyalar: `lib/models/finance_refund.dart`, `lib/ui/dialogs/finance_refunds_dialog.dart`,
`finance_refund_approve_dialog.dart`, `finance_refund_receipt_dialog.dart`, `my_refund_request_dialog.dart`, `lib/ui/widgets/finance_refunds_entry.dart`, `my_refund_section.dart`.

**KVKK bütünlüğü (karar kayıtlı).** Kişisel veri dışa aktarma (`account_export_service`) sakinin KENDİ açtığı iade taleplerini `refund_requests_made` bölümüne koyar (daire, hesap türü, tutar, kendi notu, durum, tarihler, iade makbuzu
numarası); yönetimin ret gerekçesi, çıkış hesabı, geri alma nedeni ve yönetici adına açılan talepler dışarıda bırakılır (`excluded` açıklar). **Bekleyen iade talebi hesap silmeyi ENGELLEMEZ**: silmede talep `cancelled` olur ve işlem
izine `finance.refund.cancelled` (`reason: account_deleted`; not YOK) yazılır, silme özetine `refunds_cancelled` eklenir (`account_refund_cleanup.js`); onaylı / reddedilmiş talepler değişmez (defter eklemelidir).

**Doğrulama.** Birim: `finance_funds_refund.test.js` (allocateFunds + rastgele özellik), `finance_liability_plan.test.js`, `finance_refunds.test.js`, `finance_*_schema.test.js`, `finance_devir_iade_routes.test.js` (yetki matrisi).
Gerçek PostgreSQL: `server/scripts/qa_finance_devir_iade.mjs` (devir / geri alma, iade talep → onay → makbuz → geri alma, kasa değişmezi, yarışlar, DB korumaları; 70 kontrol).
