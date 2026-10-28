// Guvenlik denetimi auth-1 / auth-2 / auth-3: KALICI (DB) deneme sinirlari (migrations/085 + security/attempt_limits.js).
//   1) 4 haneli ilk PIN ile giris (POST /auth/login): 5 yanlis -> 15 dk kilit (423 PIN_LOCKED), kilitliyken parola karsilastirilmaz, dogru PIN sayaci sifirlar,
//      yeniden baslatmada (bellek ici koruma sifirlansa da) kilit surer, artan kilit, paralel istek N tahmin yapamaz.
//   2) e-posta dogrulama kodu (/auth/verify-code ve /auth/oauth/:saglayici/verify-code) ve SMS kodu: kod basina 5 yanlis -> kod kullanilamaz, yeni kod istenir
//      (ZATEN vardi; davranis korunur) + kodlar ARASI birikimli kilit (24 saatte 15 yanlis -> 423); 30 dk kod suresi degismez.
// DB'siz: sahte pool / istemci; sinir tablosunu LimitStore SQL'in bire bir JS karsiligi olarak taklit eder (SQL'in kendisi gercek PostgreSQL'e karsi
// scripts/qa_auth_attempt_limits_pg.mjs ile dogrulanir: atomiklik, artan kilit, pencere, sessizlik, bakim).
import { describe, it, before, after, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import bcrypt from 'bcryptjs';
import express from 'express';

process.env.JWT_SECRET = process.env.JWT_SECRET || 'attempt-limits-test-only-secret-value-0123456789abcdef';

await import('../src/utils/async_errors.js');
const { pool } = await import('../src/db.js');
const { authRouter } = await import('../src/routes/auth_routes.js');
const { oauthRouter } = await import('../src/modules/oauth_routes.js');
const { createErrorHandler } = await import('../src/middlewares/error_handler.js');
const { loginFailureTracker, loginGuard } = await import('../src/middlewares/login_throttle.js');
const { loginRateLimiter, verifyCodeLimiter } = await import('../src/middlewares/rate_limiters.js');
const { resolveTrustProxy } = await import('../src/security/trust_proxy.js');
const limits = await import('../src/security/attempt_limits.js');
const { AUTH_ATTEMPT_LIMITS_DDL, ensureAuthAttemptLimitsSchema } = await import('../src/modules/auth_attempt_limits_schema.js');
const { verifyIndividualEmailCode } = await import('../src/services/membership_service.js');
const { verifyOAuthEmailCode } = await import('../src/modules/oauth_login.js');
const { hashCode, verifySmsCode } = await import('../src/modules/sms_login.js');
const { smsHooks } = await import('../src/modules/sms_provider.js');
const { normalizePersonPhone } = await import('../src/modules/people_common.js');
const { VERIFICATION_CODE_TTL_MINUTES, VERIFICATION_MAX_ATTEMPTS_PER_CODE } = await import('../src/services/membership_rules.js');

const { ATTEMPT_POLICIES } = limits;
// Kilit olayi kancasi: testlerde konsola yazmaz, olaylari toplar (varsayilan kanca ayrica test edilir).
const defaultOnLock = limits.attemptLimitHooks.onLock;
const lockEvents = [];
limits.attemptLimitHooks.onLock = (event) => lockEvents.push(event);
const here = path.dirname(fileURLToPath(import.meta.url));
const read = (rel) => fs.readFileSync(path.join(here, '..', rel), 'utf8');
const norm = (text) => String(text).replace(/\s+/g, ' ').trim();
const MIN_MS = 60 * 1000;

// ------------------------------------------------------------------------------------------------ SQL'in JS karsiligi
class LimitStore {
  constructor() {
    this.rows = new Map();
    this.offsetMs = 0;
    this.statements = [];
  }

  now() {
    return Date.now() + this.offsetMs;
  }

  advance(ms) {
    this.offsetMs += ms;
  }

  size() {
    return this.rows.size;
  }

  /** Sinir tablosu ifadesiyse sonucu, degilse null. */
  handle(sql, params = []) {
    if (!sql.includes('auth_attempt_limits')) return null;
    this.statements.push(sql);
    if (/^INSERT INTO auth_attempt_limits AS l/.test(sql)) return this.register(...params);
    if (/^SELECT GREATEST\(1, CEIL.*FROM auth_attempt_limits WHERE scope = \$1 AND target = \$2 AND locked_until IS NOT NULL/.test(sql)) {
      return this.peek(params[0], params[1]);
    }
    if (/^DELETE FROM auth_attempt_limits WHERE scope = \$1 AND target = \$2$/.test(sql)) {
      this.rows.delete(`${params[0]}|${params[1]}`);
      return { rows: [], rowCount: 1 };
    }
    if (/^DELETE FROM auth_attempt_limits WHERE updated_at/.test(sql)) return { rows: [], rowCount: 0 };
    throw new Error(`beklenmeyen sinir sorgusu: ${sql}`);
  }

  peek(scope, target) {
    const row = this.rows.get(`${scope}|${target}`);
    const t = this.now();
    if (!row || row.locked_until === null || row.locked_until <= t) return { rows: [], rowCount: 0 };
    return { rows: [{ retry_after_seconds: Math.max(1, Math.ceil((row.locked_until - t) / 1000)) }], rowCount: 1 };
  }

  register(scope, target, maxFailures, windowMinutes, baseLockMinutes, maxLockMinutes, quietMinutes) {
    const key = `${scope}|${target}`;
    const t = this.now();
    let row = this.rows.get(key);
    if (!row) {
      row = { fail_count: 1, window_started_at: t, locked_until: null, lock_level: 0, updated_at: t };
      this.rows.set(key, row);
      return { rows: [this.view(row, t)], rowCount: 1 };
    }
    if (row.locked_until !== null && row.locked_until > t) return { rows: [], rowCount: 0 }; // DO UPDATE ... WHERE: kilitli satira yazilmaz
    const fresh = row.window_started_at <= t - windowMinutes * MIN_MS;
    const count = fresh ? 1 : row.fail_count + 1;
    const trips = count >= maxFailures;
    const quiet = Math.max(row.updated_at, row.locked_until ?? row.updated_at) <= t - quietMinutes * MIN_MS;
    const level = quiet ? 0 : row.lock_level;
    row.fail_count = trips ? 0 : count;
    row.window_started_at = trips || fresh ? t : row.window_started_at;
    row.lock_level = trips ? Math.min(level + 1, 20) : level;
    row.locked_until = trips ? t + Math.min(baseLockMinutes * 2 ** level, maxLockMinutes) * MIN_MS : null;
    row.updated_at = t;
    return { rows: [this.view(row, t)], rowCount: 1 };
  }

  view(row, t) {
    const locked = row.locked_until !== null && row.locked_until > t;
    return {
      fail_count: row.fail_count,
      lock_level: row.lock_level,
      locked_until: row.locked_until === null ? null : new Date(row.locked_until),
      locked,
      retry_after_seconds: row.locked_until === null ? null : Math.max(1, Math.ceil((row.locked_until - t) / 1000)),
    };
  }
}

// ------------------------------------------------------------------------------------------------ ilkeler ve metinler
describe('kalici deneme sinirlari: ilkeler, hedef anahtari, mesajlar', () => {
  it('ilk PIN: 5 yanlis -> 15 dk; kod ilkeleri: 24 saatte 15 yanlis -> 1 saat; hepsi en cok 24 saat', () => {
    const pin = ATTEMPT_POLICIES.apartmentPin;
    assert.deepEqual([pin.scope, pin.maxFailures, pin.baseLockMinutes, pin.maxLockMinutes], ['apartment_pin', 5, 15, 24 * 60]);
    for (const policy of [ATTEMPT_POLICIES.emailCode, ATTEMPT_POLICIES.smsCode]) {
      assert.deepEqual([policy.maxFailures, policy.windowMinutes, policy.baseLockMinutes, policy.maxLockMinutes], [15, 24 * 60, 60, 24 * 60]);
    }
    assert.ok(Object.isFrozen(ATTEMPT_POLICIES) && Object.isFrozen(pin));
  });

  it('hedef SHA-256 ozeti (64 hex): e-posta / telefon duz metin saklanmaz; e-posta buyuk-kucuk harf duyarsiz; PIN hedefi parola ozetiyle degisir', () => {
    const mail = limits.emailCodeTarget('Kisi@Example.com');
    assert.match(mail, /^[0-9a-f]{64}$/);
    assert.equal(mail, limits.emailCodeTarget(' kisi@example.com '));
    assert.doesNotMatch(mail, /kisi|example/i);
    assert.match(limits.smsCodeTarget('+905321112233'), /^[0-9a-f]{64}$/);
    assert.notEqual(limits.apartmentPinTarget(7, 'ozet-a'), limits.apartmentPinTarget(7, 'ozet-b'), 'PIN yenilenince (ozet degisir) sayac sifirdan baslar');
    assert.notEqual(limits.apartmentPinTarget(7, 'ozet-a'), limits.apartmentPinTarget(8, 'ozet-a'));
  });

  it('SQL: ON CONFLICT ile atomik; KILITLI satira yazilmaz (DO UPDATE ... WHERE); kilit yokken yalniz tek ifade', () => {
    const sql = norm(limits.SQL_REGISTER_FAILURE);
    assert.match(sql, /^INSERT INTO auth_attempt_limits AS l \(scope, target, fail_count, window_started_at, locked_until, lock_level, updated_at\)/);
    assert.match(sql, /ON CONFLICT \(scope, target\) DO UPDATE SET/);
    assert.match(sql, /WHERE l\.locked_until IS NULL OR l\.locked_until <= NOW\(\) RETURNING/);
    assert.doesNotMatch(sql, /\bDELETE\b|\bDROP\b/i);
    assert.match(norm(limits.SQL_RESET_ATTEMPTS), /^DELETE FROM auth_attempt_limits WHERE scope = \$1 AND target = \$2$/);
    assert.match(norm(limits.SQL_PURGE_STALE_ATTEMPTS), /locked_until IS NULL OR locked_until < NOW\(\)/, 'kilitli satir temizlenmez');
  });

  it('kilidi KOYAN cagri izleme kancasini tek kez cagirir; blocked cagri cagirmaz; olayda kisisel veri yok (yalniz hedef ozetinin ilk 10 karakteri)', async () => {
    const store = new LimitStore();
    const db = { query: async (text, params) => store.handle(norm(text), params) };
    const target = limits.emailCodeTarget('kisi@example.com');
    lockEvents.length = 0;
    for (let i = 0; i < 14; i += 1) await limits.registerAttemptFailure(ATTEMPT_POLICIES.emailCode, target, db);
    assert.equal(lockEvents.length, 0);
    const tripped = await limits.registerAttemptFailure(ATTEMPT_POLICIES.emailCode, target, db);
    assert.equal(tripped.locked, true);
    assert.equal(lockEvents.length, 1);
    assert.deepEqual(lockEvents[0], { scope: 'email_code', level: 1, retryAfterSeconds: 3600, key: target.slice(0, 10) });
    const blocked = await limits.registerAttemptFailure(ATTEMPT_POLICIES.emailCode, target, db);
    assert.equal(blocked.blocked, true);
    assert.equal(lockEvents.length, 1, 'kilitliyken yeni olay yok');

    const warned = [];
    const realWarn = console.warn;
    console.warn = (...args) => warned.push(args.join(' '));
    try {
      defaultOnLock(lockEvents[0]);
    } finally {
      console.warn = realWarn;
    }
    assert.equal(warned.length, 1);
    assert.match(warned[0], /^\[attempt-limits\] kilit kapsam=email_code seviye=1 sure_sn=3600 anahtar=[0-9a-f]{10}$/);
    assert.doesNotMatch(warned[0], /kisi|example/i);
  });

  it('Turkce kalan sure ve kilit gövdeleri', () => {
    assert.equal(limits.formatWaitTr(45), '45 saniye');
    assert.equal(limits.formatWaitTr(900), '15 dakika');
    assert.equal(limits.formatWaitTr(3540), '59 dakika');
    assert.equal(limits.formatWaitTr(3600), '1 saat');
    assert.equal(limits.formatWaitTr(7200), '2 saat');
    assert.equal(limits.formatWaitTr(86400), '24 saat');
    const body = limits.pinLockedBody(900);
    assert.equal(body.code, 'PIN_LOCKED');
    assert.equal(body.retry_after_seconds, 900);
    assert.match(body.error, /PIN/);
    assert.match(body.error, /15 dakika/);
    assert.match(body.error, /site yönetiminizden/);
    const error = limits.codeLockedError('email', 3600);
    assert.equal(error.statusCode, 423);
    assert.equal(error.code, 'VERIFICATION_LOCKED');
    assert.equal(error.extra.retry_after_seconds, 3600);
    assert.match(error.message, /yeni bir kod/);
    assert.equal(limits.codeLockedError('sms', 60).code, 'SMS_CODE_LOCKED');
  });
});

// ------------------------------------------------------------------------------------------------ sema
describe('085 sema: migration = sema modulu, db.js baglantisi, bakim', () => {
  it('migration dosyasinin ifadeleri AUTH_ATTEMPT_LIMITS_DDL ile ayni ve ayni sirada; ekleyici ve idempotent', () => {
    const sql = read('migrations/085_auth_attempt_limits.sql')
      .split(/\r?\n/)
      .filter((line) => !line.trim().startsWith('--'))
      .join('\n');
    const statements = sql.split(';').map(norm).filter(Boolean);
    assert.deepEqual(statements, AUTH_ATTEMPT_LIMITS_DDL.map(norm));
    for (const statement of statements) assert.match(statement, /IF NOT EXISTS/);
    assert.doesNotMatch(sql, /\b(DROP|DELETE|UPDATE|TRUNCATE|ALTER)\b/i);
    assert.match(sql, /PRIMARY KEY \(scope, target\)/);
    const numbered = fs.readdirSync(path.join(here, '..', 'migrations')).filter((name) => name.startsWith('085_'));
    assert.deepEqual(numbered, ['085_auth_attempt_limits.sql'], '085 numarasi yinelenmez');
  });

  it('sema ozeti: hedef + sayac + pencere + kilit bitisi + seviye sutunlari', () => {
    const table = norm(AUTH_ATTEMPT_LIMITS_DDL[0]);
    for (const column of ['scope TEXT NOT NULL', 'target TEXT NOT NULL', 'fail_count INTEGER NOT NULL DEFAULT 0', 'window_started_at TIMESTAMPTZ NOT NULL', 'locked_until TIMESTAMPTZ', 'lock_level SMALLINT NOT NULL DEFAULT 0']) {
      assert.ok(table.includes(column), column);
    }
  });

  it('ensureAuthAttemptLimitsSchema: tablo varsa YALNIZ katalog sorgusu; yoksa katalog + 2 ifade (tablo, indeks)', async () => {
    const run = async (present) => {
      const log = [];
      await ensureAuthAttemptLimitsSchema({
        async query(text) {
          log.push(norm(text));
          return { rows: [{ present }], rowCount: 1 };
        },
      });
      return log;
    };
    assert.equal((await run(true)).length, 1);
    const created = await run(false);
    assert.equal(created.length, 3);
    assert.match(created[1], /^CREATE TABLE IF NOT EXISTS auth_attempt_limits/);
    assert.match(created[2], /^CREATE INDEX IF NOT EXISTS idx_auth_attempt_limits_updated/);
  });

  it('db.js 085 modulunu ensureFinanceFundsSchema (080) ve people_v1 aktarimindan ONCE/SONRA dogru yerde cagirir', () => {
    const db = read('src/db.js');
    assert.ok(db.includes("import { ensureAuthAttemptLimitsSchema } from './modules/auth_attempt_limits_schema.js';"));
    const call = db.indexOf('await ensureAuthAttemptLimitsSchema(client);');
    assert.ok(call > db.indexOf('await ensureFinanceFundsSchema(client);'));
    assert.ok(call < db.indexOf('await runPeopleBackfill(client);'));
  });

  it('bakim temizligi (runDatabaseCleanup) sinir tablosunu 30 gun + kilidi bitmis kosuluyla temizler', async () => {
    const { runDatabaseCleanup } = await import('../src/services/maintenance_service.js');
    const queries = [];
    const result = await runDatabaseCleanup({
      async query(text) {
        queries.push(norm(text));
        return { rowCount: 0, rows: [] };
      },
    });
    assert.equal(result.success, true);
    const purge = queries.find((sql) => sql.startsWith('DELETE FROM auth_attempt_limits'));
    assert.ok(purge, 'temizlik calisti');
    assert.match(purge, /updated_at < NOW\(\) - INTERVAL '30 days'/);
    assert.match(purge, /locked_until IS NULL OR locked_until < NOW\(\)/);
  });
});

// ------------------------------------------------------------------------------------------------ 1) PIN ile giris (HTTP)
describe('POST /auth/login: 4 haneli ilk PIN icin KALICI deneme siniri', () => {
  const PIN = '4821';
  const PIN_HASH = bcrypt.hashSync(PIN, 4);
  const NEW_PIN_HASH = bcrypt.hashSync('9137', 4);
  const LOGIN_NAME = '1000_ABlok_Daire12';
  let server;
  let baseUrl;
  let store;
  let account;
  let compareCalls;
  let originalCompare;
  let ipCounter;

  const pinAccount = () => ({
    id: 501,
    full_name: 'Daire 12 Sakini',
    email: '1000_ablok_daire12@ahbu.local',
    login_name: LOGIN_NAME,
    role: 'apartment_owner',
    is_active: true,
    email_verified: true,
    approval_status: 'approved',
    phone_number: null,
    created_at: new Date('2026-01-01T00:00:00Z'),
    password_hash: PIN_HASH,
    must_change_password: true,
    pin_issued: true,
  });

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
    store = new LimitStore();
    account = pinAccount();
    ipCounter = 0;
    pool.query = async (text, params = []) => {
      const sql = norm(text);
      const limited = store.handle(sql, params);
      if (limited) return limited;
      if (sql.includes('LOWER(login_name)')) {
        const ident = String(params[0]).toLowerCase();
        const match = account && (ident === account.login_name.toLowerCase() || ident === account.email.toLowerCase());
        return match ? { rows: [{ ...account }], rowCount: 1 } : { rows: [], rowCount: 0 };
      }
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
  });

  // Her istek FARKLI kaynaktan: bellek ici cift / IP katmanlari tetiklenmez; engel yalniz KALICI (DB) kilittir.
  const nextIp = () => `198.51.100.${(ipCounter += 1) % 250 + 1}`;
  const attempt = (password, { identifier = LOGIN_NAME, ip = nextIp() } = {}) =>
    fetch(`${baseUrl}/auth/login`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'X-Forwarded-For': ip },
      body: JSON.stringify({ login: identifier, password }),
    });
  const wrongTimes = async (n) => {
    const statuses = [];
    for (let i = 0; i < n; i += 1) statuses.push((await attempt(`000${i}`)).status);
    return statuses;
  };

  it('4 yanlis PIN 401; 5. yanlis 423 PIN_LOCKED + Retry-After 900 + Turkce mesaj', async () => {
    assert.deepEqual(await wrongTimes(4), [401, 401, 401, 401]);
    const fifth = await attempt('0000');
    assert.equal(fifth.status, 423);
    assert.equal(fifth.headers.get('retry-after'), '900');
    const body = await fifth.json();
    assert.equal(body.code, 'PIN_LOCKED');
    assert.equal(body.retry_after_seconds, 900);
    assert.match(body.error, /PIN/);
    assert.match(body.error, /15 dakika/);
    assert.match(body.error, /yenilemesini/);
  });

  it('kilitliyken DOGRU PIN bile 423 ve parola KARSILASTIRILMAZ; baska kaynaktan da (dagitik saldiri) engellenir', async () => {
    await wrongTimes(5);
    const comparesBefore = compareCalls.length;
    for (let i = 0; i < 3; i += 1) {
      const response = await attempt(PIN);
      assert.equal(response.status, 423);
      assert.equal((await response.json()).code, 'PIN_LOCKED');
    }
    assert.equal(compareCalls.length, comparesBefore, 'kilitliyken bcrypt karsilastirmasi yok');
    assert.equal(store.rows.size, 1);
    const row = [...store.rows.values()][0];
    assert.equal(row.fail_count, 0, 'kilitliyken sayac degismez (yazma yok)');
  });

  it('sure dolunca dogru PIN 200 (must_change_password true) ve sayac sifirlanir (satir silinir)', async () => {
    await wrongTimes(5);
    store.advance(15 * MIN_MS + 1000);
    const ok = await attempt(PIN);
    assert.equal(ok.status, 200);
    const body = await ok.json();
    assert.equal(body.user.must_change_password, true);
    assert.equal(typeof body.token, 'string');
    assert.equal(store.size(), 0, 'basarili dogrulama sayaci ve seviyeyi siler');
  });

  it('dogru PIN sayaci sifirlar: 4 yanlis + dogru, sonra yine 4 yanlis kilitlemez, 5. kilitler', async () => {
    await wrongTimes(4);
    assert.equal((await attempt(PIN)).status, 200);
    assert.deepEqual(await wrongTimes(4), [401, 401, 401, 401]);
    assert.equal((await attempt('1111')).status, 423);
  });

  it('5. deneme DOGRUYSA kilit kalkar: 4 yanlis + dogru = 200 (rezerve edilen hak iade)', async () => {
    await wrongTimes(4);
    const fifth = await attempt(PIN);
    assert.equal(fifth.status, 200);
    assert.equal(store.size(), 0);
    assert.equal((await attempt(PIN)).status, 200, 'kilit koymamisti');
  });

  it('artan kilit: sure dolunca tekrar 5 yanlis -> 30 dk', async () => {
    await wrongTimes(5);
    store.advance(15 * MIN_MS + 1000);
    assert.deepEqual(await wrongTimes(4), [401, 401, 401, 401]);
    const second = await attempt('2222');
    assert.equal(second.status, 423);
    assert.equal(second.headers.get('retry-after'), '1800');
    assert.match((await second.json()).error, /30 dakika/);
  });

  it('yeniden baslatma: bellek ici koruma SIFIRLANSA bile kilit surer (kalicilik)', async () => {
    await wrongTimes(5);
    loginGuard.reset();
    loginFailureTracker.reset();
    loginRateLimiter.reset();
    const response = await attempt(PIN);
    assert.equal(response.status, 423, 'DB kilidi yeniden baslatmadan etkilenmez');
  });

  it('sayac HESAP basinadir: kullanici adi ve e-posta ile karisik denemeler ayni bütçeyi paylasir', async () => {
    const statuses = [];
    for (const identifier of [LOGIN_NAME, account.email, LOGIN_NAME.toUpperCase(), account.email, LOGIN_NAME]) {
      statuses.push((await attempt('0000', { identifier })).status);
    }
    assert.deepEqual(statuses, [401, 401, 401, 401, 423]);
  });

  it('PIN yenilenince (parola ozeti degisir) sayac sifirdan baslar; eski PIN artik gecersiz', async () => {
    await wrongTimes(4);
    account.password_hash = NEW_PIN_HASH; // yonetici PIN'i yeniledi
    assert.equal((await attempt('0000')).status, 401, 'yeni PIN icin sayac 1');
    assert.equal((await attempt('9137')).status, 200, 'yeni PIN ile giris');
  });

  it('paralel 12 yanlis istek: karsilastirmaya EN COK 5 istek ulasir (4 x 401 + 1 kilitleyen + 7 x 423)', async () => {
    const responses = await Promise.all(Array.from({ length: 12 }, (_, i) => attempt(`00${i}`)));
    const statuses = responses.map((response) => response.status).sort();
    assert.deepEqual(statuses, [401, 401, 401, 401, 423, 423, 423, 423, 423, 423, 423, 423]);
    assert.equal(compareCalls.length, 5, 'N paralel istek N tahmin yapamaz');
  });

  it('PIN\'i olmayan hesap ve olmayan hesap: sinir tablosuna HIC yazilmaz / okunmaz (kimliksiz uc yazma yuku yok)', async () => {
    account.pin_issued = false;
    account.must_change_password = false;
    for (let i = 0; i < 8; i += 1) assert.equal((await attempt(`yanlis-${i}`)).status, 401);
    for (let i = 0; i < 3; i += 1) assert.equal((await attempt('1234', { identifier: 'hic-yok@example.com' })).status, 401);
    assert.deepEqual(store.statements, []);
    assert.equal((await attempt(PIN)).status, 200, 'PIN isareti yoksa normal giris');
    assert.deepEqual(store.statements, []);
  });

  it('PIN hesabinda 423 yalniz KILIT aninda gorunur: 5. yanlistan once yanit 401 (kilit ongoru bilgisi sizmaz)', async () => {
    const statuses = await wrongTimes(4);
    assert.ok(statuses.every((status) => status === 401));
  });
});

// ------------------------------------------------------------------------------------------------ 2) e-posta dogrulama kodu
describe('e-posta dogrulama kodu: kod basina 5 yanlis (korundu) + kodlar arasi KALICI birikimli kilit', () => {
  const EMAIL = 'ali@example.com';
  const GOOD_CODE = '123456';
  const savedConnect = pool.connect;
  let store;
  let log;
  let state;

  /** Dogrulama istemcisi: atomik deneme hakki (kod basina 5) + kod tablosu + sinir tablosu taklidi. */
  function makeClient() {
    return {
      async query(text, params = []) {
        const sql = norm(text);
        log.push(sql);
        if (/^(BEGIN|COMMIT|ROLLBACK)$/.test(sql)) return { rows: [], rowCount: 0 };
        if (sql.startsWith('SELECT pg_advisory_xact_lock')) return { rows: [], rowCount: 1 };
        const limited = store.handle(sql, params);
        if (limited) return limited;
        if (sql.includes('attempt_count = ev.attempt_count + 1')) {
          state.claimParams = params;
          if (state.attempts >= params[2]) return { rows: [], rowCount: 0 };
          state.attempts += 1;
          return { rows: [{ id: 700, code_hash: state.codeHash, attempt_count: state.attempts }], rowCount: 1 };
        }
        if (sql.includes('AS code_attempts')) return { rows: [{ code_attempts: state.attempts, window_attempts: state.attempts }], rowCount: 1 };
        if (/^UPDATE email_verifications SET is_verified = TRUE, verified_at = NOW\(\)/.test(sql)) return { rows: [{ id: 700 }], rowCount: 1 };
        if (/^UPDATE email_verifications SET is_verified = TRUE WHERE LOWER\(email\)/.test(sql)) return { rows: [], rowCount: 0 };
        if (/^UPDATE users SET email_verified = TRUE/.test(sql)) {
          return {
            rows: [{ id: 77, user_code: 77, full_name: 'Ali Veli', email: EMAIL, login_name: null, role: 'individual', is_active: true, email_verified: true, approval_status: 'approved', phone_number: null, created_at: new Date(), password_hash: '$2a$04$abcdefghijklmnopqrstuuABCDEFGHIJKLMNOPQRSTUVWXYZ01234' }],
            rowCount: 1,
          };
        }
        if (sql.includes('FROM site_manager_invitations')) return { rows: [], rowCount: 0 };
        throw new Error(`beklenmeyen istemci sorgusu: ${sql}`);
      },
      release() {},
    };
  }

  /** Kullanici yeni kod ister: eski kod gecersiz, yeni kodun sayaci 0. */
  const newCode = (code = GOOD_CODE) => {
    state.attempts = 0;
    state.codeHash = bcrypt.hashSync(code, 4);
  };

  beforeEach(() => {
    store = new LimitStore();
    log = [];
    state = { attempts: 0, codeHash: null, claimParams: null };
    newCode();
    pool.connect = async () => makeClient();
  });
  afterEach(() => {
    pool.connect = savedConnect;
  });

  const verify = (code) => verifyIndividualEmailCode({ email: EMAIL, code });
  const outcome = async (code) => {
    try {
      const result = await verify(code);
      return { status: 200, result };
    } catch (error) {
      return { status: error.statusCode, code: error.code, message: error.message, extra: error.extra };
    }
  };

  it('kod suresi 30 dk ve kod basina 5 deneme DEGISMEDI (mevcut davranis korunur)', async () => {
    assert.equal(VERIFICATION_CODE_TTL_MINUTES, 30);
    assert.equal(VERIFICATION_MAX_ATTEMPTS_PER_CODE, 5);
    await outcome('000000');
    assert.equal(state.claimParams[1], 30, 'deneme hakki 30 dk icindeki kodda ayrilir');
    assert.equal(state.claimParams[2], 5);
  });

  it('5 yanlis -> kod kullanilamaz, "yeni bir kod isteyiniz" (429); DOGRU kod bile o kodla kabul edilmez', async () => {
    for (let i = 0; i < 5; i += 1) {
      const wrong = await outcome(`00000${i}`);
      assert.equal(wrong.status, 400);
      assert.match(wrong.message, /hatalıdır/);
    }
    const sixth = await outcome(GOOD_CODE);
    assert.equal(sixth.status, 429);
    assert.match(sixth.message, /yeni bir kod/);
    newCode();
    assert.equal((await outcome(GOOD_CODE)).status, 200, 'yeni kod gecerli (kod sayaci kod basina)');
  });

  it('kodlar ARASI birikimli kilit: yeni kod istemek sayaci sifirlamaz; 15. yanlis 423 VERIFICATION_LOCKED (1 saat), sonra dogru kod bile engellenir', async () => {
    const statuses = [];
    for (let codeNo = 0; codeNo < 3; codeNo += 1) {
      newCode();
      for (let i = 0; i < 5; i += 1) statuses.push((await outcome(`1${i}0000`)).status);
    }
    assert.deepEqual(statuses.slice(0, 14), Array(14).fill(400));
    assert.equal(statuses[14], 423, '15. yanlis kilidi koyar');

    newCode();
    const claimsBefore = log.filter((sql) => sql.includes('attempt_count = ev.attempt_count + 1')).length;
    const locked = await outcome(GOOD_CODE);
    assert.equal(locked.status, 423);
    assert.equal(locked.code, 'VERIFICATION_LOCKED');
    assert.ok(locked.extra.retry_after_seconds > 59 * 60 && locked.extra.retry_after_seconds <= 3600);
    assert.match(locked.message, /yeni bir kod/);
    assert.equal(log.filter((sql) => sql.includes('attempt_count = ev.attempt_count + 1')).length, claimsBefore, 'kilitliyken deneme hakki harcanmaz, kod karsilastirilmaz');

    store.advance(61 * MIN_MS);
    const ok = await outcome(GOOD_CODE);
    assert.equal(ok.status, 200);
    assert.equal(store.size(), 0, 'dogru kod birikimli sayaci ve seviyeyi siler');
    assert.ok(log.some((sql) => sql.startsWith('DELETE FROM auth_attempt_limits')));
  });

  it('kilit denetimi advisory kilitten SONRA, deneme hakkindan ONCE; yanlis kod sayaci AYNI islemde COMMIT edilir; kilitliyken ROLLBACK', async () => {
    await outcome('000000');
    const order = (re) => log.findIndex((sql) => re.test(sql));
    assert.ok(order(/^SELECT pg_advisory_xact_lock/) < order(/FROM auth_attempt_limits/));
    assert.ok(order(/FROM auth_attempt_limits/) < order(/attempt_count = ev\.attempt_count \+ 1/));
    assert.ok(order(/^INSERT INTO auth_attempt_limits/) < order(/^COMMIT$/), 'birikimli sayac COMMIT oncesi yazilir');
    log.length = 0;
    for (let i = 0; i < 14; i += 1) {
      newCode();
      await outcome('000000');
    }
    log.length = 0;
    const locked = await outcome(GOOD_CODE);
    assert.equal(locked.status, 423);
    assert.ok(log.includes('ROLLBACK') && !log.includes('COMMIT'), 'kilitliyken islem geri alinir');
  });

  it('e-posta buyuk/kucuk harf duyarsiz tek bütçe; baska e-postanin bütçesi etkilenmez', async () => {
    for (let i = 0; i < 15; i += 1) {
      newCode();
      try {
        await verifyIndividualEmailCode({ email: i % 2 ? EMAIL.toUpperCase() : EMAIL, code: '000000' });
      } catch {
        // beklenen
      }
    }
    assert.equal((await outcome(GOOD_CODE)).status, 423);
    newCode();
    assert.equal(
      (await verifyIndividualEmailCode({ email: 'baska@example.com', code: GOOD_CODE }).then(() => 200, (error) => error.statusCode)),
      200,
    );
  });
});

// ------------------------------------------------------------------------------------------------ 2b) OAuth e-posta kodu (ayni sayac) ve rota
describe('OAuth e-posta kodu (/auth/oauth/:saglayici/verify-code): AYNI birikimli sayac, 423 + Retry-After', () => {
  const EMAIL = 'deniz@gmail.com';
  const savedConnect = pool.connect;
  let store;
  let state;
  let server;
  let baseUrl;

  function makeClient() {
    return {
      async query(text, params = []) {
        const sql = norm(text);
        if (/^(BEGIN|COMMIT|ROLLBACK)$/.test(sql)) return { rows: [], rowCount: 0 };
        if (sql.startsWith('SELECT pg_advisory_xact_lock')) return { rows: [], rowCount: 1 };
        const limited = store.handle(sql, params);
        if (limited) return limited;
        if (sql.includes('attempt_count = ev.attempt_count + 1')) {
          state.claims += 1;
          if (state.attempts >= params[2]) return { rows: [], rowCount: 0 };
          state.attempts += 1;
          return { rows: [{ id: 800, code_hash: state.codeHash, attempt_count: state.attempts }], rowCount: 1 };
        }
        if (sql.includes('AS code_attempts')) return { rows: [{ code_attempts: state.attempts, window_attempts: state.attempts }], rowCount: 1 };
        throw new Error(`beklenmeyen istemci sorgusu: ${sql}`);
      },
      release() {},
    };
  }

  const fresh = () => {
    state.attempts = 0;
    state.codeHash = bcrypt.hashSync('654321', 4);
  };

  before(async () => {
    const app = express();
    app.use(express.json());
    app.use(oauthRouter);
    app.use(createErrorHandler({ logger: { error: () => {}, log: () => {}, warn: () => {} } }));
    await new Promise((resolve) => {
      server = app.listen(0, '127.0.0.1', resolve);
    });
    baseUrl = `http://127.0.0.1:${server.address().port}`;
  });
  after(() => new Promise((resolve) => {
    pool.connect = savedConnect;
    server.closeAllConnections?.();
    server.close(resolve);
  }));
  beforeEach(() => {
    store = new LimitStore();
    state = { attempts: 0, codeHash: null, claims: 0 };
    fresh();
    pool.connect = async () => makeClient();
  });

  const post = (code) =>
    fetch(`${baseUrl}/auth/oauth/google/verify-code`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email: EMAIL, code }),
    });

  it('servis: yanlis kod 400; 15. yanlis (kodlar arasi) 423; kilitliyken kod karsilastirilmaz', async () => {
    const results = [];
    for (let i = 0; i < 15; i += 1) {
      fresh();
      results.push(
        await verifyOAuthEmailCode({ provider: 'google', email: EMAIL, code: '000000' }).then(
          () => 200,
          (error) => error.statusCode,
        ),
      );
    }
    assert.deepEqual(results, [...Array(14).fill(400), 423]);
    const claims = state.claims;
    fresh();
    await assert.rejects(
      () => verifyOAuthEmailCode({ provider: 'google', email: EMAIL, code: '654321' }),
      (error) => error.statusCode === 423 && error.code === 'VERIFICATION_LOCKED',
    );
    assert.equal(state.claims, claims, 'kilitliyken deneme hakki harcanmaz');
  });

  it('HTTP rota: 400 -> (15. yanlista) 423 + Retry-After + code + retry_after_seconds; baska ek alan sizmaz', async () => {
    for (let i = 0; i < 14; i += 1) {
      fresh();
      assert.equal((await post('000000')).status, 400);
    }
    fresh();
    const locked = await post('000000');
    assert.equal(locked.status, 423);
    const retryAfter = Number(locked.headers.get('retry-after'));
    assert.ok(retryAfter > 59 * 60 && retryAfter <= 3600);
    const body = await locked.json();
    assert.deepEqual(Object.keys(body).sort(), ['code', 'error', 'retry_after_seconds']);
    assert.equal(body.code, 'VERIFICATION_LOCKED');
    assert.equal(body.retry_after_seconds, retryAfter);
    assert.match(body.error, /doğrulama kodu/);
  });

  it('/auth/verify-code ile AYNI sayac: 10 yanlis e-posta yolundan + 5 yanlis OAuth yolundan = kilit', async () => {
    for (let i = 0; i < 10; i += 1) {
      fresh();
      await verifyIndividualEmailCode({ email: EMAIL, code: '000000' }).catch(() => {});
    }
    const results = [];
    for (let i = 0; i < 5; i += 1) {
      fresh();
      results.push(await verifyOAuthEmailCode({ provider: 'google', email: EMAIL, code: '000000' }).then(() => 200, (error) => error.statusCode));
    }
    assert.deepEqual(results, [400, 400, 400, 400, 423]);
  });
});

// ------------------------------------------------------------------------------------------------ 2c) /auth/verify-code rotasi
describe('POST /auth/verify-code (HTTP): 423 yaniti Retry-After ve retry_after_seconds tasir', () => {
  const savedConnect = pool.connect;
  let store;
  let server;
  let baseUrl;
  let attempts;

  before(async () => {
    const app = express();
    app.use(express.json());
    app.use(authRouter);
    app.use(createErrorHandler({ logger: { error: () => {}, log: () => {}, warn: () => {} } }));
    await new Promise((resolve) => {
      server = app.listen(0, '127.0.0.1', resolve);
    });
    baseUrl = `http://127.0.0.1:${server.address().port}`;
  });
  after(() => new Promise((resolve) => {
    pool.connect = savedConnect;
    server.closeAllConnections?.();
    server.close(resolve);
  }));
  beforeEach(() => {
    store = new LimitStore();
    attempts = 0;
    const codeHash = bcrypt.hashSync('654321', 4);
    pool.connect = async () => ({
      async query(text, params = []) {
        const sql = norm(text);
        if (/^(BEGIN|COMMIT|ROLLBACK)$/.test(sql)) return { rows: [], rowCount: 0 };
        if (sql.startsWith('SELECT pg_advisory_xact_lock')) return { rows: [], rowCount: 1 };
        const limited = store.handle(sql, params);
        if (limited) return limited;
        if (sql.includes('attempt_count = ev.attempt_count + 1')) {
          attempts = 0; // her istek "taze kod"
          attempts += 1;
          return { rows: [{ id: 900, code_hash: codeHash, attempt_count: attempts }], rowCount: 1 };
        }
        throw new Error(`beklenmeyen istemci sorgusu: ${sql}`);
      },
      release() {},
    });
  });

  it('14 yanlis 400, 15. yanlis 423 VERIFICATION_LOCKED (+ Retry-After), sonra kilitliyken 423', async () => {
    // Bellek ici IP+e-posta sinirlayicisi (10 / 15 dk) bu testin konusu degil: her istekten once sifirlanir; engel yalniz KALICI kilittir.
    const post = (code) => {
      verifyCodeLimiter.reset();
      return fetch(`${baseUrl}/auth/verify-code`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'X-Forwarded-For': '203.0.113.9' },
        body: JSON.stringify({ email: 'kisi@example.com', code }),
      });
    };
    for (let i = 0; i < 14; i += 1) assert.equal((await post('000000')).status, 400);
    const locked = await post('000000');
    assert.equal(locked.status, 423);
    const retryAfter = Number(locked.headers.get('retry-after'));
    assert.ok(retryAfter > 0 && retryAfter <= 3600);
    const body = await locked.json();
    assert.equal(body.code, 'VERIFICATION_LOCKED');
    assert.equal(body.retry_after_seconds, retryAfter);
    const again = await post('654321');
    assert.equal(again.status, 423, 'dogru kod bile kilitliyken kabul edilmez');
  });
});

// ------------------------------------------------------------------------------------------------ 3) SMS kodu
describe('SMS giris kodu: kod basina 5 yanlis (korundu) + kodlar arasi KALICI birikimli kilit', () => {
  const RAW_PHONE = '0532 111 22 33';
  const PHONE = normalizePersonPhone(RAW_PHONE);
  const GOOD = '123456';
  const savedProvider = smsHooks.provider;
  let store;
  let codes;
  let log;

  /** sms_login_codes taklidi: en yeni acik kod uzerinde atomik deneme hakki (kod basina en cok $2). */
  function fakeDb() {
    return {
      async query(text, params = []) {
        const sql = norm(text);
        log.push(sql);
        const limited = store.handle(sql, params);
        if (limited) return limited;
        if (/^UPDATE sms_login_codes SET attempts/.test(sql)) {
          const open = codes.filter((row) => !row.consumed && row.attempts < params[1]).sort((a, b) => b.id - a.id)[0];
          if (!open) return { rows: [], rowCount: 0 };
          open.attempts += 1;
          return { rows: [{ id: open.id, user_code: open.user_code, code_hash: open.code_hash }], rowCount: 1 };
        }
        if (/^UPDATE sms_login_codes SET consumed_at/.test(sql)) {
          const row = codes.find((item) => item.id === params[0] && !item.consumed);
          if (!row) return { rows: [], rowCount: 0 };
          row.consumed = true;
          return { rows: [{ id: row.id }], rowCount: 1 };
        }
        if (/^SELECT user_code AS id/.test(sql)) {
          return {
            rows: [{ id: 77, full_name: 'Ali Veli', email: 'ali@example.com', login_name: null, role: 'individual', is_active: true, email_verified: true, approval_status: 'approved', phone_number: RAW_PHONE, created_at: new Date(), password_hash: '$2a$04$abcdefghijklmnopqrstuuABCDEFGHIJKLMNOPQRSTUVWXYZ01234', must_change_password: false }],
            rowCount: 1,
          };
        }
        return { rows: [], rowCount: 0 };
      },
    };
  }
  const issue = (userCode = 77) => {
    codes.push({ id: codes.length + 1, user_code: userCode, code_hash: hashCode(PHONE, GOOD), attempts: 0, consumed: false });
  };
  const run = (code) => verifySmsCode(RAW_PHONE, code, fakeDb()).then(() => ({ status: 200 }), (error) => ({ status: error.statusCode, code: error.code, extra: error.extra }));

  beforeEach(() => {
    store = new LimitStore();
    codes = [];
    log = [];
    smsHooks.provider = () => ({ name: 'test', send: async () => {} });
  });
  afterEach(() => {
    smsHooks.provider = savedProvider;
  });

  it('kod basina 5 yanlis -> o kod kullanilamaz (401 SMS_CODE_INVALID); yeni kodla dogru kod calisir', async () => {
    issue();
    for (let i = 0; i < 5; i += 1) assert.deepEqual(await run(`00000${i}`), { status: 401, code: 'SMS_CODE_INVALID', extra: null });
    assert.equal((await run(GOOD)).status, 401, 'kod tukendi: dogru kod bile kabul edilmez');
    issue();
    assert.equal((await run(GOOD)).status, 200);
  });

  it('kodlar ARASI birikimli kilit: 15. yanlis 423 SMS_CODE_LOCKED (1 saat); kilitliyken karsilastirma ve deneme hakki YOK; sure dolunca dogru kod girer', async () => {
    const statuses = [];
    for (let codeNo = 0; codeNo < 3; codeNo += 1) {
      issue();
      for (let i = 0; i < 5; i += 1) statuses.push((await run(`11111${i}`)).status);
    }
    assert.deepEqual(statuses, [...Array(14).fill(401), 423]);
    issue();
    const updatesBefore = log.filter((sql) => /^UPDATE sms_login_codes SET attempts/.test(sql)).length;
    const locked = await run(GOOD);
    assert.equal(locked.status, 423);
    assert.equal(locked.code, 'SMS_CODE_LOCKED');
    assert.ok(locked.extra.retry_after_seconds > 59 * 60 && locked.extra.retry_after_seconds <= 3600);
    assert.equal(log.filter((sql) => /^UPDATE sms_login_codes SET attempts/.test(sql)).length, updatesBefore);
    store.advance(61 * MIN_MS);
    assert.equal((await run(GOOD)).status, 200);
    assert.equal(store.size(), 0, 'dogru kod sayaci siler');
  });

  it('acik kod YOKKEN (kod istenmeden) gonderilen bos denemeler sayilmaz: baskasinin SMS girisini kilitleyemez', async () => {
    for (let i = 0; i < 40; i += 1) assert.equal((await run('000000')).status, 401);
    assert.deepEqual(store.statements.filter((sql) => sql.startsWith('INSERT')), []);
    issue();
    assert.equal((await run(GOOD)).status, 200);
  });

  it('kayitsiz telefon (kod satiri kullanicisiz) kayitli telefonla AYNI sekilde sayilir: kullanici varligi sizmaz', async () => {
    const statuses = [];
    for (let codeNo = 0; codeNo < 3; codeNo += 1) {
      issue(null);
      for (let i = 0; i < 5; i += 1) statuses.push((await run(GOOD)).status);
    }
    assert.deepEqual(statuses, [...Array(14).fill(401), 423]);
  });
});
