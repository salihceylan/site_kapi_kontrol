// Alacak iadesi (088): saf yardımcılar, makbuz anlık görüntüsü, API gövdesi (sakin / yönetici), korumalar ve kaynak sözleşmesi (DB'siz).
// Defter + hesap hareketi + makbuz + durum makinesi ve yarışlar GERÇEK PostgreSQL'de: scripts/qa_finance_devir_iade.mjs.
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

process.env.JWT_SECRET ||= 'test-secret-test-secret-test-secret-123456';

const refunds = await import('../src/modules/finance_refunds.js');
const guard = await import('../src/modules/finance_refund_guard.js');
const exitNotice = await import('../src/modules/finance_exit_notice.js');
const ownerNotice = await import('../src/modules/apartment_owner_notice.js');

const src = (name) => readFileSync(new URL(`../src/modules/${name}`, import.meta.url), 'utf8').replace(/\r\n/g, '\n');
const bad = (fn, code = 'INVALID_BODY') => assert.throws(fn, (e) => e.statusCode === 400 && e.code === code);

describe('iade gövdeleri', () => {
  const base = { apartment_id: 7, amount_minor: 150000, idempotency_key: 'iade-anahtari-1' };

  it('sakin talebi: daire + tutar + anahtar; hesap (account_party) isteğe bağlı; not en çok 200 karakter', () => {
    const input = refunds.parseRequestInput({ ...base, note: '  Lütfen iade edin  ' }, { manager: false });
    assert.deepEqual(input, { apartmentId: 7, accountParty: null, amountMinor: 150000, note: 'Lütfen iade edin', idempotencyKey: 'iade-anahtari-1' });
    bad(() => refunds.parseRequestInput({ ...base, note: 'x'.repeat(201) }, { manager: false }));
    bad(() => refunds.parseRequestInput({ ...base, idempotency_key: undefined }, { manager: false }));
    bad(() => refunds.parseRequestInput({ ...base, apartment_id: 'abc' }, { manager: false }));
  });

  it('tutar kuruş cinsinden POZİTİF tamsayı: 0, negatif, ondalık, metin, çok büyük reddedilir', () => {
    for (const amount of [0, -1, 1.5, '100', null, undefined, Number.MAX_SAFE_INTEGER * 10, NaN, Infinity]) {
      bad(() => refunds.parseRequestInput({ ...base, amount_minor: amount }, { manager: false }));
    }
    assert.equal(refunds.parseRequestInput({ ...base, amount_minor: 1 }, { manager: false }).amountMinor, 1);
  });

  it('yönetici talebinde hesap (ev sahibi / kiracı) ZORUNLU ve geçerli olmalı', () => {
    bad(() => refunds.parseRequestInput(base, { manager: true }));
    bad(() => refunds.parseRequestInput({ ...base, account_party: 'both' }, { manager: true }));
    assert.equal(refunds.parseRequestInput({ ...base, account_party: 'tenant' }, { manager: true }).accountParty, 'tenant');
  });

  it('onay: ödeme hesabı pozitif kimlik + işlem anahtarı; ret / geri alma: gerekçe zorunlu (en çok 200) + anahtar', () => {
    assert.deepEqual(refunds.parseApproveInput({ pay_account_id: 3, idempotency_key: 'k1' }), { payAccountId: 3, idempotencyKey: 'k1' });
    for (const body of [{}, { pay_account_id: 0, idempotency_key: 'k' }, { pay_account_id: 'x', idempotency_key: 'k' }, { pay_account_id: 3 }]) bad(() => refunds.parseApproveInput(body));
    assert.equal(refunds.parseRejectInput({ reason: ' Mahsup edelim ', idempotency_key: 'k' }).reason, 'Mahsup edelim');
    bad(() => refunds.parseRejectInput({ idempotency_key: 'k' }));
    bad(() => refunds.parseRejectInput({ reason: '   ', idempotency_key: 'k' }));
    bad(() => refunds.parseRejectInput({ reason: 'x'.repeat(201), idempotency_key: 'k' }));
    bad(() => refunds.parseReverseInput({ reason: 'yanlış', idempotency_key: '' }));
    assert.equal(refunds.parseReverseInput({ reason: 'yanlış onay', idempotency_key: 'k' }).reason, 'yanlış onay');
  });

  it('istek parmak izi: aynı gövde aynı; tutar / daire / hesap / not farkı farklı', () => {
    const f = (over = {}) => refunds.requestFingerprint({ apartmentId: 1, accountParty: 'owner', amountMinor: 500, note: null, ...over });
    assert.match(f(), /^[0-9a-f]{64}$/);
    assert.equal(f(), f());
    for (const over of [{ apartmentId: 2 }, { accountParty: 'tenant' }, { amountMinor: 501 }, { note: 'x' }]) assert.notEqual(f(over), f());
  });
});

describe('alacak, yöntem ve makbuz numarası', () => {
  it('creditOf: yalnız NEGATİF bakiye (alacak) iade edilebilir; BigInt / metin / sayı kabul', () => {
    assert.equal(refunds.creditOf(-2000n), 2000n);
    assert.equal(refunds.creditOf('-2000'), 2000n);
    assert.equal(refunds.creditOf(-1), 1n);
    assert.equal(refunds.creditOf(0), 0n);
    assert.equal(refunds.creditOf(5000n), 0n, 'borçlu hesapta alacak yok');
  });

  it('residentVisibleCredit: sakinin iade üst sınırı Borcum\'da GÖRDÜĞÜ alacaktır; önceki sakinin gizli borca mahsup edilmiş fazla ödemesi yeni sakine iade edilemez', () => {
    const entry = (id, kind, amount, entryDate, anchor, over = {}) => ({ id, kind, amount_minor: String(amount), anchor, entry_date: entryDate, due_date: kind === 'charge' ? entryDate : null, reverses_entry_id: null, ...over });
    // önceki kiracı: kapsam dışı (temmuz) 600 borç; ağustosta 1000 öder -> 600 borca mahsup, 400 artık (hesap alacağı 400)
    const old = [entry(1, 'charge', 600, '2026-07-20', '2026-07-01'), entry(2, 'payment', -1000, '2026-08-10', '2026-08-01')];
    const sinceNew = { since: '2026-10-01', today: '2026-10-29' };
    assert.equal(refunds.residentVisibleCredit(old, sinceNew), 0n, 'yeni sakin Borcum\'da alacak görmez -> iade edemez (hesap alacağı 400 olsa da)');
    // yeni sakin kapsam içinde 500 fazla öderse YALNIZ onu görür (900 değil)
    const withOwn = [...old, entry(3, 'payment', -500, '2026-10-05', '2026-10-01')];
    assert.equal(refunds.residentVisibleCredit(withOwn, sinceNew), 500n);
    // kapsam yok (since null = dairenin tüm defteri; yönetici görünümü) hesap alacağıyla aynıdır
    assert.equal(refunds.residentVisibleCredit(old, { since: null, today: '2026-10-29' }), 400n);
    // borçlu sakin: alacak yok
    assert.equal(refunds.residentVisibleCredit([entry(4, 'charge', 900, '2026-10-02', '2026-10-01')], sinceNew), 0n);
    assert.equal(refunds.residentVisibleCredit([], sinceNew), 0n);
  });

  it('sakin talebi servis sözleşmesi: üst sınır görünüm kapsamıyla hesaplanır (scopeView), yönetici talebinde kapsamsız kalır; 409 gövdesi kapsamlı tutarı verir (kaynak sözleşmesi)', () => {
    const code = src('finance_refunds.js');
    assert.match(code, /insertRequest\(client, \{ siteCode, input, accountParty: ownParty, kind: 'resident', requestedBy: userCode, actor: authUser, scopeView: own \}\)/);
    assert.match(code, /insertRequest\(client, \{ siteCode, input, accountParty: input\.accountParty, kind: 'manager', requestedBy: actorInfo\.userCode, actor \}\)/, 'yönetici talebi scopeView almaz');
    assert.match(code, /if \(scopeView !== null\) \{[\s\S]*?residentVisibleCredit\(accountRows, \{ since: viewSinceOf\(scopeView, todayIsoDate\), today: todayIsoDate \}\)[\s\S]*?credit = visible;/);
    assert.match(code, /throw refundExceedsCredit\(minorToNumber\(available > 0n \? available : 0n\)\)/, 'hata gövdesi `available` (kapsamlı) tutarla kurulur');
  });

  it('payMethodOf: nakit hesap -> nakit, banka -> havale', () => {
    assert.equal(refunds.payMethodOf('cash'), 'cash');
    assert.equal(refunds.payMethodOf('bank'), 'transfer');
  });

  it('makbuz numarası IA-yıl-6 hane (MK dizisi DEĞİL)', () => {
    assert.equal(refunds.formatRefundNumber(2026, 1), 'IA-2026-000001');
    assert.equal(refunds.formatRefundNumber(2026, 123456), 'IA-2026-123456');
    assert.equal(refunds.REFUND_SERIES, 'IA');
  });
});

describe('iade makbuzu anlık görüntüsü (değişmez, asgari kişisel veri)', () => {
  const input = {
    number: 'IA-2026-000001', issuedOn: '2026-10-28', paidOn: '2026-10-28', amountMinor: 150000, method: 'cash', siteName: 'Güneş Sitesi', apartmentLabel: 'A Blok - Daire 3',
    accountParty: 'owner', payeeName: 'Ali Veli', accountName: 'Kasa', issuerName: 'Ayşe Yönetici', verificationCode: 'ABCDEF123456',
  };

  it('sürüm, numara, tür, tutar, yöntem, site, daire, alıcı, çıkış hesabı, düzenleyen, doğrulama kodu', () => {
    const s = refunds.buildRefundSnapshot(input);
    assert.deepEqual(Object.keys(s).sort(), ['amount_minor', 'apartment', 'currency', 'from_account', 'issued_on', 'issuer', 'kind', 'method', 'number', 'paid_on', 'payee', 'site', 'template_version', 'v', 'verification_code']);
    assert.equal(s.kind, 'refund');
    assert.deepEqual(s.payee, { party: 'owner', name: 'Ali Veli' });
    assert.deepEqual(s.from_account, { name: 'Kasa' });
    assert.equal(s.amount_minor, 150000);
  });

  it('TCKN / telefon / e-posta / adres / bakiye / serbest not YOK; alıcı adı yoksa null', () => {
    const json = JSON.stringify(refunds.buildRefundSnapshot({ ...input, payeeName: null, note: 'gizli not', balance: 5 }));
    assert.doesNotMatch(json, /gizli not|balance|phone|email|tckn|address/i);
    assert.equal(refunds.buildRefundSnapshot({ ...input, payeeName: null }).payee.name, null);
  });
});

describe('API gövdesi', () => {
  const row = (over = {}) => ({
    id: '12', site_code: '1000000001', apartment_id: '7', account_party: 'owner', amount_minor: '150000', status: 'requested', requested_by_kind: 'resident', requested_by: '20004',
    requested_at: new Date('2026-10-28T09:00:00Z'), note: 'iade istiyorum', resolved_by: null, resolved_at: null, reject_reason: null, pay_account_id: null, pay_date: null, pay_method: null,
    ledger_entry_id: null, receipt_year: null, receipt_no: null, receipt_issued_on: null, receipt_snapshot: null, receipt_code: null, decision_key: null, reversed_at: null,
    reversal_reason: null, reversal_ledger_entry_id: null, reversal_key: null, idempotency_key: 'k', request_fingerprint: 'f'.repeat(64), pay_account_name: null, pay_account_kind: null,
    block_name: 'A Blok', unit_label: 'Daire 3', requested_by_name: 'Deniz Sakin', resolved_by_name: 'Ayşe Yönetici', reversed_by_name: null, ...over,
  });
  const approved = row({
    status: 'approved', resolved_at: new Date('2026-10-28T10:00:00Z'), pay_account_id: '3', pay_account_name: 'Kasa', pay_date: '2026-10-28', pay_method: 'cash', ledger_entry_id: '99', receipt_year: 2026, receipt_no: 4,
    receipt_issued_on: '2026-10-28', receipt_snapshot: { v: 1 }, receipt_code: 'ABCDEF123456',
  });

  it('yönetici gövdesi: tutar / daire etiketi / hesap adı / yönetici adları / makbuz', () => {
    const body = refunds.mapRefundRow(approved);
    assert.equal(body.id, 12);
    assert.equal(body.amount_minor, 150000);
    assert.equal(body.apartment_label, 'A Blok - Daire 3');
    assert.equal(body.pay_account_name, 'Kasa');
    assert.equal(body.requested_by_name, 'Deniz Sakin');
    assert.equal(body.resolved_by_name, 'Ayşe Yönetici');
    assert.deepEqual({ ...body.receipt, snapshot: undefined }, { number: 'IA-2026-000004', issued_on: '2026-10-28', verification_code: 'ABCDEF123456', status: 'active', snapshot: undefined });
  });

  it('sakin gövdesi: yönetici adları, hesap, defter kimliği ve geri alma nedeni YOK; ret nedeni yalnız reddedilmişte görünür', () => {
    const resident = refunds.mapRefundRow(approved, { forResident: true });
    for (const key of ['requested_by_name', 'resolved_by_name', 'reversed_by_name', 'pay_account_id', 'pay_account_name', 'ledger_entry_id', 'reversal_reason', 'pay_method']) {
      assert.equal(key in resident, false, key);
    }
    assert.equal(resident.note, 'iade istiyorum');
    const rejected = refunds.mapRefundRow(row({ status: 'rejected', resolved_at: new Date(), reject_reason: 'Mahsup edelim' }), { forResident: true });
    assert.equal(rejected.reject_reason, 'Mahsup edelim');
    assert.equal(refunds.mapRefundRow(row({ reject_reason: 'sızmamalı' }), { forResident: true }).reject_reason, null, 'karara bağlanmamış talepte ret nedeni verilmez');
  });

  it('geri alınan iadenin makbuzu iptal sayılır; talepte makbuz yok', () => {
    assert.equal(refunds.mapRefundRow(row({ ...approved, status: 'reversed', reversed_at: new Date() })).receipt.status, 'cancelled');
    assert.equal(refunds.mapRefundRow(row()).receipt, null);
  });

  it('kurul yanıtından yönetici / sakin adları çıkarılır (BOARD_HIDDEN_KEYS)', async () => {
    const { redactFinanceForBoard } = await import('../src/modules/finance_common.js');
    const body = redactFinanceForBoard({ items: [refunds.mapRefundRow(approved)] }).items[0];
    assert.equal(body.requested_by_name, null);
    assert.equal(body.resolved_by_name, null);
    assert.equal(body.reversed_by_name, null);
    assert.equal(body.amount_minor, 150000);
  });
});

describe('korumalar', () => {
  it('iade / devir satırları genel ters kayıt ucuyla DOKUNULAMAZ; hata kodları sabit', () => {
    assert.deepEqual([...guard.MANAGED_SOURCE_KINDS], ['refund', 'liability_transfer']);
    assert.equal(guard.entryManagedByFlow().code, 'ENTRY_MANAGED_BY_FLOW');
    assert.equal(guard.entryManagedByFlow().statusCode, 409);
    assert.equal(guard.refundBlocksPaymentChange().code, 'REFUND_BLOCKS_PAYMENT_CHANGE');
  });

  it('devir geri alma: devrin satırı sonradan başka bir devirle taşındıysa 409 LIABILITY_TRANSFER_NOT_REVERSIBLE; geri alma ve geçmiş listesi aynı kuralı kullanır (kaynak sözleşmesi)', async () => {
    const liability = await import('../src/modules/finance_liability_service.js');
    const error = liability.transferSuperseded();
    assert.equal(error.statusCode, 409);
    assert.equal(error.code, 'LIABILITY_TRANSFER_NOT_REVERSIBLE');
    const code = src('finance_liability_service.js');
    assert.match(code, /if \(plan\.supersededIds\.length > 0\) \{[\s\S]*?throw transferSuperseded\(\);/);
    assert.match(code, /BOOL_OR\(l\.kind = 'charge' AND EXISTS \(SELECT 1 FROM ledger_entries r WHERE r\.reverses_entry_id = l\.id\)\)/);
    assert.match(code, /firstId === null \|\| firstId === undefined \|\| superseded \? false/);
  });

  it('hasApprovedRefund: site + daire + hesap ile yalnız ONAYLI (geri alınmamış) iadeyi arar', async () => {
    const calls = [];
    const db = {
      async query(text, params) {
        calls.push({ sql: text.replace(/\s+/g, ' ').trim(), params });
        return { rows: calls.length === 1 ? [{ '?column?': 1 }] : [] };
      },
    };
    assert.equal(await guard.hasApprovedRefund(db, { siteCode: 5, apartmentId: 7, accountParty: 'owner' }), true);
    assert.equal(await guard.hasApprovedRefund(db, { siteCode: 5, apartmentId: 7, accountParty: 'tenant' }), false);
    assert.match(calls[0].sql, /FROM finance_refunds WHERE site_code = \$1 AND apartment_id = \$2 AND account_party = \$3 AND status = 'approved' LIMIT 1/);
    assert.deepEqual(calls[0].params, [5, 7, 'owner']);
  });

  it('ledger servisi: genel ters kayıt iade / devir satırını reddeder ve onaylı iade varken ödeme iptali / düzeltmesini engeller (kaynak sözleşmesi)', () => {
    const ledger = src('finance_ledger_service.js');
    assert.match(ledger, /MANAGED_SOURCE_KINDS\.includes\(original\.source_kind\)/);
    assert.match(ledger, /original\.kind === 'payment' && \(await hasApprovedRefund\(client, \{ siteCode, apartmentId, accountParty: entryAccountParty\(original\) \}\)\)/);
    assert.match(ledger, /if \(await hasApprovedRefund\(client, \{ siteCode, apartmentId, accountParty: entryAccountParty\(original\) \}\)\) \{\s*throw refundBlocksPaymentChange\(\);/);
  });

  it('raporlar: iade ve devir satırları tahakkuk (borçlandırılan) sayılmaz; iade net tahsilatı düşürür; kasa durumunda iade çıkış sütunundadır (kaynak sözleşmesi)', () => {
    for (const file of ['finance_reports.js', 'finance_home.js']) {
      assert.match(src(file), /COALESCE\(source_kind, ''\) NOT IN \('opening', 'refund', 'liability_transfer'\)/, file);
      assert.match(src(file), /COALESCE\(SUM\(amount_minor\) FILTER \(WHERE source_kind = 'refund'\), 0\)/, `${file}: net tahsilat`);
    }
    assert.match(src('finance_read_service.js'), /COALESCE\(source_kind, ''\) NOT IN \('refund', 'liability_transfer'\)/);
    assert.match(src('management_company_service.js'), /COALESCE\(l\.source_kind, ''\) NOT IN \('refund', 'liability_transfer'\)/);
    assert.match(src('finance_reports.js'), /m\.kind IN \('expense', 'refund'\)/);
    assert.match(src('finance_accounts.js'), /WHEN m\.kind = 'refund' THEN/);
  });

  it('kasa defteri: iade olayları kasaya tahsilat yazılmaz (loadFundBook), yalnız avansı düşürür (kaynak sözleşmesi)', () => {
    assert.match(src('finance_funds_service.js'), /if \(event\.refund === true\) continue;/);
  });
});

describe('kiracı çıkışı öncesi malike borç bildirimi (finance_exit_notice)', () => {
  function fakeClient({ balance = '0', owners = [], fail = null } = {}) {
    const calls = [];
    return {
      calls,
      async query(text, params) {
        const sql = text.replace(/\s+/g, ' ').trim();
        calls.push({ sql, params });
        if (fail && fail.test(sql)) throw Object.assign(new Error('simule'), { code: 'XX000' });
        if (/to_regclass/.test(sql)) return { rows: [{ ok: true }] };
        if (/FROM ledger_entries l WHERE/.test(sql)) return { rows: [{ balance }] };
        // sayı = tek malik (muhatap); nesne = { user_code, is_account_holder }
        if (/FROM apartment_residencies r INNER JOIN site_people sp/.test(sql)) return { rows: owners.map((o) => (typeof o === 'object' ? o : { user_code: o, is_account_holder: true })) };
        return { rows: [], rowCount: 1 };
      },
    };
  }

  it('borç yoksa bildirim YAZILMAZ; alacaklı hesap borç sayılmaz', async () => {
    for (const balance of ['0', '-5000']) {
      const client = fakeClient({ balance, owners: [5001] });
      assert.deepEqual(await exitNotice.notifyOwnerOfTenantDebt(client, { siteCode: 1, apartmentId: 7 }), { notified: 0, debt_minor: 0 });
      assert.equal(client.calls.some((c) => /INSERT INTO apartment_notices/.test(c.sql)), false, balance);
    }
  });

  it('borç varsa hesap muhatabına uygulama içi bildirim: tutar metinde, çıkışı engelleme yok; kiracının hesabı (account_party = tenant) okunur', async () => {
    const client = fakeClient({ balance: '123456', owners: [5001] });
    const out = await exitNotice.notifyOwnerOfTenantDebt(client, { siteCode: 1, apartmentId: 7 });
    assert.deepEqual(out, { notified: 1, debt_minor: 123456 });
    const notices = client.calls.filter((c) => /INSERT INTO apartment_notices/.test(c.sql));
    assert.equal(notices.length, 1);
    assert.deepEqual(notices.map((c) => c.params[2]), [5001]);
    assert.equal(notices[0].params[3], 'tenant_exit_debt');
    assert.match(notices[0].params[4], /1\.234,56 ₺ ödenmemiş borcu var/);
    assert.match(notices[0].params[4], /site yönetimi onaylarsa ev sahibi hesabınıza devredilebilir/);
    const read = client.calls.find((c) => /FROM ledger_entries l WHERE/.test(c.sql));
    assert.match(read.sql, /= 'tenant'/);
  });

  it('bildirim gizliliği (çoklu malik): borç tutarı YALNIZ hesap muhatabına; diğer maliklere tutarsız genel not; muhatabın hesabı yoksa tutar kimseye gitmez', async () => {
    const note = ownerNotice.OWNER_DEBT_NOTE_FOR_OTHERS;
    assert.equal(note, 'Dairenizle ilgili bir borç işlemi yapıldı; ayrıntılar hesap muhatabında.');
    assert.doesNotMatch(note, /\d|₺/);
    const client = fakeClient({ balance: '123456', owners: [{ user_code: 5002, is_account_holder: false }, { user_code: 5001, is_account_holder: true }, { user_code: 5003, is_account_holder: false }] });
    const out = await exitNotice.notifyOwnerOfTenantDebt(client, { siteCode: 1, apartmentId: 7 });
    assert.deepEqual(out, { notified: 3, debt_minor: 123456 });
    const notices = client.calls.filter((c) => /INSERT INTO apartment_notices/.test(c.sql));
    const byUser = new Map(notices.map((c) => [c.params[2], c.params[4]]));
    assert.match(byUser.get(5001), /1\.234,56 ₺ ödenmemiş borcu var/);
    for (const other of [5002, 5003]) {
      assert.equal(byUser.get(other), note, `diğer malik ${other}`);
      assert.doesNotMatch(byUser.get(other), /₺|\d/);
    }
    // muhatabın hesabı yok: yalnız hesabı olan diğer malik, yalnız genel not
    const noHolder = fakeClient({ balance: '123456', owners: [{ user_code: 5002, is_account_holder: false }] });
    await exitNotice.notifyOwnerOfTenantDebt(noHolder, { siteCode: 1, apartmentId: 7 });
    const only = noHolder.calls.filter((c) => /INSERT INTO apartment_notices/.test(c.sql));
    assert.equal(only.length, 1);
    assert.equal(only[0].params[4], note);
  });

  it('devir bildirimi (finance_liability_service): aynı gizlilik yardımcısını kullanır; eski "tüm maliklere tutar" sorgusu kalmadı (kaynak sözleşmesi)', () => {
    const code = src('finance_liability_service.js');
    assert.match(code, /notifyOwnersWithPrivacy\(client, \{ siteCode, apartmentId, kind: 'liability_transfer', holderMessage: message \}\)/);
    assert.doesNotMatch(code, /SELECT DISTINCT sp\.user_code/);
    assert.match(src('finance_exit_notice.js'), /notifyOwnersWithPrivacy\(client, \{/);
  });

  it('bildirim hatası çıkışı ASLA bozmaz: hata yutulur, SAVEPOINT geri alınır', async () => {
    const client = fakeClient({ balance: '5000', owners: [5001], fail: /INSERT INTO apartment_notices/ });
    const original = console.error;
    console.error = () => {};
    try {
      const out = await exitNotice.notifyOwnerOfTenantDebt(client, { siteCode: 1, apartmentId: 7 });
      assert.equal(out.debt_minor, 5000, 'notifyApartmentUsers kendi hatasını yutar: borç bildirildi sayılır ya da 0; çıkış sürer');
    } finally {
      console.error = original;
    }
    const broken = fakeClient({ fail: /to_regclass/ });
    console.error = () => {};
    try {
      assert.deepEqual(await exitNotice.notifyOwnerOfTenantDebt(broken, { siteCode: 1, apartmentId: 7 }), { notified: 0, debt_minor: 0 });
    } finally {
      console.error = original;
    }
    assert.ok(broken.calls.some((c) => /ROLLBACK TO SAVEPOINT tenant_exit_debt/.test(c.sql)));
  });

  it('çıkış sonrası genel metin borçlu / borçsuz ayrılır', () => {
    assert.equal(exitNotice.exitDoneMessage('A - 3', 0n), 'Kiracı A - 3 dairesinden ayrıldı. Daire yönetimi size döndü.');
    assert.match(exitNotice.exitDoneMessage('A - 3', 250000n), /Kiracı A - 3 dairesinden ayrıldı\. Daire yönetimi size döndü\. Kiracının 2\.500,00 ₺ ödenmemiş borcu bulunuyor/);
  });

  it('kaynak sözleşmesi: kiracı ilişkisi kapanırken closeResidency bildirimi ÇAĞIRIR (yalnız kiracı); apartment_mgmt çıkış metni borçlu / borçsuz', () => {
    const people = src('people_service.js');
    assert.match(people, /if \(residency\.relation === 'tenant'\) \{\s*try \{\s*const \{ notifyOwnerOfTenantDebt \} = await import\('\.\/finance_exit_notice\.js'\);/);
    const mgmt = src('apartment_mgmt_service.js');
    assert.match(mgmt, /const debtMinor = await tenantDebtMinorSafe\(client, site, state\.apartment\.id\);\s*closed = await endTenancy\(client, authUser, state, 'tenant_exit'\);/);
    assert.match(mgmt, /await exitDoneText\(aptLabel\(state\.apartment\), debtMinor\)/);
  });
});
