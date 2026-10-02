# Testing Patterns

## Core Sections (Required)

### 1) Test Stack and Commands

- Flutter tests: `flutter_test` (Flutter SDK); widget/unit tests live under root `test/`.
- Flutter integration tests: `integration_test` (dev dependency) under `integration_test/` (desktop/emulator menu walkers per role plus the frame-time harness `perf_frames_test.dart` with `test_driver/perf_driver.dart`). They are NOT part of `flutter test` or CI and were not run in the final verification: the owner runs them (the end-to-end tour "Faz 4" was cancelled, see `BEKLEYEN_ISLER.md`).
- Assertion/mocking tools: Flutter `expect`/finders and `SharedPreferences.setMockInitialValues`.
- Backend test framework: Node.js built-in test runner (`node --test`, script `npm test` in `server/package.json`); most tests use fakes/stubs and do not need a database. Some SQL paths were additionally verified against a real PostgreSQL inside a rolled-back transaction during development.
- Backend lint: ESLint (`npm run lint` -> `eslint src`, `npm run lint:all` -> `eslint .`).
- Firmware: host tests in `cihaz_kontrol/host_test/` (719 checks: local control v2 core, UDP/HTTP, admin PIN, GM60, MQTT/OTA for WROOM and C3; real firmware headers + stubs, MSVC, not in CI); PlatformIO builds; behavior on hardware is checked by the field steps in `SAHA_KONTROL_LISTESI.md`.
- CI: `.github/workflows/ci.yml` (server lint + test, Flutter analyze + test, gitleaks secret scan; it has no firmware build and no deploy step) and `.github/workflows/ios-simulator.yml`.
- Commands:

```bash
# Flutter
flutter analyze
flutter test            # 2357 tests (last full run: all passed)

# Backend (Node >= 20.19)
cd server
npm ci
npm test            # node --test (tum server/test/*.test.js)
npm run lint
node scripts/migrate.js --status   # migration durumu (salt okunur)

# Firmware (PlatformIO)
cd cihaz_kontrol
python host_test/run_all.py       # ana makine testleri (Windows + MSVC), 719 dogrulama
pio run -e lolin_c3_mini           # ESP32-C3
pio run -e esp32_relay_wroom       # ESP32-WROOM
cd ../ekran_yazilimi
pio run -e esp32c3_display         # ekran firmware
```

### 2) Test Layout

- Flutter: root `test/`, files end with `_test.dart` (for example `auth_service_session_test.dart`, `door_widget_service_test.dart`, `fix_fx2_widgets_test.dart`, `local_door_service_v2_test.dart`). `test/design/` covers the design system (contrast >= 4.5:1, overflow matrix 320/360/412/820 x 1.0/1.5/2.0 x light/dark, reduce-motion, semantics); `test/screens/` runs every screen/dialog at 320x640 x 2.0 and 360x640 x 1.5 for overflow (AGENTS.md rule 6); `test/support/rebuild_probe.dart` counts widget rebuilds for performance regression tests (`home_polling_test`, `clock_rebuild_scope_test`, ...).
- Backend: `server/test/*.test.js`; file name prefix groups the area (`core_*` auth/middleware/mailer/startup, `devices_*` device and firmware, `doors_*` door policy/QR/geofence/MQTT, `members_*` membership, `sites_*` sites and guest passes, `ops_*` migrations/CI guards, `fix_*` contract-audit regression tests).
- Setup files and where they run: no shared global setup; each test file builds its own fakes.

### 3) Test Scope Matrix

| Scope | Covered? | Typical target | Notes |
|-------|----------|----------------|-------|
| Unit | yes | Services, validators, policies, models, door/geofence rules | `server/test/*.test.js`, root `test/*_test.dart` |
| Widget/UI | yes | Dialogs, cards, pages, overflow checks at small sizes/large text, contrast, rebuild/paint counts, polling lifecycle | root `test/*_test.dart`, `test/design/`, `test/screens/` |
| Integration (backend) | partial | HTTP routes with stubbed services, migration runner, import smoke test | `core_*_http`, `ops_*`, `import_smoke` tests |
| E2E | harness only (not run by CI) | Menu walk per role on desktop/emulator against a local API + MQTT broker + device simulator; partially run on Windows (individual and resident walks: 0 errors, 0 overflows) before the tour was cancelled | `integration_test/` |
| Performance | harness only (not run) | Frame build/raster percentiles and jank ratio per navigation stage on a desktop profile build | `integration_test/perf_frames_test.dart`, `test_driver/perf_driver.dart`; command in `SAHA_KONTROL_LISTESI.md` section 52 |
| Backend syntax/lint | yes | `server/src/**` | `npm run lint`, CI |
| Firmware | host tests + builds | C3, WROOM and display targets | `cihaz_kontrol/host_test/` (719 checks), PlatformIO builds; behavior verified in the field checklist |

### 4) Mocking and Isolation Strategy

- Flutter: shared preferences are mocked; `MyApp(networkCheckEnabled: false)` avoids the network health check in widget tests.
- Backend: services/DB access are injected or stubbed (for example `deviceLookup`, `publicIpUpdater` in `firmware_routes`); tests do not require a live database or MQTT broker.
- Rate limiters and the login lock-out are in-memory per process, so tests that exercise them create fresh instances.

### 5) Coverage and Quality Signals

- Coverage tool + threshold: none configured; tests are expected to pass in full (`npm test`, `flutter test`).
- Known gaps: firmware behavior (hardware), BLE provisioning, speech-to-text and Android widget on real devices, SMTP delivery against a real mail server, PostgreSQL-specific SQL paths (only partly verified against a real database).

### 6) Evidence

- `pubspec.yaml`, `analysis_options.yaml`, `test/`, `integration_test/`, `test_driver/`
- `cihaz_kontrol/host_test/README.md`
- `server/package.json`, `server/test/`
- `.github/workflows/ci.yml`
- `SAHA_KONTROL_LISTESI.md` (field verification steps)
- `PROJE_TEKNIK_NOTLAR.md`
