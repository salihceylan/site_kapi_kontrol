// Drive dosya kaydı <-> kaynak kayıt bağlantısı (097) şeması (DB'siz): migration <-> drive_source_schema.js aynı DDL (aynı sıra), ekleyici / idempotent,
// db.js bağlantısı (060'tan sonra), her şey varsa ifade yok, eksikse yalnız eksikler, CHECK kuralı iki alanı birlikte zorlar.
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { DEFAULT_MIGRATIONS_DIR, findUnsafeStatements } from '../scripts/migrate.js';
import { DRIVE_SOURCE_DDL, DRIVE_SOURCE_DDL_ORDER, driveSourceTuning, ensureDriveSourceSchema } from '../src/modules/drive_source_schema.js';

driveSourceTuning.retryDelayMs = 1;
const here = path.dirname(fileURLToPath(import.meta.url));
const MIGRATION = readFileSync(path.join(DEFAULT_MIGRATIONS_DIR, '097_drive_file_source_link.sql'), 'utf8').replace(/\r\n/g, '\n');
const DB_SOURCE = readFileSync(path.join(here, '..', 'src', 'db.js'), 'utf8');
const normalize = (text) => text.replace(/--.*$/gm, ' ').replace(/\s+/g, ' ').trim();

describe('drive_source_schema (097)', () => {
  it('migration, DDL ile ayni ifadeler ve ayni sirada', () => {
    const actual = normalize(MIGRATION);
    let cursor = 0;
    for (const name of DRIVE_SOURCE_DDL_ORDER) {
      const statement = normalize(DRIVE_SOURCE_DDL[name]);
      const at = actual.indexOf(statement, cursor);
      assert.ok(at >= cursor, `sirasiz ya da eksik: ${name}`);
      cursor = at + statement.length;
    }
  });

  it('ekleyici ve idempotent: DROP/TRUNCATE/DELETE/UPDATE yok, her ADD COLUMN / CREATE INDEX IF NOT EXISTS, tek transaction guvenli', () => {
    const sql = normalize(MIGRATION);
    assert.ok(!/\b(DROP|TRUNCATE)\b|; ?(DELETE|UPDATE) /i.test(sql));
    for (const add of sql.match(/ADD COLUMN[^;]*/g)) assert.match(add, /ADD COLUMN IF NOT EXISTS/);
    for (const create of sql.match(/CREATE (UNIQUE )?INDEX[^(]*/g)) assert.match(create, /IF NOT EXISTS/);
    assert.deepEqual(findUnsafeStatements(MIGRATION), []);
    // Yeniden calistirilabilir: CHECK kosullu eklenir.
    assert.match(sql, /IF NOT EXISTS \( SELECT 1 FROM pg_constraint WHERE conname = 'chk_drive_files_source'/);
  });

  it('CHECK: kaynak turu ve numarasi birlikte dolu ya da birlikte bos; tek basina dolu NULL kacagi yok', () => {
    const check = normalize(DRIVE_SOURCE_DDL.sourceCheck);
    assert.match(check, /\(source_type IS NULL AND source_id IS NULL\)/);
    assert.match(check, /source_type IS NOT NULL AND source_id IS NOT NULL/);
    assert.match(check, /source_id > 0/);
    assert.match(check, /\^\[a-z\]\[a-z_\]\{0,31\}\$/);
    assert.match(check, /NOT VALID/);
  });

  it('db.js ensureDriveSourceSchema cagirir (dev blokta degil, ensureDriveSchema 060 sonrasi)', () => {
    assert.ok(DB_SOURCE.includes("import { ensureDriveSourceSchema } from './modules/drive_source_schema.js'"));
    assert.ok(DB_SOURCE.indexOf('await ensureDriveSourceSchema(client)') > DB_SOURCE.indexOf('await ensureDriveSchema(client)'));
  });

  it('her sey varsa tek katalog sorgusu (DDL ve kilit yok); tablo yoksa hicbir sey; eksikse yalniz eksikler calisir', async () => {
    const calls = [];
    const make = (row) => ({
      query: async (text) => {
        calls.push(String(text));
        return { rows: [row] };
      },
    });
    await ensureDriveSourceSchema(make({ has_table: true, has_type: true, has_id: true, has_check: true, has_index: true }));
    assert.equal(calls.length, 1);

    calls.length = 0;
    await ensureDriveSourceSchema(make({ has_table: false }));
    assert.equal(calls.length, 1, 'drive_files yoksa ifade gonderilmez');

    calls.length = 0;
    await ensureDriveSourceSchema(make({ has_table: true, has_type: true, has_id: false, has_check: false, has_index: true }));
    const sent = calls.map(normalize);
    assert.ok(sent.some((s) => s.includes('ADD COLUMN IF NOT EXISTS source_id')));
    assert.ok(sent.some((s) => s.includes('chk_drive_files_source')));
    assert.ok(!sent.some((s) => s.includes('ADD COLUMN IF NOT EXISTS source_type')), 'var olan sutun yeniden eklenmez');
    assert.ok(!sent.some((s) => s.startsWith('CREATE INDEX')), 'var olan indeks yeniden kurulmaz');
    assert.ok(sent.includes("SET lock_timeout = '2s'") && sent.includes('RESET lock_timeout'));
  });

  it('kilit/kilitlenme (40P01/55P03) yeniden denenir; baska hata yukari firlatilir ve lock_timeout sifirlanir', async () => {
    let attempts = 0;
    const flaky = {
      query: async (text) => {
        const sql = normalize(text);
        if (sql.startsWith('SELECT')) return { rows: [{ has_table: true, has_type: false, has_id: true, has_check: true, has_index: true }] };
        if (sql.startsWith('ALTER TABLE')) {
          attempts += 1;
          if (attempts < 3) throw Object.assign(new Error('deadlock'), { code: '40P01' });
        }
        return { rows: [] };
      },
    };
    await ensureDriveSourceSchema(flaky);
    assert.equal(attempts, 3);

    const resets = [];
    const broken = {
      query: async (text) => {
        const sql = normalize(text);
        if (sql.startsWith('SELECT')) return { rows: [{ has_table: true, has_type: false, has_id: true, has_check: true, has_index: true }] };
        if (sql.startsWith('RESET')) resets.push(sql);
        if (sql.startsWith('ALTER TABLE')) throw Object.assign(new Error('izin yok'), { code: '42501' });
        return { rows: [] };
      },
    };
    await assert.rejects(ensureDriveSourceSchema(broken), (e) => e.code === '42501');
    assert.equal(resets.length, 1);
  });
});
