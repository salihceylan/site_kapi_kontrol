// Finans QA bolumu: S. Sakin kapsami (KVKK olculuk + dogru bakiye). scripts/qa_finance4b.mjs tarafindan yuklenir (t = ortak test ortami).
// Kural: sakin dairenin defterini kendi tasinma ayindan itibaren gorur (dayanak ayi: tazminatta hesaplanan ay, ters kayitta asil kaydin
// ayi); bakiye mahsup kuraliyla (vadesi en eski borctan) hesaplanir (finance_resident_view.residentView). Yonetici tum defteri gorur.

export default async function sectionResidentScope(t) {
  const { check, q, call, pool, sleep, TODAY, dayNo, isoOf, monthStart, ym, mkManaged, mkUser, addPerson, addResidency, P, key, pay, users } = t;
  const { MGR } = users;
  console.log('--- S. sakin kapsami ---');

  const site = await mkManaged('F4B Kapsam Sitesi', { 'K Blok': 7 });
  const [x1, x2, x3, x4, x5, x6, x7] = site.ids;
  const M3 = monthStart(-3);
  const M1 = monthStart(-1);
  const M0 = monthStart(0);
  const day = (startIso, n) => isoOf(dayNo(startIso) + n - 1);
  const FUTURE = isoOf(dayNo(TODAY) + 5);
  await q(`UPDATE apartments SET responsible_party = 'both' WHERE id = ANY($1::BIGINT[])`, [site.ids]);

  // Kisiler
  const OLD_TENANT = await mkUser('Kapsam Eski Kiraci', 'individual');
  const NEW_TENANT = await mkUser('Kapsam Yeni Kiraci', 'individual');
  const OWNER = await mkUser('Kapsam Malik', 'apartment_owner');
  const NO_DATE = await mkUser('Kapsam Tarihsiz Sakin', 'individual');
  const ONBOARD = await mkUser('Kapsam Gecis Sakini', 'individual');
  const NEW_TENANT2 = await mkUser('Kapsam Yeni Kiraci Iki', 'individual');
  await addResidency(site.code, x1, await addPerson(site.code, { user: OLD_TENANT }), 'tenant', { current: false, moveIn: day(monthStart(-6), 1) });
  await addResidency(site.code, x1, await addPerson(site.code, { user: NEW_TENANT }), 'tenant', { moveIn: day(M1, 10) });
  await addResidency(site.code, x1, await addPerson(site.code, { user: OWNER }), 'owner');
  await addResidency(site.code, x2, await addPerson(site.code, { user: NO_DATE }), 'resident', { moveIn: null });
  await addResidency(site.code, x3, await addPerson(site.code, { user: ONBOARD }), 'resident', { moveIn: null });
  await addResidency(site.code, x4, await addPerson(site.code, { user: NEW_TENANT2 }), 'tenant', { moveIn: day(M1, 10) });

  // İP-1A (G12): kiracılı (both) dairelerde aidat KİRACI hesabına yazılır (gerçek kod: borç tarihinde etkin kiracı varsa); kiracı senaryoları (x1, x4, x7)
  // satırları kiracı hesabında kurar. Tahsilatlar API'den (hesap verilmeden): sunucu vadesi en eski açık borcu olan hesabı (kiracı) seçer.
  const TENANT_APTS = new Set();
  const insert = async (apartmentId, kind, amount, period, entryDate, due, extra = {}) =>
    Number(
      (
        await q(
          `INSERT INTO ledger_entries (site_code, apartment_id, kind, amount_minor, period, entry_date, due_date, payer_party, method, reverses_entry_id, late_fee_run_id, account_party)
           VALUES ($1, $2, $3, $4, $5, $6, $7, 'both', $8, $9, $10, $11) RETURNING id`,
          [site.code, apartmentId, kind, amount, period, entryDate, due, kind === 'payment' ? 'cash' : null, extra.reverses ?? null, extra.lateFeeRun ?? null, TENANT_APTS.has(apartmentId) ? 'tenant' : null],
        )
      ).rows[0].id,
    );
  for (const id of [x1, x4, x5, x7]) TENANT_APTS.add(id);

  // --- Daire 1: onceki kiraci (M-3), yeni kiraci (M-1'den), uzun suredir malik
  const c1 = await insert(x1, 'charge', 1000, M3, M3, day(M3, 15));
  const p1res = await pay(site, x1, 500, { entry_date: day(M3, 20) }); // onceki kiracinin kismi odemesi (makbuz R1)
  const p1 = Number(p1res.body?.entry?.id);
  const r1 = Number(p1res.body?.receipt?.id);
  const p1Period = (await q(`SELECT to_char(period, 'YYYY-MM-DD') AS p FROM ledger_entries WHERE id = $1`, [p1])).rows[0]?.p;
  check('S0: geriye tarihli tahsilat 201 + makbuz; kaydin ayi tahsilat tarihinin ayi', p1res.status === 201 && Number.isInteger(r1) && p1Period === M3, { status: p1res.status, p1Period });
  const cx = await insert(x1, 'charge', 300, M3, M3, day(M3, 16));
  const c2 = await insert(x1, 'charge', 1000, M1, M1, day(M1, 15));
  const c3 = await insert(x1, 'charge', 1000, M0, M0, FUTURE);
  const p2res = await pay(site, x1, 1000, {}); // yeni kiracinin odemesi (makbuz R2); 500'u mahsup kuralina gore eski borca gider
  const p2 = Number(p2res.body?.entry?.id);
  const r2 = Number(p2res.body?.receipt?.id);
  const rev = await insert(x1, 'reversal', -300, M0, TODAY, day(M3, 16), { reverses: cx }); // eski borcun BUGUN iptali

  // Gecikme tazminati: M-3 icin hesaplanan, BU AY yazilan kalem (dayanak ayi M-3).
  await q(`INSERT INTO finance_period_closures (site_code, period, closed_by) VALUES ($1, $2, $3)`, [site.code, M3, MGR]);
  await q(
    `INSERT INTO finance_settings (site_code, late_fee_enabled, late_fee_start_period) VALUES ($1, TRUE, $2)
     ON CONFLICT (site_code) DO UPDATE SET late_fee_enabled = TRUE, late_fee_start_period = $2, settings_version = finance_settings.settings_version + 1`,
    [site.code, M3],
  );
  const runId = Number(
    (
      await q(
        `INSERT INTO late_fee_runs (site_code, period, params, total_minor, apartment_count, preview_hash, idempotency_key, request_fingerprint, posted_by)
         VALUES ($1, $2, $3::jsonb, 100, 1, $4, $5, $4, $6) RETURNING id`,
        [site.code, M3, JSON.stringify({ rate_bp: 500, method: 'daily_30', grace_days: 0, settings_version: 2 }), 'a'.repeat(64), key('lf'), MGR],
      )
    ).rows[0].id,
  );
  const lf = await insert(x1, 'charge', 100, M0, TODAY, TODAY, { lateFeeRun: runId });
  await q(
    `INSERT INTO late_fee_run_lines (site_code, run_id, apartment_id, apartment_label, amount_minor, base_day_minor, peak_overdue_minor, breakdown, ledger_entry_id)
     VALUES ($4, $1, $2, 'K Blok - Daire 1', 100, 60000, 500, '[]'::jsonb, $3)`,
    [runId, x1, lf, site.code],
  );

  // --- Daire 2: tarihsiz kayit (kayit gunu = bugun -> kapsam bu ay)
  const d2old = await insert(x2, 'charge', 700, M1, M1, day(M1, 15));
  const d2new = await insert(x2, 'charge', 300, M0, M0, FUTURE);
  // --- Daire 3: siteye gecis: tarihsiz yukleme (kapsam bu ay) + gecen ay ve bu ay aidati bugun yazildi + 2000 odeme
  const d3sep = await insert(x3, 'charge', 1000, M1, TODAY, day(M1, 15));
  const d3oct = await insert(x3, 'charge', 1000, M0, TODAY, FUTURE);
  const d3pay = Number((await pay(site, x3, 2000, {})).body?.entry?.id);
  // --- Daire 4: onceki kiracinin GEC odemesi (yeni kiracinin doneminde, eski borca mahsup)
  const d4old = await insert(x4, 'charge', 1000, M3, M3, day(M3, 15));
  const d4mine = await insert(x4, 'charge', 1000, M1, M1, day(M1, 15));
  const d4late = Number((await pay(site, x4, 1000, {})).body?.entry?.id);

  const ids = (list) => (list ?? []).map((e) => Number(e.id)).sort((a, b) => a - b);
  const same = (a, b) => JSON.stringify(a) === JSON.stringify([...b].sort((m, n) => m - n));

  // --- S1. yeni kiraci: kendi donemi + mahsup kurali
  const tenant = await call('GET', '/app/my-finance', NEW_TENANT);
  const tItem = tenant.body?.items?.find((i) => i.apartment_id === x1);
  check(
    'S1: yeni kiraci Borcum: odemesinin 500\'u eski borca mahsup edildi -> borcu 1500 (c2 kalan 500 + c3 1000), vadesi gecmis 500; onceki kiracinin borcu/odemesi, eski borcun iptali ve eski aya ait tazminat GORUNMEZ; visible_from = tasinma ayi',
    tenant.status === 200 && tItem?.balance_minor === 1500 && tItem?.overdue_minor === 500 && tItem?.next_due_minor === 1000 && tItem?.visible_from === ym(-1) && tItem?.offset_note === true && same(ids(tItem?.recent), [c2, c3, p2]),
    { status: tenant.status, item: tItem && { ...tItem, recent: ids(tItem.recent) }, expected: [c2, c3, p2] },
  );

  // --- S2. malik: tasinma 2020 -> tum defter
  const owner = await call('GET', '/app/my-finance', OWNER);
  const oItem = owner.body?.items?.find((i) => i.apartment_id === x1);
  const oTenantView = oItem?.accounts?.find((a) => a.account_party === 'tenant');
  // İP-1A (G12): malikin KENDİ hesabı ev sahibi hesabıdır (boş); both dairede kiracı hesabını SALT OKUNUR görür: tüm kiracı hesabı (kapsam 2020'den)
  check(
    'S2: uzun suredir malik (both): kendi ev sahibi hesabi bos (bakiye 0); kiraci hesabini SALT OKUNUR gorur: bakiye 1600 (hesap toplami), vadesi gecmis 600, 8 kayit; gizli kayit yok -> visible_from null',
    owner.status === 200 && oItem?.account_party === 'owner' && oItem?.balance_minor === 0 && (oItem?.recent ?? []).length === 0
      && oTenantView?.role === 'read_only' && oTenantView.balance_minor === 1600 && oTenantView.overdue_minor === 600 && oTenantView.visible_from === null && oTenantView.offset_note === false
      && same(ids(oTenantView.recent), [c1, p1, cx, c2, c3, p2, rev, lf]),
    { item: oItem && { ...oItem, recent: ids(oItem.recent), accounts: oItem.accounts?.map((a) => ({ ...a, recent: ids(a.recent) })) } },
  );

  // --- S3. ekstre
  const tSt = await call('GET', `/app/my-finance/apartments/${x1}/statement?from=${M3}&to=${TODAY}`, NEW_TENANT);
  check(
    'S3: yeni kiraci ekstresi: aralik M-3 ten baslasa da yalniz gorunen satirlar; acilis 0, kapanis 1500 (= Borcum); kayan bakiye satir anindaki durum (odeme aninda eski 300 henuz iptal edilmemisti: 1800); mahsup notu (offset_note) true; visible_from',
    tSt.status === 200 && same(ids(tSt.body?.items), [c2, c3, p2]) && tSt.body.opening_balance_minor === 0 && tSt.body.closing_balance_minor === 1500
      && JSON.stringify((tSt.body.items ?? []).map((i) => i.running_balance_minor)) === '[1000,2000,1800]' && tSt.body.totals?.charged_minor === 2000 && tSt.body.totals?.paid_minor === 1000
      && tSt.body.overdue_minor === 500 && tSt.body.offset_note === true && tSt.body.visible_from === ym(-1),
    { status: tSt.status, items: (tSt.body?.items ?? []).map((i) => [i.id, i.amount_minor, i.running_balance_minor]), body: tSt.body && { ...tSt.body, items: undefined } },
  );
  // İP-1A: malik kiracı hesabının ekstresini salt okunur görünümle ister (account_party=tenant); kendi (ev sahibi) hesap ekstresi boştur
  const oSt = await call('GET', `/app/my-finance/apartments/${x1}/statement?from=${M3}&to=${TODAY}&account_party=tenant`, OWNER);
  const oOwnSt = await call('GET', `/app/my-finance/apartments/${x1}/statement?from=${M3}&to=${TODAY}`, OWNER);
  check('S3b: malik kiraci hesabi ekstresi (salt okunur) tum satirlar (8), kapanis 1600, mahsup notu yok; kendi ev sahibi hesabi ekstresi bos', oSt.status === 200 && ids(oSt.body?.items).length === 8 && oSt.body.closing_balance_minor === 1600 && oSt.body.offset_note === false && oSt.body.role === 'read_only' && oOwnSt.status === 200 && ids(oOwnSt.body?.items).length === 0 && oOwnSt.body.account_party === 'owner', { status: oSt.status, n: ids(oSt.body?.items).length, offset: oSt.body?.offset_note, own: oOwnSt.body?.items?.length });
  const mSt = await call('GET', `${P(site.code)}/apartments/${x1}/statement?from=${M3}&to=${TODAY}`, MGR);
  check('S3c: YONETICI ekstresi degismedi: tum satirlar (8), kapanis 1600, kapsam alanlari yok', mSt.status === 200 && ids(mSt.body?.items).length === 8 && mSt.body.closing_balance_minor === 1600 && !('visible_from' in (mSt.body ?? {})) && !('offset_note' in (mSt.body ?? {})), { status: mSt.status, n: ids(mSt.body?.items).length });
  const tStLate = await call('GET', `/app/my-finance/apartments/${x1}/statement?from=${M0}&to=${TODAY}`, NEW_TENANT);
  check('S3d: yeni kiraci, bu ayla baslayan ekstre: acilis = bu aydan onceki durumda kendi borcu (c2 = 1000)', tStLate.status === 200 && tStLate.body.opening_balance_minor === 1000 && tStLate.body.closing_balance_minor === 1500, tStLate.body && { opening: tStLate.body.opening_balance_minor, closing: tStLate.body.closing_balance_minor, items: ids(tStLate.body.items) });

  // --- S4. makbuzlar
  const tRc = await call('GET', '/app/my-finance/receipts', NEW_TENANT);
  const tR1 = await call('GET', `/app/my-finance/receipts/${r1}`, NEW_TENANT);
  const tR2 = await call('GET', `/app/my-finance/receipts/${r2}`, NEW_TENANT);
  const oRc = await call('GET', '/app/my-finance/receipts', OWNER);
  check(
    'S4: yeni kiraci yalniz gorebildigi tahsilatin makbuzunu gorur (R2); onceki kiracinin makbuzu listede yok ve dogrudan 404; malik ikisini de gorur',
    same(ids(tRc.body?.items), [r2]) && tR1.status === 404 && tR2.status === 200 && same(ids(oRc.body?.items), [r1, r2]),
    { tenant: ids(tRc.body?.items), r1: tR1.status, r2: tR2.status, owner: ids(oRc.body?.items) },
  );

  // --- S5. gecikme tazminati aciklamasi
  const tLf = await call('GET', `/app/my-finance/entries/${lf}/late-fee`, NEW_TENANT);
  const oLf = await call('GET', `/app/my-finance/entries/${lf}/late-fee`, OWNER);
  check('S5: eski aya ait tazminat aciklamasi yeni kiraciya 404, malike 200 (donem M-3)', tLf.status === 404 && oLf.status === 200 && oLf.body?.period === ym(-3), { tenant: tLf.status, owner: oLf.status, period: oLf.body?.period });

  // --- S6. onceki kiraci (iliskisi bitti) daireyi hic gormez
  const old = await call('GET', '/app/my-finance', OLD_TENANT);
  const oldSt = await call('GET', `/app/my-finance/apartments/${x1}/statement`, OLD_TENANT);
  check('S6: iliskisi biten onceki kiraci: Borcum bos, ekstre 404', old.status === 200 && (old.body?.items ?? []).length === 0 && oldSt.status === 404, { items: old.body?.items, st: oldSt.status });

  // --- S7. tarihsiz kayit: kapsam kayit ayi (bu ay)
  const nd = await call('GET', '/app/my-finance', NO_DATE);
  const ndItem = nd.body?.items?.find((i) => i.apartment_id === x2);
  check('S7: tasinma tarihi bos kisi: kapsam kayit ayi (bu ay); onceki ayin borcu (700) gorunmez, bu ayinki (300) gorunur', ndItem?.visible_from === ym(0) && ndItem?.balance_minor === 300 && same(ids(ndItem?.recent), [d2new]), {
    item: ndItem && { ...ndItem, recent: ids(ndItem.recent) },
    hidden: d2old,
  });

  // --- S8. siteye gecis (tarihsiz yukleme + gecmis aya yazilan borc + tam odeme): sahte alacak YOK
  const ob = await call('GET', '/app/my-finance', ONBOARD);
  const obItem = ob.body?.items?.find((i) => i.apartment_id === x3);
  check('S8: siteye gecis: gecen ay + bu ay aidati 2000 odendi -> bakiye 0 (sahte alacak yok); gecen ayin borcu kapsam disi; odeme gorunur', obItem?.balance_minor === 0 && obItem?.overdue_minor === 0 && same(ids(obItem?.recent), [d3oct, d3pay]), {
    item: obItem && { ...obItem, recent: ids(obItem.recent) },
    hidden: d3sep,
  });

  // --- S9. onceki kiracinin gec odemesi yeni kiracinin borcunu kapatmaz
  const late = await call('GET', '/app/my-finance', NEW_TENANT2);
  const lItem = late.body?.items?.find((i) => i.apartment_id === x4);
  check('S9: onceki kiracinin tasinmadan sonra eski borcuna yaptigi odeme: yeni kiracinin borcu 1000 kalir ("Borcunuz yok" denmez)', lItem?.balance_minor === 1000 && lItem?.overdue_minor === 1000 && same(ids(lItem?.recent), [d4mine, d4late]), {
    item: lItem && { ...lItem, recent: ids(lItem.recent) },
    hidden: d4old,
  });

  // --- S11. ayni kisinin ayni dairedeki kesintisiz onceki iliskisi (kiraciyken daireyi satin aldi): eski kayitlarini gormeye devam eder
  const BUYER = await mkUser('Kapsam Kiraciyken Malik', 'individual');
  const buyerPerson = await addPerson(site.code, { user: BUYER });
  await q(
    `INSERT INTO apartment_residencies (site_code, apartment_id, person_id, relation, is_current, move_in_date, move_out_date, origin)
     VALUES ($1, $2, $3, 'tenant', FALSE, $4, $5, 'manual')`,
    [site.code, x5, buyerPerson, day(M3, 5), isoOf(dayNo(TODAY) - 1)],
  );
  await addResidency(site.code, x5, buyerPerson, 'owner', { moveIn: TODAY });
  const d5old = await insert(x5, 'charge', 400, M3, M3, day(M3, 15));
  const buyer = await call('GET', '/app/my-finance', BUYER);
  const bItem = buyer.body?.items?.find((i) => i.apartment_id === x5);
  const bTenantView = bItem?.accounts?.find((a) => a.account_party === 'tenant');
  // İP-1A (G12): eski kiracılık kayıtları KİRACI hesabındadır; kişi artık malik (both) -> kiracı hesabını salt okunur görür ve kapsam zinciri o hesapta M-3'e uzar.
  // Kendi ev sahibi hesabında kapsam malikliğiyle başlar (önceki malikin ev sahibi hesabı kayıtları görünmez).
  check('S11: kiraciyken (M-3) daireyi satin alan kisi (malik iliskisi bugun): salt okunur kiraci hesabinda kapsam zincirin basi (M-3), eski borcu (400) gorunur; kendi ev sahibi hesabi bos', bItem?.account_party === 'owner' && bItem?.balance_minor === 0
    && bTenantView?.role === 'read_only' && bTenantView.balance_minor === 400 && same(ids(bTenantView.recent), [d5old]) && bTenantView.visible_from === null, {
    item: bItem && { ...bItem, recent: ids(bItem.recent), accounts: bItem.accounts?.map((a) => ({ ...a, recent: ids(a.recent) })) },
  });

  // --- S12. malik sorumluyken (owner) kiraciyken daireyi satin alan kisi: kiracilik donemi zincire SAYILMAZ (onceki malikin kayitlari gizli)
  await q(`UPDATE apartments SET responsible_party = 'owner' WHERE id = $1`, [x6]);
  const X6 = await mkUser('Kapsam Kiraci Alici', 'individual');
  const x6Person = await addPerson(site.code, { user: X6 });
  await q(
    `INSERT INTO apartment_residencies (site_code, apartment_id, person_id, relation, is_current, move_in_date, move_out_date, origin)
     VALUES ($1, $2, $3, 'tenant', FALSE, $4, $5, 'manual')`,
    [site.code, x6, x6Person, day(M3, 5), isoOf(dayNo(TODAY) - 1)],
  );
  await addResidency(site.code, x6, x6Person, 'owner', { moveIn: TODAY });
  const d6prev = await insert(x6, 'charge', 600, M3, M3, day(M3, 15));
  const x6res = await call('GET', '/app/my-finance', X6);
  const x6Item = x6res.body?.items?.find((i) => i.apartment_id === x6);
  check('S12: malik sorumlu dairede kiraciyken satin alan kisi onceki malikin borcunu (600) GORMEZ; kapsam bu ay', x6Item?.balance_minor === 0 && (x6Item?.recent ?? []).length === 0 && x6Item?.visible_from === ym(0), {
    item: x6Item && { ...x6Item, recent: ids(x6Item.recent) },
    hidden: d6prev,
  });

  // --- S13. sakinin iliski kaydindan ONCE duzenlenmis makbuzda odeyen adi gizlenir
  await q(`UPDATE apartments SET responsible_party = 'tenant' WHERE id = $1`, [x7]);
  const A7 = await mkUser('Kapsam Giden Kiraci Adi', 'individual');
  const a7Person = await addPerson(site.code, { user: A7 });
  await addResidency(site.code, x7, a7Person, 'tenant', { moveIn: day(M1, 1) });
  await insert(x7, 'charge', 1000, M0, M0, FUTURE);
  const a7pay = await pay(site, x7, 1000, {});
  const a7Receipt = Number(a7pay.body?.receipt?.id);
  const a7Snap = (await q(`SELECT snapshot FROM receipts WHERE id = $1`, [a7Receipt])).rows[0]?.snapshot;
  await q(`UPDATE apartment_residencies SET is_current = FALSE, move_out_date = $2 WHERE person_id = $1 AND apartment_id = $3`, [a7Person, TODAY, x7]);
  await sleep(20);
  const B7 = await mkUser('Kapsam Gelen Kiraci', 'individual');
  await addResidency(site.code, x7, await addPerson(site.code, { user: B7 }), 'tenant', { moveIn: M0 });
  const b7List = await call('GET', '/app/my-finance/receipts', B7);
  const b7One = await call('GET', `/app/my-finance/receipts/${a7Receipt}`, B7);
  const b7Json = JSON.stringify([b7List.body, b7One.body]);
  check('S13: makbuz kayit sirasinda odeyen = onceki kiraci; yeni kiracinin kaydindan once duzenlendigi icin yeni kiraciya ADSIZ gorunur (liste + detay)',
    a7Snap?.payer?.name === 'Kapsam Giden Kiraci Adi' && b7One.status === 200 && b7List.body?.items?.find((i) => Number(i.id) === a7Receipt)?.payer_name === null
      && b7One.body?.snapshot?.payer?.name === null && !b7Json.includes('Kapsam Giden Kiraci Adi'),
    { snapName: a7Snap?.payer?.name, list: b7List.body?.items, detail: b7One.status });

  // --- S10. kisisel veri disa aktarma ayni gorunumu kullanir
  const { collectPersonalData } = await import('../src/modules/account_export_service.js');
  const exported = await collectPersonalData(NEW_TENANT, { db: pool });
  const fs = exported?.finance_statements ?? exported?.data?.finance_statements ?? [];
  const rcs = exported?.receipts ?? exported?.data?.receipts ?? [];
  check(
    'S10: yeni kiracinin veri disa aktarmasi: Borcum ozeti ayni (bakiye 1500, gorunen 3 satir), makbuzlarda yalniz R2',
    fs.length === 1 && fs[0].balance_minor === 1500 && same(ids(fs[0].recent), [c2, c3, p2]) && rcs.length === 1,
    { fs: fs.map((x) => ({ balance: x.balance_minor, recent: ids(x.recent) })), receipts: rcs.length },
  );
}
