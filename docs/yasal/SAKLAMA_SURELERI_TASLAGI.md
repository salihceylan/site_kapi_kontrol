# Saklama süreleri taslağı (avukata, 2026-10-21)

Bu belge avukata gidecek. Cenk okuyup iletir. Süreler ekibin önerisidir (karar H2); avukat onaylayana kadar **otomatik silme kapalı**
kalır. Hukuki iddiaların hepsi madde numarasıyla yazıldı ve `[AVUKAT DOĞRULASIN]` ile işaretlendi. Bu belge hukuki görüş değildir.

Karar: `docs/PLATFORM_YOL_HARITASI.md` "Karar kaydı (2026-10-21)" H2. İlgili: `docs/yasal/AVUKAT_KONTROL_LISTESI.md` madde 3, 4, 15,
22, 36-39; `docs/yasal/KULLANICIDAN_GEREKENLER.md` madde 10, 11, 21.

## 1. Önerilen süreler

"Bugün" sütunu kodun bugünkü davranışıdır (2026-10-21'de koddan okundu). "Kural" sütunu, süreyi koddan değil kurallar tablosundan
okutacak anahtardır (bölüm 3).

| Kayıt | Önerilen süre | Kural (varsayılan, gün) | Bugün sistemde |
| --- | --- | --- | --- |
| Mali kayıtlar: borç, tahsilat, makbuz, gider ve gider belgesi, banka dosyası, dekont | 10 yıl | `retention.finance_days` (3650) | Hiç silinmez. Defter yalnız eklemelidir; site silinince birlikte silinir. Banka dosyası ve dekont henüz yok (dalga 2). |
| Taşınan kişinin iletişim bilgileri (telefon, e-posta), açık borcu yoksa | taşındıktan 1 yıl sonra silinir | `retention.contact_after_moveout_days` (365) | Silinmez; kişi kaydı ve ilişki geçmişi kalır. |
| Kapı geçiş kayıtları | 1 yıl | `retention.door_logs_days` (365) | **30 günde kendiliğinden silinir** (`server/src/services/maintenance_service.js`). Gizlilik Politikası bölüm 7 de "30 gün" diyor. Öneri bugünkünden UZUN: soru 2. |
| Ziyaretçi ve kargo kayıtları | 1 yıl | `retention.visitor_logs_days` (365) | Silinmez (yalnız site silinince). |
| İş takibi fotoğrafları | talep kapandıktan 2 yıl sonra | `retention.work_photos_after_close_days` (730) | Kendiliğinden silinmez; yalnız elle silinir. |
| Duyurular | 5 yıl | `retention.announcements_days` (1825) | Yayımlanmış duyuru silinmez (taslak ve zamanlanmış silinebilir). |
| Denetim kaydı (kim, ne zaman, ne yaptı) | 5 yıl | `retention.audit_days` (1825) | Silinmez (temizlik işi yok); uygulamada düzenleme yolu yok (veritabanında ayrıca değişmezlik kilidi yok). |
| Karar defteri | süresiz | `retention.decision_book_days` (boş = süresiz) | Kesinleşmiş karar silinmez ve değiştirilemez (veritabanı tetikleyicisi); taslak karar silinebilir. Site silinince birlikte silinir. |
| Otomatik silme anahtarı | avukat onayına kadar kapalı | `retention.enforce` (kapalı) | Yukarıdaki yeni süreler için silme işi yok. |

Bugün zaten kendiliğinden silinen kısa ömürlü kayıtlar (değişmiyor; kaynak: Gizlilik Politikası bölüm 7 ve kod): kapı cihazlarının
bağlantı kayıtları 30 gün; süresi dolmuş karekod belirteçleri 1 gün sonra; e-posta doğrulama ve doğrulanmamış bekleyen kayıtlar 2 gün;
duyuru e-postası adres özeti 3 gün, borç hatırlatma adres özeti 8 gün; telefon bildirimi kuyruğu 14 gün, kullanılmayan cihaz kaydı 60 gün;
yönetimin sildiği belge 30 gün sonra; uygulama hata raporları 90 gün.

## 2. Dayanaklar (resmî metin, erişim 2026-10-21)

- **KVKK (6698) m.4/2-d:** kişisel veriler "İlgili mevzuatta öngörülen veya işlendikleri amaç için gerekli olan süre kadar muhafaza
  edilme" ilkesine uyularak işlenir. **m.7/1:** işlenmesini gerektiren sebepler ortadan kalkınca veriler "resen veya ilgili kişinin
  talebi üzerine veri sorumlusu tarafından silinir, yok edilir veya anonim hâle getirilir." `[AVUKAT DOĞRULASIN]`
- **KVKK m.5/2:** açık rıza aranmayan hâller arasında (ç) "Veri sorumlusunun hukuki yükümlülüğünü yerine getirebilmesi için zorunlu
  olması", (e) "Bir hakkın tesisi, kullanılması veya korunması için veri işlemenin zorunlu olması", (f) meşru menfaat. Mali kayıtları
  uzun saklamanın dayanağı olarak (ç) ve (e) düşünüldü. `[AVUKAT DOĞRULASIN]`
- **Silme, Yok Etme veya Anonim Hale Getirme Yönetmeliği (RG 28.10.2017/30224):** saklama ve imha politikası VERBİS'e kayıt
  yükümlülerine zorunludur (m.5/1); silme işlemleri kayıt altına alınır ve kayıtlar "en az üç yıl süreyle saklanır" (m.7/3); periyodik
  imha aralığı "her halde altı ayı geçemez" (m.11/2); politika hazırlama yükümlülüğü olmayan veri sorumlusu silme yükümlülüğünün
  doğduğu tarihi izleyen üç ay içinde siler (m.11/3); ilgili kişinin talebi en geç otuz günde sonuçlandırılır (m.12). (Resmî Gazete'deki
  asıl metinden okundu. Tek değişiklik RG 28.04.2019/30758 ile yapıldı ve yalnız m.4/1-e, m.7/4 ve m.12/1'deki madde atfını değiştirdi;
  buradaki hükümlere dokunmadı.) `[AVUKAT DOĞRULASIN]`
- **TTK (6102) m.82:** "Her tacir" ticari defterlerini ve kayıtların dayandığı belgeleri saklamakla yükümlüdür; bu belgeler "on yıl
  saklanır" (m.82/5); süre, kaydın yapıldığı takvim yılının bitişiyle başlar (m.82/6). Bu kural Güde (tacir) için kesindir; site
  yönetimine uygulanıp uygulanmadığı soru 1. `[AVUKAT DOĞRULASIN]`
- **VUK (213) m.253:** "Bu Kanuna göre defter tutmak mecburiyetinde olanlar" defter ve belgeleri, ilgili yılı izleyen takvim yılından
  başlayarak "beş yıl süre ile muhafaza etmeye mecburdurlar." Site yönetiminin bu kapsamda olup olmadığı soru 1. `[AVUKAT DOĞRULASIN]`
- **KMK (634) m.36:** yönetici, kurul kararlarını ve bütün giderleri karar defterine yazmak, "bu defteri ve giderlerin belgeleriyle diğer
  bütün belgeleri bir dosyada saklamaya mecburdur"; defter her yıl bitiminden başlayarak bir ay içinde notere kapattırılır. Maddede
  **süre yazmıyor** (mevzuat.gov.tr metninde KMK'da belge saklama süresi bulunamadı). `[AVUKAT DOĞRULASIN]`
- **TBK (6098) m.146:** kanunda aksi yoksa "her alacak on yıllık zamanaşımına tabidir." **m.147/1:** "Kira bedelleri, anapara faizleri
  ve ücret gibi diğer dönemsel edimler" için beş yıl. Aidat alacağının hangisine girdiği tartışmalı olduğu için uzun olan (10 yıl)
  önerildi. `[AVUKAT DOĞRULASIN]`

## 3. Otomatik silme nasıl çalışacak?

1. **Kurallar tablosu.** Süreler koddan değil, kurallar tablosundan okunur (karar G11; İP-1B, `server/src/modules/platform_rules.js`,
   `getRule`). Sırası: site değeri, yoksa platform değeri, yoksa varsayılan. Sonuç her zaman tanımlı alt ve üst sınır içine kırpılır.
   Anahtarlar bölüm 1'deki tablodadır. (Bu belge yazılırken İP-1B henüz birleştirilmemişti; anahtar adları ana planın 2.2 sözleşmesinden
   alındı.)
2. **Kapalı başlar.** `retention.enforce` kapalıyken hiçbir yeni silme işi çalışmaz. Avukat onayından sonra süper kullanıcı açar.
3. **Silme işi (yapılacak).** Günde bir kez çalışan bakım işi süresi dolan kayıtları küçük parçalar hâlinde siler ya da anonimleştirir.
   Günde bir çalışması, yönetmelikteki "en çok altı ayda bir" periyodik imha sınırını (m.11/2) rahatça karşılar. `[AVUKAT DOĞRULASIN]`
4. **Kayıt.** Her silme turu denetim kaydına yalnız sayıyla yazılır (hangi tür, kaç kayıt; ad ya da içerik yazılmaz). Bu kayıtlar en az
   3 yıl kalır (yönetmelik m.7/3). `[AVUKAT DOĞRULASIN]`
5. **Önce önizleme.** Anahtar açılmadan önce yöneticiye "şu tarihte şu kadar kayıt silinecek" bilgisi gösterilir (yapılacak).
6. **Mali kayıtların özel durumu.** Defter bugün değiştirilemez ve silinemez (veritabanı tetikleyicisi). 10 yıl dolunca silme için
   denetimli, ayrı bir yol yazılması gerekir. Silme mi anonimleştirme mi: soru 7.
7. **Yedekler.** Silinen kayıt, yedek döngüsü dolunca yedeklerden de düşer: en geç yaklaşık 7 ay (Gizlilik Politikası bölüm 7).

## 4. Sorumluluk paylaşımı

- **Roller.** Site kayıtları için veri sorumlusu site yönetimidir; Güde veri işleyendir (KVKK m.3: veri işleyen "veri sorumlusunun
  verdiği yetkiye dayanarak onun adına kişisel verileri işleyen" kişidir). Hesap ve platform verileri için Güde veri sorumlusudur.
  `[AVUKAT DOĞRULASIN]`
- **Tam muafiyet yazılamaz.** KVKK m.12/2: "Veri sorumlusu, kişisel verilerin kendi adına başka bir gerçek veya tüzel kişi tarafından
  işlenmesi hâlinde, birinci fıkrada belirtilen tedbirlerin alınması hususunda bu kişilerle birlikte müştereken sorumludur." TBK m.115/1:
  "Borçlunun ağır kusurundan sorumlu olmayacağına ilişkin önceden yapılan anlaşma kesin olarak hükümsüzdür." Bu yüzden "veri çalınırsa
  firmamız sorumlu olmasın" cümlesi olduğu gibi yazılamaz. `[AVUKAT DOĞRULASIN]`
- **Yazılabilecek olan (öneri).** Veri işleme sözleşmesinde (`server/legal/dpa.md`) görevler ayrılır: Güde teknik tedbirleri (şifreli
  yedek, erişim kaydı, güncelleme) üstlenir; site yönetimi kullanıcı yetkilerini, kendi Drive hesabını ve hesap parolalarını yönetir.
  Güde'nin sorumluluğu kendi kusuruyla ve sözleşmedeki üst sınırla sınırlanır; kast ve ağır kusur bu sınırın dışındadır. Hafif kusur
  için sınırlamanın geçerliliği: soru 9. `[AVUKAT DOĞRULASIN]`

## 5. Şifreleme ve ayrı yedekler

Bugün (kaynak: `docs/OPERASYON_YEDEK_IZLEME.md`, 2026-10-16; dış kopya için yol haritası D3, 2026-10-21):

- Veritabanı her gün 03:30'da yedeklenir. En son günlük döküm sunucuda **şifresiz** durur (yalnız sahibi okuyabilir, izin 600); eski
  günlükler, haftalık ve aylık kopyalar **şifrelidir** (AES-256).
- Yüklenen belgeler ve iş takibi fotoğrafları veritabanından **ayrı**, her biri kendi şifreli arşivindedir. Yapılandırma da ayrı ve
  şifrelidir. Yani karar H2'deki "fotoğraf ayrı, kayıtlar ayrı" bugün de böyle.
- Tutma: 7 günlük, 4 haftalık, 6 aylık kopya; dış kopyalar en çok yaklaşık 210 gün.
- Dış kopya: şifreli günlük yedekler her gün geliştirici bilgisayarına (Türkiye) çekiliyor (yol haritası D3). İşletme belgesine göre
  şifre anahtarı yedeklerle aynı yerde ve eşitlenen (OneDrive gibi) bir klasörde tutulmamalıdır; bunun uygulandığı bu çalışmada
  görülmedi.
- Drive bağlanınca (dalga 4, D1): dosyalar sitenin Google Drive'ında durur. Google'ın Workspace şifreleme incelemesine göre (Haziran
  2021) Workspace verisi bekleyen hâlde ve tesisler arası aktarımda varsayılan olarak şifrelenir, anahtarları Google yönetir. İnceleme
  kendi ifadesiyle hem kişisel (ücretsiz) hem kurumsal hesap verisi için geçerlidir ("applies to both consumer and enterprise data");
  bilgilerin Haziran 2021 itibarıyla doğru olduğunu yazar, bugünkü durum ayrıca doğrulanmadı. Uygulama ile sunucu arası aktarım TLS ile
  şifrelidir.
- Dosya içeriği ayrıca (bizim anahtarımızla) şifrelenmez (karar H2): anahtar kaybolursa dosyalar açılamaz, Drive'da önizleme ve arama
  çalışmaz; anahtarı Güde tutarsa "Güde'nin erişimi yok" savunması da zayıflar.

## 6. Avukata sorular

1. **Mali kayıtlar.** 10 yıl uygun mu? Dayanak hangisi: TTK m.82 (tacir; site yönetimi tacir değil), VUK m.253 (defter tutma
   yükümlüsü; site yönetimi bu kapsamda mı?), TBK m.146-147 (zamanaşımı) ya da KMK m.36 (süre yok)?
2. **Kapı geçiş kayıtları.** Bugün 30 gün; öneri 1 yıl. Daha uzun saklama ölçülülük ilkesine (KVKK m.4/2-ç) aykırı mı? 1 yıl seçilirse
   Gizlilik Politikası ve aydınlatma metni değişir. Hangisini önerirsiniz?
3. **Ziyaretçi ve kargo kayıtları.** 1 yıl uygun mu, dayanağı ne?
4. **Taşınan kişi.** İletişim bilgileri 1 yıl sonra silinsin; açık borç varsa borç bitene kadar kalsın; ad (borcun kime ait olduğunu
   göstermek için) mali kayıtla birlikte 10 yıl kalsın. Uygun mu?
5. **İş takibi fotoğrafları.** Talep kapandıktan 2 yıl sonra silinmesi uygun mu?
6. **Duyurular, denetim kaydı, karar defteri.** 5 yıl, 5 yıl, süresiz uygun mu? Karar defterinin süresiz tutulmasının dayanağı ne
   (KMK m.32 ve m.36 süre vermiyor)?
7. **Silme mi anonimleştirme mi?** Süresi dolan mali kayıtlar tamamen mi silinsin, yoksa ad ve iletişim bilgisi çıkarılıp tutarlar
   istatistik için kalsın mı?
8. **Site değiştirebilir mi?** Site yönetimi bu süreleri kendi sitesi için uzatabilsin ya da kısaltabilsin mi? Kısaltmanın yasal alt
   sınırı var mı?
9. **Sorumluluk.** "Veri çalınırsa firmamız sorumlu olmasın" isteği yerine yazılabilecek en geniş ifade nedir (KVKK m.12/2, TBK m.115)?
   Hafif kusur için sorumluluk sınırı geçerli olur mu?
10. **Drive.** Dosyalar sitenin kendi Google Drive'ında (yurt dışı sunucu). KVKK m.9 yurt dışı aktarımı için hangi yol? Site kişisel
    Gmail hesabı kullanabilir mi, yoksa Google Workspace mı şart? (Ayrıntı: `docs/PLATFORM_DRIVE_DEPOLAMA.md` bölüm 2.)
11. **Yedekler.** Şifreli dış kopyanın geliştirici bilgisayarında (Türkiye) tutulması yeterli mi? Silinen verinin yedeklerden en geç
    yaklaşık 7 ayda düşmesi kabul edilebilir mi? En son günlük dökümün sunucuda şifresiz (yalnız sahibi okuyabilir) durması sorun mu?
12. **Politika.** Saklama ve imha politikası yalnız VERBİS'e kayıt YÜKÜMLÜSÜ olan veri sorumlusuna zorunludur (yönetmelik m.5/1;
    belirleyici olan fiilen kayıtlı olmak değil, kayıt yükümlülüğüdür). Yükümlü olmayan veri sorumlusu süresi dolan veriyi en geç üç
    ayda siler (m.11/3). Güde ve siteler kayıt yükümlüsü mü? Değilse de politika yazılsın mı; site yönetimleri için örnek politika
    hazırlayalım mı?
13. **Silme kaydı.** Silme turlarının denetim kaydında yalnız sayıyla tutulması (yönetmelik m.7/3) yeterli mi?

## 7. Kaynaklar (hepsine 2026-10-21'de erişildi)

- KVKK (6698): <https://mevzuat.gov.tr/mevzuatmetin/1.5.6698.pdf> (m.3, m.4, m.5, m.7, m.12).
- Silme, Yok Etme veya Anonim Hale Getirme Yönetmeliği, Resmî Gazete asıl metni (28.10.2017/30224):
  <https://www.resmigazete.gov.tr/eskiler/2017/10/20171028-10.htm>; değişiklik yönetmeliği (28.04.2019/30758):
  <https://www.resmigazete.gov.tr/eskiler/2019/04/20190428-1.htm>. Lexpera'daki birleştirilmiş metin (ikincil):
  <https://www.lexpera.com.tr/mevzuat/yonetmelikler/kisisel-verilerin-silinmesi-yok-edilmesi-veya-anonim-hale-getirilmesi-hakkinda-yonetmelik>.
- TTK (6102): <https://mevzuat.gov.tr/mevzuatmetin/1.5.6102.pdf> (m.82).
- VUK (213): <https://mevzuat.gov.tr/mevzuatmetin/1.4.213.pdf> (m.253).
- KMK (634): <https://mevzuat.gov.tr/mevzuatmetin/1.5.634.pdf> (m.36).
- TBK (6098): <https://mevzuat.gov.tr/mevzuatmetin/1.5.6098.pdf> (m.115, m.146, m.147).
- Google Workspace Encryption Whitepaper (Haziran 2021): <https://services.google.com/fh/files/misc/google-workspace-encryption-wp.pdf>.
- Kodun bugünkü davranışı: `server/src/services/maintenance_service.js`, `server/legal/privacy.md` bölüm 7, `docs/OPERASYON_YEDEK_IZLEME.md`.
