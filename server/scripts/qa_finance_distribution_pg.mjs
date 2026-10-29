#!/usr/bin/env node
// Dagitim tabani (K5, P1-5) ve alacakli devir (K16, P2-4) icin GERCEK PostgreSQL dogrulamasi (sahte DB'li birim testleri SQL'i ayristirmaz).
//
//   cd server
//   node scripts/migrate.js --apply --yes        # ONCE bos, tek kullanimlik yerel bir veritabaninda (091 dahil)
//   DB_HOST=127.0.0.1 DB_PORT=55432 DB_NAME=kapi_qa DB_USER=postgres DB_PASSWORD=x QA_CONFIRM_DISPOSABLE_DB=yes node scripts/qa_finance_distribution_pg.mjs
//
// GUVENLIK: tek kullanimlik YEREL veritabani icindir (DB_HOST yalniz 127.0.0.1 / localhost ve QA_CONFIRM_DISPOSABLE_DB=yes). Kendi siteleri (site_code 1000009xxx) ve kullanicilari
// olusturur, sonda siteleri siler. Uretimde ASLA calistirmayin. Hicbir ag / SMTP baglantisi kurulmaz.
//
// KAPSAM
//   S0  ensureDbSchema iki kez; 091 kisiti 'person_count' kabul eder, bilinmeyeni (23514) reddeder
//   S1  tahakkuk (ek borc + aylik tanim): kisi sayisi tabani gercek SQL ile (gecmis sakin sayilmaz, kayitsiz daire eksik veri, skip_missing, PREVIEW_INCOMPLETE), kurus artiklari
//       kimligi kucuk dairelere, pay toplami tutara birebir; "esit" kisi/arsa payi verisini yok sayar
//   S2  isi payi alan payi tabani: varsayilan esit, arsa payi / kisi sayisi secimi, eksik veri, AREA_BASIS_INCOMPLETE, toplam birebir, defter satirlari
//   S3  alacakli devir: toplu yukleme (borc + alacak) -> defter (payment, source_kind opening, vadesiz, negatif), bakiye, M1 mahsup SQL'i (sonraki aidat alacaktan duser),
//       "tahsilat" toplamlari / kasa eslenmemis tahsilat denetimi devir alacagini SAYMAZ, makbuz / duzeltme reddi, geri alma (borc + alacak), ikinci geri alma 409
import assert from 'node:assert/strict';

if (!['127.0.0.1', 'localhost'].includes(String(process.env.DB_HOST || ''))) {
  console.error('REDDEDILDI: DB_HOST yalnizca 127.0.0.1 veya localhost olabilir (tek kullanimlik yerel veritabani).');
  process.exit(3);
}
if (process.env.QA_CONFIRM_DISPOSABLE_DB !== 'yes') {
  console.error('REDDEDILDI: veritabaninin tek kullanimlik oldugunu QA_CONFIRM_DISPOSABLE_DB=yes ile onaylayin.');
  process.exit(3);
}
process.env.JWT_SECRET ||= 'qa-integration-secret-0123456789abcdef-0123456789';
// K2 (090): Fon hesabina borc yazan tahakkuk (ek borc / aylik tanim borclandirma) dayanak ister; bu betigin konusu dayanak DEGIL: Karar Defteri KAPALI sitelerde serbest metin gerekce yeter.
const DECISION_REASON = 'QA tahakkuk gerekcesi';
console.error = () => {};

const { pool, ensureDbSchema } = await import('../src/db.js');
const { createDefinition, postCharge, postDefinition, previewCharge, previewDefinition } = await import('../src/modules/finance_service.js');
const { previewBilling, postBilling } = await import('../src/modules/metering_billing.js');
const { previewImport, commitImport } = await import('../src/modules/bulk_import_service.js');
const { getOpeningRun, revertOpeningRun } = await import('../src/modules/finance_opening.js');
const { computeIncomeExpense } = await import('../src/modules/finance_reports.js');
const { countUnassignedPayments } = await import('../src/modules/finance_accounts.js');
const { ensureReceiptForPayment } = await import('../src/modules/finance_receipts.js');
const { correctPayment } = await import('../src/modules/finance_ledger_service.js');
const { m1Ctes } = await import('../src/modules/finance_m1.js');
const { todayIso } = await import('../src/modules/people_common.js');

const q = (sql, params = []) => pool.query(sql, params);
const one = async (sql, params) => (await q(sql, params)).rows[0];
let step = 0;
const ok = (name) => console.log(`  OK ${String(++step).padStart(2, '0')}  ${name}`);
const rejects = async (fn, code, label) => {
  try {
    await fn();
  } catch (error) {
    assert.equal(error.code, code, `${label}: beklenen ${code}, gelen ${error.code} ${error.message}`);
    return error;
  }
  throw new Error(`${label}: ${code} bekleniyordu, hata yok`);
};

const TODAY = todayIso();
const PERIOD = TODAY.slice(0, 8) + '01';
const suffix = Math.random().toString(36).slice(2, 7);
let userCode = 91000 + Math.floor(Math.random() * 800);
const mkUser = async (name) => {
  userCode += 1;
  await q(
    `INSERT INTO users (user_code, full_name, email, role, password_hash, is_active, email_verified, approval_status) VALUES ($1, $2, $3, 'site_manager', 'x', TRUE, TRUE, 'approved')`,
    [userCode, name, `qa-dagitim-${userCode}-${suffix}@qa.example`],
  );
  return userCode;
};
let siteCounter = 1000009100 + Math.floor(Math.random() * 400) * 2;
const createdSites = [];
const mkSite = async (name, count, { lands = [] } = {}) => {
  siteCounter += 1;
  const code = siteCounter;
  await q(`INSERT INTO sites (site_code, name, approval_status, approved_at) VALUES ($1, $2, 'approved', NOW())`, [code, `${name} ${suffix}`]);
  createdSites.push(code);
  const blockId = Number((await q(`INSERT INTO site_blocks (site_code, block_name, sort_order) VALUES ($1, 'A Blok', 1) RETURNING id`, [code])).rows[0].id);
  const ids = [];
  for (let n = 1; n <= count; n += 1) {
    const land = lands[n - 1] ?? [null, null];
    ids.push(
      Number(
        (
          await q(
            `INSERT INTO apartments (site_code, block_id, unit_label, sort_order, land_share_numerator, land_share_denominator) VALUES ($1, $2, $3, $4, $5, $6) RETURNING id`,
            [code, blockId, `Daire ${n}`, n, land[0], land[1]],
          )
        ).rows[0].id,
      ),
    );
  }
  for (const moduleCode of ['finance', 'metering']) {
    await q(`INSERT INTO site_modules (site_code, module_code, enabled) VALUES ($1, $2, TRUE) ON CONFLICT DO NOTHING`, [code, moduleCode]);
  }
  return { code, ids };
};
/** Dairedeki kisi: current = true -> guncel sakin; false -> tasinmis (sayilmaz). */
const addResident = async (site, apartmentId, relation, current = true) => {
  const person = Number(
    (await q(`INSERT INTO site_people (site_code, full_name) VALUES ($1, $2) RETURNING id`, [site.code, `QA Kisi ${apartmentId}-${relation}-${Math.random().toString(36).slice(2, 6)}`])).rows[0].id,
  );
  await q(
    `INSERT INTO apartment_residencies (site_code, apartment_id, person_id, relation, is_current, move_in_date, origin) VALUES ($1, $2, $3, $4, $5, '2020-01-01', 'manual')`,
    [site.code, apartmentId, person, relation, current],
  );
};
const MANAGER = await (async () => {
  const code = await mkUser('QA Dagitim Yonetici');
  return { id: code, user_code: code, role: 'site_manager', full_name: 'QA Dagitim Yonetici' };
})();
const key = (() => {
  let n = 0;
  return (label) => `qa-dag-${label}-${suffix}-${(n += 1)}`;
})();
const ledgerOf = async (site, extra = '') => (await q(`SELECT * FROM ledger_entries WHERE site_code = $1 ${extra} ORDER BY id`, [site.code])).rows;
const failCode = async (sql, params = []) => {
  try {
    await q(sql, params);
    return null;
  } catch (error) {
    return error.code ?? String(error.message);
  }
};

// ---------------------------------------------------------------------------------------------------------------------------------------------------------------
console.log('--- S0. sema (091) ---');
await ensureDbSchema();
await ensureDbSchema();
{
  const def = await one(`SELECT pg_get_constraintdef(oid) AS d, convalidated FROM pg_constraint WHERE conname = 'chk_fee_definitions_distribution' AND conrelid = 'fee_definitions'::regclass`);
  assert.ok(def.convalidated && /person_count/.test(def.d), def.d);
  ok(`chk_fee_definitions_distribution person_count icerir ve dogrulanmis: ${def.d.slice(0, 90)}...`);
}

// ---------------------------------------------------------------------------------------------------------------------------------------------------------------
console.log('--- S1. tahakkuk dagitim tabani (kisi sayisi, esit) ---');
const S1 = await mkSite('QA Dagitim Sitesi', 6, { lands: [[1, 10], [2, 10], [3, 10], [1, 10], [2, 10], [1, 10]] });
{
  const [a1, a2, a3, a4, a5, a6] = S1.ids;
  await addResident(S1, a1, 'owner');
  await addResident(S1, a1, 'family_member'); // a1: 2 kisi
  await addResident(S1, a2, 'tenant');
  await addResident(S1, a2, 'family_member');
  await addResident(S1, a2, 'family_member'); // a2: 3 kisi
  await addResident(S1, a3, 'tenant');
  await addResident(S1, a3, 'tenant', false); // a3: 1 guncel + 1 tasinmis -> 1 kisi
  // a4: kisi kaydi YOK -> eksik veri
  for (let i = 0; i < 4; i += 1) await addResident(S1, a5, i === 0 ? 'owner' : 'family_member'); // a5: 4 kisi
  await addResident(S1, a6, 'owner');
  await addResident(S1, a6, 'tenant'); // a6: 2 kisi

  const body = { name: 'QA kisi sayisi gideri', distribution: 'person_count', amount_minor: 1000000, target: { type: 'site' } };
  const preview = await previewCharge({ siteCode: S1.code, body, now: new Date() });
  const persons = new Map([[a1, 2], [a2, 3], [a3, 1], [a5, 4], [a6, 2]]);
  assert.deepEqual(preview.missing_data.map((m) => [m.apartment_id, m.reason_code]), [[a4, 'person_count_missing']]);
  assert.deepEqual(preview.lines.map((l) => [l.apartment_id, l.basis_value]), [...persons].map(([id, count]) => [id, count]));
  // bagimsiz dogrulama: tam sayi (BigInt) en buyuk kalan
  const W = 12n;
  const base = new Map([...persons].map(([id, k]) => [id, (1000000n * BigInt(k)) / W]));
  const rem = new Map([...persons].map(([id, k]) => [id, (1000000n * BigInt(k)) % W]));
  let left = 1000000n - [...base.values()].reduce((s, v) => s + v, 0n);
  const order = [...persons.keys()].sort((x, y) => (rem.get(x) === rem.get(y) ? x - y : rem.get(x) > rem.get(y) ? -1 : 1));
  const expected = new Map([...base]);
  for (const id of order) {
    if (left <= 0n) break;
    expected.set(id, expected.get(id) + 1n);
    left -= 1n;
  }
  assert.deepEqual(preview.lines.map((l) => BigInt(l.amount_minor)), [...persons.keys()].map((id) => expected.get(id)));
  assert.equal(preview.total_minor, 1000000, 'toplam tutarin TAMAMI kisi kaydi olan dairelere dagilir');
  ok('kisi sayisi onizlemesi gercek SQL ile: gecmis sakin sayilmaz, kayitsiz daire eksik veri, pay toplami birebir, kurus artiklari en buyuk kalana');

  await rejects(
    () => postCharge({ siteCode: S1.code, body: { ...body, decision_reason: DECISION_REASON, expected_total_minor: preview.total_minor, expected_apartment_count: preview.apartment_count, expected_hash: preview.preview_hash, idempotency_key: key('inc') }, actor: MANAGER }),
    'PREVIEW_INCOMPLETE',
    'eksik veri onaysiz',
  );
  const posted = await postCharge({
    siteCode: S1.code,
    body: { ...body, decision_reason: DECISION_REASON, skip_missing: true, expected_total_minor: preview.total_minor, expected_apartment_count: preview.apartment_count, expected_hash: preview.preview_hash, idempotency_key: key('skip') },
    actor: MANAGER,
  });
  assert.equal(posted.skipped_count, 1);
  assert.equal(posted.redistributed, true);
  const rows = await ledgerOf(S1, `AND kind = 'charge'`);
  assert.equal(rows.length, 5);
  assert.equal(rows.reduce((s, r) => s + BigInt(r.amount_minor), 0n), 1000000n);
  assert.ok(!rows.some((r) => Number(r.apartment_id) === a4));
  ok('skip_missing ile borclandirma: 5 satir, toplam 1.000.000 kurus, eksik daireye satir yok, redistributed=true; onaysiz 409 PREVIEW_INCOMPLETE');

  // esit: kisi / arsa payi verisini YOK SAYAR (kod taban secmez); kurus artiklari kimligi kucuk dairelere
  const eqBody = { name: 'QA esit gider', distribution: 'equal', amount_minor: 1000005, target: { type: 'site' } };
  const eqPreview = await previewCharge({ siteCode: S1.code, body: eqBody, now: new Date() });
  // 1.000.005 / 6 = 166.667,5 -> taban 166.667 (6 x = 1.000.002), artan 3 kurus kimligi kucuk ilk 3 daireye
  assert.deepEqual(eqPreview.lines.map((l) => l.amount_minor), [166668, 166668, 166668, 166667, 166667, 166667]);
  assert.equal(eqPreview.total_minor, 1000005);
  assert.deepEqual(eqPreview.lines.map((l) => l.basis_value), [null, null, null, null, null, null]);
  ok('esit: 1.000.005 kurus / 6 daire -> ilk 3 daire 166.668, kalanlar 166.667 (kimligi kucuk once); kisi sayisi / arsa payi verisi yok sayildi');

  // aylik tanim: DB CHECK 'person_count' kabul eder; tanimin onizleme / borclandirmasi
  const definition = await createDefinition({
    siteCode: S1.code,
    body: { name: 'QA aylik su payi', kind: 'recurring', distribution: 'person_count', amount_minor: 600000, due_day: 5, start_period: PERIOD.slice(0, 7), target: { type: 'site' } },
    actor: MANAGER,
  });
  assert.equal(definition.distribution, 'person_count');
  const defPreview = await previewDefinition({ siteCode: S1.code, rawId: String(definition.id), body: { period: PERIOD.slice(0, 7) }, now: new Date() });
  assert.equal(defPreview.missing_data.length, 1);
  assert.equal(defPreview.lines.reduce((s, l) => s + l.amount_minor, 0), 600000);
  const defPost = await postDefinition({
    siteCode: S1.code,
    rawId: String(definition.id),
    body: { period: PERIOD.slice(0, 7), decision_reason: DECISION_REASON, skip_missing: true, expected_total_minor: defPreview.total_minor, expected_apartment_count: defPreview.apartment_count, expected_hash: defPreview.preview_hash, idempotency_key: key('def') },
    actor: MANAGER,
  });
  assert.equal(defPost.skipped_count, 1);
  ok('aylik tanim (distribution=person_count) olusur (091 CHECK), onizlenir ve borclandirilir');

  assert.equal(
    await failCode(`INSERT INTO fee_definitions (site_code, name, kind, distribution, amount_minor, due_day, start_period, target_type) VALUES ($1, 'x', 'recurring', 'm2', 100, 5, $2, 'site')`, [S1.code, PERIOD]),
    '23514',
  );
  ok("DB CHECK: bilinmeyen taban ('m2') reddedilir (23514)");
}

// ---------------------------------------------------------------------------------------------------------------------------------------------------------------
console.log('--- S2. isi payi alan payi tabani ---');
const S2 = await mkSite('QA Isi Sitesi', 3, { lands: [[1, 6], [2, 6], [null, null]] });
{
  const [b1, b2, b3] = S2.ids;
  await addResident(S2, b1, 'owner');
  await addResident(S2, b2, 'tenant');
  await addResident(S2, b2, 'family_member');
  // b3: kisi kaydi yok, arsa payi yok
  for (const [index, id] of S2.ids.entries()) {
    const meter = Number((await q(`INSERT INTO meters (site_code, apartment_id, kind, serial_no) VALUES ($1, $2, 'heat', $3) RETURNING id`, [S2.code, id, `QA-H-${index}-${suffix}`])).rows[0].id);
    await q(`INSERT INTO meter_readings (site_code, meter_id, reading_date, value) VALUES ($1, $2, '2026-01-01', 0), ($1, $2, '2026-02-01', $3)`, [S2.code, meter, 100 * (index + 1)]);
  }
  const input = { kind: 'heat', method: 'heat', period_from: '2026-01-01', period_to: '2026-02-01', total_minor: 600000 };
  const byDefault = await previewBilling({ siteCode: S2.code, body: input });
  assert.equal(byDefault.area_basis, 'equal');
  assert.equal(byDefault.params.area_basis, 'equal');
  assert.equal(byDefault.missing.length, 0, 'varsayilan esit: arsa payi / kisi kaydi eksikligi engel degil');
  assert.equal(byDefault.total_minor, 600000);
  ok('varsayilan (taban verilmedi) = ESIT: arsa payi tanimli daireler olsa bile kod arsa payina GECMEZ; eksik veri yok; toplam birebir');

  const byLand = await previewBilling({ siteCode: S2.code, body: { ...input, area_basis: 'land_share' } });
  assert.deepEqual(byLand.missing.map((m) => [m.apartment_id, m.reason]), [[b3, 'land_share_missing']]);
  assert.equal(byLand.params.area_basis, 'land_share');
  assert.equal(byLand.can_post, false);
  await rejects(
    () =>
      postBilling({
        siteCode: S2.code,
        body: { ...input, area_basis: 'land_share', idempotency_key: key('heat-l'), expected_total_minor: byLand.total_minor, expected_count: byLand.apartment_count, expected_hash: byLand.preview_hash },
        actor: MANAGER,
      }),
    'AREA_BASIS_INCOMPLETE',
    'arsa payi eksik',
  );
  ok("arsa payi secildi: arsa payi eksik daire 'land_share_missing'; onaysiz yazma 409 AREA_BASIS_INCOMPLETE (sessiz esit paya dusme yok)");

  const byPeople = await previewBilling({ siteCode: S2.code, body: { ...input, area_basis: 'person_count', skip_missing: true } });
  assert.deepEqual(byPeople.missing.map((m) => [m.apartment_id, m.reason]), [[b3, 'person_count_missing']]);
  assert.equal(byPeople.params.area_basis, 'person_count');
  assert.equal(byPeople.apartment_count, 2);
  assert.equal(byPeople.total_minor, 600000, 'atlanan dairenin payi kalanlara dagilir; toplam birebir');
  assert.notEqual(byPeople.preview_hash, byDefault.preview_hash);
  const posted = await postBilling({
    siteCode: S2.code,
    body: { ...input, area_basis: 'person_count', skip_missing: true, idempotency_key: key('heat-p'), expected_total_minor: byPeople.total_minor, expected_count: byPeople.apartment_count, expected_hash: byPeople.preview_hash },
    actor: MANAGER,
  });
  assert.equal(posted.entries_count, 2);
  const heatRows = await ledgerOf(S2, `AND kind = 'charge'`);
  assert.equal(heatRows.reduce((s, r) => s + BigInt(r.amount_minor), 0n), 600000n);
  const billing = await one(`SELECT params FROM meter_billings WHERE site_code = $1`, [S2.code]);
  assert.equal(billing.params.area_basis, 'person_count');
  ok('kisi sayisi secildi + skip_missing: 2 daire borclandirildi, defter toplami 600.000, meter_billings.params.area_basis=person_count');
}

// ---------------------------------------------------------------------------------------------------------------------------------------------------------------
console.log('--- S3. alacakli devir (K16) ---');
const S3 = await mkSite('QA Devir Sitesi', 4);
{
  const [c1, c2, c3, c4] = S3.ids;
  const CUTOVER = TODAY;
  const rows = [
    { n: 1, cells: { blok: 'A Blok', daire_no: '1', tutar: '1.250,50', aciklama: 'Eski borc' } },
    { n: 2, cells: { blok: 'A Blok', daire_no: '2', tutar: '-500,00', aciklama: 'Pesin odeme' } },
    { n: 3, cells: { blok: 'A Blok', daire_no: '3', tutar: '-75,25', vade: '15.09.2026' } },
    { n: 4, cells: { blok: 'A Blok', daire_no: '4', tutar: '300,00' } },
  ];
  const body = { spec_version: 1, rows, options: { cutover_date: CUTOVER } };
  const preview = await previewImport({ siteCode: S3.code, kind: 'opening_balances', body });
  assert.equal(preview.totals.error, 0, JSON.stringify(preview.issues));
  assert.equal(preview.plan.total_minor, 125050 + 30000);
  assert.equal(preview.plan.credit_total_minor, 50000 + 7525);
  assert.equal(preview.plan.opening_credit_add, 2);
  assert.ok(preview.issues.some((i) => i.code === 'OPENING_CREDIT_DUE_IGNORED'));
  ok('onizleme: borc toplami 1.550,50, alacak toplami 575,25, 2 alacak satiri, alacakta vade uyarisi');

  await rejects(
    () =>
      commitImport({
        siteCode: S3.code,
        kind: 'opening_balances',
        body: { ...body, options: { cutover_date: CUTOVER, expected_total_minor: 155050 }, expected_hash: preview.preview_hash, idempotency_key: key('ob0') },
        actor: MANAGER,
      }),
    'TOTAL_MISMATCH',
    'alacak toplami onaysiz',
  );
  const committed = await commitImport({
    siteCode: S3.code,
    kind: 'opening_balances',
    body: { ...body, options: { cutover_date: CUTOVER, expected_total_minor: 155050, expected_credit_total_minor: 57525 }, expected_hash: preview.preview_hash, idempotency_key: key('ob1') },
    actor: MANAGER,
  });
  assert.equal(committed.status, 201);
  const runId = Number(committed.body.run.id);
  const ledger = await ledgerOf(S3);
  const byApt = new Map(ledger.map((r) => [Number(r.apartment_id), r]));
  assert.equal(ledger.length, 4);
  assert.deepEqual([c1, c4].map((id) => [byApt.get(id).kind, Number(byApt.get(id).amount_minor), byApt.get(id).source_kind]), [['charge', 125050, 'opening'], ['charge', 30000, 'opening']]);
  for (const [id, minor, note] of [[c2, -50000, 'Pesin odeme'], [c3, -7525, null]]) {
    const row = byApt.get(id);
    assert.equal(row.kind, 'payment');
    assert.equal(Number(row.amount_minor), minor);
    assert.equal(row.source_kind, 'opening');
    assert.equal(row.method, 'transfer');
    assert.equal(row.due_date, null, 'alacagin vadesi yok');
    assert.equal(row.definition_name, 'Devir alacağı');
    assert.equal(row.description, note);
    assert.equal(row.account_party, 'owner');
    assert.equal(Number(row.source_id), runId);
    assert.equal(row.fund, null);
  }
  ok('commit: borclar charge, alacaklar payment (negatif, vadesiz, method transfer, source_kind opening, kaynak = yukleme); defter CHECK kisitlari gecti');

  // ayni dosya tekrar: degisiklik yok (borc VE alacak)
  const again = await previewImport({ siteCode: S3.code, kind: 'opening_balances', body });
  assert.equal(again.totals.unchanged, 4);
  assert.equal(again.plan.opening_add, 0);
  const diff = await previewImport({ siteCode: S3.code, kind: 'opening_balances', body: { ...body, rows: [{ n: 1, cells: { blok: 'A Blok', daire_no: '2', tutar: '-501,00' } }] } });
  assert.ok(diff.issues.some((i) => i.code === 'OPENING_EXISTS'));
  ok('ayni dosya tekrar = degisiklik yok (alacaklar dahil); farkli alacak OPENING_EXISTS');

  // bakiye + M1 mahsup (gercek SQL): c2 alacakli (-50.000); sonra c2'ye 354.167 aidat
  const chargeBody = { name: 'QA Ekim aidati', distribution: 'equal', amount_minor: 354167, target: { type: 'apartments', apartment_ids: [c2] }, due_date: TODAY };
  const chargePreview = await previewCharge({ siteCode: S3.code, body: chargeBody, now: new Date() });
  await postCharge({
    siteCode: S3.code,
    body: { ...chargeBody, decision_reason: DECISION_REASON, expected_total_minor: chargePreview.total_minor, expected_apartment_count: chargePreview.apartment_count, expected_hash: chargePreview.preview_hash, idempotency_key: key('aidat') },
    actor: MANAGER,
  });
  const balance = Number((await one(`SELECT COALESCE(SUM(amount_minor), 0)::TEXT AS s FROM ledger_entries WHERE site_code = $1 AND apartment_id = $2`, [S3.code, c2])).s);
  assert.equal(balance, 354167 - 50000, 'bakiye = borc - devir alacagi');
  const m1 = await q(
    `WITH ${m1Ctes('$1', '$2', ' AND l.apartment_id = ANY($3::BIGINT[])')} SELECT rem.apartment_id, SUM(rem.r)::TEXT AS open_total FROM rem GROUP BY rem.apartment_id`,
    [S3.code, TODAY, [c2]],
  );
  assert.equal(Number(m1.rows[0].open_total), 304167, 'M1: alacak sonraki aidattan DUSER (354.167 - 50.000)');
  ok('M1 mahsup SQL: devir alacagi sonraki aidata duser (354.167 - 50.000 = 304.167); bakiye ayni');

  // tahsilat toplamlari ve kasa eslenmemis denetimi devir alacagini SAYMAZ
  const [month] = await computeIncomeExpense(pool, S3.code, [PERIOD]);
  assert.equal(month.collected, 0n, `gelir-gider raporu tahsilat: ${month.collected}`);
  assert.equal(month.charged, 354167n, 'devir borcu "borclandirilan" toplamina girmez (mevcut davranis), yalniz aidat');
  const unassigned = await countUnassignedPayments(pool, S3.code, CUTOVER);
  assert.equal(unassigned.count, 0, 'devir alacagi hesaba eslenmemis tahsilat sayilmaz');
  ok('gelir-gider "tahsilat" = 0 ve eslenmemis tahsilat = 0 (devir alacagi tahsilat DEGIL)');

  // makbuz ve duzeltme reddi
  const creditEntry = byApt.get(c2);
  await rejects(
    async () => {
      const client = await pool.connect();
      try {
        await ensureReceiptForPayment(client, { siteCode: S3.code, entryId: Number(creditEntry.id), actor: MANAGER, actorInfo: { userCode: MANAGER.user_code } });
      } finally {
        client.release();
      }
    },
    'RECEIPT_NOT_APPLICABLE',
    'makbuz',
  );
  await rejects(
    () => correctPayment({ siteCode: S3.code, rawId: String(creditEntry.id), body: { amount_minor: 40000, entry_date: TODAY, method: 'cash', idempotency_key: key('cor') }, actor: MANAGER }),
    'ENTRY_NOT_CORRECTABLE',
    'duzeltme',
  );
  ok('devir alacagi icin makbuz (409 RECEIPT_NOT_APPLICABLE) ve tahsilat duzeltmesi (409 ENTRY_NOT_CORRECTABLE) reddedilir');

  // yukleme ayrintisi + geri alma (borc + alacak); c2'nin aidati geri alma disinda kalir
  const detail = await getOpeningRun(S3.code, String(runId));
  assert.equal(detail.revert.entries_to_reverse, 4);
  assert.equal(detail.revert.total_minor, 155050);
  assert.equal(detail.revert.credit_total_minor, 57525);
  assert.equal(detail.revert.credit_entries_to_reverse, 2);
  assert.equal(detail.revert.apartments_with_later_payments, 0, 'devir alacagi sonradan tahsilat sayilmaz');
  // NEGATIF KONTROL: GERCEK bir tahsilat (kaynak manual, kasaya eslenmemis) hem "sonradan tahsilat" hem "eslenmemis tahsilat" olarak SAYILIR
  await q(
    `INSERT INTO ledger_entries (site_code, apartment_id, kind, amount_minor, period, entry_date, payer_party, account_party, method, source_kind) VALUES ($1, $2, 'payment', -1000, $3, $4, 'owner', 'owner', 'cash', 'manual')`,
    [S3.code, c4, PERIOD, TODAY],
  );
  assert.equal((await countUnassignedPayments(pool, S3.code, CUTOVER)).count, 1, 'gercek tahsilat eslenmemis sayilir (devir alacagi sayilmaz)');
  assert.equal((await getOpeningRun(S3.code, String(runId))).revert.apartments_with_later_payments, 1, 'gercek tahsilat "sonradan tahsilat" sayilir (yalniz c4)');
  const [afterReal] = await computeIncomeExpense(pool, S3.code, [PERIOD]);
  assert.equal(afterReal.collected, 1000n, 'gelir-gider tahsilati gercek tahsilati icerir, devir alacagini icermez');
  ok('negatif kontrol: gercek tahsilat eslenmemis / sonradan tahsilat / gelir-gider tahsilati olarak sayilir; devir alacagi sayilmaz');
  await rejects(
    () => revertOpeningRun({ siteCode: S3.code, rawRunId: String(runId), body: { reason: 'QA', idempotency_key: key('rv0'), expected_count: 4, expected_total_minor: 155050 }, actor: MANAGER }),
    'OPENING_CHANGED',
    'alacak toplami onaysiz',
  );
  const revertKey = key('rv1');
  const revertBody = { reason: 'QA geri alma', idempotency_key: revertKey, expected_count: 4, expected_total_minor: 155050, expected_credit_total_minor: 57525 };
  const reverted = await revertOpeningRun({ siteCode: S3.code, rawRunId: String(runId), body: revertBody, actor: MANAGER });
  assert.deepEqual(reverted, { replayed: false, reversed_count: 4, reversed_total_minor: 155050, reversed_credit_total_minor: 57525 });
  const reversals = await ledgerOf(S3, `AND kind = 'reversal'`);
  assert.equal(reversals.length, 4);
  assert.ok(reversals.every((r) => r.source_kind === 'opening' && r.method === null));
  const netByApt = new Map((await q(`SELECT apartment_id, SUM(amount_minor)::TEXT AS s FROM ledger_entries WHERE site_code = $1 GROUP BY apartment_id`, [S3.code])).rows.map((r) => [Number(r.apartment_id), Number(r.s)]));
  assert.equal(netByApt.get(c1), 0);
  assert.equal(netByApt.get(c3), 0);
  assert.equal(netByApt.get(c4), -1000, 'c4: devir borcu geri alindi; gercek tahsilat kaldi (alacak)');
  assert.equal(netByApt.get(c2), 354167, 'c2: yalniz aidat kaldi (devir alacagi geri alindi)');
  await rejects(
    () => revertOpeningRun({ siteCode: S3.code, rawRunId: String(runId), body: { ...revertBody, idempotency_key: key('rv2') }, actor: MANAGER }),
    'OPENING_ALREADY_REVERTED',
    'ikinci geri alma',
  );
  const replay = await revertOpeningRun({ siteCode: S3.code, rawRunId: String(runId), body: revertBody, actor: MANAGER });
  assert.equal(replay.replayed, true);
  ok('geri alma: 4 ters kayit (2 borc + 2 alacak), net bakiyeler sifirlandi (aidat haric); farkli anahtarla ikinci geri alma 409, ayni anahtarla tekrar = replayed');
}

// --- temizlik
for (const code of createdSites) await q(`DELETE FROM sites WHERE site_code = $1`, [code]).catch(() => {});
console.log(`\nTAMAM: ${step} kontrol gecti.`);
await pool.end();
