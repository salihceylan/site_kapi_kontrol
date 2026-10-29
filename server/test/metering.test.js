// Sayac modulu (061), DB'siz: migration <-> metering_schema.js birebir esitlik, ensure (eksikleri sirayla calistirir / hicbir sey eksik degilse sorgu gondermez),
// saf hesap (tuketim, birim fiyat, fatura orantisi, isi payi), girdi dogrulayicilari, db.js baglantisi. Gercek PostgreSQL denemesi kullanicidadir.
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { DEFAULT_MIGRATIONS_DIR, findUnsafeStatements } from '../scripts/migrate.js';
import { METERING_DDL, METERING_STEP_NAMES, ensureMeteringSchema, schemaTuning } from '../src/modules/metering_schema.js';
import { areaShareGaps, areaShareItems, buildMeterPlan, consumptionByApartment, consumptionOfMeter, priceOf } from '../src/modules/metering_calc.js';
import { computeBillingPlan, parseBillingInput } from '../src/modules/metering_billing.js';
import { milliOf, milliText, parseReadingValue } from '../src/modules/metering_common.js';
import { invalidateRuleCache } from '../src/modules/platform_rules.js';
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
  // m2 sistemden kaldirildi: dairelerin alan bilgisi yok. Arsa payi yoksa alan payi ESIT dagitilir.
  const apartments = [{ id: 1 }, { id: 2 }, { id: 3 }];
  const consumption = new Map([[1, 10000n], [2, 30000n], [3, 0n]]);
  it('birim fiyat: yarim yukari yuvarlar, sifir tutari atlar', () => {
    assert.equal(priceOf(1500n, 333), 500n);
    const plan = buildMeterPlan({ method: 'unit_price', apartments, consumption, unitPriceMinor: 250 });
    assert.deepEqual(plan.lines.map((l) => [l.apartmentId, l.amount]), [[1, 2500n], [2, 7500n]]);
    assert.equal(plan.zeroCount, 1);
    assert.equal(plan.total, 10000n);
    assert.equal(plan.areaBasis, null);
  });
  it('fatura: tuketime orantili, toplam birebir', () => {
    const plan = buildMeterPlan({ method: 'invoice', apartments, consumption, totalMinor: 10001 });
    assert.equal(plan.total, 10001n);
    assert.deepEqual(plan.lines.map((l) => l.apartmentId), [1, 2]);
  });
  it('fatura: tuketim yoksa NO_CONSUMPTION', () => {
    assert.throws(() => buildMeterPlan({ method: 'invoice', apartments, consumption: new Map(), totalMinor: 100 }), { code: 'NO_CONSUMPTION' });
  });
  it('isi: %70 olcum + %30 alan payi (arsa payi yoksa ESIT), toplam birebir', () => {
    const plan = buildMeterPlan({ method: 'heat', apartments, consumption, totalMinor: 100000, measuredPct: 70 });
    // olcum 70000: 1 -> 17500, 2 -> 52500; alan payi 30000 esit: her daire 10000
    assert.deepEqual(plan.lines.map((l) => [l.apartmentId, l.amount]), [[1, 27500n], [2, 62500n], [3, 10000n]]);
    assert.equal(plan.total, 100000n);
    assert.equal(plan.areaBasis, 'equal');
    assert.equal('areaMissing' in plan, false);
  });
  it('isi: arsa payi SECILIRSE alan payi arsa payina gore dagitilir', () => {
    const withShare = [
      { id: 1, landShareNumerator: 1, landShareDenominator: 4 },
      { id: 2, landShareNumerator: 1, landShareDenominator: 4 },
      { id: 3, landShareNumerator: 2, landShareDenominator: 4 },
    ];
    const plan = buildMeterPlan({ method: 'heat', apartments: withShare, consumption, totalMinor: 100000, measuredPct: 70, areaBasis: 'land_share' });
    // olcum 70000: 1 -> 17500, 2 -> 52500; alan payi 30000 arsa payina gore: 1 -> 7500, 2 -> 7500, 3 -> 15000
    assert.deepEqual(plan.lines.map((l) => [l.apartmentId, l.amount]), [[1, 25000n], [2, 60000n], [3, 15000n]]);
    assert.equal(plan.total, 100000n);
    assert.equal(plan.areaBasis, 'land_share');
  });
  it('K5: tum dairelerin arsa payi tanimli olsa bile taban SECILMEDIYSE (varsayilan) alan payi ESIT dagitilir; kod arsa payina gecmez', () => {
    const withShare = [
      { id: 1, landShareNumerator: 1, landShareDenominator: 4 },
      { id: 2, landShareNumerator: 1, landShareDenominator: 4 },
      { id: 3, landShareNumerator: 2, landShareDenominator: 4 },
    ];
    const plan = buildMeterPlan({ method: 'heat', apartments: withShare, consumption, totalMinor: 100000, measuredPct: 70 });
    // olcum 70000: 1 -> 17500, 2 -> 52500; alan payi 30000 ESIT: her daire 10000
    assert.deepEqual(plan.lines.map((l) => [l.apartmentId, l.amount]), [[1, 27500n], [2, 62500n], [3, 10000n]]);
    assert.equal(plan.areaBasis, 'equal');
    assert.equal(areaShareItems(withShare).basis, 'equal');
  });
  it('isi: kisi sayisi SECILIRSE alan payi guncel kisi sayisina gore dagitilir (3 kisi : 1 kisi : 2 kisi)', () => {
    const withPeople = [{ id: 1, personCount: 3 }, { id: 2, personCount: 1 }, { id: 3, personCount: 2 }];
    const plan = buildMeterPlan({ method: 'heat', apartments: withPeople, consumption, totalMinor: 100000, measuredPct: 70, areaBasis: 'person_count' });
    // olcum 70000: 1 -> 17500, 2 -> 52500; alan payi 30000 kisi sayisina gore (3/6, 1/6, 2/6): 1 -> 15000, 2 -> 5000, 3 -> 10000
    assert.deepEqual(plan.lines.map((l) => [l.apartmentId, l.amount]), [[1, 32500n], [2, 57500n], [3, 10000n]]);
    assert.equal(plan.total, 100000n);
    assert.equal(plan.areaBasis, 'person_count');
  });
  it('isi: farkli paydalar ortak paydaya getirilir (1/2, 1/3, 1/6)', () => {
    const items = areaShareItems([
      { id: 1, landShareNumerator: 1, landShareDenominator: 2 },
      { id: 2, landShareNumerator: 1, landShareDenominator: 3 },
      { id: 3, landShareNumerator: 1, landShareDenominator: 6 },
    ], 'land_share');
    assert.equal(items.basis, 'land_share');
    assert.deepEqual(items.items.map((i) => [i.id, i.weight]), [[1, 3n], [2, 2n], [3, 1n]]);
  });
  it('K5: secilen tabanin verisi eksik daire sessizce esit paya DUSURULMEZ; eksik veri olarak raporlanir (areaShareGaps), areaShareItems reddeder', () => {
    const missingOne = [
      { id: 1, landShareNumerator: 1, landShareDenominator: 4 },
      { id: 2, landShareNumerator: null, landShareDenominator: null },
      { id: 3, landShareNumerator: 2, landShareDenominator: 4 },
    ];
    assert.deepEqual(areaShareGaps(missingOne, 'land_share'), [{ id: 2, reason: 'land_share_missing' }]);
    assert.deepEqual(areaShareGaps([{ id: 1, landShareNumerator: 1, landShareDenominator: 0 }], 'land_share'), [{ id: 1, reason: 'land_share_missing' }]);
    assert.throws(() => areaShareItems(missingOne, 'land_share'), RangeError);
    // esit tabanin verisi gerekmez; ayni daireler esit tabanda eksik sayilmaz
    assert.deepEqual(areaShareGaps(missingOne, 'equal'), []);
    assert.equal(areaShareItems(missingOne).basis, 'equal');
    assert.deepEqual(areaShareItems(missingOne).items.map((i) => i.weight), [1n, 1n, 1n]);
    // kisi sayisi: kayit yok (null) ve 0 eksik veridir
    const people = [{ id: 1, personCount: 2 }, { id: 2, personCount: 0 }, { id: 3 }, { id: 4, personCount: null }];
    assert.deepEqual(areaShareGaps(people, 'person_count'), [
      { id: 2, reason: 'person_count_missing' },
      { id: 3, reason: 'person_count_missing' },
      { id: 4, reason: 'person_count_missing' },
    ]);
    assert.throws(() => areaShareItems(people, 'person_count'), RangeError);
    // tum paylar 0: dagitilacak pay yok -> 409 (sessiz esit paya dusulmez)
    assert.throws(
      () => areaShareItems([{ id: 1, landShareNumerator: 0, landShareDenominator: 4 }, { id: 2, landShareNumerator: 0, landShareDenominator: 4 }], 'land_share'),
      { code: 'AREA_BASIS_UNUSABLE' },
    );
    assert.throws(() => areaShareItems([{ id: 1 }], 'm2'), RangeError);
  });
  it('isi: alan payi tuketimden bagimsizdir; olcum payi %0 iken tuketim olmasa da hata vermez (yaniltici NO_CONSUMPTION yok)', () => {
    const plan = buildMeterPlan({ method: 'heat', apartments, consumption: new Map([[1, 0n], [2, 0n], [3, 0n]]), totalMinor: 9001, measuredPct: 0 });
    assert.equal(plan.total, 9001n);
    assert.equal(plan.lines.length, 3);
    assert.equal(plan.areaBasis, 'equal');
  });
  it('isi: tuketim yoksa YALNIZ olcum payi icin NO_CONSUMPTION; olcum payi %0 ise alan payi yine de dagitilir', () => {
    const none = new Map();
    assert.throws(() => buildMeterPlan({ method: 'heat', apartments, consumption: none, totalMinor: 1000, measuredPct: 70 }), { code: 'NO_CONSUMPTION' });
    const plan = buildMeterPlan({ method: 'heat', apartments, consumption: none, totalMinor: 1000, measuredPct: 0 });
    assert.equal(plan.total, 1000n);
  });
  it('isi: olcum payi %100 ise alan tabani yok (areaBasis null)', () => {
    const plan = buildMeterPlan({ method: 'heat', apartments, consumption, totalMinor: 1000, measuredPct: 100 });
    assert.equal(plan.areaBasis, null);
    assert.equal(plan.total, 1000n);
  });
  it('isi: kurus kalani esit payda da toplam birebir (3 daireye 100 kurus)', () => {
    const plan = buildMeterPlan({ method: 'heat', apartments, consumption: new Map([[1, 1n], [2, 1n], [3, 1n]]), totalMinor: 100, measuredPct: 0 });
    assert.equal(plan.total, 100n);
    assert.deepEqual(plan.lines.map((l) => l.amount), [34n, 33n, 33n]);
  });
});

describe('isi plani (computeBillingPlan, sahte istemci): m2 yok, alan payi tabani YONETIMIN secimi (esit / arsa payi / kisi sayisi; varsayilan esit)', () => {
  const meterRow = (id, extra = {}) => ({
    meter_id: id, apartment_id: id, responsible_party: 'both', unit_label: String(id), block_name: 'A', has_tenant: false,
    land_share_numerator: null, land_share_denominator: null, person_count: null,
    opening: '0', opening_date: '2026-01-01', closing: String(id * 10), closing_date: '2026-02-01', ...extra,
  });
  // meters sorgusu satir dondurur; kural (heat.measured_share_pct) sorgusu satirsiz: varsayilan %70
  const fakeClient = (rows) => ({
    sql: [],
    async query(text) {
      this.sql.push(text);
      return /FROM meters m/.test(text) ? { rows } : { rows: [] };
    },
  });
  const input = { kind: 'heat', method: 'heat', from: '2026-01-01', to: '2026-02-01', totalMinor: 100000, unitPriceMinor: null };

  it('arsa payi yoksa alan payi esit dagitilir, area_basis=equal; area_missing / NO_CONSUMPTION yok', async () => {
    const client = fakeClient([meterRow(1), meterRow(2), meterRow(3)]);
    const plan = await computeBillingPlan(client, 1, input, { entryDate: '2026-02-05', lock: true });
    assert.equal(plan.params.area_basis, 'equal');
    assert.equal(plan.params.measured_pct, 70);
    assert.equal(plan.params.area_pct, 30);
    assert.deepEqual(plan.missing, []);
    assert.equal(plan.total, 100000n);
    // tuketim 10:20:30 (toplam 60): olcum 70000 -> 11667, 23333, 35000; alan payi 30000 esit -> 10000
    assert.deepEqual(plan.lines.map((l) => l.amount), [21667n, 33333n, 45000n]);
    assert.match(client.sql.find((t) => /FROM meters m/.test(t)), /a\.land_share_numerator, a\.land_share_denominator/);
    assert.doesNotMatch(client.sql.find((t) => /FROM meters m/.test(t)), /AS area/);
  });

  const shareRows = () => [
    meterRow(1, { land_share_numerator: 1, land_share_denominator: 6 }),
    meterRow(2, { land_share_numerator: 2, land_share_denominator: 6 }),
    meterRow(3, { land_share_numerator: 3, land_share_denominator: 6 }),
  ];

  it('arsa payi SECILIRSE area_basis=land_share ve plan ozeti esit paydakinden farklidir', async () => {
    const byShare = await computeBillingPlan(fakeClient(shareRows()), 1, { ...input, areaBasis: 'land_share' }, { entryDate: '2026-02-05', lock: true });
    const equal = await computeBillingPlan(fakeClient([meterRow(1), meterRow(2), meterRow(3)]), 1, input, { entryDate: '2026-02-05', lock: true });
    assert.equal(byShare.params.area_basis, 'land_share');
    // alan payi 30000 arsa payina gore: 5000, 10000, 15000 (+ olcum 11667, 23333, 35000)
    assert.deepEqual(byShare.lines.map((l) => l.amount), [16667n, 33333n, 50000n]);
    assert.notEqual(byShare.hash, equal.hash);
    assert.deepEqual(byShare.missing, []);
  });

  it('K5: arsa payi TUM dairelerde tanimli olsa bile taban secilmediyse esit dagitilir (kod arsa payina gecmez)', async () => {
    const plan = await computeBillingPlan(fakeClient(shareRows()), 1, input, { entryDate: '2026-02-05', lock: true });
    assert.equal(plan.params.area_basis, 'equal');
    assert.deepEqual(plan.lines.map((l) => l.amount), [21667n, 33333n, 45000n]);
  });

  it('arsa payi secildi ama tek dairenin arsa payi eksik: o daire eksik veri (area basis), esit paya DUSURULMEZ; kalanlar arsa payiyla dagitilir', async () => {
    const rows = [meterRow(1, { land_share_numerator: 1, land_share_denominator: 6 }), meterRow(2), meterRow(3, { land_share_numerator: 3, land_share_denominator: 6 })];
    const plan = await computeBillingPlan(fakeClient(rows), 1, { ...input, areaBasis: 'land_share' }, { entryDate: '2026-02-05', lock: true });
    assert.equal(plan.params.area_basis, 'land_share');
    assert.deepEqual(plan.missing, [{ apartment_id: 2, label: 'A - 2', reason: 'land_share_missing' }]);
    assert.deepEqual(plan.lines.map((l) => l.apartmentId), [1, 3]);
    assert.equal(plan.total, 100000n, 'toplam birebir: eksik dairenin payi kalanlara dagitilir (atlama karari yoneticide)');
  });

  it('kisi sayisi SECILIRSE yalniz o durumda kisi sayisi okunur; kayit yok / 0 olan daire eksik veri', async () => {
    const equalClient = fakeClient([meterRow(1), meterRow(2), meterRow(3)]);
    await computeBillingPlan(equalClient, 1, input, { entryDate: '2026-02-05', lock: true });
    assert.doesNotMatch(equalClient.sql.find((t) => /FROM meters m/.test(t)), /COUNT\(\*\)::INTEGER FROM apartment_residencies r/, 'esit tabanda kisi sayisi alt sorgusu yok');
    const rows = [meterRow(1, { person_count: 3 }), meterRow(2, { person_count: 0 }), meterRow(3, { person_count: 1 })];
    const client = fakeClient(rows);
    const plan = await computeBillingPlan(client, 1, { ...input, areaBasis: 'person_count' }, { entryDate: '2026-02-05', lock: true });
    assert.match(client.sql.find((t) => /FROM meters m/.test(t)), /apartment_residencies r WHERE r\.apartment_id = a\.id AND r\.is_current = TRUE/);
    assert.equal(plan.params.area_basis, 'person_count');
    assert.deepEqual(plan.missing, [{ apartment_id: 2, label: 'A - 2', reason: 'person_count_missing' }]);
    assert.deepEqual(plan.lines.map((l) => l.apartmentId), [1, 3]);
    assert.equal(plan.total, 100000n);
  });

  it('olcum payi %100 ise (alan payi yok) secilen tabanin verisi eksik olsa da eksik veri olusmaz ve taban parametrelere yazilmaz', async () => {
    const client = {
      sql: [],
      async query(text) {
        this.sql.push(text);
        if (/FROM meters m/.test(text)) return { rows: [meterRow(1), meterRow(2)] };
        if (/platform_rule_values/.test(text)) return { rows: [{ id: '1', site_code: null, value: 100, inherit: false, valid_from: '2026-01-01' }] };
        return { rows: [] };
      },
    };
    invalidateRuleCache();
    try {
      const plan = await computeBillingPlan(client, 1, { ...input, areaBasis: 'land_share' }, { entryDate: '2026-02-05', lock: true });
      assert.equal(plan.params.measured_pct, 100);
      assert.deepEqual(plan.missing, []);
      assert.equal('area_basis' in plan.params, false);
    } finally {
      invalidateRuleCache();
    }
  });

  it('olcum payi disindaki tum dairelerin tuketimi sifirsa olcum payi icin NO_CONSUMPTION (alan payiyla karismaz)', async () => {
    const zero = [meterRow(1, { closing: '0' }), meterRow(2, { closing: '0' })];
    await assert.rejects(() => computeBillingPlan(fakeClient(zero), 1, input, { entryDate: '2026-02-05', lock: true }), { code: 'NO_CONSUMPTION' });
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
    assert.equal(heat.areaBasis, 'equal', 'K5: taban verilmezse varsayilan ESIT (kod arsa payini kendiliginden secmez)');
    assert.equal(parseBillingInput(ok).areaBasis, null, 'isi payi disindaki yontemlerde alan payi tabani yok');
  });
  it('alan payi tabani (K5): esit / arsa payi / kisi sayisi; m2 ve bilinmeyen deger reddedilir; yalniz isi payi yonteminde verilebilir', () => {
    const heatBody = { kind: 'heat', method: 'heat', period_from: '2026-01-01', period_to: '2026-02-01', total_minor: 500000 };
    for (const basis of ['equal', 'land_share', 'person_count']) {
      assert.equal(parseBillingInput({ ...heatBody, area_basis: basis }).areaBasis, basis);
    }
    for (const bad of ['area', 'm2', 'gross', 'EQUAL', 5, true]) {
      assert.throws(() => parseBillingInput({ ...heatBody, area_basis: bad }), { code: 'INVALID_BODY' }, String(bad));
    }
    assert.throws(() => parseBillingInput({ ...ok, area_basis: 'land_share' }), { code: 'INVALID_BODY' });
    assert.equal(parseBillingInput({ ...heatBody, area_basis: null }).areaBasis, 'equal');
  });
  it('kayit icin onizleme bilgisi ve anahtar zorunlu', () => {
    const commit = parseBillingInput(
      { ...ok, idempotency_key: 'abcdefgh-1234', expected_total_minor: 100, expected_count: 2, expected_hash: 'x' },
      { commit: true },
    );
    assert.equal(commit.expected.count, 2);
  });
});
