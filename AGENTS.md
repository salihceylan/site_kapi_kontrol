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

6. **Mobil ve Arayüz Tasarımlarında Taşma (Overflow) Kesinlikle Yasaktır:**
   - Flutter/mobil ve masaüstü arayüz geliştirmelerinde hiçbir ekranda yatay veya dikey taşma ("Right/Bottom overflowed by X pixels") hatası oluşmayacak şekilde tasarım yapılması ZORUNLUDUR.
   - Tüm `Row`, `Column`, `Wrap` ve liste elemanlarında metin ve rozet gibi dinamik içerikler daima esnek/uyarlanabilir olmalıdır (`Flexible`, `Expanded`, `maxLines: 1`, `overflow: TextOverflow.ellipsis` veya `Wrap`).
   - Küçük ekranlar, farklı DPI oranları, uzun metinler (cihaz isimleri, mimari etiketleri, durum rozetleri) hesaba katılmalı; sabit genişlikler yerine esnek ve kırılmayan (responsive) tasarım garantilenecektir.

7. **Uygulamayı Kapatıp Açmayı Gerektirmeyen Canlı ve Otomatik Yenileme Şartı:**
   - Hiçbir sayfada veya işlem sonrasında (cihaz ekleme, kapı atama/çıkarma, düzenleme, silme, yetki verme vb.) kullanıcının güncel verileri ve durumu görmek için uygulamayı kapatıp açması KESİNLİKLE GEREKMEMELİDİR.
   - Yapılan her başarılı işlem/diyalog sonrasında ilgili sayfanın verileri otomatik olarak yeniden çekilmeli (`refresh()`, `loadData()`, `setState`) ve UI anında güncellenmelidir.
   - Sayfalarda ayrıca kullanıcının dilediğinde sayfayı tazeleyebileceği `RefreshIndicator` (aşağı çekip yenileme) ve/veya yenileme butonları mutlaka aktif tutulmalıdır.

8. **Sunucuyu (Backend VPS) Her Zaman Güncelle ve Canlı Doğrula (Zorunlu):**
   - Backend tarafında (servisler, rotalar, veritabanı şeması, migrasyonlar, MQTT köprüsü vb.) yapılan her değişiklik sonrasında sunucu güncellemesi MUTLAKA ve İSTİSNASIZ olarak canlı ortama (VPS `178.210.161.55` / `api.gudeteknoloji.com.tr`) anında dağıtılmalıdır.
   - Değiştirilen dosyalar SCP/SSH ile sunucuya aktarılmalı (`/var/www/site_kapi_kontrol/server/`), varsa migrasyon/şema kontrolleri çalıştırılmalı ve PM2 süreci (`pm2 restart kapi-api --update-env`) yeniden başlatılmalıdır.
   - Güncelleme sonrasında PM2 logları (`pm2 logs kapi-api --lines 20 --nostream`), sağlık kontrolü (`/health`) ve veritabanı/MQTT bağlantı durumu doğrulanmadan iş tamamlandı sayılmaz.
   - Sadece yerelde kod yazıp bırakmak kesinlikle yasaktır; her sunucu geliştirmesi derlenmeli, canlıya yüklenmeli ve çalıştığı uçtan uca teyit edilmelidir.

9. **Kod Değişikliklerini Doğrudan Uygula (Kullanıcı Onayı Sorma):**
   - Kodlarda veya dosyalarda değişiklik yapılması gerektiğinde kullanıcıya "kabul ediyor musun?", "değiştireyim mi?" gibi ara onay soruları sorulmayacak, değişiklikler tereddütsüz ve doğrudan koda işlenecektir.

10. **Git Yüklemeleri ve `.git/index` Bütünlüğü (Index Temizliği & Hata Engelleme):**
    - Her Git commit / push (GitHub yüklemesi) işleminden önce `.git/index` dosyasının bütünlüğü doğrulanmalı; kilit (`.git/index.lock`) veya bozulma ihtimaline karşı index temizliği yapılmalı (`Remove-Item -Force .git\index; git reset`).
    - `fatal: .git/index: index file smaller than expected` hatasının oluşması kesinlikle engellenmeli; bozuk index tespit edildiğinde otomatik onarım uygulanarak VS Code ve Git işlemleri kesintisiz yürütülmelidir.

11. **Dinamik QR & GM60 Güvenlik Aşamaları (Aşama 4, 5, 6, 7 Tamamlandı):**
    - Aşama 4 (30s süre & supersede token iptali), Aşama 5 (Haversine geofence mesafe hesabı), Aşama 6 (sahte konum / mock location ve bayat konum engeli) ve Aşama 7 (rate limiting & yönetici QR iptali) başarıyla tamamlanmış, tüm birim testleri (34/34 Node, 34/34 Flutter) geçirilmiş ve canlı VPS'e dağıtılmıştır.

12. **Üyelik Yönetim Sistemi Çalışma Kuralları (`uyelik_sistemi_asamalar.md`):**
    - Üyelik Yönetim Sistemi geliştirmesi (Aşama 0'dan Aşama 14'e kadar) %100 tamamlanmıştır.
    - Saha ve uygulama doğrulamaları için `uyelik_adim_adim_test.md` kılavuzu hazırdır.




