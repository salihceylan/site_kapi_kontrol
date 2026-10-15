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

  it('yeni dosyalar src/modules altindadir (moduler yapi)', () => {
    const files = readdirSync(path.join(srcRoot, 'modules')).sort();
    for (const expected of [
      'audit_service.js',
      'catalog.js',
      'door_guard.js',
      'errors.js',
      'management_types.js',
      'module_routes.js',
      'module_service.js',
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
