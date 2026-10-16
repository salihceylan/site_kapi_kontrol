// Duyuru ve Bildirim (Faz 3a) yönetici iş akışları (DB'siz, KATI betikli sahte veritabanı): oluştur / zamanla / yayınla / düzenle /
// geri çek / sil, kilit sırası (sites FOR KEY SHARE -> kişi advisory -> satır -> alıcılar -> küresel e-posta), atomik yayın, 40P01-23503 tek
// yeniden deneme, kötüye kullanım sınırları, çift POST koruması, zamanlayıcı yetki denetimi + başarısızlık sayacı, audit gizliliği, site kapsamı.
//
// Sahte veritabanı KATIDIR: tanımlı bir işleyiciyle eşleşmeyen sorgu (altyapı sorguları ve "izin verilen" varsayılan sınır sorguları hariç)
// hata verir; SQL'in ANLAMI gerçek-PG betiğiyle (scripts/qa_platform_pg.mjs, bölüm `announcements`) sınanır.
import { describe, it, beforeEach, afterEach, mock } from 'node:test';
import assert from 'node:assert/strict';
import { pool } from '../src/db.js';
import {
  assertPublishAllowed,
  createAnnouncement,
  deleteAnnouncement,
  getAnnouncementDetail,
  listAnnouncementRecipients,
  listAnnouncements,
  previewAnnouncementAudience,
  publishAnnouncement,
  publishDueAnnouncement,
  recordPublishFailure,
  updateAnnouncement,
  withdrawAnnouncement,
} from '../src/modules/announcement_service.js';
import { istanbulDayRange } from '../src/modules/announcement_common.js';
import { ANNOUNCEMENT_LOCK_CLASS, ANNOUNCEMENT_LOCK_JOBS } from '../src/modules/announcement_lock.js';
import { SYNC_STEPS } from '../src/modules/people_sync_sql.js';
import { resetPeopleSyncThrottle } from '../src/modules/people_sync.js';

process.env.PEOPLE_SYNC_MIN_INTERVAL_MS = '0';
process.env.JWT_SECRET ||= 'unit-test-secret-0123456789abcdef';

const SITE = 1000000001;
const NOW = new Date();
const actor = { id: 20001, user_code: 20001, userCode: 20001, role: 'site_manager', full_name: 'Ayşe Yönetici' };
const SECRET_TITLE = 'GizliBaşlıkQX7';
const SECRET_BODY = 'GizliMetinQX7';

const norm = (text) => String(text).replace(/\s+/g, ' ').trim();
const ok = (rows = [], rowCount = rows.length) => ({ rows, rowCount });

let log;
let handlers;
let txAborted = false;

const INFRA = [/^BEGIN$/, /^COMMIT$/, /^ROLLBACK$/, /^SELECT pg_advisory_xact_lock/, /^SAVEPOINT /, /^RELEASE SAVEPOINT /, /^ROLLBACK TO SAVEPOINT /, /^INSERT INTO audit_log/];

// --- sorgu desenleri -------------------------------------------------------------------------------------
const SITE_LOCK = /^SELECT site_code FROM sites WHERE site_code = \$1 FOR KEY SHARE$/;
const ADVISORY = /^SELECT pg_advisory_xact_lock/;
const PEOPLE_LOCK = /^SELECT pg_advisory_xact_lock\(hashtext\(\$1\)\)$/;
const GLOBAL_LOCK = /^SELECT pg_advisory_xact_lock\(\$1::int, \$2::int\)$/;
const INSERT_ANN = /^INSERT INTO announcements \(/;
const CLAIM = /^UPDATE announcements SET status = 'published', published_at = NOW\(\)/;
const STATE = /^SELECT status FROM announcements WHERE id = \$1 AND site_code = \$2$/;
const FINAL = /^UPDATE announcements SET recipient_count = \$2, published_at = clock_timestamp\(\) WHERE id = \$1$/;
const USAGE = /^SELECT COUNT\(\*\)::INTEGER AS used FROM announcement_recipients r INNER JOIN announcements a ON a\.id = r\.announcement_id WHERE a\.site_code = \$1 AND a\.published_at >=/;
const SNAPSHOT = /^WITH audience AS .* INSERT INTO announcement_recipients/;
const STATUS_COUNTS = /^SELECT email_status, COUNT\(\*\)::INTEGER AS n FROM announcement_recipients WHERE announcement_id = \$1 GROUP BY email_status$/;
const DETAIL = /^SELECT a\.id, a\.title, a\.body, a\.importance, a\.status, a\.target_type, a\.target_block_ids, a\.target_apartment_ids, a\.send_email, .* WHERE a\.id = \$1 AND a\.site_code = \$2 LIMIT 1$/;
const DETAIL_STATS = /^SELECT email_status, COUNT\(\*\)::INTEGER AS n, COUNT\(\*\) FILTER \(WHERE read_at IS NOT NULL\)::INTEGER AS read_n FROM announcement_recipients WHERE announcement_id = \$1 GROUP BY email_status$/;
const LOCK_ROW = /^SELECT id, title, body, importance, status, target_type, target_block_ids, target_apartment_ids, send_email, publish_at FROM announcements WHERE id = \$1 AND site_code = \$2 FOR UPDATE$/;
// kötüye kullanım sınırları ve koruma sorguları
const DAY_COUNTS = /^SELECT COUNT\(\*\)::INTEGER AS total, COUNT\(\*\) FILTER \(WHERE importance = 'urgent' AND send_email\)::INTEGER AS urgent_email FROM announcements WHERE site_code = \$1 AND id <> \$2 AND/;
const HOURLY = /^SELECT COUNT\(\*\)::INTEGER AS n FROM announcements WHERE email_requested_by = \$1 AND email_requested_at > NOW\(\) - INTERVAL '1 hour' AND id <> \$2$/;
const DUPLICATE = /^SELECT 1 FROM announcements WHERE site_code = \$1 AND created_by = \$2 AND status = 'published' AND published_at > NOW\(\) - make_interval\(secs => \$3::DOUBLE PRECISION\) AND title = \$4 AND body = \$5 AND target_type = \$6 AND target_block_ids = \$7::BIGINT\[\] AND target_apartment_ids = \$8::BIGINT\[\] LIMIT 1$/;
const ADDRESS_PRECHECK = /^WITH audience AS .* SELECT COUNT\(DISTINCT h\.email_hash\)::INTEGER AS n FROM hashed h/;
const PUBLISH_PRESELECT = /^SELECT importance, target_type, target_block_ids, target_apartment_ids, send_email FROM announcements WHERE id = \$1 AND site_code = \$2 AND status IN \('draft', 'scheduled'\)$/;
const DUE_ROW = /^SELECT created_by FROM announcements WHERE id = \$1 AND site_code = \$2 AND status = 'scheduled' AND publish_at <= NOW\(\) FOR UPDATE$/;
const CREATOR_AUTH = /^SELECT \(u\.role = 'super_user'\) AS is_super, .* FROM users u WHERE u\.user_code = \$1 AND u\.is_active = TRUE$/;
const REVERT_TO_DRAFT = /^UPDATE announcements SET status = 'draft', publish_at = NULL, publish_attempts = 0, next_attempt_at = NULL, updated_at = NOW\(\) WHERE id = \$1 AND site_code = \$2 AND status = 'scheduled'$/;
const FAILURE_COUNTER = /^UPDATE announcements SET publish_attempts = publish_attempts \+ 1, next_attempt_at = NOW\(\) \+ make_interval\(mins => LEAST\(POWER\(2, publish_attempts\)::INTEGER, 60\)\), updated_at = NOW\(\) WHERE id = \$1 AND site_code = \$2 AND status = 'scheduled' RETURNING publish_attempts$/;
const SYNC_SQLS = SYNC_STEPS.map((step) => norm(step.sql));

// Varsayılan "izin verilir" cevapları (sınırları sınayan testler kendi işleyicisini ÖNCE ekler).
const GUARD_DEFAULTS = [
  [DAY_COUNTS, () => ok([{ total: 0, urgent_email: 0 }])],
  [HOURLY, () => ok([{ n: 0 }])],
  [DUPLICATE, () => ok()],
  [ADDRESS_PRECHECK, () => ok([{ n: 10 }])],
  [CREATOR_AUTH, () => ok([{ is_super: false, is_manager: true, is_member: false }])],
  [PUBLISH_PRESELECT, () => ok()],
];

function install() {
  log = [];
  txAborted = false;
  const run = async (text, params, inTx) => {
    const sql = norm(text);
    log.push({ sql, params: params ?? [], inTx });
    if (txAborted && inTx && sql !== 'ROLLBACK') {
      throw Object.assign(new Error('current transaction is aborted'), { code: '25P02' });
    }
    for (const [pattern, handler] of [...handlers, ...GUARD_DEFAULTS]) {
      if (pattern.test(sql)) {
        return typeof handler === 'function' ? handler(sql, params ?? []) : handler;
      }
    }
    if (/^SELECT pg_try_advisory_xact_lock/.test(sql)) return ok([{ locked: true }]);
    if (INFRA.some((pattern) => pattern.test(sql))) return ok();
    throw new Error(`BEKLENMEYEN SQL (sahte DB katı): ${sql.slice(0, 240)}`);
  };
  pool.query = (text, params) => run(text, params, false);
  pool.connect = async () => ({ query: (text, params) => run(text, params, true), release() {} });
}

const find = (regex) => log.find((q) => regex.test(q.sql));
const findAll = (regex) => log.filter((q) => regex.test(q.sql));
const has = (regex) => log.some((q) => regex.test(q.sql));
const indexOfQuery = (regex) => log.findIndex((q) => regex.test(q.sql));
const auditActions = () => findAll(/^INSERT INTO audit_log/).map((q) => q.params[3]);
const auditRow = (action) => findAll(/^INSERT INTO audit_log/).find((q) => q.params[3] === action);
const auditDetails = (action) => JSON.parse(auditRow(action).params[7]);

const annRow = (overrides = {}) => ({
  id: '41',
  title: 'Başlık',
  body: 'Metin',
  importance: 'normal',
  status: 'draft',
  target_type: 'site',
  target_block_ids: [],
  target_apartment_ids: [],
  send_email: false,
  publish_at: null,
  published_at: null,
  edited_at: null,
  recipient_count: 0,
  created_at: new Date('2026-10-16T08:00:00.000Z'),
  created_by_name: 'Ayşe Yönetici',
  ...overrides,
});

/** Yazma sonrası AnnouncementDetail yüklemesi için varsayılan işleyiciler. */
function detailHandlers(row = annRow(), statRows = []) {
  return [
    [DETAIL, () => ok([row])],
    [DETAIL_STATS, () => ok(statRows)],
  ];
}

const CLAIM_ROW = { importance: 'normal', target_type: 'site', target_block_ids: [], target_apartment_ids: [], send_email: false };

/** Yayın akışının (eşitleme + anlık görüntü) işleyicileri. */
function publishHandlers({ claim = CLAIM_ROW, total = 3, pending = 0, capped = 0, used = 0 } = {}) {
  const sync = SYNC_SQLS.map((sql) => [new RegExp(`^${sql.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}$`), () => ok([], 0)]);
  return [
    [CLAIM, () => ok([claim])],
    ...sync,
    [USAGE, () => ok([{ used }])],
    [SNAPSHOT, () => ok([], total)],
    [STATUS_COUNTS, () => ok([{ email_status: 'pending', n: pending }, { email_status: 'capped', n: capped }].filter((entry) => entry.n > 0))],
    [FINAL, () => ok([], 1)],
  ];
}

beforeEach(() => {
  handlers = [];
  install();
  resetPeopleSyncThrottle();
  mock.method(console, 'error', () => {});
  mock.method(console, 'log', () => {});
});

afterEach(() => {
  delete pool.query;
  delete pool.connect;
  mock.restoreAll();
});

const base = { title: SECRET_TITLE, body: SECRET_BODY, target: { type: 'site' } };

describe('createAnnouncement: taslak ve zamanlama', () => {
  it('taslak: yayın kilidi / eşitleme / kitle / sınır sorguları YOK; sites FOR KEY SHARE -> INSERT -> audit created; tek transaction', async () => {
    handlers.push([SITE_LOCK, () => ok([{ site_code: SITE }])], [INSERT_ANN, () => ok([{ id: '41' }])], ...detailHandlers());
    const result = await createAnnouncement({ siteCode: SITE, body: base, actor, now: NOW });
    assert.equal(result.id, 41);
    assert.equal(result.status, 'draft');
    const sqls = log.map((q) => q.sql);
    assert.equal(sqls[0], 'BEGIN');
    assert.ok(indexOfQuery(SITE_LOCK) < indexOfQuery(INSERT_ANN));
    assert.equal(has(ADVISORY), false, 'taslak kişi kilidi almaz');
    assert.equal(has(CLAIM), false);
    assert.equal(has(SNAPSHOT), false);
    assert.equal(has(DAY_COUNTS) || has(DUPLICATE) || has(HOURLY), false, 'taslak sınır / çift POST sorgusu çalıştırmaz');
    assert.ok(sqls.includes('COMMIT'));
    const insert = find(INSERT_ANN);
    assert.deepEqual(insert.params.slice(0, 9), [SITE, SECRET_TITLE, SECRET_BODY, 'normal', 'draft', 'site', [], [], false]);
    assert.equal(insert.params[9], null, 'publish_at taslakta NULL');
    assert.equal(insert.params[10], 20001, 'created_by = çağıran');
    assert.deepEqual(auditActions(), ['announcement.created']);
    assert.deepEqual(auditDetails('announcement.created'), { status: 'draft', target_type: 'site', importance: 'normal', send_email: false, block_count: 0, apartment_count: 0 });
  });

  it('D1 site kilidi FOR KEY SHARE\'dir (FOR SHARE DEĞİL: yapı düzenlemenin UPDATE sites\'ı ile deadlock döngüsü kurmaz); kaynak kodda başka FOR SHARE yok', async () => {
    handlers.push([SITE_LOCK, () => ok([{ site_code: SITE }])], [INSERT_ANN, () => ok([{ id: '41' }])], ...detailHandlers());
    await createAnnouncement({ siteCode: SITE, body: base, actor, now: NOW });
    assert.match(find(/FROM sites WHERE site_code/).sql, /FOR KEY SHARE$/);
    assert.equal(has(/FOR SHARE\b/), false);
  });

  it('zamanlı: status scheduled + publish_at ISO parametre; sınır denetimi kilit altında; audit created + scheduled; kitle yazılmaz', async () => {
    handlers.push([SITE_LOCK, () => ok([{ site_code: SITE }])], [INSERT_ANN, () => ok([{ id: '42' }])], ...detailHandlers(annRow({ id: '42', status: 'scheduled' })));
    const when = new Date(NOW.getTime() + 3600_000);
    await createAnnouncement({ siteCode: SITE, body: { ...base, publish: 'schedule', publish_at: when.toISOString() }, actor, now: NOW });
    const insert = find(INSERT_ANN);
    assert.equal(insert.params[4], 'scheduled');
    assert.equal(insert.params[9], when.toISOString());
    assert.deepEqual(auditActions(), ['announcement.created', 'announcement.scheduled']);
    assert.deepEqual(auditDetails('announcement.scheduled'), { publish_at: when.toISOString() });
    assert.equal(has(SNAPSHOT), false);
    // zamanlama kişi kilidi altında sınır sayar (yarışsız): kilit -> sayım -> INSERT
    assert.ok(indexOfQuery(PEOPLE_LOCK) < indexOfQuery(DAY_COUNTS));
    assert.ok(indexOfQuery(DAY_COUNTS) < indexOfQuery(INSERT_ANN));
    const day = istanbulDayRange(when);
    assert.deepEqual(find(DAY_COUNTS).params, [SITE, 0, day.start.toISOString(), day.end.toISOString()], 'sayım ZAMANLANAN günün İstanbul aralığında');
    assert.equal(has(HOURLY), false, 'saatlik yönetici sınırı yalnız elle yayında');
  });

  it('geçersiz gövde / zaman hiçbir DB erişimi yapmaz (BEGIN yok)', async () => {
    await assert.rejects(() => createAnnouncement({ siteCode: SITE, body: { ...base, title: '' }, actor, now: NOW }), (e) => e.code === 'INVALID_BODY');
    await assert.rejects(() => createAnnouncement({ siteCode: SITE, body: { ...base, publish: 'schedule', publish_at: new Date(NOW.getTime() + 1000).toISOString() }, actor, now: NOW }), (e) => e.code === 'INVALID_SCHEDULE');
    assert.equal(log.length, 0);
  });

  it('blok / daire hedefi: kimlikler bu siteye ait değilse 400 INVALID_TARGET ve işlem hiç başlamaz', async () => {
    handlers.push([/^SELECT COUNT\(\*\)::INTEGER AS n FROM site_blocks WHERE site_code = \$1 AND id = ANY\(\$2::BIGINT\[\]\)$/, () => ok([{ n: 1 }])]);
    await assert.rejects(
      () => createAnnouncement({ siteCode: SITE, body: { ...base, target: { type: 'blocks', block_ids: [5, 6] } }, actor, now: NOW }),
      (e) => e.code === 'INVALID_TARGET' && e.statusCode === 400,
    );
    assert.deepEqual(find(/FROM site_blocks/).params, [SITE, [5, 6]], 'site kapsamlı sorgu');
    assert.equal(has(/^BEGIN$/), false);
    handlers.unshift([/^SELECT COUNT\(\*\)::INTEGER AS n FROM apartments WHERE site_code = \$1 AND id = ANY\(\$2::BIGINT\[\]\)$/, () => ok([{ n: 0 }])]);
    await assert.rejects(
      () => createAnnouncement({ siteCode: SITE, body: { ...base, target: { type: 'apartments', apartment_ids: [9] } }, actor, now: NOW }),
      (e) => e.code === 'INVALID_TARGET',
    );
  });

  it('site yoksa (silinmişse) 404 SITE_NOT_FOUND ve geri alma', async () => {
    handlers.push([SITE_LOCK, () => ok()]);
    await assert.rejects(() => createAnnouncement({ siteCode: SITE, body: base, actor, now: NOW }), (e) => e.code === 'SITE_NOT_FOUND' && e.statusCode === 404);
    assert.ok(has(/^ROLLBACK$/));
    assert.equal(has(INSERT_ANN), false);
  });
});

describe('createAnnouncement: şimdi yayınla (atomik, kilit sırası)', () => {
  it('KİLİT SIRASI: sites FOR KEY SHARE -> kişi advisory kilidi -> çift POST denetimi -> INSERT -> talep UPDATE -> sınır denetimi -> eşitleme (6 adım) -> kitle -> recipient_count -> audit; tek COMMIT', async () => {
    handlers.push([SITE_LOCK, () => ok([{ site_code: SITE }])], [INSERT_ANN, () => ok([{ id: '43' }])], ...publishHandlers({ total: 3 }), ...detailHandlers(annRow({ id: '43', status: 'published', recipient_count: 3 })));
    const result = await createAnnouncement({ siteCode: SITE, body: { ...base, publish: 'now' }, actor, now: NOW });
    assert.equal(result.status, 'published');
    const order = [SITE_LOCK, PEOPLE_LOCK, DUPLICATE, INSERT_ANN, CLAIM, DAY_COUNTS].map(indexOfQuery);
    assert.ok(order.every((index, i) => index >= 0 && (i === 0 || index > order[i - 1])), `sıra bozuk: ${order}`);
    assert.equal(log[order[1]].params[0], `people_sync:${SITE}`, 'CRM yazma yolu ve eşitleme ile AYNI advisory anahtar');
    const syncIndexes = SYNC_SQLS.map((sql) => log.findIndex((q) => q.sql === sql));
    assert.ok(syncIndexes.every((index, i) => index > order[5] && (i === 0 || index > syncIndexes[i - 1])), `eşitleme adımları sırayla bekleniyordu: ${syncIndexes}`);
    assert.deepEqual(log[syncIndexes[0]].params, [SITE, null], 'eşitleme site kapsamlı');
    assert.ok(indexOfQuery(SNAPSHOT) > syncIndexes[5], 'kitle eşitlemeden SONRA');
    assert.ok(indexOfQuery(FINAL) > indexOfQuery(SNAPSHOT));
    assert.ok(indexOfQuery(/^COMMIT$/) > indexOfQuery(FINAL));
    assert.equal(findAll(/^COMMIT$/).length, 1);
    const claim = find(CLAIM);
    assert.deepEqual(claim.params, [43, SITE, false, 20001], 'talep: kimlik + site_code + zamanlayıcı=false + yayınlayan');
    assert.match(claim.sql, /WHERE id = \$1 AND site_code = \$2 AND status IN \('draft', 'scheduled'\)/);
    assert.match(claim.sql, /published_by = \$4::INTEGER/);
    assert.deepEqual(find(FINAL).params, [43, 3]);
    assert.deepEqual(auditActions(), ['announcement.created', 'announcement.published']);
  });

  it('kitle sorgusu site kapsamlı ve yalnız güncel ilişki + aktif kişi + aktif daire; dahili adres tanımı SQL\'de; e-postasız yayın kilit / kullanım okumaz', async () => {
    handlers.push([SITE_LOCK, () => ok([{ site_code: SITE }])], [INSERT_ANN, () => ok([{ id: '43' }])], ...publishHandlers(), ...detailHandlers(annRow({ status: 'published' })));
    await createAnnouncement({ siteCode: SITE, body: { ...base, publish: 'now', target: { type: 'site' } }, actor, now: NOW });
    const snapshot = find(SNAPSHOT);
    assert.deepEqual(snapshot.params.slice(0, 4), [SITE, 43, false, 'normal']);
    assert.match(snapshot.sql, /r\.is_current = TRUE AND a\.site_code = \$1 AND a\.is_active = TRUE/);
    assert.match(snapshot.sql, /sp\.site_code = \$1 AND sp\.is_active = TRUE/);
    assert.match(snapshot.sql, /LIKE '%@ahbu\.local' THEN NULL/);
    assert.match(snapshot.sql, /COALESCE\(np\.email_announcements, TRUE\) AS email_pref/);
    assert.match(snapshot.sql, /THEN 'skipped_pref'/);
    assert.equal(has(USAGE), false, 'e-posta istenmediyse günlük kullanım okunmaz');
    assert.equal(has(GLOBAL_LOCK), false, 'e-posta istenmediyse küresel e-posta kilidi alınmaz');
    assert.equal(has(HOURLY), false, 'e-postasız yayın saatlik e-posta sınırına takılmaz');
  });

  it('blok hedefi: kimlikler (artan sıralı) dizi parametresiyle, site kapsamlı; ayrıntıda D18 blocks [{id,name}] kimlikle eşleşir', async () => {
    handlers.push(
      [/^SELECT COUNT\(\*\)::INTEGER AS n FROM site_blocks WHERE site_code = \$1 AND id = ANY\(\$2::BIGINT\[\]\)$/, () => ok([{ n: 2 }])],
      [SITE_LOCK, () => ok([{ site_code: SITE }])],
      [INSERT_ANN, () => ok([{ id: '44' }])],
      ...publishHandlers({ claim: { ...CLAIM_ROW, target_type: 'blocks', target_block_ids: ['5', '6'] } }),
      ...detailHandlers(annRow({ id: '44', status: 'published', target_type: 'blocks', target_block_ids: ['5', '6'] })),
      [/^SELECT id, block_name FROM site_blocks WHERE site_code = \$1 AND id = ANY\(\$2::BIGINT\[\]\) ORDER BY sort_order, id$/, () => ok([{ id: '5', block_name: 'A Blok' }, { id: '6', block_name: 'B Blok' }])],
    );
    const result = await createAnnouncement({ siteCode: SITE, body: { ...base, publish: 'now', target: { type: 'blocks', block_ids: [6, 5, 6] } }, actor, now: NOW });
    assert.deepEqual(find(INSERT_ANN).params.slice(5, 8), ['blocks', [5, 6], []], 'kimlikler artan sırada saklanır');
    assert.deepEqual(find(SNAPSHOT).params.slice(0, 2), [SITE, [5, 6]]);
    assert.match(find(SNAPSHOT).sql, /a\.block_id = ANY\(\$2::BIGINT\[\]\)/);
    assert.deepEqual(result.target, {
      type: 'blocks',
      block_ids: [5, 6],
      apartment_ids: [],
      labels: ['A Blok', 'B Blok'],
      blocks: [{ id: 5, name: 'A Blok' }, { id: 6, name: 'B Blok' }],
      apartments: [],
    });
  });

  it('kitle 0 -> 409 NO_RECIPIENTS: ROLLBACK, COMMIT yok, recipient_count / published audit yazılmaz', async () => {
    handlers.push([SITE_LOCK, () => ok([{ site_code: SITE }])], [INSERT_ANN, () => ok([{ id: '45' }])], ...publishHandlers({ total: 0 }));
    await assert.rejects(
      () => createAnnouncement({ siteCode: SITE, body: { ...base, publish: 'now' }, actor, now: NOW }),
      (e) => e.code === 'NO_RECIPIENTS' && e.statusCode === 409,
    );
    assert.ok(has(/^ROLLBACK$/));
    assert.equal(has(/^COMMIT$/), false);
    assert.equal(has(FINAL), false);
    assert.equal(auditActions().includes('announcement.published'), false);
  });

  it('D2 e-posta: erken kilitsiz kapı (> 1000 adres) KİLİT ALMADAN reddeder; BEGIN / advisory / site kilidi hiç çalışmaz', async () => {
    handlers.push([ADDRESS_PRECHECK, () => ok([{ n: 1001 }])]);
    await assert.rejects(
      () => createAnnouncement({ siteCode: SITE, body: { ...base, send_email: true, publish: 'now' }, actor, now: NOW }),
      (e) => e.code === 'ANNOUNCEMENT_EMAIL_LIMIT' && e.statusCode === 400 && /böl/.test(e.message),
    );
    assert.equal(has(/^BEGIN$/), false);
    assert.equal(has(ADVISORY), false);
    assert.equal(has(SITE_LOCK), false);
    assert.equal(log[0].inTx, false, 'erken kapı havuzdan, işlem dışında');
  });

  it('e-posta: ÖNCE küresel iki-int kilit, SONRA günlük kullanım, SONRA kitle; teslim edilecek adres (pending + capped) > 1000 -> 400 ANNOUNCEMENT_EMAIL_LIMIT (geri alınır)', async () => {
    handlers.push(
      [SITE_LOCK, () => ok([{ site_code: SITE }])],
      [INSERT_ANN, () => ok([{ id: '46' }])],
      ...publishHandlers({ claim: { ...CLAIM_ROW, send_email: true }, total: 1500, pending: 1001 }),
    );
    await assert.rejects(
      () => createAnnouncement({ siteCode: SITE, body: { ...base, send_email: true, publish: 'now' }, actor, now: NOW }),
      (e) => e.code === 'ANNOUNCEMENT_EMAIL_LIMIT' && e.statusCode === 400 && /böl/.test(e.message),
    );
    assert.deepEqual(find(GLOBAL_LOCK).params, [ANNOUNCEMENT_LOCK_CLASS, ANNOUNCEMENT_LOCK_JOBS.emailGlobal]);
    assert.ok(indexOfQuery(PEOPLE_LOCK) < indexOfQuery(GLOBAL_LOCK), 'kilit sırası: kişi kilidi -> küresel e-posta kilidi');
    assert.ok(indexOfQuery(GLOBAL_LOCK) < indexOfQuery(USAGE));
    assert.ok(indexOfQuery(USAGE) < indexOfQuery(SNAPSHOT), 'günlük kullanım alıcı satırları eklenmeden ÖNCE okunur');
    assert.ok(has(/^ROLLBACK$/));
    assert.equal(has(/^COMMIT$/), false);
  });

  it('e-posta sınır altında: günlük kota aşılıyorsa fazlası capped olur (yayın engellenmez); allowance = min(1000, günlük - kullanılan) INSERT parametresidir', async () => {
    process.env.ANNOUNCEMENT_EMAIL_MAX_PER_DAY_PER_SITE = '10';
    try {
      handlers.push(
        [SITE_LOCK, () => ok([{ site_code: SITE }])],
        [INSERT_ANN, () => ok([{ id: '47' }])],
        ...publishHandlers({ claim: { ...CLAIM_ROW, importance: 'urgent', send_email: true }, total: 30, pending: 6, capped: 24, used: 4 }),
        ...detailHandlers(annRow({ id: '47', status: 'published', importance: 'urgent', send_email: true })),
      );
      await createAnnouncement({ siteCode: SITE, body: { ...base, importance: 'urgent', send_email: true, publish: 'now' }, actor, now: NOW });
      const snapshot = find(SNAPSHOT);
      assert.equal(snapshot.params.at(-2), 6, '10 - 4 = 6 kalan kota');
      assert.deepEqual(snapshot.params.slice(0, 4), [SITE, 47, true, 'urgent']);
      assert.equal(auditDetails('announcement.published').send_email, true);
      assert.equal(auditDetails('announcement.published').email.capped, 24);
    } finally {
      delete process.env.ANNOUNCEMENT_EMAIL_MAX_PER_DAY_PER_SITE;
    }
  });

  it('audit yayın: yalnız sayılar / alan adları; başlık, metin, e-posta YOK; actor yöneticinin kendisi', async () => {
    handlers.push([SITE_LOCK, () => ok([{ site_code: SITE }])], [INSERT_ANN, () => ok([{ id: '43' }])], ...publishHandlers({ total: 3, pending: 2, claim: { ...CLAIM_ROW, send_email: true } }), ...detailHandlers(annRow({ status: 'published' })));
    await createAnnouncement({ siteCode: SITE, body: { ...base, send_email: true, publish: 'now' }, actor, now: NOW });
    for (const row of findAll(/^INSERT INTO audit_log/)) {
      const dump = row.params[7];
      assert.ok(!dump.includes(SECRET_TITLE) && !dump.includes(SECRET_BODY) && !dump.includes('@'), dump);
      assert.equal(row.params[0], 20001);
      assert.equal(row.params[4], SITE, 'site_code dolu');
      assert.equal(row.params[5], 'announcement', 'target_type');
      assert.equal(row.params[6], '43', 'target_id');
    }
    const published = auditDetails('announcement.published');
    assert.equal(published.recipient_count, 3);
    assert.equal(published.scheduled, false);
    assert.deepEqual(Object.keys(published.email).sort(), ['capped', 'duplicate', 'no_address', 'pending', 'skipped_pref']);
  });
});

describe('D4 / D10: kötüye kullanım sınırları ve çift POST koruması', () => {
  const day = istanbulDayRange(NOW);
  const publishNow = (overrides = {}) => createAnnouncement({ siteCode: SITE, body: { ...base, publish: 'now', ...overrides }, actor, now: NOW });
  const baseHandlers = (extra = []) => [[SITE_LOCK, () => ok([{ site_code: SITE }])], [INSERT_ANN, () => ok([{ id: '43' }])], ...extra, ...publishHandlers({ total: 3 }), ...detailHandlers(annRow({ id: '43', status: 'published' }))];

  it('D10 çift POST: aynı site + yazar + başlık + metin + hedef (artan kimlikler) 60 sn içinde yayınlanmışsa 409 DUPLICATE_ANNOUNCEMENT; INSERT / talep yazılmaz, işlem geri alınır', async () => {
    handlers.push(...baseHandlers([[DUPLICATE, () => ok([{ '?column?': 1 }])], [/^SELECT COUNT\(\*\)::INTEGER AS n FROM apartments WHERE site_code = \$1 AND id = ANY\(\$2::BIGINT\[\]\)$/, () => ok([{ n: 2 }])]]));
    await assert.rejects(() => publishNow({ target: { type: 'apartments', apartment_ids: [9, 7] } }), (e) => e.code === 'DUPLICATE_ANNOUNCEMENT' && e.statusCode === 409 && /az önce/.test(e.message));
    assert.deepEqual(find(DUPLICATE).params, [SITE, 20001, 60, SECRET_TITLE, SECRET_BODY, 'apartments', [], [7, 9]]);
    assert.equal(has(INSERT_ANN), false);
    assert.equal(has(CLAIM), false);
    assert.ok(has(/^ROLLBACK$/));
    assert.ok(indexOfQuery(PEOPLE_LOCK) < indexOfQuery(DUPLICATE), 'denetim kişi kilidi altında (eşzamanlı çift POST yarışsız)');
  });

  it('D10 yalnız publish:"now" kontrol eder (taslak ve zamanlama değil); yazar kimliği yoksa (kullanıcı kodu yok) denetim atlanır', async () => {
    handlers.push([SITE_LOCK, () => ok([{ site_code: SITE }])], [INSERT_ANN, () => ok([{ id: '41' }])], ...detailHandlers());
    await createAnnouncement({ siteCode: SITE, body: base, actor, now: NOW });
    assert.equal(has(DUPLICATE), false);
  });

  it('D4b siteye günlük TOPLAM yayın sınırı (varsayılan 30): sayım >= sınır ise 409 ANNOUNCEMENT_DAILY_LIMIT (Türkçe mesaj); geri çekilenler + o güne zamanlananlar sayılır; claim geri alınır', async () => {
    handlers.push(...baseHandlers([[DAY_COUNTS, () => ok([{ total: 30, urgent_email: 0 }])]]));
    await assert.rejects(() => publishNow(), (e) => e.code === 'ANNOUNCEMENT_DAILY_LIMIT' && e.statusCode === 409 && /günlük 30 duyuru/.test(e.message));
    assert.deepEqual(find(DAY_COUNTS).params, [SITE, 43, day.start.toISOString(), day.end.toISOString()], 'sayım bu duyuruyu hariç tutar ve İstanbul gününde');
    assert.match(find(DAY_COUNTS).sql, /status IN \('published', 'withdrawn'\) AND published_at >= \$3::TIMESTAMPTZ AND published_at < \$4::TIMESTAMPTZ\) OR \(status = 'scheduled' AND publish_at >= \$3::TIMESTAMPTZ AND publish_at < \$4::TIMESTAMPTZ/);
    assert.ok(has(/^ROLLBACK$/));
    assert.equal(has(SNAPSHOT), false);
  });

  it('D4b sınır ortamdan ayarlanır (ANNOUNCEMENT_MAX_PER_DAY_PER_SITE=5): 4 sayım geçer, 5 sayım reddedilir', async () => {
    process.env.ANNOUNCEMENT_MAX_PER_DAY_PER_SITE = '5';
    try {
      handlers.push(...baseHandlers([[DAY_COUNTS, () => ok([{ total: 4, urgent_email: 0 }])]]));
      await publishNow();
      log.length = 0;
      handlers.unshift([DAY_COUNTS, () => ok([{ total: 5, urgent_email: 0 }])]);
      await assert.rejects(() => publishNow(), (e) => e.code === 'ANNOUNCEMENT_DAILY_LIMIT' && /günlük 5 duyuru/.test(e.message));
    } finally {
      delete process.env.ANNOUNCEMENT_MAX_PER_DAY_PER_SITE;
    }
  });

  it('D4b siteye günlük ACİL + e-postalı yayın sınırı (varsayılan 3): yalnız acil + e-postalı yayına uygulanır; acil e-postasız ve normal e-postalı serbest', async () => {
    const counts = [[DAY_COUNTS, () => ok([{ total: 5, urgent_email: 3 }])]];
    handlers.push([CLAIM, () => ok([{ ...CLAIM_ROW, importance: 'urgent', send_email: true }])], ...baseHandlers(counts));
    await assert.rejects(() => publishNow({ importance: 'urgent', send_email: true }), (e) => e.code === 'ANNOUNCEMENT_DAILY_LIMIT' && /acil e-postalı duyuru/.test(e.message));
    for (const overrides of [{ importance: 'urgent', send_email: false }, { importance: 'normal', send_email: true }]) {
      log.length = 0;
      handlers.length = 0;
      handlers.push(...baseHandlers(counts));
      // CLAIM satırı yayını yapan duyurunun gerçek önem / e-posta durumunu verir
      handlers.unshift([CLAIM, () => ok([{ ...CLAIM_ROW, importance: overrides.importance, send_email: overrides.send_email }])]);
      await publishNow(overrides);
      assert.ok(has(/^COMMIT$/), JSON.stringify(overrides));
    }
  });

  it('E6 yönetici başına SAATLİK e-postalı İSTEK sınırı (varsayılan 10): elle e-postalı yayında KÜRESEL e-posta kilidi altında sayılır; e-postasız yayında sorgulanmaz; aşılırsa 409 ANNOUNCEMENT_HOURLY_LIMIT', async () => {
    handlers.push(...baseHandlers([[HOURLY, () => ok([{ n: 10 }])], [CLAIM, () => ok([{ ...CLAIM_ROW, send_email: true }])]]));
    await assert.rejects(() => publishNow({ send_email: true }), (e) => e.code === 'ANNOUNCEMENT_HOURLY_LIMIT' && e.statusCode === 409 && /saat/.test(e.message));
    assert.deepEqual(find(HOURLY).params, [20001, 43]);
    assert.match(find(HOURLY).sql, /email_requested_by = \$1 AND email_requested_at > NOW\(\) - INTERVAL '1 hour' AND id <> \$2/, 'sayaç yönetici + istek zamanı; geri çekilen / zamanlanan istek de sayılır');
    assert.doesNotMatch(find(HOURLY).sql, /status/, 'durumdan bağımsız: yayınla-geri çek döngüsü kotayı serbest bırakmaz');
    assert.deepEqual(find(GLOBAL_LOCK).params, [ANNOUNCEMENT_LOCK_CLASS, ANNOUNCEMENT_LOCK_JOBS.emailGlobal]);
    assert.ok(indexOfQuery(GLOBAL_LOCK) < indexOfQuery(HOURLY), 'sayım küresel e-posta kilidi ALTINDA (çok siteli paralel yayın aşamaz)');
    log.length = 0;
    handlers.length = 0;
    handlers.push(...baseHandlers([[HOURLY, () => ok([{ n: 99 }])]]));
    await publishNow();
    assert.equal(has(HOURLY), false, 'e-postasız yayın saatlik sınıra takılmaz');
    assert.equal(has(GLOBAL_LOCK), false, 'e-postasız yayın küresel kilit almaz');
  });

  it('E6 elle e-postalı yayın isteği SAYACA yazılır: talep UPDATE\'i email_requested_by / email_requested_at\'i yayını yapana işler; zamanlayıcı yayını işlemez', async () => {
    handlers.push(...baseHandlers([[CLAIM, () => ok([{ ...CLAIM_ROW, send_email: true }])]]));
    await publishNow({ send_email: true });
    const claim = find(CLAIM);
    assert.match(claim.sql, /email_requested_by = CASE WHEN NOT \$3::BOOLEAN AND send_email AND \$4::INTEGER IS NOT NULL THEN \$4::INTEGER ELSE email_requested_by END/);
    assert.match(claim.sql, /email_requested_at = CASE WHEN NOT \$3::BOOLEAN AND send_email AND \$4::INTEGER IS NOT NULL THEN NOW\(\) ELSE email_requested_at END/);
    assert.deepEqual(claim.params, [43, SITE, false, 20001]);
    log.length = 0;
    handlers.length = 0;
    handlers.push([SITE_LOCK, () => ok([{ site_code: SITE }])], [DUE_ROW, () => ok([{ created_by: 20001 }])], ...publishHandlers({ claim: { ...CLAIM_ROW, send_email: true }, total: 1, pending: 1 }));
    await publishDueAnnouncement({ id: 41, siteCode: SITE });
    assert.deepEqual(find(CLAIM).params, [41, SITE, true, 20001], 'zamanlayıcı yayını: $3 = true -> sayaç CASE\'leri değiştirmez (yeniden sayılmaz)');
    assert.equal(has(HOURLY), false, 'zamanlayıcının kendi yayını yeniden denetlenmez');
  });

  it('E6 e-postalı ZAMANLAMA da saatlik sınırda sayılır: kişi kilidi -> küresel kilit -> sayım -> INSERT (sayaç sütunları yöneticiyle); aşılırsa 409 ve INSERT yok; e-postasız zamanlama sorgulamaz', async () => {
    const when = new Date(NOW.getTime() + 3600_000);
    const schedule = (extra = {}) => createAnnouncement({ siteCode: SITE, body: { ...base, publish: 'schedule', publish_at: when.toISOString(), ...extra }, actor, now: NOW });
    handlers.push([SITE_LOCK, () => ok([{ site_code: SITE }])], [INSERT_ANN, () => ok([{ id: '42' }])], ...detailHandlers(annRow({ id: '42', status: 'scheduled', send_email: true })));
    await schedule({ send_email: true });
    assert.ok(indexOfQuery(PEOPLE_LOCK) < indexOfQuery(GLOBAL_LOCK) && indexOfQuery(GLOBAL_LOCK) < indexOfQuery(HOURLY) && indexOfQuery(HOURLY) < indexOfQuery(INSERT_ANN), 'kilit sırası: kişi -> küresel -> sayım -> INSERT');
    assert.deepEqual(find(HOURLY).params, [20001, 0]);
    const insert = find(INSERT_ANN);
    assert.match(insert.sql, /email_requested_by, email_requested_at \) VALUES \(.*\$12::INTEGER, CASE WHEN \$12::INTEGER IS NOT NULL THEN NOW\(\) END\)/);
    assert.equal(insert.params[11], 20001, 'zamanlama isteği yöneticiye yazılır');
    log.length = 0;
    handlers.unshift([HOURLY, () => ok([{ n: 10 }])]);
    await assert.rejects(() => schedule({ send_email: true }), (e) => e.code === 'ANNOUNCEMENT_HOURLY_LIMIT');
    assert.equal(has(INSERT_ANN), false);
    assert.ok(has(/^ROLLBACK$/));
    log.length = 0;
    await schedule({ send_email: false });
    assert.equal(has(HOURLY), false, 'e-postasız zamanlama saatlik sınıra takılmaz');
    assert.equal(has(GLOBAL_LOCK), false);
    assert.equal(find(INSERT_ANN).params[11], null, 'e-postasız zamanlama sayaca yazılmaz');
  });

  it('E6 PATCH: taslağı e-postalı zamanlama / yeniden zamanlama / e-postayı açma bir istektir (sınır + sayaç yazımı); yalnız başlık düzenlemesi ve e-postasız zamanlama değildir', async () => {
    const lockRow = (overrides = {}) => [LOCK_ROW, () => ok([{ id: '41', title: 'Eski', body: 'Eski metin', importance: 'normal', status: 'draft', target_type: 'site', target_block_ids: [], target_apartment_ids: [], send_email: true, publish_at: null, ...overrides }])];
    const when = new Date(NOW.getTime() + 7200_000);
    const updateSql = /^UPDATE announcements SET status = \$3, publish_at = \$4, publish_attempts = 0, next_attempt_at = NULL, email_requested_by = \$5, email_requested_at = NOW\(\), updated_at = NOW\(\) WHERE id = \$1 AND site_code = \$2$/;
    handlers.push([SITE_LOCK, () => ok([{ site_code: SITE }])], lockRow(), [updateSql, () => ok([], 1)], ...detailHandlers(annRow({ status: 'scheduled', send_email: true })));
    await updateAnnouncement({ siteCode: SITE, id: '41', body: { publish_at: when.toISOString() }, actor, now: NOW });
    assert.deepEqual(find(updateSql).params, [41, SITE, 'scheduled', when.toISOString(), 20001]);
    assert.ok(indexOfQuery(HOURLY) >= 0 && indexOfQuery(HOURLY) < indexOfQuery(updateSql));
    // sınır dolu: 409, UPDATE yok
    log.length = 0;
    handlers.unshift([HOURLY, () => ok([{ n: 10 }])]);
    await assert.rejects(() => updateAnnouncement({ siteCode: SITE, id: '41', body: { publish_at: when.toISOString() }, actor, now: NOW }), (e) => e.code === 'ANNOUNCEMENT_HOURLY_LIMIT');
    assert.equal(has(/^UPDATE announcements/), false);
    // zaten zamanlanmış e-postalı duyuruda yalnız başlık: yeni istek DEĞİL
    log.length = 0;
    handlers.length = 0;
    handlers.push([SITE_LOCK, () => ok([{ site_code: SITE }])], lockRow({ status: 'scheduled', publish_at: when }), [/^UPDATE announcements SET title = \$3, updated_at = NOW\(\) WHERE id = \$1 AND site_code = \$2$/, () => ok([], 1)], ...detailHandlers(annRow({ status: 'scheduled' })));
    await updateAnnouncement({ siteCode: SITE, id: '41', body: { title: 'Yeni' }, actor, now: NOW });
    assert.equal(has(HOURLY), false);
    assert.equal(has(GLOBAL_LOCK), false);
    // e-postasız taslağın e-postayı açması + zaten zamanlı olması: istek
    log.length = 0;
    handlers.length = 0;
    handlers.push([SITE_LOCK, () => ok([{ site_code: SITE }])], lockRow({ status: 'scheduled', publish_at: when, send_email: false }), [/^UPDATE announcements SET send_email = \$3, email_requested_by = \$4, email_requested_at = NOW\(\), updated_at = NOW\(\) WHERE id = \$1 AND site_code = \$2$/, () => ok([], 1)], ...detailHandlers(annRow({ status: 'scheduled', send_email: true })));
    await updateAnnouncement({ siteCode: SITE, id: '41', body: { send_email: true }, actor, now: NOW });
    assert.ok(has(HOURLY), 'e-postayı açmak da bir istektir');
    assert.deepEqual(find(/^UPDATE announcements SET send_email/).params, [41, SITE, true, 20001]);
  });

  it('assertPublishAllowed (doğrudan): sınırlar, gün aralığı, e-posta isteği koşulları (küresel kilit + sayım)', async () => {
    const calls = [];
    const client = {
      query: async (text, params) => {
        calls.push({ sql: norm(text), params });
        if (/pg_advisory_xact_lock/.test(text)) return ok();
        return /AS total/.test(text) ? ok([{ total: calls.countTotal ?? 0, urgent_email: calls.countUrgent ?? 0 }]) : ok([{ n: calls.recent ?? 0 }]);
      },
    };
    const input = { id: 7, siteCode: SITE, importance: 'normal', sendEmail: false, when: new Date('2026-10-16T21:30:00.000Z'), actorUserCode: 20001, emailRequest: true };
    await assertPublishAllowed(client, input);
    assert.deepEqual(calls[0].params, [SITE, 7, '2026-10-16T21:00:00.000Z', '2026-10-17T21:00:00.000Z'], '23:30Z İstanbul 17 Ekim 00:30: gün 17 Ekim');
    assert.equal(calls.length, 1, 'e-postasız: kilit ve saatlik sorgu yok');
    calls.length = 0;
    await assertPublishAllowed(client, { ...input, sendEmail: true, emailRequest: false });
    assert.equal(calls.length, 1, 'emailRequest=false (örn. önemi değiştirme): saatlik sorgu yok');
    calls.length = 0;
    await assertPublishAllowed(client, { ...input, sendEmail: true, actorUserCode: null });
    assert.equal(calls.length, 1, 'yazar kullanıcı kodu yoksa (sistem) saatlik sorgu yok');
    calls.length = 0;
    await assertPublishAllowed(client, { ...input, sendEmail: true });
    assert.equal(calls.length, 3, 'günlük sayım + küresel kilit + saatlik sayım');
    assert.match(calls[1].sql, /^SELECT pg_advisory_xact_lock\(\$1::int, \$2::int\)$/);
    assert.deepEqual(calls[1].params, [ANNOUNCEMENT_LOCK_CLASS, ANNOUNCEMENT_LOCK_JOBS.emailGlobal]);
    assert.deepEqual(calls[2].params, [20001, 7]);
    calls.countTotal = 29;
    await assertPublishAllowed(client, input);
    calls.countTotal = 30;
    await assert.rejects(() => assertPublishAllowed(client, input), (e) => e.code === 'ANNOUNCEMENT_DAILY_LIMIT');
    calls.countTotal = 0;
    calls.countUrgent = 3;
    await assertPublishAllowed(client, { ...input, importance: 'normal', sendEmail: true });
    await assertPublishAllowed(client, { ...input, importance: 'urgent', sendEmail: false });
    await assert.rejects(() => assertPublishAllowed(client, { ...input, importance: 'urgent', sendEmail: true }), (e) => e.code === 'ANNOUNCEMENT_DAILY_LIMIT');
    calls.countUrgent = 0;
    calls.recent = 9;
    await assertPublishAllowed(client, { ...input, sendEmail: true });
    calls.recent = 10;
    await assert.rejects(() => assertPublishAllowed(client, { ...input, sendEmail: true }), (e) => e.code === 'ANNOUNCEMENT_HOURLY_LIMIT');
  });


  it('D4b zamanlama sınırı: zamanlanan güne düşen duyuru sayısı sınıra ulaştıysa 409 (INSERT yazılmaz); zamanlanan günün İstanbul gece yarısı aralığı kullanılır', async () => {
    const when = new Date(NOW.getTime() + 36 * 3600_000);
    handlers.push([SITE_LOCK, () => ok([{ site_code: SITE }])], [INSERT_ANN, () => ok([{ id: '42' }])], [DAY_COUNTS, () => ok([{ total: 30, urgent_email: 0 }])]);
    await assert.rejects(
      () => createAnnouncement({ siteCode: SITE, body: { ...base, publish: 'schedule', publish_at: when.toISOString() }, actor, now: NOW }),
      (e) => e.code === 'ANNOUNCEMENT_DAILY_LIMIT',
    );
    const range = istanbulDayRange(when);
    assert.deepEqual(find(DAY_COUNTS).params.slice(2), [range.start.toISOString(), range.end.toISOString()]);
    assert.equal(has(INSERT_ANN), false);
  });
});

describe('geçici çakışmada tek yeniden deneme (40P01 / 23503)', () => {
  const failOnce = (code) => {
    let calls = 0;
    return () => {
      calls += 1;
      if (calls === 1) throw Object.assign(new Error('çakışma'), { code });
      return ok([{ id: '50' }]);
    };
  };

  for (const code of ['40P01', '23503']) {
    it(`${code}: işlem baştan TEK sefer denenir ve ikinci denemede başarılı olur (ROLLBACK + ikinci BEGIN)`, async () => {
      handlers.push([SITE_LOCK, () => ok([{ site_code: SITE }])], [INSERT_ANN, failOnce(code)], ...detailHandlers(annRow({ id: '50' })));
      const result = await createAnnouncement({ siteCode: SITE, body: base, actor, now: NOW });
      assert.equal(result.id, 50);
      assert.equal(findAll(/^BEGIN$/).length, 2);
      assert.equal(findAll(/^ROLLBACK$/).length, 1);
      assert.equal(findAll(INSERT_ANN).length, 2);
      assert.equal(findAll(/^COMMIT$/).length, 1);
    });
  }

  it('ikinci denemede de çakışırsa hata yüzeye çıkar (sonsuz döngü yok); diğer hata kodları yeniden DENENMEZ', async () => {
    handlers.push([SITE_LOCK, () => ok([{ site_code: SITE }])], [INSERT_ANN, () => { throw Object.assign(new Error('x'), { code: '40P01' }); }]);
    await assert.rejects(() => createAnnouncement({ siteCode: SITE, body: base, actor, now: NOW }), (e) => e.code === '40P01');
    assert.equal(findAll(/^BEGIN$/).length, 2);
    log.length = 0;
    handlers.unshift([INSERT_ANN, () => { throw Object.assign(new Error('x'), { code: '23505' }); }]);
    await assert.rejects(() => createAnnouncement({ siteCode: SITE, body: base, actor, now: NOW }), (e) => e.code === '23505');
    assert.equal(findAll(/^BEGIN$/).length, 1, '23505 yeniden denenmez');
  });
});

describe('publishAnnouncement / publishDueAnnouncement: yarış ve idempotans', () => {
  it('talep 0 satır dönerse: durum published -> 409 INVALID_STATE; withdrawn -> 409; yok/başka site -> 404; her biri ROLLBACK, kitle yazılmaz', async () => {
    for (const [status, code, statusCode] of [['published', 'INVALID_STATE', 409], ['withdrawn', 'INVALID_STATE', 409], [null, 'ANNOUNCEMENT_NOT_FOUND', 404]]) {
      log.length = 0;
      handlers.length = 0;
      handlers.push([SITE_LOCK, () => ok([{ site_code: SITE }])], [CLAIM, () => ok()], [STATE, () => (status === null ? ok() : ok([{ status }]))]);
      await assert.rejects(() => publishAnnouncement({ siteCode: SITE, id: '41', actor }), (e) => e.code === code && e.statusCode === statusCode, String(status));
      assert.deepEqual(find(STATE).params, [41, SITE], 'durum sorgusu site kapsamlı');
      assert.ok(has(/^ROLLBACK$/));
      assert.equal(has(SNAPSHOT), false);
      assert.equal(has(/^COMMIT$/), false);
    }
  });

  it('geçersiz kimlik -> 404 ve DB erişimi yok', async () => {
    await assert.rejects(() => publishAnnouncement({ siteCode: SITE, id: 'abc', actor }), (e) => e.code === 'ANNOUNCEMENT_NOT_FOUND');
    await assert.rejects(() => withdrawAnnouncement({ siteCode: SITE, id: '0', actor }), (e) => e.code === 'ANNOUNCEMENT_NOT_FOUND');
    await assert.rejects(() => deleteAnnouncement({ siteCode: SITE, id: '1.5', actor }), (e) => e.code === 'ANNOUNCEMENT_NOT_FOUND');
    await assert.rejects(() => updateAnnouncement({ siteCode: SITE, id: 'x', body: { title: 'a' }, actor }), (e) => e.code === 'ANNOUNCEMENT_NOT_FOUND');
    assert.equal(log.length, 0);
  });

  it('publish ucu: kişi kilidi ALINIR (kilit sırası); başarıda AnnouncementDetail döner; e-postasız taslakta erken adres kapısı çalışmaz', async () => {
    handlers.push([SITE_LOCK, () => ok([{ site_code: SITE }])], ...publishHandlers({ total: 2 }), ...detailHandlers(annRow({ status: 'published', recipient_count: 2 })));
    const result = await publishAnnouncement({ siteCode: SITE, id: '41', actor });
    assert.equal(result.status, 'published');
    assert.ok(indexOfQuery(ADVISORY) < indexOfQuery(CLAIM));
    assert.deepEqual(auditActions(), ['announcement.published']);
    assert.equal(has(ADDRESS_PRECHECK), false);
  });

  it('D2 publish ucu e-postalı taslakta: > 1000 adres KİLİT ALMADAN reddedilir (reddedilen yayın site kişi kilidini hiç tutmaz)', async () => {
    handlers.push([PUBLISH_PRESELECT, () => ok([{ ...CLAIM_ROW, send_email: true }])], [ADDRESS_PRECHECK, () => ok([{ n: 1500 }])]);
    await assert.rejects(() => publishAnnouncement({ siteCode: SITE, id: '41', actor }), (e) => e.code === 'ANNOUNCEMENT_EMAIL_LIMIT');
    assert.deepEqual(find(PUBLISH_PRESELECT).params, [41, SITE], 'site kapsamlı');
    assert.equal(has(/^BEGIN$/), false);
    assert.equal(has(ADVISORY), false);
  });

  it('zamanlayıcı yayını: talep scheduled=true (yalnız zamanı gelmiş scheduled), actor Sistem, published_by = OLUŞTURAN, scheduled:true audit, kitle 0 olsa da yayınlanır; yönetici sınırları uygulanmaz', async () => {
    handlers.push([SITE_LOCK, () => ok([{ site_code: SITE }])], [DUE_ROW, () => ok([{ created_by: 20001 }])], ...publishHandlers({ total: 0 }));
    const result = await publishDueAnnouncement({ id: 41, siteCode: SITE });
    assert.deepEqual(result, { published: true, recipientCount: 0, email: result.email });
    const claim = find(CLAIM);
    assert.deepEqual(claim.params, [41, SITE, true, 20001]);
    assert.match(claim.sql, /status = 'scheduled' AND publish_at <= NOW\(\)/);
    assert.match(claim.sql, /publish_at = CASE WHEN \$3::BOOLEAN THEN publish_at ELSE NULL END/);
    const row = auditRow('announcement.published');
    assert.equal(row.params[0], null, 'actor_user_code NULL');
    assert.equal(row.params[1], 'Sistem');
    assert.equal(row.params[2], 'system');
    assert.deepEqual(auditDetails('announcement.published').recipient_count, 0);
    assert.equal(auditDetails('announcement.published').scheduled, true);
    assert.equal(has(DAY_COUNTS) || has(HOURLY) || has(DUPLICATE), false, 'zamanlama anında denetlendi; zamanlayıcı yayını engellenmez');
    assert.ok(has(/^COMMIT$/));
  });

  it('zamanlayıcı: kilit sırası site kilidi -> kişi kilidi -> satır kilidi (FOR UPDATE) -> yetki -> talep', async () => {
    handlers.push([SITE_LOCK, () => ok([{ site_code: SITE }])], [DUE_ROW, () => ok([{ created_by: 20001 }])], ...publishHandlers({ total: 1 }));
    await publishDueAnnouncement({ id: 41, siteCode: SITE });
    const order = [SITE_LOCK, PEOPLE_LOCK, DUE_ROW, CREATOR_AUTH, CLAIM].map(indexOfQuery);
    assert.ok(order.every((index, i) => index >= 0 && (i === 0 || index > order[i - 1])), `sıra bozuk: ${order}`);
  });

  it('zamanlayıcı: başka yoldan yayınlanmış / yeniden zamanlanmış kayıt için { skipped: true } (veri çiftlenmez, hata yok)', async () => {
    handlers.push([SITE_LOCK, () => ok([{ site_code: SITE }])], [DUE_ROW, () => ok()], [STATE, () => ok([{ status: 'published' }])]);
    const result = await publishDueAnnouncement({ id: 41, siteCode: SITE });
    assert.deepEqual(result, { skipped: true, status: 'published' });
    assert.equal(has(SNAPSHOT), false);
    assert.equal(has(FINAL), false);
    assert.equal(has(CLAIM), false);
  });

  it('zamanlayıcı: kayıt hiç yoksa 404 ANNOUNCEMENT_NOT_FOUND (zamanlayıcı bunu başarısızlık sayar)', async () => {
    handlers.push([SITE_LOCK, () => ok([{ site_code: SITE }])], [DUE_ROW, () => ok()], [STATE, () => ok()]);
    await assert.rejects(() => publishDueAnnouncement({ id: 41, siteCode: SITE }), (e) => e.code === 'ANNOUNCEMENT_NOT_FOUND');
  });

  it('zamanlayıcı: e-posta sınırı aşılsa da yayın ENGELLENMEZ (yönetici sınırı uygulanmaz), fazlası capped (allowance parametresi 500)', async () => {
    handlers.push([SITE_LOCK, () => ok([{ site_code: SITE }])], [DUE_ROW, () => ok([{ created_by: 20001 }])], ...publishHandlers({ claim: { ...CLAIM_ROW, send_email: true }, total: 4000, pending: 500, capped: 2500, used: 0 }));
    const result = await publishDueAnnouncement({ id: 41, siteCode: SITE });
    assert.equal(result.published, true);
    assert.equal(find(SNAPSHOT).params.at(-2), 500, 'varsayılan günlük sınır 500');
  });

  it('D12 oluşturanın yetkisi alınmış: YAYINLANMAZ, taslağa döner (publish_at NULL, sayaç sıfır), announcement.publish_skipped audit (Sistem, neden), talep / kitle / e-posta yok, işlem COMMIT', async () => {
    handlers.push(
      [SITE_LOCK, () => ok([{ site_code: SITE }])],
      [DUE_ROW, () => ok([{ created_by: 20001 }])],
      [CREATOR_AUTH, () => ok([{ is_super: false, is_manager: false, is_member: false }])],
      [REVERT_TO_DRAFT, () => ok([], 1)],
    );
    const result = await publishDueAnnouncement({ id: 41, siteCode: SITE });
    assert.deepEqual(result, { skipped: true, status: 'draft', reason: 'creator_unauthorized' });
    assert.deepEqual(find(CREATOR_AUTH).params, [20001, SITE]);
    assert.deepEqual(find(REVERT_TO_DRAFT).params, [41, SITE]);
    assert.equal(has(CLAIM), false);
    assert.equal(has(SNAPSHOT), false);
    assert.deepEqual(auditActions(), ['announcement.publish_skipped']);
    const row = auditRow('announcement.publish_skipped');
    assert.equal(row.params[0], null);
    assert.equal(row.params[1], 'Sistem');
    assert.deepEqual(auditDetails('announcement.publish_skipped'), { reason: 'creator_unauthorized' });
    assert.ok(has(/^COMMIT$/));
  });

  it('D12 oluşturan hesabı silinmiş (created_by NULL): yetki sorgusu bile çalışmaz, doğrudan taslağa döner; hesap pasifse (sorgu satır dönmez) aynı', async () => {
    handlers.push([SITE_LOCK, () => ok([{ site_code: SITE }])], [DUE_ROW, () => ok([{ created_by: null }])], [REVERT_TO_DRAFT, () => ok([], 1)]);
    const deleted = await publishDueAnnouncement({ id: 41, siteCode: SITE });
    assert.equal(deleted.reason, 'creator_unauthorized');
    assert.equal(has(CREATOR_AUTH), false);
    log.length = 0;
    handlers.length = 0;
    handlers.push([SITE_LOCK, () => ok([{ site_code: SITE }])], [DUE_ROW, () => ok([{ created_by: 20001 }])], [CREATOR_AUTH, () => ok()], [REVERT_TO_DRAFT, () => ok([], 1)]);
    const inactive = await publishDueAnnouncement({ id: 41, siteCode: SITE });
    assert.equal(inactive.reason, 'creator_unauthorized');
  });

  it('D12 yetkili sayılanlar: süper kullanıcı, site yöneticisi (site_manager_sites), SITE_OWNER / SITE_ADMIN üyesi', async () => {
    for (const authority of [{ is_super: true, is_manager: false, is_member: false }, { is_super: false, is_manager: true, is_member: false }, { is_super: false, is_manager: false, is_member: true }]) {
      log.length = 0;
      handlers.length = 0;
      handlers.push([SITE_LOCK, () => ok([{ site_code: SITE }])], [DUE_ROW, () => ok([{ created_by: 20001 }])], [CREATOR_AUTH, () => ok([authority])], ...publishHandlers({ total: 1 }));
      const result = await publishDueAnnouncement({ id: 41, siteCode: SITE });
      assert.equal(result.published, true, JSON.stringify(authority));
    }
  });
});

describe('D7: zamanlanmış yayın başarısızlık sayacı (zehirli kayıt)', () => {
  it('her başarısızlık sayacı artırır ve üstel geri çekilme yazar (site kapsamlı, yalnız scheduled); yeni sayıyı döner; 10. dışında audit yazılmaz', async () => {
    handlers.push([FAILURE_COUNTER, () => ok([{ publish_attempts: 3 }])]);
    assert.equal(await recordPublishFailure({ id: 41, siteCode: SITE, code: '23503' }), 3);
    assert.deepEqual(find(FAILURE_COUNTER).params, [41, SITE]);
    assert.equal(has(/^INSERT INTO audit_log/), false);
  });

  it('10. başarısızlıkta announcement.publish_failed audit BİR kez (Sistem; yalnız deneme sayısı + kod, başlık / metin yok); 11. sayıda tekrar yazılmaz', async () => {
    handlers.push([FAILURE_COUNTER, () => ok([{ publish_attempts: 10 }])]);
    assert.equal(await recordPublishFailure({ id: 41, siteCode: SITE, code: 'x'.repeat(100) }), 10);
    assert.deepEqual(auditActions(), ['announcement.publish_failed']);
    const row = auditRow('announcement.publish_failed');
    assert.equal(row.params[1], 'Sistem');
    assert.equal(row.params[0], null);
    assert.deepEqual(auditDetails('announcement.publish_failed'), { attempts: 10, code: 'x'.repeat(40) });
    log.length = 0;
    handlers.unshift([FAILURE_COUNTER, () => ok([{ publish_attempts: 11 }])]);
    await recordPublishFailure({ id: 41, siteCode: SITE, code: 'x' });
    assert.equal(has(/^INSERT INTO audit_log/), false);
  });

  it('kayıt artık zamanlanmış değilse (0 satır) 0 döner; sayaç yazımı hata verirse yutulur (tik düşmez)', async () => {
    handlers.push([FAILURE_COUNTER, () => ok()]);
    assert.equal(await recordPublishFailure({ id: 41, siteCode: SITE, code: 'x' }), 0);
    handlers.unshift([FAILURE_COUNTER, () => { throw new Error('db kesildi'); }]);
    assert.equal(await recordPublishFailure({ id: 41, siteCode: SITE, code: 'x' }), 0);
  });
});

describe('updateAnnouncement: düzenleme kuralları', () => {
  const lockRow = (overrides = {}) => [LOCK_ROW, () => ok([{ id: '41', title: 'Eski', body: 'Eski metin', importance: 'normal', status: 'draft', target_type: 'site', target_block_ids: [], target_apartment_ids: [], send_email: false, publish_at: null, ...overrides }])];

  it('yok / başka sitenin kaydı -> 404 (sorgu site kapsamlı); geri çekilen -> 409', async () => {
    handlers.push([SITE_LOCK, () => ok([{ site_code: SITE }])], [LOCK_ROW, () => ok()]);
    await assert.rejects(() => updateAnnouncement({ siteCode: SITE, id: '41', body: { title: 'Yeni' }, actor }), (e) => e.code === 'ANNOUNCEMENT_NOT_FOUND');
    assert.deepEqual(find(LOCK_ROW).params, [41, SITE]);
    handlers.unshift(lockRow({ status: 'withdrawn' }));
    await assert.rejects(() => updateAnnouncement({ siteCode: SITE, id: '41', body: { title: 'Yeni' }, actor }), (e) => e.code === 'INVALID_STATE' && e.statusCode === 409);
    assert.equal(has(/^UPDATE announcements SET title/), false);
  });

  it('yayınlanmış: yalnız başlık/metin; başka alan 409 INVALID_STATE ve HİÇBİR şey yazılmaz', async () => {
    handlers.push([SITE_LOCK, () => ok([{ site_code: SITE }])], lockRow({ status: 'published' }));
    for (const body of [{ importance: 'urgent' }, { title: 'Yeni', target: { type: 'site' } }, { send_email: true }, { publish_at: null }, { publish: 'draft' }]) {
      await assert.rejects(() => updateAnnouncement({ siteCode: SITE, id: '41', body, actor }), (e) => e.code === 'INVALID_STATE', JSON.stringify(body));
    }
    assert.equal(has(/^UPDATE announcements/), false);
    assert.equal(auditActions().length, 0);
  });

  it('yayınlanmış: başlık/metin değişimi edited_at + edit_count + 1 yazar, audit yalnız alan adları ve sayaç; kitle/e-posta sorgusu YOK', async () => {
    handlers.push(
      [SITE_LOCK, () => ok([{ site_code: SITE }])],
      lockRow({ status: 'published' }),
      [/^UPDATE announcements SET title = \$3, body = \$4, edited_at = NOW\(\), edit_count = edit_count \+ 1, updated_at = NOW\(\) WHERE id = \$1 AND site_code = \$2 AND status = 'published' RETURNING edit_count$/, () => ok([{ edit_count: 2 }])],
      ...detailHandlers(annRow({ status: 'published', edited_at: new Date() })),
    );
    await updateAnnouncement({ siteCode: SITE, id: '41', body: { title: SECRET_TITLE, body: SECRET_BODY }, actor });
    assert.deepEqual(find(/^UPDATE announcements SET title/).params, [41, SITE, SECRET_TITLE, SECRET_BODY]);
    assert.deepEqual(auditDetails('announcement.updated'), { fields: ['title', 'body'], edit_count: 2 });
    assert.equal(has(SNAPSHOT), false);
    assert.equal(has(GLOBAL_LOCK), false);
    assert.equal(has(/announcement_recipients/), true, 'yalnız ayrıntı istatistiği okunur');
    assert.equal(has(/UPDATE announcement_recipients/), false);
    assert.ok(!JSON.stringify(auditRow('announcement.updated').params).includes(SECRET_TITLE));
  });

  it('D17 her düzenleme AYNI kilit sırasını izler: site kilidi -> kişi advisory kilidi -> satır kilidi (PATCH x yayın / zamanlayıcı yarışlarında deadlock yok)', async () => {
    handlers.push([SITE_LOCK, () => ok([{ site_code: SITE }])], lockRow({ status: 'published' }), ...detailHandlers(annRow({ status: 'published' })));
    await updateAnnouncement({ siteCode: SITE, id: '41', body: { title: 'Eski', body: 'Eski metin' }, actor });
    const order = [SITE_LOCK, PEOPLE_LOCK, LOCK_ROW].map(indexOfQuery);
    assert.ok(order.every((index, i) => index >= 0 && (i === 0 || index > order[i - 1])), `sıra bozuk: ${order}`);
  });

  it('yayınlanmış: değişiklik yoksa UPDATE ve audit yazılmaz', async () => {
    handlers.push([SITE_LOCK, () => ok([{ site_code: SITE }])], lockRow({ status: 'published', title: 'Eski', body: 'Eski metin' }), ...detailHandlers(annRow({ status: 'published' })));
    await updateAnnouncement({ siteCode: SITE, id: '41', body: { title: 'Eski', body: 'Eski metin' }, actor });
    assert.equal(has(/^UPDATE announcements/), false);
    assert.equal(auditActions().length, 0);
  });

  it('taslak: yalnız DEĞİŞEN alanlar yazılır; audit alan adları; kitle yazılmaz; durum / zaman değişmediği için sayaç sıfırlanmaz', async () => {
    handlers.push(
      [SITE_LOCK, () => ok([{ site_code: SITE }])],
      lockRow(),
      [/^UPDATE announcements SET title = \$3, importance = \$4, updated_at = NOW\(\) WHERE id = \$1 AND site_code = \$2$/, () => ok([], 1)],
      ...detailHandlers(),
    );
    await updateAnnouncement({ siteCode: SITE, id: '41', body: { title: 'Yeni', body: 'Eski metin', importance: 'urgent' }, actor });
    assert.deepEqual(find(/^UPDATE announcements SET title/).params, [41, SITE, 'Yeni', 'urgent']);
    assert.deepEqual(auditDetails('announcement.updated'), { fields: ['title', 'importance'] });
    assert.equal(has(SNAPSHOT), false);
    assert.doesNotMatch(find(/^UPDATE announcements SET title/).sql, /publish_attempts/);
  });

  it('taslak: hedef değişimi kimlik doğrulanır ve dizi parametreleri (artan sıralı) yazılır; ayrıntıda D18 apartments [{id,label}]', async () => {
    handlers.push(
      [/^SELECT COUNT\(\*\)::INTEGER AS n FROM apartments WHERE site_code = \$1 AND id = ANY\(\$2::BIGINT\[\]\)$/, () => ok([{ n: 2 }])],
      [SITE_LOCK, () => ok([{ site_code: SITE }])],
      lockRow(),
      [/^UPDATE announcements SET target_type = \$3, target_block_ids = \$4::BIGINT\[\], target_apartment_ids = \$5::BIGINT\[\], updated_at = NOW\(\) WHERE id = \$1 AND site_code = \$2$/, () => ok([], 1)],
      ...detailHandlers(annRow({ target_type: 'apartments', target_apartment_ids: ['7', '8'] })),
      [/^SELECT a\.id, b\.block_name, a\.unit_label FROM apartments a INNER JOIN site_blocks b/, () => ok([{ id: '7', block_name: 'A Blok', unit_label: 'Daire 1' }, { id: '8', block_name: 'A Blok', unit_label: 'Daire 2' }])],
    );
    const result = await updateAnnouncement({ siteCode: SITE, id: '41', body: { target: { type: 'apartments', apartment_ids: [8, 7] } }, actor });
    assert.deepEqual(find(/^UPDATE announcements SET target_type/).params, [41, SITE, 'apartments', [], [7, 8]]);
    assert.deepEqual(auditDetails('announcement.updated'), { fields: ['target'] });
    assert.deepEqual(result.target.apartments, [{ id: 7, label: 'A Blok - Daire 1' }, { id: 8, label: 'A Blok - Daire 2' }]);
    assert.deepEqual(result.target.labels, ['A Blok - Daire 1', 'A Blok - Daire 2'], 'eski labels alanı aynı sırayla kalır');
    assert.deepEqual(result.target.blocks, []);
  });

  it('publish_at:null zamanlanmışı taslağa döndürür (status draft, publish_at NULL, sayaç + geri çekilme sıfırlanır) ve audit alan adı publish_at', async () => {
    const when = new Date(NOW.getTime() + 7200_000);
    handlers.push(
      [SITE_LOCK, () => ok([{ site_code: SITE }])],
      lockRow({ status: 'scheduled', publish_at: when }),
      [/^UPDATE announcements SET status = \$3, publish_at = \$4, publish_attempts = 0, next_attempt_at = NULL, updated_at = NOW\(\) WHERE id = \$1 AND site_code = \$2$/, () => ok([], 1)],
      ...detailHandlers(),
    );
    await updateAnnouncement({ siteCode: SITE, id: '41', body: { publish_at: null }, actor, now: NOW });
    assert.deepEqual(find(/^UPDATE announcements SET status/).params, [41, SITE, 'draft', null]);
    assert.deepEqual(auditDetails('announcement.updated'), { fields: ['publish_at'] });
    assert.equal(auditActions().includes('announcement.scheduled'), false);
  });

  it('taslağa publish_at verilirse scheduled olur (audit updated + scheduled; sınır denetimi kilit altında); zaman yokken publish:schedule -> 400 INVALID_SCHEDULE', async () => {
    const when = new Date(NOW.getTime() + 7200_000);
    handlers.push(
      [SITE_LOCK, () => ok([{ site_code: SITE }])],
      lockRow(),
      [/^UPDATE announcements SET status = \$3, publish_at = \$4, publish_attempts = 0, next_attempt_at = NULL, updated_at = NOW\(\) WHERE id = \$1 AND site_code = \$2$/, () => ok([], 1)],
      ...detailHandlers(annRow({ status: 'scheduled' })),
    );
    await updateAnnouncement({ siteCode: SITE, id: '41', body: { publish_at: when.toISOString() }, actor, now: NOW });
    assert.deepEqual(find(/^UPDATE announcements SET status/).params, [41, SITE, 'scheduled', when.toISOString()]);
    assert.deepEqual(auditActions(), ['announcement.updated', 'announcement.scheduled']);
    assert.ok(indexOfQuery(DAY_COUNTS) >= 0 && indexOfQuery(DAY_COUNTS) < indexOfQuery(/^UPDATE announcements SET status/), 'zamanlama sınırı UPDATE\'ten önce');
    assert.equal(find(DAY_COUNTS).params[1], 41, 'sayım bu duyuruyu hariç tutar');
    log.length = 0;
    await assert.rejects(() => updateAnnouncement({ siteCode: SITE, id: '41', body: { publish: 'schedule' }, actor, now: NOW }), (e) => e.code === 'INVALID_SCHEDULE');
  });

  it('zamanlanmış duyurunun günü sınırı dolu güne taşınırsa 409 ANNOUNCEMENT_DAILY_LIMIT ve hiçbir şey yazılmaz', async () => {
    const when = new Date(NOW.getTime() + 7200_000);
    handlers.push([SITE_LOCK, () => ok([{ site_code: SITE }])], lockLockedRow(), [DAY_COUNTS, () => ok([{ total: 30, urgent_email: 0 }])]);
    function lockLockedRow() {
      return lockRow({ status: 'scheduled', publish_at: new Date(NOW.getTime() + 3600_000) });
    }
    await assert.rejects(() => updateAnnouncement({ siteCode: SITE, id: '41', body: { publish_at: when.toISOString() }, actor, now: NOW }), (e) => e.code === 'ANNOUNCEMENT_DAILY_LIMIT');
    assert.equal(has(/^UPDATE announcements/), false);
    assert.ok(has(/^ROLLBACK$/));
  });

  it("publish:'now' düzenlemeyle birlikte AYNI işlemde yayınlar: kişi kilidi satır kilidinden ÖNCE; eski zamanlama temizlenir; sayaç sıfırlama yazılmaz", async () => {
    handlers.push(
      [SITE_LOCK, () => ok([{ site_code: SITE }])],
      lockRow({ status: 'scheduled', publish_at: new Date(NOW.getTime() + 3600_000) }),
      [/^UPDATE announcements SET title = \$3, updated_at = NOW\(\) WHERE id = \$1 AND site_code = \$2$/, () => ok([], 1)],
      ...publishHandlers({ total: 2 }),
      ...detailHandlers(annRow({ status: 'published', recipient_count: 2 })),
    );
    await updateAnnouncement({ siteCode: SITE, id: '41', body: { title: 'Yeni', publish: 'now' }, actor, now: NOW });
    assert.ok(indexOfQuery(SITE_LOCK) < indexOfQuery(ADVISORY));
    assert.ok(indexOfQuery(ADVISORY) < indexOfQuery(LOCK_ROW), 'kilit sırası: kişi advisory -> duyuru satırı');
    assert.ok(indexOfQuery(LOCK_ROW) < indexOfQuery(CLAIM));
    assert.deepEqual(find(CLAIM).params, [41, SITE, false, 20001]);
    assert.equal(has(/^UPDATE announcements SET status = \$3/), false, "now durumunda ayrı status UPDATE'i yok (talep yazar)");
    assert.equal(findAll(/^COMMIT$/).length, 1);
  });
});

describe('withdraw / delete', () => {
  it('geri çek: talep UPDATE (yalnız published, site kapsamlı) -> HİÇ talep edilmemiş bekleyen e-postalar iptal (none, adres + özet NULL) -> yoldakiler sayılır -> audit sayılar', async () => {
    handlers.push(
      [SITE_LOCK, () => ok([{ site_code: SITE }])],
      [/^UPDATE announcements SET status = 'withdrawn', withdrawn_at = NOW\(\), updated_at = NOW\(\) WHERE id = \$1 AND site_code = \$2 AND status = 'published' RETURNING recipient_count$/, () => ok([{ recipient_count: 9 }])],
      [/^UPDATE announcement_recipients SET email_status = 'none', email = NULL, email_hash = NULL, email_next_at = NULL WHERE announcement_id = \$1 AND email_status = 'pending' AND email_claimed_at IS NULL$/, () => ok([], 4)],
      [/^SELECT COUNT\(\*\)::INTEGER AS n FROM announcement_recipients WHERE announcement_id = \$1 AND email_status = 'pending'$/, () => ok([{ n: 2 }])],
      ...detailHandlers(annRow({ status: 'withdrawn' })),
    );
    const result = await withdrawAnnouncement({ siteCode: SITE, id: '41', actor });
    assert.equal(result.status, 'withdrawn');
    assert.deepEqual(find(/^UPDATE announcements SET status = 'withdrawn'/).params, [41, SITE]);
    assert.deepEqual(find(/^UPDATE announcement_recipients SET email_status = 'none'/).params, [41]);
    assert.deepEqual(auditDetails('announcement.withdrawn'), { recipient_count: 9, email_cancelled: 4, email_in_flight: 2 });
    assert.equal(has(ADVISORY), false);
  });

  it('D3 iptal SQL\'i yoldaki (talep edilmiş) satırlara DOKUNMAZ: email_claimed_at IS NULL koşulu zorunlu; talep edilmişler pending kalır', async () => {
    handlers.push(
      [SITE_LOCK, () => ok([{ site_code: SITE }])],
      [/^UPDATE announcements SET status = 'withdrawn'/, () => ok([{ recipient_count: 3 }])],
      [/^UPDATE announcement_recipients SET email_status = 'none'/, () => ok([], 0)],
      [/^SELECT COUNT\(\*\)::INTEGER AS n FROM announcement_recipients/, () => ok([{ n: 3 }])],
      ...detailHandlers(annRow({ status: 'withdrawn' })),
    );
    await withdrawAnnouncement({ siteCode: SITE, id: '41', actor });
    assert.match(find(/^UPDATE announcement_recipients SET email_status = 'none'/).sql, /AND email_claimed_at IS NULL$/);
    assert.deepEqual(auditDetails('announcement.withdrawn'), { recipient_count: 3, email_cancelled: 0, email_in_flight: 3 });
  });

  it('geri çek: yayında değil -> 409; yok -> 404', async () => {
    handlers.push([SITE_LOCK, () => ok([{ site_code: SITE }])], [/^UPDATE announcements SET status = 'withdrawn'/, () => ok()], [STATE, () => ok([{ status: 'draft' }])]);
    await assert.rejects(() => withdrawAnnouncement({ siteCode: SITE, id: '41', actor }), (e) => e.code === 'INVALID_STATE' && e.statusCode === 409);
    handlers.unshift([STATE, () => ok()]);
    await assert.rejects(() => withdrawAnnouncement({ siteCode: SITE, id: '41', actor }), (e) => e.code === 'ANNOUNCEMENT_NOT_FOUND' && e.statusCode === 404);
    assert.equal(has(/UPDATE announcement_recipients/), false);
  });

  it('sil: yalnız draft/scheduled (DELETE ... WHERE status IN ...), { ok: true }, audit yalnız eski durum', async () => {
    handlers.push([SITE_LOCK, () => ok([{ site_code: SITE }])], [/^DELETE FROM announcements WHERE id = \$1 AND site_code = \$2 AND status IN \('draft', 'scheduled'\) RETURNING status$/, () => ok([{ status: 'scheduled' }])]);
    assert.deepEqual(await deleteAnnouncement({ siteCode: SITE, id: '41', actor }), { ok: true });
    assert.deepEqual(find(/^DELETE FROM announcements/).params, [41, SITE]);
    assert.deepEqual(auditDetails('announcement.deleted'), { status: 'scheduled' });
  });

  it('sil: yayınlanmış -> 409 INVALID_STATE; yok -> 404; silme yazılmaz', async () => {
    handlers.push([SITE_LOCK, () => ok([{ site_code: SITE }])], [/^DELETE FROM announcements/, () => ok()], [STATE, () => ok([{ status: 'published' }])]);
    await assert.rejects(() => deleteAnnouncement({ siteCode: SITE, id: '41', actor }), (e) => e.code === 'INVALID_STATE');
    handlers.unshift([STATE, () => ok()]);
    await assert.rejects(() => deleteAnnouncement({ siteCode: SITE, id: '41', actor }), (e) => e.code === 'ANNOUNCEMENT_NOT_FOUND');
    assert.equal(auditActions().length, 0);
  });
});

describe('okuma: liste, ayrıntı, alıcılar, önizleme', () => {
  it('liste: site kapsamlı sorgu; status/arama parametreleri; limit/offset kırpılır; read_count ve created_by_name eşlenir; total ayrı sayılır', async () => {
    handlers.push(
      [/^SELECT COUNT\(\*\)::INTEGER AS total FROM announcements a WHERE a\.site_code = \$1 AND a\.status = \$2 AND \(/, () => ok([{ total: 7 }])],
      [/^SELECT a\.id, a\.title, left\(a\.body, 1200\) AS body_head/, () => ok([{ ...annRow({ status: 'published' }), body_head: 'Merhaba   dünya', body_length: '15', read_count: 3 }])],
    );
    const result = await listAnnouncements(SITE, { status: 'published', q: 'SU', limit: '999', offset: '4' });
    assert.equal(result.total, 7);
    assert.equal(result.items[0].body_preview, 'Merhaba dünya');
    assert.equal(result.items[0].read_count, 3);
    const page = find(/^SELECT a\.id, a\.title, left/);
    assert.equal(page.params[0], SITE);
    assert.equal(page.params[1], 'published');
    assert.equal(page.params[2], '%su%', 'arama katlanır (Türkçe / küçük harf) ve LIKE kaçışlıdır');
    assert.deepEqual(page.params.slice(-2), [100, 4]);
    assert.match(page.sql, /ORDER BY \(a\.status IN \('draft', 'scheduled'\)\) DESC, COALESCE\(a\.published_at, a\.created_at\) DESC, a\.id DESC/);
  });

  it('liste: status=all süzgeç eklemez; geçersiz status -> 400 INVALID_QUERY', async () => {
    handlers.push([/^SELECT COUNT\(\*\)::INTEGER AS total FROM announcements a WHERE a\.site_code = \$1$/, () => ok([{ total: 0 }])], [/^SELECT a\.id, a\.title, left/, () => ok()]);
    assert.deepEqual(await listAnnouncements(SITE, {}), { items: [], total: 0 });
    assert.deepEqual(find(/^SELECT a\.id, a\.title, left/).params, [SITE, 30, 0]);
    await assert.rejects(() => listAnnouncements(SITE, { status: 'zz' }), (e) => e.code === 'INVALID_QUERY');
  });

  it('ayrıntı: site kapsamlı; istatistik (alıcı, okundu, okunmamış, e-posta durumları); hedef etiketi "Tüm site"; D18 blocks / apartments boş listeler', async () => {
    handlers.push(
      ...detailHandlers(annRow({ status: 'published', recipient_count: 4, edit_count: 2 }), [
        { email_status: 'pending', n: 2, read_n: 1 },
        { email_status: 'sent', n: 3, read_n: 2 },
        { email_status: 'no_address', n: 1, read_n: 0 },
        { email_status: 'none', n: 0, read_n: 0 },
      ]),
    );
    const detail = await getAnnouncementDetail(SITE, '41');
    assert.deepEqual(find(DETAIL).params, [41, SITE]);
    assert.deepEqual(detail.stats, {
      recipients: 6,
      read: 3,
      unread: 3,
      email: { requested: 6, sent: 3, failed: 0, no_address: 1, skipped_pref: 0, capped: 0, duplicate: 0, pending: 2 },
    });
    assert.deepEqual(detail.target, { type: 'site', block_ids: [], apartment_ids: [], labels: ['Tüm site'], blocks: [], apartments: [] });
    assert.equal(detail.read_count, 3);
    assert.equal(detail.body, 'Metin');
    assert.equal(detail.edit_count, 2, 'yayından sonra düzenleme sayısı (eklemeli alan)');
  });

  it('D18 daire hedefi: apartments [{ id, label }] kimlikle eşleşir (yalnız bu siteye ait, site kapsamlı sorgu); silinmiş daire sessizce düşer; labels aynı sıra', async () => {
    handlers.push(
      ...detailHandlers(annRow({ status: 'published', target_type: 'apartments', target_apartment_ids: ['9', '7', '500'] })),
      [/^SELECT a\.id, b\.block_name, a\.unit_label FROM apartments a INNER JOIN site_blocks b ON b\.id = a\.block_id WHERE a\.site_code = \$1 AND a\.id = ANY\(\$2::BIGINT\[\]\) ORDER BY b\.sort_order, a\.sort_order, a\.id$/, () => ok([{ id: '7', block_name: 'A Blok', unit_label: 'Daire 1' }, { id: '9', block_name: 'B Blok', unit_label: 'Daire 4' }])],
    );
    const detail = await getAnnouncementDetail(SITE, '41');
    assert.deepEqual(find(/FROM apartments a INNER JOIN site_blocks b/).params, [SITE, [9, 7, 500]]);
    assert.deepEqual(detail.target.apartments, [{ id: 7, label: 'A Blok - Daire 1' }, { id: 9, label: 'B Blok - Daire 4' }]);
    assert.deepEqual(detail.target.labels, ['A Blok - Daire 1', 'B Blok - Daire 4']);
    assert.deepEqual(detail.target.blocks, []);
    assert.deepEqual(detail.target.apartment_ids, [9, 7, 500], 'kayıtlı kimlik listesi olduğu gibi (silinmişler dahil)');
  });

  it('ayrıntı: yok -> 404; geçersiz kimlik -> 404 (DB yok)', async () => {
    handlers.push([DETAIL, () => ok()]);
    await assert.rejects(() => getAnnouncementDetail(SITE, '41'), (e) => e.code === 'ANNOUNCEMENT_NOT_FOUND' && e.statusCode === 404);
    log.length = 0;
    await assert.rejects(() => getAnnouncementDetail(SITE, 'abc'), (e) => e.code === 'ANNOUNCEMENT_NOT_FOUND');
    assert.equal(log.length, 0);
  });

  it('alıcılar: duyuru site kapsamlı doğrulanır (yoksa 404); alıcı sorgusu announcement + site_code ile bağlı; daire etiketleri toplu', async () => {
    handlers.push(
      [/^SELECT 1 FROM announcements WHERE id = \$1 AND site_code = \$2 LIMIT 1$/, () => ok([{ '?column?': 1 }])],
      [/^SELECT COUNT\(\*\)::INTEGER AS total FROM announcement_recipients r INNER JOIN site_people sp/, () => ok([{ total: 2 }])],
      [/^SELECT r\.person_id, COALESCE\(NULLIF\(u\.full_name, ''\), sp\.full_name\) AS full_name/, () => ok([{ person_id: '5', full_name: 'Ali Veli', has_account: true, read_at: new Date('2026-10-16T09:00:00.000Z'), email_status: 'sent' }, { person_id: '6', full_name: null, has_account: false, read_at: null, email_status: 'none' }])],
      [/^SELECT rr\.person_id, ap\.unit_label, sb\.block_name FROM apartment_residencies rr/, () => ok([{ person_id: '5', unit_label: 'Daire 1', block_name: 'A Blok' }])],
    );
    const result = await listAnnouncementRecipients(SITE, '41', { read: 'false', q: 'Ali', limit: '10', offset: '5' });
    assert.deepEqual(find(/^SELECT 1 FROM announcements/).params, [41, SITE]);
    const page = find(/^SELECT r\.person_id, COALESCE/);
    assert.deepEqual(page.params.slice(0, 2), [41, SITE]);
    assert.match(page.sql, /r\.announcement_id = \$1 AND sp\.site_code = \$2 AND r\.read_at IS NULL/);
    assert.deepEqual(page.params.slice(-2), [10, 5]);
    assert.deepEqual(find(/^SELECT rr\.person_id/).params, [[5, 6], SITE]);
    assert.deepEqual(result.items.map((i) => [i.person_id, i.full_name, i.apartments, i.has_account, i.email_status]), [
      [5, 'Ali Veli', ['A Blok - Daire 1'], true, 'sent'],
      [6, 'Silinmiş hesap', [], false, 'none'],
    ]);
    assert.equal(result.total, 2);
    assert.deepEqual(Object.keys(result.items[0]).sort(), ['apartments', 'email_status', 'full_name', 'has_account', 'person_id', 'read_at']);
  });

  it('alıcılar: başka sitenin duyurusu -> 404 ve alıcı sorgusu ÇALIŞMAZ', async () => {
    handlers.push([/^SELECT 1 FROM announcements WHERE id = \$1 AND site_code = \$2 LIMIT 1$/, () => ok()]);
    await assert.rejects(() => listAnnouncementRecipients(SITE, '41', {}), (e) => e.code === 'ANNOUNCEMENT_NOT_FOUND');
    assert.equal(has(/announcement_recipients/), false);
  });

  it('önizleme: hedef ve send_email doğrulanır, bu siteye ait olması denetlenir, kişi eşitlemesi (kısıtlı) çalışır, yazma YOK', async () => {
    handlers.push(
      [/^WITH audience AS .* SELECT COUNT\(\*\)::INTEGER AS people/, () => ok([{ people: 9, with_account: 5, with_email: 7 }])],
      [/^SELECT COUNT\(DISTINCT r\.apartment_id\)::INTEGER AS apartments/, () => ok([{ apartments: 8 }])],
    );
    const result = await previewAnnouncementAudience(SITE, { target: { type: 'site' }, send_email: true });
    assert.deepEqual(result, { people: 9, apartments: 8, with_account: 5, with_email: 7, without_email: 2 });
    assert.deepEqual(find(/^WITH audience AS/).params, [SITE]);
    assert.deepEqual(find(/^SELECT COUNT\(DISTINCT/).params, [SITE]);
    assert.equal(has(/^(INSERT INTO announcement|UPDATE announcement|DELETE FROM announcement)/), false, 'önizleme duyuru verisi yazmaz');
    assert.ok(log.some((q) => q.sql === SYNC_SQLS[0]), 'yeni üyeler görünsün diye kişi eşitlemesi çalışır');
  });

  it('önizleme: geçersiz send_email veya hedef -> 400 ve DB erişimi yok', async () => {
    await assert.rejects(() => previewAnnouncementAudience(SITE, { target: { type: 'site' }, send_email: 'x' }), (e) => e.code === 'INVALID_BODY');
    await assert.rejects(() => previewAnnouncementAudience(SITE, {}), (e) => e.code === 'INVALID_BODY');
    assert.equal(log.length, 0);
  });
});
