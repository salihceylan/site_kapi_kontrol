# Codebase Structure

## Core Sections (Required)

### 1) Top-Level Map

| Path | Purpose | Evidence |
|------|---------|----------|
| `lib/` | Flutter company app source: app bootstrap, config, models, services, styles, pages, widgets | `docs/codebase/.codebase-scan.txt`, `lib/app.dart` |
| `server/` | Node/Express API and PostgreSQL migrations | `server/package.json`, `server/src/server.js`, `server/migrations/` |
| `cihaz_kontrol/` | PlatformIO ESP32 firmware | `cihaz_kontrol/platformio.ini`, `cihaz_kontrol/src/main.cpp` |
| `company_qr_tool/` | Windows Python desktop helper for ESP32 scan, QR creation, firmware build/upload | `company_qr_tool/README.md`, `company_qr_tool/app.py`, `company_qr_tool/requirements.txt` |
| `assets/` | Flutter image assets | `pubspec.yaml`, `assets/images/app_logo.png` |
| `android/`, `ios/`, `linux/`, `macos/`, `web/`, `windows/` | Flutter platform shells | `.metadata`, `docs/codebase/.codebase-scan.txt` |
| `test/` | Flutter tests | `test/widget_test.dart` |
| `.github/` | GitHub-related metadata; no CI workflow detected by scan | `docs/codebase/.codebase-scan.txt` |
| `docker-compose.yml` | PostgreSQL service definition | `docker-compose.yml` |
| `README.md`, `PROJE_TEKNIK_NOTLAR.md`, `sunucu_kurulum.txt`, `MQTT_kurulum.txt` | Project intent and operations documentation | listed files |

### 2) Entry Points

- Main runtime entry: `lib/main.dart` calls `runApp(const MyApp())`.
- Flutter app root: `lib/app.dart` creates `AuthService`, `NetworkService`, and selects login/home/no-internet pages.
- API runtime entry: `server/src/server.js`, selected by `server/package.json` scripts `start` and `dev`.
- API database bootstrap: `server/src/db.js` exports `ensureDbSchema()`, called during API startup.
- Firmware entry: `cihaz_kontrol/src/main.cpp`.
- QR/firmware helper entry: `company_qr_tool/app.py`; Windows launcher is `company_qr_tool/launch_company_qr_tool.bat`.

### 3) Module Boundaries

| Boundary | What belongs here | What must not be here |
|----------|-------------------|------------------------|
| Flutter `models/` | JSON-backed records and value objects | HTTP transport or UI rendering |
| Flutter `services/` | API calls, auth session state, network checks, MQTT/BLE services | Page layout and visual styling |
| Flutter `ui/pages/` and `ui/widgets/` | Screens and reusable widgets | Backend schema migrations |
| Flutter `styles/` | Theme, colors, decorations | Business flows or API calls |
| `server/src/` | Express routes, auth middleware, DB bootstrap, JWT, mailer | Flutter UI or firmware code |
| `server/migrations/` | PostgreSQL schema migration files | Runtime route handlers |
| `cihaz_kontrol/` | Embedded Wi-Fi, MQTT, role/door control | Company desktop QR UI |
| `company_qr_tool/` | Windows serial/QR/firmware helper | API server endpoints |

### 4) Naming and Organization Rules

- File naming pattern: Dart files use `snake_case` such as `auth_service.dart`, `site_record.dart`; Node files use short lowercase names such as `server.js`, `db.js`; firmware headers use Turkish `snake_case` such as `mqtt_baglanti.h`.
- Directory organization pattern: Flutter is layer-oriented (`models`, `services`, `styles`, `ui`); backend is mostly flat under `server/src`; firmware uses PlatformIO `src`, `include`, `lib`, `test`.
- Import aliasing or path conventions: Flutter imports use package imports such as `package:site_kapi_kontrol/services/auth_api.dart`; backend uses relative ESM imports such as `./db.js`.

### 5) Evidence

- `docs/codebase/.codebase-scan.txt`
- `lib/main.dart`
- `lib/app.dart`
- `server/package.json`
- `server/src/server.js`
- `server/src/db.js`
- `cihaz_kontrol/platformio.ini`
- `company_qr_tool/README.md`
