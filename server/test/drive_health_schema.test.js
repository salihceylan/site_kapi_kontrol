// Drive sağlık/kota/doğrulama sütunları (112) şeması (DB'siz): migration <-> drive_health_schema.js aynı DDL (aynı sıra), ekleyici / idempotent,
// db.js bağlantısı (060'tan sonra), her şey varsa ifade yok, eksikse yalnız eksikler, kilit/kilitlenme yeniden denenir.
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { DEFAULT_MIGRATIONS_DIR, findUnsafeStatements } from '../scripts/migrate.js';
import { DRIVE_HEALTH_DDL, DRIVE_HEALTH_DDL_ORDER, driveHealthTuning, ensureDriveHealthSchema } from '../src/modules/drive_health_schema.js';

driveHealthTuning.retryDelayMs = 1;
const here = path.dirname(fileURLToPath(import.meta.url));
const MIGRATION = readFileSync(path.join(DEFAULT_MIGRATIONS_DIR, '112_drive_health.sql'), 'utf8').replace(/\r\n/g, '\n');
const DB_SOURCE = readFileSync(path.join(here, '..', 'src', 'db.js'), 'utf8');
const normalize = (text) => text.replace(/--.*$/gm, ' ').replace(/\s+/g, ' ').trim();

const ALL_COLUMNS = [
  'site_drive_connections.quota_limit_bytes',
  'site_drive_connections.quota_used_bytes',
  'site_drive_connections.token_expires_at',
  'site_drive_connections.health_checked_at',
  'drive_files.verify_method',
  'drive_pending_uploads.error_kind',
];
const ALL_TABLES = ['site_drive_connections', 'drive_files', 'drive_pending_uploads'];

describe('drive_health_schema (112)', () => {
  it('migration, DDL ile ayni ifadeler ve ayni sirada; ekleyici ve idempotent (DROP/UPDATE/DELETE yok, hep ADD COLUMN IF NOT EXISTS)', () => {
    const actual = normalize(MIGRATION);
    let cursor = 0;
    for (const name of DRIVE_HEALTH_DDL_ORDER) {
      const statement = normalize(DRIVE_HEALTH_DDL[name]);
      const at = actual.indexOf(statement, cursor);
      assert.ok(at >= cursor, `sirasiz ya da eksik: ${name}`);
      cursor = at + statement.length;
    }
    assert.ok(!/\b(DROP|TRUNCATE)\b|; ?(DELETE|UPDATE) /i.test(actual));
    for (const add of actual.match(/ADD COLUMN[^;]*/g)) assert.match(add, /ADD COLUMN IF NOT EXISTS/);
    assert.equal(actual.match(/ADD COLUMN/g).length, DRIVE_HEALTH_DDL_ORDER.length);
    assert.deepEqual(findUnsafeStatements(MIGRATION), []);
  });

  it('db.js ensureDriveHealthSchema cagirir (ensureDriveSchema 060 sonrasi)', () => {
    assert.ok(DB_SOURCE.includes("import { ensureDriveHealthSchema } from './modules/drive_health_schema.js'"));
    assert.ok(DB_SOURCE.indexOf('await ensureDriveHealthSchema(client)') > DB_SOURCE.indexOf('await ensureDriveSchema(client)'));
  });

  it('her sey varsa tek katalog sorgusu (DDL ve kilit yok); tablo yoksa hicbir sey; eksikse yalniz eksik sutunlar; lock_timeout sifirlanir', async () => {
    const calls = [];
    const make = (row) => ({
      query: async (text) => {
        calls.push(normalize(text));
        return { rows: [row] };
      },
    });
    await ensureDriveHealthSchema(make({ tables: ALL_TABLES, columns: ALL_COLUMNS }));
    assert.equal(calls.length, 1);

    calls.length = 0;
    await ensureDriveHealthSchema(make({ tables: [], columns: [] }));
    assert.equal(calls.length, 1, '060 tablolari yoksa ifade gonderilmez');

    calls.length = 0;
    await ensureDriveHealthSchema(make({ tables: ALL_TABLES, columns: ALL_COLUMNS.filter((c) => c !== 'drive_files.verify_method' && c !== 'drive_pending_uploads.error_kind') }));
    const alters = calls.filter((s) => s.startsWith('ALTER TABLE'));
    assert.equal(alters.length, 2);
    assert.ok(alters.some((s) => s.includes('verify_method')) && alters.some((s) => s.includes('error_kind')));
    assert.ok(calls.includes("SET lock_timeout = '2s'") && calls.includes('RESET lock_timeout'));
  });

  it('kilitlenme (40P01/55P03) yeniden denenir; baska hata yukari firlatilir ve lock_timeout yine sifirlanir', async () => {
    let attempts = 0;
    const flaky = {
      query: async (text) => {
        const sql = normalize(text);
        if (sql.startsWith('SELECT')) return { rows: [{ tables: ALL_TABLES, columns: ALL_COLUMNS.filter((c) => c !== 'drive_files.verify_method') }] };
        if (sql.startsWith('ALTER TABLE')) {
          attempts += 1;
          if (attempts < 3) throw Object.assign(new Error('deadlock'), { code: '40P01' });
        }
        return { rows: [] };
      },
    };
    await ensureDriveHealthSchema(flaky);
    assert.equal(attempts, 3);

    const resets = [];
    const broken = {
      query: async (text) => {
        const sql = normalize(text);
        if (sql.startsWith('SELECT')) return { rows: [{ tables: ALL_TABLES, columns: [] }] };
        if (sql.startsWith('RESET')) resets.push(sql);
        if (sql.startsWith('ALTER TABLE')) throw Object.assign(new Error('izin yok'), { code: '42501' });
        return { rows: [] };
      },
    };
    await assert.rejects(ensureDriveHealthSchema(broken), (e) => e.code === '42501');
    assert.equal(resets.length, 1);
  });
});
