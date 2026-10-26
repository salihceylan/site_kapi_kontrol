// Banka içe aktarma: yineleme ve çift tahsilat koruması (DB'siz, sahte havuz). Gerçek PostgreSQL: scripts/qa_platform_pg.mjs "bank".
//  - Referanslı satırın parmak izi açıklamadan bağımsızdır (aynı ekstre PDF -> XLSX yüklenince yeni sayılmaz).
//  - Eski formülle (açıklama + ref) kaydedilmiş satır da yineleme sayılır (formül değişti; geçmiş yüklemeler çift tahsilata açılmasın).
//  - Aynı hesap + daire + tutar + valörde BAŞKA banka satırına bağlı tahsilat varsa güçlü eşleşme bile 'check' olur (otomatik tahsilat yok).
import { afterEach, beforeEach, describe, it } from 'node:test';
import assert from 'node:assert/strict';

process.env.JWT_SECRET ||= 'test-secret-test-secret-test-secret-123456';

const { pool } = await import('../src/db.js');
const { previewImport, countBankLinkedPayments } = await import('../src/modules/bank_import_service.js');
const { computeFingerprints, computeLegacyFingerprints } = await import('../src/modules/bank_line_match.js');

const norm = (text) => String(text).replace(/\s+/g, ' ').trim();
const ok = (rows = []) => ({ rows, rowCount: rows.length });
const SHA = 'a'.repeat(64);
const NOW = new Date('2026-10-21T09:00:00Z');

let originalQuery;
let state;

/** Sahte havuz: her sorgu bir işleyiciyle eşleşmeli; eşleşmeyen SQL hata verir. */
function install() {
  state = { storedFingerprints: [], bankLinkedCount: 0, calls: [] };
  pool.query = async (text, params = []) => {
    const sql = norm(text);
    state.calls.push({ sql, params });
    const handlers = [
      [/FROM finance_accounts WHERE id = \$1 AND site_code = \$2/, () => ok([{ id: 5, name: 'Banka', kind: 'bank', is_active: true }])],
      [/FROM finance_site_ref_prefixes/, () => ok([{ prefix: 'GUL', site_code: 1 }])],
      [/FROM finance_apartment_ref_codes/, () => ok([{ code: 'A2', apartment_id: 7, site_code: 1 }])],
      [/FROM bank_payer_ibans/, () => ok([])],
      [/FROM apartment_residencies r JOIN site_people p/, () => ok([])],
      [/FROM apartments a JOIN site_blocks b ON b\.id = a\.block_id WHERE a\.site_code = \$1 AND a\.is_active/, () => ok([{ apartment_id: 7, unit_label: '2', block_name: 'A' }])],
      [/FROM apartments a JOIN site_blocks b ON b\.id = a\.block_id WHERE a\.site_code = \$1 AND a\.id = ANY/, () => ok([{ id: 7, unit_label: '2', block_name: 'A' }])],
      [/SELECT fingerprint FROM bank_statement_lines WHERE account_id = \$1 AND fingerprint = ANY/, (_s, p) => ok(state.storedFingerprints.filter((fp) => p[1].includes(fp)).map((fingerprint) => ({ fingerprint })))],
      [/SELECT count\(\*\)::INT AS n FROM ledger_entries l/, () => ok([{ n: state.bankLinkedCount }])],
      [/SELECT l\.id FROM ledger_entries l/, () => ok([])],
      [/FROM finance_period_closures/, () => ok([])],
      [/FROM bank_imports WHERE account_id = \$1 AND file_sha256/, () => ok([])],
    ];
    for (const [pattern, fn] of handlers) {
      if (pattern.test(sql)) return fn(sql, params);
    }
    throw new Error(`BEKLENMEYEN SQL: ${sql.slice(0, 200)}`);
  };
}

const body = (lines) => ({ account_id: 5, format: 'xlsx', file: { name: 'ekstre.xlsx', size: 100, sha256: SHA }, lines });
// 'Gül-A2-1026' -> referans kodu (GUL + A2) -> daire 7, güçlü eşleşme
const refLine = (extra = {}) => ({ value_date: '2026-10-20', amount_minor: 150000, description: 'Gül-A2-1026 aidat', bank_reference: 'REF-0042', ...extra });

describe('banka içe aktarma: yineleme ve çift tahsilat koruması', () => {
  beforeEach(() => {
    originalQuery = pool.query;
    install();
  });
  afterEach(() => {
    pool.query = originalQuery;
  });

  it('temel durum: referanslı güçlü satır tanınır (recognized)', async () => {
    const out = await previewImport({ siteCode: 1, body: body([refLine()]), now: NOW });
    assert.equal(out.lines[0].outcome, 'recognized');
    assert.equal(out.lines[0].match.apartment_id, 7);
    assert.deepEqual(out.lines[0].warnings, []);
  });

  it('YENİ formül parmak izi kayıtlıysa satır yineleme; açıklaması farklı biçimden (PDF -> XLSX) gelse de', async () => {
    const stored = computeFingerprints(5, [refLine({ description: 'EFT GELEN (PDF metni)' })]);
    state.storedFingerprints = stored;
    const out = await previewImport({ siteCode: 1, body: body([refLine({ description: 'Gül-A2-1026 aidat (XLSX metni)' })]), now: NOW });
    assert.equal(out.lines[0].outcome, 'duplicate');
    assert.equal(out.summary.duplicates, 1);
  });

  it('ESKİ formül (açıklama + ref) parmak izi kayıtlıysa satır yine yineleme sayılır (geriye uyum)', async () => {
    const line = refLine();
    state.storedFingerprints = computeLegacyFingerprints(5, [line]);
    assert.notDeepEqual(state.storedFingerprints, computeFingerprints(5, [line]), 'önkoşul: eski ve yeni parmak izi farklı');
    const out = await previewImport({ siteCode: 1, body: body([line]), now: NOW });
    assert.equal(out.lines[0].outcome, 'duplicate');
    // sorgu iki formülün parmak izlerini birlikte arar
    const dupQuery = state.calls.find((c) => /SELECT fingerprint FROM bank_statement_lines/.test(c.sql));
    assert.equal(dupQuery.params[1].length, 2);
  });

  it('aynı hesap + daire + tutar + valörde başka banka satırına bağlı tahsilat varsa güçlü eşleşme "check" olur (otomatik tahsilat YOK)', async () => {
    state.bankLinkedCount = 1;
    const out = await previewImport({ siteCode: 1, body: body([refLine()]), now: NOW });
    assert.equal(out.lines[0].outcome, 'check');
    assert.deepEqual(out.lines[0].warnings, ['POSSIBLE_DUPLICATE_PAYMENT']);
    assert.equal(out.summary.recognized, 0);
    assert.equal(out.summary.check, 1);
    // mevcut tahsilata bağlama araması yapılmaz (aday zaten başka satırın)
    assert.equal(state.calls.some((c) => /SELECT l\.id FROM ledger_entries l/.test(c.sql)), false);
  });

  it('countBankLinkedPayments: yalnız aynı valör, aynı hesap hareketi, iptal edilmemiş ve posted/linked banka satırına bağlı tahsilatları sayar', async () => {
    state.bankLinkedCount = 2;
    const n = await countBankLinkedPayments(pool, 1, { apartmentId: 7, accountId: 5, amountMinor: 150000, valueDate: '2026-10-20' });
    assert.equal(n, 2);
    const call = state.calls.at(-1);
    assert.deepEqual(call.params, [1, 7, 5, '-150000', '2026-10-20']);
    assert.match(call.sql, /l\.entry_date = \$5::DATE/);
    assert.match(call.sql, /m\.account_id = \$3/);
    assert.match(call.sql, /NOT EXISTS \(SELECT 1 FROM ledger_entries x WHERE x\.reverses_entry_id = l\.id\)/);
    assert.match(call.sql, /b\.status IN \('posted', 'linked'\)/);
  });

  it('zayıf eşleşmede (check zaten) ek sorgu yapılmaz', async () => {
    const weak = { value_date: '2026-10-20', amount_minor: 150000, description: 'A2 aidat', bank_reference: null };
    // daire kodu A2 (zayıf) -> bank bağlı sorgusu çalışmaz
    state.calls.length = 0;
    const out = await previewImport({ siteCode: 1, body: body([weak]), now: NOW });
    assert.equal(out.lines[0].outcome, 'check');
    assert.equal(state.calls.some((c) => /SELECT count\(\*\)::INT AS n FROM ledger_entries l/.test(c.sql)), false);
  });
});
