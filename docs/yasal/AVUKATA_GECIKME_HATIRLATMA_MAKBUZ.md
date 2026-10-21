# Avukata: gecikme tazminatı, borç hatırlatma ve makbuz (taslak, 2026-10-21)

Bu belge avukata gidecek. Cenk okuyup iletir. Avukat onay verene kadar gecikme tazminatı ve borç hatırlatma uygulamada KAPALI kalır;
makbuz metni "taslak" sürümdedir. Hukuki iddiaların hepsi madde numarasıyla yazıldı ve `[AVUKAT DOĞRULASIN]` ile işaretlendi.
Bu belge hukuki görüş değildir.

Kaynak belgeler: `docs/PLATFORM_FINANS_4B.md` (Ö1 makbuz, Ö2 gecikme tazminatı, Ö6 borç hatırlatma), `docs/yasal/AVUKAT_KONTROL_LISTESI.md`
madde 37, 38 ve 39. Karar: `docs/PLATFORM_YOL_HARITASI.md` "Karar kaydı (2026-10-21)" H3.

## 1. Bugün sistemde ne var?

- **Gecikme tazminatı:** Sistem hesaplar ama kendiliğinden yazmaz. Yönetici kapanmış bir ay için önizleme görür, onaylarsa tazminat
  dairenin borcuna eklenir. Varsayılan: kapalı, aylık %5, "30 gün esası", ek gün 0.
- **Borç hatırlatma e-postası:** Yönetici önizler ve gönderir. Varsayılan: kapalı. En az 50 TL ve en az 5 gün gecikme, iki
  hatırlatma arasında en az 14 gün, ödeme gelmezse art arda en çok 3 hatırlatma.
- **Makbuz:** Her tahsilatta otomatik makbuz düzenlenir (site ayarıyla kapatılabilir). Metin taslaktır (şablon sürümü 1).
- **Hukuk kapısı:** Tazminat ve hatırlatma, sistem genelindeki "hukuk onayı" bayrağı (`finance.legal_ok`) kapalıyken hiçbir sitede
  açılamaz. Uygulama bu durumda "Hukuk onayı bekleniyor" der. Bayrağı yalnız süper kullanıcı açar; bugün bunun için uygulamada düğme
  yoktur, sunucu ucu kullanılır (`PUT /admin/finance-legal-gate`).
- **Yakında:** Her dairenin iki hesabı olacak: Kiracı hesabı ve Ev sahibi hesabı (karar G12, İP-1A). Tazminat, hatırlatma ve makbuz
  hesap bazında çalışacak. Aşağıdaki örnekler tek bir hesap içindir; kural her hesapta aynıdır.

Kod: `server/src/modules/finance_late_fee_calc.js` (hesap), `finance_late_fee.js` (çalıştırma), `finance_reminders.js` ve
`finance_reminder_mail.js` (hatırlatma), `finance_receipts.js` (makbuz), `finance_settings.js` (ayarlar ve hukuk kapısı).

## 2. Kanun metinleri (resmî metinden, erişim 2026-10-21)

Aşağıdaki alıntılar mevzuat.gov.tr'deki güncel metinlerden alındı (adresler bölüm 9'da).

- **KMK (634) m.20, ikinci fıkra:** "Gider veya avans payını ödemeyen kat maliki hakkında, diğer kat maliklerinden her biri veya
  yönetici tarafından, yönetim planına, bu Kanuna ve genel hükümlere göre dava açılabilir, icra takibi yapılabilir. Gider ve avans
  payının tamamını ödemeyen kat maliki ödemede geciktiği günler için aylık yüzde beş hesabıyla gecikme tazminatı ödemekle
  yükümlüdür." Metnin dipnotuna göre oran 5711 sayılı Kanun m.9 ile "yüzde on"dan "yüzde beş"e indirildi. `[AVUKAT DOĞRULASIN]`
- **7579 sayılı Kanun (RG 22.05.2026) KMK'da yalnız m.35, m.37 ve m.70'i değiştirdi** (mevzuat.gov.tr metninin sonundaki değişiklik
  tablosu: "7579 35, 37, 70 22/5/2026"). Yani m.20 ve m.22 bu kanunla değişmedi. `[AVUKAT DOĞRULASIN]`
- **KMK m.22, birinci fıkra:** "Kat malikinin, 20 nci madde uyarınca payına düşecek gider ve avans borcundan ve gecikme tazminatından,
  bağımsız bölümlerin birinde kira akdine, oturma (sükna) hakkına veya başka bir sebebe dayanarak devamlı bir şekilde faydalananlar
  da müştereken ve müteselsilen sorumludur. Ancak, kiracının sorumluluğu ödemekle yükümlü olduğu kira miktarı ile sınırlı olup,
  yaptığı ödeme kira borcundan düşülür." `[AVUKAT DOĞRULASIN]`
- **TBK (6098) m.100:** "Borçlu, faiz veya giderleri ödemede gecikmemiş ise, kısmen yaptığı ödemeyi ana borçtan düşme hakkına
  sahiptir. Aksine anlaşma yapılamaz." `[AVUKAT DOĞRULASIN]`
- **TBK m.101:** borçlu ödeme gününde hangi borcu ödediğini bildirebilir; bildirmezse ödeme, hemen itiraz etmedikçe, "alacaklının
  makbuzda gösterdiği borç için yapılmış sayılır". `[AVUKAT DOĞRULASIN]`
- **TBK m.102:** açıklama yoksa ödeme muaccel borca sayılır; birden çok muaccel borçta "borçluya karşı ilk olarak takip edilen borç",
  takip yoksa "vadesi ilk önce gelmiş olan borç" için yapılmış olur; vadeler aynıysa "mahsup orantılı olarak" yapılır.
  `[AVUKAT DOĞRULASIN]`
- **TBK m.103:** borcu ödeyen borçlu makbuz isteyebilir. **TBK m.104:** "Faiz veya kira bedeli gibi dönemsel edimlerden biri için,
  alacaklı tarafından çekince belirtilmeksizin makbuz verilmişse, önceki dönemlere ait edimler de ifa edilmiş sayılır. Alacaklı
  anaparanın tamamı için makbuz vermişse, faizlerini de almış olduğu kabul edilir." `[AVUKAT DOĞRULASIN]`
- **6563 sayılı Kanun m.2/1-c:** ticari elektronik ileti, "elektronik posta … gibi vasıtalar kullanılarak elektronik ortamda
  gerçekleştirilen ve ticari amaçlarla gönderilen veri, ses ve görüntü içerikli iletileri" ifade eder. `[AVUKAT DOĞRULASIN]`

## 3. Sistem tazminatı nasıl hesaplıyor? (sade anlatım)

1. Yalnız **kapanmış ve bitmiş** bir ay hesaplanır. Yönetici önizler, onaylar. Aylar sırayla hesaplanır; aynı ay için ikinci kez
   tazminat yazılamaz. Yanlışsa en son yazılan ayın işlemi bütünüyle iptal edilip yeniden hesaplanır; tek bir dairenin tazminat kalemi
   ayrıca ters kayıtla iptal edilebilir.
2. Gecikme **vade gününü izleyen gün** başlar. **Ödeme günü gecikme sayılmaz.** Sonradan kaydedilen bir borç, kayıt gününden önce
   gecikmeye girmez.
3. İstenirse vadeye **ek gün** eklenir (0-90 gün; varsayılan 0).
4. Ödemeler **vadesi en eski borçtan** başlayarak düşülür (TBK m.102'ye dayanarak) `[AVUKAT DOĞRULASIN]`.
5. Her gün için "gecikmedeki tutar" bulunur. Daha önce yazılmış **tazminat kalemleri bu tutara girmez** (tazminata tazminat işlemez).
   Ama ödeme düşülürken tazminat kalemleri de sıraya girer.
6. Tazminat = (her gün gecikmedeki tutarların toplamı) × aylık oran ÷ gün esası. Gün esası "30 gün" ya da "ayın gerçek gün
   sayısı"dır. Sonuç kuruşa yuvarlanır (yarım kuruş yukarı).
7. Aylık oran en çok **%5**tir. Sistem bunun üstüne izin vermez. Yönetici daha düşük oran seçebilir, bir daireyi o ay için muaf
   tutabilir.

## 4. Örnek hesaplar (sistemin koduyla doğrulandı)

Aşağıdaki her örnek, 2026-10-21'de sistemin kendi hesap koduyla (`lateFeeForApartment`) ve ondan bağımsız gün gün hesaplayan denetim
koduyla (`lateFeeBruteForce`) çalıştırıldı; ikisi de buradaki elle hesapla **kuruşu kuruşuna aynı** sonucu verdi. Oran her örnekte
aylık %5'tir. "TL·gün", gecikmedeki tutarın gün sayısıyla çarpımıdır.

### Örnek 1: tek borç, hiç ödeme yok

Eylül 2026. Aidat 1.000,00 TL, vade 05.09.2026. Ay içinde ödeme yok. Gün esası 30, ek gün 0.

| Aralık | Gün | Gecikmedeki tutar | Tutar × gün |
| --- | --- | --- | --- |
| 06.09 - 30.09 | 25 | 1.000,00 TL | 25.000,00 TL·gün |

Tazminat = 25.000,00 × %5 ÷ 30 = 41,666… → **41,67 TL**.

### Örnek 2: kısmi ödeme, gerçek gün esası

Ekim 2026 (31 gün). Aidat 1.200,00 TL, vade 05.10.2026. Sakin 20.10.2026'da 700,00 TL öder. Gün esası: ayın gerçek gün sayısı.

| Aralık | Gün | Gecikmedeki tutar | Tutar × gün |
| --- | --- | --- | --- |
| 06.10 - 19.10 | 14 | 1.200,00 TL | 16.800,00 |
| 20.10 - 31.10 | 12 | 500,00 TL (ödeme günü sayılmaz) | 6.000,00 |
| Toplam | | | 22.800,00 TL·gün |

Tazminat = 22.800,00 × %5 ÷ 31 = 36,774… → **36,77 TL**.

### Örnek 3: eski borç, ek gün ve "tazminata tazminat yok"

Ekim 2026. Ek gün 5, gün esası 30. Dairede üç kalem var: Eylül aidatı 1.000,00 TL (vade 05.09; ek günle gecikme 11.09'da başlar),
Eylül için daha önce yazılmış 41,67 TL tazminat (02.10'da yazıldı), Ekim aidatı 1.000,00 TL (vade 05.10; gecikme 11.10'da başlar).
Sakin 15.10'da 500,00 TL öder. Ödeme en eski vadeden, yani Eylül aidatından düşülür. (Eylül tazminatı, Örnek 1'deki gibi ek gün 0
iken hesaplanmıştır: oran, gün esası ve ek gün değişince yalnız sonraki ayların hesabı etkilenir. Tazminat kalemi tabana girmediği
için tutarı bu örneğin sonucunu değiştirmez.)

| Aralık | Gün | Gecikmedeki tutar | Tutar × gün |
| --- | --- | --- | --- |
| 01.10 - 10.10 | 10 | 1.000,00 TL (Eylül) | 10.000,00 |
| 11.10 - 14.10 | 4 | 2.000,00 TL (Eylül + Ekim) | 8.000,00 |
| 15.10 - 31.10 | 17 | 1.500,00 TL (Eylül'den kalan 500 + Ekim 1.000) | 25.500,00 |
| Toplam | | 41,67 TL'lik tazminat kalemi hiçbir gün tutara girmez | 43.500,00 TL·gün |

Tazminat = 43.500,00 × %5 ÷ 30 = **72,50 TL**.

### Örnek 4: dönem kapsamı sorunu (yeni kiracı, eski borç)

Eski kiracı Eylül aidatını (1.000,00 TL, vade 05.09) ödemeden 30.09'da taşınır. Yeni kiracı 01.10'da gelir ve Ekim aidatını
(1.000,00 TL, vade 05.10) **05.10'da tam ve zamanında** öder. Ekim 2026, gün esası 30, ek gün 0.

Sistem ödemeyi en eski vadeden düşer: yeni kiracının ödemesi **eski kiracının Eylül borcunu** kapatır, Ekim aidatı açık kalır.

| Aralık | Gün | Gecikmedeki tutar | Tutar × gün |
| --- | --- | --- | --- |
| 01.10 - 04.10 | 4 | 1.000,00 TL (Eylül) | 4.000,00 |
| 05.10 | 1 | 0 (Eylül kapandı; Ekim'in vadesi bugün, gecikme değil) | 0 |
| 06.10 - 31.10 | 26 | 1.000,00 TL (Ekim) | 26.000,00 |
| Toplam | | | 30.000,00 TL·gün |

Tazminat = 30.000,00 × %5 ÷ 30 = **50,00 TL**. Bu tazminat, Ekim aidatını zamanında ödeyen yeni kiracının görebileceği bir kalem
olarak yazılır. Ayrıntı bölüm 5'te.

### Örnek 5: gün esası farkı (borç ayın tamamında gecikmede, 1.000,00 TL)

| Ay | Gün | "30 gün" esası (varsayılan) | "Gerçek gün" esası |
| --- | --- | --- | --- |
| Ekim 2026 | 31 | 51,67 TL (ayda %5,17) | 50,00 TL (ayda %5,00) |
| Şubat 2027 | 28 | 46,67 TL (ayda %4,67) | 50,00 TL (ayda %5,00) |

"30 gün" esasında 31 günlük aylarda tazminat, bir aylık borcun %5'ini biraz aşar. Soru 1.

## 5. Dönem kapsamı sorunu

Bugün kod şöyle çalışıyor (koddan okundu, 2026-10-21):

- **Tazminat** dairenin **bütün** defterinden hesaplanır; kimin oturduğu, kimin ne zaman taşındığı hesaba girmez
  (`finance_late_fee.js`, `loadLedgerRows`).
- **Hatırlatma** dairenin bütün gecikmiş borcu üzerinden karar verir ve dairenin **bugünkü** kişilerine gider
  (`finance_reminders.js`, `loadCandidateApartments` ve `loadRecipientRows`).
- Oysa sakinin "Borcum" ekranı yalnız **taşınma ayından itibaren** gösterir (`docs/PLATFORM_FINANS.md` "Sakin kapsamı").

Sonuç: yeni sakin, kendi ekranında hiç görmediği eski bir borç yüzünden hatırlatma e-postası alabilir; Örnek 4'teki gibi zamanında
ödediği halde tazminat görebilir. İki hesap (G12) gelince de sorun kiracı hesabında sürer: kiracı hesabı daireye bağlıdır, kiracı
değişse de aynı hesap kullanılır.

Seçenekler:

- **(A) Kişi kapsamı (önerimiz):** tazminat ve hatırlatma, kişinin taşınma tarihinden önceki borçları saymaz; ödeme önce kişinin kendi
  döneminin borçlarına düşülür (TBK m.101'deki bildirim gibi) `[AVUKAT DOĞRULASIN]`.
- **(B) Devir:** kiracı ayrılınca kiracı hesabındaki açık borç ev sahibi hesabına aktarılır (asıl borçlu kat malikidir: KMK m.20;
  kiracının sorumluluğu kira miktarıyla sınırlıdır: KMK m.22) `[AVUKAT DOĞRULASIN]`.
- **(C) Bugünkü gibi:** daire (hesap) bazında; yönetici gerektiğinde daireyi muaf tutar.

Hangi seçenek seçilirse seçilsin, tazminat ve hatırlatma açılmadan önce kodda uygulanacaktır (yol haritası bölüm 1, P0 maddesi).

## 6. Borç hatırlatma e-postası (metin sistemin şablonundan alındı)

Metin, 2026-10-21'de sistemin kendi şablon koduyla (`buildFinanceReminderEmail`) üretildi. Site adı, daire ve tutarlar örnektir.

**A) Nazik ton; alıcının hesabı var ve e-postası doğrulanmış (tutar yazılır):**

```text
Konu: [Örnek Sitesi] Ödeme hatırlatması

Merhaba,

Örnek Sitesi için A Blok 12 dairesine ait vadesi geçmiş ödeme görünüyor.

Vadesi geçmiş tutar: 1.250,00 ₺ (en eski vade: 05.09.2026).

Ödemeyi yaptıysanız bu iletiyi dikkate almayın; kayıtlara yansıması birkaç gün sürebilir. Ayrıntıları uygulamadaki "Borcum" bölümünden görebilir ya da site yönetimiyle iletişime geçebilirsiniz.

--
Bu ileti Örnek Sitesi site yönetimi tarafından gönderildi. Bu ileti bir tanıtım iletisi değildir; site yönetiminin aidat/avans kayıtlarına ilişkin bilgilendirmesidir. Bu e-postaları durdurmak için uygulamadaki Bildirim Tercihleri'ni kullanabilir veya şu bağlantıdan çıkabilirsiniz (site duyuru ve borç hatırlatma e-postaları durdurulur): <abonelikten çıkma bağlantısı>
```

**B) Resmî ton; hesabı olmayan kişi (tutar yazılmaz), iki daire, yönetici notu var:**

```text
Konu: [Örnek Sitesi] Ödeme hatırlatması

Sayın site sakini,

Örnek Sitesi için A Blok 12, B Blok 3 dairelerine ait vadesi geçmiş ödeme görünüyor.

Güncel tutar için uygulamadaki "Borcum" bölümüne bakabilir veya site yönetimine başvurabilirsiniz.

Ödemeyi yaptıysanız bu iletiyi dikkate almayın; kayıtlara yansıması birkaç gün sürebilir. Ayrıntıları uygulamadaki "Borcum" bölümünden görebilir ya da site yönetimiyle iletişime geçebilirsiniz.

Yönetim notu: Banka hesabımız değişmedi; açıklamaya daire numaranızı yazınız.

--
Bu ileti Örnek Sitesi site yönetimi tarafından gönderildi. Bu ileti bir tanıtım iletisi değildir; site yönetiminin aidat/avans kayıtlarına ilişkin bilgilendirmesidir. Bu e-postaları almak istemiyorsanız şu bağlantıdan çıkabilirsiniz (site duyuru ve borç hatırlatma e-postaları durdurulur): <abonelikten çıkma bağlantısı>
```

Şablonun kuralları:

- Konu satırında tutar, ad ve daire yoktur. Selamlama ada hitap etmez.
- Tutar yalnız **hesabı olan ve e-postası doğrulanmış** kişiye yazılır; yönetimin elle girdiği adreslere tutarsız metin gider
  (yanlış adrese borç bilgisi gitmesin diye).
- Tehdit, icra, dava, ihtar dili ve tanıtım içeriği yoktur. Yönetici en çok 300 karakterlik düz metin not ekleyebilir; notta bağlantı,
  alan adı ya da e-posta adresi olamaz.
- Her iletide tek tıkla abonelikten çıkma bağlantısı bulunur (sunucunun genel adresinden üretilir). Bu bağlantı ortak listeye yazar: o
  adrese **site duyuru e-postaları da** gitmez. Uygulamada ayrıca "Borç hatırlatma e-postaları" anahtarı vardır (Bildirim Tercihleri).

## 7. Makbuz çekincesi (metin sistemden alındı)

Makbuzda sabit üç cümle var (şablon sürümü 1, taslak; `finance_receipts.js`, `RECEIPT_TEMPLATE`):

1. Mahsup: "Tahsil edilen tutar, kayıtlardaki vadesi en eski borçtan başlayarak mahsup edilir."
2. Çekince: "Bu makbuz yalnızca yukarıda belirtilen tutarın tahsil edildiğini gösterir; önceki dönemlere ait borçlara, gecikme
   tazminatına ve diğer hak ve alacaklara ilişkin haklar saklıdır."
3. Uyarı: "Bu belge noter onaylı karar defteri/yasal defterlerin yerine geçmez."

Amaç: TBK m.104'teki karinenin (çekincesiz makbuz önceki dönemlerin ödendiğini gösterir) site yönetimi aleyhine işlememesi; TBK m.101
gereği ödemenin hangi borca sayıldığının makbuzda görünmesi `[AVUKAT DOĞRULASIN]`.

## 8. Avukata sorular

1. **Gün esası.** "Aylık yüzde beş hesabıyla" (KMK m.20/2) için "30 gün" mü, "ayın gerçek gün sayısı" mı doğru? 30 gün esası 31 günlük
   ayda aylık %5'i aşıyor (Örnek 5). Varsayılanı değiştirelim mi? `[AVUKAT DOĞRULASIN]`
2. **Gün sayımı.** Gecikmenin vade gününü izleyen gün başlaması, ödeme gününün sayılmaması ve isteğe bağlı ek gün (0-90) doğru mu?
3. **Kapsam.** Tazminat yalnız "gider ve avans payı" için mi? Ek borçlar (demirbaş, büyük onarım, ceza gibi) için de istenebilir mi?
   Sistem borç türüne göre ayırmıyor; yönetici daireyi muaf tutabiliyor.
4. **Tazminata tazminat.** Tazminat kalemlerine yeniden tazminat işletilmemesi (Örnek 3) doğru mu?
5. **Mahsup sırası ve TBK m.100.** Kısmi ödeme vadesi en eski kaleme sayılıyor. Ödenmemiş bir tazminat kalemi varken TBK m.100 gereği
   ödeme önce tazminata mı sayılmalı? Gecikme tazminatı bu maddedeki "faiz" kapsamında mı? `[AVUKAT DOĞRULASIN]`
6. **TBK m.102.** Kanun "ilk olarak takip edilen borç" önceliğinden ve aynı vadede "orantılı" mahsuptan söz ediyor. Sistem icra
   takibini bilmiyor ve aynı vadede kayıt sırasını kullanıyor (toplam değişmez, kalem kırılımı değişir). Bu fark kabul edilebilir mi?
7. **TBK m.101.** Ödeyen "şu borcu ödüyorum" derse ne yapmalıyız? Tahsilat ekranında bu seçim yok. Örnek 4 için bu bildirim belirleyici mi?
8. **Dönem kapsamı.** Yeni kiracının ödemesi eski kiracının borcuna sayılabilir mi? Yeni kiracı eski borçtan ve onun tazminatından
   sorumlu mu (KMK m.22/1)? Bölüm 5'teki seçeneklerden hangisi? Önerimiz (A).
9. **İki hesap.** Aidat kiracı hesabına yazılıyorsa tazminat da kiracı hesabına mı? Kiracı ödemezse aynı tutar ev sahibinden istenebilir
   mi? Kiracı ayrılınca açık borç ev sahibi hesabına devredilebilir mi (seçenek B)?
10. **Kurul kararı.** Tazminat uygulamak ve borç hatırlatma göndermek için kat malikleri kurulu kararı ya da yönetim planı hükmü gerekir
    mi? Yönetim planı oranı düşürebilir ya da yükseltebilir mi?
11. **Usul.** Tazminatın otomatik değil, yöneticinin önizleyip onayladığı aylık bir işlem olması ve sakine gün gün kırılımın
    gösterilmesi yeterli mi? Tazminat yazılmadan önce sakine bildirim gerekir mi?
12. **6563.** Borç hatırlatma e-postası "ticari elektronik ileti" (m.2/1-c) değil, bilgilendirme mi? Bu durumda önceden onay ve İYS
    kaydı gerekmez mi? `[AVUKAT DOĞRULASIN]`
13. **KVKK.** Tutarın yalnız doğrulanmış hesap e-postasına yazılması yeterli mi? Hesabı olmayan kişiye (yönetimin girdiği adres)
    hatırlatma göndermenin dayanağı ne? Gönderen site yönetimi (veri sorumlusu), Güde veri işleyen; doğru mu?
14. **Çıkış hakkı.** Abonelikten çıkma bağlantısının duyuru e-postalarını da durdurması kabul edilebilir mi?
15. **Sınırlar.** En az 50 TL, en az 5 gün gecikme, 14 gün aralık, art arda en çok 3 hatırlatma ölçülü mü?
16. **Makbuz metni.** Bölüm 7'deki üç cümle TBK m.101 ve m.104 açısından yeterli mi? Önerdiğiniz metin nedir?
17. **Makbuzun niteliği.** Belgenin adı "makbuz" olabilir mi? Vergi mevzuatı açısından site yönetiminin düzenlediği bu belge başka bir
    belge türü (ör. elektronik belge) gerektirir mi? (Bu çalışmada araştırılmadı: **doğrulanamadı**.)
18. **Saklama.** Hatırlatma ve makbuz kayıtlarının saklama süresi: `docs/yasal/SAKLAMA_SURELERI_TASLAGI.md`.

## 9. Kaynaklar (hepsine 2026-10-21'de erişildi)

- Kat Mülkiyeti Kanunu (634), güncel metin, 7579 değişiklikleri işlenmiş: <https://mevzuat.gov.tr/mevzuatmetin/1.5.634.pdf>
  (m.20, m.22 ve sondaki değişiklik tablosu).
- Türk Borçlar Kanunu (6098): <https://mevzuat.gov.tr/mevzuatmetin/1.5.6098.pdf> (m.100-104).
- Elektronik Ticaretin Düzenlenmesi Hakkında Kanun (6563): <https://mevzuat.gov.tr/mevzuatmetin/1.5.6563.pdf> (m.2/1-c).
- Örnek hesaplar: sistemin kodu (`server/src/modules/finance_late_fee_calc.js`), 2026-10-21 tarihli çalıştırma; betik depoda değil
  (geliştirici bilgisayarında, scratch klasörü).

## 10. Onaydan sonra yapılacaklar (bizde)

1. Avukatın yanıtlarına göre metinler ve varsayılanlar güncellenir (gün esası, sınırlar, makbuz cümleleri).
2. Dönem kapsamı kuralı koda yazılır ve test edilir.
3. Makbuz şablon sürümü yükseltilir (`template_version`).
4. Süper kullanıcı hukuk onayı bayrağını açar. Site yöneticileri kendi Finans Ayarları'ndan tazminatı (başlangıç ayıyla) ve
   hatırlatmayı açar.
