// Mevcut parola doğrulaması: PATCH /me ve daire sakini change-password PAYLAŞILAN rezervasyonlu doğrulayıcıya (verifyCurrentPassword) geçti
// (R1 B1). N paralel yanlış parola EN ÇOK 5 bcrypt karşılaştırması çalıştırır; sayaç `u:<user_code>` iki uçta (ve hesap silme / dışa aktarma)
// ortaktır; PATCH /me kullanıcı başına hız sınırlayıcıya sahiptir. DB'siz (sahte havuz).
import { describe, it, before, after, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert/strict';
import bcrypt from 'bcryptjs';
import express from 'express';
import '../src/utils/async_errors.js';
import { pool } from '../src/db.js';
import { signAccessToken } from '../src/jwt.js';
import { passwordChangeFailureTracker } from '../src/middlewares/login_throttle.js';
import { profileUpdateLimiter } from '../src/middlewares/rate_limiters.js';
import { authRouter } from '../src/routes/auth_routes.js';
import { changeApartmentMemberPassword } from '../src/services/membership_service.js';
import { authRequired } from '../src/middlewares/auth_middleware.js';

const SECRET = 'k9Fz-test-only-long-secret-value-0123456789abcdef';
const PASSWORD = 'Dogru-Parola-1';
const PASSWORD_HASH = bcrypt.hashSync(PASSWORD, 4);
const NEW_PASSWORD = 'Yeni-Parola-2xQ';
const user = {
  id: 42,
  db_id: 7,
  user_code: 42,
  full_name: 'Test Kullanici',
  email: 'ali@example.com',
  login_name: null,
  role: 'individual',
  is_active: true,
  email_verified: true,
  approval_status: 'approved',
  phone_number: null,
  created_at: new Date('2026-01-01T00:00:00Z'),
  deleted_at: null,
  password_hash: PASSWORD_HASH,
};

let hashLookups;
let updates;
let server;
let baseUrl;
let originalQuery;
let savedSecret;

function install() {
  hashLookups = 0;
  updates = 0;
  pool.query = async (text) => {
    const sql = String(text).replace(/\s+/g, ' ').trim();
    if (sql.includes('db_id')) return { rows: [{ ...user }], rowCount: 1 };
    if (sql.startsWith('SELECT password_hash FROM users')) {
      hashLookups += 1;
      return { rows: [{ password_hash: PASSWORD_HASH }], rowCount: 1 };
    }
    if (/^SELECT id, site_code, resident_user_code FROM apartments/.test(sql)) return { rows: [{ id: 5, site_code: 101, resident_user_code: null }], rowCount: 1 };
    if (/^SELECT 1 FROM apartment_memberships WHERE apartment_id/.test(sql)) return { rows: [{ x: 1 }], rowCount: 1 };
    if (/^UPDATE users/.test(sql)) {
      updates += 1;
      return { rows: [{ id: 42, user_code: 42, email: user.email, role: 'individual', full_name: 'Test Kullanici', is_active: true }], rowCount: 1 };
    }
    return { rows: [], rowCount: 0 };
  };
}

before(async () => {
  savedSecret = process.env.JWT_SECRET;
  process.env.JWT_SECRET = SECRET;
  originalQuery = pool.query;
  const app = express();
  app.use(express.json());
  app.use(authRouter);
  await new Promise((resolve) => {
    server = app.listen(0, '127.0.0.1', resolve);
  });
  baseUrl = `http://127.0.0.1:${server.address().port}`;
});

after(async () => {
  pool.query = originalQuery;
  if (savedSecret === undefined) delete process.env.JWT_SECRET;
  else process.env.JWT_SECRET = savedSecret;
  server.closeAllConnections?.();
  await new Promise((resolve) => server.close(resolve));
});

beforeEach(() => {
  install();
  passwordChangeFailureTracker.reset();
  profileUpdateLimiter.reset();
});

afterEach(() => {
  pool.query = originalQuery;
});

const patchMe = (body) =>
  fetch(`${baseUrl}/me`, {
    method: 'PATCH',
    headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${signAccessToken({ id: 42 }, { passwordHash: PASSWORD_HASH })}` },
    body: JSON.stringify(body),
  });

const changePassword = (current) =>
  changeApartmentMemberPassword({ apartmentId: 5, targetUserCode: 42, newPassword: 'YeniParola1xQ', currentPassword: current, authUser: { id: 42, user_code: 42, userCode: 42 } });

describe('mevcut parola: paralel tahmin penceresi kapalı (rezervasyonlu doğrulayıcı)', () => {
  it('PATCH /me: 30 PARALEL yanlış parola EN ÇOK 5 hash okuması / karşılaştırma yapar; 400 ≤ 4, kalanı 429; UPDATE hiç çalışmaz', async () => {
    const responses = await Promise.all(Array.from({ length: 30 }, (_, i) => patchMe({ password: NEW_PASSWORD, current_password: `yanlis-${i}` })));
    const statuses = responses.map((r) => r.status);
    assert.ok(hashLookups <= 5, `hash okuması ${hashLookups}`);
    assert.ok(statuses.filter((s) => s === 400).length <= 4, JSON.stringify(statuses));
    assert.equal(statuses.filter((s) => s === 400 || s === 429).length, 30, JSON.stringify(statuses));
    assert.ok(statuses.filter((s) => s === 429).length >= 26);
    assert.equal(updates, 0);
    const locked = responses.find((r) => r.status === 429);
    const body = await locked.json();
    assert.equal(body.code, 'CURRENT_PASSWORD_LOCKED');
    assert.ok(body.retry_after_seconds >= 1);
    assert.ok(Number(locked.headers.get('retry-after')) >= 1);
    // kilitliyken DOĞRU parola da reddedilir
    assert.equal((await patchMe({ password: NEW_PASSWORD, current_password: PASSWORD })).status, 429);
    assert.equal(updates, 0);
  });

  it('daire sakini change-password: 30 PARALEL yanlış parola EN ÇOK 5 hash okuması; hepsi 400 INVALID / 429 LOCKED', async () => {
    const results = await Promise.allSettled(Array.from({ length: 30 }, (_, i) => changePassword(`yanlis-${i}`)));
    assert.ok(hashLookups <= 5, `hash okuması ${hashLookups}`);
    const codes = results.map((r) => (r.status === 'rejected' ? r.reason.code : 'ok'));
    assert.ok(codes.every((code) => code === 'CURRENT_PASSWORD_INVALID' || code === 'CURRENT_PASSWORD_LOCKED'), JSON.stringify(codes));
    assert.ok(codes.filter((c) => c === 'CURRENT_PASSWORD_INVALID').length <= 4);
    const lockedError = results.find((r) => r.status === 'rejected' && r.reason.code === 'CURRENT_PASSWORD_LOCKED')?.reason;
    assert.equal(lockedError.statusCode, 429);
    assert.ok(lockedError.retryAfterSeconds >= 1);
    assert.equal(updates, 0);
  });

  it('SAYAÇ ORTAK: PATCH /me + change-password + doğrulayıcının kendisi birlikte EN ÇOK 5 karşılaştırma (u:<user_code>)', async () => {
    const jobs = [];
    for (let i = 0; i < 8; i += 1) {
      jobs.push(patchMe({ password: NEW_PASSWORD, current_password: `a-${i}` }).then((r) => r.status));
      jobs.push(changePassword(`b-${i}`).then(() => 'ok', (error) => error.statusCode));
    }
    const outcomes = await Promise.all(jobs);
    assert.ok(hashLookups <= 5, `hash okuması ${hashLookups}`);
    assert.equal(outcomes.includes('ok'), false);
    assert.equal(outcomes.includes(200), false);
    assert.equal(passwordChangeFailureTracker.check('u:42').locked, true);
  });

  it('doğru parola yanlış kilitlemez: PATCH /me ardışık 2 doğru parola 200 (sayaç temiz)', async () => {
    assert.equal((await patchMe({ password: NEW_PASSWORD, current_password: PASSWORD })).status, 200);
    assert.equal((await patchMe({ password: NEW_PASSWORD, current_password: PASSWORD })).status, 200);
    assert.equal(passwordChangeFailureTracker.size(), 0);
  });
});

describe('PATCH /me: kullanıcı başına hız sınırlayıcı', () => {
  it('rota zincirinde authRequired\'dan SONRA profileUpdateLimiter var', () => {
    const layer = authRouter.stack.find((entry) => entry.route && entry.route.path === '/me' && entry.route.methods.patch);
    assert.ok(layer);
    const handlers = layer.route.stack.map((entry) => entry.handle);
    assert.equal(handlers[0], authRequired);
    assert.equal(handlers[1], profileUpdateLimiter);
    assert.equal(handlers.length, 3);
  });

  it('15 dakikada kullanıcı başına 30 istek; 31. istek 429 + Retry-After + retry_after_seconds (başka kullanıcı etkilenmez)', () => {
    const run = (code, ip = '10.0.0.1') => {
      const headers = {};
      let status = null;
      let body = null;
      let passed = false;
      const req = { authUser: { user_code: code }, ip, socket: { remoteAddress: ip } };
      const res = {
        setHeader: (name, value) => {
          headers[name] = value;
        },
        status(value) {
          status = value;
          return this;
        },
        json(value) {
          body = value;
          return this;
        },
      };
      profileUpdateLimiter(req, res, () => {
        passed = true;
      });
      return { passed, status, body, headers };
    };
    for (let i = 0; i < 30; i += 1) assert.equal(run(42).passed, true, `istek ${i + 1}`);
    const blocked = run(42);
    assert.equal(blocked.status, 429);
    assert.ok(Number(blocked.headers['Retry-After']) >= 1);
    assert.ok(blocked.body.retry_after_seconds >= 1);
    assert.equal(run(43, '10.0.0.2').passed, true);
  });
});

describe('R2 F-2: silinmiş hesaba yazılmaz (updateUserByCode + PATCH /me)', () => {
  it('updateUserByCode: UPDATE ... WHERE user_code = $N AND deleted_at IS NULL; satır dönmezse null (parametre sırası doğru)', async () => {
    const { updateUserByCode } = await import('../src/services/user_service.js');
    const seen = [];
    const db = {
      query: async (text, params) => {
        seen.push({ sql: String(text).replace(/\s+/g, ' ').trim(), params });
        return { rows: [], rowCount: 0 };
      },
    };
    const result = await updateUserByCode({ userCode: 42, fullName: 'Yeni Ad', phoneNumber: '+905551112233', isActive: true, db });
    assert.equal(result, null);
    assert.equal(seen.length, 1);
    assert.match(seen[0].sql, /^UPDATE users SET full_name = \$1, phone_number = \$2, is_active = \$3 WHERE user_code = \$4 AND deleted_at IS NULL RETURNING /);
    assert.deepEqual(seen[0].params, ['Yeni Ad', '+905551112233', true, 42]);
  });

  it('PATCH /me: istek sırasında hesap silinmişse (UPDATE 0 satır, deleted_at dolu) 401 ACCOUNT_DELETED; yoksa 404; tombstone\'a yazılmaz', async () => {
    let lookups = 0;
    let deletedState = true;
    pool.query = async (text) => {
      const sql = String(text).replace(/\s+/g, ' ').trim();
      if (sql.includes('db_id')) return { rows: [{ ...user }], rowCount: 1 };
      if (/^UPDATE users/.test(sql)) {
        assert.match(sql, /AND deleted_at IS NULL/);
        return { rows: [], rowCount: 0 };
      }
      if (/^SELECT deleted_at FROM users WHERE user_code = \$1$/.test(sql)) {
        lookups += 1;
        return deletedState ? { rows: [{ deleted_at: new Date() }], rowCount: 1 } : { rows: [], rowCount: 0 };
      }
      return { rows: [], rowCount: 0 };
    };
    let response = await patchMe({ full_name: 'Yeni Ad Soyad' });
    assert.equal(response.status, 401);
    assert.deepEqual(await response.json(), { error: 'Bu hesap silinmis.', code: 'ACCOUNT_DELETED' });
    deletedState = false;
    response = await patchMe({ full_name: 'Yeni Ad Soyad' });
    assert.equal(response.status, 404);
    assert.equal(lookups, 2);
  });
});

describe('R7: daire sakini change-password silinmiş hesaba parola özeti YAZMAZ', () => {
  const run = async ({ deletedAfterVerify }) => {
    const seen = [];
    pool.query = async (text, params) => {
      const sql = String(text).replace(/\s+/g, ' ').trim();
      seen.push({ sql, params });
      if (sql.startsWith('SELECT password_hash FROM users')) return { rows: [{ password_hash: PASSWORD_HASH }], rowCount: 1 };
      if (/^SELECT id, site_code, resident_user_code FROM apartments/.test(sql)) return { rows: [{ id: 5, site_code: 101, resident_user_code: 42 }], rowCount: 1 };
      if (/^SELECT 1 FROM apartment_memberships WHERE apartment_id/.test(sql)) return { rows: [{ x: 1 }], rowCount: 1 };
      if (/^UPDATE users SET password_hash/.test(sql)) return { rows: [], rowCount: 0 }; // doğrulamadan SONRA silme commit etti: deleted_at IS NULL satırı dışlar
      if (/^SELECT deleted_at FROM users WHERE user_code = \$1$/.test(sql)) {
        return deletedAfterVerify ? { rows: [{ deleted_at: new Date() }], rowCount: 1 } : { rows: [], rowCount: 0 };
      }
      return { rows: [], rowCount: 0 };
    };
    const outcome = await changePassword(PASSWORD).then((value) => ({ ok: true, value }), (error) => ({ ok: false, error }));
    return { outcome, seen };
  };

  it('UPDATE `WHERE user_code = $2 AND deleted_at IS NULL`; satır dönmezse ve hesap silinmişse 401 ACCOUNT_DELETED, token YOK, eski PIN temizliği (apartments UPDATE) çalışmaz', async () => {
    const { outcome, seen } = await run({ deletedAfterVerify: true });
    const update = seen.find((entry) => /^UPDATE users SET password_hash/.test(entry.sql));
    assert.ok(update);
    assert.match(update.sql, /^UPDATE users SET password_hash = \$1, updated_at = NOW\(\) WHERE user_code = \$2 AND deleted_at IS NULL RETURNING /);
    assert.equal(update.params[1], 42);
    assert.equal(outcome.ok, false);
    assert.equal(outcome.error.statusCode, 401);
    assert.equal(outcome.error.code, 'ACCOUNT_DELETED');
    assert.equal(seen.some((entry) => /^UPDATE apartments/.test(entry.sql)), false);
  });

  it('satır dönmez ama hesap silinmiş değilse (kayıp satır) 404; başarılı yolda token ve yanıt değişmez', async () => {
    const { outcome } = await run({ deletedAfterVerify: false });
    assert.equal(outcome.ok, false);
    assert.equal(outcome.error.statusCode, 404);
    assert.equal(outcome.error.code, undefined);

    install();
    const ok = await changePassword(PASSWORD);
    assert.equal(ok.ok, true);
    assert.equal(typeof ok.token, 'string');
  });

  it('doğrulayıcı ACCOUNT_DELETED derse (doğrulamadan ÖNCE silinmiş) aynı 401 ACCOUNT_DELETED', async () => {
    pool.query = async (text) => {
      const sql = String(text).replace(/\s+/g, ' ').trim();
      if (sql.startsWith('SELECT password_hash FROM users')) return { rows: [], rowCount: 0 };
      if (/^SELECT id, site_code, resident_user_code FROM apartments/.test(sql)) return { rows: [{ id: 5, site_code: 101, resident_user_code: 42 }], rowCount: 1 };
      if (/^SELECT 1 FROM apartment_memberships WHERE apartment_id/.test(sql)) return { rows: [{ x: 1 }], rowCount: 1 };
      return { rows: [], rowCount: 0 };
    };
    await assert.rejects(changePassword(PASSWORD), (error) => error.statusCode === 401 && error.code === 'ACCOUNT_DELETED');
  });
});
