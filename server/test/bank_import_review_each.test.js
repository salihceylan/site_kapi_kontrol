// Banka dosyası: K3 hesap (İşletme / Fon) seçimi + C-26 "güçlü eşleşmeleri de tek tek gözden geçir" seçeneği (DB'siz, durumlu sahte havuz).
// Gerçek PostgreSQL: scripts/qa_platform_pg.mjs "bank". Bu test SQL parametrelerini ve akışı doğrular:
//  - K3: eşleşen daire hesabında İKİ türün de (İşletme / Fon) açık borcu varsa güçlü eşleşme bile otomatik işlenmez ("check" + FUND_CHOICE_REQUIRED);
//    tek tür borçta eskisi gibi "recognized" kalır.
//  - C-26: commit gövdesinde review_each=true ise güçlü eşleşmeler HİÇ otomatik işlenmez (satır suggested + REVIEW_EACH, önerili daire korunur);
//    varsayılan (alan yok / false) davranış aynen eskisidir (postPayment denenir).
import { afterEach, beforeEach, describe, it } from 'node:test';
import assert from 'node:assert/strict';

process.env.JWT_SECRET ||= 'test-secret-test-secret-test-secret-123456';

const { pool } = await import('../src/db.js');
const { PlatformError } = await import('../src/modules/errors.js');
const { commitImport, previewImport } = await import('../src/modules/bank_import_service.js');
const { parseStatementBody } = await import('../src/modules/bank_import_common.js');

const SITE = 1;
const SHA = 'a'.repeat(64);
const NOW = new Date('2026-10-21T09:00:00Z');
const ACTOR = { id: 20001, user_code: 20001, role: 'site_manager', full_name: 'Mehmet Yönetici' };
const norm = (text) => String(text).replace(/\s+/g, ' ').trim();
const ok = (rows = []) => ({ rows, rowCount: rows.length });

const realQuery = pool.query;
const realConnect = pool.connect;
let state;

const debt = (id, fund, amount, party = 'owner') => ({
  id: String(id),
  apartment_id: '7',
  kind: 'charge',
  amount_minor: String(amount),
  entry_date: '2026-09-01',
  due_date: '2026-09-05',
  reverses_entry_id: null,
  fund,
  source_kind: null,
  late_fee_run_id: null,
  definition_id: null,
  def_charge_party: null,
  def_kind: null,
  account_party: party,
});

/** Sahte havuz: tek işleyici listesi hem pool.query hem pool.connect() istemcisi için kullanılır; eşleşmeyen SQL hata verir. */
function install({ fundRows = [], people = [], stopAtPost = true } = {}) {
  state = { calls: [], lineInserts: [], importInsert: null, audit: [], postAttempts: 0, nextId: 9000 };
  const handlers = [
    [/^(BEGIN|COMMIT|ROLLBACK)$/, () => ok()],
    [/^(SAVEPOINT|RELEASE SAVEPOINT|ROLLBACK TO SAVEPOINT) /, () => ok()],
    [/pg_advisory_xact_lock/, () => ok()],
    [/^SELECT site_code FROM sites WHERE site_code = \$1 FOR KEY SHARE$/, () => ok([{ site_code: SITE }])],
    [/SELECT site_code, enabled FROM site_modules WHERE module_code = \$1 AND site_code = ANY/, () => ok([{ site_code: String(SITE), enabled: true }])],
    [/SELECT enabled FROM site_modules WHERE site_code = \$1 AND module_code = \$2/, () => ok([{ enabled: true }])],
    // --- analiz (önizleme ve commit ortak)
    [/FROM finance_accounts WHERE id = \$1 AND site_code = \$2/, () => ok([{ id: 5, name: 'Banka', kind: 'bank', is_active: true }])],
    [/FROM finance_site_ref_prefixes/, () => ok([{ prefix: 'GUL', site_code: 1 }])],
    [/FROM finance_apartment_ref_codes/, () => ok([{ code: 'A2', apartment_id: 7, site_code: 1 }])],
    [/FROM bank_payer_ibans/, () => ok([])],
    [/FROM apartment_residencies r JOIN site_people p/, () => ok(people)],
    [/FROM apartments a JOIN site_blocks b ON b\.id = a\.block_id WHERE a\.site_code = \$1 AND a\.is_active/, () => ok([{ apartment_id: 7, unit_label: '2', block_name: 'A' }])],
    [/FROM apartments a JOIN site_blocks b ON b\.id = a\.block_id WHERE a\.site_code = \$1 AND a\.id = ANY/, () => ok([{ id: 7, unit_label: '2', block_name: 'A' }])],
    [/SELECT fingerprint FROM bank_statement_lines WHERE account_id = \$1 AND fingerprint = ANY/, () => ok([])],
    [/SELECT count\(\*\)::INT AS n FROM ledger_entries l/, () => ok([{ n: 0 }])],
    [/SELECT l\.id FROM ledger_entries l/, () => ok([])],
    [/FROM finance_period_closures/, () => ok([])],
    [/FROM bank_imports WHERE account_id = \$1 AND file_sha256/, () => ok([])],
    // --- K3: hesap seçimi denetimi (daire hesabı bilinmiyorsa önce varsayılan hesap çözülür)
    [/LEFT JOIN fee_definitions fd ON fd\.id = l\.definition_id WHERE l\.site_code = \$1 AND \(\$2::BIGINT\[\] IS NULL/, () => ok(fundRows)],
    [/FROM ledger_entries l WHERE l\.site_code = \$1 AND l\.apartment_id = \$2 ORDER BY l\.id/, () => ok([])],
    [/SELECT a\.responsible_party, EXISTS/, () => ok([{ responsible_party: 'both', has_tenant: false }])],
    // --- commit
    [/^SELECT \* FROM bank_imports WHERE site_code = \$1 AND idempotency_key = \$2$/, () => ok([])],
    [/^SELECT nextval\(pg_get_serial_sequence\('bank_statement_lines', 'id'\)\) AS id FROM generate_series/, (_s, p) => ok(Array.from({ length: p[0] }, () => ({ id: String(++state.nextId) })))],
    // postPayment denemesi: ilk kilitler döner, anahtar sorgusunda bilinçli durdurulur (bu testin konusu postPayment'ın içi DEĞİL, girilip girilmediğidir)
    [/^SELECT id, responsible_party FROM apartments WHERE id = \$1 AND site_code = \$2 FOR KEY SHARE$/, () => {
      state.postAttempts += 1;
      return ok([{ id: '7', responsible_party: 'both' }]);
    }],
    [/^SELECT user_code FROM users WHERE user_code = \$1 AND deleted_at IS NULL FOR KEY SHARE$/, (_s, p) => ok([{ user_code: p[0] }])],
    [/FROM ledger_entries l WHERE l\.site_code = \$1 AND l\.idempotency_key = \$2/, () => {
      if (stopAtPost) throw new PlatformError(409, 'TEST_DUR', 'Test: postPayment içinde durduruldu.');
      return ok([]);
    }],
    [/^INSERT INTO bank_imports/, (_s, p) => {
      state.importInsert = p;
      return ok([{ id: '31', account_id: '5', format: 'xlsx', file_name: 'ekstre.xlsx', line_count: p[9], duplicate_count: p[10], status: 'active', statement_from: null, statement_to: null, created_at: NOW, reverted_at: null }]);
    }],
    [/^INSERT INTO bank_statement_lines/, (_s, p) => {
      state.lineInserts.push(p);
      return ok();
    }],
    [/^INSERT INTO audit_log/, (_s, p) => {
      state.audit.push(p);
      return ok();
    }],
  ];
  const query = async (text, params = []) => {
    const sql = norm(text);
    state.calls.push({ sql, params });
    for (const [pattern, fn] of handlers) {
      if (pattern.test(sql)) return fn(sql, params);
    }
    throw new Error(`BEKLENMEYEN SQL: ${sql.slice(0, 220)}`);
  };
  pool.query = query;
  pool.connect = async () => ({ query, release() {} });
}

const body = (lines, extra = {}) => ({ account_id: 5, format: 'xlsx', file: { name: 'ekstre.xlsx', size: 100, sha256: SHA }, lines, ...extra });
// 'Gül-A2-1026' -> referans kodu (GUL + A2) -> daire 7, güçlü eşleşme
const refLine = (extra = {}) => ({ value_date: '2026-10-20', amount_minor: 150000, description: 'Gül-A2-1026 aidat', bank_reference: 'REF-0042', ...extra });
const weakLine = () => ({ value_date: '2026-10-20', amount_minor: 150000, description: 'A2 aidat', bank_reference: null });
const commitBody = (lines, extra = {}) => body(lines, { expected_hash: null, idempotency_key: 'bi-anahtar-0001', ...extra });

/** Commit için önce önizleme özeti alınır (beklenen özet = çözümleme özeti). */
async function commit(lines, extra = {}) {
  const preview = await previewImport({ siteCode: SITE, body: body(lines), now: NOW });
  return commitImport({ siteCode: SITE, body: commitBody(lines, { expected_hash: preview.preview_hash, ...extra }), actor: ACTOR, now: NOW });
}

afterEach(() => {
  pool.query = realQuery;
  pool.connect = realConnect;
});

describe('K3: banka dosyası önizlemesi — iki türün de açık borcu olan daire otomatik işlenmez', () => {
  beforeEach(() => install({ fundRows: [debt(1, 'operating', 100000), debt(2, 'capital', 300000)] }));

  it('güçlü eşleşme + iki tür açık borç => "check" + FUND_CHOICE_REQUIRED uyarısı; recognized 0; özet fund_choice 1', async () => {
    const out = await previewImport({ siteCode: SITE, body: body([refLine()]), now: NOW });
    assert.equal(out.lines[0].outcome, 'check');
    assert.deepEqual(out.lines[0].warnings, ['FUND_CHOICE_REQUIRED']);
    assert.equal(out.lines[0].match.apartment_id, 7, 'eşleşme korunur: yönetici onayda hesabı seçer');
    assert.equal(out.summary.recognized, 0);
    assert.equal(out.summary.check, 1);
    assert.equal(out.summary.fund_choice, 1);
  });

  it('zayıf eşleşmede (zaten "check") hesap denetimi için ek defter sorgusu yapılmaz', async () => {
    state.calls.length = 0;
    const out = await previewImport({ siteCode: SITE, body: body([weakLine()]), now: NOW });
    assert.equal(out.lines[0].outcome, 'check');
    assert.deepEqual(out.lines[0].warnings, []);
    assert.equal(out.summary.fund_choice, 0);
    assert.equal(state.calls.some((c) => /LEFT JOIN fee_definitions fd/.test(c.sql)), false);
  });
});

describe('K3: banka dosyası önizlemesi — tek tür ya da borçsuz daire eskisi gibi tanınır', () => {
  for (const [ad, fundRows] of [
    ['yalnız Aidat borcu', [debt(1, 'operating', 100000)]],
    ['yalnız Fon borcu', [debt(2, 'capital', 300000)]],
    ['açık borç yok', []],
  ]) {
    it(`${ad}: güçlü eşleşme "recognized" kalır`, async () => {
      install({ fundRows });
      const out = await previewImport({ siteCode: SITE, body: body([refLine()]), now: NOW });
      assert.equal(out.lines[0].outcome, 'recognized');
      assert.deepEqual(out.lines[0].warnings, []);
      assert.equal(out.summary.recognized, 1);
      assert.equal(out.summary.fund_choice, 0);
    });
  }

  it('eşleşmenin hesabı (ev sahibi / kiracı) belliyse varsayılan hesap sorgusu yapılmaz; denetim O hesabın defterine bakar', async () => {
    install({ fundRows: [debt(1, 'operating', 100000), debt(2, 'capital', 300000)], people: [{ apartment_id: 7, relation: 'tenant', full_name: 'Kemal Kiracı' }] });
    state.calls.length = 0;
    const out = await previewImport({ siteCode: SITE, body: body([refLine()]), now: NOW });
    // kiracı hesabının satırı yok (satırlar ev sahibi hesabında): kiracı hesabı borçsuz => tanınır
    assert.equal(out.lines[0].match.party, 'tenant');
    assert.equal(out.lines[0].outcome, 'recognized');
    assert.equal(state.calls.some((c) => /FROM ledger_entries l WHERE l\.site_code = \$1 AND l\.apartment_id = \$2 ORDER BY l\.id/.test(c.sql)), false);
  });
});

describe('C-26: "tek tek gözden geçir" seçeneği (commit)', () => {
  beforeEach(() => install({ fundRows: [debt(1, 'operating', 100000)] }));

  it('VARSAYILAN (alan yok): güçlü eşleşme için postPayment denenir (eski davranış); denemeyi sahte sınır durdurur => satır suggested + hata kodu', async () => {
    const out = await commit([refLine()]);
    assert.equal(out.status, 201);
    assert.equal(state.postAttempts, 1, 'otomatik tahsilat denendi');
    const params = state.lineInserts[0];
    assert.equal(params[13], 'suggested');
    assert.equal(params[18], 'TEST_DUR');
  });

  it('review_each=false açıkça verilse de varsayılanla aynıdır', async () => {
    await commit([refLine()], { review_each: false });
    assert.equal(state.postAttempts, 1);
  });

  it('review_each=true: HİÇBİR tahsilat denenmez; satır önerili daireyle suggested + REVIEW_EACH; sayaçlar posted 0 / attention 1', async () => {
    const out = await commit([refLine()], { review_each: true });
    assert.equal(out.status, 201);
    assert.equal(state.postAttempts, 0, 'otomatik tahsilat YAZILMAZ');
    assert.equal(state.calls.some((c) => /^INSERT INTO ledger_entries/.test(c.sql)), false);
    const params = state.lineInserts[0];
    assert.equal(params[13], 'suggested', 'status');
    assert.equal(params[14], 'ref', 'eşleşme yöntemi korunur');
    assert.equal(params[15], 7, 'önerilen daire korunur');
    assert.equal(params[17], null, 'defter satırı yok');
    assert.equal(params[18], 'REVIEW_EACH', 'not');
    assert.deepEqual(out.body.counts, { posted: 0, linked: 0, attention: 1 });
    // denetim kaydı seçeneği taşır
    const created = state.audit.find((p) => p[3] === 'finance.bank_import.created');
    assert.ok(created, 'denetim kaydı yazıldı');
    assert.equal(JSON.parse(created[7]).review_each, true, 'audit: review_each=true');
  });

  it('review_each parmak izine YALNIZ true iken girer: aynı anahtar + farklı seçenek yeni isteği ayırır; varsayılan parmak izi eskisiyle aynı', async () => {
    await commit([refLine()]);
    const plain = state.importInsert[12];
    install({ fundRows: [debt(1, 'operating', 100000)] });
    await commit([refLine()], { review_each: true });
    const reviewed = state.importInsert[12];
    assert.notEqual(plain, reviewed);
    assert.match(plain, /^[0-9a-f]{64}$/);
    const { createHash } = await import('node:crypto');
    const preview = await previewImport({ siteCode: SITE, body: body([refLine()]), now: NOW });
    const legacy = createHash('sha256').update(JSON.stringify([5, SHA, preview.preview_hash])).digest('hex');
    assert.equal(plain, legacy, 'seçenek yokken parmak izi 3 elemanlı eski biçimle birebir aynı');
  });

  it('review_each yalnız güçlü ve tanınan satırları bekletir: zayıf / tanınmayan satırların davranışı değişmez', async () => {
    const out = await commit([weakLine()], { review_each: true });
    assert.equal(out.status, 201);
    assert.equal(state.postAttempts, 0);
    const params = state.lineInserts[0];
    assert.equal(params[13], 'suggested');
    assert.equal(params[18], null, 'zaten kontrol bölümünde: not eklenmez');
  });
});

describe('K3: banka dosyası commit — iki tür açık borçlu daire otomatik işlenmez', () => {
  beforeEach(() => install({ fundRows: [debt(1, 'operating', 100000), debt(2, 'capital', 300000)] }));

  it('güçlü eşleşme kontrol bölümüne düşer (suggested + FUND_CHOICE_REQUIRED); postPayment HİÇ denenmez', async () => {
    const out = await commit([refLine()]);
    assert.equal(out.status, 201);
    assert.equal(state.postAttempts, 0);
    const params = state.lineInserts[0];
    assert.equal(params[13], 'suggested');
    assert.equal(params[15], 7, 'önerilen daire korunur (yönetici hesabı onayda seçer)');
    assert.equal(params[18], 'FUND_CHOICE_REQUIRED');
    assert.deepEqual(out.body.counts, { posted: 0, linked: 0, attention: 1 });
  });
});

describe('review_each gövde ayrıştırması', () => {
  const parsed = (extra) => parseStatementBody(commitBody([refLine()], { expected_hash: 'b'.repeat(64), ...extra }), { commit: true, todayIso: '2026-10-21' });

  it('yok / null / false => false; true => true', () => {
    assert.equal(parsed({}).reviewEach, false);
    assert.equal(parsed({ review_each: null }).reviewEach, false);
    assert.equal(parsed({ review_each: false }).reviewEach, false);
    assert.equal(parsed({ review_each: true }).reviewEach, true);
  });

  it('boolean olmayan değer 400 INVALID_BODY (sessizce "evet" sayılmaz)', () => {
    for (const bad of ['true', 1, 'evet', {}, []]) {
      assert.throws(() => parsed({ review_each: bad }), (e) => e.statusCode === 400 && e.code === 'INVALID_BODY', String(bad));
    }
  });

  it('önizleme gövdesinde alan yoktur (seçenek yalnız commit komutudur)', () => {
    const preview = parseStatementBody(body([refLine()]), { todayIso: '2026-10-21' });
    assert.equal(preview.reviewEach, undefined);
  });
});
