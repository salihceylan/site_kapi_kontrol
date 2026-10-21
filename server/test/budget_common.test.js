// İşletme projesi (059): saf yardımcılar (tarih, geçici proje sayacı, girdi doğrulama, karşılaştırma) + migration <-> BUDGET_DDL eşitliği + ensure davranışı (DB'siz).
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { BUDGET_DDL, BUDGET_DDL_ORDER, ensureBudgetSchema, schemaTuning } from '../src/modules/budget_schema.js';
import { addDays, comparisonRow, daysBetween, mapProject, parseCreateInput, parseItemsInput, provisionalRemainingDays } from '../src/modules/budget_service.js';

schemaTuning.retryDelayMs = 1;
const here = path.dirname(fileURLToPath(import.meta.url));
const MIGRATION = readFileSync(path.join(here, '..', 'migrations', '059_budget_projects.sql'), 'utf8').replace(/\r\n/g, '\n');
const squash = (text) => text.replace(/--.*$/gm, ' ').replace(/\s+/g, ' ').replace(/ ?; ?/g, ';').trim();

describe('budget tarih ve sayaç', () => {
  it('addDays / daysBetween ay ve yıl sınırını geçer', () => {
    assert.equal(addDays('2026-12-25', 10), '2027-01-04');
    assert.equal(addDays('2026-10-21', 90), '2027-01-19');
    assert.equal(daysBetween('2026-10-21', '2026-11-01'), 11);
  });
  it('provisionalRemainingDays: kalan gün, bitince 0', () => {
    assert.equal(provisionalRemainingDays('2026-11-08', '2026-10-21'), 18);
    assert.equal(provisionalRemainingDays('2026-10-01', '2026-10-21'), 0);
  });
  it('mapProject: kesin projede kalan gün yok, açık geçici projede var', () => {
    const base = { id: '1', year: 2026, title: 'T', is_provisional: true, provisional_until: '2026-11-08', status: 'taslak' };
    assert.equal(mapProject(base, '2026-10-21').provisional_remaining_days, 18);
    assert.equal(mapProject({ ...base, status: 'kesin' }, '2026-10-21').provisional_remaining_days, null);
    assert.equal(mapProject({ ...base, is_provisional: false }, '2026-10-21').provisional_remaining_days, null);
  });
});

describe('budget girdi doğrulama', () => {
  it('parseCreateInput: geçici proje başlangıcı varsayılan bugün', () => {
    const input = parseCreateInput({ year: 2027, title: ' Yıllık  bütçe ', is_provisional: true }, { today: '2026-10-21' });
    assert.deepEqual(input, { year: 2027, title: 'Yıllık bütçe', note: null, isProvisional: true, provisionalStart: '2026-10-21' });
    assert.equal(parseCreateInput({ year: 2027, title: 'x' }, { today: '2026-10-21' }).provisionalStart, null);
  });
  it('parseCreateInput: geçersiz yıl ve boş başlık 400', () => {
    assert.throws(() => parseCreateInput({ year: 1999, title: 'x' }, { today: '2026-10-21' }), { code: 'INVALID_BODY' });
    assert.throws(() => parseCreateInput({ year: 2027, title: '  ' }, { today: '2026-10-21' }), { code: 'INVALID_BODY' });
  });
  it('parseItemsInput: tamsayı kuruş, tekrar ve negatif reddedilir', () => {
    assert.deepEqual(parseItemsInput({ items: [{ category_id: 3, annual_minor: 120000 }] }), [{ categoryId: 3, annualMinor: 120000 }]);
    assert.throws(() => parseItemsInput({ items: [{ category_id: 3, annual_minor: 1.5 }] }), { code: 'INVALID_BODY' });
    assert.throws(() => parseItemsInput({ items: [{ category_id: 3, annual_minor: -1 }] }), { code: 'INVALID_BODY' });
    assert.throws(() => parseItemsInput({ items: [{ category_id: 3, annual_minor: 1 }, { category_id: 3, annual_minor: 2 }] }), { code: 'INVALID_BODY' });
    assert.throws(() => parseItemsInput({}), { code: 'INVALID_BODY' });
  });
  it('comparisonRow: sapma ve yüzde; planlanan 0 ise yüzde null', () => {
    const row = comparisonRow({ categoryId: 1, categoryName: 'A', plannedMinor: 1000, actualMinor: 1250 });
    assert.equal(row.variance_minor, 250);
    assert.equal(row.used_pct, 125);
    assert.equal(comparisonRow({ categoryId: 1, categoryName: 'A', plannedMinor: 0, actualMinor: 5 }).used_pct, null);
  });
});

describe('budget şema', () => {
  it('migration 059 ifadeleri BUDGET_DDL ile aynı sırada ve aynı', () => {
    const body = squash(MIGRATION);
    let cursor = 0;
    for (const name of BUDGET_DDL_ORDER) {
      const at = body.indexOf(squash(BUDGET_DDL[name]), cursor);
      assert.ok(at >= cursor, `${name} migration'da sırayla bulunamadı`);
      cursor = at;
    }
  });
  it('db.js ensureBudgetSchema çağırır', () => {
    const db = readFileSync(path.join(here, '..', 'src', 'db.js'), 'utf8');
    assert.match(db, /await ensureBudgetSchema\(client\)/);
  });
  it('ensure: her şey varsa ifade göndermez; eksikse tüm ifadeleri sırayla gönderir', async () => {
    const run = async (row) => {
      const sent = [];
      await ensureBudgetSchema({ query: async (sql) => (sent.push(sql), sql.includes('has_categories') ? { rows: [row] } : { rows: [] }) });
      return sent;
    };
    const full = { tables: ['a', 'b'], indexes: ['a', 'b'], fks: [1, 2, 3, 4, 5, 6], has_categories: true };
    assert.equal((await run(full)).length, 1);
    assert.equal((await run({ ...full, tables: ['a'] })).length, 1 + BUDGET_DDL_ORDER.length);
    assert.equal((await run({ tables: [], indexes: [], fks: [], has_categories: false })).length, BUDGET_DDL_ORDER.length);
  });
});
