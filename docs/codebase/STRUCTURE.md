# Codebase Structure

## Core Sections (Required)

### 1) Top-Level Map

| Path | Purpose | Evidence |
|------|---------|----------|
| `lib/` | Flutter app source: bootstrap, config, models, services, styles, design system (`ui/design/`), pages, views, dialogs, widgets | `lib/app.dart` |
| `server/` | Node/Express API, PostgreSQL migrations, scripts, tests | `server/package.json`, `server/src/server.js`, `server/migrations/` |
| `cihaz_kontrol/` | PlatformIO ESP32 door-controller firmware (`lolin_c3_mini`, `esp32_relay_wroom`), release artifacts, and host-side firmware tests (`host_test/`) | `cihaz_kontrol/platformio.ini`, `cihaz_kontrol/src/main.cpp`, `cihaz_kontrol/host_test/README.md` |
| `ekran_yazilimi/` | PlatformIO firmware for the touch display board (`esp32c3_display`) connected to the WROOM controller | `ekran_yazilimi/platformio.ini` |
| `company_qr_tool/` | Windows Python desktop helper for ESP32 scan, QR creation, firmware build/upload | `company_qr_tool/README.md`, `company_qr_tool/app.py` |
| `android/`, `ios/`, `linux/`, `macos/`, `web/`, `windows/` | Flutter platform shells (Android widget and manifest settings live in `android/`) | `.metadata` |
| `test/` | Flutter unit/widget tests | `test/` |
| `integration_test/`, `test_driver/` | Flutter integration tests: menu walkers per role, harness self-test, frame-time harness (`perf_frames_test.dart` + `test_driver/perf_driver.dart`); run by the owner, not by CI | `integration_test/`, `test_driver/` |
| `deploy/` | Production deployment scripts (backup, prepare, activate, rollback, verify, read-only audit) used for rule 8 | `deploy/README.md` |
| `docs/` | Generated codebase notes (`docs/codebase/`) and the local control protocol contract (`docs/YEREL_KONTROL_V2.md`) | `docs/` |
| `.github/workflows/` | CI (server lint/test, Flutter analyze/test, secret scan) | `.github/workflows/ci.yml` |
| `docker-compose.yml` | PostgreSQL service definition (loopback only) | `docker-compose.yml` |
| `README.md`, `AGENTS.md`, `PROJE_TEKNIK_NOTLAR.md`, `sunucu_kurulum.txt`, `MQTT_kurulum.txt`, `OTA_KURULUM.txt`, `SAHA_KONTROL_LISTESI.md`, `BEKLEYEN_ISLER.md` | Project rules, operations and verification documentation | listed files |

### 2) Entry Points

- Main runtime entry: `lib/main.dart` calls `runApp(const MyApp())`.
- Flutter app root: `lib/app.dart` creates `AuthService`, `NetworkService`, and selects login/home/no-internet pages.
- API runtime entry: `server/src/server.js`, selected by `server/package.json` scripts `start` and `dev` (PM2: `server/ecosystem.config.cjs`).
- API database bootstrap: `server/src/db.js` exports `ensureDbSchema()`, called during API startup; migrations run via `server/scripts/migrate.js`.
- MQTT bridge: `server/src/mqtt_bridge.js`, started by `server.js`.
- Firmware entries: `cihaz_kontrol/src/main.cpp`, `ekran_yazilimi/src/main.cpp`.
- QR/firmware helper entry: `company_qr_tool/app.py`; Windows launcher is `company_qr_tool/launch_company_qr_tool.bat`.

### 3) Module Boundaries

| Boundary | What belongs here | What must not be here |
|----------|-------------------|------------------------|
| Flutter `models/` | JSON-backed records and value objects | HTTP transport or UI rendering |
| Flutter `services/` | API calls, auth session state, network checks, local door control, MQTT/BLE/widget/voice services | Page layout and visual styling |
| Flutter `ui/pages/`, `ui/views/`, `ui/dialogs/`, `ui/widgets/` | Screens, role views, dialogs, reusable widgets | Backend schema migrations |
| Flutter `styles/` | Theme, colors, decorations, role themes (wired to the design tokens) | Business flows or API calls |
| Flutter `ui/design/` | Design tokens (`tokens.dart`), page transitions, reusable visual components (cards, chips, dialogs, buttons, door-open button, countdown ring, skeletons, snackbars, login hero) | Business flows, API calls, role logic |
| `server/src/routes/` | HTTP handlers, middleware wiring | SQL and business rules |
| `server/src/services/` | Business rules, SQL, door policy, geofence | Express request/response objects |
| `server/src/middlewares/`, `config/`, `utils/` | Auth, rate limits, error handling, env/CORS config, helpers/validators | Route-specific business logic |
| `server/migrations/` | PostgreSQL schema migration files (001-027) | Runtime route handlers |
| `cihaz_kontrol/include/` | Header-only firmware modules (Wi-Fi, MQTT, OTA, offline log, local control, admin PIN, GM60) | Company desktop QR UI |
| `company_qr_tool/` | Windows serial/QR/firmware helper | API server endpoints |

### 4) Naming and Organization Rules

- File naming pattern: Dart files use `snake_case` such as `auth_service.dart`, `site_record.dart`; Node files use short lowercase snake_case names such as `door_service.js`, `db.js`; firmware headers use Turkish `snake_case` such as `mqtt_baglanti.h`.
- Directory organization pattern: Flutter is layer-oriented (`models`, `services`, `styles`, `ui`); backend is layered (`routes`, `services`, `middlewares`, `config`, `utils`); firmware uses PlatformIO `src`, `include`, `lib`, `test`.
- Import aliasing or path conventions: Flutter imports use package imports such as `package:site_kapi_kontrol/services/auth_api.dart`; backend uses relative ESM imports such as `./db.js`.
- Server test files live in `server/test/` and are prefixed by area (`core_`, `devices_`, `doors_`, `members_`, `sites_`, `ops_`, `fix_`).
- Flutter test folders: `test/` (unit/widget), `test/design/` (design-system matrix), `test/screens/` (per-screen overflow tests), `test/support/` (helpers such as `rebuild_probe.dart`); firmware host tests live in `cihaz_kontrol/host_test/` (`t_*.cpp`, `stub/`).

### 5) Evidence

- `lib/main.dart`, `lib/app.dart`
- `server/package.json`, `server/src/server.js`, `server/src/db.js`
- `cihaz_kontrol/platformio.ini`, `ekran_yazilimi/platformio.ini`
- `company_qr_tool/README.md`
- `.github/workflows/ci.yml`
