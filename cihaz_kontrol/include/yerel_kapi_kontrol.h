#ifndef YEREL_KAPI_KONTROL_H
#define YEREL_KAPI_KONTROL_H

#include <Arduino.h>
#include <WiFi.h>

#include "device_konfig.h"
#include "ota_guncelleme.h"
#include "role_kontrol.h"
#include "wifi_baglanti.h"

inline WiFiServer gYerelKapiServer(YEREL_KAPI_KONTROL_PORT);
inline bool gYerelKapiServerAktif = false;

extern bool gDoorLocked;

struct YerelHttpIstek {
  String method;
  String path;
  String token;
  String deviceUid;
};

inline void yerelHttpCevap(WiFiClient& client, int code, const char* status, const String& body) {
  client.print("HTTP/1.1 ");
  client.print(code);
  client.print(" ");
  client.println(status);
  client.println("Content-Type: application/json");
  client.println("Connection: close");
  client.print("Content-Length: ");
  client.println(body.length());
  client.println();
  client.print(body);
}

inline String yerelJsonEscape(const String& raw) {
  String escaped;
  escaped.reserve(raw.length() + 4);
  for (size_t i = 0; i < raw.length(); i += 1) {
    const char c = raw.charAt(i);
    if (c == '"' || c == '\\') {
      escaped += '\\';
    }
    escaped += c;
  }
  return escaped;
}

void mqttPublishEvent(const char* eventName, const char* detail);
void mqttPublishState(bool locked);

inline bool yerelHttpIstekOku(WiFiClient& client, YerelHttpIstek& request) {
  const unsigned long startedAt = millis();
  String firstLine;

  while (client.connected() && millis() - startedAt < 150) {
    if (!client.available()) {
      yield();
      delay(1);
      continue;
    }
    firstLine = client.readStringUntil('\n');
    firstLine.trim();
    break;
  }

  const int firstSpace = firstLine.indexOf(' ');
  const int secondSpace = firstLine.indexOf(' ', firstSpace + 1);
  if (firstSpace <= 0 || secondSpace <= firstSpace) {
    return false;
  }
  request.method = firstLine.substring(0, firstSpace);
  request.path = firstLine.substring(firstSpace + 1, secondSpace);

  while (client.connected() && millis() - startedAt < 250) {
    if (!client.available()) {
      yield();
      delay(1);
      continue;
    }

    String line = client.readStringUntil('\n');
    line.trim();
    if (line.isEmpty()) {
      break;
    }

    const int separator = line.indexOf(':');
    if (separator <= 0) {
      continue;
    }
    String name = line.substring(0, separator);
    String value = line.substring(separator + 1);
    name.trim();
    value.trim();
    name.toLowerCase();

    if (name == "x-ahbu-local-token") {
      request.token = value;
    } else if (name == "x-ahbu-device-uid") {
      request.deviceUid = value;
    }
  }

  return true;
}

inline bool yerelYetkiKontrol(WiFiClient& client, const YerelHttpIstek& request) {
  const String savedToken = wifiLocalControlToken();
  if (savedToken.isEmpty() || request.token != savedToken) {
    yerelHttpCevap(client, 401, "Unauthorized", R"({"ok":false,"error":"yetkisiz"})");
    return false;
  }

  if (!request.deviceUid.isEmpty() && request.deviceUid != cihazUniqueId()) {
    yerelHttpCevap(client, 404, "Not Found", R"({"ok":false,"error":"cihaz_uid_eslesmedi"})");
    return false;
  }

  return true;
}

inline void yerelStatusHandler(WiFiClient& client, const YerelHttpIstek& request) {
  if (!yerelYetkiKontrol(client, request)) {
    return;
  }

  String body = "{";
  body += "\"ok\":true";
  body += ",\"device_uid\":\"" + yerelJsonEscape(cihazUniqueId()) + "\"";
  body += ",\"firmware_version\":\"" + yerelJsonEscape(OTA_CURRENT_VERSION) + "\"";
  body += ",\"wifi_connected\":";
  body += wifiHazirMi() ? "true" : "false";
  body += ",\"ip\":\"" + yerelJsonEscape(wifiIpAdresi()) + "\"";
  body += ",\"local_control_port\":";
  body += String(YEREL_KAPI_KONTROL_PORT);
  body += ",\"local_control_available\":";
  body += wifiHasLocalControlToken() ? "true" : "false";
  body += ",\"door_locked\":";
  body += gDoorLocked ? "true" : "false";
  body += "}";
  yerelHttpCevap(client, 200, "OK", body);
}

inline void yerelOpenHandler(WiFiClient& client, const YerelHttpIstek& request) {
  if (!yerelYetkiKontrol(client, request)) {
    return;
  }

  roleTetikle();
  gDoorLocked = false;
  mqttPublishEvent("local_pulse_started", "");
  mqttPublishState(gDoorLocked);
  yerelHttpCevap(client, 202, "Accepted", R"({"ok":true,"message":"yerel_kapi_acma_komutu_alindi"})");
  Serial.println("Yerel ag komutu: kapi acma pulse baslatildi.");
}

inline void yerelKapiKontrolBaslat() {
  if (gYerelKapiServerAktif || !wifiHazirMi()) {
    return;
  }

  gYerelKapiServer.begin();
  gYerelKapiServer.setNoDelay(true);
  gYerelKapiServerAktif = true;
  Serial.print("Yerel kapi kontrol aktif: http://");
  Serial.print(wifiIpAdresi());
  Serial.print(":");
  Serial.print(YEREL_KAPI_KONTROL_PORT);
  Serial.println("/ahbu/status");
}

inline void yerelKapiKontrolDurdur() {
  if (!gYerelKapiServerAktif) {
    return;
  }

  gYerelKapiServer.stop();
  gYerelKapiServerAktif = false;
  Serial.println("Yerel kapi kontrol durduruldu.");
}

inline void yerelKapiKontrolLoop() {
  if (!wifiHazirMi()) {
    yerelKapiKontrolDurdur();
    return;
  }

  yerelKapiKontrolBaslat();
  WiFiClient client = gYerelKapiServer.available();
  if (!client) {
    return;
  }

  YerelHttpIstek request;
  if (!yerelHttpIstekOku(client, request)) {
    yerelHttpCevap(client, 400, "Bad Request", R"({"ok":false,"error":"gecersiz_istek"})");
    client.stop();
    return;
  }

  if (request.method == "GET" && request.path == "/ahbu/status") {
    yerelStatusHandler(client, request);
  } else if (request.method == "POST" && request.path == "/ahbu/open") {
    yerelOpenHandler(client, request);
  } else {
    yerelHttpCevap(client, 404, "Not Found", R"({"ok":false,"error":"route_bulunamadi"})");
  }
  delay(1);
  client.stop();
}

inline bool yerelKapiKontrolAktifMi() {
  return gYerelKapiServerAktif;
}

#endif
