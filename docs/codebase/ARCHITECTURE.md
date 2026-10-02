# Architecture

## Core Sections (Required)

### 1) Architectural Style

- Primary style: multi-component repository with a layer-oriented Flutter client, a modular Express API (routes -> services -> PostgreSQL), an MQTT bridge, PlatformIO firmware for two door-controller boards plus a display board, and a Python Windows helper.
- Why this classification: Flutter source is split into `models`, `services`, `styles`, `ui`; the API is split into `routes/` (HTTP), `services/` (business rules and SQL), `middlewares/`, `config/` and `utils/`; `server/src/server.js` only wires them together; firmware and QR tool are separate top-level components.
- Primary constraints: role-based access (`super_user`, `site_manager`, `apartment_owner`, `individual`), one central door-open policy (`server/src/services/door_access_policy.js`), PostgreSQL-backed state, JWT-protected API routes, MQTT over TLS for device commands/events, local-network (UDP) door control protected by challenge-bound HMAC-SHA256 signatures keyed by the per-device token (protocol v2, `docs/YEREL_KONTROL_V2.md`), and ESP32 device provisioning (BLE) and OTA.

### 2) System Flow

```text
Flutter UI -> AuthService/AuthApi -> Express route/middleware -> service -> PostgreSQL / mail / MQTT bridge -> JSON response -> Flutter state/UI
Device (ESP32) <-> MQTT broker (TLS) <-> server/src/mqtt_bridge.js -> PostgreSQL (state, door logs)
```

1. `lib/main.dart` starts `MyApp`; `lib/app.dart` initializes auth and network services before showing login, home, or no-internet UI.
2. Flutter calls `AuthService`, which holds the session (token, role refreshed from `GET /me`) and delegates HTTP transport to `AuthApi`.
3. `AuthApi` sends JSON requests to `API_BASE_URL`, attaches bearer tokens, retries only idempotent GET requests, and maps API error codes to Turkish user messages. 401/403 responses end the session centrally.
4. `server/src/server.js` mounts security headers, CORS allowlist, request logging, JSON parsing, the routers and the global error handler; routers apply `authRequired`, role checks and rate limiters, then call services.
5. Door opening (cloud, local, QR, widget, voice) goes through `assertDoorOpenAllowed` (site policy, membership, geofence); the server then publishes an MQTT `pulse` command (`device/<UID>/cmd`) with `requested_at` and `request_id`.
6. Devices publish state/events/offline logs (`device/<UID>/{state,event,availability,logs,qr_verify,screen_qr}`); the bridge stores them and acknowledges log batches (`logs_ack`).
7. Schema is owned by `server/migrations/` (+ `scripts/migrate.js`); `server/src/db.js` `ensureDbSchema()` only adds idempotent, additive repairs at boot.

### 3) Layer/Module Responsibilities

| Layer or module | Owns | Must not own | Evidence |
|-----------------|------|--------------|----------|
| Flutter app shell | Service initialization, deep links, quick actions, page selection | Route SQL or schema mutation | `lib/app.dart`, `lib/services/deep_link_service.dart` |
| Flutter services | Auth state, REST transport, network checks, local (UDP, v2 signed) door control, widget/voice integration, geofence location, BLE provisioning, adaptive polling (`adaptive_poller.dart`) and isolate offloading of heavy work (`background_work.dart`: PDF, JSON >= 64 KB) | Visual layout details | `lib/services/auth_service.dart`, `lib/services/auth_api.dart`, `lib/services/local_door_service.dart`, `lib/services/adaptive_poller.dart`, `lib/services/background_work.dart` |
| Flutter UI | Role-based screens, dialogs, QR scan, provisioning flows | Backend persistence rules | `lib/ui/pages/home_page.dart`, `lib/ui/views/`, `lib/ui/dialogs/` |
| Flutter design system ("Cilali Safir") | Design tokens (`AppPalette` theme extension, `AppTone`, `AppMotion`, `AppSpace`, `AppRadius`), page transitions, shared components (`AppCard`, `StatusChip`, `AppDialog`, `DoorOpenButton`, `CountdownRing`, `SkeletonBox`, `EmptyState`, `AppSnack`, `PrimaryActionButton`) | Screen business logic, API calls | `lib/ui/design/`, `lib/ui/widgets/list_parts.dart`, `lib/styles/` |
| API routes | HTTP endpoints, input parsing, auth/rate-limit middleware | SQL | `server/src/routes/` |
| API services | Business rules and SQL (doors, sites, membership, devices, QR, geofence, maintenance) | HTTP response formatting | `server/src/services/` |
| MQTT bridge | Device topics, pulse commands, offline-log ingestion, hardware-type self-healing | HTTP routing | `server/src/mqtt_bridge.js`, `server/src/mqtt_acl_sync.js` |
| DB module/migrations | PostgreSQL pool (timeouts), additive schema repair, migration files | HTTP response formatting | `server/src/db.js`, `server/migrations/` |
| Mailer | SMTP transport and email templates | User creation logic | `server/src/mailer.js` |
| Door-controller firmware | Wi-Fi/BLE provisioning, MQTT (TLS), relay pulse, local control, offline log, OTA with rollback, GM60 QR scanner, admin PIN | Company/admin UI | `cihaz_kontrol/src/main.cpp`, `cihaz_kontrol/include/` |
| Display firmware | Touch screen (status, rotating QR, admin menu) over UART to the controller | Door decisions (the controller re-verifies the admin PIN) | `ekran_yazilimi/src/ScreenManager.cpp` |
| QR tool | ESP32 discovery, QR output, firmware release/upload workflow | API route authorization | `company_qr_tool/app.py` |

### 4) Reused Patterns

| Pattern | Where found | Why it exists |
|---------|-------------|---------------|
| ChangeNotifier service state | `AuthService`, `MqttDoorService` | Drives Flutter UI updates from auth/MQTT state |
| Row mappers | `mapUserRow`, `mapSiteRow`, `mapDoorRow` in `server/src/utils/helpers.js` | Normalizes PostgreSQL rows into API JSON |
| Central policy functions | `assertDoorOpenAllowed`, `geofence_service.js` | One rule set for every door-open channel |
| Role/auth middleware | `authRequired`, `requireSuperUser`, `requireSiteManager`, `company_auth.js` | Protects admin/manager/company routes |
| Rate limiters + login lock-out | `server/src/middlewares/rate_limiters.js`, `login_throttle.js` | Brute-force protection (in-memory, per process) |
| Global error handler | `server/src/middlewares/error_handler.js` | Returns `{error, errorId}`; details only in server logs |
| Compile-time Flutter config | `String.fromEnvironment` (`API_BASE_URL`) | Deployment-specific API address |
| Theme-first design tokens | `lib/ui/design/tokens.dart`, `lib/styles/app_theme.dart` | One palette/tone source with >= 4.5:1 text contrast in light and dark; screens read `context.palette` / `AppTone` instead of raw colors |
| Adaptive polling | `AdaptivePoller` (`lib/services/adaptive_poller.dart`) in `HomePage` (3 s), `IndividualHomeView` (15 s), QR modal (0.8 s, cap 5 s) | No requests while backgrounded/covered/not visible, exponential back-off on errors (cap 30 s), never overlapping |
| Isolate offloading | `BackgroundWork` (`lib/services/background_work.dart`), `PdfFontSet` | PDF generation and JSON bodies >= 64 KB are processed off the UI isolate |
| Additive startup repair | `ensureDbSchema()` | Idempotent column/index repairs; fails clearly on an empty database |

### 5) Known Architectural Risks

- `lib/ui/pages/home_page.dart` (~4,400 lines) and `lib/services/auth_service.dart` / `auth_api.dart` (~2,800 / ~2,500 lines) own many workflows; extract by feature when touching them (`individual_home_view.dart` was already split into `individual_door_card.dart` / `individual_apartment_card.dart`).
- Rate limiters and login lock-out are in-memory (a PM2 cluster would need a shared store).
- Local door control (UDP, protocol v2) is unencrypted on the LAN, but the token never leaves the devices and every command is signed over a single-use challenge (rotates every 10 s); a LAN attacker can only relay a request within its own challenge and the 3 s duplicate window (`docs/YEREL_KONTROL_V2.md`).
- Firmware has been verified by builds, host tests (`cihaz_kontrol/host_test/`, 719 checks) and a device simulator only, not on hardware (see `SAHA_KONTROL_LISTESI.md` sections 42-52).

### 6) Evidence

- `lib/main.dart`, `lib/app.dart`
- `lib/services/auth_service.dart`, `lib/services/auth_api.dart`, `lib/services/local_door_service.dart`
- `lib/ui/design/`, `lib/services/adaptive_poller.dart`, `lib/services/background_work.dart`
- `server/src/server.js`, `server/src/routes/`, `server/src/services/`
- `server/src/mqtt_bridge.js`, `server/src/db.js`
- `cihaz_kontrol/src/main.cpp`, `cihaz_kontrol/include/`
- `ekran_yazilimi/src/ScreenManager.cpp`
