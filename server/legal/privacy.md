---
id: privacy
title: Gizlilik Politikası
version: 2026-10-16
effective_date: 2026-10-16
required_for: [register]
complete: false   # köşeli [KARAR/BİLGİ GEREKLİ ...] ve [AVUKAT DOĞRULASIN ...] işaretleri çözülünce bu satır silinir
---

# Gizlilik Politikası

Bu politika, Site ve Toplu Yaşam Yönetim Sistemi uygulamasını ("Platform"; kapı geçiş modülü SmartKeyPass dâhil) kullanırken hangi bilgilerinizin işlendiğini, neden işlendiğini, ne kadar süre saklandığını ve bu bilgiler üzerindeki seçeneklerinizi sade bir dille anlatır. Hukuki ayrıntılar KVKK Aydınlatma Metni'nde yer alır.

## 1. Kısaca

- Platformda reklam yoktur; reklam, davranış analizi veya profilleme amaçlı üçüncü taraf bir yazılım bileşeni kullanılmaz. Telefon bildirimi için Google'ın Firebase Cloud Messaging hizmeti kullanılır (bölüm 3.8). Sunucumuz kendi çerezlerini (cookie) ayarlamaz; API trafiğinin geçtiği Cloudflare'in güvenlik amaçlı çerezleri için bölüm 5'e bakın.
- Verileriniz satılmaz ve pazarlama için paylaşılmaz.
- Konum, kamera ve mikrofon yalnızca ilgili özelliği siz kullandığınızda ve izin verdiğinizde kullanılır. Uygulama arka planda konumunuzu izlemez.
- Telefon bildirimi kendiliğinden açılmaz; yalnızca bir cihazda siz açıkça açarsanız çalışır ve istediğiniz zaman kapatabilirsiniz (bölüm 3.8).
- Kişisel verilerinizin bir kopyasını indirebilir ve hesabınızı kendiniz silebilirsiniz: Profilim, Gizlilik ve Veri.

## 2. Kimler sorumlu?

İki ayrı sorumlu vardır:

- **Güde Teknoloji ({{company_name}}):** hesabınız, giriş güvenliği, yasal belge onaylarınız, site kurulum başvuruları, hata kayıtları ve destek için işlenen verilerin sorumlusudur.
- **Site Yönetimi:** katıldığınız sitenin kişi ve daire kayıtlarının, araç kayıtlarının, kapı yetkilerinin ve geçiş kayıtlarının, duyuruların, aidat/borç, makbuz ve gider kayıtlarının ve yüklenen belgelerin sorumlusudur. Bu kayıtlarda Güde, yönetim adına teknik hizmeti sunar.

Güde iletişim bilgileri: adres {{company_address}}; e-posta {{contact_email}}; telefon {{contact_phone}}; KEP {{kep_address}}; MERSİS {{mersis_no}}.

## 3. Hangi bilgileri işliyoruz?

### 3.1 Hesap bilgileriniz

Adınız, soyadınız, e-posta adresiniz ve (girerseniz) telefon numaranız; rolünüz ve üyelikleriniz; parolanız (yalnızca geri döndürülemez özet olarak); e-posta doğrulama ve parola sıfırlama kodlarının özetleri; yasal belgeleri hangi sürümüyle ve ne zaman onayladığınız. Yönetim tarafından açılan "daire hesabı" kullanıyorsanız kullanıcı adı da işlenir.

Hesap bilgileriniz (ad, e-posta, telefon) bir siteye katıldığınızda o sitenin yöneticisi ve kurul üyeleri tarafından hesabınızdan canlı olarak görülebilir. Aynı daireye bağlı üyeler de birbirlerinin ad, e-posta ve telefon bilgisini görür.

### 3.2 Site kayıtları (Site Yönetimi girer)

Dairenizdeki ilişkiniz (malik, kiracı, aile üyesi, sakin) ve giriş/çıkış tarihleri; iletişim bilgileriniz; araç plakanız; yönetimin eklediği notlar. Hesabınız yoksa bu bilgiler yönetimin girdiği kadarıyla tutulur. Bu kayıtları yalnızca ilgili sitenin yöneticisi düzenler; yönetim kurulu üyeleri görüntüleyebilir (notlar hariç). Kişi, daire ve araç kayıtlarında yapılan değişikliklerin geçmişi (kim, ne zaman, hangi değişikliği yaptı) yönetici ve kurul üyeleri tarafından görülebilir; bu geçmişte, hesabı olmayan bir kişinin adında yapılan değişikliğin eski ve yeni adı, araç plakaları ve silinen bir dairenin geçmiş sakinlerinin adları ile tarihleri yer alabilir.

### 3.3 Kapı geçişi

Kapıyı hangi yolla açarsanız açın (uygulama, karekod, misafir bağlantısı, sesli komut, yerel ağ veya fiziksel düğme) geçiş zamanı, kapı adı, adınız, rolünüz, varsa daire etiketiniz ve geçiş yöntemi kaydedilir. Uygulama veya misafir bağlantısıyla yapılan geçişlerde geçişi isteyen cihazın IP adresi de kaydedilir. Kapıyı açan kullanıcıyı gösteren kısa bir etiket (adınız veya e-posta adresiniz) kapı cihazına iletilir. Kapı cihazı internet bağlantısı yokken kendi geçiş kaydını (ad en çok 40 karakter, geçiş yöntemi, daire etiketi, zaman) cihazın kendi belleğinde tutar ve bağlantı gelince sunucuya iletir; sunucu aldığını onaylayınca cihaz bu kayıtları siler. Bu yolla gelen kayıtlar kullanıcı hesabınıza bağlanmadan yalnız adla saklanır; 30 günlük saklama süresi dolana kadar hesabınızı silmiş olsanız bile bu kayıtlardaki ad kalabilir.

Misafir geçiş bağlantısı oluşturduğunuzda verdiğiniz başlık (ör. "Kurye") ve bağlantıyı kullanan kişinin IP adresi geçiş kaydına yazılır. Misafirden IP adresi dışında kişisel veri toplanmaz; misafir bağlantısı kapıyı konum doğrulaması istemeden açar. Misafirin IP adresi misafire aittir ve bağlantıyı oluşturan kişinin veri dışa aktarımına girmez.

Sitede konum doğrulaması açıksa (kapıya yakın olmanız şartı), kapıyı açarken veya karekod oluştururken o anki konumunuz, doğruluk değeri ve konumun sahte olup olmadığı bilgisi sunucuya gönderilir. Ekransız (statik karekodlu) kapı cihazlarında karekod okuturken konum, site ayarından bağımsız olarak zorunludur (sitede konum merkezi tanımlıysa). Karekod oluştururken gönderilen konum, karekod kaydıyla birlikte tutulur ve karekod geçerliliğini yitirdikten kısa süre sonra silinir. Karekodun geçerlilik süresi site ayarına göre belirlenir (varsayılan 30 saniye). Uzaktan kapı açmada konum yalnızca mesafeyi doğrulamak için kullanılır ve geçiş kaydına yazılmaz.

Site yöneticisiyseniz, sitenin konum merkezini belirlemek için cihazınızın o anki konumunu kullanabilirsiniz; bu konum sitenin konum merkezi olarak kaydedilir.

Platform kamera görüntüsü kaydetmez; yüz tanıma veya otomatik plaka tanıma yapmaz.

### 3.4 Duyurular ve e-postalar

Hangi duyuruların size ulaştığı, ne zaman okuduğunuz ve e-posta tercihiniz tutulur. Yönetim e-postayla duyuru gönderirse e-posta adresiniz gönderim bitene kadar sıraya yazılır, gönderimden sonra silinir; yalnızca günlük gönderim sınırını uygulamak için adresin geri döndürülemez bir özeti kısa süre tutulur. E-postadaki "Abonelikten çık" bağlantısını kullanırsanız bu adrese duyuru gönderilmemesi için adresin özeti bir listeye eklenir.

Bu duyuru e-postaları sitenizin yönetiminden gelen bilgilendirmelerdir; ticari ileti değildir ve içerikleri reklam amacıyla kullanılmaz. Acil duyurular, uygulamadaki e-posta tercihinizden bağımsız olarak gönderilir; e-postadaki bağlantıyla çıkarsanız acil duyurular dâhil tüm duyuru e-postaları durur.

Platform ayrıca işlemle ilgili e-postalar gönderir: e-posta doğrulama kodu, parola sıfırlama bağlantısı, yönetici daveti, katılım başvurusu ve site başvurusu bildirimleri, yönetimin isteğiyle daire hesabı giriş bilgileri (kullanıcı adı ve PIN) ve hesabınız silindiğinde bilgilendirme.

Yeni duyurular uygulama açıkken uygulama içinde gösterilir. Uygulama kapalıyken telefona bildirim gönderilmesi, yalnızca siz açıkça açarsanız mümkündür; ayrıntılar bölüm 3.8'dedir.

### 3.5 Aidat ve finans kayıtları

Aidat modülü sitenizde açıksa, dairenize işlenen borçlar, tahsilatlar ve düzeltmeler (tutar, tarih, ödeme yöntemi, açıklama, kaydı yapan yönetici) tutulur. Platform üzerinden online ödeme alınmaz; kart bilgisi toplanmaz ve sakinlerin banka hesap bilgisi için ayrı bir alan yoktur. Tahsilatlar yönetimin elle girdiği kayıtlardır.

**Makbuz.** Site Yönetimi bir tahsilat için makbuz düzenlediğinde (varsayılan ayar her tahsilatta otomatik düzenlemedir) makbuz, o andaki bilgilerle değişmez bir kayıt olarak saklanır: makbuz numarası, düzenleme ve ödeme tarihi, tutar, ödeme yöntemi, site adı, daire etiketi, ödeyen olarak kayıtlı kişinin adı, makbuzu düzenleyen yöneticinin adı ve bir doğrulama kodu. Yönetici ve kurul üyeleri sitenin makbuzlarını, sakinler ise görebildikleri dairelerin makbuzlarını görür. Yanlış makbuz silinmez; ayrı bir iptal makbuzu düzenlenir. Makbuzun her yazdırılması (kim, ne zaman) kaydedilir.

**Gecikme tazminatı.** Site Yönetimi bu özelliği açarsa geciken aidat borçları için aylık oranla hesaplanan gecikme tazminatı daire hesabına borç olarak işlenir; hesabın nasıl yapıldığı ilgili kişinin ekranında açıklanır. Özellik varsayılan olarak kapalıdır ve Platform işleticisinin hukuki onay anahtarı açılmadan açılamaz.

**Gider, tedarikçi, kasa ve banka kayıtları.** Site Yönetimi sitenin giderlerini (kategori, açıklama, tutar, KDV, tarih, belge türü ve numarası), tedarikçi kayıtlarını (ad, isteğe bağlı vergi veya T.C. kimlik numarası, telefon ve not), gider belgelerini (fatura veya fiş gibi PDF, JPG ve PNG dosyaları; gider başına en çok 5) ve sitenin kasa ve banka hesaplarındaki hareketleri tutabilir. Tedarikçi gerçek kişiyse bu kayıtlar o kişinin kişisel verisidir ve sorumlusu Site Yönetimidir. Kurul üyeleri tedarikçinin vergi veya T.C. kimlik numarasını, telefonunu ve notunu görmez. Gider kayıtları silinmez, iptal edilirse ayrı bir iptal kaydı oluşur; bir gider belgesi kaldırıldığında dosya sunucuda kalır.

**Borç hatırlatma e-postası.** Site Yönetimi bu özelliği açarsa vadesi geçmiş borcu olan dairenin sorumlu tarafına (malik, kiracı veya ikisi) site yönetimi adına e-posta gönderebilir. Özellik varsayılan olarak kapalıdır ve Platform işleticisinin hukuki onay anahtarı açılmadan açılamaz; anahtar kapatılırsa sırada bekleyen hatırlatmalar da gönderilmez. E-posta sabit bir şablondur: konu "[Site adı] Ödeme hatırlatması"dır; gövdede dairenin etiketi bulunur. Vadesi geçmiş tutar ve en eski vade tarihi yalnızca doğrulanmış hesap e-postasına gönderilen iletilerde yazılır; yönetimin girdiği veya doğrulanmamış adreslere tutar yazılmaz. Yönetim, bağlantı içermeyen en çok 300 karakterlik bir not ekleyebilir. E-posta tanıtım iletisi değildir; her iletide gönderen site yönetimi ve abonelikten çıkma bağlantısı bulunur, bağlantıyla çıkarsanız duyuru e-postaları da durur. E-posta adresiniz gönderilene kadar sıraya yazılır (en geç 24 saat), sonra silinir; adresin geri döndürülemez özeti en çok 8 gün tutulur. Aynı daireye sık sık tekrar hatırlatma gönderilmez.

Dairenin borç bilgisini, dairenin sorumlu tarafına (malik, kiracı veya her ikisi) göre ilgili kişiler görür; sorumlu tarafta güncel bir kişi kayıtlı değilse dairenin güncel malik, kiracı ve sakin kayıtları görür. Aile üyeleri görmez. Daire ekranı önceki sakinlerin dönemine ait son hareketleri de gösterebilir. Yönetici tüm daireleri görür; kurul üyeleri yalnızca görüntüler.

### 3.6 Teknik bilgiler ve hata raporları

Güvenlik ve hata ayıklama için sunucu günlüklerinde istek türü, adresin gizli değerleri maskelenmiş hâli, sonuç kodu ve süre tutulur; parolalar ve oturum belirteçleri günlüklere yazılmaz. Bazı güvenlik ve yönetim olaylarında (ör. misafir bağlantısının kullanımı, cihaz kaydı ve devri) kullanıcı kodu, e-posta adresi veya IP adresi günlüğe yazılabilir. Ayrıca sunucunun önündeki web sunucusu (nginx) erişim günlüğünde IP adresi ve istek adresi tutulur. [KARAR/BİLGİ GEREKLİ: nginx erişim günlüğünün saklama süresi] Uygulama günlükleri haftalık döndürülür veya 20 MB'ı aşınca döndürülür ve en çok 8 eski dosya saklanır. Hız sınırlaması için IP adresi yalnızca kısa süreli olarak sunucu belleğinde kullanılır. Yönetici işlemleri (kim, ne zaman, hangi işlem) denetim kaydında tutulur.

Uygulama beklenmedik bir hatayla karşılaşırsa bir hata raporu (hata türü, uygulama ve işletim sistemi sürümü, hata mesajı en çok 500 karakter ve hatanın teknik izinin ilk bölümü) sunucumuza gönderilebilir. Rapor 90 gün saklanır. Raporla birlikte kullanıcı, IP adresi veya cihaz tanıtıcısı saklanmaz. Rapor metnindeki e-posta, telefon, belirteç ve benzeri değerlerin otomatik olarak temizlenmesi için çaba gösterilir; ad gibi serbest metin değerleri her durumda yakalanamayabilir.

### 3.7 Telefonunuzda saklananlar

Oturumunuz telefonunuzun güvenli depolama alanında tutulur; hesabınızdan çıkış yaptığınızda silinir. Ana ekran kapı widget'ının çalışabilmesi için oturum anahtarınızın bir kopyası, API adresi ve kapı/site adları widget deposunda (Android'de uygulama tercihleri, iOS'ta uygulama grubu deposu) tutulur; bu depo işletim sisteminin anahtarlık/anahtar deposu değildir. Çıkış yaptığınızda bu kopya silinir.

Giriş yaptığınız e-posta veya kullanıcı adı için sunucudan alınan imzalı bir "giriş cihazı belirteci" telefonunuzun güvenli depolama alanında saklanır (tanımlayıcılar özet olarak, en çok 8 kayıt, 180 gün geçerli). Bu belirteç parola yerine geçmez; yalnızca başkalarının hatalı denemeleriyle hesabınızın kilitlenmesini önler. Çıkış yaptığınızda silinmez; hesabınızı sildiğinizde silinir.

Kapı kontrolüne ilişkin bazı yerel erişim bilgileri ve tercihleriniz (tema, "beni hatırla" ile kaydedilen kullanıcı adı veya e-posta, eller serbest dinleme tercihi) cihazınızda saklanır. Uygulama ayrıca hata raporlarının hız sınırı için cihazınızda rastgele üretilmiş bir kurulum numarası ve gönderilemeyen hata raporları için kısa bir sıra tutar; bu numara hesabınızla ilişkilendirilmez. Android'de uygulama verisi bulut yedeklemesine ve cihaz aktarımına çıkarılmaz.

Telefon bildirimini bir cihazda açtıysanız o cihazda ayrıca bildirim için üretilmiş rastgele bir kurulum numarası (hata raporu numarasından ayrıdır), kayıt durumunun kısa bir özeti (jetonun kendisi değil özeti) ve tercihleriniz tutulur; Google'ın verdiği bildirim jetonu da telefonunuzdaki Firebase bileşeninde bulunur. Çıkış yaptığınızda jeton ve kayıt özeti silinir; kurulum numarası ve tercihler ise hesabınızı sildiğinizde veya uygulamayı kaldırdığınızda silinir.

Dışa aktardığınız bir liste, indirdiğiniz belge veya veri dosyanız paylaşım için telefonun geçici klasörüne yazılır; uygulama bunları paylaşımdan kısa süre sonra, çıkışta veya hesap silmede silmeye çalışır. Dosyayı paylaştığınız başka bir uygulamadaki kopya bizim denetimimizde değildir.

### 3.8 Telefon bildirimi

Telefon bildirimi, uygulama kapalıyken yeni duyuruları telefonunuza bildirim olarak getirir. Kendiliğinden açılmaz: yalnızca bir cihazda "Bu cihazda aç" veya "Telefon bildirimi" ile siz açıkça açarsanız ve telefonunuzun bildirim iznini verirseniz çalışır; uygulama açılışta izin sormaz. Özellik sunucuda etkinleştirilmemişse uygulamada telefon bildirimi seçenekleri görünmez. [KARAR/BİLGİ GEREKLİ: telefon bildiriminin canlıda ne zaman etkinleştirileceği; etkinleşmeden önce bu bölümün ve Firebase yapılandırmasının hazır olması]

Bildirimi açtığınız cihaz için şunlar sunucuda tutulur: cihazın Android mi iOS mu olduğu, uygulama sürümü, Google'ın verdiği bildirim kayıt jetonu, işletim sistemi bildirim izninizin durumu, uygulamanın bu cihaz için ürettiği rastgele kurulum numarası, son görülme ve son başarılı gönderim zamanları ile en son gönderim hatasının kodu. Bir hesapta en çok 10 cihaz tutulur. Bildirim gönderilirken sunucu ayrıca hangi duyurunun hangi kullanıcıya hangi önem düzeyiyle gönderildiğini ve sonucunu (gönderildi, atlandı, süresi doldu veya başarısız) kuyruk kaydı olarak tutar; bildirimin metni kuyrukta saklanmaz. Uygulama cihaz kaydını yalnızca duyuru alabilen roller (sakin ve site yöneticisi) için yapar.

Bildirimin içeriği varsayılan olarak ayrıntısızdır: normal duyuruda başlık sitenin adı, metin "Yönetimden yeni bir duyuru var." olur; acil duyuruda başlık "Acil duyuru", metin "{Site adı}: acil bir duyuru var. Ayrıntı için uygulamayı açın." olur. "Bildirimde duyuru başlığını göster"i (varsayılan kapalı) açarsanız duyurunun başlığı (en çok 80 karakter) bildirimde yazılır ve kilit ekranında başkaları tarafından okunabilir. Bildirimle birlikte duyuru numarası, site numarası ve önem düzeyi teknik veri olarak iletilir. Tutar, borç, ad veya daire bilgisi telefon bildirimine yazılmaz.

Tercihleriniz: normal duyuruların telefon bildirimi anahtarı, duyuru başlığını gösterme, sessiz saatler (varsayılan kapalı; Türkiye saatine göre) ve cihaz listesi Profilim, Bildirim Tercihleri bölümündedir. Acil duyurular "Telefon bildirimi" anahtarından ve sessiz saatlerden etkilenmez; acil duyuru bildirimini de durdurmak için cihazı kaldırmanız veya telefonun bildirim iznini kapatmanız gerekir. Normal duyurular için kullanıcı başına günlük bir bildirim sınırı uygulanır; acil duyurular bu sınıra tabi değildir.

Bildirimler Google'ın Firebase Cloud Messaging hizmeti üzerinden iletilir; iOS'ta Apple'ın bildirim hizmeti de devreye girer. Sunucumuz bu amaçla Google'ın hizmet adreslerine bağlanır ve jetonunuzu, bildirim metnini (site adı dâhil) ile duyuru ve site numarasını Google'a iletir. Google ve Apple bu verileri Türkiye dışındaki sistemlerde işleyebilir ve kendi koşullarına tabidir. [AVUKAT DOĞRULASIN: Google'ın ve Apple'ın bu işlemdeki rolü (veri işleyen veya ayrı veri sorumlusu); yurt dışına aktarımın KVKK m.9 uyarınca dayanağı; telefon bildirimi için hukuki sebebin açık rıza (m.5/1) mı yoksa sözleşmenin ifası veya meşru menfaat mi olduğu ve "Aç" istemi metninin açık rıza koşullarını (bilgilendirme, özgür irade, geri alma kolaylığı) taşıyıp taşımadığı]

Uygulama, Google'ın Firebase bileşenlerini (Firebase Core ve Cloud Messaging) içerir; Firebase Analytics gibi analitik bileşen yoktur. Bildirim jetonu, siz telefon bildirimini açıncaya kadar üretilmez. [AVUKAT DOĞRULASIN: Firebase bileşeninin uygulama başlarken veya jeton alınırken Google'a gönderdiği teknik veriler (ör. Firebase Installations kimliği, cihaz ve uygulama bilgisi) ve bunun aydınlatma ile mağaza beyanlarına (Google Play Veri güvenliği, App Store gizlilik etiketi) yansıması]

Normal duyuruların bildirimini anahtarla kapatabilirsiniz; bildirimin tamamını durdurmak için "Bu cihazı kaldır"ı kullanabilir, hesabınızdan çıkış yapabilir veya telefonunuzun ayarlarından bildirim iznini kaldırabilirsiniz. Çıkışta sunucudaki kayıt ve telefondaki jeton silinir; bir cihazı listeden kaldırdığınızda o cihazın sunucudaki kaydı silinir; kullanılmayan cihaz kaydı ayrıca 60 gün sonra, tamamlanmış kuyruk kayıtları 14 gün sonra otomatik silinir.

### 3.9 Belgeler

Belgeler modülü sitenizde açıksa site yöneticisi belge yükleyebilir: yönetmelik, toplantı tutanağı veya karar, sözleşme, bilgilendirme ve diğer. Yönetici her belge için kimlerin göreceğini seçer: tüm sakinler (isterse seçili bloklar veya daireler), yalnızca yönetim kurulu veya yalnızca yöneticiler. Kurul üyeleri kurula ve sakinlere açık belgeleri salt okunur görür; yalnızca yöneticilere açık belgeleri görmez. Belgeleri indirmek için hesap gerekir. Belge bir duyuruya eklenirse o duyurunun tüm alıcıları belgeyi indirebilir; e-postaya belge eklenmez.

Belge için başlık, açıklama, kategori, dosya adı, boyut, sürümler, dosyanın kendisi, yükleyen hesap, tarihler ve toplam indirme sayısı tutulur; belgeyi kimin indirdiği kaydedilmez. Belgenin içeriğini yönetim belirler ve içerik kişisel veri taşıyabilir (ad, telefon, adres, T.C. kimlik numarası, IBAN gibi); yükleme ekranı yöneticiyi bu konuda uyarır ve bu belgelerin sorumlusu Site Yönetimidir. Varsayılan olarak yalnızca PDF, JPG, PNG, DOCX ve XLSX dosyaları kabul edilir.

Dosyalar veritabanında değil, sunucuda yalnızca sunucu hesabının erişebildiği ayrı bir dizinde tutulur; uygulama düzeyinde ayrıca şifrelenmez. Yönetimin sildiği belge geri alınabilir şekilde silinenlere taşınır ve varsayılan ayara göre 30 gün sonra sunucudan kalıcı olarak silinir (yönetim bunu hemen de yapabilir). Belge dosyaları, veritabanı yedeğinden ayrı olarak şifreli bir belge arşivinde de yedeklenir (bölüm 7). Yüklediğiniz belgeler hesabınızı silseniz de siteye ait olduğu için kalır; yükleyen adı "Silinmiş Kullanıcı" olarak görünür. [KARAR/BİLGİ GEREKLİ: belgeler için saklama süresi; sunucu diskinin şifrelenip şifrelenmediği; belge arşivi yedeğinin üretimde devrede olduğu] [AVUKAT DOĞRULASIN: belgeler için Site Yönetiminin sorumluluğu ve T.C. kimlik numarası gibi belgelerin gerekli olmayan kitlelere açılmasının önlenmesine ilişkin tedbirler yeterli mi]

### 3.10 Toplu yükleme ve dışa aktarma

Site yöneticisi kişi, daire ve araç bilgilerini Excel veya CSV dosyasıyla toplu olarak yükleyebilir. Dosya yöneticinin cihazında okunur ve sunucuya dosyanın kendisi değil, doğrulanacak satırların içeriği gönderilir; dosya ve ham satırlar sunucuda saklanmaz. Yalnızca doğrulanan kayıtlar kişi, ilişki ve araç kayıtlarına işlenir; çalışma kaydında yalnızca sayılar ve işlemi yapan hesap tutulur, yapılan değişiklikler yönetim işlem (denetim) kaydına yazılır. Yönetici ayrıca kişi, daire, araç ve finans kayıtlarını Excel veya CSV olarak dışa aktarabilir; kurul üyeleri bu dışa aktarmayı yapamaz. Her dışa aktarma kayıt altına alınır (kim, ne zaman, hangi tür, kaç satır); dosya yöneticinin cihazında oluşturulur ve sonrasında yöneticinin sorumluluğundadır. Toplu yükleme ile hesap açılmaz, davet gönderilmez ve kapı erişimi verilmez.

## 4. Cihaz izinleri

- **Konum:** kapıya yakın olduğunuzu doğrulamak ve karekod oluşturmak için; yalnızca konum doğrulaması gereken kapılarda ve siz işlemi başlattığınızda. Site yöneticileri, site konum merkezini belirlemek için de kullanabilir.
- **Kamera:** cihaz, kapı veya site katılım karekodunu okumak için. Görüntü cihazınızda işlenir, kaydedilmez ve sunucuya gönderilmez. [AVUKAT DOĞRULASIN: Android'de karekod okuma bileşeninin (Google ML Kit) kendi tanılama verisi gönderip göndermediği]
- **Mikrofon ve konuşma tanıma:** "Kapıyı aç" gibi sesli komutlar için; yalnızca özelliği kullandığınızda. Konuşmanız cihazınızın işletim sistemindeki konuşma tanıma hizmetiyle metne çevrilir; bu hizmetin sağlayıcısı ses kaydını kendi sunucularında işleyebilir ve kendi gizlilik koşullarına tabidir. Ses kaydı Güde'ye gönderilmez.
- **Bluetooth:** yeni bir kapı cihazının Wi-Fi ayarını yapmak için. Wi-Fi bilgileri cihaza Bluetooth ile iletilir, sunucuya gönderilmez.
- **Yerel ağ (iOS):** aynı ağdaki kapı kontrol cihazını bulmak ve kapıyı yerel ağ üzerinden açmak için.
- **Bildirim:** telefon bildirimini açtığınızda uygulama bildirimleri göstermek için işletim sisteminden izin ister (Android 13 ve üzerinde ve iOS'ta; daha eski Android sürümlerinde çalışma zamanı izni yoktur ve bildirim izni telefon ayarlarından yönetilir). İzin yalnızca siz telefon bildirimini açtığınızda istenir.
- **Ağ:** sunucuya, kapı cihazına ve yerel ağdaki kapı kontrol cihazına erişmek için.

İzni reddederseniz ilgili özellik çalışmaz; diğer özellikler çalışmaya devam eder. İzinleri istediğiniz zaman telefonunuzun ayarlarından değiştirebilirsiniz.

## 5. Çerezler ve izleme

Sunucumuz kendi çerezlerini ayarlamaz. Uygulamada reklam, analitik veya davranış izleme bileşeni yoktur; Google'ın telefon bildirimi için kullanılan Firebase bileşenleri bölüm 3.8'de açıklanmıştır. Web sürümünde oturumunuz ve tercihleriniz tarayıcınızın yerel depolamasında tutulur. API trafiği Cloudflare üzerinden geçtiğinden Cloudflare, güvenlik amacıyla kendi çerezlerini veya başlıklarını kullanabilir. [AVUKAT DOĞRULASIN: Cloudflare üzerinden geçen trafikte çerez kullanımı ve aydınlatma gereği]

Mobil uygulama, internet bağlantısını sınamak için sunucumuzdan yanıt alamadığında Google'ın genel bağlantı denetim adresine (clients3.google.com) içeriksiz bir istek gönderebilir; bu istekte kişisel verileriniz gönderilmez, ancak IP adresiniz bu adresin sahibi tarafından görülür.

Web sürümünü kullanırken tarayıcınız çalışma dosyalarını ve yazı tiplerini [KARAR/BİLGİ GEREKLİ: web sürümünün barındırıldığı adres ve üçüncü taraf içerik dağıtım ağlarının (ör. Google gstatic/googleapis) kullanılıp kullanılmadığı] adreslerinden yükleyebilir; bu durumda IP adresiniz ve tarayıcı bilgileriniz ilgili sağlayıcı tarafından görülür.

## 6. Bilgilerinizi kimlerle paylaşıyoruz?

- **Site Yönetimi:** sitenizle ilgili kayıtları yönetmesi için. Yönetici sitenin tüm kayıtlarını yönetir; kurul üyeleri yalnızca görüntüler; görevliler yalnızca kapı geçişi için yetkilidir ve kişi listesini veya finans kayıtlarını göremez.
- **Aynı dairedeki üyeler:** birbirlerinin ad, e-posta ve telefon bilgisini görür.
- **Hizmet sağlayıcılarımız:** sunucu barındırma [KARAR/BİLGİ GEREKLİ: sağlayıcı adı ve sunucu konumu], e-posta gönderimi [KARAR/BİLGİ GEREKLİ: sağlayıcı adı ve sunucu konumu] ve alan adı DNS hizmeti. Alan adı DNS hizmeti Cloudflare tarafından sağlanır; uygulama sunucusu (API) adresi Cloudflare'in kenar ağına çözümlenir ve API trafiği Cloudflare üzerinden geçer. [AVUKAT DOĞRULASIN: Cloudflare üzerinden geçen trafik için yurt dışına aktarım değerlendirmesi] Kapı cihazlarının kullandığı MQTT adresinin durumu [KARAR/BİLGİ GEREKLİ: MQTT alan adının Cloudflare vekili üzerinden geçip geçmediği]. Bu sağlayıcılar verilerinizi yalnızca bizim adımıza ve talimatlarımızla işler.
- **Google (Firebase Cloud Messaging) ve Apple (iOS bildirim hizmeti):** yalnızca telefon bildirimini açtıysanız; bildirim jetonunuz, bildirim metni (site adı dâhil) ve duyuru ile site numarası, bildirimin telefonunuza ulaştırılması için bu şirketlere iletilir (bölüm 3.8). [AVUKAT DOĞRULASIN: Google ve Apple'ın rolü ve yurt dışına aktarım dayanağı]
- **Yetkili kurumlar:** mahkeme veya kamu kurumlarının yasal talepleri halinde, talebin kapsamıyla sınırlı olarak.

Verileriniz yurt dışına aktarılacaksa Kanun'un 9. maddesine uygun yöntemler kullanılır. [KARAR/BİLGİ GEREKLİ: sunucu ve e-posta sağlayıcılarının veri merkezi konumu] [AVUKAT DOĞRULASIN: yurt dışı aktarım değerlendirmesi]

## 7. Ne kadar süre saklıyoruz?

Aşağıdaki kayıtlar otomatik olarak silinir:

- **Kapı geçiş kayıtları:** 30 gün.
- **Kapı cihazlarının bağlantı kayıtları:** 30 gün.
- **Karekod belirteçleri (oluştururken gönderilen konum dâhil):** süresi dolduktan veya yenisi üretilerek geçersiz kılındıktan sonra en geç yaklaşık iki gün içinde.
- **E-posta doğrulama kodu kayıtları ve doğrulanmamış bekleyen kayıtlar:** 2 gün.
- **Duyuru e-postası için sıraya alınan e-posta adresi:** gönderimden hemen sonra silinir; adres özeti 3 gün sonra silinir.
- **Aidat hatırlatma e-postası için sıraya alınan e-posta adresi:** gönderimden veya vazgeçilmesinden hemen sonra, en geç 24 saat içinde silinir; adres özeti 8 gün sonra silinir.
- **Telefon bildirimi cihaz kaydı:** kullanılmadığında 60 gün sonra; tamamlanmış bildirim kuyruğu kayıtları 14 gün sonra.
- **Silinen belgeler:** Site Yönetimi sildikten sonra varsayılan olarak 30 gün sonra sunucudan kalıcı olarak silinir.
- **Hata raporları:** 90 gün.

Parola sıfırlama bağlantısı 30 dakika geçerlidir ve tek kullanımlıktır; süresi dolduktan sonra kullanılamaz.

Diğer kayıtlar:

- **Hesap bilgileriniz:** hesabınız açık kaldığı sürece. Hesabınızı sildiğinizde kimliksizleştirilir (bölüm 9).
- **Site kayıtları ve aidat/borç kayıtları:** Site Yönetiminin saklama yükümlülüklerine ve yasal sürelere göre; hesabınızı silmeniz bu kayıtların yasal saklama süresi dolmadan silinmesini sağlamaz. [KARAR/BİLGİ GEREKLİ: kişi/daire/araç kayıtları, duyurular ve aidat/borç kayıtları için saklama süresi]
- **Makbuz, gecikme tazminatı, gider, tedarikçi, kasa ve banka kayıtları ile gider belgeleri:** Site Yönetiminin saklama yükümlülüklerine göre; bu kayıtlar silinemez ve değiştirilemez, hesabınızı silmeniz bu kayıtlardaki adınızı kaldırmaz. [KARAR/BİLGİ GEREKLİ: bu kayıtlar için saklama süresi] [AVUKAT DOĞRULASIN: bu kayıtların saklanma yükümlülüğü, süresi ve süre dolduğunda silinmesi]
- **Yüklenen belgeler:** Site Yönetimi silene kadar; Site Yönetimi sildikten sonra yukarıdaki süreyle. [KARAR/BİLGİ GEREKLİ: belgeler için saklama süresi]
- **Diğer:** [KARAR/BİLGİ GEREKLİ: saklama süresi belirlenecek kayıtlar: denetim kaydı, yasal belge onay kayıtları, misafir geçiş bağlantıları, katılım başvuruları ve davetler, abonelikten çıkma listesi, nginx erişim günlüğü, yedekler]
- **Yedekler:** sunucudaki yerel yedekler günlük 14, haftalık 8 ve aylık 6 adet tutulur; dış kopyalar en çok yaklaşık 210 gün saklanır. Silinen veya kimliksizleştirilen verinin yedeklerdeki kopyası bu döngü dolunca, yani en geç yaklaşık 7 ay içinde yok olur. Yüklenen belge dosyaları (gider belgeleri dâhil) ayrı bir şifreli belge arşivinde yedeklenir; arşivin son 5 sürümü tutulur ve en yenisi dışındakiler en çok yaklaşık 210 gün saklanır. [KARAR/BİLGİ GEREKLİ: yedekleme düzeninin (veritabanı ve belge arşivi) üretimde devrede olduğu, dış kopyanın nerede tutulduğu ve saklama süreleri doğrulanacak]

## 8. Verilerinizi nasıl koruyoruz?

Yalnızca gerçekten uygulanan önlemler:

- Uygulama ile sunucu arasındaki bağlantılar şifrelidir (HTTPS); kapı cihazlarıyla sunucu arasındaki haberleşme TLS ile korunur. Android uygulaması internet üzerinde şifresiz (HTTP) bağlantıya izin vermez.
- Hesap parolanız geri döndürülemez biçimde (özet olarak) saklanır; doğrulama kodları ve parola sıfırlama bağlantıları da yalnızca özet olarak tutulur. İstisna: yönetim tarafından açılan eski tip "daire hesaplarında" hesabın sakine iletilebilmesi için PIN ayrıca okunabilir biçimde saklanır ve e-postayla iletilebilir. [KARAR/BİLGİ GEREKLİ: daire hesabı PIN'inin okunabilir saklanması kaldırılacak mı; kaldırılmazsa bu cümle kalır]
- Oturumlar imzalı ve süreli belirteçlerle yürür; belirteç yalnızca kullanıcı kodunu, parola sürümünü ve süre bilgisini taşır; e-posta veya rol taşımaz. Parolanız değişince eski oturumlar geçersiz olur. Hatalı giriş denemeleri sınırlandırılır ve art arda hatalı denemede hesap geçici olarak kilitlenir.
- Oturum anahtarınızın ana ekran widget'ı için tutulan kopyası işletim sisteminin anahtar deposunda değil, widget deposundadır (bölüm 3.7); çıkışta silinir.
- Erişim rol ve site bazında sınırlandırılmıştır: bir site yöneticisi yalnızca kendi sitesinin kayıtlarını görür; sakin yalnızca kendi kayıtlarını, kendi dairesinin borcunu ve aynı dairedeki üyelerin iletişim bilgisini görür.
- Yönetim işlemleri denetim kaydına yazılır. Aidat ve finans defteri ile makbuz, gider, kasa ve banka hareketleri veritabanı düzeyinde değiştirilemez ve silinemez; hatalar ters kayıtla düzeltilir. Tek istisna: bir site kalıcı olarak silindiğinde o sitenin defteri de silinir.
- Yüklenen belgeler sunucuda veritabanı dışındaki ayrı bir dizinde (dizin ve dosya izinleri yalnızca sunucu hesabına açık) tutulur; dosya türü içeriğinden doğrulanır, boyut ve site başına kota sınırlanır, indirmeler yetki denetiminden geçer ve tarayıcıda doğrudan açılmak yerine indirme olarak sunulur. Dosyalar uygulama düzeyinde ayrıca şifrelenmez. Telefon bildirimlerine finansal veya kişisel ayrıntı yazılmaz; bildirim metni varsayılan olarak ayrıntısızdır.
- Veritabanı yalnızca sunucunun kendisinden erişilebilir durumdadır.
- Telefonunuzdaki oturum anahtarı işletim sisteminin güvenli depolama alanında tutulur.
- Hata raporları kişisel veriden arındırılmaya çalışılır; parola ve belirteçler günlüğe yazılmaz; duyuru e-postası adresleri günlük sınır takibi için özetlenir.
- Karekodlar kısa ömürlü ve tek kullanımlıktır.
- Yedekler: bölüm 7'de belirtilen düzende tutulur; haftalık, aylık ve dış kopyalar şifrelidir, sunucudaki en son günlük yedek ise şifrelenmeden, yalnızca sahibine okunabilir dosya izinleriyle saklanır. [KARAR/BİLGİ GEREKLİ: yedeklerin şifreleme ve izin ayrıntıları ile yedeklerin tutulduğu yerler (sunucu, dış kopya, yönetim bilgisayarı) doğrulanacak]

Hiçbir sistem tamamen risksizdir. Güvenliğe ilişkin bir sorun fark ederseniz {{contact_email}} adresine yazın.

## 9. Verileriniz üzerindeki seçenekleriniz

- **Verilerimi indir:** Profilim, Gizlilik ve Veri, "Verilerimi İndir". Şifreniz istenir; 24 saatte en fazla 3 kez yapılabilir. Dosya sizin verdiğiniz ve sizin adınıza üretilen verileri içerir: bildirim tercihleriniz, kayıtlı telefon bildirimi cihazlarınız (platform, uygulama sürümü ve tarihler; bildirim jetonu ve kurulum numarası yoktur), yüklediğiniz belgelerin yalnızca kayıt bilgisi (başlık, kategori, dosya adı, tür, boyut, tarih), görebildiğiniz dairelerin makbuz özeti (numara, tür, durum, tutar, tarih, daire) ve size gönderilen aidat hatırlatmalarının geçmişi (tarih, ton, durum). Başka kişilerin kişisel verilerini, yönetici iç notlarını, parola özetini, oturum belirteçlerini, belgelerin içeriğini, makbuzlardaki ad ve doğrulama bilgilerini, hatırlatma e-postalarının metnini, tutarlarını ve adres özetini içermez. Dosyada hangi bilgilerin neden dışarıda bırakıldığı "excluded" bölümünde yazar.
- **Hesabımı sil:** Profilim, Gizlilik ve Veri, "Hesabımı Sil". Önce nelerin silineceğini ve nelerin saklanacağını görürsünüz, sonra şifrenizle onaylarsınız. Ayrıntılar için Hesap ve Veri Silme sayfasına bakın.
- **E-posta tercihleri:** Profilim, Bildirim Tercihleri, "E-posta ile duyuru al". Duyuru ve aidat hatırlatma e-postalarındaki "Abonelikten çık" bağlantısı da kullanılabilir; bağlantıyla çıkıldığında her iki tür e-posta da durur.
- **Telefon bildirimi:** Profilim, Bildirim Tercihleri, "Telefon bildirimi" bölümü: anahtar, başlık gösterme, sessiz saatler, cihaz listesi ve "Bu cihazı kaldır" (bölüm 3.8).
- **Diğer haklar:** erişim, düzeltme, silme ve itiraz gibi Kanun'dan doğan haklarınız için KVKK Aydınlatma Metni'ndeki başvuru yollarını kullanabilirsiniz.

## 10. Çocuklar

Platform 18 yaşından küçüklere yönelik değildir. Hesap oluşturarak 18 yaşını doldurduğunuzu beyan edersiniz; uygulama yaşınızı ayrıca doğrulamaz. Site Yönetimi 18 yaşından küçük bir kişiyi aile üyesi olarak kaydederse bu kaydın sorumlusu Site Yönetimidir ve çocuğa ait veriyi en az düzeyde tutmalıdır. Bir çocuğa ait verilerin silinmesini veya düzeltilmesini veli olarak talep edebilirsiniz. [AVUKAT DOĞRULASIN: yaş sınırı ve küçüklerin kişisel verilerinin işlenmesine ilişkin ifade]

## 11. Değişiklikler

Bu politika değiştiğinde yeni sürüm uygulamada yayımlanır ve gerekli olduğunda tekrar onayınız istenir. Sürüm ve yürürlük tarihi sayfanın başında yer alır.

## 12. İletişim

Gizlilikle ilgili soru ve talepleriniz için: {{contact_email}} veya {{company_address}}. KEP: {{kep_address}}.
