// Guvenlik denetimi auth-4 (bcrypt DoS): senkron bcrypt (hashSync / compareSync) olay dongusunu 70-120 ms kilitler; giris, parola korumasi ve sahte ozet
// ASENKRON olmali. Kapsam: server/src altinda senkron bcrypt YOK (kaynak taramasi), sahte ozet asenkron + onbellekli + gecerli, giris ve mevcut-parola
// dogrulamasi asenkron yolla calisir (DB'siz; sahte pool.query).
import { describe, it, before, after, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import bcrypt from 'bcryptjs';
import express from 'express';
import '../src/utils/async_errors.js';
import { pool } from '../src/db.js';
import { authRouter } from '../src/routes/auth_routes.js';
import { createErrorHandler } from '../src/middlewares/error_handler.js';
import { createFailureTracker, loginFailureTracker, loginGuard } from '../src/middlewares/login_throttle.js';
import { loginRateLimiter } from '../src/middlewares/rate_limiters.js';
import { passwordGuardDeps, verifyCurrentPassword } from '../src/modules/account_password_guard.js';
import { isBcryptHash } from '../src/security/login_guard.js';
import { BCRYPT_COST, bcryptCostOf, getDummyPasswordHash } from '../src/security/password_hashing.js';
import { resolveTrustProxy } from '../src/security/trust_proxy.js';

const here = path.dirname(fileURLToPath(import.meta.url));
const srcDir = path.resolve(here, '..', 'src');
const SECRET = 'bcrypt-async-test-only-secret-value-0123456789abcdef';
const PASSWORD = 'Mavi-Kapi-77-Ruzgar';

function listJsFiles(dir) {
  const files = [];
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) files.push(...listJsFiles(full));
    else if (entry.name.endsWith('.js')) files.push(full);
  }
  return files;
}

const stripComments = (code) => code.replace(/\/\*[\s\S]*?\*\//g, '').replace(/(^|[^:])\/\/.*$/gm, '$1');

describe('bcrypt: senkron cagri yok (olay dongusu kilitlenmez)', () => {
  it('server/src altinda hashSync / compareSync / genSaltSync cagrisi YOK (yorumlar haric)', () => {
    const files = listJsFiles(srcDir);
    assert.ok(files.length > 100, 'kaynak taramasi dosyalari buldu');
    const offenders = [];
    for (const file of files) {
      const raw = fs.readFileSync(file, 'utf8');
      // Hizli ele: adlar hic gecmeyen dosyada yorum ayiklamaya gerek yok.
      if (!/hashSync|compareSync|genSaltSync/.test(raw)) continue;
      if (/\b(hashSync|compareSync|genSaltSync)\s*\(/.test(stripComments(raw))) offenders.push(path.relative(srcDir, file));
    }
    assert.deepEqual(offenders, []);
  });

  it('getDummyPasswordHash ASENKRON: soz doner ve olay dongusune nefes aldirir (sync ozet sirasini bekletirdi)', async () => {
    // Onbellek BOS bir modul ornegi (sorgu parametresi ayri ornek yukler): ilk cagri gercekten hesaplar; ice aktarmada baslayan on isitma sonucu karismaz.
    const fresh = await import(`../src/security/password_hashing.js?taze=${Date.now()}`);
    assert.notEqual(fresh.getDummyPasswordHash, getDummyPasswordHash, 'ayri modul ornegi');
    let ticked = false;
    setImmediate(() => {
      ticked = true;
    });
    const pending = fresh.getDummyPasswordHash();
    assert.ok(pending instanceof Promise, 'eszamanli deger degil, soz');
    assert.equal(ticked, false, 'cagri donerken olay dongusu hic donmemisti (kilitlenmedi)');
    const hash = await pending;
    assert.equal(ticked, true, 'ozet hesaplanirken olay dongusu dondu');
    assert.ok(isBcryptHash(hash));
  });

  it('on isitma: ice aktarmada baslayan ozet hesaplanir, giris onu bekler (soz onbellekte)', async () => {
    const warmed = getDummyPasswordHash();
    assert.ok(warmed instanceof Promise);
    assert.ok(isBcryptHash(await warmed));
  });

  it('sahte ozet gecerli bcrypt ozeti, BCRYPT_COST maliyetinde, onbellekli (eszamanli cagrilar TEK ozeti bekler) ve hicbir tahminle eslesmez', async () => {
    const first = getDummyPasswordHash();
    assert.equal(getDummyPasswordHash(), first, 'ayni soz');
    const [a, b] = await Promise.all([first, getDummyPasswordHash()]);
    assert.equal(a, b);
    assert.ok(isBcryptHash(a), 'login_guard.isBcryptHash gecerli sayar');
    assert.equal(bcryptCostOf(a), BCRYPT_COST, 'var olan hesapla ayni maliyet: sure farki hesap varligini ele vermez');
    assert.equal(await bcrypt.compare('1234', a), false);
    assert.equal(await bcrypt.compare('', a), false);
  });
});

describe('mevcut parola dogrulamasi: sahte ozet yolu asenkron calisir', () => {
  it('saklı ozet yokken karsilastirma ASENKRON sahte ozetle yapilir; sonuc 400 CURRENT_PASSWORD_INVALID', async () => {
    const seen = [];
    const deps = {
      tracker: createFailureTracker(),
      loadUser: async () => ({ password_hash: '', deleted_at: null }),
      compare: async (plain, hash) => {
        seen.push(hash);
        return bcrypt.compare(plain, hash);
      },
    };
    await assert.rejects(
      () => verifyCurrentPassword({ userCode: 5, currentPassword: 'herhangi-bir-sey' }, deps),
      (error) => error.code === 'CURRENT_PASSWORD_INVALID' && error.statusCode === 400,
    );
    assert.equal(seen.length, 1, 'tek karsilastirma (sure sabit)');
    assert.equal(seen[0], await getDummyPasswordHash());
  });

  it('varsayilan bagimlilik gercek bcrypt.compare; dogru parola gecer, yanlis parola 400', async () => {
    const hash = await bcrypt.hash('Dogru-Parola-1', 4);
    const deps = {
      ...passwordGuardDeps,
      tracker: createFailureTracker(),
      loadUser: async () => ({ password_hash: hash, deleted_at: null }),
    };
    await verifyCurrentPassword({ userCode: 6, currentPassword: 'Dogru-Parola-1' }, deps);
    await assert.rejects(() => verifyCurrentPassword({ userCode: 6, currentPassword: 'Yanlis-Parola-1' }, deps), { code: 'CURRENT_PASSWORD_INVALID' });
  });
});

describe('POST /auth/login: asenkron bcrypt yolu', () => {
  let server;
  let baseUrl;
  let savedSecret;
  let originalCompare;
  let compareCalls;
  const hash = bcrypt.hashSync(PASSWORD, 4);
  const account = {
    id: 42,
    full_name: 'Ali Test',
    email: 'ali@example.com',
    login_name: 'ali.k',
    role: 'individual',
    is_active: true,
    email_verified: true,
    approval_status: 'approved',
    phone_number: null,
    created_at: new Date('2026-01-01T00:00:00Z'),
    password_hash: hash,
    must_change_password: false,
    pin_issued: false,
  };

  before(async () => {
    const app = express();
    app.set('env', 'test');
    app.set('trust proxy', resolveTrustProxy({}).value);
    app.use(express.json({ limit: '1mb' }));
    app.use(authRouter);
    app.use(createErrorHandler({ logger: { error: () => {}, log: () => {}, warn: () => {} } }));
    await new Promise((resolve) => {
      server = app.listen(0, '127.0.0.1', resolve);
    });
    baseUrl = `http://127.0.0.1:${server.address().port}`;
  });

  after(
    () =>
      new Promise((resolve) => {
        delete pool.query;
        server.closeAllConnections?.();
        server.close(resolve);
      }),
  );

  beforeEach(() => {
    savedSecret = process.env.JWT_SECRET;
    process.env.JWT_SECRET = SECRET;
    pool.query = async (text, params) => {
      const sql = String(text);
      if (sql.includes('LOWER(login_name)') && String(params[0]).toLowerCase() === 'ali@example.com') return { rows: [{ ...account }], rowCount: 1 };
      return { rows: [], rowCount: 0 };
    };
    compareCalls = [];
    originalCompare = bcrypt.compare;
    bcrypt.compare = (plain, stored, ...rest) => {
      compareCalls.push(stored);
      return originalCompare.call(bcrypt, plain, stored, ...rest);
    };
    loginRateLimiter.reset();
    loginFailureTracker.reset();
    loginGuard.reset();
  });

  afterEach(() => {
    bcrypt.compare = originalCompare;
    delete pool.query;
    if (savedSecret === undefined) delete process.env.JWT_SECRET;
    else process.env.JWT_SECRET = savedSecret;
  });

  const login = (body, ip = '198.51.100.10') =>
    fetch(`${baseUrl}/auth/login`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'X-Forwarded-For': ip },
      body: JSON.stringify(body),
    });

  it('olmayan hesap: 401 ve karsilastirma ASENKRON sahte ozetle yapilir (hesap varligi sureden cikmaz)', async () => {
    const response = await login({ email: 'hic-yok@example.com', password: 'herhangi-bir-parola' });
    assert.equal(response.status, 401);
    assert.deepEqual(compareCalls, [await getDummyPasswordHash()]);
  });

  it('var olan hesap: yanlis parola 401, dogru parola 200 (gercek ozetle asenkron karsilastirma)', async () => {
    const wrong = await login({ email: 'ali@example.com', password: 'yanlis-parola-1' });
    assert.equal(wrong.status, 401);
    const ok = await login({ email: 'ali@example.com', password: PASSWORD });
    assert.equal(ok.status, 200);
    const body = await ok.json();
    assert.equal(typeof body.token, 'string');
    assert.deepEqual(compareCalls, [hash, hash]);
  });

  it('bozuk / bcrypt olmayan saklı ozet: sahte ozetle karsilastirilir, 401 (silinmis hesap sureden ayrismaz)', async () => {
    pool.query = async (text) =>
      String(text).includes('LOWER(login_name)') ? { rows: [{ ...account, password_hash: '!silinmis-hesap-ozeti' }], rowCount: 1 } : { rows: [], rowCount: 0 };
    const response = await login({ email: 'ali@example.com', password: PASSWORD });
    assert.equal(response.status, 401);
    assert.deepEqual(compareCalls, [await getDummyPasswordHash()]);
  });
});
