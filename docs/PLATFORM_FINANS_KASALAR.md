# Finans: İki Kasa (İşletme Projesi (Aidat) Hesabı / Yatırım ve Demirbaş (Fon) Hesabı) ve Kiracı Admin

Bu belge sunucu (`server/`) ve uygulama (`lib/`) için BAĞLAYICIDIR. Öncül belgeler: `docs/PLATFORM_FINANS.md` (defter, iki daire hesabı İP-1A,
`charge_party`, `account_party`), `docs/PLATFORM_FINANS_4B.md` (kasa/banka hesapları, gider, makbuz, raporlar), `docs/PLATFORM_DAIRE_YONETIMI.md`
(daire admini, kiracı, devir). Kullanıcı kararı: 2026-10-26.

## 1. Kavramlar

- **Kasa (fon):** her sitede İKİ mantıksal kasa vardır:
  - `operating` → **"İşletme Projesi (Aidat) Hesabı"**: aidat ve işletme giderleri; borcu **dairede oturan** öder (kiracı varsa kiracı, yoksa malik).
  - `capital` → **"Yatırım ve Demirbaş (Fon) Hesabı"**: yatırım, demirbaş, büyük onarım katkı payları; borcu **her zaman malik** öder.
- **Ad (kullanıcı kararı, 2026-10-26):** arayüzde, makbuzda, raporda ve hata metinlerinde kasalar TAM bu adlarla anılır: "İşletme Projesi (Aidat) Hesabı" ve "Yatırım ve Demirbaş (Fon) Hesabı" (kısa yer gerekirse "Aidat Hesabı" / "Fon Hesabı"). Ev sahibi / kiracı daire hesaplarıyla ve nakit / banka hesaplarıyla karışmasın diye bu iki ad hep tam yazılır; kod adları `operating` / `capital`.
- Kasa bir **bakiyedir**, fiziksel hesap değildir. Nakit ve banka hesapları (`finance_accounts`) olduğu gibi kalır ve iki kasada ortaktır. Her
  tahsilat ve gider bir kasaya yazılır; iki kasanın bakiyesi ayrı izlenir.
- **İki daire hesabı (değişmedi, İP-1A):** her dairenin ev sahibi (`owner`) ve kiracı (`tenant`) hesabı vardır. Kasa kuralı bunun üstüne kurulur:
  - Kiracılı daire: Fon borçları malik hesabına, İşletme borçları kiracı hesabına yazılır (ödemeleri de ilgili hesaba).
  - Malik oturuyorsa iki kasanın borcu da malik hesabındadır.

## 2. Borcun kasası

| Kaynak | Kasa |
|---|---|
| Aidat / borç tanımı (`fee_definitions`) | `charge_party = owner` ⇒ `capital`; `occupant` ⇒ `operating` (canlı veriyle birebir: aidatlar `occupant`, asansör / dış cephe katkı payları `owner`) |
| Gecikme bedeli | Kaynak borcun kasası (türetilemiyorsa `operating`). **Uygulama:** tazminat HESAP başına tek satırdır; satırın kasası, vadesi geçen anaparanın kuruş·gün tabanında AĞIR BASAN kasadır (eşitlikte / tabansızda `operating`) |
| Devir bakiyesi (açılış) | `operating` (bu sürümde) |
| Sayaç borçlandırma | `operating` |
| Diğer borç kaynakları | `operating`; uygulayıcı her kaynağı listeler ve belgeye ekler (kesin liste §8.1) |

- Tanım API'si `fund` alanını döndürür (charge_party'den türetilmiş). Yazmada `fund` verilebilir: `capital` ⇒ `charge_party = owner`,
  `operating` ⇒ `occupant`; ikisi birlikte verilir ve çelişirse 400 `INVALID_BODY`. `charge_party` sütunu ve eski istemci uyumu korunur.
- `ledger_entries.fund` (NULL | `operating` | `capital`) eklenir. Yeni borç satırları kasayla yazılır. 080 öncesi satırlarda NULL kalır ve kasa
  OKUMADA türetilir: çalıştırma → tanım `charge_party`; bulunamazsa `operating`. Ters kayıt, asılın kasasını taşır.

## 3. Tahsilatın kasalara dağıtımı (otomatik, en eski vade önce)

- Dağıtım **okumada türetilir** (saklanmaz). Her daire hesabı (`apartment_id` + `account_party`) için:
  1. Borçlar (charge, kasa ve vade ile) vade tarihine göre (eşitlikte id) sıralanır; alacaklar (payment / alacak yönlü kayıtlar) tarih sırasıyla
     işlenir; ters kayıtlar asıllarını nötrler.
  2. Her alacak, o anda açık olan en eski vadeli borçtan başlayarak kapatır. Borcu aşan kısım **avanstır** ve sonradan oluşan borçlara (vade
     sırasıyla) uygulanır.
  3. Tahsilatta isteğe bağlı `fund` verilmişse (yönetici "yalnız şu kasa" seçti) o tahsilat yalnız o kasanın borçlarına uygulanır; artanı o
     kasanın avansıdır.
- Bir dağıtımın tarihi = max(tahsilat tarihi, borcun tarihi). Kasa hareket dökümü bu tarihle sıralanır.
- Bu kural daire ekstresinde kasa bazında açık borç, sakinin "Borcum" ekranında kasa kırılımı ve kasa bakiyelerinin TEK kaynağıdır (tek saf
  işlev; birim testleriyle sabitlenir).

### 3.1 Hesap (İşletme / Fon) seçimi: yazılım ödemeyi kendiliğinden atamaz (K3, 2026-10-28; sahip kararı, karşılaştırma raporu P1-3)

- **Kural.** Tahsilatın hangi hesaba (İşletme Projesi (Aidat) Hesabı / Yatırım ve Demirbaş (Fon) Hesabı) gireceğini yönetici belirler. Bir daire hesabında (daire + ev sahibi / kiracı hesabı) `allocateFunds` sonucundaki AÇIK borca göre:
  - **İki türün de açık borcu varsa seçim ZORUNLUDUR.** `fund` verilmeyen tahsilat 400 `FUND_CHOICE_REQUIRED` ile reddedilir (hiçbir satır yazılmaz); hata gövdesi `fund_choice` ek alanıyla açık borçları taşır.
  - **Yalnız bir türün açık borcu varsa** önerilen hesap formda SEÇİLİ gelir (yönetici değiştirebilir). Sunucu kendiliğinden kısıt atamaz: kısıt, istemci seçili gönderirse yazılır; gönderilmezse (eski istemci) kısıtsız kalır (zaten tek türe uygulanır).
  - **Açık borç yoksa** seçim zorunlu değildir; tutar genel avans olur ve sonradan yazılan borca eskisi gibi mahsup edilir.
  Dağıtım ikinci yerde hesaplanmaz: açık borçlar `allocateFunds` sonucundan okunur (`finance_fund_choice.js`). Borç düzeyindeki "en eski vade önce" mahsup kuralı DEĞİŞMEZ.
- **Uygulandığı yollar** (hepsi tek giriş noktası `finance_parties.postPayment` içinde denetlenir; idempotent tekrar denetimden geçmez):
  elle tahsilat (`POST payments`); tahsilat düzeltmesi (`entries/:id/correct`: yeni tahsilat ters kayıttan SONRA denetlenir, asıl kayıt kısıtlıysa kısıt korunur); dekont onayı (`payment-notices/:id/approve` gövdesinde `fund`; toplu onayda iki türlü satır `FUND_CHOICE_REQUIRED` koduyla tek tek başarısız olur);
  banka satırı "Daireye işle" (`bank-lines/:id/assign` gövdesinde `fund`) ve onay (`bank-lines/confirm` gövdesinde SATIR BAŞINA `fund_choices: [{ line_id, fund }]`; seçim gereken satır `failed` listesinde kalır, bir satırın seçimi başkasına uygulanmaz);
  banka dosyası yüklemesi (iki türlü borçlu daireye eşleşen güçlü satır OTOMATİK işlenmez: önizlemede `check` + `FUND_CHOICE_REQUIRED` uyarısı ve `summary.fund_choice` sayısı, kayıtta `suggested` + satır notu `FUND_CHOICE_REQUIRED`).
- **Uç.** `GET …/finance/payments/fund-choice?apartment_id=&account_party=&amount_minor=&paid_on=` (yazma yetkisi; kurul / görevli / sakin 403; yazmaz) → `{ apartment_id, account_party, open: { operating_minor, capital_minor }, advance_minor, choice_required, suggested_fund, proposal }`. `account_party` verilmezse tahsilat hesabı `postPayment` ile aynı kuralla çözülür. `proposal` (yalnız `amount_minor` verilmişse) otomatik dağıtımın NE yapacağını yalnız BİLGİ olarak gösterir.
- **Arayüz.** Tahsilat, dekont inceleme, "Daireye işle" ve "Tek tek gözden geçir" pencereleri aynı parçayı kullanır (`FundChoicePanel`, başlık "İşletme / Fon hesabı"): iki türde "Otomatik" yoktur ve seçim yapılmadan kayıt GÖNDERİLMEZ; tek türde öneri seçili gelir; borçsuzda "Hesap seçmeden (genel avans)". Tahsilat düzeltmede asıl kayıt hâlâ defterde olduğundan durum okunmaz; sunucu 400 verirse panel zorunlu kipe geçer.
- **Bölme yok.** Tutarı iki hesaba bölmek için iki ayrı tahsilat girilir (ayrı makbuz); bölünmüş tahsilat ve karar defteri bağlantısı bu sürümde yoktur.

## 4. Gider ve kasa bakiyesi

- `expense_categories.fund` (varsayılan `operating`); her siteye sistem kategorisi **"Yatırım ve demirbaş"** (`capital`) eklenir (idempotent).
- Giderin kasası: gider satırındaki kasa seçimi varsa o, yoksa kategorinin kasası. Gider formunda kasa, kategoriden öndoldurulur.
  İptal edilen gider hiçbir kasayı etkilemez.
- **Kasalar arası aktarım** (`finance_fund_transfers`): tarih, kaynak kasa, hedef kasa, tutar, açıklama; eklemeli; düzeltme yalnız ters aktarımla.
  Fiziksel hesap hareketi doğurmaz. Kullanım: açılış bölüşümü ve kurul kararıyla aktarım.
- **Kasa bakiyesi** = açılış + dağıtılmış tahsilatlar − giderler ± aktarımlar. Açılış: fiziksel hesapların açılış bakiyeleri toplamı İşletme'ye,
  Fon'a 0.
- **Avans** (henüz borca dağıtılmamış ödeme) iki kasaya da yazılmaz, ayrı satırda gösterilir. Değişmez: İşletme + Fon + avans = tüm hesapların
  toplam bakiyesi (aynı kapsamdaki hareketler için).

## 5. API (eklemeli; eski alanlar korunur)

- Tanım uçları: `fund` (okuma + yazma, bkz. §2).
- Tahsilat (`POST …/payments`): isteğe bağlı `fund` (`operating` | `capital`; yoksa otomatik). Yanıta `fund_split` (bu tahsilatın şu anki
  dağıtımı: `{ operating_minor, capital_minor, advance_minor }`).
- Daire ekstresi (`…/apartments/:id/account`): `funds: { operating: { balance_minor, overdue_minor }, capital: {…} }`; her `Entry` için `fund`.
- Sakin (`/app/my-finance`): her hesap öğesine `funds` kırılımı (kiracı yalnız `operating`; kiracılı dairede malik yalnız `capital`).
- Gider ve kategori uçları: `fund`.
- Yeni: `GET …/finance/funds` (iki kasa: açılış, tahsilat, gider, aktarım, bakiye; ayrıca avans; `from` / `to` dönem süzgeci) ve
  `GET …/finance/funds/:fund/movements` (sayfalı döküm). `POST …/finance/fund-transfers` ve ters aktarım ucu. Yetki: mevcut finans kuralları
  (okuma: yönetici, süper, kurul; yazma: yönetici, süper).
- Makbuz anlık görüntüsüne verildiği andaki `fund_split` eklenir (bilgi amaçlı).

## 6. Uygulama (Flutter)

- Tanım formu: "Kim öder" yerine **"Kasa"** seçimi: "İşletme Projesi (Aidat) Hesabı — dairede oturan öder (kiracı varsa kiracı)" ve
  "Yatırım ve Demirbaş (Fon) Hesabı — malik öder". Listelerde kasa etiketi.
- Tahsilat formu: "İşletme / Fon hesabı" seçimi (K3, §3.1): iki türlü borçta zorunlu, tek türde önerilen hesap seçili, borçsuzda isteğe bağlı. Kaydedince dağılım gösterilir.
- Gider formu ve kategori yönetimi: "Kasa".
- Finans > Kasa sekmesinin üstünde iki kasa kartı (bakiye, dönem tahsilatı, gideri, aktarımlar) + avans satırı + "Kasalar arası aktarım";
  altında mevcut nakit / banka hesapları listesi.
- Daire ekstresi ve sakinin "Borcum" ekranı: kasa bazında borç.
- Taşma yok (AGENTS.md kural 6); canlı yenileme (kural 7).

## 7. Kiracı her zaman daire admini

- Dairede güncel kiracı varsa **daire admini kiracıdır**; malik ve kiracı aynı dairede birlikte tanımlıdır. Malik admin kalamaz.
- "Yönetimi kiracıya devret" seçimi kalkar: malik kiracı eklediğinde, site yöneticisi kişi kartından / daire ekranından kiracı ilişkisi
  eklediğinde ve toplu yüklemede kiracı admin olur. Toplu yüklemede admin önceliği: kiracı > malik > diğerleri.
- Kiracı ayrılınca (taşındı, çıkarıldı) admin yeniden malik olur (mevcut kural).
- Mevcut daireler: güncel kiracısı olup admini malik kalan her dairede admin kiracıya geçer (açılışta idempotent, denetim kaydıyla).
  Kiracı hesapsızsa gösterge mevcut kurala göre davranır.
- Finans görünürlüğü değişmez (kiracı kiracı hesabını, malik ev sahibi hesabını görür).

## 8. Sunucu uygulaması (gerçekleşen ayrıntılar; §1-§5'e göre AYRINTILI, çelişirse bu bölüm)

Kod: `server/src/modules/finance_funds.js` (saf kurallar + TEK dağıtım işlevi `allocateFunds`), `finance_funds_schema.js` (migration **080** = `migrations/080_finance_funds.sql`, aynı idempotent adımlar),
`finance_funds_service.js` (kasa özeti, döküm, aktarım), `finance_funds_routes.js` (uçlar). Birim: `test/finance_funds*.test.js`; gerçek PG: `scripts/qa_finance_funds_section.mjs` (`qa_platform_pg.mjs` "funds").
Ad sabitleri: `FUND_LABELS` ("İşletme Projesi (Aidat) Hesabı" / "Yatırım ve Demirbaş (Fon) Hesabı"), `FUND_SHORT_LABELS` ("Aidat Hesabı" / "Fon Hesabı"); yanıtlarda ad döndürülen yerler `fund_label` / `fund_short_label`.

### 8.1 Borç satırı yazan TÜM yollar ve kasaları

| Yol (dosya) | Kasa |
|---|---|
| Aylık borçlandırma `POST …/definitions/:id/post` (`finance_service.writeRun`) | tanımın etkin `charge_party` değeri: `owner` ⇒ `capital`, `occupant` ⇒ `operating` (tüm satırlar aynı kasa) |
| Ek borç `POST …/charges` (`finance_service.writeRun`) | aynı kural; varsayılan `charge_party = owner` ⇒ `capital` (`fund: "operating"` verilirse `occupant`) |
| Gecikme tazminatı `POST …/late-fee/post` (`finance_late_fee.js`) | satır başına ağırlıklı kasa (yukarıdaki tablo); iptalde (`void`) ters kayıtlar asılın kasasını kopyalar |
| Tahsilat (`finance_parties.postPayment`; yönetici tahsilatı, düzeltmenin yeni tahsilatı, dekont onayı, banka satırı, kart) | borç değildir; satırdaki `fund` = "yalnız bu kasaya" KISITIDIR (NULL = otomatik) |
| Ters kayıt `…/entries/:id/reverse`, `…/correct` (`finance_ledger_service.insertReversal`) | asılın HAM `fund` değeri kopyalanır; DB tetikleyicisi `trg_ledger_entries_fund` boşsa asıldan doldurur, farklıysa P0001 ile reddeder |
| Devir bakiyesi geri alma `…/opening-balances/:runId/revert` (`finance_opening.js`) | asılın `fund` değeri (devirde NULL) kopyalanır |
| Sayaç borçlandırma (`metering_billing.js`) | `operating` (satıra yazılır) |
| Devir bakiyesi yükleme (`bulk_import_writer.applyOpeningOps`; BAŞKA ajanın dosyası, değiştirilmedi) | NULL yazılır; okumada `source_kind = 'opening'` ⇒ `operating` türetilir |

**Fon (capital) hesabına borç yazan iki yol (aylık borçlandırma ve ek borç) bir DAYANAĞA bağlanır** (K2, migration 090): Karar Defteri modülü açık sitede kesinleşmiş karar (`decision_id`), kapalı sitede serbest metin gerekçe (`decision_reason`) zorunludur; sözleşme `docs/PLATFORM_FINANS_KARAR_BAGI.md`.

080 öncesi satırlarda `fund` NULL KALIR (geri doldurma yok) ve OKUMADA `effectiveFund` ile türetilir: kaynak `opening` ⇒ `operating`; gecikme tazminatı ⇒ `operating`; `definition_id` varsa tanımın etkin
"kim öder" değeri (NULL ise aylık `occupant`, tek seferlik `owner`) ⇒ `operating` / `capital`; aksi `operating`. Tahsilat satırında NULL "kısıtsız" demektir (türetme yok).

### 8.2 Dağıtım (`allocateFunds`) ayrıntıları

- Girdi bir daire HESABININ satırları (ev sahibi ya da kiracı hesabı ayrı ayrı); çıktı: kasa bazında `open` (açık borç), `overdue` (vadesi `bugün` ve öncesi), `advance` (o kasaya kısıtlı avans), `generalAdvance`, `advanceTotal`, her tahsilatın
  dağıtımı (`operating` + `capital` + `advance` = tutar) ve tarihli dağıtım olayları.
- Olaylar (tarih, borç önce, id) sırasıyla işlenir (zaman duyarlı): tahsilat yalnız O ana kadar kaydedilmiş borçlara uygulanır; borçtan fazlası avanstır ve sonradan kaydedilen borca (önce o kasaya kısıtlı avans, sonra genel avans, tahsilat sırasıyla)
  uygulanır. Geç kaydedilen eski vadeli borç, sonraki tahsilatlarda açık borçların önüne geçer; önceki tahsilat yeniden dağıtılmaz. Ters kayıt asıl kaydı VE kendisini yok sayar ("güncel durum"; asılı bulunmayan öksüz ters kayıt kendi işaretiyle borç / alacak sayılır).
- Kısıtsız tahsilatlarda ve borçlar tahsilattan ÖNCE kaydedildiyse sonuç M1 mahsup kuralıyla (`finance_m1.m1Remainders`) BİREBİR aynıdır (birim testi 200 rastgele hesapla doğrular).
- Değişmez: `open(operating) + open(capital) − advanceTotal = hesap bakiyesi` (rastgele 400 hesapla test).

### 8.3 Uç sözleşmeleri (alan adları kesin)

Tüm tutarlar tamsayı kuruş. Hata gövdesi `{ error, code }` (Türkçe `error`).

- **Tanım** `GET/POST/PATCH …/definitions`: `Definition.fund` (`operating` | `capital`; `charge_party`'den türetilir). Yazma gövdesinde `fund`; `charge_party` ile birlikte çelişirse 400 `INVALID_BODY`. PATCH `fund` borçlandırılmış tanımda da değişir (yalnız sonraki borçlandırmaları etkiler). Ek borç `POST …/charges/preview|charges` gövdesinde `fund`.
- **Tahsilat** `POST …/payments` gövde: `fund?` (`operating` | `capital`; yoksa otomatik). Yanıt: `{ entry, balance_minor, account_balance_minor, receipt, movement_id, fund_split }`; `entry.fund` = kısıt (kısıtsız `null`); `fund_split = { operating_minor, capital_minor, advance_minor }`.
  Aynı `idempotency_key` + farklı `fund` ⇒ 409 `IDEMPOTENCY_CONFLICT`; kısıtsız tekrar (eski istemci) aynı kaydı döndürür. `POST …/entries/:id/correct` gövdesinde de `fund?` (verilmezse ASILIN kısıtı korunur); yanıtta `fund_split`.
- **Entry** (ekstre, tahsilat yanıtı, ters kayıt): `fund`; ekstre öğelerinde ayrıca `fund_split` (yalnız tahsilatta dolu, diğerlerinde `null`).
- **Daire ekstresi** `GET …/apartments/:id/account[?account_party=]`: `funds: { operating: { balance_minor, overdue_minor, advance_minor }, capital: { … } }` (açık borç; `advance_minor` = o kasaya kısıtlı avans) ve `advance_minor` (TOPLAM avans, kısıtsız dahil).
  Kapsam: `account_party` verilmişse o hesap, verilmemişse iki hesabın toplamı.
- **Sakin** `GET /app/my-finance`: her öğede ve `accounts[]` her görünümünde `funds` + `advance_minor` (sakin kapsamı kuralı: yalnız dayanak ayı ≥ `visible_from` olan borçlar sayılır; dağıtım hesabın TÜM satırlarıyla yapılır, kapsam dışı eski borçlar önce ödenir). Üst düzey `funds` = kendi hesabı.
- **Gider** `POST …/expenses` gövde `fund?` (yoksa kategorinin kasası; satıra HER ZAMAN yazılır); `Expense.fund`. Düzeltmede (`…/correct`) yeni gider kendi `fund`'ını alır.
- **Kategori** `GET/POST/PATCH …/expense-categories`: `fund`. Oluşturmada varsayılan `operating`. PATCH ile kasa değişimi: sistem kategorisinde 409 `CATEGORY_FUND_LOCKED`; kasası kaydedilmemiş (080 öncesi) gideri olan kategoride 409 `CATEGORY_FUND_LOCKED`.
  Sistem kategorisi "Yatırım ve demirbaş" (`is_system`, `fund = capital`): kategorisi olan siteler için migration / açılış veri adımıyla, kategorisi hiç olmayan siteler için varsayılan kümenin 13. kategorisi olarak (liste ucu eksikse tamamlar). Kategorinin açıklama alanı yoktur.
- **`GET …/finance/funds[?from=YYYY-MM-DD&to=YYYY-MM-DD]`** (okuma: yönetici, süper, kurul; no-store; site başına en çok 2 eşzamanlı ağır rapor, aşılırsa 503 `REPORT_BUSY` + `Retry-After`):
  `{ currency, from, to, has_accounts, funds: { operating: Fund, capital: Fund }, advance_minor, accounts_total_minor, difference_minor, balanced, unassigned_payments: { count, total_minor } }`;
  `Fund = { fund, fund_label, fund_short_label, opening_minor, collections_minor, expenses_minor, transfers_in_minor, transfers_out_minor, adjustments_minor, balance_minor, negative_balance }`.
  `to` yoksa bugün; `from > to` ⇒ 400 `INVALID_QUERY`. `balance_minor = opening + collections − expenses + transfers_in − transfers_out + adjustments`. `from` verilirse `opening_minor` = o günden önceki TÜM hareketler (+ aralık içinde açılan hesapların açılışı); bakiye hep `to` itibarıyladır.
  Yalnız bir kasa / banka hesabına EŞLENMİŞ (collection hareketi olan) tahsilatlar sayılır; eşlenmemişler `unassigned_payments`'ta ayrı raporlanır. Hesap düzeltme hareketleri (banka masrafı / faiz / sayım farkı, ayna dahil) `adjustments_minor` ile İşletme'ye yazılır (değişmezin tutması için).
  **Değişmez:** `operating.balance_minor + capital.balance_minor + advance_minor = accounts_total_minor` (`difference_minor = 0`, `balanced = true`). Dağıtım güncel durumdan türetildiğinden, geçmiş bir `to` için sonradan ters çevrilmiş tahsilat / iptal edilmiş gider fiziksel toplamla fark yaratabilir (`difference_minor ≠ 0`); `to = bugün` için fark 0'dır.
- **`GET …/finance/funds/:fund/movements[?from&to&limit=50&offset=0]`** (`:fund` = `operating` | `capital`, aksi 404 `FUND_NOT_FOUND`; limit ≤ 200):
  `{ fund, fund_label, fund_short_label, currency, from, to, balance_minor, total, limit, offset, items: [{ key, type, date, amount_minor, label, apartment, account, category, ref_id }] }`; `type`: `opening` | `collection` | `expense` | `transfer_in` | `transfer_out` | `adjustment`;
  `amount_minor` kasaya etkisidir (işaretli); tahsilatta `apartment = { id, label }` (kişi adı yok), giderde `category`, hesap hareketlerinde `account = { id, name }`. Sıra yeni → eski; `balance_minor` `to` itibarıyla kasa bakiyesidir.
- **`POST …/finance/fund-transfers`** gövde `{ from_fund, to_fund, amount_minor, transfer_date, description?, idempotency_key }` (yazma: yönetici, süper): kasalar farklı, tutar 1..10^12, tarih gelecek olamaz ve AÇIK ayda olmalı (409 `PERIOD_CLOSED`). 201 `{ transfer }` (aynı anahtar + aynı gövde 200 aynı kayıt; farklı gövde 409 `IDEMPOTENCY_CONFLICT`).
  `FundTransfer = { id, from_fund, to_fund, amount_minor, transfer_date, period, description, reverses_transfer_id, reversed_by_transfer_id, reversal_reason, created_by_name, created_at }` (`created_by_name` kurulda `null`).
- **`POST …/finance/fund-transfers/:id/reverse`** gövde `{ reason, idempotency_key }`: ters aktarım satırı (yönler yer değiştirir, aynı tutar, tarih BUGÜN, dönem açık ay) ⇒ 201 `{ transfer, original }`. Bir aktarımın tek ters aktarımı olur (409 `FUND_TRANSFER_ALREADY_REVERSED`); ters aktarım tekrar ters çevrilemez (409 `FUND_TRANSFER_NOT_REVERSIBLE`); başka sitenin / olmayan kimlik 404 `FUND_TRANSFER_NOT_FOUND`.
- **`GET …/finance/fund-transfers[?from&to&limit=50&before_id]`** ⇒ `{ items: [FundTransfer], next_before_id }` (yeni → eski).
- **Makbuz:** `snapshot.fund_split` (verildiği andaki dağıtım, bilgi amaçlı; 080 öncesi makbuzda yok; iptal makbuzu asılınkini kopyalar). Makbuz şablonu (`receipt.template`) `fund_labels` ve `fund_short_labels` taşır (metni sunucu verir).
- Denetim eylemleri: `finance.fund_transfer.created`, `finance.fund_transfer.reversed` (ayrıntıda yalnız kasa kod adları, tutar, dönem, kimlik; açıklama / neden / ad YOK); gider denetimine `fund` eklendi.

### 8.4 Şema (080) özeti

`ledger_entries.fund` (NULL | operating | capital; CHECK NOT VALID → VALIDATE; varsayılansız) + `trg_ledger_entries_fund`; `expense_categories.fund` (NOT NULL DEFAULT operating, CHECK); `expenses.fund` (NULL | operating | capital, CHECK);
`finance_fund_transfers` (eklemeli: genel `trg_finance_immutable('created_by')` + TRUNCATE engeli + ters aktarım ayna tetikleyicisi; `uq_finance_fund_transfers_reverses`, `(site_code, idempotency_key)` tekil; FK'ler ayrı ve katalog korumalı); veri adımı: kategorisi olan her siteye sistem kategorisi.
Açılış: `ensureFinanceFundsSchema` (db.js, 077/078'den sonra; hiçbir şey eksik değilse yalnız iki SELECT, kilit yok; ön koşul tablo / işlev yoksa hiçbir şey yapmaz).

### 8.4a Dönemsel rapor (aylık / 3 aylık / yıllık; karşılaştırma raporu P2-3)

- `GET …/finance/reports/period?from=YYYY-MM&to=YYYY-MM` (okuma: yönetici, süper, kurul; 120/saat/kullanıcı, rapor yuvası). Varsayılan: bu yılın ocağından bu aya; gelecek `to` bu aya çekilir; en çok 36 ay.
  Dönem sonu günü = ayın son günü (bu ay için bugün). Tek REPEATABLE READ anlık görüntüde hesaplanır; bölüm hatası BÜTÜN yanıtı hata yapar.
- Yeni hesap kuralı YOKTUR: Hesap (Aidat / Fon) rakamları `summarizeBook` ile, borçlu özeti `computeAging` ile aynıdır. Her Hesap için `opening_minor`, `collections_minor`, `expenses_minor`,
  `transfers_in/out_minor`, `adjustments_minor`, `closing_minor`, `change_minor` (= kapanış - açılış = tahsilat - gider + aktarım giriş - çıkış + düzeltme) ve `expense_by_category`.
  `months[]` aylık tahsilat / gider / net (Hesap bazında ve toplam); toplamları dönem toplamına eşittir. `totals` iki Hesabın toplamı; `reconciliation` (hesap toplamı - (Aidat + Fon + avans)).
- `debtors`: dönem sonu itibarıyla `debtor_count`, `apartment_count`, `total_overdue_minor`, yaşlandırma kovaları. KİŞİ VERİSİ YOKTUR (ad ve daire etiketi çıkmaz).
- Dışa aktarma: `GET …/finance/exports/finance_period_report?from=&to=` (yalnız yönetici / süper; uzun biçim: Bölüm / Hesap / Kalem / Dönem / Adet / Tutar; dosyayı istemci üretir).
- Sınırlar: dağıtım güncel durumdan türetildiği için geçmiş dönem sonunda `reconciliation.difference_minor` sıfırdan farklı olabilir (§8.5); Hesap bazında borçlu kırılımı YOK (yalnız toplam);
  PDF üretilmedi (ekran + CSV/Excel).

### 8.5 Bilerek kapsam dışı / bilinen sınırlar

- Kasa bakiyesi eksiye düşerse aktarım ENGELLENMEZ (`negative_balance` işareti; veri eksik olabilir). Aktarım yanıtı bakiye döndürmez (istemci `GET …/funds` ile yeniler).
- Dağıtım güncel durumdan türetilir (tarihli ters kayıt modeli yok): geçmiş `to` için fiziksel hesap toplamıyla fark olabilir (bkz. değişmez notu).
- `funds` uçları sitenin tüm defterini okur (balances ucu gibi O(site satırı)); site başına 2 eşzamanlı rapor yuvası, 120/saat/kullanıcı.
- Dışa aktarma (`exports/*`) ve raporlara (`reports/*`) kasa sütunu / kırılımı EKLENMEDİ.
- Devir bakiyesi yükleme yazıcısı (`bulk_import_writer.js`) değiştirilmedi: NULL yazar, okuma `operating` türetir.
- **Yan düzeltme (QA altyapısı):** platform öncesi kesilmiş şemada (QA "upgrade/live": db.js platform şablonu 031'de kesilir) HEAD'de zaten düşen ekleyici adımlar (054 `finance_payment_schema`, 056 `finance_expense_nature_schema`, 058 / 062 / 066 / 067 / 074) üst tablo yokken
  açılışı durduruyordu; 054 ve 056 üst tablo yoksa yabancı anahtar adımını erteler, diğerleri `db.js` `ensureDeferred` ile (yalnız 42P01 yutulur, başka hata açılışı durdurur) sarılıdır.
