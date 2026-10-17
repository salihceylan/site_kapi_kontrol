// Finans Faz 4b QA bolumu: E. Raporlar + disa aktarma (O5). scripts/qa_finance4b.mjs tarafindan yuklenir (t = ortak test ortami).

const mulberry32 = (seed) => () => {
  let a = (seed += 0x6d2b79f5);
  a = Math.imul(a ^ (a >>> 15), a | 1);
  a ^= a + Math.imul(a ^ (a >>> 7), a | 61);
  return ((a ^ (a >>> 14)) >>> 0) / 4294967296;
};

export default async function sectionReports(t) {
  const { check, q, call, hooks, TODAY, dayNo, ago, monthStart, ym, mkManaged, mkUser, addPerson, addResidency, P, key, failMessage, users, sleep } = t;
  const { MGR, BOARD, STAFF, OUTSIDER, RESIDENT, MGR2, SUPER } = users;
  console.log('--- E. raporlar ---');
  const rnd = mulberry32(20261017);
  const randInt = (min, max) => min + Math.floor(rnd() * (max - min + 1)); // yalniz TEST girdisi uretir; para hesabi degil
  const periodOf = (iso) => `${iso.slice(0, 7)}-01`;
  const BUCKETS = ['not_due', 'd0_30', 'd31_60', 'd61_90', 'd91_180', 'd181_365', 'd366_plus'];

  const site = await mkManaged('F4B Rapor Sitesi', { 'R Blok': 14 });
  const owner = await mkUser('Rapor Malik Ayse Kaya', 'apartment_owner');
  await addResidency(site.code, site.ids[0], await addPerson(site.code, { user: owner }), 'owner');
  const tenantPerson = await addPerson(site.code, { name: 'Rapor Kiraci Mehmet Demir' });
  await addResidency(site.code, site.ids[0], tenantPerson, 'tenant');

  // --- rastgele defter (dogrudan SQL; tarihler bugune kadar)
  const insert = async (apartmentId, kind, amount, entryDate, due, extra = {}) => {
    const cols = ['site_code', 'apartment_id', 'kind', 'amount_minor', 'period', 'entry_date', 'due_date', 'payer_party', 'method', 'reverses_entry_id', 'late_fee_run_id', 'definition_name'];
    const vals = [site.code, apartmentId, kind, amount, periodOf(entryDate), entryDate, due, 'both', kind === 'payment' ? 'cash' : null, extra.reverses ?? null, extra.lateFee ?? null, extra.name ?? null];
    return Number((await q(`INSERT INTO ledger_entries (${cols.join(', ')}) VALUES (${cols.map((_, i) => `$${i + 1}`).join(', ')}) RETURNING id`, vals)).rows[0].id);
  };
  const model = new Map(); // apartmentId -> satirlar (JS referans M1 icin)
  for (const apartmentId of site.ids) {
    const rows = [];
    const addRow = async (kind, amount, entryDate, due, extra = {}) => {
      const id = await insert(apartmentId, kind, amount, entryDate, due, extra);
      const row = { id, kind, amount: BigInt(amount), entryDate, due, reverses: extra.reverses ?? null };
      rows.push(row);
      return row;
    };
    const chargeCount = randInt(0, 12);
    const charges = [];
    for (let i = 0; i < chargeCount; i += 1) {
      const due = ago(randInt(-40, 420));
      const entryDate = ago(Math.max(0, Math.min(randInt(0, 460), Math.max(0, dayNo(TODAY) - dayNo(due)) + 30)));
      const entry = entryDate > TODAY ? TODAY : entryDate;
      charges.push(await addRow('charge', randInt(1000, 90000), entry, due));
    }
    const payCount = randInt(0, 8);
    const payments = [];
    for (let i = 0; i < payCount; i += 1) payments.push(await addRow('payment', -randInt(500, 80000), ago(randInt(0, 400)), null));
    for (const charge of charges) {
      if (rnd() < 0.12) await addRow('reversal', -Number(charge.amount), ago(randInt(0, Math.max(0, dayNo(TODAY) - dayNo(charge.entryDate)))), charge.due, { reverses: charge.id });
    }
    for (const payment of payments) {
      if (rnd() < 0.15) await addRow('reversal', -Number(payment.amount), ago(randInt(0, Math.max(0, dayNo(TODAY) - dayNo(payment.entryDate)))), null, { reverses: payment.id });
    }
    model.set(apartmentId, rows);
  }

  // saf JS referans M1 (T tarihinde): kova toplamlari
  const referenceAging = (rows, asOf) => {
    const reversedAt = new Map();
    for (const r of rows) if (r.kind === 'reversal') reversedAt.set(r.reverses, r.entryDate);
    const alive = (r) => r.entryDate <= asOf && !(reversedAt.has(r.id) && reversedAt.get(r.id) <= asOf);
    const items = rows.filter((r) => r.kind === 'charge' && alive(r)).sort((a, b) => ((a.due ?? a.entryDate) === (b.due ?? b.entryDate) ? a.id - b.id : (a.due ?? a.entryDate) < (b.due ?? b.entryDate) ? -1 : 1));
    let payTotal = 0n;
    for (const r of rows) if (r.kind === 'payment' && alive(r)) payTotal += -r.amount;
    const out = Object.fromEntries(BUCKETS.map((b) => [b, 0n]));
    let cumulative = 0n;
    for (const item of items) {
      cumulative += item.amount;
      const open = cumulative - payTotal;
      const rem = open < 0n ? 0n : open < item.amount ? open : item.amount;
      const due = item.due ?? item.entryDate;
      const days = dayNo(asOf) - dayNo(due);
      const bucket = days < 0 ? 'not_due' : days <= 30 ? 'd0_30' : days <= 60 ? 'd31_60' : days <= 90 ? 'd61_90' : days <= 180 ? 'd91_180' : days <= 365 ? 'd181_365' : 'd366_plus';
      out[bucket] += rem;
    }
    const credit = payTotal > cumulative ? payTotal - cumulative : 0n;
    return { buckets: out, credit };
  };

  const aging = await call('GET', `${P(site.code)}/reports/aging?status=all&limit=500`, MGR);
  const balances = await call('GET', `${P(site.code)}/balances?limit=200`, MGR);
  const balById = new Map(balances.body.items.map((b) => [b.apartment_id, b]));
  const overdueEq = aging.body.items.every((item) => BigInt(item.d0_30_minor + item.d31_60_minor + item.d61_90_minor + item.d91_180_minor + item.d181_365_minor + item.d366_plus_minor) === BigInt(balById.get(item.apartment_id).overdue_minor));
  check('E1: DEGISMEZ: as_of = bugun icin Σ(d0_30…d366_plus) = 4a overdue_minor (HER daire; rastgele defter, ters kayitli borc / odeme dahil)', aging.status === 200 && aging.body.items.length === 14 && overdueEq, aging.body.items?.filter((i) => BigInt(i.d0_30_minor + i.d31_60_minor + i.d61_90_minor + i.d91_180_minor + i.d181_365_minor + i.d366_plus_minor) !== BigInt(balById.get(i.apartment_id).overdue_minor)).slice(0, 2));
  const balanceEq = aging.body.items.every((item) => {
    const total = BigInt(item.not_due_minor) + BigInt(item.total_overdue_minor) - BigInt(item.credit_minor);
    return total === BigInt(balById.get(item.apartment_id).balance_minor);
  });
  check('E1b: DEGISMEZ: vadesi gelmemis + gecikmis - alacak = bakiye (daire bazinda) ve toplamlar bakiye listesiyle ayni', balanceEq && aging.body.totals.total_overdue_minor === balances.body.items.reduce((a, b) => a + b.overdue_minor, 0));
  let referenceOk = true;
  const referenceDetail = [];
  for (const asOf of [TODAY, ago(30), ago(120), ago(250), ago(500)]) {
    const res = await call('GET', `${P(site.code)}/reports/aging?status=all&limit=500&as_of=${asOf}`, MGR);
    for (const item of res.body.items) {
      const ref = referenceAging(model.get(item.apartment_id), asOf);
      const got = Object.fromEntries(BUCKETS.map((b) => [b, BigInt(item[`${b}_minor`])]));
      const ok = BUCKETS.every((b) => got[b] === ref.buckets[b]) && BigInt(item.credit_minor) === ref.credit;
      if (!ok) {
        referenceOk = false;
        referenceDetail.push({ asOf, apartment: item.apartment_id, got: item, ref });
      }
    }
  }
  check('E2: TARIHLI MODEL: gecmis as_of (bugun, -30, -120, -250, -500 gun) SQL kovalari saf JS M1 referansiyla BIREBIR (14 daire x 5 tarih)', referenceOk, referenceDetail.slice(0, 1));
  const first = aging.body.items.find((i) => i.owner_name !== null);
  check('E2b: yaslandirma satirinda malik / kiraci adi (yonetici) ve toplamlar; items total_overdue DESC siralidir', first?.owner_name === 'Rapor Malik Ayse Kaya' && first.tenant_name === 'Rapor Kiraci Mehmet Demir' && aging.body.items.every((item, i, list) => i === 0 || list[i - 1].total_overdue_minor >= item.total_overdue_minor), first);
  const debtorOnly = await call('GET', `${P(site.code)}/reports/aging?status=debtor&limit=3&offset=1`, MGR);
  check('E2c: status=debtor yalniz gecikmisleri listeler; limit / offset; gecersiz as_of 400 / gelecek 400', debtorOnly.body.items.every((i) => i.total_overdue_minor > 0) && debtorOnly.body.items.length <= 3 && (await call('GET', `${P(site.code)}/reports/aging?as_of=2999-01-01`, MGR)).status === 400 && (await call('GET', `${P(site.code)}/reports/aging?as_of=abc`, MGR)).status === 400);

  // gelecek tarihli (entry_date > bugun) borc: 4a esitligi yine korunur (vade > bugun -> vadesi gelmemis)
  await insert(site.ids[13], 'charge', 77700, ym(1) + '-01', ym(1) + '-10');
  const agingFuture = await call('GET', `${P(site.code)}/reports/aging?status=all&limit=500`, MGR);
  const balFuture = await call('GET', `${P(site.code)}/balances?limit=200`, MGR);
  const futureEq = agingFuture.body.items.every((item) => BigInt(item.d0_30_minor + item.d31_60_minor + item.d61_90_minor + item.d91_180_minor + item.d181_365_minor + item.d366_plus_minor) === BigInt(balFuture.body.items.find((b) => b.apartment_id === item.apartment_id).overdue_minor));
  check('E2d: gelecek aya yazilmis borc varken de Σ(gecikmis kovalar) = 4a overdue_minor', futureEq);

  // --- E3. gelir-gider
  const s2 = await mkManaged('F4B Gelir Gider', { 'G Blok': 3 });
  const [g1, g2, g3] = s2.ids;
  const ins2 = (apartmentId, kind, amount, entryDate, due, extra = {}) =>
    q(`INSERT INTO ledger_entries (site_code, apartment_id, kind, amount_minor, period, entry_date, due_date, payer_party, method, reverses_entry_id, late_fee_run_id) VALUES ($1, $2, $3, $4, $5, $6, $7, 'both', $8, $9, $10) RETURNING id`, [s2.code, apartmentId, kind, amount, periodOf(entryDate), entryDate, due, kind === 'payment' ? 'cash' : null, extra.reverses ?? null, extra.lateFee ?? null]);
  const m1 = monthStart(-2);
  const m2 = monthStart(-1);
  await ins2(g1, 'charge', 100000, m1, m1);
  await ins2(g2, 'charge', 100000, m1, m1);
  await ins2(g1, 'payment', -60000, `${m1.slice(0, 7)}-10`, null);
  const cRev = Number((await ins2(g3, 'charge', 5000, m1, m1)).rows[0].id);
  await ins2(g3, 'reversal', -5000, `${m1.slice(0, 7)}-12`, m1, { reverses: cRev });
  await ins2(g2, 'charge', 100000, m2, m2);
  const payB = Number((await ins2(g2, 'payment', -30000, `${m2.slice(0, 7)}-05`, null)).rows[0].id);
  await ins2(g2, 'reversal', 30000, `${m2.slice(0, 7)}-06`, null, { reverses: payB });
  const kasa2 = await call('POST', `${P(s2.code)}/accounts`, MGR, { name: 'Kasa', kind: 'cash', opening_balance_minor: 0, opening_date: ago(90), idempotency_key: key('a') });
  const cat = (await call('GET', `${P(s2.code)}/expense-categories`, MGR)).body.items.find((c) => c.name === 'Elektrik').id;
  const cat2 = (await call('GET', `${P(s2.code)}/expense-categories`, MGR)).body.items.find((c) => c.name === 'Su').id;
  const ex1 = await call('POST', `${P(s2.code)}/expenses`, MGR, { category_id: cat, account_id: kasa2.body.account.id, description: 'Elektrik', amount_minor: 25000, expense_date: ago(75), idempotency_key: key('e1') });
  const ex2 = await call('POST', `${P(s2.code)}/expenses`, MGR, { category_id: cat2, account_id: kasa2.body.account.id, description: 'Su', amount_minor: 4000, expense_date: ago(5), idempotency_key: key('e2') });
  await call('POST', `${P(s2.code)}/expenses/${ex1.body.expense.id}/void`, MGR, { reason: 'iptal', idempotency_key: key('v') });
  const ie = await call('GET', `${P(s2.code)}/reports/income-expense?from=${ym(-3)}&to=${ym(0)}`, MGR);
  const rowOf = (month) => ie.body.months.find((m) => m.period === month);
  check('E3: aylik gelir-gider: net tahakkuk (ters kayit dusuk), tahsilat (ters kayit dusuk), tahsilat orani (bp), veri olmayan ay SATIR olarak 0', ie.status === 200 && ie.body.months.length === 4 && rowOf(ym(-3)).charged_minor === 0 && rowOf(ym(-3)).collected_minor === 0
    && rowOf(ym(-2)).charged_minor === 200000 && rowOf(ym(-2)).collected_minor === 60000 && rowOf(ym(-2)).collection_rate_bp === 3000 && rowOf(ym(-1)).charged_minor === 100000 && rowOf(ym(-1)).collected_minor === 0 && rowOf(ym(-1)).collection_rate_bp === 0, ie.body.months);
  check('E3b: gider NET (gider - iptal) ve iptal edilen gider iptal ayinda negatif; kategori kirilimi; net_cash = tahsilat - gider', ie.body.totals.expense_minor === 4000 && ie.body.totals.charged_minor === 300000 && ie.body.totals.collected_minor === 60000 && ie.body.totals.net_cash_minor === 56000
    && ie.body.expense_by_category.some((c) => c.category_name === 'Su' && c.total_minor === 4000) && !ie.body.expense_by_category.some((c) => c.category_name === 'Elektrik' && c.total_minor !== 0), [ie.body.totals, ie.body.expense_by_category]);
  void ex2;
  check('E3c: 36 aydan uzun aralik 400; ters aralik 400; closed_through basliktadir', (await call('GET', `${P(s2.code)}/reports/income-expense?from=2020-01&to=2026-01`, MGR)).status === 400 && (await call('GET', `${P(s2.code)}/reports/income-expense?from=${ym(0)}&to=${ym(-2)}`, MGR)).status === 400 && 'closed_through' in ie.body && ie.body.currency === 'TRY' && /yerine ge/.test(ie.body.footer));

  // --- E4. kasa durumu
  const cp = await call('GET', `${P(s2.code)}/reports/cash-position`, MGR);
  const accList = await call('GET', `${P(s2.code)}/accounts`, MGR);
  check('E4: kasa durumu: hesap bakiyesi = /accounts bakiyesi; DEGISMEZ Σ bakiye = Σ acilis + Σ hareketler; toplamlar', cp.status === 200 && cp.body.accounts[0].balance_minor === accList.body.items[0].balance_minor
    && cp.body.totals.balance_minor === cp.body.totals.opening_minor + cp.body.totals.collections_minor + cp.body.totals.expenses_minor + cp.body.totals.transfers_in_minor + cp.body.totals.transfers_out_minor + cp.body.totals.adjustments_minor + cp.body.totals.reversals_minor, cp.body);
  const cpPast = await call('GET', `${P(s2.code)}/reports/cash-position?as_of=${ago(40)}`, MGR);
  check('E4b: tarihli model: gecmis as_of icin sonraki hareketler dahil edilmez (gider -75 gun once eklenmisti; bugunku gider dahil degil)', cpPast.status === 200 && cpPast.body.accounts[0].expenses_minor === -25000 && cpPast.body.accounts[0].reversals_minor === 0, cpPast.body.accounts);
  check('E4c: as_of hesabin acilisindan once ise hesap listelenmez', (await call('GET', `${P(s2.code)}/reports/cash-position?as_of=${ago(200)}`, MGR)).body.accounts.length === 0);

  // --- E5. ekstre
  const st = await call('GET', `${P(s2.code)}/apartments/${g2}/statement?from=${m1}&to=${TODAY}`, MGR);
  const lastRunning = st.body.items[st.body.items.length - 1].running_balance_minor;
  check('E5: ekstre: acilis + kalemler = kapanis; son satirin running_balance = closing; ekstre toplamlari; 4a bakiyesiyle ayni', st.status === 200 && st.body.opening_balance_minor === 0 && lastRunning === st.body.closing_balance_minor
    && st.body.items.reduce((a, e) => a + e.amount_minor, st.body.opening_balance_minor) === st.body.closing_balance_minor && st.body.closing_balance_minor === (await call('GET', `${P(s2.code)}/apartments/${g2}/account`, MGR)).body.balance_minor
    && st.body.totals.charged_minor === 200000 && st.body.totals.paid_minor === 30000 && st.body.totals.reversed_minor === 30000, st.body.totals);
  const stOpen = await call('GET', `${P(s2.code)}/apartments/${g2}/statement?from=${m2}&to=${TODAY}`, MGR);
  check('E5b: from sonrasi ekstrede acilis bakiyesi onceki kayitlarin toplamidir (100000)', stOpen.body.opening_balance_minor === 100000, stOpen.body.opening_balance_minor);
  const big = await mkManaged('F4B Buyuk Ekstre', { 'B Blok': 1 });
  await q(`INSERT INTO ledger_entries (site_code, apartment_id, kind, amount_minor, period, entry_date, due_date, payer_party) SELECT $1, $2, 'charge', 100, $3::date, $4::date, $4::date, 'both' FROM generate_series(1, 5001)`, [big.code, big.ids[0], monthStart(0), TODAY]);
  const tooBig = await call('GET', `${P(big.code)}/apartments/${big.ids[0]}/statement?from=${monthStart(0)}`, MGR);
  check('E5c: 5000 satirdan buyuk ekstre 409 STATEMENT_TOO_LARGE; baska siteninin dairesi 404', tooBig.status === 409 && tooBig.body.code === 'STATEMENT_TOO_LARGE' && (await call('GET', `${P(big.code)}/apartments/${g2}/statement`, MGR)).status === 404, tooBig.body);
  const resStatement = await call('GET', `/app/my-finance/apartments/${site.ids[0]}/statement`, owner);
  const resOther = await call('GET', `/app/my-finance/apartments/${site.ids[1]}/statement`, owner);
  check('E5d: sakin ekstresi: yalniz kendi dairesi; yonetici aciklama / olusturan adi YOK; baska daire 404', resStatement.status === 200 && resStatement.body.items.every((e) => e.description === null && e.created_by_name === null && e.reversal_reason === null) && resOther.status === 404, resOther.body);

  // --- E6. kurul ozet raporu
  const bs = await call('GET', `${P(site.code)}/reports/board-summary?from=${ym(-11)}&to=${ym(0)}`, BOARD);
  const names = ['Rapor Malik Ayse Kaya', 'Rapor Kiraci Mehmet Demir', 'F4B Yonetici', 'Otis'];
  check('E6: kurul ozet raporu: bolumler (tahsilat, alacak durumu, gider, kasa, tazminat, hatirlatma, uyarilar); KISI ADI ve borclu listesi YOK', bs.status === 200 && ['collection', 'receivables', 'expenses', 'cash', 'late_fee', 'reminders', 'warnings'].every((k) => k in bs.body) && !('debtor_list' in bs.body)
    && !names.some((n) => JSON.stringify(bs.body).includes(n)) && bs.body.receivables.aging.length === 7, Object.keys(bs.body));
  const bsBoardWants = await call('GET', `${P(site.code)}/reports/board-summary?include_debtor_list=true`, BOARD);
  check('E6b: kurul include_debtor_list=true gonderse bile liste VERILMEZ', bsBoardWants.status === 200 && !('debtor_list' in bsBoardWants.body));
  const auditsBefore = (await q(`SELECT COUNT(*)::int AS n FROM audit_log WHERE site_code = $1 AND action = 'finance.report.debtor_list'`, [site.code])).rows[0].n;
  const bsMgr = await call('GET', `${P(site.code)}/reports/board-summary?include_debtor_list=true`, MGR);
  const auditsAfter = (await q(`SELECT COUNT(*)::int AS n FROM audit_log WHERE site_code = $1 AND action = 'finance.report.debtor_list'`, [site.code])).rows[0].n;
  check('E6c: yonetici borclu listesi (en cok 10 daire: etiket + tutar) alir ve kullanim audit\'e dusuer (yalniz bayrak)', bsMgr.body.debtor_list?.length > 0 && bsMgr.body.debtor_list.length <= 10 && bsMgr.body.debtor_list[0].label && auditsAfter === auditsBefore + 1
    && !(JSON.stringify((await q(`SELECT details FROM audit_log WHERE action = 'finance.report.debtor_list' ORDER BY id DESC LIMIT 1`)).rows[0].details)).includes('R Blok'), bsMgr.body.debtor_list);
  check('E6d: ozet uyarilari: kapanmamis gecmis donem ve (varsa) esleme / mutabakat uyarilari', bs.body.warnings.some((w) => w.code === 'UNCLOSED_PAST_PERIODS') || bs.body.receivables.as_of === TODAY);

  // --- E7. yetki matrisi
  const rows = [];
  for (const [label, user, expectRead, expectExport] of [['yonetici', MGR, 200, 200], ['super', SUPER, 200, 200], ['kurul', BOARD, 200, 403], ['gorevli', STAFF, 403, 403], ['sakin', RESIDENT, 403, 403], ['ilgisiz', OUTSIDER, 403, 403], ['baska site yoneticisi', MGR2, 403, 403]]) {
    const r = await call('GET', `${P(site.code)}/reports/aging`, user);
    const e = await call('GET', `${P(site.code)}/exports/finance_aging`, user);
    rows.push([label, r.status, e.status, expectRead, expectExport]);
  }
  check('E7: yetki matrisi: raporlar yonetici / super / kurul okur; DISA AKTARMA yalniz yonetici / super (kurul 403); gorevli / sakin / ilgisiz / baska site 403', rows.every(([, r, e, er, ee]) => r === er && e === ee), rows);

  // --- E8. disa aktarma zarfi = rapor
  const envAging = await call('GET', `${P(site.code)}/exports/finance_aging?status=all&format=csv`, MGR);
  const sumRows = envAging.body.rows.reduce((a, row) => a + BigInt(row[12]), 0n);
  check('E8: finance_aging zarfi: kind, spec_version 1, filename_base ASCII, columns tipli (money), row_count = rows; toplam gecikmis = ekran toplami (sapma yok)', envAging.status === 200 && envAging.body.kind === 'finance_aging' && envAging.body.spec_version === 1 && /^[a-z0-9_-]+$/.test(envAging.body.filename_base)
    && envAging.body.columns.filter((c) => c.type === 'money').length === 10 && envAging.body.row_count === envAging.body.rows.length && sumRows === BigInt(aging.body.totals.total_overdue_minor) && /no-store/.test(envAging.headers.get('cache-control')), [envAging.body.columns.length, sumRows, aging.body.totals.total_overdue_minor]);
  const envIE = await call('GET', `${P(s2.code)}/exports/finance_income_expense?from=${ym(-3)}&to=${ym(0)}`, MGR);
  check('E8b: finance_income_expense zarfi = rapor JSON (ay sayisi, net tahsilat, tahsilat orani yuzde olarak scale 2)', envIE.status === 200 && envIE.body.row_count === 4 && envIE.body.rows[1][3] === 60000 && envIE.body.rows[1][6] === 30 && envIE.body.columns[6].type === 'number' && envIE.body.columns[6].scale === 2, envIE.body.rows);
  const envCash = await call('GET', `${P(s2.code)}/exports/finance_cash_position`, MGR);
  const envStmt = await call('GET', `${P(s2.code)}/exports/finance_statement?apartment_id=${g2}&from=${m1}`, MGR);
  const envExp = await call('GET', `${P(s2.code)}/exports/finance_expenses?status=all`, MGR);
  const envRec = await call('GET', `${P(site.code)}/exports/finance_receipts`, MGR);
  check('E8c: kasa durumu / ekstre / gider / makbuz zarflari: sutun tipleri, satir sayilari ve toplam satiri; apartment_id yoksa 400; bilinmeyen tur 404',
    envCash.status === 200 && envCash.body.rows[envCash.body.rows.length - 1][0] === 'Toplam' && envStmt.status === 200 && envStmt.body.rows[0][1] === 'Devreden' && envStmt.body.rows.length === st.body.items.length + 1 && envExp.body.row_count === 2 && envExp.body.columns[4].type === 'money'
      && envRec.status === 200 && envRec.body.columns.length === 8 && (await call('GET', `${P(s2.code)}/exports/finance_statement`, MGR)).status === 400 && (await call('GET', `${P(s2.code)}/exports/bilinmeyen`, MGR)).status === 404, [envCash.status, envStmt.status, envExp.body.row_count, envRec.status]);
  const exportAudit = (await q(`SELECT details FROM audit_log WHERE action = 'export' AND site_code = $1 ORDER BY id DESC LIMIT 1`, [site.code])).rows[0]?.details;
  check('E8d: dışa aktarma audit (export): kind, row_count, format, suzgec ADLARI; veri / ad YOK', exportAudit?.kind && exportAudit.row_count >= 0 && Array.isArray(exportAudit.filters) && !JSON.stringify(exportAudit).includes('Rapor Malik'), exportAudit);
  // 20 000 satir siniri
  const huge = await mkManaged('F4B Buyuk Disa Aktarma', { 'H Blok': 1 });
  const hk = await call('POST', `${P(huge.code)}/accounts`, MGR, { name: 'K', kind: 'cash', opening_balance_minor: 0, opening_date: ago(30), idempotency_key: key('hk') });
  const hcat = (await call('GET', `${P(huge.code)}/expense-categories`, MGR)).body.items[0].id;
  await q(`INSERT INTO expenses (site_code, category_id, category_name, description, amount_minor, expense_date, period, account_id, idempotency_key, request_fingerprint)
           SELECT $1, $2, 'x', 'gider ' || g, 100, $3::date, $4::date, $5, 'bulk-' || g, repeat('a', 64) FROM generate_series(1, 20001) g`, [huge.code, hcat, TODAY, monthStart(0), hk.body.account.id]);
  const tooLarge = await call('GET', `${P(huge.code)}/exports/finance_expenses`, MGR);
  check('E8e: 20 000 satir ustu dışa aktarma 422 EXPORT_TOO_LARGE; sinirda (suzgecle daraltilmis) calisir', tooLarge.status === 422 && tooLarge.body.code === 'EXPORT_TOO_LARGE' && (await call('GET', `${P(huge.code)}/exports/finance_expenses?q=${encodeURIComponent('gider 20001')}`, MGR)).status === 200, tooLarge.body);

  // --- E9. tek snapshot, hata = bütün hata, eszamanlilik
  const failed = await (async () => {
    hooks.failOnce = { match: /FROM expense_voids v INNER JOIN expenses e/, code: '57014', times: 1 };
    const res = await call('GET', `${P(s2.code)}/reports/income-expense?from=${ym(-3)}&to=${ym(0)}`, MGR);
    hooks.failOnce = null;
    return res;
  })();
  check('E9: rapor sorgusu ortasinda hata -> BUTUN yanit 5xx ({error, errorId}); kismi sifir / bos veri DONMEZ', failed.status === 500 && typeof failed.body.errorId === 'string' && !('months' in failed.body), failed.body);
  const failedBoard = await (async () => {
    hooks.failOnce = { match: /FROM finance_reminder_runs r INNER JOIN finance_reminder_items i/, code: '57014', times: 1 };
    const res = await call('GET', `${P(site.code)}/reports/board-summary`, BOARD);
    hooks.failOnce = null;
    return res;
  })();
  check('E9b: kurul ozetinin bir bolumu (hatirlatma) basarisizsa BUTUN rapor 5xx (digerleri sifirla dolmaz)', failedBoard.status === 500 && !('collection' in failedBoard.body) && !('warnings' in failedBoard.body), failedBoard.body);
  // tutarlilik: rapor suresince yazilan odeme rapora GIRMEZ (REPEATABLE READ)
  const before = (await call('GET', `${P(s2.code)}/reports/income-expense?from=${ym(0)}&to=${ym(0)}`, MGR)).body.totals.collected_minor;
  let release;
  const gate = new Promise((resolve) => { release = resolve; });
  hooks.pause = { match: /FROM expenses e WHERE e\.site_code = \$1 AND e\.period BETWEEN|SELECT period, category_name, SUM\(total\)/, gate };
  const slow = call('GET', `${P(s2.code)}/reports/income-expense?from=${ym(0)}&to=${ym(0)}`, MGR);
  await sleep(300);
  const concurrent = await call('POST', `${P(s2.code)}/payments`, MGR, { apartment_id: g1, amount_minor: 1234, entry_date: TODAY, method: 'cash', idempotency_key: key('cc'), account_id: kasa2.body.account.id });
  release();
  const slowRes = await slow;
  hooks.pause = null;
  const afterWrite = (await call('GET', `${P(s2.code)}/reports/income-expense?from=${ym(0)}&to=${ym(0)}`, MGR)).body.totals.collected_minor;
  check('E9c: TEK SNAPSHOT: rapor calisirken yazilan tahsilat o rapora GIRMEZ (REPEATABLE READ); sonraki rapor girer', concurrent.status === 201 && slowRes.status === 200 && slowRes.body.totals.collected_minor === before && afterWrite === before + 1234, [before, slowRes.body?.totals, afterWrite]);
  // eszamanlilik semaforu: 2 devam eden rapor + 3.'sü 503 REPORT_BUSY
  let release2;
  const gate2 = new Promise((resolve) => { release2 = resolve; });
  hooks.pause = { match: /WITH\s+items AS/, gate: gate2 };
  const r1 = call('GET', `${P(site.code)}/reports/aging`, MGR);
  const r2 = call('GET', `${P(site.code)}/reports/aging`, MGR);
  await sleep(400);
  const r3 = await call('GET', `${P(site.code)}/reports/aging`, MGR);
  release2();
  const done = await Promise.all([r1, r2]);
  hooks.pause = null;
  check('E9d: site basina en cok 2 eszamanli agir rapor: 3. istek 503 REPORT_BUSY + Retry-After; ilk ikisi 200; sonra yine calisir', r3.status === 503 && r3.body.code === 'REPORT_BUSY' && r3.headers.get('retry-after') !== null && done.every((r) => r.status === 200) && (await call('GET', `${P(site.code)}/reports/aging`, MGR)).status === 200, [r3.status, r3.body]);

  // --- E10. EXPLAIN: ledger_entries uzerinde yalniz site indeksi (Seq Scan yok)
  const perf = await mkManaged('F4B Rapor Performans', { 'P Blok': 1 });
  await q(`INSERT INTO apartments (site_code, block_id, unit_label, sort_order) SELECT $1, $2, 'D ' || g, g + 10 FROM generate_series(1, 2999) g`, [perf.code, perf.apts[0].blockId]);
  const aptIds = (await q(`SELECT id FROM apartments WHERE site_code = $1`, [perf.code])).rows.map((r) => Number(r.id));
  await q(`INSERT INTO ledger_entries (site_code, apartment_id, kind, amount_minor, period, entry_date, due_date, payer_party)
           SELECT $1, a, 'charge', 10000, date_trunc('month', d)::date, d::date, d::date, 'both' FROM unnest($2::bigint[]) a CROSS JOIN generate_series(CURRENT_DATE - 330, CURRENT_DATE - 30, interval '30 days') d`, [perf.code, aptIds]);
  await q(`INSERT INTO ledger_entries (site_code, apartment_id, kind, amount_minor, period, entry_date, payer_party, method)
           SELECT $1, a, 'payment', -10000, date_trunc('month', d)::date, d::date, 'both', 'cash' FROM unnest($2::bigint[]) a CROSS JOIN generate_series(CURRENT_DATE - 300, CURRENT_DATE - 30, interval '60 days') d`, [perf.code, aptIds]);
  // gercekci coklu-kiraci tablo boyutu: baska sitenin defteri (planlayici sitenin payini kucuk gorur); 4a "L" bolumundeki dolgu yontemi
  const filler = await mkManaged('F4B Rapor Dolgu', { 'D Blok': 1 });
  await q(`INSERT INTO apartments (site_code, block_id, unit_label, sort_order) SELECT $1, $2, 'D ' || g, g + 10 FROM generate_series(1, 1500) g`, [filler.code, filler.apts[0].blockId]);
  const fillerApts = (await q(`SELECT id FROM apartments WHERE site_code = $1`, [filler.code])).rows.map((r) => Number(r.id));
  await q(`INSERT INTO ledger_entries (site_code, apartment_id, kind, amount_minor, period, entry_date, due_date, payer_party)
           SELECT $1, a, 'charge', 10000, date_trunc('month', d)::date, d::date, d::date, 'both' FROM unnest($2::bigint[]) a CROSS JOIN generate_series(CURRENT_DATE - 1500, CURRENT_DATE - 30, interval '15 days') d`, [filler.code, fillerApts]);
  await q('ANALYZE ledger_entries');
  await q('ANALYZE apartments');
  const t0 = Date.now();
  const perfAging = await call('GET', `${P(perf.code)}/reports/aging?status=debtor&limit=50`, MGR);
  const agingMs = Date.now() - t0;
  const { m1Ctes, bucketSumSql } = await import('../src/modules/finance_m1.js');
  const plan = JSON.stringify((await q(`EXPLAIN (FORMAT JSON) WITH ${m1Ctes('$1', '$2')} SELECT rem.apartment_id, ${bucketSumSql('$2')} FROM rem GROUP BY rem.apartment_id`, [perf.code, TODAY])).rows[0]['QUERY PLAN']);
  const ledgerSeq = (plan.match(/"Node Type":"Seq Scan"[^}]*"Relation Name":"ledger_entries"/g) || []).length + (plan.match(/"Relation Name":"ledger_entries"[^}]*"Node Type":"Seq Scan"/g) || []).length;
  const rowsPerf = Number((await q(`SELECT COUNT(*)::int AS n FROM ledger_entries WHERE site_code = $1`, [perf.code])).rows[0].n);
  check(`E10: 3000 daireli, ${rowsPerf} satirli sitede yaslandirma ${agingMs} ms (hedef < 2000); sayfa 50`, perfAging.status === 200 && perfAging.body.items.length === 50 && agingMs < 2000, { agingMs, rowsPerf });
  check('E10b: yaslandirma sorgusunun planinda ledger_entries icin SEQ SCAN yok (site indeksi); OLCUM: plan boyutu', ledgerSeq === 0, plan.slice(0, 300));
  void failMessage;
}
