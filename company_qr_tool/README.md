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

1. `Env` secin (varsayilan: `esp32-s3-devkitc-1`).
2. `Surum` alanina deger yazin (`1.2.3` formati).
3. `Surum olustur` butonuna basin.
   Bu adim:
   - `cihaz_kontrol` kodunu derler,
   - `firmware.bin`, `bootloader.bin`, `partitions.bin` dosyalarini
     `cihaz_kontrol/firmware_releases/...` altina kaydeder.
4. Cihazi listeden secin.
5. `Son surumu yukle` butonuna basin.
   Yukleme ilerlemesi `%` olarak gosterilir, tamamlaninca `TMM` mesaji gelir.

## Logo

Logo otomatik olarak su yoldan cekilir:

`..\..\ahbu\assets\images\app_logo.png`

ve `company_qr_tool/assets/ahbu_logo.png` dosyasina kopyalanir.

## Gereksinimler

- Windows
- Python 3.10+
- USB driver (CH340 / CP210x, karta gore)
