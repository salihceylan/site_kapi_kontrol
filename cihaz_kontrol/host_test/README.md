# Firmware ana makine (host) testleri

Bu klasördeki testler **donanım olmadan**, Windows'ta MSVC ile derlenir. GERÇEK firmware başlıklarını (`../include/*.h`) sahte donanım katmanı (`stub/`: Arduino, WiFi, WiFiUdp, PubSubClient, Preferences, Update, mbedtls, esp_ota_ops …), sahte saat ve sahte RNG ile çalıştırır. Amaç: firmware mantığındaki (yerel kontrol protokolü v2, yönetici PIN'i, GM60 QR korumaları, MQTT/OTA durum makineleri, `millis()` taşması) gerilemeleri cihaza yazmadan yakalamak.

Cihazdaki gerçek davranış (röle, Wi-Fi, OTA rollback, ekran, gerçek ağ) bu testlerle doğrulanmış SAYILMAZ; onun için `SAHA_KONTROL_LISTESI.md` bölüm 42–52 sahada uygulanır.

| Test | Kapsadığı başlık(lar) | Doğrulama |
|------|-----------------------|-----------|
| `t_core.cpp` | `yerel_kontrol_cekirdek.h`: HMAC bilinen-cevap vektörleri, Node `crypto` ile çapraz doğrulama (600 rastgele vektör), challenge / yinelenen paket durum makinesi, işaretsiz zaman farkı ve sarma | 165 |
| `t_udp.cpp` | `yerel_kapi_kontrol.h`: UDP/HTTP uçtan uca (beacon, discover, open/pulse, hata yolları) | 143 |
| `t_pin.cpp` | `admin_pin.h`: zayıf PIN listesi, kilitleme zamanı | 78 |
| `t_gm60.cpp` | `gm60_scanner.h`: QR okuyucu korumaları | 44 |
| `t_mqtt.cpp` (WROOM) | `mqtt_baglanti.h` + `ota_guncelleme.h` + `ota_is_kimligi.h` | 164 |
| `t_mqtt.cpp` (C3) | aynı başlıklar, ESP32-C3 derleme koşullarıyla | 125 |
| `t_fuzz.cpp` (isteğe bağlı) | rastgele olay dizileri, AddressSanitizer | — |

Toplam: 719 doğrulama (2026-10-02 itibarıyla hepsi geçiyor). Protokol sözleşmesi: `../../docs/YEREL_KONTROL_V2.md`.

## Gereksinimler

- Windows + Visual Studio (C++ derleme araçları, `cl.exe`). `vcvars64.bat` yolu farklıysa `VCVARS` ortam değişkeniyle verin (varsayılan: `C:\Program Files\Microsoft Visual Studio\18\Community\VC\Auxiliary\Build\vcvars64.bat`).
- Python 3 (çalıştırıcı) ve Node.js (t_core için rastgele HMAC vektörleri: `gen_vectors.mjs` → `vectors.txt`, yoksa otomatik üretilir).
- ArduinoJson: `cihaz_kontrol` bir kez PlatformIO ile derlenmiş olmalı (`pio run -e lolin_c3_mini`; başlıklar `../.pio/libdeps/lolin_c3_mini/ArduinoJson/src` altında aranır).

## Çalıştırma

```bash
cd cihaz_kontrol/host_test
python run_all.py                 # hepsi (t_core, t_udp, t_pin, t_gm60, t_mqtt WROOM + C3)
python run_all.py --new-vectors   # t_core için HMAC vektörlerini yeniden üret
python run_all.py --fuzz          # ek: AddressSanitizer'lı rastgele olay testi (uzun sürer)
```

Her test `SONUC: N dogrulama gecti, M basarisiz` satırı yazar; çıkış kodu tümü geçtiyse 0'dır. Derleme çıktıları (`*.exe`, `*.obj`, `*.pdb`, `vectors.txt`) `.gitignore`'dadır.

## Notlar

- Sahte katman (`stub/`) basitleştirilmiştir: gerçek zamanlama, bellek sınırı (RAM/Flash) ve ağ davranışı ölçülmez. Bellek/boyut için PlatformIO derlemesine (`pio run`) bakılır.
- `ref_crypto.h` / `mbedtls_stub_impl.h`: `mbedtls_md_hmac` yerine referans HMAC-SHA256 (Node `crypto` ile aynı sonuçları vermelidir; çapraz doğrulama t_core içindedir).
- Bu testler CI'da koşmaz (MSVC + PlatformIO bağımlılıkları gerekir); firmware başlıklarını değiştirdikten sonra elle çalıştırın.
