# QR ve GM60 Kapı Açma Özelliği – Yapay Zekâ Ajanı Görev Talimatı

Bu projede WROOM tabanlı röle modülü, GM60 QR okuyucu, mobil uygulama ve sunucu bileşenleri kullanılarak QR kod aracılığıyla kapı açma özelliği geliştirilecektir.

Çalışma küçük, kontrollü ve test edilebilir aşamalar hâlinde yürütülecektir. Sistem bir bütün olarak tek seferde geliştirilmeyecektir.

> **En önemli öncelik:** Sahada çalışan eski ESP32-C3 röle modülleri QR özelliğine sahip değildir ve düzgün çalışmaya devam etmelidir. Yeni QR özelliğinin tamamlanması, eski cihazların kararlılığından daha önemli değildir.

## Değişmez çalışma kuralları

1. Her seferinde yalnızca aşağıda belirtilen tek bir aşama uygulanacaktır.
2. Bir aşama tamamlandıktan sonra çalışma durdurulacaktır.
3. Her aşamanın sonunda değiştirilen dosyalar, gerçekleştirilen işlemler, test adımları, beklenen sonuç, logların yeri ve geri alma yöntemi açıkça bildirilecektir.
4. Gerçek telefon, GM60, WROOM ve röle ile test yapılmadan sonraki aşamaya geçilmeyecektir.
5. Kullanıcı açıkça **“Bu aşama başarılı, sonraki aşamaya geç”** demeden yeni aşamaya başlanmayacaktır.
6. Test başarısız olursa yalnızca mevcut aşamadaki sorun teşhis edilip düzeltilecektir.
7. Önceki aşamada çalışan bir özellik değiştirilmeden önce kullanıcı bilgilendirilecektir.
8. Büyük çaplı kod değişikliklerinden, gereksiz yeniden yapılandırmadan ve toplu dosya değişikliklerinden kaçınılacaktır.
9. Aşağıdaki mevcut çalışan özellikler korunacaktır:
   - ESP32/WROOM internet bağlantısı
   - Wi-Fi kurulum sistemi
   - Bluetooth üzerinden Wi-Fi yapılandırması
   - MQTT veya mevcut sunucu iletişimi
   - Mevcut röleyle kapı açma sistemi
   - Kullanıcı giriş sistemi
   - Rol ve yetkilendirme sistemi
   - Mevcut cihaz kayıt ve cihaz sınırlama sistemi
10. Yeni özellikler mümkün olduğunca ayrı servis, sınıf, endpoint ve modüller hâlinde geliştirilecektir.
11. Sabit IP, kullanıcı kimliği, site kimliği, kapı kimliği, parola veya gizli anahtarlar kaynak koduna gömülmeyecektir.
12. Veritabanı değişikliği gerekiyorsa önce migration hazırlanacak; mevcut veriler silinmeyecektir.
13. Her aşamadan önce mevcut durum incelenecektir. Teknoloji veya dosya yapısı bilinmiyorsa tahminde bulunulmayacak, kullanıcıdan bilgi istenecektir.
14. Uygulamanın mevcut tasarımı korunacaktır. Flutter ekranlarında taşma oluşturulmayacak; küçük ve büyük ekranlarda responsive davranış sürdürülecektir.
15. Güvenlik özellikleri uygulama içinde taklit edilmeyecektir. Nihai yetkilendirme kararını sunucu verecektir.
16. Her aşama için geri alma yöntemi belirtilecektir.
17. Her aşamadaki değişiklikler mümkünse ayrı bir Git commit oluşturulabilecek kadar temiz ve sınırlı olacaktır. Kullanıcının mevcut değişiklikleri silinmeyecek veya geri alınmayacaktır.
18. Değişiklikten önce ilgili mevcut akışlar ve testler belirlenecektir. Zorunlu olmadıkça mevcut API, protokol, veri formatı veya donanım davranışı değiştirilmeyecektir.
19. Her aşamada geriye dönük uyumluluk gözetilecektir. Eski istemci, cihaz, firmware veya API etkilenebilecekse uyumluluk planı önceden bildirilecektir.
20. Uygulama, backend, WROOM ve GM60 arasındaki iletişim modüler ve gevşek bağlı tasarlanacaktır.
21. Loglama merkezi, yapılandırılabilir ve güvenli olacaktır. Token, parola, gizli anahtar ve gereksiz kişisel veriler açık biçimde loglanmayacaktır.
22. Loglarda mümkün olduğunca korelasyon/işlem kimliği ile kullanıcı, site, kapı, cihaz ve sonuç bilgileri güvenli biçimde tutulacaktır.
23. Her yeni modülün sorumlulukları, giriş/çıkışları ve hata davranışları tanımlanacaktır.
24. Logların yeri, filtreleme yöntemi, saklama süresi ve erişim yetkileri belirtilecektir.
25. Yeni loglama veya modülerleştirme mevcut entegrasyonları etkiliyorsa geriye dönük uyumlu geçiş planı sunulacaktır.
26. Her aşamanın sonunda regresyon kontrolü yapılacaktır. Yeni özellik çalışsa bile eski bir özellik bozulmuşsa aşama tamamlanmış sayılmayacaktır.
27. Hata durumunda sistem güvenli varsayılan davranışa geçecektir. Loglama başarısız olsa bile yetkilendirme kontrolleri devre dışı kalmayacaktır.

## Sahadaki eski ESP32-C3 cihazların kesin korunması

28. Sahada çalışan eski ESP32-C3 röle modülleri **legacy cihaz** olarak kabul edilecektir. Bu cihazlarda GM60 ve QR özelliği bulunmayacaktır.
29. QR özelliği yalnızca yeni WROOM tabanlı ve GM60 bağlı cihazlar için geliştirilecektir. Eski ESP32-C3 firmware'ine GM60 UART veya QR kodu eklenmeyecektir.
30. Kullanıcı açıkça izin vermedikçe eski ESP32-C3 firmware dosyalarında hiçbir değişiklik yapılmayacak, bu cihazlara firmware derlenmeyecek ve OTA güncellemesi gönderilmeyecektir.
31. Eski C3 cihazların Wi-Fi, Bluetooth ile kurulum, MQTT, röle süresi, cihaz kimliği, bağlantı yenileme, watchdog ve OTA davranışları aynen korunacaktır.
32. Backend ve veritabanı değişiklikleri geriye dönük uyumlu olacaktır. Eski cihazların kullandığı endpoint, MQTT topic, JSON alanları, mesaj ve cevap yapıları bozulmayacaktır.
33. Mevcut mesajlara alan eklemek gerekirse yeni alanlar isteğe bağlı olacak; eski cihaz bu alanı göndermediğinde çalışmaya devam edecektir.
34. QR özelliği cihaz yeteneğine göre açılacaktır. Mevcut mimariye göre `deviceType`, `qrReaderEnabled` veya `capabilities` benzeri alanlar değerlendirilecek; kesin isimler proje incelendikten sonra belirlenecektir.
35. Mevcut tüm cihaz kayıtlarında QR yeteneği varsayılan olarak **kapalı/false** olacaktır. Migration hiçbir eski cihazı kendiliğinden QR destekli yapmayacaktır.
36. QR özelliği global açılmayacak; yalnızca seçilmiş test sitesi, kapı ve yeni WROOM cihazında feature flag veya kayıtlı cihaz yeteneğiyle etkinleştirilecektir.
37. Eski ve yeni cihaz ayrımında mobil uygulamanın beyanına güvenilmeyecek; sunucudaki kayıtlı cihaz kimliği ve cihaz türü esas alınacaktır.
38. QR doğrulama komutları eski C3 cihazların dinlediği mevcut MQTT topic'e gönderilmeyecektir. Ayrı endpoint, topic veya geriye dönük uyumlu mesaj türü kullanılacaktır.
39. Yeni QR mesajı yanlışlıkla eski cihaza ulaşsa bile röleyi çalıştırmamalı, bağlantıyı kesmemeli ve cihazı yeniden başlatma/hata döngüsüne sokmamalıdır.
40. Eski C3'ün normal uygulama üzerinden kapı açma işlemi QR süresi, tek kullanım, geofence veya QR token kontrollerine bağlanmayacaktır.
41. QR, geofence veya token servisindeki hata eski C3 cihazın normal sunucu iletişimini ve mevcut kapı açma yöntemini etkilemeyecektir.
42. Ortak backend servisinde değişiklik gerekirse eski C3 davranışı önce testlerle kayıt altına alınacak ve değişiklikten sonra aynı testler tekrarlanacaktır.
43. Eski C3 regresyon testlerinden biri başarısızsa aşama tamamlanmış sayılmayacak ve sonraki aşamaya geçilmeyecektir.
44. Her aşama raporunda ayrı bir **“Eski ESP32-C3 Etki Kontrolü”** başlığı bulunacaktır. Bu bölümde eski firmware'e dokunulup dokunulmadığı, ortak backend değişiklikleri, MQTT/API uyumluluğu, yapılan regresyon testleri ve kalan riskler yazılacaktır.
45. Eski C3 firmware'i yeni WROOM firmware'iyle birleştirilmeyecek veya QR için yeniden yazılmayacaktır. Ortak kod zorunluysa önce kullanıcıya gerekçe ve riskler açıklanarak onay alınacaktır.
46. Sahadaki eski ESP32-C3 cihazların kararlı çalışması en yüksek önceliktir. Etkisi belirsiz değişiklik uygulanmayacaktır.

## Temel sistem akışı

Hedeflenen nihai QR akışı:

1. Daire kullanıcısı veya yetkili site kullanıcısı uygulamadan QR talep eder.
2. Sunucu kullanıcının rolünü ve ilgili site/kapı yetkisini kontrol eder.
3. Sunucu QR tokeni üretir.
4. Mobil uygulama tokeni QR olarak gösterir.
5. GM60 QR'ı okur ve UART üzerinden yeni WROOM cihazına gönderir.
6. WROOM tokeni sunucuya doğrulatır.
7. Sunucu izin verirse yalnızca ilgili yeni WROOM cihazına röle izni verir.
8. Sonraki aşamalarda süre, tek kullanım ve geofence eklenir.

QR içinde kullanıcı adı, daire numarası, parola, erişim anahtarı veya tahmin edilebilir bilgi olmayacaktır. Yalnızca rastgele ve tahmin edilemez bir token bulunacaktır.

## Roller

- Daire kullanıcısı
- Site yöneticisi veya kapı açma yetkisi bulunan site kullanıcısı

Her kullanıcı yalnızca yetkili olduğu site ve kapılar için QR oluşturabilir. Süper kullanıcı ve diğer mevcut roller korunacaktır.

# AŞAMA 0 — Yalnızca inceleme ve planlama

**Henüz kod yazılmayacaktır.** Proje incelenerek şunlar raporlanacaktır:

- Mobil uygulama teknolojisi ve ilgili klasörler
- Backend teknolojisi ve ilgili klasörler
- Kullanıcı rollerinin tanımlandığı yer
- Site, daire, kapı ve cihaz veri ilişkileri
- Mevcut kapı açma akışı
- WROOM'un MQTT/HTTP iletişim yöntemi
- GM60 UART kodunun mevcut olup olmadığı
- QR üretiminde kullanılabilecek mevcut paketler
- Mevcut loglama altyapısı, formatı, erişimi ve saklama politikası
- Mevcut modül ve servis sınırları
- Mevcut testler ve uygulanacak regresyon testleri
- Sahadaki eski ESP32-C3 firmware dosyaları
- Eski C3 ile yeni WROOM firmware'inin nasıl ayrıldığı
- Eski C3'lerin kullandığı MQTT topic, API ve mesaj formatları
- Cihaz türü/yetenek alanlarının mevcut olup olmadığı
- QR'ın yalnızca yeni WROOM'da etkinleştirilme yöntemi
- Backend değişikliklerinin eski cihazlara olası etkileri
- Eski C3 için regresyon test planı
- Yanlış firmware/QR komutunun eski cihaza gitmesini önleme yöntemi
- Değiştirilecek veya eklenecek dosyalar
- Aşama 1 için en küçük uygulama planı
- Kullanıcıdan istenmesi gereken eksik bilgiler

İncelemenin ardından çalışma durdurulacak ve kullanıcı onayı beklenecektir.

# AŞAMA 1 — Süresiz QR ile temel uçtan uca test

Bu aşamada süre, geofence, tek kullanım, cihaz bütünlüğü veya ekran görüntüsü önleme eklenmeyecektir.

Amaç: **Mobil uygulama → QR → GM60 → yeni WROOM → sunucu → röle** zincirini doğrulamaktır.

1. Sunucuda rastgele ve tahmin edilemez token üretilecektir.
2. Token; kullanıcı, rol, site, kapı, aktif/pasif durum ve oluşturulma zamanıyla ilişkilendirilecektir.
3. Token bu aşamada süresiz olabilir ancak yönetici tarafından iptal edilebilir olacaktır.
4. Yalnızca yetkili kullanıcı QR oluşturabilecektir.
5. Daire kullanıcısı ve site kullanıcısı için ayrı test senaryosu olacaktır.
6. GM60 tokeni yeni WROOM üzerinden doğrulama sistemine gönderecektir.
7. Sunucu yalnızca tokenin bağlı olduğu kapıya ve QR özellikli yeni WROOM'a izin verecektir.
8. Röle mevcut güvenli açma süresi kadar çalışacaktır.
9. Başarılı/başarısız denemeler güvenli biçimde loglanacaktır.
10. Token açık biçimde loglanmayacaktır.
11. Başka site/kapıya ait token reddedilecektir.
12. Yeni modüller mevcut akışlardan ayrılacaktır.
13. Mevcut API, MQTT topic veya veri formatı bozulmayacaktır.
14. QR ekranı/özelliği eski C3'e bağlı kapılarda gösterilmeyecek veya kullanılamayacaktır.

Testler:

- Daire ve site kullanıcısı QR oluşturup doğru yeni WROOM kapısını açabiliyor mu?
- Geçersiz ve başka kapı/siteye ait QR reddediliyor mu?
- İnternet yokken QR kapısı güvenli biçimde kapalı kalıyor mu?
- Yeni WROOM'un Wi-Fi, Bluetooth kurulumu ve normal kapı açması çalışıyor mu?
- Loglar güvenli ve yeterli mi?
- Sahadaki eski C3 normal komutla bağlanıp kapıyı eskisi gibi açıyor mu?
- Eski C3 QR özelliği görmüyor ve QR mesajı almıyor mu?
- QR servisinin kapatılması/bozulması eski C3'ü etkilemiyor mu?

Sonuçlardan sonra dur ve onay bekle.

# AŞAMA 2 — QR koduna süre ekleme

Yalnızca Aşama 1 onaylandıktan sonra:

1. Token kayıtlarına son kullanma zamanı ekle.
2. Süreyi ayarlardan değiştirilebilir yap; ilk test 60 saniye olsun.
3. Süreyi yalnızca sunucu saatine göre doğrula.
4. Süresi geçen token röleyi çalıştırmasın.
5. Uygulamada kalan süreyi göster; dolunca QR'ı kaldır veya süresi doldu durumuna geçir.
6. Güvenlik kararını uygulama sayacı değil sunucu versin.
7. Süre kontrolü ayrı, test edilebilir ve geriye uyumlu olsun.

Testler: 60 saniye içinde/sonrasında kullanım, telefon saatini değiştirme, süre dolmadan tekrar kullanım, loglar, önceki işlevler ve eski C3 regresyon testlerinin tamamı.

Sonuçlardan sonra dur ve onay bekle.

# AŞAMA 3 — QR kodunu tek kullanımlık yapma

Yalnızca Aşama 2 onaylandıktan sonra:

1. Kullanılan tokeni atomik biçimde tüket.
2. İkinci okutmayı reddet.
3. Eşzamanlı iki istekte yalnızca birinin başarılı olmasını sağla.
4. Yarış durumunu veritabanı seviyesinde engelle.
5. Kullanım zamanı ve kapıyı güvenli biçimde logla.
6. Kullanılmadan süresi geçen tokeni ayrı durumda tut.

Testler: ilk/ikinci okutma, hızlı tekrar, eşzamanlı iki cihaz, loglar, önceki işlevler ve eski C3 regresyon testlerinin tamamı.

Sonuçlardan sonra dur ve onay bekle.

# AŞAMA 4 — QR süresini güvenli değere düşürme

Yalnızca Aşama 3 onaylandıktan sonra:

1. Süreyi önce 30 saniyeye indir.
2. Gerçek testten sonra 15 ve gerekirse 10 saniyeyi ayrı ayrı dene.
3. Süreyi kaynak kod yerine sunucu/site ayarından yönet.
4. Gereksiz sürekli token üretimini engelle.
5. Yeni QR oluşunca eski QR'ın davranışını açıkça tanımla.
6. Değişiklikleri logla ve geri alınabilir yap.

Her süre saha testinden sonra dur. Eski C3 regresyon testlerini tekrarla.

# AŞAMA 5 — Temel geofence kontrolü

Yalnızca önceki aşamalar onaylandıktan sonra:

1. Her site için enlem, boylam ve izin verilen yarıçapı sunucuda tanımla.
2. İlk yarıçap 150 metre olsun.
3. Uygulama QR istemeden hemen önce güncel konum alsın.
4. Sunucuya enlem, boylam, doğruluk ve ölçüm zamanı gönderilsin.
5. Mesafeyi sunucu hesaplasın; istemcinin `geofence içindeyim` beyanına güvenme.
6. Dışarıdaysa, izin kapalıysa veya konum alınamıyorsa QR üretme.
7. İlk doğruluk şartını saha testine uygun gevşek ve loglanabilir tut.
8. Site koordinatlarını uygulamaya sabit gömme.
9. Süre ve tek kullanım kontrollerini koru.
10. Hassas konumu gereksiz veya süresiz loglama; saklama/maskeleme politikasını belirt.
11. Geofence'i ayrı servis/modül olarak geliştir.

Saha testleri: site içi/dışı, sınır, izin kapalı, zayıf GPS, Android/iOS farkı, gecikme, güvenli loglar, önceki işlevler ve eski C3 regresyon testlerinin tamamı.

Sonuçlardan sonra dur ve onay bekle.

# AŞAMA 6 — Geofence güvenliğini küçük alt adımlarla artırma

Her alt adım ayrı uygulanacak ve testten sonra durulacaktır:

1. Konumun en fazla 10 saniyelik olmasını doğrula.
2. Kabul edilebilir doğruluğu saha testine göre belirle.
3. Android mock location göstergelerini incele ve güvenli biçimde logla.
4. Root/jailbreak kontrolünü ayrı aşamada değerlendir.
5. Android Play Integrity'yi ayrı aşamada uygula.
6. iOS App Attest/DeviceCheck'i ayrı aşamada uygula.
7. Kullanıcıya anlaşılır hata göster.
8. Her güvenlik kontrolünü sunucu tarafı feature flag ile aşamalı aç.
9. Her alt adımda geri alma, loglama ve eski C3 regresyon testlerini uygula.

# AŞAMA 7 — Paylaşım ve kötüye kullanım önlemleri

1. Kullanıcı başına QR üretme hız sınırı ekle.
2. Kısa sürede çok sayıda QR üretimini ve başarısız doğrulamayı sınırla.
3. Çok üretim, geçersiz okutma, farklı kapılarda hızlı kullanım ve geofence ihlallerini güvenli biçimde kaydet.
4. Yöneticiye aktif QR'ları iptal etme olanağı ver.
5. Hesap veya kayıtlı telefon pasifse tokenleri geçersiz yap.
6. Ekran görüntüsü paylaşımının tamamen engellenemeyeceğini kabul et; eski görüntüleri süre ve tek kullanımla işlevsiz yap.
7. Önlemleri bağımsız modüllerde geliştir.
8. Her değişiklikte eski C3 regresyon testlerini uygula.

## Her aşamada zorunlu eski ESP32-C3 regresyon kontrolü

- Cihaz sunucuya ve MQTT'ye bağlanabiliyor mu?
- Mevcut abonelikleri ve durum mesajları çalışıyor mu?
- Normal kapı açma komutu çalışıyor mu?
- Röle yalnızca bir kez ve doğru süreyle çalışıyor mu?
- Wi-Fi kesilip geldiğinde yeniden bağlanıyor mu?
- Bluetooth ile Wi-Fi kurulumu korunuyor mu?
- QR özelliği eski cihaz/kapı için görünmüyor mu?
- QR mesajları eski cihaza gönderilmiyor mu?
- QR veya geofence servisindeki hata eski cihazı etkilemiyor mu?

Bu kontrollerden biri başarısız olursa aşama tamamlanmış sayılmayacaktır.

## Nihai güvenlik ilkeleri

- Kapıyı açma kararını mobil uygulama vermeyecektir.
- Yeni WROOM yalnızca sunucunun açık onayıyla QR üzerinden röleyi çalıştıracaktır.
- Yetki, süre, kullanım, site, kapı ve geofence kontrolleri sunucuda yapılacaktır.
- QR tokeni tahmin edilemez olacak ve mümkünse veritabanında hashlenmiş saklanacaktır.
- Tokenler kullanıcı, site ve kapıyla ilişkilendirilecektir.
- Token, parola, gizli anahtar ve gereksiz kişisel veri açık loglanmayacaktır.
- Log erişimi rol tabanlı; saklama ve silme politikası tanımlı olacaktır.
- Sunucuya erişilemediğinde QR akışı kapıyı açmayacaktır.
- QR özelliği önce test ortamında, sonra yalnızca seçilmiş yeni WROOM cihazında pilot uygulanacaktır.
- Eski ESP32-C3 cihazlarda QR özelliği varsayılan olarak kapalıdır ve mevcut kapı açma davranışı aynen korunur.
- Her aşamada geri alma yöntemi, etkilenen modüller, uyumluluk riskleri ve **Eski ESP32-C3 Etki Kontrolü** raporlanacaktır.

---

## Şimdi yapılacak görev

**Yalnızca AŞAMA 0 gerçekleştirilecektir. Kod yazılmayacak, dosya değiştirilmeyecek ve diğer aşamalara geçilmeyecektir. İnceleme raporu sunulduktan sonra kullanıcı onayı beklenecektir.**
