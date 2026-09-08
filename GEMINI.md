# ÇALIŞMA VE KODLAMA KURALLARI (RULES)

Bu kurallar projede geliştirme yapılırken MUTLAKA ve İSTİSNASIZ olarak uygulanmalıdır:

1. **Modüler Yapıda Çalış:**
   - Kodları monolitik veya devasa tek bir dosya içerisine yazma.
   - Backend tarafında servisler (`services/`), yönlendiriciler (`routes/`), veri erişimi (`db.js`) ve yardımcılar (`utils/helpers.js`) şeklinde katmanlı ve modüler mimariyi koru.
   - Mobil tarafta modeller, servisler, UI sayfaları ve yeniden kullanılabilir widget bileşenleri ayrımına sadık kal.
   - Firmware tarafında başlık (`.h`) ve kaynak (`.cpp`) modüllerini koru.

2. **Geçmiş Özellikleri ve Geriye Dönük Uyumluluğu Asla Bozma:**
   - Kullanıcı tarafından açıkça bir özelliğin geliştirilmesi veya değiştirilmesi talep edilmedikçe, geçmişte yapılmış ve çalışan hiçbir özelliği, API uç noktasını, parametreyi veya iş mantığını bozma, kaldırma ya da değiştirme.
   - Yeni eklenen tüm özellikler geriye dönük uyumlu (backward-compatible) olmalı; mevcut istemciler ve sahadaki cihazlar kesintiye uğramamalıdır.

3. **ESP32-C3 Süper Mini Sahada Aktif - Çalışmasını Asla Bozma:**
   - ESP32-C3 Süper Mini cihazları sahada aktif olarak çalışmaya devam etmektedir.
   - ESP32-C3'ün çalışmasını, pin konfigürasyonunu, BLE/Wi-Fi/MQTT haberleşmesini veya işlevlerini bozacak/aksatacak hiçbir kodlama veya mimari değişiklik yapma.
   - Flash ve RAM kısıtlarını (NimBLE, bellek optimizasyonları) her zaman gözet.

4. **Güncellemeleri Cihaza Göre (İzole Hedefli) Yap:**
   - Yeni donanım (örneğin ESP32-WROOM-32E röle kartı) ve mevcut donanım (ESP32-C3 Süper Mini) birbirinden tamamen bağımsız iki donanım hedefidir.
   - Firmware derlemeleri, OTA manifest dosyaları (`/firmware/esp32-c3/manifest.json` ve `/firmware/esp32-wroom/manifest.json`) ve versiyon kontrolleri cihaz mimarisine (`hardware_target`) göre ayrı ayrı yürütülmeli ve asla birbirine karışmamalıdır.
   - Her cihaz yalnızca kendi mimarisine ait güncellemeleri çekmelidir.

5. **Saha Kontrol Listesini Güncel Tut:**
   - Kullanıcı yeni bir özellik talep ettiğinde ve bu özellik kodlanıp tamamlandığında, `SAHA_KONTROL_LISTESI.md` dosyasına ilgili özelliği test adımı (`- [ ]`) olarak ekle.
   - Test adımında özelliğin nasıl test edileceğini ve beklenen sonucunu net olarak açıkla.

