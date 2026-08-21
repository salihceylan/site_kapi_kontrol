# Technology Stack

## Core Sections (Required)

### 1) Runtime Summary

| Area | Value | Evidence |
|------|-------|----------|
| Primary language | Dart/Flutter for the company client; JavaScript for the API; C++ for ESP32 firmware; Python for the QR/firmware desktop helper | `pubspec.yaml`, `server/package.json`, `cihaz_kontrol/platformio.ini`, `company_qr_tool/requirements.txt` |
| Runtime + version | Dart SDK constraint `^3.11.0`; Node.js version is `[TODO]`; Python requirement is 3.10+ in README; PlatformIO uses Arduino framework on Espressif32 | `pubspec.yaml`, `server/package.json`, `company_qr_tool/README.md`, `cihaz_kontrol/platformio.ini` |
| Package manager | Flutter/Dart pub; npm; pip; PlatformIO | `pubspec.yaml`, `server/package.json`, `company_qr_tool/requirements.txt`, `cihaz_kontrol/platformio.ini` |
| Module/build system | Flutter multi-platform app, Node ESM API, Docker Compose PostgreSQL, PlatformIO firmware | `.metadata`, `server/package.json`, `docker-compose.yml`, `cihaz_kontrol/platformio.ini` |

### 2) Production Frameworks and Dependencies

| Dependency | Version | Role in system | Evidence |
|------------|---------|----------------|----------|
| Flutter | SDK dependency | Company UI application | `pubspec.yaml` |
| http | `^1.2.2` | REST API client in Flutter | `pubspec.yaml`, `lib/services/auth_api.dart` |
| mobile_scanner | `^7.2.0` | QR scanning | `pubspec.yaml`, `lib/ui/pages/qr_scan_page.dart` |
| mqtt_client | `^10.7.0` | MQTT door state/command transport | `pubspec.yaml`, `lib/services/mqtt_door_service_io.dart` |
| shared_preferences | `^2.5.3` | Local auth session persistence | `pubspec.yaml`, `lib/services/auth_service.dart` |
| permission_handler | `^12.0.1` | Device permissions | `pubspec.yaml` |
| flutter_reactive_ble | `^5.4.0` | BLE Wi-Fi provisioning | `pubspec.yaml`, `lib/services/ble_wifi_provision_service.dart` |
| express | `^4.21.2` | HTTP API server | `server/package.json`, `server/src/server.js` |
| pg | `^8.13.1` | PostgreSQL access | `server/package.json`, `server/src/db.js` |
| jsonwebtoken | `^9.0.2` | Access token signing/verification | `server/package.json`, `server/src/jwt.js` |
| bcryptjs | `^2.4.3` | Password and verification-code hashing | `server/package.json`, `server/src/server.js` |
| nodemailer | `^6.10.1` | Email verification and apartment credential delivery | `server/package.json`, `server/src/mailer.js` |
| PubSubClient | unpinned | ESP32 MQTT client | `cihaz_kontrol/platformio.ini`, `cihaz_kontrol/include/mqtt_baglanti.h` |
| ArduinoJson | `^7.3.1` | ESP32 JSON handling | `cihaz_kontrol/platformio.ini` |
| qrcode[pil], Pillow, pyserial, esptool | minimum versions in requirements | Windows QR generation, serial detection, firmware upload | `company_qr_tool/requirements.txt`, `company_qr_tool/README.md` |

### 3) Development Toolchain

| Tool | Purpose | Evidence |
|------|---------|----------|
| flutter_lints | Dart lint rules | `pubspec.yaml`, `analysis_options.yaml` |
| flutter_test | Flutter widget test framework | `pubspec.yaml`, `test/widget_test.dart` |
| node --watch | API development runner | `server/package.json` |
| node --check | Syntax check documented for backend | `PROJE_TEKNIK_NOTLAR.md` |
| Docker Compose | Local PostgreSQL runtime | `docker-compose.yml`, `README.md` |
| PM2 | Production API process manager | `sunucu_kurulum.txt`, `PROJE_TEKNIK_NOTLAR.md` |
| PlatformIO | ESP32 firmware build/upload | `cihaz_kontrol/platformio.ini`, `company_qr_tool/README.md` |

### 4) Key Commands

```bash
flutter pub get
flutter analyze
flutter test
flutter run --dart-define=API_BASE_URL=http://localhost:8080

docker compose up -d postgres

cd server
npm install
npm run dev
npm start
node --check src/server.js
```

### 5) Environment and Config

- Config sources: `lib/config/app_config.dart`, `server/.env.example`, `docker-compose.yml`, `cihaz_kontrol/include/mqtt_baglanti.h`.
- Required backend env vars: `PORT`, `JWT_SECRET`, `JWT_EXPIRES_IN`, `DB_HOST`, `DB_PORT`, `DB_NAME`, `DB_USER`, `DB_PASSWORD`, `SMTP_HOST`, `SMTP_PORT`, `SMTP_USER`, `SMTP_PASSWORD`, `SMTP_FROM`, `MQTT_HOST`, `MQTT_PORT`, `MQTT_USER`, `MQTT_PASSWORD`.
- Flutter compile-time config: `API_BASE_URL`.
- Deployment/runtime constraints: PostgreSQL is provided through Docker Compose locally; production notes document Nginx, PM2, SSL, and VPS deployment.

### 6) Evidence

- `pubspec.yaml`
- `server/package.json`
- `server/.env.example`
- `docker-compose.yml`
- `cihaz_kontrol/platformio.ini`
- `company_qr_tool/requirements.txt`
- `PROJE_TEKNIK_NOTLAR.md`
