// Site Yonetimi > Daireler: dairenin TUM guncel sakinleri + daire admini (GET /manager/sites/:siteCode/apartments/:id/household).
// Kok neden: yapi ucu daire satirina yalniz apartments.resident_user_code ile tek kisi veriyordu. DB gerektirmez (sahte db).
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { buildHousehold, getApartmentHousehold } from '../src/modules/apartment_mgmt_household.js';
import { mapApartmentRow } from '../src/utils/helpers.js';

const here = path.dirname(fileURLToPath(import.meta.url));
const read = (rel) => readFileSync(path.join(here, '..', rel), 'utf8');

const member = (user_code, role, extra = {}) => ({ user_code, role, is_active: true, created_at: '2026-01-01', full_name: `U${user_code}`, phone_number: null, ...extra });
const res = (person_id, user_code, relation, name, extra = {}) => ({
  id: person_id,
  person_id,
  user_code,
  relation,
  name,
  phone: null,
  is_minor: false,
  has_account: user_code !== null,
  ...extra,
});

describe('buildHousehold', () => {
  it('admin ust satirda, aile uyeleri altinda; kucukler yetiskinlerden sonra', () => {
    const h = buildHousehold({
      members: [member(1, 'APARTMENT_ADMIN'), member(2, 'FAMILY_MEMBER')],
      residencies: [
        res(10, 1, 'owner', 'Veli K', { phone: '0555' }),
        res(11, 2, 'family_member', 'Ayse K'),
        res(12, null, 'family_member', 'Cocuk K', { is_minor: true }),
        res(13, null, 'family_member', 'Anne K'),
      ],
      detailed: true,
    });
    assert.equal(h.admin.name, 'Veli K');
    assert.equal(h.admin.is_admin, true);
    assert.equal(h.admin.phone, '0555');
    assert.equal(h.absent_owner, null);
    assert.deepEqual(h.members.map((m) => m.name), ['Ayse K', 'Anne K', 'Cocuk K']);
    assert.equal(h.members[2].is_minor, true);
    assert.equal(h.members[1].has_account, false, 'hesapsiz aile uyesi');
    assert.equal(h.total, 4);
  });

  it('kiraci oturan dairede malik admin degilse "oturmuyor" ayri satir; kiraci admin', () => {
    const h = buildHousehold({
      members: [member(1, 'FAMILY_MEMBER'), member(2, 'APARTMENT_ADMIN')],
      residencies: [res(10, 1, 'owner', 'Malik M'), res(11, 2, 'tenant', 'Kiraci T'), res(12, null, 'family_member', 'Es T')],
      detailed: true,
    });
    assert.equal(h.admin.name, 'Kiraci T');
    assert.equal(h.admin.relation, 'tenant');
    assert.equal(h.absent_owner.name, 'Malik M');
    assert.deepEqual(h.members.map((m) => m.name), ['Es T']);
    assert.equal(h.total, 3);
  });

  it('malik admin kalip kiraci varsa kiraci uyeler arasindadir, malik "oturmuyor" sayilmaz', () => {
    const h = buildHousehold({
      members: [member(1, 'APARTMENT_ADMIN'), member(2, 'FAMILY_MEMBER')],
      residencies: [res(10, 1, 'owner', 'Malik M'), res(11, 2, 'tenant', 'Kiraci T')],
      detailed: true,
    });
    assert.equal(h.admin.name, 'Malik M');
    assert.equal(h.absent_owner, null);
    assert.deepEqual(h.members.map((m) => [m.name, m.relation]), [['Kiraci T', 'tenant']]);
  });

  it('tek kisili daire: yalniz admin, uye yok', () => {
    const h = buildHousehold({ members: [member(1, 'APARTMENT_ADMIN')], residencies: [res(10, 1, 'resident', 'Tek K')], detailed: true });
    assert.equal(h.admin.name, 'Tek K');
    assert.deepEqual(h.members, []);
    assert.equal(h.total, 1);
  });

  it('eski gosterge (resident_user_code) uyeliksiz admin sayilir ve listeden dusmez', () => {
    const h = buildHousehold({
      members: [],
      legacyUserCode: 7,
      residencies: [res(11, null, 'family_member', 'Cocuk', { is_minor: true })],
      extraUsers: new Map([[7, { full_name: 'Eski Sakin', phone_number: '0532' }]]),
      detailed: true,
    });
    assert.equal(h.admin.name, 'Eski Sakin');
    assert.equal(h.admin.person_id, null);
    assert.equal(h.admin.phone, '0532');
    assert.deepEqual(h.members.map((m) => m.name), ['Cocuk']);
    assert.equal(h.total, 2);
  });

  it('iliskisi esitlenmemis aktif uye listeye "sakin/aile uyesi" olarak girer (kimse dusmez)', () => {
    const h = buildHousehold({
      members: [member(1, 'APARTMENT_ADMIN'), member(2, 'FAMILY_MEMBER', { full_name: 'Yeni Uye' })],
      residencies: [],
      detailed: true,
    });
    assert.equal(h.total, 2);
    assert.equal(h.admin.name, 'U1');
    assert.deepEqual(h.members.map((m) => [m.name, m.relation]), [['Yeni Uye', 'family_member']]);
  });

  it('kapi erisimi askisi: acik askiya alma kaydi ya da pasife alinmis uyelik "access_suspended" olur', () => {
    const h = buildHousehold({
      members: [member(1, 'APARTMENT_ADMIN'), member(2, 'FAMILY_MEMBER', { is_active: false }), member(3, 'FAMILY_MEMBER')],
      residencies: [res(10, 1, 'owner', 'A'), res(11, 2, 'family_member', 'B'), res(12, 3, 'family_member', 'C')],
      suspended: new Set([3]),
      detailed: true,
    });
    const byName = Object.fromEntries(h.members.map((m) => [m.name, m.access_suspended]));
    assert.deepEqual(byName, { B: true, C: true });
    assert.equal(h.admin.access_suspended, false);
  });

  it('kurul (detailed:false): YALNIZ ad + iliski + admin; telefon, kucuk, hesap, askida, kullanici kodu HIC yok', () => {
    const h = buildHousehold({
      members: [member(1, 'APARTMENT_ADMIN', { phone_number: '0555' }), member(2, 'FAMILY_MEMBER')],
      residencies: [res(10, 1, 'owner', 'A', { phone: '0555' }), res(11, 2, 'family_member', 'B', { is_minor: true }), res(12, null, 'tenant', 'C')],
      suspended: new Set([2]),
      detailed: false,
    });
    const keys = (p) => Object.keys(p).sort();
    assert.deepEqual(keys(h.admin), ['is_admin', 'name', 'person_id', 'relation']);
    for (const m of [...h.members, ...(h.absent_owner ? [h.absent_owner] : [])]) {
      assert.deepEqual(keys(m), ['is_admin', 'name', 'person_id', 'relation']);
    }
    assert.doesNotMatch(JSON.stringify(h), /0555|is_minor|has_account|access_suspended|user_code/);
  });

  it('tam gorunumde de kullanici kodu donmez', () => {
    const h = buildHousehold({ members: [member(1, 'APARTMENT_ADMIN')], residencies: [res(10, 1, 'owner', 'A')], detailed: true });
    assert.doesNotMatch(JSON.stringify(h), /user_code/);
  });
});

describe('getApartmentHousehold (sahte db)', () => {
  const makeDb = ({ apartment = { id: 5, site_code: 11, unit_label: 'Daire 5', resident_user_code: 1, block_name: 'A Blok' } } = {}) => {
    const queries = [];
    return {
      queries,
      async query(sql, params) {
        queries.push({ sql, params });
        if (/FROM apartments a/.test(sql)) {
          return { rows: apartment && params[1] === apartment.site_code ? [apartment] : [] };
        }
        if (/FROM apartment_memberships/.test(sql)) {
          return { rows: [member(1, 'APARTMENT_ADMIN'), member(2, 'FAMILY_MEMBER')] };
        }
        if (/FROM apartment_residencies/.test(sql)) {
          return { rows: [res(10, 1, 'owner', 'Veli K'), res(11, 2, 'family_member', 'Ayse K'), res(12, null, 'family_member', 'Cocuk K', { is_minor: true })] };
        }
        if (/apartment_access_suspensions/.test(sql)) {
          return { rows: [{ user_code: 2 }] };
        }
        return { rows: [] };
      },
    };
  };
  const noSync = async () => {};

  it('tum guncel sakinleri tek yanitla verir; baslik etiketi ve detay seviyesi dogru', async () => {
    const db = makeDb();
    const out = await getApartmentHousehold({ siteCode: 11, apartmentId: '5', detailed: true }, { db, sync: noSync });
    assert.equal(out.apartment_id, 5);
    assert.equal(out.label, 'A Blok - Daire 5');
    assert.equal(out.detail, 'full');
    assert.equal(out.admin.name, 'Veli K');
    assert.deepEqual(out.members.map((m) => m.name), ['Ayse K', 'Cocuk K']);
    assert.equal(out.members[0].access_suspended, true);
    assert.equal(out.total, 3);
  });

  it('kurul: askiya alma sorgusu hic calismaz; yanit "basic"', async () => {
    const db = makeDb();
    const out = await getApartmentHousehold({ siteCode: 11, apartmentId: 5, detailed: false }, { db, sync: noSync });
    assert.equal(out.detail, 'basic');
    assert.equal(db.queries.some((q) => /apartment_access_suspensions/.test(q.sql)), false);
    assert.doesNotMatch(JSON.stringify(out), /access_suspended|is_minor|phone/);
  });

  it('baska sitenin dairesi, olmayan daire ve gecersiz kimlik 404 APARTMENT_NOT_FOUND', async () => {
    for (const [site, id] of [[99, 5], [11, 'x'], [11, 0]]) {
      await assert.rejects(
        getApartmentHousehold({ siteCode: site, apartmentId: id, detailed: true }, { db: makeDb(), sync: noSync }),
        (e) => e.statusCode === 404 && e.code === 'APARTMENT_NOT_FOUND',
      );
    }
  });
});

describe('uc kaydi ve eski yanit uyumu', () => {
  it('yonlendirici ucu yetkiyle kaydeder: okuma yetkisi (kurul dahil), yazma yetkisi tam detay; kullanici kodu sizmaz', () => {
    const src = read('src/modules/apartment_mgmt_routes.js');
    assert.match(src, /apartmentMgmtRouter\.get\('\/manager\/sites\/:siteCode\/apartments\/:apartmentId\/household'/);
    const block = src.slice(src.indexOf("'/manager/sites/:siteCode/apartments/:apartmentId/household'"));
    assert.match(block.slice(0, 700), /resolvePeopleAccess\(req, res\)/, 'okuma yetkisi: yonetici / super / kurul; gorevli ve baska site 403');
    assert.match(block.slice(0, 700), /detailed: access\.canWrite/);
  });

  it('mapApartmentRow: household_count yoksa anahtar hic yazilmaz (eski yanit biciminin aynisi); varsa sayi', () => {
    const base = { id: 1, site_code: 2, block_id: 3, block_name: 'A', unit_label: '1', sort_order: 1, is_active: true };
    assert.equal('household_count' in mapApartmentRow({ ...base }), false);
    assert.equal(mapApartmentRow({ ...base, household_count: '5' }).household_count, 5);
    assert.equal(mapApartmentRow({ ...base, household_count: 0 }).household_count, 0);
  });

  it('site yapisi listesi daire basina kisi sayisini tek toplu sorguyla ekler, eski tek-sakin alanlari yerinde kalir', () => {
    const src = read('src/services/site_service.js');
    assert.match(src, /household_count/);
    const header = readFileSync(path.join(here, '..', 'src/services/apartment_service.js'), 'utf8');
    assert.match(header, /u\.full_name AS resident_full_name/);
  });
});
