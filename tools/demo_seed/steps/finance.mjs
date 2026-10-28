// Aidat ve Finans: hesaplar, aidat tanimlari, 46 aylik borclandirma, tahsilat, gider, aktarim, mutabakat, ay kapatma.
// Modul: finance. Uygulamanin KENDI servisleri cagrilir (zaman benzetimi icin `now` parametresiyle); dogrudan SQL yalniz
// servisi olmayan kayitlar (dekont bildirimi, banka satiri) icindir.

import { fakeIban, fakePhone } from '../lib/identity.mjs';
import {
  AVG_DUES_TL, SUPPLIERS, TR_MONTHS, adjustPaymentDate, buildRawExpenses, chronicPartial, monthLabel, planChargePayments, profileOfIndex, simulateAccounts,
} from '../lib/finance_plan.mjs';
import { addDays, monthsBetween, noonIstanbul, ymOf } from '../lib/util.mjs';

const EXTRA_CHARGES = [
  { date: '2024-03-04', due: '2024-03-25', name: 'Asansör Modernizasyonu Katkı Payı (1/2)', mult: 2.0 },
  { date: '2024-04-04', due: '2024-04-25', name: 'Asansör Modernizasyonu Katkı Payı (2/2)', mult: 2.0 },
  { date: '2025-05-06', due: '2025-05-26', name: 'Dış Cephe Boya ve Onarım Katkı Payı (1/4)', mult: 2.0 },
  { date: '2025-06-05', due: '2025-06-25', name: 'Dış Cephe Boya ve Onarım Katkı Payı (2/4)', mult: 2.0 },
  { date: '2025-07-07', due: '2025-07-25', name: 'Dış Cephe Boya ve Onarım Katkı Payı (3/4)', mult: 2.0 },
  { date: '2025-08-05', due: '2025-08-25', name: 'Dış Cephe Boya ve Onarım Katkı Payı (4/4)', mult: 2.0 },
];
const EXPENSE_RATIO = { 2023: 0.97, 2024: 1.03, 2025: 0.96, 2026: 0.95 };

export async function seedFinance(ctx) {
  const { q, rng, site, apartments, manager, svc, TODAY, START, log, batchId } = ctx;
  const siteCode = site.code;
  const actor = { user_code: manager.user_code, full_name: manager.full_name, role: manager.role };
  const N = apartments.length;
  const key = (kind, n) => `${batchId}:${kind}:${n}`.slice(0, 64);
  const stats = { charges: 0, payments: 0, expenses: 0, transfers: 0, errors: [] };

  // ---- 0) hesaplar, ayarlar -----------------------------------------------------------------------------------------------------
  const dues = {};
  for (const [y, avg] of Object.entries(AVG_DUES_TL)) dues[Number(y)] = Math.round(N * avg * 100);
  const firstYearTotal = dues[2023];

  // ---- 1) aidat tanimlari ve borclandirma (2023-01 .. bu ay) ---------------------------------------------------------------------
  // Hesap acilmadan once borclandirma yapilabilir (hesap yalniz tahsilat/gider icin zorunlu).
  // Dagitim ARSA PAYINA gore ('land_share'): m2 dagitimi kaldirildi (sunucu 'area' icin 400 AREA_DISTRIBUTION_REMOVED verir); arsa paylari
  // people adiminda dairelerin goreli buyuklugune oranli yazilir, boylece daire basina aidat yine farkli ve toplam tam tutardir.
  const defs = {};
  for (const y of [2023, 2024, 2025, 2026]) {
    const created = await svc.finance_service.createDefinition({
      siteCode,
      actor,
      body: {
        name: `Aylık Aidat ${y}`,
        kind: 'recurring',
        distribution: 'land_share',
        amount_minor: dues[y],
        due_day: 10,
        start_period: `${y}-01-01`,
        end_period: `${y}-12-01`,
        target: { type: 'site' },
        charge_party: 'occupant',
      },
    });
    defs[y] = created;
  }
  const months = monthsBetween(ymOf(START), ymOf(TODAY));
  let runN = 0;
  for (const ym of months) {
    const y = Number(ym.slice(0, 4));
    const period = `${ym}-01`;
    const now = noonIstanbul(period);
    const def = defs[y];
    const preview = await svc.finance_service.previewDefinition({ siteCode, rawId: def.id, body: { period }, now });
    await svc.finance_service.postDefinition({
      siteCode,
      rawId: def.id,
      actor,
      now,
      body: {
        period,
        expected_total_minor: preview.total_minor,
        expected_apartment_count: preview.apartment_count,
        expected_hash: preview.preview_hash,
        idempotency_key: key('run', (runN += 1)),
      },
    });
  }
  for (const extra of EXTRA_CHARGES) {
    const y = Number(extra.date.slice(0, 4));
    const now = noonIstanbul(extra.date);
    const body = {
      name: extra.name,
      amount_minor: Math.round(dues[y] * extra.mult),
      distribution: 'land_share',
      target: { type: 'site' },
      due_date: extra.due,
      charge_party: 'owner',
    };
    const preview = await svc.finance_service.previewCharge({ siteCode, body, now });
    await svc.finance_service.postCharge({
      siteCode,
      actor,
      now,
      body: { ...body, expected_total_minor: preview.total_minor, expected_apartment_count: preview.apartment_count, expected_hash: preview.preview_hash, idempotency_key: key('charge', extra.date) },
    });
  }
  const chargeRows = (
    await q(
      `SELECT id, apartment_id, COALESCE(account_party, CASE WHEN payer_party = 'tenant' THEN 'tenant' ELSE 'owner' END) AS account_party,
              amount_minor::TEXT AS amount_minor, to_char(entry_date, 'YYYY-MM-DD') AS entry_date, to_char(due_date, 'YYYY-MM-DD') AS due_date,
              to_char(period, 'YYYY-MM-DD') AS period, definition_name
       FROM ledger_entries WHERE site_code = $1 AND kind = 'charge' ORDER BY entry_date, id`,
      [siteCode],
    )
  ).rows.map((r) => ({ ...r, id: Number(r.id), apartment_id: Number(r.apartment_id), isMonthly: String(r.definition_name).startsWith('Aylık Aidat') }));
  stats.charges = chargeRows.length;
  log(`Finans: ${months.length} ay borclandirildi, ${chargeRows.length} borc satiri`);

  // ---- 2) tahsilat plani ----------------------------------------------------------------------------------------------------------
  const aptIndexById = new Map(apartments.map((a) => [a.id, a.index]));
  const cashLovers = new Set(apartments.filter((a) => a.index % 3 === 1).map((a) => a.id));
  const payEvents = [];
  const byApt = new Map();
  for (const c of chargeRows) {
    if (!byApt.has(c.apartment_id)) byApt.set(c.apartment_id, []);
    byApt.get(c.apartment_id).push(c);
  }
  const prepayQuarterFor = (charge) => {
    const mi = Number(charge.entry_date.slice(5, 7)) - 1;
    if (mi % 3 !== 0) return [];
    return [{ date: addDays(charge.entry_date, 4), amountMinor: Number(charge.amount_minor) * 3 }];
  };
  for (const [aptId, list] of byApt) {
    const idx = aptIndexById.get(aptId) ?? 0;
    const profileBase = profileOfIndex(idx);
    for (const c of list) {
      const profile = profileBase === 'prepay' && !c.isMonthly ? 'punctual' : profileBase;
      const plan = planChargePayments({ profile, aptSeed: idx, charge: c, rng, today: TODAY, start: START, prepayQuarterFor });
      for (const p of plan) {
        const pref = cashLovers.has(aptId) ? rng.chance(0.8) : rng.chance(0.1);
        const method = profile === 'prepay' ? (rng.chance(0.15) ? 'cheque' : 'transfer') : pref ? 'cash' : rng.chance(0.02) ? 'cheque' : 'transfer';
        const date = adjustPaymentDate(p.date, method);
        if (date > TODAY) continue;
        payEvents.push({ kind: 'payment', date, amountMinor: p.amountMinor, aptId, party: c.account_party, method, chargeId: c.id, period: c.entry_date.slice(0, 7), profile });
      }
    }
    for (const p of chronicPartial(profileBase, list, TODAY)) {
      const charge = list.find((c) => c.id === p.chargeId);
      payEvents.push({ kind: 'payment', date: adjustPaymentDate(p.date, 'transfer'), amountMinor: p.amountMinor, aptId, party: charge.account_party, method: 'transfer', chargeId: p.chargeId, period: charge.entry_date.slice(0, 7), profile: 'partial' });
    }
  }
  const collectionsByYear = {};
  for (const e of payEvents) collectionsByYear[e.date.slice(0, 4)] = (collectionsByYear[e.date.slice(0, 4)] ?? 0) + e.amountMinor;

  // ---- 3) gider plani ---------------------------------------------------------------------------------------------------------------
  const raw = buildRawExpenses({ dues, start: START, today: TODAY, rng });
  const rawByYear = {};
  for (const e of raw) rawByYear[e.date.slice(0, 4)] = (rawByYear[e.date.slice(0, 4)] ?? 0) + e.raw;
  const scaleByYear = {};
  for (const y of Object.keys(rawByYear)) scaleByYear[y] = (EXPENSE_RATIO[y] * (collectionsByYear[y] ?? 0)) / rawByYear[y];
  const docSeq = {};
  const expenseEvents = raw.map((e, i) => {
    const scale = scaleByYear[e.date.slice(0, 4)];
    const step = e.key && String(e.key).startsWith('salary') ? 5000 : 1000;
    let amountMinor = Math.max(step, Math.round((e.raw * scale) / step) * step);
    if (e.doc === 'invoice' && step === 1000) amountMinor += rng.int(0, 99);
    const monthlyTotal = dues[Number(e.date.slice(0, 4))];
    const small = amountMinor < 0.07 * monthlyTotal && !String(e.key).startsWith('salary') && e.key !== 'manager' && e.key !== 'bank';
    const from = small && rng.chance(0.55) ? 'cash' : 'bank';
    const year = e.date.slice(0, 4);
    docSeq[year] = (docSeq[year] ?? 0) + 1;
    return { kind: 'expense', ...e, amountMinor, from, docNo: e.doc === 'none' ? null : `${e.doc === 'invoice' ? 'FTR' : 'MKB'}-${year}-${String(docSeq[year]).padStart(4, '0')}`, n: i + 1 };
  });

  // ---- 4) kasa/banka benzetimi -> acilis bakiyeleri ve aktarimlar ------------------------------------------------------------------
  const monthlyTotalOf = (d) => dues[Number(d.slice(0, 4))];
  const sim = simulateAccounts({
    collections: payEvents.map((e) => ({ date: e.date, amountMinor: e.amountMinor, to: e.method === 'cash' ? 'cash' : 'bank' })),
    expenses: expenseEvents.map((e) => ({ date: e.date, amountMinor: e.amountMinor, from: e.from })),
    monthlyTotalOf,
    start: START,
    today: TODAY,
  });
  const openCash = Math.round(Math.max(0, -sim.minCash) + 0.3 * firstYearTotal);
  const openBank = Math.round(Math.max(0, -sim.minBank) + 1.1 * firstYearTotal);
  log(`Gider plani: ${expenseEvents.length} kalem; tahsilat plani: ${payEvents.length} odeme; aktarim: ${sim.transfers.length}; acilis kasa=${openCash / 100} banka=${openBank / 100}`);

  // ---- 5) hesaplar, tedarikciler, kategoriler, odeme bilgisi ----------------------------------------------------------------------
  const nowOpen = noonIstanbul(addDays(START, 1));
  const cashAccount = (await svc.finance_accounts.createAccount({
    siteCode, actor, now: nowOpen,
    body: { name: 'Kasa (Nakit)', kind: 'cash', opening_balance_minor: openCash, opening_date: START, note: 'Site kasası (demo)', idempotency_key: key('acc', 'cash') },
  })).account;
  const bankAccount = (await svc.finance_accounts.createAccount({
    siteCode, actor, now: nowOpen,
    body: { name: 'Aidat Hesabı (Demo Banka)', kind: 'bank', opening_balance_minor: openBank, opening_date: START, note: 'Sahte IBAN - demo veri', idempotency_key: key('acc', 'bank') },
  })).account;
  const iban = fakeIban(siteCode % 100000);
  await svc.finance_payment_info.putBankDetails({ siteCode, rawId: bankAccount.id, actor, body: { iban, payee_name: `${site.name} Yönetimi (SAHTE IBAN)`.slice(0, 70) } });
  let prefixSet = 'CNK';
  try {
    await svc.finance_payment_info.putPaymentSettings({ siteCode, actor, body: { prefix: prefixSet, resident_account_id: bankAccount.id, notices_enabled: true } });
  } catch (error) {
    prefixSet = null;
    log(`Odeme ayarlari onek olmadan yazilacak (${error.code ?? error.message})`);
    await svc.finance_payment_info.putPaymentSettings({ siteCode, actor, body: { resident_account_id: bankAccount.id, notices_enabled: true } });
  }
  try {
    await svc.finance_payment_info.ensureApartmentCodes(siteCode);
  } catch (error) {
    log(`Daire kodlari uretilemedi: ${error.code ?? error.message}`);
  }

  await svc.finance_expenses.ensureDefaultCategories(svc.pool, siteCode);
  const categories = new Map((await q(`SELECT id, name FROM expense_categories WHERE site_code = $1`, [siteCode])).rows.map((r) => [r.name, Number(r.id)]));
  const neededCats = new Set(['Temizlik hizmeti', 'Peyzaj ve Bahçe', 'Kırtasiye ve Ofis', 'Diğer', ...expenseEvents.map((e) => e.cat)]);
  for (const extraCat of neededCats) {
    if (!categories.has(extraCat)) {
      const res = await svc.finance_expenses.createCategory({ siteCode, actor, body: { name: extraCat } });
      categories.set(extraCat, Number(res.category.id));
    }
  }
  const suppliers = new Map();
  for (const s of SUPPLIERS) {
    try {
      const res = await svc.finance_expenses.createSupplier({ siteCode, actor, body: { name: s.name, phone: `0 500 000 ${String(rng.int(0, 99)).padStart(2, '0')} ${String(rng.int(0, 99)).padStart(2, '0')}` } });
      suppliers.set(s.key, { id: Number(res.supplier.id), name: s.name });
    } catch (error) {
      const found = await q(`SELECT id FROM finance_suppliers WHERE site_code = $1 AND lower(name) = lower($2)`, [siteCode, s.name]);
      if (!found.rows[0]) throw error;
      suppliers.set(s.key, { id: Number(found.rows[0].id), name: s.name });
    }
  }

  // ---- 6) olaylari tarih sirasiyla uygula --------------------------------------------------------------------------------------------
  const byDate = new Map();
  const put = (e) => {
    if (!byDate.has(e.date)) byDate.set(e.date, []);
    byDate.get(e.date).push(e);
  };
  for (const e of payEvents) put({ ...e, order: 1 });
  for (const t of sim.transfers) put({ kind: 'transfer', order: t.phase === 'pre' ? 2 : 4, ...t });
  for (const e of expenseEvents) put({ ...e, order: 3 });
  const accountId = (name) => (name === 'cash' ? cashAccount.id : bankAccount.id);
  const expenseRefs = [];
  let payN = 0;
  let trN = 0;
  const fail = (what, error) => {
    stats.errors.push(`${what}: ${error?.code ?? ''} ${error?.message ?? error}`);
    if (stats.errors.length > 25) throw new Error(`Cok fazla hata:\n${stats.errors.join('\n')}`);
  };
  for (const date of [...byDate.keys()].sort()) {
    const now = noonIstanbul(date);
    for (const e of byDate.get(date).sort((a, b) => a.order - b.order)) {
      try {
        if (e.kind === 'payment') {
          payN += 1;
          const desc = e.profile === 'partial' ? `${monthLabel(e.period)} aidatına kısmi ödeme` : `${monthLabel(e.period)} aidat ödemesi`;
          await svc.finance_ledger_service.recordPayment({
            siteCode, actor, now,
            body: {
              apartment_id: e.aptId, amount_minor: e.amountMinor, entry_date: date, method: e.method, account_party: e.party,
              account_id: accountId(e.method === 'cash' ? 'cash' : 'bank'), description: desc, idempotency_key: key('pay', payN),
            },
          });
          stats.payments += 1;
        } else if (e.kind === 'transfer') {
          trN += 1;
          await svc.finance_accounts.createTransfer({
            siteCode, actor, now,
            body: { from_account_id: accountId(e.from), to_account_id: accountId(e.to), amount_minor: e.amountMinor, transfer_date: date, description: e.description, idempotency_key: key('tr', trN) },
          });
          stats.transfers += 1;
        } else {
          const supplier = e.supplier ? suppliers.get(e.supplier) : null;
          const vatRate = date < '2023-07-10' ? 18 : 20;
          const body = {
            category_id: categories.get(e.cat) ?? categories.get('Diğer'),
            supplier_id: supplier ? supplier.id : null,
            description: e.text,
            amount_minor: e.amountMinor,
            expense_date: date,
            account_id: accountId(e.from),
            document_kind: e.doc,
            document_no: e.docNo,
            nature: e.nature,
            idempotency_key: key('exp', e.n),
          };
          if (e.doc === 'invoice') body.vat_minor = Math.round((e.amountMinor * vatRate) / (100 + vatRate));
          const res = await svc.finance_expenses.createExpense({ siteCode, actor, now, body });
          const id = Number(res.expense?.id ?? res.id);
          expenseRefs.push({ id, key: e.key, equip: e.equip, funded: e.funded ?? null, date, amountMinor: e.amountMinor, cat: e.cat, text: e.text, supplierKey: e.supplier });
          stats.expenses += 1;
        }
      } catch (error) {
        fail(`${e.kind} ${date}`, error);
      }
    }
  }
  log(`Finans yazildi: tahsilat=${stats.payments} gider=${stats.expenses} aktarim=${stats.transfers} hata=${stats.errors.length}`);
  if (stats.errors.length) log(`  ilk hatalar: ${stats.errors.slice(0, 3).join(' | ')}`);

  // ---- 7) mutabakat -------------------------------------------------------------------------------------------------------------------
  const balanceAsOf = async (accountIdValue, asOf) => {
    const r = await q(
      `SELECT COALESCE(SUM(m.amount_minor), 0)::TEXT AS b FROM account_movements m
       WHERE m.site_code = $1 AND m.account_id = $2
         AND ((m.movement_date <= $3::DATE AND NOT EXISTS (SELECT 1 FROM account_reconciliations r WHERE r.adjustment_movement_id = m.id))
              OR EXISTS (SELECT 1 FROM account_reconciliations r WHERE r.adjustment_movement_id = m.id AND r.as_of_date <= $3::DATE))`,
      [siteCode, accountIdValue, asOf],
    );
    return Number(r.rows[0].b);
  };
  const recon = [
    { acc: bankAccount, asOf: '2023-12-31', diff: 0, note: 'Yıl sonu banka ekstresi ile mutabakat' },
    { acc: bankAccount, asOf: '2024-12-31', diff: -3500, adjust: { reason_code: 'bank_fee', note: 'Hesap işletim ücreti farkı' }, note: 'Banka ekstresi farkı düzeltildi' },
    { acc: cashAccount, asOf: '2025-06-30', diff: 0, note: 'Kasa sayımı' },
    { acc: bankAccount, asOf: '2025-12-31', diff: 0, note: 'Yıl sonu banka ekstresi ile mutabakat' },
    { acc: bankAccount, asOf: '2026-06-30', diff: 1275, adjust: { reason_code: 'bank_interest', note: 'Vadesiz hesap faiz geliri' }, note: 'Haziran sonu mutabakatı' },
    { acc: cashAccount, asOf: '2026-09-30', diff: 0, note: 'Eylül sonu kasa sayımı' },
  ];
  let reconCount = 0;
  for (const r of recon) {
    if (r.asOf > TODAY) continue;
    try {
      const computed = await balanceAsOf(r.acc.id, r.asOf);
      await svc.finance_accounts.createReconciliation({
        siteCode, actor, rawId: r.acc.id, now: noonIstanbul(addDays(r.asOf, 1)),
        body: {
          as_of_date: r.asOf, statement_balance_minor: computed + r.diff, expected_computed_minor: computed, note: r.note,
          ...(r.adjust ? { adjust: r.adjust } : {}), idempotency_key: key('rec', `${r.acc.id}-${r.asOf}`),
        },
      });
      reconCount += 1;
    } catch (error) {
      fail(`mutabakat ${r.asOf}`, error);
    }
  }

  // ---- 8) dekont bildirimleri (bekleyen) ve eslesmemis banka satirlari --------------------------------------------------------------
  const lastCharges = [...byApt.entries()].map(([aptId, list]) => ({ aptId, last: list[list.length - 1] }));
  const pendingTargets = lastCharges.filter((x) => x.last && x.last.entry_date.startsWith(ymOf(TODAY))).slice(0, 2);
  let noticeCount = 0;
  for (const t of pendingTargets) {
    const submitter = ctx.peopleResult.peopleByApt.get(t.aptId)?.find((m) => m.role === 'head') ?? null;
    await q(
      `INSERT INTO payment_notices (site_code, apartment_id, account_party, origin, submitted_by, amount_minor, paid_on, method, sender_name, sender_iban, description, status, file_required, submitted_at)
       VALUES ($1, $2, $3, 'resident_app', $4, $5, $6::DATE, 'transfer', $7, $8, $9, 'pending', FALSE, $10::timestamptz)`,
      [siteCode, t.aptId, t.last.account_party, submitter?.userCode ?? null, Number(t.last.amount_minor), addDays(TODAY, -2), submitter?.fullName ?? null, fakeIban(Number(t.aptId) + 77), 'Ekim aidat ödemesi (dekont bekliyor)', `${addDays(TODAY, -2)}T14:20:00+03:00`],
    );
    noticeCount += 1;
  }
  // Banka satir ice aktarimi (eslesmemis satirlar): sahte ekstre
  const importRes = await q(
    `INSERT INTO bank_imports (site_code, account_id, format, file_name, file_size, file_sha256, statement_from, statement_to, line_count, status, idempotency_key, request_fingerprint, created_by, created_at)
     VALUES ($1, $2, 'csv', 'demo-ekstre-2026-10.csv', 2048, $3, $4::DATE, $5::DATE, 4, 'active', $6, $7, $8, $9::timestamptz) RETURNING id`,
    [siteCode, bankAccount.id, 'a'.repeat(64), addDays(TODAY, -20), TODAY, key('bimp', 1), 'b'.repeat(64), manager.user_code, `${addDays(TODAY, -1)}T10:00:00+03:00`],
  );
  const importId = Number(importRes.rows[0].id);
  const bankLines = [
    ['Havale - Aidat Ekim', 480000, 'Demo Gönderen 1'],
    ['EFT bilinmeyen gönderen', 125000, 'Demo Gönderen 2'],
    ['Havale ek ödeme', 350000, 'Demo Gönderen 3'],
    ['Hesap işletim ücreti', -3500, null],
  ];
  for (const [i, [desc, amount, name]] of bankLines.entries()) {
    await q(
      `INSERT INTO bank_statement_lines (import_id, site_code, account_id, line_no, value_date, amount_minor, description, counterparty_name, fingerprint, status)
       VALUES ($1, $2, $3, $4, $5::DATE, $6, $7, $8, $9, 'unmatched')`,
      [importId, siteCode, bankAccount.id, i + 1, addDays(TODAY, -15 + i * 3), amount, desc, name, `demo-line-${importId}-${i + 1}`.padEnd(64, '0')],
    );
  }

  return { defs, accounts: { cash: cashAccount, bank: bankAccount }, categories, suppliers, expenseRefs, stats, dues, collectionsByYear, rawByYear, scaleByYear, reconCount, noticeCount, sim, iban, key, byApt, chargeRows };
}

/** Ay kapatma: cagiran TUM finans yazimlari bittikten sonra cagirir (kapali doneme yazilamaz). */
export async function closeFinancePeriods(ctx, throughYm) {
  const { svc, manager, site, TODAY, log } = ctx;
  const actor = { user_code: manager.user_code, full_name: manager.full_name, role: manager.role };
  await svc.finance_ledger_service.closePeriod({ siteCode: site.code, rawPeriod: throughYm, actor, now: noonIstanbul(TODAY) });
  log(`Ay kapatma: ${throughYm} dahil kapali`);
}

export { TR_MONTHS, fakePhone };
