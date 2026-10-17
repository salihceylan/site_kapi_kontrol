// Finans Faz 4b QA bolumu: S. Bagimsiz 2. tur (R15) duzeltmeleri. scripts/qa_finance4b.mjs tarafindan yuklenir.
// Duzeltmeden once bu bolumun P1-A / P2-1 / P2-2 / P2-4 kontrolleri BASARISIZDI (bkz. docs/PLATFORM_FINANS_4B.md "R15 duzeltmeleri").

export default async function sectionR15(t) {
  const { check, same, q, call, ctx, TODAY, ago, ym, dayOf, mkManaged, mkUser, addPerson, addResidency, P, key, users } = t;
  const { SUPER, MGR } = users;
  const mails = ctx.mails;
  const queue = await import('../src/modules/finance_reminder_queue.js');
  queue.reminderQueueHooks.sleep = async () => {};
  console.log('--- S. R15 duzeltmeleri ---');
  const mkAcc = (base, name, over = {}) => call('POST', `${base}/accounts`, MGR, { name, kind: 'cash', opening_balance_minor: 0, opening_date: ago(5), idempotency_key: key('sa'), ...over });
  const pay = (site, apt, amount, over = {}) => call('POST', `${P(site.code)}/payments`, MGR, { apartment_id: apt, amount_minor: amount, entry_date: TODAY, method: 'cash', idempotency_key: key('sp'), ...over });
  const periodOf = (iso) => `${iso.slice(0, 7)}-01`;
  const addCharge = (site, aptId, amount, dueDaysAgo) =>
    q(`INSERT INTO ledger_entries (site_code, apartment_id, kind, amount_minor, period, entry_date, due_date, payer_party) VALUES ($1, $2, 'charge', $3, $4::date, $5::date, $6::date, 'both')`, [
      site.code, aptId, amount, periodOf(ago(dueDaysAgo + 5)), ago(dueDaysAgo + 5), ago(dueDaysAgo),
    ]);

  // ============================================================================================================
  // S1 (P1-A): mutabakat cift duzeltme TARIH SIRASINDAN bagimsiz kapanir
  // ============================================================================================================
  const rs = await mkManaged('F4B R15 Mutabakat', { 'M Blok': 1 });
  const rb = P(rs.code);
  const recOf = (accId, asOf, statement, expected, adjust) =>
    call('POST', `${rb}/accounts/${accId}/reconciliations`, MGR, { as_of_date: asOf, statement_balance_minor: statement, expected_computed_minor: expected, ...(adjust ? { adjust: { reason_code: 'bank_fee' } } : {}), idempotency_key: key('sr') });
  const balanceOf = async (accId) => (await call('GET', `${rb}/accounts`, MGR)).body.items.find((a) => a.id === accId).balance_minor;
  const countAdj = async (accId) => (await q(`SELECT COUNT(*)::int AS n FROM account_movements WHERE account_id = $1 AND kind = 'adjustment'`, [accId])).rows[0].n;

  // (a) once ESKI tarih (ago40), sonra YENI tarih (ago20): ikinci mutabakat birincinin duzeltmesini gorur
  const accA = (await mkAcc(rb, 'Sira A', { opening_balance_minor: 100000, opening_date: ago(50) })).body.account.id;
  const a1 = await recOf(accA, ago(40), 99500, 100000, true);
  const a2 = await recOf(accA, ago(20), 99500, 100000, true); // istemci ESKI bakiyeyi biliyor
  const a3 = a2.status === 409 ? await recOf(accA, ago(20), 99500, a2.body.computed_balance_minor, true) : a2;
  check('S1: P1-A once ago40 sonra ago20 mutabakati: ikinci mutabakat ESKI beklenen degerle 409 RECONCILIATION_STALE (+ guncel 99500, birincinin duzeltmesi dahil); guncel degerle fark 0, duzeltme YOK; bakiye 99500 (99000 olmaz), duzeltme hareketi 1',
    a1.status === 201 && a2.status === 409 && a2.body.code === 'RECONCILIATION_STALE' && a2.body.computed_balance_minor === 99500 && a3.status === 201 && a3.body.reconciliation.difference_minor === 0 && a3.body.reconciliation.adjusted === false
      && (await balanceOf(accA)) === 99500 && (await countAdj(accA)) === 1, { a1: a1.status, a2: [a2.status, a2.body], a3: [a3.status, a3.body], balance: await balanceOf(accA), adj: await countAdj(accA) });

  // (b) once YENI tarih (ago20), sonra ESKI tarih (ago40): ESKI tarihe DUZELTME istenirse 409 RECONCILIATION_ORDER; yalniz kayit serbest
  const accB = (await mkAcc(rb, 'Sira B', { opening_balance_minor: 100000, opening_date: ago(50) })).body.account.id;
  const b1 = await recOf(accB, ago(20), 99500, 100000, true);
  const b2 = await recOf(accB, ago(40), 99500, 100000, true);
  const b3 = await recOf(accB, ago(40), 99500, 100000, false);
  check('S2: P1-A ters sira (once ago20 sonra ago40): daha YENI tarihli duzeltilmis mutabakat varken eski tarihe duzeltme (adjust) 409 RECONCILIATION_ORDER (Turkce ileti, yeni duzeltme YAZILMAZ); yalniz kayit (adjust yok) 201 ve fark gosterilir; bakiye 99500',
    b1.status === 201 && b2.status === 409 && b2.body.code === 'RECONCILIATION_ORDER' && /mutabakat/i.test(b2.body.error) && b3.status === 201 && b3.body.reconciliation.difference_minor === -500 && b3.body.reconciliation.adjusted === false
      && (await balanceOf(accB)) === 99500 && (await countAdj(accB)) === 1, { b1: b1.status, b2: [b2.status, b2.body], b3: [b3.status, b3.body], balance: await balanceOf(accB), adj: await countAdj(accB) });

  // (c) R7 korunur: AYNI tarih tekrari ikinci duzeltme yazmaz
  const accC = (await mkAcc(rb, 'Sira C', { opening_balance_minor: 100000, opening_date: ago(50) })).body.account.id;
  const c1 = await recOf(accC, ago(1), 110000, 100000, true);
  const c2 = await recOf(accC, ago(1), 110000, 100000, true);
  const c3 = await recOf(accC, ago(1), 110000, 110000, true);
  check('S3: R7 korunur: AYNI as_of icin tekrar: eski beklenen degerle 409 STALE, guncel degerle fark 0 ve duzeltme YOK; bakiye 110000', c1.status === 201 && c2.status === 409 && c2.body.code === 'RECONCILIATION_STALE' && c3.status === 201 && c3.body.reconciliation.difference_minor === 0 && (await balanceOf(accC)) === 110000 && (await countAdj(accC)) === 1, [c1.status, c2.status, c3.status]);

  // (d) iki duzeltilmis mutabakat ARDISIK tarihlerde (ago40 -> ago20 -> ago5): her biri oncekini gorur, toplam duzeltme = gercek fark
  const accD = (await mkAcc(rb, 'Sira D', { opening_balance_minor: 100000, opening_date: ago(50) })).body.account.id;
  const d1 = await recOf(accD, ago(40), 99500, 100000, true);
  const d2 = await recOf(accD, ago(20), 99300, 99500, true); // yeni -200 fark (bu tarihe kadar toplam -700)
  const d3 = await recOf(accD, ago(5), 99300, 99300, true); // fark 0
  check('S4: ardisik uc mutabakat (ago40 -500, ago20 -200 ek fark, ago5 fark 0): her biri oncekinin duzeltmesini gorur; duzeltme hareketleri toplami -700, bakiye 99300',
    d1.status === 201 && d2.status === 201 && d2.body.reconciliation.difference_minor === -200 && d3.status === 201 && d3.body.reconciliation.difference_minor === 0 && (await balanceOf(accD)) === 99300 && (await countAdj(accD)) === 2, [d1.status, d2.status, d2.body, d3.status, d3.body]);

  // ============================================================================================================
  // S5 (P2-2): ACCOUNT_INACTIVE iletisi etkin hesap varken yaniltmaz
  // ============================================================================================================
  await call('PUT', '/admin/finance-legal-gate', SUPER, { legal_ok: true });
  const ps = await mkManaged('F4B R15 Pasif', { 'P Blok': 2 });
  const pb = P(ps.code);
  const oldAcc = (await mkAcc(pb, 'Eski Kasa', { opening_date: ago(100) })).body.account.id;
  const newAcc = (await mkAcc(pb, 'Yeni Banka', { kind: 'bank', opening_date: ago(10) })).body.account.id;
  await call('PATCH', `${pb}/accounts/${oldAcc}`, MGR, { is_active: false });
  const noAcc = await pay(ps, ps.ids[0], 5000, { entry_date: ago(30) });
  const withNew = await pay(ps, ps.ids[0], 5000, { entry_date: ago(30), account_id: newAcc });
  check('S5: P2-2 eski hesap pasif, yeni hesap ETKIN ama tahsilat tarihinden sonra acilmis: hesapsiz tahsilat 409 ACCOUNT_INACTIVE ve ileti "tum hesaplar pasif" DEMEZ ("Bu tarihte acik olan hesaplarin hepsi pasif"); yeni hesaba o tarihli odeme BEFORE_OPENING_DATE',
    noAcc.status === 409 && noAcc.body.code === 'ACCOUNT_INACTIVE' && /Bu tarihte/.test(noAcc.body.error) && !/Tüm/.test(noAcc.body.error) && withNew.status === 409 && withNew.body.code === 'BEFORE_OPENING_DATE', [noAcc.body, withNew.body]);

  // ============================================================================================================
  // S6 (P2-1): gonderim aninda dusen daire icin aralik kaydi ve kalem apartment_ids guncellenir
  // ============================================================================================================
  await call('PUT', '/admin/finance-legal-gate', SUPER, { legal_ok: true });
  const site = await mkManaged('F4B R15 Hatirlatma', { 'H Blok': 2 });
  const [h1, h2] = site.ids;
  const tag = `r15${Date.now() % 100000}`;
  const email = `${tag}-malik@qa.example`;
  await q(`UPDATE apartments SET responsible_party = 'owner' WHERE id = ANY($1::bigint[])`, [[h1, h2]]);
  const owner = await mkUser(`R15 Malik ${tag}`, 'apartment_owner', { email, verified: true });
  const person = await addPerson(site.code, { user: owner });
  await addResidency(site.code, h1, person, 'owner');
  await addResidency(site.code, h2, person, 'owner');
  await addCharge(site, h1, 90000, 40);
  await addCharge(site, h2, 80000, 40);
  const hb = P(site.code);
  const s0 = await call('GET', `${hb}/settings`, MGR);
  await call('PUT', `${hb}/settings`, MGR, { expected_settings_version: s0.body.settings_version, reminders: { enabled: true, min_overdue_minor: 5000, min_days_overdue: 5, min_interval_days: 14, max_consecutive: 3 } });
  const pv = await call('POST', `${hb}/reminders/preview`, MGR, { tone: 'friendly' });
  void queue.stopFinanceReminderQueue();
  const send = await call('POST', `${hb}/reminders/send`, MGR, { tone: 'friendly', note: null, expected_hash: pv.body.preview_hash, expected_apartment_count: pv.body.apartment_count, expected_person_count: pv.body.person_count, idempotency_key: key('sh') });
  const runId = send.body.run.id;
  const intervalsBefore = (await q(`SELECT COUNT(*)::int AS n FROM finance_reminder_apartments WHERE run_id = $1`, [runId])).rows[0].n;
  await call('PUT', `${hb}/reminders/exclusions/${h2}`, MGR, { reason: 'dava' }); // gonderimden SONRA h2 muaf
  mails.length = 0;
  queue.resumeFinanceReminderQueue();
  await queue.kickFinanceReminderQueue();
  void queue.stopFinanceReminderQueue();
  const item = (await q(`SELECT email_status, apartment_ids FROM finance_reminder_items WHERE run_id = $1`, [runId])).rows[0];
  const intervalsAfter = (await q(`SELECT apartment_id FROM finance_reminder_apartments WHERE run_id = $1 ORDER BY apartment_id`, [runId])).rows.map((r) => Number(r.apartment_id));
  const sentMail = mails.find((m) => String(m.to).toLowerCase() === email.toLowerCase());
  check('S6: P2-1 gonderim aninda dusen daire (muaf): iletide yalniz kalan daire, kalemin apartment_ids\'i [kalan], dusen dairenin ARALIK kaydi silinir (hic hatirlatilmamis daire 14 gun beklemez)',
    pv.body.apartment_count === 2 && intervalsBefore === 2 && item.email_status === 'sent' && same(item.apartment_ids.map(Number), [h1]) && same(intervalsAfter, [h1]) && sentMail && /H Blok - Daire 1/.test(sentMail.text ?? '') && !/H Blok - Daire 2/.test(sentMail.text ?? ''),
    { pv: pv.body.apartment_count, intervalsBefore, item, intervalsAfter, text: sentMail?.text?.slice(0, 200) });

  // ============================================================================================================
  // S7 (P2-4): ayni anahtar + FARKLI govde 409 IDEMPOTENCY_CONFLICT (neden / not); ayni govde 200
  // ============================================================================================================
  const rp = await mkManaged('F4B R15 Tekrar', { 'T Blok': 3 });
  const rpb = P(rp.code);
  const cash = (await mkAcc(rpb, 'Tekrar Kasa', { opening_balance_minor: 100000 })).body.account.id;
  const bank = (await mkAcc(rpb, 'Tekrar Banka', { kind: 'bank' })).body.account.id;
  const conflict = (r) => r.status === 409 && r.body.code === 'IDEMPOTENCY_CONFLICT';
  // duzeltme hareketi
  const adjKey = key('adj');
  const adjBody = (over = {}) => ({ amount_minor: -250, movement_date: TODAY, reason_code: 'bank_fee', idempotency_key: adjKey, ...over });
  const adj1 = await call('POST', `${rpb}/accounts/${cash}/adjustments`, MGR, adjBody());
  const adj2 = await call('POST', `${rpb}/accounts/${cash}/adjustments`, MGR, adjBody());
  const adj3 = await call('POST', `${rpb}/accounts/${cash}/adjustments`, MGR, adjBody({ reason_code: 'other', note: 'sayim farki' }));
  check('S7a: P2-4 duzeltme hareketi tekrari: ayni govde 200; ayni anahtar + farkli neden kodu / not 409 IDEMPOTENCY_CONFLICT', adj1.status === 201 && adj2.status === 200 && conflict(adj3), [adj1.status, adj2.status, adj3.status, adj3.body]);
  // aktarim iptali
  const tr = await call('POST', `${rpb}/transfers`, MGR, { from_account_id: cash, to_account_id: bank, amount_minor: 1000, transfer_date: TODAY, idempotency_key: key('tr') });
  const tvKey = key('tv');
  const tv1 = await call('POST', `${rpb}/transfers/${tr.body.transfer.id}/void`, MGR, { reason: 'yanlis hesap', idempotency_key: tvKey });
  const tv2 = await call('POST', `${rpb}/transfers/${tr.body.transfer.id}/void`, MGR, { reason: 'yanlis hesap', idempotency_key: tvKey });
  const tv3 = await call('POST', `${rpb}/transfers/${tr.body.transfer.id}/void`, MGR, { reason: 'BASKA NEDEN', idempotency_key: tvKey });
  check('S7b: P2-4 aktarim iptali tekrari: ayni govde 200; farkli neden 409 IDEMPOTENCY_CONFLICT', tv1.status === 201 && tv2.status === 200 && conflict(tv3), [tv1.status, tv2.status, tv3.status, tv3.body]);
  // makbuz iptali
  const rpay = await pay(rp, rp.ids[0], 5000, { account_id: cash });
  const rcKey = key('rc');
  const rc1 = await call('POST', `${rpb}/receipts/${rpay.body.receipt.id}/cancel`, MGR, { reason_code: 'issued_in_error', note: 'ilk not', idempotency_key: rcKey });
  const rc2 = await call('POST', `${rpb}/receipts/${rpay.body.receipt.id}/cancel`, MGR, { reason_code: 'issued_in_error', note: 'ilk not', idempotency_key: rcKey });
  const rc3 = await call('POST', `${rpb}/receipts/${rpay.body.receipt.id}/cancel`, MGR, { reason_code: 'issued_in_error', note: 'BASKA NOT', idempotency_key: rcKey });
  check('S7c: P2-4 makbuz iptali tekrari: ayni govde 200; farkli not 409 IDEMPOTENCY_CONFLICT', rc1.status === 201 && rc2.status === 200 && conflict(rc3), [rc1.status, rc2.status, rc3.status, rc3.body]);
  // gider iptali
  const cat = (await call('GET', `${rpb}/expense-categories`, MGR)).body.items[0].id;
  const ex = await call('POST', `${rpb}/expenses`, MGR, { category_id: cat, description: 'Tekrar gideri', amount_minor: 700, expense_date: TODAY, account_id: cash, idempotency_key: key('ex') });
  const evKey = key('ev');
  const ev1 = await call('POST', `${rpb}/expenses/${ex.body.expense.id}/void`, MGR, { reason: 'yanlis kayit', idempotency_key: evKey });
  const ev2 = await call('POST', `${rpb}/expenses/${ex.body.expense.id}/void`, MGR, { reason: 'yanlis kayit', idempotency_key: evKey });
  const ev3 = await call('POST', `${rpb}/expenses/${ex.body.expense.id}/void`, MGR, { reason: 'BASKA NEDEN', idempotency_key: evKey });
  check('S7d: P2-4 gider iptali tekrari: ayni govde 200; farkli neden 409 IDEMPOTENCY_CONFLICT', ev1.status === 201 && ev2.status === 200 && conflict(ev3), [ev1.status, ev2.status, ev3.status, ev3.body]);
  // tazminat iptali (anahtar yolu): tekrar ozgun yanitla AYNI reversed_count / reversed_total_minor
  const lf = await mkManaged('F4B R15 Tazminat', { 'L Blok': 2 });
  const lb = P(lf.code);
  const lset = await call('GET', `${lb}/settings`, MGR);
  await call('PUT', `${lb}/settings`, MGR, { expected_settings_version: lset.body.settings_version, late_fee: { enabled: true, start_period: ym(-3), rate_bp: 500, method: 'daily_30', grace_days: 0 } });
  for (const id of lf.ids) {
    await q(`INSERT INTO ledger_entries (site_code, apartment_id, kind, amount_minor, period, entry_date, due_date, payer_party) VALUES ($1, $2, 'charge', 100000, $3::date, $4::date, $5::date, 'both')`, [lf.code, id, `${ym(-3)}-01`, dayOf(-3, 5), dayOf(-3, 10)]);
  }
  for (const off of [-3, -2, -1]) await call('POST', `${lb}/periods/${ym(off)}/close`, MGR);
  const lpv = await call('POST', `${lb}/late-fee/preview`, MGR, { period: ym(-3) });
  const lpost = await call('POST', `${lb}/late-fee/post`, MGR, { period: ym(-3), expected_total_minor: lpv.body.total_minor, expected_apartment_count: lpv.body.apartment_count, expected_hash: lpv.body.preview_hash, idempotency_key: key('lp') });
  const lvKey = key('lv');
  const lv1 = await call('POST', `${lb}/late-fee/runs/${lpost.body.run.id}/void`, MGR, { reason: 'tazminat iptali', idempotency_key: lvKey });
  const lv2 = await call('POST', `${lb}/late-fee/runs/${lpost.body.run.id}/void`, MGR, { reason: 'tazminat iptali', idempotency_key: lvKey });
  const lv3 = await call('POST', `${lb}/late-fee/runs/${lpost.body.run.id}/void`, MGR, { reason: 'BASKA NEDEN', idempotency_key: lvKey });
  check('S7e: P2-4 tazminat iptali tekrari (anahtar yolu): ayni govde 200 ve OZGUN yanitla ayni reversed_count / reversed_total_minor (0 degil); farkli neden 409 IDEMPOTENCY_CONFLICT',
    lpost.status === 201 && lv1.status === 201 && lv1.body.reversed_count === 2 && lv1.body.reversed_total_minor > 0 && lv2.status === 200 && lv2.body.reversed_count === lv1.body.reversed_count && lv2.body.reversed_total_minor === lv1.body.reversed_total_minor && conflict(lv3),
    [lv1.status, lv1.body.reversed_count, lv1.body.reversed_total_minor, lv2.status, lv2.body.reversed_count, lv2.body.reversed_total_minor, lv3.status, lv3.body]);

  // ============================================================================================================
  // S8 (P2-7): mühürlü adres ozetlerini temizleme yolu calisir
  // ============================================================================================================
  const purged = await queue.purgeStaleReminderHashes();
  check('S8: P2-7 purgeStaleReminderHashes calisir (hata yok, sayi doner)', Number.isInteger(purged) && purged >= 0, purged);

  void SUPER;
}
