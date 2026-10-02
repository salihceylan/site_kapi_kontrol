#include "ScreenManager.h"
#include "display_protocol.h"
#include "config.h"
#include <qrcode.h>

ScreenManager::ScreenManager()
  : _currentState(STATE_HOME),
    _stateEnteredMs(0),
    _autoReturnTimeoutMs(0),
    _isSleeping(false),
    _lastActivityMs(0),
    _pinBuffer(""),
    _pinError(false),
    _adminSessionStartMs(0),
    _sessionPin(""),
    _pinWaiting(false),
    _pinWaitStartMs(0),
    _manualOpenSent(false),
    _adminNotice(NOTICE_NONE),
    _adminNoticeCount(0),
    _adminLockStartMs(0),
    _adminLockDurMs(0),
    _lastNoticeDrawMs(0),
    _lastSessionDrawMs(0),
    _wifiConnected(false),
    _mqttConnected(false),
    _cameraStatus(-1),
    _wifiSsid(""),
    _wifiIp(""),
    _wifiRssi(""),
    _uptimeStr(""),
    _deviceUid(""),
    _firmwareVersion(""),
    _hardwareTarget(""),
    _qrData("AHBU:DOOR:READY"),
    _lastQrCode(""),
    _qrTimerStartMs(0),
    _lastBarUpdateMs(0),
    _lastRemainingSec(-1),
    _sendCb(nullptr) {
}

void ScreenManager::begin() {
#if defined(TFT_BL) && (TFT_BL >= 0)
  pinMode(TFT_BL, OUTPUT);
  digitalWrite(TFT_BL, HIGH);
#endif
  tft.init();
  tft.setRotation(0); // Portrait 240x320
  tft.fillScreen(COLOR_BG);
  _lastActivityMs = millis();
  _isSleeping = false;
  showHomeScreen();
}

void ScreenManager::resetSleepTimer() {
  _lastActivityMs = millis();
}

void ScreenManager::wakeScreen() {
  _isSleeping = false;
#if defined(TFT_BL) && (TFT_BL >= 0)
  digitalWrite(TFT_BL, HIGH);
#endif
  resetSleepTimer();
}

void ScreenManager::sleepScreen() {
  // Kullanıcı talebi: Ekran hiç kapanmaz, her zaman aydınlık kalır
  _isSleeping = false;
#if defined(TFT_BL) && (TFT_BL >= 0)
  digitalWrite(TFT_BL, HIGH);
#endif
}

// ---------------------------------------------------------------------------------------------
// Yönetici oturumu (C10)
// ---------------------------------------------------------------------------------------------

// PIN yok (NOPIN) veya geçici kilit varsa tuş takımı kapalıdır.
bool ScreenManager::adminInputBlocked() const {
  if (_adminNotice == NOTICE_NOPIN) {
    return true;
  }
  if (_adminNotice == NOTICE_LOCKED) {
    return millis() - _adminLockStartMs < _adminLockDurMs;  // {başlangıç,süre}: işaretsiz fark (millis() sarmasına dayanıklı)
  }
  return false;
}

void ScreenManager::endAdminSession() {
  _sessionPin = "";
  _adminSessionStartMs = 0;
  _pinBuffer = "";
  _pinWaiting = false;
  _manualOpenSent = false;
}

void ScreenManager::submitAdminPin() {
  // PIN'i ekranda DOĞRULAMAYIZ: ana MCU doğrular (NVS'teki PIN, hatalı deneme sayacı ve kilit orada).
  _pinWaiting = true;
  _pinWaitStartMs = millis();
  _adminNotice = NOTICE_CHECKING;
  drawAdminPinScreen();
  String cmd = String(CMD_ADMIN_AUTH) + "|" + _pinBuffer;
  sendCommand(cmd.c_str());
}

void ScreenManager::handleAdminOk() {
  if (_currentState != STATE_ADMIN_PIN || !_pinWaiting) {
    return; // istenmemiş yanıt
  }
  _sessionPin = _pinBuffer;
  _pinBuffer = "";
  _pinWaiting = false;
  _adminNotice = NOTICE_NONE;
  _adminSessionStartMs = millis();
  showAdminMenuScreen();
}

// rest: "BAD|<kalan>", "LOCKED|<sn>", "NOPIN", "BUSY|0"
void ScreenManager::handleAdminDenied(const String& rest) {
  const int p = rest.indexOf('|');
  const String reason = p > 0 ? rest.substring(0, p) : rest;
  const int n = p > 0 ? rest.substring(p + 1).toInt() : 0;

  if (_currentState == STATE_HOME || _currentState == STATE_DOOR_OPENED || _currentState == STATE_QR_DENIED ||
      _currentState == STATE_QR_READING) {
    return; // istenmemiş yanıt
  }

  if (_currentState != STATE_ADMIN_PIN) {
    // Menü oturumundaki ADMIN_OPEN reddedildi: oturumu bitir, PIN ekranına dön
    endAdminSession();
    showAdminPinScreen();
  }

  _pinWaiting = false;
  _pinBuffer = "";
  _adminNoticeCount = n;
  if (reason == "NOPIN") {
    _adminNotice = NOTICE_NOPIN;
  } else if (reason == "LOCKED") {
    _adminNotice = NOTICE_LOCKED;
    _adminLockStartMs = millis();
    _adminLockDurMs = static_cast<unsigned long>(n > 0 ? n : 1) * 1000UL;
  } else if (reason == "BUSY") {
    _adminNotice = NOTICE_BUSY;
  } else {
    _adminNotice = NOTICE_BAD;
  }
  drawAdminPinScreen();
}

// rest: "READY", "NOPIN", "LOCKED|<sn>"  (REQ_ADMIN yanıtı; yalnızca PIN ekranında anlamlı)
void ScreenManager::handleAdminState(const String& rest) {
  if (_currentState != STATE_ADMIN_PIN || _pinWaiting) {
    return;
  }
  const int p = rest.indexOf('|');
  const String state = p > 0 ? rest.substring(0, p) : rest;
  if (state == "NOPIN") {
    _adminNotice = NOTICE_NOPIN;
  } else if (state == "LOCKED") {
    const int n = p > 0 ? rest.substring(p + 1).toInt() : 1;
    _adminNotice = NOTICE_LOCKED;
    _adminLockStartMs = millis();
    _adminLockDurMs = static_cast<unsigned long>(n > 0 ? n : 1) * 1000UL;
  } else if (_adminNotice == NOTICE_NOPIN || _adminNotice == NOTICE_LOCKED) {
    _adminNotice = NOTICE_NONE;
  }
  drawAdminPinScreen();
}

void ScreenManager::update() {
  const unsigned long now = millis();

  // 0. Yönetici menü oturumu MUTLAK 20 sn: dokunma/komut oturumu uzatmaz.
  if (_adminSessionStartMs != 0 && now - _adminSessionStartMs >= ADMIN_SESSION_MAX_MS) {
    endAdminSession();
    showHomeScreen();
    return;
  }

  // PIN doğrulama yanıtı gelmedi
  if (_pinWaiting && now - _pinWaitStartMs >= ADMIN_AUTH_TIMEOUT_MS) {
    _pinWaiting = false;
    _pinBuffer = "";
    _adminNotice = NOTICE_TIMEOUT;
    if (_currentState == STATE_ADMIN_PIN) {
      drawAdminPinScreen();
    }
  }

  // PIN ekranında kilit geri sayımı / kilit bitişi
  if (_currentState == STATE_ADMIN_PIN && _adminNotice == NOTICE_LOCKED && now - _lastNoticeDrawMs >= 1000) {
    _lastNoticeDrawMs = now;
    if (now - _adminLockStartMs >= _adminLockDurMs) {
      _adminNotice = NOTICE_NONE;
    }
    drawAdminPinMessage();
  }

  // 1. Ekran hiç kapanmaz (Always ON). Ancak PIN veya Ayarlar ekranındaysa 30 sn sonra otomatik Ana Sayfaya döner.
  if (_currentState != STATE_HOME && (now - _lastActivityMs >= 30000UL)) {
    endAdminSession();
    _currentState = STATE_HOME;
    _pinError = false;
    showHomeScreen();
    return;
  }

  // 2. Durum zaman aşımları (Kapı açıldı, Geçersiz QR vb. otomatik ana ekrana dönüş)
  if (_autoReturnTimeoutMs > 0 && (now - _stateEnteredMs >= _autoReturnTimeoutMs)) {
    _autoReturnTimeoutMs = 0;
    endAdminSession();
    showHomeScreen();
    return;
  }

  // 3. Ana ekrandayken QR süre göstergesini (progress bar ve saniye sayacı) akıcı güncelle
  if (_currentState == STATE_HOME && !_isSleeping) {
    drawQrCountdownBar(false);
  }

  // 4. Menü oturumu kalan süre göstergesi
  if (_adminSessionStartMs != 0 && now - _lastSessionDrawMs >= 500 &&
      (_currentState == STATE_ADMIN_MENU || _currentState == STATE_MANUAL_OPEN ||
       _currentState == STATE_STATUS || _currentState == STATE_DEVICE_INFO)) {
    _lastSessionDrawMs = now;
    drawAdminSessionTimer();
  }

  // 5. Ana MCU sessizlik izleme (#8): MAIN_LINK_TIMEOUT_MS boyunca ana MCU'dan HİÇ satır gelmediyse Wi-Fi/Bulut durumu ve QR
  // bayattır (son değerde donup "bağlı" / geçerli QR gibi görünmesin). Süre ana MCU'nun meşru en uzun sessizliğinden büyüktür.
  // Alarm bir kez tetiklenir ve _mainRxSeen'i kapatır (damga eskimez, tekrar tekrar çizim yok); yeni ana MCU satırı yeniden kurar.
  // Bağlantı geri gelince normal akış sürer: ekran QR yokken 2 sn'de bir READY ister (main.cpp) ve ana MCU durum/QR'ı yollar.
  if (_mainRxSeen && now - _lastMainRxMs > MAIN_LINK_TIMEOUT_MS) {
    _mainRxSeen = false;
    const bool gosterilenVar = _wifiConnected || _mqttConnected || hasValidQr();
    _wifiConnected = false;
    _mqttConnected = false;
    _qrData = "AHBU:DOOR:READY";  // hasValidQr()'nin "QR yok" yer tutucusu (kurucudaki ilk durum)
    if (gosterilenVar && _currentState == STATE_HOME && !_isSleeping) {
      drawHomeScreen();  // üst çubuk (WiFi/Bulut YOK) + QR alanı + geri sayım
    }
  }
}

void ScreenManager::sendCommand(const char* cmd) {
  if (_sendCb != nullptr && cmd != nullptr) {
    _sendCb(cmd);
  }
}

void ScreenManager::setWifiStatus(bool connected) {
  if (_wifiConnected != connected) {
    _wifiConnected = connected;
    if (_currentState == STATE_HOME && !_isSleeping) {
      drawTopBar(true);
    }
  }
}

void ScreenManager::setMqttStatus(bool connected) {
  if (_mqttConnected != connected) {
    _mqttConnected = connected;
    if (_currentState == STATE_HOME && !_isSleeping) {
      drawTopBar(true);
    }
  }
}

void ScreenManager::updateSystemStatus(const String& ssid, const String& ip, const String& rssi, bool mqtt, const String& uptime, int camera) {
  _wifiSsid = ssid;
  _wifiIp = ip;
  _wifiRssi = rssi;
  _mqttConnected = mqtt;
  _uptimeStr = uptime;
  _cameraStatus = camera;
  if (_currentState == STATE_STATUS && !_isSleeping) {
    drawConnectionStatusScreen();
  }
}

void ScreenManager::updateDeviceInfo(const String& uid, const String& fw, const String& target) {
  _deviceUid = uid;
  _firmwareVersion = fw;
  _hardwareTarget = target;
  if (_currentState == STATE_DEVICE_INFO && !_isSleeping) {
    drawDeviceInfoScreen();
  }
}

void ScreenManager::drawTopBar(bool showSettingsBtn) {
  tft.fillRect(0, 0, 240, 30, COLOR_BG);

  // WiFi Durumu (Yeşil / Kırmızı nokta)
  uint16_t wifiCol = _wifiConnected ? COLOR_SUCCESS : COLOR_DANGER;
  tft.fillCircle(10, 15, 4, wifiCol);
  tft.setTextColor(COLOR_TEXT, COLOR_BG);
  tft.setTextSize(1);
  tft.setCursor(18, 11);
  tft.print(_wifiConnected ? "WiFi OK" : "WiFi YOK");

  // MQTT (Bulut) Durumu
  uint16_t mqttCol = _mqttConnected ? COLOR_SUCCESS : COLOR_DANGER;
  tft.fillCircle(105, 15, 4, mqttCol);
  tft.setCursor(113, 11);
  tft.print(_mqttConnected ? "Bulut OK" : "Bulut YOK");

  // Sağ üstte Yönetici / Ayarlar (⚙) dokunmatik ikonu
  if (showSettingsBtn) {
    tft.fillRoundRect(195, 4, 38, 22, 4, COLOR_CARD);
    tft.drawRoundRect(195, 4, 38, 22, 4, COLOR_CARD_BORDER);
    tft.setTextColor(COLOR_ACCENT, COLOR_CARD);
    tft.setTextSize(1);
    tft.setCursor(204, 11);
    tft.print("AYAR");
  }

  tft.drawFastHLine(0, 30, 240, COLOR_CARD_BORDER);
}

void ScreenManager::showHomeScreen() {
  wakeScreen();
  endAdminSession(); // oturum PIN'i ve sayaçları ana ekrana dönerken mutlaka silinir
  _currentState = STATE_HOME;
  _stateEnteredMs = millis();
  _autoReturnTimeoutMs = 0;
  _pinError = false;
  _adminNotice = NOTICE_NONE;
  drawHomeScreen();
}

void ScreenManager::drawHomeScreen() {
  tft.fillScreen(COLOR_BG);
  drawTopBar(true);

  // AHBU Marka Başlığı
  tft.setTextColor(COLOR_ACCENT, COLOR_BG);
  tft.setTextSize(2);
  tft.setCursor(95, 36);
  tft.print("AHBU");

  // Alt yazı — Türkçe karakter kullanılmıyor (TFT_eSPI GLCD fontu ASCII-only)
  tft.setTextColor(COLOR_TEXT, COLOR_BG);
  tft.setTextSize(1);
  tft.setCursor(60, 57);
  tft.print("QR KOD ILE GECIS SISTEMI");

  // QR Kod Çerçevesi — yazının altına boşluklu yerleştir (Y: 78)
  tft.fillRoundRect(30, 78, 180, 180, 10, COLOR_CARD);
  tft.drawRoundRect(30, 78, 180, 180, 10, COLOR_CARD_BORDER);
  drawQRCode(_qrData, 36, 84, 168);

  // 30 saniyelik Süre Göstergesi (Progress Bar & Geri Sayım Metni)
  drawQrCountdownBar(true);
}

void ScreenManager::showQrReading() {
  wakeScreen();
  _currentState = STATE_QR_READING;
  _stateEnteredMs = millis();
  _autoReturnTimeoutMs = 6000; // 6 saniye yanıt gelmezse dön
  drawQrReadingScreen();
}

void ScreenManager::drawQrReadingScreen() {
  tft.fillScreen(COLOR_BG);
  drawTopBar(false);

  // Mavi bilgi dairesi
  tft.fillCircle(120, 120, 45, COLOR_ACCENT);
  tft.fillCircle(120, 120, 40, COLOR_BG);

  // Büyüteç / Tarama simgesi
  tft.fillCircle(115, 115, 16, COLOR_ACCENT);
  tft.fillCircle(115, 115, 11, COLOR_BG);
  tft.drawLine(127, 127, 138, 138, COLOR_ACCENT);
  tft.drawLine(128, 127, 139, 138, COLOR_ACCENT);

  tft.setTextColor(COLOR_TEXT, COLOR_BG);
  tft.setTextSize(2);
  tft.setCursor(35, 190);
  tft.print("QR Okunuyor...");

  tft.setTextColor(COLOR_MUTED, COLOR_BG);
  tft.setTextSize(1);
  tft.setCursor(65, 225);
  tft.print("Lutfen bekleyiniz");
}

void ScreenManager::showDoorOpened() {
  wakeScreen();
  endAdminSession(); // yönetici kapı açma tamamlandı: PIN RAM'den silinir
  _currentState = STATE_DOOR_OPENED;
  _stateEnteredMs = millis();
  _autoReturnTimeoutMs = 2500; // 2.5 saniye sonra dön
  drawDoorOpenedScreen();
}

void ScreenManager::drawDoorOpenedScreen() {
  tft.fillScreen(COLOR_BG);
  drawTopBar(false);

  // Yeşil başarı dairesi ve tik işareti
  tft.fillCircle(120, 120, 45, COLOR_SUCCESS);
  // Tik
  tft.drawLine(105, 120, 115, 132, COLOR_TEXT);
  tft.drawLine(106, 120, 116, 132, COLOR_TEXT);
  tft.drawLine(115, 132, 138, 108, COLOR_TEXT);
  tft.drawLine(116, 132, 139, 108, COLOR_TEXT);

  tft.setTextColor(COLOR_SUCCESS, COLOR_BG);
  tft.setTextSize(2);
  tft.setCursor(55, 190);
  tft.print("KAPI ACILDI");

  tft.setTextColor(COLOR_TEXT, COLOR_BG);
  tft.setTextSize(1);
  tft.setCursor(60, 225);
  tft.print("Gecis Yapabilirsiniz");
}

void ScreenManager::showDoorClosed() {
  if (_currentState == STATE_DOOR_OPENED) {
    showHomeScreen();
  }
}

void ScreenManager::showQrSuccess(const String& code) {
  showDoorOpened();
}

void ScreenManager::showQrDenied() {
  wakeScreen();
  endAdminSession();
  _currentState = STATE_QR_DENIED;
  _stateEnteredMs = millis();
  _autoReturnTimeoutMs = 3000; // 3 saniye sonra dön
  drawQrDeniedScreen();
}

void ScreenManager::drawQrDeniedScreen() {
  tft.fillScreen(COLOR_BG);
  drawTopBar(false);

  // Kırmızı çarpı dairesi
  tft.fillCircle(120, 120, 45, COLOR_DANGER);
  tft.drawLine(105, 105, 135, 135, COLOR_TEXT);
  tft.drawLine(106, 105, 136, 135, COLOR_TEXT);
  tft.drawLine(105, 135, 135, 105, COLOR_TEXT);
  tft.drawLine(106, 135, 136, 105, COLOR_TEXT);

  tft.setTextColor(COLOR_DANGER, COLOR_BG);
  tft.setTextSize(2);
  tft.setCursor(45, 190);
  tft.print("GECERSIZ QR");

  tft.setTextColor(COLOR_MUTED, COLOR_BG);
  tft.setTextSize(1);
  tft.setCursor(55, 225);
  tft.print("Yetkisiz veya Bayat Kod!");
}

void ScreenManager::showAdminPinScreen() {
  wakeScreen();
  _currentState = STATE_ADMIN_PIN;
  _stateEnteredMs = millis();
  _autoReturnTimeoutMs = 0;
  _pinBuffer = "";
  _pinError = false;
  _pinWaiting = false;
  _adminNotice = NOTICE_NONE;
  _adminNoticeCount = 0;
  _lastNoticeDrawMs = millis();
  drawAdminPinScreen();
  // Ana MCU'dan PIN durumunu (tanımsız / kilitli / hazır) iste
  sendCommand(CMD_REQ_ADMIN);
}

// PIN ekranı üst mesaj satırı (y: 30..52): talimat veya durum bildirimi
void ScreenManager::drawAdminPinMessage() {
  tft.fillRect(0, 30, 240, 22, COLOR_BG);
  tft.setTextSize(1);
  char buf[40];
  switch (_adminNotice) {
    case NOTICE_CHECKING:
      tft.setTextColor(COLOR_ACCENT, COLOR_BG);
      tft.setCursor(70, 36);
      tft.print("Dogrulaniyor...");
      break;
    case NOTICE_NOPIN:
      tft.setTextColor(COLOR_DANGER, COLOR_BG);
      tft.setCursor(20, 33);
      tft.print("PIN tanimli degil");
      tft.setCursor(20, 43);
      tft.print("Yonetici menusu kilitli");
      break;
    case NOTICE_LOCKED: {
      const unsigned long gecenMs = millis() - _adminLockStartMs;
      const long kalanMs = gecenMs < _adminLockDurMs ? static_cast<long>(_adminLockDurMs - gecenMs) : 0L;
      int kalanSn = kalanMs > 0 ? static_cast<int>((kalanMs + 999) / 1000) : 0;
      tft.setTextColor(COLOR_DANGER, COLOR_BG);
      tft.setCursor(40, 33);
      tft.print("Cok fazla hatali deneme");
      snprintf(buf, sizeof(buf), "Kilitli: %d sn", kalanSn);
      tft.setCursor(70, 43);
      tft.print(buf);
      break;
    }
    case NOTICE_BAD:
      tft.setTextColor(COLOR_DANGER, COLOR_BG);
      tft.setCursor(40, 36);
      snprintf(buf, sizeof(buf), "Hatali PIN (kalan: %d)", _adminNoticeCount);
      tft.print(buf);
      break;
    case NOTICE_TIMEOUT:
      tft.setTextColor(COLOR_WARNING, COLOR_BG);
      tft.setCursor(40, 36);
      tft.print("Yanit yok, tekrar deneyin");
      break;
    case NOTICE_BUSY:
      tft.setTextColor(COLOR_WARNING, COLOR_BG);
      tft.setCursor(40, 36);
      tft.print("Role mesgul, tekrar deneyin");
      break;
    default:
      tft.setTextColor(COLOR_MUTED, COLOR_BG);
      tft.setCursor(55, 36);
      tft.print("6 Haneli Kodu Tuslayin");
      break;
  }
}

void ScreenManager::drawAdminPinScreen() {
  tft.fillScreen(COLOR_BG);

  // Başlık
  tft.setTextColor(COLOR_ACCENT, COLOR_BG);
  tft.setTextSize(2);
  tft.setCursor(35, 12);
  tft.print("Yonetici Girisi");

  // Hata uyarısı veya talimat
  drawAdminPinMessage();

  // PIN Gösterge Noktaları (6 haneli: ● ● ● ○ ○ ○)
  int startX = 45;
  for (int i = 0; i < 6; i++) {
    int cx = startX + (i * 26);
    int cy = 66;
    if (i < static_cast<int>(_pinBuffer.length())) {
      tft.fillCircle(cx, cy, 6, COLOR_ACCENT);
    } else {
      tft.drawCircle(cx, cy, 6, COLOR_MUTED);
    }
  }

  // 3x4 Numpad Tuş Takımı
  // Tuş boyutları: W: 64, H: 42, boşluklar: X=12, Y=8
  // Kolonlar: X0=18, X1=88, X2=158
  // Satırlar: Y0=82, Y1=132, Y2=182, Y3=232
  const char* labels[4][3] = {
    {"1", "2", "3"},
    {"4", "5", "6"},
    {"7", "8", "9"},
    {"Sil", "0", "Geri"}
  };

  const bool blocked = adminInputBlocked() || _pinWaiting;
  for (int r = 0; r < 4; r++) {
    for (int c = 0; c < 3; c++) {
      int bx = 18 + (c * 72);
      int by = 82 + (r * 50);
      const bool isBack = (r == 3 && c == 2);
      uint16_t btnBg = (r == 3 && c != 1) ? COLOR_CARD_BORDER : COLOR_CARD;
      uint16_t txtCol = (r == 3 && c == 0) ? COLOR_DANGER : ((r == 3 && c == 2) ? COLOR_WARNING : COLOR_TEXT);
      if (blocked && !isBack) {
        txtCol = COLOR_MUTED; // kilitliyken tuşlar soluk
      }

      tft.fillRoundRect(bx, by, 62, 42, 6, btnBg);
      tft.drawRoundRect(bx, by, 62, 42, 6, COLOR_CARD_BORDER);

      tft.setTextColor(txtCol, btnBg);
      if (r == 3 && (c == 0 || c == 2)) {
        tft.setTextSize(1);
        tft.setCursor(bx + 18, by + 16);
      } else {
        tft.setTextSize(2);
        tft.setCursor(bx + 25, by + 14);
      }
      tft.print(labels[r][c]);
    }
  }
}

void ScreenManager::showAdminMenuScreen() {
  wakeScreen();
  _currentState = STATE_ADMIN_MENU;
  _stateEnteredMs = millis();
  _autoReturnTimeoutMs = 0;
  _manualOpenSent = false;
  drawAdminMenuScreen();
  drawAdminSessionTimer();
}

void ScreenManager::drawAdminMenuScreen() {
  tft.fillScreen(COLOR_BG);

  // Başlık
  tft.setTextColor(COLOR_ACCENT, COLOR_BG);
  tft.setTextSize(2);
  tft.setCursor(35, 12);
  tft.print("YONETICI MENUSU");

  tft.drawFastHLine(0, 38, 240, COLOR_CARD_BORDER);

  // Menü Seçenekleri (Büyük dokunmatik butonlar: W: 200, H: 44, X: 20)
  // 1. Kapıyı Aç
  tft.fillRoundRect(20, 50, 200, 44, 8, COLOR_SUCCESS);
  tft.setTextColor(COLOR_TEXT, COLOR_SUCCESS);
  tft.setTextSize(2);
  tft.setCursor(45, 64);
  tft.print("KAPIYI AC");

  // 2. Bağlantı Durumu
  tft.fillRoundRect(20, 104, 200, 44, 8, COLOR_CARD);
  tft.drawRoundRect(20, 104, 200, 44, 8, COLOR_CARD_BORDER);
  tft.setTextColor(COLOR_TEXT, COLOR_CARD);
  tft.setTextSize(2);
  tft.setCursor(32, 118);
  tft.print("BAGLANTI DURUMU");

  // 3. Cihaz Bilgileri
  tft.fillRoundRect(20, 158, 200, 44, 8, COLOR_CARD);
  tft.drawRoundRect(20, 158, 200, 44, 8, COLOR_CARD_BORDER);
  tft.setTextColor(COLOR_TEXT, COLOR_CARD);
  tft.setTextSize(2);
  tft.setCursor(38, 172);
  tft.print("CIHAZ BILGISI");

  // 4. Ana Menüye Dön
  tft.fillRoundRect(20, 230, 200, 44, 8, COLOR_CARD_BORDER);
  tft.setTextColor(COLOR_WARNING, COLOR_CARD_BORDER);
  tft.setTextSize(2);
  tft.setCursor(55, 244);
  tft.print("GERI / CIKIS");
}

// Menü oturumunun kalan süresi (mutlak 20 sn) — ekranın altında küçük metin
void ScreenManager::drawAdminSessionTimer() {
  if (_adminSessionStartMs == 0) {
    return;
  }
  const unsigned long gecen = millis() - _adminSessionStartMs;
  const int kalan = gecen >= ADMIN_SESSION_MAX_MS ? 0 : static_cast<int>((ADMIN_SESSION_MAX_MS - gecen + 999UL) / 1000UL);
  tft.fillRect(0, 298, 240, 14, COLOR_BG);
  tft.setTextColor(kalan <= 5 ? COLOR_DANGER : COLOR_MUTED, COLOR_BG);
  tft.setTextSize(1);
  char buf[32];
  snprintf(buf, sizeof(buf), "Oturum: %d sn", kalan);
  tft.setCursor(80, 302);
  tft.print(buf);
}

void ScreenManager::showManualOpenConfirm() {
  wakeScreen();
  _currentState = STATE_MANUAL_OPEN;
  _stateEnteredMs = millis();
  _autoReturnTimeoutMs = 15000; // 15s yanıt yoksa menüye dön
  _manualOpenSent = false;
  drawManualOpenConfirmScreen();
  drawAdminSessionTimer();
}

void ScreenManager::drawManualOpenConfirmScreen() {
  tft.fillScreen(COLOR_BG);

  if (_manualOpenSent) {
    // ADMIN_OPEN gönderildi; ana MCU yanıtı bekleniyor (DOOR_OPENED veya ADMIN_DENIED)
    tft.setTextColor(COLOR_ACCENT, COLOR_BG);
    tft.setTextSize(2);
    tft.setCursor(45, 130);
    tft.print("Isleniyor...");
    return;
  }

  tft.setTextColor(COLOR_WARNING, COLOR_BG);
  tft.setTextSize(2);
  tft.setCursor(30, 40);
  tft.print("Kapi Acilsin mi?");

  tft.setTextColor(COLOR_MUTED, COLOR_BG);
  tft.setTextSize(1);
  tft.setCursor(35, 75);
  tft.print("Role aninda tetiklenecek!");

  // İptal Butonu (X: 20, Y: 150, W: 90, H: 48)
  tft.fillRoundRect(20, 150, 90, 48, 8, COLOR_DANGER);
  tft.setTextColor(COLOR_TEXT, COLOR_DANGER);
  tft.setTextSize(2);
  tft.setCursor(35, 166);
  tft.print("IPTAL");

  // Aç Butonu (X: 125, Y: 150, W: 95, H: 48)
  tft.fillRoundRect(125, 150, 95, 48, 8, COLOR_SUCCESS);
  tft.setTextColor(COLOR_TEXT, COLOR_SUCCESS);
  tft.setTextSize(2);
  tft.setCursor(155, 166);
  tft.print("AC");
}

void ScreenManager::showConnectionStatus() {
  wakeScreen();
  _currentState = STATE_STATUS;
  _stateEnteredMs = millis();
  _autoReturnTimeoutMs = 30000;
  // WROOM'dan güncel durumu talep et
  sendCommand(CMD_REQ_STATUS);
  drawConnectionStatusScreen();
  drawAdminSessionTimer();
}

void ScreenManager::drawConnectionStatusScreen() {
  tft.fillScreen(COLOR_BG);

  tft.setTextColor(COLOR_ACCENT, COLOR_BG);
  tft.setTextSize(2);
  tft.setCursor(30, 12);
  tft.print("BAGLANTI DURUMU");

  tft.drawFastHLine(0, 36, 240, COLOR_CARD_BORDER);

  // Wi-Fi Kartı
  tft.fillRoundRect(15, 46, 210, 42, 6, COLOR_CARD);
  tft.setTextColor(COLOR_MUTED, COLOR_CARD);
  tft.setTextSize(1);
  tft.setCursor(25, 52);
  tft.print("Wi-Fi SSID:");
  tft.setCursor(25, 66);
  tft.print("Sinyal (RSSI):");
  tft.setTextColor(COLOR_TEXT, COLOR_CARD);
  tft.setCursor(110, 52);
  tft.print(_wifiSsid.length() > 0 ? _wifiSsid : (_wifiConnected ? "Bagli" : "Kopuk"));
  tft.setCursor(110, 66);
  tft.print(_wifiRssi.length() > 0 ? _wifiRssi : "-");

  // IP Kartı
  tft.fillRoundRect(15, 96, 210, 42, 6, COLOR_CARD);
  tft.setTextColor(COLOR_MUTED, COLOR_CARD);
  tft.setCursor(25, 102);
  tft.print("Yerel IP:");
  tft.setCursor(25, 116);
  tft.print("MQTT Bulut:");
  tft.setTextColor(COLOR_TEXT, COLOR_CARD);
  tft.setCursor(110, 102);
  tft.print(_wifiIp.length() > 0 ? _wifiIp : "-");
  tft.setTextColor(_mqttConnected ? COLOR_SUCCESS : COLOR_DANGER, COLOR_CARD);
  tft.setCursor(110, 116);
  tft.print(_mqttConnected ? "Aktif (Bagli)" : "Kopuk");

  // Çalışma Süresi Kartı
  tft.fillRoundRect(15, 146, 210, 42, 6, COLOR_CARD);
  tft.setTextColor(COLOR_MUTED, COLOR_CARD);
  tft.setCursor(25, 152);
  tft.print("Calisma Suresi:");
  tft.setCursor(25, 166);
  tft.print("GM60 Optik:");
  tft.setTextColor(COLOR_TEXT, COLOR_CARD);
  tft.setCursor(110, 152);
  tft.print(_uptimeStr.length() > 0 ? _uptimeStr : "-");
  // Kamera durumu ana MCU'dan gelir (sahte "Hazir" yazısı yok)
  if (_cameraStatus == 1) {
    tft.setTextColor(COLOR_SUCCESS, COLOR_CARD);
    tft.setCursor(110, 166);
    tft.print("Hazir");
  } else if (_cameraStatus == 0) {
    tft.setTextColor(COLOR_DANGER, COLOR_CARD);
    tft.setCursor(110, 166);
    tft.print("Yok");
  } else {
    tft.setTextColor(COLOR_MUTED, COLOR_CARD);
    tft.setCursor(110, 166);
    tft.print("-");
  }

  // Geri Butonu
  tft.fillRoundRect(20, 240, 200, 44, 8, COLOR_CARD_BORDER);
  tft.setTextColor(COLOR_TEXT, COLOR_CARD_BORDER);
  tft.setTextSize(2);
  tft.setCursor(75, 254);
  tft.print("<- GERI");
}

void ScreenManager::showDeviceInfo() {
  wakeScreen();
  _currentState = STATE_DEVICE_INFO;
  _stateEnteredMs = millis();
  _autoReturnTimeoutMs = 30000;
  // WROOM'dan güncel donanım bilgilerini talep et
  sendCommand(CMD_REQ_INFO);
  drawDeviceInfoScreen();
  drawAdminSessionTimer();
}

void ScreenManager::drawDeviceInfoScreen() {
  tft.fillScreen(COLOR_BG);

  tft.setTextColor(COLOR_ACCENT, COLOR_BG);
  tft.setTextSize(2);
  tft.setCursor(40, 12);
  tft.print("CIHAZ BILGISI");

  tft.drawFastHLine(0, 36, 240, COLOR_CARD_BORDER);

  // Cihaz UID Kartı (gerçek UID ana MCU'dan SYS_INFO ile gelir; gelene kadar "-")
  tft.fillRoundRect(15, 46, 210, 52, 6, COLOR_CARD);
  tft.setTextColor(COLOR_MUTED, COLOR_CARD);
  tft.setTextSize(1);
  tft.setCursor(25, 54);
  tft.print("Cihaz Unique ID:");
  tft.setTextColor(COLOR_TEXT, COLOR_CARD);
  tft.setTextSize(1);
  tft.setCursor(25, 72);
  tft.print(_deviceUid.length() > 0 ? _deviceUid : "-");

  // Firmware & Donanım Kartı (ana MCU) + ekran kartı sürümü
  tft.fillRoundRect(15, 106, 210, 66, 6, COLOR_CARD);
  tft.setTextColor(COLOR_MUTED, COLOR_CARD);
  tft.setCursor(25, 114);
  tft.print("Firmware:");
  tft.setCursor(25, 132);
  tft.print("Hedef Kart:");
  tft.setCursor(25, 150);
  tft.print("Ekran FW:");
  tft.setTextColor(COLOR_TEXT, COLOR_CARD);
  tft.setCursor(95, 114);
  tft.print(_firmwareVersion.length() > 0 ? _firmwareVersion : "-");
  tft.setCursor(95, 132);
  tft.print(_hardwareTarget.length() > 0 ? _hardwareTarget : "-");
  tft.setCursor(95, 150);
  tft.print(DISPLAY_FIRMWARE_VERSION);

  // Geri Butonu
  tft.fillRoundRect(20, 240, 200, 44, 8, COLOR_CARD_BORDER);
  tft.setTextColor(COLOR_TEXT, COLOR_CARD_BORDER);
  tft.setTextSize(2);
  tft.setCursor(75, 254);
  tft.print("<- GERI");
}

void ScreenManager::drawQRCode(const String& data, int x, int y, int size) {
  QRCode qrcode;
  uint8_t qrcodeData[qrcode_getBufferSize(3)];
  tft.fillRect(x, y, size, size, TFT_WHITE);

  // Dönüş değeri kontrol edilir: metin sürüme sığmazsa (veya hata) rastgele/başlatılmamış modül çizilmez.
  if (qrcode_initText(&qrcode, qrcodeData, 3, ECC_LOW, data.c_str()) != 0) {
    tft.setTextColor(TFT_BLACK, TFT_WHITE);
    tft.setTextSize(2);
    tft.setCursor(x + 40, y + size / 2 - 8);
    tft.print("QR HATA");
    return;
  }

  int border = 2;
  int modules = qrcode.size;
  int scale = size / (modules + (border * 2));
  if (scale < 1) scale = 1;
  int offset = (size - ((modules + (border * 2)) * scale)) / 2;

  for (uint8_t qy = 0; qy < qrcode.size; qy++) {
    for (uint8_t qx = 0; qx < qrcode.size; qx++) {
      if (qrcode_getModule(&qrcode, qx, qy)) {
        tft.fillRect(
          x + offset + ((qx + border) * scale),
          y + offset + ((qy + border) * scale),
          scale,
          scale,
          TFT_BLACK
        );
      }
    }
  }
}

void ScreenManager::drawQrCountdownBar(bool forceRedraw) {
  // Zaman aşımı kontrolü (30 saniye)
  if (_qrTimerStartMs == 0) {
    _qrTimerStartMs = millis();
  }

  const unsigned long now = millis();
  if (!forceRedraw && (now - _lastBarUpdateMs < 150)) {
    return;
  }
  _lastBarUpdateMs = now;

  const unsigned long elapsed = now - _qrTimerStartMs;
  const unsigned long duration = 30000UL;
  const unsigned long remainingMs = (elapsed < duration) ? (duration - elapsed) : 0UL;
  const int remainingSec = (int)((remainingMs + 999UL) / 1000UL);
  if (remainingMs == 0UL) {
    // Süre doldu: damgayı "tam süre önce"ye çek. Böylece damga hiçbir zaman ~49,7 günden (millis() sarması) eski kalmaz; yoksa
    // yeni QR gelmeden o kadar süre sonra elapsed sarıp geri sayım yeniden 30 sn'den başlıyormuş gibi görünürdü.
    _qrTimerStartMs = now - duration;
    if (_qrTimerStartMs == 0) {
      _qrTimerStartMs = 1;  // 0 = "henüz başlamadı" işareti (yukarıda); 1 ms sapma önemsiz
    }
  }

  // 1. İlerleme Çubuğu (Progress Bar)
  const int barX = 30;
  const int barY = 266;
  const int barW = 180;
  const int barH = 8;
  const int fillW = (int)((barW * remainingMs) / duration);

  // Kalan süreye göre dinamik renk
  uint16_t barColor = COLOR_ACCENT;
  if (remainingSec <= 5) {
    barColor = COLOR_DANGER;
  } else if (remainingSec <= 12) {
    barColor = COLOR_WARNING;
  }

  // Zemin kartı ve dolgu
  tft.fillRoundRect(barX, barY, barW, barH, 4, COLOR_CARD);
  if (fillW > 0) {
    tft.fillRoundRect(barX, barY, fillW, barH, 4, barColor);
  }
  tft.drawRoundRect(barX, barY, barW, barH, 4, COLOR_CARD_BORDER);

  // 2. Kalan Süre Metni (Sadece saniye değiştiğinde güncellenir - flicker önleme)
  if (remainingSec != _lastRemainingSec || forceRedraw) {
    _lastRemainingSec = remainingSec;
    tft.fillRect(barX, 278, barW, 16, COLOR_BG);
    tft.setTextColor(remainingSec <= 5 ? COLOR_DANGER : COLOR_MUTED, COLOR_BG);
    tft.setTextSize(1);
    tft.setCursor(66, 282);
    tft.print("Kalan Sure: ");
    if (remainingSec < 10) tft.print("0");
    tft.print(remainingSec);
    tft.print(" sn");
  }
}

void ScreenManager::onTouch(int16_t x, int16_t y) {
  // Dokunma etkinliği (uyku/etkinsizlik sayacını sıfırlar)
  resetSleepTimer();

  // 1. Ana Ekran Dokunmaları
  if (_currentState == STATE_HOME) {
    // Ayarlar Butonu (Sağ üst: X: 190..240, Y: 0..35)
    if (x >= 190 && x <= 240 && y >= 0 && y <= 35) {
      showAdminPinScreen();
      return;
    }
    // Ekrana dokunulduğunda sadece uyanır (resetSleepTimer yukarıda çağrıldı).
    // Güvenlik gereği ana ekranda doğrudan yetkisiz kapı açma butonu yoktur.
    return;
  }

  // 2. PIN Giriş Ekranı Dokunmaları
  if (_currentState == STATE_ADMIN_PIN) {
    const char* labels[4][3] = {
      {"1", "2", "3"},
      {"4", "5", "6"},
      {"7", "8", "9"},
      {"Sil", "0", "Geri"}
    };
    for (int r = 0; r < 4; r++) {
      for (int c = 0; c < 3; c++) {
        int bx = 18 + (c * 72);
        int by = 82 + (r * 50);
        if (x >= bx && x <= bx + 64 && y >= by && y <= by + 45) {
          if (r == 3 && c == 2) { // Geri her zaman çalışır
            showHomeScreen();
            return;
          }
          // PIN yok / kilitli / doğrulama sürüyor: tuş girişi yok sayılır
          if (adminInputBlocked() || _pinWaiting) {
            return;
          }
          if (r == 3 && c == 0) { // Sil
            if (_pinBuffer.length() > 0) {
              _pinBuffer.remove(_pinBuffer.length() - 1);
              _adminNotice = NOTICE_NONE;
              drawAdminPinScreen();
            }
          } else { // Rakam tuşlandı
            if (_pinBuffer.length() < 6) {
              _pinBuffer += labels[r][c];
              _adminNotice = NOTICE_NONE;
              drawAdminPinScreen();
              // 6 hane tamamlandıysa ana MCU'ya doğrulat (PIN ekranda karşılaştırılmaz)
              if (_pinBuffer.length() == 6) {
                submitAdminPin();
              }
            }
          }
          return;
        }
      }
    }
    return;
  }

  // 3. Yönetici Menüsü Dokunmaları
  if (_currentState == STATE_ADMIN_MENU) {
    // 1. Kapıyı Aç (Y: 50..95)
    if (x >= 20 && x <= 220 && y >= 50 && y <= 95) {
      showManualOpenConfirm();
      return;
    }
    // 2. Bağlantı Durumu (Y: 104..150)
    if (x >= 20 && x <= 220 && y >= 104 && y <= 150) {
      showConnectionStatus();
      return;
    }
    // 3. Cihaz Bilgileri (Y: 158..205)
    if (x >= 20 && x <= 220 && y >= 158 && y <= 205) {
      showDeviceInfo();
      return;
    }
    // 4. Çıkış / Geri (Y: 230..275)
    if (x >= 20 && x <= 220 && y >= 230 && y <= 275) {
      showHomeScreen();
      return;
    }
    return;
  }

  // 4. Manuel Kapı Açma Onay Modalı Dokunmaları
  if (_currentState == STATE_MANUAL_OPEN) {
    if (_manualOpenSent) {
      return; // yanıt bekleniyor
    }
    // İptal (X: 20..110, Y: 150..200)
    if (x >= 20 && x <= 110 && y >= 150 && y <= 200) {
      showAdminMenuScreen();
      return;
    }
    // Aç (X: 125..220, Y: 150..200)
    if (x >= 125 && x <= 220 && y >= 150 && y <= 200) {
      // Ana MCU PIN'i yeniden doğrular (ADMIN_OPEN|<pin>); PIN gönderildikten sonra RAM'den silinir.
      if (_sessionPin.length() != 6) {
        endAdminSession();
        showHomeScreen();
        return;
      }
      String cmd = String(CMD_ADMIN_OPEN) + "|" + _sessionPin;
      sendCommand(cmd.c_str());
      _sessionPin = "";
      _adminSessionStartMs = 0;
      _manualOpenSent = true;
      _stateEnteredMs = millis();
      _autoReturnTimeoutMs = 4000; // yanıt (DOOR_OPENED / ADMIN_DENIED) gelmezse ana ekrana dön
      drawManualOpenConfirmScreen();
      return;
    }
    return;
  }

  // 5. Durum veya Cihaz Bilgisi Ekranından Geri Dönüş
  if (_currentState == STATE_STATUS || _currentState == STATE_DEVICE_INFO) {
    // Alt Geri Butonu (Y: 235..290)
    if (x >= 20 && x <= 220 && y >= 235 && y <= 290) {
      showAdminMenuScreen();
      return;
    }
  }
}

void ScreenManager::onButtonPress() {
  resetSleepTimer();
  sendCommand(CMD_BTN_OPEN);
}

// Ana MCU'dan gelen satırı işler. NOT: komut almak ekranı "uyandırmaz"/etkinsizlik sayacını sıfırlamaz;
// yalnızca dokunma/buton sıfırlar (periyodik SHOW_QR / durum satırları PIN ekranını sonsuza dek açık tutmasın).
void ScreenManager::processCommand(const String& cmd) {
  if (cmd == CMD_MAIN_READY || cmd == CMD_SHOW_HOME) {
    // Zaten home ekranındaysa yeniden çizme (flash önleme)
    if (_currentState != STATE_HOME) {
      showHomeScreen();
    }
  } else if (cmd == CMD_QR_READING) {
    showQrReading();
  } else if (cmd == CMD_DOOR_OPENED) {
    showDoorOpened();
  } else if (cmd == CMD_DOOR_CLOSED) {
    showDoorClosed();
  } else if (cmd == CMD_QR_DENIED) {
    showQrDenied();
  } else if (cmd == CMD_WIFI_CONNECTED) {
    setWifiStatus(true);
  } else if (cmd == CMD_WIFI_DISCONNECTED) {
    setWifiStatus(false);
    setMqttStatus(false); // Wi-Fi yokken bulut bağlantısı da yoktur
  } else if (cmd == CMD_MQTT_CONNECTED) {
    setMqttStatus(true);
  } else if (cmd == CMD_MQTT_DISCONNECTED) {
    setMqttStatus(false);
  } else if (cmd == CMD_ADMIN_OK) {
    handleAdminOk();
  } else if (cmd.startsWith(CMD_ADMIN_DENIED_PREFIX)) {
    handleAdminDenied(cmd.substring(strlen(CMD_ADMIN_DENIED_PREFIX)));
  } else if (cmd.startsWith(CMD_ADMIN_STATE_PREFIX)) {
    handleAdminState(cmd.substring(strlen(CMD_ADMIN_STATE_PREFIX)));
  } else if (cmd.startsWith(CMD_SYS_STATUS_PREFIX)) {
    // SYS_STATUS|SSID|IP|RSSI|MQTT|UPTIME[|CAM]  (ana MCU SSID içindeki '|' karakterini temizler)
    String rest = cmd.substring(strlen(CMD_SYS_STATUS_PREFIX));
    String f[6];
    int count = 0;
    int start = 0;
    for (int i = 0; i <= static_cast<int>(rest.length()) && count < 6; i++) {
      if (i == static_cast<int>(rest.length()) || rest[i] == '|') {
        f[count++] = rest.substring(start, i);
        start = i + 1;
      }
    }
    if (count >= 5) {
      const int camera = (count >= 6) ? (f[5] == "1" ? 1 : 0) : -1;
      updateSystemStatus(f[0], f[1], f[2], f[3] == "1", f[4], camera);
    }
  } else if (cmd.startsWith(CMD_SYS_INFO_PREFIX)) {
    // SYS_INFO|UID|FW|TARGET
    String rest = cmd.substring(strlen(CMD_SYS_INFO_PREFIX));
    int p1 = rest.indexOf('|');
    int p2 = rest.indexOf('|', p1 + 1);
    String uid = (p1 > 0) ? rest.substring(0, p1) : "";
    String fw = (p2 > p1 && p1 > 0) ? rest.substring(p1 + 1, p2) : "";
    String target = (p2 > 0) ? rest.substring(p2 + 1) : "";
    updateDeviceInfo(uid, fw, target);
  } else if (cmd.startsWith(CMD_SHOW_QR_PREFIX)) {
    String newQr = cmd.substring(strlen(CMD_SHOW_QR_PREFIX));
    // Biçim doğrulaması: boş/aşırı uzun veri QR sürümüne sığmaz (qrcode_initText hata verir)
    if (newQr.length() == 0 || newQr.length() > 60) {
      return;
    }
    if (newQr != _qrData) {
      // Yeni QR — veriyi güncelle ve home ekranındaysa sadece QR bölgesini yeniden çiz
      _qrData = newQr;
      if (_currentState == STATE_HOME && !_isSleeping) {
        // Tüm ekranı yeniden çizmek yerine sadece QR çerçeve alanını güncelle
        tft.fillRoundRect(30, 78, 180, 180, 10, COLOR_CARD);
        tft.drawRoundRect(30, 78, 180, 180, 10, COLOR_CARD_BORDER);
        drawQRCode(_qrData, 36, 84, 168);
        _qrTimerStartMs = millis();
        _lastRemainingSec = -1;
        drawQrCountdownBar(true);
      } else {
        _qrTimerStartMs = millis();
        _lastRemainingSec = -1;
      }
    }
    // Aynı QR ise hiçbir şey yapma (flash önleme)
  }
}
