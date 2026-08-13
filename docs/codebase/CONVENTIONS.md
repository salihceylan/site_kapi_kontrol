# Coding Conventions

## Core Sections (Required)

### 1) Naming Rules

| Item | Rule | Example | Evidence |
|------|------|---------|----------|
| Files | Dart uses `snake_case`; Node uses short lowercase module names; firmware headers use Turkish `snake_case` | `auth_api.dart`, `server.js`, `mqtt_baglanti.h` | `lib/services/auth_api.dart`, `server/src/server.js`, `cihaz_kontrol/include/mqtt_baglanti.h` |
| Functions/methods | Dart and JavaScript use lower camel case; firmware uses lower camel case/Turkish names | `listManagedUsers`, `normalizeEmail`, `wifiBaglan` | `lib/services/auth_service.dart`, `server/src/server.js`, `cihaz_kontrol/src/main.cpp` |
| Types/interfaces | Dart classes use PascalCase | `AuthService`, `UserSession`, `SiteRecord` | `lib/services/auth_service.dart`, `lib/models/user_session.dart`, `lib/models/site_record.dart` |
| Constants/env vars | Dart constants use lower camel case; environment keys use uppercase snake case | `apiBaseUrl`, `API_BASE_URL`, `JWT_SECRET` | `lib/config/app_config.dart`, `server/.env.example`, `server/src/jwt.js` |

### 2) Formatting and Linting

- Formatter: Dart formatter is implied by Flutter tooling; no repo-specific formatter config found.
- Linter: `flutter_lints` through `analysis_options.yaml`.
- Most relevant enforced rules: the default Flutter lint set from `package:flutter_lints/flutter.yaml`; custom rule overrides are commented out.
- JavaScript linter: `[TODO]` no ESLint/Prettier config found in the scanned root or `server/package.json`.
- Run commands: `flutter analyze`; backend syntax check is documented as `node --check src/server.js`.

### 3) Import and Module Conventions

- Import grouping/order: Dart files group SDK imports before package imports in observed service files; JavaScript imports packages before local modules.
- Alias vs relative import policy: Dart uses `package:site_kapi_kontrol/...`; Node uses relative ESM imports.
- Public exports/barrel policy: `lib/main.dart` re-exports `app.dart`; no broad barrel-export convention found elsewhere.

### 4) Error and Logging Conventions

- Error strategy by layer: Flutter converts API failures into Turkish user-facing strings via `ApiException`; API routes return JSON `{ error: ... }` with HTTP status codes; firmware status is published through MQTT events/state.
- Logging style and required context fields: API startup logs to console; no structured logging format found.
- Sensitive-data redaction rules: `.env` is documented as not committed, but concrete redaction/secret scanning policy is `[TODO]`.

### 5) Testing Conventions

- Test file naming/location rule: Flutter tests live in `test/` and use `_test.dart`.
- Mocking strategy norm: current test uses `SharedPreferences.setMockInitialValues`; no broader mocking convention found.
- Coverage expectation: `[TODO]` no coverage threshold or CI coverage config found.

### 6) Evidence

- `analysis_options.yaml`
- `pubspec.yaml`
- `lib/config/app_config.dart`
- `lib/services/auth_service.dart`
- `lib/services/auth_api.dart`
- `server/package.json`
- `server/src/server.js`
- `test/widget_test.dart`
