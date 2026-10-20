# Elektronik genel kurul taslağı (avukata, 2026-10-21)

Bu belge avukata gidecek. Cenk okuyup kontrol eder, sonra iletir (karar H4). İçinde: mevzuatın bugünkü durumu, önerdiğimiz akış, taslak
metinler ve avukata sorular. Hukuki iddiaların hepsi madde numarasıyla yazıldı ve `[AVUKAT DOĞRULASIN]` ile işaretlendi. Bu belge
hukuki görüş değildir.

**Bugün sistemde:** elektronik genel kurul modülü YOK; deneme listesinde "Yakında" duruyor. Var olan: Karar Defteri modülü (kararları
kaydeder, toplantı türü "genel kurul" seçilebilir, kesinleşen karar değiştirilemez, yıl PDF'i alınır). Karar Defteri ekranı ve PDF'i
"noter onaylı karar defterinin yerine geçmez" uyarısını taşır (`docs/PLATFORM_KARAR_DEFTERI.md`). Bu taslak onaylanmadan kod yazılmaz.

## 1. Mevzuat durumu

### 1.1 Doğrulananlar (resmî metin, erişim 2026-10-21)

Kaynak: Kat Mülkiyeti Kanunu'nun (634) mevzuat.gov.tr'deki güncel metni (7579 sayılı Kanunla yapılan değişiklikler işlenmiş).

- **KMK'da elektronik toplantı ya da elektronik oy hükmü yok.** Metinde "elektronik" sözcüğü yalnız tapu işlemlerinde (projenin ve yapı
  kullanma izninin tapu ya da kadastro müdürlüğüne elektronik ortamda gönderilmesi) geçiyor. `[AVUKAT DOĞRULASIN]`
- **7579 sayılı Kanun (RG 22.05.2026) toplantı maddelerine dokunmadı.** KMK'da yalnız m.35, m.37 ve m.70 değişti (metnin sonundaki
  değişiklik tablosu). m.29-33 aynı kaldı.
- **Toplantı zamanı ve çağrı (m.29):** kurul yılda en az bir kez, yönetim planında yazılı zamanda, yazmıyorsa takvim yılının ilk ayında
  toplanır (toplu yapılarda en geç iki yılda bir). Önemli bir sebeple toplantı, "toplantı için istenilen tarihten en az onbeş gün önce
  bütün kat maliklerine imzalattırılacak bir çağrı veya bir taahhütlü mektupla, toplantı sebebi de bildirilmek şartiyle" yapılır. İlk
  çağrıda ikinci toplantının yeri ve tarihi de yazılır; iki toplantı arasında en az yedi gün olur.
- **Yeter sayı (m.30):** kurul "kat maliklerinin sayı ve arsa payı bakımından yarısından fazlasiyle toplanır ve oy çokluğuyla karar
  verir." İlk toplantı yeter sayı yüzünden yapılamazsa ikinci toplantı en geç on beş gün sonra yapılır ve karar yeter sayısı
  "katılanların salt çoğunluğudur." Kanundaki özel yeter sayılar saklıdır.
- **Oy ve vekâlet (m.31):** her kat malikinin bir oyu vardır; birden çok bağımsız bölümü olan her bölüm için oy kullanır ama oyları
  toplamın üçte birini geçemez. Bir bölümün birden çok maliki varsa içlerinden birini vekil yapar. Karar doğrudan kendisini
  ilgilendiren malik görüşmede bulunur ama oy kullanamaz. "Bir kişi, oy sayısının yüzde beşinden fazlasını kullanmak üzere vekil tayin
  edilemez. Ancak, kırk ve daha az sayıdaki kat mülkiyetine tâbi taşınmazlarda bir kişi, en fazla iki kişiye vekâlet edebilir."
- **Karar defteri ve imza (m.32):** kararlar "(1) den başlayıp sırayla giden sayfa numaraları taşıyan her sayfası noter mühüriyle
  tasdikli bir deftere yazılarak, toplantıda bulunan bütün kat maliklerince imzalanır; karara aykırı oy verenler bu aykırılığın sebebini
  belirterek imza koyarlar."
- **İptal davası (m.33):** toplantıya katılıp aykırı oy veren karar tarihinden, katılmayan kararı öğrenmesinden başlayarak bir ay içinde
  ve her hâlde karar tarihinden başlayarak altı ay içinde sulh mahkemesinde iptal davası açabilir; yok ya da mutlak butlanla hükümsüz
  kararlarda süre aranmaz.
- **Defterin kapatılması (m.36):** karar defteri her takvim yılının bitiminden başlayarak bir ay içinde notere kapattırılır.
- **İşletme projesi (m.37, 7579 ile değişik):** "İşletme projesi kat malikleri genel kurulunda onaylanır." Geçici proje kat maliklerine
  "imzaları karşılığında veya taahhütlü mektupla bildirilir ve en geç üç ay içinde aynen veya değiştirilerek kabulüne yönelik genel
  kurulda karar alınır."
- **Kıyas, şirketler (TTK m.1527):** Türk Ticaret Kanunu şirketlerde elektronik genel kurulu açıkça düzenler: şirket sözleşmesinde
  öngörülmesi şartıyla "elektronik ortamda ortaklar kuruluna ve genel kurula katılma, öneride bulunma ve oy verme, fizikî katılımın,
  öneride bulunmanın ve oy vermenin bütün hukuki sonuçlarını doğurur"; bunun için ayrıca amaca özgü internet sitesi, teknik rapor ve oy
  kullananların kimliklerinin saklanması şarttır. KMK'da buna benzer bir hüküm yok. `[AVUKAT DOĞRULASIN]`

### 1.2 İkincil kaynak

- Bir hukuk bürosu yazısına göre (Mıhcı Hukuk Bürosu, tarihsiz): "Elektronik ortamda genel kurul toplantısı kural olarak mümkün
  değildir." ve "Bu durum, Kat Mülkiyeti Kanununda açıkça yasaklanmamıştır." Gerekçe olarak tutanak ve hazirun cetvelinin toplantıya
  katılanlarca imzalanması gösteriliyor. `[AVUKAT DOĞRULASIN]`

### 1.3 Doğrulanamayanlar

- Elektronik ortamda yapılmış bir kat malikleri kurulu toplantısının ya da kararının geçerliliğine dair Yargıtay kararı (bu çalışmada
  bulunamadı).
- Yönetim planının elektronik toplantıya ya da elektronik oya izin verip veremeyeceği.
- Çağrının KEP, e-posta ya da uygulama bildirimiyle yapılmasının geçerliliği.
- Karar defterinin elektronik tutulması ya da elektronik imzayla imzalanması.

**Sonuç (bizim okumamız, avukat onayına bağlı):** tamamen uzaktan yapılan bir genel kurulun açık yasal dayanağı yok. Bu yüzden önerimiz
**karma model**: hazırlık, belge paylaşımı, vekâlet takibi, hazirun listesi, yeter sayı ve oy sayımı yardımı uygulamada; yasal adımlar
(imzalı çağrı ya da taahhütlü mektup, salonda toplantı, noter tasdikli deftere yazım ve ıslak imza) bugünkü gibi kâğıt üzerinde.

## 2. Önerilen akış (taslak)

1. **Hazırlık (yönetici).** Toplantı türü (olağan, önemli sebeple olağanüstü), tarih, saat, yer, gündem maddeleri, ekler (faaliyet
   raporu, işletme projesi taslağı, denetim raporu). İkinci toplantının tarihi ve yeri. Sistem uyarır: çağrı tarihi ile toplantı arasında
   en az 15 gün (m.29; olağan toplantı için yönetim planına bakılır); iki toplantı arasında en az 7 ve en çok 15 gün (m.29 ve m.30).
2. **Çağrı.** Sistem çağrı metnini ve iki çıktıyı hazırlar: taahhütlü mektup listesi (malik adı ve adresi) ve imzaya açık çağrı listesi
   (PDF). Yönetici taahhütlü gönderi numaralarını ya da imzalı listenin fotoğrafını sisteme ekler. Uygulama bildirimi ve e-posta yalnız
   **ek bilgilendirmedir**, yasal çağrının yerine geçmez (soru 4).
3. **Vekâlet.** Malik vekilini uygulamadan bildirir ve vekâletnameyi yükler; yönetici onaylar. Sistem m.31 sınırlarını denetler (bir
   kişi oyların %5'inden fazlası için vekil olamaz; 40 ve daha az bağımsız bölümde en çok 2 vekâlet; çok malikli bölümde tek temsilci).
4. **Toplantı günü.** Hazirun cetveli çıktısı (bölüm, malik, arsa payı, bizzat ya da vekil). Sistem katılanları işaretledikçe yeter sayıyı
   gösterir: sayı ve arsa payı bakımından yarıdan fazla mı (m.30). Gündem maddesi başına kabul, ret ve çekimser sayısı girilir; aykırı oy
   verenin gerekçesi yazılır; kararın doğrudan ilgilendirdiği malik oy dışı işaretlenir. Hesaplar **yardımcıdır**, karar toplantı
   başkanlığına aittir.
5. **Tutanak ve karar defteri.** Sistem kararları Karar Defteri'ne taslak olarak aktarır. Yönetici noter tasdikli deftere yazar ve
   imzaları alır; imzalı sayfaların fotoğrafı ya da PDF'i eklenince karar kesinleştirilir.
6. **Duyuru.** Kesin kararlar sakinlere duyurulur. Toplantıya katılmayan maliklere bildirim gider ve bildirim tarihi kaydedilir (iptal
   davası süresi kararı öğrenmekten başlar: m.33).
7. **Arşiv.** Karar defteri kaydı süresiz saklanır (karar H2; `docs/yasal/SAKLAMA_SURELERI_TASLAGI.md`).
8. **Sonraki adım (yalnız avukat "geçerli" derse).** Uzaktan katılım ve uygulamadan oy: hesapla giriş artı tek kullanımlık kodla kimlik
   doğrulama, değiştirilemez oy kaydı, oy kullananların kimliklerinin saklanması (TTK m.1527'deki koşullara benzer).

## 3. Taslak metinler

Köşeli ayraç içindekiler sistemin dolduracağı alanlardır.

### 3.1 Toplantı çağrısı (olağan toplantı)

> Sayın Kat Maliki,
>
> [Site adı] Kat Malikleri Kurulu olağan toplantısı [tarih] günü saat [saat]'te [yer] adresinde aşağıdaki gündemle yapılacaktır. İlk
> toplantıda yeter sayı sağlanamazsa ikinci toplantı [tarih] günü saat [saat]'te [yer] adresinde yapılacaktır.
>
> Gündem: 1. Açılış, toplantı başkanı ve yazmanın seçimi. 2. Yönetici ve denetçi raporlarının okunması. 3. [Yıl] yılı hesaplarının
> görüşülmesi ve yöneticinin ibrası. 4. [Yıl] yılı işletme projesinin görüşülmesi ve onaylanması. 5. Yönetici ve denetçinin seçimi.
> 6. Dilek ve temenniler.
>
> Toplantıya katılamayacak kat malikleri yazılı vekâletnameyle temsil edilebilir. Bir kişi oyların yüzde beşinden fazlasını kullanmak
> üzere vekil olamaz; [40 ve daha az bağımsız bölümlü yapılarda: bir kişi en fazla iki kat malikine vekâlet edebilir].
>
> Toplantı belgeleri (faaliyet raporu, işletme projesi taslağı, denetim raporu) uygulamada ve yönetim ofisinde incelemenize açıktır.
>
> [Yönetici adı soyadı], Yönetici, [tarih]

Not: Bu çağrı ayrıca taahhütlü mektupla ya da imza karşılığı elden tebliğ edilir; uygulama bildirimi ek bilgilendirmedir.
`[AVUKAT DOĞRULASIN]`

### 3.2 Vekâletname

> [Site adı] [blok ve daire] numaralı bağımsız bölümün maliki olarak, [tarih] tarihinde yapılacak [olağan / olağanüstü] kat malikleri
> kurulu toplantısında ve yeter sayı sağlanamazsa yapılacak ikinci toplantıda beni temsile, gündemdeki konularda oy kullanmaya ve
> tutanakları imzalamaya [vekilin adı soyadı]'nı vekil tayin ettim.
>
> Vekâlet veren: [ad soyad], [imza], [tarih]

Not: Noter onayı ve T.C. kimlik numarası gerekip gerekmediği soru 6. `[AVUKAT DOĞRULASIN]`

### 3.3 Hazirun cetveli

Sütunlar: Bağımsız bölüm · Kat maliki · Arsa payı · Bizzat / vekil · Vekilin adı · İmza.

Alt satır: "Toplam bağımsız bölüm: [N]; toplam arsa payı: [P]. Katılan: [n] bölüm ([%]); arsa payı [p] ([%]). Toplantı yeter sayısı
(sayı ve arsa payı bakımından yarıdan fazla, KMK m.30): [sağlandı / sağlanamadı]."

### 3.4 Karar tutanağı

> [Tarih] tarihinde [yer] adresinde yapılan [Site adı] Kat Malikleri Kurulu [olağan] toplantısında, hazirun cetvelinde imzası bulunan
> [n] kat maliki ve vekili hazır bulundu; toplantı yeter sayısının sağlandığı görüldü.
>
> Gündemin 1. maddesi: Toplantı başkanlığına [ad soyad], yazmanlığa [ad soyad] [oy birliğiyle / oy çokluğuyla] seçildi.
>
> Gündemin 4. maddesi: [Yıl] yılı işletme projesi okundu. Yapılan oylamada [k] kabul, [r] ret, [ç] çekimser oyla proje [aynen /
> değiştirilerek] kabul edildi. Aykırı oy verenler ve gerekçeleri: [ad soyad: gerekçe].
>
> Toplantıda bulunan kat malikleri ve vekilleri: [imzalar]

### 3.5 Katılmayanlara sonuç bildirimi

> Sayın Kat Maliki, [tarih] tarihli kat malikleri kurulu toplantısında alınan kararların özeti aşağıdadır. Kararların tam metni karar
> defterindedir ve yönetimde incelenebilir. [karar özetleri]

## 4. Sistemde nasıl olur? (kod yok, plan)

- Yeni modül "e-genel kurul": varsayılan kapalı, avukat onayına kadar "Yakında…". Karar Defteri'ne bağlanır (toplantı türü "genel
  kurul").
- Kayıtlar: toplantı, gündem, çağrı kanıtı (taahhütlü gönderi numarası ya da imzalı liste), vekâletler, hazirun, madde başına oy
  sayıları, karar metinleri.
- Yeter sayı hesabı daire künyesindeki arsa payını kullanır.
- Kişisel veri: hazirun, oy dökümü ve vekâletname yalnız yönetime ve kurula açık; sakin kendi bölümünü görür (soru 9).

## 5. Avukata sorular

1. KMK'da elektronik toplantı ve elektronik oy hükmü yok. Tamamen uzaktan yapılan bir genel kurul ve kararları geçerli olur mu, yoksa
   yok hükmünde ya da iptal edilebilir mi?
2. Karma model (salonda toplantı; uzaktan yalnız izleme; oy salonda ya da vekille) sorunsuz mu?
3. Yönetim planı elektronik toplantıya ve elektronik oya izin verebilir mi?
4. Çağrı: m.29'daki "imzalattırılacak bir çağrı veya taahhütlü mektup" yerine KEP, e-posta ya da uygulama bildirimi kullanılabilir mi?
   Olağan toplantının çağrı usulü yönetim planında yoksa hangi kural uygulanır?
5. Karar defteri (m.32): elektronik imza ya da uygulama içi onay ıslak imzanın yerine geçer mi? Defter elektronik tutulabilir mi?
6. Vekâletnamenin şekli: noter onayı şart mı? Uygulamaya yüklenen fotoğraf ya da tarama yeterli mi?
7. Sistemin hesapladığı yeter sayı ve oy sonucu yalnız "yardımcı" olarak mı kalmalı, yoksa tutanağa doğrudan yazılabilir mi?
8. İptal davası süresi (m.33): katılmayanlara bildirimin uygulamada kaydedilmesi "öğrenme" tarihinin ispatı için yeterli mi?
9. KVKK: hazirun, oy dökümü ve vekâletname kimlere açık olmalı, ne kadar saklanmalı?
10. Toplu yapılarda temsilciler kurulu (KMK m.66 ve devamı) için aynı akış kullanılabilir mi? (Bu taslak tek yapının kat malikleri
    kurulu için yazıldı.)
11. 7579 sonrası işletme projesinin genel kurulda onaylanması (m.37) bu akışla yapılabilir mi?

## 6. Kaynaklar (hepsine 2026-10-21'de erişildi)

- Kat Mülkiyeti Kanunu (634), güncel metin: <https://mevzuat.gov.tr/mevzuatmetin/1.5.634.pdf> (m.29-33, m.36, m.37 ve değişiklik
  tablosu).
- Türk Ticaret Kanunu (6102): <https://mevzuat.gov.tr/mevzuatmetin/1.5.6102.pdf> (m.1527).
- Mıhcı Hukuk Bürosu, "Apartman Kat Malikleri Kurulu Toplantısı" (tarihsiz, ikincil kaynak):
  <https://mihci.av.tr/apartman-kat-malikleri-kurulu-toplantisi/>
