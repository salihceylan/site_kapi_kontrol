import { describe, it, beforeEach, afterEach, mock } from 'node:test';
import assert from 'node:assert/strict';
import jwt from 'jsonwebtoken';
import {
  DEFAULT_JWT_EXPIRES_IN,
  isPasswordVersionValid,
  passwordVersionOf,
  resetJwtSecretWarning,
  signAccessToken,
  verifyAccessToken,
} from '../src/jwt.js';
import {
  evaluateJwtSecret,
  isPlaceholderSecret,
  isValidExpiresIn,
  validateEnv,
} from '../src/config/env.js';

const LONG_SECRET = 'k9Fz-test-only-long-secret-value-0123456789abcdef'; // >= 32 karakter, sahte test degeri
const SHORT_SECRET = 'q8Wr-test-short-20ch'; // 20 karakter (uretimdeki uzunluk), sahte test degeri

describe('JWT secret degerlendirmesi (C12)', () => {
  it('bos / yer tutucu secret reddedilir', () => {
    for (const value of [undefined, null, '', '   ', 'change_this_secret', 'CHANGE_ME', 'changeme', 'your-secret', '<JWT_SECRET>', '${JWT_SECRET}', 'secret', 'replace-me-with-random']) {
      assert.equal(isPlaceholderSecret(value), true, `yer tutucu sayilmali: ${String(value)}`);
      assert.equal(evaluateJwtSecret(value).ok, false);
    }
  });

  it('20 karakterlik gercek secret ACILIR (ok:true) ama uyari uretir', () => {
    assert.equal(SHORT_SECRET.length, 20);
    const result = evaluateJwtSecret(SHORT_SECRET);
    assert.equal(result.ok, true);
    assert.match(result.warning, /20 karakter/);
    assert.match(result.warning, /32/);
  });

  it('>=32 karakterli secret uyarisiz kabul edilir', () => {
    const result = evaluateJwtSecret(LONG_SECRET);
    assert.equal(result.ok, true);
    assert.equal(result.warning, undefined);
  });

  it('validateEnv: yer tutucu secret hata, kisa secret yalnizca uyari', () => {
    const bad = validateEnv({ JWT_SECRET: 'change_this_secret' });
    assert.ok(bad.errors.length >= 1);
    assert.match(bad.errors[0], /JWT_SECRET/);

    const shortOnly = validateEnv({ JWT_SECRET: SHORT_SECRET });
    assert.deepEqual(shortOnly.errors, []);
    assert.ok(shortOnly.warnings.some((w) => /JWT_SECRET/.test(w)));
  });

  it('validateEnv sirlari ciktiya yazmaz', () => {
    const { errors, warnings } = validateEnv({ JWT_SECRET: SHORT_SECRET, DB_PASSWORD: 'db-pass-xyz', SMTP_PASSWORD: 'smtp-pass-xyz', MQTT_PASSWORD: 'mqtt-pass-xyz', COMPANY_API_KEY: 'company-key-value-123456789' });
    const all = [...errors, ...warnings].join('\n');
    for (const secret of [SHORT_SECRET, 'db-pass-xyz', 'smtp-pass-xyz', 'mqtt-pass-xyz', 'company-key-value-123456789']) {
      assert.equal(all.includes(secret), false);
    }
  });

  it('JWT_EXPIRES_IN bicim kontrolu', () => {
    for (const value of ['30d', '12h', '15m', '3600', '2 days']) {
      assert.equal(isValidExpiresIn(value), true, value);
    }
    for (const value of ['', 'abc', '-5d', '30 gun']) {
      assert.equal(isValidExpiresIn(value), false, value);
    }
  });
});

describe('JWT imzalama / dogrulama', () => {
  let savedSecret;
  let savedExpires;

  beforeEach(() => {
    savedSecret = process.env.JWT_SECRET;
    savedExpires = process.env.JWT_EXPIRES_IN;
    process.env.JWT_SECRET = LONG_SECRET;
    delete process.env.JWT_EXPIRES_IN;
    resetJwtSecretWarning();
  });

  afterEach(() => {
    if (savedSecret === undefined) delete process.env.JWT_SECRET;
    else process.env.JWT_SECRET = savedSecret;
    if (savedExpires === undefined) delete process.env.JWT_EXPIRES_IN;
    else process.env.JWT_EXPIRES_IN = savedExpires;
    mock.restoreAll();
  });

  const user = { id: 42, email: 'a@example.com', role: 'individual' };

  it('yer tutucu/bos secret ile token uretimi ve dogrulama reddedilir', () => {
    process.env.JWT_SECRET = 'change_this_secret';
    assert.throws(() => signAccessToken(user), /JWT_SECRET/);
    assert.throws(() => verifyAccessToken('x.y.z'), /JWT_SECRET/);
    delete process.env.JWT_SECRET;
    assert.throws(() => signAccessToken(user), /JWT_SECRET/);
  });

  it('kisa (20 karakter) secret ile calisir ve yalnizca bir kez uyarir', () => {
    process.env.JWT_SECRET = SHORT_SECRET;
    const warn = mock.method(console, 'warn', () => {});
    const token = signAccessToken(user);
    const claims = verifyAccessToken(token);
    assert.equal(claims.sub, '42');
    signAccessToken(user);
    assert.equal(warn.mock.callCount(), 1);
    assert.match(String(warn.mock.calls[0].arguments[0]), /JWT_SECRET 20 karakter/);
  });

  it('varsayilan omur 30 gundur; env ile ozellestirilebilir', () => {
    assert.equal(DEFAULT_JWT_EXPIRES_IN, '30d');
    const claims = jwt.decode(signAccessToken(user));
    assert.equal(claims.exp - claims.iat, 30 * 24 * 60 * 60);

    process.env.JWT_EXPIRES_IN = '12h';
    const shortLived = jwt.decode(signAccessToken(user));
    assert.equal(shortLived.exp - shortLived.iat, 12 * 60 * 60);
  });

  it('algoritma HS256 olarak sabitlenir (HS384 ve alg:none reddedilir)', () => {
    const header = jwt.decode(signAccessToken(user), { complete: true }).header;
    assert.equal(header.alg, 'HS256');

    const hs384 = jwt.sign({ sub: '42' }, LONG_SECRET, { algorithm: 'HS384', expiresIn: '1h' });
    assert.throws(() => verifyAccessToken(hs384), (error) => error.name === 'JsonWebTokenError');

    const none = `${Buffer.from('{"alg":"none","typ":"JWT"}').toString('base64url')}.${Buffer.from('{"sub":"42"}').toString('base64url')}.`;
    assert.throws(() => verifyAccessToken(none), (error) => error.name === 'JsonWebTokenError');
  });

  it('imza hatali / suresi dolmus token JsonWebTokenError/TokenExpiredError atar', () => {
    const wrongKey = jwt.sign({ sub: '42' }, 'baska-bir-secret-degeri-0123456789abcdef', { algorithm: 'HS256' });
    assert.throws(() => verifyAccessToken(wrongKey), (error) => error.name === 'JsonWebTokenError');

    const expired = jwt.sign({ sub: '42' }, LONG_SECRET, { algorithm: 'HS256', expiresIn: -10 });
    assert.throws(() => verifyAccessToken(expired), (error) => error.name === 'TokenExpiredError');
  });

  it('pv claim: parola hash varsa eklenir, yoksa eklenmez (eski davranis)', () => {
    const withPv = verifyAccessToken(signAccessToken(user, { passwordHash: '$2a$10$abcdefghijklmnopqrstuv' }));
    assert.equal(typeof withPv.pv, 'string');
    assert.equal(withPv.pv, passwordVersionOf('$2a$10$abcdefghijklmnopqrstuv'));

    const rowStyle = verifyAccessToken(signAccessToken({ ...user, password_hash: '$2a$10$zzzzzzzzzzzzzzzzzzzzzz' }));
    assert.equal(rowStyle.pv, passwordVersionOf('$2a$10$zzzzzzzzzzzzzzzzzzzzzz'));

    const withoutPv = verifyAccessToken(signAccessToken(user));
    assert.equal(withoutPv.pv, undefined);
  });

  it('pv karsilastirmasi: ayni hash gecerli, degisen hash gecersiz, claim yoksa gecerli (eski token)', () => {
    const hashA = '$2a$10$AAAAAAAAAAAAAAAAAAAAAA';
    const hashB = '$2a$10$BBBBBBBBBBBBBBBBBBBBBB';
    const claims = verifyAccessToken(signAccessToken(user, { passwordHash: hashA }));

    assert.equal(isPasswordVersionValid(claims, hashA), true);
    assert.equal(isPasswordVersionValid(claims, hashB), false);
    assert.equal(isPasswordVersionValid(claims, null), false);

    // Claim'siz eski token: parola degisse bile suresi dolana kadar gecerli kalir.
    const legacy = verifyAccessToken(jwt.sign({ sub: '42', email: 'a@example.com', role: 'individual' }, LONG_SECRET, { expiresIn: '1h' }));
    assert.equal(isPasswordVersionValid(legacy, hashB), true);

    assert.equal(isPasswordVersionValid({ pv: 12345 }, hashA), false);
  });

  it('passwordVersionOf hash degerini acik etmez ve bos girdide null doner', () => {
    const hash = '$2a$10$AAAAAAAAAAAAAAAAAAAAAA';
    const pv = passwordVersionOf(hash);
    assert.equal(pv.length, 16);
    assert.equal(hash.includes(pv), false);
    assert.equal(passwordVersionOf(''), null);
    assert.equal(passwordVersionOf(undefined), null);
  });
});
