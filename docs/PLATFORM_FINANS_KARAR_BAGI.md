# Finans: Demirbaş / Fon tahakkukunun dayanağı (Karar Defteri kaydı ya da gerekçe) ve sakin kalem dökümü

Bu belge sunucu (`server/`) ve uygulama (`lib/`) için BAĞLAYICIDIR. Öncül belgeler: `docs/PLATFORM_FINANS.md` (defter, tahakkuk = borçlandırma), `docs/PLATFORM_FINANS_KASALAR.md` (iki hesap: İşletme Projesi (Aidat) Hesabı / Yatırım ve Demirbaş (Fon) Hesabı), `docs/PLATFORM_KARAR_DEFTERI.md` (kesin karar). Karar: K2 (karşılaştırma güçlendirme programı, madde P1-2) ve P2-1.

## 1. Kural (K2)

Yatırım ve Demirbaş (**Fon / `capital`**) hesabına borç yazan her tahakkuk bir DAYANAĞA bağlanır:

| Karar Defteri (`decision_book`) modülü | Zorunlu girdi | Eksikse |
| --- | --- | --- |
| **AÇIK** | `decision_id`: bu sitenin KESİNLEŞMİŞ (numara almış) kararı | 400 `DECISION_REQUIRED` (gerekçe tek başına yetmez) |
| **KAPALI** | `decision_reason`: serbest metin gerekçe (3..300 karakter, tek satır) | 400 `DECISION_REASON_REQUIRED`; `decision_id` gönderilirse 400 `DECISION_MODULE_OFF` (sessizce yok sayılmaz) |

- "Tahakkuk" = çalıştırma (`fee_runs`): `POST …/finance/definitions/:id/post` (aylık/tek seferlik tanım borçlandırma) ve `POST …/finance/charges` (ek borç). Her çalıştırmanın dayanağı AYRI girilir (aylık Fon tanımında her ayın borçlandırması kendi dayanağını taşır; arayüz son seçimi önermez, yönetici bilerek seçer).
- Fon hesabı = tanımın / ek borcun etkin `fund` değeri `capital` (`charge_party = owner`). **İşletme (Aidat) hesabında dayanak zorunlu DEĞİLDİR**; verilirse (`decision_id` / `decision_reason`) aynı kurallarla doğrulanır ve saklanır. Günlük aidat akışı değişmez.
- Karar bu sitenin olmalıdır: başka sitenin / olmayan karar 404 `DECISION_NOT_FOUND` (aynı yanıt: kimlik sızmaz); taslak (numarasız) karar 409 `DECISION_NOT_FINAL`. Kararın oy sonucu (`vote_result`) denetlenmez: kayıt sahibinin seçimidir, arayüz oy sonucunu seçim satırında gösterir.
- Modül AÇIKKEN ek `decision_reason` (not) da gönderilebilir; ikisi birlikte saklanır.
- Denetim finans yazma işleminin İÇİNDE, `finance_post:<site>` advisory kilidi altında ve plan hesaplanmadan ÖNCE yapılır (hızlı ret; hiçbir şey yazılmaz, işlem geri alınır). Karar satırı `FOR KEY SHARE` okunur.
- Geriye uyum: dayanaksız (eski) istemci Fon tahakkuku yazamaz (400, Türkçe ileti arayüzde gösterilir); işletme hesabı yazmaları eskisi gibi çalışır. Uygulama sürümü güncellenene kadar yönetici Fon borcunu web sürümünden yazar.

## 2. Uçlar (eklemeli; eski alanlar korunur)

- **Önizleme** (`POST …/definitions/:id/preview`, `POST …/charges/preview`) yanıtına `decision_requirement: { required, mode, module_enabled, reason_min, reason_max }`: `mode` = `decision` (Fon + modül açık), `reason` (Fon + modül kapalı), `none` (işletme hesabı). Önizleme dayanak ALMAZ ve doğrulamaz; arayüz bu alana göre girdiyi önizleme aşamasında ister.
- **Onay gövdesi** (`POST …/definitions/:id/post`, `POST …/charges`) isteğe bağlı `decision_id` (pozitif tamsayı) ve `decision_reason`. Geçersiz biçim 400 `INVALID_BODY`. Parmak izine YALNIZ verilmişse girer: dayanaksız isteğin parmak izi eskisiyle aynıdır; aynı `idempotency_key` + farklı karar/gerekçe 409 `IDEMPOTENCY_CONFLICT`.
- **Yanıt** `run.decision`: `{ id, number_label ("2026/4"), title, visibility, reason }` (dayanak varsa; yoksa alan YOK). Tekrar (aynı anahtar) aynı dayanakla döner.
- **Daire ekstresi** (`GET …/apartments/:id/account`): borç satırlarında `Entry.decision` (aynı biçim; yönetici ve kurul tüm alanları görür). Dayanaksız satırda ve tahsilatta alan yoktur.
- **Sakin** (`GET /app/my-finance`): `recent[].decision` = `{ number_label, title, reason }` — başlık YALNIZ karar sakinlere açıksa (`visibility = sakinler`), iç kimlik ve görünürlük bayrağı verilmez. **Gerekçe, yönetimin sakinlere göstermek üzere yazdığı metindir**: arayüz yazarken "sakinlerin Borcum ekranında görünür" uyarısı verir (yönetici serbest metinlerinin sakine verilmemesi kuralının bilinçli ve tek istisnası).
- **Audit**: `finance.run.posted` / `finance.charge.posted` ayrıntısına `decision_id` ve `decision_reason_given: true`; gerekçe METNİ denetime/günlüğe YAZILMAZ.

## 3. Sakin kalem dökümü (P2-1)

`GET /app/my-finance` her daire öğesine (kendi hesabı) ve `accounts[]` her görünümüne `breakdown: { items, truncated }` ekler.

- Kalem = sakin kapsamında (dayanak ayı ≥ taşınma ayı) ve hâlâ ödenmemiş (kalan > 0) borç. Tamamen ödenen, iptal edilen (ters kayıtlı) ve kapsam dışı kalemler listelenmez. Sıra mahsup sırasıdır (vade, kimlik).
- `Item`: `entry_id`, `type` (`monthly` aylık tanım, `one_time` ek borç / tek seferlik tanım, `late_fee`, `opening` devir bakiyesi, `other` tanımsız: sayaç faturası, düzeltme), `name` (borçlandırma anındaki tanım adı), `fund` (`operating` | `capital`), `period` (`YYYY-MM`), `due_date`, `overdue` (vade bugün ve öncesi), `amount_minor`, `remaining_minor`, `decision` (sakin biçimi ya da `null`). Para tamsayı kuruş.
- `remaining_minor` bakiyeyi hesaplayan AYNI mahsuptan gelir (`finance_resident_view.residentView` → `lines`); ayrı hesap yoktur. Kalemlerin kalan toplamı, görünür alacak kalanı düşülmeden önceki kapsam içi borca eşittir.
- En çok 200 kalem (en eski vadeli önce); fazlası `truncated: true`.
- Yönetici serbest metinleri (açıklama, ters kayıt nedeni) ve oluşturan adı kaleme KONMAZ. Eski sunucuda alan yoktur: arayüz bölüm çizmez ve "borç yok" DEMEZ.
- Arayüz: Borcum kartında "Borç kalemleri (N)" düğmesi (varsayılan kapalı); açılınca her kalemin kaynağı ("Ekim 2026 • Ek borç • Fon Hesabı"), tutar / ödenen / kalan, vade ve "Dayanak: Karar 2026/4 · …" ya da "Dayanak: Gerekçe: …".

## 4. Şema (migration 090)

`migrations/090_finance_run_decision.sql` = `server/src/modules/finance_run_decision_schema.js` adımlarının birleşimi (test: `finance_run_decision_schema.test.js`); `db.js` AYNI adımları katalog kontrolüyle ve her adım kendi otomatik onaylı ifadesiyle uygular (`ensureFinanceRunDecisionSchema`).

- `fee_runs.decision_id BIGINT`, `fee_runs.decision_reason TEXT` (ikisi de NULL olabilir; varsayılansız; **geri doldurma yok**: 090 öncesi çalıştırmalar ve işletme hesabı çalıştırmaları dayanaksız kalır).
- `chk_fee_runs_decision`: `decision_reason` NULL ya da 1..300 karakter (NOT VALID → VALIDATE).
- `fee_runs_decision_fkey`: bileşik `(site_code, decision_id) → board_decisions (site_code, id)`, `ON DELETE NO ACTION` (karar AYNI sitede olmak zorundadır; kesin karar silinemez; site silme CASCADE zinciri iki tabloyu aynı ifadede siler; SET NULL KULLANILMAZ çünkü `fee_runs` eklemelidir).
- `idx_fee_runs_decision (site_code, decision_id) WHERE decision_id IS NOT NULL`.
- Veritabanı tetikleyicisi KONMAZ: zorunluluk uygulama katmanındadır, çünkü canlıdaki geri alma hedefi (090'ı bilmeyen sürüm) Fon çalıştırmasını dayanaksız yazar. `fee_runs` zaten `trg_fee_runs_append_only` ile eklemelidir: dayanak çalıştırma yazılırken konur, sonradan DEĞİŞMEZ.

## 5. Bilerek kapsam dışı

- Tahsilatın hangi hesaba gireceğinin seçimi, İşletme / Fon hesapları arası aktarım ve Fon gideri için karar bağı (hesap tasarımı W2'nin diğer parçaları) bu dilimde YOK.
- Eski (090 öncesi) çalıştırmaların dayanağı sonradan eklenemez (`fee_runs` eklemeli).
- Karar Defteri kaydı noter onaylı karar defterinin yerine geçmez (`docs/PLATFORM_KARAR_DEFTERI.md`); gerekçe metni hukuki dayanak değil, yönetimin açıklamasıdır. Sakine görünen karar/gerekçe metinleri avukat kontrol listesine (`docs/yasal/`) eklenmelidir.

## 6. Doğrulama

- Birim (DB'siz, katı sahte DB): `server/test/finance_run_decision.test.js` (kural matrisi, 400/404/409 yolları, hiçbir şey yazılmaz, idempotans, denetimde metin yok), `finance_run_decision_schema.test.js`, `finance_debt_breakdown.test.js` (kalem dökümü, mahsup tutarlılığı, sakin gizliliği, `getMyFinance`).
- İstemci: `test/finance_run_basis_models_test.dart`, `test/screens/finance_decision_basis_test.dart` (onay kapısı, gönderilen alanlar, taşma matrisi, kalem dökümü açılımı).
- Gerçek PostgreSQL: `scripts/qa_finance_funds_section.mjs` K12 (`QA_CONFIRM_DISPOSABLE_DB=yes QA_ONLY=chain,live,funds node scripts/qa_platform_pg.mjs`). Diğer finans QA bölümleri Fon borcu yazarken `qa_finance4b.mjs` / `qa_platform_pg.mjs` `call` yardımcısı, gövdede `decision_id` / `decision_reason` hiç yoksa KAPALI sitelerde gerekçe ekler (bu bölümlerin konusu dayanak değildir).
