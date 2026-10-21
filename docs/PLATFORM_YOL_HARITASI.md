# Platform yol haritası ve yapılacaklar

Kaynak: 2026-10-19 karşılaştırması ("Yazılımcı için Yol Haritası — Ekranlar ve Menü" belgesi ile bugünkü sistem). Bu dosya
yapılacakların tek listesidir; bir madde bitince işaretlenir ve tarih, commit ve canlı bilgisi yanına yazılır.

Öncelik: **P0** hukuki risk / satış öncesi şart · **P1** en büyük kullanıcı değeri · **P2** önemli iyileştirme · **P3** sonra.
Büyüklük: **S** bir gün içinde · **M** birkaç gün · **L** bir haftadan uzun (inceleme ve gerçek PG QA dahil).

## 1. Hukuki ve KVKK

- [x] **P0 · M — Borcum sakin kapsamı (2026-10-19).** Sakin dairenin defterini yalnız kendi taşınma ayından itibaren görür (borç,
  ödeme, makbuz, ekstre, gecikme açıklaması, veri dışa aktarma); bakiye mahsup kuralıyla (vadesi en eski borçtan) hesaplanır,
  böylece önceki sakinin geç ödemesi ya da geçmiş aya yazılan borç yanlış bakiye üretmez. Yönetici tüm defteri görür. Ayrıntı:
  `docs/PLATFORM_FINANS.md` "Sakin kapsamı". Gerçek PG: `QA_ONLY=finance4b QA_PART=resident_scope` (S0-S11).
- [ ] **P1 · S — Taşınma tarihinin önemi yöneticiye gösterilsin.** Kişi eklerken ve toplu yüklemede "Borcum bu tarihten itibaren
  gösterir" uyarısı; yöneticinin daire / kişi kartında "sakin X ayından itibaren görür" göstergesi.
- [ ] **P2 · L — Kişi bazlı tahsilat.** Tahsilatta "kim ödedi" (kişi) tutulursa önceki sakinin taşınmadan sonra yaptığı ödeme yeni
  sakine hiç görünmez; malik ve kiracı için ayrı hesap (yazılımcı belgesindeki "her dairenin iki hesabı") bunun üzerine kurulur.
- [ ] **P0 · kullanıcıda — Yasal metinlerin yayını.** KVKK aydınlatma, gizlilik, kullanım koşulları, hesap ve veri silme, veri
  işleme sözleşmesi şablonları ve uygulamadaki gösterim altyapısı hazır. Gerekenler: şirket bilgileri (unvan, MERSİS, adres,
  KEP) ve avukat onayı (`docs/yasal/KULLANICIDAN_GEREKENLER.md`, `docs/yasal/AVUKAT_KONTROL_LISTESI.md`). Yayından sonra
  `legal.enforce_consents` açılır. Kontrol: aydınlatma metni "onay" istemez (bilgilendirmedir); açık rıza gereken işlem
  varsa ayrı alınır.
- [ ] **P0 · satış sürecinde — Veri işleme sözleşmesi.** Her site yönetimiyle (veri sorumlusu) Güde Teknoloji (veri işleyen)
  arasında imzalanır; şablon hazır.
- [ ] **P0 · M — Gecikme tazminatı ve borç hatırlatmayı açmadan önce dönem kapsamı.** Bugün ikisi de daire bazında hesaplanıyor:
  daire el değiştirince önceki dönemin gecikmiş borcu yeni sakine tazminat ya da hatırlatma olarak yansıyabilir. Açılmadan
  önce Borcum'daki kapsamla aynı kural uygulanmalı. İkisi de bugün varsayılan KAPALI ve hukuk onayı bayrağına bağlı.
- [ ] **P0 · kullanıcıda — Avukat onayı:** gecikme tazminatı (KMK 20: aylık %5, gün hesabı), borç hatırlatma metni,
  makbuz çekincesi (TBK 102/104).

## 2. Para akışı (en büyük değer)

- [ ] **P1 · M — Sakine ödeme bilgisi.** Borcum'da sitenin IBAN'ı ve daireye / aya özel referans kodu (ör. `GUL-A2-1026`),
  "kopyala" düğmeleriyle. Para doğrudan sitenin hesabına gider; ödeme lisansı gerekmez. Bağımlılık: kasa / banka hesabına
  IBAN alanı. Referans kodu, aşağıdaki banka eşlemesinin ilk kuralıdır.
- [ ] **P1 · L — Banka ekstresi yükleme ve otomatik eşleme.** Excel / CSV yüklenir, dosya olduğu gibi saklanır. Eşleme sırası:
  referans kodu → açıklamadaki daire kodu → daha önce eşlenmiş IBAN → gönderen adı → "bekliyor" (yönetici seçer, sistem
  ezberler). Kurallar: aynı satır iki kez işlenmez (tarih + tutar + açıklama + IBAN özeti); birden çok aya yayılan ödeme en
  eski borçtan kapatılır; daire olmayan satırlar (faiz, masraf, tedarikçi) gelir / gider olarak işlenir; "bu yüklemeyi geri
  al" tüm satırları ters kayıtla sıfırlar. Kabul: 3 aylık gerçek dosyada satırların en az %80'i kendiliğinden eşleşir; aynı
  dosya ikinci kez yüklenince hiçbir şey çift yazılmaz. Hukuk: banka dosyası üçüncü kişilerin verisini içerir, saklama süresi
  yasal metinlere yazılır.
- [ ] **P2 · L — Online kart ödemesi.** Yalnız lisanslı bir ödeme kuruluşu üzerinden ve para sitenin hesabına (6493 sayılı
  Kanun). Sağlayıcı seçimi ve sözleşme kullanıcıda.

## 3. Yönetici deneyimi

- [ ] **P1 · M — Yönetici ana sayfası "Bu ay".** Dört sayı: bu ay yazılan, toplanan (yüzdesiyle), geciken daire sayısı,
  kasa + banka toplamı (karta dokununca ilgili liste). Altında aylık beş adım (borç yaz → haber ver → parayı eşle → gider gir
  → rapor al), yapılanlar işaretli, yapılmamış ilk adımın yanında tek düğme. Son 5 para hareketi tek satırda.
- [ ] **P2 · M — Yönetim firması için "Tüm siteler" tablosu.** Yöneticinin sitelerinde aynı dört sayı, satır başına bir site,
  en düşük tahsilat oranı en üstte.
- [ ] **P2 · S — Ekranlarda sade dil.** "Tahakkuk", "Mutabakat" gibi sözcükler ekrandan çıkar ("Borç yazma", "Banka / kasa
  kontrolü"); kod ve API adları değişmez.
- [ ] **P2 · S — Her listede Excel'e aktarma.** Kişi, daire, araç ve finans raporlarında var; eksik listelerin envanteri
  çıkarılıp tamamlanır.

## 4. Bütçe ve raporlar

- [ ] **P2 · L — İşletme projesi (bütçe).** KMK 37 (7579 sayılı Kanunla 2026'da değişti): genel kurul onayı, onaylı proje
  yoksa geçici proje (en geç üç ayda kurula), yürürlükteki projeye göre artış en fazla yeniden değerleme oranı. Bütçe ile
  gerçekleşen karşılaştırması, kesinleşen projenin PDF'i.
- [ ] **P3 · M — İcra dökümü PDF.** Kesinleşmiş işletme projesi ya da kurul kararı + daire ekstresi (İİK 68/1). Avukat
  görüşüyle.
- [ ] **P3 · L — Isı pay ölçer paylaşımı** (Sayaç Okuma modülü, sitede "Yakında"). Sayaç firmasının dosyası yüklenir; fatura
  %70 ölçüme, %30 m²'ye bölünür (yönetmelik); önizleme ve onay.

## 5. Sakin uygulaması ve iletişim

- [ ] **P1 · kullanıcıda — Telefon bildirimini canlıya alma.** Kod hazır ve kapalı; Firebase hizmet hesabı dosyası ve
  `PUSH_ENABLED` bekliyor.
- [ ] **P2 · M — Telefon + SMS koduyla şifresiz giriş.** SMS sağlayıcısı ve maliyet kararı kullanıcıda.
- [ ] **P2 · M — SMS ve WhatsApp bildirimleri** (sitede "Yakında"). WhatsApp için KVKK 9. madde (yurt dışına aktarım:
  standart sözleşme ve Kurum'a bildirim) avukatla netleşir. Borç bilgisi yalnız ilgilisine gider (KVKK Kurulu 2026/348).
- [x] **İş takibinde fotoğraf eki** (2026-10-19, migration 047/048, canlıda).

## 6. Altyapı, yedek ve güvenlik

- [x] **P0 — Kaynak kodun gizliliği (karar 14, 2026-10-20).** `site_kapi_kontrol` GitHub deposu gizliye çekildi (Salih). Aynı kontrol
  `ev_otomasyon` deposu için de yapılmalı (`gudeteknoloji_com_tr` zaten gizli).
- [x] **P0 · S — Veritabanının dış kopyası (karar 13'ün kapsamadığı kısım; kuruldu 2026-10-21).** Şifreli günlük yedekler her gün
  geliştirici bilgisayarına çekiliyor (Windows zamanlanmış görevi `KapiYedekCek`, 11:00, hedef `G:\kapi-yedek`; ilk çalışma 15 dosyayı
  indirip doğruladı; ayrıntı `docs/OPERASYON_YEDEK_IZLEME.md` bölüm 7). Güde'nin Drive hesabı bağlanınca ikinci kopya oraya (karar D3).
  Aşağıdaki Drive kararı sisteme YÜKLENEN DOSYALARI kapsar;
  bütün sitelerin ortak veritabanını (kişiler, daireler, finans defteri, makbuzlar, kararlar, duyurular) kapsamaz. Veritabanı yedeği
  hâlâ yalnız sunucuda: sunucu kaybolursa kayıtların hepsi gider. Betikler hazır (`deploy/ops/offsite_push.sh`,
  `deploy/ops/pull_backups_windows.ps1`, şifreli); yalnız hedef seçilecek. Boyut küçük: bugün ~50 KB, 5.000 sitede 1. yıl sonunda
  günlük şifreli döküm ~5 GB. Kişisel veri içerdiği için Türkiye'de bir hedef tercih edilir (yurt dışı ise KVKK 9. madde).
- [ ] **P1 · L — Sitenin dosyaları sitenin Google Drive'ında (karar 13, 2026-10-20).** Her site yönetimi kendi Drive hesabını
  sisteme bağlar; sisteme yüklediği HER dosya (belgeler, iş takibi fotoğrafları, gider belgeleri, ileride eklenecek her yükleme)
  o sitenin Drive'ına kaydedilir ve oradan gösterilir. Plan, araştırma ve gereklilikler: `docs/PLATFORM_DRIVE_DEPOLAMA.md`.
  Uygulamadan önce netleşecekler:
  - **Asıl kopya mı, yedek mi:** 2026-10-20 kullanıcı kararı: Drive asıl depo; dosya alanını sunucuda karşılayamayız. Önerilen
    model: sunucuda kalıcı dosya yok, yalnız üst sınırı sabit önbellek ve bağlantı kopukken küçük geçici bekleme alanı; Drive
    bağlantısı dosya yükleyen modüller için zorunlu.
  - **Hesabın sahibi:** bir kişinin değil sitenin adına açılmış hesap; yönetim değişince devrin nasıl olacağı.
  - **Erişim:** sakinlere Drive bağlantısı verilmez; dosyayı uygulama gösterir, bugünkü yetki kuralları (kim hangi belgeyi görür)
    korunur.
  - **Google izni:** yalnız uygulamanın oluşturduğu dosyalara erişim (`drive.file`); Google Cloud projesi, onay ekranı ve gizlilik
    politikası adresi gerekir (yasal metinlerin yayınına bağlı).
  - **KVKK:** Drive sunucuları yurt dışında; veri sorumlusu site yönetimidir. Aydınlatma metni, veri işleme sözleşmesi ve
    9. madde (yurt dışına aktarım) avukatla netleşir.
  - **Hata durumları:** kota dolarsa ya da bağlantı koparsa yükleme sistemde kalır, yöneticiye uyarı gider, bağlantı gelince
    eksikler gönderilir.

## Kararlar ve sıra

2026-10-21'den beri kararların, uygulama sırasının ve dışarıdan gerekenlerin güncel hâli aşağıdaki eksik listesinin sonunda:
"Karar kaydı (2026-10-21)", "Uygulama sırası (2026-10-21)" ve "Dışarıdan gerekenler". Önceki "Sizden gerekenler" ve
"Önerilen sıra" listeleri bu kayıtla kapandı.

## Eksik listesi — işveren belgeleri ve Apsiyon karşılaştırması (2026-10-20)

İşveren bugün şunu bildirdi: sistem hâlâ yalnız bir kapı açma sistemi gibi duruyor; kullanıcılar Apsiyon'da çalışır gibi rahat etmeli;
girişte, kendisine tanımlı modüller güzel resimlerle dizili görünmeli. Bu bölüm, bunun için işverenin üç belgesinde ve Apsiyon'da olup
bizde olmayanları kanıtıyla listeler.

2026-10-21: Tablolardaki "Karar ya da bilgi (kimden)" sütunundaki sorular bölüm sonundaki "Karar kaydı (2026-10-21)" ile
kapatıldı; sütun tarihçe olarak bırakıldı.

**Kaynaklar**

1. `komutlar.txt` — 3 tasarım kuralı, renk ve ikon tablosu, 3 ekran çizimi, 5 aylık yol haritası, 5 net talimat. Tabloda: "komutlar".
2. "Yazılımcı için Yol Haritası — Ekranlar ve Menü" (PDF, 15 Ekim 2026, @cenk). Tabloda: "Yol Haritası PDF". Bu belge 2026-10-19'da bu
   dosyanın üst bölümleriyle zaten karşılaştırıldı; o işler burada yeniden yazılmadı, "Yol haritasında var: <madde adı>" diye bağlandı.
3. "Site Yönetim Sistemi — Yapılacaklar ve Kararlar 2026-10-19" (PDF): Cenk ve Salih'in yanıtları ve Cenk'in "sistemde görmediklerim"
   1 ve 2 notları. Tabloda: "Kararlar N" (N = karar numarası), "görmediklerim 1/2".
4. Apsiyon (yönetici paneli, yönetici mobil, sakin mobil). Tabloda: "Apsiyon [A…]"; adresler aşağıda.

**Yöntem**

- Taranan yerler: `lib/` (Flutter), `server/src/` (Node), `server/migrations/`, `docs/PLATFORM_*.md`, `docs/yasal/`,
  `tools/deneme_listesi/platform.json`.
- "Bugün sistemde" sütunu: **var / kısmen / yok** ve kanıt. Kanıt; dosya yolu (gerektiğinde satır), tablo ya da migration adıdır.
  "Araması sonuç yok" = o ifade `lib/`, `server/src/` ve `server/migrations/` içinde bulunamadı. Emin olunamayan yerde
  **doğrulanamadı** yazıldı.
- Satır numaraları 2026-10-20 durumuna aittir; dosyalar değişince kayabilir. Canlı sunucudaki veri (ör. Platform Ayarları değerleri)
  bu taramanın dışındadır.
- Apsiyon bilgileri aşağıdaki sayfalardan alındı. Hepsi **"Apsiyon'un sitesinde yazıyor"** türünde pazarlama iddiasıdır; bağımsız
  doğrulanmadı. Sayfada geçmeyen bir özellik "yok" demek değildir, "sayfada belirtilmemiş" demektir.
- Öncelik (P0–P3) ve büyüklük (S/M/L) ölçeği bu dosyanın başındakiyle aynıdır. Satır başındaki kodlar (G1, F2 …) "Önerilen sıra" ve
  "Sizden gereken kararlar ve bilgiler" listelerine bağlantıdır.

**Apsiyon kaynakları (hepsi "Apsiyon'un sitesinde yazıyor"; A19 ve A20 haber sitesidir)**

| Kod | Adres | Sitede yazan (özet) |
| --- | --- | --- |
| A1 | https://www.apsiyon.com/urunler/apsiyon | Yönetici paneli: aidat dağıtımı (kat maliki, kiracı, daire, kategori), kartla online tahsilat, rezervasyon ve konsiyerj, banka entegrasyonu ("tüm bankalar"), finans ve raporlama, e-posta/mobil bildirim/WhatsApp/SMS, sayaç, kişi-daire kayıtları, iş takibi, ücretsiz web sitesi, geçiş kontrol. Paketler: bağımsız yönetimler için Blue ve Black, yönetim ve inşaat firmaları için Kurumsal. |
| A2 | https://www.apsiyon.com/yonetici-mobil-uygulama | Yönetici mobil: gelir-gider ve kasa durumu, banka hareketlerini görme ve onaylama, kişi kartları ve davet, tesis ve rezervasyon onayı, tahsilat, iş takibi, cari izleme, onay bekleyen kişiler, borçlandırma, bakım emri. |
| A3 | https://www.apsiyon.com/konut-sakini/mobil-uygulama | Sakin mobil: banka/kredi kartıyla aidat, borç ve kira sözleşmesi, makbuz ve ekstre, site finansalları, rezervasyon, anket, ilan panosu, haber kaynağı, ziyaretçi kaydı, kargo takibi (SMS/e-posta), iş talebi, yönetim kadrosu, telefon rehberi, sigorta ve kampanya, 8 dil. |
| A4 | https://www.apsiyon.com/aidat-takip-programi | Aidat: işletme projesi (gider bütçesi, planlanan/gerçekleşen), otomatik dağıtım (m², arsa payı, bağımsız bölüm), gecikme tazminatı, toplu borçlandırma ve Excel ile borç yükleme, makbuz, toplu tahsilat, banka hareketlerini Excel ile yükleme ve onaylama, iade ve devir bakiye, 10 haneli kodla borç sorgulama, noterli işletme defteri basımı, icra takibi başlatma. |
| A5 | https://www.apsiyon.com/online-banka-entegrasyonu | 21 banka listeli ("Türkiye'nin tüm bankaları"), hareketler tek ekranda, "akıllı algoritma" ile kişiyle eşleme, anında onay, sanal POS ödemelerinin hesaba aktarımı. Sayfada CSV/Excel yükleme ve IBAN geçmiyor. |
| A6 | https://www.apsiyon.com/online-tahsilat-sistemi | Kredi kartıyla ödeme (iyzico altyapısı), kart saklama ve tek tık ödeme, otomatik ödeme talimatı, daireyle otomatik eşleme. Komisyon bu sayfada belirtilmemiş. |
| A7 | https://www.apsiyon.com/sayac-faturalandirma | Uzaktan okuma, Excel'den toplu aktarma, fatura veya birim fiyat ile dağıtım, sıcak su dağıtımı, Excel raporu, faturayı e-posta ve SMS ile gönderme. Elle giriş ve fotoğrafla okuma sayfada belirtilmemiş. |
| A8 | https://www.apsiyon.com/otomatik-isi-pay-olcer-kalorimetre-sistemi | Isı pay ölçer: uzaktan günlük okuma, bağımsız bölümlere paylaştırma, e-posta/SMS bildirimi; SSS: 26847 sayılı yönetmelik 8.1 uyarınca %70 ölçüm, %30 alan. |
| A9 | https://www.apsiyon.com/rezervasyon-sistemi | Tesis kriterleri, onay/iptal, müsaitlik, mobilden rezervasyon, ücretli tesis için online ödeme, rezervasyon geçmişi, kart ve QR ile geçiş entegrasyonu. |
| A10 | https://www.apsiyon.com/tur-kontrol-sistemi | NFC/QR ile personel turu, rota ve süre, fotoğraflı not, çevrimdışı çalışma, rapor. |
| A11 | https://www.apsiyon.com/e-posta-sms-gonderimi | Sınırsız şablon, otomatik hatırlatmalar (borç, iş atama, rezervasyon, anket), ileri tarihe planlama, iletildi/okundu bilgisi; kanallar: e-posta, SMS, mobil bildirim, WhatsApp. |
| A12 | https://www.apsiyon.com/gecis-kontrol-sistemleri | Kartlı geçiş, plaka tanıma, HGS, QR ile geçiş (kurye dahil), Santral Plus (sesli borç bildirimi). Telefonla kapı açma sayfada belirtilmemiş. |
| A13 | https://www.apsiyon.com/tum-cozumler | 18 yönetici çözümü başlığı: muhasebe (tek düzen hesap planı), bakım ve onarım, tur kontrol, Santral Plus, saha mobil ve diğerleri. Yönetim firması "Tüm siteler" görünümü, genel kurul, ziyaretçi ve komşu panosu başlıkları bu sayfada yok. |
| A14 | https://www.apsiyon.com/mobil-aidat-tahsilat-cihazi | Android tabanlı kartlı tahsilat cihazı ve termal yazıcı; tahsilat sisteme otomatik işlenir. |
| A15 | https://www.apsiyon.com/web-sitesi-hizmeti | Ücretsiz özelleştirilebilir web sitesi: duyuru, anket, galeri, forum, rezervasyon, iş talebi, yönetim kadrosu ve telefonlar. |
| A16 | https://www.apsiyon.com/urunler/apsis | Apsis (sade paket): toplu borçlandırma, banka, gelir-gider, e-posta/SMS, icra, sınırsız firma ve kişi. Örnek fiyat: 20 daire için yılda 3.240 TL + KDV. |
| A17 | https://www.apsiyon.com/ada-dijital-asistan ve https://www.apsiyon.com/site-yonetici-asistani | ADA (sakin ve yönetici) ve ASYA (yönetici; Kat Mülkiyeti Kanunu soruları): WhatsApp tabanlı yapay zekâ asistanları. |
| A18 | https://www.apsiyon.com/konut-sakini/avantajlar | Sakin avantajları: arıza/talep kaydı, kartla ödeme, rezervasyon, duyuru ve anket, kargo takibi, sigorta, ilan panosu. |
| A19 | https://webrazzi.com/2020/04/03/apsiyon-komsum-var | (Haber.) "Komşum Var": yardım iste, yönetici onayı, "Ben Yaparım". |
| A20 | https://webrazzi.com/2021/05/11/apsiyon-yeni-hizmetiyle-apartman-ve-site-yonetimlerini-profesyonel-yonetim-firmalariyla-bulusturuyor/ | (Haber.) "Profesyonel yönetim firması bul" hizmeti. Çoklu site ya da firma paneli bu haberde geçmiyor. |

Mağaza kuralları için (H6): Apple https://developer.apple.com/support/enrollment/ ve Google Play https://support.google.com/googleplay/android-developer/answer/14151465.

### 1. Görünüm ve gezinme

| Konu | İstek (kaynak) | Bugün sistemde (var / kısmen / yok + kanıt) | Öncelik | Büyüklük | Karar ya da bilgi (kimden) |
| --- | --- | --- | --- | --- | --- |
| **G1** Panel modül vitrini: girişte kapı paneli yerine, kendisine tanımlı modüllerin resimli kartları | Bugünkü geri bildirim; Apsiyon [A1] | **Yapılıyor** (ayrı ajan). Bugün: yönetici girişte saat + kapı durum kartı (`lib/ui/views/dashboard_view.dart` 99-104), daire sakini girişte yalnız kapı kumandası (aynı dosya 72-96). Hazır olanlar: modül verisi `GET /app/my-modules` (`docs/PLATFORM_MODUL_SISTEMI.md`), görsel yer tutucu sözleşmesi `lib/ui/design/module_art.dart` (commit 14d98bb). | P1 | M | Yok |
| **G2** Gruplu menü (Apsiyon düzeni): 7 başlık, 22 sayfa; Ayarlar sağ üstte dişli; site seçici en üstte | Yol Haritası PDF (Menü); komutlar Ekran 1 | **Yapıldı (Dalga 1, 2026-10-21):** çekmece 8 başlıkta: Ana sayfa · Daireler · Borçlar · Tahsilat · Giderler · İletişim · Raporlar · Site hizmetleri; görünür öğesi olmayan başlık çizilmez (Tahsilat, Giderler ve Raporlar bugün boş). Ayarlar sağ üstte dişli: sağdan açılan panelde Profilim, Eller Serbest, kullanıcı yönetimi, Modüller, Modül Talepleri, Site Başvuruları, cihaz ekranları, Denetim Kaydı, Platform Ayarları ve İstemci Hataları; bekleyen sayılar dişlide rozet, "Masaüstüne Widget Ekle" de bu panelde. Site seçici çekmecenin en üstünde (birden çok sitesi olan yöneticide "Tüm siteler" ya da bir site). Kanıt: `lib/ui/widgets/yan_menu.dart` (`SirketMenuGroup`, `menuGroupOf`, `YanMenuAyarlar`), `lib/ui/pages/home_page.dart`; `docs/TASARIM_DILI.md` §8 "Gezinme"; alt plan `docs/superpowers/plans/2026-10-21-ip-1d.md`. Ayrı web paneli yine yok (aynı Flutter uygulaması web'de çalışır; `platform.json` F11.05 yakinda). Deneme: F28. | P1 | L | Cenk: grup adları ve sırası |
| **G3** Sakin alt çubuğu (4 sekme); açılışta doğrudan borç | Yol Haritası PDF Ekran 4: Borcum · Duyuru · Arıza · Belgeler; komutlar Ekran 3: Özet · Arıza · Kapı · Belge | **Yapıldı (Dalga 1, 2026-10-21):** sakin alt çubuğu Özet · Duyuru · Arıza · Kapı · Belgeler (`lib/ui/widgets/resident_bottom_bar.dart`, kurallar `lib/ui/helpers/resident_tabs.dart`). Sekmeler menünün görünür öğelerinden türer (modülü kapalı sekme yok); Kapı yalnız kapı yetkisi olana görünür; iki sekmeden azsa ve kısa ekranda (yatay telefon, yükseklik 480 dp'nin altında) çubuk yok. Yalnız sakin görünümünde (daire sakini, sakin modundaki yönetici). Uygulama Özet'te (Panel vitrini, borç kartı üstte) açılır; "Öde" düğmesi dalga 2'de (F1 + G4). Deneme: F28.07-F28.12. | P1 | M | Cenk: iki belge farklı sekme öneriyor (Kapı mı Belgeler mi?) |
| **G4** Sakin ana ekranı: koyu "Güncel toplam borcunuz" kartı + [Öde]; altında beyaz hızlı kutular (Arıza Bildir, Ziyaretçi Kodu, Belgeler) | komutlar Kural 3 ve Ekran 3; Yol Haritası PDF Ekran 4 | **Yok.** Daire sakini girişte kapı kumandasını görür (`dashboard_view.dart` 72-96). Borç kartı ayrı sayfada (`lib/ui/views/my_finance_view.dart`, "Toplam borç" satır 205); "Öde" düğmesi yok. | P1 | M | Bağımlı: F1 |
| **G5** Yönetici ana sayfası: dört sayı kartı, beş adımlı aylık döngü, koyu "Dikkat edilmesi gereken N işlem" barı, son hareketler | Yol Haritası PDF Ekran 1; komutlar Ekran 1 | **Yok.** Yol haritasında var: «Yönetici ana sayfası "Bu ay"». Yeni ayrıntı: koyu dikkat barı (ekstrede tanınmayan ödeme; geçici işletme projesinde kalan gün) ve "son defter hareketleri" şeridi. Site geneli hareket uç noktası yok (defter okuma daire bazlı: `GET .../apartments/:id/account`, `docs/PLATFORM_FINANS.md` 49). Dikkat barının iki kaynağı (F3, F7) henüz yok. | P1 | M | Yok |
| **G6** Renk ve buton kuralı: %90 beyaz; koyu #0F172A yalnız ana buton ve kritik uyarıda | komutlar Kural 1, renk tablosu, talimat 3 | **Yapıldı (Dalga 1, 2026-10-21):** sade stil tema ve bileşen düzeyinde: düz #F8FAFC zemin (ışıma yok), beyaz gölgesiz kart + ince #E2E8F0 çerçeve, gövde metni #475569, ana onay düğmesi #0F172A ve düz (koyu temada #F8FAFC zemin + koyu yazı), ikincil düğmeler beyaz + çerçeve, bildirim çubuğu tek koyu yüzey, mavi yalnız bağlantı ve odak halkasında; koyu tema kalır. Kapı düğmesinin görünüşü değişmedi (piksel karşılaştırmalı testle korunur). Kanıt: `lib/styles/app_theme.dart`, `lib/ui/design/tokens.dart`, `buttons.dart`, `app_card.dart`, `app_snack.dart`; `docs/TASARIM_DILI.md` (ekran düzeyinde kalanlar §11). Deneme: F27. | P2 | M | Cenk: sade stil (komutlar) mi, mevcut parlak stil mi? Yeni ekranlardan önce karar iyi olur |
| **G7** Durum noktaları (● zümrüt #10B981, kehribar #F59E0B, mercan #E11D48), arka plan boyamadan | komutlar renk tablosu | **Yapıldı (Dalga 1, 2026-10-21):** durum metnin solunda küçük nokta; zemin ve çerçeve boyanmaz: tamam #10B981, bekliyor #F59E0B, kritik #E11D48 (tehlike tonu da artık #E11D48); öteki tonlarda nokta gri. Yeni `StatusDot` (`lib/ui/design/status_dot.dart`); `StatusChip` aynı görünüme döndü (`lib/ui/design/status_chip.dart`); `docs/TASARIM_DILI.md` §1 ve §5. Deneme: F27.04, F27.05. | P3 | S | Bağlı: G6 |
| **G8** İkon seti: Lucide ya da Phosphor, 1,5 px ince çizgi | komutlar bölüm 2 | **Yok.** `pubspec.yaml` bağımlılıklarında ikon paketi yok; Material ikonları kullanılıyor (ör. `Icons.table_chart_rounded`). | P3 | M | Cenk: Lucide mi Phosphor mu |
| **G9** Beyaz etiket tema: aynı veritabanında site ya da firma başına ayrı tema (5 sabit renk değişkeni) | komutlar bölüm 2 | **Yok.** Tema sabit (`lib/styles/app_theme.dart`, `tokens.dart`); site ya da firma başına tema/marka alanı yok (tema, marka, logo araması sonuç yok). | P3 | M | Cenk: yönetim firmalarına "kendi markanız" satılacak mı? |
| **G10** Sade dil: "tahakkuk, cari, mutabakat" ekranda yok | Yol Haritası PDF (dil kuralı) | **Kısmen.** Yol haritasında var: «Ekranlarda sade dil». Kanıt: "Tahakkuk" ekranda (`lib/ui/views/finance_reports_tab.dart` 868, 925, 1470) ve PDF'te (`lib/services/pdf_finance_service.dart` 710, 859); "Mutabakat" düğmesi (`lib/ui/widgets/finance_4b_parts.dart` 325). "Cari" ekranda geçmiyor. | P2 | S | Yok |
| **G11** Kurallar koddan değil tablodan: "%5 gecikme", "90 gün geçici bütçe", "%70/%30 ısı payı" | komutlar talimat 4 | **Yapıldı (Dalga 1, 2026-10-21):** kurallar tablosu (`server/migrations/053_platform_rules.sql`; kayıt defteri `server/src/modules/platform_rules.js`, okuma ve yazma `platform_rules_service.js`): gecikme tazminatı aylık üst sınırı (varsayılan %5; kod 500 baz puanı hiçbir koşulda aşmaz), geçici işletme projesi en uzun süresi (90 gün), itiraz süresi (7 gün), ısınma payı (%70 ölçüm / %30 alan, toplamı 100), gelecek yıl tahmini artış oranı (siteye özel değer verilebilir) ve H2 saklama süreleri (otomatik silme avukat onayına kadar kapalı ve kilitli). Her kuralın sınırı, geçerlilik tarihi ve mevzuat notu var; değişiklik denetim kaydına yazılır. Site yöneticisinin Finans Ayarları'ndaki gecikme oranı bu sınırı aşamaz. Süper kullanıcı Platform Ayarları > Kurallar'dan, siteye özel değeri Modüller > Kurallar'dan değiştirir; yönetici Modüller'den yalnız görür (`lib/ui/views/platform_rules_view.dart`). `docs/PLATFORM_KURALLAR.md`; deneme F26. | P2 | M | Avukat: hangi oran sabit, hangisini site değiştirebilir? |
| **G12** Daire kartında iki sekme [Kiracı Hesabı] [Ev Sahibi Hesabı]; bakiyeler karışmaz | komutlar talimat 2, Adım 1; Yol Haritası PDF (sözlük: "her dairenin iki hesabı") | **Yapıldı (Dalga 1, 2026-10-21):** her dairenin "Kiracı hesabı" ve "Ev sahibi hesabı" ayrı, bakiyeler karışmaz (`server/migrations/052_finance_parties.sql`; sözleşme modülü `server/src/modules/finance_parties.js`). Borç tanımında ve ek borçta "Kim öder" (dairede oturan / ev sahibi; varsayılan aylık aidatta dairede oturan, tek seferlikte ev sahibi); tahsilat seçilen hesaba yazılır, düzeltmeyle öteki hesaba taşınabilir; ekstrede iki sekme, bakiye listesinde iki rozet, yaşlandırma ve daire ekstresinde hesap süzgeci; gecikme tazminatı, mahsup ve hatırlatma hesap başına. Sakin yalnız kendi hesabını görür ("İkisi" olan dairede malik kiracı hesabını salt okunur görür). Eski kayıtlar geri doldurulmadı: hesap, kaydın "kim öder" anlık görüntüsünden okunur (kiracı → kiracı hesabı; malik / ikisi → ev sahibi hesabı). `docs/PLATFORM_FINANS.md` "İki hesap (2026-10-21)"; deneme F25. | P1 | L | Cenk + avukat: hangi kalem kimin hesabına yazılır; kiracı ödemezse malik sorumlu mu (KMK m.22 notu: `docs/PLATFORM_FINANS_4B.md` 18) |
| **G13** Satır düzeyi güvenlik (RLS) | komutlar Adım 1 | **Yok.** `ROW LEVEL SECURITY` ve `CREATE POLICY` migration ve sunucu kodunda yok (arama sonuç yok). Site yalıtımı uygulama katmanında (`docs/PLATFORM_FINANS.md` "Yetki"). | P3 | M | Salih: uygulama katmanı yeterli mi? |
| **G14** Her listede arama ve Excel'e aktar | Yol Haritası PDF (sade kullanım kuralı) | **Kısmen.** Yol haritasında var: «Her listede Excel'e aktarma». Envanter: Excel/CSV var — Kişiler, Daireler, Araçlar (`lib/ui/widgets/bulk_entry_buttons.dart`; `server/src/modules/bulk_import_spec.js` 10) ve finansta yaşlandırma, gelir-gider, kasa durumu, daire ekstresi, gider, makbuz (`server/src/modules/finance_export_tables.js`). Yok: duyurular, iş talepleri, ziyaretçi/kargo, rezervasyon, anket sonucu, firma/sözleşme, karar listesi, belgeler (`lib/ui` içinde Excel/CSV geçen 11 dosyanın hepsi kişi ya da finans). Kapı günlüğü yalnız PDF (`lib/services/pdf_logs_service.dart`). | P2 | M | Yok |
| **G15** İki haftada bir canlı ekran demosu | komutlar talimat 5 | **Yapıldı (Dalga 1, 2026-10-21):** demo senaryosu `docs/DEMO_SENARYOSU.md`: kurallar (gerçek kişi verisi gösterilmez, süper kullanıcı ekranları demo sitesine süzülür, "Yakında…" ve hukuk onayı bekleyen özellik çalışıyor gibi gösterilmez), demo sitesi hazırlığı ve demo günü kontrol listesi, 15 dakikalık akış (yönetici, sakin, süper kullanıcı), "Bu iki haftada yeni" bölümü, yedek plan ve demo kaydı tablosu. Takvim Cenk ve Salih'te. Deneme: F29.09. | — | — | Cenk ve Salih: demo takvimi |

### 2. Finans ve tahsilat

| Konu | İstek (kaynak) | Bugün sistemde (var / kısmen / yok + kanıt) | Öncelik | Büyüklük | Karar ya da bilgi (kimden) |
| --- | --- | --- | --- | --- | --- |
| **F1** Sakine ödeme bilgisi: sitenin IBAN'ı + daire ve aya özel referans kodu (GUL-A2-1026); "Komisyonsuz öde (FAST/POS)" | Yol Haritası PDF Ekran 4; komutlar Ekran 3 | **Yok.** Yol haritasında var: «Sakine ödeme bilgisi». Kanıt: IBAN için alan ya da sütun yok (`iban` sözcüğü `server/src`, `server/migrations` ve `lib` içinde yalnız kişisel veri uyarı metinlerinde geçiyor: `lib/ui/dialogs/document_upload_dialog.dart` 39, `lib/ui/dialogs/finance_expense_dialog.dart` 715); kasa/banka hesabı yalnız ad ve tür taşır (`server/migrations/040_finance_4b.sql` 183-202, tür: cash ya da bank). | P1 | M | Site yöneticileri: sitelerin IBAN'ları. Cenk: referans biçimi |
| **F2** Dekontla ödeme: sakin dekontu paylaşır/yükler, kayıt "geçici kabul"e düşer, yönetici karşılaştırıp onaylar ya da iptal eder (toplu da); elden makbuz/dekont girişi | Kararlar 7 (Cenk) | **Yok.** Sakinin ödeme bildirme yolu yok. Tahsilat yöntemi yalnız yöneticinin girdiği nakit, havale, çek (`034_finance.sql` 121-124). "Dekont", "geçici kabul" araması ilgili sonuç vermedi. Telefondan uygulamaya dosya paylaşma alıcısı yok (`android/app/src/main/AndroidManifest.xml` içinde `ACTION_SEND` yok; `pubspec.yaml`'da paylaşım alıcı paketi yok). Gerekli parçalar: sakin yükleme ekranı; bekleyen ödeme tablosu (defter DIŞINDA, onaylanınca deftere yazılır); yönetici karşılaştırma ekranı (tutar, tarih, gönderen, daire; yanlış daire koruması); tek ve toplu onay/ret; onayda makbuz. Dekont dosyası Drive'a gider (D1). | P1 | L | Cenk: geçici kabulde sakinin bakiyesi düşer mi, "inceleniyor" mu görünür? Avukat: dekont üçüncü kişi verisi içerir (KVKK) |
| **F3** Banka ekstresi (Excel, CSV, MT940) yükleme; IBAN hafızası; yalnız tanınmayan satırlar ekrana gelir, aynı satırda daire seçilir, "bu IBAN'ı kaydet"; çift işleme yok; yükleme geri alınır | komutlar Kural 2 ve Ekran 2; Yol Haritası PDF Ekran 3 | **Yok.** Yol haritasında var: «Banka ekstresi yükleme ve otomatik eşleme». Kanıt: `docs/PLATFORM_FINANS_4B.md` 13 "banka ekstresi içe aktarma/otomatik eşleştirme" kapsam dışı; IBAN alanı yok (F1); `platform.json` F8.02 yakinda. Apsiyon [A5]: hareketler tek ekranda, "akıllı algoritma" ile eşleme, onay (sitesinde yazıyor); [A4]: banka hareketini Excel ile yükleme (sitesinde yazıyor). | P1 | L | Cenk/site yöneticileri: gerçek ekstre örnekleri (en az 3 banka, 3 ay); MT940 gerekli mi? |
| **F4** Eski yazılımdan borç ve devir bakiyesi göçü (Excel) | komutlar Adım 3 ("Veri Göçü"); Apsiyon [A4] | **Kısmen.** Excel yükleme yalnız daire, kişi, araç (`bulk_import_spec.js` 10). Daire borcu ya da devir bakiyesi yüklenemez; açılış bakiyesi yalnız kasa/banka hesabında (`finance_accounts.opening_balance_minor`, `040_finance_4b.sql` 190). Elle "Ek borç" ile girilir (`docs/PLATFORM_FINANS.md` 45). | P1 | M | Cenk: bir eski yazılımın örnek dışa aktarma dosyası |
| **F5** "Altın veri seti": işverenin gerçek örnek hesabıyla kuruşu kuruşuna sıfır sapma testi | komutlar Adım 2; Yol Haritası PDF (yapım sırası 2) | **Yapıldı (Dalga 1, 2026-10-21):** ekip elle hesaplanmış 24 daireli örnek site tablosunu hazırladı: dağıtım (D1–D6: eşit, brüt / net m², arsa payı, kategori, sabit), gecikme tazminatı (L1–L4), mahsup (M1–M3) ve iki hesaplı 7 kontrol; sonuç kuruşu kuruşuna tutmazsa test düşer (`server/test/fixtures/finance_golden_site.js`, `server/test/finance_golden_dataset.test.js`; `docs/PLATFORM_FINANS.md` "Altın veri seti (F5, 2026-10-21)"). Cenk'in gerçek tablosu gelince ikinci set olarak eklenir. Deneme: F26.09. | P1 | S | Cenk: gerçek bir sitenin 1–2 aylık, elle hesaplanmış aidat tablosu |
| **F6** Online kart ödemesi | Yol Haritası PDF Ekran 4; Apsiyon [A6] | **Yok.** Yol haritasında var: «Online kart ödemesi». Katalogda `online_payment` "yakında" (`server/src/modules/catalog.js` 90-97). Apsiyon [A6] sitesinde yazıyor: kart saklama, otomatik ödeme talimatı; taksit [A13]'te anılıyor. | P2 | L | Cenk: sağlayıcı; kart komisyonunu kim öder ("Komisyonsuz öde" kartıyla çelişmesin) |
| **F7** İşletme projesi (bütçe): Taslak → Tebliğ → Kesin durum makinesi; geçici proje 90 gün; planlanan–gerçekleşen | komutlar Adım 2 ve Ekran 1 (dikkat barı: "geçici işletme projesi için son 18 gün"); Apsiyon [A4] | **Yok.** Yol haritasında var: «İşletme projesi (bütçe)». Kanıt: bütçe/işletme projesi kodda yok (`budget`, `bütçe`, `işletme proje` araması yalnız ilgisiz dosyalarda çıktı); `docs/PLATFORM_FINANS_4B.md` 13 kapsam dışı sayıyor. Apsiyon [A4] sitesinde yazıyor: gider bütçesi, planlanan/gerçekleşen. | P2 | L | Avukat: KMK m.37 (7579 sayılı Kanun) adımları ve süreleri. Cenk: "Tebliğ" adımı belge ister mi? |
| **F8** İcra: tek tıkla icra PDF'i ve avukat Excel'i | komutlar Adım 4; Yol Haritası PDF (İcra dökümü) | **Yok.** Yol haritasında var: «İcra dökümü PDF». Kanıt: icra özelliği yok (`icra` araması yalnız hatırlatma şablonundaki yasak-dil notunda: `server/src/modules/finance_reminder_mail.js` 4). Apsiyon [A4] sitesinde yazıyor: icra takibi başlatma ve izleme. | P3 | M | Avukat: dökümün içeriği (İİK 68/1) |

### 3. Sakin uygulaması

| Konu | İstek (kaynak) | Bugün sistemde (var / kısmen / yok + kanıt) | Öncelik | Büyüklük | Karar ya da bilgi (kimden) |
| --- | --- | --- | --- | --- | --- |
| **S1** Telefon + SMS koduyla şifresiz giriş | Yol Haritası PDF Ekran 4 | **Yok.** Yol haritasında var: «Telefon + SMS koduyla şifresiz giriş». Giriş "E-posta veya Kullanıcı Adı" + şifre (`lib/ui/pages/login_page.dart` 286). SMS sağlayıcı kodu yok (SMS, OTP araması sonuç yok). | P2 | M | Cenk: SMS sağlayıcı ve maliyet (Kararlar 10 yanıtı boş) |
| **S2** Telefon bildirimi (uygulama kapalıyken) | Kararlar 6; Yol Haritası PDF | **Kod hazır, kapalı.** Yol haritasında var: «Telefon bildirimini canlıya alma». `PUSH_ENABLED` varsayılan 0 (`server/src/modules/push_config.js` 4). | P1 | S | Cenk ve Salih: Firebase hizmet hesabı; Apple hesabı kararı (H6) |
| **S3** Kargo ve paket geldi bildirimi (SMS, e-posta, telefon) | Apsiyon [A3] | **Kısmen.** Kargo kaydı var (`visitor_entries.kind` visitor ya da cargo: `server/migrations/045_visitor_log.sql` 27); bildirim yalnız uygulama içi (`server/src/modules/catalog.js` 109); SMS/e-posta/telefon bildirimi yok. | P2 | S | Bağımlı: S2, C1 |
| **S4** Komşu panosu / ilan panosu / "Komşum Var" yardımlaşma | Apsiyon [A3], [A19] | **Yok.** `ilan`, `komşum`, `neighbor`, `forum` araması ilgili sonuç vermedi. İşveren belgelerinde istek yok. Apsiyon sitesinde yazıyor: ilan panosu, alım-satım, yolculuk paylaşımı. | P3 | M | Cenk: isteniyor mu? İçerik denetimi sorumluluğu (hukuk) |
| **S5** Yönetim kadrosu ve faydalı telefonlar (rehber) | Apsiyon [A3], [A15] | **Yok.** `rehber`, `phone_directory`, `faydalı telefon` araması ilgili sonuç vermedi. | P3 | S | Cenk |
| **S6** Çok dilli uygulama | Apsiyon [A3] (8 dil, sitesinde yazıyor) | **Yok.** Yalnız Türkçe: `lib/` altında `.arb` dosyası yok, `pubspec.yaml`'da `flutter_localizations` yok. | P3 | L | Cenk: yabancı uyruklu sakin ihtiyacı var mı? |

### 4. İletişim

| Konu | İstek (kaynak) | Bugün sistemde (var / kısmen / yok + kanıt) | Öncelik | Büyüklük | Karar ya da bilgi (kimden) |
| --- | --- | --- | --- | --- | --- |
| **C1** SMS ve WhatsApp bildirimi | Kararlar 10 (yanıt boş); Yol Haritası PDF; Apsiyon [A11] | **Yok.** Yol haritasında var: «SMS ve WhatsApp bildirimleri». Sağlayıcı kodu yok; `platform.json` F3.12 ve F3.13 yakinda. Bizde duyuru zamanlama, okundu bilgisi ve e-posta var (`platform.json` F3.04, F3.06, F3.08 hazir). Apsiyon [A11] sitesinde yazıyor: sınırsız şablon, otomatik hatırlatmalar, iletildi/okundu, WhatsApp. | P2 | M | Cenk: isteniyor mu, bütçe? Avukat: WhatsApp için KVKK m.9 |

### 5. Teknik işletme ve sayaç

| Konu | İstek (kaynak) | Bugün sistemde (var / kısmen / yok + kanıt) | Öncelik | Büyüklük | Karar ya da bilgi (kimden) |
| --- | --- | --- | --- | --- | --- |
| **T1** Sayaç okuma ve faturalandırma modülü (su, elektrik, ısı); uzaktan okuyan sayaç için link ya da dosyadan içe aktarma | Kararlar 8; komutlar Adım 4; Apsiyon [A7] | **Yok.** Katalogda `metering` "yakında" (`server/src/modules/catalog.js` 82-89); tablo ve ekran yok (sayaç tablosu/ucu araması sonuç yok); `platform.json` F7.01–F7.03 yakinda. Apsiyon [A7] sitesinde yazıyor: uzaktan okuma, Excel aktarma, fatura/birim fiyat dağıtımı, faturayı e-posta ve SMS ile gönderme. | P2 | L | Cenk: sayaç firmaları ve dosya/link biçimleri |
| **T2** Isı pay ölçer paylaşımı: fatura %70 ölçüme, %30 m²'ye; Excel okuyucu; sakin borcunda "Ekim ısı pay ölçer" kalemi | Yol Haritası PDF; komutlar Adım 4 ve Ekran 3 | **Yok.** Yol haritasında var: «Isı pay ölçer paylaşımı». m² verisi hazır (`apartments.gross_area_m2`, `net_area_m2`: `docs/PLATFORM_FINANS.md` 3). Apsiyon [A8] sitesinde yazıyor: 26847 sayılı yönetmelik 8.1, %70/%30. | P2 | M | Avukat/mevzuat: oranın yönetmelik dayanağı doğrulansın (mevzuat.gov.tr'den doğrulanmadı) |
| **T3** Elle okuma: görevli saati fotoğraflar, sistem değeri okur (OCR); daire no fotoğraftan alınır; çekim ekranı sıradaki daireyi gösterir, kamera kapanmaz (Daire 1 → 2 → …) | Kararlar 8 | **Yok.** Kamera/OCR paketi yok (`pubspec.yaml`: `camera`, `image_picker`, ML Kit yok; `mobile_scanner` yalnız karekod için). Fotoğraf `file_picker` ile seçilir (`lib/services/work_attachment_picker.dart` 164-176). Küçültme ve EXIF silme hazır (`lib/services/work_photo_prepare.dart`). | P2 | L | Salih: OCR telefonda mı sunucuda mı? Cenk: yanlış okumada kim düzeltir/onaylar? |
| **T4** İnternet yoksa fotoğraf telefonda bekler, bağlantı gelince Drive ile eşitlenir | Kararlar 8 | **Yok.** Drive planında yalnız sunucu–Drive arası bekleme alanı var (`docs/PLATFORM_DRIVE_DEPOLAMA.md` 16-19); telefon tarafında çevrimdışı kuyruk planda geçmiyor (çevrimdışı araması sonuç yok). | P2 | M | Bağımlı: D1 |
| **T5** Dosya adı kuralı (AB_D13_201026) ve Drive klasörleri (SrvEkim_26, suEkim_26, elektrikEkim_26, TeklifEkim_26); sistemde yalnız günlük (log) | Kararlar 8 | **Yok.** Drive planında modül klasörleri var (`PLATFORM_DRIVE_DEPOLAMA.md` 72-75), ay bazlı klasör ve bu dosya adı kuralı yok (`SrvEkim`, `AB_D13` araması `docs/` içinde sonuç yok). | P2 | S | Cenk: adlandırma kesin mi? |
| **T6** Teklif toplama: o ay alınan teklif PDF ve fotoğrafları kendi klasöründe | Kararlar 8 (TeklifEkim) | **Yok.** Teklif modülü yok (teklif araması ilgili sonuç vermedi). Sözleşme takibi var (`contracts`, `server/migrations/049_contracts.sql`) ama teklif yok. | P2 | M | Cenk: teklifler hangi modüle bağlanır (gider, sözleşme, iş takibi)? "Teklif Pro"daki Drive sistemini tarif etmeli (depoda yok) |
| **T7** Ekipman envanteri ve periyodik bakım (asansör, interkom, kamera, bariyer, yangın algılama) | görmediklerim 2; Apsiyon [A13] ("Bakım ve Onarım") | **Yok.** İş takibinde "bakım" yalnız talep kategorisi (`server/migrations/042_work_tracking.sql` 33). Cihaz envanteri yalnız kapı cihazları için (`server/migrations/024_device_inventory_and_defect_management.sql`). | P2 | M | Cenk: hangi ekipman, hangi bakım periyodu |
| **T8** Geçiş donanımı: kamera Hikvision, Tiandy ve yerli markalar | Kararlar 9 | **Kısmen.** Kartlı geçiş hazır (`catalog.js` 114-121; `server/migrations/046_access_cards.sql`). Plaka tanıma, HGS, kamera "yakında" (`catalog.js` 138-161). Marka adları kodda ya da belgelerde geçmiyor (`Hikvision`, `Tiandy` araması sonuç yok): entegrasyon araştırması yapılmamış. | P3 | L | Cenk: kullanılacak model ve protokol. Salih: SDK/arayüz araştırması |

### 6. Raporlar

| Konu | İstek (kaynak) | Bugün sistemde (var / kısmen / yok + kanıt) | Öncelik | Büyüklük | Karar ya da bilgi (kimden) |
| --- | --- | --- | --- | --- | --- |
| **R1** Gelir-gider analizi: rutin ve ekstra gider, kategori/ekipman bazında; 3-6-12 aylık grafik; gelecek yıl tahmini | görmediklerim 2 (Cenk) | **Kısmen.** Aylık gelir-gider raporu var (en çok 36 ay, kategori kırılımıyla: `server/src/modules/finance_4b_routes.js` 438; `docs/PLATFORM_FINANS_4B.md` 170); 12 hazır gider kategorisi (`server/src/modules/finance_expenses.js` 55-68). Yok: grafik (`pubspec.yaml`'da grafik paketi yok; `grafik`/`chart` araması yalnız ikon adları), "rutin / olağan dışı" işareti (gider tablosunda yok: `040_finance_4b.sql` 239-283), ekipman bazlı toplam (T7), 3-6 aylık karşılaştırma, tahmin (finans dosyalarında `tahmin`/`forecast` araması sonuç yok). | P1 | L | Cenk: "rutin" gider nasıl işaretlenir? Tahmin yöntemi (geçen yıl + oran mı?) |
| **R2** Yıl sonu faaliyet raporu: kayıtlı dosya, fotoğraf ve görsellerden otomatik hazırlanır, yönetici değiştirir | görmediklerim 1 (Cenk) | **Kısmen.** Parçalar var: yönetim kurulu özeti (`reports/board-summary`, yıllık dönem verilebilir: `finance_4b_routes.js` 440; `docs/PLATFORM_FINANS_4B.md` 173), karar defteri yıl PDF'i (`lib/services/pdf_decision_service.dart`), belgeler, gider belgeleri, iş takibi fotoğrafları. Yok: bunları tek taslakta toplayan, düzenlenebilir rapor (`faaliyet`, `annual_report` araması sonuç yok). Dosyalar Drive'a taşınınca (D1) rapor görselleri Drive'dan alacak. | P2 | L | Cenk: rapor bölümleri ve örnek bir faaliyet raporu. Avukat: KMK m.39/41 içeriği |
| **R3** Raporlar menüsü: Aylık özet, Yıllık hesap, Daire ekstresi, İcra dökümü | Yol Haritası PDF | **Kısmen.** Var: yaşlandırma, gelir-gider, kasa durumu, daire ekstresi, kurul özeti (`finance_4b_routes.js` 437-443; PDF/CSV/Excel: `docs/PLATFORM_FINANS_4B.md` 165-175). "Aylık özet" ve "Yıllık hesap" adlı ayrı sayfa yok (gelir-gider ve kurul özeti bu işi görür). İcra dökümü: F8. | P2 | S | Yok |

### 7. Yönetim firması

| Konu | İstek (kaynak) | Bugün sistemde (var / kısmen / yok + kanıt) | Öncelik | Büyüklük | Karar ya da bilgi (kimden) |
| --- | --- | --- | --- | --- | --- |
| **Y1** "Tüm siteler" tablosu (firma sahibi; en kötü tahsilat oranı üstte) | Yol Haritası PDF Ekran 1 | **Yok.** Yol haritasında var: «Yönetim firması için "Tüm siteler" tablosu». Kanıt: firma/kurum kaydı yok (`management_company` araması sonuç yok; roller: `lib/models/user_role.dart`). Bir yönetici birden çok siteyi yönetebilir (`site_manager_sites`, `server/migrations/006_site_structure_and_access.sql`; `platform.json` F1.10). Apsiyon [A1] sitesinde yazıyor: yönetim firmaları için "Kurumsal" paket; çoklu site görünümünün ayrıntısı doğrulanamadı. | P2 | M | Cenk: yönetim firması tek kullanıcı mı, çok personelli kurum mu? |
| **Y2** Fiyat, 1–2 ay ücretsiz deneme, komisyon faturasıyla ortaklık payı, firmanın fiyatının bireysel yöneticiye de uygulanması, banka anlaşması | Kararlar 3 (Cenk; bilgi notu) | **Kısmen (şema var, iş yok).** `subscription_plans` (fiyat boş; "Standart" plan kapalı) ve `site_subscriptions` (durumlar: active, trial, past_due, cancelled, expired; bitiş tarihi) tabloları var (`server/migrations/033_site_applications.sql` 9-41). Yok: fiyat listesi, deneme bitişinde işlem, komisyon/ortaklık alanı, yönetim firması ilişkisi, ödeme ve fatura. Modül bugün süper kullanıcı onayıyla açılıyor (`docs/PLATFORM_MODUL_SISTEMI.md` 139-141). Bilgi notu: Apsiyon'un Apsis ürününde örnek fiyat 20 daire için yılda 3.240 TL + KDV (Apsiyon'un sitesinde yazıyor [A16]). | P3 | M | Cenk: fiyat listesi, deneme süresi, komisyon oranı ve faturası |

### 8. Hukuk ve hesaplar

| Konu | İstek (kaynak) | Bugün sistemde (var / kısmen / yok + kanıt) | Öncelik | Büyüklük | Karar ya da bilgi (kimden) |
| --- | --- | --- | --- | --- | --- |
| **H1** Yasal metinler: şirket bilgileri; ilk açılışta aydınlatma metni | Kararlar 1; Yol Haritası PDF Ekran 4 | **Yapıldı (Dalga 1, 2026-10-21; kod kısmı):** KEP ve MERSİS isteğe bağlı: boşken yasal metinlerde o satır ve cümleler hiç yazılmaz ve belge bu yüzden eksik sayılmaz (koşullu bölüm: `server/src/modules/legal_documents.js`; şablonlar `server/legal/*.md`); telefonun başındaki "+" artık metinde korunur; Platform Ayarları açıklaması ve alan ipuçları buna göre (`lib/ui/views/platform_settings_view.dart`). Yol haritasında var: «Yasal metinlerin yayını». Cenk'in verdiği unvan, adres ve telefon dağıtımdan sonra Platform Ayarları'na girilir; kvkk e-posta adresi bekleniyor (`docs/yasal/KULLANICIDAN_GEREKENLER.md` bölüm 1 "Durum"); sunucudaki değerlerin girilip girilmediği bu belgede doğrulanmadı. Aydınlatma metni kapısı kodda hazır, `legal.enforce_consents` kapalı. Deneme: F29.01–F29.05. | P0 | S | Cenk: KEP, MERSİS, kvkk e-posta adresi. Salih: Platform Ayarları'na giriş |
| **H2** Kayıtların saklama süreleri; saklama yönetim firmasının Drive'ında, şifreli; yedekler ayrı (fotoğraf ayrı, log/kayıt ayrı); veri çalınırsa firma sorumlu olmasın | Kararlar 2 (Cenk; süre alanı boş) | **Kısmen.** Önerilen süreler yazılı ama kesin değil: aidat/borç ve ilişki geçmişi 10 yıl, araç kaydı pasifleşince 1 yıl, duyuru 5 yıl, denetim kaydı 5 yıl (`docs/yasal/KULLANICIDAN_GEREKENLER.md` 58-59, 82); otomatik silme işi yok (aynı belge 59). Sunucu yedekleri zaten ayrı şifreli arşivler: veritabanı, belgeler, iş takibi fotoğrafları (`docs/OPERASYON_YEDEK_IZLEME.md` 23-24, 84). Veritabanı (finans defteri) Drive'a konmuyor; Cenk'in "saklama tamamen yönetim firmalarının Drive'ında" ifadesi bunu da kapsıyorsa fark var. | P0 | M | Cenk: süreler; veritabanı da Drive'a mı? Avukat: "veri çalınırsa firmamız sorumlu olmasın" ifadesi mümkün mü (veri sorumlusu/işleyen) |
| **H3** Gecikme tazminatı ve borç hatırlatma: avukata sorulacak taslak (biz hazırlamalıyız) | Kararlar 4 (Cenk) | **Yapıldı (Dalga 1, 2026-10-21; taslak):** avukata gidecek taslak `docs/yasal/AVUKATA_GECIKME_HATIRLATMA_MAKBUZ.md`: kanun metinleri (KMK m.20/2 ve m.22/1, TBK m.100-104, 6563 m.2/1-c; resmî metinden), sistemin koduyla doğrulanmış beş örnek hesap, borç hatırlatma e-postası ve makbuz metni, dönem kapsamı sorunu (Örnek 4: zamanında ödeyen yeni kiracıya 50,00 TL tazminat) ve 18 soru; hukuki iddialar `[AVUKAT DOĞRULASIN]` işaretli. Hesap ve e-posta kodu hazır ama avukat onayına kadar KAPALI (`finance.legal_ok`); dönem kapsamı kuralı onaydan sonra koda yazılacak. Cenk'in iletmesi bekleniyor. Deneme: F29.06, F29.07. | P0 | S | Cenk: taslağı avukata iletmek. Avukat: onay → `finance.legal_ok` |
| **H4** Elektronik genel kurul: taslak metin (Cenk kontrol ettirip avukata soracak) | Kararlar 12 | **Yapıldı (Dalga 1, 2026-10-21; taslak):** `docs/yasal/E_GENEL_KURUL_TASLAGI.md`: mevzuat durumu (KMK'da elektronik toplantı hükmü yok; doğrulananlar, ikincil kaynak ve doğrulanamayanlar ayrı), önerilen akış, toplantı çağrısı / vekâletname / hazirun cetveli / karar tutanağı / sonuç bildirimi taslakları ve 11 soru. E-genel kurul modülü yine yok: Karar Defteri yalnız kararı kaydeder (toplantı türü `genel_kurul`: `server/migrations/050_decision_book.sql`); sistem planı taslağın 4. bölümünde; `platform.json` F11.02 yakinda. Deneme: F29.06, F29.07. | P2 | M | Cenk: taslak istiyor. Avukat: elektronik genel kurulun mevzuat koşulları (bu belgede doğrulanamadı) |
| **H5** Mağaza ve geliştirici hesapları (Google Play, App Store); taslak/örnek çalışma | Kararlar 5 | **Yapıldı (Dalga 1, 2026-10-21; rehber):** `docs/MAGAZA_VE_BILDIRIM_HESAPLARI_REHBERI.md`: toplanacak bilgiler, D-U-N-S numarası, Apple ve Google Play kuruluş hesabı, Firebase (telefon bildirimi) ve Google Cloud (Drive onay ekranı) adımları, ücret ve süre özeti, kim ne yapar; kaynaklarıyla. Uygulama yükleme adımları `docs/YAYIN_HAZIRLIGI.md`'de; Android paket adı `tr.com.gudeteknoloji.siteyonetim`. Hesapları açmak Cenk'te; iOS Team ID henüz yok. Yayın, yasal metinlerin tamamlanmasına bağlı. Deneme: F29.08. | P1 | S | Cenk ve Salih: hesapları açmak |
| **H6** "Apple hesabını açarız, şirket adına olması şart mı?" | Kararlar 6 | **Yapıldı (Dalga 1, 2026-10-21; bilgi, kod değil):** yanıt rehberin başında ("Kısa yanıt", `docs/MAGAZA_VE_BILDIRIM_HESAPLARI_REHBERI.md`): şart değil, ama bireysel hesapta App Store'da kişinin yasal adı görünür; şirket adına kuruluş hesabı önerilir (tüzel kişilik, D-U-N-S numarası, şirket alan adlı iş e-postası ve çalışan web sitesi gerekir). Güde bir limited şirket; D-U-N-S numarası olup olmadığı doğrulanamadı. Google Play'de 13 Kasım 2023'ten sonra açılan KİŞİSEL hesaplar yayından önce 12 test kullanıcısıyla 14 gün kapalı test yapmak zorundadır; sayfa bu şartı kuruluş hesapları için yazmıyor. Deneme: F29.08. | P1 | S | Cenk: karar (öneri: şirket adına, mağazada "Güde Teknoloji" görünür). Bilgi: D-U-N-S var mı? |

### 9. Drive ve yedek

| Konu | İstek (kaynak) | Bugün sistemde (var / kısmen / yok + kanıt) | Öncelik | Büyüklük | Karar ya da bilgi (kimden) |
| --- | --- | --- | --- | --- | --- |
| **D1** Sitenin yüklediği her dosya sitenin Drive'ında; sunucuda gerekli bağlantı dursun ("Teklif Pro'daki Drive saklama sistemi gibi") | Kararlar 13 (Cenk) | **Plan var, kod yok.** Yol haritasında var: «Sitenin dosyaları sitenin Google Drive'ında». `docs/PLATFORM_DRIVE_DEPOLAMA.md` durum satırı: "plan, kod yazılmadı"; dosyalar bugün sunucu diskinde (`server/src/modules/document_storage.js`). Fark: Cenk "sunucuda yalnız bağlantı" diyor; önerilen model C sunucuda sabit önbellek ve küçük bekleme alanı tutuyor (aynı belge bölüm 3). | P1 | L | Cenk: model C kabul mü; "Teklif Pro" sisteminin tarifi (depoda yok, doğrulanamadı). Avukat: KVKK m.9 |
| **D2** Dosyalar şifreli durmalı ("şifrelenmiş şekilde kendi sistemlerinde") | Kararlar 2 | **Yok.** Planda yalnız Drive yenileme anahtarı şifreli (`PLATFORM_DRIVE_DEPOLAMA.md` 121); dosya içeriği şifrelemesi yok. İçerik şifreli olursa Drive'da önizleme/arama çalışmaz; anahtarı biz tutarsak "firma sorumlu olmasın" ifadesi zayıflar. | P2 | M | Cenk ve Salih: şifreleme dosya içeriği için mi isteniyor? |
| **D3** Veritabanının dış kopyası | Kararlar 13 (Salih) | **Var (2026-10-21).** Şifreli günlük yedek her gün geliştirici bilgisayarına çekiliyor (`KapiYedekCek` görevi, `G:\kapi-yedek`); betikler `deploy/ops/pull_backups_windows.ps1`, `deploy/ops/offsite_push.sh`. | P0 | S | Karar kaydı D3 |

### 10. Apsiyon'da olup işveren belgelerinde olmayanlar (şimdilik önerilmez)

| Konu | İstek (kaynak) | Bugün sistemde (var / kısmen / yok + kanıt) | Öncelik | Büyüklük | Karar ya da bilgi (kimden) |
| --- | --- | --- | --- | --- | --- |
| **Z1** Ücretli tesis rezervasyonu (online ödeme); rezervasyon süresine bağlı kart/QR geçişi | Apsiyon [A9] | **Yok.** Rezervasyon şemasında ücret alanı yok (`server/src/modules/reservation_schema.js` içinde ücret/ödeme araması sonuç yok); `card_access` dosyalarında rezervasyon geçmiyor. | P3 | M | Cenk (bağlı: F6) |
| **Z2** Muhasebe: tek düzen hesap planı, yevmiye; işletme defterinin noterli basımı | Apsiyon [A13], [A4] | **Yok.** `hesap planı`, `yevmiye` araması sonuç yok; raporlar yasal defterin yerine geçmez diyor (`docs/PLATFORM_FINANS_4B.md` 18). | P3 | L | Cenk + avukat |
| **Z3** Tur kontrol (NFC/QR noktaları) | Apsiyon [A10] | **Yok.** `tur kontrol`, `patrol`, `checkpoint` araması ilgili sonuç vermedi. | P3 | L | Cenk |
| **Z4** Sakinler için ücretsiz web sayfası (duyuru, galeri, forum) | Apsiyon [A15] | **Yok.** Ayrı sakin web sayfası yok; Flutter uygulaması web'de de çalışır (`web/index.html`). | P3 | L | Cenk |
| **Z5** Santral Plus (gelen aramada sesli borç bildirimi); mobil tahsilat cihazı | Apsiyon [A12], [A13], [A14] | **Yok.** Donanım/telefon altyapısı işi. | P3 | L | Cenk |
| **Z6** Yapay zekâ asistanı (WhatsApp; ADA, ASYA) | Apsiyon [A17] | **Yok.** | P3 | L | Cenk |
| **Z7** Sigorta, kampanya, kira sözleşmesi, yönetim firması bulma pazaryeri | Apsiyon [A3], [A18], [A20] | **Yok.** Satış modeli işi; işveren belgelerinde istek yok. | P3 | — | Cenk |
| **Z8** Firma (tedarikçi) bazlı cari dökümü | Apsiyon [A2] ("cari izleme") | **Kısmen.** Tedarikçi kaydı ve gider listesinde tedarikçi süzgeci var (`docs/PLATFORM_FINANS_4B.md` 147-149); firma bazlı özet ekranı doğrulanamadı. | P3 | S | Cenk |

### 11. Zaten karşılanan istekler (yanlış eksik sayılmasın)

| Konu | İstek (kaynak) | Kanıt |
| --- | --- | --- |
| **K1** Silinemez defter; düzeltme ters kayıtla | komutlar talimat 1; Yol Haritası PDF | `ledger_entries` değiştirilemez/silinemez (`server/migrations/034_finance.sql` 5 ve 92-132); ters kayıt: `POST .../entries/:id/reverse` (`docs/PLATFORM_FINANS.md` 53); uygulamada "Düzelt / İptal Et" (aynı belge 109). |
| **K2** Aidat dağıtımı: sabit, eşit, kategori, arsa payı, m² (brüt/net) | komutlar Adım 2; Apsiyon [A4] | `fee_definitions.distribution` (`034_finance.sql` 31); "en büyük kalan" bölme (`server/src/modules/finance_distribution.js` 59). |
| **K3** Gecikme aylık en çok %5, tazminat tabana girmez (faiz üstüne faiz yok) | komutlar Adım 2 | `server/migrations/040_finance_4b.sql` 11 ve 23; `server/src/modules/finance_late_fee_calc.js` 6. Kapalı: hukuk onayı bekliyor (H3). |
| **K4** Makbuz, kasa/banka, aktarım, mutabakat, gider + belge, borç hatırlatma e-postası | Yol Haritası PDF Ekran 3 | `040_finance_4b.sql` (receipts, finance_accounts, account_reconciliations, expenses, finance_reminder_runs). |
| **K5** Raporlar: yaşlandırma, gelir-gider, kasa durumu, daire ekstresi, kurul özeti; PDF/CSV/Excel | Yol Haritası PDF (Raporlar) | `server/src/modules/finance_4b_routes.js` 437-443; `finance_export_tables.js`; `lib/services/pdf_finance_service.dart`. |
| **K6** Daire künyesi (brüt/net m², arsa payı, kategori); malik ve kiracı ilişkisi ayrı kayıtlı | Yol Haritası PDF (Daireler) | `docs/PLATFORM_FINANS.md` 3; `platform.json` F2.05. (Bakiyenin ikiye ayrılması: G12.) |
| **K7** Sakin: Borcum, ekstre, makbuz | Yol Haritası PDF Ekran 4 | `lib/ui/views/my_finance_view.dart`; yol haritası 1. bölüm «Borcum sakin kapsamı». |
| **K8** Arıza/talep: fotoğraflı, atama, durum izleme, performans raporu | Yol Haritası PDF Ekran 4 | Durumlar yeni, işlemde, beklemede, çözüldü, kapandı, iptal ve atama (`server/migrations/042_work_tracking.sql` 24, 37); fotoğraf eki `047_work_attachments.sql`; `server/src/modules/work_tracking_report.js`. |
| **K9** Rezervasyon ve konsiyerj, anket, ziyaretçi ve kargo, firma ve sözleşme, karar defteri (yıl PDF'i) | Apsiyon [A1], [A3] | `server/src/modules/catalog.js`; migration 043-050; `lib/services/pdf_decision_service.dart`. |
| **K10** Kapı: telefondan açma, karekod, misafir geçişi (Ziyaretçi Kodu), kartlı geçiş | komutlar Kural 3 | Migration 008, 011-015, 046; `catalog.js` 114-121. |
| **K11** Onay bekleyen kişiler (katılım isteği) | Apsiyon [A2] | `lib/ui/dialogs/manage_join_requests_dialog.dart`; `server/migrations/019_join_requests_notes.sql`. |
| **K12** Yönetim türleri: önce apartman/site, rezidans, kooperatif; AVM en son | Kararlar 11 | Beş tür seçilebilir (`docs/PLATFORM_MODUL_SISTEMI.md` 166-180); türe özel ileri özellikler `platform.json` F9.01–F9.04 yakinda. |
| **K13** Yedekler ayrı ve şifreli (veritabanı, belgeler, iş takibi fotoğrafları) | Kararlar 2 | `docs/OPERASYON_YEDEK_IZLEME.md` 23-24 ve 84. |
| **K14** Hesap silme, veri dışa aktarma, yardım ve tanıtım turu | Yol Haritası PDF Ekran 4 | `platform.json` F12 ve F16 bölümleri. |
| **K15** Kaynak kodun gizliliği | Kararlar 14 | Bu dosyanın 6. bölümünde işaretli (2026-10-20). |

### Karar kaydı (2026-10-21)

Kaynak: Cenk'in 2026-10-19 belgesindeki kırmızı yanıtlar ve `komutlar.txt` talimatları. Yanıtı boş kalan ya da iki belgenin ayrıştığı
yerlerde karar, gerekçesiyle ekip tarafından verildi (Salih, 2026-10-21: "başka karar isteme, ne gerekiyorsa yap"). Yukarıdaki
tablolardaki "Karar ya da bilgi" sütunu tarihçe olarak kaldı; geçerli olan bu kayıttır. Hukuki maddeler avukata gidecek taslaklarda
`[AVUKAT DOĞRULASIN]` işaretiyle yazılır; avukat onayına kadar ilgili özellik kapalı kalır. Dışarıdan hesap ya da sözleşme gerektiren
özelliklerin temel yapısı hazırlanır ve uygulamada "Yakında…" etiketiyle durur.

| Kod | Karar | Dayanak |
| --- | --- | --- |
| G6, G7 | Tasarım dili `komutlar.txt`'deki sade stil: zemin #F8FAFC; kart beyaz, ince #E2E8F0 çerçeve, gölgesiz; metin #475569; ana onay düğmesi ve kritik uyarı #0F172A, düz (parlaksız). Durum, metnin solunda küçük nokta (● #10B981 / #F59E0B / #E11D48); zemin boyanmaz. Mavi yalnız bağlantı ve odak halkasında. Koyu tema erişilebilirlik için kalır. Kapı düğmesinin görünüşü ve kapı akışı değişmez. | Cenk: komutlar Kural 1, renk tablosu, talimat 3 |
| G8 | İkon seti Phosphor, "regular" ağırlık (24 px'te 1,5 px çizgi). Önce menü, alt çubuk ve vitrin; kalan ekranlar kademeli. | Cenk: komutlar bölüm 2 ("Lucide ya da Phosphor"); Phosphor'un regular çizgisi talimattaki 1,5 px'e birebir uyar |
| G9 | Beyaz etiket yapılır: yönetim firması başına 5 renk, logo ve uygulamada görünen ad; varsayılan Güde teması. | Cenk: komutlar bölüm 2 ("beyaz etiket yapısı … ayrı tema") |
| G2 | Menü PDF'teki 7 başlıkla gruplanır: Ana sayfa · Daireler · Borçlar · Tahsilat · Giderler · İletişim · Raporlar. Bizdeki ek modüller (Kapılar, kartlı geçiş, ziyaretçi ve kargo, rezervasyon, sözleşmeler, karar defteri, belgeler, sayaç, ekipman) 8. başlık "Site hizmetleri" altında. Ayarlar sağ üstte dişli. Kullanıcıya tanımlı öğesi olmayan başlık görünmez. | Cenk: Yol Haritası PDF (Menü); 8. başlık bizdeki fazla modüller için |
| G3 | Sakin alt çubuğu: Özet · Duyuru · Arıza · Kapı · Belgeler. Uygulama Özet'te açılır (en üstte borç kartı ve "Öde"). Kapı sekmesi yalnız kapı yetkisi olana görünür; olmayanda PDF'teki dört sekme kalır. Modülü kapalı sekme görünmez. | İki belgenin birleşimi: PDF Ekran 4 (Borcum, Duyuru, Arıza, Belgeler), komutlar Ekran 3 (Özet, Arıza, Kapı, Belge); alt çubukta en çok 5 sekme |
| G11 | Kurallar tablosu: "%5 gecikme", "90 gün geçici bütçe", "itiraz süresi", "%70/%30 ısı payı" gibi değerler koddan değil tablodan okunur; her kuralın geçerlilik tarihi ve mevzuat notu olur. Yasal üst sınır (ör. aylık %5) site ayarıyla aşılamaz. | Cenk: komutlar talimat 4 |
| G12 | Her dairenin iki ayrı hesabı olur: Kiracı hesabı ve Ev sahibi hesabı; bakiyeler karışmaz. Aidat ve işletme giderleri daire kiradaysa kiracı hesabına, değilse ev sahibi hesabına yazılır; demirbaş, yatırım, büyük onarım ve devir bakiyesi ev sahibi hesabına (borç tanımında değiştirilebilir). Tahsilat, ödeyenin hesabına yazılır. Sakin yalnız kendi hesabını görür; yönetici iki hesabı iki sekmede görür. Bugünkü kayıtlar dairenin "kim öder" bilgisine göre ilgili hesaba aktarılır. | Cenk: komutlar talimat 2 ve Adım 1; TBK m.341 (yan giderler kiracıda), KMK m.22 (kiracının sorumluluğu) `[AVUKAT DOĞRULASIN]` |
| F1 | Sakine ödeme bilgisi: sitenin IBAN'ı, alıcı adı ve referans kodu, kopyala düğmeleriyle. Referans biçimi `GUL-A2-1026`: site kısa kodu (3 harf; yönetici değiştirebilir, sistemde tekil) - blok ve daire - ay ve yıl. Eşleme dönemli ve dönemsiz kodu tanır; boşluk, tire ve harf büyüklüğü fark etmez. IBAN kasa/banka hesabına girilir ve TR IBAN denetiminden geçer. | Cenk: Yol Haritası PDF Ekran 4 ve örnek kod |
| F2 | Dekontla ödeme Cenk'in tarif ettiği gibi: sakin dekontu uygulamadan yükler ya da telefondan "Paylaş" ile gönderir; kayıt geçici kabule düşer, yöneticiye bildirim gider; yönetici karşılaştırma bilgisine bakıp onaylar ya da iptal eder (toplu da). Sakin yapamıyorsa yönetici elden makbuz/dekont girer; o da geçici kabulden geçer. Geçici kabuldeki tutar deftere yazılmaz, bakiye düşmez; sakin borç kartının altında "İnceleniyor: 1.250 TL" görür. Onayda deftere dekont tarihiyle tahsilat ve makbuz yazılır; iptalde neden sakine gösterilir. Yanlış daireye karşı: karşılaştırmada dekonttaki ad, IBAN ve açıklama ile dairenin kişileri, referans kodu ve açık borç yan yana durur; uyuşmazlıkta uyarı verilir. | Cenk: Kararlar 7. Bakiyenin düşmemesi: doğrulanmamış tahsilat kayda alınmaz |
| F3 | Banka dosyası: Excel, CSV ve MT940. Bankaya göre sütun eşlemesi bir kez seçilir ve o hesap için hatırlanır. Eşleme sırası: referans kodu → açıklamadaki daire kodu → IBAN hafızası → gönderen adı → bekliyor. IBAN hafızası daireyle birlikte hesabı (kiracı / ev sahibi) da tutar. Gerçek ekstre örneği beklenmez; yaygın biçimlerle yapılır, örnek gelince test eklenir. | Cenk: komutlar Kural 2 ve Ekran 2; Yol Haritası PDF Ekran 3 |
| F4 | Devir bakiyesi: kendi Excel şablonumuz (daire, hesap, tutar, vade, açıklama) ve başka dosyalar için sütun eşleme; önizleme ve tek onay; geri alma ters kayıtla. | komutlar Adım 3 ("Veri Göçü") |
| F5 | Altın veri seti: ekip gerçekçi bir site için elle hesaplanmış tablo hazırlar (eşit, m², arsa payı dağıtımı; gecikme; mahsup); sonuç kuruşu kuruşuna tutmazsa test düşer. Cenk'in gerçek tablosu gelince ikinci set olarak eklenir. | komutlar Adım 2; Yol Haritası PDF yapım sırası 2 |
| F6 | Kart ödemesi lisanslı bir ödeme kuruluşuyla; para doğrudan sitenin hesabına (alt üye işyeri modeli). Kart komisyonu ödeyene yansır ve ödemeden önce gösterilir; FAST/havale komisyonsuz kalır. Şimdilik sağlayıcıdan bağımsız arayüz hazırlanır ve "Yakında…" kalır; sözleşme yapılınca bağlanır. | Cenk: Kararlar 7 ("site yönetiminin banka hesabına"); 6493 sayılı Kanun |
| F7 | İşletme projesi: Taslak → Tebliğ → Kesin. Onaylı proje yoksa geçici proje en çok 90 gün; kalan gün yöneticinin dikkat barında. Süreler kurallar tablosundan. Planlanan–gerçekleşen karşılaştırması. | komutlar Adım 2 ve Ekran 1; KMK m.37 (7579 sayılı Kanunla değişik) `[AVUKAT DOĞRULASIN]` |
| F8 | İcra dökümü: daire ve hesap bazında PDF (kesinleşmiş proje ya da kurul kararı bilgisi, ödenmemiş kalemler, varsa gecikme tazminatı) ve avukat için Excel listesi. | komutlar Adım 4; İİK m.68 `[AVUKAT DOĞRULASIN]` |
| R1 | Giderde "rutin / beklenmedik" işareti: sözleşmeli ve her ay tekrar eden gider kendiliğinden "rutin" önerilir, yönetici değiştirebilir. Gider ekipmana bağlanabilir (asansör, interkom, kamera, bariyer, yangın algılama…); ekipman başına yıllık maliyet çıkar. Aylık, 3, 6 ve 12 aylık grafik. Gelecek yıl tahmini: son 12 ayın kategori toplamları ile yöneticinin girdiği artış oranı (varsayılanı kurallar tablosunda), üstüne beklenmedik giderlerin ortalaması. | Cenk: "Sistemde görmediklerim" 2 |
| R2 | Faaliyet raporu bölümleri: genel bilgiler; mali durum (gelir-gider, bütçe karşılaştırması); tahsilat ve borçlar; yapılan işler (iş takibi, fotoğraflarıyla); bakım ve ekipman; sözleşmeler; kararlar; duyurular; gelecek yıl tahmini. Sistem taslağı kayıtlardan doldurur, yönetici her bölümü değiştirir, PDF alınır. | Cenk: "Sistemde görmediklerim" 1; KMK m.39 ve 41 |
| T1–T5 | Sayaç okuma Cenk'in tarifi gibi: uzaktan okuyan sayaç için dosyadan ya da bağlantıdan içe aktarma. Elle okumada görevli saati fotoğraflar; sistem değeri ve (saatte yazıyorsa) daire numarasını okur; kamera kapanmaz, ekranın üstünde sıradaki daire yazar; internet yoksa fotoğraflar telefonda bekler, gelince Drive'a gönderilir. Okuma telefonda yapılır (internetsiz çalışsın diye); okunan değeri görevli onaylar ya da düzeltir, yönetici sonradan düzeltirse kaydı tutulur. Dosya adı `AB_D13_201026` (A blok, daire 13, 20.10.2026). Drive klasörleri `SrvEkim_26`, `suEkim_26`, `elektrikEkim_26`, `TeklifEkim_26`; diğer türler aynı kalıpla (`isiEkim_26`, `GiderEkim_26`, `DekontEkim_26`, `BelgeEkim_26`). Sistemde yalnız kayıt (log) tutulur. Isı payı %70 ölçüm, %30 m². | Cenk: Kararlar 8; ısı payı yönetmeliği (RG 26847) doğrulanacak |
| T6 | Teklifler "Giderler" altında: konu, firma, tutar, geçerlilik, belge (Drive `TeklifEkim_26`); yan yana karşılaştırma; kabul edilen teklif gidere ya da sözleşmeye dönüşür. | Cenk: Kararlar 8 (TeklifEkim) |
| T7 | Ekipman ve bakım: varsayılan türler asansör, interkom, kamera, bariyer, yangın algılama, hidrofor, jeneratör, kazan, havuz; bakım aralığı (aylık, 3, 6, 12 ay) varsayılanla gelir, yönetici değiştirir; yasal periyodik kontrol hatırlatması (ör. asansör yılda bir). | Cenk: "Sistemde görmediklerim" 2 |
| T8 | Kamera ve plaka tanıma: Hikvision için üreticinin ISAPI arayüzü, Tiandy ve yerli markalar için ONVIF. Kamera olayı sunucuya gönderir; sunucu plakayı sitenin araç listesiyle karşılaştırır. Şimdilik cihaz kaydı, üreticiye göre bağdaştırıcı ve olay ucu ("Yakında…"); saha denemesi donanım gelince. | Cenk: Kararlar 9 |
| C1, S1, S3 | Kararlar 10'un yanıtı boş kaldığı için belgedeki öneri uygulanır: önce ücretsiz telefon bildirimi ve e-posta; SMS isteğe bağlı ücretli ek modül (maliyet siteye). Sağlayıcıdan bağımsız arayüz; ilk bağdaştırıcı yaygın bir yerli SMS firması; hesap açılana kadar "Yakında…". Telefon + SMS koduyla şifresiz giriş SMS açılınca çalışır. Kargo geldi bildirimi telefon bildirimi ve e-postayla. WhatsApp: KVKK m.9 netleşene kadar yalnız arayüz. | Kararlar 10'daki öneri (yanıt boş) |
| H1 | Platform Ayarları'na Cenk'in verdiği bilgiler girilir: GÜDE TEKNOLOJİ LTD. ŞTİ., Yalı Mah. 6436 Sok. No:37/A Karşıyaka / İzmir, 0543 795 60 44. KEP ve MERSİS boş kalır; boş alan metinlerde görünmez. | Cenk: Kararlar 1 |
| H2 | Saklama süreleri (avukata gidecek taslak; otomatik silme avukat onayına kadar kapalı): mali kayıtlar (borç, tahsilat, makbuz, gider belgesi, banka dosyası, dekont) 10 yıl; taşınan kişinin iletişim bilgileri, açık borcu yoksa 1 yıl sonra silinir; kapı geçiş ve ziyaretçi kayıtları 1 yıl; iş takibi fotoğrafları talep kapandıktan 2 yıl sonra; duyurular ve denetim kaydı 5 yıl; karar defteri süresiz. Sorumluluk: veri sorumlusu site yönetimi, Güde veri işleyen; veri işleme sözleşmesi sorumluluğu paylaştırır (KVKK m.12/2 nedeniyle tam muafiyet yazılamaz; ağır kusurdan önceden sorumsuzluk TBK m.115'e göre geçersizdir). Şifreleme: Drive'daki dosyalar Google'ın kendi şifrelemesiyle durur, aktarım TLS ile; veritabanı yedekleri ayrıca şifreli. Dosya içeriği ayrıca şifrelenmez (anahtar kaybolursa dosyalar açılamaz, önizleme çalışmaz). Yedekler ayrı: fotoğraflar, belgeler ve veritabanı/kayıtlar ayrı arşivlerde (bugün de böyle). | Cenk: Kararlar 2 (süre boş); TTK m.82 (10 yıl), VUK m.253 (5 yıl) `[AVUKAT DOĞRULASIN]` |
| H3, H4 | Avukata gidecek taslakları ekip yazar: gecikme tazminatı, borç hatırlatma ve makbuz için "örnek hesap + sorular"; elektronik genel kurul için taslak metin ve soru listesi. | Cenk: Kararlar 4 ve 12 |
| H5, H6 | Mağaza hesapları şirket adına (kuruluş hesabı; Apple için D-U-N-S numarası ücretsiz alınır). Cenk ve Salih için adım adım rehber ekip hazırlar. Apple sorusunun yanıtı: şart değil, ama kişisel hesapta mağazada kişinin adı görünür; şirket adına önerilir. | Cenk: Kararlar 5 ve 6 |
| D1, D2 | Drive modeli C: sunucuda kalıcı dosya yok; yalnız üst sınırı sabit önbellek ve bağlantı kopukken kısa bekleme alanı; asıl kopya sitenin Drive'ında. "Teklif Pro" tarifi beklenmez: aynı ilke uygulanır (dosya Drive'da, sistemde bağlantı ve kayıt). Şifreleme H2'deki gibi. Drive bağlanana kadar dosyalar bugünkü gibi sunucuda kalır. | Cenk: Kararlar 13 |
| D3 | Veritabanının dış kopyası: şifreli günlük yedekler her gün Türkiye'deki geliştirici bilgisayarına çekilir (hazır betik `deploy/ops/pull_backups_windows.ps1`, zamanlanmış görev); Güde'nin Drive hesabı bağlanınca ikinci kopya oraya. | Kararlar 13 (Salih); kopya Türkiye'de kaldığı için yurt dışına aktarım (KVKK m.9) doğmaz |
| G13 | Satır düzeyi güvenlik (RLS) şimdilik yok; site yalıtımı uygulama katmanında kalır ve her yeni uç için "başka sitenin kimliğiyle erişim reddedilir" testi zorunlu. | Canlı sistemde bütün sorguların değişmesini gerektirir; yalıtım bugün testlerle korunuyor |
| Y1 | Yönetim firması çok personelli kurum: firma kaydı, firma sahibi ve personel, firmaya bağlı siteler. Firma sahibi "Tüm siteler" tablosunu görür (en düşük tahsilat oranı en üstte). | Yol Haritası PDF Ekran 1; Kararlar 3 (yönetim firmaları asıl müşteri) |
| Y2 | Deneme süresi ayarlanabilir (ilk kullananlara 1–2 ay; varsayılan 60 gün). Yönetim firmasının ortaklık payı oranı firma kaydında, aylık pay dökümüyle. Bireysel yöneticiye aynı fiyat listesi. Fiyatlar depoya yazılmaz, süper kullanıcı girer. Banka anlaşması iş geliştirme konusu (kod yok). | Cenk: Kararlar 3 |
| S4, S5, S6 | Rehber (yönetim kadrosu ve faydalı telefonlar) yapılır. Komşu panosu yönetici onaylı ilan olarak yapılır (şikâyet ve kaldırma düğmesiyle). Çok dil için altyapı kurulur (Türkçe + İngilizce iskelet); tam çeviri sonra. | Apsiyon [A3]; işveren belgelerinde istek yok, düşük öncelik |
| G4, G5 | Sakin ana ekranı: koyu "Güncel toplam borcunuz" kartı ve "Öde" (F1 ödeme bilgisi + dekont yükleme); altında Arıza Bildir, Ziyaretçi Kodu, Belgeler. Yönetici ana sayfası: dört sayı, beş adımlı aylık döngü, koyu dikkat barı (bekleyen dekont, eşleşmeyen banka satırı, geçici bütçede kalan gün), son beş para hareketi. | komutlar Kural 3, Ekran 1 ve 3; Yol Haritası PDF Ekran 1 ve 4 |
| G10, G14, R3 | Ekranda "tahakkuk, mutabakat, cari" yerine yöneticinin dili ("borç yazma", "banka / kasa kontrolü"); her listede arama ve Excel'e aktar; rapor adları PDF'teki gibi (Aylık özet, Yıllık hesap, Daire ekstresi, İcra dökümü). | Yol Haritası PDF |
| G15 | İki haftada bir yapılacak canlı demo için demo senaryosu belgesi hazırlanır. | komutlar talimat 5 |
| Z1–Z8 | Bu turda yapılmaz: işveren belgelerinde istenmedi (Apsiyon'a özgü ek hizmetler). | Kapsam |

### Faz Kontrol Listesi notlarından gelen işler (2026-10-21)

Faz Kontrol Listesi sayfasında maddelere yazılmış, yanıtlanmamış notlar (2026-10-16/19). Her biri bir işe bağlandı; sayfadaki notlara
Claude yanıtı yazıldı.

| Kod | İş | Not (madde) | Dalga |
| --- | --- | --- | --- |
| N1 | Duyurular: sakin girer girmez Panel'in en üstünde okunmamış duyuru kartı, yanıp söner (hareket azaltma açıksa sabit vurgu); okununca Panel'den kalkar, Duyurular'da kalır. Alıcı duyuruyu kendi listesinden siler; yönetici duyuruyu siler (listelerden kalkar, kayıt yasal süre boyunca arka planda saklanır). | F3.03, F3.04 | 2 |
| N2 | Yönetim kadrosu: kişi kartından "Görev ver" (yönetim kurulu üyesi; görevli: kapıcı, teknik, danışma) ve tek sayfada yönetici, kurul ve görevliler. Kimseye görev verilmezse işler yöneticide kalır. Bugün görev atama Modüller ekranındaki "Ek roller"de, e-postayla; bulunması zor. | F2.02, F2.15, F1.12 | 2 |
| N3 | Kişiye uygulama daveti: e-postası olan her kişiye (dolu daire dahil) "Uygulamaya davet et"; kişi şifresini kendisi belirler. E-postası olmayan kişi telefon + SMS koduyla girer (S1, SMS ek hizmeti açılınca); o zamana kadar ekranda açık not. | F2.03 | 2 |
| N4 | Ay kapatma: yönetici istediği ayı seçip kapatır (önceki açık aylar birlikte kapanır); "sırayla kapat" zorunluluğu ve baskı yapan uyarılar kalkar; kapatmak isteğe bağlıdır. | F4.15 | 2 |
| N5 | Hesap silme engeli: kayıtlı sitesi olan yönetici siteyi devretmeden ya da kapatma talebi göndermeden, borcu olan sakin borcu kapanmadan hesabını silemez; ekranda nedeni ve yolu yazar. `[AVUKAT DOĞRULASIN]` (KVKK m.11 ve m.13: gerekçeli yanıt). | F12.08 | 2 |
| N6 | Tek dosyada toplu yükleme: "Hepsi bir arada" Excel şablonu (daire, sakin ve ilişkisi, telefon, e-posta, taşınma tarihi, plaka, not); önizleme ve onay. | F13.02 | 2 |
| N7 | F1.20 deneme maddesi sade dille yeniden yazıldı (API adımı yerine ekran adımları). | F1.20 | yapıldı |
| N8 | Telefon bildirimi: Firebase'in bildirim hizmeti ücretsiz; hesap açılınca devreye alınır (hatırlatma). Web uygulaması için Firebase'siz tarayıcı bildirimi. | F1.30, F3.01 | hesap: dışarıdan; web bildirimi: 5 |
| N9 | Destek e-postası, telefonu ve çalışma saatleri Platform Ayarları'na girilecek (hatırlatma). | F12.44 | dışarıdan |
| N10 | Tanıtım turu yeni Panel'i (modül kartları, Kapılar, gruplu menü, sakin alt çubuğu) anlatır. | F12.36 | yapıldı (1D) |

### Uygulama sırası (2026-10-21)

Her dalga ayrı ajanlarla ve bağımsız incelemeyle yapılır (para, yetki ve veri işlerinde en az iki tur ve gerçek PostgreSQL denemesi).
Dalga bitince canlıya alınır, deneme maddeleri Faz Kontrol Listesi sayfasına eklenir. Yeni modüller varsayılan kapalı gelir. Ayrıntılı
iş planı: `docs/superpowers/plans/2026-10-21-eksik-listesi-programi.md`.

| Dalga | İçerik | Durum |
| --- | --- | --- |
| 0 | G1 Panel modül vitrini | son düzeltme turunda; ardından canlı |
| 1 | G12 iki hesap · G11 kurallar tablosu + F5 altın veri seti · G6 + G7 sade tasarım · G2 + G3 gruplu menü ve sakin alt çubuğu · H1–H6 ve G15 hukuk taslakları, hesap rehberleri, demo senaryosu · D3 dış kopya (kuruldu 2026-10-21) | tamamlandı, canlıya alınıyor |
| 2 | F1 + G4 IBAN, referans kodu, "Öde" · F2 dekont ve geçici kabul · F3 banka dosyası ve IBAN hafızası · F4 + N6 devir bakiyesi ve tek dosyada toplu yükleme · R1 gelir-gider analizi, grafik ve tahmin · G5 + N4 yönetici ana sayfası, dikkat barı ve ay kapatma · N1 duyurular · N2 + N3 + S5 yönetim kadrosu, uygulama daveti ve rehber · N5 hesap silme engeli | temel yapı tamamlandı (2026-10-21): A ve B aşamaları |
| 3 | F7 işletme projesi · T7 ekipman ve bakım + T6 teklifler (R1'e ekipman kırılımı) · R2 faaliyet raporu · F8 icra dökümü · G10 + G14 + R3 sade dil, Excel'e aktar, rapor adları | temel yapı tamamlandı (2026-10-21): A ve B aşamaları |
| 4 | D1 Drive bağlantısı · T1–T5 sayaç, fotoğrafla okuma, çevrimdışı kuyruk, adlandırma · T2 ısı payı | temel yapı tamamlandı (2026-10-21): A ve B aşamaları |
| 5 | Y1 + Y2 yönetim firması, deneme süresi, ortaklık payı · C1 + S1 + S3 SMS arayüzü, SMS ile giriş, kargo bildirimi; web için Firebase'siz tarayıcı bildirimi (N8) · S4 komşu panosu | temel yapı tamamlandı (2026-10-21): yönetim firması, SMS ve tarayıcı bildirimi, komşu panosu |
| 6 | G8 + G9 Phosphor ikonları ve beyaz etiket · F6 + T8 kart ödemesi ve kamera arayüzleri · S6 çok dil altyapısı | temel yapı tamamlandı (2026-10-21): A ve B aşamaları |

### Dışarıdan gerekenler (karar değil; hesap açma ve onay)

Kod bunlar için hazırlanır ve kapalı ya da "Yakında…" olarak bekler; hiçbiri işi durdurmaz.

1. Avukat: H2, H3, H4 taslakları (ekip yazar, Cenk iletir). Onaya kadar gecikme tazminatı, borç hatırlatma ve otomatik silme kapalı.
2. Google Cloud projesi ve onay ekranı (Drive için; adım adım rehber dalga 4'te).
3. Firebase hizmet hesabı (telefon bildirimi; kod hazır). Firebase'in bildirim hizmeti ücretsizdir; yalnız bir Google hesabıyla proje
   açılır (iPhone için ayrıca Apple geliştirici hesabı). Hesap açılınca bildirim kısa sürede devreye alınır (N8).
4. Apple ve Google Play geliştirici hesapları, şirket adına (rehber dalga 1'de).
5. SMS firması hesabı (SMS ek hizmeti açılacaksa) ve ödeme kuruluşu sözleşmesi (kart ödemesi açılacaksa).
6. Sitelerin IBAN'ları: her site yöneticisi kendi ekranından girer.
7. KEP adresi ve MERSİS numarası (varsa): Platform Ayarları'na girilir.
8. Gerçek örnek dosyalar (banka ekstresi, eski yazılımın dışa aktarması, sayaç dosyası, elle hesaplanmış aidat tablosu): gelirse teste eklenir; beklenmez.
9. Destek e-postası, destek telefonu ve çalışma saatleri: Platform Ayarları'na girilir (N9; yardım ekranında görünür).

### Doğrulanamayanlar ve dikkat

- Platform Ayarları'ndaki canlı yasal bilgi değerleri (H1) ve Cenk'e daha önce gönderilmiş bir avukat taslağı olup olmadığı (H3).
- "Teklif Pro" Drive saklama sistemi (D1, T6): depoda yok, tarifi Cenk'ten gerekli.
- Apsiyon'un yönetim firmaları için çoklu site görünümü (Y1): sitesinde yalnız "Kurumsal" paket adı var; ayrıntı doğrulanamadı.
- Apple D-U-N-S durumu ve Google Play kuruluş hesabı kuralı (H6); elektronik genel kurulun mevzuat dayanağı (H4); ısı yönetmeliğinin numarası ve oranları (T2: Apsiyon'un sitesinden alındı, mevzuat.gov.tr'den doğrulanmadı).
- Tüm Apsiyon bilgileri pazarlama iddiasıdır (bkz. Yöntem).
- Liste tutarsızlığı: `tools/deneme_listesi/platform.json` içinde F2.08, F2.09 (Excel yükleme ve aktarma), F3.11 (Belgeler) ve F4.07, F4.09–F4.11 (makbuz, gider, kasa/banka, raporlar) hâlâ "planli"; oysa F13, F14 ve F15 bölümleriyle yapıldı. F4.08 ve F4.14 (gecikme tazminatı, borç hatırlatma) kodlandı ama hukuk onayına kadar bilerek kapalı. F11.02 "E-genel kurul ve karar defteri" yakinda; karar defteri F22'de hazır, eksik olan yalnız e-genel kurul (H4). Bu dosya yalnız yol haritasına yazıldığından `platform.json` değiştirilmedi.
