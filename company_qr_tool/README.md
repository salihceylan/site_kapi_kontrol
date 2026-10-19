# SmartKeyPass Cihaz Etiketleyici (Windows Desktop)

Bu arac Windows'ta masaustu uygulamasi olarak calisir.

Amac:
- Bagli ESP32 cihazlarini otomatik tarar.
- Cihazin unique ID bilgisini (MAC) otomatik okur.
- Ortasi SmartKeyPass logolu QR olusturur.
- QR cikti dosyasini `output/` klasorune kaydeder.
- `cihaz_kontrol` kodundan firmware surumu olusturur.
- Son surumu secili ESP32 cihaza yukler.
- Yukleme sirasinda yuzde ilerleme gosterir, bitince `TMM` mesaji verir.
- `Cihaz dene` penceresiyle seri porttan cihaz durumunu, firmware surumunu,
  OTA durumunu, MQTT kimligini ve role testlerini ayni uygulamada gosterir.

MQTT gerekmez.

## Cift Tik ile Calistirma

`launch_company_qr_tool.bat` dosyasina cift tiklayin.

Bu dosya:
- Otomatik `.venv` olusturur (ilk calistirmada),
- Gereken kutuphaneleri kurar,
- Masaustu uygulamasini acar.

PowerShell `ExecutionPolicy` hatasina takilmaz, cunku `.bat` kullanir.

## Arayüz

Tek pencere, solda menü (Ctrl+1…5 ile de geçilir, F5 bulunduğunuz sayfayı yeniler):

| Sayfa | Ne yapar |
| --- | --- |
| **Etiketle** | Bağlı kartın kimliğini okur, karekodu hazırlar, sunucuya kaydeder, yazdırır |
| **Kayıtlı cihazlar** | Sunucu + bu bilgisayardaki kayıtlar: arama, karekod, yazdır, sil, PDF raporu |
| **Cihaz testi** | Seri porttan canlı durum, röle / karekod okuyucu testleri, renkli seri kayıt |
| **Cihaz yazılımı** | Derle → Sürüm oluştur → Dağıt (USB, sunucu/OTA, çalışma arkadaşı ZIP'i) |
| **Ekran yazılımı** | 2.4" ekran modülünü bulur, derler, sürüm oluşturur, USB ile yükler, canlı test |

- Her akışın üstünde adım göstergesi vardır; sıradaki adımın düğmesi vurgulanır.
- Başarı mesajları sağ altta kendiliğinden kaybolan bildirim olarak gelir; hatalar
  çözüm adımlarıyla birlikte pencere olarak gelir.
- Alt çubukta son durum ve iş sürerken dönen gösterge bulunur.
- Windows'ta "Animasyon efektleri" kapalıysa uygulama da animasyonsuz çalışır.
- Arayüz parçaları (tema, simgeler, bileşenler) `ui_kit.py` içindedir; yalnızca
  tkinter ve Pillow kullanır, yeni paket gerekmez.

## Kullanma Adımları (Etiketle)

1. `launch_company_qr_tool.bat` dosyasına çift tıklayın.
2. ESP32 kartını USB ile bağlayın. Liste kendiliğinden yenilenir (elle: `Yeniden tara` / F5);
   tek kart bağlıysa kendiliğinden seçilir.
3. Satırı seçip `Kimliği oku` düğmesine basın (çift tık ya da Enter da olur).
   Okuma kartı yeniden başlatabilir. Kimlik okununca karekod kendiliğinden hazırlanır.
4. `Sunucuya kaydet` ile cihazı ve karekodu hem bu bilgisayara hem sunucuya yazın.
5. `Yazdır` ile doğrudan yazdırın ya da `PNG kaydet` ile `output/` klasörüne alın.

Seçili kartın karekodu hazır değilse kaydet/yazdır düğmeleri kapalıdır; böylece başka
bir kartın etiketi yanlışlıkla basılmaz.

## Cihaz Testi

- Port seçip `Bağlan`a basın; kartın durum bloğu geldikçe kimlik, yazılım sürümü, OTA,
  Wi-Fi, Bluetooth, MQTT ve röle bilgileri gruplu olarak dolar (değişen değer kısa süre vurgulanır).
- `h`, `l`, `r`, `k`, `p` seri komutları `Hızlı testler` düğmeleriyle gönderilir.
- Röle pininin HIGH/LOW/pulse davranışı seri kayıttan izlenir.
- Kart aynı ağda yerel yayın (UDP 8765) yapıyorsa `Yerel yayın (UDP)` alanı dolar.
  Windows Güvenlik Duvarı ilk seferde Python için izin isteyebilir (özel ağa izin verin).

## Yazılım Sürümleme ve Yükleme (Cihaz yazılımı)

1. `Kart türü` seçin, `Sürüm numarası` yazın (`1.2.3` biçimi).
2. `Derle`ye basın (sürüm numarası kaynak koda da yazılır).
3. `Sürüm oluştur`: `firmware.bin`, `bootloader.bin`, `partitions.bin` ve `manifest.json`
   `cihaz_kontrol/firmware_releases/...` altına kaydedilir.
4. `Dağıt` kartında hedef kartı seçin ve `USB ile karta yükle`ye basın.
   İlerleme `%` olarak görünür, bitince `TMM` bildirimi gelir.
5. `Sunucuya gönder (OTA)` son sürümü VPS'e taşır; sahadaki kartlar OTA ile indirir.
6. `Çalışma arkadaşı için ZIP` USB yükleme paketini oluşturur.

## Cihaz Kaydı, Sunucu Depolama ve PDF Raporlama

SmartKeyPass Cihaz Etiketleyici, üretilen/etiketlenen cihazları hem yerel bilgisayarda hem de sunucuda arşivler:

### 1. Sunucu Tarafı Depolama (VPS)
- **Karekod PNG Dosyaları:** `/var/www/site_kapi_kontrol/server/public/qrcodes/<device_uid>.png`
- **Genel Erişim URL'si:** `https://api.gudeteknoloji.com.tr/qrcodes/<device_uid>.png`
- **Etiketli Cihaz Veritabanı / İndeksi:** `/var/www/site_kapi_kontrol/server/data/labeled_devices.json`
- **PostgreSQL Envanteri:** `devices` tablosu (`device_uid`, `created_at`)
- **API Uçları:**
  - `POST /api/company/labeled-devices` (Cihaz ve karekod görseli kaydetme / güncelleme - mükerrer kaydı engeller)
  - `GET /api/company/labeled-devices` (Tüm kayıtlı cihaz listesi)
  - `GET /api/company/devices/:deviceUid/runtime` (Salt okunur; "Cihaz testi" sayfasındaki "Genel IP (WAN)" alanı için yalnızca o kartın `{device_uid, public_ip, last_seen_at}` bilgisi. Genel IP, kartın OTA güncelleme kontrolünü yaptığı adrestir: açılıştan ~2 dk sonra ve günde bir yenilenir. Anahtarsız 401, geçersiz kimlik 400, kayıtsız kart 404)
  - `GET /qrcodes/:file` (Karekod görselini doğrudan tarayıcı/uygulamaya sunma)

### 2. Yerel Bilgisayar Depolama
- **Karekod PNG Dosyaları:** `company_qr_tool/output/qrcodes/<device_uid>.png`
- **Cihaz İndeks Dosyası:** `company_qr_tool/output/labeled_devices.json`
- **PDF Raporları:** İsteğe bağlı olarak seçilen dosya yolu (ör. `SmartKeyPass_Cihaz_Karekod_Raporu_YYYYMMDD.pdf`)

### 3. İlgili Düğmeler
- **`Sunucuya kaydet`** (Etiketle): Seçili cihazın UID'sini, çipini ve karekod görselini sunucuya (`/var/www/site_kapi_kontrol/server/public/qrcodes/`) ve veritabanına aktarır.
- **`Karekodlu PDF raporu`** (Kayıtlı cihazlar): Sunucu ve yereldeki tüm cihazları toplayarak 300 DPI A4 boyutunda yüksek çözünürlüklü, taranabilir karekodlu çok sayfalı PDF envanter kataloğu oluşturur.
- **Kayıtlı cihazlar** sayfası: Şimdiye kadar etiketlenmiş tüm cihazları listeler; arama, önizleme, yazdırma, kimlik kopyalama ve silme (sağ tık menüsü ve Delete tuşu dahil) sunar.

## Logo

Karekodun ortasindaki ve rapor basligindaki logo `company_qr_tool/assets/smartkeypass_logo.png` dosyasidir
(SmartKeyPass, Akilli Gecis Sistemleri). Eski `ahbu_logo.png` ev otomasyonunun logosuydu, kaldirildi.

## Gereksinimler

- Windows
- Etiketleyici uygulamayı çalıştıran bilgisayarda Python 3.10+
- USB driver (CH340 / CP210x, karta göre)

Çalışma arkadaşına verilen ZIP paketinde Python ve esptool paket içine eklenir; o bilgisayarda Python kurulu olmak zorunda değildir.

## Guvenlik ve Ortam Ayarlari

Sirlar kaynak koda yazilmaz; `.env` dosyasindan (git'e girmez) veya Windows
kullanici ortam degiskenlerinden okunur. Ornek: `env.example`.

### Sunucu yetkisi (COMPANY_API_KEY)

- Sunucudaki sirket uclari (`/api/company/*`) `X-Company-Key` basligini ister.
  Deger, sunucudaki `server/.env` icindeki `COMPANY_API_KEY` ile ayni olmalidir.
- Bu bilgisayarda `company_qr_tool/.env` dosyasina `COMPANY_API_KEY=...` yazin
  (veya `setx COMPANY_API_KEY "..."`), sonra uygulamayi yeniden acin.
- Anahtar yoksa uygulama sunucuya istek gondermez; "COMPANY_API_KEY tanimli degil"
  uyarisi gosterir (yerel kayit yine yapilir).
- Anahtar yalnizca HTTPS (veya localhost) uzerinden gonderilir. Duz HTTP yedek uc
  (`http://<IP>:3000`) artik varsayilan olarak KAPALIDIR (`AHBU_API_FALLBACK_URL`).

### SFTP ile firmware gonderme: sunucu kimligi dogrulamasi

Uygulama bilinmeyen sunuculara otomatik guvenmez (`RejectPolicy`); sunucunun
anahtari `known_hosts` dosyasinda (varsayilan `~/.ssh/known_hosts`, veya
`SSH_KNOWN_HOSTS`) kayitli olmalidir.

Ilk kurulum (bir kez):

1. Sunucuda parmak izini ogrenin: `ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub`
2. Bu bilgisayarda: `ssh-keyscan -p 22667 -H 178.210.161.55 >> %USERPROFILE%\.ssh\known_hosts`
3. Eklenen anahtarin parmak izini 1. adimdaki ile karsilastirin
   (`ssh-keygen -lf %USERPROFILE%\.ssh\known_hosts`); eslesmiyorsa satiri silin.

Sunucu yeniden kurulursa anahtar degisir; uygulama "UYUSMUYOR" uyarisi verir.
Once sunucudan parmak izini dogrulayin, sonra eski kaydi `ssh-keygen -R "[178.210.161.55]:22667"`
ile silip adimlari tekrarlayin.

Kimlik dogrulama: `SSH_KEY_FILE` (ve gerekirse `SSH_KEY_PASSPHRASE`) tanimliysa anahtar ile
baglanilir (ONERILEN). Tanimli degilse `AHBU_VPS_PASSWORD` veya uygulamanin sordugu parola kullanilir.

### Diger ayarlar (hepsi istege bagli; varsayilanlar korunur)

`AHBU_API_URL`, `AHBU_VPS_HOST`, `AHBU_VPS_PORT`, `AHBU_VPS_USER`, `AHBU_VPS_FIRMWARE_DIR`,
`AHBU_VPS_DATA_DIR`, `AHBU_VPS_QRCODES_DIR`. (Ortam degiskeni adlari urunun eski adi AHBU ile kalir; mevcut .env dosyalari bozulmasin diye degistirilmedi.)
