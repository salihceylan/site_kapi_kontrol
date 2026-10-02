# 📋 SAHA KONTROL LİSTESİ (FIELD VERIFICATION CHECKLIST)

Bu kontrol listesi; son bir hafta içerisinde geliştirilen, düzeltilen ve sahada/uygulamada test edilmeye hazır tüm özellikleri adım adım içermektedir.  
Sahada veya uygulamada test ettikçe ilgili kutucukları `- [x]` olarak işaretleyebilirsiniz.

> ℹ️ **Not:** Talep ettiğiniz her yeni özellik tamamlandığında bu listeye otomatik olarak yeni bir kontrol adımı olarak eklenecektir.

---

## 1. 📡 Cihaz Uptime (Çevrimiçi Süresi) ve Wi-Fi Kopma / Offline Logları
*Son geliştirilen telemetri ve akordeon log özellikleri.*

- [ ] **1.1. Cihaz Kartında Canlı Uptime Gösterimi:**
  - **Nasıl Test Edilir:** Süper kullanıcı olarak "Kayıtlı Cihazlar" sayfasına girin. Çevrimiçi olan bir cihazın kartını açın.
  - **Beklenen Sonuç:** Yeşil renkli canlı rozet içerisinde `Kesintisiz Çevrimiçi (Uptime): X gün Y saat Z dakika` ve bağlantı başlangıç tarih/saati doğru görüntülenmeli.
- [ ] **1.2. Çevrimdışı (Offline) Cihaz Durum Bildirimi:**
  - **Nasıl Test Edilir:** Cihazın Wi-Fi bağlantısı veya elektriği kesildiğinde kartı açın.
  - **Beklenen Sonuç:** Kırmızı renkli rozette `Cihaz Şu An Çevrimdışı` ve son kopma saati gösterilmeli.
- [ ] **1.3. Aşağıya Açılır (Akordeon) Kopma Log Paneli:**
  - **Nasıl Test Edilir:** Cihaz kartı içindeki "Bağlantı & Kopma Geçmişi (Logları Gör)" butonuna dokunun.
  - **Beklenen Sonuç:** Panel kapı açma logları gibi aşağı doğru akıcı şekilde açılmalı, geçmiş kopma kayıtlarını listelemeli.
- [ ] **1.4. Kopma Log Detaylarının Doğruluğu:**
  - **Nasıl Test Edilir:** Listelenen kopma loglarını inceleyin.
  - **Beklenen Sonuç:** Her kayıtta kopma anı, cihazın koptuğu ana kadar ne kadar süre kesintisiz online kaldığı (örn: `4 saat 20 dk`), kopma anındaki son Wi-Fi sinyal gücü (% ve dBm), IP adresi ve kopma nedeni (`Wi-Fi/MQTT Bağlantısı Kesildi`) eksiksiz görünmeli.
- [ ] **1.5. Log Sayfalama ve Yenileme:**
  - **Nasıl Test Edilir:** Akordeon panelindeki yenile (refresh) ikonuna ve sayfa değiştirme butonlarına (`< >`) basın.
  - **Beklenen Sonuç:** Loglar bekleme animasyonuyla anlık güncellenmeli ve sayfalar arası geçiş pürüzsüz çalışmalı.

---

## 2. 🔌 Kapılarda Çoklu Cihaz / Donanım Modeli Görünürlüğü
*Farklı donanımların (ESP32-C3, ESP32-WROOM vb.) kapı bazında net ayırt edilebilmesi.*

- [ ] **2.1. Kapı Kartlarında Donanım Rozeti:**
  - **Nasıl Test Edilir:** "Siteler" sayfasında herhangi bir siteyi seçip kapı listesine bakın.
  - **Beklenen Sonuç:** Her kapının sağ üstünde cihaza ait donanım etiketi (C3 için mavi `ESP32-C3`, WROOM için mor `ESP32-WROOM`) ve altında model adı (`ESP32-C3 Süper Mini` veya `ESP32-WROOM-32E Röle Kartı`) görünmeli.
- [ ] **2.2. Kapı Kartında Canlı Telemetri ve Cihaz UID:**
  - **Nasıl Test Edilir:** Kapı kartını inceleyin.
  - **Beklenen Sonuç:** Kapıya atanan cihazın UID'si, yeşil/kırmızı online noktası, firmware sürümü ve yerel IP adresi kart üzerinde görünmeli. Cihaz atanmamış kapıda sarı renkle "Cihaz atanmamış" yazmalı.
- [ ] **2.3. Yönetici Telemetri Kartında (AdminDoorStatusCard) Kapı Seçimi:**
  - **Nasıl Test Edilir:** Ana ekrandaki Kapı Kontrolü & Telemetri kartındaki kapı dropdown açılır menüsüne tıklayın.
  - **Beklenen Sonuç:** Listede her kapının yanında donanım rozeti ve UID'si bulunmalı (örn: `Ana Kapı • ESP32-C3 (A1B2C3)`).
- [ ] **2.4. Telemetri Detay Panelinde Donanım Satırları:**
  - **Nasıl Test Edilir:** Kapı kontrol kartındaki durum çubuğuna ("Detaylar") tıklayarak paneli genişletin.
  - **Beklenen Sonuç:** `Donanım Modeli` ve `Donanım Hedefi` satırları net şekilde listelenmeli.
- [ ] **2.5. Cihaz Atama Ekranlarında Donanım Modeli:**
  - **Nasıl Test Edilir:** Kapıya cihaz atama veya cihazı kapıya atama diyaloglarını açın.
  - **Beklenen Sonuç:** Seçim listelerinde kapıların donanım modeli ve mevcut cihaz durumu görünmeli.

---

## 3. 🛡️ Site Erişim Politikaları (QR Sadece, Uygulama Sadece, Hibrit)
*Site yöneticileri ve sakinleri için kapı açma yöntemlerinin sınırlandırılması/yetkilendirilmesi.*

- [ ] **3.1. Süper Kullanıcı Güvenlik Politikası Belirleme:**
  - **Nasıl Test Edilir:** Siteler listesinde bir sitenin yanındaki "Erişim Politikası" butonuna dokunun.
  - **Beklenen Sonuç:** Giriş yöntemleri (Sadece QR, Sadece Uygulama, Hibrit), Dinamik QR Rotasyon Süresi ve Geofence (GPS Konum Zorunluluğu) ayarlarını içeren diyalog açılmalı ve ayarlar kaydedilebilmeli.
- [ ] **3.2. Sadece QR Kod Seçili Site Testi:**
  - **Nasıl Test Edilir:** Bir siteyi "Sadece QR Kod" moduna alın ve o sitenin daire sakini veya yöneticisi ile giriş yapın.
  - **Beklenen Sonuç:** Uygulamada doğrudan dinamik QR kod açılmalı; uzaktan butona basarak kapı açma butonu devre dışı bırakılmalı. Buton zorlansa dahi backend 403 engeli koymalı.
- [ ] **3.3. Sadece Mobil Uygulama Seçili Site Testi:**
  - **Nasıl Test Edilir:** Siteyi "Sadece Uygulama" moduna alın.
  - **Beklenen Sonuç:** QR sekmesi veya menüsü gizlenmeli / pasife alınmalı; kapı yalnızca uygulama içi butonla açılabilmeli.
- [ ] **3.4. Hibrit Mod Testi:**
  - **Nasıl Test Edilir:** Siteyi "Hibrit (Uygulama + QR)" moduna alın.
  - **Beklenen Sonuç:** Kullanıcı hem uygulama butonunu hem de dinamik QR kodu serbestçe kullanabilmeli.
- [ ] **3.5. Dinamik QR Rotasyonu (TOTP):**
  - **Nasıl Test Edilir:** QR kod ekranını açıp bekleyin.
  - **Beklenen Sonuç:** Belirlenen süre (örn: 30 saniye) dolduğunda sayaç sıfırlanmalı ve yeni dinamik QR kod ekranda otomatik yenilenmeli.
- [ ] **3.6. Coğrafi Konum (Geofence) Kısıtlaması:**
  - **Nasıl Test Edilir:** Siteye koordinat ve yarıçap (örn: 100 metre; varsayılan yarıçap 100 m) tanımlayın.
  - **Beklenen Sonuç:** Site sınırları dışından kapı açılmaya çalışıldığında kullanıcıya konum uyarısı verilmeli ve kapı açılmamalı.

---

## 4. 🎨 Karanlık Mod (Dark Theme) & Arayüz Kontrast İyileştirmeleri
*Lüks cam morfizması (glassmorphism) ve okuma kolaylığı.*

- [ ] **4.1. ListTile Ink Splash / Framework Assertion Kontrolü:**
  - **Nasıl Test Edilir:** Yan menüyü (çekmeceyi) açıp kapatın, menü öğelerine tıklayın.
  - **Beklenen Sonuç:** Flutter konsolunda veya arayüzde hiçbir assertion veya ink splash hatası oluşmamalı.
- [ ] **4.2. Karanlık Modda Metin Kontrastı:**
  - **Nasıl Test Edilir:** Cihazı veya uygulamayı karanlık moda alın. Siteler, Kayıtlı Cihazlar, Kullanıcılar ve Kapı Kontrol sayfalarını gezin.
  - **Beklenen Sonuç:** Başlıklar (`Site Listesi`, `Daireler`, `Kapılar`) ve ikincil metinler (`AppColors.textMutedLight` Slate-300) yüksek kontrastlı ve rahat okunur olmalı; koyu arka planda kaybolmamalı.
- [ ] **4.3. Diyalog ve Açılır Pencereler:**
  - **Nasıl Test Edilir:** Kullanıcı düzenleme, site ekleme ve güvenlik politikası diyaloglarını açın.
  - **Beklenen Sonuç:** Form alanları, etiketler ve butonlar karanlık temada net ve dengeli görünmeli.
- [ ] **4.4. Cam Kart Başlıkları (Glass Card Headers) ve Sayfa Başlıkları Kontrastı:**
  - **Nasıl Test Edilir:** Koyu temada "Siteler", "Site Onay Talepleri", "Kayıtlı Cihazlar", "Cihaz Ekle", "Profil", "Abonelik Talepleri", "Bluetooth & Wi-Fi" ve "İnternet Bağlantısı Yok" ekranlarını açın.
  - **Beklenen Sonuç:** Kartların en üstündeki tüm ana başlıklar koyu modda koyu arkaplan üzerinde kaybolmadan yüksek kontrastlı açık beyaz (`#F8FAFC`) ile net olarak okunabilmeli; açık modda ise kurumsal koyu lacivert (`#0F172A`) görünümünü korumalıdır.

---

## 5. 📱 Android Ana Ekran Widget'ı (Home Screen Widget)
*Telefon ana ekranından uygulama açmadan kapı kontrolü.*

- [ ] **5.1. Ana Ekran Widget'ının Eklenmesi:**
  - **Nasıl Test Edilir:** Android ana ekranına basılı tutup "Site Kapı Kontrol" widget'ını ana ekrana ekleyin.
  - **Beklenen Sonuç:** Dijital saat, güncel tarih ve kapı kontrol kartı kusursuz yüklenmeli; küçük ekranlarda bile taşma (overflow) olmamalı.
- [ ] **5.2. Çoklu Kapı Gezinmesi:**
  - **Nasıl Test Edilir:** Birden fazla kapı tanımlı bir sitede widget üzerindeki sağ/sol ok butonlarına basın.
  - **Beklenen Sonuç:** Kapı adı ve durumu sıralı olarak değişmeli; ilk ve son kapılarda ok butonları aktif/pasif durumu korumalı.
- [ ] **5.3. Widget Üzerinden Kapı Açma:**
  - **Nasıl Test Edilir:** Widget üzerindeki "Kapıyı Aç" butonuna basın.
  - **Beklenen Sonuç:** Cihaz online ise kapı tetiklenmeli, titreşim bildirimi verilmeli ve durum anında güncellenmeli.

---

## 6. 📊 Kapı Geçiş & Erişim Logları Akordeonu
*Admin panelinde kapı kullanım geçmişi.*

- [x] **6.1. Sayfalanmış Kapı Logları:**
  - **Nasıl Test Edilir:** Kapı kontrol ekranında "Geçiş Logları" akordeonunu açın.
  - **Beklenen Sonuç:** Kapıdan kimin, ne zaman, hangi yöntemle (QR, Uzaktan, Bluetooth) geçtiği listelenmeli.
- [ ] **6.2. Çevrimdışı (LittleFS) Log Senkronizasyonu:**
  - **Nasıl Test Edilir:** İnternet yokken yerel ağdan kapıyı açın, internet geldiğinde logların sunucuya aktarıldığını doğrulayın.
  - **Beklenen Sonuç:** `door_access_logs` tablosunda ve log ekranında `local_wifi` / `mqtt_sync` kayıtları görünmeli.
- [ ] **6.3. GM60 QR ve Ekran Butonu Geçiş Logları:**
  - **Nasıl Test Edilir:** GM60 okuyucudan QR okutarak veya ekran üzerindeki kapı açma butonuyla kapıyı açın. Yönetim panelindeki "Geçiş Logları" akordeonunu açıp yenileyin.
  - **Beklenen Sonuç:** Log listesinde tetikleyici olarak `GM60 QR Okuyucu` veya `Ekran Butonu` olarak anında görünmeli, LittleFS veya MQTT üzerinden sunucuya iletilmelidir.

---

## 7. 🚀 Modüler Backend & İki Farklı Donanım Hedefi
*Mimari güvenlik ve geleceğe hazırlık.*

- [ ] **7.1. Modüler Sunucu Kararlılığı:**
  - **Nasıl Test Edilir:** Backend testlerini (`npm test`) ve API uç noktalarını çalıştırın.
  - **Beklenen Sonuç:** 20/20 test hatasız geçmeli, tüm servis katmanları birbirinden izole çalışmalı.
- [ ] **7.2. ESP32-C3 ve ESP32-WROOM OTA İzolasyonu:**
  - **Nasıl Test Edilir:** `/firmware/esp32-c3/manifest.json` ve `/firmware/esp32-wroom/manifest.json` dosyalarını tarayıcıda açın.
  - **Beklenen Sonuç:** Her donanım hedefi yalnızca kendi derleme dosyasını ve sürümünü sunmalı; cihazların birbirinin yazılımını indirmesi engellenmiş olmalı.
- [x] **7.3. ESP32-WROOM-32E Kartı Fiziki Doğrulaması:**
  - **Nasıl Test Edilir:** CH340 üzerinden USB ile bağlanıp `esp32_relay_wroom` ortamından derlenip yüklendi.
  - **Beklenen Sonuç:** Cihaz başarıyla boot etti (UID: `00861A0D5020`, Hardware: `esp32-wroom`, Sürüm: `1.0.0`), GPIO 23 rölesi tetiklendi ve LittleFS loglama tamponu doğrulandı.

---

*Eklenmesini istediğiniz veya test aşamasında özel olarak kontrol etmek istediğiniz bir madde olursa lütfen bildirin.*

---

## 8. GM60 ve Display UART Entegrasyonu (ESP32-WROOM)

- [ ] **8.1. GM60 Pin 16/17 UART2 Okuma:**
  - **Nasıl Test Edilir:** GM60 TX -> WROOM GPIO16 (RX), GM60 RX -> WROOM GPIO17 (TX) bağlayın. Barkod/QR okutun.
- [ ] **8.1. GM60 Pin 25/26 UART2 Okuma:**
  - **Nasıl Test Edilir:** GM60 Sarı kablosunu (TXD) -> WROOM GPIO25 (RX2), GM60 Yeşil kablosunu (RXD) -> WROOM GPIO26 (TX2), Kırmızı kablosunu -> 5V/VIN, Siyah kablosunu -> GND bağlayın. Barkod/QR okutun.
  - **Beklenen Sonuç:** Seri monitörde `GM60 QR Okundu: <data>` görünmeli, geçerli QR ise röle tetiklenmeli ve ekrana `QR_OK|<data>` ile `DOOR_OPENED` gönderilmeli.
- [ ] **8.2. Display UART Başlatma:**
  - **Nasıl Test Edilir:** ESP32-WROOM'u açın, seri monitörü (`115200 baud`) izleyin.
  - **Beklenen Sonuç:** Boot sırasında `[DISPLAY] UART1 initialized (RX=32, TX=33)` ve `[DISPLAY] TX: READY` görünmeli.
- [ ] **8.3. Ekrandan Buton Komutu ile Röle Tetikleme (BTN_OPEN):**
  - **Nasıl Test Edilir:** Ekran kartından UART üzerinden `BTN_OPEN\n` gönderin (veya ekrandaki "KAPIYI AÇ" butonuna basın).
  - **Beklenen Sonuç:** WROOM seri monitörde `[DISPLAY] Kapi acma butonu alindi -> Role tetikleniyor` görünmeli ve röle çekmeli; röle süresi bitince ekrana `DOOR_CLOSED` bildirilmeli.
- [ ] **8.4. Wi-Fi ve MQTT Durum Senkronizasyonu:**
  - **Nasıl Test Edilir:** WROOM Wi-Fi'a bağlandığında veya koptuğunda.
  - **Beklenen Sonuç:** WROOM tarafından ekrana otomatik `WIFI_CONNECTED` / `WIFI_DISCONNECTED` ve `MQTT_CONNECTED` satırları aktarılmalı.
- [ ] **8.5. İlk Açılış Donanım Self-Testi (Röle Çek-Bırak + GM60 Flaş/Bip):**
  - **Nasıl Test Edilir:** Cihazı yeniden başlatın (veya USB'yi takın).
  - **Beklenen Sonuç:** Açılışta 120 ms süreli röle mekanik çek-bırak sesi duyulmalı, ardından GM60 kamera ışıkları 300 ms yanıp sönmeli, buzzer bip sesi vermelidir. Seri ekranda `[TEST 1/2] Role mekanik test ediliyor... [OK]`, `[TEST 2/2] GM60 Kamera test ediliyor... [OK / YANIT ALINDI]`, `[SELF-TEST] Donanim hazir.` yazmalıdır.
- [ ] **8.6. Seri Monitör ve AHBU Test Arayüzünde Kamera Bağlantı Durumu:**
  - **Nasıl Test Edilir:** Cihazın `--- ESP32 SISTEM BILGISI ---` çıktısını veya AHBU Cihaz Deneme aracındaki "Kamera / QR Okuyucu" alanını kontrol edin.
  - **Beklenen Sonuç:** Kamera bağlıysa `Kamera / QR Okuyucu: Bagli (Hazir)`, bağlı değilse veya yanıt yoksa `Bagli Degil` olarak görünmeli ve anlık güncellenmelidir.
- [ ] **8.7. Manuel Kamera Testi (Seri 'k' Komutu ve Arayüz Butonu):**
  - **Nasıl Test Edilir:** AHBU Test aracındaki `Kamera Test (Isik/Bip)` butonuna basın veya seri terminale `k` gönderin.
  - **Beklenen Sonuç:** GM60 flaş ışığı yanıp söner, bip sesi çalar ve seri logda `[GM60 TEST] Kamera Durumu: Bagli (Hazir)` teyit edilir.

---

## 9. Ekran Yazılımı (ESP32-C3 + ST7789 TFT)

- [ ] **9.1. Modern Ana Ekran (Home UI):**
  - **Nasıl Test Edilir:** `ekran_yazilimi` yüklü ESP32-C3 kartını açın.
  - **Beklenen Sonuç:** Üst barda Wi-Fi ve Bulut durum göstergesi (nokta ve metin), ortada büyük QR kod alanı ("Giris Icin QR Okutunuz"), altta yeşil "KAPIYI AC" butonu ve gri "AYARLAR" butonu çizilmeli.
- [ ] **9.2. "KAPI AÇILDI" Ekran Durumu:**
  - **Nasıl Test Edilir:** WROOM'dan `DOOR_OPENED\n` komutu gönderin veya ekrandaki butona basın.
  - **Beklenen Sonuç:** Ekranda büyük yeşil zemin üzerinde "KAPI ACILDI - Lutfen geciniz..." gösterilmeli; 4 saniye sonra veya `DOOR_CLOSED` gelince otomatik ana ekrana dönmeli.
- [ ] **9.3. "GİRİŞ ONAYLANDI" ve "GEÇERSİZ QR" Ekranları:**
  - **Nasıl Test Edilir:** WROOM'dan sırasıyla `QR_OK|123456\n` ve `QR_DENIED\n` komutları gönderin.
  - **Beklenen Sonuç:** Geçerli QR için yeşil "GIRIS ONAYLANDI", geçersiz için kırmızı "GECERSIZ QR - Yetkisiz veya suresi dolmus!" ekranı gelmeli ve 3 saniye sonra ana ekrana dönmeli.
- [ ] **9.4. Ayarlar Ekranı ve Geri Dönüş:**
  - **Nasıl Test Edilir:** Ekrandaki "AYARLAR" butonuna basın veya `SHOW_SETTINGS\n` gönderin.
  - **Beklenen Sonuç:** Cihaz bilgisi (ESP32-C3, ST7789, WiFi/MQTT durumu) görüntülenmeli, "GERI" butonuna basıldığında ana ekrana dönmeli ve WROOM'a `BTN_BACK` iletilmeli.
- [ ] **9.5. Non-Blocking Çalışma Doğrulaması:**
  - **Nasıl Test Edilir:** UART iletişimi sürerken butonlara basın ve seri monitörü izleyin.
  - **Beklenen Sonuç:** Hiçbir `delay()` blokajı olmadan, millis() state machine ile akıcı çalışmalı.
- [x] **9.6. CST816D Kapasitif Dokunmatik & Titreşimsiz Tetikleme (Debounce):**
  - **Nasıl Test Edilir:** Ekranda "KAPIYI AC" ve "AYARLAR" butonlarına dokunun. Parmak ekranda basılı tutulurken ve çekildiğinde seri monitörü (`COM6`) izleyin.
  - **Beklenen Sonuç:** CST816D kontrolcüsü `0x15` I2C adresinde dokunmaları anında algılamalı; basılı tutma sırasında arka arkaya buton zıplaması olmamalı, tek dokunuşta tek komut (`BTN_OPEN` / `BTN_SETTINGS`) üretilmelidir.
- [x] **9.7. ESP32-C3 Çift UART & USB Seri Monitör Test Kolaylığı:**
  - **Nasıl Test Edilir:** Bilgisayardan `COM6` seri monitörü açıp `WIFI_CONNECTED`, `DOOR_OPENED` veya `SHOW_SETTINGS` yazıp gönderin.
  - **Beklenen Sonuç:** Ekran bilgisayardan gelen komutları derhal işleyip arayüzü güncellemeli; aynı zamanda ESP32-WROOM haberleşmesi donanım pinleri (RX: GPIO 20, TX: GPIO 21) üzerinden bağımsız olarak yürütülmelidir.

---

## 10. 🏷️ AHBU Cihaz Etiketleyici & Harici CH340 / USB-TTL Desteği

- [ ] **10.1. Kilitlenmesiz Anlık UID Okuma (0.3 saniye):**
  - **Nasıl Test Edilir:** ESP32-WROOM veya ESP32-C3 cihazını bilgisayara bağlayın. AHBU Cihaz Etiketleyici uygulamasında portu seçip "Seçili cihaz UID oku" butonuna basın.
  - **Beklenen Sonuç:** Uygulama kilitlenmeden, cihazı yeniden başlatmaya zorlamadan 0.3 saniye içinde cihazın Unique ID'sini (`00861A0D5020`) ve donanım tipini okuyup ekrana yansıtmalı.
- [ ] **10.2. CH340 Uyumlu USB Firmware Yükleme (Baud Rate & Write Timeout Koruması):**
  - **Nasıl Test Edilir:** CH340 dönüştürücü ile bağlı ESP32-WROOM modülü için "Sürümü USB ile cihaza yükle" butonuna basın (harici dönüştürücülerde karttaki BOOT butonuna basılı tutup EN'e basarak indirme moduna alın).
  - **Beklenen Sonuç:** Yükleme 460800 baud hızında başlatılmalı, pySerial `Write timeout` hatası vermeden firmware yazımı %100 tamamlanmalı ve başarı mesajı görüntülenmelidir.
- [ ] **10.3. ESP32-WROOM Röle Kartı GPIO16 ve Durum LED (GPIO23) Doğrulaması:**
  - **Nasıl Test Edilir:** v3.0.5 yüklendikten sonra "AHBU Cihaz Deneme" ekranında COM7'ye bağlanın, "Role Pulse", "Role Pin HIGH" ve "Role Pin LOW" butonlarına basın.
  - **Beklenen Sonuç:** GPIO 16 üzerinden röle mekanik "tık" sesiyle tetiklenmeli; GPIO 23 üzerindeki LED ise cihaz açılışında 4 kez flaş yapıp sistem canlılık göstergesi olarak açık kalmalıdır.
- [ ] **10.4. OTA Sonrası Otomatik Wi-Fi RF Temiz Başlatma & Yeniden Bağlanma:**
  - **Nasıl Test Edilir:** Cihaza OTA üzerinden güncelleme gönderin. Güncelleme tamamlanıp cihaz kendi kendine yeniden başladığında seri logu ve ağ durumunu izleyin (cihaza fiziksel olarak dokunmayın).
  - **Beklenen Sonuç:** Cihaz fişi çekilip takılmaya gerek kalmadan, yazılımsal resetin ardından 5-10 saniye içinde Wi-Fi ağına ve MQTT sunucusuna otomatik olarak bağlanmalı ve IP almalıdır.
---

## 11. 📱 Canlı Veri Yenileme & Kayıtlı Cihazlar Atama Önceliği (Sıralama ve Tonlama)

- [ ] **11.1. Atanmamış Cihazların En Üstte ve Farklı Tonda Görünmesi:**
  - **Nasıl Test Edilir:** Süper kullanıcı veya site yöneticisi olarak "Kayıtlı Cihazlar" sayfasına girin.
  - **Beklenen Sonuç:** Kapıya henüz atanmamış cihazlar listenin en üstünde `Atama Bekleyen Cihazlar (X)` rozet başlığı altında; sıcak amber/bal rengi kart arka planı, belirgin sarı/kehribar çerçeve, `KAPI ATANMAMIŞ` rozeti ve renkli `Kapı: Atanmamış` metniyle dikkat çekecek şekilde görünmeli. Kapıya atanmış cihazlar ise onların altında `Kapıya Atanmış Cihazlar (Y)` grubu altında düzenli sıralanmalıdır.
- [ ] **11.2. İşlem Sonrası Otomatik Güncellenme (Uygulama Kapatma Zorunluluğunun Kaldırılması):**
  - **Nasıl Test Edilir:** Kayıtlı bir cihaza "Kapıya Ata" butonuna basarak kapı atayın veya cihazı düzenleyin/silin.
  - **Beklenen Sonuç:** İşlem başarılı olduğu anda uygulama kapatılıp açılmadan (restart gerekmeksizin) cihaz listesi ve kapı durumları anında otomatik güncellenmeli; atanan cihaz hemen "Kapıya Atanmış Cihazlar" arasına geçmelidir.
- [ ] **11.3. Tek Dokunuşla Yenileme (AppBar İkonu) ve Çek-Bırak (Pull-to-Refresh):**
  - **Nasıl Test Edilir:** Herhangi bir sayfadayken (Dashboard, Siteler, Kayıtlı Cihazlar, Kullanıcı Yönetimi, Talepler) üst çubuktaki (AppBar) `Yenile` butonuna dokunun veya listeyi aşağı doğru çekip bırakın.
  - **Beklenen Sonuç:** Uygulamadan çıkış yapmaya veya uygulamayı yeniden başlatmaya gerek kalmadan o ekrandaki tüm veriler anında güncellenmelidir.

---

## 12. 📷 GM60 QR Okuyucu Entegrasyonu & 🔄 Canlı OTA Durum Senkronizasyonu

- [ ] **12.1. GM60 QR Okuyucu Self-Test (Açılış ve Seri Komut):**
  - **Nasıl Test Edilir:** ESP32-WROOM cihazı açıldığında donanım self-testini izleyin veya seri monitörden `k` tuşuna basın.
  - **Beklenen Sonuç:** Kameranın hedefleme ışığı 250ms yanıp sönmeli, buzzer'dan bip sesi gelmeli ve seri monitörde `[GM60 TEST] Kamera Durumu: BAGLI (Hazir)` teyidi alınmalıdır.
- [ ] **12.2. Karekod Okuma ve Otomatik Röle Tetikleme (50ms Frame Timeout):**
  - **Nasıl Test Edilir:** Kameraya geçerli bir site kapı karekodu tutun.
  - **Beklenen Sonuç:** Kamera yeşil ışık yaktığı an seri monitörde `[GM60 RAW OKUNDU]` ve `[GM60 QR ONAYLANDI]` logları basılmalı, röle anında çekip bırakmalı (pulse) ve kapı açılmalıdır.
- [ ] **12.3. Cihaz Açılışında NVS OTA Durumu Temizliği ("İndiriliyor" Takılma Koruması):**
  - **Nasıl Test Edilir:** OTA güncellemesi sonrası veya USB flaşlama ardından cihazı yeniden başlatın.
  - **Beklenen Sonuç:** NVS'te kalan eski "guncelleme indiriliyor" durumu açılışta otomatik temizlenmeli, seri logda `OTA son durum: guncel` görünmeli ve MQTT'ye temiz "guncel" durumu iletilmelidir.
- [ ] **12.4. Mobil ve Masaüstü Uygulamada Doğru OTA Rozeti Gösterimi:**
  - **Nasıl Test Edilir:** Mobil uygulamadan veya masaüstü aracından cihaz durumunu inceleyin.
  - **Beklenen Sonuç:** Güncellenmiş ve çalışır durumdaki cihazın OTA durumu "İndiriliyor" şeklinde asılı kalmamalı; doğrudan "Güncel" rozetiyle temiz şekilde görüntülenmelidir.

---

## 13. 🔑 Aşama 1 — GM60 Kamera & WROOM Uçtan Uca Süresiz QR ile Kapı Açma

- [ ] **13.1. Mobil Uygulamada Kriptografik QR Üretimi ve Gösterimi:**
  - **Nasıl Test Edilir:** Daire sakini veya site yöneticisi olarak uygulamaya girin. QR okuyuculu kapı için "📲 Giriş QR Kodu" butonuna dokunun.
  - **Beklenen Sonuç:** Sunucudan `QR:<48-hex>` formatında tahmin edilemez ve güvenli bir token üretilip mobil ekranda temiz bir dialog içinde `QrImageView` ile gösterilmeli; arayüzde hiçbir dikey/yatay taşma ("overflow") olmamalıdır.
- [ ] **13.2. GM60 ile QR Okuma, WROOM MQTT İletimi ve Kapı Açılışı:**
  - **Nasıl Test Edilir:** Mobil ekrandaki QR kodu GM60 kamera okuyucusuna 5-15 cm mesafeden gösterin.
  - **Beklenen Sonuç:** GM60 kodu 50ms içinde okumalı; WROOM kodu `device/{uid}/qr_verify` MQTT konusuna göndermeli; sunucu tokeni doğrulayarak WROOM'a pulse komutu vermeli; WROOM rölesi çekip kapıyı açmalıdır. Log tablosuna (`door_access_logs`) `trigger_type = 'qr_scanner'` olarak kullanıcı adıyla yazılmalı (token içeriği asla loglanmamalıdır).
- [ ] **13.3. Başka Kapıya Ait veya Geçersiz QR Kodunun Reddedilmesi:**
  - **Nasıl Test Edilir:** Farklı bir kapı için üretilmiş bir QR kodunu veya rastgele bir metni GM60'a okutun.
  - **Beklenen Sonuç:** Sunucu `DOOR_MISMATCH` veya `INVALID_TOKEN` tespit etmeli, pulse göndermemeli; WROOM'a `qr_result: allowed=false` dönmeli; röle tetiklenmemeli ve kapı kesinlikle açılmamalıdır.
- [ ] **13.4. İnternet / MQTT Yokken Dinamik QR'ın Güvenli Kapalı Kalması (Fail-Secure):**
  - **Nasıl Test Edilir:** WROOM'un internet/MQTT bağlantısını kesin ve QR kodu okutun.
  - **Beklenen Sonuç:** Cihaz offline durumdayken dinamik QR tokenleri ile kapıyı açmamalı, ekranda/seri logda `MQTT bağlantısı yok` uyarısı vererek röleyi tetiklememelidir.
- [ ] **13.5. Sahadaki Eski ESP32-C3 Cihazlarının İzolasyonu (Regresyon Güvencesi):**
  - **Nasıl Test Edilir:** ESP32-C3 firmware derlemesini kontrol edin ve C3 bağlı kapılarda test yapın.
  - **Beklenen Sonuç:** ESP32-C3 cihazlarının `qr_reader_enabled` özelliği varsayılan kapalı kalmalı; C3'e bağlı kapılarda QR kodu butonu çıkmamalı; C3'ün normal uygulama açışı, BLE ve Wi-Fi fonksiyonları kesintisiz çalışmalıdır.
- [ ] **13.6. Kameranın QR'ı Tutulurken Peş Peşe Çoklu Tetikleme Yapmasını Önleme (Debounce & Token Cooldown):**
  - **Nasıl Test Edilir:** Telefon ekranında açık olan karekodu kameraya yaklaştırıp çekmeden 5-10 saniye boyunca kameranın önünde sabit tutun.
  - **Beklenen Sonuç:** Kamera kodu okuyup ilk geçerli tetiklemede kapıyı 1 kez açmalıdır. QR kamera önünde kalmaya devam etse dahi 30 saniye boyunca aynı token tekrar işlenmemeli, sunucu yanıtı beklenirken yeni okumalar engellenmeli ve kapı peş peşe röle tıklamalarıyla açılmamalıdır (yalnızca tek 1 tetik verilmelidir).

---

## 14. ⏳ Aşama 2 — QR Koduna Süre Sınırı (Expiration) ve Canlı Geri Sayım

- [ ] **14.1. Mobil Arayüzde Canlı Geri Sayım Sayacı (60 Saniye) ve İlerleme Çubuğu:**
  - **Nasıl Test Edilir:** Uygulamada QR kod modalını açın.
  - **Beklenen Sonuç:** Modal altında "Kalan Süre: 60 sn" şeklinde saniye saniye geri sayan canlı bir sayaç ve ona bağlı renk değiştiren (yeşil -> sarı -> kırmızı) ilerleme çubuğu görüntülenmeli; ekranda hiçbir taşma (overflow) olmamalıdır.
- [ ] **14.2. Süre İçi Geçerli QR Kod ile Kapının Açılması:**
  - **Nasıl Test Edilir:** QR kodu üretildikten sonraki ilk 60 saniye içinde (örneğin 20. saniyede) GM60 kamerasına okutun.
  - **Beklenen Sonuç:** Token sunucu tarafından doğrulanmalı (`allowed: true, reason: 'OK'`), WROOM rölesi çekerek kapıyı açmalıdır.
- [ ] **14.3. Süresi Dolan QR Kodun Sunucu Tarafından Kesin Reddi (EXPIRED_TOKEN):**
  - **Nasıl Test Edilir:** QR kodun fotoğrafını çekin veya ekran görüntüsünü alın. 60 saniye sürenin dolmasını bekleyin. Süre bittikten sonra (örneğin 70. saniyede) bu eski QR kodu GM60 kamerasına gösterin.
  - **Beklenen Sonuç:** Sunucu `NOW() > t.expires_at` kontrolüyle kodu reddetmeli (`allowed: false, reason: 'EXPIRED_TOKEN'`), cihaz röleyi kesinlikle tetiklememeli ve kapı kapalı kalmalıdır.
- [ ] **14.4. Süre Dolduğunda Mobil Ekranda Otomatik Karartma / Kilitlenme:**
  - **Nasıl Test Edilir:** Mobil uygulamada QR kod modalını açık bırakıp 60 saniyelik sürenin sıfırlanmasını bekleyin.
  - **Beklenen Sonuç:** Süre 0 olduğunda sayaç durmalı, QR kod üzerine yarı saydam kırmızı "Süresi Doldu - Kodu yenileyiniz" uyarısı gelmeli ve altındaki buton "Yeni QR Kod Al" butonuna dönüşmelidir.
- [ ] **14.5. Tek Dokunuşla Yeni QR Kod Alınması:**
  - **Nasıl Test Edilir:** Süresi dolduktan sonra "Yeni QR Kod Al" butonuna dokunun.
  - **Beklenen Sonuç:** Uygulama sunucudan anında yeni bir 60 saniyelik geçerli token üretmeli, sayaç tekrar 60'tan başlayarak geri saymalı ve yeni üretilen kodla kapı açılabilmelidir.
- [ ] **14.6. Telefon Saatini Değiştirme Saldırılarına Karşı Mutlak Güvenlik (Sunucu Saati Otoritesi):**
  - **Nasıl Test Edilir:** Telefonda bir QR kod üretin, telefonun sistem saatini 1 saat geriye alın ve eski kodu GM60'a okutun.
  - **Beklenen Sonuç:** Süre otoritesi telefon değil merkezi Postgres sunucusu olduğu için sunucu sürenin dolduğunu tespit etmeli (`EXPIRED_TOKEN`) ve kapı kesinlikle açılmamalıdır.
- [ ] **14.7. Kapı Açıldığında QR Kodun Animasyonlu Yeşil Tike Dönüşmesi ve Sayacın Durması:**
  - **Nasıl Test Edilir:** Telefonda QR kodu açık tutun ve GM60 okuyucuya gösterip kapıyı açtırın.
  - **Beklenen Sonuç:** Kapı açıldığı anda azalan çember anında durmalı ve canlı yeşil renge kilitlenmelidir. Ortadaki QR kod kaybolup yerine esnek elastik animasyonla büyüyen yeşil bir onay işareti (`Icons.check_rounded`) ve "Kapı Açıldı! - Geçiş onaylandı" yazısı gelmelidir. Pencere 3 saniye sonra kendiliğinden kapanmalıdır.
- [ ] **14.8. Akıllı Sesli Yönlendirme ve Durum Bildirimleri (TTS):**
  - **Nasıl Test Edilir:** Uygulamada QR kod modalını açın, kameraya gösterin ve kapıyı açtırın (veya sürenin dolmasını bekleyin).
  - **Beklenen Sonuç:** QR kod açıldığında telefon Türkçe olarak *"Telefonunuzun ekranını kameraya gösteriniz, 10 15 santimetre yaklaştırınız."* demeli; kapı açıldığında *"Kapı açıldı, geçebilirsiniz."* sesli uyarısı vermeli; süre dolduğunda ise *"Karekodun süresi doldu, lütfen kodu yenileyiniz."* diyerek kullanıcıyı ekrana bakmadan yönlendirmelidir.
- [ ] **14.9. Başka Kapıya Ait QR Okutulduğunda Kapı Uyuşmazlığı Uyarısı (Görsel + Sesli):**
  - **Nasıl Test Edilir:** A Kapısı için üretilmiş bir QR kodunu, B Kapısına ait GM60 kamera okuyucusuna gösterin.
  - **Beklenen Sonuç:** Sunucu `DOOR_MISMATCH` tespit edip B Kapısının rölesini tetiklememeli (kapı açılmamalıdır). Kullanıcının telefon ekranındaki dinamik sayaç çemberi anında kırmızı renge dönmeli; ekranda *"Kapı Uyuşmazlığı! Bu kod [Kapı Adı] kapısına ait değil"* rozeti belirmeli ve telefon sesli olarak *"Bu karekod bu kapıya ait değil. Lütfen doğru kapının karekodunu gösteriniz."* uyarısı vermelidir. 4 saniye sonra görsel uyarı kalkıp kullanıcının doğru kodla tekrar denemesi için normal karekod ekranına dönmelidir.

---

## 15. 🔒 Aşama 3 — QR Kodunu Tek Kullanımlık Yapma (Single-Use & Replay Koruması)

- [ ] **15.1. İlk Okutmada Kapının Açılması ve Kodun Atomik Tüketilmesi:**
  - **Nasıl Test Edilir:** Yeni bir QR kod oluşturun ve GM60 kamerasına okutun.
  - **Beklenen Sonuç:** Kod başarıyla doğrulanmalı (`allowed: true`), kapı rölesi çekip açılmalı ve veritabanında token `is_used = true, used_at = NOW(), use_count = 1` olarak atomik işaretlenmelidir.
- [ ] **15.2. İkinci Okutmada Kesin Reddetme (Replay / Kopya Engeli):**
  - **Nasıl Test Edilir:** 60 saniyelik süre henüz dolmamışken (örneğin 20. saniyede), ilk geçişte kullanılan aynı QR kodunu tekrar GM60 kamerasına gösterin (veya çekilen fotoğrafını okutun).
  - **Beklenen Sonuç:** Sunucu `ALREADY_USED` yanıtı dönmeli; WROOM rölesi kesinlikle çekmemeli, kapı kapalı kalmalı ve log tablosuna `${userName} (Zaten Kullanılmış QR)` olarak işlenmelidir.
- [ ] **15.3. Kullanılmış Kod Okutulduğunda Görsel Uyarı & Sesli Asistan Bildirimi:**
  - **Nasıl Test Edilir:** Zaten kullanılmış olan kodu açık tutup GM60 okuyucusuna gösterin.
  - **Beklenen Sonuç:** Telefon ekranındaki sayaç halkası turuncu/kehribar renge dönmeli; ekranda *"Bu Karekod Zaten Kullanıldı! Karekodlar tek kullanımlıktır. Lütfen yeni kod alınız."* rozeti belirmeli ve telefon Türkçe sesli olarak *"Bu karekod daha önce kullanılmıştır. Lütfen yeni karekod alınız."* anonsunu yapmalıdır.
- [ ] **15.4. Veritabanı Seviyesinde Yarış Durumu (Race Condition) Koruması:**
  - **Nasıl Test Edilir:** GM60 önünde kodun çok hızlı peş peşe algılanmasını sağlayın veya eşzamanlı iki istek gönderin.
  - **Beklenen Sonuç:** Postgres atomik `UPDATE ... WHERE is_used = FALSE AND (used_at IS NULL AND use_count = 0)` kilidi sayesinde yalnızca tek bir istek başarılı olmalı, ikinci istek `ALREADY_USED` ile reddedilmeli ve kapı asla 2 kez tetiklenmemelidir.
- [ ] **15.5. Tüketilen (`USED`) ile Kullanılmadan Süresi Dolan (`EXPIRED`) Kodların Ayrışması:**
  - **Nasıl Test Edilir:** Hiç okutulmadan 60 saniyesi dolan bir token ile kapıyı açıp tüketilen bir tokeni veritabanı veya loglardan inceleyin.
  - **Beklenen Sonuç:** Süresi dolan token `EXPIRED_TOKEN`, kullanılarak geçiş yapılan token ise `is_used = true` olarak net şekilde ayrışmalı; durumlar birbirine karışmamalıdır.
- [ ] **15.6. Sahadaki Eski ESP32-C3 Cihazların Kesin Korunması (Regresyon Güvencesi):**
  - **Nasıl Test Edilir:** ESP32-C3 bağlı bir kapıda mobil uygulama ile uzaktan kapı açma komutu verin.
  - **Beklenen Sonuç:** Eski C3 cihazları bu tek kullanımlık QR token kontrollerinden tamamen izole kalmalı; normal MQTT veya uygulama butonuyla kapıyı eskisi gibi 1 saniyelik darbeyle sorunsuz açmaya devam etmelidir.

---

## 16. ⚡ Mobil Uygulama Kapı Açma Butonu Hız Optimizasyonu (6-7 Saniye Gecikmenin Sıfırlanması)

- [ ] **16.1. Mobil Buton ile Anında Kapı Açma (< 300 ms):**
  - **Nasıl Test Edilir:** Telefon ev veya site Wi-Fi ağına bağlıyken veya mobil verideyken, ana ekrandaki "KAPIYI AÇ" butonuna dokunun.
  - **Beklenen Sonuç:** Butona basıldığı an 6-7 saniyelik yerel ağ discovery/timeout beklemesi yaşanmamalı; tıpkı QR okumada olduğu gibi ~200-300 milisaniye içinde MQTT üzerinden röle çekmeli ve kapı anında açılmalıdır.
- [ ] **16.2. Canlı Beacon Yokken Sıfır Gecikmeyle Buluta Geçiş (Zero-Wait Cloud Fallback):**
  - **Nasıl Test Edilir:** Telefon cihazla aynı yerel ağda değilken veya cihazdan canlı beacon gelmiyorken kapıyı aç butonuna basın.
  - **Beklenen Sonuç:** Uygulama eski/ölü IP'lere ve UDP discovery broadcast'lerine 4-5 saniye boyunca boşuna soket açıp beklememeli; 0 milisaniye gecikmeyle doğrudan bulut API'ye (`api.openDoor`) giderek kapıyı anında açmalıdır.
- [ ] **16.3. Yerel Ağda Canlı Cihaz Varken Ultra Hızlı Yerel Tetikleme (150 ms Sınırı):**
  - **Nasıl Test Edilir:** Cihaz ile aynı Wi-Fi ağındayken ve cihazdan canlı UDP beacon akarken kapıyı aç butonuna basın.
  - **Beklenen Sonuç:** Yerel UDP unicast soketi maksimum 150 ms içinde kapıyı açmalı; yerelden yanıt alınamazsa hiçbir HTTP veya broadcast kuyruğuna girmeden derhal buluta devredilmelidir.

---

## 17. 👤 Üyelik Sistemi — Aşama 2: Bireysel Kullanıcı Self-Service Kaydı ve 6 Haneli E-posta Doğrulaması

- [ ] **17.1. Giriş Ekranından "Yeni Hesap Oluştur" Sayfasına Geçiş:**
  - **Nasıl Test Edilir:** Uygulama giriş ekranının en altında yer alan *"Hesabınız yok mu? Yeni Hesap Oluştur"* butonuna dokunun.
  - **Beklenen Sonuç:** "Kayıt Ol" başlıklı form sayfası (Ad, Soyad, E-posta, Şifre, Şifre Tekrar) akıcı şekilde açılmalı, arayüzde hiçbir taşma (overflow) olmamalı.
- [ ] **17.2. Form Doğrulamaları ve Hata Denetimi:**
  - **Nasıl Test Edilir:** Alanları boş bırakarak veya şifreleri birbiriyle uyumsuz girerek "Kayıt Ol" butonuna basın.
  - **Beklenen Sonuç:** Form geçersiz alanları kırmızı uyarı ile belirtmeli, şifrelerin eşleşmediğini kullanıcıya bildirmelidir.
- [ ] **17.3. Kayıt Olma ve SMTP ile 6 Haneli Doğrulama Kodu Gönderimi:**
  - **Nasıl Test Edilir:** Geçerli bir e-posta adresi (örneğin kendi e-postanız) girerek "Kayıt Ol" butonuna basın.
  - **Beklenen Sonuç:** Bu aşamada `users` tablosunda satır OLUŞMAMALI; `pending_registrations` tablosunda ad ve parola ÖZETİ (bcrypt) ile bekleyen kayıt bulunmalı. Kurumsal SMTP (`kodver@gudeteknoloji.com.tr`) üzerinden ilgili e-postaya 6 haneli kod gönderilmeli (e-postada istek saati ve "30 dakika geçerlidir" yazmalı) ve uygulama "E-Posta Doğrulama" ekranına geçmelidir. E-posta GÖNDERİLEMEZSE uygulama "Doğrulama kodu şu anda e-posta ile gönderilemiyor…" hatasını göstermeli ve doğrulama ekranına GEÇMEMELİDİR.
- [ ] **17.4. 6 Haneli Kod ile Hesap Doğrulama ve Otomatik Giriş:**
  - **Nasıl Test Edilir:** E-postaya gelen 6 haneli kodu büyük kutucuğa girin ve "Doğrula" butonuna basın (veya klavyeden onaylayın).
  - **Beklenen Sonuç:** Kod başarıyla doğrulanmalı; `users` satırı ANCAK ŞİMDİ oluşmalı (`email_verified = true`, `role = 'individual'`), `pending_registrations` satırı silinmeli, kod tek kullanımlık olmalı (aynı kod ikinci kez kabul edilmemeli). Kullanıcıya JWT token üretilerek doğrudan ana ekrana yönlendirilmelidir.
- [ ] **17.5. Hatalı Kod Girildiğinde Deneme Hakkı Koruması:**
  - **Nasıl Test Edilir:** Kasıtlı olarak yanlış bir 6 haneli kod girip "Doğrula"ya basın.
  - **Beklenen Sonuç:** Ekranda "Geçersiz veya süresi dolmuş doğrulama kodu. Kalan hakkınız: X" uyarısı çıkmalı, 5 hatalı denemeden sonra kod bloke edilmelidir.
- [ ] **17.6. Kodu Yeniden Gönder (Resend Code) Fonksiyonu:**
  - **Nasıl Test Edilir:** Doğrulama ekranındaki "Kodu Tekrar Gönder" butonuna dokunun.
  - **Beklenen Sonuç:** E-posta kutusuna yeni bir 6 haneli kod gelmeli; eski kod, yeni kod BAŞARIYLA gönderildikten sonra iptal edilmelidir (gönderim başarısız olursa önceki geçerli kod geçerli kalır). Kod 30 dakika geçerlidir; e-posta gecikirse bu süre içinde girilen kod kabul edilmelidir.

---

## 18. 📦 Üyelik Sistemi — Aşama 3: Kutu QR Kodu ile Cihaz Sahiplenme (Device Claiming)

- [x] **18.1. Bireysel Kullanıcı Ana Paneli Görünümü:**
  - **Nasıl Test Edilir:** Doğrulanmış bireysel kullanıcı (`individual`) hesabıyla uygulamaya girin.
  - **Beklenen Sonuç:** "Cihaz Ekle", "Daire Kullanıcısıyım" butonları ve "Sahiplendiğim Cihazlar" listesi şık, taşmasız bir arayüzle açılmalı.
- [x] **18.2. Kutu QR Kodu ile Kamera Taraması:**
  - **Nasıl Test Edilir:** Ana ekrandaki "Cihaz Ekle" butonuna dokunun ve "Kutu QR Kodunu Tara" seçeneğini seçip ambalaj kutusundaki QR kodu kameraya gösterin.
  - **Beklenen Sonuç:** Kamera QR kodu anında yakalamalı, taranan cihaz UID'si sunucuya gönderilmeli ve cihaz kullanıcı hesabına bağlanmalıdır.
- [x] **18.3. Seri Numarası / UID ile Elle Ekleme:**
  - **Nasıl Test Edilir:** "Cihaz Ekle" diyalogunda "Seri No / UID ile Elle Ekle" seçeneğine dokunup elinizdeki cihazın UID'sini (örn: `00861A0D5020`) yazarak "Cihazı Hesaba Bağla" butonuna basın.
  - **Beklenen Sonuç:** Cihaz başarıyla hesaba bağlanmalı ve "Cihaz (00861A0D5020) başarıyla hesabınıza bağlandı!" bildirimi gösterilmelidir.
- [x] **18.4. Canlı Liste Güncellemesi & Otomatik Rol Güncellemesi:**
  - **Nasıl Test Edilir:** Cihaz sahiplenildikten sonra ana ekrana dönün.
  - **Beklenen Sonuç:** Cihaz eklenince kullanıcı otomatik "Site Yöneticisi" rolünü almalı, "Daire Kullanıcısıyım" butonu gizlenmeli ve cihaz listede taşmasız yer almalıdır.
- [ ] **18.5. Zaten Sahiplenilmiş Cihaz Koruma Denetimi:**
  - **Nasıl Test Edilir:** Başka bir kullanıcı hesabı tarafından sahiplenilmiş bir cihazın QR veya UID'sini girmeye çalışın.
  - **Beklenen Sonuç:** Sunucu `409 Conflict` dönmeli; kullanıcıya "Bu cihaz zaten başka bir kullanıcı hesabı tarafından sahiplenilmiş" uyarısı verilmelidir.

---

## 19. 🏢 Üyelik Sistemi — Aşama 4: Dinamik Site, Blok ve Daire Yönetimi (Site Kurulumu)

- [x] **19.1. Sahiplenilen Cihaz Kartında "Siteyi Kur" Butonu:**
  - **Nasıl Test Edilir:** Ana ekranda sahiplenilmiş cihaz kartına bakın.
  - **Beklenen Sonuç:** Kart üzerinde "Siteyi Kur" butonu belirmeli, tıklandığında "Site Kurulum Sihirbazı" açılmalıdır.
- [x] **19.2. Dinamik Blok Ekleme ve Düzenleme:**
  - **Nasıl Test Edilir:** Sihirbazda "+ Blok Ekle" butonuna basın, blok adlarını ("A Blok", "B Blok", "Zümrüt Blok" vb.) ve daire sayılarını değiştirin.
  - **Beklenen Sonuç:** Bloklar listeye dinamik olarak eklenmeli, daire sayıları bağımsız olarak ayarlanabilmeli, istenen blok silinebilmelidir.
- [x] **19.3. Otomatik Site Onayı ve SITE_OWNER Rolü:**
  - **Nasıl Test Edilir:** Formu doldurup "Site Kurulumunu Tamamla" butonuna basın.
  - **Beklenen Sonuç:** Site veritabanında `approval_status = 'approved'` olarak oluşturulmalı, kullanıcı `site_memberships` tablosunda `role = 'SITE_OWNER'` olarak kaydedilmeli ve cihaz kapıya bağlanmalıdır.
- [x] **19.4. Kurulum Sonrası Yönetici Ekranına Otomatik Geçiş:**
  - **Nasıl Test Edilir:** Kurulum tamamlandıktan sonra ana ekranın tepkisini izleyin.
  - **Beklenen Sonuç:** Uygulamayı kapatıp açmaya gerek kalmadan kurulan sitenin blokları ve daireleri yönetim panelinde listelenmelidir.

---

## 20. 🚪 Üyelik Sistemi — Aşama 5: Bağımsız Kapı Yönetimi & Cihaz Atama (Kapı ≠ Cihaz)

- [x] **20.1. Siteye Bağımsız "+ Yeni Kapı" Ekleme:**
  - **Nasıl Test Edilir:** Siteler sayfasında sitenizi seçip "Kapılar" bölümündeki "+ Yeni Kapı" butonuna dokunun. "Otopark Bariyeri" adında bir kapı tanımlayıp kaydedin.
  - **Beklenen Sonuç:** Kapı anında oluşturulmalı, "Cihaz atanmamış (Kapı kontrolü pasif)" uyarısıyla listede belirmelidir.
- [x] **20.2. Kapı Erişim Kapsamı (Ortak / Blok Kapısı / Özel):**
  - **Nasıl Test Edilir:** Yeni kapı eklerken veya düzenlerken erişim kapsamını "Blok Kapısı" yapıp açılan listeden "A Blok"u seçin.
  - **Beklenen Sonuç:** Kapı kartında turkuaz renkli `A Blok Kapısı` rozeti net şekilde görüntülenmeli, taşma olmamalıdır.
- [x] **20.3. Sahiplenilen Cihazı Listeden Tek Tıkla Atama:**
  - **Nasıl Test Edilir:** Kapı kartında "Cihaz Ata" butonuna dokunun. Açılan penceredeki "Kullanılabilir Cihazlarınız" listesinden ambalaj kutusundan sahiplendiğiniz `00861A0D5020` kartına dokunun.
  - **Beklenen Sonuç:** UID otomatik form alanına dolmalı; "Cihazı Ata" denildiğinde kapı cihazla eşleşip donanım rozetiyle (mor WROOM) aktifleşmelidir.
- [x] **20.4. Cihazı Kapıdan Çıkarma (Serbest Bırak / Unassign):**
  - **Nasıl Test Edilir:** Cihaz atanmış bir kapıda "Değiştir"e basın ve alttaki kırmızı "Cihazı Kapıdan Çıkar (Serbest Bırak)" butonuna dokunun.
  - **Beklenen Sonuç:** Cihaz kapıdan sökülmeli, kapı "Cihaz atanmamış" durumuna geçmeli, cihaz ise boşa çıkarak başka kapılara atanabilir hale gelmelidir.
- [x] **20.5. Kapıyı Düzenleme ve Silme:**
  - **Nasıl Test Edilir:** Kapı kartındaki üç nokta (⋮) menüsünden "Kapıyı Düzenle" ve "Kapıyı Sil" işlemlerini test edin.
  - **Beklenen Sonuç:** Kapı adı/kapsamı güncellenebilmeli; silindiğinde ise onay diyalogu çıkıp kapı güvenle kaldırılmalı ve sitenin kapı sayısı güncellenmelidir.

---

## 21. 🔄 Üyelik Sistemi — Aşama 6: Arızalı Cihazı Değiştirme (Kapı ve Yetkiler Korunarak)

- [ ] **21.1. Menüden "Arızalı Cihazı Değiştir" Diyalogunun Açılması:**
  - **Nasıl Test Edilir:** Cihaz atanmış bir kapı kartının üç nokta (⋮) menüsünden "Arızalı Cihazı Değiştir" seçeneğine dokunun (veya "Değiştir" butonuna basıp açılan penceredeki sarı butona dokunun).
  - **Beklenen Sonuç:** Yeşil kalkan ikonlu bilgilendirme uyarısı ("Kapı numarası, daire izinleri ve sakin yetkileri aynen korunur"), eski arızalı UID ve yeni cihaz giriş alanı ile taşmasız şık bir diyalog açılmalıdır.
- [ ] **21.2. Yeni Cihazın Kutu QR Kodunu Okutarak Değiştirme:**
  - **Nasıl Test Edilir:** Diyalogda "Yeni Cihazın Kutu QR Kodunu Tara" butonuna basıp yeni kutu ambalajındaki QR kodu kameraya gösterin.
  - **Beklenen Sonuç:** Kamera QR kodu okur okumaz yeni UID alana yazılmalı, "Cihazı Değiştir" butonuna basıldığında yeni donanım anında kapıya atanmalı, eski cihaz boşa çıkarılmalı ve kapı yetkileri hiç bozulmadan korunmalıdır.
- [ ] **21.3. Boştaki Cihazlardan Seçerek veya Seri No Girerek Değiştirme:**
  - **Nasıl Test Edilir:** Diyalogda hesapta kayıtlı boş cihaz çiplerinden birine dokunun veya yeni seri no/UID girip onaylayın.
  - **Beklenen Sonuç:** Cihaz başarıyla değiştirilmeli, "Cihaz başarıyla değiştirildi. Kapı yetkileri ve ayarları aynen korundu." bildirimi gelmeli ve kapı kartı yeni UID ile otomatik canlı güncellenmelidir.
- [ ] **21.4. Kapı Yetkilerinin ve Sakin İzinlerinin Korunduğunun Doğrulanması:**
  - **Nasıl Test Edilir:** Cihaz değişimi sonrasında kapı detayını veya sakin yetkilerini inceleyin.
  - **Beklenen Sonuç:** Kapı ID'si (`site_doors.id`), kapı adı, blok eşleşmesi ve daha önce atanmış tüm geçiş yetkileri sıfırlanmadan aynen kalmalıdır.

---

## 22. 📱 Üyelik Sistemi — Aşama 7: Site Katılım QR Kodu Üretimi & Yönetimi

- [x] **22.1. Site Katılım QR Kodunun Görüntülenmesi:**
  - **Nasıl Test Edilir:** Süper Kullanıcı veya Site Yöneticisi olarak "Siteler" sayfasına girin. Bir site kartında veya seçili site detay kutusunda bulunan mavi renkli **"Site Katılım QR"** butonuna dokunun.
  - **Beklenen Sonuç:** Taşma ("overflow") olmaksızın şık bir diyalog penceresi açılmalı; sitenin adı, şehri, ortasında yüksek çözünürlüklü `SITE_JOIN:<token>` QR kodu, geçerlilik/oluşturulma tarihi ve bilgilendirme metni ("Bu QR kod site sakinlerinin siteye katılma başvurusu yapması içindir. Kapı açmaz.") gösterilmelidir.
- [x] **22.2. QR Paylaşım Metninin Panoya Kopyalanması:**
  - **Nasıl Test Edilir:** Diyalog penceresindeki **"Bağlantı & QR Kodunu Kopyala"** butonuna dokunun.
  - **Beklenen Sonuç:** "Site katılım bilgileri panoya kopyalandı." yeşil bildirimi çıkmalı ve panoya site adı, katılım formatı (`SITE_JOIN:...`) ve yönergeleri içeren temiz bir metin kopyalanmalıdır.
- [x] **22.3. QR Kodunu Güvenle Yenileme (Rotate Token):**
  - **Nasıl Test Edilir:** Diyalog penceresindeki kırmızı çerçeveli **"QR Kodunu Yenile"** butonuna dokunun, çıkan güvenlik onay penceresinde ("Eski QR kodlar anında geçersiz kılınır") "Evet, Yenile" butonunu onaylayın.
  - **Beklenen Sonuç:** Sunucuda eski katılım tokeni iptal edilmeli, anında yeni bir katılım tokeni (`SITE_JOIN:SJT-...`) üretilmeli ve ekrandaki QR kod görüntüsü otomatik canlı olarak yeni QR ile güncellenmelidir.
- [x] **22.4. Güvenlik ve Geriye Dönük Uyumluluk (Kapı QR Ayrımı):**
  - **Nasıl Test Edilir:** Üretilen QR kodun ham içeriğini veya kopyalanan metni inceleyin.
  - **Beklenen Sonuç:** Token `SITE_JOIN:SJT-...` önekiyle başlar; kapı açma QR kodlarından (`QR:<token>`) tamamen ayrıdır ve kapı okuyucularında kapı açma yetkisi doğurmaz.

---

## 23. 👥 Üyelik Sistemi — Aşama 8: Sakin Katılım Talebi & Yönetici Onay/Ret Paneli

- [ ] **23.1. Bireysel Kullanıcının QR Okutarak Başvuru Yapması:**
  - **Nasıl Test Edilir:** Bireysel kullanıcı hesabıyla giriş yapın. Ana ekrandaki **"Siteye Katıl (QR Okut)"** butonuna dokunun. Yöneticinin ürettiği Site Katılım QR kodunu kamerayla tarayın (veya tokeni yapıştırıp "Site Bilgilerini Getir"e basın).
  - **Beklenen Sonuç:** Sitenin adı ve şehri yüklenmeli; açılan menülerden `[Blok Seçimi]` ve `[Daire Seçimi]` dinamik olarak yapılabilmeli, isteğe bağlı not yazılıp "Katılım Başvurusunu Gönder" denildiğinde başvuru başarıyla oluşturulmalıdır.
- [ ] **23.2. Bireysel Kullanıcı Ekranında Başvuru Durumunun Görünmesi:**
  - **Nasıl Test Edilir:** Başvuru gönderildikten sonra ana ekranı kontrol edin.
  - **Beklenen Sonuç:** "Katılım Başvurularım" başlığı altında sitenin adı, blok, daire ve sarı renkli `Onay Bekliyor` rozeti listelenmelidir.
- [ ] **23.3. Yöneticinin Katılım Taleplerini İncelemesi & Onaylaması:**
  - **Nasıl Test Edilir:** Site yöneticisi veya süper kullanıcı hesabına geçin. "Siteler" sayfasındaki site kartında veya detay kutusunda sarı renkli **"Katılım Talepleri"** butonuna dokunun.
  - **Beklenen Sonuç:** Açılan pencerede başvuran kişinin adı, e-postası, telefonu, talep ettiği blok/daire ve başvuru tarihi listelenmeli; bekleyen talep sayısı rozeti görünmelidir.
  - **Onaylama:** `Onayla` butonuna dokunun. "Başvuru başarıyla onaylandı" bildirimi çıkmalı, talep yeşil `Onaylandı` durumuna geçmeli; dairede ilk sakinse `APARTMENT_ADMIN`, sonraki sakinse `FAMILY_MEMBER` rolüyle atanmalıdır.
- [ ] **23.4. Katılım Başvurusunun Reddedilmesi ve Gerekçe Bildirimi:**
  - **Nasıl Test Edilir:** Başka bir başvuru için `Reddet` butonuna dokunun, isteğe bağlı gerekçe (örn: "Daire sahibi teyit etmedi") yazıp onaylayın.
  - **Beklenen Sonuç:** Talep kırmızı `Reddedildi` rozetine geçmeli; başvuran kullanıcının ekranında da ret gerekçesiyle birlikte kırmızı bildirim görünmelidir.
- [ ] **23.5. Mükerrer Başvuru ve E-posta Doğrulama Koruması:**
  - **Nasıl Test Edilir:** Aynı daire için bekleyen başvurusu olan bir hesapla tekrar başvuru yapmayı deneyin.
  - **Beklenen Sonuç:** "Bu site için zaten onay bekleyen bir katılım başvurunuz bulunmaktadır" uyarısı verilmeli, mükerrer kayıt engellenmelidir.

---

## 24. 👑 Üyelik Sistemi — Aşama 9: Daire Admini & Aile Üyeleri Hiyerarşisi

- [ ] **24.1. İlk Onaylanan Sakinin Otomatik "Daire Yöneticisi" Olması:**
  - **Nasıl Test Edilir:** Boş bir daireye ilk kez katılım başvurusu yapan bir bireysel kullanıcıyı yönetici panelinden onaylayın. Ardından o kullanıcının hesabıyla giriş yapıp ana ekranı kontrol edin.
  - **Beklenen Sonuç:** Ana ekranda "Kayıtlı Dairem" kartı altında sitenin adı, bloğu, dairesi ve altın/kehribar renkli `👑 Daire Yöneticisi` rozeti görünmeli; "Daire Sakinleri" listesinde kendisi "(Siz)" etiketiyle `Daire Yön.` olarak listelenmelidir.
- [ ] **24.2. Sonraki Sakinlerin Otomatik "Aile Üyesi" Olması:**
  - **Nasıl Test Edilir:** Aynı daireye ikinci bir bireysel kullanıcı hesabıyla katılım başvurusu gönderip onaylayın.
  - **Beklenen Sonuç:** İkinci kullanıcının ekranında mavi/mor renkli `👨‍👩‍👧 Aile Üyesi` rozeti görünmeli; Daire Yöneticisinin ekranında ise bu yeni sakin otomatik olarak "Aile Üyesi" etiketiyle listelenmelidir.
- [ ] **24.3. Daire Yöneticisinin Aile Üyelerini Listelemesi & Yönetmesi:**
  - **Nasıl Test Edilir:** Daire Yöneticisi hesabıyla ana ekrandaki "Daire Sakinleri" listesini inceleyin.
  - **Beklenen Sonuç:** Dairedeki tüm fertlerin adı, e-posta adresi, rol rozeti ve katılım tarihi eksiksiz görünmelidir.
- [ ] **24.4. Aile Üyesini Daireden Çıkarma İşlemi (Yetki Korumalı):**
  - **Nasıl Test Edilir:** Daire Yöneticisi ekranında aile üyesinin yanındaki kırmızı "Üyeyi Çıkar" butonuna dokunun ve onaylayın.
  - **Beklenen Sonuç:** Onay sonrası üye listeden anında kalkmalı, çıkarılan kullanıcının ekranında ilgili daire kaydı silinmeli; aile üyesi ise Daire Yöneticisini veya kendisini bu yolla çıkaramamalıdır.
- [ ] **24.5. Canlı ve Otomatik Yenileme (Uygulamayı Kapatıp Açmama):**
  - **Nasıl Test Edilir:** Üye onaylandığında veya çıkarıldığında üstteki "Daireleri Yenile" butonuna veya aşağı çekip bırakmaya (RefreshIndicator) dokunun.
  - **Beklenen Sonuç:** Uygulamadan çıkış yapmadan veya uygulamayı yeniden başlatmadan güncel sakin kadrosu ve roller anında ekrana yansımalıdır.

---

## 25. 🚪 Üyelik Sistemi — Aşama 10: Otomatik Kapı Yetkilendirmesi

- [ ] **25.1. Ortak Kapı Yetkisinin Otomatik Tanımlanması (SITE_COMMON):**
  - **Nasıl Test Edilir:** Dairesi onaylanmış bir bireysel kullanıcı hesabıyla giriş yapın.
  - **Beklenen Sonuç:** Sitenin ortak kapıları ("Site Ana Giriş", "Bahçe Kapısı" vb.) "Yetkili Kapılarım" başlığı altında yeşil `🌐 Site Ortak Kapısı` rozetiyle otomatik olarak listelenmeli; kullanıcı kapıyı açabilmeli ve "Giriş QR Kodu" üretebilmelidir.
- [ ] **25.2. Bloğa Özel Kapı Yetkisi (Kendi Bloğu - BLOCK):**
  - **Nasıl Test Edilir:** A Blok'ta dairesi onaylanmış bir sakinle giriş yapın.
  - **Beklenen Sonuç:** Sitede tanımlı olan "A Blok Giriş" kapısı mavi `🏢 A Blok Kapısı` rozetiyle yetkili kapı listesinde görünmeli; "Kapıyı Aç" butonuyla veya "Giriş QR Kodu" ile kapı tetiklenebilmelidir.
- [ ] **25.3. Farklı Blok Kapılarının Gizlenmesi ve Yetkisiz Erişim Engeli:**
  - **Nasıl Test Edilir:** Sitede hem A Blok hem B Blok kapıları tanımlıyken, yalnızca A Blok sakini olan kullanıcının ekranını ve kapı erişimini inceleyin.
  - **Beklenen Sonuç:** B Blok kapısı kullanıcının listesinde KESİNLİKLE GÖRÜNMEMELİDİR. Doğrudan API üzerinden B Blok kapı ID'si tetiklenmek istense dahi sunucu `404 / 403 Yetkisiz Erişim` hatası dönmeli ve geçişe izin vermemelidir.
- [ ] **25.4. Bireysel Panelde Hızlı Kapı Açma & QR Giriş Entegrasyonu:**
  - **Nasıl Test Edilir:** "Yetkili Kapılarım" kartındaki "Kapıyı Aç" ve "Giriş QR Kodu" butonlarına dokunun.
  - **Beklenen Sonuç:** "Kapıyı Aç" butonuna basıldığında buton üzerinde yükleme çarkı dönmeli ve başarılı tetiklemede "Kapı açılıyor..." yeşil bildirimi çıkmalıdır. "Giriş QR Kodu" butonuna basıldığında ise GM60 okuyucuya gösterilecek dinamik QR kodu açılmalıdır.
- [ ] **25.5. Canlı ve Otomatik Yenileme (Uygulamayı Kapatıp Açmama Kuralı):**
  - **Nasıl Test Edilir:** Sakinin dairesi yönetici tarafından onaylandığı anda, bireysel kullanıcı ekranındaki "Kapıları Yenile" butonuna dokunun veya ekranı aşağı çekip bırakın.
  - **Beklenen Sonuç:** Uygulamayı kapatıp açmaya gerek kalmadan sakinin yetkili olduğu ortak kapılar ve blok kapısı canlı olarak ekrana yansımalıdır.

---

## 26. 🔑 Üyelik Sistemi — Aşama 11: Ek Kapı Yetkileri ve Toplu Yetkilendirme

- [ ] **26.1. Kapı Yetki Yönetimi Panelinin Açılması:**
  - **Nasıl Test Edilir:** Site Yöneticisi veya Süper Kullanıcı olarak "Siteler" sayfasındaki "Kapılar" listesine gelin. İlgili kapının sağındaki üç nokta (`⋮`) menüsünden **"Kapı Yetkileri"** seçeneğine dokunun.
  - **Beklenen Sonuç:** Kapı adı, kapı kapsam etiketi (`Site Ortak Kapısı`, `A Blok Kapısı`, `Özel / Ekstra Kapı`), bilgi kutucuğu ve sitedeki tüm blokların/dairelerin/sakinlerin hiyerarşik listesini içeren modern dialog penceresi açılmalıdır.
- [ ] **26.2. Tekil Sakine Ek Kapı Yetkisi Verme & Açma:**
  - **Nasıl Test Edilir:** B Blok kapısı veya Garaj kapısı için Yetki Yönetimi penceresini açın. A Blok'ta oturan bir sakinin yanındaki açma/kapama switch'ini açık konuma getirin (veya yetki verin).
  - **Beklenen Sonuç:** Durum rozeti mavi `Ek İzinli` olmalı; A Blok sakini kendi telefonundan uygulamayı kapatıp açmadan sayfayı yenilediğinde ilgili kapıyı görmeli ve tek tıkla açabilmelidir.
- [ ] **26.3. Bloğa Toplu Yetki Verme (Tüm Blok Sakinlerine Tek Tıkla Erişim):**
  - **Nasıl Test Edilir:** Kapı Yetkileri penceresinde herhangi bir blok başlığındaki üç nokta (`⋮`) menüsünden **"Tüm Bloğa Yetki Ver"** seçeneğine dokunun.
  - **Beklenen Sonuç:** Sunucuda o bloktaki tüm kayıtlı sakinler için tek işlemde `OVERRIDE_ALLOWED` tanımlanmalı; blok başlığında yetkili sakin sayısı anında tam sayıya (örn: `15/15 Yetkili`) güncellenmeli ve tüm sakinlerin switch'leri açık konuma gelmelidir.
- [ ] **26.4. Bloğun Ek Yetkilerini Sıfırlama:**
  - **Nasıl Test Edilir:** Daha önce ek yetki verilmiş bir blok için üç nokta (`⋮`) menüsünden **"Bloğun Yetkilerini Sıfırla"** seçeneğine dokunun.
  - **Beklenen Sonuç:** Ek yetkiler tek tıkla temizlenmeli, o bloktaki sakinler varsayılan durumlarına (yetkisiz veya blok varsayılanı) dönmeli ve yetkili sayısı anında güncellenmelidir.
- [ ] **26.5. İstisnai Erişim Engelleme (Ortak Kapıyı veya Blok Kapısını Bireysel Kapatma):**
  - **Nasıl Test Edilir:** Bir Ortak Kapı veya blok kapısı için listedeki sakinin switch'ini kapalı konuma getirin.
  - **Beklenen Sonuç:** Durum rozeti kırmızı `Engellendi` olmalı; o sakin kendi telefonunda ortak kapıyı açmaya çalıştığında yetkisiz erişim engellenmelidir. Switch tekrar açıldığında engel kalkıp varsayılan `Ortak Kapı` / `Blok Sakini` durumuna dönmelidir.
- [ ] **26.6. Dinamik Arama ve Canlı Yenileme (Uygulama Kapatıp Açmama Kuralı):**
  - **Nasıl Test Edilir:** Pencere üstündeki "Sakin veya daire ara..." kutusuna daire numarası veya isim yazıp arama yapın; yetki değişikliklerini kaydedip yenileme butonuna basın.
  - **Beklenen Sonuç:** Liste anında filtrelenmeli; hiçbir işlemde uygulama kapatıp açmaya gerek kalmadan veriler anında ve canlı güncellenmelidir.

---

## 27. 🏢 Üyelik Sistemi — Aşama 12: Akordiyon Sakin Listesi (PDF Bağımlılığının Kalkması)

- [ ] **27.1. Akordiyon Sakin Listesi Panelinin Açılması:**
  - **Nasıl Test Edilir:** Site Yöneticisi veya Süper Kullanıcı olarak "Siteler" sayfasına gelin. Site kartındaki yeşil renkli **"Sakin Listesi (Akordiyon)"** butonuna veya "Daireler" başlığının sağındaki butona dokunun.
  - **Beklenen Sonuç:** Sitedeki toplam blok, toplam daire ve toplam sakin sayısını özetleyen sayaç rozetleri, arama kutucuğu ve filtre çipleriyle birlikte modern akordiyon penceresi açılmalıdır.
- [ ] **27.2. Hiyerarşik Akordiyon Ağacı Gezinimi (Blok ▶ Daire ▶ Sakinler):**
  - **Nasıl Test Edilir:** Pencerede herhangi bir blok başlığına (`▶ A Blok (X Sakin • Y Daire)`) dokunarak bloğu genişletin; altındaki daire başlığına (`▶ Daire 12 (4 Sakin)`) dokunarak daireyi açın.
  - **Beklenen Sonuç:** Akıcı ve takılmasız animasyonla hiyerarşik yapı açılmalı; sağ üstteki "Genişlet / Daralt" butonuna basıldığında tüm ağaç tek hamlede açılıp kapanabilmelidir.
- [ ] **27.3. Daire Admini ve Aile Üyeleri Rollerinin İncelenmesi:**
  - **Nasıl Test Edilir:** Daire altındaki sakin kartlarını inceleyin.
  - **Beklenen Sonuç:** Daireye ilk onaylanan sakin sarı/altın renkli `👑 Daire Admini`, sonrakiler mor/mavi renkli `👨‍👩‍👧 Aile Üyesi` rozetiyle net olarak ayrışmalı; daha önce PDF şifre dökümü indirme zorunluluğu olmaksızın tüm sakin kadrosu canlı görüntülenebilmelidir.
- [ ] **27.4. Dinamik Arama ve Dolu/Boş Daire Filtreleri:**
  - **Nasıl Test Edilir:** Arama çubuğuna sakin adı, telefon numarası veya daire numarası yazın; filtre çiplerinden "Boş Daireler" veya "Dolu Daireler" seçin.
  - **Beklenen Sonuç:** Liste anlık olarak filtrelenmeli; aranan kriterle eşleşmeyen daireler ve bloklar gizlenerek aranan kişi veya daire doğrudan ekranda kalmalıdır.
- [ ] **27.5. Telefon ve E-posta Tek Dokunuşla Kopyalama:**
  - **Nasıl Test Edilir:** Sakin kartındaki telefon veya e-posta satırına dokunun (veya sağdaki `⋮` menüsünden "Numarayı Kopyala" seçin).
  - **Beklenen Sonuç:** Bilgi anında panoya kopyalanmalı ve "Panoya kopyalandı" mavi bildirimi çıkmalıdır.
- [ ] **27.6. Daireden Çıkarma & Canlı Yenileme:**
  - **Nasıl Test Edilir:** Bir sakinin sağındaki `⋮` menüsünden "Daireden Çıkar" seçeneğine dokunun ve onaylayın.
  - **Beklenen Sonuç:** Sakin listeden anında kalkmalı, daire ve blok sakin sayaçları otomatik güncellenmeli; uygulamayı kapatıp açmaya gerek kalmadan canlı durum korunmalıdır.

---

## 28. 🌐 Üyelik Sistemi — Aşama 13: Çoklu Site & Yönetim Firması Senaryoları

- [ ] **28.1. Tek Hesaptan Birden Fazla Site Yönetimi (Yönetim Firması Desteği):**
  - **Nasıl Test Edilir:** Bir hesapla birden fazla site kurun veya kullanıcıyı birden fazla sitede `SITE_OWNER` / `SITE_ADMIN` olarak yetkilendirin. Yönetici paneline ("Dashboard" ve "Siteler" sayfalarına) girin.
  - **Beklenen Sonuç:** "Siteler" sayfasında kullanıcının yetkili olduğu TÜM siteler listelenmeli; "Dashboard" (Kapı Kontrol) ekranındaki "Site Seçin" açılır menüsünden herhangi bir site seçildiğinde o sitenin kapıları ve donanım durumları anında yüklenmelidir.
- [ ] **28.2. Çift Rol (Yönetici & Sakin) Mod Değiştirme Butonu:**
  - **Nasıl Test Edilir:** Hem bir sitenin yöneticisi olan hem de herhangi bir sitede dairesi/kapısı bulunan kullanıcı hesabıyla uygulamaya giriş yapın. Üst çubuktaki (AppBar) `[ 🏠 Sakin Modu ]` / `[ 🏢 Yönetici Paneli ]` butonuna veya yan menüdeki (Drawer) en üstteki mod geçiş satırına dokunun.
  - **Beklenen Sonuç:** Uygulamadan çıkış yapmaya gerek kalmadan tek dokunuşla "Yönetici Paneli" ve "Sakin Modu" arasında geçiş yapılabilmelidir. Sakin Moduna geçildiğinde kullanıcının dairesi ve kapıları, Yönetici Paneline geçildiğinde ise site yönetim araçları aktif olmalıdır.
- [ ] **28.3. Bireysel Ekranda Çoklu Site Filtresi (Site Switcher Çipleri):**
  - **Nasıl Test Edilir:** Kullanıcının 2 veya daha fazla farklı sitede dairesi veya kapı yetkisi olduğunda Sakin Modu ana ekranını inceleyin.
  - **Beklenen Sonuç:** Ekranın üst kısmında (dar ekranda alt satıra sarılan, yatay kaydırma gerektirmeyen) site filtre çipleri (`[ 🏢 Tüm Siteler (X) ]`, `[ 🏢 Gül Sitesi (Y) ]`, `[ 🏢 Lale Sitesi (Z) ]`) görüntülenmelidir. Bir site çipine tıklandığında hem "Yetkili Kapılarım" hem de "Kayıtlı Dairelerim" yalnızca seçilen siteye göre anında süzülmeli; "Tüm Siteler" seçildiğinde tümü tekrar gösterilmelidir.
- [ ] **28.4. Kapı Kartlarında Belirgin Site Adı Rozeti:**
  - **Nasıl Test Edilir:** Bireysel kapı kartlarındaki başlık alanını inceleyin.
  - **Beklenen Sonuç:** Farklı sitelere ait kapıların hangi siteye ait olduğunu anında anlamak için kapı adının altında bina ikonuyla birlikte site adı rozeti (`🏢 Site Adı`) belirgin şekilde görüntülenmeli, taşma (overflow) olmamalıdır.
- [ ] **28.5. Canlı ve Otomatik Senkronizasyon (Uygulama Kapatıp Açmama Kuralı):**
  - **Nasıl Test Edilir:** Bir siteye yeni daire eklendiğinde veya yeni bir site kurulduğunda modlar veya siteler arasında geçiş yapın.
  - **Beklenen Sonuç:** Hiçbir işlemde uygulamayı kapatıp açmak gerekmemeli; filtreler ve seçimler anında `setState` ile canlı olarak güncellenmelidir.

---

## 29. 🛡️ Üyelik Sistemi — Aşama 14: Regresyon Testi ve Uçtan Uca Bütünlük

- [ ] **29.1. ESP32-C3 Süper Mini Donanım & Röle Bütünlüğü (Kural 3):**
  - **Nasıl Test Edilir:** Sahada aktif çalışan ESP32-C3 cihazını açın; hem mobil uygulamadan "Kapıyı Aç" butonuna basın hem de MQTT üzerinden tetikleme yapın.
  - **Beklenen Sonuç:** ESP32-C3 cihazı GPIO 10 üzerinden 1.5s röle pulse üretmeli, GPIO 2 durum LED'i çalışmalı, MQTT bağlantısı kopmamalı ve cihaz işlevleri hiçbir kesintiye uğramamalıdır.
- [ ] **29.2. ESP32-WROOM-32E Röle Kartı ve GM60 Entegrasyon Bütünlüğü (Kural 4):**
  - **Nasıl Test Edilir:** ESP32-WROOM cihazı üzerindeki GM60 okuyucusuna dinamik QR kodu okutun.
  - **Beklenen Sonuç:** GM60 UART2 (RX: 25, TX: 26) üzerinden okunan QR anında doğrulanmalı; GPIO 16 röle tetiklenmeli, GPIO 23 durum göstergesi stabil kalmalı ve peş peşe tetikleme debounce (5s) devrede olmalıdır.
- [ ] **29.3. Bluetooth ile Wi-Fi Kurulumu (BLE Provisioning) Doğrulaması:**
  - **Nasıl Test Edilir:** Mobil uygulamada "Bluetooth ile Wi-Fi Kur" ekranına girin; cihazı taratıp Wi-Fi ağ bilgilerini gönderin.
  - **Beklenen Sonuç:** BLE tarama ve kimlik aktarımı başarıyla tamamlanmalı; cihaz yeni Wi-Fi bilgilerini alıp ağa bağlanmalıdır.
- [ ] **29.4. Tüm Kapı Açma Metotlarının Birlikte Çalışması (Uçtan Uca Bütünlük):**
  - **Nasıl Test Edilir:** Sırasıyla:
    1. Mobil butonla uzaktan açma,
    2. GM60 kameraya dinamik QR göstererek açma,
    3. Geçici misafir kodu (Guest Pass) ile açma senaryolarını çalıştırın.
  - **Beklenen Sonuç:** Her üç yöntem de hatasız kapı açmalı; sunucu geçiş loglarına kullanıcı adı, geçiş yöntemi ve zaman damgası eksiksiz kaydedilmelidir.
- [ ] **29.5. Çoklu Site & Çift Rol Geçişinin Sıfır Takılma ile Doğrulanması:**
  - **Nasıl Test Edilir:** Hem yönetici hem sakin olan bir hesapta Yönetici Paneli ve Sakin Modu arasında geçiş yapıp ardından farklı siteleri filtreleyerek kapı açın.
  - **Beklenen Sonuç:** Mod ve site geçişleri sırasında hiçbir oturum kaybı veya ekran takılması yaşanmamalı; doğru kapılar ve doğru daireler anında ekranda görüntülenmelidir.

---

## 30. ⏱️ Dinamik QR — Aşama 4: Geçerlilik Süresini 30 Saniyeye Düşürme & Eski Tokenleri İptal Etme (Supersede)

- [ ] **30.1. Varsayılan Sürenin 30 Saniyeye İnmesi ve Dinamik Geri Sayım:**
  - **Nasıl Test Edilir:** Mobil uygulamadan kapı için dinamik QR kod penceresini açın.
  - **Beklenen Sonuç:** Sayaç halkası ve geri sayım süresi varsayılan olarak 30 saniyeden geriye doğru akmalı; süre bitince ekranda "Süresi Dolmuş QR Kod" uyarısı gösterilmelidir.
- [ ] **30.2. Yeni QR Kod Üretildiğinde Önceki QR Kodun Anında Hükümsüz Kılınması (Supersede):**
  - **Nasıl Test Edilir:** Ekrandaki ilk QR kodunun fotoğrafını çekin veya ekran görüntüsünü alın. Ardından modalı kapatıp açarak (veya yenileyerek) yeni bir kod alın. Eski fotoğrafı GM60 okuyucusuna gösterin.
  - **Beklenen Sonuç:** Eski kod sunucu tarafından `SUPERSEDED_TOKEN` koduyla reddedilmeli; röle tetiklenmemeli ve loglarda `${userName} (Hükümsüz/Yenilenmiş QR)` olarak işaretlenmelidir.
- [ ] **30.3. Ekrandaki Hükümsüz Kod (SUPERSEDED) Rozeti ve Sesli Asistan:**
  - **Nasıl Test Edilir:** Yenilenmiş eski bir kod GM60 okuyucusuna gösterildiğinde telefon ekranını izleyin.
  - **Beklenen Sonuç:** Sayaç kehribar rengine dönmeli, ekranda *"Karekod Hükümsüz Kılındı! Bu kod yenilendiği için geçersizdir."* uyarısı belirmeli ve Türkçe sesli anons yapılmalıdır.

---

## 31. 📍 Dinamik QR — Aşama 5: Sunucu Tabanlı Temel Geofence (Mesafe ve Yarıçap) Kontrolü

- [ ] **31.1. Geofence Alanı İçindeyken QR Kod Üretimi:**
  - **Nasıl Test Edilir:** Sitenin tanımlı koordinatlarına (`geofence_latitude`, `geofence_longitude`) izin verilen yarıçap (örn: 150m) dahilindeyken QR kodu isteyin.
  - **Beklenen Sonuç:** Sunucu Haversine formülüyle mesafeyi hesaplamalı; sınır içinde olunduğunu doğrulayıp yeşil onay ile 30 saniyelik QR kodunu üretmelidir.
- [ ] **31.2. Geofence Alanı Dışındayken QR Üretiminin Engellenmesi:**
  - **Nasıl Test Edilir:** Siteden 200m veya daha uzaktayken QR kodu açmayı deneyin.
  - **Beklenen Sonuç:** Sunucu `403 Forbidden` (`GEOFENCE_OUT_OF_RANGE`) hatası dönmeli; ekranda *"Kapı konumunda değilsiniz (Mesafe: ~Xm, İzin verilen sınır: Ym)"* uyarısı çıkmalı ve QR kod kesinlikle üretilmemelidir.
- [ ] **31.3. Konum Servisi Kapalıyken veya İzin Verilmediğinde Bilgilendirme:**
  - **Nasıl Test Edilir:** Telefonun GPS konumunu kapatıp QR kod butonuna dokunun.
  - **Beklenen Sonuç:** Uygulama *"Bu kapı için konum doğrulaması zorunludur. Lütfen telefonunuzun GPS konum servisini ve uygulama izinlerini açınız."* uyarısı vermeli, çökme yaşanmamalıdır.

---

## 32. 🛡️ Dinamik QR — Aşama 6: Geofence Güvenlik Katmanı (Zaman Aşımı, Hassasiyet ve Sahte Konum Koruması)

- [ ] **32.1. Sahte Konum (Mock Location / Fake GPS) Tespiti ve Engelleme:**
  - **Nasıl Test Edilir:** Android Geliştirici Seçenekleri'nden sahte konum (Mock Location) uygulaması açarak konumu site içine ayarlayın ve QR kodu isteyin.
  - **Beklenen Sonuç:** Sunucu `is_mocked: true` tespitini yakalamalı; `403 Forbidden` (`GEOFENCE_MOCK_LOCATION`) hatası vermeli ve audit loga güvenlik ihlali olarak kaydetmelidir.
- [ ] **32.2. Bayat / Eski Konum Bilgisi (Stale Location) Engeli:**
  - **Nasıl Test Edilir:** Konum zaman damgasının 60 saniyeden eski (veya gelecekte) olduğu senaryoyu test edin.
  - **Beklenen Sonuç:** Sunucu `GEOFENCE_LOCATION_STALE` hatası vermeli ve taze GPS sinyali alınana kadar geçişe izin vermemelidir.
- [ ] **32.3. Yetersiz GPS Doğruluğu (Inaccurate Accuracy > 100m) Koruması:**
  - **Nasıl Test Edilir:** GPS sinyalinin çok zayıf olduğu kapalı/bodrum alanında doğruluk payı 100 metreden büyükken istek gönderin.
  - **Beklenen Sonuç:** `GEOFENCE_LOCATION_INACCURATE` uyarısı verilmeli, açık alana çıkılması istenmelidir.

---

## 33. 🚫 Dinamik QR — Aşama 7: Kötüye Kullanım Önleme, Rate Limiting ve Yönetici Aktif QR İptali

- [ ] **33.1. Kullanıcı Başına Karekod İstek Sınırı (Rate Limiting):**
  - **Nasıl Test Edilir:** 60 saniye içinde peş peşe 6'dan fazla QR kodu istemeyi deneyin.
  - **Beklenen Sonuç:** Sunucu `429 Too Many Requests` yanıtı dönmeli; *"Karekod talebi çok sık yapıldı. Lütfen birkaç saniye bekleyip tekrar deneyiniz."* uyarısı gösterilmelidir.
- [ ] **33.2. Yöneticinin Bir Kapıdaki Tüm Aktif Karekodları Toplu İptal Edebilmesi:**
  - **Nasıl Test Edilir:** Yönetici panelinden `POST /manager/doors/:id/revoke-active-qrs` çağrısını çalıştırın.
  - **Beklenen Sonuç:** İlgili kapı için üretilmiş ve henüz kullanılmamış tüm aktif tokenlar anında iptal edilmeli (`is_active = FALSE, revoked_at = NOW()`); okutulmak istendiğinde kapı açılmamalıdır.
- [ ] **33.3. Sakinin Modal Pencereyi Kapatmasıyla Tokenin Otomatik İptal Edilmesi:**
  - **Nasıl Test Edilir:** QR kod ekranını açıp ardından kapatın (`pop`). Kapatılan tokenin veritabanındaki durumunu kontrol edin.
  - **Beklenen Sonuç:** Pencere kapandığı an arka planda `revoke-my-qr` tetiklenmeli; kullanılmamış açık token yakılarak (`burned`) kötüye kullanım engellenmelidir.

---

## 34. ⚡ Stabilite, Donma Önleme ve Kilitlenme Kontrolleri (Mobil & Canlı Test)

- [x] **34.1. Hızlı GPS Önbellek Doğrulaması (Kilitlenme ve Donma Önleme):**
  - **Nasıl Test Edilir:** Konum korumalı bir kapının QR kodunu açın. Cihazın son 12 saniye içinde taze konumu varken yanıt süresini gözlemleyin.
  - **Beklenen Sonuç:** Uygulama 10 saniye boyunca GPS uydusu beklemeden anında taze konumu kullanmalı; kapalı alanlarda modalın donması ve gecikmesi engellenmelidir.
- [x] **34.2. Eşzamanlı Buton Tıklama ve Race Condition Koruması (`_isFetchingToken`):**
  - **Nasıl Test Edilir:** QR kod modalındaki "Kodu Yenile" veya "Tekrar Dene" butonuna arka arkaya hızlıca dokunun.
  - **Beklenen Sonuç:** Çoklu istekler kilit (`_isFetchingToken`) mekanizması ile filtrelenmeli, sunucuya çakışan paralel istek gitmemeli ve arayüz kilitlenmemelidir.
- [x] **34.3. Güvenli Modal Kapanışı ve Sayfa Pop Sızıntısı Koruması (`canPop`):**
  - **Nasıl Test Edilir:** Kapı açıldıktan sonra kullanıcı modalı 3 saniye dolmadan el ile kapatsın.
  - **Beklenen Sonuç:** Otomatik kapanış sayacı tetiklendiğinde `Navigator.canPop()` kontrolü sayesinde arkadaki ana sayfa yanlışlıkla kapanmamalı, kullanıcı bulunduğu ekranda kalmalıdır.
- [x] **34.4. Fiziksel Cihazda Canlı Başlatma ve Impeller Vulkan Doğrulaması:**
  - **Nasıl Test Edilir:** Uygulama bağlı olan Android 15 (API 35) cihazında başlatılır (`adb am start`).
  - **Beklenen Sonuç:** Impeller Vulkan grafik motoru ve UDP Beacon port 8765 üzerinde hatasız, çökmesiz (0 crash/fatal) canlı olarak başlamalıdır.

---

## 35. 🎯 Donanıma Dayalı QR Butonu Görünürlüğü (ESP32-C3 ve Kamerasız Cihaz Filtresi)

- [x] **35.1. ESP32-C3 Süper Mini Kapılarında QR Geçiş Butonunun Gizlenmesi:**
  - **Nasıl Test Edilir:** ESP32-C3 bağlı olan bir kapıyı seçin (sakin veya bireysel kullanıcı ana ekranında).
  - **Beklenen Sonuç:** Kapıda kamera/GM60 bulunmadığı için "📲 QR Kod ile Giriş Yap" butonu kesinlikle görünmemeli; kullanıcı sadece "Kapıyı Aç" ve "Misafir Geçişi" butonlarını görmelidir.
- [x] **35.2. QR Okuyuculu WROOM Kapılarında QR Butonunun Aktif Olması:**
  - **Nasıl Test Edilir:** GM60 QR okuyucusu tanımlı (`qr_reader_enabled: true`) bir ESP32-WROOM kapısını seçin.
  - **Beklenen Sonuç:** QR butonu görünür olmalı, dokunulduğunda dinamik QR kodu sorunsuz üretilmelidir.
- [x] **35.3. Sunucu Koruması (Kamerasız Cihaz İçin Token İsteği Engeli):**
  - **Nasıl Test Edilir:** Postman veya curl ile C3 takılı bir kapı için `POST /app/doors/:id/qr-token` çağrısı yapın.
  - **Beklenen Sonuç:** Sunucu `400 Bad Request` ve `NO_QR_SCANNER_HARDWARE` hatası dönmeli; donanımsız kapılar için token üretmemelidir.

---

## 36. 👥 Daire Sakinleri Yönetimi (Aktif/Pasif, Silme, Şifre Değiştirme, Aile Reisi Devri)

- [ ] **36.1. Daire Sakini Aktif / Pasif (Deaktif) Yapma:**
  - **Nasıl Test Edilir:** Süper kullanıcı veya site yöneticisi olarak Siteler sayfasından "Site Sakinleri" akordiyon ağacını açın. İlgili daire sakin kartındaki üç nokta menüsünden "Üyeliği Pasife Al" seçeneğine dokunun ve onaylayın.
  - **Beklenen Sonuç:** Sakinin durumu pasife alınmalı, listede "İnaktif" kırmızı rozeti belirip metin üzeri çizili tona geçmeli; pasif sakinin kapı erişimleri durdurulmalıdır. Aynı menüden "Üyeliği Aktif Et" dendiğinde tekrar aktifleşmelidir. Yalnızca o daire üyeliği/kapı erişimi pasifleşir; kişinin hesabı (giriş) etkilenmez. Sistem yöneticisi hesabı pasife aldıysa kartta "Hesap pasif (sistem yöneticisi)" rozeti çıkar ve menüde işlem yerine bilgi satırı görünür. Sayfa kapatıp açılmadan anında güncellenmelidir.
- [ ] **36.2. Daire Sakinini Daireden Tamamen Silme:**
  - **Nasıl Test Edilir:** Sakin kartındaki menüden kırmızı renkli "Daireden Sil" seçeneğini seçip onaylayın.
  - **Beklenen Sonuç:** Sakin daireden tamamen çıkarılmalı, kapı yetki istisnaları temizlenmeli; eğer silinen kişi daire yöneticisi ise dairedeki diğer sakinlerden ilki otomatik olarak yeni yönetici yapılmalı (yoksa daire boşaltılmalıdır). Liste anında güncellenmelidir.
- [ ] **36.3. Daire Sakini Kendi Şifresini Değiştirme (Mevcut Parola Zorunlu):**
  - **Nasıl Test Edilir:** Daire sakini hesabıyla Profil ekranından şifre değiştirin: önce yanlış, sonra doğru mevcut parola girin. (Sakin kartındaki üç nokta menüsünde yönetici için "Şifre Değiştir" seçeneği YOKTUR.)
  - **Beklenen Sonuç:** Yanlış mevcut parola → 400 `CURRENT_PASSWORD_INVALID`; art arda 5 hata → 429 `CURRENT_PASSWORD_LOCKED` (Retry-After). Doğru parolada şifre bcrypt ile güncellenir, yanıtla yeni oturum anahtarı gelir (uygulama oturumu açık kalır) ve sakin yeni şifresiyle giriş yapabilir.
- [ ] **36.4. Aile Reisi Değiştirme (Yeni Daire Yöneticisi Atama):**
  - **Nasıl Test Edilir:** Standart aile üyesi olan bir sakin için üç nokta menüsünden "Aile Reisi Yap" seçeneğine dokunun ve onaylayın.
  - **Beklenen Sonuç:** Seçilen sakin `APARTMENT_ADMIN` ("Daire Admini") rozetine kavuşmalı; önceki daire yöneticisi standart aile üyesine dönüştürülmelidir.

---

## 37. 🛡️ Çift Taraflı Karşılıklı Site Silme Onay Sistemi (Site Yöneticisi & Süper Kullanıcı)

- [ ] **37.1. Site Yöneticisinin Silme Talebi Başlatması:**
  - **Nasıl Test Edilir:** Site Yöneticisi hesabıyla giriş yapın. Sitenin kartını açıp "Sil" butonuna dokunun ve onay verin.
  - **Beklenen Sonuç:** Site doğrudan silinmemelidir. Ekranda "Site silme talebi oluşturuldu. Süper kullanıcının onayı gerekmektedir." mesajı çıkmalı; sitede "Silme Onayı" rozeti ve amber renkli bilgi kutusu ("Süper Kullanıcının onayı bekleniyor", "Talebi İptal Et" butonu) belirmelidir.
- [ ] **37.2. Süper Kullanıcının Site Yöneticisi Talebini Onaylaması veya Reddetmesi:**
  - **Nasıl Test Edilir:** Süper Kullanıcı hesabıyla giriş yapın. Silme onayı bekleyen sitenin kartında beliren kırmızı uyarı kutusundaki "Silmeyi Onayla" ve "Talebi Reddet" butonlarını test edin.
  - **Beklenen Sonuç:** "Silmeyi Onayla" seçildiğinde onay modalı açılmalı ve onaylandığında site ve bağlı tüm birimler kalıcı olarak silinmeli; "Talebi Reddet" seçildiğinde ise talep iptal edilerek site normal durumuna dönmelidir.
- [ ] **37.3. Süper Kullanıcının Silme Talebi Başlatması ve Site Yöneticisinin Onaylaması:**
  - **Nasıl Test Edilir:** Süper Kullanıcı olarak yöneticisi bulunan bir sitede "Sil" butonuna dokunup talebi iletin. Ardından Site Yöneticisi hesabıyla girip site kartındaki kırmızı uyarı kutusunu kontrol edin.
  - **Beklenen Sonuç:** Süper Kullanıcı doğrudan silememeli, talep Site Yöneticisinin onayına düşmelidir. Site Yöneticisi "Silmeyi Onayla" butonuna bastığında site kalıcı olarak silinmelidir.
- [ ] **37.4. Yöneticisiz / Sahipsiz Sitelerin Doğrudan Silinebilmesi:**
  - **Nasıl Test Edilir:** Atanmış hiçbir site yöneticisi bulunmayan (yeni oluşturulmuş veya sahipsiz) bir sitede Süper Kullanıcı olarak "Sil" butonuna basın.
  - **Beklenen Sonuç:** Onay verecek yönetici bulunmadığından Süper Kullanıcı doğrudan kalıcı olarak silebilmeli; sahipsiz kilitli site durumu oluşmamalıdır.
- [ ] **37.5. Talep Eden Tarafın Kendi Talebini İptal Edebilmesi:**
  - **Nasıl Test Edilir:** Silme talebi oluşturmuş olan kullanıcı (Süper Kullanıcı veya Site Yöneticisi) site kartındaki "Talebi İptal Et" butonuna dokunsun.
  - **Beklenen Sonuç:** Silme talebi veritabanında `deletion_status = 'none'` durumuna getirilmeli; karttaki uyarı kutusu ve rozet anında kaybolmalıdır.
- [ ] **37.6. Canlı UI Yenilenmesi (Kural 7) ve Sıfır Taşma (Kural 6) Doğrulaması:**
  - **Nasıl Test Edilir:** Talep oluşturma, onaylama ve iptal etme işlemlerini farklı ekran boyutlarında test edin.
  - **Beklenen Sonuç:** Hiçbir işlemden sonra uygulamayı kapatıp açmak gerekmemeli (`_loadSites` ile anında güncellenmeli); küçük ekranlarda veya uzun site/kullanıcı isimlerinde hiçbir render taşması ("RenderFlex overflowed") oluşmamalıdır.

---

## 38. 📧 Süper Kullanıcı E-Posta Doğrulama Kodu İle Doğrudan Site Silme

- [ ] **38.1. E-Posta Doğrulama Kodunun Üretilmesi ve Gönderilmesi:**
  - **Nasıl Test Edilir:** Süper Kullanıcı olarak Siteler sayfasına girin. Bir sitenin kartındaki "Sil" butonuna basıp açılan seçim diyaloğundan "E-Posta Kodu İle Doğrudan Sil" seçeneğine dokunun (veya doğrudan karttaki "E-Posta Koduyla Sil" butonuna basın).
  - **Beklenen Sonuç:** Süper kullanıcının kayıtlı e-posta adresine `[DİKKAT] <Site Adı> Sitesi Kalıcı Silme Doğrulama Kodu` başlıklı e-posta gitmeli; e-postada "site ve tüm daire kullanıcıları silinecek eminseniz kodu giriniz" uyarısı ve 6 haneli kod yer almalıdır. Ekranda 6 haneli kod giriş modalı açılmalıdır.
- [ ] **38.2. Yanlış veya Eksik Kod Girişi Koruması:**
  - **Nasıl Test Edilir:** Açılan modalda hatalı veya 6 haneden kısa bir kod girip "Onayla ve Kalıcı Olarak Sil"e basın.
  - **Beklenen Sonuç:** İşlem reddedilmeli, modal kapanmamalı ve ekranda kırmızı renkle net hata bildirimi ("Lütfen 6 haneli kodu eksiksiz giriniz" veya "Girdiğiniz silme doğrulama kodu hatalı") gösterilmelidir.
- [ ] **38.3. Kodu Tekrar Gönder Butonu:**
  - **Nasıl Test Edilir:** Modal içindeki "Kodu Tekrar Gönder" butonuna dokunun.
  - **Beklenen Sonuç:** Buton geçici olarak pasife alınmalı, sunucudan yeni 6 haneli kod üretilip e-postaya gönderilmeli ve "Yeni kod e-posta adresinize gönderildi" teyidi verilmelidir.
- [ ] **38.4. Doğru Kod İle Sitenin Kalıcı Olarak Silinmesi:**
  - **Nasıl Test Edilir:** E-postaya gelen 6 haneli doğru kodu girip "Onayla ve Kalıcı Olarak Sil" butonuna basın.
  - **Beklenen Sonuç:** Site, bağlı bloklar, daireler, kapılar ve cihaz atamaları veritabanından kalıcı olarak silinmeli; başarı mesajı çıkmalı, sayfa kapatıp açılmadan anında taze verilerle yenilenmelidir (`_loadSites(force: true)`).
- [ ] **38.5. Bekleyen Onay Durumunda da E-Posta ile Hemen Silme Seçeneği:**
  - **Nasıl Test Edilir:** Site yöneticisine silme talebi iletilmiş ve yöneticinin onayı beklenirken (`pending_site_manager_approval`), Süper Kullanıcı olarak site kartını açın.
  - **Beklenen Sonuç:** Süper Kullanıcı uyarı bandında "Talebi İptal Et" butonunun yanında "E-Posta Kodu İle Hemen Sil" butonunu da görmeli; yönetici onayını beklemeden e-posta koduyla siteyi anında silebilmelidir.

---

## 39. 👥 Süper Kullanıcı Tüm Kullanıcılar Yönetim Menüsü (Sayfalanmış, Filtreli & Doğrudan Yönetim)

- [ ] **39.1. Yan Menüde Özel "Kullanıcı Yönetimi" Menü Öğesi:**
  - **Nasıl Test Edilir:** Süper Kullanıcı olarak giriş yapın ve sol yan menüyü açın.
  - **Beklenen Sonuç:** Menüde Profilim seçeneğinin hemen altında `Kullanıcı Yönetimi` öğesi yer almalı; tıklandığında doğrudan tüm kullanıcıların listelendiği özel yönetim sayfasına geçilmelidir.
- [ ] **39.2. Sayfa Sayfa (Paginated) Kullanıcı Listeleme:**
  - **Nasıl Test Edilir:** Kullanıcı Yönetimi sayfasını açın ve alt kısımdaki sayfalama butonlarını inceleyin.
  - **Beklenen Sonuç:** Sistemdeki kayıtlı tüm kullanıcılar (800+ kullanıcı) sayfa sayfa (varsayılan 15'erli, opsiyonel 25 ve 50'li) listelenmeli; toplam kullanıcı sayısı, mevcut sayfa ve toplam sayfa sayısı doğru gösterilmeli; İlk Sayfa, Önceki, Sonraki ve Son Sayfa butonları hatasız çalışmalıdır.
- [ ] **39.3. Canlı Arama ve Kişi Filtreleme:**
  - **Nasıl Test Edilir:** Sayfanın üstündeki arama kutusuna kullanıcı adı, e-posta adresi (`gmail.com`), kullanıcı kodu (`55906`) veya daire sakini kullanıcı adı yazın.
  - **Beklenen Sonuç:** Arama metnine uygun olan kullanıcılar debounced olarak anında listelenmeli; eşleşen kayıt sayısı güncellenmeli; 'X' temizleme butonu ile arama sıfırlanabilmelidir.
- [ ] **39.4. Rol Filtreleme Çipleri İle Anında Süzme & Süper Kullanıcı İzolasyonu:**
  - **Nasıl Test Edilir:** Arama çubuğunun altındaki "Tüm Roller", "Site Yöneticileri", "Daire Sakinleri" ve "Bireysel Kullanıcılar" çiplerini inceleyin.
  - **Beklenen Sonuç:** Süper kullanıcılar bu genel listede ve filtre çiplerinde kesinlikle yer almamalıdır (onlar için ayrı "Süper Kullanıcı Yönetimi" ekranı mevcuttur); yalnızca seçilen role sahip kullanıcılar listelenmeli ve sayfa sayfa gezilebilmelidir.
- [ ] **39.5. Sadeleştirilmiş Liste Kartları ve Detay Sayfası (Modal Bottom Sheet):**
  - **Nasıl Test Edilir:** Kullanıcı Yönetimi ekranındaki liste kartlarını inceleyin ve herhangi bir kullanıcının kartına dokunun.
  - **Beklenen Sonuç:** Ana listede yalnızca kullanıcının Adı Soyadı ve E-postası görüntülenmeli, taşma (overflow) yaşanmamalıdır; karta tıklandığında alttan açılan detay sayfasında rol, ID (#), e-posta doğrulama rozeti, telefon, kayıt tarihi, aktif/pasif anahtarı ve Düzenle/Sil butonları açılmalıdır.
- [ ] **39.6. Kullanıcı Bilgilerini Düzenleme & E-Posta Değiştirilemez (Deaktif Textbox) Koruması:**
  - **Nasıl Test Edilir:** Kullanıcı detay sayfasındaki "Düzenle" butonuna dokunarak açılan formu inceleyin; e-posta kutusunu değiştirmeyi deneyin.
  - **Beklenen Sonuç:** E-posta kutusu deaktif (disabled/salt okunur) görünmeli, kilit simgesi ve "E-posta adresi güvenlik nedeniyle değiştirilemez" uyarısı yer almalı; Süper kullanıcı dahil hiç kimse e-posta adresini düzenleme ekranından değiştirememelidir. Ad Soyad, telefon, rol, şifre ve aktiflik güncellenebilmelidir.
- [ ] **39.7. Hızlı Aktif/Pasif Geçişi:**
  - **Nasıl Test Edilir:** Kullanıcı detay sayfasındaki switch'e dokunarak kullanıcıyı pasife veya aktife çekin.
  - **Beklenen Sonuç:** Kullanıcının durumu canlı olarak sunucuda güncellenmeli ve anında yansımalıdır.
- [ ] **39.8. Kullanıcı Silme:**
  - **Nasıl Test Edilir:** Kullanıcı detay sayfasındaki kırmızı "Sil" butonuna dokunun; onay modalını onaylayın.
  - **Beklenen Sonuç:** Silinen kullanıcıya ait tüm yetkiler, cihaz ilişkileri ve kayıtlar güvenle temizlenerek kullanıcı veritabanından kalıcı olarak silinmeli; liste kapatıp açılmadan canlı yenilenmelidir.

---

## 40. 🧹 Veritabanı Temizliği, Otomatik Yaşam Döngüsü & Çöp Engelleme Sistemi

- [ ] **40.1. Sahte (@ahbu.local) Kullanıcı Temizliği & Otomatik Üretimin Engellenmesi:**
  - **Nasıl Test Edilir:** Yeni bir site ve daireler oluşturun. Veritabanını (`users` tablosu) veya Kullanıcı Yönetimi ekranını kontrol edin.
  - **Beklenen Sonuç:** Daireler oluşturulduğunda arka planda hiçbir sahte/kukla kullanıcı (`@ahbu.local`) üretilmemeli; daireler boş açılmalı; sadece gerçek kullanıcılar kayıt veya üyelik yoluyla atanmalıdır.
- [ ] **40.2. Daire Sıfırlama ve Site Silmede Gerçek Kullanıcıların Korunması:**
  - **Nasıl Test Edilir:** Bir daireye kullanıcı atayın ve ardından daireyi sıfırlayın veya siteyi silin.
  - **Beklenen Sonuç:** Dairenin kullanıcı ile ilişiği kesilmeli (`resident_user_code = null`) ancak gerçek kullanıcının kendisi veritabanından ASLA silinmemelidir.
- [ ] **40.3. Otomatik 24 Saatlik Arka Plan Bakım ve Çöp Toplayıcı (Maintenance Service):**
  - **Nasıl Test Edilir:** Sunucu başlangıç loglarını (`pm2 logs kapi-api`) inceleyin.
  - **Beklenen Sonuç:** API başladığında ve her 24 saatte bir `runDatabaseCleanup` otomatik tetiklenmeli; süresi geçmiş QR tokenler (1 günden eski), 2 günden eski e-posta doğrulama kodları ve 30 günden eski cihaz bağlantı/kapı logları otomatik temizlenmeli ve loglanmalıdır. Bakım servisi KULLANICI HESABI, üyelik veya tablo SİLMEZ (eski @ahbu.local silme ve yetim kayıt temizliği kaldırıldı); günlük bakımdan sonra kullanıcı sayısı değişmemelidir.
- [ ] **40.4. Süper Kullanıcı Canlı Veritabanı Sağlığı ve Manuel Temizlik Butonu:**
  - **Nasıl Test Edilir:** Süper Kullanıcı olarak "Kullanıcı Yönetimi" sayfasına girin ve üst bardaki temizlik fırçası (`Icons.cleaning_services_rounded`) simgesine dokunun.
  - **Beklenen Sonuç:** Veritabanı sağlık modalı açılmalı; gerçek kullanıcı sayısı (4), çöp kullanıcı sayısı (0), aktif siteler, çevrimiçi cihazlar ve log durumları canlı gösterilmeli; "Çöp Temizliği Yap" butonuna basıldığında temizlik tetiklenip kaç kaydın temizlendiği bildirilmelidir (yalnızca süresi geçmiş token/kod ve eski loglar silinir; hiçbir kullanıcı hesabı silinmez). "Kukla" sayacı yalnızca hiçbir daireye/üyeliğe bağlı olmayan @ahbu.local hesaplarını sayar; temizlik bu hesapları silmez.

---

## 41. 👥 Çoklu Site Yöneticisi, Yönetici Davet Sistemi & Çoklu Site Yönetimi

- [ ] **41.1. Bir Siteye Birden Fazla Site Yöneticisi Atanabilmesi:**
  - **Nasıl Test Edilir:** Bir site seçin. "Site Yöneticileri" kartındaki listeyi inceleyin.
  - **Beklenen Sonuç:** Sitede hem kurucu yönetici (`Kurucu Yönetici` rozeti) hem de eklenen ortak yöneticiler (`Site Yöneticisi` rozeti) aynı anda aktif olarak listelenebilmeli; hepsi siteyi yönetebilmelidir.
- [ ] **41.2. E-Posta ile Yönetici Davet Etme (Kayıtlı Kullanıcı):**
  - **Nasıl Test Edilir:** Site Yöneticileri kartındaki "Yönetici Davet Et" butonuna dokunun. Sistemde zaten kayıtlı olan bireysel veya sakin bir kullanıcının e-postasını girip davet gönderin.
  - **Beklenen Sonuç:** Kullanıcı anında bu sitenin yöneticileri arasına eklenmeli, rolü `site_manager`'a yükseltilmeli, kullanıcıya bilgilendirme e-postası gönderilmeli ve sayfa kapatıp açılmadan anında listede belirmelidir.
- [ ] **41.3. E-Posta ile Yönetici Davet Etme (Kayıtlı Olmayan Kullanıcı):**
  - **Nasıl Test Edilir:** Henüz sisteme kaydı olmayan bir e-posta adresi ile "Yönetici Davet Et" diyaloğundan davet gönderin.
  - **Beklenen Sonuç:** E-posta adresine site yöneticiliği davet linki ve bilgilendirme e-postası iletilmeli; Site Yöneticileri kartında "Bekleyen Davetler" başlığı altında davet edilen e-posta görüntülenmelidir.
- [ ] **41.4. Davet Edilen Kullanıcının Kaydolarak Otomatik Yönetici Olması:**
  - **Nasıl Test Edilir:** Davet edilen yeni kullanıcı e-postası ile mobil uygulamadan kayıt olun ve e-posta doğrulama kodunu girin.
  - **Beklenen Sonuç:** E-posta doğrulandığı anda sistem bekleyen daveti otomatik olarak kabul edilmiş (`ACCEPTED`) duruma getirmeli, kullanıcının rolünü `site_manager` yapmalı ve kullanıcı doğrudan sitenin yöneticisi olarak ana sayfaya giriş yapmalıdır.
- [ ] **41.5. Bekleyen Yönetici Davetini İptal Etme:**
  - **Nasıl Test Edilir:** "Bekleyen Davetler" listesinde yer alan bir davetin yanındaki "İptal Et" butonuna dokunun ve onaylayın.
  - **Beklenen Sonuç:** Davet sunucuda anında iptal edilmeli (`REVOKED`) ve listeden canlı olarak kaldırılmalıdır.
- [ ] **41.6. Ortak Yöneticilik Yetkisini Kaldırma (Kurucu Yönetici Koruması):**
  - **Nasıl Test Edilir:** Kurucu olmayan bir site yöneticisinin yanındaki kırmızı kullanıcı çıkarma simgesine dokunun ve onaylayın.
  - **Beklenen Sonuç:** Yöneticinin o sitedeki yöneticilik yetkisi kaldırılmalı; kurucu yöneticinin yanında ise kaldırma butonu gösterilmemeli ve sistemde en az 1 yönetici kalma kuralı korunmalıdır.
- [ ] **41.7. Bir Kullanıcının Birden Fazla Siteyi Yönetebilmesi (Çoklu Site Yönetimi):**
  - **Nasıl Test Edilir:** Site Yöneticisi rolündeki bir hesapla giriş yapın. Siteler menüsünde "Yeni Site" butonuna dokunarak ikinci bir site kurun veya başka bir siteye yönetici olarak davet edin.
  - **Beklenen Sonuç:** Site yöneticisi birden fazla siteyi listeleyebilmeli, siteler arasında serbestçe geçiş yapabilmeli ve her bir sitenin kapılarını, dairelerini ve telemetrisini bağımsız olarak yönetebilmelidir.

---

> **Bölüm 42–52 hakkında (2026-10 güvenlik/dayanıklılık + arayüz/akıcılık turu):** Bu bölümlerdeki maddeler, söz konusu turda sunucu, Flutter/Android istemcisi ve firmware üzerinde yapılan değişikliklerin saha doğrulama adımlarıdır. Her madde ilgili uygulama ajanının raporundan olduğu gibi ("yap → beklenen sonuç") aktarılmıştır. Eski bölümlerle çelişen bir adım olursa bu bölümlerdeki (daha yeni) davranış geçerlidir. Gizli değerler (parola, token, API anahtarı) listeye yazılmaz; komutlardaki `<paket>`, `<uid>` gibi yer tutucuları kendi değerlerinizle değiştirin. ESP32-C3 ve ESP32-WROOM ayrı donanımlardır: firmware maddeleri yalnız ilgili donanımda denenir. docker-compose.yml / ecosystem.config.cjs ile ilgili maddeler yalnız bu dosyalar canlıya uygulanırsa geçerlidir.

---

## 42. 🔐 Sunucu Sertleştirme — Kimlik Doğrulama, Oturum, Hız Sınırı, CORS, Şirket Uçları (S1)

- [ ] **42.1.** Dağıtımdan ÖNCE sunucu .env'de COMPANY_API_KEY (≥24), gerekiyorsa CORS_ORIGINS, (opsiyonel) NODE_ENV=production tanımla → pm2 logs başlangıçta [ENV] UYARI satırlarında bunlar kalmaz; "[CORS] Izinli origin sayisi" görünür.
- [ ] **42.2.** Mevcut 20 karakterlik JWT_SECRET ile `pm2 restart kapi-api --update-env` → sunucu açılır; logda yalnız "[ENV] UYARI: JWT_SECRET 20 karakter..." (değer görünmez); /health OK.
- [ ] **42.3.** Planlı pencerede JWT_SECRET'ı ≥32 karaktere çıkar (tüm oturumlar düşer, kullanıcılara duyur) ve JWT_EXPIRES_IN'i 30d yap → yeni girişlerde token exp-iat=30 gün.
- [ ] **42.4.** JWT_SECRET boş veya change_this_secret iken servis başlat → exit 1, "[ENV] HATA: JWT_SECRET...", DB'ye bağlanılmaz.
- [ ] **42.5.** Yanlış parolayla art arda 5 giriş → 5. denemede 429 LOGIN_LOCKED + Retry-After ~900; kilitte doğru parola da 429; başka hesap normal girer; 15 dk sonra açılır.
- [ ] **42.6.** Profilde parolayı mevcut parola OLMADAN değiştirmeyi dene → 400 CURRENT_PASSWORD_REQUIRED; doğru mevcut parola ile → 200, yanıtta yeni token, uygulama oturumu düşmeden devam eder.
- [ ] **42.7.** Parola değiştirdikten sonra başka cihazdaki eski oturumla istek → 401 TOKEN_REVOKED, uygulama giriş ekranına döner; güncelleme öncesi (pv'siz) eski token'lar süresi dolana dek çalışır.
- [ ] **42.8.** Kayıtlı ve kayıtsız e-postayla "Şifremi unuttum" → ikisinde de aynı başarı mesajı; yalnız kayıtlı aktif hesaba e-posta gelir (migration 025 kolonları canlıda olmalı). Gelen sıfırlama bağlantısı iki kez kullanılamaz.
- [ ] **42.9.** Aynı e-postaya 4+ "şifremi unuttum"/"kodu tekrar gönder" → 429.
- [ ] **42.10.** `curl -i https://api.gudeteknoloji.com.tr/health` → X-Frame-Options: DENY, X-Content-Type-Options: nosniff, Strict-Transport-Security var; izinsiz Origin ile Access-Control-Allow-Origin YOK.
- [ ] **42.11.** Anahtarsız `curl https://api.gudeteknoloji.com.tr/api/company/labeled-devices` → 401; `-H "X-Company-Key: <anahtar>"` ile 200; /qrcodes/<UID>.png aynı şekilde anahtar ister.
- [ ] **42.12.** company_qr_tool COMPANY_API_KEY ile cihaz kaydet/listele/sil → başarılı; denetim logunda company_device_saved/deleted (actor:company_key).
- [ ] **42.13.** Sıfırlama linki, misafir linki (/guest/<tok>) ve katılım token'ı ile istek → pm2 logs satırlarında token yerine *** görünür.
- [ ] **42.14.** Bozuk JSON gövdesi → 400 "Gecersiz JSON govdesi."; sunucu hatasında yanıtta yalnız genel mesaj+errorId, pm2 logs'ta aynı errorId ile ayrıntı.
- [ ] **42.15.** 8080'e dışarıdan doğrudan erişim kapalı (yalnız nginx).

---

## 43. 📧 Üyelik, 6 Haneli E-posta Kodu, Cihaz Sahiplenme, Site Kurulumu ve Daire Yönetimi (S2)

- [ ] **43.1.** Yeni e-postayla kayıt → 6 haneli kod gelir; kayıt yanıtı code_length:6; 6 hane girince doğrulama başarılı, giriş yapılır.
- [ ] **43.2.** Yanlış kodu 5 kez gir → 429 "Çok fazla hatalı deneme"; yeni kod isteyip toplam 10 yanlış denemeye ulaşınca → 429 "30 dakika sonra tekrar deneyiniz".
- [ ] **43.3.** Kodu 10 dk sonra gir → 404 "Aktif bir doğrulama kodu bulunamadı"; yeni kod istendikten sonra eski kodla doğrulama → reddedilir.
- [ ] **43.4.** "Kodu tekrar gönder"e 30 sn içinde iki kez bas → aynı başarı mesajı ama ikinci e-posta gitmez; kayıtsız/doğrulanmış e-postada da aynı mesaj.
- [ ] **43.5.** Cihaz sahiplen (kutu QR) → yanıtta role: site_manager; aynı cihazı ikinci hesapla okut → 409; my-devices çağrısı rolü değiştirmez.
- [ ] **43.6.** Site kur: 101 blok / toplam 5001 daire / 101 kapı → 400; aynı blok adı iki kez → 400 "benzersiz olmalı"; normal kurulum 201.
- [ ] **43.7.** Daire sakinini pasifleştir → yalnız o dairedeki üyelik pasif, kişinin hesabı (giriş) etkilenmez; dairede kayıtlı olmayan kullanıcıya istek → 404.
- [ ] **43.8.** Sakini daireden çıkar/sil veya kapı iznini kaldır → cihaza yeni local_control_token MQTT ile gider; eski token ile yerel açma reddedilir; uygulama yeni token ile yerel/bulut açabilir.
- [ ] **43.9.** Daire yöneticisi "sakini kalıcı sil" → 403; site yöneticisi aynı işlemi yapınca 200.
- [ ] **43.10.** Pasif/çıkarılmış üyeyi "aile reisi yap" → 409.
- [ ] **43.11.** Toplu kapı yetkisinde başka siteye ait blok/daire id'si → "Seçilen alanda aktif sakin bulunamadı" (0 kişi).
- [ ] **43.12.** Sunucuyu yeniden başlat → loglarda ensureDbSchema hatası yok; veriler aynen; users.password_reset_token_hash, users.updated_at, idx_users_email_lower oluşmuş; şifremi unuttum çalışır.
- [ ] **43.13.** Günlük bakım koştuktan sonra kullanıcı sayısı değişmez.
- [ ] **43.14.** (M2 sonrası) Profil/daire "şifre değiştir" ekranı current_password ile çalışır.

---

## 44. 🔧 Cihaz Servisi, Firmware/OTA Sunucu Tarafı, MQTT ACL ve Kapı Günlükleri (S3)

- [ ] **44.1.** Çevrimdışı log: cihaz Wi-Fi/MQTT yokken 3 kapı açılışı yap, bağlantıyı geri ver → 3 kayıt kapı loglarında görünür; aynı batch tekrar yayınlansa çift kayıt oluşmaz.
- [ ] **44.2.** `node scripts/sync_mqtt_acl.js --dry-run` → api_bridge'de `topic read device/+/logs`, her cihaz bloğunda `topic write device/<UID>/logs`; geçersiz UID'li kayıt UYARI ile atlanır.
- [ ] **44.3.** ACL senkronu + broker reload sonrası cihaz device/<uid>/logs yayınlayabiliyor (mosquitto logunda ACL denied yok).
- [ ] **44.4.** Süper kullanıcı panelinden cihaz ekle → yanıtta mqtt_sync.ok:true (sudoers sarmalayıcı root olarak çalışıyor); kapi-mqtt-sync.sh root-sahipli kopyadan, LF satır sonlu.
- [ ] **44.5.** POST /device/sync-logs Authorization'sız → 401; yetkisiz kullanıcı → 403; yetkili → 200 {synced_count,duplicate_count,rejected_count}.
- [ ] **44.6.** Admin panelde cihaz düzenle (kapı adı/site/kullanıcı ataması) → kayıt başarılı (eskiden SQL hatasıydı).
- [ ] **44.7.** OTA: GET /firmware/esp32-wroom/manifest.json?uid=<UID>&current_version=<eski> → update_available:true, anahtarlar aynı, target:"esp32-wroom"; C3 için esp32-c3.
- [ ] **44.8.** DB'de hardware_type'ı esp32_c3 olan cihazla wroom manifesti iste → 403 FIRMWARE_TARGET_MISMATCH; admin PATCH /admin/devices/:id {hardware_type:"esp32_wroom"} ile düzeltince OTA çalışır.
- [ ] **44.9.** Kayıtsız (rastgele) UID ile manifest iste → 200; device_runtime_status'ta yeni satır OLUŞMAZ.
- [ ] **44.10.** Süper kullanıcı site silme e-posta kodu: 5 hatalı kod → 429 + Retry-After.
- [ ] **44.11.** /admin/sites/:id/features: uzaktan açma açıkken yalnız QR'ı kapat → başarılı; ikisini birden kapat → 400.
- [ ] **44.12.** MQTT api_bridge parolasını döndür ve server/.env MQTT_PASSWORD'ü güncelle; scripts/trigger_ota.js <UID> env ile çalışıyor.

---

## 45. 🚪 Kapı Açma Politikası, Geofence, Dinamik QR ve MQTT Köprüsü (S4a)

- [ ] **45.1.** WROOM ekranlı kapıda uygulamadan ekran karekodunu okut → kapı açılır; AYNI karekodu tekrar okut → "bu karekod daha önce kullanıldı" (403 SCREEN_QR_ALREADY_USED).
- [ ] **45.2.** Sunucuyu yeniden başlat; ekran yeni token yayınlayana kadar karekod okut → 409 EKRAN_QR_BEKLENIYOR, kapı AÇILMAZ; birkaç sn sonra tekrar → açılır.
- [ ] **45.3.** C3 (ekransız) kapıda, site koordinatı tanımlıyken uygulamayla statik karekod okut: kapıdayken → açılır; >100 m uzakta → GEOFENCE_OUT_OF_RANGE; konum izni kapalı → istek gönderilmez / GEOFENCE_LOCATION_REQUIRED.
- [ ] **45.4.** Site politikasında "uygulamadan uzaktan açma"yı kapat (süper kullanıcı) → uygulamadan Aç → 403 REMOTE_OPEN_DISABLED; kapıdaki karekod okuyucu ve karekod okutma çalışmaya devam eder.
- [ ] **45.5.** "Karekod girişi aktif"i kapat → karekod üretimi ve okuyucuda geçiş QR_ENTRY_INACTIVE ile reddedilir; tekrar aç → çalışır.
- [ ] **45.6.** Karekod üretildikten sonra (okutmadan) kullanıcının daire/kapı yetkisini kaldır, sonra okuyucuya okut → reddedilir (ACCESS_REVOKED), kapı açılmaz.
- [ ] **45.7.** MQTT'ye engel koy (veya cihazı çevrimdışı yap), karekodu okut → kapı açılmaz, karekod geçerlilik süresi içinde tekrar okutulabilir, geçiş logunda "açıldı" kaydı YOK, "Komutu Gönderilemedi" kaydı var.
- [ ] **45.8.** Geofence zorunlu sitede sahte konum (mock) ile Aç → 403 GEOFENCE_MOCK_LOCATION; konum 60 sn'den eski → GEOFENCE_LOCATION_STALE.
- [ ] **45.9.** Cihaz çevrimdışıyken kapıyı birkaç kez aç, Wi-Fi'yi geri getir → kayıtlar görünür; sunucu loglarında "[MQTT Logs] ... eklenen=N"; cihaz batch'i yalnız logs_ack sonrası siler; aynı batch tekrar gelirse çift kayıt oluşmaz.
- [ ] **45.10.** Henüz siteye atanmamış cihazın offline logları: ack yok → cihaz saklar; cihaz kapıya atanınca loglar gelir.
- [ ] **45.11.** Pulse yükünde request_id (hex string) ve requested_at (epoch sn) var; firmware requested_at 60 sn'den eskiyse (saat senkronsa) pulse'u reddeder.
- [ ] **45.12.** qr_verify'a request_id (tamsayı) konur → qr_result aynı request_id ile döner; eşleşmeyen sonuç firmware'de yok sayılır.
- [ ] **45.13.** Broker'da device/<uid>/screen_qr retained mesajı bırak (test) → sunucu bunu görmez; cihaz retain=false yayınlar.

---

## 46. 🏢 Site, Yönetici Davetleri, Güvenlik Politikası ve Misafir Geçişi (S4b)

- [ ] **46.1.** Site yöneticisi hesabıyla Güvenlik Politikası penceresinde yalnız konum doğrulaması/yarıçap/QR giriş durumunu kaydet → 200, değişiklik görünür, 403 yok; giriş yöntemi anahtarları (uzaktan/QR/misafir) yöneticiye kapalı kalır.
- [ ] **46.2.** Site yöneticisi politika isteğinde require_geofence=true gönderip koordinat vermeden kaydet → 400 "enlem/boylam zorunlu".
- [ ] **46.3.** Süper kullanıcı ile qr_entry_active açıkken yalnız yarıçapı değiştir → QR giriş durumu değişmez.
- [ ] **46.4.** Tek kullanımlık misafir linki oluştur, tarayıcıda aç, "KAPIYI AÇ" → bir kez açılır; ikinci basışta "Kullanım limiti dolmuş". İki telefonla aynı anda basınca yalnız biri açar.
- [ ] **46.5.** Cihazı çevrimdışı yapıp aynı linke bas → "Kapı cihazı şu anda bağlı değil" (503); cihaz dönünce aynı link çalışır (hak harcanmamış).
- [ ] **46.6.** Linki oluşturan kullanıcının daire üyeliğini kaldır/hesabı pasifleştir → linke basınca 403, kapı açılmaz.
- [ ] **46.7.** Site misafir geçişi kapalıyken linke bas → 403 ve ilgili mesaj.
- [ ] **46.8.** Başlığa <b>x</b> yazıp link oluştur, sayfayı aç → başlık düz metin görünür.
- [ ] **46.9.** Site yöneticisi davet ekranında kayıtlı ve kayıtsız e-posta gir → iki durumda da aynı mesaj; geçersiz e-posta → hata.
- [ ] **46.10.** Sitenin tek yöneticisini çıkarmayı dene → "Son yönetici çıkarılamaz"; iki yöneticiden birini çıkar → başarılı; çıkarılanın başka sitesi yoksa rolü individual/apartment_owner'a döner, varsa site_manager kalır.
- [ ] **46.11.** Süper kullanıcı e-posta kodu ile site silme: yanlış kodu 5 kez gir → kilit (429) ve kod iptal; yeni kodla doğru silme çalışır; silinen sitenin cihazının eski local token'ıyla yerel açma reddedilir.
- [ ] **46.12.** replace-device ile başkasının cihazını seç → 403/409 ile reddedilir.

---

## 47. 🛠️ Operasyon — Dağıtım, Migration, CI ve Şirket Aracı (D1)

- [ ] **47.1.** VPS: depo kökündeki .env'e POSTGRES_PASSWORD ekle (chmod 600), `docker-compose config` hatasız; değişken yokken "POSTGRES_PASSWORD zorunlu" hatası.
- [ ] **47.2.** VPS: server/.env DB_HOST=127.0.0.1 doğrula; compose yeniden oluşturulursa `docker ps` PORTS 127.0.0.1:5432->5432; healthcheck healthy; /health bağlı. (Mevcut DB parolası değişmez.)
- [ ] **47.3.** Dışarıdan 5432 kapalı (zaten doğrulandı 2026-10-01).
- [ ] **47.4.** Yerelde `cd server && npm ci && npm run lint && npm test` → lint 0 hata, testler geçer.
- [ ] **47.5.** VPS (isteğe bağlı): `pm2 delete kapi-api && pm2 start ecosystem.config.cjs && pm2 save` → online; loglar hatasız; /health OK.
- [ ] **47.6.** VPS: `node scripts/migrate.js --status` (salt okunur) → schema_migrations yok + 25 bekleyen; `--apply` baseline'sız REDDEDİLİR (exit 3); şema 001-024 ile uyumlu doğrulanınca `--baseline 24`, `--apply --dry-run` yalnız 025, `--apply` → 025 uygulanır.
- [ ] **47.7.** company_qr_tool: .env'de sunucudakiyle aynı COMPANY_API_KEY → "Cihazı Sunucuya Kaydet" başarılı; anahtar yoksa uyarı ve istek yok; yanlış anahtar → "HTTP 401 reddetti"; known_hosts yokken ilk kurulum diyaloğu; SSH_KEY_FILE ile parola sorulmaz.
- [ ] **47.8.** GitHub: PR'da Actions "Server", "Flutter", "Secret scan" çalışır (gitleaks geçmişteki parola yüzünden kırmızı çıkabilir → parolayı döndür).
- [ ] **47.9.** Temiz klonda `git ls-files --eol server/scripts/kapi-mqtt-sync.sh` → w/lf.
- [ ] **47.10.** `git status`'ta server/data/ ve server/public/qrcodes/ görünmez.

---

## 48. 🧪 Sözleşme Denetimi Düzeltmeleri — Sunucu: Cihaz Tipi, Şirket Uçları, Kapı/Site/Üyelik/Parola (SX1, SX2)

- [ ] **48.1.** Şirket aracıyla chip'i 'ESP32-WROOM' okunan kartı kaydet → /admin/devices'ta kart WROOM görünür (rozet + Model: ESP32-WROOM), cihaz OTA manifest isteğinde 403 almaz.
- [ ] **48.2.** DB'de hardware_type yanlış (WROOM kart esp32_c3 kayıtlı) bir cihazı MQTT'ye bağla → PM2 logunda "Cihaz donanim tipi cihaz bildirimine gore duzeltildi: <UID> esp32_c3 -> esp32_wroom"; /admin/devices'ta tip düzelir, OTA manifest 200.
- [ ] **48.3.** PATCH /admin/devices/:id yalnızca {"hardware_type":"esp32_wroom"} → site/kullanıcı/kapı adı atamaları KORUNUR, yanıtta device.hardware_type "esp32_wroom", yerel kontrol anahtarı dönmez.
- [ ] **48.4.** Şirket aracından cihaz sil → araç başarılı der, /admin/devices'ta cihaz yok, yanıtta mqtt_sync özeti var; MQTT_SYNC_COMMAND tanımlıysa broker passwd/acl'den cihaz çıkar.
- [ ] **48.5.** DB geçici kapalıyken şirket aracında 'Cihazı Sunucuya Kaydet' → araç hata gösterir ("başarıyla kaydedildi" denmez); DB gelince aynı UID ile tekrar kayıt çalışır.
- [ ] **48.6.** Süper kullanıcı kendi satırında parola yazıp kaydeder (veya PATCH /admin/users/<kendi kodu> {password}) → 400 "Kendi şifrenizi Profilim ekranından..." (USE_PROFILE_PASSWORD_CHANGE); Profilim'den mevcut şifreyle değiştirme çalışır.
- [ ] **48.7.** GET /health → mqtt içinde ham hata metni yok, yalnızca has_error ve kısa last_error kodu.
- [ ] **48.8.** 50'den fazla siteli süper kullanıcıda kapı kontrolü site seçicisi tüm siteleri listeler.
- [ ] **48.9.** Veritabanı Bakım penceresi: daire sakini (@ahbu.local, daireye bağlı) hesapları 'Kukla' sayılmaz; 'Çöp Temizliği Yap' sonrası süresi dolmuş kayıt kalmadıysa 'Veritabanı temiz' görünür.
- [ ] **48.10.** Offline kapı logu: DB bağlantısı kısa süre kesilip geri geldikten sonra (PM2 restart OLMADAN) cihazın bekleyen logları sunucuya yazılır ve ack gider.
- [ ] **48.11.** Süper kullanıcı → Siteler → "Giriş & Güvenlik Politikaları" → misafir geçişi / yarıçap / QR süresi değiştirip Kaydet → "Route bulunamadı" çıkmaz, ayarlar kaydedilir; site yöneticisi giriş yöntemi bayrağını değiştirmeye çalışırsa yine 403.
- [ ] **48.12.** Site yöneticisi → kapı kartı → "Arızalı Cihazı Değiştir" → şirket envanterindeki sahipsiz yeni cihazın kutu QR'ı → cihaz değişir (500 yok). Kendi önceden sahiplendiği cihaz 409 vermez; başka hesabın cihazı 409 "başka hesap sahiplenmiş".
- [ ] **48.13.** Daire sakini change-password ucu (API): 5 yanlış mevcut parola → 5. denemede 429 CURRENT_PASSWORD_LOCKED (Retry-After ≈ 900 sn); Profilim'deki parola değişimi de aynı kilide takılır, kilitliyken doğru parola da reddedilir.
- [ ] **48.14.** Yönetici → Kapı Yetkileri: sakin Ali'ye CUSTOM kapı için ek izin ver → Ali'yi "Hesabı Pasife Al" → Ali o kapıyı listede görmez/açamaz (uzaktan, QR, misafir); "Aktif Et" → izin geri gelir.
- [ ] **48.15.** Aile reisini (ilk onaylanan sakin) pasife al → daire ağaçta kalır, diğer aile üyeleri erişimini korur, aile reisi göstergesi diğer aktif üyeye geçer; reisi tekrar aktif et → erişimi geri gelir.
- [ ] **48.16.** Süper kullanıcı bir sakinin hesabını pasife aldıktan sonra yönetici ağaçta o üyeyi "Aktif Et" yapar → "hesap sistem yöneticisi tarafından pasife alınmış" uyarısı görünür (normal başarı mesajı değil).
- [ ] **48.17.** Daireler → sakini olan daire → Düzenle (şifre alanı yok) → ad/telefon/aktiflik değiştirip Kaydet → 400 vermez, kaydedilir. Boş dairede 4 haneli şifre girmeden sakin eklemek 400 "Sifre 4 haneli sayisal olmali."
- [ ] **48.18.** Üyelik sistemiyle gelen (e-postalı) sakinin dairesini bu diyalogla düzenle → sakinin e-postası ve giriş adı değişmez, giriş yapabilmeye devam eder.
- [ ] **48.19.** Cihaz sahiplenmemiş bireysel hesapla POST /membership/setup-site (API) → 400 "önce bir cihaz sahiplenmelisiniz", site oluşmaz; başkasının cihaz UID'siyle → 404; kutu QR'ını sahiplenip kurulum → başarılı; 10 dk'da 10'dan fazla istek → 429.
- [ ] **48.20.** Mevcut site yöneticisi "Site Ekle" (cihaz seçmeden) → site yine kurulabilir (cihazsız kurulum korundu).
- [ ] **48.21.** 5 yanlış girişle kilitlenen hesap → "Şifremi unuttum" → yeni şifre belirle → hemen giriş 200 (15 dk beklemez).
- [ ] **48.22.** Profilim → mevcut şifrenin sonuna boşluk ekleyerek şifre değiştir → kabul edilir (girişle tutarlı).
- [ ] **48.23.** Süper kullanıcı site politikasında "Yerel Ağ (UDP) ile açma"yı kapatır → daha önce token almış telefon aynı Wi-Fi'dan UDP "open" gönderince cihaz reddeder; bayrak tekrar açılınca /status yeni token verir.
- [ ] **48.24.** Yeni kurulan sitede konum yarıçapı varsayılanı 100 m; mevcut sitelerin yarıçapı değişmemiş.
- [ ] **48.25.** Misafir geçişi kapalı sitede süper kullanıcı "Kurye/Misafir Geçişi Oluştur" → 403 GUEST_DISABLED, link üretilmez.
- [ ] **48.26.** Site yöneticisi → cihaz düzenleme → kapı etiketi boş bırakıp Kaydet → 400 vermez.
- [ ] **48.27.** Süper kullanıcı cihaz siler (DELETE /manager/devices/:id) → 204; broker ACL senkronu çalışır, senkron hatasında 503 + mesaj.
- [ ] **48.28.** Başka sitenin yöneticisiyle katılım talebini onayla/reddet (API) → talep durumu ne olursa olsun 403 (409 "zaten APPROVED" sızmaz).

---

## 49. 🤖 Android — Widget, Derin Bağlantı, Sesli Komut ve Yerel Kontrol (M1)

- [ ] **49.1.** Android ana ekrana widget ekle, "KAPIYI AÇ"a dokun → "Açılıyor... ⏳" → "Açıldı! ✅" → ~3 sn sonra "Çevrimiçi / Hazır"; kapı açılır; ◀ ▶ kapı değiştirir (receiver exported=false sonrası çalışmalı).
- [ ] **49.2.** Widget'a 1 sn içinde 2-3 kez dokun → sunucuda tek açma komutu/log.
- [ ] **49.3.** Uçak modunda widget'a dokun → "Bağlantı hatası ❌"; widget kalıcı çevrimdışına dönmez, ağ gelince tekrar açılır.
- [ ] **49.4.** Cihaz çevrimdışıyken widget'a dokun → "Kapı çevrimdışı ❌"; düğme "ÇEVRİMDIŞI - DENE" ve tıklanabilir.
- [ ] **49.5.** Uygulamadan çıkış → widget "Kapı Tanımlı Değil / Giriş Yapın"; `adb shell run-as <paket> cat shared_prefs/HomeWidgetPreferences.xml` içinde auth_token, api_base_url, door_* YOK.
- [ ] **49.6.** `adb shell am broadcast -a es.antonborri.home_widget.action.BACKGROUND -d sitekapi://open_door_action -n <paket>/es.antonborri.home_widget.HomeWidgetBackgroundReceiver` → erişim reddedilir (exported değil), kapı açılmaz.
- [ ] **49.7.** `adb shell am start -a android.intent.action.VIEW -d "sitekapi://open?doorIndex=1" <paket>` → "Kapı açılsın mı?" diyaloğu; "Vazgeç" açmaz; "Kapıyı Aç" açar; soğuk başlangıçta diyalog TEK kez.
- [ ] **49.8.** Çok siteli hesapta aynı doorIndex iki sitede varsa aynı link "Hangi kapı açılsın?" listesi; seçince o kapı açılır; siteCode=<kod> ile liste çıkmadan o siteye gider.
- [ ] **49.9.** Uygulama ikonuna uzun bas → kapı kısayolu → önce onay penceresi.
- [ ] **49.10.** Sesli: "kapıyı kapat"/"kapıyı açma" → açmaz ve uyarır; çok kapılı hesapta "kapıyı aç" → "Hangi kapıyı açmamı istersiniz?"; "1. kapıyı aç"/"otopark kapısını aç" → o kapı açılır.
- [ ] **49.11.** Çıkış yapıp başka hesapla gir, sesli komut → önceki hesabın kapıları kullanılmaz.
- [ ] **49.12.** Release APK: `aapt dump badging`/`apkanalyzer manifest print` → allowBackup=false, usesCleartextTraffic=false, receiver/service exported=false; debug APK'da usesCleartextTraffic=true; iki build de manifest birleştirme hatasız.
- [ ] **49.13.** Cihaz local_control_config token'ını almamışken uygulama yerel açmayı denemez, doğrudan buluta düşer; token varsa ve cihaz LAN'daysa yerel UDP açar.

---

## 50. 📱 Flutter İstemci — Oturum, Hata Eşlemeleri, Geofence ve Arayüz (M2, FX1, FX2)

- [ ] **50.1.** Eski sürümden güncelle (oturum açık) → açılışta oturum korunur; eski SharedPreferences oturum kaydı silinir.
- [ ] **50.2.** Hesabı sunucudan pasif yap, uygulamayı arka plandan öne getir → oturum kapanır, giriş ekranında "Hesap aktif degil" bildirimi.
- [ ] **50.3.** Başka cihazdan şifre değiştir → bu cihazdaki ilk istekte oturum kapanır ve "Şifreniz değiştirildiği için oturumunuz sonlandırıldı" görünür.
- [ ] **50.4.** Profilde Mevcut Şifre olmadan yeni şifre → kayıt engellenir; yanlış mevcut şifre → "Mevcut şifreniz hatalı", oturum açık kalır; doğru girince şifre değişir, oturum açık kalır, widget çalışır.
- [ ] **50.5.** Giriş ekranında 5+ hatalı şifre → "Çok fazla hatalı deneme yapıldı. N dakika sonra tekrar deneyin." (SnackBar, taşma yok).
- [ ] **50.6.** Konum zorunlu sitede (GPS kapalı) "Kapıyı Aç" → istek gitmez, "Konum servisleri kapalı"; GPS açıkken kapı açılır; kapıdan uzakta → "X m uzaktasınız, izin verilen Y m".
- [ ] **50.7.** Mock location uygulamasıyla konum zorunlu kapıyı aç → "Sahte konum tespit edildi" ile reddedilir.
- [ ] **50.8.** Ekransız (C3) kapıda statik karekodla açma → konum istenir ve gönderilir (site geofence kapalı olsa bile).
- [ ] **50.9.** Site güvenlik politikası: konum doğrulamasını aç, koordinatı boş bırak → kayıt engellenir, alan altında hata; "Mevcut Konumu Al" çalışır; 320 px genişlikte taşma yok.
- [ ] **50.10.** Yönetici panelinde hızlı site değiştir (A→B) → ekranda daima son seçilen sitenin kapıları kalır.
- [ ] **50.11.** Panelde kapı seçince masaüstü widget'ının aktif kapısı da değişir; kapı listesi boşalınca widget temizlenir; çıkışta widget'ta token kalmaz.
- [ ] **50.12.** Uygulama arka plandan öne gelince /me çağrılır (rol/hesap durumu güncellenir); kapı durumu yoklaması yavaş ağda üst üste binmez.
- [ ] **50.13.** Doğrulama kodu ekranı: 6 haneli kod girilir; 4 haneli kod reddedilir.
- [ ] **50.14.** Haftalık log PDF'i 200'den fazla kayıtlı sitede tüm kayıtları içerir (sayfalı çekim).
- [ ] **50.15.** Kapı açma sırasında ağ kopsa → komut ikinci kez gönderilmez (çift açma yok); 10 sn içinde yanıt yoksa "Kapı açılmış olabilir" mesajı.
- [ ] **50.16.** Yeni bireysel hesap oluştur, 6 haneli kodu gir → ana sayfa açılır; sonra Çıkış Yap (veya başka cihazdan şifre değiştir) → uygulamayı yeniden başlatmadan giriş ekranına dönülür.
- [ ] **50.17.** Doğrulama ekranında "Kodu Tekrar Gönder" ilk 30 sn pasif ve "(NN sn)" geri sayımı gösterir; süre dolunca basınca yeni kod e-postası gelir ve geri sayım yeniden başlar (320 px'te taşma yok).
- [ ] **50.18.** Başka cihazdan şifresi değişmiş hesapta Profilim'de adı değiştirip Kaydet → oturum kapanır, giriş ekranında "Şifreniz değiştirildiği için..." bildirimi görünür.
- [ ] **50.19.** Profilim'de yanlış mevcut şifre ile şifre değiştir → "Mevcut şifreniz hatalı..." mesajı, oturum açık kalır.
- [ ] **50.20.** Kapı seçili ana ekranda Profilim'den şifre değiştir → giriş ekranına atılmaz, "Profil güncellendi" görünür ve yeni şifreyle oturum sürer.
- [ ] **50.21.** HTML 403/401 dönen proxy/WAF'lı ağda (kurum/okul ağı) uygulama açıkken çıkış yapılmaz, "Sunucuya ulaşılamadı. Ağ bağlantınızı (güvenlik duvarı/proxy)..." görünür.
- [ ] **50.22.** Site silerken sunucu boş/5xx yanıt dönerse "Site silindi." görünmez, hata mesajı çıkar; başarılı silmede liste yenilenir.
- [ ] **50.23.** Süper kullanıcı: kullanıcı düzenleme penceresinde "E-Posta Doğrulandı" anahtarını değiştirip Kaydet → listede rozet güncellenir, kullanıcı giriş yapabilir.
- [ ] **50.24.** Süper kullanıcı kendi satırını düzenlerken şifre alanı yok, "Profilim ekranından değiştirin" notu görünür; yeni kullanıcı eklerken şifre alanı var.
- [ ] **50.25.** Süper kullanıcı: sitede uzaktan açma kapalıyken uygulamadan kapıyı açabilir (sunucu izin verir).
- [ ] **50.26.** Site konum doğrulaması açılmış, uygulamadaki kapı kaydı eski iken "Kapıya QR Göster" → konum alınır ve QR açılır; "Tekrar Dene" aynı hatayı vermez.
- [ ] **50.27.** Yerel ağ kapalı/yerel token'ı olmayan kullanıcıda cihaz beacon'u görünse bile "Yerel Ağda Aktif" yazmaz (Çevrimdışı görünür); token varken yazar.
- [ ] **50.28.** Bulut zaman aşımı/5xx iken cihaz yerel ağda erişilebilir ve yerel token varsa kapı durumu hata şeridi gizlenir; sunucu 403/404 iş hatalarında şerit görünür.
- [ ] **50.29.** Bireysel (yönetici olmayan) hesapla uygulamayı açınca sunucu loglarında GET /manager/sites 403 oluşmaz; yönetici/süper kullanıcıda site listesi normal yüklenir.
- [ ] **50.30.** Yönetici, kapı kartı → Yetkiler → blok başlığında doğru "X/Y Yetkili", daire başlığı "Daire N" (çift önek yok), rol "Daire Admini/Aile Üyesi", yetkili sakinin anahtarı açık; dokununca durum tersine döner ve liste yenilenir.
- [ ] **50.31.** Süper kullanıcı, listeden onaylı site → Düzenle → "Mevcut daire sayıları okunuyor..." sonra gerçek blok sayıları (ör. 24/30) görünür; yalnız adı değiştirip Güncelle → daire ve sakin üyelikleri değişmez; ağ kesikken Güncelle kapalı, "Tekrar Dene" çıkar.
- [ ] **50.32.** Süper kullanıcı → Şirket Cihazları: WROOM kartında rozet/Model "ESP32-WROOM"; kayıtlı tür ile cihaz bildirimi çelişirse "Kayıtlı Tür: ... (cihaz bildirimiyle uyuşmuyor)" çipi; sahipli ama kapısız cihazda "Depoya Al" görünür.
- [ ] **50.33.** Sakin, "Kapı Ekranından QR Oku" başarılı → tek "açıldı" mesajı; geçiş logunda tek satır (screen_qr), ikinci "Kapı açma komutu gönderildi" yok.
- [ ] **50.34.** Kapı geçiş günlüğü ve PDF: yerel UDP, ekran yönetici PIN'i, seri port geçişleri doğru etiketli; PDF özet kutularının toplamı toplam geçişe eşit.
- [ ] **50.35.** Sakin QR penceresi açıkken yönetici karekod girişini kapatır veya yetki alır, okuyucuya okutulur → modalda "Kapı Yetkisi Yok / Karekod Girişi Kapalı" mesajı, yoklama durur; okuyucu komutu iletemezse "tekrar gösterin" uyarısı birkaç sn görünür.
- [ ] **50.36.** Bireysel kullanıcı: cihaz kapalıyken uygulama açılır, cihaz bağlanır → ~15 sn içinde kapı "Çevrimiçi" olur; "Çevrimdışı" görünen kapıda düğmeye basınca liste tazelenir, cihaz çevrimiçiyse komut gider.
- [ ] **50.37.** Site kurulum sihirbazı: A, B, C ekle → B'yi sil → Blok Ekle → "D Blok" gelir; aynı adı elle yazarsan "Blok adı benzersiz olmalı." uyarısı çıkar.
- [ ] **50.38.** Güvenlik politikası: yarıçapı 500 m olan sitede pencere "500 metre" gösterir, kaydırıcıya dokunmadan kaydedince 500 kalır; QR süresi 45 sn olan sitede seçici "45 saniye" gösterir ve değer korunur.
- [ ] **50.39.** Site yöneticisi → Cihaz düzenleme: Kapı Etiketi boş + Kaydet → başarılı; 1 karakter → "en az 2 karakter".
- [ ] **50.40.** Sitede misafir geçişi kapalıyken yönetici kapı kartında "Kurye / Misafir Geçişi Oluştur" düğmesi görünmez.
- [ ] **50.41.** Misafir geçiş linki penceresinde "Paylaş" sistem paylaşım sayfasını açar.
- [ ] **50.42.** Site → Sakinler: sistem yöneticisinin hesabını pasife aldığı sakinde "Hesap pasif (sistem yöneticisi)" rozeti çıkar, menüde işlem yerine bilgi satırı olur; diğer sakinlerde menü/onay metinleri "Üyeliği Aktif Et/Pasife Al" (üyelik/kapı erişimi) der.
- [ ] **50.43.** Cihaz sürüm raporu PDF: C3 ve WROOM için ayrı en yüksek sürüm "güncel" sayılır.

---

## 51. 🔌 Firmware — ESP32-C3, ESP32-WROOM ve Ekran Yazılımı (F1, F2A1, F2A2, F2B)

- [ ] **51.1.** WROOM'u USB ile yükle, saat senkron olduktan sonra seri izle → "MQTT baglaniyor ... baglandi"; sunucuda cihaz çevrimiçi. Doğrulama hatasında "Hata rc=-2 tls=..." çıkar (CA/zaman kontrolü).
- [ ] **51.2.** Wi-Fi'siz/saatsiz açılışta → TLS denenmez, NTP gelince bağlanır.
- [ ] **51.3.** Açılışta röle tıklamaz (self-test kaldırıldı); cihaz resetlenince röle pasif.
- [ ] **51.4.** Uygulamadan/MQTT'den pulse → röle ~1,5 sn çeker ve bırakır; bu sürede MQTT/OTA/Wi-Fi bloklanmış olsa bile kapanır (pulse sırasında Wi-Fi kes) ve gDoorLocked yine kilitlenir.
- [ ] **51.5.** Aynı request_id ile pulse'ı iki kez yayınla (mosquitto_pub) → ikincisi yok sayılır; requested_at'i 2 dk geçmiş sayı ver → röle çekmez, pulse_rejected olayı; requested_at'siz pulse → kabul.
- [ ] **51.6.** Düz metin pulse/on yayını → röle ÇEKMEZ.
- [ ] **51.7.** Üyelik/izin kaldır → sunucu token'ı döndürür → cihaz yeni token'ı alır, eski token reddedilir.
- [ ] **51.8.** İnternet kesikken yerel açma yap → kayıt /offline_logs.ndjson'a düşer (? ile durum). İnternet gelince device/<uid>/logs batch'i yayınlanır, sunucu logs_ack yollar ve satırlar silinir; ack'i engelle (cihaz atanmamış) → batch silinmez, artan aralıkla tekrar yayınlanır. ACL: cihaza write device/<uid>/logs, api_bridge'e read device/+/logs (sync_mqtt_acl.js çalıştırılmış olmalı).
- [ ] **51.9.** Çevrimdışıyken saat gelmeden açılan kayıtlar (epoch=0) saat gelince doğru zamanla gelir.
- [ ] **51.10.** Ekran: PIN tanımsız iken AYAR → "PIN tanimli degil / Yonetici menusu kilitli". mosquitto_pub ile {"action":"admin_pin_config","admin_pin":"123456"} (veya seri ADMINPIN:123456) → PIN tanımlanır.
- [ ] **51.11.** Doğru PIN → menü açılır, "Oturum: NN sn" geri sayar ve 20. sn'de dokunmasan da ana ekrana döner; dokunmaya devam etsen de 20 sn'de kapanır.
- [ ] **51.12.** Yanlış PIN → "Hatali PIN (kalan: n)"; 5 yanlış → "Kilitli: 300 sn" geri sayım; kilitliyken doğru PIN de reddedilir; cihazı resetle → kilit yine ~5 dk; kilit bitince 1 deneme hakkı.
- [ ] **51.13.** "KAPIYI AC → AC" → röle çeker, ekran "KAPI ACILDI"; PIN ekran RAM'inde tutulmaz.
- [ ] **51.14.** "Cihaz Bilgisi" → gerçek UID, sürüm (5.2.0) ve hedef (esp32-wroom); "Ekran FW: 1.1.1"; kamera gerçek durum; MQTT kopunca "Bulut YOK".
- [ ] **51.15.** Seride PIN/QR token/local token/MQTT parolası görünmez ([GM60] QR okundu, uzunluk: N; ADMIN_AUTH|***).
- [ ] **51.16.** QR okut → ekranda gerçek token'lı QR 30 sn'de bir döner; aynı QR'ı hemen okutmak 5 sn debounce'a takılır; sunucuya yayın başarısızsa debounce ilerlemez.
- [ ] **51.17.** Çok uzun (>512 B) QR → reddedilir, ekranda "GECERSIZ QR".
- [ ] **51.18.** OTA: manifest sha256 DOLU olmalı; yeni sürüm → indirme % ilerler, doğrulama sonrası yeniden başlar, ~60 sn sonra ota_validated olayı; aynı/eski sürüm manifest'i → "guncel", indirme yok; yanlış sha256 → ota_failed, boot bölümü değişmez; yeni imaj açılıp bağlanamadan güç döngüsü → eski sürüme geri döner.
- [ ] **51.19.** C3 (sahadaki) cihazda: WiFi/BLE provisioning akışı bozulmadan çalışır (BLE yalnız Wi-Fi yokken/reset sonrası); mqtt.gudeteknoloji.com.tr dışı host reddedilir.
- [ ] **51.20.** Yeni/Wi-Fi'siz WROOM kartta seri araçla h → röle çeker, "Role manuel GPIO 16 = HIGH" ve "60 sn sonra OTOMATIK birakilacak" yazar; l göndermesen de ~60. sn'de röle kendiliğinden bırakır ("Role birak okuma GPIO 16 = LOW").
- [ ] **51.21.** h tutarken uygulamadan/MQTT'den pulse dene → reddedilir (pulse_rejected / HTTP 429 role_mesgul); OTA bu sürede başlamaz.
- [ ] **51.22.** l röleyi anında bırakır; r tek pulse verir (2,5 sn içinde ikinci r debounce mesajı); k kamera ışık/bip testini çalıştırır; ? UID/hedef/sürümü döker.
- [ ] **51.23.** p → pinler sırayla yanar; test bitince röle PASİF, seri çıktı "PIN BULMA TESTI BITTI."; GM60 ve (WROOM'da) ekran çalışmaya devam eder; C3'te Wi-Fi reset butonu pini yanlışlıkla "basılı" görünmez.
- [ ] **51.24.** Wi-Fi'si kayıtlı saha cihazında h, l, p → yalnız "Atolye modu kapali (Wi-Fi sifirlayin veya reset butonu 3 sn)" yazar, röle/GPIO değişmez; ?, r, k çalışır. Reset butonu 3 sn basılı tutulunca cihaz provisioning'e girer ve h/l/p açılır.
- [ ] **51.25.** ≥26 gün kesintisiz çalıştır, sonra router'ı 2 dk kapat-aç → Wi-Fi gelince MQTT ≤~60–90 sn'de döner, sunucuda "online" (eski kodda ~25 gün bağlanamazdı).
- [ ] **51.26.** OTA ile yeni imaj yükle; seri "OTA: calisan imaj dogrulanmadi (PENDING_VERIFY)..." görünür. İlk 60 sn içinde ota_check gönder → "OTA kontrol talebi" hemen, "OTA kontrolu basladi" ancak "gecerli olarak isaretlendi" satırından sonra.
- [ ] **51.27.** İndirme ortasında AP'yi kapat → "indirme eksik/hatali" veya "indirme http hata: -1"; NVS `ota_cfg/try_cnt` artmaz, 4+ ağ hatasında "deneme siniri asildi" çıkmaz, tekrar aralıkları katlanır. Manifest sha256'yı bozdurunca 3. denemede "deneme siniri asildi (3)".
- [ ] **51.28.** Panelden 2+ cihaza OTA işi (ota_job_id'li) → her cihazda "OTA kontrol talebi" ile "OTA kontrolu basladi" arası 0–120 sn, cihaza göre farklı; tekil ota_check hemen çalışır.
- [ ] **51.29.** MQTT bağlıyken modem WAN'ını çek (Wi-Fi açık) → "MQTT: broker TCP on-kontrolu basarisiz..." satırları; bu sırada UDP discover / `/ahbu/status` yanıtı <1 sn (her 4. denemede ~15 sn'ye kadar gecikebilir); WAN gelince ≤60 sn'de bağlanır.
- [ ] **51.30.** Gerçek OTA'da (C3) seri "MQTT: OTA indirmesi icin oturum kapatildi."; broker'da retained availability=offline; OTA bitince/yenilenince online; panelde iş "installed" (OTA öncesi/sonrası ESP.getFreeHeap()/getMaxAllocHeap() logu eklemek faydalı).
- [ ] **51.31.** Kendini toparlama (geçici derleme: MQTT_KENDINI_TOPARLA_MS = 2 dk, sonra geri al): broker erişimini kes → ~2 dk sonra "kontrollu yeniden baslatma"; röle pininde (C3 GPIO10 / WROOM GPIO16) osiloskopla tık yok; açılış sonrası bağlanınca `self_recovery_restart` olayı.
- [ ] **51.32.** AP'yi kapat → "WiFi baglantisi yeniden deneniyor" satırları ~6, 12, 24, 48, 60, 60 sn aralıkla; AP'yi aç → ≤60 sn'de bağlanır, sonraki kopma yine 6 sn'den başlar.
- [ ] **51.33.** NVS silinmiş cihazda bir kapı geçişi → client_log_id `<UID>-<çoğunlukla ≥2^20 sayı>-1`; sunucu logunda `eklenen=1 tekrar=0`.
- [ ] **51.34.** C3'e laptop USB bağla, `?` gönder → çıktı eksiksiz; USB'yi çıkar → durum dökümü sırasında bile UDP/HTTP yanıt süresi normal.
- [ ] **51.35.** (Uygulama v2 ile) aynı Wi-Fi'de UDP dinle → ~5 sn'de bir beacon `{"device_uid","ip","port":8765,"rssi","hw","ch":"<16 hex>"}`; `ch` ~10 sn'de bir değişir.
- [ ] **51.36.** Uygulamadan yerel "Kapıyı aç" → röle ~1,5 sn çeker, yanıt ok:true; paket yakalamada (tcpdump/Wireshark) pakette `token` alanı YOK, `ch` ve 64 haneli `sig` var.
- [ ] **51.37.** Yakalanan açma paketini 5+ sn sonra yeniden gönder (replay) → `{"ok":false,"error":"challenge","ch":"<güncel>"}`, röle çekmez; aynı paketi 3 sn içinde yeniden göndermek → `{"ok":true,"duplicate":true}`, röle ikinci kez çekmez.
- [ ] **51.38.** Yanlış imza (ch doğru) → `unauthorized`; sunucu local_control_config göndermemişken açma → `unauthorized` + `local_control_available:false`; eski biçim (`token` alanlı) paket → `challenge` yanıtı, röle çekmez.
- [ ] **51.39.** Röle çekiliyorken ikinci imzalı istek → `role_mesgul`; aynı `ch` ile röle bırakıldıktan sonra yeniden denenebilir (challenge tüketilmemiştir).
- [ ] **51.40.** `POST /ahbu/open` → 404 route_bulunamadi; `GET /ahbu/status` çalışır ve sır içermez.
- [ ] **51.41.** Açılış seri günlüğünde HMAC öz-testi geçti satırı; (bozuk derlemede) `local_control_selftest_failed` olayı ve yerel açma kapalı.
- [ ] **51.42.** `ADMINPIN:123456` / `000000` / `111111` / `654321` / `012345` → reddedilir (seride "weak_pin"; PIN değeri yazılmaz); `ADMINPIN:482915` kabul. MQTT admin_pin_config ile zayıf PIN → reddedilir, `weak_pin` olayı.
- [ ] **51.43.** 5 yanlış PIN → 5 dk kilit; kilit bitince tek deneme hakkı ve ekran tekrar "kilitli" göstermez.
- [ ] **51.44.** Çok-kullanımlı misafir QR'ı ikinci kişi 10 sn sonra okutur → sunucuya gider (8 sn pencere); sunucu reddi/hata sonrası aynı QR yeniden denenebilir.
- [ ] **51.45.** Panelden toplu OTA işi → cihaz olayları `ota_job_id` taşır; sunucuda iş durumu (installed/failed/already_current) doğru görünür.
- [ ] **51.46.** Ekranı flash et, admin menüsü → CİHAZ BİLGİSİ → "Ekran FW: 1.1.1"; USB seri `?` → `...|FW:1.1.1`.
- [ ] **51.47.** USB monitörü bağlayıp kapat/kabloyu çek, 2 dk PIN tuşla/dokun → takılma yok (öncesinde log halkası dolunca her dokunuş ~100 ms takılırdı).
- [ ] **51.48.** USB monitör açıkken ekrana dokun → `[TOUCH] Tap at` satırı YOK (`[TX->WROOM]` satırları var); yalnız `-D AHBU_DEBUG_TOUCH` derlemesinde görünür.
- [ ] **51.49.** Açılışta dokunmatiği devre dışı bırak (konektör gevşek) → log `[TOUCH] CST816D not detected`; bağla → 5 sn içinde `CST816D touch controller initialized` + `TOUCH_READY`, AYAR → PIN ekranı güç döngüsüsüz açılır.
- [ ] **51.50.** Ana kartla 10 dk izle → "WiFi OK / Bulut OK" sabit, QR 30 sn'de bir yenilenir, yanlış alarm yok.
- [ ] **51.51.** WROOM'u reset'te tut veya UART hattını ayır → ~45 sn sonra "WiFi YOK / Bulut YOK", QR yer tutucu, "Kalan Sure: 00 sn"; bağlantıyı geri ver → en geç ~2 sn içinde WiFi/Bulut OK ve yeni QR.
- [ ] **51.52.** Router'ın internetini (WAN) kes, Wi-Fi açık kalsın → ekran "WiFi OK" kalır (yalnız Bulut YOK); "WiFi YOK" titremesi olmaz.

---

## 52. ✨ Arayüz Yenileme ve Akıcılık — Tasarım Sistemi, Performans, Yoklama ve Zaman Aşımları (FAZ5)

- [ ] **52.1.** Açık ve koyu temada her rolle (süper kullanıcı, site yöneticisi, daire sakini, bireysel) tüm menüleri gez: kart alt yazıları, "Detaylar/Gizle", rozetler, hata/uyarı metinleri soluk değil okunur; kartlar, rozetler, düğmeler tutarlı; menü değişince yalnız yeni içerik yumuşakça solarak gelir (çift içerik/titreme yok); sayfa geçişleri (hafif solma+kayma) akıcı.
- [ ] **52.2.** En küçük ekran + en büyük sistem yazı boyutunda (masaüstünde pencereyi ≈360x640'a küçült) tüm rollerin ekranlarını, diyaloglarını ve çekmecesini aç: sarı-siyah taşma şeridi yok, başlık/düğme etiketi kırpılmıyor (yazı ölçeği 2,0'da sınırlanır); giriş ekranında "Yeni Hesap Oluştur" ve "Şifremi Unuttum?" rahat dokunulur (>=44 dp).
- [ ] **52.3.** Ana panel üst çubuğu: yenile/çıkış/widget-iğneleme ikonları >=44 dp dokunma alanında; çift modlu rolde "Sakin Modu/Yönetici Paneli" hapı geniş ekranda etiketli, ekran <400 dp ya da yazı >1,3x iken yalnız ikon (basılı tutunca ipucu etiketi çıkar, mod geçişi yine çalışır); kaydırınca üst çubuk rengi değişmez; yazı büyüdükçe alt satır büyür, araç çubuğu kırpılmaz.
- [ ] **52.4.** Çekmece: başlık rol rengine göre gradyan (süper=mavi, yönetici=zümrüt, sakin/bireysel=mor), ad ve e-posta beyaz ve okunur, rol rozeti okunur; seçili menü öğesi tint'li "hap" + sağda ince çubuk; açılışta ilk 8 öğe kademeli belirir; kısa ekranda (<480 dp, yatay telefon) başlık+liste+sürüm birlikte kaydırılır; menü sırası, çıkış ve mod geçişi eskisi gibi.
- [ ] **52.5.** Kapı açma düğmesi (yönetici kartı, sakin kartı, bireysel kapı kartı): çevrimiçi cihazda "Kapıyı Aç"a dokun → "açılıyor" halkası → başarıda tik + yeşil ton (bireysel kartta "Gönderildi") ~1,4 sn sonra eski hâline döner; Android'de dokunuşta/başarıda hafif titreşim; komut sürerken ikinci dokunuş yeni istek göndermez. Çevrimdışı cihazda dokun → düğme kısa titrer ve mevcut uyarı/yeniden-kontrol akışı eskisi gibi çalışır. Düzen: önce tek dolu "Kapıyı Aç", altında QR/Misafir tonal düğmeleri.
- [ ] **52.6.** Daire sakini kartı (birden çok kapılı hesap): kapı çipleri yatay kaydırma olmadan alt satıra sarar, hiçbir kapı gizli kalmaz, seçili çipte beyaz onay işareti; durum cümlesi değişince yumuşak geçiş; IP/bağlantı rozetleri okunur; "Konum Hatası" ve "Geçiş Reddedildi" uyarıları eskisi gibi çıkar.
- [ ] **52.7.** Dinamik QR modalı: geri sayım halkası akıcı (takılma yok) ve kalan saniye rakamı görünür; halka rengi yeşil→amber→kırmızı; durum başlığı (Güvenli Kapı QR Kodu / Süresi Dolmuş QR Kod / ret başlıkları) rozet olarak, kapı adı başlıkta; arka plana alıp geri dönünce durum doğru ("Kapı Açıldı!" tespiti, süre dolunca yenileme/uyarı eskisi gibi); açık ve koyu temada halka/gölge okunur; kapat düğmesinin "Kapat" ipucu var.
- [ ] **52.8.** Listeler (Site Yönetimi, Kullanıcı Yönetimi, Site Yöneticileri, Şirket Cihaz Envanteri, Bekleyen Site/Abonelik Talepleri, kapı günlükleri): ilk yüklemede iskelet satırlar, boş listede açıklamalı boş durum ekranı, ilk 8 öğe kademeli belirir; her öğe tek yüzeyli kart (kart içinde kart yok); eylem düğmeleri (Yönet/Sil/Onayla/Reddet vb.) görünür ve çalışır, sıra karar → yönetim → yıkıcı; rol/site çipleri yatay kaydırmasız sarar; kullanıcı dizininde daire sakini ve bireysel kullanıcı aynı mor tonda, pasif hesap kartı nötr tonlu; çekip yenileme ve yenile düğmeleri çalışır, sayfalama düğmeleri (Önceki/Sonraki sayfa) 44 dp.
- [ ] **52.9.** Diyaloglar (kapı/cihaz/site, misafir geçişi, yönetici daveti, sakin yönetimi, güvenlik politikası, site kurulumu, cihaz sahiplenme, katılım istekleri): ortak başlık şeridi (ikon + başlık/alt başlık) ve eylem satırı; klavye açıkken ve büyük yazıda başlık+içerik birlikte kaydırılır, alanlar kaybolmaz; büyük yazıda (>1,3x) bazı diyaloglarda alt başlık/eylem düğmeleri içeriğin sonuna taşınır (kasıtlı); Kapat/Yenile düğmeleri 44 dp; iptal/kaydet davranışı ve metinler eskisi gibi.
- [ ] **52.10.** Giriş → "Yeni Hesap Oluştur" → Kayıt → E-posta doğrulama ekranları: giriş ekranında logo + başlık + tek kart, yükleme sırasında düğmede çark; "Beni Hatırla" satırının tamamı dokunulabilir; Kayıt'ta Ad/Soyad geniş ekranda yan yana, dar ekran/büyük yazıda alt alta; 6 haneli kod alanı büyük yazıda da sığar, hata/başarı kutuları okunur; "Şifremi Unuttum" diyaloğu çalışır; internet yok ekranı ve "Tekrar Dene" okunur.
- [ ] **52.11.** Bireysel ana ekran: ilk yüklemede iskelet (Hoş Geldiniz/kurulum kartları o sırada gizli), sonra kartlar; site filtre çipleri sarar; "Üyeyi Çıkar" 44 dp; Wi-Fi/BLE kurulum sayfasında cihaz/ağ satırlarında sinyal gücü rozetleri ("Çok güçlü (-48 dBm)" vb.) ve "Şifreli/Açık ağ" rozeti; kaydet düğmesi "Bağlanıyor ve Kaydediliyor..." metnini korur.
- [ ] **52.12.** Sesli kapı komutu: sesli komutu başlat → kart içindeki canlı banner (dinleniyor/algılanıyor) okunur; dar ekran + büyük yazıda metin kırpılmaz (kompakt düzen); mikrofon parıltısı yalnız dinlerken döner, durunca animasyon kalmaz.
- [ ] **52.13.** Sistem ayarında animasyonları kaldır/azalt açıkken (Android: Geliştirici seçenekleri → animasyon ölçekleri kapalı ya da Erişilebilirlik → Animasyonları kaldır; Windows: Erişilebilirlik → Animasyon efektleri kapalı): kayma/titreme/nabız/iskelet parıltısı anında biter, hiçbir ekran takılı kalmaz, kapı açma yine çalışır.
- [ ] **52.14.** Dijital saat kartı: saniyelik güncellemede sayfa kaydırma takılmaz; gece yarısı (ya da cihaz saatini ileri alarak) tarih metni değişir; küçük ekran/büyük yazıda taşma yok; rozet metni "TSİ (UTC+3)".
- [ ] **52.15.** Günlük PDF dışa aktar (site/kapı, ~400 satıra kadar): "hazırlanıyor" göstergesi ve SnackBar animasyonu donmaz, kaydırma akıcı, yazdır/paylaş önizlemesi açılır; ~600+ satırda hata iletisi eskisi gibi ("PDF oluşturulurken hata ... more than 20 pages").
- [ ] **52.16.** Sunucu erişim günlüğünden yoklama trafiği: Panel (kapı kartı) açıkken ~3 sn'de bir /app/doors/:id/status isteği; Profilim/Site Yönetimi menüsüne geçince ya da opak sayfa açılınca kesilir, Panel'e dönünce sürer; uygulamayı arka plana alınca kesilir, öne gelince hemen tek istek; bireysel kullanıcıda status isteği yok (kapı listesi ~15 sn'de bir); QR modalı açıkken ~800 ms'de bir.
- [ ] **52.17.** Uçak modu/zayıf ağ: durum yoklaması 3→6→12→24→30 sn aralıkla seyrekleşir, ağ dönünce 3 sn'ye döner (QR modalında tavan 5 sn); okuma (GET) istekleri 20 sn'de "Sunucu yanıt vermedi, tekrar deneyin." der; kapı açma 10 sn, yazma 45 sn davranışı değişmedi; kapı açarken düğme kilidi çalışır.
- [ ] **52.18.** Soğuk açılış: oturumlu ve oturumsuz açılışta ilk ekran hızlı (logo + ilerleme göstergesi; Android'de `adb shell am start -W` ile süre ölç, taban sürümle karşılaştır); internet yokken ~6,5 sn içinde "internet yok" ekranı; logo (giriş sayfası + çekmece avatarı) DPR 3+ cihazda keskin.
- [ ] **52.19.** Büyük site (300+ daire): Site Yönetimi → Daireler akordiyonunu aç ve hızlı kaydır (akıcı, takılma yok); sakin ağacı penceresinde arama yazarken liste ~220 ms bekleyip tek geçişte süzülür, temizle düğmesi anında; pencere açılış süresini not et (5x60x3 ağaçta test VM'de ≈3 sn; telefonda belirgin yavaşsa bildir).
- [ ] **52.20.** (Geliştirici) Windows profil kare ölçümü: `flutter drive --profile -d windows --driver=test_driver/perf_driver.dart --target=integration_test/perf_frames_test.dart --dart-define=API_BASE_URL=<yerel API> --dart-define=PERF_USER=<kullanıcı> --dart-define=PERF_SITE=<site> --dart-define=PERF_OUT=<çıktı klasörü> --dart-define=PERF_LABEL=faz5` (yerel/test API'si; üretime bağlanma); aynı komut eski sürümde PERF_LABEL=taban ile çalıştırılıp perf_frames.json'lar kıyaslanır (hedef: build/raster p90 ≤8 ms, jank oranı ≤%2; özellikle ana_panel_bosta, kapi_karti, site_yonetimi_liste aşamaları).

---

## 53. 🚀 Canlı Sunucu Dağıtımı, Yerel Web CORS ve Android Gradle JVM 21 Desteği

- [ ] **53.1. Canlı Sunucu Sağlık ve Veritabanı Kontrolü:**
  - **Nasıl Test Edilir:** `https://api.gudeteknoloji.com.tr/health` adresine tarayıcıdan veya curl ile istek atın.
  - **Beklenen Sonuç:** `{"ok":true,"database":"connected","mqtt":{"configured":true,"connected":true,"has_error":false,"last_error":null,"acl_sync_configured":true}}` 200 OK yanıtı dönmeli.
- [ ] **53.2. Android Gradle JDK 21 Uyumluluğu:**
  - **Nasıl Test Edilir:** `flutter build apk --debug` veya `flutter run` komutunu çalıştırın.
  - **Beklenen Sonuç:** Gradle Java 8 JVM yerine `android/gradle.properties` içinde tanımlı Android Studio JDK 21 (`jbr`) ile hatasız derlenmeli (`problems-report.html` hatası çıkmamalı).
- [ ] **53.3. Web / Localhost CORS Doğrulaması:**
  - **Nasıl Test Edilir:** Chrome veya Edge üzerinde yerel web debug (`flutter run -d chrome`) başlatıp giriş yapmayı deneyin.
  - **Beklenen Sonuç:** "Sunucuya ulaşılamadı" CORS engellemesi olmadan doğrudan API yanıtı alınmalı.

---

## 54. ✉️ E-posta Doğrulama Standardı — Bekleyen Kayıt, Gecikmeye Dayanıklı Kod (2026-10-02)

Ayrıntı ve işletim notları: `docs/EPOSTA_DOGRULAMA.md`.

- [ ] **54.1. Doğrulamadan Önce Hesap Oluşmaması:**
  - **Nasıl Test Edilir:** Yeni bir e-posta ile kayıt olun, kodu GİRMEDEN yönetici panelindeki "Tüm Kullanıcılar" listesine bakın (veya veritabanında `SELECT * FROM users WHERE LOWER(email) = '<e-posta>'`).
  - **Beklenen Sonuç:** Kullanıcı listede/`users` tablosunda görünmemeli; giriş denemesi "Giris bilgileri hatali" döndürmeli. Kod girilince kullanıcı oluşmalı ve ana ekrana geçilmelidir.
- [ ] **54.2. Geç Gelen Kod:**
  - **Nasıl Test Edilir:** Kayıt olun, kodu 12-25 dakika sonra girin.
  - **Beklenen Sonuç:** Kod kabul edilmeli (süre 30 dakika). 30 dakikadan sonra "Aktif bir doğrulama kodu bulunamadı… Kod 30 dakika geçerlidir" mesajı ve "Kodu Tekrar Gönder" yönlendirmesi çıkmalıdır.
- [ ] **54.3. E-posta Sunucusu Çalışmazken Kayıt:**
  - **Nasıl Test Edilir:** (Yerel API'de) `SMTP_HOST` değerini geçersiz yapıp kayıt olmayı deneyin.
  - **Beklenen Sonuç:** Uygulama "Doğrulama kodu şu anda e-posta ile gönderilemiyor" hatasını göstermeli, doğrulama ekranına geçmemeli; hemen yeniden denenebilmelidir (30 sn bekleme dayatılmaz).
- [ ] **54.4. Birden Fazla Kod E-postası:**
  - **Nasıl Test Edilir:** "Kodu Tekrar Gönder" ile ikinci kodu isteyin; e-postaları karşılaştırın.
  - **Beklenen Sonuç:** Her e-postada istek saati yazmalı; yalnızca EN SON istenen kod geçerli olmalı, öncekiler "kod hatalı" demelidir.
- [ ] **54.5. Bekleyen Kayıt Temizliği:**
  - **Nasıl Test Edilir:** Kayıt olup kodu hiç girmeyin; 2 gün sonra bakım çalıştıktan sonra `pending_registrations` tablosuna bakın.
  - **Beklenen Sonuç:** 2 günden eski bekleyen kayıt silinmeli; `users` sayısı değişmemelidir (bakım hesap silmez).
