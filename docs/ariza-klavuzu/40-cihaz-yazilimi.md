# Cihaz yazılımı — ESP32 firmware, ekran, OTA, GM60, yerel kontrol

[← Ana sayfa](../ARIZA_KLAVUZU.md) · [İndeks](../ARIZA_KLAVUZU_INDEKS.md) · [Ekler](../ARIZA_KLAVUZU_EKLER.md) · [Hata mesajları](../ARIZA_KLAVUZU_HATA_MESAJLARI.md)

> ⚠ **Doğrulanmadı:** bu bölümün açıklamaları (olası nedenler, adımlar) ajanlarca kodu okuyarak yazıldı ama bağımsız çürütücü incelemeden GEÇMEDİ. `dosya:satır` bağlantıları ise koddan çözülür ve her çalıştırmada denetlenir (güvenilir). Açıklamayı uygulamadan önce bağlantıdaki koda bakarak teyit edin.

Bu bölüm cihaz_kontrol (ESP32-C3 saha cihazı + ESP32-WROOM röle kartı), ekran_yazilimi (ESP32-C3 2,4" ekran) ve cihaz_dene (seri deneme aracı) içindir. İlk bakılacak yer seri monitördür (115200 baud): cihazda "?" yazıp durum dökümünü alın (Wi-Fi, MQTT, OTA, GM60, atölye modu). KURAL (AGENTS.md 3 ve 4): ESP32-C3 sahada çalışır, pin/BLE/Wi-Fi/MQTT davranışı bozulmamalı; C3 ve WROOM ayrı donanım hedefidir (OTA manifesti, derleme ortamı, sürüm ayrı).

## Dosya haritası

| Dosya | Rol |
| --- | --- |
| [cihaz_kontrol/src/main.cpp](../../cihaz_kontrol/src/main.cpp) | setup/loop, seri komutlar (? r k h l p ADMINPIN), atölye modu, durum dökümü, ekran QR rotasyonu (WROOM) |
| [cihaz_kontrol/include/wifi_baglanti.h](../../cihaz_kontrol/include/wifi_baglanti.h) | Wi-Fi bağlantısı, BLE kurulum (provisioning), reset butonu, LED, NVS kayıtları |
| [cihaz_kontrol/include/mqtt_baglanti.h](../../cihaz_kontrol/include/mqtt_baglanti.h) | MQTT bağlantısı/geri çekilme, komut işleme (pulse, ota_check, local_control_config, admin_pin_config, logs_ack), yayınlar |
| [cihaz_kontrol/include/tls_kok_sertifika.h](../../cihaz_kontrol/include/tls_kok_sertifika.h) | Gömülü kök CA (MQTT ve OTA TLS doğrulaması) |
| [cihaz_kontrol/include/ota_guncelleme.h](../../cihaz_kontrol/include/ota_guncelleme.h) | OTA: manifest, indirme, SHA-256, rollback doğrulaması, deneme sınırı, hedef (c3/wroom) ve sürüm sabitleri |
| [cihaz_kontrol/include/ota_is_kimligi.h](../../cihaz_kontrol/include/ota_is_kimligi.h) | OTA iş kimliği (ota_job_id) yansıtma |
| [cihaz_kontrol/include/ota_imza.h](../../cihaz_kontrol/include/ota_imza.h) | OTA paket imzası (KAPI-OTA-IMZA-V1): imzalanan ileti, anahtar durumu (HAZIR / YER TUTUCU / GEÇERSİZ), çıplak imza çözümleme, otaImzaDogrula |
| [cihaz_kontrol/include/ota_public_key.h](../../cihaz_kontrol/include/ota_public_key.h) | Gömülü OTA genel anahtarı (32 bayt; teslimde YER TUTUCU: gerçek anahtar ota_anahtar.mjs yaz ile yazılır) |
| [cihaz_kontrol/include/gm60_scanner.h](../../cihaz_kontrol/include/gm60_scanner.h) | GM60 QR okuyucu: UART, self-test, QR korumaları, qr_verify gönderimi |
| [cihaz_kontrol/include/qr_dogrulama.h](../../cihaz_kontrol/include/qr_dogrulama.h) | ÖLÜ KOD: hiçbir yerden çağrılmaz; QR doğrulaması yalnız sunucudadır |
| [cihaz_kontrol/include/role_kontrol.h](../../cihaz_kontrol/include/role_kontrol.h) | Röle pini, pulse süresi, debounce, manuel tutma, esp_timer ile bırakma |
| [cihaz_kontrol/include/yerel_kapi_kontrol.h](../../cihaz_kontrol/include/yerel_kapi_kontrol.h) | Yerel ağ kontrolü: UDP 8765 (discover/open/pulse, beacon), HTTP GET /ahbu/status |
| [cihaz_kontrol/include/yerel_kontrol_cekirdek.h](../../cihaz_kontrol/include/yerel_kontrol_cekirdek.h) | Yerel kontrol v2 çekirdeği: challenge, HMAC-SHA256 imza, yinelenen paket |
| [cihaz_kontrol/include/offline_log.h](../../cihaz_kontrol/include/offline_log.h) | Çevrimdışı kapı geçiş kayıtları (LittleFS NDJSON) ve sunucuya batch/ack senkronu |
| [cihaz_kontrol/include/admin_pin.h](../../cihaz_kontrol/include/admin_pin.h) | Yönetici ekran PIN'i (NVS), zayıf PIN reddi, hatalı deneme kilidi |
| [cihaz_kontrol/include/device_konfig.h](../../cihaz_kontrol/include/device_konfig.h) | Donanıma göre pin sabitleri (GM60, LED, reset butonu), cihaz UID, NTP saat denetimi |
| [cihaz_kontrol/src/display_uart.cpp](../../cihaz_kontrol/src/display_uart.cpp) | WROOM tarafı ekran UART protokolü (ADMIN_*, REQ_*, durum satırları) |
| [cihaz_kontrol/include/display_uart.h](../../cihaz_kontrol/include/display_uart.h) | Ekran UART pinleri/baud (WROOM GPIO32/33) ve sistem kancaları |
| [cihaz_kontrol/include/display_protocol.h](../../cihaz_kontrol/include/display_protocol.h) | Ekran protokolü komut sabitleri (ekran_yazilimi ile BİREBİR aynı olmalı) |
| [cihaz_kontrol/platformio.ini](../../cihaz_kontrol/platformio.ini) | cihaz_kontrol derleme ortamları: lolin_c3_mini (C3) ve esp32_relay_wroom (WROOM) |
| [platformio.ini](../../platformio.ini) | Kök platformio.ini (VS Code girişi; cihaz_kontrol/ kaynaklarını derler, bayrakları farklıdır) |
| [cihaz_kontrol/partitions_ota_4mb.csv](../../cihaz_kontrol/partitions_ota_4mb.csv) | Bölüm tablosu (4 MB): nvs, otadata, app0/app1 (OTA), spiffs (LittleFS), coredump |
| [cihaz_kontrol/flash_wroom.bat](../../cihaz_kontrol/flash_wroom.bat) | WROOM USB yükleme + otadata sıfırlama betiği |
| [cihaz_kontrol/host_test/README.md](../../cihaz_kontrol/host_test/README.md) | Firmware ana makine (host) testleri: ne kapsar, nasıl çalıştırılır |
| [cihaz_kontrol/host_test/run_all.py](../../cihaz_kontrol/host_test/run_all.py) | Host test çalıştırıcısı (MSVC, VCVARS, ArduinoJson yolu) |
| [ekran_yazilimi/src/ScreenManager.cpp](../../ekran_yazilimi/src/ScreenManager.cpp) | Ekran: ekran durumları, PIN ekranı, QR çizimi, dokunma, ana MCU komutları |
| [ekran_yazilimi/include/ScreenManager.h](../../ekran_yazilimi/include/ScreenManager.h) | Ekran: süre sabitleri (oturum 20 sn, PIN yanıtı 3 sn, ana MCU sessizliği 45 sn) |
| [ekran_yazilimi/src/main.cpp](../../ekran_yazilimi/src/main.cpp) | Ekran: UART/USB seri girişi, dokunma ve düğme döngüsü |
| [ekran_yazilimi/include/config.h](../../ekran_yazilimi/include/config.h) | Ekran: UART, dokunmatik, LED ve düğme pinleri; ekran firmware sürümü |
| [ekran_yazilimi/include/cst816d_touch.h](../../ekran_yazilimi/include/cst816d_touch.h) | Ekran: CST816D dokunmatik I2C sürücüsü |
| [ekran_yazilimi/platformio.ini](../../ekran_yazilimi/platformio.ini) | Ekran derleme ortamı ve TFT_eSPI pin/sürücü bayrakları |
| [cihaz_dene/app.py](../../cihaz_dene/app.py) | Cihaz Dene (SmartKeyPass Cihaz Deneme) seri aracı: durum tablosu, röle butonları |
| [OTA_KURULUM.txt](../../OTA_KURULUM.txt) | OTA akışı, manifest alanları, sunucu dizin yapısı (c3 / wroom ayrı) |
| [docs/YEREL_KONTROL_V2.md](../../docs/YEREL_KONTROL_V2.md) | Yerel kontrol protokol sözleşmesi (LOCALCTRL_V2) |

## Bu bölümdeki girişler (45)

- [cihaz-wifi-baglanmiyor](#cihaz-wifi-baglanmiyor) — Cihaz Wi-Fi'ye bağlanmıyor: Wi-Fi LED'i yavaş (yaklaşık 0,7 sn) yanıp sönüyor, uygulamada cihaz çevrimdışı
- [cihaz-led-hizli-yanip-sonuyor](#cihaz-led-hizli-yanip-sonuyor) — Cihazın Wi-Fi LED'i hızlı (yaklaşık 0,15 sn) yanıp sönüyor: Wi-Fi bilgisi girilmemiş, kurulum bekliyor
- [cihaz-ble-gorunmuyor](#cihaz-ble-gorunmuyor) — Telefon BLE taramasında "SmartKeyPass..." (eski kartlarda "AHBU...") adlı cihaz görünmüyor, Wi-Fi kurulumu başlatılamıyor
- [cihaz-ble-kurulum-basarisiz](#cihaz-ble-kurulum-basarisiz) — BLE ile Wi-Fi/MQTT kurulumu başarısız: "SSID bilgisi eksik veya gecersiz", "MQTT cihaz kimligi eksik" ya da "MQTT sunucu adresi izinli degil"
- [cihaz-wifi-sifirlama-butonu](#cihaz-wifi-sifirlama-butonu) — Wi-Fi bilgisini silmek / cihazı yeniden kuruluma almak için reset butonu çalışmıyor ("sifirlama iptal")
- [cihaz-saat-ntp-yok](#cihaz-saat-ntp-yok) — Wi-Fi bağlı görünüyor ama cihaz MQTT'ye hiç bağlanmıyor ve OTA başlamıyor (sistem saati NTP ile gelmemiş)
- [cihaz-mqtt-rc-hatasi](#cihaz-mqtt-rc-hatasi) — Cihaz çevrimdışı: seri günlükte "MQTT baglaniyor (id=...)...Hata rc=N tekrar denenecek"
- [cihaz-mqtt-tls-hatasi](#cihaz-mqtt-tls-hatasi) — MQTT satırında "tls=..." hatası: sertifika doğrulanamıyor / TLS el sıkışma başarısız, cihaz çevrimdışı
- [cihaz-mqtt-kimlik-yok](#cihaz-mqtt-kimlik-yok) — Wi-Fi bağlı ama MQTT hiç denenmiyor: günlükte "MQTT kimligi yok; BLE provisioning ile cihaz kimligi yazilmali."
- [cihaz-mqtt-yayin-basarisiz](#cihaz-mqtt-yayin-basarisiz) — Cihaz bağlı görünüyor ama durum/olay/log yayınları sunucuya ulaşmıyor; günlükte "MQTT publish basarisiz"
- [cihaz-mqtt-tcp-onkontrol](#cihaz-mqtt-tcp-onkontrol) — İnternet kesilince cihaz yavaşlıyor/yerel işler gecikiyor; günlükte "MQTT: broker TCP on-kontrolu basarisiz (ag/internet yok?)"
- [cihaz-mqtt-6-saat-yeniden-baslama](#cihaz-mqtt-6-saat-yeniden-baslama) — Cihaz kendiliğinden yeniden başlıyor; sunucuda "self_recovery_restart" (mqtt_6h) olayı görülüyor
- [cihaz-ota-guncelleme-baslamiyor](#cihaz-ota-guncelleme-baslamiyor) — Panelden "güncelle" denildi ya da yeni sürüm yayınlandı ama cihaz OTA kontrolünü hiç başlatmıyor ("OTA kontrolu basladi." günlükte yok)
- [cihaz-ota-manifest-hatasi](#cihaz-ota-manifest-hatasi) — OTA durumu "manifest http hata: N", "manifest json okunamadi" ya da "manifest baglantisi baslatilamadi" gösteriyor; olay ota_check_failed
- [cihaz-ota-hedef-uyusmazligi](#cihaz-ota-hedef-uyusmazligi) — OTA durumu "hedef uyusmazligi", "USB ile tam yukleme gerekli" ya da "indirme adresi reddedildi"; cihaz güncellenmiyor
- [cihaz-ota-indirme-basarisiz](#cihaz-ota-indirme-basarisiz) — OTA durumu "guncelleme basarisiz: ..." (indirme eksik/hatali, sha256 uyusmuyor, Update.begin/Update.end basarisiz) ve olay ota_failed
- [cihaz-ota-deneme-siniri-asildi](#cihaz-ota-deneme-siniri-asildi) — OTA durumu "deneme siniri asildi (3): <sürüm>"; cihaz aynı sürümü bir daha denemiyor
- [cihaz-ota-sonrasi-geri-aldi](#cihaz-ota-sonrasi-geri-aldi) — OTA "tamam" dedi ama cihaz eski sürüme döndü: seri "?" -> OTA durum "geri alindi: <sürüm> yuklenemedi"
- [cihaz-ota-is-kimligi-yansimiyor](#cihaz-ota-is-kimligi-yansimiyor) — Panelden toplu OTA işi başlatıldı ama sunucudaki iş kaydında cihaz OTA olayları işe bağlanmıyor (ota_job_id eksik)
- [cihaz-offline-log-senkronize-olmuyor](#cihaz-offline-log-senkronize-olmuyor) — Cihaz internetsizken açılan kapı geçişleri sunucuda/uygulama günlüğünde görünmüyor; seri günlükte "batch yayinlanamadi" ya da hiç "ack" yok
- [cihaz-offline-log-dosya-sorunu](#cihaz-offline-log-dosya-sorunu) — Cihazda çevrimdışı kayıtlar kayboluyor ya da seri günlükte "Offline Log: dosya doldu" / "Dosya yazma hatasi" / "LittleFS mount basarisiz" görülüyor
- [cihaz-watchdog-yeniden-basliyor](#cihaz-watchdog-yeniden-basliyor) — Cihaz kendiliğinden yeniden başlıyor (seri günlükte yeniden başlatma, "Task watchdog"); özellikle OTA ya da MQTT/TLS bağlanırken
- [cihaz-gm60-baglanti-yok](#cihaz-gm60-baglanti-yok) — QR okuyucu (kamera) ışık yakmıyor/bip yapmıyor; seri "?" -> "Kamera / QR Okuyucu: Bagli Degil", açılışta "UYARI (Kamera yanit vermedi"
- [cihaz-qr-okundu-kapi-acilmiyor](#cihaz-qr-okundu-kapi-acilmiyor) — QR okutuluyor ("[GM60] QR okundu") ama kapı açılmıyor ya da ekranda "reddedildi": "Sunucu yaniti bekleniyor", "Debounce", "Ayni token ... atlaniyor"
- [cihaz-qr-offline-acilmiyor](#cihaz-qr-offline-acilmiyor) — İnternet/MQTT yokken QR okutulunca kapı açılmıyor; seri "[GM60 UYARI] MQTT baglantisi yok! Dinamik QR offline modda acilamaz."
- [cihaz-role-acmiyor](#cihaz-role-acmiyor) — Komut/QR kabul edildi ama röle çekmiyor ya da kapı kilidi açılmıyor; seri "Role debounce: Role zaten aktif ..." ya da pin okuması beklenenden farklı
- [cihaz-role-acilista-tiklamasi](#cihaz-role-acilista-tiklamasi) — Cihaz açılırken/yeniden başlarken röle tıklıyor ya da kapı kısa süre açılıyor mu şüphesi
- [cihaz-mqtt-pulse-reddedildi](#cihaz-mqtt-pulse-reddedildi) — Panel/uygulamadan kapı açma komutu gönderildi ama cihaz açmadı; sunucuda "pulse_rejected" olayı (stale ya da role_busy)
- [cihaz-yerel-udp-cevap-yok](#cihaz-yerel-udp-cevap-yok) — Uygulama yerel ağdan (UDP) cihazı bulamıyor ya da kapıyı açamıyor; cihaz discover/open paketine hiç cevap vermiyor
- [cihaz-yerel-udp-imza-reddi](#cihaz-yerel-udp-imza-reddi) — Yerel UDP kapı açma "unauthorized" / "challenge" / "role_mesgul" dönüyor; seri "UDP Kapi Acma REDDEDILDI: imza gecersiz" ya da "yerel kontrol kapali"
- [cihaz-yerel-ozdeneme-basarisiz](#cihaz-yerel-ozdeneme-basarisiz) — Cihaz yerel kapı açmayı tamamen kapattı: seri "UYARI: Yerel kontrol HMAC oz-testi BASARISIZ"; sunucuda local_control_selftest_failed olayı
- [cihaz-yerel-beacon-gelmiyor](#cihaz-yerel-beacon-gelmiyor) — Uygulama/Cihaz Dene aracı cihazın yerel ağ duyurusunu (beacon) almıyor, cihaz listede çıkmıyor
- [cihaz-yerel-http-status-hata](#cihaz-yerel-http-status-hata) — http://<cihaz-ip>:8765/ahbu/status 404 (route_bulunamadi / cihaz_uid_eslesmedi), 400 ya da 431 dönüyor; eski POST /ahbu/open çalışmıyor
- [cihaz-admin-pin-tanimsiz-reddedildi](#cihaz-admin-pin-tanimsiz-reddedildi) — Ekranda yönetici menüsü "PIN tanımlı değil" (NOPIN) gösteriyor ya da PIN atanamıyor: "Yonetici PIN'i REDDEDILDI: zayif PIN" / "gecersiz"
- [cihaz-admin-pin-kilitli](#cihaz-admin-pin-kilitli) — Ekranda yönetici PIN girişi "kilitli" (LOCKED, kalan saniye) gösteriyor; doğru PIN bile kabul edilmiyor ya da yönetici kapı açma "BUSY" diyor
- [cihaz-ekran-bos-baglanti](#cihaz-ekran-bos-baglanti) — Ekran (WROOM + C3 ekran kartı) boş/bayat: Wi-Fi, bulut ya da QR görünmüyor; ana karttan UART satırı gelmiyor
- [cihaz-ekran-qr-yenilenmiyor](#cihaz-ekran-qr-yenilenmiyor) — Ekrandaki dinamik QR yenilenmiyor ya da uygulamayla okutunca "geçersiz/süresi dolmuş" diyor (WROOM ekranlı cihaz)
- [cihaz-seri-atolye-komutlari](#cihaz-seri-atolye-komutlari) — Seri monitörden "h" / "l" / "p" komutları cevap vermiyor: "Atolye modu kapali (Wi-Fi sifirlayin veya reset butonu 3 sn)"; "?" çıktısı kendiliğinden gelmiyor
- [cihaz-derleme-ortami-hatasi](#cihaz-derleme-ortami-hatasi) — Firmware derlenmiyor ya da yanlış donanım için derleniyor (pio run hatası, "BOARD_ESP32_..." tanımsız, röle/GM60 pini beklenenden farklı)
- [cihaz-wroom-usb-yukleme](#cihaz-wroom-usb-yukleme) — WROOM kartına USB ile firmware yüklenemiyor ("USB yukleme basarisiz") ya da yükleme sonrası kart eski sürümle açılıyor
- [cihaz-ota-partition-yok](#cihaz-ota-partition-yok) — OTA durumu "OTA partition yok; cihaza USB ile OTA partition tablosu yuklenmeli"
- [cihaz-yerel-anahtar-reddedildi](#cihaz-yerel-anahtar-reddedildi) — Sunucudan yerel kontrol anahtarı gönderildi ama cihaz "local_control_config_rejected" (invalid_token) olayı yayınlıyor; yerel kontrol "kapali (anahtar yok)" kalıyor
- [cihaz-host-test-calismiyor](#cihaz-host-test-calismiyor) — Firmware ana makine testleri (host_test) derlenmiyor ya da başarısız; "vcvars64.bat bulunamadi" ya da ArduinoJson yolu hatası
- [cihaz-kok-sertifika-suresi](#cihaz-kok-sertifika-suresi) — Tüm cihazlar aynı gün MQTT ve OTA için TLS hatası vermeye başladı (kök sertifika değişti ya da süresi doldu)
- [cihaz-ota-imza-reddi](#cihaz-ota-imza-reddi) — Cihaz OTA güncellemesini kurmuyor: OTA durumu ya da ota_failed ayrıntısı "imza: ..." ("imza: dosya yok", "imza: dogrulama basarisiz", "imza: anahtar yerlestirilmemis", "imza: bicim gecersiz")

## Girişler

<a id="cihaz-wifi-baglanmiyor"></a>
### cihaz-wifi-baglanmiyor · Cihaz Wi-Fi'ye bağlanmıyor: Wi-Fi LED'i yavaş (yaklaşık 0,7 sn) yanıp sönüyor, uygulamada cihaz çevrimdışı

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [cihaz_kontrol/include/wifi_baglanti.h:670](../../cihaz_kontrol/include/wifi_baglanti.h#L670) | <code>inline void wifiLoop() {</code> | Kayıtlı Wi-Fi varken bağlı değilse yedek yeniden deneme: bekleme 6 -> 12 -> 24 -> 48 -> 60 sn katlanır |
| [cihaz_kontrol/include/wifi_baglanti.h:43](../../cihaz_kontrol/include/wifi_baglanti.h#L43) | <code>inline constexpr unsigned long WIFI_RETRY_MIN_MS = 6000;</code> | Yeniden deneme beklemesinin başlangıç değeri (üst sınır WIFI_RETRY_MAX_MS 60 sn) |
| [cihaz_kontrol/include/wifi_baglanti.h:660](../../cihaz_kontrol/include/wifi_baglanti.h#L660) | <code>Serial.printf("WiFi baglanti koptu / basarisiz (Hata kodu: %d)\n", info.wifi_sta_disconne…</code> | Kopma/başarısızlık nedeni ESP-IDF "Hata kodu" olarak seriye yazılır |
| [cihaz_kontrol/include/wifi_baglanti.h:623](../../cihaz_kontrol/include/wifi_baglanti.h#L623) | <code>inline void wifiBaglan() {</code> | Açılışta NVS'teki SSID/parola ile WiFi.begin; kayıt yoksa BLE kuruluma geçer |
| [cihaz_kontrol/include/wifi_baglanti.h:261](../../cihaz_kontrol/include/wifi_baglanti.h#L261) | <code>inline void wifiUpdateLed() {</code> | Bağlıyken LED sürekli yanar; bağlı değilken yapılandırılmışsa 700 ms, değilse 150 ms yanıp söner |
| [cihaz_kontrol/include/wifi_baglanti.h:46](../../cihaz_kontrol/include/wifi_baglanti.h#L46) | <code>inline constexpr unsigned long WIFI_IP_BEKLEME_MAX_MS = 30000;</code> | AP'ye bağlanıp DHCP/IP beklenirken deneme en fazla 30 sn kesilmez |

**Olası nedenler**
- Kayıtlı SSID/parola yanlış ya da değişmiş (router parolası değişti)
- AP kapalı, menzil dışı veya yalnız 5 GHz yayın yapıyor (ESP32 yalnız 2,4 GHz)
- Seri günlükteki Hata kodu: 201 = AP bulunamadı, 202 = kimlik doğrulama başarısız (ESP-IDF WIFI_REASON kodları)
- DHCP/IP alınamıyor (IP bekleme 30 sn sonra deneme yenilenir)

**Adım adım kontrol**
- Seri monitörü açın (115200) ve "?" yazın: "Wi-Fi Durumu", "WiFi kayitli", "WiFi SSID" satırlarına bakın
- Günlükte "Kayitli WiFi bulundu: <ssid>" ve ardından gelen "Hata kodu" satırını okuyun
- AP'yi/parolayı doğrulayın; gerekirse reset butonu 3 sn ile Wi-Fi bilgisini silip BLE ile yeniden kurun (bkz. cihaz-wifi-sifirlama-butonu)
- LED hızlı yanıp sönüyorsa sorun bu değildir: cihaz-led-hizli-yanip-sonuyor

**Günlükte aranacak ifadeler**
- `Kayitli WiFi bulundu: %s, baglaniliyor...`
- `WiFi baglanti koptu / basarisiz (Hata kodu: %d)`
- `WiFi baglantisi yeniden deneniyor (%s)...`
- `WiFi IP alindi: %s`

**Komutlar**
```bash
cd cihaz_kontrol && pio device monitor -e lolin_c3_mini
```

**Bkz.:** [cihaz-led-hizli-yanip-sonuyor](#cihaz-led-hizli-yanip-sonuyor), [cihaz-wifi-sifirlama-butonu](#cihaz-wifi-sifirlama-butonu), [cihaz-saat-ntp-yok](#cihaz-saat-ntp-yok)

<a id="cihaz-led-hizli-yanip-sonuyor"></a>
### cihaz-led-hizli-yanip-sonuyor · Cihazın Wi-Fi LED'i hızlı (yaklaşık 0,15 sn) yanıp sönüyor: Wi-Fi bilgisi girilmemiş, kurulum bekliyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [cihaz_kontrol/include/wifi_baglanti.h:48](../../cihaz_kontrol/include/wifi_baglanti.h#L48) | <code>inline constexpr unsigned long WIFI_UNCONFIGURED_BLINK_INTERVAL_MS = 150;</code> | Wi-Fi yapılandırılmamışsa LED 150 ms aralıkla yanıp söner (yapılandırılmışsa 700 ms) |
| [cihaz_kontrol/include/wifi_baglanti.h:645](../../cihaz_kontrol/include/wifi_baglanti.h#L645) | <code>Serial.println("Kayitli WiFi yok, BLE provisioning baslatiliyor.");</code> | Kayıtlı SSID yoksa açılışta BLE kurulum modu başlar |
| [cihaz_kontrol/include/wifi_baglanti.h:702](../../cihaz_kontrol/include/wifi_baglanti.h#L702) | <code>} else if (!gWifiConfigured) {</code> | Çalışırken de yapılandırma yoksa kurulum modu (yeniden) açılır |
| [cihaz_kontrol/include/device_konfig.h:26](../../cihaz_kontrol/include/device_konfig.h#L26) | <code>constexpr int WIFI_STATUS_LED_PIN = 2;</code> | ESP32-C3: Wi-Fi LED GPIO2 |
| [cihaz_kontrol/include/device_konfig.h:11](../../cihaz_kontrol/include/device_konfig.h#L11) | <code>constexpr int WIFI_STATUS_LED_PIN = 23;</code> | WROOM: Wi-Fi/Power LED GPIO23 (açılışta 2 kez yanıp söner, sonra bağlıyken sürekli yanar) |

**Olası nedenler**
- Yeni ya da Wi-Fi'si sıfırlanmış kart: NVS'te SSID yok, cihaz BLE kurulum bekliyor (normal)
- Reset butonu 3 sn basılı tutulup Wi-Fi bilgisi silinmiş
- Kart atölye modunda (kayıtlı Wi-Fi yok) olduğu için h/l/p seri komutları açık

**Adım adım kontrol**
- Seri "?" çıktısı: "WiFi kayitli: Yok", "Bluetooth provisioning: aktif" ve "Bluetooth adi: SmartKeyPass<UID>" (eski firmware: AHBU<UID>)
- Uygulamadan cihaz ekleme (BLE) akışını başlatın; başarısızsa cihaz-ble-kurulum-basarisiz

**Günlükte aranacak ifadeler**
- `Kayitli WiFi yok, BLE provisioning baslatiliyor.`
- `BLE WiFi provisioning aktif: %s`

**Bkz.:** [cihaz-ble-gorunmuyor](#cihaz-ble-gorunmuyor), [cihaz-ble-kurulum-basarisiz](#cihaz-ble-kurulum-basarisiz), [cihaz-wifi-baglanmiyor](#cihaz-wifi-baglanmiyor)

<a id="cihaz-ble-gorunmuyor"></a>
### cihaz-ble-gorunmuyor · Telefon BLE taramasında "SmartKeyPass..." (eski kartlarda "AHBU...") adlı cihaz görünmüyor, Wi-Fi kurulumu başlatılamıyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [cihaz_kontrol/include/wifi_baglanti.h:375](../../cihaz_kontrol/include/wifi_baglanti.h#L375) | <code>return "SmartKeyPass" + cihazUniqueId();</code> | BLE cihaz adı: "SmartKeyPass" + 12 haneli UID (efuse MAC); eski firmware "AHBU" + UID yayınlardı |
| [cihaz_kontrol/include/wifi_baglanti.h:507](../../cihaz_kontrol/include/wifi_baglanti.h#L507) | <code>inline void wifiStartProvisioningMode() {</code> | BLE sunucusu/servis/özellikler kurulur ve yayın (advertising) başlar |
| [cihaz_kontrol/include/wifi_baglanti.h:699](../../cihaz_kontrol/include/wifi_baglanti.h#L699) | <code>if (gProvisioningMode &amp;&amp; wifiHasMqttCredentials()) {</code> | Wi-Fi bağlanıp MQTT kimliği de varsa BLE kurulum modu KAPATILIR |
| [cihaz_kontrol/include/wifi_baglanti.h:645](../../cihaz_kontrol/include/wifi_baglanti.h#L645) | <code>Serial.println("Kayitli WiFi yok, BLE provisioning baslatiliyor.");</code> | BLE yalnız kayıtlı Wi-Fi YOKKEN açılışta başlar |
| [cihaz_kontrol/include/wifi_baglanti.h:581](../../cihaz_kontrol/include/wifi_baglanti.h#L581) | <code>inline void wifiHandleResetButton() {</code> | Kayıtlı Wi-Fi varsa BLE'yi yeniden açmanın yolu: reset butonu 3 sn |

**Olası nedenler**
- Cihazda kayıtlı Wi-Fi var: BLE kurulum penceresi kapalı (önce reset butonu 3 sn ile Wi-Fi bilgisini silin)
- Cihaz Wi-Fi'ye bağlandı ve MQTT kimliği var: BLE kendiliğinden kapatıldı
- Yanlış cihaz: ad UID'ye bağlıdır, etiketle karşılaştırın
- Telefonda Bluetooth/konum izni kapalı (uygulama tarafı)

**Adım adım kontrol**
- Seri "?": "Bluetooth provisioning: aktif|pasif" ve "Bluetooth adi"
- pasif ise reset butonunu 3 sn basılı tutun; günlükte "WiFi ayarlari sifirlaniyor..." sonra "BLE WiFi provisioning aktif" görülmeli

**Günlükte aranacak ifadeler**
- `BLE WiFi provisioning aktif: %s`
- `BLE WiFi provisioning kapatildi.`
- `WiFi ayarlari sifirlaniyor...`

**Bkz.:** [cihaz-led-hizli-yanip-sonuyor](#cihaz-led-hizli-yanip-sonuyor), [cihaz-wifi-sifirlama-butonu](#cihaz-wifi-sifirlama-butonu), [cihaz-ble-kurulum-basarisiz](#cihaz-ble-kurulum-basarisiz)

<a id="cihaz-ble-kurulum-basarisiz"></a>
### cihaz-ble-kurulum-basarisiz · BLE ile Wi-Fi/MQTT kurulumu başarısız: "SSID bilgisi eksik veya gecersiz", "MQTT cihaz kimligi eksik" ya da "MQTT sunucu adresi izinli degil"

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [cihaz_kontrol/include/wifi_baglanti.h:433](../../cihaz_kontrol/include/wifi_baglanti.h#L433) | <code>class WifiProvisionCommandCallbacks : public BLECharacteristicCallbacks {</code> | BLE komut yazımı burada doğrulanır; hatalar BLE "result" özelliğine yazılır (seriye değil) |
| [cihaz_kontrol/include/wifi_baglanti.h:476](../../cihaz_kontrol/include/wifi_baglanti.h#L476) | <code>wifiNotifyBleResult("error", "SSID bilgisi eksik veya gecersiz.");</code> | SSID boş, 32 karakterden uzun ya da parola 63 karakterden uzun |
| [cihaz_kontrol/include/wifi_baglanti.h:488](../../cihaz_kontrol/include/wifi_baglanti.h#L488) | <code>wifiNotifyBleResult("error", "MQTT cihaz kimligi eksik. Once cihazi sirket hesabina kayde…</code> | mqtt_host / mqtt_port / mqtt_username / mqtt_password dördü birden dolu olmalı |
| [cihaz_kontrol/include/wifi_baglanti.h:412](../../cihaz_kontrol/include/wifi_baglanti.h#L412) | <code>inline bool wifiMqttHostIzinliMi(const String&amp; host) {</code> | MQTT sunucu adı yalnız izinli alan adı ekiyle bitebilir (sahte broker yönlendirmesi engeli) |
| [cihaz_kontrol/include/wifi_baglanti.h:37](../../cihaz_kontrol/include/wifi_baglanti.h#L37) | <code>#define AHBU_MQTT_HOST_SUFFIX ".gudeteknoloji.com.tr"</code> | Varsayılan izinli ek; özel/test ortamı için -D AHBU_MQTT_HOST_SUFFIX ile derlenir |
| [cihaz_kontrol/include/wifi_baglanti.h:39](../../cihaz_kontrol/include/wifi_baglanti.h#L39) | <code>inline constexpr size_t BLE_COMMAND_MAX_BYTES = 640;</code> | 640 bayttan büyük komut SESSİZCE yok sayılır (hata dönmez) |
| [cihaz_kontrol/include/wifi_baglanti.h:381](../../cihaz_kontrol/include/wifi_baglanti.h#L381) | <code>inline void wifiApplyProvisioningRequest() {</code> | Geçerli talep NVS'e yazılır, sonuç "restarting" olur ve cihaz yeniden başlar |

**Olası nedenler**
- MQTT cihaz kimliği (kullanıcı/parola) uygulama tarafından gönderilmedi: cihaz şirket hesabına kayıtlı değil (sunucu tarafı bu alanın dışında)
- MQTT sunucu adı izinli ekle (.gudeteknoloji.com.tr) bitmiyor; test sunucusu kullanılıyorsa firmware o ekle derlenmeli
- BLE komutu 640 bayttan uzun ya da kurulum penceresi kapalı: cihaz hiçbir sonuç yazmadan yok sayar
- Önceki talep henüz işlenmeden ikinci talep gönderildi (yok sayılır)
- JSON bozuk: "BLE komutu okunamadi."

**Adım adım kontrol**
- Uygulamada BLE sonuç metnini (status/message) okuyun: error/ready/restarting/scan_complete
- Cihaz kurulum penceresinde mi: seri "?" -> "Bluetooth provisioning: aktif"
- Başarıdan sonra cihaz yeniden başlar; seri günlükte "Kayitli WiFi bulundu" görülmeli

**Günlükte aranacak ifadeler**
- `SSID bilgisi eksik veya gecersiz.`
- `MQTT cihaz kimligi eksik. Once cihazi sirket hesabina kaydedin.`
- `MQTT sunucu adresi izinli degil.`
- `BLE komutu okunamadi.`
- `WiFi ve MQTT bilgileri kaydedildi. Cihaz temiz baglanti icin yeniden baslatiliyor.`

**Bkz.:** [cihaz-ble-gorunmuyor](#cihaz-ble-gorunmuyor), [cihaz-mqtt-kimlik-yok](#cihaz-mqtt-kimlik-yok)

<a id="cihaz-wifi-sifirlama-butonu"></a>
### cihaz-wifi-sifirlama-butonu · Wi-Fi bilgisini silmek / cihazı yeniden kuruluma almak için reset butonu çalışmıyor ("sifirlama iptal")

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [cihaz_kontrol/include/wifi_baglanti.h:581](../../cihaz_kontrol/include/wifi_baglanti.h#L581) | <code>inline void wifiHandleResetButton() {</code> | Düğme basılı süresi izlenir; 3 sn dolunca Wi-Fi bilgisi silinir ve cihaz yeniden başlar |
| [cihaz_kontrol/include/wifi_baglanti.h:616](../../cihaz_kontrol/include/wifi_baglanti.h#L616) | <code>Serial.println("WiFi ayarlari sifirlaniyor...");</code> | Sıfırlama tetiklendi: wifiForgetCredentials + yeniden başlatma |
| [cihaz_kontrol/include/wifi_baglanti.h:154](../../cihaz_kontrol/include/wifi_baglanti.h#L154) | <code>inline void wifiForgetCredentials() {</code> | YALNIZ SSID ve parolayı siler; MQTT kimliği ve yerel kontrol anahtarı NVS'te kalır |
| [cihaz_kontrol/include/device_konfig.h:15](../../cihaz_kontrol/include/device_konfig.h#L15) | <code>constexpr uint8_t WIFI_RESET_BUTTON_PIN = 0;</code> | Reset butonu GPIO0, aktif-düşük (iki donanım hedefinde de aynı) |
| [cihaz_kontrol/include/device_konfig.h:17](../../cihaz_kontrol/include/device_konfig.h#L17) | <code>constexpr unsigned long WIFI_RESET_HOLD_MS = 3000;</code> | Basılı tutma süresi 3000 ms (iki hedefte aynı) |

**Olası nedenler**
- 3 sn dolmadan bırakıldı: "WiFi reset butonu birakildi, sifirlama iptal."
- Düğme bağlantısı/GPIO0 hattı (INPUT_PULLUP, basınca LOW)
- WROOM'da GPIO0 aynı zamanda ESP32 boot pinidir: basılıyken açılırsa indirme moduna girebilir

**Adım adım kontrol**
- Seri günlükte "WiFi reset butonu algilandi. Sifirlama icin 3 saniye basili tutun." ve saniye sayacı "WiFi reset basili: N sn" çıkmalı
- Sıfırlamadan sonra cihaz yeniden başlar ve BLE kurulum açılır (cihaz-led-hizli-yanip-sonuyor)

**Günlükte aranacak ifadeler**
- `WiFi reset butonu algilandi. Sifirlama icin 3 saniye basili tutun.`
- `WiFi reset basili: `
- `WiFi reset butonu birakildi, sifirlama iptal.`
- `WiFi ayarlari sifirlaniyor...`

**Bkz.:** [cihaz-ble-gorunmuyor](#cihaz-ble-gorunmuyor), [cihaz-led-hizli-yanip-sonuyor](#cihaz-led-hizli-yanip-sonuyor)

<a id="cihaz-saat-ntp-yok"></a>
### cihaz-saat-ntp-yok · Wi-Fi bağlı görünüyor ama cihaz MQTT'ye hiç bağlanmıyor ve OTA başlamıyor (sistem saati NTP ile gelmemiş)

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [cihaz_kontrol/include/device_konfig.h:60](../../cihaz_kontrol/include/device_konfig.h#L60) | <code>inline bool zamanSenkronMu() {</code> | Saat "senkron" sayılır: epoch > 1600000000 |
| [cihaz_kontrol/include/device_konfig.h:57](../../cihaz_kontrol/include/device_konfig.h#L57) | <code>return now &gt; 1600000000 ? static_cast&lt;uint32_t&gt;(now) : 0;</code> | Eşik: NTP gelmeden time() küçük değer döner |
| [cihaz_kontrol/include/wifi_baglanti.h:697](../../cihaz_kontrol/include/wifi_baglanti.h#L697) | <code>sNtpConfigured = true;</code> | Wi-Fi bağlanınca configTime ile NTP başlatılır (pool.ntp.org, time.google.com, time.cloudflare.com; UTC+3) |
| [cihaz_kontrol/include/mqtt_baglanti.h:430](../../cihaz_kontrol/include/mqtt_baglanti.h#L430) | <code>if (!zamanSenkronMu()) {</code> | Saat gelmeden MQTT denemesi YAPILMAZ; 5 sn sonra tekrar bakılır (günlük yazmaz) |
| [cihaz_kontrol/include/ota_guncelleme.h:330](../../cihaz_kontrol/include/ota_guncelleme.h#L330) | <code>if (!zamanSenkronMu()) {</code> | Saat gelmeden OTA kontrolü başlamaz (TLS doğrulaması saate bağlı) |

**Olası nedenler**
- Ağ NTP sunucularına (UDP 123) ya da DNS'e izin vermiyor / internet yok
- Router yalnız yerel ağ veriyor (cihaz Wi-Fi'ye bağlı ama internet çıkışı yok)

**Adım adım kontrol**
- Günlükte "WiFi IP alindi" var ama hiç "MQTT baglaniyor (id=" satırı yoksa saat beklenir
- Aynı ağdaki başka cihazdan internet/NTP erişimini deneyin
- Yerel UDP kontrolü saat gerektirmez; internet gelince MQTT kendiliğinden bağlanır

**Günlükte aranacak ifadeler**
- `WiFi IP alindi: %s`
- `MQTT baglaniyor (id=`

**Bkz.:** [cihaz-wifi-baglanmiyor](#cihaz-wifi-baglanmiyor), [cihaz-mqtt-tls-hatasi](#cihaz-mqtt-tls-hatasi), [cihaz-ota-guncelleme-baslamiyor](#cihaz-ota-guncelleme-baslamiyor)

<a id="cihaz-mqtt-rc-hatasi"></a>
### cihaz-mqtt-rc-hatasi · Cihaz çevrimdışı: seri günlükte "MQTT baglaniyor (id=...)...Hata rc=N tekrar denenecek"

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [cihaz_kontrol/include/mqtt_baglanti.h:416](../../cihaz_kontrol/include/mqtt_baglanti.h#L416) | <code>inline bool mqttReconnect() {</code> | Bağlantı denemesi: ön koşullar (Wi-Fi, kimlik, saat), TCP ön kontrolü, client.connect ve sonuç günlüğü |
| [cihaz_kontrol/include/mqtt_baglanti.h:501](../../cihaz_kontrol/include/mqtt_baglanti.h#L501) | <code>Serial.print("Hata rc=");</code> | PubSubClient durum kodu (rc) ve (varsa) TLS hata metni burada yazılır |
| [cihaz_kontrol/include/mqtt_baglanti.h:391](../../cihaz_kontrol/include/mqtt_baglanti.h#L391) | <code>inline unsigned long mqttGeriCekilmeMs(int rc) {</code> | rc=4/5 (hatalı kimlik / yetkisiz) için 5 dk bekleme, diğerleri için 2 sn -> 60 sn üstel geri çekilme |
| [cihaz_kontrol/include/mqtt_baglanti.h:37](../../cihaz_kontrol/include/mqtt_baglanti.h#L37) | <code>inline constexpr unsigned long MQTT_UNAUTH_BEKLEME_MS = 5UL * 60UL * 1000UL;   // rc=4/5 …</code> | Yetkisiz/hatalı kimlik sonrası bekleme: 5 dakika |
| [cihaz_kontrol/include/mqtt_baglanti.h:24](../../cihaz_kontrol/include/mqtt_baglanti.h#L24) | <code>inline const char* MQTT_DEFAULT_SERVER = "mqtt.gudeteknoloji.com.tr";</code> | BLE ile sunucu verilmediyse varsayılan broker (port 8883, TLS) |

**Olası nedenler**
- rc=4 (kullanıcı/parola hatalı) veya rc=5 (yetkisiz/ACL): cihazın NVS'teki MQTT kimliği broker'da yok ya da değişmiş (sunucu/broker tarafı kapsam dışı)
- rc=-2 (PubSubClient bağlantı kurulamadı): TCP/TLS aşaması başarısız; satır sonundaki "tls=" metnine bakın (cihaz-mqtt-tls-hatasi)
- rc=-4 zaman aşımı: broker yanıt vermiyor ya da ağ çok yavaş
- Sunucu adı/port yanlış kaydedilmiş (BLE ile yazılan mqtt_host / mqtt_port)

**Adım adım kontrol**
- Seri "?": "MQTT kimligi: cihaz ozel kimlikli" mi, "MQTT sunucu: host:port" doğru mu
- rc=4/5 sonrası cihaz 5 dk bekler; hemen denemek için cihazı yeniden başlatın
- Broker günlüğünde aynı clientId ("SmartKeyPass-<UID>"; eski firmware "AHBU-<UID>") için red nedenini arayın

**Günlükte aranacak ifadeler**
- `MQTT baglaniyor (id=`
- `Hata rc=`
- ` tekrar denenecek`
- `baglandi`

**İlgili testler:** [cihaz_kontrol/host_test/t_mqtt.cpp](../../cihaz_kontrol/host_test/t_mqtt.cpp)

**Bkz.:** [cihaz-mqtt-tls-hatasi](#cihaz-mqtt-tls-hatasi), [cihaz-mqtt-kimlik-yok](#cihaz-mqtt-kimlik-yok), [cihaz-saat-ntp-yok](#cihaz-saat-ntp-yok)

<a id="cihaz-mqtt-tls-hatasi"></a>
### cihaz-mqtt-tls-hatasi · MQTT satırında "tls=..." hatası: sertifika doğrulanamıyor / TLS el sıkışma başarısız, cihaz çevrimdışı

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [cihaz_kontrol/include/tls_kok_sertifika.h:4](../../cihaz_kontrol/include/tls_kok_sertifika.h#L4) | <code>inline const char TLS_ROOT_CA[] PROGMEM = R"EOF(</code> | Gömülü kök CA (ISRG Root X1, 2035-06-04'e kadar geçerli); MQTT ve OTA bunu kullanır |
| [cihaz_kontrol/include/mqtt_baglanti.h:584](../../cihaz_kontrol/include/mqtt_baglanti.h#L584) | <code>espClientSecure.setCACert(TLS_ROOT_CA);</code> | MQTT TLS doğrulaması bu kök CA ile yapılır (setInsecure YOK) |
| [cihaz_kontrol/include/mqtt_baglanti.h:504](../../cihaz_kontrol/include/mqtt_baglanti.h#L504) | <code>if (espClientSecure.lastError(tlsHata, sizeof(tlsHata) - 1) != 0 &amp;&amp; tlsHata[0] != '\0') {</code> | mbedtls hata metni " tls=..." olarak seriye eklenir |
| [cihaz_kontrol/include/mqtt_baglanti.h:32](../../cihaz_kontrol/include/mqtt_baglanti.h#L32) | <code>inline constexpr uint32_t MQTT_TLS_HANDSHAKE_TIMEOUT_S = 10;</code> | El sıkışma zaman aşımı 10 sn (loop bu sürede bloklanabilir) |
| [cihaz_kontrol/include/ota_guncelleme.h:355](../../cihaz_kontrol/include/ota_guncelleme.h#L355) | <code>inline bool otaReadManifest(JsonDocument&amp; doc) {</code> | OTA da aynı kök CA ile api.gudeteknoloji.com.tr'ye bağlanır: sertifika sorunu OTA'yı da bozar |

**Olası nedenler**
- Broker/API sertifika zinciri gömülü kök CA'ya (ISRG Root X1) bağlanmıyor ya da sunucu sertifikasının süresi dolmuş (yenilenmemiş)
- Kök CA değişirse cihaz firmware'i güncellenmelidir; sertifika sorunu varken OTA da çalışmaz, USB gerekir
- Ağda TLS'e müdahale eden proxy/güvenlik duvarı
- Sistem saati yanlışsa sertifika geçerlilik denetimi başarısız olur (cihaz saat gelmeden zaten denemez)

**Adım adım kontrol**
- "Hata rc=-2 tls=..." satırındaki metni kaydedin
- Sunucu sertifikasını dışarıdan inceleyin (aşağıdaki komut); zincirin ISRG Root X1'e çıktığını doğrulayın
- Aynı ağda OTA da "manifest http hata" veriyorsa sorun ortak TLS/kök CA/saat'tir (cihaz-ota-manifest-hatasi)

**Günlükte aranacak ifadeler**
- `Hata rc=`
- ` tls=`

**Komutlar**
```bash
openssl s_client -connect mqtt.gudeteknoloji.com.tr:8883 -servername mqtt.gudeteknoloji.com.tr </dev/null 2>/dev/null | openssl x509 -noout -issuer -dates
```

**Bkz.:** [cihaz-mqtt-rc-hatasi](#cihaz-mqtt-rc-hatasi), [cihaz-saat-ntp-yok](#cihaz-saat-ntp-yok), [cihaz-ota-manifest-hatasi](#cihaz-ota-manifest-hatasi)

<a id="cihaz-mqtt-kimlik-yok"></a>
### cihaz-mqtt-kimlik-yok · Wi-Fi bağlı ama MQTT hiç denenmiyor: günlükte "MQTT kimligi yok; BLE provisioning ile cihaz kimligi yazilmali."

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [cihaz_kontrol/include/mqtt_baglanti.h:425](../../cihaz_kontrol/include/mqtt_baglanti.h#L425) | <code>Serial.println("MQTT kimligi yok; BLE provisioning ile cihaz kimligi yazilmali.");</code> | Kimlik yoksa her 10 sn bu satır yazılır ve bağlantı denenmez |
| [cihaz_kontrol/include/wifi_baglanti.h:162](../../cihaz_kontrol/include/wifi_baglanti.h#L162) | <code>inline bool wifiHasMqttCredentials() {</code> | Kimlik = NVS'te mqtt_user ve mqtt_pass dolu |
| [cihaz_kontrol/include/wifi_baglanti.h:134](../../cihaz_kontrol/include/wifi_baglanti.h#L134) | <code>inline void wifiPersistMqttCredentials(</code> | host, port, kullanıcı, parola dördü birden dolu değilse HİÇBİR ŞEY yazılmaz |
| [cihaz_kontrol/include/wifi_baglanti.h:23](../../cihaz_kontrol/include/wifi_baglanti.h#L23) | <code>inline constexpr char WIFI_PREF_MQTT_USER[] = "mqtt_user";</code> | NVS anahtarı (namespace wifi_cfg) |
| [cihaz_kontrol/src/main.cpp:395](../../cihaz_kontrol/src/main.cpp#L395) | <code>Serial.println(wifiHasMqttCredentials() ? "cihaz ozel kimlikli" : "eksik");</code> | Seri durum dökümü: "MQTT kimligi: cihaz ozel kimlikli \| eksik" |

**Olası nedenler**
- Cihaz BLE ile şirket hesabına kayıtlı kurulmadı ya da NVS silindi (erase_flash)
- Reset butonu MQTT kimliğini silmez; kimlik eksikse BLE ile yeniden kurulum şart

**Adım adım kontrol**
- Seri "?": "MQTT kimligi: eksik" ise kimlik yoktur
- BLE kurulumunu yeniden yapın (cihaz-ble-kurulum-basarisiz)
- Not: bu durumda 6 saatlik kendini toparlama yeniden başlatması devreye girmez (bağlantı beklenmediği için)

**Günlükte aranacak ifadeler**
- `MQTT kimligi yok; BLE provisioning ile cihaz kimligi yazilmali.`

**Bkz.:** [cihaz-ble-kurulum-basarisiz](#cihaz-ble-kurulum-basarisiz), [cihaz-mqtt-rc-hatasi](#cihaz-mqtt-rc-hatasi)

<a id="cihaz-mqtt-yayin-basarisiz"></a>
### cihaz-mqtt-yayin-basarisiz · Cihaz bağlı görünüyor ama durum/olay/log yayınları sunucuya ulaşmıyor; günlükte "MQTT publish basarisiz"

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [cihaz_kontrol/include/mqtt_baglanti.h:87](../../cihaz_kontrol/include/mqtt_baglanti.h#L87) | <code>inline bool mqttYayinla(const char* topic, const char* payload, bool retained) {</code> | Tüm yayınlar buradan geçer; 5 ardışık hatada bağlantı kapatılıp yeniden kurulur |
| [cihaz_kontrol/include/mqtt_baglanti.h:96](../../cihaz_kontrol/include/mqtt_baglanti.h#L96) | <code>Serial.print("MQTT publish basarisiz: ");</code> | Başarısız yayının konusu seriye yazılır |
| [cihaz_kontrol/include/mqtt_baglanti.h:30](../../cihaz_kontrol/include/mqtt_baglanti.h#L30) | <code>inline constexpr size_t MQTT_BUFFER_SIZE = 1024;           // state/event/logs yayinlari …</code> | PubSubClient tamponu 1024 bayt: daha büyük JSON yayınlanamaz |
| [cihaz_kontrol/include/mqtt_baglanti.h:591](../../cihaz_kontrol/include/mqtt_baglanti.h#L591) | <code>if (!client.setBufferSize(MQTT_BUFFER_SIZE)) {</code> | Tampon ayrılamazsa (bellek) uyarı basılır |
| [cihaz_kontrol/include/offline_log.h:454](../../cihaz_kontrol/include/offline_log.h#L454) | <code>Serial.println("Offline Log: batch yayinlanamadi (MQTT).");</code> | Çevrimdışı log batch'i de aynı yolla yayınlanamıyorsa görülür |

**Olası nedenler**
- Bağlantı kopmuş ama PubSubClient henüz fark etmedi (keepalive 15 sn)
- Yük 1024 baytı aşıyor (state/event JSON büyümüş)
- Heap yetersiz: "MQTT tamponu ayrilamadi; yayinlar basarisiz olabilir!"

**Adım adım kontrol**
- Seri günlükte "MQTT publish basarisiz: device/<UID>/..." satırının konusuna bakın
- Arka arkaya 5 hatadan sonra cihaz bağlantıyı yeniler; ardından "MQTT baglaniyor" görülür

**Günlükte aranacak ifadeler**
- `MQTT publish basarisiz: `
- `MQTT tamponu ayrilamadi; yayinlar basarisiz olabilir!`

**İlgili testler:** [cihaz_kontrol/host_test/t_mqtt.cpp](../../cihaz_kontrol/host_test/t_mqtt.cpp)

**Bkz.:** [cihaz-mqtt-rc-hatasi](#cihaz-mqtt-rc-hatasi), [cihaz-offline-log-senkronize-olmuyor](#cihaz-offline-log-senkronize-olmuyor)

<a id="cihaz-mqtt-tcp-onkontrol"></a>
### cihaz-mqtt-tcp-onkontrol · İnternet kesilince cihaz yavaşlıyor/yerel işler gecikiyor; günlükte "MQTT: broker TCP on-kontrolu basarisiz (ag/internet yok?)"

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [cihaz_kontrol/include/mqtt_baglanti.h:407](../../cihaz_kontrol/include/mqtt_baglanti.h#L407) | <code>inline bool mqttTcpOnKontrol(const IPAddress&amp; ip, uint16_t port) {</code> | Broker IP'sine 400 ms'lik TCP sondası (DNS ve TLS yok) |
| [cihaz_kontrol/include/mqtt_baglanti.h:444](../../cihaz_kontrol/include/mqtt_baglanti.h#L444) | <code>Serial.println("MQTT: broker TCP on-kontrolu basarisiz (ag/internet yok?); tam baglanti d…</code> | Ön kontrol başarısızsa tam bağlantı (DNS+TCP+TLS, 5-15 sn bloklar) denenmez |
| [cihaz_kontrol/include/mqtt_baglanti.h:41](../../cihaz_kontrol/include/mqtt_baglanti.h#L41) | <code>inline constexpr uint8_t MQTT_ONKONTROL_ATLAMA_MAX = 3;                        // art ard…</code> | 3 ardışık ön kontrol hatasından sonra 4. deneme TAM connect yapar (broker IP'si değişirse iyileşir) |
| [cihaz_kontrol/include/mqtt_baglanti.h:36](../../cihaz_kontrol/include/mqtt_baglanti.h#L36) | <code>inline constexpr unsigned long MQTT_RECONNECT_MAX_MS = 60000;</code> | Geri çekilme 2 sn'den 60 sn'ye katlanır (+%25 jitter) |

**Olası nedenler**
- Wi-Fi bağlı ama internet/broker erişilemiyor: ön kontrol başarısız, normal geri çekilme uygulanır (beklenen davranış)
- Tam connect yapıldığında DNS/TLS yüzünden loop 5-15 sn bloklanır; bu sürede yerel UDP/QR/ekran gecikir

**Adım adım kontrol**
- İnternet geri geldiğinde cihaz en geç 60 sn (+jitter) içinde bağlanır; bağlanmazsa cihaz-mqtt-rc-hatasi
- Yerel UDP kapı kontrolü internet olmadan da çalışır (cihaz-yerel-udp-cevap-yok)

**Günlükte aranacak ifadeler**
- `MQTT: broker TCP on-kontrolu basarisiz (ag/internet yok?); tam baglanti denenmedi.`

**İlgili testler:** [cihaz_kontrol/host_test/t_mqtt.cpp](../../cihaz_kontrol/host_test/t_mqtt.cpp)

**Bkz.:** [cihaz-mqtt-rc-hatasi](#cihaz-mqtt-rc-hatasi), [cihaz-mqtt-6-saat-yeniden-baslama](#cihaz-mqtt-6-saat-yeniden-baslama)

<a id="cihaz-mqtt-6-saat-yeniden-baslama"></a>
### cihaz-mqtt-6-saat-yeniden-baslama · Cihaz kendiliğinden yeniden başlıyor; sunucuda "self_recovery_restart" (mqtt_6h) olayı görülüyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [cihaz_kontrol/include/mqtt_baglanti.h:560](../../cihaz_kontrol/include/mqtt_baglanti.h#L560) | <code>inline void mqttKendiniToparla() {</code> | Wi-Fi hazır + MQTT kimliği var iken 6 saat hiç bağlanılamazsa kontrollü ESP.restart() |
| [cihaz_kontrol/include/mqtt_baglanti.h:42](../../cihaz_kontrol/include/mqtt_baglanti.h#L42) | <code>inline constexpr unsigned long MQTT_KENDINI_TOPARLA_MS = 6UL * 60UL * 60UL * 1000UL;  // …</code> | 6 saatlik eşik |
| [cihaz_kontrol/include/mqtt_baglanti.h:573](../../cihaz_kontrol/include/mqtt_baglanti.h#L573) | <code>Serial.println("MQTT 6 saattir baglanamadi: kontrollu yeniden baslatma (kendini toparlama…</code> | Yeniden başlatmadan hemen önce yazılan günlük satırı |
| [cihaz_kontrol/include/mqtt_baglanti.h:493](../../cihaz_kontrol/include/mqtt_baglanti.h#L493) | <code>mqttPublishEvent("self_recovery_restart", "mqtt_6h");</code> | Sonraki açılışta MQTT bağlanınca bir kez bildirilir (saha tanılaması) |
| [cihaz_kontrol/include/mqtt_baglanti.h:543](../../cihaz_kontrol/include/mqtt_baglanti.h#L543) | <code>inline void mqttBootNedeniOku() {</code> | Yeniden başlatma nedeni NVS işaretinden okunur (namespace ahbu_sys) |

**Olası nedenler**
- Broker/internet 6 saatten uzun erişilemedi (broker reddi rc>0 sayacı tazeler, yeniden başlatma olmaz)
- Heap parçalanması ya da TLS/lwIP takılması nedeniyle bağlantı kalıcı kurulamadı
- Role aktif ya da OTA sürüyorsa yeniden başlatma ertelenir
- Çalışan imaj PENDING_VERIFY ise bu yeniden başlatma bootloader'da önceki imaja geri dönüşü tetikler (istenen davranış)

**Adım adım kontrol**
- Sunucu günlüğünde olayın zamanına bakın; öncesinde 6 saat cihaz çevrimdışı muydu
- Yeniden başlatma röle pulse'u üretmez (roleSetup setup'ın ilk satırı)
- Sık tekrarlıyorsa cihaz-mqtt-rc-hatasi ve cihaz-mqtt-tls-hatasi adımlarını izleyin

**Günlükte aranacak ifadeler**
- `MQTT 6 saattir baglanamadi: kontrollu yeniden baslatma (kendini toparlama).`

**İlgili testler:** [cihaz_kontrol/host_test/t_mqtt.cpp](../../cihaz_kontrol/host_test/t_mqtt.cpp)

**Bkz.:** [cihaz-mqtt-rc-hatasi](#cihaz-mqtt-rc-hatasi), [cihaz-watchdog-yeniden-basliyor](#cihaz-watchdog-yeniden-basliyor), [cihaz-ota-sonrasi-geri-aldi](#cihaz-ota-sonrasi-geri-aldi)

<a id="cihaz-ota-guncelleme-baslamiyor"></a>
### cihaz-ota-guncelleme-baslamiyor · Panelden "güncelle" denildi ya da yeni sürüm yayınlandı ama cihaz OTA kontrolünü hiç başlatmıyor ("OTA kontrolu basladi." günlükte yok)

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [cihaz_kontrol/include/ota_guncelleme.h:321](../../cihaz_kontrol/include/ota_guncelleme.h#L321) | <code>inline bool otaShouldCheckNow() {</code> | Kontrol başlamasının tüm ön koşulları: Wi-Fi hazır, OTA sürmüyor, röle pasif, saat senkron, imaj doğrulanmış, 10 dk tekrar sınırı |
| [cihaz_kontrol/include/ota_guncelleme.h:722](../../cihaz_kontrol/include/ota_guncelleme.h#L722) | <code>inline void otaCheckAndUpdate() {</code> | Ana döngüden her turda çağrılır; ilk plan Wi-Fi oturunca ~90 sn + MAC tabanlı gecikmeyle kurulur |
| [cihaz_kontrol/include/ota_guncelleme.h:63](../../cihaz_kontrol/include/ota_guncelleme.h#L63) | <code>inline constexpr unsigned long OTA_BOOT_CHECK_DELAY_MS = 90UL * 1000UL;</code> | Açılıştan sonra ilk otomatik kontrol en az ~90 sn (+0-60 sn cihaz gecikmesi) sonra; sonra 24 saatte bir |
| [cihaz_kontrol/include/ota_guncelleme.h:295](../../cihaz_kontrol/include/ota_guncelleme.h#L295) | <code>inline void otaTalepEt(const char* reason = "manual", bool dagit = false) {</code> | Elle/MQTT talebi: tekil talep hemen, toplu iş (ota_job_id) 0-120 sn dağıtılarak planlanır |
| [cihaz_kontrol/include/mqtt_baglanti.h:350](../../cihaz_kontrol/include/mqtt_baglanti.h#L350) | <code>} else if (action == "ota_check") {</code> | Sunucudan gelen ota_check komutu (retry ve ota_job_id burada okunur) |
| [cihaz_kontrol/src/main.cpp:510](../../cihaz_kontrol/src/main.cpp#L510) | <code>otaCheckAndUpdate();</code> | Döngüde OTA çağrısı |

**Olası nedenler**
- Çalışan imaj doğrulanmadı (PENDING_VERIFY): yeni OTA, imaj 60 sn sağlıklı kalıp geçerli işaretlenene kadar başlamaz (talep korunur)
- Röle aktif (kapı açık darbesi ya da seri "h" tutması): OTA ertelenir
- Sistem saati NTP ile gelmedi (cihaz-saat-ntp-yok) ya da Wi-Fi hazır değil
- Son denemeden 10 dk geçmedi (OTA_MIN_RETRY_MS); yalnız açık yönetici talebi bunu atlar
- Açılıştan sonra henüz ~90 sn + jitter geçmedi; ya da 24 saatlik periyot dolmadı
- Manifest "interval_hours" büyük verildi (en fazla 7 gün, en az 1 saat uygulanır)

**Adım adım kontrol**
- Seri "?": "OTA durum", "OTA son hedef surum" ve "Firmware surumu" satırlarını okuyun
- Açılış günlüğünde "OTA: calisan imaj dogrulanmadi (PENDING_VERIFY)" var mı bakın; varsa Wi-Fi + MQTT 60 sn kesintisiz bağlı kalmalı
- Sunucu tarafında ota_check komutunun gönderildiğini ve "ota_check_requested" olayının geldiğini doğrulayın
- Günlükte "OTA kontrol talebi: mqtt" görüldü ama "OTA kontrolu basladi." görülmüyorsa yukarıdaki ön koşullardan biri engellemektedir

**Günlükte aranacak ifadeler**
- `OTA kontrol talebi: `
- `OTA kontrolu basladi.`
- `OTA: calisan imaj dogrulanmadi (PENDING_VERIFY); dogrulanana kadar yeni OTA baslatilmaz.`

**İlgili testler:** [cihaz_kontrol/host_test/t_mqtt.cpp](../../cihaz_kontrol/host_test/t_mqtt.cpp)

**Bkz.:** [cihaz-saat-ntp-yok](#cihaz-saat-ntp-yok), [cihaz-ota-manifest-hatasi](#cihaz-ota-manifest-hatasi), [cihaz-ota-sonrasi-geri-aldi](#cihaz-ota-sonrasi-geri-aldi), [cihaz-ota-is-kimligi-yansimiyor](#cihaz-ota-is-kimligi-yansimiyor)

<a id="cihaz-ota-manifest-hatasi"></a>
### cihaz-ota-manifest-hatasi · OTA durumu "manifest http hata: N", "manifest json okunamadi" ya da "manifest baglantisi baslatilamadi" gösteriyor; olay ota_check_failed

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [cihaz_kontrol/include/ota_guncelleme.h:355](../../cihaz_kontrol/include/ota_guncelleme.h#L355) | <code>inline bool otaReadManifest(JsonDocument&amp; doc) {</code> | Manifest GET isteği: ?current_version=&uid= ile; hata durumu NVS'e "manifest ..." olarak yazılır |
| [cihaz_kontrol/include/ota_guncelleme.h:38](../../cihaz_kontrol/include/ota_guncelleme.h#L38) | <code>inline constexpr char OTA_MANIFEST_URL[] =</code> | Hedefe göre manifest adresi (c3 ve wroom ayrı yol); iki tanım var, ilkini gösterir |
| [cihaz_kontrol/include/ota_guncelleme.h:376](../../cihaz_kontrol/include/ota_guncelleme.h#L376) | <code>otaPersistStatus("manifest http hata: " + String(code));</code> | HTTP 200 dışı yanıt: negatif kod bağlantı/TLS/zaman aşımı, pozitif kod sunucu yanıtı |
| [cihaz_kontrol/include/ota_guncelleme.h:749](../../cihaz_kontrol/include/ota_guncelleme.h#L749) | <code>Serial.print("OTA manifest hatasi: ");</code> | Hata seriye yazılır, ota_check_failed olayı yayınlanır, üstel geri çekilme başlar (10-20-40 dk) |
| [cihaz_kontrol/include/ota_guncelleme.h:151](../../cihaz_kontrol/include/ota_guncelleme.h#L151) | <code>inline void otaPlanFailure() {</code> | Başarısız denemede geri çekilme: 10 dk, 20 dk, 40 dk ... en çok periyodik aralık |
| [cihaz_kontrol/include/tls_kok_sertifika.h:4](../../cihaz_kontrol/include/tls_kok_sertifika.h#L4) | <code>inline const char TLS_ROOT_CA[] PROGMEM = R"EOF(</code> | Manifest TLS doğrulaması bu gömülü kök CA ile yapılır |

**Olası nedenler**
- Sunucu manifest dosyasını vermiyor (404/500): sunucuda ilgili hedef klasörü ya da manifest.json yok (bkz. OTA_KURULUM.txt)
- Negatif http kodu: TLS/DNS/zaman aşımı; ortak neden kök CA, saat ya da internettir (cihaz-mqtt-tls-hatasi)
- Manifest JSON bozuk (sunucuda elle düzenlenmiş)
- API (api.gudeteknoloji.com.tr) geçici erişilemiyor

**Adım adım kontrol**
- Seri "?" -> "OTA durum" satırında hata metni görünür
- Aynı manifest adresini dışarıdan açın: https://api.gudeteknoloji.com.tr/firmware/esp32-c3/manifest.json (wroom için esp32-wroom)
- MQTT de TLS hatası veriyorsa kök neden ortaktır (cihaz-mqtt-tls-hatasi)
- Hata geçiciyse cihaz kendisi 10 dk sonra yeniden dener; elle denemek için ota_check komutu gönderin

**Günlükte aranacak ifadeler**
- `OTA manifest hatasi: `
- `manifest http hata: `
- `manifest json okunamadi`

**Komutlar**
```bash
curl -s -o /dev/null -w "%{http_code}\n" https://api.gudeteknoloji.com.tr/firmware/esp32-c3/manifest.json
```

**İlgili testler:** [cihaz_kontrol/host_test/t_mqtt.cpp](../../cihaz_kontrol/host_test/t_mqtt.cpp)

**Bkz.:** [cihaz-mqtt-tls-hatasi](#cihaz-mqtt-tls-hatasi), [cihaz-ota-guncelleme-baslamiyor](#cihaz-ota-guncelleme-baslamiyor), [cihaz-saat-ntp-yok](#cihaz-saat-ntp-yok)

<a id="cihaz-ota-hedef-uyusmazligi"></a>
### cihaz-ota-hedef-uyusmazligi · OTA durumu "hedef uyusmazligi", "USB ile tam yukleme gerekli" ya da "indirme adresi reddedildi"; cihaz güncellenmiyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [cihaz_kontrol/include/ota_guncelleme.h:759](../../cihaz_kontrol/include/ota_guncelleme.h#L759) | <code>if (!manifestTarget.isEmpty() &amp;&amp; manifestTarget != OTA_TARGET) {</code> | Manifestin target alanı cihaz hedefiyle (esp32-c3 \| esp32-wroom) eşleşmezse güncelleme YAPILMAZ |
| [cihaz_kontrol/include/ota_guncelleme.h:47](../../cihaz_kontrol/include/ota_guncelleme.h#L47) | <code>inline constexpr char OTA_ALLOWED_URL_PREFIX[] = "https://api.gudeteknoloji.com.tr/";</code> | İndirme adresi yalnız bu önekle (https + api.gudeteknoloji.com.tr) başlayabilir |
| [cihaz_kontrol/include/ota_guncelleme.h:792](../../cihaz_kontrol/include/ota_guncelleme.h#L792) | <code>if (usbRequired) {</code> | Manifest usb_required ise OTA yapılmaz; "ota_usb_required" olayı |
| [cihaz_kontrol/include/ota_guncelleme.h:815](../../cihaz_kontrol/include/ota_guncelleme.h#L815) | <code>if (otaSurumKarsilastir(version, String(OTA_CURRENT_VERSION)) &lt;= 0) {</code> | Yalnız artan sürüm kabul edilir; eşit/eski sürüm "downgrade reddedildi" ve cihaz "güncel" sayılır |
| [cihaz_kontrol/include/ota_guncelleme.h:855](../../cihaz_kontrol/include/ota_guncelleme.h#L855) | <code>if (!otaSha256HexGecerli(sha256)) {</code> | Manifestte 64 hane hex sha256 yoksa güncelleme yapılmaz |
| [cihaz_kontrol/include/ota_guncelleme.h:32](../../cihaz_kontrol/include/ota_guncelleme.h#L32) | <code>inline constexpr char OTA_VERSION_C3[] = "4.4.0";</code> | C3 sürüm sabiti (WROOM ayrı: OTA_VERSION_WROOM); manifest sürümü bundan büyük olmalı (sürüm değeri satırda; araç her sürümde yeniden yazar) |

**Olası nedenler**
- Sunucuda yanlış klasöre firmware konmuş: wroom bin dosyası c3 manifestinde ya da tersi (iki donanımın dosyaları asla karışmamalı)
- Manifest url alanı http:// ya da başka alan adı gösteriyor
- Manifest sha256 alanı boş/kısa/hatalı
- Manifest sürümü cihaz sürümünden büyük değil (örn. cihaz ve manifest aynı sürümde)
- Sunucu bilerek usb_required=true veriyor (partition tablosu değişti, OTA yetmez)

**Adım adım kontrol**
- Manifesti açın: target, version, url, sha256 alanlarını cihaz hedefiyle karşılaştırın
- Seri günlükte "OTA HATA: Hedef mimari uyusmuyor!" satırında cihaz hedefi ile manifest hedefi birlikte yazılır
- Sürüm karşılaştırması parçalıdır ("4.1.4" < "4.2.0"); sürüm sabitleri ota_guncelleme.h başındadır

**Günlükte aranacak ifadeler**
- `OTA HATA: Hedef mimari uyusmuyor! Cihaz hedefi: `
- `OTA HATA: manifest url izinli sunucu/HTTPS degil.`
- `OTA HATA: manifest sha256 alani yok veya gecersiz; guncelleme yapilmadi.`
- `OTA: manifest surumu mevcut surumden yeni degil; downgrade reddedildi.`

**İlgili testler:** [cihaz_kontrol/host_test/t_mqtt.cpp](../../cihaz_kontrol/host_test/t_mqtt.cpp)

**Bkz.:** [cihaz-ota-guncelleme-baslamiyor](#cihaz-ota-guncelleme-baslamiyor), [cihaz-ota-indirme-basarisiz](#cihaz-ota-indirme-basarisiz), [cihaz-ota-manifest-hatasi](#cihaz-ota-manifest-hatasi)

<a id="cihaz-ota-indirme-basarisiz"></a>
### cihaz-ota-indirme-basarisiz · OTA durumu "guncelleme basarisiz: ..." (indirme eksik/hatali, sha256 uyusmuyor, Update.begin/Update.end basarisiz) ve olay ota_failed

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [cihaz_kontrol/include/ota_guncelleme.h:634](../../cihaz_kontrol/include/ota_guncelleme.h#L634) | <code>inline String otaIndirVeYaz(const String&amp; url, const String&amp; beklenenSha256, const String…</code> | İndirme + SHA-256 + Update; dönüş "" ise başarılı, aksi halde hata metni; agHatasi geçici ağ hatasını ayırır |
| [cihaz_kontrol/include/ota_guncelleme.h:696](../../cihaz_kontrol/include/ota_guncelleme.h#L696) | <code>return "sha256 uyusmuyor";</code> | Hesaplanan özet manifestteki sha256 ile eşleşmezse yazılan imaj iptal edilir (boot bölümü değişmez) |
| [cihaz_kontrol/include/ota_guncelleme.h:667](../../cihaz_kontrol/include/ota_guncelleme.h#L667) | <code>return "firmware boyutu bilinmiyor";</code> | Sunucu Content-Length vermezse indirme başlamaz |
| [cihaz_kontrol/include/ota_guncelleme.h:672](../../cihaz_kontrol/include/ota_guncelleme.h#L672) | <code>return "Update.begin basarisiz: " + String(Update.errorString());</code> | Hedef bölüme sığmıyorsa/başlatılamıyorsa (bölüm tablosu, boyut) |
| [cihaz_kontrol/include/ota_guncelleme.h:708](../../cihaz_kontrol/include/ota_guncelleme.h#L708) | <code>return "Update.end basarisiz: " + String(Update.errorString());</code> | İmaj doğrulaması (MD5/başlık) başarısız |
| [cihaz_kontrol/include/ota_guncelleme.h:433](../../cihaz_kontrol/include/ota_guncelleme.h#L433) | <code>class OtaHashStream : public Stream {</code> | Gelen veriyi Update'e yazar ve SHA-256 hesaplar; flash yazma hatası hata=true yapar |
| [cihaz_kontrol/include/ota_guncelleme.h:924](../../cihaz_kontrol/include/ota_guncelleme.h#L924) | <code>if (gOtaMqttKapat != nullptr) {</code> | İndirmeden önce MQTT TLS oturumu kapatılır (bellek); sunucuda kısa offline görülür |
| [cihaz_kontrol/include/mqtt_baglanti.h:524](../../cihaz_kontrol/include/mqtt_baglanti.h#L524) | <code>inline void mqttOtaOncesiKapat() {</code> | availability=offline yayınlanır ve MQTT bağlantısı kesilir |

**Olası nedenler**
- Dosya sunucuda değişti ya da manifestteki sha256 yanlış (build sonrası yeniden üretilmemiş)
- İndirme yarıda koptu (Wi-Fi zayıf); bu geçici ağ hatasıdır, deneme hakkı iade edilir
- TLS belleği yetersiz (ikinci TLS oturumu) ya da sertifika sorunu
- Firmware.bin bölüme (0x1E0000 bayt) sığmıyor
- Flash yazma hatası (nadir): deneme hakkı yanar

**Adım adım kontrol**
- Seri günlükte "[OTA] Indiriliyor: %N" ilerlemesini izleyin; hangi yüzdede kesildiğine bakın
- Sunucudaki firmware.bin dosyasının SHA-256'sını manifestle karşılaştırın
- Sinyal gücünü kontrol edin (seri "?" -> "WiFi gucu")
- Hata geçici ağ hatasıysa cihaz 10 dk sonra yeniden dener; sha256/imaj hatasında hak yanar ve en çok 3 deneme yapılır (cihaz-ota-deneme-siniri-asildi)

**Günlükte aranacak ifadeler**
- `[OTA] Indiriliyor: %`
- `guncelleme basarisiz: `
- `indirme eksik/hatali (`
- `indirme http hata: `

**İlgili testler:** [cihaz_kontrol/host_test/t_mqtt.cpp](../../cihaz_kontrol/host_test/t_mqtt.cpp)

**Bkz.:** [cihaz-ota-deneme-siniri-asildi](#cihaz-ota-deneme-siniri-asildi), [cihaz-ota-hedef-uyusmazligi](#cihaz-ota-hedef-uyusmazligi), [cihaz-mqtt-tls-hatasi](#cihaz-mqtt-tls-hatasi)

<a id="cihaz-ota-deneme-siniri-asildi"></a>
### cihaz-ota-deneme-siniri-asildi · OTA durumu "deneme siniri asildi (3): <sürüm>"; cihaz aynı sürümü bir daha denemiyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [cihaz_kontrol/include/ota_guncelleme.h:406](../../cihaz_kontrol/include/ota_guncelleme.h#L406) | <code>inline bool otaDenemeHakkiAyir(const String&amp; version) {</code> | Aynı sürüm için deneme sayacı NVS'te (try_ver / try_cnt) tutulur; 3 hak |
| [cihaz_kontrol/include/ota_guncelleme.h:71](../../cihaz_kontrol/include/ota_guncelleme.h#L71) | <code>inline constexpr uint8_t OTA_MAX_DENEME = 3;                           // ayni surum icin…</code> | Aynı sürüm için en çok 3 deneme |
| [cihaz_kontrol/include/ota_guncelleme.h:422](../../cihaz_kontrol/include/ota_guncelleme.h#L422) | <code>inline void otaDenemeHakkiIadeEt(const String&amp; version) {</code> | Yalnız geçici ağ hatasında hak iade edilir; güç kesintisi, geri alma, sha256 ve flash hatalarında hak yanar |
| [cihaz_kontrol/include/ota_guncelleme.h:307](../../cihaz_kontrol/include/ota_guncelleme.h#L307) | <code>inline void otaDenemeSayacinaSifirla() {</code> | Yönetici ota_check ile retry:true gönderince sayaç ve geri çekilme sıfırlanır |
| [cihaz_kontrol/include/mqtt_baglanti.h:351](../../cihaz_kontrol/include/mqtt_baglanti.h#L351) | <code>if (doc["retry"] &#124; false) {</code> | ota_check komutunda retry alanı |
| [cihaz_kontrol/include/ota_guncelleme.h:905](../../cihaz_kontrol/include/ota_guncelleme.h#L905) | <code>otaPersistStatus("deneme siniri asildi (" + String(OTA_MAX_DENEME) + "): " + version, ver…</code> | Sınır aşılınca cihaz daha yeni bir sürüm bekler |

**Olası nedenler**
- Aynı sürüm 3 kez denendi ve her seferinde sha256/imaj/flash hatası ya da güç kesintisi/geri alma oldu
- Yeni imaj açıldı ama doğrulanamadan yeniden başladı (bootloader önceki imaja döndü): hak yandı

**Adım adım kontrol**
- Önce asıl hata nedenini bulun (cihaz-ota-indirme-basarisiz, cihaz-ota-sonrasi-geri-aldi)
- Düzelttikten sonra aynı sürüm için yeniden denemek: panelden/ota_check komutuyla retry:true gönderin ya da daha yüksek sürüm yayınlayın
- Seri "?" -> "OTA durum" satırında "deneme siniri asildi" görünür

**Günlükte aranacak ifadeler**
- `OTA: ayni surum icin deneme siniri asildi, daha yeni surum bekleniyor.`

**İlgili testler:** [cihaz_kontrol/host_test/t_mqtt.cpp](../../cihaz_kontrol/host_test/t_mqtt.cpp)

**Bkz.:** [cihaz-ota-indirme-basarisiz](#cihaz-ota-indirme-basarisiz), [cihaz-ota-sonrasi-geri-aldi](#cihaz-ota-sonrasi-geri-aldi), [cihaz-ota-guncelleme-baslamiyor](#cihaz-ota-guncelleme-baslamiyor)

<a id="cihaz-ota-sonrasi-geri-aldi"></a>
### cihaz-ota-sonrasi-geri-aldi · OTA "tamam" dedi ama cihaz eski sürüme döndü: seri "?" -> OTA durum "geri alindi: <sürüm> yuklenemedi"

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [cihaz_kontrol/include/ota_guncelleme.h:257](../../cihaz_kontrol/include/ota_guncelleme.h#L257) | <code>otaPersistStatus("geri alindi: " + gOtaLastVersion + " yuklenemedi");</code> | Açılışta "guncelleme tamam" kayıtlı ama çalışan sürüm hedef sürüm değilse geri alma kaydedilir |
| [cihaz_kontrol/include/ota_guncelleme.h:979](../../cihaz_kontrol/include/ota_guncelleme.h#L979) | <code>inline void otaGecerliligiDogrula(bool saglikli) {</code> | Wi-Fi + MQTT 60 sn kesintisiz sağlıklıysa imaj geçerli işaretlenir (esp_ota_mark_app_valid_cancel_rollback) |
| [cihaz_kontrol/include/ota_guncelleme.h:70](../../cihaz_kontrol/include/ota_guncelleme.h#L70) | <code>inline constexpr unsigned long OTA_SAGLIK_SURESI_MS = 60UL * 1000UL;  // Wi-Fi+MQTT bu su…</code> | Sağlık süresi 60 sn; bundan önce yeniden başlarsa bootloader eski imaja döner |
| [cihaz_kontrol/src/main.cpp:42](../../cihaz_kontrol/src/main.cpp#L42) | <code>extern "C" bool verifyRollbackLater() {</code> | true döner: Arduino çekirdeği yeni imajı kendiliğinden geçerli yapmaz; doğrulama otaGecerliligiDogrula ile yapılır |
| [cihaz_kontrol/src/main.cpp:511](../../cihaz_kontrol/src/main.cpp#L511) | <code>otaGecerliligiDogrula(wifiHazirMi() &amp;&amp; mqttBagliMi());</code> | Her döngüde sağlık bildirilir |
| [cihaz_kontrol/include/ota_guncelleme.h:236](../../cihaz_kontrol/include/ota_guncelleme.h#L236) | <code>inline bool otaCalisanImajPendingMi() {</code> | Açılışta çalışan imaj PENDING_VERIFY mi okunur |

**Olası nedenler**
- Yeni imaj Wi-Fi ya da MQTT bağlantısını 60 sn kesintisiz tutamadı (ör. kimlik/ağ sorunu) ve araya yeniden başlatma girdi
- Yeni imaj bozuk/çöküyor ya da watchdog yeniden başlatması yaptı (cihaz-watchdog-yeniden-basliyor)
- 6 saatlik MQTT kendini toparlama yeniden başlatması doğrulanmamış imajda geri dönüşü tetikledi (istenen davranış)
- Güç kesintisi doğrulama bitmeden oldu

**Adım adım kontrol**
- Seri "?" -> "Firmware Versiyon" ve "OTA durum": çalışan sürüm hedef sürümle aynı mı
- Açılış günlüğünde "OTA: calisan imaj dogrulanmadi (PENDING_VERIFY)" ve sonrasında "OTA: yeni imaj saglikli calisti, gecerli olarak isaretlendi" aranır
- Sunucuda "ota_validated" olayı gelmiş mi bakın; gelmediyse imaj doğrulanmamıştır
- WROOM: otadata bozuksa flash_wroom.bat otadata'yı sıfırlar (cihaz-wroom-usb-yukleme)

**Günlükte aranacak ifadeler**
- `OTA: yeni imaj saglikli calisti, gecerli olarak isaretlendi (rollback iptal).`
- `OTA: imaj gecerli isaretlenemedi!`

**İlgili testler:** [cihaz_kontrol/host_test/t_mqtt.cpp](../../cihaz_kontrol/host_test/t_mqtt.cpp)

**Bkz.:** [cihaz-ota-deneme-siniri-asildi](#cihaz-ota-deneme-siniri-asildi), [cihaz-mqtt-6-saat-yeniden-baslama](#cihaz-mqtt-6-saat-yeniden-baslama), [cihaz-watchdog-yeniden-basliyor](#cihaz-watchdog-yeniden-basliyor), [cihaz-ota-guncelleme-baslamiyor](#cihaz-ota-guncelleme-baslamiyor)

<a id="cihaz-ota-is-kimligi-yansimiyor"></a>
### cihaz-ota-is-kimligi-yansimiyor · Panelden toplu OTA işi başlatıldı ama sunucudaki iş kaydında cihaz OTA olayları işe bağlanmıyor (ota_job_id eksik)

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [cihaz_kontrol/include/ota_is_kimligi.h:36](../../cihaz_kontrol/include/ota_is_kimligi.h#L36) | <code>inline bool otaIsKimligiAyarla(JsonVariantConst v) {</code> | ota_check komutundaki ota_job_id okunur: 1-40 karakter ([A-Za-z0-9._:-]) metin ya da pozitif tamsayı; aksi halde GEÇERSİZ ve önceki kimlik silinir |
| [cihaz_kontrol/include/ota_is_kimligi.h:72](../../cihaz_kontrol/include/ota_is_kimligi.h#L72) | <code>inline bool otaOlayBitirirMi(const char* olayAdi) {</code> | Başarı/hata/güncel/usb/hedef uyuşmazlığı olayından sonra kimlik temizlenir |
| [cihaz_kontrol/include/ota_is_kimligi.h:81](../../cihaz_kontrol/include/ota_is_kimligi.h#L81) | <code>inline void otaIsKimligiEkle(JsonDocument&amp; doc) {</code> | Kimlik varsa olay JSON'una ota_job_id eklenir (tamsayı gelmişse tamsayı olarak) |
| [cihaz_kontrol/include/mqtt_baglanti.h:356](../../cihaz_kontrol/include/mqtt_baglanti.h#L356) | <code>otaIsKimligiAyarla(doc["ota_job_id"]);</code> | ota_check işleyicisi kimliği kaydeder |
| [cihaz_kontrol/include/mqtt_baglanti.h:151](../../cihaz_kontrol/include/mqtt_baglanti.h#L151) | <code>otaIsKimligiEkle(doc);  // OTA olaylari (ota_*): sunucudaki is takibi icin ota_job_id yan…</code> | Yalnız adı "ota_" ile başlayan olaylara eklenir |
| [cihaz_kontrol/include/ota_guncelleme.h:220](../../cihaz_kontrol/include/ota_guncelleme.h#L220) | <code>if (otaOlayBitirirMi(eventName)) {</code> | OTA olayı yayınlandıktan sonra kimlik temizleme |

**Olası nedenler**
- ota_job_id geçersiz karakter içeriyor, 40 karakterden uzun, sıfır/negatif ya da sayı/metin değil: cihaz kimliği yok sayar
- Dize komutu ("ota" / "ota_check") iş kimliği taşımaz; önceki kimlik bilerek temizlenir
- Kimlik yalnız RAM'dedir: ota_success olayı yeniden başlatmadan ÖNCE yayınlanır; cihaz araya girerek yeniden başlarsa kimlik kaybolur
- MQTT oturumu OTA indirmesi için kapatıldı; olay bağlantı yeniden kurulunca yayınlanır (geç gelebilir)

**Adım adım kontrol**
- Panelin gönderdiği ota_check JSON'unda ota_job_id alanını doğrulayın (sunucu tarafı bu alanın dışında)
- Cihazdan gelen device/<UID>/event olaylarında ota_job_id alanı var mı bakın
- Kimlik yoksa sunucu son 6 saatteki işi varsayar (ota_guncelleme/ota_is_kimligi.h başlık yorumu)

**İlgili testler:** [cihaz_kontrol/host_test/t_mqtt.cpp](../../cihaz_kontrol/host_test/t_mqtt.cpp)

**Bkz.:** [cihaz-ota-guncelleme-baslamiyor](#cihaz-ota-guncelleme-baslamiyor), [cihaz-ota-sonrasi-geri-aldi](#cihaz-ota-sonrasi-geri-aldi)

<a id="cihaz-offline-log-senkronize-olmuyor"></a>
### cihaz-offline-log-senkronize-olmuyor · Cihaz internetsizken açılan kapı geçişleri sunucuda/uygulama günlüğünde görünmüyor; seri günlükte "batch yayinlanamadi" ya da hiç "ack" yok

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [cihaz_kontrol/include/offline_log.h:407](../../cihaz_kontrol/include/offline_log.h#L407) | <code>inline void offlineLogSenkronizeEt() {</code> | 3 sn'de bir: bekleyen kayıt + Wi-Fi + MQTT bağlıysa dosyanın başından batch yayınlar; ack gelmezse aralık katlanarak tekrar yayınlar |
| [cihaz_kontrol/include/offline_log.h:305](../../cihaz_kontrol/include/offline_log.h#L305) | <code>inline bool offlineLogBatchHazirla(uint32_t batchId, String&amp; payload, size_t&amp; satir) {</code> | device/<uid>/logs konusuna {batch_id, logs[]} (tek yayın <= 900 bayt) hazırlanır; bozuk/uzun satır atlanır |
| [cihaz_kontrol/include/offline_log.h:375](../../cihaz_kontrol/include/offline_log.h#L375) | <code>inline bool offlineLogAckIsle(uint32_t batchId) {</code> | Yerel kayıtlar YALNIZ sunucunun logs_ack komutuyla silinir; batch_id eşleşmezse ack yok sayılır |
| [cihaz_kontrol/include/mqtt_baglanti.h:386](../../cihaz_kontrol/include/mqtt_baglanti.h#L386) | <code>} else if (action == "logs_ack") {</code> | logs_ack komutu burada cihaza ulaşır |
| [cihaz_kontrol/include/offline_log.h:35](../../cihaz_kontrol/include/offline_log.h#L35) | <code>inline constexpr unsigned long OFFLINE_LOG_ACK_TIMEOUT_MAX_MS = 600000;</code> | Ack bekleme süresi 15 sn'den başlayıp 10 dk'ya kadar katlanır |
| [cihaz_kontrol/include/offline_log.h:299](../../cihaz_kontrol/include/offline_log.h#L299) | <code>inline void offlineLogMqttBaglandi() {</code> | MQTT yeniden bağlanınca bekleyen batch serbest bırakılır, hemen yeniden gönderilir |
| [cihaz_kontrol/include/offline_log.h:147](../../cihaz_kontrol/include/offline_log.h#L147) | <code>inline const char* offlineLogTurSecimi(const char* tur) {</code> | trigger_type sunucu izin listesinde değilse "offline_sync"e çevrilir (aksi halde sunucu reddedip ack'ler = veri kaybı) |

**Olası nedenler**
- MQTT bağlı değil ya da LittleFS başlatılamadı (gOfflineLogFsHazir false): senkron hiç denenmez
- Sunucu batch'i aldı ama logs_ack komutu cihaza ulaşmadı: cihaz aynı kayıtları tekrar yayınlar (sunucu idempotent, mükerrer yazmaz)
- Batch yayını başarısız ("MQTT publish basarisiz"): cihaz-mqtt-yayin-basarisiz
- Sunucu kaydı reddediyor (bilinmeyen trigger_type, desen dışı client_log_id): sunucu tarafı için sunucu-offline-log-senkronu-hata
- Saat senkron değilken yazılan kayıtlarda epoch=0 olur; saat gelince aynı açılışın kayıtları gönderimde düzeltilir

**Adım adım kontrol**
- Seri günlükte "Offline Log: batch yayinlandi, ack bekleniyor (satir=N)" ve ardından "batch sunucu tarafindan onaylandi, yerel kayitlar silindi." çifti görülmeli
- Yalnız "yayinlandi" var, "onaylandi" yok: sunucu/ack yolu (sunucu-offline-log-senkronu-hata, altyapi-offline-log-alimi)
- Açılış günlüğünde "Offline Log Sistemi: LittleFS baslatildi." var mı

**Günlükte aranacak ifadeler**
- `Offline Log: batch yayinlandi, ack bekleniyor (satir=`
- `Offline Log: batch sunucu tarafindan onaylandi, yerel kayitlar silindi.`
- `Offline Log: batch yayinlanamadi (MQTT).`
- `Offline Log Sistemi: LittleFS baslatildi.`

**İlgili testler:** [cihaz_kontrol/host_test/t_mqtt.cpp](../../cihaz_kontrol/host_test/t_mqtt.cpp)

**Bkz.:** [cihaz-offline-log-dosya-sorunu](#cihaz-offline-log-dosya-sorunu), [cihaz-mqtt-yayin-basarisiz](#cihaz-mqtt-yayin-basarisiz), [sunucu-offline-log-senkronu-hata](10-sunucu-api.md#sunucu-offline-log-senkronu-hata), [altyapi-offline-log-alimi](20-sunucu-altyapi-ve-yayin.md#altyapi-offline-log-alimi)

<a id="cihaz-offline-log-dosya-sorunu"></a>
### cihaz-offline-log-dosya-sorunu · Cihazda çevrimdışı kayıtlar kayboluyor ya da seri günlükte "Offline Log: dosya doldu" / "Dosya yazma hatasi" / "LittleFS mount basarisiz" görülüyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [cihaz_kontrol/include/offline_log.h:246](../../cihaz_kontrol/include/offline_log.h#L246) | <code>inline void offlineLogInit() {</code> | LittleFS açılır; mount başarısızsa FORMATLANIR (eski kayıtlar silinir); bootId rastgele bileşenle üretilir |
| [cihaz_kontrol/include/offline_log.h:163](../../cihaz_kontrol/include/offline_log.h#L163) | <code>inline void offlineLogEkle(</code> | Kaydı NDJSON dosyasına ekler; dosya 16 KB'ı aşarsa en eski kayıtlar atılır (12 KB hedef) |
| [cihaz_kontrol/include/offline_log.h:30](../../cihaz_kontrol/include/offline_log.h#L30) | <code>inline constexpr size_t OFFLINE_LOG_MAX_FILE_SIZE = 16 * 1024;     // asilirsa en eski ka…</code> | Dosya sınırı; aşılınca tüm dosya silinmez, yalnız en eski satırlar atılır |
| [cihaz_kontrol/include/offline_log.h:75](../../cihaz_kontrol/include/offline_log.h#L75) | <code>inline bool offlineLogDosyayiYenile(size_t atlanacakSatir, size_t baytAtla) {</code> | Geçici dosya + rename ile atomik yeniden yazım (güç kesintisine dayanıklı) |
| [cihaz_kontrol/partitions_ota_4mb.csv:6](../../cihaz_kontrol/partitions_ota_4mb.csv#L6) | <code>spiffs,   data, spiffs,  0x3D0000,0x20000,</code> | LittleFS bölümü yalnız 128 KB (0x20000); bölüm tablosu değişirse kayıtlar etkilenir |

**Olası nedenler**
- İnternet çok uzun süre yok: en eski kayıtlar bilerek atılır ("dosya doldu"); sunucuya hiç ulaşmayan kayıtlar kaybolur
- Flash bölümü bozuk ya da bölüm tablosu değişti: LittleFS mount hatası, otomatik format
- Kayıt eksik yazıldı (flash dolu): "Kayit eksik yazildi"
- Güç kesilmesi: yarım kalan geçici dosya açılışta ya geri alınır ya da silinir

**Adım adım kontrol**
- Açılış günlüğünde "Offline Log Sistemi: ..." satırını okuyun (baslatildi | formatlaniyor | baslatilamadi)
- Kapı geçişinden sonra "Offline Log: kapi gecisi kaydedildi." görülüyor mu
- Bölüm tablosunu OTA ile değiştirmeyin; USB ile tam yükleme gerekirse eski kayıtlar silinebilir

**Günlükte aranacak ifadeler**
- `Offline Log: dosya doldu, en eski kayitlar atildi.`
- `Offline Log: Dosya yazma hatasi!`
- `Offline Log Sistemi: LittleFS mount basarisiz, formatlaniyor...`
- `Offline Log: kapi gecisi kaydedildi.`

**Bkz.:** [cihaz-offline-log-senkronize-olmuyor](#cihaz-offline-log-senkronize-olmuyor)

<a id="cihaz-watchdog-yeniden-basliyor"></a>
### cihaz-watchdog-yeniden-basliyor · Cihaz kendiliğinden yeniden başlıyor (seri günlükte yeniden başlatma, "Task watchdog"); özellikle OTA ya da MQTT/TLS bağlanırken

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [cihaz_kontrol/src/main.cpp:38](../../cihaz_kontrol/src/main.cpp#L38) | <code>constexpr uint32_t LOOP_WDT_TIMEOUT_S = 30;</code> | Döngü 30 sn içinde watchdog'u beslemezse cihaz yeniden başlar |
| [cihaz_kontrol/src/main.cpp:449](../../cihaz_kontrol/src/main.cpp#L449) | <code>esp_task_wdt_init(LOOP_WDT_TIMEOUT_S, true);</code> | setup'ta loop görevi izlemeye alınır (panic=true) |
| [cihaz_kontrol/src/main.cpp:493](../../cihaz_kontrol/src/main.cpp#L493) | <code>void loop() {</code> | Her turun başında esp_task_wdt_reset(); uzun işler kendi içinde besler |
| [cihaz_kontrol/include/mqtt_baglanti.h:464](../../cihaz_kontrol/include/mqtt_baglanti.h#L464) | <code>const bool baglandi = client.connect(clientId.c_str(), mqttUser.c_str(), mqttPass.c_str()…</code> | Bloklayan MQTT connect (DNS+TCP+TLS, 5-15 sn) öncesi ve sonrası watchdog resetlenir |
| [cihaz_kontrol/include/ota_guncelleme.h:449](../../cihaz_kontrol/include/ota_guncelleme.h#L449) | <code>size_t write(const uint8_t* buf, size_t size) override {</code> | OTA indirmesinde her blokta watchdog beslenir |
| [cihaz_kontrol/src/main.cpp:65](../../cihaz_kontrol/src/main.cpp#L65) | <code>void pinBulmaTesti() {</code> | Atölye pin testi döngüyü bloklar; her adımda watchdog beslenir |

**Olası nedenler**
- Bloklayan bir işin watchdog beslemeden 30 sn'yi aşması (DNS/TLS/TCP zaman aşımları, yeni eklenen uzun işlem)
- Bellek (heap) yetersizliği ya da çökme (ikinci TLS oturumu, büyük JSON)
- Yetersiz/dalgalı güç kaynağı (röle çekerken voltaj düşmesi) nedeniyle brown-out yeniden başlatması
- MQTT 6 saat bağlanamayınca bilinçli kontrollü yeniden başlatma (cihaz-mqtt-6-saat-yeniden-baslama) ve doğrulanmamış imajda geri alma (cihaz-ota-sonrasi-geri-aldi)

**Adım adım kontrol**
- Seri monitörde yeniden başlatma nedenini (reset reason / panic dökümü) yakalayın; WROOM/C3'te coredump bölümü bu amaçla ayrılmıştır (partitions_ota_4mb.csv)
- Yeniden başlatmadan hemen önceki son günlük satırına bakın: hangi iş sürüyordu (OTA, MQTT bağlanma, pin bulma)
- Röle çekerken yeniden başlatma oluyorsa güç beslemesini ölçün (yazılım nedeni değildir)
- Yeniden başlatma röle pulse'u üretmez: roleSetup setup'ın ilk satırıdır

**Günlükte aranacak ifadeler**
- `DONANIM SELF-TEST BASLATILIYOR`

**Bkz.:** [cihaz-mqtt-6-saat-yeniden-baslama](#cihaz-mqtt-6-saat-yeniden-baslama), [cihaz-ota-sonrasi-geri-aldi](#cihaz-ota-sonrasi-geri-aldi), [cihaz-role-acilista-tiklamasi](#cihaz-role-acilista-tiklamasi)

<a id="cihaz-gm60-baglanti-yok"></a>
### cihaz-gm60-baglanti-yok · QR okuyucu (kamera) ışık yakmıyor/bip yapmıyor; seri "?" -> "Kamera / QR Okuyucu: Bagli Degil", açılışta "UYARI (Kamera yanit vermedi"

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [cihaz_kontrol/include/gm60_scanner.h:131](../../cihaz_kontrol/include/gm60_scanner.h#L131) | <code>inline bool gm60SelfTest(bool seriYazdir = false) {</code> | Işık aç komutunu gönderip 250 ms içinde herhangi bir bayt yanıtı bekler; yanıt yoksa gm60Bagli=false |
| [cihaz_kontrol/include/gm60_scanner.h:188](../../cihaz_kontrol/include/gm60_scanner.h#L188) | <code>inline void gm60Setup() {</code> | WROOM: UART2 (RX25/TX26, 9600 baud); C3: UART1 (RX20/TX21) |
| [cihaz_kontrol/include/device_konfig.h:21](../../cihaz_kontrol/include/device_konfig.h#L21) | <code>constexpr int GM60_RX_PIN = 25;</code> | WROOM GM60 pinleri (GPIO16 röledir, GM60 buraya bağlanamaz) |
| [cihaz_kontrol/include/device_konfig.h:36](../../cihaz_kontrol/include/device_konfig.h#L36) | <code>inline int GM60_RX_PIN = 20;</code> | C3 GM60 pinleri (UART1 RX 20, TX 21); C3'te GM60 pini negatifse okuyucu hiç başlatılmaz |
| [cihaz_kontrol/src/main.cpp:478](../../cihaz_kontrol/src/main.cpp#L478) | <code>const bool kameraOk = gm60SelfTest(false);</code> | Açılış self-testi: yalnız uyarı basar, açılışı durdurmaz |
| [cihaz_kontrol/src/main.cpp:183](../../cihaz_kontrol/src/main.cpp#L183) | <code>gm60SelfTestManuel();</code> | Seri "k" komutu kamera testini elle çalıştırır |
| [cihaz_kontrol/include/gm60_scanner.h:73](../../cihaz_kontrol/include/gm60_scanner.h#L73) | <code>inline bool gm60Probe(int rx, int tx, uint32_t baud) {</code> | Pin/baud deneme yardımcısı (ışık + sorgu komutlarıyla yanıt arar) |

**Olası nedenler**
- GM60 TX/RX hatları ters ya da gevşek; besleme yok
- Okuyucu farklı baud hızında (varsayılan 9600)
- Atölye pin bulma testi sonrası UART pinleri GPIO'ya çevrilmiş (test sonunda gm60Setup yeniden bağlar)
- Okuyucu yalnız barkod okur ama komutlara yanıt vermiyor (bazı firmware varyantları): gm60Bagli ilk gerçek okumada true olur

**Adım adım kontrol**
- Seri "k" yazın: "[GM60 TEST] Kamera Durumu: BAGLI (Hazir)" ya da "BAGLI DEGIL (Yanit Yok)"
- Okuyucunun besleme/UART kablolarını ve pinleri (device_konfig.h) karşılaştırın
- Bir QR okutun: "[GM60] QR okundu, uzunluk: N" satırı geliyorsa okuyucu çalışıyordur (gm60Bagli true olur)

**Günlükte aranacak ifadeler**
- `[GM60 TEST] Kamera Durumu: `
- `GM60 QR Okuyucu baslatildi (UART2 RX:`
- `UYARI (Kamera yanit vermedi - baglanti/pinleri kontrol edin)`

**İlgili testler:** [cihaz_kontrol/host_test/t_gm60.cpp](../../cihaz_kontrol/host_test/t_gm60.cpp)

**Bkz.:** [cihaz-qr-okundu-kapi-acilmiyor](#cihaz-qr-okundu-kapi-acilmiyor), [cihaz-seri-atolye-komutlari](#cihaz-seri-atolye-komutlari)

<a id="cihaz-qr-okundu-kapi-acilmiyor"></a>
### cihaz-qr-okundu-kapi-acilmiyor · QR okutuluyor ("[GM60] QR okundu") ama kapı açılmıyor ya da ekranda "reddedildi": "Sunucu yaniti bekleniyor", "Debounce", "Ayni token ... atlaniyor"

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [cihaz_kontrol/include/gm60_scanner.h:206](../../cihaz_kontrol/include/gm60_scanner.h#L206) | <code>inline void gm60QrVerisiniIsle(String qrData) {</code> | Tek okumanın tüm akışı: temizleme, 3 koruma, MQTT qr_verify gönderimi |
| [cihaz_kontrol/include/gm60_scanner.h:46](../../cihaz_kontrol/include/gm60_scanner.h#L46) | <code>constexpr unsigned long GM60_SUNUCU_YANITLAMA_TIMEOUT_MS = 10000UL; // 10 saniye</code> | KORUMA 1: qr_verify sonrası sunucu yanıtı gelene ya da 10 sn dolana kadar yeni okuma işlenmez |
| [cihaz_kontrol/include/gm60_scanner.h:242](../../cihaz_kontrol/include/gm60_scanner.h#L242) | <code>if (gm60SonOkumaMs != 0 &amp;&amp; millis() - gm60SonOkumaMs &lt; 5000) {</code> | KORUMA 2: son başarılı yayından sonra 5 sn debounce |
| [cihaz_kontrol/include/gm60_scanner.h:35](../../cihaz_kontrol/include/gm60_scanner.h#L35) | <code>constexpr unsigned long GM60_TOKEN_TEKRAR_SURESI_MS = 8000UL; // 8 saniye</code> | KORUMA 3: aynı token 8 sn içinde tekrar gönderilmez (sunucu reddi/hata sonrası token unutulur) |
| [cihaz_kontrol/include/gm60_scanner.h:62](../../cihaz_kontrol/include/gm60_scanner.h#L62) | <code>inline bool gm60SunucuYanitiKabulEt(bool idVar, uint32_t id) {</code> | qr_result, bekleyen request_id ile eşleşmezse (geç/eski) yok sayılır |
| [cihaz_kontrol/include/mqtt_baglanti.h:278](../../cihaz_kontrol/include/mqtt_baglanti.h#L278) | <code>inline void mqttHandleQrResult(const String&amp; message) {</code> | Sunucu sonucu: allowed=false ise ekrana QR_DENIED; true ise kapı pulse'u ayrıca gelir |
| [cihaz_kontrol/include/mqtt_baglanti.h:173](../../cihaz_kontrol/include/mqtt_baglanti.h#L173) | <code>inline bool mqttPublishQrVerify(const String&amp; qrToken, uint32_t requestId) {</code> | qr_verify yayını: {token, timestamp, request_id} |
| [cihaz_kontrol/include/mqtt_baglanti.h:247](../../cihaz_kontrol/include/mqtt_baglanti.h#L247) | <code>inline void mqttHandlePulse(JsonDocument&amp; json) {</code> | Onaylanan QR'ın kapı açma pulse'u bu işleyiciden röleye gider |

**Olası nedenler**
- Önceki qr_verify yanıtı henüz gelmedi (10 sn bekleme) ya da 5 sn debounce sürüyor: okuma bilerek atlanır
- Aynı QR kabulden sonra 8 sn içinde tekrar okutuldu
- Sunucu reddetti (süresi dolmuş, geçersiz, yetkisiz QR): seri "[MQTT QR Sonuc] Izin: REDDEDILDI | Neden: ..." (sunucu tarafı: sunucu-tarama-qr-ekran-token ve ilgili girişler)
- qr_result cihaza dönmedi (ACL/abonelik): altyapi-qr-sonuc-cihaza-donmuyor
- Kabul geldi ama pulse reddedildi (stale / role_busy): cihaz-mqtt-pulse-reddedildi
- QR 512 karakterden uzun: tampon taştı, okuma REDDEDİLİR (kırpılmaz)

**Adım adım kontrol**
- Seri günlükte sırayla: "[GM60] QR okundu, uzunluk" -> "QR token sunucuya iletiliyor" -> "[MQTT QR Sonuc] Izin: ..." -> "MQTT pulse" / "Role tetiklendi"
- QR içeriği seriye YAZILMAZ; yalnız uzunluk görünür
- Hangi aşamada kesildiğine göre ilgili girişe geçin (offline: cihaz-qr-offline-acilmiyor)

**Günlükte aranacak ifadeler**
- `[GM60] QR okundu, uzunluk: `
- `[GM60] Sunucu yaniti bekleniyor (`
- `[GM60] Debounce suresi dolmadi, atlaniyor.`
- `[GM60 HATA] QR sunucuya iletilemedi.`
- `[MQTT QR Sonuc] eslesmeyen/eski sonuc yok sayildi.`
- `[GM60] QR cok uzun (tampon tasti), okuma reddedildi.`

**İlgili testler:** [cihaz_kontrol/host_test/t_gm60.cpp](../../cihaz_kontrol/host_test/t_gm60.cpp)

**Bkz.:** [cihaz-qr-offline-acilmiyor](#cihaz-qr-offline-acilmiyor), [cihaz-gm60-baglanti-yok](#cihaz-gm60-baglanti-yok), [cihaz-mqtt-pulse-reddedildi](#cihaz-mqtt-pulse-reddedildi), [altyapi-qr-sonuc-cihaza-donmuyor](20-sunucu-altyapi-ve-yayin.md#altyapi-qr-sonuc-cihaza-donmuyor), [akis-dinamik-qr-gm60](60-akislar.md#akis-dinamik-qr-gm60)

<a id="cihaz-qr-offline-acilmiyor"></a>
### cihaz-qr-offline-acilmiyor · İnternet/MQTT yokken QR okutulunca kapı açılmıyor; seri "[GM60 UYARI] MQTT baglantisi yok! Dinamik QR offline modda acilamaz."

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [cihaz_kontrol/include/gm60_scanner.h:291](../../cihaz_kontrol/include/gm60_scanner.h#L291) | <code>// Guvenlik: Dinamik tokenler (QR:...) sunucu tarafinda dogrulanmak ZORUNDADIR.</code> | TASARIM GEREĞİ: MQTT yokken QR ile kapı açılmaz; cihaz güvenli şekilde kapalı kalır |
| [cihaz_kontrol/include/gm60_scanner.h:263](../../cihaz_kontrol/include/gm60_scanner.h#L263) | <code>if (mqttBagliMi()) {</code> | Yalnız MQTT bağlıysa qr_verify yayınlanır; değilse ekrana QR_DENIED gider |
| [cihaz_kontrol/include/qr_dogrulama.h:14](../../cihaz_kontrol/include/qr_dogrulama.h#L14) | <code>inline bool qrKoduGecerliMi(const String&amp; rawData, String&amp; outReason) {</code> | ÖLÜ KOD: hiçbir yerden çağrılmaz; yerel QR kuralları güvenli DEĞİLDİR, kapı kararı için kullanılmamalı |
| [cihaz_kontrol/include/yerel_kapi_kontrol.h:385](../../cihaz_kontrol/include/yerel_kapi_kontrol.h#L385) | <code>inline void yerelUdpAcmaIsle(JsonDocument&amp; doc, const String&amp; action, const String&amp; benim…</code> | İnternet yokken kapı açmanın doğru yolu: uygulamadan yerel UDP (HMAC imzalı), QR değil |

**Olası nedenler**
- Cihaz çevrimdışı (internet, Wi-Fi, MQTT kimliği ya da broker sorunu): cihaz-mqtt-rc-hatasi, cihaz-wifi-baglanmiyor
- QR doğrulaması yalnız sunucuda yapılır; qr_dogrulama.h kullanılmayan eski koddur (değiştirmek güvenlik açığı doğurur)

**Adım adım kontrol**
- Seri "?" -> "MQTT: bagli" değil ise önce bağlantıyı onarın
- Acil durumda kapıyı uygulamadan yerel ağ yoluyla (UDP) açın: cihaz-yerel-udp-cevap-yok
- qr_dogrulama.h dosyasını include etmeyin; hiçbir akışta kullanılmıyor

**Günlükte aranacak ifadeler**
- `[GM60 UYARI] MQTT baglantisi yok! Dinamik QR offline modda acilamaz.`

**İlgili testler:** [cihaz_kontrol/host_test/t_gm60.cpp](../../cihaz_kontrol/host_test/t_gm60.cpp)

**Bkz.:** [cihaz-qr-okundu-kapi-acilmiyor](#cihaz-qr-okundu-kapi-acilmiyor), [cihaz-mqtt-rc-hatasi](#cihaz-mqtt-rc-hatasi), [cihaz-yerel-udp-cevap-yok](#cihaz-yerel-udp-cevap-yok)

<a id="cihaz-role-acmiyor"></a>
### cihaz-role-acmiyor · Komut/QR kabul edildi ama röle çekmiyor ya da kapı kilidi açılmıyor; seri "Role debounce: Role zaten aktif ..." ya da pin okuması beklenenden farklı

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [cihaz_kontrol/include/role_kontrol.h:124](../../cihaz_kontrol/include/role_kontrol.h#L124) | <code>inline bool roleTetikle() {</code> | Röleyi çeker: zaten aktifse ya da son tetikten 2,5 sn geçmediyse false döner (debounce) |
| [cihaz_kontrol/include/role_kontrol.h:11](../../cihaz_kontrol/include/role_kontrol.h#L11) | <code>constexpr uint8_t ROLE_PIN = 16;</code> | WROOM röle pini GPIO16 (opto-yalıtımlı kart) |
| [cihaz_kontrol/include/role_kontrol.h:15](../../cihaz_kontrol/include/role_kontrol.h#L15) | <code>constexpr uint8_t ROLE_PIN = 10;</code> | C3 röle pini GPIO10 |
| [cihaz_kontrol/include/role_kontrol.h:13](../../cihaz_kontrol/include/role_kontrol.h#L13) | <code>constexpr bool ROLE_ACTIVE_LOW = false;</code> | Aktif seviye: HIGH (iki hedefte de ters mantık YOK); röle kartı ters ise burası değişirdi |
| [cihaz_kontrol/include/role_kontrol.h:12](../../cihaz_kontrol/include/role_kontrol.h#L12) | <code>constexpr unsigned long ROLE_SURE_MS = 1500;</code> | Normal darbe süresi 1500 ms |
| [cihaz_kontrol/include/role_kontrol.h:46](../../cihaz_kontrol/include/role_kontrol.h#L46) | <code>inline void roleBirak() {</code> | Bırakma esp_timer görevinde yapılır (loop kilitlense bile röle bırakılır) |
| [cihaz_kontrol/include/role_kontrol.h:159](../../cihaz_kontrol/include/role_kontrol.h#L159) | <code>inline bool roleLoop() {</code> | Yedek bırakma yolu ve "bırakıldı" bildirimi (gDoorLocked, ekran, MQTT durum) döngüden verilir |
| [cihaz_kontrol/src/main.cpp:497](../../cihaz_kontrol/src/main.cpp#L497) | <code>if (roleLoop()) {</code> | Röle bırakılınca kapı "kilitli" durumu yayınlanır |

**Olası nedenler**
- Debounce: ikinci tetik aynı darbe içinde/2,5 sn içinde geldi (pulse_rejected: role_busy)
- Röle kartı/besleme ya da kapı kilidi donanım arızası: GPIO seviyesi doğru ama kilit çekmiyor
- Yanlış pin ya da yanlış hedef firmware (C3 firmware'i WROOM kartına yüklenmiş: röle GPIO10'da, kart GPIO16'da)
- Atölye modunda seri "h" ile röle HIGH tutuluyor (60 sn sonra otomatik bırakılır); tutma sırasında yeni pulse reddedilir

**Adım adım kontrol**
- Seri "r" gönderin: "Role tetiklendi GPIO N -> HIGH" ve "Role birak okuma" satırlarında pin okumasına bakın
- Seri "?" -> "Role GPIO" ve "Hardware Target" donanımla uyuşuyor mu
- Röle kartındaki LED/klik sesi ile pin okumasını karşılaştırın
- ESP32-C3 sahada çalışıyor: pin/darbe süresini DEĞİŞTİRMEYİN (AGENTS.md kural 3-4)

**Günlükte aranacak ifadeler**
- `Role tetiklendi GPIO `
- `Role debounce: Role zaten aktif veya son tetikten bu yana 2.5s gecmedi.`
- `Role birakildi GPIO `
- `Seri komut: role pulse`

**İlgili testler:** [cihaz_kontrol/host_test/t_mqtt.cpp](../../cihaz_kontrol/host_test/t_mqtt.cpp)

**Bkz.:** [cihaz-mqtt-pulse-reddedildi](#cihaz-mqtt-pulse-reddedildi), [cihaz-role-acilista-tiklamasi](#cihaz-role-acilista-tiklamasi), [cihaz-seri-atolye-komutlari](#cihaz-seri-atolye-komutlari), [altyapi-komut-yayini-roleyi-calistirmiyor](20-sunucu-altyapi-ve-yayin.md#altyapi-komut-yayini-roleyi-calistirmiyor)

<a id="cihaz-role-acilista-tiklamasi"></a>
### cihaz-role-acilista-tiklamasi · Cihaz açılırken/yeniden başlarken röle tıklıyor ya da kapı kısa süre açılıyor mu şüphesi

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [cihaz_kontrol/include/role_kontrol.h:61](../../cihaz_kontrol/include/role_kontrol.h#L61) | <code>inline void roleSetup() {</code> | Pin önce pasif seviyeye çekilir, sonra çıkış yapılır (açılışta röle tıklamasın) |
| [cihaz_kontrol/src/main.cpp:432](../../cihaz_kontrol/src/main.cpp#L432) | <code>roleSetup();</code> | setup()'ın İLK satırı; Wi-Fi/MQTT/OTA gibi bloklayan işlerden önce çalışır |
| [cihaz_kontrol/src/main.cpp:473](../../cihaz_kontrol/src/main.cpp#L473) | <code>// (Role cek-birak testi KALDIRILDI: acilista kapi/role istenmeden tetiklenmemeli.)</code> | Açılış self-testinde röle çek-bırak testi bilerek kaldırıldı |
| [cihaz_kontrol/include/role_kontrol.h:78](../../cihaz_kontrol/include/role_kontrol.h#L78) | <code>inline void roleSetupLogYaz() {</code> | Açılışta röle boş durum seviyesini yazar |

**Olası nedenler**
- Güç kesilip gelmesi/brown-out sırasında kart donanımının GPIO'yu kısa süre tanımsız bırakması (yazılım dışı; açılışta GPIO seviyesine bakın)
- Önyükleme sırasında bazı GPIO'lar ESP32 tarafından geçici durumda olabilir (kart tasarımı)

**Adım adım kontrol**
- Seri açılış günlüğünde "Role bos durum GPIO N -> LOW" ve "Role setup okuma" satırlarını doğrulayın
- Yeniden başlatma röle pulse'u üretmez: kendini toparlama ya da watchdog yeniden başlatmasında kapı açılmaz
- ESP32-C3/WROOM sahada çalışıyor: setup sırasını DEĞİŞTİRMEYİN

**Günlükte aranacak ifadeler**
- `Role bos durum GPIO `
- `Role setup okuma`

**Bkz.:** [cihaz-role-acmiyor](#cihaz-role-acmiyor), [cihaz-watchdog-yeniden-basliyor](#cihaz-watchdog-yeniden-basliyor)

<a id="cihaz-mqtt-pulse-reddedildi"></a>
### cihaz-mqtt-pulse-reddedildi · Panel/uygulamadan kapı açma komutu gönderildi ama cihaz açmadı; sunucuda "pulse_rejected" olayı (stale ya da role_busy)

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [cihaz_kontrol/include/mqtt_baglanti.h:247](../../cihaz_kontrol/include/mqtt_baglanti.h#L247) | <code>inline void mqttHandlePulse(JsonDocument&amp; json) {</code> | pulse komutu: requested_at penceresi, tekrar (request_id) ve röle kontrolü sırayla yapılır |
| [cihaz_kontrol/include/mqtt_baglanti.h:39](../../cihaz_kontrol/include/mqtt_baglanti.h#L39) | <code>inline constexpr int64_t MQTT_PULSE_MAX_YAS_S = 60;                            // &#124;now - …</code> | \|şimdi - requested_at\| 60 sn'yi aşarsa komut "stale" ile reddedilir (yalnız cihaz saati senkronsa) |
| [cihaz_kontrol/include/mqtt_baglanti.h:257](../../cihaz_kontrol/include/mqtt_baglanti.h#L257) | <code>mqttPublishEvent("pulse_rejected", "stale", rid);</code> | Eski/ileri tarihli komut: sunucu ile cihaz saati arasında fark ya da gecikmiş teslim |
| [cihaz_kontrol/include/mqtt_baglanti.h:268](../../cihaz_kontrol/include/mqtt_baglanti.h#L268) | <code>mqttPublishEvent("pulse_rejected", "role_busy", rid);</code> | Röle aktif ya da debounce süresinde |
| [cihaz_kontrol/include/mqtt_baglanti.h:231](../../cihaz_kontrol/include/mqtt_baglanti.h#L231) | <code>inline bool mqttPulseIdTekrarMi(const char* id) {</code> | Aynı request_id yakın zamanda işlendiyse (QoS1 tekrar teslimi) yok sayılır, olay yayınlanmaz |
| [cihaz_kontrol/include/mqtt_baglanti.h:209](../../cihaz_kontrol/include/mqtt_baglanti.h#L209) | <code>inline int64_t mqttReadRequestedAt(JsonVariantConst v) {</code> | requested_at sayı değilse "yok" sayılır ve komut geriye uyum için KABUL edilir |

**Olası nedenler**
- Komut gecikmeli ulaştı (cihaz çevrimdışıydı, QoS1 teslim) ve requested_at 60 sn'den eski
- Cihaz saati yanlış (NTP) ya da sunucu saati kaymış
- Röle zaten aktif: ikinci pulse reddedilir (role_busy)
- Aynı request_id ikinci kez geldi: yok sayıldı (kapı zaten açıldı)

**Adım adım kontrol**
- Sunucu olay kaydında detail alanına bakın: "stale" mı "role_busy" mi
- Seri günlükte "MQTT pulse REDDEDILDI: requested_at zaman penceresi disinda." satırı aranır
- Cihaz saatinin senkron olduğundan emin olun (cihaz-saat-ntp-yok)

**Günlükte aranacak ifadeler**
- `MQTT pulse REDDEDILDI: requested_at zaman penceresi disinda.`
- `MQTT pulse yok sayildi: ayni request_id tekrar geldi.`

**İlgili testler:** [cihaz_kontrol/host_test/t_mqtt.cpp](../../cihaz_kontrol/host_test/t_mqtt.cpp)

**Bkz.:** [cihaz-role-acmiyor](#cihaz-role-acmiyor), [cihaz-saat-ntp-yok](#cihaz-saat-ntp-yok), [sunucu-kapi-acma-cihaz-offline](10-sunucu-api.md#sunucu-kapi-acma-cihaz-offline)

<a id="cihaz-yerel-udp-cevap-yok"></a>
### cihaz-yerel-udp-cevap-yok · Uygulama yerel ağdan (UDP) cihazı bulamıyor ya da kapıyı açamıyor; cihaz discover/open paketine hiç cevap vermiyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [cihaz_kontrol/include/yerel_kapi_kontrol.h:451](../../cihaz_kontrol/include/yerel_kapi_kontrol.h#L451) | <code>inline void yerelUdpIsle() {</code> | UDP paketini okur: >=512 bayt, JSON olmayan ya da yerel olmayan kaynak adres SESSİZCE yok sayılır |
| [cihaz_kontrol/include/yerel_kapi_kontrol.h:122](../../cihaz_kontrol/include/yerel_kapi_kontrol.h#L122) | <code>inline bool yerelAdresIzinli(const IPAddress&amp; ip) {</code> | Yalnız 10.x, 172.16-31.x, 192.168.x, 169.254.x ya da cihazla aynı alt ağdan gelen paket kabul edilir |
| [cihaz_kontrol/include/yerel_kapi_kontrol.h:488](../../cihaz_kontrol/include/yerel_kapi_kontrol.h#L488) | <code>if (action == "discover") {</code> | discover: hedef UID boş, "*" ya da cihaz UID'siyle eşleşirse cevap (ip, port, ch, local_control_available) verilir |
| [cihaz_kontrol/include/yerel_kapi_kontrol.h:272](../../cihaz_kontrol/include/yerel_kapi_kontrol.h#L272) | <code>inline void yerelKapiKontrolBaslat() {</code> | UDP 8765 soketi ve mDNS yalnız Wi-Fi hazırken başlatılır |
| [cihaz_kontrol/include/yerel_kapi_kontrol.h:514](../../cihaz_kontrol/include/yerel_kapi_kontrol.h#L514) | <code>inline void yerelKapiKontrolLoop() {</code> | Wi-Fi koptuysa yerel kontrol durdurulur; bağlıyken UDP işlenir ve beacon yayınlanır |
| [cihaz_kontrol/include/device_konfig.h:18](../../cihaz_kontrol/include/device_konfig.h#L18) | <code>constexpr uint16_t YEREL_KAPI_KONTROL_PORT = 8765;</code> | UDP/HTTP portu 8765 (iki hedefte aynı) |

**Olası nedenler**
- Telefon ve cihaz farklı ağda/VLAN'da; router "AP/client isolation" açık ya da UDP broadcast filtreli
- Cihaz Wi-Fi'ye bağlı değil (yerel kontrol Wi-Fi yokken kapalıdır)
- Paket cihazla aynı özel/yerel ağdan değil (VPN, mobil veri, yönlendirilmiş port): reddedilir
- Hedef UID bu cihazla eşleşmiyor: discover cevapsız, open/pulse "hedef UID eslesmiyor" ile reddedilir
- Paket 512 bayt ve üstü ya da bozuk JSON

**Adım adım kontrol**
- Seri "?" -> "WiFi IP" ve "Yerel kontrol: etkin (anahtar var)" satırları
- Aynı ağdaki bir bilgisayardan GET http://<cihaz-ip>:8765/ahbu/status deneyin (cihaz-yerel-http-status-hata)
- Cihaz Dene aracında beacon geliyor mu (cihaz-yerel-beacon-gelmiyor)
- Cevap geliyor ama "unauthorized" ise cihaz-yerel-udp-imza-reddi

**Günlükte aranacak ifadeler**
- `Yerel kapi kontrol aktif: http://`
- `UDP Kapi Acma REDDEDILDI: hedef UID bu cihazla eslesmiyor.`
- `Yerel kapi kontrol durduruldu.`

**İlgili testler:** [cihaz_kontrol/host_test/t_udp.cpp](../../cihaz_kontrol/host_test/t_udp.cpp)

**Bkz.:** [cihaz-yerel-udp-imza-reddi](#cihaz-yerel-udp-imza-reddi), [cihaz-yerel-beacon-gelmiyor](#cihaz-yerel-beacon-gelmiyor), [cihaz-yerel-http-status-hata](#cihaz-yerel-http-status-hata), [cekirdek-yerel-udp-acma-basarisiz](30-uygulama-cekirdek.md#cekirdek-yerel-udp-acma-basarisiz), [akis-yerel-kapi-acma](60-akislar.md#akis-yerel-kapi-acma)

<a id="cihaz-yerel-udp-imza-reddi"></a>
### cihaz-yerel-udp-imza-reddi · Yerel UDP kapı açma "unauthorized" / "challenge" / "role_mesgul" dönüyor; seri "UDP Kapi Acma REDDEDILDI: imza gecersiz" ya da "yerel kontrol kapali"

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [cihaz_kontrol/include/yerel_kapi_kontrol.h:385](../../cihaz_kontrol/include/yerel_kapi_kontrol.h#L385) | <code>inline void yerelUdpAcmaIsle(JsonDocument&amp; doc, const String&amp; action, const String&amp; benim…</code> | v2 açma isteği: v1 token paketi net reddedilir; sonra yerelAcmaDegerlendir sonucu JSON hata koduna çevrilir |
| [cihaz_kontrol/include/yerel_kontrol_cekirdek.h:200](../../cihaz_kontrol/include/yerel_kontrol_cekirdek.h#L200) | <code>inline YerelSonuc yerelAcmaDegerlendir(YerelDurum&amp; d, const char* token, bool hmacSaglam,…</code> | Karar sırası: token yok -> yinelenen -> challenge -> imza -> röle; her sonuç ayrı hata kodu |
| [cihaz_kontrol/include/yerel_kontrol_cekirdek.h:152](../../cihaz_kontrol/include/yerel_kontrol_cekirdek.h#L152) | <code>inline bool yerelImzaHesapla(const char* token, const char* action, const char* uid, cons…</code> | sig = HMAC-SHA256(token, "action\|UID_BÜYÜK\|ch") küçük hex; sabit zamanlı karşılaştırılır |
| [cihaz_kontrol/include/yerel_kontrol_cekirdek.h:23](../../cihaz_kontrol/include/yerel_kontrol_cekirdek.h#L23) | <code>inline constexpr uint32_t YEREL_CH_DONME_MS = 10000UL;           // challenge her 10 sn'd…</code> | Challenge (ch) her 10 sn'de döner; güncel ve bir önceki kabul edilir |
| [cihaz_kontrol/include/yerel_kontrol_cekirdek.h:24](../../cihaz_kontrol/include/yerel_kontrol_cekirdek.h#L24) | <code>inline constexpr uint32_t YEREL_YINELEME_PENCERESI_MS = 3000UL;  // ayni ch+sig bu surede…</code> | Aynı ch+sig 3 sn içinde tekrar gelirse "duplicate" (röle tekrar tetiklenmez) |
| [cihaz_kontrol/include/mqtt_baglanti.h:361](../../cihaz_kontrol/include/mqtt_baglanti.h#L361) | <code>} else if (action == "local_control_config") {</code> | Yerel kontrol anahtarı (token) sunucudan MQTT ile gelir ve NVS'e yazılır |
| [cihaz_kontrol/include/wifi_baglanti.h:192](../../cihaz_kontrol/include/wifi_baglanti.h#L192) | <code>inline bool wifiLocalTokenGecerliMi(const String&amp; token) {</code> | Token 16-64 karakter, yalnız [0-9A-Za-z_-]; aksi halde reddedilir (local_control_config_rejected) |

**Olası nedenler**
- "challenge": istemcinin önbelleğindeki ch bayat (>~20 sn); normal akış, istemci cevaptaki yeni ch ile bir kez yeniden dener
- "unauthorized" + local_control_available:false: cihazda yerel kontrol anahtarı yok (sunucu local_control_config göndermemiş) ya da HMAC öz-testi başarısız (cihaz-yerel-ozdeneme-basarisiz)
- "unauthorized" + local_control_available:true: istemcinin token'ı cihazdakiyle farklı (anahtar rotasyonu sonrası) ya da imaj mesajı yanlış kurulmuş (action|UID BÜYÜK|ch)
- Eski (v1) istemci: açık metin token paketi artık kabul edilmez
- "role_mesgul": imza doğru ama röle aktif/debounce; challenge tüketilmez, tekrar denenebilir

**Adım adım kontrol**
- Seri "?" -> "Yerel kontrol:" satırı: kapali (anahtar yok) | etkin (anahtar var) | KAPALI (HMAC oz-testi basarisiz)
- Cevaptaki error alanına göre dallanın (challenge | unauthorized | role_mesgul | duplicate)
- İstemci tarafı: cekirdek-yerel-udp-acma-basarisiz; sunucu tarafı anahtar üretimi: sunucu-yerel-kontrol-token-bos, sunucu-yerel-token-rotasyonu
- Protokol sözleşmesi: docs/YEREL_KONTROL_V2.md

**Günlükte aranacak ifadeler**
- `UDP Kapi Acma REDDEDILDI: imza gecersiz.`
- `UDP Kapi Acma REDDEDILDI: yerel kontrol kapali (anahtar yok / oz-test).`
- `UDP Kapi Acma REDDEDILDI: eski (v1) token paketi artik kabul edilmiyor.`
- `Yerel UDP: yinelenen acma paketi (role tekrar tetiklenmedi).`
- `Yerel UDP: KAPI ACILDI (role tetiklendi).`

**İlgili testler:** [cihaz_kontrol/host_test/t_core.cpp](../../cihaz_kontrol/host_test/t_core.cpp), [cihaz_kontrol/host_test/t_udp.cpp](../../cihaz_kontrol/host_test/t_udp.cpp)

**Bkz.:** [cihaz-yerel-ozdeneme-basarisiz](#cihaz-yerel-ozdeneme-basarisiz), [cihaz-yerel-udp-cevap-yok](#cihaz-yerel-udp-cevap-yok), [cekirdek-yerel-udp-acma-basarisiz](30-uygulama-cekirdek.md#cekirdek-yerel-udp-acma-basarisiz), [sunucu-yerel-token-rotasyonu](10-sunucu-api.md#sunucu-yerel-token-rotasyonu), [test-yerel-kontrol-v2](50-arac-test-ve-surec.md#test-yerel-kontrol-v2)

<a id="cihaz-yerel-ozdeneme-basarisiz"></a>
### cihaz-yerel-ozdeneme-basarisiz · Cihaz yerel kapı açmayı tamamen kapattı: seri "UYARI: Yerel kontrol HMAC oz-testi BASARISIZ"; sunucuda local_control_selftest_failed olayı

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [cihaz_kontrol/include/yerel_kapi_kontrol.h:65](../../cihaz_kontrol/include/yerel_kapi_kontrol.h#L65) | <code>inline void yerelHmacOzTesti() {</code> | Açılışta bir kez bilinen-cevap testi; başarısızsa yerel açma KAPALI (fail-closed) ve olay MQTT bağlanınca yayınlanır |
| [cihaz_kontrol/include/yerel_kontrol_cekirdek.h:182](../../cihaz_kontrol/include/yerel_kontrol_cekirdek.h#L182) | <code>inline bool yerelKatCalistir() {</code> | Şartnamedeki open/pulse imza vektörlerini üretimle AYNI HMAC koduyla hesaplar |
| [cihaz_kontrol/include/yerel_kontrol_cekirdek.h:179](../../cihaz_kontrol/include/yerel_kontrol_cekirdek.h#L179) | <code>inline constexpr char YEREL_KAT_SIG_OPEN[] = "92f22b8a741bcc00b1aec15ff573b6ee4d48edea1bb…</code> | Beklenen open imzası (herkese açık TEST değeri; gerçek token değildir) |
| [cihaz_kontrol/include/yerel_kapi_kontrol.h:520](../../cihaz_kontrol/include/yerel_kapi_kontrol.h#L520) | <code>if (mqttPublishEvent("local_control_selftest_failed", "hmac_kat")) {</code> | Başarısızlık olayı |
| [cihaz_kontrol/include/yerel_kapi_kontrol.h:59](../../cihaz_kontrol/include/yerel_kapi_kontrol.h#L59) | <code>inline bool yerelKontrolKullanilabilirMi() {</code> | local_control_available = öz-test geçti VE token var |

**Olası nedenler**
- Bu derlemede HMAC/mbedtls yolu beklenenden farklı sonuç veriyor (derleme/kütüphane sürümü değişikliği)
- Vektör sabitleri (token/UID/ch/imza) yanlışlıkla değiştirildi

**Adım adım kontrol**
- Seri "?" -> "Yerel kontrol: KAPALI (HMAC oz-testi basarisiz)" görünür
- Ana makine testini çalıştırın: python cihaz_kontrol/host_test/run_all.py (t_core KAT ve Node çapraz doğrulaması)
- Cihaz yazılımını son sağlam derlemeye döndürün; sahada yerel kapı açma kapalı kalırken bulut yolu çalışmaya devam eder

**Günlükte aranacak ifadeler**
- `UYARI: Yerel kontrol HMAC oz-testi BASARISIZ; yerel kapi acma KAPALI (fail-closed).`
- `Yerel kontrol: HMAC oz-testi basarili.`

**İlgili testler:** [cihaz_kontrol/host_test/t_core.cpp](../../cihaz_kontrol/host_test/t_core.cpp)

**Bkz.:** [cihaz-yerel-udp-imza-reddi](#cihaz-yerel-udp-imza-reddi), [test-yerel-kontrol-v2](50-arac-test-ve-surec.md#test-yerel-kontrol-v2)

<a id="cihaz-yerel-beacon-gelmiyor"></a>
### cihaz-yerel-beacon-gelmiyor · Uygulama/Cihaz Dene aracı cihazın yerel ağ duyurusunu (beacon) almıyor, cihaz listede çıkmıyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [cihaz_kontrol/include/yerel_kapi_kontrol.h:341](../../cihaz_kontrol/include/yerel_kapi_kontrol.h#L341) | <code>inline void yerelBeaconYayinla() {</code> | ~5 sn'de bir {device_uid, ip, port, rssi, hw, ch} JSON'u alt ağ yayınına ve 255.255.255.255'e gönderir |
| [cihaz_kontrol/include/yerel_kapi_kontrol.h:338](../../cihaz_kontrol/include/yerel_kapi_kontrol.h#L338) | <code>inline constexpr unsigned long YEREL_BEACON_ARALIK_MS = 5000;</code> | Beacon aralığı 5 sn |
| [cihaz_kontrol/include/yerel_kapi_kontrol.h:367](../../cihaz_kontrol/include/yerel_kapi_kontrol.h#L367) | <code>const IPAddress hedefler[2] = {WiFi.broadcastIP(), IPAddress(255, 255, 255, 255)};</code> | İki yayın adresi (bazı AP'ler birini filtreler) |
| [cihaz_kontrol/include/yerel_kapi_kontrol.h:306](../../cihaz_kontrol/include/yerel_kapi_kontrol.h#L306) | <code>inline void yerelKapiKontrolDurdur() {</code> | Wi-Fi koptuğunda UDP kapatılır: beacon da durur |

**Olası nedenler**
- Wi-Fi bağlı değil ya da UDP soketi açılmadı
- Router UDP broadcast/multicast'i filtreliyor ya da istemci izolasyonu açık
- Dinleyici farklı alt ağda (broadcast alt ağ dışına çıkmaz)
- İstemci paketin KAYNAK adresinden IP'yi alır; NAT/VPN arkasındaysa görünmez

**Adım adım kontrol**
- Seri "?" -> "WiFi IP" dolu mu; yoksa cihaz-wifi-baglanmiyor
- Aynı alt ağdaki bilgisayarda UDP 8765 dinleyin (paket JSON'unda device_uid ve ch görünür)
- Beacon ch'si 10 sn'de bir değişir; açma imzası bu ch'ye bağlıdır
- Cihaz Dene aracı için arac-cihaz-dene-beacon-wan

**İlgili testler:** [cihaz_kontrol/host_test/t_udp.cpp](../../cihaz_kontrol/host_test/t_udp.cpp)

**Bkz.:** [cihaz-yerel-udp-cevap-yok](#cihaz-yerel-udp-cevap-yok), [cekirdek-yerel-beacon-alinmiyor](30-uygulama-cekirdek.md#cekirdek-yerel-beacon-alinmiyor), [arac-cihaz-dene-beacon-wan](50-arac-test-ve-surec.md#arac-cihaz-dene-beacon-wan)

<a id="cihaz-yerel-http-status-hata"></a>
### cihaz-yerel-http-status-hata · http://<cihaz-ip>:8765/ahbu/status 404 (route_bulunamadi / cihaz_uid_eslesmedi), 400 ya da 431 dönüyor; eski POST /ahbu/open çalışmıyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [cihaz_kontrol/include/yerel_kapi_kontrol.h:563](../../cihaz_kontrol/include/yerel_kapi_kontrol.h#L563) | <code>if (request.method == "GET" &amp;&amp; request.path == "/ahbu/status") {</code> | Yalnız GET /ahbu/status vardır; diğer her istek 404 route_bulunamadi |
| [cihaz_kontrol/include/yerel_kapi_kontrol.h:566](../../cihaz_kontrol/include/yerel_kapi_kontrol.h#L566) | <code>// POST /ahbu/open v2'de KALDIRILDI (token acik metin tasirdi): 404</code> | v2'de HTTP ile kapı açma YOK (token açık metin taşırdı) |
| [cihaz_kontrol/include/yerel_kapi_kontrol.h:243](../../cihaz_kontrol/include/yerel_kapi_kontrol.h#L243) | <code>inline void yerelStatusHandler(WiFiClient&amp; client, const YerelHttpIstek&amp; request) {</code> | Durum cevabı: device_uid, firmware_version, wifi_connected, ip, door_locked, local_control_available (sır yok) |
| [cihaz_kontrol/include/yerel_kapi_kontrol.h:145](../../cihaz_kontrol/include/yerel_kapi_kontrol.h#L145) | <code>inline YerelOkuSonuc yerelHttpIstekOku(WiFiClient&amp; client, YerelHttpIstek&amp; request) {</code> | 512 bayt ve 300 ms sınırı; aşılırsa 431 (istek_cok_buyuk), bozuk/zaman aşımı 400 (gecersiz_istek) |
| [cihaz_kontrol/include/yerel_kapi_kontrol.h:233](../../cihaz_kontrol/include/yerel_kapi_kontrol.h#L233) | <code>inline bool yerelUidEslesiyor(const String&amp; gelenUid) {</code> | X-AHBU-Device-UID başlığı verilmişse cihaz UID'siyle eşleşmeli (büyük/küçük harf duyarsız), değilse 404 |
| [cihaz_kontrol/include/yerel_kapi_kontrol.h:292](../../cihaz_kontrol/include/yerel_kapi_kontrol.h#L292) | <code>MDNS.addService("ahbu", "tcp", YEREL_KAPI_KONTROL_PORT);  // servis turu protokol kimligi…</code> | mDNS adı smartkeypass-<uid>.local (eski firmware ahbu-<uid>.local; servis türü _ahbu._tcp protokol kimliği olarak kalır); ağ mDNS'i filtreliyorsa IP ile deneyin |

**Olası nedenler**
- Eski istemci POST /ahbu/open kullanıyor: v2 ile kaldırıldı, UDP imzalı açma kullanılmalı
- Yanlış UID başlığı ya da yanlış yol
- Kaynak adres yerel ağ değil: bağlantı sessizce kapatılır
- İstek 300 ms içinde tamamlanmadı (yavaş istemci)

**Adım adım kontrol**
- curl http://<ip>:8765/ahbu/status ile deneyin; ok:true ve door_locked alanlarını okuyun
- Seri açılışta "Yerel kapi kontrol aktif: http://<ip>:8765/ahbu/status" satırı görünmeli

**Komutlar**
```bash
curl -s http://<cihaz-ip>:8765/ahbu/status
```

**İlgili testler:** [cihaz_kontrol/host_test/t_udp.cpp](../../cihaz_kontrol/host_test/t_udp.cpp)

**Bkz.:** [cihaz-yerel-udp-cevap-yok](#cihaz-yerel-udp-cevap-yok), [cihaz-yerel-udp-imza-reddi](#cihaz-yerel-udp-imza-reddi)

<a id="cihaz-admin-pin-tanimsiz-reddedildi"></a>
### cihaz-admin-pin-tanimsiz-reddedildi · Ekranda yönetici menüsü "PIN tanımlı değil" (NOPIN) gösteriyor ya da PIN atanamıyor: "Yonetici PIN'i REDDEDILDI: zayif PIN" / "gecersiz"

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [cihaz_kontrol/include/admin_pin.h:120](../../cihaz_kontrol/include/admin_pin.h#L120) | <code>inline bool adminPinAyarla(const String&amp; pin, AdminPinRed* red = nullptr) {</code> | PIN yazar/siler; biçim (tam 6 rakam) ve zayıf PIN denetimi; ret nedeni red'e yazılır, PIN değeri hiçbir yere yazılmaz |
| [cihaz_kontrol/include/admin_pin.h:69](../../cihaz_kontrol/include/admin_pin.h#L69) | <code>inline bool adminPinZayifMi(const String&amp; pin) {</code> | Zayıf liste (000000, 111111, 123456, 654321, 123123, 121212, 112233, 000001), hepsi aynı rakam ve tam ardışık diziler reddedilir |
| [cihaz_kontrol/include/mqtt_baglanti.h:370](../../cihaz_kontrol/include/mqtt_baglanti.h#L370) | <code>} else if (action == "admin_pin_config") {</code> | MQTT ile PIN atama; ret olayı admin_pin_config_rejected (weak_pin \| invalid_pin \| unsupported_target) |
| [cihaz_kontrol/src/main.cpp:123](../../cihaz_kontrol/src/main.cpp#L123) | <code>if (satir.startsWith("ADMINPIN:")) {</code> | Seri satırla PIN atama: ADMINPIN:NNNNNN (boş bırakılırsa PIN silinir) |
| [cihaz_kontrol/src/display_uart.cpp:81](../../cihaz_kontrol/src/display_uart.cpp#L81) | <code>static void displayAdminDurumuGonder() {</code> | Ekrana ADMIN_STATE\|NOPIN \| LOCKED\|<sn> \| READY gönderir |
| [cihaz_kontrol/include/admin_pin.h:107](../../cihaz_kontrol/include/admin_pin.h#L107) | <code>inline void adminPinBaslat() {</code> | Açılışta PIN NVS'ten (admin_cfg / admin_pin) okunur; biçimi geçersizse PIN yok sayılır |

**Olası nedenler**
- PIN hiç atanmadı (ekranda sabit PIN yoktur; NOPIN normaldir)
- Atanan PIN zayıf ya da 6 rakam değil: cihaz reddeder, eski PIN değişmez
- C3 cihazda "admin_pin_config" gönderildi: C3'te ekran yoktur, "unsupported_target" döner
- NVS silindi (erase_flash): PIN de silinir

**Adım adım kontrol**
- Seri "?" -> "Yonetici PIN: tanimli | tanimli degil" (yalnız WROOM)
- Sunucu olaylarında admin_pin_configured veya admin_pin_config_rejected (detail: weak_pin/invalid_pin) arayın
- Seri satırdan deneyin: ADMINPIN:NNNNNN; PIN yankılanmaz, ret nedeni yazılır

**Günlükte aranacak ifadeler**
- `Yonetici PIN'i guncellendi.`
- `Yonetici PIN'i reddedildi (MQTT): zayif PIN.`
- `Yonetici PIN'i gecersiz (tam 6 rakam olmali`

**İlgili testler:** [cihaz_kontrol/host_test/t_pin.cpp](../../cihaz_kontrol/host_test/t_pin.cpp)

**Bkz.:** [cihaz-admin-pin-kilitli](#cihaz-admin-pin-kilitli), [cihaz-ekran-bos-baglanti](#cihaz-ekran-bos-baglanti)

<a id="cihaz-admin-pin-kilitli"></a>
### cihaz-admin-pin-kilitli · Ekranda yönetici PIN girişi "kilitli" (LOCKED, kalan saniye) gösteriyor; doğru PIN bile kabul edilmiyor ya da yönetici kapı açma "BUSY" diyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [cihaz_kontrol/include/admin_pin.h:184](../../cihaz_kontrol/include/admin_pin.h#L184) | <code>inline AdminPinSonuc adminPinDogrula(const String&amp; pin, uint32_t&amp; kalan) {</code> | Doğrulama: kilitliyse KILITLI; yanlışta sayaç artar; 5. hatada 5 dk kilit başlar |
| [cihaz_kontrol/include/admin_pin.h:24](../../cihaz_kontrol/include/admin_pin.h#L24) | <code>inline constexpr unsigned long ADMIN_PIN_KILIT_MS = 5UL * 60UL * 1000UL;</code> | Kilit süresi 5 dakika |
| [cihaz_kontrol/include/admin_pin.h:23](../../cihaz_kontrol/include/admin_pin.h#L23) | <code>inline constexpr uint8_t ADMIN_PIN_MAX_HATA = 5;</code> | Ardışık 5 hatalı denemede kilit |
| [cihaz_kontrol/include/admin_pin.h:150](../../cihaz_kontrol/include/admin_pin.h#L150) | <code>inline uint32_t adminPinKilitKalanSn() {</code> | Kilit bitince yalnız 1 deneme hakkı verilir (4 hata sayılır); sayaç NVS'te kalıcıdır |
| [cihaz_kontrol/src/display_uart.cpp:106](../../cihaz_kontrol/src/display_uart.cpp#L106) | <code>static void displayAdminIstegiIsle(bool kapiAc, const String&amp; pin) {</code> | ADMIN_AUTH (menü) ve ADMIN_OPEN (kapı aç) aynı doğrulayıcı ve sayacı paylaşır; olaylar admin_pin_failed / admin_pin_locked |
| [cihaz_kontrol/src/display_uart.cpp:128](../../cihaz_kontrol/src/display_uart.cpp#L128) | <code>displayUartSend(String(CMD_ADMIN_DENIED_PREFIX) + "BUSY&#124;0");</code> | PIN doğru ama röle tetiklenemedi (aktif/debounce): BUSY |
| [cihaz_kontrol/src/main.cpp:515](../../cihaz_kontrol/src/main.cpp#L515) | <code>adminPinZamanlayici();  // PIN kilidi suresi dolunca sorgu beklemeden kapat (bayat baslan…</code> | Kilit süresi dolunca bayrak sorgu beklemeden kapatılır |

**Olası nedenler**
- 5 yanlış PIN girişi: 5 dk kilit; yeniden başlatma kilidi SIFIRLAMAZ (açılışta kilit yeniden başlar)
- Ekran yazılımı eski: PIN'siz ADMIN komutu gönderir ve reddedilir ("ekran yazilimi guncel olmali")
- BUSY: röle zaten aktif

**Adım adım kontrol**
- Ekrandaki geri sayım ana karttan gelen LOCKED|<sn> değeridir; bekleyin ya da MQTT/seri ile yeni PIN atayın (atama sayacı ve kilidi sıfırlar)
- Sunucuda admin_pin_failed / admin_pin_locked olayları kimin kaç kez denediğini gösterir
- PIN değeri hiçbir günlükte yazılmaz

**Günlükte aranacak ifadeler**
- `[DISPLAY] UYARI: PIN'siz ADMIN komutu reddedildi (ekran yazilimi guncel olmali)`
- `[DISPLAY] Yonetici PIN dogrulandi -> role tetiklendi`

**İlgili testler:** [cihaz_kontrol/host_test/t_pin.cpp](../../cihaz_kontrol/host_test/t_pin.cpp)

**Bkz.:** [cihaz-admin-pin-tanimsiz-reddedildi](#cihaz-admin-pin-tanimsiz-reddedildi), [cihaz-ekran-bos-baglanti](#cihaz-ekran-bos-baglanti)

<a id="cihaz-ekran-bos-baglanti"></a>
### cihaz-ekran-bos-baglanti · Ekran (WROOM + C3 ekran kartı) boş/bayat: Wi-Fi, bulut ya da QR görünmüyor; ana karttan UART satırı gelmiyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [cihaz_kontrol/src/display_uart.cpp:42](../../cihaz_kontrol/src/display_uart.cpp#L42) | <code>void displayUartSetup() {</code> | UART1 (RX32/TX33, 115200) açılır ve ekrana READY gönderilir |
| [cihaz_kontrol/include/display_uart.h:7](../../cihaz_kontrol/include/display_uart.h#L7) | <code>constexpr int DISPLAY_UART_RX_PIN = 32; // UART1 RX</code> | Ekran UART pinleri (WROOM GPIO32 RX <- C3 TX, GPIO33 TX -> C3 RX) |
| [cihaz_kontrol/src/display_uart.cpp:133](../../cihaz_kontrol/src/display_uart.cpp#L133) | <code>static void handleDisplayCommand(const String &amp;rawCmd) {</code> | Ekranın gönderdiği komutlar (READY, REQ_STATUS, REQ_INFO, REQ_ADMIN, ADMIN_*) burada işlenir; bilinmeyen komut yok sayılır |
| [cihaz_kontrol/src/display_uart.cpp:200](../../cihaz_kontrol/src/display_uart.cpp#L200) | <code>void displayUartLoop() {</code> | Satır tabanlı okuma; 255 karakterden uzun satır sonraki satır sonuna kadar atılır |
| [cihaz_kontrol/src/main.cpp:281](../../cihaz_kontrol/src/main.cpp#L281) | <code>void displayDurumSenkronizasyonLoop() {</code> | Wi-Fi/MQTT durum değişimini ve 5 sn'de bir durum + QR tekrarını ekrana yollar |
| [cihaz_kontrol/src/main.cpp:276](../../cihaz_kontrol/src/main.cpp#L276) | <code>void displayDurumuYenidenGonder() {</code> | Ekran READY gönderince durumlar hemen tekrar yollanır |
| [cihaz_kontrol/include/display_protocol.h:26](../../cihaz_kontrol/include/display_protocol.h#L26) | <code>#define CMD_SYS_STATUS_PREFIX    "SYS_STATUS&#124;"     // "SYS_STATUS&#124;SSID&#124;IP&#124;RSSI&#124;MQTT(1/0)&#124;…</code> | Protokol sabitleri ekran_yazilimi ile BİREBİR aynı olmalı (iki kopya) |
| [ekran_yazilimi/include/ScreenManager.h:142](../../ekran_yazilimi/include/ScreenManager.h#L142) | <code>static constexpr unsigned long MAIN_LINK_TIMEOUT_MS = 45000UL;</code> | Ekran tarafında: 45 sn hiç satır gelmezse Wi-Fi/Bulut/QR bayat sayılır |

**Olası nedenler**
- Ekran kartı ile ana kart arasındaki TX/RX hatları ters ya da kopuk (GPIO32/33)
- Ana kart C3 (ekransız hedef): displayUartSend* C3'te boş fonksiyondur, ekran sürücüsü yalnız WROOM'dadır
- display_protocol.h iki projede farklı sürümde (komut sabiti uyuşmuyor)
- Ana MCU döngüsü uzun süre bloklandı (DNS/TLS): ekran 45 sn sonra bayat uyarısı verir
- Atölye pin bulma testi sonrası UART yeniden bağlanır (displayUartSetup); test sürerken ekran susar

**Adım adım kontrol**
- Seri günlükte "[DISPLAY] UART1 initialized (RX=32, TX=33)" ve "[DISPLAY] TX/RX" satırları görünüyor mu (periyodik WIFI_/MQTT_/SHOW_QR satırları bilerek yazılmaz)
- İki projedeki display_protocol.h dosyalarını karşılaştırın (byte-byte aynı olmalı)
- Ekran firmware tarafı: arac-ekran-firmware ve ekran_yazilimi/ girişleri (başka alan)

**Günlükte aranacak ifadeler**
- `[DISPLAY] UART1 initialized (RX=`
- `[DISPLAY] RX satiri cok uzun, sonraki satir sonuna kadar atlaniyor`
- `[DISPLAY] Bilinmeyen komut (yoksayildi)`

**Bkz.:** [cihaz-ekran-qr-yenilenmiyor](#cihaz-ekran-qr-yenilenmiyor), [cihaz-admin-pin-tanimsiz-reddedildi](#cihaz-admin-pin-tanimsiz-reddedildi), [arac-ekran-firmware](50-arac-test-ve-surec.md#arac-ekran-firmware)

<a id="cihaz-ekran-qr-yenilenmiyor"></a>
### cihaz-ekran-qr-yenilenmiyor · Ekrandaki dinamik QR yenilenmiyor ya da uygulamayla okutunca "geçersiz/süresi dolmuş" diyor (WROOM ekranlı cihaz)

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [cihaz_kontrol/src/main.cpp:232](../../cihaz_kontrol/src/main.cpp#L232) | <code>constexpr unsigned long SCREEN_QR_ROTATION_INTERVAL_MS = 30000UL;</code> | Ekran QR token'ı 30 sn'de bir yenilenir |
| [cihaz_kontrol/src/main.cpp:254](../../cihaz_kontrol/src/main.cpp#L254) | <code>void broadcastScreenQrToken(bool isNewToken) {</code> | Token üretir, ekrana SHOW_QR\| ile yollar; yayınlanmadıysa MQTT screen_qr konusuna (retained DEĞİL) gönderir |
| [cihaz_kontrol/src/main.cpp:235](../../cihaz_kontrol/src/main.cpp#L235) | <code>static bool rfAktifMi() {</code> | RF (Wi-Fi/BLE) kapalıyken token ÜRETİLMEZ (esp_random gerçek rastgele olsun) |
| [cihaz_kontrol/src/main.cpp:239](../../cihaz_kontrol/src/main.cpp#L239) | <code>static String generateDynamicScreenQrToken() {</code> | 6 karakterlik token, modulo yanlılığı olmadan |
| [cihaz_kontrol/include/mqtt_baglanti.h:188](../../cihaz_kontrol/include/mqtt_baglanti.h#L188) | <code>inline bool mqttPublishScreenQr(const String&amp; token, int validSeconds = 30) {</code> | device/<uid>/screen_qr: {token, valid_seconds, device_uid, timestamp_ms}; sunucu bu tokenı doğrular |
| [cihaz_kontrol/src/display_uart.cpp:17](../../cihaz_kontrol/src/display_uart.cpp#L17) | <code>static bool displayLogGizli(const String&amp; s) {</code> | SHOW_QR ve ADMIN_ satırları seriye maskelenerek yazılır (token görünmez) |

**Olası nedenler**
- MQTT bağlı değil: token ekrana gider ama sunucuya bildirilmez; uygulamayla okutma doğrulanamaz
- MQTT yayını başarısız: gScreenQrMqttYayinlandi false kalır, sonraki turda yeniden denenir
- Cihaz C3 (ekransız): bu özellik yoktur
- Wi-Fi/RF kapalı ya da henüz açılmadı: token üretilmez

**Adım adım kontrol**
- Seri "?" -> "MQTT: bagli" ve sunucuda device/<uid>/screen_qr alımı (altyapi-ekran-qr-token-sunucuda, sunucu-tarama-qr-ekran-token)
- Uygulama tarafı okutma akışı için akis-ekran-qr-uygulama-okutma
- Ekran kartı yeniden başlayınca READY ile güncel QR hemen istenir

**İlgili testler:** [cihaz_kontrol/host_test/t_mqtt.cpp](../../cihaz_kontrol/host_test/t_mqtt.cpp)

**Bkz.:** [cihaz-ekran-bos-baglanti](#cihaz-ekran-bos-baglanti), [altyapi-ekran-qr-token-sunucuda](20-sunucu-altyapi-ve-yayin.md#altyapi-ekran-qr-token-sunucuda), [sunucu-tarama-qr-ekran-token](10-sunucu-api.md#sunucu-tarama-qr-ekran-token), [akis-ekran-qr-uygulama-okutma](60-akislar.md#akis-ekran-qr-uygulama-okutma)

<a id="cihaz-seri-atolye-komutlari"></a>
### cihaz-seri-atolye-komutlari · Seri monitörden "h" / "l" / "p" komutları cevap vermiyor: "Atolye modu kapali (Wi-Fi sifirlayin veya reset butonu 3 sn)"; "?" çıktısı kendiliğinden gelmiyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [cihaz_kontrol/src/main.cpp:52](../../cihaz_kontrol/src/main.cpp#L52) | <code>static bool atolyeModuAcikMi() {</code> | Atölye modu = kayıtlı Wi-Fi YOK ya da BLE provisioning penceresi açık; AHBU_DEBUG_SERIAL_CMDS derlemesinde hep açık |
| [cihaz_kontrol/src/main.cpp:140](../../cihaz_kontrol/src/main.cpp#L140) | <code>void seriKomutKontrol() {</code> | ? s u i (durum), r (pulse), k (kamera) HER derlemede açık; h l p yalnız atölye modunda |
| [cihaz_kontrol/src/main.cpp:191](../../cihaz_kontrol/src/main.cpp#L191) | <code>Serial.println("Atolye modu kapali (Wi-Fi sifirlayin veya reset butonu 3 sn)");</code> | Saha cihazında (Wi-Fi kayıtlı) h/l/p bilerek cevap vermez |
| [cihaz_kontrol/src/main.cpp:523](../../cihaz_kontrol/src/main.cpp#L523) | <code>const bool periyodikDurum = atolyeModuAcikMi() &#124;&#124; gSeriOturumAktif;</code> | 5 sn'lik durum dökümü yalnız atölye modunda ya da seri porta bir şey yazıldıktan sonra açılır |
| [cihaz_kontrol/src/main.cpp:353](../../cihaz_kontrol/src/main.cpp#L353) | <code>void seriDurumYazdir() {</code> | Salt-okunur durum özeti (token/PIN/parola yazdırmaz) |
| [cihaz_kontrol/src/main.cpp:65](../../cihaz_kontrol/src/main.cpp#L65) | <code>void pinBulmaTesti() {</code> | p: her pini 800 ms HIGH yapar; döngüyü bloklar, sonunda pinler güvenli duruma döner |
| [cihaz_kontrol/platformio.ini:11](../../cihaz_kontrol/platformio.ini#L11) | <code>;      -D AHBU_DEBUG_SERIAL_CMDS</code> | Atölye kapısını kaldıran derleme bayrağı (platformio.ini başlık yorumunda anlatılır) |
| [cihaz_kontrol/include/role_kontrol.h:90](../../cihaz_kontrol/include/role_kontrol.h#L90) | <code>inline void roleManuelSeviye(uint8_t level) {</code> | h: röle 60 sn tutulur ve otomatik bırakılır; l: hemen bırakır |

**Olası nedenler**
- Cihaz sahada ve Wi-Fi kayıtlı: atölye kapısı bilerek kapalı (rölenin yanlışlıkla tutulmasını önler)
- Periyodik döküm saha cihazında susar: kimse dinlemiyorsa yazdırılmaz; "?" gönderince açılır
- Cihaz Dene aracı seri portu tutuyorsa başka monitör bağlanamaz ("Baglantiyi Kes")

**Adım adım kontrol**
- Önce "?" yazın: "Atolye modu: acik|kapali" satırı durumu söyler
- Atölye modu açmak için Wi-Fi bilgisini silin (reset butonu 3 sn, cihaz-wifi-sifirlama-butonu)
- Üretim derlemesine AHBU_DEBUG_SERIAL_CMDS EKLEMEYİN (saha cihazında kapıyı açık tutan komutları açar)

**Günlükte aranacak ifadeler**
- `Atolye modu kapali (Wi-Fi sifirlayin veya reset butonu 3 sn)`
- `Seri komut: role pini HIGH`
- `Seri komut: pin bulma testi`
- `PIN BULMA TESTI BASLADI!`

**Bkz.:** [cihaz-role-acmiyor](#cihaz-role-acmiyor), [cihaz-gm60-baglanti-yok](#cihaz-gm60-baglanti-yok), [cihaz-wifi-sifirlama-butonu](#cihaz-wifi-sifirlama-butonu), [arac-cihaz-dene-durum-bos](50-arac-test-ve-surec.md#arac-cihaz-dene-durum-bos)

<a id="cihaz-derleme-ortami-hatasi"></a>
### cihaz-derleme-ortami-hatasi · Firmware derlenmiyor ya da yanlış donanım için derleniyor (pio run hatası, "BOARD_ESP32_..." tanımsız, röle/GM60 pini beklenenden farklı)

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [cihaz_kontrol/platformio.ini:28](../../cihaz_kontrol/platformio.ini#L28) | <code>[env:lolin_c3_mini]</code> | C3 ortamı: -D BOARD_ESP32_C3; bölüm tablosu partitions_ota_4mb.csv |
| [cihaz_kontrol/platformio.ini:36](../../cihaz_kontrol/platformio.ini#L36) | <code>[env:esp32_relay_wroom]</code> | WROOM ortamı: -D BOARD_ESP32_WROOM_RELAY (ekran sürücüsü, admin PIN, ekran QR yalnız bu bayrakla derlenir) |
| [cihaz_kontrol/platformio.ini:15](../../cihaz_kontrol/platformio.ini#L15) | <code>platform = espressif32@6.5.0</code> | Platform sürümü sabitlenmiştir; değiştirmek davranışı etkileyebilir |
| [platformio.ini:13](../../platformio.ini#L13) | <code>[env]</code> | Kök platformio.ini (VS Code girişi): cihaz_kontrol kaynaklarını derler fakat bayrakları farklıdır; hangi dizinden derlendiğine dikkat |
| [cihaz_kontrol/include/device_konfig.h:7](../../cihaz_kontrol/include/device_konfig.h#L7) | <code>#if defined(BOARD_ESP32_WROOM_RELAY)</code> | Pin sabitleri bayrağa göre seçilir: bayrak yoksa C3 değerleri kullanılır |
| [cihaz_kontrol/include/ota_guncelleme.h:35](../../cihaz_kontrol/include/ota_guncelleme.h#L35) | <code>#if defined(BOARD_ESP32_WROOM_RELAY) &#124;&#124; defined(BOARD_ESP32_WROOM)</code> | OTA hedefi ve manifest adresi de aynı bayraktan türer |

**Olası nedenler**
- cihaz_kontrol dizininde değil de kökten ya da yanlış -e ortamıyla derlendi
- Bayrak yok: kod C3 varsayımıyla derlenir (röle GPIO10, GM60 20/21)
- ArduinoJson/PubSubClient kütüphanesi indirilemedi (ağ) ya da sürüm uyumsuz (ArduinoJson ^7.3.1 gerekir)
- Aynı firmware.bin yanlış donanıma yüklendi: OTA hedef uyuşmazlığı ve röle/pin farkları doğurur

**Adım adım kontrol**
- cd cihaz_kontrol && pio run -e lolin_c3_mini (C3) ya da -e esp32_relay_wroom (WROOM)
- Seri "?" -> "Hardware Target" ve "Role GPIO" derlenen donanımla uyumlu mu
- Sürüm/derleme araçları için arac-test-ve-surec alanına (test-nerede-firmware) bakın
- ESP32-C3 sahada: pin/BLE/Wi-Fi/MQTT davranışına dokunan derleme değişikliği yapmayın

**Komutlar**
```bash
cd cihaz_kontrol && pio run -e esp32_relay_wroom
```

**Bkz.:** [cihaz-wroom-usb-yukleme](#cihaz-wroom-usb-yukleme), [cihaz-ota-hedef-uyusmazligi](#cihaz-ota-hedef-uyusmazligi), [test-nerede-firmware](50-arac-test-ve-surec.md#test-nerede-firmware)

<a id="cihaz-wroom-usb-yukleme"></a>
### cihaz-wroom-usb-yukleme · WROOM kartına USB ile firmware yüklenemiyor ("USB yukleme basarisiz") ya da yükleme sonrası kart eski sürümle açılıyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [cihaz_kontrol/flash_wroom.bat:19](../../cihaz_kontrol/flash_wroom.bat#L19) | <code>call pio run -e esp32_relay_wroom -t upload --upload-port %PORT%</code> | app0 (0x10000) USB ile yazılır; varsayılan port COM7, ilk argümanla değişir |
| [cihaz_kontrol/flash_wroom.bat:27](../../cihaz_kontrol/flash_wroom.bat#L27) | <code>"%USERPROFILE%\.platformio\penv\Scripts\python.exe" "%USERPROFILE%\.platformio\packages\t…</code> | otadata sıfırlanır: bootloader yeni app0'ı seçsin (OTA ile app1'e geçilmişse eski imaj açılmasını önler) |
| [cihaz_kontrol/flash_wroom.bat:22](../../cihaz_kontrol/flash_wroom.bat#L22) | <code>echo Lutfen SmartKeyPass Cihaz Deneme veya Seri Monitor baglantisini Kes butonuna basarak…</code> | Seri port başka program tarafından tutuluyorsa yükleme başarısız olur |
| [cihaz_kontrol/partitions_ota_4mb.csv:3](../../cihaz_kontrol/partitions_ota_4mb.csv#L3) | <code>otadata,  data, ota,     0xe000,  0x2000,</code> | otadata 0xe000 / 0x2000 bayt; bat betiği tam bu bölgeyi siler |
| [cihaz_kontrol/partitions_ota_4mb.csv:4](../../cihaz_kontrol/partitions_ota_4mb.csv#L4) | <code>app0,     app,  ota_0,   0x10000, 0x1E0000,</code> | app0 0x10000, app1 0x1F0000; her biri 0x1E0000 bayt |
| [cihaz_kontrol/flash_wroom.bat:8](../../cihaz_kontrol/flash_wroom.bat#L8) | <code>set PORT=COM7</code> | Varsayılan port; farklı portta ilk argüman verilmeli |

**Olası nedenler**
- Seri port başka uygulamada (Cihaz Dene, seri monitör) açık
- Yanlış COM portu ya da kartın indirme moduna alınamaması (GPIO0)
- otadata silinmedi: önceki OTA ile aktif bölüm app1 kalmış, yeni app0 görünmez (betiğin 3. adımı bunun için)
- pio derlemesi başarısız (cihaz-derleme-ortami-hatasi)

**Adım adım kontrol**
- flash_wroom.bat COM9 gibi doğru portla çalıştırın
- Seri bağlantıyı kapatın, sonra yeniden deneyin
- Yükleme sonrası seri "?" -> "Firmware Versiyon" beklenen sürüm mü; değilse otadata adımının çalıştığını doğrulayın
- Bu betik cihazdaki NVS verilerini (Wi-Fi/MQTT kimliği) SİLMEZ; tam flash silme yapmayın

**Bkz.:** [cihaz-derleme-ortami-hatasi](#cihaz-derleme-ortami-hatasi), [cihaz-ota-sonrasi-geri-aldi](#cihaz-ota-sonrasi-geri-aldi), [cihaz-ota-partition-yok](#cihaz-ota-partition-yok)

<a id="cihaz-ota-partition-yok"></a>
### cihaz-ota-partition-yok · OTA durumu "OTA partition yok; cihaza USB ile OTA partition tablosu yuklenmeli"

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [cihaz_kontrol/include/ota_guncelleme.h:883](../../cihaz_kontrol/include/ota_guncelleme.h#L883) | <code>const esp_partition_t* updatePartition = esp_ota_get_next_update_partition(nullptr);</code> | OTA için bir sonraki güncelleme bölümü yoksa (eski bölüm tablosu) güncelleme yapılmaz |
| [cihaz_kontrol/include/ota_guncelleme.h:885](../../cihaz_kontrol/include/ota_guncelleme.h#L885) | <code>otaPersistStatus("OTA partition yok; cihaza USB ile OTA partition tablosu yuklenmeli", ve…</code> | Durum metni; ota_failed olayı yayınlanır |
| [cihaz_kontrol/partitions_ota_4mb.csv:5](../../cihaz_kontrol/partitions_ota_4mb.csv#L5) | <code>app1,     app,  ota_1,   0x1F0000,0x1E0000,</code> | İki eşit uygulama bölümü (ota_0, ota_1) gerekir |
| [cihaz_kontrol/platformio.ini:30](../../cihaz_kontrol/platformio.ini#L30) | <code>board_build.partitions = partitions_ota_4mb.csv</code> | İki ortam da OTA bölüm tablosunu kullanır |

**Olası nedenler**
- Cihaz OTA'lı bölüm tablosu olmadan, eski tek uygulamalı tabloyla USB'den yüklenmiş: OTA hiçbir zaman çalışmaz
- Bölüm tablosu OTA ile değiştirilemez; USB ile tam yükleme (bootloader + partitions + firmware) gerekir

**Adım adım kontrol**
- Cihazı USB ile bu depodaki partitions_ota_4mb.csv ile yeniden yükleyin
- Sunucu manifestinde usb_required kullanımı için cihaz-ota-hedef-uyusmazligi

**Günlükte aranacak ifadeler**
- `OTA partition yok; cihaza USB ile OTA partition tablosu yuklenmeli`

**Bkz.:** [cihaz-wroom-usb-yukleme](#cihaz-wroom-usb-yukleme), [cihaz-ota-hedef-uyusmazligi](#cihaz-ota-hedef-uyusmazligi)

<a id="cihaz-yerel-anahtar-reddedildi"></a>
### cihaz-yerel-anahtar-reddedildi · Sunucudan yerel kontrol anahtarı gönderildi ama cihaz "local_control_config_rejected" (invalid_token) olayı yayınlıyor; yerel kontrol "kapali (anahtar yok)" kalıyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [cihaz_kontrol/include/mqtt_baglanti.h:368](../../cihaz_kontrol/include/mqtt_baglanti.h#L368) | <code>mqttPublishEvent("local_control_config_rejected", "invalid_token");</code> | Geçersiz token: olay yayınlanır, anahtar yazılmaz |
| [cihaz_kontrol/include/wifi_baglanti.h:207](../../cihaz_kontrol/include/wifi_baglanti.h#L207) | <code>inline int wifiPersistLocalToken(const String&amp; token) {</code> | 0 geçersiz, 1 değişmedi, 2 güncellendi; NVS'e yalnız değişince yazar (flash aşınması) |
| [cihaz_kontrol/include/wifi_baglanti.h:192](../../cihaz_kontrol/include/wifi_baglanti.h#L192) | <code>inline bool wifiLocalTokenGecerliMi(const String&amp; token) {</code> | 16-64 karakter, yalnız harf/rakam/-/_ |
| [cihaz_kontrol/src/main.cpp:401](../../cihaz_kontrol/src/main.cpp#L401) | <code>Serial.println(!wifiHasLocalControlToken() ? "kapali (anahtar yok)" : (gYerelHmacSaglam ?…</code> | Seri durum dökümünde yerel kontrol durumu |

**Olası nedenler**
- Sunucunun ürettiği token 16-64 karakter ya da izinli karakter kuralına uymuyor
- Komut cihaz çevrimdışıyken gitti ve ulaşmadı: cihaz bağlanınca sunucunun yeniden göndermesi gerekir (sunucu tarafı)

**Adım adım kontrol**
- Sunucu olaylarında local_control_config_rejected (detail: invalid_token) var mı
- Seri "?" -> "Yerel kontrol:" satırı
- Sunucu tarafı: sunucu-yerel-kontrol-token-bos, sunucu-yerel-token-rotasyonu

**Günlükte aranacak ifadeler**
- `Yerel kontrol anahtari guncellendi.`

**İlgili testler:** [cihaz_kontrol/host_test/t_mqtt.cpp](../../cihaz_kontrol/host_test/t_mqtt.cpp)

**Bkz.:** [cihaz-yerel-udp-imza-reddi](#cihaz-yerel-udp-imza-reddi), [sunucu-yerel-kontrol-token-bos](10-sunucu-api.md#sunucu-yerel-kontrol-token-bos), [cekirdek-yerel-token-yok](30-uygulama-cekirdek.md#cekirdek-yerel-token-yok)

<a id="cihaz-host-test-calismiyor"></a>
### cihaz-host-test-calismiyor · Firmware ana makine testleri (host_test) derlenmiyor ya da başarısız; "vcvars64.bat bulunamadi" ya da ArduinoJson yolu hatası

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [cihaz_kontrol/host_test/run_all.py:22](../../cihaz_kontrol/host_test/run_all.py#L22) | <code>VCVARS = os.environ.get(</code> | Visual Studio vcvars64.bat yolu; farklıysa VCVARS ortam değişkeniyle verilir |
| [cihaz_kontrol/host_test/run_all.py:21](../../cihaz_kontrol/host_test/run_all.py#L21) | <code>ARDUINOJSON = os.path.normpath(os.path.join(HERE, '..', '.pio', 'libdeps', 'lolin_c3_mini…</code> | ArduinoJson başlıkları .pio/libdeps/lolin_c3_mini altında aranır: önce pio run yapılmış olmalı |
| [cihaz_kontrol/host_test/run_all.py:29](../../cihaz_kontrol/host_test/run_all.py#L29) | <code>TESTS = [</code> | Test listesi: t_core, t_udp, t_pin, t_gm60, t_mqtt (WROOM + C3) |
| [cihaz_kontrol/host_test/README.md:20](../../cihaz_kontrol/host_test/README.md#L20) | <code>## Gereksinimler</code> | MSVC, Python 3, Node.js (t_core vektörleri) ve ArduinoJson gereksinimi |
| [cihaz_kontrol/host_test/t_core.cpp:440](../../cihaz_kontrol/host_test/t_core.cpp#L440) | <code>printf("\nSONUC: %d dogrulama gecti, %d basarisiz\n", g_pass, g_fail);</code> | Her test "SONUC: N dogrulama gecti, M basarisiz" satırı yazar; çıkış kodu 0 = hepsi geçti |

**Olası nedenler**
- Visual Studio sürümü/yolu farklı (VCVARS verilmedi)
- cihaz_kontrol bir kez PlatformIO ile derlenmedi: ArduinoJson yolu yok
- Node.js yok: t_core için vektör üretilemez
- Firmware başlığı değişti ve test beklentisi eski: gerçek bir gerileme olabilir

**Adım adım kontrol**
- cd cihaz_kontrol/host_test && python run_all.py
- Önce pio run -e lolin_c3_mini ile kütüphaneleri indirin
- Testler cihaz davranışını (röle, Wi-Fi, OTA rollback, gerçek ağ) doğrulamaz; sahada SAHA_KONTROL_LISTESI.md uygulanır

**Komutlar**
```bash
cd cihaz_kontrol/host_test && python run_all.py
```

**Bkz.:** [test-firmware-host-derleme](50-arac-test-ve-surec.md#test-firmware-host-derleme), [test-yerel-kontrol-v2](50-arac-test-ve-surec.md#test-yerel-kontrol-v2)

<a id="cihaz-kok-sertifika-suresi"></a>
### cihaz-kok-sertifika-suresi · Tüm cihazlar aynı gün MQTT ve OTA için TLS hatası vermeye başladı (kök sertifika değişti ya da süresi doldu)

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [cihaz_kontrol/include/tls_kok_sertifika.h:4](../../cihaz_kontrol/include/tls_kok_sertifika.h#L4) | <code>inline const char TLS_ROOT_CA[] PROGMEM = R"EOF(</code> | Gömülü tek kök CA; MQTT, OTA manifesti ve OTA indirmesi hepsi bunu kullanır |
| [cihaz_kontrol/include/mqtt_baglanti.h:584](../../cihaz_kontrol/include/mqtt_baglanti.h#L584) | <code>espClientSecure.setCACert(TLS_ROOT_CA);</code> | MQTT TLS doğrulaması; kök değişirse hiçbir cihaz bağlanamaz |
| [cihaz_kontrol/include/ota_guncelleme.h:357](../../cihaz_kontrol/include/ota_guncelleme.h#L357) | <code>otaClient.setCACert(TLS_ROOT_CA);</code> | OTA da aynı kökle doğrular: kök bozulursa OTA ile düzeltme yapılamaz |

**Olası nedenler**
- Sunucu zinciri farklı bir köke taşındı (ISRG Root X1 yerine başka kök): cihaz doğrulayamaz
- Kök CA 2035-06-04 tarihinde sona erer (gömülü sertifikanın bitiş tarihi)
- Saat yanlışsa da doğrulama başarısız olur (cihaz-saat-ntp-yok)

**Adım adım kontrol**
- Sunucu sertifika zincirini dışarıdan inceleyin (cihaz-mqtt-tls-hatasi komutu)
- Zincir değiştiyse yeni kök CA ile firmware üretip USB ile yüklemek gerekir; OTA çalışmaz çünkü indirme de TLS'e bağlıdır
- Kök değişikliğini planlarken eski + yeni kökü aynı pakette taşıyan geçiş sürümü önceden OTA ile dağıtın

**Bkz.:** [cihaz-mqtt-tls-hatasi](#cihaz-mqtt-tls-hatasi), [cihaz-ota-manifest-hatasi](#cihaz-ota-manifest-hatasi), [cihaz-saat-ntp-yok](#cihaz-saat-ntp-yok)

<a id="cihaz-ota-imza-reddi"></a>
### cihaz-ota-imza-reddi · Cihaz OTA güncellemesini kurmuyor: OTA durumu ya da ota_failed ayrıntısı "imza: ..." ("imza: dosya yok", "imza: dogrulama basarisiz", "imza: anahtar yerlestirilmemis", "imza: bicim gecersiz")

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [cihaz_kontrol/include/ota_guncelleme.h:561](../../cihaz_kontrol/include/ota_guncelleme.h#L561) | <code>inline String otaImzaAl(const OtaImzaIstegi&amp; istek, uint8_t imza[OTA_IMZA_BOYUT], bool&amp; a…</code> | Önce imza alınır: manifestte signature varsa o, yoksa .sig dosyası (aracın JSON'u ya da çıplak imza); imza yoksa paket HİÇ indirilmez |
| [cihaz_kontrol/include/ota_guncelleme.h:518](../../cihaz_kontrol/include/ota_guncelleme.h#L518) | <code>inline bool otaImzaDosyasiCozumle(const uint8_t* veri, size_t n, uint8_t imza[OTA_IMZA_BO…</code> | .sig JSON'undan yalnız format (KAPI-OTA-IMZA-V1), algorithm (Ed25519) ve 128 hane hex signature okunur; başka biçim reddedilir |
| [cihaz_kontrol/include/ota_guncelleme.h:701](../../cihaz_kontrol/include/ota_guncelleme.h#L701) | <code>const String imzaSonuc = otaImzaYukunuDogrula(imza, imzaIstegi, static_cast&lt;uint32_t&gt;(aki…</code> | SHA-256 tuttuktan sonra, Update.end'den ÖNCE imza doğrulanır; geçersizse Update.abort ve boot bölümü değişmez |
| [cihaz_kontrol/include/ota_guncelleme.h:613](../../cihaz_kontrol/include/ota_guncelleme.h#L613) | <code>inline String otaImzaYukunuDogrula(const uint8_t imza[OTA_IMZA_BOYUT], const OtaImzaIsteg…</code> | Yük cihazın KENDİ bildiği değerlerle (hedef, manifest sürümü, indirilen bayt sayısı, hesaplanan SHA-256 [+ rollback_max]) kurulur |
| [cihaz_kontrol/include/ota_guncelleme.h:955](../../cihaz_kontrol/include/ota_guncelleme.h#L955) | <code>Serial.println("OTA GUVENLIK: paket imzasi dogrulanamadi; guncelleme REDDEDILDI (boot bol…</code> | Reddedilen paket seriye Türkçe güvenlik satırı olarak yazılır |
| [cihaz_kontrol/include/ota_imza.h:298](../../cihaz_kontrol/include/ota_imza.h#L298) | <code>inline OtaImzaSonuc otaImzaDogrula(const uint8_t imza[OTA_IMZA_BOYUT], const uint8_t* ana…</code> | Anahtar HAZIR değilse hiçbir imza geçerli sayılmaz; yük kurulur ve Ed25519 doğrulanır |
| [cihaz_kontrol/include/ota_public_key.h:30](../../cihaz_kontrol/include/ota_public_key.h#L30) | <code>inline constexpr uint8_t OTA_IMZA_GENEL_ANAHTAR[32] = {</code> | Gömülü genel anahtar: teslimde YER TUTUCU (hiçbir paket kurulmaz); gerçek anahtar cihaz_kontrol/tools/ota_anahtar.mjs yaz ile yazılır |

**Olası nedenler**
- "imza: dosya yok (http 404/403/410)": paket imzasız ya da sunucuda .sig yok (imzasız paket köprü sürümden sonra KURULMAZ; bu beklenen korumadır)
- "imza: dogrulama basarisiz": imza gömülü anahtarla bu hedef/sürüm/boyut/SHA-256 için atılmamış (başka anahtar, manifest sürümü ≠ imzalanan sürüm, paket imzadan sonra değişti, yanlış hedef); rollback_max/allow_downgrade uyuşmazlığı da böyle görünür
- "imza: anahtar yerlestirilmemis": gömülü genel anahtar YER TUTUCU ya da geçersiz (yer tutuculu sürüm yayınlanmış: o cihazlar bir daha OTA ile güncellenemez, USB gerekir)
- "imza: bicim gecersiz" / "imza: dosya cok buyuk": .sig ne aracın JSON'u ne de 64 bayt ham / 128 hane hex / 88 karakter base64; dosya 1024 baytı aşıyor
- "imza: dosya alinamadi (http N)": geçici ağ/sunucu hatası (deneme hakkı yanmaz, cihaz yeniden dener)

**Adım adım kontrol**
- Seri açılışta "OTA imza anahtari: HAZIR (Ed25519, zorunlu); parmak izi <16 hane>" satırı olmalı; parmak izi imzalama aracının key_id değeriyle AYNI olmalı (YER TUTUCU/GECERSIZ yazıyorsa kart hiçbir paketi kurmaz)
- Sunucuda manifest'i cihazın sürümüyle okuyun: signature (128 hane hex) ve version imzalanan sürümle aynı mı; node tools/ota_imza/ota_imza.mjs dogrula <firmware.bin> --genel <genel.pem> --manifest <manifest.json>
- Yayın öncesi ikilide yer tutucu kalmadığını doğrulayın: node cihaz_kontrol/tools/ota_anahtar.mjs kontrol <firmware.bin> <genel_anahtar>
- Ayrıntı, köprü sürüm planı ve hata tablosu: docs/OTA_IMZA_CIHAZ.md bölüm 3 ve docs/OTA_IMZA.md bölüm 6-7

**Günlükte aranacak ifadeler**
- `OTA GUVENLIK: paket imzasi dogrulanamadi`
- `imza: dosya yok`
- `imza: anahtar yerlestirilmemis`
- `imza: dogrulama basarisiz`

**Komutlar**
```bash
curl -s "https://api.gudeteknoloji.com.tr/firmware/esp32-c3/manifest.json?current_version=4.4.0"
curl -s -o /dev/null -w "%{http_code}\n" https://api.gudeteknoloji.com.tr/firmware/esp32-c3/firmware-v4.4.1.bin.sig
```

**İlgili testler:** [cihaz_kontrol/host_test/t_imza.cpp](../../cihaz_kontrol/host_test/t_imza.cpp), [cihaz_kontrol/host_test/t_mqtt.cpp](../../cihaz_kontrol/host_test/t_mqtt.cpp)

**Bkz.:** [cihaz-ota-manifest-hatasi](#cihaz-ota-manifest-hatasi), [cihaz-ota-guncelleme-baslamiyor](#cihaz-ota-guncelleme-baslamiyor), [sunucu-firmware-yukleme-imza](10-sunucu-api.md#sunucu-firmware-yukleme-imza), [arac-ota-imza-araci](50-arac-test-ve-surec.md#arac-ota-imza-araci)

