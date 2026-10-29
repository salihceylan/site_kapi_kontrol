// Acil durum akışı (107, P2-24): şema <-> migration, girdi kuralları, kapsam ("adres bilgisi DOĞRU siteden") ve uçlar.
// DB'siz, KATI sahte veritabanı: tanımsız SQL fırlatır. Kimlik katmanı sahte (x-test-user); gerçek HTTP, gerçek Express.
// Gerçek PostgreSQL doğrulaması: tablo ve kısıtlar migrations/107_site_emergency_info.sql (deploy provasında tablo varlığı).
import { describe, it, before, after, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import express from 'express';
import { DEFAULT_MIGRATIONS_DIR, findUnsafeStatements } from '../scripts/migrate.js';
import { pool } from '../src/db.js';
import { authRequired } from '../src/middlewares/auth_middleware.js';
import { EMERGENCY_DDL, ensureEmergencySchema } from '../src/modules/emergency_schema.js';
import { emergencyReadLimiter, emergencyRouter, emergencyWriteLimiter } from '../src/modules/emergency_routes.js';
import {
  FIRM_NAME_MAX,
  listEmergencySites,
  normalizeFirmName,
  normalizeFirmPhone,
  parseEmergencyInfoBody,
} from '../src/modules/emergency_service.js';
import { MODULE_CATALOG } from '../src/modules/catalog.js';

process.env.JWT_SECRET ||= 'emergency-test-secret';
const here = path.dirname(fileURLToPath(import.meta.url));
const norm = (s) => String(s).replace(/\r\n/g, '\n').replace(/--.*$/gm, '').replace(/\s+/g, ' ').replace(/ ?\( ?/g, '(').replace(/ ?\) ?/g, ')').replace(/ ?, ?/g, ',').trim();
const sqlNorm = (text) => String(text).replace(/\s+/g, ' ').trim();
const MIGRATION = readFileSync(path.join(DEFAULT_MIGRATIONS_DIR, '107_site_emergency_info.sql'), 'utf8');
const DB_SOURCE = readFileSync(path.join(here, '..', 'src', 'db.js'), 'utf8');
const SERVER_SOURCE = readFileSync(path.join(here, '..', 'src', 'server.js'), 'utf8');

const SITE_A = 1000000001;
const SITE_B = 1000000002;
const SITE_C = 1000000003;
const mk = (id, role, name) => ({ id, user_code: id, userCode: id, role, full_name: name, email: `u${id}@example.com` });
const users = {
  superUser: mk(1, 'super_user', 'Süper'),
  managerA: mk(20001, 'site_manager', 'A Yöneticisi'),
  residentB: mk(20002, 'apartment_owner', 'B Sakini'),
  mixed: mk(20003, 'site_manager', 'A Yöneticisi, B Sakini'),
  board: mk(20004, 'individual', 'Kurul'),
  staff: mk(20005, 'individual', 'Görevli'),
  loner: mk(20006, 'individual', 'Sitesiz'),
};

describe('107 şema', () => {
  it('db.js DDL migration ile birebir ve idempotent', () => {
    const all = norm(MIGRATION);
    for (const [name, sql] of Object.entries(EMERGENCY_DDL)) {
      assert.match(sql, /IF NOT EXISTS/, name);
      assert.ok(all.includes(norm(sql)), `${name} migration ile ayni degil`);
    }
    assert.deepEqual(findUnsafeStatements(MIGRATION), []);
  });

  it('ekleyici: DROP / DELETE / UPDATE yok; kullanıcıya yabancı anahtar yok (hesap silme politikası dışı)', () => {
    for (const sql of Object.values(EMERGENCY_DDL)) {
      assert.doesNotMatch(sql, /\b(DROP|TRUNCATE|DELETE FROM|UPDATE)\b/i);
      assert.doesNotMatch(sql, /REFERENCES users/i);
      assert.match(sql, /REFERENCES sites\(site_code\) ON DELETE CASCADE/);
    }
  });

  it('tablo varsa hiçbir DDL gönderilmez; yoksa kilit zaman aşımıyla oluşturulur', async () => {
    const sent = [];
    const mk2 = (exists) => ({
      async query(sql) {
        if (/to_regclass/.test(sql)) return { rows: [{ ok: exists }] };
        sent.push(sqlNorm(sql));
        return { rows: [] };
      },
    });
    await ensureEmergencySchema(mk2(true));
    assert.equal(sent.length, 0);
    await ensureEmergencySchema(mk2(false));
    assert.equal(sent.length, 3);
    assert.match(sent[0], /SET lock_timeout/);
    assert.match(sent[1], /CREATE TABLE IF NOT EXISTS site_emergency_info/);
    assert.match(sent[2], /RESET lock_timeout/);
  });

  it('db.js ensureEmergencySchema çağırır; server.js router kaydeder (tek satır)', () => {
    assert.match(DB_SOURCE, /await ensureEmergencySchema\(client\)/);
    assert.match(SERVER_SOURCE, /app\.use\(emergencyRouter\)/);
  });

  it('modül DEĞİLDİR: katalogda acil durum kodu yok (kapatılamaz, talep edilemez)', () => {
    assert.equal(MODULE_CATALOG.some((m) => /emergency|acil/i.test(m.code)), false);
  });
});

describe('girdi kuralları', () => {
  it('firma adı: boşluklar teke iner, görünmez karakter atılır, boş -> null, sınır', () => {
    assert.equal(normalizeFirmName('  Yıldız   Asansör  '), 'Yıldız Asansör');
    assert.equal(normalizeFirmName(`A${String.fromCharCode(0x200b)}B${String.fromCharCode(0x202e)}`), 'AB');
    assert.equal(normalizeFirmName('   '), null);
    assert.equal(normalizeFirmName(undefined), null);
    assert.equal(normalizeFirmName(null), null);
    assert.equal(normalizeFirmName('x'.repeat(FIRM_NAME_MAX)), 'x'.repeat(FIRM_NAME_MAX));
    assert.throws(() => normalizeFirmName('x'.repeat(FIRM_NAME_MAX + 1)), (e) => e.code === 'INVALID_FIELD' && e.extra.field === 'elevator_firm_name');
    assert.throws(() => normalizeFirmName(5), (e) => e.code === 'INVALID_FIELD');
  });

  it('telefon: +90, sabit hat ve kısa numara kabul; harf, eksik / fazla hane ve aşırı uzunluk reddedilir', () => {
    assert.equal(normalizeFirmPhone('+90 532 123 45 67'), '+90 532 123 45 67');
    assert.equal(normalizeFirmPhone(' 0212  555 12 34 '), '0212 555 12 34');
    assert.equal(normalizeFirmPhone('444 1 234'), '444 1 234');
    assert.equal(normalizeFirmPhone('112'), '112');
    assert.equal(normalizeFirmPhone(''), null);
    assert.equal(normalizeFirmPhone(null), null);
    for (const bad of ['12', 'abc 123 45', '+90 532 abc', '1234567890123456', '+', 'tel:112', '0212;555', 7]) {
      assert.throws(() => normalizeFirmPhone(bad), (e) => e.code === 'INVALID_FIELD' && e.extra.field === 'elevator_firm_phone', String(bad));
    }
    assert.throws(() => normalizeFirmPhone(`+${'1 '.repeat(20)}`), (e) => e.code === 'INVALID_FIELD');
  });

  it('gövde: iki alan yerine yazılır; hiçbiri gönderilmezse 400; telefonsuz firma adı 400; ikisi boşsa silme', () => {
    assert.deepEqual(parseEmergencyInfoBody({ elevator_firm_name: ' Yıldız Asansör ', elevator_firm_phone: '0212 555 12 34' }), { name: 'Yıldız Asansör', phone: '0212 555 12 34' });
    assert.deepEqual(parseEmergencyInfoBody({ elevator_firm_phone: '0212 555 12 34' }), { name: null, phone: '0212 555 12 34' });
    assert.deepEqual(parseEmergencyInfoBody({ elevator_firm_name: '', elevator_firm_phone: null }), { name: null, phone: null });
    for (const body of [undefined, null, {}, [], 'x', { baska: 1 }]) {
      assert.throws(() => parseEmergencyInfoBody(body), (e) => e.code === 'INVALID_BODY', JSON.stringify(body));
    }
    assert.throws(() => parseEmergencyInfoBody({ elevator_firm_name: 'Yıldız Asansör' }), (e) => e.code === 'INVALID_FIELD' && e.extra.field === 'elevator_firm_phone');
  });
});

// --------------------------------------------------------------------------------------------------------------------------
// Sahte veritabanı
// --------------------------------------------------------------------------------------------------------------------------

const ok = (rows = []) => ({ rows, rowCount: rows.length });
let state;
let log;
let clientLog;
let connects;

function makeState() {
  return {
    sites: {
      [SITE_A]: { name: 'Gül Sitesi', address: 'Atatürk Mah. 12. Sok. No: 5', city: 'İstanbul', district: 'Kadıköy' },
      [SITE_B]: { name: 'Lale Sitesi', address: 'Cumhuriyet Mah. 3. Cad. No: 9', city: 'Ankara', district: 'Çankaya' },
      [SITE_C]: { name: 'Başka Site', address: 'Gizli Mah. 1. Sok.', city: 'İzmir', district: 'Konak' },
    },
    emergency: { [SITE_A]: { name: 'Yıldız Asansör', phone: '+905321234567' } },
    // kullanıcı -> [{ site_code, rank }]  (4 yönetici, 3 kurul, 2 görevli, 1 sakin: MY_SITES_SQL)
    links: {
      20001: [{ site_code: SITE_A, rank: 4 }],
      20002: [{ site_code: SITE_B, rank: 1 }],
      20003: [{ site_code: SITE_A, rank: 4 }, { site_code: SITE_B, rank: 1 }],
      20004: [{ site_code: SITE_A, rank: 3 }],
      20005: [{ site_code: SITE_A, rank: 2 }],
    },
    audit: [],
    writes: [],
  };
}

function fakeQuery(text, params = []) {
  const sql = sqlNorm(text);
  log.push({ sql, params });
  if (sql.startsWith('WITH links AS')) {
    const rows = (state.links[Number(params[0])] ?? [])
      .map((l) => ({ site_code: String(l.site_code), site_name: state.sites[l.site_code].name, management_type: 'apartment_site', rank: l.rank, door_access: true }))
      .sort((a, b) => a.site_name.localeCompare(b.site_name, 'tr'));
    return ok(rows);
  }
  if (/^SELECT s\.site_code, s\.address, s\.city, s\.district, e\.elevator_firm_name, e\.elevator_firm_phone FROM sites s LEFT JOIN site_emergency_info e ON e\.site_code = s\.site_code WHERE s\.site_code = ANY\(\$1::BIGINT\[\]\)$/.test(sql)) {
    return ok(
      params[0]
        .filter((code) => state.sites[code])
        .map((code) => ({
          site_code: String(code),
          address: state.sites[code].address,
          city: state.sites[code].city,
          district: state.sites[code].district,
          elevator_firm_name: state.emergency[code]?.name ?? null,
          elevator_firm_phone: state.emergency[code]?.phone ?? null,
        })),
    );
  }
  if (/^SELECT 1 FROM site_manager_sites WHERE site_code = \$1 AND manager_user_code = \$2 LIMIT 1$/.test(sql)) {
    const [site, user] = params.map(Number);
    return ok((state.links[user] ?? []).filter((l) => l.site_code === site && l.rank === 4).map(() => ({ x: 1 })));
  }
  if (/^SELECT 1 FROM site_memberships WHERE site_code = \$1 AND user_code = \$2 AND role IN \('SITE_OWNER', 'SITE_ADMIN'\) AND is_active = TRUE LIMIT 1$/.test(sql)) return ok();
  if (/^SELECT EXISTS \( SELECT 1 FROM site_memberships WHERE site_code = \$1 AND user_code = \$2 AND role = 'BOARD_MEMBER'/.test(sql)) {
    const [site, user] = params.map(Number);
    const here = (state.links[user] ?? []).filter((l) => l.site_code === site);
    const other = (state.links[user] ?? []).some((l) => l.rank >= 3);
    return ok([{ is_board_here: here.some((l) => l.rank === 3), is_member_here: here.length > 0, has_other_role: other }]);
  }
  if (/^SELECT site_code FROM sites WHERE site_code = \$1 LIMIT 1$/.test(sql)) return ok(state.sites[Number(params[0])] ? [{ site_code: String(params[0]) }] : []);
  throw new Error(`BEKLENMEYEN SQL (sahte DB katı): ${sql.slice(0, 200)}`);
}

function fakeClient() {
  return {
    async query(text, params = []) {
      const sql = sqlNorm(text);
      clientLog.push({ sql, params });
      if (/^(BEGIN|COMMIT|ROLLBACK)$/.test(sql)) return ok();
      if (/^(SAVEPOINT|RELEASE SAVEPOINT|ROLLBACK TO SAVEPOINT) audit_insert$/.test(sql)) return ok();
      if (/^INSERT INTO site_emergency_info \(site_code, elevator_firm_name, elevator_firm_phone\) VALUES \(\$1, \$2, \$3\) ON CONFLICT \(site_code\) DO UPDATE SET elevator_firm_name = EXCLUDED\.elevator_firm_name, elevator_firm_phone = EXCLUDED\.elevator_firm_phone, updated_at = NOW\(\)$/.test(sql)) {
        const [site, name, phone] = params;
        state.emergency[Number(site)] = { name, phone };
        state.writes.push({ op: 'upsert', site: Number(site), name, phone });
        return ok();
      }
      if (sql === 'DELETE FROM site_emergency_info WHERE site_code = $1') {
        delete state.emergency[Number(params[0])];
        state.writes.push({ op: 'delete', site: Number(params[0]) });
        return ok();
      }
      if (/^INSERT INTO audit_log \(/.test(sql)) {
        state.audit.push({ actor_user_code: params[0], action: params[3], site_code: params[4], target_type: params[5], target_id: params[6], details: JSON.parse(params[7]) });
        return ok();
      }
      throw new Error(`BEKLENMEYEN transaction SQL (sahte DB katı): ${sql.slice(0, 200)}`);
    },
    release() {},
  };
}

const ORIGINAL_ROUTES = emergencyRouter.stack
  .filter((layer) => layer.route)
  .map((layer) => ({ path: layer.route.path, method: Object.keys(layer.route.methods)[0], handlers: layer.route.stack.map((entry) => entry.handle) }));

let server;
let baseUrl;

before(async () => {
  for (const layer of emergencyRouter.stack) {
    if (!layer.route) continue;
    layer.route.stack[0].handle = (req, res, next) => {
      const header = req.headers['x-test-user'];
      if (!header) return res.status(401).json({ error: 'Oturum gerekli.' });
      req.authUser = JSON.parse(decodeURIComponent(header));
      return next();
    };
    layer.route.stack[1].handle = (_req, _res, next) => next(); // hız sınırlayıcılar rota zincirinde sınanır
  }
  const app = express();
  app.use(express.json({ limit: '1mb' }));
  app.use(emergencyRouter);
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
    connects += 1;
    return fakeClient();
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

const PUT = (site = SITE_A) => `/manager/sites/${site}/emergency`;
const GOOD = { elevator_firm_name: '  Yıldız   Asansör ', elevator_firm_phone: '0212  555 12 34' };

describe('rota zinciri', () => {
  it('iki uç vardır; her biri authRequired ile BAŞLAR, ikinci halka hız sınırlayıcıdır (GET: okuma; PUT: yazma)', () => {
    const routes = ORIGINAL_ROUTES.map((route) => `${route.method.toUpperCase()} ${route.path}`);
    assert.deepEqual([...routes].sort(), ['GET /app/emergency', 'PUT /manager/sites/:siteCode/emergency']);
    for (const route of ORIGINAL_ROUTES) {
      assert.equal(route.handlers[0], authRequired, `${route.method} ${route.path}`);
      assert.equal(route.handlers[1], route.method === 'get' ? emergencyReadLimiter : emergencyWriteLimiter, `${route.method} ${route.path}`);
    }
  });

  it('kimliksiz istek 401 ve veritabanına gitmez', async () => {
    assert.equal((await call('GET', '/app/emergency')).status, 401);
    assert.equal((await call('PUT', PUT(), { body: GOOD })).status, 401);
    assert.equal(log.length, 0);
    assert.equal(connects, 0);
  });
});

describe('GET /app/emergency: adres bilgisi DOĞRU siteden', () => {
  it('yönetici + sakin: her sitenin kendi adresi, kendi firması; yalnız yöneticisi olunan sitede can_edit', async () => {
    const res = await call('GET', '/app/emergency', { user: users.mixed });
    assert.equal(res.status, 200);
    assert.equal(res.headers.get('cache-control'), 'no-store');
    assert.deepEqual(res.body.sites, [
      { site_code: SITE_A, site_name: 'Gül Sitesi', address: 'Atatürk Mah. 12. Sok. No: 5', city: 'İstanbul', district: 'Kadıköy', elevator_firm_name: 'Yıldız Asansör', elevator_firm_phone: '+905321234567', can_edit: true },
      { site_code: SITE_B, site_name: 'Lale Sitesi', address: 'Cumhuriyet Mah. 3. Cad. No: 9', city: 'Ankara', district: 'Çankaya', elevator_firm_name: null, elevator_firm_phone: null, can_edit: false },
    ]);
  });

  it('başka sitenin adresi / firması ASLA dönmez: sorgu yalnız kullanıcının bağlı olduğu site kodlarıyla çalışır', async () => {
    const res = await call('GET', '/app/emergency', { user: users.residentB });
    assert.deepEqual(res.body.sites.map((s) => s.site_code), [SITE_B]);
    assert.doesNotMatch(JSON.stringify(res.body), /Gül Sitesi|Başka Site|Yıldız Asansör|Gizli Mah/);
    const detail = log.find((entry) => /FROM sites s LEFT JOIN site_emergency_info/.test(entry.sql));
    assert.deepEqual(detail.params, [[SITE_B]]);
    const mine = log.find((entry) => entry.sql.startsWith('WITH links AS'));
    assert.deepEqual(mine.params, [20002]);
  });

  it('kurul ve görevli sitenin bilgisini görür ama düzenleyemez (can_edit false)', async () => {
    for (const user of [users.board, users.staff]) {
      const res = await call('GET', '/app/emergency', { user });
      assert.equal(res.status, 200);
      assert.equal(res.body.sites.length, 1);
      assert.equal(res.body.sites[0].site_code, SITE_A);
      assert.equal(res.body.sites[0].can_edit, false);
      assert.equal(res.body.sites[0].elevator_firm_phone, '+905321234567');
    }
  });

  it('sitesi olmayan kullanıcı ve süper kullanıcı: boş liste (süper için veritabanı sorgusu bile yok)', async () => {
    const lonely = await call('GET', '/app/emergency', { user: users.loner });
    assert.deepEqual(lonely.body, { sites: [] });
    assert.equal(log.filter((entry) => /site_emergency_info/.test(entry.sql)).length, 0, 'bağsız kullanıcı için ikinci sorgu yok');
    log.length = 0;
    const sup = await call('GET', '/app/emergency', { user: users.superUser });
    assert.deepEqual(sup.body, { sites: [] });
    assert.equal(log.length, 0);
  });

  it('adres alanları boşsa null döner (istemci "adres kayıtlı değil" der); boşluk-yalnız değerler null olur', async () => {
    state.sites[SITE_A].address = '   ';
    state.sites[SITE_A].city = null;
    const res = await call('GET', '/app/emergency', { user: users.managerA });
    assert.equal(res.body.sites[0].address, null);
    assert.equal(res.body.sites[0].city, null);
    assert.equal(res.body.sites[0].district, 'Kadıköy');
  });

  it('servis doğrudan: kullanıcı kodu çözümlenemeyen kimlik boş liste verir', async () => {
    assert.deepEqual(await listEmergencySites({ role: 'individual' }, { query: async () => { throw new Error('sorgu olmamalı'); } }), { sites: [] });
  });
});

describe('PUT /manager/sites/:siteCode/emergency', () => {
  it('yönetici firmayı yazar: değerler temizlenir, upsert + denetim kaydı (telefon günlüğe YAZILMAZ)', async () => {
    const res = await call('PUT', PUT(), { user: users.managerA, body: GOOD });
    assert.equal(res.status, 200);
    assert.deepEqual(res.body, { site_code: SITE_A, elevator_firm_name: 'Yıldız Asansör', elevator_firm_phone: '0212 555 12 34' });
    assert.deepEqual(state.writes, [{ op: 'upsert', site: SITE_A, name: 'Yıldız Asansör', phone: '0212 555 12 34' }]);
    assert.equal(state.audit.length, 1);
    assert.equal(state.audit[0].action, 'emergency.info_updated');
    assert.equal(state.audit[0].site_code, SITE_A);
    assert.deepEqual(state.audit[0].details, { elevator_firm: 'set' });
    assert.doesNotMatch(JSON.stringify(state.audit[0]), /555|Yıldız/);
    assert.deepEqual(clientLog.map((e) => e.sql).filter((s) => /^(BEGIN|COMMIT)$/.test(s)), ['BEGIN', 'COMMIT']);
    // yazdıktan sonra GET aynı değeri döner
    const read = await call('GET', '/app/emergency', { user: users.managerA });
    assert.equal(read.body.sites[0].elevator_firm_phone, '0212 555 12 34');
  });

  it('ikisi de boşsa kayıt silinir ("tanımlı değil"); denetim kaydı cleared', async () => {
    const res = await call('PUT', PUT(), { user: users.managerA, body: { elevator_firm_name: '', elevator_firm_phone: '' } });
    assert.equal(res.status, 200);
    assert.deepEqual(res.body, { site_code: SITE_A, elevator_firm_name: null, elevator_firm_phone: null });
    assert.deepEqual(state.writes, [{ op: 'delete', site: SITE_A }]);
    assert.deepEqual(state.audit[0].details, { elevator_firm: 'cleared' });
    const read = await call('GET', '/app/emergency', { user: users.managerA });
    assert.equal(read.body.sites[0].elevator_firm_name, null);
  });

  it('süper kullanıcı her siteye yazabilir', async () => {
    const res = await call('PUT', PUT(SITE_B), { user: users.superUser, body: GOOD });
    assert.equal(res.status, 200);
    assert.equal(state.writes[0].site, SITE_B);
  });

  it('sakin, kurul ve görevli yazamaz: 403 FORBIDDEN_ROLE ve işlem açılmaz', async () => {
    for (const [user, site] of [[users.residentB, SITE_B], [users.board, SITE_A], [users.staff, SITE_A]]) {
      const res = await call('PUT', PUT(site), { user, body: GOOD });
      assert.equal(res.status, 403, user.full_name);
      assert.equal(res.body.code, 'FORBIDDEN_ROLE', user.full_name);
    }
    assert.equal(connects, 0);
    assert.equal(state.writes.length, 0);
  });

  it('başka sitenin yöneticisi yazamaz: 403 FORBIDDEN_SITE ve hiçbir şey değişmez', async () => {
    const res = await call('PUT', PUT(SITE_B), { user: users.managerA, body: GOOD });
    assert.equal(res.status, 403);
    assert.equal(res.body.code, 'FORBIDDEN_SITE');
    assert.equal(connects, 0);
    assert.deepEqual(state.emergency, { [SITE_A]: { name: 'Yıldız Asansör', phone: '+905321234567' } });
  });

  it('yetki gövdeden ÖNCE denetlenir: yetkisiz kullanıcıya gövde hatası değil 403 döner', async () => {
    const res = await call('PUT', PUT(SITE_A), { user: users.residentB, body: { elevator_firm_phone: 'harf' } });
    assert.equal(res.status, 403);
  });

  it('geçersiz gövde 400: harfli telefon, telefonsuz firma, boş gövde, çok uzun ad; hiçbir şey yazılmaz', async () => {
    const cases = [
      [{ elevator_firm_name: 'Yıldız', elevator_firm_phone: 'çağır beni' }, 'INVALID_FIELD'],
      [{ elevator_firm_name: 'Yıldız' }, 'INVALID_FIELD'],
      [{}, 'INVALID_BODY'],
      [{ elevator_firm_name: 'x'.repeat(FIRM_NAME_MAX + 1), elevator_firm_phone: '112' }, 'INVALID_FIELD'],
      [{ elevator_firm_name: ['dizi'], elevator_firm_phone: '112' }, 'INVALID_FIELD'],
    ];
    for (const [body, code] of cases) {
      const res = await call('PUT', PUT(), { user: users.managerA, body });
      assert.equal(res.status, 400, JSON.stringify(body));
      assert.equal(res.body.code, code, JSON.stringify(body));
    }
    assert.equal(state.writes.length, 0);
    assert.equal(connects, 0);
  });

  it('site kodu biçimi ve olmayan site: 400 INVALID_SITE_CODE / 404 SITE_NOT_FOUND', async () => {
    const bad = await call('PUT', '/manager/sites/abc/emergency', { user: users.superUser, body: GOOD });
    assert.equal(bad.status, 400);
    assert.equal(bad.body.code, 'INVALID_SITE_CODE');
    const missing = await call('PUT', '/manager/sites/1999999999/emergency', { user: users.superUser, body: GOOD });
    assert.equal(missing.status, 404);
    assert.equal(missing.body.code, 'SITE_NOT_FOUND');
  });

  it('işlem içi hata geri alınır ve ayrıntı sızmaz (500 genel mesaj + errorId)', async () => {
    pool.connect = async () => ({
      async query(text) {
        const sql = sqlNorm(text);
        clientLog.push({ sql });
        if (sql.startsWith('INSERT INTO site_emergency_info')) throw new Error('gizli ayrıntı: relation "site_emergency_info" does not exist');
        return ok();
      },
      release() {},
    });
    const res = await call('PUT', PUT(), { user: users.managerA, body: GOOD });
    assert.equal(res.status, 500);
    assert.doesNotMatch(JSON.stringify(res.body), /gizli|relation/);
    assert.ok(res.body.errorId);
    assert.ok(clientLog.some((e) => e.sql === 'ROLLBACK'));
    assert.ok(!clientLog.some((e) => e.sql === 'COMMIT'));
  });
});
