// Finans Faz 4b makbuz (saf + sahte DB): numara biçimi, doğrulama kodu (HMAC), snapshot değişmezliği, sakin görünümü, ayrıştırıcılar, doğrulama ucu.
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import {
  RECEIPT_REASON_CODES,
  RECEIPT_TEMPLATE,
  buildSnapshot,
  codesMatch,
  formatReceiptNumber,
  mapReceipt,
  mapReceiptForResident,
  mapReceiptSummary,
  parseCancelBody,
  parseReceiptNumber,
  parseReceiptsQuery,
  parseVerifyBody,
  receiptRef,
  receiptSecret,
  relationForPayer,
  snapshotHash,
  verificationCodeFor,
  verifyReceipt,
} from '../src/modules/finance_receipts.js';

const throwsCode = (fn, code) => assert.throws(fn, (error) => error.code === code, code);

const ROW = (over = {}) => ({
  id: '5', receipt_year: 2026, receipt_no: 17, kind: 'collection', ledger_entry_id: '90', cancels_receipt_id: null, apartment_id: '12', amount_minor: '125000',
  paid_on: '2026-10-10', issued_on: '2026-10-10', issued_at: new Date('2026-10-10T08:00:00Z'), snapshot: buildSnapshot({
    number: 'MK-2026-000017', kind: 'collection', issuedOn: '2026-10-10', paidOn: '2026-10-10', amountMinor: 125000, method: 'cash', siteName: 'Gül Sitesi', apartmentLabel: 'A Blok 5', payerParty: 'owner', payerName: 'Ali Veli', issuerName: 'Yönetici', verificationCode: 'ABCDEF123456',
  }), verification_code: 'ABCDEF123456', template_version: 1, cancel_reason_code: null, cancel_note: null, issued_by_name: 'Yönetici', cancelled_by_id: null, cancelled_by_year: null,
  cancelled_by_no: null, target_year: null, target_no: null, copy_count: 2, ...over,
});

describe('numara biçimi', () => {
  it('MK-YYYY-NNNNNN gidiş-dönüş; geçersiz biçimler null; küçük harf ve boşluk kabul', () => {
    assert.equal(formatReceiptNumber(2026, 1), 'MK-2026-000001');
    assert.equal(formatReceiptNumber(2026, 123456), 'MK-2026-123456');
    assert.deepEqual(parseReceiptNumber('MK-2026-000123'), { year: 2026, no: 123 });
    assert.deepEqual(parseReceiptNumber(' mk-2026-000123 '), { year: 2026, no: 123 });
    for (const bad of ['MK-2026-0', 'MK-26-000001', 'XX-2026-000001', 'MK-2026-000000', 'MK-1999-000001', 'MK-2101-000001', 12, null, undefined, '', 'MK-2026-1234567']) assert.equal(parseReceiptNumber(bad), null, String(bad));
  });
});

describe('doğrulama kodu (HMAC-SHA256, ilk 12, büyük harf/rakam)', () => {
  const secret = 'x'.repeat(20);
  const base = { siteCode: 1000000001, year: 2026, no: 17, amountMinor: 125000, paidOn: '2026-10-10' };

  it('kararlı, 12 karakter, yalnız [0-9A-F]; her girdi değişince değişir', () => {
    const code = verificationCodeFor(secret, base);
    assert.match(code, /^[0-9A-F]{12}$/);
    assert.equal(verificationCodeFor(secret, { ...base }), code);
    for (const change of [{ siteCode: 1000000002 }, { year: 2027 }, { no: 18 }, { amountMinor: 125001 }, { paidOn: '2026-10-11' }]) assert.notEqual(verificationCodeFor(secret, { ...base, ...change }), code);
    assert.notEqual(verificationCodeFor('y'.repeat(20), base), code);
  });

  it('codesMatch: büyük/küçük harf ve boşluktan bağımsız; uzunluk ya da içerik farkı reddedilir; boş asla eşleşmez', () => {
    const code = verificationCodeFor(secret, base);
    assert.equal(codesMatch(code, code.toLowerCase()), true);
    assert.equal(codesMatch(code, ` ${code} `), true);
    assert.equal(codesMatch(code, code.slice(1)), false);
    assert.equal(codesMatch(code, `${code.slice(0, 11)}${code[11] === 'A' ? 'B' : 'A'}`), false);
    assert.equal(codesMatch('', ''), false);
    assert.equal(codesMatch(null, undefined), false);
  });

  it('receiptSecret: doğrudan sır >= 16; kısa sır yok sayılır ve JWT_SECRET\'tan türetilir (ham JWT sırrı DEĞİL); hiçbiri yoksa null', () => {
    assert.equal(receiptSecret({ FINANCE_RECEIPT_SECRET: 'a'.repeat(16) }), 'a'.repeat(16));
    const derived = receiptSecret({ FINANCE_RECEIPT_SECRET: 'kisa', JWT_SECRET: 'jwt-sirrim' });
    assert.match(derived, /^[0-9a-f]{64}$/);
    assert.notEqual(derived, 'jwt-sirrim');
    assert.equal(receiptSecret({ JWT_SECRET: 'jwt-sirrim' }), derived);
    assert.notEqual(receiptSecret({ JWT_SECRET: 'baska' }), derived);
    assert.equal(receiptSecret({}), null);
    assert.equal(receiptSecret({ FINANCE_RECEIPT_SECRET: '   ', JWT_SECRET: '' }), null);
  });
});

describe('snapshot', () => {
  it('v1 alanları; kişisel veri (TCKN, telefon, e-posta, adres, bakiye) YOK; sürüm şablonla tutarlı', () => {
    const snapshot = ROW().snapshot;
    assert.deepEqual(Object.keys(snapshot).sort(), ['amount_minor', 'apartment', 'cekince', 'currency', 'cancels_number', 'issued_on', 'issuer', 'kind', 'mahsup', 'method', 'number', 'paid_on', 'payer', 'site', 'template_version', 'v', 'verification_code'].sort());
    assert.equal(snapshot.currency, 'TRY');
    assert.equal(snapshot.template_version, RECEIPT_TEMPLATE.version);
    assert.equal(snapshot.mahsup, 'oldest_due_first');
    assert.equal(snapshot.cekince, true);
    assert.equal(snapshot.cancels_number, null);
    assert.equal(/tckn|phone|telefon|email|e-posta|address|adres|balance|bakiye/i.test(JSON.stringify(snapshot)), false);
  });

  it('snapshotHash: anahtar sırasından bağımsız, bir alan değişince değişir; sha256 hex', () => {
    const snapshot = ROW().snapshot;
    const reordered = Object.fromEntries(Object.entries(snapshot).reverse());
    assert.equal(snapshotHash(reordered), snapshotHash(snapshot));
    assert.match(snapshotHash(snapshot), /^[0-9a-f]{64}$/);
    assert.notEqual(snapshotHash({ ...snapshot, amount_minor: snapshot.amount_minor + 1 }), snapshotHash(snapshot));
    assert.notEqual(snapshotHash({ ...snapshot, payer: { party: 'owner', name: 'Başka' } }), snapshotHash(snapshot));
  });

  it('relationForPayer: kiracı -> tenant; malik ve ikisi birden -> owner', () => {
    assert.equal(relationForPayer('tenant'), 'tenant');
    assert.equal(relationForPayer('owner'), 'owner');
    assert.equal(relationForPayer('both'), 'owner');
  });

  it('şablon taslak ve üç sabit metin dolu (avukat onayına açık)', () => {
    assert.equal(RECEIPT_TEMPLATE.draft, true);
    for (const key of ['mahsup_text', 'cekince_text', 'disclaimer_text']) assert.ok(RECEIPT_TEMPLATE[key].length > 30, key);
    assert.deepEqual([...RECEIPT_REASON_CODES], ['payment_reversed', 'payment_corrected', 'issued_in_error']);
  });
});

describe('eşlemeler', () => {
  it('liste özeti: durum yalnız tahsilat için (active/cancelled); iptal makbuzunda null; tutar sayıya', () => {
    // İP-1A: account_party (tahsilatın hesabı; SELECT'te yoksa null) eklemeli alandır
    assert.deepEqual(mapReceiptSummary(ROW()), { id: 5, number: 'MK-2026-000017', kind: 'collection', status: 'active', paid_on: '2026-10-10', issued_on: '2026-10-10', amount_minor: 125000, apartment: { id: 12, label: 'A Blok 5' }, payer_name: 'Ali Veli', account_party: null });
    assert.equal(mapReceiptSummary(ROW({ account_party: 'tenant' })).account_party, 'tenant');
    assert.equal(mapReceiptSummary(ROW({ cancelled_by_id: '6', cancelled_by_year: 2026, cancelled_by_no: 18 })).status, 'cancelled');
    assert.equal(mapReceiptSummary(ROW({ kind: 'cancellation' })).status, null);
  });

  it('tam makbuz: iptal bağlantıları numara olarak, şablon ve kopya sayısı; sakin görünümünden iç alanlar çıkar ama neden KODU kalır', () => {
    const full = mapReceipt(ROW({ cancelled_by_id: '6', cancelled_by_year: 2026, cancelled_by_no: 18, cancel_reason_code: 'issued_in_error', cancel_note: 'dahili not' }));
    assert.equal(full.cancelled_by_number, 'MK-2026-000018');
    assert.equal(full.cancels_number, null);
    assert.equal(full.copy_count, 2);
    assert.equal(full.template, RECEIPT_TEMPLATE);
    assert.equal(full.ledger_entry_id, 90);
    const resident = mapReceiptForResident(ROW({ cancel_reason_code: 'issued_in_error', cancel_note: 'dahili not' }));
    for (const hidden of ['ledger_entry_id', 'copy_count', 'cancel_note', 'issued_by_name']) assert.equal(Object.hasOwn(resident, hidden), false, hidden);
    assert.equal(resident.cancel_reason_code, 'issued_in_error');
    assert.equal(resident.verification_code, 'ABCDEF123456');
    const cancellation = mapReceipt(ROW({ kind: 'cancellation', target_year: 2026, target_no: 17 }));
    assert.equal(cancellation.cancels_number, 'MK-2026-000017');
    assert.deepEqual(receiptRef(ROW()), { id: 5, number: 'MK-2026-000017' });
    assert.equal(receiptRef(null), null);
  });
});

describe('ayrıştırıcılar', () => {
  it('iptal gövdesi: yalnız issued_in_error; anahtar zorunlu; not 200 karakteri geçemez', () => {
    const ok = parseCancelBody({ reason_code: 'issued_in_error', note: ' hatalı ', idempotency_key: 'iptal-anahtar-1' });
    assert.equal(ok.reasonCode, 'issued_in_error');
    assert.equal(ok.note, 'hatalı');
    assert.equal(ok.idempotencyKey, 'iptal-anahtar-1');
    for (const bad of [{}, { reason_code: 'payment_reversed', idempotency_key: 'iptal-anahtar-1' }, { reason_code: 'issued_in_error' }, { reason_code: 'issued_in_error', idempotency_key: 'iptal-anahtar-1', note: 'x'.repeat(201) }, null, []]) {
      assert.throws(() => parseCancelBody(bad), (error) => error.statusCode === 400, JSON.stringify(bad));
    }
  });

  it('doğrulama gövdesi: numara ve 12 karakterlik kod; uydurma alanlar yok sayılır', () => {
    assert.deepEqual(parseVerifyBody({ number: 'MK-2026-000017', code: ' abcdef123456 ', extra: 1 }), { year: 2026, no: 17, code: 'abcdef123456' });
    for (const bad of [{ number: 'MK-2026-000017' }, { number: 'x', code: 'ABCDEF123456' }, { number: 'MK-2026-000017', code: 'KISA' }, { number: 'MK-2026-000017', code: 'ABCDEF12345!' }, { number: 'MK-2026-000017', code: 123456789012 }]) {
      throwsCode(() => parseVerifyBody(bad), 'INVALID_BODY');
    }
  });

  it('liste sorgusu: varsayılan limit 50, üst sınır 200; geçersiz tür / yıl 400; arama 60 karaktere kırpılır', () => {
    assert.deepEqual(parseReceiptsQuery({}), { apartmentId: null, year: null, kind: null, q: null, limit: 50, beforeId: null });
    const parsed = parseReceiptsQuery({ apartment_id: '4', year: '2026', kind: 'cancellation', q: ` ${'a'.repeat(100)} `, limit: '9999', before_id: '77' });
    assert.equal(parsed.limit, 200);
    assert.equal(parsed.q.length, 60);
    assert.equal(parsed.apartmentId, 4);
    assert.equal(parsed.beforeId, 77);
    throwsCode(() => parseReceiptsQuery({ kind: 'x' }), 'INVALID_QUERY');
    throwsCode(() => parseReceiptsQuery({ year: '1900' }), 'INVALID_QUERY');
  });
});

describe('verifyReceipt (sahte DB)', () => {
  const dbWith = (row) => ({ calls: [], async query(sql, params) { this.calls.push({ sql, params }); return { rows: row ? [row] : [] }; } });

  it('doğru kod -> valid + durum; yanlış kod / kayıt yok -> aynı yanıt (valid false, ayrıntı sızmaz); hiçbir şey yazmaz', async () => {
    const db = dbWith(ROW());
    assert.deepEqual(await verifyReceipt({ siteCode: 1, body: { number: 'MK-2026-000017', code: 'abcdef123456' }, db }), { valid: true, status: 'active', number: 'MK-2026-000017', amount_minor: 125000, paid_on: '2026-10-10', issued_on: '2026-10-10', apartment_label: 'A Blok 5' });
    assert.deepEqual(await verifyReceipt({ siteCode: 1, body: { number: 'MK-2026-000017', code: 'ABCDEF123457' }, db }), { valid: false, status: null });
    assert.deepEqual(await verifyReceipt({ siteCode: 1, body: { number: 'MK-2026-000099', code: 'ABCDEF123456' }, db: dbWith(null) }), { valid: false, status: null });
    assert.deepEqual(await verifyReceipt({ siteCode: 1, body: { number: 'MK-2026-000017', code: 'ABCDEF123456' }, db: dbWith(ROW({ kind: 'cancellation' })) }).then((r) => [r.valid, r.status]), [true, 'cancellation']);
    assert.deepEqual(await verifyReceipt({ siteCode: 1, body: { number: 'MK-2026-000017', code: 'ABCDEF123456' }, db: dbWith(ROW({ cancelled_by_id: '6' })) }).then((r) => [r.valid, r.status]), [true, 'cancelled']);
    assert.ok(db.calls.every((call) => /^\s*SELECT/.test(call.sql)), 'yalnız okuma');
    assert.ok(db.calls.every((call) => call.params[0] === 1), 'site kapsamı');
  });
});
