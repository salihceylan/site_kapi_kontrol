// Sayac tarifesi (116), DB'siz: migration <-> DDL birebir esitlik, tarife gecerliligi (yeni tarife eskiyi kapatir, sira bozulamaz),
// onizleme = tahakkuk (ayni plan ozeti; tarife degisirse ozet degisir), tarife yoksa TARIFF_MISSING, yetki baglantisi. Gercek PostgreSQL denemesi kullanicidadir.
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { DEFAULT_MIGRATIONS_DIR, findUnsafeStatements } from '../scripts/migrate.js';
import { METER_TARIFF_DDL } from '../src/modules/metering_tariff_schema.js';
import { createTariff } from '../src/modules/metering_tariff.js';
import { computeBillingPlan, parseBillingInput } from '../src/modules/metering_billing.js';

const here = path.dirname(fileURLToPath(import.meta.url));
const MIGRATION = readFileSync(path.join(DEFAULT_MIGRATIONS_DIR, '117_meter_tariffs.sql'), 'utf8').replace(/\r\n/g, '\n');
const ROUTES = readFileSync(path.join(here, '..', 'src', 'modules', 'metering_routes.js'), 'utf8');
const DB_SOURCE = readFileSync(path.join(here, '..', 'src', 'db.js'), 'utf8');
const norm = (text) => text.replace(/--.*$/gm, ' ').replace(/\s+/g, ' ').replace(/ ;/g, ';').trim();

describe('116 sema', () => {
  it('migration, METER_TARIFF_DDL ile birebir ayni ve guvenli; db.js baglar', () => {
    assert.equal(norm(MIGRATION), norm(Object.values(METER_TARIFF_DDL).map((s) => `${s};`).join('\n')));
    assert.deepEqual(findUnsafeStatements(MIGRATION), []);
    assert.doesNotMatch(MIGRATION, /\b(DROP|TRUNCATE)\b|\bDELETE\s+FROM/i);
    assert.match(DB_SOURCE, /await ensureMeterTariffSchema\(client\)/);
  });
});

describe('tarife yetkisi', () => {
  it('yazma ucu write:true (kurul / sakin / gorevli yazamaz), okuma ucu salt okur; ikisi de modul + site denetimli handler', () => {
    assert.match(ROUTES, /meter-tariffs`,\s*authRequired,\s*meteringWriteLimiter,\s*handler\(\{[^}]*write: true/);
    assert.match(ROUTES, /meteringRouter\.get\(\s*`\$\{BASE\}\/meter-tariffs`,\s*authRequired,\s*meteringReadLimiter,\s*handler\(\{ context: 'meter_tariffs_list', fallback: '[^']*' \}/);
  });
});

/** Sahte havuz: tarife tablosu bellekte; UPDATE / INSERT / SELECT ifadelerini taklit eder. */
function fakePool(initial = []) {
  const rows = initial.map((r, i) => ({ id: i + 1, ...r }));
  const log = [];
  const client = {
    async query(text, params = []) {
      log.push(text.trim().split(/\s+/).slice(0, 3).join(' '));
      if (/^\s*(BEGIN|COMMIT|ROLLBACK|SAVEPOINT|RELEASE)/i.test(text) || /pg_advisory_xact_lock/.test(text) || /INSERT INTO audit_log/.test(text)) return { rows: [] };
      if (/FOR UPDATE/.test(text)) {
        const last = rows.filter((r) => r.kind === params[1]).sort((a, b) => (a.valid_from < b.valid_from ? 1 : -1))[0];
        return { rows: last ? [{ id: last.id, valid_from: last.valid_from }] : [] };
      }
      if (/^\s*UPDATE meter_tariffs/.test(text)) {
        const target = rows.find((r) => r.id === params[0] && !r.valid_to);
        if (target) target.valid_to = params[1];
        return { rows: [] };
      }
      if (/^\s*INSERT INTO meter_tariffs/.test(text)) {
        const id = rows.length + 1;
        rows.push({ id, kind: params[1], unit_price_minor: params[2], valid_from: params[3], valid_to: null });
        return { rows: [{ id }] };
      }
      if (/FROM meter_tariffs\s+WHERE id = \$1/.test(text)) {
        const r = rows.find((x) => x.id === params[0]);
        return { rows: [{ ...r, unit_price_minor: String(r.unit_price_minor) }] };
      }
      return { rows: [] };
    },
    release() {},
  };
  return { rows, log, async connect() { return client; } };
}

describe('tarife gecerliligi', () => {
  const actor = { user_code: 7, role: 'ADMIN' };
  it('yeni tarife turdeki acik tarifeyi kendi baslangicinda kapatir; baska tur etkilenmez', async () => {
    const db = fakePool([
      { kind: 'water', unit_price_minor: 4000, valid_from: '2026-01-01', valid_to: null },
      { kind: 'electricity', unit_price_minor: 900, valid_from: '2026-01-01', valid_to: null },
    ]);
    const out = await createTariff({ siteCode: 1, actor, body: { kind: 'water', unit_price_minor: 5000, valid_from: '2026-07-01' }, db });
    assert.equal(out.tariff.valid_from, '2026-07-01');
    assert.equal(out.tariff.unit_price_minor, 5000);
    assert.equal(db.rows[0].valid_to, '2026-07-01', 'eski su tarifesi yeni baslangicta kapandi');
    assert.equal(db.rows[1].valid_to, null, 'elektrik tarifesi etkilenmedi');
  });

  it('son tarifenin baslangicindan once ya da ayni gun baslayan tarife reddedilir (409); fiyat tamsayi kurus olmali (400)', async () => {
    const db = fakePool([{ kind: 'water', unit_price_minor: 4000, valid_from: '2026-07-01', valid_to: null }]);
    await assert.rejects(createTariff({ siteCode: 1, actor, body: { kind: 'water', unit_price_minor: 5000, valid_from: '2026-07-01' }, db }), { code: 'TARIFF_OUT_OF_ORDER' });
    await assert.rejects(createTariff({ siteCode: 1, actor, body: { kind: 'water', unit_price_minor: 5000, valid_from: '2026-03-01' }, db }), { code: 'TARIFF_OUT_OF_ORDER' });
    await assert.rejects(createTariff({ siteCode: 1, actor, body: { kind: 'water', unit_price_minor: 45.5, valid_from: '2026-09-01' }, db }), { code: 'INVALID_BODY' });
    await assert.rejects(createTariff({ siteCode: 1, actor, body: { kind: 'gaz', unit_price_minor: 4500, valid_from: '2026-09-01' }, db }), { code: 'INVALID_BODY' });
    assert.equal(db.rows.length, 1, 'reddedilen tarife yazilmadi');
    assert.equal(db.rows[0].valid_to, null);
  });
});

describe('onizleme = tahakkuk (tarifeli birim fiyat)', () => {
  const meterRow = (id, closing) => ({
    meter_id: id, apartment_id: id, responsible_party: 'both', unit_label: String(id), block_name: 'A', has_tenant: false,
    land_share_numerator: null, land_share_denominator: null, person_count: null,
    opening: '0', opening_date: '2026-09-01', closing, closing_date: '2026-10-01',
  });
  const clientWith = (tariffRows) => ({
    sql: [],
    async query(text) {
      this.sql.push(text);
      if (/FROM meters m/.test(text)) return { rows: [meterRow(1, '10'), meterRow(2, '25.500')] };
      if (/FROM meter_tariffs/.test(text)) return { rows: tariffRows };
      return { rows: [] };
    },
  });
  const tariff = (price, from = '2026-01-01') => ({ id: '3', kind: 'water', unit_price_minor: String(price), valid_from: from, valid_to: null });
  const input = parseBillingInput({ kind: 'water', method: 'unit_price', period_from: '2026-09-01', period_to: '2026-10-01' });

  it('fiyat istekte yoksa tarifeden okunur; tutar = tuketim x tarife; tarife params ve onizlemeye yazilir', async () => {
    assert.equal(input.unitPriceMinor, null);
    const plan = await computeBillingPlan(clientWith([tariff(4500)]), 1, input, { entryDate: '2026-10-02', lock: true });
    assert.deepEqual(plan.lines.map((l) => l.amount), [45000n, 114750n]);
    assert.equal(plan.total, 159750n);
    assert.deepEqual(plan.params, { tariff_id: 3, tariff_valid_from: '2026-01-01', unit_price_minor: 4500 });
    assert.deepEqual(plan.tariff, { id: 3, unit_price_minor: 4500, valid_from: '2026-01-01', mid_period: false });
  });

  it('onizleme ve kayit ayni hesabi kullanir: ayni girdi ayni ozet; tarife degisirse ozet degisir (PREVIEW_STALE yolu); donem icinde baslayan tarife mid_period', async () => {
    const a = await computeBillingPlan(clientWith([tariff(4500)]), 1, input, { entryDate: '2026-10-02' });
    const b = await computeBillingPlan(clientWith([tariff(4500)]), 1, input, { entryDate: '2026-10-02', lock: true });
    assert.equal(a.hash, b.hash);
    assert.equal(a.total, b.total);
    const changed = await computeBillingPlan(clientWith([tariff(4600, '2026-09-15')]), 1, input, { entryDate: '2026-10-02' });
    assert.notEqual(changed.hash, a.hash);
    assert.equal(changed.tariff.mid_period, true);
  });

  it('tarife yoksa 409 TARIFF_MISSING; acik fiyat verilirse tarife sorgulanmaz (eski davranis)', async () => {
    await assert.rejects(computeBillingPlan(clientWith([]), 1, input, { entryDate: '2026-10-02' }), { code: 'TARIFF_MISSING' });
    const explicit = parseBillingInput({ kind: 'water', method: 'unit_price', period_from: '2026-09-01', period_to: '2026-10-01', unit_price_minor: 4000 });
    const client = clientWith([]);
    const plan = await computeBillingPlan(client, 1, explicit, { entryDate: '2026-10-02' });
    assert.equal(plan.tariff, null);
    assert.deepEqual(plan.params, { unit_price_minor: 4000 });
    assert.equal(client.sql.some((t) => /FROM meter_tariffs/.test(t)), false);
  });

  it('tarife sorgusu donem sonunda gecerli olani secer ([valid_from, valid_to))', async () => {
    const client = clientWith([tariff(4500)]);
    await computeBillingPlan(client, 1, input, { entryDate: '2026-10-02' });
    const sql = client.sql.find((t) => /FROM meter_tariffs/.test(t));
    assert.match(sql, /valid_from <= \$3::DATE AND \(valid_to IS NULL OR valid_to > \$3::DATE\)/);
  });
});
