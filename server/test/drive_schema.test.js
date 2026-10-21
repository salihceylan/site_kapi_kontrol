// Site Drive deposu (060) şeması (DB'siz): migration <-> drive_schema.js aynı DDL (aynı sıra), ekleyici / idempotent, db.js bağlantısı, eksik yoksa ifade yok.
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { DEFAULT_MIGRATIONS_DIR, findUnsafeStatements } from '../scripts/migrate.js';
import { DRIVE_DDL, DRIVE_DDL_ORDER, ensureDriveSchema, schemaTuning } from '../src/modules/drive_schema.js';

schemaTuning.retryDelayMs = 1;
const here = path.dirname(fileURLToPath(import.meta.url));
const MIGRATION = readFileSync(path.join(DEFAULT_MIGRATIONS_DIR, '060_drive_storage.sql'), 'utf8').replace(/\r\n/g, '\n');
const DB_SOURCE = readFileSync(path.join(here, '..', 'src', 'db.js'), 'utf8');
const normalize = (text) => text.replace(/--.*$/gm, ' ').replace(/\s+/g, ' ').trim();

describe('drive_schema (060)', () => {
  it('migration, DDL ile ayni ifadeler ve ayni sirada', () => {
    const expected = DRIVE_DDL_ORDER.map((name) => normalize(DRIVE_DDL[name]));
    const actual = normalize(MIGRATION);
    let cursor = 0;
    for (const statement of expected) {
      const at = actual.indexOf(statement, cursor);
      assert.ok(at >= cursor, `sirasiz ya da eksik: ${statement.slice(0, 60)}`);
      cursor = at + statement.length;
    }
  });

  it('ekleyici ve idempotent: DROP/DELETE/TRUNCATE yok, her CREATE IF NOT EXISTS', () => {
    assert.ok(!/\b(DROP|TRUNCATE)\b|; ?(DELETE|UPDATE) /i.test(normalize(MIGRATION)));
    for (const create of normalize(MIGRATION).match(/CREATE (UNIQUE )?(TABLE|INDEX)[^(]*/g)) {
      assert.match(create, /IF NOT EXISTS/);
    }
    assert.deepEqual(findUnsafeStatements?.(MIGRATION) ?? [], []);
  });

  it('db.js ensureDriveSchema cagirir (dev blokta degil, 053 sonrasi)', () => {
    assert.ok(DB_SOURCE.indexOf('await ensureDriveSchema(client)') > DB_SOURCE.indexOf('await ensurePlatformRulesSchema(client)'));
  });

  it('her sey varsa hicbir DDL gonderilmez; eksikse yalniz eksikler calisir', async () => {
    const calls = [];
    const full = {
      query: async (text) => {
        calls.push(String(text));
        return {
          rows: [
            {
              tables: ['site_drive_connections', 'drive_oauth_states', 'drive_files', 'drive_pending_uploads'],
              indexes: ['idx_drive_files_name', 'idx_drive_files_site', 'idx_drive_pending_due', 'idx_drive_oauth_states_expiry'],
              fks: [
                'site_drive_connections.site_drive_connections_site_code_fkey',
                'site_drive_connections.site_drive_connections_connected_by_fkey',
                'drive_oauth_states.drive_oauth_states_site_code_fkey',
                'drive_files.drive_files_site_code_fkey',
                'drive_files.drive_files_uploaded_by_fkey',
                'drive_pending_uploads.drive_pending_uploads_file_id_fkey',
                'drive_pending_uploads.drive_pending_uploads_site_code_fkey',
              ],
            },
          ],
        };
      },
    };
    await ensureDriveSchema(full);
    assert.equal(calls.length, 1);

    const sent = [];
    const empty = {
      query: async (text) => {
        sent.push(normalize(String(text)));
        return { rows: [{ tables: [], indexes: [], fks: [] }] };
      },
    };
    await ensureDriveSchema(empty);
    assert.ok(sent.some((s) => s.startsWith('CREATE TABLE IF NOT EXISTS drive_files')));
    assert.ok(sent.some((s) => s.startsWith('CREATE UNIQUE INDEX IF NOT EXISTS idx_drive_files_name')));
  });
});
