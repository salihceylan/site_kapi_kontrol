// Duyuru ve Bildirim (Faz 3a) yönetici iş akışları (DB'siz, KATI betikli sahte veritabanı): oluştur / zamanla / yayınla / düzenle /
// geri çek / sil, kilit sırası, atomik yayın, 40P01-23503 tek yeniden deneme, audit gizliliği, yetkisiz site kapsamı.
//
// Sahte veritabanı KATIDIR: tanımlı bir işleyiciyle eşleşmeyen sorgu (altyapı sorguları hariç) hata verir; SQL'in ANLAMI gerçek-PG betiğiyle
// (scripts/qa_platform_pg.mjs, bölüm `announcements`) sınanır.
import { describe, it, beforeEach, afterEach, mock } from 'node:test';
import assert from 'node:assert/strict';
import { pool } from '../src/db.js';
import {
  createAnnouncement,
  deleteAnnouncement,
  getAnnouncementDetail,
  listAnnouncementRecipients,
  listAnnouncements,
  previewAnnouncementAudience,
  publishAnnouncement,
  publishDueAnnouncement,
  updateAnnouncement,
  withdrawAnnouncement,
} from '../src/modules/announcement_service.js';
import { SYNC_STEPS } from '../src/modules/people_sync_sql.js';
import { resetPeopleSyncThrottle } from '../src/modules/people_sync.js';

process.env.PEOPLE_SYNC_MIN_INTERVAL_MS = '0';

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

function install() {
  log = [];
  txAborted = false;
  const run = async (text, params, inTx) => {
    const sql = norm(text);
    log.push({ sql, params: params ?? [], inTx });
    if (txAborted && inTx && sql !== 'ROLLBACK') {
      throw Object.assign(new Error('current transaction is aborted'), { code: '25P02' });
    }
    for (const [pattern, handler] of handlers) {
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

// --- sorgu desenleri -------------------------------------------------------------------------------------
const SITE_SHARE = /^SELECT site_code FROM sites WHERE site_code = \$1 FOR SHARE$/;
const ADVISORY = /^SELECT pg_advisory_xact_lock/;
const INSERT_ANN = /^INSERT INTO announcements \(/;
const CLAIM = /^UPDATE announcements SET status = 'published', published_at = NOW\(\)/;
const STATE = /^SELECT status FROM announcements WHERE id = \$1 AND site_code = \$2$/;
const FINAL = /^UPDATE announcements SET recipient_count = \$2, published_at = clock_timestamp\(\) WHERE id = \$1$/;
const USAGE = /FROM announcement_recipients r INNER JOIN announcements a ON a\.id = r\.announcement_id WHERE a\.site_code = \$1 AND a\.published_at >=/;
const SNAPSHOT = /^WITH audience AS .* INSERT INTO announcement_recipients/;
const DEDUPE = /^UPDATE announcement_recipients r SET email_status = 'duplicate'/;
const PENDING_COUNT = /^SELECT COUNT\(\*\)::INTEGER AS n FROM announcement_recipients WHERE announcement_id = \$1 AND email_status = 'pending'$/;
const CAP = /^UPDATE announcement_recipients r SET email_status = 'capped'/;
const STATUS_COUNTS = /^SELECT email_status, COUNT\(\*\)::INTEGER AS n FROM announcement_recipients WHERE announcement_id = \$1 GROUP BY email_status$/;
const DETAIL = /^SELECT a\.id, a\.title, a\.body, a\.importance, a\.status, a\.target_type, a\.target_block_ids, a\.target_apartment_ids, a\.send_email, .* WHERE a\.id = \$1 AND a\.site_code = \$2 LIMIT 1$/;
const DETAIL_STATS = /^SELECT email_status, COUNT\(\*\)::INTEGER AS n, COUNT\(\*\) FILTER \(WHERE read_at IS NOT NULL\)::INTEGER AS read_n FROM announcement_recipients WHERE announcement_id = \$1 GROUP BY email_status$/;
const LOCK_ROW = /^SELECT id, title, body, importance, status, target_type, target_block_ids, target_apartment_ids, send_email, publish_at FROM announcements WHERE id = \$1 AND site_code = \$2 FOR UPDATE$/;
const SYNC_SQLS = SYNC_STEPS.map((step) => norm(step.sql));

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

/** Yayın akışının (eşitleme + anlık görüntü) işleyicileri. */
function publishHandlers({ claim = { importance: 'normal', target_type: 'site', target_block_ids: [], target_apartment_ids: [], send_email: false }, total = 3, pending = 0, used = 0 } = {}) {
  const sync = SYNC_SQLS.map((sql) => [new RegExp(`^${sql.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}$`), () => ok([], 0)]);
  return [
    [CLAIM, () => ok([claim])],
    ...sync,
    [USAGE, () => ok([{ used }])],
    [SNAPSHOT, () => ok([], total)],
    [DEDUPE, () => ok([], 0)],
    [PENDING_COUNT, () => ok([{ n: pending }])],
    [CAP, () => ok([], 0)],
    [STATUS_COUNTS, () => ok([{ email_status: 'pending', n: pending }])],
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
  it('taslak: yayın kilidi / eşitleme / kitle YOK; sites FOR SHARE -> INSERT -> audit created; tek transaction', async () => {
    handlers.push([SITE_SHARE, () => ok([{ site_code: SITE }])], [INSERT_ANN, () => ok([{ id: '41' }])], ...detailHandlers());
    const result = await createAnnouncement({ siteCode: SITE, body: base, actor, now: NOW });
    assert.equal(result.id, 41);
    assert.equal(result.status, 'draft');
    const sqls = log.map((q) => q.sql);
    assert.equal(sqls[0], 'BEGIN');
    assert.ok(indexOfQuery(SITE_SHARE) < indexOfQuery(INSERT_ANN));
    assert.equal(has(ADVISORY), false, 'taslak kişi kilidi almaz');
    assert.equal(has(CLAIM), false);
    assert.equal(has(SNAPSHOT), false);
    assert.ok(sqls.includes('COMMIT'));
    const insert = find(INSERT_ANN);
    assert.deepEqual(insert.params.slice(0, 9), [SITE, SECRET_TITLE, SECRET_BODY, 'normal', 'draft', 'site', [], [], false]);
    assert.equal(insert.params[9], null, 'publish_at taslakta NULL');
    assert.equal(insert.params[10], 20001, 'created_by = çağıran');
    assert.deepEqual(auditActions(), ['announcement.created']);
    assert.deepEqual(auditDetails('announcement.created'), { status: 'draft', target_type: 'site', importance: 'normal', send_email: false, block_count: 0, apartment_count: 0 });
  });

  it('zamanlı: status scheduled + publish_at ISO parametre; audit created + scheduled; kitle yazılmaz', async () => {
    handlers.push([SITE_SHARE, () => ok([{ site_code: SITE }])], [INSERT_ANN, () => ok([{ id: '42' }])], ...detailHandlers(annRow({ id: '42', status: 'scheduled' })));
    const when = new Date(NOW.getTime() + 3600_000);
    await createAnnouncement({ siteCode: SITE, body: { ...base, publish: 'schedule', publish_at: when.toISOString() }, actor, now: NOW });
    const insert = find(INSERT_ANN);
    assert.equal(insert.params[4], 'scheduled');
    assert.equal(insert.params[9], when.toISOString());
    assert.deepEqual(auditActions(), ['announcement.created', 'announcement.scheduled']);
    assert.deepEqual(auditDetails('announcement.scheduled'), { publish_at: when.toISOString() });
    assert.equal(has(SNAPSHOT), false);
    assert.equal(has(ADVISORY), false);
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
    handlers.push([SITE_SHARE, () => ok()]);
    await assert.rejects(() => createAnnouncement({ siteCode: SITE, body: base, actor, now: NOW }), (e) => e.code === 'SITE_NOT_FOUND' && e.statusCode === 404);
    assert.ok(has(/^ROLLBACK$/));
    assert.equal(has(INSERT_ANN), false);
  });
});

describe('createAnnouncement: şimdi yayınla (atomik, kilit sırası)', () => {
  it('KİLİT SIRASI: sites FOR SHARE -> kişi advisory kilidi -> INSERT -> talep UPDATE -> eşitleme (6 adım) -> kitle -> recipient_count -> audit; tek COMMIT', async () => {
    handlers.push([SITE_SHARE, () => ok([{ site_code: SITE }])], [INSERT_ANN, () => ok([{ id: '43' }])], ...publishHandlers({ total: 3 }), ...detailHandlers(annRow({ id: '43', status: 'published', recipient_count: 3 })));
    const result = await createAnnouncement({ siteCode: SITE, body: { ...base, publish: 'now' }, actor, now: NOW });
    assert.equal(result.status, 'published');
    const order = [SITE_SHARE, ADVISORY, INSERT_ANN, CLAIM].map(indexOfQuery);
    assert.ok(order.every((index, i) => index >= 0 && (i === 0 || index > order[i - 1])), `sıra bozuk: ${order}`);
    assert.equal(log[order[1]].params[0], `people_sync:${SITE}`, 'CRM yazma yolu ve eşitleme ile AYNI advisory anahtar');
    const syncIndexes = SYNC_SQLS.map((sql) => log.findIndex((q) => q.sql === sql));
    assert.ok(syncIndexes.every((index, i) => index > order[3] && (i === 0 || index > syncIndexes[i - 1])), `eşitleme adımları sırayla bekleniyordu: ${syncIndexes}`);
    assert.deepEqual(log[syncIndexes[0]].params, [SITE, null], 'eşitleme site kapsamlı');
    assert.ok(indexOfQuery(SNAPSHOT) > syncIndexes[5], 'kitle eşitlemeden SONRA');
    assert.ok(indexOfQuery(FINAL) > indexOfQuery(SNAPSHOT));
    assert.ok(indexOfQuery(/^COMMIT$/) > indexOfQuery(FINAL));
    assert.equal(findAll(/^COMMIT$/).length, 1);
    const claim = find(CLAIM);
    assert.deepEqual(claim.params, [43, SITE, false], 'talep: kimlik + site_code + zamanlayıcı=false');
    assert.match(claim.sql, /WHERE id = \$1 AND site_code = \$2 AND status IN \('draft', 'scheduled'\)/);
    assert.deepEqual(find(FINAL).params, [43, 3]);
    assert.deepEqual(auditActions(), ['announcement.created', 'announcement.published']);
  });

  it('kitle sorgusu site kapsamlı ve yalnız güncel ilişki + aktif kişi + aktif daire; dahili adres tanımı SQL\'de', async () => {
    handlers.push([SITE_SHARE, () => ok([{ site_code: SITE }])], [INSERT_ANN, () => ok([{ id: '43' }])], ...publishHandlers(), ...detailHandlers(annRow({ status: 'published' })));
    await createAnnouncement({ siteCode: SITE, body: { ...base, publish: 'now', target: { type: 'site' } }, actor, now: NOW });
    const snapshot = find(SNAPSHOT);
    assert.deepEqual(snapshot.params, [SITE, 43, false, 'normal']);
    assert.match(snapshot.sql, /r\.is_current = TRUE AND a\.site_code = \$1 AND a\.is_active = TRUE/);
    assert.match(snapshot.sql, /sp\.site_code = \$1 AND sp\.is_active = TRUE/);
    assert.match(snapshot.sql, /LIKE '%@ahbu\.local' THEN NULL/);
    assert.match(snapshot.sql, /COALESCE\(np\.email_announcements, TRUE\) AS email_pref/);
    assert.match(snapshot.sql, /THEN 'skipped_pref'/);
    assert.equal(has(USAGE), false, 'e-posta istenmediyse günlük kullanım okunmaz');
  });

  it('blok hedefi: kimlikler dizi parametresiyle, site kapsamlı', async () => {
    handlers.push(
      [/^SELECT COUNT\(\*\)::INTEGER AS n FROM site_blocks WHERE site_code = \$1 AND id = ANY\(\$2::BIGINT\[\]\)$/, () => ok([{ n: 2 }])],
      [SITE_SHARE, () => ok([{ site_code: SITE }])],
      [INSERT_ANN, () => ok([{ id: '44' }])],
      ...publishHandlers({ claim: { importance: 'normal', target_type: 'blocks', target_block_ids: ['5', '6'], target_apartment_ids: [], send_email: false } }),
      ...detailHandlers(annRow({ id: '44', status: 'published', target_type: 'blocks', target_block_ids: ['5', '6'] })),
      [/^SELECT block_name FROM site_blocks WHERE site_code = \$1 AND id = ANY\(\$2::BIGINT\[\]\) ORDER BY sort_order, id$/, () => ok([{ block_name: 'A Blok' }, { block_name: 'B Blok' }])],
    );
    const result = await createAnnouncement({ siteCode: SITE, body: { ...base, publish: 'now', target: { type: 'blocks', block_ids: [5, 6, 5] } }, actor, now: NOW });
    assert.deepEqual(find(INSERT_ANN).params.slice(5, 8), ['blocks', [5, 6], []]);
    assert.deepEqual(find(SNAPSHOT).params.slice(0, 2), [SITE, [5, 6]]);
    assert.match(find(SNAPSHOT).sql, /a\.block_id = ANY\(\$2::BIGINT\[\]\)/);
    assert.deepEqual(result.target, { type: 'blocks', block_ids: [5, 6], apartment_ids: [], labels: ['A Blok', 'B Blok'] });
  });

  it('kitle 0 -> 409 NO_RECIPIENTS: ROLLBACK, COMMIT yok, recipient_count / published audit yazılmaz', async () => {
    handlers.push([SITE_SHARE, () => ok([{ site_code: SITE }])], [INSERT_ANN, () => ok([{ id: '45' }])], ...publishHandlers({ total: 0 }));
    await assert.rejects(
      () => createAnnouncement({ siteCode: SITE, body: { ...base, publish: 'now' }, actor, now: NOW }),
      (e) => e.code === 'NO_RECIPIENTS' && e.statusCode === 409,
    );
    assert.ok(has(/^ROLLBACK$/));
    assert.equal(has(/^COMMIT$/), false);
    assert.equal(has(FINAL), false);
    assert.equal(auditActions().includes('announcement.published'), false);
  });

  it('e-posta: günlük kullanım okunur, tekilleştirme + sayım çalışır; teslim edilecek adres > 1000 -> 400 ANNOUNCEMENT_EMAIL_LIMIT (geri alınır)', async () => {
    handlers.push(
      [SITE_SHARE, () => ok([{ site_code: SITE }])],
      [INSERT_ANN, () => ok([{ id: '46' }])],
      ...publishHandlers({ claim: { importance: 'normal', target_type: 'site', target_block_ids: [], target_apartment_ids: [], send_email: true }, total: 1500, pending: 1001 }),
    );
    await assert.rejects(
      () => createAnnouncement({ siteCode: SITE, body: { ...base, send_email: true, publish: 'now' }, actor, now: NOW }),
      (e) => e.code === 'ANNOUNCEMENT_EMAIL_LIMIT' && e.statusCode === 400 && /böl/.test(e.message),
    );
    assert.ok(has(USAGE));
    assert.ok(indexOfQuery(USAGE) < indexOfQuery(SNAPSHOT), 'günlük kullanım alıcı satırları eklenmeden ÖNCE okunur');
    assert.ok(has(DEDUPE));
    assert.equal(has(CAP), false, 'sınır aşımında önce hata; kırpma yapılmaz');
    assert.ok(has(/^ROLLBACK$/));
    assert.equal(has(/^COMMIT$/), false);
  });

  it('e-posta sınır altında: günlük kota aşılıyorsa fazlası capped olur (yayın engellenmez); allowance = min(1000, günlük - kullanılan)', async () => {
    process.env.ANNOUNCEMENT_EMAIL_MAX_PER_DAY_PER_SITE = '10';
    try {
      handlers.push(
        [SITE_SHARE, () => ok([{ site_code: SITE }])],
        [INSERT_ANN, () => ok([{ id: '47' }])],
        ...publishHandlers({ claim: { importance: 'urgent', target_type: 'site', target_block_ids: [], target_apartment_ids: [], send_email: true }, total: 30, pending: 25, used: 4 }),
        ...detailHandlers(annRow({ id: '47', status: 'published', importance: 'urgent', send_email: true })),
      );
      await createAnnouncement({ siteCode: SITE, body: { ...base, importance: 'urgent', send_email: true, publish: 'now' }, actor, now: NOW });
      assert.deepEqual(find(CAP).params, [47, 6], '10 - 4 = 6 kalan kota');
      assert.deepEqual(find(SNAPSHOT).params.slice(-3), [47, true, 'urgent']);
      assert.ok(auditDetails('announcement.published').send_email === true);
    } finally {
      delete process.env.ANNOUNCEMENT_EMAIL_MAX_PER_DAY_PER_SITE;
    }
  });

  it('audit yayın: yalnız sayılar / alan adları; başlık, metin, e-posta YOK; actor yöneticinin kendisi', async () => {
    handlers.push([SITE_SHARE, () => ok([{ site_code: SITE }])], [INSERT_ANN, () => ok([{ id: '43' }])], ...publishHandlers({ total: 3, pending: 2, claim: { importance: 'normal', target_type: 'site', target_block_ids: [], target_apartment_ids: [], send_email: true } }), ...detailHandlers(annRow({ status: 'published' })));
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
      handlers.push([SITE_SHARE, () => ok([{ site_code: SITE }])], [INSERT_ANN, failOnce(code)], ...detailHandlers(annRow({ id: '50' })));
      const result = await createAnnouncement({ siteCode: SITE, body: base, actor, now: NOW });
      assert.equal(result.id, 50);
      assert.equal(findAll(/^BEGIN$/).length, 2);
      assert.equal(findAll(/^ROLLBACK$/).length, 1);
      assert.equal(findAll(INSERT_ANN).length, 2);
      assert.equal(findAll(/^COMMIT$/).length, 1);
    });
  }

  it('ikinci denemede de çakışırsa hata yüzeye çıkar (sonsuz döngü yok); diğer hata kodları yeniden DENENMEZ', async () => {
    handlers.push([SITE_SHARE, () => ok([{ site_code: SITE }])], [INSERT_ANN, () => { throw Object.assign(new Error('x'), { code: '40P01' }); }]);
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
      handlers.push([SITE_SHARE, () => ok([{ site_code: SITE }])], [CLAIM, () => ok()], [STATE, () => (status === null ? ok() : ok([{ status }]))]);
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

  it('publish ucu: kişi kilidi ALINIR (kilit sırası); başarıda AnnouncementDetail döner', async () => {
    handlers.push([SITE_SHARE, () => ok([{ site_code: SITE }])], ...publishHandlers({ total: 2 }), ...detailHandlers(annRow({ status: 'published', recipient_count: 2 })));
    const result = await publishAnnouncement({ siteCode: SITE, id: '41', actor });
    assert.equal(result.status, 'published');
    assert.ok(indexOfQuery(ADVISORY) < indexOfQuery(CLAIM));
    assert.deepEqual(auditActions(), ['announcement.published']);
  });

  it('zamanlayıcı yayını: talep scheduled=true (yalnız zamanı gelmiş scheduled), actor Sistem (kullanıcı kodu yok), scheduled:true audit, kitle 0 olsa da yayınlanır', async () => {
    handlers.push([SITE_SHARE, () => ok([{ site_code: SITE }])], ...publishHandlers({ total: 0 }));
    const result = await publishDueAnnouncement({ id: 41, siteCode: SITE });
    assert.deepEqual(result, { published: true, recipientCount: 0, email: result.email });
    const claim = find(CLAIM);
    assert.deepEqual(claim.params, [41, SITE, true]);
    assert.match(claim.sql, /status = 'scheduled' AND publish_at <= NOW\(\)/);
    assert.match(claim.sql, /publish_at = CASE WHEN \$3::BOOLEAN THEN publish_at ELSE NULL END/);
    const row = auditRow('announcement.published');
    assert.equal(row.params[0], null, 'actor_user_code NULL');
    assert.equal(row.params[1], 'Sistem');
    assert.equal(row.params[2], 'system');
    assert.deepEqual(auditDetails('announcement.published').recipient_count, 0);
    assert.equal(auditDetails('announcement.published').scheduled, true);
    assert.ok(has(/^COMMIT$/));
  });

  it('zamanlayıcı: başka yoldan yayınlanmış / yeniden zamanlanmış kayıt için { skipped: true } (veri çiftlenmez, hata yok)', async () => {
    handlers.push([SITE_SHARE, () => ok([{ site_code: SITE }])], [CLAIM, () => ok()], [STATE, () => ok([{ status: 'published' }])]);
    const result = await publishDueAnnouncement({ id: 41, siteCode: SITE });
    assert.deepEqual(result, { skipped: true, status: 'published' });
    assert.equal(has(SNAPSHOT), false);
    assert.equal(has(FINAL), false);
  });

  it('zamanlayıcı: e-posta sınırı aşılsa da yayın ENGELLENMEZ (yönetici sınırı uygulanmaz), fazlası capped', async () => {
    handlers.push([SITE_SHARE, () => ok([{ site_code: SITE }])], ...publishHandlers({ claim: { importance: 'normal', target_type: 'site', target_block_ids: [], target_apartment_ids: [], send_email: true }, total: 4000, pending: 3000, used: 0 }));
    const result = await publishDueAnnouncement({ id: 41, siteCode: SITE });
    assert.equal(result.published, true);
    assert.deepEqual(find(CAP).params, [41, 500], 'varsayılan günlük sınır 500');
  });
});

describe('updateAnnouncement: düzenleme kuralları', () => {
  const lockRow = (overrides = {}) => [LOCK_ROW, () => ok([{ id: '41', title: 'Eski', body: 'Eski metin', importance: 'normal', status: 'draft', target_type: 'site', target_block_ids: [], target_apartment_ids: [], send_email: false, publish_at: null, ...overrides }])];

  it('yok / başka sitenin kaydı -> 404 (sorgu site kapsamlı); geri çekilen -> 409', async () => {
    handlers.push([SITE_SHARE, () => ok([{ site_code: SITE }])], [LOCK_ROW, () => ok()]);
    await assert.rejects(() => updateAnnouncement({ siteCode: SITE, id: '41', body: { title: 'Yeni' }, actor }), (e) => e.code === 'ANNOUNCEMENT_NOT_FOUND');
    assert.deepEqual(find(LOCK_ROW).params, [41, SITE]);
    handlers.unshift(lockRow({ status: 'withdrawn' }));
    await assert.rejects(() => updateAnnouncement({ siteCode: SITE, id: '41', body: { title: 'Yeni' }, actor }), (e) => e.code === 'INVALID_STATE' && e.statusCode === 409);
    assert.equal(has(/^UPDATE announcements SET title/), false);
  });

  it('yayınlanmış: yalnız başlık/metin; başka alan 409 INVALID_STATE ve HİÇBİR şey yazılmaz', async () => {
    handlers.push([SITE_SHARE, () => ok([{ site_code: SITE }])], lockRow({ status: 'published' }));
    for (const body of [{ importance: 'urgent' }, { title: 'Yeni', target: { type: 'site' } }, { send_email: true }, { publish_at: null }, { publish: 'draft' }]) {
      await assert.rejects(() => updateAnnouncement({ siteCode: SITE, id: '41', body, actor }), (e) => e.code === 'INVALID_STATE', JSON.stringify(body));
    }
    assert.equal(has(/^UPDATE announcements/), false);
    assert.equal(auditActions().length, 0);
  });

  it('yayınlanmış: başlık/metin değişimi edited_at + edit_count + 1 yazar, audit yalnız alan adları ve sayaç; kitle/e-posta sorgusu YOK', async () => {
    handlers.push(
      [SITE_SHARE, () => ok([{ site_code: SITE }])],
      lockRow({ status: 'published' }),
      [/^UPDATE announcements SET title = \$3, body = \$4, edited_at = NOW\(\), edit_count = edit_count \+ 1, updated_at = NOW\(\) WHERE id = \$1 AND site_code = \$2 AND status = 'published' RETURNING edit_count$/, () => ok([{ edit_count: 2 }])],
      ...detailHandlers(annRow({ status: 'published', edited_at: new Date() })),
    );
    await updateAnnouncement({ siteCode: SITE, id: '41', body: { title: SECRET_TITLE, body: SECRET_BODY }, actor });
    assert.deepEqual(find(/^UPDATE announcements SET title/).params, [41, SITE, SECRET_TITLE, SECRET_BODY]);
    assert.deepEqual(auditDetails('announcement.updated'), { fields: ['title', 'body'], edit_count: 2 });
    assert.equal(has(SNAPSHOT), false);
    assert.equal(has(ADVISORY), false, 'yayınlanmış düzenleme kişi kilidi almaz (yeniden bildirim yok)');
    assert.equal(has(/announcement_recipients/), true, 'yalnız ayrıntı istatistiği okunur');
    assert.equal(has(/UPDATE announcement_recipients/), false);
    assert.ok(!JSON.stringify(auditRow('announcement.updated').params).includes(SECRET_TITLE));
  });

  it('yayınlanmış: değişiklik yoksa UPDATE ve audit yazılmaz', async () => {
    handlers.push([SITE_SHARE, () => ok([{ site_code: SITE }])], lockRow({ status: 'published', title: 'Eski', body: 'Eski metin' }), ...detailHandlers(annRow({ status: 'published' })));
    await updateAnnouncement({ siteCode: SITE, id: '41', body: { title: 'Eski', body: 'Eski metin' }, actor });
    assert.equal(has(/^UPDATE announcements/), false);
    assert.equal(auditActions().length, 0);
  });

  it('taslak: yalnız DEĞİŞEN alanlar yazılır; audit alan adları; kitle yazılmaz', async () => {
    handlers.push(
      [SITE_SHARE, () => ok([{ site_code: SITE }])],
      lockRow(),
      [/^UPDATE announcements SET title = \$3, importance = \$4, updated_at = NOW\(\) WHERE id = \$1 AND site_code = \$2$/, () => ok([], 1)],
      ...detailHandlers(),
    );
    await updateAnnouncement({ siteCode: SITE, id: '41', body: { title: 'Yeni', body: 'Eski metin', importance: 'urgent' }, actor });
    assert.deepEqual(find(/^UPDATE announcements SET title/).params, [41, SITE, 'Yeni', 'urgent']);
    assert.deepEqual(auditDetails('announcement.updated'), { fields: ['title', 'importance'] });
    assert.equal(has(SNAPSHOT), false);
  });

  it('taslak: hedef değişimi kimlik doğrulanır ve dizi parametreleri yazılır', async () => {
    handlers.push(
      [/^SELECT COUNT\(\*\)::INTEGER AS n FROM apartments WHERE site_code = \$1 AND id = ANY\(\$2::BIGINT\[\]\)$/, () => ok([{ n: 2 }])],
      [SITE_SHARE, () => ok([{ site_code: SITE }])],
      lockRow(),
      [/^UPDATE announcements SET target_type = \$3, target_block_ids = \$4::BIGINT\[\], target_apartment_ids = \$5::BIGINT\[\], updated_at = NOW\(\) WHERE id = \$1 AND site_code = \$2$/, () => ok([], 1)],
      ...detailHandlers(annRow({ target_type: 'apartments', target_apartment_ids: ['7', '8'] })),
      [/^SELECT b\.block_name, a\.unit_label FROM apartments a INNER JOIN site_blocks b/, () => ok([{ block_name: 'A Blok', unit_label: 'Daire 1' }])],
    );
    await updateAnnouncement({ siteCode: SITE, id: '41', body: { target: { type: 'apartments', apartment_ids: [8, 7] } }, actor });
    assert.deepEqual(find(/^UPDATE announcements SET target_type/).params, [41, SITE, 'apartments', [], [8, 7]]);
    assert.deepEqual(auditDetails('announcement.updated'), { fields: ['target'] });
  });

  it('publish_at:null zamanlanmışı taslağa döndürür (status draft, publish_at NULL) ve audit alan adı publish_at', async () => {
    const when = new Date(NOW.getTime() + 7200_000);
    handlers.push(
      [SITE_SHARE, () => ok([{ site_code: SITE }])],
      lockRow({ status: 'scheduled', publish_at: when }),
      [/^UPDATE announcements SET status = \$3, publish_at = \$4, updated_at = NOW\(\) WHERE id = \$1 AND site_code = \$2$/, () => ok([], 1)],
      ...detailHandlers(),
    );
    await updateAnnouncement({ siteCode: SITE, id: '41', body: { publish_at: null }, actor, now: NOW });
    assert.deepEqual(find(/^UPDATE announcements SET status/).params, [41, SITE, 'draft', null]);
    assert.deepEqual(auditDetails('announcement.updated'), { fields: ['publish_at'] });
    assert.equal(auditActions().includes('announcement.scheduled'), false);
  });

  it('taslağa publish_at verilirse scheduled olur (audit updated + scheduled); zaman yokken publish:schedule -> 400 INVALID_SCHEDULE', async () => {
    const when = new Date(NOW.getTime() + 7200_000);
    handlers.push(
      [SITE_SHARE, () => ok([{ site_code: SITE }])],
      lockRow(),
      [/^UPDATE announcements SET status = \$3, publish_at = \$4, updated_at = NOW\(\) WHERE id = \$1 AND site_code = \$2$/, () => ok([], 1)],
      ...detailHandlers(annRow({ status: 'scheduled' })),
    );
    await updateAnnouncement({ siteCode: SITE, id: '41', body: { publish_at: when.toISOString() }, actor, now: NOW });
    assert.deepEqual(find(/^UPDATE announcements SET status/).params, [41, SITE, 'scheduled', when.toISOString()]);
    assert.deepEqual(auditActions(), ['announcement.updated', 'announcement.scheduled']);
    log.length = 0;
    await assert.rejects(() => updateAnnouncement({ siteCode: SITE, id: '41', body: { publish: 'schedule' }, actor, now: NOW }), (e) => e.code === 'INVALID_SCHEDULE');
  });

  it("publish:'now' düzenlemeyle birlikte AYNI işlemde yayınlar: kişi kilidi satır kilidinden ÖNCE; eski zamanlama temizlenir", async () => {
    handlers.push(
      [SITE_SHARE, () => ok([{ site_code: SITE }])],
      lockRow({ status: 'scheduled', publish_at: new Date(NOW.getTime() + 3600_000) }),
      [/^UPDATE announcements SET title = \$3, updated_at = NOW\(\) WHERE id = \$1 AND site_code = \$2$/, () => ok([], 1)],
      ...publishHandlers({ total: 2 }),
      ...detailHandlers(annRow({ status: 'published', recipient_count: 2 })),
    );
    await updateAnnouncement({ siteCode: SITE, id: '41', body: { title: 'Yeni', publish: 'now' }, actor, now: NOW });
    assert.ok(indexOfQuery(SITE_SHARE) < indexOfQuery(ADVISORY));
    assert.ok(indexOfQuery(ADVISORY) < indexOfQuery(LOCK_ROW), 'kilit sırası: kişi advisory -> duyuru satırı');
    assert.ok(indexOfQuery(LOCK_ROW) < indexOfQuery(CLAIM));
    assert.deepEqual(find(CLAIM).params, [41, SITE, false]);
    assert.equal(has(/^UPDATE announcements SET status = \$3/), false, "now durumunda ayrı status UPDATE'i yok (talep yazar)");
    assert.equal(findAll(/^COMMIT$/).length, 1);
  });
});

describe('withdraw / delete', () => {
  it('geri çek: talep UPDATE (yalnız published, site kapsamlı) -> bekleyen e-postalar iptal (durum none, adres NULL) -> audit sayılar', async () => {
    handlers.push(
      [SITE_SHARE, () => ok([{ site_code: SITE }])],
      [/^UPDATE announcements SET status = 'withdrawn', withdrawn_at = NOW\(\), updated_at = NOW\(\) WHERE id = \$1 AND site_code = \$2 AND status = 'published' RETURNING recipient_count$/, () => ok([{ recipient_count: 9 }])],
      [/^UPDATE announcement_recipients SET email_status = 'none', email = NULL WHERE announcement_id = \$1 AND email_status = 'pending'$/, () => ok([], 4)],
      ...detailHandlers(annRow({ status: 'withdrawn' })),
    );
    const result = await withdrawAnnouncement({ siteCode: SITE, id: '41', actor });
    assert.equal(result.status, 'withdrawn');
    assert.deepEqual(find(/^UPDATE announcements SET status = 'withdrawn'/).params, [41, SITE]);
    assert.deepEqual(find(/^UPDATE announcement_recipients SET email_status = 'none'/).params, [41]);
    assert.deepEqual(auditDetails('announcement.withdrawn'), { recipient_count: 9, email_cancelled: 4 });
    assert.equal(has(ADVISORY), false);
  });

  it('geri çek: yayında değil -> 409; yok -> 404', async () => {
    handlers.push([SITE_SHARE, () => ok([{ site_code: SITE }])], [/^UPDATE announcements SET status = 'withdrawn'/, () => ok()], [STATE, () => ok([{ status: 'draft' }])]);
    await assert.rejects(() => withdrawAnnouncement({ siteCode: SITE, id: '41', actor }), (e) => e.code === 'INVALID_STATE' && e.statusCode === 409);
    handlers.unshift([STATE, () => ok()]);
    await assert.rejects(() => withdrawAnnouncement({ siteCode: SITE, id: '41', actor }), (e) => e.code === 'ANNOUNCEMENT_NOT_FOUND' && e.statusCode === 404);
    assert.equal(has(/UPDATE announcement_recipients/), false);
  });

  it('sil: yalnız draft/scheduled (DELETE ... WHERE status IN ...), { ok: true }, audit yalnız eski durum', async () => {
    handlers.push([SITE_SHARE, () => ok([{ site_code: SITE }])], [/^DELETE FROM announcements WHERE id = \$1 AND site_code = \$2 AND status IN \('draft', 'scheduled'\) RETURNING status$/, () => ok([{ status: 'scheduled' }])]);
    assert.deepEqual(await deleteAnnouncement({ siteCode: SITE, id: '41', actor }), { ok: true });
    assert.deepEqual(find(/^DELETE FROM announcements/).params, [41, SITE]);
    assert.deepEqual(auditDetails('announcement.deleted'), { status: 'scheduled' });
  });

  it('sil: yayınlanmış -> 409 INVALID_STATE; yok -> 404; silme yazılmaz', async () => {
    handlers.push([SITE_SHARE, () => ok([{ site_code: SITE }])], [/^DELETE FROM announcements/, () => ok()], [STATE, () => ok([{ status: 'published' }])]);
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

  it('ayrıntı: site kapsamlı; istatistik (alıcı, okundu, okunmamış, e-posta durumları); hedef etiketi "Tüm site"', async () => {
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
    assert.deepEqual(detail.target, { type: 'site', block_ids: [], apartment_ids: [], labels: ['Tüm site'] });
    assert.equal(detail.read_count, 3);
    assert.equal(detail.body, 'Metin');
    assert.equal(detail.edit_count, 2, 'yayından sonra düzenleme sayısı (eklemeli alan)');
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
