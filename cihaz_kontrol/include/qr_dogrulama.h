#ifndef QR_DOGRULAMA_H
#define QR_DOGRULAMA_H

// !!! KULLANILMIYOR (olu kod) !!!
// Bu dosya hicbir yerden include edilmez ve qrKoduGecerliMi() hicbir yerde cagrilmaz. QR dogrulamasi
// YALNIZ sunucuda yapilir (gm60_scanner.h -> MQTT qr_verify -> qr_result). Asagidaki yerel kurallar
// (UID/uzunluk/on-ek tabanli kabul) GUVENLIDIR DEGIL; kapi acma karari icin ASLA kullanilmamali.
// Silinmedi: gecmis referans icin tutuluyor.

#include <Arduino.h>
#include "role_kontrol.h"
#include "wifi_baglanti.h"

inline bool qrKoduGecerliMi(const String& rawData, String& outReason) {
  String data = rawData;
  data.trim();

  if (data.isEmpty()) {
    outReason = "Bos QR";
    return false;
  }

  // 1. Direct match with Local Control Token
  const String localToken = wifiLocalControlToken();
  if (!localToken.isEmpty() && data == localToken) {
    outReason = "Lokal Token Eslesti";
    return true;
  }

  // 2. Direct match with Device Unique ID
  if (data == cihazUniqueId()) {
    outReason = "Cihaz UID Master QR";
    return true;
  }

  // 3. Dynamic Prefix Format (DYN:timestamp:token or GP:token)
  if (data.startsWith("GP:") || data.startsWith("DYN:") || data.startsWith("QR:")) {
    outReason = "Gecerli Formatli QR";
    return true;
  }

  // 4. Fallback minimum length check for secure passes (e.g. 16+ chars)
  if (data.length() >= 16) {
    outReason = "Token Dogrulandi";
    return true;
  }

  outReason = "Gecersiz QR Formati";
  return false;
}

#endif
