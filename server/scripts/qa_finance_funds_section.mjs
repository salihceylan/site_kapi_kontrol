// Iki kasa (Isletme `operating` / Yatirim ve Demirbas Fon `capital`; migration 080) icin GERCEK PostgreSQL bolumu (docs/PLATFORM_FINANS_KASALAR.md).
// scripts/qa_finance4b.mjs ortamini kullanir (t: gercek authRequired + gercek JWT, ayri HTTP kapisi, fabrikalar). qa_platform_pg.mjs "funds" bolumu calistirir:
//   QA_CONFIRM_DISPOSABLE_DB=yes QA_ONLY=chain,live,funds DB_HOST=127.0.0.1 DB_PORT=... DB_USER=postgres node scripts/qa_platform_pg.mjs
// Kapsam:
//   K0  sema: sutunlar + CHECK, ters kayit kasa tetikleyicisi, finance_fund_transfers kisitlari + degismezlik (UPDATE / DELETE / TRUNCATE) + ayna tetikleyicisi,
//       site silinince CASCADE, ensure idempotans (yalniz 2 SELECT), sistem kategorisi veri adimi (kategorisi olan siteye eklenir, bos siteye eklenmez)
//   K1  tanim API: fund <-> charge_party (cakisma 400), PATCH, liste, ek borc varsayilani
//   K2  borclandirma kasayi yazar (aylik tanim, ek borc)
//   K3  tahsilat dagitimi (en eski vade onde, kasa kisiti, avans), idempotans, ters kayit / duzeltme kasayi korur
//   K4  ekstre kasa kirilimi (Entry.fund, fund_split, funds) ve sakin /app/my-finance funds
//   K5  gider / kategori kasasi (sistem kategorisi, kasa kilidi, eski giderde turetme)
//   K6  kasa ozeti + dokum + aktarim; DEGISMEZ: Isletme + Fon + avans = hesaplarin toplami (+ donem suzgeci, ters aktarim, iptal edilen gider / tahsilat)
//   K7  yetki matrisi + IDOR + dogrulama
//   K8  gecikme tazminati kasasi (agirlikli kasa) ve iptalinde kasa kopyasi
//   K9  eszamanli aktarim (tekil anahtar, cift ters) ve karisik yazma turu (40P01 = 0)
//   K10 makbuz anlik goruntusunde fund_split
//   K12 Fon tahakkukunun dayanagi (090; docs/PLATFORM_FINANS_KARAR_BAGI.md): Karar Defteri ACIK sitede kesin karar, KAPALI sitede gerekce zorunlu (400 / 404 / 409 yollari, idempotans,
//       FK / CHECK / append-only, ekstre ve sakin kalem dokumu, denetimde metin yok, karar bagli calistirmasi olan site silme)
// NOT: dosya ASCII Turkce kullanir; para hesabi tamsayi kurus (BigInt), kayan nokta yok.

export default async function sectionFunds(t) {
  const { check, same, q, call, pool, hooks, ctx, TODAY, ago, ym, dayOf, monthStart, mkUser, mkManaged, addPerson, P, key, users, failCode, failMessage } = t;
  const { SUPER, MGR, MGR2, BOARD, STAFF, OUTSIDER, RESIDENT } = users;
  const { CAPITAL_CATEGORY_NAME, allocateFunds, toAllocatorEntry } = await import('../src/modules/finance_funds.js');
  const { ensureFinanceFundsSchema, financeFundsMigrationSql } = await import('../src/modules/finance_funds_schema.js');
  const deadlocksAtStart = hooks.deadlocks;
  console.log('--- K. iki kasa (Isletme / Yatirim ve Demirbas Fon, 080) ---');

  // --- yardimcilar
  const setResponsible = (aptId, party) => q(`UPDATE apartments SET responsible_party = $2 WHERE id = $1`, [aptId, party]);
  const resident = async (site, aptId, relation, label, { moveIn = '2020-01-01' } = {}) => {
    const user = await mkUser(label, 'apartment_owner');
    const person = await addPerson(site.code, { user });
    await q(
      `INSERT INTO apartment_residencies (site_code, apartment_id, person_id, relation, is_current, move_in_date, origin) VALUES ($1, $2, $3, $4, TRUE, $5, 'manual')`,
      [site.code, aptId, person, relation, moveIn],
    );
    return { user, person };
  };
  const createDefinition = (site, body) => call('POST', `${P(site.code)}/definitions`, MGR, { kind: 'recurring', distribution: 'fixed', due_day: 1, target: { type: 'site' }, ...body });
  const postDefinition = async (site, definitionId, period) => {
    const pv = await call('POST', `${P(site.code)}/definitions/${definitionId}/preview`, MGR, { period });
    const post = await call('POST', `${P(site.code)}/definitions/${definitionId}/post`, MGR, { period, expected_total_minor: pv.body.total_minor, expected_apartment_count: pv.body.apartment_count, expected_hash: pv.body.preview_hash });
    if (post.status !== 201) throw new Error(`borclandirma basarisiz: ${JSON.stringify(post.body)}`);
    return post;
  };
  const postCharge = async (site, body) => {
    const pv = await call('POST', `${P(site.code)}/charges/preview`, MGR, body);
    const post = await call('POST', `${P(site.code)}/charges`, MGR, { ...body, expected_total_minor: pv.body.total_minor, expected_apartment_count: pv.body.apartment_count, expected_hash: pv.body.preview_hash, idempotency_key: key('ek') });
    return { pv, post };
  };
  const payment = (site, aptId, amount, extra = {}) =>
    call('POST', `${P(site.code)}/payments`, MGR, { apartment_id: aptId, amount_minor: amount, entry_date: TODAY, method: 'cash', idempotency_key: key('kp'), ...extra });
  const funds = (site, query = '', user = MGR) => call('GET', `${P(site.code)}/funds${query}`, user);
  const movements = (site, fund, query = '', user = MGR) => call('GET', `${P(site.code)}/funds/${fund}/movements${query}`, user);
  const account = (site, aptId, query = '', user = MGR) => call('GET', `${P(site.code)}/apartments/${aptId}/account${query}`, user);
  const categories = async (site) => (await call('GET', `${P(site.code)}/expense-categories`, MGR)).body.items;
  const categoryOf = async (site, name) => (await categories(site)).find((c) => c.name === name);
  const ACC = `COALESCE(l.account_party, CASE WHEN l.payer_party = 'tenant' THEN 'tenant' ELSE 'owner' END)`;
  const rowsOf = async (site, aptId, party) =>
    (
      await q(
        `SELECT l.id, l.kind, l.amount_minor::TEXT AS amount_minor, to_char(l.entry_date, 'YYYY-MM-DD') AS entry_date, to_char(l.due_date, 'YYYY-MM-DD') AS due_date, l.reverses_entry_id, l.fund,
                l.source_kind, l.late_fee_run_id, l.definition_id, fd.charge_party AS def_charge_party, fd.kind AS def_kind
         FROM ledger_entries l LEFT JOIN fee_definitions fd ON fd.id = l.definition_id
         WHERE l.site_code = $1 AND l.apartment_id = $2 AND ${ACC} = $3 ORDER BY l.id`,
        [site.code, aptId, party],
      )
    ).rows;
  const oracle = async (site, aptId, party) => allocateFunds((await rowsOf(site, aptId, party)).map(toAllocatorEntry), { today: TODAY });
  const sqlBalance = async (site, aptId, party) => Number((await q(`SELECT COALESCE(SUM(l.amount_minor), 0)::TEXT AS s FROM ledger_entries l WHERE l.site_code = $1 AND l.apartment_id = $2 AND ${ACC} = $3`, [site.code, aptId, party])).rows[0].s);
  const insertLedger = (site, aptId, { kind = 'charge', amount, fund = null, reverses = null, party = 'owner', entryDate = TODAY, dueDate = TODAY, extraCols = '', extraVals = [] }) =>
    q(
      `INSERT INTO ledger_entries (site_code, apartment_id, kind, amount_minor, period, entry_date, due_date, payer_party, account_party, fund, reverses_entry_id${extraCols})
       VALUES ($1, $2, $3, $4, $5, $6, $7, 'both', $8, $9, $10${extraVals.map((_, i) => `, $${11 + i}`).join('')}) RETURNING id`,
      [site.code, aptId, kind, amount, monthStart(0), entryDate, dueDate, party, fund, reverses, ...extraVals],
    ).then((r) => Number(r.rows[0].id));
  const fundOfRow = async (id) => (await q(`SELECT fund FROM ledger_entries WHERE id = $1`, [id])).rows[0].fund;
  const fillFp = 'a'.repeat(64);
  const sameSplit = (a, b) => a && b && a.operating_minor === b.operating_minor && a.capital_minor === b.capital_minor && a.advance_minor === b.advance_minor;

  // ============================================================================================================
  // K0. sema, degismezlik, ensure idempotans
  // ============================================================================================================
  {
    const cols = (await q(`SELECT table_name, is_nullable, column_default FROM information_schema.columns WHERE table_schema = 'public' AND column_name = 'fund' AND table_name IN ('ledger_entries', 'expense_categories', 'expenses') ORDER BY table_name`)).rows;
    check(
      'K0a: fund sutunlari: ledger_entries NULL olabilir (varsayilansiz), expenses NULL olabilir, expense_categories NOT NULL DEFAULT operating',
      same(cols.map((r) => [r.table_name, r.is_nullable]), [['expense_categories', 'NO'], ['expenses', 'YES'], ['ledger_entries', 'YES']]) && /operating/.test(cols[0].column_default) && cols[2].column_default === null,
      cols,
    );
    const cons = (await q(`SELECT conname, convalidated, pg_get_constraintdef(oid) AS def FROM pg_constraint WHERE conname IN ('chk_ledger_entries_fund', 'chk_expense_categories_fund', 'chk_expenses_fund') ORDER BY conname`)).rows;
    check('K0b: uc CHECK kisiti var ve DOGRULANMIS (NOT VALID -> VALIDATE)', cons.length === 3 && cons.every((c) => c.convalidated === true), cons);

    const S0 = await mkManaged('K Sema Sitesi', { 'S Blok': 2 });
    const [a1] = S0.ids;
    check('K0c: ledger_entries.fund CHECK: gecersiz kasa reddedilir (23514)', (await failCode(`INSERT INTO ledger_entries (site_code, apartment_id, kind, amount_minor, period, entry_date, due_date, payer_party, fund) VALUES ($1, $2, 'charge', 100, $3, $4, $4, 'both', 'fon')`, [S0.code, a1, monthStart(0), TODAY])) === '23514');
    check('K0d: expense_categories.fund CHECK: gecersiz kasa reddedilir (23514)', (await failCode(`INSERT INTO expense_categories (site_code, name, fund) VALUES ($1, 'K Gecersiz', 'fon')`, [S0.code])) === '23514');

    // ters kayit kasa tetikleyicisi
    const cCap = await insertLedger(S0, a1, { amount: 1000, fund: 'capital' });
    const rCap = await insertLedger(S0, a1, { kind: 'reversal', amount: -1000, reverses: cCap });
    check('K0e: ters kayit kasasi bos ise ASILIN kasasi doldurulur (capital)', (await fundOfRow(rCap)) === 'capital');
    const cLegacy = await insertLedger(S0, a1, { amount: 2000, fund: null });
    const rLegacy = await insertLedger(S0, a1, { kind: 'reversal', amount: -2000, reverses: cLegacy });
    check('K0f: asilda kasa YOKSA (080 oncesi) ters kayitta da NULL kalir (geri doldurma yok)', (await fundOfRow(rLegacy)) === null);
    const cOp = await insertLedger(S0, a1, { amount: 3000, fund: 'capital' });
    const mismatch = await failMessage(`INSERT INTO ledger_entries (site_code, apartment_id, kind, amount_minor, period, entry_date, due_date, payer_party, account_party, fund, reverses_entry_id) VALUES ($1, $2, 'reversal', -3000, $3, $4, $4, 'both', 'owner', 'operating', $5)`, [S0.code, a1, monthStart(0), TODAY, cOp]);
    check('K0g: ters kayit asilin kasasindan FARKLI ise reddedilir (P0001 "must keep the fund")', /P0001:.*finance reversal must keep the fund of its original entry/.test(mismatch ?? ''), mismatch);
    const pRes = await insertLedger(S0, a1, { kind: 'payment', amount: -500, fund: 'capital', extraCols: ', method', extraVals: ['cash'] });
    const pRev = await insertLedger(S0, a1, { kind: 'reversal', amount: 500, reverses: pRes });
    check('K0h: kisitli tahsilatin ters kaydi kisiti tasir (capital)', (await fundOfRow(pRev)) === 'capital');

    // finance_fund_transfers
    const ins = (over = {}) => {
      const v = { from: 'operating', to: 'capital', amount: 500, date: TODAY, period: monthStart(0), keyName: key('ft'), fp: fillFp, reverses: null, reason: null, ...over };
      return q(
        `INSERT INTO finance_fund_transfers (site_code, from_fund, to_fund, amount_minor, transfer_date, period, idempotency_key, request_fingerprint, reverses_transfer_id, reversal_reason) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10) RETURNING id`,
        [S0.code, v.from, v.to, v.amount, v.date, v.period, v.keyName, v.fp, v.reverses, v.reason],
      ).then((r) => Number(r.rows[0].id));
    };
    const tOk = await ins();
    check('K0i: gecerli aktarim yazilir', tOk > 0);
    const bad = [
      ['ayni kasalar', { from: 'capital', to: 'capital' }],
      ['gecersiz kasa', { to: 'fon' }],
      ['tutar 0', { amount: 0 }],
      ['tutar > 1e12', { amount: 1000000000001 }],
      ['donem ayin 1i degil', { period: dayOf(0, 15) }],
      ['anahtar 65 karakter', { keyName: 'k'.repeat(65) }],
      ['parmak izi 63 karakter', { fp: 'a'.repeat(63) }],
      ['neden yalniz ters satirda', { reason: 'neden' }],
    ];
    const badCodes = [];
    for (const [label, over] of bad) badCodes.push([label, await ins(over).then(() => 'KABUL', (e) => e.code)]);
    check('K0j: aktarim CHECK kisitlari (ayni kasa, gecersiz kasa, tutar, donem, anahtar, parmak izi, neden) 23514', badCodes.every(([, code]) => code === '23514'), badCodes);
    check('K0k: ayni (site, anahtar) ikinci kez 23505', (await failCode(`INSERT INTO finance_fund_transfers (site_code, from_fund, to_fund, amount_minor, transfer_date, period, idempotency_key, request_fingerprint) SELECT site_code, from_fund, to_fund, amount_minor, transfer_date, period, idempotency_key, request_fingerprint FROM finance_fund_transfers WHERE id = $1`, [tOk])) === '23505');
    const updateMsg = await failMessage(`UPDATE finance_fund_transfers SET amount_minor = 1 WHERE id = $1`, [tOk]);
    const deleteMsg = await failMessage(`DELETE FROM finance_fund_transfers WHERE id = $1`, [tOk]);
    const truncateMsg = await failMessage(`TRUNCATE finance_fund_transfers`);
    check('K0l: aktarim DEGISMEZ: UPDATE / DELETE "finance records are append-only", TRUNCATE engelli', /append-only/.test(updateMsg ?? '') && /append-only/.test(deleteMsg ?? '') && /append-only/.test(truncateMsg ?? ''), { updateMsg, deleteMsg, truncateMsg });
    const rev = await ins({ from: 'capital', to: 'operating', reverses: tOk, reason: 'ters', keyName: key('ftr') });
    check('K0n: ters aktarim (yonler yer degistirir, ayni tutar) yazilir', rev > 0);
    const mirrorBad = await failMessage(`INSERT INTO finance_fund_transfers (site_code, from_fund, to_fund, amount_minor, transfer_date, period, idempotency_key, request_fingerprint, reverses_transfer_id, reversal_reason) VALUES ($1, 'capital', 'operating', 400, $2, $3, $4, $5, $6, 'x')`, [S0.code, TODAY, monthStart(0), key('ftx'), fillFp, tOk]);
    check('K0o: ters aktarim tutari / yonu asila uymazsa reddedilir (mirror)', /must mirror/.test(mirrorBad ?? ''), mirrorBad);
    const twice = await failCode(`INSERT INTO finance_fund_transfers (site_code, from_fund, to_fund, amount_minor, transfer_date, period, idempotency_key, request_fingerprint, reverses_transfer_id, reversal_reason) VALUES ($1, 'capital', 'operating', 500, $2, $3, $4, $5, $6, 'x')`, [S0.code, TODAY, monthStart(0), key('fty'), fillFp, tOk]);
    check('K0p: bir aktarimin tek ters aktarimi olur (23505)', twice === '23505', twice);
    const revOfRev = await failMessage(`INSERT INTO finance_fund_transfers (site_code, from_fund, to_fund, amount_minor, transfer_date, period, idempotency_key, request_fingerprint, reverses_transfer_id, reversal_reason) VALUES ($1, 'operating', 'capital', 500, $2, $3, $4, $5, $6, 'x')`, [S0.code, TODAY, monthStart(0), key('ftz'), fillFp, rev]);
    check('K0q: ters aktarimin tersi yazilamaz (mirror)', /must mirror/.test(revOfRev ?? ''), revOfRev);
    const otherSite = await mkManaged('K Sema Sitesi 2', { 'S Blok': 1 });
    const foreign = await failMessage(`INSERT INTO finance_fund_transfers (site_code, from_fund, to_fund, amount_minor, transfer_date, period, idempotency_key, request_fingerprint, reverses_transfer_id, reversal_reason) VALUES ($1, 'capital', 'operating', 500, $2, $3, $4, $5, $6, 'x')`, [otherSite.code, TODAY, monthStart(0), key('ftw'), fillFp, tOk]);
    check('K0r: baska sitenin aktarimi ters cevrilemez (mirror: site)', /must mirror/.test(foreign ?? ''), foreign);

    // site silme CASCADE
    const del = await mkManaged('K Silinecek Site', { 'S Blok': 1 });
    await q(`INSERT INTO finance_fund_transfers (site_code, from_fund, to_fund, amount_minor, transfer_date, period, idempotency_key, request_fingerprint) VALUES ($1, 'operating', 'capital', 1, $2, $3, 'del-1', $4)`, [del.code, TODAY, monthStart(0), fillFp]);
    const siteDel = await failCode(`DELETE FROM sites WHERE site_code = $1`, [del.code]);
    const left = (await q(`SELECT COUNT(*)::INT AS n FROM finance_fund_transfers WHERE site_code = $1`, [del.code])).rows[0].n;
    check('K0s: SITE SILININCE aktarimlar CASCADE ile silinir (degismezlik tetikleyicisi "site artik yok" istisnasi)', siteDel === null && left === 0, { siteDel, left });

    // ensure idempotans: yalniz katalog SELECT'leri
    const recorded = [];
    const client = await pool.connect();
    const original = client.query.bind(client);
    client.query = (text, ...rest) => {
      recorded.push(typeof text === 'string' ? text : text?.text);
      return original(text, ...rest);
    };
    await ensureFinanceFundsSchema(client);
    client.query = original;
    client.release();
    check('K0t: ensureFinanceFundsSchema ikinci calistirmada YALNIZ 2 SELECT (katalog + veri adimi var-mi); DDL / kilit yok', recorded.length === 2 && recorded.every((s) => /^SELECT/.test(s)), recorded.map((s) => s.slice(0, 40)));

    // 080 dosyasi elle (psql gibi) iki kez calistirilinca hata vermez, veri degismez
    const sqlFile = financeFundsMigrationSql();
    const before = Number((await q(`SELECT COUNT(*) AS n FROM expense_categories`)).rows[0].n);
    await pool.query(sqlFile);
    await pool.query(sqlFile);
    const after = Number((await q(`SELECT COUNT(*) AS n FROM expense_categories`)).rows[0].n);
    check('K0u: migration 080 govdesi elle iki kez calistirilir: hata yok, kategori sayisi degismez (zaten var)', before === after, { before, after });

    // sistem kategorisi veri adimi: kategorisi olan siteye eklenir; kategorisi hic olmayan siteye EKLENMEZ
    const withCats = await mkManaged('K Kategorili Site', { 'K Blok': 1 });
    const noCats = await mkManaged('K Kategorisiz Site', { 'K Blok': 1 });
    await categories(withCats);
    const capitalsOf = async (site) => (await q(`SELECT name, is_system, fund FROM expense_categories WHERE site_code = $1 AND is_system AND fund = 'capital'`, [site.code])).rows;
    check('K0v: ilk kullanimda varsayilan kume 13 kategori ve 1 sistem kategorisi "Yatirim ve demirbas" (capital)', (await categories(withCats)).length === 13 && same((await capitalsOf(withCats)).map((c) => c.name), [CAPITAL_CATEGORY_NAME]));
    await q(`DELETE FROM expense_categories WHERE site_code = $1 AND is_system AND fund = 'capital'`, [withCats.code]);
    const ensureClient = await pool.connect();
    const applied = await ensureFinanceFundsSchema(ensureClient);
    ensureClient.release();
    const noCatRows = Number((await q(`SELECT COUNT(*) AS n FROM expense_categories WHERE site_code = $1`, [noCats.code])).rows[0].n);
    check('K0w: ensure veri adimi: kategorisi OLAN siteye sistem kategorisi geri eklenir (tek adim), kategorisi HIC olmayan siteye eklenmez (varsayilan kume bozulmaz)', same(applied, ['data:capital_category']) && (await capitalsOf(withCats)).length === 1 && noCatRows === 0, { applied, noCatRows });
    // yeniden adlandirma: yeniden eklemeyi tetiklemez; liste ucu eksikse tamamlar
    const sysCat = await categoryOf(withCats, CAPITAL_CATEGORY_NAME);
    const renamed = await call('PATCH', `${P(withCats.code)}/expense-categories/${sysCat.id}`, MGR, { name: 'K Yeni Ad' });
    const ensureClient2 = await pool.connect();
    const applied2 = await ensureFinanceFundsSchema(ensureClient2);
    ensureClient2.release();
    check('K0x: sistem kategorisi yeniden adlandirilinca (is_system + capital) ensure yeni kategori EKLEMEZ', renamed.status === 200 && applied2.length === 0 && (await capitalsOf(withCats)).length === 1, { applied2 });
    await q(`DELETE FROM expense_categories WHERE site_code = $1 AND is_system AND fund = 'capital'`, [withCats.code]);
    await categories(withCats);
    check('K0y: kategori listesi ucu eksik sistem kategorisini (080 oncesi site) tamamlar', (await capitalsOf(withCats)).length === 1);
  }

  // ============================================================================================================
  // K1. tanim API: fund <-> charge_party
  // ============================================================================================================
  const D = await mkManaged('K Tanim Sitesi', { 'D Blok': 3 });
  {
    const aidat = await createDefinition(D, { name: 'K Aidat', amount_minor: 100000, start_period: ym(-1) });
    check('K1a: aylik tanim varsayilani: charge_party occupant, fund operating', aidat.status === 201 && aidat.body.charge_party === 'occupant' && aidat.body.fund === 'operating', aidat.body);
    const fon = await createDefinition(D, { name: 'K Fon', amount_minor: 50000, start_period: ym(-1), fund: 'capital' });
    check('K1b: yalniz fund verilirse kim oder turetilir (capital => owner)', fon.status === 201 && fon.body.charge_party === 'owner' && fon.body.fund === 'capital', fon.body);
    const both = await createDefinition(D, { name: 'K Fon 2', amount_minor: 50000, start_period: ym(-1), fund: 'operating', charge_party: 'occupant' });
    check('K1c: fund + charge_party tutarliysa kabul', both.status === 201 && both.body.fund === 'operating');
    const conflict = await createDefinition(D, { name: 'K Cakisma', amount_minor: 100, start_period: ym(-1), fund: 'operating', charge_party: 'owner' });
    check('K1d: fund ile charge_party CAKISIRSA 400 INVALID_BODY', conflict.status === 400 && conflict.body.code === 'INVALID_BODY', conflict.body);
    const invalid = await createDefinition(D, { name: 'K Gecersiz', amount_minor: 100, start_period: ym(-1), fund: 'fon' });
    check('K1e: gecersiz fund 400 INVALID_BODY', invalid.status === 400 && invalid.body.code === 'INVALID_BODY');
    const oneTime = await call('POST', `${P(D.code)}/definitions`, MGR, { name: 'K Tek Seferlik', kind: 'one_time', distribution: 'fixed', amount_minor: 100, start_period: ym(0), target: { type: 'site' } });
    check('K1f: tek seferlik tanim varsayilani owner => fund capital (canli veriyle birebir)', oneTime.status === 201 && oneTime.body.fund === 'capital' && oneTime.body.charge_party === 'owner', oneTime.body);

    const patch = await call('PATCH', `${P(D.code)}/definitions/${both.body.id}`, MGR, { fund: 'capital' });
    check('K1g: PATCH fund (borclandirilmamis tanim) => charge_party owner', patch.status === 200 && patch.body.fund === 'capital' && patch.body.charge_party === 'owner', patch.body);
    const patchConflict = await call('PATCH', `${P(D.code)}/definitions/${both.body.id}`, MGR, { fund: 'operating', charge_party: 'owner' });
    check('K1h: PATCH fund + charge_party cakismasi 400', patchConflict.status === 400 && patchConflict.body.code === 'INVALID_BODY');
    const patchBad = await call('PATCH', `${P(D.code)}/definitions/${both.body.id}`, MGR, { fund: null });
    check('K1i: PATCH fund null 400', patchBad.status === 400);
    await postDefinition(D, aidat.body.id, ym(-1));
    const patchPosted = await call('PATCH', `${P(D.code)}/definitions/${aidat.body.id}`, MGR, { fund: 'capital' });
    check('K1j: borclandirilmis tanimda da fund degisir (yalniz SONRAKI borclandirmalari etkiler); eski satirlar degismez', patchPosted.status === 200 && patchPosted.body.fund === 'capital');
    await call('PATCH', `${P(D.code)}/definitions/${aidat.body.id}`, MGR, { fund: 'operating' });
    const list = await call('GET', `${P(D.code)}/definitions`, MGR);
    check('K1k: tanim listesi her tanimda fund tasir', list.status === 200 && list.body.items.every((d) => d.fund === (d.charge_party === 'owner' ? 'capital' : 'operating')), list.body.items?.map((d) => [d.name, d.fund, d.charge_party]));
    const unknown = await call('PATCH', `${P(D.code)}/definitions/${aidat.body.id}`, MGR, { fund: 'x' });
    check('K1l: PATCH gecersiz fund 400', unknown.status === 400);
  }

  // ============================================================================================================
  // K2. borclandirma kasayi yazar
  // ============================================================================================================
  {
    const defs = (await call('GET', `${P(D.code)}/definitions`, MGR)).body.items;
    const aidat = defs.find((d) => d.name === 'K Aidat');
    const fon = defs.find((d) => d.name === 'K Fon');
    await postDefinition(D, fon.id, ym(-1));
    const byDefinition = (await q(`SELECT definition_id, fund, COUNT(*)::INT AS n FROM ledger_entries WHERE site_code = $1 AND kind = 'charge' GROUP BY 1, 2 ORDER BY 1`, [D.code])).rows;
    check(
      'K2a: aylik borclandirma kasayi yazar: aidat satirlari operating, fon satirlari capital (her tanim tek kasada, 3 daire)',
      byDefinition.length === 2 && byDefinition.find((r) => Number(r.definition_id) === aidat.id)?.fund === 'operating' && byDefinition.find((r) => Number(r.definition_id) === fon.id)?.fund === 'capital' && byDefinition.every((r) => r.n === 3),
      byDefinition,
    );
    const ek = await postCharge(D, { name: 'K Ek Borc Varsayilan', amount_minor: 3000, distribution: 'fixed', target: { type: 'site' } });
    const ekRows = (await q(`SELECT DISTINCT fund FROM ledger_entries WHERE run_id = $1`, [ek.post.body?.run?.id ?? 0])).rows.map((r) => r.fund);
    check('K2b: ek borc varsayilani ev sahibi => capital; satirlarda fund=capital', ek.post.status === 201 && same(ekRows, ['capital']) && ek.post.body.definition.fund === 'capital', { status: ek.post.status, ekRows });
    const ek2 = await postCharge(D, { name: 'K Ek Borc Isletme', amount_minor: 2000, distribution: 'fixed', target: { type: 'site' }, fund: 'operating' });
    const ek2Rows = (await q(`SELECT DISTINCT fund FROM ledger_entries WHERE run_id = $1`, [ek2.post.body?.run?.id ?? 0])).rows.map((r) => r.fund);
    check('K2c: ek borc fund=operating => occupant, satirlar operating', ek2.post.status === 201 && same(ek2Rows, ['operating']) && ek2.post.body.definition.charge_party === 'occupant', { status: ek2.post.status, ek2Rows });
    const ek3 = await call('POST', `${P(D.code)}/charges/preview`, MGR, { name: 'K Cakisma', amount_minor: 100, distribution: 'fixed', target: { type: 'site' }, fund: 'capital', charge_party: 'occupant' });
    check('K2d: ek borc onizlemesinde fund / charge_party cakismasi 400', ek3.status === 400 && ek3.body.code === 'INVALID_BODY');
    check('K2e: yeni borc satirlarinda kasa HIC bos degil', Number((await q(`SELECT COUNT(*) AS n FROM ledger_entries WHERE site_code = $1 AND kind = 'charge' AND fund IS NULL`, [D.code])).rows[0].n) === 0);
  }

  // ============================================================================================================
  // Ana senaryo sitesi (K3-K6, K10): 4 daire; A2 kiracili
  // ============================================================================================================
  const FS = await mkManaged('K Kasa Sitesi', { 'F Blok': 4 });
  const [A1, A2, A3, A4] = FS.ids;
  await setResponsible(A2, 'both');
  const a2Owner = await resident(FS, A2, 'owner', 'K A2 Malik');
  const a2Tenant = await resident(FS, A2, 'tenant', 'K A2 Kiraci');
  const aidatDef = await createDefinition(FS, { name: 'K F Aidat', amount_minor: 100000, start_period: ym(-1) });
  const fonDef = await createDefinition(FS, { name: 'K F Fon', amount_minor: 50000, start_period: ym(-1), fund: 'capital' });
  await postDefinition(FS, aidatDef.body.id, ym(-1));
  await postDefinition(FS, fonDef.body.id, ym(-1));
  // 080 oncesi surum gibi: A4 hesap acilmadan ONCE (hesap acilis tarihinden eski) 7777 tahsilat; kasaya dahil edilmez (eslenmemis / acilisa dahil)
  // K3 (P1-3): A4'te Aidat + Fon borcu BIRLIKTE acik; kisitsiz tahsilat reddedilirdi => yonetici hesabi secer (Aidat Hesabi). Dagitim sonucu degismez.
  const p0 = await payment(FS, A4, 7777, { entry_date: ago(90), fund: 'operating' });
  const cash = await call('POST', `${P(FS.code)}/accounts`, MGR, { name: 'K Ana Kasa', kind: 'cash', opening_balance_minor: 1000000, opening_date: ago(60), idempotency_key: key('acc') });
  const accountId = cash.body?.account?.id;
  check('K3-hazirlik: A4 icin hesap oncesi tahsilat 201, hesap acildi (acilis 10.000,00 TL)', p0.status === 201 && cash.status === 201 && accountId > 0, { p0: p0.status, cash: cash.status });

  // ============================================================================================================
  // K3. tahsilat dagitimi
  // ============================================================================================================
  // K3 (P1-3, 2026-10-28): yazilim odemeyi kendiliginden bir hesaba ATAMAZ. A1 ve A3'te Aidat + Fon borcu BIRLIKTE acik: kisitsiz tahsilat reddedilir, yonetici hesabi secer.
  const paymentCount = async (aptId) => Number((await q(`SELECT COUNT(*) AS n FROM ledger_entries WHERE site_code = $1 AND apartment_id = $2 AND kind = 'payment'`, [FS.code, aptId])).rows[0].n);
  const noChoice = await payment(FS, A1, 150000, { account_id: accountId, entry_date: ago(12), __strict: true }); // ham yanit: QA yardimcisi yeniden denemez
  check(
    'K3a0: A1 (Aidat 100000 + Fon 50000 birlikte acik) kisitsiz 150000 => 400 FUND_CHOICE_REQUIRED; fund_choice acik borclari tasir (secim zorunlu, oneri yok); HICBIR satir yazilmadi',
    noChoice.status === 400 && noChoice.body.code === 'FUND_CHOICE_REQUIRED' && same(noChoice.body.fund_choice?.open, { operating_minor: 100000, capital_minor: 50000 }) &&
      noChoice.body.fund_choice?.choice_required === true && noChoice.body.fund_choice?.suggested_fund === null && (await paymentCount(A1)) === 0,
    noChoice.body,
  );
  const choicePath = `${P(FS.code)}/payments/fund-choice?apartment_id=${A1}&account_party=owner&amount_minor=150000`;
  const choiceGet = await call('GET', choicePath, MGR);
  const choiceDenied = [];
  for (const user of [STAFF, RESIDENT, OUTSIDER, BOARD]) choiceDenied.push((await call('GET', choicePath, user)).status);
  check(
    'K3a1: GET payments/fund-choice: zorunlu + acik borclar + otomatik dagitim onerisi YALNIZ bilgi (100000 + 50000; hicbir satir yazilmaz); gorevli / sakin / ilgisiz / kurul 403',
    choiceGet.status === 200 && choiceGet.body.choice_required === true && same(choiceGet.body.open, { operating_minor: 100000, capital_minor: 50000 }) &&
      same(choiceGet.body.proposal, { operating_minor: 100000, capital_minor: 50000, advance_minor: 0 }) && choiceGet.body.suggested_fund === null && (await paymentCount(A1)) === 0 && choiceDenied.every((s) => s === 403),
    { get: choiceGet.body, denied: choiceDenied },
  );
  const pay1a = await payment(FS, A1, 100000, { account_id: accountId, entry_date: ago(12), fund: 'operating' });
  // Aidat borcu kapandi: artik TEK tur (Fon) borc acik => kisitsiz kabul edilir (oneriyi istemci secili gonderir; sunucu kisit ATAMAZ => entry.fund null)
  const pay1 = await payment(FS, A1, 50000, { account_id: accountId, entry_date: ago(12) });
  check(
    'K3a: A1: once Aidat Hesabi secimiyle 100000 (fund_split operating 100000; entry.fund=operating), sonra tek tur (Fon) borc kaldigi icin kisitsiz 50000 kabul => capital 50000; entry.fund null',
    pay1a.status === 201 && same(pay1a.body.fund_split, { operating_minor: 100000, capital_minor: 0, advance_minor: 0 }) && pay1a.body.entry.fund === 'operating' &&
      pay1.status === 201 && same(pay1.body.fund_split, { operating_minor: 0, capital_minor: 50000, advance_minor: 0 }) && pay1.body.entry.fund === null,
    [pay1a.body, pay1.body],
  );
  const afterChoice = await call('GET', choicePath.replace('&amount_minor=150000', ''), MGR);
  check('K3a2: A1 odemelerden sonra acik borc yok: secim zorunlu degil, oneri yok', afterChoice.status === 200 && afterChoice.body.choice_required === false && afterChoice.body.suggested_fund === null && same(afterChoice.body.open, { operating_minor: 0, capital_minor: 0 }), afterChoice.body);
  const pay2 = await payment(FS, A2, 30000, { account_id: accountId, entry_date: ago(8), account_party: 'owner', fund: 'capital' });
  check(
    'K3b: A2 (malik hesabi) KISITLI 30000 (fund=capital) => yalniz fon borcuna; entry.fund=capital; fund_split capital 30000',
    pay2.status === 201 && same(pay2.body.fund_split, { operating_minor: 0, capital_minor: 30000, advance_minor: 0 }) && pay2.body.entry.fund === 'capital' && pay2.body.entry.account_party === 'owner',
    pay2.body,
  );
  const pay3a = await payment(FS, A3, 100000, { account_id: accountId, entry_date: ago(10), fund: 'operating' });
  const pay3 = await payment(FS, A3, 70000, { account_id: accountId, entry_date: ago(10) }); // Aidat kapandi: tek tur (Fon) kaldi => kisitsiz kabul
  check(
    'K3c: A3: Aidat Hesabi secimiyle 100000, sonra (tek tur Fon borcu kaldi) kisitsiz 70000 => Fon 50000 + AVANS 20000 (genel avans)',
    pay3a.status === 201 && pay3.status === 201 && same(pay3a.body.fund_split, { operating_minor: 100000, capital_minor: 0, advance_minor: 0 }) && same(pay3.body.fund_split, { operating_minor: 0, capital_minor: 50000, advance_minor: 20000 }),
    [pay3a.body.fund_split, pay3.body.fund_split],
  );
  const a2Restricted = await payment(FS, A2, 40000, { account_id: accountId, entry_date: ago(7), account_party: 'owner', fund: 'operating' });
  check('K3d: kisit, kisitin kasasinda borc yokken (malik hesabinda yalniz fon borcu var) tamami AVANS (operating kisitli)', a2Restricted.status === 201 && same(a2Restricted.body.fund_split, { operating_minor: 0, capital_minor: 0, advance_minor: 40000 }), a2Restricted.body.fund_split);
  const a2Rev = await call('POST', `${P(FS.code)}/entries/${a2Restricted.body.entry.id}/reverse`, MGR, { reason: 'deneme', idempotency_key: key('rev') });
  check('K3e: kisitli tahsilat ters cevrilince ters kayit KISITI tasir (fund=operating) ve dagitim yok olur', a2Rev.status === 201 && a2Rev.body.entry.fund === 'operating' && (await fundOfRow(a2Rev.body.entry.id)) === 'operating', a2Rev.body.entry);
  const keyed = key('fkey');
  const first = await payment(FS, A4, 5000, { account_id: accountId, idempotency_key: keyed, fund: 'capital' });
  const again = await payment(FS, A4, 5000, { account_id: accountId, idempotency_key: keyed, fund: 'capital' });
  const withoutFund = await payment(FS, A4, 5000, { account_id: accountId, idempotency_key: keyed });
  const otherFund = await payment(FS, A4, 5000, { account_id: accountId, idempotency_key: keyed, fund: 'operating' });
  check(
    'K3f: ayni anahtar + ayni kisit = ayni kayit (200); kisitsiz tekrar (eski istemci) ayni kayit; FARKLI kisit 409 IDEMPOTENCY_CONFLICT',
    first.status === 201 && again.status === 200 && again.body.entry.id === first.body.entry.id && withoutFund.status === 200 && otherFund.status === 409 && otherFund.body.code === 'IDEMPOTENCY_CONFLICT',
    [first.status, again.status, withoutFund.status, otherFund.status],
  );
  const undoFirst = await call('POST', `${P(FS.code)}/entries/${first.body.entry.id}/reverse`, MGR, { reason: 'deneme', idempotency_key: key('rev') });
  check('K3g: A4 deneme tahsilati ters cevrildi (kasalarda iz birakmaz)', undoFirst.status === 201);
  const fixed = await payment(FS, A4, 10000, { account_id: accountId, fund: 'capital' });
  const corrected = await call('POST', `${P(FS.code)}/entries/${fixed.body.entry.id}/correct`, MGR, { amount_minor: 12000, entry_date: TODAY, method: 'cash', account_id: accountId, idempotency_key: key('cor') });
  check(
    'K3h: duzeltme: kasa kisiti gövdede verilmezse ASILIN kisiti korunur (yeni tahsilat capital); ters kayit asilin kasasini tasir',
    corrected.status === 201 && corrected.body.entry.fund === 'capital' && corrected.body.reversal.fund === 'capital' && corrected.body.fund_split?.capital_minor === 12000,
    corrected.body,
  );
  const correctedOverride = await call('POST', `${P(FS.code)}/entries/${corrected.body.entry.id}/correct`, MGR, { amount_minor: 12000, entry_date: TODAY, method: 'cash', account_id: accountId, fund: 'operating', idempotency_key: key('cor') });
  check('K3i: duzeltmede fund verilirse yeni tahsilat O kisitla yazilir', correctedOverride.status === 201 && correctedOverride.body.entry.fund === 'operating', correctedOverride.body.entry);
  // temizlik: A4 deneme tahsilatlarini ters cevir (kasa senaryosu A4'te yalniz 7777 + acik borc kalsin)
  await call('POST', `${P(FS.code)}/entries/${correctedOverride.body.entry.id}/reverse`, MGR, { reason: 'temizlik', idempotency_key: key('rev') });
  const rejected = await payment(FS, A1, 100, { account_id: accountId, fund: 'fon' });
  check('K3j: gecersiz kasa kisiti 400 INVALID_BODY, kayit yazilmaz', rejected.status === 400 && rejected.body.code === 'INVALID_BODY');

  // bagimsiz dogrulama: her hesabin API ekstresi, ayni satirlardan hesaplanan dagitimla (kahin) ve SQL bakiyesiyle uyusur
  let consistent = true;
  const details = [];
  for (const [aptId, party] of [[A1, 'owner'], [A2, 'owner'], [A2, 'tenant'], [A3, 'owner'], [A4, 'owner']]) {
    const res = await account(FS, aptId, `?account_party=${party}`);
    if (res.status !== 200) {
      consistent = false;
      details.push([aptId, party, res.status, res.body]);
      continue;
    }
    const o = await oracle(FS, aptId, party);
    const sql = await sqlBalance(FS, aptId, party);
    const apiOpen = res.body.funds.operating.balance_minor + res.body.funds.capital.balance_minor - res.body.advance_minor;
    const ok =
      res.status === 200 && res.body.funds.operating.balance_minor === Number(o.funds.operating.open) && res.body.funds.capital.balance_minor === Number(o.funds.capital.open) &&
      res.body.advance_minor === Number(o.advanceTotal) && apiOpen === sql && res.body.balance_minor === sql;
    consistent = consistent && ok;
    details.push([aptId, party, res.body.funds, res.body.advance_minor, sql]);
  }
  check('K4a: ekstre kasa kirilimi (hesap suzgecli) kahine ve SQL bakiyesine birebir: acik borc(op) + acik borc(fon) - avans = hesap bakiyesi (5 hesap)', consistent, details);
  const a3 = await account(FS, A3);
  const a3Chosen = a3.body.items.find((e) => e.kind === 'payment' && e.fund === 'operating');
  const a3Auto = a3.body.items.find((e) => e.kind === 'payment' && e.fund === null);
  check(
    'K4b: A3 ekstresi: funds capital/operating 0, advance_minor 20000; odeme satirlarinda fund_split ve fund (secilen operating; kisitsiz null); borc satirlari kendi kasasiyla',
    a3.status === 200 && a3.body.advance_minor === 20000 && a3.body.funds.operating.balance_minor === 0 && a3.body.funds.capital.balance_minor === 0 &&
      same(a3Chosen?.fund_split, { operating_minor: 100000, capital_minor: 0, advance_minor: 0 }) && same(a3Auto?.fund_split, { operating_minor: 0, capital_minor: 50000, advance_minor: 20000 }) &&
      a3.body.items.filter((e) => e.kind === 'charge').map((e) => e.fund).sort().join(',') === 'capital,operating',
    a3.body.items,
  );
  const a2All = await account(FS, A2);
  check('K4c: A2 iki hesap birlikte: operating acik 100000 (kiraci hesabi), capital acik 20000 (malik hesabi); fund_split ekstrede', a2All.status === 200 && a2All.body.funds.operating.balance_minor === 100000 && a2All.body.funds.capital.balance_minor === 20000 && a2All.body.advance_minor === 0, a2All.body.funds);

  // sakin: /app/my-finance
  const ownerView = await call('GET', '/app/my-finance', a2Owner.user);
  const tenantView = await call('GET', '/app/my-finance', a2Tenant.user);
  const ownerItem = ownerView.body?.items?.find((i) => i.apartment_id === A2);
  const tenantItem = tenantView.body?.items?.find((i) => i.apartment_id === A2);
  check(
    'K4d: Borcum: kiraci hesabi yalniz operating (100000), malik hesabi yalniz capital (20000); malike salt okunur kiraci hesabi da funds tasir; ust duzey funds = kendi hesabi',
    ownerItem?.funds?.capital?.balance_minor === 20000 && ownerItem?.funds?.operating?.balance_minor === 0 && tenantItem?.funds?.operating?.balance_minor === 100000 && tenantItem?.funds?.capital?.balance_minor === 0 &&
      ownerItem.accounts.length === 2 && ownerItem.accounts[1].role === 'read_only' && ownerItem.accounts[1].funds.operating.balance_minor === 100000 && typeof tenantItem.advance_minor === 'number',
    { owner: ownerItem?.funds, tenant: tenantItem?.funds },
  );
  const stranger = await call('GET', '/app/my-finance', RESIDENT);
  check('K4e: baska kullanicinin Borcum cevabinda bu daire / kasa kirilimi yok', !(stranger.body?.items ?? []).some((i) => i.apartment_id === A2));

  // ============================================================================================================
  // K5. gider / kategori kasasi
  // ============================================================================================================
  const sysCategory = await categoryOf(FS, CAPITAL_CATEGORY_NAME);
  const elektrik = await categoryOf(FS, 'Elektrik');
  check('K5a: kategori listesi fund tasir; "Yatirim ve demirbas" sistem + capital, "Elektrik" operating', sysCategory?.fund === 'capital' && sysCategory?.is_system === true && elektrik?.fund === 'operating', { sysCategory, elektrik });
  const expense = (body) => call('POST', `${P(FS.code)}/expenses`, MGR, { description: 'K gider', expense_date: ago(6), account_id: accountId, idempotency_key: key('ex'), ...body });
  const exOp = await expense({ category_id: elektrik.id, amount_minor: 40000, description: 'K elektrik' });
  const exCap = await expense({ category_id: sysCategory.id, amount_minor: 25000, description: 'K demirbas' });
  const exOverride = await expense({ category_id: elektrik.id, amount_minor: 5000, description: 'K elektrik fon', fund: 'capital' });
  check(
    'K5b: gider kasasi: kategori operating => operating; sistem kategorisi => capital; gider satirinda fund secilirse O (kategoriyi ezer); satira HER ZAMAN yazilir',
    [exOp, exCap, exOverride].every((r) => r.status === 201) && exOp.body.expense.fund === 'operating' && exCap.body.expense.fund === 'capital' && exOverride.body.expense.fund === 'capital' &&
      same((await q(`SELECT fund FROM expenses WHERE site_code = $1 ORDER BY id`, [FS.code])).rows.map((r) => r.fund), ['operating', 'capital', 'capital']),
    [exOp.body, exCap.body, exOverride.body].map((b) => b.expense?.fund ?? b),
  );
  const exBad = await expense({ category_id: elektrik.id, amount_minor: 1000, fund: 'fon' });
  check('K5c: gecersiz gider kasasi 400', exBad.status === 400 && exBad.body.code === 'INVALID_BODY');
  const exVoidSrc = await expense({ category_id: elektrik.id, amount_minor: 777, description: 'K iptal edilecek' });
  const exVoid = await call('POST', `${P(FS.code)}/expenses/${exVoidSrc.body.expense.id}/void`, MGR, { reason: 'deneme', idempotency_key: key('exv') });
  check('K5d: iptal edilen gider kasayi etkilemez (K6 degismezinde sinanir)', exVoid.status === 200 || exVoid.status === 201, exVoid.body);
  const listed = await call('GET', `${P(FS.code)}/expenses`, MGR);
  check('K5e: gider listesi fund tasir', listed.status === 200 && listed.body.items.every((e) => e.fund === 'operating' || e.fund === 'capital'), listed.body.items?.map((e) => e.fund));
  const userCat = await call('POST', `${P(FS.code)}/expense-categories`, MGR, { name: 'K Ozel Fon Kategorisi', fund: 'capital' });
  check('K5f: kategori olusturma fund=capital; varsayilan operating', userCat.status === 201 && userCat.body.category.fund === 'capital' && (await call('POST', `${P(FS.code)}/expense-categories`, MGR, { name: 'K Ozel Isletme' })).body.category.fund === 'operating');
  const sysPatch = await call('PATCH', `${P(FS.code)}/expense-categories/${sysCategory.id}`, MGR, { fund: 'operating' });
  check('K5g: SISTEM kategorisinin kasasi degistirilemez: 409 CATEGORY_FUND_LOCKED', sysPatch.status === 409 && sysPatch.body.code === 'CATEGORY_FUND_LOCKED', sysPatch.body);
  const userPatch = await call('PATCH', `${P(FS.code)}/expense-categories/${userCat.body.category.id}`, MGR, { fund: 'operating' });
  const badPatch = await call('PATCH', `${P(FS.code)}/expense-categories/${userCat.body.category.id}`, MGR, { fund: 'fon' });
  check('K5h: kullanici kategorisinin kasasi (eski gideri yoksa) degisir; gecersiz kasa 400', userPatch.status === 200 && userPatch.body.category.fund === 'operating' && badPatch.status === 400);
  // 080 oncesi gider (kasa NULL): kategorinin kasasindan turetilir; kasa degisimi KILITLI
  const LG = await mkManaged('K Eski Gider Sitesi', { 'E Blok': 1 });
  const lgAccount = (await call('POST', `${P(LG.code)}/accounts`, MGR, { name: 'K Eski Kasa', kind: 'cash', opening_balance_minor: 0, opening_date: ago(60), idempotency_key: key('acc') })).body.account;
  const lgCat = await call('POST', `${P(LG.code)}/expense-categories`, MGR, { name: 'K Eski Kategori' });
  await q(
    `INSERT INTO expenses (site_code, category_id, category_name, description, amount_minor, expense_date, period, account_id, idempotency_key, request_fingerprint) VALUES ($1, $2, 'K Eski Kategori', 'eski gider', 4200, $3, $4, $5, $6, $7)`,
    [LG.code, lgCat.body.category.id, ago(5), `${ago(5).slice(0, 7)}-01`, lgAccount.id, key('legacy'), fillFp],
  );
  const lgList = await call('GET', `${P(LG.code)}/expenses`, MGR);
  const lgLocked = await call('PATCH', `${P(LG.code)}/expense-categories/${lgCat.body.category.id}`, MGR, { fund: 'capital' });
  check('K5i: kasasi kaydedilmemis eski gider okumada kategorinin kasasini alir (operating); o kategorinin kasasi degistirilemez (409 CATEGORY_FUND_LOCKED)', lgList.body.items[0].fund === 'operating' && lgLocked.status === 409 && lgLocked.body.code === 'CATEGORY_FUND_LOCKED', { fund: lgList.body.items?.[0]?.fund, locked: lgLocked.body });

  // ============================================================================================================
  // K6. kasa ozeti, dokum, aktarim ve DEGISMEZ
  // ============================================================================================================
  const adj = await call('POST', `${P(FS.code)}/accounts/${accountId}/adjustments`, MGR, { amount_minor: -1500, movement_date: ago(4), reason_code: 'bank_fee', idempotency_key: key('adj') });
  check('K6-hazirlik: banka masrafi duzeltmesi -1500', adj.status === 201, adj.body);
  const t1 = await call('POST', `${P(FS.code)}/fund-transfers`, MGR, { from_fund: 'operating', to_fund: 'capital', amount_minor: 60000, transfer_date: ago(3), description: 'K acilis bolusumu', idempotency_key: key('ft') });
  const t2 = await call('POST', `${P(FS.code)}/fund-transfers`, MGR, { from_fund: 'capital', to_fund: 'operating', amount_minor: 10000, transfer_date: ago(2), idempotency_key: key('ft') });
  const r2 = await call('POST', `${P(FS.code)}/fund-transfers/${t2.body?.transfer?.id}/reverse`, MGR, { reason: 'yanlis', idempotency_key: key('ftr') });
  check(
    'K6a: aktarim 201 { transfer }; ters aktarim 201 (yonler yer degistirir, bugunun tarihi), asil reversed_by_transfer_id tasir',
    t1.status === 201 && t1.body.transfer.from_fund === 'operating' && t1.body.transfer.amount_minor === 60000 && t1.body.transfer.period === ago(3).slice(0, 7) && r2.status === 201 &&
      r2.body.transfer.from_fund === 'operating' && r2.body.transfer.to_fund === 'capital' && r2.body.transfer.reverses_transfer_id === t2.body.transfer.id && r2.body.original.reversed_by_transfer_id === r2.body.transfer.id && r2.body.transfer.transfer_date === TODAY,
    [t1.body, r2.body],
  );

  // A4: eslenen tahsilat + ters kayit ve iptal edilmis gider zaten yapildi; son durumu dogrula
  const summary = await funds(FS);
  const op = summary.body.funds?.operating;
  const cap = summary.body.funds?.capital;
  check(
    'K6b: kasa ozeti (elle hesap): Isletme 1.098.500 (acilis 1.000.000 + tahsilat 200.000 - gider 40.000 + aktarim 10.000 - 70.000 + duzeltme -1.500), Fon 160.000, avans 20.000',
    summary.status === 200 && op.opening_minor === 1000000 && op.collections_minor === 200000 && op.expenses_minor === 40000 && op.transfers_in_minor === 10000 && op.transfers_out_minor === 70000 && op.adjustments_minor === -1500 && op.balance_minor === 1098500 &&
      cap.opening_minor === 0 && cap.collections_minor === 130000 && cap.expenses_minor === 30000 && cap.transfers_in_minor === 70000 && cap.transfers_out_minor === 10000 && cap.balance_minor === 160000 && summary.body.advance_minor === 20000,
    summary.body,
  );
  check(
    'K6c: DEGISMEZ: Isletme + Fon + avans = hesaplarin toplam bakiyesi (1.278.500); difference_minor 0, balanced true; eslenmemis tahsilat 0 (acilistan onceki 7777 listelenmez)',
    summary.body.accounts_total_minor === 1278500 && summary.body.difference_minor === 0 && summary.body.balanced === true && summary.body.unassigned_payments.count === 0 && summary.body.has_accounts === true,
    summary.body,
  );
  const sqlPhysical = Number((await q(`SELECT COALESCE(SUM(amount_minor), 0)::TEXT AS s FROM account_movements WHERE site_code = $1`, [FS.code])).rows[0].s);
  check('K6d: hesaplarin toplami SQL ile de ayni (account_movements toplami)', sqlPhysical === 1278500, sqlPhysical);
  const fromTo = await funds(FS, `?from=${ago(9)}&to=${TODAY}`);
  const op9 = fromTo.body.funds?.operating;
  const cap9 = fromTo.body.funds?.capital;
  check(
    'K6e: donem suzgeci from=ago(9): acilis = oncesindeki tum hareketler (Isletme 1.200.000, Fon 100.000), donem ici akislar ayri; bakiye ayni; avans / toplam ayni',
    fromTo.status === 200 && op9.opening_minor === 1200000 && op9.collections_minor === 0 && op9.expenses_minor === 40000 && op9.balance_minor === 1098500 && cap9.opening_minor === 100000 && cap9.collections_minor === 30000 && cap9.expenses_minor === 30000 && cap9.balance_minor === 160000 && fromTo.body.balanced === true,
    fromTo.body,
  );
  const early = await funds(FS, `?to=${ago(30)}`);
  check('K6f: gecmis tarih (to=ago(30)): yalniz acilis (1.000.000 / 0), tahsilat yok, avans 0; fiziksel toplamla FARKSIZ', early.status === 200 && early.body.funds.operating.balance_minor === 1000000 && early.body.funds.capital.balance_minor === 0 && early.body.advance_minor === 0 && early.body.balanced === true, early.body);
  const bothBad = await funds(FS, `?from=${TODAY}&to=${ago(3)}`);
  check('K6g: from > to 400 INVALID_QUERY', bothBad.status === 400 && bothBad.body.code === 'INVALID_QUERY');

  const mvOp = await movements(FS, 'operating');
  const mvCap = await movements(FS, 'capital');
  const countByType = (res) => Object.fromEntries(Object.entries(res.body.items.reduce((acc, item) => ({ ...acc, [item.type]: (acc[item.type] ?? 0) + 1 }), {})).sort());
  const sorted = (obj) => Object.fromEntries(Object.entries(obj).sort());
  check(
    'K6h: kasa dokumu: Isletme 8 hareket (1 acilis, 2 tahsilat, 1 gider, 3 aktarim, 1 duzeltme), Fon 8 (3 tahsilat, 2 gider, 3 aktarim); toplam = olay sayisi; bakiye ozetle ayni; yeni -> eski',
    mvOp.status === 200 && mvOp.body.total === 8 && same(countByType(mvOp), sorted({ opening: 1, collection: 2, expense: 1, transfer_out: 2, transfer_in: 1, adjustment: 1 })) && mvOp.body.balance_minor === 1098500 &&
      mvCap.body.total === 8 && same(countByType(mvCap), sorted({ collection: 3, expense: 2, transfer_in: 2, transfer_out: 1 })) && mvCap.body.balance_minor === 160000 &&
      mvOp.body.items.every((item, i, all) => i === 0 || all[i - 1].date >= item.date),
    { op: mvOp.body.items?.map((i) => [i.type, i.date, i.amount_minor]), cap: countByType(mvCap) },
  );
  check(
    'K6i: dokumde hareket toplami = kasa bakiyesi (Isletme 1.098.500, Fon 160.000); tahsilat satiri daire etiketi tasir, kisi adi YOK',
    mvOp.body.items.reduce((s, i) => s + i.amount_minor, 0) === 1098500 && mvCap.body.items.reduce((s, i) => s + i.amount_minor, 0) === 160000 && mvOp.body.items.filter((i) => i.type === 'collection').every((i) => /Daire/.test(i.label ?? '') && i.apartment?.id > 0) && !JSON.stringify(mvOp.body).includes('K A2'),
  );
  const page1 = await movements(FS, 'operating', '?limit=3&offset=0');
  const page2 = await movements(FS, 'operating', '?limit=3&offset=3');
  check('K6j: sayfalama: limit 3 / offset; toplam sabit; sayfalar birlesince ayni sira', page1.body.items.length === 3 && page2.body.items.length === 3 && page1.body.total === 8 && same([...page1.body.items, ...page2.body.items].map((i) => i.key), mvOp.body.items.slice(0, 6).map((i) => i.key)));
  const noFund = await movements(FS, 'fon');
  check('K6k: bilinmeyen kasa 404 FUND_NOT_FOUND', noFund.status === 404 && noFund.body.code === 'FUND_NOT_FOUND');
  const tList = await call('GET', `${P(FS.code)}/fund-transfers`, MGR);
  check('K6l: aktarim listesi yeni -> eski; ters aktarim reverses_transfer_id tasir; created_by_name yonetici icin dolu, kurul icin null', tList.status === 200 && tList.body.items.length === 3 && tList.body.items[0].reverses_transfer_id === t2.body.transfer.id && tList.body.items[0].created_by_name !== null && (await call('GET', `${P(FS.code)}/fund-transfers`, BOARD)).body.items.every((i) => i.created_by_name === null));
  const dupReverse = await call('POST', `${P(FS.code)}/fund-transfers/${t2.body.transfer.id}/reverse`, MGR, { reason: 'tekrar', idempotency_key: key('ftr') });
  const reverseOfReverse = await call('POST', `${P(FS.code)}/fund-transfers/${r2.body.transfer.id}/reverse`, MGR, { reason: 'ters', idempotency_key: key('ftr') });
  check('K6m: cift ters aktarim 409 FUND_TRANSFER_ALREADY_REVERSED; ters aktarimin tersi 409 FUND_TRANSFER_NOT_REVERSIBLE', dupReverse.status === 409 && dupReverse.body.code === 'FUND_TRANSFER_ALREADY_REVERSED' && reverseOfReverse.status === 409 && reverseOfReverse.body.code === 'FUND_TRANSFER_NOT_REVERSIBLE', [dupReverse.body, reverseOfReverse.body]);
  const t1Replay = await call('POST', `${P(FS.code)}/fund-transfers`, MGR, { from_fund: 'operating', to_fund: 'capital', amount_minor: 60000, transfer_date: ago(3), description: 'K acilis bolusumu', idempotency_key: t1.body.transfer.id ? (await q(`SELECT idempotency_key FROM finance_fund_transfers WHERE id = $1`, [t1.body.transfer.id])).rows[0].idempotency_key : 'x' });
  const t1Conflict = await call('POST', `${P(FS.code)}/fund-transfers`, MGR, { from_fund: 'operating', to_fund: 'capital', amount_minor: 60001, transfer_date: ago(3), description: 'K acilis bolusumu', idempotency_key: (await q(`SELECT idempotency_key FROM finance_fund_transfers WHERE id = $1`, [t1.body.transfer.id])).rows[0].idempotency_key });
  check('K6n: ayni anahtar + ayni govde = ayni aktarim (200, tek satir); ayni anahtar + farkli tutar 409 IDEMPOTENCY_CONFLICT', t1Replay.status === 200 && t1Replay.body.transfer.id === t1.body.transfer.id && t1Conflict.status === 409 && t1Conflict.body.code === 'IDEMPOTENCY_CONFLICT');
  const badTransfers = [
    [{ from_fund: 'operating', to_fund: 'operating', amount_minor: 1 }, 'ayni kasa'],
    [{ from_fund: 'operating', to_fund: 'fon', amount_minor: 1 }, 'gecersiz kasa'],
    [{ from_fund: 'operating', to_fund: 'capital', amount_minor: 0 }, 'tutar 0'],
    [{ from_fund: 'operating', to_fund: 'capital', amount_minor: 1.5 }, 'ondalik tutar'],
    [{ from_fund: 'operating', to_fund: 'capital', amount_minor: 1, transfer_date: dayOf(1, 20) }, 'gelecek tarih'],
    [{ from_fund: 'operating', to_fund: 'capital', amount_minor: 1, idempotency_key: undefined }, 'anahtar yok'],
  ];
  const badStatuses = [];
  for (const [over, label] of badTransfers) {
    const res = await call('POST', `${P(FS.code)}/fund-transfers`, MGR, { from_fund: 'operating', to_fund: 'capital', amount_minor: 1, transfer_date: TODAY, idempotency_key: key('ftb'), ...over });
    badStatuses.push([label, res.status, res.body?.code]);
  }
  check('K6o: gecersiz aktarim govdeleri 400 INVALID_BODY', badStatuses.every(([, status, code]) => status === 400 && code === 'INVALID_BODY'), badStatuses);
  await call('POST', `${P(FS.code)}/periods/${ym(-3)}/close`, MGR);
  const closedDate = await call('POST', `${P(FS.code)}/fund-transfers`, MGR, { from_fund: 'operating', to_fund: 'capital', amount_minor: 1, transfer_date: dayOf(-4, 10), idempotency_key: key('ftc') });
  check('K6p: kapali doneme aktarim yazilamaz: 409 PERIOD_CLOSED', closedDate.status === 409 && closedDate.body.code === 'PERIOD_CLOSED', closedDate.body);

  // ============================================================================================================
  // K7. yetki matrisi + IDOR
  // ============================================================================================================
  {
    const FS2 = await mkManaged('K Baska Site', { 'B Blok': 1 });
    await q(`INSERT INTO site_manager_sites (site_code, manager_user_code) VALUES ($1, $2)`, [FS2.code, MGR2]);
    const routes = [
      ['GET', '/funds', 'read'], ['GET', '/funds/operating/movements', 'read'], ['GET', '/fund-transfers', 'read'],
      ['POST', '/fund-transfers', 'write'], ['POST', '/fund-transfers/1/reverse', 'write'],
    ];
    const rows = [];
    for (const [method, suffix, kind] of routes) {
      const send = (user, site = FS) => call(method, `${P(site.code)}${suffix}`, user, method === 'GET' ? undefined : {});
      const ok = [];
      for (const user of [MGR, SUPER]) ok.push((await send(user)).status);
      const board = (await send(BOARD)).status;
      const denied = [];
      for (const user of [STAFF, RESIDENT, OUTSIDER]) denied.push([(await send(user)).status, (await send(user)).body?.code]);
      const other = await send(MGR2, FS);
      const unauth = await call(method, `${P(FS.code)}${suffix}`, null, method === 'GET' ? undefined : {});
      rows.push([method, suffix, ok, board, denied, other.status, other.body?.code, unauth.status]);
      void kind;
    }
    check(
      'K7a: yetki matrisi: yonetici / super yetkili (403 degil), kurul OKUR (yazamaz 403), gorevli / sakin / ilgisiz 403 FORBIDDEN_ROLE, baska site yoneticisi 403 FORBIDDEN_SITE, kimliksiz 401',
      rows.every(([method, , ok, board, denied, other, otherCode, unauth], i) =>
        ok.every((s) => s !== 403 && s !== 401) && (routes[i][2] === 'read' ? board !== 403 : board === 403) && denied.every(([s, c]) => s === 403 && c === 'FORBIDDEN_ROLE') && other === 403 && otherCode === 'FORBIDDEN_SITE' && unauth === 401 && method.length > 0),
      rows,
    );
    const foreignReverse = await call('POST', `${P(FS.code)}/fund-transfers/${t1.body.transfer.id}/reverse`, MGR2, { reason: 'x', idempotency_key: key('ftr') });
    check('K7b: baska sitenin yoneticisi (FS yolunda yetkisiz) aktarimi ters cevirmeye calisinca 403 FORBIDDEN_SITE; aktarim degismez', foreignReverse.status === 403 && foreignReverse.body.code === 'FORBIDDEN_SITE', foreignReverse.body);
    const idor = await call('POST', `${P(FS2.code)}/fund-transfers/${t1.body.transfer.id}/reverse`, MGR2, { reason: 'x', idempotency_key: key('ftr') });
    check('K7c: IDOR (kendi sitesinin yolu, baska sitenin aktarim kimligi): 404 FUND_TRANSFER_NOT_FOUND, aktarim degismez', idor.status === 404 && idor.body.code === 'FUND_TRANSFER_NOT_FOUND', idor.body);
    const boardWrite = await call('POST', `${P(FS.code)}/fund-transfers`, BOARD, { from_fund: 'operating', to_fund: 'capital', amount_minor: 1, transfer_date: TODAY, idempotency_key: key('ftb') });
    check('K7d: kurul aktarim yazamaz (403 FORBIDDEN_ROLE) ve veri yazilmaz', boardWrite.status === 403 && boardWrite.body.code === 'FORBIDDEN_ROLE');
    const noBoardNames = await funds(FS, '', BOARD);
    check('K7e: kurul kasa ozetini okur (200); ozet kisi adi icermez', noBoardNames.status === 200 && !/K A2|K Ana/.test(JSON.stringify(noBoardNames.body)));
  }

  // ============================================================================================================
  // K8. gecikme tazminati kasasi
  // ============================================================================================================
  {
    const LF = await mkManaged('K Tazminat Sitesi', { 'T Blok': 2 });
    const [L1, L2] = LF.ids;
    await setResponsible(L1, 'both');
    await setResponsible(L2, 'owner');
    await resident(LF, L1, 'owner', 'K T Malik');
    await resident(LF, L1, 'tenant', 'K T Kiraci');
    await resident(LF, L2, 'owner', 'K T Malik Iki');
    const lfAidat = await createDefinition(LF, { name: 'K T Aidat', amount_minor: 100000, start_period: ym(-2) });
    const lfFon = await createDefinition(LF, { name: 'K T Fon', amount_minor: 50000, start_period: ym(-2), fund: 'capital' });
    await postDefinition(LF, lfAidat.body.id, ym(-2));
    await postDefinition(LF, lfFon.body.id, ym(-2));
    for (const off of [-2, -1]) {
      const closed = await call('POST', `${P(LF.code)}/periods/${ym(off)}/close`, MGR);
      if (closed.status !== 200) throw new Error(`donem kapatilamadi: ${JSON.stringify(closed.body)}`);
    }
    await call('PUT', '/admin/finance-legal-gate', SUPER, { legal_ok: true });
    const lfSettings = await call('GET', `${P(LF.code)}/settings`, MGR);
    const lfEnable = await call('PUT', `${P(LF.code)}/settings`, MGR, { expected_settings_version: lfSettings.body.settings_version, late_fee: { enabled: true, start_period: ym(-1), rate_bp: 200, method: 'daily_30', grace_days: 0 } });
    if (lfEnable.status !== 200) throw new Error(`tazminat acilamadi: ${JSON.stringify(lfEnable.body)}`);
    const pv = await call('POST', `${P(LF.code)}/late-fee/preview`, MGR, { period: ym(-1) });
    const post = await call('POST', `${P(LF.code)}/late-fee/post`, MGR, { period: ym(-1), excluded_apartment_ids: [], expected_total_minor: pv.body.total_minor, expected_apartment_count: pv.body.apartment_count, expected_hash: pv.body.preview_hash, idempotency_key: key('lf') });
    const runId = post.body?.run?.id ?? 0;
    const feeRows = (await q(`SELECT apartment_id, account_party, fund FROM ledger_entries WHERE late_fee_run_id = $1 AND kind = 'charge' ORDER BY apartment_id, account_party`, [runId])).rows;
    const got = feeRows.map((r) => `${Number(r.apartment_id) === L1 ? 'L1' : 'L2'}:${r.account_party}:${r.fund}`);
    check(
      'K8a: tazminat satirinin kasasi = vadesi gecen anaparanin agirlikli oldugu kasa: L1 malik hesabi (yalniz fon borcu) capital, L1 kiraci hesabi (aidat) operating, L2 malik hesabi (aidat 100.000 > fon 50.000) operating',
      post.status === 201 && same(got, ['L1:owner:capital', 'L1:tenant:operating', 'L2:owner:operating']),
      { status: post.status, got },
    );
    const voided = await call('POST', `${P(LF.code)}/late-fee/runs/${runId}/void`, MGR, { reason: 'deneme', idempotency_key: key('lfv') });
    const reversals = (await q(`SELECT r.fund AS rfund, o.fund AS ofund FROM ledger_entries r INNER JOIN ledger_entries o ON o.id = r.reverses_entry_id WHERE o.late_fee_run_id = $1`, [runId])).rows;
    check('K8b: tazminat iptalinde ters kayitlar asilin kasasini tasir (3 satir, hicbiri NULL degil)', [200, 201].includes(voided.status) && reversals.length === 3 && reversals.every((r) => r.rfund !== null && r.rfund === r.ofund), reversals);
    const owner = await account(LF, L1, '?account_party=owner');
    const tenant = await account(LF, L1, '?account_party=tenant');
    check('K8c: L1 ekstresi: malik hesabinda tazminat dahil tum acik borc fon kasasinda degil, ters kayit sonrasi yalniz anapara kalir (kasa kirilimi SQL bakiyesine esit)',
      owner.body.funds.capital.balance_minor === owner.body.balance_minor && tenant.body.funds.operating.balance_minor === tenant.body.balance_minor, [owner.body.funds, tenant.body.funds]);
  }

  // ============================================================================================================
  // K9. eszamanli
  // ============================================================================================================
  {
    const C = await mkManaged('K Eszamanli Sitesi', { 'C Blok': 3 });
    const sameKey = key('par');
    const runs = await Promise.all(Array.from({ length: 8 }, () => call('POST', `${P(C.code)}/fund-transfers`, MGR, { from_fund: 'operating', to_fund: 'capital', amount_minor: 1234, transfer_date: TODAY, idempotency_key: sameKey })));
    const statuses = runs.map((r) => r.status).sort();
    const rows = Number((await q(`SELECT COUNT(*) AS n FROM finance_fund_transfers WHERE site_code = $1 AND idempotency_key = $2`, [C.code, sameKey])).rows[0].n);
    check('K9a: 8 eszamanli ayni-anahtarli aktarim => TEK satir (1 x 201, 7 x 200)', rows === 1 && statuses.filter((s) => s === 201).length === 1 && statuses.filter((s) => s === 200).length === 7, { statuses, rows });
    const original = runs.find((r) => r.status === 201).body.transfer;
    const reverses = await Promise.all(Array.from({ length: 6 }, () => call('POST', `${P(C.code)}/fund-transfers/${original.id}/reverse`, MGR, { reason: 'yaris', idempotency_key: key('parr') })));
    const rs = reverses.map((r) => `${r.status}:${r.body?.code ?? ''}`).sort();
    const reversalRows = Number((await q(`SELECT COUNT(*) AS n FROM finance_fund_transfers WHERE reverses_transfer_id = $1`, [original.id])).rows[0].n);
    check('K9b: 6 eszamanli ters aktarim (farkli anahtar) => TEK ters satir (1 x 201, 5 x 409 FUND_TRANSFER_ALREADY_REVERSED)', reversalRows === 1 && rs.filter((s) => s === '201:').length === 1 && rs.filter((s) => s === '409:FUND_TRANSFER_ALREADY_REVERSED').length === 5, rs);
    const deadlocksBefore = hooks.deadlocks;
    const defC = await createDefinition(C, { name: 'K C Aidat', amount_minor: 10000, start_period: ym(-1) });
    const accountC = (await call('POST', `${P(C.code)}/accounts`, MGR, { name: 'K C Kasa', kind: 'cash', opening_balance_minor: 50000, opening_date: ago(60), idempotency_key: key('acc') })).body.account;
    await postDefinition(C, defC.body.id, ym(-1));
    // Havuz bagi sinirli (pool max): her tur 6 yazma + 1 kasa ozeti ESZAMANLI (7 baglanti); turlar art arda
    const results = [];
    const ozet = [];
    for (let round = 0; round < 6; round += 1) {
      const mixed = [];
      for (const [index, aptId] of C.ids.entries()) {
        mixed.push(call('POST', `${P(C.code)}/payments`, MGR, { apartment_id: aptId, amount_minor: 1000 + round, entry_date: TODAY, method: 'cash', account_id: accountC.id, fund: round % 2 === 0 ? 'operating' : undefined, idempotency_key: key('mixp') }));
        mixed.push(call('POST', `${P(C.code)}/fund-transfers`, MGR, { from_fund: index % 2 === 0 ? 'operating' : 'capital', to_fund: index % 2 === 0 ? 'capital' : 'operating', amount_minor: 100 + round, transfer_date: TODAY, idempotency_key: key('mixt') }));
      }
      const summary = funds(C);
      results.push(...(await Promise.all(mixed)));
      ozet.push(await summary);
    }
    const bad = results.filter((r) => ![200, 201].includes(r.status));
    const final = await funds(C);
    check('K9c: karisik tur (6 tur x 6 eszamanli tahsilat / aktarim + her turda kasa ozeti): hepsi 200/201, 40P01 = 0, sonunda DEGISMEZ korunur (difference 0)', bad.length === 0 && ozet.every((r) => r.status === 200) && hooks.deadlocks === deadlocksBefore && final.body.balanced === true, { bad: bad.map((r) => [r.status, r.body?.code]).slice(0, 3), deadlocks: hooks.deadlocks - deadlocksBefore, final: final.body });
  }

  // ============================================================================================================
  // K10. makbuz anlik goruntusunde fund_split
  // ============================================================================================================
  {
    const receiptId = pay1.body.receipt?.id;
    const receipt = receiptId ? await call('GET', `${P(FS.code)}/receipts/${receiptId}`, MGR) : null;
    const cancelledSource = await call('POST', `${P(FS.code)}/receipts/${receiptId}/cancel`, MGR, { reason_code: 'issued_in_error', idempotency_key: key('rc') });
    check(
      'K10a: tahsilat makbuzunun anlik goruntusu verildigi andaki fund_split tasir (kisitsiz 50000 => capital 50000); iptal makbuzu ayni bilgiyi kopyalar',
      receipt?.status === 200 && sameSplit(receipt.body.snapshot.fund_split, { operating_minor: 0, capital_minor: 50000, advance_minor: 0 }) && (cancelledSource.status === 201 || cancelledSource.status === 200) &&
        sameSplit(cancelledSource.body.cancellation?.snapshot?.fund_split, { operating_minor: 0, capital_minor: 50000, advance_minor: 0 }),
      { receipt: receipt?.body?.snapshot, cancellation: cancelledSource.body?.cancellation?.snapshot },
    );
    const total = Number((await q(`SELECT COUNT(*) AS n FROM receipts WHERE site_code = $1 AND snapshot ? 'fund_split'`, [FS.code])).rows[0].n);
    check('K10b: yeni makbuzlarin hepsinde fund_split var', total >= 2, total);
  }

  // ============================================================================================================
  // K12. K3: tahsilat DUZELTME de hesap secimine tabidir (ters kayit AYNI islemde; iki tur acikken kisitsiz yeni tahsilat YAZILMAZ, ters kayit da kalmaz)
  // ============================================================================================================
  {
    // K3 oncesi surumde yazilabilen KISITSIZ bir tahsilat (A4'te Aidat + Fon birlikte acik) dogrudan SQL ile eklenir; hesap hareketi de eslenir.
    const inserted = await q(
      `INSERT INTO ledger_entries (site_code, apartment_id, kind, amount_minor, period, entry_date, payer_party, method, idempotency_key, created_by, account_party, source_kind, fund)
       VALUES ($1, $2, 'payment', -20000, date_trunc('month', CURRENT_DATE)::DATE, CURRENT_DATE, 'both', 'cash', $3, $4, 'owner', 'manual', NULL) RETURNING id`,
      [FS.code, A4, key('k12legacy'), MGR],
    );
    const legacyId = Number(inserted.rows[0].id);
    await q(
      `INSERT INTO account_movements (site_code, account_id, kind, amount_minor, movement_date, period, ledger_entry_id, created_by)
       VALUES ($1, $2, 'collection', 20000, CURRENT_DATE, date_trunc('month', CURRENT_DATE)::DATE, $3, $4)`,
      [FS.code, accountId, legacyId, MGR],
    );
    const reversalsOf = async (id) => Number((await q(`SELECT COUNT(*) AS n FROM ledger_entries WHERE site_code = $1 AND reverses_entry_id = $2`, [FS.code, id])).rows[0].n);
    const corrNoFund = await call('POST', `${P(FS.code)}/entries/${legacyId}/correct`, MGR, { amount_minor: 20000, entry_date: TODAY, method: 'cash', account_id: accountId, idempotency_key: key('k12a'), __strict: true });
    check(
      'K12a: kisitsiz asil tahsilatin duzeltmesi, ters kayit sonrasi iki tur (Aidat + Fon) acik kalirsa 400 FUND_CHOICE_REQUIRED; islem TAMAMEN geri alinir (ters kayit da yok, asil tahsilat duruyor)',
      corrNoFund.status === 400 && corrNoFund.body.code === 'FUND_CHOICE_REQUIRED' && corrNoFund.body.fund_choice?.choice_required === true && (await reversalsOf(legacyId)) === 0,
      corrNoFund.body,
    );
    const corrFund = await call('POST', `${P(FS.code)}/entries/${legacyId}/correct`, MGR, { amount_minor: 20000, entry_date: TODAY, method: 'cash', account_id: accountId, fund: 'capital', idempotency_key: key('k12b') });
    check(
      'K12b: hesap secilince (fund=capital) duzeltme yazilir: yeni tahsilat Fon kisitli, ters kayit asilin kisitini (kisitsiz) tasir; fund_split capital 20000',
      corrFund.status === 201 && corrFund.body.entry?.fund === 'capital' && corrFund.body.reversal?.fund === null && corrFund.body.fund_split?.capital_minor === 20000 && (await reversalsOf(legacyId)) === 1,
      corrFund.body,
    );
    // temizlik: A4'te yalniz 7777 + acik borc kalsin
    if (corrFund.body.entry?.id) await call('POST', `${P(FS.code)}/entries/${corrFund.body.entry.id}/reverse`, MGR, { reason: 'temizlik', idempotency_key: key('k12c') });
  }

  // ============================================================================================================
  // K11. 080 yukseltmesi VERI VARKEN: 001..079 kurulu ayri veritabaninda eski satirlar -> migrate.js 080 ve ensure yolu AYNI sonucu verir
  // ============================================================================================================
  {
    const pg = (await import('pg')).default;
    const fsMod = await import('node:fs');
    const osMod = await import('node:os');
    const pathMod = await import('node:path');
    const baseDb = `${process.env.DB_NAME}_k079`;
    const migrateDb = `${process.env.DB_NAME}_k080m`;
    const ensureDb = `${process.env.DB_NAME}_k080e`;
    const admin = new pg.Client(ctx.connectConfig(process.env.QA_ADMIN_DB || 'postgres'));
    await admin.connect();
    const recreate = async (name, template = null) => {
      await admin.query(`DROP DATABASE IF EXISTS "${name}" WITH (FORCE)`);
      await admin.query(`CREATE DATABASE "${name}"${template ? ` TEMPLATE "${template}"` : ''}`);
    };
    const dirBefore = fsMod.mkdtempSync(pathMod.join(osMod.tmpdir(), 'qa-funds-079-'));
    const dirOnly = fsMod.mkdtempSync(pathMod.join(osMod.tmpdir(), 'qa-funds-080-'));
    try {
      for (const name of ctx.migrationFiles()) {
        const number = Number(name.slice(0, name.indexOf('_')));
        if (number < 80) fsMod.copyFileSync(pathMod.join(ctx.MIGRATIONS_DIR, name), pathMod.join(dirBefore, name));
        if (number === 80) fsMod.copyFileSync(pathMod.join(ctx.MIGRATIONS_DIR, name), pathMod.join(dirOnly, name));
      }
      await recreate(baseDb);
      const baseOk = ctx.runMigrate(baseDb, dirBefore);
      const base = new pg.Client(ctx.connectConfig(baseDb));
      await base.connect();
      const siteCode = 1000000980;
      const emptySite = 1000000981;
      await base.query(`INSERT INTO sites (site_code, name, mqtt_site_id) VALUES ($1, 'K Yukseltme', generate_unique_mqtt_site_id()), ($2, 'K Yukseltme Bos', generate_unique_mqtt_site_id())`, [siteCode, emptySite]);
      const blockId = Number((await base.query(`INSERT INTO site_blocks (site_code, block_name, sort_order) VALUES ($1, 'Y Blok', 1) RETURNING id`, [siteCode])).rows[0].id);
      const apt = Number((await base.query(`INSERT INTO apartments (site_code, block_id, unit_label, sort_order, responsible_party) VALUES ($1, $2, 'Daire 1', 1, 'both') RETURNING id`, [siteCode, blockId])).rows[0].id);
      const def = async (name, kind, chargeParty) =>
        Number(
          (
            await base.query(
              `INSERT INTO fee_definitions (site_code, name, kind, distribution, amount_minor, due_day, start_period, target_type, charge_party) VALUES ($1, $2, $3, 'fixed', 1000, $4, $5, 'site', $6) RETURNING id`,
              [siteCode, name, kind, kind === 'recurring' ? 1 : null, monthStart(-2), chargeParty],
            )
          ).rows[0].id,
        );
      const defOccupant = await def('Y Aidat', 'recurring', 'occupant');
      const defOwner = await def('Y Asansor', 'recurring', 'owner');
      const defNullOneTime = await def('Y Ek', 'one_time', null);
      const old = async (kind, amount, extra = {}) =>
        Number(
          (
            await base.query(
              `INSERT INTO ledger_entries (site_code, apartment_id, kind, amount_minor, period, entry_date, due_date, payer_party, definition_id, method, source_kind, source_id) VALUES ($1, $2, $3, $4, $5, $6, $6, 'both', $7, $8, $9, $10) RETURNING id`,
              [siteCode, apt, kind, amount, monthStart(-1), ago(40), extra.definition ?? null, kind === 'payment' ? 'cash' : null, extra.sourceKind ?? null, extra.sourceId ?? null],
            )
          ).rows[0].id,
        );
      const cOccupant = await old('charge', 10000, { definition: defOccupant });
      const cOwner = await old('charge', 20000, { definition: defOwner });
      const cNull = await old('charge', 3000, { definition: defNullOneTime });
      const cOpening = await old('charge', 4000, { sourceKind: 'opening', sourceId: 1 });
      const pOld = await old('payment', -5000);
      await base.query(`INSERT INTO ledger_entries (site_code, apartment_id, kind, amount_minor, period, entry_date, due_date, payer_party, reverses_entry_id) VALUES ($1, $2, 'reversal', -10000, $3, $4, $4, 'both', $5)`, [siteCode, apt, monthStart(0), TODAY, cOccupant]);
      await base.query(`INSERT INTO expense_categories (site_code, name, is_system, sort_order) VALUES ($1, 'Y Eski Kategori', FALSE, 1)`, [siteCode]);
      const before = (await base.query(`SELECT COUNT(*)::INT AS n, SUM(amount_minor)::TEXT AS s FROM ledger_entries WHERE site_code = $1`, [siteCode])).rows[0];
      await base.end();

      await recreate(migrateDb, baseDb);
      await recreate(ensureDb, baseDb);
      const migrated = ctx.runMigrate(migrateDb, dirOnly);
      const ensureClient = new pg.Client(ctx.connectConfig(ensureDb));
      await ensureClient.connect();
      const ensured = await ensureFinanceFundsSchema(ensureClient);
      const ensuredAgain = await ensureFinanceFundsSchema(ensureClient);

      const catalog = async (client) => ({
        columns: (await client.query(`SELECT table_name, column_name, data_type, is_nullable, column_default FROM information_schema.columns WHERE table_schema = 'public' AND (table_name = 'finance_fund_transfers' OR (column_name = 'fund' AND table_name IN ('ledger_entries', 'expense_categories', 'expenses'))) ORDER BY 1, 2`)).rows,
        constraints: (await client.query(`SELECT conrelid::regclass::text AS tbl, conname, pg_get_constraintdef(oid) AS def, convalidated FROM pg_constraint WHERE conname LIKE '%fund%' ORDER BY 1, 2`)).rows,
        indexes: (await client.query(`SELECT indexname, indexdef FROM pg_indexes WHERE schemaname = 'public' AND (tablename = 'finance_fund_transfers' OR indexname LIKE '%fund%') ORDER BY 1`)).rows,
        triggers: (await client.query(`SELECT tgname, regexp_replace(pg_get_triggerdef(oid), '\\s+', ' ', 'g') AS def FROM pg_trigger WHERE NOT tgisinternal AND tgname LIKE '%fund%' ORDER BY 1`)).rows,
        functions: (await client.query(`SELECT proname, regexp_replace(prosrc, '\\s+', ' ', 'g') AS src FROM pg_proc WHERE proname LIKE '%fund%' AND pronamespace = 'public'::regnamespace ORDER BY 1`)).rows,
      });
      const viaEnsure = await catalog(ensureClient);
      const viaEnsureData = {
        ledger: (await ensureClient.query(`SELECT COUNT(*)::INT AS n, SUM(amount_minor)::TEXT AS s, COUNT(fund)::INT AS filled FROM ledger_entries WHERE site_code = $1`, [siteCode])).rows[0],
        capitals: (await ensureClient.query(`SELECT site_code, name, is_system, fund FROM expense_categories WHERE fund = 'capital' ORDER BY site_code`)).rows,
        oldCategory: (await ensureClient.query(`SELECT fund FROM expense_categories WHERE site_code = $1 AND name = 'Y Eski Kategori'`, [siteCode])).rows[0],
      };
      await ensureClient.end();
      const migClient = new pg.Client(ctx.connectConfig(migrateDb));
      await migClient.connect();
      const viaMigrate = await catalog(migClient);
      const viaMigrateData = {
        ledger: (await migClient.query(`SELECT COUNT(*)::INT AS n, SUM(amount_minor)::TEXT AS s, COUNT(fund)::INT AS filled FROM ledger_entries WHERE site_code = $1`, [siteCode])).rows[0],
        capitals: (await migClient.query(`SELECT site_code, name, is_system, fund FROM expense_categories WHERE fund = 'capital' ORDER BY site_code`)).rows,
        oldCategory: (await migClient.query(`SELECT fund FROM expense_categories WHERE site_code = $1 AND name = 'Y Eski Kategori'`, [siteCode])).rows[0],
      };
      // eski satirlarin okumada turetilen kasasi (geri doldurma yok): aidat operating, asansor (owner) capital, tek seferlik varsayilan owner => capital, devir operating
      const rowsForOracle = (
        await migClient.query(
          `SELECT l.id, l.kind, l.amount_minor::TEXT AS amount_minor, to_char(l.entry_date, 'YYYY-MM-DD') AS entry_date, to_char(l.due_date, 'YYYY-MM-DD') AS due_date, l.reverses_entry_id, l.fund, l.source_kind, l.late_fee_run_id, l.definition_id, fd.charge_party AS def_charge_party, fd.kind AS def_kind
           FROM ledger_entries l LEFT JOIN fee_definitions fd ON fd.id = l.definition_id WHERE l.site_code = $1 ORDER BY l.id`,
          [siteCode],
        )
      ).rows;
      const derived = Object.fromEntries(rowsForOracle.map((r) => [Number(r.id), toAllocatorEntry(r).fund]));
      await migClient.end();

      check('K11a: 001..079 + eski veri hazir (6 defter satiri); 080 migration dosyasi ve ensure yolu hatasiz uygulandi', baseOk && migrated && ensured.length > 10 && ensuredAgain.length === 0, { baseOk, migrated, ensured: ensured.length, ensuredAgain });
      check('K11b: 080 sema sonucu migrate yolu = ensure yolu (sutun, kisit, indeks, tetikleyici, islev birebir)', same(viaMigrate, viaEnsure), { m: viaMigrate.constraints.length, e: viaEnsure.constraints.length });
      check(
        'K11c: eski defter satirlari DEGISMEDI (sayi ve toplam ayni) ve kasa GERI DOLDURULMADI (hepsi NULL); eski kategori operating kaldi',
        viaMigrateData.ledger.n === before.n && viaMigrateData.ledger.s === before.s && viaMigrateData.ledger.filled === 0 && viaEnsureData.ledger.filled === 0 && viaMigrateData.oldCategory.fund === 'operating',
        { before, viaMigrateData },
      );
      check(
        'K11d: okumada turetilen eski kasa: aylik oturan => operating; aylik owner => capital; tek seferlik varsayilan owner => capital; devir => operating; ters kayit asilin kasasini izler',
        derived[cOccupant] === 'operating' && derived[cOwner] === 'capital' && derived[cNull] === 'capital' && derived[cOpening] === 'operating' && derived[pOld] === null,
        derived,
      );
      check(
        'K11e: sistem kategorisi YALNIZ kategorisi olan siteye eklendi (1 adet, capital + sistem); kategorisiz siteye eklenmedi; iki yol ayni',
        same(viaMigrateData.capitals.map((c) => [Number(c.site_code), c.name, c.is_system, c.fund]), [[siteCode, CAPITAL_CATEGORY_NAME, true, 'capital']]) && same(viaMigrateData.capitals, viaEnsureData.capitals),
        viaMigrateData.capitals,
      );
    } finally {
      await admin.query(`DROP DATABASE IF EXISTS "${baseDb}" WITH (FORCE)`).catch(() => {});
      await admin.query(`DROP DATABASE IF EXISTS "${migrateDb}" WITH (FORCE)`).catch(() => {});
      await admin.query(`DROP DATABASE IF EXISTS "${ensureDb}" WITH (FORCE)`).catch(() => {});
      await admin.end();
      fsMod.rmSync(dirBefore, { recursive: true, force: true });
      fsMod.rmSync(dirOnly, { recursive: true, force: true });
    }
  }

  // ============================================================================================================
  // K12. Fon tahakkukunun dayanagi (090; docs/PLATFORM_FINANS_KARAR_BAGI.md): Karar Defteri ACIK sitede kesin karar, KAPALI sitede gerekce
  // ============================================================================================================
  {
    console.log('--- K12. Fon tahakkukunun dayanagi (Karar Defteri kaydi ya da gerekce, 090) ---');
    const { ensureFinanceRunDecisionSchema } = await import('../src/modules/finance_run_decision_schema.js');
    const siteSvc = await import('../src/services/site_service.js');
    const year = Number(TODAY.slice(0, 4));
    const D = await mkManaged('K Dayanak Sitesi', { 'S Blok': 3 });
    const D2 = await mkManaged('K Dayanak Sitesi 2', { 'S Blok': 1 });
    const [d1] = D.ids;
    const newDecision = (site, { no, title, visibility = 'sakinler', status = 'kesin' }) =>
      q(
        `INSERT INTO board_decisions (site_code, year, decision_no, meeting_type, meeting_date, title, body, vote_result, visibility, status, finalized_at)
         VALUES ($1, $2, $3, 'yonetim_kurulu', $4, $5, 'Karar metni', 'kabul', $6, $7, ${status === 'kesin' ? 'NOW()' : 'NULL'}) RETURNING id`,
        [site.code, year, status === 'kesin' ? no : null, TODAY, title, visibility, status],
      ).then((r) => Number(r.rows[0].id));
    const finalId = await newDecision(D, { no: 41, title: 'K Dayanak Asansor Karari' });
    const internalId = await newDecision(D, { no: 42, title: 'K GIZLI BASLIK', visibility: 'yonetim' });
    const draftId = await newDecision(D, { no: 0, title: 'K Taslak Karar', status: 'taslak' });
    const foreignId = await newDecision(D2, { no: 1, title: 'K Baska Sitenin Karari' });
    const kCharge = async (site, extra = {}, keyOverride = null) => {
      const body = { name: 'K Dayanak Borcu', distribution: 'fixed', amount_minor: 1000, target: { type: 'site' }, ...extra };
      const pv = await call('POST', `${P(site.code)}/charges/preview`, MGR, body);
      const idempotencyKey = keyOverride ?? key('dy');
      const post = await call('POST', `${P(site.code)}/charges`, MGR, { ...body, expected_total_minor: pv.body.total_minor, expected_apartment_count: pv.body.apartment_count, expected_hash: pv.body.preview_hash, idempotency_key: idempotencyKey });
      return { pv, post, key: idempotencyKey };
    };
    const runRow = async (runId) => (await q(`SELECT decision_id::TEXT AS decision_id, decision_reason FROM fee_runs WHERE id = $1`, [runId])).rows[0];
    const wroteRuns = async (site) => Number((await q(`SELECT COUNT(*)::INT AS n FROM fee_runs WHERE site_code = $1`, [site.code])).rows[0].n);

    const cols = (await q(`SELECT column_name, is_nullable, column_default FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'fee_runs' AND column_name IN ('decision_id', 'decision_reason') ORDER BY column_name`)).rows;
    const cons = (await q(`SELECT conname, convalidated, pg_get_constraintdef(oid) AS def FROM pg_constraint WHERE conname IN ('fee_runs_decision_fkey', 'chk_fee_runs_decision') ORDER BY conname`)).rows;
    check(
      'K12a: fee_runs.decision_id / decision_reason NULL olabilir (varsayilansiz); CHECK dogrulanmis; bilesik FK (site_code, decision_id) -> board_decisions NO ACTION',
      same(cols.map((c) => [c.column_name, c.is_nullable, c.column_default]), [['decision_id', 'YES', null], ['decision_reason', 'YES', null]]) &&
        cons.length === 2 && cons.every((c) => c.convalidated === true) && /FOREIGN KEY \(site_code, decision_id\) REFERENCES board_decisions\(site_code, id\)/.test(cons[1].def),
      { cols, cons },
    );
    const ensureClient = await pool.connect();
    let ensured;
    try {
      ensured = await ensureFinanceRunDecisionSchema(ensureClient);
    } finally {
      ensureClient.release();
    }
    check('K12b: ensureFinanceRunDecisionSchema ikinci kez HICBIR adim uygulamaz (idempotent)', same(ensured, []), ensured);

    // --- Karar Defteri KAPALI (varsayilan): gerekce zorunlu
    const offNone = await kCharge(D, { name: 'K Dayanak Borcu 1', decision_reason: null });
    check('K12c: Karar Defteri KAPALI + gerekcesiz Fon borcu: onizleme mode=reason, onay 400 DECISION_REASON_REQUIRED, hicbir sey yazilmaz', offNone.pv.body.decision_requirement?.mode === 'reason' && offNone.post.status === 400 && offNone.post.body.code === 'DECISION_REASON_REQUIRED' && (await wroteRuns(D)) === 0, [offNone.pv.body.decision_requirement, offNone.post.body]);
    const offDecision = await kCharge(D, { name: 'K Dayanak Borcu 2', decision_id: finalId });
    check('K12d: Karar Defteri KAPALI iken decision_id gonderilirse 400 DECISION_MODULE_OFF (sessizce yok sayilmaz)', offDecision.post.status === 400 && offDecision.post.body.code === 'DECISION_MODULE_OFF' && (await wroteRuns(D)) === 0, offDecision.post.body);
    const offReason = await kCharge(D, { name: 'K Dayanak Borcu 3', decision_reason: '  Yonetim kurulunun 14 Ekim tarihli   karari ' });
    const offRow = offReason.post.status === 201 ? await runRow(offReason.post.body.run.id) : null;
    check('K12e: Karar Defteri KAPALI + gerekce: 201; gerekce temizlenip saklanir (karar yok); yanitta run.decision.reason', offReason.post.status === 201 && offRow.decision_id === null && offRow.decision_reason === 'Yonetim kurulunun 14 Ekim tarihli karari' && offReason.post.body.run.decision.reason === offRow.decision_reason, [offReason.post.body, offRow]);
    const tooShort = await kCharge(D, { name: 'K Dayanak Borcu 4', decision_reason: 'ab' });
    check('K12f: 3 karakterden kisa gerekce 400 INVALID_BODY', tooShort.post.status === 400 && tooShort.post.body.code === 'INVALID_BODY', tooShort.post.body);

    // --- Karar Defteri ACIK: kesin karar zorunlu
    const enabled = await call('PUT', `/manager/sites/${D.code}/modules/decision_book`, SUPER, { enabled: true });
    check('K12g: Karar Defteri modulu acildi', enabled.status === 200, enabled.body);
    const before = await wroteRuns(D);
    const onNone = await kCharge(D, { name: 'K Dayanak Borcu 5', decision_reason: null });
    const onReasonOnly = await kCharge(D, { name: 'K Dayanak Borcu 6', decision_reason: 'Sadece gerekce yeterli degil' });
    check('K12h: Karar Defteri ACIK + kararsiz Fon borcu 400 DECISION_REQUIRED (onizleme mode=decision); yalniz gerekce de 400; hicbir sey yazilmaz', onNone.pv.body.decision_requirement?.mode === 'decision' && onNone.post.status === 400 && onNone.post.body.code === 'DECISION_REQUIRED' && onReasonOnly.post.status === 400 && onReasonOnly.post.body.code === 'DECISION_REQUIRED' && (await wroteRuns(D)) === before, [onNone.post.body, onReasonOnly.post.body]);
    const onDraft = await kCharge(D, { name: 'K Dayanak Borcu 7', decision_id: draftId });
    const onForeign = await kCharge(D, { name: 'K Dayanak Borcu 8', decision_id: foreignId });
    const onMissing = await kCharge(D, { name: 'K Dayanak Borcu 9', decision_id: 987654321 });
    check('K12i: taslak karar 409 DECISION_NOT_FINAL; baska sitenin karari ve olmayan karar AYNI 404 DECISION_NOT_FOUND (IDOR yok)', onDraft.post.status === 409 && onDraft.post.body.code === 'DECISION_NOT_FINAL' && onForeign.post.status === 404 && onForeign.post.body.code === 'DECISION_NOT_FOUND' && onMissing.post.status === 404 && onMissing.post.body.code === 'DECISION_NOT_FOUND' && (await wroteRuns(D)) === before, [onDraft.post.body, onForeign.post.body, onMissing.post.body]);
    const onOk = await kCharge(D, { name: 'K Dayanak Borcu 10', decision_id: finalId });
    const onRow = onOk.post.status === 201 ? await runRow(onOk.post.body.run.id) : null;
    check('K12j: kesin karar ile 201; fee_runs.decision_id yazilir; yanitta run.decision karar numarasi ve basligi', onOk.post.status === 201 && onRow.decision_id === String(finalId) && onOk.post.body.run.decision.number_label === `${year}/41` && onOk.post.body.run.decision.title === 'K Dayanak Asansor Karari', [onOk.post.body, onRow]);
    const replay = await kCharge(D, { name: 'K Dayanak Borcu 10', decision_id: finalId }, onOk.key);
    const conflict = await kCharge(D, { name: 'K Dayanak Borcu 10', decision_id: internalId }, onOk.key);
    check('K12k: ayni anahtar + ayni dayanak tekrari 200 ayni kayit (dayanagiyla); ayni anahtar + FARKLI karar 409 IDEMPOTENCY_CONFLICT', replay.post.status === 200 && replay.post.body.run.id === onOk.post.body.run.id && replay.post.body.run.decision?.number_label === `${year}/41` && conflict.post.status === 409 && conflict.post.body.code === 'IDEMPOTENCY_CONFLICT', [replay.post.status, conflict.post.status, conflict.post.body.code]);
    const operatingOk = await kCharge(D, { name: 'K Dayanak Aidat Borcu', fund: 'operating', decision_reason: null });
    const operatingRow = operatingOk.post.status === 201 ? await runRow(operatingOk.post.body.run.id) : null;
    check('K12l: Isletme (Aidat) hesabi borcu dayanaksiz yazilir (onizleme mode=none); dayanak kolonlari NULL', operatingOk.pv.body.decision_requirement?.mode === 'none' && operatingOk.post.status === 201 && operatingRow.decision_id === null && operatingRow.decision_reason === null && !('decision' in operatingOk.post.body.run), [operatingOk.pv.body.decision_requirement, operatingOk.post.body.run]);

    // --- veritabani butunlugu
    const foreignFk = await failCode(`INSERT INTO fee_runs (site_code, definition_id, period, total_minor, apartment_count, decision_id) SELECT site_code, definition_id, (period + INTERVAL '1 month')::DATE, total_minor, apartment_count, $2 FROM fee_runs WHERE id = $1`, [onOk.post.body.run.id, foreignId]);
    const longReason = await failCode(`INSERT INTO fee_runs (site_code, definition_id, period, total_minor, apartment_count, decision_reason) SELECT site_code, definition_id, (period + INTERVAL '1 month')::DATE, total_minor, apartment_count, repeat('x', 301) FROM fee_runs WHERE id = $1`, [onOk.post.body.run.id]);
    const updateMsg = await failMessage(`UPDATE fee_runs SET decision_reason = 'degisti' WHERE id = $1`, [onOk.post.body.run.id]);
    const deleteDecision = await failMessage(`DELETE FROM board_decisions WHERE id = $1`, [finalId]);
    check('K12m: baska sitenin kararina FK 23503; 301 karakter gerekce 23514; dayanak sonradan DEGISTIRILEMEZ (append-only); baglanti kesin karar silinemez', foreignFk === '23503' && longReason === '23514' && /append-only/.test(updateMsg ?? '') && /immutable/.test(deleteDecision ?? ''), { foreignFk, longReason, updateMsg, deleteDecision });

    // --- ekstre, sakin, denetim
    const internalOk = await kCharge(D, { name: 'K Dayanak Borcu 11', decision_id: internalId });
    const owner = await resident(D, d1, 'owner', 'K Dayanak Sakin');
    const account1 = await account(D, d1, '?account_party=owner');
    const statement = account1.body.items.filter((e) => e.kind === 'charge' && e.definition_name === 'K Dayanak Borcu 10');
    check('K12n: yonetici ekstresinde borc satirinda Entry.decision (numara, baslik); dayanaksiz satirda alan yok', account1.status === 200 && statement.length === 1 && statement[0].decision?.number_label === `${year}/41` && statement[0].decision?.title === 'K Dayanak Asansor Karari' && account1.body.items.filter((e) => e.definition_name === 'K Dayanak Aidat Borcu').every((e) => !('decision' in e)), account1.body.items.map((e) => [e.definition_name, e.decision]));
    const view = await call('GET', '/app/my-finance', owner.user);
    const items = view.body?.items?.[0]?.breakdown?.items ?? [];
    const byName = Object.fromEntries(items.map((i) => [i.name, i]));
    check(
      'K12o: sakin Borcum kalem dokumu: her odenmemis kalemin kaynagi (donem, tur, hesap) ve dayanagi; yonetim gorunurluklu kararin BASLIGI sizmaz; gerekce gorunur; kalan tutarlar bakiyeye esit',
      view.status === 200 && byName['K Dayanak Borcu 10']?.decision?.number_label === `${year}/41` && byName['K Dayanak Borcu 10']?.decision?.title === 'K Dayanak Asansor Karari' && byName['K Dayanak Borcu 11']?.decision?.number_label === `${year}/42` && byName['K Dayanak Borcu 11']?.decision?.title === null && byName['K Dayanak Borcu 3']?.decision?.reason === 'Yonetim kurulunun 14 Ekim tarihli karari' && byName['K Dayanak Aidat Borcu']?.fund === 'operating' && byName['K Dayanak Borcu 10']?.fund === 'capital' && byName['K Dayanak Borcu 10']?.type === 'one_time' && items.reduce((sum, i) => sum + i.remaining_minor, 0) === view.body.items[0].balance_minor && !JSON.stringify(view.body).includes('K GIZLI BASLIK') && !/run_decision|"visibility"/.test(JSON.stringify(view.body)),
      byName,
    );
    const auditRows = (await q(`SELECT details FROM audit_log WHERE site_code = $1 AND action = 'finance.charge.posted' ORDER BY id`, [D.code])).rows.map((r) => r.details);
    check('K12p: denetim kaydinda decision_id ve decision_reason_given var, gerekce METNI yok', auditRows.some((d) => d.decision_id === finalId) && auditRows.some((d) => d.decision_reason_given === true) && !JSON.stringify(auditRows).includes('Yonetim kurulunun'), auditRows);
    check('K12q: Karar Defteri KAPATILDIKTAN sonra da baglanti okunur (ekstrede karar numarasi kalir)', (await call('PUT', `/manager/sites/${D.code}/modules/decision_book`, SUPER, { enabled: false })).status === 200 && (await account(D, d1, '?account_party=owner')).body.items.some((e) => e.decision?.number_label === `${year}/41`));

    // --- site silme: karar bagli calistirma olan site silinir (NO ACTION FK ayni ifadede iki tabloyu da siler)
    let deleteError = null;
    try {
      await siteSvc.deleteSitePermanently(D.code, { user_code: SUPER, userCode: SUPER, id: SUPER, role: 'super_user', full_name: 'K Super' });
    } catch (error) {
      deleteError = error?.message ?? String(error);
    }
    const left = (await q(`SELECT (SELECT COUNT(*) FROM fee_runs WHERE site_code = $1)::INT AS runs, (SELECT COUNT(*) FROM board_decisions WHERE site_code = $1)::INT AS decisions`, [D.code])).rows[0];
    check('K12r: karar bagli calistirmasi olan site deleteSitePermanently ile SILINIR (kararlar ve calistirmalar CASCADE; FK / tetikleyici engellemez); kalinti yok', deleteError === null && left.runs === 0 && left.decisions === 0, { deleteError, left });
  }

  const total = hooks.deadlocks - deadlocksAtStart;
  check('K-son: bolum boyunca kilit cikmazi (40P01) = 0', total === 0, total);
  void ctx;
}
