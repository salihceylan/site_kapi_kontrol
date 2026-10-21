// Ekipman, bakim ve teklif (068): migration <-> equipment_schema.js ayni DDL, ekleyici/idempotent, db.js baglantisi, girdi dogrulama, katalog varsayilani KAPALI.
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { DEFAULT_MIGRATIONS_DIR, findUnsafeStatements } from '../scripts/migrate.js';
import { EQUIPMENT_STEPS, ensureEquipmentSchema, equipmentMigrationBody, schemaTuning } from '../src/modules/equipment_schema.js';
import { isoDate, kurus, text, DEFAULT_KINDS } from '../src/modules/equipment_service.js';
import { MODULE_CATALOG } from '../src/modules/catalog.js';

schemaTuning.retryDelayMs = 1;
const here = path.dirname(fileURLToPath(import.meta.url));
const norm = (s) => s.replace(/\r\n/g, '\n').replace(/--.*$/gm, '').replace(/\s+/g, ' ').trim();
const MIGRATION = readFileSync(path.join(DEFAULT_MIGRATIONS_DIR, '068_equipment.sql'), 'utf8');
const DB_SOURCE = readFileSync(path.join(here, '..', 'src', 'db.js'), 'utf8');

describe('equipment_schema', () => {
  it('migration 068 govdesi adimlarin birlesimidir', () => {
    assert.ok(norm(MIGRATION).includes(norm(equipmentMigrationBody())));
  });
  it('ekleyici ve idempotent: DROP/DELETE/UPDATE yok, hepsi IF NOT EXISTS korumali', () => {
    for (const step of EQUIPMENT_STEPS) {
      assert.doesNotMatch(step.sql, /\b(DROP|TRUNCATE|DELETE FROM|UPDATE)\b/i);
      assert.match(step.sql, /IF NOT EXISTS/);
    }
    assert.deepEqual(findUnsafeStatements(MIGRATION), []);
  });
  it('sira: tablolar, FK, indeks; FK basina tek ust tablo', () => {
    const kinds = EQUIPMENT_STEPS.map((s) => s.kind);
    assert.deepEqual(kinds, [...kinds].sort((a, b) => ['table', 'fk', 'index'].indexOf(a) - ['table', 'fk', 'index'].indexOf(b)));
    assert.equal(EQUIPMENT_STEPS.filter((s) => s.kind === 'table').length, 5);
  });
  it('db.js ensureEquipmentSchema cagirir', () => {
    assert.match(DB_SOURCE, /await ensureEquipmentSchema\(client\)/);
  });
  it('her sey varsa hicbir DDL gonderilmez; eksikse yalniz eksikler calisir', async () => {
    const all = EQUIPMENT_STEPS.map((s) => s.name);
    const sent = [];
    const mk = (present) => ({
      async query(sql) {
        if (/unnest/.test(sql)) {
          return { rows: [{ tables: present.filter((n) => n.startsWith('equipment_') && !n.endsWith('_fkey')), fks: present.filter((n) => n.endsWith('_fkey')), indexes: present.filter((n) => n.startsWith('idx_')) }] };
        }
        sent.push(sql);
        return { rows: [] };
      },
    });
    await ensureEquipmentSchema(mk(all));
    assert.equal(sent.length, 0);
    await ensureEquipmentSchema(mk(all.filter((n) => n !== 'idx_equipment_quotes_topic')));
    assert.equal(sent.filter((s) => /CREATE INDEX/.test(s)).length, 1);
  });
});

describe('equipment girdi dogrulama', () => {
  it('tarih, kurus ve metin', () => {
    assert.equal(isoDate('2026-02-28', 'd', 'D'), '2026-02-28');
    assert.throws(() => isoDate('2026-02-30', 'd', 'D'), { code: 'INVALID_FIELD' });
    assert.equal(kurus(1250, 'k', 'K', { required: true, min: 1 }), 1250);
    assert.throws(() => kurus(12.5, 'k', 'K'), { code: 'INVALID_FIELD' });
    assert.throws(() => kurus('100', 'k', 'K'), { code: 'INVALID_FIELD' });
    assert.throws(() => text('x'.repeat(200), 'n', 'N', 120), { code: 'INVALID_FIELD' });
    assert.throws(() => text('', 'n', 'N', 120, { required: true }), { code: 'INVALID_FIELD' });
  });
  it('varsayilan turler ve asansor yillik yasal kontrol', () => {
    assert.equal(DEFAULT_KINDS.length, 9);
    assert.equal(DEFAULT_KINDS.find((k) => k.code === 'asansor').legal_months, 12);
  });
  it('modul katalogda var ve varsayilan KAPALI', () => {
    const entry = (MODULE_CATALOG ?? []).find((m) => m.code === 'equipment');
    assert.ok(entry);
    assert.equal(entry.defaultEnabled, false);
  });
});
