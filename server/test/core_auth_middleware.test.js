import { describe, it, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert/strict';
import jwt from 'jsonwebtoken';
import { pool } from '../src/db.js';
import { signAccessToken } from '../src/jwt.js';
import { authRequired } from '../src/middlewares/auth_middleware.js';

const SECRET = 'k9Fz-test-only-long-secret-value-0123456789abcdef';
const HASH = '$2a$10$AAAAAAAAAAAAAAAAAAAAAA';
const OTHER_HASH = '$2a$10$BBBBBBBBBBBBBBBBBBBBBB';

function makeRes() {
  const res = {
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
  return res;
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
    password_hash: HASH,
    ...overrides,
  };
}

async function run(header, rowOrError) {
  const originalQuery = pool.query;
  pool.query = async () => {
    if (rowOrError instanceof Error) throw rowOrError;
    return { rows: rowOrError ? [rowOrError] : [], rowCount: rowOrError ? 1 : 0 };
  };
  try {
    const req = { headers: header ? { authorization: header } : {} };
    const res = makeRes();
    let nextArg = 'not-called';
    await authRequired(req, res, (arg) => {
      nextArg = arg;
    });
    return { req, res, nextArg };
  } finally {
    pool.query = originalQuery;
  }
}

describe('authRequired (C12)', () => {
  let savedSecret;
  beforeEach(() => {
    savedSecret = process.env.JWT_SECRET;
    process.env.JWT_SECRET = SECRET;
  });
  afterEach(() => {
    if (savedSecret === undefined) delete process.env.JWT_SECRET;
    else process.env.JWT_SECRET = savedSecret;
  });

  it('Bearer yoksa 401', async () => {
    const { res, nextArg } = await run(undefined, userRow());
    assert.equal(res.statusCode, 401);
    assert.equal(nextArg, 'not-called');
  });

  it('gecerli pv claim li token kabul edilir; password_hash istek nesnesine tasinmaz', async () => {
    const token = signAccessToken({ id: 42, email: 'a@example.com', role: 'individual' }, { passwordHash: HASH });
    const { req, nextArg } = await run(`Bearer ${token}`, userRow());
    assert.equal(nextArg, undefined, 'next() hatasiz cagrilmali');
    assert.equal(req.authUser.userCode, 42);
    assert.equal('password_hash' in req.authUser, false);
  });

  it('parola degisince (pv uyusmaz) eski token 401 TOKEN_REVOKED', async () => {
    const token = signAccessToken({ id: 42, email: 'a@example.com', role: 'individual' }, { passwordHash: HASH });
    const { res, nextArg } = await run(`Bearer ${token}`, userRow({ password_hash: OTHER_HASH }));
    assert.equal(res.statusCode, 401);
    assert.equal(res.body.code, 'TOKEN_REVOKED');
    assert.equal(nextArg, 'not-called');
  });

  it('pv claim i olmayan eski token suresi dolana kadar gecerli kalir', async () => {
    const legacy = jwt.sign({ sub: '42', email: 'a@example.com', role: 'individual' }, SECRET, { expiresIn: '1h' });
    const { req, nextArg } = await run(`Bearer ${legacy}`, userRow({ password_hash: OTHER_HASH }));
    assert.equal(nextArg, undefined);
    assert.equal(req.authUser.userCode, 42);
  });

  it('rol token tan DEGIL DB den taze okunur', async () => {
    const token = jwt.sign({ sub: '42', role: 'super_user' }, SECRET, { expiresIn: '1h' });
    const { req } = await run(`Bearer ${token}`, userRow({ role: 'individual' }));
    assert.equal(req.authUser.role, 'individual');
  });

  it('hesap pasifse 403, e-posta dogrulanmadiysa 403', async () => {
    const token = signAccessToken({ id: 42, email: 'a@example.com', role: 'individual' }, { passwordHash: HASH });
    const inactive = await run(`Bearer ${token}`, userRow({ is_active: false }));
    assert.equal(inactive.res.statusCode, 403);
    const unverified = await run(`Bearer ${token}`, userRow({ email_verified: false }));
    assert.equal(unverified.res.statusCode, 403);
  });

  it('kullanici yoksa 401', async () => {
    const token = signAccessToken({ id: 42, email: 'a@example.com', role: 'individual' });
    const { res } = await run(`Bearer ${token}`, null);
    assert.equal(res.statusCode, 401);
  });

  it('gecersiz imza 401, DB hatasi ise 401 DEGIL next(err) (istemciyi yanlislikla cikisa zorlamaz)', async () => {
    const forged = jwt.sign({ sub: '42' }, 'baska-bir-secret-degeri-0123456789abcdef', { expiresIn: '1h' });
    const bad = await run(`Bearer ${forged}`, userRow());
    assert.equal(bad.res.statusCode, 401);

    const token = signAccessToken({ id: 42, email: 'a@example.com', role: 'individual' }, { passwordHash: HASH });
    const dbDown = await run(`Bearer ${token}`, new Error('connection refused'));
    assert.ok(dbDown.nextArg instanceof Error);
    assert.equal(dbDown.res.statusCode, 200, 'yanit gonderilmemeli (hata middleware e birakilir)');
  });

  it('sub gecersizse 401', async () => {
    const token = jwt.sign({ sub: 'abc' }, SECRET, { expiresIn: '1h' });
    const { res } = await run(`Bearer ${token}`, userRow());
    assert.equal(res.statusCode, 401);
    const huge = jwt.sign({ sub: '9'.repeat(30) }, SECRET, { expiresIn: '1h' });
    const second = await run(`Bearer ${huge}`, userRow());
    assert.equal(second.res.statusCode, 401);
  });
});
