// Daire sahipligi, yonetimi ve koruma politikasi (074): sema <-> migration, SAF kurallar (admin cozumleme, devir, vekalet, imza hakki, arama gizliligi,
// yetiskin uyeyi cikarma), uc kayitlari ve kaynak denetimleri. DB gerektirmez.
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { DEFAULT_MIGRATIONS_DIR, findUnsafeStatements } from '../scripts/migrate.js';
import {
  APARTMENT_MGMT_STEPS,
  apartmentMgmtMigrationBody,
  ensureApartmentMgmtSchema,
  schemaTuning,
} from '../src/modules/apartment_mgmt_schema.js';
import * as rules from '../src/modules/apartment_mgmt_rules.js';

schemaTuning.retryDelayMs = 1;
const here = path.dirname(fileURLToPath(import.meta.url));
const read = (rel) => readFileSync(path.join(here, '..', rel), 'utf8');
const norm = (s) => s.replace(/\r\n/g, '\n').replace(/--.*$/gm, '').replace(/\s+/g, ' ').trim();
const MIGRATION = readFileSync(path.join(DEFAULT_MIGRATIONS_DIR, '074_apartment_management.sql'), 'utf8');

const member = (user_code, role, created_at = '2026-01-01') => ({ user_code, role, is_active: true, created_at });
const res = (id, person_id, user_code, relation, extra = {}) => ({ id, person_id, user_code, relation, name: `K${person_id}`, ...extra });

describe('apartment_mgmt sema', () => {
  it('migration 074 govdesi adimlarin birlesimidir; ekleyici ve idempotent', () => {
    assert.ok(norm(MIGRATION).includes(norm(apartmentMgmtMigrationBody())));
    for (const step of APARTMENT_MGMT_STEPS) {
      assert.doesNotMatch(step.sql, /\b(DROP|TRUNCATE|DELETE FROM)\b/i);
      assert.match(step.sql, /IF NOT EXISTS/);
    }
    assert.deepEqual(findUnsafeStatements(MIGRATION), []);
  });
  it('tablolar, kolonlar, FK, indeks sirasi; beklenen tablolar var', () => {
    const order = ['table', 'column', 'fk', 'index'];
    const kinds = APARTMENT_MGMT_STEPS.map((s) => s.kind);
    assert.deepEqual(kinds, [...kinds].sort((a, b) => order.indexOf(a) - order.indexOf(b)));
    const tables = APARTMENT_MGMT_STEPS.filter((s) => s.kind === 'table').map((s) => s.name);
    for (const t of ['apartment_admin_delegations', 'apartment_link_requests', 'apartment_proxies', 'apartment_notices', 'apartment_safety_requests', 'apartment_safety_notes', 'apartment_access_suspensions']) {
      assert.ok(tables.includes(t), t);
    }
    const columns = APARTMENT_MGMT_STEPS.filter((s) => s.kind === 'column').map((s) => s.name);
    assert.deepEqual(columns.sort(), ['apartment_residencies.is_minor', 'apartment_residencies.sponsor_person_id', 'users.search_visible']);
  });
  it('varsayilanlar guvenli: aramada gorunme KAPALI, aile uyesi yetiskin', () => {
    const body = apartmentMgmtMigrationBody();
    assert.match(body, /search_visible BOOLEAN NOT NULL DEFAULT FALSE/);
    assert.match(body, /is_minor BOOLEAN NOT NULL DEFAULT FALSE/);
  });
  it('vekalet kisiti en cok 1 yil; bag kesme / uye cikarma talebi turleri var', () => {
    const body = apartmentMgmtMigrationBody();
    assert.match(body, /valid_until - valid_from <= 366/);
    assert.match(body, /'member_removal'/);
  });
  it('her sey varsa hicbir DDL gonderilmez; eksikse yalniz eksikler calisir', async () => {
    const all = APARTMENT_MGMT_STEPS.map((s) => s.name);
    const sent = [];
    const mk = (present) => ({
      async query(sql) {
        if (/unnest/.test(sql)) {
          return {
            rows: [{
              tables: present.filter((n) => APARTMENT_MGMT_STEPS.find((s) => s.name === n && s.kind === 'table')),
              fks: present.filter((n) => n.endsWith('_fkey')),
              indexes: present.filter((n) => APARTMENT_MGMT_STEPS.find((s) => s.name === n && s.kind === 'index')),
              columns: present.filter((n) => APARTMENT_MGMT_STEPS.find((s) => s.name === n && s.kind === 'column')),
            }],
          };
        }
        sent.push(sql);
        return { rows: [] };
      },
    });
    await ensureApartmentMgmtSchema(mk(all));
    assert.deepEqual(sent.filter((q) => !/lock_timeout/.test(q)), []);
    sent.length = 0;
    await ensureApartmentMgmtSchema(mk(all.filter((n) => n !== 'apartment_proxies')));
    assert.equal(sent.filter((q) => /CREATE TABLE IF NOT EXISTS apartment_proxies/.test(q)).length, 1);
  });
  it('db.js sema ensure cagirir; server.js router kaydeder', () => {
    assert.match(read('src/db.js'), /await ensureApartmentMgmtSchema\(client\)/);
    assert.match(read('src/server.js'), /app\.use\(apartmentMgmtRouter\)/);
  });
});

describe('admin cozumleme ve roller', () => {
  it('APARTMENT_ADMIN uyeligi admindir; malik admin ise "owner"', () => {
    const roles = rules.resolveApartmentRoles({
      members: [member(1, 'APARTMENT_ADMIN'), member(2, 'FAMILY_MEMBER')],
      residencies: [res(10, 100, 1, 'owner'), res(11, 101, 2, 'family_member')],
    });
    assert.equal(roles.adminUserCode, 1);
    assert.equal(roles.adminKind, 'owner');
    assert.equal(rules.adminSideOf(roles), 'owner');
  });
  it('eski kayit: malik / kiraci kaydi yoksa admin maliktir (turetilmis)', () => {
    const roles = rules.resolveApartmentRoles({ members: [member(1, 'APARTMENT_ADMIN')], residencies: [res(10, 100, 1, 'resident')] });
    assert.equal(roles.adminKind, 'owner_derived');
    const me = rules.rolesOfUser(roles, 1);
    assert.equal(me.is_owner, true);
    assert.equal(me.is_owner_derived, true);
    assert.equal(me.my_role, 'owner');
    assert.equal(me.can.add_tenant, true);
  });
  it('eski gosterge (resident_user_code) uyelik satiri olmadan admin sayilir', () => {
    const roles = rules.resolveApartmentRoles({ members: [], legacyUserCode: 7, residencies: [] });
    assert.equal(roles.adminUserCode, 7);
    assert.equal(roles.adminSource, 'legacy');
  });
  it('kiraci admin iken yonetim kiracidadir; malik kiraci varken turetilmis malik olmaz', () => {
    const roles = rules.resolveApartmentRoles({
      members: [member(1, 'FAMILY_MEMBER'), member(2, 'APARTMENT_ADMIN')],
      residencies: [res(10, 100, 1, 'owner'), res(11, 101, 2, 'tenant')],
    });
    assert.equal(roles.adminKind, 'tenant');
    const owner = rules.rolesOfUser(roles, 1);
    assert.equal(owner.is_admin, false);
    assert.equal(owner.is_owner, true);
    assert.equal(owner.can.manage_family, false, 'daire yonetimi yalniz adminde');
    assert.equal(owner.can.add_tenant, false, 'kiraci varken yeni kiraci eklenemez');
    assert.equal(owner.can.delegate_management, false, 'zaten devredilmis');
    assert.equal(owner.can.manage_proxy, true);
    const tenant = rules.rolesOfUser(roles, 2);
    assert.equal(tenant.is_tenant, true);
    assert.equal(tenant.can.manage_family, true);
    assert.equal(tenant.can.exit, true);
    assert.equal(tenant.can.manage_proxy, false);
  });
  it('malik admin kalirsa kiraciya devredebilir; aile uyesi yalniz okur', () => {
    const roles = rules.resolveApartmentRoles({
      members: [member(1, 'APARTMENT_ADMIN'), member(2, 'FAMILY_MEMBER'), member(3, 'FAMILY_MEMBER')],
      residencies: [res(10, 100, 1, 'owner'), res(11, 101, 2, 'tenant'), res(12, 102, 3, 'family_member')],
    });
    assert.equal(rules.rolesOfUser(roles, 1).can.delegate_management, true);
    const family = rules.rolesOfUser(roles, 3);
    assert.equal(family.my_role, 'family_member');
    assert.ok(Object.values(family.can).every((v) => v === false), 'aile uyesinin hicbir yonetim yetkisi yok');
  });
  it('bag kesme karsi tarafi: kiraci acarsa malik, malik acarsa kiraci; hesapsiz karsi taraf null', () => {
    const roles = rules.resolveApartmentRoles({
      members: [member(1, 'APARTMENT_ADMIN'), member(2, 'FAMILY_MEMBER')],
      residencies: [res(10, 100, 1, 'owner'), res(11, 101, 2, 'tenant')],
    });
    assert.equal(rules.disconnectCounterpart(roles, 2), 1);
    assert.equal(rules.disconnectCounterpart(roles, 1), 2);
    const noAccount = rules.resolveApartmentRoles({ members: [member(1, 'APARTMENT_ADMIN')], residencies: [res(10, 100, 1, 'owner'), res(11, 101, null, 'tenant')] });
    assert.equal(rules.disconnectCounterpart(noAccount, 1), null);
  });
  it('kiraci cikisinda yalniz kiracinin ekledigi aile biter; sponsorsuz / malik ailesi kalir', () => {
    const family = [res(1, 1, 5, 'family_member', { sponsor_person_id: 101 }), res(2, 2, 6, 'family_member', { sponsor_person_id: 100 }), res(3, 3, 7, 'family_member', { sponsor_person_id: null })];
    assert.deepEqual(rules.familyEndingWithTenant(family, 101).map((r) => r.id), [1]);
    assert.deepEqual(rules.familyEndingWithTenant(family, null), []);
  });
  it('aile uyesini admin ya da ekleyen yonetebilir', () => {
    assert.equal(rules.canManageFamilyMember({ isAdmin: true, actorPersonId: 1, residency: { sponsor_person_id: 9 } }), true);
    assert.equal(rules.canManageFamilyMember({ isAdmin: false, actorPersonId: 9, residency: { sponsor_person_id: 9 } }), true);
    assert.equal(rules.canManageFamilyMember({ isAdmin: false, actorPersonId: 1, residency: { sponsor_person_id: 9 } }), false);
  });
});

describe('talep durum makinesi', () => {
  const now = new Date('2026-10-22T10:00:00Z');
  it('sure: davet / bag kesme 14 gun, uye cikarma istegi 7 gun', () => {
    assert.equal(rules.requestExpiresAt(now, 'tenant_invite').toISOString(), '2026-11-05T10:00:00.000Z');
    assert.equal(rules.requestExpiresAt(now, 'disconnect').toISOString(), '2026-11-05T10:00:00.000Z');
    assert.equal(rules.requestExpiresAt(now, 'member_removal').toISOString(), '2026-10-29T10:00:00.000Z');
  });
  it('suresi dolan bekleyen talep expired sayilir ve yanitlanamaz; yalniz hedef yanitlar, yalniz acan geri ceker', () => {
    const pending = { status: 'pending', expires_at: '2026-10-30T00:00:00Z', target_user_code: 5, requested_by: 6 };
    assert.equal(rules.effectiveRequestStatus(pending, now), 'pending');
    assert.equal(rules.canRespondToRequest(pending, 5, now), true);
    assert.equal(rules.canRespondToRequest(pending, 6, now), false);
    assert.equal(rules.canCancelRequest(pending, 6, now), true);
    assert.equal(rules.canCancelRequest(pending, 5, now), false);
    const old = { ...pending, expires_at: '2026-10-21T00:00:00Z' };
    assert.equal(rules.effectiveRequestStatus(old, now), 'expired');
    assert.equal(rules.canRespondToRequest(old, 5, now), false);
    assert.equal(rules.canRespondToRequest({ ...pending, status: 'approved' }, 5, now), false);
  });
});

describe('koruma politikasi: yetiskin uyeyi tek tarafli cikaramama', () => {
  it('admin yalniz 18 yasindan kucuk isaretli ya da hesabi olmayan uyeyi tek tarafli cikarir', () => {
    assert.equal(rules.adminMayRemoveWithoutConsent({ user_code: 5, is_minor: false }), false, 'hesapli yetiskin: onay gerekir');
    assert.equal(rules.adminMayRemoveWithoutConsent({ user_code: 5, is_minor: true }), true);
    assert.equal(rules.adminMayRemoveWithoutConsent({ user_code: null, is_minor: false }), true, 'hesapsiz: kesilecek erisim yok');
    assert.equal(rules.adminMayRemoveWithoutConsent(null), false);
  });
  it('kaynak: aile uyesi cikarma onay istegine donusur, eski uclar yetiskin icin 403 CONSENT_REQUIRED verir, ayrilma onaysizdir', () => {
    const service = read('src/modules/apartment_mgmt_service.js');
    assert.match(service, /adminMayRemoveWithoutConsent\(residency\)/);
    assert.match(service, /kind: 'member_removal'/);
    assert.match(service, /export async function leaveApartment/);
    const membership = read('src/services/membership_service.js');
    assert.match(membership, /CONSENT_REQUIRED/);
    assert.match(membership, /assertAdminMayActOnMember\(apt\.id, tUserCode\)/);
    assert.match(membership, /assertAdminMayActOnMember\(apt\.id, tUserCode, \{ activating: activeBool \}\)/);
  });
});

describe('vekalet ve imza hakki', () => {
  const today = '2026-10-22';
  it('pencere: varsayilan bugunden 1 yil; gecmis, 1 yildan uzun, ters aralik reddedilir', () => {
    assert.deepEqual(rules.resolveProxyWindow({ today }), { valid_from: '2026-10-22', valid_until: '2027-10-22' });
    assert.equal(rules.resolveProxyWindow({ validFrom: '2026-10-01', today }).error, 'valid_from');
    assert.equal(rules.resolveProxyWindow({ validUntil: '2027-10-23', today }).error, 'valid_until');
    assert.equal(rules.resolveProxyWindow({ validFrom: '2026-12-01', validUntil: '2026-11-01', today }).error, 'valid_until');
    assert.equal(rules.resolveProxyWindow({ validUntil: 'abc', today }).error, 'valid_until');
    assert.equal(rules.addOneYear('2028-02-29'), '2029-02-28');
  });
  it('vekalet yalniz iptal edilmemis ve pencere icindeyken gecerli', () => {
    const p = { valid_from: '2026-10-22', valid_until: '2027-01-01', revoked_at: null };
    assert.equal(rules.proxyIsActive(p, '2026-10-22'), true);
    assert.equal(rules.proxyIsActive(p, '2027-01-02'), false);
    assert.equal(rules.proxyIsActive({ ...p, revoked_at: '2026-11-01' }, '2026-11-02'), false);
  });
  it('vekalet yoksa imza hakki maliktedir; aktif vekil varsa vekildedir; vekil kiraci degilse yok sayilir', () => {
    const owner = { person_id: 1, name: 'Veli Kaya' };
    const proxy = { id: 1, scope: 'toplanti_imza', proxy_person_id: 2, proxy_name: 'Ali Yilmaz', valid_from: '2026-10-01', valid_until: '2027-09-30', revoked_at: null, holder_ok: true };
    assert.equal(rules.pickSigningHolder({ owner, proxies: [], today }).kind, 'owner');
    const withProxy = rules.pickSigningHolder({ owner, proxies: [proxy], today });
    assert.equal(withProxy.kind, 'proxy');
    assert.equal(withProxy.person_id, 2);
    assert.equal(rules.pickSigningHolder({ owner, proxies: [{ ...proxy, holder_ok: false }], today }).kind, 'owner');
    assert.equal(rules.pickSigningHolder({ owner, proxies: [{ ...proxy, scope: 'kurul_uyeligi' }], today }).kind, 'owner', 'kurul vekaleti imza hakkini degistirmez');
    assert.equal(rules.pickSigningHolder({ owner: null, proxies: [], today }).kind, 'none');
  });
  it('imza satiri biçimi', () => {
    const owner = { person_id: 1, name: 'Veli Kaya' };
    const proxy = { id: 1, scope: 'toplanti_imza', proxy_person_id: 2, proxy_name: 'Ali Yilmaz', valid_from: '2026-10-01', valid_until: '2027-09-30', revoked_at: null };
    assert.equal(rules.signingLabel('Daire 5', rules.pickSigningHolder({ owner, proxies: [proxy], today: '2026-10-22' })), 'Daire 5 - vekil: Ali Y. (malik: Veli K.)');
    assert.equal(rules.signingLabel('Daire 5', rules.pickSigningHolder({ owner, proxies: [], today })), 'Daire 5 - malik: Veli K.');
  });
});

describe('kisi arama gizliligi', () => {
  it('maskeli ad / e-posta', () => {
    assert.equal(rules.maskName('Ahmet Yilmaz'), 'Ahmet Y***');
    assert.equal(rules.maskName('Ahmet'), 'Ah***');
    assert.equal(rules.maskEmail('ahmet.yilmaz@gmail.com'), 'ah***@gmail.com');
    assert.equal(rules.shortName('Mehmet Ali Yilmaz'), 'Mehmet Ali Y.');
  });
  it('en az 3 karakter; e-posta ve telefon TAM ESLESME, ad-soyad bulanik', () => {
    assert.equal(rules.normalizeSearchQuery('ab'), null);
    assert.equal(rules.normalizeSearchQuery('  abc '), 'abc');
    assert.deepEqual(rules.classifySearchQuery('Ahmet@Mail.com'), { kind: 'email', value: 'ahmet@mail.com' });
    assert.deepEqual(rules.classifySearchQuery('+90 532 111 22 33'), { kind: 'phone', value: '5321112233' });
    assert.deepEqual(rules.classifySearchQuery('0532 111 22 33'), { kind: 'phone', value: '5321112233' });
    assert.equal(rules.classifySearchQuery('Ahmet Y').kind, 'name');
    assert.equal(rules.classifySearchQuery('532').kind, 'name', 'kismi rakam telefon eslesmesi sayilmaz');
  });
  it('denetim icin maskeli sorgu tam degeri icermez', () => {
    assert.equal(rules.maskSearchQuery('ahmet.yilmaz@gmail.com'), 'ah***@gmail.com');
    assert.equal(rules.maskSearchQuery('05321112233'), '+90 *** *** ** 33');
    assert.equal(rules.maskSearchQuery('Ahmet Yilmaz'), 'Ah***');
  });
  it('secim belirteci imzali, aranan kisiye ve hedefe bagli, kisa omurlu', () => {
    const secret = 'unit-test-secret-value-1234567890';
    const handle = rules.signCandidateHandle(secret, 10, 20, 1_000_000);
    assert.equal(rules.verifyCandidateHandle(secret, 10, handle, 1_000_500), 20);
    assert.equal(rules.verifyCandidateHandle(secret, 11, handle, 1_000_500), null, 'baska kullanici kullanamaz');
    assert.equal(rules.verifyCandidateHandle('baska-sir-baska-sir-baska-sir-12', 10, handle, 1_000_500), null);
    assert.equal(rules.verifyCandidateHandle(secret, 10, handle, 1_000_000 + rules.CANDIDATE_TTL_MS + 1), null, 'sure doldu');
    const tampered = `${handle.slice(0, 6)}${handle[6] === 'A' ? 'B' : 'A'}${handle.slice(7)}`;
    assert.equal(rules.verifyCandidateHandle(secret, 10, tampered, 1_000_500), null);
    assert.equal(rules.verifyCandidateHandle(secret, 10, 'abc', 1_000_500), null);
    assert.equal(rules.SEARCH_HOURLY_LIMIT, 60);
    assert.equal(rules.SEARCH_MAX_RESULTS, 5);
  });
  it('kaynak: arama audit yazar (maskeli), aramada gorunme ayari ve guvenlik talebi gizliligi', () => {
    const service = read('src/modules/apartment_mgmt_service.js');
    assert.match(service, /action: 'apartment_mgmt\.person_search'/);
    assert.match(service, /maskSearchQuery\(q\)/);
    assert.match(service, /u\.search_visible = TRUE/);
    const safety = read('src/modules/apartment_mgmt_safety.js');
    assert.match(safety, /'safety_request'/, 'denetim hedef turu Kisi / Daire gecmisinde gorunmez');
    assert.doesNotMatch(safety, /notifyApartmentUsers/, 'guvenlik islemleri hicbir kullaniciya bildirim uretmez');
    const history = read('src/modules/people_history_service.js');
    assert.doesNotMatch(history, /safety_request|access_suspension/);
  });
});

describe('uclar', () => {
  const routes = read('src/modules/apartment_mgmt_routes.js');
  it('sakin uclari ve yonetici uclari kayitli', () => {
    for (const p of [
      "'/app/apartments/mine'", "'/app/apartments/people-search'", "'/app/apartments/:apartmentId/tenant'", "'/app/apartments/:apartmentId/family'",
      "'/app/apartments/:apartmentId/exit'", "'/app/apartments/:apartmentId/leave'", "'/app/apartments/:apartmentId/proxies'",
      "'/app/apartments/:apartmentId/safety-requests'", "'/app/apartments/search-visibility'",
      "'/manager/sites/:siteCode/signing-roster'", "'/manager/sites/:siteCode/apartments/:apartmentId/admin'",
      "'/manager/sites/:siteCode/safety-requests'", "'/manager/sites/:siteCode/apartments/:apartmentId/members/:userCode/suspend'",
    ]) {
      assert.ok(routes.includes(p), p);
    }
  });
  it('sabit yollar parametreli :apartmentId yolundan ONCE kayitli', () => {
    assert.ok(routes.indexOf("'/app/apartments/mine'") < routes.indexOf("'/app/apartments/:apartmentId'"));
    assert.ok(routes.indexOf("'/app/apartments/search-visibility'") < routes.indexOf("'/app/apartments/:apartmentId'"));
  });
  it('yonetici / guvenlik uclari yalniz yonetici ve super (write: true); kisi arama saatte 60', () => {
    assert.equal((routes.match(/resolvePeopleAccess\(req, res, \{ write: true \}\)/g) ?? []).length >= 3, true);
    assert.match(routes, /max: SEARCH_HOURLY_LIMIT/);
  });
});
