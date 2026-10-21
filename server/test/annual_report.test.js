import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { ANNUAL_REPORT_DDL } from '../src/modules/annual_report_schema.js';
import { forecastExpense, parseGrowth, parseYear, sanitizeEdits, EDIT_MAX } from '../src/modules/annual_report_service.js';

const norm = (s) => s.replace(/--.*$/gm, '').replace(/\s+/g, ' ').replace(/ ?\( ?/g, '(').replace(/ ?\) ?/g, ')').replace(/ ?, ?/g, ',').trim();
const migration = readFileSync(path.join(path.dirname(fileURLToPath(import.meta.url)), '..', 'migrations', '069_annual_report.sql'), 'utf8');

describe('069 faaliyet raporu', () => {
  it('db.js DDL migration ile birebir ve idempotent', () => {
    const all = norm(migration);
    for (const [name, sql] of Object.entries(ANNUAL_REPORT_DDL)) {
      assert.match(sql, /IF NOT EXISTS/, name);
      assert.ok(all.includes(norm(sql)), `${name} migration ile ayni degil`);
    }
  });

  it('yil dogrulamasi', () => {
    const now = new Date('2026-10-21T00:00:00Z');
    assert.equal(parseYear('2025', now), 2025);
    assert.equal(parseYear('2026', now), 2026);
    for (const bad of ['2027', '99', 'abc', '', undefined, '2025.5']) assert.throws(() => parseYear(bad, now), (e) => e.code === 'INVALID_FIELD');
  });

  it('buyume orani sinirlari', () => {
    assert.equal(parseGrowth(undefined), null);
    assert.equal(parseGrowth('2500'), 2500);
    assert.throws(() => parseGrowth('50001'));
    assert.throws(() => parseGrowth('1.5'));
  });

  it('duzenleme metinleri temizlenir, bilinmeyen bolum reddedilir', () => {
    assert.deepEqual(sanitizeEdits({ general: '  Merhaba​ ', finance: '', works: null }), { general: 'Merhaba' });
    assert.throws(() => sanitizeEdits({ nope: 'x' }));
    assert.throws(() => sanitizeEdits({ general: 5 }));
    assert.throws(() => sanitizeEdits({ general: 'x'.repeat(EDIT_MAX + 1) }));
    assert.throws(() => sanitizeEdits([]));
    assert.deepEqual(sanitizeEdits(undefined), {});
  });

  it('gelecek yil gider tahmini tamsayi kurus', () => {
    assert.equal(forecastExpense(1000000, 0), 1000000);
    assert.equal(forecastExpense(1000000, 2500), 1250000);
    assert.equal(forecastExpense(333, 1000), 366);
    assert.equal(forecastExpense(1000000, -1000), 900000);
  });
});
