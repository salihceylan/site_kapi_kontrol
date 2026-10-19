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
- [ ] **8.6. Seri Monitör ve SmartKeyPass Cihaz Deneme Arayüzünde Kamera Bağlantı Durumu:**
  - **Nasıl Test Edilir:** Cihazın `--- ESP32 SISTEM BILGISI ---` çıktısını veya SmartKeyPass Cihaz Deneme aracındaki "Kamera / QR Okuyucu" alanını kontrol edin.
  - **Beklenen Sonuç:** Kamera bağlıysa `Kamera / QR Okuyucu: Bagli (Hazir)`, bağlı değilse veya yanıt yoksa `Bagli Degil` olarak görünmeli ve anlık güncellenmelidir.
- [ ] **8.7. Manuel Kamera Testi (Seri 'k' Komutu ve Arayüz Butonu):**
  - **Nasıl Test Edilir:** SmartKeyPass Cihaz Deneme aracındaki `Kamera Test (Isik/Bip)` butonuna basın veya seri terminale `k` gönderin.
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

## 10. 🏷️ SmartKeyPass Cihaz Etiketleyici & Harici CH340 / USB-TTL Desteği

- [ ] **10.1. Kilitlenmesiz Anlık UID Okuma (0.3 saniye):**
  - **Nasıl Test Edilir:** ESP32-WROOM veya ESP32-C3 cihazını bilgisayara bağlayın. SmartKeyPass Cihaz Etiketleyici uygulamasında portu seçip "Seçili cihaz UID oku" butonuna basın.
  - **Beklenen Sonuç:** Uygulama kilitlenmeden, cihazı yeniden başlatmaya zorlamadan 0.3 saniye içinde cihazın Unique ID'sini (`00861A0D5020`) ve donanım tipini okuyup ekrana yansıtmalı.
- [ ] **10.2. CH340 Uyumlu USB Firmware Yükleme (Baud Rate & Write Timeout Koruması):**
  - **Nasıl Test Edilir:** CH340 dönüştürücü ile bağlı ESP32-WROOM modülü için "Sürümü USB ile cihaza yükle" butonuna basın (harici dönüştürücülerde karttaki BOOT butonuna basılı tutup EN'e basarak indirme moduna alın).
  - **Beklenen Sonuç:** Yükleme 460800 baud hızında başlatılmalı, pySerial `Write timeout` hatası vermeden firmware yazımı %100 tamamlanmalı ve başarı mesajı görüntülenmelidir.
- [ ] **10.3. ESP32-WROOM Röle Kartı GPIO16 ve Durum LED (GPIO23) Doğrulaması:**
  - **Nasıl Test Edilir:** v3.0.5 yüklendikten sonra "SmartKeyPass Cihaz Deneme" ekranında COM7'ye bağlanın, "Role Pulse", "Role Pin HIGH" ve "Role Pin LOW" butonlarına basın.
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
  - **Beklenen Sonuç:** "Kayıt Ol" başlıklı form sayfası (Ad, Soyad, E-posta, Şifre [ipucu: "En az 8 karakter"], Şifre Tekrar ve yasal onay kutusu) akıcı şekilde açılmalı, arayüzde hiçbir taşma (overflow) olmamalı.
- [ ] **17.2. Form Doğrulamaları ve Hata Denetimi:**
  - **Nasıl Test Edilir:** Alanları boş bırakarak veya şifreleri birbiriyle uyumsuz girerek "Kayıt Ol" butonuna basın (yasal onay kutusu işaretsizken düğme pasiftir: önce işaretleyin). 7 karakterli "abc1234" ve yaygın "12345678" şifrelerini de deneyin.
  - **Beklenen Sonuç:** Form geçersiz alanları kırmızı uyarı ile belirtmeli, şifrelerin eşleşmediğini kullanıcıya bildirmelidir. Kısa şifrede "Şifre çok kısa: en az 8 karakter olmalı…", yaygın şifrede "Bu şifre çok yaygın ve kolay tahmin edilir…" görünmeli, kayıt gönderilmemelidir (ayrıntı: bölüm 66).
- [ ] **17.3. Kayıt Olma ve SMTP ile 6 Haneli Doğrulama Kodu Gönderimi:**
  - **Nasıl Test Edilir:** Geçerli bir e-posta adresi (örneğin kendi e-postanız) ile, 8+ karakterli yaygın olmayan bir şifre (örn. "Mavi-Balon-Kapi-2026") girip yasal onay kutusunu işaretleyerek "Kayıt Ol" butonuna basın.
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
- [ ] **42.3.** Planlı pencerede JWT_SECRET'ı ≥32 karaktere çıkar (tüm oturumlar düşer, kullanıcılara duyur) ve JWT_EXPIRES_IN'i 30d yap → yeni girişlerde token exp-iat=30 gün. JWT_EXPIRES_IN en çok 90 gündür: daha uzun değer (canlıdaki 365d dahil) 90 güne KIRPILIR ve açılışta "[ENV] UYARI: JWT_EXPIRES_IN ust siniri asiyor; tokenlar 90 gune kirpilarak uretiliyor" yazar; boş/geçersizse varsayılan 30 gün.
- [ ] **42.4.** JWT_SECRET boş veya change_this_secret iken servis başlat → exit 1, "[ENV] HATA: JWT_SECRET...", DB'ye bağlanılmaz.
- [ ] **42.5.** Yanlış parolayla art arda 5 giriş → 5. denemede 429 LOGIN_LOCKED + Retry-After ~900; kilitte doğru parola da 429; başka hesap normal girer; 15 dk sonra açılır. Kilit tekrarında 30 dk, 60 dk, en çok 2 sa'e uzar (24 sa hatasız geçince başa döner); uygulama iletisi "Çok fazla hatalı deneme yapıldı. 15 dakika sonra tekrar deneyin."; sayaçlar bellek içidir (sunucu yeniden başlayınca sıfırlanır). Ayrıntı: bölüm 66.
- [ ] **42.6.** Profilde parolayı mevcut parola OLMADAN değiştirmeyi dene → 400 CURRENT_PASSWORD_REQUIRED; doğru mevcut parola ile → 200, yanıtta yeni token, uygulama oturumu düşmeden devam eder.
- [ ] **42.7.** Parola değiştirdikten sonra başka cihazdaki eski oturumla istek → 401 TOKEN_REVOKED, uygulama giriş ekranına döner ("Şifreniz değiştirildiği için oturumunuz sonlandırıldı. Lütfen yeniden giriş yapın."); parola sürümü (pv) artık ZORUNLUDUR: pv'siz eski token'lar da reddedilir ve kullanıcı bir kez yeniden giriş yapar (yalnız .env'de JWT_REQUIRE_PV=0 ise kabul edilir ve açılışta GÜVENLİK uyarısı çıkar).
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

---

## 55. 🌗 Aydınlık / Karanlık Tema Geçiş Düğmesi (2026-10-02)

- [ ] **55.1. Giriş Ekranında Tema Geçişi:**
  - **Nasıl Test Edilir:** Giriş ekranında kartın sağ üst köşesindeki ay (🌙) simgesine dokunun.
  - **Beklenen Sonuç:** Uygulama anında karanlık temaya geçmeli, simge güneşe dönmeli (ipucu: "Aydınlık temaya geç"). Güneşe dokununca aydınlık temaya dönmeli. Taşma olmamalı.
- [ ] **55.2. Seçimin Kalıcılığı:**
  - **Nasıl Test Edilir:** Karanlık temayı seçip uygulamayı tamamen kapatıp yeniden açın.
  - **Beklenen Sonuç:** Uygulama seçilen temayla (ilk karede, aydınlık yanıp sönmeden) açılmalı. Hiç seçim yapılmamışsa cihazın tema ayarı izlenmeli (eski davranış).
- [ ] **55.3. Ana Panelde Tema Geçişi:**
  - **Nasıl Test Edilir:** Giriş yapın; üst çubukta yenile düğmesinin solundaki ay/güneş simgesine dokunun. Küçük ekranda ve büyük yazı boyutunda da deneyin.
  - **Beklenen Sonuç:** Tema anında değişmeli; üst çubuktaki düğmeler (mod hapı, widget, tema, yenile, çıkış) taşmadan ve en az 44 dp dokunma alanıyla sığmalı. Çıkış yapıp tekrar girince seçim korunmalı.
- [ ] **55.4. Kayıt ve Doğrulama Ekranları:**
  - **Nasıl Test Edilir:** "Yeni Hesap Oluştur" ve e-posta doğrulama ekranlarının sağ üstündeki tema düğmesine dokunun.
  - **Beklenen Sonuç:** Tema her ekranda aynı şekilde değişmeli; ekranlar arası geçişte seçim korunmalı.
- [ ] **55.5. Erişilebilirlik:**
  - **Nasıl Test Edilir:** TalkBack/VoiceOver açıkken düğmeye odaklanın.
  - **Beklenen Sonuç:** "Koyu temaya geç" / "Aydınlık temaya geç" okunmalı.

---

## 56. 📚 Arıza Bulma Klavuzu (2026-10-02)

Ana sayfa: `docs/ARIZA_KLAVUZU.md`. Araç ve giriş biçimi: `tools/klavuz/README.md`.

- [ ] **56.1. Klavuz Güncel mi:**
  - **Nasıl Test Edilir:** Depo kökünde `node tools/klavuz/build.mjs --check --fresh` çalıştırın; ardından `node --test "tools/klavuz/*.test.mjs"`.
  - **Beklenen Sonuç:** `TAMAM`, `GÜNCEL` yazmalı, uyarı olmamalı; testler geçmeli. Kod değişikliğinden sonra `ESKİ` çıkarsa `node tools/klavuz/build.mjs` ile belgeleri yenileyin.
- [ ] **56.2. Belirtiden Koda Ulaşma:**
  - **Nasıl Test Edilir:** `docs/ARIZA_KLAVUZU_INDEKS.md` içinde "kapı açma" ya da "giriş 401" gibi bir belirtiyi aratın; satırdaki `dosya:satır` bağlantısına tıklayın.
  - **Beklenen Sonuç:** Bağlantı, belirtiyle ilgili gerçek koda (örn. `server/src/routes/auth_routes.js` giriş ucu) götürmeli; girişteki "olası nedenler" ve "adım adım kontrol" koddaki davranışla uyuşmalı. Uyuşmayan bir açıklama bulursanız ilgili `tools/klavuz/entries/*.mjs` girişini düzeltin (bölümler "doğrulanmadı" etiketlidir).
- [ ] **56.3. Hata Mesajından Koda Ulaşma:**
  - **Nasıl Test Edilir:** Uygulamada gördüğünüz bir hata mesajının parçasını `docs/ARIZA_KLAVUZU_HATA_MESAJLARI.md` içinde aratın.
  - **Beklenen Sonuç:** Mesajı üreten `dosya:satır` listelenmeli.


---

## 57. 💎 Modern Premium Arayüz — Cilalı Kapı Düğmesi ve Ortak Tasarım Dili (2026-10-03)

Kurallar ve bileşenler: `docs/TASARIM_DILI.md`. Bu bölüm emülatörde/cihazda GÖZLE denenir; otomatik testler taşma, kontrast, hareket azaltma ve "boştayken animasyon yok" kurallarını zaten sınar.

- [ ] **57.1. Yuvarlak Cilalı Kapı Düğmesi (3 kart):**
  - **Nasıl Test Edilir:** Daire sakini, site yöneticisi/süper kullanıcı ve bireysel kullanıcı olarak giriş yapın; kapı kartlarına bakın. Yönetici panosunda düğme kartın ortasında, bireysel kartta solda (dar ekranda/büyük yazıda üstte ortalı), daire sakini kartında ortada olmalıdır.
  - **Beklenen Sonuç:** Düğme yuvarlak, parlak (üstte cam gibi yansıma, kenar ışığı), altında yumuşak renkli ışıma olmalı; etiket ve ikon net okunmalı (`KAPIYI AÇ` / `KAPI AÇ` / `UZAKTAN AÇ` / `YEREL AĞDAN AÇ`). Boştayken hiçbir şey kıpırdamamalı.
- [ ] **57.2. Basış ve Açılma Efektleri:**
  - **Nasıl Test Edilir:** Çevrimiçi bir kapının düğmesine dokunun.
  - **Beklenen Sonuç:** Dokunur dokunmaz hafif titreşim, düğme hafif küçülür ve dışa yayılan çift halka görülür; komut sürerken düğme "AÇILIYOR" olur, ortada dönen gösterge ve dışa yayılan sonar halkaları görülür; komut bitince düğme yeşile döner, onay işareti, ışıltı süpürmesi, patlama halkası ve kıvılcımlar görülür (`GÖNDERİLDİ`), 1,4 sn sonra eski haline döner. Hiçbir adım komutu geciktirmemeli (düğme anında tepki verir).
- [ ] **57.3. Çevrimdışı ve Devre Dışı Durumlar:**
  - **Nasıl Test Edilir:** Cihazı çevrimdışı yapın (ya da çevrimdışı bir kapı seçin); düğmeye dokunun. Cihazı yeniden çevrimiçi yapın.
  - **Beklenen Sonuç:** Düğme soluk/camsı gri görünmeli (`ÇEVRİMDIŞI`); dokununca hafif titreşim + yatay titreme + uyarı; çevrimiçi olunca düğme canlanıp kısa bir ışıltı göstermeli.
- [ ] **57.4. Hareket Azaltma ve Yüksek Karşıtlık:**
  - **Nasıl Test Edilir:** Cihaz erişilebilirlik ayarlarından animasyonları kapatın (Android: "Animasyonları kaldır"; iOS: "Hareketi Azalt"), sonra "Yüksek karşıtlık" metnini açın.
  - **Beklenen Sonuç:** Düğme çalışmaya devam eder (titreşim, durum değişimi) ama halka/ışıltı/kıvılcım efektleri görülmez; yüksek karşıtlıkta cila olmadan düz renkli ve net görünür.
- [ ] **57.5. Aydınlık / Karanlık Tema:**
  - **Nasıl Test Edilir:** Tema düğmesiyle iki tema arasında geçin; giriş, ana panel, listeler ve diyaloglara bakın.
  - **Beklenen Sonuç:** İki temada da kartlar, rozetler ve düğmeler okunaklı; karanlıkta kartlarda hafif cam parıltısı, aydınlıkta hero kartlarda hafif ton yıkaması görülür; ana sayfa başlığında rol rengine uygun hafif gradyan ve avatar rozeti vardır.
- [ ] **57.6. Ortak Bileşenler:**
  - **Nasıl Test Edilir:** Bir diyalog açın (örn. Şifremi Unuttum, Site Ekle), boş bir liste görün, başarı/hata bildirimi tetikleyin, açılır bir menüye ya da ipucuna dokunun.
  - **Beklenen Sonuç:** Diyalog başlığında cilalı ikon rozeti; boş listede büyük parlak rozet; bildirimde cam daire içinde simge; açılır menü ve alt sayfa köşeleri yuvarlak; ilerleme göstergelerinin uçları yuvarlak.
- [ ] **57.7. Kısayol / Widget ile Kapı Açma Onayı:**
  - **Nasıl Test Edilir:** Ana ekran widget'ından ya da uygulama kısayolundan bir kapıyı açmayı deneyin (birden çok kapı varsa seçim penceresi de açılır).
  - **Beklenen Sonuç:** "Kapı açılsın mı?" penceresi cilalı kilit rozeti ve uyarı kutusuyla açılır; birden çok kapıda "Hangi kapı açılsın?" penceresinde her kapı dokunulabilir kartlardır; Vazgeç/Kapıyı Aç davranışı eskisi gibidir.
- [ ] **57.8. Küçük Ekran, Büyük Yazı ve Taşma:**
  - **Nasıl Test Edilir:** Sistem yazı boyutunu en büyüğe alın (uygulama içinde en çok 2,0x uygulanır) ve küçük bir telefonda (veya pencereyi daraltarak) tüm ana ekranları, diyalogları ve listeleri gezin.
  - **Beklenen Sonuç:** Hiçbir yerde "overflowed" şeridi/kesilen metin olmamalı; bireysel kapı kartında düğme üstte ortalanmalı; tüm düğmeler en az 44 dp dokunma alanında kalmalı.
- [ ] **57.9. Hız ve Akıcılık:**
  - **Nasıl Test Edilir:** Orta/düşük seviye bir cihazda listeleri hızlıca kaydırın, menü ve sayfa geçişlerini, tema değişimini ve kapı açmayı tekrarlayın.
  - **Beklenen Sonuç:** Kaydırma ve geçişler takılmadan akmalı; sayfa geçişi ~0,2 sn; boştayken (hiçbir şeye dokunmazken) cihaz ısınmamalı/pil harcamamalı (sürekli animasyon yoktur).
- [ ] **57.10. Klavye / Odak (masaüstü ve erişilebilirlik):**
  - **Nasıl Test Edilir:** Windows/web sürümünde Tab ile kapı düğmesine odaklanın; Enter'a basın. TalkBack/VoiceOver ile düğmeye odaklanın.
  - **Beklenen Sonuç:** Odaktaki yuvarlak düğmenin dışında net bir halka görülür; Enter komutu gönderir; ekran okuyucu düğme etiketini ("Kapıyı Aç" vb.) ve açılırken/başarıda durumu okur.
- [ ] **57.11. Ekranlar ve Listeler:**
  - **Nasıl Test Edilir:** Süper kullanıcı/yönetici olarak Siteler, Kullanıcılar, Talepler ve Cihaz Envanteri ekranlarını; bireysel kullanıcıyla Kurulum ve Profil ekranlarını gezin.
  - **Beklenen Sonuç:** Kart başlıklarında cilalı ikon rozetleri (durumuna göre ton: onaylı mavi, bekleyen amber, çevrimiçi yeşil, çevrimdışı kırmızı); listeler sırayla belirir; yüklenirken iskelet, boşken ikon rozetli boş durum görünür. Onay bekleyen kartlarda "Onayla" önde ve dokununca hafif titreşim verir; süper kullanıcıda cihaz kartı başlığında yalnız dikkat gerektiren OTA durumu ("OTA: Hata" vb.) rozet olur.
- [ ] **57.12. Diyaloglar:**
  - **Nasıl Test Edilir:** Site ekle/düzenle, kapı yetkileri, daire sakinleri, cihaz ekle/değiştir, misafir geçişi oluştur ve siteye katıl diyaloglarını açın.
  - **Beklenen Sonuç:** Bölüm başlıklarında ikon rozeti, anahtarlarda durum rozeti, açılır listelerde yuvarlak köşe; kaydet/onayla başarıda hafif titreşim. Misafir geçişi oluşturulunca sonuç kartı bağlantıyı, "Son geçerlilik" ve "Kullanım hakkı" satırlarını göstermelidir.
- [ ] **57.13. Giriş, Kayıt ve QR Tarama:**
  - **Nasıl Test Edilir:** Çıkış yapıp giriş ekranına bakın; "Yeni Hesap Oluştur" ve e-posta doğrulama ekranlarını, ardından kapı ekranı QR tarama sayfasını açın.
  - **Beklenen Sonuç:** Logo halkası parlak ve yumuşak ışımalı; doğrulama ekranında büyük kod alanı, 30 saniye bekleme süresince tükenen ince çizgi; QR sayfasında köşe işaretli tarama çerçevesi ve ipucu kapsülü. Giriş ve doğrulama başarısında hafif titreşim.

---

## 58. 🚪 Sade Daire Kullanıcısı Ekranı ve Çekmece Komutları (2026-10-04)

Daire kullanıcısı (Daire Sakini) ana ekranında artık yalnız kapılar ve yuvarlak "AÇ" düğmesi vardır; açıklama metinleri, rozetler, IP bilgileri ve saat kaldırıldı. Diğer komutlar sol üstteki üç çizgi (hamburger) menüsünde toplandı. (Bireysel kullanıcı ve yönetici ekranları değişmedi.)

- [ ] **58.1. Sade Ana Ekran:**
  - **Nasıl Test Edilir:** Daire kullanıcısı olarak giriş yapın.
  - **Beklenen Sonuç:** Ekranda yalnız tek kart görünür: tek kapı varsa kapı adı, birden çok kapı varsa kapı seçici çipler; altında büyük yuvarlak düğme (`KAPIYI AÇ`). "SmartKeyPass AKILLI GEÇİŞ" rozeti, "Çevrimiçi - Kapıyı açmak için dokunun" cümlesi, IP rozetleri, saat, sesli banner ve QR / misafir düğmeleri görünmemelidir.
- [ ] **58.2. Kapı Seçimi ve Açma:**
  - **Nasıl Test Edilir:** Birden çok kapısı olan hesapta çiplerle kapı değiştirin, düğmeye dokunun; cihazı çevrimdışı yapıp tekrar dokunun.
  - **Beklenen Sonuç:** Seçilen kapı vurgulanır, düğme o kapıyı açar (AÇILIYOR, GÖNDERİLDİ efektleri aynı). Çevrimdışıyken düğme `ÇEVRİMDIŞI` yazar ve dokununca "… şu an çevrimdışı" uyarısı çıkar.
- [ ] **58.3. Çekmece Komutları:**
  - **Nasıl Test Edilir:** Sol üstteki üç çizgi simgesine dokunun.
  - **Beklenen Sonuç:** "Panel"in hemen altında, kapıdaki yetkiye ve cihaza göre şu öğeler görünür: `Sesli Kapı Açma`, `Kapıya QR Göster`, `Kapı Ekranından QR Oku` (yalnız ekranlı cihazda), `Kurye / Misafir Geçiş Linki Oluştur`; yetkisi olmayan öğe hiç görünmez. Ardından eski menü öğeleri (Daireye Katıl & Cihaz Ekle, Eller Serbest & Kestirmeler, Profilim, Çıkış Yap) gelir.
- [ ] **58.4. Çekmeceden QR ve Misafir Geçişi:**
  - **Nasıl Test Edilir:** Çekmeceden sırayla `Kapıya QR Göster`, `Kapı Ekranından QR Oku` ve `Kurye / Misafir Geçiş Linki Oluştur` öğelerine dokunun.
  - **Beklenen Sonuç:** Çekmece kapanır ve eski ana ekran düğmeleriyle aynı akış çalışır: dinamik karekod penceresi (konum zorunluysa önce konum denetimi), kamera ile ekran karekodu okuma ve misafir geçişi diyaloğu. Cihaz çevrimdışıysa QR öğeleri uyarı gösterir.
- [ ] **58.5. Sesli Komut:**
  - **Nasıl Test Edilir:** Çekmeceden `Sesli Kapı Açma` öğesine dokunun, "kapıyı aç" deyin.
  - **Beklenen Sonuç:** Alt sayfada dinleme göstergesi açılır ve eskiden ana ekrandaki sesli banner'la aynı şekilde komut çalışır.
- [ ] **58.6. Küçük Ekran ve Büyük Yazı:**
  - **Nasıl Test Edilir:** Yazı boyutunu en büyüğe alın, küçük telefonda ana ekranı ve çekmeceyi açın.
  - **Beklenen Sonuç:** Taşma olmaz; kapı adı/çipler kırpılmadan sarar, çekmece öğeleri kaydırılabilir.

---

## 59. 🧩 Platform Modül Sistemi — Faz 1: Modül Aç/Kapa, Yönetim Türü, Denetim Kaydı, Ek Roller (2026-10-15)

Site ve toplu yaşam yönetim platformunun çekirdeği: her site hangi modüllerin açık olacağını seçer (şimdilik yalnız Geçiş Kontrol (SmartKeyPass) seçilebilir; diğerleri "Yakında…"). Sözleşme: `docs/PLATFORM_MODUL_SISTEMI.md`. Deneme listesi (claude.ai): `tools/deneme_listesi`. Yeni modüller varsayılan KAPALI, Geçiş Kontrol varsayılan AÇIKTIR.

- [ ] **59.1. Eski ve Yeni Uygulama Sürümü: Kapı Açma Değişmez:**
  - **Nasıl Test Edilir:** Güncellemeden önceki uygulama sürümüyle, sonra yeni sürümle giriş yapın; telefondan kapıyı açın, giriş QR kodu üretin, bir misafir bağlantısı oluşturup açın.
  - **Beklenen Sonuç:** Üçü de her iki sürümde eskisi gibi çalışır, hata çıkmaz (Geçiş Kontrol modülü varsayılan olarak AÇIKTIR; mevcut siteler etkilenmez).
- [ ] **59.2. Modüller Ekranı:**
  - **Nasıl Test Edilir:** Site yöneticisi olarak ve ayrıca süper kullanıcı olarak çekmeceden "Modüller"i açın.
  - **Beklenen Sonuç:** 8 kart görünür. Süper kullanıcıda "Geçiş Kontrol (SmartKeyPass)" anahtarlıdır; site yöneticisinde ANAHTAR YOKTUR (Açık modül "Tanımlı", kapalı modül "Tanımlı değil" + "Modül Talep Et"). "Kişi ve Daire Kayıtları" ile "Duyuru ve Bildirim" "Her sitede açık"; diğer 5 modül (Aidat ve Finans dahil) "Yakında…" ve anahtarsız/talepsizdir. Çekip yenileme ve yenile düğmesi çalışır.
- [ ] **59.3. Geçiş Kontrol Modülünü Kapatma ve Açma (süper kullanıcı):**
  - **Nasıl Test Edilir:** Süper kullanıcı olarak Modüller ekranında bir sitenin Geçiş Kontrol anahtarını kapatın, uyarıyı okuyup onaylayın; sonra yeniden açın. Site yöneticisi hesabıyla aynı siteye bakın.
  - **Beklenen Sonuç:** Kapatmadan önce "Telefondan kapı açma, QR ve misafir geçişi durur" uyarısı çıkar; vazgeçilirse hiçbir şey değişmez. Onaylanınca çip "Kapalı" olur. Tek siteli yöneticide "Kayıtlı Cihazlar" ve "Bluetooth ile Wi-Fi Kur" menüleri kaybolur, Panel'de "Geçiş Kontrol modülü kapalı" kartı çıkar. Yeniden açınca her şey anında geri gelir. Site yöneticisi kendisi açıp kapatamaz (anahtarı yoktur; API ile denerse 403 "Modülleri yalnızca sistem yöneticisi açıp kapatabilir. Modül talebi gönderebilirsiniz.").
- [ ] **59.4. Kapalı Modülde Sakin Deneyimi:**
  - **Nasıl Test Edilir:** Geçiş Kontrol kapalıyken (başka telefonda) sakin hesabıyla Panel'e bakın; telefon widget'ından kapıyı açmayı deneyin; hesapta sesle dinleme açıksa uygulamayı yeniden açın. Sonra yönetici modülü açsın.
  - **Beklenen Sonuç:** Panel'de düğmesiz bilgi kartı görünür, "Eller Serbest" menüsü yoktur, widget o siteyi göstermez (eski kalmışsa "Geçiş kapalı ❌" der). "Tanımlı bir kapı bulunamadı." sesli uyarısı DUYULMAZ ve dinleme durur. Modül açılınca aşağı çekince ya da ~30 sn içinde kapı kartları geri gelir.
- [ ] **59.5. Kapalı Modülde Misafir Bağlantısı ve QR Okuyucu:**
  - **Nasıl Test Edilir:** Geçiş Kontrol kapalıyken bir misafir geçişi bağlantısını açın; kapıdaki QR okuyucuya bir QR gösterin. Sonra modülü açıp tekrar deneyin.
  - **Beklenen Sonuç:** Misafir sayfası kibar bir "Geçiş şu anda kullanılamıyor" bilgisi verir, kapı açma düğmesi yoktur. Okuyucudan açma reddedilir (kapı açılmaz). Modül açılınca ikisi de eskisi gibi çalışır.
- [ ] **59.6. Modül Kapatılınca Yerel (LAN) Anahtar Döner:**
  - **Nasıl Test Edilir:** Cihazla aynı Wi-Fi'deyken uygulamada yerel açmanın çalıştığını doğrulayın; (süper kullanıcıyla) Geçiş Kontrol'ü kapatın; eski uygulama önbelleğiyle yerel açmayı deneyin; modülü yeniden açın ve uygulamayı yenileyin.
  - **Beklenen Sonuç:** Kapatma sonrası eski anahtarla yerel (UDP) açma çalışmaz. Yeniden açıp yenileyince uygulama yeni anahtarı alır ve yerel açma yine çalışır. Cihaz çevrimiçi kalır. (Cihaz o sırada çevrimdışıysa yeni anahtar bağlanınca gider.)
- [ ] **59.7. İki Siteli Yönetici:**
  - **Nasıl Test Edilir:** İki siteyi yöneten hesapla birinde Geçiş Kontrol'ü kapatın; Panel'in site seçicisine ve Modüller ekranının site seçicisine bakın.
  - **Beklenen Sonuç:** Panel'in site seçicisinde yalnız modülü açık site listelenir ve menüler durur. Modüller ekranında site değiştirince her sitenin durumu ayrı görünür; birinde kapalı olan diğerinde açık olabilir.
- [ ] **59.8. Bireysel Kullanıcı ve Sakin Modundaki Yönetici (Kapalı Site):**
  - **Nasıl Test Edilir:** Bireysel kullanıcı ya da Sakin Modu'ndaki yönetici olarak, Geçiş Kontrol'ü kapalı bir sitedeyken ana ekrana bakın.
  - **Beklenen Sonuç:** "Kayıtlı Dairelerim", "Katılım Başvurularım" ve hızlı işlemler (Cihaz Ekle, Site Kur, Siteye Katıl) görünmeye devam eder; üstte tek satır "Geçiş Kontrol modülü kapalı…" notu vardır.
- [ ] **59.9. Süper Kullanıcı: Modüller ve Panel:**
  - **Nasıl Test Edilir:** Süper kullanıcıyla giriş yapın; çekmeceye bakın; Panel'de Geçiş Kontrol'ü kapalı bir siteyi seçin; Modüller'den açıp yenileyin.
  - **Beklenen Sonuç:** Çekmecede "Modüller" ve "Denetim Kaydı" görünür. Kapalı sitede kapı kartları yerine bilgi kartı ("Modüller Ekranını Aç" düğmesiyle) çıkar, uzaktan açma "Bu özellik şu an kapalı…" der. Açınca kartlar geri gelir.
- [ ] **59.10. Denetim Kaydı:**
  - **Nasıl Test Edilir:** Süper kullanıcı olarak "Denetim Kaydı"nı açın; az önce yaptığınız modül ve rol işlemlerini bulun; "Site filtresi" ve "Eylem filtresi"ni (Tümü / Modül açıldı / Modül kapatıldı / Rol verildi / Rol kaldırıldı) kullanın; "Daha fazla yükle" ve çekip yenilemeyi deneyin. Site yöneticisi hesabıyla ekranı açmayı deneyin.
  - **Beklenen Sonuç:** Kim, ne zaman, hangi siteye hangi işlemi yaptı satırları görünür; filtreler birlikte çalışır; yüklenirken yenile ya da filtre değiştirince düğme takılı kalmaz; ağ hatasında "kayıt yok" değil hata kartı çıkar. Yönetici hesabı bu ekranı göremez. Kayıtlar silinemez.
- [ ] **59.11. Yönetim Türü Seçici:**
  - **Nasıl Test Edilir:** Site Kur (site yöneticisi/bireysel) ve Süper kullanıcı Site Ekle ekranlarında "Yönetim Türü" alanına bakın; mevcut bir sitenin kartına ve Site Düzenle'ye bakın.
  - **Beklenen Sonuç:** "Apartman ve Site" seçili gelir; Rezidans, İş Merkezi, Kooperatif ve Alışveriş Merkezi "Yakında…" etiketli ve seçilemez. Site kartında tür çipi vardır; mevcut siteler "Apartman ve Site" görünür; Site Düzenle'de tür salt okunurdur.
- [ ] **59.12. Ek Roller: Yönetim Kurulu ve Görevli:**
  - **Nasıl Test Edilir:** Modüller ekranı → "Ek roller": hesabı olan bir kişinin e-postasını "Yönetim Kurulu" rolüyle ekleyin; kayıtsız bir e-posta ve site yöneticisinin e-postasını deneyin; kişiyi kaldırın.
  - **Beklenen Sonuç:** Eklenen kişi listede görünür. Kayıtsız e-posta "Bu e-posta ile kayıtlı hesap yok." der; site yöneticisi "Bu kişi zaten site yöneticisi." der. Kaldırmak onay ister ve kişiyi listeden çıkarır; kişinin hesabı ve dairesindeki kapı yetkisi bozulmaz. Denetim Kaydı'nda "Rol verildi/kaldırıldı" görünür.
- [ ] **59.13. Yalnız Kurul/Görevli Rolü Olan Hesap:**
  - **Nasıl Test Edilir:** Yalnızca Yönetim Kurulu ya da Görevli rolü olan (başka kapı erişimi olmayan) hesapla giriş yapın.
  - **Beklenen Sonuç:** Menüler ve Panel değişmez; "Geçiş Kontrol kapalı" sayılmaz, kapı menüleri gizlenmez.
- [ ] **59.14. Ağ Hatası ve Küçük Ekran:**
  - **Nasıl Test Edilir:** İnterneti kapatıp Modüller ve Denetim Kaydı ekranlarını açın; telefonda yazı boyutunu en büyüğe alıp bu ekranları ve Ek Rol Ata / kapatma onayı pencerelerini açın.
  - **Beklenen Sonuç:** Hata kartı ve "Tekrar Dene" görünür ("site yok" ya da "kayıt yok" yazmaz); menüler kaybolmaz. Taşma olmaz.
- [ ] **59.15. (Geliştirici) Sunucu Kapı Koruması ve Hız Sınırları:**
  - **Nasıl Test Edilir:** Geçiş Kontrol kapalı sitede POST /app/doors/:id/open, /qr-token ve POST /app/guest-passes çağırın; GET /app/my-doors'a bakın; PUT /manager/sites/:siteCode/modules/door_control {enabled:false} isteğini onaysız (confirm yok) gönderin; modül ve ek rol uçlarını art arda çağırın.
  - **Beklenen Sonuç:** Kapı uçları 403 `{code:"MODULE_DISABLED", module:"door_control"}` döner; my-doors o sitenin kapılarını listelemez; onaysız kapatma 409 `MODULE_CONFIRM_REQUIRED` döner; modül ucu kullanıcı başına 60/saat, ek rol ucu 20/saat sonrası 429 (`Retry-After`) döner.
- [ ] **59.16. (Operasyon) DNS ve MQTT Bağlantısı:**
  - **Nasıl Test Edilir:** Cloudflare DNS'te `mqtt` kaydının "DNS only" (gri bulut) olduğunu doğrulayın; `api` kaydı turuncu bulut (Cloudflare vekili) arkasında olabilir: bu durumda sunucuda `.env` içindeki `TRUST_PROXY` değerinin `loopback,cloudflare` içerdiğini (ya da nginx `real_ip` ayarını) ve `pm2 logs kapi-api` içinde "Istemci IP'si cozulemedi" uyarısının OLMADIĞINI kontrol edin; sunucuda `curl http://127.0.0.1:8080/health` ve `bash ~/ops/healthcheck.sh --dry-run -v` (`mqtt_public` satırı) çıktısına bakın. `evotomasyon` kaydı bu projenin dışındadır (ev_otomasyon listesine bakın).
  - **Beklenen Sonuç:** `mqtt` kaydı gri bulutta olmalıdır: turuncu bulut MQTT 8883/8884 portlarını taşımaz, cihazlar bağlanamaz (`healthcheck.sh` bu durumda "DNS proxy açık olabilir (MQTT için 'DNS only' gerekir)" uyarısı verir). `api` kaydı turuncu bulutta olabilir (yasal metinler API trafiği için Cloudflare'i alt işleyen olarak yazar); gerçek istemci IP'si çözülmezse giriş kilidinin IP geneli katmanı kendini devre dışı bırakır. `/health` içinde `mqtt.connected:true` görünür (API köprüsü `MQTT_CONNECT_HOST=127.0.0.1` ile yerel brokera bağlanır; cihazlar yine genel adla bağlanır).
- [ ] **59.17. Modül Talebi (Site Yöneticisi → Süper Kullanıcı):**
  - **Nasıl Test Edilir:** Süper kullanıcı bir sitede Geçiş Kontrol'ü kapatsın. Site yöneticisi olarak Modüller ekranında "Modül Talep Et"e dokunup not yazın ve gönderin; aynı modül için ikinci talep göndermeyi deneyin; "Talebi Geri Çek"i deneyip yeniden talep edin.
  - **Beklenen Sonuç:** Talepten sonra çip "Talep gönderildi" olur ve "Modül Taleplerim"de "Bekliyor" görünür; ikinci talep "Bu modül için bekleyen bir talebiniz var." diye reddedilir; geri çekince çip "Tanımlı değil"e döner. Tüm aktif süper kullanıcılara "Site ve Toplu Yaşam Yönetim Sistemi - Yeni Modül Talebi" e-postası gider. "Yakında…" modüller için talep düğmesi yoktur; süper kullanıcıda "Modül Talep Et" düğmesi çıkmaz.
- [ ] **59.18. Modül Talepleri (Süper Kullanıcı Onayı):**
  - **Nasıl Test Edilir:** Süper kullanıcı olarak çekmecede "Modül Talepleri"ni açın; süzgeçleri (Bekleyen / Onaylanan / Reddedilen / Tümü) deneyin; bir talebi onaylayın, bir başkasını gerekçeyle reddedin. İkinci cihazdan aynı talebi tekrar onaylamayı deneyin.
  - **Beklenen Sonuç:** Çekmece öğesinde bekleyen sayısı rozeti görünür ve onay/ret sonrası düşer. Onayda modül siteye tanımlanır; site yöneticisi yenileyince "Tanımlı" görür ve modülün menüleri gelir. Retta yönetici gerekçeyi "Modül Taleplerim"de görür, modül kapalı kalır. İkinci onay "Bu talep artık bekleyen durumda değil." der. Süper kullanıcı modülü Modüller anahtarıyla doğrudan açarsa o modülün bekleyen talebi otomatik "onaylandı" olur. Denetim Kaydı'nda `module_request.*` ve `module.enabled` satırları görünür.
- [ ] **59.19. Ürün Adı: "Site ve Toplu Yaşam Yönetim Sistemi":**
  - **Nasıl Test Edilir:** Giriş ekranına, Panel başlığına, web sekme başlığına, Android/Windows uygulama adına, doğrulama kodu ve şifre sıfırlama e-postalarına ve şifre sıfırlama sayfasına bakın; kapı kartında etiketi okuyun.
  - **Beklenen Sonuç:** Platform adı her yerde "Site ve Toplu Yaşam Yönetim Sistemi"dir (giriş alt başlığı "Yönetici ve sakin girişi", Panel başlığı "Panel"; uzun başlık dar ekranda taşmadan sarar). Kapı modülünün adı SmartKeyPass'tir (kapı kartı etiketleri "SmartKeyPass AKILLI GEÇİŞ"), katalogdaki "Geçiş Kontrol (SmartKeyPass)", cihaz/BLE adları ve kapı günlüğü/cihaz raporları.

---

## 60. 👥 Kişi ve Daire Kayıtları (CRM) — Faz 2a: Kişiler, Daireler, Araçlar, Geçmiş (2026-10-16)

Sitedeki herkesin, her dairenin ve her aracın tek yerde tutulduğu çekirdek kayıt. Sözleşme: `docs/PLATFORM_KISILER.md` (sonundaki "Faz 2a inceleme kararları" öncelikli). Toplu Excel yükleme ve dışa aktarma Faz 2b'dedir (henüz yok). Mevcut sakinler ilk açılışta otomatik aktarıldı; kapı yetkileri değişmedi.

- [ ] **60.1. Mevcut Sakinler Otomatik Aktarıldı:**
  - **Nasıl Test Edilir:** Güncellemeden sonra site yöneticisi olarak çekmeceden "Kişiler"i açın; güncellemeden önce var olan bir sakini bulun. Sakin hesabıyla kapıyı açın.
  - **Beklenen Sonuç:** Bugünkü sakinler Kişiler listesinde bağlı oldukları daireyle (ilişki "Sakin") görünür. Kapı açma ve kapı yetkileri eskisi gibidir; kimse yeniden kaydolmadı.
- [ ] **60.2. Kişiler, Daireler ve Araçlar Sekmeleri:**
  - **Nasıl Test Edilir:** Kişiler ekranında üç sekmeyi gezin; arama kutusuna ad, telefon, e-posta, daire etiketi, plaka yazın; ilişki ve durum süzgeçlerini kullanın; aşağı çekip yenileyin. İki siteli yöneticide üstteki site seçicisini değiştirin.
  - **Beklenen Sonuç:** Her sekme yüklenirken, boş ve hatalıyken doğru durumu gösterir ("kayıt yok" yalnız gerçekten boşken). Arama yazdıkça daralır, hızlı yazarken eski sonuç yenisini ezmez. Site değişince liste o sitenin kayıtlarına döner.
- [ ] **60.3. Kişi Ekle ve Telefon Girişi:**
  - **Nasıl Test Edilir:** Kişi Ekle: ad, telefon alanına 5551234567 yazın, ardından +905321234567 ve 05321234567 yapıştırın; daire ve ilişki seçin; giriş tarihine 05032024 yazın; kaydedin. Aynı e-postayla bir kez daha ekleyin.
  - **Beklenen Sonuç:** Telefon her seferinde tek ve doğru "+90 555 123 45 67" biçimi olur (yapıştırma çift ülke kodu üretmez). Tarih 05.03.2024 olur. Kişi listede ve dairesinde görünür. İkinci eklemede "Bu e-posta ile kayıtlı bir kişi zaten var." ve "Kişiyi Aç" çıkar.
- [ ] **60.4. Boş Daireye E-postalı Kişi: Giriş Bilgisi:**
  - **Nasıl Test Edilir:** Boş bir daireye gerçek e-postalı bir kişi ekleyin. Dolu bir daireye de e-postalı kişi ekleyin.
  - **Beklenen Sonuç:** Boş dairede o kişiye hesap açılır ve giriş bilgileri e-postayla gider ("Giriş bilgileri e-postayla gönderildi." ya da gönderilemediyse uyarı). Dolu dairede hesap AÇILMAZ, yalnız kayıt tutulur.
- [ ] **60.5. Hesaplı Kişide Alanlar Kilitli:**
  - **Nasıl Test Edilir:** Hesabı olan bir kişinin kartında "Düzenle"yi açın.
  - **Beklenen Sonuç:** Ad, telefon ve e-posta salt okunurdur (kişinin kendi profilinden değişir); yalnız not düzenlenir. Dahili (daire) hesabında e-posta düzenlenebilir.
- [ ] **60.6. Taşındı: Eski Sakin ve Kapı Yetkisi:**
  - **Nasıl Test Edilir:** Bir kişinin kartında "Taşındı"yı seçin (onay penceresini okuyun); yarın gibi gelecek tarih yazmayı deneyin; sonra o kişinin hesabıyla o dairenin kapısını açmayı deneyin. Aynı daireye yeni kiracı ekleyin.
  - **Beklenen Sonuç:** Kişi "Eski sakin" olur ve dairenin geçmişinde kalır. Gelecek tarih "Taşınma tarihi bugünden ileri olamaz." diye reddedilir. Taşınan kişi o daire için kapıyı AÇAMAZ; başka dairedeki yetkisi etkilenmez. Yeni kiracı güncel sakin olur.
- [ ] **60.7. Taşındı: Yönetici ve Özel Kapı İzni:**
  - **Nasıl Test Edilir:** Dairenin APARTMENT_ADMIN sakinini "Taşındı" yapın (dairede başka sakin varsa onun girişini deneyin). Özel kapı izni verilmiş eski usul bir sakini taşındı yapın.
  - **Beklenen Sonuç:** Dairede kalan diğer sakinin kapı erişimi ve PIN'i bozulmaz; yönetici rolü başka bir sakine devredilir. Özel izinli taşınan sakinin kapısı da kapanır.
- [ ] **60.8. Eski Ekranlardan Çıkarma CRM'e Yansır:**
  - **Nasıl Test Edilir:** Daireler/Sakinler ekranında bir sakin için "Daireden çıkar" ve başka birinde "Sakini Daireden Sil" yapın; Kişiler'e dönüp yenileyin. Sonra aynı dairede malik eklemeyi deneyin.
  - **Beklenen Sonuç:** Çıkarılan kişinin o daireyle ilişkisi biter ("Eski sakin"). Elle malik girilmişse bile "bu dairede malik zaten var" hatası çıkmaz. Geçici "Pasife al/Aktif et" ise ilişkiyi BİTİRMEZ.
- [ ] **60.9. Hesap Silme ve Daire Sıfırlama:**
  - **Nasıl Test Edilir:** Bir dairede "Daire sakinini sıfırla"yı çalıştırın; süper kullanıcıyla bir test hesabını silin; Kişiler'i yenileyin.
  - **Beklenen Sonuç:** İşlemler hata vermez. "Silinmiş hesap" adında aktif kayıt kalmaz; kişi eski sakin olarak adıyla geçmişte durur.
- [ ] **60.10. Daireler: Alanlar, Arsa Payı, Muhatap:**
  - **Nasıl Test Edilir:** Bir dairenin kartında "Düzenle": kat, brüt/net m², arsa payı 35/1000, daire tipi ve "Borç ve bildirimler kime gitsin" seçin; yalnız pay girip payda boş bırakın; m² alanına 1e3 yazın. Aynı dairede ikinci malik eklemeyi deneyin.
  - **Beklenen Sonuç:** Geçerli değerler kaydolur. Tek başına pay ve "1e3" reddedilir. İkinci malik "Bu dairede bu ilişki için aktif bir kişi zaten var." der. Daire arama kutusu blok-daire etiketi ve sakin adıyla bulur.
- [ ] **60.11. Araç ve Plaka:**
  - **Nasıl Test Edilir:** Araçlar sekmesinde bir kişiye "34 abc 123" plakası ekleyin; aynı plakayı tekrar ekleyin; plakayla arayın; aracı kaldırın (onay), kaldırma düğmesinin okunuşuna bakın.
  - **Beklenen Sonuç:** Plaka büyük harf ve boşluksuz kaydolur; ikinci kez "Bu plaka bu sitede zaten kayıtlı." der; arama kişiyi bulur; kaldırma onay ister ve kaydı silmez, pasifleştirir. Düğme "34ABC123 plakalı aracı kaldır" diye okunur.
- [ ] **60.12. Geçmiş (Denetim) ve Kişisel Veri:**
  - **Nasıl Test Edilir:** Bir kişinin adını, bir dairenin m²'sini ve bir kişinin telefonunu değiştirin; kişi ve daire kartlarında "Geçmiş"i açın.
  - **Beklenen Sonuç:** Satırlar kim/ne zaman/ne değişti gösterir; ad ve m² için eski → yeni görünür. Telefon, e-posta ve not için yalnız "Telefon güncellendi" yazar (eski/yeni değer saklanmaz). Otomatik işlemler "Sistem tarafından" diye görünür.
- [ ] **60.13. Yönetim Kurulu Üyesi: Salt Okunur:**
  - **Nasıl Test Edilir:** Yönetim kurulu üyesi hesabıyla "Kişiler"i açın; görevli (STAFF) hesabıyla menüye bakın.
  - **Beklenen Sonuç:** Kurul üyesinde hiçbir ekle/düzenle/taşındı/kaldır düğmesi yoktur ("yalnızca görüntüleyebilirsiniz" notu); kişi ve araç notları görünmez. Görevlide "Kişiler" menüsü yoktur.
- [ ] **60.14. Başka Sitenin Kullanıcısına Bağlanmaz:**
  - **Nasıl Test Edilir:** Başka bir sitede (ya da yalnızca "Görevli/Kurul" rolüyle bu sitede) kayıtlı birinin e-postasıyla bu sitede kişi ekleyin (daire seçerek).
  - **Beklenen Sonuç:** Kişi hesapsız kaydolur; başka sitedeki ad/telefon görünmez; o kişiye bu sitede kapı yetkisi AÇILMAZ. Kişi siteye katılım akışıyla üye olunca eşleşme sonradan kurulur.
- [ ] **60.15. Sakin: Kayıtlarım:**
  - **Nasıl Test Edilir:** Sakin hesabıyla Profilim ekranında "Kayıtlarım"a bakın; başka bir sitede kaydı olmayan hesapla da bakın.
  - **Beklenen Sonuç:** Yalnız kendi dairen, ilişkin, giriş tarihin ve kendi plakaların görünür; yönetici notları ve başkasının bilgisi görünmez. Kaydı olmayan hesapta bölüm gizlidir ya da açıklama yazar; hata "kayıt yok" diye gösterilmez.
- [ ] **60.16. Küçük Ekran, Klavye ve Ekran Okuyucu:**
  - **Nasıl Test Edilir:** Telefonda yazı boyutunu en büyüğe alıp Kişi Ekle, İlişki, Taşındı, Araç ve Daire düzenleme pencerelerini açın; sunucudan hata aldırın (aynı e-posta); gönderirken geri tuşuna basın; ekran okuyucuyla daire seçicisini ve temizle düğmesini dolaşın.
  - **Beklenen Sonuç:** Taşma yoktur; hata uyarısı kaydet düğmesinin yanında görünür. Gönderim sürerken geri tuşu pencereyi kapatmaz. Seçici hata metni ve "Seçimi temizle" ekran okuyucuya okunur.
- [ ] **60.17. (Geliştirici) Gerçek Veritabanı Doğrulaması:**
  - **Nasıl Test Edilir:** server klasöründe `node scripts/qa_platform_pg.mjs` komutunu `QA_CONFIRM_DISPOSABLE_DB=yes` ile çalıştırın (geçici yerel PostgreSQL).
  - **Beklenen Sonuç:** Altı bölüm yeşil (≈407 kontrol): migrate zinciri = ensureDbSchema (tetikleyici dahil), yetim/silme senaryoları, taşındı kapı kapanışı, kilit yarışları (Taşındı × kullanıcı silme / sıfırlama / daire azaltma), başka site bağı.
- [ ] **60.18. (Operasyon) Canlı Dağıtım Doğrulaması:**
  - **Nasıl Test Edilir:** Sunucuda: `SELECT code FROM platform_backfills;` ve `SELECT tgname FROM pg_trigger WHERE tgname='trg_users_preserve_site_people';` ve `pm2 logs kapi-api --lines 60 --nostream`.
  - **Beklenen Sonuç:** Biri `people_v1`, diğeri tetikleyici adını döndürür; günlükte "people_v1 aktarimi basarisiz" yoktur; `/health` içinde `mqtt.connected:true`. (Provada 3 aktif üyelik = 3 kişi + 3 ilişki; kapı üyelik sayısı değişmedi.)

---

## 61. 📢 Duyuru ve Bildirim — Faz 3a: Duyuru, Hedefleme, Okundu, E-posta, Tercihler (2026-10-16)

Yönetimin sakinlere duyuru yaptığı çekirdek modül (her sitede hep açık). Sözleşme: `docs/PLATFORM_DUYURU.md` (sonundaki kararlar öncelikli). Bu sürümde uygulama kapalıyken telefon bildirimi ve Belgeler YOK (Faz 3b; telefon bildirimi için Firebase kurulumu gerekir); SMS ve WhatsApp "Yakında…". Uygulama açıkken bildirim anlık itme değil, ~20 sn yoklamadır.

- [ ] **61.1. Duyuru Oluşturma ve Hedef Seçimi:**
  - **Nasıl Test Edilir:** Site yöneticisi olarak çekmeceden "Duyurular"ı açın; "Yeni Duyuru": başlık, metin, önem (Normal/Acil); hedefi "Tüm site", sonra "Bloklar", sonra "Daireler" seçerek deneyin; yayınlamadan önce çıkan "N kişiye ulaşır, M kişinin e-postası var" özetine bakın.
  - **Beklenen Sonuç:** Hedef değişince kişi sayısı değişir. Hedefte ulaşılacak kimse yoksa yayın engellenir ve nedeni söylenir. SMS ve WhatsApp seçenekleri "Yakında…" etiketli ve pasiftir.
- [ ] **61.2. Yayınlama, Sakinde Görünme ve Okundu:**
  - **Nasıl Test Edilir:** Duyuruyu "Şimdi yayınla". Sakin hesabıyla Duyurular'ı açın, duyuruyu okuyun; yönetici olarak duyurunun ayrıntısında "Alıcılar" sekmesine bakın.
  - **Beklenen Sonuç:** Sakinde okunmamış duyuru nokta ve kalın başlıkla görünür, açınca okundu olur, çekmece rozeti düşer. Yönetici kaç kişinin okuduğunu ve okumayanların isimlerini görür (Okumayanlar / Okuyanlar, arama).
- [ ] **61.3. Anlık Bildirim (Yaklaşık 20 Saniye) ve Acil Şerit:**
  - **Nasıl Test Edilir:** Sakin hesabı uygulamayı açık tutarken yönetici yeni duyuru, sonra Acil duyuru yayınlasın. Sakin Profilim ekranına geçip aşağı kaydırsın.
  - **Beklenen Sonuç:** En geç ~20 sn içinde "Yeni duyuru" uyarısı ve rozet çıkar (sayfayı yenilemeden). Acil duyuruda ekranın üstünde kırmızı şerit okunana kadar sabit kalır, kaydırınca kaybolmaz, başka menülerde de görünür; dokununca duyuru açılır, okununca şerit kalkar. Bağlantı koparsa "daha seyrek kontrol ediliyor" notu çıkar.
- [ ] **61.4. Taslak, Zamanlama ve Zamanında Yayın:**
  - **Nasıl Test Edilir:** Taslak kaydedin; Düzenle → Zamanla: 2-3 dakika sonrası (İstanbul saati); geçmiş saat ve 1 yıldan uzak saat deneyin; bekleyin.
  - **Beklenen Sonuç:** Taslak ve "Zamanlanmış" yalnız yöneticide görünür. Zamanı gelince kendiliğinden "Yayında" olur ve sakinlere ulaşır (audit'te "Sistem"). Geçersiz zaman açık Türkçe uyarı verir.
- [ ] **61.5. Düzenleme, Geri Çekme ve Silme:**
  - **Nasıl Test Edilir:** Yayınlanmış duyurunun metnini düzeltin; başka bir duyuruyu geri çekin; bir taslağı silin; yayınlanmışı silmeyi deneyin.
  - **Beklenen Sonuç:** Düzeltme sakinde güncellenir ve "Düzenlendi" notu görünür (yeniden bildirim/e-posta yok). Yayınlanmış duyuruda yalnız başlık/metin değişir. Geri çekilen duyuru sakinde kaybolur, yöneticide "Geri çekildi" olarak kalır. Silme yalnız taslak/zamanlanmışta (onaylı).
- [ ] **61.6. E-posta ile Gönderme ve İstatistik:**
  - **Nasıl Test Edilir:** "E-posta da gönder"i işaretleyerek (kendi e-postalı kişiniz dahil) yayınlayın; duyuru ayrıntısındaki e-posta özetine bakın; aynı adresli iki kişiye gönderin.
  - **Beklenen Sonuç:** Yayın isteği hemen döner, e-postalar kısa sürede gelir. Konu "[Site Adı] Başlık" (acilde "ACİL: " öneki). İstatistik: gönderilen, e-postası olmayan, tercihi nedeniyle atlanan, yinelenen adres, sınır nedeniyle atlanan. Aynı adrese bir duyuruda tek e-posta gider.
- [ ] **61.7. Bildirim Tercihleri:**
  - **Nasıl Test Edilir:** Sakin hesabında Profil → "Bildirim Tercihleri": e-posta anahtarını kapatın; yönetici normal, sonra acil duyuruyu e-postalı yayınlasın.
  - **Beklenen Sonuç:** Normal duyurunun e-postası gelmez (uygulamada görünür), acil duyurunun e-postası tercihten etkilenmez. "Telefon bildirimi — Yakında…" pasiftir. Yalnız görevli ve bireysel hesapta bu bölüm ve "Duyurular" menüsü yoktur.
- [ ] **61.8. Abonelikten Çıkma Bağlantısı:**
  - **Nasıl Test Edilir:** Hesabı olmayan (yalnız kayıtlı) e-postalı bir kişiye duyuru gönderin; e-postadaki "Abonelikten çık" bağlantısını açıp onaylayın (Gmail'de ayrıca "Abonelikten çık" düğmesi); aynı kişiye yeni (acil dahil) duyuru gönderin. Hesabı olan biri için aynı bağlantıyı kullanıp uygulamadaki tercihe bakın, tercihi açın.
  - **Beklenen Sonuç:** Onay sayfası açılır, "Evet"e basılana kadar hiçbir şey değişmez. Çıkıştan sonra o adrese acil dahil duyuru e-postası gitmez (istatistikte "tercihi nedeniyle atlandı"). Hesabı olan kişide uygulamadaki e-posta tercihi KAPALI görünür; tercihi açınca e-postalar yeniden gelir.
- [ ] **61.9. Kötüye Kullanım Sınırları:**
  - **Nasıl Test Edilir:** Aynı duyuruyu art arda iki kez yayınlayın; kısa sürede çok sayıda e-postalı yayın veya zamanlama yapın; aynı adrese bir gün içinde dörtten çok duyuru e-postası gönderin.
  - **Beklenen Sonuç:** İkinci aynı duyuru "az önce yayınlandı" diye engellenir ve liste güncellenir. Yönetici saatlik sınır (10 e-postalı yayın/zamanlama), site günlük sınırları (30 yayın, 3 acil+e-posta) aşılınca açık Türkçe mesaj çıkar; adres başına günlük 3 sınırını aşan e-posta "sınır nedeniyle atlandı" olur.
- [ ] **61.10. Yönetim Kurulu Üyesi: Salt Okunur:**
  - **Nasıl Test Edilir:** Kurul hesabıyla Duyurular → "Yönetim görünümü"; çok az kişiye (1-4) giden bir duyuruyu açın; görevli hesabıyla menüye bakın.
  - **Beklenen Sonuç:** Yazma düğmeleri, alıcı isimleri ve oluşturan kişi görünmez; yalnız içerik ve sayılar vardır. 1-4 alıcılı duyuruda okunma/e-posta sayıları "—" ve "Gizli: küçük hedef" olur. Görevli hesapta "Duyurular" yoktur.
- [ ] **61.11. Başka Siteden Duyuru Görünmez:**
  - **Nasıl Test Edilir:** İki ayrı sitede iki ayrı yönetici birer duyuru yayınlasın; her sitenin sakin hesabıyla gelen kutusuna bakın.
  - **Beklenen Sonuç:** Sakin yalnız kendi sitesinin ve kendisine hedeflenen duyuruları görür. Başka sitenin duyurusu hiçbir ekranda çıkmaz.
- [ ] **61.12. Form Hataları ve Girişler:**
  - **Nasıl Test Edilir:** Başlığı boş bırakıp ekranın altındaki Yayınla'ya basın; saat alanına 9:30 yapıştırın; tarihe 31.02 yazın; başlığa 130 karakter yapıştırın; Acil seçip e-postayı kapatın ve Acil'e yeniden dokunun; yazı boyutunu en büyüğe alın.
  - **Beklenen Sonuç:** Eksik alan olunca form ilk hatalı alana kaydırır, imleç oradadır ve "işaretli alanları düzeltin" özeti çıkar. Saat 09:30 olur; 31.02 "Geçersiz tarih" der; uzun başlık sessizce kesilmez, sayaç kırmızı olur ve gönderilmez; Acil'e yeniden dokunmak e-posta tercihini ezmez. Taşma yoktur.
- [ ] **61.13. Aynı Sitede Görevli ve Sakin:**
  - **Nasıl Test Edilir:** Aynı sitede hem görevli rolü hem dairesi olan hesapla giriş yapın.
  - **Beklenen Sonuç:** "Duyurular" menüsü, rozet, bildirim ve tercih bölümü çalışır (kapı erişimi olan görevli sakin sayılır). Yalnız görevli (dairesi/kapı erişimi olmayan) hesapta yoktur.
- [ ] **61.14. (Geliştirici) Gerçek Veritabanı ve Yarış Doğrulaması:**
  - **Nasıl Test Edilir:** server klasöründe `node scripts/qa_platform_pg.mjs` komutunu `QA_CONFIRM_DISPOSABLE_DB=yes` ile çalıştırın.
  - **Beklenen Sonuç:** Yedi bölüm yeşil (≈771 kontrol): migrate zinciri = ensureDbSchema, kitle kuralları, yayın yarışları, IDOR/rol matrisi, e-posta kuyruğu (tercih, acil, sınırlar, bastırma, geri çekme yarışı), kilit turları (yayın × yapı değişikliği dahil, 40P01=0), 3000 daireli sitede yayın ≈250 ms.
- [ ] **61.15. (Operasyon) Gizli Anahtar, Genel Uç ve Dağıtım:**
  - **Nasıl Test Edilir:** Sunucu .env'e güçlü rastgele ANNOUNCEMENT_EMAIL_SECRET (≥ 16 karakter) ekleyin (ilk e-postadan önce; değiştirilirse eskisini ANNOUNCEMENT_EMAIL_SECRET_PREVIOUS'a yazın); PUBLIC_APP_URL/PUBLIC_BASE_URL kökünü doğrulayın; `curl -i "https://api.gudeteknoloji.com.tr/public/announcement-unsubscribe?t=x"`; pm2 loglarına bakın.
  - **Beklenen Sonuç:** Tanımsız/zayıf sır için açılışta `[ENV] UYARI` görünür; sır tanımlıyken görünmez. Geçersiz belirteçli istek 400 ve "Bağlantı geçersiz" sayfası (CSP başlıklarıyla) döner. Kök yanlışsa e-postadaki bağlantı ölüdür. Loglarda e-posta adresi/başlık yoktur, erişim logunda `?t=***` maskelidir.
- [ ] **61.16. Eski Ekranlar ve Kapı Açma Etkilenmedi:**
  - **Nasıl Test Edilir:** Duyuru özelliği gelmişken kapı açma, QR, misafir bağlantısı, Kişiler ve Modüller ekranlarını kısaca kullanın.
  - **Beklenen Sonuç:** Hiçbiri değişmeden çalışır. Modüller ekranında "Duyuru ve Bildirim" "Her sitede açık" görünür.

---

## 62. 📝 Site Yöneticisi Olma — Site Başvurusu ve Süper Kullanıcı Onayı (2026-10-16)

Bireysel kullanıcı site için başvurur; süper kullanıcı onaylayınca site kurulur ve kişi site yöneticisi olur. SmartKeyPass cihazı şart değildir (isteğe bağlı); cihaz sahiplenmek yönetici yapmaz. İleride ödeme/abonelik bu onayın yerini alacak (altyapı hazır, ödeme yok). Sözleşme: `docs/PLATFORM_SITE_BASVURUSU.md` (sondaki kararlar öncelikli). Mevcut sahibi olduğu sitesi olan yöneticinin "Site Ekle"si ve süper kullanıcının site kurması anlık kalır.

- [ ] **62.1. Bireysel Başvuru (Cihaz Şartı Yok):**
  - **Nasıl Test Edilir:** Cihazı OLMAYAN bir bireysel hesapla giriş yapın; ana ekranda "Site Kurmak İçin Başvur"a dokunun; site adı, şehir/ilçe, blok ve daire sayılarını girip "Başvuruyu Gönder".
  - **Beklenen Sonuç:** "Başvurunuz alındı. Süper kullanıcı onayladığında site yöneticisi olacaksınız." çıkar; cihaz istenmez. Hesap hâlâ bireyseldir, yönetici ekranları açılmaz. Üstte "Site başvurunuz inceleniyor" kartı görünür.
- [ ] **62.2. Başvuru Kartı, İptal ve Yinelenen Başvuru:**
  - **Nasıl Test Edilir:** Bekleyen başvuruyla ana ekrana bakın; ikinci cihazdan aynı hesapla başvurmayı deneyin; "Başvuruyu iptal et"e basıp onaylayın; kartı ve "Yeniden başvur"u görün. İnterneti kapatıp ekranı açın.
  - **Beklenen Sonuç:** Bekleyen başvuruda yeni başvuru düğmesi pasiftir ve nedeni yazılır; ikinci cihazdan başvuru formu kapanır ve bekleyen kart görünür. İptalden sonra "iptal ettiniz" kartı + "Yeniden başvur". Ağ yokken "durum alınamadı • Tekrar Dene" çıkar, "başvuru yok" yazmaz.
- [ ] **62.3. Süper Kullanıcı: Site Başvuruları:**
  - **Nasıl Test Edilir:** Süper kullanıcıyla giriş yapın; çekmecede "Site Başvuruları" ve rozeti görün; liste, durum süzgeci, arama; bir başvurunun ayrıntısını açın; 12'den fazla bloklu başvuruda "Tümünü göster"e basın.
  - **Beklenen Sonuç:** Başvuran, site, blok/daire/kapı sayısı, tarih ve durum görünür; ayrıntıda başvuranın iletişimi, bloklar/kapılar, not ve cihaz durumu vardır. Rozet bekleyen sayısını gösterir (hesabı silinmiş başvuranlar sayılmaz). Sıradan kullanıcıda bu ekran yoktur.
- [ ] **62.4. Onay: Site Kurulur ve Başvuran Yönetici Olur:**
  - **Nasıl Test Edilir:** Süper kullanıcıyla başvuruyu "Onayla" (onay özetini okuyun). Başvuranın uygulaması açıkken bekleyin (en geç ~30 sn); başvuran hesapta çekmece ve Site Yönetimi'ne bakın.
  - **Beklenen Sonuç:** Site bloklar, daireler ve kapılarla kurulur; başvuran sayfa yenilemeden "Artık site yöneticisisiniz" iletisini alır ve yönetici görünümüne geçer. İkinci onay "zaten sonuçlandı" der. Başvuruda seçilen cihaz hâlâ başvuranındaysa 1. kapıya bağlanır; değilse cihazsız kurulur ve iletişim bunu söyler.
- [ ] **62.5. Red, Gerekçe ve Yeniden Başvuru:**
  - **Nasıl Test Edilir:** Süper kullanıcı başka bir başvuruyu gerekçeyle reddetsin (gerekçe 300 karakterle sınırlı; 301'de düğme kapanır); başvuran kartı okuyup "Yeniden başvur"a bassın.
  - **Beklenen Sonuç:** Başvuranda "reddedildi" kartı ve gerekçe görünür (gerekçe/not başvurana açıktır, arayüz bunu yazar); form önceki değerlerle açılır. Hesabı silinmiş başvuranda "Onayla" pasiftir, yalnız "Reddet" çalışır.
- [ ] **62.6. Cihaz Sahiplenmek Yönetici Yapmaz:**
  - **Nasıl Test Edilir:** Cihazı olan bireysel hesapla "Cihaz Ekle"; çıkan "Cihaz Eklendi" penceresinde "Site Kur"a dokunun. Menülerde/kartlarda "Yönetici Olarak Cihaz Ekle", "Cihaz Ekleyerek Site Yöneticisi Ol", "SITE_OWNER", "AHBU" metinlerini arayın.
  - **Beklenen Sonuç:** Rol bireysel kalır; "Site Kur" başvuru formunu cihaz seçili açar; "Daha Sonra" form açmaz. Aranan metinlerin hiçbiri görünmez.
- [ ] **62.7. Kendi Sitesi Olmayan Yönetici Başvurur:**
  - **Nasıl Test Edilir:** Bir yöneticinin davet ettiği (kendi sitesi olmayan) hesapla Site Yönetimi'ndeki yeni site düğmesine bakın; sahibi olduğu sitesi olan bir yöneticiyle aynı düğmeye bakın; süper kullanıcıyla bakın.
  - **Beklenen Sonuç:** Davetle yönetici olanda düğme "Site Başvurusu" olur ve başvuru akışı çalışır (onaydan sonra "Yeni Site" anlık açılır). Kendi sitesi olan yöneticide "Yeni Site" anlıktır ve eskisi gibi çalışır. Süper kullanıcı etkilenmez. Sunucuda sahip bağı kalkmış bayat ekranda anlık gönderim "başvuru yapmanız gerekiyor" der ve form başvuru kipine geçer.
- [ ] **62.8. Ödeme Altyapısı: Yakında:**
  - **Nasıl Test Edilir:** Başvuru formunda ve ana ekran kartında "Abonelikle hemen site aç" satırına bakın; sunucuda `SELECT code,is_active FROM subscription_plans; SELECT * FROM platform_settings;` çalıştırın.
  - **Beklenen Sonuç:** "Yakında…" pasif satırı vardır, ödeme alınmaz. Tohumlar: `manual_approval` açık, `standard` kapalı, ayar `{"mode":"approval"}`. Onaylanan her yeni site `site_subscriptions` satırı alır (`manual_approval`); eski siteler satırsızdır.
- [ ] **62.9. Sınırlar ve Girdi Güvenliği:**
  - **Nasıl Test Edilir:** Kısa sürede çok başvuru gönderip iptal edin; site adına sıfır genişlikli/yön değiştiren karakter ve 150 emoji yapıştırın; 60 karakterden uzun blok adı yazın; nota 501 karakter yazın.
  - **Beklenen Sonuç:** Son 24 saatte en fazla 5 başvuru (aşılırsa Türkçe mesaj). Tehlikeli/görünmez karakterler temizlenir, uzun adlar sınırda kesilir, 500 üstü not reddedilir; uygulama ve sunucu hata vermez.
- [ ] **62.10. E-posta ve Denetim:**
  - **Nasıl Test Edilir:** Yeni başvuru gönderin ve süper kullanıcının e-postasına bakın; onay/redden sonra başvuranın e-postasına bakın; süper kullanıcıyla Denetim Kaydı'nda eylem süzgecini kullanın.
  - **Beklenen Sonuç:** Süper kullanıcıya "yeni site başvurusu" e-postası gelir (başvuranın e-posta/telefonu yoktur); başvurana sonuç e-postası gider. Denetimde başvuru olayları Türkçe etiketlidir; not/gerekçe metni ve e-posta adresi denetim kaydında yoktur.
- [ ] **62.11. Küçük Ekran, Klavye ve Ekran Okuyucu:**
  - **Nasıl Test Edilir:** Yazı boyutunu en büyüğe alıp telefonu yatay çevirerek klavye açıkken başvuru formunu doldurun; TalkBack/VoiceOver ile başarı ekranını ve silme düğmelerini dolaşın.
  - **Beklenen Sonuç:** Taşma yoktur, "Başvuruyu Gönder"e ulaşılır; başarıda odak başlığa gelir ve "Başvurunuz alındı" okunur; silme düğmeleri "Bloğu sil: A Blok" gibi okunur; iptal/yenile/429 sonrası durum duyurulur.
- [ ] **62.12. (Geliştirici) Gerçek Veritabanı Doğrulaması:**
  - **Nasıl Test Edilir:** server klasöründe `node scripts/qa_platform_pg.mjs` komutunu `QA_CONFIRM_DISPOSABLE_DB=yes` ile çalıştırın.
  - **Beklenen Sonuç:** Sekiz bölüm yeşil (≈1000 kontrol): site_applications bölümünde şema eşitliği, başvuru→onay→site/rol/abonelik, ROLLBACK (11 hata noktası), çift başvuru/çift onay yarışları, sahip bağı kuralı, IDOR/rol matrisi, güvenli metin, 40P01 = 0.
- [ ] **62.13. (Operasyon) Dağıtım Doğrulaması:**
  - **Nasıl Test Edilir:** Sunucuda: `SELECT count(*) FROM site_applications;` (0), `SELECT count(*) FROM site_subscriptions;` (0, mevcut sitelere satır yazılmaz), `\d site_manager_sites` (link_source sütunu), pm2 logunda DDL hatası ve `?q=***` maskesi.
  - **Beklenen Sonuç:** Tablolar boş, `link_source` sütunu vardır, mevcut yönetici bağları NULL (sahip sayılır) olduğundan canlıdaki yönetici "Site Ekle"yi anlık kullanmaya devam eder. Eski uygulama sürümü bireysel "Site Kur"da 409 alır, bu yüzden yeni uygulama sürümü sunucuyla birlikte yayınlanmalıdır.

---

## 63. 💰 Aidat ve Finans — Faz 4a: Tanım, Borçlandırma, Tahsilat, Düzeltme, Ay Kapatma (2026-10-16)

Siteye göre açılıp kapanan finans modülü (varsayılan KAPALI). Para tamsayı kuruş; defter eklemelidir (silme yok, ters kayıt). Sözleşme: `docs/PLATFORM_FINANS.md` (sonundaki kararlar öncelikli). Bu sürümde makbuz, gecikme tazminatı, gider, kasa/banka, raporlar ve borç hatırlatma YOK (Faz 4b); online ödeme ve banka bağlantısı "Yakında…".

- [ ] **63.1. Modül Varsayılan KAPALI; Açma ve Talep:**
  - **Nasıl Test Edilir:** Aidat ve Finans kapalı bir test sitesinde yönetici ve sakin hesabıyla çekmeceye bakın; yöneticiyle Modüller → "Aidat ve Finans" → "Modül Talep Et"; süper kullanıcıyla talebi onaylayın ya da doğrudan açın; yeniden bakın; modülü kapatın.
  - **Beklenen Sonuç:** Kapalıyken "Finans" ve "Borcum" yoktur ("Modül Talep Et" görünür, yönetici kendi açamaz). Açılınca yöneticide "Finans", alıcısı olan sakinde "Borcum" çıkar; kapatınca kalkar, veriler silinmez. Canlıda mevcut siteler açılışta etkilenmez (varsayılan kapalı).
- [ ] **63.2. Aidat Tanımı ve Para Girişi:**
  - **Nasıl Test Edilir:** Finans → Tanımlar → Yeni Tanım: "Aylık aidat", aylık, her ayın 15'i, sabit tutar; tutar alanına 1.250,50 yazın; 1,250 ve 12₺50 ve 1,5E3 deneyin; dağıtım yöntemlerini (sabit, eşit pay, daire tipine göre, arsa payı, m²) ve hedefi (tüm site/bloklar/daireler) gezin.
  - **Beklenen Sonuç:** Tutar altında okunuşuyla gösterilir (1.250,50 ₺); 1,250 / 12₺50 / 1,5E3 görünür hata verir, alan sessizce değişmez. Tutarı kimin ödeyeceği tanımda yoktur: dairenin "borç ve bildirimler kime gitsin" ayarına uyar. Borçlandırılmış tanımın tutarı/dağıtımı değişmez.
- [ ] **63.3. Önizlemeli Borçlandırma:**
  - **Nasıl Test Edilir:** Aylık tanımda "Borçlandır" → dönem seç → önizleme listesi → "Onayla ve Borçlandır"; sonra Daireler'e bakın; aynı dönemi tekrar önizleyin.
  - **Beklenen Sonuç:** Önizleme anında hiçbir borç yazılmaz. Onaydan sonra her aktif daireye borç düşer; toplam önizlemedekiyle aynı (paylar kuruşuna kadar tutar). Aynı dönem ikinci kez borçlandırılamaz; onay pasiftir ve nedeni yazar.
- [ ] **63.4. Eksik Bilgi ve Yeniden Dağıtım:**
  - **Nasıl Test Edilir:** Arsa payına göre ek borç yazın (toplam 60.000 ₺), bir dairenin arsa payını boş bırakın; önizlemeye, "eksik daireleri atla" seçeneğine ve toplama bakın.
  - **Beklenen Sonuç:** "N dairenin bilgisi eksik" ve nedeni görünür; atla işaretlenmeden onay açılmaz. Atlananın payı kalanlara yeniden paylaştırıldığı onaydan önce yazılır; toplam tam 60.000,00 ₺. Arsa payı 0 olan daire eksik sayılmaz (satır almaz).
- [ ] **63.5. Ek Borç ve Tekrar Koruması:**
  - **Nasıl Test Edilir:** "Ek Borç Ekle"yi kaydedin; hemen aynısını yeniden kaydetmeyi deneyin; bağlantıyı kesip tekrar deneyin.
  - **Beklenen Sonuç:** Aynı ek borç kısa süre önce kaydedilmişse "Aynı ek borç kısa süre önce kaydedilmiş görünüyor" uyarısı çıkar ve çift borç yazılmaz; bilerek "Yine de ekle" dersek bir kez daha yazar. Bağlantı kopmasında çift kayıt oluşmaz.
- [ ] **63.6. Tahsilat, Fazla Ödeme ve Düzeltme:**
  - **Nasıl Test Edilir:** Daire ekstresinden "Tahsilat Ekle" (tutar, tarih, yöntem); borçtan fazla ödeyin; yanlış tahsilatı "Düzelt" ile düzeltin; bir borç satırını "İptal Et" (özet ve neden onayı).
  - **Beklenen Sonuç:** Bakiye düşer, fazlası alacak olur. Düzeltme tek adımda ters kayıt + yeni tahsilattır; eski kayıt "İptal edildi" rozetiyle kalır, silinmez. İkinci iptal ve ters kaydın iptali reddedilir. Gelecek ve 5 yıldan eski tarih reddedilir.
- [ ] **63.7. Ay Kapatma:**
  - **Nasıl Test Edilir:** Dönemler sekmesinde "Kapatılacak ay" listesinden bir ay seçip kapatın; o aya ve öncesine tahsilat/borç eklemeyi deneyin; sonraki ayı kapatın; süper kullanıcıyla "Yeniden Aç".
  - **Beklenen Sonuç:** Seçilen ay ve öncesi değiştirilemez olur (kayıt eklenemez); sonraki kapatma sırayla bir sonraki aydır; ters kayıt açık dönemde yazılır. Yeniden açmayı yalnız süper kullanıcı yapar ve yalnız en son kapatılanı açar; yönetici "Yeniden Aç" görmez.
- [ ] **63.8. Önizleme Sonrası Veri Değişimi:**
  - **Nasıl Test Edilir:** Önizleme açıkken başka cihazdan bir dairenin arsa payını ya da "kim öder" ayarını değiştirin; ilk cihazda "Onayla"ya basın.
  - **Beklenen Sonuç:** "Veriler değişti, önizleme yenilendi" uyarısı ve yeni toplam çıkar; eski önizlemeyle yazılmaz, yeni toplamı görüp tekrar onaylarsınız.
- [ ] **63.9. Yönetim Kurulu: Salt Okunur:**
  - **Nasıl Test Edilir:** Kurul üyesi hesabıyla Finans'ı açın; bakiyelere, ekstreye ve tanımlara bakın; tahsilat/borç eklemeyi deneyin.
  - **Beklenen Sonuç:** Bakiyeler ve ekstre görünür; hiçbir yazma düğmesi yoktur ("yalnızca görüntüleyebilirsiniz"); kaydı yapan kişi ve yönetici notu görünmez. Görevli hesapta Finans yoktur.
- [ ] **63.10. Sakin: Borcum:**
  - **Nasıl Test Edilir:** Sakin hesabıyla "Borcum"u açın; kiracı/malik/aile üyesi hesaplarıyla ve "borç kime gitsin" ayarının üç değeriyle deneyin; interneti kapatıp yenileyin; sıfır bakiyede bakın.
  - **Beklenen Sonuç:** Toplam borç/alacak, vadesi gelen, sıradaki vade ve hareketler görünür; yalnız kendi dairesi. Borç ayara uyar (malik/kiracı/ikisi); aile üyesi görmez. Hata ve yükleme durumunda "Borcunuz yok" DENMEZ; yalnız gerçekten sıfırken yazılır. Yönetici notu, iptal nedeni ve kaydeden adı görünmez.
- [ ] **63.11. Mali Kaydı Olan Daire Silinemez:**
  - **Nasıl Test Edilir:** Borçlandırılmış sitede daire sayısını azaltmayı deneyin (hem mali kaydı olan hem olmayan daireler için).
  - **Beklenen Sonuç:** "Mali kaydı olan daire silinemez" uyarısı çıkar ve hiçbir daire silinmez; mali kaydı olmayan dairelerde azaltma eskisi gibi çalışır.
- [ ] **63.12. Denetim Kaydı:**
  - **Nasıl Test Edilir:** Süper kullanıcıyla Denetim Kaydı → eylem süzgeci: tanım, borçlandırma, tahsilat, ters kayıt, ay kapatma/açma.
  - **Beklenen Sonuç:** Finans olayları Türkçe etiketlidir ("Tahsilat kaydedildi", "Ay kapatıldı"…); dönem/tutar sayıları vardır, açıklama/neden metni ve kişi adı yoktur.
- [ ] **63.13. Küçük Ekran, Klavye ve Ekran Okuyucu:**
  - **Nasıl Test Edilir:** Yazı boyutunu en büyüğe alıp telefonu yatay çevirerek tahsilat ve borçlandırma pencerelerini açın; TalkBack/VoiceOver ile sekmeleri, tutarları ve "Onayla" düğmesini dolaşın.
  - **Beklenen Sonuç:** Taşma yoktur; hata uyarısı görünür bölgededir; tutarlar tek kez ve sözcüklerle okunur ("bin iki yüz elli lira"); sekmeler "sekme, seçili" diye okunur; pasif "Onayla"nın nedeni okunur.
- [ ] **63.14. (Geliştirici) Gerçek Veritabanı Doğrulaması:**
  - **Nasıl Test Edilir:** server klasöründe `node scripts/qa_platform_pg.mjs` komutunu `QA_CONFIRM_DISPOSABLE_DB=yes` ile çalıştırın (PG 16 ve 18).
  - **Beklenen Sonuç:** finance bölümü ≈278 kontrol yeşil: dağıtım toplam eşitliği, append-only defter, idempotans ve parmak izi, ay kapatma sırası, ters kayıt, yarışlar (40P01 = 0), 034'ün canlı benzeri şemada eşzamanlı uygulanması. Not: PG 16'da eski `people/T6` EXPLAIN kontrolü kırmızıdır (finans dışı).
- [ ] **63.15. (Operasyon) Dağıtım Doğrulaması:**
  - **Nasıl Test Edilir:** Sunucuda: `\d ledger_entries`, `SELECT tgname FROM pg_trigger WHERE tgname LIKE 'trg_ledger%' OR tgname LIKE 'trg_fee_runs%'`, `SELECT count(*) FROM site_modules WHERE module_code='finance' AND enabled`.
  - **Beklenen Sonuç:** Tablolar ve 6 değişmezlik tetikleyicisi vardır; `finance` açık site sayısı 0 (varsayılan kapalı). Dağıtım trafiksizken yapılır (açılış DDL'i yoğun yazma altında 40P01 alabilir; yeniden başlatma yeter).

---

## 64. 🧾 Hesabım: Verilerimi İndir ve Hesabımı Sil (2026-10-16)

Kullanıcı kendi kişisel verisinin kopyasını JSON olarak indirir ve hesabını kendisi siler (KVKK erişim ve silme hakları). Silme geri alınamaz: hesap satırı kimliksizleştirilir ("Silinmiş Kullanıcı"), üyelikler, kapı yetkileri ve oturumlar kalkar, site yönetiminin yasal saklama kayıtları kalır. Sözleşme: `docs/PLATFORM_SATISA_HAZIRLIK.md` §1.5 (veri dışa aktarma) ve §1.6 (hesap silme); yasal metin `server/legal/account_deletion.md`. Bu bölüm satışa hazırlık sunucu sürümü (migration 035 ve 036) canlıdayken denenir; silme adımlarını yalnız silinmesinde sakınca olmayan TEST hesaplarıyla yapın.

- [ ] **64.1. Gizlilik ve Veri Bölümü Her Rolde Görünür:**
  - **Nasıl Test Edilir:** Bireysel kullanıcı, daire sakini, site yöneticisi ve süper kullanıcı hesaplarıyla sırayla çekmeceden "Profilim"i açın. Sayfanın en altına kaydırın.
  - **Beklenen Sonuç:** Her rolde "Gizlilik ve Veri" kartı vardır; altında "Kişisel verilerinizin bir kopyasını alabilir veya hesabınızı kalıcı olarak silebilirsiniz." yazar ve iki blok görünür: "Verilerimi İndir" ve "Hesabımı Sil" (her birinin açıklaması ve tam genişlikte düğmesiyle).
- [ ] **64.2. Şifre Penceresi: Boş ve Yanlış Şifre:**
  - **Nasıl Test Edilir:** "Verilerimi İndir" düğmesine dokunun ve pencere metnini okuyun. Şifre alanı boşken "Verilerimi Hazırla"ya basın. Yanlış bir şifre yazıp tekrar "Verilerimi Hazırla"ya basın.
  - **Beklenen Sonuç:** "Verilerimi İndir" başlıklı pencere açılır: "Hesabınıza ait kişisel verilerin bir kopyasını JSON dosyası olarak hazırlarız. Devam etmek için şifrenizi girin. Bu işlem 24 saat içinde en fazla 3 kez yapılabilir." Boş şifrede alan altında "Devam etmek için şifrenizi girin." ve "Lütfen işaretli alanları düzeltin." görünür. Yanlış şifrede pencere AÇIK kalır, hata kutusunda "Mevcut şifreniz hatalı. Lütfen kontrol edip tekrar deneyin." yazar ve şifre alanı temizlenir; dosya hazırlanmaz, oturum kapanmaz. "Vazgeç" pencereyi kapatır.
- [ ] **64.3. Doğru Şifre: Veri Dosyası Hazırlanır ve Paylaşılır:**
  - **Nasıl Test Edilir:** "Verilerimi İndir"de doğru şifreyi yazıp "Verilerimi Hazırla"ya basın. Açılan telefon paylaşım menüsünden dosyayı "Dosyalar"a/Drive'a kaydedin ya da kendi e-postanıza gönderin.
  - **Beklenen Sonuç:** Düğmede "Hazırlanıyor..." görünür, ardından paylaşım menüsü açılır. Ekranda yeşil bildirim çıkar: "Veri dosyanız hazır: kisisel-veri-<kullanıcı kodu>-<YYYYAAGG>.json (<boyut>). Dosya kişisel verilerinizi içerir; güvenli bir yerde saklayın ve başkalarıyla paylaşmayın." Dosya adındaki tarih İstanbul gününe göredir.
- [ ] **64.4. Paylaşım Menüsü Kapatılırsa Dosya Kartı Kalır:**
  - **Nasıl Test Edilir:** Önkoşul: Bir önceki maddedeki hazır dosya kartı. Paylaşım menüsünü bir şey seçmeden kapatın. Kart üzerindeki "Paylaş / Kaydet"e dokunun. İşiniz bitince "Kapat (dosyayı bellekten at)"a dokunun.
  - **Beklenen Sonuç:** Menü kapansa da dosya kartı ekranda kalır; "Paylaş / Kaydet" menüyü yeniden açar (şifre yeniden sorulmaz, yeni indirme hakkı harcanmaz). "Kapat (dosyayı bellekten at)" kartı kaldırır; dosyayı yeniden almak için "Verilerimi İndir" ve şifre gerekir. Menü açılamazsa "Paylaşım menüsü açılamadı. Dosya hazır; "Paylaş / Kaydet" ile yeniden deneyebilirsiniz." uyarısı çıkar.
- [ ] **64.5. Dosya İçeriği: Yalnız Kendi Verim:**
  - **Nasıl Test Edilir:** Kaydettiğiniz JSON dosyasını bilgisayara aktarıp bir metin düzenleyicide açın. Üstteki alanlara ve "excluded" listesine bakın; "password_hash" sözcüğünü aratın.
  - **Beklenen Sonuç:** Dosyada "format_version", "generated_at", "notice", "user", "memberships", "consents", "finance_statements", "door_events" ve "excluded" gibi alanlar vardır; kendi ad ve e-postanız "user" içindedir. "excluded" listesi dışarıda bırakılanları Türkçe açıklar (parola özeti ve belirteçler, aynı dairedeki başkalarının kişisel bilgileri, yönetici iç notları, cihaz sırları). "password_hash" bulunmaz; başka bir kişinin adı, telefonu ya da e-postası görünmez. Çok büyük veride bölümler kısaltılır ve "truncated": true ile "truncated_sections" yazılır (sessiz kayıp yok).
- [ ] **64.6. Dışa Aktarma Şifre Kilidi (5 Yanlış Şifre):**
  - **Nasıl Test Edilir:** Önkoşul: Test hesabı (kilit, Profilim'deki şifre değişikliği ve hesap silme ile ORTAK bütçedir). "Verilerimi İndir"de art arda 5 kez yanlış şifre girin. Hemen ardından doğru şifreyi yazın.
  - **Beklenen Sonuç:** 5. denemede "Mevcut şifre için çok fazla hatalı deneme yapıldı. 15 dakika sonra tekrar deneyin." çıkar ve gönder düğmesi kısa süre pasif olur; kilit sürerken doğru şifre de reddedilir. Yaklaşık 15 dakika sonra (ya da "Şifremi Unuttum?" ile şifre sıfırlanınca) yeniden çalışır.
- [ ] **64.7. Günlük Sınır: 24 Saatte En Fazla 3 Dışa Aktarma:**
  - **Nasıl Test Edilir:** Önkoşul: Aynı hesapla 24 saat içinde 3 başarılı dışa aktarma yapılmış olmalı. Aynı hesapla dördüncü kez "Verilerimi İndir"i açıp doğru şifreyi girin.
  - **Beklenen Sonuç:** "Kişisel veri dışa aktarma sınırına ulaştınız (24 saatte en fazla 3). Daha sonra tekrar deneyin." çıkar; dosya hazırlanmaz. Sınır kullanıcı başınadır; başka hesap etkilenmez.
- [ ] **64.8. Silme Sayfası: Neler Silinir, Neler Saklanır:**
  - **Nasıl Test Edilir:** Önkoşul: Silinmesinde sakınca olmayan TEST hesabı (feda edilebilir). "Hesabımı Sil" düğmesine dokunun. Sayfayı sonuna kadar kaydırıp okuyun.
  - **Beklenen Sonuç:** "Hesabımı Sil" başlıklı sayfada sarı uyarı çıkar: "Hesabınızı silmek geri alınamaz. Devam etmeden önce aşağıda nelerin silineceğini ve nelerin saklanacağını okuyun." Altında "Silinecekler" kartı (hesabınız "Silinmiş Kullanıcı" olur, e-posta/telefon/parola kaldırılır, üyelikler ve kapı yetkileri kalkar, misafir geçişleri ve karekodlar iptal edilir...) ve "Saklanacaklar" kartı (site yönetiminin yasal saklama kayıtları, aidat/borç/ekstre kayıtları, denetim kayıtları...) bulunur. Altta "Silmeye Devam Et" ve "Vazgeç" düğmeleri vardır. İnternet yokken kart yerine hata ve "Tekrar Dene" çıkar; bilgi yüklenmeden silme AÇILMAZ.
- [ ] **64.9. Silme Engeli: Süper Kullanıcı ve Tek Yönetici:**
  - **Nasıl Test Edilir:** Rol: Süper kullanıcı / Site yöneticisi. Önkoşul: Süper kullanıcı hesabı ve aktif üyesi olan bir sitenin TEK yöneticisi olan site yöneticisi hesabı. Süper kullanıcı hesabıyla Profilim → "Hesabımı Sil" sayfasını açın. Aynı sayfayı tek yönetici olan site yöneticisi hesabıyla açın.
  - **Beklenen Sonuç:** Kırmızı "Hesabınız şu anda silinemez" kartı çıkar. Süper kullanıcıda: "Süper kullanıcı hesabı bu ekrandan silinemez. Hesabın kaldırılması için başka bir süper kullanıcıyla iletişime geçin." Site yöneticisinde: "\"<site adı>\" sitesinde aktif üyeler varken tek yöneticisiniz. Önce siteye başka bir yönetici atayın veya siteyi kaldırın." ve "Site kodu: N". "Yukarıdaki engeller kalkmadan hesabınız silinemez." yazar ve "Silmeye Devam Et" PASİF kalır.
- [ ] **64.10. Silme Onayı: SİL Yazma ve Yanlış Şifre:**
  - **Nasıl Test Edilir:** Önkoşul: Silinmesinde sakınca olmayan, engeli olmayan TEST hesabı. "Silmeye Devam Et"e dokunun. Şifre alanına doğru şifreyi yazın, "Onaylamak için SİL yazın" alanını boş bırakıp düğmenin durumuna bakın. Yanlış şifreyle SİL yazıp "Hesabımı Sil"e basın.
  - **Beklenen Sonuç:** "Hesabı kalıcı olarak sil" penceresi açılır: "Bu işlem geri alınamaz. Hesabınız silinecek ve oturumunuz kapanacak. Onaylamak için şifrenizi girin ve SİL yazın." SİL yazılmadan "Hesabımı Sil" düğmesi pasiftir ve alanın altında "SİL yazdığınızda düğme açılır." görünür (büyük/küçük harf ve SIL/SİL ayrımı gözetilmez). Yanlış şifrede "Mevcut şifreniz hatalı. Lütfen kontrol edip tekrar deneyin." çıkar ve hesap SİLİNMEZ.
- [ ] **64.11. Hesap Silinir, Aynı E-postayla Yeniden Kayıt Olunur:**
  - **Nasıl Test Edilir:** Önkoşul: Silinmesinde sakınca olmayan TEST hesabı; e-posta kodu alınabilen adres. Doğru şifre ve SİL ile "Hesabımı Sil"e basın. Giriş ekranındaki bilgi mesajını okuyun. Silinen hesabın eski e-posta ve şifresiyle giriş yapmayı deneyin. Birkaç dakika sonra o adresin e-posta kutusuna bakın. "Yeni Hesap Oluştur" ile aynı e-posta adresiyle kayıt başlatın.
  - **Beklenen Sonuç:** "Siliniyor..." sonrası giriş ekranına dönülür ve yaklaşık 8 saniye "Hesabınız silindi ve bu cihazdaki verileriniz temizlendi. İsterseniz aynı e-posta adresiyle yeniden kayıt olabilirsiniz." bildirimi görünür; giriş alanında eski e-posta kalmaz. Eski bilgilerle giriş reddedilir. E-posta kutusuna "Site ve Toplu Yaşam Yönetim Sistemi - Hesabınız Silindi" konulu bilgilendirme gelir (SMTP'ye bağlı, gecikebilir). Aynı e-postayla kayıt "zaten kayıtlı" denmeden kabul edilir ve 6 haneli doğrulama kodu gelir; eski hesabın üyelikleri yeni hesaba geçmez.
- [ ] **64.12. (Geliştirici) Hesap Silme ve Veri Dışa Aktarma Sunucu Doğrulaması:**
  - **Nasıl Test Edilir:** server klasöründe `node --test test/account_routes.test.js test/account_deletion_service.test.js test/account_export_service.test.js test/account_password_guard.test.js` çalıştırın. Proje kökünde `flutter test test/screens/account_deletion_view_test.dart test/screens/account_privacy_section_test.dart test/account_api_test.dart test/account_models_test.dart test/account_local_wipe_test.dart test/account_export_share_test.dart` çalıştırın. Tek kullanımlık yerel PostgreSQL ile server klasöründe `DB_HOST=127.0.0.1 DB_PORT=55432 DB_USER=postgres DB_PASSWORD= QA_CONFIRM_DISPOSABLE_DB=yes QA_ONLY=account node scripts/qa_platform_pg.mjs` çalıştırın (üretimde ÇALIŞTIRMAYIN).
  - **Beklenen Sonuç:** Testler yeşil; `account` bölümü yeşil: dışa aktarma sızdırma yok (parola özeti/belirteç/başkasının verisi çıkmaz), 24 saatte 3 sınırı paralel isteklerde de tutar ve üretim hatasında hak iade edilir, silme tek işlemdedir (kimliksizleştirme, yarışlar, kimliksiz denetim kaydı `account.deleted`), 40P01 = 0.

---

## 65. 📜 Yasal Metinler ve Onaylar — Kayıt Onayı, Belge Okuma, Güncellenen Koşullar, Web Sayfaları (2026-10-16)

Kayıt ve site başvurusunda yasal onay kutusu, belge okuma ekranı, giriş ekranı altındaki bağlantılar, "Güncellenen Koşullar" kapısı ve sunucunun `/legal/...` web sayfaları. Beş belge (Kullanım Koşulları, Gizlilik Politikası, KVKK Aydınlatma Metni, Veri İşleme Sözleşmesi, Hesap ve Veri Silme) şimdilik `complete: false` (taslak) gelir: hukuk incelemesi (`docs/yasal/AVUKAT_KONTROL_LISTESI.md`) ve şirket bilgileri (Platform Ayarları → "Şirket ve Yasal Bilgiler") bitene dek sarı "taslak" uyarısı görünür; bu yüzden sunucu tarafı onay kaydı ve "Güncellenen Koşullar" kapısı henüz devrede değildir. Sözleşme: `docs/PLATFORM_SATISA_HAZIRLIK.md` §1.4; metinler `server/legal/*.md`; açık maddeler `docs/yasal/KULLANICIDAN_GEREKENLER.md`.

- [ ] **65.1. Kayıt Formunda Yasal Onay Kutusu:**
  - **Nasıl Test Edilir:** Rol: Bireysel kullanıcı. Çıkış yapın; giriş ekranında "Yeni Hesap Oluştur"a dokunun. Ad, Soyad, E-Posta ve geçerli şifre alanlarını doldurun ama onay kutusunu işaretlemeyin. Formu aşağı kaydırıp "Kayıt Ol" düğmesine ve üstündeki yazıya bakın; sonra kutuyu işaretleyin.
  - **Beklenen Sonuç:** Formda "Kullanım Koşulları, Gizlilik Politikası ve KVKK Aydınlatma Metni'ni okudum." etiketli kutu ve altında üç bağlantı düğmesi vardır: "Kullanım Koşulları metnini oku", "Gizlilik Politikası metnini oku", "KVKK Aydınlatma Metni metnini oku". Kutu işaretlenmeden "Kayıt Ol" pasiftir ve üstünde "Devam etmek için belgeleri okuyup onay kutusunu işaretleyin." yazar; işaretleyince düğme açılır. Belgeler yüklenirken "Belgeler yükleniyor..." görünür.
- [ ] **65.2. Belge Okuma Ekranı:**
  - **Nasıl Test Edilir:** Kayıt formunda "Gizlilik Politikası metnini oku"ya dokunun. Başlığa, çiplere ve gövdeye bakın; sonuna kadar kaydırın; geri dönün.
  - **Beklenen Sonuç:** Ekran başlığı "Gizlilik Politikası" olur; "Sürüm: 2026-10-16" ve "Yürürlük: 16.10.2026" çipleri görünür (değerler belge sürümüne göre değişir); metin başlık, liste ve kalın yazıyla okunur biçimdedir (tablo yok). Belge tamamlanmamışsa sarı kutuda "Bu belgedeki köşeli parantezli [……] alanlar henüz doldurulmamıştır. Belge taslak niteliğindedir." yazar (hukuk onayı bitene dek BEKLENEN durum). Geri dönünce form alanları ve kutu durumu korunur.
- [ ] **65.3. Giriş Ekranı Altındaki Yasal Bağlantılar:**
  - **Nasıl Test Edilir:** Çıkış yapıp giriş ekranına gelin; en alttaki "Kullanım Koşulları · Gizlilik · KVKK" satırından her bağlantıya sırayla dokunun. Yazı boyutunu en büyüğe alıp aynı satıra tekrar bakın.
  - **Beklenen Sonuç:** Oturum açmadan sırasıyla "Kullanım Koşulları", "Gizlilik Politikası" ve "KVKK Aydınlatma Metni" belgeleri açılır (başlık, sürüm ve yürürlük çipleri görünür). En büyük yazıda bağlantılar alt alta dizilir, taşma olmaz.
- [ ] **65.4. Yardım Ekranında Yasal Belgeler Listesi:**
  - **Nasıl Test Edilir:** Çekmeceden "Yardım ve Destek"i açıp "Yasal belgeler" bölümüne inin. Listedeki her belgeye dokunun.
  - **Beklenen Sonuç:** Beş belge listelenir: Kullanım Koşulları, Gizlilik Politikası, KVKK Aydınlatma Metni, Veri İşleme Sözleşmesi, Hesap ve Veri Silme. Her satırda "Sürüm: … · Yürürlük: …" yazar ve dokununca belge açılır. Liste yüklenemezse "Şu an yayımlanmış bir belge yok." DENMEZ; hata ve "Yeniden dene" görünür.
- [ ] **65.5. Site Başvurusunda Veri İşleme Sözleşmesi Onayı:**
  - **Nasıl Test Edilir:** Rol: Bireysel kullanıcı. Önkoşul: Cihazı olmayan bireysel hesap. "Daireye Katıl & Cihaz Ekle" ekranında "Site Kurmak İçin Başvur"a dokunun. Formu "Not (İsteğe Bağlı)" alanının altına kadar kaydırın. Onay kutusunu işaretlemeden "Başvuruyu Gönder"e bakın; sonra "Veri İşleme Sözleşmesi metnini oku"ya dokunup kutuyu işaretleyin.
  - **Beklenen Sonuç:** Notun altında "Veri İşleme Sözleşmesi'ni okudum ve kabul ediyorum." kutusu ve "Veri İşleme Sözleşmesi metnini oku" bağlantısı vardır. Kutu işaretlenmeden "Başvuruyu Gönder" pasiftir ve nedeni ("Devam etmek için belgeleri okuyup onay kutusunu işaretleyin.") yazar; belge açılır ve kapatılınca form korunur.
- [ ] **65.6. Güncellenen Koşullar Kapısı:**
  - **Nasıl Test Edilir:** Önkoşul: En az bir belge TAMAMLANMIŞ olmalı (hukuk incelemesi bitip belge dosyasındaki `complete: false` satırı kalkmış ve şirket bilgileri doldurulmuş); hesap o belgenin güncel sürümünü daha önce onaylamamış olmalı. Hesapla giriş yapın (ya da uygulamayı kapatıp açın). "Güncellenen Koşullar" ekranında belgenin "metnini oku" düğmesine dokunun, kutuyu işaretleyin ve "Kabul Et ve Devam Et"e basın. Başka bir denemede "Kabul etmiyorum, oturumu kapat"a dokunun.
  - **Beklenen Sonuç:** Ana sayfanın üstüne tam ekran "Güncellenen Koşullar" biner: "Hizmet koşullarımız güncellendi. Uygulamayı kullanmaya devam etmek için aşağıdaki belgeleri okuyup onaylamanız gerekir." Belge satırlarında ad, "Sürüm: …" ve "… metnini oku" bulunur; "Yukarıdaki belgeyi okudum ve kabul ediyorum." kutusu işaretlenmeden "Kabul Et ve Devam Et" pasiftir ("Devam etmek için belgeleri okuyup onay kutusunu işaretleyin."). Kabulden sonra kapı kalkar ve ana sayfa (ilk kullanımda ilk kullanım turu) açılır. "Kabul etmiyorum, oturumu kapat" "Oturum kapatılsın mı?" penceresini açar ("Güncel koşulları kabul etmezseniz uygulamayı kullanamazsınız..."): "Oturumu Kapat" çıkış yapar, "Vazgeç" geri döner. Ağ/sunucu hatasında kullanıcı KİLİTLENMEZ. Belgeler tamamlanmadan bu ekran hiç çıkmaz (sunucu yalnız tamamlanmış belgeyi bekleyen sayar).
- [ ] **65.7. Yasal Web Sayfaları:**
  - **Nasıl Test Edilir:** Telefon tarayıcısında sırayla açın: `https://api.gudeteknoloji.com.tr/legal/privacy`, `/legal/terms`, `/legal/kvkk-notice`, `/legal/dpa`, `/legal/account-deletion`. Olmayan bir adres açın: `/legal/yok`.
  - **Beklenen Sonuç:** Her adres oturumsuz, sade ve telefona uygun bir sayfa açar: üstte belge adı (örn. "Gizlilik Politikası"), altında "Sürüm: 2026-10-16 · Yürürlük tarihi: 2026-10-16". Belge tamamlanmamışsa sarı kutuda "Bu belgede henüz doldurulmamış veya doğrulanmamış bölümler bulunuyor; belge taslak niteliğindedir." görünür (hukuk onayı bitene dek BEKLENEN durum). Olmayan adres "Belge bulunamadı" / "İstediğiniz belge bulunamadı." sayfasını (404) verir. Bu adresler mağaza formlarına yazılacağı için tamamlanmış hâlleri, "Yasal Sayfalar Mağaza İçin Hazır mı (Son Kapı)" maddesindeki son kapıdır.
- [ ] **65.8. Şirket Bilgileri Belgelere Yansır:**
  - **Nasıl Test Edilir:** Rol: Süper kullanıcı. Önkoşul: Şirket unvanı, adres, MERSİS, KEP ve iletişim bilgilerinin gerçek değerleri elinizde. Platform Ayarları → "Şirket ve Yasal Bilgiler" kartında "Şirket unvanı"nı doldurup "Değişiklikleri Kaydet"e basın. Bir dakika bekleyip `https://api.gudeteknoloji.com.tr/legal/privacy` sayfasını yenileyin.
  - **Beklenen Sonuç:** Belgede şirket adının geçtiği yerlerde girdiğiniz unvan görünür; doldurulmayan alanlar (adres, MERSİS, KEP, e-posta, telefon) "[……]" olarak kalır. Sayfa en çok ~60 sn önbellekte tutulabilir. Tüm alanlar dolsa bile belgeler, içlerindeki `[KARAR/BİLGİ GEREKLİ ...]` ve `[AVUKAT DOĞRULASIN ...]` işaretleri çözülüp `complete: false` satırı kalkana dek taslak sayılır.
- [ ] **65.9. (Geliştirici) Yasal Onay Sunucu ve Uygulama Doğrulaması:**
  - **Nasıl Test Edilir:** server klasöründe `node --test test/legal_documents.test.js test/legal_routes.test.js test/legal_consent_service.test.js test/legal_consent_registration.test.js test/legal_real_documents.test.js` çalıştırın. Proje kökünde `flutter test test/legal_consent_test.dart test/legal_gate_test.dart test/legal_document_view_test.dart test/legal_dpa_dialog_test.dart test/legal_markdown_test.dart test/legal_api_test.dart` çalıştırın. Belgeler tamamlanmış ve "Onayları zorunlu kıl" AÇIKken `accepted_documents` göndermeden kayıt isteği yapın.
  - **Beklenen Sonuç:** Testler yeşil. Zorunluluk kapalıyken (varsayılan) eski istemciler çalışır ve yalnız tamamlanmış belgelerin güncel sürümü `user_consents`'a yazılır. Zorunluluk açık ve belge tamamlanmışken eksik/eski onay `400 {"code":"CONSENT_REQUIRED","missing":[...]}`, bayat sürüm `409 CONSENT_VERSION_STALE`, tamamlanmamış belge `409 DOCUMENT_INCOMPLETE` döner. Belgeler tamamlanana dek zorunluluğu açmak fiilen etkisizdir.

---

## 66. 🔑 Giriş Güvenliği ve Parola İlkesi — 8 Karakter, Yaygın Şifre Reddi, Giriş Kilidi, Oturum (2026-10-16)

Yeni, değişen ve sıfırlanan şifre en az 8, en çok 128 karakter (UTF-8'de en çok 72 bayt) olmalı; e-posta/adla aynı ya da yaygın olamaz. Eski şifreler girişte çalışmaya devam eder. Yanlış şifrede hesap × cihaz/IP çifti 5 hatada 15 dk kilitlenir; kilit tekrarında 30 dk, 60 dk, en çok 2 saate uzar. Oturum belirteci 30 gün (en çok 90 gün) yaşar ve parola değişince düşer. Sayaçlar sunucu belleğindedir (yeniden başlatma sıfırlar). Arayüzde bu metinlerde "şifre" denir. Sözleşme: `docs/PLATFORM_SATISA_HAZIRLIK.md` §1.7; kod: `server/src/security/*`, `lib/ui/helpers/password_policy.dart`.

- [ ] **66.1. Kayıtta Kısa Şifre (8 Karakter Kuralı):**
  - **Nasıl Test Edilir:** Rol: Bireysel kullanıcı. "Yeni Hesap Oluştur" formunda Ad, Soyad ve E-Posta'yı doldurun; yasal onay kutusunu işaretleyin. "Şifre" alanının ipucuna bakın; 7 karakterlik "abc1234" yazın, "Şifre Tekrar"a aynısını yazıp "Kayıt Ol"a basın.
  - **Beklenen Sonuç:** "Şifre" alanında "En az 8 karakter" ipucu vardır. 7 karakterde alan altında "Şifre çok kısa: en az 8 karakter olmalı. Birkaç sözcüğü art arda yazabilirsiniz." görünür ve kayıt gönderilmez (e-posta kodu istenmez).
- [ ] **66.2. Yaygın Şifre Reddi:**
  - **Nasıl Test Edilir:** Rol: Bireysel kullanıcı. Aynı formda şifre olarak sırayla "12345678", "password1", "Fenerbahce1907" ve "sifre2024" yazıp (Şifre Tekrar aynı) "Kayıt Ol"a basın. Sonra "Mavi-Balon-Kapi-2026" gibi uzun ve özgün bir ifade deneyin.
  - **Beklenen Sonuç:** İlk dört şifrenin her biri "Bu şifre çok yaygın ve kolay tahmin edilir. Daha özgün bir şifre seçin." hatasını verir. Özgün ifade şifre alanında hata vermez ve kayıt ilerler (e-posta doğrulama kodu ekranı).
- [ ] **66.3. E-posta ya da Adla Aynı Şifre Reddi:**
  - **Nasıl Test Edilir:** Rol: Bireysel kullanıcı. E-Posta alanına ornek.kisi@example.com, Ad'a "Deneme", Soyad'a "Kullanici" yazın. Şifre olarak sırayla "ornek.kisi@example.com", "ornekkisi" ve "Deneme Kullanici" yazıp (Şifre Tekrar aynı) her birinde "Kayıt Ol"a basın.
  - **Beklenen Sonuç:** İlk ikisinde "Şifre e-posta adresinizle aynı olamaz. Farklı bir şifre seçin." görünür (büyük/küçük harf, Türkçe harf ve nokta/boşluk farkı yok sayılır). Üçüncüde "Şifre adınızla ya da kullanıcı adınızla aynı olamaz. Farklı bir şifre seçin." görünür.
- [ ] **66.4. Profilim'de Şifre Değiştirme Kuralları:**
  - **Nasıl Test Edilir:** Rol: Site yöneticisi / Bireysel kullanıcı / Süper kullanıcı. Profilim'de "Mevcut Şifre"yi boş bırakıp "Yeni Şifre (opsiyonel)"e özgün bir şifre yazın, "Profili Kaydet"e basın. "Mevcut Şifre"ye doğru şifreyi yazın; "Yeni Şifre (opsiyonel)"e sırayla "1234567" ve "12345678" yazıp kaydetmeyi deneyin. Özgün 8+ karakterli yeni şifreyle kaydedin.
  - **Beklenen Sonuç:** Mevcut şifre yokken "Şifre değiştirmek için mevcut şifrenizi girin." çıkar. Yeni şifre alanında ipucu "En az 8 karakter"dir; "1234567" için "Şifre çok kısa...", "12345678" için "Bu şifre çok yaygın..." hatası görünür. Geçerli şifrede "Profil bilgileri güncellendi." görünür, oturum açık kalır; çıkış yapıp yeni şifreyle girilebilir, eski şifre girmez.
- [ ] **66.5. Şifremi Unuttum: Web Sayfasında Aynı Kurallar:**
  - **Nasıl Test Edilir:** Önkoşul: E-posta kutusuna erişilebilen hesap. Giriş ekranında "Şifremi Unuttum?"a dokunun, e-postayı yazıp "Bağlantı Gönder"e basın; gelen bağlantıyı telefon tarayıcısında açın. "Yeni Şifre" alanına 7 karakter yazıp "Şifremi Güncelle"ye basın; sonra "12345678" deneyin; en sonda özgün bir şifre girin.
  - **Beklenen Sonuç:** Uygulamada "Bu e-posta adresiyle kayıtlı bir hesap varsa şifre sıfırlama bağlantısı gönderildi..." bildirimi çıkar (kayıtlı olmayan adreste de AYNI mesaj). "Yeni Şifre Belirleyin" sayfası 7 karakterde "Şifreniz en az 8 karakter olmalıdır.", eşleşmeyen tekrar için "Girdiğiniz şifreler birbiriyle eşleşmiyor.", yaygın şifre için "Bu şifre çok yaygın ve kolay tahmin edilir. Daha özgün bir şifre seçin." der. Geçerli şifrede "Şifreniz Güncellendi!" görünür; bağlantı ikinci kez kullanılamaz.
- [ ] **66.6. Eski Şifreler Girişte Çalışmaya Devam Eder:**
  - **Nasıl Test Edilir:** Rol: Daire sakini / Hepsi. Önkoşul: Güncellemeden önce kurulmuş, 8 karakterden kısa şifreli bir hesap (örn. 4 haneli şifreli daire sakini hesabı). Bu hesapla giriş yapın.
  - **Beklenen Sonuç:** Giriş SORUNSUZ olur: parola ilkesi yalnız YENİ belirlenen şifrelerde uygulanır, girişte uygulanmaz.
- [ ] **66.7. Giriş Kilidi: 5 Yanlış Şifre:**
  - **Nasıl Test Edilir:** Önkoşul: TEST hesabı (gerçek kullanıcıyı kilitlemeyin); sunucu yeniden başlatılmışsa sayaçlar sıfırdır. Giriş ekranında doğru e-posta ve yanlış şifreyle art arda 5 kez giriş deneyin. Hemen ardından DOĞRU şifreyle girmeyi deneyin. Aynı telefonda başka bir hesapla doğru bilgilerle girin.
  - **Beklenen Sonuç:** İlk 4 denemede giriş reddedilir. 5. denemede "Çok fazla hatalı deneme yapıldı. 15 dakika sonra tekrar deneyin." çıkar (Retry-After ≈ 900 sn). Kilitliyken doğru şifre de aynı iletiyi alır. Başka hesap normal girer (kilit hesap × cihaz/IP çiftine uygulanır).
- [ ] **66.8. Kilit Artar; Şifremi Unuttum Kilidi Açar:**
  - **Nasıl Test Edilir:** Önkoşul: Bir önceki maddedeki kilit bitmiş (≈15 dk) TEST hesabı; e-posta kutusuna erişim. Kilit bitince yeniden 5 kez yanlış şifre girin. İkinci kilit sürerken "Şifremi Unuttum?" ile şifreyi sıfırlayın ve yeni şifreyle girmeyi deneyin.
  - **Beklenen Sonuç:** İkinci kilitte ileti "30 dakika" der (sonraki kilitler 60 dakika, en çok 2 saat; 24 saat hatasız geçince seviye sıfırlanır). Şifre sıfırlama tamamlanınca hesap kilidi açılır ve yeni şifreyle hemen giriş yapılır (kilit süresi beklenmez).
- [ ] **66.9. Şifre Değişince Diğer Cihazın Oturumu Düşer:**
  - **Nasıl Test Edilir:** Rol: Site yöneticisi / Bireysel kullanıcı. Aynı hesapla iki telefonda (A ve B) oturum açın. A telefonunda Profilim'den şifreyi değiştirin. B telefonunda uygulamayı açın ya da bir ekranı yenileyin.
  - **Beklenen Sonuç:** A'da oturum sürer. B giriş ekranına döner ve "Şifreniz değiştirildiği için oturumunuz sonlandırıldı. Lütfen yeniden giriş yapın." gösterir. B'de eski şifre girmez, yeni şifre girer. Parola sürümü (pv) artık zorunludur: bu değişiklikten önce açılmış eski belirteçler de bir kez yeniden giriş ister.
- [ ] **66.10. (Operasyon) Oturum Süresi ve Gizli Anahtar Ayarları:**
  - **Nasıl Test Edilir:** Sunucuda `pm2 logs kapi-api --lines 200 --nostream` çıktısında son yeniden başlatmadaki "[ENV] UYARI:" satırlarına bakın (değer değil yalnız uyarı metni). `server/.env` içinde `JWT_EXPIRES_IN` ve `JWT_SECRET` uzunluğu kararını verin (değerleri sohbete/depoya yazmayın).
  - **Beklenen Sonuç:** `JWT_EXPIRES_IN` 90 günden uzunsa (canlıda 365d idi) "JWT_EXPIRES_IN ust siniri asiyor; tokenlar 90 gune kirpilarak uretiliyor. Oneri: JWT_EXPIRES_IN=30d." uyarısı çıkar; öneri 30d. `JWT_SECRET` 32 karakterden kısaysa "JWT_SECRET N karakter; en az 32 karakter onerilir..." uyarısı çıkar (sunucu yine açılır); döndürmek için yeni ≥64 karakterlik sır `JWT_SECRET`'a, eskisi `JWT_SECRET_PREVIOUS` + `JWT_SECRET_PREVIOUS_UNTIL`'e yazılır (tüm oturumlar düşebilir; kullanıcılara duyurun). Kararlar `BEKLEYEN_ISLER.md` içinde sizde bekliyor.
- [ ] **66.11. (Geliştirici) Giriş Güvenliği Sunucu ve Uygulama Doğrulaması:**
  - **Nasıl Test Edilir:** server klasöründe `node --test test/security_password_policy.test.js test/security_login_guard.test.js test/security_weak_password_routes.test.js test/security_jwt.test.js` çalıştırın. Proje kökünde `flutter test test/password_policy_test.dart` çalıştırın.
  - **Beklenen Sonuç:** Testler yeşil. Eşikler: çift (hesap × cihaz/IP) 5 hata/15 dk → 15, 30, 60 dk, en çok 2 sa; hesap geneli 20 hata/60 dk → 15 dk (en çok 4 sa); kaynak (IP) geneli 30 hata/15 dk → 15 dk (en çok 2 sa); istemci IP'si çözülemezse (Cloudflare kenarı/genel olmayan adres) IP geneli katman uygulanmaz. Güvenilir cihaz belirteci (`device_token`, 180 gün, parola sürümüne bağlı) hesap ve IP geneli kilitlerden muaf tutar ama o cihazın kendi çift kilidinden DEĞİL; parola değişince/sıfırlanınca belirteç muafiyet vermez ve bir sonraki başarılı girişte yenisi verilir. Parola ilkesi girişte uygulanmaz.

---

## 67. 🛟 Yardım ve Destek ve İlk Kullanım Turu (2026-10-16)

Çekmecedeki "Yardım ve Destek" ekranı (role göre "Nasıl yapılır", sık sorulan sorular, destek bilgisi, hesap/veri notu, yasal belgeler, sürüm) ve ilk girişte bir kez açılan 4 adımlık tanıtım turu. Destek bilgisi Platform Ayarları'ndan gelir (boşsa "Destek bilgisi yakında"). Sözleşme: `docs/PLATFORM_SATISA_HAZIRLIK.md` §1.1 ve §1.8; içerik: `lib/ui/views/help_content.dart`, `lib/ui/views/onboarding_tour.dart`.

- [ ] **67.1. Yardım ve Destek Girişi ve Ekran Yapısı:**
  - **Nasıl Test Edilir:** Her rolle çekmeceyi açın; listenin sonuna bakın. "Yardım ve Destek"e dokunun ve ekranı baştan sona kaydırın.
  - **Beklenen Sonuç:** "Yardım ve Destek", "Çıkış Yap"ın hemen üstündedir (her rolde). Dokununca çekmece kapanır ve tam ekran "Yardım ve Destek" açılır: "Size nasıl yardımcı olabiliriz?" kartı, "Tanıtım turunu göster", "Nasıl yapılır", "Sık sorulan sorular", "Destek", "Hesabım ve verilerim", "Yasal belgeler" bölümleri ve en altta "Uygulama sürümü: 1.0.0 (1)" (derleme numarası parantez içinde) yazar.
- [ ] **67.2. Nasıl Yapılır: Role Göre ve Gerçek Menü Adlarıyla:**
  - **Nasıl Test Edilir:** "Nasıl yapılır" bölümünden bir konuya dokunup açın. Adımlarda “…” içinde geçen menü ve düğme adlarını uygulamada tek tek bulun. Başka bir rolle aynı bölümü açıp konuları karşılaştırın.
  - **Beklenen Sonuç:** Konular role göre değişir (örn. bireysel: "Cihazımı hesabıma nasıl eklerim?", "Site yöneticisi olmak için nasıl başvururum?", "Daireme nasıl katılırım?", "Profilimi ve şifremi nasıl değiştiririm?"; sakin: "Kapıyı nasıl açarım?"; site yöneticisi: "Duyuru nasıl yayınlarım?"; süper kullanıcı: "Uygulama ayarlarını ve hata raporlarını nerede görürüm?"). Adımlar 1., 2., ... diye numaralıdır ve adımlarda geçen her menü/düğme adı (örn. “Daireye Katıl & Cihaz Ekle”, “QR / Kod ile Daireye Katıl”, “Platform Ayarları”) gerçekten vardır; bulamadığınız ad bir yardım metni hatasıdır, bildirin.
- [ ] **67.3. Sık Sorulan Sorular:**
  - **Nasıl Test Edilir:** "Sık sorulan sorular" bölümündeki beş soruyu sırayla açın.
  - **Beklenen Sonuç:** Sorular: "Şifremi unuttum, ne yapmalıyım?", "Doğrulama kodu e-postama gelmedi.", "Kapı açılmıyor.", "Oturumum neden kapandı?" ve "Kişisel verilerim nasıl korunuyor?". Cevaplar uygulamadaki gerçek adlarla uyumludur (“Şifremi Unuttum?”, “Kodu Tekrar Gönder”; kod 30 dakika geçerli; oturum şifre değişince/süre dolunca kapanır); son soru “Yasal belgeler” bölümüne yönlendirir.
- [ ] **67.4. Destek Bölümü: Bilgi Yokken ve Doluyken:**
  - **Nasıl Test Edilir:** Önkoşul: Önce Platform Ayarları'nda destek alanları boş, sonra dolu olmalı (bkz. Platform Ayarları bölümü). Destek alanları BOŞKEN "Destek" bölümüne bakın. Süper kullanıcıyla "Destek e-postası", "Destek telefonu", "Çalışma saatleri" ve "Destek web adresi"ni doldurup kaydedin. Yardım ekranında aşağı çekerek yenileyin; "E-posta gönder", "Kopyala", "Ara" ve "Web sitesini aç" düğmelerini deneyin.
  - **Beklenen Sonuç:** Boşken "Destek bilgisi yakında" yazar. Doluyken satırlar görünür: "E-posta" (+ "E-posta gönder", "Kopyala"), "Telefon" (+ "Ara", "Kopyala"), "Çalışma saatleri", "Web sitesi" (+ "Web sitesini aç"). "Kopyala" "Panoya kopyalandı." der; dış uygulama açılamazsa "Uygulama açılamadı; bilgi panoya kopyalandı." çıkar. Bilgi önbellekte 15 dakika tutulur: yenilemek için aşağı çekin ya da uygulamayı yeniden açın. Bilgi alınamazsa "Destek bilgisi alınamadı. İnternet bağlantınızı kontrol edip tekrar deneyin." ve "Yeniden dene" çıkar.
- [ ] **67.5. Hesabım ve Verilerim Kartı:**
  - **Nasıl Test Edilir:** "Hesabım ve verilerim" bölümündeki "Profilim ekranına git"e dokunun.
  - **Beklenen Sonuç:** Kartta "Kişisel verilerinizin bir kopyasını almak ve hesabınızı silmek için “Profilim” ekranındaki hesap ve veri bölümünü kullanın. Hesap silme geri alınamaz; silmeden önce ekrandaki uyarıları okuyun." yazar. Düğme Yardım'ı kapatır ve çekmecede "Profilim" seçili açılır; orada "Gizlilik ve Veri" kartı vardır.
- [ ] **67.6. İlk Kullanım Turu: İlk Girişte Bir Kez:**
  - **Nasıl Test Edilir:** Önkoşul: Turu daha önce görmemiş hesap/cihaz (yeni hesap ya da uygulama verisi temizlenmiş telefon). Giriş yapın (varsa "Güncellenen Koşullar" kapısını geçin). Açılan tam ekran turda "İleri" ile dört adımı gezin; ikinci adımdan itibaren "Geri"yi deneyin; son adımda "Başla"ya basın. Uygulamayı kapatıp aynı hesapla yeniden açın.
  - **Beklenen Sonuç:** Tur otomatik açılır; her adımda ikon, başlık ve metin vardır. Son adımın başlığı hep "Yardım her zaman yanınızda"dır; öncekiler rolü anlatır (bireysel: "Hoş geldiniz", "Daireye katılın", "Cihaz ekleyin ya da site kurun"; sakin: "Kapınız cebinizde", "QR, sesli komut ve misafir geçişi", "Duyurular ve borcunuz"; site yöneticisi: "Sitenizi yönetin", "Kayıtlar ve duyurular", "Modüller"; süper kullanıcı: "Platform yönetimi", "Başvurular ve talepler", "Cihazlar ve denetim"). "Başla" turu kapatır; aynı hesapta tur bir daha kendiliğinden açılmaz (bu cihazda "görüldü" tutulur).
- [ ] **67.7. Turu Atlama ve Yeniden Açma:**
  - **Nasıl Test Edilir:** Yeni bir hesapla girişte açılan turda "Atla"ya dokunun (ya da geri tuşuna basın). Çekmece → "Yardım ve Destek" → "Tanıtım turunu göster"e dokunun.
  - **Beklenen Sonuç:** "Atla" ve geri tuşu turu kapatır ve "görüldü" sayılır (yeniden girişte tekrar açılmaz). "Tanıtım turunu göster" turu her durumda yeniden açar.
- [ ] **67.8. Yardım ve Tur Küçük Ekranda, Büyük Yazıda ve Ekran Okuyucuyla:**
  - **Nasıl Test Edilir:** Yazı boyutunu en büyüğe alıp telefonu yatay çevirerek Yardım ekranını ve turu gezin. TalkBack/VoiceOver ile turun adımlarını ve Yardım başlıklarını dolaşın.
  - **Beklenen Sonuç:** Taşma ve kırpılma yoktur; tur düğmeleri satıra sığmazsa alta iner, dokunma hedefleri ≥ 48 dp'dir. Adım değişince "Adım 2 / 4: <başlık>" duyurulur; ilerleme noktaları ekran okuyucuya okunmaz (süstür).
- [ ] **67.9. Çevrimdışı Yardım Ekranı:**
  - **Nasıl Test Edilir:** Uygulama açıkken telefonu uçak moduna alın; "Yardım ve Destek"i açın. Uçak modunu kapatıp "Yeniden dene"ye dokunun.
  - **Beklenen Sonuç:** "Nasıl yapılır" ve "Sık sorulan sorular" internetsiz de görünür (uygulama içinde yazılıdır). "Yasal belgeler" bölümü "Şu an yayımlanmış bir belge yok." DEMEZ; "Belgeler yüklenemedi. İnternet bağlantınızı kontrol edip tekrar deneyin." ve "Yeniden dene" gösterir. Destek bilgisi önceden yüklenmişse önbellekten görünür, yoksa hata + "Yeniden dene" çıkar. Bağlantı gelince "Yeniden dene" listeyi yükler.
- [ ] **67.10. (Geliştirici) Yardım ve Tur Uygulama Testleri:**
  - **Nasıl Test Edilir:** Proje kökünde `flutter test test/help_content_test.dart test/help_view_test.dart test/onboarding_tour_test.dart test/app_config_test.dart` çalıştırın.
  - **Beklenen Sonuç:** Testler yeşil: yardım/tur metinlerinde geçen her menü ve düğme adı `HelpContent.knownMenuTitles` / `knownScreenLabels` kümelerinde (gerçek etiketlerle birebir) bulunur; tur role göre 4 adımdır; "görüldü" bilgisi kullanıcı başına (`onboarding_tour_seen_v1_<kullanıcı kodu>`) saklanır.

---

## 68. 🛠 Platform Ayarları ve İstemci Hataları — Süper Kullanıcı (2026-10-16)

Süper kullanıcı, uygulama sürümü ve bakım modunu, destek iletişim bilgisini ve şirket/yasal bilgileri "Platform Ayarları"ndan yönetir; uygulamalardan gelen hata raporlarını "İstemci Hataları"ndan izler. Kendini kilitlemeyi önleyen korumalar, riskli değişiklik onayı ve kaydedilmemiş değişiklik uyarısı vardır. Sözleşme: `docs/PLATFORM_SATISA_HAZIRLIK.md` §1.2 (`GET/PUT /admin/platform-config`) ve §1.3 (`GET /admin/client-errors`). Canlıda bakım modunu ve sürüm eşiklerini yalnız denerken, kısa süre ve geri alarak değiştirin.

- [ ] **68.1. Menü Girişi Yalnız Süper Kullanıcıda:**
  - **Nasıl Test Edilir:** Rol: Süper kullanıcı. Süper kullanıcı hesabıyla çekmecede "Platform Ayarları" ve "İstemci Hataları" girişlerini bulun (listenin sonunda, "Denetim Kaydı"nın altında). Site yöneticisi, daire sakini ve bireysel kullanıcı hesaplarının çekmecesine bakın.
  - **Beklenen Sonuç:** İki giriş yalnız süper kullanıcıdadır; diğer rollerde yoktur.
- [ ] **68.2. Platform Ayarları Ekranı ve Alanlar:**
  - **Nasıl Test Edilir:** Rol: Süper kullanıcı. "Platform Ayarları"nı açın ve ekranı baştan sona kaydırın.
  - **Beklenen Sonuç:** Başlık "Platform Ayarları"; açıklama "Uygulama sürümü, bakım modu, destek iletişimi ve şirket / yasal bilgiler. Boş bıraktığınız alan "ayarsız" sayılır." Üç kart: "Uygulama Sürümü ve Bakım" ("En düşük desteklenen sürüm", "Son sürüm", "Android güncelleme bağlantısı", "iOS güncelleme bağlantısı", "Bakım modu" anahtarı, "Bakım iletisi"), "Destek İletişim" ("Destek e-postası", "Destek telefonu", "Çalışma saatleri", "Destek web adresi") ve "Şirket ve Yasal Bilgiler" ("Şirket unvanı", "Şirket adresi", "MERSİS numarası", "KEP adresi", "İletişim e-postası", "İletişim telefonu", "Onayları zorunlu kıl" anahtarı). Değişiklik yokken "Değişiklikleri Kaydet" pasiftir ve "Kaydedilecek değişiklik yok." yazar.
- [ ] **68.3. Alan Doğrulamaları:**
  - **Nasıl Test Edilir:** Rol: Süper kullanıcı. "En düşük desteklenen sürüm"e "1.2" yazın (alan yalnız rakam ve nokta kabul eder). "Android güncelleme bağlantısı"na "http://ornek.com", "Destek e-postası"na "abc", "MERSİS numarası"na 15 rakam, "Şirket unvanı"na "A<B" yazın. "Değişiklikleri Kaydet"e basın.
  - **Beklenen Sonuç:** Alan altlarında sırayla: "En düşük desteklenen sürüm 1.2.3 biçiminde olmalı (üç sayı, noktalarla).", "Android güncelleme bağlantısı https:// ile başlayan geçerli bir adres olmalı (boşluk ve özel işaret içeremez).", "Destek e-postası geçerli bir e-posta adresi olmalı.", "MERSİS numarası 16 haneli olmalı.", "Şirket unvanı köşeli parantez, < >, ters eğik çizgi, ters tırnak veya ** içeremez; #, -, +, *, > ile başlayamaz." Üstte "Lütfen işaretli alanları düzeltin." çıkar ve hiçbir şey kaydedilmez.
- [ ] **68.4. Kendini Kilitleme Koruması: Sürüm Eşikleri:**
  - **Nasıl Test Edilir:** Rol: Süper kullanıcı. "Son sürüm"ü boş bırakın; "En düşük desteklenen sürüm"e uygulamanızın sürümünden YÜKSEK bir değer (örn. 9.0.0) yazıp kaydetmeyi deneyin. "Son sürüm"e 1.0.0, "En düşük desteklenen sürüm"e 2.0.0 yazıp kaydetmeyi deneyin.
  - **Beklenen Sonuç:** İlkinde "En düşük desteklenen sürüm (9.0.0), bu uygulamanın sürümünden (1.0.0) yüksek olamaz: kaydederseniz kendi uygulamanız da güncelleme ekranına düşer." çıkar. İkincisinde "En düşük desteklenen sürüm, son sürümden büyük olamaz." çıkar. İkisinde de kayıt gönderilmez.
- [ ] **68.5. Kaydedilmemiş Değişiklik Uyarısı:**
  - **Nasıl Test Edilir:** Rol: Süper kullanıcı. Herhangi bir alana bir şey yazın ve sayfanın üstüne bakın. Kaydetmeden çekmeceden "Panel"e geçmeyi deneyin; önce "Düzenlemeye Dön"ü, sonra aynı geçişte "Değişiklikleri Sil"i seçin. Platform Ayarları'na dönüp bir alanı değiştirin ve "Değişiklikleri Geri Al"a basın.
  - **Beklenen Sonuç:** Sarı "Kaydedilmemiş değişiklikleriniz var." kutusu çıkar ve "Değişiklikleri Kaydet" açılır. Menü değişiminde "Kaydedilmemiş değişiklikler" penceresi çıkar: "Platform ayarlarında kaydedilmemiş değişiklikleriniz var. Devam ederseniz bu değişiklikler kaybolur." "Düzenlemeye Dön" ekranda bırakır; "Değişiklikleri Sil" menüyü değiştirir ve yazılanlar kaybolur. "Değişiklikleri Geri Al" alanları kayıtlı değerlere döndürür ve "Kaydedilecek değişiklik yok." yazar.
- [ ] **68.6. Kaydetme ve Kalıcılık:**
  - **Nasıl Test Edilir:** Rol: Süper kullanıcı. "Destek e-postası", "Destek telefonu" ve "Çalışma saatleri"ni gerçek bilgilerle doldurup "Değişiklikleri Kaydet"e basın. Başka bir menüye gidip dönün; uygulamayı kapatıp yeniden açın ve Platform Ayarları'nı açın.
  - **Beklenen Sonuç:** Yeşil "Ayarlar kaydedildi." bildirimi çıkar. Alanlar yeniden açılışta aynı değerlerle gelir ve "Kaydedilecek değişiklik yok." yazar. Aşırı sık kayıtta (60/saat) 429 iletisi çıkar ve kaydet düğmesi kısa süre kilitlenir. Destek bilgisi Yardım ekranında görünür (bkz. Yardım bölümü).
- [ ] **68.7. Riskli Değişiklik Onay Penceresi:**
  - **Nasıl Test Edilir:** Rol: Süper kullanıcı. "Bakım modu" anahtarını açıp "Değişiklikleri Kaydet"e basın; çıkan pencerede "Vazgeç"i seçin (bakımı AÇMAYIN). "Onayları zorunlu kıl" anahtarını açıp kaydetmeyi deneyin; yine "Vazgeç".
  - **Beklenen Sonuç:** "Bu değişiklikleri kaydet?" penceresi riski madde madde söyler: "Bakım modu AÇILACAK: kullanıcılar bakım iletisini görür ve uygulamayı kullanamayabilir." ve "Onaylar ZORUNLU kılınacak: tamamlanmış yasal belgeleri onaylamayan kullanıcılar kayıt olamaz ve site başvurusu yapamaz." "Vazgeç" kaydı iptal eder (sunucuya hiçbir şey gitmez); "Kaydet" uygular. Yasal belgeler tamamlanmadan zorunluluk fiilen etkisizdir. Sürüm eşiği yükseltirken de "En düşük desteklenen sürüm X olacak: bu sürümün altındaki uygulamalar güncellenmeden kullanılamaz (şu an kullandığınız sürüm: …, etkilenmez)." notu çıkar.
- [ ] **68.8. Değişiklik Denetim Kaydına Düşer:**
  - **Nasıl Test Edilir:** Rol: Süper kullanıcı. Bir ayarı değiştirip kaydettikten sonra çekmeceden "Denetim Kaydı"nı açın; "Tümü" süzgeciyle en üstteki kayda bakın.
  - **Beklenen Sonuç:** Yeni bir kayıt eklenir (başlığı "Platform ayarları güncellendi" görünür). Kayıtta adres, telefon, e-posta gibi DEĞERLER görünmez; sunucu yalnız değişen alan adlarını saklar.
- [ ] **68.9. İstemci Hataları Ekranı:**
  - **Nasıl Test Edilir:** Rol: Süper kullanıcı. "İstemci Hataları"nı açın. Kayıt varsa bir karttaki "Örnek yığını göster" ve "Ayrıntıyı kopyala"yı deneyin; "Yenile" ikonuna basın. Telefonu uçak moduna alıp "Yenile"ye basın.
  - **Beklenen Sonuç:** Başlık "İstemci Hataları"; açıklama "Uygulamalardan gelen hata raporları. Aynı hata tek kayıtta toplanır; kişisel veriler sunucuda maskelenir ve kayıtlar 90 gün sonra silinir." Kayıt yoksa "Kayıtlı istemci hatası yok." ve "Uygulamalardan gelen hata raporları (90 gün) burada listelenir." yazar. Kayıt varsa kartta "Çökme" ya da "Hata", "N kez", platform ve "v<sürüm>" çipleri, hata türü ve iletisi, "İlk görülme:" / "Son görülme:" (İstanbul saati) bulunur; "Ayrıntıyı kopyala" "Hata ayrıntısı panoya kopyalandı." der. İnternet yokken "kayıt yok" DEĞİL, hata ve "Tekrar Dene" görünür. Hata iletilerinde gerçek e-posta, telefon veya belirteç görünmez.
- [ ] **68.10. (Geliştirici) Platform Ayarları ve İstemci Hatası Sunucu Doğrulaması:**
  - **Nasıl Test Edilir:** server klasöründe `node --test test/platform_config_routes.test.js test/platform_config_service.test.js test/app_config_routes.test.js test/client_error_routes.test.js test/client_error_service.test.js` çalıştırın. Proje kökünde `flutter test test/screens/platform_settings_view_test.dart test/screens/client_errors_view_test.dart test/app_config_test.dart` çalıştırın. Tek kullanımlık yerel PostgreSQL ile `QA_ONLY=platform_services QA_CONFIRM_DISPOSABLE_DB=yes DB_HOST=127.0.0.1 DB_PORT=55432 DB_USER=postgres DB_PASSWORD= node scripts/qa_platform_pg.mjs` çalıştırın (üretimde ÇALIŞTIRMAYIN). Süper kullanıcı olmayan bir belirteçle `GET /admin/platform-config` ve `GET /admin/client-errors` çağırın.
  - **Beklenen Sonuç:** Testler yeşil. `GET /public/app-config` kimliksiz ve `Cache-Control: no-store`'dur. Süper kullanıcı olmayan belirteç 403 alır. PUT kısmi günceller; denetim satırında yalnız anahtar adları vardır. `POST /public/client-errors` kimliksizdir, 202 döner, gövde ≤ 32 KB, IP başına 30/saat ve install_id başına 10/saat sınırlıdır; e-posta/telefon/JWT/uzun sayı dizileri maskelenir; kayıtlar 90 gün sonra silinir.

---

## 69. 🚧 Sürüm/Bakım Kapısı ve Çökme Raporu (2026-10-16)

Uygulama açılışta (ve bakım/güncelleme ekranındayken her öne gelişte; aksi hâlde 10 dakikadan eskiyse) `GET /public/app-config` okur: bakım modu açıksa "Bakım çalışması", kurulu sürüm `min_supported_version`'ın altındaysa "Güncelleme gerekli" tam ekranı, `latest_version`'ın altındaysa kapatılabilir "Yeni sürüm hazır" kartı çıkar. Yapılandırma okunamazsa uygulama ENGELLENMEZ. Süper kullanıcı bakım ve zorunlu güncellemeyle engellenmez ("yönetici görünümü" şeridi). Çökme raporu yalnız yayın/profil derlemesinde açıktır ve kişisel veri temizler. Sözleşme: `docs/PLATFORM_SATISA_HAZIRLIK.md` §1.1 ve §1.3; `docs/YAYIN_HAZIRLIGI.md` §2. Canlıda bakım modunu yalnız kısa süre ve sizin saatinizde açın.

- [ ] **69.1. Bakım Ekranı (Sıradan Kullanıcı):**
  - **Nasıl Test Edilir:** Rol: Site yöneticisi / Daire sakini. Önkoşul: İki telefon: biri süper kullanıcı, diğeri site yöneticisi ya da sakin oturumuyla. Süper kullanıcı telefonunda Platform Ayarları'nda "Bakım iletisi"ne "Deneme bakımı: 5 dakika sonra döneceğiz." yazın. "Bakım modu"nu açıp "Değişiklikleri Kaydet"e basın; onay penceresinde "Kaydet"i seçin. Diğer telefonda uygulamayı tamamen kapatıp yeniden açın.
  - **Beklenen Sonuç:** Diğer telefonda tam ekran "Bakım çalışması" çıkar; altında yazdığınız ileti (boş bırakılsaydı "Sistemimiz kısa süreli bakımda. Lütfen birkaç dakika sonra tekrar deneyin."), "Yeniden dene" ve "Yönetici girişi" düğmeleri bulunur; destek bilgisi tanımlıysa en altta "Destek: …" satırı da görünür. Geri tuşu uygulamadan çıkar (altındaki ekrana dönmez).
- [ ] **69.2. Bakımda Süper Kullanıcı Engellenmez:**
  - **Nasıl Test Edilir:** Rol: Süper kullanıcı. Bakım modu açıkken süper kullanıcı telefonunda uygulamayı kapatıp yeniden açın.
  - **Beklenen Sonuç:** Uygulama normal açılır; altta "Bakım modu açık (yönetici görünümü). Diğer kullanıcılar bakım ekranını görür." şeridi görünür ve Platform Ayarları'na girilebilir (bakımı kapatabilirsiniz).
- [ ] **69.3. Yeniden Dene ve Bakımın Kalkması:**
  - **Nasıl Test Edilir:** Rol: Site yöneticisi / Daire sakini. Diğer telefondaki bakım ekranında bakım hâlâ açıkken "Yeniden dene"ye basın. Süper kullanıcıyla bakım modunu kapatıp kaydedin; diğer telefonda "Yeniden dene"ye basın.
  - **Beklenen Sonuç:** Bakım sürerken "Sistem hâlâ bakımda. Lütfen biraz sonra tekrar deneyin." çıkar (sunucuya ulaşılamazsa "Sunucuya ulaşılamadı. Bağlantınızı kontrol edip tekrar deneyin."). Bakım kapanınca ekran kalkar ve uygulama oturum ve ekran kaybı olmadan kaldığı yerden devam eder.
- [ ] **69.4. Bakım Ekranında Yönetici Girişi:**
  - **Nasıl Test Edilir:** Önkoşul: Bakım modu açık; bir telefonda oturum KAPALI, diğerinde sıradan kullanıcı oturumu AÇIK. Oturumu kapalı telefonda bakım ekranındaki "Yönetici girişi"ne dokunup önce site yöneticisi, sonra süper kullanıcı hesabıyla girin. Oturumu açık sıradan kullanıcı telefonunda aynı düğmeye dokunun.
  - **Beklenen Sonuç:** Oturum yokken giriş ekranı geçici açılır ve altta "Yönetici girişi: yalnızca süper kullanıcı hesabıyla devam edilebilir." şeridi ("Vazgeç") görünür. Site yöneticisiyle girilirse bakım ekranı geri gelir ve "Bu hesap süper kullanıcı değil; bakım/güncelleme sırasında yalnızca yönetici hesabı kullanılabilir." yazar. Süper kullanıcıyla girilirse engel kalkar (yönetici görünümü). Sıradan oturum açıkken düğme "Yönetici girişi yalnızca süper kullanıcı hesabıyla yapılabilir. Bu cihazda başka bir hesabın oturumu açık." yazar.
- [ ] **69.5. Yumuşak Güncelleme Uyarısı (Son Sürüm):**
  - **Nasıl Test Edilir:** Önkoşul: Bakım modu KAPALI; "En düşük desteklenen sürüm" boş ya da kurulu sürümden düşük. Süper kullanıcıyla "Son sürüm"e 9.9.9 yazıp kaydedin; uygulamayı kapatıp açın. Çıkan kartta "Tamam"a (bağlantı tanımsızsa) ya da "Sonra"ya dokunun; uygulamayı yeniden açın. "Android güncelleme bağlantısı"na bir https adresi girip kaydedin; yeniden açıp "Güncelle"ye dokunun.
  - **Beklenen Sonuç:** Altta kapatılabilir "Yeni sürüm hazır (9.9.9)" kartı çıkar; uygulama ENGELLENMEZ. Bağlantı yokken "Uygulamayı mağazadan güncelleyebilirsiniz." ve "Tamam", bağlantı varken "Yeni özellikler ve düzeltmeler için güncelleyin." ile "Sonra" ve "Güncelle" düğmeleri görünür. Kapatılan sürüm için kart yeniden açılışta çıkmaz. "Güncelle" bağlantıyı açar. Testten sonra "Son sürüm"ü gerçek değerine (ya da boşa) çevirin.
- [ ] **69.6. Zorunlu Güncelleme Ekranı:**
  - **Nasıl Test Edilir:** Rol: Site yöneticisi / Daire sakini. Önkoşul: Kurulu sürümü, ayarlayacağınız "En düşük desteklenen sürüm"den DÜŞÜK ikinci bir telefon (yeni sürüm iki mağazada da yayınlandıktan sonra eski sürümlü telefon); süper kullanıcı kendi uygulamasından yüksek eşik kaydedemez. Süper kullanıcıyla "En düşük desteklenen sürüm"ü eski telefondaki sürümden yüksek bir değere (örn. 1.0.1) ayarlayıp "Android güncelleme bağlantısı"nı girerek kaydedin. Eski sürümlü telefonda uygulamayı kapatıp açın ve "Güncelle"ye dokunun.
  - **Beklenen Sonuç:** Tam ekran "Güncelleme gerekli" çıkar: "Uygulamanın bu sürümü (1.0.0) artık desteklenmiyor. Devam etmek için lütfen 1.0.1 veya daha yeni bir sürüme güncelleyin." "Güncelle" mağaza bağlantısını açar; bağlantı tanımsızsa "Uygulamayı mağazadan (Google Play veya App Store) güncelleyebilirsiniz." yazar ve düğme çıkmaz; açılamazsa "Mağaza bağlantısı açılamadı. Lütfen uygulamayı mağazadan elle güncelleyin." uyarısı gelir. Güncel sürümlü telefonlar ve süper kullanıcı etkilenmez. Eşiği yalnız yeni sürüm iki mağazada da yayındayken yükseltin.
- [ ] **69.7. Yapılandırma Okunamazsa Uygulama Engellenmez:**
  - **Nasıl Test Edilir:** Telefonu uçak moduna alıp uygulamayı kapatın ve yeniden açın.
  - **Beklenen Sonuç:** "Bakım çalışması" ya da "Güncelleme gerekli" ekranı AÇILMAZ (yapılandırma 4 sn içinde okunamazsa engel konmaz); uygulama kendi çevrimdışı akışıyla ("internet yok" ekranı ya da oturumlu ana sayfa) açılır. İnternet gelince bakım açıksa bir sonraki denetimde bakım ekranı çıkar.
- [ ] **69.8. (Geliştirici) Sahte Hata Raporu ve Kişisel Veri Maskesi:**
  - **Nasıl Test Edilir:** `curl -X POST https://api.gudeteknoloji.com.tr/public/client-errors -H "Content-Type: application/json" -d '{"install_id":"00000000-0000-4000-8000-000000000001","app_version":"1.0.0","platform":"android","error_type":"DenemeHatasi","message":"deneme ornek@example.com 05320000000","fatal":false}'` gönderin (uydurma veri). Süper kullanıcıyla "İstemci Hataları"nı yenileyin; aynı isteği tekrarlayın. Aynı `install_id` ile saatte 10'dan fazla rapor gönderin.
  - **Beklenen Sonuç:** Yanıt `202 {"ok":true}`. Listede "DenemeHatasi" kartı çıkar ve ileti "deneme [email] [phone]" biçiminde maskelidir. Aynı rapor tekrarlanınca yeni kart değil "N kez" sayacı artar. Fazla rapor "Çok fazla rapor. Biraz sonra tekrar deneyin." (429) alır. Gerçek çökme için: yayın/profil derlemesinde ya da `--dart-define=CRASH_REPORTING=true` ile debug derlemede geçici bir `throw` ekleyip raporun listeye düştüğünü görün (debug derlemede bayraksız rapor gönderilmez; `CRASH_REPORTING=false` yayında bile kapatır).
- [ ] **69.9. (Geliştirici) Sürüm Kapısı ve Çökme Raporu Uygulama Testleri:**
  - **Nasıl Test Edilir:** Proje kökünde `flutter test test/screens/app_gate_views_test.dart test/app_version_test.dart test/app_config_test.dart test/crash_reporter_test.dart` çalıştırın.
  - **Beklenen Sonuç:** Testler yeşil: sürüm karşılaştırması `major.minor.patch` sayısaldır (derleme numarası yok sayılır), süper kullanıcı kaçışı ve ardışık iki yoklamada geri dönüş, bakım/güncelleme sırasında gelen kapı derin bağlantılarının yok sayılması, çökme temizleyicisinin (JWT, Bearer, e-posta, telefon, kullanıcı dizini) doğrusal zamanlı çalışması.

---

## 70. 💾 (Operasyon) Yedek, Geri Yükleme ve İzleme — Kullanıcıya Düşen Adımlar (2026-10-16)

Canlı sunucuda günlük şifreli veritabanı yedeği (03:30 İstanbul; 14 günlük + 8 haftalık + 6 aylık), aylık geri yükleme provası, 5 dakikada bir izleme + e-posta uyarısı ve PM2 günlük döngüsü hazırdır. Aşağıdakiler SİZİN yapacağınız adımlardır: şifre anahtarının kopyası, dış kopya kararı, harici izleme ve elle doğrulamalar. Kaynak: `docs/OPERASYON_YEDEK_IZLEME.md` ve `deploy/ops/*`; sunucu adresi/oturum bilgisi `deploy/README.md`. Kapsam yalnız site_kapi_kontrol'dür (ev_otomasyon, EMQX, teklifpro yedeklenmez). [denenmedi] işaretli kısımlar (ikinci sunucu, gerçek heartbeat hizmeti, rclone) ilk kullanımda dikkatle uygulanmalıdır.

- [ ] **70.1. (Operasyon) Şifreleme Anahtarını Güvenli Yere Alın:**
  - **Nasıl Test Edilir:** Önkoşul: Windows'ta OpenSSH istemcisi ve sunucuya parolasız ssh erişimi (`ssh -p 22667 -o BatchMode=yes salihceylan@<sunucu> echo tamam` çalışmalı). `deploy/ops/pull_backups_windows.ps1` dosyasının klasöründe PowerShell'de `powershell -NoProfile -ExecutionPolicy Bypass -File .\pull_backups_windows.ps1 -FetchKey` çalıştırın. `%LOCALAPPDATA%\kapi-anahtar-tasi\kapi-backup.key` dosyasının içeriğini parola yöneticinize (ya da çevrimdışı bir USB'ye) kaydedip `kapi-anahtar-tasi` klasörünü silin.
  - **Beklenen Sonuç:** Anahtar yedeklerin klasörünün DIŞINA iner ve içeriği ekrana yazdırılmaz. Anahtar OneDrive/Dropbox/Google Drive gibi eşitlenen bir klasörde ve yedeklerle aynı yerde DURMAZ. Anahtar yalnız sunucuda kalırsa sunucu giderse şifreli yedeklerin (dış kopyalar dahil) hiçbiri açılamaz: bu madde en önemlisidir.
- [ ] **70.2. (Operasyon) Anahtar Parmak İzini Doğrulayın:**
  - **Nasıl Test Edilir:** Sunucuda `cut -c1-12 ~/ops/state/key.sha256` çıktısını not edin. Windows'ta kopyaladığınız anahtar dosyası için `certutil -hashfile <dosya> SHA256` çıktısının ilk 12 hanesini karşılaştırın.
  - **Beklenen Sonuç:** İlk 12 hane aynıdır. Farklıysa yanlış dosya kopyalanmıştır. (Anahtar sunucuda kaybolur ya da değişirse `healthcheck.sh` CRIT uyarısı verir; yeni anahtar bilerek `install_ops.sh --new-key` ile üretilir.)
- [ ] **70.3. (Operasyon) Yedekleri Bilgisayara Çekin:**
  - **Nasıl Test Edilir:** `... .\pull_backups_windows.ps1 -ListOnly` ile sunucudaki dosyaları listeleyin. Aynı komutu `-ListOnly` olmadan çalıştırın; sonra bir kez daha çalıştırın.
  - **Beklenen Sonuç:** İlk çalıştırmada `%USERPROFILE%\kapi-yedek` içine yalnız şifreli dosyalar iner (`kapi_<tarih>.sql.gz.enc`, `kapi_config_<tarih>.tgz.enc`, `kapi_firmware_<tarih>.tgz.enc`); her dosyanın SHA-256'sı sunucudakiyle eşleşir; `pull.log` ve `LAST_OK.txt` oluşur. İkinci çalıştırmada yeni dosya inmez. Sunucuda hiçbir şey yazılmaz/silinmez. Yerel dosyalar 210 günden sonra silinir (`-PruneDays 210`; 0 = silme).
- [ ] **70.4. (Operasyon) Zamanlanmış Görev Kurun (Yerel Dış Kopya):**
  - **Nasıl Test Edilir:** Betiği sabit bir yere (örn. `C:\kapi-ops\pull_backups_windows.ps1`) kopyalayın; yönetici olmayan PowerShell'de `docs/OPERASYON_YEDEK_IZLEME.md` bölüm 7 adım 4'teki `Register-ScheduledTask` komutuyla 'KapiYedekCek' görevini (günlük 11:00, `-StartWhenAvailable`) kurun. Görev Zamanlayıcı'da görevi elle çalıştırıp "Son çalıştırma sonucu"na bakın.
  - **Beklenen Sonuç:** Sonuç `0x0`; `pull.log`'a yeni satır eklenir ve `LAST_OK.txt` güncellenir (1 ise `pull.log`'a bakın). Bilgisayar o saatte kapalıysa açılışta çalışır.
- [ ] **70.5. (Operasyon) Yedeğin Açılıp Sağlam Olduğunu Doğrulayın:**
  - **Nasıl Test Edilir:** Çektiğiniz bir dosyayı Git Bash'te açın: `openssl enc -d -aes-256-cbc -pbkdf2 -iter 200000 -pass file:ANAHTAR -in kapi_<tarih>.sql.gz.enc -out kapi_<tarih>.sql.gz` (ANAHTAR = parola yöneticisinden bir dosyaya yazdığınız kopya). `gzip -t kapi_<tarih>.sql.gz && echo "yedek saglam"` çalıştırın; işiniz bitince açılmış dosyayı ve anahtar kopyasını silin.
  - **Beklenen Sonuç:** "yedek saglam" yazar. `bad decrypt` büyük olasılıkla yanlış anahtardır; ancak AES-CBC kimlik doğrulamasızdır ve yanlış anahtarda bazen hata vermeden çöp üretir: asıl doğrulayıcı `gzip -t`'dir (yapılandırma yedeği için `tar -tzf`).
- [ ] **70.6. (Operasyon) Sunucu Sağlık Kontrolü (Elle):**
  - **Nasıl Test Edilir:** Sunucuya ssh ile bağlanıp `bash ~/ops/healthcheck.sh --dry-run -v` çalıştırın.
  - **Beklenen Sonuç:** Kontrol tablosu (api, mqtt_bridge, api_public, pm2, postgres, disk, memory, backup_age, backup_run, backup_key, restore_test, offsite, tls_origin, tls_edge, tls_mqtt, mqtt_local, mqtt_public) hepsi OK görünür; yalnız bilinen uyarılar olabilir (örn. dış kopya yapılandırılmadı). E-posta gitmez, durum/sayaç dosyaları değişmez. `mqtt_public` uyarısında "DNS proxy açık olabilir (MQTT için 'DNS only' gerekir)" yazarsa `mqtt` kaydı turuncu buluttadır (bkz. 59.16).
- [ ] **70.7. (Operasyon) Uyarı E-postası Testi:**
  - **Nasıl Test Edilir:** Sunucuda `bash ~/ops/healthcheck.sh --test-alert` çalıştırın. Süper kullanıcı e-posta kutusuna bakın.
  - **Beklenen Sonuç:** Komut `TEST_ALERT_SENT` yazar ve kutuya "[KAPI-OPS] TEST uyarisi" konulu e-posta gelir. `TEST_ALERT_FAILED` ise SMTP ayarına ve `~/ops/logs/healthcheck.log` ile `~/ops/state/ALERT_UNSENT` dosyalarına bakın. Alıcı varsayılan olarak aktif süper kullanıcı hesaplarıdır; değiştirmek için `~/.config/kapi-ops.env` içine `ALERT_EMAIL=...` yazılır.
- [ ] **70.8. (Operasyon) Elle Yedek ve Geri Yükleme Provası:**
  - **Nasıl Test Edilir:** Sunucuda `bash ~/ops/backup_db.sh` çalıştırın; ardından `cat ~/ops/state/backup.status`. `bash ~/ops/restore_test.sh` çalıştırın; ardından `cat ~/ops/state/restore_test.status`.
  - **Beklenen Sonuç:** `backup.status` içinde `result=OK` (tablolar ≥ 30, users > 0) görünür. `restore_test.status` içinde `result=PASS`, `errors=0` ve tablo/satır sayıları yazar (`files_tested`: düz + şifreli dış kopya varsa 2); geçici `kapi_restoretest_*` veritabanı silinir. Aylık otomatik prova ayın 2'sinde 04:15 (İstanbul) çalışır; yeni sürümün canlıdaki ilk tam çalışması 2026-11-02'dedir [denenmedi]. Yedek dosyası `\connect`/`DROP DATABASE` gibi satırlar içeriyorsa betik yüklemeyi REDDEDER.
- [ ] **70.9. (Operasyon) Dış Kopya Hedefi: Karar ve Kurulum:**
  - **Nasıl Test Edilir:** Önkoşul: Bir dış kopya hedefi seçilmiş olmalı (A: kendi bilgisayarınıza çekme [yukarıdaki adımlar]; B: ikinci sunucuya rsync; C: Cloudflare R2/Backblaze B2 + rclone; D: Drive/OneDrive + rclone). Önerilen: hemen A, kısa sürede C. B ya da C için sunucuda `~/.config/kapi-offsite.env` dosyasını `deploy/ops/kapi-offsite.env.example`'a göre oluşturun (`chmod 600`). `bash ~/ops/offsite_push.sh --check`, sonra `bash ~/ops/offsite_push.sh --all` çalıştırın; `cat ~/ops/state/offsite.status`.
  - **Beklenen Sonuç:** `--check` hedefe bağlanabildiğini söyler. `--all` yalnız şifreli (`Salted__` başlıklı) dosyaları gönderir; `offsite.status` içinde `result=OK` yazar. Yapılandırma yokken durum `UNCONFIGURED` olur ve izleme 24 saatte bir "dış kopya yapılandırılmadı" hatırlatır. Dış kopyalar en çok ~210 gün tutulur (gizlilik metniyle uyumlu). Yedek yalnız aynı sunucuda durursa sunucuyla birlikte kaybolur.
- [ ] **70.10. (Operasyon) Ölü Adam Anahtarı (Heartbeat) Kurun:**
  - **Nasıl Test Edilir:** healthchecks.io'da (ya da UptimeRobot "Heartbeat") "Add Check" ile `kapi healthcheck` adında, Period 5 minutes ve Grace Time 10 minutes ayarlı bir kontrol oluşturup e-posta entegrasyonu ekleyin; ping adresini kopyalayın. Sunucuda `umask 077; printf 'HEARTBEAT_URL=%s\n' '<ping adresi>' >> ~/.config/kapi-ops.env; chmod 600 ~/.config/kapi-ops.env` çalıştırın ve 5 dakika bekleyin.
  - **Beklenen Sonuç:** Panelde ilk ping görünür. Adres günlüklere yazılmaz ve GİZLİDİR (sohbete/depoya yazmayın). Sunucu ya da cron ölürse içeriden e-posta gelemeyeceği hâlde bu yöntem sizi uyarır [gerçek hizmetle denenmedi].
- [ ] **70.11. (Operasyon) Harici İzleme Kurun (UptimeRobot):**
  - **Nasıl Test Edilir:** UptimeRobot'ta "Add New Monitor" ile HTTP(s) anahtar sözcük monitörü oluşturun: URL `https://api.gudeteknoloji.com.tr/health`, anahtar sözcük `"ok":true`, "Alert when keyword does not exist", aralık 5 dk. İsteğe bağlı: sunucu IP'si ve 8883 portu için "Port" monitörü ve SSL bitiş uyarısı ekleyin; uyarı iletişimi olarak e-posta tanımlayın.
  - **Beklenen Sonuç:** Monitör "Up" olur ve kesintide e-posta gelir. MQTT portu Cloudflare'dan geçmediği için IP ile izlenir. Plan limitleri ve ticari kullanım koşulları kayıt sırasında kontrol edilmelidir.
- [ ] **70.12. (Operasyon) GitHub Actions "Uptime" İş Akışını Çalıştırın:**
  - **Nasıl Test Edilir:** `.github/workflows/uptime.yml` dosyasını `main` dalına push edin (zamanlanmış işler yalnız varsayılan daldan çalışır). GitHub → Actions → "Uptime" → "Run workflow" ile bir kez elle çalıştırın; GitHub → Settings → Notifications → "Actions" bölümünde başarısız çalışma e-postasını açın.
  - **Beklenen Sonuç:** "API saglik ucu" işi yeşil biter (sağlık ucu 3 denemeyle `ok:true` ve `database:connected` döner). Çıktıda `HTTP 403` varsa Cloudflare GitHub IP'lerini engelliyordur: `/health` yolu için WAF "skip" kuralı ekleyin. İş akışı 30 dakikada bir çalışır (≈1440 dk/ay); özel depoda ücretsiz plan 2000 dk/ay'dır ve `ci.yml` aynı kotayı kullanır. Bu çalışma GitHub üzerinde henüz denenmedi.
- [ ] **70.13. (Operasyon) Eski Elle (Dağıtım) Yedek Klasörleri Kararı:**
  - **Nasıl Test Edilir:** Sunucuda `ls -1dt ~/backups/kapi_2* | tail -n +11` ve `find ~/backups -maxdepth 1 -name 'kapi_2*' -mtime +30` çalıştırın (bunlar SİLMEZ).
  - **Beklenen Sonuç:** 10'dan eski ve 30 günden eski dağıtım yedekleri aday olarak listelenir. Bu klasörler şifrelenmez ve süresiz kalır (gizlilik metnindeki saklama süresiyle çelişir); öneri en son 10 dağıtım yedeği ve en çok 30 gündür, karar sizindir. Elle silerken yalnız `kapi_<tarih>` klasörlerini seçin (`ev_*`, `emqx_*` başka projelerindir).
- [ ] **70.14. (Operasyon) Zamanlama ve PM2 Günlük Döngüsü:**
  - **Nasıl Test Edilir:** Sunucuda `crontab -l` ve `ls -la ~/.pm2/logs/` çalıştırın.
  - **Beklenen Sonuç:** Crontab'da "BEGIN kapi-ops" / "END kapi-ops" bloğu vardır: healthcheck her 5 dk; yedek 00:30 UTC (03:30 İstanbul); dış kopya 00:50 UTC; günlük döngüsü 01:05 UTC; geri yükleme provası ayın 2'si 01:15 UTC. `kapi-api-*.log` dosyaları haftalık ya da 20 MB'ı aşınca döner (`copytruncate`; kapi-api yeniden başlamaz).

---

## 71. 📦 (Yayın) İmzalı Sürüm, Paket Kimliği ve Mağaza Hazırlığı (2026-10-16)

Kalıcı paket kimliği `tr.com.gudeteknoloji.siteyonetim` (Android ve iOS), Android yükleme anahtarıyla imzalı release derlemesi, cihazda R8'li paket denemesi, mağaza formları ve yayın sonrası ayarlar. Bu bölümün çoğu SİZİN yapacağınız adımlardır (mağaza hesapları, Team ID, ekran görüntüleri). Mağaza alan uzunlukları, görsel boyutları ve hedef-API şartları belgede "doğrulanmadı" diye işaretlidir: yüklemeden önce Play Console ve App Store Connect'in güncel şartlarına bakın. Kaynak: `docs/YAYIN_HAZIRLIGI.md`; yasal metin durumu: bu listenin 65. bölümü.

- [ ] **71.1. (Geliştirici) Kalıcı Paket Kimliği:**
  - **Nasıl Test Edilir:** `android/app/build.gradle.kts` içinde `applicationId` ve `namespace`, `ios/Runner.xcodeproj/project.pbxproj` içinde `PRODUCT_BUNDLE_IDENTIFIER` değerlerine bakın. Proje kökünde `flutter test test/release_identity_test.dart` çalıştırın.
  - **Beklenen Sonuç:** Hepsi `tr.com.gudeteknoloji.siteyonetim` (testler `….RunnerTests`); `com.example.*` kalıntısı yoktur; Android Wi-Fi kanalı `tr.com.gudeteknoloji.siteyonetim/wifi_helper`, kapı kısayol şeması `sitekapi://` değişmemiştir. Paket kimliği mağazaya ilk yüklemeden sonra DEĞİŞTİRİLEMEZ.
- [ ] **71.2. (Yayın) Yükleme Anahtarını İki Yere Yedekleyin:**
  - **Nasıl Test Edilir:** `G:\site\_anahtarlar\siteyonetim-upload.jks` ve `android\key.properties` dosyalarını parola yöneticinize ve şifreli bir harici yedeğe (iki AYRI güvenli konum) kopyalayın.
  - **Beklenen Sonuç:** Her iki dosya da en az iki konumda vardır; `key.properties` git'e girmez (`android/.gitignore`), dosyalar sohbete/e-postaya konmaz. Parolalar yalnız `android\key.properties` içindedir. Anahtar kaybolursa Play App Signing açıksa Play Console'dan "Yükleme anahtarı sıfırlama" istenir (günler sürebilir); Play App Signing kullanılmazsa uygulama güncellenemez hâle gelir.
- [ ] **71.3. (Yayın) İmzalı Paket Derleme:**
  - **Nasıl Test Edilir:** Başka hiçbir `flutter` komutu çalıştırmadan proje kökünde `flutter build appbundle --release` çalıştırın (test için `flutter build apk --release`).
  - **Beklenen Sonuç:** `build\app\outputs\bundle\release\app-release.aab` (APK: `build\app\outputs\flutter-apk\app-release.apk`) üretilir ve çıktıda "android/key.properties bulunamadı" UYARISI görünmez (görünürse paket debug anahtarıyla imzalanmıştır, yayına uygun değildir). `key.properties` var ama eksik/bozuksa derleme HATA verir. Derleme sırasında `flutter test` veya `flutter pub get` çalıştırmayın (eklenti kaydını bozup derlemeyi düşürebilir). Not: `build\app\outputs\flutter-apk\app-release.apk` dosyası anahtar oluşturulmadan önce (16.10 15:23) üretildi ve `CN=Android Debug` ile imzalıdır: yayın için yeniden derleyin.
- [ ] **71.4. (Yayın) İmza Doğrulama (Debug İmzası Olmamalı):**
  - **Nasıl Test Edilir:** APK için Android SDK'daki `apksigner verify --print-certs build\app\outputs\flutter-apk\app-release.apk` çalıştırın (JAVA_HOME gerekir; örn. `...\Android\Sdk\build-tools\36.0.0\apksigner.bat`). AAB için `keytool -printcert -jarfile build\app\outputs\bundle\release\app-release.aab` çalıştırın. SHA-256 değerini `docs/YAYIN_HAZIRLIGI.md` bölüm 3'teki yükleme sertifikasıyla karşılaştırın.
  - **Beklenen Sonuç:** Sertifika sahibi `CN=Android Debug` DEĞİLDİR ve SHA-256 `4E:9C:66:FD:…` ile başlayan yükleme sertifikasıyla (bölüm 3'teki tam değer) aynıdır. Not: APK yalnız v2/v3 imzalıysa `keytool -printcert -jarfile <apk>` "Not a signed jar file" der (16.10'daki APK'da böyle görüldü); APK için `apksigner` kullanın. AAB için `keytool -printcert -jarfile` komutu `docs/YAYIN_HAZIRLIGI.md` §4'te önerilir; bu çalışmada AAB üretilmediği için denenmedi (olmazsa `jarsigner -verify -verbose -certs <aab>` deneyin).
- [ ] **71.5. (Yayın) R8'li Release Paketi Cihazda Açılıyor mu:**
  - **Nasıl Test Edilir:** Önkoşul: Anahtarla imzalı `app-release.apk`. Debug paketini kaldırıp `app-release.apk`'yı telefona kurun (`adb install -r` ya da dosyadan). Giriş yapın; "Panel"de kapı kartından "KAPIYI AÇ" ile kapıyı bulut yolundan açın.
  - **Beklenen Sonuç:** Uygulama çökmeden açılır; giriş ve kapı açma çalışır. R8 küçültme açıktır (`android/app/proguard-rules.pro`) ve R8'li paket cihazda DENENMEDİ: kural eksikliği ancak cihazda görülür.
- [ ] **71.6. (Yayın) Release Paketinde İzinli Özellikler (Kamera, Mikrofon, Bluetooth):**
  - **Nasıl Test Edilir:** Önkoşul: Anahtarla imzalı `app-release.apk` telefonda kurulu. QR kod okuma akışını açın (kamera izni). "Sesli Kapı Açma"yı açın (mikrofon izni). "Bluetooth ile Wi-Fi Kur"u açın (Bluetooth/konum izni).
  - **Beklenen Sonuç:** Her akışta sistem izin penceresi gelir, izin verilince özellik çalışır, reddedilince uygulama çökmez ve açıklayıcı ileti verir. Uygulama arka plan konumu, SMS, arama kaydı gibi gereksiz izin istemez (izin gerekçeleri `docs/YAYIN_HAZIRLIGI.md` bölüm 5).
- [ ] **71.7. (Yayın) Release Paketinde Ana Ekran Widget'ı ve Kısayollar:**
  - **Nasıl Test Edilir:** Önkoşul: Anahtarla imzalı `app-release.apk` telefonda kurulu. Ana ekrana uygulamanın kapı widget'ını ekleyin ve dokunun. Uygulama simgesine uzun basıp çıkan kısayolları ("sitekapi://" bağlantılarına dayanır) deneyin.
  - **Beklenen Sonuç:** Widget ve kısayollar uygulamayı çökmeden açar; kapı açma onay penceresi gelir. Bakım ya da zorunlu güncelleme ekranı açıkken kısayol/derin bağlantı YOK SAYILIR.
- [ ] **71.8. (Yayın) Sürüm Numarası Tutarlılığı:**
  - **Nasıl Test Edilir:** Çekmecenin altındaki sürüm satırına ve "Yardım ve Destek" altındaki "Uygulama sürümü"ne bakın. `pubspec.yaml` içindeki `version:` ve `lib/config/app_config.dart` içindeki `appVersion` / `buildNumber` değerleriyle karşılaştırın.
  - **Beklenen Sonuç:** Çekmecede "v1.0.0 (Build 1)", Yardım'da "Uygulama sürümü: 1.0.0 (1)" yazar. `pubspec.yaml` `version: 1.0.0+1`'dir (+ öncesi kullanıcıya görünen sürüm, sonrası Android `versionCode` / iOS `CFBundleVersion`). Çekmece sürümü `lib/config/app_config.dart` sabitlerinden, Yardım ve sürüm kapısı paket bilgisinden (`pubspec.yaml`) okur: ikisini birlikte güncelleyin. Her mağaza yüklemesinde derleme numarası ARTMALIDIR (örn. 1.0.1+2). Sunucudaki `min_supported_version`/`latest_version` ile `major.minor.patch` olarak karşılaştırılır (derleme numarası yok sayılır).
- [ ] **71.9. (Yayın) Yasal Sayfalar Mağaza İçin Hazır mı (Son Kapı):**
  - **Nasıl Test Edilir:** Önkoşul: Hukuk incelemesi bitmiş, belgelerdeki `complete: false` satırları kalkmış ve Platform Ayarları'nda şirket bilgileri doldurulmuş olmalı. PowerShell'de `curl.exe -s -o NUL -w "%{http_code}" https://api.gudeteknoloji.com.tr/legal/privacy` ve aynısını `/legal/account-deletion` için çalıştırın. İki sayfayı tarayıcıda açıp "[……]" ve sarı "taslak" kutusu arayın.
  - **Beklenen Sonuç:** İkisi HTTP 200 verir ve sayfada "[……]" yer tutucusu ile "Bu belgede henüz doldurulmamış veya doğrulanmamış bölümler bulunuyor; belge taslak niteliğindedir." kutusu YOKTUR. Belgeler şu an taslak olduğundan bu madde hukuk incelemesi (`docs/yasal/AVUKAT_KONTROL_LISTESI.md`) ve şirket bilgileri girilene kadar BAŞARISIZ olması beklenir; mağaza incelemesi taslak sayfayı reddedebilir.
- [ ] **71.10. (Yayın) Google Play Console Formları:**
  - **Nasıl Test Edilir:** Önkoşul: Google Play geliştirici hesabı (kurumsal hesapta D-U-N-S istenebilir; yeni kişisel hesaplarda yayın öncesi kapalı test şartı olabilir: konsolda doğrulayın). Play Console'da uygulamayı oluşturun (varsayılan dil Türkçe, "Uygulama", "Ücretsiz"); Play App Signing'i kabul edin. "Uygulama içeriği"nde gizlilik politikası URL'sine `https://api.gudeteknoloji.com.tr/legal/privacy`, veri silme URL'sine `https://api.gudeteknoloji.com.tr/legal/account-deletion` girin; reklam: Hayır; uygulamaya erişim: test hesabı bilgisi; hedef kitle: 18 yaş ve üzeri. Veri güvenliği formunu `docs/YAYIN_HAZIRLIGI.md` bölüm 5'teki tabloya göre doldurun ve AAB'yi yükleyin.
  - **Beklenen Sonuç:** Form yanıtları belgeyle uyumludur (izinler ve gerekçeleri, "finansal özellik yok" beyanı, veri satılmaz/reklam yok). Hesap silme yolu uygulamada "Profilim → Gizlilik ve Veri → Hesabımı Sil" olarak ve web URL'siyle vardır. Play'in güncel hedef-API şartı, alan uzunlukları ve ekran görüntüsü boyutları belgede doğrulanmadı: konsolda kontrol edin (şu an `compileSdk 36`, `targetSdk 36`, `minSdk 24`).
- [ ] **71.11. (Yayın) App Store Connect ve iOS Derlemesi:**
  - **Nasıl Test Edilir:** Önkoşul: Apple Developer üyeliği ve Team ID (depoya yazılmadı, `DEVELOPMENT_TEAM` boş); macOS + Xcode. Xcode'da Runner hedefinde Signing → Team seçin; `flutter build ipa --release` çalıştırın; Transporter/Organizer ile yükleyin. App Store Connect'te gizlilik URL'sini (`https://api.gudeteknoloji.com.tr/legal/privacy`), destek URL'sini, yaş derecelendirmesini (4+), hesap silme bilgisini ve "Uygulama gizliliği" etiketlerini girin; inceleme bilgisine demo hesap ve donanım notunu yazın.
  - **Beklenen Sonuç:** iOS projesi Windows'ta DERLENMEDİ (yalnız biçim/çapraz referans denetimi yapıldı); `ios/Runner/PrivacyInfo.xcprivacy` Apple doğrulamasını yükleme sırasında geçmelidir. Yerel kapı kontrolü UDP yayını için iOS 14+ `com.apple.developer.networking.multicast` yetkisi (Apple'a başvuru) gerekebilir: yetkisiz iPhone'da yerel keşif çalışmayabilir, bulut/MQTT yolu etkilenmez; yayından önce gerçek iPhone'da yerel kapı açmayı deneyin. iPad desteklendiği için iPad ekran görüntüsü seti de gerekir (kaçınmak için `TARGETED_DEVICE_FAMILY` = 1).
- [ ] **71.12. (Yayın) Mağaza Varlıkları ve Demo Hesaplar:**
  - **Nasıl Test Edilir:** Simge (512×512 PNG), öne çıkan görsel (1024×500), telefon ekran görüntüleri (Play için en az 2; App Store için iPhone 6.9" seti, iPad destekleniyorsa 13" seti) ve kısa/tam açıklama metinlerini hazırlayın. Her rol için gerçek veri içermeyen demo hesaplar oluşturun.
  - **Beklenen Sonuç:** Ekran görüntülerinde gerçek kişi verisi (ad, telefon, plaka, adres) yoktur; demo hesap bilgileri (e-posta/parola/rol) yalnız inceleme formuna yazılır. Boyutlar ve karakter sınırları belgede doğrulanmadı: konsolda kontrol edin.
- [ ] **71.13. (Yayın) Yayından Sonra: Güncelleme Bağlantıları ve Sürüm Eşikleri:**
  - **Nasıl Test Edilir:** Önkoşul: Uygulama mağazada yayında. Platform Ayarları'nda "Android güncelleme bağlantısı"na `https://play.google.com/store/apps/details?id=tr.com.gudeteknoloji.siteyonetim` yazın; iOS yayınlanınca "iOS güncelleme bağlantısı"na `https://apps.apple.com/app/id<UYGULAMA_NO>` yazın. "Son sürüm"e yayınlanan sürümü yazıp kaydedin.
  - **Beklenen Sonuç:** Eski sürüm kullanıcıları "Yeni sürüm hazır" kartında "Güncelle" ile mağazaya gider. "En düşük desteklenen sürüm"ü YALNIZ yeni sürüm iki mağazada da kullanıcıya ulaştıktan sonra yükseltin; aksi hâlde kullanıcılar güncelleyemeyecekleri bir ekranda kilitlenir.

---

## 72. 🗂 Toplu Yükleme ve Dışa Aktarma — Faz 2b: Excel/CSV ile Daire, Kişi ve Araç (2026-10-17)

Site yöneticisi (ve süper kullanıcı) Kişiler ekranındaki "Toplu Yükle" ile Excel (.xlsx) ya da CSV dosyasından daire bilgilerini, kişileri (daire ilişkisi ve plakalarıyla) ve araçları yükler; "Dışa Aktar" ile aynı listeleri dosyaya alır. Dosya cihazda okunur, sunucuya yalnız satırlar gider; her yükleme ÖNİZLEME (hiçbir kayıt değişmez) → onay ile yapılır. Hiçbir kayıt silinmez, hesap açılmaz, e-posta gönderilmez; TOPLU GERİ ALMA YOKTUR. Kurul, görevli ve sakin bu düğmeleri görmez. Sözleşme: `docs/PLATFORM_TOPLU_ISLEMLER.md`. Not: "Excel'den yükle" kısayolu yalnız BOŞ Kişiler listesinde vardır; site kurulum ekranında henüz kısayol YOKTUR. Bu bölüm 038 numaralı sunucu sürümü canlıyken, bir TEST sitesinde denenir.

- [ ] **72.1. Girişler ve Yetki:**
  - **Nasıl Test Edilir:** Rol: Site yöneticisi / Yönetim kurulu. Site yöneticisiyle çekmeceden "Kişiler"i açın; "Kişiler", "Daireler", "Araçlar" sekmelerinin üstündeki düğmelere bakın. Yönetim kurulu üyesi hesabıyla (varsa) aynı ekrana bakın; görevli ve sıradan sakin hesabının çekmecesinde "Kişiler" olup olmadığına bakın.
  - **Beklenen Sonuç:** Yöneticide "Toplu Yükle" ve "Dışa Aktar" düğmeleri vardır (dar ekranda alt alta sarar). Yönetim kurulu üyesi listeleri okur ama bu iki düğmeyi GÖRMEZ (toplu veri çıkışı yapamaz). Görevli ve sıradan sakinde "Kişiler" menüsü hiç yoktur.
- [ ] **72.2. Boş Kişiler Listesinde "Excel'den yükle":**
  - **Nasıl Test Edilir:** Rol: Site yöneticisi. Önkoşul: Hiç kişi kaydı olmayan yeni TEST sitesi. "Kişiler" sekmesini açın (arama ya da süzgeç kullanmayın). Kartın içindeki "Excel'den yükle"ye dokunun.
  - **Beklenen Sonuç:** Boş listede "Daire ve kişi bilgilerini şimdi toplu yükleyin." yazısı ve "Excel'den yükle" düğmesi çıkar; dokununca "Toplu Yükle" sihirbazı açılır ve "Kişiler" türü seçili gelir. Arama ya da süzgeç uygulanmışken boş sonuçta bu düğme çıkmaz. "Daireler" ve "Araçlar" sekmelerinin boş durumunda ve site kurulum penceresinin bitiş ekranında bu kısayol YOKTUR (henüz eklenmedi).
- [ ] **72.3. Adım 1: Tür Kartları ve Şablon İndirme:**
  - **Nasıl Test Edilir:** Rol: Site yöneticisi. "Toplu Yükle"ye dokunun; başlıktaki adım göstergesine ve site özetine bakın. "Daireler", "Kişiler" ve "Araçlar" kartlarını sırayla seçin. "Şablonu indir (Excel)"e dokunup dosyayı açın; sonra "Şablonu indir (CSV)"ye dokunun.
  - **Beklenen Sonuç:** Adım göstergesi "Adım 1 / 5 · Tür" der (adımlar: Tür, Dosya, Sütunlar, Önizleme, Sonuç); üstte site adı ve daire/blok özet çipi vardır. Metin: "Excel (.xlsx) veya CSV dosyasıyla toplu yükleme yapın. Önerilen sıra: Daireler, Kişiler, Araçlar; hepsi isteğe bağlıdır." Her kartta açıklama ve "Önerilen sıra" çipi vardır (Daireler: "Var olan dairelerin kat, tip, m², arsa payı ve borç sorumlusu bilgilerini doldurur. Yeni daire eklemez."; Kişiler: "Kişileri, daire ilişkilerini ve araç plakalarını ekler. Hesap açmaz, e-posta göndermez."). Excel şablonu (toplu_yukleme_sablonu.xlsx) üç veri sayfası ve bir "Açıklama" sayfası içerir; seçtiğiniz türün sayfası ilk sıradadır. "Daireler" sayfası sitenizin MEVCUT blok ve daire numaralarıyla (ve kayıtlı kat/tip/m² değerleriyle) önceden doludur (liste alınamazsa "Mevcut daire numaraları alınamadığı için daire sayfası boş hazırlandı." notu çıkar); "Kişiler" ve "Araçlar" sayfaları yalnız başlık satırıdır (veri sayfalarında örnek kayıt YOKTUR); "Açıklama" sayfasında sütun, zorunluluk, kural ve örnek değerler yazar. CSV şablonu yalnız seçili türün dosyasıdır (başlık satırı; Daireler için mevcut dairelerle dolu), adı toplu_yukleme_sablonu_daireler.csv / _kisiler.csv / _araclar.csv biçimindedir (noktalı virgül ayraçlı, UTF-8). Mobilde paylaşım sayfası, masaüstü/web'de kaydet penceresi açılır ve "Şablon hazır: <dosya adı>" yazar.
- [ ] **72.4. Daireler: Dosya, Sütun Eşleme, Önizleme ve Onay:**
  - **Nasıl Test Edilir:** Rol: Site yöneticisi. Önkoşul: Şablonun "Daireler" sayfasında 2-3 dairenin Kat, Tip, Brüt m², Net m², Arsa Payı (Pay), Arsa Payı (Payda) ve Borç Sorumlusu hücreleri doldurulup dosya kaydedilmiş. "Daireler" kartını seçip "Devam: Dosya seç"e dokunun; "Dosya Seç" ile .xlsx dosyanızı seçin. "Sütunları Gözden Geçir"e, açılan eşlemeyi inceleyip "Önizlemeyi Hazırla"ya basın. Önizlemeyi okuyun; "Aktar (N satır)"a dokunun; onay penceresinde "Onayla ve Aktar"a basın. Sonuç ekranına bakıp "Dairelere git"e dokunun.
  - **Beklenen Sonuç:** Dosya adı ve boyutu ile "N satır okundu." yazar. Önizleme hiçbir kaydı değiştirmez ("Önizleme hiçbir kaydı değiştirmez. Aşağıdaki özeti ve sorunlu satırları inceleyip aktarın."); çipler "Güncellenecek", "Değişmeyecek", "Hatalı", "Uyarılı"dır. Arsa payı doluysa "Arsa payı toplamı: 1000/1000 ✓" ya da "987/1000: eksik olabilir" (fazlaysa "fazla olabilir") görünür; bu kontrol sitedeki TÜM dairelerin güncel payını toplar ve engellemez. Onay penceresi "Yüklemeyi onaylayın": "N satır aktarılacak. Bu işlem toplu geri alınamaz; yanlış yüklenen kayıtlar tek tek düzeltilir." Sonuç: "Daireler yüklemesi tamamlandı." ve "Uygulanan: N", "Değişmeyen: N", "Atlanan: N" çipleri; "Dairelere git" "Daireler" sekmesini açar ve yüklediğiniz kat/tip/m²/arsa payı değerleri dairelerde görünür.
- [ ] **72.5. "Dolu alanların üzerine yaz" ve Korunan Değerler:**
  - **Nasıl Test Edilir:** Rol: Site yöneticisi. Önkoşul: Bir önceki madde yapılmış; dosyada aynı dairelerin bazı hücreleri FARKLI değerlerle değiştirilmiş. Dosyayı aynı akışla seçip önizlemeye kadar gelin; sorunlu satırlar listesine bakın. "Dolu alanların üzerine yaz" anahtarını açın; önizlemenin yenilenmesini bekleyin ve "Aktar"a basıp onay penceresine bakın.
  - **Beklenen Sonuç:** Anahtar kapalıyken farklı hücreler korunur; uyarılarda "<Alan> korundu: dolu alanın üzerine yazılmadı." yazar ve açıklama "Kapalıyken yalnız boş alanlar doldurulur; farklı olan değerler korunur." Anahtar açılınca "N alanın üzerine yazılacak." görünür ve onay penceresi "N alanın mevcut değerinin üzerine yazılacak." der. Mali kaydı (borç/tahsilat) olan bir dairenin m², arsa payı, tip ya da sorumlu bilgisi değişiyorsa uyarı çıkar: "Bu dairenin mali kaydı var; yeni değerler yalnız sonraki borçlandırmayı etkiler."
- [ ] **72.6. Kişiler: Önizleme Sayıları, Yasal Dayanak Onayı ve Sonuç:**
  - **Nasıl Test Edilir:** Rol: Site yöneticisi. Önkoşul: "Kişiler" sayfası şablonda 3-4 kişiyle doldurulmuş (Ad Soyad; Telefon; E-posta; Blok ve Daire No birlikte; İlişki: Malik/Kiracı/Aile; Giriş Tarihi 15.03.2021 gibi; Plaka; Not). "Kişiler" kartını seçip dosyanızı yükleyin; eşlemeden önizlemeye geçin. Çipleri ve "Örnek satırlar"ı okuyun; "Aktar (N satır)"a basın. Onay penceresinde onay kutusunu işaretlemeden "Onayla ve Aktar"a bakın; sonra kutuyu işaretleyip onaylayın. Sonuç ekranından "Kişilere git"e dokunun.
  - **Beklenen Sonuç:** Çipler "Eklenecek", "Bağlanacak", "Değişmeyecek", "Hatalı", "Uyarılı" olur; örnek satırlar "Satır 2 · Yeni: <Ad Soyad> → <daire> (Malik) + 1 plaka" biçiminde okunur (eylem etiketi Yeni, Bağlanır, Güncellenir ya da Değişmez olur). Onay penceresinde "Kişi verilerini işlemek için gerekli yasal dayanağa sahip olduğumu onaylıyorum." kutusu vardır; işaretlenmeden "Onayla ve Aktar" PASİFTİR. Sonuçta "Kişiler yüklemesi tamamlandı." yazar. Kişiler listesinde yeni kişiler hesapsız görünür (hesap açılmaz, e-posta gitmez); dairelerde ilişki ve plakalar eklenmiştir. Aynı dairede ikinci malik ya da kiracı yazılmışsa o satır hata alır (aile üyeleri için "Aile" yazın).
- [ ] **72.7. Hatalı Satırlar, Hata Raporu ve "Hatalı satır varsa hiçbirini aktarma":**
  - **Nasıl Test Edilir:** Rol: Site yöneticisi. Önkoşul: Kişiler dosyasına bilerek hatalı satırlar eklenmiş: boş Ad Soyad, E-posta "abc", var olmayan Blok "Z", İlişki "Komşu", Ad Soyad hücresine =1+1, Telefon "123". Dosyayı yükleyip önizlemeye gelin; "Sorunlu satırlar" listesini ve "Hatalar" / "Uyarılar" süzgeçlerini deneyin. "Hata raporunu indir"e dokunun; dosyayı açın. "Hatalı satır varsa hiçbirini aktarma" anahtarını açın; "Aktar" düğmesinin durumuna ve altındaki nedene bakın. Anahtarı kapatıp "Aktar"a basın; onay penceresine bakıp onaylayın (yalnız geçerli satırlar yazılsın).
  - **Beklenen Sonuç:** "Sorunlu satırlar (N)" listesinde her sorun "Satır 7 · <alan>" başlığıyla ve Türkçe nedenle görünür; satır numarası Excel'de gördüğünüz numaradır (başlık 1. satır). Örnek nedenler: "Ad Soyad zorunludur.", "E-posta biçimi geçersiz: «abc».", "Blok bulunamadı: «Z». Sitedeki bloklar: ...", "İlişki anlaşılamadı: «Komşu». Malik, Kiracı, Aile ya da Sakin yazın.", "Ad Soyad formül gibi görünüyor (= ile başlıyor). İşareti kaldırın.", "Telefon geçersiz: «123». 10 haneli numara girin." Hata raporu `hata_raporu_people_<YYYYAAGG>.csv` adlı noktalı virgüllü dosyadır; sütunları "Satır", "Alan", "Kod", "İleti"dir. Anahtar açıkken ve hatalı satır varken "Aktar" PASİFTİR; altında "Aktarmak için: Hatalı satırlar var ve «hiçbirini aktarma» seçili. Seçeneği kapatın ya da dosyayı düzeltin." yazar (hatasız dosyada anahtar açıkken onay penceresi "Katı mod açık: hatalı satır çıkarsa hiçbir satır aktarılmaz." der). Anahtar kapalıyken geçerli satırlar aktarılır, hatalılar atlanır; onay penceresi "N hatalı satır aktarılmayacak." der. Hata raporu önizlemede de, sonuç ekranında da "Hata raporunu indir" düğmesiyle indirilir.
- [ ] **72.8. Aynı Dosyayı İkinci Kez Yükleme:**
  - **Nasıl Test Edilir:** Rol: Site yöneticisi. Önkoşul: Bir dosya daha önce başarıyla yüklenmiş. Aynı dosyayı yeniden seçip önizlemeye gelin.
  - **Beklenen Sonuç:** Önizlemede (satırlarda uyarı yoksa) aktarılacak değişiklik yoktur: "Dosyadaki kayıtlar zaten sistemde var; aktarılacak bir değişiklik yok." yazar ve "Aktar" düğmesi pasiftir ("Aktarmak için: Aktarılacak geçerli satır yok."). Kişiler çift kayıt OLMAZ. Düzeltilmiş bir dosyayı yeniden yüklemek, yalnız eksik satırları ekler. Hızlı çift dokunma ya da bağlantı kopması sonrası aynı yükleme tekrar denenirse "Bu yükleme daha önce tamamlanmıştı; aynı dosya yeniden uygulanmadı." çıkabilir.
- [ ] **72.9. Araçlar: Kişiyi Bulma ve Plaka Kuralları:**
  - **Nasıl Test Edilir:** Rol: Site yöneticisi. Önkoşul: Sitede kayıtlı kişiler var; "Araçlar" sayfası doldurulmuş: bir satırda kayıtlı kişinin E-postası + geçerli Plaka, bir satırda Blok + Daire No + Plaka, bir satırda kayıtlı olmayan E-posta, bir satırda geçersiz Plaka ("XYZ"), bir satırda sitede başka kişide kayıtlı plaka. "Araçlar" kartını seçip dosyayı yükleyin ve önizlemeye gelin. Sorunlu satırlar listesini inceleyin; geçerli satırları aktarın; "Araçlar" sekmesine bakın.
  - **Beklenen Sonuç:** Kişi önce e-postayla, yoksa Blok+Daire No ile (dairede tek sakin varsa o; birden çok sakin varsa Ad Soyad ile) bulunur. Bulunamayan satırda "Kişi bulunamadı. Kayıtlı bir e-posta ya da dairede kayıtlı bir sakin gerekir." (hata); birden çok aday varsa "Birden çok kişi eşleşti. E-posta ya da telefon ekleyerek ayırın." Geçersiz plaka "Plaka atlandı (biçim geçersiz): «XYZ»." ve başkasında kayıtlı plaka "Plaka atlandı: «...» sitede başka bir kişide kayıtlı." diye bildirilir; satırdaki TÜM plakalar atlanmışsa ve eklenecek/mevcut plaka kalmamışsa bu uyarılar HATA olur (satırdan hiçbir şey yüklenmez). Geçerli plakalar "Araçlar" sekmesinde ilgili kişiyle görünür. (Kişiler dosyasındaki plaka sorunları ise yalnız UYARIdır: kişi ve ilişki yazılır, sorunlu plaka atlanır.)
- [ ] **72.10. Dosya Biçimleri, Boyut ve Satır Sınırları, "Başka Dosya Seç":**
  - **Nasıl Test Edilir:** Rol: Site yöneticisi. Bir CSV dosyası seçin: Türkçe Excel'in "CSV (Noktalı virgülle ayrılmış)" çıktısı ve "CSV UTF-8" çıktısı (ikisini ayrı ayrı deneyin). Aynı ekranda "Başka Dosya Seç"e dokunup sırayla şunları seçin: eski .xls dosyası, 10 MB'tan büyük bir .xlsx, 5.000'den fazla veri satırı olan bir dosya, birden çok sayfalı ve sayfa adı tanınmayan bir .xlsx.
  - **Beklenen Sonuç:** Türkçe karakterler (ğ ü ş ı İ ö ç) doğru okunur; Windows-1254 yedeğine düşülürse "Windows-1254 olarak okundu" notu çıkar. Dosya seçildikten sonra düğme "Başka Dosya Seç" olur ve önceki dosyanın verisi yenisine karışmaz. .xls için "Eski .xls biçimi (ya da parola korumalı Excel dosyası) desteklenmez. Dosyayı Excel'de parolasız olarak .xlsx veya CSV biçiminde kaydedip yükleyin." çıkar. 10 MB'tan büyük .xlsx için "Dosya çok büyük (en çok 10 MB). Satırları parçalara bölüp ayrı ayrı yükleyin."; CSV için sınır 5 MB'tır. 5.000 satırdan fazlası için "Dosyada 5000 satırdan fazla veri var. Bir seferde en çok 5000 satır yüklenebilir..." çıkar. Çok sayfalı dosyada seçtiğiniz türün sayfası bulunamazsa "Hangi sayfa yüklensin?" listesi ve "Dosyada birden çok sayfa var ve Kişiler sayfası bulunamadı. Verilerin olduğu sayfayı seçin." yazısı gelir. Makrolu (.xlsm), ikili (.xlsb) ve OpenDocument (.ods) dosyaları reddedilir. Hiçbirinde uygulama çökmez.
- [ ] **72.11. Sütun Eşleme Adımı:**
  - **Nasıl Test Edilir:** Rol: Site yöneticisi. Önkoşul: Başlıkları şablondan farklı yazılmış bir dosya (örn. "Ad-Soyad", "Cep", "Kapı No") ve zorunlu sütunu eksik bir dosya. Farklı başlıklı dosyayı "Kişiler" türüyle yükleyip "Sütunlar" adımına gelin. Bir alanın eşlemesini listeden "Eşleme yok (boş bırak)" yapın; zorunlu "Ad Soyad" alanını eşlenmemiş bırakmayı deneyin. Dosyada ilgisiz bir sütun (örn. "Yorum") bırakıp adımın altındaki uyarıya bakın.
  - **Beklenen Sonuç:** Başlıklar otomatik eşlenir ("Sayfa: ...", "Başlık: N. satır", "N satır okundu" çipleri); her alan için "<Alan> için dosyadaki sütun" listesi vardır, zorunlu alanlar "Zorunlu" çipi taşır. Zorunlu alan eşlenmezse "Devam etmek için: «Ad Soyad» alanı için bir sütun seçin." yazar ve "Önizlemeyi Hazırla" kapalı kalır; iki sütun aynı alana uyuyorsa "Birden çok sütun bu alana uyuyor (...). Birini seçin." çıkar. İlgisiz sütun için "Yok sayılacak sütunlar: «Yorum». Bu sütunlardaki veriler yüklenmez." yazar. Dosya başka türe benziyorsa (örn. Daireler dosyasını Kişiler diye yüklemek) "Bu dosyanın başlıkları «Daireler» türüne daha çok benziyor..." uyarısı çıkar. Formül sonucu dosyada kayıtlı olmayan hücreler BOŞ okunur ve bu açıkça yazılır.
- [ ] **72.12. Dışa Aktar: Kişiler, Daireler, Araçlar (CSV ve Excel) ve Gidiş-Dönüş:**
  - **Nasıl Test Edilir:** Rol: Site yöneticisi. "Kişiler" sekmesinde bir süzgeç uygulayın (örn. durum "Aktif", ilişki "Malik") ve "Dışa Aktar"a dokunun. Açılan sayfada "Ne aktarılsın?", "Dosya biçimi" ve "Uygulanan süzgeç"e bakın; "Excel (.xlsx) · önerilen" ile "Kaydet" (mobilde "Paylaş") deyin; dosyayı Excel'de açın. Aynısını "CSV (Excel uyumlu)" biçimiyle ve "Daireler" ve "Araçlar" seçenekleriyle tekrarlayın; "Kişiler" için "Yönetici notlarını da ekle" anahtarını açıp bir kez daha deneyin. Dışa aktardığınız "Daireler" dosyasını "Toplu Yükle"de "Daireler" türüyle geri yükleyip sütun eşlemeye bakın.
  - **Beklenen Sonuç:** Sayfada "Kayıtlar sunucudan alınır, dosya cihazınızda hazırlanır. Tüm sayfalardaki kayıtlar dahil edilir." yazar; süzgeç açık sekmeninkiyle aynıdır ve TÜM sayfalardaki kayıtlar dosyaya girer. "Bu dosya kişisel veri içerir; güvenli saklayın ve yetkisiz kişilerle paylaşmayın." uyarısı vardır; "Yönetici notlarını da ekle" (Araçlarda "Araç notlarını da ekle") VARSAYILAN KAPALIDIR ("Varsayılan olarak kapalıdır."). Başarıda "Dosya kaydedildi/hazır: kisiler_<site>_<YYYYAAGG>.xlsx (N satır, boyut)." yazar. Excel'de Türkçe karakterler doğrudur; telefon "0 (555) 123 45 67" biçimindedir (baştaki sıfır kaybolmaz); birden çok plaka tek hücrede virgülle yazılır; "Hesap" (Var/Yok) ve "Durum" (Aktif/Pasif) salt okunur sütunlardır. CSV noktalı virgül ayraçlı, UTF-8'dir ve "=" gibi işaretle başlayan metin hücrelerinin başına kesme işareti konur. Süzgeçle eşleşen kayıt yoksa "Bu süzgeçle dışa aktarılacak kayıt yok." çıkar; 20.000 satırı aşan veride "Çok fazla kayıt var. Süzgeçle daraltın." Geri yüklemede "Malik", "Kiracı", "Sakin Sayısı" gibi salt okunur sütunlar "Yok sayılacak sütunlar" olarak listelenir ve yükleme çalışır.
- [ ] **72.13. (Geliştirici) Toplu Yükleme Sunucu ve Uygulama Doğrulaması:**
  - **Nasıl Test Edilir:** server klasöründe `node --test` ile `test/` altındaki `bulk_import_*.test.js` dosyalarını çalıştırın. Proje kökünde `flutter test` ile `test/bulk_*_test.dart` ve `test/screens/bulk_*_test.dart` dosyalarını çalıştırın. Tek kullanımlık yerel PostgreSQL ile `QA_ONLY=bulk_import QA_CONFIRM_DISPOSABLE_DB=yes DB_HOST=127.0.0.1 DB_PORT=55432 DB_USER=postgres DB_PASSWORD= node scripts/qa_platform_pg.mjs` çalıştırın (üretimde ÇALIŞTIRMAYIN).
  - **Beklenen Sonuç:** Testler yeşil. Gerçek PG bölümü: 038 şeması ve açılış DDL'i idempotent (tablo FK'sız oluşturulur, iki FK ayrı ifadelerle eklenir), idempotans, `PREVIEW_STALE`, eşleşme matrisi, kilit turları (40P01 = 0), 5000 satırlık ölçek hedefleri. Spec `GET /manager/sites/:siteCode/imports/spec` `max_rows: 5000` ve `max_body_bytes: 5242880` döner; 5 MB'ı aşan istek 413 `PAYLOAD_TOO_LARGE` (nginx'te 413 gövdesiz gelirse istemci yine "Dosya çok büyük. Satırları parçalara bölüp ayrı ayrı yükleyin." gösterir).

---

## 73. 📁 Belgeler (Dosya Deposu) — Faz 3b-A: Yükleme, Kitle, Sürüm, Silme ve Duyuru Eki (2026-10-17)

"Belgeler (Dosya Deposu)" modülü varsayılan KAPALIDIR: önce Modüller ekranından açın (yönetici talep eder, süper kullanıcı onaylar ya da doğrudan açar). Yönetici belge yükler, kategori ve kitle seçer (Sakinler: tüm site / bloklar / daireler; Yönetim kurulu; Yalnız yöneticiler), yeni sürüm yükler, düzenler, siler ve geri alır; sakin kitlesindeki kişi belgeyi "Belgeler" ekranından açar. Belge duyuruya eklenebilir (en çok 5, yalnız sakinlere açık belgeler; e-postaya dosya EKLENMEZ). Kabul edilen türler PDF, JPG, PNG, DOCX, XLSX; dosya başına 10 MB, site başına 200 MB varsayılan sınır. Sözleşme: `docs/PLATFORM_BELGELER.md`. Belge içine kişisel veri (T.C. kimlik no, IBAN) koymayın; denemelerde gerçek kişi verisi içermeyen dosyalar kullanın.

- [ ] **73.1. Modül Kapalıyken Menü Yok; Açınca "Belgeler" Gelir:**
  - **Nasıl Test Edilir:** Rol: Site yöneticisi / Süper kullanıcı / Daire sakini. Önkoşul: Belgeler modülü KAPALI bir TEST sitesi (yönetici, bir sakin ve süper kullanıcı hesabı). Yönetici ve sakin hesaplarının çekmecesinde "Belgeler" olup olmadığına bakın. Yönetici olarak Modüller → "Belgeler (Dosya Deposu)" → "Modül Talep Et"; süper kullanıcıyla talebi onaylayın (ya da doğrudan açın). Yönetici ve sakin hesaplarının çekmecesine yeniden bakın; "Belgeler"i açın. Süper kullanıcının çekmecesinde "Belgeler"in modülden bağımsız olarak bulunduğuna bakın.
  - **Beklenen Sonuç:** Kapalıyken yönetici ve sakinde "Belgeler" yoktur (modül açıkken, çekmecede "Finans"/"Borcum"un, yoksa "Duyurular"ın altında görünür). Açılınca yöneticide "Belgeler" belirir; sakinde de belirir (kitlesinde belge olsun olmasın). "Belgeler" sayfasında başlık "Belgeler" ve açıklama vardır; yöneticide "Belge Yükle" düğmesi, "Belge ara" kutusu, "Kategori" ve "Durum" ("Yayında" / "Silinenler") süzgeçleri görünür. Modül kapatılırsa ekran "Belgeler bu site için kapalı." der ve "Modüller" düğmesi sunar. Görevli ve bireysel kullanıcıda "Belgeler" yoktur.
- [ ] **73.2. Belge Yükleme (PDF) ve İlerleme:**
  - **Nasıl Test Edilir:** Rol: Site yöneticisi. Önkoşul: Belgeler modülü AÇIK TEST sitesi; gerçek veri içermeyen küçük bir PDF. "Belge Yükle"ye dokunun; formu üstten alta okuyun (uyarı metni, "Dosya Seç", "Başlık", "Kategori", "Kimler görebilir?", "Hedef", "Açıklama (isteğe bağlı)"). PDF'i seçin, başlık yazın, "Yönetmelik" kategorisini, "Sakinler" kitlesini ve "Tüm site" hedefini seçip "Yükle"ye basın. Yükleme sürerken ilerleme çubuğuna bakın; bitince listeye bakın.
  - **Beklenen Sonuç:** Formda "Belgede kişisel veri (T.C. kimlik no, IBAN, telefon, adres) varsa yalnız ilgili kitleye açın; gereksiz veriyi karartın." uyarısı vardır; dosya alanının ipucunda "PDF, JPG, PNG, DOCX veya XLSX" yazar (sunucudan öğrenilmişse "· en çok 10 MB" ve "· kalan alan ..." da eklenir; bilinmeyen sayı gösterilmez). Kategoriler: Yönetmelik, Toplantı Tutanağı / Karar, Sözleşme, Bilgilendirme, Diğer. Kitle seçilmeden "Belgeyi kimlerin görebileceğini seçin." hatası çıkar. Yükleme sırasında "Yükleniyor" ilerlemesi (%, boyut), "Dosya gönderildi, sunucu kaydediyor..." aşaması görünür; bitince "Belge yüklendi." bildirimi çıkar ve belge listede başlık, kategori, "Kitle: Tüm sakinler", dosya adı/boyutu, "v1" ve "0 indirme" ile görünür. Yükleme sırasında "Vazgeç" "Yükleme iptal edilsin mi?" sorar.
- [ ] **73.3. Dosya Türü, Boyut ve Sahte Uzantı Kuralları:**
  - **Nasıl Test Edilir:** Rol: Site yöneticisi. "Belge Yükle"de sırayla seçin: .txt (ya da .exe) dosyası, boş (0 bayt) bir dosya, 10 MB'tan büyük bir PDF, uzantısı .pdf yapılmış sıradan bir metin dosyası.
  - **Beklenen Sonuç:** Desteklenmeyen tür için seçimde "Bu dosya türü desteklenmiyor. PDF, JPG, PNG, DOCX veya XLSX yükleyin." çıkar; boş dosya için "Seçilen dosya boş. Başka bir dosya seçin."; büyük dosya için "Dosya çok büyük (...). En fazla ... yükleyebilirsiniz." Uzantısı değiştirilmiş sahte PDF yükleme sırasında sunucuda "Dosya içeriği uzantısıyla uyuşmuyor ya da bozuk." diye reddedilir; makrolu Office dosyaları "Makro içeren belge yüklenemez. Makrosuz kaydedip yeniden yükleyin." ile reddedilir. Reddedilen dosya listede belge olarak görünmez.
- [ ] **73.4. Kitle ve Hedef Seçimi (Kim Görür):**
  - **Nasıl Test Edilir:** Rol: Site yöneticisi / Daire sakini / Yönetim kurulu. Önkoşul: İki bloklu TEST sitesi: A bloğunda bir sakin, B bloğunda bir sakin, bir yönetim kurulu üyesi. "Belge Yükle"de "Sakinler" kitlesi için "Hedef" olarak "Bloklar"ı seçin; hiçbir blok eklemeden "Yükle"ye basın; sonra "Blok Ekle"yle yalnız A bloğunu seçip yükleyin. Aynı şekilde "Daireler" hedefiyle bir belge yükleyin ("Daire Ekle" ile tek daire); ayrıca "Yönetim kurulu" ve "Yalnız yöneticiler" kitleleriyle birer belge yükleyin. Yönetici listesinde her belgenin "Kitle:" çipine bakın. Sırayla A sakini, B sakini ve yönetim kurulu üyesi hesabıyla "Belgeler"i açın.
  - **Beklenen Sonuç:** Blok/daire hedefinde hiçbir öğe seçilmezse "En az bir blok seçin." / "En az bir daire seçin." hatası çıkar; en çok 500 öğe seçilebilir. Kitle çipleri "Tüm sakinler", "A Blok" (blok adı), daire adı, "Yönetim kurulu", "Yalnız yöneticiler" olarak yazar. A sakini yalnız hedefinde A bloğu/dairesi olan veya "Tüm sakinler" belgeleri görür, B sakini A'ya özel belgeyi GÖRMEZ; "Yönetim kurulu" ve "Yalnız yöneticiler" belgeleri sakinde görünmez. Kurul üyesi "Sakinler" ve "Yönetim kurulu" belgelerini salt okur, "Yalnız yöneticiler" belgesini görmez. Belgeyi yükleyen yönetici hepsini görür. Kitle değişikliği anında geçerlidir.
- [ ] **73.5. Sakin Görünümü: Arama, Süzgeç ve "Aç / Kaydet":**
  - **Nasıl Test Edilir:** Rol: Daire sakini. Sakin hesabıyla "Belgeler"i açın; "Belge ara"ya başlık yazın, "Kategori" çiplerini deneyin. Bir belgenin kartındaki "Aç / Kaydet"e dokunun; indirme penceresi bitince telefonun paylaşım menüsünden kaydedin/açın. Yönetici sakin modundayken (hem yönetim hem sakin görünümü olan hesapla) "Yönetim görünümü" ve "Belgelerim" çiplerini deneyin.
  - **Beklenen Sonuç:** Sayfada "Yönetimin sizinle paylaştığı belgeleri buradan açabilir ya da kaydedebilirsiniz." yazar; boşsa "Henüz belge yok." / arama sonucu yoksa "Bu arama ve süzgeç için belge bulunamadı."; birden çok sitede "Site" seçimi ve "Tüm siteler" vardır. "Aç / Kaydet" "Belge indiriliyor" penceresini (yüzde ve boyut) açar, bitince paylaşım menüsü gelir; kartta başlık, kategori, dosya türü/boyutu ve (yeni sürümde) "Güncellendi" rozeti görünür. İndirme sırasında "Vazgeç" işlemi durdurur; hatada "Belge indirilemedi" ve "Tekrar Dene" çıkar. Hem yönetim hem sakin yetkisi olan hesapta "Yönetim görünümü" ve "Belgelerim" çipleri görünüm değiştirir.
- [ ] **73.6. Yeni Sürüm Yükleme ve Sürüm Geçmişi:**
  - **Nasıl Test Edilir:** Rol: Site yöneticisi / Daire sakini. Önkoşul: Yüklenmiş ve sakinin gördüğü bir belge. Belge kartına dokunup ayrıntıyı açın; "Yeni Sürüm Yükle"ye dokunun, başka bir PDF seçin, "Sürüm notu (isteğe bağlı)"na "Madde 4 düzeltildi" yazıp "Sürümü Yükle"ye basın. Ayrıntıda "Sürümler" bölümüne bakın; "v1 İndir" ve "v2 İndir"i deneyin. Sakin hesabıyla belgeyi açıp indirin. Yönetici ayrıntısında eski sürüm için "v1 Sil"i deneyin (iki sürüm varken).
  - **Beklenen Sonuç:** Pencere başlığı "Yeni Sürüm Yükle"dür ve "Yeni sürüm yüklenince sakinler yalnız güncel sürümü indirir; önceki sürümler yöneticilerde kalır." yazar; bitince ayrıntıda "Yeni sürüm yüklendi. Sakinler artık güncel sürümü indirir." çıkar. "Sürümler" bölümünde "v2 (güncel)" ve "v1" satırları dosya adı, boyut, tarih, not ve yükleyen bilgisiyle listelenir. Sakin yalnız güncel sürümü indirir ve kartta "Güncellendi" görür. "v1 Sil" onay penceresi "v1 sürümü silinsin mi?" der ("Bu sürümün dosyası hemen ve kalıcı olarak silinir; geri alınamaz."); belgenin tek sürümü kaldıysa sürüm silme düğmesi çıkmaz.
- [ ] **73.7. Belgeyi Düzenleme:**
  - **Nasıl Test Edilir:** Rol: Site yöneticisi. Belge ayrıntısında "Düzenle"ye dokunun; başlığı, kategoriyi, açıklamayı ve kitleyi değiştirip "Kaydet"e basın. Başlığı boşaltmayı ve 120 karakterden uzun yapmayı deneyin.
  - **Beklenen Sonuç:** "Belgeyi Düzenle" penceresi açılır; değişiklik "Belge güncellendi." ile bildirilir. Pencerede "Kitle değişikliği anında geçerlidir. Dosyayı değiştirmek için "Yeni Sürüm Yükle"yi kullanın." yazar. Boş başlık "Başlık boş olamaz.", uzun başlık "Başlık en çok 120 karakter olabilir." der (açıklama en çok 1000, sürüm notu en çok 200 karakter). Kaydetmeden kapatırken "Değişiklikler silinsin mi?" sorulur ("Düzenlemeye Dön" / "Vazgeç ve Kapat").
- [ ] **73.8. Sil, Geri Yükle ve Kalıcı Sil:**
  - **Nasıl Test Edilir:** Rol: Site yöneticisi / Daire sakini. Bir belgenin ayrıntısında "Sil"e dokunup "Belge silinsin mi?" penceresini okuyun ve "Sil"i onaylayın. Sakin hesabıyla belgenin kaybolduğunu doğrulayın. Yönetici olarak "Durum" altından "Silinenler"i seçin; belgeyi açıp "Geri Yükle"ye dokunun. Başka bir belgeyi silip "Silinenler"den "Kalıcı Sil"e dokunun ve onaylayın.
  - **Beklenen Sonuç:** Pencere "Belge Silinenler listesine taşınır ve sakinlere/kurula gösterilmez. Bir süre saklanır; bu sürede geri yükleyebilirsiniz, sonra kalıcı olarak silinir." der; sonra "Belge silindi. Silinenler listesinden geri yükleyebilirsiniz." çıkar. "Silinen belgeler" listesinde her belge "Silindi · N gün sonra kalıcı silinir" rozeti taşır (liste altında "Silinen belgeler bir süre sonra kalıcı olarak silinir. Süre dolmadan geri yükleyebilirsiniz."). "Geri Yükle" "Belge geri yüklendi." der ve belge sakinde yeniden görünür. "Kalıcı Sil" "Kalıcı olarak silinsin mi?" sorar ("Belge ve tüm sürümleri hemen ve kalıcı olarak silinir; geri alınamaz. Duyurulardaki ekleri de kalkar.") ve "Belge kalıcı olarak silindi." ile bitirir.
- [ ] **73.9. Belge Alanı (Kota) Göstergesi:**
  - **Nasıl Test Edilir:** Rol: Site yöneticisi. Belge listesinin üstündeki "Belge alanı" satırına bakın; bir belge yükleyip tekrar bakın; bir belgeyi kalıcı silip tekrar bakın.
  - **Beklenen Sonuç:** "Belge alanı" satırında kullanılan miktar (örn. "12 MB / 200 MB") ve bir ilerleme çubuğu görünür; yükleme sonrası artar, kalıcı silmeyle azalır. %90'ı geçince çubuk uyarı tonuna döner (ekran okuyucu "Alan dolmak üzere" der). Yükleme penceresinde dosya ipucunda "kalan alan ..." yazar. (Kota aşımında sunucu "Site belge alanı doldu (... MB / ... MB). Eski belgeleri kalıcı olarak silin." der; bunu denemek için kotası düşürülmüş test ortamı gerekir.)
- [ ] **73.10. Duyuruya Belge Ekleme:**
  - **Nasıl Test Edilir:** Rol: Site yöneticisi / Daire sakini. Önkoşul: "Sakinler" kitlesine açık yayında en az bir belge; hedef dar (yalnız A bloğu) ikinci bir belge. Yeni duyuru oluşturma penceresinde "Belge eki" bölümündeki "Belge Ekle"ye dokunun; uyarıyı okuyun; bir belgeyi işaretleyip "Ekle"ye basın; duyuruyu yayınlayın. "Belge Ekle" listesinde "Yönetim kurulu" ya da "Yalnız yöneticiler" kitleli belgenin olmadığına bakın; 5'ten fazla belge seçmeyi deneyin. Sakin hesabıyla duyuruyu açın; "Ekler (1)" bölümünden "Aç / Kaydet"e dokunun. Duyurunun e-postasını (gönderildiyse) açıp dosya ekini arayın.
  - **Beklenen Sonuç:** Seçici "Belge Ekle" başlığıyla açılır ve "Bu belge duyurunun tüm alıcılarına açılır. Yalnız sakinlere açık, yayındaki belgeler eklenebilir." der; liste yalnız "Sakinler" kitleli yayındaki belgeleri gösterir; en çok 5 belge seçilebilir ("En çok 5 belge seçilebilir."), eklenecek belge yoksa "Eklenebilecek belge yok." çıkar. Formda "Belge eki" bölümü eklenen belgeleri başlıklarıyla listeler ve her birinin yanında çıkarma düğmesi (ekran okuyucuda "<başlık> ekini kaldır") vardır. Duyurunun tüm alıcıları (belgenin kendi hedefi daha dar olsa bile) eki "Ekler (N)" altında "Aç / Kaydet" ile indirebilir. E-postaya dosya EKLENMEZ (alıcılar belgeyi uygulamadan açar).
- [ ] **73.11. Duyuruda Kullanılan Belgeyi Silme / Kitlesini Daraltma Uyarıları:**
  - **Nasıl Test Edilir:** Rol: Site yöneticisi / Daire sakini. Önkoşul: Yayındaki bir duyuruya ekli belge. O belgeyi "Sil"mek isteyin; çıkan uyarıda önce "Vazgeç", sonra "Yine de Sil"i seçin. Başka bir ekli belgenin kitlesini "Düzenle"den "Yalnız yöneticiler"e çevirip kaydetmeyi deneyin; uyarıda "Yine de Değiştir"i seçin. Sakin hesabıyla ilgili duyurunun eklerine bakın.
  - **Beklenen Sonuç:** Silmede "Belge duyurularda kullanılıyor" penceresi çıkar ("Bu belge N yayındaki duyuruya ekli. Silerseniz duyurularda "kullanılamıyor" görünür ve alıcılar dosyayı indiremez. Yine de silinsin mi?"); "Yine de Sil"den sonra "Belge silindi. Ekli olduğu duyurularda artık kullanılamıyor." çıkar. Kitle sakinlerden çıkarılırken aynı başlıkla "Bu belge N yayındaki duyuruya ekli. Kitleyi sakinlerden çıkarırsanız duyuru alıcıları ekine erişemez; taslak ve zamanlanmış duyurulardan ek çıkarılır. Yine de değiştirilsin mi?" sorulur ("Vazgeç" / "Yine de Değiştir"). Sakinin duyurusunda silinen belgenin eki "Artık kullanılamıyor." rozetiyle görünür ve açılmaz. Düzenleme penceresinde de "Bu belge duyurulara ekli..." bilgi notu vardır.
- [ ] **73.12. Yönetim Kurulu Üyesi Salt Okur:**
  - **Nasıl Test Edilir:** Rol: Yönetim kurulu. Yönetim kurulu üyesi hesabıyla "Belgeler"i açın; bir belgeyi açın.
  - **Beklenen Sonuç:** Sayfada "Yönetim kurulu üyesi olarak belgeleri yalnızca görüntüleyebilirsiniz. Yalnız yöneticilere açık belgeler görünmez." yazar; "Belge Yükle" yoktur; belge ayrıntısında "Aç / Kaydet" vardır, "Yeni Sürüm Yükle", "Düzenle", "Sil" yoktur ve "Yönetim kurulu üyesi olarak belgeyi yalnızca görüntüleyebilirsiniz." notu çıkar.
- [ ] **73.13. Denetim Kaydında Belge İşlemleri:**
  - **Nasıl Test Edilir:** Rol: Süper kullanıcı. Süper kullanıcıyla "Denetim Kaydı"nı açıp eylem süzgecinden "Belge yüklendi", "Belge sürümü eklendi", "Belge düzenlendi", "Belge silindi", "Belge geri yüklendi", "Belge kalıcı silindi", "Belge sürümü silindi", "Belge duyuruya eklendi", "Belge duyurudan çıkarıldı" seçeneklerini sırayla deneyin.
  - **Beklenen Sonuç:** Önceki maddelerde yaptığınız her belge işlemi Türkçe etiketiyle (örn. "Belge yüklendi", "Belge silindi") ve hedef "Belge #N" olarak listelenir. Satırlarda belge başlığı, açıklaması ya da dosya adı GÖRÜNMEZ (yalnız numara ve sayılar).
- [ ] **73.14. (Geliştirici) Belgeler Sunucu ve Uygulama Doğrulaması:**
  - **Nasıl Test Edilir:** server klasöründe `node --test` ile `test/document_*.test.js` dosyalarını çalıştırın. Proje kökünde `flutter test` ile `test/document_*_test.dart` ve `test/screens/document_*_test.dart` dosyalarını çalıştırın. Tek kullanımlık yerel PostgreSQL ile `QA_ONLY=documents QA_CONFIRM_DISPOSABLE_DB=yes DB_HOST=127.0.0.1 DB_PORT=55432 DB_USER=postgres DB_PASSWORD= node scripts/qa_platform_pg.mjs` çalıştırın (üretimde ÇALIŞTIRMAYIN).
  - **Beklenen Sonuç:** Testler yeşil: tür/imza doğrulaması ve etkin içerik reddi, kota (`DOCUMENT_QUOTA_EXCEEDED`), yarım yükleme süpürmesi, yetkili indirme (başka sitenin/kitlenin belgesi 404 `DOCUMENT_NOT_FOUND`), sürümleme, yumuşak silme/kalıcı silme, `DOCUMENT_IN_USE` (duyuru eki), `MODULE_DISABLED`. Sunucuda `DOCUMENTS_STORAGE_DIR` yapılandırılmamışsa yükleme "Belge yükleme şu an kullanılamıyor." (503) verir; nginx `client_max_body_size` belge yükleme yolu için dosya sınırından büyük olmalıdır.

---

## 74. 🧾 Makbuz — Faz 4b: Düzenleme, Yazdırma, İptal, Doğrulama (2026-10-17)

Tahsilat kaydedilince site ayarına göre otomatik numaralı makbuz (MK-YYYY-NNNNNN) düzenlenir; makbuz değişmez bir kayıttır: yazdırma ASIL/KOPYA sayılır, hatalı makbuz silinmez İPTAL edilir (iptal makbuzu düzenlenir), ödeme düzeltilir/iptal edilirse makbuz da otomatik iptal olur. Sakin kendi dairesinin makbuzlarını "Makbuzlarım" altında görür. PDF cihazda üretilir. Yönetici düzenler/iptal eder; kurul yalnız okur. Sözleşme: `docs/PLATFORM_FINANS_4B.md` Ö1. Önkoşul: Aidat ve Finans modülü AÇIK, en az bir borçlandırılmış daire.

- [ ] **74.1. Otomatik Makbuz Ayarı ve Tahsilatta Makbuz:**
  - **Nasıl Test Edilir:** Rol: Site yöneticisi. Önkoşul: Aidat ve Finans AÇIK TEST sitesi; borçlandırılmış bir daire. Finans → "Finans Ayarları"nı açın; "Makbuz" bölümünde "Tahsilatta makbuz otomatik düzenlensin" anahtarının açık olduğuna bakın ve "Kaydet"e basın. "Daireler" sekmesinde bir daireye dokunun; "Tahsilat Ekle"yle bir tahsilat kaydedin. Kaydın hemen ardından açılan makbuz penceresini okuyun.
  - **Beklenen Sonuç:** Anahtar varsayılan olarak AÇIKTIR ("Kapalıyken makbuz, ekstreden elle düzenlenir."); kayıtta "Finans ayarları kaydedildi." çıkar. Tahsilattan sonra "Makbuz" penceresi açılır: "Makbuz MK-2026-000001 düzenlendi. Yazdırabilir ya da paylaşabilirsiniz." (numara MK-<yıl>-<altı haneli sıra>, boşluksuz artar); "Tahsilat makbuzu" başlığı, "Geçerli" rozeti, "Makbuz No", "Tahsil edilen tutar" ve "Yazıyla: ..." tutarı, "Düzenleme tarihi", "Tahsilat tarihi", "Daire", "Ödeyen", "Yöntem", "Düzenleyen", "Doğrulama kodu" satırları görünür. Geçmiş tarihli tahsilat bile BUGÜNÜN makbuz numarasını alır. Ekstrede tahsilat satırında "Makbuz MK-..." düğmesi çıkar.
- [ ] **74.2. Makbuz Yazdırma ve Paylaşma (ASIL / KOPYA):**
  - **Nasıl Test Edilir:** Rol: Site yöneticisi. Makbuz penceresinde "Yazdır"a dokunun, yazdırma/PDF önizlemesini inceleyip tamamlayın; sonra tekrar "Yazdır"a dokunun. "Paylaş (PDF)"e dokunun ve PDF'i kaydedin/açın. Pencerede "Basım sayısı" satırına bakın.
  - **Beklenen Sonuç:** İlk yönetici basımı "ASIL", sonraki basımlar "KOPYA (2)", "KOPYA (3)" damgalıdır; "Basım sayısı" her basımda artar (basım sunucuya kaydedilir; PDF hazırlanamazsa "Basım kaydedildi ancak PDF hazırlanamadı. Tekrar deneyin; yeni bir kopya sayılmaz." çıkar). PDF'te Türkçe karakterler (ş ğ ı İ ö ü ç ₺) doğru görünür; makbuz numarası, tutar, daire, tarih ve doğrulama kodu vardır; dosya adı `Makbuz_MK-<yıl>-<sıra>.pdf` biçimindedir (ASCII). İptal edilmiş makbuz basılırsa "İPTAL EDİLMİŞTİR" damgası ve iptal makbuzu numarası görünür.
- [ ] **74.3. Otomatik Kapalıyken Elle "Makbuz Düzenle":**
  - **Nasıl Test Edilir:** Rol: Site yöneticisi. Finans Ayarları'nda "Tahsilatta makbuz otomatik düzenlensin"i kapatıp kaydedin; bir tahsilat kaydedin (makbuz penceresi AÇILMAZ). "Daireler" → o dairenin ekstresinde tahsilat satırındaki "Makbuz Düzenle"ye dokunun; ikinci kez dokunmayı deneyin.
  - **Beklenen Sonuç:** Anahtar kapalıyken tahsilattan sonra makbuz penceresi çıkmaz ve satırda "Makbuz Düzenle" düğmesi vardır. Düğme makbuzu düzenler ve makbuz penceresini açar (aynı tahsilat için tek AKTİF makbuz: ikinci istek yeni makbuz üretmez, mevcudu gösterir). Ters kaydı olan (iptal edilmiş) ödeme için "Bu ödeme iptal edilmiş; iptal edilmiş ödeme için makbuz düzenlenemez." çıkar. Testten sonra anahtarı yeniden açın.
- [ ] **74.4. Hatalı Makbuzu İptal Etme ve Yeniden Düzenleme:**
  - **Nasıl Test Edilir:** Rol: Site yöneticisi. Makbuz penceresinde "Makbuzu İptal Et"e dokunun; açıklamayı okuyup "Not (isteğe bağlı)" yazın ve onaylayın. Aynı makbuza ve yeni numaralı iptal makbuzuna bakın; ekstreden aynı ödeme için "Makbuz Düzenle"yle yeni makbuz düzenleyin. İptal makbuzunun penceresinde "Makbuzu İptal Et" düğmesi arayın.
  - **Beklenen Sonuç:** Açıklama: "Ödeme değişmez; yalnızca bu makbuz geçersiz sayılır ve yeni numaralı bir iptal makbuzu düzenlenir. Daha sonra, hesap ekstresindeki "Makbuz Düzenle" ile aynı ödeme için yeni bir makbuz düzenleyebilirsiniz." Onaydan sonra "Makbuz iptal edildi. İptal makbuzu düzenlendi." çıkar; asıl makbuz "İptal edildi" rozeti ve "Bu makbuz iptal edilmiştir. İptal makbuzu No MK-... " yazısı taşır, yeni iptal makbuzu ("İptal makbuzu" başlığı) kendi numarasını alır ve hangi makbuzu iptal ettiğini ("MK-... numaralı makbuzu iptal eder. Neden: Makbuz hatalı düzenlendi.") yazar. İptal makbuzunda ve iptal edilmiş makbuzda "Makbuzu İptal Et" düğmesi YOKTUR (iptal makbuzu iptal edilemez). Ödeme (tahsilat) değişmez; yeni "Makbuz Düzenle" yeni numara üretir. Not yalnız yönetim kayıtlarında görünür (sakin göremez).
- [ ] **74.5. Ödeme Düzeltilince / İptal Edilince Makbuz Otomatik İptal Olur:**
  - **Nasıl Test Edilir:** Rol: Site yöneticisi. Makbuzlu bir tahsilatı ekstrede "Düzelt"le düzeltin (tutarı değiştirin); sonra başka bir makbuzlu tahsilatı "İptal Et"le iptal edin. Makbuz numaralarına ve "Makbuzlar" listesine bakın.
  - **Beklenen Sonuç:** Düzeltmede eski makbuz otomatik iptal edilir (iptal makbuzunun nedeni "Ödeme düzeltildi") ve yeni tahsilat için yeni numaralı makbuz düzenlenir (açıksa makbuz penceresi çıkar); iptalde makbuz "Ödeme iptal edildi" nedeniyle iptal edilir ve iptal makbuzu düzenlenir. Numaralar atlanmadan artar; iptal edilen makbuzlar listeden silinmez.
- [ ] **74.6. Makbuz Listesi, Arama ve Dışa Aktar:**
  - **Nasıl Test Edilir:** Rol: Site yöneticisi / Yönetim kurulu. Daire ekstresinde "Makbuzlar"a dokunun; "Makbuz ara"ya numara/ödeyen yazın; yıl çiplerini ve "Tümü"nü deneyin. Yöneticiyle "Dışa Aktar"a dokunup makbuz listesini Excel/CSV olarak alın. Yönetim kurulu üyesiyle aynı listeye bakın.
  - **Beklenen Sonuç:** Başlık "Makbuzlar"dır; liste "Makbuz listesi" altında satırlar halinde gelir; arama kutusu "Makbuz no, daire veya ödeyen adı" ipucuyla çalışır; boşken "Henüz makbuz düzenlenmemiş.", süzgeçte sonuç yoksa "Bu arama ve süzgeç için makbuz bulunamadı." Yöneticide "Makbuz Doğrula" ve "Dışa Aktar" düğmeleri vardır; dışa aktarma `finance_receipts` listesini (süzgece göre) dosyaya alır. Yönetim kurulu üyesi listeyi ve makbuzu okur ama "Dışa Aktar", "Makbuzu İptal Et" ve "Makbuz Düzenle" düğmelerini görmez.
- [ ] **74.7. Makbuz Doğrulama:**
  - **Nasıl Test Edilir:** Rol: Site yöneticisi. "Makbuzlar" penceresinde "Makbuz Doğrula"ya dokunun; makbuz penceresinden gerçek numarayı ve "Doğrulama kodu"nu girip "Doğrula"ya basın. Kodun bir hanesini değiştirerek tekrar deneyin; numarayı "MK-2026-123" gibi yanlış biçimde yazmayı deneyin. İptal edilmiş bir makbuzun numarasını ve kodunu doğrulayın.
  - **Beklenen Sonuç:** Pencere "Makbuz üzerindeki numarayı ve doğrulama kodunu girin. Bilgiler sunucudaki kayıtla karşılaştırılır; hiçbir şey değişmez." der. Doğru çiftte "Bu makbuz kayıtlarla eşleşiyor ve geçerli." (yeşil), makbuz no/tutar/daire/tarih satırlarıyla; yanlış kodda "Girilen numara ve kod kayıtlarla eşleşmiyor. Bilgileri kontrol edin."; biçim hatasında "Numara MK-2026-000123 biçiminde olmalı." ve "Kod 12 harf ya da rakamdan oluşur."; iptal edilmiş makbuzda "Bu makbuz kayıtlarla eşleşiyor ancak İPTAL EDİLMİŞ."; iptal makbuzunda "Bu belge kayıtlarla eşleşiyor: bir makbuzu iptal eden İPTAL MAKBUZUDUR." Doğrulama hiçbir kaydı değiştirmez.
- [ ] **74.8. Sakin: "Makbuzlarım" ve KOPYA Çıktı:**
  - **Nasıl Test Edilir:** Rol: Daire sakini. Önkoşul: Sakinin dairesine makbuz düzenlenmiş (ve borç/ödeme kendisine görünür); iptal edilmiş bir makbuz da varsa daha iyi. Sakin hesabıyla "Borcum"u açın; dairenin kartında "Makbuzlarım"a dokunun. Bir makbuzu açıp "Yazdır" ya da "Paylaş (PDF)"i deneyin; ekstre için "Ekstreyi Yazdır" ve "Ekstreyi Paylaş"ı deneyin. Başka dairenin makbuzunu görmeye çalışın (başka daire sakini hesabıyla).
  - **Beklenen Sonuç:** Pencere "Makbuzlarım" başlığıyla açılır ve "Dairenize düzenlenen makbuzlar. Kendi cihazınızdan alacağınız çıktı "KOPYA" damgalı olur." yazar; yalnız kendi dairesinin makbuzları listelenir (borcu kendisine görünür olan daireler). Sakin çıktısı her zaman "KOPYA" damgalıdır ve basım sayısını artırmaz; makbuzda yönetici notu görünmez, iptal makbuzunda neden görünür (not görünmez). "Makbuzu İptal Et" ve "Makbuz Düzenle" yoktur. Aile üyesi hesabı borç/makbuz görmez. Başka dairenin makbuzu açılmaz.
- [ ] **74.9. (Geliştirici) Makbuz Sunucu ve Uygulama Doğrulaması:**
  - **Nasıl Test Edilir:** server klasöründe `node --test` ile `test/finance_*.test.js` (makbuz dosyaları) çalıştırın. Proje kökünde `flutter test` ile `test/receipt_*_test.dart`, `test/screens/finance_receipt_*_test.dart` çalıştırın. Gerçek PG ile `QA_ONLY=finance_4b QA_CONFIRM_DISPOSABLE_DB=yes DB_HOST=127.0.0.1 DB_PORT=55432 DB_USER=postgres DB_PASSWORD= node scripts/qa_platform_pg.mjs` çalıştırın (üretimde ÇALIŞTIRMAYIN).
  - **Beklenen Sonuç:** Testler yeşil. Makbuz numarası boşluksuzdur (50 eşzamanlı ödeme sonrası `COUNT = MAX = son sıra`), makbuz/iptal/basım olayları değişmezdir (UPDATE/DELETE hata), bir ödemenin tek aktif makbuzu vardır, doğrulama kodu HMAC ile üretilir, `POST receipts/verify` kurul dahil okuma yetkisiyle çalışır ve hiçbir şey yazmaz. PDF yazı tipi gömülüdür (ağ gerekmez).

---

## 75. 🏦 Kasa/Banka Hesapları, Aktarım ve Mutabakat — Faz 4b (2026-10-17)

"Kasa" sekmesi nakit kasa ve banka hesaplarının bakiyesini tutar: tahsilatlar ve giderler seçilen hesaba işlenir, hesaplar arası aktarım yapılır, banka ekstresi/kasa sayımı ile mutabakat girilir (fark düzeltme hareketiyle kapatılabilir ya da yalnız kayıt olarak girilir). Hiçbir hareket silinmez; yanlış kayıt iptal/ters hareketle düzeltilir. Yalnız yönetici yazar; kurul okur. Sözleşme: `docs/PLATFORM_FINANS_4B.md` Ö4. Önkoşul: Aidat ve Finans AÇIK TEST sitesi.

- [ ] **75.1. Hesap Ekleme ve Düzenleme:**
  - **Nasıl Test Edilir:** Rol: Site yöneticisi. Finans → "Kasa" sekmesini açın; "Hesap Ekle"ye dokunun; "Hesap adı" (örn. Nakit Kasa), "Tür" (Kasa / Banka), "Açılış bakiyesi" (örn. 5.000,00), "Açılış tarihi" girip kaydedin; bir ikinci hesabı (Banka) ekleyin. Bir hesap kartında "Düzenle"ye dokunup adı/notu değiştirin; "Hesap aktif"i kapatmayı deneyin.
  - **Beklenen Sonuç:** Hesap yokken "Henüz kasa ya da banka hesabı yok." ve "Tahsilat ve giderler bir hesaba işlenir. İlk hesabı "Hesap Ekle" ile oluşturun." yazar. Kayıtta "Hesap eklendi: <ad>." çıkar; üstte "Toplam bakiye" ve "N hesap" görünür; kartta bakiye, tür çipi ve "Hareketler", "Düzeltme", "Mutabakat", "Düzenle" düğmeleri vardır. Açılış bakiyesi için "Açılış bilgisi sonradan değiştirilemez." uyarısı vardır; açılış tarihi bugünden ileri olamaz. Aynı adla ikinci hesap "Bu adla başka bir hesap var. Farklı bir ad seçin." ile reddedilir; en çok 20 hesap tanımlanabilir. Düzenlemede "Hesap aktif" kapatılırsa bakiye ≠ 0 ise "Pasifleştirince bakiye silinmez; önce aktarım ya da düzeltmeyle sıfırlamanız önerilir." uyarısı çıkar; pasif hesaplar "Pasif hesaplar" başlığı altına iner ve pasif hesaba yeni hareket yazılamaz.
- [ ] **75.2. Tahsilat Hesaba İşlenir (Hesap Seçimi Zorunlu):**
  - **Nasıl Test Edilir:** Rol: Site yöneticisi. "Daireler" sekmesinde bir daireden "Tahsilat Ekle"yi açın; "Hesap" seçmeden kaydetmeyi deneyin. Bir hesap seçip tahsilatı kaydedin; "Kasa" sekmesinde o hesabın "Hareketler"ine bakın. Tahsilat tarihini hesabın açılış tarihinden önceye almayı deneyin.
  - **Beklenen Sonuç:** Sitede aktif hesap varken "Hesap" bölümü vardır ("Tahsilat seçtiğiniz kasa ya da banka hesabına işlenir.") ve seçilmezse "Tahsilatın gireceği hesabı seçin." hatası çıkar. Kayıttan sonra hesap bakiyesi tutar kadar artar; "Hesap Hareketleri" penceresinde "Tahsilat" hareketi (daire etiketiyle) ve "Güncel bakiye" görünür. Açılış tarihinden önceki tarihte "Seçilen tarih kasa / banka hesaplarının açılış tarihinden önce; bu tahsilat bir hesaba işlenmeyecek." uyarısı/hatası çıkar ("Tarih, hesabın açılış tarihinden önce olamaz."). Tahsilat düzeltilir/iptal edilirse hesapta ters hareket yazılır ("Ters kayıt").
- [ ] **75.3. Hesaplar Arası Aktarım ve Aktarımı İptal:**
  - **Nasıl Test Edilir:** Rol: Site yöneticisi. Önkoşul: En az iki aktif hesap (biri bakiyeli). "Aktarım Yap"a dokunun; çıkış ve giriş hesabını, tutarı, tarihi ve açıklamayı girip "Aktar"a basın; aynı hesabı iki yere seçmeyi ve bakiyeden büyük tutar girmeyi deneyin. İki hesabın "Hareketler"ine bakın; "Aktarım Geçmişi"ni açıp aktarımda "İptal Et" → "Aktarımı İptal Et"i onaylayın.
  - **Beklenen Sonuç:** Tek hesapla "Aktarım için en az iki aktif hesap gerekir." (düğme pasif) ; pencere "Hesaplar Arası Aktarım" başlığıyla açılır. Aynı hesap seçilirse "Çıkış ve giriş hesabı aynı olamaz."; bakiyeyi aşan tutarda "Bu tutar çıkış hesabının bakiyesini (...) aşıyor; hesap eksiye düşer. Kayıtları kontrol edin." uyarısı çıkar ama engellenmez. Başarıda "Aktarım yapıldı: <tutar> (<çıkış> → <giriş>)." yazar; çıkış hesabında "Aktarım (çıkış)", giriş hesabında "Aktarım (giriş)" hareketi ve toplam bakiye DEĞİŞMEZ. İptalde "Aktarım iptal edildi." çıkar, iki hesapta da ters hareket yazılır, aktarım kaydı silinmez ("İptal edildi" rozeti kalır).
- [ ] **75.4. Düzeltme Hareketi (Banka Masrafı, Faiz, Sayım Farkı):**
  - **Nasıl Test Edilir:** Rol: Site yöneticisi. Banka hesabı kartında "Düzeltme"ye dokunun; yön olarak "Hesaptan çıkış (-)" seçin, tutar girin, neden olarak "Banka masrafı"nı seçin, kaydedin. Aynı pencerede "Diğer" nedenini seçip notu boş bırakmayı deneyin; sonra "Hesaba giriş (+)" ve "Banka faizi" ile bir düzeltme daha yazın.
  - **Beklenen Sonuç:** Pencere "Düzeltme Hareketi" başlığıyla açılır ve "Banka masrafı, banka faizi ya da kasa sayım farkı gibi hesap bakiyesini düzelten bir hareket yazar. Hareket raporlarda ayrı satır olarak görünür." der. Yön seçilmeden "Düzeltmenin yönünü seçin (giriş ya da çıkış).", neden seçilmeden "Düzeltme nedenini seçin." hatası çıkar; nedenler: Banka masrafı, Banka faizi, Sayım farkı, Diğer ("Diğer" için not zorunludur: ""Diğer" nedeninde açıklama notu zorunludur."). Tutara eksi işareti girilmez ("Eksi işareti girmeyin; yön yukarıda seçilir."); formda "Bakiye: X → Y" önizlemesi görünür. Kayıttan sonra "Düzeltme yazıldı: ..." çıkar ve hesabın hareketlerinde "Düzeltme" satırı ayrı görünür.
- [ ] **75.5. Mutabakat: Fark Yok, Fark Düzeltilir, Fark Yalnız Kayıt:**
  - **Nasıl Test Edilir:** Rol: Site yöneticisi. Bir hesapta "Mutabakat"a dokunun; "Sistemde hesaplanan bakiye"yi okuyun; aynı tutarı "Ekstre / sayım bakiyesi"ne yazıp "Mutabakatı Kaydet"e basın. İkinci kez, ekstre bakiyesini sistemden farklı girin; "Farkı düzeltme hareketi olarak yaz"ı açın, neden seçip kaydedin. Üçüncü kez yine farklı bir tutar girin ve anahtarı KAPALI bırakıp kaydedin. Kasa sekmesinde ve hesap hareketlerinde sonuçlara bakın.
  - **Beklenen Sonuç:** Pencere "Mutabakat": "Banka ekstresindeki ya da kasada saydığınız bakiyeyi girin; sistemdeki bakiyeyle karşılaştırılır." Fark yoksa "Fark yok: bakiye ekstreyle tutuyor." ve kayıtta "Mutabakat kaydedildi: <hesap> bakiyesi ekstreyle tutuyor." Fark varsa "Fark: +X (ekstre sistemden fazla)" / "(ekstre sistemden az)" görünür; düzeltme açıkken ve neden seçilmişse "Mutabakat kaydedildi: fark ... düzeltme hareketiyle giderildi." ve hesaba bir "Düzeltme" hareketi yazılır; kapalıyken "Mutabakat kaydedildi: fark ... düzeltilmedi; raporlarda uyarı olarak görünür." çıkar ve bakiye DEĞİŞMEZ. Sonradan ekstrede "Son mutabakat farkı" uyarısı raporlarda kalır. Mutabakat tarihi her zaman bugündür; hesap siz bakarken değişirse "Hesap bakiyesi siz bakarken değişti..." uyarısı çıkar ve yeniden onay istenir.
- [ ] **75.6. Hesaba Eşlenmemiş Tahsilat ve "Toplu Eşle":**
  - **Nasıl Test Edilir:** Rol: Site yöneticisi. Önkoşul: Hesap tanımlanmadan ÖNCE kaydedilmiş tahsilatlar olan (tarihi hesabın açılış tarihinden sonra) TEST sitesi; kapatılmamış ay. "Kasa" sekmesinin üstündeki "Hesaba eşlenmemiş N tahsilat" uyarısına bakın. "Dönemler" sekmesinden o ayı kapatmayı deneyin. "Toplu Eşle"ye dokunun; her ödeme yöntemi (Nakit, Havale / EFT, Çek) için bir hesap seçip "Önizle"ye, sonra "Onayla ve Eşle"ye basın.
  - **Beklenen Sonuç:** Uyarı "Hesaba eşlenmemiş N tahsilat var. Toplam ... Kasa rakamları eksik olabilir ve ilgili ay kapatılamaz." der. Ay kapatma "Bu ay kapatılamaz: hesaba eşlenmemiş tahsilatlar var. Kasa bölümündeki "Toplu Eşle" ile eşleyin." ile reddedilir. Pencere "Tahsilatları Hesaplara Eşle" başlığıyla açılır ve "Hesap tanımlanmadan önce kaydedilmiş tahsilatlar, ödeme yöntemine göre seçtiğiniz hesaba işlenir. Önce önizleme gösterilir; onaylamadan hiçbir şey kaydedilmez." der; önizleme tahsilat sayısı ve yöntem bazlı toplamı gösterir, kapalı ayda ya da hesap açılışından önce olanları "bu işlemle eşlenmeyecek" diye ayrı listeler. Onaydan sonra "N tahsilat hesaplara eşlendi (toplam ...)" çıkar, uyarı kalkar ve ay kapatılabilir. Önizleme ile onay arasında veri değişirse "Veriler değişti, önizleme yenilendi..." uyarısıyla yeniden onay istenir.
- [ ] **75.7. Kurul Üyesi Salt Okur:**
  - **Nasıl Test Edilir:** Rol: Yönetim kurulu. Yönetim kurulu üyesi hesabıyla Finans → "Kasa" sekmesini açın; bir hesabın hareketlerine bakın.
  - **Beklenen Sonuç:** Hesaplar ve hareketler görünür; "Hesap Ekle", "Aktarım Yap", "Toplu Eşle", "Düzeltme", "Mutabakat", "Düzenle" düğmeleri YOKTUR ve sayfada "Yönetim kurulu üyesi olarak mali kayıtları yalnızca görüntüleyebilirsiniz." yazar.
- [ ] **75.8. (Geliştirici) Kasa ve Mutabakat Sunucu ve Uygulama Doğrulaması:**
  - **Nasıl Test Edilir:** server klasöründe `node --test` ile `test/finance_*.test.js` (hesap/aktarım/mutabakat dosyaları) çalıştırın; proje kökünde `flutter test` ile `test/cash_*_test.dart` ve `test/screens/finance_cash_*_test.dart` çalıştırın. Gerçek PG ile `QA_ONLY=finance_4b QA_CONFIRM_DISPOSABLE_DB=yes DB_HOST=127.0.0.1 DB_PORT=55432 DB_USER=postgres DB_PASSWORD= node scripts/qa_platform_pg.mjs` çalıştırın (üretimde ÇALIŞTIRMAYIN).
  - **Beklenen Sonuç:** Testler yeşil. Hesap bakiyesi yalnız `account_movements` toplamıdır; aktarım iki hareketi tek işlemde yazar; mutabakat hesaplanan bakiyeyi kilit altında yeniden hesaplar (`RECONCILIATION_STALE`), daha yeni tarihli düzeltmeli mutabakat varken eski tarihe düzeltme `RECONCILIATION_ORDER` alır (arayüz "Yalnız kayıt olarak gir" sunar); eşlenmemiş tahsilat varken `PERIOD_HAS_UNASSIGNED_PAYMENTS`; 40P01 = 0.

---

## 76. 🛒 Gider Kaydı, Kategori/Tedarikçi ve Gider Belgesi — Faz 4b (2026-10-17)

"Giderler" sekmesi ödenmiş giderleri bir kasa/banka hesabından çıkan kayıt olarak tutar (nakit esaslı): kategori, tedarikçi, KDV (tutara dahil), belge türü/numarası ve en çok 5 belge eki (PDF/JPG/PNG). Gider silinmez; İPTAL edilir (hesapta ters hareket) ya da DÜZELTİLİR (iptal + yeni gider). Çift kayıt koruması vardır (aynı tedarikçi + belge no; 24 saatte aynı tutar/tarih/kategori). Yalnız yönetici yazar; kurul okur (tedarikçi vergi/T.C. no ve telefonu görünmez). Gider belgesi için Belgeler modülünün AÇIK olması gerekmez. Sözleşme: `docs/PLATFORM_FINANS_4B.md` Ö3. Önkoşul: Aidat ve Finans AÇIK TEST sitesi ve en az bir kasa/banka hesabı.

- [ ] **76.1. Gider Ekleme (Hesaptan Çıkar):**
  - **Nasıl Test Edilir:** Rol: Site yöneticisi. Hesabı olmayan sitede Giderler sekmesinden "Gider Ekle"yi açın. Hesap eklendikten sonra "Gider Ekle"de Kategori, Açıklama ("Örn. Eylül ayı asansör bakımı"), Gider tutarı, KDV tutarı (isteğe bağlı), Gider tarihi, "Çıkacağı hesap" ve Belge türü (Belgesiz / Fatura / Fiş / makbuz / Sözleşme / Diğer) ile "Belge / fatura no" girip "Kaydet"e basın. Kasa sekmesinde o hesabın bakiyesine ve "Hareketler"ine bakın.
  - **Beklenen Sonuç:** Hesap yokken "Gider kaydı için bir kasa ya da banka hesabı gerekir. Önce Kasa sekmesinden bir hesap ekleyin." çıkar. Eksik alanlarda "Gider kategorisini seçin.", "Gider açıklamasını girin.", "Giderin çıkacağı hesabı seçin." görünür; KDV tutardan büyükse "KDV tutarı gider tutarından büyük olamaz." (KDV tutara DAHİLDİR, yalnız bilgidir). Kayıtta "Gider kaydedildi: <tutar> (<kategori>)." çıkar; listede "Geçerli" gider ve üstte "Geçerli gider" toplamı görünür; hesabın bakiyesi tutar kadar azalır ve hareketlerde "Gider" satırı vardır. Kategori adı ve tedarikçi adı kayıt anında saklanır.
- [ ] **76.2. Kategori ve Tedarikçi Yönetimi:**
  - **Nasıl Test Edilir:** Rol: Site yöneticisi / Yönetim kurulu. "Kategori ve Tedarikçiler"e dokunun; "Kategoriler" sekmesinde hazır kategorilere bakın; yeni kategori ekleyin, bir kategoriyi pasifleştirin. "Tedarikçiler" sekmesinde "Tedarikçi Ekle"yle ad, "Vergi / T.C. kimlik no" (önce 5 rakam, sonra 10 rakam), telefon ve not girip kaydedin. Yönetim kurulu üyesiyle aynı listeye bakın.
  - **Beklenen Sonuç:** İlk açılışta hazır kategoriler gelir (Personel, Elektrik, Su, Doğalgaz/Yakıt, Asansör bakım, Bakım-onarım, Temizlik malzemesi, Sigorta, Yönetici aylığı, Vergi/harç, Banka/noter masrafı, Diğer) ve "Hazır kategori" çipi taşır. Altta "Silinmez: kullanılmayan kategori pasifleştirilir. Geçmiş giderler kayıt anındaki adı korur." yazar; pasif kategoriye yeni gider yazılamaz ("Bu gider kategorisi pasif. Başka bir kategori seçin."). Vergi/T.C. no 10-11 hane olmalıdır ("Numara 10 ya da 11 rakam olmalı."). Kurul üyesi tedarikçi adını görür ama vergi/T.C. no, telefon ve notu görmez ("Kimlik numarası ve telefon kurul üyelerine gösterilmez.").
- [ ] **76.3. Gider Belge Eki (PDF/JPG/PNG):**
  - **Nasıl Test Edilir:** Rol: Site yöneticisi. "Gider Ekle"de "Belge Ekle"yle bir PDF ve bir fotoğraf seçin; bir .docx seçmeyi deneyin; kaydedin. Gider ayrıntısında "Belgeler" bölümüne bakın; "Belge Ekle"yle ek belge ekleyin (toplam 5'e kadar, altıncıyı deneyin).
  - **Beklenen Sonuç:** Bölümde "En çok 5 dosya (PDF, JPG, PNG). Kimlik numarası ve IBAN gibi bilgileri karartın; telefon fotoğrafları konum bilgisi içerebilir." yazar; .docx için "Yalnızca PDF, JPG ve PNG eklenebilir. Eklenmeyen: ..." çıkar. Kayıtta "N belge eklendi." bildirilir (yüklenemeyen olursa hangisi olduğu yazılır; gider belgesiz de kaydedilir). Ayrıntıda "N belge bağlı." ve dosya adı + türü ("Fatura", "Fiş / makbuz", "Fotoğraf", "Diğer") listelenir. Altıncı belge için "Bir gidere en çok 5 belge eklenebilir." çıkar. Gider belgeleri kalıcı silinmez (yasal saklama).
- [ ] **76.4. Çift Kayıt Korumaları:**
  - **Nasıl Test Edilir:** Rol: Site yöneticisi. Aynı tedarikçiyle aynı "Belge / fatura no"yu iptal edilmemiş bir giderde ikinci kez girmeyi deneyin. Aynı kategori, tutar ve tarihle (tedarikçi aynı) 24 saat içinde ikinci bir gider kaydetmeyi deneyin; çıkan uyarıda önce vazgeçin, sonra "Yine de kaydet"i seçin.
  - **Beklenen Sonuç:** Aynı tedarikçi ve fatura numarası: "Bu tedarikçiden aynı belge numarasıyla iptal edilmemiş bir gider zaten var." (kayıt reddedilir; "Aynı tedarikçiden aynı numara ikinci kez girilemez." ipucu forma yazılıdır). Aynı tutar/tarih/kategori: "Aynı gider daha önce kaydedilmiş" penceresi ("Aynı tutar, tarih ve kategoriyle bir gider son 24 saatte kaydedilmiş görünüyor. Önce gider listesini kontrol edin. Gerçekten ikinci bir gider ise devam edebilirsiniz.") çıkar; "Yine de kaydet" bilinçli tekrarı kaydeder. Çift dokunma tek kayıt üretir. İptal edilmiş giderin belge numarası yeniden kullanılabilir (düzeltme akışı çalışsın diye).
- [ ] **76.5. Gideri İptal Etme ve Düzeltme:**
  - **Nasıl Test Edilir:** Rol: Site yöneticisi. Bir giderin ayrıntısında "Gideri İptal Et"e dokunun; nedeni yazıp onaylayın; hesap bakiyesine bakın. Başka bir giderde "Gideri Düzelt"e dokunun; tutarı/kategoriyi değiştirip "Düzelt"e basın. Giderler listesinde "Durum" için "İptal edilen" ve "Hepsi" çiplerini deneyin.
  - **Beklenen Sonuç:** İptal penceresi "<tutar> tutarındaki gider iptal edilir: hesapta ters hareket yazılır, gider silinmez ve "İptal edildi" olarak kalır." der; sonra "Gider iptal edildi." çıkar, ayrıntıda "İptal edildi" rozeti ve "Bu gider iptal edilmiştir (...). Neden: ..." yazar, hesap bakiyesi geri döner. Aynı gider ikinci kez iptal edilemez ("Bu gider zaten iptal edilmiş..."). "Gideri Düzelt" "Düzeltilen gider" bilgisini ve "Bu gider silinmez: iptal edilir ve aşağıdaki bilgilerle yeni bir gider yazılır. İkisi tek işlemde yapılır." notunu gösterir; sonuçta "Gider düzeltildi: ..." çıkar, yeni gider "Bu gider, daha önce iptal edilen bir giderin düzeltmesidir." notu taşır. "İptal edilen" çipinde iptal edilmişler ve "İptal edilen" toplamı görünür.
- [ ] **76.6. Kapalı Ay, Gelecek Tarih ve Hesap Açılışı Kuralları:**
  - **Nasıl Test Edilir:** Rol: Site yöneticisi. Önkoşul: Kapatılmış bir ay (Dönemler sekmesi). "Gider Ekle"de gider tarihini kapatılmış bir aya verin. Gider tarihini yarına ve 5 yıldan eskiye almayı deneyin; tarihi seçilen hesabın açılış tarihinden öncesine verin.
  - **Beklenen Sonuç:** Kapalı aya gider yazılamaz ("Bu dönem kapatılmış; kapalı döneme kayıt eklenemez. Kapalı ayı yalnızca süper kullanıcı yeniden açabilir."); gelecek tarih ve 5 yıldan eski tarih reddedilir ("Tarih bugünden en fazla 5 yıl öncesi olabilir."); hesap açılışından önceki tarih "Tarih, hesabın açılış tarihinden önce olamaz." der. Kapalı ayın giderine belge eklemek/kaldırmak ise serbesttir.
- [ ] **76.7. Gider Listesi: Dönem, Süzgeç, Arama ve Dışa Aktar:**
  - **Nasıl Test Edilir:** Rol: Site yöneticisi / Yönetim kurulu. Giderler sekmesinde "Dönem" çiplerini (Bu ay, Geçen ay, Bu yıl, Tümü), "Kategori" ve "Hesap" listelerini ve "Gider ara"yı (açıklama, tedarikçi ya da belge no) deneyin. Yöneticiyle "Dışa Aktar"a dokunup gider listesini Excel/CSV alın; kurul üyesiyle aynı sekmeye bakın.
  - **Beklenen Sonuç:** Liste "Giderler" başlığı altında süzgece göre değişir; boşken "Bu dönemde gider kaydı yok." / süzgeçte "Bu süzgeç için gider bulunamadı."; üstte "Geçerli gider" (ve iptal edilenler görünürken "İptal edilen") toplamları vardır. "Dışa Aktar" (yönetici) süzgeci dosyaya taşır (`finance_expenses`); kurul üyesinde "Gider Ekle", "Kategori ve Tedarikçiler" yazma işlemleri ve "Dışa Aktar" YOKTUR; tedarikçi vergi/T.C. no ve telefonu görünmez.
- [ ] **76.8. (Geliştirici) Gider Sunucu ve Uygulama Doğrulaması:**
  - **Nasıl Test Edilir:** server klasöründe `node --test` ile `test/finance_*.test.js` (gider/tedarikçi/belge dosyaları) çalıştırın; proje kökünde `flutter test` ile `test/expense_*_test.dart` ve `test/screens/finance_expense_*_test.dart` çalıştırın. Gerçek PG ile `QA_ONLY=finance_4b QA_CONFIRM_DISPOSABLE_DB=yes DB_HOST=127.0.0.1 DB_PORT=55432 DB_USER=postgres DB_PASSWORD= node scripts/qa_platform_pg.mjs` çalıştırın (üretimde ÇALIŞTIRMAYIN).
  - **Beklenen Sonuç:** Testler yeşil: gider iptali ayna hareketle, düzeltme tek işlemde iptal + yeni gider, `DUPLICATE_DOCUMENT_NO` / `DUPLICATE_EXPENSE`, `PERIOD_CLOSED`, `BEFORE_OPENING_DATE`, gider belgesi için yalnız PDF/JPEG/PNG ve gider başına 5 belge sınırı; belge deposu yapılandırılmamışsa gider belgesiz tam çalışır (`DOCUMENTS_NOT_AVAILABLE` / 503 `DOCUMENT_STORAGE_NOT_CONFIGURED`).

---

## 77. 📊 Raporlar ve PDF/CSV/XLSX Çıktı — Faz 4b (2026-10-17)

Finans → "Raporlar" sekmesi beş rapor sunar: Yaşlandırma (borçların gecikme kovaları), Gelir-Gider (aylık tahakkuk/tahsilat/gider/net nakit), Kasa Durumu (hesap bazında hareket özeti), Daire Ekstresi ve Kurul Özeti (yıllık hesap verme özeti, kişi adı içermez). Rakamlar sunucudan, PDF cihazdan gelir; yönetici CSV/XLSX alır, kurul yalnız ekranı okur ve PDF basar. Her raporun altbilgisi: "Bu rapor noter onaylı karar defteri/yasal defterlerin yerine geçmez." Sözleşme: `docs/PLATFORM_FINANS_4B.md` Ö5. Önkoşul: Aidat ve Finans AÇIK TEST sitesi; borçlandırma, tahsilat, gider ve en az bir hesap yapılmış olmalı.

- [ ] **77.1. Raporlar Sekmesi ve Ortak Kurallar:**
  - **Nasıl Test Edilir:** Rol: Site yöneticisi / Yönetim kurulu. Finans → "Raporlar" sekmesini açın; rapor çiplerine ve sayfanın altındaki bilgilere bakın. Her çipe dokunup "Raporu Getir"i deneyin; süzgeçlerden birini değiştirip PDF/dosya düğmelerinin durumuna bakın.
  - **Beklenen Sonuç:** Çipler: "Yaşlandırma", "Gelir-Gider", "Kasa Durumu", "Daire Ekstresi", "Kurul Özeti"; açıklama "Rapor türünü seçin; rakamlar sunucudan alınır, PDF cihazınızda hazırlanır." Rapor gelince "Hazırlanma: <tarih saat>" , kapalı dönem bilgisi ("Kapalı dönem: <ay> ve öncesi. Sonraki aylar kesinleşmemiştir." ya da "Kapatılmış dönem yok: rakamlar kesinleşmemiştir.") ve "Bu rapor noter onaylı karar defteri/yasal defterlerin yerine geçmez." yazar. Süzgeç değişince "Süzgeçler değişti. Güncel rapor için "Raporu Getir"e basın; PDF ve dosya ekrandaki rapora aittir." uyarısı çıkar ve PDF/dosya düğmeleri yeniden getirilene dek pasif kalır. Hata durumunda "0/boş" gösterilmez: "Rapor alınamadı. İnternet bağlantınızı kontrol edip tekrar deneyin." çıkar. Çok sık istekte düğme kısa süre kilitlenir (sunucu meşgulse "REPORT_BUSY" beklemesi).
- [ ] **77.2. Yaşlandırma Raporu:**
  - **Nasıl Test Edilir:** Rol: Site yöneticisi. Önkoşul: Vadesi geçmiş borcu olan en az iki daire (biri 30 günden eski). "Yaşlandırma"da "Rapor tarihi"ni bugün bırakıp "Yalnız borçlu" ve "Tümü" çiplerini deneyin; "Raporu Getir"e basın. Rapor tarihini geçmiş bir güne (örn. 2 ay önce) alıp yeniden getirin. "Daireler" sekmesindeki vadesi geçmiş borç toplamıyla raporun "Vadesi geçmiş toplam"ını karşılaştırın.
  - **Beklenen Sonuç:** Kovalar: "Vadesi gelmemiş", "0-30 gün", "31-60 gün", "61-90 gün", "91-180 gün", "181-365 gün", "366 gün ve üzeri"; "Toplam" kartında "Vadesi geçmiş toplam", "Kullanılmamış alacak" (ve varsa "Ödenmemiş gecikme tazminatı (bilgi)") görünür; daire satırlarında Malik/Kiracı adları ve kova çipleri vardır (en yüksek vadesi geçmiş tutar üstte). Borç yoksa "Bu tarihte vadesi geçmiş borç yok." Rapor tarihi bugün iken "Vadesi geçmiş toplam" Finans "Daireler" sekmesindeki toplam vadesi geçmiş borçla BİREBİR aynıdır. Gelecek tarih ("Rapor tarihi bugünden ileri olamaz.") ve 5 yıldan eski tarih reddedilir. Geçmiş tarihte rakamlar o günün durumunu gösterir.
- [ ] **77.3. Gelir-Gider Raporu:**
  - **Nasıl Test Edilir:** Rol: Site yöneticisi. "Gelir-Gider"de "Başlangıç ayı" ve "Bitiş ayı"nı (ay seçici) bu yılın ilk ayından bugüne ayarlayıp "Raporu Getir"e basın. 37 aylık bir aralık seçmeyi deneyin.
  - **Beklenen Sonuç:** "Dönem toplamı" kartında "Tahakkuk", "Tahsilat", "Gider", "Net nakit" (= tahsilat − gider) görünür; her ay kartında "Kesinleşmiş" / "Kesinleşmemiş" rozeti, "Tahakkuk", varsa "Gecikme tazminatı", "Tahsilat", "Tahsilat oranı", "Gider", "Net nakit" yazar; altta "Gider kategorileri" toplamları vardır. Verisi olmayan aylar da sıfırlı satır olarak gelir (hata ile karışmaz). Başlangıç bitişten sonraysa "Başlangıç ayı bitiş ayından sonra olamaz.", 36 ayı aşarsa "Rapor en çok 36 ay olabilir. Dönemi daraltın." çıkar. Giderler sekmesindeki geçerli gider toplamları ve Tahsilat kayıtlarıyla tutarlıdır.
- [ ] **77.4. Kasa Durumu Raporu:**
  - **Nasıl Test Edilir:** Rol: Site yöneticisi. "Kasa Durumu"nda "Rapor tarihi"ni bugün bırakıp "Raporu Getir"e basın; Kasa sekmesindeki bakiyelerle karşılaştırın. Hesaba eşlenmemiş tahsilat varsa uyarı satırına bakın.
  - **Beklenen Sonuç:** Her hesap için "Açılış", "Tahsilat", "Gider", "Aktarım (giriş)", "Aktarım (çıkış)", "Düzeltme", "Ters kayıt" ve "Bakiye" satırları görünür; "Toplam bakiye" Kasa sekmesindeki "Toplam bakiye" ile aynıdır. Eşlenmemiş tahsilat varsa "Hesaba eşlenmemiş N tahsilat var (toplam ...). Kasa rakamları eksik olabilir." uyarısı çıkar. Hesap yoksa "Bu tarihte hesap bulunmuyor."
- [ ] **77.5. Daire Ekstresi Raporu:**
  - **Nasıl Test Edilir:** Rol: Site yöneticisi. "Daire Ekstresi"nde "Daire" seçip başlangıç ve bitiş tarihini (GG.AA.YYYY) girin; "Ekstreyi Getir"e basın. Bitiş tarihini yarına verin; daire seçmeden getirmeyi deneyin.
  - **Beklenen Sonuç:** Özette "Önceki bakiye", "Borçlandırılan", varsa "Gecikme tazminatı", "Ödenen", "İptal edilen", "Dönem sonu bakiye" ve "Vadesi geçmiş" satırları; altında hareketler "Bakiye: ..." yürüyen bakiyesiyle listelenir ("Daha fazla göster (N)"). Daire seçilmezse "Önce bir daire seçin.", bitiş gelecekteyse "Bitiş tarihi bugünden ileri olamaz." çıkar; ekstre 5.000 satırı aşarsa "Ekstre çok uzun (5.000 satırdan fazla). Tarih aralığını daraltın." Hareket yoksa "Bu aralıkta hareket yok."
- [ ] **77.6. Yönetim Kurulu Özeti:**
  - **Nasıl Test Edilir:** Rol: Site yöneticisi / Yönetim kurulu. "Kurul Özeti"nde ay aralığını bu yıl olarak seçip "Raporu Getir"e basın; bölümleri sırayla okuyun. "En yüksek 10 borçlu daireyi ekle"yi (yalnız yöneticide) açıp yeniden getirin; Denetim Kaydı'na bakın. Yönetim kurulu üyesiyle aynı raporu açın.
  - **Beklenen Sonuç:** Bölümler: "Tahakkuk ve tahsilat", "Alacak durumu", "Gider" ("En büyük gider kalemleri": kategori + tarih + tutar, tedarikçi adı ve açıklama YOK), "Kasa ve banka", "Gecikme tazminatı", "Borç hatırlatma" (gönderilen SAYISI) ve varsa "Uyarılar" (kapatılmamış geçmiş dönem, mutabakat farkı, eşlenmemiş tahsilat, eksi bakiye). Rapor KİŞİ ADI içermez. "En yüksek 10 borçlu daireyi ekle" varsayılan KAPALIDIR ("Yalnız etiket ve tutar; kişi adı yok. Kullanımı denetim kaydına işlenir."), yalnız yöneticide çıkar ve kullanımı Denetim Kaydı'nda "Borçlu listesi görüntülendi" olarak görünür. Kurul üyesi raporu okur ve "Yönetim Kuruluna Sun (PDF)" ile PDF basar; borçlu listesi seçeneğini ve "Dışa Aktar"ı görmez (bu rapor için dosya dışa aktarması hiç yoktur).
- [ ] **77.7. Rapor PDF'i (Yazdır / Paylaş):**
  - **Nasıl Test Edilir:** Rol: Site yöneticisi / Yönetim kurulu. Bir rapor getirin; yöneticide "PDF Yazdır"a, sonra "PDF Paylaş"a dokunun (kurulda "Yönetim Kuruluna Sun (PDF)"); PDF'i açın. Aynısını "Daire Ekstresi" ve "Kurul Özeti" için de yapın; uzun (200+ satır) bir ekstre varsa onu da deneyin.
  - **Beklenen Sonuç:** PDF Türkçe karakterlerle (ş ğ ı İ ö ü ç ₺) bozulmadan çıkar (yazı tipi uygulamaya gömülüdür, internet gerekmez); ekrandaki rakamlarla aynıdır; her sayfada/altbilgide "Bu rapor noter onaylı karar defteri/yasal defterlerin yerine geçmez." yazar; dosya adı ASCII'dir. Uzun çıktıda ekran donmaz. PDF hazırlanamazsa "PDF hazırlanamadı. Tekrar deneyin." çıkar.
- [ ] **77.8. CSV/Excel Dışa Aktarma ve Ekranla Tutarlılık:**
  - **Nasıl Test Edilir:** Rol: Site yöneticisi / Yönetim kurulu. Yaşlandırma, Gelir-Gider, Kasa Durumu ve Daire Ekstresi raporlarında yöneticiyle "Dışa Aktar"a dokunup önce Excel (.xlsx), sonra CSV alın; dosyaları Excel'de açın. Giderler sekmesinden ve "Makbuzlar" penceresinden de birer dosya alın; Kurul Özeti'nde ve kurul üyesi hesabında "Dışa Aktar"ı arayın.
  - **Beklenen Sonuç:** Dosya adları `<rapor>_<site>_<YYYYAAGG>` biçimindedir; tutar sütunları sayı olarak (Excel'de toplanabilir), tarihler tarih olarak, oranlar yüzde olarak gelir; toplamlar ekrandakiyle aynıdır (ekran ve dosya aynı süzgeci kullanır). CSV noktalı virgül ayraçlı, UTF-8'dir; ondalık ayırıcı virgüldür. 20.000 satırı aşan veri "Dışa aktarılacak veri çok büyük (en çok 20.000 satır). Süzgeçlerle daraltın." ile reddedilir. Kurul Özeti'nde ve kurul üyesinde "Dışa Aktar" düğmesi YOKTUR.
- [ ] **77.9. (Geliştirici) Rapor Sunucu ve Uygulama Doğrulaması:**
  - **Nasıl Test Edilir:** server klasöründe `node --test` ile `test/finance_*.test.js` (rapor/dışa aktarma dosyaları) çalıştırın; proje kökünde `flutter test` ile `test/report_*_test.dart` ve `test/screens/finance_report_*_test.dart` çalıştırın. Gerçek PG ile `QA_ONLY=finance_4b QA_CONFIRM_DISPOSABLE_DB=yes DB_HOST=127.0.0.1 DB_PORT=55432 DB_USER=postgres DB_PASSWORD= node scripts/qa_platform_pg.mjs` çalıştırın (üretimde ÇALIŞTIRMAYIN).
  - **Beklenen Sonuç:** Testler yeşil. Değişmezler: `as_of = bugün` için yaşlandırma kovalarının toplamı `overdue_minor` ile eşit; kasa durumunda Σ bakiye = Σ açılış + Σ hareketler; raporlar tek `REPEATABLE READ READ ONLY` işlemde hesaplanır (bir bölüm başarısızsa bütün yanıt 5xx); site başına en çok 2 eşzamanlı ağır rapor (aşılırsa 503 `REPORT_BUSY` + `Retry-After`); `finance/exports/*` kurula 403.

---

## 78. ⏳ Gecikme Tazminatı — Faz 4b: Hukuk Onayı Bayrağı, Önizleme/Onay, "Tazminat Yok" İşareti (2026-10-17)

Gecikme tazminatı OTOMATİK DEĞİLDİR: yönetici her ay için kapatılmış ve bitmiş ayı önizler, onaylar ve tazminat borç olarak yazılır (oran aylık en çok %5, sunucu sınırı). Özellik, sistem düzeyindeki HUKUK ONAYI bayrağı (`finance.legal_ok`, varsayılan KAPALI) açılana kadar KULLANILAMAZ ve site ayarından AÇILAMAZ; bayrağı açma kararı avukatındır (yalnız süper kullanıcı API'siyle: `PUT /admin/finance-legal-gate`; uygulamada bu bayrak için ekran yoktur). Bu yüzden şu anki beklenen durum "Hukuk onayı bekleniyor"dur; onaydan sonraki maddeler planlıdır ve bayrak açıldıktan sonra yalnız bir TEST sitesinde denenir. Sözleşme: `docs/PLATFORM_FINANS_4B.md` Ö2 (KMK m.20: oran aylık yüzde beş).

- [ ] **78.1. Hukuk Onayı Beklenirken Engel İletisi (Şu Anki Durum):**
  - **Nasıl Test Edilir:** Rol: Site yöneticisi. Önkoşul: `finance.legal_ok` KAPALI (varsayılan). Finans → "Dönemler" sekmesinin altındaki "Gecikme tazminatı" bölümüne bakın. "Finans Ayarları"nı açın; "Gecikme tazminatı" bölümüne ve anahtara bakın.
  - **Beklenen Sonuç:** Bölümde "Hukuk onayı bekleniyor" başlığı ve "Gecikme tazminatı, hukuki doğrulama tamamlanınca kullanıma açılır. Şimdilik bu özellik kullanılamıyor." yazar; "Hesapla" düğmesi yoktur. Finans Ayarları'nda uyarı "Hukuk onayı bekleniyor. Gecikme tazminatı onay tamamlanana dek açılamaz." çıkar ve "Gecikme tazminatı kullanılsın" anahtarı PASİFTİR (açılamaz). Bayrak kapalıyken (API ile elle denerseniz) ayar açma isteği "Bu özellik hukuki onay bekliyor; onaylanınca kullanılabilir." ile reddedilir. Hiçbir daireye tazminat yazılmaz.
- [ ] **78.2. Tazminat Ayarları (Hukuk Onayı Sonrası):**
  - **Nasıl Test Edilir:** Rol: Site yöneticisi. Önkoşul: `finance.legal_ok` AÇIK (avukat onayı sonrası; süper kullanıcı `PUT /admin/finance-legal-gate` ile açar) ve yalnız bir TEST sitesi. Finans Ayarları'nda "Gecikme tazminatı kullanılsın"ı açın; başlangıç ayını seçmeden kaydetmeyi deneyin. "Aylık oran (%)"a 6 yazmayı deneyin; sonra 4,5 yazın; "Gün esası" seçeneklerini, "Vadeye ek gün (0-90)" alanını ve "Başlangıç Ayını Seç"i kullanın; kaydedin.
  - **Beklenen Sonuç:** "Otomatik değildir: her ay önizlenir ve onaylanır." yazar. Başlangıç ayı seçilmeden "Tazminat için ilk hesaplanacak ayı (başlangıç ayı) seçin." çıkar ("Geçmişe yönelik sürpriz tahakkuk olmaması için zorunludur; bu aydan önceki aylar hesaplanmaz."). Oran sistem sınırını (aylık %5) aşarsa "Oran %5,00 sistem sınırını aşamaz." çıkar; "Vadeye ek gün" 0-90 dışı reddedilir. Kayıtta "Finans ayarları kaydedildi." çıkar ve Dönemler sekmesinde "Açık", "Önizleme ve onayla çalışır" rozetleri, "Oran %4,50 aylık • ... • vadeye ek N gün" ve "İlk hesaplanacak ay" görünür. Oran/yöntem/ek gün yalnız SONRAKİ hesaplamaları etkiler; ilk çalıştırma yapıldıktan sonra başlangıç ayı değiştirilemez. Uyarı: "Oran ve yöntemin hukuka uygunluğunu hukuki danışmanlıkla doğrulayın; bu ekran hukuki görüş değildir."
- [ ] **78.3. Tazminat Önizleme, Onay ve Yazma:**
  - **Nasıl Test Edilir:** Rol: Site yöneticisi. Önkoşul: Ayarlar açık; başlangıç ayı geçmiş bir ay; o ay KAPATILMIŞ ve BİTMİŞ; vadesi geçmiş borcu olan daireler. Dönemler → "Gecikme tazminatı" bölümünde "Hesapla"ya dokunun; "Hesaplanacak ay"ı sıradaki aya getirin; "Önizle"ye basın. Önizlemeyi (dönem, hesap aralığı, oran, "Toplam tazminat", "Daire listesi") okuyup "Onayla ve Yaz"a, çıkan pencerede "Yaz"a basın. Bir dairenin ekstresine bakın; kapatılmamış ya da bitmemiş bir ayı seçmeyi de deneyin.
  - **Beklenen Sonuç:** Önizleme hiçbir şey kaydetmez ("Önizle düğmesi hiçbir şey kaydetmez."). Önizlemede dönem, "Hesap aralığı: ... (N gün)", oran ve toplam, daire satırları (daire, sorumlu, tutar) görünür. Pencere "Gecikme tazminatını yaz": "<Ay> için N daireye toplam ... gecikme tazminatı borç olarak yazılacak. Yazıldıktan sonra yalnızca SON çalıştırma iptal edilebilir." der; sonra "Gecikme tazminatı yazıldı: <ay>, N daire, toplam ...". Daire ekstresinde "Gecikme tazminatı" kalemi (borç) görünür; tazminat kalemleri sonraki ayların tazminat tabanına girmez (faiz üstüne faiz yok). Kapatılmamış ay için "Önce ilgili dönemi kapatın. Tazminat yalnızca kapatılmış ay için hesaplanır.", bitmemiş ay için "Bu ay henüz bitmedi. Tazminat yalnızca bitmiş ay için hesaplanır.", sırası gelmemiş ay için "Tazminat aylar sırayla hesaplanır. Sıradaki ayı seçin." çıkar. Önizleme ile onay arasında ödeme/ayar değişirse "Veriler değişti, önizleme yenilendi..." uyarısıyla yeniden onay istenir.
- [ ] **78.4. "Nasıl Hesaplandı?" Dökümü (Yönetici ve Sakin):**
  - **Nasıl Test Edilir:** Rol: Site yöneticisi / Daire sakini. Önkoşul: Yazılmış bir tazminat çalıştırması; tazminat kalemi olan daire. Yönetici olarak "Tazminat Satırları"ndan ("Satırlar") bir satırda "Nasıl hesaplandı?"ya dokunun. Sakin hesabıyla "Borcum"da tazminat kaleminin yanındaki "Nasıl hesaplandı?"ya dokunun.
  - **Beklenen Sonuç:** Yönetici dökümünde oran, yöntem, ek gün, "Ay içinde gecikmiş tutarların gün toplamı" ve gecikme dilimleri (tarih aralığı + gecikmiş tutar) yazar. Sakin penceresi "Gecikme Tazminatı" başlığıyla "Bu ay için gecikme tazminatı: ...", "Oran: ... aylık.", "Gün esası: ...", dilimleri ve "Tazminat bu değerlerden site yönetimi sisteminde hesaplanır. Bir yanlışlık olduğunu düşünüyorsanız site yönetimiyle iletişime geçin." notunu gösterir. Sakin yalnız kendi dairesinin kalemi için açıklama görür.
- [ ] **78.5. Daireyi O Ay İçin Muaf Tutma:**
  - **Nasıl Test Edilir:** Rol: Site yöneticisi. Önizlemede bir dairede "Bu ay muaf tut"a dokunun; "Önizlemeyi Yenile"ye basın; onaylayın. Aynı daire için "Muafiyeti kaldır"ı da deneyin (onaydan ÖNCE).
  - **Beklenen Sonuç:** Önizleme yenilenince muaf daire hesap dışı kalır; "N daire muaf tutuldu" başlıklı kutu ("Bu ayın tazminatı bu dairelere KALICI olarak yazılmaz.") daireyi "(yazılmayacak)" tutarıyla listeler. Muaf listesi değişince onay için önizlemenin yenilenmesi gerekir. Yazılan çalıştırma kartında "N muaf" çipi görünür; o ayın tazminatı muaf dairelere KALICI olarak yazılmaz.
- [ ] **78.6. Tazminat Doğmayan Ay: "Ayı Kaydet" (İşaret):**
  - **Nasıl Test Edilir:** Rol: Site yöneticisi. Önkoşul: Hiçbir dairede tazminat doğurmayan bir ay (örn. tüm borçlar ödenmiş). O ay için "Önizle"ye basın; "Ayı Kaydet"e dokunun, penceredeki "Ayı Kaydet"i onaylayın. "Çalıştırma geçmişi"ne bakın; sıradaki ayı kontrol edin.
  - **Beklenen Sonuç:** Önizlemede "Bu ay için tazminat doğuran daire yok. "Ayı Kaydet" ile ay "tazminat yok" olarak kaydedilir ve sıra bir sonraki aya geçer; kaydetmezseniz sonraki aylar hesaplanamaz." yazar; pencere "Tazminat yok - ayı kaydet" başlığıyla açılır ("hiçbir daireye borç yazılmaz"); sonra "<Ay> için "tazminat yok" olarak kaydedildi. Hiçbir daireye borç yazılmadı." çıkar. Geçmişte kayıt "Tazminat yok (işaret)" çipiyle ve "Bu ay için tazminat doğmadı; borç yazılmadı." yazısıyla görünür; "Sıradaki ay" bir sonraki aya geçer. Bu işaret de "Son çalıştırmayı iptal et" ile geri alınabilir ("Ters çevrilecek borç yoktur.").
- [ ] **78.7. Son Çalıştırmayı İptal Etme ve Zincir Kuralları:**
  - **Nasıl Test Edilir:** Rol: Site yöneticisi / Süper kullanıcı. Çalıştırma geçmişinde son çalıştırma için "Son çalıştırmayı iptal et" → "Çalıştırmayı İptal Et"i onaylayın; "Satırlar"a bakın. Aynı ayı yeniden hesaplayın; bir önceki çalıştırmayı iptal etmeyi deneyin. Süper kullanıcıyla tazminat çalıştırması bulunan ayı "Dönemler"den yeniden açmayı deneyin.
  - **Beklenen Sonuç:** "Son Çalıştırmayı İptal Et" penceresi "... tazminat çalıştırması (N daire, ...) iptal edilir: henüz iptal edilmemiş tüm kalemlere ters kayıt yazılır. Sonra aynı ay yeniden hesaplanabilir." der; sonra "<Ay> gecikme tazminatı çalıştırması iptal edildi." çıkar, kalemler ters kayıtla düzeltilir (silinmez; satırlarda "İptal edildi"). Yalnız SON çalıştırma iptal edilebilir (diğerleri için "Bu çalıştırma iptal edilemiyor: yalnızca son (aktif) tazminat çalıştırması iptal edilir..."). Aylar sırayla hesaplanır, boşluk/tekrar olmaz; tazminat çalıştırması varken ayı yeniden açmak "Bu ay yeniden açılamaz: sonraki aylar için tazminat çalıştırması var. Önce çalıştırmayı iptal edin." ile reddedilir. Denetim Kaydı'nda "Gecikme tazminatı yazıldı" ve "Gecikme tazminatı iptal edildi" satırları görünür.
- [ ] **78.8. (Geliştirici) Tazminat Sunucu ve Uygulama Doğrulaması:**
  - **Nasıl Test Edilir:** server klasöründe `node --test` ile `test/finance_*.test.js` (tazminat hesabı/ayar dosyaları) çalıştırın; proje kökünde `flutter test` ile `test/late_fee_*_test.dart` ve `test/screens/finance_late_fee_*_test.dart` çalıştırın. Gerçek PG ile `QA_ONLY=finance_4b QA_CONFIRM_DISPOSABLE_DB=yes DB_HOST=127.0.0.1 DB_PORT=55432 DB_USER=postgres DB_PASSWORD= node scripts/qa_platform_pg.mjs` çalıştırın (üretimde ÇALIŞTIRMAYIN). Hukuk bayrağı: süper kullanıcı belirteciyle `GET /admin/finance-legal-gate` ve `PUT /admin/finance-legal-gate {"legal_ok":true}` (yalnız test ortamında; canlıda karar avukatındır).
  - **Beklenen Sonuç:** Testler yeşil: gün-gün kaba kuvvet simülatörü üretim hesabıyla eşleşir (`fee = ⌊(2·S·R + 10000·D) / (20000·D)⌋`, BigInt), oran üst sınırı `LATE_FEE_MAX_MONTHLY_BP = 500`, zincir tetikleyicisi, `PREVIEW_STALE`, boş plan `record_empty`, 40P01 = 0. Bayrak kapalıyken `PUT settings` ile tazminat/hatırlatma açma `409 LEGAL_APPROVAL_REQUIRED`; bayrak değişimi Denetim Kaydı'nda "Finans hukuk onayı bayrağı güncellendi" olarak görünür.

---

## 79. ✉️ Borç Hatırlatma — Faz 4b: Önizleme, Gönderim, Muafiyet ve Tercih (2026-10-17)

Yönetici vadesi geçmiş borcu olan dairelerin sorumlularına (borç ve bildirimler kime gidiyorsa) e-postayla bilgilendirme gönderir: her gönderim önizlenir ve onaylanır, günde en çok bir çalıştırma, aynı adrese 7 günde en çok bir hatırlatma, ardışık hatırlatma sınırından sonra daire "elden takip" listesine düşer (e-posta gitmez). İleti tanıtım içermez; konuda tutar/ad/daire yoktur. Tutar yalnız doğrulanmış hesap e-postasına yazılır. Sakin "Bildirim Tercihleri"nden "Borç hatırlatma e-postaları"nı kapatabilir; e-postadaki bağlantıyla abonelikten çıkılırsa duyuru e-postaları da durur. Gecikme tazminatı gibi hukuk onayı bayrağı (`finance.legal_ok`) AÇILANA kadar kullanılamaz (açma kararı avukatındır). Sözleşme: `docs/PLATFORM_FINANS_4B.md` Ö6.

- [ ] **79.1. Hukuk Onayı Beklenirken Engel İletisi (Şu Anki Durum):**
  - **Nasıl Test Edilir:** Rol: Site yöneticisi. Önkoşul: `finance.legal_ok` KAPALI (varsayılan). Finans → "Daireler" sekmesinin üstündeki "Borç hatırlatma" kartına bakın. "Finans Ayarları"nda "Borç hatırlatma" bölümüne ve anahtara bakın.
  - **Beklenen Sonuç:** Kartta "Hukuk onayı bekleniyor" başlığı ve "Borç hatırlatma, hukuki doğrulama tamamlanınca kullanıma açılır. Şimdilik bu özellik kullanılamıyor." yazar; "Borç Hatırlat" düğmesi yoktur. Ayarlarda "Hukuk onayı bekleniyor. Borç hatırlatma onay tamamlanana dek açılamaz." uyarısı çıkar ve "Borç hatırlatma kullanılsın" anahtarı pasiftir. Hiçbir e-posta gönderilmez.
- [ ] **79.2. Profilde "Borç hatırlatma e-postaları" Anahtarı:**
  - **Nasıl Test Edilir:** Rol: Daire sakini / Site yöneticisi / Bireysel kullanıcı. Çekmeceden "Profilim"i açın; "Bildirim Tercihleri" bölümüne inin; "E-posta ile duyuru al" ve "Borç hatırlatma e-postaları" anahtarlarını sırayla kapatıp açın. Profilim'i yeniden açıp anahtarların kaydedilmiş olduğunu doğrulayın.
  - **Beklenen Sonuç:** Bölüm "Bildirim Tercihleri" başlığıyla "Duyuruları ve borç hatırlatmalarını nasıl almak istediğinizi seçin." yazar. "Borç hatırlatma e-postaları" anahtarının açıklaması: "Aidat borcunuz için site yönetiminin gönderdiği hatırlatma e-postaları. Kapalıyken bu hatırlatmalar e-postayla gelmez; duyurular ve borç bilgileriniz uygulamada görünmeye devam eder." İki anahtar birbirinden BAĞIMSIZDIR (biri değişince diğeri değişmez) ve kalıcıdır. E-postadan abonelikten çıkılmışsa "E-posta bildirimleri e-postadaki bağlantıyla durduruldu." notu görünür. "Telefon bildirimi" satırı ayrıdır.
- [ ] **79.3. Hatırlatma Ayarları (Hukuk Onayı Sonrası):**
  - **Nasıl Test Edilir:** Rol: Site yöneticisi. Önkoşul: `finance.legal_ok` AÇIK (avukat onayı sonrası) ve yalnız bir TEST sitesi; sunucuda e-posta (SMTP) yapılandırılmış. Finans Ayarları'nda "Borç hatırlatma kullanılsın"ı açın; "En az vadesi geçmiş tutar", "En az gecikme günü (1-120)", "İki hatırlatma arası en az gün (7-90)" ve "Ardışık hatırlatma sınırı (1-6)" değerlerine aralık dışı değerler yazıp kaydetmeyi deneyin; sonra geçerli değerlerle kaydedin.
  - **Beklenen Sonuç:** Anahtar açıklaması "E-posta ile bilgilendirme; her gönderim önizlenir ve onaylanır." Sınır dışı değerde "Değer 1 ile 120 arasında olmalı." (ve benzerleri); en az tutar 1,00 ₺'den küçükse "En az vadesi geçmiş tutar en az 1,00 ₺ olmalıdır." çıkar. Sunucuda e-posta yapılandırılmamışsa "E-posta gönderimi bu sunucuda yapılandırılmamış; hatırlatma gönderilemez." uyarısı görünür. Kayıttan sonra Daireler sekmesindeki kartta "En az ... ve N gün gecikmiş borç • N günde bir • en çok N ardışık hatırlatma" özeti yazar.
- [ ] **79.4. Borç Hatırlat: Önizleme:**
  - **Nasıl Test Edilir:** Rol: Site yöneticisi. Önkoşul: Hatırlatma ayarı açık; vadesi eşiği aşmış borcu olan daireler (sorumluları e-postalı kişiler); biri doğrulanmış hesap e-postalı, biri hesapsız (yönetimin girdiği e-posta) kişi. Daireler sekmesinde "Borç Hatırlat"a dokunun; "Ton" olarak "Nazik hatırlatma"yı seçin; "Ek not (isteğe bağlı)"a bir bağlantı (örn. www.ornek.com) yazmayı deneyin, sonra düz bir cümle yazın. "Önizle"ye basın; sayılara, "Örnek daireler"e ve "Gönderilmeyenler" listesine bakın.
  - **Beklenen Sonuç:** Pencere "Borç Hatırlat": "Vadesi geçmiş borcu olan dairelerin sorumlularına bilgilendirme e-postası gönderilir. İleti tanıtım içermez; konu satırında tutar, ad ya da daire yazmaz. Önce önizleme gösterilir." Tonlar "Nazik hatırlatma" ("Merhaba,") ve "Resmî hatırlatma" ("Sayın site sakini"); not bağlantı/alan adı/e-posta içeremez ("Not bağlantı, alan adı ya da e-posta adresi içeremez.") ve en çok 300 karakterdir. Önizleme hiçbir şey göndermez: "N daire, M kişi", "K kişiye tutarlı, L kişiye tutarsız ileti gider.", "Toplam vadesi geçmiş: ..." ve adres/ad GÖSTERİLMEZ. "Gönderilmeyenler" sayıları: adresi olmayan kişi; e-posta tercihi kapalı / abonelikten çıkmış kişi; aynı adrese zaten gidecek (tekrar); yedi günlük adres sınırına takılan; tutarı eşiğin altında kalan daire; gecikme günü eşiğin altında kalan daire; son hatırlatmadan beri yeterli süre geçmemiş daire; ardışık hatırlatma sınırına ulaşan daire; muaf listesindeki daire; alıcısı bulunamayan daire. Sınıra ulaşan daireler için "Elden takip: N daire ardışık hatırlatma sınırına ulaştı; e-posta gitmez, yönetimce elden takip edilmelidir."
- [ ] **79.5. Borç Hatırlat: Gönderim ve E-posta İçeriği:**
  - **Nasıl Test Edilir:** Rol: Site yöneticisi / Daire sakini. Önkoşul: Bir önceki madde; alıcı olarak kendi test e-posta adresiniz olan bir dairenin sorumlusu. Önizlemeden sonra "Onayla ve Gönder"e basın; çıkan "Hatırlatmaları gönder" penceresinde "Gönder"i onaylayın. Alıcının e-posta kutusunda iletiyi açın (konu, gövde, altbilgi); iletideki "Abonelikten çık" bağlantısını bu denemede KULLANMAYIN. Aynı gün ikinci kez "Borç Hatırlat" → önizleme → gönder deneyin.
  - **Beklenen Sonuç:** Onay penceresi "N kişiye (M daire için) borç hatırlatma e-postası gönderilecek. Gönderim başlayınca geri alınamaz; yalnız henüz gönderilmemiş iletiler iptal edilebilir." der; sonra "Hatırlatma gönderimi başlatıldı: N kişi, M daire. İlerlemeyi Hatırlatma Geçmişi'nden izleyebilirsiniz." çıkar. E-posta konusu "[<Site adı>] Ödeme hatırlatması"dır (tutar, ad, daire YOK). Gövde "Merhaba," (ya da "Sayın site sakini,") ile başlar, "<Site> için <daire> dairesine ait vadesi geçmiş ödeme görünüyor." der; tutar satırı ("Vadesi geçmiş tutar: 1.250,00 ₺ (en eski vade: GG.AA.YYYY).") YALNIZ doğrulanmış hesap e-postasına gider, diğer adreslere "Güncel tutar için uygulamadaki "Borcum" bölümüne bakabilir veya site yönetimine başvurabilirsiniz." yazar. "Ödemeyi yaptıysanız bu iletiyi dikkate almayın; ..." kapanışı, varsa "Yönetim notu: ...", ve altbilgide "Bu ileti bir tanıtım iletisi değildir; site yönetiminin aidat/avans kayıtlarına ilişkin bilgilendirmesidir." ile abonelikten çıkma bağlantısı bulunur. Aynı gün ikinci çalıştırma "Bugün zaten bir hatırlatma gönderildi. Günde en çok bir çalıştırma yapılabilir." ile reddedilir; aile üyesi ve aynı adrese ikinci ileti gönderilmez.
- [ ] **79.6. Hatırlatma Geçmişi ve Bekleyenleri İptal:**
  - **Nasıl Test Edilir:** Rol: Site yöneticisi / Yönetim kurulu. "Hatırlatma Geçmişi"ni açın; en son çalıştırmanın sayılarına bakın. Gönderim sürerken (çok alıcılı bir denemede) "Bekleyenleri iptal et" → "Bekleyenleri İptal Et"i onaylayın. Yönetim kurulu üyesiyle aynı geçmişe bakın.
  - **Beklenen Sonuç:** Geçmiş "Çalıştırmalar" altında her çalıştırma için durum ("Gönderiliyor" / "Tamamlandı" / "İptal edildi"), "N daire • M kişi", ton ve sayılar ("Gönderilen", "Bekleyen", "Başarısız", "Adresi olmayan", "Tercih nedeniyle atlanan", "Tekrar adres", "Sınıra takılan", "Güncel olmadığı için gönderilmeyen", "İptal edilen") gösterilir; alıcı adı/adresi GÖRÜNMEZ. İptal penceresi "Henüz gönderilmemiş (bekleyen) iletiler iptal edilir. Yolda olan iletiler sonuçlanır; zaten gönderilenler geri alınamaz." der; sonra "Bekleyen hatırlatmalar iptal edildi." çıkar. Kurul üyesi geçmişi okur ama "Borç Hatırlat", "Muaf Daireler" ve iptal düğmelerini görmez.
- [ ] **79.7. Daireyi Hatırlatmadan Muaf Tutma:**
  - **Nasıl Test Edilir:** Rol: Site yöneticisi. Bir dairenin ekstresinde "Hatırlatmadan Muaf Tut"a dokunun, nedeni yazıp "Muaf Tut"a basın. "Borç Hatırlat" → "Önizle"de "Gönderilmeyenler" listesine bakın. Daireler sekmesindeki "Muaf Daireler"i açıp "Daire Seç" ile başka bir daire ekleyin; ilk daireyi listeden çıkarın.
  - **Beklenen Sonuç:** Ekstreden "<Daire> borç hatırlatmalarından muaf tutuldu." çıkar; pencere "Muaf tutulan daireye borç hatırlatma e-postası gönderilmez. İstediğiniz zaman muafiyeti kaldırabilirsiniz." der ve muafsa "Bu daire borç hatırlatmalarından muaf." ile "Muafiyeti Kaldır" sunar ("<Daire> yeniden borç hatırlatmalarına dahil edildi."). Önizlemede "Muaf listesindeki daire" sayısı artar ve o daire alıcı olmaz. "Hatırlatmadan Muaf Daireler" penceresi "Anlaşmazlık ya da dava altındaki daireleri buraya ekleyin; muaf dairelere borç hatırlatması gönderilmez." der; boşken "Muaf daire yok."
- [ ] **79.8. Alıcı Tercihi ve Abonelikten Çıkma:**
  - **Nasıl Test Edilir:** Rol: Daire sakini. Önkoşul: Hatırlatma gönderilebilir durumda; sakin hesabının profilinde "Borç hatırlatma e-postaları" KAPALI. Yönetici olarak o sakinin dairesi için "Borç Hatırlat" → "Önizle"ye bakın. Sakini profilden açıp tekrar önizleyin; (isteğe bağlı) hatırlatma e-postasındaki "Abonelikten çık" bağlantısını TEST adresinde kullanın.
  - **Beklenen Sonuç:** Tercih kapalıyken o kişi alıcı sayılmaz: "E-posta tercihi kapalı / abonelikten çıkmış kişi" sayısına girer ve ileti gitmez; tercih açılınca bir sonraki önizlemede alıcı olur. Abonelikten çıkış (e-posta bağlantısıyla) ORTAK bastırma listesine yazar: o adrese duyuru e-postaları da durur (sayfa "site duyuru ve borç hatırlatma e-postaları" der). Sakinin uygulamadaki duyuru ve "Borcum" bilgisi bundan etkilenmez.
- [ ] **79.9. (Geliştirici) Hatırlatma Sunucu ve Uygulama Doğrulaması:**
  - **Nasıl Test Edilir:** server klasöründe `node --test` ile `test/finance_*.test.js` (hatırlatma/kuyruk/e-posta dosyaları) çalıştırın; proje kökünde `flutter test` ile `test/reminder_*_test.dart` ve `test/screens/finance_reminder_*_test.dart` çalıştırın. Gerçek PG ile `QA_ONLY=finance_4b QA_CONFIRM_DISPOSABLE_DB=yes DB_HOST=127.0.0.1 DB_PORT=55432 DB_USER=postgres DB_PASSWORD= node scripts/qa_platform_pg.mjs` çalıştırın (üretimde ÇALIŞTIRMAYIN).
  - **Beklenen Sonuç:** Testler yeşil: önizleme/gönderim `PREVIEW_STALE`, günlük 1 çalıştırma (`REMINDER_DAILY_LIMIT`), adres başına 7 günde 1 (`capped`), bayat borç koruması (gönderim anında yeniden doğrulama; `resolved`), SMTP yokken çalıştırma hiç oluşmaz (`EMAIL_NOT_CONFIGURED`), hukuk bayrağı kapalıyken gönderim anı kapısı (`legal_gate`), kuyruk işçisi log'a adres/ad yazmaz, `noteHasLink` bağlantılı notu reddeder.

---

## 80. 🧹 Hesap Silme Önizlemesi ve Veri Dosyası — Belgeler, Makbuz, Hatırlatma ve Bildirim Cihazları (2026-10-17)

"Hesabımı Sil" önizlemesi (64. bölüm) ve "Verilerimi İndir" dosyası yeni modüllerin verisini de açıkça sayar: yüklediğiniz belgeler siteye ait olduğu için SİLİNMEZ (yükleyen adı "Silinmiş Kullanıcı" olur); makbuz ve tahsilat kayıtları yasal mali kayıt olarak DEĞİŞTİRİLMEDEN kalır; size gönderilecek bekleyen aidat hatırlatma e-postalarının adresi silinir ve gönderilmez; telefon bildirimi cihaz kayıtları (jetonlarıyla) silinir. Veri dosyasına yüklenen belgelerin KAYIT bilgisi, makbuz özeti ve hatırlatma geçmişi eklenir; belge BAŞLIĞI, dosya içeriği, ödeyen adı ve doğrulama kodu dosyaya girmez. Sözleşme: `docs/PLATFORM_SATISA_HAZIRLIK.md` §1.5-§1.6; yasal metin `server/legal/account_deletion.md`.

- [ ] **80.1. Silme Önizlemesinde Belge, Makbuz ve Hatırlatma Maddeleri:**
  - **Nasıl Test Edilir:** Rol: Site yöneticisi / Daire sakini. Önkoşul: Silinmesinde sakınca olmayan TEST hesabı: en az bir belge yüklemiş (yönetici) ya da bir daireye bağlı (sakin); varsa bekleyen aidat hatırlatması olan. Profilim → "Gizlilik ve Veri" → "Hesabımı Sil" sayfasını açın. "Silinecekler" ve "Saklanacaklar" kartlarını sonuna kadar okuyun (SİLMEYİ SÜRDÜRMEYİN).
  - **Beklenen Sonuç:** "Saklanacaklar" kartında hesapta belge yüklemişse "Yüklediğiniz belgeler (N dosya sürümü) site yönetiminde kalır (belgeler siteye aittir); yükleyen adı "Silinmiş Kullanıcı" olarak görünür." maddesi; bir siteye/daireye bağlıysa "Makbuz ve tahsilat kayıtları (düzenleyen yönetici ve ödeyen adını içeren makbuz anlık görüntüsü dahil) yasal mali kayıt saklama yükümlülükleri gereği DEĞİŞTİRİLMEDEN saklanır; makbuz anlık görüntüsündeki ad anonimleştirilmez." maddesi yazar. "Silinecekler" kartında bekleyen aidat hatırlatma e-postası varsa "Size gönderilmek üzere bekleyen aidat hatırlatma e-postalarının (N) kayıtlarındaki e-posta adresiniz silinir; bu hatırlatmalar gönderilmez." maddesi yazar. Belge yüklememiş hesapta belge maddesi hiç çıkmaz (sıfır sayılı madde yazılmaz).
- [ ] **80.2. Hesap Silinince Belge ve Makbuz Kalır:**
  - **Nasıl Test Edilir:** Rol: Site yöneticisi. Önkoşul: Silinmesinde sakınca olmayan, başka yöneticisi olan sitede ikinci bir yönetici TEST hesabı; bu hesabın yüklediği bir belge ve düzenlediği/ödediği bir makbuz var. O hesabın "Hesabımı Sil" akışını tamamlayın (feda edilebilir hesap!). Başka bir yönetici hesabıyla "Belgeler"de o belgeyi açıp "Yükleyen" satırına ve belgenin açılabilirliğine bakın; dairenin ekstresinde makbuza bakın.
  - **Beklenen Sonuç:** Belge SİLİNMEZ ve sakinlerce açılmaya devam eder; ayrıntıda yükleyen adı "Silinmiş Kullanıcı" görünür. Makbuz ve tahsilat kayıtları ekstrede aynen durur (makbuzdaki ad anonimleştirilmez). Hesapla ilgili bekleyen aidat hatırlatması gönderilmez.
- [ ] **80.3. Veri Dosyasına Eklenen Bölümler:**
  - **Nasıl Test Edilir:** Rol: Site yöneticisi / Daire sakini. Önkoşul: Belge yüklemiş ve/veya makbuzu olan, aidat hatırlatması almış (varsa) TEST hesabı. Profilim → "Verilerimi İndir" ile dosyayı hazırlayıp bilgisayarda bir metin düzenleyicide açın. "receipts", "uploaded_documents", "finance_reminders_received", "push_devices" ve "notification_preferences" bölümlerine ve "excluded" listesine bakın; belge başlığını dosyada aratın.
  - **Beklenen Sonuç:** "uploaded_documents" her satırda yalnız `document_id`, `version_no`, `site_code`, `site_name`, `category`, `file_name`, `mime_type`, `size_bytes`, `version_status`, `recorded_at`, `completed_at` alanlarını taşır: dosya adı, tür, boyut, tarih, kategori ve sürüm numarası VAR; belgenin BAŞLIĞI, dosya içeriği, durumu/silinme zamanı, kitle ve sürüm notu YOKTUR. "receipts" yalnız numara, tür, durum, tutar, tarihler ve daire bilgisidir (ödeyen adı, düzenleyen yönetici, doğrulama kodu YOK). "finance_reminders_received" yalnız çalıştırma tarihi, ton, durum ve daire sayısını taşır (e-posta metni, tutar, not, adres özeti YOK). "notification_preferences" içinde `email_announcements`, `email_finance_reminders` ve `push_*` alanları bulunur. "excluded" listesi bunların neden dışarıda kaldığını Türkçe açıklar (örn. "Yüklediğiniz belgelerin dosya içerikleri, depolama anahtarları, içerik özetleri (hash), kitle / hedef bilgisi ve sürüm notları: ..."; "Makbuzlar ve tahsilat belgeleri: ..."; "Aidat hatırlatma e-postaları: ...").
- [ ] **80.4. Telefon Bildirimi Cihazları Silme ve Dışa Aktarmada:**
  - **Nasıl Test Edilir:** Rol: Site yöneticisi / Daire sakini. Önkoşul: Telefon bildirimi (Firebase) kurulu bir sürüm ve bu hesapta kayıtlı en az bir bildirim cihazı. Hesapta telefon bildirimini açıp cihazı kaydedin; "Verilerimi İndir" dosyasındaki "push_devices" bölümüne bakın. "Hesabımı Sil" sayfasındaki "Silinecekler" kartına bakın.
  - **Beklenen Sonuç:** "push_devices" her cihaz için yalnız platform, uygulama sürümü, bildirimin açık olup olmadığı ve tarihleri taşır; bildirim jetonu ve kurulum kimliği dosyada YOKTUR ("excluded" listesinde bu açıklanır). Silme önizlemesinde "Telefon bildirimi için kayıtlı cihazlarınız (N) ve bunların bildirim jetonları ile bekleyen telefon bildirimleriniz silinir." maddesi çıkar.
- [ ] **80.5. (Geliştirici) Hesap Silme ve Veri Dosyası Yeni Bölüm Doğrulaması:**
  - **Nasıl Test Edilir:** server klasöründe `node --test test/account_deletion_service.test.js test/account_export_service.test.js test/account_routes.test.js` çalıştırın. Tek kullanımlık yerel PostgreSQL ile `QA_ONLY=account QA_CONFIRM_DISPOSABLE_DB=yes DB_HOST=127.0.0.1 DB_PORT=55432 DB_USER=postgres DB_PASSWORD= node scripts/qa_platform_pg.mjs` çalıştırın (üretimde ÇALIŞTIRMAYIN).
  - **Beklenen Sonuç:** Testler yeşil. Silme önizleme metinleri `server/legal/account_deletion.md` ile tutarlıdır; dışa aktarma yeni bölümleri (`receipts`, `uploaded_documents`, `finance_reminders_received`, `push_devices`) şemadan türetilir ve belge başlığı/ödeyen adı/doğrulama kodu/jeton seçilmez; yeni tablolar yoksa (eski şema) bölümler boş döner ve silme önizlemesi bozulmaz.

---

## 81. 🎨 Cihaz Etiketleyici (company_qr_tool) Yeni Arayüz — Tek Pencere, Adımlı Akışlar (2026-10-19)

Masaüstü etiketleme aracı tek pencereli, sol menülü yeni arayüze geçti: Etiketle, Kayıtlı cihazlar, Cihaz testi, Cihaz yazılımı, Ekran yazılımı. Kimlik okuma, karekod, sunucu kaydı, derleme ve yükleme mantığı değişmedi. Başarı mesajları sağ altta kendiliğinden kaybolan bildirim oldu; hatalar yine pencere olarak gelir. Başlatma: `company_qr_tool/launch_company_qr_tool.bat`.

- [ ] **81.1. Açılış, Menü ve Kısayollar:**
  - **Nasıl Test Edilir:** Rol: Şirket (üretim) bilgisayarı. `launch_company_qr_tool.bat` ile açın. Sol menüdeki sayfalara tıklayın; sonra Ctrl+1…Ctrl+5 ile geçin. Ekran ölçeği %125/%150 olan bir bilgisayarda da açın.
  - **Beklenen Sonuç:** Pencere tam ekran açılır; solda lacivert menü, SmartKeyPass logosu ve altta "Sunucu anahtarı hazır" (yeşil nokta) ya da "Sunucu anahtarı yok" (sarı nokta, üzerine gelince nasıl tanımlanacağı yazar) görünür. Sayfa geçişi kısa bir kaymayla olur, menüdeki seçim çizgisi yeni öğeye kayar. Yazılar yüksek ölçekte bulanık değildir.
- [ ] **81.2. Kart Takınca Liste Kendiliğinden Yenilenir:**
  - **Nasıl Test Edilir:** Etiketle sayfasında bir ESP32 kartını USB ile takın, birkaç saniye bekleyin; sonra çıkarın. Ardından "Yeniden tara" (F5) düğmesine basın.
  - **Beklenen Sonuç:** Takınca kart 2 saniye içinde listeye gelir, sağ altta "Kart bağlandı: COMx" bildirimi çıkar; tek kart bağlıysa kendiliğinden seçilir. Çıkarınca listeden düşer ve "Kart çıkarıldı" bildirimi gelir. Hiç kart yokken tabloda "Bağlı kart yok" açıklaması görünür.
- [ ] **81.3. Etiketleme Akışı (Seç → Kimliği oku → Kaydet ve yazdır):**
  - **Nasıl Test Edilir:** Listeden kartı seçip "Kimliği oku"ya basın (çift tık ya da Enter da olur).
  - **Beklenen Sonuç:** Okurken sağdaki rozet "Kimlik okunuyor", alt çubukta dönen gösterge görünür. Bitince "Kimlik okundu" bildirimi gelir, karekod hafif bir animasyonla belirir, kimlik büyük yazıyla ve kopyalama düğmesiyle görünür; satırın durumu "Karekod hazır" olur, üstteki adım göstergesinde ilk iki adım tamamlanır. Ayrıca "QR oluştur" düğmesine basmak gerekmez.
- [ ] **81.4. Sunucuya Kaydet, Yazdır, PNG Kaydet:**
  - **Nasıl Test Edilir:** Kimliği okunmuş kartta sırayla "Sunucuya kaydet", "Yazdır" ve "PNG kaydet"e basın. Sonra kimliği okunmamış başka bir kartı seçin.
  - **Beklenen Sonuç:** Kaydederken rozet "Kaydediliyor", bitince "Kaydedildi" olur; satırda "✓ Kaydedildi" yazar, adım göstergesinin üçü de tamamlanır. Sunucu anahtarı yoksa "Yerel kayıt tamam, sunucuya gönderilemedi" uyarı penceresi çıkar. Yazdır yazıcıya gönderir; PNG `output\` klasörüne kaydedilir ve bildirim gelir. Kimliği okunmamış kart seçiliyken kaydet/yazdır/PNG düğmeleri kapalıdır (başka kartın etiketi basılamaz).
- [ ] **81.5. Kimlik Okunamazsa Düğmeler Kilitlenmez:**
  - **Nasıl Test Edilir:** Kartın portunu başka bir seri monitörde açık tutun (ya da okuma sürerken kabloyu çekin) ve "Kimliği oku"ya basın.
  - **Beklenen Sonuç:** Çözüm adımlarını anlatan "Kimlik okunamadı" penceresi çıkar; kapatınca düğmeler yeniden kullanılabilir (eskiden okuma hatasından sonra düğmeler kalıcı olarak kapalı kalıyordu).
- [ ] **81.6. Kayıtlı Cihazlar Sayfası:**
  - **Nasıl Test Edilir:** "Kayıtlı cihazlar" sayfasını açın. Arama kutusuna kimliğin bir parçasını yazın, Esc ile temizleyin. Bir satır seçin; Yazdır, PNG kaydet, kimlik kopyala düğmelerini ve sağ tık menüsünü deneyin. "Karekodlu PDF raporu"na basın. (Silmeyi yalnız TEST kaydıyla deneyin.)
  - **Beklenen Sonuç:** Arama kutusunun yanındaki rozet cihaz sayısını ("3 cihaz" / aramada "1 / 3 cihaz") gösterir; eşleşme yoksa "Eşleşen cihaz yok" yazar. Seçilen cihazın karekodu sağda belirir; kayıt tarihleri yerel saatle görünür. PDF açılır ve "PDF raporu hazır" bildirimi gelir. Sunucuya ulaşılamazsa tablonun altında sarı uyarı simgesiyle neden yazar.
- [ ] **81.7. Cihaz Testi Sayfası:**
  - **Nasıl Test Edilir:** "Cihaz testi"nde portu seçip "Bağlan"a basın; "Hızlı testler"deki Röle HIGH/LOW/pulse, Kamera testi ve Pin bulma düğmelerini deneyin; "Temizle"ye basın; "Bağlantıyı kes" ile kapatın.
  - **Beklenen Sonuç:** Başlıktaki rozet "Bağlanıyor" → "Bağlı: COMx" olur. Bilgiler Kimlik ve yazılım, Bluetooth, Donanım, Wi-Fi ve ağ, MQTT gruplarında dolar; değişen değer kısa süre vurgulanır. Seri kayıtta gönderilen komutlar mavi, hatalar kırmızı görünür. Kart aynı ağdaysa "Yerel yayın (UDP)" alanı dolar (eskiden hiç dolmuyordu); Windows Güvenlik Duvarı ilk seferde Python için izin isteyebilir, özel ağa izin verin.
- [ ] **81.8. Cihaz Yazılımı: Derle → Sürüm oluştur → Dağıt:**
  - **Nasıl Test Edilir:** "Cihaz yazılımı"nda kart türünü ve sürüm numarasını seçip "Derle", ardından "Sürüm oluştur"a basın; "Hedef kart" listesinden kartı seçip "USB ile karta yükle"ye basın. Bir de bilerek hatalı sürüm (ör. `1.2`) ya da derlenmeyen bir kodla deneyin.
  - **Beklenen Sonuç:** Sıradaki adımın düğmesi koyu renkle vurgulanır. Derlerken ilerleme çubuğunda gidip gelen şerit ve "Derleniyor" rozeti görünür; yüklemede yüzde ilerler; bitince "TMM · Yükleme tamamlandı" bildirimi gelir ve adım göstergesi tamamlanır. Hedef kart listesi Etiketle sayfasındaki seçimle eşittir. Derleme/sürüm/sunucu/ZIP hatasında hata penceresi çıkar (eskiden bu hatalarda pencere hiç açılmıyordu) ve rozet "Başarısız" olur.
- [ ] **81.9. Çalışma Arkadaşı İçin ZIP:**
  - **Nasıl Test Edilir:** Sürüm oluşturduktan sonra "Çalışma arkadaşı için ZIP"e basıp bir dosya adı seçin; ZIP'i açıp `flash_smartkeypass_usb.bat` ve `README.txt` dosyalarına bakın.
  - **Beklenen Sonuç:** ZIP oluşur ve "ZIP hazır" bildirimi gelir (eskiden bu düğme hata verip ZIP oluşturmuyordu). BAT ve README'de hedef donanım adı (`esp32-c3` / `esp32-wroom`) doğru yazar.
- [ ] **81.10. Ekran Yazılımı Sayfası:**
  - **Nasıl Test Edilir:** Ekran modülü bağlıyken "Ekran yazılımı" sayfasını ilk kez açın (açılışta portlar taranır, kartlar yeniden başlayabilir). "Bağlan", canlı test düğmeleri (Ping, Test karekodu, Kapı açıldı, Ayarlar, Ana ekran, Yeniden başlat), "Sürüm oluştur" ve "USB ile ekrana yükle"yi deneyin.
  - **Beklenen Sonuç:** Ekran bulununca yeşil rozette "COMx · SmartKeyPass 2.4" ekran yanıt verdi" yazar; bulunamazsa sarı/kırmızı rozet nedenini söyler. Komutlar seri kayıtta mavi görünür; yükleme bitince "TMM" bildirimi gelir ve seri konsol kendiliğinden yeniden bağlanır.
- [ ] **81.11. Animasyon Efektleri Kapalıyken:**
  - **Nasıl Test Edilir:** Windows Ayarlar → Erişilebilirlik → Görsel efektler → "Animasyon efektleri"ni kapatıp uygulamayı yeniden açın; sayfalar arasında geçin, bir kimlik okuyun.
  - **Beklenen Sonuç:** Sayfa geçişleri, bildirimler ve karekod animasyonsuz, anında görünür; işlevler aynı çalışır.

---

## 82. 🌐 Cihaz Testi "Genel IP (WAN)" Alanı Dolmuyor — Açık Hata (2026-10-19)

Cihaz Etiketleyici → "Cihaz testi" sayfasındaki "Genel IP (WAN)" alanı şu an hiç dolmuyor. Neden: araç kartın genel IP'sini tanımsız bir adresten (`API_BASE_URL/api/devices`) istiyor, bu yüzden istek hiç gönderilmiyor. Sunucu kartın genel IP'sini aslında tutuyor (`device_runtime_status.public_ip`, MQTT köprüsü yazar), ama bunu şirket anahtarıyla (`X-Company-Key`) okunabilir şekilde veren bir uç yok; bu bilgi yalnızca yönetici oturumu isteyen uçlardan dönüyor. Bu hata henüz düzeltilmedi; sayfadaki diğer alanlar etkilenmez.

- [ ] **82.1. Mevcut Durumu Doğrula (Bilinen Hata):**
  - **Nasıl Test Edilir:** Rol: Şirket (üretim) bilgisayarı. Wi-Fi'ye ve MQTT'ye bağlı (internete çıkan) bir kapı kartını USB ile bağlayın. Cihaz Etiketleyici → "Cihaz testi" → portu seçip "Bağlan"a basın; kart durum bloğunu yazana kadar bekleyin (gerekirse kartı yeniden başlatın).
  - **Beklenen Sonuç (şu an):** Cihaz kimliği, Yerel IP, MQTT gibi alanlar dolar; "Genel IP (WAN)" alanı "-" olarak kalır. Uygulama donmaz, hata penceresi çıkmaz.
- [ ] **82.2. Genel IP'nin Sunucuda Var Olduğunu Doğrula:**
  - **Nasıl Test Edilir:** Rol: Süper kullanıcı / Site yöneticisi. 82.1'deki kartın genel IP (WAN) bilgisine mobil uygulamada (yönetici hesabıyla) kartın durum bilgisinden bakın.
  - **Beklenen Sonuç:** Mobil uygulamada genel IP görünüyorsa veri sunucuda var demektir; sorun yalnızca masaüstü aracının bu bilgiye erişememesidir. Görünmüyorsa sorun daha geniştir (sunucu kartın genel IP'sini hiç almıyor) ve düzeltmeye bu da eklenmelidir.
- [ ] **82.3. Düzeltmeden Sonra Kabul Ölçütü (Düzeltme Yapılınca İşaretlenir):**
  - **Nasıl Test Edilir:** Düzeltilmiş sürümle 82.1 adımlarını tekrarlayın. Sonra `company_qr_tool/.env` içindeki `COMPANY_API_KEY` satırını geçici olarak kaldırıp uygulamayı yeniden açın ve tekrar deneyin. Son olarak bilgisayarın internetini kesip deneyin. Bitince anahtarı geri koyun.
  - **Beklenen Sonuç:** Durum bloğu geldikten birkaç saniye içinde "Genel IP (WAN)" alanı kartın genel IP'siyle dolar (değer kısa süre vurgulanır) ve 82.2'de görülen değerle aynıdır; yalnızca bağlı kartın IP'si gösterilir, başka kartınki gösterilmez. Anahtar yokken ya da sunucuya ulaşılamazken alan "-" kalır, uygulama donmaz ve hata penceresi çıkmaz.
- [ ] **82.4. (Geliştirici) Düzeltme Kapsamı ve Doğrulaması:**
  - **Nasıl Test Edilir:** Sunucuya şirket anahtarıyla (`requireCompanyAccess`) korunan, tek bir cihaz kimliği için yalnızca genel IP'yi (ve son görülme zamanını) döndüren salt okunur bir uç ekleyin (ör. `GET /api/company/devices/:deviceUid/runtime`). `company_qr_tool/app.py` içindeki `DeviceTesterPage._fetch_public_ip` bu uca `company_request_headers` ile istek atsın; tanımsız `API_BASE_URL` kaldırılsın. server klasöründe `npm test && npm run lint`; `company_qr_tool` için `python -m py_compile app.py ui_kit.py` çalıştırın.
  - **Beklenen Sonuç:** Uç anahtarsız istekte 401, geçersiz kimlikte 400, bilinmeyen cihazda 404 döner; yanıt yalnızca istenen cihazın genel IP'sini içerir (cihaz listesi, kullanıcı ya da site bilgisi dönmez). Testler ve lint yeşil, derleme hatasız.

---

## 83. 🗳️ Anket ve Oylama, Ziyaretçi ve Kargo, Yönetim Türü Terimleri ve Kartlı Geçiş Altyapısı — F9/F10/F11 (2026-10-19)

Üç yeni modül ve yönetim türü terimleri: Anket ve Oylama (migration 044, F11.01), Ziyaretçi ve Kargo (migration 045, F11.03), Kartlı Geçiş (migration 046, F10; YALNIZ sunucu kayıt altyapısı, uygulama ekranı ve kart okuyucu YOK). Yeni modüller varsayılan KAPALIDIR: süper kullanıcı siteye açar ya da site yöneticisi "Modüller" ekranından "Modül Talep Et" ile ister. Yönetim türü terimleri (F9) için migration yoktur: beş tür seçilebilir, kelimeler (İş Merkezi: Ofis/Firma, Kooperatif: Hisse/Üye, Alışveriş Merkezi: Mağaza/Kiracı firma) ve "Bu tür için önerilir" işareti türe göre gelir. Ziyaretçi ve kargoda e-posta/telefon bildirimi YOKTUR. Denemeleri bir TEST sitesinde yapın. Sözleşmeler: `docs/PLATFORM_ANKET.md`, `docs/PLATFORM_ZIYARETCI_KARGO.md`, `docs/PLATFORM_GECIS_GENISLEME.md`, `docs/PLATFORM_MODUL_SISTEMI.md` (Yönetim türü terimleri). Faz listesi: F9, F10, F11.

- [ ] **83.1. Migration 044-046 Uygulandı mı (Operasyon):**
  - **Nasıl Test Edilir:** Rol: Sunucu yöneticisi. VPS'te server klasöründe `node scripts/migrate.js --status` (salt okunur) çalıştırın.
  - **Beklenen Sonuç:** `044_survey`, `045_visitor_log` ve `046_access_cards` uygulanmış görünür; bekleyen migration yoktur (tablolar: `surveys`, `survey_votes`, `visitor_entries`, `access_cards`).
- [ ] **83.2. Modülleri Siteye Açma ve Menüler:**
  - **Nasıl Test Edilir:** Rol: Site yöneticisi / Süper kullanıcı. TEST sitesinde site yöneticisi "Modüller" ekranında "Anket ve Oylama" ve "Ziyaretçi ve Kargo" kartlarında "Modül Talep Et"e basar; süper kullanıcı "Modül Talepleri"nden onaylar (ya da "Modüller" ekranından doğrudan açar). Sonra yönetici, görevli (kapıcı/güvenlik), yönetim kurulu üyesi ve daire sakini hesaplarıyla menüye bakın. "Modüller" ekranında "Kartlı Geçiş", "Plaka Tanıma", "HGS Geçişi" ve "Kamera (CCTV) Bağlantısı" kartlarına da bakın.
  - **Beklenen Sonuç:** Yöneticide "Anket ve Oylama" ve "Ziyaretçi ve Kargo"; kurul üyesinde ikisi salt okunur; görevlide yalnız "Ziyaretçi ve Kargo"; sakinde "Anketler" ve "Ziyaretçi ve Kargo" menüsü görünür. Modül kapalıyken bu menüler yoktur. "Kartlı Geçiş" açılabilir ama açılsa da uygulamada yeni ekran çıkmaz (uygulama ekranı ve kart okuyucu henüz yok); Plaka Tanıma, HGS Geçişi ve Kamera (CCTV) Bağlantısı "Yakında…" çipiyle gelir ve açılamaz.
- [ ] **83.3. Anket Açma ve Yayınlama:**
  - **Nasıl Test Edilir:** Rol: Site yöneticisi. "Anket ve Oylama" → "Yeni Anket": başlık, soru ve en az iki seçenek ("Seçenek ekle"); "Hedef kitle" "Tüm site"; isteğe bağlı "Kapanış günü"; "Taslak Kaydet". Taslağı açıp "Yayınla"ya basın ve onaylayın. İkinci bir ankette "Hedef kitle"yi "Bloklar" seçip bir blok ekleyin, "Daire başına tek oy"u açın, "Anonim oylama"yı kapatıp yayınlayın.
  - **Beklenen Sonuç:** Taslak kaydedilir ("Anket taslak olarak kaydedildi.") ve sakinde görünmez. Yayınlanınca "Anket yayınlandı." yazar; yayınlanan anketin sorusu ve seçenekleri değiştirilemez. Liste durum süzgeciyle (Taslak / Açık / Kapalı / Tümü) daralır.
- [ ] **83.4. Oy Verme (Sakin):**
  - **Nasıl Test Edilir:** Rol: Daire sakini. "Anketler" → "Açık anketler"de anketi açın, bir seçenek seçip "Oy ver" → "Oyunuzu onaylayın" penceresinde onaylayın; aynı ankete yeniden oy vermeyi deneyin. "Daire başına tek oy" açık ankette aynı dairenin ikinci sakin hesabıyla oy vermeyi deneyin; seçilmeyen bloktaki bir sakin "Anketler"e baksın.
  - **Beklenen Sonuç:** Oy verince "Oyunuz alındı." yazar ve sonuçlar (seçenek başına oy ve yüzde) görünür; oy değiştirilemez, ikinci oy kabul edilmez. Aynı dairenin ikinci hesabı oy veremez ve nedeni yazılır. Seçilmeyen bloktaki sakin anketi hiç görmez. Oy vermeden sonuç görünmez ("Sonuçlar henüz paylaşılmadı.").
- [ ] **83.5. Anketi Kapama, Oy Verenler ve Kurul:**
  - **Nasıl Test Edilir:** Rol: Site yöneticisi / Yönetim kurulu. Yönetici anonim olmayan anketi açıp "Oy verenleri göster"e basar, sonra "Anketi Kapat"a basıp onaylar. Sakin "Kapanan anketler"e baksın. Yönetim kurulu üyesi hesabıyla "Anket ve Oylama"yı açın.
  - **Beklenen Sonuç:** Yönetici sonucu "Toplam N oy · M kişiden %X katılım" biçiminde görür; anonim olmayan ankette "Oy verenler" listesinde kişi, daire ve seçim yazar (anonim ankette kimin ne oy verdiği görünmez). Kapatınca "Anket kapatıldı." yazar, oy verilemez, kapanan anket yeniden açılamaz; sakin sonucu "Kapanan anketler"de görür. Kurul üyesi anketleri ve sonuçları görür; yeni anket, yayınla ve kapat düğmeleri yoktur, oy verenleri göremez ("... yalnızca görüntüleyebilirsiniz. Oy verenler görünmez." notu).
- [ ] **83.6. Ziyaretçi ve Kargo Kaydı (Görevli):**
  - **Nasıl Test Edilir:** Rol: Görevli / Site yöneticisi. Önkoşul: kapıcı/güvenlik hesabı siteye görevli olarak eklenmiş. "Ziyaretçi ve Kargo" → "Yeni Kayıt": "Tür" Kargo, "Kargo firması / gönderen", "Daire (isteğe bağlı)" alanından bir daire; "Kaydet". İkinci kayıt: "Tür" Ziyaretçi, "Ziyaretçi adı", aynı daire. Kargoyu "Teslim edildi olarak işaretle", ziyaretçiyi "Ayrıldı olarak işaretle" ile kapatın. "Kayıt ara" kutusunu (ad, firma veya daire) ve süzgeçleri deneyin.
  - **Beklenen Sonuç:** Kargo "Bekliyor" ("Kargo kaydı açıldı (Bekliyor)."), ziyaretçi "İçeride" ("Ziyaretçi kaydı açıldı (İçeride).") durumuyla açılır. Kapatınca "Teslim edildi" / "Ayrıldı" olur ve kapanış zamanı görünür; kapanan kayıt yeniden açılamaz, kayıt silinmez (yanlış kayıt "İptal" ile kapatılır). Kurul üyesinde "Yeni Kayıt" ve durum düğmeleri yoktur ("Yönetim kurulu üyesi olarak kayıtları yalnızca görüntüleyebilirsiniz.").
- [ ] **83.7. Sakin Rozeti ve Görünürlük:**
  - **Nasıl Test Edilir:** Rol: Daire sakini. 6. adımdaki dairenin sakini menüde "Ziyaretçi ve Kargo"nun yanındaki sayı rozetine bakar, ekranı açar, "Yeni" rozetli kaydı açıp kapatır ve menüye döner. Başka bir dairenin sakini aynı ekrana baksın.
  - **Beklenen Sonuç:** Görülmemiş kayıtlar kalın ve "Yeni" rozetiyle listelenir; üstte "Görülmemiş N kaydınız var." yazar ve menüde sayı rozeti çıkar. Kayıt açılınca "Yeni" kalkar ve menüdeki sayı azalır. Kaydeden görevlinin adı sakine gösterilmez. Başka dairenin kayıtları ve daire seçilmeden açılan kayıtlar hiçbir sakine görünmez. E-posta ve telefon bildirimi gelmez (bu sürümde yok).
- [ ] **83.8. Yönetim Türü Seçimi ve Terimler:**
  - **Nasıl Test Edilir:** Rol: Süper kullanıcı / Site yöneticisi. "Yeni Site Ekle" (ya da "Site Kurulum Sihirbazı") penceresinin "Yönetim Türü" bölümünde beş türe bakın; İş Merkezi, Kooperatif ve Alışveriş Merkezi türünde birer TEST sitesi kurun (tür sonradan değiştirilemez). Her sitede "Kişiler" ekranının ikinci sekmesine ve "Modüller" ekranına bakın; birini "Site Düzenle" ile açın.
  - **Beklenen Sonuç:** Beş türün hepsi seçilebilir; her satırda tek cümlelik açıklama ve farklı kelimelerin özeti yazar (örn. "Daire → Ofis, Sakin → Firma, ..."). "Kişiler"in ikinci sekmesi İş Merkezi'nde "Ofisler" (arama "Ofis ara"), Kooperatif'te "Hisseler", Alışveriş Merkezi'nde "Mağazalar" olur; Apartman ve Site ile Rezidans'ta "Daireler" kalır. "Modüller" ekranında türe önerilen modüllerde "Bu tür için önerilir" çipi görünür (örn. İş Merkezi: İş Takibi, Ziyaretçi ve Kargo, Aidat ve Finans, Belgeler); modüller yine kapalı gelir. "Site Düzenle"de tür yalnız çip olarak görünür ve "Yönetim türü site kurulduktan sonra değiştirilemez." yazar.
- [ ] **83.9. (Geliştirici) Gerçek PostgreSQL QA:**
  - **Nasıl Test Edilir:** Tek kullanımlık yerel PostgreSQL ile server klasöründe `QA_ONLY=chain,live,survey,visitor_log,card_access QA_CONFIRM_DISPOSABLE_DB=yes DB_HOST=127.0.0.1 DB_PORT=55432 DB_USER=postgres DB_PASSWORD= node scripts/qa_platform_pg.mjs` çalıştırın (üretimde ÇALIŞTIRMAYIN).
  - **Beklenen Sonuç:** Seçilen bölümlerin tümü yeşil biter. Hesap silme kuralları belgelerdeki gibidir: anket oyu kalır ve hesap bağı koparılır (anonimleşir), ziyaretçi/kargo kaydı siteye kalır ("Silinmiş Kullanıcı"), kart kişi kaydına bağlı kalır ve dışa aktarmada maskelidir.

## 84. 📷 İş Takibi Fotoğraf Eki ve Personel Raporu; Rezervasyon/Konsiyerj Sonuç İşareti — F5/F6/F16 (2026-10-19)

İş takibi taleplerine fotoğraf eklenebilir: talep başına en çok 4 fotoğraf, her biri en çok 5 MB, yalnız JPEG/PNG/WebP (iPhone'da galeriden seçilen HEIC fotoğraf otomatik JPEG'e çevrilir). Kişi başına sitede en çok 200 MB, site başına en çok 10 GB fotoğraf saklanır. Sakin, yönetimin eklediği fotoğrafta kişi adını değil "Yönetim" yazısını görür. Yönetici ve kurul için "Talepler" ekranında "Rapor" sekmesi vardır. Rezervasyon ve konsiyerjde yönetim karar verince ya da not yazınca sakinde okunmamış işareti çıkar. E-posta ve telefon bildirimi YOKTUR. İş Takibi ile Rezervasyon ve Konsiyerj modülleri varsayılan KAPALIDIR; önce süper kullanıcı siteye açar. Sözleşmeler: `docs/PLATFORM_IS_TAKIBI.md`, `docs/PLATFORM_REZERVASYON.md`, `docs/KAPASITE_VE_DISK_YONETIMI.md`; yasal metin `server/legal/account_deletion.md`.

- [ ] **84.1. Fotoğraflı Talep Açma:**
  - **Nasıl Test Edilir:** Rol: Daire sakini. Önkoşul: İş Takibi modülü sitede açık. "Taleplerim" → "Yeni Talep"; kategori, konum, başlık ve açıklama yazın; "Fotoğraf Ekle" ile 1–4 fotoğraf seçip kaydedin. Talebi açıp fotoğraf şeridindeki bir fotoğrafa dokunun; tam ekranda iki parmakla büyütün, oklarla ya da kaydırarak diğer fotoğrafa geçin.
  - **Beklenen Sonuç:** Talep "Yeni" durumuyla ve fotoğraflarıyla kaydedilir; listede fotoğraf sayısı rozeti görünür. Yükleme sırasında ilerleme çubuğu çıkar. Bir fotoğraf yüklenemezse talep yine açılır ve "Talep oluşturuldu, N fotoğraf yüklenemedi." yazar; eksik fotoğraf talep ayrıntısından yeniden eklenebilir. Büyütülmüş fotoğrafta kaydırma sayfayı değiştirmez, fotoğrafı gezdirir.
- [ ] **84.2. Fotoğraf Sınırları:**
  - **Nasıl Test Edilir:** Rol: Daire sakini. Aynı talebe beşinci fotoğrafı eklemeyi; 5 MB'tan büyük bir resmi; PDF gibi resim olmayan bir dosyayı seçmeyi deneyin. Kapanmış ya da iptal edilmiş bir talebe fotoğraf eklemeyi deneyin.
  - **Beklenen Sonuç:** Beşinci fotoğrafta "En fazla 4 fotoğraf eklenebilir." yazar. Büyük ya da resim olmayan dosya ayrı satırda nedeniyle reddedilir ve diğer geçerli fotoğrafların yerini kapmaz. Kapanmış/iptal talepte "Fotoğraf Ekle" düğmesi yoktur. Kota dolarsa "Bu sitedeki fotoğraf kotanız doldu (en çok 200 MB)…" uyarısı çıkar.
- [ ] **84.3. iPhone'da Galeriden Fotoğraf Seçme:**
  - **Nasıl Test Edilir:** Rol: Daire sakini, iPhone. Kamerayla bir fotoğraf çekin (iPhone varsayılanı HEIC). "Fotoğraf Ekle"ye dokunun.
  - **Beklenen Sonuç:** Fotoğraflar (galeri) seçicisi açılır (Dosyalar uygulaması DEĞİL); seçilen HEIC fotoğraf JPEG olarak yüklenir ve talepte görünür. Android'de sistem seçicisinden "Görseller"/Galeri ile seçilebilir.
- [ ] **84.4. Yönetim Fotoğrafı, Roller ve Silme:**
  - **Nasıl Test Edilir:** Rol: Site yöneticisi, görevli, yönetim kurulu, sakin. Yönetici ya da görevli olarak bir talebe fotoğraf ekleyin; sakin hesabıyla aynı talebe bakın (fotoğrafa dokunun, ekran okuyucu varsa okutun). Kurul hesabıyla talebi açın. Talebi "Kapandı" yapıp yönetici olarak bir fotoğrafı silin; aynısını görevli hesabıyla deneyin.
  - **Beklenen Sonuç:** Sakin, yönetimin eklediği fotoğrafta "Yönetim", kendi eklediğinde "Siz" görür; görevlinin adı hiçbir yerde (alt yazı, ekran okuyucu) görünmez. Sakinin listesinde yönetim fotoğrafı için okunmamış işareti çıkar; sakinin kendi eklediği fotoğraf işaret çıkarmaz. Kurul fotoğrafları görür, ekleme/silme düğmesi yoktur. Yönetici kapanmış talepteki fotoğrafı silebilir (uygunsuz içerik ya da KVKK talebi için); görevli ve sakin kapanmış talepte silemez. Sakin yalnız kendi eklediği fotoğrafı silebilir.
- [ ] **84.5. Personel Performans Raporu:**
  - **Nasıl Test Edilir:** Rol: Site yöneticisi / Yönetim kurulu / Görevli. "Talepler" → "Rapor" sekmesi; "Bu ay", "Son 30 gün", "Son 90 gün" ve "Özel aralık" (GG.AA.YYYY) deneyin; 366 günden uzun bir aralık girin. Bir talebi "Çözüldü" yapıp raporu yenileyin. Görevli hesabıyla sekmeye bakın.
  - **Beklenen Sonuç:** Özet kartları (açılan, çözülen, kapanan, iptal, şu an açık, gecikmiş, ortalama/medyan çözüm süresi), görevli bazında tablo (açık, gecikmiş, çözülen, ortalama süre, zamanında %) ve kategori satırları gelir. Çözüm, çözüldüğü anda talebe atanmış kişiye yazılır; o anda atanmamışsa "Atanmamış" satırına düşer. 366 günden uzun aralık reddedilir. Kurul salt okur; görevlide "Rapor" sekmesi yoktur.
- [ ] **84.6. Rezervasyon Kararı: Okunmamış İşareti:**
  - **Nasıl Test Edilir:** Rol: Daire sakini + Site yöneticisi. Önkoşul: Rezervasyon modülü açık, onay modu "yönetici onaylı" bir alan. Sakin rezervasyon yapar; yönetici birini onaylar, birini gerekçeyle reddeder. Sakin hesabıyla "Rezervasyon" ekranını açın; varsayılan "Yaklaşan" süzgecinde kalın; sonra "Tümünü göster"e dokunun ve reddedilen kaydı açın.
  - **Beklenen Sonuç:** "Rezervasyonlarım" sekmesinde sayı rozeti çıkar; okunmamış kayıtta "Yeni güncelleme" etiketi görünür. Reddedilen kayıt varsayılan süzgeçte gizliyse "N rezervasyonunuzda yeni güncelleme var." uyarısı ve "Tümünü göster" düğmesi çıkar. Kayıt açılınca etiket ve rozet kaybolur. Sakinin kendi yaptığı işlemler (oluşturma, kendi iptali) ve yöneticinin kendi rezervasyonunda kendi kararı işaret çıkarmaz.
- [ ] **84.7. Konsiyerj Talebi: Okunmamış İşareti:**
  - **Nasıl Test Edilir:** Rol: Daire sakini + Görevli. Sakin konsiyerj talebi açar; görevli durumu "Hazırlanıyor" yapıp sakine görünen not yazar, sonra "Tamamlandı" yapar. Sakin hesabıyla "Konsiyerj" sekmesine bakın.
  - **Beklenen Sonuç:** Sekmede sayı rozeti ve talepte "Yeni güncelleme" etiketi çıkar; tamamlanan talep "Açık" süzgecinde gizliyse "N talebinizde yeni güncelleme var." uyarısı ve "Tümünü göster" çıkar. Talep açılınca işaret kaybolur.
- [ ] **84.8. Hesap Silme ve Veri Dosyası: Talepler, Fotoğraflar, Rezervasyonlar:**
  - **Nasıl Test Edilir:** Rol: Daire sakini. Önkoşul: Silinmesinde sakınca olmayan TEST hesabı; fotoğraflı bir talebi, gelecekte onaylı bir rezervasyonu ve açık bir konsiyerj talebi var. Profilim → "Gizlilik ve Veri" → "Hesabımı Sil" önizlemesine bakın (SÜRDÜRMEYİN). "Verilerimi İndir" dosyasında "work_items_created", "work_item_comments", "work_item_attachments_uploaded", "reservations_made", "concierge_requests_made" bölümlerine ve "excluded" listesine bakın. (Feda edilebilir hesapla) silmeyi tamamlayıp yönetici hesabıyla talebe, alanın takvimine ve konsiyerj listesine bakın.
  - **Beklenen Sonuç:** "Saklanacaklar" kartında talepler/yorumlar ve "İş takibi taleplerine eklediğiniz fotoğraflar (N) taleple birlikte site yönetiminde kalır" maddesi; "Silinecekler"de gelecekteki rezervasyonlar ve açık konsiyerj talepleri sayıyla yazar. Dosyada fotoğrafların yalnız kayıt bilgisi (dosya adı, tür, boyut, durum, tarih) vardır, içeriği yoktur. Silme sonrası talep ve fotoğraflar sitede kalır (açan/yükleyen "Silinmiş Kullanıcı"); gelecekteki rezervasyonlar ve açık konsiyerj talepleri iptal olur, kapasite boşalır.
- [ ] **84.9. (Geliştirici) Test, QA ve Yedek Doğrulaması:**
  - **Nasıl Test Edilir:** server klasöründe `node --test test/work_attachments.test.js test/work_report.test.js test/reservation_unread.test.js` çalıştırın. Tek kullanımlık yerel PostgreSQL ile `QA_ONLY=chain,live,work_tracking,reservation,account QA_CONFIRM_DISPOSABLE_DB=yes DB_HOST=127.0.0.1 DB_PORT=55432 DB_USER=postgres DB_PASSWORD= node scripts/qa_platform_pg.mjs` çalıştırın (üretimde ÇALIŞTIRMAYIN). Sunucuda yedek sonrası `~/ops` günlüğüne ve `kapi_work_attachments_*.tgz.enc` arşivine bakın; `restore_test.sh` çıktısında fotoğraf tutarlılığı satırını okuyun.
  - **Beklenen Sonuç:** Testler ve seçilen QA bölümleri yeşil. Fotoğraflar belge arşivinden AYRI, şifreli `kapi_work_attachments_*` arşivinde yedeklenir; geri yükleme denemesi hazır fotoğrafların arşivde olduğunu doğrular.
