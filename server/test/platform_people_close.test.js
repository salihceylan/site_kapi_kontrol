// Kisi ve Daire Kayitlari: "Tasindi" / pasiflestirme (H3, H10, S2-S4) - erisimin gercekten kapanmasi (DB'siz, KATI betikli sahte veritabani).
//
// CRM tasinmasi mevcut uye cikarma akisinin (membership_service.removeApartmentMember) yan etkilerini YENIDEN KULLANIR:
// yonetici devri (handOverApartmentResident), manuel kapi izni temizligi (cleanupDoorOverridesIfNoMembership). Kilit sirasi:
// site kilidi -> apartments (daire satiri, iliski/kisi satirlarindan ONCE) -> users -> kisi/iliski/arac. Son iliski bitince kisi
// pasif olur ve hesaptan KOPAR (anlik kopya). SQL'in gercek anlami gercek-PG betigi (scripts/qa_platform_pg.mjs, bolum "people").
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
const PRE_READ = /^SELECT r\.apartment_id FROM apartment_residencies r INNER JOIN site_people sp ON sp\.id = r\.person_id WHERE r\.id = \$1 AND sp\.site_code = \$2$/;
const APT_FIRST_LOCK = /^SELECT id FROM apartments WHERE id = \$1 FOR UPDATE$/;
const APT_LOCK = /^SELECT id, site_code, resident_user_code, resident_email FROM apartments WHERE id = \$1 FOR UPDATE$/;
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
const SNAPSHOT_SELECT = /^SELECT sp\.id, sp\.user_code, sp\.is_active, sp\.full_name, sp\.phone, sp\.email, u\.full_name AS account_name, u\.phone_number AS account_phone, u\.email AS account_email FROM site_people sp LEFT JOIN users u ON u\.user_code = sp\.user_code WHERE sp\.id = \$1 FOR UPDATE OF sp$/;
const PERSON_OFF = /^UPDATE site_people SET is_active = FALSE, user_code = NULL, full_name = \$2, phone = \$3, email = \$4, updated_at = NOW\(\) WHERE id = \$1 AND is_active = TRUE RETURNING id$/;
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
 *  otherAdmin / remainingMember: handOver icin; internalOff: dahili hesap pasiflesti mi; remaining: baska guncel iliski var mi;
 *  snapshot: kisi satiri + hesap bilgisi (anlik kopya icin).
 */
function closeHandlers({
  member = { role: 'FAMILY_MEMBER', is_active: true },
  indicator = null,
  residentEmail = null,
  otherAdmin = false,
  remainingMember = false,
  internalOff = false,
  remaining = false,
  vehicles = [],
  snapshot = { id: '5', user_code: 30001, is_active: true, full_name: null, phone: null, email: null, account_name: 'Ali Hesap', account_phone: '+905551112233', account_email: 'ali@example.com' },
} = {}) {
  handlers.push(
    [PRE_READ, () => ok([{ apartment_id: '9' }])],
    [APT_FIRST_LOCK, (_sql, params) => ok([{ id: String(params[0]) }])],
    [RESIDENCY_LOOKUP, () => ok([residencyRow()])],
    [APT_LOCK, (_sql, params) => ok([{ id: String(params[0]), site_code: String(SITE), resident_user_code: indicator, resident_email: residentEmail }])],
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
    [SNAPSHOT_SELECT, () => ok([snapshot])],
    [PERSON_OFF, () => ok([{ id: '5' }])],
    [VEHICLES_OFF, () => ok(vehicles)],
    [ROTATION, () => ok()],
    [DETAIL_PERSON, () => ok([{ id: '5', user_code: null, is_active: false, note: null, created_at: new Date('2026-10-14T08:00:00.000Z'), full_name: 'Ali', phone: null, email: null, has_account: false, account_kind: 'none' }])],
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

describe('H3/S4: "Tasindi" mevcut uye cikarma akisinin yan etkilerini uygular; kilit sirasi daire -> iliski/kisi', () => {
  it('KILIT SIRASI: daire satiri, iliski/kisi satirlarindan ONCE kilitlenir (kilitsiz on okuma -> daire FOR UPDATE -> iliski FOR UPDATE); sonra uyelik FOR UPDATE', async () => {
    closeHandlers();
    await endResidency({ siteCode: SITE, residencyId: 31, body: {}, actor });
    assert.deepEqual(find(PRE_READ).params, [31, SITE], 'on okuma site kapsamli');
    assert.equal(find(PRE_READ).inTx, true);
    assert.equal(Number(find(APT_FIRST_LOCK).params[0]), 9);
    assert.ok(at(PRE_READ) < at(APT_FIRST_LOCK), 'once kilitsiz okuma');
    assert.ok(at(APT_FIRST_LOCK) < at(RESIDENCY_LOOKUP), 'daire kilidi iliski satiri kilidinden ONCE (apartments -> iliski)');
    assert.ok(at(RESIDENCY_LOOKUP) < at(RESIDENCY_END));
    assert.ok(at(RESIDENCY_END) < at(MEMBER_SELECT));
    assert.ok(at(MEMBER_SELECT) < at(MEMBER_OFF));
    assert.deepEqual(find(MEMBER_OFF).params.map(Number), [9, 30001], 'yalniz O daire ve O kullanici');
    // kullanici satiri (dahili hesap pasiflestirme) iliski/kisi yazimlarindan ONCE, kisi satiri en SONA yakin
    assert.ok(at(MEMBER_OFF) < at(INTERNAL_OFF));
    assert.ok(at(INTERNAL_OFF) < at(SNAPSHOT_SELECT), 'users -> site_people sirasi');
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

  it('S3: gosterge BASKA kisiye (ornegin dahili hesap I) aitken kayitli yonetici R tasininca gosterge/PIN KORUNUR (yalniz admin rolu devredilir)', async () => {
    // R APARTMENT_ADMIN ama apartments.resident_user_code = 40000 (I): R'nin tasinmasi I'nin gostergesini/PIN'ini silmemeli
    closeHandlers({ member: { role: 'APARTMENT_ADMIN', is_active: true }, indicator: 40000, otherAdmin: false, remainingMember: true });
    await endResidency({ siteCode: SITE, residencyId: 31, body: {}, actor });
    assert.ok(has(OTHER_ADMIN), 'devir calisti');
    assert.deepEqual(find(PROMOTE).params.map(Number), [9, 30003], 'admin rolu en eski aktif uyeye devredildi');
    assert.equal(has(INDICATOR_SET), false, 'gosterge DEGISTIRILMEDI (I korunur)');
    assert.equal(has(INDICATOR_CLEAR), false, 'gosterge/PIN temizlenmedi');

    install();
    handlers.length = 0;
    closeHandlers({ member: { role: 'APARTMENT_ADMIN', is_active: true }, indicator: 40000, otherAdmin: true });
    await endResidency({ siteCode: SITE, residencyId: 31, body: {}, actor });
    assert.equal(has(INDICATOR_SET) || has(INDICATOR_CLEAR), false, 'baska admin varken de gosterge degismez');

    install();
    handlers.length = 0;
    closeHandlers({ member: { role: 'APARTMENT_ADMIN', is_active: true }, indicator: 40000 });
    await endResidency({ siteCode: SITE, residencyId: 31, body: {}, actor });
    assert.equal(has(INDICATOR_CLEAR), false, 'kimse kalmasa da baskasinin gostergesi/PIN\'i silinmez');
  });

  it('S3: ASKIYA ALINMIS (pasif) yonetici uyeligi devri tetiklemez; yalniz AKTIF yonetici veya gosterge sahibi icin devir yapilir', async () => {
    closeHandlers({ member: { role: 'APARTMENT_ADMIN', is_active: false }, indicator: 40000 });
    await endResidency({ siteCode: SITE, residencyId: 31, body: {}, actor });
    assert.equal(has(OTHER_ADMIN), false, 'devir hic cagrilmadi');
    assert.equal(has(MEMBER_OFF), false, 'zaten pasif uyelik yeniden guncellenmez');

    install();
    handlers.length = 0;
    closeHandlers({ member: { role: 'FAMILY_MEMBER', is_active: true }, indicator: 40000 });
    await endResidency({ siteCode: SITE, residencyId: 31, body: {}, actor });
    assert.equal(has(OTHER_ADMIN), false, 'aile uyesi tasininca devir yok');
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

  it('HESAPSIZ kisi: uyelik/kapi sorgusu hic calismaz; anahtar donmez; daire kilidi yine ILK alinir', async () => {
    closeHandlers();
    handlers.unshift([RESIDENCY_LOOKUP, () => ok([residencyRow({ user_code: null })])]);
    await endResidency({ siteCode: SITE, residencyId: 31, body: {}, actor });
    assert.equal(has(MEMBER_SELECT) || has(MEMBER_OFF) || has(OVERRIDE_CLEANUP) || has(INTERNAL_OFF), false);
    assert.equal(has(ROTATION), false);
    assert.ok(has(APT_FIRST_LOCK) && has(APT_LOCK), 'daire kilidi hesapsizda da alinir (tutarli kilit sirasi)');
  });

  it('S2b: son guncel iliski bitince kisi PASIF olur ve HESAPTAN KOPAR: ad/telefon/e-posta anlik kopyasi yazilir, user_code NULL; ARACLAR pasiflesir (kayit silinmez, vehicle.removed audit)', async () => {
    closeHandlers({ vehicles: [{ id: '4', plate: '34ABC123' }, { id: '5', plate: '06XYZ99' }] });
    await endResidency({ siteCode: SITE, residencyId: 31, body: {}, actor });
    const off = find(PERSON_OFF);
    assert.deepEqual([Number(off.params[0]), ...off.params.slice(1)], [5, 'Ali Hesap', '+905551112233', 'ali@example.com'], 'users tablosundaki o anki ad/telefon/e-posta kopyalandi');
    assert.match(off.sql, /user_code = NULL/, 'hesapla canli bag kesildi');
    assert.deepEqual(find(VEHICLES_OFF).params.map(Number), [5]);
    assert.equal(has(/DELETE FROM (site_people|apartment_residencies|vehicles)/), false, 'CRM kayitlari silinmez');
    assert.deepEqual(auditActions(), ['residency.ended', 'person.deactivated', 'vehicle.removed', 'vehicle.removed']);
    assert.deepEqual(auditDetails('person.deactivated'), { reason: 'residency_ended' });
    const removed = findAll(/^INSERT INTO audit_log/).filter((q) => q.params[3] === 'vehicle.removed');
    assert.deepEqual(removed.map((q) => q.params[6]), ['4', '5']);
    assert.deepEqual(JSON.parse(removed[0].params[7]), { plate: '34ABC123', person_id: 5, reason: 'residency_ended' });
  });

  it('S2b: dahili daire hesabinda kopya, TASINMADAN ONCE okunan GUNCEL iletisim e-postasidir (apartments.resident_email); ad/telefon users\'tan', async () => {
    closeHandlers({
      member: null,
      indicator: 30001,
      residentEmail: 'iletisim@example.com',
      internalOff: true,
      snapshot: { id: '5', user_code: 30001, is_active: true, full_name: null, phone: null, email: 'eski.kopya@example.com', account_name: 'Dahili Sakin', account_phone: null, account_email: 'a-blok-2@ahbu.local' },
    });
    await endResidency({ siteCode: SITE, residencyId: 31, body: {}, actor });
    assert.deepEqual([Number(find(PERSON_OFF).params[0]), ...find(PERSON_OFF).params.slice(1)], [5, 'Dahili Sakin', null, 'iletisim@example.com']);
  });

  it('S2b: hesapsiz kisi pasiflesirken mevcut CRM alanlari aynen kalir (kopya = kendi degerleri)', async () => {
    closeHandlers({ snapshot: { id: '5', user_code: null, is_active: true, full_name: 'Hesapsiz Ali', phone: '+905321112233', email: 'h@example.com', account_name: null, account_phone: null, account_email: null } });
    handlers.unshift([RESIDENCY_LOOKUP, () => ok([residencyRow({ user_code: null })])]);
    await endResidency({ siteCode: SITE, residencyId: 31, body: {}, actor });
    assert.deepEqual([Number(find(PERSON_OFF).params[0]), ...find(PERSON_OFF).params.slice(1)], [5, 'Hesapsiz Ali', '+905321112233', 'h@example.com']);
  });

  it('baska guncel iliskisi kalan kisi aktif kalir (kopyalanmaz/kopmaz), araclari pasiflesmez', async () => {
    closeHandlers({ remaining: true });
    await endResidency({ siteCode: SITE, residencyId: 31, body: {}, actor });
    assert.equal(has(SNAPSHOT_SELECT), false);
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
    closeHandlers();
    handlers.unshift([RESIDENCY_LOOKUP, () => ok([residencyRow({ is_current: false, move_out_date: '2025-05-01' })])]);
    await assert.rejects(() => endResidency({ siteCode: SITE, residencyId: 31, body: {}, actor }), (e) => e.code === 'RESIDENCY_NOT_CURRENT' && e.statusCode === 409);
    install();
    handlers.length = 0;
    handlers.push([PRE_READ, () => ok()], [RESIDENCY_LOOKUP, () => ok()]);
    await assert.rejects(() => endResidency({ siteCode: SITE, residencyId: 31, body: {}, actor }), (e) => e.code === 'RESIDENCY_NOT_FOUND');
  });

  it('S4: 40P01 (deadlock) TEK SEFER bastan denenir - ikinci denemede basarili olur; ikinci kez olursa hata yukari gider', async () => {
    closeHandlers();
    let lookups = 0;
    handlers.unshift([
      RESIDENCY_LOOKUP,
      () => {
        lookups += 1;
        if (lookups === 1) throw Object.assign(new Error('deadlock detected'), { code: '40P01' });
        return ok([residencyRow()]);
      },
    ]);
    await endResidency({ siteCode: SITE, residencyId: 31, body: {}, actor });
    assert.equal(lookups, 2, 'islem bir kez yeniden denendi');
    assert.equal(log.filter((q) => q.sql === 'BEGIN').length, 2);
    assert.equal(log.filter((q) => q.sql === 'ROLLBACK').length, 1, 'ilk deneme geri alindi');
    assert.equal(log.filter((q) => q.sql === 'COMMIT').length, 1);

    install();
    handlers.length = 0;
    closeHandlers();
    handlers.unshift([
      RESIDENCY_LOOKUP,
      () => {
        throw Object.assign(new Error('deadlock detected'), { code: '40P01' });
      },
    ]);
    await assert.rejects(() => endResidency({ siteCode: SITE, residencyId: 31, body: {}, actor }), (error) => error.code === '40P01');
    assert.equal(log.filter((q) => q.sql === 'BEGIN').length, 2, 'en fazla bir yeniden deneme');
  });
});

describe('H10/S4: kisiyi pasiflestirme once site\'i esitler, bilinen daireleri id sirasiyla kilitler, tum daireleri kapatir, araclari pasiflestirir', () => {
  const lock = /^SELECT sp\.id, sp\.user_code, sp\.full_name, sp\.phone, sp\.email, sp\.note, sp\.is_active, u\.email AS account_email FROM site_people sp LEFT JOIN users u ON u\.user_code = sp\.user_code WHERE sp\.id = \$1 AND sp\.site_code = \$2 FOR UPDATE OF sp$/;
  const CURRENT = /^SELECT r\.id, r\.apartment_id, r\.person_id, r\.relation FROM apartment_residencies r WHERE r\.person_id = \$1 AND r\.is_current = TRUE ORDER BY r\.id FOR UPDATE$/;
  const KNOWN = /^SELECT DISTINCT r\.apartment_id FROM apartment_residencies r INNER JOIN site_people sp ON sp\.id = r\.person_id WHERE r\.person_id = \$1 AND sp\.site_code = \$2 AND r\.is_current = TRUE ORDER BY r\.apartment_id$/;
  const KNOWN_LOCK = /^SELECT id FROM apartments WHERE id = ANY\(\$1::BIGINT\[\]\) ORDER BY id FOR UPDATE$/;

  it('KILIT SIRASI: bilinen daireler (id sirasiyla) kisi satirindan ve esitlemeden ONCE kilitlenir; esitleme (TUM adimlar) iliski listesinden once; her daire kilit + erisim kapanisi', async () => {
    closeHandlers();
    handlers.unshift(
      [KNOWN, () => ok([{ apartment_id: '9' }, { apartment_id: '10' }])],
      [KNOWN_LOCK, () => ok([{ id: '9' }, { id: '10' }])],
      [lock, () => ok([{ id: '5', user_code: 30001, full_name: null, phone: null, email: null, note: null, is_active: true, account_email: 'ali@example.com' }])],
      [CURRENT, () => ok([{ id: '31', apartment_id: '9', person_id: '5', relation: 'owner' }, { id: '32', apartment_id: '10', person_id: '5', relation: 'resident' }])],
    );
    await updatePerson({ siteCode: SITE, personId: 5, body: { is_active: false }, actor });
    assert.deepEqual(find(KNOWN_LOCK).params[0].map(Number), [9, 10], 'id sirasiyla');
    assert.ok(at(KNOWN) < at(KNOWN_LOCK) && at(KNOWN_LOCK) < at(lock), 'daire kilitleri kisi satiri kilidinden ONCE');
    const stepIndexes = log.map((q, i) => (STEP_SQLS.has(q.sql) ? i : -1)).filter((i) => i >= 0);
    assert.equal(stepIndexes.length, SYNC_STEPS.length, 'esitlemenin tum adimlari calisti');
    assert.ok(stepIndexes.every((i) => log[i].inTx && i < at(CURRENT)), 'esitleme, kapatma listesinden once ve transaction icinde');
    assert.ok(stepIndexes.every((i) => i > at(KNOWN_LOCK)), 'esitleme daire kilitlerinden SONRA');
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
    assert.equal(has(KNOWN_LOCK), false);
  });

  it('iliskisi olmayan kisi pasiflestirilirse de pasif + hesaptan kopar + araclari pasiflesir', async () => {
    closeHandlers({ snapshot: { id: '5', user_code: null, is_active: true, full_name: 'Ali', phone: null, email: null, account_name: null, account_phone: null, account_email: null } });
    handlers.unshift(
      [KNOWN, () => ok()],
      [lock, () => ok([{ id: '5', user_code: null, full_name: 'Ali', phone: null, email: null, note: null, is_active: true, account_email: null }])],
      [CURRENT, () => ok()],
    );
    await updatePerson({ siteCode: SITE, personId: 5, body: { is_active: false }, actor });
    assert.ok(has(PERSON_OFF));
    assert.ok(has(VEHICLES_OFF));
    assert.equal(has(MEMBER_SELECT), false);
    assert.equal(has(KNOWN_LOCK), false, 'bilinen daire yok -> daire kilidi sorgusu yok');
  });
});
