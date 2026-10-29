// Deneme erişim kodu (P2-27): kod üretimi / özeti ve deneme oturumu erişim ilkesi (saf birim testleri; DB yok).
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import {
  TRIAL_CODE_ALPHABET,
  TRIAL_CODE_LENGTH,
  TRIAL_SESSION_HOURS,
  evaluateTrialRequest,
  formatTrialCode,
  generateTrialCode,
  hashTrialCode,
  isTrialAccountEmail,
  normalizeTrialCode,
  splitTrialPath,
  trialCodeHint,
} from '../src/modules/trial_access_common.js';
import { isReservedEmail } from '../src/utils/reserved_email.js';

describe('deneme kodu: üretim / biçim / özet', () => {
  it('kod XXXX-XXXX-XXXX biçimindedir, yalnız karışmayan karakterler kullanır', () => {
    for (let i = 0; i < 200; i += 1) {
      const code = generateTrialCode();
      assert.match(code, /^[2-9A-HJKMNP-Z]{4}-[2-9A-HJKMNP-Z]{4}-[2-9A-HJKMNP-Z]{4}$/);
      assert.equal(code.replace(/-/g, '').length, TRIAL_CODE_LENGTH);
    }
    for (const bad of ['0', '1', 'I', 'L', 'O']) {
      assert.equal(TRIAL_CODE_ALPHABET.includes(bad), false, `${bad} alfabede olmamalı`);
    }
  });

  it('kodlar rastgeledir: 5000 üretim çakışmaz, her karakter konumu çeşitlidir', () => {
    const seen = new Set();
    const firstChars = new Set();
    for (let i = 0; i < 5000; i += 1) {
      const code = generateTrialCode();
      seen.add(code);
      firstChars.add(code[0]);
    }
    assert.equal(seen.size, 5000);
    assert.ok(firstChars.size >= 20, `ilk karakter çeşitliliği düşük: ${firstChars.size}`);
  });

  it('randomInt enjekte edilebilir (alfabe sınırı dahil)', () => {
    const calls = [];
    const code = generateTrialCode((min, max) => {
      calls.push([min, max]);
      return 0;
    });
    assert.equal(code, 'AAAA-AAAA-AAAA'.replace(/A/g, TRIAL_CODE_ALPHABET[0]));
    assert.equal(calls.length, TRIAL_CODE_LENGTH);
    assert.ok(calls.every(([min, max]) => min === 0 && max === TRIAL_CODE_ALPHABET.length));
  });

  it('normalizeTrialCode: küçük harf / boşluk / tire toleransı; uzunluk ve alfabe dışı reddedilir', () => {
    const code = generateTrialCode();
    const flat = code.replace(/-/g, '');
    assert.equal(normalizeTrialCode(code), flat);
    assert.equal(normalizeTrialCode(code.toLowerCase()), flat);
    assert.equal(normalizeTrialCode(` ${code.replace(/-/g, ' ')} `), flat);
    assert.equal(normalizeTrialCode(flat.slice(0, 11)), null);
    assert.equal(normalizeTrialCode(`${flat}A`), null);
    assert.equal(normalizeTrialCode(`${flat.slice(0, 11)}0`), null, '0 alfabede yok');
    assert.equal(normalizeTrialCode(`${flat.slice(0, 11)}O`), null, 'O alfabede yok');
    assert.equal(normalizeTrialCode(''), null);
    assert.equal(normalizeTrialCode(undefined), null);
    assert.equal(normalizeTrialCode(null), null);
    assert.equal(normalizeTrialCode(12345), null);
    assert.equal(normalizeTrialCode({ toString: () => flat }), null);
    assert.equal(normalizeTrialCode('A'.repeat(500)), null);
    assert.equal(formatTrialCode(flat), code);
    assert.equal(trialCodeHint(flat), flat.slice(-4));
  });

  it('özet: sabit, 64 onaltılık, anahtara bağlı; anahtarsız üretilemez; düz kod özette geçmez', () => {
    const flat = normalizeTrialCode(generateTrialCode());
    const a = hashTrialCode(flat, 'pepper-A');
    assert.match(a, /^[0-9a-f]{64}$/);
    assert.equal(hashTrialCode(flat, 'pepper-A'), a);
    assert.notEqual(hashTrialCode(flat, 'pepper-B'), a);
    assert.notEqual(hashTrialCode(`${flat.slice(0, 11)}${flat[11] === '2' ? '3' : '2'}`, 'pepper-A'), a);
    assert.equal(a.includes(flat.toLowerCase()), false);
    assert.throws(() => hashTrialCode(flat, ''), /TRIAL_CODE_PEPPER/);
  });

  it('TRIAL_CODE_PEPPER yoksa JWT_SECRET kullanılır', () => {
    const saved = { p: process.env.TRIAL_CODE_PEPPER, j: process.env.JWT_SECRET };
    try {
      delete process.env.TRIAL_CODE_PEPPER;
      process.env.JWT_SECRET = 'jwt-secret-for-pepper-test-0123456789abcdef';
      const flat = normalizeTrialCode(generateTrialCode());
      assert.equal(hashTrialCode(flat), hashTrialCode(flat, process.env.JWT_SECRET));
      process.env.TRIAL_CODE_PEPPER = 'dedicated-pepper';
      assert.equal(hashTrialCode(flat), hashTrialCode(flat, 'dedicated-pepper'));
    } finally {
      if (saved.p === undefined) delete process.env.TRIAL_CODE_PEPPER;
      else process.env.TRIAL_CODE_PEPPER = saved.p;
      if (saved.j === undefined) delete process.env.JWT_SECRET;
      else process.env.JWT_SECRET = saved.j;
    }
  });

  it('deneme e-posta alanı ayrılmıştır (kayıt / davet / yönetici oluşturma reddeder)', () => {
    assert.equal(isReservedEmail('trial-ab12@deneme.invalid'), true);
    assert.equal(isReservedEmail('x@alt.deneme.invalid'), true);
    assert.equal(isReservedEmail('x@deneme.com'), false);
    assert.equal(isReservedEmail('x@deleted.invalid'), true);
  });

  it('isTrialAccountEmail: yalnız ayrılmış alan adı (büyük/küçük harf duyarsız)', () => {
    assert.equal(isTrialAccountEmail('trial-ab12@deneme.invalid'), true);
    assert.equal(isTrialAccountEmail(' TRIAL-AB12@Deneme.Invalid '), true);
    assert.equal(isTrialAccountEmail('x@deneme.com'), false);
    assert.equal(isTrialAccountEmail('x@alt.deneme.invalid'), false, 'alt alan adı üretilmez');
    assert.equal(isTrialAccountEmail('deneme.invalid@example.com'), false);
    assert.equal(isTrialAccountEmail(null), false);
    assert.equal(isTrialAccountEmail(undefined), false);
  });

  it('oturum süresi 72 saattir', () => {
    assert.equal(TRIAL_SESSION_HOURS, 72);
  });
});

describe('splitTrialPath', () => {
  it('sorgu, parça ve sondaki eğik çizgi atılır; parçalar küçük harfe çevrilir', () => {
    assert.deepEqual(splitTrialPath('/Manager/Sites/123/Finance/Summary?x=1#a'), ['manager', 'sites', '123', 'finance', 'summary']);
    assert.deepEqual(splitTrialPath('/me/'), ['me']);
    assert.deepEqual(splitTrialPath('/'), []);
  });

  it('Express ile farklı çözülebilecek her biçim null döner', () => {
    for (const bad of [
      '',
      'manager/sites',
      '//manager/sites',
      '/manager//sites',
      '/manager/sites/%31%32',
      '/manager/sites/1;x=2',
      '/manager/sites/../admin',
      '/manager/sites/./1',
      '/manager/sites\\1',
      '/manager/sites/1 2',
      '/manager/sitês/1',
      '/manager/sites/1\u0000',
      '/manager/sites/<script>',
    ]) {
      assert.equal(splitTrialPath(bad), null, JSON.stringify(bad));
    }
    assert.equal(splitTrialPath(undefined), null);
    assert.equal(splitTrialPath(null), null);
  });
});

describe('evaluateTrialRequest: deneme oturumu erişim ilkesi (varsayılan RED)', () => {
  const NOW = Date.parse('2026-11-01T10:00:00Z');
  const DEMO = 4000000001;
  const OTHER = 4000000002;
  const active = { siteCode: DEMO, expiresAt: new Date(NOW + 3600_000) };
  const evaluate = (method, path, overrides = {}) =>
    evaluateTrialRequest({ trial: active, demoSiteCode: DEMO, now: NOW, method, path, ...overrides });
  const allowed = (method, path) => assert.deepEqual(evaluate(method, path), { ok: true }, `${method} ${path} açık olmalı`);
  const denied = (method, path, code = 'TRIAL_ACTION_DENIED') => {
    const verdict = evaluate(method, path);
    assert.equal(verdict.ok, false, `${method} ${path} kapalı olmalı`);
    assert.equal(verdict.status, 403, `${method} ${path}`);
    assert.equal(verdict.code, code, `${method} ${path}`);
  };

  it('süre dolumu: HER yolda 401 TRIAL_EXPIRED (GET /me dahil); sınırda (==) dolmuş sayılır', () => {
    for (const path of ['/me', '/manager/sites', `/manager/sites/${DEMO}/finance/summary`, '/app/my-modules']) {
      const verdict = evaluate('GET', path, { trial: { siteCode: DEMO, expiresAt: new Date(NOW - 1) } });
      assert.equal(verdict.ok, false);
      assert.equal(verdict.status, 401);
      assert.equal(verdict.code, 'TRIAL_EXPIRED');
    }
    assert.equal(evaluate('GET', '/me', { trial: { siteCode: DEMO, expiresAt: new Date(NOW) } }).code, 'TRIAL_EXPIRED');
    assert.equal(evaluate('GET', '/me', { trial: { siteCode: DEMO, expiresAt: new Date(NOW + 1) } }).ok, true);
  });

  it('süre bilgisi yok ya da bozuk: oturum bitmiş sayılır (güvenli taraf)', () => {
    for (const expiresAt of [null, undefined, 'bozuk', Number.NaN]) {
      const verdict = evaluate('GET', '/me', { trial: { siteCode: DEMO, expiresAt } });
      assert.equal(verdict.ok, false);
      assert.equal(verdict.code, 'TRIAL_EXPIRED');
    }
  });

  it('iptal: 401 TRIAL_REVOKED; demo site kaldırıldı / değişti: 401 TRIAL_REVOKED', () => {
    const revoked = evaluate('GET', '/me', { trial: { ...active, revokedAt: new Date(NOW - 5) } });
    assert.equal(revoked.status, 401);
    assert.equal(revoked.code, 'TRIAL_REVOKED');
    for (const demoSiteCode of [null, undefined, '', OTHER, '0', 'abc']) {
      const verdict = evaluate('GET', '/me', { demoSiteCode });
      assert.equal(verdict.ok, false, String(demoSiteCode));
      assert.equal(verdict.status, 401);
      assert.equal(verdict.code, 'TRIAL_REVOKED');
    }
    assert.equal(evaluate('GET', '/me', { demoSiteCode: String(DEMO) }).ok, true, 'metin olarak gelen demo site kodu kabul');
  });

  it('kapsam dışı site: demo dışı siteye her yöntem ve her alt yol 403 TRIAL_SCOPE_DENIED', () => {
    for (const method of ['GET', 'POST', 'PUT', 'PATCH', 'DELETE']) {
      denied(method, `/manager/sites/${OTHER}`, 'TRIAL_SCOPE_DENIED');
      denied(method, `/manager/sites/${OTHER}/finance/summary`, 'TRIAL_SCOPE_DENIED');
      denied(method, `/manager/sites/${OTHER}/people`, 'TRIAL_SCOPE_DENIED');
      denied(method, `/manager/sites/${OTHER}/announcements/5/publish`, 'TRIAL_SCOPE_DENIED');
      denied(method, `/sites/${OTHER}/meter-field/meters`, 'TRIAL_SCOPE_DENIED');
    }
    denied('GET', `/membership/sites/${OTHER}/residents-tree`, 'TRIAL_SCOPE_DENIED');
    // büyük / küçük harf ve sondaki eğik çizgi kapsamı atlatmaz
    denied('GET', `/MANAGER/Sites/${OTHER}/Finance/`, 'TRIAL_SCOPE_DENIED');
    // baştaki sıfır ya da başka biçim demo site kodu DEĞİLDİR (Express parseId başka siteye çözebilir)
    denied('GET', `/manager/sites/0${DEMO}/finance/summary`, 'TRIAL_SCOPE_DENIED');
    denied('GET', `/manager/sites/${DEMO}0/finance/summary`, 'TRIAL_SCOPE_DENIED');
  });

  it('yol saldırıları 403 TRIAL_PATH_DENIED (yüzde kodlaması, "..", "//", noktalı virgül)', () => {
    for (const path of [
      `/manager/sites/%34000000001/finance/summary`,
      `/manager/sites/${DEMO}/../${OTHER}/finance/summary`,
      `/manager/sites/${DEMO}/./finance/summary`,
      `//manager/sites/${OTHER}/finance/summary`,
      `/manager/sites/${DEMO};/finance/summary`,
      `/manager/sites/${DEMO}%2f..%2f${OTHER}`,
    ]) {
      denied('GET', path, 'TRIAL_PATH_DENIED');
    }
  });

  it('demo sitenin kendi verisinde işlem serbest (okuma ve yazma)', () => {
    allowed('GET', `/manager/sites/${DEMO}`);
    allowed('GET', `/manager/sites/${DEMO}/structure`);
    allowed('GET', `/manager/sites/${DEMO}/finance/summary`);
    allowed('POST', `/manager/sites/${DEMO}/finance/payments`);
    allowed('POST', `/manager/sites/${DEMO}/finance/charges`);
    allowed('POST', `/manager/sites/${DEMO}/finance/entries/7/reverse`);
    allowed('POST', `/manager/sites/${DEMO}/announcements`);
    allowed('POST', `/manager/sites/${DEMO}/announcements/9/publish`);
    allowed('POST', `/manager/sites/${DEMO}/people`);
    allowed('PATCH', `/manager/sites/${DEMO}/people/3`);
    allowed('PUT', `/manager/sites/${DEMO}/apartments/4/admin`);
    allowed('POST', `/manager/sites/${DEMO}/documents`);
    allowed('POST', `/manager/sites/${DEMO}/work-items/2/comments`);
    allowed('POST', `/manager/sites/${DEMO}/surveys`);
    allowed('DELETE', `/manager/sites/${DEMO}/decisions/3`);
    allowed('POST', `/manager/sites/${DEMO}/imports/people/preview`);
    allowed('GET', `/manager/sites/${DEMO}/imports/spec`);
    allowed('GET', `/manager/sites/${DEMO}/exports/people`);
    allowed('GET', `/sites/${DEMO}/meter-field/meters`);
    allowed('GET', `/membership/sites/${DEMO}/residents-tree`);
    allowed('POST', `/manager/sites/${DEMO}/finance/bank-imports/preview`);
    allowed('PUT', `/manager/sites/${DEMO}/finance/payment-settings`);
    allowed('GET', `/manager/sites/${DEMO}/staff-roles`);
    allowed('GET', `/manager/sites/${DEMO}/drive`);
    allowed('GET', `/manager/sites/${DEMO}/access-cards`);
    allowed('GET', `/manager/sites/${DEMO}/modules`);
  });

  it('oturum / sakin tarafı uçları açık: /me, /me/consents, /app/*, listeler', () => {
    allowed('GET', '/me');
    allowed('GET', '/me/consents');
    allowed('POST', '/me/consents');
    allowed('GET', '/app/my-modules');
    allowed('GET', '/app/announcements');
    allowed('POST', '/app/push/devices');
    allowed('GET', '/manager/sites');
    allowed('GET', '/manager/devices');
    allowed('GET', '/manager/door-logs');
    allowed('GET', '/membership/my-apartments');
    allowed('GET', '/membership/site-applications/mine');
    allowed('GET', '/brand-theme/mine');
    allowed('GET', '/app/doors/5/status');
  });

  it('dış etkisi olan / hesap-site yaşam döngüsü uçları KAPALI', () => {
    // yeni site, profil, hesap silme, veri dışa aktarma
    denied('POST', '/manager/sites');
    denied('PATCH', '/me');
    denied('PUT', '/me');
    denied('POST', '/me/account-deletion');
    denied('GET', '/me/data-export');
    // site yaşam döngüsü / üyelik
    denied('PATCH', `/manager/sites/${DEMO}`);
    denied('DELETE', `/manager/sites/${DEMO}`);
    denied('POST', `/manager/sites/${DEMO}/approve-deletion`);
    denied('PATCH', `/manager/sites/${DEMO}/security-policy`);
    denied('GET', `/manager/sites/${DEMO}/managers`);
    denied('POST', `/manager/sites/${DEMO}/managers/invite`);
    denied('DELETE', `/manager/sites/${DEMO}/managers/12345`);
    denied('GET', `/manager/sites/${DEMO}/join-token`);
    denied('POST', `/manager/sites/${DEMO}/join-token/rotate`);
    denied('GET', `/manager/sites/${DEMO}/join-requests`);
    denied('DELETE', `/manager/sites/${DEMO}/invitations/4`);
    // donanım / dış bağlantı
    denied('POST', `/manager/sites/${DEMO}/doors`);
    denied('GET', `/manager/sites/${DEMO}/assignable-devices`);
    denied('POST', `/manager/sites/${DEMO}/cameras`);
    denied('GET', `/manager/sites/${DEMO}/cctv/cameras/3/snapshot`);
    denied('POST', `/manager/sites/${DEMO}/cctv/clip-link`);
    denied('GET', `/manager/sites/${DEMO}/plate-recognition/events`);
    denied('GET', `/manager/sites/${DEMO}/plate-events`);
    denied('POST', `/manager/sites/${DEMO}/drive/connect`);
    denied('DELETE', `/manager/sites/${DEMO}/drive`);
    denied('POST', `/manager/sites/${DEMO}/access-cards`);
    denied('PUT', `/manager/sites/${DEMO}/card-payments/iyzico`);
    denied('PUT', `/manager/sites/${DEMO}/modules/finance`);
    denied('POST', '/manager/devices/mqtt-credentials');
    denied('PATCH', '/manager/doors/5/device');
    denied('POST', '/manager/doors/5/replace-device');
    denied('PATCH', '/manager/apartments/5/resident');
    denied('POST', '/manager/join-requests/5/approve');
    denied('GET', '/manager/devices/lookup');
    // platform düzeyi talep + kendini çoğaltma
    denied('POST', `/manager/sites/${DEMO}/module-requests`);
    denied('GET', `/manager/sites/${DEMO}/trial-access`);
    denied('POST', `/manager/sites/${DEMO}/trial-access/codes`);
    denied('PUT', `/manager/sites/${DEMO}/trial-access/demo`);
    denied('DELETE', `/manager/sites/${DEMO}/trial-access/codes/3`);
    // e-posta / SMS gönderen, hesap ve kullanıcı kodu üreten uçlar
    denied('POST', `/manager/sites/${DEMO}/people/bulk-actions`);
    denied('POST', `/manager/sites/${DEMO}/people/5/invitation`);
    denied('DELETE', `/manager/sites/${DEMO}/people/5/invitation`);
    denied('POST', `/manager/sites/${DEMO}/people/5/password-reset`);
    denied('POST', `/manager/sites/${DEMO}/people/5/account`);
    denied('POST', `/manager/sites/${DEMO}/people/5/reset-pin`);
    denied('POST', `/manager/sites/${DEMO}/finance/reminders/send`);
    denied('POST', `/manager/sites/${DEMO}/imports/people/commit`);
    denied('POST', `/manager/sites/${DEMO}/imports/people/accounts`);
    denied('POST', `/manager/sites/${DEMO}/imports/login-names/check`);
    // başka kullanıcıları (platform genelinde) e-postayla arayan uç
    denied('PUT', `/manager/sites/${DEMO}/staff-roles`);
    denied('DELETE', `/manager/sites/${DEMO}/staff-roles/12345`);
    // sakin tarafında kapı komutu, misafir geçişi, davet kabulü
    denied('POST', '/app/doors/5/open');
    denied('POST', '/app/doors/scan-qr-open');
    denied('POST', '/app/doors/5/qr-token');
    denied('POST', '/app/guest-passes');
    denied('DELETE', '/app/guest-passes/4');
    denied('POST', '/app/invitations/4/accept');
    // kimlik doğrulamalı diğer ailelerin tamamı
    denied('GET', '/admin/users');
    denied('POST', '/admin/sites');
    denied('GET', '/admin/audit-log');
    denied('PUT', '/admin/platform-config');
    denied('POST', '/membership/setup-site');
    denied('POST', '/membership/claim-device');
    denied('POST', '/membership/join-request');
    denied('POST', '/membership/site-applications');
    denied('GET', '/companies');
    denied('PUT', '/brand-themes/site/4000000001');
    denied('GET', '/device/sync-logs');
    denied('GET', '/bilinmeyen/yol');
    denied('GET', '/');
  });

  it('yöntem büyük/küçük harfi önemsemez; HEAD okuma sayılır', () => {
    assert.equal(evaluateTrialRequest({ trial: active, demoSiteCode: DEMO, now: NOW, method: 'get', path: '/me' }).ok, true);
    assert.equal(evaluateTrialRequest({ trial: active, demoSiteCode: DEMO, now: NOW, method: 'head', path: `/manager/sites/${DEMO}/drive` }).ok, true);
    assert.equal(evaluateTrialRequest({ trial: active, demoSiteCode: DEMO, now: NOW, method: 'post', path: `/manager/sites/${DEMO}/drive/files` }).ok, false);
  });
});
