// Kritik yetki olaylarının denetim kaydı (audit_log) - DB'siz, sahte havuz / bağlantı.
//  - Kullanıcı hesabı (admin_routes + modules/user_account_audit.js): user.created / updated / role_changed / password_set / activated / deactivated / deleted
//    ve abonelik talebi kararı
//  - Site yöneticisi ve site silme (services/site_service.js): site_manager.added / invited / removed / invitation_revoked, site.deleted, silme talebi
//  - Katılım başvurusu (services/membership_service.js): join_request.approved / rejected
//  - Kapı özel izni (services/membership_service.js): door_permission.granted / denied / removed ve toplu karşılıkları
//  - Cihaz sahipliği (services/device_service.js): device.ownership_released
// Her olay için: recordAudit DOĞRU action / hedef / site ile, değişikliği yapan AYNI bağlantıdan (işlem içinde; havuzdan değil) ve KİŞİSEL VERİ
// (ad, e-posta, parola, serbest metin) içermeyen details ile çağrılır.
import { describe, it, before, after, beforeEach, afterEach, mock } from 'node:test';
import assert from 'node:assert/strict';
import express from 'express';
import '../src/utils/async_errors.js';
import { pool } from '../src/db.js';
import { adminRouter } from '../src/routes/admin_routes.js';
import { createErrorHandler } from '../src/middlewares/error_handler.js';
import { SQL_BULK_BLOCK_USERS } from '../src/services/membership_rules.js';
import {
  approveJoinRequest,
  rejectJoinRequest,
  setBulkDoorAccessOverride,
  setDoorAccessOverride,
} from '../src/services/membership_service.js';
import {
  deleteSitePermanently,
  inviteSiteManager,
  rejectOrCancelSiteDeletion,
  removeSiteManager,
  requestSiteDeletion,
  revokeSiteManagerInvitation,
  upsertSiteManagerLink,
} from '../src/services/site_service.js';
import { releaseDeviceOwnership } from '../src/services/device_service.js';
import {
  USER_AUDIT_ACTIONS,
  auditUserActiveChange,
  auditUserDeleted,
  auditUserUpdated,
} from '../src/modules/user_account_audit.js';

const norm = (text) => String(text).replace(/\s+/g, ' ').trim();
const ok = (rows = [], rowCount = rows.length) => ({ rows, rowCount });
const AUDIT_INSERT = /^INSERT INTO audit_log/;

/** Günlükteki `INSERT INTO audit_log` çağrılarını okunur biçime çevirir (parametre sırası: audit_service.recordAudit). */
function auditsOf(log) {
  return log
    .map((entry, index) => ({ entry, index }))
    .filter(({ entry }) => AUDIT_INSERT.test(entry.sql))
    .map(({ entry, index }) => ({
      index,
      actorUserCode: entry.params[0],
      actorName: entry.params[1],
      actorRole: entry.params[2],
      action: entry.params[3],
      siteCode: entry.params[4],
      targetType: entry.params[5],
      targetId: entry.params[6],
      details: JSON.parse(entry.params[7]),
      raw: entry.params[7],
    }));
}
const indexOf = (log, pattern) => log.findIndex((entry) => pattern.test(entry.sql));
const has = (log, pattern) => indexOf(log, pattern) >= 0;

/** Kişisel veri sızmadığını doğrular: ham ayrıntı JSON'unda yasak metinlerin hiçbiri geçmez. */
function assertNoPersonalData(audit, forbidden) {
  for (const text of forbidden) {
    assert.equal(audit.raw.includes(text), false, `${audit.action}: ayrıntıda "${text}" olmamalı -> ${audit.raw}`);
  }
}

/** Havuz (pool.query) ve tek bağlantı (pool.connect) için sahte; kurallar [regex, sonuç | (sql, params) => sonuç]. */
function install({ poolRules = [], clientRules = [] } = {}) {
  const poolLog = [];
  const clientLog = [];
  const runner = (log, rules) => async (text, params = []) => {
    const sql = norm(text);
    log.push({ sql, params });
    for (const [pattern, result] of rules) {
      if (pattern.test(sql)) {
        return typeof result === 'function' ? result(sql, params) : result;
      }
    }
    return ok();
  };
  pool.query = runner(poolLog, poolRules);
  const client = { released: 0, query: runner(clientLog, clientRules), release() { client.released += 1; } };
  pool.connect = async () => client;
  return { poolLog, clientLog, client };
}

const originalEnv = { SMTP_HOST: process.env.SMTP_HOST };

beforeEach(() => {
  // E-posta gönderimi bu testlerde asla denenmez (eksik SMTP -> servis hatayı günlüğe yazıp sürer).
  process.env.SMTP_HOST = '';
  mock.method(console, 'log', () => {});
  mock.method(console, 'warn', () => {});
  mock.method(console, 'error', () => {});
});

afterEach(() => {
  delete pool.query;
  delete pool.connect;
  if (originalEnv.SMTP_HOST === undefined) {
    delete process.env.SMTP_HOST;
  } else {
    process.env.SMTP_HOST = originalEnv.SMTP_HOST;
  }
  mock.restoreAll();
});

// ---------------------------------------------------------------------------------------------------------------------------------
// 1) Kullanıcı hesabı: admin uçları (HTTP, sabit süper kullanıcı)
// ---------------------------------------------------------------------------------------------------------------------------------
describe('kullanıcı hesabı denetim kaydı (admin uçları)', () => {
  const SUPER = { id: 1, user_code: 1, role: 'super_user', full_name: 'Süper Yönetici', is_active: true };
  const STRONG = 'Zarif-Parola-2026!x';
  let server;
  let baseUrl;
  let poolCalls;
  let clientCalls;
  let poolHandler;
  let clientHandler;
  let released;
  const originalConnect = pool.connect;
  const originalQuery = pool.query;
  const originalConsole = { error: console.error, warn: console.warn };

  before(async () => {
    for (const layer of adminRouter.stack) {
      if (!layer.route) continue;
      layer.route.stack[0].handle = (req, _res, next) => {
        req.authUser = { ...SUPER };
        next();
      };
    }
    const app = express();
    app.set('env', 'test');
    app.use(express.json());
    app.use(adminRouter);
    app.use(createErrorHandler({ logger: { error: () => {}, log: () => {}, warn: () => {} } }));
    await new Promise((resolve) => {
      server = app.listen(0, '127.0.0.1', resolve);
    });
    baseUrl = `http://127.0.0.1:${server.address().port}`;
  });

  after(() => new Promise((resolve) => {
    pool.query = originalQuery;
    pool.connect = originalConnect;
    server.closeAllConnections?.();
    server.close(resolve);
  }));

  beforeEach(() => {
    poolCalls = [];
    clientCalls = [];
    released = 0;
    poolHandler = async () => ok();
    clientHandler = async () => ok();
    pool.query = async (text, params) => {
      const sql = norm(text);
      poolCalls.push({ sql, params: params ?? [] });
      return poolHandler(sql, params ?? []);
    };
    pool.connect = async () => ({
      query: async (text, params) => {
        const sql = norm(text);
        clientCalls.push({ sql, params: params ?? [] });
        return clientHandler(sql, params ?? []);
      },
      release() {
        released += 1;
      },
    });
  });

  const send = async (method, path, body) => {
    const response = await fetch(`${baseUrl}${path}`, {
      method,
      headers: { 'content-type': 'application/json' },
      body: body === undefined ? undefined : JSON.stringify(body),
    });
    const text = await response.text();
    let json = null;
    try {
      json = JSON.parse(text);
    } catch (_e) {
      // gövdesiz yanıt
    }
    return { status: response.status, body: json };
  };
  const userRow = (extra = {}) => ({ id: 41001, full_name: 'Yeni Kişi', email: 'yeni@example.com', login_name: null, role: 'individual', is_active: false, email_verified: true, approval_status: 'approved', phone_number: '05321112233', created_at: new Date('2026-10-26T10:00:00Z'), ...extra });
  const PERSONAL = ['Yeni Kişi', 'Yeni Ad Soyad', 'yeni@example.com', '05321112233', STRONG, 'Süper Yönetici'];
  // Kayıttaki "kim" alanı süper kullanıcının KENDİ adıdır (eylemi yapan); ayrıntıda ise hiçbir ad / e-posta / telefon / parola olmamalı.
  const PERSONAL_IN_DETAILS = PERSONAL;

  it('POST /admin/users: user.created AYNI işlemde (INSERT -> denetim -> bayrak -> COMMIT); ayrıntıda yalnız rol / aktiflik / geçici parola', async () => {
    clientHandler = async (sql) => (/^INSERT INTO users/.test(sql) ? ok([userRow()]) : ok());
    const res = await send('POST', '/admin/users', { full_name: 'Yeni Kişi', email: 'yeni@example.com', password: STRONG, role: 'individual', phone_number: '05321112233' });
    assert.equal(res.status, 201, JSON.stringify(res.body));
    const [audit] = auditsOf(clientCalls);
    assert.equal(auditsOf(poolCalls).length, 0, 'denetim havuzdan değil işlem bağlantısından');
    assert.deepEqual(
      { action: audit.action, siteCode: audit.siteCode, targetType: audit.targetType, targetId: audit.targetId, actorUserCode: audit.actorUserCode, actorRole: audit.actorRole },
      { action: 'user.created', siteCode: null, targetType: 'user', targetId: '41001', actorUserCode: 1, actorRole: 'super_user' },
    );
    assert.deepEqual(audit.details, { role: 'individual', is_active: false, temporary_password: true });
    assertNoPersonalData(audit, PERSONAL_IN_DETAILS);
    const begin = indexOf(clientCalls, /^BEGIN$/);
    const insert = indexOf(clientCalls, /^INSERT INTO users/);
    const flag = indexOf(clientCalls, /^UPDATE users SET must_change_password = TRUE/);
    const commit = indexOf(clientCalls, /^COMMIT$/);
    assert.ok(begin === 0 && begin < insert && insert < audit.index && audit.index < flag && flag < commit, JSON.stringify(clientCalls.map((c) => c.sql.slice(0, 30))));
    assert.equal(released, 1);
  });

  it('POST /admin/users: kullanıcı INSERT hatasında denetim kaydı da geri alınır (ROLLBACK, COMMIT yok)', async () => {
    clientHandler = async (sql) => {
      if (/^INSERT INTO users/.test(sql)) throw Object.assign(new Error('dup'), { code: '23505', constraint: 'users_email_key' });
      return ok();
    };
    const res = await send('POST', '/admin/users', { full_name: 'Yeni Kişi', email: 'yeni@example.com', password: STRONG, role: 'individual', phone_number: '05321112233' });
    assert.equal(res.status, 409);
    assert.equal(auditsOf(clientCalls).length, 0, 'kullanıcı yazılamadı -> denetim satırı da yazılmaz');
    assert.ok(has(clientCalls, /^ROLLBACK$/));
    assert.equal(has(clientCalls, /^COMMIT$/), false);
  });

  it('PATCH /admin/users/:id: user.updated (alan ADLARI) + user.role_changed (eski / yeni rol) + user.password_set (parola YOK) + user.deactivated; hepsi aynı işlemde', async () => {
    poolHandler = async (sql) => (/^SELECT role FROM users WHERE user_code = \$1$/.test(sql) ? ok([{ role: 'site_manager' }]) : ok());
    clientHandler = async (sql) => {
      if (/^SELECT role, is_active FROM users WHERE user_code = \$1 AND deleted_at IS NULL FOR NO KEY UPDATE$/.test(sql)) return ok([{ role: 'site_manager', is_active: true }]);
      if (/^UPDATE users SET .*password_hash/.test(sql)) return ok([userRow({ id: 41010, role: 'individual', is_active: false })]);
      return ok();
    };
    const res = await send('PATCH', '/admin/users/41010', { full_name: 'Yeni Ad Soyad', password: STRONG, role: 'individual', is_active: false });
    assert.equal(res.status, 200, JSON.stringify(res.body));
    const audits = auditsOf(clientCalls);
    assert.deepEqual(audits.map((a) => a.action), ['user.updated', 'user.role_changed', 'user.password_set', 'user.deactivated']);
    assert.deepEqual(audits[0].details, { fields: ['full_name', 'password', 'is_active', 'role'] });
    assert.deepEqual(audits[1].details, { old_role: 'site_manager', new_role: 'individual' });
    assert.deepEqual(audits[2].details, { temporary: true });
    assert.deepEqual(audits[3].details, { old_is_active: true, new_is_active: false });
    for (const audit of audits) {
      assert.equal(audit.targetType, 'user');
      assert.equal(audit.targetId, '41010');
      assert.equal(audit.siteCode, null);
      assert.equal(audit.actorUserCode, 1);
      assertNoPersonalData(audit, PERSONAL_IN_DETAILS);
    }
    const lock = indexOf(clientCalls, /FOR NO KEY UPDATE$/);
    const write = indexOf(clientCalls, /^UPDATE users SET .*password_hash/);
    const flag = indexOf(clientCalls, /^UPDATE users SET must_change_password = TRUE/);
    const commit = indexOf(clientCalls, /^COMMIT$/);
    assert.ok(lock < write && write < audits[0].index && audits[3].index < flag && flag < commit, JSON.stringify(clientCalls.map((c) => c.sql.slice(0, 30))));
    assert.equal(auditsOf(poolCalls).length, 0);
  });

  it('PATCH /admin/users/:id: rol / aktiflik GERÇEKTEN değişmediyse role_changed ve activated / deactivated yazılmaz (user.updated yine yazılır)', async () => {
    clientHandler = async (sql) => {
      if (/FOR NO KEY UPDATE$/.test(sql)) return ok([{ role: 'individual', is_active: false }]);
      if (/^UPDATE users SET /.test(sql)) return ok([userRow({ id: 41011, role: 'individual', is_active: false })]);
      return ok();
    };
    const res = await send('PATCH', '/admin/users/41011', { role: 'individual', is_active: false, phone_number: '05321112233' });
    assert.equal(res.status, 200, JSON.stringify(res.body));
    const audits = auditsOf(clientCalls);
    assert.deepEqual(audits.map((a) => a.action), ['user.updated']);
    assert.deepEqual(audits[0].details, { fields: ['phone_number', 'is_active', 'role'] });
  });

  it('PATCH /admin/users/:id: kullanıcı bulunamadı / silinmiş -> denetim kaydı yazılmaz', async () => {
    poolHandler = async (sql) => (/^SELECT deleted_at FROM users/.test(sql) ? ok([{ deleted_at: new Date('2026-10-01T10:00:00Z') }]) : ok());
    const res = await send('PATCH', '/admin/users/41012', { full_name: 'Yeni Ad Soyad' });
    assert.equal(res.status, 409);
    assert.equal(auditsOf(clientCalls).length, 0);
  });

  it('PATCH /admin/users/:id/activation: aktiflik değişince user.deactivated / user.activated; değişmediyse kayıt yok; ayrıntıda yalnız durum', async () => {
    clientHandler = async (sql) => {
      if (/FOR NO KEY UPDATE$/.test(sql)) return ok([{ role: 'site_manager', is_active: true }]);
      if (/^UPDATE users SET is_active/.test(sql)) return ok([userRow({ id: 41013, role: 'site_manager', is_active: false })]);
      return ok();
    };
    let res = await send('PATCH', '/admin/users/41013/activation', { is_active: false });
    assert.equal(res.status, 200, JSON.stringify(res.body));
    let audits = auditsOf(clientCalls);
    assert.equal(audits.length, 1);
    assert.equal(audits[0].action, 'user.deactivated');
    assert.deepEqual(audits[0].details, { old_is_active: true, new_is_active: false });
    assert.equal(audits[0].targetId, '41013');
    assertNoPersonalData(audits[0], PERSONAL_IN_DETAILS);
    assert.ok(audits[0].index < indexOf(clientCalls, /^COMMIT$/));

    clientCalls.length = 0;
    clientHandler = async (sql) => {
      if (/FOR NO KEY UPDATE$/.test(sql)) return ok([{ role: 'site_manager', is_active: false }]);
      if (/^UPDATE users SET is_active/.test(sql)) return ok([userRow({ id: 41013, role: 'site_manager', is_active: true })]);
      return ok();
    };
    res = await send('PATCH', '/admin/users/41013/activation', { is_active: true });
    assert.equal(res.status, 200);
    audits = auditsOf(clientCalls);
    assert.deepEqual(audits.map((a) => a.action), ['user.activated']);

    clientCalls.length = 0;
    clientHandler = async (sql) => {
      if (/FOR NO KEY UPDATE$/.test(sql)) return ok([{ role: 'site_manager', is_active: true }]);
      if (/^UPDATE users SET is_active/.test(sql)) return ok([userRow({ id: 41013, role: 'site_manager', is_active: true })]);
      return ok();
    };
    res = await send('PATCH', '/admin/users/41013/activation', { is_active: true });
    assert.equal(res.status, 200);
    assert.equal(auditsOf(clientCalls).length, 0, 'zaten aktif -> değişiklik yok, kayıt yok');
  });

  it('DELETE /admin/users/:id: user.deleted silme ile AYNI işlemde (silme -> denetim -> COMMIT); ayrıntıda silinen rol kodu ve etkilenen site sayısı', async () => {
    poolHandler = async (sql) => (/^SELECT site_code FROM site_manager_sites WHERE manager_user_code = \$1 UNION/.test(sql) ? ok([{ site_code: 5 }, { site_code: 6 }]) : ok());
    clientHandler = async (sql) => (/^DELETE FROM users WHERE user_code = \$1/.test(sql) ? ok([{ role: 'site_manager' }], 1) : ok());
    const res = await send('DELETE', '/admin/users/41014');
    assert.equal(res.status, 204);
    const [audit] = auditsOf(clientCalls);
    assert.equal(auditsOf(clientCalls).length, 1);
    assert.deepEqual(
      { action: audit.action, siteCode: audit.siteCode, targetType: audit.targetType, targetId: audit.targetId, actorUserCode: audit.actorUserCode },
      { action: 'user.deleted', siteCode: null, targetType: 'user', targetId: '41014', actorUserCode: 1 },
    );
    assert.deepEqual(audit.details, { role: 'site_manager', affected_site_count: 2 });
    assertNoPersonalData(audit, PERSONAL_IN_DETAILS);
    const del = indexOf(clientCalls, /^DELETE FROM users WHERE user_code = \$1/);
    const commit = indexOf(clientCalls, /^COMMIT$/);
    assert.ok(del < audit.index && audit.index < commit);
    assert.equal(auditsOf(poolCalls).length, 0);
  });

  it('DELETE /admin/users/:id: silme 0 satır döndürürse (yarış) denetim kaydı YAZILMAZ; ROLLBACK', async () => {
    clientHandler = async () => ok();
    const res = await send('DELETE', '/admin/users/41015');
    assert.equal(res.status, 404);
    assert.equal(auditsOf(clientCalls).length, 0);
    assert.ok(has(clientCalls, /^ROLLBACK$/));
  });

  it('PATCH /admin/subscription-requests/:id: onay user.subscription_approved, ret user.subscription_rejected (aynı işlemde; ayrıntıda yalnız rol)', async () => {
    clientHandler = async (sql) => (/^UPDATE users SET approval_status/.test(sql) ? ok([userRow({ id: 41020, role: 'site_manager', is_active: true, approval_status: 'approved' })]) : ok());
    let res = await send('PATCH', '/admin/subscription-requests/41020', { action: 'approve' });
    assert.equal(res.status, 200, JSON.stringify(res.body));
    let audits = auditsOf(clientCalls);
    assert.deepEqual(audits.map((a) => [a.action, a.targetType, a.targetId, a.details]), [['user.subscription_approved', 'user', '41020', { role: 'site_manager' }]]);
    assertNoPersonalData(audits[0], PERSONAL_IN_DETAILS);
    assert.ok(audits[0].index < indexOf(clientCalls, /^COMMIT$/));

    clientCalls.length = 0;
    clientHandler = async (sql) => (/^UPDATE users SET approval_status/.test(sql) ? ok([userRow({ id: 41020, role: 'site_manager', is_active: false, approval_status: 'rejected' })]) : ok());
    res = await send('PATCH', '/admin/subscription-requests/41020', { action: 'reject' });
    assert.equal(res.status, 200);
    audits = auditsOf(clientCalls);
    assert.deepEqual(audits.map((a) => a.action), ['user.subscription_rejected']);
  });

  it('PATCH /admin/sites/:id/approval: site.rejected güncelleme BAŞARILI olduktan sonra; sonuçlanmış talepte (409) kayıt yok', async () => {
    const siteRow = { id: 7001, name: 'Test Sitesi', approval_status: 'pending', block_count: 1, apartment_count: 0, door_count: 1 };
    let updated = true;
    poolHandler = async (sql) => {
      if (/^SELECT/.test(sql) && /FROM sites/.test(sql)) return ok([siteRow]);
      if (/^UPDATE sites SET approval_status/.test(sql)) return updated ? ok([{ ...siteRow, approval_status: 'rejected' }]) : ok([], 0);
      return ok();
    };
    let res = await send('PATCH', '/admin/sites/7001/approval', { action: 'reject' });
    assert.equal(res.status, 200, JSON.stringify(res.body));
    let audits = auditsOf(poolCalls);
    assert.deepEqual(audits.map((a) => [a.action, a.siteCode, a.targetType, a.targetId, a.actorRole]), [['site.rejected', 7001, 'site', '7001', 'super_user']]);
    assert.ok(audits[0].index > indexOf(poolCalls, /^UPDATE sites SET approval_status/));

    poolCalls.length = 0;
    updated = false;
    res = await send('PATCH', '/admin/sites/7001/approval', { action: 'reject' });
    assert.equal(res.status, 409);
    audits = auditsOf(poolCalls);
    assert.equal(audits.length, 0);
  });

  it('DELETE /admin/apartments/:id/resident: apartment.resident_cleared (site kodu ile, ayrıntıda kişisel veri yok)', async () => {
    poolHandler = async () => ok([{ id: 5001, site_code: 7001 }]);
    clientHandler = async () => ok([{ id: 5001, site_code: 7001 }]);
    const res = await send('DELETE', '/admin/apartments/5001/resident');
    assert.equal(res.status, 200, JSON.stringify(res.body));
    const audits = [...auditsOf(poolCalls), ...auditsOf(clientCalls)];
    assert.deepEqual(audits.map((a) => [a.action, a.siteCode, a.targetType, a.targetId]), [['apartment.resident_cleared', 7001, 'apartment', '5001']]);
    assert.deepEqual(audits[0].details, {});
  });
});

describe('user_account_audit: yardımcılar', () => {
  const fakeDb = () => {
    const log = [];
    return { log, query: async (text, params = []) => { log.push({ sql: norm(text), params }); return ok(); } };
  };
  const actor = { user_code: 1, full_name: 'Süper', role: 'super_user' };

  it('eylem listesi tekil ve "alan.eylem" biçiminde', () => {
    assert.equal(new Set(USER_AUDIT_ACTIONS).size, USER_AUDIT_ACTIONS.length);
    for (const action of USER_AUDIT_ACTIONS) assert.match(action, /^user\.[a-z_]+$/);
  });

  it('auditUserUpdated: gönderilmeyen alan listelenmez; rol okunamadıysa (before null) role_changed eski rolsüz yazılır', async () => {
    const db = fakeDb();
    await auditUserUpdated(db, actor, { before: null, user: { id: 7, role: 'super_user', is_active: true }, changes: { role: 'super_user' } });
    const audits = auditsOf(db.log);
    assert.deepEqual(audits.map((a) => a.action), ['user.updated', 'user.role_changed']);
    assert.deepEqual(audits[0].details, { fields: ['role'] });
    assert.deepEqual(audits[1].details, { old_role: null, new_role: 'super_user' });
    for (const call of db.log) assert.ok(/^SAVEPOINT|^RELEASE|^INSERT INTO audit_log/.test(call.sql), 'recordAudit inTransaction: SAVEPOINT içinde');
  });

  it('auditUserActiveChange: değişim yoksa false ve satır yok; before bilinmiyorsa yazılır', async () => {
    const db = fakeDb();
    assert.equal(await auditUserActiveChange(db, actor, { before: { is_active: true }, user: { id: 7, is_active: true } }), false);
    assert.equal(db.log.length, 0);
    assert.equal(await auditUserActiveChange(db, actor, { before: null, user: { id: 7, is_active: false } }), true);
    assert.deepEqual(auditsOf(db.log).map((a) => [a.action, a.details]), [['user.deactivated', { old_is_active: null, new_is_active: false }]]);
  });

  it('auditUserDeleted: rol yoksa null, sayı geçersizse 0', async () => {
    const db = fakeDb();
    await auditUserDeleted(db, actor, { userCode: 9, role: undefined, affectedSiteCount: undefined });
    assert.deepEqual(auditsOf(db.log)[0].details, { role: null, affected_site_count: 0 });
  });
});

// ---------------------------------------------------------------------------------------------------------------------------------
// 2) Site yöneticisi ve site silme
// ---------------------------------------------------------------------------------------------------------------------------------
describe('site yöneticisi ve site silme denetim kaydı (site_service)', () => {
  const SITE_ROW = /FROM sites s LEFT JOIN LATERAL/;
  const inviter = { id: 9, user_code: 9, userCode: 9, role: 'site_manager', full_name: 'Yönetici Ayşe' };

  it('inviteSiteManager (kayıtlı kullanıcı): site_manager.added yetki yazımıyla AYNI işlemde; ad / e-posta yazılmaz', async () => {
    const { poolLog, clientLog } = install({
      poolRules: [
        [SITE_ROW, ok([{ site_code: 55, name: 'Gül Sitesi' }])],
        [/^SELECT user_code, full_name, email, role FROM users WHERE LOWER\(email\)/, ok([{ user_code: 77, full_name: 'Ali Veli', email: 'ali@example.com', role: 'individual' }])],
      ],
      clientRules: [[/FOR KEY SHARE$/, ok([{ user_code: 77 }])]],
    });
    const result = await inviteSiteManager({ siteCode: 55, email: 'ali@example.com', fullName: 'Ali Veli', inviterUser: inviter });
    assert.equal(result.ok, true);
    const audits = auditsOf(clientLog);
    assert.equal(audits.length, 1);
    assert.equal(auditsOf(poolLog).length, 0, 'havuzdan değil işlem bağlantısından');
    const [audit] = audits;
    assert.deepEqual(
      { action: audit.action, siteCode: audit.siteCode, targetType: audit.targetType, targetId: audit.targetId, actorUserCode: audit.actorUserCode, actorRole: audit.actorRole },
      { action: 'site_manager.added', siteCode: 55, targetType: 'user', targetId: '77', actorUserCode: 9, actorRole: 'site_manager' },
    );
    assert.deepEqual(audit.details, { role: 'SITE_ADMIN', via: 'invitation', promoted_to_site_manager: true });
    assertNoPersonalData(audit, ['ali@example.com', 'Ali Veli', 'Gül Sitesi']);
    const link = indexOf(clientLog, /^INSERT INTO site_manager_sites/);
    const roleUpdate = indexOf(clientLog, /^UPDATE users SET role = 'site_manager'/);
    const commit = indexOf(clientLog, /^COMMIT$/);
    assert.ok(link < audit.index && roleUpdate < audit.index && audit.index < commit, JSON.stringify(clientLog.map((c) => c.sql.slice(0, 30))));
  });

  it('inviteSiteManager: hedef zaten site_manager ise promoted_to_site_manager false; zaten yönetici (409) ise denetim kaydı yok', async () => {
    const rules = {
      poolRules: [
        [SITE_ROW, ok([{ site_code: 55, name: 'Gül Sitesi' }])],
        [/^SELECT user_code, full_name, email, role FROM users WHERE LOWER\(email\)/, ok([{ user_code: 77, full_name: 'Ali Veli', email: 'ali@example.com', role: 'site_manager' }])],
      ],
      clientRules: [[/FOR KEY SHARE$/, ok([{ user_code: 77 }])]],
    };
    let env = install(rules);
    await inviteSiteManager({ siteCode: 55, email: 'ali@example.com', inviterUser: inviter });
    assert.equal(auditsOf(env.clientLog)[0].details.promoted_to_site_manager, false);

    env = install({ ...rules, clientRules: [...rules.clientRules, [/^SELECT 1 FROM site_manager_sites WHERE site_code = \$1 AND manager_user_code = \$2/, ok([{ x: 1 }])]] });
    await assert.rejects(() => inviteSiteManager({ siteCode: 55, email: 'ali@example.com', inviterUser: inviter }), (error) => error.statusCode === 409);
    assert.equal(auditsOf(env.clientLog).length, 0);
    assert.ok(has(env.clientLog, /^ROLLBACK$/));
  });

  it('inviteSiteManager (kayıtsız e-posta): site_manager.invited davet satırıyla AYNI işlemde; hedef davet numarası, e-posta / ad yazılmaz', async () => {
    const { poolLog, clientLog } = install({
      poolRules: [
        [SITE_ROW, ok([{ site_code: 55, name: 'Gül Sitesi' }])],
        [/^SELECT user_code, full_name, email, role FROM users WHERE LOWER\(email\)/, ok()],
      ],
      clientRules: [[/^INSERT INTO site_manager_invitations/, ok([{ id: 412 }])]],
    });
    await inviteSiteManager({ siteCode: 55, email: 'yeni.kisi@example.com', fullName: 'Yeni Kişi', inviterUser: inviter });
    const audits = auditsOf(clientLog);
    assert.equal(audits.length, 1);
    assert.equal(auditsOf(poolLog).length, 0);
    const [audit] = audits;
    assert.deepEqual(
      { action: audit.action, siteCode: audit.siteCode, targetType: audit.targetType, targetId: audit.targetId, actorUserCode: audit.actorUserCode },
      { action: 'site_manager.invited', siteCode: 55, targetType: 'site_manager_invitation', targetId: '412', actorUserCode: 9 },
    );
    assert.deepEqual(audit.details, { expires_in_days: 7 });
    assertNoPersonalData(audit, ['yeni.kisi@example.com', 'Yeni Kişi', 'Gül Sitesi']);
    const begin = indexOf(clientLog, /^BEGIN$/);
    const insert = indexOf(clientLog, /^INSERT INTO site_manager_invitations/);
    const commit = indexOf(clientLog, /^COMMIT$/);
    assert.ok(begin < insert && insert < audit.index && audit.index < commit);
    assert.match(clientLog[insert].sql, /RETURNING id$/);
  });

  it('removeSiteManager: site_manager.removed çıkarma ile AYNI işlemde; çıkarılan rol kodu ve hesabın düştüğü genel rol', async () => {
    const { poolLog, clientLog } = install({
      clientRules: [
        [/^SELECT manager_user_code FROM site_manager_sites WHERE site_code = \$1 FOR UPDATE$/, ok([{ manager_user_code: 7 }, { manager_user_code: 9 }])],
        [/^SELECT user_code, role FROM site_memberships/, ok([{ user_code: 7, role: 'SITE_OWNER' }, { user_code: 9, role: 'SITE_ADMIN' }])],
        [/has_other_managed_sites/, ok([{ has_other_managed_sites: false, has_apartment_membership: false }])],
        [/^SELECT role FROM users WHERE user_code = \$1 FOR NO KEY UPDATE$/, ok([{ role: 'site_manager' }])],
      ],
    });
    const result = await removeSiteManager({ siteCode: 55, targetUserCode: 9, callerUser: { id: 7, user_code: 7, role: 'site_manager', full_name: 'Site Sahibi' } });
    assert.equal(result.ok, true);
    const audits = auditsOf(clientLog);
    assert.equal(audits.length, 1);
    assert.equal(auditsOf(poolLog).length, 0);
    const [audit] = audits;
    assert.deepEqual(
      { action: audit.action, siteCode: audit.siteCode, targetType: audit.targetType, targetId: audit.targetId, actorUserCode: audit.actorUserCode },
      { action: 'site_manager.removed', siteCode: 55, targetType: 'user', targetId: '9', actorUserCode: 7 },
    );
    assert.deepEqual(audit.details, { role: 'SITE_ADMIN', new_user_role: 'individual' });
    assertNoPersonalData(audit, ['Site Sahibi']);
    const del = indexOf(clientLog, /^DELETE FROM site_manager_sites/);
    const roleUpdate = indexOf(clientLog, /^UPDATE users SET role = \$2/);
    const commit = indexOf(clientLog, /^COMMIT$/);
    assert.ok(del < audit.index && roleUpdate < audit.index && audit.index < commit);
  });

  it('removeSiteManager: kural reddederse (son yönetici) denetim kaydı yok, ROLLBACK', async () => {
    const { clientLog } = install({
      clientRules: [
        [/^SELECT manager_user_code FROM site_manager_sites WHERE site_code = \$1 FOR UPDATE$/, ok([{ manager_user_code: 9 }])],
        [/^SELECT user_code, role FROM site_memberships/, ok([{ user_code: 9, role: 'SITE_ADMIN' }])],
      ],
    });
    await assert.rejects(() => removeSiteManager({ siteCode: 55, targetUserCode: 9, callerUser: { id: 1, role: 'super_user' } }), (error) => error.statusCode === 400);
    assert.equal(auditsOf(clientLog).length, 0);
    assert.ok(has(clientLog, /^ROLLBACK$/));
  });

  it('revokeSiteManagerInvitation: site_manager.invitation_revoked iptalle AYNI işlemde; bulunamazsa kayıt yok (404, ROLLBACK)', async () => {
    let env = install({ clientRules: [[/^UPDATE site_manager_invitations/, ok([{ id: 12 }])]] });
    await revokeSiteManagerInvitation({ siteCode: 55, invitationId: 12, callerUser: inviter });
    const [audit] = auditsOf(env.clientLog);
    assert.deepEqual(
      { action: audit.action, siteCode: audit.siteCode, targetType: audit.targetType, targetId: audit.targetId, actorUserCode: audit.actorUserCode, details: audit.details },
      { action: 'site_manager.invitation_revoked', siteCode: 55, targetType: 'site_manager_invitation', targetId: '12', actorUserCode: 9, details: {} },
    );
    assert.ok(audit.index < indexOf(env.clientLog, /^COMMIT$/));

    env = install({ clientRules: [[/^UPDATE site_manager_invitations/, ok()]] });
    await assert.rejects(() => revokeSiteManagerInvitation({ siteCode: 55, invitationId: 12, callerUser: inviter }), (error) => error.statusCode === 404);
    assert.equal(auditsOf(env.clientLog).length, 0);
    assert.ok(has(env.clientLog, /^ROLLBACK$/));
  });

  it('upsertSiteManagerLink (admin ataması): site_manager.added bağ + üyelik yazımıyla AYNI işlemde', async () => {
    const { poolLog, clientLog } = install();
    await upsertSiteManagerLink({ siteCode: 55, managerUserCode: 77, actor: { user_code: 1, role: 'super_user', full_name: 'Süper' } });
    const audits = auditsOf(clientLog);
    assert.equal(audits.length, 1);
    assert.equal(auditsOf(poolLog).length, 0);
    assert.deepEqual(
      { action: audits[0].action, siteCode: audits[0].siteCode, targetType: audits[0].targetType, targetId: audits[0].targetId, details: audits[0].details },
      { action: 'site_manager.added', siteCode: 55, targetType: 'user', targetId: '77', details: { role: 'SITE_ADMIN', via: 'admin_assignment' } },
    );
    const link = indexOf(clientLog, /^INSERT INTO site_manager_sites/);
    const membership = indexOf(clientLog, /^INSERT INTO site_memberships/);
    assert.ok(link < membership && membership < audits[0].index && audits[0].index < indexOf(clientLog, /^COMMIT$/));
  });

  it('upsertSiteManagerLink: yönetici kodu yoksa (null) yazım da denetim kaydı da yok', async () => {
    const { clientLog, poolLog } = install();
    await upsertSiteManagerLink({ siteCode: 55, managerUserCode: null, actor: { user_code: 1 } });
    assert.equal(clientLog.length, 0);
    assert.equal(auditsOf(poolLog).length, 0);
  });

  it('deleteSitePermanently: site.deleted site satırı silinmeden ÖNCE ve aynı işlemde; site kodu kayıtta, site adı ayrıntıda YOK', async () => {
    const { poolLog, clientLog } = install({
      clientRules: [
        [/^SELECT name FROM sites WHERE site_code = \$1 FOR UPDATE/, ok([{ name: 'Gül Sitesi' }])],
        [/^DELETE FROM sites WHERE site_code = \$1/, ok([], 1)],
      ],
    });
    const result = await deleteSitePermanently(42, { id: 1, user_code: 1, role: 'super_user', full_name: 'Süper' });
    assert.equal(result.deleted, true);
    const audits = auditsOf(clientLog);
    assert.equal(audits.length, 1);
    assert.equal(auditsOf(poolLog).length, 0);
    const [audit] = audits;
    assert.deepEqual(
      { action: audit.action, siteCode: audit.siteCode, targetType: audit.targetType, targetId: audit.targetId, actorUserCode: audit.actorUserCode, details: audit.details },
      { action: 'site.deleted', siteCode: 42, targetType: 'site', targetId: '42', actorUserCode: 1, details: { device_count: 0 } },
    );
    assertNoPersonalData(audit, ['Gül Sitesi']);
    assert.ok(audit.index < indexOf(clientLog, /^DELETE FROM sites WHERE site_code = \$1/), 'site satırı silinmeden önce');
    assert.ok(indexOf(clientLog, /^DELETE FROM sites WHERE site_code = \$1/) < indexOf(clientLog, /^COMMIT$/));
  });

  it('deleteSitePermanently: site bulunamazsa denetim kaydı yazılmadan 404 (ROLLBACK)', async () => {
    const { clientLog } = install({ clientRules: [[/^SELECT name FROM sites/, ok()]] });
    await assert.rejects(() => deleteSitePermanently(42, { id: 1, role: 'super_user' }), (error) => error.statusCode === 404);
    assert.equal(auditsOf(clientLog).length, 0);
  });

  it('requestSiteDeletion / rejectOrCancelSiteDeletion: site.deletion_requested ve site.deletion_cancelled (havuzdan; tek ifadelik güncelleme)', async () => {
    let env = install({
      poolRules: [
        [/^SELECT site_code, name, deletion_status, deletion_requested_by_role/, ok([{ site_code: 55, name: 'Gül Sitesi', deletion_status: 'none' }])],
        [/^SELECT manager_user_code FROM site_manager_sites WHERE site_code = \$1 UNION/, ok([{ manager_user_code: 7 }])],
      ],
    });
    const requested = await requestSiteDeletion({ siteCode: 55, authUser: { id: 1, user_code: 1, role: 'super_user', full_name: 'Süper' } });
    assert.equal(requested.pending, true);
    let audits = auditsOf(env.poolLog);
    assert.equal(audits.length, 1);
    assert.deepEqual(
      { action: audits[0].action, siteCode: audits[0].siteCode, targetType: audits[0].targetType, targetId: audits[0].targetId, details: audits[0].details },
      { action: 'site.deletion_requested', siteCode: 55, targetType: 'site', targetId: '55', details: { requested_by_role: 'super_user' } },
    );
    assert.ok(indexOf(env.poolLog, /^UPDATE sites SET deletion_status = 'pending_site_manager_approval'/) < audits[0].index);
    assertNoPersonalData(audits[0], ['Gül Sitesi', 'Süper']);

    env = install({ poolRules: [[/^SELECT site_code, deletion_status FROM sites/, ok([{ site_code: 55, deletion_status: 'pending_site_manager_approval' }])]] });
    await rejectOrCancelSiteDeletion({ siteCode: 55, authUser: { id: 1, user_code: 1, role: 'super_user' } });
    audits = auditsOf(env.poolLog);
    assert.deepEqual(
      audits.map((a) => [a.action, a.siteCode, a.details]),
      [['site.deletion_cancelled', 55, { previous_status: 'pending_site_manager_approval' }]],
    );
  });
});

// ---------------------------------------------------------------------------------------------------------------------------------
// 3) Katılım başvurusu ve kapı özel izni
// ---------------------------------------------------------------------------------------------------------------------------------
describe('katılım başvurusu ve kapı özel izni denetim kaydı (membership_service)', () => {
  const superActor = { id: 1, user_code: 1, role: 'super_user', full_name: 'Süper' };
  const joinRow = { id: 9, site_code: 101, apartment_id: 3, block_id: 5, user_code: 77, status: 'PENDING', site_name: 'Gül Sitesi', unit_label: 'Daire 3', block_name: 'A', full_name: 'Ali Veli', email: 'ali@example.com' };

  it('approveJoinRequest: join_request.approved onayla AYNI işlemde (durum güncellemesinden sonra, COMMIT\'ten önce); ad / e-posta yazılmaz', async () => {
    const { poolLog, clientLog } = install({ clientRules: [[/FOR UPDATE OF jr FOR KEY SHARE OF u$/, ok([joinRow])]] });
    const result = await approveJoinRequest({ requestId: 9, authUser: superActor });
    assert.equal(result.assignedRole, 'APARTMENT_ADMIN');
    const audits = auditsOf(clientLog);
    assert.equal(audits.length, 1);
    assert.equal(auditsOf(poolLog).length, 0);
    const [audit] = audits;
    assert.deepEqual(
      { action: audit.action, siteCode: audit.siteCode, targetType: audit.targetType, targetId: audit.targetId, actorUserCode: audit.actorUserCode, actorRole: audit.actorRole, details: audit.details },
      { action: 'join_request.approved', siteCode: 101, targetType: 'join_request', targetId: '9', actorUserCode: 1, actorRole: 'super_user', details: { user_code: 77, apartment_id: 3, assigned_role: 'APARTMENT_ADMIN' } },
    );
    assertNoPersonalData(audit, ['ali@example.com', 'Ali Veli', 'Gül Sitesi']);
    assert.ok(indexOf(clientLog, /^UPDATE join_requests SET status = 'APPROVED'/) < audit.index);
    assert.ok(audit.index < indexOf(clientLog, /^COMMIT$/));
  });

  it('approveJoinRequest: askı nedeniyle reddedilirse (409) denetim kaydı yazılmaz', async () => {
    const { clientLog } = install({
      clientRules: [
        [/FOR UPDATE OF jr FOR KEY SHARE OF u$/, ok([joinRow])],
        [/^SELECT 1 FROM apartment_access_suspensions/, ok([{ x: 1 }])],
      ],
    });
    await assert.rejects(() => approveJoinRequest({ requestId: 9, authUser: superActor }), (error) => error.statusCode === 409);
    assert.equal(auditsOf(clientLog).length, 0);
    assert.ok(has(clientLog, /^ROLLBACK$/));
  });

  it('rejectJoinRequest: join_request.rejected retle AYNI işlemde; ret gerekçesi (serbest metin) yazılmaz, yalnız "gerekçe var" bilgisi', async () => {
    const { poolLog, clientLog } = install({ clientRules: [[/^SELECT \* FROM join_requests WHERE id = \$1 FOR UPDATE$/, ok([{ id: 9, site_code: 101, apartment_id: 3, user_code: 77, status: 'PENDING' }])]] });
    await rejectJoinRequest({ requestId: 9, authUser: superActor, reason: 'Komşu şikayeti: Ali Veli ile ilgili özel gerekçe' });
    const audits = auditsOf(clientLog);
    assert.equal(audits.length, 1);
    assert.equal(auditsOf(poolLog).length, 0);
    const [audit] = audits;
    assert.deepEqual(
      { action: audit.action, siteCode: audit.siteCode, targetType: audit.targetType, targetId: audit.targetId, details: audit.details },
      { action: 'join_request.rejected', siteCode: 101, targetType: 'join_request', targetId: '9', details: { user_code: 77, apartment_id: 3, has_reason: true } },
    );
    assertNoPersonalData(audit, ['Komşu', 'Ali Veli', 'gerekçe']);
    assert.ok(indexOf(clientLog, /^UPDATE join_requests SET status = 'REJECTED'/) < audit.index && audit.index < indexOf(clientLog, /^COMMIT$/));

    const noReason = install({ clientRules: [[/^SELECT \* FROM join_requests WHERE id = \$1 FOR UPDATE$/, ok([{ id: 9, site_code: 101, apartment_id: 3, user_code: 77, status: 'PENDING' }])]] });
    await rejectJoinRequest({ requestId: 9, authUser: superActor });
    assert.equal(auditsOf(noReason.clientLog)[0].details.has_reason, false);
  });

  it('rejectJoinRequest: talep zaten sonuçlanmışsa (409) kayıt yazılmaz', async () => {
    const { clientLog } = install({ clientRules: [[/^SELECT \* FROM join_requests WHERE id = \$1 FOR UPDATE$/, ok([{ id: 9, site_code: 101, apartment_id: 3, user_code: 77, status: 'APPROVED' }])]] });
    await assert.rejects(() => rejectJoinRequest({ requestId: 9, authUser: superActor }), (error) => error.statusCode === 409);
    assert.equal(auditsOf(clientLog).length, 0);
  });

  const DOOR = [/FROM site_doors d JOIN sites s/, ok([{ id: 12, site_code: 101, door_name: 'Ana Kapı', assigned_device_id: null, site_name: 'Gül Sitesi' }])];
  const overrideRow = (allowed) => ok([{ id: 5, site_code: 101, door_id: 12, user_code: 77, is_allowed: allowed, notes: 'Misafir: Ali Veli', updated_at: new Date('2026-10-26T10:00:00Z') }]);

  it('setDoorAccessOverride: ek izin verme -> door_permission.granted; reddetme -> door_permission.denied; aynı işlemde, not (serbest metin) yazılmaz', async () => {
    let env = install({ poolRules: [DOOR], clientRules: [[/^WITH target AS/, overrideRow(true)]] });
    const granted = await setDoorAccessOverride({ doorId: 12, userCode: 77, isAllowed: true, notes: 'Misafir: Ali Veli', authUser: superActor });
    assert.equal(granted.action, 'GRANTED');
    let audits = auditsOf(env.clientLog);
    assert.equal(audits.length, 1);
    assert.equal(auditsOf(env.poolLog).length, 0, 'havuzdan değil işlem bağlantısından');
    assert.equal(has(env.poolLog, /^WITH target AS|^INSERT INTO door_access_overrides|^DELETE FROM door_access_overrides/), false, 'izin yazımı artık işlem bağlantısında');
    assert.deepEqual(
      { action: audits[0].action, siteCode: audits[0].siteCode, targetType: audits[0].targetType, targetId: audits[0].targetId, actorUserCode: audits[0].actorUserCode, details: audits[0].details },
      { action: 'door_permission.granted', siteCode: 101, targetType: 'user', targetId: '77', actorUserCode: 1, details: { door_id: 12, is_allowed: true } },
    );
    assertNoPersonalData(audits[0], ['Misafir', 'Ali Veli', 'Gül Sitesi', 'Ana Kapı']);
    assert.ok(indexOf(env.clientLog, /^WITH target AS/) < audits[0].index && audits[0].index < indexOf(env.clientLog, /^COMMIT$/));

    env = install({ poolRules: [DOOR], clientRules: [[/^WITH target AS/, overrideRow(false)]] });
    const denied = await setDoorAccessOverride({ doorId: 12, userCode: 77, isAllowed: false, authUser: superActor });
    assert.equal(denied.action, 'DENIED');
    audits = auditsOf(env.clientLog);
    assert.deepEqual(audits.map((a) => [a.action, a.details]), [['door_permission.denied', { door_id: 12, is_allowed: false }]]);
  });

  it('setDoorAccessOverride: hedef kullanıcı yok/silinmiş (CTE satır döndürmez) -> 404, denetim kaydı yok, ROLLBACK', async () => {
    const { clientLog } = install({ poolRules: [DOOR], clientRules: [[/^WITH target AS/, ok()]] });
    await assert.rejects(() => setDoorAccessOverride({ doorId: 12, userCode: 77, isAllowed: true, authUser: superActor }), (error) => error.statusCode === 404);
    assert.equal(auditsOf(clientLog).length, 0);
    assert.ok(has(clientLog, /^ROLLBACK$/));
    assert.equal(has(clientLog, /^COMMIT$/), false);
  });

  it('setDoorAccessOverride: özel izni kaldırma (isAllowed null) -> door_permission.removed yalnız satır silindiyse', async () => {
    let env = install({ poolRules: [DOOR], clientRules: [[/^DELETE FROM door_access_overrides/, ok([], 1)]] });
    const reset = await setDoorAccessOverride({ doorId: 12, userCode: 77, isAllowed: null, authUser: superActor });
    assert.equal(reset.action, 'RESET');
    const audits = auditsOf(env.clientLog);
    assert.deepEqual(
      audits.map((a) => [a.action, a.siteCode, a.targetType, a.targetId, a.details]),
      [['door_permission.removed', 101, 'user', '77', { door_id: 12 }]],
    );
    assert.ok(indexOf(env.clientLog, /^DELETE FROM door_access_overrides/) < audits[0].index && audits[0].index < indexOf(env.clientLog, /^COMMIT$/));

    env = install({ poolRules: [DOOR], clientRules: [[/^DELETE FROM door_access_overrides/, ok([], 0)]] });
    const nothing = await setDoorAccessOverride({ doorId: 12, userCode: 77, isAllowed: undefined, authUser: superActor });
    assert.equal(nothing.action, 'RESET');
    assert.equal(auditsOf(env.clientLog).length, 0, 'silinecek özel izin yoktu -> değişiklik yok, kayıt yok');
  });

  it('setDoorAccessOverride: geçersiz isAllowed 400 (işlem açılmadan)', async () => {
    const env = install({ poolRules: [DOOR] });
    await assert.rejects(() => setDoorAccessOverride({ doorId: 12, userCode: 77, isAllowed: 'belki', authUser: superActor }), (error) => error.statusCode === 400);
    assert.equal(env.clientLog.length, 0);
  });

  it('setBulkDoorAccessOverride: tek özet satır (granted / denied / removed) toplu yazımla AYNI işlemde; kapsam, sayı ve kullanıcı kodları; not yazılmaz', async () => {
    let env = install({ poolRules: [DOOR, [/^SELECT user_code FROM users WHERE user_code = ANY/, ok([{ user_code: 77 }, { user_code: 78 }])]] });
    const result = await setBulkDoorAccessOverride({ doorId: 12, userCodes: [77, 78], isAllowed: true, notes: 'Toplantı: Ali Veli', authUser: superActor });
    assert.equal(result.count, 2);
    let audits = auditsOf(env.clientLog);
    assert.equal(audits.length, 1, 'kullanıcı başına değil tek özet satır');
    assert.equal(auditsOf(env.poolLog).length, 0);
    assert.deepEqual(
      { action: audits[0].action, siteCode: audits[0].siteCode, targetType: audits[0].targetType, targetId: audits[0].targetId, details: audits[0].details },
      { action: 'door_permission.bulk_granted', siteCode: 101, targetType: 'door', targetId: '12', details: { door_id: 12, scope: 'users', count: 2, user_codes: [77, 78], user_codes_truncated: false } },
    );
    assertNoPersonalData(audits[0], ['Toplantı', 'Ali Veli', 'Gül Sitesi']);
    assert.ok(indexOf(env.clientLog, /^INSERT INTO door_access_overrides/) < audits[0].index && audits[0].index < indexOf(env.clientLog, /^COMMIT$/));

    env = install({ poolRules: [DOOR, [/^SELECT user_code FROM users WHERE user_code = ANY/, ok([{ user_code: 77 }])]] });
    await setBulkDoorAccessOverride({ doorId: 12, userCodes: [77], isAllowed: false, authUser: superActor });
    assert.deepEqual(auditsOf(env.clientLog).map((a) => a.action), ['door_permission.bulk_denied']);

    env = install({ poolRules: [DOOR, [/^SELECT user_code FROM users WHERE user_code = ANY/, ok([{ user_code: 77 }])]] });
    await setBulkDoorAccessOverride({ doorId: 12, userCodes: [77], isAllowed: null, authUser: superActor });
    audits = auditsOf(env.clientLog);
    assert.deepEqual(audits.map((a) => a.action), ['door_permission.bulk_removed']);
    assert.ok(indexOf(env.clientLog, /^DELETE FROM door_access_overrides/) < audits[0].index);
  });

  it('setBulkDoorAccessOverride: blok kapsamı (block_id) ve 200\'den fazla kişide kod listesi kırpılır (sayı tam, user_codes_truncated)', async () => {
    const many = Array.from({ length: 250 }, (_, index) => ({ user_code: 1000 + index }));
    // Kural deseni: regex benzeri nesne (yalnız test() gerekir); blok sakinleri sorgusu birebir eşleşir.
    const blockUsersSql = { test: (sql) => sql === norm(SQL_BULK_BLOCK_USERS) };
    const env = install({ poolRules: [DOOR, [blockUsersSql, ok(many)]] });
    const result = await setBulkDoorAccessOverride({ doorId: 12, blockId: 5, isAllowed: true, authUser: superActor });
    assert.equal(result.count, 250);
    const [audit] = auditsOf(env.clientLog);
    assert.equal(audit.details.scope, 'block');
    assert.equal(audit.details.block_id, 5);
    assert.equal(audit.details.count, 250);
    assert.equal(audit.details.user_codes.length, 200);
    assert.equal(audit.details.user_codes_truncated, true);
    assert.equal('apartment_id' in audit.details, false);
  });

  it('setBulkDoorAccessOverride: kapsamda kimse yoksa (count 0) yazım da kayıt da yok', async () => {
    const env = install({ poolRules: [DOOR, [/^SELECT user_code FROM users WHERE user_code = ANY/, ok()]] });
    const result = await setBulkDoorAccessOverride({ doorId: 12, userCodes: [77], isAllowed: true, authUser: superActor });
    assert.equal(result.count, 0);
    assert.equal(env.clientLog.length, 0);
  });
});

// ---------------------------------------------------------------------------------------------------------------------------------
// 4) Cihaz sahipliği
// ---------------------------------------------------------------------------------------------------------------------------------
describe('cihaz sahipliği denetim kaydı (device_service)', () => {
  it('releaseDeviceOwnership: device.ownership_released sıfırlamayla AYNI işlemde; cihaz UID / e-posta yazılmaz', async () => {
    const { poolLog, clientLog } = install({
      clientRules: [
        [/^SELECT id, device_uid, site_code, owner_user_id FROM devices/, ok([{ id: 3, device_uid: 'D4C771A172E0', site_code: 1000000001, owner_user_id: 8 }])],
        [/^UPDATE devices SET owner_user_id = NULL/, ok([{ id: 3, device_uid: 'D4C771A172E0', hardware_type: 'esp32_wroom' }])],
      ],
    });
    await releaseDeviceOwnership({ deviceId: 3, authUser: { id: 1, user_code: 1, role: 'super_user', email: 'admin@example.test', full_name: 'Süper' } });
    const audits = auditsOf(clientLog);
    assert.equal(audits.length, 1);
    assert.equal(auditsOf(poolLog).length, 0);
    const [audit] = audits;
    assert.deepEqual(
      { action: audit.action, siteCode: audit.siteCode, targetType: audit.targetType, targetId: audit.targetId, actorUserCode: audit.actorUserCode, details: audit.details },
      { action: 'device.ownership_released', siteCode: 1000000001, targetType: 'device', targetId: '3', actorUserCode: 1, details: { previous_owner_id: 8 } },
    );
    assertNoPersonalData(audit, ['D4C771A172E0', 'admin@example.test']);
    assert.ok(indexOf(clientLog, /^UPDATE devices SET owner_user_id = NULL/) < audit.index && audit.index < indexOf(clientLog, /^COMMIT$/));
  });

  it('releaseDeviceOwnership: cihaz yoksa (404) denetim kaydı yok', async () => {
    const { clientLog } = install({ clientRules: [[/^SELECT id, device_uid, site_code, owner_user_id FROM devices/, ok()]] });
    await assert.rejects(() => releaseDeviceOwnership({ deviceId: 3, authUser: { id: 1 } }), (error) => error.statusCode === 404);
    assert.equal(auditsOf(clientLog).length, 0);
  });
});
