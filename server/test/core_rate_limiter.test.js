import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import {
  adminSensitiveLimiter,
  claimDeviceLimiter,
  createRuleLimiter,
  doorCommandRateLimiter,
  forgotPasswordLimiter,
  inviteLimiter,
  loginRateLimiter,
  qrTokenRateLimiter,
  registerLimiter,
  registerSweeper,
  resendCodeLimiter,
  resetPasswordLimiter,
  sweepAllRateLimitStores,
  verifyCodeLimiter,
} from '../src/middlewares/rate_limiters.js';
import { createFailureTracker } from '../src/middlewares/login_throttle.js';

function makeRes() {
  return {
    statusCode: 200,
    headers: {},
    body: undefined,
    setHeader(name, value) {
      this.headers[name] = value;
    },
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

// Limiter'i bir kez calistirir; { blocked, res } doner.
function hit(limiter, req) {
  const res = makeRes();
  let passed = false;
  limiter({ path: '/x', params: {}, body: {}, ...req }, res, () => {
    passed = true;
  });
  return { blocked: !passed, res };
}

describe('createRuleLimiter', () => {
  it('limit asilinca 429 + Retry-After; pencere dolunca serbest', () => {
    let clock = 1_000_000;
    const limiter = createRuleLimiter({
      rules: [{ windowMs: 10_000, max: 2, key: (req) => `ip:${req.ip}` }],
      message: 'cok fazla',
      now: () => clock,
    });
    assert.equal(hit(limiter, { ip: '1.1.1.1' }).blocked, false);
    assert.equal(hit(limiter, { ip: '1.1.1.1' }).blocked, false);
    const third = hit(limiter, { ip: '1.1.1.1' });
    assert.equal(third.blocked, true);
    assert.equal(third.res.statusCode, 429);
    assert.deepEqual(third.res.body, { error: 'cok fazla' });
    assert.equal(Number(third.res.headers['Retry-After']), 10);

    // baska IP etkilenmez
    assert.equal(hit(limiter, { ip: '2.2.2.2' }).blocked, false);

    clock += 10_001;
    assert.equal(hit(limiter, { ip: '1.1.1.1' }).blocked, false);
  });

  it('birden fazla kural: herhangi biri asilirsa engellenir; key null olan kural atlanir', () => {
    const limiter = createRuleLimiter({
      rules: [
        { windowMs: 60_000, max: 100, key: (req) => `ip:${req.ip}` },
        { windowMs: 60_000, max: 2, key: (req) => (req.body.email ? `e:${req.body.email}` : null) },
      ],
      message: 'x',
    });
    // IP degisse de ayni e-posta 3. istekte engellenir
    assert.equal(hit(limiter, { ip: '1.1.1.1', body: { email: 'a@x.com' } }).blocked, false);
    assert.equal(hit(limiter, { ip: '2.2.2.2', body: { email: 'a@x.com' } }).blocked, false);
    assert.equal(hit(limiter, { ip: '3.3.3.3', body: { email: 'a@x.com' } }).blocked, true);
    // e-postasiz istekler yalnizca IP kuralina tabi
    for (let i = 0; i < 10; i += 1) {
      assert.equal(hit(limiter, { ip: '4.4.4.4', body: {} }).blocked, false);
    }
  });

  it('bellek ust siniri: cok sayida benzersiz anahtar store u sinirsiz buyutmez', () => {
    const limiter = createRuleLimiter({
      rules: [{ windowMs: 60 * 60 * 1000, max: 5, key: (req) => `k:${req.ip}` }],
      message: 'x',
    });
    for (let i = 0; i < 50_500; i += 1) {
      hit(limiter, { ip: `10.${i}` });
    }
    assert.ok(limiter.size() <= 50_000, `store boyutu ${limiter.size()}`);
  });

  it('periyodik temizlik: suresi dolmus kayitlar sweep ile silinir', () => {
    let clock = 5_000_000;
    const limiter = createRuleLimiter({
      rules: [{ windowMs: 1_000, max: 5, key: (req) => `k:${req.ip}` }],
      message: 'x',
      now: () => clock,
    });
    hit(limiter, { ip: 'a' });
    hit(limiter, { ip: 'b' });
    assert.equal(limiter.size(), 2);
    sweepAllRateLimitStores(clock + 500);
    assert.equal(limiter.size(), 2, 'sure dolmadan silinmez');
    sweepAllRateLimitStores(clock + 2_000);
    assert.equal(limiter.size(), 0);
  });

  it('registerSweeper kaydi iptal edilebilir ve temizlik hatalari yutulur', () => {
    let calls = 0;
    const unregister = registerSweeper(() => {
      calls += 1;
    });
    registerSweeper(() => {
      throw new Error('temizlik hatasi');
    });
    sweepAllRateLimitStores();
    assert.equal(calls, 1);
    unregister();
    sweepAllRateLimitStores();
    assert.equal(calls, 1);
  });
});

describe('Kapi komutu limiter i (kullanici bazli)', () => {
  it('ayni IP (NAT) arkasindaki farkli kullanicilar birbirini kilitlemez', () => {
    doorCommandRateLimiter.reset();
    const nat = '203.0.113.9';
    for (let i = 0; i < 4; i += 1) {
      assert.equal(hit(doorCommandRateLimiter, { ip: nat, path: '/app/doors/5/open', authUser: { userCode: 1 } }).blocked, false);
    }
    assert.equal(hit(doorCommandRateLimiter, { ip: nat, path: '/app/doors/5/open', authUser: { userCode: 1 } }).blocked, true);
    // ayni IP, baska kullanici -> serbest
    assert.equal(hit(doorCommandRateLimiter, { ip: nat, path: '/app/doors/5/open', authUser: { userCode: 2 } }).blocked, false);
  });

  it('userCode yoksa IP anahtari kullanilir (misafir gecisi)', () => {
    doorCommandRateLimiter.reset();
    const req = { ip: '198.51.100.7', path: '/public/guest-pass/abc/open' };
    for (let i = 0; i < 4; i += 1) {
      assert.equal(hit(doorCommandRateLimiter, req).blocked, false);
    }
    assert.equal(hit(doorCommandRateLimiter, req).blocked, true);
    assert.equal(hit(doorCommandRateLimiter, { ...req, ip: '198.51.100.8' }).blocked, false);
  });
});

describe('C1 limiter adlari ve davranislari', () => {
  const exported = {
    registerLimiter,
    verifyCodeLimiter,
    resendCodeLimiter,
    forgotPasswordLimiter,
    resetPasswordLimiter,
    claimDeviceLimiter,
    inviteLimiter,
    adminSensitiveLimiter,
    loginRateLimiter,
    qrTokenRateLimiter,
  };

  it('C1 sozlesmesindeki tum limiter lar (req,res,next) middleware olarak export edilir', () => {
    for (const [name, limiter] of Object.entries(exported)) {
      assert.equal(typeof limiter, 'function', name);
      assert.equal(limiter.length, 3, `${name} (req,res,next) imzasinda olmali`);
    }
  });

  it('forgotPasswordLimiter: ayni IP+e-posta 3. istekten sonra, e-posta tek basina 5. istekten sonra engellenir', () => {
    forgotPasswordLimiter.reset();
    const body = { email: 'kurban@example.com' };
    assert.equal(hit(forgotPasswordLimiter, { ip: '1.1.1.1', body }).blocked, false);
    assert.equal(hit(forgotPasswordLimiter, { ip: '1.1.1.1', body }).blocked, false);
    assert.equal(hit(forgotPasswordLimiter, { ip: '1.1.1.1', body }).blocked, false);
    assert.equal(hit(forgotPasswordLimiter, { ip: '1.1.1.1', body }).blocked, true);

    // IP degistirerek e-posta bombalama: e-posta kuralinda yakalanir (toplam 5)
    assert.equal(hit(forgotPasswordLimiter, { ip: '2.2.2.2', body }).blocked, false);
    assert.equal(hit(forgotPasswordLimiter, { ip: '3.3.3.3', body }).blocked, true);
  });

  it('verifyCodeLimiter: e-posta bazli kaba kuvvet IP degistirerek asilamaz', () => {
    verifyCodeLimiter.reset();
    const body = { email: 'kurban@example.com', code: '123456' };
    let blockedAt = null;
    for (let i = 1; i <= 40; i += 1) {
      const result = hit(verifyCodeLimiter, { ip: `9.9.9.${i}`, body });
      if (result.blocked && blockedAt === null) blockedAt = i;
    }
    assert.ok(blockedAt !== null && blockedAt <= 21, `ilk engel ${blockedAt}. istekte olmali`);
  });

  it('claimDeviceLimiter / adminSensitiveLimiter / inviteLimiter: kullanici bazli, kullanici yoksa IP', () => {
    for (const limiter of [claimDeviceLimiter, adminSensitiveLimiter, inviteLimiter]) {
      limiter.reset();
      let blocked = false;
      for (let i = 0; i < 100; i += 1) {
        if (hit(limiter, { ip: `10.0.0.${i % 250}`, authUser: { userCode: 77 } }).blocked) {
          blocked = true;
          break;
        }
      }
      assert.equal(blocked, true, 'ayni kullanici IP degistirse de sinirlanmali');
      assert.equal(hit(limiter, { ip: '10.9.9.9', authUser: { userCode: 78 } }).blocked, false, 'baska kullanici etkilenmemeli');
    }
  });

  it('429 govdesi {error} icerir, kimlik/sir icermez', () => {
    registerLimiter.reset();
    let last;
    for (let i = 0; i < 7; i += 1) {
      last = hit(registerLimiter, { ip: '5.5.5.5', body: { email: 'x@example.com', password: 'gizli-parola' } });
    }
    assert.equal(last.res.statusCode, 429);
    assert.equal(JSON.stringify(last.res.body).includes('gizli-parola'), false);
  });

  it('loginRateLimiter: ayni IP+kimlik 15 denemeden sonra engellenir, NAT tarafindaki baska hesaplar etkilenmez', () => {
    loginRateLimiter.reset();
    const nat = '203.0.113.50';
    let blockedAt = null;
    for (let i = 1; i <= 20; i += 1) {
      if (hit(loginRateLimiter, { ip: nat, body: { email: 'a@example.com' } }).blocked && blockedAt === null) blockedAt = i;
    }
    assert.equal(blockedAt, 16);
    assert.equal(hit(loginRateLimiter, { ip: nat, body: { email: 'b@example.com' } }).blocked, false);
  });
});

describe('Hesap bazli ardisik hata sayaci (login_throttle)', () => {
  it('5 hata -> kilit; kilitliyken check locked; 15 dk sonra acilir', () => {
    let clock = 1_000_000;
    const tracker = createFailureTracker({ maxFailures: 5, windowMs: 15 * 60_000, lockMs: 15 * 60_000, now: () => clock });
    for (let i = 1; i <= 4; i += 1) {
      const state = tracker.recordFailure('ali@example.com');
      assert.equal(state.locked, false);
      assert.equal(state.failures, i);
    }
    assert.equal(tracker.check('ali@example.com').locked, false);

    const fifth = tracker.recordFailure('ali@example.com');
    assert.equal(fifth.locked, true);
    assert.equal(fifth.retryAfterSeconds, 900);
    assert.equal(tracker.check('ali@example.com').locked, true);

    clock += 5 * 60_000;
    const mid = tracker.check('ali@example.com');
    assert.equal(mid.locked, true);
    assert.equal(mid.retryAfterSeconds, 600);

    clock += 10 * 60_000 + 1;
    assert.equal(tracker.check('ali@example.com').locked, false);
  });

  it('basarili giris sayaci sifirlar; baska hesaplar etkilenmez', () => {
    const tracker = createFailureTracker({ maxFailures: 5 });
    for (let i = 0; i < 4; i += 1) tracker.recordFailure('a');
    tracker.recordFailure('b');
    tracker.recordSuccess('a');
    for (let i = 0; i < 4; i += 1) {
      assert.equal(tracker.recordFailure('a').locked, false);
    }
    assert.equal(tracker.check('b').locked, false);
    assert.equal(tracker.recordFailure('a').locked, true);
  });

  it('pencere disinda kalan eski hatalar sayilmaz', () => {
    let clock = 0;
    const tracker = createFailureTracker({ maxFailures: 3, windowMs: 60_000, lockMs: 60_000, now: () => clock });
    tracker.recordFailure('x');
    tracker.recordFailure('x');
    clock += 61_000;
    assert.equal(tracker.recordFailure('x').locked, false);
    assert.equal(tracker.recordFailure('x').locked, false);
    assert.equal(tracker.recordFailure('x').locked, true);
  });
});
