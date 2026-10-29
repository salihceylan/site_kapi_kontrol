// Deneme oturumu erişim ilkesi, gerçek ara katmanda (authRequired) ve GERÇEK rota tablosunda:
//  1) authRequired + sahte veritabanı: süre dolumu / iptal / demo değişimi 401, kapsam dışı 403, deneme olmayan hesap etkilenmez.
//  2) Rota tablosu taraması: server.js'teki HER kimlikli rota için "demo dışı siteye istek asla geçmez", "admin / şirket / cihaz aileleri kapalı",
//     "tehlikeli uçlar kapalı" değişmezleri (yeni rota eklenince de bu testler onu kapsar; açık küme sessizce genişleyemez).
import { describe, it, before, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert/strict';
import { pool } from '../src/db.js';
import { signAccessToken } from '../src/jwt.js';
import { authRequired } from '../src/middlewares/auth_middleware.js';
import { DEMO_SITE_SETTING_KEY, evaluateTrialRequest } from '../src/modules/trial_access_common.js';
import { mapUserRow } from '../src/utils/helpers.js';

const SECRET = 'k9Fz-test-only-long-secret-value-0123456789abcdef';
const HASH = '$2a$10$AAAAAAAAAAAAAAAAAAAAAA';
const DEMO = 4000000001;
const OTHER = 4000000002;

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
    id: 20099,
    user_code: 20099,
    full_name: 'Deneme Kullanıcısı 7',
    email: 'trial-aabbccddeeff0011@deneme.invalid',
    login_name: null,
    role: 'site_manager',
    is_active: true,
    email_verified: true,
    approval_status: 'approved',
    phone_number: null,
    created_at: new Date(),
    password_hash: HASH,
    ...overrides,
  };
}

const futureIso = (ms = 3600_000) => new Date(Date.now() + ms).toISOString();
const trialContext = (overrides = {}) => ({
  code_id: 7,
  site_code: DEMO,
  expires_at: futureIso(),
  revoked_at: null,
  demo_site_code: String(DEMO),
  ...overrides,
});

async function run(method, url, row) {
  const originalQuery = pool.query;
  const queries = [];
  pool.query = async (text, params) => {
    queries.push({ text: String(text), params });
    return { rows: row ? [{ ...row }] : [], rowCount: row ? 1 : 0 };
  };
  try {
    const token = signAccessToken({ id: 20099 }, { passwordHash: HASH });
    const req = { headers: { authorization: `Bearer ${token}` }, method, originalUrl: url, url };
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

describe('authRequired + deneme oturumu ilkesi', () => {
  let savedSecret;
  beforeEach(() => {
    savedSecret = process.env.JWT_SECRET;
    process.env.JWT_SECRET = SECRET;
  });
  afterEach(() => {
    if (savedSecret === undefined) delete process.env.JWT_SECRET;
    else process.env.JWT_SECRET = savedSecret;
  });

  it('geçerli oturum + demo sitede yol: geçer; req.authUser.trial dolar, ham trial_context sızmaz', async () => {
    const { req, res, nextArg } = await run('GET', `/manager/sites/${DEMO}/structure`, userRow({ trial_context: trialContext() }));
    assert.equal(nextArg, undefined, JSON.stringify(res.body));
    assert.equal(req.authUser.trial.siteCode, DEMO);
    assert.equal(req.authUser.trial.codeId, 7);
    assert.ok(req.authUser.trial.expiresAt instanceof Date);
    assert.equal('trial_context' in req.authUser, false);
    assert.equal('password_hash' in req.authUser, false);
  });

  it('kapsam dışı site: 403 TRIAL_SCOPE_DENIED, next çağrılmaz, req.authUser atanmaz', async () => {
    for (const [method, url] of [
      ['GET', `/manager/sites/${OTHER}/finance/summary`],
      ['POST', `/manager/sites/${OTHER}/finance/expense-categories`],
      ['DELETE', `/manager/sites/${OTHER}`],
      ['GET', `/sites/${OTHER}/meter-field/meters`],
    ]) {
      const { req, res, nextArg } = await run(method, url, userRow({ trial_context: trialContext() }));
      assert.equal(res.statusCode, 403, `${method} ${url}`);
      assert.equal(res.body.code, 'TRIAL_SCOPE_DENIED');
      assert.equal(nextArg, 'not-called');
      assert.equal(req.authUser, undefined);
    }
  });

  it('kapalı işlem: 403 TRIAL_ACTION_DENIED (site açma, profil değiştirme, yönetici daveti)', async () => {
    for (const [method, url] of [
      ['POST', '/manager/sites'],
      ['PATCH', '/me'],
      ['POST', `/manager/sites/${DEMO}/managers/invite`],
      ['GET', '/admin/users'],
    ]) {
      const { res, nextArg } = await run(method, url, userRow({ trial_context: trialContext() }));
      assert.equal(res.statusCode, 403, `${method} ${url}`);
      assert.equal(res.body.code, 'TRIAL_ACTION_DENIED');
      assert.equal(nextArg, 'not-called');
    }
  });

  it('süre dolumu / iptal / demo değişimi: 401 (istemci oturumu kapatır); pasif hesapta bile 403 değil açıklayıcı 401', async () => {
    const expired = await run('GET', '/me', userRow({ trial_context: trialContext({ expires_at: new Date(Date.now() - 1000).toISOString() }) }));
    assert.equal(expired.res.statusCode, 401);
    assert.equal(expired.res.body.code, 'TRIAL_EXPIRED');
    assert.match(expired.res.body.error, /Deneme süreniz doldu/);
    assert.equal(expired.nextArg, 'not-called');

    const revoked = await run('GET', '/me', userRow({ trial_context: trialContext({ revoked_at: new Date().toISOString() }) }));
    assert.equal(revoked.res.statusCode, 401);
    assert.equal(revoked.res.body.code, 'TRIAL_REVOKED');

    for (const demo of [null, String(OTHER)]) {
      const moved = await run('GET', '/me', userRow({ trial_context: trialContext({ demo_site_code: demo }) }));
      assert.equal(moved.res.statusCode, 401, String(demo));
      assert.equal(moved.res.body.code, 'TRIAL_REVOKED');
    }

    // hesap kapatıldıktan sonra (is_active=false) da mesaj "Hesap aktif değil" değil, deneme süresi
    const closed = await run('GET', '/me', userRow({ is_active: false, trial_context: trialContext({ expires_at: new Date(Date.now() - 1000).toISOString() }) }));
    assert.equal(closed.res.statusCode, 401);
    assert.equal(closed.res.body.code, 'TRIAL_EXPIRED');
  });

  it('bozuk / eksik deneme bilgisi güvenli tarafta biter (401)', async () => {
    for (const ctx of [trialContext({ expires_at: null }), trialContext({ expires_at: 'bozuk' }), trialContext({ site_code: null })]) {
      const { res, nextArg } = await run('GET', '/me', userRow({ trial_context: ctx }));
      assert.ok([401, 403].includes(res.statusCode), JSON.stringify(ctx));
      assert.equal(nextArg, 'not-called');
    }
  });

  it('parola sürümü (pv) uyuşmuyorsa önce TOKEN_REVOKED (deneme ilkesinden önce)', async () => {
    const { res } = await run('GET', '/me', userRow({ password_hash: '$2a$10$BBBBBBBBBBBBBBBBBBBBBB', trial_context: trialContext() }));
    assert.equal(res.statusCode, 401);
    assert.equal(res.body.code, 'TOKEN_REVOKED');
  });

  it('deneme olmayan hesap etkilenmez: trial_context null ya da alan hiç yok -> mevcut davranış', async () => {
    for (const extra of [{ trial_context: null }, {}]) {
      const { req, nextArg } = await run('PATCH', `/manager/sites/${OTHER}`, userRow({ role: 'individual', email: 'ali@example.com', ...extra }));
      assert.equal(nextArg, undefined);
      assert.equal(req.authUser.trial, undefined);
    }
  });

  it('YETİM deneme hesabı: kod satırı yok (demo site silindi, CASCADE) ama e-posta @deneme.invalid -> sıradan yönetici gibi çalışamaz, 401 TRIAL_REVOKED', async () => {
    for (const extra of [{ trial_context: null }, {}]) {
      for (const [method, url] of [['GET', '/me'], ['POST', '/manager/sites'], ['POST', '/membership/setup-site']]) {
        const { res, nextArg } = await run(method, url, userRow({ email: 'trial-0011223344556677@DENEME.invalid', ...extra }));
        assert.equal(res.statusCode, 401, `${method} ${url}`);
        assert.equal(res.body.code, 'TRIAL_REVOKED');
        assert.equal(nextArg, 'not-called');
      }
    }
    // benzer görünen ama ayrılmış alan adında olmayan adres etkilenmez
    for (const email of ['trial-aa@deneme.invalid.example.com', 'x@deneme.com', 'deneme.invalid@example.com']) {
      const { nextArg } = await run('GET', '/me', userRow({ role: 'individual', email, trial_context: null }));
      assert.equal(nextArg, undefined, email);
    }
  });

  it('sorgu: tek kullanıcı sorgusu, deneme bağlamı demo site anahtarıyla birlikte aynı sorguda okunur', async () => {
    const { queries } = await run('GET', '/me', userRow({ trial_context: trialContext() }));
    assert.equal(queries.length, 1, 'ek gidiş-dönüş yok');
    assert.match(queries[0].text, /FROM trial_access_codes tac/);
    assert.match(queries[0].text, /tac\.used_by = users\.user_code/);
    assert.ok(queries[0].text.includes(`ps.key = '${DEMO_SITE_SETTING_KEY}'`));
    assert.deepEqual(queries[0].params, [20099]);
  });

  it('mapUserRow: deneme alanları yalnız deneme hesabında', () => {
    const plain = mapUserRow(userRow({ role: 'individual' }));
    assert.equal('trial_expires_at' in plain, false);
    assert.equal('trial_site_code' in plain, false);
    assert.equal('is_trial' in plain, false);
    const trial = mapUserRow({ ...userRow(), trial: { codeId: 7, siteCode: DEMO, expiresAt: new Date('2026-11-01T10:00:00Z') } });
    assert.equal(trial.is_trial, true);
    assert.equal(trial.trial_expires_at, '2026-11-01T10:00:00.000Z');
    assert.equal(trial.trial_site_code, DEMO);
    assert.equal(mapUserRow({ ...userRow(), trial: { siteCode: DEMO, expiresAt: 'bozuk' } }).trial_expires_at, null);
  });
});

describe('rota tablosu taraması: gerçek server.js uygulaması', () => {
  let routes = [];

  before(async () => {
    process.env.SERVER_SKIP_START = '1';
    process.env.JWT_SECRET = process.env.JWT_SECRET || SECRET;
    const { app } = await import('../src/server.js');
    const found = [];
    const walk = (stack) => {
      for (const layer of stack) {
        if (layer.route) {
          const names = layer.route.stack.map((entry) => entry.name || entry.handle?.name || '');
          const paths = Array.isArray(layer.route.path) ? layer.route.path : [layer.route.path];
          for (const pattern of paths) {
            for (const method of Object.keys(layer.route.methods).filter((m) => layer.route.methods[m])) {
              found.push({ method: method.toUpperCase(), pattern, names });
            }
          }
        } else if (layer.name === 'router' && layer.handle?.stack) {
          walk(layer.handle.stack);
        }
      }
    };
    walk(app._router.stack);
    // kimlikli rota: authRequired ya da (toplu yükleme kapılarındaki) authOnce / parseStep
    routes = found.filter(
      (r) => r.names.includes('authRequired') || r.names.includes('authOnce') || /^\/manager\/sites\/:siteCode\/(imports|exports)\//.test(r.pattern),
    );
  });

  const concrete = (pattern, siteCode) => {
    const segs = pattern.split('/');
    return segs.map((s, i) => (!s.startsWith(':') ? s : segs[i - 1] === 'sites' ? String(siteCode) : '1')).join('/');
  };
  const trial = { siteCode: DEMO, expiresAt: new Date(Date.now() + 3600_000) };
  const verdictOf = (route, siteCode = DEMO) =>
    evaluateTrialRequest({ trial, demoSiteCode: DEMO, method: route.method, path: concrete(route.pattern, siteCode) });
  const label = (route) => `${route.method} ${route.pattern}`;
  const firstSeg = (route) => route.pattern.split('/')[1];

  it('tarama anlamlı: yüzlerce kimlikli rota bulundu, bir kısmı açık bir kısmı kapalı', () => {
    assert.ok(routes.length > 450, `kimlikli rota sayısı: ${routes.length}`);
    const allowed = routes.filter((r) => verdictOf(r).ok);
    assert.ok(allowed.length > 150, `açık rota sayısı: ${allowed.length}`);
    assert.ok(allowed.length < routes.length * 0.8, 'açık küme tüm tablo olamaz');
    assert.ok(routes.some((r) => r.pattern === '/manager/sites/:siteCode/imports/:kind/commit'), 'toplu yükleme kapıları taramada');
    assert.ok(routes.some((r) => r.pattern === '/manager/sites/:siteCode/trial-access/codes'));
  });

  it('DEMO DIŞI SİTE: site parametresi taşıyan HER kimlikli rota için istek 403 olur (hiçbir yöntem / alt yol geçmez)', () => {
    const siteScoped = routes.filter((r) => /\/sites\/:/.test(r.pattern));
    assert.ok(siteScoped.length > 350);
    const leaks = siteScoped.filter((r) => {
      const verdict = verdictOf(r, OTHER);
      return verdict.ok || verdict.status !== 403;
    });
    assert.deepEqual(leaks.map(label), []);
  });

  it('site parametresi olmayan ve demo ile ilgisiz aileler (admin, şirket, tema, cihaz) tamamen kapalı', () => {
    const closed = routes.filter((r) => ['admin', 'companies', 'brand-themes', 'device'].includes(firstSeg(r)));
    assert.ok(closed.length >= 60);
    assert.deepEqual(closed.filter((r) => verdictOf(r).ok).map(label), []);
  });

  it('açık kümenin ilk parçası yalnız me | app | manager | sites | membership | brand-theme', () => {
    const allowedRoots = new Set(['me', 'app', 'manager', 'sites', 'membership', 'brand-theme']);
    const stray = routes.filter((r) => verdictOf(r).ok && !allowedRoots.has(firstSeg(r)));
    assert.deepEqual(stray.map(label), []);
  });

  it('/manager altında site kodu taşımayan rotalar: yalnız GET /manager/sites | /manager/devices | /manager/door-logs açık', () => {
    const nonSite = routes.filter((r) => firstSeg(r) === 'manager' && !/^\/manager\/sites\/:/.test(r.pattern));
    assert.ok(nonSite.length >= 20);
    const open = nonSite.filter((r) => verdictOf(r).ok).map(label).sort();
    assert.deepEqual(open, ['GET /manager/devices', 'GET /manager/door-logs', 'GET /manager/sites']);
  });

  it('/membership altında yalnız salt-okunur kendi-kapsamlı uçlar açık; site kurma / cihaz sahiplenme / katılım / başvuru kapalı', () => {
    const membership = routes.filter((r) => firstSeg(r) === 'membership');
    const open = membership.filter((r) => verdictOf(r).ok).map(label).sort();
    assert.deepEqual(open, [
      'GET /membership/my-apartments',
      'GET /membership/my-devices',
      'GET /membership/my-join-requests',
      'GET /membership/site-applications/mine',
      'GET /membership/sites/:id/residents-tree',
    ]);
    for (const dangerous of ['POST /membership/setup-site', 'POST /membership/claim-device', 'POST /membership/join-request', 'POST /membership/site-applications']) {
      assert.ok(membership.some((r) => label(r) === dangerous), `${dangerous} rota tablosunda olmalı`);
    }
  });

  it('/me: yalnız GET /me ve GET|POST /me/consents açık', () => {
    const me = routes.filter((r) => firstSeg(r) === 'me');
    assert.deepEqual(me.filter((r) => verdictOf(r).ok).map(label).sort(), ['GET /me', 'GET /me/consents', 'POST /me/consents']);
  });

  it('/app: kapı komutu, misafir geçişi ve davet kabulü (okuma dışı) kapalı', () => {
    const app = routes.filter((r) => firstSeg(r) === 'app');
    const guarded = app.filter(
      (r) => r.method !== 'GET' && /^\/app\/(doors|guest-passes|invitations)(\/|$)/.test(r.pattern),
    );
    assert.ok(guarded.length >= 8, `korunan sakin yazma uçları: ${guarded.length}`);
    assert.deepEqual(guarded.filter((r) => verdictOf(r).ok).map(label), []);
  });

  it('TEHLİKELİ UÇLAR (yeni site / yönetici daveti / e-posta-SMS / hesap üretimi / donanım / platform arama) rota tablosunda VAR ve KAPALI', () => {
    const mustBeClosed = [
      'POST /manager/sites',
      'PATCH /manager/sites/:id',
      'DELETE /manager/sites/:id',
      'PATCH /manager/sites/:id/security-policy',
      'GET /manager/sites/:id/join-token',
      'POST /manager/sites/:id/join-token/rotate',
      'GET /manager/sites/:siteCode/managers',
      'POST /manager/sites/:siteCode/managers/invite',
      'DELETE /manager/sites/:siteCode/managers/:userCode',
      'POST /manager/sites/:siteCode/doors',
      'GET /manager/sites/:siteCode/assignable-devices',
      'POST /manager/sites/:siteCode/cameras',
      'POST /manager/sites/:siteCode/cctv/cameras',
      'GET /manager/sites/:siteCode/cctv/cameras/:id/snapshot',
      'PUT /manager/sites/:siteCode/staff-roles',
      'DELETE /manager/sites/:siteCode/staff-roles/:userCode',
      'POST /manager/sites/:siteCode/people/bulk-actions',
      'POST /manager/sites/:siteCode/people/:personId/invitation',
      'POST /manager/sites/:siteCode/people/:personId/password-reset',
      'POST /manager/sites/:siteCode/people/:personId/account',
      'POST /manager/sites/:siteCode/people/:personId/reset-pin',
      'POST /manager/sites/:siteCode/finance/reminders/send',
      'POST /manager/sites/:siteCode/imports/:kind/commit',
      'POST /manager/sites/:siteCode/imports/:kind/accounts',
      'POST /manager/sites/:siteCode/imports/login-names/check',
      'POST /manager/sites/:siteCode/module-requests',
      'POST /manager/sites/:siteCode/drive/connect',
      'PUT /manager/sites/:siteCode/card-payments/:provider',
      'POST /manager/sites/:siteCode/access-cards',
      'POST /manager/sites/:siteCode/quote-requests',
      'POST /manager/sites/:siteCode/quote-requests/:id/approve',
      'PUT /manager/sites/:siteCode/modules/:moduleCode',
      'POST /manager/sites/:siteCode/trial-access/codes',
      'DELETE /manager/sites/:siteCode/trial-access/codes/:id',
      'PUT /manager/sites/:siteCode/trial-access/demo',
      'GET /manager/sites/:siteCode/trial-access',
      'PATCH /me',
      'POST /me/account-deletion',
      'POST /me/data-export',
      'POST /app/doors/:id/open',
      'POST /app/guest-passes',
    ];
    const index = new Map(routes.map((r) => [label(r), r]));
    const missing = mustBeClosed.filter((l) => !index.has(l));
    assert.deepEqual(missing, [], 'rota yeniden adlandırılmış olabilir: ilke gözden geçirilmeli');
    assert.deepEqual(mustBeClosed.filter((l) => verdictOf(index.get(l)).ok), []);
  });

  // YENİ ROTA AİLESİ ALARMI: başka dalgalar / işler yeni rota ailesi eklediğinde (ör. kurulum sihirbazı, acil yardım, geri bildirim) deneme ilkesi
  // onu sessizce AÇIK bırakmasın: aile ya demo site alt ağacında kendiliğinden açık sayılır ya da genel kural kapatır. İlkeyi
  // (modules/trial_access_common.js) gözden geçirin; dış etkisi (e-posta / SMS / donanım / hesap üretimi / platform genelinde sorgu) varsa
  // SITE_DENIED_FIRST / SITE_READ_ONLY_FIRST ya da alt yol kuralına ekleyin; SONRA aşağıdaki listeye ekleyin.
  const REVIEWED = {
    top: ['admin', 'app', 'brand-theme', 'brand-themes', 'companies', 'device', 'manager', 'me', 'membership', 'sites'],
    managerOther: ['apartments', 'devices', 'door-logs', 'doors', 'join-requests'],
    siteFirst: [
      '(kök)', 'access-cards', 'announcements', 'annual-report', 'apartments', 'approve-deletion', 'assignable-devices', 'audit-log', 'budget-projects', 'cameras',
      'card-payments', 'cctv', 'concierge-requests', 'contract-vendors', 'contracts', 'decisions', 'directory', 'documents', 'doors', 'drive', 'emergency', 'equipment',
      'exports', 'feedback', 'finance', 'history', 'imports', 'invitations', 'join-requests', 'join-token', 'managers', 'meter-apartments', 'meter-billings',
      'meter-readings', 'menu-layout', 'meters', 'module-requests', 'modules', 'neighbor-board', 'people', 'plate-events', 'plate-recognition', 'quote-requests', 'quotes',
      'reject-deletion', 'reservation-areas', 'reservations', 'residencies', 'residency-log', 'rules', 'safety-requests', 'security-policy',
      'signing-roster', 'staff-roles', 'structure', 'surveys', 'team', 'trial-access', 'vehicles', 'visitor-entries', 'work-categories', 'work-items',
    ],
    app: [
      'access-cards', 'announcements', 'apartments', 'concierge-requests', 'decisions', 'directory', 'documents', 'doors', 'emergency', 'feedback', 'guest-passes', 'invitations',
      'management-types', 'manager-contact', 'modules', 'my-doors', 'my-finance', 'my-modules', 'my-records', 'neighbor-board', 'notification-preferences', 'notifications',
      'plate-permits', 'push', 'reservation-areas', 'reservations', 'surveys', 'visitor-entries', 'web-push', 'work-categories', 'work-items',
    ],
    membership: ['apartments', 'claim-device', 'doors', 'join-info', 'join-request', 'my-apartments', 'my-devices', 'my-join-requests', 'setup-site', 'site-applications', 'sites'],
    me: ['account-deletion', 'consents', 'data-export'],
  };

  it('YENİ ROTA AİLESİ ALARMI: kimlikli rota aileleri gözden geçirilmiş listede (yeni aile eklenirse deneme ilkesi önce karara bağlanmalı)', () => {
    const found = { top: new Set(), managerOther: new Set(), siteFirst: new Set(), app: new Set(), membership: new Set(), me: new Set() };
    for (const route of routes) {
      const segs = route.pattern.split('/').filter(Boolean);
      found.top.add(segs[0]);
      if (segs[0] === 'manager' && segs[1] === 'sites' && segs[2]?.startsWith(':')) found.siteFirst.add(segs[3] ?? '(kök)');
      else if (segs[0] === 'manager' && segs[1] !== 'sites') found.managerOther.add(segs[1]);
      if (segs[0] === 'app') found.app.add(segs[1]);
      if (segs[0] === 'membership') found.membership.add(segs[1]);
      if (segs[0] === 'me' && segs[1]) found.me.add(segs[1]);
    }
    for (const [group, reviewed] of Object.entries(REVIEWED)) {
      const unknown = [...found[group]].filter((name) => !reviewed.includes(name)).sort();
      assert.deepEqual(unknown, [], `${group}: yeni rota ailesi — deneme ilkesine karar verip listeye ekleyin`);
    }
  });

  it('demo sitenin kendi verisindeki temel ekran uçları AÇIK (deneme anlamlı çalışır)', () => {
    const mustBeOpen = [
      'GET /manager/sites',
      'GET /manager/sites/:id/structure',
      'GET /manager/sites/:siteCode/finance/summary',
      'POST /manager/sites/:siteCode/finance/payments',
      'POST /manager/sites/:siteCode/finance/charges',
      'POST /manager/sites/:siteCode/announcements',
      'POST /manager/sites/:siteCode/announcements/:id/publish',
      'POST /manager/sites/:siteCode/people',
      'GET /manager/sites/:siteCode/people',
      'GET /manager/sites/:siteCode/apartments',
      'PATCH /manager/sites/:siteCode/apartments/:apartmentId',
      'GET /manager/sites/:siteCode/work-items',
      'POST /manager/sites/:siteCode/surveys',
      'GET /manager/sites/:siteCode/documents',
      'POST /manager/sites/:siteCode/imports/:kind/preview',
      'GET /manager/sites/:siteCode/exports/:kind',
      'GET /app/my-modules',
      'GET /app/announcements',
      // Dalga E (birleştirme kararı): acil durum bilgisi ve site işlem kayıtları demo sitenin KENDİ verisidir; dış etkisi (e-posta / SMS / donanım /
      // hesap üretimi / platform genelinde sorgu) yoktur: bakım firması adı + telefonu yalnız kaydedilir, işlem kaydı yalnız okunur ve site kapsamlıdır.
      'GET /app/emergency',
      'PUT /manager/sites/:siteCode/emergency',
      'GET /manager/sites/:siteCode/audit-log',
    ];
    const index = new Map(routes.map((r) => [label(r), r]));
    const missing = mustBeOpen.filter((l) => !index.has(l));
    assert.deepEqual(missing, []);
    assert.deepEqual(mustBeOpen.filter((l) => !verdictOf(index.get(l)).ok), []);
  });
});
