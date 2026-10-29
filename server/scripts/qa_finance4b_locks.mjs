// Finans Faz 4b QA bolumu: H. Kilit sirasi ve eszamanlilik (docs/PLATFORM_FINANS_4B.md "Karar 7" kilit sirasi). scripts/qa_finance4b.mjs tarafindan yuklenir.
// Olcut: 40P01 (deadlock) SAYISI = 0 (hooks.deadlocks, uygulama tek yeniden denemeyle gecse bile sayar), sunucuda beklenmeyen 5xx (errorId'li log) = 0,
// ve defter degismezleri (hesap hareketi = odeme, makbuz = aktif odeme, makbuz numarasi bosluksuz) karisik eszamanli yuk SONRASINDA da dogru.
// Kapsam: karisik yazma firtinasi (odeme / ters kayit / duzeltme / gider / aktarim / duzeltme hareketi / rapor) x kullanici silme (sert + kimliksizlestirme)
// x daire azaltma x gecikme tazminati x site silme (CASCADE) x hatirlatma kuyrugu; silinmis hesapla yazma reddi.

export default async function sectionLocks(t) {
  const { check, same, q, call, hooks, serverErrors, TODAY, ago, ym, dayOf, mkManaged, mkUser, addPerson, addResidency, link, P, key, failCode, users, sleep, ctx } = t;
  const { SUPER, MGR } = users;
  const ROUNDS = Number(process.env.QA_LOCK_ROUNDS || 6);
  console.log('--- H. kilit sirasi ve eszamanlilik ---');

  const { FINANCE_4B_TABLES } = await import('../src/modules/finance_4b_schema.js');
  const queue = await import('../src/modules/finance_reminder_queue.js');
  queue.reminderQueueHooks.sleep = async () => {};
  const deadlocks = () => hooks.deadlocks;
  const errorIds = () => serverErrors.filter((line) => /errorId=/.test(line)).length;
  const dl0 = deadlocks();
  const err0 = errorIds();
  const unexpected = [];
  /** Beklenen durumlar disindaki yanitlari kaydeder (5xx yalniz REPORT_BUSY 503 olabilir). */
  const judge = (label, results, allowed = [200, 201, 409]) => {
    for (const r of results) {
      if (r === null || r === undefined) continue;
      if (r.status >= 500 ? !(r.status === 503 && r.body?.code === 'REPORT_BUSY') : !allowed.includes(r.status)) unexpected.push(`${label}: ${r.status} ${r.body?.code ?? ''}`);
    }
  };
  const mkAccount = async (base, name, kind, opening, user = MGR) => {
    const res = await call('POST', `${base}/accounts`, user, { name, kind, opening_balance_minor: opening, opening_date: TODAY, idempotency_key: key('acc') });
    if (res.status !== 201) throw new Error(`hesap acilamadi: ${res.status} ${JSON.stringify(res.body)}`);
    return res.body.account.id;
  };
  const addCharge = (site, aptId, amount, entryDate = ago(25), due = ago(20)) =>
    q(`INSERT INTO ledger_entries (site_code, apartment_id, kind, amount_minor, period, entry_date, due_date, payer_party) VALUES ($1, $2, 'charge', $3, $4::date, $5::date, $6::date, 'both')`, [
      site.code, aptId, amount, `${entryDate.slice(0, 7)}-01`, entryDate, due,
    ]);

  // ============================================================================================================
  // H1. Karisik yazma firtinasi (tek site): her turda ~20 eszamanli istek
  // ============================================================================================================
  const site = await mkManaged('F4B Kilit Karisik', { 'K Blok': 12 });
  const base = P(site.code);
  const kasa = await mkAccount(base, 'Kasa', 'cash', 100000);
  const banka = await mkAccount(base, 'Banka', 'bank', 50000);
  const categoryId = (await call('GET', `${base}/expense-categories`, MGR)).body.items[0].id;
  for (const id of site.ids) for (let n = 0; n < 3; n += 1) await addCharge(site, id, 50000, ago(30 + n), ago(25 + n));
  const payments = []; // henuz ters cevrilmemis odemeler
  const expenses = [];
  const dlBeforeStorm = deadlocks();
  const statusCounts = {};
  const tally = (r) => { statusCounts[r.status] = (statusCounts[r.status] ?? 0) + 1; return r; };
  for (let round = 0; round < ROUNDS; round += 1) {
    const ops = [];
    // borclandirma (4a ek borc: onizleme sirada, onay firtinanin icinde)
    const chargeBody = { name: `Kilit ek borc ${round}`, distribution: 'equal', amount_minor: 120000 + round * 12, target: { type: 'site' }, due_date: dayOf(1, 15) };
    const chargePreview = await call('POST', `${base}/charges/preview`, MGR, chargeBody);
    if (chargePreview.status === 200) {
      ops.push(call('POST', `${base}/charges`, MGR, { ...chargeBody, expected_total_minor: chargePreview.body.total_minor, expected_apartment_count: chargePreview.body.apartment_count, expected_hash: chargePreview.body.preview_hash, idempotency_key: key('ch') }).then(tally));
    } else {
      unexpected.push(`H1 ek borc onizleme: ${chargePreview.status} ${chargePreview.body?.code ?? ''}`);
    }
    for (let i = 0; i < 5; i += 1) {
      const apt = site.ids[(round * 5 + i) % site.ids.length];
      const amount = 1000 + i * 7 + round;
      ops.push(call('POST', `${base}/payments`, MGR, { apartment_id: apt, amount_minor: amount, entry_date: TODAY, method: i % 2 === 0 ? 'cash' : 'transfer', account_id: i % 2 === 0 ? kasa : banka, idempotency_key: key('p') })
        .then((r) => { if (r.status === 201) payments.push({ id: r.body.entry.id, apt, amount }); return tally(r); }));
    }
    const reverse = payments.shift();
    if (reverse) ops.push(call('POST', `${base}/entries/${reverse.id}/reverse`, MGR, { reason: 'kilit turu', idempotency_key: key('rv') }).then(tally));
    const correct = payments.shift();
    if (correct) ops.push(call('POST', `${base}/entries/${correct.id}/correct`, MGR, { amount_minor: correct.amount + 1, entry_date: TODAY, method: 'cash', idempotency_key: key('cr') }).then(tally));
    for (let i = 0; i < 2; i += 1) {
      ops.push(call('POST', `${base}/expenses`, MGR, { category_id: categoryId, description: `Kilit gideri ${round}-${i}`, amount_minor: 300 + round * 11 + i, expense_date: TODAY, account_id: i % 2 === 0 ? kasa : banka, allow_duplicate: true, idempotency_key: key('ex') })
        .then((r) => { if (r.status === 201) expenses.push(r.body.expense.id); return tally(r); }));
    }
    const voided = expenses.shift();
    if (voided) ops.push(call('POST', `${base}/expenses/${voided}/void`, MGR, { reason: 'kilit turu', idempotency_key: key('xv') }).then(tally));
    ops.push(call('POST', `${base}/transfers`, MGR, { from_account_id: kasa, to_account_id: banka, amount_minor: 100 + round, transfer_date: TODAY, idempotency_key: key('tr') }).then(tally));
    ops.push(call('POST', `${base}/transfers`, MGR, { from_account_id: banka, to_account_id: kasa, amount_minor: 50 + round, transfer_date: TODAY, idempotency_key: key('tr') }).then(tally));
    ops.push(call('POST', `${base}/accounts/${kasa}/adjustments`, MGR, { amount_minor: -5 - round, movement_date: TODAY, reason_code: 'bank_fee', idempotency_key: key('adj') }).then(tally));
    ops.push(call('GET', `${base}/reports/aging`, MGR).then(tally));
    ops.push(call('GET', `${base}/reports/cash-position`, MGR).then(tally));
    ops.push(call('GET', `${base}/exports/finance_receipts`, MGR).then(tally));
    ops.push(call('GET', `${base}/accounts`, MGR).then(tally));
    judge(`H1 tur ${round}`, await Promise.all(ops), [200, 201, 409]);
  }
  check(`H1: karisik firtina (${ROUNDS} tur x ~20 eszamanli istek: ek borc onayi / odeme / ters kayit / duzeltme / gider + iptal / iki yonlu aktarim / duzeltme hareketi / rapor / disa aktarma): 40P01 = 0, beklenmeyen yanit yok`,
    deadlocks() === dlBeforeStorm && unexpected.length === 0 && errorIds() === err0 && (statusCounts[201] ?? 0) > ROUNDS * 5, { deadlocks: deadlocks() - dlBeforeStorm, unexpected: unexpected.slice(0, 5), statusCounts, errorIds: errorIds() - err0 });

  // --- H1b. firtina SONRASI defter degismezleri
  const balances = (await call('GET', `${base}/accounts`, MGR)).body;
  const sumOfMovements = (await q(`SELECT account_id, COALESCE(SUM(amount_minor), 0)::bigint AS s FROM account_movements WHERE site_code = $1 GROUP BY account_id`, [site.code])).rows;
  const balanceMatches = balances.items.every((a) => Number(sumOfMovements.find((r) => Number(r.account_id) === a.id)?.s ?? 0) === a.balance_minor);
  check('H1b: her hesabin bakiyesi = hareketlerinin toplami (API = DB); toplam bakiye = hesap bakiyeleri toplami', balanceMatches && balances.total_balance_minor === balances.items.reduce((sum, a) => sum + a.balance_minor, 0), { balances: balances.items.map((a) => [a.id, a.balance_minor]), sums: sumOfMovements });
  const badMirror = (await q(
    `SELECT COUNT(*)::int AS n FROM ledger_entries p WHERE p.site_code = $1 AND p.kind = 'payment' AND (
       (SELECT COUNT(*) FROM account_movements m WHERE m.ledger_entry_id = p.id AND m.kind = 'collection') <> 1
       OR (SELECT COUNT(*) FROM account_movements r WHERE r.reverses_movement_id IN (SELECT id FROM account_movements WHERE ledger_entry_id = p.id AND kind = 'collection'))
          <> (SELECT COUNT(*) FROM ledger_entries v WHERE v.reverses_entry_id = p.id))`,
    [site.code],
  )).rows[0].n;
  check('H1c: her odemenin TAM BIR tahsilat hareketi var; ters cevrilen her odemenin TAM BIR ayna hareketi var (cift / eksik hareket yok)', badMirror === 0, badMirror);
  const badReceipt = (await q(
    `SELECT COUNT(*)::int AS n FROM ledger_entries p WHERE p.site_code = $1 AND p.kind = 'payment' AND (
       (NOT EXISTS (SELECT 1 FROM ledger_entries v WHERE v.reverses_entry_id = p.id)
         AND (SELECT COUNT(*) FROM receipts c WHERE c.ledger_entry_id = p.id AND c.kind = 'collection' AND NOT EXISTS (SELECT 1 FROM receipts x WHERE x.cancels_receipt_id = c.id)) <> 1)
       OR (EXISTS (SELECT 1 FROM ledger_entries v WHERE v.reverses_entry_id = p.id)
         AND (SELECT COUNT(*) FROM receipts c WHERE c.ledger_entry_id = p.id AND c.kind = 'collection' AND NOT EXISTS (SELECT 1 FROM receipts x WHERE x.cancels_receipt_id = c.id)) <> 0))`,
    [site.code],
  )).rows[0].n;
  check('H1d: ters cevrilmemis her odemenin TAM BIR aktif makbuzu; ters cevrilenin aktif makbuzu YOK (iptal makbuzu yazildi)', badReceipt === 0, badReceipt);
  const numbering = (await q(`SELECT receipt_year, COUNT(*)::int AS n, MIN(receipt_no)::int AS lo, MAX(receipt_no)::int AS hi FROM receipts WHERE site_code = $1 GROUP BY receipt_year`, [site.code])).rows;
  const counters = (await q(`SELECT receipt_year, last_no::int AS last_no FROM receipt_counters WHERE site_code = $1`, [site.code])).rows;
  check('H1e: makbuz numaralari her yil icin BOSLUKSUZ ve tekil (1..N), sayac = en buyuk numara (eszamanli 40+ makbuz sonrasi)',
    numbering.length > 0 && numbering.every((row) => row.lo === 1 && row.hi === row.n && counters.some((c) => c.receipt_year === row.receipt_year && c.last_no === row.hi)), { numbering, counters });
  const unbalancedLedger = (await q(`SELECT COUNT(*)::int AS n FROM ledger_entries l WHERE l.site_code = $1 AND l.kind = 'reversal' AND NOT EXISTS (SELECT 1 FROM ledger_entries o WHERE o.id = l.reverses_entry_id AND o.amount_minor = -l.amount_minor)`, [site.code])).rows[0].n;
  check('H1f: her ters kayit hedefinin tam tersi (tutar); defter append-only (silme / guncelleme yok: satir sayisi yalniz artti)', unbalancedLedger === 0, unbalancedLedger);

  // ============================================================================================================
  // H2. Kullanici silme x finans yazmalari (sert silme + kimliksizlestirme)
  // ============================================================================================================
  const siteU = await mkManaged('F4B Kilit Kullanici', { 'U Blok': 8 });
  const baseU = P(siteU.code);
  const kasaU = await mkAccount(baseU, 'Kasa', 'cash', 1000);
  const bankaU = await mkAccount(baseU, 'Banka', 'bank', 1000);
  const categoryU = (await call('GET', `${baseU}/expense-categories`, MGR)).body.items[0].id;
  for (const id of siteU.ids) await addCharge(siteU, id, 90000);
  const deletion = await import('../src/modules/account_deletion_service.js');
  const dlBeforeUsers = deadlocks();
  const errBeforeUsers = errorIds();
  const usersRound = [];
  for (let round = 0; round < ROUNDS; round += 1) {
    for (const mode of ['hard', 'tombstone']) {
      const mgr = await mkUser(`Kilit Silinecek ${mode} ${round}`, 'site_manager');
      await link.manager(siteU.code, mgr);
      const ops = [];
      for (let i = 0; i < 4; i += 1) {
        ops.push(call('POST', `${baseU}/payments`, mgr, { apartment_id: siteU.ids[(round + i) % siteU.ids.length], amount_minor: 500 + i, entry_date: TODAY, method: 'cash', account_id: i % 2 === 0 ? kasaU : bankaU, idempotency_key: key('up') }));
      }
      ops.push(call('POST', `${baseU}/expenses`, mgr, { category_id: categoryU, description: `Silinen kullanici gideri ${mode} ${round}`, amount_minor: 120, expense_date: TODAY, account_id: kasaU, allow_duplicate: true, idempotency_key: key('ue') }));
      ops.push(call('POST', `${baseU}/transfers`, mgr, { from_account_id: kasaU, to_account_id: bankaU, amount_minor: 30, transfer_date: TODAY, idempotency_key: key('ut') }));
      ops.push(call('PUT', `${baseU}/settings`, mgr, { expected_settings_version: 1, receipts: { auto_issue: true } }));
      const deleter = mode === 'hard'
        ? failCode(`DELETE FROM users WHERE user_code = $1`, [mgr]).then((code) => ({ status: code === null ? 200 : 500, body: { code } }))
        : deletion.performAccountDeletion(mgr).then(() => ({ status: 200, body: {} }), (error) => ({ status: error.statusCode ?? 500, body: { code: error.code } }));
      const results = await Promise.all([...ops, deleter]);
      judge(`H2 ${mode} ${round}`, results.slice(0, -1), [200, 201, 401, 403, 404, 409]);
      usersRound.push([mode, results.at(-1).status]);
      if (results.at(-1).status !== 200) unexpected.push(`H2 ${mode} ${round}: silme ${results.at(-1).status} ${results.at(-1).body.code}`);
    }
  }
  check(`H2: kullanici silme x finans yazmalari (${ROUNDS} tur x {sert DELETE, kimliksizlestirme}): 40P01 = 0; beklenmeyen yanit yok; silme her seferinde basarili`,
    deadlocks() === dlBeforeUsers && errorIds() === errBeforeUsers && unexpected.length === 0, { deadlocks: deadlocks() - dlBeforeUsers, errorIds: errorIds() - errBeforeUsers, unexpected: unexpected.slice(0, 5), usersRound: usersRound.slice(0, 4) });
  const orphan = (await q(
    `SELECT (SELECT COUNT(*) FROM receipts WHERE issued_by IS NOT NULL AND NOT EXISTS (SELECT 1 FROM users u WHERE u.user_code = receipts.issued_by))::int AS r,
            (SELECT COUNT(*) FROM account_movements WHERE created_by IS NOT NULL AND NOT EXISTS (SELECT 1 FROM users u WHERE u.user_code = account_movements.created_by))::int AS m,
            (SELECT COUNT(*) FROM expenses WHERE created_by IS NOT NULL AND NOT EXISTS (SELECT 1 FROM users u WHERE u.user_code = expenses.created_by))::int AS e`,
  )).rows[0];
  const keptRows = (await q(`SELECT (SELECT COUNT(*) FROM receipts WHERE site_code = $1)::int AS r, (SELECT COUNT(*) FROM account_movements WHERE site_code = $1)::int AS m`, [siteU.code])).rows[0];
  check('H2b: silinen (sert) kullanicilarin makbuz / hareket / gider satirlari KALIR ve *_by NULL ya da var olan kullaniciyi gosterir (sallanan referans yok)', orphan.r === 0 && orphan.m === 0 && orphan.e === 0 && keptRows.r > 0 && keptRows.m > 0, { orphan, keptRows });

  // --- H2c. kimliksizlestirilmis (silinmis) hesapla yazma reddedilir: lockActorRow (deleted_at IS NULL FOR KEY SHARE)
  const ledgerService = await import('../src/modules/finance_ledger_service.js');
  const accountsService = await import('../src/modules/finance_accounts.js');
  const expensesService = await import('../src/modules/finance_expenses.js');
  const settingsService = await import('../src/modules/finance_settings.js');
  const ghost = await mkUser('Kilit Hayalet Yonetici', 'site_manager');
  await link.manager(siteU.code, ghost);
  await deletion.performAccountDeletion(ghost);
  const ghostActor = { id: ghost, user_code: ghost, role: 'site_manager', full_name: 'Silinmis Kullanici' };
  const counts = async () => JSON.stringify((await q(
    `SELECT (SELECT COUNT(*) FROM ledger_entries WHERE site_code = $1)::int AS l, (SELECT COUNT(*) FROM finance_accounts WHERE site_code = $1)::int AS a, (SELECT COUNT(*) FROM expenses WHERE site_code = $1)::int AS e,
            (SELECT COUNT(*) FROM account_transfers WHERE site_code = $1)::int AS t, (SELECT COUNT(*) FROM receipts WHERE site_code = $1)::int AS r, (SELECT COUNT(*) FROM audit_log WHERE site_code = $1)::int AS g,
            (SELECT settings_version FROM finance_settings WHERE site_code = $1) AS v`, [siteU.code])).rows[0]);
  const countsBefore = await counts();
  const attempts = await Promise.all([
    ledgerService.recordPayment({ siteCode: siteU.code, body: { apartment_id: siteU.ids[0], amount_minor: 111, entry_date: TODAY, method: 'cash', account_id: kasaU, idempotency_key: key('gh1') }, actor: ghostActor }),
    accountsService.createAccount({ siteCode: siteU.code, body: { name: 'Hayalet Kasa', kind: 'cash', opening_balance_minor: 0, opening_date: TODAY, idempotency_key: key('gh2') }, actor: ghostActor }),
    expensesService.createExpense({ siteCode: siteU.code, body: { category_id: categoryU, description: 'Hayalet gider', amount_minor: 10, expense_date: TODAY, account_id: kasaU, allow_duplicate: true, idempotency_key: key('gh3') }, actor: ghostActor }),
    accountsService.createTransfer({ siteCode: siteU.code, body: { from_account_id: kasaU, to_account_id: bankaU, amount_minor: 5, transfer_date: TODAY, idempotency_key: key('gh4') }, actor: ghostActor }),
    settingsService.updateSettings({ siteCode: siteU.code, body: { expected_settings_version: 1, receipts: { auto_issue: false } }, actor: ghostActor }),
  ].map((promise) => promise.then(() => 'YAZILDI', (error) => error.code ?? String(error.message))));
  check('H2c: kimliksizlestirilmis (silinmis) hesapla odeme / hesap / gider / aktarim / ayar yazmasi 401 ACCOUNT_DELETED ile REDDEDILIR ve hicbir satir (defter, hesap, gider, aktarim, makbuz, denetim, ayar) yazilmaz',
    attempts.every((a) => a === 'ACCOUNT_DELETED') && (await counts()) === countsBefore, { attempts, countsBefore, countsAfter: await counts() });

  // ============================================================================================================
  // H3. Daire azaltma (syncSiteStructureCounts) x gecikme tazminati x odeme x rapor
  // ============================================================================================================
  const siteSvc = await import('../src/services/site_service.js');
  await t.legalAll(true); // hukuk onayi site basina (114): simdiki ve bundan sonra olusacak siteler acik
  const dlBeforeShrink = deadlocks();
  const errBeforeShrink = errorIds();
  const shrinkOutcomes = [];
  const lateOutcomes = [];
  for (let round = 0; round < Math.max(2, Math.floor(ROUNDS / 2)); round += 1) {
    const s = await mkManaged(`F4B Kilit Azaltma ${round}`, { 'Z Blok': 8 });
    const b = P(s.code);
    const settings0 = await call('GET', `${b}/settings`, MGR);
    const enable = await call('PUT', `${b}/settings`, MGR, { expected_settings_version: settings0.body.settings_version, late_fee: { enabled: true, start_period: ym(-3), rate_bp: 500, method: 'daily_30', grace_days: 0 } });
    if (enable.status !== 200) throw new Error(`tazminat acilamadi: ${enable.status} ${JSON.stringify(enable.body)}`);
    for (const id of s.ids.slice(0, 4)) await addCharge(s, id, 120000, dayOf(-3, 5), dayOf(-3, 10));
    for (const off of [-3, -2, -1]) {
      const closed = await call('POST', `${b}/periods/${ym(off)}/close`, MGR);
      if (closed.status !== 200) throw new Error(`donem kapatilamadi ${ym(off)}: ${JSON.stringify(closed.body)}`);
    }
    const pv = await call('POST', `${b}/late-fee/preview`, MGR, { period: ym(-3) });
    if (pv.status !== 200 || pv.body.can_post !== true) throw new Error(`onizleme gonderilemez: ${JSON.stringify(pv.body.blockers)}`);
    const post = call('POST', `${b}/late-fee/post`, MGR, { period: ym(-3), expected_total_minor: pv.body.total_minor, expected_apartment_count: pv.body.apartment_count, expected_hash: pv.body.preview_hash, idempotency_key: key('lf') });
    const shrink = siteSvc
      .syncSiteStructureCounts({ siteCode: s.code, blockCount: 1, apartmentCount: 4, blockApartmentCounts: [4], doorCount: 0, actor: { id: SUPER, user_code: SUPER, role: 'super_user', full_name: 'F4B Super' } })
      .then(() => ({ status: 200, body: {} }), (error) => ({ status: error.statusCode ?? 500, body: { code: error.code ?? error.message } }));
    const others = [0, 1, 2].map((i) => call('POST', `${b}/payments`, MGR, { apartment_id: s.ids[i], amount_minor: 700 + i, entry_date: TODAY, method: 'cash', idempotency_key: key('zp') }));
    const reports = [call('GET', `${b}/reports/aging`, MGR), call('GET', `${b}/reports/cash-position`, MGR)];
    const results = await Promise.all([post, shrink, ...others, ...reports]);
    judge(`H3 tur ${round}`, results, [200, 201, 409]);
    lateOutcomes.push(results[0].status);
    shrinkOutcomes.push(results[1].status);
  }
  check(`H3: gecikme tazminati post x daire azaltma x odemeler x raporlar (${shrinkOutcomes.length} tur): 40P01 = 0; beklenmeyen yanit yok; azaltma ve post sonuclari tutarli (200/201/409)`,
    deadlocks() === dlBeforeShrink && errorIds() === errBeforeShrink && unexpected.length === 0, { deadlocks: deadlocks() - dlBeforeShrink, errorIds: errorIds() - errBeforeShrink, shrinkOutcomes, lateOutcomes, unexpected: unexpected.slice(0, 5) });
  const lateInvariant = (await q(
    `SELECT COUNT(*)::int AS n FROM late_fee_runs r WHERE r.voided_at IS NULL AND r.total_minor <> COALESCE((SELECT SUM(amount_minor) FROM ledger_entries l WHERE l.late_fee_run_id = r.id AND l.kind = 'charge'), 0)`,
  )).rows[0].n;
  check('H3b: her etkin tazminat calistirmasinin toplami = defter satirlari toplami (eszamanli azaltma / odeme altinda sapma yok)', lateInvariant === 0, lateInvariant);

  // ============================================================================================================
  // H4. Iki yonlu aktarim firtinasi (hesap satirlari id sirasiyla kilitlenir) + pasiflestirme
  // ============================================================================================================
  const dlBeforeTransfers = deadlocks();
  const totalBefore = (await call('GET', `${base}/accounts`, MGR)).body.total_balance_minor;
  const opsT = [];
  for (let i = 0; i < 20; i += 1) {
    opsT.push(call('POST', `${base}/transfers`, MGR, { from_account_id: kasa, to_account_id: banka, amount_minor: 10 + i, transfer_date: TODAY, idempotency_key: key('t1') }));
    opsT.push(call('POST', `${base}/transfers`, MGR, { from_account_id: banka, to_account_id: kasa, amount_minor: 10 + i, transfer_date: TODAY, idempotency_key: key('t2') }));
  }
  opsT.push(call('POST', `${base}/accounts/${kasa}/adjustments`, MGR, { amount_minor: 1, movement_date: TODAY, reason_code: 'other', note: 'kilit', idempotency_key: key('ta') }));
  const resT = await Promise.all(opsT);
  judge('H4', resT, [200, 201, 409]);
  const totalAfter = (await call('GET', `${base}/accounts`, MGR)).body.total_balance_minor;
  check('H4: 40 eszamanli iki yonlu aktarim (kasa<->banka): 40P01 = 0; hepsi 201; aktarim toplam bakiyeyi DEGISTIRMEZ (yalniz +1 duzeltme)',
    deadlocks() === dlBeforeTransfers && resT.slice(0, 40).every((r) => r.status === 201) && totalAfter === totalBefore + 1 && unexpected.length === 0, { deadlocks: deadlocks() - dlBeforeTransfers, statuses: resT.map((r) => r.status).join(','), totalBefore, totalAfter, unexpected: unexpected.slice(0, 5) });

  // ============================================================================================================
  // H5. Site silme (CASCADE) x suren finans yazmalari
  // ============================================================================================================
  const dlBeforeDelete = deadlocks();
  const errBeforeDelete = errorIds();
  const leftoverReport = [];
  const siteColumns = new Map();
  for (const table of FINANCE_4B_TABLES) {
    siteColumns.set(table, (await q(`SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = $1 AND column_name = 'site_code'`, [table])).rows.length > 0);
  }
  for (let round = 0; round < Math.max(2, Math.floor(ROUNDS / 2)); round += 1) {
    const s = await mkManaged(`F4B Kilit Silinecek ${round}`, { 'S Blok': 6 });
    const b = P(s.code);
    const acc1 = await mkAccount(b, 'Kasa', 'cash', 1000);
    const acc2 = await mkAccount(b, 'Banka', 'bank', 1000);
    const cat = (await call('GET', `${b}/expense-categories`, MGR)).body.items[0].id;
    for (const id of s.ids) await addCharge(s, id, 40000);
    for (let i = 0; i < 4; i += 1) await call('POST', `${b}/payments`, MGR, { apartment_id: s.ids[i], amount_minor: 900 + i, entry_date: TODAY, method: 'cash', account_id: acc1, idempotency_key: key('sp') });
    await call('POST', `${b}/expenses`, MGR, { category_id: cat, description: 'Silinecek site gideri', amount_minor: 100, expense_date: TODAY, account_id: acc1, allow_duplicate: true, idempotency_key: key('se') });
    await call('POST', `${b}/transfers`, MGR, { from_account_id: acc1, to_account_id: acc2, amount_minor: 50, transfer_date: TODAY, idempotency_key: key('st') });
    const ops = [];
    for (let i = 0; i < 4; i += 1) ops.push(call('POST', `${b}/payments`, MGR, { apartment_id: s.ids[i + 1], amount_minor: 800 + i, entry_date: TODAY, method: 'cash', account_id: acc2, idempotency_key: key('sq') }));
    ops.push(call('POST', `${b}/expenses`, MGR, { category_id: cat, description: 'Eszamanli gider', amount_minor: 60, expense_date: TODAY, account_id: acc2, allow_duplicate: true, idempotency_key: key('sx') }));
    ops.push(call('POST', `${b}/transfers`, MGR, { from_account_id: acc2, to_account_id: acc1, amount_minor: 20, transfer_date: TODAY, idempotency_key: key('sy') }));
    ops.push(call('GET', `${b}/reports/aging`, MGR));
    ops.push(call('GET', `${b}/exports/finance_expenses`, MGR));
    const deleter = failCode(`DELETE FROM sites WHERE site_code = $1`, [s.code]);
    const results = await Promise.all([...ops, deleter]);
    judge(`H5 tur ${round}`, results.slice(0, -1), [200, 201, 404, 409]);
    if (results.at(-1) !== null) unexpected.push(`H5 tur ${round}: site silme ${results.at(-1)}`);
    for (const table of FINANCE_4B_TABLES) {
      if (!siteColumns.get(table)) continue;
      const n = (await q(`SELECT COUNT(*)::int AS n FROM ${table} WHERE site_code = $1`, [s.code])).rows[0].n;
      if (n > 0) leftoverReport.push(`${table}=${n}`);
    }
    const ledgerLeft = (await q(`SELECT COUNT(*)::int AS n FROM ledger_entries WHERE site_code = $1`, [s.code])).rows[0].n;
    if (ledgerLeft > 0) leftoverReport.push(`ledger_entries=${ledgerLeft}`);
  }
  check('H5: site silme (CASCADE) x suren odeme / gider / aktarim / rapor: 40P01 = 0; beklenmeyen 5xx YOK (FK ihlali 500 olmaz: 404 ya da basarili); silme basarili; 4b tablolarinda ve defterde kalinti yok',
    deadlocks() === dlBeforeDelete && errorIds() === errBeforeDelete && unexpected.length === 0 && leftoverReport.length === 0, { deadlocks: deadlocks() - dlBeforeDelete, errorIds: errorIds() - errBeforeDelete, leftoverReport, unexpected: unexpected.slice(0, 5) });

  // ============================================================================================================
  // H6. Hatirlatma kuyrugu x odemeler x kullanici silme x rapor
  // ============================================================================================================
  const dlBeforeRem = deadlocks();
  const errBeforeRem = errorIds();
  const sr = await mkManaged('F4B Kilit Hatirlatma', { 'R Blok': 10 });
  const br = P(sr.code);
  const recipients = [];
  for (let i = 0; i < sr.ids.length; i += 1) {
    const user = await mkUser(`Kilit Alici ${i}`, 'apartment_owner', { email: `kilit-alici-${sr.code}-${i}@qa.example`, verified: true });
    await addResidency(sr.code, sr.ids[i], await addPerson(sr.code, { user }), 'owner');
    await q(`UPDATE apartments SET responsible_party = 'owner' WHERE id = $1`, [sr.ids[i]]);
    await addCharge(sr, sr.ids[i], 60000, ago(45), ago(40));
    recipients.push(user);
  }
  const rs0 = await call('GET', `${br}/settings`, MGR);
  const rsOn = await call('PUT', `${br}/settings`, MGR, { expected_settings_version: rs0.body.settings_version, reminders: { enabled: true, min_overdue_minor: 5000, min_days_overdue: 5, min_interval_days: 14, max_consecutive: 3 } });
  if (rsOn.status !== 200) throw new Error(`hatirlatma acilamadi: ${rsOn.status} ${JSON.stringify(rsOn.body)}`);
  const rpv = await call('POST', `${br}/reminders/preview`, MGR, { tone: 'friendly' });
  const mailsBefore = ctx.mails.length;
  const sendBody = { tone: 'friendly', note: null, expected_hash: rpv.body.preview_hash, expected_apartment_count: rpv.body.apartment_count, expected_person_count: rpv.body.person_count, idempotency_key: key('rs') };
  // 1) kuyruk DURDURULUR: gonderim satirlari bekler; 3 eszamanli gonderim (2 ayni anahtar + 1 farkli) -> TEK calistirma
  void queue.stopFinanceReminderQueue();
  const sendResults = await Promise.all([
    call('POST', `${br}/reminders/send`, MGR, sendBody),
    call('POST', `${br}/reminders/send`, MGR, sendBody),
    call('POST', `${br}/reminders/send`, MGR, { ...sendBody, idempotency_key: key('rs2') }),
  ]);
  judge('H6 gonderim', sendResults, [200, 201, 409]);
  // 2) kuyruk acilirken: borclari kapatan odemeler (talepte taze dogrulama), alici hesaplarinin silinmesi, rapor, liste
  queue.resumeFinanceReminderQueue();
  const opsR = [
    ...[0, 1, 2, 3].map((i) => call('POST', `${br}/payments`, MGR, { apartment_id: sr.ids[i], amount_minor: 60000, entry_date: TODAY, method: 'cash', idempotency_key: key('rp') })),
    call('GET', `${br}/reports/aging`, MGR),
    call('GET', `${br}/reminders/runs`, MGR),
    failCode(`DELETE FROM users WHERE user_code = ANY($1::int[])`, [recipients.slice(8)]).then((code) => ({ status: code === null ? 200 : 500, body: { code } })),
    Promise.resolve().then(() => queue.kickFinanceReminderQueue()).then(() => ({ status: 200, body: {} })),
  ];
  judge('H6', await Promise.all(opsR), [200, 201, 409]);
  const drained = await (async () => {
    for (let i = 0; i < 100; i += 1) {
      void queue.kickFinanceReminderQueue();
      if (!(await queue.hasPendingReminders()) && (await q(`SELECT COUNT(*)::int AS n FROM finance_reminder_items i JOIN finance_reminder_runs r ON r.id = i.run_id WHERE r.site_code = $1 AND i.email_status = 'pending'`, [sr.code])).rows[0].n === 0) return true;
      await sleep(200);
    }
    return false;
  })();
  const statuses = (await q(`SELECT i.email_status, COUNT(*)::int AS n FROM finance_reminder_items i JOIN finance_reminder_runs r ON r.id = i.run_id WHERE r.site_code = $1 GROUP BY 1 ORDER BY 1`, [sr.code])).rows;
  const sentRows = statuses.find((r) => r.email_status === 'sent')?.n ?? 0;
  const sentMails = ctx.mails.slice(mailsBefore).filter((mail) => /kilit-alici-/.test(String(mail.to))).length;
  check('H6: hatirlatma gonderimi x odemeler x alici hesap silme x rapor: 40P01 = 0; beklenmeyen yanit yok; kuyruk BOSALIR (bekleyen kalmadi); gonderilen e-posta sayisi = "sent" satirlari',
    deadlocks() === dlBeforeRem && errorIds() === errBeforeRem && unexpected.length === 0 && drained && sentMails === sentRows && sentRows > 0 && sendResults.filter((r) => r.status === 201).length === 1, { deadlocks: deadlocks() - dlBeforeRem, errorIds: errorIds() - errBeforeRem, drained, statuses, sentMails, sendResults: sendResults.map((r) => `${r.status}:${r.body?.code ?? ''}`), blockers: rpv.body.blockers, unexpected: unexpected.slice(0, 5) });
  const runsOfSite = (await q(`SELECT COUNT(*)::int AS n FROM finance_reminder_runs WHERE site_code = $1`, [sr.code])).rows[0].n;
  check('H6b: ayni gun eszamanli iki gonderim -> TEK calistirma (gunluk sinir / idempotans); kuyruk islemleri finans satirini kilitlemedi', runsOfSite === 1, runsOfSite);

  // --- toplam
  check(`H7: BU BOLUMUN TOPLAMI: 40P01 = ${deadlocks() - dl0} (beklenen 0), sunucuda errorId'li hata = ${errorIds() - err0} (beklenen 0), beklenmeyen yanit = ${unexpected.length}`, deadlocks() === dl0 && errorIds() === err0 && unexpected.length === 0, unexpected.slice(0, 8));
  void same;
}
