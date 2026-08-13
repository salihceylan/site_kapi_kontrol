# Testing Patterns

## Core Sections (Required)

### 1) Test Stack and Commands

- Primary test framework: Flutter `flutter_test` from the Flutter SDK.
- Assertion/mocking tools: Flutter `expect`/finders and `SharedPreferences.setMockInitialValues`.
- Backend test framework: `[TODO]` no backend test script or test dependency found in `server/package.json`.
- Firmware test framework: PlatformIO test folder exists with README, but no concrete tests found.
- Commands:

```bash
flutter test
flutter analyze

cd server
node --check src/server.js
```

### 2) Test Layout

- Test file placement pattern: Flutter tests are under root `test/`.
- Naming convention: Flutter test files use `_test.dart`.
- Setup files and where they run: no shared setup file found; current widget test initializes shared preferences inside the test body.

### 3) Test Scope Matrix

| Scope | Covered? | Typical target | Notes |
|-------|----------|----------------|-------|
| Unit | partial | `[TODO]` no focused unit tests found | Only a Flutter widget smoke test is present |
| Widget/UI | yes, minimal | Login page render | `test/widget_test.dart` checks `Sirket Girisi` and `Giris Yap` |
| Integration | no evidence | API/database/MQTT boundaries | No integration test files found |
| E2E | no evidence | Full login/admin/device flows | No E2E tooling found |
| Backend syntax | documented | `server/src/server.js` | `node --check src/server.js` is documented in technical notes |
| Firmware | no evidence | PlatformIO tests | `cihaz_kontrol/test/README` exists, no source tests found |

### 4) Mocking and Isolation Strategy

- Main mocking approach: current Flutter test mocks shared preferences.
- Isolation guarantees: current test starts `MyApp(networkCheckEnabled: false)`, avoiding the network health check.
- Common failure mode in tests: `[TODO]` no test-run history or flaky test notes found.

### 5) Coverage and Quality Signals

- Coverage tool + threshold: `[TODO]` no coverage configuration found.
- Current reported coverage: `[TODO]` not measured during this documentation pass.
- Known gaps/flaky areas: backend routes, database migrations/bootstrap, role authorization, SMTP, MQTT, BLE provisioning, QR tool, and firmware behavior have no tests found in repo.

### 6) Evidence

- `pubspec.yaml`
- `analysis_options.yaml`
- `test/widget_test.dart`
- `server/package.json`
- `PROJE_TEKNIK_NOTLAR.md`
- `docs/codebase/.codebase-scan.txt`
