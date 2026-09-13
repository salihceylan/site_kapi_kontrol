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
  - **Nasıl Test Edilir:** Siteye koordinat ve yarıçap (örn: 75 metre) tanımlayın.
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

## 17. 👤 Üyelik Sistemi — Aşama 2: Bireysel Kullanıcı Self-Service Kaydı ve 4 Haneli E-posta Doğrulaması

- [ ] **17.1. Giriş Ekranından "Yeni Hesap Oluştur" Sayfasına Geçiş:**
  - **Nasıl Test Edilir:** Uygulama giriş ekranının en altında yer alan *"Hesabınız yok mu? Yeni Hesap Oluştur"* butonuna dokunun.
  - **Beklenen Sonuç:** "Kayıt Ol" başlıklı form sayfası (Ad, Soyad, E-posta, Şifre, Şifre Tekrar) akıcı şekilde açılmalı, arayüzde hiçbir taşma (overflow) olmamalı.
- [ ] **17.2. Form Doğrulamaları ve Hata Denetimi:**
  - **Nasıl Test Edilir:** Alanları boş bırakarak veya şifreleri birbiriyle uyumsuz girerek "Kayıt Ol" butonuna basın.
  - **Beklenen Sonuç:** Form geçersiz alanları kırmızı uyarı ile belirtmeli, şifrelerin eşleşmediğini kullanıcıya bildirmelidir.
- [ ] **17.3. Kayıt Olma ve SMTP ile 4 Haneli Doğrulama Kodu Gönderimi:**
  - **Nasıl Test Edilir:** Geçerli bir e-posta adresi (örneğin kendi e-postanız) girerek "Kayıt Ol" butonuna basın.
  - **Beklenen Sonuç:** Kullanıcı hesabı veritabanına `email_verified = false` ve `role = 'individual'` olarak kaydedilmeli; kurumsal SMTP (`kodver@gudeteknoloji.com.tr`) üzerinden ilgili e-postaya 4 haneli sayısal kod gönderilmeli ve uygulama otomatik olarak "E-Posta Doğrulama" ekranına geçmelidir.
- [ ] **17.4. 4 Haneli Kod ile Hesap Doğrulama ve Otomatik Giriş:**
  - **Nasıl Test Edilir:** E-postaya gelen 4 haneli kodu büyük kutucuğa girin ve "Doğrula" butonuna basın (veya klavyeden onaylayın).
  - **Beklenen Sonuç:** Kod başarıyla doğrulanmalı (`is_used = true`), kullanıcının e-postası `email_verified = true` olarak işaretlenmeli; kullanıcıya JWT token üretilerek doğrudan ana ekrana yönlendirilmelidir.
- [ ] **17.5. Hatalı Kod Girildiğinde Deneme Hakkı Koruması:**
  - **Nasıl Test Edilir:** Kasıtlı olarak yanlış bir 4 haneli kod girip "Doğrula"ya basın.
  - **Beklenen Sonuç:** Ekranda "Geçersiz veya süresi dolmuş doğrulama kodu. Kalan hakkınız: X" uyarısı çıkmalı, 5 hatalı denemeden sonra kod bloke edilmelidir.
- [ ] **17.6. Kodu Yeniden Gönder (Resend Code) Fonksiyonu:**
  - **Nasıl Test Edilir:** Doğrulama ekranındaki "Kodu Tekrar Gönder" butonuna dokunun.
  - **Beklenen Sonuç:** E-posta kutusuna yeni bir 4 haneli kod gelmeli ve eski kod iptal edilmelidir.

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
  - **Beklenen Sonuç:** Ekranın üst kısmında yatay kaydırılabilir site filtre çipleri (`[ 🏢 Tüm Siteler (X) ]`, `[ 🏢 Gül Sitesi (Y) ]`, `[ 🏢 Lale Sitesi (Z) ]`) görüntülenmelidir. Bir site çipine tıklandığında hem "Yetkili Kapılarım" hem de "Kayıtlı Dairelerim" yalnızca seçilen siteye göre anında süzülmeli; "Tüm Siteler" seçildiğinde tümü tekrar gösterilmelidir.
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
  - **Beklenen Sonuç:** Sunucu `403 Forbidden` (`GEOFENCE_EXCEEDED`) hatası dönmeli; ekranda *"Kapı konumunda değilsiniz (Mesafe: ~Xm, İzin verilen sınır: Ym)"* uyarısı çıkmalı ve QR kod kesinlikle üretilmemelidir.
- [ ] **31.3. Konum Servisi Kapalıyken veya İzin Verilmediğinde Bilgilendirme:**
  - **Nasıl Test Edilir:** Telefonun GPS konumunu kapatıp QR kod butonuna dokunun.
  - **Beklenen Sonuç:** Uygulama *"Bu kapı için konum doğrulaması zorunludur. Lütfen telefonunuzun GPS konum servisini ve uygulama izinlerini açınız."* uyarısı vermeli, çökme yaşanmamalıdır.

---

## 32. 🛡️ Dinamik QR — Aşama 6: Geofence Güvenlik Katmanı (Zaman Aşımı, Hassasiyet ve Sahte Konum Koruması)

- [ ] **32.1. Sahte Konum (Mock Location / Fake GPS) Tespiti ve Engelleme:**
  - **Nasıl Test Edilir:** Android Geliştirici Seçenekleri'nden sahte konum (Mock Location) uygulaması açarak konumu site içine ayarlayın ve QR kodu isteyin.
  - **Beklenen Sonuç:** Sunucu `is_mocked: true` tespitini yakalamalı; `403 Forbidden` (`MOCK_LOCATION_DETECTED`) hatası vermeli ve audit loga güvenlik ihlali olarak kaydetmelidir.
- [ ] **32.2. Bayat / Eski Konum Bilgisi (Stale Location) Engeli:**
  - **Nasıl Test Edilir:** Konum zaman damgasının 15 saniyeden eski olduğu senaryoyu test edin.
  - **Beklenen Sonuç:** Sunucu `LOCATION_STALE` hatası vermeli ve taze GPS sinyali alınana kadar geçişe izin vermemelidir.
- [ ] **32.3. Yetersiz GPS Doğruluğu (Inaccurate Accuracy > 150m) Koruması:**
  - **Nasıl Test Edilir:** GPS sinyalinin çok zayıf olduğu kapalı/bodrum alanında doğruluk payı 150 metreden büyükken istek gönderin.
  - **Beklenen Sonuç:** `LOCATION_INACCURATE` uyarısı verilmeli, açık alana çıkılması istenmelidir.

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
  - **Nasıl Test Edilir:** Süper kullanıcı veya site yöneticisi olarak Siteler sayfasından "Site Sakinleri" akordiyon ağacını açın. İlgili daire sakin kartındaki üç nokta menüsünden "Hesabı Pasife Al" seçeneğine dokunun ve onaylayın.
  - **Beklenen Sonuç:** Sakinin durumu pasife alınmalı, listede "İnaktif" kırmızı rozeti belirip metin üzeri çizili tona geçmeli; pasif sakinin kapı erişimleri durdurulmalıdır. Aynı menüden "Hesabı Aktif Et" dendiğinde tekrar aktifleşmelidir. Sayfa kapatıp açılmadan anında güncellenmelidir.
- [ ] **36.2. Daire Sakinini Daireden Tamamen Silme:**
  - **Nasıl Test Edilir:** Sakin kartındaki menüden kırmızı renkli "Daireden Sil" seçeneğini seçip onaylayın.
  - **Beklenen Sonuç:** Sakin daireden tamamen çıkarılmalı, kapı yetki istisnaları temizlenmeli; eğer silinen kişi daire yöneticisi ise dairedeki diğer sakinlerden ilki otomatik olarak yeni yönetici yapılmalı (yoksa daire boşaltılmalıdır). Liste anında güncellenmelidir.
- [ ] **36.3. Daire Sakini Şifre / PIN Güncelleme:**
  - **Nasıl Test Edilir:** Sakin kartındaki menüden "Şifre Değiştir" seçeneğine dokunun. Açılan modalda en az 4 karakterli yeni şifre girip "Güncelle" butonuna basın.
  - **Beklenen Sonuç:** Sunucuda şifre güvenli hash (bcrypt) ile güncellenmeli, başarı bildirimi gösterilmeli ve sakin yeni şifresiyle sisteme giriş yapabilmelidir.
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
- [ ] **39.4. Rol Filtreleme Çipleri İle Anında Süzme:**
  - **Nasıl Test Edilir:** Arama çubuğunun altındaki "Tüm Roller", "Süper Kullanıcılar", "Site Yöneticileri", "Daire Sakinleri" ve "Bireysel Kullanıcılar" çiplerine dokunun.
  - **Beklenen Sonuç:** Yalnızca seçilen role sahip kullanıcılar sayfalanarak ekrana gelmeli; aktif filtre rengiyle belirginleşmelidir.
- [ ] **39.5. Kullanıcı Bilgilerini Düzenleme (Ad, E-Posta, Telefon, Rol, Şifre, Aktiflik, E-Posta Onayı):**
  - **Nasıl Test Edilir:** Herhangi bir kullanıcının kartındaki "Düzenle" butonuna dokunun; bilgileri değiştirip "Kaydet"e basın.
  - **Beklenen Sonuç:** Ad Soyad, e-posta, telefon, kullanıcı rolü, şifre sıfırlama, aktiflik ve e-posta doğrulama durumu başarıyla güncellenmeli; uygulama kapatıp açılmadan liste canlı olarak güncellenmelidir.
- [ ] **39.6. Hızlı Aktif/Pasif Geçişi ve Kendini Pasife Alma Koruması:**
  - **Nasıl Test Edilir:** Kart üzerindeki switch'e dokunarak kullanıcıyı pasife veya aktife çekin. Süper kullanıcının kendi kartındaki switch'i deneyin.
  - **Beklenen Sonuç:** Diğer kullanıcıların durumu anında güncellenmeli; Süper kullanıcının kendi kartındaki switch kilitli olmalı ve "Kendi süper kullanıcı hesabınızı pasif yapamazsınız" uyarısı verilmelidir.
- [ ] **39.7. Kullanıcı Silme ve Kendini Silme Koruması:**
  - **Nasıl Test Edilir:** Bir kullanıcı kartındaki kırmızı "Sil" butonuna dokunun; onay modalını onaylayın. Süper kullanıcının kendi kartını kontrol edin.
  - **Beklenen Sonuç:** Silinen kullanıcıya ait tüm yetkiler, cihaz ilişkileri ve kayıtlar güvenle temizlenerek kullanıcı veritabanından kalıcı olarak silinmeli; liste kapatıp açılmadan canlı yenilenmeli; Süper kullanıcının kendi kartında "Sil" butonu gizlenmeli ve kendini silmesi engellenmelidir.


















