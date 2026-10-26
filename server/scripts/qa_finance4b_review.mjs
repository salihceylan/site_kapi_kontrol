// Finans Faz 4b QA bolumu: R. Bagimsiz R10 incelemesi duzeltmeleri (para / hukuk / gizlilik). scripts/qa_finance4b.mjs tarafindan yuklenir.
// Her P1 icin gercek PostgreSQL'de BASARISIZ -> GECEN sinama: duzeltmeden once bu bolum basarisizdi (bkz. docs/PLATFORM_FINANS_4B.md "R10 duzeltmeleri").

export default async function sectionReview(t) {
  const { check, same, q, call, ctx, TODAY, ago, ym, monthStart, mkManaged, mkUser, addPerson, addResidency, P, key, users, pool } = t;
  const { SUPER, MGR } = users;
  const mails = ctx.mails;
  const queue = await import('../src/modules/finance_reminder_queue.js');
  const reports = await import('../src/modules/finance_reports.js');
  queue.reminderQueueHooks.sleep = async () => {};
  console.log('--- R. R10 duzeltmeleri ---');
  const periodOf = (iso) => `${iso.slice(0, 7)}-01`;
  const addCharge = (site, aptId, amount, dueDaysAgo) =>
    q(`INSERT INTO ledger_entries (site_code, apartment_id, kind, amount_minor, period, entry_date, due_date, payer_party) VALUES ($1, $2, 'charge', $3, $4::date, $5::date, $6::date, 'both')`, [
      site.code, aptId, amount, periodOf(ago(dueDaysAgo + 5)), ago(dueDaysAgo + 5), ago(dueDaysAgo),
    ]);

  // ============================================================================================================
  // R1-R2 (P1-1, P1-2): hatirlatma kuyrugu GONDERIM ANINDA kapilari ve alici iliskisini yeniden denetler
  // ============================================================================================================
  await call('PUT', '/admin/finance-legal-gate', SUPER, { legal_ok: true });
  let counter = 0;
  /** Kuyruk DURDURULMUSKEN bir hatirlatma calistirmasi olusturur (satir bekler); sonra senaryo kapiyi / iliskiyi bozar. */
  const mkReminderRun = async (label, { extraTenant = false } = {}) => {
    counter += 1;
    const tag = `rv${counter}${Date.now() % 100000}`;
    const site = await mkManaged(`F4B Inceleme ${label}`, { 'R Blok': 2 });
    const [a1, a2] = site.ids;
    await q(`UPDATE apartments SET responsible_party = 'owner' WHERE id = $1`, [a1]);
    const email = `${tag}-malik@qa.example`;
    const owner = await mkUser(`Inceleme Malik ${tag}`, 'apartment_owner', { email, verified: true });
    const person = await addPerson(site.code, { user: owner });
    await addResidency(site.code, a1, person, 'owner');
    await addCharge(site, a1, 90000, 40);
    if (extraTenant) {
      // malik baska dairede kiraci olarak AKTIF kalir (a2); a1'den cikarilirsa yalniz a1 icin alici olmaktan cikar
      await addResidency(site.code, a2, person, 'tenant');
      await q(`UPDATE apartments SET responsible_party = 'tenant' WHERE id = $1`, [a2]);
    }
    const base = P(site.code);
    const s0 = await call('GET', `${base}/settings`, MGR);
    const on = await call('PUT', `${base}/settings`, MGR, { expected_settings_version: s0.body.settings_version, reminders: { enabled: true, min_overdue_minor: 5000, min_days_overdue: 5, min_interval_days: 14, max_consecutive: 3 } });
    if (on.status !== 200) throw new Error(`hatirlatma acilamadi: ${on.status} ${JSON.stringify(on.body)}`);
    const pv = await call('POST', `${base}/reminders/preview`, MGR, { tone: 'friendly' });
    void queue.stopFinanceReminderQueue(); // senaryo kapiyi bozana kadar satirlar BEKLER
    const send = await call('POST', `${base}/reminders/send`, MGR, { tone: 'friendly', note: null, expected_hash: pv.body.preview_hash, expected_apartment_count: pv.body.apartment_count, expected_person_count: pv.body.person_count, idempotency_key: key('rvs') });
    if (send.status !== 201) throw new Error(`gonderim olusmadi: ${send.status} ${JSON.stringify(send.body)}`);
    return { site, base, a1, a2, owner, person, email, runId: send.body.run.id };
  };
  /** Kuyrugu acar, TEK tur calistirir, tekrar durdurur. Sonuc: bu calistirmanin satir durumlari ve ilgili adrese giden ileti sayisi. */
  const drain = async (ctxRun) => {
    mails.length = 0;
    queue.resumeFinanceReminderQueue();
    await queue.kickFinanceReminderQueue();
    void queue.stopFinanceReminderQueue();
    const states = (await q(`SELECT email_status, (email IS NULL) AS cleared FROM finance_reminder_items WHERE run_id = $1`, [ctxRun.runId])).rows;
    return { states: states.map((r) => r.email_status), cleared: states.every((r) => r.cleared), sent: mails.filter((m) => String(m.to).toLowerCase() === ctxRun.email.toLowerCase()).length };
  };
  const audits = async (ctxRun) => (await q(`SELECT details FROM audit_log WHERE site_code = $1 AND action = 'finance.reminder.cancelled' ORDER BY id`, [ctxRun.site.code])).rows.map((r) => r.details);

  // kontrol grubu: kapi acik, iliski ayni -> ileti GIDER (kurulum dogrulamasi)
  const control = await mkReminderRun('kontrol');
  const controlResult = await drain(control);
  check('R0: kontrol: kapilar acik ve iliski ayniyken kuyruk tek iletiyi GONDERIR (kurulum dogru)', same(controlResult.states, ['sent']) && controlResult.sent === 1, controlResult);

  // P1-1 / S-A: hukuk onayi geri alinir
  const legal = await mkReminderRun('hukuk');
  await call('PUT', '/admin/finance-legal-gate', SUPER, { legal_ok: false });
  const legalResult = await drain(legal);
  await call('PUT', '/admin/finance-legal-gate', SUPER, { legal_ok: true });
  const legalAudit = await audits(legal);
  check('R1: P1-1 hukuk onayi (finance.legal_ok) GERI ALINIRSA kuyruktaki hatirlatma GONDERILMEZ: satir cancelled, adres silinir, ileti 0; nedeni denetimde (gate kodu)',
    same(legalResult.states, ['cancelled']) && legalResult.cleared && legalResult.sent === 0 && legalAudit.some((d) => d?.gate === 'legal_gate' && d?.cancelled_count === 1), { legalResult, legalAudit });

  // P1-1 / S-B: finans modulu kapali sayilirsa. Kural 25 (079): finans TEMEL modul, API'den KAPATILAMAZ (400 MODULE_NOT_TOGGLEABLE); ancak kuyruk site_modules satirini DOGRUDAN SQL ile
  // okur (satir yoksa acik): satir elle / eski kayitla enabled=FALSE ise (ensureDbSchema bunu her acilista TRUE'ya ceker) hatirlatma yine GONDERILMEZ - savunma katmani korunur.
  const mod = await mkReminderRun('modul');
  const closeTry = await call('PUT', `/manager/sites/${mod.site.code}/modules/finance`, SUPER, { enabled: false });
  await q(`INSERT INTO site_modules (site_code, module_code, enabled) VALUES ($1, 'finance', FALSE) ON CONFLICT (site_code, module_code) DO UPDATE SET enabled = FALSE`, [mod.site.code]);
  const modResult = await drain(mod);
  await q(`DELETE FROM site_modules WHERE site_code = $1 AND module_code = 'finance'`, [mod.site.code]);
  const modAudit = await audits(mod);
  check('R2: P1-1 finans temel modul API ile kapatilamaz (400 MODULE_NOT_TOGGLEABLE); site_modules satiri enabled=FALSE ise bekleyen hatirlatma yine GONDERILMEZ (cancelled, ileti 0, neden module_disabled)',
    closeTry.status === 400 && closeTry.body.code === 'MODULE_NOT_TOGGLEABLE' && same(modResult.states, ['cancelled']) && modResult.cleared && modResult.sent === 0 && modAudit.some((d) => d?.gate === 'module_disabled'), { closeTry: closeTry.body, modResult, modAudit });

  // P1-1 / S-C: yonetici hatirlatma ayarini kapatir
  const setting = await mkReminderRun('ayar');
  const st = await call('GET', `${setting.base}/settings`, MGR);
  const off = await call('PUT', `${setting.base}/settings`, MGR, { expected_settings_version: st.body.settings_version, reminders: { enabled: false } });
  const settingResult = await drain(setting);
  const settingAudit = await audits(setting);
  check('R3: P1-1 hatirlatma AYARI kapatilirsa bekleyen hatirlatma GONDERILMEZ (cancelled, ileti 0, neden reminders_disabled)',
    off.status === 200 && same(settingResult.states, ['cancelled']) && settingResult.cleared && settingResult.sent === 0 && settingAudit.some((d) => d?.gate === 'reminders_disabled'), { settingResult, settingAudit });

  // P1-2 / S-D: malik daireden cikarilir (baska dairede kiraci olarak aktif kalir): eski dairesinin borcu icin ileti GITMEZ
  const moved = await mkReminderRun('iliski', { extraTenant: true });
  await q(`UPDATE apartment_residencies SET is_current = FALSE WHERE site_code = $1 AND apartment_id = $2 AND person_id = $3`, [moved.site.code, moved.a1, moved.person]);
  const movedResult = await drain(moved);
  check('R4: P1-2 kisi DAIREDEN CIKARILMISSA (iliski artik guncel degil) o dairenin borcu icin ileti GITMEZ (resolved, adres silinir, ileti 0)',
    same(movedResult.states, ['resolved']) && movedResult.cleared && movedResult.sent === 0, movedResult);

  // P1-2 / S-H: daire gonderimden sonra MUAF tutulur
  const excl = await mkReminderRun('muaf');
  const addEx = await call('PUT', `${excl.base}/reminders/exclusions/${excl.a1}`, MGR, { reason: 'dava' });
  const exclResult = await drain(excl);
  check('R5: P1-2 daire gonderimden SONRA muaf tutulursa ileti GITMEZ (resolved, ileti 0)', addEx.status === 200 && same(exclResult.states, ['resolved']) && exclResult.cleared && exclResult.sent === 0, exclResult);

  // P1-2 (İP-1A / G12 ile BİLEREK DEĞİŞTİ): hatırlatma HESABIN SAHİBİNE gider. Sorumluluk değişimi (owner -> tenant) geçmiş borcun hesabını DEĞİŞTİRMEZ
  // (borç ev sahibi hesabında kalır, yeni aidat kiracı hesabına yazılır): ev sahibi hesabındaki borç için ileti malike GİDER. Kişi hesabın sahibi olmaktan
  // çıkarsa (ilişkisi aile üyesine çevrildi) ileti GİTMEZ (R6b). Daireden çıkarılma R4'tedir.
  const resp = await mkReminderRun('sorumlu');
  const tenantUser = await mkUser('Inceleme Kiraci', 'apartment_owner', { email: `rvk${counter}${Date.now() % 100000}@qa.example`, verified: true });
  await addResidency(resp.site.code, resp.a1, await addPerson(resp.site.code, { user: tenantUser }), 'tenant');
  await q(`UPDATE apartments SET responsible_party = 'tenant' WHERE id = $1`, [resp.a1]);
  const respResult = await drain(resp);
  check('R6: P1-2 (İP-1A) daire sorumlusu degisse de (owner -> tenant) EV SAHIBI HESABINDAKI borc icin ileti malike GIDER (sent 1); kiraci bu borc icin alici degil', same(respResult.states, ['sent']) && respResult.sent === 1, respResult);
  const fam = await mkReminderRun('aile');
  await q(`UPDATE apartment_residencies SET relation = 'family_member' WHERE site_code = $1 AND apartment_id = $2 AND person_id = $3`, [fam.site.code, fam.a1, fam.person]);
  const famResult = await drain(fam);
  check('R6b: P1-2 (İP-1A) kisi hesabin sahibi olmaktan cikarsa (iliski aile uyesi) ileti GITMEZ (resolved, adres silinir, ileti 0)', same(famResult.states, ['resolved']) && famResult.cleared && famResult.sent === 0, famResult);

  // ============================================================================================================
  // R7 (P1-3): mutabakatta ayni gecmis ekstre tarihi icin CIFT duzeltme olmaz
  // ============================================================================================================
  const rs = await mkManaged('F4B Inceleme Mutabakat', { 'M Blok': 2 });
  const rb = P(rs.code);
  const acc = await call('POST', `${rb}/accounts`, MGR, { name: 'Mutabakat Hesabi', kind: 'bank', opening_balance_minor: 100000, opening_date: ago(5), idempotency_key: key('ra') });
  const accId = acc.body.account.id;
  const balanceOf = async () => (await call('GET', `${rb}/accounts`, MGR)).body.items.find((a) => a.id === accId).balance_minor;
  const rec = (over = {}) => call('POST', `${rb}/accounts/${accId}/reconciliations`, MGR, { as_of_date: ago(1), statement_balance_minor: 110000, expected_computed_minor: 100000, adjust: { reason_code: 'bank_interest' }, idempotency_key: key('rr'), ...over });
  const rec1 = await rec();
  check('R7: P1-3 ilk mutabakat (as_of dun, ekstre 110000, hesaplanan 100000, duzeltme) 201; bakiye 110000', rec1.status === 201 && rec1.body.reconciliation.adjusted === true && rec1.body.reconciliation.difference_minor === 10000 && (await balanceOf()) === 110000, [rec1.status, rec1.body]);
  const rec2 = await rec(); // ikinci kisi / sayfa yenileme: AYNI tarih ve ekstre, ESKI beklenen deger, baska anahtar
  const adjustments = (await q(`SELECT COUNT(*)::int AS n FROM account_movements WHERE account_id = $1 AND kind = 'adjustment'`, [accId])).rows[0].n;
  check('R7b: P1-3 AYNI as_of icin ikinci mutabakat ikinci duzeltme YAZMAZ: hesap bakiyesi 110000 KALIR (120000 olmaz); duzeltme hareketi 1', (await balanceOf()) === 110000 && adjustments === 1, { status: rec2.status, body: rec2.body, balance: await balanceOf(), adjustments });
  const rec3 = await rec({ expected_computed_minor: 110000 });
  const adjustments3 = (await q(`SELECT COUNT(*)::int AS n FROM account_movements WHERE account_id = $1 AND kind = 'adjustment'`, [accId])).rows[0].n;
  check('R7c: P1-3 guncel hesaplanan bakiyeyle (110000) tekrar mutabakat: fark 0, duzeltme YOK, bakiye 110000', rec3.status === 201 && rec3.body.reconciliation.difference_minor === 0 && rec3.body.reconciliation.adjusted === false && adjustments3 === 1 && (await balanceOf()) === 110000, [rec3.status, rec3.body]);

  // ============================================================================================================
  // R8 (P1-5): rapor semaforu baglanti alinamazsa SIZMAZ
  // ============================================================================================================
  let attempts = 0;
  const flaky = {
    connect: async () => {
      attempts += 1;
      if (attempts <= 3) throw new Error('timeout exceeded when trying to connect');
      return pool.connect();
    },
  };
  const outcomes = [];
  for (let i = 0; i < 3; i += 1) {
    outcomes.push(await reports.withReportSnapshot(rs.code, async () => 'ok', flaky).then(() => 'ok', (error) => error.code ?? error.message));
  }
  const afterLeak = await reports.withReportSnapshot(rs.code, async (client) => (await client.query('SELECT 1 AS one')).rows[0].one, flaky).then((v) => v, (error) => error.code ?? error.message);
  const apiAfter = await call('GET', `${rb}/reports/aging`, MGR);
  check('R8: P1-5 baglanti alinamazsa (3 kez) rapor semaforu SIZMAZ: sayac bos, ardindan rapor 1 doner (REPORT_BUSY degil) ve HTTP raporu 200',
    outcomes.every((o) => o === 'timeout exceeded when trying to connect') && afterLeak === 1 && apiAfter.status === 200 && Object.keys(reports.reportConcurrency()).length === 0, { outcomes, afterLeak, api: apiAfter.status, counters: reports.reportConcurrency() });

  // ============================================================================================================
  // P2 duzeltmeleri
  // ============================================================================================================
  const { RESIDENT } = users;
  const pay = (site, apt, amount, over = {}) =>
    call('POST', `${P(site.code)}/payments`, MGR, { apartment_id: apt, amount_minor: amount, entry_date: TODAY, method: 'cash', idempotency_key: key('rp'), ...over });
  const mkAcc = (base, name, over = {}) => call('POST', `${base}/accounts`, MGR, { name, kind: 'cash', opening_balance_minor: 0, opening_date: ago(5), idempotency_key: key('pa'), ...over });

  // --- P2-1: toplu esleme tekrari govdeyi dogrular
  const bs = await mkManaged('F4B Inceleme Toplu', { 'T Blok': 3 });
  const bb = P(bs.code);
  const bp1 = await pay(bs, bs.ids[0], 1000, { entry_date: ago(2), method: 'cash' });
  const bp2 = await pay(bs, bs.ids[1], 2000, { entry_date: ago(2), method: 'transfer' });
  const accCash = (await mkAcc(bb, 'Toplu Kasa')).body.account.id;
  const accBank = (await mkAcc(bb, 'Toplu Banka', { kind: 'bank' })).body.account.id;
  const assignBody = { account_by_method: { cash: accCash, transfer: accBank } };
  const apv = await call('POST', `${bb}/accounts/assign-payments/preview`, MGR, assignBody);
  const assignKey = key('as');
  const commitBody = { ...assignBody, expected_count: apv.body.count, expected_total_minor: apv.body.total_minor, expected_hash: apv.body.preview_hash, idempotency_key: assignKey };
  const commit1 = await call('POST', `${bb}/accounts/assign-payments/commit`, MGR, commitBody);
  const commit2 = await call('POST', `${bb}/accounts/assign-payments/commit`, MGR, commitBody);
  const commitSwapped = await call('POST', `${bb}/accounts/assign-payments/commit`, MGR, { ...commitBody, account_by_method: { cash: accBank, transfer: accCash } });
  const commitFake = await call('POST', `${bb}/accounts/assign-payments/commit`, MGR, { ...commitBody, expected_count: 1, expected_total_minor: 1000 });
  check('R9: P2-1 toplu esleme TEKRARI govdeyi dogrular: ayni govde 200 replay; baska hesap eslemesi ya da sahte ozet (sayi / toplam) 409 IDEMPOTENCY_CONFLICT',
    bp1.status === 201 && bp2.status === 201 && commit1.status === 201 && commit2.status === 200 && commit2.body.replayed === true && commitSwapped.status === 409 && commitSwapped.body.code === 'IDEMPOTENCY_CONFLICT' && commitFake.status === 409 && commitFake.body.code === 'IDEMPOTENCY_CONFLICT',
    [commit1.status, commit2.status, commitSwapped.status, commitSwapped.body, commitFake.status]);

  // --- P2-2: diger tekrar karsilastirma bosluklari
  const cp = await pay(bs, bs.ids[2], 5000, { account_id: accCash });
  const corrKey = key('cc');
  const corr = (over = {}) => call('POST', `${bb}/entries/${cp.body.entry.id}/correct`, MGR, { amount_minor: 5100, entry_date: TODAY, method: 'cash', account_id: accBank, idempotency_key: corrKey, ...over });
  const corr1 = await corr();
  const corr2 = await corr();
  const corr3 = await corr({ account_id: accCash });
  check('R10: P2-2 duzeltme (correct) TEKRARI hesabi karsilastirir: ayni govde 200; farkli account_id 409 IDEMPOTENCY_CONFLICT', corr1.status === 201 && corr2.status === 200 && corr3.status === 409 && corr3.body.code === 'IDEMPOTENCY_CONFLICT', [corr1.status, corr2.status, corr3.status, corr3.body]);
  const accKey = key('ac');
  const acc1 = await mkAcc(bb, 'Tekrar Hesabi', { idempotency_key: accKey });
  const acc2 = await mkAcc(bb, 'Tekrar Hesabi', { idempotency_key: accKey });
  const acc3 = await mkAcc(bb, 'Tekrar Hesabi', { idempotency_key: accKey, opening_date: ago(6) });
  check('R11: P2-2 hesap olusturma TEKRARI acilis tarihini karsilastirir: ayni govde 200; farkli opening_date 409', acc1.status === 201 && acc2.status === 200 && acc3.status === 409 && acc3.body.code === 'IDEMPOTENCY_CONFLICT', [acc1.status, acc2.status, acc3.status]);
  const recKey = key('rk');
  const recBody = (over = {}) => ({ as_of_date: ago(1), statement_balance_minor: 1000, expected_computed_minor: 0, adjust: { reason_code: 'bank_interest' }, idempotency_key: recKey, ...over });
  const recAcc = acc1.body.account.id;
  const pr1 = await call('POST', `${bb}/accounts/${recAcc}/reconciliations`, MGR, recBody());
  const pr2 = await call('POST', `${bb}/accounts/${recAcc}/reconciliations`, MGR, recBody());
  const pr3 = await call('POST', `${bb}/accounts/${recAcc}/reconciliations`, MGR, recBody({ adjust: { reason_code: 'bank_fee' } }));
  const pr4 = await call('POST', `${bb}/accounts/${recAcc}/reconciliations`, MGR, recBody({ adjust: undefined }));
  check('R12: P2-2 mutabakat TEKRARI duzeltme nedenini / varligini karsilastirir: ayni govde 200; farkli neden ya da duzeltmesiz 409 IDEMPOTENCY_CONFLICT',
    pr1.status === 201 && pr2.status === 200 && pr3.status === 409 && pr3.body.code === 'IDEMPOTENCY_CONFLICT' && pr4.status === 409, [pr1.status, pr2.status, pr3.status, pr4.status]);

  // --- P2-4: tum hesaplar pasifken hesapsiz tahsilat
  const ps = await mkManaged('F4B Inceleme Pasif', { 'P Blok': 2 });
  const pb = P(ps.code);
  const pAcc = (await mkAcc(pb, 'Tek Hesap')).body.account.id;
  await call('PATCH', `${pb}/accounts/${pAcc}`, MGR, { is_active: false });
  const before = (await q(`SELECT COUNT(*)::int AS n FROM ledger_entries WHERE site_code = $1 AND kind = 'payment'`, [ps.code])).rows[0].n;
  const allPassive = await pay(ps, ps.ids[0], 1500);
  const after = (await q(`SELECT COUNT(*)::int AS n FROM ledger_entries WHERE site_code = $1 AND kind = 'payment'`, [ps.code])).rows[0].n;
  await call('PATCH', `${pb}/accounts/${pAcc}`, MGR, { is_active: true });
  const noAccount = await pay(ps, ps.ids[0], 1500);
  const withAccount = await pay(ps, ps.ids[0], 1500, { account_id: pAcc });
  check('R13: P2-4 TUM hesaplar pasifken hesapsiz tahsilat reddedilir (409 ACCOUNT_INACTIVE, kayit yazilmaz; aksi halde esleme + ay kapatma kilitlenirdi); hesap yeniden etkin: hesapsiz ACCOUNT_REQUIRED, hesapli 201',
    allPassive.status === 409 && allPassive.body.code === 'ACCOUNT_INACTIVE' && before === after && noAccount.body.code === 'ACCOUNT_REQUIRED' && withAccount.status === 201, [allPassive.body, before, after, noAccount.body, withAccount.status]);

  // --- P2-6: makbuz dogrulama yaniti tutar / tarih / daire etiketi
  const vr = withAccount.body.receipt;
  const full = await call('GET', `${pb}/receipts/${vr.id}`, MGR);
  const verified = await call('POST', `${pb}/receipts/verify`, MGR, { number: vr.number, code: full.body.verification_code });
  const wrong = await call('POST', `${pb}/receipts/verify`, MGR, { number: vr.number, code: 'ABCDEF123456' });
  check('R14: P2-6 makbuz dogrulama GECERLIYSE numara, tutar, odeme tarihi ve daire etiketini dondurur (sahte belge karsilastirilsin); gecersizde ayrinti YOK',
    verified.status === 200 && verified.body.valid === true && verified.body.amount_minor === 1500 && verified.body.paid_on === TODAY && verified.body.number === vr.number && /P Blok/.test(verified.body.apartment_label ?? '') && wrong.body.valid === false && Object.keys(wrong.body).sort().join() === 'status,valid', [verified.body, wrong.body]);

  // --- P2-8: sakin makbuz uclari no-store
  await addResidency(ps.code, ps.ids[0], await addPerson(ps.code, { user: RESIDENT }), 'owner');
  const myList = await call('GET', '/app/my-finance/receipts', RESIDENT);
  const myOne = await call('GET', `/app/my-finance/receipts/${vr.id}`, RESIDENT);
  check('R15: P2-8 sakin makbuz uclari Cache-Control: no-store dondurur (liste ve ayrinti)', myList.status === 200 && /no-store/.test(myList.headers.get('cache-control') ?? '') && myOne.status === 200 && /no-store/.test(myOne.headers.get('cache-control') ?? ''), [myList.status, myOne.status, myList.headers.get('cache-control')]);

  // --- P2-9: agir onizlemeler AYRI yuvada (rapor yuvasini tuketmez, doluysa 503 REPORT_BUSY)
  const gates = [];
  const holders = [0, 1].map(() => {
    let release;
    gates.push(new Promise((resolve) => { release = resolve; }));
    const running = reports.withReportSnapshot(ps.code, () => gates.at(-1), pool, { slot: 'preview' });
    gates[gates.length - 1].release = release;
    return running;
  });
  await t.sleep(100);
  const lfBusy = await call('POST', `${pb}/late-fee/preview`, MGR, {});
  const remBusy = await call('POST', `${pb}/reminders/preview`, MGR, { tone: 'friendly' });
  const agingOk = await call('GET', `${pb}/reports/aging`, MGR);
  gates.forEach((gate) => gate.release());
  await Promise.all(holders);
  const lfFree = await call('POST', `${pb}/late-fee/preview`, MGR, {});
  check('R16: P2-9 tazminat ve hatirlatma ONIZLEMELERI site basina yuva sinirli (2): doluyken 503 REPORT_BUSY; yonetici raporu etkilenmez (200); yuvalar birakilinca onizleme calisir',
    lfBusy.status === 503 && lfBusy.body.code === 'REPORT_BUSY' && remBusy.status === 503 && agingOk.status === 200 && lfFree.status === 200 && Object.keys(reports.reportConcurrency()).length === 0, [lfBusy.status, remBusy.status, agingOk.status, lfFree.status, reports.reportConcurrency()]);

  // --- P2-10: pasif / silinmis kisinin bekleyen hatirlatma adresi kuyruk dolmadan silinir
  const gone = await mkReminderRun('silinen');
  await q(`UPDATE site_people SET is_active = FALSE WHERE id = $1`, [gone.person]);
  const scrubbed = await queue.failStaleReminderRows();
  const goneRows = (await q(`SELECT email_status, email, email_hash FROM finance_reminder_items WHERE run_id = $1`, [gone.runId])).rows;
  check('R17: P2-10 kisi pasiflesince bekleyen hatirlatma satiri HEMEN resolved olur, duz adres ve ozet silinir (kuyruk dolmayi beklemez)', scrubbed >= 1 && goneRows.every((r) => r.email_status === 'resolved' && r.email === null && r.email_hash === null), { scrubbed, goneRows });

  // --- P2-3: tazminat iptali tekrari (tum kalemler daha once tek tek ters kaydedilmis)
  await call('PUT', '/admin/finance-legal-gate', SUPER, { legal_ok: true });
  const ls = await mkManaged('F4B Inceleme Tazminat', { 'L Blok': 2 });
  const lb = P(ls.code);
  const dayOf = (offset, day) => `${ym(offset)}-${String(day).padStart(2, '0')}`;
  const lset = await call('GET', `${lb}/settings`, MGR);
  await call('PUT', `${lb}/settings`, MGR, { expected_settings_version: lset.body.settings_version, late_fee: { enabled: true, start_period: ym(-3), rate_bp: 500, method: 'daily_30', grace_days: 0 } });
  for (const id of ls.ids) {
    await q(`INSERT INTO ledger_entries (site_code, apartment_id, kind, amount_minor, period, entry_date, due_date, payer_party) VALUES ($1, $2, 'charge', 100000, $3::date, $4::date, $5::date, 'both')`, [ls.code, id, `${ym(-3)}-01`, dayOf(-3, 5), dayOf(-3, 10)]);
  }
  for (const off of [-3, -2, -1]) await call('POST', `${lb}/periods/${ym(off)}/close`, MGR);
  const lpv = await call('POST', `${lb}/late-fee/preview`, MGR, { period: ym(-3) });
  const lpost = await call('POST', `${lb}/late-fee/post`, MGR, { period: ym(-3), expected_total_minor: lpv.body.total_minor, expected_apartment_count: lpv.body.apartment_count, expected_hash: lpv.body.preview_hash, idempotency_key: key('lp') });
  const lines = (await call('GET', `${lb}/late-fee/runs/${lpost.body.run.id}/lines`, MGR)).body.items;
  for (const line of lines) await call('POST', `${lb}/entries/${line.ledger_entry_id}/reverse`, MGR, { reason: 'tek tek', idempotency_key: key('lr') });
  const voidKey = key('lv');
  const void1 = await call('POST', `${lb}/late-fee/runs/${lpost.body.run.id}/void`, MGR, { reason: 'tazminat iptali', idempotency_key: voidKey });
  const void2 = await call('POST', `${lb}/late-fee/runs/${lpost.body.run.id}/void`, MGR, { reason: 'tazminat iptali', idempotency_key: voidKey });
  const void3 = await call('POST', `${lb}/late-fee/runs/${lpost.body.run.id}/void`, MGR, { reason: 'baska neden', idempotency_key: key('lv2') });
  check('R18: P2-3 tazminat iptali TEKRARI: tum kalemler daha once tek tek ters kaydedilmisse de ayni anahtar + ayni neden 200 replay (409 degil); farkli neden 409 LATE_FEE_RUN_NOT_VOIDABLE',
    lpost.status === 201 && lines.length === 2 && void1.status === 201 && void1.body.reversed_count === 0 && void2.status === 200 && void2.body.run.status === 'voided' && void3.status === 409 && void3.body.code === 'LATE_FEE_RUN_NOT_VOIDABLE', [lpost.status, lines.length, void1.status, void1.body, void2.status, void3.status, void3.body]);

  // --- P2-14: bugunun ayi KAPALIYSA mutabakat duzeltmesi PERIOD_CLOSED degil, iptal aynalari gibi sonraki acik aya yazilir
  const cs = await mkManaged('F4B Inceleme Kapali Ay', { 'K Blok': 1 });
  const cb = P(cs.code);
  const cAcc = (await mkAcc(cb, 'Kapali Ay Hesabi', { opening_balance_minor: 50000 })).body.account.id;
  const closedNow = await call('POST', `${cb}/periods/${ym(0)}/close`, MGR);
  const cRec = await call('POST', `${cb}/accounts/${cAcc}/reconciliations`, MGR, { as_of_date: ago(1), statement_balance_minor: 52000, expected_computed_minor: 50000, adjust: { reason_code: 'bank_interest' }, idempotency_key: key('cr') });
  const cMove = (await q(`SELECT to_char(period, 'YYYY-MM-DD') AS period, to_char(movement_date, 'YYYY-MM-DD') AS movement_date FROM account_movements WHERE account_id = $1 AND kind = 'adjustment'`, [cAcc])).rows[0];
  check('R19: P2-14 bugunun ayi kapaliyken mutabakat duzeltmesi 201 (PERIOD_CLOSED degil) ve hareket SONRAKI ACIK aya yazilir (tarih bugun)', closedNow.status === 200 && cRec.status === 201 && cMove && cMove.period === `${ym(1)}-01` && cMove.movement_date === TODAY, [closedNow.status, cRec.status, cRec.body, cMove]);

  // --- R20: hesap listesi ve kurul ozeti last_reconciliation.adjusted
  const ls2 = await mkManaged('F4B Inceleme Adjusted', { 'J Blok': 1 });
  const lb2 = P(ls2.code);
  const jAdj = (await mkAcc(lb2, 'Duzeltilen', { opening_balance_minor: 100000 })).body.account.id;
  const jOpen = (await mkAcc(lb2, 'Duzeltilmeyen', { opening_balance_minor: 50000 })).body.account.id;
  const jNone = (await mkAcc(lb2, 'Mutabakatsiz')).body.account.id;
  const recJ = (id, statement, computed, adjust) => call('POST', `${lb2}/accounts/${id}/reconciliations`, MGR, { as_of_date: ago(1), statement_balance_minor: statement, expected_computed_minor: computed, adjust, idempotency_key: key('ja') });
  const jr1 = await recJ(jAdj, 110000, 100000, { reason_code: 'bank_interest' });
  const jr2 = await recJ(jOpen, 49000, 50000, undefined);
  const jList = (await call('GET', `${lb2}/accounts`, MGR)).body.items;
  const byId = Object.fromEntries(jList.map((a) => [a.id, a.last_reconciliation]));
  const jSummary = await call('GET', `${lb2}/reports/board-summary`, MGR);
  const summaryAccounts = Object.fromEntries((jSummary.body.cash?.accounts ?? []).map((a) => [a.id, a.last_reconciliation]));
  check('R20: hesap listesi last_reconciliation.adjusted: duzeltme hareketiyle kapatilan fark true, duzeltilmeyen false, mutabakatsiz null; fark degerleri ayni; kurul ozeti kasa bolumu de adjusted tasir',
    jr1.status === 201 && jr2.status === 201 && same(byId[jAdj], { as_of_date: ago(1), difference_minor: 10000, adjusted: true }) && same(byId[jOpen], { as_of_date: ago(1), difference_minor: -1000, adjusted: false }) && byId[jNone] === null
      && summaryAccounts[jAdj]?.adjusted === true && summaryAccounts[jOpen]?.adjusted === false && summaryAccounts[jNone] === null, { byId, summaryAccounts, status: jSummary.status });

  void TODAY;
  void monthStart;
}
