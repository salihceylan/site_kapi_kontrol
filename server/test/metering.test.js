// Sayac modulu (061), DB'siz: migration <-> metering_schema.js birebir esitlik, ensure (eksikleri sirayla calistirir / hicbir sey eksik degilse sorgu gondermez),
// saf hesap (tuketim, birim fiyat, fatura orantisi, isi payi), girdi dogrulayicilari, db.js baglantisi. Gercek PostgreSQL denemesi kullanicidadir.
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { DEFAULT_MIGRATIONS_DIR, findUnsafeStatements } from '../scripts/migrate.js';
import { METERING_DDL, METERING_STEP_NAMES, ensureMeteringSchema, schemaTuning } from '../src/modules/metering_schema.js';
import { buildMeterPlan, consumptionByApartment, consumptionOfMeter, priceOf } from '../src/modules/metering_calc.js';
import { parseBillingInput } from '../src/modules/metering_billing.js';
import { milliOf, milliText, parseReadingValue } from '../src/modules/metering_common.js';
import { MODULE_CATALOG } from '../src/modules/catalog.js';

schemaTuning.retryDelayMs = 1;
const here = path.dirname(fileURLToPath(import.meta.url));
const MIGRATION = readFileSync(path.join(DEFAULT_MIGRATIONS_DIR, '061_metering.sql'), 'utf8').replace(/\r\n/g, '\n');
const DB_SOURCE = readFileSync(path.join(here, '..', 'src', 'db.js'), 'utf8');
const norm = (text) => text.replace(/--.*$/gm, ' ').replace(/\s+/g, ' ').replace(/ ;/g, ';').trim();

describe('061 sema', () => {
  it('migration, METERING_DDL ile birebir ayni (ayni sira) ve guvenli', () => {
    assert.equal(norm(MIGRATION), norm(Object.values(METERING_DDL).map((s) => `${s};`).join('\n')));
    assert.deepEqual(findUnsafeStatements(MIGRATION), []);
    assert.deepEqual(METERING_STEP_NAMES, Object.keys(METERING_DDL));
    assert.doesNotMatch(MIGRATION, /\b(DROP|TRUNCATE)\b|\bDELETE\s+FROM|\bUPDATE\s+\w+\s+SET/i);
  });

  it('db.js ensureMeteringSchema cagirir', () => {
    assert.match(DB_SOURCE, /await ensureMeteringSchema\(client\)/);
  });

  it('hicbir sey eksik degilse yalniz katalog sorgusu gider; eksikse yalniz eksikler sirayla', async () => {
    const all = { tables: ['meters', 'meter_readings', 'meter_billings', 'meter_billing_lines'] };
    const calls = [];
    const make = (found) => ({
      async query(sql) {
        calls.push(sql);
        return /to_regclass/.test(sql) ? { rows: [found] } : { rows: [] };
      },
    });
    const full = {
      tables: all.tables,
      indexes: ['uq_meters_site_kind_serial', 'idx_meters_apartment', 'uq_meter_readings_meter_date', 'uq_meter_billings_key', 'idx_meter_billings_site_kind', 'idx_meter_billing_lines_billing'],
      fks: [
        'meters.meters_site_code_fkey',
        'meters.meters_apartment_id_fkey',
        'meters.meters_created_by_fkey',
        'meter_readings.meter_readings_site_code_fkey',
        'meter_readings.meter_readings_meter_id_fkey',
        'meter_readings.meter_readings_created_by_fkey',
        'meter_billings.meter_billings_site_code_fkey',
        'meter_billings.meter_billings_posted_by_fkey',
        'meter_billing_lines.meter_billing_lines_billing_id_fkey',
        'meter_billing_lines.meter_billing_lines_site_code_fkey',
      ],
    };
    await ensureMeteringSchema(make(full));
    assert.equal(calls.length, 1);
    calls.length = 0;
    await ensureMeteringSchema(make({ tables: [], indexes: [], fks: [] }));
    const ddl = calls.filter((c) => !/to_regclass|lock_timeout/.test(c));
    assert.equal(ddl.length, METERING_STEP_NAMES.length);
    assert.match(ddl[0], /CREATE TABLE IF NOT EXISTS meters/);
  });
});

describe('katalog', () => {
  it('metering kullanilabilir ve varsayilan KAPALI', () => {
    const entry = MODULE_CATALOG.find((m) => m.code === 'metering');
    assert.equal(entry.status, 'available');
    assert.equal(entry.defaultEnabled, false);
    assert.equal(entry.core, false);
  });
});

describe('okuma degeri', () => {
  it('ondalik, virgul ve sinirlar', () => {
    assert.equal(parseReadingValue('12,5').text, '12.500');
    assert.equal(parseReadingValue(7).text, '7.000');
    assert.equal(parseReadingValue('0.001').milli, 1n);
    for (const bad of ['-1', '1.2345', 'abc', '', null, NaN, 1e21, '1e3', '123456789012']) assert.equal(parseReadingValue(bad), null, String(bad));
    assert.equal(milliOf('123.450'), 123450n);
    assert.equal(milliText(123450n), '123.450');
  });
});

describe('tuketim', () => {
  const base = { opening: 1000n, closing: 6500n, openingDate: '2026-08-31', closingDate: '2026-09-30' };
  it('fark, eksik acilis/kapanis, azalan', () => {
    assert.deepEqual(consumptionOfMeter(base), { milli: 5500n });
    assert.deepEqual(consumptionOfMeter({ ...base, opening: null }), { missing: 'no_opening' });
    assert.deepEqual(consumptionOfMeter({ ...base, closingDate: '2026-08-31' }), { missing: 'no_closing' });
    assert.deepEqual(consumptionOfMeter({ ...base, closing: 500n }), { missing: 'decreasing' });
  });
  it('bir dairenin sayaci eksikse daire eksiktir; cok sayac toplanir', () => {
    const { byApartment, missing } = consumptionByApartment([
      { apartmentId: 1, ...base },
      { apartmentId: 1, ...base },
      { apartmentId: 2, ...base },
      { apartmentId: 2, ...base, opening: null },
    ]);
    assert.equal(byApartment.get(1), 11000n);
    assert.equal(byApartment.has(2), false);
    assert.equal(missing.get(2), 'no_opening');
  });
});

describe('dagitim', () => {
  const apartments = [{ id: 1, areaX100: 10000n }, { id: 2, areaX100: 10000n }, { id: 3, areaX100: 20000n }];
  const consumption = new Map([[1, 10000n], [2, 30000n], [3, 0n]]);
  it('birim fiyat: yarim yukari yuvarlar, sifir tutari atlar', () => {
    assert.equal(priceOf(1500n, 333), 500n);
    const plan = buildMeterPlan({ method: 'unit_price', apartments, consumption, unitPriceMinor: 250 });
    assert.deepEqual(plan.lines.map((l) => [l.apartmentId, l.amount]), [[1, 2500n], [2, 7500n]]);
    assert.equal(plan.zeroCount, 1);
    assert.equal(plan.total, 10000n);
  });
  it('fatura: tuketime orantili, toplam birebir', () => {
    const plan = buildMeterPlan({ method: 'invoice', apartments, consumption, totalMinor: 10001 });
    assert.equal(plan.total, 10001n);
    assert.deepEqual(plan.lines.map((l) => l.apartmentId), [1, 2]);
  });
  it('fatura: tuketim yoksa NO_CONSUMPTION', () => {
    assert.throws(() => buildMeterPlan({ method: 'invoice', apartments, consumption: new Map(), totalMinor: 100 }), { code: 'NO_CONSUMPTION' });
  });
  it('isi: %70 olcum + %30 alan, toplam birebir', () => {
    const plan = buildMeterPlan({ method: 'heat', apartments, consumption, totalMinor: 100000, measuredPct: 70 });
    // olcum 70000: 1 -> 17500, 2 -> 52500; alan 30000: 1 -> 7500, 2 -> 7500, 3 -> 15000
    assert.deepEqual(plan.lines.map((l) => [l.apartmentId, l.amount]), [[1, 25000n], [2, 60000n], [3, 15000n]]);
    assert.equal(plan.total, 100000n);
  });
  it('isi: alani olmayan daire alan payi almaz ve raporlanir', () => {
    const plan = buildMeterPlan({
      method: 'heat',
      apartments: [{ id: 1, areaX100: 10000n }, { id: 2, areaX100: null }],
      consumption: new Map([[1, 1000n], [2, 1000n]]),
      totalMinor: 1000,
      measuredPct: 50,
    });
    assert.deepEqual(plan.areaMissing, [2]);
    assert.equal(plan.total, 1000n);
    assert.equal(plan.lines.find((l) => l.apartmentId === 1).amount, 750n);
  });
});

describe('fatura girdisi', () => {
  const ok = { kind: 'water', method: 'unit_price', period_from: '2026-08-31', period_to: '2026-09-30', unit_price_minor: 4500 };
  it('gecerli ve gecersiz girdiler', () => {
    assert.equal(parseBillingInput(ok).unitPriceMinor, 4500);
    assert.throws(() => parseBillingInput({ ...ok, method: 'heat' }), { code: 'INVALID_BODY' });
    assert.throws(() => parseBillingInput({ ...ok, period_to: '2026-08-31' }), { code: 'INVALID_BODY' });
    assert.throws(() => parseBillingInput({ ...ok, unit_price_minor: 12.5 }), { code: 'INVALID_BODY' });
    assert.throws(() => parseBillingInput({ ...ok, unit_price_minor: '4500' }), { code: 'INVALID_BODY' });
    assert.throws(() => parseBillingInput({ ...ok, kind: 'gaz' }), { code: 'INVALID_BODY' });
    assert.throws(() => parseBillingInput(ok, { commit: true }), { code: 'INVALID_BODY' });
    const heat = parseBillingInput({ kind: 'heat', method: 'heat', period_from: '2026-01-01', period_to: '2026-02-01', total_minor: 500000 });
    assert.equal(heat.totalMinor, 500000);
  });
  it('kayit icin onizleme bilgisi ve anahtar zorunlu', () => {
    const commit = parseBillingInput(
      { ...ok, idempotency_key: 'abcdefgh-1234', expected_total_minor: 100, expected_count: 2, expected_hash: 'x' },
      { commit: true },
    );
    assert.equal(commit.expected.count, 2);
  });
});
