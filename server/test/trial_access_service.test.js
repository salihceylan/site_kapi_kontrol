// Deneme erişim kodu hizmeti + uçları (sahte, bellek içi veritabanı; gerçek PostgreSQL kanıtı: trial_access_pg.test.js).
// Kapsam: kod üretimi (düz kod yalnız yanıtta, özet saklanır), kullanım (tek kullanım, ikinci kullanım ret, süre dolumu, iptal, kapalı demo,
// geri alma), 72 saatlik oturum + JWT ömrü, hesap özellikleri, kaba kuvvet hız sınırı, uç yetkileri.
import { describe, it, before, after, beforeEach, afterEach, mock } from 'node:test';
import assert from 'node:assert/strict';
import express from 'express';
import jwt from 'jsonwebtoken';
import { pool } from '../src/db.js';
import { authRequired, requireSiteManager, requireSuperUser } from '../src/middlewares/auth_middleware.js';
import {
  TRIAL_MAX_ACTIVE_CODES,
  TRIAL_SESSION_HOURS,
  hashTrialCode,
  normalizeTrialCode,
} from '../src/modules/trial_access_common.js';
import {
  closeExpiredTrialAccounts,
  createTrialCode,
  redeemTrialCode,
  revokeTrialCode,
  setDemoSite,
  trialCodeStatus,
} from '../src/modules/trial_access_service.js';
import { redeemLimiter, trialAccessRouter, trialAdminLimiter } from '../src/modules/trial_access_routes.js';
import { isBcryptHash } from '../src/security/login_guard.js';

const SECRET = 'trial-service-test-secret-0123456789abcdef0123456789';
const DEMO = 4000000001;
const norm = (text) => String(text).replace(/\s+/g, ' ').trim();
const ok = (rows = [], rowCount = rows.length) => ({ rows, rowCount });

/** Bellek içi sahte veritabanı: yalnız bu hizmetin SQL'lerini canlandırır; BEGIN/ROLLBACK'te durum anlık görüntüsü geri yüklenir. */
function createFakeDb(initial = {}) {
  const state = {
    demoSite: DEMO,
    sites: new Map([[DEMO, { name: 'Örnek Demo Sitesi', approval_status: 'approved' }]]),
    codes: [],
    users: [],
    links: [],
    members: [],
    audits: [],
    nextCodeId: 1,
    nextUserCode: 20001,
    failOn: null,
    ...initial,
  };
  let snapshot = null;
  const log = [];
  const handle = async (text, params = []) => {
    const sql = norm(text);
    log.push({ sql, params });
    if (state.failOn && state.failOn.test(sql)) throw new Error('simulated failure');
    if (sql === 'BEGIN') {
      snapshot = structuredClone({ codes: state.codes, users: state.users, links: state.links, members: state.members, audits: state.audits, nextCodeId: state.nextCodeId, nextUserCode: state.nextUserCode });
      return ok();
    }
    if (sql === 'COMMIT') {
      snapshot = null;
      return ok();
    }
    if (sql === 'ROLLBACK') {
      if (snapshot) Object.assign(state, snapshot);
      snapshot = null;
      return ok();
    }
    if (/^(SAVEPOINT|RELEASE SAVEPOINT|ROLLBACK TO SAVEPOINT)/.test(sql)) return ok();
    if (/^INSERT INTO audit_log/.test(sql)) {
      state.audits.push({ action: params[3], site_code: params[4], target_id: params[6], details: JSON.parse(params[7]) });
      return ok([], 1);
    }
    if (/^SELECT value->>'site_code' AS site_code FROM platform_settings/.test(sql)) {
      return ok(state.demoSite ? [{ site_code: String(state.demoSite) }] : []);
    }
    if (/^INSERT INTO platform_settings/.test(sql)) {
      state.demoSite = Number(params[1]);
      return ok([], 1);
    }
    if (/^DELETE FROM platform_settings/.test(sql)) {
      if (state.demoSite && String(state.demoSite) === params[1]) {
        state.demoSite = null;
        return ok([{ key: params[0] }], 1);
      }
      return ok([], 0);
    }
    if (/^SELECT site_code, name, approval_status FROM sites/.test(sql)) {
      const site = state.sites.get(Number(params[0]));
      return ok(site ? [{ site_code: params[0], ...site }] : []);
    }
    if (/^SELECT site_code, name FROM sites WHERE site_code = \$1 AND approval_status = 'approved'/.test(sql)) {
      const site = state.sites.get(Number(params[0]));
      return ok(site && site.approval_status === 'approved' ? [{ site_code: params[0], name: site.name }] : []);
    }
    if (/^WITH closing AS/.test(sql)) {
      const now = Date.now();
      const closing = state.codes.filter((c) => c.used_by && !c.closed_at && (new Date(c.session_expires_at).getTime() <= now || c.revoked_at));
      for (const c of closing) {
        c.closed_at = new Date();
        const user = state.users.find((u) => u.id === c.used_by);
        if (user && user.email.endsWith('@deneme.invalid')) user.is_active = false;
        state.links = state.links.filter((l) => !(l.user === c.used_by && l.site === c.site_code));
        state.members.filter((m) => m.user === c.used_by && m.site === c.site_code).forEach((m) => { m.is_active = false; });
      }
      return ok([{ closed: closing.length }]);
    }
    if (/^SELECT COUNT\(\*\)::int AS n FROM trial_access_codes WHERE used_at IS NULL AND revoked_at IS NULL AND expires_at > NOW\(\)/.test(sql)) {
      const now = Date.now();
      return ok([{ n: state.codes.filter((c) => !c.used_at && !c.revoked_at && new Date(c.expires_at).getTime() > now).length }]);
    }
    if (/^INSERT INTO trial_access_codes/.test(sql)) {
      const [hash, hint, site, createdBy, days, note] = params;
      if (state.codes.some((c) => c.code_hash === hash)) return ok([], 0);
      const row = {
        id: state.nextCodeId++, code_hash: hash, code_hint: hint, site_code: Number(site), created_by: createdBy, created_at: new Date(),
        expires_at: new Date(Date.now() + days * 86400000), note, used_by: null, used_at: null, session_expires_at: null, revoked_at: null, closed_at: null,
      };
      state.codes.push(row);
      return ok([{ ...row }], 1);
    }
    if (/^UPDATE trial_access_codes SET used_at = NOW\(\)/.test(sql)) {
      const [hash, hours, site] = params;
      const row = state.codes.find((c) => c.code_hash === hash);
      if (!row || row.used_at || row.revoked_at || new Date(row.expires_at).getTime() <= Date.now() || site === null || row.site_code !== Number(site)) return ok([], 0);
      row.used_at = new Date();
      row.session_expires_at = new Date(Date.now() + hours * 3600000);
      return ok([{ id: row.id, site_code: row.site_code, session_expires_at: row.session_expires_at }], 1);
    }
    if (/^SELECT used_at, revoked_at, expires_at FROM trial_access_codes WHERE code_hash = \$1/.test(sql)) {
      const row = state.codes.find((c) => c.code_hash === params[0]);
      return ok(row ? [{ used_at: row.used_at, revoked_at: row.revoked_at, expires_at: row.expires_at }] : []);
    }
    if (/^INSERT INTO users/.test(sql)) {
      const user = {
        id: state.nextUserCode++, full_name: params[0], email: params[1], login_name: null, role: 'site_manager', is_active: true, email_verified: true,
        approval_status: 'approved', phone_number: null, created_at: new Date(), password_hash: params[2],
      };
      state.users.push(user);
      const { password_hash: _hash, ...visible } = user;
      return ok([visible], 1);
    }
    if (/^INSERT INTO site_manager_sites/.test(sql)) {
      state.links.push({ site: Number(params[0]), user: params[1] });
      return ok([], 1);
    }
    if (/^INSERT INTO site_memberships/.test(sql)) {
      state.members.push({ site: Number(params[0]), user: params[1], role: 'SITE_ADMIN', is_active: true });
      return ok([], 1);
    }
    if (/^UPDATE trial_access_codes SET used_by = \$1 WHERE id = \$2/.test(sql)) {
      state.codes.find((c) => c.id === params[1]).used_by = params[0];
      return ok([], 1);
    }
    if (/^UPDATE trial_access_codes SET revoked_at = COALESCE/.test(sql)) {
      const row = state.codes.find((c) => c.id === params[0] && c.site_code === Number(params[1]));
      if (!row) return ok([], 0);
      row.revoked_at = row.revoked_at ?? new Date();
      return ok([{ ...row }], 1);
    }
    if (/^SELECT t\.id, t\.code_hint/.test(sql)) {
      return ok(state.codes.filter((c) => c.site_code === Number(params[0])).map((c) => ({ ...c, created_by_name: 'Sahip' })).reverse());
    }
    if (/^SELECT site_code FROM sites WHERE site_code = \$1/.test(sql)) {
      return ok(state.sites.has(Number(params[0])) ? [{ site_code: params[0] }] : []);
    }
    throw new Error(`SAHTE VERITABANI: tanimsiz SQL: ${sql}`);
  };
  const client = { query: handle, release() {} };
  return { state, log, query: handle, connect: async () => client };
}

const actor = { id: 1, user_code: 1, role: 'super_user', full_name: 'Sahip' };

describe('deneme erişim kodu hizmeti (sahte veritabanı)', () => {
  let savedSecret;
  beforeEach(() => {
    savedSecret = process.env.JWT_SECRET;
    process.env.JWT_SECRET = SECRET;
    mock.method(console, 'error', () => {});
  });
  afterEach(() => {
    mock.restoreAll();
    if (savedSecret === undefined) delete process.env.JWT_SECRET;
    else process.env.JWT_SECRET = savedSecret;
  });

  it('kod üretimi: düz kod yalnız yanıtta; veritabanında HMAC özeti + son 4 karakter; denetim kaydı düz kod taşımaz', async () => {
    const db = createFakeDb();
    const created = await createTrialCode({ siteCode: DEMO, note: '  Ahmet   Bey ', validDays: 7, actor, db });
    assert.match(created.code, /^[2-9A-HJKMNP-Z]{4}-[2-9A-HJKMNP-Z]{4}-[2-9A-HJKMNP-Z]{4}$/);
    const flat = normalizeTrialCode(created.code);
    assert.equal(db.state.codes.length, 1);
    const row = db.state.codes[0];
    assert.equal(row.code_hash, hashTrialCode(flat));
    assert.equal(row.code_hint, flat.slice(-4));
    assert.equal(row.note, 'Ahmet Bey');
    assert.equal(created.item.status, 'active');
    assert.equal(created.item.hint, flat.slice(-4));
    assert.ok(Math.abs(new Date(created.item.expires_at) - Date.now() - 7 * 86400000) < 5000);
    assert.equal(JSON.stringify(db.state.codes).includes(flat), false);
    assert.equal(JSON.stringify(db.state.audits).includes(flat), false);
    assert.equal(db.state.audits[0].action, 'trial_access.code_created');
    assert.equal('code_hash' in created.item, false, 'özet yanıta sızmaz');
  });

  it('kod üretimi: demo olmayan site 409; geçersiz süre / not 400; 100 bekleyen kod sınırı 409', async () => {
    const db = createFakeDb({ demoSite: null });
    await assert.rejects(createTrialCode({ siteCode: DEMO, actor, db }), (e) => e.code === 'NOT_DEMO_SITE' && e.statusCode === 409);
    db.state.demoSite = DEMO;
    for (const validDays of [0, -1, 61, 1.5, 'abc']) {
      await assert.rejects(createTrialCode({ siteCode: DEMO, validDays, actor, db }), (e) => e.code === 'INVALID_BODY' && e.statusCode === 400, String(validDays));
    }
    await assert.rejects(createTrialCode({ siteCode: DEMO, note: 'x'.repeat(201), actor, db }), (e) => e.code === 'INVALID_BODY');
    await assert.rejects(createTrialCode({ siteCode: DEMO, note: 42, actor, db }), (e) => e.code === 'INVALID_BODY');
    for (let i = 0; i < TRIAL_MAX_ACTIVE_CODES; i += 1) {
      db.state.codes.push({ id: 1000 + i, code_hash: `h${i}`, code_hint: 'ABCD', site_code: DEMO, expires_at: new Date(Date.now() + 86400000), used_at: null, revoked_at: null });
    }
    await assert.rejects(createTrialCode({ siteCode: DEMO, actor, db }), (e) => e.code === 'TOO_MANY_ACTIVE_CODES' && e.statusCode === 409);
  });

  it('kullanım: 72 saatlik oturum, rol site_manager, tek bağ demo site, parola özeti bcrypt DEĞİL, JWT ömrü <= 72 saat', async () => {
    const db = createFakeDb();
    const { code } = await createTrialCode({ siteCode: DEMO, actor, db });
    const result = await redeemTrialCode({ code: code.toLowerCase().replace(/-/g, ' '), db });
    assert.equal(result.user.role, 'site_manager');
    assert.match(result.user.email, /^trial-[0-9a-f]{16}@deneme\.invalid$/);
    assert.match(result.user.full_name, /^Deneme Kullanıcısı 1$/);
    assert.equal(result.trial.session_hours, TRIAL_SESSION_HOURS);
    assert.equal(result.trial.site_code, DEMO);
    assert.equal(result.trial.site_name, 'Örnek Demo Sitesi');
    assert.equal(result.user.trial_site_code, DEMO);
    assert.equal(result.user.trial_expires_at, result.trial.expires_at);
    assert.equal(JSON.stringify(result).includes('password_hash'), false);
    assert.equal(JSON.stringify(result).includes('!trial:'), false);
    const user = db.state.users[0];
    assert.equal(isBcryptHash(user.password_hash), false, 'hiçbir parolayla eşleşmez');
    assert.equal(user.is_active, true);
    assert.deepEqual(db.state.links, [{ site: DEMO, user: user.id }]);
    assert.deepEqual(db.state.members, [{ site: DEMO, user: user.id, role: 'SITE_ADMIN', is_active: true }]);
    const claims = jwt.decode(result.token);
    assert.equal(String(claims.sub), String(user.id));
    assert.ok(claims.exp - claims.iat <= 72 * 3600 && claims.exp - claims.iat >= 72 * 3600 - 10);
    const seconds = (new Date(result.trial.expires_at) - Date.now()) / 1000;
    assert.ok(seconds > 72 * 3600 - 10 && seconds <= 72 * 3600);
    assert.equal(db.state.codes[0].used_by, user.id);
    assert.equal(db.state.audits.at(-1).action, 'trial_access.redeemed');
  });

  it('JWT ömrü yapılandırılmış ömürden uzun OLMAZ (JWT_EXPIRES_IN=1h iken deneme belirteci 1 saat)', async () => {
    const saved = process.env.JWT_EXPIRES_IN;
    process.env.JWT_EXPIRES_IN = '3600';
    try {
      const db = createFakeDb();
      const { code } = await createTrialCode({ siteCode: DEMO, actor, db });
      const result = await redeemTrialCode({ code, db });
      const claims = jwt.decode(result.token);
      assert.equal(claims.exp - claims.iat, 3600);
    } finally {
      if (saved === undefined) delete process.env.JWT_EXPIRES_IN;
      else process.env.JWT_EXPIRES_IN = saved;
    }
  });

  it('İKİNCİ KULLANIM reddedilir (401 TRIAL_CODE_USED); hesap sayısı artmaz', async () => {
    const db = createFakeDb();
    const { code } = await createTrialCode({ siteCode: DEMO, actor, db });
    await redeemTrialCode({ code, db });
    for (const variant of [code, code.toLowerCase(), code.replace(/-/g, '')]) {
      await assert.rejects(redeemTrialCode({ code: variant, db }), (e) => e.code === 'TRIAL_CODE_USED' && e.statusCode === 401);
    }
    assert.equal(db.state.users.length, 1);
  });

  it('geçersiz / biçimsiz kod: veritabanına hiç gidilmez ya da 401 TRIAL_CODE_INVALID; hiçbir kod yanmaz', async () => {
    const db = createFakeDb();
    const { code } = await createTrialCode({ siteCode: DEMO, actor, db });
    const queriesBefore = db.log.length;
    for (const bad of ['', 'kisa', '0000-0000-0000', 'ABCD-EFGH-JKM', null, undefined, 12345, {}, 'A'.repeat(100)]) {
      await assert.rejects(redeemTrialCode({ code: bad, db }), (e) => e.code === 'TRIAL_CODE_INVALID' && e.statusCode === 401, String(bad));
    }
    assert.equal(db.log.length, queriesBefore, 'biçimsiz kod için sorgu yok');
    await assert.rejects(redeemTrialCode({ code: 'ABCD-EFGH-JKMN', db }), (e) => e.code === 'TRIAL_CODE_INVALID');
    assert.equal(db.state.codes[0].used_at, null);
    assert.ok((await redeemTrialCode({ code, db })).token, 'asıl kod hâlâ kullanılabilir');
  });

  it('süresi dolmuş kod 401 TRIAL_CODE_EXPIRED; iptal edilmiş kod 401 TRIAL_CODE_REVOKED', async () => {
    const db = createFakeDb();
    const a = await createTrialCode({ siteCode: DEMO, actor, db });
    db.state.codes[0].expires_at = new Date(Date.now() - 1000);
    await assert.rejects(redeemTrialCode({ code: a.code, db }), (e) => e.code === 'TRIAL_CODE_EXPIRED');
    const b = await createTrialCode({ siteCode: DEMO, actor, db });
    await revokeTrialCode({ siteCode: DEMO, id: b.item.id, actor, db });
    await assert.rejects(redeemTrialCode({ code: b.code, db }), (e) => e.code === 'TRIAL_CODE_REVOKED');
    assert.equal(db.state.users.length, 0);
  });

  it('demo site yoksa ya da değiştiyse geçerli kod 503 TRIAL_UNAVAILABLE; kod yanmaz', async () => {
    const db = createFakeDb();
    const { code } = await createTrialCode({ siteCode: DEMO, actor, db });
    db.state.demoSite = null;
    await assert.rejects(redeemTrialCode({ code, db }), (e) => e.code === 'TRIAL_UNAVAILABLE' && e.statusCode === 503);
    db.state.demoSite = 4000000009;
    await assert.rejects(redeemTrialCode({ code, db }), (e) => e.code === 'TRIAL_UNAVAILABLE');
    assert.equal(db.state.codes[0].used_at, null);
    db.state.demoSite = DEMO;
    assert.ok((await redeemTrialCode({ code, db })).token);
  });

  it('hesap oluşturma başarısız olursa işlem geri alınır: kod yanmaz, yarım hesap kalmaz', async () => {
    const db = createFakeDb();
    const { code } = await createTrialCode({ siteCode: DEMO, actor, db });
    db.state.failOn = /^INSERT INTO site_memberships/;
    await assert.rejects(redeemTrialCode({ code, db }), /simulated failure/);
    db.state.failOn = null;
    assert.equal(db.state.codes[0].used_at, null);
    assert.equal(db.state.users.length, 0);
    assert.equal(db.state.links.length, 0);
    assert.ok(db.log.some((l) => l.sql === 'ROLLBACK'));
    assert.ok((await redeemTrialCode({ code, db })).token);
  });

  it('süre dolumu / iptal: closeExpiredTrialAccounts hesabı pasife alır, yönetici bağını siler, idempotenttir', async () => {
    const db = createFakeDb();
    const { code } = await createTrialCode({ siteCode: DEMO, actor, db });
    const session = await redeemTrialCode({ code, db });
    assert.equal(await closeExpiredTrialAccounts(db), 0, 'süre dolmadı');
    db.state.codes[0].session_expires_at = new Date(Date.now() - 1);
    assert.equal(await closeExpiredTrialAccounts(db), 1);
    const user = db.state.users.find((u) => u.id === session.user.id);
    assert.equal(user.is_active, false);
    assert.deepEqual(db.state.links, []);
    assert.equal(db.state.members[0].is_active, false);
    assert.equal(await closeExpiredTrialAccounts(db), 0);
  });

  it('süren oturumun kodu iptal edilince hesap hemen kapanır; durum "ended"', async () => {
    const db = createFakeDb();
    const { code, item } = await createTrialCode({ siteCode: DEMO, actor, db });
    await redeemTrialCode({ code, db });
    assert.equal(trialCodeStatus(db.state.codes[0]), 'in_use');
    const revoked = await revokeTrialCode({ siteCode: DEMO, id: item.id, actor, db });
    assert.equal(revoked.item.status, 'ended');
    assert.equal(db.state.users[0].is_active, false);
    assert.deepEqual(db.state.links, []);
    await assert.rejects(revokeTrialCode({ siteCode: DEMO, id: 99999, actor, db }), (e) => e.code === 'TRIAL_CODE_NOT_FOUND' && e.statusCode === 404);
    await assert.rejects(revokeTrialCode({ siteCode: DEMO, id: 'abc', actor, db }), (e) => e.code === 'TRIAL_CODE_NOT_FOUND');
    await assert.rejects(revokeTrialCode({ siteCode: 4000000009, id: item.id, actor, db }), (e) => e.code === 'TRIAL_CODE_NOT_FOUND', 'kod başka siteye ait');
  });

  it('trialCodeStatus: active | expired | revoked | in_use | ended', () => {
    const now = Date.now();
    const future = new Date(now + 1000);
    const past = new Date(now - 1000);
    assert.equal(trialCodeStatus({ expires_at: future }, now), 'active');
    assert.equal(trialCodeStatus({ expires_at: past }, now), 'expired');
    assert.equal(trialCodeStatus({ expires_at: future, revoked_at: past }, now), 'revoked');
    assert.equal(trialCodeStatus({ expires_at: future, used_at: past, session_expires_at: future }, now), 'in_use');
    assert.equal(trialCodeStatus({ expires_at: future, used_at: past, session_expires_at: past }, now), 'ended');
    assert.equal(trialCodeStatus({ expires_at: future, used_at: past, session_expires_at: future, revoked_at: past }, now), 'ended');
  });

  it('setDemoSite: onaylı site işaretlenir, onaysız 409, olmayan 404, gövde bool olmalı; kaldırma yalnız o site demo ise', async () => {
    const db = createFakeDb({ demoSite: null });
    db.state.sites.set(4000000002, { name: 'Bekleyen', approval_status: 'pending' });
    db.state.sites.set(4000000003, { name: 'Başka', approval_status: 'approved' });
    assert.deepEqual(await setDemoSite({ siteCode: DEMO, enabled: true, actor, db }), { site_code: DEMO, is_demo: true });
    await assert.rejects(setDemoSite({ siteCode: 4000000002, enabled: true, actor, db }), (e) => e.code === 'SITE_NOT_APPROVED' && e.statusCode === 409);
    await assert.rejects(setDemoSite({ siteCode: 4999999999, enabled: true, actor, db }), (e) => e.code === 'SITE_NOT_FOUND' && e.statusCode === 404);
    await assert.rejects(setDemoSite({ siteCode: DEMO, enabled: 'evet', actor, db }), (e) => e.code === 'INVALID_BODY');
    // başka bir site demo olunca öncekinin işareti kalkar (tek demo site)
    assert.equal((await setDemoSite({ siteCode: 4000000003, enabled: true, actor, db })).is_demo, true);
    assert.equal(db.state.demoSite, 4000000003);
    // demo olmayan siteyi "kaldır" demo işaretini bozmaz
    assert.equal((await setDemoSite({ siteCode: DEMO, enabled: false, actor, db })).is_demo, false);
    assert.equal(db.state.demoSite, 4000000003);
    assert.equal((await setDemoSite({ siteCode: 4000000003, enabled: false, actor, db })).is_demo, false);
    assert.equal(db.state.demoSite, null);
  });
});

describe('deneme erişim kodu uçları (HTTP, sahte veritabanı)', () => {
  const users = {
    superUser: { id: 1, user_code: 1, userCode: 1, role: 'super_user', full_name: 'Sahip', email: 'sahip@example.com' },
    demoManager: { id: 20010, user_code: 20010, userCode: 20010, role: 'site_manager', full_name: 'Demo Yöneticisi', email: 'd@example.com' },
    trial: { id: 20099, user_code: 20099, userCode: 20099, role: 'site_manager', full_name: 'Deneme Kullanıcısı 7', email: 'trial-aa@deneme.invalid', trial: { codeId: 7, siteCode: DEMO, expiresAt: new Date(Date.now() + 3600_000) } },
  };
  let db;
  let server;
  let baseUrl;
  let savedSecret;
  const originalChains = new Map();

  before(async () => {
    savedSecret = process.env.JWT_SECRET;
    process.env.JWT_SECRET = SECRET;
    for (const layer of trialAccessRouter.stack) {
      if (!layer.route) continue;
      originalChains.set(layer.route, layer.route.stack.map((entry) => entry.handle));
      for (const entry of layer.route.stack) {
        if (entry.handle === authRequired) {
          entry.handle = (req, res, next) => {
            const key = req.headers['x-test-user'];
            if (!key) return res.status(401).json({ error: 'Yetkisiz erisim.' });
            req.authUser = { ...users[key] };
            return next();
          };
        } else if (entry.handle === requireSiteManager) {
          entry.handle = (req, res, next) => (['site_manager', 'super_user'].includes(req.authUser?.role) ? next() : res.status(403).json({ error: 'site yoneticisi gerekir' }));
        }
      }
    }
    const app = express();
    app.use(express.json());
    app.use(trialAccessRouter);
    await new Promise((resolve) => {
      server = app.listen(0, '127.0.0.1', resolve);
    });
    baseUrl = `http://127.0.0.1:${server.address().port}`;
  });

  after(async () => {
    process.env.JWT_SECRET = savedSecret;
    server.closeAllConnections?.();
    await new Promise((resolve) => server.close(resolve));
    delete pool.query;
    delete pool.connect;
  });

  beforeEach(() => {
    db = createFakeDb();
    // resolveManagedSite -> hasSiteManagementAccess: süper her siteyi, demoManager yalnız DEMO'yu yönetir
    pool.query = async (text, params) => {
      const sql = norm(text);
      if (/^SELECT 1 FROM site_manager_sites WHERE site_code = \$1 AND manager_user_code = \$2/.test(sql)) {
        return ok(Number(params[0]) === DEMO && Number(params[1]) === users.demoManager.id ? [{ '?column?': 1 }] : []);
      }
      if (/^SELECT 1 FROM site_memberships/.test(sql)) return ok();
      return db.query(text, params);
    };
    pool.connect = db.connect;
    mock.method(console, 'error', () => {});
    mock.method(console, 'log', () => {});
  });
  afterEach(() => {
    mock.restoreAll();
    redeemLimiter.reset();
    trialAdminLimiter.reset();
  });

  const call = async (method, path, user, body) => {
    const response = await fetch(`${baseUrl}${path}`, {
      method,
      headers: { 'content-type': 'application/json', ...(user ? { 'x-test-user': user } : {}) },
      body: body === undefined ? undefined : JSON.stringify(body),
    });
    const text = await response.text();
    let json = null;
    try {
      json = JSON.parse(text);
    } catch (_error) {
      // JSON değil
    }
    return { status: response.status, json, text, headers: response.headers };
  };

  it('POST /auth/trial-access: kimliksiz çalışır; kod yok / metin değil 400; yanıt önbelleğe alınmaz', async () => {
    const created = await createTrialCode({ siteCode: DEMO, actor, db });
    const missing = await call('POST', '/auth/trial-access', undefined, {});
    assert.equal(missing.status, 400);
    assert.equal(missing.json.code, 'INVALID_BODY');
    assert.equal((await call('POST', '/auth/trial-access', undefined, { code: 123 })).status, 400);
    assert.equal((await call('POST', '/auth/trial-access', undefined, { code: '  ' })).status, 400);
    const success = await call('POST', '/auth/trial-access', undefined, { code: created.code });
    assert.equal(success.status, 200);
    assert.equal(success.headers.get('cache-control'), 'no-store');
    assert.ok(success.json.token);
    assert.equal(success.json.user.role, 'site_manager');
    assert.equal(success.json.trial.session_hours, 72);
    const again = await call('POST', '/auth/trial-access', undefined, { code: created.code });
    assert.equal(again.status, 401);
    assert.equal(again.json.code, 'TRIAL_CODE_USED');
    const wrong = await call('POST', '/auth/trial-access', undefined, { code: 'ABCD-EFGH-JKMN' });
    assert.equal(wrong.status, 401);
    assert.equal(wrong.json.code, 'TRIAL_CODE_INVALID');
  });

  it('KABA KUVVET: IP başına 15 dakikada 10 deneme; 11. istek 429 + Retry-After; doğru kod bile sınırdayken reddedilir', async () => {
    const created = await createTrialCode({ siteCode: DEMO, actor, db });
    const statuses = [];
    for (let i = 0; i < 12; i += 1) {
      const r = await call('POST', '/auth/trial-access', undefined, { code: 'ABCD-EFGH-JKMN' });
      statuses.push(r.status);
      if (i === 10) {
        assert.ok(Number(r.headers.get('retry-after')) > 0, 'Retry-After başlığı');
        assert.ok(r.json.retry_after_seconds > 0);
      }
    }
    assert.deepEqual(statuses, [...Array(10).fill(401), 429, 429]);
    const blocked = await call('POST', '/auth/trial-access', undefined, { code: created.code });
    assert.equal(blocked.status, 429);
    assert.equal(db.state.codes[0].used_at, null, 'sınır aşılmışken kod kullanılmaz');
    redeemLimiter.reset();
    assert.equal((await call('POST', '/auth/trial-access', undefined, { code: created.code })).status, 200);
  });

  it('yönetim uçları: kimliksiz 401; süper ve demo yöneticisi çalışır; deneme oturumu 403; başka site yöneticisi kapsam dışı', async () => {
    assert.equal((await call('GET', `/manager/sites/${DEMO}/trial-access`)).status, 401);
    assert.equal((await call('GET', `/manager/sites/${DEMO}/trial-access`, 'trial')).status, 403);
    const trialDenied = await call('POST', `/manager/sites/${DEMO}/trial-access/codes`, 'trial', {});
    assert.equal(trialDenied.status, 403);
    assert.equal(trialDenied.json.code, 'TRIAL_ACTION_DENIED');
    assert.equal((await call('DELETE', `/manager/sites/${DEMO}/trial-access/codes/1`, 'trial')).status, 403);
    assert.equal(db.state.codes.length, 0, 'deneme oturumu kod üretemez');

    const view = await call('GET', `/manager/sites/${DEMO}/trial-access`, 'demoManager');
    assert.equal(view.status, 200);
    assert.equal(view.json.is_demo, true);
    assert.equal(view.json.session_hours, 72);
    const created = await call('POST', `/manager/sites/${DEMO}/trial-access/codes`, 'demoManager', { note: 'Aday A', valid_days: 5 });
    assert.equal(created.status, 201);
    assert.ok(created.json.code);
    assert.equal(created.headers.get('cache-control'), 'no-store');
    const listed = await call('GET', `/manager/sites/${DEMO}/trial-access`, 'superUser');
    assert.equal(listed.json.items.length, 1);
    assert.equal(JSON.stringify(listed.json).includes(created.json.code), false, 'liste düz kod içermez');
    assert.equal(JSON.stringify(listed.json).includes('code_hash'), false);
    // demo yöneticisi başka siteye kod üretemez
    const other = await call('POST', `/manager/sites/4000000002/trial-access/codes`, 'demoManager', {});
    assert.equal(other.status, 403);
    assert.equal(other.json.code, 'FORBIDDEN_SITE');
    assert.equal((await call('POST', `/manager/sites/abc/trial-access/codes`, 'superUser', {})).status, 400);
    const revoked = await call('DELETE', `/manager/sites/${DEMO}/trial-access/codes/${created.json.item.id}`, 'demoManager');
    assert.equal(revoked.status, 200);
    assert.equal(revoked.json.item.status, 'revoked');
  });

  it('demo site işareti: yalnız süper kullanıcı; gövde bool olmalı', async () => {
    assert.equal((await call('PUT', `/manager/sites/${DEMO}/trial-access/demo`, undefined, { enabled: true })).status, 401);
    const denied = await call('PUT', `/manager/sites/${DEMO}/trial-access/demo`, 'demoManager', { enabled: true });
    assert.equal(denied.status, 403);
    assert.equal((await call('PUT', `/manager/sites/${DEMO}/trial-access/demo`, 'superUser', { enabled: 'x' })).status, 400);
    const off = await call('PUT', `/manager/sites/${DEMO}/trial-access/demo`, 'superUser', { enabled: false });
    assert.equal(off.status, 200);
    assert.equal(off.json.is_demo, false);
    const on = await call('PUT', `/manager/sites/${DEMO}/trial-access/demo`, 'superUser', { enabled: true });
    assert.equal(on.json.is_demo, true);
  });

  it('yönetim uç zincirleri: kimlik -> yetki -> hız sınırı sırası bozulmamış', () => {
    const chain = (method, path) => [...originalChains.entries()].find(([route]) => route.path === path && route.methods[method.toLowerCase()])?.[1];
    const put = chain('PUT', '/manager/sites/:siteCode/trial-access/demo');
    assert.equal(put[0], authRequired);
    assert.equal(put[1], requireSuperUser);
    assert.equal(put[2], trialAdminLimiter);
    const post = chain('POST', '/manager/sites/:siteCode/trial-access/codes');
    assert.equal(post[0], authRequired);
    assert.equal(post[1], requireSiteManager);
    assert.equal(post[2], trialAdminLimiter);
    const redeem = chain('POST', '/auth/trial-access');
    assert.equal(redeem[0], redeemLimiter, 'herkese açık uç hız sınırlayıcıdan başlar ve kimlik İSTEMEZ');
    assert.equal(redeem.includes(authRequired), false);
  });
});
