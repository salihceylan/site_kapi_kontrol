// Kartlı Geçiş uçları (DB'siz, KATI sahte veritabanı): rota zinciri + hız sınırları, yetki / modül kapısı sırası (biçim -> yetki -> site -> modül), kurul salt okur,
// STAFF / sakin / ilgisiz 403, kart tanımlama (UID normalize, CARD_EXISTS, kişi başka sitede 404, kilit sırası), iptal (kayıt kalır, INVALID_STATE, varlık sızmaz),
// sakin listesi (YALNIZ kendi kartları, UID maskeli), audit'te tam UID YOK. Kimlik katmanı sahte (x-test-user); gerçek HTTP, gerçek Express.
// Gerçek PostgreSQL doğrulaması (kısmi tekil indeks, FK silme politikası, cihaz yolu, hesap silme / dışa aktarma, 40P01 = 0): scripts/qa_platform_pg.mjs "card_access".
import { describe, it, before, after, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import express from 'express';
import { pool } from '../src/db.js';
import { authRequired } from '../src/middlewares/auth_middleware.js';
import { cardAccessRouter, cardReadLimiter, cardWriteLimiter } from '../src/modules/card_access_routes.js';

const SITE = 1000000001;
const OTHER_SITE = 1000000002;
const mk = (id, role, name) => ({ id, user_code: id, userCode: id, role, full_name: name, email: `u${id}@example.com` });
const users = {
  superUser: mk(1, 'super_user', 'Süper'),
  manager: mk(20001, 'site_manager', 'Yönetici'),
  otherManager: mk(20002, 'site_manager', 'Başka Yönetici'),
  resident: mk(20004, 'apartment_owner', 'Sakin Bir'),
  staff: mk(20005, 'individual', 'Görevli'),
  board: mk(20006, 'individual', 'Kurul'),
  resident2: mk(20007, 'apartment_owner', 'Sakin İki'),
  outsider: mk(20008, 'individual', 'İlgisiz'),
};

const norm = (text) => String(text).replace(/\s+/g, ' ').trim();
const ok = (rows = []) => ({ rows, rowCount: rows.length });
const CREATED_AT = new Date('2026-10-19T10:00:00.000Z');
const REVOKED_AT = new Date('2026-10-19T11:00:00.000Z');
let state;
let log;
let clientLog;
let connects;

function makeState() {
  return {
    sites: new Set([SITE, OTHER_SITE]),
    managerLinks: [{ site_code: SITE, user_code: 20001 }, { site_code: OTHER_SITE, user_code: 20002 }],
    memberships: [
      { site_code: SITE, user_code: 20005, role: 'STAFF', is_active: true },
      { site_code: SITE, user_code: 20006, role: 'BOARD_MEMBER', is_active: true },
    ],
    users: new Set([1, 20001, 20002, 20004, 20005, 20006, 20007, 20008]),
    moduleEnabled: { [SITE]: true, [OTHER_SITE]: true },
    people: [
      { id: 41, site_code: SITE, user_code: 20004, full_name: 'Sakin Bir', is_active: true, apartments: [{ b: 'A Blok', u: 'Daire 3' }] },
      { id: 42, site_code: SITE, user_code: 20007, full_name: 'Sakin İki', is_active: true, apartments: [{ b: 'A Blok', u: 'Daire 4' }] },
      { id: 43, site_code: SITE, user_code: null, full_name: 'Pasif Kişi', is_active: false, apartments: [] },
      { id: 91, site_code: OTHER_SITE, user_code: 20004, full_name: 'Sakin Bir (başka site)', is_active: true, apartments: [{ b: null, u: 'Daire 1' }] },
    ],
    cards: [],
    nextCardId: 1,
    audit: [],
  };
}

const personOf = (card) => state.people.find((p) => p.id === card.person_id);
const managerRow = (card) => ({
  id: String(card.id), site_code: String(card.site_code), person_id: String(card.person_id), card_uid: card.card_uid, label: card.label, is_active: card.is_active,
  revoked_at: card.revoked_at, created_at: card.created_at, person_name: personOf(card)?.full_name ?? null, apartments: personOf(card)?.apartments ?? [],
});
const seedCard = (over) => {
  const card = { id: state.nextCardId, site_code: SITE, person_id: 41, card_uid: 'AAAA1111', label: null, is_active: true, revoked_at: null, created_at: CREATED_AT, created_by: 20001, ...over };
  state.nextCardId += 1;
  state.cards.push(card);
  return card;
};

/** Yönetim listesi / sayımı: WHERE parçasından süzgeçler (site her zaman $1). */
function filterCards(whereSql, params) {
  const site = Number(params[0]);
  let list = state.cards.filter((c) => c.site_code === site);
  if (/c\.is_active = TRUE/.test(whereSql)) list = list.filter((c) => c.is_active);
  if (/c\.is_active = FALSE/.test(whereSql)) list = list.filter((c) => !c.is_active);
  const person = /c\.person_id = \$(\d+)/.exec(whereSql);
  if (person) list = list.filter((c) => c.person_id === Number(params[Number(person[1]) - 1]));
  const like = /LIKE \$(\d+)/.exec(whereSql);
  if (like) {
    const needle = String(params[Number(like[1]) - 1]).replace(/^%|%$/g, '').replace(/\\([%_\\])/g, '$1');
    list = list.filter((c) => c.card_uid.includes(needle.toUpperCase()) || (personOf(c)?.full_name ?? '').toLowerCase().includes(needle.toLowerCase()));
  }
  return list.sort((a, b) => Number(b.is_active) - Number(a.is_active) || b.id - a.id);
}

function fakeQuery(text, params = []) {
  const sql = norm(text);
  log.push(sql);
  if (/^SELECT 1 FROM site_manager_sites WHERE site_code = \$1 AND manager_user_code = \$2 LIMIT 1$/.test(sql)) {
    return ok(state.managerLinks.filter((l) => l.site_code === Number(params[0]) && l.user_code === Number(params[1])).map(() => ({ x: 1 })));
  }
  if (/^SELECT 1 FROM site_memberships WHERE site_code = \$1 AND user_code = \$2 AND role IN \('SITE_OWNER', 'SITE_ADMIN'\) AND is_active = TRUE LIMIT 1$/.test(sql)) return ok();
  if (/^SELECT EXISTS \( SELECT 1 FROM site_memberships WHERE site_code = \$1 AND user_code = \$2 AND role = 'BOARD_MEMBER'/.test(sql)) {
    const [site, user] = params.map(Number);
    const here = state.memberships.filter((m) => m.site_code === site && m.user_code === user && m.is_active);
    const otherRole = state.managerLinks.some((l) => l.user_code === user) || state.memberships.some((m) => m.user_code === user && m.is_active && m.role === 'BOARD_MEMBER');
    return ok([{ is_board_here: here.some((m) => m.role === 'BOARD_MEMBER'), is_member_here: here.length > 0, has_other_role: otherRole }]);
  }
  if (/^SELECT site_code FROM sites WHERE site_code = \$1 LIMIT 1$/.test(sql)) return ok(state.sites.has(Number(params[0])) ? [{ site_code: String(params[0]) }] : []);
  if (/^SELECT enabled FROM site_modules WHERE site_code = \$1 AND module_code = \$2 LIMIT 1$/.test(sql)) {
    return ok(params[1] === 'card_access' && Number(params[0]) in state.moduleEnabled ? [{ enabled: state.moduleEnabled[Number(params[0])] }] : []);
  }
  let match = /^SELECT COUNT\(\*\)::int AS n FROM access_cards c INNER JOIN site_people sp ON sp\.id = c\.person_id LEFT JOIN users u ON u\.user_code = sp\.user_code WHERE (.+)$/.exec(sql);
  if (match) return ok([{ n: filterCards(match[1], params).length }]);
  match = /^SELECT c\.id, c\.site_code, c\.person_id, c\.card_uid, c\.label, c\.is_active, c\.revoked_at, c\.created_at, .+ AS apartments FROM access_cards c INNER JOIN site_people sp ON sp\.id = c\.person_id LEFT JOIN users u ON u\.user_code = sp\.user_code WHERE (.+) ORDER BY c\.is_active DESC, c\.id DESC LIMIT \$(\d+) OFFSET \$(\d+)$/.exec(sql);
  if (match) {
    const limit = Number(params[Number(match[2]) - 1]);
    const offset = Number(params[Number(match[3]) - 1]);
    return ok(filterCards(match[1], params).slice(offset, offset + limit).map(managerRow));
  }
  match = /^SELECT c\.id, c\.site_code, s\.name AS site_name, c\.card_uid, c\.label, c\.is_active, c\.revoked_at, c\.created_at FROM access_cards c INNER JOIN site_people sp ON sp\.id = c\.person_id AND sp\.user_code = \$1 INNER JOIN sites s ON s\.site_code = c\.site_code WHERE EXISTS \(SELECT 1 FROM site_modules smod WHERE smod\.site_code = c\.site_code AND smod\.module_code = 'card_access' AND smod\.enabled = TRUE\)( AND c\.site_code = \$2)? ORDER BY c\.is_active DESC, c\.id DESC LIMIT 200$/.exec(sql);
  if (match) {
    const user = Number(params[0]);
    const site = match[1] ? Number(params[1]) : null;
    const rows = state.cards
      .filter((c) => personOf(c)?.user_code === user && state.moduleEnabled[c.site_code] === true && (site === null || c.site_code === site))
      .sort((a, b) => Number(b.is_active) - Number(a.is_active) || b.id - a.id)
      .map((c) => ({ id: String(c.id), site_code: String(c.site_code), site_name: c.site_code === SITE ? 'Gül Sitesi' : 'Başka Site', card_uid: c.card_uid, label: c.label, is_active: c.is_active, revoked_at: c.revoked_at, created_at: c.created_at }));
    return ok(rows);
  }
  throw new Error(`BEKLENMEYEN SQL (sahte DB katı): ${sql.slice(0, 200)}`);
}

/** Yazma transaction'ı: yalnız sözleşmedeki ifadeler; tanımsız SQL fırlatır. */
function fakeClient() {
  return {
    async query(text, params = []) {
      const sql = norm(text);
      clientLog.push(sql);
      if (/^(BEGIN|COMMIT|ROLLBACK)$/.test(sql)) return ok();
      if (/^(SAVEPOINT|RELEASE SAVEPOINT|ROLLBACK TO SAVEPOINT) audit_insert$/.test(sql)) return ok();
      if (sql === 'SELECT site_code FROM sites WHERE site_code = $1 FOR KEY SHARE') return ok(state.sites.has(Number(params[0])) ? [{ site_code: String(params[0]) }] : []);
      if (sql === 'SELECT user_code FROM users WHERE user_code = $1 AND deleted_at IS NULL FOR KEY SHARE') return ok(state.users.has(Number(params[0])) ? [{ user_code: params[0] }] : []);
      if (sql === 'SELECT id FROM site_people WHERE id = $1 AND site_code = $2 AND is_active = TRUE FOR KEY SHARE') {
        return ok(state.people.filter((p) => p.id === Number(params[0]) && p.site_code === Number(params[1]) && p.is_active).map((p) => ({ id: String(p.id) })));
      }
      if (sql === 'INSERT INTO access_cards (site_code, person_id, card_uid, label, created_by) VALUES ($1, $2, $3, $4, $5) RETURNING id') {
        const [siteCode, personId, cardUid, label, createdBy] = params;
        if (state.cards.some((c) => c.site_code === Number(siteCode) && c.card_uid === cardUid && c.is_active)) {
          throw Object.assign(new Error('duplicate key value violates unique constraint "uq_access_cards_site_uid_active"'), { code: '23505' });
        }
        const card = seedCard({ site_code: Number(siteCode), person_id: Number(personId), card_uid: cardUid, label, created_by: createdBy });
        return ok([{ id: String(card.id) }]);
      }
      if (/^INSERT INTO audit_log \(/.test(sql)) {
        state.audit.push({ actor_user_code: params[0], action: params[3], site_code: params[4], target_type: params[5], target_id: params[6], details: JSON.parse(params[7]) });
        return ok();
      }
      if (/^SELECT c\.id, c\.site_code, c\.person_id, c\.card_uid, .+ AS apartments FROM access_cards c INNER JOIN site_people sp ON sp\.id = c\.person_id LEFT JOIN users u ON u\.user_code = sp\.user_code WHERE c\.site_code = \$1 AND c\.id = \$2$/.test(sql)) {
        return ok(state.cards.filter((c) => c.site_code === Number(params[0]) && c.id === Number(params[1])).map(managerRow));
      }
      if (sql === 'SELECT id, person_id, card_uid, is_active FROM access_cards WHERE id = $1 AND site_code = $2 FOR UPDATE') {
        return ok(state.cards.filter((c) => c.id === Number(params[0]) && c.site_code === Number(params[1])).map((c) => ({ id: String(c.id), person_id: String(c.person_id), card_uid: c.card_uid, is_active: c.is_active })));
      }
      if (sql === 'UPDATE access_cards SET is_active = FALSE, revoked_at = NOW(), updated_at = NOW() WHERE id = $1 AND site_code = $2') {
        const card = state.cards.find((c) => c.id === Number(params[0]) && c.site_code === Number(params[1]));
        if (card) {
          card.is_active = false;
          card.revoked_at = REVOKED_AT;
        }
        return ok();
      }
      throw new Error(`BEKLENMEYEN transaction SQL (sahte DB katı): ${sql.slice(0, 200)}`);
    },
    release() {},
  };
}

const withTransactions = () => {
  pool.connect = async () => {
    connects += 1;
    return fakeClient();
  };
};

const ORIGINAL_ROUTES = cardAccessRouter.stack
  .filter((layer) => layer.route)
  .map((layer) => ({ path: layer.route.path, method: Object.keys(layer.route.methods)[0], handlers: layer.route.stack.map((entry) => entry.handle) }));

let server;
let baseUrl;

before(async () => {
  for (const layer of cardAccessRouter.stack) {
    if (!layer.route) continue;
    layer.route.stack[0].handle = (req, _res, next) => {
      req.authUser = JSON.parse(decodeURIComponent(req.headers['x-test-user']));
      next();
    };
    layer.route.stack[1].handle = (_req, _res, next) => next(); // hız sınırlayıcılar ayrı testte sınanır
  }
  const app = express();
  app.use(express.json({ limit: '1mb' }));
  app.use(cardAccessRouter);
  await new Promise((resolve) => {
    server = app.listen(0, '127.0.0.1', resolve);
  });
  baseUrl = `http://127.0.0.1:${server.address().port}`;
});

after(async () => {
  server.closeAllConnections?.();
  await new Promise((resolve) => server.close(resolve));
  delete pool.query;
  delete pool.connect;
});

beforeEach(() => {
  state = makeState();
  log = [];
  clientLog = [];
  connects = 0;
  pool.query = async (text, params) => fakeQuery(text, params);
  pool.connect = async () => {
    throw new Error('işlem açılmamalıydı (doğrulama / yetki hatası veritabanına gitmeden dönmeli)');
  };
});

async function call(method, urlPath, { user = null, body } = {}) {
  const init = { method, headers: {} };
  if (user) init.headers['x-test-user'] = encodeURIComponent(JSON.stringify(user));
  if (body !== undefined) {
    init.body = typeof body === 'string' ? body : JSON.stringify(body);
    init.headers['content-type'] = 'application/json';
  }
  const res = await fetch(`${baseUrl}${urlPath}`, init);
  let json = null;
  try {
    json = await res.json();
  } catch (_error) {
    // gövdesiz
  }
  return { status: res.status, body: json, headers: res.headers };
}

const M = (suffix = '', site = SITE) => `/manager/sites/${site}/access-cards${suffix}`;
const GOOD = { person_id: 41, card_uid: '04:a3:b2:c1:d5', label: '  Ana   kapı ' };

describe('rota zinciri ve hız sınırları', () => {
  it('sözleşmedeki 4 uç vardır; her biri authRequired ile BAŞLAR, ikinci halka hız sınırlayıcıdır (GET: okuma; POST: yazma)', () => {
    const routes = ORIGINAL_ROUTES.map((route) => `${route.method.toUpperCase()} ${route.path}`);
    assert.deepEqual([...routes].sort(), [
      'GET /app/access-cards',
      'GET /manager/sites/:siteCode/access-cards',
      'POST /manager/sites/:siteCode/access-cards',
      'POST /manager/sites/:siteCode/access-cards/:id/revoke',
    ]);
    for (const route of ORIGINAL_ROUTES) {
      assert.equal(route.handlers[0], authRequired, `${route.method} ${route.path}`);
      assert.equal(route.handlers[1], route.method === 'get' ? cardReadLimiter : cardWriteLimiter, `${route.method} ${route.path}`);
    }
  });

  it('yazma 120/saat, okuma 1200/saat (429 + Retry-After)', () => {
    const fire = (limiter, userCode, times) => {
      const statuses = [];
      for (let i = 0; i < times; i += 1) {
        const req = { authUser: { user_code: userCode }, ip: `10.0.4.${userCode % 200}`, headers: {}, socket: { remoteAddress: `10.0.4.${userCode % 200}` } };
        const headers = {};
        const res = {
          setHeader: (key, value) => { headers[key] = value; },
          status(code) { statuses.push([code, headers['Retry-After']]); return { json() {} }; },
        };
        limiter(req, res, () => statuses.push([200]));
      }
      return statuses;
    };
    for (const [limiter, max, user] of [[cardWriteLimiter, 120, 779001], [cardReadLimiter, 1200, 779002]]) {
      const statuses = fire(limiter, user, max + 1);
      assert.equal(statuses.slice(0, max).every(([code]) => code === 200), true);
      assert.equal(statuses[max][0], 429);
      assert.ok(Number(statuses[max][1]) > 0);
    }
  });
});

describe('yönetim uçları: sıra biçim -> yetki -> site -> modül', () => {
  it('geçersiz site kodu 400 INVALID_SITE_CODE (veritabanına gitmeden)', async () => {
    const res = await call('GET', '/manager/sites/abc/access-cards', { user: users.manager });
    assert.deepEqual([res.status, res.body.code], [400, 'INVALID_SITE_CODE']);
    assert.equal(log.length, 0);
  });

  it('sakin / görevli (STAFF) / ilgisiz 403 FORBIDDEN_ROLE; başka sitenin yöneticisi 403 FORBIDDEN_SITE; olmayan site (süper) 404 SITE_NOT_FOUND', async () => {
    for (const user of [users.resident, users.staff, users.outsider]) {
      const list = await call('GET', M(), { user });
      const created = await call('POST', M(), { user, body: GOOD });
      const revoked = await call('POST', M('/5/revoke'), { user, body: {} });
      for (const res of [list, created, revoked]) assert.deepEqual([res.status, res.body.code], [403, 'FORBIDDEN_ROLE'], user.full_name);
    }
    for (const [method, path, body] of [['GET', M(), undefined], ['POST', M(), GOOD], ['POST', M('/5/revoke'), {}]]) {
      const other = await call(method, path, { user: users.otherManager, body });
      assert.deepEqual([other.status, other.body.code], [403, 'FORBIDDEN_SITE'], path);
    }
    const missing = await call('GET', '/manager/sites/1999999999/access-cards', { user: users.superUser });
    assert.deepEqual([missing.status, missing.body.code], [404, 'SITE_NOT_FOUND']);
    assert.equal(connects, 0);
  });

  it('modül KAPALI: süper / yönetici (okuma ve yazma) ve kurul (okuma) 403 MODULE_DISABLED { module: card_access }; yetki modülden ÖNCE denetlenir (kurul yazma, görevli, ilgisiz FORBIDDEN_ROLE)', async () => {
    state.moduleEnabled[SITE] = false;
    for (const user of [users.superUser, users.manager]) {
      for (const [method, path, body] of [['GET', M(), undefined], ['POST', M(), GOOD], ['POST', M('/5/revoke'), {}]]) {
        const res = await call(method, path, { user, body });
        assert.deepEqual([res.status, res.body.code, res.body.module], [403, 'MODULE_DISABLED', 'card_access'], `${user.full_name} ${method} ${path}`);
      }
    }
    const boardRead = await call('GET', M(), { user: users.board });
    assert.deepEqual([boardRead.status, boardRead.body.code, boardRead.body.module], [403, 'MODULE_DISABLED', 'card_access']);
    for (const [method, path, body] of [['POST', M(), GOOD], ['POST', M('/5/revoke'), {}]]) {
      assert.deepEqual([(await call(method, path, { user: users.board, body })).body.code], ['FORBIDDEN_ROLE'], path);
    }
    assert.equal((await call('GET', M(), { user: users.outsider })).body.code, 'FORBIDDEN_ROLE');
    assert.equal((await call('GET', M(), { user: users.staff })).body.code, 'FORBIDDEN_ROLE');
    assert.equal(connects, 0);
  });

  it('kurul SALT OKUR: GET 200 (UID açık, kişi adı ve daire etiketi); POST / iptal 403 FORBIDDEN_ROLE (işlem açılmadan)', async () => {
    seedCard({ card_uid: '04A3B2C1D5', label: 'Ana kapı' });
    const list = await call('GET', M(), { user: users.board });
    assert.equal(list.status, 200);
    assert.deepEqual(list.body, {
      items: [{ id: 1, person_id: 41, person_name: 'Sakin Bir', apartment_labels: ['A Blok - Daire 3'], card_uid: '04A3B2C1D5', label: 'Ana kapı', is_active: true, revoked_at: null, created_at: '2026-10-19T10:00:00.000Z' }],
      total: 1,
    });
    const created = await call('POST', M(), { user: users.board, body: GOOD });
    const revoked = await call('POST', M('/1/revoke'), { user: users.board, body: {} });
    for (const res of [created, revoked]) assert.deepEqual([res.status, res.body.code], [403, 'FORBIDDEN_ROLE']);
    assert.equal(connects, 0);
    assert.equal(state.cards.length, 1);
  });

  it('doğrulama hataları (yetkili yönetici) işlem açmadan döner: UID geçersiz 400 CARD_UID_INVALID; kişi yok / etiket uzun 400 INVALID_BODY; liste sorgusu 400 INVALID_QUERY', async () => {
    for (const uid of ['ab', 'A'.repeat(33), '04A3_B2C1', 'ÇAĞ1', 7, null, undefined]) {
      const res = await call('POST', M(), { user: users.manager, body: { person_id: 41, card_uid: uid } });
      assert.deepEqual([res.status, res.body.code], [400, 'CARD_UID_INVALID'], String(uid));
    }
    for (const body of [{ card_uid: 'ABCD' }, { person_id: 0, card_uid: 'ABCD' }, { person_id: 'x', card_uid: 'ABCD' }, { person_id: 41, card_uid: 'ABCD', label: 'x'.repeat(61) }, { person_id: 41, card_uid: 'ABCD', label: 5 }]) {
      const res = await call('POST', M(), { user: users.manager, body });
      assert.deepEqual([res.status, res.body.code], [400, 'INVALID_BODY'], JSON.stringify(body));
    }
    for (const query of ['?status=bogus', '?person_id=x', '?offset=-1']) {
      const res = await call('GET', M(query), { user: users.manager });
      assert.deepEqual([res.status, res.body.code], [400, 'INVALID_QUERY'], query);
    }
    assert.equal(connects, 0);
    assert.equal(state.cards.length, 0);
  });

  it('4 KB üstü gövde 413 BODY_TOO_LARGE (veritabanına gitmeden)', async () => {
    const res = await call('POST', M(), { user: users.manager, body: { ...GOOD, label: 'z'.repeat(5000) } });
    assert.deepEqual([res.status, res.body.code], [413, 'BODY_TOO_LARGE']);
    assert.equal(log.length, 0);
  });
});

describe('kart tanımlama ve iptal (sahte transaction)', () => {
  it('yönetici kart tanımlar: 201, UID kanonik, etiket sıkıştırılmış, kişi adı + daire; kilit sırası sites -> users -> site_people; audit yalnız son 4 karakter', async () => {
    withTransactions();
    const res = await call('POST', M(), { user: users.manager, body: GOOD });
    assert.equal(res.status, 201);
    assert.deepEqual(res.body, {
      item: { id: 1, person_id: 41, person_name: 'Sakin Bir', apartment_labels: ['A Blok - Daire 3'], card_uid: '04A3B2C1D5', label: 'Ana kapı', is_active: true, revoked_at: null, created_at: '2026-10-19T10:00:00.000Z' },
    });
    assert.equal(state.cards[0].created_by, 20001);
    assert.deepEqual(clientLog.slice(0, 4), [
      'BEGIN',
      'SELECT site_code FROM sites WHERE site_code = $1 FOR KEY SHARE',
      'SELECT user_code FROM users WHERE user_code = $1 AND deleted_at IS NULL FOR KEY SHARE',
      'SELECT id FROM site_people WHERE id = $1 AND site_code = $2 AND is_active = TRUE FOR KEY SHARE',
    ]);
    assert.equal(clientLog[clientLog.length - 1], 'COMMIT');
    assert.deepEqual(state.audit.map((a) => [a.actor_user_code, a.action, a.site_code, a.target_type, a.target_id, a.details]), [[20001, 'access_card.created', SITE, 'access_card', '1', { person_id: 41, uid_suffix: 'C1D5' }]]);
    assert.ok(!JSON.stringify(state.audit).includes('04A3B2C1D5'), 'audit tam UID taşımaz');
    const asSuper = await call('POST', M(), { user: users.superUser, body: { person_id: 42, card_uid: 'bbbb2222' } });
    assert.equal(asSuper.status, 201);
    assert.equal(asSuper.body.item.card_uid, 'BBBB2222');
    assert.equal(asSuper.body.item.label, null);
  });

  it('aynı sitede aynı AKTİF UID 409 CARD_EXISTS (ROLLBACK); iptalden sonra aynı UID yeniden verilir; başka sitede aynı UID serbest', async () => {
    withTransactions();
    assert.equal((await call('POST', M(), { user: users.manager, body: GOOD })).status, 201);
    const dup = await call('POST', M(), { user: users.manager, body: { person_id: 42, card_uid: '04a3-b2c1-d5' } });
    assert.deepEqual([dup.status, dup.body.code], [409, 'CARD_EXISTS']);
    assert.ok(!dup.body.error.includes('_'));
    assert.equal(clientLog[clientLog.length - 1], 'ROLLBACK');
    assert.equal(state.cards.length, 1);
    assert.equal((await call('POST', M('/1/revoke'), { user: users.manager, body: {} })).status, 200);
    const again = await call('POST', M(), { user: users.manager, body: { person_id: 42, card_uid: '04A3B2C1D5' } });
    assert.equal(again.status, 201);
    assert.deepEqual(state.cards.map((c) => [c.id, c.person_id, c.is_active]), [[1, 41, false], [2, 42, true]]);
    const otherSite = await call('POST', M('', OTHER_SITE), { user: users.otherManager, body: { person_id: 91, card_uid: '04A3B2C1D5' } });
    assert.equal(otherSite.status, 201);
    assert.deepEqual(otherSite.body.item.apartment_labels, ['Daire 1']);
  });

  it('kişi başka sitede ya da pasif: 404 PERSON_NOT_FOUND (varlık sızmaz; kart yazılmaz, işlem geri alınır)', async () => {
    withTransactions();
    for (const personId of [91, 43, 777]) {
      const res = await call('POST', M(), { user: users.manager, body: { person_id: personId, card_uid: 'ABCD1234' } });
      assert.deepEqual([res.status, res.body.code], [404, 'PERSON_NOT_FOUND'], String(personId));
    }
    assert.equal(state.cards.length, 0);
    assert.equal(clientLog.filter((s) => s === 'ROLLBACK').length, 3);
    assert.ok(!clientLog.some((s) => /^INSERT/.test(s)));
  });

  it('iptal: kayıt KALIR (is_active=false, revoked_at); audit access_card.revoked; yeniden iptal 409 INVALID_STATE; olmayan / başka sitenin / biçimsiz kimlik 404 CARD_NOT_FOUND', async () => {
    withTransactions();
    seedCard({ person_id: 42, card_uid: 'BBBB2222', label: 'Yedek' });
    seedCard({ site_code: OTHER_SITE, person_id: 91, card_uid: 'CCCC3333' });
    const res = await call('POST', M('/1/revoke'), { user: users.manager, body: {} });
    assert.equal(res.status, 200);
    assert.deepEqual(res.body.item, { id: 1, person_id: 42, person_name: 'Sakin İki', apartment_labels: ['A Blok - Daire 4'], card_uid: 'BBBB2222', label: 'Yedek', is_active: false, revoked_at: '2026-10-19T11:00:00.000Z', created_at: '2026-10-19T10:00:00.000Z' });
    assert.equal(state.cards.length, 2, 'iptal silmez');
    assert.deepEqual(state.audit.map((a) => [a.action, a.target_id, a.details]), [['access_card.revoked', '1', { person_id: 42, uid_suffix: '2222' }]]);
    assert.ok(clientLog.includes('SELECT id, person_id, card_uid, is_active FROM access_cards WHERE id = $1 AND site_code = $2 FOR UPDATE'));
    const again = await call('POST', M('/1/revoke'), { user: users.manager, body: {} });
    assert.deepEqual([again.status, again.body.code], [409, 'INVALID_STATE']);
    const before = connects;
    for (const id of ['999', '2', 'abc', '0']) {
      const notFound = await call('POST', M(`/${id}/revoke`), { user: users.superUser, body: {} });
      assert.deepEqual([notFound.status, notFound.body.code], [404, 'CARD_NOT_FOUND'], id);
    }
    assert.equal(connects - before, 2, 'biçimsiz kimlik (abc, 0) işlem açmaz');
    assert.equal(state.cards[1].is_active, true, 'başka sitenin kartına dokunulmaz');
    assert.equal(state.audit.length, 1);
  });

  it('yönetim listesi: varsayılan yalnız aktif; status=all / revoked; person_id ve q süzgeci; total süzgeçle uyumlu', async () => {
    seedCard({ card_uid: '04A3B2C1D5' });
    seedCard({ person_id: 42, card_uid: 'BBBB2222' });
    seedCard({ person_id: 42, card_uid: 'DDDD4444', is_active: false, revoked_at: REVOKED_AT });
    seedCard({ site_code: OTHER_SITE, person_id: 91, card_uid: 'CCCC3333' });
    const active = await call('GET', M(), { user: users.manager });
    assert.deepEqual([active.status, active.body.total, active.body.items.map((i) => i.id)], [200, 2, [2, 1]]);
    const all = await call('GET', M('?status=all&limit=10&offset=0'), { user: users.manager });
    assert.deepEqual([all.body.total, all.body.items.map((i) => [i.id, i.is_active])], [3, [[2, true], [1, true], [3, false]]]);
    const revoked = await call('GET', M('?status=revoked'), { user: users.manager });
    assert.deepEqual([revoked.body.total, revoked.body.items.map((i) => i.id), revoked.body.items[0].revoked_at], [1, [3], '2026-10-19T11:00:00.000Z']);
    const byPerson = await call('GET', M('?person_id=42&status=all'), { user: users.manager });
    assert.deepEqual([byPerson.body.total, byPerson.body.items.map((i) => i.id)], [2, [2, 3]]);
    const byUid = await call('GET', M('?q=04a3'), { user: users.manager });
    assert.deepEqual([byUid.body.total, byUid.body.items.map((i) => i.card_uid)], [1, ['04A3B2C1D5']]);
    assert.ok(all.body.items.every((i) => Object.keys(i).join() === 'id,person_id,person_name,apartment_labels,card_uid,label,is_active,revoked_at,created_at'));
  });
});

describe('sakin: GET /app/access-cards', () => {
  it('yalnız KENDİ kişi kayıtlarına bağlı kartlar; UID maskeli (son 4); kişi kimliği / tam UID yok; iptal edilen de görünür', async () => {
    seedCard({ card_uid: '04A3B2C1D5', label: 'Ana kapı' });
    seedCard({ card_uid: 'AAAA1111', is_active: false, revoked_at: REVOKED_AT });
    seedCard({ person_id: 42, card_uid: 'BBBB2222' });
    seedCard({ site_code: OTHER_SITE, person_id: 91, card_uid: 'CCCC3333' });
    const mine = await call('GET', '/app/access-cards', { user: users.resident });
    assert.equal(mine.status, 200);
    assert.deepEqual(mine.body, {
      items: [
        { id: 4, site_code: OTHER_SITE, site_name: 'Başka Site', masked_uid: '****3333', label: null, is_active: true, revoked_at: null, created_at: '2026-10-19T10:00:00.000Z' },
        { id: 1, site_code: SITE, site_name: 'Gül Sitesi', masked_uid: '******C1D5', label: 'Ana kapı', is_active: true, revoked_at: null, created_at: '2026-10-19T10:00:00.000Z' },
        { id: 2, site_code: SITE, site_name: 'Gül Sitesi', masked_uid: '****1111', label: null, is_active: false, revoked_at: '2026-10-19T11:00:00.000Z', created_at: '2026-10-19T10:00:00.000Z' },
      ],
    });
    const text = JSON.stringify(mine.body);
    for (const secret of ['04A3B2C1D5', 'AAAA1111', 'BBBB2222', 'CCCC3333', 'card_uid', 'person_id', 'person_name', 'Sakin İki']) assert.ok(!text.includes(secret), secret);
    const other = await call('GET', '/app/access-cards', { user: users.resident2 });
    assert.deepEqual(other.body.items.map((i) => [i.id, i.masked_uid]), [[3, '****2222']]);
    assert.deepEqual((await call('GET', '/app/access-cards', { user: users.outsider })).body, { items: [] });
  });

  it('site_code süzgeci; modülü KAPALI site atlanır (sessizce boş); geçersiz site_code 400 INVALID_QUERY; sakin yazamaz (yönetim ucu 403)', async () => {
    seedCard({ card_uid: '04A3B2C1D5' });
    seedCard({ site_code: OTHER_SITE, person_id: 91, card_uid: 'CCCC3333' });
    const filtered = await call('GET', `/app/access-cards?site_code=${SITE}`, { user: users.resident });
    assert.deepEqual(filtered.body.items.map((i) => i.id), [1]);
    state.moduleEnabled[SITE] = false;
    assert.deepEqual((await call('GET', `/app/access-cards?site_code=${SITE}`, { user: users.resident })).body, { items: [] });
    assert.deepEqual((await call('GET', '/app/access-cards', { user: users.resident })).body.items.map((i) => i.id), [2]);
    const bad = await call('GET', '/app/access-cards?site_code=abc', { user: users.resident });
    assert.deepEqual([bad.status, bad.body.code], [400, 'INVALID_QUERY']);
    assert.equal((await call('POST', M(), { user: users.resident, body: GOOD })).body.code, 'FORBIDDEN_ROLE');
    assert.equal(connects, 0);
  });
});
