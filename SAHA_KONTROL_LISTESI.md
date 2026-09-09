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
- [ ] **7.3. ESP32-WROOM-32E Kartı Fiziki Doğrulaması:**
  - **Nasıl Test Edilir:** Yeni röle kartı kargodan geldiğinde test edilecek.
  - **Beklenen Sonuç:** `role_kontrol.h` GPIO pinleri kesinleştirilip ilk saha testi yapılacak.

---

*Eklenmesini istediğiniz veya test aşamasında özel olarak kontrol etmek istediğiniz bir madde olursa lütfen bildirin.*

---

## 8. GM60 ve Display UART Entegrasyonu (ESP32-WROOM)

- [ ] **8.1. GM60 Pin 16/17 UART2 Okuma:**
  - **Nasıl Test Edilir:** GM60 TX -> WROOM GPIO16 (RX), GM60 RX -> WROOM GPIO17 (TX) bağlayın. Barkod/QR okutun.
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


