// S-C: JWT sertleştirmesi (asgari claim, exp zorunlu, sır döndürme geçişi, üretimde pv zorunluluğu, ömür üst sınırı).
import { describe, it, beforeEach, afterEach, mock } from 'node:test';
import assert from 'node:assert/strict';
import jwt from 'jsonwebtoken';
import { pool } from '../src/db.js';
import {
  isPasswordVersionValid,
  passwordVersionOf,
  resetJwtSecretWarning,
  signAccessToken,
  verifyAccessToken,
} from '../src/jwt.js';
import {
  DEFAULT_JWT_EXPIRES_SECONDS,
  MAX_JWT_EXPIRES_SECONDS,
  isPasswordVersionRequired,
  parseExpiresInSeconds,
  resolveJwtExpiresSeconds,
  resolvePreviousJwtSecret,
  validateEnv,
} from '../src/config/env.js';
import { authRequired } from '../src/middlewares/auth_middleware.js';

const NEW_SECRET = 'k9Fz-test-only-long-secret-value-0123456789abcdef';
const OLD_SECRET = 'q8Wr-test-short-20ch'; // canlıdaki uzunlukta sahte değer
const HASH = '$2a$10$AAAAAAAAAAAAAAAAAAAAAA';
const ENV_KEYS = ['JWT_SECRET', 'JWT_EXPIRES_IN', 'JWT_SECRET_PREVIOUS', 'JWT_SECRET_PREVIOUS_UNTIL', 'JWT_REQUIRE_PV', 'NODE_ENV'];

const saved = {};
function saveEnv() {
  for (const key of ENV_KEYS) {
    saved[key] = process.env[key];
    delete process.env[key];
  }
}
function restoreEnv() {
  for (const key of ENV_KEYS) {
    if (saved[key] === undefined) delete process.env[key];
    else process.env[key] = saved[key];
  }
}
const inDays = (days) => new Date(Date.now() + days * 24 * 3600 * 1000).toISOString();

describe('JWT: asgari claim ve exp zorunluluğu', () => {
  beforeEach(() => {
    saveEnv();
    process.env.JWT_SECRET = NEW_SECRET;
    resetJwtSecretWarning();
  });
  afterEach(() => {
    restoreEnv();
    mock.restoreAll();
  });

  it('token yalnızca sub + pv + iat + exp taşır (e-posta / rol yazılmaz)', () => {
    const claims = jwt.decode(signAccessToken({ id: 42, email: 'a@example.com', role: 'super_user' }, { passwordHash: HASH }));
    assert.deepEqual(Object.keys(claims).sort(), ['exp', 'iat', 'pv', 'sub']);
    assert.equal(claims.sub, '42');
    assert.equal(claims.pv, passwordVersionOf(HASH));
  });

  it('exp’siz token (imzası doğru olsa bile) reddedilir', () => {
    const noExp = jwt.sign({ sub: '42', pv: passwordVersionOf(HASH) }, NEW_SECRET, { algorithm: 'HS256' });
    assert.throws(() => verifyAccessToken(noExp), (error) => error.name === 'JsonWebTokenError' && /exp/.test(error.message));
  });

  it('HS256 dışı algoritma reddedilir (HS512, none)', () => {
    const hs512 = jwt.sign({ sub: '42' }, NEW_SECRET, { algorithm: 'HS512', expiresIn: '1h' });
    assert.throws(() => verifyAccessToken(hs512), (error) => error.name === 'JsonWebTokenError');
  });
});

describe('JWT ömrü (JWT_EXPIRES_IN)', () => {
  beforeEach(() => {
    saveEnv();
    process.env.JWT_SECRET = NEW_SECRET;
  });
  afterEach(restoreEnv);

  it('parseExpiresInSeconds: yalnız rakam = SANİYE (milisaniye değil), birimler, geçersiz -> null', () => {
    assert.equal(parseExpiresInSeconds('3600'), 3600);
    assert.equal(parseExpiresInSeconds('30d'), 30 * 86400);
    assert.equal(parseExpiresInSeconds('12h'), 43200);
    assert.equal(parseExpiresInSeconds('2 days'), 2 * 86400);
    assert.equal(parseExpiresInSeconds('15m'), 900);
    assert.equal(parseExpiresInSeconds('abc'), null);
    assert.equal(parseExpiresInSeconds(''), null);
  });

  it('varsayılan 30 gün; 365d -> 90 güne kırpılır; geçersiz -> 30 gün; "3600" -> 1 saat', () => {
    assert.equal(resolveJwtExpiresSeconds({}), DEFAULT_JWT_EXPIRES_SECONDS);
    assert.equal(resolveJwtExpiresSeconds({ JWT_EXPIRES_IN: '365d' }), MAX_JWT_EXPIRES_SECONDS);
    assert.equal(resolveJwtExpiresSeconds({ JWT_EXPIRES_IN: 'yanlis' }), DEFAULT_JWT_EXPIRES_SECONDS);
    assert.equal(resolveJwtExpiresSeconds({ JWT_EXPIRES_IN: '0' }), DEFAULT_JWT_EXPIRES_SECONDS);

    process.env.JWT_EXPIRES_IN = '365d';
    const clamped = jwt.decode(signAccessToken({ id: 1 }, { passwordHash: HASH }));
    assert.equal(clamped.exp - clamped.iat, 90 * 86400);

    process.env.JWT_EXPIRES_IN = '3600';
    const hour = jwt.decode(signAccessToken({ id: 1 }, { passwordHash: HASH }));
    assert.equal(hour.exp - hour.iat, 3600, 'eskiden jsonwebtoken "3600"ü 3,6 saniye sayardı');
  });

  it('validateEnv: 365d için kırpma uyarısı, 60d için öneri uyarısı', () => {
    const long = validateEnv({ JWT_SECRET: NEW_SECRET, JWT_EXPIRES_IN: '365d' }).warnings.join('\n');
    assert.match(long, /90 gune kirpilarak/);
    const medium = validateEnv({ JWT_SECRET: NEW_SECRET, JWT_EXPIRES_IN: '60d' }).warnings.join('\n');
    assert.match(medium, /30 gunden uzun/);
  });
});

describe('JWT sır döndürme: JWT_SECRET_PREVIOUS + JWT_SECRET_PREVIOUS_UNTIL', () => {
  beforeEach(() => {
    saveEnv();
    resetJwtSecretWarning();
  });
  afterEach(() => {
    restoreEnv();
    mock.restoreAll();
  });

  function oldToken() {
    process.env.JWT_SECRET = OLD_SECRET;
    mock.method(console, 'warn', () => {});
    const token = signAccessToken({ id: 42 }, { passwordHash: HASH });
    mock.restoreAll();
    return token;
  }

  it('pencere içinde eski sırla imzalı token doğrulanır; YENİ tokenlar yeni sırla imzalanır', () => {
    const token = oldToken();
    process.env.JWT_SECRET = NEW_SECRET;
    process.env.JWT_SECRET_PREVIOUS = OLD_SECRET;
    process.env.JWT_SECRET_PREVIOUS_UNTIL = inDays(14);
    assert.equal(verifyAccessToken(token).sub, '42');
    const fresh = signAccessToken({ id: 42 }, { passwordHash: HASH });
    assert.doesNotThrow(() => jwt.verify(fresh, NEW_SECRET, { algorithms: ['HS256'] }));
    assert.throws(() => jwt.verify(fresh, OLD_SECRET, { algorithms: ['HS256'] }));
  });

  it('UNTIL geçmişse / yoksa / geçersizse eski sır kabul EDİLMEZ (süresiz kabul yok)', () => {
    const token = oldToken();
    process.env.JWT_SECRET = NEW_SECRET;
    process.env.JWT_SECRET_PREVIOUS = OLD_SECRET;
    for (const until of [inDays(-1), undefined, 'yarin']) {
      if (until === undefined) delete process.env.JWT_SECRET_PREVIOUS_UNTIL;
      else process.env.JWT_SECRET_PREVIOUS_UNTIL = until;
      assert.throws(() => verifyAccessToken(token), (error) => error.name === 'JsonWebTokenError', String(until));
    }
  });

  it('eski sırla imzalı ama süresi dolmuş token: TokenExpiredError (pencere süreyi uzatmaz)', () => {
    const expired = jwt.sign({ sub: '42', pv: passwordVersionOf(HASH) }, OLD_SECRET, { algorithm: 'HS256', expiresIn: -10 });
    process.env.JWT_SECRET = NEW_SECRET;
    process.env.JWT_SECRET_PREVIOUS = OLD_SECRET;
    process.env.JWT_SECRET_PREVIOUS_UNTIL = inDays(14);
    assert.throws(() => verifyAccessToken(expired), (error) => error.name === 'TokenExpiredError');
  });

  it('resolvePreviousJwtSecret durumları; değer hiçbir uyarıda görünmez', () => {
    const base = { JWT_SECRET: NEW_SECRET };
    assert.equal(resolvePreviousJwtSecret(base).status, 'none');
    assert.equal(resolvePreviousJwtSecret({ ...base, JWT_SECRET_PREVIOUS: OLD_SECRET }).status, 'missing_until');
    assert.equal(resolvePreviousJwtSecret({ ...base, JWT_SECRET_PREVIOUS: OLD_SECRET, JWT_SECRET_PREVIOUS_UNTIL: 'x' }).status, 'invalid_until');
    assert.equal(resolvePreviousJwtSecret({ ...base, JWT_SECRET_PREVIOUS: OLD_SECRET, JWT_SECRET_PREVIOUS_UNTIL: inDays(-1) }).status, 'expired');
    assert.equal(resolvePreviousJwtSecret({ ...base, JWT_SECRET_PREVIOUS: NEW_SECRET, JWT_SECRET_PREVIOUS_UNTIL: inDays(5) }).status, 'same_as_current');
    assert.equal(resolvePreviousJwtSecret({ ...base, JWT_SECRET_PREVIOUS: 'changeme', JWT_SECRET_PREVIOUS_UNTIL: inDays(5) }).status, 'placeholder');
    const active = resolvePreviousJwtSecret({ ...base, JWT_SECRET_PREVIOUS: OLD_SECRET, JWT_SECRET_PREVIOUS_UNTIL: inDays(5) });
    assert.equal(active.status, 'active');

    for (const env of [
      { ...base, JWT_SECRET_PREVIOUS: OLD_SECRET },
      { ...base, JWT_SECRET_PREVIOUS: OLD_SECRET, JWT_SECRET_PREVIOUS_UNTIL: inDays(-1) },
      { ...base, JWT_SECRET_PREVIOUS: OLD_SECRET, JWT_SECRET_PREVIOUS_UNTIL: inDays(200) },
    ]) {
      const { errors, warnings } = validateEnv(env);
      const all = [...errors, ...warnings].join('\n');
      assert.ok(/JWT_SECRET_PREVIOUS/.test(all));
      assert.equal(all.includes(OLD_SECRET) || all.includes(NEW_SECRET), false, 'sır asla yazılmaz');
    }
  });
});

describe('Üretimde kısa JWT_SECRET: açılış ÇÖKMEZ, güvenlik uyarısı; pv zorunlu', () => {
  beforeEach(() => {
    saveEnv();
    resetJwtSecretWarning();
  });
  afterEach(() => {
    restoreEnv();
    mock.restoreAll();
  });

  it('validateEnv(production, 20 karakter): errors boş, GUVENLIK uyarısı; sır yazılmaz', () => {
    const { errors, warnings } = validateEnv({ NODE_ENV: 'production', JWT_SECRET: OLD_SECRET });
    assert.deepEqual(errors, []);
    const all = warnings.join('\n');
    assert.match(all, /JWT_SECRET 20 karakter/);
    assert.match(all, /GUVENLIK: uretimde JWT_SECRET en az 32/);
    assert.equal(all.includes(OLD_SECRET), false);
    const dev = validateEnv({ JWT_SECRET: OLD_SECRET }).warnings.join('\n');
    assert.equal(/GUVENLIK/.test(dev), false, 'geliştirmede ek uyarı yok');
  });

  it('isPasswordVersionRequired: varsayılan HER ORTAMDA açık (NODE_ENV tanımsız dahil); yalnız JWT_REQUIRE_PV=0 kapatır (uyarılı)', () => {
    assert.equal(isPasswordVersionRequired({}), true, 'canlıda NODE_ENV tanımsız: yine zorunlu');
    assert.equal(isPasswordVersionRequired({ NODE_ENV: 'development' }), true);
    assert.equal(isPasswordVersionRequired({ NODE_ENV: 'production' }), true);
    assert.equal(isPasswordVersionRequired({ JWT_REQUIRE_PV: '1' }), true);
    assert.equal(isPasswordVersionRequired({ JWT_REQUIRE_PV: 'bozuk' }), true, 'geçersiz değer -> zorunlu');
    for (const off of ['0', 'false', 'no', 'off', ' OFF ']) {
      assert.equal(isPasswordVersionRequired({ JWT_REQUIRE_PV: off }), false, off);
    }
    const devWarn = validateEnv({ JWT_SECRET: NEW_SECRET, JWT_REQUIRE_PV: '0' }).warnings.join('\n');
    assert.match(devWarn, /GUVENLIK: JWT_REQUIRE_PV=0/, 'kapatma her ortamda uyarılır');
    const invalidWarn = validateEnv({ JWT_SECRET: NEW_SECRET, JWT_REQUIRE_PV: 'bozuk' }).warnings.join('\n');
    assert.match(invalidWarn, /JWT_REQUIRE_PV gecersiz/);
    assert.equal(/JWT_REQUIRE_PV/.test(validateEnv({ JWT_SECRET: NEW_SECRET }).warnings.join('\n')), false);
  });

  it('pv zorunlu (varsayılan): pv’siz (sahte ya da eski) token isPasswordVersionValid=false; pv’li token geçerli', () => {
    assert.equal(isPasswordVersionValid({ sub: '42' }, HASH), false);
    assert.equal(isPasswordVersionValid({ sub: '42', pv: passwordVersionOf(HASH) }, HASH), true);
    process.env.JWT_REQUIRE_PV = '0';
    assert.equal(isPasswordVersionValid({ sub: '42' }, HASH), true, 'yalnız açıkça kapatılınca eski davranış');
  });

  it('authRequired (NODE_ENV tanımsız, canlıdaki gibi): sırrı bilen ama parola özetini bilmeyen sahte token 401 TOKEN_REVOKED', async () => {
    process.env.JWT_SECRET = NEW_SECRET;
    const forged = jwt.sign({ sub: '42', role: 'super_user' }, NEW_SECRET, { algorithm: 'HS256', expiresIn: '1h' });
    const originalQuery = pool.query;
    pool.query = async () => ({
      rowCount: 1,
      rows: [{ db_id: 7, id: 42, user_code: 42, role: 'super_user', is_active: true, email_verified: true, approval_status: 'approved', password_hash: HASH }],
    });
    try {
      const res = {
        statusCode: 200,
        body: null,
        status(code) {
          this.statusCode = code;
          return this;
        },
        json(payload) {
          this.body = payload;
          return this;
        },
      };
      let nextCalled = false;
      await authRequired({ headers: { authorization: `Bearer ${forged}` } }, res, () => {
        nextCalled = true;
      });
      assert.equal(nextCalled, false);
      assert.equal(res.statusCode, 401);
      assert.equal(res.body.code, 'TOKEN_REVOKED');
    } finally {
      pool.query = originalQuery;
    }
  });
});
