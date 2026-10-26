// Finans Faz 4b QA bolumu: B. Makbuz (O1). scripts/qa_finance4b.mjs tarafindan yuklenir (t = ortak test ortami).
import { createHash, createHmac } from 'node:crypto';

export default async function sectionReceipts(t) {
  const { check, same, q, call, hooks, TODAY, monthStart, mkManaged, mkUser, addPerson, addResidency, P, key, pay, users } = t;
  const { MGR, MGR2, BOARD, STAFF, OUTSIDER, RESIDENT, SUPER } = users;
  console.log('--- B. makbuz ---');
  const site = await mkManaged('F4B Makbuz Sitesi', { 'A Blok': 6 });
  const [x1, x2, x3, x4, x5, x6] = site.ids;
  const owner = await mkUser('Malik Ahmet Yilmaz', 'apartment_owner', { phone: '05551112233', email: 'malik.gizli@qa.example' });
  const ownerPerson = await addPerson(site.code, { user: owner });
  await addResidency(site.code, x1, ownerPerson, 'owner');

  // --- B1. otomatik makbuz: numara, snapshot, dogrulama kodu
  const r1 = await pay(site, x1, 150000, { method: 'transfer', description: 'GIZLI-ACIKLAMA-123' });
  const rc1 = r1.body?.receipt;
  const year = Number(TODAY.slice(0, 4));
  check('B1: POST payments 201 + OTOMATIK makbuz { id, number: MK-yil-000001 } + movement_id null (hesap yok: 4a davranisi)', r1.status === 201 && rc1?.number === `MK-${year}-000001` && r1.body.movement_id === null, r1.body);
  const g1 = await call('GET', `${P(site.code)}/receipts/${rc1.id}`, MGR);
  const snap = g1.body?.snapshot ?? {};
  const expectCode = createHmac('sha256', process.env.FINANCE_RECEIPT_SECRET).update(`${site.code}|${year}|1|150000|${TODAY}`).digest('hex').slice(0, 12).toUpperCase();
  check('B1b: makbuz detayi: snapshot v1 (tutar, tarih, yontem, daire, ODEYEN = malik adi, duzenleyen), HMAC dogrulama kodu = beklenen, sablon taslak', g1.status === 200 && snap.v === 1 && snap.amount_minor === 150000 && snap.method === 'transfer' && snap.paid_on === TODAY && snap.apartment?.label === 'A Blok - Daire 1'
    && snap.payer?.name === 'Malik Ahmet Yilmaz' && snap.issuer?.name === 'F4B Yonetici' && g1.body.verification_code === expectCode && snap.verification_code === expectCode && g1.body.template.draft === true, { snap, code: g1.body?.verification_code, expectCode });
  const rawSnap = JSON.stringify(g1.body);
  check('B1c: snapshot / yanit KISISEL VERI icermez: telefon, e-posta, bakiye, serbest tahsilat aciklamasi YOK', !/05551112233|malik\.gizli|GIZLI-ACIKLAMA|balance/.test(rawSnap), rawSnap.slice(0, 300));
  const stored = (await q(`SELECT snapshot_sha256, snapshot FROM receipts WHERE id = $1`, [rc1.id])).rows[0];
  const canon = (v) => (Array.isArray(v) ? `[${v.map(canon).join(',')}]` : v && typeof v === 'object' ? `{${Object.keys(v).sort().map((k) => `${JSON.stringify(k)}:${canon(v[k])}`).join(',')}}` : JSON.stringify(v ?? null));
  check('B1d: snapshot_sha256 = kanonik JSON ozeti', stored.snapshot_sha256 === createHash('sha256').update(canon(stored.snapshot)).digest('hex'));

  // --- B2. idempotans / manuel duzenleme
  const entryId = r1.body.entry.id;
  const man = await call('POST', `${P(site.code)}/entries/${entryId}/receipt`, MGR);
  check('B2: manuel POST entries/:id/receipt IDEMPOTENT: aktif makbuz varsa 200 + AYNI makbuz (yeni numara almaz)', man.status === 200 && man.body.receipt.id === rc1.id, man.body);
  const counter0 = (await q(`SELECT last_no FROM receipt_counters WHERE site_code = $1 AND receipt_year = $2`, [site.code, year])).rows[0].last_no;
  check('B2b: sayac 1 (cift duzenleme numara tuketmedi)', Number(counter0) === 1, counter0);
  const chargeEntry = Number((await q(`INSERT INTO ledger_entries (site_code, apartment_id, kind, amount_minor, period, entry_date, due_date, payer_party) VALUES ($1, $2, 'charge', 5000, $3, $4, $4, 'both') RETURNING id`, [site.code, x2, monthStart(0), TODAY])).rows[0].id);
  const notPayment = await call('POST', `${P(site.code)}/entries/${chargeEntry}/receipt`, MGR);
  check('B2c: borc kaydina makbuz duzenlenemez (ENTRY_NOT_FOUND 404: yalniz tahsilat)', notPayment.status === 404, notPayment.body);

  // otomatiksiz site ayari: makbuz duzenlenmez, sonra manuel duzenlenir
  const st0 = await call('GET', `${P(site.code)}/settings`, MGR);
  const off = await call('PUT', `${P(site.code)}/settings`, MGR, { expected_settings_version: st0.body.settings_version, receipts: { auto_issue: false } });
  const noAuto = await pay(site, x2, 7000);
  check('B3: ayar receipts.auto_issue=false -> odeme makbuzsuz (receipt null); sonra manuel duzenleme 201', off.status === 200 && noAuto.status === 201 && noAuto.body.receipt === null && (await call('POST', `${P(site.code)}/entries/${noAuto.body.entry.id}/receipt`, MGR)).status === 201);
  const st1 = await call('GET', `${P(site.code)}/settings`, MGR);
  await call('PUT', `${P(site.code)}/settings`, MGR, { expected_settings_version: st1.body.settings_version, receipts: { auto_issue: true } });

  // --- B4. odeme ters cevrilince AYNI islemde iptal makbuzu
  const toReverse = await pay(site, x3, 40000);
  const rev = await call('POST', `${P(site.code)}/entries/${toReverse.body.entry.id}/reverse`, MGR, { reason: 'yanlis daire', idempotency_key: key('rv') });
  const afterRev = await call('GET', `${P(site.code)}/receipts?apartment_id=${x3}`, MGR);
  const canceled = afterRev.body.items.find((i) => i.id === toReverse.body.receipt.id);
  const cancellation = afterRev.body.items.find((i) => i.kind === 'cancellation');
  check('B4: odeme ters cevrilince makbuz otomatik IPTAL edilir (status cancelled) ve yeni numarali IPTAL makbuzu (payment_reversed) yazilir', rev.status === 201 && canceled?.status === 'cancelled' && cancellation && cancellation.status === null, afterRev.body);
  const cancDetail = await call('GET', `${P(site.code)}/receipts/${cancellation.id}`, MGR);
  check('B4b: iptal makbuzu detayi: cancels_number = asil numara, neden kodu payment_reversed; asil makbuz cancelled_by_number dolu', cancDetail.body.cancels_number === toReverse.body.receipt.number && cancDetail.body.cancel_reason_code === 'payment_reversed' && (await call('GET', `${P(site.code)}/receipts/${toReverse.body.receipt.id}`, MGR)).body.cancelled_by_number === cancDetail.body.number);
  const manRev = await call('POST', `${P(site.code)}/entries/${toReverse.body.entry.id}/receipt`, MGR);
  check('B4c: ters kayitli odemeye makbuz 409 PAYMENT_REVERSED', manRev.status === 409 && manRev.body.code === 'PAYMENT_REVERSED', manRev.body);
  const stmt = await call('GET', `${P(site.code)}/apartments/${x3}/account`, MGR);
  const stmtPay = stmt.body.items.find((e) => e.id === toReverse.body.entry.id);
  check('B4d: ekstrede odeme satiri makbuz bilgisini tasir (status cancelled + cancelled_by_number); sakin gorunumunde de makbuz numarasi var', stmtPay?.receipt?.status === 'cancelled' && stmtPay.receipt.cancelled_by_number === cancDetail.body.number && stmtPay.late_fee_run_id === null, stmtPay);

  // --- B5. duzeltme: eski makbuz iptal + yeni makbuz
  const toCorrect = await pay(site, x4, 25000);
  const cor = await call('POST', `${P(site.code)}/entries/${toCorrect.body.entry.id}/correct`, MGR, { amount_minor: 26000, entry_date: TODAY, method: 'cash', idempotency_key: key('cr') });
  const corList = (await call('GET', `${P(site.code)}/receipts?apartment_id=${x4}`, MGR)).body.items;
  check('B5: tahsilat duzeltme: eski makbuz iptal (payment_corrected) + YENI makbuz; yanitta yeni makbuz', cor.status === 201 && cor.body.receipt && corList.length === 3 && corList.filter((i) => i.status === 'active').length === 1
    && (await call('GET', `${P(site.code)}/receipts/${corList.find((i) => i.kind === 'cancellation').id}`, MGR)).body.cancel_reason_code === 'payment_corrected', corList);

  // --- B6. makbuz iptal ucu
  const toCancel = await pay(site, x5, 12000);
  const cancelKey = key('cancel');
  const balanceBefore = (await call('GET', `${P(site.code)}/apartments/${x5}/account`, MGR)).body.balance_minor;
  const c1 = await call('POST', `${P(site.code)}/receipts/${toCancel.body.receipt.id}/cancel`, MGR, { reason_code: 'issued_in_error', note: 'hatali duzenlendi', idempotency_key: cancelKey });
  const balanceAfter = (await call('GET', `${P(site.code)}/apartments/${x5}/account`, MGR)).body.balance_minor;
  check('B6: POST receipts/:id/cancel 201 { cancellation, receipt cancelled }; odeme DEGISMEZ (bakiye ayni)', c1.status === 201 && c1.body.cancellation.kind === 'cancellation' && c1.body.receipt.status === 'cancelled' && c1.body.cancellation.cancel_reason_code === 'issued_in_error' && balanceBefore === balanceAfter, c1.body);
  const c1b = await call('POST', `${P(site.code)}/receipts/${toCancel.body.receipt.id}/cancel`, MGR, { reason_code: 'issued_in_error', note: 'hatali duzenlendi', idempotency_key: cancelKey });
  const c1c = await call('POST', `${P(site.code)}/receipts/${toCancel.body.receipt.id}/cancel`, MGR, { reason_code: 'issued_in_error', idempotency_key: cancelKey }); // R15 P2-4: not FARKLI (yok) -> 409
  const c2 = await call('POST', `${P(site.code)}/receipts/${toCancel.body.receipt.id}/cancel`, MGR, { reason_code: 'issued_in_error', idempotency_key: key('c2') });
  const c3 = await call('POST', `${P(site.code)}/receipts/${c1.body.cancellation.id}/cancel`, MGR, { reason_code: 'issued_in_error', idempotency_key: key('c3') });
  const c4 = await call('POST', `${P(site.code)}/receipts/${toCancel.body.receipt.id}/cancel`, MGR, { reason_code: 'payment_reversed', idempotency_key: key('c4') });
  check('B6b: ayni anahtar + AYNI govdeyle tekrar 200 (replay), farkli not 409 IDEMPOTENCY_CONFLICT; ikinci iptal 409 RECEIPT_ALREADY_CANCELLED; iptal makbuzu iptal edilemez 409 RECEIPT_NOT_CANCELLABLE; gecersiz neden kodu 400',
    c1b.status === 200 && c1b.body.cancellation.id === c1.body.cancellation.id && c1c.status === 409 && c1c.body.code === 'IDEMPOTENCY_CONFLICT' && c2.status === 409 && c2.body.code === 'RECEIPT_ALREADY_CANCELLED' && c3.status === 409 && c3.body.code === 'RECEIPT_NOT_CANCELLABLE' && c4.status === 400, [c1b.status, c2.body, c3.body, c4.body]);
  const reissue = await call('POST', `${P(site.code)}/entries/${toCancel.body.entry.id}/receipt`, MGR);
  check('B6c: iptalden sonra AYNI odeme icin YENI makbuz duzenlenebilir (201, yeni numara)', reissue.status === 201 && reissue.body.receipt.id !== toCancel.body.receipt.id, reissue.body);
  const idemConflict = await call('POST', `${P(site.code)}/receipts/${reissue.body.receipt.id}/cancel`, MGR, { reason_code: 'issued_in_error', idempotency_key: cancelKey });
  check('B6d: baska makbuz icin kullanilmis iptal anahtari 409 IDEMPOTENCY_CONFLICT', idemConflict.status === 409 && idemConflict.body.code === 'IDEMPOTENCY_CONFLICT', idemConflict.body);

  // --- B7. basim olaylari
  const tp = await pay(site, x6, 3300);
  const pr1 = await call('POST', `${P(site.code)}/receipts/${tp.body.receipt.id}/print`, MGR, { idempotency_key: 'print-a' });
  const pr1b = await call('POST', `${P(site.code)}/receipts/${tp.body.receipt.id}/print`, MGR, { idempotency_key: 'print-a' });
  const prDeb = await call('POST', `${P(site.code)}/receipts/${tp.body.receipt.id}/print`, MGR, {});
  check('B7: ilk basim copy_number 1 (ASIL); ayni anahtar ve 5 sn icinde tekrar tek olay sayilir', pr1.status === 200 && pr1.body.copy_number === 1 && pr1.body.is_original === true && pr1b.body.copy_number === 1 && prDeb.body.copy_number === 1, [pr1.body, pr1b.body, prDeb.body]);
  await q(`ALTER TABLE receipt_print_events DISABLE TRIGGER USER`);
  await q(`UPDATE receipt_print_events SET printed_at = printed_at - INTERVAL '1 minute' WHERE receipt_id = $1`, [tp.body.receipt.id]);
  await q(`ALTER TABLE receipt_print_events ENABLE TRIGGER USER`);
  const pr2 = await call('POST', `${P(site.code)}/receipts/${tp.body.receipt.id}/print`, MGR, { idempotency_key: 'print-b' });
  const detail = await call('GET', `${P(site.code)}/receipts/${tp.body.receipt.id}`, MGR);
  check('B7b: 5 sn gecince yeni basim copy_number 2 (KOPYA); copy_count 2', pr2.body.copy_number === 2 && pr2.body.is_original === false && detail.body.copy_count === 2, [pr2.body, detail.body.copy_count]);
  const boardPrint = await call('POST', `${P(site.code)}/receipts/${tp.body.receipt.id}/print`, BOARD, {});
  check('B7c: kurul basim kaydi yazamaz (403)', boardPrint.status === 403, boardPrint.body);

  // --- B8. dogrulama
  const ok = await call('POST', `${P(site.code)}/receipts/verify`, MGR, { number: detail.body.number, code: detail.body.verification_code });
  const bad = await call('POST', `${P(site.code)}/receipts/verify`, MGR, { number: detail.body.number, code: 'AAAAAAAAAAAA' });
  const none = await call('POST', `${P(site.code)}/receipts/verify`, MGR, { number: `MK-${year}-999999`, code: detail.body.verification_code });
  const boardOk = await call('POST', `${P(site.code)}/receipts/verify`, BOARD, { number: detail.body.number, code: detail.body.verification_code.toLowerCase() });
  check('B8: dogrulama: dogru kod valid+active; yanlis kod / olmayan numara valid false (ayrinti sizmaz); kurul dogrulayabilir (kod harf duyarsiz); bicim hatasi 400',
    ok.body.valid === true && ok.body.status === 'active' && bad.body.valid === false && bad.body.status === null && none.body.valid === false && boardOk.status === 200 && boardOk.body.valid === true
      && (await call('POST', `${P(site.code)}/receipts/verify`, MGR, { number: 'x', code: 'y' })).status === 400, [ok.body, bad.body, none.body, boardOk.body]);

  // --- B9. yetki matrisi, IDOR, kurul redaksiyonu
  const matrix = [];
  for (const [label, user, expectWrite, expectRead] of [['yonetici', MGR, 201, 200], ['super', SUPER, 201, 200], ['kurul', BOARD, 403, 200], ['gorevli', STAFF, 403, 403], ['ilgisiz', OUTSIDER, 403, 403], ['baska site yoneticisi', MGR2, 403, 403], ['sakin', RESIDENT, 403, 403]]) {
    const read = await call('GET', `${P(site.code)}/receipts`, user);
    const fresh = await pay(site, x2, 100);
    const writeRes = await call('POST', `${P(site.code)}/receipts/${fresh.body.receipt.id}/cancel`, user, { reason_code: 'issued_in_error', idempotency_key: key('m') });
    matrix.push([label, read.status, writeRes.status === 201 || writeRes.status === 200 ? 201 : writeRes.status, expectRead, expectWrite]);
  }
  check('B9: yetki matrisi: yonetici/super yazar+okur; kurul YALNIZ okur (yazma 403); gorevli/ilgisiz/baska site/sakin 403', matrix.every(([, r, w, er, ew]) => r === er && w === ew), matrix);
  const boardDetail = await call('GET', `${P(site.code)}/receipts/${tp.body.receipt.id}`, BOARD);
  const boardCancelled = await call('GET', `${P(site.code)}/receipts/${c1.body.cancellation.id}`, BOARD);
  check('B9b: kurul yanitinda duzenleyen adi ve iptal notu YOK (null)', boardDetail.body.issued_by_name === null && boardCancelled.body.cancel_note === null && boardCancelled.body.issued_by_name === null, boardCancelled.body);
  const other = await mkManaged('F4B Baska Makbuz Sitesi', { 'B Blok': 2 });
  const foreign2 = await call('GET', `${P(site.code)}/receipts/${tp.body.receipt.id}`, MGR2);
  check('B9c: baska sitenin yoneticisi makbuzu goremez (403)', foreign2.status === 403, foreign2.status);
  const foreignOwn = await call('GET', `${P(other.code)}/receipts/${tp.body.receipt.id}`, MGR);
  check('B9d: IDOR: yonetici iki sitenin yoneticisiyken diger sitenin makbuz kimligini goremez (404 RECEIPT_NOT_FOUND)', foreignOwn.status === 404 && foreignOwn.body.code === 'RECEIPT_NOT_FOUND', foreignOwn.body);
  const crossCancel = await call('POST', `${P(other.code)}/receipts/${tp.body.receipt.id}/cancel`, MGR, { reason_code: 'issued_in_error', idempotency_key: key('x') });
  check('B9e: baska sitenin makbuzu iptal edilemez (404) ve DEGISMEDI', crossCancel.status === 404 && (await q(`SELECT COUNT(*)::int AS n FROM receipts WHERE cancels_receipt_id = $1`, [tp.body.receipt.id])).rows[0].n === 0, crossCancel.body);

  // --- B10. liste: sorgu, sayfalama, arama
  const list = await call('GET', `${P(site.code)}/receipts?limit=3`, MGR);
  const page2 = await call('GET', `${P(site.code)}/receipts?limit=3&before_id=${list.body.next_before_id}`, MGR);
  const byNumber = await call('GET', `${P(site.code)}/receipts?q=${encodeURIComponent(detail.body.number.slice(-4))}`, MGR);
  const byName = await call('GET', `${P(site.code)}/receipts?q=${encodeURIComponent('AHMET')}`, MGR);
  const onlyCanc = await call('GET', `${P(site.code)}/receipts?kind=cancellation`, MGR);
  check('B10: liste sayfalama (limit/before_id), numaraya ve odeyen adina gore arama (Turkce katlama), tura gore sorgu; gecersiz sorgu 400', list.body.items.length === 3 && list.body.next_before_id !== null && page2.body.items.every((i) => i.id < list.body.next_before_id)
    && byNumber.body.items.some((i) => i.id === tp.body.receipt.id) && byName.body.items.some((i) => i.id === rc1.id) && onlyCanc.body.items.every((i) => i.kind === 'cancellation') && (await call('GET', `${P(site.code)}/receipts?year=abc`, MGR)).status === 400);

  // --- B11. sakin ucu
  const mine = await call('GET', `/app/my-finance/receipts`, owner);
  const mineOne = await call('GET', `/app/my-finance/receipts/${rc1.id}`, owner);
  const mineOther = await call('GET', `/app/my-finance/receipts/${tp.body.receipt.id}`, owner);
  const stranger = await call('GET', `/app/my-finance/receipts`, OUTSIDER);
  check('B11: sakin YALNIZ kendi dairesinin makbuzlarini gorur; baska daire 404; ilgisiz kullanici bos; yanitta ledger_entry_id / copy_count / cancel_note / issued_by YOK',
    mine.status === 200 && mine.body.items.length === 1 && mine.body.items[0].id === rc1.id && mineOne.status === 200 && !('ledger_entry_id' in mineOne.body) && !('copy_count' in mineOne.body) && !('cancel_note' in mineOne.body) && !('issued_by_name' in mineOne.body)
      && mineOther.status === 404 && stranger.body.items.length === 0, [mine.body, mineOther.status]);

  // --- B12. finans TEMEL modul (Kural 25, 079): kapatilamaz; satir elle enabled=FALSE yazilsa bile makbuz uclari acik kalir (MODULE_DISABLED asla)
  const closeTry = await call('PUT', `/manager/sites/${other.code}/modules/finance`, SUPER, { enabled: false });
  await q(`INSERT INTO site_modules (site_code, module_code, enabled) VALUES ($1, 'finance', FALSE) ON CONFLICT (site_code, module_code) DO UPDATE SET enabled = FALSE`, [other.code]);
  const stillOpen = await call('GET', `${P(other.code)}/receipts`, MGR);
  await q(`DELETE FROM site_modules WHERE site_code = $1 AND module_code = 'finance'`, [other.code]);
  check('B12: finans kapatilamaz (400 MODULE_NOT_TOGGLEABLE); site_modules satiri enabled=FALSE olsa bile makbuz uclari 200 (MODULE_DISABLED YOK)', closeTry.status === 400 && closeTry.body.code === 'MODULE_NOT_TOGGLEABLE' && stillOpen.status === 200 && Array.isArray(stillOpen.body.items), [closeTry.body, stillOpen.status]);

  // --- B13. 50 eszamanli tahsilat: bosluksuz numara dizisi
  const race = await mkManaged('F4B Makbuz Yaris', { 'Y Blok': 10 });
  const results = await Promise.all(Array.from({ length: 50 }, (_, i) => pay(race, race.ids[i % 10], 1000 + i, { idempotency_key: `race-${i}-${Date.now()}` })));
  const numbers = results.map((r) => r.body?.receipt?.number).filter(Boolean).sort();
  const seq = (await q(`SELECT receipt_no FROM receipts WHERE site_code = $1 AND receipt_year = $2 ORDER BY receipt_no`, [race.code, year])).rows.map((r) => Number(r.receipt_no));
  const gaps = (await q(`SELECT COUNT(*)::int AS n FROM generate_series(1, $2::int) g WHERE NOT EXISTS (SELECT 1 FROM receipts WHERE site_code = $1 AND receipt_year = $3 AND receipt_no = g)`, [race.code, 50, year])).rows[0].n;
  const counterRow = Number((await q(`SELECT last_no FROM receipt_counters WHERE site_code = $1 AND receipt_year = $2`, [race.code, year])).rows[0].last_no);
  check('B13: 50 ESZAMANLI tahsilat -> 50 makbuz, COUNT = MAX = sayac = 50, generate_series ile bosluk = 0, tekrar yok', results.every((r) => r.status === 201) && numbers.length === 50 && new Set(numbers).size === 50 && seq.length === 50 && seq[49] === 50 && counterRow === 50 && gaps === 0, { statuses: results.map((r) => r.status).filter((s) => s !== 201), gaps, counterRow });

  // --- B14. geri alma: sayac de geri doner (bosluk yok)
  const beforeNo = Number((await q(`SELECT last_no FROM receipt_counters WHERE site_code = $1 AND receipt_year = $2`, [race.code, year])).rows[0].last_no);
  hooks.failOnce = { match: /SELECT COALESCE\(SUM\(amount_minor\), 0\)::TEXT AS balance FROM ledger_entries/, code: '57014', times: 1 };
  const failed = await pay(race, race.ids[0], 4444, { idempotency_key: key('fail') });
  hooks.failOnce = null;
  const afterFailNo = Number((await q(`SELECT last_no FROM receipt_counters WHERE site_code = $1 AND receipt_year = $2`, [race.code, year])).rows[0].last_no);
  const nextOk = await pay(race, race.ids[0], 4445, { idempotency_key: key('ok') });
  check('B14: islem ortasinda hata (makbuz yazildiktan sonra) -> ROLLBACK: sayac DEGISMEDI, odeme / makbuz yok; sonraki odeme AYNI numarayi alir (bosluk yok)',
    failed.status === 500 && afterFailNo === beforeNo && nextOk.body.receipt.number.endsWith(String(beforeNo + 1).padStart(6, '0')), { failed: failed.status, beforeNo, afterFailNo, next: nextOk.body?.receipt });

  // --- B15. odeme ters kayit x makbuz yarisi
  const dup = await mkManaged('F4B Makbuz Cakisma', { 'C Blok': 2 });
  const dp = await pay(dup, dup.ids[0], 5000);
  const raced = await Promise.all([
    call('POST', `${P(dup.code)}/entries/${dp.body.entry.id}/reverse`, MGR, { idempotency_key: key('r1') }),
    call('POST', `${P(dup.code)}/entries/${dp.body.entry.id}/receipt`, MGR),
    call('POST', `${P(dup.code)}/receipts/${dp.body.receipt.id}/cancel`, MGR, { reason_code: 'issued_in_error', idempotency_key: key('r3') }),
    call('POST', `${P(dup.code)}/entries/${dp.body.entry.id}/receipt`, MGR),
  ]);
  const active = (await q(`SELECT COUNT(*)::int AS n FROM receipts r WHERE r.site_code = $1 AND r.kind = 'collection' AND NOT EXISTS (SELECT 1 FROM receipts c WHERE c.cancels_receipt_id = r.id)`, [dup.code])).rows[0].n;
  const reversedRows = (await q(`SELECT COUNT(*)::int AS n FROM ledger_entries WHERE site_code = $1 AND kind = 'reversal'`, [dup.code])).rows[0].n;
  const collections = (await q(`SELECT COUNT(*)::int AS n FROM receipts WHERE site_code = $1 AND kind = 'collection'`, [dup.code])).rows[0].n;
  const cancellations = (await q(`SELECT COUNT(*)::int AS n FROM receipts WHERE site_code = $1 AND kind = 'cancellation'`, [dup.code])).rows[0].n;
  check('B15: ESZAMANLI ters kayit / manuel makbuz / iptal: sonuc tutarli (ters kayitli odemenin AKTIF makbuzu yok; makbuz sayisi = iptal + aktif; sunucu hatasi yok)',
    reversedRows === 1 && active === 0 && collections - cancellations === active && raced.every((r) => r.status < 500), { raced: raced.map((r) => [r.status, r.body?.code]), active, reversedRows, collections, cancellations });

  // --- B16. yil donumu: DB saati bir sonraki yilin 2 Ocak'ina alinirsa YENI yil sayaci 1'den baslar; eski yil sayaci korunur (iki yil birbirinden bagimsiz)
  const yr = await mkManaged('F4B Makbuz Yil', { 'Y Blok': 3 });
  const y1 = await pay(yr, yr.ids[0], 1100);
  hooks.rewrite = (text) => (text.includes('(SELECT clock_timestamp() AS t) x') ? text.replace('SELECT clock_timestamp() AS t', `SELECT TIMESTAMPTZ '${year + 1}-01-02 10:00:00+03' AS t`) : text);
  const y2 = await pay(yr, yr.ids[1], 1200);
  const y3 = await pay(yr, yr.ids[2], 1300);
  hooks.rewrite = null;
  const y4 = await pay(yr, yr.ids[0], 1400);
  const yearRows = (await q(`SELECT receipt_year, receipt_no, to_char(issued_on, 'YYYY-MM-DD') AS issued_on FROM receipts WHERE site_code = $1 ORDER BY id`, [yr.code])).rows;
  const yearCounters = (await q(`SELECT receipt_year, last_no FROM receipt_counters WHERE site_code = $1 ORDER BY receipt_year`, [yr.code])).rows.map((r) => [Number(r.receipt_year), Number(r.last_no)]);
  check('B16: YIL DONUMU: bu yil MK-yil-000001, DB saati gelecek yila alininca MK-(yil+1)-000001 ve 000002 (yeni sayac 1\'den), geri donunce bu yilin sayaci kaldigi yerden (000002); issued_on yilla tutarli',
    y1.body.receipt.number === `MK-${year}-000001` && y2.body.receipt.number === `MK-${year + 1}-000001` && y3.body.receipt.number === `MK-${year + 1}-000002` && y4.body.receipt.number === `MK-${year}-000002`
      && same(yearCounters, [[year, 2], [year + 1, 2]]) && yearRows.filter((r) => r.receipt_year === year + 1).every((r) => r.issued_on === `${year + 1}-01-02`),
    { numbers: [y1, y2, y3, y4].map((r) => r.body?.receipt?.number ?? r.body), yearCounters, yearRows });
}
