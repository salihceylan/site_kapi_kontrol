// İki hesap (İP-1A, sözleşme 2.1): finance_parties.js saf kuralları ve DB işlevleri (KATI sahte istemci). Gerçek PostgreSQL: scripts/qa_platform_pg.mjs "parties".
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import {
  ACCOUNT_PARTIES,
  CHARGE_PARTIES,
  SOURCE_KINDS,
  accountBalances,
  accountForCharge,
  accountPartyOfRow,
  accountPartySql,
  defaultPaymentParty,
  effectiveChargeParty,
  occupantAccount,
  oldestOpenDue,
  parseAccountParty,
  parseChargeParty,
  partyOfRelation,
  postPayment,
  resolveChargeParty,
  resolvePersonParty,
  responsiblePersonSql,
  tenantOnDateSql,
  visiblePartyOfRelation,
} from '../src/modules/finance_parties.js';

const norm = (text) => String(text).replace(/\s+/g, ' ').trim();

/** KATI sahte istemci: her sorgu bir işleyiciyle eşleşmeli; eşleşmeyen SQL hata verir. */
function strictClient(handlers) {
  const calls = [];
  return {
    calls,
    async query(text, params = []) {
      const sql = norm(text);
      calls.push({ sql, params });
      for (const [pattern, fn] of handlers) {
        if (pattern.test(sql)) return typeof fn === 'function' ? fn(sql, params) : fn;
      }
      throw new Error(`BEKLENMEYEN SQL: ${sql.slice(0, 200)}`);
    },
  };
}
const ok = (rows = []) => ({ rows, rowCount: rows.length });

describe('sözleşme 2.1: sabitler ve saf kurallar', () => {
  it('ACCOUNT_PARTIES = [owner, tenant]; CHARGE_PARTIES = [occupant, owner]; kaynak türleri sabit', () => {
    assert.deepEqual(ACCOUNT_PARTIES, ['owner', 'tenant']);
    assert.ok(Object.isFrozen(ACCOUNT_PARTIES));
    assert.deepEqual(CHARGE_PARTIES, ['occupant', 'owner']);
    assert.deepEqual(SOURCE_KINDS, ['manual', 'payment_notice', 'bank_line', 'opening', 'card']);
  });

  it('052 öncesi satırın hesabı payer_party anlık görüntüsünden: tenant -> kiracı, owner / both -> ev sahibi; dolu account_party önceliklidir', () => {
    assert.equal(accountPartyOfRow({ account_party: null, payer_party: 'tenant' }), 'tenant');
    assert.equal(accountPartyOfRow({ account_party: null, payer_party: 'owner' }), 'owner');
    assert.equal(accountPartyOfRow({ account_party: null, payer_party: 'both' }), 'owner');
    assert.equal(accountPartyOfRow({ payer_party: 'both' }), 'owner');
    assert.equal(accountPartyOfRow({ account_party: 'tenant', payer_party: 'owner' }), 'tenant');
    assert.equal(norm(accountPartySql('l')), `COALESCE(l.account_party, CASE WHEN l.payer_party = 'tenant' THEN 'tenant' ELSE 'owner' END)`);
  });

  it('tanımın etkin kim öder değeri: verilmezse aylık -> occupant, tek seferlik -> owner', () => {
    assert.equal(effectiveChargeParty(null, 'recurring'), 'occupant');
    assert.equal(effectiveChargeParty(undefined, 'one_time'), 'owner');
    assert.equal(effectiveChargeParty('owner', 'recurring'), 'owner');
    assert.equal(effectiveChargeParty('occupant', 'one_time'), 'occupant');
  });

  it('occupant kuralı: sorumlu owner -> ev sahibi; tenant / both -> kiracı VARSA kiracı, yoksa ev sahibi; owner borcu her zaman ev sahibi', () => {
    assert.equal(occupantAccount('owner', true), 'owner');
    assert.equal(occupantAccount('owner', false), 'owner');
    assert.equal(occupantAccount('tenant', true), 'tenant');
    assert.equal(occupantAccount('tenant', false), 'owner');
    assert.equal(occupantAccount('both', true), 'tenant');
    assert.equal(occupantAccount('both', false), 'owner');
    for (const responsible of ['owner', 'tenant', 'both']) {
      for (const hasTenant of [true, false]) {
        assert.equal(accountForCharge('owner', responsible, hasTenant), 'owner');
        assert.equal(accountForCharge('occupant', responsible, hasTenant), occupantAccount(responsible, hasTenant));
      }
    }
  });

  it('kişinin kendi hesabı: owner -> ev sahibi; tenant -> kiracı; resident -> güncel kiracı varsa kiracı, yoksa ev sahibi; family_member -> null', () => {
    assert.equal(partyOfRelation('owner', true), 'owner');
    assert.equal(partyOfRelation('owner', false), 'owner');
    assert.equal(partyOfRelation('tenant', false), 'tenant');
    assert.equal(partyOfRelation('resident', true), 'tenant');
    assert.equal(partyOfRelation('resident', false), 'owner');
    assert.equal(partyOfRelation('family_member', true), null);
    assert.equal(partyOfRelation('family_member', false), null);
    assert.equal(partyOfRelation('x', false), null);
  });

  it('inceleme: görünüm / hatırlatma hesabı = kendi hesabı; belirtilmemiş sakin yalnız sorumlu "both" iken ya da sorumlu tarafın kişisi yokken (F2.05 yedeği)', () => {
    const ctx = (responsibleParty, hasResponsiblePerson, hasCurrentTenant = false) => ({ responsibleParty, hasResponsiblePerson, hasCurrentTenant });
    assert.equal(visiblePartyOfRelation('resident', ctx('owner', true)), null);
    assert.equal(visiblePartyOfRelation('resident', ctx('tenant', true, true)), null);
    assert.equal(visiblePartyOfRelation('resident', ctx('owner', false)), 'owner');
    assert.equal(visiblePartyOfRelation('resident', ctx('owner', false, true)), 'tenant');
    assert.equal(visiblePartyOfRelation('resident', ctx('both', true, true)), 'tenant');
    assert.equal(visiblePartyOfRelation('resident', ctx('both', true, false)), 'owner');
    assert.equal(visiblePartyOfRelation('owner', ctx('tenant', true, true)), 'owner');
    assert.equal(visiblePartyOfRelation('tenant', ctx('owner', true, true)), 'tenant');
    assert.equal(visiblePartyOfRelation('family_member', ctx('both', false)), null);
    const sql = norm(responsiblePersonSql('a'));
    assert.match(sql, /rp\.apartment_id = a\.id AND rp\.is_current = TRUE/);
    assert.match(sql, /rpp\.is_active = TRUE/);
    assert.match(sql, /rp\.relation = CASE a\.responsible_party WHEN 'owner' THEN 'owner' WHEN 'tenant' THEN 'tenant' END/);
  });

  it('gövde alanları: account_party yoksa null, geçersizse 400; charge_party yoksa null, geçersizse 400', () => {
    assert.equal(parseAccountParty(undefined), null);
    assert.equal(parseAccountParty(null), null);
    assert.equal(parseAccountParty('tenant'), 'tenant');
    assert.throws(() => parseAccountParty('both'), (e) => e.statusCode === 400 && e.code === 'INVALID_BODY');
    assert.throws(() => parseAccountParty(1), (e) => e.code === 'INVALID_BODY');
    assert.equal(parseChargeParty(undefined), null);
    assert.equal(parseChargeParty('occupant'), 'occupant');
    assert.throws(() => parseChargeParty('tenant'), (e) => e.code === 'INVALID_BODY');
  });

  it('etkin kiracı SQL parçası: tarih kapsamı (başlangıç = taşınma günü, boşsa kayıt günü), güncel ilişkide kişi etkin, bitmişte move_out >= tarih', () => {
    const sql = norm(tenantOnDateSql('a', '$3::DATE'));
    assert.match(sql, /tr\.apartment_id = a\.id AND tr\.relation = 'tenant'/);
    assert.match(sql, /COALESCE\(tr\.move_in_date, \(tr\.created_at AT TIME ZONE 'Europe\/Istanbul'\)::DATE\) <= \$3::DATE/);
    assert.match(sql, /\(tr\.is_current = TRUE AND tsp\.is_active = TRUE\) OR \(tr\.is_current = FALSE AND tr\.move_out_date IS NOT NULL AND tr\.move_out_date >= \$3::DATE\)/);
  });
});

describe('vadesi en eski açık borç (varsayılan tahsilat hesabı)', () => {
  const charge = (id, amount, due, extra = {}) => ({ id, kind: 'charge', amount: BigInt(amount), entryDate: due, dueDate: due, reversesId: null, ...extra });
  const payment = (id, amount, date) => ({ id, kind: 'payment', amount: BigInt(-amount), entryDate: date, dueDate: null, reversesId: null });

  it('mahsup vadesi en eski borçtan: ödemeler önce eski borcu kapatır; ilk açık kalemin vadesi döner; hepsi ödenmişse null', () => {
    assert.equal(oldestOpenDue([]), null);
    assert.equal(oldestOpenDue([charge(1, 100, '2026-01-05'), charge(2, 100, '2026-02-05')]), '2026-01-05');
    assert.equal(oldestOpenDue([charge(1, 100, '2026-01-05'), charge(2, 100, '2026-02-05'), payment(3, 150, '2026-02-10')]), '2026-02-05');
    assert.equal(oldestOpenDue([charge(1, 100, '2026-01-05'), payment(3, 100, '2026-02-10')]), null);
    // ters kaydı olan borç sayılmaz; ters kaydı olan ödeme de
    const reversedCharge = [charge(1, 100, '2026-01-05'), { id: 2, kind: 'reversal', amount: -100n, entryDate: '2026-01-06', dueDate: '2026-01-05', reversesId: 1 }, charge(3, 50, '2026-03-05')];
    assert.equal(oldestOpenDue(reversedCharge), '2026-03-05');
    const reversedPay = [charge(1, 100, '2026-01-05'), payment(2, 100, '2026-01-10'), { id: 3, kind: 'reversal', amount: 100n, entryDate: '2026-01-11', dueDate: null, reversesId: 2 }];
    assert.equal(oldestOpenDue(reversedPay), '2026-01-05');
    // vadesiz borçta kayıt tarihi esas
    assert.equal(oldestOpenDue([{ id: 1, kind: 'charge', amount: 10n, entryDate: '2026-04-01', dueDate: null, reversesId: null }]), '2026-04-01');
  });

  it('defaultPaymentParty: iki hesaptan vadesi EN ESKİ açık borcu olan; hiç açık borç yoksa borç tarihindeki oturanın hesabı', async () => {
    const rows = (list) => [/FROM ledger_entries l WHERE l\.site_code = \$1 AND l\.apartment_id = \$2/, () => ok(list)];
    const apt = (responsible, hasTenant) => [/SELECT a\.responsible_party, EXISTS/, () => ok([{ responsible_party: responsible, has_tenant: hasTenant }])];
    const row = (id, account, kind, amount, due) => ({ id: String(id), account_party: account, kind, amount_minor: String(amount), entry_date: due, due_date: kind === 'payment' ? null : due, reverses_entry_id: null });
    const both = strictClient([rows([row(1, 'owner', 'charge', 100, '2026-03-05'), row(2, 'tenant', 'charge', 100, '2026-02-05')]), apt('both', true)]);
    assert.equal(await defaultPaymentParty(both, { siteCode: 1, apartmentId: 5, onDate: '2026-10-21' }), 'tenant');
    const ownerOlder = strictClient([rows([row(1, 'owner', 'charge', 100, '2026-01-05'), row(2, 'tenant', 'charge', 100, '2026-02-05')]), apt('both', true)]);
    assert.equal(await defaultPaymentParty(ownerOlder, { siteCode: 1, apartmentId: 5, onDate: '2026-10-21' }), 'owner');
    // inceleme: iki hesabın en eski açık borcu AYNI gün vadeli -> eşitlikte ev sahibi (belgedeki kural; kayıt sırası fark etmez)
    const tie = strictClient([rows([row(1, 'tenant', 'charge', 100, '2026-02-05'), row(2, 'owner', 'charge', 100, '2026-02-05')]), apt('both', true)]);
    assert.equal(await defaultPaymentParty(tie, { siteCode: 1, apartmentId: 5, onDate: '2026-10-21' }), 'owner');
    // kiracı hesabının borcu ödenmiş: kalan açık borç ev sahibinde
    const paid = strictClient([rows([row(1, 'owner', 'charge', 100, '2026-05-05'), row(2, 'tenant', 'charge', 100, '2026-02-05'), row(3, 'tenant', 'payment', -100, '2026-02-06')]), apt('both', true)]);
    assert.equal(await defaultPaymentParty(paid, { siteCode: 1, apartmentId: 5, onDate: '2026-10-21' }), 'owner');
    // hiç açık borç yok: oturanın hesabı (kiracı varsa kiracı)
    const none = strictClient([rows([]), apt('both', true)]);
    assert.equal(await defaultPaymentParty(none, { siteCode: 1, apartmentId: 5, onDate: '2026-10-21' }), 'tenant');
    const noneOwner = strictClient([rows([]), apt('owner', true)]);
    assert.equal(await defaultPaymentParty(noneOwner, { siteCode: 1, apartmentId: 5, onDate: '2026-10-21' }), 'owner');
  });
});

describe('resolveChargeParty / resolvePersonParty / accountBalances', () => {
  it('resolveChargeParty: owner sorgusuz ev sahibi; occupant dairenin sorumlusu + tarihteki kiracıyla; başka sitenin dairesi 404', async () => {
    const none = strictClient([]);
    assert.equal(await resolveChargeParty(none, { siteCode: 1, apartmentId: 2, chargeParty: 'owner', onDate: '2026-10-01' }), 'owner');
    assert.equal(none.calls.length, 0);
    for (const [responsible, hasTenant, expected] of [['both', true, 'tenant'], ['both', false, 'owner'], ['tenant', true, 'tenant'], ['owner', true, 'owner']]) {
      const client = strictClient([[/SELECT a\.responsible_party, EXISTS/, () => ok([{ responsible_party: responsible, has_tenant: hasTenant }])]]);
      assert.equal(await resolveChargeParty(client, { siteCode: 1, apartmentId: 2, chargeParty: 'occupant', onDate: '2026-10-01' }), expected);
      assert.deepEqual(client.calls[0].params, [2, 1, '2026-10-01']);
      assert.match(client.calls[0].sql, /WHERE a\.id = \$1 AND a\.site_code = \$2/);
    }
    const missing = strictClient([[/SELECT a\.responsible_party, EXISTS/, () => ok([])]]);
    await assert.rejects(() => resolveChargeParty(missing, { siteCode: 1, apartmentId: 2, chargeParty: 'occupant', onDate: '2026-10-01' }), (e) => e.code === 'APARTMENT_NOT_FOUND');
    await assert.rejects(() => resolveChargeParty(none, { siteCode: 1, apartmentId: 2, chargeParty: 'tenant', onDate: '2026-10-01' }), (e) => e.code === 'INVALID_BODY');
  });

  it('resolvePersonParty: kişinin güncel ilişkisi -> hesap; ilişki yok / aile üyesi -> null; sorgu site + daire + kullanıcıyla sınırlı', async () => {
    for (const [relation, hasTenant, expected] of [['owner', true, 'owner'], ['tenant', false, 'tenant'], ['resident', true, 'tenant'], ['resident', false, 'owner'], ['family_member', true, null]]) {
      const client = strictClient([[/FROM site_people sp INNER JOIN apartment_residencies r/, () => ok([{ relation, has_tenant: hasTenant }])]]);
      assert.equal(await resolvePersonParty(client, { siteCode: 7, apartmentId: 9, userCode: 42 }), expected, relation);
      assert.deepEqual(client.calls[0].params, [9, 7, 42]);
      assert.match(client.calls[0].sql, /sp\.user_code = \$3 AND sp\.site_code = \$2 AND sp\.is_active = TRUE/);
    }
    const nobody = strictClient([[/FROM site_people sp INNER JOIN apartment_residencies r/, () => ok([])]]);
    assert.equal(await resolvePersonParty(nobody, { siteCode: 7, apartmentId: 9, userCode: 42 }), null);
  });

  it('accountBalances: hesap başına bakiye ve vadesi geçen (bakiye - vadesi gelmemiş, en az 0); satırı olmayan hesap 0', async () => {
    const client = strictClient([
      [/GROUP BY 1/, () => ok([{ account_party: 'owner', balance: '1500', not_due: '500' }, { account_party: 'tenant', balance: '-300', not_due: '0' }])],
    ]);
    const balances = await accountBalances(client, { siteCode: 1, apartmentId: 2 });
    assert.deepEqual(balances, { owner: { balance_minor: 1500, overdue_minor: 1000 }, tenant: { balance_minor: -300, overdue_minor: 0 } });
    assert.match(client.calls[0].sql, /COALESCE\(l\.account_party, CASE WHEN l\.payer_party = 'tenant' THEN 'tenant' ELSE 'owner' END\)/);
    assert.deepEqual(client.calls[0].params.slice(0, 2), [1, 2]);
    const empty = strictClient([[/GROUP BY 1/, () => ok([])]]);
    assert.deepEqual(await accountBalances(empty, { siteCode: 1, apartmentId: 2 }), { owner: { balance_minor: 0, overdue_minor: 0 }, tenant: { balance_minor: 0, overdue_minor: 0 } });
  });
});

describe('postPayment (tek tahsilat giriş noktası)', () => {
  const base = {
    siteCode: 1000000001,
    apartmentId: 11,
    amountMinor: 25000,
    paidOn: '2026-10-20',
    method: 'cash',
    description: 'Elden',
    idempotencyKey: 'pay-key-1',
    actor: { id: 20001, user_code: 20001, role: 'site_manager', full_name: 'Ayşe Yönetici' },
    now: new Date('2026-10-21T09:00:00Z'),
  };

  function paymentClient({ existing = null, closed = false, accounts = false, autoIssue = false, ledgerRows = [], hasTenant = true, responsible = 'both' } = {}) {
    let insertedParams = null;
    const client = strictClient([
      [/^SELECT id, responsible_party FROM apartments WHERE id = \$1 AND site_code = \$2 FOR KEY SHARE$/, (_s, p) => ok(p[0] === 11 ? [{ id: '11', responsible_party: responsible }] : [])],
      [/^SELECT user_code FROM users WHERE user_code = \$1 AND deleted_at IS NULL FOR KEY SHARE$/, (_s, p) => ok([{ user_code: p[0] }])],
      [/FROM ledger_entries l WHERE l\.site_code = \$1 AND l\.idempotency_key = \$2/, () => ok(existing ? [existing] : [])],
      [/^SELECT m\.id, m\.account_id/, () => ok([])],
      [/FROM finance_period_closures WHERE site_code = \$1 AND period >= \$2::DATE/, () => ok(closed ? [{ x: 1 }] : [])],
      [/SELECT bool_or\(is_active\) AS has_active FROM finance_accounts/, () => ok(accounts ? [{ has_active: true }] : [])],
      [/FROM ledger_entries l WHERE l\.site_code = \$1 AND l\.apartment_id = \$2/, () => ok(ledgerRows)],
      [/SELECT a\.responsible_party, EXISTS/, () => ok([{ responsible_party: responsible, has_tenant: hasTenant }])],
      [/^INSERT INTO ledger_entries/, (_s, p) => {
        insertedParams = p;
        return ok([{ id: '901' }]);
      }],
      [/FROM finance_settings/, () => ok(autoIssue ? [{ receipts_auto_issue: true }] : [{ receipts_auto_issue: false }])],
      [/FROM receipts r/, () => ok([])],
      [/^(SAVEPOINT|RELEASE SAVEPOINT|ROLLBACK TO SAVEPOINT) /, () => ok()],
      [/^INSERT INTO audit_log/, () => ok()],
    ]);
    client.inserted = () => insertedParams;
    return client;
  }

  it('hesap verilirse o hesaba yazar; kaynak izi manual; kilit sırası daire -> kullanıcı -> defter; makbuz kapalıysa receiptId null', async () => {
    const client = paymentClient();
    const result = await postPayment(client, { ...base, accountParty: 'tenant', sourceKind: 'manual', sourceId: null });
    assert.equal(result.entryId, 901);
    assert.equal(result.receiptId, null);
    assert.equal(result.replayed, false);
    assert.equal(result.accountParty, 'tenant');
    const order = client.calls.map((c) => c.sql);
    const at = (re) => order.findIndex((sql) => re.test(sql));
    assert.ok(at(/FROM apartments WHERE id = \$1/) < at(/FROM users WHERE user_code/));
    assert.ok(at(/FROM users WHERE user_code/) < at(/^INSERT INTO ledger_entries/));
    const params = client.inserted();
    const insertSql = order[at(/^INSERT INTO ledger_entries/)];
    assert.match(insertSql, /account_party, source_kind, source_id/);
    assert.ok(params.includes('tenant') && params.includes('manual'));
    assert.ok(params.includes('-25000'), 'defterde negatif tutar');
  });

  it('hesap verilmezse (eski istemci) vadesi en eski açık borcu olan hesap seçilir', async () => {
    const ledgerRows = [
      { id: '1', account_party: 'owner', kind: 'charge', amount_minor: '100', entry_date: '2026-05-01', due_date: '2026-05-05', reverses_entry_id: null },
      { id: '2', account_party: null, payer_party: 'tenant', kind: 'charge', amount_minor: '100', entry_date: '2026-04-01', due_date: '2026-04-05', reverses_entry_id: null },
    ];
    const client = paymentClient({ ledgerRows });
    const result = await postPayment(client, { ...base, accountParty: null });
    assert.equal(result.accountParty, 'tenant');
    assert.ok(client.inserted().includes('tenant'));
  });

  it('aynı anahtar: aynı gövde = aynı kayıt (replayed); farklı hesap / tutar = 409 IDEMPOTENCY_CONFLICT; hesap verilmemişse hesap karşılaştırılmaz', async () => {
    const existing = { id: '77', kind: 'payment', apartment_id: '11', amount_minor: '-25000', entry_date: '2026-10-20', method: 'cash', account_party: 'owner', payer_party: 'both', source_kind: 'manual', source_id: null };
    const same = paymentClient({ existing });
    const replay = await postPayment(same, { ...base, accountParty: 'owner' });
    assert.deepEqual([replay.replayed, replay.entryId], [true, 77]);
    assert.equal(same.inserted(), null);
    const omitted = await postPayment(paymentClient({ existing }), { ...base, accountParty: null });
    assert.equal(omitted.replayed, true);
    await assert.rejects(() => postPayment(paymentClient({ existing }), { ...base, accountParty: 'tenant' }), (e) => e.code === 'IDEMPOTENCY_CONFLICT');
    await assert.rejects(() => postPayment(paymentClient({ existing }), { ...base, accountParty: 'owner', amountMinor: 1 }), (e) => e.code === 'IDEMPOTENCY_CONFLICT');
    await assert.rejects(
      () => postPayment(paymentClient({ existing }), { ...base, accountParty: 'owner', sourceKind: 'bank_line', sourceId: 5 }),
      (e) => e.code === 'IDEMPOTENCY_CONFLICT',
      'aynı anahtar başka kaynakla',
    );
  });

  it('ikinci inceleme: kaynak izi (dalga 2: dekont / banka satırı / devir / kart) AYNEN yazılır; aynı anahtar + başka kaynak TÜRÜ ya da başka kaynak KİMLİĞİ ayrı ayrı 409', async () => {
    const client = paymentClient();
    const posted = await postPayment(client, { ...base, accountParty: 'owner', sourceKind: 'bank_line', sourceId: 7001 });
    assert.equal(posted.replayed, false);
    assert.deepEqual(client.inserted().slice(10), ['owner', 'bank_line', 7001, null], 'INSERT: account_party, source_kind, source_id, fund (kısıtsız = NULL)');
    const existing = { id: '78', kind: 'payment', apartment_id: '11', amount_minor: '-25000', entry_date: '2026-10-20', method: 'cash', account_party: 'owner', payer_party: 'both', source_kind: 'bank_line', source_id: '7001' };
    const replay = await postPayment(paymentClient({ existing }), { ...base, accountParty: 'owner', sourceKind: 'bank_line', sourceId: 7001 });
    assert.deepEqual([replay.replayed, replay.entryId], [true, 78]);
    // yalnız tür farklı (aynı kimlik): dekont 7001 ile banka satırı 7001 aynı tahsilat DEĞİLDİR
    await assert.rejects(
      () => postPayment(paymentClient({ existing }), { ...base, accountParty: 'owner', sourceKind: 'payment_notice', sourceId: 7001 }),
      (e) => e.code === 'IDEMPOTENCY_CONFLICT',
      'aynı kimlik, başka kaynak türü',
    );
    // yalnız kimlik farklı (aynı tür)
    await assert.rejects(
      () => postPayment(paymentClient({ existing }), { ...base, accountParty: 'owner', sourceKind: 'bank_line', sourceId: 7002 }),
      (e) => e.code === 'IDEMPOTENCY_CONFLICT',
      'aynı tür, başka kaynak kimliği',
    );
    // kaynak verilmeyen (yönetici) istek kaynaklı kaydı tekrar saymaz
    await assert.rejects(() => postPayment(paymentClient({ existing }), { ...base, accountParty: 'owner' }), (e) => e.code === 'IDEMPOTENCY_CONFLICT', 'kaynaksız istek');
  });

  it('kapalı dönem 409 PERIOD_CLOSED (yazılmaz); daire başka sitede 404; geçersiz hesap / kaynak 400; kaynak kimliği türsüz olamaz', async () => {
    const closed = paymentClient({ closed: true });
    await assert.rejects(() => postPayment(closed, { ...base, accountParty: 'owner' }), (e) => e.code === 'PERIOD_CLOSED');
    assert.equal(closed.inserted(), null);
    await assert.rejects(() => postPayment(paymentClient(), { ...base, apartmentId: 12, accountParty: 'owner' }), (e) => e.code === 'APARTMENT_NOT_FOUND');
    await assert.rejects(() => postPayment(paymentClient(), { ...base, accountParty: 'both' }), (e) => e.code === 'INVALID_BODY');
    await assert.rejects(() => postPayment(paymentClient(), { ...base, accountParty: 'owner', sourceKind: 'iban' }), (e) => e.code === 'INVALID_BODY');
    await assert.rejects(() => postPayment(paymentClient(), { ...base, accountParty: 'owner', sourceKind: null, sourceId: 3 }), (e) => e.code === 'INVALID_BODY');
    await assert.rejects(() => postPayment(paymentClient(), { ...base, accountParty: 'owner', amountMinor: 0 }), (e) => e.code === 'INVALID_BODY');
    await assert.rejects(() => postPayment(paymentClient(), { ...base, accountParty: 'owner', paidOn: '2026-10-22' }), (e) => e.code === 'INVALID_BODY', 'gelecek tarih');
  });

  it('sitede etkin kasa / banka hesabı varsa ve cashAccountId verilmediyse 409 ACCOUNT_REQUIRED (Faz 4b kuralı korunur)', async () => {
    await assert.rejects(() => postPayment(paymentClient({ accounts: true }), { ...base, accountParty: 'owner' }), (e) => e.code === 'ACCOUNT_REQUIRED');
  });
});
