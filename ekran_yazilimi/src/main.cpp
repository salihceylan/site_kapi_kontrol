#include <Arduino.h>
#include "ScreenManager.h"
#include "display_protocol.h"
#include "config.h"
#include "cst816d_touch.h"

// PC USB seri portu: kimlik sorgusu ("?", "IDENT", "DISP_PING" -> AHBU_DEVICE:DISPLAY...) ve görsel test komutları
// (SHOW_QR|..., DOOR_OPENED vb. - şirket aracı kullanır) çalışır. "ADMIN_*" komutları PC'den ASLA işlenmez:
// yönetici PIN kapısı USB üzerinden atlatılamaz (gerçek doğrulama zaten ana MCU'dadır).

// Communication with main ESP32-WROOM via Hardware UART1 (Serial1 on ESP32-C3, GPIO 20/21)
// NOTE: ARDUINO_USB_CDC_ON_BOOT=1 olduğunda Serial0 USB CDC'ye düşer.
// Fiziksel GPIO20 (RX) / GPIO21 (TX) için Serial1 kullanılmalıdır.
HardwareSerial &wroomSerial = Serial1;

ScreenManager screen;
CST816DTouch touch;

// Seriye yazdırırken gizli veri (yönetici PIN'i, QR token'ı) maskelenir.
static bool logGizliMi(const char* cmd) {
  return strncmp(cmd, "ADMIN_", 6) == 0 || strncmp(cmd, CMD_SHOW_QR_PREFIX, strlen(CMD_SHOW_QR_PREFIX)) == 0;
}

static void logSatiri(const char* yon, const String& cmd) {
  Serial.print(yon);
  if (logGizliMi(cmd.c_str())) {
    const int ayirac = cmd.indexOf('|');
    Serial.print(ayirac > 0 ? cmd.substring(0, ayirac) : cmd);
    Serial.println("|***");
  } else {
    Serial.println(cmd);
  }
}

// Forward declaration for sending commands to ESP32-WROOM
void sendToWroom(const char* cmd) {
  if (cmd == nullptr || strlen(cmd) == 0) return;
  wroomSerial.println(cmd);
  logSatiri("[TX->WROOM] ", String(cmd));
}

// Non-blocking UART reception buffers
static String wroomUartBuffer = "";
static bool wroomSatirAtla = false;  // tasma sonrası: bir sonraki '\n'e kadar her şeyi at (yeniden senkronizasyon)
static String pcSerialBuffer = "";

constexpr size_t UART_LINE_MAX = 255;

void processUartInput() {
  // 1. Read from WROOM hardware UART
  while (wroomSerial.available() > 0) {
    char c = static_cast<char>(wroomSerial.read());

    if (wroomSatirAtla) {
      if (c == '\n') {
        wroomSatirAtla = false;
        wroomUartBuffer = "";
      }
      continue;
    }

    if (c == '\r' || c == '\n') {
      if (wroomUartBuffer.length() > 0) {
        const String satir = wroomUartBuffer;
        wroomUartBuffer = "";
        logSatiri("[RX<-WROOM] ", satir);
        screen.noteMainRx();  // ana MCU canli: sessizlik izleme damgasi (USB'den gelen test satirlari damgalamaz)
        screen.processCommand(satir);
      }
    } else if (static_cast<uint8_t>(c) < 0x20) {
      // Çerçeveleme gürültüsü (kontrol baytları): yok say
    } else if (wroomUartBuffer.length() >= UART_LINE_MAX) {
      Serial.println("[RX<-WROOM] satir cok uzun, sonraki satir sonuna kadar atlaniyor");
      wroomUartBuffer = "";
      wroomSatirAtla = true;
    } else {
      wroomUartBuffer += c;
    }
  }

  // 2. Read from PC USB Serial (kimlik sorgusu + görsel test komutları; ADMIN_* hariç)
  while (Serial.available() > 0) {
    char c = static_cast<char>(Serial.read());
    if (c == '\r' || c == '\n') {
      if (pcSerialBuffer.length() > 0) {
        if (pcSerialBuffer == "?" || pcSerialBuffer == "IDENT" || pcSerialBuffer == "DISP_PING") {
          Serial.print("AHBU_DEVICE:DISPLAY|CHIP:ESP32-C3|TARGET:esp32c3-display|FW:");
          Serial.println(DISPLAY_FIRMWARE_VERSION);
        }
        else if (!pcSerialBuffer.startsWith("ADMIN_")) {
          logSatiri("[RX<-PC] ", pcSerialBuffer);
          screen.processCommand(pcSerialBuffer);
        }
        pcSerialBuffer = "";
      }
    } else {
      pcSerialBuffer += c;
      if (pcSerialBuffer.length() >= UART_LINE_MAX) {
        pcSerialBuffer = "";
      }
    }
  }
}

// Non-blocking capacitive touch polling with touch-down / release tracking
// Not (millis): bu dosyadaki tum damgalar "simdi - damga >= sure" (isaretsiz fark) HIZ SINIRLAYICILARIDIR; damga cok eskirse
// (49,7 gunluk millis() sarmasi) etkisi en fazla bir "sure" kadar gecikmedir, mantik kilitlenmez.
static unsigned long lastTouchPollMs = 0;
static bool wasTouching = false;
static unsigned long lastTouchActionMs = 0;
static unsigned long lastTouchInitTryMs = 0;
constexpr unsigned long TOUCH_REINIT_INTERVAL_MS = 5000;

void processTouchInput() {
  if (!touch.isAvailable()) {
    // CST816D acilista hazir olmadiysa (gec acilis / gevsek kontak / gecici I2C hatasi) ekran guc dongusune kadar
    // dokunmasiz (PIN / yonetici menusu kapali) kalmasin: 5 sn'de bir yeniden dene. begin() ~60 ms bloklar (RST darbesi).
    const unsigned long simdi = millis();
    if (simdi - lastTouchInitTryMs >= TOUCH_REINIT_INTERVAL_MS) {
      lastTouchInitTryMs = simdi;
      if (touch.begin(TOUCH_SDA_PIN, TOUCH_SCL_PIN, TOUCH_RST_PIN, TOUCH_INT_PIN, false)) {
        sendToWroom(CMD_TOUCH_READY);
      }
    }
    return;
  }

  // Poll touch controller at ~30 Hz (30ms)
  if (millis() - lastTouchPollMs < 30) return;
  lastTouchPollMs = millis();

  int16_t tx, ty;
  bool isTouching = touch.readTouch(tx, ty);

  if (isTouching) {
    // Fire on initial finger-down or after 350ms transition debounce
    if (!wasTouching && (millis() - lastTouchActionMs > 350)) {
      lastTouchActionMs = millis();
#ifdef AHBU_DEBUG_TOUCH
      // YALNIZ GELISTIRME (-D AHBU_DEBUG_TOUCH): PIN tus izgarasi sabit oldugundan dokunma koordinatlarindan yonetici PIN'i
      // cikarilabilir. Sahada / uretim derlemesinde KAPALI tutulur.
      Serial.printf("[TOUCH] Tap at X=%d, Y=%d\n", tx, ty);
#endif

      // Kural 9 & 11: Ekran uykudayken ilk dokunuş sadece ekranı uyandırır, hiçbir butonu tetiklemez!
      if (screen.isSleeping()) {
        Serial.println("[TOUCH] Ekran uykudan uyandirildi (ilk dokunus korumasi)");
        screen.wakeScreen();
        screen.showHomeScreen();
        wasTouching = true;
        return;
      }

      screen.onTouch(tx, ty);
    }
    wasTouching = true;
  } else {
    wasTouching = false;
  }
}

// Non-blocking hardware test button (active LOW with pullup)
static bool lastBtnState = HIGH;
static unsigned long lastBtnDebounceMs = 0;

void processButtonInput() {
  const bool curState = digitalRead(BTN_PIN);
  if (curState != lastBtnState && (millis() - lastBtnDebounceMs > 200)) {
    lastBtnDebounceMs = millis();
    lastBtnState = curState;
    if (curState == LOW) {
      Serial.println("[BTN] Physical button pressed");
      screen.onButtonPress();
    }
  }
}

// Non-blocking status heartbeat LED
static unsigned long lastLedBlinkMs = 0;
static bool ledState = false;

void processHeartbeatLed() {
  if (millis() - lastLedBlinkMs >= 500) {
    lastLedBlinkMs = millis();
    ledState = !ledState;
    digitalWrite(STATUS_LED_PIN, ledState ? HIGH : LOW);
  }
}

void setup() {
  // Initialize USB CDC for PC debugging
  Serial.begin(115200);
#if defined(ARDUINO_USB_CDC_ON_BOOT) && ARDUINO_USB_CDC_ON_BOOT
  // USB-CDC (HWCDC, arduino-esp32 2.0.14): host bir kez baglanip cekilince cekirdek TX zaman asimini 100 ms'de birakir ve
  // 256 B'lik TX halkasi dolunca her Serial.print() ~100 ms bloklar (UART/dokunma isleme donar). 0 = asla bloklama yok;
  // host yoksa/okumuyorsa sigmayan log baytlari atilir (loglar kritik degil).
  Serial.setTxTimeoutMs(0);
#endif

  // Initialize Hardware UART0 to main ESP32-WROOM MCU
  wroomSerial.setRxBufferSize(512);
  wroomSerial.begin(DISPLAY_UART_BAUD, SERIAL_8N1, DISPLAY_UART_RX_PIN, DISPLAY_UART_TX_PIN);

  pinMode(BTN_PIN, INPUT_PULLUP);
  pinMode(STATUS_LED_PIN, OUTPUT);
  digitalWrite(STATUS_LED_PIN, LOW);

  Serial.println("\n==========================================");
  Serial.println("  ESP32-C3 2.4\" ST7789 Display Controller ");
  Serial.println("==========================================");

  screen.setSendCallback(sendToWroom);
  screen.begin();

  // Initialize capacitive touch controller CST816D
  if (touch.begin(TOUCH_SDA_PIN, TOUCH_SCL_PIN, TOUCH_RST_PIN, TOUCH_INT_PIN)) {
    sendToWroom(CMD_TOUCH_READY);
  }

  // Notify WROOM that display controller has booted
  sendToWroom(CMD_DISP_READY);
  Serial.println("[INIT] Display controller ready.");
}

void loop() {
  // 1. Process UART commands from WROOM and PC (non-blocking)
  processUartInput();

  // 2. Process capacitive touch events (non-blocking)
  processTouchInput();

  // 3. Process hardware inputs / test button (non-blocking)
  processButtonInput();

  // 4. Update screen manager (non-blocking timeouts, animations)
  screen.update();

  // 5. Periodic sync: if we don't have a valid door QR yet, ask WROOM every 2s
  static unsigned long lastQrReqMs = 0;
  if (!screen.hasValidQr() && (millis() - lastQrReqMs >= 2000)) {
    lastQrReqMs = millis();
    sendToWroom(CMD_DISP_READY);
  }

  // 6. Heartbeat LED blink
  processHeartbeatLed();
}
