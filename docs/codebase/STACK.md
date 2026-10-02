# Technology Stack

## Core Sections (Required)

### 1) Runtime Summary

| Area | Value | Evidence |
|------|-------|----------|
| Primary language | Dart/Flutter for the company client; JavaScript for the API; C++ for ESP32 firmware; Python for the QR/firmware desktop helper | `pubspec.yaml`, `server/package.json`, `cihaz_kontrol/platformio.ini`, `company_qr_tool/requirements.txt` |
| Runtime + version | Dart SDK constraint `^3.11.0`; Node.js >= 20.19 (`engines`; CI and `.nvmrc` use Node 24); Python requirement is 3.10+ in README; PlatformIO uses Arduino framework on Espressif32 | `pubspec.yaml`, `server/package.json`, `company_qr_tool/README.md`, `cihaz_kontrol/platformio.ini` |
| Package manager | Flutter/Dart pub; npm; pip; PlatformIO | `pubspec.yaml`, `server/package.json`, `company_qr_tool/requirements.txt`, `cihaz_kontrol/platformio.ini` |
| Module/build system | Flutter multi-platform app, Node ESM API, Docker Compose PostgreSQL, PlatformIO firmware | `.metadata`, `server/package.json`, `docker-compose.yml`, `cihaz_kontrol/platformio.ini` |

### 2) Production Frameworks and Dependencies

| Dependency | Version | Role in system | Evidence |
|------------|---------|----------------|----------|
| Flutter | SDK dependency | Company UI application | `pubspec.yaml` |
| http | `^1.2.2` | REST API client in Flutter | `pubspec.yaml`, `lib/services/auth_api.dart` |
| mobile_scanner | `^7.2.0` | QR scanning | `pubspec.yaml`, `lib/ui/pages/qr_scan_page.dart` |
| mqtt_client | `^10.7.0` | MQTT door state/command transport | `pubspec.yaml`, `lib/services/mqtt_door_service_io.dart` |
| flutter_secure_storage | `^10.0.0` | Session token storage (shared_preferences `^2.5.3` only for non-secret settings and one-time migration) | `pubspec.yaml`, `lib/services/auth_service.dart` |
| geolocator | `^13.0.2` | Location for server-side geofence checks | `pubspec.yaml`, `lib/services/geofence_service.dart` |
| crypto | `^3.0.6` | HMAC-SHA256 signatures for local door control v2 | `pubspec.yaml`, `lib/services/local_door_service.dart` |
| home_widget, app_links, quick_actions | `^0.9.4`, `^6.4.1`, `^1.1.0` | Android home-screen widget, `sitekapi://` deep links, launcher shortcuts | `pubspec.yaml`, `lib/services/door_widget_service.dart`, `lib/services/deep_link_service.dart` |
| speech_to_text, flutter_tts | `^7.3.0`, `^4.2.3` | Voice door command | `pubspec.yaml`, `lib/services/voice_door_service.dart` |
| permission_handler | `^12.0.1` | Device permissions | `pubspec.yaml` |
| flutter_reactive_ble | `^5.4.0` | BLE Wi-Fi provisioning | `pubspec.yaml`, `lib/services/ble_wifi_provision_service.dart` |
| express | `^4.21.2` | HTTP API server | `server/package.json`, `server/src/server.js` |
| pg | `^8.13.1` | PostgreSQL access | `server/package.json`, `server/src/db.js` |
| jsonwebtoken | `^9.0.2` | Access token signing/verification | `server/package.json`, `server/src/jwt.js` |
| bcryptjs | `^2.4.3` | Password and verification-code hashing | `server/package.json`, `server/src/services/` |
| mqtt | `^5.14.1` | API <-> broker (TLS) | `server/package.json`, `server/src/mqtt_bridge.js` |
| nodemailer | `^10.0.13` | Email verification and apartment credential delivery | `server/package.json`, `server/src/mailer.js` |
| PubSubClient | `^2.8` | ESP32 MQTT client | `cihaz_kontrol/platformio.ini`, `cihaz_kontrol/include/mqtt_baglanti.h` |
| ArduinoJson | `^7.3.1` | ESP32 JSON handling | `cihaz_kontrol/platformio.ini` |
| qrcode[pil], Pillow, pyserial, esptool | minimum versions in requirements | Windows QR generation, serial detection, firmware upload | `company_qr_tool/requirements.txt`, `company_qr_tool/README.md` |

### 3) Development Toolchain

| Tool | Purpose | Evidence |
|------|---------|----------|
| flutter_lints | Dart lint rules | `pubspec.yaml`, `analysis_options.yaml` |
| flutter_test, integration_test | Flutter unit/widget and integration test frameworks (2357 unit/widget tests; integration/perf harnesses are run manually) | `pubspec.yaml`, `test/`, `integration_test/`, `test_driver/` |
| MSVC + Python (host tests) | Firmware logic tests against stubbed hardware (`python cihaz_kontrol/host_test/run_all.py`) | `cihaz_kontrol/host_test/README.md` |
| node:test (`node --test`) | Backend test runner | `server/package.json`, `server/test/` |
| ESLint | Backend lint (`npm run lint`) | `server/package.json`, `server/eslint.config.js` |
| node --watch | API development runner | `server/package.json` |
| node --check | Syntax check for backend files | `PROJE_TEKNIK_NOTLAR.md` |
| GitHub Actions | CI: server lint/test, Flutter analyze/test, secret scan | `.github/workflows/ci.yml` |
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
npm ci
npm run dev
npm start
npm test
npm run lint
node scripts/migrate.js --status
```

### 5) Environment and Config

- Config sources: `lib/config/app_config.dart`, `server/.env.example`, `docker-compose.yml`, `cihaz_kontrol/include/device_konfig.h`, `cihaz_kontrol/include/mqtt_baglanti.h`.
- Required backend env vars: `PORT`, `JWT_SECRET` (>= 32 chars), `DB_HOST`, `DB_PORT`, `DB_NAME`, `DB_USER`, `DB_PASSWORD`, `SMTP_HOST`, `SMTP_PORT`, `SMTP_USER`, `SMTP_PASSWORD`, `SMTP_FROM`, `MQTT_HOST`, `MQTT_PORT`, `MQTT_USER`, `MQTT_PASSWORD`, `PUBLIC_BASE_URL`; recommended: `COMPANY_API_KEY` (>= 24 chars), `CORS_ORIGINS`, `JWT_EXPIRES_IN` (default 30d), `NODE_ENV=production`; optional: `DB_POOL_MAX`, `DB_STATEMENT_TIMEOUT_MS`, `DB_CONNECT_TIMEOUT_MS` (see `server/.env.example`).
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
