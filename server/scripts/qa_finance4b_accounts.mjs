// Finans Faz 4b QA bolumu: C. Kasa / banka hesaplari (O4). scripts/qa_finance4b.mjs tarafindan yuklenir (t = ortak test ortami).

export default async function sectionAccounts(t) {
  const { check, same, q, call, hooks, TODAY, ago, monthStart, mkManaged, P, key, pay, failMessage, failCode, users } = t;
  const { MGR, BOARD, STAFF, OUTSIDER, RESIDENT } = users;
  console.log('--- C. kasa / banka ---');
  const site = await mkManaged('F4B Kasa Sitesi', { 'K Blok': 6 });
  const [k1, k2, k3, k4, k5] = site.ids;
  const acc = (body, user = MGR) => call('POST', `${P(site.code)}/accounts`, user, { kind: 'cash', opening_balance_minor: 0, opening_date: TODAY, idempotency_key: key('acc'), ...body });
  const bal = async (id) => (await call('GET', `${P(site.code)}/accounts`, MGR)).body.items.find((a) => a.id === id)?.balance_minor;
  const movementsOf = async (id) => (await call('GET', `${P(site.code)}/accounts/${id}/movements?limit=200`, MGR)).body;

  // --- C0. hesap yokken 4a davranisi
  const p0 = await pay(site, k1, 10000);
  check('C0: hesap YOKKEN odeme 4a gibi calisir (account_id gerekmez, movement_id null)', p0.status === 201 && p0.body.movement_id === null, p0.body);
  const noAccExpense = await call('GET', `${P(site.code)}/accounts`, MGR);
  check('C0b: GET accounts bos liste + eslenmemis 0', noAccExpense.status === 200 && noAccExpense.body.items.length === 0 && noAccExpense.body.unassigned_payments.count === 0 && noAccExpense.body.total_balance_minor === 0, noAccExpense.body);

  // --- C1. hesap olusturma: dogrulama, acilis hareketi
  const bad = [];
  for (const [label, body] of [['bos ad', { name: '' }], ['61 karakter ad', { name: 'x'.repeat(61) }], ['gecersiz tur', { name: 'A', kind: 'x' }], ['ondalik bakiye', { name: 'A', opening_balance_minor: 10.5 }], ['10^12 ustu bakiye', { name: 'A', opening_balance_minor: 1000000000001 }],
    ['gelecek acilis', { name: 'A', opening_date: '2999-01-01' }], ['gecersiz tarih', { name: 'A', opening_date: '2026-02-30' }], ['anahtarsiz', { name: 'A', idempotency_key: '' }], ['not 201', { name: 'A', note: 'x'.repeat(201) }]]) {
    bad.push([label, (await acc(body)).status]);
  }
  check('C1: hesap olusturma dogrulamalari 400 (ad, tur, bakiye, tarih, anahtar, not)', bad.every(([, s]) => s === 400), bad);
  const kasa = await acc({ name: 'Ana Kasa', kind: 'cash', opening_balance_minor: 50000, note: 'nakit' });
  check('C1b: 201 hesap + acilis bakiyesi 50000; acilis HAREKETI yazildi (kind opening); bakiye = acilis', kasa.status === 201 && kasa.body.account.balance_minor === 50000 && kasa.body.account.opening_balance_minor === 50000 && (await movementsOf(kasa.body.account.id)).items.some((m) => m.kind === 'opening' && m.amount_minor === 50000), kasa.body);
  const banka = await acc({ name: 'Banka', kind: 'bank', opening_balance_minor: 0 });
  check('C1c: acilis bakiyesi 0 ise acilis hareketi YAZILMAZ; bakiye 0', banka.status === 201 && banka.body.account.balance_minor === 0 && (await movementsOf(banka.body.account.id)).items.length === 0);
  const kasaId = kasa.body.account.id;
  const bankaId = banka.body.account.id;
  const dupName = await acc({ name: 'ANA KASA' });
  const sameKey = key('same');
  const first = await acc({ name: 'Yedek', idempotency_key: sameKey });
  const replay = await acc({ name: 'Yedek', idempotency_key: sameKey });
  const conflict = await acc({ name: 'Baska', idempotency_key: sameKey });
  check('C2: ad tekil (buyuk-kucuk harf duyarsiz) 409 ACCOUNT_NAME_TAKEN; ayni anahtar + ayni gövde 200 replay (tek hesap); ayni anahtar + farkli gövde 409 IDEMPOTENCY_CONFLICT',
    dupName.status === 409 && dupName.body.code === 'ACCOUNT_NAME_TAKEN' && first.status === 201 && replay.status === 200 && replay.body.account.id === first.body.account.id && conflict.status === 409 && conflict.body.code === 'IDEMPOTENCY_CONFLICT', [dupName.body, replay.status, conflict.body]);
  const yedekId = first.body.account.id;

  // --- C3. odeme <-> hesap esleme
  const needAcc = await pay(site, k2, 20000);
  check('C3: aktif hesap varken account_id YOKSA odeme 409 ACCOUNT_REQUIRED (hicbir kayit yazilmaz)', needAcc.status === 409 && needAcc.body.code === 'ACCOUNT_REQUIRED' && (await q(`SELECT COUNT(*)::int AS n FROM ledger_entries WHERE site_code = $1 AND apartment_id = $2`, [site.code, k2])).rows[0].n === 0, needAcc.body);
  const withAcc = await pay(site, k2, 20000, { account_id: kasaId });
  check('C3b: account_id ile odeme 201 + movement_id; kasa bakiyesi 50000 + 20000', withAcc.status === 201 && withAcc.body.movement_id > 0 && (await bal(kasaId)) === 70000, withAcc.body);
  const notFoundAcc = await pay(site, k2, 100, { account_id: 99999999 });
  const otherSite = await mkManaged('F4B Kasa Baska', { 'B Blok': 1 });
  const otherAcc = await call('POST', `${P(otherSite.code)}/accounts`, MGR, { name: 'Baska Kasa', kind: 'cash', opening_balance_minor: 0, opening_date: TODAY, idempotency_key: key('oa') });
  const foreignAcc = await pay(site, k2, 100, { account_id: otherAcc.body.account.id });
  check('C3c: olmayan / BASKA SITENIN hesabi 404 ACCOUNT_NOT_FOUND (IDOR yok); odeme yazilmadi', notFoundAcc.status === 404 && foreignAcc.status === 404 && foreignAcc.body.code === 'ACCOUNT_NOT_FOUND' && (await bal(kasaId)) === 70000, [notFoundAcc.body, foreignAcc.body]);
  const passive = await call('PATCH', `${P(site.code)}/accounts/${yedekId}`, MGR, { is_active: false });
  const inactive = await pay(site, k2, 100, { account_id: yedekId });
  check('C3d: pasif hesaba odeme 409 ACCOUNT_INACTIVE; PATCH yanitinda bakiye var (istemci uyarir)', passive.status === 200 && passive.body.account.is_active === false && 'balance_minor' in passive.body.account && inactive.status === 409 && inactive.body.code === 'ACCOUNT_INACTIVE', inactive.body);
  // acilistan ONCEKI tarihli odeme: hesap acilis tarihi bugun; dun tarihli odeme -> hesap gerekmez (acilis bakiyesine dahil), account_id verilirse BEFORE_OPENING_DATE
  const yesterdayNoAcc = await pay(site, k3, 3000, { entry_date: ago(1) });
  const yesterdayAcc = await pay(site, k3, 3000, { entry_date: ago(1), account_id: kasaId });
  check('C3e: acilis tarihinden ONCEKI tahsilat hesap istemez (acilis bakiyesine dahil); hesap verilirse 409 BEFORE_OPENING_DATE', yesterdayNoAcc.status === 201 && yesterdayNoAcc.body.movement_id === null && yesterdayAcc.status === 409 && yesterdayAcc.body.code === 'BEFORE_OPENING_DATE', [yesterdayNoAcc.body.movement_id, yesterdayAcc.body]);

  // --- C4. ters kayit / duzeltme -> ayna hareket
  const rv = await call('POST', `${P(site.code)}/entries/${withAcc.body.entry.id}/reverse`, MGR, { reason: 'iptal', idempotency_key: key('rv') });
  const mv = await movementsOf(kasaId);
  const col = mv.items.find((m) => m.kind === 'collection');
  const mir = mv.items.find((m) => m.kind === 'reversal');
  check('C4: odeme ters cevrilince eslenmis hareketin AYNASI (reversal, -tutar, bugun) AYNI islemde yazilir; kasa bakiyesi geri 50000; hareketler birbirine bagli', rv.status === 201 && (await bal(kasaId)) === 50000 && col && mir && mir.amount_minor === -20000 && mir.reverses_movement_id === col.id && col.reversed_by_movement_id === mir.id, mv.items);
  const cp = await pay(site, k4, 8000, { account_id: bankaId });
  const cr = await call('POST', `${P(site.code)}/entries/${cp.body.entry.id}/correct`, MGR, { amount_minor: 9000, entry_date: TODAY, method: 'cash', idempotency_key: key('cr') });
  check('C4b: duzeltme (hesap verilmedi): eski hareket aynalanir, yeni tahsilat ESKI hesaba yazilir (banka 9000)', cr.status === 201 && cr.body.movement_id > 0 && (await bal(bankaId)) === 9000, cr.body);
  const cp2 = await pay(site, k4, 1000, { account_id: bankaId });
  const cr2 = await call('POST', `${P(site.code)}/entries/${cp2.body.entry.id}/correct`, MGR, { amount_minor: 1000, entry_date: TODAY, method: 'cash', idempotency_key: key('cr2'), account_id: kasaId });
  check('C4c: duzeltmede yeni hesap verilirse tahsilat O hesaba gider (banka 9000 korunur, kasa +1000)', cr2.status === 201 && (await bal(bankaId)) === 9000 && (await bal(kasaId)) === 51000, [cr2.body, await bal(bankaId), await bal(kasaId)]);
  const chargeReverse = Number((await q(`INSERT INTO ledger_entries (site_code, apartment_id, kind, amount_minor, period, entry_date, due_date, payer_party) VALUES ($1, $2, 'charge', 100, $3, $4, $4, 'both') RETURNING id`, [site.code, k5, monthStart(0), TODAY])).rows[0].id);
  const revCharge = await call('POST', `${P(site.code)}/entries/${chargeReverse}/reverse`, MGR, { idempotency_key: key('rc') });
  check('C4d: borc kaydinin ters kaydi hesap hareketi YAZMAZ (kasa bakiyesi degismez)', revCharge.status === 201 && (await bal(kasaId)) === 51000);

  // --- C5. duzeltme hareketi (adjustment)
  const adj = (id, body, user = MGR) => call('POST', `${P(site.code)}/accounts/${id}/adjustments`, user, { amount_minor: -250, movement_date: TODAY, reason_code: 'bank_fee', idempotency_key: key('adj'), ...body });
  const adjBad = [];
  for (const [label, body] of [['tutar 0', { amount_minor: 0 }], ['gecersiz neden', { reason_code: 'x' }], ['other + notsuz', { reason_code: 'other' }], ['gelecek', { movement_date: '2999-01-01' }], ['anahtarsiz', { idempotency_key: '' }]]) adjBad.push([label, (await adj(bankaId, body)).status]);
  check('C5: duzeltme dogrulamalari 400 (tutar 0, neden, other icin not zorunlu, gelecek tarih, anahtar)', adjBad.every(([, s]) => s === 400), adjBad);
  const adjOk = await adj(bankaId, { amount_minor: -250 });
  check('C5b: banka masrafi (-250) 201; bakiye 9000 - 250; raporda AYRI hareket (adjustment, reason_code bank_fee)', adjOk.status === 201 && (await bal(bankaId)) === 8750 && adjOk.body.movement.kind === 'adjustment' && adjOk.body.movement.reason_code === 'bank_fee', adjOk.body);
  const adjKey = key('adjk');
  const a1 = await adj(bankaId, { amount_minor: 500, reason_code: 'bank_interest', idempotency_key: adjKey });
  const a2 = await adj(bankaId, { amount_minor: 500, reason_code: 'bank_interest', idempotency_key: adjKey });
  const a3 = await adj(bankaId, { amount_minor: 600, reason_code: 'bank_interest', idempotency_key: adjKey });
  check('C5c: ayni anahtar tekrar 200 (cift hareket yok, bakiye +500 bir kez); farkli gövde 409 IDEMPOTENCY_CONFLICT', a1.status === 201 && a2.status === 200 && a2.body.movement.id === a1.body.movement.id && a3.status === 409 && (await bal(bankaId)) === 9250, [a2.body, a3.body]);
  const adjInactive = await adj(yedekId, {});
  const adjBefore = await adj(bankaId, { movement_date: ago(3) });
  check('C5d: pasif hesaba 409 ACCOUNT_INACTIVE; acilis tarihinden once 409 BEFORE_OPENING_DATE', adjInactive.status === 409 && adjInactive.body.code === 'ACCOUNT_INACTIVE' && adjBefore.status === 409 && adjBefore.body.code === 'BEFORE_OPENING_DATE', [adjInactive.body, adjBefore.body]);

  // --- C6. aktarim
  const tr = (body, user = MGR) => call('POST', `${P(site.code)}/transfers`, user, { from_account_id: kasaId, to_account_id: bankaId, amount_minor: 4000, transfer_date: TODAY, idempotency_key: key('tr'), ...body });
  const trBad = [];
  for (const [label, body] of [['ayni hesap', { to_account_id: kasaId }], ['tutar 0', { amount_minor: 0 }], ['gelecek', { transfer_date: '2999-01-01' }], ['anahtarsiz', { idempotency_key: '' }], ['olmayan hesap id', { to_account_id: 'abc' }]]) trBad.push([label, (await tr(body)).status]);
  check('C6: aktarim dogrulamalari 400 (ayni hesap, tutar, tarih, anahtar, hesap kimligi)', trBad.every(([, s]) => s === 400), trBad);
  const kasaBefore = await bal(kasaId);
  const bankaBefore = await bal(bankaId);
  const trOk = await tr({});
  const trMovs = trOk.body?.movements ?? [];
  check('C6b: aktarim 201: TEK islemde iki hareket (transfer_out -4000 / transfer_in +4000); bakiyeler guncel; toplam degismez', trOk.status === 201 && trMovs.length === 2 && trMovs.map((m) => m.kind).sort().join() === 'transfer_in,transfer_out' && (await bal(kasaId)) === kasaBefore - 4000 && (await bal(bankaId)) === bankaBefore + 4000, trOk.body);
  const trKey = key('trk');
  const t1 = await tr({ idempotency_key: trKey });
  const t2 = await tr({ idempotency_key: trKey });
  const t3 = await tr({ idempotency_key: trKey, amount_minor: 4001 });
  check('C6c: ayni anahtar tekrar 200 (cift aktarim yok); farkli gövde 409 IDEMPOTENCY_CONFLICT', t1.status === 201 && t2.status === 200 && t2.body.transfer.id === t1.body.transfer.id && t3.status === 409 && t3.body.code === 'IDEMPOTENCY_CONFLICT');
  const trInactive = await tr({ to_account_id: yedekId });
  const trMissing = await tr({ to_account_id: otherAcc.body.account.id });
  check('C6d: pasif hesaba 409 ACCOUNT_INACTIVE; BASKA SITENIN hesabi 404 ACCOUNT_NOT_FOUND', trInactive.status === 409 && trInactive.body.code === 'ACCOUNT_INACTIVE' && trMissing.status === 404, [trInactive.body, trMissing.body]);
  // atomiklik: ikinci hareket yazilirken hata -> hicbiri yok
  const trCountBefore = (await q(`SELECT (SELECT COUNT(*) FROM account_transfers WHERE site_code = $1)::int AS t, (SELECT COUNT(*) FROM account_movements WHERE site_code = $1)::int AS m`, [site.code])).rows[0];
  hooks.failOnce = { match: /INSERT INTO account_movements \(site_code, account_id, kind, amount_minor, movement_date, period, transfer_id, created_by\)/, code: '57014', times: 1 };
  const trFail = await tr({ amount_minor: 1234 });
  hooks.failOnce = null;
  const trCountAfter = (await q(`SELECT (SELECT COUNT(*) FROM account_transfers WHERE site_code = $1)::int AS t, (SELECT COUNT(*) FROM account_movements WHERE site_code = $1)::int AS m`, [site.code])).rows[0];
  check('C6e: aktarim ortasinda hata -> ROLLBACK: ne aktarim ne hareket kalir (yarim aktarim yok)', trFail.status === 500 && same(trCountBefore, trCountAfter), [trFail.status, trCountBefore, trCountAfter]);
  const kasaPre = await bal(kasaId);
  const bankaPre = await bal(bankaId);
  const vo = await call('POST', `${P(site.code)}/transfers/${trOk.body.transfer.id}/void`, MGR, { reason: 'yanlis hesap', idempotency_key: key('tv') });
  const vo2 = await call('POST', `${P(site.code)}/transfers/${trOk.body.transfer.id}/void`, MGR, { reason: 'tekrar', idempotency_key: key('tv2') });
  const list = await call('GET', `${P(site.code)}/transfers`, MGR);
  check('C6f: aktarim iptali iki AYNA hareket yazar (kasa +4000, banka -4000); ikinci iptal 409 TRANSFER_ALREADY_VOIDED; listede voided dolu',
    vo.status === 201 && vo.body.transfer.voided !== null && (await bal(kasaId)) === kasaPre + 4000 && (await bal(bankaId)) === bankaPre - 4000 && vo2.status === 409 && vo2.body.code === 'TRANSFER_ALREADY_VOIDED'
      && list.body.items.find((i) => i.id === trOk.body.transfer.id)?.voided !== null, [vo.body, vo2.body]);
  const transferNet = (await q(`SELECT COALESCE(SUM(amount_minor), 0)::text AS s FROM account_movements WHERE site_code = $1 AND transfer_id IS NOT NULL`, [site.code])).rows[0].s;
  const mirrorNet = (await q(`SELECT COALESCE(SUM(r.amount_minor), 0)::text AS s FROM account_movements r JOIN account_movements o ON o.id = r.reverses_movement_id WHERE r.site_code = $1 AND o.transfer_id IS NOT NULL`, [site.code])).rows[0].s;
  check('C6g: DEGISMEZ: aktarim hareketleri + aynalari toplami 0 (transfer net 0)', BigInt(transferNet) + BigInt(mirrorNet) === 0n, { transferNet, mirrorNet });

  // --- C7. mutabakat
  const accList = await call('GET', `${P(site.code)}/accounts`, MGR);
  const bankaNow = accList.body.items.find((a) => a.id === bankaId).balance_minor;
  const rec = (body, id = bankaId) => call('POST', `${P(site.code)}/accounts/${id}/reconciliations`, MGR, { as_of_date: TODAY, statement_balance_minor: bankaNow, expected_computed_minor: bankaNow, idempotency_key: key('rec'), ...body });
  const recOk = await rec({});
  check('C7: mutabakat fark 0: 201, difference_minor 0, duzeltme yok', recOk.status === 201 && recOk.body.reconciliation.difference_minor === 0 && recOk.body.reconciliation.adjusted === false, recOk.body);
  const recStale = await rec({ expected_computed_minor: bankaNow + 1 });
  check('C7b: beklenen hesaplanan bakiye farkliysa 409 RECONCILIATION_STALE (+ guncel deger); kayit yazilmaz', recStale.status === 409 && recStale.body.code === 'RECONCILIATION_STALE' && recStale.body.computed_balance_minor === bankaNow, recStale.body);
  const recDiff = await rec({ statement_balance_minor: bankaNow - 300, adjust: { reason_code: 'bank_fee', note: 'ekstre farki' } });
  check('C7c: fark -300 + adjust: duzeltme hareketi AYNI islemde (-300) yazilir; banka bakiyesi ekstreyle esit', recDiff.status === 201 && recDiff.body.reconciliation.difference_minor === -300 && recDiff.body.reconciliation.adjusted === true && (await bal(bankaId)) === bankaNow - 300, recDiff.body);
  const recKey = key('reck');
  const bankaNow2 = await bal(bankaId);
  const r1 = await rec({ statement_balance_minor: bankaNow2, expected_computed_minor: bankaNow2, idempotency_key: recKey });
  const r2 = await rec({ statement_balance_minor: bankaNow2, expected_computed_minor: bankaNow2, idempotency_key: recKey });
  const r3 = await rec({ statement_balance_minor: bankaNow2 + 5, expected_computed_minor: bankaNow2, idempotency_key: recKey });
  check('C7d: ayni anahtar tekrar 200 (tek kayit); farkli gövde 409 IDEMPOTENCY_CONFLICT; mutabakat gecmisi listelenir', r1.status === 201 && r2.status === 200 && r2.body.reconciliation.id === r1.body.reconciliation.id && r3.status === 409
    && (await call('GET', `${P(site.code)}/accounts/${bankaId}/reconciliations`, MGR)).body.items.length >= 3);
  const accAfter = (await call('GET', `${P(site.code)}/accounts`, MGR)).body.items.find((a) => a.id === bankaId);
  check('C7e: hesap listesinde son mutabakat (as_of_date, difference_minor) gorunur', accAfter.last_reconciliation && accAfter.last_reconciliation.as_of_date === TODAY, accAfter.last_reconciliation);
  const recBefore = await rec({ as_of_date: ago(400), statement_balance_minor: 0, expected_computed_minor: 0 });
  check('C7f: acilis tarihinden ONCEKI ekstre tarihi 409 BEFORE_OPENING_DATE', recBefore.status === 409 && recBefore.body.code === 'BEFORE_OPENING_DATE', recBefore.body);

  // --- C8. eslenmemis tahsilat: toplu esleme + ay kapatma engeli
  const s2 = await mkManaged('F4B Kasa Eslestirme', { 'E Blok': 4 });
  const [e1, e2, e3, e4] = s2.ids;
  await call('POST', `${P(s2.code)}/payments`, MGR, { apartment_id: e1, amount_minor: 1000, entry_date: ago(40), method: 'cash', idempotency_key: key('p1') });
  await call('POST', `${P(s2.code)}/payments`, MGR, { apartment_id: e2, amount_minor: 2000, entry_date: ago(35), method: 'transfer', idempotency_key: key('p2') });
  const pe3 = await call('POST', `${P(s2.code)}/payments`, MGR, { apartment_id: e3, amount_minor: 4000, entry_date: ago(2), method: 'cheque', idempotency_key: key('p3') });
  void pe3;
  const kasa2 = await call('POST', `${P(s2.code)}/accounts`, MGR, { name: 'Kasa', kind: 'cash', opening_balance_minor: 0, opening_date: ago(60), idempotency_key: key('a1') });
  const banka2 = await call('POST', `${P(s2.code)}/accounts`, MGR, { name: 'Banka', kind: 'bank', opening_balance_minor: 0, opening_date: ago(60), idempotency_key: key('a2') });
  const list2 = await call('GET', `${P(s2.code)}/accounts`, MGR);
  check('C8: hesap acilisindan sonraki, hesaba eslenmemis tahsilatlar listelenir (3 adet, toplam 7000)', kasa2.status === 201 && list2.body.unassigned_payments.count === 3 && list2.body.unassigned_payments.total_minor === 7000, list2.body.unassigned_payments);
  const lastMonth = monthStart(-1);
  const closeBlocked = await call('POST', `${P(s2.code)}/periods/${lastMonth.slice(0, 7)}/close`, MGR);
  check('C8b: eslenmemis tahsilat varken ay kapatma 409 PERIOD_HAS_UNASSIGNED_PAYMENTS', closeBlocked.status === 409 && closeBlocked.body.code === 'PERIOD_HAS_UNASSIGNED_PAYMENTS' && closeBlocked.body.count >= 1, closeBlocked.body);
  const mapBody = { account_by_method: { cash: kasa2.body.account.id, transfer: banka2.body.account.id, cheque: banka2.body.account.id } };
  const prev = await call('POST', `${P(s2.code)}/accounts/assign-payments/preview`, MGR, mapBody);
  check('C8c: toplu esleme onizlemesi YAZMAZ: count 3, toplam 7000, yonteme gore kirilim, preview_hash', prev.status === 200 && prev.body.count === 3 && prev.body.total_minor === 7000 && prev.body.by_method.length === 3 && /^[0-9a-f]{64}$/.test(prev.body.preview_hash) && (await q(`SELECT COUNT(*)::int AS n FROM account_movements WHERE site_code = $1 AND kind = 'collection'`, [s2.code])).rows[0].n === 0, prev.body);
  const partial = await call('POST', `${P(s2.code)}/accounts/assign-payments/preview`, MGR, { account_by_method: { cash: kasa2.body.account.id } });
  check('C8d: yontemi hesapsiz birakilan tahsilatlar atlanir (no_account sayilir)', partial.body.count === 1 && partial.body.skipped.no_account === 2, partial.body);
  const stale = await call('POST', `${P(s2.code)}/accounts/assign-payments/commit`, MGR, { ...mapBody, expected_count: 3, expected_total_minor: 7000, expected_hash: 'a'.repeat(64), idempotency_key: key('ac') });
  check('C8e: onizleme ozeti uyusmazsa 409 PREVIEW_STALE (hicbir sey yazilmaz)', stale.status === 409 && stale.body.code === 'PREVIEW_STALE' && (await q(`SELECT COUNT(*)::int AS n FROM account_movements WHERE site_code = $1 AND kind = 'collection'`, [s2.code])).rows[0].n === 0, stale.body);
  const ackey = key('ac2');
  const commit = await call('POST', `${P(s2.code)}/accounts/assign-payments/commit`, MGR, { ...mapBody, expected_count: 3, expected_total_minor: 7000, expected_hash: prev.body.preview_hash, idempotency_key: ackey });
  const commit2 = await call('POST', `${P(s2.code)}/accounts/assign-payments/commit`, MGR, { ...mapBody, expected_count: 3, expected_total_minor: 7000, expected_hash: prev.body.preview_hash, idempotency_key: ackey });
  const list3 = await call('GET', `${P(s2.code)}/accounts`, MGR);
  const mapped = (await q(`SELECT m.movement_date::text AS d, l.entry_date::text AS e, m.account_id FROM account_movements m JOIN ledger_entries l ON l.id = m.ledger_entry_id WHERE m.site_code = $1 AND m.kind = 'collection'`, [s2.code])).rows;
  check('C8f: commit 201: 3 tahsilat esleme, hareket tarihi = tahsilat tarihi; eslenmemis 0; ayni anahtar tekrar 200 (cift hareket yok)', commit.status === 201 && commit.body.count === 3 && commit2.status === 200 && commit2.body.replayed === true && mapped.length === 3 && mapped.every((m) => m.d === m.e) && list3.body.unassigned_payments.count === 0, [commit.body, commit2.body, list3.body.unassigned_payments]);
  const closeOk = await call('POST', `${P(s2.code)}/periods/${lastMonth.slice(0, 7)}/close`, MGR);
  check('C8g: esleme sonrasi ay kapatilabilir (200)', closeOk.status === 200, closeOk.body);
  // kapali aydaki tahsilat artik eslenemez: yeni hesap + kapali ay tahsilati
  const pClosed = await call('POST', `${P(s2.code)}/payments`, MGR, { apartment_id: e4, amount_minor: 500, entry_date: ago(1), method: 'cash', idempotency_key: key('p4'), account_id: kasa2.body.account.id });
  check('C8h: normal akis: yeni tahsilat hesapla birlikte yazilir (hesap bakiyesi guncel)', pClosed.status === 201 && pClosed.body.movement_id > 0);

  // --- C9. degismezler (DB)
  const invariantsSql = `
    SELECT
      (SELECT COALESCE(SUM(balance), 0) FROM (SELECT account_id, SUM(amount_minor) AS balance FROM account_movements WHERE site_code = $1 GROUP BY account_id) b)::text AS sum_balances,
      (SELECT COALESCE(SUM(opening_balance_minor), 0) FROM finance_accounts WHERE site_code = $1)::text AS sum_openings,
      (SELECT COALESCE(SUM(amount_minor), 0) FROM account_movements WHERE site_code = $1 AND kind <> 'opening')::text AS sum_non_opening`;
  const inv = (await q(invariantsSql, [site.code])).rows[0];
  check('C9: DEGISMEZ: Σ hesap bakiyeleri = Σ acilis + Σ diger hareketler', BigInt(inv.sum_balances) === BigInt(inv.sum_openings) + BigInt(inv.sum_non_opening), inv);
  const collSum = (await q(`SELECT COALESCE(SUM(m.amount_minor), 0)::text AS s FROM account_movements m WHERE m.site_code = $1 AND m.kind IN ('collection') `, [site.code])).rows[0].s;
  const mirSum = (await q(`SELECT COALESCE(SUM(r.amount_minor), 0)::text AS s FROM account_movements r JOIN account_movements o ON o.id = r.reverses_movement_id WHERE r.site_code = $1 AND o.kind = 'collection'`, [site.code])).rows[0].s;
  const mappedPayments = (await q(`SELECT COALESCE(SUM(-l.amount_minor) FILTER (WHERE NOT EXISTS (SELECT 1 FROM ledger_entries rv WHERE rv.reverses_entry_id = l.id)), 0)::text AS s FROM ledger_entries l WHERE l.site_code = $1 AND l.kind = 'payment' AND EXISTS (SELECT 1 FROM account_movements m WHERE m.ledger_entry_id = l.id AND m.kind = 'collection')`, [site.code])).rows[0].s;
  check('C9b: DEGISMEZ: tahsilat hareketleri (ayna dahil net) = eslenmis ve ters kaydi olmayan odemelerin toplami', BigInt(collSum) + BigInt(mirSum) === BigInt(mappedPayments), { collSum, mirSum, mappedPayments });

  const movId = (await q(`SELECT id FROM account_movements WHERE site_code = $1 AND kind = 'collection' LIMIT 1`, [site.code])).rows[0].id;
  const dbChecks = [
    ['UPDATE', await failMessage(`UPDATE account_movements SET amount_minor = 1 WHERE id = $1`, [movId])],
    ['DELETE', await failMessage(`DELETE FROM account_movements WHERE id = $1`, [movId])],
    ['TRUNCATE', await failMessage(`TRUNCATE account_movements`)],
    ['hesap acilis bakiyesi', await failMessage(`UPDATE finance_accounts SET opening_balance_minor = 5 WHERE id = $1`, [kasaId])],
    ['hesap acilis tarihi', await failMessage(`UPDATE finance_accounts SET opening_date = opening_date - 1 WHERE id = $1`, [kasaId])],
    ['hesap tablosu TRUNCATE', await failMessage(`TRUNCATE finance_accounts CASCADE`)],
  ];
  check('C9c: hareket UPDATE / DELETE / TRUNCATE ve hesap acilis alanlari UPDATE tetikleyici hatasi verir', dbChecks.every(([, m]) => m !== null), dbChecks);
  const lid = (await q(`SELECT ledger_entry_id FROM account_movements WHERE id = $1`, [movId])).rows[0].ledger_entry_id;
  const dbInserts = [
    ['ayni odeme ikinci hesapta', await failCode(`INSERT INTO account_movements (site_code, account_id, kind, amount_minor, movement_date, period, ledger_entry_id) SELECT $1, id, 'collection', 1000, $3::date, $4::date, $2 FROM finance_accounts WHERE site_code = $1 LIMIT 1`, [site.code, lid, TODAY, monthStart(0)])],
    ['tutar uyusmayan tahsilat', await failCode(`INSERT INTO account_movements (site_code, account_id, kind, amount_minor, movement_date, period, ledger_entry_id) VALUES ($1, $2, 'collection', 1, $4::date, $5::date, $3)`, [site.code, kasaId, chargeReverse, TODAY, monthStart(0)])],
    ['hatali ayna (tutar)', await failCode(`INSERT INTO account_movements (site_code, account_id, kind, amount_minor, movement_date, period, reverses_movement_id) VALUES ($1, $2, 'reversal', 7, $3::date, $4::date, $5)`, [site.code, kasaId, TODAY, monthStart(0), movId])],
    ['ters kaydin tersi', await failCode(`INSERT INTO account_movements (site_code, account_id, kind, amount_minor, movement_date, period, reverses_movement_id) SELECT $1, account_id, 'reversal', -amount_minor, $2::date, $3::date, id FROM account_movements WHERE kind = 'reversal' AND site_code = $1 LIMIT 1`, [site.code, TODAY, monthStart(0)])],
    ['ikinci acilis hareketi', await failCode(`INSERT INTO account_movements (site_code, account_id, kind, amount_minor, movement_date, period) VALUES ($1, $2, 'opening', 5, $3::date, $4::date)`, [site.code, kasaId, TODAY, monthStart(0)])],
    ['isaret hatasi (gider pozitif)', await failCode(`INSERT INTO account_movements (site_code, account_id, kind, amount_minor, movement_date, period, expense_id) VALUES ($1, $2, 'expense', 5, $3::date, $4::date, 1)`, [site.code, kasaId, TODAY, monthStart(0)])],
    ['duzeltme nedensiz', await failCode(`INSERT INTO account_movements (site_code, account_id, kind, amount_minor, movement_date, period) VALUES ($1, $2, 'adjustment', 5, $3::date, $4::date)`, [site.code, kasaId, TODAY, monthStart(0)])],
    ['baska sitenin hesabi', await failCode(`INSERT INTO account_movements (site_code, account_id, kind, amount_minor, movement_date, period, reason_code) VALUES ($1, $2, 'adjustment', 5, $3::date, $4::date, 'other')`, [site.code, otherAcc.body.account.id, TODAY, monthStart(0)])],
    ['acilistan onceki tarih', await failCode(`INSERT INTO account_movements (site_code, account_id, kind, amount_minor, movement_date, period, reason_code) VALUES ($1, $2, 'adjustment', 5, $3::date, $4::date, 'other')`, [site.code, kasaId, ago(5), monthStart(0)])],
  ];
  check('C9d: hareket kisitlari / tetikleyicileri ihlalleri reddeder (cift esleme 23505, tutar uyusmazligi, ayna, ters kaydin tersi, ikinci acilis, isaret, neden, baska site, acilis tarihi)', dbInserts.every(([, c]) => c !== null), dbInserts);

  // --- C10. yetki matrisi
  const rows = [];
  for (const [label, user, read, writeExpect] of [['yonetici', MGR, 200, 201], ['kurul', BOARD, 200, 403], ['gorevli', STAFF, 403, 403], ['sakin', RESIDENT, 403, 403], ['ilgisiz', OUTSIDER, 403, 403]]) {
    const r = await call('GET', `${P(site.code)}/accounts`, user);
    const m = await call('GET', `${P(site.code)}/accounts/${kasaId}/movements`, user);
    const w = await acc({ name: `Yetki ${label}` }, user);
    const wStatus = w.status === 409 ? 201 : w.status;
    rows.push([label, r.status, m.status, wStatus, read, writeExpect]);
  }
  check('C10: yetki matrisi: yonetici yazar + okur; kurul YALNIZ okur; gorevli / sakin / ilgisiz 403', rows.every(([, r, m, w, er, ew]) => r === er && m === er && w === ew), rows);
}
