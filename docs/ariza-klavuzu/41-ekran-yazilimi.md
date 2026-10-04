# Ekran yazılımı — ST7789 ekran, CST816D dokunmatik, QR, UART protokolü

[← Ana sayfa](../ARIZA_KLAVUZU.md) · [İndeks](../ARIZA_KLAVUZU_INDEKS.md) · [Ekler](../ARIZA_KLAVUZU_EKLER.md) · [Hata mesajları](../ARIZA_KLAVUZU_HATA_MESAJLARI.md)

> ⚠ **Doğrulanmadı:** bu bölümün açıklamaları (olası nedenler, adımlar) ajanlarca kodu okuyarak yazıldı ama bağımsız çürütücü incelemeden GEÇMEDİ. `dosya:satır` bağlantıları ise koddan çözülür ve her çalıştırmada denetlenir (güvenilir). Açıklamayı uygulamadan önce bağlantıdaki koda bakarak teyit edin.

Bu bölüm ekran_yazilimi (ESP32-C3, 2,4" 240x320 ST7789 ekran, CST816D dokunmatik) içindir; ana kart (WROOM) ile tek UART hattından satır tabanlı komutlarla konuşur. İlk bakılacak yer ekranın USB seri monitörüdür (115200 baud): "[RX<-WROOM]" ve "[TX->WROOM]" satırları protokolü, "[TOUCH]" satırları dokunmatiği gösterir. KURAL (AGENTS.md): ESP32-C3 sahada çalışır; protokol dosyası iki projede BİREBİR aynı kalmalı, pin ve UART davranışı bozulmamalı. Ana kart tarafı: 40-cihaz-yazilimi bölümü.

## Dosya haritası

| Dosya | Rol |
| --- | --- |
| [ekran_yazilimi/src/main.cpp](../../ekran_yazilimi/src/main.cpp) | setup/loop: UART okuma, PC USB komutları, dokunma yoklama (30 ms), düğme, LED, 2 sn READY isteği |
| [ekran_yazilimi/src/ScreenManager.cpp](../../ekran_yazilimi/src/ScreenManager.cpp) | Ekran durumları, çizim, PIN akışı, QR çizimi ve geri sayım, ana MCU komutlarının işlenmesi |
| [ekran_yazilimi/include/ScreenManager.h](../../ekran_yazilimi/include/ScreenManager.h) | Renkler, durum enumları, süre sabitleri (oturum 20 sn, PIN yanıtı 3 sn, ana MCU sessizliği 45 sn) |
| [ekran_yazilimi/include/config.h](../../ekran_yazilimi/include/config.h) | Pinler (UART 20/21, TFT, dokunmatik 4/5/2/3, LED 1, düğme 9) ve DISPLAY_FIRMWARE_VERSION |
| [ekran_yazilimi/include/cst816d_touch.h](../../ekran_yazilimi/include/cst816d_touch.h) | CST816D I2C sürücüsü (adres 0x15, yeniden deneme, koordinat okuma) |
| [ekran_yazilimi/include/display_protocol.h](../../ekran_yazilimi/include/display_protocol.h) | UART komut sabitleri; cihaz_kontrol/include/display_protocol.h ile BİREBİR aynı olmalı |
| [ekran_yazilimi/platformio.ini](../../ekran_yazilimi/platformio.ini) | Derleme ortamı esp32c3_display: TFT_eSPI bayrakları, USB CDC, upload_port COM8, kütüphaneler |
| [ekran_yazilimi/firmware_releases/index.json](../../ekran_yazilimi/firmware_releases/index.json) | Sürüm dizini: aracın "Sürüm oluştur" adımının ürettiği kayıtlar (id, sürüm, SHA-256) |
| [ekran_yazilimi/firmware_releases/20260917_115500_v1_0_2/manifest.json](../../ekran_yazilimi/firmware_releases/20260917_115500_v1_0_2/manifest.json) | Bir sürümün manifesti: firmware/bootloader/partitions yolları ve SHA-256/MD5 |

## Bu bölümdeki girişler (20)

- [ekran-siyah-bos](#ekran-siyah-bos) — Ekran hiç yanmıyor ya da yalnızca beyaz/siyah boş görünüyor; yazı ve QR yok
- [ekran-yeniden-baslama-dongusu](#ekran-yeniden-baslama-dongusu) — Ekran kartı sürekli yeniden başlıyor ya da açılışta takılıyor; seri monitörde başlık tekrar ediyor
- [ekran-dokunmatik-yok](#ekran-dokunmatik-yok) — Dokunmatik hiç yanıt vermiyor; AYAR ve PIN tuşları çalışmıyor ("CST816D not detected")
- [ekran-dokunma-yanlis-koordinat](#ekran-dokunma-yanlis-koordinat) — Dokunmatik çalışıyor ama dokunulan yer ile basılan tuş uyuşmuyor (yanlış tuş, kayık dokunma alanı)
- [ekran-dokunma-tekrar-tetikleme](#ekran-dokunma-tekrar-tetikleme) — Tek dokunuş birden fazla tuş basımı sayılıyor ya da hızlı ardışık dokunuşlar yutuluyor
- [ekran-pin-ekrani-tus-yanit-yok](#ekran-pin-ekrani-tus-yanit-yok) — Yönetici PIN ekranında rakamlar girilmiyor ya da 6. haneden sonra "Dogrulaniyor..." / "Yanit yok, tekrar deneyin" görünüyor
- [ekran-pin-hatali-kilitli-nopin](#ekran-pin-hatali-kilitli-nopin) — PIN ekranı "Hatali PIN (kalan: N)", "Cok fazla hatali deneme / Kilitli: N sn" ya da "PIN tanimli degil" diyor
- [ekran-yonetici-oturum-20sn](#ekran-yonetici-oturum-20sn) — Yönetici menüsü kendiliğinden kapanıyor / ana ekrana dönüyor; "Kapıyı Aç" onayında "Isleniyor..." sonra ana ekran
- [ekran-fiziksel-dugme-kapi-acmaz](#ekran-fiziksel-dugme-kapi-acmaz) — Ekran kartındaki fiziksel düğmeye basılınca kapı açılmıyor
- [ekran-qr-gorunmuyor](#ekran-qr-gorunmuyor) — Ana ekranda QR kod yok, "AHBU:DOOR:READY" yer tutucusu ya da "QR HATA" görünüyor
- [ekran-qr-yenilenmiyor](#ekran-qr-yenilenmiyor) — Ekrandaki QR 30 sn sonra yenilenmiyor ya da "Kalan Sure: 00 sn" sonrası aynı QR kalıyor; uygulama okutunca süresi doldu diyor
- [ekran-qr-boyut-okunmuyor](#ekran-qr-boyut-okunmuyor) — Ekrandaki QR telefonla/GM60 ile zor okunuyor ya da çok küçük/silik görünüyor
- [ekran-ana-kart-sessiz](#ekran-ana-kart-sessiz) — Ekranda üst çubukta "WiFi YOK" / "Bulut YOK" yanıyor ya da QR kayboluyor, oysa ana kart çalışıyor
- [ekran-uart-protokol-uyusmazligi](#ekran-uart-protokol-uyusmazligi) — Ekran ile ana kart birbirini anlamıyor: komutlar işlenmiyor, "Bilinmeyen komut" ya da eski/yeni yazılım uyuşmazlığı
- [ekran-uart-satir-cok-uzun](#ekran-uart-satir-cok-uzun) — Ekran seri monitöründe "satir cok uzun, sonraki satir sonuna kadar atlaniyor"; bazı komutlar kayboluyor
- [ekran-kapi-acildi-denied-ekran](#ekran-kapi-acildi-denied-ekran) — Kapı açıldı/Geçersiz QR ekranı gelmiyor, takılı kalıyor ya da "QR Okunuyor..." ekranında kalıyor
- [ekran-turkce-karakter-yazi](#ekran-turkce-karakter-yazi) — Ekranda Türkçe karakterler (ğ, ş, ı, İ) görünmüyor ya da yazılar ASCII ("GECIS", "ACILDI") yazılmış
- [ekran-baglanti-durumu-bos](#ekran-baglanti-durumu-bos) — Yönetici menüsündeki "Baglanti Durumu" ya da "Cihaz Bilgisi" ekranında değerler "-" / "Kopuk" görünüyor
- [ekran-surum-derleme-yukleme](#ekran-surum-derleme-yukleme) — Ekran firmware derlenmiyor ya da yüklenmiyor (COM8, PlatformIO, TFT_eSPI hatası); yükleme sonrası ekran açılmıyor
- [ekran-surum-uyusmazligi](#ekran-surum-uyusmazligi) — Ekran firmware sürümü beklenenle uyuşmuyor ("Ekran FW" farklı) ya da sürüm kayıtlarında (firmware_releases) görünmüyor

## Girişler

<a id="ekran-siyah-bos"></a>
### ekran-siyah-bos · Ekran hiç yanmıyor ya da yalnızca beyaz/siyah boş görünüyor; yazı ve QR yok

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [ekran_yazilimi/src/ScreenManager.cpp:43](../../ekran_yazilimi/src/ScreenManager.cpp#L43) | <code>void ScreenManager::begin() {</code> | Açılış: arka ışık pini HIGH, tft.init(), döndürme 0 (dikey), ana ekran çizimi |
| [ekran_yazilimi/src/ScreenManager.cpp:45](../../ekran_yazilimi/src/ScreenManager.cpp#L45) | <code>pinMode(TFT_BL, OUTPUT);</code> | Arka ışık TFT_BL (GPIO0) pininden açılır; bağlantı/pin yanlışsa ekran karanlık kalır |
| [ekran_yazilimi/include/config.h:25](../../ekran_yazilimi/include/config.h#L25) | <code>#define TFT_MOSI 7</code> | TFT pinleri (MOSI 7, SCLK 6, DC 10, RST 8, BL 0); platformio.ini bayrakları öncelikli |
| [ekran_yazilimi/platformio.ini:14](../../ekran_yazilimi/platformio.ini#L14) | <code>-D ST7789_DRIVER=1</code> | Sürücü ve renk/ters çevirme bayrakları (TFT_RGB_ORDER, TFT_INVERSION_ON): yanlışsa renkler tersine görünür |
| [ekran_yazilimi/platformio.ini:26](../../ekran_yazilimi/platformio.ini#L26) | <code>-D SPI_FREQUENCY=20000000</code> | SPI hızı 20 MHz; uzun/gevşek kabloda düşürmek gerekebilir |

**Olası nedenler**
- Arka ışık pini (GPIO0) bağlı değil ya da ekran modülü farklı pinoutlu
- TFT_eSPI bayrakları (pin/sürücü) kartla uyuşmuyor; yanlış ortamla derlenip yüklenmiş
- Besleme yetersiz / ekran flexi gevşek
- Renkler ters (TFT_RGB_ORDER / TFT_INVERSION_ON): "boş" değil, ters renkli görünüyor olabilir

**Adım adım kontrol**
- USB seri monitörü açın: "[INIT] Display controller ready." görünüyor mu (kart çalışıyor ama ekran yanmıyorsa donanım/pin)
- Ekran firmware ortamı esp32c3_display ile mi yüklendi (pio run -d ekran_yazilimi -e esp32c3_display)
- Pinleri config.h ve platformio.ini ile modül şemasında karşılaştırın

**Günlükte aranacak ifadeler**
- `[INIT] Display controller ready.`

**Komutlar**
```bash
node tools/klavuz/build.mjs --where "TFT_BL"
```

**Bkz.:** [ekran-surum-derleme-yukleme](#ekran-surum-derleme-yukleme), [ekran-yeniden-baslama-dongusu](#ekran-yeniden-baslama-dongusu)

<a id="ekran-yeniden-baslama-dongusu"></a>
### ekran-yeniden-baslama-dongusu · Ekran kartı sürekli yeniden başlıyor ya da açılışta takılıyor; seri monitörde başlık tekrar ediyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [ekran_yazilimi/src/main.cpp:190](../../ekran_yazilimi/src/main.cpp#L190) | <code>void setup() {</code> | Açılış sırası: Serial, UART1, pinler, screen.begin(), dokunmatik begin, DISP_READY |
| [ekran_yazilimi/src/main.cpp:197](../../ekran_yazilimi/src/main.cpp#L197) | <code>Serial.setTxTimeoutMs(0);</code> | USB CDC TX bloklamasını kapatır; kaldırılırsa seri monitör takılıyken UART/dokunma ~100 ms donabilir (BOZMAYIN) |
| [ekran_yazilimi/platformio.ini:12](../../ekran_yazilimi/platformio.ini#L12) | <code>-D ARDUINO_USB_CDC_ON_BOOT=1</code> | Serial USB CDC üzerinden; fiziksel UART için Serial1 kullanılır |
| [ekran_yazilimi/src/main.cpp:14](../../ekran_yazilimi/src/main.cpp#L14) | <code>HardwareSerial &amp;wroomSerial = Serial1;</code> | WROOM hattı Serial1 (GPIO20/21); Serial0 USB CDC'ye düştüğü için ana kart hattı için kullanılmaz |

**Olası nedenler**
- Besleme zayıf (ekran + C3 akımı): sıfırlama donanım kaynaklıdır; ekran yazılımında kendiliğinden yeniden başlatma çağrısı yoktur
- Yanlış kart ortamı ile yüklenmiş firmware (ör. ana kart ortamı); esp32c3_display dışında bir ortamla yüklenmemeli
- Açılışta takılma: "[INIT] Display controller ready." satırı hiç görünmüyorsa takılan yer setup sırasındadır (screen.begin / tft.init / touch.begin)

**Adım adım kontrol**
- Seri monitörde açılış başlığı (ST7789 Display Controller) dakikada kaç kez tekrarlıyor; "[INIT] Display controller ready." satırına ulaşıyor mu
- Besleme gerilimini ölçün; ana kartın 5 V hattı ve GND ortak mı
- Son yüklenen sürümü aracın Sürüm/Yükle adımıyla yeniden yükleyin

**Günlükte aranacak ifadeler**
- `ST7789 Display Controller`
- `[INIT] Display controller ready.`

**Bkz.:** [ekran-siyah-bos](#ekran-siyah-bos), [ekran-surum-derleme-yukleme](#ekran-surum-derleme-yukleme)

<a id="ekran-dokunmatik-yok"></a>
### ekran-dokunmatik-yok · Dokunmatik hiç yanıt vermiyor; AYAR ve PIN tuşları çalışmıyor ("CST816D not detected")

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [ekran_yazilimi/include/cst816d_touch.h:16](../../ekran_yazilimi/include/cst816d_touch.h#L16) | <code>bool begin(int sda, int scl, int rst = -1, int irq = -1, bool verbose = true) {</code> | RST darbesi + I2C başlatma + 0x15 adres yoklaması; başarısızsa _initialized=false |
| [ekran_yazilimi/include/cst816d_touch.h:49](../../ekran_yazilimi/include/cst816d_touch.h#L49) | <code>Serial.println("[TOUCH] CST816D not detected (fallback to button input)");</code> | Algılanamadı mesajı (yalnız açılışta bir kez yazılır): kablo/pin/adres sorunu. Mesaj "düğmeye düşer" dese de fiziksel düğme yalnız BTN_OPEN yollar ve ana kart bunu yok sayar; dokunmatiksiz PIN/menü açılamaz |
| [ekran_yazilimi/src/main.cpp:112](../../ekran_yazilimi/src/main.cpp#L112) | <code>constexpr unsigned long TOUCH_REINIT_INTERVAL_MS = 5000;</code> | Açılışta bulunamazsa 5 sn'de bir yeniden dener (begin ~60 ms bloklar) |
| [ekran_yazilimi/src/main.cpp:115](../../ekran_yazilimi/src/main.cpp#L115) | <code>if (!touch.isAvailable()) {</code> | Dokunmatik hazır değilken yoklama atlanır, yeniden deneme yapılır; başarıda TOUCH_READY gönderilir |
| [ekran_yazilimi/include/config.h:46](../../ekran_yazilimi/include/config.h#L46) | <code>constexpr int TOUCH_SDA_PIN = 4;</code> | Dokunmatik pinleri: SDA 4, SCL 5, RST 2, INT 3 |

**Olası nedenler**
- I2C kablosu (SDA/SCL) gevşek ya da ters; RST/INT bağlı değil
- Panel farklı I2C adresli (kod yalnız 0x15 yoklar)
- Açılışta kontrol çipi geç hazır oldu: 5 sn içinde kendini toplamalı
- Başka bir şey I2C hattını tutuyor (Wire.end/begin yeniden denemesi sıfırlar)

**Adım adım kontrol**
- Seri monitörde "[TOUCH] CST816D touch controller initialized at 0x15" görünüyor mu
- 5 sn bekleyin: yeniden deneme başarılı olursa ana karta TOUCH_READY gider; yeniden denemelerde "not detected" satırı tekrar yazılmaz (yalnız başarı satırı yazılır)
- Pin eşlemesini config.h ile kart şemasında karşılaştırın

**Günlükte aranacak ifadeler**
- `[TOUCH] CST816D touch controller initialized at 0x15`
- `[TOUCH] CST816D not detected (fallback to button input)`

**Bkz.:** [ekran-dokunma-yanlis-koordinat](#ekran-dokunma-yanlis-koordinat), [ekran-dokunma-tekrar-tetikleme](#ekran-dokunma-tekrar-tetikleme)

<a id="ekran-dokunma-yanlis-koordinat"></a>
### ekran-dokunma-yanlis-koordinat · Dokunmatik çalışıyor ama dokunulan yer ile basılan tuş uyuşmuyor (yanlış tuş, kayık dokunma alanı)

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [ekran_yazilimi/include/cst816d_touch.h:77](../../ekran_yazilimi/include/cst816d_touch.h#L77) | <code>x = ((xHigh &amp; 0x0F) &lt;&lt; 8) &#124; xLow;</code> | Ham koordinat 12 bit okunur; döndürme/ters çevirme/kalibrasyon YOK |
| [ekran_yazilimi/include/cst816d_touch.h:81](../../ekran_yazilimi/include/cst816d_touch.h#L81) | <code>x = constrain(x, 0, 240);</code> | Koordinatlar 240x320 sınırına kırpılır |
| [ekran_yazilimi/src/ScreenManager.cpp:951](../../ekran_yazilimi/src/ScreenManager.cpp#L951) | <code>void ScreenManager::onTouch(int16_t x, int16_t y) {</code> | Dokunma bölgeleri ekran durumuna göre sabit dikdörtgenlerle denetlenir |
| [ekran_yazilimi/src/ScreenManager.cpp:977](../../ekran_yazilimi/src/ScreenManager.cpp#L977) | <code>int bx = 18 + (c * 72);</code> | PIN tuş ızgarası dokunma tarafı (çizimdeki 18/72 ve 82/50 ile aynı olmalı) |
| [ekran_yazilimi/src/ScreenManager.cpp:49](../../ekran_yazilimi/src/ScreenManager.cpp#L49) | <code>tft.setRotation(0); // Portrait 240x320</code> | Ekran dikey (0); döndürme değişirse dokunma bölgeleri uymaz |
| [ekran_yazilimi/src/main.cpp:139](../../ekran_yazilimi/src/main.cpp#L139) | <code>#ifdef AHBU_DEBUG_TOUCH</code> | -D AHBU_DEBUG_TOUCH ile "[TOUCH] Tap at X=.. Y=.." yazdırılır (YALNIZ geliştirme; PIN çıkarılabilir, sahada kapalı kalmalı) |

**Olası nedenler**
- Çizim koordinatı ile dokunma bölgesi (onTouch) ayrı sabitlerle yazılmış; birini değiştirip diğerini unutmak kayma yapar
- Panel/ekran yönü değişti (setRotation) ama dokunma haritası aynı kaldı
- Panel farklı donanım sürümü: ham eksenler ters çıkıyor (kodda eksen çevirme yok)

**Adım adım kontrol**
- Geçici olarak -D AHBU_DEBUG_TOUCH ile derleyip köşelere dokunun ve "[TOUCH] Tap" koordinatlarını okuyun; sahaya bu bayraksız yükleyin
- drawAdminPinScreen ve onTouch içindeki tuş ızgarası sabitlerini karşılaştırın

**Bkz.:** [ekran-dokunmatik-yok](#ekran-dokunmatik-yok), [ekran-pin-ekrani-tus-yanit-yok](#ekran-pin-ekrani-tus-yanit-yok)

<a id="ekran-dokunma-tekrar-tetikleme"></a>
### ekran-dokunma-tekrar-tetikleme · Tek dokunuş birden fazla tuş basımı sayılıyor ya da hızlı ardışık dokunuşlar yutuluyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [ekran_yazilimi/src/main.cpp:114](../../ekran_yazilimi/src/main.cpp#L114) | <code>void processTouchInput() {</code> | Yoklama ~30 Hz; parmak-inme algılama (wasTouching) ve 350 ms debounce |
| [ekran_yazilimi/src/main.cpp:137](../../ekran_yazilimi/src/main.cpp#L137) | <code>if (!wasTouching &amp;&amp; (millis() - lastTouchActionMs &gt; 350)) {</code> | İki dokunma arası en az 350 ms; hızlı yazılan PIN tuşları yutulabilir (bilinçli sınır) |
| [ekran_yazilimi/src/main.cpp:129](../../ekran_yazilimi/src/main.cpp#L129) | <code>if (millis() - lastTouchPollMs &lt; 30) return;</code> | 30 ms yoklama aralığı |
| [ekran_yazilimi/include/cst816d_touch.h:75](../../ekran_yazilimi/include/cst816d_touch.h#L75) | <code>if (fingerNum == 0) return false;</code> | Parmak yoksa dokunma yok sayılır |

**Olası nedenler**
- 350 ms debounce: 6 haneli PIN çok hızlı girilirse bazı basımlar kaybolur
- Parmak basılı tutulursa yalnızca ilk inişte tetiklenir (wasTouching), basılı tutma tekrar üretmez
- Panel gürültülü: kısa kopma sonrası yeni iniş gibi görünür

**Adım adım kontrol**
- Tuşlara her seferinde yarım saniye arayla basarak deneyin
- Kablo/besleme gürültüsünü kontrol edin (gürültüde sahte inişler olur)

**Bkz.:** [ekran-dokunmatik-yok](#ekran-dokunmatik-yok)

<a id="ekran-pin-ekrani-tus-yanit-yok"></a>
### ekran-pin-ekrani-tus-yanit-yok · Yönetici PIN ekranında rakamlar girilmiyor ya da 6. haneden sonra "Dogrulaniyor..." / "Yanit yok, tekrar deneyin" görünüyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [ekran_yazilimi/src/ScreenManager.cpp:99](../../ekran_yazilimi/src/ScreenManager.cpp#L99) | <code>void ScreenManager::submitAdminPin() {</code> | 6 hane tamamlanınca ADMIN_AUTH\|<pin> ana karta gider; PIN ekranda DOĞRULANMAZ |
| [ekran_yazilimi/src/ScreenManager.cpp:186](../../ekran_yazilimi/src/ScreenManager.cpp#L186) | <code>if (_pinWaiting &amp;&amp; now - _pinWaitStartMs &gt;= ADMIN_AUTH_TIMEOUT_MS) {</code> | Ana karttan 3 sn içinde yanıt gelmezse "Yanit yok" bildirimi (NOTICE_TIMEOUT) ve PIN silinir |
| [ekran_yazilimi/src/ScreenManager.cpp:985](../../ekran_yazilimi/src/ScreenManager.cpp#L985) | <code>if (adminInputBlocked() &#124;&#124; _pinWaiting) {</code> | PIN yok, kilitli ya da doğrulama sürerken tuş girişi yok sayılır (yalnız Geri çalışır) |
| [ekran_yazilimi/src/ScreenManager.cpp:109](../../ekran_yazilimi/src/ScreenManager.cpp#L109) | <code>void ScreenManager::handleAdminOk() {</code> | ADMIN_OK gelince menü açılır; yalnız PIN ekranında ve yanıt beklenirken kabul edilir |
| [cihaz_kontrol/src/display_uart.cpp:133](../../cihaz_kontrol/src/display_uart.cpp#L133) | <code>static void handleDisplayCommand(const String &amp;rawCmd) {</code> | Ana kart tarafı: ADMIN_AUTH\|pin burada işlenir ve ADMIN_OK / ADMIN_DENIED döner |
| [cihaz_kontrol/src/display_uart.cpp:152](../../cihaz_kontrol/src/display_uart.cpp#L152) | <code>Serial.println("[DISPLAY] UYARI: PIN'siz ADMIN komutu reddedildi (ekran yazilimi guncel o…</code> | Eski ekran yazılımı PIN'siz ADMIN_AUTH yollarsa ana kart reddeder |

**Olası nedenler**
- Ana kart (WROOM) UART üzerinden yanıt vermiyor: kablo (TX/RX çapraz), ana kart yeniden başlıyor ya da takılı
- Ana kart yazılımı eski/yeni: protokol uyuşmazlığı
- PIN ekranında kilit (LOCKED) ya da PIN tanımsız (NOPIN) olduğu için tuş takımı soluk ve kapalı
- 350 ms debounce nedeniyle çok hızlı girilen basımlar yutuldu (bkz. ekran-dokunma-tekrar-tetikleme)

**Adım adım kontrol**
- Ekran USB seri monitöründe "[TX->WROOM] ADMIN_AUTH|***" satırı çıkıyor mu; ardından "[RX<-WROOM]" yanıtı geliyor mu
- Ana kart seri çıkışında "[DISPLAY] RX" satırı görünüyor mu
- UART kablosu: ekran GPIO21(TX) -> WROOM GPIO32(RX), ekran GPIO20(RX) <- WROOM GPIO33(TX), ortak GND

**Günlükte aranacak ifadeler**
- `[TX->WROOM] `
- `[RX<-WROOM] `

**Bkz.:** [ekran-pin-hatali-kilitli-nopin](#ekran-pin-hatali-kilitli-nopin), [ekran-uart-protokol-uyusmazligi](#ekran-uart-protokol-uyusmazligi), [ekran-ana-kart-sessiz](#ekran-ana-kart-sessiz)

<a id="ekran-pin-hatali-kilitli-nopin"></a>
### ekran-pin-hatali-kilitli-nopin · PIN ekranı "Hatali PIN (kalan: N)", "Cok fazla hatali deneme / Kilitli: N sn" ya da "PIN tanimli degil" diyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [ekran_yazilimi/src/ScreenManager.cpp:122](../../ekran_yazilimi/src/ScreenManager.cpp#L122) | <code>void ScreenManager::handleAdminDenied(const String&amp; rest) {</code> | ADMIN_DENIED\|BAD\|kalan, \|LOCKED\|sn, \|NOPIN, \|BUSY ayrıştırılır; kilit süresi ana karttan gelir |
| [ekran_yazilimi/src/ScreenManager.cpp:156](../../ekran_yazilimi/src/ScreenManager.cpp#L156) | <code>void ScreenManager::handleAdminState(const String&amp; rest) {</code> | PIN ekranı açılınca REQ_ADMIN yanıtı (READY/NOPIN/LOCKED) ile bildirimi günceller |
| [ekran_yazilimi/src/ScreenManager.cpp:484](../../ekran_yazilimi/src/ScreenManager.cpp#L484) | <code>void ScreenManager::drawAdminPinMessage() {</code> | Ekrandaki tüm PIN mesaj metinlerinin kaynağı |
| [ekran_yazilimi/src/ScreenManager.cpp:81](../../ekran_yazilimi/src/ScreenManager.cpp#L81) | <code>bool ScreenManager::adminInputBlocked() const {</code> | NOPIN ya da süren kilit tuş takımını kapatır |
| [cihaz_kontrol/src/display_uart.cpp:81](../../cihaz_kontrol/src/display_uart.cpp#L81) | <code>static void displayAdminDurumuGonder() {</code> | Ana kartta PIN durumu (tanımsız/kilitli/hazır) ekrana buradan bildirilir |
| [cihaz_kontrol/include/admin_pin.h:28](../../cihaz_kontrol/include/admin_pin.h#L28) | <code>ADMIN_PIN_YANLIS = 1,</code> | PIN doğrulama sonuçları ve kilit mantığı ana karttadır (NVS) |

**Olası nedenler**
- PIN yanlış girildi; kilit sayacı ana kartta tutulur (ekran saymaz): 5 ardışık hatada 5 dk kilit, süre dolunca açılır (admin_pin.h)
- Cihazda yönetici PIN'i hiç tanımlanmamış (NOPIN): PIN ana karta MQTT admin_pin_config eylemiyle ya da seri ADMINPIN:NNNNNN satırıyla atanır; zayıf PIN reddedilir
- "Role mesgul": ana kart ADMIN_OPEN'da PIN'i doğruladı ama röleyi tetikleyemedi (systemAdminKapiAc false) ve BUSY döndü - biraz sonra tekrar deneyin
- Eski ekran yazılımı PIN'siz ADMIN_AUTH yollarsa ana kart reddeder ve ekranda "Hatali PIN (kalan: 0)" görünür

**Adım adım kontrol**
- Kilit geri sayımı ekranda "Kilitli: N sn" olarak akar; süre bitince tuşlara basılabilir (tuş yazıları ilk basışa kadar soluk kalabilir: kilit bitince yalnız mesaj satırı yenilenir)
- Ana kart seri çıkışında "?" yazıp yönetici PIN'inin tanımlı olup olmadığına bakın (uygulama/sunucuda PIN ayarı yoktur; atama MQTT eylemi ya da seri satırdır)
- Ana kart tarafı için cihaz-admin-pin-tanimsiz-reddedildi ve cihaz-admin-pin-kilitli girişlerine bakın

**Bkz.:** [ekran-pin-ekrani-tus-yanit-yok](#ekran-pin-ekrani-tus-yanit-yok), [ekran-yonetici-oturum-20sn](#ekran-yonetici-oturum-20sn), [cihaz-admin-pin-tanimsiz-reddedildi](40-cihaz-yazilimi.md#cihaz-admin-pin-tanimsiz-reddedildi), [cihaz-admin-pin-kilitli](40-cihaz-yazilimi.md#cihaz-admin-pin-kilitli)

<a id="ekran-yonetici-oturum-20sn"></a>
### ekran-yonetici-oturum-20sn · Yönetici menüsü kendiliğinden kapanıyor / ana ekrana dönüyor; "Kapıyı Aç" onayında "Isleniyor..." sonra ana ekran

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [ekran_yazilimi/include/ScreenManager.h:105](../../ekran_yazilimi/include/ScreenManager.h#L105) | <code>static constexpr unsigned long ADMIN_SESSION_MAX_MS = 20000UL;  // menü oturumu MUTLAK 20…</code> | Menü oturumu MUTLAK 20 sn; dokunma uzatmaz (güvenlik kuralı) |
| [ekran_yazilimi/src/ScreenManager.cpp:179](../../ekran_yazilimi/src/ScreenManager.cpp#L179) | <code>if (_adminSessionStartMs != 0 &amp;&amp; now - _adminSessionStartMs &gt;= ADMIN_SESSION_MAX_MS) {</code> | Süre dolunca oturum biter ve ana ekran gelir |
| [ekran_yazilimi/src/ScreenManager.cpp:205](../../ekran_yazilimi/src/ScreenManager.cpp#L205) | <code>if (_currentState != STATE_HOME &amp;&amp; (now - _lastActivityMs &gt;= 30000UL)) {</code> | Ana ekran dışındaki ekranlar 30 sn dokunulmazsa ana ekrana döner |
| [ekran_yazilimi/src/ScreenManager.cpp:1055](../../ekran_yazilimi/src/ScreenManager.cpp#L1055) | <code>String cmd = String(CMD_ADMIN_OPEN) + "&#124;" + _sessionPin;</code> | "AC" onayı: ana karta ADMIN_OPEN\|pin gider ve PIN RAM'den silinir; yanıt (DOOR_OPENED/ADMIN_DENIED) beklenir |
| [ekran_yazilimi/src/ScreenManager.cpp:1061](../../ekran_yazilimi/src/ScreenManager.cpp#L1061) | <code>_autoReturnTimeoutMs = 4000; // yanıt (DOOR_OPENED / ADMIN_DENIED) gelmezse ana ekrana dön</code> | Yanıt 4 sn içinde gelmezse ana ekrana dönülür |
| [cihaz_kontrol/src/display_uart.cpp:125](../../cihaz_kontrol/src/display_uart.cpp#L125) | <code>Serial.println("[DISPLAY] Yonetici PIN dogrulandi -&gt; role tetiklendi");</code> | Ana kart ADMIN_OPEN'ı doğrularsa röleyi tetikler ve DOOR_OPENED döner |

**Olası nedenler**
- Tasarım: oturum 20 sn mutlaktır, menüde gezinirken dolması normal
- Kapı açma onayı sonrası yanıt gelmedi: ana kart UART yanıtı vermedi ya da PIN reddedildi
- Ana karttaki röle meşgul (BUSY) sayılırsa PIN ekranına dönülür ve "Role mesgul" görünür

**Adım adım kontrol**
- Ekranın altındaki "Oturum: N sn" göstergesini izleyin
- Seri monitörde "[TX->WROOM] ADMIN_OPEN|***" sonrasında "[RX<-WROOM] DOOR_OPENED" gelip gelmediğine bakın

**Günlükte aranacak ifadeler**
- `[DISPLAY] Yonetici PIN dogrulandi -> role tetiklendi`

**Bkz.:** [ekran-pin-hatali-kilitli-nopin](#ekran-pin-hatali-kilitli-nopin), [ekran-kapi-acildi-denied-ekran](#ekran-kapi-acildi-denied-ekran)

<a id="ekran-fiziksel-dugme-kapi-acmaz"></a>
### ekran-fiziksel-dugme-kapi-acmaz · Ekran kartındaki fiziksel düğmeye basılınca kapı açılmıyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [ekran_yazilimi/src/main.cpp:166](../../ekran_yazilimi/src/main.cpp#L166) | <code>void processButtonInput() {</code> | Düğme (GPIO9, aktif LOW) 200 ms debounce ile okunur ve screen.onButtonPress() çağrılır |
| [ekran_yazilimi/src/ScreenManager.cpp:1080](../../ekran_yazilimi/src/ScreenManager.cpp#L1080) | <code>sendCommand(CMD_BTN_OPEN);</code> | Ekran yalnızca BTN_OPEN gönderir; kapıyı kendisi açmaz |
| [cihaz_kontrol/src/display_uart.cpp:145](../../cihaz_kontrol/src/display_uart.cpp#L145) | <code>Serial.println("[DISPLAY] UYARI: Yetkisiz ekran kapi acma komutu guvenlik nedeniyle engel…</code> | Ana kart BTN_OPEN ve DOOR_OPEN komutlarını GÜVENLİK gereği yok sayar (bilinçli) |

**Olası nedenler**
- Beklenen davranış: düğme kapı açmaz; ana kart komutu yetkisiz sayar
- Kapı yalnızca geçerli QR ya da PIN ile yönetici menüsünden açılır

**Adım adım kontrol**
- Ana kart seri çıkışında "[DISPLAY] UYARI: Yetkisiz ..." satırını görmek komutun ulaştığını gösterir

**Günlükte aranacak ifadeler**
- `[DISPLAY] UYARI: Yetkisiz ekran kapi acma komutu guvenlik nedeniyle engellendi`
- `[BTN] Physical button pressed`

**Bkz.:** [ekran-yonetici-oturum-20sn](#ekran-yonetici-oturum-20sn)

<a id="ekran-qr-gorunmuyor"></a>
### ekran-qr-gorunmuyor · Ana ekranda QR kod yok, "AHBU:DOOR:READY" yer tutucusu ya da "QR HATA" görünüyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [ekran_yazilimi/src/ScreenManager.cpp:35](../../ekran_yazilimi/src/ScreenManager.cpp#L35) | <code>_qrData("AHBU:DOOR:READY"),</code> | Başlangıç değeri yer tutucudur; gerçek QR ana karttan SHOW_QR\| ile gelmeden geçerli sayılmaz |
| [ekran_yazilimi/include/ScreenManager.h:84](../../ekran_yazilimi/include/ScreenManager.h#L84) | <code>bool hasValidQr() const { return _qrData.length() &gt; 0 &amp;&amp; _qrData != "AHBU:DOOR:READY"; }</code> | Geçerli QR yoksa main.cpp 2 sn'de bir READY gönderip QR ister |
| [ekran_yazilimi/src/main.cpp:240](../../ekran_yazilimi/src/main.cpp#L240) | <code>if (!screen.hasValidQr() &amp;&amp; (millis() - lastQrReqMs &gt;= 2000)) {</code> | QR yokken ana karttan 2 sn'de bir yeniden gönderme istenir |
| [ekran_yazilimi/src/ScreenManager.cpp:1139](../../ekran_yazilimi/src/ScreenManager.cpp#L1139) | <code>} else if (cmd.startsWith(CMD_SHOW_QR_PREFIX)) {</code> | SHOW_QR\| işleyicisi: boş ya da 60 karakterden uzun veri atılır |
| [ekran_yazilimi/src/ScreenManager.cpp:865](../../ekran_yazilimi/src/ScreenManager.cpp#L865) | <code>tft.print("QR HATA");</code> | QR metni QR sürüm 3 / ECC_LOW kapasitesine sığmazsa "QR HATA" yazılır |
| [cihaz_kontrol/src/main.cpp:254](../../cihaz_kontrol/src/main.cpp#L254) | <code>void broadcastScreenQrToken(bool isNewToken) {</code> | Ana kart: RF kapalıyken token ÜRETİLMEZ, bu yüzden SHOW_QR gitmez |
| [cihaz_kontrol/src/main.cpp:267](../../cihaz_kontrol/src/main.cpp#L267) | <code>const String qrCmd = String(CMD_SHOW_QR_PREFIX) + "AHBU:DOOR:" + cihazUniqueId() + ":" + …</code> | Ekrana giden QR: AHBU:DOOR:<UID>:<TOKEN> |

**Olası nedenler**
- Ana kart henüz açılmadı / RF kapalı (token üretilmedi) ya da UART bağlantısı yok
- SHOW_QR verisi 60 karakteri aşıyor ya da QR sürümüne sığmıyor ("QR HATA")
- Ana karttan 45 sn satır gelmedi: ekran QR'ı bayat sayıp yer tutucuya döndü (bkz. ekran-ana-kart-sessiz)

**Adım adım kontrol**
- Ekran seri monitöründe "[RX<-WROOM] SHOW_QR|***" satırı akıyor mu (token maskelenir)
- Ana kart seri çıkışında UID ve Wi-Fi/RF durumuna bakın
- Ekranı USB'den "SHOW_QR|AHBU:DOOR:TEST:ABC" satırı ile elle deneyebilirsiniz (ADMIN_* PC'den işlenmez)

**Günlükte aranacak ifadeler**
- `[RX<-WROOM] `

**Bkz.:** [ekran-qr-yenilenmiyor](#ekran-qr-yenilenmiyor), [ekran-ana-kart-sessiz](#ekran-ana-kart-sessiz), [ekran-uart-protokol-uyusmazligi](#ekran-uart-protokol-uyusmazligi), [altyapi-ekran-qr-token-sunucuda](20-sunucu-altyapi-ve-yayin.md#altyapi-ekran-qr-token-sunucuda)

<a id="ekran-qr-yenilenmiyor"></a>
### ekran-qr-yenilenmiyor · Ekrandaki QR 30 sn sonra yenilenmiyor ya da "Kalan Sure: 00 sn" sonrası aynı QR kalıyor; uygulama okutunca süresi doldu diyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [cihaz_kontrol/src/main.cpp:232](../../cihaz_kontrol/src/main.cpp#L232) | <code>constexpr unsigned long SCREEN_QR_ROTATION_INTERVAL_MS = 30000UL;</code> | Ana kart her 30 sn yeni token üretip SHOW_QR yollar |
| [ekran_yazilimi/src/ScreenManager.cpp:1145](../../ekran_yazilimi/src/ScreenManager.cpp#L1145) | <code>if (newQr != _qrData) {</code> | Yeni QR geldiğinde veri değişir, geri sayım yeniden 30 sn'den başlar; aynı QR gelirse hiçbir şey yapılmaz |
| [ekran_yazilimi/src/ScreenManager.cpp:890](../../ekran_yazilimi/src/ScreenManager.cpp#L890) | <code>void ScreenManager::drawQrCountdownBar(bool forceRedraw) {</code> | 30 sn ilerleme çubuğu + "Kalan Sure" metni; süre bitince çubuk boşalır ama QR yenisi gelmeden değişmez |
| [ekran_yazilimi/src/ScreenManager.cpp:238](../../ekran_yazilimi/src/ScreenManager.cpp#L238) | <code>if (_mainRxSeen &amp;&amp; now - _lastMainRxMs &gt; MAIN_LINK_TIMEOUT_MS) {</code> | 45 sn ana karttan satır gelmezse QR yer tutucuya alınır (donmuş eski QR gösterilmez) |
| [cihaz_kontrol/src/main.cpp:272](../../cihaz_kontrol/src/main.cpp#L272) | <code>gScreenQrMqttYayinlandi = mqttPublishScreenQr(gCurrentScreenQrToken, 30);</code> | Token sunucuya MQTT ile bildirilir; yayın başarısızsa sunucu tokenı tanımaz (okutma reddedilir) |

**Olası nedenler**
- Ana kart token üretmiyor (RF kapalı, döngü takılı) ya da UART üzerinden SHOW_QR ulaşmıyor
- Ekran güncelleniyor ama token MQTT ile sunucuya gitmedi: ekrandaki QR sunucuda bilinmiyor
- Ekran saati ile ana kart rotasyonu farklı: ekran kendi 30 sn çubuğunu SHOW_QR alış anından sayar

**Adım adım kontrol**
- Ekran seri monitöründe SHOW_QR satırlarının yaklaşık 5 sn aralıkla aktığını, QR değerinin 30 sn'de bir değiştiğini doğrulayın
- MQTT/sunucu tarafı için altyapı bölümündeki ekran QR token girişine bakın

**Bkz.:** [ekran-qr-gorunmuyor](#ekran-qr-gorunmuyor), [ekran-ana-kart-sessiz](#ekran-ana-kart-sessiz), [altyapi-ekran-qr-token-sunucuda](20-sunucu-altyapi-ve-yayin.md#altyapi-ekran-qr-token-sunucuda), [akis-ekran-qr-uygulama-okutma](60-akislar.md#akis-ekran-qr-uygulama-okutma)

<a id="ekran-qr-boyut-okunmuyor"></a>
### ekran-qr-boyut-okunmuyor · Ekrandaki QR telefonla/GM60 ile zor okunuyor ya da çok küçük/silik görünüyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [ekran_yazilimi/src/ScreenManager.cpp:855](../../ekran_yazilimi/src/ScreenManager.cpp#L855) | <code>void ScreenManager::drawQRCode(const String&amp; data, int x, int y, int size) {</code> | QR çizimi: sürüm 3 sabit, ECC_LOW, modül ölçeği = size / (modül + 4 kenar boşluğu) |
| [ekran_yazilimi/src/ScreenManager.cpp:871](../../ekran_yazilimi/src/ScreenManager.cpp#L871) | <code>int scale = size / (modules + (border * 2));</code> | Ölçek tam sayıdır; QR 168 piksel alana ortalanır |
| [ekran_yazilimi/src/ScreenManager.cpp:355](../../ekran_yazilimi/src/ScreenManager.cpp#L355) | <code>drawQRCode(_qrData, 36, 84, 168);</code> | Ana ekranda QR 168x168, beyaz zeminli 180x180 çerçeve içinde |
| [ekran_yazilimi/platformio.ini:25](../../ekran_yazilimi/platformio.ini#L25) | <code>-D TFT_INVERSION_ON=1</code> | Renk ters çevirme yanlışsa QR kontrastı bozulur; panel tipine göre ayarlanır |

**Olası nedenler**
- QR uzunluğu sürüm 3'e sığmıyor (60 karakter sınırı) - "QR HATA" yazar
- Ekran ters renk ayarı yanlış, parlaklık/kontrast düşük
- Tarayıcı (GM60) ekrana çok yakın/uzak ya da parlama var

**Adım adım kontrol**
- QR'ın etrafında beyaz boşluk (border) kaybolmuş mu
- QR uzunluğunu kontrol edin: AHBU:DOOR:<UID>:<TOKEN> 60 karakteri aşmamalı

**Bkz.:** [ekran-qr-gorunmuyor](#ekran-qr-gorunmuyor), [ekran-siyah-bos](#ekran-siyah-bos)

<a id="ekran-ana-kart-sessiz"></a>
### ekran-ana-kart-sessiz · Ekranda üst çubukta "WiFi YOK" / "Bulut YOK" yanıyor ya da QR kayboluyor, oysa ana kart çalışıyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [ekran_yazilimi/include/ScreenManager.h:142](../../ekran_yazilimi/include/ScreenManager.h#L142) | <code>static constexpr unsigned long MAIN_LINK_TIMEOUT_MS = 45000UL;</code> | 45 sn ana karttan hiç satır gelmezse Wi-Fi/Bulut/QR bayat sayılır |
| [ekran_yazilimi/src/main.cpp:67](../../ekran_yazilimi/src/main.cpp#L67) | <code>screen.noteMainRx();  // ana MCU canli: sessizlik izleme damgasi (USB'den gelen test sati…</code> | Yalnız WROOM UART satırları canlılık damgası günceller (USB test satırları değil) |
| [ekran_yazilimi/src/ScreenManager.cpp:295](../../ekran_yazilimi/src/ScreenManager.cpp#L295) | <code>void ScreenManager::drawTopBar(bool showSettingsBtn) {</code> | Üst çubuk: WiFi / Bulut noktaları ve AYAR düğmesi |
| [ekran_yazilimi/src/ScreenManager.cpp:1101](../../ekran_yazilimi/src/ScreenManager.cpp#L1101) | <code>} else if (cmd == CMD_WIFI_DISCONNECTED) {</code> | Wi-Fi kopuk satırı bulutu da kopuk gösterir |
| [cihaz_kontrol/src/main.cpp:276](../../cihaz_kontrol/src/main.cpp#L276) | <code>void displayDurumuYenidenGonder() {</code> | Ana kart tarafı: ekran READY gönderince Wi-Fi/MQTT durumunu yeniden yollar |
| [cihaz_kontrol/src/main.cpp:281](../../cihaz_kontrol/src/main.cpp#L281) | <code>void displayDurumSenkronizasyonLoop() {</code> | Ana kartın durum değişimi ve periyodik gönderimi |

**Olası nedenler**
- UART hattı (GPIO20/21 - 32/33) kopuk ya da TX/RX ters
- Ana kart gerçekten çevrimdışı (Wi-Fi/MQTT yok): gösterge doğru
- Ana kart uzun süre meşgul (OTA indirme gibi): 45 sn aşılırsa geçici "YOK" görünür, sonra düzelir

**Adım adım kontrol**
- Ekran seri monitöründe "[RX<-WROOM]" satırı akıyor mu
- Ana kart seri çıkışında Wi-Fi/MQTT durumunu kontrol edin

**Bkz.:** [ekran-qr-yenilenmiyor](#ekran-qr-yenilenmiyor), [ekran-uart-protokol-uyusmazligi](#ekran-uart-protokol-uyusmazligi), [cihaz-wifi-baglanmiyor](40-cihaz-yazilimi.md#cihaz-wifi-baglanmiyor)

<a id="ekran-uart-protokol-uyusmazligi"></a>
### ekran-uart-protokol-uyusmazligi · Ekran ile ana kart birbirini anlamıyor: komutlar işlenmiyor, "Bilinmeyen komut" ya da eski/yeni yazılım uyuşmazlığı

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [ekran_yazilimi/include/display_protocol.h:8](../../ekran_yazilimi/include/display_protocol.h#L8) | <code>// NOTE: This file MUST be byte-identical in cihaz_kontrol/include and ekran_yazilimi/inc…</code> | Kural: ekran_yazilimi/include/display_protocol.h ile cihaz_kontrol/include/display_protocol.h BİREBİR aynı olmalı |
| [cihaz_kontrol/include/display_protocol.h:8](../../cihaz_kontrol/include/display_protocol.h#L8) | <code>// NOTE: This file MUST be byte-identical in cihaz_kontrol/include and ekran_yazilimi/inc…</code> | Aynı dosyanın ana kart kopyası; biri değişince diğeri de aynen güncellenmeli |
| [ekran_yazilimi/src/ScreenManager.cpp:1085](../../ekran_yazilimi/src/ScreenManager.cpp#L1085) | <code>void ScreenManager::processCommand(const String&amp; cmd) {</code> | Ekran tarafı komut dağıtıcısı; tanınmayan satır sessizce yok sayılır |
| [cihaz_kontrol/src/display_uart.cpp:196](../../cihaz_kontrol/src/display_uart.cpp#L196) | <code>Serial.println("[DISPLAY] Bilinmeyen komut (yoksayildi)");</code> | Ana kart tarafında tanınmayan komut günlüğü |
| [ekran_yazilimi/include/config.h:15](../../ekran_yazilimi/include/config.h#L15) | <code>constexpr uint32_t DISPLAY_UART_BAUD = 115200;</code> | Baud 115200 8N1; iki taraf aynı olmalı |
| [cihaz_kontrol/include/display_uart.h:7](../../cihaz_kontrol/include/display_uart.h#L7) | <code>constexpr int DISPLAY_UART_RX_PIN = 32; // UART1 RX</code> | Ana kart pinleri RX 32 / TX 33; ekranınki RX 20 / TX 21 (çapraz bağlanır) |

**Olası nedenler**
- İki protokol dosyası ayrışmış (biri güncellendi, diğeri unutuldu)
- Ekran ve ana kart farklı sürümde: örn. eski ekran PIN'siz ADMIN_AUTH yollar, ana kart reddeder
- TX/RX çapraz bağlanmadı ya da GND ortak değil; baud farkı

**Adım adım kontrol**
- Dosyaları karşılaştırın: fc /b ya da diff -q ile iki display_protocol.h aynı mı (aynı olmalı)
- Ekran Cihaz Bilgisi sayfasında "Ekran FW" ile ana kart "Firmware" sürümlerini yazın ve aracın yayın kayıtlarıyla karşılaştırın
- Ana kart seri çıkışında "[DISPLAY] Bilinmeyen komut" ya da "ekran yazilimi guncel olmali" uyarısı var mı

**Günlükte aranacak ifadeler**
- `[DISPLAY] Bilinmeyen komut (yoksayildi)`

**Komutlar**
```bash
diff -q ekran_yazilimi/include/display_protocol.h cihaz_kontrol/include/display_protocol.h
```

**Bkz.:** [ekran-pin-ekrani-tus-yanit-yok](#ekran-pin-ekrani-tus-yanit-yok), [ekran-uart-satir-cok-uzun](#ekran-uart-satir-cok-uzun), [ekran-surum-uyusmazligi](#ekran-surum-uyusmazligi)

<a id="ekran-uart-satir-cok-uzun"></a>
### ekran-uart-satir-cok-uzun · Ekran seri monitöründe "satir cok uzun, sonraki satir sonuna kadar atlaniyor"; bazı komutlar kayboluyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [ekran_yazilimi/src/main.cpp:47](../../ekran_yazilimi/src/main.cpp#L47) | <code>constexpr size_t UART_LINE_MAX = 255;</code> | Satır sınırı 255 bayt (protokol kuralı) |
| [ekran_yazilimi/src/main.cpp:73](../../ekran_yazilimi/src/main.cpp#L73) | <code>Serial.println("[RX&lt;-WROOM] satir cok uzun, sonraki satir sonuna kadar atlaniyor");</code> | Taşmada satır atılır ve bir sonraki \n'e kadar her şey yok sayılır (yeniden senkronizasyon) |
| [ekran_yazilimi/src/main.cpp:71](../../ekran_yazilimi/src/main.cpp#L71) | <code>// Çerçeveleme gürültüsü (kontrol baytları): yok say</code> | 0x20 altındaki baytlar (\r/\n hariç) satıra eklenmez |
| [cihaz_kontrol/src/display_uart.cpp:14](../../cihaz_kontrol/src/display_uart.cpp#L14) | <code>constexpr size_t DISPLAY_LINE_MAX = 255;</code> | Ana kart tarafındaki aynı sınır |

**Olası nedenler**
- Hatta gürültü/bozuk bayt: satır sonu kaçtı ve tampon doldu
- Bir gönderici alanlara "|" ya da çok uzun metin koydu (SSID gibi alanlar ana kartta temizlenir/kısaltılır)
- Baud uyuşmazlığı: anlamsız baytlar uzun satır gibi görünür

**Adım adım kontrol**
- Kabloyu kısaltıp GND'yi doğrulayın; baud ve pinleri iki tarafta karşılaştırın

**Günlükte aranacak ifadeler**
- `[RX<-WROOM] satir cok uzun, sonraki satir sonuna kadar atlaniyor`

**Bkz.:** [ekran-uart-protokol-uyusmazligi](#ekran-uart-protokol-uyusmazligi), [ekran-ana-kart-sessiz](#ekran-ana-kart-sessiz)

<a id="ekran-kapi-acildi-denied-ekran"></a>
### ekran-kapi-acildi-denied-ekran · Kapı açıldı/Geçersiz QR ekranı gelmiyor, takılı kalıyor ya da "QR Okunuyor..." ekranında kalıyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [ekran_yazilimi/src/ScreenManager.cpp:1091](../../ekran_yazilimi/src/ScreenManager.cpp#L1091) | <code>} else if (cmd == CMD_QR_READING) {</code> | QR_READING gelince "QR Okunuyor..." ekranı; 6 sn yanıt gelmezse ana ekrana döner |
| [ekran_yazilimi/src/ScreenManager.cpp:399](../../ekran_yazilimi/src/ScreenManager.cpp#L399) | <code>_autoReturnTimeoutMs = 2500; // 2.5 saniye sonra dön</code> | "KAPI ACILDI" ekranı 2,5 sn |
| [ekran_yazilimi/src/ScreenManager.cpp:441](../../ekran_yazilimi/src/ScreenManager.cpp#L441) | <code>_autoReturnTimeoutMs = 3000; // 3 saniye sonra dön</code> | "GECERSIZ QR" ekranı 3 sn |
| [ekran_yazilimi/src/ScreenManager.cpp:214](../../ekran_yazilimi/src/ScreenManager.cpp#L214) | <code>if (_autoReturnTimeoutMs &gt; 0 &amp;&amp; (now - _stateEnteredMs &gt;= _autoReturnTimeoutMs)) {</code> | Tüm geçici ekranların otomatik ana ekrana dönüşü |
| [ekran_yazilimi/src/ScreenManager.cpp:426](../../ekran_yazilimi/src/ScreenManager.cpp#L426) | <code>void ScreenManager::showDoorClosed() {</code> | DOOR_CLOSED yalnız "Kapı açıldı" ekranındaysa ana ekrana döndürür |

**Olası nedenler**
- Ana kart sonucu (DOOR_OPENED / QR_DENIED) göndermedi: sunucu yanıtı ya da UART sorunu
- Sonuç geldi ama ekran başka bir ekrandaydı (yönetici menüsü): PIN istenmemiş yanıtlar bilinçli yok sayılır
- Zaman aşımı normal: ekran 2,5 / 3 / 6 sn sonra kendi ana ekranına döner

**Adım adım kontrol**
- Ekran seri monitöründe "[RX<-WROOM] QR_READING / DOOR_OPENED / QR_DENIED" satırlarını izleyin
- Sonuç hiç gelmiyorsa ana kart ve sunucu tarafı girişlerine bakın

**Bkz.:** [altyapi-qr-sonuc-cihaza-donmuyor](20-sunucu-altyapi-ve-yayin.md#altyapi-qr-sonuc-cihaza-donmuyor), [ekran-ana-kart-sessiz](#ekran-ana-kart-sessiz)

<a id="ekran-turkce-karakter-yazi"></a>
### ekran-turkce-karakter-yazi · Ekranda Türkçe karakterler (ğ, ş, ı, İ) görünmüyor ya da yazılar ASCII ("GECIS", "ACILDI") yazılmış

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [ekran_yazilimi/src/ScreenManager.cpp:346](../../ekran_yazilimi/src/ScreenManager.cpp#L346) | <code>// Alt yazı — Türkçe karakter kullanılmıyor (TFT_eSPI GLCD fontu ASCII-only)</code> | Bilinçli: ekranda yalnız ASCII yazılır |
| [ekran_yazilimi/platformio.ini:28](../../ekran_yazilimi/platformio.ini#L28) | <code>-D LOAD_GLCD=1</code> | Yüklü fontlar (GLCD, FONT2/4/6/7/8, GFXFF, SMOOTH_FONT); yazılar varsayılan GLCD ile çizilir |
| [ekran_yazilimi/src/ScreenManager.cpp:350](../../ekran_yazilimi/src/ScreenManager.cpp#L350) | <code>tft.print("QR KOD ILE GECIS SISTEMI");</code> | Örnek: ASCII metin (Türkçe karakter yok) |

**Olası nedenler**
- Beklenen davranış: GLCD fontunda Türkçe harf yok; metinler ASCII yazıldı
- Metin eklerken Türkçe harf kullanılırsa ekranda bozuk/boş karakter çıkar

**Adım adım kontrol**
- Yeni metinlerde ğ, ş, ı, İ, ö, ü, ç yerine g, s, i, I, o, u, c kullanın; ekran dikey 240x320 ve sabit konumlu çizildiği için uzunluğu taşırmayın

**Bkz.:** [ekran-siyah-bos](#ekran-siyah-bos)

<a id="ekran-baglanti-durumu-bos"></a>
### ekran-baglanti-durumu-bos · Yönetici menüsündeki "Baglanti Durumu" ya da "Cihaz Bilgisi" ekranında değerler "-" / "Kopuk" görünüyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [ekran_yazilimi/src/ScreenManager.cpp:722](../../ekran_yazilimi/src/ScreenManager.cpp#L722) | <code>sendCommand(CMD_REQ_STATUS);</code> | Bağlantı Durumu ekranı açılınca ana karttan durum istenir |
| [ekran_yazilimi/src/ScreenManager.cpp:1114](../../ekran_yazilimi/src/ScreenManager.cpp#L1114) | <code>} else if (cmd.startsWith(CMD_SYS_STATUS_PREFIX)) {</code> | SYS_STATUS\|SSID\|IP\|RSSI\|MQTT\|UPTIME[\|CAM] ayrıştırılır; en az 5 alan gerekir |
| [ekran_yazilimi/src/ScreenManager.cpp:804](../../ekran_yazilimi/src/ScreenManager.cpp#L804) | <code>sendCommand(CMD_REQ_INFO);</code> | Cihaz Bilgisi ekranı açılınca UID/FW/hedef istenir |
| [ekran_yazilimi/src/ScreenManager.cpp:1130](../../ekran_yazilimi/src/ScreenManager.cpp#L1130) | <code>} else if (cmd.startsWith(CMD_SYS_INFO_PREFIX)) {</code> | SYS_INFO\|UID\|FW\|TARGET ayrıştırılır |
| [cihaz_kontrol/src/display_uart.cpp:156](../../cihaz_kontrol/src/display_uart.cpp#L156) | <code>} else if (cmd == CMD_REQ_STATUS) {</code> | Ana kart durum satırını üretir (SSID, IP, RSSI, MQTT, çalışma süresi, kamera) |
| [cihaz_kontrol/src/display_uart.cpp:177](../../cihaz_kontrol/src/display_uart.cpp#L177) | <code>} else if (cmd == CMD_REQ_INFO) {</code> | Ana kart gerçek UID, firmware sürümü ve hedefi yollar |

**Olası nedenler**
- Ana kart yanıt vermedi (UART/yazılım uyuşmazlığı); değerler gelene kadar "-" kalır
- Alan eksik/uzun: satır ayrıştırması en az 5 alan ister
- "GM60 Optik: Yok": ana kart kamerayı/okuyucuyu bulamadı (kamera durumu ana karttan gelir)

**Adım adım kontrol**
- Seri monitörde "[TX->WROOM] REQ_STATUS" ve ardından "[RX<-WROOM] SYS_STATUS|..." satırı var mı
- Okuyucu "Yok" ise 40-cihaz-yazilimi bölümündeki GM60 girişlerine bakın

**Günlükte aranacak ifadeler**
- `[TX->WROOM] `

**Bkz.:** [ekran-ana-kart-sessiz](#ekran-ana-kart-sessiz), [ekran-uart-protokol-uyusmazligi](#ekran-uart-protokol-uyusmazligi)

<a id="ekran-surum-derleme-yukleme"></a>
### ekran-surum-derleme-yukleme · Ekran firmware derlenmiyor ya da yüklenmiyor (COM8, PlatformIO, TFT_eSPI hatası); yükleme sonrası ekran açılmıyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [ekran_yazilimi/platformio.ini:1](../../ekran_yazilimi/platformio.ini#L1) | <code>[env:esp32c3_display]</code> | Tek ortam; platform espressif32@6.5.0, board esp32-c3-devkitm-1 |
| [ekran_yazilimi/platformio.ini:5](../../ekran_yazilimi/platformio.ini#L5) | <code>upload_port = COM8</code> | Yükleme portu COM8 sabit; farklı porttaysa --upload-port ile verin ya da aracı kullanın |
| [ekran_yazilimi/platformio.ini:38](../../ekran_yazilimi/platformio.ini#L38) | <code>bodmer/TFT_eSPI@^2.5.0</code> | Kütüphaneler: TFT_eSPI, QRCode, ArduinoJson |
| [ekran_yazilimi/platformio.ini:13](../../ekran_yazilimi/platformio.ini#L13) | <code>-D USER_SETUP_LOADED=1</code> | TFT_eSPI kullanıcı ayarı yüklenmez; tüm pinler bayraklarla verilir (User_Setup.h değişimi etkisizdir) |
| [ekran_yazilimi/platformio.ini:10](../../ekran_yazilimi/platformio.ini#L10) | <code>-D HARDWARE_TARGET="esp32c3-display"</code> | Donanım hedefi etiketi |
| [company_qr_tool/app.py:2991](../../company_qr_tool/app.py#L2991) | <code>class ScreenFirmwareWindow:</code> | Şirket aracında ekran için derle/sürümle/yükle penceresi |

**Olası nedenler**
- COM8 yok/başka programda açık; ekranın bağlı olduğu port farklı
- Kütüphane indirilemedi (ağ yok) ya da platform sürümü uyuşmuyor
- Yükleme için BOOT+RST sırası gerekebilir
- Yanlış proje/ortamla (ana kart ortamıyla) yüklendi

**Adım adım kontrol**
- Derleme: pio run -d ekran_yazilimi -e esp32c3_display
- Seri monitörü kapatıp tekrar yükleyin; aygıt yöneticisinde portu doğrulayın
- Yükleme sonrası seri monitörde açılış başlığı ve "[INIT] Display controller ready." görünmeli

**Günlükte aranacak ifadeler**
- `[INIT] Display controller ready.`

**Komutlar**
```bash
pio run -d ekran_yazilimi -e esp32c3_display
```

**Bkz.:** [arac-ekran-firmware](50-arac-test-ve-surec.md#arac-ekran-firmware), [ekran-siyah-bos](#ekran-siyah-bos), [ekran-surum-uyusmazligi](#ekran-surum-uyusmazligi)

<a id="ekran-surum-uyusmazligi"></a>
### ekran-surum-uyusmazligi · Ekran firmware sürümü beklenenle uyuşmuyor ("Ekran FW" farklı) ya da sürüm kayıtlarında (firmware_releases) görünmüyor

| Dosya:satır | Satırdaki kod | Ne işe yarar |
| --- | --- | --- |
| [ekran_yazilimi/include/config.h:4](../../ekran_yazilimi/include/config.h#L4) | <code>#define DISPLAY_FIRMWARE_VERSION "1.1.1"</code> | Ekranın sürüm kaynağı (Cihaz Bilgisi ekranında "Ekran FW" ve USB kimlik yanıtında) |
| [ekran_yazilimi/src/ScreenManager.cpp:845](../../ekran_yazilimi/src/ScreenManager.cpp#L845) | <code>tft.print(DISPLAY_FIRMWARE_VERSION);</code> | Cihaz Bilgisi ekranında sürümün gösterildiği yer |
| [ekran_yazilimi/src/main.cpp:88](../../ekran_yazilimi/src/main.cpp#L88) | <code>Serial.println(DISPLAY_FIRMWARE_VERSION);</code> | USB "?" / IDENT / DISP_PING yanıtındaki FW alanı |
| [ekran_yazilimi/firmware_releases/index.json:2](../../ekran_yazilimi/firmware_releases/index.json#L2) | <code>"releases": [</code> | Yayın dizini: her kayıt id, sürüm, env ve dosya özetleri taşır |
| [ekran_yazilimi/firmware_releases/20260917_115500_v1_0_2/manifest.json:2](../../ekran_yazilimi/firmware_releases/20260917_115500_v1_0_2/manifest.json#L2) | <code>"version": "1.0.2",</code> | Örnek sürüm manifesti |
| [company_qr_tool/app.py:51](../../company_qr_tool/app.py#L51) | <code>DISPLAY_RELEASES_DIR = DISPLAY_PROJECT_DIR / "firmware_releases"</code> | Araç sürümleri bu klasöre yazar; sürüm numarasını config.h'tan okur/yazar |

**Olası nedenler**
- config.h sürümü değişti ama araçla yayın kaydı oluşturulmadı (firmware_releases geride kalabilir)
- Sahadaki ekrana eski firmware yüklü kaldı
- Sürüm elle düzenlendi; araçla "sürümle" adımı atlandı

**Adım adım kontrol**
- Ekranda Yönetici > Cihaz Bilgisi > "Ekran FW" değerini okuyun; USB'den "?" yazınca FW: alanına bakın
- config.h sürümünü firmware_releases/index.json en son kaydıyla karşılaştırın

**Bkz.:** [arac-ekran-firmware](50-arac-test-ve-surec.md#arac-ekran-firmware), [ekran-surum-derleme-yukleme](#ekran-surum-derleme-yukleme), [ekran-uart-protokol-uyusmazligi](#ekran-uart-protokol-uyusmazligi)

