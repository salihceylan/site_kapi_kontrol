// Kisi ve Daire Kayitlari: "Tasindi" / pasiflestirme (H3, H10) - erisimin gercekten kapanmasi (DB'siz, KATI betikli sahte veritabani).
//
// CRM tasinmasi mevcut uye cikarma akisinin (membership_service.removeApartmentMember) yan etkilerini YENIDEN KULLANIR:
// yonetici devri (handOverApartmentResident), manuel kapi izni temizligi (cleanupDoorOverridesIfNoMembership), daire kilidi sirasi.
// SQL'in gercek anlami gercek-PG betigi (scripts/qa_platform_pg.mjs, bolum "people") ile sinanir.
import { describe, it, beforeEach, afterEach, mock } from 'node:test';
import assert from 'node:assert/strict';
import { pool } from '../src/db.js';
import { endResidency, updatePerson } from '../src/modules/people_service.js';
import { SYNC_STEPS } from '../src/modules/people_sync_sql.js';

process.env.PEOPLE_SYNC_MIN_INTERVAL_MS = '0';

const SITE = 1000000001;
const actor = { id: 20001, user_code: 20001, userCode: 20001, role: 'site_manager', full_name: 'Ayşe Yönetici' };
const norm = (text) => String(text).replace(/\s+/g, ' ').trim();
const ok = (rows = []) => ({ rows, rowCount: rows.length });

let log;
let handlers;

const INFRA = [/^BEGIN$/, /^COMMIT$/, /^ROLLBACK$/, /^SELECT pg_advisory_xact_lock/, /^SAVEPOINT /, /^RELEASE SAVEPOINT /, /^ROLLBACK TO SAVEPOINT /, /^INSERT INTO audit_log/];
const STEP_SQLS = new Set(SYNC_STEPS.map((step) => norm(step.sql)));

function install() {
  log = [];
  const run = async (text, params, inTx) => {
    const sql = norm(text);
    log.push({ sql, params: params ?? [], inTx });
    for (const [pattern, handler] of handlers) {
      if (pattern.test(sql)) return typeof handler === 'function' ? handler(sql, params ?? []) : handler;
    }
    if (INFRA.some((pattern) => pattern.test(sql)) || STEP_SQLS.has(sql)) return ok();
    throw new Error(`BEKLENMEYEN SQL (sahte DB kati): ${sql.slice(0, 220)}`);
  };
  pool.query = (text, params) => run(text, params, false);
  pool.connect = async () => ({ query: (text, params) => run(text, params, true), release() {} });
}

const find = (regex) => log.find((q) => regex.test(q.sql));
const findAll = (regex) => log.filter((q) => regex.test(q.sql));
const has = (regex) => log.some((q) => regex.test(q.sql));
const at = (regex) => log.findIndex((q) => regex.test(q.sql));
const auditActions = () => findAll(/^INSERT INTO audit_log/).map((q) => q.params[3]);
const auditDetails = (action) => JSON.parse(findAll(/^INSERT INTO audit_log/).find((q) => q.params[3] === action).params[7]);

const RESIDENCY_LOOKUP = /FROM apartment_residencies r INNER JOIN site_people sp ON sp\.id = r\.person_id WHERE r\.id = \$1 AND sp\.site_code = \$2 LIMIT 1 FOR UPDATE OF r$/;
const APT_LOCK = /^SELECT id, site_code, resident_user_code FROM apartments WHERE id = \$1 FOR UPDATE$/;
const RESIDENCY_END = /^UPDATE apartment_residencies SET is_current = FALSE, move_out_date = \$2, updated_at = NOW\(\) WHERE id = \$1 AND is_current = TRUE RETURNING id$/;
const MEMBER_SELECT = /^SELECT role, is_active FROM apartment_memberships WHERE apartment_id = \$1 AND user_code = \$2 FOR UPDATE$/;
const MEMBER_OFF = /^UPDATE apartment_memberships SET is_active = FALSE, updated_at = NOW\(\) WHERE apartment_id = \$1 AND user_code = \$2$/;
const OTHER_ADMIN = /^SELECT user_code FROM apartment_memberships WHERE apartment_id = \$1 AND user_code <> \$2 AND is_active = TRUE AND role = 'APARTMENT_ADMIN'/;
const REMAINING_MEMBER = /^SELECT user_code FROM apartment_memberships WHERE apartment_id = \$1 AND user_code <> \$2 AND is_active = TRUE ORDER BY created_at ASC, id ASC LIMIT 1$/;
const PROMOTE = /^UPDATE apartment_memberships SET role = 'APARTMENT_ADMIN', updated_at = NOW\(\) WHERE apartment_id = \$1 AND user_code = \$2$/;
const INDICATOR_SET = /^UPDATE apartments SET resident_user_code = \$1 WHERE id = \$2$/;
const INDICATOR_CLEAR = /^UPDATE apartments SET resident_user_code = NULL, resident_pin_code = NULL WHERE id = \$1$/;
const INTERNAL_OFF = /^UPDATE users SET is_active = FALSE WHERE user_code = \$1 AND email LIKE '%@ahbu\.local'/;
const OVERRIDE_CLEANUP = /^DELETE FROM door_access_overrides dao WHERE dao\.site_code = \$1 AND dao\.user_code = \$2/;
const REMAINING_RESIDENCY = /^SELECT 1 FROM apartment_residencies WHERE person_id = \$1 AND is_current = TRUE LIMIT 1$/;
const PERSON_OFF = /^UPDATE site_people SET is_active = FALSE, updated_at = NOW\(\) WHERE id = \$1 AND is_active = TRUE RETURNING id$/;
const VEHICLES_OFF = /^UPDATE vehicles SET is_active = FALSE WHERE person_id = \$1 AND is_active = TRUE RETURNING id, plate$/;
const ROTATION = /^SELECT DISTINCT devices\.id FROM devices/;
const DETAIL_PERSON = /^SELECT sp\.id, sp\.user_code, sp\.is_active, sp\.note[\s\S]*WHERE sp\.site_code = \$1 AND sp\.id = \$2 LIMIT 1$/;
const DETAIL_RESIDENCIES = /FROM apartment_residencies r INNER JOIN apartments a ON a\.id = r\.apartment_id INNER JOIN site_blocks b ON b\.id = a\.block_id WHERE r\.person_id = \$1 ORDER BY/;
const DETAIL_VEHICLES = /FROM vehicles v LEFT JOIN site_people sp ON sp\.id = v\.person_id[\s\S]*WHERE v\.person_id = \$1 AND v\.is_active = TRUE ORDER BY v\.id$/;

const today = () => new Intl.DateTimeFormat('en-CA', { timeZone: 'Europe/Istanbul', year: 'numeric', month: '2-digit', day: '2-digit' }).format(new Date());

const residencyRow = (extra = {}) => ({
  id: '31',
  apartment_id: '9',
  person_id: '5',
  relation: 'resident',
  is_current: true,
  move_in_date: '2025-01-01',
  move_out_date: null,
  user_code: 30001,
  ...extra,
});

/**
 * Tasinma akisinin ortak isleyicileri. Secenekler:
 *  member: apartment_memberships satiri ({role,is_active}) ya da null; indicator: apartments.resident_user_code;
 *  otherAdmin / remainingMember: handOver icin; internalOff: dahili hesap pasiflesti mi; remaining: baska guncel iliski var mi.
 */
function closeHandlers({ member = { role: 'FAMILY_MEMBER', is_active: true }, indicator = null, otherAdmin = false, remainingMember = false, internalOff = false, remaining = false, vehicles = [] } = {}) {
  handlers.push(
    [RESIDENCY_LOOKUP, () => ok([residencyRow()])],
    [APT_LOCK, (_sql, params) => ok([{ id: String(params[0]), site_code: String(SITE), resident_user_code: indicator }])],
    [RESIDENCY_END, () => ok([{ id: '31' }])],
    [MEMBER_SELECT, () => (member ? ok([member]) : ok())],
    [MEMBER_OFF, () => ok()],
    [OTHER_ADMIN, () => (otherAdmin ? ok([{ user_code: 30002 }]) : ok())],
    [REMAINING_MEMBER, () => (remainingMember ? ok([{ user_code: 30003 }]) : ok())],
    [PROMOTE, () => ok()],
    [INDICATOR_SET, () => ok()],
    [INDICATOR_CLEAR, () => ok()],
    [INTERNAL_OFF, () => (internalOff ? ok([{ user_code: 30001 }]) : ok())],
    [OVERRIDE_CLEANUP, () => ok()],
    [REMAINING_RESIDENCY, () => (remaining ? ok([{ x: 1 }]) : ok())],
    [PERSON_OFF, () => ok([{ id: '5' }])],
    [VEHICLES_OFF, () => ok(vehicles)],
    [ROTATION, () => ok()],
    [DETAIL_PERSON, () => ok([{ id: '5', user_code: 30001, is_active: true, note: null, created_at: new Date('2026-10-14T08:00:00.000Z'), full_name: 'Ali', phone: null, email: null, has_account: true, account_kind: 'registered' }])],
    [DETAIL_RESIDENCIES, () => ok()],
    [DETAIL_VEHICLES, () => ok()],
  );
}

beforeEach(() => {
  handlers = [];
  install();
  mock.method(console, 'error', () => {});
  mock.method(console, 'log', () => {});
});

afterEach(() => {
  delete pool.query;
  delete pool.connect;
  mock.restoreAll();
});

describe('H3: "Tasindi" mevcut uye cikarma akisinin yan etkilerini uygular', () => {
  it('daire satiri ILK kilitlenir (uyelik akislariyla ayni kilit sirasi); sonra iliski, uyelik; uyelik FOR UPDATE', async () => {
    closeHandlers();
    await endResidency({ siteCode: SITE, residencyId: 31, body: {}, actor });
    assert.deepEqual(find(APT_LOCK).params.map(Number), [9]);
    assert.ok(at(APT_LOCK) < at(RESIDENCY_END), 'daire kilidi iliski guncellemesinden once');
    assert.ok(at(RESIDENCY_END) < at(MEMBER_SELECT));
    assert.ok(at(MEMBER_SELECT) < at(MEMBER_OFF));
    assert.deepEqual(find(MEMBER_OFF).params.map(Number), [9, 30001], 'yalniz O daire ve O kullanici');
  });

  it('daire yoneticisi (APARTMENT_ADMIN) tasininca YONETICI DEVRI: baska aktif admin varsa gosterge ona; yoksa en eski aktif uye admin olur', async () => {
    closeHandlers({ member: { role: 'APARTMENT_ADMIN', is_active: true }, indicator: 30001, otherAdmin: true });
    await endResidency({ siteCode: SITE, residencyId: 31, body: {}, actor });
    assert.deepEqual(find(INDICATOR_SET).params.map(Number), [30002, 9], 'gosterge baska aktif admine devredildi');
    assert.equal(has(PROMOTE), false);

    install();
    handlers.length = 0;
    closeHandlers({ member: { role: 'APARTMENT_ADMIN', is_active: true }, indicator: 30001, remainingMember: true });
    await endResidency({ siteCode: SITE, residencyId: 31, body: {}, actor });
    assert.deepEqual(find(PROMOTE).params.map(Number), [9, 30003], 'en eski aktif uye admin yapildi');
    assert.deepEqual(find(INDICATOR_SET).params.map(Number), [30003, 9]);

    install();
    handlers.length = 0;
    closeHandlers({ member: { role: 'APARTMENT_ADMIN', is_active: true }, indicator: 30001 });
    await endResidency({ siteCode: SITE, residencyId: 31, body: {}, actor });
    assert.deepEqual(find(INDICATOR_CLEAR).params.map(Number), [9], 'kimse kalmadi: gosterge ve PIN temizlendi (eski sakin erisimi surmesin)');
  });

  it('SAF legacy sakin (apartment_memberships satiri YOK, resident_user_code var): gosterge devredilir/temizlenir, kapi izinleri SILINIR, anahtar doner', async () => {
    closeHandlers({ member: null, indicator: 30001 });
    await endResidency({ siteCode: SITE, residencyId: 31, body: {}, actor });
    assert.equal(has(MEMBER_OFF), false, 'uyelik satiri yok -> guncelleme yok');
    assert.ok(has(INDICATOR_CLEAR));
    const cleanup = find(OVERRIDE_CLEANUP);
    assert.deepEqual(cleanup.params, [SITE, 30001]);
    assert.ok(at(INDICATOR_CLEAR) < at(OVERRIDE_CLEANUP), 'izin temizligi gostergeyi bosalttiktan SONRA (aksi halde eski sakin sayilip izin kalir)');
    assert.match(cleanup.sql, /NOT EXISTS \( SELECT 1 FROM apartment_memberships am .* am\.is_active = TRUE AND a\.is_active = TRUE \) AND NOT EXISTS \( SELECT 1 FROM apartments a2 WHERE a2\.site_code = \$1 AND a2\.resident_user_code = \$2 AND a2\.is_active = TRUE \)/);
    assert.ok(has(ROTATION), 'yerel kontrol anahtari donduruldu');
  });

  it('dahili (@ahbu.local) daire hesabi: baska erisimi kalmadiysa hesap PASIFLESIR (giris ve PIN ile kapi kapanir)', async () => {
    closeHandlers({ member: null, indicator: 30001, internalOff: true });
    await endResidency({ siteCode: SITE, residencyId: 31, body: {}, actor });
    const off = find(INTERNAL_OFF);
    assert.deepEqual(off.params, [30001]);
    assert.match(off.sql, /AND is_active = TRUE AND NOT EXISTS \(SELECT 1 FROM apartment_memberships am WHERE am\.user_code = \$1 AND am\.is_active = TRUE\) AND NOT EXISTS \(SELECT 1 FROM apartments a WHERE a\.resident_user_code = \$1\)/);
    assert.ok(at(INDICATOR_CLEAR) < at(INTERNAL_OFF), 'gosterge bosaldiktan sonra');
    assert.equal(has(/DELETE FROM users/), false, 'hesap silinmez, pasiflesir');
  });

  it('hesapli ama BU dairede erisimi olmayan kisi (yalniz kayit): erisim islemi yok, anahtar donmez', async () => {
    closeHandlers({ member: null, indicator: null });
    await endResidency({ siteCode: SITE, residencyId: 31, body: {}, actor });
    assert.equal(has(MEMBER_OFF), false);
    assert.equal(has(INDICATOR_CLEAR) || has(INDICATOR_SET), false);
    assert.equal(has(ROTATION), false);
  });

  it('HESAPSIZ kisi: uyelik/kapi sorgusu hic calismaz; anahtar donmez', async () => {
    closeHandlers();
    handlers.unshift([RESIDENCY_LOOKUP, () => ok([residencyRow({ user_code: null })])]);
    await endResidency({ siteCode: SITE, residencyId: 31, body: {}, actor });
    assert.equal(has(MEMBER_SELECT) || has(MEMBER_OFF) || has(OVERRIDE_CLEANUP) || has(INTERNAL_OFF), false);
    assert.equal(has(ROTATION), false);
    assert.ok(has(APT_LOCK), 'daire kilidi hesapsizda da alinir (tutarli kilit sirasi)');
  });

  it('son guncel iliski bitince kisi PASIF olur ve ARACLARI pasiflesir (kayit silinmez, her arac icin vehicle.removed audit)', async () => {
    closeHandlers({ vehicles: [{ id: '4', plate: '34ABC123' }, { id: '5', plate: '06XYZ99' }] });
    await endResidency({ siteCode: SITE, residencyId: 31, body: {}, actor });
    assert.deepEqual(find(VEHICLES_OFF).params.map(Number), [5]);
    assert.equal(has(/DELETE FROM (site_people|apartment_residencies|vehicles)/), false, 'CRM kayitlari silinmez');
    assert.deepEqual(auditActions(), ['residency.ended', 'person.deactivated', 'vehicle.removed', 'vehicle.removed']);
    const removed = findAll(/^INSERT INTO audit_log/).filter((q) => q.params[3] === 'vehicle.removed');
    assert.deepEqual(removed.map((q) => q.params[6]), ['4', '5']);
    assert.deepEqual(JSON.parse(removed[0].params[7]), { plate: '34ABC123', person_id: 5, reason: 'residency_ended' });
  });

  it('baska guncel iliskisi kalan kisi aktif kalir, araclari pasiflesmez', async () => {
    closeHandlers({ remaining: true });
    await endResidency({ siteCode: SITE, residencyId: 31, body: {}, actor });
    assert.equal(has(PERSON_OFF), false);
    assert.equal(has(VEHICLES_OFF), false);
    assert.deepEqual(auditActions(), ['residency.ended']);
    assert.deepEqual(auditDetails('residency.ended').apartment_id, 9);
  });

  it('move_out_date GELECEKTE olamaz (400 INVALID_BODY); bugun ve gecmis tarih kabul edilir', async () => {
    closeHandlers();
    await assert.rejects(
      () => endResidency({ siteCode: SITE, residencyId: 31, body: { move_out_date: '2099-01-01' }, actor }),
      (error) => error.code === 'INVALID_BODY' && error.statusCode === 400 && /move_out_date/.test(error.message),
    );
    assert.equal(has(RESIDENCY_END), false, 'hicbir sey yazilmadi');
    await endResidency({ siteCode: SITE, residencyId: 31, body: { move_out_date: today() }, actor });
    assert.deepEqual(find(RESIDENCY_END).params.map(String), ['31', today()]);
    install();
    handlers.length = 0;
    closeHandlers();
    await endResidency({ siteCode: SITE, residencyId: 31, body: { move_out_date: '2025-06-01' }, actor });
    assert.equal(find(RESIDENCY_END).params[1], '2025-06-01');
  });

  it('cikis tarihi giris tarihinden once 400; zaten sona ermis 409; yok 404', async () => {
    closeHandlers();
    await assert.rejects(() => endResidency({ siteCode: SITE, residencyId: 31, body: { move_out_date: '2024-12-31' }, actor }), (e) => e.code === 'INVALID_BODY' && /move_out_date/.test(e.message));
    install();
    handlers.length = 0;
    handlers.push([RESIDENCY_LOOKUP, () => ok([residencyRow({ is_current: false, move_out_date: '2025-05-01' })])]);
    await assert.rejects(() => endResidency({ siteCode: SITE, residencyId: 31, body: {}, actor }), (e) => e.code === 'RESIDENCY_NOT_CURRENT' && e.statusCode === 409);
    install();
    handlers.length = 0;
    handlers.push([RESIDENCY_LOOKUP, () => ok()]);
    await assert.rejects(() => endResidency({ siteCode: SITE, residencyId: 31, body: {}, actor }), (e) => e.code === 'RESIDENCY_NOT_FOUND');
  });
});

describe('H10: kisiyi pasiflestirme once site\'i esitler, tum daireleri kilitleyip kapatir, araclari pasiflestirir', () => {
  const lock = /^SELECT sp\.id, sp\.user_code, sp\.full_name, sp\.phone, sp\.email, sp\.note, sp\.is_active, u\.email AS account_email FROM site_people sp LEFT JOIN users u ON u\.user_code = sp\.user_code WHERE sp\.id = \$1 AND sp\.site_code = \$2 FOR UPDATE OF sp$/;
  const CURRENT = /^SELECT r\.id, r\.apartment_id, r\.person_id, r\.relation FROM apartment_residencies r WHERE r\.person_id = \$1 AND r\.is_current = TRUE ORDER BY r\.id FOR UPDATE$/;

  it('esitleme (TUM adimlar) iliski listesinden ONCE ayni transaction\'da calisir; her daire icin kilit + erisim kapanisi', async () => {
    closeHandlers();
    handlers.unshift(
      [lock, () => ok([{ id: '5', user_code: 30001, full_name: null, phone: null, email: null, note: null, is_active: true, account_email: 'ali@example.com' }])],
      [CURRENT, () => ok([{ id: '31', apartment_id: '9', person_id: '5', relation: 'owner' }, { id: '32', apartment_id: '10', person_id: '5', relation: 'resident' }])],
    );
    await updatePerson({ siteCode: SITE, personId: 5, body: { is_active: false }, actor });
    const stepIndexes = log.map((q, i) => (STEP_SQLS.has(q.sql) ? i : -1)).filter((i) => i >= 0);
    assert.equal(stepIndexes.length, SYNC_STEPS.length, 'esitlemenin tum adimlari calisti');
    assert.ok(stepIndexes.every((i) => log[i].inTx && i < at(CURRENT)), 'esitleme, kapatma listesinden once ve transaction icinde');
    assert.deepEqual(log[stepIndexes[0]].params, [SITE, null]);
    assert.deepEqual(findAll(APT_LOCK).map((q) => Number(q.params[0])), [9, 10], 'her iliski icin daire kilitlendi');
    assert.deepEqual(findAll(MEMBER_OFF).map((q) => q.params.map(Number)), [[9, 30001], [10, 30001]]);
    assert.ok(has(PERSON_OFF));
    assert.ok(has(VEHICLES_OFF), 'kisi pasif olunca araclar da pasif');
    assert.ok(has(ROTATION));
  });

  it('esitleme YALNIZ pasiflestirmede calisir (diger duzenlemelerde yok)', async () => {
    closeHandlers();
    handlers.unshift([lock, () => ok([{ id: '5', user_code: null, full_name: 'Ali', phone: null, email: null, note: null, is_active: true, account_email: null }])], [/^UPDATE site_people SET note/, () => ok()]);
    await updatePerson({ siteCode: SITE, personId: 5, body: { note: 'x' }, actor });
    assert.equal(log.some((q) => STEP_SQLS.has(q.sql)), false);
  });

  it('iliskisi olmayan kisi pasiflestirilirse de araclari pasiflesir', async () => {
    closeHandlers();
    handlers.unshift(
      [lock, () => ok([{ id: '5', user_code: null, full_name: 'Ali', phone: null, email: null, note: null, is_active: true, account_email: null }])],
      [CURRENT, () => ok()],
    );
    await updatePerson({ siteCode: SITE, personId: 5, body: { is_active: false }, actor });
    assert.ok(has(VEHICLES_OFF));
    assert.equal(has(MEMBER_SELECT), false);
  });
});
