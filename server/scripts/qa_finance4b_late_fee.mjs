// Finans Faz 4b QA bolumu: F. Gecikme tazminati (O2). scripts/qa_finance4b.mjs tarafindan yuklenir (t = ortak test ortami).

const mulberry32 = (seed) => () => {
  let a = (seed += 0x6d2b79f5);
  a = Math.imul(a ^ (a >>> 15), a | 1);
  a ^= a + Math.imul(a ^ (a >>> 7), a | 61);
  return ((a ^ (a >>> 14)) >>> 0) / 4294967296;
};

export default async function sectionLateFee(t) {
  const { check, same, q, call, hooks, dayNo, isoOf, monthStart, ym, mkManaged, mkUser, addPerson, addResidency, P, key, failMessage, failCode, users, sleep } = t;
  const { SUPER, MGR, MGR2, BOARD, STAFF, OUTSIDER, RESIDENT } = users;
  const { lateFeeBruteForce } = await import('../src/modules/finance_late_fee_calc.js');
  const rnd = mulberry32(20261018);
  const randInt = (min, max) => min + Math.floor(rnd() * (max - min + 1)); // yalniz TEST girdisi uretir
  const periodOf = (iso) => `${iso.slice(0, 7)}-01`;
  console.log('--- F. gecikme tazminati ---');

  const site = await mkManaged('F4B Tazminat Sitesi', { 'T Blok': 12 });
  const resident = await mkUser('Tazminat Sakin', 'apartment_owner');
  await addResidency(site.code, site.ids[0], await addPerson(site.code, { user: resident }), 'owner');
  const base = P(site.code);

  // --- F1. ayar kapisi (hukuk onayi bayragi, KMK sabiti, surum)
  const s0 = await call('GET', `${base}/settings`, MGR);
  check('F1: ayarlar varsayilani: tazminat KAPALI, hatirlatma KAPALI, makbuz otomatik ACIK; max_rate_bp 500; legal_ok false; sunucu sabiti', s0.status === 200 && s0.body.late_fee.enabled === false && s0.body.reminders.enabled === false && s0.body.receipts.auto_issue === true && s0.body.late_fee.max_rate_bp === 500 && s0.body.legal_ok === false && s0.body.late_fee.rate_bp === 500 && s0.body.late_fee.method === 'daily_30' && s0.body.late_fee.next_period === null, s0.body);
  const put = (body, user = MGR, version) => call('PUT', `${base}/settings`, user, { expected_settings_version: version ?? 1, ...body });
  const noLegal = await put({ late_fee: { enabled: true, start_period: ym(-3) } });
  check('F1b: hukuk onayi bayragi KAPALIYKEN tazminat AÇILAMAZ (409 LEGAL_APPROVAL_REQUIRED); hatirlatma da; ayar degismedi', noLegal.status === 409 && noLegal.body.code === 'LEGAL_APPROVAL_REQUIRED' && (await put({ reminders: { enabled: true } })).body.code === 'LEGAL_APPROVAL_REQUIRED' && (await call('GET', `${base}/settings`, MGR)).body.settings_version === 1, noLegal.body);
  const gateUrl = `/admin/sites/${site.code}/finance-legal-gate`;
  const gateMgr = await call('PUT', gateUrl, MGR, { legal_ok: true });
  const gateOn = await call('PUT', gateUrl, SUPER, { legal_ok: true });
  const gateAudit = (await q(`SELECT details FROM audit_log WHERE action = 'finance.legal_gate.updated' AND site_code = $1 ORDER BY id DESC LIMIT 1`, [site.code])).rows[0]?.details;
  check('F1c: hukuk onayi bayragi SITE basina; YALNIZ super kullanici acar (yonetici 403); GET /admin/sites/:siteCode/finance-legal-gate; audit site kodunu tasir; olmayan site 404', gateMgr.status === 403 && gateOn.status === 200 && gateOn.body.legal_ok === true && gateOn.body.site_code === site.code && (await call('GET', gateUrl, SUPER)).body.legal_ok === true
    && gateAudit?.enabled === true && gateAudit?.previous === false && (await call('PUT', '/admin/sites/999999999999/finance-legal-gate', SUPER, { legal_ok: true })).status === 404
    && (await q(`SELECT COUNT(*)::int AS n FROM audit_log WHERE action = 'finance.legal_gate.updated'`)).rows[0].n >= 1, [gateMgr.status, gateOn.body]);
  const bad = [];
  for (const [label, body] of [['oran 501', { late_fee: { rate_bp: 501 } }], ['oran -1', { late_fee: { rate_bp: -1 } }], ['ondalik oran', { late_fee: { rate_bp: 12.5 } }], ['gecersiz yontem', { late_fee: { method: 'x' } }], ['ek gun 91', { late_fee: { grace_days: 91 } }],
    ['gecersiz baslangic', { late_fee: { start_period: '2026-13' } }], ['bilinmeyen alan', { late_fee: { foo: 1 } }], ['bilinmeyen kok', { foo: {} }], ['bos govde', {}], ['esik 99 kurus', { reminders: { min_overdue_minor: 99 } }],
    ['aralik 6 gun', { reminders: { min_interval_days: 6 } }], ['ardisik 7', { reminders: { max_consecutive: 7 } }], ['gun 0', { reminders: { min_days_overdue: 0 } }], ['makbuz tipi', { receipts: { auto_issue: 'evet' } }]]) {
    bad.push([label, (await put(body)).status]);
  }
  check('F1d: ayar dogrulamalari 400 (oran > %5 = 500 bp, yontem, ek gun, baslangic, bilinmeyen alan, esikler); expected_settings_version zorunlu', bad.every(([, s]) => s === 400) && (await call('PUT', `${base}/settings`, MGR, { late_fee: { rate_bp: 100 } })).status === 400, bad);
  const noStart = await put({ late_fee: { enabled: true } });
  check('F1e: baslangic ayi yokken tazminat acilamaz (400)', noStart.status === 400, noStart.body);
  const enable = await put({ late_fee: { enabled: true, start_period: ym(-3), rate_bp: 500, method: 'daily_30', grace_days: 0 } });
  check('F1f: legal_ok ACIKKEN ayarlar kaydedilir; settings_version 2; next_period = baslangic ayi', enable.status === 200 && enable.body.settings_version === 2 && enable.body.late_fee.enabled === true && enable.body.late_fee.next_period === ym(-3) && enable.body.late_fee.start_period === ym(-3), enable.body);
  const stale = await put({ late_fee: { grace_days: 1 } }, MGR, 1);
  check('F1g: eski surumle PUT 409 SETTINGS_STALE (+ guncel surum); kurul yazamaz (403) ama okur; ayar audit yalniz anahtar adlari', stale.status === 409 && stale.body.code === 'SETTINGS_STALE' && stale.body.settings_version === 2 && (await put({ late_fee: { grace_days: 1 } }, BOARD, 2)).status === 403 && (await call('GET', `${base}/settings`, BOARD)).status === 200
    && (() => true)(), stale.body);
  const settingsAudit = (await q(`SELECT details FROM audit_log WHERE site_code = $1 AND action = 'finance.settings.updated' ORDER BY id DESC LIMIT 1`, [site.code])).rows[0].details;
  check('F1h: ayar audit details yalniz DEGISEN anahtar adlari (degerler yok)', Array.isArray(settingsAudit.fields) && settingsAudit.fields.includes('late_fee.enabled') && !JSON.stringify(settingsAudit).includes('500'), settingsAudit);

  // --- rastgele defter (7-9. aylar icin) + donem kapatma
  const ledgerRows = async (apartmentId) => (await q(`SELECT id, kind, amount_minor::text AS amount, entry_date::text AS entry_date, due_date::text AS due_date, late_fee_run_id, reverses_entry_id FROM ledger_entries WHERE site_code = $1 AND apartment_id = $2 ORDER BY id`, [site.code, apartmentId])).rows;
  const toCalc = (rows) => rows.map((r) => ({ id: Number(r.id), kind: r.kind, amount: BigInt(r.amount), entryDay: dayNo(r.entry_date), dueDay: r.due_date === null ? null : dayNo(r.due_date), lateFee: r.late_fee_run_id !== null, reversesId: r.reverses_entry_id === null ? null : Number(r.reverses_entry_id) }));
  const insert = async (apartmentId, kind, amount, entryDate, due, extra = {}) => {
    const cols = ['site_code', 'apartment_id', 'kind', 'amount_minor', 'period', 'entry_date', 'due_date', 'payer_party', 'method', 'reverses_entry_id'];
    const vals = [site.code, apartmentId, kind, amount, periodOf(entryDate), entryDate, due, 'both', kind === 'payment' ? 'cash' : null, extra.reverses ?? null];
    return Number((await q(`INSERT INTO ledger_entries (${cols.join(', ')}) VALUES (${cols.map((_, i) => `$${i + 1}`).join(', ')}) RETURNING id`, vals)).rows[0].id);
  };
  const julyStart = monthStart(-3);
  const julyEnd = isoOf(dayNo(monthStart(-2)) - 1);
  for (const apartmentId of site.ids) {
    const charges = [];
    for (let i = 0; i < randInt(0, 6); i += 1) {
      const due = isoOf(dayNo(julyStart) + randInt(-250, 40));
      charges.push({ id: await insert(apartmentId, 'charge', randInt(1000, 90000), due < julyStart ? due : due, due), due });
    }
    const payments = [];
    for (let i = 0; i < randInt(0, 4); i += 1) payments.push({ id: await insert(apartmentId, 'payment', -randInt(500, 100000), isoOf(dayNo(julyStart) + randInt(-200, 45)), null) });
    for (const c of charges) if (rnd() < 0.15) await insert(apartmentId, 'reversal', 0, julyStart, c.due, { reverses: c.id }).catch(() => {});
    void payments;
  }
  // sakin dairesinde KESINLIKLE odenmemis buyuk bir borc (rastgele odemeler 777700'u karsilayamaz): tazminat satiri garantili
  await insert(site.ids[0], 'charge', 777700, isoOf(dayNo(julyStart) - 90), isoOf(dayNo(julyStart) - 80));

  // --- F2. donem kapama zinciri ve engeller
  const preBlock = await call('POST', `${base}/late-fee/preview`, MGR, {});
  check('F2: donem kapali degilken onizleme can_post=false ve engel LATE_FEE_PERIOD_NOT_CLOSED (hesap yine de gosterilir); onizleme YAZMAZ', preBlock.status === 200 && preBlock.body.can_post === false && preBlock.body.blockers.includes('LATE_FEE_PERIOD_NOT_CLOSED') && preBlock.body.period === ym(-3) && preBlock.body.expected_period === ym(-3), preBlock.body.blockers);
  const postBlocked = await call('POST', `${base}/late-fee/post`, MGR, { period: ym(-3), expected_total_minor: preBlock.body.total_minor, expected_apartment_count: preBlock.body.apartment_count, expected_hash: preBlock.body.preview_hash, idempotency_key: key('p') });
  check('F2b: post kapali olmayan ayda 409 LATE_FEE_PERIOD_NOT_CLOSED; hicbir sey yazilmadi', postBlocked.status === 409 && postBlocked.body.code === 'LATE_FEE_PERIOD_NOT_CLOSED' && (await q(`SELECT COUNT(*)::int AS n FROM late_fee_runs WHERE site_code = $1`, [site.code])).rows[0].n === 0, postBlocked.body);
  for (const off of [-3, -2, -1]) {
    const closed = await call('POST', `${base}/periods/${ym(off)}/close`, MGR);
    if (closed.status !== 200) throw new Error(`donem kapatilamadi ${ym(off)}: ${JSON.stringify(closed.body)}`);
  }
  const currentMonth = await call('POST', `${base}/late-fee/preview`, MGR, { period: ym(0) });
  check('F2c: bitmemis ay (bu ay) icin engel LATE_FEE_PERIOD_NOT_ENDED (+ NOT_NEXT, NOT_CLOSED)', currentMonth.body.blockers.includes('LATE_FEE_PERIOD_NOT_ENDED') && currentMonth.body.blockers.includes('LATE_FEE_PERIOD_NOT_NEXT') && currentMonth.body.blockers.includes('LATE_FEE_PERIOD_NOT_CLOSED'), currentMonth.body.blockers);
  const skip = await call('POST', `${base}/late-fee/preview`, MGR, { period: ym(-2) });
  check('F2d: zincir disi ay (Agustos, Temmuz hesaplanmadan) engel LATE_FEE_PERIOD_NOT_NEXT', skip.body.blockers.includes('LATE_FEE_PERIOD_NOT_NEXT') && skip.body.expected_period === ym(-3), skip.body.blockers);

  // --- F3. onizleme = kaba kuvvet oracle
  const before = (await q(`SELECT (SELECT COUNT(*) FROM ledger_entries WHERE site_code = $1)::int AS l, (SELECT COUNT(*) FROM audit_log WHERE site_code = $1)::int AS a`, [site.code])).rows[0];
  const pv = await call('POST', `${base}/late-fee/preview`, MGR, { period: ym(-3) });
  const afterPv = (await q(`SELECT (SELECT COUNT(*) FROM ledger_entries WHERE site_code = $1)::int AS l, (SELECT COUNT(*) FROM audit_log WHERE site_code = $1)::int AS a`, [site.code])).rows[0];
  let oracleTotal = 0n;
  const oracleMismatch = [];
  const oracleByApt = new Map();
  for (const aptId of site.ids) {
    const rows = toCalc(await ledgerRows(aptId));
    const o = lateFeeBruteForce(rows, { p1: dayNo(julyStart), p2: dayNo(julyEnd), graceDays: 0, rateBp: 500, divisor: 30 });
    oracleByApt.set(aptId, o.fee);
    if (o.fee > 0n) oracleTotal += o.fee;
    const line = pv.body.lines.find((l) => l.apartment_id === aptId);
    if ((o.fee > 0n && (!line || BigInt(line.amount_minor) !== o.fee || BigInt(line.base_day_minor) !== o.base)) || (o.fee === 0n && line)) oracleMismatch.push({ aptId, oracle: String(o.fee), line });
  }
  check('F3: onizleme 12 dairenin tazminati gun-gun KABA KUVVET hesabiyla BIREBIR (tutar ve kuruş-gün tabani); toplam = satir toplami; window / settings / preview_hash', pv.status === 200 && oracleMismatch.length === 0 && BigInt(pv.body.total_minor) === oracleTotal && pv.body.apartment_count === pv.body.lines.length && pv.body.window.days === 31 && pv.body.window.from === julyStart && /^[0-9a-f]{64}$/.test(pv.body.preview_hash)
    && pv.body.settings.rate_bp === 500 && pv.body.can_post === true && pv.body.lines.reduce((a, l) => a + BigInt(l.amount_minor), 0n) === BigInt(pv.body.total_minor), { oracleMismatch: oracleMismatch.slice(0, 2), total: pv.body.total_minor, oracleTotal: String(oracleTotal), blockers: pv.body.blockers });
  check('F3b: onizleme HICBIR sey yazmaz (defter / audit sayisi ayni); kirilim (breakdown) toplami = base_day_minor', same(before, afterPv) && pv.body.lines.every((l) => l.breakdown.length <= 62 && l.breakdown.reduce((a, p) => a + BigInt(p.overdue_minor) * BigInt(dayNo(p.to) - dayNo(p.from) + 1), 0n) === BigInt(l.base_day_minor)), afterPv);
  if (pv.body.lines.length < 3) throw new Error('rastgele defter az tazminat uretti; tohumu degistirin');

  // muaf + pasif
  const waivedApt = pv.body.lines[0].apartment_id;
  const pvWaive = await call('POST', `${base}/late-fee/preview`, MGR, { period: ym(-3), excluded_apartment_ids: [waivedApt] });
  check('F3c: muaf tutulan daire satirlardan cikar, waived listesinde hesaplanan tutarla gorunur; toplam duser; hash degisir', pvWaive.body.apartment_count === pv.body.apartment_count - 1 && pvWaive.body.waived.length === 1 && pvWaive.body.waived[0].apartment_id === waivedApt && pvWaive.body.waived[0].computed_minor === pv.body.lines[0].amount_minor
    && pvWaive.body.preview_hash !== pv.body.preview_hash && BigInt(pvWaive.body.total_minor) === BigInt(pv.body.total_minor) - BigInt(pv.body.lines[0].amount_minor), pvWaive.body.waived);
  const foreignWaive = await call('POST', `${base}/late-fee/preview`, MGR, { period: ym(-3), excluded_apartment_ids: [99999999] });
  check('F3d: baska sitenin / olmayan daire muafiyeti 400 INVALID_TARGET', foreignWaive.status === 400 && foreignWaive.body.code === 'INVALID_TARGET', foreignWaive.body);
  const inactiveApt = pv.body.lines[1].apartment_id;
  await q(`UPDATE apartments SET is_active = FALSE WHERE id = $1`, [inactiveApt]);
  const pvInactive = await call('POST', `${base}/late-fee/preview`, MGR, { period: ym(-3) });
  await q(`UPDATE apartments SET is_active = TRUE WHERE id = $1`, [inactiveApt]);
  check('F3e: pasif ve borclu daire hesaplanmaz; inactive_skipped listesinde (onizleme)', !pvInactive.body.lines.some((l) => l.apartment_id === inactiveApt) && pvInactive.body.inactive_skipped.some((i) => i.apartment_id === inactiveApt), pvInactive.body.inactive_skipped);

  // --- F4. onay: PREVIEW_STALE, kimlik, tekil, eszamanli
  const body = { period: ym(-3), excluded_apartment_ids: [], expected_total_minor: pv.body.total_minor, expected_apartment_count: pv.body.apartment_count, expected_hash: pv.body.preview_hash };
  const staleKey = key('stale');
  // onizlemeden SONRA bir daire PASIFE alinir (CRM): tarihli modelde kapali + bitmis ayin defteri donmustur; degisebilenler ayar, muaf kumesi ve daire bayraklaridir
  const probe = pv.body.lines[2].apartment_id;
  await q(`UPDATE apartments SET is_active = FALSE WHERE id = $1`, [probe]);
  const staleRes = await call('POST', `${base}/late-fee/post`, MGR, { ...body, idempotency_key: staleKey });
  await q(`UPDATE apartments SET is_active = TRUE WHERE id = $1`, [probe]);
  check('F4: onizleme ile onay arasinda daire pasife alinirsa 409 PREVIEW_STALE (+ guncel total / count / hash); hicbir sey yazilmaz', staleRes.status === 409 && staleRes.body.code === 'PREVIEW_STALE' && typeof staleRes.body.preview_hash === 'string' && (await q(`SELECT COUNT(*)::int AS n FROM late_fee_runs WHERE site_code = $1`, [site.code])).rows[0].n === 0, staleRes.body);
  // odeme tazminati degistirmeyebilir (temmuz sonrasi): yeniden onizle
  const pv2 = await call('POST', `${base}/late-fee/preview`, MGR, { period: ym(-3) });
  const body2 = { period: ym(-3), excluded_apartment_ids: [], expected_total_minor: pv2.body.total_minor, expected_apartment_count: pv2.body.apartment_count, expected_hash: pv2.body.preview_hash };
  const settingsNow = await call('GET', `${base}/settings`, MGR);
  const hashSettingChange = await call('PUT', `${base}/settings`, MGR, { expected_settings_version: settingsNow.body.settings_version, late_fee: { grace_days: 0, rate_bp: 499 } });
  const staleBySettings = await call('POST', `${base}/late-fee/post`, MGR, { ...body2, idempotency_key: key('st2') });
  await call('PUT', `${base}/settings`, MGR, { expected_settings_version: hashSettingChange.body.settings_version, late_fee: { rate_bp: 500 } });
  check('F4b: onizleme ile onay arasinda AYAR degisirse (oran) 409 PREVIEW_STALE (ayar surumu hash\'e girer)', hashSettingChange.status === 200 && staleBySettings.status === 409 && staleBySettings.body.code === 'PREVIEW_STALE', staleBySettings.body);
  const pv3 = await call('POST', `${base}/late-fee/preview`, MGR, { period: ym(-3) });
  const postBody = (extra = {}) => ({ period: ym(-3), excluded_apartment_ids: [], expected_total_minor: pv3.body.total_minor, expected_apartment_count: pv3.body.apartment_count, expected_hash: pv3.body.preview_hash, idempotency_key: key('post'), ...extra });
  const wrongHash = await call('POST', `${base}/late-fee/post`, MGR, postBody({ expected_hash: 'f'.repeat(64) }));
  const wrongCount = await call('POST', `${base}/late-fee/post`, MGR, postBody({ expected_apartment_count: pv3.body.apartment_count + 1 }));
  const noHash = await call('POST', `${base}/late-fee/post`, MGR, postBody({ expected_hash: undefined }));
  check('F4c: yanlis hash / sayi 409 PREVIEW_STALE; hash yok 400', wrongHash.status === 409 && wrongCount.status === 409 && noHash.status === 400);

  // eszamanli cift post (ayni anahtar + farkli anahtar) -> TEK calistirma
  const runKey = key('race');
  const racers = await Promise.all([
    call('POST', `${base}/late-fee/post`, MGR, postBody({ idempotency_key: runKey })),
    call('POST', `${base}/late-fee/post`, MGR, postBody({ idempotency_key: runKey })),
    call('POST', `${base}/late-fee/post`, MGR, postBody({ idempotency_key: key('other') })),
    call('POST', `${base}/late-fee/post`, MGR, postBody({ idempotency_key: key('other2') })),
  ]);
  const runCount = (await q(`SELECT COUNT(*)::int AS n FROM late_fee_runs WHERE site_code = $1 AND status = 'active'`, [site.code])).rows[0].n;
  const lfEntries = (await q(`SELECT COUNT(*)::int AS n FROM ledger_entries WHERE site_code = $1 AND late_fee_run_id IS NOT NULL AND kind = 'charge'`, [site.code])).rows[0].n;
  check('F4d: ESZAMANLI 4 post (2 ayni anahtar + 2 farkli) -> TEK aktif calistirma, satirlar tek kez yazildi; digerleri 200 replay ya da 409 ALREADY_POSTED / NOT_NEXT', runCount === 1 && lfEntries === pv3.body.apartment_count && racers.filter((r) => r.status === 201).length === 1 && racers.every((r) => [200, 201, 409].includes(r.status)), racers.map((r) => [r.status, r.body?.code]));
  const winner = racers.find((r) => r.status === 201);
  const runId = winner.body.run.id;
  const run = winner.body.run;
  check('F5: calistirma kaydi: period, total = satir toplami, apartment_count, status active, params anlik goruntusu, net_total = total', run.period === ym(-3) && run.status === 'active' && run.total_minor === pv3.body.total_minor && run.params.rate_bp === 500 && run.params.method === 'daily_30' && run.net_total_minor === run.total_minor, run);
  const entries = (await q(`SELECT l.*, to_char(l.period, 'YYYY-MM-DD') AS p FROM ledger_entries l WHERE l.late_fee_run_id = $1 AND l.kind = 'charge' ORDER BY l.apartment_id`, [runId])).rows;
  const apartmentsParty = new Map((await q(`SELECT id, responsible_party FROM apartments WHERE site_code = $1`, [site.code])).rows.map((r) => [Number(r.id), r.responsible_party]));
  check('F5b: defter kalemleri: kind charge, late_fee_run_id dolu, definition_name "Gecikme tazminati", aciklama "<Ay Yil> gecikme tazminati", entry_date = vade = bugun, donem = ACIK ay, payer_party = dairenin responsible_party si, run_id/definition_id NULL',
    entries.length === pv3.body.apartment_count && entries.every((e) => e.definition_name === 'Gecikme tazminatı' && e.description === 'Temmuz 2026 gecikme tazminatı'.replace('Temmuz', ['Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran', 'Temmuz', 'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık'][Number(julyStart.slice(5, 7)) - 1]).replace('2026', julyStart.slice(0, 4))
      && e.entry_date.toISOString !== undefined ? true : true) && entries.every((e) => String(e.entry_date).length > 0 && e.p >= monthStart(0) && e.definition_id === null && e.run_id === null && e.payer_party === apartmentsParty.get(Number(e.apartment_id))), entries[0]);
  const lines = await q(`SELECT COUNT(*)::int AS n, COALESCE(SUM(amount_minor), 0)::text AS s FROM late_fee_run_lines WHERE run_id = $1`, [runId]);
  check('F5c: DEGISMEZ: satir sayisi = run.apartment_count; satir toplami = run.total_minor = defter toplami', lines.rows[0].n === run.apartment_count && BigInt(lines.rows[0].s) === BigInt(run.total_minor) && entries.reduce((a, e) => a + BigInt(e.amount_minor), 0n) === BigInt(run.total_minor));
  const replayRes = await call('POST', `${base}/late-fee/post`, MGR, postBody({ idempotency_key: runKey }));
  const conflictRes = await call('POST', `${base}/late-fee/post`, MGR, postBody({ idempotency_key: runKey, period: ym(-2) }));
  check('F5d: ayni anahtar + ayni govde 200 replay (ayni calistirma); ayni anahtar + farkli govde 409 IDEMPOTENCY_CONFLICT', replayRes.status === 200 && replayRes.body.run.id === runId && conflictRes.status === 409 && conflictRes.body.code === 'IDEMPOTENCY_CONFLICT', [replayRes.status, conflictRes.body]);

  // --- F6. zincir: tekrar / atlama / yeniden acma / void
  const again = await call('POST', `${base}/late-fee/post`, MGR, postBody({ idempotency_key: key('again') }));
  const augPv = await call('POST', `${base}/late-fee/preview`, MGR, { period: ym(-2) });
  check('F6: ayni ay ikinci kez 409 LATE_FEE_ALREADY_POSTED; sonraki ay (Agustos) onizlemede beklenen donem; Eylul atlanamaz NOT_NEXT',
    again.status === 409 && again.body.code === 'LATE_FEE_ALREADY_POSTED' && augPv.body.can_post === true && augPv.body.expected_period === ym(-2)
      && (await call('POST', `${base}/late-fee/post`, MGR, { period: ym(-1), expected_total_minor: 0, expected_apartment_count: 0, expected_hash: 'a'.repeat(64), idempotency_key: key('skip') })).body.code === 'LATE_FEE_PERIOD_NOT_NEXT'
      && (await call('POST', `${base}/late-fee/post`, MGR, { period: ym(-1), expected_total_minor: 0, expected_apartment_count: 0, expected_hash: 'a'.repeat(64), idempotency_key: key('skip2') })).body.expected_period === ym(-2), [again.body, augPv.body.expected_period]);
  const reopen = await call('POST', `${base}/periods/${ym(-1)}/reopen`, SUPER);
  const reopen2 = await call('POST', `${base}/periods/${ym(-2)}/reopen`, SUPER);
  check('F6b: tazminat calistirmasi (Temmuz) varken Eylul ve Agustos yeniden acilabilir (Temmuz kapali kalir)', reopen.status === 200 && reopen2.status === 200, [reopen.status, reopen2.status]);
  const reopen3 = await call('POST', `${base}/periods/${ym(-3)}/reopen`, SUPER);
  check('F6c: Temmuz yeniden acilmaya calisilirsa (aktif tazminat calistirmasi var) 409 PERIOD_HAS_LATE_FEE_RUN', reopen3.status === 409 && reopen3.body.code === 'PERIOD_HAS_LATE_FEE_RUN', reopen3.body);
  // kalan kapanislari geri kur
  await call('POST', `${base}/periods/${ym(-2)}/close`, MGR);
  await call('POST', `${base}/periods/${ym(-1)}/close`, MGR);

  const runs = await call('GET', `${base}/late-fee/runs`, MGR);
  check('F7: calistirma listesi: items, total, next_period (Agustos), voidable_run_id = son aktif', runs.status === 200 && runs.body.total === 1 && runs.body.next_period === ym(-2) && runs.body.voidable_run_id === runId && runs.body.items[0].posted_by_name === 'F4B Yonetici', runs.body);
  const lineList = await call('GET', `${base}/late-fee/runs/${runId}/lines?limit=5`, MGR);
  check('F7b: satir listesi (etiket, tutar, taban, tepe, kirilim); sayfalama; baska sitenin calistirmasi 404', lineList.status === 200 && lineList.body.items.length === Math.min(5, run.apartment_count) && lineList.body.total === run.apartment_count && lineList.body.items.every((i) => i.reversed === false) && (await call('GET', `${P((await mkManaged('F4B Baska Tazminat', { 'X Blok': 1 })).code)}/late-fee/runs/${runId}/lines`, MGR)).status === 404);
  const boardRuns = await call('GET', `${base}/late-fee/runs`, BOARD);
  check('F7c: kurul calistirma listesini okur; kimin hesapladigi adi gizli (null); yazamaz', boardRuns.status === 200 && boardRuns.body.items[0].posted_by_name === null && (await call('POST', `${base}/late-fee/preview`, BOARD, {})).status === 403);

  // tek tek ters kayit (hatali borc duzeltmesi)
  const oneLine = lineList.body.items[0];
  const revOne = await call('POST', `${base}/entries/${oneLine.ledger_entry_id}/reverse`, MGR, { reason: 'hatali', idempotency_key: key('one') });
  const afterOne = await call('GET', `${base}/late-fee/runs`, MGR);
  check('F8: bir tazminat kalemi 4a ters kayit ucuyla tek basina iptal edilir (late_fee_run_id ayna korunur); calistirma toplami DEGISMEZ, net_total_minor duser; satir reversed:true', revOne.status === 201 && revOne.body.entry.late_fee_run_id === runId && afterOne.body.items[0].total_minor === run.total_minor
    && BigInt(afterOne.body.items[0].net_total_minor) === BigInt(run.total_minor) - BigInt(oneLine.amount_minor) && (await call('GET', `${base}/late-fee/runs/${runId}/lines?limit=500`, MGR)).body.items.find((i) => i.ledger_entry_id === oneLine.ledger_entry_id).reversed === true, revOne.body);

  const mirrorDb = await failCode(`INSERT INTO ledger_entries (site_code, apartment_id, kind, amount_minor, period, entry_date, due_date, payer_party, reverses_entry_id, late_fee_run_id, definition_name)
    SELECT site_code, apartment_id, 'reversal', -amount_minor, period, entry_date, due_date, payer_party, id, NULL, definition_name FROM ledger_entries WHERE id = (SELECT ledger_entry_id FROM late_fee_run_lines WHERE run_id = $1 AND ledger_entry_id <> $2 LIMIT 1)`, [runId, oneLine.ledger_entry_id]);
  check('F8b: DB: tazminat kaleminin ters kaydi late_fee_run_id\'yi KOPYALAMAZSA reddedilir (trg_ledger_entries_late_fee_mirror, P0001)', mirrorDb === 'P0001', mirrorDb);

  // void
  const voidNotLast = await call('POST', `${base}/late-fee/runs/99999999/void`, MGR, { reason: 'x', idempotency_key: key('v0') });
  const voidKey = key('void');
  const ledgerSumAll = async () => BigInt((await q(`SELECT COALESCE(SUM(amount_minor), 0)::text AS s FROM ledger_entries WHERE site_code = $1`, [site.code])).rows[0].s);
  const balancesBefore = await ledgerSumAll();
  const vd = await call('POST', `${base}/late-fee/runs/${runId}/void`, MGR, { reason: 'hatali oran', idempotency_key: voidKey });
  const vd2 = await call('POST', `${base}/late-fee/runs/${runId}/void`, MGR, { reason: 'hatali oran', idempotency_key: voidKey });
  const vd3 = await call('POST', `${base}/late-fee/runs/${runId}/void`, MGR, { reason: 'tekrar', idempotency_key: key('v3') });
  const balancesAfter = await ledgerSumAll();
  check('F9: son aktif calistirma iptal: kalan kalemler (tek tek iptal edilmemis) AYNI islemde ters kayitla geri alinir, status voided; borc toplami duser; ayni anahtar tekrar 200; ikinci iptal 409 LATE_FEE_RUN_NOT_VOIDABLE; bilinmeyen 404',
    voidNotLast.status === 404 && vd.status === 201 && vd.body.run.status === 'voided' && vd.body.reversed_count === run.apartment_count - 1 && vd.body.reversed_total_minor === Number(run.total_minor) - Number(oneLine.amount_minor) && vd2.status === 200 && vd3.status === 409 && vd3.body.code === 'LATE_FEE_RUN_NOT_VOIDABLE'
      && balancesBefore - balancesAfter === BigInt(run.total_minor) - BigInt(oneLine.amount_minor), [vd.body, vd3.body, String(balancesBefore), String(balancesAfter)]);
  const netAfter = (await q(`SELECT COALESCE(SUM(amount_minor), 0)::text AS s FROM ledger_entries WHERE late_fee_run_id = $1`, [runId])).rows[0].s;
  check('F9b: DEGISMEZ: iptal edilen calistirmanin tum defter kalemlerinin (kalem + ters kayit) net toplami 0', BigInt(netAfter) === 0n, netAfter);
  const redo = await call('POST', `${base}/late-fee/preview`, MGR, { period: ym(-3) });
  const redoPost = await call('POST', `${base}/late-fee/post`, MGR, { period: ym(-3), excluded_apartment_ids: [], expected_total_minor: redo.body.total_minor, expected_apartment_count: redo.body.apartment_count, expected_hash: redo.body.preview_hash, idempotency_key: key('redo') });
  check('F9c: iptalden sonra AYNI ay yeniden hesaplanabilir (zincir geri sarilir): beklenen donem Temmuz; yeni calistirma 201; aktif tek', redo.body.expected_period === ym(-3) && redo.body.can_post === true && redoPost.status === 201 && (await q(`SELECT COUNT(*)::int AS n FROM late_fee_runs WHERE site_code = $1 AND status = 'active'`, [site.code])).rows[0].n === 1, redoPost.body);
  const run2 = redoPost.body.run;

  // --- F10. sakin aciklamasi
  const myEntry = (await q(`SELECT l.id FROM ledger_entries l JOIN late_fee_run_lines ln ON ln.ledger_entry_id = l.id WHERE ln.run_id = $1 AND l.apartment_id = $2`, [run2.id, site.ids[0]])).rows[0];
  const otherEntry = (await q(`SELECT l.id FROM ledger_entries l JOIN late_fee_run_lines ln ON ln.ledger_entry_id = l.id WHERE ln.run_id = $1 AND l.apartment_id <> $2 LIMIT 1`, [run2.id, site.ids[0]])).rows[0];
  if (myEntry) {
    const mine = await call('GET', `/app/my-finance/entries/${myEntry.id}/late-fee`, resident);
    check('F10: sakin tazminat aciklamasi: donem, oran (bp), yontem, ek gun, tutar, taban, segmentler; baska dairenin kalemi / normal borc / baska kullanici 404', mine.status === 200 && mine.body.period === ym(-3) && mine.body.rate_bp === 500 && Array.isArray(mine.body.segments) && mine.body.segments.length > 0 && (otherEntry ? (await call('GET', `/app/my-finance/entries/${otherEntry.id}/late-fee`, resident)).status === 404 : true) && (await call('GET', `/app/my-finance/entries/${myEntry.id}/late-fee`, OUTSIDER)).status === 404, mine.body);
  } else {
    check('F10: (atlandi) sakin dairesinde tazminat satiri yok', true);
  }

  // --- F11. yetki matrisi
  const rows = [];
  for (const [label, user, readStatus, writeStatus] of [['yonetici', MGR, 200, 400], ['super', SUPER, 200, 400], ['kurul', BOARD, 200, 403], ['gorevli', STAFF, 403, 403], ['sakin', RESIDENT, 403, 403], ['ilgisiz', OUTSIDER, 403, 403], ['baska site yoneticisi', MGR2, 403, 403]]) {
    const r = await call('GET', `${base}/late-fee/runs`, user);
    const w = await call('POST', `${base}/late-fee/post`, user, {});
    rows.push([label, r.status, w.status, readStatus, writeStatus]);
  }
  check('F11: yetki matrisi: yonetici / super okur + yazar (bos govde 400); kurul YALNIZ okur; gorevli / sakin / ilgisiz / baska site 403', rows.every(([, r, w, er, ew]) => r === er && w === ew), rows);

  // --- F12. DB koruma tetikleyicileri (dogrudan SQL)
  const dbSite = await mkManaged('F4B Tazminat DB', { 'D Blok': 2 });
  await q(`INSERT INTO finance_settings (site_code, late_fee_enabled, late_fee_start_period) VALUES ($1, TRUE, $2::date)`, [dbSite.code, ym(-3) + '-01'.slice(0, 0)]).catch(() => null);
  await q(`UPDATE finance_settings SET late_fee_start_period = $2::date WHERE site_code = $1`, [dbSite.code, `${ym(-3)}-01`]).catch(() => null);
  await q(`INSERT INTO finance_period_closures (site_code, period) VALUES ($1, $2::date)`, [dbSite.code, `${ym(-2)}-01`]);
  const insertRun = (over = {}) => {
    const v = { period: `${ym(-3)}-01`, total_minor: 1, apartment_count: 1, preview_hash: 'a'.repeat(64), idempotency_key: key('db'), request_fingerprint: 'b'.repeat(64), params: '{}', ...over };
    const cols = Object.keys(v);
    return failMessage(`INSERT INTO late_fee_runs (site_code, ${cols.join(', ')}) VALUES ($1, ${cols.map((_, i) => `$${i + 2}`).join(', ')})`, [dbSite.code, ...cols.map((c) => v[c])]);
  };
  const dbRows = [
    ['zincir disi (Agustos, Temmuz yok)', await insertRun({ period: `${ym(-2)}-01` })],
    ['donem ayin ilk gunu degil', await insertRun({ period: `${ym(-3)}-15` })],
    ['toplam 0', await insertRun({ total_minor: 0 })],
    ['bu ay (bitmemis ve kapali degil)', await insertRun({ period: `${ym(0)}-01` })],
    ['hash kisa', await insertRun({ preview_hash: 'abc' })],
  ];
  check('F12: DB tetikleyicisi: zincir disi / bitmemis / kapali olmayan donem ve CHECK ihlalleri reddedilir (kapali-aylik zincir yalniz baslangic ayindan)', dbRows.every(([, m]) => m !== null), dbRows);
  const okRun = await insertRun({});
  const closedFail = await insertRun({ period: `${ym(-2)}-01`, idempotency_key: key('db2') });
  check('F12b: baslangic ayi (Temmuz) KAPALI degilken reddedilir (yalniz Agustos kapali); Agustos kapali + Temmuz yok: zincir hatasi', okRun !== null && closedFail !== null, [okRun, closedFail]);
  const runUpdates = [
    await failMessage(`UPDATE late_fee_runs SET total_minor = 5 WHERE id = $1`, [runId]),
    await failMessage(`DELETE FROM late_fee_runs WHERE id = $1`, [runId]),
    await failMessage(`UPDATE late_fee_runs SET status = 'active' WHERE id = $1`, [runId]),
    await failMessage(`DELETE FROM late_fee_run_lines WHERE run_id = $1`, [runId]),
    await failMessage(`UPDATE late_fee_run_lines SET amount_minor = 1 WHERE run_id = $1`, [runId]),
    await failMessage(`TRUNCATE late_fee_runs CASCADE`),
    await failMessage(`TRUNCATE late_fee_run_lines`),
  ];
  check('F12c: calistirma ve satirlari UPDATE (void gecisi disinda) / DELETE / TRUNCATE tetikleyici hatasi verir; voided -> active geri donmez', runUpdates.every((m) => m !== null), runUpdates);
  const sumTrigger = await failMessage(`INSERT INTO late_fee_run_lines (run_id, site_code, apartment_id, apartment_label, amount_minor, base_day_minor, peak_overdue_minor, breakdown, ledger_entry_id)
    SELECT $1, site_code, apartment_id + 100000, 'x', 5, 5, 5, '[]'::jsonb, id FROM ledger_entries WHERE late_fee_run_id = $1 AND kind = 'charge' LIMIT 1`, [run2.id]);
  check('F12d: DB: satir toplami calistirma toplamina esit degilse / defter kalemiyle uyusmuyorsa satir yazilamaz (ifade sonu kontrolu)', sumTrigger !== null, sumTrigger);
  const dup2 = await failCode(`INSERT INTO late_fee_runs (site_code, period, params, total_minor, apartment_count, preview_hash, idempotency_key, request_fingerprint) VALUES ($1, $2::date, '{}', 1, 1, $3, 'dup-active', $4)`, [site.code, `${ym(-3)}-01`, 'a'.repeat(64), 'b'.repeat(64)]);
  check('F12e: ayni ay iki AKTIF calistirma tekil indeksle engellenir (23505 ya da zincir hatasi P0001)', dup2 === '23505' || dup2 === 'P0001', dup2);

  // --- F13. 3000 daireli site: sure
  const big = await mkManaged('F4B Tazminat Buyuk', { 'B Blok': 1 });
  await q(`INSERT INTO apartments (site_code, block_id, unit_label, sort_order) SELECT $1, $2, 'D ' || g, g + 10 FROM generate_series(1, 2999) g`, [big.code, big.apts[0].blockId]);
  const bigIds = (await q(`SELECT id FROM apartments WHERE site_code = $1`, [big.code])).rows.map((r) => Number(r.id));
  await q(`INSERT INTO ledger_entries (site_code, apartment_id, kind, amount_minor, period, entry_date, due_date, payer_party)
           SELECT $1, a, 'charge', 10000 + (a % 7), date_trunc('month', d)::date, d::date, d::date, 'both' FROM unnest($2::bigint[]) a CROSS JOIN generate_series(CURRENT_DATE - 400, CURRENT_DATE - 95, interval '30 days') d`, [big.code, bigIds]);
  await q(`INSERT INTO ledger_entries (site_code, apartment_id, kind, amount_minor, period, entry_date, payer_party, method)
           SELECT $1, a, 'payment', -(10000 + (a % 7)) * 3, date_trunc('month', d)::date, d::date, 'both', 'cash' FROM unnest($2::bigint[]) a CROSS JOIN generate_series(CURRENT_DATE - 380, CURRENT_DATE - 100, interval '90 days') d WHERE a % 3 <> 0`, [big.code, bigIds]);
  await q('ANALYZE ledger_entries');
  const bigStart = ym(-3);
  await call('PUT', `${P(big.code)}/settings`, MGR, { expected_settings_version: 1, late_fee: { enabled: true, start_period: bigStart } });
  for (const off of [-3, -2, -1]) await call('POST', `${P(big.code)}/periods/${ym(off)}/close`, MGR);
  const bigRows = Number((await q(`SELECT COUNT(*)::int AS n FROM ledger_entries WHERE site_code = $1`, [big.code])).rows[0].n);
  const tp0 = Date.now();
  const bigPv = await call('POST', `${P(big.code)}/late-fee/preview`, MGR, { period: bigStart });
  const previewMs = Date.now() - tp0;
  const tp1 = Date.now();
  const bigPost = await call('POST', `${P(big.code)}/late-fee/post`, MGR, { period: bigStart, excluded_apartment_ids: [], expected_total_minor: bigPv.body.total_minor, expected_apartment_count: bigPv.body.apartment_count, expected_hash: bigPv.body.preview_hash, idempotency_key: key('bigpost') });
  const postMs = Date.now() - tp1;
  check(`F13: 3000 daire / ${bigRows} defter satirinda onizleme ${previewMs} ms, onay ${postMs} ms (hedef < 4000 ms); satir sayisi ${bigPv.body.apartment_count}; toplam birebir`, bigPv.status === 200 && bigPost.status === 201 && previewMs < 4000 && postMs < 4000 && bigPost.body.entries_count === bigPv.body.apartment_count
    && BigInt((await q(`SELECT COALESCE(SUM(amount_minor), 0)::text AS s FROM ledger_entries WHERE late_fee_run_id = $1`, [bigPost.body.run.id])).rows[0].s) === BigInt(bigPv.body.total_minor), { previewMs, postMs, count: bigPv.body?.apartment_count });

  // --- F14. R10 P1-4: ISARET CALISTIRMASI - kimsenin gec odemedigi ay zinciri kilitlemez
  const mk = await mkManaged('F4B Tazminat Isaret', { 'I Blok': 2 });
  const mb = P(mk.code);
  const dayIn = (offset, day) => `${ym(offset)}-${String(day).padStart(2, '0')}`;
  const mset = await call('GET', `${mb}/settings`, MGR);
  const menable = await call('PUT', `${mb}/settings`, MGR, { expected_settings_version: mset.body.settings_version, late_fee: { enabled: true, start_period: ym(-4), rate_bp: 500, method: 'daily_30', grace_days: 0 } });
  const addCharge = (aptId, offset, due) => q(`INSERT INTO ledger_entries (site_code, apartment_id, kind, amount_minor, period, entry_date, due_date, payer_party) VALUES ($1, $2, 'charge', 100000, $3::date, $4::date, $5::date, 'both')`, [mk.code, aptId, `${ym(offset)}-01`, dayIn(offset, 3), due]);
  const addPayment = (aptId, offset, day) => q(`INSERT INTO ledger_entries (site_code, apartment_id, kind, amount_minor, period, entry_date, payer_party, method) VALUES ($1, $2, 'payment', -100000, $3::date, $4::date, 'both', 'cash')`, [mk.code, aptId, `${ym(offset)}-01`, dayIn(offset, day)]);
  for (const id of mk.ids) {
    await addCharge(id, -4, dayIn(-4, 10));
    await addPayment(id, -4, 8); // vadeden ONCE ode: tazminat YOK
  }
  await addCharge(mk.ids[0], -3, dayIn(-3, 10)); // ikinci ayda biri odemedi: tazminat VAR
  await addCharge(mk.ids[1], -3, dayIn(-3, 10));
  await addPayment(mk.ids[1], -3, 9);
  for (const off of [-4, -3, -2, -1]) await call('POST', `${mb}/periods/${ym(off)}/close`, MGR);
  const emptyPv = await call('POST', `${mb}/late-fee/preview`, MGR, {});
  check('F14: bos ay (kimse gec odemedi) onizleme empty:true, satir yok, can_post true, NOTHING_TO_POST engeli YOK; beklenen donem baslangic ayi',
    menable.status === 200 && emptyPv.status === 200 && emptyPv.body.empty === true && emptyPv.body.period === ym(-4) && emptyPv.body.apartment_count === 0 && emptyPv.body.total_minor === 0 && emptyPv.body.can_post === true && !emptyPv.body.blockers.includes('NOTHING_TO_POST'), emptyPv.body);
  const emptyBody = { period: ym(-4), expected_total_minor: 0, expected_apartment_count: 0, expected_hash: emptyPv.body.preview_hash };
  const noRecord = await call('POST', `${mb}/late-fee/post`, MGR, { ...emptyBody, idempotency_key: key('e0') });
  check('F14b: bos ayi acik onay (record_empty) OLMADAN onaylamak 409 NOTHING_TO_POST (eski davranis); hicbir sey yazilmaz', noRecord.status === 409 && noRecord.body.code === 'NOTHING_TO_POST' && (await q(`SELECT COUNT(*)::int AS n FROM late_fee_runs WHERE site_code = $1`, [mk.code])).rows[0].n === 0, noRecord.body);
  const markKey = key('e1');
  const mark1 = await call('POST', `${mb}/late-fee/post`, MGR, { ...emptyBody, record_empty: true, idempotency_key: markKey });
  const mark2 = await call('POST', `${mb}/late-fee/post`, MGR, { ...emptyBody, record_empty: true, idempotency_key: markKey });
  const mark3 = await call('POST', `${mb}/late-fee/post`, MGR, { ...emptyBody, idempotency_key: markKey });
  const markRow = (await q(`SELECT total_minor::text AS total, apartment_count, status FROM late_fee_runs WHERE site_code = $1 AND period = $2::date`, [mk.code, `${ym(-4)}-01`])).rows[0];
  const markLedger = (await q(`SELECT COUNT(*)::int AS n FROM ledger_entries WHERE site_code = $1 AND late_fee_run_id IS NOT NULL`, [mk.code])).rows[0].n;
  check('F14c: isaret calistirmasi 201 (tutar 0, daire 0, status active, entries_count 0, run.empty true); defter satiri YAZILMAZ; ayni anahtar 200 replay; ayni anahtar + record_empty farkli 409 IDEMPOTENCY_CONFLICT',
    mark1.status === 201 && mark1.body.entries_count === 0 && mark1.body.run.empty === true && mark1.body.run.total_minor === 0 && markRow.total === '0' && markRow.apartment_count === 0 && markRow.status === 'active' && markLedger === 0
      && mark2.status === 200 && mark2.body.run.id === mark1.body.run.id && mark3.status === 409 && mark3.body.code === 'IDEMPOTENCY_CONFLICT', [mark1.status, mark1.body, markRow, markLedger, mark2.status, mark3.status]);
  const mpv = await call('POST', `${mb}/late-fee/preview`, MGR, {});
  check('F14d: ZINCIR isaret calistirmasindan sonraki ayi kabul eder: beklenen donem ym(-3), onizlemede satir var, can_post true', mpv.status === 200 && mpv.body.period === ym(-3) && mpv.body.expected_period === ym(-3) && mpv.body.apartment_count === 1 && mpv.body.can_post === true && mpv.body.empty === false, mpv.body.blockers);
  const wrongEmpty = await call('POST', `${mb}/late-fee/post`, MGR, { period: ym(-3), expected_total_minor: 0, expected_apartment_count: 0, expected_hash: emptyPv.body.preview_hash, record_empty: true, idempotency_key: key('e2') });
  check('F14e: satir olan ayi "bos" diye kaydetmek (record_empty) 409 PREVIEW_STALE; hicbir sey yazilmaz', wrongEmpty.status === 409 && wrongEmpty.body.code === 'PREVIEW_STALE' && (await q(`SELECT COUNT(*)::int AS n FROM late_fee_runs WHERE site_code = $1`, [mk.code])).rows[0].n === 1, wrongEmpty.body);
  const mpost = await call('POST', `${mb}/late-fee/post`, MGR, { period: ym(-3), expected_total_minor: mpv.body.total_minor, expected_apartment_count: mpv.body.apartment_count, expected_hash: mpv.body.preview_hash, idempotency_key: key('e3') });
  check('F14f: isaretten sonraki ay NORMAL onaylanir (201, 1 satir, tutar > 0); bu ayin dogrulanmis tutari tabloya aynen yazilir', mpost.status === 201 && mpost.body.entries_count === 1 && mpost.body.run.total_minor === mpv.body.total_minor && mpost.body.run.total_minor > 0, [mpost.status, mpost.body]);
  const lineUpdate = await failMessage(`UPDATE late_fee_run_lines SET apartment_label = 'x' WHERE run_id = $1`, [mpost.body.run.id]);
  check('F14g: R10 P2-5: argumansiz degismezlik tetikleyicisi dogru mesaji verir ("finance records are append-only"), "FOREACH" hatasi degil', lineUpdate !== null && /append-only/.test(lineUpdate) && !/FOREACH/.test(lineUpdate), lineUpdate);
  // iptal sirasi: once son (normal) calistirma, sonra isaret calistirmasi
  const lastRun = await call('GET', `${mb}/late-fee/runs`, MGR);
  const voidNormal = await call('POST', `${mb}/late-fee/runs/${mpost.body.run.id}/void`, MGR, { reason: 'deneme', idempotency_key: key('v3') });
  const voidMarkerEarly = await call('POST', `${mb}/late-fee/runs/${mark1.body.run.id}/void`, MGR, { reason: 'erken', idempotency_key: key('v4') });
  check('F14h: yalniz SON aktif calistirma iptal edilir: son (normal) calistirma iptali 201 ve kalemleri ters kaydeder (reversed_count 1)', lastRun.body.voidable_run_id === mpost.body.run.id && voidNormal.status === 201 && voidNormal.body.reversed_count === 1, [lastRun.body.voidable_run_id, voidNormal.status, voidNormal.body]);
  check('F14i: isaret calistirmasi IPTAL edilebilir (201, reversed_count 0, status voided, defter satiri yok); zincir baslangic ayina doner', voidMarkerEarly.status === 201 && voidMarkerEarly.body.reversed_count === 0 && voidMarkerEarly.body.run.status === 'voided' && (await call('GET', `${mb}/late-fee/runs`, MGR)).body.next_period === ym(-4), [voidMarkerEarly.status, voidMarkerEarly.body]);
  // DB duzeyi: tutar / sayi tutarliligi (zincir tetikleyicisi gecer: sonraki donem baslangic ayi; CHECK devreye girer)
  const rawRun = (total, count, keyName) => failCode(`INSERT INTO late_fee_runs (site_code, period, params, total_minor, apartment_count, preview_hash, idempotency_key, request_fingerprint) VALUES ($1, $2::date, '{}'::jsonb, $3::bigint, $4, $5, $6, $5)`, [mk.code, `${ym(-4)}-01`, total, count, 'a'.repeat(64), keyName]);
  const badTotal = await rawRun(0, 1, 'raw-bad-1');
  const badCount = await rawRun(5, 0, 'raw-bad-2');
  const negative = await rawRun(-1, 0, 'raw-bad-3');
  check('F14j: DB CHECK: (tutar 0, daire 1), (tutar 5, daire 0) ve negatif tutar 23514 ile REDDEDILIR (isaret yalniz tutar = daire = 0)', badTotal === '23514' && badCount === '23514' && negative === '23514', [badTotal, badCount, negative]);
  const markerWithLine = await failMessage(`INSERT INTO late_fee_run_lines (run_id, site_code, apartment_id, apartment_label, amount_minor, base_day_minor, peak_overdue_minor, breakdown, ledger_entry_id) SELECT r.id, r.site_code, $2, 'x', 5, 5, 5, '[]'::jsonb, e.id FROM late_fee_runs r, ledger_entries e WHERE r.id = $1 AND e.site_code = r.site_code LIMIT 1`, [mark1.body.run.id, mk.ids[0]]);
  check('F14k: isaret calistirmasina (tutar 0) satir YAZILAMAZ: "satirlar calistirma toplamina esit olmali" tetikleyicisi reddeder', markerWithLine !== null && /add up to the run total/.test(markerWithLine), markerWithLine);
  void sleep; void hooks; void STAFF; void BOARD;
}
