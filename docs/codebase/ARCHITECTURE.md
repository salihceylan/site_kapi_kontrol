# Architecture

## Core Sections (Required)

### 1) Architectural Style

- Primary style: multi-component repository with a layer-oriented Flutter client, a single-file Express API, PostgreSQL schema/migration layer, PlatformIO firmware, and a Python Windows helper.
- Why this classification: Flutter source is split into `models`, `services`, `styles`, and `ui`; API routing, validation, data access, and domain helpers are colocated in `server/src/server.js`; DB bootstrap is in `server/src/db.js`; firmware and QR tool are separate top-level components.
- Primary constraints: role-based access (`super_user`, `site_manager`, `apartment_owner`), PostgreSQL-backed state, JWT-protected API routes, MQTT door command/state topics, and ESP32 device provisioning.

### 2) System Flow

```text
Flutter UI -> AuthService/AuthApi -> Express route/middleware -> PostgreSQL/mail/MQTT metadata -> JSON response -> Flutter state/UI
```

1. `lib/main.dart` starts `MyApp`; `lib/app.dart` initializes auth and network services before showing login, home, or no-internet UI.
2. Flutter calls `AuthService`, which gates super-user actions locally and delegates HTTP transport to `AuthApi`.
3. `AuthApi` sends JSON requests to `API_BASE_URL`, attaches bearer tokens for protected routes, retries one transport failure, and maps API errors to Turkish user messages.
4. `server/src/server.js` validates request bodies, applies `authRequired`, `requireSuperUser`, or `requireSiteManager`, and executes SQL through the shared `pool`.
5. `server/src/db.js` creates/updates PostgreSQL tables and indexes during startup; migration files also initialize schema for Docker Compose.
6. Door control state/commands use MQTT topics in Flutter (`lib/services/mqtt_door_service_io.dart`) and ESP32 firmware (`cihaz_kontrol/include/mqtt_baglanti.h`).

### 3) Layer/Module Responsibilities

| Layer or module | Owns | Must not own | Evidence |
|-----------------|------|--------------|----------|
| Flutter app shell | Service initialization and page selection | Route SQL or schema mutation | `lib/app.dart` |
| Flutter services | Auth state, REST transport, network checks, MQTT/BLE adapters | Visual layout details | `lib/services/auth_service.dart`, `lib/services/auth_api.dart`, `lib/services/mqtt_door_service_io.dart` |
| Flutter UI | Admin screens, login, QR scan, provisioning flows | Backend persistence rules | `lib/ui/pages/home_page.dart`, `lib/ui/pages/login_page.dart` |
| API server | HTTP endpoints, request validation, role checks, business mutations | Flutter widget state | `server/src/server.js` |
| DB module/migrations | PostgreSQL pool, schema bootstrap, tables/indexes/functions | HTTP response formatting | `server/src/db.js`, `server/migrations/` |
| Mailer | SMTP transport and email templates | User creation logic | `server/src/mailer.js` |
| Firmware | Wi-Fi/MQTT loop and door pulse notification | Company/admin UI | `cihaz_kontrol/src/main.cpp`, `cihaz_kontrol/include/mqtt_baglanti.h` |
| QR tool | ESP32 discovery, QR output, firmware release/upload workflow | API route authorization | `company_qr_tool/README.md`, `company_qr_tool/app.py` |

### 4) Reused Patterns

| Pattern | Where found | Why it exists |
|---------|-------------|---------------|
| ChangeNotifier service state | `AuthService`, `MqttDoorService` | Drives Flutter UI updates from auth/MQTT state |
| Mapper functions | `mapUserRow`, `mapSiteRow`, `mapDeviceRow`, `mapDoorRow` in `server/src/server.js` | Normalizes PostgreSQL rows into API JSON |
| Validation helpers before mutation | `validateCreateInput`, `validateStructuredSiteInput`, related helpers | Keeps request validation close to route handlers |
| Role middleware | `authRequired`, `requireSuperUser`, `requireSiteManager` | Protects admin/manager routes |
| Compile-time Flutter config | `String.fromEnvironment` and `int.fromEnvironment` | Allows deployment-specific API/MQTT values |
| Startup schema repair | `ensureDbSchema()` | Adds missing tables/columns/indexes at API boot |

### 5) Known Architectural Risks

- `server/src/server.js` is very large and mixes routing, validation, business logic, and SQL access, which increases change risk.
- `lib/ui/pages/home_page.dart` is the largest scanned source file and likely owns several admin workflows in one page.
- Runtime schema repair in `ensureDbSchema()` overlaps with migrations; intent and ownership between migrations and startup repair needs a team decision.
- MQTT credentials have defaults in Flutter config and firmware headers; this is operationally convenient but security-sensitive.

### 6) Evidence

- `lib/main.dart`
- `lib/app.dart`
- `lib/services/auth_service.dart`
- `lib/services/auth_api.dart`
- `lib/services/mqtt_door_service_io.dart`
- `server/src/server.js`
- `server/src/db.js`
- `server/src/mailer.js`
- `cihaz_kontrol/src/main.cpp`
- `cihaz_kontrol/include/mqtt_baglanti.h`
