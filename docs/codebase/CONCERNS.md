# Codebase Concerns

## Core Sections (Required)

### 1) Top Risks (Prioritized)

| Severity | Concern | Evidence | Impact | Suggested action |
|----------|---------|----------|--------|------------------|
| high | Production credentials were exposed in the past (repository history, firmware binaries, chat) | git history, `cihaz_kontrol/firmware_releases/` | Anyone with the old values could reach SSH/MQTT/DB/SMTP | Rotate all production credentials (VPS SSH, MQTT, DB, SMTP, JWT secret); consider history cleanup (`git filter-repo`) - a user decision |
| high | Firmware has never run on hardware (builds + device simulator only) | `SAHA_KONTROL_LISTESI.md` sections 42-52 | Field behavior (relay, OTA rollback, local control v2, admin PIN, display) is unverified | Run the field checklist on one C3 and one WROOM board before rollout |
| medium | Production `.env` is weaker than the code expects (short `JWT_SECRET`, long `JWT_EXPIRES_IN`, optional `NODE_ENV`) | `server/.env.example`, `BEKLEYEN_ISLER.md` | Weak token secret/lifetime | Update production values in a maintenance window (all sessions are invalidated when the secret changes) |
| medium | Rate limiters and login lock-out are in-memory | `server/src/middlewares/rate_limiters.js`, `login_throttle.js` | Limits reset on restart and are per process | Move to a shared store if PM2 cluster mode is ever used |
| low | Local door control (UDP v2) is unencrypted on the LAN | `cihaz_kontrol/include/yerel_kapi_kontrol.h`, `docs/YEREL_KONTROL_V2.md` | Request/response content is readable, but the token never leaves the devices and commands are bound to a single-use challenge | Encrypt only if the threat model requires it; app and firmware must be updated together (v1 clients no longer work) |
| medium | Generated firmware binaries are tracked in git (~180 MB) | `cihaz_kontrol/firmware_releases/` | Repository size, unclear provenance | Move release binaries to external storage |
| low | Very large Flutter files | `lib/ui/pages/home_page.dart` (~4,400 lines), `lib/services/auth_service.dart`, `lib/services/auth_api.dart` | Harder reviews and rebuild cost | Extract by feature when editing |
| low | UI changes were verified by analysis, unit/widget tests and builds only (no device/emulator walk-through) | `SAHA_KONTROL_LISTESI.md` section 52, `BEKLEYEN_ISLER.md` Faz 4/5 | Visual regressions (dark theme, small screens, large text) may only show on devices | The owner runs section 52 on a phone and a desktop window; frame-time harness: `integration_test/perf_frames_test.dart` |

Resolved since the previous scan (kept here for traceability): monolithic `server.js` (now layered), wildcard CORS (allowlist), missing CI (`.github/workflows/ci.yml`), no backend tests (`server/test/`), hard-coded MQTT credentials in Flutter defaults (removed), insecure MQTT TLS in firmware (CA verification on), UID-only local control (token required; since v2 the token is never sent and HTTP open was removed), unauthenticated company routes (`X-Company-Key`/super user), unbounded app polling (`AdaptivePoller`), heavy work on the UI isolate (PDF/JSON offloaded), low text contrast and five divergent "open door" buttons (design system, `DoorOpenButton`).

### 2) Technical Debt

| Debt item | Why it exists | Where | Risk if ignored | Suggested fix |
|-----------|---------------|-------|-----------------|---------------|
| Large Flutter home page | Many admin workflows consolidated | `lib/ui/pages/home_page.dart` | UI changes become coupled | Extract feature widgets/pages by management area |
| Large client service files | Auth, session, door, site and user calls in one class | `lib/services/auth_service.dart`, `auth_api.dart` | Cross-feature regressions | Split by domain behind the same public API |
| Schema ownership | Migrations plus additive startup repair | `server/migrations/`, `server/src/db.js` | Drift between environments | Keep new schema changes in migrations; startup repair stays additive |
| Duplicate local-open logs | App notification and device offline log can both record a local open | `server/src/services/door_log_service.js` | Duplicate rows in door history | Time-window de-duplication (deferred) |

### 3) Security Concerns

| Risk | OWASP category (if applicable) | Evidence | Current mitigation | Gap |
|------|--------------------------------|----------|--------------------|-----|
| Bearer token lifetime and revocation | A07 | `server/src/jwt.js` | HS256 only, `pv` password-version claim revokes tokens on password change | No refresh-token/revocation list; long production `JWT_EXPIRES_IN` |
| Brute force | A07 | rate limiters, login lock-out | Per-IP/per-account limits, 5-failure lock | In-memory only |
| Local control on LAN | A02 | `yerel_kapi_kontrol.h`, `yerel_kontrol_cekirdek.h` | Challenge-bound HMAC (token never on the wire), single-use challenge rotating every 10 s, RFC1918/link-local targets only, boot-time HMAC self-test (fail-closed), token rotated on permission removal | Unencrypted transport; v1 firmware/app must not be mixed with v2 |
| Secret scanning | A05 | `.github/workflows/ci.yml` (gitleaks) | CI secret scan; secrets only in `.env` | History still contains old secrets |

### 4) Performance and Scaling Concerns

| Concern | Evidence | Current symptom | Scaling risk | Suggested improvement |
|---------|----------|-----------------|--------------|-----------------------|
| Polling in the app (door status 3 s, individual home 15 s, QR modal 0.8 s) | `lib/services/adaptive_poller.dart`, `lib/ui/pages/home_page.dart`, `lib/ui/views/individual_home_view.dart` | Fixed: stops when hidden/backgrounded, backs off on errors (cap 30 s; 5 s in the QR modal) | Still one request per active panel every 3 s | Server-side push (SSE/MQTT over WebSocket) if user counts grow |
| Deferred UI performance items | `site_residents_accordion_dialog.dart` (eager apartment tree: ~3 s for 5x60x3 in the test VM), `all_users_view.dart` / `company_devices_view.dart` (~2000 elements rebuilt per `HomePage.setState`), `AuthService.listMyDoors` (widget sync on every call), ~60 remaining `setState` in `HomePage`, daily PDF report limited to 20 pages (~500+ rows) | Not measured on devices | Large sites (300+ apartments) may feel slow | Sliver-based lazy lists, narrower `setState`, raise `maxPages` (product decision); measure with `integration_test/perf_frames_test.dart` |
| No load tests | `BEKLEYEN_ISLER.md` | Unknown | Capacity limits not measured | Soak/load test against the local harness |
| DB pool and timeouts | `server/src/db.js` | Defaults: pool 12, 30 s statement timeout | Tune via `DB_POOL_MAX`, `DB_STATEMENT_TIMEOUT_MS` | Monitor in production |

### 5) Fragile/High-Churn Areas

| Area | Why fragile | Safe change strategy |
|------|-------------|----------------------|
| `server/src/services/door_access_policy.js` and `geofence_service.js` | Every door-open channel depends on them | Change with the `doors_*` tests |
| `server/src/mqtt_bridge.js` | Device protocol contracts (pulse, qr_verify, offline logs) | Keep contracts in sync with firmware (`SAHA_KONTROL_LISTESI.md` section 51) |
| `lib/ui/pages/home_page.dart` | Very large UI file | Extract one workflow at a time, verify with widget tests and the menu walker |
| `lib/ui/design/` (tokens, palette, components) | A palette or token change restyles ~60 screens | Run `flutter test test/design test/screens` (contrast >= 4.5:1, overflow at 320x640 x 2.0, reduce-motion) before and after; keep widget types (`ElevatedButton`, `AlertDialog`, `ListTile`) stable because finders in tests and the menu walker depend on them |
| `cihaz_kontrol/include/` and `ekran_yazilimi/` | The UART protocol (`display_protocol.h`) must be identical in both projects; C3 and WROOM are separate hardware targets | Update controller and display together; never mix pins between targets |

### 6) Open Decisions

1. Rotate production credentials and decide on git history cleanup.
2. Whether `cihaz_kontrol/firmware_releases/` stays in git.
3. Production values for `JWT_EXPIRES_IN`, `NODE_ENV`, `CORS_ORIGINS`.
4. Release signing / application id (`com.example.*`) before store publication.

### 7) Evidence

- `BEKLEYEN_ISLER.md`, `SAHA_KONTROL_LISTESI.md`
- `server/src/`, `server/.env.example`
- `lib/ui/pages/home_page.dart`
- `cihaz_kontrol/include/`
