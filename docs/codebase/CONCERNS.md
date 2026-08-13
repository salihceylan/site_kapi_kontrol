# Codebase Concerns

## Core Sections (Required)

### 1) Top Risks (Prioritized)

| Severity | Concern | Evidence | Impact | Suggested action |
|----------|---------|----------|--------|------------------|
| high | MQTT password/default credentials are present in Flutter config defaults | `lib/config/app_config.dart` | Client builds may expose broker credentials | Move secrets to per-environment build configuration, rotate exposed credentials, and document credential lifecycle |
| high | API route/business/data logic is concentrated in one very large file | `server/src/server.js`, scan largest files | Role and data changes are harder to test and review safely | Split by route group/service/repository while preserving endpoint contracts |
| high | Minimal automated test coverage for a role/security-sensitive system | `test/widget_test.dart`, `server/package.json`, scan output | Authorization, DB mutation, and email/device flows can regress silently | Add backend route tests and Flutter service/widget tests around critical workflows |
| medium | Schema management is split between migrations and `ensureDbSchema()` startup repair | `server/migrations/`, `server/src/db.js` | Production schema drift can become hard to reason about | Decide ownership: migrations only, startup repair only, or a documented hybrid |
| medium | Generated firmware binaries are present in the repository | `cihaz_kontrol/firmware_releases/`, scan largest files | Repo size grows and binary provenance can become unclear | Confirm whether release binaries belong in git or external release storage |
| medium | No CI/CD pipeline detected | `docs/codebase/.codebase-scan.txt` | Analyze/test/build checks rely on manual execution | Add CI for Flutter analyze/test and backend syntax/test checks |

### 2) Technical Debt

| Debt item | Why it exists | Where | Risk if ignored | Suggested fix |
|-----------|---------------|-------|-----------------|---------------|
| Large Flutter home page | Many admin workflows appear consolidated | `lib/ui/pages/home_page.dart` | UI changes become coupled and harder to verify | Extract feature widgets/pages by management area |
| Large API server module | Routes, validators, SQL helpers, mapping, and startup live together | `server/src/server.js` | Cross-feature edits can create unintended regressions | Introduce route modules and service/data helpers incrementally |
| Sparse tests | Project has only one observed Flutter widget test | `test/widget_test.dart`, `server/package.json` | Critical flows are manually verified | Add smoke tests for auth, admin authorization, site approval, device assignment |
| Runtime schema mutation | Startup repairs historical schema gaps | `server/src/db.js` | App boot has side effects beyond starting the server | Capture desired schema in migrations and document migration policy |

### 3) Security Concerns

| Risk | OWASP category (if applicable) | Evidence | Current mitigation | Gap |
|------|--------------------------------|----------|--------------------|-----|
| Client-visible MQTT credentials | A02/A05 | `lib/config/app_config.dart` | MQTT ACL setup documented | Credential exposure/rotation strategy is missing |
| Broad CORS policy | A05 | `server/src/server.js` uses `app.use(cors())` | None found in code | Restrict origins per environment |
| Local session stores bearer token | A07 | `lib/services/auth_service.dart` | JWT expiry configured through env | Token storage hardening and logout/expiry handling policy is `[TODO]` |
| Missing security config/scanning | N/A | scan security section | `.env` template avoids real backend secrets | No Dependabot/security policy/SAST config found |

### 4) Performance and Scaling Concerns

| Concern | Evidence | Current symptom | Scaling risk | Suggested improvement |
|---------|----------|-----------------|--------------|-----------------------|
| Large route handlers and SQL in request path | `server/src/server.js` | No measured symptom | Harder to tune query behavior and cache carefully | Add route-level tests and extract query helpers |
| Startup schema repair runs at boot | `server/src/db.js` | Boot performs many DDL checks | Multi-instance startup or limited DB permissions may fail unexpectedly | Move routine schema evolution to migrations |
| No performance/load tests found | scan performance section | Unknown | Capacity limits are not measured | Add simple API load checks for list endpoints and device flows |

### 5) Fragile/High-Churn Areas

| Area | Why fragile | Churn signal | Safe change strategy |
|------|-------------|--------------|----------------------|
| `server/src/server.js` | Very large, owns many route groups and SQL helpers | Recent commits include auth, site approval, device, apartment changes | Change route groups narrowly and add targeted route tests |
| `lib/ui/pages/home_page.dart` | Very large UI file | Scan lists it as largest source file | Extract one workflow at a time, verify with widget tests |
| `server/src/db.js` and `server/migrations/` | Both define/repair schema | Technical notes mention owner/schema issues | Treat DB changes as migrations with explicit rollout notes |
| `cihaz_kontrol/firmware_releases/` | Binary artifacts in source tree | Scan lists firmware binaries as largest files | Confirm release artifact policy before editing |

### 6) `[ASK USER]` Questions

1. [ASK USER] Should MQTT credentials ever be embedded as Flutter defaults, or should all production credentials be supplied only through build/release secrets?
2. [ASK USER] Should PostgreSQL schema evolution be owned by migration files, by `ensureDbSchema()`, or by a documented hybrid process?
3. [ASK USER] Should `cihaz_kontrol/firmware_releases/` stay versioned in git, or move to external release storage?
4. [ASK USER] Which flows must be protected by tests first: super-user admin, site-manager approval, device assignment, MQTT door control, or QR/firmware tooling?

### 7) Evidence

- `docs/codebase/.codebase-scan.txt`
- `lib/config/app_config.dart`
- `lib/ui/pages/home_page.dart`
- `server/src/server.js`
- `server/src/db.js`
- `server/package.json`
- `test/widget_test.dart`
- `cihaz_kontrol/firmware_releases/`
