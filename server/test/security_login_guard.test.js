// S-C: giriş koruması (hesap × kaynak / hesap geneli / IP geneli, artan bekleme, güvenilir cihaz, tek tip yanıt).
import { describe, it, before, after, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert/strict';
import bcrypt from 'bcryptjs';
import express from 'express';
import jwt from 'jsonwebtoken';
import '../src/utils/async_errors.js';
import { pool } from '../src/db.js';
import { authRouter } from '../src/routes/auth_routes.js';
import { createErrorHandler } from '../src/middlewares/error_handler.js';
import { clearAccountLocks, loginFailureTracker, loginGuard } from '../src/middlewares/login_throttle.js';
import { loginRateLimiter } from '../src/middlewares/rate_limiters.js';
import { resolveTrustProxy } from '../src/security/trust_proxy.js';
import {
  LOGIN_GUARD_DEFAULTS,
  PROVISIONAL_RETRY_AFTER_SECONDS,
  buildLoginAttempt,
  createEscalatingCounter,
  createLoginGuard,
  isBcryptHash,
  loginAccountKey,
} from '../src/security/login_guard.js';
import {
  DEVICE_TOKEN_TTL_SECONDS,
  deviceTokenMatchesPassword,
  issueDeviceToken,
  verifyDeviceToken,
} from '../src/security/login_device_token.js';
import { passwordVersionOf } from '../src/jwt.js';
import { BCRYPT_COST, bcryptCostOf } from '../src/security/password_hashing.js';

const MIN = 60 * 1000;
const SECRET = 'k9Fz-test-only-long-secret-value-0123456789abcdef';
const OTHER_SECRET = 'Zq7w-test-only-other-secret-value-abcdef012345';
const PASSWORD = 'Mavi-Kapi-77-Ruzgar';
const PASSWORD_HASH = bcrypt.hashSync(PASSWORD, 4);
const OTHER_PASSWORD_HASH = bcrypt.hashSync('Yesil-Kapi-88-Bulut', 4);

const attemptFor = (accountKey, ip, extra = {}) => ({
  accountKey,
  sourceKey: `ip:${ip}`,
  ipKey: `ip:${ip}`,
  trusted: false,
  ...extra,
});

function newGuard() {
  let clock = 1_000_000_000;
  const events = [];
  const guard = createLoginGuard({ now: () => clock, onLock: (event) => events.push(event) });
  return {
    guard,
    events,
    advance(ms) {
      clock += ms;
    },
  };
}

describe('login_guard: hesap × kaynak (çift) katmanı ve artan bekleme', () => {
  it('5 hata -> 15 dk; süre dolunca 5 hata -> 30 dk; sonra 60 dk; üst sınır 2 sa; 24 sa hatasız -> seviye sıfır', () => {
    const { guard, advance, events } = newGuard();
    const attempt = attemptFor('u:42', '203.0.113.1');
    const lockOnce = () => {
      let result;
      for (let i = 0; i < 5; i += 1) {
        result = guard.recordFailure(attempt);
      }
      return result;
    };

    for (let i = 0; i < 4; i += 1) {
      assert.equal(guard.recordFailure(attempt).locked, false);
    }
    const first = guard.recordFailure(attempt);
    assert.equal(first.locked, true);
    assert.equal(first.retryAfterSeconds, 15 * 60);
    assert.equal(first.scope, 'pair');
    assert.equal(guard.check(attempt).locked, true);
    assert.equal(events.at(-1).scope, 'pair');

    advance(15 * MIN + 1);
    assert.equal(guard.check(attempt).locked, false);
    assert.equal(lockOnce().retryAfterSeconds, 30 * 60, 'ikinci kilit iki kat');
    advance(30 * MIN + 1);
    assert.equal(lockOnce().retryAfterSeconds, 60 * 60);
    advance(60 * MIN + 1);
    assert.equal(lockOnce().retryAfterSeconds, 120 * 60);
    advance(120 * MIN + 1);
    assert.equal(lockOnce().retryAfterSeconds, 120 * 60, 'üst sınır 2 saat');

    advance(25 * 60 * MIN);
    assert.equal(lockOnce().retryAfterSeconds, 15 * 60, '24 saat hatasız: seviye sıfırlanır');
  });

  it('başarılı giriş yalnızca kendi çiftini sıfırlar', () => {
    const { guard } = newGuard();
    const attempt = attemptFor('u:42', '203.0.113.1');
    for (let i = 0; i < 4; i += 1) guard.recordFailure(attempt);
    guard.recordSuccess(attempt);
    for (let i = 0; i < 4; i += 1) {
      assert.equal(guard.recordFailure(attempt).locked, false, 'sayaç sıfırlandı');
    }
  });
});

describe('login_guard: hizmet reddi direnci (saldırgan başkasını kilitleyemez)', () => {
  it('saldırganın IP A’dan 5 hatası kurbanın IP B’sini kilitlemez', () => {
    const { guard } = newGuard();
    for (let i = 0; i < 5; i += 1) guard.recordFailure(attemptFor('u:42', '203.0.113.66'));
    assert.equal(guard.check(attemptFor('u:42', '203.0.113.66')).locked, true);
    assert.equal(guard.check(attemptFor('u:42', '198.51.100.7')).locked, false, 'kurbanın kaynağı serbest');
  });

  it('dağıtık saldırı (20 farklı IP) hesabı güvenilmeyen istemcilere kilitler; güvenilir cihaz MUAF', () => {
    const { guard, events } = newGuard();
    for (let i = 1; i <= 20; i += 1) {
      guard.recordFailure(attemptFor('u:42', `203.0.113.${i}`));
    }
    assert.equal(events.some((event) => event.scope === 'account'), true);
    const fresh = guard.check(attemptFor('u:42', '198.51.100.7'));
    assert.equal(fresh.locked, true);
    assert.equal(fresh.scope, 'account');

    const trusted = { accountKey: 'u:42', sourceKey: 'd:cihaz-1234567890abcdef', ipKey: 'ip:198.51.100.7', trusted: true };
    assert.equal(guard.check(trusted).locked, false, 'kayıtlı cihaz hesap kilidinden etkilenmez');
  });

  it('kilit sonrası hesap geneli: her 5 hatada yeni (iki kat) kilit', () => {
    const { guard, advance } = newGuard();
    for (let i = 1; i <= 20; i += 1) guard.recordFailure(attemptFor('u:7', `203.0.113.${i}`));
    advance(15 * MIN + 1);
    let last;
    for (let i = 21; i <= 25; i += 1) last = guard.recordFailure(attemptFor('u:7', `203.0.113.${i}`));
    assert.equal(last.locked, true);
    assert.equal(last.scope, 'account');
    assert.equal(last.retryAfterSeconds, 30 * 60);
  });

  it('parola püskürtme: tek IP’den 30 farklı hesaba hata -> IP kilidi; başka IP ve güvenilir cihaz etkilenmez', () => {
    const { guard } = newGuard();
    for (let i = 1; i <= 30; i += 1) guard.recordFailure(attemptFor(`i:kisi${i}@example.com`, '203.0.113.9'));
    const blocked = guard.check(attemptFor('u:99', '203.0.113.9'));
    assert.equal(blocked.locked, true);
    assert.equal(blocked.scope, 'source');
    assert.equal(guard.check(attemptFor('u:99', '198.51.100.1')).locked, false);
    const trusted = { accountKey: 'u:99', sourceKey: 'd:cihaz-abcdefghijklmnop', ipKey: 'ip:203.0.113.9', trusted: true };
    assert.equal(guard.check(trusted).locked, false, 'aynı (CGNAT) IP’deki kayıtlı cihaz girebilir');
  });

  it('clearAccount yalnızca o hesabın çift + hesap kilitlerini açar; IP kilidi ve başka hesap kalır', () => {
    const { guard } = newGuard();
    for (let i = 1; i <= 20; i += 1) guard.recordFailure(attemptFor('u:42', `203.0.113.${i}`));
    for (let i = 0; i < 5; i += 1) guard.recordFailure(attemptFor('u:43', '203.0.113.200'));
    guard.clearAccount('u:42');
    assert.equal(guard.check(attemptFor('u:42', '203.0.113.1')).locked, false);
    assert.equal(guard.check(attemptFor('u:43', '203.0.113.200')).locked, true);
  });
});

describe('login_guard: anahtarlar ve bellek', () => {
  it('hesap anahtarı: var olan hesapta user_code, yoksa küçük harfli tanımlayıcı', () => {
    assert.equal(loginAccountKey({ userCode: 42, identifier: 'X@Y.com' }), 'u:42');
    assert.equal(loginAccountKey({ userCode: undefined, identifier: ' X@Y.com ' }), 'i:x@y.com');
  });

  it('buildLoginAttempt: cihaz belirteci yalnızca aynı hesap + GÜNCEL parola sürümüyle eşleşirse güvenilir; IPv6 /64 kovası', () => {
    const req = { ip: '2001:db8:1:2:aaaa:bbbb:cccc:dddd' };
    const device = { userCode: 42, deviceId: 'abcdefghijklmnopqrstuvwx', pv: passwordVersionOf(PASSWORD_HASH) };
    const own = buildLoginAttempt({ req, identifier: 'a@example.com', userCode: 42, device, passwordHash: PASSWORD_HASH });
    assert.equal(own.trusted, true);
    assert.equal(own.sourceKey, 'd:abcdefghijklmnopqrstuvwx');
    assert.equal(own.ipKey, 'ip:2001:db8:1:2::/64');
    const other = buildLoginAttempt({ req, identifier: 'b@example.com', userCode: 43, device, passwordHash: PASSWORD_HASH });
    assert.equal(other.trusted, false);
    assert.equal(other.sourceKey, 'ip:2001:db8:1:2::/64');
    const unknown = buildLoginAttempt({ req, identifier: 'yok@example.com', userCode: undefined, device });
    assert.equal(unknown.trusted, false);
    const passwordChanged = buildLoginAttempt({ req, identifier: 'a@example.com', userCode: 42, device, passwordHash: OTHER_PASSWORD_HASH });
    assert.equal(passwordChanged.trusted, false, 'parola değişince / sıfırlanınca eski belirteç muafiyet sağlamaz');
    const noPv = buildLoginAttempt({ req, identifier: 'a@example.com', userCode: 42, device: { ...device, pv: undefined }, passwordHash: PASSWORD_HASH });
    assert.equal(noPv.trusted, false);
  });

  it('istemci IP’si çözülemediyse (Cloudflare kenarı / bilinmiyor) IP geneli katman uygulanmaz (ortak kilit yok)', () => {
    const originalWarn = console.warn;
    console.warn = () => {};
    try {
      const cf = buildLoginAttempt({ req: { ip: '173.245.48.10' }, identifier: 'x@example.com', userCode: undefined, device: null });
      assert.equal(cf.ipKey, null);
      assert.equal(cf.sourceKey, 'ip:173.245.48.10', 'çift katmanı yine kaynakla anahtarlanır');
      const unknown = buildLoginAttempt({ req: {}, identifier: 'x@example.com', userCode: undefined, device: null });
      assert.equal(unknown.ipKey, null);
      // nginx X-Forwarded-For iletmiyorsa herkes 127.0.0.1 görünür: IP geneli kilit herkesi kilitlerdi.
      for (const ip of ['127.0.0.1', '::1', '10.1.2.3', '192.168.1.5', '::ffff:127.0.0.1']) {
        assert.equal(buildLoginAttempt({ req: { ip }, identifier: 'x@example.com', device: null }).ipKey, null, ip);
      }
      assert.equal(buildLoginAttempt({ req: { ip: '198.51.100.7' }, identifier: 'x@example.com', device: null }).ipKey, 'ip:198.51.100.7');
    } finally {
      console.warn = originalWarn;
    }

    const { guard } = newGuard();
    for (let i = 1; i <= 40; i += 1) {
      guard.recordFailure({ accountKey: `i:kisi${i}@example.com`, sourceKey: 'ip:173.245.48.10', ipKey: null, trusted: false });
    }
    const other = { accountKey: 'u:5', sourceKey: 'ip:173.245.48.10', ipKey: null, trusted: false };
    assert.equal(guard.check(other).locked, false, 'aynı Cloudflare kenarındaki başka kullanıcı kilitlenmez');
  });

  it('sayaç doluyken kilitli kayıtlar önce atılmaz (anahtar şişirerek kilit sildirilemez)', () => {
    const counter = createEscalatingCounter({ ...LOGIN_GUARD_DEFAULTS.pair, maxKeys: 3 });
    const at = 5_000_000;
    for (let i = 0; i < 5; i += 1) counter.fail('kurban', at);
    assert.equal(counter.check('kurban', at).locked, true);
    for (let i = 0; i < 50; i += 1) counter.fail(`sisirme-${i}`, at + 1);
    assert.ok(counter.size() <= 3);
    assert.equal(counter.check('kurban', at + 2).locked, true);
  });

  it('sweep: süresi dolmuş ve seviyesi sönmüş kayıtlar silinir', () => {
    const { guard, advance } = newGuard();
    guard.recordFailure(attemptFor('u:1', '203.0.113.1'));
    assert.equal(guard.size(), 1);
    advance(2 * 60 * MIN);
    guard.sweep();
    assert.equal(guard.size(), 0);
  });
});

describe('login_guard: rezervasyon (yarış güvenliği) ve iade', () => {
  // Rota akışının birebir benzeri: DB gecikmesi (await) -> reserve (eşzamanlı) -> bcrypt (await) -> sonuç.
  async function simulate(guard, attempts, { correct = () => false } = {}) {
    let compares = 0;
    const outcomes = await Promise.all(
      attempts.map(async (attempt, index) => {
        await Promise.resolve();
        const reservation = guard.reserve(attempt);
        if (reservation.blocked) {
          return 'blocked';
        }
        compares += 1;
        await new Promise((resolve) => setTimeout(resolve, 2));
        if (correct(index)) {
          guard.recordSuccess(attempt, reservation);
          return 'ok';
        }
        guard.commitFailure(reservation);
        return reservation.locked ? 'locked' : 'wrong';
      }),
    );
    return { compares, outcomes };
  }

  it('A (çift): 12 paralel yanlış deneme -> en çok 5 karşılaştırma', async () => {
    const { guard } = newGuard();
    const { compares, outcomes } = await simulate(guard, Array.from({ length: 12 }, () => attemptFor('u:1', '203.0.113.5')));
    assert.equal(compares, 5);
    assert.equal(outcomes.filter((outcome) => outcome === 'blocked').length, 7);
  });

  it('B (hesap): 40 farklı IP’den paralel -> en çok 20 karşılaştırma', async () => {
    const { guard } = newGuard();
    const { compares } = await simulate(guard, Array.from({ length: 40 }, (_, i) => attemptFor('u:2', `203.0.113.${i + 1}`)));
    assert.equal(compares, 20);
  });

  it('C (IP): tek IP’den 50 farklı hesaba paralel -> en çok 30 karşılaştırma', async () => {
    const { guard } = newGuard();
    const { compares } = await simulate(guard, Array.from({ length: 50 }, (_, i) => attemptFor(`i:k${i}@example.com`, '203.0.113.200')));
    assert.equal(compares, 30);
  });

  it('iade: eşiği dolduran rezervasyon doğru parolaysa koyduğu kilitler (hesap + IP) geri alınır', () => {
    const { guard } = newGuard();
    for (let i = 1; i <= 19; i += 1) guard.recordFailure(attemptFor('u:3', `203.0.113.${i}`));
    for (let i = 1; i <= 29; i += 1) guard.recordFailure(attemptFor(`i:x${i}@example.com`, '198.51.100.50'));
    const attempt = attemptFor('u:3', '198.51.100.50');
    const reservation = guard.reserve(attempt);
    assert.equal(reservation.blocked, false);
    assert.equal(reservation.locked, true, '20. hesap hatası ve 30. IP hatası rezervasyonla kilitlenir');
    guard.recordSuccess(attempt, reservation);
    assert.equal(guard.check(attemptFor('u:3', '198.51.100.51')).locked, false, 'hesap kilidi geri alındı');
    assert.equal(guard.check(attemptFor('u:4', '198.51.100.50')).locked, false, 'IP kilidi geri alındı');
    assert.equal(guard.recordFailure(attemptFor('u:3', '203.0.113.99')).locked, true, 'sayaç 19’da kalmıştı: bir sonraki hata kilitler');
  });

  it('iade başkasının koyduğu kilidi açmaz; kilitliyken rezervasyon sayılmaz', () => {
    const { guard } = newGuard();
    for (let i = 1; i <= 18; i += 1) guard.recordFailure(attemptFor('u:5', `203.0.113.${i}`));
    const mine = attemptFor('u:5', '198.51.100.1');
    const reservation = guard.reserve(mine); // 19
    guard.recordFailure(attemptFor('u:5', '203.0.113.100')); // 20 -> başkası kilitledi
    guard.recordSuccess(mine, reservation);
    assert.equal(guard.check(attemptFor('u:5', '198.51.100.2')).locked, true);
    const blocked = guard.reserve(attemptFor('u:5', '198.51.100.3'));
    assert.equal(blocked.blocked, true);
    assert.deepEqual(blocked.items, []);
  });

  it('commitFailure kilit olayını yalnız yanlış parola kesinleşince günlüğe yazar', () => {
    const { guard, events } = newGuard();
    const attempt = attemptFor('u:6', '203.0.113.7');
    for (let i = 0; i < 4; i += 1) guard.recordFailure(attempt);
    const reservation = guard.reserve(attempt);
    assert.equal(reservation.locked, true);
    assert.equal(events.length, 0, 'henüz sonuç belli değil');
    guard.recordSuccess(attempt, reservation);
    assert.equal(events.length, 0, 'doğru parola: kilit olayı yok');
    for (let i = 0; i < 4; i += 1) guard.recordFailure(attempt);
    guard.commitFailure(guard.reserve(attempt));
    assert.equal(events.some((event) => event.scope === 'pair'), true);
  });
});

describe('login_guard: geçici kilit (R7#1) ve dolu harita maliyeti (R7#6)', () => {
  const layerCases = [
    ['pair (4 hata)', (g) => { for (let i = 0; i < 4; i += 1) g.recordFailure(attemptFor('u:7', '203.0.113.7')); }, attemptFor('u:7', '203.0.113.7'), attemptFor('u:7', '203.0.113.7')],
    ['account (19 dağıtık hata)', (g) => { for (let i = 1; i <= 19; i += 1) g.recordFailure(attemptFor('u:8', `203.0.113.${i}`)); }, attemptFor('u:8', '198.51.100.1'), attemptFor('u:8', '198.51.100.2')],
    ['source (29 hesap, aynı IP)', (g) => { for (let i = 1; i <= 29; i += 1) g.recordFailure(attemptFor(`i:z${i}@example.com`, '198.51.100.77')); }, attemptFor('u:9', '198.51.100.77'), attemptFor('u:10', '198.51.100.77')],
  ];

  for (const [name, prime, mine, other] of layerCases) {
    it(`${name}: eşik−1’de DOĞRU giriş rezervasyonu -> eşzamanlı isteğe kısa (≤2 sn) Retry-After; iade sonrası kilit yok`, () => {
      const { guard } = newGuard();
      prime(guard);
      const reservation = guard.reserve(mine);
      assert.equal(reservation.blocked, false);
      assert.equal(reservation.locked, true);
      const concurrent = guard.reserve(other);
      assert.equal(concurrent.blocked, true);
      assert.ok(concurrent.retryAfterSeconds >= 1 && concurrent.retryAfterSeconds <= PROVISIONAL_RETRY_AFTER_SECONDS, String(concurrent.retryAfterSeconds));
      assert.equal(guard.check(other).retryAfterSeconds <= PROVISIONAL_RETRY_AFTER_SECONDS, true);
      guard.recordSuccess(mine, reservation);
      assert.equal(guard.check(other).locked, false);
    });

    it(`${name}: eşik−1’de YANLIŞ parola -> kendi yanıtı ve sonraki istekler GERÇEK süre (900 sn)`, () => {
      const { guard } = newGuard();
      prime(guard);
      const reservation = guard.reserve(mine);
      assert.equal(reservation.retryAfterSeconds, 900, 'rezervasyonu yapanın yanıtı gerçek süre');
      assert.ok(guard.check(other).retryAfterSeconds <= PROVISIONAL_RETRY_AFTER_SECONDS, 'sonuç belli olana dek kısa');
      guard.commitFailure(reservation);
      assert.equal(guard.check(other).retryAfterSeconds, 900);
    });
  }

  it('sonucu hiç gelmeyen geçici kilit 10 sn sonra gerçek kilit sayılır (istek düştü)', () => {
    const { guard, advance } = newGuard();
    for (let i = 0; i < 4; i += 1) guard.recordFailure(attemptFor('u:11', '203.0.113.11'));
    guard.reserve(attemptFor('u:11', '203.0.113.11'));
    assert.equal(guard.check(attemptFor('u:11', '203.0.113.11')).retryAfterSeconds, PROVISIONAL_RETRY_AFTER_SECONDS);
    advance(11 * 1000);
    assert.equal(guard.check(attemptFor('u:11', '203.0.113.11')).retryAfterSeconds, 900 - 11);
  });

  it('dolu harita: tam süpürme her eklemede DEĞİL, en çok 30 sn’de bir; boyut sınırı ve kilitler korunur', () => {
    const counter = createEscalatingCounter({ ...LOGIN_GUARD_DEFAULTS.source, maxKeys: 5000 });
    const at = 7_000_000;
    for (let i = 0; i < 30; i += 1) counter.fail('kilitli-kaynak', at);
    assert.equal(counter.check('kilitli-kaynak', at).locked, true);
    for (let i = 0; i < 5000; i += 1) counter.fail(`k${i}`, at + 1);
    const before = counter.stats().fullSweepsOnInsert;
    const started = process.hrtime.bigint();
    for (let i = 0; i < 2000; i += 1) counter.fail(`yeni${i}`, at + 2);
    const perInsertMs = Number(process.hrtime.bigint() - started) / 1e6 / 2000;
    assert.equal(counter.stats().fullSweepsOnInsert - before, 0, 'aynı 30 sn içinde yeni tam süpürme yok');
    assert.ok(counter.size() <= 5000);
    assert.equal(counter.check('kilitli-kaynak', at + 3).locked, true, 'kilit tahliye edilmedi');
    assert.ok(perInsertMs < 0.5, `ekleme başı ${perInsertMs.toFixed(4)} ms`);
    counter.fail('sonra', at + 31_000);
    assert.equal(counter.stats().fullSweepsOnInsert - before, 1, '30 sn sonra bir tam süpürme');
  });
});

describe('login_device_token', () => {
  const env = { JWT_SECRET: SECRET };

  it('imzalı, hesaba ve parola sürümüne bağlı, süreli; kurcalanırsa / başka sırla / süresi dolunca geçersiz', async () => {
    const now = Date.UTC(2026, 9, 16);
    assert.equal(issueDeviceToken({ userCode: 42 }, { env, nowMs: now }), null, 'parola özeti yoksa belirteç verilmez');
    const token = issueDeviceToken({ userCode: 42, passwordHash: PASSWORD_HASH }, { env, nowMs: now });
    const verified = verifyDeviceToken(token, { env, nowMs: now + 1000 });
    assert.equal(verified.userCode, 42);
    assert.match(verified.deviceId, /^[A-Za-z0-9_-]{16,64}$/);
    assert.equal(verified.pv, passwordVersionOf(PASSWORD_HASH));
    assert.equal(deviceTokenMatchesPassword(verified, PASSWORD_HASH), true);
    assert.equal(deviceTokenMatchesPassword(verified, OTHER_PASSWORD_HASH), false, 'parola değişti');
    assert.equal(deviceTokenMatchesPassword(verified, null), false);

    // pv alanı olmayan (eski biçim) belirteç imzası doğru olsa bile kabul edilmez.
    const [, rawBody] = token.split('.');
    const payloadNoPv = { ...JSON.parse(Buffer.from(rawBody, 'base64url')) };
    delete payloadNoPv.p;
    const crypto = await import('node:crypto');
    const key = crypto.createHmac('sha256', SECRET).update('kapi-login-device-token/v1').digest();
    const bodyNoPv = Buffer.from(JSON.stringify(payloadNoPv)).toString('base64url');
    const sigNoPv = crypto.createHmac('sha256', key).update(`ldt1.${bodyNoPv}`).digest('base64url');
    assert.equal(verifyDeviceToken(`ldt1.${bodyNoPv}.${sigNoPv}`, { env, nowMs: now }), null);

    const [prefix, body, sig] = token.split('.');
    const forgedBody = Buffer.from(JSON.stringify({ ...JSON.parse(Buffer.from(body, 'base64url')), u: 1 })).toString('base64url');
    assert.equal(verifyDeviceToken(`${prefix}.${forgedBody}.${sig}`, { env, nowMs: now }), null);
    assert.equal(verifyDeviceToken(token, { env: { JWT_SECRET: OTHER_SECRET }, nowMs: now }), null);
    assert.equal(verifyDeviceToken(token, { env, nowMs: now + (DEVICE_TOKEN_TTL_SECONDS + 1) * 1000 }), null);
    assert.equal(verifyDeviceToken('ldt1.x.y', { env, nowMs: now }), null);
    assert.equal(verifyDeviceToken('x'.repeat(600), { env, nowMs: now }), null);
    assert.equal(verifyDeviceToken(undefined, { env, nowMs: now }), null);
  });

  it('sır döndürme: eski sırla verilen belirteç yalnızca JWT_SECRET_PREVIOUS_UNTIL öncesinde geçerli', () => {
    const now = Date.UTC(2026, 9, 16);
    const old = issueDeviceToken(
      { userCode: 42, deviceId: 'abcdefghijklmnopqrstuvwx', passwordHash: PASSWORD_HASH },
      { env: { JWT_SECRET: OTHER_SECRET }, nowMs: now },
    );
    const rotated = {
      JWT_SECRET: SECRET,
      JWT_SECRET_PREVIOUS: OTHER_SECRET,
      JWT_SECRET_PREVIOUS_UNTIL: new Date(now + 10 * 24 * 3600 * 1000).toISOString(),
    };
    assert.equal(verifyDeviceToken(old, { env: rotated, nowMs: now + 1000 })?.deviceId, 'abcdefghijklmnopqrstuvwx');
    assert.equal(verifyDeviceToken(old, { env: rotated, nowMs: now + 11 * 24 * 3600 * 1000 }), null);
  });
});

// ------------------------------------------------------------------------------------------- HTTP
describe('POST /auth/login (HTTP): tek tip yanıt, kaynak ayrımı, güvenilir cihaz', () => {
  let server;
  let baseUrl;
  const saved = {};
  const originalConsoleError = console.error;
  const originalConsoleWarn = console.warn;

  const users = new Map([
    ['ali@example.com', { id: 42, full_name: 'Ali Test', email: 'ali@example.com', login_name: 'ali.k' }],
    ['veli@example.com', { id: 43, full_name: 'Veli Test', email: 'veli@example.com', login_name: null }],
  ]);
  const rowFor = (ident) => {
    for (const user of users.values()) {
      if (user.email === ident || user.login_name === ident) {
        return {
          ...user,
          role: 'individual',
          is_active: true,
          email_verified: true,
          approval_status: 'approved',
          phone_number: null,
          created_at: new Date('2026-01-01T00:00:00Z'),
          password_hash: PASSWORD_HASH,
        };
      }
    }
    return null;
  };

  before(async () => {
    const app = express();
    app.set('env', 'test');
    app.set('trust proxy', resolveTrustProxy({}).value); // "loopback": test istemcisi 127.0.0.1 -> X-Forwarded-For geçerli
    app.use(express.json({ limit: '1mb' }));
    app.use(authRouter);
    app.use(createErrorHandler({ logger: { error: () => {}, log: () => {}, warn: () => {} } }));
    await new Promise((resolve) => {
      server = app.listen(0, '127.0.0.1', resolve);
    });
    baseUrl = `http://127.0.0.1:${server.address().port}`;
  });

  after(() => new Promise((resolve) => {
    delete pool.query;
    server.closeAllConnections?.();
    server.close(resolve);
  }));

  beforeEach(() => {
    for (const name of ['JWT_SECRET', 'JWT_EXPIRES_IN', 'JWT_SECRET_PREVIOUS', 'JWT_SECRET_PREVIOUS_UNTIL', 'NODE_ENV']) {
      saved[name] = process.env[name];
      delete process.env[name];
    }
    process.env.JWT_SECRET = SECRET;
    pool.query = async (text, params) => {
      const sql = String(text);
      if (sql.includes('LOWER(login_name)')) {
        const row = rowFor(String(params[0]).toLowerCase());
        return row ? { rows: [row], rowCount: 1 } : { rows: [], rowCount: 0 };
      }
      return { rows: [], rowCount: 0 };
    };
    console.error = () => {};
    console.warn = () => {};
    loginRateLimiter.reset();
    loginFailureTracker.reset();
  });

  afterEach(() => {
    delete pool.query;
    console.error = originalConsoleError;
    console.warn = originalConsoleWarn;
    for (const [name, value] of Object.entries(saved)) {
      if (value === undefined) delete process.env[name];
      else process.env[name] = value;
    }
  });

  const login = (body, { ip = '198.51.100.10', headers = {} } = {}) =>
    fetch(`${baseUrl}/auth/login`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'X-Forwarded-For': ip, ...headers },
      body: JSON.stringify(body),
    });

  it('başarılı giriş: asgari claim (sub, pv, iat, exp; e-posta/rol YOK) + device_token', async () => {
    const response = await login({ email: 'ALI@example.com', password: PASSWORD });
    assert.equal(response.status, 200);
    const body = await response.json();
    const claims = jwt.decode(body.token);
    assert.deepEqual(Object.keys(claims).sort(), ['exp', 'iat', 'pv', 'sub']);
    assert.equal(claims.sub, '42');
    assert.equal(typeof body.device_token, 'string');
    assert.equal(verifyDeviceToken(body.device_token).userCode, 42);
  });

  it('var olan ve olmayan hesap: 401 ve 5. hatadaki 429 yanıtları AYNI (kullanıcı varlığı sızmaz)', async () => {
    const run = async (email, ip) => {
      const statuses = [];
      let lastBody;
      for (let i = 0; i < 5; i += 1) {
        const response = await login({ email, password: `yanlis-${i}` }, { ip });
        statuses.push(response.status);
        lastBody = await response.json();
      }
      return { statuses, lastBody };
    };
    const existing = await run('ali@example.com', '203.0.113.11');
    const missing = await run('hic-yok@example.com', '203.0.113.12');
    assert.deepEqual(existing.statuses, [401, 401, 401, 401, 429]);
    assert.deepEqual(missing.statuses, existing.statuses);
    assert.deepEqual(missing.lastBody, existing.lastBody);
    assert.equal(existing.lastBody.code, 'LOGIN_LOCKED');
    assert.equal(/ali@example\.com|hic-yok/.test(JSON.stringify(existing.lastBody)), false);
  });

  it('e-posta ve kullanıcı adı AYNI hesap bütçesini paylaşır (iki tanımlayıcıyla 2 kat deneme yok)', async () => {
    for (let i = 0; i < 3; i += 1) await login({ email: 'ali@example.com', password: 'yanlis' }, { ip: '203.0.113.20' });
    const fourth = await login({ login: 'ali.k', password: 'yanlis' }, { ip: '203.0.113.20' });
    assert.equal(fourth.status, 401);
    const fifth = await login({ login: 'ali.k', password: 'yanlis' }, { ip: '203.0.113.20' });
    assert.equal(fifth.status, 429);
  });

  it('saldırganın IP’si kilitlenir, kurbanın IP’si doğru parolayla girer (hizmet reddi yok)', async () => {
    for (let i = 0; i < 5; i += 1) await login({ email: 'ali@example.com', password: 'yanlis' }, { ip: '203.0.113.66' });
    assert.equal((await login({ email: 'ali@example.com', password: PASSWORD }, { ip: '203.0.113.66' })).status, 429);
    assert.equal((await login({ email: 'ali@example.com', password: PASSWORD }, { ip: '198.51.100.7' })).status, 200);
  });

  it('dağıtık saldırı hesabı kilitler; kayıtlı cihaz belirteciyle sahibi yine girer; başka hesabın belirteci işe yaramaz', async () => {
    const own = await (await login({ email: 'ali@example.com', password: PASSWORD }, { ip: '198.51.100.7' })).json();
    const foreign = await (await login({ email: 'veli@example.com', password: PASSWORD }, { ip: '198.51.100.8' })).json();

    for (let i = 1; i <= 20; i += 1) {
      await login({ email: 'ali@example.com', password: 'yanlis' }, { ip: `203.0.113.${100 + i}` });
    }
    const untrusted = await login({ email: 'ali@example.com', password: PASSWORD }, { ip: '198.51.100.9' });
    assert.equal(untrusted.status, 429, 'belirteçsiz yeni kaynak: hesap geneli kilit');

    const viaBody = await login({ email: 'ali@example.com', password: PASSWORD, device_token: own.device_token }, { ip: '198.51.100.9' });
    assert.equal(viaBody.status, 200, 'kayıtlı cihaz (gövde) muaf');
    const viaHeader = await login(
      { email: 'ali@example.com', password: PASSWORD },
      { ip: '198.51.100.9', headers: { 'X-Device-Token': own.device_token } },
    );
    assert.equal(viaHeader.status, 200, 'kayıtlı cihaz (başlık) muaf');
    const renewed = await viaHeader.json();
    assert.equal(verifyDeviceToken(renewed.device_token).deviceId, verifyDeviceToken(own.device_token).deviceId, 'cihaz kimliği korunur');

    const wrongDevice = await login({ email: 'ali@example.com', password: PASSWORD, device_token: foreign.device_token }, { ip: '198.51.100.9' });
    assert.equal(wrongDevice.status, 429, 'başka hesabın belirteci muafiyet sağlamaz');

    const trustedWrongPassword = await login({ email: 'ali@example.com', password: 'yanlis', device_token: own.device_token }, { ip: '198.51.100.9' });
    assert.equal(trustedWrongPassword.status, 401, 'belirteç parola yerine geçmez');
  });

  it('parola sıfırlama (clearAccountLocks) hesap geneli kilidi açar', async () => {
    for (let i = 1; i <= 20; i += 1) {
      await login({ email: 'ali@example.com', password: 'yanlis' }, { ip: `203.0.113.${150 + i}` });
    }
    assert.equal((await login({ email: 'ali@example.com', password: PASSWORD }, { ip: '198.51.100.30' })).status, 429);
    clearAccountLocks({ email: 'ali@example.com', loginName: 'ali.k', userCode: 42 });
    assert.equal((await login({ email: 'ali@example.com', password: PASSWORD }, { ip: '198.51.100.30' })).status, 200);
  });

  it('kilit yanıtı: Retry-After + retry_after_seconds + dakika bilgisi; LOGIN_LOCKED', async () => {
    let last;
    for (let i = 0; i < 5; i += 1) last = await login({ email: 'veli@example.com', password: 'yanlis' }, { ip: '203.0.113.77' });
    assert.equal(last.status, 429);
    assert.equal(last.headers.get('retry-after'), '900');
    const body = await last.json();
    assert.equal(body.retry_after_seconds, 900);
    assert.match(body.error, /15 dakika/);
  });

  it('eski uyumlu arayüz (loginFailureTracker) ve guard aynı durumu paylaşır', () => {
    for (let i = 0; i < 5; i += 1) loginFailureTracker.recordFailure('z@example.com');
    assert.equal(loginFailureTracker.check('z@example.com').locked, true);
    assert.equal(loginGuard.size(), 1);
    loginFailureTracker.reset();
    assert.equal(loginGuard.size(), 0);
  });

  // --- R1 B2: yarış güvenliği (bcrypt'ten ÖNCE rezervasyon) ---
  function spyCompare() {
    const original = bcrypt.compare;
    const hashes = [];
    bcrypt.compare = (plain, hash, ...rest) => {
      hashes.push(hash);
      return original.call(bcrypt, plain, hash, ...rest);
    };
    return { hashes, restore: () => { bcrypt.compare = original; } };
  }

  it('12 PARALEL yanlış deneme (aynı hesap + IP): en çok 5 bcrypt karşılaştırması; 4×401 + 8×429', async () => {
    const spy = spyCompare();
    try {
      const responses = await Promise.all(
        Array.from({ length: 12 }, (_, i) => login({ email: 'ali@example.com', password: `yanlis-${i}` }, { ip: '203.0.113.240' })),
      );
      const statuses = responses.map((response) => response.status).sort();
      assert.ok(spy.hashes.length <= 5, `karşılaştırma sayısı ${spy.hashes.length}`);
      assert.deepEqual(statuses, [401, 401, 401, 401, 429, 429, 429, 429, 429, 429, 429, 429]);
    } finally {
      spy.restore();
    }
  });

  it('hesap geneli katman da paralelde aşılmaz: 30 farklı IP’den aynı anda 30 yanlış deneme -> en çok 20 karşılaştırma', async () => {
    const spy = spyCompare();
    try {
      await Promise.all(
        Array.from({ length: 30 }, (_, i) => login({ email: 'veli@example.com', password: 'yanlis' }, { ip: `198.51.100.${100 + i}` })),
      );
      assert.ok(spy.hashes.length <= 20, `karşılaştırma sayısı ${spy.hashes.length}`);
    } finally {
      spy.restore();
    }
  });

  it('doğru parola rezervasyonu iade eder: 19 dağıtık hata + doğru giriş -> hesap kilidi YOK; sonraki tek hata kilitler', async () => {
    for (let i = 1; i <= 19; i += 1) {
      await login({ email: 'ali@example.com', password: 'yanlis' }, { ip: `198.51.100.${10 + i}` });
    }
    assert.equal((await login({ email: 'ali@example.com', password: PASSWORD }, { ip: '198.51.100.60' })).status, 200);
    assert.equal((await login({ email: 'ali@example.com', password: PASSWORD }, { ip: '198.51.100.61' })).status, 200, 'iade: sayaç 19’da');
    assert.equal((await login({ email: 'ali@example.com', password: 'yanlis' }, { ip: '198.51.100.62' })).status, 429, '20. hata kilitler');
  });

  // --- R7#1: eşik−1'de doğru parolalı giriş başkasına uzun (900 sn) 429 döndürmez ---
  it('HTTP: 4 hatadan sonra aynı anda iki DOĞRU giriş -> biri 200, diğeri kısa (≤2 sn) 429; sonra kilit yok', async () => {
    for (let i = 0; i < 4; i += 1) {
      await login({ email: 'ali@example.com', password: 'yanlis' }, { ip: '198.51.100.140' });
    }
    const original = bcrypt.compare;
    bcrypt.compare = async (...args) => {
      await new Promise((resolve) => setTimeout(resolve, 150)); // bcrypt penceresini genişlet
      return original.apply(bcrypt, args);
    };
    let responses;
    try {
      responses = await Promise.all([
        login({ email: 'ali@example.com', password: PASSWORD }, { ip: '198.51.100.140' }),
        login({ email: 'ali@example.com', password: PASSWORD }, { ip: '198.51.100.140' }),
      ]);
    } finally {
      bcrypt.compare = original;
    }
    const statuses = responses.map((response) => response.status).sort();
    assert.deepEqual(statuses, [200, 429]);
    const blocked = responses.find((response) => response.status === 429);
    assert.ok(Number(blocked.headers.get('retry-after')) <= PROVISIONAL_RETRY_AFTER_SECONDS);
    const body = await blocked.json();
    assert.equal(body.code, 'LOGIN_LOCKED');
    assert.match(body.error, /saniye/);
    assert.equal((await login({ email: 'ali@example.com', password: PASSWORD }, { ip: '198.51.100.140' })).status, 200, 'kilit kalkmış');
  });

  it('HTTP: yanlış parola kilit koyarsa yanıtı ve sonrası gerçek 900 sn', async () => {
    let last;
    for (let i = 0; i < 5; i += 1) last = await login({ email: 'ali@example.com', password: 'yanlis' }, { ip: '198.51.100.141' });
    assert.equal(last.headers.get('retry-after'), '900');
    const after = await login({ email: 'ali@example.com', password: PASSWORD }, { ip: '198.51.100.141' });
    assert.equal(after.headers.get('retry-after') !== null && Number(after.headers.get('retry-after')) > 800, true);
  });

  // --- R7#4: sahte özet ve yeni özetler aynı maliyette (BCRYPT_COST) ---
  it('olmayan hesapta sahte özetin maliyeti BCRYPT_COST (var olan hesapların yeni özetleriyle aynı)', async () => {
    const spy = spyCompare();
    try {
      await login({ email: 'hic-yok@example.com', password: 'yanlis-parola' }, { ip: '198.51.100.150' });
      assert.equal(spy.hashes.length, 1);
      assert.equal(bcryptCostOf(spy.hashes[0]), BCRYPT_COST);
    } finally {
      spy.restore();
    }
  });

  // --- R1 B12: biçimsiz (bcrypt olmayan) saklı özet sabit zamanlı yoldan ---
  it('silinmiş hesabın "!<hex>" özeti: karşılaştırma SAHTE bcrypt özetiyle yapılır (hızlı dönüş yok), 401', async () => {
    users.set('deleted-77@deleted.invalid', { id: 77, full_name: 'Silinmiş Kullanıcı', email: 'deleted-77@deleted.invalid', login_name: null });
    const tombstone = `!${'ab'.repeat(48)}`;
    const originalQuery = pool.query;
    pool.query = async (text, params) => {
      const sql = String(text);
      if (sql.includes('LOWER(login_name)') && String(params[0]).toLowerCase() === 'deleted-77@deleted.invalid') {
        return { rows: [{ ...rowFor('deleted-77@deleted.invalid'), is_active: false, password_hash: tombstone }], rowCount: 1 };
      }
      return originalQuery(text, params);
    };
    const spy = spyCompare();
    try {
      const response = await login({ email: 'deleted-77@deleted.invalid', password: 'herhangi-bir-parola' }, { ip: '198.51.100.90' });
      assert.equal(response.status, 401);
      assert.equal(spy.hashes.length, 1);
      assert.notEqual(spy.hashes[0], tombstone);
      assert.equal(isBcryptHash(spy.hashes[0]), true, 'sahte özet gerçek bir bcrypt özeti (aynı maliyet)');
    } finally {
      spy.restore();
      users.delete('deleted-77@deleted.invalid');
    }
    assert.equal(isBcryptHash(tombstone), false);
    assert.equal(isBcryptHash(PASSWORD_HASH), true);
    assert.equal(isBcryptHash(''), false);
    assert.equal(isBcryptHash(undefined), false);
  });

  // --- R1 B7: parola değişince cihaz belirteci muafiyeti düşer ---
  it('parola sıfırlanınca/değişince eski device_token hesap kilidinden muafiyet SAĞLAMAZ; yeni girişte yenisi verilir', async () => {
    const own = await (await login({ email: 'ali@example.com', password: PASSWORD }, { ip: '198.51.100.7' })).json();
    const newPassword = 'Yesil-Kapi-88-Bulut';
    const user = users.get('ali@example.com');
    const originalRowFor = rowFor;
    const originalQuery = pool.query;
    pool.query = async (text, params) => {
      const sql = String(text);
      if (sql.includes('LOWER(login_name)') && ['ali@example.com', 'ali.k'].includes(String(params[0]).toLowerCase())) {
        return { rows: [{ ...originalRowFor('ali@example.com'), password_hash: OTHER_PASSWORD_HASH }], rowCount: 1 };
      }
      return originalQuery(text, params);
    };
    try {
      assert.ok(user);
      for (let i = 1; i <= 20; i += 1) {
        await login({ email: 'ali@example.com', password: 'yanlis' }, { ip: `203.0.113.${60 + i}` });
      }
      const stale = await login({ email: 'ali@example.com', password: newPassword, device_token: own.device_token }, { ip: '198.51.100.9' });
      assert.equal(stale.status, 429, 'eski parola sürümüne bağlı belirteç güvenilir sayılmaz');
    } finally {
      pool.query = originalQuery;
    }
  });
});
