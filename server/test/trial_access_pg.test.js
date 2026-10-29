// Deneme erişim kodu (P2-27 / K10): GERÇEK PostgreSQL ile uçtan uca (gerçek server.js uygulaması, gerçek authRequired, gerçek SQL).
// YALNIZ TRIAL_ACCESS_PG_URL tanımlıysa koşar (örn. postgres://postgres@127.0.0.1:55467/postgres); aksi halde atlanır (npm test hermetik kalır).
// Her koşuda geçici bir veritabanı açılır (CREATE DATABASE) ve sonunda düşürülür; sunucu şeması ensureDbSchema ile sıfırdan kurulur.
//
// Kanıtlanan: tablo + indeks kurulumu (ensureDbSchema), tek kullanımlık atomik kullanım (8 eşzamanlı istek -> 1 başarı), 72 saatlik oturum,
// DEMO siteye kilit (kapsam dışı 403, başka site yazma yok), süre dolumu / iptal / demo site değişimi (401), hesap kapatma, kod düz saklanmaz,
// yetki matrisi (süper / demo yöneticisi / başka site yöneticisi / deneme hesabı), kaba kuvvet hız sınırı, parolayla giriş imkânsız.
import { describe, it, before, after } from 'node:test';
import assert from 'node:assert/strict';

const ADMIN_URL = process.env.TRIAL_ACCESS_PG_URL;
const skip = ADMIN_URL ? false : 'TRIAL_ACCESS_PG_URL tanımlı değil (gerçek PostgreSQL gerekir)';

describe('deneme erişim kodu: gerçek PostgreSQL', { skip }, () => {
  let pool;
  let server;
  let baseUrl;
  let dbName;
  let adminClient;
  let svc;
  let routes;
  let signAccessToken;
  let jwt;
  const ids = {};
  const tokens = {};
  const HASH = '$2a$04$abcdefghijklmnopqrstuuABCDEFGHIJKLMNOPQRSTUVWXYZ01234';

  const q = (sql, params = []) => pool.query(sql, params);
  const api = async (method, path, token, body) => {
    const response = await fetch(`${baseUrl}${path}`, {
      method,
      headers: { 'content-type': 'application/json', ...(token ? { authorization: `Bearer ${token}` } : {}) },
      body: body === undefined ? undefined : JSON.stringify(body),
    });
    const text = await response.text();
    let json = null;
    try {
      json = JSON.parse(text);
    } catch (_error) {
      // JSON değil
    }
    return { status: response.status, json, text };
  };
  const insertUser = async (name, email, role) => {
    const r = await q(
      `INSERT INTO users (full_name, email, role, is_active, email_verified, approval_status, password_hash)
       VALUES ($1, $2, $3, TRUE, TRUE, 'approved', $4) RETURNING user_code`,
      [name, email, role, HASH],
    );
    return r.rows[0].user_code;
  };
  const insertSite = async (name) => {
    const r = await q(`INSERT INTO sites (name, approval_status, approved_at) VALUES ($1, 'approved', NOW()) RETURNING site_code`, [name]);
    return Number(r.rows[0].site_code);
  };
  const tokenOf = (userCode, hash = HASH, options = {}) => signAccessToken({ id: userCode }, { passwordHash: hash, ...options });

  before(async () => {
    const pg = (await import('pg')).default;
    adminClient = new pg.Client({ connectionString: ADMIN_URL });
    await adminClient.connect();
    dbName = `trial_pg_${Date.now().toString(36)}`;
    await adminClient.query(`CREATE DATABASE ${dbName}`);
    const url = new URL(ADMIN_URL);
    process.env.DB_HOST = url.hostname;
    process.env.DB_PORT = url.port || '5432';
    process.env.DB_NAME = dbName;
    process.env.DB_USER = decodeURIComponent(url.username || 'postgres');
    process.env.DB_PASSWORD = decodeURIComponent(url.password || '');
    process.env.JWT_SECRET = 'trial-pg-test-secret-0123456789abcdef0123456789abcdef';
    process.env.SERVER_SKIP_START = '1';
    process.env.ANNOUNCEMENT_SCHEDULER_DISABLED = '1';
    delete process.env.JWT_EXPIRES_IN;

    // Sıfırdan kurulum: önce numaralı migration zinciri (106 dahil), sonra sunucunun açılış şeması (ensureDbSchema), tıpkı canlı gibi.
    const errors = [];
    const { main: migrate } = await import('../scripts/migrate.js');
    const exitCode = await migrate(['--apply', '--yes'], { ...process.env }, { log() {}, logError: (message) => errors.push(message) });
    assert.equal(exitCode, 0, `migration zinciri uygulanamadı: ${errors.join(' | ')}`);
    const db = await import('../src/db.js');
    pool = db.pool;
    await db.ensureDbSchema();
    ({ signAccessToken } = await import('../src/jwt.js'));
    jwt = (await import('jsonwebtoken')).default;
    svc = await import('../src/modules/trial_access_service.js');
    routes = await import('../src/modules/trial_access_routes.js');
    const { enableCoreModulesForSite } = await import('../src/modules/core_modules.js');
    const { app } = await import('../src/server.js');
    await new Promise((resolve) => {
      server = app.listen(0, '127.0.0.1', resolve);
    });
    baseUrl = `http://127.0.0.1:${server.address().port}`;

    ids.superUser = await insertUser('Sahip', 'sahip@example.com', 'super_user');
    ids.demoSite = await insertSite('Örnek Demo Sitesi');
    ids.realSite = await insertSite('Gerçek Müşteri Sitesi');
    ids.otherSite = await insertSite('Başka Müşteri Sitesi');
    for (const site of [ids.demoSite, ids.realSite, ids.otherSite]) {
      await enableCoreModulesForSite(pool, site);
    }
    ids.realManager = await insertUser('Gerçek Yönetici', 'gercek@example.com', 'site_manager');
    await q(`INSERT INTO site_manager_sites (site_code, manager_user_code) VALUES ($1, $2)`, [ids.realSite, ids.realManager]);
    await q(`INSERT INTO site_memberships (site_code, user_code, role) VALUES ($1, $2, 'SITE_ADMIN')`, [ids.realSite, ids.realManager]);
    ids.demoManager = await insertUser('Demo Yöneticisi', 'demo-yonetici@example.com', 'site_manager');
    await q(`INSERT INTO site_manager_sites (site_code, manager_user_code) VALUES ($1, $2)`, [ids.demoSite, ids.demoManager]);
    await q(`INSERT INTO site_memberships (site_code, user_code, role) VALUES ($1, $2, 'SITE_ADMIN')`, [ids.demoSite, ids.demoManager]);
    tokens.superUser = tokenOf(ids.superUser);
    tokens.realManager = tokenOf(ids.realManager);
    tokens.demoManager = tokenOf(ids.demoManager);
  });

  after(async () => {
    if (server) {
      server.closeAllConnections?.();
      await new Promise((resolve) => server.close(resolve));
    }
    if (pool) await pool.end().catch(() => {});
    if (adminClient) {
      await adminClient.query(`DROP DATABASE IF EXISTS ${dbName} WITH (FORCE)`).catch(() => {});
      await adminClient.end().catch(() => {});
    }
  });

  it('şema: ensureDbSchema tabloyu ve indeksleri kurar; ikinci çağrı hiçbir şey değiştirmez', async () => {
    const present = await q(`SELECT to_regclass('public.trial_access_codes') AS t`);
    assert.ok(present.rows[0].t);
    const indexes = (await q(`SELECT indexname FROM pg_indexes WHERE tablename = 'trial_access_codes'`)).rows.map((r) => r.indexname);
    for (const name of ['uq_trial_access_codes_used_by', 'idx_trial_access_codes_created', 'idx_trial_access_codes_open', 'uq_trial_access_codes_hash']) {
      assert.ok(indexes.includes(name), `${name} yok`);
    }
    const { ensureDbSchema } = await import('../src/db.js');
    await ensureDbSchema();
    // migration dosyası da (olduğu gibi, ikinci kez) çalışır: idempotent
    const { readFileSync } = await import('node:fs');
    const sql = readFileSync(new URL('../migrations/106_trial_access_codes.sql', import.meta.url), 'utf8');
    await q(sql);
  });

  it('CHECK / FK kısıtları: tutarsız kullanım satırı reddedilir; kod hash tekilliği', async () => {
    const base = `INSERT INTO trial_access_codes (code_hash, code_hint, site_code, expires_at`;
    await assert.rejects(q(`${base}, used_at) VALUES ('h1', 'ABCD', $1, NOW() + interval '1 day', NOW())`, [ids.demoSite]), /chk_trial_access_codes_used/);
    await assert.rejects(q(`${base}) VALUES ('h2', 'ABC', $1, NOW() + interval '1 day')`, [ids.demoSite]), /chk_trial_access_codes_hint/);
    await assert.rejects(q(`${base}) VALUES ('h3', 'ABCD', 999, NOW() + interval '1 day')`), /foreign key/);
    await q(`${base}) VALUES ('hdup', 'ABCD', $1, NOW() + interval '1 day')`, [ids.demoSite]);
    await assert.rejects(q(`${base}) VALUES ('hdup', 'WXYZ', $1, NOW() + interval '1 day')`, [ids.demoSite]), /uq_trial_access_codes_hash/);
    await q(`DELETE FROM trial_access_codes WHERE code_hash = 'hdup'`);
  });

  it('demo site işareti: yalnız süper kullanıcı koyar; demo değilken kod üretilemez (409)', async () => {
    const before = await api('GET', `/manager/sites/${ids.demoSite}/trial-access`, tokens.superUser);
    assert.equal(before.status, 200);
    assert.equal(before.json.is_demo, false);
    assert.deepEqual(before.json.items, []);
    assert.equal(before.json.session_hours, 72);
    const refuse = await api('POST', `/manager/sites/${ids.demoSite}/trial-access/codes`, tokens.superUser, {});
    assert.equal(refuse.status, 409);
    assert.equal(refuse.json.code, 'NOT_DEMO_SITE');
    // yönetici (süper değil) demo işaretleyemez
    const byManager = await api('PUT', `/manager/sites/${ids.demoSite}/trial-access/demo`, tokens.demoManager, { enabled: true });
    assert.equal(byManager.status, 403);
    assert.equal((await api('PUT', `/manager/sites/${ids.demoSite}/trial-access/demo`, tokens.superUser, { enabled: 'evet' })).status, 400);
    assert.equal((await api('PUT', `/manager/sites/9999999999/trial-access/demo`, tokens.superUser, { enabled: true })).status, 404);
    const set = await api('PUT', `/manager/sites/${ids.demoSite}/trial-access/demo`, tokens.superUser, { enabled: true });
    assert.equal(set.status, 200);
    assert.equal(set.json.is_demo, true);
    // bekleyen onaylı olmayan site demo olamaz
    const pending = await q(`INSERT INTO sites (name, approval_status) VALUES ('Bekleyen Site', 'pending') RETURNING site_code`);
    const bad = await api('PUT', `/manager/sites/${pending.rows[0].site_code}/trial-access/demo`, tokens.superUser, { enabled: true });
    assert.equal(bad.status, 409);
    assert.equal(bad.json.code, 'SITE_NOT_APPROVED');
    assert.equal(await svc.readDemoSiteCode(), ids.demoSite);
  });

  let issued;
  it('kod üretimi: süper kullanıcı ve demo sitenin yöneticisi üretir; başka site yöneticisi 403; kod yalnız özet olarak saklanır', async () => {
    const asRealManager = await api('POST', `/manager/sites/${ids.demoSite}/trial-access/codes`, tokens.realManager, {});
    assert.equal(asRealManager.status, 403, 'başka sitenin yöneticisi demo site için kod üretemez');
    assert.equal(asRealManager.json.code, 'FORBIDDEN_SITE');
    const nonDemo = await api('POST', `/manager/sites/${ids.realSite}/trial-access/codes`, tokens.realManager, {});
    assert.equal(nonDemo.status, 409, 'gerçek site demo değil: kod üretilemez');
    assert.equal(nonDemo.json.code, 'NOT_DEMO_SITE');
    assert.equal((await api('POST', `/manager/sites/${ids.demoSite}/trial-access/codes`, undefined, {})).status, 401);

    const byManager = await api('POST', `/manager/sites/${ids.demoSite}/trial-access/codes`, tokens.demoManager, { note: 'Ahmet Bey - X Sitesi' });
    assert.equal(byManager.status, 201);
    assert.match(byManager.json.code, /^[2-9A-HJKMNP-Z]{4}-[2-9A-HJKMNP-Z]{4}-[2-9A-HJKMNP-Z]{4}$/);
    assert.equal(byManager.json.item.status, 'active');
    assert.equal(byManager.json.item.note, 'Ahmet Bey - X Sitesi');
    assert.equal(byManager.json.session_hours, 72);

    issued = await api('POST', `/manager/sites/${ids.demoSite}/trial-access/codes`, tokens.superUser, { valid_days: 3 });
    assert.equal(issued.status, 201);
    const days = (new Date(issued.json.item.expires_at) - new Date(issued.json.item.created_at)) / 86400000;
    assert.ok(days > 2.99 && days < 3.01, `geçerlilik 3 gün olmalı: ${days}`);
    assert.equal((await api('POST', `/manager/sites/${ids.demoSite}/trial-access/codes`, tokens.superUser, { valid_days: 0 })).status, 400);
    assert.equal((await api('POST', `/manager/sites/${ids.demoSite}/trial-access/codes`, tokens.superUser, { valid_days: 61 })).status, 400);
    assert.equal((await api('POST', `/manager/sites/${ids.demoSite}/trial-access/codes`, tokens.superUser, { note: 'x'.repeat(201) })).status, 400);

    const dump = JSON.stringify((await q(`SELECT * FROM trial_access_codes`)).rows) + JSON.stringify((await q(`SELECT details FROM audit_log`)).rows);
    for (const code of [byManager.json.code, issued.json.code]) {
      assert.equal(dump.includes(code), false, 'düz kod veritabanında / denetim kaydında olmamalı');
      assert.equal(dump.includes(code.replace(/-/g, '')), false);
    }
    const row = (await q(`SELECT code_hash, code_hint FROM trial_access_codes WHERE id = $1`, [issued.json.item.id])).rows[0];
    assert.match(row.code_hash, /^[0-9a-f]{64}$/);
    assert.equal(row.code_hint, issued.json.code.slice(-4));
    const audit = (await q(`SELECT action FROM audit_log WHERE action LIKE 'trial_access.%' ORDER BY id`)).rows.map((r) => r.action);
    assert.ok(audit.includes('trial_access.demo_site_set') && audit.includes('trial_access.code_created'));
  });

  let session;
  it('kodla giriş: 72 saatlik oturum, rol deneme (site_manager), tek bağ demo site; parolayla giriş imkânsız', async () => {
    routes.redeemLimiter.reset();
    const before = Number((await q(`SELECT COUNT(*) AS n FROM users WHERE email LIKE '%@deneme.invalid'`)).rows[0].n);
    const response = await api('POST', '/auth/trial-access', undefined, { code: issued.json.code.toLowerCase().replace(/-/g, ' ') });
    assert.equal(response.status, 200, response.text);
    session = response.json;
    assert.ok(session.token);
    assert.equal(session.user.role, 'site_manager');
    assert.match(session.user.email, /^trial-[0-9a-f]{16}@deneme\.invalid$/);
    assert.match(session.user.full_name, /^Deneme Kullanıcısı \d+$/);
    assert.equal(session.trial.session_hours, 72);
    assert.equal(session.trial.site_code, ids.demoSite);
    assert.equal(session.trial.site_name, 'Örnek Demo Sitesi');
    assert.equal(session.user.trial_site_code, ids.demoSite);
    assert.equal(session.user.is_trial, true);
    assert.equal(session.user.trial_expires_at, session.trial.expires_at);
    assert.equal('password_hash' in session.user, false);

    const seconds = (new Date(session.trial.expires_at) - Date.now()) / 1000;
    assert.ok(seconds > 72 * 3600 - 30 && seconds <= 72 * 3600, `oturum 72 saat olmalı: ${seconds}`);
    const claims = jwt.decode(session.token);
    // Belirteç oturumdan (veritabanı süresi) ASLA uzun yaşamaz: ömür 72 saatten en çok birkaç saniye eksiktir.
    assert.ok(claims.exp - claims.iat <= 72 * 3600 && claims.exp - claims.iat >= 72 * 3600 - 10, `JWT ömrü 72 saat olmalı: ${claims.exp - claims.iat}`);
    assert.ok(claims.exp * 1000 <= new Date(session.trial.expires_at).getTime() + 1000, 'belirteç oturumdan uzun yaşamaz');
    assert.equal(String(claims.sub), String(session.user.id));

    const rows = (await q(`SELECT * FROM trial_access_codes WHERE id = $1`, [issued.json.item.id])).rows[0];
    assert.equal(rows.used_by, session.user.id);
    assert.ok(rows.used_at && rows.session_expires_at);
    assert.equal(Math.round((rows.session_expires_at - rows.used_at) / 1000), 72 * 3600);
    assert.equal(Number((await q(`SELECT COUNT(*) AS n FROM users WHERE email LIKE '%@deneme.invalid'`)).rows[0].n), before + 1);

    // yalnız demo siteye bağlı: yönetici bağı ve üyelik tek satır, tek site
    const links = (await q(`SELECT site_code FROM site_manager_sites WHERE manager_user_code = $1`, [session.user.id])).rows.map((r) => Number(r.site_code));
    const members = (await q(`SELECT site_code, role, is_active FROM site_memberships WHERE user_code = $1`, [session.user.id])).rows;
    assert.deepEqual(links, [ids.demoSite]);
    assert.equal(members.length, 1);
    assert.equal(Number(members[0].site_code), ids.demoSite);
    assert.equal(members[0].role, 'SITE_ADMIN');
    const siteSvc = await import('../src/services/site_service.js');
    const trialAuthUser = { role: 'site_manager', userCode: session.user.id, user_code: session.user.id, id: session.user.id };
    assert.equal(await siteSvc.hasSiteManagementAccess(trialAuthUser, ids.demoSite), true);
    for (const other of [ids.realSite, ids.otherSite]) {
      assert.equal(await siteSvc.hasSiteManagementAccess(trialAuthUser, other), false, 'ikinci kat: yetki yardımcısı da başka siteye izin vermez');
    }
    assert.deepEqual([...(await siteSvc.getManagedSiteCodes(trialAuthUser))], [ids.demoSite]);

    // parolayla giriş imkânsız (e-posta + herhangi bir parola)
    for (const password of ['x', 'Deneme123!', session.token, '!trial:']) {
      const login = await api('POST', '/auth/login', undefined, { email: session.user.email, password });
      assert.equal(login.status, 401, 'deneme hesabına parolayla girilemez');
    }
    tokens.trial = session.token;
    ids.trialUser = session.user.id;
  });

  it('ikinci kullanım reddedilir (aynı kod, farklı yazım dahil); yanlış / biçimsiz kod 401', async () => {
    routes.redeemLimiter.reset();
    for (const variant of [issued.json.code, issued.json.code.toLowerCase(), issued.json.code.replace(/-/g, '')]) {
      const again = await api('POST', '/auth/trial-access', undefined, { code: variant });
      assert.equal(again.status, 401);
      assert.equal(again.json.code, 'TRIAL_CODE_USED');
    }
    assert.equal((await api('POST', '/auth/trial-access', undefined, { code: 'ABCD-EFGH-JKMN' })).json.code, 'TRIAL_CODE_INVALID');
    assert.equal((await api('POST', '/auth/trial-access', undefined, { code: 'kisa' })).json.code, 'TRIAL_CODE_INVALID');
    assert.equal((await api('POST', '/auth/trial-access', undefined, { code: 12345678 })).status, 400);
    assert.equal((await api('POST', '/auth/trial-access', undefined, {})).status, 400);
    assert.equal((await api('POST', '/auth/trial-access', undefined, { code: '   ' })).status, 400);
    const users = Number((await q(`SELECT COUNT(*) AS n FROM users WHERE email LIKE '%@deneme.invalid'`)).rows[0].n);
    assert.equal(users, 1, 'reddedilen denemeler hesap üretmez');
  });

  it('EŞZAMANLI kullanım: aynı kodu 8 istek aynı anda dener -> tam 1 başarı, 7 ret, tek hesap', async () => {
    const created = await svc.createTrialCode({ siteCode: ids.demoSite, actor: { id: ids.superUser, role: 'super_user', full_name: 'Sahip' } });
    const before = Number((await q(`SELECT COUNT(*) AS n FROM users WHERE email LIKE '%@deneme.invalid'`)).rows[0].n);
    const results = await Promise.allSettled(Array.from({ length: 8 }, () => svc.redeemTrialCode({ code: created.code })));
    const ok = results.filter((r) => r.status === 'fulfilled');
    const failed = results.filter((r) => r.status === 'rejected');
    assert.equal(ok.length, 1, JSON.stringify(failed.map((f) => f.reason?.code ?? String(f.reason))));
    assert.equal(failed.length, 7);
    for (const f of failed) assert.equal(f.reason.code, 'TRIAL_CODE_USED');
    const after = Number((await q(`SELECT COUNT(*) AS n FROM users WHERE email LIKE '%@deneme.invalid'`)).rows[0].n);
    assert.equal(after, before + 1);
    // temizlik: bu ekstra oturumu bitir
    await svc.revokeTrialCode({ siteCode: ids.demoSite, id: created.item.id, actor: { id: ids.superUser, role: 'super_user' } });
  });

  it('kapsam: deneme oturumu demo sitede çalışır (okuma + yazma), diğer sitelere HER istek 403, hiçbir yazma sızmaz', async () => {
    const token = tokens.trial;
    const me = await api('GET', '/me', token);
    assert.equal(me.status, 200);
    assert.equal(me.json.user.trial_site_code, ids.demoSite);
    assert.ok(me.json.user.trial_expires_at);
    const sites = await api('GET', '/manager/sites', token);
    assert.equal(sites.status, 200);
    assert.deepEqual(sites.json.sites?.map((s) => s.id) ?? sites.json.items?.map((s) => s.id) ?? [], [ids.demoSite]);
    assert.equal((await api('GET', `/manager/sites/${ids.demoSite}/structure`, token)).status, 200);

    // demo sitede yazma serbest
    const write = await api('POST', `/manager/sites/${ids.demoSite}/finance/expense-categories`, token, { name: 'Deneme kategorisi' });
    assert.equal(write.status, 201, write.text);
    assert.equal(Number((await q(`SELECT COUNT(*) AS n FROM expense_categories WHERE site_code = $1 AND name = 'Deneme kategorisi'`, [ids.demoSite])).rows[0].n), 1);

    // başka siteler: okuma / yazma / alt yollar / harf biçimi / sondaki eğik çizgi
    for (const site of [ids.realSite, ids.otherSite]) {
      for (const [method, path, body] of [
        ['GET', `/manager/sites/${site}/structure`],
        ['GET', `/manager/sites/${site}/finance/summary`],
        ['POST', `/manager/sites/${site}/finance/expense-categories`, { name: 'Sızıntı' }],
        ['GET', `/manager/sites/${site}/people`],
        ['PATCH', `/manager/sites/${site}`, { name: 'Ele geçirildi' }],
        ['DELETE', `/manager/sites/${site}`],
        ['GET', `/MANAGER/SITES/${site}/structure/`],
        ['GET', `/sites/${site}/meter-field/meters`],
        ['GET', `/membership/sites/${site}/residents-tree`],
        ['POST', `/manager/sites/${site}/trial-access/codes`, {}],
      ]) {
        const r = await api(method, path, token, body);
        assert.equal(r.status, 403, `${method} ${path} -> ${r.status} ${r.text}`);
        assert.equal(r.json.code, 'TRIAL_SCOPE_DENIED', `${method} ${path}`);
      }
    }
    for (const site of [ids.realSite, ids.otherSite]) {
      const leaked = Number((await q(`SELECT COUNT(*) AS n FROM expense_categories WHERE site_code = $1 AND name IN ('Sızıntı', 'Deneme kategorisi')`, [site])).rows[0].n);
      assert.equal(leaked, 0, 'gerçek sitede hiçbir kayıt oluşmamalı');
      assert.equal((await q(`SELECT name FROM sites WHERE site_code = $1`, [site])).rows[0].name.includes('Ele geçirildi'), false);
    }

    // kapalı uçlar (site yaşam döngüsü, hesap, donanım, dış etkili, yönetim)
    for (const [method, path, body] of [
      ['POST', '/manager/sites', { name: 'Yeni Site', blocks: [] }],
      ['PATCH', '/me', { full_name: 'Başka Ad' }],
      ['POST', '/me/account-deletion', {}],
      ['POST', '/me/data-export', {}],
      ['PATCH', `/manager/sites/${ids.demoSite}`, { name: 'Ad Değişti' }],
      ['DELETE', `/manager/sites/${ids.demoSite}`],
      ['POST', `/manager/sites/${ids.demoSite}/managers/invite`, { email: 'x@example.com' }],
      ['GET', `/manager/sites/${ids.demoSite}/join-token`],
      ['POST', `/manager/sites/${ids.demoSite}/doors`, { door_name: 'Kapı' }],
      ['PUT', `/manager/sites/${ids.demoSite}/staff-roles`, { email: 'gercek@example.com', role: 'STAFF' }],
      ['POST', `/manager/sites/${ids.demoSite}/finance/reminders/send`, {}],
      ['POST', `/manager/sites/${ids.demoSite}/trial-access/codes`, {}],
      ['GET', `/manager/sites/${ids.demoSite}/trial-access`],
      ['GET', '/admin/users'],
      ['POST', '/admin/sites', {}],
      ['POST', '/membership/setup-site', {}],
      ['POST', '/app/doors/1/open', {}],
      ['POST', '/app/guest-passes', {}],
      ['PATCH', '/manager/doors/1/device', {}],
    ]) {
      const r = await api(method, path, tokens.trial, body);
      assert.equal(r.status, 403, `${method} ${path} -> ${r.status} ${r.text}`);
      assert.equal(r.json.code, 'TRIAL_ACTION_DENIED', `${method} ${path}`);
    }
    assert.equal(Number((await q(`SELECT COUNT(*) AS n FROM sites WHERE name = 'Yeni Site'`)).rows[0].n), 0);
    assert.equal((await q(`SELECT name FROM sites WHERE site_code = $1`, [ids.demoSite])).rows[0].name, 'Örnek Demo Sitesi');
    assert.equal(Number((await q(`SELECT COUNT(*) AS n FROM site_memberships WHERE user_code = (SELECT user_code FROM users WHERE email = 'gercek@example.com') AND site_code = $1`, [ids.demoSite])).rows[0].n), 0);

    // yol saldırıları
    for (const path of [`/manager/sites/${ids.demoSite}/../${ids.realSite}/structure`, `/manager/sites/%${ids.demoSite.toString().slice(0, 2)}${ids.demoSite.toString().slice(2)}/structure`, `//manager/sites/${ids.realSite}/structure`]) {
      const r = await api('GET', path, token);
      assert.ok(r.status === 403 || r.status === 404, `${path} -> ${r.status}`);
      assert.notEqual(r.status, 200);
    }
  });

  it('normal kullanıcılar etkilenmez: /me deneme alanı taşımaz, yönetici kendi sitesinde çalışır', async () => {
    const real = await api('GET', '/me', tokens.realManager);
    assert.equal(real.status, 200);
    assert.equal('trial_expires_at' in real.json.user, false);
    assert.equal('trial_site_code' in real.json.user, false);
    assert.equal('is_trial' in real.json.user, false);
    assert.equal((await api('GET', `/manager/sites/${ids.realSite}/structure`, tokens.realManager)).status, 200);
    assert.equal((await api('GET', `/manager/sites/${ids.demoSite}/structure`, tokens.realManager)).status, 403, 'mevcut davranış: başka site yöneticisi demo siteye erişemez');
    assert.equal((await api('GET', '/me', tokens.superUser)).status, 200);
  });

  it('süre dolumu: 72 saat sonra HER istek 401 TRIAL_EXPIRED; hesap kapatılır; demo site yönetici bağı silinir', async () => {
    assert.equal((await api('GET', '/me', tokens.trial)).status, 200);
    await q(`UPDATE trial_access_codes SET session_expires_at = NOW() - interval '1 second' WHERE used_by = $1`, [ids.trialUser]);
    for (const path of ['/me', `/manager/sites/${ids.demoSite}/structure`, '/manager/sites']) {
      const r = await api('GET', path, tokens.trial);
      assert.equal(r.status, 401, path);
      assert.equal(r.json.code, 'TRIAL_EXPIRED');
      assert.match(r.json.error, /Deneme süreniz doldu/);
    }
    assert.equal((await api('POST', `/manager/sites/${ids.demoSite}/finance/expense-categories`, tokens.trial, { name: 'Süre sonrası' })).status, 401);
    assert.equal(Number((await q(`SELECT COUNT(*) AS n FROM expense_categories WHERE name = 'Süre sonrası'`)).rows[0].n), 0);

    const closed = await svc.closeExpiredTrialAccounts();
    assert.ok(closed >= 1);
    const user = (await q(`SELECT is_active FROM users WHERE user_code = $1`, [ids.trialUser])).rows[0];
    assert.equal(user.is_active, false);
    assert.equal(Number((await q(`SELECT COUNT(*) AS n FROM site_manager_sites WHERE manager_user_code = $1`, [ids.trialUser])).rows[0].n), 0);
    assert.equal((await q(`SELECT is_active FROM site_memberships WHERE user_code = $1`, [ids.trialUser])).rows[0].is_active, false);
    assert.ok((await q(`SELECT closed_at FROM trial_access_codes WHERE used_by = $1`, [ids.trialUser])).rows[0].closed_at);
    // kapatıldıktan sonra da mesaj aynı (403 "Hesap aktif degil" değil)
    const after = await api('GET', '/me', tokens.trial);
    assert.equal(after.status, 401);
    assert.equal(after.json.code, 'TRIAL_EXPIRED');
    assert.equal(await svc.closeExpiredTrialAccounts(), 0, 'idempotent');
    // kapatılmış hesap gerçek bir kullanıcıya dokunmaz
    assert.equal((await q(`SELECT is_active FROM users WHERE user_code = $1`, [ids.realManager])).rows[0].is_active, true);
    assert.equal(Number((await q(`SELECT COUNT(*) AS n FROM site_manager_sites WHERE manager_user_code = $1`, [ids.realManager])).rows[0].n), 1);
    // süresi dolan kod yeniden kullanılamaz
    routes.redeemLimiter.reset();
    const reuse = await api('POST', '/auth/trial-access', undefined, { code: issued.json.code });
    assert.equal(reuse.json.code, 'TRIAL_CODE_USED');
  });

  it('kullanılmadan süresi dolan kod: 401 TRIAL_CODE_EXPIRED; iptal edilen kod: TRIAL_CODE_REVOKED', async () => {
    routes.redeemLimiter.reset();
    const actor = { id: ids.superUser, role: 'super_user', full_name: 'Sahip' };
    const expired = await svc.createTrialCode({ siteCode: ids.demoSite, actor });
    await q(`UPDATE trial_access_codes SET created_at = NOW() - interval '3 days', expires_at = NOW() - interval '1 day' WHERE id = $1`, [expired.item.id]);
    const e = await api('POST', '/auth/trial-access', undefined, { code: expired.code });
    assert.equal(e.status, 401);
    assert.equal(e.json.code, 'TRIAL_CODE_EXPIRED');
    const listed = await api('GET', `/manager/sites/${ids.demoSite}/trial-access`, tokens.superUser);
    assert.equal(listed.json.items.find((i) => i.id === expired.item.id).status, 'expired');

    const toRevoke = await api('POST', `/manager/sites/${ids.demoSite}/trial-access/codes`, tokens.superUser, {});
    const revoke = await api('DELETE', `/manager/sites/${ids.demoSite}/trial-access/codes/${toRevoke.json.item.id}`, tokens.superUser);
    assert.equal(revoke.status, 200);
    assert.equal(revoke.json.item.status, 'revoked');
    const r = await api('POST', '/auth/trial-access', undefined, { code: toRevoke.json.code });
    assert.equal(r.status, 401);
    assert.equal(r.json.code, 'TRIAL_CODE_REVOKED');
    assert.equal((await api('DELETE', `/manager/sites/${ids.demoSite}/trial-access/codes/${toRevoke.json.item.id}`, tokens.superUser)).status, 200, 'idempotent');
    assert.equal((await api('DELETE', `/manager/sites/${ids.demoSite}/trial-access/codes/987654`, tokens.superUser)).status, 404);
    assert.equal((await api('DELETE', `/manager/sites/${ids.demoSite}/trial-access/codes/abc`, tokens.superUser)).status, 404);
  });

  it('süren oturumun kodu iptal edilince oturum biter (401 TRIAL_REVOKED); başka yöneticinin iptali başka siteyi etkilemez', async () => {
    routes.redeemLimiter.reset();
    const created = await api('POST', `/manager/sites/${ids.demoSite}/trial-access/codes`, tokens.demoManager, {});
    const login = await api('POST', '/auth/trial-access', undefined, { code: created.json.code });
    assert.equal(login.status, 200);
    assert.equal((await api('GET', '/me', login.json.token)).status, 200);
    // başka site yöneticisi iptal edemez
    assert.equal((await api('DELETE', `/manager/sites/${ids.demoSite}/trial-access/codes/${created.json.item.id}`, tokens.realManager)).status, 403);
    assert.equal((await api('GET', '/me', login.json.token)).status, 200);
    const revoke = await api('DELETE', `/manager/sites/${ids.demoSite}/trial-access/codes/${created.json.item.id}`, tokens.demoManager);
    assert.equal(revoke.status, 200);
    assert.equal(revoke.json.item.status, 'ended');
    const after = await api('GET', '/me', login.json.token);
    assert.equal(after.status, 401);
    assert.equal(after.json.code, 'TRIAL_REVOKED');
    const user = (await q(`SELECT is_active FROM users WHERE user_code = $1`, [login.json.user.id])).rows[0];
    assert.equal(user.is_active, false, 'iptal anında hesap kapatılır');
  });

  it('demo site değişince / kaldırılınca açık oturumlar biter ve bekleyen kodlar kullanılamaz', async () => {
    routes.redeemLimiter.reset();
    const created = await api('POST', `/manager/sites/${ids.demoSite}/trial-access/codes`, tokens.superUser, {});
    const pendingCode = await api('POST', `/manager/sites/${ids.demoSite}/trial-access/codes`, tokens.superUser, {});
    const login = await api('POST', '/auth/trial-access', undefined, { code: created.json.code });
    assert.equal((await api('GET', '/me', login.json.token)).status, 200);
    // demo işareti kalkar
    const off = await api('PUT', `/manager/sites/${ids.demoSite}/trial-access/demo`, tokens.superUser, { enabled: false });
    assert.equal(off.json.is_demo, false);
    const ended = await api('GET', '/me', login.json.token);
    assert.equal(ended.status, 401);
    assert.equal(ended.json.code, 'TRIAL_REVOKED');
    // bekleyen kod: geçerli olsa da demo kapalıyken kullanılamaz (503), geçersiz kod hâlâ 401
    const closedDemo = await api('POST', '/auth/trial-access', undefined, { code: pendingCode.json.code });
    assert.equal(closedDemo.status, 503);
    assert.equal(closedDemo.json.code, 'TRIAL_UNAVAILABLE');
    assert.equal((await api('POST', '/auth/trial-access', undefined, { code: 'ABCD-EFGH-JKMN' })).status, 401);
    assert.equal(Number((await q(`SELECT COUNT(*) AS n FROM trial_access_codes WHERE id = $1 AND used_at IS NOT NULL`, [pendingCode.json.item.id])).rows[0].n), 0, 'kapalı demo kodu yakmaz');
    // başka siteye taşınırsa eski sitenin kodu geçmez
    await api('PUT', `/manager/sites/${ids.realSite}/trial-access/demo`, tokens.superUser, { enabled: true });
    assert.equal((await api('POST', '/auth/trial-access', undefined, { code: pendingCode.json.code })).json.code, 'TRIAL_UNAVAILABLE');
    // geri al: demo site tekrar ilk site
    await api('PUT', `/manager/sites/${ids.demoSite}/trial-access/demo`, tokens.superUser, { enabled: true });
    assert.equal(await svc.readDemoSiteCode(), ids.demoSite);
    assert.equal((await api('GET', `/manager/sites/${ids.realSite}/trial-access`, tokens.superUser)).json.is_demo, false, 'aynı anda tek demo site');
  });

  it('yetim deneme hesabı: kod satırı silinirse (demo site silinmesi / el ile temizlik) hesap sıradan yönetici gibi çalışamaz', async () => {
    routes.redeemLimiter.reset();
    const created = await api('POST', `/manager/sites/${ids.demoSite}/trial-access/codes`, tokens.superUser, {});
    const login = await api('POST', '/auth/trial-access', undefined, { code: created.json.code });
    assert.equal(login.status, 200);
    assert.equal((await api('GET', '/me', login.json.token)).status, 200);
    await q(`DELETE FROM trial_access_codes WHERE id = $1`, [created.json.item.id]);
    for (const [method, path, body] of [['GET', '/me'], ['POST', '/manager/sites', { name: 'Yetim Site', blocks: [] }], ['POST', '/membership/setup-site', {}], ['GET', `/manager/sites/${ids.demoSite}/structure`]]) {
      const r = await api(method, path, login.json.token, body);
      assert.equal(r.status, 401, `${method} ${path} -> ${r.status} ${r.text}`);
      assert.equal(r.json.code, 'TRIAL_REVOKED');
    }
    assert.equal(Number((await q(`SELECT COUNT(*) AS n FROM sites WHERE name = 'Yetim Site'`)).rows[0].n), 0);
  });

  it('kaba kuvvet: IP başına 15 dakikada 10 deneme, sonrası 429 Retry-After; kodu doğru bile olsa sınır aşılınca reddedilir', async () => {
    routes.redeemLimiter.reset();
    const statuses = [];
    for (let i = 0; i < 12; i += 1) {
      const r = await api('POST', '/auth/trial-access', undefined, { code: `ABCD-EFGH-JK${i % 2 ? 'M' : 'N'}${(i % 7) + 2}` });
      statuses.push(r.status);
    }
    assert.deepEqual(statuses.slice(0, 10), Array(10).fill(401));
    assert.deepEqual(statuses.slice(10), [429, 429]);
    const created = await api('POST', `/manager/sites/${ids.demoSite}/trial-access/codes`, tokens.superUser, {});
    const blocked = await api('POST', '/auth/trial-access', undefined, { code: created.json.code });
    assert.equal(blocked.status, 429, 'sınır aşılmışken doğru kod bile kabul edilmez');
    assert.equal(Number((await q(`SELECT COUNT(*) AS n FROM trial_access_codes WHERE id = $1 AND used_at IS NOT NULL`, [created.json.item.id])).rows[0].n), 0);
    routes.redeemLimiter.reset();
    assert.equal((await api('POST', '/auth/trial-access', undefined, { code: created.json.code })).status, 200);
    routes.redeemLimiter.reset();
  });

  it('en çok 100 kullanılmamış kod: sınır aşılınca 409 TOO_MANY_ACTIVE_CODES', async () => {
    await q(`DELETE FROM trial_access_codes WHERE used_at IS NULL`);
    const actor = { id: ids.superUser, role: 'super_user', full_name: 'Sahip' };
    await q(
      `INSERT INTO trial_access_codes (code_hash, code_hint, site_code, expires_at)
       SELECT 'bulk' || g, 'ABCD', $1, NOW() + interval '1 day' FROM generate_series(1, 100) g`,
      [ids.demoSite],
    );
    await assert.rejects(svc.createTrialCode({ siteCode: ids.demoSite, actor }), (error) => error.code === 'TOO_MANY_ACTIVE_CODES' && error.statusCode === 409);
    await q(`DELETE FROM trial_access_codes WHERE code_hash LIKE 'bulk%'`);
    assert.ok((await svc.createTrialCode({ siteCode: ids.demoSite, actor })).code);
  });

  it('kod başarısız hesap oluşturmada yanmaz: işlem geri alınır, kod yeniden kullanılabilir', async () => {
    const actor = { id: ids.superUser, role: 'super_user', full_name: 'Sahip' };
    const created = await svc.createTrialCode({ siteCode: ids.demoSite, actor });
    // kullanıcı eklemeyi bozan geçici tetikleyici
    await q(`CREATE OR REPLACE FUNCTION trial_test_block() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'trial test: kullanici eklenemez'; END $$`);
    await q(`CREATE TRIGGER trg_trial_test_block BEFORE INSERT ON users FOR EACH ROW WHEN (NEW.email LIKE '%@deneme.invalid') EXECUTE FUNCTION trial_test_block()`);
    try {
      await assert.rejects(svc.redeemTrialCode({ code: created.code }));
    } finally {
      await q(`DROP TRIGGER trg_trial_test_block ON users`);
      await q(`DROP FUNCTION trial_test_block()`);
    }
    const row = (await q(`SELECT used_at, used_by FROM trial_access_codes WHERE id = $1`, [created.item.id])).rows[0];
    assert.equal(row.used_at, null, 'başarısız kullanım kodu yakmamalı');
    const retry = await svc.redeemTrialCode({ code: created.code });
    assert.ok(retry.token);
  });

  it('bakım adımı yalnız deneme hesaplarını kapatır; audit kayıtları düz kod taşımaz', async () => {
    const audits = (await q(`SELECT action, details FROM audit_log WHERE action LIKE 'trial_access.%'`)).rows;
    const actions = new Set(audits.map((a) => a.action));
    for (const action of ['trial_access.demo_site_set', 'trial_access.demo_site_cleared', 'trial_access.code_created', 'trial_access.code_revoked', 'trial_access.redeemed']) {
      assert.ok(actions.has(action), `${action} denetim kaydı yok`);
    }
    const json = JSON.stringify(audits);
    assert.equal(/[2-9A-HJKMNP-Z]{4}-[2-9A-HJKMNP-Z]{4}-[2-9A-HJKMNP-Z]{4}/.test(json), false);
    assert.equal(Number((await q(`SELECT COUNT(*) AS n FROM users WHERE is_active = FALSE AND email NOT LIKE '%@deneme.invalid'`)).rows[0].n), 0, 'gerçek hesaplara dokunulmadı');
  });
});
