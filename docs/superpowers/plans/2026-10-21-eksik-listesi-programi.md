# Eksik Listesi Programı — Uygulama Planı (2026-10-21)

> **Ajanlar için:** Bu belge programın ana planıdır. Her iş paketi (İP) ajanı işe başlamadan önce kendi alt planını
> `docs/superpowers/plans/2026-10-21-ip-<kod>.md` olarak yazar: dosya haritası (oluşturulacak / değişecek dosyalar ve her birinin tek
> sorumluluğu) ve test-önce görev listesi (`- [ ]`, her adım 2–5 dakikalık tek iş: önce düşen test, sonra en küçük kod, sonra yeşil,
> sonra commit). Ardından alt planı uygular ve kutuları işaretler. Kararlar: `docs/PLATFORM_YOL_HARITASI.md` → "Karar kaydı
> (2026-10-21)". Bu plan ile karar kaydı çelişirse karar kaydı geçerlidir.

**Amaç:** İşverenin üç belgesindeki (komutlar.txt, "Yazılımcı için Yol Haritası" PDF, "Yapılacaklar ve Kararlar 2026-10-19" PDF) ve
Apsiyon karşılaştırmasındaki eksikleri (yol haritası G/F/S/C/T/R/Y/H/D kodları) dalgalar hâlinde canlıya almak; dışarıdan hesap ya da
sözleşme gerektirenlerin temel yapısını hazırlayıp arayüzde "Yakında…" bırakmak.

**Mimari:** Modüler monolit. Flutter istemci (`lib/`; web, Android, iOS ve Windows tek kod), Node/Express API (`server/src`),
PostgreSQL 16 (`server/migrations/NNN_*.sql` ile `server/src/db.js` içindeki `ensureDbSchema` AYNI DDL'i taşır). Para tamsayı kuruş,
defter yalnız eklemeli (append-only), düzeltme ters kayıtla. Modüller katalogla açılır ve kapanır (`server/src/modules/catalog.js`,
`docs/PLATFORM_MODUL_SISTEMI.md`); istemci menüsü kapalıyken gizler (fail-closed).

**Teknoloji:** Flutter 3 / Dart, Node + Express + `pg`, `node --test`, `flutter_test`, gerçek PostgreSQL QA betikleri
(`server/scripts/qa_*.mjs`).

---

## 1. Ortak kurallar (her İP için)

1. **Çalışma yeri.** İP, Workflow'un açtığı ayrı worktree'de çalışır. İlk iş: `git merge --ff-only <taban dalı>` (taban dalı istemde
   verilir; worktree origin/main'den başlamış olabilir). Ana çalışma ağacına (`G:\site\site_kapi_kontrol`) yazılmaz.
2. **Dokunulmayacaklar.** Kapı açma mantığı (kapı komutları, MQTT, BLE, firmware, kapı servisleri ve kapı düğmesinin davranışı)
   DEĞİŞMEZ. Başka İP'nin dosyalarına yalnız "bağlantı noktası" kadar dokunulur (madde 9).
3. **Veritabanı.** Her İP'ye ayrılmış migration numarası kullanılır (bölüm 3 ve 4). DDL hem `server/migrations/NNN_*.sql` hem
   `server/src/db.js` `ensureDbSchema` içinde AYNI metindir (şema eşitlik testleri bunu denetler); yalnız ekleyici ve idempotent
   (`IF NOT EXISTS`). `db.js`'teki kilit notları (035 ve 036 açıklamaları) okunur. Yalnız eklemeli tablolara (ör. `ledger_entries`)
   UPDATE gerekiyorsa tetikleyici kuralı bozulmaz; geri doldurma yerine okuma tarafında türetme tercih edilir.
4. **Para.** Tamsayı kuruş (`amount_minor`, `server/src/modules/finance_money.js`); dağıtımda en büyük kalan yöntemi; yuvarlama farkı
   kaybolmaz. Mahsup: vadesi en eski borçtan.
5. **Yetki.** Her yeni uç `authRequired` + site rolü denetimi + modül açık mı (`MODULE_DISABLED`) + başka sitenin kimliğiyle 403/404
   testi (IDOR). Sakin yalnız kendi dairesini ve kendi hesabını görür. RLS yok (karar G13); yalıtım testle korunur.
6. **Kapalı gelir.** Yeni modül varsayılan KAPALI. Dışarıdan hesap gerektiren özellik arayüzde "Yakında…" görünür
   (`MODULE_STATUS_COMING_SOON` kalıbı, `catalog.js`).
7. **Test.** `cd server && npm test` ve `npm run lint`; `flutter analyze` (0 sorun) ve `flutter test` (tamamı). Para, yetki ve veri
   işlerinde gerçek PostgreSQL: mevcut QA betiklerinin ilgili bölümleri yeşil kalır, yeni davranış için yeni bölüm
   (`server/scripts/qa_<alan>_section.mjs` kalıbı) yazılır. Arayüz için widget testi; görsel kontrol için testte PNG önizleme üretmek
   serbesttir. Uygulama penceresi açmak, emülatör ya da tarayıcıda gezmek YOK (deneme kullanıcıdadır).
8. **Gerçek PG örneği.** İkililer: `G:\site\ev_otomasyon\tools\qa_stack\node_modules\@embedded-postgres\windows-x64\native\bin\`.
   Kendi veri dizinin worktree dışında olsun. `initdb -U postgres -A trust -E UTF8 --locale=C`; sunucuyu
   `postgres.exe -D <veri> -p <port> -c listen_addresses=127.0.0.1` ile Bash'te arka planda (`run_in_background`) başlat;
   `pg_ctl start -w` KULLANMA (aracı kilitler). Port İP'ye ayrılmıştır (bölüm 3 ve 4); 54329 ve 55432'ye dokunma. Bitince
   `pg_ctl stop -D <veri> -m fast`. Toplu ve tuhaf hatada önce PG günlüğüne bak (Windows'ta ara ara 0xC0000409 çökmesi bilinen
   oynaklıktır: yalnız o bölümü yeniden koş).
9. **Ortak dosyalar (çakışma alanı).** `lib/ui/widgets/yan_menu.dart`, `lib/ui/pages/home_page.dart`,
   `lib/ui/helpers/module_showcase.dart`, `server/src/server.js` (router kaydı), `server/src/modules/catalog.js`, yardım metinleri ve
   tanıtım turu. Bu dosyalarda yalnız kendi İP'nin satırlarını tek blok hâlinde ekle; yeniden düzenleme, taşıma ya da biçimlendirme
   yapma. `docs/SAHA_KONTROL_LISTESI.md` ve `tools/deneme_listesi/platform.json` dosyalarına DOKUNMA: deneme maddelerini son raporda
   ver (koordinatör ekler).
10. **Belge.** Alanın sözleşme belgesi (`docs/PLATFORM_<ALAN>.md`) güncellenir ya da yeni açılır: uçlar, tablolar, kurallar, inceleme
    kararları. Yardım metni ve tanıtım turu yeni ekranı anlatır.
11. **Dil.** Ekranda yöneticinin dili: borç, tahsilat, gider, daire, sakin. "Tahakkuk", "cari", "mutabakat", "tenant" ekranda yok. Kod
    ve uç adları İngilizce kalabilir.
12. **Tasarım.** `docs/TASARIM_DILI.md` ve karar G6/G7 (sade stil). Yeni ekranlar `context.palette`, `AppSpace`, `AppRadius`,
    `AppMotion` belirteçlerini kullanır; dokunma hedefi en az 48 dp; anlamsal etiketler; metin kontrastı en az 4.5:1.
13. **Görünmez karakter.** Kaynağa `\uXXXX` kaçışı yazma (yazma aracı bazılarını gerçek karaktere çeviriyor); gerekiyorsa kod noktası
    sayısı kullan (`String.fromCharCode(0x202e)`). Yazdığın dosyaları U+200B–U+200F, U+2028–U+202E, U+2060, U+FEFF için tara.
14. **Windows.** Worktree CRLF çıkarabilir; satır sonu testleri yalnız worktree'de düşebilir: yeni dosyaları LF yaz,
    `.gitattributes`'a uy. Kesme işaretli ya da regex'li betikleri Bash heredoc'una değil dosyaya yazıp çalıştır. Node'da yol
    `G:/...` biçiminde.
15. **Commit.** Türkçe, `feat(alan): …` / `fix(alan): …`; her mantıklı adımda commit; sonda kendi model adınla `Co-Authored-By:`
    satırı. Yalnız kendi dosyalarını ekle (`git add <yol>`), `git add -A` kullanma.
16. **Rapor.** İP sonunda istemdeki şemayla özet: commitler, değişen dosyalar, test sayıları (server, flutter, gerçek PG), açık riskler,
    deneme maddeleri (Faz Kontrol Listesi için: başlık, adımlar, beklenen sonuç) ve belge güncellemeleri. Doğrulamadığın şeyi
    "doğrulandı" diye yazma.

## 2. Paketler arası sözleşmeler

### 2.1 İki hesap (İP-1A çıkarır; dalga 2'deki dekont, banka dosyası ve devir bakiyesi kullanır)

- Defter satırı bir dairenin iki hesabından birine aittir: `account_party` = `'owner'` (Ev sahibi hesabı) ya da `'tenant'`
  (Kiracı hesabı). API alanı da `account_party`.
- Defterde kaynak izi: `source_kind` (`'manual'`, `'payment_notice'`, `'bank_line'`, `'opening'`, `'card'`) ve `source_id`.
- Sunucu modülü `server/src/modules/finance_parties.js` en az şunları dışa verir (adlar sabittir, dalga 2 bunları çağırır):
  - `ACCOUNT_PARTIES` = `['owner', 'tenant']`
  - `resolveChargeParty(client, { siteCode, apartmentId, chargeParty, onDate })` → `'owner' | 'tenant'`
  - `resolvePersonParty(client, { siteCode, apartmentId, userCode })` → `'owner' | 'tenant' | null`
  - `accountBalances(db, { siteCode, apartmentId })` → `{ owner: { balance_minor, overdue_minor }, tenant: { … } }`
  - `postPayment(client, { siteCode, apartmentId, accountParty, amountMinor, paidOn, method, description, sourceKind, sourceId,
    idempotencyKey, actor })` → `{ entryId, receiptId }`: tek giriş noktası; çağıran defterin iç yapısına dokunmaz.

### 2.2 Kurallar tablosu (İP-1B çıkarır)

- `server/src/modules/platform_rules.js`: `RULES` kayıt defteri (anahtar, tür, varsayılan, alt/üst sınır, sitede değişebilir mi,
  mevzuat notu) ve `getRule(db, key, { siteCode, onDate })`. Çözüm sırası: site değeri → platform değeri → varsayılan; sonuç her zaman
  sınırlar içine kırpılır (yasal üst sınır aşılamaz).
- Anahtarlar ve varsayılanlar: `finance.late_fee.monthly_bp_max` 500 (yalnız platform), `budget.provisional_max_days` 90,
  `budget.objection_days` 7, `heat.measured_share_pct` 70, `heat.area_share_pct` 30, `forecast.default_increase_bp` 0,
  `retention.finance_days` 3650, `retention.contact_after_moveout_days` 365, `retention.door_logs_days` 365,
  `retention.visitor_logs_days` 365, `retention.work_photos_after_close_days` 730, `retention.announcements_days` 1825,
  `retention.audit_days` 1825, `retention.decision_book_days` null (süresiz), `retention.enforce` false.

### 2.3 Tasarım belirteçleri (İP-1C çıkarır)

- `AppPalette` (`context.palette`) sade stil alanları: sayfa zemini #F8FAFC, kart #FFFFFF, kart çerçevesi #E2E8F0, gövde metni #475569,
  başlık metni #0F172A, ana eylem #0F172A ve üstündeki metin, odak halkası mavi, durum noktaları #10B981 / #F59E0B / #E11D48.
- `StatusDot` (nokta + metin) bileşeni. Dalga 2 ve sonrasındaki yeni ekranlar bunları kullanır.

### 2.4 Menü grupları (İP-1D çıkarır)

- `SirketMenuGroup` (Ana sayfa, Daireler, Borçlar, Tahsilat, Giderler, İletişim, Raporlar, Site hizmetleri) ve her `SirketMenuItem` için
  grup eşlemesi; Ayarlar öğeleri sağ üstteki dişliden açılır. Yeni ekran eklemek = enum değeri + grup eşlemesi + görünürlük kuralı.
- Sakin alt çubuğu sekmeleri (Özet, Duyuru, Arıza, Kapı, Belgeler) görünür öğelerden türetilir.

## 3. Dalga 1 (taban: Panel vitrini canlıya çıktıktan sonraki `main`)

| İP | Kapsam | Migration | Gerçek PG portu |
| --- | --- | --- | --- |
| 1A | G12 malik/kiracı iki hesap | 052 | 55441 |
| 1B | G11 kurallar tablosu + F5 altın veri seti | 053 | 55442 |
| 1C | G6 + G7 sade tasarım dili | — | — |
| 1D | G2 + G3 gruplu menü ve sakin alt çubuğu | — | — |
| 1E | H1–H6 ve G15: hukuk taslakları, hesap rehberleri, demo senaryosu | — | — |

D3 (veritabanı dış kopyası) koordinatör tarafından kurulur (zamanlanmış görev), İP değildir.

### İP-1A — G12 Malik/kiracı iki hesap

**Hedef (karar G12):** Her dairenin iki ayrı hesabı olur: Kiracı hesabı ve Ev sahibi hesabı; bakiyeler karışmaz. Sözleşme 2.1'deki
modül ve alanlar bu İP'de çıkar.

**Başlangıç noktaları:** `server/migrations/034_finance.sql` (ledger_entries, fee_definitions), `040_finance_4b.sql`;
`server/src/modules/finance_ledger_service.js` (`insertPaymentRow`, `responsibleParty`), `finance_read_service.js`,
`finance_resident_view.js`, `finance_service.js`, `finance_distribution.js`, `finance_late_fee.js`, `finance_late_fee_calc.js`,
`finance_reminder_queue.js`, `finance_reminders.js`, `finance_receipts.js`, `finance_reports.js`, `finance_export_tables.js`,
`finance_common.js`; `docs/PLATFORM_FINANS.md` ("Kim öder", "Kim görür", "Sakin kapsamı"), `docs/PLATFORM_FINANS_4B.md`;
istemcide `lib/models/finance.dart`, `lib/ui/views/my_finance_view.dart`, `lib/ui/dialogs/apartment_card_dialog.dart` ve finans
diyalogları; QA: `server/scripts/qa_platform_pg.mjs` (finance), `qa_finance4b_*.mjs`.

**Kurallar:**
- Borç tanımına `charge_party`: `'occupant'` (dairede oturanın hesabı) ya da `'owner'`. Varsayılan: dönemlik aidat `occupant`, tek
  seferlik ek borç `owner`; yönetici değiştirebilir.
- `occupant` borcunun yazılacağı hesap, dairenin `responsible_party` değerine göre: `owner` → ev sahibi hesabı (ev sahibi aidatı
  kendisi ödüyor); `tenant` ya da `both` → borç tarihinde dairenin etkin kiracısı varsa kiracı hesabı, yoksa ev sahibi hesabı.
- Var olan satırlar: hesap, satırdaki `payer_party` anlık görüntüsünden türetilir: `tenant` → kiracı, `owner` → ev sahibi, `both` → ev
  sahibi (makbuzdaki "both ⇒ malik" kuralıyla aynı). Yalnız eklemeli tabloya UPDATE yazmak yerine okuma tarafında türetme (ör.
  `COALESCE(account_party, CASE payer_party …)`) ya da tetikleyiciyi bozmayan güvenli bir geri doldurma; seçilen yol belgeye yazılır.
- Tahsilat seçilen hesaba yazılır; yönetici ekranında varsayılan hesap, vadesi en eski açık borcu olan hesaptır. Mahsup, gecikme
  tazminatı, hatırlatma, makbuz, yaşlandırma, ekstre ve dışa aktarma HESAP BAZINDA çalışır (dışa aktarmada "Hesap" sütunu).
- Görünürlük: kiracı kendi kiracı hesabını, ev sahibi ev sahibi hesabını görür; `responsible_party = both` ise ev sahibi kiracı hesabını
  da salt okunur görür. `family_member` hiçbir hesabı görmez (bugünkü kural). Sakin kapsamı (taşınma ayından itibaren) her hesap için
  o kişinin ilişki başlangıcına göre uygulanır.
- Hatırlatma, hesabın sahibine gider (kiracı hesabı → kiracı; ev sahibi hesabı → ev sahibi).

**İstemci:** Daire finans kartında iki sekme: [Kiracı hesabı] [Ev sahibi hesabı] (kiracısı olmamış ve kiracı hesabında satırı olmayan
dairede yalnız ev sahibi hesabı, sekmesiz). Tahsilat ve ek borç diyaloğunda hesap seçimi. Borcum ve vitrindeki borç kartı kişinin
kendi hesabını gösterir. Raporlarda hesap sütunu ya da süzgeci.

**Kabul:** sunucu ve istemci testleri yeşil; gerçek PG'de finance ve finance4b bölümleri yeşil + yeni `parties` bölümü (iki hesabın
karışmadığı, her hesabın kendi mahsubu, var olan satırların doğru hesaba düştüğü, görünürlük matrisi, IDOR, eşzamanlı tahsilat ×
borçlandırma kilit sırası); `docs/PLATFORM_FINANS.md`'de "İki hesap (2026-10-21)" bölümü.

### İP-1B — G11 kurallar tablosu + F5 altın veri seti

**Hedef (karar G11, F5):** Sözleşme 2.2'deki kurallar tablosu ve `getRule`; koda gömülü `LATE_FEE_MAX_MONTHLY_BP` üst sınırı kural
kaydından okunur (yasal sınır kırpma korunur). Kurallar Platform Ayarları'nda listelenir (süper değiştirir, site yöneticisi görür).

**Altın veri seti:** 24 daireli gerçekçi bir site (blok, m², arsa payı, kategori), en az şu senaryolar: eşit, m² (brüt ve net),
arsa payı ve kategori dağıtımı; yuvarlama farkı; gecikme tazminatı (gün hesabı, yalnız ana borca, aylık %5 sınırı); mahsup (en eski
vadeden). Beklenen değerler kodu çalıştırarak DEĞİL elle hesaplanır; hesap adımları fikstürde ya da belgede tablo olarak yazılır.
Sonuç kuruşu kuruşuna tutmazsa test düşer. Belge: `docs/PLATFORM_FINANS.md` "Altın veri seti" bölümü.

**Kabul:** birim testleri + gerçek PG'de kural tablosu ve çözüm sırası; `getRule` sınır kırpması; şema eşitlik testi.

### İP-1C — G6 + G7 sade tasarım dili

**Hedef (karar G6, G7):** Açık temada ana onay düğmesi #0F172A, düz (parlak katman, degrade ve gölge yok); ikincil düğme beyaz zemin,
#E2E8F0 çerçeve, #0F172A metin; kartlar #FFFFFF, 1 px #E2E8F0 çerçeve, gölgesiz; sayfa zemini #F8FAFC, ışıma yok; gövde metni
#475569, başlık #0F172A; durum gösterimi nokta + metin (`StatusDot`; `StatusChip` varsayılan görünümü buna döner), tehlike tonu #E11D48.
Mavi yalnız bağlantı ve odak halkası. Koyu tema kalır; ana düğme orada da en az 4.5:1 kontrastla çözülür.

**Başlangıç noktaları:** `lib/styles/app_theme.dart`, `app_colors.dart`, `app_decorations.dart`, `lib/ui/design/tokens.dart`,
`status_chip.dart`, `gloss.dart`, `icon_orb.dart`, `buttons.dart`, `app_card.dart`; vitrin renkleri `AppShowcaseColors`;
`docs/TASARIM_DILI.md`.

**Dokunulmayacak:** kapı düğmesi (`door_open_button.dart`) görünüşü ve davranışı; ekran akışları ve yerleşim.

**Kabul:** `flutter analyze` 0, `flutter test` tamamı; renk denetleyen testler güncellendi; kontrast ölçümleri belgede; önemli
ekranların PNG önizlemesi (scratch) kontrol edildi; `docs/TASARIM_DILI.md` güncel.

### İP-1D — G2 + G3 gruplu menü ve sakin alt çubuğu

**Hedef (karar G2, G3):** Çekmece menüsü sözleşme 2.4'teki 8 başlıkla gruplanır; Ayarlar öğeleri (profil, platform ayarları, modüller,
kullanıcılar, cihazlar, denetim kaydı, istemci hataları vb.) sağ üstteki dişliden açılır. Site seçici en üstte. Daire sakinine alt çubuk:
Özet · Duyuru · Arıza · Kapı · Belgeler; Kapı yalnız kapı yetkisi olana; modülü kapalı sekme görünmez; iki sekmeden azsa çubuk yok.
Özet = Panel vitrini (borç kartı üstte). Fail-closed kuralı ve vitrinin bugünkü davranışı korunur.

**Başlangıç noktaları:** `lib/ui/widgets/yan_menu.dart` (`SirketMenuItem`, rol listeleri, `additionalItems`, gizli öğeler),
`lib/ui/helpers/module_menu.dart` (`hiddenMenuItemsFor`), `lib/ui/pages/home_page.dart` (PopScope, sayfa değişimi, `_jumpBodyToTop`),
`lib/ui/helpers/module_showcase.dart`, `lib/ui/views/module_showcase_view.dart`, `lib/services/deep_link_service.dart`
(`showDoorPanel` → Kapı sekmesi), yardım içeriği ve tanıtım turu, `integration_test/walk_*` turları.

**Kabul:** widget testleri (rol × modül × kapı yetkisi matrisi: hangi grup ve sekme görünür), geri tuşu (sekmeden Özet'e, Özet'ten
çıkış), Android widget derin bağlantısı Kapı sekmesini açar; integration_test turları yeni gezinmeye uyarlandı (çalıştırma kullanıcıda);
yardım ve tur metinleri güncel.

### İP-1E — Hukuk taslakları, hesap rehberleri, demo senaryosu

**Okur:** Cenk (teknik değil) ve avukat. Sade Türkçe; her hukuki iddia madde numarasıyla ve `[AVUKAT DOĞRULASIN]` işaretiyle;
web kaynakları erişim tarihiyle. Uydurma madde, tarih ya da ücret YAZMA: doğrulayamadığını "doğrulanamadı" diye yaz.

**Dosyalar:**
- `docs/yasal/SAKLAMA_SURELERI_TASLAGI.md`: karar H2'deki süreler, dayanakları, otomatik silmenin nasıl çalışacağı (kurallar tablosu
  `retention.*`, `retention.enforce` kapalı), sorumluluk paylaşımı (KVKK m.12/2, TBK m.115), şifreleme ve ayrı yedekler, avukata
  sorular.
- `docs/yasal/AVUKATA_GECIKME_HATIRLATMA_MAKBUZ.md`: gecikme tazminatı örnek hesapları (sistemdeki hesap koduyla aynı sonucu veren
  2–3 örnek), borç hatırlatma e-postası metni, makbuz çekincesi; dönem kapsamı sorunu; avukata sorular.
- `docs/yasal/E_GENEL_KURUL_TASLAGI.md`: elektronik genel kurul taslak akışı ve metinleri; mevzuat durumu (KMK ve 7579 sayılı Kanun;
  doğrulanamayan kısım açıkça yazılır); avukata sorular.
- `docs/MAGAZA_VE_BILDIRIM_HESAPLARI_REHBERI.md`: Apple (kuruluş hesabı, D-U-N-S), Google Play (kuruluş hesabı), Firebase (telefon
  bildirimi hizmet hesabı), Google Cloud (Drive onay ekranı) adım adım; ücretler ve süreler kaynağıyla; Cenk'in "şirket adına şart mı"
  sorusunun yanıtı.
- `docs/DEMO_SENARYOSU.md`: iki haftalık canlı demo için 15 dakikalık senaryo (yönetici, sakin, süper kullanıcı akışları).
- Kod: yasal metinlerde boş KEP ve MERSİS satırı görünmüyor mu, denetle (`server/src/modules/legal_documents.js` ve ilgili şablonlar);
  görünüyorsa düzelt ve test ekle. `docs/yasal/KULLANICIDAN_GEREKENLER.md`'de Cenk'in verdiği bilgileri işaretle.

**Kabul:** belgeler yazıldı; kod değişikliği varsa testli; iddialar kaynaklı.

## 4. Dalga 2–6 (özet; her dalga başlamadan bu bölüm ayrıntılandırılır)

| Dalga | İP | Kapsam | Migration | PG portu |
| --- | --- | --- | --- | --- |
| 2 | 2A | F1 + G4: IBAN, alıcı adı, site kısa kodu, referans kodu (oluşturma, ayrıştırma, normalleştirme), sakine ödeme bilgisi, borç kartında "Öde" sayfası (kopyala düğmeleri, "Dekont yükle", "Kartla öde — Yakında…") | 054 | 55451 |
| 2 | 2B | F2: dekont bildirimi (yükleme, Android paylaş alıcısı), geçici kabul, yönetici karşılaştırma ekranı, tek ve toplu onay/iptal, onayda `postPayment` + makbuz, bildirimler, dikkat sayısı | 055 | 55452 |
| 2 | 2C | F3: banka dosyası (xlsx, CSV, MT940), sütun eşleme profili, yinelenen satır özeti, eşleme sırası, IBAN hafızası, eşleşmeyenler ekranı, daire dışı satırlar gelir/gider, yüklemeyi geri alma, dikkat sayısı | 056 | 55453 |
| 2 | 2D | F4: devir bakiyesi şablonu, sütun eşleme, önizleme, tek onay, geri alma | 057 | 55454 |
| 2 | 2E | R1: gider "rutin / beklenmedik", aylık + 3/6/12 aylık seriler, kategori kırılımı, tahmin, grafik (fl_chart), PDF/Excel | 058 | 55455 |
| 2 | 2F | G5: yönetici ana sayfası "Bu ay" (dört sayı, beş adım, koyu dikkat barı, son beş hareket) | — | — |
| 3 | 3A | F7: işletme projesi (Taslak → Tebliğ → Kesin, geçici proje süresi, planlanan–gerçekleşen) | 059 | 55461 |
| 3 | 3B | T7 + T6: ekipman, bakım planı ve kaydı, yasal kontrol hatırlatması; teklifler ve karşılaştırma; R1'e ekipman kırılımı | 060 | 55462 |
| 3 | 3C | R2: faaliyet raporu taslağı, bölüm düzenleme, PDF | 061 | 55463 |
| 3 | 3D | F8: icra dökümü PDF ve avukat Excel'i | — | — |
| 3 | 3E | G10 + G14 + R3: sade dil, kalan listelere arama ve Excel'e aktar, rapor adları | — | — |
| 4 | 4A | D1: Drive bağlantısı (OAuth `drive.file`, şifreli belirteç, yükleme/indirme vekili, önbellek ve bekleme alanı, klasör ve dosya adı kuralları T5), "Yakında…" Google projesi açılana dek | 062 | 55471 |
| 4 | 4B | T1 + T2: sayaç modülü (dosyadan içe aktarma, okuma kaydı, borç kalemi), ısı payı %70/%30 | 063 | 55472 |
| 4 | 4C | T3 + T4 + T5: fotoğrafla okuma (telefonda metin tanıma), sıradaki daire akışı, çevrimdışı kuyruk, Drive eşitleme | 064 | 55473 |
| 5 | 5A | Y1 + Y2: yönetim firması, personel, "Tüm siteler", deneme süresi, ortaklık payı dökümü | 065 | 55481 |
| 5 | 5B | C1 + S1 + S3: SMS/WhatsApp sağlayıcı arayüzü ("Yakında…"), telefon + SMS koduyla giriş, kargo bildirimi | 066 | 55482 |
| 5 | 5C | S5 + S4: rehber, yönetici onaylı komşu panosu | 067 | 55483 |
| 6 | 6A | G8 + G9: Phosphor ikonları (menü, alt çubuk, vitrin), beyaz etiket tema | 068 | 55491 |
| 6 | 6B | F6 + T8: kart ödemesi sağlayıcı arayüzü, kamera/plaka bağdaştırıcıları ("Yakında…") | 069 | 55492 |
| 6 | 6C | S6: çok dil altyapısı (Türkçe + İngilizce iskelet) | — | — |

## 5. Dalga akışı (koordinatör)

1. Taban: `main` (önceki dalga canlıda).
2. Workflow: İP başına uygulayıcı (ayrı worktree) → bağımsız inceleyici-düzeltici (aynı dalda sürdürür); para, yetki ve veri
   İP'lerinde iki inceleme turu.
3. Koordinatör: dalları tümleşik dala birleştirir; iki tarafın da değiştirdiği her dosyada `git diff -U0` ile yalnız beklenen eklerin
   kaldığını görür; `node --check`, server test ve lint, gerçek PG (tüm bölümler), `flutter analyze`, `flutter test`, temiz
   `flutter build web --release` (`build/web` silinerek).
4. Son doğrulayıcı (bir ajan): tümleşik dalda yayın engeli var mı.
5. `main`'e birleştir ve gönder; sunucu dağıtımı (prepare → rehearse → activate → verify), web dizin takası; gerekiyorsa Platform
   Ayarları değerleri (H1).
6. Faz Kontrol Listesi sayfası (`tools/deneme_listesi/platform.json` → `uret.py` → aynı adres), `docs/SAHA_KONTROL_LISTESI.md`, yol
   haritası işaretleri.

## 6. Kapsam denetimi (karar kaydı → İP)

| Karar | İP |
| --- | --- |
| G6, G7 | 1C |
| G2, G3 | 1D |
| G11, F5 | 1B |
| G12 | 1A |
| H1–H6, G15 | 1E |
| D3 | koordinatör |
| F1, G4 | 2A |
| F2 | 2B |
| F3 | 2C |
| F4 | 2D |
| R1 | 2E (+ 3B ekipman kırılımı) |
| G5 | 2F |
| F7 | 3A |
| T6, T7 | 3B |
| R2 | 3C |
| F8 | 3D |
| G10, G14, R3 | 3E |
| D1, D2, T5 | 4A |
| T1, T2 | 4B |
| T3, T4 | 4C |
| Y1, Y2 | 5A |
| C1, S1, S3 | 5B |
| S4, S5 | 5C |
| G8, G9 | 6A |
| F6, T8 | 6B |
| S6 | 6C |
| G13 | karar: yok (her İP'de IDOR testi) |
| Z1–Z8 | kapsam dışı |
