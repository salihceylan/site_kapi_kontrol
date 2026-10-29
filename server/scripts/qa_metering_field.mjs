// Sayac saha akisi (P1-6) ve sicrama uyarisi (P1-7, karar K12) icin GERCEK PostgreSQL denemesi (docs/PLATFORM_SAYAC.md "Saha akisi ve sicrama uyarisi").
// Kapsam: saha listesi (blok, onceki okuma, sicrama tabani, DATE saat dilimi), sicrama uyarisi + onay izi, K site ayari (kurallar tablosu), yeniden cekim
// (ayni kayit, sira kurali, bugun / dun penceresi, faturalandirilmis donem kilidi), eski istemci (confirm_jump yok), tekrar gonderim.
//
//   ALLOW_DEV_SCRIPTS=1 DB_HOST=127.0.0.1 DB_PORT=55432 DB_NAME=<migration uygulanmis bos veritabani> DB_USER=postgres DB_PASSWORD=x node scripts/qa_metering_field.mjs
//
// Kendi gecici sitesini olusturur ve sonunda siler (CASCADE); baska veriye dokunmaz. CANLI veritabanina KARSI CALISTIRMAYIN. `npm test` icinde degildir.
import './_dev_guard.js';
import { pool } from '../src/db.js';
import { addFieldReading, listFieldMeters } from '../src/modules/metering_field_service.js';
import { invalidateRuleCache } from '../src/modules/platform_rules.js';

const NOW = new Date('2026-10-28T09:00:00Z');
const ACTOR = { role: 'STAFF', full_name: 'Gorevli Deneme' };
let failures = 0;
const check = (name, ok, extra) => {
  if (!ok) failures += 1;
  console.log(`${ok ? 'OK  ' : 'FAIL'} ${name}${ok ? '' : ` -> ${JSON.stringify(extra)}`}`);
};
const attempt = async (promise) => {
  try {
    return { value: await promise };
  } catch (error) {
    return { error };
  }
};

let siteCode = null;
try {
  const site = await pool.query(
    `INSERT INTO sites (name, mqtt_site_id) VALUES ('Sayac QA ' || to_char(clock_timestamp(), 'HH24MISSUS'), generate_unique_mqtt_site_id()) RETURNING site_code`,
  );
  siteCode = Number(site.rows[0].site_code);
  const block = async (name, order) =>
    (await pool.query(`INSERT INTO site_blocks (site_code, block_name, sort_order) VALUES ($1, $2, $3) RETURNING id`, [siteCode, name, order])).rows[0].id;
  const apartment = async (blockId, unit, order) =>
    (await pool.query(`INSERT INTO apartments (site_code, block_id, unit_label, sort_order) VALUES ($1, $2, $3, $4) RETURNING id`, [siteCode, blockId, unit, order])).rows[0].id;
  const meter = async (apartmentId, serial) =>
    Number((await pool.query(`INSERT INTO meters (site_code, apartment_id, kind, serial_no) VALUES ($1, $2, 'water', $3) RETURNING id`, [siteCode, apartmentId, serial])).rows[0].id);
  const blockA = await block('A Blok', 1);
  const blockB = await block('B Blok', 2);
  const m1 = await meter(await apartment(blockA, '1', 1), 'W1');
  const m2 = await meter(await apartment(blockA, '2', 2), 'W2');
  const m3 = await meter(await apartment(blockB, '1', 1), 'W3');
  const reading = (m, date, value) =>
    pool.query(`INSERT INTO meter_readings (site_code, meter_id, reading_date, value) VALUES ($1, $2, $3::DATE, $4::NUMERIC)`, [siteCode, m, date, value]);
  for (const [date, value] of [['2026-07-20', 100], ['2026-08-20', 110], ['2026-09-20', 121], ['2026-10-20', 130]]) await reading(m1, date, value);
  await reading(m2, '2026-09-20', 30);
  await reading(m2, '2026-10-20', 40);
  const call = (meterId, body) => addFieldReading({ siteCode, rawMeterId: String(meterId), actor: ACTOR, body, now: NOW });
  const audits = async () => (await pool.query(`SELECT action, details FROM audit_log WHERE site_code = $1 ORDER BY id`, [siteCode])).rows;
  const readingValue = async (id) => (await pool.query(`SELECT value::TEXT AS value FROM meter_readings WHERE id = $1`, [id])).rows[0].value;

  // 1) Liste
  let list = await listFieldMeters(siteCode, { kind: 'water', date: '2026-10-28' }, { now: NOW });
  const item = (id) => list.items.find((x) => x.id === id);
  check('liste: 3 sayac, daire sirasiyla', list.items.map((x) => x.id).join() === [m1, m2, m3].join(), list.items.map((x) => x.id));
  check('liste: blok / daire alanlari', item(m1).block_name === 'A Blok' && item(m1).unit_label === '1' && item(m3).block_name === 'B Blok', [item(m1).block_name, item(m3).block_name]);
  check(
    'liste: m1 onceki okuma 130 (2026-10-20), taban medyan 10 / esik 50 / K 5 (DATE saat dilimi kaymaz)',
    JSON.stringify(item(m1).previous_reading) === '{"value":"130.000","date":"2026-10-20"}' && JSON.stringify(item(m1).jump) === '{"median":"10.000","limit":"50.000","factor":5}',
    [item(m1).previous_reading, item(m1).jump],
  );
  check('liste: last_reading.date de kaymaz (2026-10-20)', item(m1).last_reading.date === '2026-10-20', item(m1).last_reading);
  check('liste: m2 (2 okuma) tabansiz, m3 (okumasiz) onceki okuma yok', item(m2).jump === null && item(m2).previous_reading.value === '40.000' && item(m3).previous_reading === null && item(m3).jump === null, [item(m2), item(m3)]);
  check('liste: ust duzey jump_factor 5 ve date', list.jump_factor === 5 && list.date === '2026-10-28', [list.jump_factor, list.date]);

  // 2) Sicrama uyarisi ve onay izi
  let r = await attempt(call(m1, { date: '2026-10-28', value: '181', confirm_jump: false }));
  check('esik ustu (tuketim 51 > 50): 409 READING_JUMP', r.error?.code === 'READING_JUMP' && r.error.statusCode === 409 && r.error.extra.jump.consumption === '51.000' && r.error.extra.jump.limit === '50.000', r.error ?? r.value);
  check('uyari kaydetmedi', Number((await pool.query(`SELECT COUNT(*)::INT AS n FROM meter_readings WHERE meter_id = $1`, [m1])).rows[0].n) === 4);
  r = await attempt(call(m1, { date: '2026-10-28', value: '180', confirm_jump: false }));
  check('esik esit (tuketim 50): uyari yok, kaydedildi', !r.error && r.value.reading.value === '180.000' && r.value.replayed === false, r.error ?? r.value);
  await pool.query(`DELETE FROM meter_readings WHERE meter_id = $1 AND reading_date = '2026-10-28'`, [m1]);
  r = await attempt(call(m1, { date: '2026-10-28', value: '181', confirm_jump: true }));
  check('onayli kayit: kaydedildi, jump_confirmed true', !r.error && r.value.jump_confirmed === true && r.value.reading.value === '181.000', r.error ?? r.value);
  const trail = await audits();
  const jumpAudit = trail.find((a) => a.action === 'metering.reading.jump_confirmed');
  check('onay izi: factor 5, ratio_pct 510, meter_id; okunan deger yok', jumpAudit && jumpAudit.details.factor === 5 && jumpAudit.details.ratio_pct === 510 && jumpAudit.details.meter_id === m1 && !JSON.stringify(trail).includes('181'), trail);
  r = await attempt(call(m1, { date: '2026-10-28', value: '181', confirm_jump: false }));
  check('tekrar gonderim: replayed (uyari / denetim yok)', !r.error && r.value.replayed === true, r.error ?? r.value);
  r = await attempt(call(m1, { date: '2026-10-28', value: '150' }));
  check('replace olmadan farkli deger: READING_EXISTS', r.error?.code === 'READING_EXISTS', r.error ?? r.value);

  // 3) Yeniden cekim
  list = await listFieldMeters(siteCode, { kind: 'water', date: '2026-10-28' }, { now: NOW });
  check('bugunku okuma varken onceki okuma yine 130 (tarihten ONCEKI), son okuma 181 ve tarihi 2026-10-28', item(m1).previous_reading.value === '130.000' && item(m1).last_reading.value === '181.000' && item(m1).last_reading.date === '2026-10-28', [item(m1).previous_reading, item(m1).last_reading]);
  const todayId = Number((await pool.query(`SELECT id FROM meter_readings WHERE meter_id = $1 AND reading_date = '2026-10-28'`, [m1])).rows[0].id);
  r = await attempt(call(m1, { date: '2026-10-28', value: '150', replace: true, confirm_jump: false }));
  check('yeniden cekim: ayni kayit degisti, retaken true, veritabaninda 150.000', !r.error && r.value.retaken === true && r.value.reading.id === todayId && (await readingValue(todayId)) === '150.000', r.error ?? r.value);
  r = await attempt(call(m1, { date: '2026-10-28', value: '120', replace: true }));
  check('yeniden cekimde sira kurali: onceki okumadan kucuk reddedilir', r.error?.code === 'READING_OUT_OF_ORDER' && (await readingValue(todayId)) === '150.000', r.error ?? r.value);
  r = await attempt(call(m1, { date: '2026-10-20', value: '131', replace: true }));
  check('8 gun onceki okuma yeniden cekilemez: RETAKE_WINDOW', r.error?.code === 'RETAKE_WINDOW', r.error ?? r.value);
  r = await attempt(call(m1, { date: '2026-10-28', value: '300', replace: true, confirm_jump: false }));
  check('yeniden cekimde sicrama (tuketim 170 > 50) uyarir, kayit degismez', r.error?.code === 'READING_JUMP' && (await readingValue(todayId)) === '150.000', r.error ?? r.value);
  check('denetim: retaken kaydi var', (await audits()).some((a) => a.action === 'metering.reading.retaken' && a.details.meter_id === m1 && a.details.source === 'field'));

  // 4) Faturalandirilmis donem kilidi
  await pool.query(
    `INSERT INTO meter_billings (site_code, kind, method, period_from, period_to, total_minor, apartment_count, preview_hash, idempotency_key, request_fingerprint)
     VALUES ($1, 'water', 'unit_price', '2026-09-20', '2026-10-28', 1000, 1, 'h', 'idem-key-0001', 'fp')`,
    [siteCode],
  );
  r = await attempt(call(m1, { date: '2026-10-28', value: '160', replace: true }));
  check('faturalandirilmis donem: READING_RETAKE_LOCKED, deger degismedi', r.error?.code === 'READING_RETAKE_LOCKED' && (await readingValue(todayId)) === '150.000', r.error ?? r.value);

  // 5) K site ayari (kurallar tablosu)
  await pool.query(`INSERT INTO platform_rule_values (rule_key, site_code, value, valid_from) VALUES ('metering.jump_factor', $1, '3'::JSONB, '2026-01-01')`, [siteCode]);
  invalidateRuleCache();
  list = await listFieldMeters(siteCode, { kind: 'water', date: '2026-10-28' }, { now: NOW });
  check('site K=3: liste esigi 30 ve jump_factor 3', item(m1).jump.factor === 3 && item(m1).jump.limit === '30.000' && list.jump_factor === 3, [item(m1).jump, list.jump_factor]);

  // 6) Eski istemci ve ilk okuma
  r = await attempt(call(m2, { date: '2026-10-28', value: '99999' }));
  check('eski istemci (confirm_jump yok): hicbir denetim olmadan kaydolur', !r.error && r.value.replayed === false, r.error ?? r.value);
  r = await attempt(call(m3, { date: '2026-10-28', value: '77', confirm_jump: false }));
  check('okumasiz sayac: ilk okuma uyarisiz kaydolur', !r.error, r.error ?? r.value);
} finally {
  if (siteCode !== null) await pool.query(`DELETE FROM sites WHERE site_code = $1`, [siteCode]).catch(() => {});
  await pool.end();
}
console.log(failures === 0 ? 'TUMU GECTI' : `${failures} HATA`);
process.exitCode = failures === 0 ? 0 : 1;
