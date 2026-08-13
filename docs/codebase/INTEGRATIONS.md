# External Integrations

## Core Sections (Required)

### 1) Integration Inventory

| System | Type (API/DB/Queue/etc) | Purpose | Auth model | Criticality | Evidence |
|--------|--------------------------|---------|------------|-------------|----------|
| PostgreSQL | Database | Users, sites, devices, blocks, apartments, doors, manager-site mappings | DB username/password env vars | high | `docker-compose.yml`, `server/src/db.js`, `server/migrations/` |
| Express API | HTTP API | Backend for Flutter clients | JWT bearer tokens for protected routes | high | `server/src/server.js`, `server/src/jwt.js` |
| SMTP server | Email | Site-manager verification and apartment credential emails | SMTP username/password env vars | high | `server/.env.example`, `server/src/mailer.js` |
| MQTT broker `mqtt.gudeteknoloji.com.tr` | MQTT | Door command, state, event, availability messaging | Username/password, ACL documented | high | `lib/config/app_config.dart`, `lib/services/mqtt_door_service_io.dart`, `MQTT_kurulum.txt`, `cihaz_kontrol/include/mqtt_baglanti.h` |
| Nginx | Reverse proxy | Production HTTPS proxy to Node API | OS/server config, Let's Encrypt | high | `sunucu_kurulum.txt`, `PROJE_TEKNIK_NOTLAR.md` |
| Let's Encrypt/Certbot | Certificate authority/tooling | SSL certificates for API and MQTT domains | ACME/certbot flow | high | `sunucu_kurulum.txt`, `MQTT_kurulum.txt` |
| ESP32 serial/USB | Local hardware integration | Device UID read and firmware upload | Local USB access | medium | `company_qr_tool/README.md`, `company_qr_tool/requirements.txt` |

### 2) Data Stores

| Store | Role | Access layer | Key risk | Evidence |
|-------|------|--------------|----------|----------|
| PostgreSQL `site_kapi_kontrol` | Primary relational store | `server/src/db.js` pool and SQL in `server/src/server.js` | Schema is maintained by both migrations and startup repair | `docker-compose.yml`, `server/src/db.js`, `server/migrations/` |
| Flutter shared preferences | Local session storage | `AuthService._persist()` | JWT lifetime and local device access risks depend on platform storage behavior | `lib/services/auth_service.dart` |
| QR output/firmware release folders | Local files for QR PNGs and firmware artifacts | `company_qr_tool` workflow | Generated artifacts may be committed unless intentionally managed | `company_qr_tool/README.md`, `cihaz_kontrol/firmware_releases/` |

### 3) Secrets and Credentials Handling

- Credential sources: backend `.env`; Flutter `--dart-define`; MQTT credentials in compile-time config/defaults; firmware header constants.
- Hardcoding checks: `lib/config/app_config.dart` contains default MQTT username/password and production API/MQTT hosts; `cihaz_kontrol/include/mqtt_baglanti.h` contains broker constants.
- Rotation or lifecycle notes: MQTT ACL setup is documented; credential rotation process is `[TODO]`.

### 4) Reliability and Failure Behavior

- Retry/backoff behavior: `AuthApi` retries one timeout or `http.ClientException` after 350 ms.
- Timeout policy: Flutter HTTP requests use a 15-second timeout.
- Circuit-breaker or fallback behavior: `NetworkService` health-checks the API; MQTT client enables auto-reconnect and resubscribe.
- Backend DB startup: API calls `ensureDbSchema()` before listening.

### 5) Observability for Integrations

- Logging around external calls: API logs startup/fatal startup failure only in observed code; MQTT client logging is disabled in Flutter.
- Metrics/tracing coverage: none found.
- Missing visibility gaps: no CI, APM, structured API logging, SMTP delivery logging, or MQTT health metrics were found in repo files.

### 6) Evidence

- `server/.env.example`
- `server/src/db.js`
- `server/src/mailer.js`
- `server/src/jwt.js`
- `lib/config/app_config.dart`
- `lib/services/auth_api.dart`
- `lib/services/mqtt_door_service_io.dart`
- `docker-compose.yml`
- `MQTT_kurulum.txt`
- `sunucu_kurulum.txt`
