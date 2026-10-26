// Dekont bildirimi: sakin -> bildirim -> dosya yükleme -> yönetici onayı ZİNCİRİ (DB'siz, durumlu sahte veritabanı).
// Gerçek PostgreSQL doğrulaması (kısıtlar, tetikleyiciler, eşzamanlılık) kullanıcı denemesinde / QA'dadır; bu test SQL parametrelerini ve akışı doğrular.
//  - P1: sakin bildirimi hesap alanını loadVisibleAccounts görünümünden (`account_party`) alır; eskiden `own.party` (undefined) -> NULL -> NOT NULL ihlali (500).
//  - P2: POSSIBLE_DUPLICATE yalnız bekleyenleri değil onaylı bildirimleri ve bildirime / banka satırına bağlı tahsilatları da sayar.
import { afterEach, beforeEach, describe, it } from 'node:test';
import assert from 'node:assert/strict';

process.env.JWT_SECRET ||= 'test-secret-test-secret-test-secret-123456';

const { pool } = await import('../src/db.js');
const { approveNotice, completeUpload, computeNoticeWarnings, createMyNotice, getNoticeDetail } = await import('../src/modules/payment_notice_service.js');

const SITE = 1000000001;
const NOW = new Date('2026-10-21T09:00:00Z');
const RESIDENT = { id: 42, user_code: 42, role: 'resident', full_name: 'Ayşe Sakin' };
const MANAGER = { id: 20001, user_code: 20001, role: 'site_manager', full_name: 'Mehmet Yönetici' };
const norm = (text) => String(text).replace(/\s+/g, ' ').trim();
const ok = (rows = []) => ({ rows, rowCount: rows.length });

let originalQuery;
let originalConnect;
let db;

/** Durumlu sahte veritabanı: tek işleyici listesi hem pool.query hem de pool.connect() istemcisi için kullanılır. */
function makeDb({ views, dupCount = 0 } = {}) {
  const state = {
    notice: null,
    insertParams: null,
    ledgerInsertParams: null,
    approveUpdateParams: null,
    dupSql: null,
    dupParams: null,
    dupCount,
    log: [],
  };
  const noticeRow = () => ({
    ...state.notice,
    block_name: 'A Blok',
    unit_label: '7',
  });
  const handlers = [
    [/^(BEGIN|COMMIT|ROLLBACK)$/, () => ok()],
    [/^(SAVEPOINT|RELEASE SAVEPOINT|ROLLBACK TO SAVEPOINT) /, () => ok()],
    [/pg_try_advisory_xact_lock/, () => ok([{ locked: false }])], // kişi eşitlemesi atlanır (busy)
    [/pg_advisory_xact_lock/, () => ok()],
    // --- sakin: görünür daireler + modül + ayar
    [
      /FROM site_people sp INNER JOIN apartment_residencies r/,
      () =>
        ok([
          {
            apartment_id: '7',
            site_code: String(SITE),
            site_name: 'Gül Sitesi',
            unit_label: '7',
            block_name: 'A Blok',
            block_sort: 1,
            apt_sort: 7,
            responsible_party: views?.responsible ?? 'both',
            relation: views?.relation ?? 'owner',
            start_date: '2026-01-01',
            relation_created_at: new Date('2026-01-01T08:00:00Z'),
            has_current_tenant: views?.hasTenant ?? false,
            has_responsible_person: true,
            previous: [],
          },
        ]),
    ],
    [/SELECT site_code, enabled FROM site_modules WHERE module_code = \$1 AND site_code = ANY/, () => ok([{ site_code: String(SITE), enabled: true }])],
    [/SELECT enabled FROM site_modules WHERE site_code = \$1 AND module_code = \$2/, () => ok([{ enabled: true }])],
    [/SELECT notices_enabled FROM finance_payment_settings/, () => ok([{ notices_enabled: true }])],
    // --- bildirim ekleme
    [/WHERE n\.site_code = \$1 AND n\.apartment_id = \$2 AND n\.idempotency_key = \$3/, () => ok([])],
    [/FROM payment_notices WHERE submitted_by = \$1/, () => ok([{ n: 0 }])],
    [/FROM payment_notices WHERE apartment_id = \$1 AND origin/, () => ok([{ n: 0 }])],
    [/COALESCE\(SUM\(size_bytes\), 0\)::TEXT AS total FROM payment_notices/, () => ok([{ total: '0' }])],
    [
      /^INSERT INTO payment_notices/,
      (_s, p) => {
        state.insertParams = p;
        state.notice = {
          id: '55',
          site_code: String(p[0]),
          apartment_id: String(p[1]),
          account_party: p[2], // NOT NULL kısıtını sahte veritabanı da uygular
          origin: p[3],
          submitted_by: p[4],
          amount_minor: String(p[5]),
          paid_on: p[6],
          method: p[7],
          sender_name: p[8],
          sender_iban: p[9],
          description: p[10],
          note: p[11],
          status: p[12],
          file_required: p[13],
          storage_key: p[14],
          display_name: p[15],
          mime_type: p[16],
          size_bytes: p[17] === null ? null : String(p[17]),
          sha256: null,
          file_completed_at: null,
          submitted_at: NOW,
          decided_by: null,
          decided_at: null,
          reject_reason_code: null,
          reject_note: null,
          ledger_entry_id: null,
          linked_existing: false,
          resident_seen_at: null,
          idempotency_key: p[18],
          request_fingerprint: p[19],
        };
        if (state.notice.account_party === undefined || state.notice.account_party === null) {
          const error = new Error('null value in column "account_party" of relation "payment_notices" violates not-null constraint');
          error.code = '23502';
          throw error;
        }
        return ok([{ id: '55' }]);
      },
    ],
    [
      /^UPDATE payment_notices SET status = 'pending', sha256 = \$2/,
      (_s, p) => {
        state.notice = { ...state.notice, status: 'pending', sha256: p[1], file_completed_at: NOW };
        return ok([{ site_code: state.notice.site_code }]);
      },
    ],
    // --- bildirim okuma (SELECT_NOTICE): tek satır
    [/FROM payment_notices n INNER JOIN apartments a ON a\.id = n\.apartment_id/, () => ok(state.notice ? [noticeRow()] : [])],
    // --- onay: kilitler
    [/^SELECT site_code FROM sites WHERE site_code = \$1 FOR KEY SHARE$/, () => ok([{ site_code: SITE }])],
    [/^SELECT apartment_id FROM payment_notices WHERE id = \$1 AND site_code = \$2$/, () => ok([{ apartment_id: '7' }])],
    [/^SELECT id FROM apartments WHERE id = \$1 AND site_code = \$2 FOR KEY SHARE$/, () => ok([{ id: '7' }])],
    [/^SELECT user_code FROM users WHERE user_code = \$1 AND deleted_at IS NULL FOR KEY SHARE$/, (_s, p) => ok([{ user_code: p[0] }])],
    // --- onay: uyarı gerçekleri
    [/FROM payment_notices WHERE site_code = \$1 AND sha256 = \$2 AND id <> \$3/, () => ok([{ n: 0 }])],
    [
      /FROM payment_notices o/,
      (sql, p) => {
        state.dupSql = sql;
        state.dupParams = p;
        return ok([{ n: state.dupCount }]);
      },
    ],
    [/FROM apartment_residencies r INNER JOIN site_people sp ON sp\.id = r\.person_id WHERE r\.apartment_id = \$1 AND r\.is_current = TRUE AND sp\.is_active = TRUE AND sp\.full_name/, () => ok([])],
    [/SELECT COALESCE\(SUM\(l\.amount_minor\), 0\)::TEXT AS balance FROM ledger_entries l/, () => ok([{ balance: '150000' }])],
    [/SELECT sp\.full_name AS name, r\.relation FROM apartment_residencies r/, () => ok([])],
    [/SELECT l\.id, to_char\(l\.entry_date, 'YYYY-MM-DD'\) AS entry_date, \(-l\.amount_minor\)::TEXT AS amount_minor/, () => ok([])],
    [/GROUP BY 1/, () => ok([])], // accountBalances
    [/FROM finance_period_closures/, () => ok([])],
    [/SELECT resident_account_id FROM finance_payment_settings/, () => ok([{ resident_account_id: null }])],
    // --- onay: postPayment
    [/^SELECT id, responsible_party FROM apartments WHERE id = \$1 AND site_code = \$2 FOR KEY SHARE$/, () => ok([{ id: '7', responsible_party: 'both' }])],
    [/FROM ledger_entries l WHERE l\.site_code = \$1 AND l\.idempotency_key = \$2/, () => ok([])],
    [/^SELECT m\.id, m\.account_id/, () => ok([])],
    [/SELECT bool_or\(is_active\) AS has_active FROM finance_accounts/, () => ok([])],
    [
      /^INSERT INTO ledger_entries/,
      (_s, p) => {
        state.ledgerInsertParams = p;
        return ok([{ id: '901' }]);
      },
    ],
    [/FROM finance_settings/, () => ok([{ receipts_auto_issue: false }])],
    [/FROM receipts r/, () => ok([])],
    [/^INSERT INTO audit_log/, () => ok()],
    [
      /^UPDATE payment_notices SET status = 'approved'/,
      (_s, p) => {
        state.approveUpdateParams = p;
        state.notice = { ...state.notice, status: 'approved', ledger_entry_id: String(p[1]), decided_by: p[2], decided_at: NOW, account_party: p[3] };
        return ok();
      },
    ],
  ];
  const query = async (text, params = []) => {
    const sql = norm(text);
    state.log.push({ sql, params });
    for (const [pattern, fn] of handlers) {
      if (pattern.test(sql)) return fn(sql, params);
    }
    throw new Error(`BEKLENMEYEN SQL: ${sql.slice(0, 220)}`);
  };
  return { state, query };
}

function install(options) {
  db = makeDb(options);
  originalQuery = pool.query;
  originalConnect = pool.connect;
  pool.query = db.query;
  pool.connect = async () => ({ query: db.query, release() {} });
}

const residentBody = (extra = {}) => ({
  apartment_id: 7,
  amount_minor: 125000,
  paid_on: '2026-10-20',
  idempotency_key: 'sakin-anahtar-1',
  file: { name: 'dekont.pdf', size: 1000, content_type: 'application/pdf' },
  ...extra,
});

describe('sakin -> bildirim -> onay zinciri', () => {
  beforeEach(() => install());
  afterEach(() => {
    pool.query = originalQuery;
    pool.connect = originalConnect;
  });

  it('P1: sakin bildirimi hesabı görünümün account_party alanından alır (INSERT $3 = owner); NULL / 500 olmaz', async () => {
    const out = await createMyNotice(RESIDENT, residentBody(), { now: NOW });
    assert.equal(db.state.insertParams[2], 'owner', 'payment_notices.account_party');
    assert.equal(out.notice.account_party, 'owner');
    assert.equal(out.notice.status, 'uploading');
    assert.equal(out.replayed, false);
    assert.equal(out.upload.method, 'PUT');
    assert.equal(db.state.insertParams[4], 42, 'gönderen = sakin');
    assert.equal(db.state.insertParams[3], 'resident_app');
  });

  it('kiracı sakin: bildirim kiracı hesabına (tenant) yazılır', async () => {
    pool.query = originalQuery;
    pool.connect = originalConnect;
    install({ views: { relation: 'tenant', responsible: 'both', hasTenant: true } });
    const out = await createMyNotice(RESIDENT, residentBody({ idempotency_key: 'sakin-anahtar-2' }), { now: NOW });
    assert.equal(db.state.insertParams[2], 'tenant');
    assert.equal(out.notice.account_party, 'tenant');
  });

  it('yetkisiz daire: sakinin görünümünde olmayan daire 404 APARTMENT_NOT_FOUND', async () => {
    await assert.rejects(() => createMyNotice(RESIDENT, residentBody({ apartment_id: 99, idempotency_key: 'sakin-anahtar-3' }), { now: NOW }), (e) => e.code === 'APARTMENT_NOT_FOUND');
    assert.equal(db.state.insertParams, null);
  });

  it('tam zincir: sakin bildirir -> dosya tamamlanır (pending) -> yönetici onaylar -> tahsilat sakinin hesabına (owner) yazılır, bildirim approved', async () => {
    await createMyNotice(RESIDENT, residentBody(), { now: NOW });
    const uploaded = await completeUpload({ id: 55, sha256: 'b'.repeat(64) });
    assert.equal(uploaded.notice.status, 'pending');

    const approved = await approveNotice({ siteCode: SITE, rawId: '55', body: {}, actor: MANAGER, now: NOW });
    assert.equal(approved.replayed, false);
    assert.equal(approved.entry_id, 901);
    assert.equal(approved.notice.status, 'approved');
    // defter satırı: hesap = owner, kaynak izi payment_notice / 55, anahtar pn:55, tutar negatif
    const ledger = db.state.ledgerInsertParams;
    assert.ok(ledger.includes('owner'));
    assert.deepEqual(ledger.slice(10), ['owner', 'payment_notice', 55, null]);
    assert.ok(ledger.includes('pn:55'));
    assert.ok(ledger.includes('-125000'));
    // bildirim satırı: onayda hesap korunur
    assert.equal(db.state.approveUpdateParams[3], 'owner');
    assert.equal(db.state.approveUpdateParams[1], 901);
  });

  it('P2: olası çift tahsilat sayımı bekleyen + ONAYLI bildirimleri ve bildirime / banka satırına bağlı tahsilatları da kapsar', async () => {
    await createMyNotice(RESIDENT, residentBody(), { now: NOW });
    await completeUpload({ id: 55, sha256: 'b'.repeat(64) });
    const detail = await getNoticeDetail(SITE, '55', { now: NOW });
    assert.deepEqual(detail.warnings.map((w) => w.code), []);
    const sql = db.state.dupSql;
    assert.match(sql, /o\.status IN \('pending', 'approved'\)/);
    // onaylı bildirimin tahsilatı iptal edilmişse sayılmaz
    assert.match(sql, /o\.status = 'pending' OR NOT EXISTS \(SELECT 1 FROM ledger_entries r WHERE r\.reverses_entry_id = o\.ledger_entry_id\)/);
    // bildirime bağlı tahsilat dışlanmaz (eski: NOT EXISTS payment_notices pn WHERE pn.ledger_entry_id = l.id)
    assert.doesNotMatch(sql, /pn\.ledger_entry_id/);
    assert.match(sql, /NOT EXISTS \(SELECT 1 FROM ledger_entries r WHERE r\.reverses_entry_id = l\.id\)/, 'iptal edilmiş tahsilat sayılmaz');
    // parametreler: site, daire, tutar, tarih, hesap, bildirim kimliği
    assert.deepEqual(db.state.dupParams.map(String), [String(SITE), '7', '125000', '2026-10-20', 'owner', '55']);
  });

  it('P2: yinelenen havale uyarısı önemli (strong): onay açık kabul olmadan geçmez; kabulle geçer', async () => {
    pool.query = originalQuery;
    pool.connect = originalConnect;
    install({ dupCount: 1 });
    await createMyNotice(RESIDENT, residentBody(), { now: NOW });
    await completeUpload({ id: 55, sha256: 'b'.repeat(64) });
    const warnings = await computeNoticeWarnings(pool, db.state.notice, NOW);
    assert.ok(warnings.some((w) => w.code === 'POSSIBLE_DUPLICATE' && w.level === 'strong'));
    await assert.rejects(
      () => approveNotice({ siteCode: SITE, rawId: '55', body: {}, actor: MANAGER, now: NOW }),
      (e) => e.code === 'NOTICE_WARNINGS_UNACKNOWLEDGED',
    );
    assert.equal(db.state.ledgerInsertParams, null, 'kabul edilmeden tahsilat yazılmaz');
    const approved = await approveNotice({ siteCode: SITE, rawId: '55', body: { acknowledged: ['POSSIBLE_DUPLICATE'] }, actor: MANAGER, now: NOW });
    assert.equal(approved.notice.status, 'approved');
  });
});
