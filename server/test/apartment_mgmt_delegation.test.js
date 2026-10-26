// Yönetim devri (apartment_admin_delegations) yaşam döngüsü ve askı kontrolü - DB'siz:
//  - resolveApartmentRoles: açık devir YALNIZ devralan güncel kiracıysa (ya da manager kaynağında güncel sakinse) ve hesabıysa aktif üyeliği varsa uygulanır;
//    aksi halde bayat sayılır (eskiden aktif APARTMENT_ADMIN üyeliğini koşulsuz eziyordu);
//  - closeDelegationsOnLeave: ayrılan kişinin açık devri kapanır, vekaletleri iptal edilir (idempotent);
//  - membership_service: daireden çıkar / sil ve "Aile Reisini Değiştir" devri kapatır; katılım başvurusu / onayı kapı erişimi askıdaki kişi için reddedilir.
import { describe, it, beforeEach, afterEach, mock } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { pool } from '../src/db.js';
import * as rules from '../src/modules/apartment_mgmt_rules.js';
import { closeDelegationsOnLeave, endOpenDelegation } from '../src/modules/apartment_delegation_close.js';
import { endOpenDelegation as coreEndOpenDelegation } from '../src/modules/apartment_mgmt_core.js';
import {
  approveJoinRequest,
  createJoinRequest,
  deleteApartmentMember,
  removeApartmentMember,
  setApartmentPrimaryAdmin,
} from '../src/services/membership_service.js';

const here = path.dirname(fileURLToPath(import.meta.url));
const read = (rel) => readFileSync(path.join(here, '..', rel), 'utf8').replace(/\r\n/g, '\n');
const norm = (text) => String(text).replace(/\s+/g, ' ').trim();
const ok = (rows = [], rowCount = rows.length) => ({ rows, rowCount });

const member = (user_code, role, created_at = '2026-01-01') => ({ user_code, role, is_active: true, created_at });
const res = (id, person_id, user_code, relation, extra = {}) => ({ id, person_id, user_code, relation, name: `K${person_id}`, ...extra });
const delegation = (extra = {}) => ({ id: 1, admin_user_code: 2, admin_person_id: 101, source: 'tenant_delegated', state: 'active', ended_at: null, ...extra });

describe('resolveApartmentRoles: açık devir yalnız geçerliyse admini belirler', () => {
  const owner = res(10, 100, 1, 'owner');
  const tenant = res(11, 101, 2, 'tenant');

  it('devralan güncel kiracı + aktif üyelik: devir uygulanır (üyelikte admin başka olsa bile)', () => {
    const roles = rules.resolveApartmentRoles({
      members: [member(1, 'APARTMENT_ADMIN'), member(2, 'FAMILY_MEMBER')],
      residencies: [owner, tenant],
      delegation: delegation(),
    });
    assert.equal(roles.adminUserCode, 2);
    assert.equal(roles.adminKind, 'tenant');
    assert.equal(roles.adminSource, 'tenant_delegated');
  });

  it('devralanın aktif üyeliği yok (çıkarıldı / pasif): devir BAYAT, admin üyelikteki APARTMENT_ADMIN (malik) kalır', () => {
    const roles = rules.resolveApartmentRoles({
      members: [member(1, 'APARTMENT_ADMIN')],
      residencies: [owner, tenant],
      delegation: delegation(),
    });
    assert.equal(roles.adminUserCode, 1);
    assert.equal(roles.adminKind, 'owner');
    assert.equal(roles.adminSource, 'membership');
    // pasif üyelik de aynı: etkin olmayan üye listeden elenir
    const inactive = rules.resolveApartmentRoles({
      members: [member(1, 'APARTMENT_ADMIN'), { ...member(2, 'FAMILY_MEMBER'), is_active: false }],
      residencies: [owner, tenant],
      delegation: delegation(),
    });
    assert.equal(inactive.adminUserCode, 1);
  });

  it('devralan artık dairenin güncel kiracısı değil (ilişki bitti / başka kiracı geldi): devir BAYAT', () => {
    const gone = rules.resolveApartmentRoles({
      members: [member(1, 'APARTMENT_ADMIN'), member(2, 'FAMILY_MEMBER')],
      residencies: [owner],
      delegation: delegation(),
    });
    assert.equal(gone.adminUserCode, 1);
    assert.equal(gone.adminKind, 'owner');
    const replaced = rules.resolveApartmentRoles({
      members: [member(1, 'APARTMENT_ADMIN'), member(2, 'FAMILY_MEMBER'), member(3, 'FAMILY_MEMBER')],
      residencies: [owner, res(12, 102, 3, 'tenant')],
      delegation: delegation(),
    });
    assert.equal(replaced.adminUserCode, 1);
  });

  it('hesapsız devralan (pending_account): kişi güncel kiracıysa uygulanır (kişi kimliği), değilse bayat sayılır', () => {
    const pending = delegation({ admin_user_code: null, state: 'pending_account' });
    const applied = rules.resolveApartmentRoles({
      members: [member(1, 'APARTMENT_ADMIN')],
      residencies: [owner, res(11, 101, null, 'tenant')],
      delegation: pending,
    });
    assert.equal(applied.adminPersonId, 101);
    assert.equal(applied.adminUserCode, 1, 'hesap yok: kullanıcı kodu üyelikten gelir');
    const stale = rules.resolveApartmentRoles({
      members: [member(1, 'APARTMENT_ADMIN')],
      residencies: [owner],
      delegation: pending,
    });
    assert.equal(stale.adminPersonId, 100, 'bayat devir görmezden gelinir: admin malik');
  });

  it('manager kaynaklı devir: devralan kiracı olmak zorunda değil, güncel sakin yeterli (malik / aile üyesi atanabilir)', () => {
    const family = res(12, 102, 3, 'family_member');
    const roles = rules.resolveApartmentRoles({
      members: [member(1, 'FAMILY_MEMBER'), member(3, 'APARTMENT_ADMIN')],
      residencies: [owner, family],
      delegation: delegation({ admin_user_code: 3, admin_person_id: 102, source: 'manager' }),
    });
    assert.equal(roles.adminUserCode, 3);
    assert.equal(roles.adminKind, 'family');
    const notResident = rules.resolveApartmentRoles({
      members: [member(1, 'APARTMENT_ADMIN'), member(3, 'FAMILY_MEMBER')],
      residencies: [owner],
      delegation: delegation({ admin_user_code: 3, admin_person_id: 102, source: 'manager' }),
    });
    assert.equal(notResident.adminUserCode, 1, 'sakin olmayan devralan: bayat');
  });

  it('bitmiş devir (ended_at dolu) ve devir yok: davranış aynen (üyelik / eski gösterge)', () => {
    const ended = rules.resolveApartmentRoles({
      members: [member(1, 'APARTMENT_ADMIN'), member(2, 'FAMILY_MEMBER')],
      residencies: [owner, tenant],
      delegation: delegation({ ended_at: '2026-10-01T00:00:00Z', state: 'ended' }),
    });
    assert.equal(ended.adminUserCode, 1);
    const none = rules.resolveApartmentRoles({ members: [], legacyUserCode: 7, residencies: [] });
    assert.equal(none.adminUserCode, 7);
  });
});

function scripted(handlers = [], { strict = false } = {}) {
  const log = [];
  return {
    log,
    async query(text, params) {
      const sql = norm(text);
      log.push({ sql, params: params ?? [] });
      for (const [pattern, handler] of handlers) {
        if (pattern.test(sql)) return typeof handler === 'function' ? handler(sql, params ?? []) : handler;
      }
      if (/^(BEGIN|COMMIT|ROLLBACK|SAVEPOINT|RELEASE SAVEPOINT|ROLLBACK TO SAVEPOINT)\b/.test(sql) || /^INSERT INTO (audit_log|apartment_residency_log)/.test(sql)) return ok();
      if (strict) throw new Error(`BEKLENMEYEN SQL: ${sql.slice(0, 200)}`);
      return ok();
    },
  };
}
const has = (log, regex) => log.some((q) => regex.test(q.sql));
const find = (log, regex) => log.find((q) => regex.test(q.sql));
const indexOf = (log, regex) => log.findIndex((q) => regex.test(q.sql));

describe('closeDelegationsOnLeave', () => {
  it('devralan kişinin açık devrini kapatır, vekaletlerini iptal eder; kişi hem user_code hem kişi kaydı üzerinden eşleşir', async () => {
    const client = scripted([
      [/^UPDATE apartment_admin_delegations/, ok([], 1)],
      [/^UPDATE apartment_proxies/, ok([], 2)],
    ], { strict: true });
    const result = await closeDelegationsOnLeave(client, { siteCode: 1000000001, apartmentId: 9, userCode: 30001, reason: 'member_removed' });
    assert.deepEqual(result, { delegationsClosed: 1, proxiesRevoked: 2 });
    const del = find(client.log, /^UPDATE apartment_admin_delegations/);
    assert.match(del.sql, /SET state = 'ended', ended_at = NOW\(\), end_reason = \$5::text/);
    assert.match(del.sql, /ended_at IS NULL/);
    assert.match(del.sql, /admin_user_code = \$3::int/);
    assert.match(del.sql, /admin_person_id IN \(SELECT sp\.id FROM site_people sp WHERE sp\.site_code = \$2::bigint AND sp\.user_code = \$3::int\)/);
    assert.deepEqual(del.params, [9, 1000000001, 30001, null, 'member_removed']);
    const proxy = find(client.log, /^UPDATE apartment_proxies/);
    assert.match(proxy.sql, /SET revoked_at = NOW\(\), revoked_reason = \$5::text/);
    assert.match(proxy.sql, /revoked_at IS NULL/);
    assert.match(proxy.sql, /proxy_person_id = \$4::bigint OR owner_person_id = \$4::bigint/);
    assert.deepEqual(proxy.params, [9, 1000000001, 30001, null, 'member_removed']);
  });

  it('hesapsız kişi için kişi kaydı kimliği (personId) ile eşleşir; kimlik yoksa HİÇBİR sorgu çalışmaz; neden 60 karakterle sınırlanır', async () => {
    const client = scripted([], { strict: true });
    const idle = await closeDelegationsOnLeave(client, { siteCode: 1, apartmentId: 9, userCode: null, personId: null, reason: 'x' });
    assert.deepEqual(idle, { delegationsClosed: 0, proxiesRevoked: 0 });
    assert.equal(client.log.length, 0);

    const lazy = scripted([[/^UPDATE/, ok()]]);
    await closeDelegationsOnLeave(lazy, { siteCode: 1, apartmentId: 9, userCode: null, personId: 101, reason: 'r'.repeat(100) });
    const del = find(lazy.log, /^UPDATE apartment_admin_delegations/);
    assert.deepEqual(del.params.slice(0, 4), [9, 1, null, 101]);
    assert.equal(del.params[4].length, 60);
  });

  it('endOpenDelegation tek kaynak: apartment_mgmt_core aynı işlevi yeniden dışa aktarır (idempotent, neden kırpılır)', async () => {
    assert.equal(coreEndOpenDelegation, endOpenDelegation);
    const client = scripted();
    await endOpenDelegation(client, 9, 'z'.repeat(80));
    const q = client.log[0];
    assert.match(q.sql, /^UPDATE apartment_admin_delegations SET state = 'ended', ended_at = NOW\(\), end_reason = \$2 WHERE apartment_id = \$1 AND ended_at IS NULL$/);
    assert.equal(q.params[1].length, 60);
  });

  it('modül bağımsız yapraktır: yerel modül içe aktarmaz (membership_service <-> apartment_mgmt_core döngüsü olmaz)', () => {
    assert.equal(/^import .* from '\.\.?\//m.test(read('src/modules/apartment_delegation_close.js')), false);
  });
});

describe('membership_service: ayrılma yolları devri kapatır', () => {
  const superUser = { id: 1, user_code: 1, role: 'super_user', full_name: 'Süper' };
  const aptRow = { id: 3, site_code: 101, block_id: 1, unit_label: 'Daire 3', resident_user_code: null, resident_pin_code: null };

  beforeEach(() => {
    mock.method(console, 'error', () => {});
  });
  afterEach(() => {
    delete pool.query;
    delete pool.connect;
    mock.restoreAll();
  });

  function install(clientHandlers) {
    const poolScript = scripted([[/^SELECT a\.id, a\.site_code, a\.block_id/, ok([aptRow])]]);
    const clientScript = scripted([
      [/^SELECT id, site_code, resident_user_code FROM apartments/, ok([aptRow])],
      ...clientHandlers,
    ]);
    pool.query = poolScript.query;
    pool.connect = async () => ({ query: clientScript.query, release() {} });
    return clientScript.log;
  }

  it('removeApartmentMember: devir + vekalet kapatma, CRM adımından ÖNCE (kişi hesaptan kopmadan) ve COMMIT\'ten önce; kapı izinlerinden sonra', async () => {
    const log = install([
      [/^UPDATE apartment_memberships SET is_active/, ok([{ role: 'FAMILY_MEMBER' }])],
      [/^SELECT r\.id, r\.site_code, r\.person_id, r\.relation FROM apartment_residencies r/, ok([{ id: '31', site_code: '101', person_id: '5', relation: 'tenant' }])],
      [/^SELECT 1 FROM apartment_residencies WHERE person_id/, ok([{ x: 1 }])],
    ]);
    await removeApartmentMember({ apartmentId: 3, targetUserCode: 20000, authUser: superUser });
    const close = indexOf(log, /^UPDATE apartment_admin_delegations SET state = 'ended'/);
    const proxies = indexOf(log, /^UPDATE apartment_proxies SET revoked_at/);
    const crm = indexOf(log, /^SELECT r\.id, r\.site_code, r\.person_id, r\.relation FROM apartment_residencies r/);
    assert.ok(close > indexOf(log, /^UPDATE apartment_memberships SET is_active/), 'üyelik pasifleştikten sonra');
    assert.ok(close > indexOf(log, /^DELETE FROM door_access_overrides/));
    assert.ok(close >= 0 && proxies > close && crm > proxies, 'devir -> vekalet -> CRM');
    assert.ok(crm < indexOf(log, /^COMMIT$/));
    assert.deepEqual(log[close].params, [3, 101, 20000, null, 'member_removed']);
  });

  it('deleteApartmentMember: aynı kapatma (neden member_deleted), CRM adımından önce, aynı transaction', async () => {
    const log = install([
      [/^DELETE FROM apartment_memberships WHERE apartment_id = \$1 AND user_code = \$2 RETURNING role/, ok([{ role: 'FAMILY_MEMBER' }])],
      [/^SELECT r\.id, r\.site_code, r\.person_id, r\.relation FROM apartment_residencies r/, ok([{ id: '31', site_code: '101', person_id: '5', relation: 'tenant' }])],
      [/^SELECT 1 FROM apartment_residencies WHERE person_id/, ok([{ x: 1 }])],
    ]);
    await deleteApartmentMember({ apartmentId: 3, targetUserCode: 20000, authUser: superUser });
    const close = indexOf(log, /^UPDATE apartment_admin_delegations SET state = 'ended'/);
    const crm = indexOf(log, /^SELECT r\.id, r\.site_code, r\.person_id, r\.relation FROM apartment_residencies r/);
    assert.ok(close > indexOf(log, /^DELETE FROM apartment_memberships/));
    assert.ok(close >= 0 && close < crm && crm < indexOf(log, /^COMMIT$/));
    assert.deepEqual(log[close].params, [3, 101, 20000, null, 'member_deleted']);
  });

  it('Aile Reisini Değiştir (setApartmentPrimaryAdmin): önceki devir kapanır (admin_changed) ve COMMIT\'ten önce; zaten admin olana dokunmaz', async () => {
    const log = install([
      [/^SELECT role, is_active FROM apartment_memberships WHERE apartment_id = \$1 AND user_code = \$2/, ok([{ role: 'FAMILY_MEMBER', is_active: true }])],
    ]);
    await setApartmentPrimaryAdmin({ apartmentId: 3, targetUserCode: 20000, authUser: superUser });
    const close = find(log, /^UPDATE apartment_admin_delegations SET state = 'ended'/);
    assert.ok(close);
    assert.deepEqual(close.params, [3, 'admin_changed']);
    assert.ok(indexOf(log, /^UPDATE apartment_admin_delegations/) > indexOf(log, /^UPDATE apartment_memberships SET role = 'APARTMENT_ADMIN'/));
    assert.ok(indexOf(log, /^UPDATE apartment_admin_delegations/) < indexOf(log, /^COMMIT$/));

    const already = install([
      [/^SELECT role, is_active FROM apartment_memberships WHERE apartment_id = \$1 AND user_code = \$2/, ok([{ role: 'APARTMENT_ADMIN', is_active: true }])],
    ]);
    await setApartmentPrimaryAdmin({ apartmentId: 3, targetUserCode: 20000, authUser: superUser });
    assert.equal(has(already, /apartment_admin_delegations/), false);
  });
});

describe('katılım başvurusu / onayı: kapı erişimi askıdaki kişi geri bağlanamaz', () => {
  const superUser = { id: 1, user_code: 1, role: 'super_user', full_name: 'Süper' };
  const SUSPENSION = /^SELECT 1 FROM apartment_access_suspensions WHERE apartment_id = \$1 AND user_code = \$2 AND lifted_at IS NULL LIMIT 1$/;

  beforeEach(() => {
    mock.method(console, 'error', () => {});
  });
  afterEach(() => {
    delete pool.query;
    delete pool.connect;
    mock.restoreAll();
  });

  function joinClient({ suspended }) {
    const client = scripted([
      [/^SELECT id FROM apartments WHERE id = \$1 FOR KEY SHARE/, ok([{ id: 3 }])],
      [/FROM users WHERE user_code = \$1 AND deleted_at IS NULL LIMIT 1 FOR KEY SHARE/, ok([{ user_code: 77, full_name: 'Ali', email: 'ali@example.com', email_verified: true, is_active: true }])],
      [/FROM site_join_tokens t/, ok([{ site_code: '101', site_name: 'Gül Sitesi' }])],
      [/^SELECT a\.id, a\.site_code, a\.block_id, a\.unit_label, b\.block_name FROM apartments a/, ok([{ id: 3, site_code: 101, block_id: 5, unit_label: 'Daire 3', block_name: 'A' }])],
      [SUSPENSION, ok(suspended ? [{ x: 1 }] : [])],
      [/^INSERT INTO join_requests/, ok([{ id: 9, site_code: 101, block_id: 5, apartment_id: 3, user_code: 77, status: 'PENDING', notes: null, created_at: new Date() }])],
    ]);
    pool.query = async () => ok();
    pool.connect = async () => ({ query: client.query, release() {} });
    return client.log;
  }

  it('createJoinRequest: askıdaki kişi 403 ACCESS_SUSPENDED (neden gösterilmez); INSERT YOK, ROLLBACK var', async () => {
    const log = joinClient({ suspended: true });
    await assert.rejects(
      createJoinRequest({ userCode: 77, token: 'SJT-ABC', apartmentId: 3 }),
      (error) => error.statusCode === 403 && error.code === 'ACCESS_SUSPENDED' && !/mahkeme|güvenlik/i.test(error.message),
    );
    assert.equal(has(log, /^INSERT INTO join_requests/), false);
    assert.ok(has(log, /^ROLLBACK$/));
    assert.equal(has(log, /^COMMIT$/), false);
    assert.deepEqual(find(log, SUSPENSION).params, [3, 77]);
  });

  it('createJoinRequest: askı yoksa başvuru yazılır (davranış aynen); askı denetimi daire doğrulamasından sonra, INSERT\'ten önce', async () => {
    const log = joinClient({ suspended: false });
    const result = await createJoinRequest({ userCode: 77, token: 'SJT-ABC', apartmentId: 3 });
    assert.equal(result.ok, true);
    assert.ok(indexOf(log, SUSPENSION) > indexOf(log, /^SELECT a\.id, a\.site_code, a\.block_id/));
    assert.ok(indexOf(log, SUSPENSION) < indexOf(log, /^INSERT INTO join_requests/));
    assert.ok(has(log, /^COMMIT$/));
  });

  function approveClient({ suspended }) {
    const client = scripted([
      [/FOR UPDATE OF jr FOR KEY SHARE OF u$/, ok([{ id: 9, site_code: 101, apartment_id: 3, block_id: 5, user_code: 77, status: 'PENDING', site_name: 'S', unit_label: 'Daire 3', block_name: 'A', full_name: 'Ali', email: 'ali@example.com' }])],
      [SUSPENSION, ok(suspended ? [{ x: 1 }] : [])],
    ]);
    pool.connect = async () => ({ query: client.query, release() {} });
    return client.log;
  }

  it('approveJoinRequest: askıdaki kişinin başvurusu onaylanmaz: 409 ACCESS_SUSPENDED; üyelik YAZILMAZ / yeniden aktifleşmez, ROLLBACK; başvuru PENDING kalır', async () => {
    const log = approveClient({ suspended: true });
    await assert.rejects(
      approveJoinRequest({ requestId: 9, authUser: superUser }),
      (error) => error.statusCode === 409 && error.code === 'ACCESS_SUSPENDED',
    );
    assert.equal(has(log, /^INSERT INTO apartment_memberships/), false);
    assert.equal(has(log, /^INSERT INTO site_memberships/), false);
    assert.equal(has(log, /^UPDATE join_requests/), false);
    assert.ok(has(log, /^ROLLBACK$/));
    assert.equal(has(log, /^COMMIT$/), false);
    assert.deepEqual(find(log, SUSPENSION).params, [3, 77]);
    assert.ok(indexOf(log, SUSPENSION) > indexOf(log, /^SELECT id FROM apartments WHERE id = \$1 FOR UPDATE/), 'daire kilidinden sonra bakılır (eşzamanlı askı ile onay serileşir)');
  });

  it('approveJoinRequest: askı yoksa onay aynen sürer (üyelik + site üyeliği + durum APPROVED, COMMIT)', async () => {
    const log = approveClient({ suspended: false });
    const result = await approveJoinRequest({ requestId: 9, authUser: superUser });
    assert.equal(result.ok, true);
    assert.ok(has(log, /^INSERT INTO apartment_memberships/));
    assert.ok(has(log, /^UPDATE join_requests/));
    assert.ok(has(log, /^COMMIT$/));
  });
});

describe('kaynak: insertRequest süresi dolmuş bekleyen talepleri önce kapatır', () => {
  it('ayni dairenin suresi dolmus bekleyenleri INSERT\'ten ONCE expired yapilir (kismi tekil indeks yeni talebi engellemesin)', () => {
    const service = read('src/modules/apartment_mgmt_service.js');
    const start = service.indexOf('async function insertRequest(');
    const body = service.slice(start, service.indexOf('\n}\n', start));
    const expire = body.indexOf("UPDATE apartment_link_requests SET status = 'expired', responded_at = NOW(), updated_at = NOW()");
    const insert = body.indexOf('INSERT INTO apartment_link_requests');
    assert.ok(expire > 0 && insert > expire, 'once expired, sonra INSERT');
    assert.match(body, /WHERE apartment_id = \$1 AND status = 'pending' AND expires_at <= NOW\(\)/);
    assert.match(body, /\[state\.apartment\.id\]/);
  });
});
