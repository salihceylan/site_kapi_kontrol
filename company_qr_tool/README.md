# AHBU Cihaz Etiketleyici (Windows Desktop)

Bu arac Windows'ta masaustu uygulamasi olarak calisir.

Amac:
- Bagli ESP32 cihazlarini otomatik tarar.
- Cihazin unique ID bilgisini (MAC) otomatik okur.
- Ortasi AHBU logolu QR olusturur.
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

## Kullanma Adimlari

1. ESP32 cihazi USB ile bilgisayara baglayin.
2. `launch_company_qr_tool.bat` dosyasina cift tiklayin.
3. Uygulamada `Bagli cihazlari tara` butonuna basin.
4. Listeden cihazi secin.
5. `Secili cihaz UID oku` butonuna basin.
6. `Secili cihaz icin QR olustur` butonuna basin.
7. `QR kaydet` ile PNG ciktiyi alin veya `QR yazdir` ile direkt yazdirin.

## Cihaz Deneme

Ana ekrandaki `Cihaz dene` butonu seri port test penceresini acar.

Bu pencerede:
- Cihaz UID, firmware surumu, OTA durumu, Wi-Fi, Bluetooth, MQTT ve role bilgileri
  canli durum bloklarindan okunur.
- `h`, `l`, `r`, `p` seri komutlari butonlarla gonderilir.
- Role pininin HIGH/LOW/pulse davranisi seri logdan takip edilir.

## Firmware Surumleme ve Yukleme

1. `Env` secin (su an yalniz `lolin_c3_mini` aktiftir).
2. `Surum` alanina deger yazin (`1.2.3` formati).
3. `Firmware derle` butonuna basin.
4. Derleme basarili olursa `Surum olustur` butonuna basin.
   Bu adim:
   - `firmware.bin`, `bootloader.bin`, `partitions.bin` dosyalarini
     `cihaz_kontrol/firmware_releases/...` altina kaydeder.
5. Cihazi listeden secin.
6. `Surumu USB ile cihaza yukle` butonuna basin.
   Yukleme ilerlemesi `%` olarak gosterilir, tamamlaninca `TMM` mesaji gelir.
7. `Guncelleme Dosyasini Sunucuya gonder` butonu son surumu VPS'e tasir.
8. `Calisma arkadasina guncelleme zip dosyasi olustur` butonu USB yukleme
   paketini olusturur.

## Cihaz Kaydı, Sunucu Depolama ve PDF Raporlama

AHBU Cihaz Etiketleyici, üretilen/etiketlenen cihazları hem yerel bilgisayarda hem de sunucuda arşivler:

### 1. Sunucu Tarafı Depolama (VPS)
- **Karekod PNG Dosyaları:** `/var/www/site_kapi_kontrol/server/public/qrcodes/<device_uid>.png`
- **Genel Erişim URL'si:** `https://api.gudeteknoloji.com.tr/qrcodes/<device_uid>.png`
- **Etiketli Cihaz Veritabanı / İndeksi:** `/var/www/site_kapi_kontrol/server/data/labeled_devices.json`
- **PostgreSQL Envanteri:** `devices` tablosu (`device_uid`, `created_at`)
- **API Uçları:**
  - `POST /api/company/labeled-devices` (Cihaz ve karekod görseli kaydetme / güncelleme - mükerrer kaydı engeller)
  - `GET /api/company/labeled-devices` (Tüm kayıtlı cihaz listesi)
  - `GET /qrcodes/:file` (Karekod görselini doğrudan tarayıcı/uygulamaya sunma)

### 2. Yerel Bilgisayar Depolama
- **Karekod PNG Dosyaları:** `company_qr_tool/output/qrcodes/<device_uid>.png`
- **Cihaz İndeks Dosyası:** `company_qr_tool/output/labeled_devices.json`
- **PDF Raporları:** İsteğe bağlı olarak seçilen dosya yolu (ör. `AHBU_Cihaz_Karekod_Raporu_YYYYMMDD.pdf`)

### 3. Yeni Butonlar ve İşlevleri
- **`[ Cihazı Sunucuya Kaydet ]`**: Seçili cihazın UID'sini, çipini ve karekod görselini sunucuya (`/var/www/site_kapi_kontrol/server/public/qrcodes/`) ve veritabanına aktarır.
- **`[ Karekodlu PDF Raporu İndir ]`**: Sunucu ve yereldeki tüm cihazları toplayarak 300 DPI A4 boyutunda yüksek çözünürlüklü, taranabilir karekodlu çok sayfalı PDF envanter kataloğu oluşturur.
- **`[ Kayıtlı Cihazlar & Karekodlar ]`**: Şimdiye kadar etiketlenmiş tüm cihazları listeleyen, tekil yazdırma ve önizleme sunan yönetim penceresini açar.

## Logo

Logo otomatik olarak şu yoldan çekilir:

`..\..\ahbu\assets\images\app_logo.png`

ve `company_qr_tool/assets/ahbu_logo.png` dosyasına kopyalanır.

## Gereksinimler

- Windows
- Etiketleyici uygulamayı çalıştıran bilgisayarda Python 3.10+
- USB driver (CH340 / CP210x, karta göre)

Çalışma arkadaşına verilen ZIP paketinde Python ve esptool paket içine eklenir; o bilgisayarda Python kurulu olmak zorunda değildir.
