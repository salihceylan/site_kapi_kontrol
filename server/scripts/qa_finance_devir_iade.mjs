#!/usr/bin/env node
// Kiraci borcunun malike devri (migration 089) ve alacak iadesi (migration 088) icin GERCEK PostgreSQL dogrulamasi (servis katmani, HTTP'siz).
// `npm test` ICINDE DEGILDIR; elle / CI'da bilincli olarak, TEK KULLANIMLIK veritabaninda calistirilir:
//   QA_CONFIRM_DISPOSABLE_DB=yes DB_HOST=127.0.0.1 DB_PORT=55432 DB_NAME=qa_devir_iade DB_USER=postgres DB_PASSWORD=x \
//     node scripts/migrate.js --apply --yes && QA_CONFIRM_DISPOSABLE_DB=yes <ayni ortam> node scripts/qa_finance_devir_iade.mjs
// Kapsam:
//   D  devir: kalem bazli ters kayit + malik borcu (kismi odenmis kalem, tazminat istisnasi), iki hesabin toplami degismez, idempotans, bayat onizleme, NO_OWNER, geri alma
//      (eski bakiyeler, ters kayitla), cift geri alma, geri alma kaydinin tersi, devirden sonra malik odemesi -> geri alinamaz, genel "kaydi iptal et" ucu devir satirini reddeder
//   I  iade: talep (alacak siniri, bekleyen talepler, baska daire 404), onay (defter + hesap hareketi + makbuz IA-yil-sira + durum TEK islem), kasa degismezi
//      (Isletme + Fon + avans = hesaplar toplami), nakit yetersiz, ret (gerekce sakine gorunur), geri alma, iade varken odeme iptali engeli, cift onay yarisi, raporlarda tahakkuk degismez
// Her kontrol `check(ad, kosul, ayrinti)`; en sonda ozet ve cikis kodu (0 = hepsi gecti).

const SERVER = new URL('..', import.meta.url).href;
const load = (path) => import(new URL(path, SERVER).href);

if (process.env.QA_CONFIRM_DISPOSABLE_DB !== 'yes') {
  console.error('Bu betik TEK KULLANIMLIK veritabaninda calisir: QA_CONFIRM_DISPOSABLE_DB=yes verin.');
  process.exit(2);
}
process.env.JWT_SECRET ||= 'qa-secret-qa-secret-qa-secret-123456';

const { pool, ensureDbSchema } = await load('src/db.js');
await ensureDbSchema(); // migrate.js zinciri + sunucu acilisindaki ensure adimlari (sites.approved_at vb. dev blok) - gercek acilisla ayni
const { todayIso } = await load('src/modules/people_common.js');
const liability = await load('src/modules/finance_liability_service.js');
const refunds = await load('src/modules/finance_refunds.js');
const ledgerService = await load('src/modules/finance_ledger_service.js');
const accountsService = await load('src/modules/finance_accounts.js');
const fundsService = await load('src/modules/finance_funds_service.js');
const { allocateFunds, toAllocatorEntry } = await load('src/modules/finance_funds.js');
const { accountPartySql } = await load('src/modules/finance_parties.js');

let failures = 0;
let total = 0;
const check = (name, ok, detail = undefined) => {
  total += 1;
  if (!ok) failures += 1;
  console.log(`${ok ? 'OK   ' : 'HATA '} ${name}${ok || detail === undefined ? '' : ` -> ${JSON.stringify(detail, (_k, v) => (typeof v === 'bigint' ? String(v) : v))}`}`);
};
const q = (sql, params = []) => pool.query(sql, params);
const fails = async (fn) => {
  try {
    await fn();
    return null;
  } catch (error) {
    return { status: error.statusCode ?? null, code: error.code ?? null, message: error.message };
  }
};

const TODAY = todayIso();
const dayNo = (iso) => Date.UTC(Number(iso.slice(0, 4)), Number(iso.slice(5, 7)) - 1, Number(iso.slice(8, 10))) / 86400000;
const ago = (days) => new Date((dayNo(TODAY) - days) * 86400000).toISOString().slice(0, 10);
const periodOf = (iso) => `${iso.slice(0, 7)}-01`;
let keyCounter = 0;
const key = (label) => `qa-${label}-${(keyCounter += 1)}-${Date.now()}`;

// --- fabrikalar -----------------------------------------------------------------------------------------------------------------------
// Her kosu farkli kod araligi kullanir (yarida kalan kosu ayni veritabaninda tekrar calistirilabilsin)
const RUN = Math.floor(Date.now() / 1000) % 1_000_000;
let nextUser = 20000 + (RUN % 6000) * 10; // user_code 10000..99999 araliginda
const mkUser = async (name, role) => {
  nextUser += 1;
  await q(
    `INSERT INTO users (user_code, full_name, email, role, password_hash, is_active, email_verified, approval_status) VALUES ($1, $2, $3, $4, 'x', TRUE, TRUE, 'approved')`,
    [nextUser, name, `qa${nextUser}@qa.example`, role],
  );
  return { user_code: nextUser, userCode: nextUser, id: nextUser, role, full_name: name, email: `qa${nextUser}@qa.example` };
};
let nextSite = 1_100_000_000 + RUN * 100;
const mkSite = async (name, apartmentCount = 2) => {
  nextSite += 1;
  await q(`INSERT INTO sites (site_code, name, approval_status, approved_at) VALUES ($1, $2, 'approved', NOW())`, [nextSite, `${name} ${nextSite}`]);
  const block = Number((await q(`INSERT INTO site_blocks (site_code, block_name, sort_order) VALUES ($1, 'A Blok', 1) RETURNING id`, [nextSite])).rows[0].id);
  const ids = [];
  for (let n = 1; n <= apartmentCount; n += 1) {
    ids.push(Number((await q(`INSERT INTO apartments (site_code, block_id, unit_label, sort_order) VALUES ($1, $2, $3, $4) RETURNING id`, [nextSite, block, `Daire ${n}`, n])).rows[0].id));
  }
  return { code: nextSite, ids };
};
const addResident = async (site, apartmentId, relation, user, { moveIn = '2020-01-01' } = {}) => {
  const person = Number((await q(`INSERT INTO site_people (site_code, user_code) VALUES ($1, $2) RETURNING id`, [site.code, user.user_code])).rows[0].id);
  await q(
    `INSERT INTO apartment_residencies (site_code, apartment_id, person_id, relation, is_current, move_in_date, origin) VALUES ($1, $2, $3, $4, TRUE, $5, 'manual')`,
    [site.code, apartmentId, person, relation, moveIn],
  );
  return person;
};
const insertLedger = async (site, apartmentId, { kind = 'charge', amount, party = 'tenant', entryDate = TODAY, dueDate = entryDate, name = 'Aidat', fund = null, extraCols = '', extraVals = [] }) =>
  Number(
    (
      await q(
        `INSERT INTO ledger_entries (site_code, apartment_id, kind, amount_minor, period, entry_date, due_date, definition_name, payer_party, account_party, fund${extraCols})
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, 'both', $9, $10${extraVals.map((_, i) => `, $${11 + i}`).join('')}) RETURNING id`,
        [site.code, apartmentId, kind, amount, periodOf(entryDate), entryDate, dueDate, name, party, fund, ...extraVals],
      )
    ).rows[0].id,
  );
const balance = async (site, apartmentId, party) =>
  Number((await q(`SELECT COALESCE(SUM(l.amount_minor), 0)::TEXT AS s FROM ledger_entries l WHERE l.site_code = $1 AND l.apartment_id = $2 AND ${accountPartySql('l')} = $3`, [site.code, apartmentId, party])).rows[0].s);
const rowsOf = async (site, apartmentId, party) =>
  (
    await q(
      `SELECT l.id, l.kind, l.amount_minor::TEXT AS amount_minor, to_char(l.entry_date, 'YYYY-MM-DD') AS entry_date, to_char(l.due_date, 'YYYY-MM-DD') AS due_date, l.reverses_entry_id, l.fund,
              l.source_kind, l.late_fee_run_id, l.definition_id, fd.charge_party AS def_charge_party, fd.kind AS def_kind
       FROM ledger_entries l LEFT JOIN fee_definitions fd ON fd.id = l.definition_id WHERE l.site_code = $1 AND l.apartment_id = $2 AND ${accountPartySql('l')} = $3 ORDER BY l.id`,
      [site.code, apartmentId, party],
    )
  ).rows;
/** allocateFunds degismezi: acik borc - avans = hesap bakiyesi. */
const allocatorBalanced = async (site, apartmentId, party) => {
  const allocation = allocateFunds((await rowsOf(site, apartmentId, party)).map(toAllocatorEntry), { today: TODAY });
  const lhs = allocation.funds.operating.open + allocation.funds.capital.open - allocation.advanceTotal;
  return { ok: lhs === BigInt(await balance(site, apartmentId, party)), allocation };
};

const MANAGER = await mkUser('QA Yonetici', 'site_manager');

// =====================================================================================================================================
// D. DEVIR
// =====================================================================================================================================
console.log('--- D. kiraci borcunun malike devri (089) ---');
{
  const site = await mkSite('QA Devir Sitesi', 3);
  const [apt, aptNoOwner] = site.ids;
  const owner = await mkUser('QA Malik', 'apartment_owner');
  const tenant = await mkUser('QA Kiraci', 'apartment_owner');
  await addResident(site, apt, 'owner', owner);
  await addResident(site, apt, 'tenant', tenant);
  await addResident(site, aptNoOwner, 'tenant', await mkUser('QA Kiraci 2', 'apartment_owner'));

  // kiraci hesabi: 3 x 1000 borc (vade -60, -30, -5 gun), 1500 odeme -> kalan: 2. kalem 500, 3. kalem 1000 (toplam 1500)
  const c1 = await insertLedger(site, apt, { amount: 1000, entryDate: ago(70), dueDate: ago(60) });
  const c2 = await insertLedger(site, apt, { amount: 1000, entryDate: ago(40), dueDate: ago(30) });
  const c3 = await insertLedger(site, apt, { amount: 1000, entryDate: ago(10), dueDate: ago(5) });
  await insertLedger(site, apt, { kind: 'payment', amount: -1500, entryDate: ago(2), extraCols: ', method', extraVals: ['cash'] });
  // tazminat kalemi (devredilmez): late_fee_run_id icin sahte kosu satiri gerekir -> yalniz birim testlerinde; burada ek borc kalemi: vadesi GELECEK (devredilmez)
  await insertLedger(site, apt, { amount: 700, entryDate: TODAY, dueDate: ago(-20), name: 'Gelecek aidat' });
  const tenantBefore = await balance(site, apt, 'tenant');
  const ownerBefore = await balance(site, apt, 'owner');

  const preview = await liability.previewLiabilityTransfer(site.code, apt);
  check('D1: onizleme: vadesi gecmis ve odenmemis 2 kalem, toplam 1500 (kismi odenmis kalem 500; gelecek vadeli kalem dahil degil)', preview.item_count === 2 && preview.total_minor === 1500 && preview.items[0].remaining_minor === 500 && preview.items[0].paid_minor === 500 && preview.items[1].remaining_minor === 1000, preview);
  check('D1b: onizleme malik kaydini ve can_transfer bilgisini verir; yazmaz', preview.has_owner === true && preview.can_transfer === true && (await balance(site, apt, 'tenant')) === tenantBefore);

  const transferKey = key('devir');
  const body = { expected_total_minor: preview.total_minor, expected_hash: preview.preview_hash, reason: 'Kiraci tasindi, borc odenmedi', idempotency_key: transferKey };
  const out = await liability.createLiabilityTransfer({ siteCode: site.code, rawApartmentId: apt, body, actor: MANAGER });
  const tenantAfter = await balance(site, apt, 'tenant');
  const ownerAfter = await balance(site, apt, 'owner');
  check('D2: devir: kiraci hesabi tam devredilen tutar kadar duser, malik hesabi AYNI tutar kadar artar', tenantBefore - tenantAfter === 1500 && ownerAfter - ownerBefore === 1500, { tenantBefore, tenantAfter, ownerBefore, ownerAfter });
  check('D2b: iki hesabin toplami degismez', tenantBefore + ownerBefore === tenantAfter + ownerAfter);
  check('D2c: yanit bakiyeleri veritabaniyla ayni, kayit 201 (replayed=false)', out.replayed === false && out.tenant_balance_minor === tenantAfter && out.owner_balance_minor === ownerAfter && out.transfer.kind === 'transfer' && out.transfer.total_minor === 1500 && out.transfer.item_count === 2);

  const written = (await q(`SELECT l.id, l.kind, ${accountPartySql('l')} AS party, l.amount_minor::TEXT AS amount, l.reverses_entry_id, l.fund FROM ledger_entries l WHERE l.site_code = $1 AND l.source_kind = 'liability_transfer' AND l.source_id = $2 ORDER BY l.id`, [site.code, out.transfer.id])).rows;
  const sum = (rows, filter) => rows.filter(filter).reduce((s, r) => s + Number(r.amount), 0);
  check('D3: defter: kiraci tarafinda 2 ters kayit (-1000, -1000) + 1 yeni borc (odenmis 500); malik tarafinda 2 yeni borc (500 + 1000)',
    written.filter((r) => r.kind === 'reversal' && r.party === 'tenant').length === 2 && sum(written, (r) => r.kind === 'reversal') === -2000 && sum(written, (r) => r.kind === 'charge' && r.party === 'tenant') === 500 && sum(written, (r) => r.kind === 'charge' && r.party === 'owner') === 1500, written);
  check('D3b: asil kalemler (c2, c3) ters kayitli; c1 ve gelecek kalem dokunulmamis', written.some((r) => Number(r.reverses_entry_id) === c2) && written.some((r) => Number(r.reverses_entry_id) === c3) && !written.some((r) => Number(r.reverses_entry_id) === c1));
  check('D3c: malik borclari kiracinin kasasini (isletme) korur (fund yazili)', written.filter((r) => r.party === 'owner').every((r) => r.fund === 'operating'), written);
  const record = (await q(`SELECT total_minor::TEXT AS t, item_count, reason, created_by, from_party, to_party FROM finance_liability_transfers WHERE id = $1`, [out.transfer.id])).rows[0];
  check('D4: devir kaydi: kim / kac kalem / ne kadar / neden', Number(record.t) === 1500 && record.item_count === 2 && record.created_by === MANAGER.user_code && record.from_party === 'tenant' && record.to_party === 'owner' && /odenmedi/.test(record.reason), record);
  const audit = (await q(`SELECT details::TEXT AS d FROM audit_log WHERE action = 'finance.liability_transfer.created' AND target_id = $1`, [String(out.transfer.id)])).rows;
  check('D4b: denetim kaydi yazildi; neden metni YOK, tutar ve kalem sayisi VAR', audit.length === 1 && /1500/.test(audit[0].d) && !/odenmedi/.test(audit[0].d), audit);
  const alloc = await allocatorBalanced(site, apt, 'owner');
  const alloc2 = await allocatorBalanced(site, apt, 'tenant');
  check('D5: allocateFunds degismezi (acik borc - avans = bakiye) iki hesapta da korunur', alloc.ok && alloc2.ok);
  const notices = (await q(`SELECT COUNT(*)::INT AS n FROM apartment_notices WHERE apartment_id = $1 AND user_code = $2 AND kind = 'liability_transfer'`, [apt, owner.user_code])).rows[0].n;
  check('D5b: malike uygulama ici bildirim yazildi', notices === 1, notices);

  const replay = await liability.createLiabilityTransfer({ siteCode: site.code, rawApartmentId: apt, body, actor: MANAGER });
  check('D6: ayni anahtar = ayni kayit (replayed), yeni satir yok', replay.replayed === true && replay.transfer.id === out.transfer.id && (await balance(site, apt, 'owner')) === ownerAfter);
  const conflictKey = await fails(() => liability.createLiabilityTransfer({ siteCode: site.code, rawApartmentId: apt, body: { ...body, reason: 'baska neden' }, actor: MANAGER }));
  check('D6b: ayni anahtar + farkli govde 409 IDEMPOTENCY_CONFLICT', conflictKey?.status === 409 && conflictKey.code === 'IDEMPOTENCY_CONFLICT', conflictKey);
  const nothing = await fails(() => liability.createLiabilityTransfer({ siteCode: site.code, rawApartmentId: apt, body: { ...body, idempotency_key: key('ikinci') }, actor: MANAGER }));
  check('D6c: devirden sonra devredilecek kalem kalmadi -> 409 NOTHING_TO_TRANSFER', nothing?.status === 409 && nothing.code === 'NOTHING_TO_TRANSFER', nothing);

  const generic = await fails(() => ledgerService.reverseEntry({ siteCode: site.code, rawId: written.find((r) => r.kind === 'charge' && r.party === 'owner').id, body: { reason: 'elle iptal', idempotency_key: key('gen') }, actor: MANAGER }));
  check('D7: genel "kaydi iptal et" ucu devir satirini reddeder (ENTRY_MANAGED_BY_FLOW)', generic?.status === 409 && generic.code === 'ENTRY_MANAGED_BY_FLOW', generic);

  const history = await liability.listLiabilityTransfers(site.code, apt);
  check('D8: gecmis: devir listede, geri alinabilir', history.items.length === 1 && history.items[0].reversible === true && history.items[0].reversed_by_transfer_id === null, history);

  const rev = await liability.reverseLiabilityTransfer({ siteCode: site.code, rawId: out.transfer.id, body: { reason: 'yanlis devir', idempotency_key: key('geri') }, actor: MANAGER });
  const tenantRev = await balance(site, apt, 'tenant');
  const ownerRev = await balance(site, apt, 'owner');
  check('D9: geri alma: kiraci ve malik bakiyeleri devirden ONCEKI degerlere doner', tenantRev === tenantBefore && ownerRev === ownerBefore, { tenantRev, tenantBefore, ownerRev, ownerBefore });
  check('D9b: geri alma kaydi: kind=reversal, yonler yer degistirdi, ayni tutar; cift kayit kalir (satir sayisi arttı)', rev.transfer.kind === 'reversal' && rev.transfer.from_party === 'owner' && rev.transfer.to_party === 'tenant' && rev.transfer.total_minor === 1500);
  const ledgerCount = Number((await q(`SELECT COUNT(*)::INT AS n FROM ledger_entries WHERE site_code = $1 AND source_kind = 'liability_transfer'`, [site.code])).rows[0].n);
  check('D9c: devir ve geri alma satirlari defterde KALIR (silinmez): 5 + 5 satir', ledgerCount === 10, ledgerCount);
  const rev2 = await fails(() => liability.reverseLiabilityTransfer({ siteCode: site.code, rawId: out.transfer.id, body: { reason: 'tekrar', idempotency_key: key('geri2') }, actor: MANAGER }));
  check('D9d: cift geri alma 409 LIABILITY_TRANSFER_ALREADY_REVERSED', rev2?.status === 409 && rev2.code === 'LIABILITY_TRANSFER_ALREADY_REVERSED', rev2);
  const rev3 = await fails(() => liability.reverseLiabilityTransfer({ siteCode: site.code, rawId: rev.transfer.id, body: { reason: 'tersinin tersi', idempotency_key: key('geri3') }, actor: MANAGER }));
  check('D9e: geri alma kaydi tekrar geri alinamaz (409)', rev3?.status === 409 && rev3.code === 'LIABILITY_TRANSFER_NOT_REVERSIBLE', rev3);
  const alloc3 = await allocatorBalanced(site, apt, 'tenant');
  check('D9f: geri alma sonrasi allocateFunds degismezi', alloc3.ok);

  // yeniden devir (kalemler geri geldi) -> malik odemesi -> geri alinamaz
  const preview2 = await liability.previewLiabilityTransfer(site.code, apt);
  check('D10: geri almadan sonra onizleme ayni kalemleri verir (toplam 1500)', preview2.total_minor === 1500 && preview2.item_count === 2, preview2);
  const stale = await fails(() => liability.createLiabilityTransfer({ siteCode: site.code, rawApartmentId: apt, body: { expected_total_minor: 1500, expected_hash: 'f'.repeat(64), reason: 'x', idempotency_key: key('bayat') }, actor: MANAGER }));
  check('D10b: bayat onizleme ozeti 409 LIABILITY_TRANSFER_CHANGED', stale?.status === 409 && stale.code === 'LIABILITY_TRANSFER_CHANGED', stale);
  const out2 = await liability.createLiabilityTransfer({ siteCode: site.code, rawApartmentId: apt, body: { expected_total_minor: preview2.total_minor, expected_hash: preview2.preview_hash, reason: 'ikinci devir', idempotency_key: key('devir2') }, actor: MANAGER });
  await insertLedger(site, apt, { kind: 'payment', amount: -300, party: 'owner', entryDate: TODAY, extraCols: ', method', extraVals: ['cash'] });
  const blocked = await fails(() => liability.reverseLiabilityTransfer({ siteCode: site.code, rawId: out2.transfer.id, body: { reason: 'malik odemesi sonrasi', idempotency_key: key('geri4') }, actor: MANAGER }));
  check('D11: devirden sonra malik hesabina odeme girildiyse geri alma 409 LIABILITY_TRANSFER_OWNER_PAID', blocked?.status === 409 && blocked.code === 'LIABILITY_TRANSFER_OWNER_PAID', blocked);
  const history2 = await liability.listLiabilityTransfers(site.code, apt);
  check('D11b: gecmiste bu devir artik geri alinabilir degil (reversible=false)', history2.items.find((i) => i.id === out2.transfer.id)?.reversible === false, history2);

  const noOwner = await fails(() => liability.createLiabilityTransfer({ siteCode: site.code, rawApartmentId: aptNoOwner, body: { expected_total_minor: 100, expected_hash: 'a'.repeat(64), reason: 'x', idempotency_key: key('yok') }, actor: MANAGER }));
  check('D12: malik kaydi olmayan dairede 409 NO_OWNER', noOwner?.status === 409 && noOwner.code === 'NO_OWNER', noOwner);
  const other = await fails(() => liability.previewLiabilityTransfer(site.code + 999, apt));
  check('D12b: baska sitenin dairesi icin onizleme 404', other?.status === 404, other);
}

// =====================================================================================================================================
// I. IADE
// =====================================================================================================================================
console.log('--- I. alacak iadesi (088) ---');
{
  const site = await mkSite('QA Iade Sitesi', 3);
  const [apt, aptOther] = site.ids;
  const owner = await mkUser('QA Iade Malik', 'apartment_owner');
  const stranger = await mkUser('QA Iade Baskasi', 'apartment_owner');
  await addResident(site, apt, 'owner', owner);
  await addResident(site, aptOther, 'owner', stranger);

  const cash = (await accountsService.createAccount({ siteCode: site.code, body: { name: 'Kasa', kind: 'cash', opening_balance_minor: 100000, opening_date: ago(200), idempotency_key: key('acc1') }, actor: MANAGER })).account;
  const poor = (await accountsService.createAccount({ siteCode: site.code, body: { name: 'Bos Kasa', kind: 'cash', opening_balance_minor: 0, opening_date: ago(200), idempotency_key: key('acc2') }, actor: MANAGER })).account;
  const bank = (await accountsService.createAccount({ siteCode: site.code, body: { name: 'Banka', kind: 'bank', opening_balance_minor: 0, opening_date: ago(200), idempotency_key: key('acc3') }, actor: MANAGER })).account;

  await insertLedger(site, apt, { amount: 3000, party: 'owner', entryDate: ago(20), dueDate: ago(15) });
  const pay = await ledgerService.recordPayment({
    siteCode: site.code,
    body: { apartment_id: apt, amount_minor: 5000, entry_date: TODAY, method: 'cash', account_id: cash.id, account_party: 'owner', idempotency_key: key('pay') },
    actor: MANAGER,
  });
  const paymentId = pay.entry.id;
  check('I0: kurulum: 3000 borca 5000 odeme -> malik hesabi -2000 (alacak 2000)', (await balance(site, apt, 'owner')) === -2000);
  const fundsBefore = await fundsService.getFundSummary(site.code);
  check('I0b: kasa degismezi baslangicta tutuyor (Isletme + Fon + avans = hesaplar toplami)', fundsBefore.balanced === true && fundsBefore.advance_minor === 2000, fundsBefore);

  // --- talep
  const mkBody = (over = {}) => ({ apartment_id: apt, amount_minor: 1500, note: 'Iade istiyorum', idempotency_key: key('rq'), ...over });
  const tooMuch = await fails(() => refunds.createMyRefundRequest(owner, mkBody({ amount_minor: 2500 })));
  check('I1: alacaktan fazla tutar talep edilemez (409 REFUND_EXCEEDS_CREDIT)', tooMuch?.status === 409 && tooMuch.code === 'REFUND_EXCEEDS_CREDIT', tooMuch);
  const foreign = await fails(() => refunds.createMyRefundRequest(stranger, mkBody()));
  check('I1b: baska dairenin hesabi icin talep 404 (IDOR yok)', foreign?.status === 404, foreign);
  const wrongParty = await fails(() => refunds.createMyRefundRequest(owner, mkBody({ account_party: 'tenant' })));
  check('I1c: sakin kendi hesabi disindaki hesap icin talep acamaz (404)', wrongParty?.status === 404, wrongParty);
  const request = await refunds.createMyRefundRequest(owner, mkBody({ idempotency_key: 'qa-iade-talep-1' }));
  check('I2: sakin talep acti: status=requested, tutar 1500, makbuz yok, ledger degismedi', request.refund.status === 'requested' && request.refund.amount_minor === 1500 && request.refund.receipt === null && (await balance(site, apt, 'owner')) === -2000, request);
  const again = await refunds.createMyRefundRequest(owner, mkBody({ idempotency_key: 'qa-iade-talep-1' }));
  check('I2b: ayni anahtar = ayni talep (replayed)', again.replayed === true && again.refund.id === request.refund.id);
  const second = await fails(() => refunds.createMyRefundRequest(owner, mkBody({ amount_minor: 600 })));
  check('I2c: bekleyen talep dusulunce kalan alacak 500: 600 talep edilemez', second?.status === 409 && second.code === 'REFUND_EXCEEDS_CREDIT' && second.message.length > 0, second);
  const bad = await fails(() => refunds.createMyRefundRequest(owner, { apartment_id: apt, amount_minor: 0, idempotency_key: key('b') }));
  check('I2d: sifir / gecersiz tutar 400', bad?.status === 400, bad);

  // --- onay
  const notEnoughCash = await fails(() => refunds.approveRefund({ siteCode: site.code, rawId: request.refund.id, body: { pay_account_id: poor.id, idempotency_key: key('ap0') }, actor: MANAGER }));
  check('I3: nakit hesapta bakiye yetmiyorsa 409 CASH_INSUFFICIENT; hicbir satir yazilmadi', notEnoughCash?.status === 409 && notEnoughCash.code === 'CASH_INSUFFICIENT' && (await balance(site, apt, 'owner')) === -2000, notEnoughCash);
  const cashBefore = Number((await q(`SELECT COALESCE(SUM(amount_minor), 0)::TEXT AS s FROM account_movements WHERE account_id = $1`, [cash.id])).rows[0].s);
  const { computeIncomeExpense } = await load('src/modules/finance_reports.js');
  const ie0 = (await computeIncomeExpense(pool, site.code, [periodOf(TODAY)]))[0];
  const approveKey = key('ap1');
  const approved = await refunds.approveRefund({ siteCode: site.code, rawId: request.refund.id, body: { pay_account_id: cash.id, idempotency_key: approveKey }, actor: MANAGER });
  const cashAfter = Number((await q(`SELECT COALESCE(SUM(amount_minor), 0)::TEXT AS s FROM account_movements WHERE account_id = $1`, [cash.id])).rows[0].s);
  check('I4: onay: hesap bakiyesi (alacak) 1500 duser (-2000 -> -500)', (await balance(site, apt, 'owner')) === -500);
  check('I4b: onay: kasa hesabindan 1500 CIKIS hareketi (kind=refund, negatif)', cashBefore - cashAfter === 1500 && (await q(`SELECT COUNT(*)::INT AS n FROM account_movements WHERE kind = 'refund' AND refund_id = $1 AND amount_minor = -1500`, [request.refund.id])).rows[0].n === 1);
  check('I4c: onay: makbuz olustu (IA-yil-000001), snapshot tutar / hesap / tarih', /^IA-\d{4}-000001$/.test(approved.refund.receipt?.number ?? '') && approved.refund.receipt.snapshot.amount_minor === 1500 && approved.refund.receipt.snapshot.from_account.name === 'Kasa' && approved.refund.receipt.verification_code.length === 12 && approved.refund.receipt.status === 'active', approved.refund.receipt);
  check('I4d: onay: durum approved; defter satiri source_kind=refund, tur charge, kasa yok', approved.refund.status === 'approved' && (await q(`SELECT COUNT(*)::INT AS n FROM ledger_entries WHERE source_kind = 'refund' AND source_id = $1 AND kind = 'charge' AND amount_minor = 1500 AND fund IS NULL`, [request.refund.id])).rows[0].n === 1);
  const audit = (await q(`SELECT details::TEXT AS d FROM audit_log WHERE action = 'finance.refund.approved' AND target_id = $1`, [String(request.refund.id)])).rows;
  check('I4e: denetim kaydi (tutar / hesap / makbuz no); not metni YOK', audit.length === 1 && /1500/.test(audit[0].d) && /IA-/.test(audit[0].d) && !/istiyorum/.test(audit[0].d), audit);
  const fundsAfter = await fundsService.getFundSummary(site.code);
  check('I5: kasa degismezi iadeden sonra da tutar (fark 0); avans 2000 -> 500; kasalara tahsilat yazilmadi', fundsAfter.balanced === true && fundsAfter.advance_minor === 500 && fundsAfter.funds.operating.collections_minor === fundsBefore.funds.operating.collections_minor, fundsAfter);
  const allocOk = await allocatorBalanced(site, apt, 'owner');
  check('I5b: allocateFunds: odemenin dagilimi (operating 3000, refunded 1500, avans 500)', allocOk.ok && allocOk.allocation.payments.get(paymentId).operating === 3000n && allocOk.allocation.payments.get(paymentId).refunded === 1500n && allocOk.allocation.payments.get(paymentId).advance === 500n, allocOk.allocation.payments.get(paymentId));
  const replayApprove = await refunds.approveRefund({ siteCode: site.code, rawId: request.refund.id, body: { pay_account_id: cash.id, idempotency_key: approveKey }, actor: MANAGER });
  check('I6: ayni anahtarla tekrar onay = ayni kayit (replayed), ikinci cikis yok', replayApprove.replayed === true && (await q(`SELECT COUNT(*)::INT AS n FROM account_movements WHERE kind = 'refund' AND refund_id = $1`, [request.refund.id])).rows[0].n === 1);
  const approveAgain = await fails(() => refunds.approveRefund({ siteCode: site.code, rawId: request.refund.id, body: { pay_account_id: cash.id, idempotency_key: key('ap2') }, actor: MANAGER }));
  check('I6b: farkli anahtarla ikinci onay 409 REFUND_NOT_PENDING', approveAgain?.status === 409 && approveAgain.code === 'REFUND_NOT_PENDING', approveAgain);

  // --- raporlar: iade tahakkuk degildir, net tahsilati dusurur
  const ie1 = (await computeIncomeExpense(pool, site.code, [periodOf(TODAY)]))[0];
  check('I7: gelir-gider: iade tahakkuka (charged) EKLENMEZ; net tahsilat (collected) iade kadar (1500) duser', ie1.charged === ie0.charged && ie0.collected - ie1.collected === 1500n, { ie0, ie1 });
  const cashPosition = (await (await load('src/modules/finance_reports.js')).computeCashPosition(pool, site.code, TODAY)).accounts.find((a) => a.id === cash.id);
  check('I7b: kasa durumu: iade cikis (giderler) sutununda, bakiye denklemi tutar', cashPosition.opening_minor + cashPosition.collections_minor + cashPosition.expenses_minor + cashPosition.transfers_in_minor + cashPosition.transfers_out_minor + cashPosition.adjustments_minor + cashPosition.reversals_minor === cashPosition.balance_minor, cashPosition);

  // --- engeller
  const refundEntry = (await q(`SELECT id FROM ledger_entries WHERE source_kind = 'refund' AND source_id = $1 AND kind = 'charge'`, [request.refund.id])).rows[0].id;
  const generic = await fails(() => ledgerService.reverseEntry({ siteCode: site.code, rawId: refundEntry, body: { reason: 'elle iptal', idempotency_key: key('gen') }, actor: MANAGER }));
  check('I8: genel "kaydi iptal et" ucu iade satirini reddeder (ENTRY_MANAGED_BY_FLOW)', generic?.status === 409 && generic.code === 'ENTRY_MANAGED_BY_FLOW', generic);
  const payRev = await fails(() => ledgerService.reverseEntry({ siteCode: site.code, rawId: paymentId, body: { reason: 'odeme iptali', idempotency_key: key('payrev') }, actor: MANAGER }));
  check('I8b: onayli iade varken odemenin iptali engellenir (REFUND_BLOCKS_PAYMENT_CHANGE)', payRev?.status === 409 && payRev.code === 'REFUND_BLOCKS_PAYMENT_CHANGE', payRev);
  const payCorrect = await fails(() => ledgerService.correctPayment({ siteCode: site.code, rawId: paymentId, body: { amount_minor: 4000, entry_date: TODAY, method: 'cash', account_id: cash.id, idempotency_key: key('paycor') }, actor: MANAGER }));
  check('I8c: onayli iade varken odeme duzeltmesi de engellenir', payCorrect?.status === 409 && payCorrect.code === 'REFUND_BLOCKS_PAYMENT_CHANGE', payCorrect);

  // --- ret
  const req2 = await refunds.createManagerRefundRequest({ siteCode: site.code, body: { apartment_id: apt, account_party: 'owner', amount_minor: 400, note: 'Sakin sozlu istedi', idempotency_key: key('mrq') }, actor: MANAGER });
  const rejected = await refunds.rejectRefund({ siteCode: site.code, rawId: req2.refund.id, body: { reason: 'Odemeyi sonraki aidata mahsup edelim', idempotency_key: key('rj') }, actor: MANAGER });
  check('I9: ret: durum rejected, gerekce kayitli; ledger / hesap hareketi yok', rejected.refund.status === 'rejected' && rejected.refund.reject_reason.length > 0 && (await balance(site, apt, 'owner')) === -500);
  const noMovement = (await q(`SELECT COUNT(*)::INT AS n FROM account_movements WHERE refund_id = $1`, [req2.refund.id])).rows[0].n;
  check('I9b: reddedilen talepte hesap hareketi yok', noMovement === 0);
  const rejectedNotice = (await q(`SELECT message FROM apartment_notices WHERE apartment_id = $1 AND kind = 'refund' ORDER BY id DESC LIMIT 1`, [apt])).rows;
  check('I9c: sakine bildirim (manager acti -> hesabin kisisi malik)', rejectedNotice.length === 1);
  const residentList = await refunds.listMyRefundRequests(owner, {});
  check('I9d: sakinin listesi yalniz kendi talebini gosterir; manager talebi (baska acan) YOK; yonetici adi YOK', residentList.items.length === 1 && residentList.items[0].id === request.refund.id && !('requested_by_name' in residentList.items[0]), residentList);
  const approveRejected = await fails(() => refunds.approveRefund({ siteCode: site.code, rawId: req2.refund.id, body: { pay_account_id: cash.id, idempotency_key: key('ap3') }, actor: MANAGER }));
  check('I9e: reddedilmis talep onaylanamaz (409)', approveRejected?.status === 409 && approveRejected.code === 'REFUND_NOT_PENDING', approveRejected);

  // --- vazgecme
  const req3 = await refunds.createMyRefundRequest(owner, mkBody({ amount_minor: 200, idempotency_key: key('rq3') }));
  const cancelled = await refunds.cancelMyRefundRequest(owner, req3.refund.id);
  check('I10: sakin bekleyen talebi geri cekti (cancelled); baskasi geri ceken 404', cancelled.refund.status === 'cancelled' && (await fails(() => refunds.cancelMyRefundRequest(stranger, req3.refund.id)))?.status === 404);

  // --- eszamanli cift onay
  const req4 = await refunds.createManagerRefundRequest({ siteCode: site.code, body: { apartment_id: apt, account_party: 'owner', amount_minor: 300, idempotency_key: key('mrq4') }, actor: MANAGER });
  const racers = await Promise.allSettled([
    refunds.approveRefund({ siteCode: site.code, rawId: req4.refund.id, body: { pay_account_id: bank.id, idempotency_key: key('race1') }, actor: MANAGER }),
    refunds.approveRefund({ siteCode: site.code, rawId: req4.refund.id, body: { pay_account_id: cash.id, idempotency_key: key('race2') }, actor: MANAGER }),
  ]);
  const wins = racers.filter((r) => r.status === 'fulfilled').length;
  const losses = racers.filter((r) => r.status === 'rejected' && r.reason?.code === 'REFUND_NOT_PENDING').length;
  check('I11: eszamanli cift onay: tam biri gecer, digeri 409 REFUND_NOT_PENDING; tek hareket', wins === 1 && losses === 1 && (await q(`SELECT COUNT(*)::INT AS n FROM account_movements WHERE kind = 'refund' AND refund_id = $1`, [req4.refund.id])).rows[0].n === 1, racers.map((r) => r.status));
  check('I11b: sonrasinda alacak 500 - 300 = 200', (await balance(site, apt, 'owner')) === -200);

  // --- geri alma
  const cashBeforeRev = Number((await q(`SELECT COALESCE(SUM(amount_minor), 0)::TEXT AS s FROM account_movements WHERE account_id = $1`, [cash.id])).rows[0].s);
  const reversed = await refunds.reverseRefund({ siteCode: site.code, rawId: request.refund.id, body: { reason: 'Yanlis onay', idempotency_key: key('rv') }, actor: MANAGER });
  const cashAfterRev = Number((await q(`SELECT COALESCE(SUM(amount_minor), 0)::TEXT AS s FROM account_movements WHERE account_id = $1`, [cash.id])).rows[0].s);
  check('I12: geri alma: durum reversed, alacak 1500 geri geldi, kasa hesabi 1500 geri girdi, makbuz iptal', reversed.refund.status === 'reversed' && (await balance(site, apt, 'owner')) === -200 - 1500 && cashAfterRev - cashBeforeRev === 1500 && reversed.refund.receipt.status === 'cancelled', { reversed: reversed.refund.status, bal: await balance(site, apt, 'owner'), delta: cashAfterRev - cashBeforeRev });
  const fundsRev = await fundsService.getFundSummary(site.code);
  check('I12b: geri alma sonrasi kasa degismezi tutar', fundsRev.balanced === true, fundsRev);
  const reverseTwice = await fails(() => refunds.reverseRefund({ siteCode: site.code, rawId: request.refund.id, body: { reason: 'tekrar', idempotency_key: key('rv2') }, actor: MANAGER }));
  check('I12c: ikinci geri alma 409 REFUND_NOT_APPROVED', reverseTwice?.status === 409 && reverseTwice.code === 'REFUND_NOT_APPROVED', reverseTwice);
  const allocRev = await allocatorBalanced(site, apt, 'owner');
  check('I12d: geri alma sonrasi allocateFunds degismezi', allocRev.ok);
  check('I12e: yetim satir yok: reddedilen / geri alinan iadelerin defter satirlari cift kayit (iade + ters) olarak durur', Number((await q(`SELECT COUNT(*)::INT AS n FROM ledger_entries WHERE source_kind = 'refund' AND source_id = $1`, [request.refund.id])).rows[0].n) === 2);

  // --- veritabani korumalari
  const direct = await fails(() => q(`UPDATE finance_refunds SET amount_minor = 1 WHERE id = $1`, [request.refund.id]));
  check('I13: finance_refunds tutari dogrudan degistirilemez (tetikleyici)', direct !== null, direct);
  const del = await fails(() => q(`DELETE FROM finance_refunds WHERE id = $1`, [request.refund.id]));
  check('I13b: finance_refunds satiri silinemez', del !== null, del);
  const forged = await fails(() =>
    q(`INSERT INTO account_movements (site_code, account_id, kind, amount_minor, movement_date, period, refund_id) VALUES ($1, $2, 'refund', -999, $3, $4, $5)`, [site.code, cash.id, TODAY, periodOf(TODAY), request.refund.id]),
  );
  check('I13c: durumu requested olmayan iadeye hesap hareketi yazilamaz (tetikleyici)', forged !== null, forged);
  const cashBank = await refunds.createManagerRefundRequest({ siteCode: site.code, body: { apartment_id: apt, account_party: 'owner', amount_minor: 100, idempotency_key: key('mrq5') }, actor: MANAGER });
  const viaBank = await refunds.approveRefund({ siteCode: site.code, rawId: cashBank.refund.id, body: { pay_account_id: bank.id, idempotency_key: key('ap5') }, actor: MANAGER });
  check('I14: banka hesabindan iade (yontem havale), hesap bakiyesi eksiye dusebilir', viaBank.refund.pay_method === 'transfer' && viaBank.refund.receipt.snapshot.method === 'transfer' && /^IA-\d{4}-000003$/.test(viaBank.refund.receipt.number), viaBank.refund); // sira: 000001 ilk onay, 000002 yarisin kazanani, 000003 bu iade (kaybeden islem sayac almadi: bosluk yok)
}

console.log(`\n${total - failures}/${total} kontrol gecti${failures ? `, ${failures} HATA` : ''}`);
await pool.end();
process.exit(failures ? 1 : 0);
