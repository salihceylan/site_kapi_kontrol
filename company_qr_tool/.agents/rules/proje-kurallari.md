# Proje Kuralları

Bu proje aktif olarak geliştirilen ve çalışan özellikler içeren bir üretim projesidir.

Amaç; yeni özellikler geliştirirken mevcut çalışan davranışları korumak, gereksiz refactorlardan kaçınmak ve özellikle kritik cihaz bağlantılarını bozmamaktır.

## Genel Çalışma Kuralları

- Görevi tamamlamak için gerekli kodlarda değişiklik yapmakta serbestsin.
- İstenen görevle ilgisi olmayan dosya, sınıf, fonksiyon veya modüllerde gereksiz değişiklik yapma.
- Sırf kodu "daha temiz", "daha modern" veya "daha iyi mimarili" yapmak amacıyla çalışan kodu yeniden yazma.
- Mevcut çalışan davranışları mümkün olduğunca koru.
- Büyük ve kapsam dışı refactor yapma.
- Yeni özellik eklerken mümkün olduğunca mevcut yapıyla uyumlu ilerle.
- Bir değişiklik başka bir modülü etkileyebilecekse önce bağımlılıklarını incele.
- Public API, MQTT topic, veritabanı şeması veya ortak veri formatı değişecekse diğer bileşenlere etkisini kontrol et.
- Gereksiz paket, framework veya mimari değişikliği yapma.
- Değişiklikleri mümkün olduğunca küçük, anlaşılır ve geri alınabilir tut.
- Bir hatayı düzeltirken başka çalışan özelliklerin davranışını değiştirme.
- İş tamamlandıktan sonra build hatası, analyzer hatası ve ilgili ekran/akışlarda çalışma hatası olmadığını kontrol et.
- Her zaman modüler yapıda çalış. eklenen silinen değiştirilen özelliklerin başka özellikleri etkilememeli.

---

# Korunan Kritik Alanlar

Aşağıdaki alanlar şu anda çalışan ve kritik kabul edilen bölümlerdir.

Bu alanlar yeni görevle doğrudan ilgili değilse değiştirilmemelidir.

## 1. ESP32 İnternet / Wi-Fi Bağlantısı

ESP32'nin internete ve Wi-Fi ağına bağlanmasını sağlayan mevcut çalışan kodları koru.

- Wi-Fi bağlantı mantığını görev gerektirmedikçe değiştirme.
- Wi-Fi bilgilerinin alınması, kaydedilmesi ve kullanılmasıyla ilgili çalışan akışı bozma.
- Wi-Fi yeniden bağlanma/reconnect davranışını gereksiz yere değiştirme.
- Cihazın internete çıkmasını sağlayan çalışan kodlarda refactor yapma.
- Başka bir özellik geliştirirken Wi-Fi sistemini yeniden tasarlama.
- Wi-Fi ile ilgili çalışan fonksiyon isimlerini, akışlarını veya veri formatlarını gereksiz yere değiştirme.
- Yeni görev Wi-Fi sistemiyle doğrudan ilgili değilse bu kodlara dokunma.

## 2. ESP32 Bluetooth Bağlantısı ve Kurulum Akışı

Cihazın Bluetooth bağlantısının kurulması ve Bluetooth üzerinden ilk kurulumunun yapılmasıyla ilgili mevcut çalışan kodları koru.

- Bluetooth cihaz bulma/tarama mantığını görev gerektirmedikçe değiştirme.
- Bluetooth bağlantı kurulma akışını bozma.
- Bluetooth üzerinden ESP32'ye gönderilen bilgilerin formatını gereksiz yere değiştirme.
- Bluetooth üzerinden Wi-Fi bilgilerinin cihaza aktarılmasıyla ilgili çalışan kodu bozma.
- Bağlantı durumu, servis, characteristic veya haberleşme yapısını görev gerektirmedikçe değiştirme.
- Başka bir özellik eklerken Bluetooth kodunu "iyileştirme" amacıyla yeniden yazma.
- Yeni görev Bluetooth sistemiyle doğrudan ilgili değilse bu kodlara dokunma.

## 3. Röle İşlemleri

ESP32'nin röleyi kontrol etmesiyle ilgili mevcut çalışan kodları ve davranışları koru.

- Rölenin açılması/kapanmasıyla ilgili mevcut mantığı görev gerektirmedikçe değiştirme.
- Röle tetikleme süresini gereksiz yere değiştirme.
- Rölenin GPIO/pin yapılandırmasını görev gerektirmedikçe değiştirme.
- MQTT veya uygulamadan gelen röle komutlarının mevcut çalışma biçimini bozma.
- Röle güvenliği açısından mevcut otomatik kapanma davranışını koru.
- Başka bir özellik geliştirirken çalışan röle kodunu yeniden yazma veya refactor etme.
- Yeni görev röle kontrolüyle doğrudan ilgili değilse bu kodlara dokunma.

## Kritik Alanlarda Değişiklik Zorunluysa

Bir görev yukarıdaki kritik alanlardan birinin değiştirilmesini gerçekten gerektiriyorsa değişiklik yapılabilir.

Bu durumda:

1. Önce mevcut çalışma mantığını incele.
2. Değişikliğin neden gerekli olduğunu belirle.
3. Sadece görev için gerekli minimum değişikliği yap.
4. İlgisiz bölümlere dokunma.
5. Mevcut davranışların korunup korunmadığını kontrol et.
6. Değişiklikten sonra ilgili bağlantı veya kontrol akışını test et.

Amaç kritik kodları tamamen kilitlemek değil; başka özellikler geliştirilirken çalışan Wi-Fi, Bluetooth ve röle sistemlerinin yanlışlıkla bozulmasını önlemektir.

---

# Flutter Arayüz ve Responsive Tasarım Kuralları

Flutter arayüzlerinde hiçbir ekranda `RenderFlex overflow`, taşma, kesilme veya ekran dışına çıkma kabul edilmez.

Yeni ekran oluştururken veya mevcut ekranı değiştirirken arayüz mutlaka farklı ekran boyutlarına uyumlu tasarlanmalıdır.

## Temel Responsive Kuralları

- Sabit telefon ekranı ölçülerine göre tasarım yapma.
- Mümkün olduğunca sabit `width` ve `height` değerlerinden kaçın.
- Ekran genişliğini ve yüksekliğini dikkate almak için gerektiğinde `MediaQuery`, `LayoutBuilder`, `Expanded`, `Flexible`, `Wrap` ve benzeri responsive yapıları kullan.
- `Row` içerisinde uzun metin veya geniş widget varsa taşma ihtimalini mutlaka kontrol et.
- `Row` çocuklarında gerektiğinde `Expanded` veya `Flexible` kullan.
- Yan yana öğeler küçük ekranlarda sığmıyorsa `Wrap`, alternatif yerleşim veya dikey yerleşim kullan.
- İçeriği ekran yüksekliğini aşabilecek sayfalarda `SingleChildScrollView`, `ListView` veya uygun scroll yapısı kullan.
- Scroll gerektiren bir ekranı sadece `Column` ile oluşturarak dikey taşmaya sebep olma.
- `Column` içinde scrollable widget kullanırken uygun `Expanded`, `Flexible` veya `shrinkWrap` yaklaşımını kullan.
- Kullanıcı klavyeyi açtığında form alanları veya butonlar ekran dışına taşmamalıdır.
- Klavye açıldığında `MediaQuery.viewInsets` etkisini dikkate al.
- Gerekirse form ekranlarını scrollable yap.
- `SafeArea` gereken ekranlarda kullan ve sistem çentik/status bar/navigation bar alanlarını dikkate al.

## Dialog, BottomSheet ve Form Kuralları

- Dialog içeriklerini sabit yüksekliğe mahkum etme.
- Uzun dialog içerikleri scroll edilebilir olmalıdır.
- Dialog yüksekliği ekran yüksekliğini aşmamalıdır.
- Dialog genişliği küçük ekranlarda ekran dışına taşmamalıdır.
- Büyük ekranlarda gereksiz yere tüm genişliği kullanmamalıdır.
- Form alanları ekran genişliğine göre esnemelidir.
- Yan yana iki form alanı küçük ekranda sığmıyorsa responsive olarak alt alta geçebilmelidir.
- `AlertDialog`, `Dialog`, `showModalBottomSheet` ve özel modal yapılar küçük ekranlarda ayrıca kontrol edilmelidir.
- Bottom sheet kullanılıyorsa klavye açıldığında içerik görünür kalmalıdır.
- Kaydet/İptal gibi ana aksiyon butonları içerik taşsa bile erişilebilir kalmalıdır.

## Metin Kuralları

- Uzun başlık, açıklama ve kullanıcı verilerinin taşmayacağını varsayma.
- Gerekli yerlerde `maxLines`, `softWrap` ve uygun `TextOverflow` davranışı kullan.
- Önemli bilgileri gereksiz yere `ellipsis` ile gizleme; gerekiyorsa satır sayısını artır veya layout'u esnet.
- Türkçe metinlerin İngilizceye göre daha uzun olabileceğini hesaba kat.
- Dinamik kullanıcı verileri için yeterli alan bırak.
- Sistem font boyutu büyütüldüğünde arayüzün tamamen bozulmamasına dikkat et.
- Responsive tasarım sorununu çözmek için global olarak kullanıcı metin ölçeğini zorla küçültme veya accessibility ayarlarını devre dışı bırakma.

## Dropdown ve Seçim Alanları

- `DropdownButton`, `DropdownButtonFormField` ve benzeri seçim alanlarının metinleri küçük ekranlarda taşmamalıdır.
- Uzun seçenek metinlerinde uygun esnek yerleşim kullan.
- Yan yana bulunan İl / İlçe gibi alanların toplam genişliğini sabit piksel değerleriyle belirleme.
- Seçim alanlarının label ve içerik metinleri birbirinin üzerine binmemelidir.

## Responsive Kontrol Zorunluluğu

Bir Flutter ekranı tamamlanmış sayılmadan önce en az aşağıdaki durumlar düşünülmelidir:

- Dar telefon ekranı
- Normal telefon ekranı
- Büyük telefon ekranı
- Dikey kullanım
- Yatay kullanımın desteklendiği ekranlar
- Klavye açık durum
- Uzun metin / uzun kullanıcı verisi
- Birden fazla satıra taşabilecek başlıklar
- Büyük sistem yazı boyutu

## Flutter Hata Kabul Kriterleri

Aşağıdaki hatalar mevcutsa görev tamamlanmış kabul edilmez:

- `RIGHT OVERFLOWED BY ... PIXELS`
- `BOTTOM OVERFLOWED BY ... PIXELS`
- `RenderFlex overflowed`
- Widget'ların ekran dışına çıkması
- Butonların veya giriş alanlarının erişilemez hale gelmesi
- Metinlerin birbirinin üzerine binmesi
- Klavye açıldığında aktif alanların kullanılamaz hale gelmesi
- Küçük ekranlarda dialog içeriğinin kesilmesi

Eğer bu hatalardan biri oluşuyorsa layout responsive hale getirilmeden görev tamamlandı olarak belirtilmemelidir.

---

# Değişiklik Sonrası Kontrol

Kod değişikliği tamamlandıktan sonra:

1. İlgili dosyalarda derleme hatası olmadığını kontrol et.
2. Flutter kodunda analyzer hatalarını kontrol et.
3. Değiştirilen ekranlarda taşma/overflow oluşmadığını kontrol et.
4. Değişikliğin mevcut çalışan akışları bozmadığını kontrol et.
5. Yeni özellik için gerekli ana kullanım senaryosunu test et.
6. Kritik ESP32 Wi-Fi, Bluetooth ve röle alanlarına gereksiz değişiklik yapılmadığını kontrol et.

---

# Ana İlke

Yeni özellik geliştirmek serbesttir.

Ancak yeni bir özellik eklerken çalışan başka bir özelliği gereksiz yere değiştirmek veya bozmak kabul edilmez.

Özellikle:

- ESP32 Wi-Fi / internet bağlantısı
- ESP32 Bluetooth bağlantısı ve ilk kurulum akışı
- Röle kontrol işlemleri
- Flutter ekranlarının responsive ve taşmasız çalışması

projenin korunması gereken temel davranışlarıdır.
