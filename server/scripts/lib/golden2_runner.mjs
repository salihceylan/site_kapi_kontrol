// Altın veri seti 2'nin GERÇEK servislerle (HTTP'siz) çalıştırıcısı. Kullananlar:
//   * server/scripts/qa_finance_golden2_pg.mjs  (yerel QA PostgreSQL: beklenen bakiyeleri doğrular, iki koşuyu karşılaştırır)
//   * tools/demo_seed/golden_site.mjs           (aynı siteyi demo tohumu olarak kurar; hedef koruması ve geri alma kaydıyla)
// Girdi ve BEKLENEN değerler server/test/fixtures/finance_golden_site_2.js içindedir (elle hesap); bu dosya yalnız uygular ve GÖZLEMLER.
// `observed` kimlik / zaman damgası / rastgele kod içermez (daire etiketleri, tutarlar, durum kodları): iki koşunun özeti (digest) birebir aynı olmalıdır.
// SABİT SAAT: bütün servis çağrılarına `now = GOLDEN2_CLOCK.nowIso` verilir; sonuçlar çalıştırma gününden bağımsızdır.
//
// `load(göreli_yol)`: sunucu dizinine göre modül yükleyici (örn. 'src/modules/finance_service.js'); çağıran verir (QA: kendi dizini, demo: --server-dir).
// `q(sql, params)`: SQL çalıştırıcı (QA: pool.query; demo: yakalama kancalı havuz). Servisler kendi havuzlarını (src/db.js) kullanır.

import { createHash } from 'node:crypto';
import {
  GOLDEN2_ACCOUNTS,
  GOLDEN2_APARTMENTS,
  GOLDEN2_BLOCK,
  GOLDEN2_CLOCK,
  GOLDEN2_DEFINITIONS,
  GOLDEN2_LABELS,
  GOLDEN2_LATE_FEE_SETTINGS,
  GOLDEN2_OPENING,
  GOLDEN2_OWNER_PAYMENTS_A4,
  GOLDEN2_OWNER_PAYMENT_A4_TOTAL,
  GOLDEN2_PAYMENTS,
  GOLDEN2_SITE_NAME,
} from '../../test/fixtures/finance_golden_site_2.js';

/** Anahtarları sıralı, kararlı JSON (BigInt metne çevrilir). */
export function canonicalJson(value) {
  const normalize = (item) => {
    if (typeof item === 'bigint') return String(item);
    if (Array.isArray(item)) return item.map(normalize);
    if (item && typeof item === 'object') return Object.fromEntries(Object.keys(item).sort().map((key) => [key, normalize(item[key])]));
    return item;
  };
  return JSON.stringify(normalize(value));
}
export const digestOf = (value) => createHash('sha256').update(canonicalJson(value)).digest('hex');

const NOW = new Date(GOLDEN2_CLOCK.nowIso);
const n = (value) => Number(value);
const SERVICE_MODULES = {
  finance: 'src/modules/finance_service.js',
  ledger: 'src/modules/finance_ledger_service.js',
  accounts: 'src/modules/finance_accounts.js',
  liability: 'src/modules/finance_liability_service.js',
  refunds: 'src/modules/finance_refunds.js',
  funds: 'src/modules/finance_funds_service.js',
  lateFee: 'src/modules/finance_late_fee.js',
  imports: 'src/modules/bulk_import_service.js',
  parties: 'src/modules/finance_parties.js',
  m1: 'src/modules/finance_m1.js',
};

/** Sunucu servislerini yükler (adlandırılmış kısayollar). */
export async function loadGolden2Services(load) {
  const services = {};
  for (const [name, path] of Object.entries(SERVICE_MODULES)) services[name] = await load(path);
  return services;
}

/** Hata yakalayıcı: { status, code } ya da null (hata yok). */
export async function failureOf(fn) {
  try {
    await fn();
    return null;
  } catch (error) {
    return { status: error.statusCode ?? error.status ?? null, code: error.code ?? null };
  }
}

/**
 * Siteyi kurar (site, blok, 6 daire, kullanıcılar, malik / kiracı kayıtları, yönetici bağı) ve altın senaryoyu çalıştırır.
 * @returns {{ siteCode: number, manager: object, users: object[], apartments: Record<string, number>, observed: object }}
 */
export async function runGolden2({
  load,
  q,
  siteName = GOLDEN2_SITE_NAME,
  suffixSiteCode = true,
  emailDomain = 'demo.invalid',
  passwordHashFor = () => 'x',
  appReady = false,
  services = null,
  log = () => {},
}) {
  const S = services ?? (await loadGolden2Services(load));
  const { pool } = await load('src/db.js');
  const observed = {};
  const rowsOf = async (sql, params = []) => (await q(sql, params)).rows;
  const oneOf = async (sql, params = []) => (await rowsOf(sql, params))[0];

  // --- site, blok, daireler -------------------------------------------------------------------------------------------------------------------
  const siteCode = n((await oneOf(`SELECT COALESCE(MAX(site_code), 1000000000) + 1 AS c FROM sites`)).c);
  await q(`INSERT INTO sites (site_code, name, approval_status, approved_at) VALUES ($1, $2, 'approved', NOW())`, [siteCode, suffixSiteCode ? `${siteName} #${siteCode}` : siteName]);
  await q(`INSERT INTO site_modules (site_code, module_code, enabled) VALUES ($1, 'finance', TRUE) ON CONFLICT DO NOTHING`, [siteCode]);
  const blockId = n((await oneOf(`INSERT INTO site_blocks (site_code, block_name, sort_order) VALUES ($1, $2, 1) RETURNING id`, [siteCode, GOLDEN2_BLOCK])).id);
  const apartmentId = {};
  for (const [index, apt] of GOLDEN2_APARTMENTS.entries()) {
    apartmentId[apt.label] = n(
      (
        await oneOf(
          `INSERT INTO apartments (site_code, block_id, unit_label, sort_order, land_share_numerator, land_share_denominator, category, responsible_party)
           VALUES ($1, $2, $3, $4, $5, $6, $7, $8) RETURNING id`,
          [siteCode, blockId, apt.unit, index + 1, apt.land[0], apt.land[1], apt.category, apt.responsible],
        )
      ).id,
    );
  }
  const labelOf = Object.fromEntries(Object.entries(apartmentId).map(([label, id]) => [id, label]));

  // --- kullanıcılar: yönetici + her dairede bir malik (+ kiracılı dairede bir kiracı) -----------------------------------------------------------------
  const people = [{ key: 'manager', fullName: 'Altın Yönetici', role: 'site_manager' }];
  for (const apt of GOLDEN2_APARTMENTS) {
    people.push({ key: `${apt.label} owner`, fullName: `Altın Malik ${apt.label}`, role: 'apartment_owner', apartment: apt.label, relation: 'owner' });
    if (apt.tenant) people.push({ key: `${apt.label} tenant`, fullName: `Altın Kiracı ${apt.label}`, role: 'apartment_owner', apartment: apt.label, relation: 'tenant' });
  }
  const taken = new Set((await rowsOf(`SELECT user_code FROM users WHERE user_code BETWEEN 70000 AND 79999`)).map((row) => n(row.user_code)));
  let nextCode = 70000;
  const users = [];
  for (const person of people) {
    while (taken.has(nextCode)) nextCode += 1;
    taken.add(nextCode);
    // kullanıcı kodu tekildir; e-posta site koduna DEĞİL ona bağlanır (site silinse de kullanıcılar kalır: kod yeniden kullanılsa bile e-posta çakışmaz)
    const email = `golden2-${nextCode}-${person.key.replace(/\s+/g, '-').toLowerCase()}@${emailDomain}`;
    await q(
      `INSERT INTO users (user_code, full_name, email, role, password_hash, is_active, email_verified, approval_status) VALUES ($1, $2, $3, $4, $5, TRUE, TRUE, 'approved')`,
      [nextCode, person.fullName, email, person.role, await passwordHashFor(person.key)],
    );
    users.push({ ...person, userCode: nextCode, email });
  }
  const managerUser = users[0];
  await q(`INSERT INTO site_manager_sites (site_code, manager_user_code) VALUES ($1, $2) ON CONFLICT DO NOTHING`, [siteCode, managerUser.userCode]);
  for (const user of users.slice(1)) {
    const person = n((await oneOf(`INSERT INTO site_people (site_code, user_code, full_name) VALUES ($1, $2, $3) RETURNING id`, [siteCode, user.userCode, user.fullName])).id);
    await q(
      `INSERT INTO apartment_residencies (site_code, apartment_id, person_id, relation, is_current, move_in_date, origin) VALUES ($1, $2, $3, $4, TRUE, '2025-01-01', 'manual')`,
      [siteCode, apartmentId[user.apartment], person, user.relation],
    );
  }
  const MANAGER = { id: managerUser.userCode, user_code: managerUser.userCode, userCode: managerUser.userCode, role: 'site_manager', full_name: managerUser.fullName, email: managerUser.email };
  const key = (label) => `g2-${siteCode}-${label}`;
  log(`Site #${siteCode} kuruldu: ${GOLDEN2_LABELS.length} daire, ${users.length} kullanıcı`);

  // --- hesaplar (Kasa, Banka) -----------------------------------------------------------------------------------------------------------------------
  const accountId = {};
  for (const account of GOLDEN2_ACCOUNTS) {
    const created = await S.accounts.createAccount({
      siteCode,
      body: { name: account.name, kind: account.kind, opening_balance_minor: account.openingBalanceMinor, opening_date: account.openingDate, idempotency_key: key(`acc-${account.key}`) },
      actor: MANAGER,
      now: NOW,
    });
    accountId[account.key] = n(created.account.id);
  }

  // --- okuma yardımcıları ---------------------------------------------------------------------------------------------------------------------------
  const partySql = S.parties.accountPartySql('l');
  const emptyBalances = () => ({ owner: Object.fromEntries(GOLDEN2_LABELS.map((l) => [l, 0])), tenant: Object.fromEntries(GOLDEN2_LABELS.map((l) => [l, 0])) });
  const balances = async () => {
    const result = emptyBalances();
    for (const row of await rowsOf(`SELECT l.apartment_id, ${partySql} AS party, SUM(l.amount_minor)::TEXT AS s FROM ledger_entries l WHERE l.site_code = $1 GROUP BY 1, 2`, [siteCode])) {
      result[row.party][labelOf[n(row.apartment_id)]] = n(row.s);
    }
    return result;
  };
  const balanceOf = async (label, party) =>
    n((await oneOf(`SELECT COALESCE(SUM(l.amount_minor), 0)::TEXT AS s FROM ledger_entries l WHERE l.site_code = $1 AND l.apartment_id = $2 AND ${partySql} = $3`, [siteCode, apartmentId[label], party])).s);
  const accountBalance = async (name) =>
    n((await oneOf(`SELECT COALESCE(SUM(m.amount_minor), 0)::TEXT AS s FROM account_movements m INNER JOIN finance_accounts a ON a.id = m.account_id WHERE m.site_code = $1 AND a.name = $2`, [siteCode, name])).s);
  /** Bir hesabın [ad, vade, M1 kalanı] listesi (ters kaydı olmayan borçlar, vade sırasıyla; ödemeler + devir alacağı alacak). `skipIds` karşılaştırma için bazı satırları çıkarır. */
  const openItems = async (label, party, { withoutOpeningCredit = false } = {}) => {
    const rows = await rowsOf(
      `SELECT l.id, l.kind, l.amount_minor::TEXT AS amount, l.definition_name, to_char(COALESCE(l.due_date, l.entry_date), 'YYYY-MM-DD') AS due, l.reverses_entry_id, l.source_kind
       FROM ledger_entries l WHERE l.site_code = $1 AND l.apartment_id = $2 AND ${partySql} = $3 ORDER BY l.id`,
      [siteCode, apartmentId[label], party],
    );
    const reversed = new Set(rows.filter((row) => row.kind === 'reversal').map((row) => n(row.reverses_entry_id)));
    const charges = rows.filter((row) => row.kind === 'charge' && !reversed.has(n(row.id))).sort((a, b) => (a.due < b.due ? -1 : a.due > b.due ? 1 : n(a.id) - n(b.id)));
    const credits = rows.filter((row) => row.kind === 'payment' && !(withoutOpeningCredit && row.source_kind === 'opening'));
    const pay = credits.reduce((acc, row) => acc - BigInt(row.amount), 0n);
    const { rem } = S.m1.m1Remainders(charges.map((row) => ({ amount: BigInt(row.amount) })), pay);
    return charges.map((row, index) => [row.definition_name, row.due, n(rem[index])]);
  };
  const candidateBody = (list) => ({
    count: list.count,
    total_minor: list.total_minor,
    truncated: list.truncated,
    items: list.items.map((item) => ({
      apartment: labelOf[item.apartment_id],
      reason: item.reason,
      tenant_present: item.tenant_present,
      has_owner: item.has_owner,
      can_transfer: item.can_transfer,
      item_count: item.item_count,
      total_minor: item.total_minor,
      oldest_due_date: item.oldest_due_date,
    })),
  });
  const candidateBrief = (list) => list.items.map((item) => ({ apartment: labelOf[item.apartment_id], total_minor: item.total_minor }));
  const transferRows = async (label) => {
    const rows = await rowsOf(
      `SELECT l.kind, ${partySql} AS party, l.amount_minor::TEXT AS amount FROM ledger_entries l WHERE l.site_code = $1 AND l.apartment_id = $2 AND l.source_kind = 'liability_transfer' ORDER BY l.id`,
      [siteCode, apartmentId[label]],
    );
    const sums = {};
    for (const row of rows) sums[`${row.party} ${row.kind}`] = (sums[`${row.party} ${row.kind}`] ?? 0) + n(row.amount);
    return { writtenRows: rows.length, sums };
  };
  const previewBody = (preview) => ({
    has_owner: preview.has_owner,
    can_transfer: preview.can_transfer,
    item_count: preview.item_count,
    total_minor: preview.total_minor,
    tenant_balance_minor: preview.tenant_balance_minor,
    owner_balance_minor: preview.owner_balance_minor,
    items: preview.items.map((item) => ({ name: item.name, due_date: item.due_date, original_minor: item.original_minor, remaining_minor: item.remaining_minor, paid_minor: item.paid_minor, fund: item.fund })),
  });

  // --- 1. devir alacağı (K16): A-5'e -500,00 TL ------------------------------------------------------------------------------------------------------
  {
    const rows = GOLDEN2_OPENING.rows.map((row, index) => ({ n: index + 1, cells: { blok: GOLDEN2_BLOCK, daire_no: GOLDEN2_APARTMENTS.find((a) => a.label === row.apartment).unit, tutar: row.cell } }));
    const body = { spec_version: 1, rows, options: { cutover_date: GOLDEN2_OPENING.cutoverDate } };
    const preview = await S.imports.previewImport({ siteCode, kind: 'opening_balances', body });
    if (preview.totals.error !== 0) throw new Error(`devir alacağı önizlemesi hatalı: ${JSON.stringify(preview.issues)}`);
    const credit = GOLDEN2_OPENING.rows.reduce((acc, row) => acc - row.minor, 0);
    const committed = await S.imports.commitImport({
      siteCode,
      kind: 'opening_balances',
      body: { ...body, options: { cutover_date: GOLDEN2_OPENING.cutoverDate, expected_total_minor: 0, expected_credit_total_minor: credit }, expected_hash: preview.preview_hash, idempotency_key: key('opening') },
      actor: MANAGER,
    });
    const entry = await oneOf(
      `SELECT l.apartment_id, l.kind, l.amount_minor::TEXT AS amount, ${partySql} AS party, l.source_kind, l.due_date FROM ledger_entries l WHERE l.site_code = $1 AND l.source_kind = 'opening'`,
      [siteCode],
    );
    observed.opening = {
      rowCount: n(preview.plan.opening_credit_add),
      committedStatus: committed.status,
      creditTotalMinor: credit,
      entry: { apartment: labelOf[n(entry.apartment_id)], kind: entry.kind, amount: n(entry.amount), account: entry.party, source: entry.source_kind, due: entry.due_date },
    };
  }

  // --- 2. borçlandırmalar: aylık aidat (kategori) x 2 dönem, asansör (sabit), çatı (arsa payı) -----------------------------------------------------------
  observed.runs = {};
  const readRun = async (name, runId, total, count) => {
    const rows = await rowsOf(`SELECT l.apartment_id, l.amount_minor::TEXT AS amount, ${partySql} AS party, l.fund FROM ledger_entries l WHERE l.site_code = $1 AND l.run_id = $2 AND l.kind = 'charge' ORDER BY l.apartment_id`, [siteCode, runId]);
    observed.runs[name] = {
      total_minor: n(total),
      apartment_count: count,
      rows: Object.fromEntries(rows.map((row) => [labelOf[n(row.apartment_id)], { amount: n(row.amount), account: row.party, fund: row.fund }])),
    };
  };
  {
    const def = GOLDEN2_DEFINITIONS.aidat;
    const definition = await S.finance.createDefinition({
      siteCode,
      body: { name: def.name, kind: def.kind, distribution: def.distribution, category_amounts: def.categoryAmounts, due_day: def.dueDay, start_period: def.startPeriod, target: { type: 'site' } },
      actor: MANAGER,
    });
    for (const period of def.periods) {
      const preview = await S.finance.previewDefinition({ siteCode, rawId: String(definition.id), body: { period }, now: NOW });
      const posted = await S.finance.postDefinition({
        siteCode,
        rawId: String(definition.id),
        body: { period, expected_total_minor: preview.total_minor, expected_apartment_count: preview.apartment_count, expected_hash: preview.preview_hash, idempotency_key: key(`aidat-${period}`) },
        actor: MANAGER,
        now: NOW,
      });
      await readRun(`${def.name} ${period}`, n(posted.run.id), posted.run.total_minor, posted.run.apartment_count);
    }
  }
  observed.balancesAfterAidat = await balances();

  // --- 3. ödemeler (çatıdan ÖNCE: yalnız İşletme borcu açıkken hesap seçimi gerekmez) -------------------------------------------------------------------
  const pay = (payment) =>
    S.ledger.recordPayment({
      siteCode,
      body: {
        apartment_id: apartmentId[payment.apartment],
        amount_minor: payment.amountMinor,
        entry_date: payment.date,
        method: payment.method,
        account_id: accountId[payment.account],
        account_party: payment.party,
        idempotency_key: key(`pay-${payment.id}`),
        ...(payment.fund ? { fund: payment.fund } : {}),
      },
      actor: MANAGER,
      now: NOW,
    });
  for (const payment of GOLDEN2_PAYMENTS) await pay(payment);
  observed.balancesAfterPayments = await balances();

  // --- 3b. tek seferlik borçlar: asansör (daire başı sabit) ve çatı (arsa payı) - YALNIZ bugünün tarihiyle yazılır -----------------------------------------
  for (const [slug, def] of [['asansor', GOLDEN2_DEFINITIONS.asansor], ['cati', GOLDEN2_DEFINITIONS.cati]]) {
    const body = {
      name: def.name,
      distribution: def.distribution,
      amount_minor: def.amountMinor,
      charge_party: def.chargeParty,
      due_date: def.dueDate,
      target: { type: 'site' },
      ...(def.decisionReason ? { decision_reason: def.decisionReason } : {}),
    };
    const preview = await S.finance.previewCharge({ siteCode, body, now: NOW });
    const posted = await S.finance.postCharge({
      siteCode,
      body: { ...body, expected_total_minor: preview.total_minor, expected_apartment_count: preview.apartment_count, expected_hash: preview.preview_hash, idempotency_key: key(`charge-${slug}`) },
      actor: MANAGER,
      now: NOW,
    });
    await readRun(def.name, n(posted.run.id), posted.run.total_minor, posted.run.apartment_count);
  }
  observed.balancesAfterOneTime = await balances();
  observed.openItems = {
    'A-2 tenant': await openItems('A-2', 'tenant'),
    'A-5 owner': await openItems('A-5', 'owner'),
    'A-5 owner (devir alacağı olmasaydı)': await openItems('A-5', 'owner', { withoutOpeningCredit: true }),
  };

  // --- 4. K17: gecikmiş kiracı borcu -> malike devir adayları ---------------------------------------------------------------------------------------
  observed.candidatesBefore = candidateBody(await S.liability.listTransferCandidates(siteCode, NOW));
  const attention = async () => {
    const result = await S.liability.tenantDebtOverdueAttention(pool, siteCode, NOW);
    return { count: result.count, total_minor: result.total_minor };
  };
  observed.attentionBefore = await attention();

  // --- 5. A-2: devir + geri alma (K1) --------------------------------------------------------------------------------------------------------------
  {
    const label = 'A-2';
    const preview = await S.liability.previewLiabilityTransfer(siteCode, apartmentId[label], NOW);
    const transfer = await S.liability.createLiabilityTransfer({
      siteCode,
      rawApartmentId: apartmentId[label],
      body: { expected_total_minor: preview.total_minor, expected_hash: preview.preview_hash, reason: 'Kiracı Ekim aidatını ödemedi (altın veri seti 2)', idempotency_key: key('a2-devir') },
      actor: MANAGER,
      now: NOW,
    });
    const history1 = await S.liability.listLiabilityTransfers(siteCode, apartmentId[label]);
    const afterTransfer = {
      tenant: await balanceOf(label, 'tenant'),
      owner: await balanceOf(label, 'owner'),
      ...(await transferRows(label)),
      candidates: candidateBrief(await S.liability.listTransferCandidates(siteCode, NOW)),
      reversible: history1.items.find((item) => n(item.id) === n(transfer.transfer.id))?.reversible,
    };
    await S.liability.reverseLiabilityTransfer({ siteCode, rawId: transfer.transfer.id, body: { reason: 'Kiracı ödedi (altın veri seti 2)', idempotency_key: key('a2-geri') }, actor: MANAGER, now: NOW });
    const history2 = await S.liability.listLiabilityTransfers(siteCode, apartmentId[label]);
    const afterReverse = {
      tenant: await balanceOf(label, 'tenant'),
      owner: await balanceOf(label, 'owner'),
      ...(await transferRows(label)),
      candidates: candidateBrief(await S.liability.listTransferCandidates(siteCode, NOW)),
      transferReversible: history2.items.find((item) => n(item.id) === n(transfer.transfer.id))?.reversible,
    };
    const reverseTwice = await failureOf(() => S.liability.reverseLiabilityTransfer({ siteCode, rawId: transfer.transfer.id, body: { reason: 'tekrar', idempotency_key: key('a2-geri-2') }, actor: MANAGER, now: NOW }));
    observed.a2 = { preview: previewBody(preview), afterTransfer, afterReverse, reverseTwice };
  }

  // --- 6. A-4: "kiracı vermezse malik öder" (K17) ---------------------------------------------------------------------------------------------------
  {
    const label = 'A-4';
    const preview = await S.liability.previewLiabilityTransfer(siteCode, apartmentId[label], NOW);
    const transferBody = (total) => ({ expected_total_minor: total, expected_hash: preview.preview_hash, reason: 'Kiracı ödemedi, malik öder (altın veri seti 2)', idempotency_key: key(`a4-devir-${total}`) });
    const staleTotal = await failureOf(() => S.liability.createLiabilityTransfer({ siteCode, rawApartmentId: apartmentId[label], body: transferBody(preview.total_minor + 1), actor: MANAGER, now: NOW }));
    const transfer = await S.liability.createLiabilityTransfer({ siteCode, rawApartmentId: apartmentId[label], body: transferBody(preview.total_minor), actor: MANAGER, now: NOW });
    const afterTransfer = {
      tenant: await balanceOf(label, 'tenant'),
      owner: await balanceOf(label, 'owner'),
      ...(await transferRows(label)),
      candidates: candidateBrief(await S.liability.listTransferCandidates(siteCode, NOW)),
    };
    // K3: iki türün de (İşletme: devredilen kalemler, Fon: çatı) açık borcu var -> hesap seçimi olmadan ödeme reddedilir; hiçbir satır yazılmaz
    let fundChoice = null;
    try {
      await pay({ ...GOLDEN2_OWNER_PAYMENTS_A4[0], id: 'P8-nofund', amountMinor: GOLDEN2_OWNER_PAYMENT_A4_TOTAL, fund: undefined });
    } catch (error) {
      fundChoice = {
        status: error.statusCode ?? null,
        code: error.code ?? null,
        open: error.extra?.fund_choice?.open ?? null,
        balanceUnchanged: await balanceOf(label, 'owner'),
      };
    }
    for (const payment of GOLDEN2_OWNER_PAYMENTS_A4) await pay(payment);
    const afterOwnerPayment = { tenant: await balanceOf(label, 'tenant'), owner: await balanceOf(label, 'owner') };
    const reverseBlocked = await failureOf(() => S.liability.reverseLiabilityTransfer({ siteCode, rawId: transfer.transfer.id, body: { reason: 'malik ödedikten sonra', idempotency_key: key('a4-geri') }, actor: MANAGER, now: NOW }));
    const afterBlockedReverse = { tenant: await balanceOf(label, 'tenant'), owner: await balanceOf(label, 'owner') };
    observed.a4 = { preview: previewBody(preview), staleTotal, fundChoice, afterTransfer, afterOwnerPayment, reverseBlocked, afterBlockedReverse };
  }
  observed.attentionAfter = await attention();

  // --- 7. A-3: onaylı alacak iadesi (K4) -----------------------------------------------------------------------------------------------------------
  {
    const label = 'A-3';
    const creditBefore = -(await balanceOf(label, 'owner'));
    const request = (amount, tag) =>
      S.refunds.createManagerRefundRequest({ siteCode, body: { apartment_id: apartmentId[label], account_party: 'owner', amount_minor: amount, note: 'Fazla ödeme iadesi (altın veri seti 2)', idempotency_key: key(`iade-${tag}`) }, actor: MANAGER });
    const tooMuch = await failureOf(() => request(creditBefore + 5000, 'fazla'));
    const requested = await request(100000, 'ok');
    const approve = (tag) => S.refunds.approveRefund({ siteCode, rawId: requested.refund.id, body: { pay_account_id: accountId.kasa, idempotency_key: key(`iade-onay-${tag}`) }, actor: MANAGER, now: NOW });
    const approved = await approve('1');
    const approveTwice = await failureOf(() => approve('2'));
    const ownerBalanceAfter = await balanceOf(label, 'owner');
    observed.refund = {
      credit_before_minor: creditBefore,
      tooMuch,
      approved: {
        status: approved.refund.status,
        amount_minor: approved.refund.amount_minor,
        method: approved.refund.pay_method,
        account: approved.refund.pay_account_name,
        receiptSeq: Number(String(approved.refund.receipt?.number ?? '').split('-')[2]),
      },
      ownerBalanceAfter,
      creditAfter: Math.max(0, -ownerBalanceAfter),
      approveTwice,
      accountBalances: { Kasa: await accountBalance('Kasa'), Banka: await accountBalance('Banka') },
    };
  }

  // --- 8. gecikme tazminatı planı (Ekim 2026; yazmaz) ----------------------------------------------------------------------------------------------
  {
    const plan = await S.lateFee.computeLateFeePlan(pool, siteCode, {
      period: GOLDEN2_LATE_FEE_SETTINGS.period,
      settings: GOLDEN2_LATE_FEE_SETTINGS.settings,
      excluded: [],
    });
    observed.lateFee = {
      total_minor: n(plan.total),
      lines: plan.lines
        .map((line) => ({ apartment: labelOf[n(line.apartmentId)], account: line.accountParty, base_day: n(line.baseDay), amount: n(line.amount) }))
        .sort((a, b) => (a.apartment < b.apartment ? -1 : a.apartment > b.apartment ? 1 : a.account < b.account ? -1 : 1)),
    };
  }

  // --- 9. son durum ---------------------------------------------------------------------------------------------------------------------------------
  {
    const final = await balances();
    const owner = Object.values(final.owner).reduce((acc, v) => acc + v, 0);
    const tenant = Object.values(final.tenant).reduce((acc, v) => acc + v, 0);
    const charged = n((await oneOf(`SELECT COALESCE(SUM(amount_minor), 0)::TEXT AS s FROM ledger_entries WHERE site_code = $1 AND kind = 'charge' AND COALESCE(source_kind, '') <> 'liability_transfer'`, [siteCode])).s);
    const credited = -n((await oneOf(`SELECT COALESCE(SUM(amount_minor), 0)::TEXT AS s FROM ledger_entries WHERE site_code = $1 AND kind = 'payment'`, [siteCode])).s);
    const transferNet = n((await oneOf(`SELECT COALESCE(SUM(amount_minor), 0)::TEXT AS s FROM ledger_entries WHERE site_code = $1 AND source_kind = 'liability_transfer'`, [siteCode])).s);
    const fundSummary = await S.funds.getFundSummary(siteCode);
    observed.final = {
      balances: final,
      totals: { owner, tenant, all: owner + tenant },
      ledgerIdentity: { charged_minor: charged, credited_minor: credited, transfer_net_minor: transferNet },
      funds: {
        operating_collections_minor: fundSummary.funds.operating.collections_minor,
        capital_collections_minor: fundSummary.funds.capital.collections_minor,
        advance_minor: fundSummary.advance_minor,
        accounts_total_minor: fundSummary.accounts_total_minor,
        balanced: fundSummary.balanced,
      },
    };
  }

  // --- uygulamada açılabilir site (yalnız demo tohumu): yönetici üyeliği, abonelik satırı, temel modüller. Senaryodan SONRA: Karar Defteri gibi bir temel modül açılırsa
  // çatı borçlandırması gerekçe yerine karar isterdi (K2); senaryo kapalı modülle çalışır.
  if (appReady) {
    await q(`INSERT INTO site_memberships (site_code, user_code, role, is_active) VALUES ($1, $2, 'SITE_ADMIN', TRUE) ON CONFLICT (site_code, user_code) DO NOTHING`, [siteCode, managerUser.userCode]);
    await q(`INSERT INTO site_subscriptions (site_code, plan_code, status, source) VALUES ($1, 'manual_approval', 'active', 'admin')`, [siteCode]);
    const { enableCoreModulesForSite } = await load('src/modules/core_modules.js');
    await enableCoreModulesForSite({ query: (sql, params) => q(sql, params) }, siteCode);
  }

  return { siteCode, manager: managerUser, users, apartments: apartmentId, observed };
}

/** Gözlenen değeri beklenenle karşılaştırır; ilk farkın yolunu döndürür (yoksa null). Yalnız beklenen anahtarlar denetlenir. */
export function firstDifference(actual, expected, path = '') {
  if (expected === null || typeof expected !== 'object') {
    return Object.is(actual, expected) ? null : `${path}: gözlenen ${JSON.stringify(actual)} != beklenen ${JSON.stringify(expected)}`;
  }
  if (Array.isArray(expected)) {
    if (!Array.isArray(actual) || actual.length !== expected.length) return `${path}: dizi uzunluğu ${Array.isArray(actual) ? actual.length : typeof actual} != ${expected.length}`;
    for (let i = 0; i < expected.length; i += 1) {
      const diff = firstDifference(actual[i], expected[i], `${path}[${i}]`);
      if (diff) return diff;
    }
    return null;
  }
  if (actual === null || typeof actual !== 'object') return `${path}: nesne bekleniyordu, gözlenen ${JSON.stringify(actual)}`;
  for (const k of Object.keys(expected)) {
    const diff = firstDifference(actual[k], expected[k], path ? `${path}.${k}` : k);
    if (diff) return diff;
  }
  return null;
}
