import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';
import { expenseNatureMigrationBody } from '../src/modules/finance_expense_nature_schema.js';
import { categoryDefaultNature, parseNature, suggestExpenseNature } from '../src/modules/finance_expense_nature.js';
import { buildForecast, changeBp, divRound, parseAnalysisQuery } from '../src/modules/finance_expense_analysis.js';

test('oneri sirasi: sozlesme > tekrar > kategori > varsayilan', () => {
  assert.deepEqual(suggestExpenseNature({ activeContract: true, recurringMonths: 0, categoryName: 'Diğer' }), { nature: 'routine', reason: 'contract' });
  assert.deepEqual(suggestExpenseNature({ activeContract: false, recurringMonths: 2, categoryName: 'Diğer' }), { nature: 'routine', reason: 'recurring' });
  assert.deepEqual(suggestExpenseNature({ activeContract: false, recurringMonths: 1, categoryName: 'Elektrik' }), { nature: 'routine', reason: 'category' });
  assert.deepEqual(suggestExpenseNature({ activeContract: false, recurringMonths: 1, categoryName: 'Bakım-onarım' }), { nature: 'unexpected', reason: 'default' });
  assert.equal(categoryDefaultNature('Özel kategori'), 'unexpected');
  assert.equal(categoryDefaultNature('SU'), 'routine');
});

test('parseNature', () => {
  assert.equal(parseNature(undefined), null);
  assert.equal(parseNature('routine'), 'routine');
  assert.throws(() => parseNature('x'));
});

test('divRound yarim yukari', () => {
  assert.equal(divRound(3n, 2n), 2n);
  assert.equal(divRound(-3n, 2n), -1n);
  assert.equal(divRound(10n, 4n), 3n);
  assert.equal(changeBp(112n, 100n), 1200);
  assert.equal(changeBp(5n, 0n), null);
});

test('tahmin: altin tablo 12 ay ve 4 ay, toplam = parcalar', () => {
  const full = buildForecast([{ category_name: 'Elektrik', routine: 1200n, unexpected: 600n }], 12, 1000);
  assert.equal(full.items[0].forecast_routine_minor, 1320);
  assert.equal(full.items[0].forecast_minor, 1920);
  const short = buildForecast([{ category_name: 'Su', routine: 400n, unexpected: 0n }, { category_name: 'Diğer', routine: 0n, unexpected: 1n }], 4, 0);
  assert.equal(short.items.find((i) => i.category_name === 'Su').forecast_minor, 1200);
  assert.equal(short.items.find((i) => i.category_name === 'Diğer').annual_unexpected_minor, 3);
  assert.equal(short.totals.forecast_minor, short.items.reduce((s, i) => s + i.forecast_minor, 0));
  assert.equal(buildForecast([], 0, 0), null);
});

test('analiz sorgusu: pencere ve artis siniri', () => {
  const now = new Date('2026-10-21T10:00:00Z');
  assert.equal(parseAnalysisQuery({}, now).window, 3);
  assert.throws(() => parseAnalysisQuery({ window: '5' }, now));
  assert.throws(() => parseAnalysisQuery({ increase_bp: '10001' }, now));
  assert.throws(() => parseAnalysisQuery({ to: '2027-01' }, now));
  assert.equal(parseAnalysisQuery({ increase_bp: '0' }, now).increaseBp, 0);
});

test('056 migration dosyasi sema modulu ile ayni DDL', () => {
  const sql = fs.readFileSync(new URL('../migrations/056_expense_natures.sql', import.meta.url), 'utf8').replace(/\r\n/g, '\n');
  assert.ok(sql.includes(expenseNatureMigrationBody()));
});
