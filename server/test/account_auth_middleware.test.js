// authRequired x silinmiş hesap (DB'siz): kimliksizleştirilmiş hesabın ESKİ tokenları (pv'li ve pv'siz) 401 ACCOUNT_DELETED ile reddedilir;
// deleted_at isteğe taşınmaz; sağlam hesaplar etkilenmez.
import { describe, it, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert/strict';
import { pool } from '../src/db.js';
import { signAccessToken } from '../src/jwt.js';
import { authRequired } from '../src/middlewares/auth_middleware.js';

const SECRET = 'k9Fz-test-only-long-secret-value-0123456789abcdef';
const OLD_HASH = '$2a$10$AAAAAAAAAAAAAAAAAAAAAA';
const TOMBSTONE_HASH = '!deadbeef';

function makeRes() {
  return {
    statusCode: 200,
    body: undefined,
    status(code) {
      this.statusCode = code;
      return this;
    },
    json(payload) {
      this.body = payload;
      return this;
    },
  };
}

function userRow(overrides = {}) {
  return {
    db_id: 7,
    id: 42,
    user_code: 42,
    full_name: 'Test Kullanici',
    email: 'a@example.com',
    login_name: null,
    role: 'individual',
    is_active: true,
    email_verified: true,
    approval_status: 'approved',
    phone_number: null,
    created_at: new Date(),
    deleted_at: null,
    password_hash: OLD_HASH,
    ...overrides,
  };
}

async function run(token, row) {
  const originalQuery = pool.query;
  const queries = [];
  pool.query = async (text) => {
    queries.push(String(text));
    return { rows: row ? [{ ...row }] : [], rowCount: row ? 1 : 0 };
  };
  try {
    const req = { headers: { authorization: `Bearer ${token}` } };
    const res = makeRes();
    let nextArg = 'not-called';
    await authRequired(req, res, (arg) => {
      nextArg = arg;
    });
    return { req, res, nextArg, queries };
  } finally {
    pool.query = originalQuery;
  }
}

describe('authRequired: silinmiş (kimliksizleştirilmiş) hesap', () => {
  let savedSecret;
  beforeEach(() => {
    savedSecret = process.env.JWT_SECRET;
    process.env.JWT_SECRET = SECRET;
  });
  afterEach(() => {
    if (savedSecret === undefined) delete process.env.JWT_SECRET;
    else process.env.JWT_SECRET = savedSecret;
  });

  it('sorgu deleted_at sütununu okur (her istekte taze)', async () => {
    const token = signAccessToken({ id: 42 }, { passwordHash: OLD_HASH });
    const { queries } = await run(token, userRow());
    assert.ok(queries.some((sql) => /\bdeleted_at\b/.test(sql)));
  });

  it('pv\'siz ESKİ token + silinmiş hesap: 401 ACCOUNT_DELETED (403 "Hesap aktif değil" değil: istemci oturumu kapatır)', async () => {
    const token = signAccessToken({ id: 42 }); // parola özeti verilmedi -> pv claim'i yok
    const { res, nextArg } = await run(token, userRow({ is_active: false, deleted_at: new Date(), password_hash: TOMBSTONE_HASH }));
    assert.equal(res.statusCode, 401);
    assert.equal(res.body.code, 'ACCOUNT_DELETED');
    assert.equal(nextArg, 'not-called');
  });

  it('pv\'li ESKİ token + silinmiş hesap: parola özeti değiştiği için de reddedilir (401; TOKEN_REVOKED ya da ACCOUNT_DELETED), next çağrılmaz', async () => {
    const token = signAccessToken({ id: 42 }, { passwordHash: OLD_HASH });
    const { res, nextArg } = await run(token, userRow({ is_active: false, deleted_at: new Date(), password_hash: TOMBSTONE_HASH }));
    assert.equal(res.statusCode, 401);
    assert.ok(['ACCOUNT_DELETED', 'TOKEN_REVOKED'].includes(res.body.code), res.body.code);
    assert.equal(nextArg, 'not-called');
  });

  it('silinmiş hesap deleted_at\'i aktif işaretlense bile (yönetici hatası) reddedilir', async () => {
    const token = signAccessToken({ id: 42 }, { passwordHash: TOMBSTONE_HASH });
    const { res, nextArg } = await run(token, userRow({ is_active: true, deleted_at: new Date(), password_hash: TOMBSTONE_HASH }));
    assert.equal(res.statusCode, 401);
    assert.equal(res.body.code, 'ACCOUNT_DELETED');
    assert.equal(nextArg, 'not-called');
  });

  it('sağlam hesap geçer ve req.authUser içine deleted_at / parola özeti TAŞINMAZ', async () => {
    const token = signAccessToken({ id: 42 }, { passwordHash: OLD_HASH });
    const { req, nextArg } = await run(token, userRow());
    assert.equal(nextArg, undefined);
    assert.equal('deleted_at' in req.authUser, false);
    assert.equal('password_hash' in req.authUser, false);
    assert.equal(req.authUser.user_code, 42);
  });

  it('hâlâ pasif ama silinmemiş hesap: eskisi gibi 403 "Hesap aktif değil"', async () => {
    const token = signAccessToken({ id: 42 }, { passwordHash: OLD_HASH });
    const { res } = await run(token, userRow({ is_active: false }));
    assert.equal(res.statusCode, 403);
    assert.equal(res.body.code, undefined);
  });
});
