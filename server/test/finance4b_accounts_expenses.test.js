// Finans Faz 4b kasa/banka + gider (saf): gövde ayrıştırıcıları, parmak izleri, süzgeç SQL'i, belge adaptörü (ad temizliği, başlıklar, dikiş yokluğu).
import { afterEach, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { Readable } from 'node:stream';
import {
  ACCOUNT_KINDS,
  ADJUSTMENT_REASONS,
  MAX_ACCOUNT_AMOUNT,
  parseAccountCreate,
  parseAccountPatch,
  parseAdjustment,
  parseAssignBody,
  parseMovementsQuery,
  parseReconciliation,
  parseTransfer,
  parseVoidBody as parseTransferVoid,
} from '../src/modules/finance_accounts.js';
import {
  DEFAULT_EXPENSE_CATEGORIES,
  expenseFilterSql,
  expenseFingerprint,
  mapExpenseRow,
  normalizeDocumentNo,
  parseCategoryBody,
  parseExpenseInput,
  parseExpensesQuery,
  parseSuppliersQuery,
  parseVoidInput,
  redactSupplierForBoard,
} from '../src/modules/finance_expenses.js';
import {
  STORAGE_KEY_PATTERN,
  downloadHeaders,
  loadDocumentSeam,
  maxFileBytes,
  requireDocumentSeam,
  reserveStorageKey,
  sanitizeDocumentName,
  setDocumentSeamForTests,
  siteQuotaBytes,
  streamOf,
} from '../src/modules/finance_documents_adapter.js';
import { parseDocumentCreate } from '../src/modules/finance_expense_documents.js';

const NOW = new Date('2026-10-16T09:00:00Z');
const KEY = 'anahtar-12345';
const throwsCode = (fn, code) => assert.throws(fn, (error) => error.code === code, code);
const throws400 = (fn, label) => assert.throws(fn, (error) => error.statusCode === 400 && error.code === 'INVALID_BODY' && error.expose === true, label);

describe('hesap gövdeleri', () => {
  const base = { name: ' Banka  1 ', kind: 'bank', opening_date: '2026-01-01', opening_balance_minor: 150000, idempotency_key: KEY };

  it('oluşturma: ad boşluk daraltılır, tür kasa/banka, açılış bakiyesi tamsayı kuruş (varsayılan 0, eksi serbest), gelecek tarih ve anahtarsız istek reddedilir', () => {
    const ok = parseAccountCreate(base, NOW);
    assert.deepEqual(ok, { name: 'Banka 1', kind: 'bank', note: null, openingBalanceMinor: 150000, openingDate: '2026-01-01', idempotencyKey: KEY });
    assert.equal(parseAccountCreate({ ...base, opening_balance_minor: undefined, kind: 'cash' }, NOW).openingBalanceMinor, 0);
    assert.equal(parseAccountCreate({ ...base, opening_balance_minor: -500 }, NOW).openingBalanceMinor, -500);
    assert.equal(parseAccountCreate({ ...base, opening_date: '2026-10-16' }, NOW).openingDate, '2026-10-16');
    for (const bad of [
      { ...base, opening_date: '2026-10-17' }, { ...base, kind: 'kredi' }, { ...base, name: '   ' }, { ...base, name: 'x'.repeat(61) }, { ...base, opening_balance_minor: 1.5 },
      { ...base, opening_balance_minor: '100' }, { ...base, opening_balance_minor: MAX_ACCOUNT_AMOUNT + 1 }, { ...base, idempotency_key: undefined }, { ...base, opening_date: '2026-02-30' }, { ...base, note: 'x'.repeat(201) },
    ]) throws400(() => parseAccountCreate(bad, NOW), JSON.stringify(bad));
    assert.deepEqual([...ACCOUNT_KINDS], ['cash', 'bank']);
  });

  it('güncelleme: yalnız ad / not / aktiflik / sıra; açılış alanları ve bilinmeyen anahtar reddedilir; boş yama 400; aktiflik yalnız boolean', () => {
    assert.deepEqual(parseAccountPatch({ name: ' Yeni ', is_active: false, sort_order: 3, note: null }), { patch: { name: 'Yeni', note: null, isActive: false, sortOrder: 3 }, fields: ['name', 'note', 'is_active', 'sort_order'] });
    for (const bad of [{}, { opening_balance_minor: 5 }, { kind: 'cash' }, { name: 'a', opening_date: '2026-01-01' }, { is_active: 'false' }, { is_active: 0 }, { sort_order: -1 }, { sort_order: 1.5 }, { sort_order: 10001 }, { name: '' }]) {
      assert.throws(() => parseAccountPatch(bad), (error) => error.statusCode === 400, JSON.stringify(bad));
    }
  });

  it('düzeltme: sıfır tutar reddedilir, nedeni listeden, "other" için not zorunlu, gelecek tarih yok; eksi tutar serbest', () => {
    const ok = parseAdjustment({ amount_minor: -2500, reason_code: 'bank_fee', movement_date: '2026-10-10', idempotency_key: KEY }, NOW);
    assert.deepEqual(ok, { amountMinor: -2500, reasonCode: 'bank_fee', note: null, movementDate: '2026-10-10', idempotencyKey: KEY });
    assert.equal(parseAdjustment({ amount_minor: 10, reason_code: 'other', note: 'açıklama', movement_date: '2026-10-10', idempotency_key: KEY }, NOW).note, 'açıklama');
    for (const bad of [
      { amount_minor: 0, reason_code: 'bank_fee' }, { amount_minor: 10, reason_code: 'diger' }, { amount_minor: 10, reason_code: 'other' }, { amount_minor: 10, reason_code: 'bank_fee', movement_date: '2026-10-17' },
      { amount_minor: 10, reason_code: 'bank_fee', movement_date: '2026-10-10' }, { amount_minor: '10', reason_code: 'bank_fee', movement_date: '2026-10-10', idempotency_key: KEY },
    ]) throws400(() => parseAdjustment(bad, NOW), JSON.stringify(bad));
    assert.deepEqual([...ADJUSTMENT_REASONS], ['bank_fee', 'bank_interest', 'cash_count', 'other']);
  });

  it('aktarım: iki farklı hesap, tutar > 0, gelecek tarih yok; iptal gövdesi neden + anahtar zorunlu', () => {
    const ok = parseTransfer({ from_account_id: 1, to_account_id: 2, amount_minor: 5000, transfer_date: '2026-10-16', description: ' kasadan bankaya ', idempotency_key: KEY }, NOW);
    assert.deepEqual(ok, { fromId: 1, toId: 2, amountMinor: 5000, transferDate: '2026-10-16', description: 'kasadan bankaya', idempotencyKey: KEY });
    const valid = { from_account_id: 1, to_account_id: 2, amount_minor: 5000, transfer_date: '2026-10-16', idempotency_key: KEY };
    for (const change of [{ to_account_id: 1 }, { amount_minor: 0 }, { amount_minor: -5 }, { transfer_date: '2026-10-17' }, { from_account_id: 'a' }, { to_account_id: 0 }, { idempotency_key: 'bosluk iceren' }, { idempotency_key: 'x'.repeat(65) }]) throws400(() => parseTransfer({ ...valid, ...change }, NOW), JSON.stringify(change));
    assert.deepEqual(parseTransferVoid({ reason: ' yanlış hesap ', idempotency_key: KEY }), { reason: 'yanlış hesap', idempotencyKey: KEY });
    throws400(() => parseTransferVoid({ idempotency_key: KEY }), 'neden zorunlu');
  });

  it('toplu eşleme: önizleme yalnız yöntem->hesap; commit için beklenen sayı / toplam / 64 hex özet / anahtar zorunlu; bilinmeyen yöntem reddedilir', () => {
    assert.deepEqual(parseAssignBody({ account_by_method: { cash: 1, transfer: 2 } }, { commit: false }), { accountByMethod: { cash: 1, transfer: 2 } });
    const hash = 'a'.repeat(64);
    const commit = parseAssignBody({ account_by_method: { cash: 1 }, expected_count: 3, expected_total_minor: 900, expected_hash: hash, idempotency_key: KEY }, { commit: true });
    assert.deepEqual(commit, { accountByMethod: { cash: 1 }, expectedCount: 3, expectedTotal: 900, expectedHash: hash, idempotencyKey: KEY });
    for (const bad of [{}, { account_by_method: {} }, { account_by_method: { havale: 1 } }, { account_by_method: { bank_transfer: 2 } }, { account_by_method: { cash: 'x' } }]) throws400(() => parseAssignBody(bad, { commit: false }), JSON.stringify(bad));
    for (const change of [{ expected_count: undefined }, { expected_count: -1 }, { expected_total_minor: -1 }, { expected_hash: 'kisa' }, { expected_hash: 'A'.repeat(64) }, { idempotency_key: undefined }]) {
      throws400(() => parseAssignBody({ account_by_method: { cash: 1 }, expected_count: 3, expected_total_minor: 900, expected_hash: hash, idempotency_key: KEY, ...change }, { commit: true }), JSON.stringify(change));
    }
  });

  it('mutabakat: ekstre bakiyesi + beklenen hesaplanan bakiye (bayat denetimi) zorunlu; adjust isteğe bağlı ve nedeni listeden', () => {
    const valid = { as_of_date: '2026-10-15', statement_balance_minor: 1000, expected_computed_minor: 900, idempotency_key: KEY };
    const ok = parseReconciliation({ ...valid, adjust: { reason_code: 'bank_fee' } }, NOW);
    assert.deepEqual(ok, { asOf: '2026-10-15', statementMinor: 1000, expectedComputed: 900, note: null, adjust: { reasonCode: 'bank_fee', note: null }, idempotencyKey: KEY });
    assert.equal(parseReconciliation(valid, NOW).adjust, null);
    for (const change of [{ as_of_date: '2026-10-17' }, { statement_balance_minor: 1.2 }, { expected_computed_minor: undefined }, { adjust: { reason_code: 'x' } }, { adjust: { reason_code: 'other' } }, { idempotency_key: undefined }]) {
      throws400(() => parseReconciliation({ ...valid, ...change }, NOW), JSON.stringify(change));
    }
  });

  it('hareket sorgusu: sayfa 50 (üst 200); ters aralık 400', () => {
    assert.deepEqual(parseMovementsQuery({}), { from: null, to: null, limit: 50, beforeId: null });
    assert.equal(parseMovementsQuery({ limit: '1000' }).limit, 200);
    throws400(() => parseMovementsQuery({ from: '2026-05-02', to: '2026-05-01' }), 'ters aralık');
  });
});

describe('gider gövdeleri', () => {
  const base = { category_id: 3, supplier_id: 4, description: ' Asansör   bakımı ', amount_minor: 120000, vat_minor: 20000, expense_date: '2026-10-10', account_id: 2, document_kind: 'invoice', document_no: ' ab-123 ', idempotency_key: KEY };

  it('geçerli gider: açıklama boşluk daraltılır, belge türü varsayılan "none", KDV tutarı geçemez, tutar > 0, tarih bugünü geçemez', () => {
    const ok = parseExpenseInput(base, NOW);
    assert.equal(ok.description, 'Asansör bakımı');
    assert.equal(ok.vatMinor, 20000);
    assert.equal(ok.documentNo, 'ab-123');
    assert.equal(ok.allowDuplicate, false);
    assert.equal(parseExpenseInput({ ...base, document_kind: undefined, vat_minor: undefined, supplier_id: undefined, account_id: undefined }, NOW).documentKind, 'none');
    assert.equal(parseExpenseInput({ ...base, vat_minor: undefined }, NOW).vatMinor, null);
    assert.equal(parseExpenseInput({ ...base, allow_duplicate: true }, NOW).allowDuplicate, true);
    for (const change of [{ category_id: undefined }, { amount_minor: 0 }, { amount_minor: 12.5 }, { vat_minor: 120001 }, { vat_minor: -1 }, { expense_date: '2026-10-17' }, { description: '' }, { document_kind: 'fatura' }, { document_no: 'x'.repeat(41) }, { idempotency_key: undefined }, { allow_duplicate: 'evet' }]) {
      throws400(() => parseExpenseInput({ ...base, ...change }, NOW), JSON.stringify(change));
    }
    assert.deepEqual(DEFAULT_EXPENSE_CATEGORIES.length, 12);
    assert.equal(new Set(DEFAULT_EXPENSE_CATEGORIES).size, 12);
  });

  it('belge numarası normalizasyonu: Türkçe katlama, küçük harf, yalnız harf/rakam; boş -> null (tedarikçi + belge no tekilliği boşta uygulanmaz)', () => {
    assert.equal(normalizeDocumentNo('AB-123/İ'), 'ab123i');
    assert.equal(normalizeDocumentNo(' FAT 2026 / Şç '), 'fat2026sc');
    assert.equal(normalizeDocumentNo('---'), null);
    assert.equal(normalizeDocumentNo(''), null);
    assert.equal(normalizeDocumentNo(null), null);
  });

  it('parmak izi: tutar / hesap / belge değişince değişir; anahtar ve allowDuplicate değişince DEĞİŞMEZ (yeniden oynatma)', () => {
    const input = parseExpenseInput(base, NOW);
    const same = parseExpenseInput({ ...base, idempotency_key: 'baska-anahtar-1', allow_duplicate: true }, NOW);
    assert.equal(expenseFingerprint(same), expenseFingerprint(input));
    for (const change of [{ amount_minor: 120001 }, { account_id: 9 }, { category_id: 9 }, { document_no: 'ab-124' }, { description: 'Başka' }, { expense_date: '2026-10-09' }]) {
      assert.notEqual(expenseFingerprint(parseExpenseInput({ ...base, ...change }, NOW)), expenseFingerprint(input), JSON.stringify(change));
    }
  });

  it('iptal gövdesi, kategori ve tedarikçi gövdeleri', () => {
    assert.deepEqual(parseVoidInput({ reason: ' yanlış girildi ', idempotency_key: KEY }), { reason: 'yanlış girildi', idempotencyKey: KEY });
    throws400(() => parseVoidInput({ idempotency_key: KEY }), 'neden zorunlu');
    assert.deepEqual(parseCategoryBody({ name: ' Boya ' }, { create: true }), { name: 'Boya' });
    throws400(() => parseCategoryBody({}, { create: true }), 'ad zorunlu');
    assert.deepEqual(parseCategoryBody({ is_active: false, sort_order: 4 }, { create: false }), { isActive: false, sortOrder: 4 });
    throws400(() => parseCategoryBody({}, { create: false }), 'boş yama');
    throws400(() => parseCategoryBody({ is_active: 'x' }, { create: false }), 'boolean olmayan');
  });

  it('tedarikçi sorgusu ve kurul sansürü: vergi no / telefon / not null; ad kalır', () => {
    assert.deepEqual(parseSuppliersQuery({}), { q: null, active: null, limit: 50, offset: 0 });
    assert.equal(parseSuppliersQuery({ active: 'true', q: '  asansör ' }).q, 'asansör');
    throwsCode(() => parseSuppliersQuery({ active: 'belki' }), 'INVALID_QUERY');
    const redacted = redactSupplierForBoard({ id: 1, name: 'Asansörcü', tax_id: '1234567890', phone: '5551112233', note: 'özel', is_active: true });
    assert.deepEqual(redacted, { id: 1, name: 'Asansörcü', tax_id: null, phone: null, note: null, is_active: true });
  });

  it('gider listesi süzgeci: parametreli SQL, değer metne gömülmez; q dört alanda katlanmış LIKE ve ESCAPE; durum iptal bağlantısına göre', () => {
    const filters = parseExpensesQuery({ from: '2026-01-01', to: '2026-12-31', category_id: '3', supplier_id: '4', account_id: '5', status: 'voided', q: "100%_'; DROP", limit: '10', before_id: '99' });
    assert.equal(filters.limit, 10);
    const { params, clauses } = expenseFilterSql(filters, [1000000001]);
    const sql = clauses.join(' AND ');
    assert.equal(params[0], 1000000001);
    assert.ok(params.includes('2026-01-01') && params.includes('2026-12-31') && params.includes(3) && params.includes(4) && params.includes(5));
    assert.ok(params.some((value) => typeof value === 'string' && value.includes('\\%') && value.includes('\\_')), 'LIKE joker kaçışı');
    assert.equal(/DROP|100%|2026-01-01/.test(sql), false, 'değerler SQL metnine girmez');
    assert.match(sql, /v\.expense_id IS NOT NULL/);
    assert.equal((sql.match(/ESCAPE/g) ?? []).length, 4);
    assert.equal(expenseFilterSql(parseExpensesQuery({ status: 'active' })).clauses.join(' '), 'v.expense_id IS NULL');
    assert.deepEqual(expenseFilterSql(parseExpensesQuery({})).clauses, []);
    throws400(() => parseExpensesQuery({ from: '2026-05-02', to: '2026-05-01' }), 'ters aralık');
    throwsCode(() => parseExpensesQuery({ status: 'iptal' }), 'INVALID_QUERY');
  });

  it('mapExpenseRow: iptal bilgisi + düzeltme bağlantısı + belge sayısı; tutarlar sayıya', () => {
    const row = { id: '7', category_id: '3', category_name: 'Su', supplier_id: null, supplier_name: null, description: 'Su faturası', amount_minor: '50000', vat_minor: null, expense_date: '2026-10-01', account_id: '2', account_name: 'Kasa', document_kind: 'none', document_no: null, voided_at: null, corrects_expense_id: '5', documents_count: '2', created_by_name: 'Yönetici', created_at: new Date('2026-10-01T10:00:00Z') };
    const mapped = mapExpenseRow(row);
    assert.deepEqual([mapped.id, mapped.amount_minor, mapped.vat_minor, mapped.voided, mapped.corrects_expense_id, mapped.documents_count, mapped.account], [7, 50000, null, null, 5, 2, { id: 2, name: 'Kasa' }]);
    assert.deepEqual(mapExpenseRow({ ...row, voided_at: new Date('2026-10-02T10:00:00Z'), void_reason: 'hata', void_period: '2026-10-01' }).voided, { at: '2026-10-02T10:00:00.000Z', reason: 'hata', period: '2026-10-01' });
  });
});

describe('belge adaptörü (A4 ad temizliği, A8 başlıkları, dikiş yokluğu)', () => {
  afterEach(() => setDocumentSeamForTests(undefined));

  it('dosya adı: yol parçaları atılır, kontrol / yön karakterleri silinir, yasak karakterler _ olur, çift uzantı kapanır, ayrılmış ad korunur, uzantı kanonikleşir', () => {
    assert.deepEqual(sanitizeDocumentName('C:\\Users\\x\\Fatura Ocak.PDF'), { displayName: 'Fatura Ocak.pdf', declaredMime: 'application/pdf' });
    assert.deepEqual(sanitizeDocumentName('../../etc/passwd.png'), { displayName: 'passwd.png', declaredMime: 'image/png' });
    assert.equal(sanitizeDocumentName('foto.JPEG').displayName, 'foto.jpg');
    assert.equal(sanitizeDocumentName('a.b.c.pdf').displayName, 'a_b_c.pdf');
    assert.equal(sanitizeDocumentName('fa\u202etura\u0000.pdf').displayName, 'fatura.pdf');
    assert.equal(sanitizeDocumentName('a<b>:"c|d?*.pdf').displayName, 'a_b___c_d__.pdf');
    assert.equal(sanitizeDocumentName('con.pdf').displayName, '_con.pdf');
    assert.equal(sanitizeDocumentName('.pdf').displayName, '_pdf');
    assert.deepEqual(sanitizeDocumentName('makbuz'), { displayName: 'makbuz', declaredMime: null });
    assert.equal(sanitizeDocumentName('   .pdf  ').displayName, '_pdf');
    assert.ok(Array.from(sanitizeDocumentName(`${'ş'.repeat(300)}.pdf`).displayName).length <= 120);
    for (const bad of ['virus.exe', 'sayfa.html', 'arsiv.zip', 'tablo.xlsx', 'a.pdf.exe']) {
      assert.throws(() => sanitizeDocumentName(bad), (error) => error.statusCode === 415 && error.code === 'DOCUMENT_TYPE_NOT_ALLOWED', bad);
    }
    throws400(() => sanitizeDocumentName(42), 'metin değil');
  });

  it('indirme başlıkları: attachment (inline asla), nosniff, sandbox CSP, no-store; ASCII yedek adında tırnak / noktalı virgül yok; filename* UTF-8', () => {
    const headers = downloadHeaders({ mimeType: 'application/pdf', sizeBytes: 1234, displayName: 'Şirket "Fatura"; ağustos.pdf' });
    assert.match(headers['Content-Disposition'], /^attachment; filename="[\x20-\x7e]*"; filename\*=UTF-8''/);
    assert.equal(headers['Content-Disposition'].includes('inline'), false);
    assert.equal(/filename="[^"]*[;\\][^"]*"/.test(headers['Content-Disposition']), false);
    assert.ok(headers['Content-Disposition'].includes(encodeURIComponent('Şirket "Fatura"; ağustos.pdf').replace(/'/g, '%27')) || headers['Content-Disposition'].includes("%C5%9Eirket"));
    assert.equal(headers['X-Content-Type-Options'], 'nosniff');
    assert.match(headers['Content-Security-Policy'], /sandbox/);
    assert.match(headers['Cache-Control'], /no-store/);
    assert.equal(headers['Content-Length'], '1234');
  });

  it('dikiş yoksa (null): requireDocumentSeam 409 DOCUMENTS_NOT_AVAILABLE; sahte dikiş yüklenir; streamOf iki biçimi de kabul eder, başkasını reddeder', async () => {
    setDocumentSeamForTests(null);
    assert.equal(await loadDocumentSeam(), null);
    await assert.rejects(() => requireDocumentSeam(), (error) => error.statusCode === 409 && error.code === 'DOCUMENTS_NOT_AVAILABLE');
    const seam = { maxFileBytes: 2_000_000 };
    setDocumentSeamForTests(seam);
    assert.equal(await requireDocumentSeam(), seam);
    const readable = Readable.from(['x']);
    assert.equal(streamOf(readable), readable);
    assert.equal(streamOf({ stream: readable }), readable);
    assert.throws(() => streamOf({}));
    assert.throws(() => streamOf(null));
  });

  it('gerçek modül (S-3b) henüz storeUpload / openDownload / removeFile sunmuyorsa dikiş null kalır (güvenli: ek uçları kapalı)', async () => {
    setDocumentSeamForTests(undefined);
    const seam = await loadDocumentSeam();
    if (seam !== null) {
      for (const name of ['storeUpload', 'openDownload', 'removeFile']) assert.equal(typeof seam[name], 'function', name);
    }
  });

  it('boyut sınırları: dikiş değeri üst sınırı (25 MiB) geçemez; ortam değeri geçerliyse kullanılır; kota varsayılanı 200 MiB', () => {
    assert.equal(maxFileBytes(null, {}), 10485760);
    assert.equal(maxFileBytes({ maxFileBytes: 5_000_000 }, {}), 5_000_000);
    assert.equal(maxFileBytes({ maxFileBytes: 900_000_000 }, {}), 26214400);
    assert.equal(maxFileBytes(null, { DOCUMENTS_MAX_FILE_BYTES: '3000000' }), 3_000_000);
    assert.equal(maxFileBytes(null, { DOCUMENTS_MAX_FILE_BYTES: '900000000' }), 10485760);
    assert.equal(maxFileBytes(null, { DOCUMENTS_MAX_FILE_BYTES: 'x' }), 10485760);
    assert.equal(siteQuotaBytes({}), 209715200);
    assert.equal(siteQuotaBytes({ DOCUMENTS_SITE_QUOTA_BYTES: '1000' }), 1000);
    assert.match(reserveStorageKey(1000000001), STORAGE_KEY_PATTERN);
    assert.match(reserveStorageKey(7), STORAGE_KEY_PATTERN);
  });

  it('belge oluşturma gövdesi: boyut tamsayı > 0 ve sınır altında, tür listeden, anahtar zorunlu; uzantısız ad için PDF varsayılır', () => {
    const ok = parseDocumentCreate({ file: { name: 'Fatura.pdf', size: 2048, content_type: 'application/pdf' }, kind: 'invoice', idempotency_key: KEY }, null);
    assert.deepEqual(ok, { displayName: 'Fatura.pdf', mime: 'application/pdf', size: 2048, kind: 'invoice', idempotencyKey: KEY });
    assert.equal(parseDocumentCreate({ file: { name: 'foto', size: 10, content_type: 'image/png' }, kind: 'photo', idempotency_key: KEY }, null).mime, 'image/png');
    assert.equal(parseDocumentCreate({ file: { name: 'foto', size: 10 }, kind: 'photo', idempotency_key: KEY }, null).mime, 'application/pdf');
    for (const bad of [
      { file: { name: 'a.pdf', size: 0 }, kind: 'invoice', idempotency_key: KEY }, { file: { name: 'a.pdf', size: 1.5 }, kind: 'invoice', idempotency_key: KEY }, { file: { name: 'a.pdf', size: 10 }, kind: 'x', idempotency_key: KEY },
      { file: { name: 'a.pdf', size: 10 }, kind: 'invoice' }, { kind: 'invoice', idempotency_key: KEY },
    ]) throws400(() => parseDocumentCreate(bad, null), JSON.stringify(bad));
    assert.throws(() => parseDocumentCreate({ file: { name: 'a.pdf', size: 10485761 }, kind: 'invoice', idempotency_key: KEY }, null), (error) => error.statusCode === 413 && error.code === 'DOCUMENT_TOO_LARGE');
  });
});
