#pragma once

#include <Arduino.h>
#include <TFT_eSPI.h>

// ==========================================
// 240x320 Portre Kurumsal Renk Paleti
// ==========================================
#define COLOR_BG          0x0842  // Çok koyu lacivert
#define COLOR_CARD        0x18E3  // Kart ve buton arka planı
#define COLOR_CARD_BORDER 0x31A6  // Kart çerçevesi
#define COLOR_ACCENT      0x051D  // Turkuaz / Mavi vurgu
#define COLOR_SUCCESS     0x05E5  // Zümrüt Yeşili
#define COLOR_DANGER      0xF9C7  // Mercan Kırmızısı
#define COLOR_WARNING     0xFD20  // Turuncu uyarı
#define COLOR_TEXT        0xFFFF  // Beyaz
#define COLOR_MUTED       0x9CF3  // Açık kurşuni gri

enum ScreenState {
  STATE_HOME,              // Ana bekleme ekranı ("QR Kodunuzu Okutunuz", AHBU Logo, üst bar, ayarlar ikonu)
  STATE_QR_READING,        // "QR Kod Okunuyor...", "Lütfen Bekleyiniz"
  STATE_DOOR_OPENED,       // "Kapı Açıldı", yeşil onay dairesi
  STATE_QR_DENIED,         // "Geçersiz / Yetkisiz QR Kod", kırmızı uyarı
  STATE_ADMIN_PIN,         // 6 haneli PIN giriş ekranı
  STATE_ADMIN_MENU,        // Yönetici Ana Menüsü
  STATE_MANUAL_OPEN,       // "Kapı Açılsın mı? [İptal] [AÇ]" onay ekranı
  STATE_STATUS,            // Bağlantı Durumu (Wi-Fi, IP, Sinyal, MQTT, API)
  STATE_DEVICE_INFO        // Cihaz Bilgileri (UID, MAC, Firmware, Uptime)
};

// PIN ekranında gösterilen bildirim türleri (C10: PIN doğrulaması ana MCU'dadır)
enum AdminNotice : uint8_t {
  NOTICE_NONE = 0,
  NOTICE_CHECKING,  // ADMIN_AUTH gönderildi, yanıt bekleniyor
  NOTICE_NOPIN,     // Ana MCU'da PIN tanımlı değil -> menü kilitli
  NOTICE_LOCKED,    // Çok sayıda hatalı deneme -> geçici kilit
  NOTICE_BAD,       // Hatalı PIN
  NOTICE_TIMEOUT,   // Ana MCU yanıt vermedi
  NOTICE_BUSY       // Röle meşgul (debounce)
};

// Callback type to send UART commands to main ESP32-WROOM
typedef void (*UartSendCallback)(const char* cmd);

class ScreenManager {
public:
  ScreenManager();
  void begin();
  void update(); // Non-blocking loop handler (handles auto-return timeouts and sleep)
  void processCommand(const String& cmd);

  // Status updates from main controller
  void setWifiStatus(bool connected);
  void setMqttStatus(bool connected);
  // camera: 1 = hazır, 0 = yok, -1 = bilinmiyor
  void updateSystemStatus(const String& ssid, const String& ip, const String& rssi, bool mqtt, const String& uptime, int camera = -1);
  void updateDeviceInfo(const String& uid, const String& fw, const String& target);

  // Screen transitions
  void showHomeScreen();
  void showQrReading();
  void showDoorOpened();
  void showDoorClosed();
  void showQrSuccess(const String& code);
  void showQrDenied();
  void showAdminPinScreen();
  void showAdminMenuScreen();
  void showManualOpenConfirm();
  void showConnectionStatus();
  void showDeviceInfo();

  // Sleep Manager (Ekran her zaman açık - Always ON)
  void wakeScreen();
  void sleepScreen();
  bool isSleeping() const { return false; }
  void resetSleepTimer();

  // Input handling
  void onTouch(int16_t x, int16_t y);
  void onButtonPress(); // Fallback hardware button

  void setSendCallback(UartSendCallback cb) { _sendCb = cb; }

  bool hasValidQr() const { return _qrData.length() > 0 && _qrData != "AHBU:DOOR:READY"; }
  const String& getQrData() const { return _qrData; }

  // Ana MCU'dan (UART1) tam bir satir alindi: baglanti canlilik damgasi (sessizlik izleme, bkz. update()).
  // Yalniz ana MCU satirlari icin cagrilir; USB'den gelen test komutlari (processCommand) damgalamaz.
  void noteMainRx() { _lastMainRxMs = millis(); _mainRxSeen = true; }

private:
  TFT_eSPI tft;
  ScreenState _currentState;
  unsigned long _stateEnteredMs;
  unsigned long _autoReturnTimeoutMs;

  // Sleep state
  bool _isSleeping;
  unsigned long _lastActivityMs;
  static constexpr unsigned long SCREEN_SLEEP_TIMEOUT_MS = 30000UL; // 30 saniye

  // PIN buffer ve yönetici oturumu (C10). Sabit PIN YOKTUR: PIN ana MCU'da (NVS) saklanır ve orada doğrulanır.
  String _pinBuffer;
  bool _pinError;
  static constexpr unsigned long ADMIN_SESSION_MAX_MS = 20000UL;  // menü oturumu MUTLAK 20 sn
  static constexpr unsigned long ADMIN_AUTH_TIMEOUT_MS = 3000UL;  // ana MCU yanıt bekleme süresi
  unsigned long _adminSessionStartMs;  // 0: oturum yok
  String _sessionPin;                  // yalnızca oturum süresince RAM'de; ADMIN_OPEN|<pin> için
  bool _pinWaiting;
  unsigned long _pinWaitStartMs;
  bool _manualOpenSent;
  uint8_t _adminNotice;
  int _adminNoticeCount;               // BAD: kalan deneme
  unsigned long _adminLockStartMs;     // LOCKED: kilidin başladığı an
  unsigned long _adminLockDurMs;       // LOCKED: kilit süresi (ms); {başlangıç,süre} + işaretsiz fark => millis() sarmasına dayanıklı
  unsigned long _lastNoticeDrawMs;
  unsigned long _lastSessionDrawMs;

  // Connection & Device Info
  bool _wifiConnected;
  bool _mqttConnected;
  int _cameraStatus;
  String _wifiSsid;
  String _wifiIp;
  String _wifiRssi;
  String _uptimeStr;
  String _deviceUid;
  String _firmwareVersion;
  String _hardwareTarget;

  // Dynamic QR & Countdown Timer
  String _qrData;
  String _lastQrCode;
  unsigned long _qrTimerStartMs;
  unsigned long _lastBarUpdateMs;
  int _lastRemainingSec;

  // Ana MCU sessizlik izleme (#8). Ana MCU periyodik (en fazla ~5 sn arayla) WIFI_/MQTT_/SHOW_QR satırı yollar. Bu kadar süre
  // HİÇ satır gelmezse Wi-Fi/Bulut/QR bayat sayılır. 45 sn: ana MCU döngüsü DNS/TLS el sıkışma yüzünden meşru olarak ~30 sn'ye
  // kadar susabilir (ana MCU loop watchdog'u 30 sn; WDT yeniden başlatması ~35 sn) -> bağlantı varken yanlış alarm olmaz.
  // Not: OTA indirmesi (watchdog beslenerek) bundan uzun sürerse geçici olarak "YOK" gösterilebilir; cihaz bitince yeniden başlar.
  static constexpr unsigned long MAIN_LINK_TIMEOUT_MS = 45000UL;
  unsigned long _lastMainRxMs = 0;   // son ana MCU satırının zamanı; YALNIZ _mainRxSeen iken okunur (hep taze: satır akıyor ya da alarm tetiklenir)
  bool _mainRxSeen = false;          // satır geldi ve alarm henüz tetiklenmedi (alarmdan sonra yeni satıra kadar kapalı => damga eskimez)

  UartSendCallback _sendCb;

  // Drawing routines
  void drawTopBar(bool showSettingsBtn = true);
  void drawHomeScreen();
  void drawQrCountdownBar(bool forceRedraw = false);
  void drawQrReadingScreen();
  void drawDoorOpenedScreen();
  void drawQrDeniedScreen();
  void drawAdminPinScreen();
  void drawAdminPinMessage();
  void drawAdminMenuScreen();
  void drawManualOpenConfirmScreen();
  void drawConnectionStatusScreen();
  void drawDeviceInfoScreen();
  void drawAdminSessionTimer();
  void drawQRCode(const String& data, int x, int y, int size);

  // Yönetici oturumu / PIN yardımcıları
  bool adminInputBlocked() const;
  void endAdminSession();
  void submitAdminPin();
  void handleAdminOk();
  void handleAdminDenied(const String& rest);
  void handleAdminState(const String& rest);

  void sendCommand(const char* cmd);
};
