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

- Platformda reklam yoktur; reklam, davranış analizi veya profilleme amaçlı üçüncü taraf bir yazılım bileşeni kullanılmaz. Sunucumuz kendi çerezlerini (cookie) ayarlamaz; API trafiğinin geçtiği Cloudflare'in güvenlik amaçlı çerezleri için bölüm 5'e bakın.
- Verileriniz satılmaz ve pazarlama için paylaşılmaz.
- Konum, kamera ve mikrofon yalnızca ilgili özelliği siz kullandığınızda ve izin verdiğinizde kullanılır. Uygulama arka planda konumunuzu izlemez.
- Kişisel verilerinizin bir kopyasını indirebilir ve hesabınızı kendiniz silebilirsiniz: Profilim, Gizlilik ve Veri.

## 2. Kimler sorumlu?

İki ayrı sorumlu vardır:

- **Güde Teknoloji ({{company_name}}):** hesabınız, giriş güvenliği, yasal belge onaylarınız, site kurulum başvuruları, hata kayıtları ve destek için işlenen verilerin sorumlusudur.
- **Site Yönetimi:** katıldığınız sitenin kişi ve daire kayıtlarının, araç kayıtlarının, kapı yetkilerinin ve geçiş kayıtlarının, duyuruların ve aidat/borç kayıtlarının sorumlusudur. Bu kayıtlarda Güde, yönetim adına teknik hizmeti sunar.

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

Şu anda uygulama kapalıyken telefon bildirimi (push) gönderilmez; yeni duyurular uygulama açıkken uygulama içinde gösterilir. [AVUKAT DOĞRULASIN: ileride push bildirimi (ör. Firebase) eklenirse sağlayıcı, yurt dışı aktarım ve izin metni bu bölüme eklenecek]

### 3.5 Aidat ve finans kayıtları

Aidat modülü sitenizde açıksa, dairenize işlenen borçlar, tahsilatlar ve düzeltmeler (tutar, tarih, ödeme yöntemi, açıklama, kaydı yapan yönetici) tutulur. Platform üzerinden online ödeme alınmaz; kart veya banka bilgisi toplanmaz. Tahsilatlar yönetimin elle girdiği kayıtlardır.

Dairenin borç bilgisini, dairenin sorumlu tarafına (malik, kiracı veya her ikisi) göre ilgili kişiler görür; sorumlu tarafta güncel bir kişi kayıtlı değilse dairenin güncel malik, kiracı ve sakin kayıtları görür. Aile üyeleri görmez. Daire ekranı önceki sakinlerin dönemine ait son hareketleri de gösterebilir. Yönetici tüm daireleri görür; kurul üyeleri yalnızca görüntüler.

### 3.6 Teknik bilgiler ve hata raporları

Güvenlik ve hata ayıklama için sunucu günlüklerinde istek türü, adresin gizli değerleri maskelenmiş hâli, sonuç kodu ve süre tutulur; parolalar ve oturum belirteçleri günlüklere yazılmaz. Bazı güvenlik ve yönetim olaylarında (ör. misafir bağlantısının kullanımı, cihaz kaydı ve devri) kullanıcı kodu, e-posta adresi veya IP adresi günlüğe yazılabilir. Ayrıca sunucunun önündeki web sunucusu (nginx) erişim günlüğünde IP adresi ve istek adresi tutulur. [KARAR/BİLGİ GEREKLİ: nginx erişim günlüğünün saklama süresi] Uygulama günlükleri haftalık döndürülür veya 20 MB'ı aşınca döndürülür ve en çok 8 eski dosya saklanır. Hız sınırlaması için IP adresi yalnızca kısa süreli olarak sunucu belleğinde kullanılır. Yönetici işlemleri (kim, ne zaman, hangi işlem) denetim kaydında tutulur.

Uygulama beklenmedik bir hatayla karşılaşırsa bir hata raporu (hata türü, uygulama ve işletim sistemi sürümü, hata mesajı en çok 500 karakter ve hatanın teknik izinin ilk bölümü) sunucumuza gönderilebilir. Rapor 90 gün saklanır. Raporla birlikte kullanıcı, IP adresi veya cihaz tanıtıcısı saklanmaz. Rapor metnindeki e-posta, telefon, belirteç ve benzeri değerlerin otomatik olarak temizlenmesi için çaba gösterilir; ad gibi serbest metin değerleri her durumda yakalanamayabilir.

### 3.7 Telefonunuzda saklananlar

Oturumunuz telefonunuzun güvenli depolama alanında tutulur; hesabınızdan çıkış yaptığınızda silinir. Ana ekran kapı widget'ının çalışabilmesi için oturum anahtarınızın bir kopyası, API adresi ve kapı/site adları widget deposunda (Android'de uygulama tercihleri, iOS'ta uygulama grubu deposu) tutulur; bu depo işletim sisteminin anahtarlık/anahtar deposu değildir. Çıkış yaptığınızda bu kopya silinir.

Giriş yaptığınız e-posta veya kullanıcı adı için sunucudan alınan imzalı bir "giriş cihazı belirteci" telefonunuzun güvenli depolama alanında saklanır (tanımlayıcılar özet olarak, en çok 8 kayıt, 180 gün geçerli). Bu belirteç parola yerine geçmez; yalnızca başkalarının hatalı denemeleriyle hesabınızın kilitlenmesini önler. Çıkış yaptığınızda silinmez; hesabınızı sildiğinizde silinir.

Kapı kontrolüne ilişkin bazı yerel erişim bilgileri ve tercihleriniz (tema, "beni hatırla" ile kaydedilen kullanıcı adı veya e-posta, eller serbest dinleme tercihi) cihazınızda saklanır. Uygulama ayrıca hata raporlarının hız sınırı için cihazınızda rastgele üretilmiş bir kurulum numarası ve gönderilemeyen hata raporları için kısa bir sıra tutar; bu numara hesabınızla ilişkilendirilmez. Android'de uygulama verisi bulut yedeklemesine ve cihaz aktarımına çıkarılmaz.

## 4. Cihaz izinleri

- **Konum:** kapıya yakın olduğunuzu doğrulamak ve karekod oluşturmak için; yalnızca konum doğrulaması gereken kapılarda ve siz işlemi başlattığınızda. Site yöneticileri, site konum merkezini belirlemek için de kullanabilir.
- **Kamera:** cihaz, kapı veya site katılım karekodunu okumak için. Görüntü cihazınızda işlenir, kaydedilmez ve sunucuya gönderilmez. [AVUKAT DOĞRULASIN: Android'de karekod okuma bileşeninin (Google ML Kit) kendi tanılama verisi gönderip göndermediği]
- **Mikrofon ve konuşma tanıma:** "Kapıyı aç" gibi sesli komutlar için; yalnızca özelliği kullandığınızda. Konuşmanız cihazınızın işletim sistemindeki konuşma tanıma hizmetiyle metne çevrilir; bu hizmetin sağlayıcısı ses kaydını kendi sunucularında işleyebilir ve kendi gizlilik koşullarına tabidir. Ses kaydı Güde'ye gönderilmez.
- **Bluetooth:** yeni bir kapı cihazının Wi-Fi ayarını yapmak için. Wi-Fi bilgileri cihaza Bluetooth ile iletilir, sunucuya gönderilmez.
- **Yerel ağ (iOS):** aynı ağdaki kapı kontrol cihazını bulmak ve kapıyı yerel ağ üzerinden açmak için.
- **Ağ:** sunucuya, kapı cihazına ve yerel ağdaki kapı kontrol cihazına erişmek için.

İzni reddederseniz ilgili özellik çalışmaz; diğer özellikler çalışmaya devam eder. İzinleri istediğiniz zaman telefonunuzun ayarlarından değiştirebilirsiniz.

## 5. Çerezler ve izleme

Sunucumuz kendi çerezlerini ayarlamaz. Uygulamada reklam, analitik veya davranış izleme bileşeni yoktur. Web sürümünde oturumunuz ve tercihleriniz tarayıcınızın yerel depolamasında tutulur. API trafiği Cloudflare üzerinden geçtiğinden Cloudflare, güvenlik amacıyla kendi çerezlerini veya başlıklarını kullanabilir. [AVUKAT DOĞRULASIN: Cloudflare üzerinden geçen trafikte çerez kullanımı ve aydınlatma gereği]

Mobil uygulama, internet bağlantısını sınamak için sunucumuzdan yanıt alamadığında Google'ın genel bağlantı denetim adresine (clients3.google.com) içeriksiz bir istek gönderebilir; bu istekte kişisel verileriniz gönderilmez, ancak IP adresiniz bu adresin sahibi tarafından görülür.

Web sürümünü kullanırken tarayıcınız çalışma dosyalarını ve yazı tiplerini [KARAR/BİLGİ GEREKLİ: web sürümünün barındırıldığı adres ve üçüncü taraf içerik dağıtım ağlarının (ör. Google gstatic/googleapis) kullanılıp kullanılmadığı] adreslerinden yükleyebilir; bu durumda IP adresiniz ve tarayıcı bilgileriniz ilgili sağlayıcı tarafından görülür.

## 6. Bilgilerinizi kimlerle paylaşıyoruz?

- **Site Yönetimi:** sitenizle ilgili kayıtları yönetmesi için. Yönetici sitenin tüm kayıtlarını yönetir; kurul üyeleri yalnızca görüntüler; görevliler yalnızca kapı geçişi için yetkilidir ve kişi listesini veya finans kayıtlarını göremez.
- **Aynı dairedeki üyeler:** birbirlerinin ad, e-posta ve telefon bilgisini görür.
- **Hizmet sağlayıcılarımız:** sunucu barındırma [KARAR/BİLGİ GEREKLİ: sağlayıcı adı ve sunucu konumu], e-posta gönderimi [KARAR/BİLGİ GEREKLİ: sağlayıcı adı ve sunucu konumu] ve alan adı DNS hizmeti. Alan adı DNS hizmeti Cloudflare tarafından sağlanır; uygulama sunucusu (API) adresi Cloudflare'in kenar ağına çözümlenir ve API trafiği Cloudflare üzerinden geçer. [AVUKAT DOĞRULASIN: Cloudflare üzerinden geçen trafik için yurt dışına aktarım değerlendirmesi] Kapı cihazlarının kullandığı MQTT adresinin durumu [KARAR/BİLGİ GEREKLİ: MQTT alan adının Cloudflare vekili üzerinden geçip geçmediği]. Bu sağlayıcılar verilerinizi yalnızca bizim adımıza ve talimatlarımızla işler.
- **Yetkili kurumlar:** mahkeme veya kamu kurumlarının yasal talepleri halinde, talebin kapsamıyla sınırlı olarak.

Verileriniz yurt dışına aktarılacaksa Kanun'un 9. maddesine uygun yöntemler kullanılır. [KARAR/BİLGİ GEREKLİ: sunucu ve e-posta sağlayıcılarının veri merkezi konumu] [AVUKAT DOĞRULASIN: yurt dışı aktarım değerlendirmesi]

## 7. Ne kadar süre saklıyoruz?

Aşağıdaki kayıtlar otomatik olarak silinir:

- **Kapı geçiş kayıtları:** 30 gün.
- **Kapı cihazlarının bağlantı kayıtları:** 30 gün.
- **Karekod belirteçleri (oluştururken gönderilen konum dâhil):** süresi dolduktan veya yenisi üretilerek geçersiz kılındıktan sonra en geç yaklaşık iki gün içinde.
- **E-posta doğrulama kodu kayıtları ve doğrulanmamış bekleyen kayıtlar:** 2 gün.
- **Duyuru e-postası için sıraya alınan e-posta adresi:** gönderimden hemen sonra silinir; adres özeti 3 gün sonra silinir.
- **Hata raporları:** 90 gün.

Parola sıfırlama bağlantısı 30 dakika geçerlidir ve tek kullanımlıktır; süresi dolduktan sonra kullanılamaz.

Diğer kayıtlar:

- **Hesap bilgileriniz:** hesabınız açık kaldığı sürece. Hesabınızı sildiğinizde kimliksizleştirilir (bölüm 9).
- **Site kayıtları ve aidat/borç kayıtları:** Site Yönetiminin saklama yükümlülüklerine ve yasal sürelere göre; hesabınızı silmeniz bu kayıtların yasal saklama süresi dolmadan silinmesini sağlamaz. [KARAR/BİLGİ GEREKLİ: kişi/daire/araç kayıtları, duyurular ve aidat/borç kayıtları için saklama süresi]
- **Diğer:** [KARAR/BİLGİ GEREKLİ: saklama süresi belirlenecek kayıtlar: denetim kaydı, yasal belge onay kayıtları, misafir geçiş bağlantıları, katılım başvuruları ve davetler, abonelikten çıkma listesi, nginx erişim günlüğü, yedekler]
- **Yedekler:** sunucudaki yerel yedekler günlük 14, haftalık 8 ve aylık 6 adet tutulur; dış kopyalar en çok yaklaşık 210 gün saklanır. Silinen veya kimliksizleştirilen verinin yedeklerdeki kopyası bu döngü dolunca, yani en geç yaklaşık 7 ay içinde yok olur. [KARAR/BİLGİ GEREKLİ: yedekleme düzeninin üretimde devrede olduğu, dış kopyanın nerede tutulduğu ve saklama süreleri doğrulanacak]

## 8. Verilerinizi nasıl koruyoruz?

Yalnızca gerçekten uygulanan önlemler:

- Uygulama ile sunucu arasındaki bağlantılar şifrelidir (HTTPS); kapı cihazlarıyla sunucu arasındaki haberleşme TLS ile korunur. Android uygulaması internet üzerinde şifresiz (HTTP) bağlantıya izin vermez.
- Hesap parolanız geri döndürülemez biçimde (özet olarak) saklanır; doğrulama kodları ve parola sıfırlama bağlantıları da yalnızca özet olarak tutulur. İstisna: yönetim tarafından açılan eski tip "daire hesaplarında" hesabın sakine iletilebilmesi için PIN ayrıca okunabilir biçimde saklanır ve e-postayla iletilebilir. [KARAR/BİLGİ GEREKLİ: daire hesabı PIN'inin okunabilir saklanması kaldırılacak mı; kaldırılmazsa bu cümle kalır]
- Oturumlar imzalı ve süreli belirteçlerle yürür; belirteç yalnızca kullanıcı kodunu, parola sürümünü ve süre bilgisini taşır; e-posta veya rol taşımaz. Parolanız değişince eski oturumlar geçersiz olur. Hatalı giriş denemeleri sınırlandırılır ve art arda hatalı denemede hesap geçici olarak kilitlenir.
- Oturum anahtarınızın ana ekran widget'ı için tutulan kopyası işletim sisteminin anahtar deposunda değil, widget deposundadır (bölüm 3.7); çıkışta silinir.
- Erişim rol ve site bazında sınırlandırılmıştır: bir site yöneticisi yalnızca kendi sitesinin kayıtlarını görür; sakin yalnızca kendi kayıtlarını, kendi dairesinin borcunu ve aynı dairedeki üyelerin iletişim bilgisini görür.
- Yönetim işlemleri denetim kaydına yazılır. Aidat ve finans defteri veritabanı düzeyinde değiştirilemez ve silinemez; hatalar ters kayıtla düzeltilir. Tek istisna: bir site kalıcı olarak silindiğinde o sitenin defteri de silinir.
- Veritabanı yalnızca sunucunun kendisinden erişilebilir durumdadır.
- Telefonunuzdaki oturum anahtarı işletim sisteminin güvenli depolama alanında tutulur.
- Hata raporları kişisel veriden arındırılmaya çalışılır; parola ve belirteçler günlüğe yazılmaz; duyuru e-postası adresleri günlük sınır takibi için özetlenir.
- Karekodlar kısa ömürlü ve tek kullanımlıktır.
- Yedekler: bölüm 7'de belirtilen düzende tutulur; haftalık, aylık ve dış kopyalar şifrelidir, sunucudaki en son günlük yedek ise şifrelenmeden, yalnızca sahibine okunabilir dosya izinleriyle saklanır. [KARAR/BİLGİ GEREKLİ: yedeklerin şifreleme ve izin ayrıntıları ile yedeklerin tutulduğu yerler (sunucu, dış kopya, yönetim bilgisayarı) doğrulanacak]

Hiçbir sistem tamamen risksizdir. Güvenliğe ilişkin bir sorun fark ederseniz {{contact_email}} adresine yazın.

## 9. Verileriniz üzerindeki seçenekleriniz

- **Verilerimi indir:** Profilim, Gizlilik ve Veri, "Verilerimi İndir". Şifreniz istenir; 24 saatte en fazla 3 kez yapılabilir. Dosya sizin verdiğiniz ve sizin adınıza üretilen verileri içerir; başka kişilerin kişisel verilerini, yönetici iç notlarını, parola özetini ve oturum belirteçlerini içermez.
- **Hesabımı sil:** Profilim, Gizlilik ve Veri, "Hesabımı Sil". Önce nelerin silineceğini ve nelerin saklanacağını görürsünüz, sonra şifrenizle onaylarsınız. Ayrıntılar için Hesap ve Veri Silme sayfasına bakın.
- **E-posta tercihleri:** Profilim, Bildirim Tercihleri, "E-posta ile duyuru al". Duyuru e-postalarındaki "Abonelikten çık" bağlantısı da kullanılabilir.
- **Diğer haklar:** erişim, düzeltme, silme ve itiraz gibi Kanun'dan doğan haklarınız için KVKK Aydınlatma Metni'ndeki başvuru yollarını kullanabilirsiniz.

## 10. Çocuklar

Platform 18 yaşından küçüklere yönelik değildir. Hesap oluşturarak 18 yaşını doldurduğunuzu beyan edersiniz; uygulama yaşınızı ayrıca doğrulamaz. Site Yönetimi 18 yaşından küçük bir kişiyi aile üyesi olarak kaydederse bu kaydın sorumlusu Site Yönetimidir ve çocuğa ait veriyi en az düzeyde tutmalıdır. Bir çocuğa ait verilerin silinmesini veya düzeltilmesini veli olarak talep edebilirsiniz. [AVUKAT DOĞRULASIN: yaş sınırı ve küçüklerin kişisel verilerinin işlenmesine ilişkin ifade]

## 11. Değişiklikler

Bu politika değiştiğinde yeni sürüm uygulamada yayımlanır ve gerekli olduğunda tekrar onayınız istenir. Sürüm ve yürürlük tarihi sayfanın başında yer alır.

## 12. İletişim

Gizlilikle ilgili soru ve talepleriniz için: {{contact_email}} veya {{company_address}}. KEP: {{kep_address}}.
