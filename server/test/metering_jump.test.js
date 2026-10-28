// Sayac saha akisi (P1-6) ve sicrama uyarisi (P1-7, karar K12), DB'siz: medyan / esik hesabi (3 donemden az veri = uyari yok), kural kaydi,
// saha okumasi servisi (uyari, onay izi, yeniden cekim) sahte baglanti havuzuyla, saha listesi (blok, onceki okuma, taban).
// Gercek PostgreSQL denemesi: scripts/qa_platform_pg.mjs degil, kullanici denemesi (docs/PLATFORM_SAYAC.md).
import { describe, it, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import { PlatformError } from '../src/modules/errors.js';
import { RULES, invalidateRuleCache } from '../src/modules/platform_rules.js';
import {
  JUMP_DEFAULT_FACTOR,
  JUMP_HISTORY_READINGS,
  JUMP_PERIODS,
  JUMP_RULE_KEY,
  evaluateJump,
  jumpBaseline,
  jumpBaselineView,
  jumpDetailsView,
  medianMilli,
  siteJumpFactor,
} from '../src/modules/metering_jump.js';
import { addFieldReading, listFieldMeters } from '../src/modules/metering_field_service.js';
import { dateOnly } from '../src/modules/metering_service.js';
import { types } from 'pg';

const milli = (value) => BigInt(Math.round(value * 1000));
const NOW = new Date('2026-10-28T09:00:00Z');
const SITE = 1000000001;
const ACTOR = { userCode: 7, full_name: 'Görevli Kişi', role: 'STAFF' };

describe('medyan ve esik hesabi (saf)', () => {
  it('medyan: tek sayida ortadaki, cift sayida ortadaki ikisinin ortalamasi (asagi), bos liste null', () => {
    assert.equal(medianMilli([milli(9), milli(11), milli(10)]), milli(10));
    assert.equal(medianMilli([milli(1), milli(2), milli(3), milli(4)]), milli(2.5));
    assert.equal(medianMilli([5n, 6n]), 5n);
    assert.equal(medianMilli([]), null);
    assert.equal(medianMilli(undefined), null);
  });

  it('taban: son 3 donem = 4 okuma; medyan x K; yeni okumanin tabani en yeni okumadir', () => {
    // En yeniden eskiye: 130, 121, 110, 100 -> tuketimler 9, 11, 10 -> medyan 10
    const base = jumpBaseline([milli(130), milli(121), milli(110), milli(100)], 5);
    assert.equal(JUMP_PERIODS, 3);
    assert.equal(JUMP_HISTORY_READINGS, 4);
    assert.deepEqual(base, { previous: milli(130), median: milli(10), limit: milli(50), factor: 5 });
    // Eski okumalar (5.) tabani degistirmez: yalniz en yeni 4 okuma sayilir
    assert.deepEqual(jumpBaseline([milli(130), milli(121), milli(110), milli(100), milli(1)], 5), base);
  });

  it('3 donemden az veri varsa uyari YOK: 0-3 okuma (en cok 2 donem) taban vermez', () => {
    assert.equal(jumpBaseline([], 5), null);
    assert.equal(jumpBaseline([milli(10)], 5), null);
    assert.equal(jumpBaseline([milli(20), milli(10)], 5), null);
    assert.equal(jumpBaseline([milli(30), milli(20), milli(10)], 5), null, '3 okuma = 2 donem');
    assert.equal(evaluateJump(jumpBaseline([milli(30), milli(20), milli(10)], 5), milli(100000)), null);
    assert.equal(jumpBaseline(undefined, 5), null);
  });

  it('medyan 0 (olcek yok) ya da negatif donem tuketimi: taban yok; gecersiz K: taban yok', () => {
    assert.equal(jumpBaseline([milli(100), milli(100), milli(100), milli(100)], 5), null, 'uc donem de sifir');
    assert.equal(jumpBaseline([milli(105), milli(100), milli(100), milli(100)], 5), null, 'iki donem sifir -> medyan 0');
    assert.ok(jumpBaseline([milli(115), milli(105), milli(100), milli(100)], 5), 'medyan 5 > 0 (tuketimler 10, 5, 0)');
    assert.equal(jumpBaseline([milli(100), milli(110), milli(120), milli(130)], 5), null, 'azalan seri (negatif tuketim)');
    assert.equal(jumpBaseline([milli(130), milli(121), milli(110), milli(100)], 0), null);
    assert.equal(jumpBaseline([milli(130), milli(121), milli(110), milli(100)], 2.5), null);
  });

  it('esik "asarsa": esitlik uyari vermez, bir milli fazlasi verir; ondalikli deger tam hesaplanir', () => {
    const base = jumpBaseline([milli(130), milli(121), milli(110), milli(100)], 5);
    assert.equal(evaluateJump(base, milli(180)), null, 'tuketim 50 = esik');
    const over = evaluateJump(base, milli(180) + 1n);
    assert.equal(over.consumption, milli(50) + 1n);
    assert.equal(over.ratioPct, 500);
    assert.equal(evaluateJump(base, milli(131)), null);
    assert.equal(evaluateJump(base, milli(100)), null, 'onceki okumadan kucuk deger uyari degil (sira kurali ayri reddeder)');
    assert.equal(evaluateJump(null, milli(999)), null);
    const exact = evaluateJump(jumpBaseline([milli(1000.125), milli(999.1), milli(998.05), milli(997)], 3), milli(1010));
    // tuketimler 1.025, 1.05, 1.1 -> medyan 1.05; esik 3.15; yeni tuketim 9.875 > esik
    assert.equal(exact.median, 1050n);
    assert.equal(exact.limit, 3150n);
    assert.equal(exact.consumption, 9875n);
    assert.equal(exact.ratioPct, 940);
  });

  it('gorunumler: liste tabani ve 409 govdesi metin (3 ondalik), ham BigInt sizmaz', () => {
    const base = jumpBaseline([milli(130), milli(121), milli(110), milli(100)], 5);
    assert.deepEqual(jumpBaselineView(base), { median: '10.000', limit: '50.000', factor: 5 });
    assert.equal(jumpBaselineView(null), null);
    const details = evaluateJump(base, milli(181));
    assert.deepEqual(jumpDetailsView(details), { previous_value: '130.000', consumption: '51.000', median: '10.000', limit: '50.000', factor: 5 });
    assert.doesNotThrow(() => JSON.stringify(jumpDetailsView(details)));
  });
});

describe('DATE sutunu tarihi (sunucu saat dilimi Europe/Istanbul)', () => {
  it('pg DATE degerini yerel gece yarisi Date yapar; dateOnly AYNI gunu verir (toISOString bir gun geri kaydirirdi)', () => {
    const parse = types.getTypeParser(1082, 'text');
    for (const day of ['2026-10-20', '2026-01-01', '2026-12-31', '2026-03-29']) {
      assert.equal(dateOnly(parse(day)), day, day);
    }
    assert.equal(dateOnly('2026-10-20'), '2026-10-20');
    assert.equal(dateOnly('2026-10-20T00:00:00.000Z'), '2026-10-20');
    assert.equal(dateOnly(null), null);
    assert.equal(dateOnly(undefined), null);
    assert.equal(dateOnly(new Date('gecersiz')), null);
  });
});

describe('K kurali (site ayari)', () => {
  beforeEach(() => invalidateRuleCache());

  it('kayit defterinde: metering.jump_factor, varsayilan 5, 2..100, sitede degisebilir, birimi kat', () => {
    const rule = RULES[JUMP_RULE_KEY];
    assert.equal(rule.defaultValue, JUMP_DEFAULT_FACTOR);
    assert.equal(rule.defaultValue, 5);
    assert.equal(rule.min, 2);
    assert.equal(rule.max, 100);
    assert.equal(rule.siteOverridable, true);
    assert.equal(rule.unit, 'times');
    assert.equal(rule.group, 'metering');
  });

  const rulesDb = (rows) => ({ query: async () => ({ rows }) });
  const row = (value, site = null) => ({ id: '1', site_code: site === null ? null : String(site), value, inherit: false, valid_from: '2026-01-01' });

  it('site degeri -> platform degeri -> 5; sinir disi deger kirpilir; okunamazsa varsayilan', async () => {
    assert.equal(await siteJumpFactor(rulesDb([]), SITE), 5);
    invalidateRuleCache();
    assert.equal(await siteJumpFactor(rulesDb([row(8, SITE)]), SITE), 8);
    invalidateRuleCache();
    assert.equal(await siteJumpFactor(rulesDb([row(3)]), SITE), 3, 'platform degeri');
    invalidateRuleCache();
    assert.equal(await siteJumpFactor(rulesDb([row(9999, SITE)]), SITE), 100, 'ust sinira kirpilir');
    invalidateRuleCache();
    assert.equal(await siteJumpFactor({ query: async () => Promise.reject(new Error('db yok')) }, SITE), 5);
  });
});

// --- Sahte baglanti havuzu (SQL metnine gore) ------------------------------------------------------------------------

/** meters: [{ id, kind, is_active, ... }], readings: [{ id, meter_id, date, value }]. Yalnizca bu servisin gonderdigi SQL'ler taklit edilir. */
function fakePool({ meters = [{ id: 1, kind: 'water', is_active: true }], readings = [], billings = [], rules = [] } = {}) {
  const state = { readings: readings.map((r) => ({ ...r })), audits: [], statements: [], nextId: 500, released: 0, rolledBack: 0 };
  const val = (r) => (typeof r.value === 'number' ? r.value.toFixed(3) : String(r.value));
  const byMeterDate = (id, date) => state.readings.find((r) => r.meter_id === id && r.date === date);
  const ordered = (id, predicate) => state.readings.filter((r) => r.meter_id === id && predicate(r)).sort((a, b) => (a.date < b.date ? 1 : -1));
  const client = {
    async query(sql, params = []) {
      const text = String(sql).replace(/\s+/g, ' ').trim();
      state.statements.push(text);
      if (/^(BEGIN|COMMIT|SAVEPOINT|RELEASE)/.test(text)) return { rows: [] };
      if (/^ROLLBACK/.test(text)) {
        if (!/SAVEPOINT/.test(text)) state.rolledBack += 1;
        return { rows: [] };
      }
      if (/pg_advisory_xact_lock/.test(text)) return { rows: [] };
      if (/^SELECT id, kind, is_active FROM meters/.test(text)) {
        const found = meters.find((m) => m.id === params[0]);
        return { rows: found ? [found] : [] };
      }
      if (/FROM meter_readings WHERE meter_id = \$1 AND reading_date = \$2::DATE FOR UPDATE/.test(text)) {
        const found = byMeterDate(params[0], params[1]);
        return { rows: found ? [{ id: found.id, value: val(found) }] : [] };
      }
      if (/reading_date < \$2::DATE ORDER BY reading_date DESC LIMIT 1$/.test(text)) {
        const [first] = ordered(params[0], (r) => r.date < params[1]);
        return { rows: first ? [{ value: val(first) }] : [] };
      }
      if (/reading_date > \$2::DATE ORDER BY reading_date ASC LIMIT 1$/.test(text)) {
        const [last] = ordered(params[0], (r) => r.date > params[1]).reverse();
        return { rows: last ? [{ value: val(last) }] : [] };
      }
      if (/reading_date < \$2::DATE ORDER BY reading_date DESC LIMIT 4$/.test(text)) {
        return { rows: ordered(params[0], (r) => r.date < params[1]).slice(0, 4).map((r) => ({ value: val(r), reading_date: r.date })) };
      }
      if (/FROM meter_billings/.test(text)) {
        return { rows: billings.some((b) => b.kind === params[1] && b.period_to >= params[2]) ? [{ '?column?': 1 }] : [] };
      }
      if (/^INSERT INTO meter_readings/.test(text)) {
        state.nextId += 1;
        state.readings.push({ id: state.nextId, meter_id: params[1], date: params[2], value: params[3], source: 'manual', created_by: params[4] });
        return { rows: [{ id: state.nextId }] };
      }
      if (/^UPDATE meter_readings SET value/.test(text)) {
        const target = state.readings.find((r) => r.id === params[0]);
        target.value = params[1];
        target.created_by = params[2];
        return { rows: [] };
      }
      if (/^INSERT INTO audit_log/.test(text)) {
        state.audits.push({ action: params[3], siteCode: params[4], targetId: params[6], details: JSON.parse(params[7]) });
        return { rows: [] };
      }
      if (/FROM platform_rule_values/.test(text)) return { rows: rules };
      throw new Error(`sahte havuz: beklenmeyen SQL: ${text.slice(0, 120)}`);
    },
    release() {
      state.released += 1;
    },
  };
  return { state, connect: async () => client, query: client.query };
}

/** Bir sayacin dort aylik okumasi: tuketimler 10, 11, 9 (medyan 10); en yeni 2026-10-20 = 130. */
const FOUR_MONTHS = [
  { id: 1, meter_id: 1, date: '2026-07-20', value: 100 },
  { id: 2, meter_id: 1, date: '2026-08-20', value: 110 },
  { id: 3, meter_id: 1, date: '2026-09-20', value: 121 },
  { id: 4, meter_id: 1, date: '2026-10-20', value: 130 },
];

const call = (db, body, extra = {}) => addFieldReading({ siteCode: SITE, rawMeterId: '1', actor: ACTOR, body, now: NOW, db, ...extra });
const failure = async (promise) => {
  try {
    await promise;
  } catch (error) {
    return error;
  }
  return assert.fail('hata bekleniyordu');
};

describe('saha okumasi: sicrama uyarisi ve onay izi', () => {
  beforeEach(() => invalidateRuleCache());

  it('ESKI istemci (confirm_jump yok): hic denetim yapilmaz, olagan disi okuma da eskisi gibi kaydolur', async () => {
    const db = fakePool({ readings: FOUR_MONTHS });
    const result = await call(db, { date: '2026-10-28', value: '5000' });
    assert.equal(result.replayed, false);
    assert.equal(result.jump_confirmed, false);
    assert.equal(db.state.readings.length, 5);
    assert.deepEqual(db.state.audits.map((a) => a.action), ['metering.reading.added']);
    assert.ok(!db.state.statements.some((s) => /LIMIT 4$/.test(s)), 'gecmis okuma sorgusu bile gonderilmez');
  });

  it('yeni istemci, esik altinda: uyarisiz kaydolur, onay izi yazilmaz', async () => {
    const db = fakePool({ readings: FOUR_MONTHS });
    const result = await call(db, { date: '2026-10-28', value: '180', confirm_jump: false });
    assert.equal(result.reading.value, '180.000');
    assert.equal(result.jump_confirmed, false);
    assert.deepEqual(db.state.audits.map((a) => a.action), ['metering.reading.added']);
  });

  it('yeni istemci, esik ustu: 409 READING_JUMP + tuketim / medyan / esik; hicbir sey yazilmaz', async () => {
    const db = fakePool({ readings: FOUR_MONTHS });
    const error = await failure(call(db, { date: '2026-10-28', value: '181', confirm_jump: false }));
    assert.ok(error instanceof PlatformError);
    assert.equal(error.statusCode, 409);
    assert.equal(error.code, 'READING_JUMP');
    assert.deepEqual(error.extra.jump, { previous_value: '130.000', consumption: '51.000', median: '10.000', limit: '50.000', factor: 5 });
    assert.match(error.message, /Olağan dışı tüketim/);
    assert.equal(db.state.readings.length, 4);
    assert.equal(db.state.audits.length, 0);
    assert.equal(db.state.rolledBack, 1, 'islem geri alindi');
    assert.equal(db.state.released, 1);
  });

  it('onayla gec: confirm_jump:true kaydeder ve ONAY IZI yazar (K ve medyana orani; okunan DEGER yok)', async () => {
    const db = fakePool({ readings: FOUR_MONTHS });
    const result = await call(db, { date: '2026-10-28', value: '181', confirm_jump: true });
    assert.equal(result.jump_confirmed, true);
    assert.equal(db.state.readings.length, 5);
    assert.deepEqual(db.state.audits.map((a) => a.action), ['metering.reading.added', 'metering.reading.jump_confirmed']);
    const trail = db.state.audits[1];
    assert.deepEqual(trail.details, { meter_id: 1, factor: 5, ratio_pct: 510 });
    assert.equal(trail.siteCode, SITE);
    assert.equal(trail.targetId, String(result.reading.id));
    assert.ok(!JSON.stringify(db.state.audits).includes('181'), 'denetim kaydinda okuma degeri yok');
  });

  it('onay (confirm_jump:true) ama sicrama yok: onay izi yazilmaz', async () => {
    const db = fakePool({ readings: FOUR_MONTHS });
    const result = await call(db, { date: '2026-10-28', value: '140', confirm_jump: true });
    assert.equal(result.jump_confirmed, false);
    assert.deepEqual(db.state.audits.map((a) => a.action), ['metering.reading.added']);
  });

  it('3 donemden az veri (3 okuma): olagan disi degerde bile uyari YOK', async () => {
    const db = fakePool({ readings: FOUR_MONTHS.slice(1) });
    const result = await call(db, { date: '2026-10-28', value: '99999', confirm_jump: false });
    assert.equal(result.replayed, false);
    assert.equal(db.state.readings.length, 4);
  });

  it('medyan 0 (sahipsiz daire): olcek yok, uyari YOK', async () => {
    const flat = [100, 100, 100, 105].map((value, i) => ({ id: i + 1, meter_id: 1, date: `2026-0${7 + i}-20`, value }));
    const db = fakePool({ readings: flat });
    const result = await call(db, { date: '2026-10-28', value: '500', confirm_jump: false });
    assert.equal(result.replayed, false);
  });

  it('K site ayarindan gelir: site 3 kat -> 31 tuketim uyarir; ayni deger varsayilan 5 katta uyarmaz', async () => {
    const strict = fakePool({ readings: FOUR_MONTHS, rules: [{ id: '1', site_code: String(SITE), value: 3, inherit: false, valid_from: '2026-01-01' }] });
    const error = await failure(call(strict, { date: '2026-10-28', value: '161', confirm_jump: false }));
    assert.equal(error.code, 'READING_JUMP');
    assert.equal(error.extra.jump.factor, 3);
    assert.equal(error.extra.jump.limit, '30.000');
    invalidateRuleCache();
    const normal = fakePool({ readings: FOUR_MONTHS });
    assert.equal((await call(normal, { date: '2026-10-28', value: '161', confirm_jump: false })).replayed, false);
  });

  it('tekrar gonderim (ayni sayac + tarih + ayni deger): sessizce ayni kayit; uyari, denetim ve yazma yok', async () => {
    const db = fakePool({ readings: [...FOUR_MONTHS, { id: 9, meter_id: 1, date: '2026-10-28', value: 500 }] });
    const result = await call(db, { date: '2026-10-28', value: '500', confirm_jump: false });
    assert.equal(result.replayed, true);
    assert.equal(result.reading.id, 9);
    assert.equal(db.state.audits.length, 0);
    assert.equal(db.state.readings.length, 5);
  });

  it('sira kurali uyariyi onceler: onceki okumadan kucuk deger READING_OUT_OF_ORDER', async () => {
    const db = fakePool({ readings: FOUR_MONTHS });
    const error = await failure(call(db, { date: '2026-10-28', value: '120', confirm_jump: false }));
    assert.equal(error.code, 'READING_OUT_OF_ORDER');
  });

  it('girdi dogrulama: confirm_jump / replace boolean olmali; gelecek tarih, bos deger, sayac yok, pasif sayac', async () => {
    const db = fakePool({ readings: FOUR_MONTHS });
    assert.equal((await failure(call(db, { date: '2026-10-28', value: '140', confirm_jump: 'evet' }))).code, 'INVALID_BODY');
    assert.equal((await failure(call(db, { date: '2026-10-28', value: '140', replace: 1 }))).code, 'INVALID_BODY');
    assert.equal((await failure(call(db, { date: '2026-10-29', value: '140' }))).code, 'INVALID_BODY');
    assert.equal((await failure(call(db, { date: '2026-10-28', value: 'abc' }))).code, 'INVALID_BODY');
    assert.equal((await failure(addFieldReading({ siteCode: SITE, rawMeterId: '77', actor: ACTOR, body: { date: '2026-10-28', value: '140' }, now: NOW, db }))).code, 'METER_NOT_FOUND');
    assert.equal((await failure(addFieldReading({ siteCode: SITE, rawMeterId: 'x', actor: ACTOR, body: { date: '2026-10-28', value: '140' }, now: NOW, db }))).code, 'METER_NOT_FOUND');
    const inactive = fakePool({ meters: [{ id: 1, kind: 'water', is_active: false }] });
    assert.equal((await failure(call(inactive, { date: '2026-10-28', value: '140' }))).code, 'METER_INACTIVE');
  });
});

describe('saha okumasi: yeniden cekim (replace)', () => {
  beforeEach(() => invalidateRuleCache());
  const TODAY_READING = { id: 9, meter_id: 1, date: '2026-10-28', value: 500 };

  it('replace olmadan farkli deger: 409 READING_EXISTS (eski davranis)', async () => {
    const db = fakePool({ readings: [...FOUR_MONTHS, TODAY_READING] });
    assert.equal((await failure(call(db, { date: '2026-10-28', value: '140' }))).code, 'READING_EXISTS');
  });

  it('replace:true: bugunku okumanin degeri degisir (ayni id), denetim "retaken", deger yok', async () => {
    const db = fakePool({ readings: [...FOUR_MONTHS, TODAY_READING] });
    const result = await call(db, { date: '2026-10-28', value: '140', replace: true });
    assert.equal(result.retaken, true);
    assert.equal(result.replayed, false);
    assert.equal(result.reading.id, 9);
    assert.equal(db.state.readings.find((r) => r.id === 9).value, '140.000');
    assert.equal(db.state.readings.length, 5, 'yeni satir eklenmez');
    assert.deepEqual(db.state.audits.map((a) => a.action), ['metering.reading.retaken']);
    assert.deepEqual(db.state.audits[0].details, { meter_id: 1, source: 'field' });
  });

  it('replace:true ama o gun okuma yok: normal ekleme gibi calisir (kuyruk sirasi / silinmis kayit guvenli)', async () => {
    const db = fakePool({ readings: FOUR_MONTHS });
    const result = await call(db, { date: '2026-10-28', value: '140', replace: true });
    assert.equal(result.retaken, false);
    assert.equal(db.state.readings.length, 5);
    assert.deepEqual(db.state.audits.map((a) => a.action), ['metering.reading.added']);
  });

  it('yeniden cekimde sicrama tabani DEGISEN okumayi disarida birakir: onceki okuma 10-20, bugunku 500 ise esik 130 uzerinden', async () => {
    const db = fakePool({ readings: [...FOUR_MONTHS, TODAY_READING] });
    const error = await failure(call(db, { date: '2026-10-28', value: '300', replace: true, confirm_jump: false }));
    assert.equal(error.code, 'READING_JUMP');
    assert.equal(error.extra.jump.previous_value, '130.000');
    assert.equal(error.extra.jump.consumption, '170.000');
    const ok = await call(db, { date: '2026-10-28', value: '300', replace: true, confirm_jump: true });
    assert.equal(ok.jump_confirmed, true);
    assert.deepEqual(db.state.audits.map((a) => a.action), ['metering.reading.retaken', 'metering.reading.jump_confirmed']);
  });

  it('yeniden cekimde de sira kurali gecerli: onceki okumadan kucuk deger reddedilir, kayit degismez', async () => {
    const db = fakePool({ readings: [...FOUR_MONTHS, TODAY_READING] });
    assert.equal((await failure(call(db, { date: '2026-10-28', value: '120', replace: true }))).code, 'READING_OUT_OF_ORDER');
    assert.equal(db.state.readings.find((r) => r.id === 9).value, 500);
  });

  it('yalniz bugun ve dun: iki gun onceki okuma yeniden cekilemez (RETAKE_WINDOW); dun serbest', async () => {
    const old = fakePool({ readings: [...FOUR_MONTHS, { id: 9, meter_id: 1, date: '2026-10-26', value: 135 }] });
    assert.equal((await failure(call(old, { date: '2026-10-26', value: '136', replace: true }))).code, 'RETAKE_WINDOW');
    const yesterday = fakePool({ readings: [...FOUR_MONTHS, { id: 9, meter_id: 1, date: '2026-10-27', value: 135 }] });
    assert.equal((await call(yesterday, { date: '2026-10-27', value: '136', replace: true })).retaken, true);
  });

  it('faturalandirilmis donemdeki okuma degistirilemez (READING_RETAKE_LOCKED); baska turdeki fatura engellemez', async () => {
    const billed = fakePool({ readings: [...FOUR_MONTHS, TODAY_READING], billings: [{ kind: 'water', period_to: '2026-10-28' }] });
    assert.equal((await failure(call(billed, { date: '2026-10-28', value: '140', replace: true }))).code, 'READING_RETAKE_LOCKED');
    assert.equal(billed.state.readings.find((r) => r.id === 9).value, 500);
    const other = fakePool({ readings: [...FOUR_MONTHS, TODAY_READING], billings: [{ kind: 'electricity', period_to: '2026-10-28' }] });
    assert.equal((await call(other, { date: '2026-10-28', value: '140', replace: true })).retaken, true);
  });
});

describe('saha listesi: blok, onceki okuma, sicrama tabani', () => {
  beforeEach(() => invalidateRuleCache());

  /** pool.query: sayac listesi + gecmis okumalar + kural satirlari. */
  function listDb({ meters, history, rules = [] }) {
    const seen = [];
    return {
      seen,
      query: async (sql, params) => {
        const text = String(sql).replace(/\s+/g, ' ').trim();
        seen.push({ text, params });
        if (/FROM platform_rule_values/.test(text)) return { rows: rules };
        if (/CROSS JOIN LATERAL/.test(text)) return { rows: history };
        if (/FROM meters m INNER JOIN apartments/.test(text)) return { rows: meters };
        throw new Error(`beklenmeyen SQL: ${text.slice(0, 100)}`);
      },
    };
  }

  const meterRow = (id, block, unit, extra = {}) => ({
    id,
    kind: 'water',
    serial_no: `S${id}`,
    is_active: true,
    apartment_id: id * 10,
    created_at: new Date('2026-01-01T00:00:00Z'),
    unit_label: unit,
    block_name: block,
    last_value: null,
    last_date: null,
    ...extra,
  });

  it('blok + daire alanlari, onceki okuma, taban (yalniz 4 okumasi olan sayacta) ve ust duzey jump_factor / date', async () => {
    const db = listDb({
      meters: [meterRow(1, 'A Blok', '1', { last_value: '130.000', last_date: '2026-10-20' }), meterRow(2, 'A Blok', '2'), meterRow(3, 'B Blok', '1', { last_value: '12.000', last_date: '2026-10-20' })],
      history: [
        { meter_id: 1, value: '130.000', reading_date: new Date('2026-10-20T00:00:00Z') },
        { meter_id: 1, value: '121.000', reading_date: '2026-09-20' },
        { meter_id: 1, value: '110.000', reading_date: '2026-08-20' },
        { meter_id: 1, value: '100.000', reading_date: '2026-07-20' },
        { meter_id: 3, value: '12.000', reading_date: '2026-10-20' },
        { meter_id: 3, value: '10.000', reading_date: '2026-09-20' },
      ],
    });
    const out = await listFieldMeters(SITE, { kind: 'water' }, { now: NOW, db });
    assert.equal(out.jump_factor, 5);
    assert.equal(out.date, '2026-10-28');
    assert.deepEqual(out.items.map((m) => [m.id, m.block_name, m.unit_label, m.apartment_label]), [
      [1, 'A Blok', '1', 'A Blok - 1'],
      [2, 'A Blok', '2', 'A Blok - 2'],
      [3, 'B Blok', '1', 'B Blok - 1'],
    ]);
    assert.deepEqual(out.items[0].previous_reading, { value: '130.000', date: '2026-10-20' });
    assert.deepEqual(out.items[0].jump, { median: '10.000', limit: '50.000', factor: 5 });
    assert.equal(out.items[1].previous_reading, null);
    assert.equal(out.items[1].jump, null);
    assert.deepEqual(out.items[2].previous_reading, { value: '12.000', date: '2026-10-20' });
    assert.equal(out.items[2].jump, null, '2 okuma = tek donem: taban yok');
    assert.deepEqual(out.items[0].last_reading, { value: '130.000', date: '2026-10-20' }, 'eski alanlar korunur');
    const historyCall = db.seen.find((s) => /CROSS JOIN LATERAL/.test(s.text));
    assert.deepEqual(historyCall.params, [SITE, '2026-10-28', 'water'], 'tarih sorgusu: istemcinin tarihi yoksa Istanbul bugunu');
  });

  it('date verilirse taban o tarihten ONCEKI okumalardan hesaplanir; site K degeri esige yansir; gecersiz tarih 400', async () => {
    const db = listDb({
      meters: [meterRow(1, 'A Blok', '1')],
      history: [
        { meter_id: 1, value: '130.000', reading_date: '2026-10-20' },
        { meter_id: 1, value: '121.000', reading_date: '2026-09-20' },
        { meter_id: 1, value: '110.000', reading_date: '2026-08-20' },
        { meter_id: 1, value: '100.000', reading_date: '2026-07-20' },
      ],
      rules: [{ id: '1', site_code: String(SITE), value: 8, inherit: false, valid_from: '2026-01-01' }],
    });
    const out = await listFieldMeters(SITE, { date: '2026-10-25' }, { now: NOW, db });
    assert.equal(out.date, '2026-10-25');
    assert.equal(out.jump_factor, 8);
    assert.equal(out.items[0].jump.limit, '80.000');
    assert.deepEqual(db.seen.find((s) => /CROSS JOIN LATERAL/.test(s.text)).params, [SITE, '2026-10-25', null]);
    const error = await failure(listFieldMeters(SITE, { date: 'dun' }, { now: NOW, db }));
    assert.equal(error.code, 'INVALID_BODY');
    const kind = await failure(listFieldMeters(SITE, { kind: 'gaz' }, { now: NOW, db }));
    assert.equal(kind.code, 'INVALID_BODY');
  });
});
