# AHBU – Antigravity Geliştirme Promptu
## QR Kod ile Güvenli Kapı Açma ve Dokunmatik Yerel Yönetim Ekranı

Bu dosya, mevcut AHBU projesinin çalışan özelliklerini bozmadan, 2.4" 240x320 ST7789 kapasitif dokunmatik ekran için profesyonel kullanıcı arayüzünün ve yerel yönetim fonksiyonlarının geliştirilmesi amacıyla hazırlanmıştır.

> **KRİTİK KURAL:** Mevcut çalışan sistemleri bozma. Yeni özellikleri mevcut mimariye mümkün olduğunca modüler şekilde ekle. Çalışan kodu gereksiz yere yeniden yazma.

---

# 1. PROJENİN ANA AMACI

AHBU cihazının temel görevi:

**QR kod okutma → QR doğrulama → yetkiliyse kapıyı açma**

Dokunmatik ekran bu temel görevi destekleyecek ve gerektiğinde site yöneticisinin yerel cihaz yönetimi yapmasını sağlayacaktır.

Cihazı gereksiz bir genel amaçlı sistem veya karmaşık dashboard haline getirme.

Ana kullanıcı deneyimi:

**Bekle → QR okut → doğrula → kapıyı aç / reddet → tekrar bekle**

---

# 2. MEVCUT ÇALIŞAN SİSTEMLER KORUNACAK

Kod üzerinde çalışmaya başlamadan önce mevcut projeyi analiz et.

Aşağıdaki özelliklerin mevcut çalışma mantığını değiştirme:

- QR okuyucu / GM60
- QR doğrulama
- Wi-Fi bağlantısı
- Bluetooth provisioning
- İnternet bağlantısı
- API haberleşmesi
- MQTT
- MQTT LWT
- Röle / kapı açma mekanizması
- UART haberleşmesi
- Cihaz ID sistemi
- MAC / donanım bilgileri
- Mevcut pin yapılandırması
- Mevcut bağlantı ve yeniden bağlanma mantıkları

Özellikle çalışan Wi-Fi, Bluetooth provisioning ve MQTT/LWT kodlarını gereksiz yere yeniden yazma.

Yeni ekran sistemi bu altyapının üzerine kurulmalıdır.

---

# 3. GELİŞTİRMEYE BAŞLAMADAN ÖNCE ANALİZ

İlk aşamada hiçbir kodu değiştirme.

Önce projeyi incele ve aşağıdakileri tespit et:

1. Ana `.ino` / `.cpp` dosyaları
2. Ekranla ilgili mevcut kodlar
3. Touch sürücüsü
4. ST7789 bağlantısı
5. GM60 UART bağlantısı
6. QR doğrulama fonksiyonları
7. Röle tetikleme fonksiyonu
8. Wi-Fi bağlantı fonksiyonları
9. MQTT bağlantı fonksiyonları
10. API bağlantı fonksiyonları
11. Cihaz ID yapısı
12. Bluetooth provisioning
13. Mevcut loop yapısı
14. Mevcut `delay()` kullanımları
15. Mevcut state/status yapısı

Analiz sonunda önce kısa bir teknik rapor çıkar:

- Mevcut mimari
- İlgili dosyalar
- Değiştirilmesi gereken dosyalar
- Korunması gereken kritik kodlar
- Yeni modüller
- Olası riskler

Sonra geliştirmeye geç.

---

# 4. EKRAN DONANIMI

Hedef ekran:

- 2.4"
- 240x320
- ST7789
- SPI
- Kapasitif dokunmatik

Arayüz bu çözünürlüğe özel hazırlanmalıdır.

Telefon/tablet arayüzünü küçültüp ekrana koyma.

240x320 üzerinde:

- büyük dokunmatik alanlar
- okunabilir yazılar
- sade ikonlar
- yeterli boşluk
- yüksek kontrast
- net durum mesajları

kullan.

Ekranda taşma kesinlikle olmamalıdır.

---

# 5. PROFESYONEL UI/UX

Arayüz:

- modern
- sade
- profesyonel
- kurumsal
- kolay anlaşılır
- dokunmatik kullanıma uygun
- yüksek kontrastlı
- göz yormayan
- gereksiz animasyonlardan arındırılmış

olmalıdır.

Küçük yazılar ve küçük butonlar kullanma.

Her ekranın tek bir ana amacı olmalı.

Kullanıcı hangi durumda olduğunu tek bakışta anlayabilmelidir.

---

# 6. ANA BEKLEME EKRANI

Normal durumda ekranda:

- AHBU logosu
- "QR Kodunuzu Okutunuz"
- gerekiyorsa bağlantı durumunun küçük bir göstergesi
- gerektiğinde ayarlara giriş için uygun bir dokunmatik alan

bulunabilir.

Ana ekran kalabalık olmamalıdır.

QR okutma cihazın temel işlevi olduğundan ekranda bunun görsel önceliği yüksek olmalıdır.

---

# 7. QR DURUMLARI

QR işlemi sırasında ayrı durumlar kullanılmalıdır.

Örnek state yapısı:

```cpp
IDLE
QR_SCANNING
VALIDATING
DOOR_OPENED
INVALID_QR
ADMIN_LOGIN
ADMIN_MENU
SETTINGS
```

### IDLE

Göster:

**QR Kodunuzu Okutunuz**

### QR_SCANNING

Göster:

**QR Kod Okunuyor...**

### VALIDATING

Göster:

**Lütfen bekleyiniz**

### Başarılı

Göster:

**Kapı Açıldı**

Gerekirse kısa süreli görsel başarı göstergesi kullan.

### Başarısız

Göster:

**Geçersiz / Yetkisiz QR Kod**

Hata mesajı anlaşılır olmalı.

İşlem sonrasında otomatik olarak ana bekleme ekranına dön.

---

# 8. EKRAN UYKU MODU

## KRİTİK

Ekran sürekli açık ve tam parlaklıkta beklememelidir.

Amaç:

- gereksiz enerji tüketimini azaltmak
- arka aydınlatmanın gereksiz kullanımını önlemek
- sürekli çalışan cihazda ekran ömrünü korumak

Varsayılan ekran uyku süresi:

**30 saniye**

Örnek:

```cpp
const unsigned long SCREEN_SLEEP_TIMEOUT = 30000;
```

Bu değer merkezi bir yerde tutulmalıdır.

Gelecekte ayarlardan değiştirilebilecek şekilde tasarlanmalıdır.

---

# 9. EKRAN UYKUSUNDA SİSTEM ÇALIŞMAYA DEVAM EDECEK

Ekran uykuya geçtiğinde:

- ESP32 çalışmaya devam etmeli
- Wi-Fi çalışmaya devam etmeli
- MQTT çalışmaya devam etmeli
- API çalışmaya devam etmeli
- GM60 QR okuyucu çalışmaya devam etmeli
- QR doğrulama sistemi çalışmaya devam etmeli
- röle sistemi çalışmaya devam etmeli

Ekran uykusu cihazın ana sistemini durdurmamalıdır.

---

# 10. EKRAN UYKU YÖNTEMİ

Mümkünse yalnızca ST7789 ekranın **backlight/arka aydınlatması kapatılmalıdır**.

Ekran kontrolcüsünü gereksiz yere tamamen resetleme.

Ekranı kapatıp açmak için tüm cihazı yeniden başlatma.

Uyku mekanizması non-blocking olmalıdır.

`delay()` kullanarak sistemin tamamını bloke eden bir çözüm oluşturma.

`millis()` tabanlı zamanlama kullan.

---

# 11. DOKUNARAK UYANDIRMA

Ekran uyku modundayken kullanıcı ekrana dokunursa:

1. Ekran hemen uyandırılmalı.
2. Arka aydınlatma açılmalı.
3. Ana QR bekleme ekranı gösterilmeli.
4. İlk dokunma başka bir butonu tetiklememeli.
5. Yeni uyku zamanlayıcısı başlatılmalı.

Önemli:

**İlk dokunma sadece ekranı uyandırmalıdır.**

Örneğin kullanıcı ekranda ayarlar bölgesine dokunduğunda ekran uyanırken aynı dokunuş yanlışlıkla ayarlar menüsünü açmamalıdır.

---

# 12. QR OKUTULDUĞUNDA EKRANI UYANDIRMA

Mümkünse QR okuyucudan veri geldiğinde ekran da otomatik uyandırılmalıdır.

Akış:

1. Ekran uyuyor.
2. Kullanıcı QR kodu GM60'a gösteriyor.
3. GM60 veri gönderiyor.
4. ESP32 QR verisini alıyor.
5. Ekran otomatik uyanıyor.
6. "QR Kod Okunuyor..." gösteriliyor.
7. QR doğrulaması yapılıyor.
8. Sonuç gösteriliyor.
9. İşlem bitince ana ekrana dönülüyor.
10. Hareketsizlik süresi sonunda ekran tekrar uyuyor.

QR okuyucunun mevcut UART çalışma mantığını değiştirme.

---

# 13. DOKUNMATİK EKRAN

Touch sistemi doğru koordinatlarla çalışmalıdır.

Daha önce görülebilen ters yön / koordinat problemi varsa düzelt.

Kontrol edilmesi gerekenler:

- X yönü
- Y yönü
- rotation
- calibration
- ekran yönü
- dokunma alanlarının gerçek koordinatları

Özellikle:

- Geri
- Ayarlar
- Kapıyı Aç
- Numara tuşları

gibi butonların doğru çalıştığını fiziksel olarak test et.

---

# 14. YÖNETİCİ GİRİŞİ

Dokunmatik ekranın normal kullanıcı için gereksiz yönetim menülerini açık bırakma.

Yönetici işlemleri için:

**6 haneli yönetici kodu**

kullanılmalıdır.

Örnek akış:

Ana ekran → Yönetici/Ayarlar alanı → 6 haneli kod → doğrulama → yönetici menüsü

Kod doğruysa:

**Yönetici Menüsü**

Kod yanlışsa:

**Hatalı Kod**

göster.

Gerekirse sınırlı sayıda denemeden sonra bekleme süresi uygulanabilir.

Yönetici kodunu ekrana veya kaynak koduna gereksiz şekilde açık biçimde yazma.

Mevcut güvenlik mimarisine uygun şekilde sakla.

---

# 15. YÖNETİCİ MENÜSÜ

Yönetici menüsü sade olmalıdır.

Önerilen seçenekler:

1. **Kapıyı Aç**
2. **Bağlantı Durumu**
3. **Ağ Ayarları**
4. **Cihaz Bilgileri**
5. **Geri**

Butonlar büyük ve dokunmatik kullanıma uygun olmalıdır.

---

# 16. MANUEL KAPI AÇMA

Site yöneticisi gerektiğinde QR kullanmadan dokunmatik ekran üzerinden kapıyı açabilmelidir.

Akış:

Yönetici Menüsü  
→ Kapıyı Aç  
→ Onay ekranı  
→ Kapıyı Aç

Örneğin:

**Kapı açılsın mı?**

[İptal] [Kapıyı Aç]

Onay verilirse mevcut çalışan röle/kapı açma fonksiyonu çağrılmalıdır.

Röle kontrol mantığını yeniden yazma.

Mevcut çalışan kapı açma fonksiyonunu kullan.

---

# 17. BAĞLANTI DURUMU

Yönetici bağlantı durumunu ekrandan görebilmelidir.

Gerçek sistem verilerini kullan.

Sahte veya statik durum göstermeyin.

Gösterilebilecek bilgiler:

- Wi-Fi: Bağlı / Bağlı değil
- İnternet: Bağlı / Bağlı değil
- API: Bağlı / Erişilebilir / Hata
- MQTT: Bağlı / Bağlı değil
- RSSI
- IP adresi
- bağlantı durumu
- gerekiyorsa MQTT sunucu durumu

Örneğin:

**Wi-Fi**  
Bağlı

**IP**  
192.168.x.x

**Sinyal**  
-62 dBm

**MQTT**  
Bağlı

**API**  
Bağlı

---

# 18. AĞ AYARLARI

Cihaz internete/ağa bağlı değilse yönetici dokunmatik ekran üzerinden Wi-Fi ayarlarını değiştirebilmelidir.

Akış:

Yönetici Menüsü  
→ Ağ Ayarları  
→ Wi-Fi ağlarını tara  
→ SSID seç  
→ Şifre gir  
→ Bağlan  
→ Sonucu göster

Örnek:

**Wi-Fi Ağı Seç**

- AG
- AG_5G
- SiteWiFi
- vb.

Şifre ekranında dokunmatik klavye kullanılabilir.

Klavye 240x320 çözünürlüğüne uygun hazırlanmalıdır.

Mevcut Bluetooth provisioning sistemi varsa gereksiz yere kaldırma veya değiştirme.

---

# 19. BAĞLANTI YENİLEME

Wi-Fi ayarı değiştirildiğinde:

- mevcut bağlantıyı kontrollü şekilde sonlandır
- yeni Wi-Fi bilgileriyle bağlantı kur
- sonucu kontrol et
- bağlantı başarılıysa durumu göster
- başarısızsa anlaşılır hata göster

Sistem bağlantı kurmaya çalışırken ekranın tamamını `delay()` ile kilitleme.

---

# 20. CİHAZ BİLGİLERİ

Yönetici cihaz bilgilerini görebilmelidir.

Örneğin:

- Cihaz ID
- MAC adresi
- Firmware sürümü
- IP adresi
- Wi-Fi SSID
- RSSI
- MQTT durumu
- API durumu
- çalışma süresi / uptime

Ekrana sığmayan bilgileri sayfalayabilir veya kaydırılabilir yapı kullanabilirsin.

240x320 sınırını kesinlikle aşma.

---

# 21. UI DURUM MAKİNESİ

Ekran sistemi mümkün olduğunca merkezi bir state machine ile yönetilmelidir.

Örneğin:

```cpp
enum ScreenState {
    SCREEN_IDLE,
    SCREEN_QR_SCANNING,
    SCREEN_VALIDATING,
    SCREEN_DOOR_OPENED,
    SCREEN_INVALID_QR,
    SCREEN_ADMIN_LOGIN,
    SCREEN_ADMIN_MENU,
    SCREEN_MANUAL_OPEN,
    SCREEN_CONNECTION_STATUS,
    SCREEN_NETWORK_SETTINGS,
    SCREEN_DEVICE_INFO
};
```

Mevcut projeye uygun daha iyi bir mimari varsa onu kullanabilirsin.

Ama ekran durumlarını birbirinden kopuk `if` bloklarıyla karmaşıklaştırma.

---

# 22. NON-BLOCKING PROGRAMLAMA

Özellikle:

- ekran uyku zamanlayıcısı
- bağlantı kontrolleri
- QR sonuç mesajları
- ekran geçişleri
- yönetici menüsü

non-blocking çalışmalıdır.

Mümkün olduğunca:

```cpp
millis()
```

tabanlı zamanlama kullan.

Uzun:

```cpp
delay(5000);
```

gibi sistemin tamamını durduran işlemler kullanma.

---

# 23. MODÜLER MİMARİ

Yeni ekran kodunu mevcut çalışan sistemden mümkün olduğunca ayır.

Örneğin uygun görülürse:

```text
display_manager
touch_manager
screen_manager
admin_menu
screen_sleep
```

gibi modüller oluşturulabilir.

Ancak sırf modüler olmak için çalışan projeyi gereksiz yere onlarca dosyaya bölme.

Mevcut proje yapısını analiz ettikten sonra en uygun mimariyi seç.

Ana amaç:

**Bakımı kolay + güvenilir + geri dönüşü kolay + mevcut sistemi bozmayan yapı**

---

# 24. EKRAN SLEEP MANAGER

Ekran uyku mekanizması mümkünse ayrı bir mantık halinde tutulmalıdır.

Örneğin:

```cpp
void resetScreenSleepTimer();
void updateScreenSleep();
void wakeScreen();
void sleepScreen();
```

Benzeri bir yapı kullanılabilir.

Bu fonksiyonlar:

- QR geldiğinde
- touch geldiğinde
- yönetici menüsünde işlem yapıldığında
- ekran mesajı gösterildiğinde

uygun şekilde çağrılmalıdır.

---

# 25. EKRAN MESAJLARININ SÜRELERİ

Başarı/hata ekranları gereksiz uzun tutulmamalıdır.

Örneğin:

- Kapı Açıldı → kısa süre
- Geçersiz QR → kısa süre
- Hatalı yönetici kodu → kısa süre

Sonrasında ana bekleme ekranına dön.

Bu süreleri merkezi sabitler halinde tut.

---

# 26. GÖRSEL TASARIM

240x320 için:

- büyük başlık
- büyük durum mesajı
- geniş butonlar
- yeterli padding
- yuvarlatılmış buton görünümü mümkünse kullanılabilir
- sade ikonlar
- net başarı/hata görseli
- tutarlı tipografi

kullan.

Her ekranda aynı tasarım dili devam etsin.

---

# 27. RENK SİSTEMİ

Renkleri rastgele kullanma.

Basit bir renk sistemi oluştur.

Örneğin:

- ana marka rengi
- arka plan
- normal metin
- ikincil metin
- başarı
- hata
- uyarı
- buton

renkleri merkezi tanımlansın.

Renkler yüksek kontrast sağlamalı.

---

# 28. AYARLAR MENÜSÜNÜN GÜVENLİĞİ

Normal kullanıcı:

- Wi-Fi ayarlarına
- cihaz bilgilerine
- manuel kapı açma
- yönetici ayarlarına

doğrudan erişememelidir.

Bu alanlar yönetici doğrulamasından sonra açılmalıdır.

Ana QR kullanımını gereksiz şekilde karmaşıklaştırma.

---

# 29. EKRAN UYKU VE YÖNETİCİ MODU

Yönetici menüsünde kullanıcı aktif olarak işlem yapıyorsa ekran uyku süresi her dokunmada yeniden başlatılmalıdır.

Örneğin:

Yönetici menüsünde kullanıcı 10 saniye sonra başka bir butona bastıysa:

**Uyku sayacı tekrar başlamalıdır.**

Yönetici işlem yapmayı bıraktığında timeout sonunda ekran uykuya geçebilir.

---

# 30. HATA YÖNETİMİ

Her işlem için kullanıcıya anlaşılır durum göster.

Örneğin:

Wi-Fi bağlanamadı:

**Wi-Fi bağlantısı kurulamadı**

API erişilemiyor:

**Sunucuya ulaşılamıyor**

MQTT bağlantısı yok:

**MQTT bağlantısı yok**

QR geçersiz:

**Geçersiz / Yetkisiz QR Kod**

Hataları teknik loglarda ayrıntılı tut, ekranda kullanıcıya gereksiz teknik hata metinleri gösterme.

---

# 31. LOG SİSTEMİ

Yeni sistem için debug logları gerekiyorsa kontrollü ekle.

Örneğin:

```text
[DISPLAY]
[TOUCH]
[QR]
[ADMIN]
[NETWORK]
```

gibi anlaşılır log etiketleri kullanılabilir.

Production modunda gereksiz seri loglarını azaltabilecek bir yapı tercih et.

---

# 32. PERFORMANS

Ekran çizimleri sürekli gereksiz yere tekrar yapılmamalıdır.

Örneğin ekran aynı state'teyse her `loop()` içinde tüm ekranı baştan çizme.

State değiştiğinde veya gerekli veri değiştiğinde ekranı güncelle.

Bu:

- işlemci yükünü
- SPI trafiğini
- flicker ihtimalini

azaltacaktır.

---

# 33. TOUCH PERFORMANSI

Touch okuma sistemi:

- debounce
- yanlışlıkla çift tıklama
- ekran uyandırma
- buton tıklama

konularını düzgün yönetmelidir.

Ekran uykudan uyandığında ilk dokunmanın buton tıklaması olarak işlenmesini engelle.

---

# 34. TEST STRATEJİSİ

Geliştirme aşama aşama yapılmalıdır.

Bir aşama tamamlanmadan diğerine geçme.

Her aşamada:

1. Kodu derle
2. ESP32'ye yükle
3. Çalıştır
4. İlgili özelliği fiziksel olarak test et
5. Hata varsa düzelt
6. Mevcut özelliklerin bozulmadığını kontrol et
7. Sonra sonraki aşamaya geç

---

# 35. GELİŞTİRME AŞAMALARI

## A1 – Proje Analizi

Mevcut mimariyi ve kritik çalışan kodları analiz et.

Kod değiştirme.

## A2 – Ekran Altyapısı

ST7789 ekranı düzgün şekilde başlat.

240x320 yönünü ve rotation'ı doğrula.

## A3 – Görsel Tasarım

Ana ekranın profesyonel tasarımını oluştur.

## A4 – Ana QR Ekranı

"QR Kodunuzu Okutunuz"

## A5 – QR Durumları

- Okunuyor
- Doğrulanıyor
- Kapı Açıldı
- Geçersiz QR

durumlarını ekle.

## A6 – Touch

Touch koordinatlarını düzelt ve test et.

## A7 – Ekran Uyku

30 saniye işlem yoksa backlight kapansın.

Touch ile uyansın.

QR geldiğinde mümkünse otomatik uyansın.

## A8 – Yönetici Girişi

6 haneli kod ekranını oluştur.

## A9 – Yönetici Menüsü

- Kapıyı Aç
- Bağlantı Durumu
- Ağ Ayarları
- Cihaz Bilgileri
- Geri

## A10 – Manuel Kapı Açma

Mevcut röle fonksiyonunu kullan.

## A11 – Bağlantı Durumu

Gerçek Wi-Fi/API/MQTT verilerini göster.

## A12 – Wi-Fi Ayarları

SSID seçimi ve şifre girişi.

## A13 – Cihaz Bilgileri

Cihaz ID, MAC, IP, firmware, RSSI vb.

## A14 – UI/UX Son Rötuş

- yazı boyutları
- boşluklar
- butonlar
- ikonlar
- geçişler
- okunabilirlik
- ekran taşmaları
- touch hassasiyeti

kontrol edilsin.

---

# 36. HER AŞAMA SONRASI RAPOR

Her aşama tamamlandığında şu formatta kısa rapor ver:

```text
AŞAMA:
Yapılanlar:
Değiştirilen dosyalar:
Eklenen dosyalar:
Test:
Sonuç:
Mevcut sistemlerde regresyon:
Sonraki aşama:
```

Bir hata varsa sonraki aşamaya geçme.

---

# 37. REGRESYON TESTİ

Her önemli değişiklikten sonra aşağıdakileri kontrol et:

### QR

- Geçerli QR
- Geçersiz QR
- Yetkisiz QR

### Kapı

- Röle tetikleniyor mu?
- Doğru süre çalışıyor mu?

### Wi-Fi

- Bağlanıyor mu?
- Yeniden bağlanıyor mu?

### MQTT

- Bağlanıyor mu?
- LWT çalışmaya devam ediyor mu?

### API

- API haberleşmesi çalışıyor mu?

### UART

- GM60 veri gönderiyor mu?

### Touch

- doğru koordinat
- doğru buton
- doğru yön

### Ekran

- uyku
- uyanma
- QR ile uyanma
- ekran taşması

---

# 38. UZUN SÜRELİ TEST

Son aşamada cihazı uzun süre çalıştır.

Kontrol et:

- memory leak
- ekran flicker
- touch kilitlenmesi
- Wi-Fi kopması
- MQTT kopması
- API kopması
- QR okuyucunun çalışması
- ekranın uyuyup uyanması
- rölenin çalışması

Cihazın 7/24 çalışacak bir ürün olduğu varsayımıyla hareket et.

---

# 39. ÖNEMLİ GELİŞTİRME KURALLARI

Aşağıdaki kurallara kesinlikle uy:

### Kural 1
Çalışan kodu gereksiz yere değiştirme.

### Kural 2
Mevcut haberleşme altyapısını yeniden yazma.

### Kural 3
Her özelliği modüler geliştir.

### Kural 4
Bir aşamayı test etmeden diğerine geçme.

### Kural 5
`delay()` ile sistemi bloke etme.

### Kural 6
Ekran çözünürlüğünü aşma.

### Kural 7
Touch koordinatlarını fiziksel cihaz üzerinde test et.

### Kural 8
Ekran uykusu cihazın diğer fonksiyonlarını durdurmamalı.

### Kural 9
İlk touch yalnızca ekranı uyandırıyorsa buton işlemi yapmamalı.

### Kural 10
QR okuyucu veri gönderdiğinde mümkünse ekran otomatik uyanmalı.

### Kural 11
Gerçek bağlantı durumlarını göster, sahte durum oluşturma.

### Kural 12
Kullanıcıya teknik hata yerine anlaşılır mesaj göster.

### Kural 13
Kod okunabilir ve sürdürülebilir olsun.

### Kural 14
Mevcut çalışan fonksiyonların yerine yeni kopya fonksiyonlar yazma; mümkünse mevcut fonksiyonları çağır.

### Kural 15
Bir değişiklik mevcut çalışan bir özelliği etkiliyorsa önce bunu raporla ve güvenli çözüm üret.

---

# 40. SON KABUL KRİTERLERİ

Proje tamamlandığında aşağıdaki akışların tamamı sorunsuz çalışmalıdır:

### Normal kullanıcı

```text
Ekran uyanık
↓
QR Kodunuzu Okutunuz
↓
QR okutulur
↓
QR doğrulanır
↓
Yetkili
↓
Kapı Açıldı
↓
Ana ekran
↓
30 saniye işlem yok
↓
Ekran backlight kapanır
```

### Geçersiz QR

```text
QR okutulur
↓
Doğrulama
↓
Geçersiz / Yetkisiz QR Kod
↓
Ana ekran
```

### Ekran uykusu

```text
30 saniye işlem yok
↓
Backlight OFF
↓
ESP32 çalışmaya devam eder
↓
Touch
↓
Backlight ON
↓
Ana ekran
```

### QR ile uyanma

```text
Ekran uyuyor
↓
QR okutulur
↓
GM60 veri gönderir
↓
Ekran uyanır
↓
QR doğrulama
↓
Sonuç
```

### Yönetici

```text
Ana ekran
↓
Ayarlar / Yönetici girişi
↓
6 haneli kod
↓
Yönetici Menüsü
↓
Kapıyı Aç
Bağlantı Durumu
Ağ Ayarları
Cihaz Bilgileri
Geri
```

---

# 41. ANTIGRAVITY İÇİN SON TALİMAT

Bu dosyayı proje geliştirme talimatı olarak kabul et.

**İlk iş olarak A1 – Proje Analizi aşamasını gerçekleştir.**

Hemen büyük çaplı kod değişikliğine başlama.

Önce:

1. Projeyi tara.
2. Mevcut mimariyi çıkar.
3. Çalışan kritik fonksiyonları belirle.
4. Ekran ve touch bağlantılarını belirle.
5. GM60 UART yapısını belirle.
6. QR doğrulama ve röle fonksiyonlarını belirle.
7. Wi-Fi / Bluetooth / MQTT / API yapılarını belirle.
8. Ekran uyku sisteminin mevcut mimariye nasıl ekleneceğini belirle.
9. Değiştirilecek dosyaları listele.
10. Riskleri belirt.

Sonra yalnızca **A1 sonucunu raporla**.

A1 onaylandıktan sonra aşama aşama ilerle.

Her aşamada:

**Geliştir → derle → yükle → test et → raporla → sonraki aşamaya geç.**

Ana hedef:

> **AHBU = QR ile güvenli kapı açma + dokunmatik yerel yönetim/servis ekranı**

Sistemin güvenilir, profesyonel, sade, hızlı ve 7/24 çalışmaya uygun olması temel önceliktir.
