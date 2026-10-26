// Kasa servisi (DB'siz, KATI sahte veritabanı): kasa özeti hesabı (summarizeBook), sorgu / gövde doğrulama, aktarım yazma ve ters aktarım akışı (kilit sırası, tekrar, çakışma, hata kodları),
// denetim kaydında kişi verisi / neden metni yok. Gerçek PostgreSQL: scripts/qa_finance_funds_section.mjs (qa_platform_pg.mjs "funds").
import { describe, it, beforeEach, afterEach, mock } from 'node:test';
import assert from 'node:assert/strict';

process.env.JWT_SECRET ||= 'test-secret-test-secret-test-secret-123456';

const { pool } = await import('../src/db.js');
const service = await import('../src/modules/finance_funds_service.js');
const { summarizeBook, parseFundsQuery, parseMovementsQuery, parseFundTransfer, parseFundTransferReverse, parseTransfersListQuery, mapFundTransfer, createFundTransfer, reverseFundTransfer, listFundTransfers } = service;

const NOW = new Date('2026-10-26T09:00:00Z');
const SITE = 1000000001;
const ACTOR = { user_code: 20001, role: 'site_manager', full_name: 'Ayşe Yönetici' };
const norm = (text) => String(text).replace(/\s+/g, ' ').trim();
const ok = (rows = [], rowCount = rows.length) => ({ rows, rowCount });
const expectCode = (fn, code, status) => assert.throws(fn, (error) => error.code === code && (status === undefined || error.statusCode === status), code);

// --- saf: kasa özeti ------------------------------------------------------------------------------------------------------------------------------

const ev = (fund, type, date, amount, extra = {}) => ({ fund, type, date, amount: BigInt(amount), refId: extra.refId ?? 1, label: null, ...extra });
const bookOf = (events, { movements = [], payments = [], paid = new Map() } = {}) => ({
  events,
  movementTotals: movements.map(([date, amount]) => ({ date, amount: BigInt(amount) })),
  mappedPayments: payments.map(([id, date, amount]) => ({ id, date, amount: BigInt(amount), apartmentId: 1 })),
  paidByPayment: paid,
});

describe('summarizeBook: kasa bakiyesi = açılış + tahsilat - gider ± aktarım (+ düzeltme)', () => {
  const events = [
    ev('operating', 'opening', '2026-08-01', 1_000_000),
    ev('operating', 'collection', '2026-10-01', 200_000, { refId: 5 }),
    ev('capital', 'collection', '2026-10-01', 50_000, { refId: 5 }),
    ev('operating', 'expense', '2026-10-05', -40_000),
    ev('capital', 'expense', '2026-10-06', -30_000),
    ev('operating', 'transfer_out', '2026-10-10', -60_000, { refId: 3 }),
    ev('capital', 'transfer_in', '2026-10-10', 60_000, { refId: 3 }),
    ev('operating', 'adjustment', '2026-10-11', -1_500),
  ];
  const book = bookOf(events, {
    movements: [['2026-08-01', 1_000_000], ['2026-10-01', 260_000], ['2026-10-05', -40_000], ['2026-10-06', -30_000], ['2026-10-11', -1_500]],
    payments: [[5, '2026-10-01', 260_000]],
    paid: new Map([[5, [{ date: '2026-10-01', amount: 250_000n }]]]),
  });

  it('tüm tarihler: açılış yalnız açılış hareketleri, kalemler ayrı, bakiye hepsinin toplamı; avans = eşlenmiş tahsilatın dağıtılmamış kısmı', () => {
    const s = summarizeBook(book, { from: null, to: '2026-10-26' });
    assert.equal(s.funds.operating.opening, 1_000_000n);
    assert.equal(s.funds.operating.collections, 200_000n);
    assert.equal(s.funds.operating.expenses, 40_000n);
    assert.equal(s.funds.operating.transfersOut, 60_000n);
    assert.equal(s.funds.operating.adjustments, -1_500n);
    assert.equal(s.balanceOf(s.funds.operating), 1_000_000n + 200_000n - 40_000n - 60_000n - 1_500n);
    assert.equal(s.balanceOf(s.funds.capital), 50_000n - 30_000n + 60_000n);
    assert.equal(s.advance, 10_000n);
    assert.equal(s.accountsTotal, 1_000_000n + 260_000n - 40_000n - 30_000n - 1_500n);
    // değişmez: iki kasa + avans = hesapların toplamı
    assert.equal(s.balanceOf(s.funds.operating) + s.balanceOf(s.funds.capital) + s.advance, s.accountsTotal);
  });

  it('from verilirse: öncesindeki her şey açılışa girer; aralık içi akışlar ayrı; bakiye değişmez', () => {
    const all = summarizeBook(book, { from: null, to: '2026-10-26' });
    const ranged = summarizeBook(book, { from: '2026-10-05', to: '2026-10-26' });
    assert.equal(ranged.funds.operating.opening, 1_000_000n + 200_000n, 'açılış + 1 Ekim tahsilatı');
    assert.equal(ranged.funds.operating.collections, 0n);
    assert.equal(ranged.funds.operating.expenses, 40_000n);
    assert.equal(ranged.funds.capital.opening, 50_000n);
    assert.equal(ranged.balanceOf(ranged.funds.operating), all.balanceOf(all.funds.operating));
    assert.equal(ranged.balanceOf(ranged.funds.capital), all.balanceOf(all.funds.capital));
  });

  it('to geçmişte: sonraki olaylar sayılmaz; to tarihinden sonraki tahsilat avans / hesap toplamına girmez', () => {
    const early = summarizeBook(book, { from: null, to: '2026-09-01' });
    assert.equal(early.balanceOf(early.funds.operating), 1_000_000n);
    assert.equal(early.balanceOf(early.funds.capital), 0n);
    assert.equal(early.advance, 0n);
    assert.equal(early.accountsTotal, 1_000_000n);
  });

  it('avans as-of: dağıtım olayı to tarihinden SONRA ise o kısım to tarihinde hâlâ avanstır', () => {
    const later = bookOf([], { payments: [[9, '2026-10-01', 100_000]], paid: new Map([[9, [{ date: '2026-11-01', amount: 100_000n }]]]) });
    assert.equal(summarizeBook(later, { from: null, to: '2026-10-26' }).advance, 100_000n);
    assert.equal(summarizeBook(later, { from: null, to: '2026-11-01' }).advance, 0n);
  });

  it('negatif bakiye mümkündür (engellenmez); boş defter sıfırdır', () => {
    const negative = bookOf([ev('capital', 'expense', '2026-10-01', -5_000)]);
    const s = summarizeBook(negative, { from: null, to: '2026-10-26' });
    assert.equal(s.balanceOf(s.funds.capital), -5_000n);
    const empty = summarizeBook(bookOf([]), { from: null, to: '2026-10-26' });
    assert.equal(empty.balanceOf(empty.funds.operating), 0n);
    assert.equal(empty.advance, 0n);
  });
});

// --- sorgu ve gövde doğrulama -----------------------------------------------------------------------------------------------------------------------

describe('kasa sorguları ve aktarım gövdeleri', () => {
  it('parseFundsQuery: to yoksa bugün; from > to 400 INVALID_QUERY; geçersiz tarih 400', () => {
    assert.deepEqual(parseFundsQuery({}, NOW), { from: null, to: '2026-10-26' });
    assert.deepEqual(parseFundsQuery({ from: '2026-10-01', to: '2026-10-20' }, NOW), { from: '2026-10-01', to: '2026-10-20' });
    expectCode(() => parseFundsQuery({ from: '2026-10-21', to: '2026-10-20' }, NOW), 'INVALID_QUERY', 400);
    expectCode(() => parseFundsQuery({ from: '2026-13-01' }, NOW), 'INVALID_QUERY', 400);
  });

  it('parseMovementsQuery: limit 1..200 (varsayılan 50), offset >= 0', () => {
    assert.deepEqual(parseMovementsQuery({}, NOW), { from: null, to: '2026-10-26', limit: 50, offset: 0 });
    assert.equal(parseMovementsQuery({ limit: '500' }, NOW).limit, 200);
    expectCode(() => parseMovementsQuery({ limit: '0' }, NOW), 'INVALID_QUERY');
    expectCode(() => parseMovementsQuery({ offset: '-1' }, NOW), 'INVALID_QUERY');
  });

  const body = { from_fund: 'operating', to_fund: 'capital', amount_minor: 60_000, transfer_date: '2026-10-20', description: '  Açılış   bölüşümü ', idempotency_key: 'ft-1' };
  it('parseFundTransfer: geçerli gövde temizlenir; kasalar farklı, tutar tamsayı 1..1e12, tarih gelecek olamaz, anahtar zorunlu', () => {
    assert.deepEqual(parseFundTransfer(body, NOW), { fromFund: 'operating', toFund: 'capital', amountMinor: 60_000, transferDate: '2026-10-20', description: 'Açılış bölüşümü', idempotencyKey: 'ft-1' });
    for (const [change, label] of [
      [{ to_fund: 'operating' }, 'aynı kasa'],
      [{ to_fund: 'fon' }, 'geçersiz kasa'],
      [{ from_fund: undefined }, 'kaynak yok'],
      [{ amount_minor: 0 }, 'tutar 0'],
      [{ amount_minor: -5 }, 'negatif tutar'],
      [{ amount_minor: 1.5 }, 'ondalık tutar'],
      [{ amount_minor: 1_000_000_000_001 }, 'tutar üst sınırı'],
      [{ amount_minor: '100' }, 'metin tutar'],
      [{ transfer_date: '2026-10-27' }, 'gelecek tarih'],
      [{ transfer_date: '27.10.2026' }, 'biçim'],
      [{ idempotency_key: undefined }, 'anahtar yok'],
      [{ description: 'x'.repeat(201) }, 'uzun açıklama'],
    ]) {
      expectCode(() => parseFundTransfer({ ...body, ...change }, NOW), 'INVALID_BODY', 400);
      void label;
    }
    assert.equal(parseFundTransfer({ ...body, description: undefined }, NOW).description, null);
  });

  it('parseFundTransferReverse: neden ve anahtar zorunlu; parseTransfersListQuery: tarih aralığı ve imleç', () => {
    assert.deepEqual(parseFundTransferReverse({ reason: ' yanlış ', idempotency_key: 'r-1' }), { reason: 'yanlış', idempotencyKey: 'r-1' });
    expectCode(() => parseFundTransferReverse({ idempotency_key: 'r-1' }), 'INVALID_BODY');
    expectCode(() => parseFundTransferReverse({ reason: 'x' }), 'INVALID_BODY');
    assert.deepEqual(parseTransfersListQuery({ before_id: '9', limit: '10' }), { from: null, to: null, beforeId: 9, limit: 10 });
    expectCode(() => parseTransfersListQuery({ before_id: 'x' }), 'INVALID_QUERY');
    expectCode(() => parseTransfersListQuery({ from: '2026-10-02', to: '2026-10-01' }), 'INVALID_QUERY');
  });

  it('mapFundTransfer: tamsayı kuruş, dönem YYYY-MM, kimlikler sayı, boşlar null', () => {
    const mapped = mapFundTransfer({ id: '4', from_fund: 'operating', to_fund: 'capital', amount_minor: '60000', transfer_date: '2026-10-20', period: '2026-10-01', description: null, reverses_transfer_id: null, reversed_by_transfer_id: '5', reversal_reason: null, created_at: new Date('2026-10-20T09:00:00Z'), created_by_name: 'Ayşe' });
    assert.deepEqual(mapped, {
      id: 4, from_fund: 'operating', to_fund: 'capital', amount_minor: 60000, transfer_date: '2026-10-20', period: '2026-10', description: null, reverses_transfer_id: null, reversed_by_transfer_id: 5,
      reversal_reason: null, created_by_name: 'Ayşe', created_at: '2026-10-20T09:00:00.000Z',
    });
  });
});

// --- aktarım yazma: sahte işlem ------------------------------------------------------------------------------------------------------------------------

let log;
let handlers;

function installFakeDb() {
  const run = async (text, params = []) => {
    const sql = norm(text);
    log.push({ sql, params });
    for (const [pattern, fn] of handlers) {
      if (pattern.test(sql)) return fn(sql, params);
    }
    throw new Error(`BEKLENMEYEN SQL (sahte DB katı): ${sql.slice(0, 160)}`);
  };
  pool.query = run;
  pool.connect = async () => ({ query: run, release() {} });
}

const transferRow = (over = {}) => ({
  id: '41', from_fund: 'operating', to_fund: 'capital', amount_minor: '60000', transfer_date: '2026-10-20', period: '2026-10-01', description: 'Açılış bölüşümü', reverses_transfer_id: null,
  reversed_by_transfer_id: null, reversal_reason: null, created_at: new Date('2026-10-20T09:00:00Z'), request_fingerprint: 'f'.repeat(64), idempotency_key: 'ft-1', created_by_name: 'Ayşe Yönetici', ...over,
});

const flowHandlers = (extra = []) => [
  [/^BEGIN$/, () => ok()],
  [/^COMMIT$/, () => ok()],
  [/^ROLLBACK$/, () => ok()],
  [/^SELECT site_code FROM sites WHERE site_code = \$1 FOR KEY SHARE$/, () => ok([{ site_code: String(SITE) }])],
  [/^SELECT pg_advisory_xact_lock/, () => ok()],
  [/^SELECT enabled FROM site_modules/, () => ok([{ enabled: true }])],
  [/^SELECT user_code FROM users WHERE user_code = \$1 AND deleted_at IS NULL FOR KEY SHARE$/, () => ok([{ user_code: 20001 }])],
  [/^(SAVEPOINT|RELEASE SAVEPOINT|ROLLBACK TO SAVEPOINT)/, () => ok()],
  [/^INSERT INTO audit_log/, () => ok()],
  ...extra,
];

beforeEach(() => {
  log = [];
  installFakeDb();
  mock.method(console, 'error', () => {});
});

afterEach(() => {
  mock.restoreAll();
  delete pool.query;
  delete pool.connect;
});

const BODY = { from_fund: 'operating', to_fund: 'capital', amount_minor: 60_000, transfer_date: '2026-10-20', description: 'Açılış bölüşümü', idempotency_key: 'ft-1' };
const indexOf = (pattern) => log.findIndex((entry) => pattern.test(entry.sql));

describe('createFundTransfer: tek işlem, kilit sırası, tekrar ve çakışma', () => {
  it('sıra: BEGIN -> sites KEY SHARE -> finance_post advisory -> modül -> işlemi yapan kullanıcı -> anahtar araması -> dönem kapalı mı -> INSERT -> audit -> COMMIT; 201 gövdesi', async () => {
    handlers = flowHandlers([
      [/^SELECT .* FROM finance_fund_transfers t .* WHERE t\.site_code = \$1 AND t\.idempotency_key = \$2$/, () => ok()],
      [/^SELECT 1 FROM finance_period_closures WHERE site_code = \$1 AND period >= \$2::DATE LIMIT 1$/, () => ok()],
      [/^INSERT INTO finance_fund_transfers \(/, () => ok([{ id: '41' }])],
      [/^SELECT .* FROM finance_fund_transfers t .* WHERE t\.id = \$1 AND t\.site_code = \$2$/, () => ok([transferRow()])],
    ]);
    const result = await createFundTransfer({ siteCode: SITE, body: BODY, actor: ACTOR, now: NOW });
    assert.equal(result.replayed, false);
    assert.equal(result.transfer.id, 41);
    assert.equal(result.transfer.amount_minor, 60_000);
    const order = ['^BEGIN$', '^SELECT site_code FROM sites', '^SELECT pg_advisory_xact_lock', '^SELECT enabled FROM site_modules', '^SELECT user_code FROM users', 'idempotency_key = \\$2$', 'finance_period_closures', '^INSERT INTO finance_fund_transfers', '^INSERT INTO audit_log', '^COMMIT$'].map((p) => indexOf(new RegExp(p)));
    assert.deepEqual([...order].sort((a, b) => a - b), order, JSON.stringify(order));
    assert.ok(order.every((i) => i >= 0), JSON.stringify(order));
    assert.equal(log[indexOf(/^SELECT pg_advisory_xact_lock/)].params[0], `finance_post:${SITE}`);
    const insert = log[indexOf(/^INSERT INTO finance_fund_transfers/)];
    assert.deepEqual(insert.params.slice(0, 7), [SITE, 'operating', 'capital', '60000', '2026-10-20', '2026-10-01', 'Açılış bölüşümü']);
    assert.equal(insert.params[7], 'ft-1');
    assert.equal(insert.params[8].length, 64, 'parmak izi');
    assert.equal(insert.params[9], 20001);
  });

  it('denetim kaydı: eylem finance.fund_transfer.created; ayrıntıda yalnız kasa adı / tutar / dönem (açıklama, kişi adı, neden YOK)', async () => {
    handlers = flowHandlers([
      [/idempotency_key = \$2$/, () => ok()],
      [/FROM finance_period_closures/, () => ok()],
      [/^INSERT INTO finance_fund_transfers/, () => ok([{ id: '41' }])],
      [/t\.id = \$1 AND t\.site_code = \$2$/, () => ok([transferRow()])],
    ]);
    await createFundTransfer({ siteCode: SITE, body: BODY, actor: ACTOR, now: NOW });
    const audit = log.find((entry) => /^INSERT INTO audit_log/.test(entry.sql));
    assert.equal(audit.params[3], 'finance.fund_transfer.created');
    assert.equal(audit.params[5], 'finance');
    assert.equal(audit.params[6], '41');
    assert.deepEqual(JSON.parse(audit.params[7]), { from_fund: 'operating', to_fund: 'capital', amount_minor: 60000, period: '2026-10' });
    assert.doesNotMatch(audit.params[7], /Açılış|Ayşe|reason|description/);
  });

  it('aynı anahtar + aynı gövde = aynı kayıt (replayed, yazma yok); aynı anahtar + farklı gövde 409 IDEMPOTENCY_CONFLICT', async () => {
    let fingerprint = null;
    handlers = flowHandlers([
      [/idempotency_key = \$2$/, () => ok(fingerprint === null ? [] : [transferRow({ request_fingerprint: fingerprint })])],
      [/FROM finance_period_closures/, () => ok()],
      [/^INSERT INTO finance_fund_transfers/, (_s, params) => {
        fingerprint = params[8];
        return ok([{ id: '41' }]);
      }],
      [/t\.id = \$1 AND t\.site_code = \$2$/, () => ok([transferRow({ request_fingerprint: fingerprint })])],
    ]);
    await createFundTransfer({ siteCode: SITE, body: BODY, actor: ACTOR, now: NOW });
    log.length = 0;
    const again = await createFundTransfer({ siteCode: SITE, body: BODY, actor: ACTOR, now: NOW });
    assert.equal(again.replayed, true);
    assert.equal(log.some((entry) => /^INSERT INTO finance_fund_transfers/.test(entry.sql)), false);
    await assert.rejects(() => createFundTransfer({ siteCode: SITE, body: { ...BODY, amount_minor: 60_001 }, actor: ACTOR, now: NOW }), (error) => error.code === 'IDEMPOTENCY_CONFLICT');
  });

  it('kapalı dönem 409 PERIOD_CLOSED ve hiçbir şey yazılmaz; gövde hatası işlem AÇMADAN 400', async () => {
    handlers = flowHandlers([
      [/idempotency_key = \$2$/, () => ok()],
      [/FROM finance_period_closures/, () => ok([{ x: 1 }])],
    ]);
    await assert.rejects(() => createFundTransfer({ siteCode: SITE, body: BODY, actor: ACTOR, now: NOW }), (error) => error.code === 'PERIOD_CLOSED' && error.statusCode === 409);
    assert.equal(log.some((entry) => /^INSERT INTO finance_fund_transfers/.test(entry.sql)), false);
    assert.equal(log.some((entry) => entry.sql === 'ROLLBACK'), true);
    log.length = 0;
    await assert.rejects(() => createFundTransfer({ siteCode: SITE, body: { ...BODY, to_fund: 'operating' }, actor: ACTOR, now: NOW }), (error) => error.code === 'INVALID_BODY');
    assert.equal(log.length, 0, 'doğrulama hatasında veritabanına hiç gidilmez');
  });
});

describe('reverseFundTransfer: ters aktarım', () => {
  const reverseBody = { reason: 'yanlış kasa', idempotency_key: 'r-1' };
  const reverseFlow = (original, extra = []) =>
    flowHandlers([
      [/t\.id = \$1 AND t\.site_code = \$2$/, (_s, params) => ok(Number(params[0]) === 41 ? [original] : [])],
      [/idempotency_key = \$2$/, () => ok()],
      [/FROM finance_period_closures/, () => ok()],
      ...extra,
    ]);

  it('yönler yer değiştirir, tutar aynı, tarih BUGÜN, dönem açık ay, bağlantı reverses_transfer_id; 201 { transfer, original }', async () => {
    handlers = reverseFlow(transferRow(), [[/^INSERT INTO finance_fund_transfers/, () => ok([{ id: '42' }])]]);
    handlers.unshift([/t\.id = \$1 AND t\.site_code = \$2$/, (_s, params) => ok([Number(params[0]) === 42 ? transferRow({ id: '42', from_fund: 'capital', to_fund: 'operating', reverses_transfer_id: '41', reversal_reason: 'yanlış kasa' }) : transferRow()])]);
    const result = await reverseFundTransfer({ siteCode: SITE, rawId: '41', body: reverseBody, actor: ACTOR, now: NOW });
    assert.equal(result.replayed, false);
    assert.equal(result.transfer.id, 42);
    const insert = log.find((entry) => /^INSERT INTO finance_fund_transfers/.test(entry.sql));
    assert.deepEqual(insert.params.slice(0, 8), [SITE, 'capital', 'operating', '60000', '2026-10-26', '2026-10-01', 41, 'yanlış kasa']);
    const audit = log.find((entry) => /^INSERT INTO audit_log/.test(entry.sql));
    assert.equal(audit.params[3], 'finance.fund_transfer.reversed');
    assert.deepEqual(JSON.parse(audit.params[7]), { reversed_transfer_id: 41, from_fund: 'capital', to_fund: 'operating', amount_minor: 60000, period: '2026-10' });
    assert.doesNotMatch(audit.params[7], /yanlış/);
  });

  it('zaten ters çevrilmiş 409 FUND_TRANSFER_ALREADY_REVERSED; ters aktarımın tersi 409 FUND_TRANSFER_NOT_REVERSIBLE; eşzamanlı tekil ihlali de ALREADY_REVERSED', async () => {
    handlers = reverseFlow(transferRow({ reversed_by_transfer_id: '50' }));
    await assert.rejects(() => reverseFundTransfer({ siteCode: SITE, rawId: '41', body: reverseBody, actor: ACTOR, now: NOW }), (error) => error.code === 'FUND_TRANSFER_ALREADY_REVERSED' && error.statusCode === 409);
    handlers = reverseFlow(transferRow({ reverses_transfer_id: '30' }));
    await assert.rejects(() => reverseFundTransfer({ siteCode: SITE, rawId: '41', body: reverseBody, actor: ACTOR, now: NOW }), (error) => error.code === 'FUND_TRANSFER_NOT_REVERSIBLE' && error.statusCode === 409);
    handlers = reverseFlow(transferRow(), [
      [/^INSERT INTO finance_fund_transfers/, () => {
        throw Object.assign(new Error('dup'), { code: '23505', constraint: 'uq_finance_fund_transfers_reverses' });
      }],
    ]);
    await assert.rejects(() => reverseFundTransfer({ siteCode: SITE, rawId: '41', body: reverseBody, actor: ACTOR, now: NOW }), (error) => error.code === 'FUND_TRANSFER_ALREADY_REVERSED');
  });

  it('olmayan / başka sitenin / geçersiz kimlik 404 FUND_TRANSFER_NOT_FOUND (IDOR: sorgu hep site_code ile)', async () => {
    handlers = reverseFlow(transferRow());
    await assert.rejects(() => reverseFundTransfer({ siteCode: SITE, rawId: '99', body: reverseBody, actor: ACTOR, now: NOW }), (error) => error.code === 'FUND_TRANSFER_NOT_FOUND' && error.statusCode === 404);
    await assert.rejects(() => reverseFundTransfer({ siteCode: SITE, rawId: 'abc', body: reverseBody, actor: ACTOR, now: NOW }), (error) => error.code === 'FUND_TRANSFER_NOT_FOUND');
    const lookups = log.filter((entry) => /t\.id = \$1 AND t\.site_code = \$2$/.test(entry.sql));
    assert.ok(lookups.length > 0 && lookups.every((entry) => entry.params[1] === SITE));
  });

  it('aynı anahtar + aynı neden = aynı ters aktarım (replayed); aynı anahtar + başka neden 409 IDEMPOTENCY_CONFLICT', async () => {
    const fp = (await import('../src/modules/finance_4b_common.js')).fingerprintOf({ v: 1, kind: 'fund_transfer_reverse', of: 41, reason: 'yanlış kasa' });
    handlers = flowHandlers([
      [/t\.id = \$1 AND t\.site_code = \$2$/, () => ok([transferRow()])],
      [/idempotency_key = \$2$/, () => ok([transferRow({ id: '42', reverses_transfer_id: '41', request_fingerprint: fp })])],
    ]);
    const again = await reverseFundTransfer({ siteCode: SITE, rawId: '41', body: reverseBody, actor: ACTOR, now: NOW });
    assert.equal(again.replayed, true);
    assert.equal(again.transfer.id, 42);
    await assert.rejects(() => reverseFundTransfer({ siteCode: SITE, rawId: '41', body: { ...reverseBody, reason: 'başka' }, actor: ACTOR, now: NOW }), (error) => error.code === 'IDEMPOTENCY_CONFLICT');
  });
});

describe('listFundTransfers: sayfalama', () => {
  it('limit + 1 satır okunur, next_before_id son satırın kimliği; her sorguda site_code', async () => {
    handlers = [[/FROM finance_fund_transfers t .* WHERE t\.site_code = \$1(?: .*)? ORDER BY t\.id DESC LIMIT \$2$/, () => ok([transferRow({ id: '9' }), transferRow({ id: '8' })])]];
    const out = await listFundTransfers(SITE, { limit: '1' }, pool);
    assert.equal(out.items.length, 1);
    assert.equal(out.next_before_id, 9);
    assert.equal(log[0].params[0], SITE);
    assert.equal(log[0].params.at(-1), 2);
  });
});
