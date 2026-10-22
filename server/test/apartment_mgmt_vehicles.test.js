// Daire araclari ("Dairem > Araclarim"): daire admini ekler / not duzenler / cikarir, aile uyesi ve admin olmayan malik yalniz gorur,
// site yoneticisi de yazar (limit 8), baska daire 404, limit, tekil plaka, mesaj sizdirmama. DB gerektirmez (durumlu sahte veritabani).
import { describe, it, beforeEach, afterEach, mock } from 'node:test';
import assert from 'node:assert/strict';
import { pool } from '../src/db.js';
import {
  ADMIN_VEHICLE_LIMIT,
  MANAGER_VEHICLE_LIMIT,
  PLATE_RECOGNITION_NOTICE,
  createApartmentVehicle,
  listApartmentVehicles,
  ownerOptions,
  parseVehicleNote,
  pickOwner,
  plateConflict,
  removeApartmentVehicle,
  updateApartmentVehicle,
  vehicleAccess,
  vehicleLimitFor,
} from '../src/modules/apartment_mgmt_vehicles.js';
import { requireTrPlate } from '../src/modules/plate_recognition_common.js';

const SITE = 1000000001;
const norm = (text) => String(text).replace(/\s+/g, ' ').trim();
const ok = (rows = []) => ({ rows, rowCount: rows.length });

const user = (code, extra = {}) => ({ id: code, user_code: code, userCode: code, role: 'apartment_owner', full_name: `Kullanici ${code}`, ...extra });
const ADMIN = user(101, { full_name: 'Ali Admin' });
const FAMILY = user(102, { full_name: 'Ayse Aile' });
const STRANGER = user(999, { full_name: 'Baska Daire' });
const SITE_MANAGER = user(500, { role: 'site_manager', full_name: 'Site Yoneticisi' });
const OTHER_SITE_MANAGER = user(501, { role: 'site_manager', full_name: 'Baska Site Yoneticisi' });
const SUPER = user(1, { role: 'super_user', full_name: 'Super' });

let world;
let log;

function freshWorld() {
  return {
    apartment: { id: '9', site_code: String(SITE), unit_label: 'Daire 2', resident_user_code: null, is_active: true, block_name: 'A Blok', site_name: 'Gul Sitesi', approval_status: 'approved' },
    members: [
      { user_code: '101', role: 'APARTMENT_ADMIN', is_active: true, created_at: '2026-01-01', full_name: 'Ali Admin' },
      { user_code: '102', role: 'FAMILY_MEMBER', is_active: true, created_at: '2026-01-02', full_name: 'Ayse Aile' },
    ],
    residencies: [
      { id: '1', person_id: '5', relation: 'owner', origin: 'manual', sponsor_person_id: null, is_minor: false, move_in_date: null, user_code: '101', person_active: true, name: 'Ali Admin', account_kind: 'user' },
      { id: '2', person_id: '6', relation: 'family_member', origin: 'manual', sponsor_person_id: null, is_minor: false, move_in_date: null, user_code: '102', person_active: true, name: 'Ayse Aile', account_kind: 'user' },
    ],
    vehicles: [],
    nextId: 1,
    managerOf: new Set([`${SITE}:500`]),
    suspended: new Set(),
    audit: [],
  };
}

const vehicle = (id, plate, extra = {}) => ({
  id, site_code: SITE, plate, plate_display: plate, note: null, person_id: '5', apartment_id: '9', is_active: true, person_name: 'Ali Admin', ...extra,
});

function run(text, params = []) {
  const sql = norm(text);
  log.push({ sql, params });
  if (/^(BEGIN|COMMIT|ROLLBACK)$/.test(sql) || /^SELECT pg_advisory_xact_lock/.test(sql) || /SAVEPOINT/.test(sql)) return ok();
  if (/^INSERT INTO audit_log/.test(sql)) {
    world.audit.push({ actor: params[0], actor_name: params[1], action: params[3], target_id: params[6], details: JSON.parse(params[7]) });
    return ok();
  }
  if (/FROM apartments a LEFT JOIN site_blocks b/.test(sql)) {
    return params[0] === Number(world.apartment.id) ? ok([world.apartment]) : ok();
  }
  if (/FROM apartment_memberships am INNER JOIN users u/.test(sql)) return ok(world.members);
  if (/FROM apartment_residencies r INNER JOIN site_people sp ON sp\.id = r\.person_id LEFT JOIN users u/.test(sql)) return ok(world.residencies);
  if (/FROM site_manager_sites/.test(sql)) return ok(world.managerOf.has(`${params[0]}:${params[1]}`) ? [{ '?column?': 1 }] : []);
  if (/FROM site_memberships/.test(sql)) return ok();
  if (/FROM apartment_link_requests/.test(sql)) return ok();
  if (/FROM apartment_access_suspensions/.test(sql)) return ok(world.suspended.has(params[1]) ? [{ '?column?': 1 }] : []);
  if (/^SELECT DISTINCT ON \(target_id\) target_id, actor_name/.test(sql)) {
    const rows = world.audit
      .filter((a) => a.action === 'vehicle.added' && params[1].includes(a.target_id))
      .map((a) => ({ target_id: a.target_id, actor_name: a.actor_name, source: a.details.source ?? null }));
    return ok(rows);
  }
  if (/^SELECT v\.id, v\.plate, v\.plate_display, v\.note, v\.person_id, v\.apartment_id/.test(sql)) {
    const [site, apt, only] = params;
    const people = new Set(world.residencies.map((r) => r.person_id));
    let rows = world.vehicles.filter(
      (v) => v.site_code === site && v.is_active && (String(v.apartment_id) === String(apt) || (v.apartment_id === null && people.has(String(v.person_id)))),
    );
    if (/AND v\.id = \$3/.test(sql)) rows = rows.filter((v) => Number(v.id) === Number(only));
    return ok(rows);
  }
  if (/^SELECT id, person_id, apartment_id FROM vehicles WHERE site_code = \$1 AND plate = \$2 AND is_active = TRUE/.test(sql)) {
    return ok(world.vehicles.filter((v) => v.site_code === params[0] && v.plate === params[1] && v.is_active).slice(0, 1));
  }
  if (/^INSERT INTO vehicles/.test(sql)) {
    const [site, person, apt, plate, display, note] = params;
    if (world.vehicles.some((v) => v.site_code === site && v.plate === plate && v.is_active)) throw Object.assign(new Error('dup'), { code: '23505' });
    const id = 100 + world.nextId++;
    world.vehicles.push(vehicle(id, plate, { plate_display: display, note, person_id: String(person), apartment_id: String(apt), person_name: 'Ad' }));
    return ok([{ id: String(id) }]);
  }
  if (/^UPDATE vehicles SET note = \$2 WHERE id = \$1/.test(sql)) {
    world.vehicles.find((v) => Number(v.id) === Number(params[0])).note = params[1];
    return ok();
  }
  if (/^UPDATE vehicles SET person_id = \$2 WHERE id = \$1/.test(sql)) {
    world.vehicles.find((v) => Number(v.id) === Number(params[0])).person_id = String(params[1]);
    return ok();
  }
  if (/^UPDATE vehicles SET is_active = FALSE WHERE id = \$1/.test(sql)) {
    world.vehicles.find((v) => Number(v.id) === Number(params[0])).is_active = false;
    return ok();
  }
  throw new Error(`BEKLENMEYEN SQL (sahte DB kati): ${sql.slice(0, 200)}`);
}

beforeEach(() => {
  world = freshWorld();
  log = [];
  pool.query = async (text, params) => run(text, params);
  pool.connect = async () => ({ query: async (text, params) => run(text, params), release() {} });
  mock.method(console, 'error', () => {});
});

afterEach(() => {
  delete pool.query;
  delete pool.connect;
  mock.restoreAll();
});

const code = (c, status) => (e) => e.code === c && (status === undefined || e.statusCode === status);
const added = () => world.audit.filter((a) => a.action === 'vehicle.added');

describe('arac kurallari (saf)', () => {
  it('limitler: daire admini 4, site yoneticisi 8', () => {
    assert.equal(ADMIN_VEHICLE_LIMIT, 4);
    assert.equal(MANAGER_VEHICLE_LIMIT, 8);
    assert.equal(vehicleLimitFor('admin'), 4);
    assert.equal(vehicleLimitFor('manager'), 8);
  });
  it('plaka gecerli Turk plakasi olmali (il kodu 01-81, 1-3 harf, 2-4 rakam)', () => {
    assert.equal(requireTrPlate('34 abc 123'), '34ABC123');
    assert.equal(requireTrPlate('06-A-1234'), '06A1234');
    for (const bad of ['99 AB 123', '00 AB 123', '34 ABCD 123', '34 AB 1', '34 AB 12345', 'ABC123', '', null]) {
      assert.throws(() => requireTrPlate(bad), code('PLATE_INVALID', 400), String(bad));
    }
  });
  it('not: bos null, en cok 200 karakter, metin olmali', () => {
    assert.equal(parseVehicleNote('  beyaz  '), 'beyaz');
    assert.equal(parseVehicleNote('   '), null);
    assert.equal(parseVehicleNote(undefined), null);
    assert.throws(() => parseVehicleNote('x'.repeat(201)), code('INVALID_BODY', 400));
    assert.throws(() => parseVehicleNote(5), code('INVALID_BODY', 400));
  });
  it('yazma yetkisi: yonetici her zaman; sakin yalniz daire admini ve askiya alinmamissa', () => {
    assert.equal(vehicleAccess({ kind: 'manager' }).canManage, true);
    assert.equal(vehicleAccess({ kind: 'manager' }).limit, 8);
    assert.equal(vehicleAccess({ kind: 'member', me: { is_admin: true } }).canManage, true);
    assert.equal(vehicleAccess({ kind: 'member', me: { is_admin: true } }).limit, 4);
    assert.equal(vehicleAccess({ kind: 'member', me: { is_admin: true, suspended: true } }).canManage, false);
    assert.equal(vehicleAccess({ kind: 'member', me: { is_admin: false, is_owner: true } }).canManage, false);
    assert.equal(vehicleAccess({ kind: 'member', me: { is_admin: false } }).kind, 'member');
  });
  it('plaka cakisma iletisi baska kaydin bilgisini sizdirmaz', () => {
    const elsewhere = plateConflict({ sameApartment: false });
    assert.equal(elsewhere.message, 'Bu plaka başka bir kayıtta kullanılıyor; site yönetimiyle görüşün.');
    assert.doesNotMatch(elsewhere.message, /daire|blok|kişi|sakin/i);
    assert.equal(elsewhere.code, 'PLATE_IN_USE');
    assert.equal(plateConflict({ sameApartment: true }).code, 'PLATE_EXISTS');
  });
  it('sahip: yalniz dairenin aktif sakinleri; varsayilan admin', () => {
    const state = {
      roles: { adminUserCode: 101 },
      residencies: [
        { person_id: 5, user_code: 101, name: 'Ali', person_active: true },
        { person_id: 6, user_code: 102, name: 'Ayse', person_active: true },
        { person_id: 7, user_code: null, name: 'Pasif', person_active: false },
      ],
    };
    assert.deepEqual(ownerOptions(state).map((o) => [o.person_id, o.is_default]), [[5, true], [6, false]]);
    assert.equal(pickOwner(state, undefined), 5);
    assert.equal(pickOwner(state, '6'), 6);
    assert.throws(() => pickOwner(state, 7), code('NOT_AN_ACTIVE_RESIDENT', 409));
    assert.throws(() => pickOwner(state, 44), code('NOT_AN_ACTIVE_RESIDENT', 409));
    assert.throws(() => pickOwner(state, 'x'), code('INVALID_BODY', 400));
  });
});

describe('daire admini: ekler, not duzenler, cikarir', () => {
  it('ekleme: plaka normalize + gosterim, daireye baglanir, audit maskeli ve kaynak daire admini', async () => {
    const out = await createApartmentVehicle({ authUser: ADMIN, apartmentId: 9, body: { plate: '34 abc 123', note: ' beyaz Fiat ' } });
    assert.equal(out.vehicle.plate, '34ABC123');
    assert.equal(out.vehicle.plate_display, '34 ABC 123');
    assert.equal(out.vehicle.note, 'beyaz Fiat');
    assert.equal(out.vehicle.source, 'apartment_admin');
    assert.equal(out.vehicle.added_by, 'Ali Admin');
    const insert = log.find((q) => /^INSERT INTO vehicles/.test(q.sql));
    assert.deepEqual(insert.params, [SITE, 5, 9, '34ABC123', '34 ABC 123', 'beyaz Fiat']);
    assert.equal(added().length, 1);
    assert.deepEqual(added()[0].details, { plate: '34***23', person_id: 5, apartment_id: 9, source: 'apartment_admin' });
    assert.doesNotMatch(JSON.stringify(added()[0].details), /34ABC123/);
  });
  it('ekleme: sahip olarak dairenin baska aktif sakini secilebilir; baska dairenin kisisi 409', async () => {
    const out = await createApartmentVehicle({ authUser: ADMIN, apartmentId: 9, body: { plate: '35 XY 99', person_id: 6 } });
    assert.equal(out.vehicle.person_id, 6);
    await assert.rejects(() => createApartmentVehicle({ authUser: ADMIN, apartmentId: 9, body: { plate: '35 XY 98', person_id: 77 } }), code('NOT_AN_ACTIVE_RESIDENT', 409));
  });
  it('gecersiz plaka 400; yazma yapilmaz', async () => {
    await assert.rejects(() => createApartmentVehicle({ authUser: ADMIN, apartmentId: 9, body: { plate: '99 ZZ 1' } }), code('PLATE_INVALID', 400));
    assert.equal(log.some((q) => /^INSERT INTO vehicles/.test(q.sql)), false);
  });
  it('not duzenleme: vehicle.updated audit (plaka maskeli, plaka degismez); degisiklik yoksa audit yok', async () => {
    world.vehicles.push(vehicle(11, '34ABC123'));
    const out = await updateApartmentVehicle({ authUser: ADMIN, apartmentId: 9, vehicleId: 11, body: { note: 'kirmizi' } });
    assert.equal(out.vehicle.note, 'kirmizi');
    assert.equal(out.vehicle.plate, '34ABC123');
    const upd = world.audit.filter((a) => a.action === 'vehicle.updated');
    assert.equal(upd.length, 1);
    assert.deepEqual(upd[0].details, { plate: '34***23', apartment_id: 9, changes: ['note'], source: 'apartment_admin' });
    await updateApartmentVehicle({ authUser: ADMIN, apartmentId: 9, vehicleId: 11, body: { note: 'kirmizi' } });
    assert.equal(world.audit.filter((a) => a.action === 'vehicle.updated').length, 1);
    await assert.rejects(() => updateApartmentVehicle({ authUser: ADMIN, apartmentId: 9, vehicleId: 11, body: {} }), code('INVALID_BODY', 400));
  });
  it('cikarma: pasife alinir (kayit kalir), vehicle.removed audit; ayni plaka yeniden eklenebilir', async () => {
    world.vehicles.push(vehicle(11, '34ABC123'));
    assert.deepEqual(await removeApartmentVehicle({ authUser: ADMIN, apartmentId: 9, vehicleId: 11 }), { ok: true });
    assert.equal(world.vehicles[0].is_active, false);
    assert.equal(log.some((q) => /DELETE FROM vehicles/.test(q.sql)), false);
    const removed = world.audit.filter((a) => a.action === 'vehicle.removed');
    assert.deepEqual(removed[0].details, { plate: '34***23', person_id: 5, apartment_id: 9, source: 'apartment_admin' });
    await createApartmentVehicle({ authUser: ADMIN, apartmentId: 9, body: { plate: '34 ABC 123' } });
    assert.equal(world.vehicles.filter((v) => v.is_active).length, 1);
  });
  it('liste: daire araclari + kaynak etiketi; eski kayit (apartment_id bos, sahibi sakin) site yonetimi sayilir ve audit sorgulanmaz', async () => {
    await createApartmentVehicle({ authUser: ADMIN, apartmentId: 9, body: { plate: '34 ABC 123' } });
    world.vehicles.push(vehicle(50, '06XY123', { apartment_id: null }));
    world.vehicles.push(vehicle(51, '35ZZ999', { apartment_id: '10' })); // baska daire
    const auditQueriesBefore = log.filter((q) => /^SELECT DISTINCT ON/.test(q.sql)).length;
    const out = await listApartmentVehicles({ authUser: ADMIN, apartmentId: 9 });
    assert.equal(out.can_manage, true);
    assert.equal(out.limit, 4);
    assert.equal(out.notice, PLATE_RECOGNITION_NOTICE);
    assert.deepEqual(out.items.map((i) => [i.plate, i.source]).sort(), [['06XY123', 'site_manager'], ['34ABC123', 'apartment_admin']]);
    assert.equal(out.items.find((i) => i.plate === '06XY123').added_by, null);
    assert.equal(log.filter((q) => /^SELECT DISTINCT ON/.test(q.sql)).length - auditQueriesBefore, 1); // yalniz apartment_id dolu satirlar icin tek sorgu
    assert.deepEqual(out.owners.map((o) => o.person_id), [5, 6]);
  });
});

describe('aile uyesi ve admin olmayan malik yalniz gorur; baska daire 404', () => {
  it('aile uyesi: liste gorur (can_manage false, sahip listesi bos); ekle / duzenle / cikar 403', async () => {
    world.vehicles.push(vehicle(11, '34ABC123'));
    const out = await listApartmentVehicles({ authUser: FAMILY, apartmentId: 9 });
    assert.equal(out.can_manage, false);
    assert.equal(out.items.length, 1);
    assert.deepEqual(out.owners, []);
    await assert.rejects(() => createApartmentVehicle({ authUser: FAMILY, apartmentId: 9, body: { plate: '35 XY 99' } }), code('FORBIDDEN_ROLE', 403));
    await assert.rejects(() => updateApartmentVehicle({ authUser: FAMILY, apartmentId: 9, vehicleId: 11, body: { note: 'x' } }), code('FORBIDDEN_ROLE', 403));
    await assert.rejects(() => removeApartmentVehicle({ authUser: FAMILY, apartmentId: 9, vehicleId: 11 }), code('FORBIDDEN_ROLE', 403));
    assert.equal(log.some((q) => /^(INSERT INTO vehicles|UPDATE vehicles)/.test(q.sql)), false);
  });
  it('malik kiraciya devretmisse (admin kiraci) malik yalniz gorur', async () => {
    world.members = [
      { user_code: '101', role: 'FAMILY_MEMBER', is_active: true, created_at: '2026-01-01', full_name: 'Ali Malik' },
      { user_code: '103', role: 'APARTMENT_ADMIN', is_active: true, created_at: '2026-02-01', full_name: 'Kemal Kiraci' },
    ];
    world.residencies = [
      { id: '1', person_id: '5', relation: 'owner', origin: 'manual', sponsor_person_id: null, is_minor: false, move_in_date: null, user_code: '101', person_active: true, name: 'Ali Malik', account_kind: 'user' },
      { id: '3', person_id: '8', relation: 'tenant', origin: 'manual', sponsor_person_id: null, is_minor: false, move_in_date: null, user_code: '103', person_active: true, name: 'Kemal Kiraci', account_kind: 'user' },
    ];
    const out = await listApartmentVehicles({ authUser: ADMIN, apartmentId: 9 });
    assert.equal(out.can_manage, false);
    await assert.rejects(() => createApartmentVehicle({ authUser: ADMIN, apartmentId: 9, body: { plate: '35 XY 99' } }), code('FORBIDDEN_ROLE', 403));
    const tenant = await createApartmentVehicle({ authUser: user(103), apartmentId: 9, body: { plate: '35 XY 99' } });
    assert.equal(tenant.vehicle.person_id, 8); // varsayilan sahip: admin (kiraci)
  });
  it('dairede bagi olmayan kullanici: 404 APARTMENT_NOT_FOUND (var oldugu sizdirilmaz)', async () => {
    for (const call of [
      () => listApartmentVehicles({ authUser: STRANGER, apartmentId: 9 }),
      () => createApartmentVehicle({ authUser: STRANGER, apartmentId: 9, body: { plate: '35 XY 99' } }),
      () => removeApartmentVehicle({ authUser: STRANGER, apartmentId: 9, vehicleId: 11 }),
    ]) {
      await assert.rejects(call, code('APARTMENT_NOT_FOUND', 404));
    }
    await assert.rejects(() => listApartmentVehicles({ authUser: ADMIN, apartmentId: 12345 }), code('APARTMENT_NOT_FOUND', 404));
  });
  it('baska sitenin yoneticisi dairede bagi yoksa 404; onaysiz site 404', async () => {
    await assert.rejects(() => createApartmentVehicle({ authUser: OTHER_SITE_MANAGER, apartmentId: 9, body: { plate: '35 XY 99' } }), code('APARTMENT_NOT_FOUND', 404));
    world.apartment.approval_status = 'pending';
    await assert.rejects(() => listApartmentVehicles({ authUser: ADMIN, apartmentId: 9 }), code('APARTMENT_NOT_FOUND', 404));
  });
  it('baska dairenin aracini (var olan id) duzenleme / cikarma 404 VEHICLE_NOT_FOUND', async () => {
    world.vehicles.push(vehicle(51, '35ZZ999', { apartment_id: '10' }));
    await assert.rejects(() => updateApartmentVehicle({ authUser: ADMIN, apartmentId: 9, vehicleId: 51, body: { note: 'x' } }), code('VEHICLE_NOT_FOUND', 404));
    await assert.rejects(() => removeApartmentVehicle({ authUser: ADMIN, apartmentId: 9, vehicleId: 51 }), code('VEHICLE_NOT_FOUND', 404));
    await assert.rejects(() => removeApartmentVehicle({ authUser: ADMIN, apartmentId: 9, vehicleId: 'abc' }), code('VEHICLE_NOT_FOUND', 404));
    assert.equal(world.vehicles[0].is_active, true);
  });
  it('kapi erisimi askiya alinmis admin yazamaz', async () => {
    world.suspended.add(101);
    await assert.rejects(() => createApartmentVehicle({ authUser: ADMIN, apartmentId: 9, body: { plate: '35 XY 99' } }), code('FORBIDDEN_ROLE', 403));
  });
});

describe('site yoneticisi de yazar (limit 8, kaynak site yonetimi)', () => {
  it('site yoneticisi dairede sakin olmadan arac ekler; super de ekler', async () => {
    const a = await createApartmentVehicle({ authUser: SITE_MANAGER, apartmentId: 9, body: { plate: '34 ABC 123' } });
    assert.equal(a.vehicle.source, 'site_manager');
    assert.equal(a.vehicle.added_by, null);
    assert.equal(added()[0].details.source, 'site_manager');
    const b = await createApartmentVehicle({ authUser: SUPER, apartmentId: 9, body: { plate: '34 ABC 124', person_id: 6 } });
    assert.equal(b.vehicle.person_id, 6);
    const list = await listApartmentVehicles({ authUser: SITE_MANAGER, apartmentId: 9 });
    assert.equal(list.can_manage, true);
    assert.equal(list.limit, 8);
  });
  it('limit: admin 4. aractan sonra 409 VEHICLE_LIMIT; site yoneticisi 8e kadar', async () => {
    for (let i = 0; i < 4; i += 1) {
      await createApartmentVehicle({ authUser: ADMIN, apartmentId: 9, body: { plate: `34 AB 10${i}` } });
    }
    await assert.rejects(
      () => createApartmentVehicle({ authUser: ADMIN, apartmentId: 9, body: { plate: '34 AB 200' } }),
      (e) => e.code === 'VEHICLE_LIMIT' && e.statusCode === 409 && e.extra.limit === 4,
    );
    for (let i = 4; i < 8; i += 1) {
      await createApartmentVehicle({ authUser: SITE_MANAGER, apartmentId: 9, body: { plate: `34 AB 10${i}` } });
    }
    await assert.rejects(
      () => createApartmentVehicle({ authUser: SITE_MANAGER, apartmentId: 9, body: { plate: '34 AB 201' } }),
      (e) => e.code === 'VEHICLE_LIMIT' && e.extra.limit === 8,
    );
    // Cikarilan arac yer acar.
    await removeApartmentVehicle({ authUser: ADMIN, apartmentId: 9, vehicleId: world.vehicles[0].id });
    await createApartmentVehicle({ authUser: SITE_MANAGER, apartmentId: 9, body: { plate: '34 AB 201' } });
  });
});

describe('tekil plaka ve mesaj sizdirmama', () => {
  it('plaka baska dairede aktifse genel mesaj; baska dairenin adi / dairesi / sahibi gecmez', async () => {
    world.vehicles.push(vehicle(51, '34ABC123', { apartment_id: '10', person_id: '77', person_name: 'Gizli Komsu' }));
    await assert.rejects(
      () => createApartmentVehicle({ authUser: ADMIN, apartmentId: 9, body: { plate: '34 abc 123' } }),
      (e) => {
        assert.equal(e.code, 'PLATE_IN_USE');
        assert.equal(e.statusCode, 409);
        assert.equal(e.message, 'Bu plaka başka bir kayıtta kullanılıyor; site yönetimiyle görüşün.');
        assert.doesNotMatch(`${e.message} ${JSON.stringify(e.extra ?? {})}`, /Gizli|Komşu|Blok|Daire|77|10/);
        return true;
      },
    );
    assert.equal(log.some((q) => /^INSERT INTO vehicles/.test(q.sql)), false);
  });
  it('plaka ayni dairede aktifse PLATE_EXISTS; pasif kayit engel olmaz', async () => {
    world.vehicles.push(vehicle(11, '34ABC123'));
    await assert.rejects(() => createApartmentVehicle({ authUser: ADMIN, apartmentId: 9, body: { plate: '34 ABC 123' } }), code('PLATE_EXISTS', 409));
    world.vehicles[0].is_active = false;
    await createApartmentVehicle({ authUser: ADMIN, apartmentId: 9, body: { plate: '34 ABC 123' } });
  });
  it('yaris: tekil indeks hatasi (23505) genel mesaja cevrilir', async () => {
    const original = pool.connect;
    pool.connect = async () => {
      const client = await original();
      return {
        release() {},
        query: async (text, params) => {
          if (/^INSERT INTO vehicles/.test(norm(text))) throw Object.assign(new Error('dup'), { code: '23505' });
          return client.query(text, params);
        },
      };
    };
    await assert.rejects(() => createApartmentVehicle({ authUser: ADMIN, apartmentId: 9, body: { plate: '35 XY 99' } }), code('PLATE_IN_USE', 409));
  });
});

describe('kaynak kontrolleri', () => {
  it('kapi / MQTT / firmware modullerine bagimlilik yok', async () => {
    const { readFileSync } = await import('node:fs');
    const { fileURLToPath } = await import('node:url');
    const source = readFileSync(fileURLToPath(new URL('../src/modules/apartment_mgmt_vehicles.js', import.meta.url)), 'utf8');
    const imports = source.split(String.fromCharCode(10)).filter((line) => /^import /.test(line)).join(' ');
    assert.doesNotMatch(imports, /mqtt|ble|firmware|door_command|device_command|door_service|gate/i);
  });
});
