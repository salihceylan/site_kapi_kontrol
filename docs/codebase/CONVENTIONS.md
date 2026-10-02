# Coding Conventions

## Core Sections (Required)

### 1) Naming Rules

| Item | Rule | Example | Evidence |
|------|------|---------|----------|
| Files | Dart uses `snake_case`; Node uses short lowercase `snake_case` module names; firmware headers use Turkish `snake_case` | `auth_api.dart`, `door_service.js`, `mqtt_baglanti.h` | `lib/services/auth_api.dart`, `server/src/services/door_service.js`, `cihaz_kontrol/include/mqtt_baglanti.h` |
| Functions/methods | Dart and JavaScript use lower camel case; firmware uses lower camel case/Turkish names | `listManagedUsers`, `normalizeEmail`, `wifiBaglan` | `lib/services/auth_service.dart`, `server/src/utils/helpers.js`, `cihaz_kontrol/src/main.cpp` |
| Types/interfaces | Dart classes use PascalCase | `AuthService`, `UserSession`, `SiteRecord` | `lib/services/auth_service.dart`, `lib/models/user_session.dart`, `lib/models/site_record.dart` |
| Constants/env vars | Dart constants use lower camel case; environment keys use uppercase snake case | `apiBaseUrl`, `API_BASE_URL`, `JWT_SECRET` | `lib/config/app_config.dart`, `server/.env.example`, `server/src/jwt.js` |

### 2) Formatting and Linting

- Formatter: Dart formatter is implied by Flutter tooling; no repo-specific formatter config found.
- Linter: `flutter_lints` through `analysis_options.yaml`.
- Most relevant enforced rules: the default Flutter lint set from `package:flutter_lints/flutter.yaml`; custom rule overrides are commented out.
- JavaScript linter: ESLint (`server/eslint.config.js`; `no-undef` is an error). No Prettier config.
- Run commands: `flutter analyze`; `cd server && npm run lint` (CI runs both).

### 3) Import and Module Conventions

- Import grouping/order: Dart files group SDK imports before package imports in observed service files; JavaScript imports packages before local modules.
- Alias vs relative import policy: Dart uses `package:site_kapi_kontrol/...`; Node uses relative ESM imports.
- Public exports/barrel policy: `lib/main.dart` re-exports `app.dart`; no broad barrel-export convention found elsewhere.

### 3b) UI Conventions (design system)

- Colors, spacing and motion come from `lib/ui/design/tokens.dart` (`context.palette`, `AppTone`, `AppSpace`, `AppRadius`, `AppMotion`); new UI does not use raw `Color(0xFF...)`, `Colors.red/green/grey`, `isDark ? a : b` triples or literal `fontSize` values. Text must keep >= 4.5:1 contrast in both themes (`test/design/contrast_test.dart` is the referee).
- Animations take their duration from `AppMotion.of(context)` (zero when the system asks to reduce motion); `AnimatedSize`/`AnimatedCrossFade` use 1 ms instead of zero (Flutter asserts on zero). No endless animations in steady state (status-chip pulse stops after 3 cycles; skeleton shimmer only while loading) so `pumpAndSettle` and the menu walker terminate.
- Touch targets are >= 44 dp; UI must not overflow at 320x640 with text scale 2.0 (AGENTS.md rule 6) - the app clamps text scaling to 2.0 in `lib/app.dart`; existing Material widget types (`ElevatedButton`, `AlertDialog`, `ListTile`, `CircularProgressIndicator`) and user-visible texts stay unchanged because test finders and the walkers depend on them.
- Network polling goes through `AdaptivePoller`; work that can exceed ~16 ms (PDF building, large JSON) goes through `BackgroundWork`.

### 4) Error and Logging Conventions

- Error strategy by layer: Flutter converts API failures into Turkish user-facing strings via `ApiException` and `messageForErrorCode`; API routes return JSON `{ error, code? }` and the global handler adds an `errorId` for unexpected errors (details only in server logs); firmware status is published through MQTT events/state.
- Logging style and required context fields: console logging with a request logger that masks tokens in URLs; no structured (JSON) format.
- Sensitive-data redaction rules: `.env` is never committed; tokens in URLs are masked in logs; secrets are never printed by firmware (PIN, QR token, local token, MQTT password); CI runs a gitleaks secret scan.

### 5) Testing Conventions

- Test file naming/location rule: Flutter tests live in `test/` and use `_test.dart`; backend tests live in `server/test/` and use `<area>_*.test.js` (`node --test`).
- Mocking strategy norm: Flutter uses `SharedPreferences.setMockInitialValues` and fake services; backend injects fakes/stubs for DB and MQTT.
- Coverage expectation: no coverage threshold; all tests must pass (`flutter test`, `npm test`, `python cihaz_kontrol/host_test/run_all.py` after firmware header changes).
- Layout tests use `pumpAt` from `test/design/harness.dart` (size x text scale x theme x reduce-motion matrix); performance regressions are guarded by rebuild/paint/request counters (`test/support/rebuild_probe.dart`) instead of wall-clock thresholds.

### 6) Evidence

- `analysis_options.yaml`
- `pubspec.yaml`
- `lib/config/app_config.dart`
- `lib/services/auth_service.dart`
- `lib/services/auth_api.dart`
- `server/package.json`
- `server/eslint.config.js`
- `server/src/server.js`
- `test/`, `server/test/`
