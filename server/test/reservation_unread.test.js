// Okunmamış işareti (048; docs/PLATFORM_REZERVASYON.md "Okunmamış işareti") - DB'siz, KATI sahte veritabanı: bayrak eşlemesi (yalnız sakin görünümü), liste
// `unread_count` sorgusu (sahiplik + onaylı site + modül; kapsam / durum / sayfa süzgeci YOK), GET'lerin YAZMAMASI, /seen (koşullu tek UPDATE, sahiplik, idempotans,
// 404), geçiş SQL'leri: yönetim kararı / konsiyerj güncellemesi yalnız resident_updated_at (clock_timestamp), sakinin kendi iptali iki sütun birden (NOW), hesap silme
// (sistem iptali) hiçbirine dokunmaz. Gerçek PostgreSQL doğrulaması: scripts/qa_platform_pg.mjs "reservation" (K bölümü).
import { describe, it, beforeEach, after } from 'node:test';
import assert from 'node:assert/strict';
import { pool } from '../src/db.js';
import { mapConcierge, mapReservation } from '../src/modules/reservation_common.js';
import { cancelMyReservation, getMyReservation, listMyReservations, markMyReservationSeen } from '../src/modules/reservation_resident.js';
import { cancelMyRequest, getMyRequest, listMyRequests, markMyRequestSeen, updateRequest } from '../src/modules/reservation_concierge.js';
import { decideReservation, releaseUserReservations } from '../src/modules/reservation_service.js';

const norm = (text) => String(text).replace(/\s+/g, ' ').trim();
const ok = (rows = []) => ({ rows, rowCount: rows.length });
const SITE = 1000000001;
const USER = { user_code: 20004, userCode: 20004, id: 20004, role: 'apartment_owner', full_name: 'Sakin' };
const MANAGER = { user_code: 20001, userCode: 20001, id: 20001, role: 'site_manager', full_name: 'Yönetici' };
const ACCESS = { kind: 'manager', siteCode: SITE };
const FUTURE = new Date(Date.now() + 5 * 3_600_000);
const FUTURE_END = new Date(FUTURE.getTime() + 3_600_000);

let handlers;
let log;

beforeEach(() => {
  handlers = [];
  log = [];
  const run = async (text, params = []) => {
    const sql = norm(text);
    log.push({ sql, params });
    for (const [pattern, fn] of handlers) {
      if (pattern.test(sql)) return typeof fn === 'function' ? fn(sql, params) : fn;
    }
    if (/^(BEGIN|COMMIT|ROLLBACK)$/.test(sql) || /^(SAVEPOINT|RELEASE SAVEPOINT|ROLLBACK TO SAVEPOINT) /.test(sql) || /^INSERT INTO audit_log/.test(sql)) return ok();
    if (/^SELECT site_code FROM sites WHERE site_code = \$1 FOR KEY SHARE$/.test(sql)) return ok([{ site_code: String(params[0]) }]);
    if (/^SELECT user_code FROM users WHERE user_code = \$1 AND deleted_at IS NULL FOR KEY SHARE$/.test(sql)) return ok([{ user_code: params[0] }]);
    throw new Error(`BEKLENMEYEN SQL (sahte DB katı): ${sql.slice(0, 240)}`);
  };
  pool.query = async (text, params) => run(text, params);
  pool.connect = async () => ({ query: (text, params) => run(text, params), release() {} });
});

after(() => {
  delete pool.query;
  delete pool.connect;
});

const resRow = (id, over = {}) => ({
  id: String(id), site_code: String(SITE), area_id: '5', user_code: 20004, apartment_id: null, starts_at: FUTURE, ends_at: FUTURE_END, slot_count: 1, status: 'onaylandi',
  note: null, decision_note: null, decided_by: null, cancelled_by_kind: null, created_at: new Date('2026-10-18T09:00:00Z'), area_name: 'Havuz', cancel_cutoff_hours: 2,
  site_name: 'Gül Sitesi', block_name: null, unit_label: null, requester_name: 'Sakin', requester_phone: null, decider_name: null, unread: false, ...over,
});
const reqRow = (id, over = {}) => ({
  id: String(id), site_code: String(SITE), user_code: 20004, apartment_id: null, category: 'paket_teslim', note: 'Kapıda', requested_for: null, status: 'yeni', staff_note: null,
  created_at: new Date('2026-10-18T09:00:00Z'), updated_at: new Date('2026-10-18T09:00:00Z'), closed_at: null, site_name: 'Gül Sitesi', block_name: null, unit_label: null,
  requester_name: 'Sakin', requester_phone: null, unread: false, ...over,
});
const firstWords = () => log.map((entry) => entry.sql.split(' ')[0]);

const RES_LIST = /^SELECT r\.id, r\.site_code, .* ORDER BY r\.id DESC LIMIT \$\d+$/;
const RES_COUNT = /^SELECT COUNT\(\*\)::INTEGER AS n FROM reservations r INNER JOIN sites s ON s\.site_code = r\.site_code WHERE /;
const RES_DETAIL = /^SELECT r\.id, r\.site_code, .* WHERE r\.id = \$2 AND r\.user_code = \$1 AND s\.approval_status = 'approved' AND EXISTS .* LIMIT 1$/;
const REQ_LIST = /^SELECT c\.id, c\.site_code, .* ORDER BY c\.id DESC LIMIT \$\d+$/;
const REQ_COUNT = /^SELECT COUNT\(\*\)::INTEGER AS n FROM concierge_requests c INNER JOIN sites s ON s\.site_code = c\.site_code WHERE /;
const REQ_DETAIL = /^SELECT c\.id, c\.site_code, .* WHERE c\.id = \$2 AND c\.user_code = \$1 AND s\.approval_status = 'approved' AND EXISTS .* LIMIT 1$/;
const MODULE_ENABLED = /^SELECT enabled FROM site_modules WHERE site_code = \$1 AND module_code = \$2 LIMIT 1$/;
const SITE_RELATION = /^WITH my_apts AS MATERIALIZED .* \) AS related$/;
const moduleGate = (alias) => `EXISTS (SELECT 1 FROM site_modules smod WHERE smod.site_code = ${alias}.site_code AND smod.module_code = 'reservation' AND smod.enabled = TRUE)`;
const siteGate = (alias) => `EXISTS (SELECT 1 FROM sites sa WHERE sa.site_code = ${alias}.site_code AND sa.approval_status = 'approved')`;

describe('yanıt eşleme: unread yalnız sakin görünümünde', () => {
  it('mapReservation / mapConcierge: resident görünümünde unread boolean (true yalnız satır true ise; eksik / null -> false); yönetim ve kurul görünümünde alan YOK', () => {
    assert.equal(mapReservation(resRow(1, { unread: true }), { view: 'resident' }).unread, true);
    assert.equal(mapReservation(resRow(1, { unread: false }), { view: 'resident' }).unread, false);
    assert.equal(mapReservation(resRow(1, { unread: undefined }), { view: 'resident' }).unread, false);
    for (const view of ['manager', 'board']) assert.ok(!('unread' in mapReservation(resRow(1, { unread: true }), { view })), view);
    assert.equal(mapConcierge(reqRow(1, { unread: true }), { view: 'resident' }).unread, true);
    assert.equal(mapConcierge(reqRow(1, { unread: null }), { view: 'resident' }).unread, false);
    for (const view of ['manager', 'board']) assert.ok(!('unread' in mapConcierge(reqRow(1, { unread: true }), { view })), view);
  });
});

describe('GET /app/reservations ve /app/reservations/:id (yazmaz)', () => {
  it('liste: öğelerde unread, üstte unread_count; sayaç sorgusu yalnız sahiplik + onaylı site + modül koşullarını taşır (kapsam / before_id / limit YOK), parametresi [kullanıcı]; hiç UPDATE yok', async () => {
    handlers.push([RES_LIST, ok([resRow(9, { unread: true }), resRow(8), resRow(7)])], [RES_COUNT, ok([{ n: 3 }])]);
    const result = await listMyReservations(USER, { scope: 'upcoming', before_id: '50', limit: '2' });
    assert.deepEqual(result.items.map((item) => [item.id, item.unread]), [[9, true], [8, false]]);
    assert.equal(result.next_before_id, 8);
    assert.equal(result.unread_count, 3);
    const count = log.find((entry) => RES_COUNT.test(entry.sql));
    assert.deepEqual(count.params, [20004]);
    assert.ok(count.sql.endsWith(`WHERE r.user_code = $1 AND s.approval_status = 'approved' AND ${moduleGate('r')} AND r.resident_updated_at > r.resident_seen_at`), count.sql);
    assert.ok(!/r\.ends_at|r\.id <|LIMIT/.test(count.sql), 'sayaçta kapsam / imleç / sınır yok');
    const list = log.find((entry) => RES_LIST.test(entry.sql));
    assert.ok(list.sql.includes('(r.resident_updated_at > r.resident_seen_at) AS unread'));
    assert.ok(list.params.length === 4 && list.params[3] === 3, 'liste: kullanıcı, şimdi, before_id, limit+1');
    assert.ok(firstWords().every((word) => word === 'SELECT'), 'GET yazmaz');
  });

  it('site_code verilince sayaç da site süzgecini taşır ([kullanıcı, site]); modül KAPALI + siteyle bağ yok -> { items:[], next_before_id:null, unread_count:0 }', async () => {
    handlers.push(
      [MODULE_ENABLED, (sql, params) => ok([{ enabled: Number(params[0]) === SITE }])],
      [SITE_RELATION, ok([{ related: false }])],
      [RES_LIST, ok([resRow(9)])],
      [RES_COUNT, ok([{ n: 1 }])],
    );
    const result = await listMyReservations(USER, { site_code: String(SITE) });
    assert.equal(result.unread_count, 1);
    const count = log.find((entry) => RES_COUNT.test(entry.sql));
    assert.deepEqual(count.params, [20004, SITE]);
    assert.ok(count.sql.includes('AND r.site_code = $2 AND r.resident_updated_at > r.resident_seen_at'), count.sql);
    assert.deepEqual(await listMyReservations(USER, { site_code: '1000000002' }), { items: [], next_before_id: null, unread_count: 0 });
    assert.ok(!log.some((entry) => /^UPDATE/.test(entry.sql)));
  });

  it('ayrıntı: satır okunmamış -> reservation.unread true; yalnız SELECT; yok / başkasının 404 RESERVATION_NOT_FOUND; geçersiz kimlik sorgusuz 404', async () => {
    handlers.push([RES_DETAIL, (sql, params) => ok(Number(params[1]) === 7 ? [resRow(7, { unread: true })] : [])]);
    const detail = await getMyReservation(USER, '7');
    assert.equal(detail.reservation.unread, true);
    assert.deepEqual(log[0].params, [20004, 7]);
    assert.ok(firstWords().every((word) => word === 'SELECT'));
    await assert.rejects(getMyReservation(USER, '8'), (error) => error.statusCode === 404 && error.code === 'RESERVATION_NOT_FOUND');
    log.length = 0;
    await assert.rejects(getMyReservation(USER, 'abc'), { code: 'RESERVATION_NOT_FOUND' });
    assert.equal(log.length, 0);
  });
});

describe('POST /app/reservations/:id/seen', () => {
  const SEEN_UPDATE = /^UPDATE reservations r SET resident_seen_at = clock_timestamp\(\) WHERE /;
  const OWN = /^SELECT 1 FROM reservations r WHERE r\.id = \$2 AND r\.user_code = \$1 AND /;

  it('okunmamışsa TEK koşullu UPDATE (sahip + okunmamış + onaylı site + modül açık, RETURNING) -> { id, unread:false }', async () => {
    handlers.push([SEEN_UPDATE, ok([{ id: '7' }])]);
    assert.deepEqual(await markMyReservationSeen(USER, '7'), { id: 7, unread: false });
    assert.equal(log.length, 1);
    assert.deepEqual(log[0].params, [20004, 7]);
    assert.equal(
      log[0].sql,
      `UPDATE reservations r SET resident_seen_at = clock_timestamp() WHERE r.id = $2 AND r.user_code = $1 AND r.resident_updated_at > r.resident_seen_at AND ${siteGate('r')} AND ${moduleGate('r')} RETURNING r.id`,
    );
  });

  it('zaten okunmuşsa UPDATE boş döner, sahiplik AYNI kapılarla SELECT ile doğrulanır (ikinci UPDATE yok): idempotent 200; sahip değilse / modül kapalıysa 404; geçersiz kimlik sorgusuz 404; silinmiş hesap 401 ACCOUNT_DELETED', async () => {
    handlers.push([SEEN_UPDATE, ok()], [OWN, (sql, params) => ok(Number(params[1]) === 7 ? [{ x: 1 }] : [])]);
    assert.deepEqual(await markMyReservationSeen(USER, '7'), { id: 7, unread: false });
    assert.deepEqual(firstWords(), ['UPDATE', 'SELECT']);
    assert.equal(log[1].sql, `SELECT 1 FROM reservations r WHERE r.id = $2 AND r.user_code = $1 AND ${siteGate('r')} AND ${moduleGate('r')} LIMIT 1`);
    await assert.rejects(markMyReservationSeen(USER, '8'), (error) => error.statusCode === 404 && error.code === 'RESERVATION_NOT_FOUND');
    log.length = 0;
    await assert.rejects(markMyReservationSeen(USER, '0'), { code: 'RESERVATION_NOT_FOUND' });
    await assert.rejects(markMyReservationSeen({ role: 'x' }, '7'), (error) => error.statusCode === 401 && error.code === 'ACCOUNT_DELETED');
    assert.equal(log.length, 0);
  });
});

describe('GET /app/concierge-requests, GET /:id ve POST /:id/seen', () => {
  const SEEN_UPDATE = /^UPDATE concierge_requests c SET resident_seen_at = clock_timestamp\(\) WHERE /;
  const OWN = /^SELECT 1 FROM concierge_requests c WHERE c\.id = \$2 AND c\.user_code = \$1 AND /;

  it('liste: öğelerde unread, üstte unread_count; sayaç sorgusu durum / before_id / limit süzgeci taşımaz; yalnız SELECT', async () => {
    handlers.push([REQ_LIST, ok([reqRow(4, { unread: true }), reqRow(3)])], [REQ_COUNT, ok([{ n: 2 }])]);
    const result = await listMyRequests(USER, { status: 'closed', before_id: '9', limit: '5' });
    assert.deepEqual(result.items.map((item) => [item.id, item.unread]), [[4, true], [3, false]]);
    assert.equal(result.next_before_id, null);
    assert.equal(result.unread_count, 2);
    const count = log.find((entry) => REQ_COUNT.test(entry.sql));
    assert.deepEqual(count.params, [20004]);
    assert.ok(count.sql.endsWith(`WHERE c.user_code = $1 AND s.approval_status = 'approved' AND ${moduleGate('c')} AND c.resident_updated_at > c.resident_seen_at`), count.sql);
    assert.ok(!/c\.status|c\.id <|LIMIT/.test(count.sql));
    assert.ok(log.find((entry) => REQ_LIST.test(entry.sql)).sql.includes('(c.resident_updated_at > c.resident_seen_at) AS unread'));
    assert.ok(firstWords().every((word) => word === 'SELECT'));
  });

  it('modül KAPALI + bağ yok -> unread_count 0 ile boş liste; ayrıntı: sahip 200 (unread, staff_note), başkasının / geçersiz kimlik 404 CONCIERGE_NOT_FOUND; yazmaz', async () => {
    handlers.push(
      [MODULE_ENABLED, ok([{ enabled: false }])],
      [SITE_RELATION, ok([{ related: false }])],
      [REQ_DETAIL, (sql, params) => ok(Number(params[1]) === 4 ? [reqRow(4, { unread: true, status: 'hazirlaniyor', staff_note: 'Hazır' })] : [])],
    );
    assert.deepEqual(await listMyRequests(USER, { site_code: '1000000002' }), { items: [], next_before_id: null, unread_count: 0 });
    const detail = await getMyRequest(USER, '4');
    assert.deepEqual([detail.request.id, detail.request.unread, detail.request.staff_note, detail.request.can_cancel], [4, true, 'Hazır', false]);
    assert.deepEqual(log.find((entry) => REQ_DETAIL.test(entry.sql)).params, [20004, 4]);
    assert.ok(firstWords().every((word) => word === 'SELECT' || word === 'WITH'));
    await assert.rejects(getMyRequest(USER, '5'), (error) => error.statusCode === 404 && error.code === 'CONCIERGE_NOT_FOUND');
    log.length = 0;
    await assert.rejects(getMyRequest(USER, 'abc'), { code: 'CONCIERGE_NOT_FOUND' });
    assert.equal(log.length, 0);
  });

  it('seen: okunmamışsa tek koşullu UPDATE -> { id, unread:false }; okunmuşsa sahiplik SELECT (idempotent); başkasının 404; geçersiz kimlik sorgusuz 404', async () => {
    handlers.push([SEEN_UPDATE, (sql, params) => ok(Number(params[1]) === 4 ? [{ id: '4' }] : [])], [OWN, (sql, params) => ok(Number(params[1]) === 5 ? [{ x: 1 }] : [])]);
    assert.deepEqual(await markMyRequestSeen(USER, '4'), { id: 4, unread: false });
    assert.equal(log.length, 1);
    assert.equal(
      log[0].sql,
      `UPDATE concierge_requests c SET resident_seen_at = clock_timestamp() WHERE c.id = $2 AND c.user_code = $1 AND c.resident_updated_at > c.resident_seen_at AND ${siteGate('c')} AND ${moduleGate('c')} RETURNING c.id`,
    );
    assert.deepEqual(await markMyRequestSeen(USER, '5'), { id: 5, unread: false });
    assert.deepEqual(firstWords(), ['UPDATE', 'UPDATE', 'SELECT']);
    assert.equal(log[2].sql, `SELECT 1 FROM concierge_requests c WHERE c.id = $2 AND c.user_code = $1 AND ${siteGate('c')} AND ${moduleGate('c')} LIMIT 1`);
    await assert.rejects(markMyRequestSeen(USER, '6'), (error) => error.statusCode === 404 && error.code === 'CONCIERGE_NOT_FOUND');
    log.length = 0;
    await assert.rejects(markMyRequestSeen(USER, '-1'), { code: 'CONCIERGE_NOT_FOUND' });
    assert.equal(log.length, 0);
  });
});

describe('geçişler: hangi yazma işaret bırakır', () => {
  const DECIDE_LOCK = /^SELECT status, starts_at, ends_at, user_code FROM reservations WHERE id = \$1 AND site_code = \$2 FOR UPDATE$/;
  const DECIDE_UPDATE = /^UPDATE reservations SET status = \$3, /;
  const MANAGER_LOAD = /^SELECT r\.id, r\.site_code, .* WHERE r\.site_code = \$1 AND r\.id = \$2 LIMIT 1$/;
  const CONCIERGE_LOCK = /^SELECT status, staff_note, user_code FROM concierge_requests WHERE id = \$1 AND site_code = \$2 FOR UPDATE$/;
  const CONCIERGE_MANAGER_LOAD = /^SELECT c\.id, c\.site_code, .* WHERE c\.site_code = \$1 AND c\.id = \$2 LIMIT 1$/;
  const DECISION_TAIL = "cancelled_by_kind = CASE WHEN $3::TEXT = 'iptal' THEN 'management' ELSE NULL END,";

  it('yönetim kararı (approve / reject / cancel): UPDATE yalnız resident_updated_at = clock_timestamp() yazar, resident_seen_at\'e DOKUNMAZ; aynı karar tekrarı (changed:false) hiçbir şey yazmaz; yönetim yanıtında unread yok', async () => {
    let status = 'beklemede';
    handlers.push(
      [DECIDE_LOCK, () => ok([{ status, starts_at: FUTURE, ends_at: FUTURE_END, user_code: 20004 }])],
      [DECIDE_UPDATE, ok()],
      [MANAGER_LOAD, () => ok([resRow(7, { status: 'onaylandi', unread: true })])],
    );
    for (const [action, note, target] of [['approve', 'Uygun', 'onaylandi'], ['reject', 'Dolu', 'reddedildi'], ['cancel', 'Bakım', 'iptal']]) {
      log.length = 0;
      const result = await decideReservation({ siteCode: SITE, rawId: '7', actor: MANAGER, access: ACCESS, body: { action, note } });
      assert.equal(result.changed, true, action);
      assert.ok(!('unread' in result.reservation), 'yönetim görünümünde unread yok');
      const update = log.find((entry) => DECIDE_UPDATE.test(entry.sql));
      assert.ok(update, action);
      assert.ok(update.sql.endsWith("cancelled_by_kind = CASE WHEN $3::TEXT = 'iptal' THEN 'management' ELSE NULL END, resident_updated_at = clock_timestamp() WHERE id = $1 AND site_code = $2"), update.sql);
      assert.ok(!update.sql.includes('resident_seen_at'), action);
      assert.deepEqual(update.params, [7, SITE, target, note, 20001], action);
    }
    status = 'onaylandi';
    log.length = 0;
    const repeat = await decideReservation({ siteCode: SITE, rawId: '7', actor: MANAGER, access: ACCESS, body: { action: 'approve' } });
    assert.equal(repeat.changed, false);
    assert.ok(!log.some((entry) => /^UPDATE/.test(entry.sql)));
  });

  it('RU-1: karar veren kaydın SAHİBİYSE (sakin olan yönetici / görevli) approve / reject / cancel iki sütunu AYNI NOW() ile yazar (clock_timestamp YOK) -> öz-okunmamış yok; sahipsiz (user_code NULL) ya da başkasının kaydı clock_timestamp', async () => {
    let owner = 20001;
    handlers.push(
      [DECIDE_LOCK, () => ok([{ status: 'beklemede', starts_at: FUTURE, ends_at: FUTURE_END, user_code: owner }])],
      [DECIDE_UPDATE, ok()],
      [MANAGER_LOAD, () => ok([resRow(7, { status: 'onaylandi', user_code: owner })])],
    );
    for (const [action, note, target] of [['approve', null, 'onaylandi'], ['reject', 'Kendi kararım', 'reddedildi'], ['cancel', 'Vazgeçtim', 'iptal']]) {
      log.length = 0;
      const result = await decideReservation({ siteCode: SITE, rawId: '7', actor: MANAGER, access: ACCESS, body: note === null ? { action } : { action, note } });
      assert.equal(result.changed, true, action);
      const update = log.find((entry) => DECIDE_UPDATE.test(entry.sql));
      assert.ok(update.sql.endsWith(`${DECISION_TAIL} resident_updated_at = NOW(), resident_seen_at = NOW() WHERE id = $1 AND site_code = $2`), update.sql);
      assert.ok(!update.sql.includes('clock_timestamp'), action);
      assert.deepEqual(update.params, [7, SITE, target, note, 20001], action);
    }
    for (const other of [null, 20004]) {
      owner = other;
      log.length = 0;
      await decideReservation({ siteCode: SITE, rawId: '7', actor: MANAGER, access: ACCESS, body: { action: 'approve' } });
      const update = log.find((entry) => DECIDE_UPDATE.test(entry.sql));
      assert.ok(update.sql.endsWith(`${DECISION_TAIL} resident_updated_at = clock_timestamp() WHERE id = $1 AND site_code = $2`), String(other));
      assert.ok(!update.sql.includes('resident_seen_at'), String(other));
    }
  });

  it('RU-1: konsiyerj talebinin SAHİBİ güncelleyen yönetici / görevliyse (durum, yalnız not, ikisi) iki sütun AYNI NOW() (clock_timestamp YOK); sahipsiz talep clock_timestamp', async () => {
    let owner = 20001;
    handlers.push(
      [CONCIERGE_LOCK, () => ok([{ status: 'yeni', staff_note: null, user_code: owner }])],
      [/^UPDATE concierge_requests SET updated_at = NOW\(\), /, ok()],
      [CONCIERGE_MANAGER_LOAD, () => ok([reqRow(4, { status: 'hazirlaniyor', user_code: owner })])],
    );
    for (const body of [{ status: 'hazirlaniyor' }, { note: 'Kendi notum' }, { status: 'tamamlandi', note: 'Teslim aldım' }]) {
      log.length = 0;
      const result = await updateRequest({ siteCode: SITE, rawId: '4', actor: MANAGER, access: ACCESS, body });
      assert.equal(result.changed, true, JSON.stringify(body));
      const update = log.find((entry) => /^UPDATE concierge_requests SET/.test(entry.sql));
      assert.ok(update.sql.startsWith('UPDATE concierge_requests SET updated_at = NOW(), resident_updated_at = NOW(), resident_seen_at = NOW()'), update.sql);
      assert.ok(!update.sql.includes('clock_timestamp'), JSON.stringify(body));
      assert.ok(update.sql.endsWith('WHERE id = $1 AND site_code = $2'));
    }
    owner = null;
    log.length = 0;
    await updateRequest({ siteCode: SITE, rawId: '4', actor: MANAGER, access: ACCESS, body: { note: 'Sahipsiz' } });
    const update = log.find((entry) => /^UPDATE concierge_requests SET/.test(entry.sql));
    assert.ok(update.sql.startsWith('UPDATE concierge_requests SET updated_at = NOW(), resident_updated_at = clock_timestamp(), staff_note = $3'), update.sql);
    assert.ok(!update.sql.includes('resident_seen_at'));
  });

  it('sakinin kendi iptali: UPDATE iki sütunu birden AYNI değerle (NOW()) yazar -> öz-okunmamış üretmez; yanıt unread false', async () => {
    handlers.push(
      [/^SELECT site_code FROM reservations WHERE id = \$2 AND user_code = \$1$/, ok([{ site_code: String(SITE) }])],
      [/^SELECT r\.status, r\.starts_at, r\.ends_at, a\.cancel_cutoff_hours FROM reservations r INNER JOIN reservation_areas a .* FOR UPDATE OF r$/, ok([{ status: 'onaylandi', starts_at: FUTURE, ends_at: FUTURE_END, cancel_cutoff_hours: 2 }])],
      [/^UPDATE reservations SET status = 'iptal', /, ok()],
      [RES_DETAIL, ok([resRow(7, { status: 'iptal', cancelled_by_kind: 'resident' })])],
    );
    const result = await cancelMyReservation({ actor: USER, rawId: '7' });
    assert.equal(result.reservation.unread, false);
    assert.equal(result.reservation.cancelled_by, 'resident');
    const update = log.find((entry) => /^UPDATE reservations SET status = 'iptal'/.test(entry.sql));
    assert.equal(update.sql, "UPDATE reservations SET status = 'iptal', cancelled_at = NOW(), cancelled_by_kind = 'resident', updated_at = NOW(), resident_updated_at = NOW(), resident_seen_at = NOW() WHERE id = $1");
    assert.deepEqual(update.params, [7]);
  });

  it('konsiyerj yönetim güncellemesi (durum, yalnız not, ikisi): UPDATE resident_updated_at = clock_timestamp() yazar, resident_seen_at\'e dokunmaz; değişiklik yoksa (changed:false) yazmaz', async () => {
    handlers.push(
      [CONCIERGE_LOCK, ok([{ status: 'yeni', staff_note: null, user_code: 20004 }])],
      [/^UPDATE concierge_requests SET updated_at = NOW\(\), resident_updated_at = clock_timestamp\(\)/, ok()],
      [CONCIERGE_MANAGER_LOAD, ok([reqRow(4, { status: 'hazirlaniyor', unread: true })])],
    );
    for (const body of [{ status: 'hazirlaniyor' }, { note: 'Hazır' }, { status: 'tamamlandi', note: 'Teslim edildi' }]) {
      log.length = 0;
      const result = await updateRequest({ siteCode: SITE, rawId: '4', actor: MANAGER, access: ACCESS, body });
      assert.equal(result.changed, true, JSON.stringify(body));
      assert.ok(!('unread' in result.request));
      const update = log.find((entry) => /^UPDATE concierge_requests SET/.test(entry.sql));
      assert.ok(update && update.sql.startsWith('UPDATE concierge_requests SET updated_at = NOW(), resident_updated_at = clock_timestamp()'), JSON.stringify(body));
      assert.ok(!update.sql.includes('resident_seen_at'), JSON.stringify(body));
      assert.ok(update.sql.endsWith('WHERE id = $1 AND site_code = $2'));
    }
    log.length = 0;
    const same = await updateRequest({ siteCode: SITE, rawId: '4', actor: MANAGER, access: ACCESS, body: { status: 'yeni' } });
    assert.equal(same.changed, false);
    assert.ok(!log.some((entry) => /^UPDATE/.test(entry.sql)));
  });

  it('sakinin kendi talep iptali: iki sütun birden (NOW()); hesap silme (sistem iptali) hiçbir okunmamış sütununa DOKUNMAZ', async () => {
    handlers.push(
      [/^SELECT site_code FROM concierge_requests WHERE id = \$2 AND user_code = \$1$/, ok([{ site_code: String(SITE) }])],
      [/^SELECT c\.status FROM concierge_requests c WHERE c\.id = \$2 AND c\.user_code = \$1 AND .* FOR UPDATE OF c$/, ok([{ status: 'yeni' }])],
      [/^UPDATE concierge_requests SET status = 'iptal', closed_at = NOW\(\), updated_at = NOW\(\), resident_updated_at = NOW\(\), resident_seen_at = NOW\(\) WHERE id = \$1$/, ok()],
      [REQ_DETAIL, ok([reqRow(4, { status: 'iptal', closed_at: new Date() })])],
      [/^SELECT to_regclass\('public\.reservations'\) IS NOT NULL AS present$/, ok([{ present: true }])],
      [/^UPDATE reservations SET status = 'iptal', cancelled_at = NOW\(\), cancelled_by_kind = 'system'/, { rows: [], rowCount: 2 }],
      [/^UPDATE concierge_requests SET status = 'iptal', closed_at = NOW\(\), updated_at = NOW\(\) WHERE id IN/, { rows: [], rowCount: 1 }],
    );
    const result = await cancelMyRequest({ actor: USER, rawId: '4' });
    assert.equal(result.request.unread, false);
    assert.equal(result.request.status, 'iptal');
    assert.ok(log.some((entry) => /^UPDATE concierge_requests SET status = 'iptal', closed_at = NOW\(\), updated_at = NOW\(\), resident_updated_at = NOW\(\), resident_seen_at = NOW\(\) WHERE id = \$1$/.test(entry.sql)));
    log.length = 0;
    const released = await releaseUserReservations({ query: (text, params) => pool.query(text, params) }, 20004);
    assert.deepEqual(released, { reservations: 2, requests: 1 });
    const systemUpdates = log.filter((entry) => /^UPDATE/.test(entry.sql));
    assert.equal(systemUpdates.length, 2);
    assert.ok(systemUpdates.every((entry) => !/resident_(updated|seen)_at/.test(entry.sql)), 'sistem iptali işaret bırakmaz');
  });
});
