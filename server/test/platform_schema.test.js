// Platform modul sistemi: migration 029 <-> db.js ayni DDL, ekleyici/idempotent sema, denetim kaydi yalnizca eklenir.
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { DEFAULT_MIGRATIONS_DIR, findUnsafeStatements, listMigrations } from '../scripts/migrate.js';

const here = path.dirname(fileURLToPath(import.meta.url));
const srcRoot = path.join(here, '..', 'src');
const read = (relative) => readFileSync(path.join(srcRoot, relative), 'utf8').replace(/\r\n/g, '\n');
const MIGRATION = readFileSync(path.join(DEFAULT_MIGRATIONS_DIR, '029_platform_modules.sql'), 'utf8').replace(/\r\n/g, '\n');
const MIGRATION_030 = readFileSync(path.join(DEFAULT_MIGRATIONS_DIR, '030_module_requests.sql'), 'utf8').replace(/\r\n/g, '\n');
const DB_SOURCE = read('db.js');

// SQL yorumlarini at, bosluklari tek bosluga indir.
function normalizeSql(text) {
  return text
    .replace(/\/\*[\s\S]*?\*\//g, ' ')
    .replace(/--.*$/gm, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

function listSourceFiles(dir) {
  const out = [];
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) out.push(...listSourceFiles(full));
    else if (/\.(js|mjs)$/.test(entry.name)) out.push(full);
  }
  return out;
}

describe('platform sema: migration 029', () => {
  it('029 var, 29. siradadir (numaralar ardisik) ve calistirici icin guvenli (ust duzey BEGIN/COMMIT yok)', () => {
    // "son migration" iddiasi YOK: sonraki migration'lar bu testi kirmamali.
    const list = listMigrations(DEFAULT_MIGRATIONS_DIR);
    assert.ok(list.length >= 29, `en az 29 migration beklenir: ${list.length}`);
    const entry = list.find((m) => m.number === 29);
    assert.ok(entry, '029 numarali migration yok');
    assert.equal(entry.file, '029_platform_modules.sql');
    assert.equal(entry.version, '029_platform_modules');
    assert.equal(list[28], entry, 'sirali listede 29. eleman');
    assert.deepEqual(findUnsafeStatements(MIGRATION), []);
  });

  it('basliginda db.js ile ayni DDL oldugu ve ekleyici/idempotent oldugu belirtilir', () => {
    const header = MIGRATION.split('\n').slice(0, 8).join('\n');
    assert.match(header, /db\.js/);
    assert.match(header, /ekleyici/i);
    assert.match(header, /idempotent/i);
  });

  it('db.js ensureDbSchema ayni DDL\'i icerir (yorumlar ve bosluklar disinda birebir)', () => {
    const migrationSql = normalizeSql(MIGRATION);
    assert.ok(migrationSql.length > 800, 'migration DDL\'i beklenenden kisa');
    assert.ok(
      normalizeSql(DB_SOURCE).includes(migrationSql),
      'migrations/029_platform_modules.sql ile db.js ayni DDL degil',
    );
  });

  it('beklenen nesneler: sites.management_type + CHECK, site_modules, audit_log, indeksler, rol CHECK genislemesi', () => {
    const sql = normalizeSql(MIGRATION);
    assert.match(sql, /ALTER TABLE sites ADD COLUMN IF NOT EXISTS management_type TEXT NOT NULL DEFAULT 'apartment_site'/);
    assert.match(
      sql,
      /CHECK \(management_type IN \('apartment_site', 'residence', 'business_center', 'cooperative', 'shopping_mall'\)\)/,
    );
    assert.match(
      sql,
      /CREATE TABLE IF NOT EXISTS site_modules \( site_code BIGINT NOT NULL REFERENCES sites\(site_code\) ON DELETE CASCADE, module_code TEXT NOT NULL, enabled BOOLEAN NOT NULL, updated_by INTEGER REFERENCES users\(user_code\) ON DELETE SET NULL, updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW\(\), PRIMARY KEY \(site_code, module_code\) \)/,
    );
    assert.match(sql, /CREATE TABLE IF NOT EXISTS audit_log \( id BIGSERIAL PRIMARY KEY,/);
    assert.match(sql, /actor_user_code INTEGER REFERENCES users\(user_code\) ON DELETE SET NULL/);
    assert.match(sql, /action TEXT NOT NULL/);
    assert.match(sql, /details JSONB NOT NULL DEFAULT '\{\}'::jsonb/);
    assert.match(sql, /CREATE INDEX IF NOT EXISTS idx_audit_log_site_id ON audit_log \(site_code, id DESC\)/);
    assert.match(sql, /CREATE INDEX IF NOT EXISTS idx_audit_log_id ON audit_log \(id DESC\)/);
    assert.match(sql, /CHECK \(role IN \('SITE_OWNER', 'SITE_ADMIN', 'RESIDENT', 'BOARD_MEMBER', 'STAFF'\)\)/);
  });

  it('audit_log.site_code icin FOREIGN KEY YOK (site silinse de kayit kalir)', () => {
    const sql = normalizeSql(MIGRATION);
    const table = /CREATE TABLE IF NOT EXISTS audit_log \(([\s\S]*?)\);/.exec(sql);
    assert.ok(table, 'audit_log tablosu bulunamadi');
    assert.match(table[1], /site_code BIGINT,/);
    assert.equal(/site_code[^,]*REFERENCES/i.test(table[1]), false);
  });

  it('ekleyici: tablo/veri silmez, veri yazmaz; her CREATE/ADD COLUMN IF NOT EXISTS ile', () => {
    const sql = normalizeSql(MIGRATION);
    assert.equal(/DROP\s+TABLE|DROP\s+COLUMN|TRUNCATE|DELETE\s+FROM|\bUPDATE\s+\w+\s+SET|\bINSERT\s+INTO/i.test(sql), false);
    assert.deepEqual(sql.match(/CREATE\s+(UNIQUE\s+)?(TABLE|INDEX)\s+(?!IF NOT EXISTS)/gi) || [], []);
    assert.deepEqual(sql.match(/ADD\s+COLUMN\s+(?!IF NOT EXISTS)/gi) || [], []);
    // tek DROP CONSTRAINT: yalnizca site_memberships rol kisiti (dinamik ad), koşullu DO blogunda
    const drops = sql.match(/DROP CONSTRAINT [^;]*/g) || [];
    assert.equal(drops.length, 1);
    assert.match(drops[0], /DROP CONSTRAINT %I/);
    assert.match(sql, /EXECUTE format\('ALTER TABLE site_memberships DROP CONSTRAINT %I', old_check\.conname\)/);
  });

  it('eski rol kisiti yalnizca YENI rolleri icermiyorsa kaldirilir; mevcut guncel kisit yeniden olusturulmaz', () => {
    const sql = normalizeSql(MIGRATION);
    assert.match(sql, /pg_get_constraintdef\(c\.oid\) LIKE '%SITE_OWNER%' AND pg_get_constraintdef\(c\.oid\) NOT LIKE '%BOARD_MEMBER%'/);
    assert.match(
      sql,
      /IF NOT EXISTS \( SELECT 1 FROM pg_constraint WHERE conname = 'chk_site_membership_role' AND conrelid = 'site_memberships'::regclass \) THEN ALTER TABLE site_memberships ADD CONSTRAINT chk_site_membership_role/,
    );
  });

  it('db.js\'in mevcut "yalnizca additive" korumalariyla uyumlu (DELETE FROM / DROP TABLE / TRUNCATE yok)', () => {
    const noComments = DB_SOURCE.replace(/\/\/.*$/gm, '').replace(/--.*$/gm, '');
    assert.equal(/\bDELETE\s+FROM\b/i.test(noComments), false);
    assert.equal(/DROP\s+TABLE/i.test(noComments), false);
    assert.equal(/TRUNCATE/i.test(noComments), false);
    // users_role_check tek DROP CONSTRAINT'i korunur
    assert.equal((noComments.match(/DROP\s+CONSTRAINT[^;]*users_role_check/gi) || []).length, 1);
  });

  it('migration, kendisinden once olusan tablolari degistirir (sites 003, site_memberships 016, users 001)', () => {
    const earlier = listMigrations(DEFAULT_MIGRATIONS_DIR)
      .filter((m) => m.number < 29)
      .map((m) => m.sql)
      .join('\n');
    for (const table of ['sites', 'site_memberships', 'users']) {
      assert.match(earlier, new RegExp(`CREATE TABLE IF NOT EXISTS ${table}\\b`), table);
    }
  });
});

describe('platform sema: migration 030 (modul talebi, Faz 1.1)', () => {
  it('030 var, 30. siradadir (numaralar ardisik) ve calistirici icin guvenli (ust duzey BEGIN/COMMIT yok)', () => {
    const list = listMigrations(DEFAULT_MIGRATIONS_DIR);
    assert.ok(list.length >= 30, `en az 30 migration beklenir: ${list.length}`);
    const entry = list.find((m) => m.number === 30);
    assert.ok(entry, '030 numarali migration yok');
    assert.equal(entry.file, '030_module_requests.sql');
    assert.equal(entry.version, '030_module_requests');
    assert.equal(list[29], entry, 'sirali listede 30. eleman');
    assert.deepEqual(findUnsafeStatements(MIGRATION_030), []);
  });

  it('basliginda db.js ile ayni DDL oldugu ve ekleyici/idempotent oldugu belirtilir', () => {
    const header = MIGRATION_030.split('\n').slice(0, 6).join('\n');
    assert.match(header, /db\.js/);
    assert.match(header, /ekleyici/i);
    assert.match(header, /idempotent/i);
  });

  it('db.js ensureDbSchema ayni DDL\'i icerir (yorumlar ve bosluklar disinda birebir); 029\'dan SONRA gelir', () => {
    const normalizedDb = normalizeSql(DB_SOURCE);
    const migration030 = normalizeSql(MIGRATION_030);
    assert.ok(migration030.length > 500, '030 DDL\'i beklenenden kisa');
    assert.ok(normalizedDb.includes(migration030), 'migrations/030_module_requests.sql ile db.js ayni DDL degil');
    // 029 DDL'i de yerinde ve 030'dan once
    assert.ok(normalizedDb.indexOf(normalizeSql(MIGRATION)) < normalizedDb.indexOf(migration030));
  });

  it('module_requests: sozlesmedeki alanlar, FK davranislari, status CHECK ve varsayilanlar', () => {
    const sql = normalizeSql(MIGRATION_030);
    const table = /CREATE TABLE IF NOT EXISTS module_requests \(([\s\S]*?)\);/.exec(sql);
    assert.ok(table, 'module_requests tablosu bulunamadi');
    const body = table[1];
    assert.match(body, /id BIGSERIAL PRIMARY KEY/);
    assert.match(body, /site_code BIGINT NOT NULL REFERENCES sites\(site_code\) ON DELETE CASCADE/);
    assert.match(body, /module_code TEXT NOT NULL/);
    assert.match(body, /status TEXT NOT NULL DEFAULT 'pending'/);
    assert.match(body, /requested_by INTEGER REFERENCES users\(user_code\) ON DELETE SET NULL/);
    assert.match(body, /requested_by_name TEXT/);
    assert.match(body, /note TEXT/);
    assert.match(body, /decided_by INTEGER REFERENCES users\(user_code\) ON DELETE SET NULL/);
    assert.match(body, /decided_by_name TEXT/);
    assert.match(body, /decision_note TEXT/);
    assert.match(body, /created_at TIMESTAMPTZ NOT NULL DEFAULT NOW\(\)/);
    assert.match(body, /decided_at TIMESTAMPTZ(,| \))/);
    assert.match(body, /CHECK \(status IN \('pending', 'approved', 'rejected', 'cancelled'\)\)/);
  });

  it('ayni (site, modul) icin TEK bekleyen talep: kismi tekil indeks; ayrica (status, id DESC) ve (site_code, id DESC) indeksleri', () => {
    const sql = normalizeSql(MIGRATION_030);
    assert.match(
      sql,
      /CREATE UNIQUE INDEX IF NOT EXISTS uq_module_requests_pending ON module_requests \(site_code, module_code\) WHERE status = 'pending'/,
    );
    assert.match(sql, /CREATE INDEX IF NOT EXISTS idx_module_requests_status_id ON module_requests \(status, id DESC\)/);
    assert.match(sql, /CREATE INDEX IF NOT EXISTS idx_module_requests_site_id ON module_requests \(site_code, id DESC\)/);
  });

  it('ekleyici: yalniz CREATE TABLE/INDEX IF NOT EXISTS; mevcut tablo/veriye dokunmaz', () => {
    const sql = normalizeSql(MIGRATION_030);
    assert.equal(/DROP\s|TRUNCATE|DELETE\s+FROM|\bUPDATE\s+\w+\s+SET|\bINSERT\s+INTO|ALTER\s+TABLE/i.test(sql), false);
    assert.deepEqual(sql.match(/CREATE\s+(UNIQUE\s+)?(TABLE|INDEX)\s+(?!IF NOT EXISTS)/gi) || [], []);
    assert.equal((sql.match(/CREATE TABLE IF NOT EXISTS/g) || []).length, 1);
  });

  it('hicbir kaynak dosyasi module_requests satirlarini silmez (talepler denetim izidir); bakim servisi dokunmaz', () => {
    for (const file of listSourceFiles(srcRoot)) {
      const text = readFileSync(file, 'utf8');
      assert.equal(/DELETE\s+FROM\s+module_requests\b|TRUNCATE\s+(TABLE\s+)?module_requests\b|DROP\s+TABLE\s+(IF EXISTS\s+)?module_requests\b/i.test(text), false, file);
    }
    assert.equal(/module_requests/.test(read('services/maintenance_service.js')), false);
  });
});

describe('platform denetim kaydi: yalnizca eklenir', () => {
  it('hicbir kaynak dosyasi audit_log\'u guncellemez/silmez (bakim servisi dahil)', () => {
    for (const file of listSourceFiles(srcRoot)) {
      const text = readFileSync(file, 'utf8');
      assert.equal(/UPDATE\s+audit_log\b|DELETE\s+FROM\s+audit_log\b|TRUNCATE\s+(TABLE\s+)?audit_log\b|DROP\s+TABLE\s+(IF EXISTS\s+)?audit_log\b/i.test(text), false, file);
    }
    assert.equal(/audit_log/.test(read('services/maintenance_service.js')), false);
  });

  it('audit_service yalnizca INSERT ve SELECT kullanir', () => {
    const text = read('modules/audit_service.js');
    assert.match(text, /INSERT INTO audit_log/);
    assert.match(text, /FROM audit_log a/);
  });
});

describe('platform: sunucuya baglanti', () => {
  it('server.js moduleRouter\'i kaydeder (diger router\'lardan sonra, SPA statik servisinden once)', () => {
    const server = read('server.js');
    assert.match(server, /import \{ moduleRouter \} from '\.\/modules\/module_routes\.js';/);
    const mount = server.indexOf('app.use(moduleRouter);');
    assert.ok(mount > server.indexOf('app.use(membershipRouter);'));
    assert.ok(mount < server.indexOf('webBuildPath, { maxAge'), 'moduleRouter SPA statik servisinden once baglanmali');
  });

  it('server.js moduleRequestRouter\'i da kaydeder (moduleRouter\'dan sonra, SPA statik servisinden once)', () => {
    const server = read('server.js');
    assert.match(server, /import \{ moduleRequestRouter \} from '\.\/modules\/module_request_routes\.js';/);
    const mount = server.indexOf('app.use(moduleRequestRouter);');
    assert.ok(mount > server.indexOf('app.use(moduleRouter);'));
    assert.ok(mount < server.indexOf('webBuildPath, { maxAge'));
  });

  it('yeni dosyalar src/modules altindadir (moduler yapi)', () => {
    const files = readdirSync(path.join(srcRoot, 'modules')).sort();
    for (const expected of [
      'audit_service.js',
      'catalog.js',
      'door_guard.js',
      'errors.js',
      'management_types.js',
      'module_request_routes.js',
      'module_request_service.js',
      'module_routes.js',
      'module_service.js',
      'route_helpers.js',
      'staff_role_service.js',
    ]) {
      assert.ok(files.includes(expected), expected);
    }
  });

  it('requireSiteManager ve hasSiteManagementAccess yalnizca SITE_OWNER/SITE_ADMIN\'i yonetici sayar (BOARD_MEMBER/STAFF sayilmaz)', () => {
    const roleLists = [read('middlewares/auth_middleware.js'), read('services/site_service.js')].join('\n');
    assert.equal(/IN \('SITE_OWNER', 'SITE_ADMIN'(, [^)]*)\)/.test(roleLists), false);
    assert.equal(/BOARD_MEMBER|STAFF/.test(read('middlewares/auth_middleware.js')), false);
    assert.equal(/BOARD_MEMBER|STAFF/.test(read('services/site_service.js')), false);
    assert.equal(/BOARD_MEMBER|STAFF/.test(read('services/door_service.js')), false);
  });
});
