// Plaka Tanıma yönetici canlı geçiş akışı (GET /manager/sites/:siteCode/plate-recognition/events?since|live): yetki matrisi (yönetici + kurul okur,
// sakin / ilgisiz 403, başka site 403 FORBIDDEN_SITE), geçersiz since 400, yanıt biçimi (yön, karar türü, kapı, içeride sayısı, ayar) ve since süzgeci. DB'siz (sahte havuz).
import { describe, it, before, after, beforeEach, afterEach, mock } from 'node:test';
import assert from 'node:assert/strict';
import express from 'express';
import { pool } from '../src/db.js';
import { eventsLimiter, plateRecognitionRouter } from '../src/modules/plate_recognition_routes.js';
import { liveFeedConfig, parseListQuery, parseSince } from '../src/modules/plate_recognition_common.js';

const SITE_1 = 1000000001;
const SITE_2 = 1000000002;
const mk = (id, role) => ({ id, user_code: id, userCode: id, role, full_name: `U${id}`, email: `u${id}@example.com` });
const users = {
  mgrA: mk(20001, 'site_manager'),
  mgrB: mk(20002, 'site_manager'),
  resident: mk(20004, 'apartment_owner'),
  board: mk(20006, 'individual'),
  outsider: mk(20008, 'individual'),
};
const norm = (text) => String(text).replace(/\s+/g, ' ').trim();
const ok = (rows = []) => ({ rows, rowCount: rows.length });

let log;
let eventRows;

function handle(sql, params) {
  log.push({ sql, params });
  if (/^SELECT 1 FROM site_manager_sites WHERE site_code = \$1 AND manager_user_code = \$2 LIMIT 1$/.test(sql)) {
    const [site, user] = params.map(Number);
    return ok((site === SITE_1 && user === 20001) || (site === SITE_2 && user === 20002) ? [{ x: 1 }] : []);
  }
  if (/FROM site_memberships WHERE site_code = \$1 AND user_code = \$2 AND role IN \('SITE_OWNER', 'SITE_ADMIN'\)/.test(sql)) return ok([]);
  if (/is_board_here/.test(sql)) {
    const [site, user] = params.map(Number);
    return ok([{ is_board_here: site === SITE_1 && user === 20006, is_member_here: (site === SITE_1 && user === 20006) || user === 20004, has_other_role: user === 20002 || user === 20006 }]);
  }
  if (/FROM site_memberships WHERE site_code = \$1 AND user_code = \$2 AND role = 'STAFF'/.test(sql)) return ok([]);
  if (/^SELECT site_code FROM sites WHERE site_code = \$1 LIMIT 1$/.test(sql)) return ok([SITE_1, SITE_2].includes(Number(params[0])) ? [{ site_code: String(params[0]) }] : []);
  if (/^SELECT enabled FROM site_modules/.test(sql)) return ok([{ enabled: true }]);
  if (/FROM plate_decisions d/.test(sql)) return ok(eventRows);
  if (/FROM plate_presence WHERE site_code = \$1 AND inside/.test(sql)) return ok([{ n: 7 }]);
  if (/^(INSERT|UPDATE|DELETE)\b/.test(sql)) throw new Error(`BEKLENMEYEN yazma SQL: ${sql.slice(0, 160)}`);
  return ok();
}

let server;
let baseUrl;

before(async () => {
  const layer = plateRecognitionRouter.stack.find((l) => l.route && l.route.path.endsWith('/plate-recognition/events'));
  layer.route.stack[0].handle = (req, _res, next) => {
    req.authUser = JSON.parse(decodeURIComponent(req.headers['x-test-user']));
    next();
  };
  const app = express();
  app.use(express.json());
  app.use(plateRecognitionRouter);
  await new Promise((resolve) => {
    server = app.listen(0, '127.0.0.1', resolve);
  });
  baseUrl = `http://127.0.0.1:${server.address().port}`;
});

after(async () => {
  server.closeAllConnections?.();
  await new Promise((resolve) => server.close(resolve));
  delete pool.query;
});

beforeEach(() => {
  log = [];
  eventRows = [
    { id: '12', plate: '34ABC123', decision: 'ALLOWED', decision_kind: 'acildi', direction: 'giris', reason: 'resident', confidence: '0.97', auto_action: 'none', decided_at: new Date('2026-10-29T10:00:00Z'), seen_at: new Date('2026-10-29T10:00:00Z'), device_name: 'Kamera 1', door_name: 'Ana Giriş' },
    { id: '11', plate: '06XYZ99', decision: 'DENIED', decision_kind: null, direction: null, reason: 'blacklisted', confidence: null, auto_action: 'none', decided_at: new Date('2026-10-29T09:59:00Z'), seen_at: null, device_name: null, door_name: null },
  ];
  pool.query = async (text, params) => handle(norm(text), params ?? []);
  mock.method(console, 'error', () => {});
});

afterEach(() => {
  mock.restoreAll();
  eventsLimiter.reset();
});

const get = async (site, user, qs = '') => {
  const response = await fetch(`${baseUrl}/manager/sites/${site}/plate-recognition/events${qs}`, { headers: { 'x-test-user': encodeURIComponent(JSON.stringify(user)) } });
  return { status: response.status, body: await response.json() };
};

describe('plaka canli akis ucu', () => {
  it('yonetici ve kurul okur; yanit yon, karar turu, kapi, iceride sayisi ve yenileme ayarini tasir', async () => {
    for (const user of [users.mgrA, users.board]) {
      const { status, body } = await get(SITE_1, user, '?live=1');
      assert.equal(status, 200);
      assert.equal(body.inside_count, 7);
      assert.equal(body.refresh_seconds, 5);
      assert.equal(body.limit, 30);
      assert.equal(body.events.length, 2);
      assert.deepEqual(
        { id: body.events[0].id, direction: body.events[0].direction, decision_kind: body.events[0].decision_kind, door_name: body.events[0].door_name },
        { id: 12, direction: 'giris', decision_kind: 'acildi', door_name: 'Ana Giriş' },
      );
      assert.equal(body.events[1].direction, null);
    }
    const sql = log.find((entry) => /FROM plate_decisions d/.test(entry.sql));
    assert.equal(sql.params[2], 31, 'limit + 1 (ayardan 30)');
  });

  it('since: kayit numarasi ya da ISO zamani sorguya baglanir; canli ek alanlar since ile de gelir', async () => {
    const byId = await get(SITE_1, users.mgrA, '?since=11');
    assert.equal(byId.status, 200);
    assert.equal(byId.body.inside_count, 7);
    assert.equal(log.find((e) => /FROM plate_decisions d/.test(e.sql)).params[4], 11);
    log = [];
    const byTime = await get(SITE_1, users.mgrA, '?since=2026-10-29T09:00:00Z');
    assert.equal(byTime.status, 200);
    assert.equal(log.find((e) => /FROM plate_decisions d/.test(e.sql)).params[5].toISOString(), '2026-10-29T09:00:00.000Z');
  });

  it('canli olmayan cagri eski bicimi korur (inside_count yok)', async () => {
    const { status, body } = await get(SITE_1, users.mgrA);
    assert.equal(status, 200);
    assert.equal(body.inside_count, undefined);
    assert.ok(Array.isArray(body.events));
  });

  it('gecersiz since 400 INVALID_BODY; sakin / ilgisiz 403 FORBIDDEN_ROLE; baska sitenin yoneticisi 403 FORBIDDEN_SITE; bilinmeyen site 403', async () => {
    assert.equal((await get(SITE_1, users.mgrA, '?since=yarin')).body.code, 'INVALID_BODY');
    for (const user of [users.resident, users.outsider]) {
      const { status, body } = await get(SITE_1, user, '?live=1');
      assert.equal(status, 403);
      assert.equal(body.code, 'FORBIDDEN_ROLE');
    }
    const other = await get(SITE_1, users.mgrB, '?live=1');
    assert.equal(other.status, 403);
    assert.equal(other.body.code, 'FORBIDDEN_SITE');
    assert.equal((await get(999, users.mgrA, '?live=1')).status, 403);
    assert.equal(log.some((e) => /FROM plate_decisions d/.test(e.sql)), false, '403 durumunda veri sorgusu calismaz');
  });
});

describe('canli akis ayarlari ve sorgu', () => {
  it('liveFeedConfig ortamdan okunur ve araliga sikistirilir', () => {
    assert.deepEqual(liveFeedConfig({}), { refresh_seconds: 5, limit: 30 });
    assert.deepEqual(liveFeedConfig({ PLATE_LIVE_REFRESH_SECONDS: '1', PLATE_LIVE_LIMIT: '9999' }), { refresh_seconds: 2, limit: 100 });
    assert.deepEqual(liveFeedConfig({ PLATE_LIVE_REFRESH_SECONDS: '10', PLATE_LIVE_LIMIT: '20' }), { refresh_seconds: 10, limit: 20 });
  });

  it('parseSince ve parseListQuery', () => {
    assert.deepEqual(parseSince(undefined), { id: null, at: null });
    assert.equal(parseSince('42').id, 42);
    assert.throws(() => parseSince('abc'), (error) => error.statusCode === 400);
    assert.equal(parseListQuery({}).live, false);
    assert.equal(parseListQuery({}).limit, 50);
    assert.equal(parseListQuery({ live: '1' }).limit, 30);
    assert.equal(parseListQuery({ live: '1', limit: '5' }).limit, 5);
  });
});
