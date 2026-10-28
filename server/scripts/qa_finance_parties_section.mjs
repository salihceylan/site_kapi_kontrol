// Iki hesap (IP-1A, karar G12) icin GERCEK PostgreSQL bolumu (docs/PLATFORM_FINANS.md "Iki hesap (2026-10-21)").
// scripts/qa_finance4b.mjs ortamini kullanir (t: gercek authRequired + gercek JWT, ayri HTTP kapisi, fabrikalar). qa_platform_pg.mjs "parties" bolumu calistirir:
//   QA_CONFIRM_DISPOSABLE_DB=yes QA_ONLY=chain,live,parties DB_HOST=127.0.0.1 DB_PORT=... DB_USER=postgres node scripts/qa_platform_pg.mjs
// Kapsam:
//   P0  052 VERI VARKEN yukseltme (001..051 + eski satirlar -> migrate.js): eski satirlar dogru hesaba duser, geri doldurma YOK, eski surumun ters kaydi
//   P1  sema: kisitlar dogrulanmis, tazminat satiri anahtari, tetikleyiciler, 052 dosyasi idempotent, satir duzeyi kisitlar + ters kayit tetikleyicisi
//   P2  052 oncesi (hesapsiz) satirlar okumada dogru hesapta
//   P3  "kim oder": aylik tanim (oturan), ek borc (ev sahibi / oturan), ay ortasi tasinan / cikan kiraci, PATCH, PREVIEW_STALE, resolveChargeParty
//   P4  tahsilat hesabi + hesap basina mahsup; hesaplar ASLA karismaz (bakiye, vadesi gecen, borc / alacak, ozet); idempotans; makbuz odeyeni
//   P5  sakin gorunum matrisi (kendi hesabi, both dairede salt okunur kiraci hesabi), resolvePersonParty, IDOR (ekstre, makbuz, yonetici uclari)
//   P6  yaslandirma (M1 hesap basina), ekstre ve disa aktarma "Hesap" sutunu
//   P4i duzeltme / ters kayit hesabi korur (yanlis hesaba girilen tahsilatin duzeltilmesi)
//   P7  gecikme tazminati: ayni dairenin iki hesabi iki satir (kaba kuvvet kahini), sakin aciklamasi IDOR, iptal hesabi korur
//   P8  borc hatirlatma alicisi = hesabin sahibi (gercek kuyruk + sahte SMTP), tutar hesabin tutari
//   P9  ESZAMANLI tahsilat x borclandirma x ters kayit x duzeltme x CRM degisikligi (40P01 = 0, hesap tutarliligi)
//   P10 postPayment (sozlesme 2.1) kaynak izi, tekrar, cakisma, dogrulama
//   P11 eski istemci uyumu (eski alanlar korunur)
//   P12 tum veritabani degismezleri (ters kayit = asilin hesabi, tazminat satiri = defter satirinin hesabi, yeni satir hesapsiz yazilmaz, 40P01 = 0)
//   Ikinci inceleme (mutasyonla bulunan test bosluklari): P4m kiraci sekmesi kurali, P5g kisisel veri disa aktarmasi yalniz kendi hesabi,
//   P6f hesap suzgecli ekstrenin acilis bakiyesi, P8d ardisik hatirlatma sayaci hesabin son tahsilatina gore
// NOT: dosya ASCII Turkce kullanir; para hesabi tamsayi kurus (BigInt kahin), kayan nokta yok.

import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

const mulberry32 = (seed) => () => {
  let a = (seed += 0x6d2b79f5);
  a = Math.imul(a ^ (a >>> 15), a | 1);
  a ^= a + Math.imul(a ^ (a >>> 7), a | 61);
  return ((a ^ (a >>> 14)) >>> 0) / 4294967296;
};

export default async function sectionParties(t) {
  const { check, same, q, call, pool, hooks, ctx, TODAY, dayNo, ago, monthStart, ym, dayOf, mkUser, mkManaged, addPerson, P, key, users, failCode } = t;
  const { SUPER, MGR, MGR2, BOARD, OUTSIDER } = users;
  const { accountPartySql, accountBalances, resolveChargeParty, resolvePersonParty, postPayment } = await import('../src/modules/finance_parties.js');
  const { withFinanceTransaction } = await import('../src/modules/finance_tx.js');
  const { bucketOfDaysLate } = await import('../src/modules/finance_m1.js');
  const { lateFeeBruteForce } = await import('../src/modules/finance_late_fee_calc.js');
  const { ensureFinancePartiesSchema } = await import('../src/modules/finance_parties_schema.js');
  const queue = await import('../src/modules/finance_reminder_queue.js');
  const ACC = accountPartySql('l');
  const mails = ctx.mails;
  const deadlocksAtStart = hooks.deadlocks;
  const firstNewId = Number((await q(`SELECT COALESCE(MAX(id), 0)::BIGINT AS m FROM ledger_entries`)).rows[0].m) + 1;
  const legacyIds = []; // bilerek HESAPSIZ (052 oncesi surum gibi) yazilan satirlar; P12'de "yeni kod hesapsiz yazmaz" sayimindan cikarilir
  console.log('--- P. iki hesap (IP-1A / G12) ---');

  // --- yardimcilar
  const setResponsible = (aptId, party) => q(`UPDATE apartments SET responsible_party = $2 WHERE id = $1`, [aptId, party]);
  const resident = async (site, aptId, relation, label, { moveIn = '2020-01-01', current = true, moveOut = null, email = null } = {}) => {
    const user = await mkUser(label, 'apartment_owner', email ? { email } : {});
    const person = await addPerson(site.code, { user });
    await q(
      `INSERT INTO apartment_residencies (site_code, apartment_id, person_id, relation, is_current, move_in_date, move_out_date, origin) VALUES ($1, $2, $3, $4, $5, $6, $7, 'manual')`,
      [site.code, aptId, person, relation, current, moveIn, moveOut],
    );
    return { user, person, label };
  };
  const mine = async (user) => (await call('GET', '/app/my-finance', user)).body?.items ?? [];
  const itemOf = async (user, aptId) => (await mine(user)).find((i) => i.apartment_id === aptId) ?? null;
  const viewOf = (item, party) => item?.accounts?.find((a) => a.account_party === party) ?? null;
  const account = (site, aptId, query = '', user = MGR) => call('GET', `${P(site.code)}/apartments/${aptId}/account${query}`, user);
  const sqlSums = async (site, aptId) => {
    const out = { owner: 0, tenant: 0 };
    for (const row of (await q(`SELECT ${ACC} AS p, SUM(l.amount_minor)::TEXT AS s FROM ledger_entries l WHERE l.site_code = $1 AND l.apartment_id = $2 GROUP BY 1`, [site.code, aptId])).rows) {
      out[row.p] = Number(row.s);
    }
    return out;
  };
  const createDefinition = (site, body) => call('POST', `${P(site.code)}/definitions`, MGR, { kind: 'recurring', distribution: 'fixed', due_day: 1, target: { type: 'site' }, ...body });
  const postDefinition = async (site, definitionId, period) => {
    const pv = await call('POST', `${P(site.code)}/definitions/${definitionId}/preview`, MGR, { period });
    const post = await call('POST', `${P(site.code)}/definitions/${definitionId}/post`, MGR, { period, expected_total_minor: pv.body.total_minor, expected_apartment_count: pv.body.apartment_count, expected_hash: pv.body.preview_hash });
    return { pv, post };
  };
  const chargePreview = (site, body) => call('POST', `${P(site.code)}/charges/preview`, MGR, body);
  const chargePostBody = (body, pv) => ({ ...body, expected_total_minor: pv.body.total_minor, expected_apartment_count: pv.body.apartment_count, expected_hash: pv.body.preview_hash, idempotency_key: key('ek') });
  const postCharge = async (site, body) => {
    const pv = await chargePreview(site, body);
    const post = await call('POST', `${P(site.code)}/charges`, MGR, chargePostBody(body, pv));
    return { pv, post };
  };
  const payment = (site, aptId, amount, extra = {}) => call('POST', `${P(site.code)}/payments`, MGR, { apartment_id: aptId, amount_minor: amount, entry_date: TODAY, method: 'cash', idempotency_key: key('pp'), ...extra });
  const accountsOfRun = async (runId) => new Map((await q(`SELECT apartment_id, account_party FROM ledger_entries WHERE run_id = $1`, [runId])).rows.map((r) => [Number(r.apartment_id), r.account_party]));
  const errorOf = (promise) => promise.then(() => null, (error) => ({ status: error?.statusCode ?? null, code: error?.code ?? null }));
  const dueNext = dayOf(1, 15); // gelecek ay: vadesi gelmemis
  const range = `from=${ago(120)}&to=${TODAY}`;

  // ============================================================================================================
  // P0. 052 yukseltmesi VERI VARKEN: 001..051 kurulu ayri veritabaninda eski satirlar -> migrate.js 052
  // ============================================================================================================
  {
    const pg = (await import('pg')).default;
    const upDb = `${process.env.DB_NAME}_p051`;
    const admin = new pg.Client(ctx.connectConfig(process.env.QA_ADMIN_DB || 'postgres'));
    await admin.connect();
    await admin.query(`DROP DATABASE IF EXISTS "${upDb}" WITH (FORCE)`);
    await admin.query(`CREATE DATABASE "${upDb}"`);
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'qa-parties-051-'));
    const client = new pg.Client(ctx.connectConfig(upDb));
    try {
      for (const name of ctx.migrationFiles()) {
        if (Number(name.slice(0, name.indexOf('_'))) < 52) fs.copyFileSync(path.join(ctx.MIGRATIONS_DIR, name), path.join(dir, name));
      }
      const baseOk = ctx.runMigrate(upDb, dir);
      await client.connect();
      const newColumns = async () =>
        (await client.query(`SELECT COUNT(*)::INT AS n FROM pg_attribute WHERE attrelid = 'ledger_entries'::regclass AND attname IN ('account_party', 'source_kind', 'source_id') AND NOT attisdropped`)).rows[0].n;
      const before = await newColumns();
      const siteCode = 1000000990;
      // yalniz migration zinciri (ensureDbSchema calismadi): sites'in yalniz migration'lardaki sutunlari
      await client.query(`INSERT INTO sites (site_code, name, mqtt_site_id) VALUES ($1, 'P Yukseltme', generate_unique_mqtt_site_id())`, [siteCode]);
      const blockId = Number((await client.query(`INSERT INTO site_blocks (site_code, block_name, sort_order) VALUES ($1, 'Y Blok', 1) RETURNING id`, [siteCode])).rows[0].id);
      const apt = Number((await client.query(`INSERT INTO apartments (site_code, block_id, unit_label, sort_order, responsible_party) VALUES ($1, $2, 'Daire 1', 1, 'both') RETURNING id`, [siteCode, blockId])).rows[0].id);
      const old = async (kind, amount, payer) =>
        Number(
          (
            await client.query(
              `INSERT INTO ledger_entries (site_code, apartment_id, kind, amount_minor, period, entry_date, due_date, payer_party, method) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9) RETURNING id`,
              [siteCode, apt, kind, amount, monthStart(0), TODAY, kind === 'charge' ? TODAY : null, payer, kind === 'payment' ? 'cash' : null],
            )
          ).rows[0].id,
        );
      const oldTenantCharge = await old('charge', 30000, 'tenant');
      const oldOwnerCharge = await old('charge', 20000, 'owner');
      await old('charge', 10000, 'both');
      await old('payment', -5000, 'tenant');
      const migrated = ctx.runMigrate(upDb, ctx.MIGRATIONS_DIR);
      const after = await newColumns();
      const nulls = (await client.query(`SELECT COUNT(*) FILTER (WHERE account_party IS NULL)::INT AS nulls, COUNT(*)::INT AS n FROM ledger_entries WHERE site_code = $1`, [siteCode])).rows[0];
      const balances = await accountBalances(client, { siteCode, apartmentId: apt });
      check(
        'P0: 052 VERI VARKEN uygulanir (001..051 + 4 eski satir -> migrate.js): 3 yeni sutun; eski satirlar GERI DOLDURULMAZ (account_party NULL kalir); OKUMADA hesap turetilir: payer tenant -> kiraci (30000 - 5000 = 25000), owner + both -> ev sahibi (20000 + 10000 = 30000)',
        baseOk && migrated && before === 0 && after === 3 && nulls.n === 4 && nulls.nulls === 4 && balances.owner.balance_minor === 30000 && balances.tenant.balance_minor === 25000,
        { baseOk, migrated, before, after, nulls, balances },
      );
      // 052'yi bilmeyen eski surum surec (dagitim sirasinda) HESAPSIZ ters kayit yazar: tetikleyici hesabi ASILDAN doldurur; yanlis hesapli ters kayit reddedilir
      const oldReversal = Number(
        (
          await client.query(
            `INSERT INTO ledger_entries (site_code, apartment_id, kind, amount_minor, period, entry_date, due_date, payer_party, reverses_entry_id, reversal_reason) VALUES ($1, $2, 'reversal', -30000, $3, $4, $4, 'both', $5, 'eski surum') RETURNING id`,
            [siteCode, apt, monthStart(0), TODAY, oldTenantCharge],
          )
        ).rows[0].id,
      );
      const filled = (await client.query(`SELECT account_party FROM ledger_entries WHERE id = $1`, [oldReversal])).rows[0].account_party;
      let mismatch = null;
      try {
        await client.query(
          `INSERT INTO ledger_entries (site_code, apartment_id, kind, amount_minor, period, entry_date, due_date, payer_party, reverses_entry_id, reversal_reason, account_party) VALUES ($1, $2, 'reversal', -20000, $3, $4, $4, 'both', $5, 'yanlis hesap', 'tenant')`,
          [siteCode, apt, monthStart(0), TODAY, oldOwnerCharge],
        );
      } catch (error) {
        mismatch = `${error.code}:${error.message}`;
      }
      const steps = await ensureFinancePartiesSchema(client);
      const final = await accountBalances(client, { siteCode, apartmentId: apt });
      check(
        'P0b: yukseltmeden sonra eski surumun hesapsiz ters kaydi asilin hesabina (kiraci) duser; ASILDAN farkli hesapli ters kayit P0001; migrate sonrasi ensureFinancePartiesSchema hicbir adim uygulamaz; kiraci 25000 - 30000 = -5000, ev sahibi 30000',
        filled === 'tenant' && /^P0001:.*keep the account/.test(mismatch ?? '') && steps.length === 0 && final.tenant.balance_minor === -5000 && final.owner.balance_minor === 30000,
        { filled, mismatch, steps, final },
      );
    } finally {
      await client.end().catch(() => {});
      await admin.query(`DROP DATABASE IF EXISTS "${upDb}" WITH (FORCE)`).catch(() => {});
      await admin.end().catch(() => {});
      fs.rmSync(dir, { recursive: true, force: true });
    }
  }

  // ============================================================================================================
  // P1. Sema (live + ensureDbSchema ile yukseltilmis veritabani)
  // ============================================================================================================
  const TABLES = ['ledger_entries', 'fee_definitions', 'late_fee_run_lines', 'apartments'];
  const catalog = async () => ({
    cols: (await q(`SELECT table_name, column_name, data_type, is_nullable, column_default FROM information_schema.columns WHERE table_schema = 'public' AND table_name = ANY($1) ORDER BY 1, 2`, [TABLES])).rows,
    cons: (await q(`SELECT conrelid::regclass::text AS t, conname, pg_get_constraintdef(oid) AS d, convalidated FROM pg_constraint WHERE conrelid::regclass::text = ANY($1) ORDER BY 1, 2`, [TABLES])).rows,
    idx: (await q(`SELECT tablename, indexname, indexdef FROM pg_indexes WHERE schemaname = 'public' AND tablename = ANY($1) ORDER BY 1, 2`, [TABLES])).rows,
    trg: (await q(`SELECT c.relname AS t, tg.tgname, pg_get_triggerdef(tg.oid) AS d FROM pg_trigger tg JOIN pg_class c ON c.oid = tg.tgrelid WHERE NOT tg.tgisinternal AND c.relname = ANY($1) ORDER BY 1, 2`, [TABLES])).rows,
    fn: (await q(`SELECT proname, prosrc FROM pg_proc WHERE pronamespace = 'public'::regnamespace AND prosrc LIKE '%fp:1%' ORDER BY 1`)).rows,
  });
  const cat = await catalog();
  const conOf = (name) => cat.cons.find((c) => c.conname === name);
  const lineKey = cat.cons.find((c) => c.t === 'late_fee_run_lines' && /^PRIMARY KEY/.test(c.d));
  check(
    'P1: 052 nesneleri: ledger_entries account_party / source_kind / source_id (NULL olabilir, varsayilansiz); fee_definitions.charge_party; late_fee_run_lines.account_party; 4 CHECK DOGRULANMIS; tazminat satiri anahtari (run_id, ledger_entry_id) + hesap basina kismi tekil; kaynak izi indeksi; 2 tetikleyici + 2 islev (fp:1)',
    ['account_party', 'source_kind', 'source_id'].every((c) => cat.cols.some((r) => r.table_name === 'ledger_entries' && r.column_name === c && r.is_nullable === 'YES' && r.column_default === null))
      && cat.cols.some((r) => r.table_name === 'fee_definitions' && r.column_name === 'charge_party') && cat.cols.some((r) => r.table_name === 'late_fee_run_lines' && r.column_name === 'account_party')
      && ['chk_ledger_entries_account_party', 'chk_ledger_entries_source', 'chk_fee_definitions_charge_party', 'chk_late_fee_run_lines_account'].every((n) => conOf(n)?.convalidated === true)
      && lineKey?.d === 'PRIMARY KEY (run_id, ledger_entry_id)' && cat.idx.some((i) => i.indexname === 'uq_late_fee_run_lines_account') && cat.idx.some((i) => i.indexname === 'idx_ledger_entries_source')
      && cat.trg.some((r) => r.tgname === 'trg_ledger_entries_account_party') && cat.trg.some((r) => r.tgname === 'trg_late_fee_run_lines_account') && cat.fn.length === 2,
    { lineKey, fn: cat.fn.map((f) => f.proname) },
  );
  const file052 = fs.readdirSync(ctx.MIGRATIONS_DIR).find((name) => /^052_.+\.sql$/.test(name));
  // Satir sonlari migrate.js normalizeSql gibi LF'ye cevrilir: Windows (CRLF) checkout'ta islev govdeleri (prosrc) aksi halde CR tasir ve katalog
  // karsilastirmasi yalanci "degisti" der (migrate.js ve ensure yollari LF uygular).
  const sql052 = fs.readFileSync(path.join(ctx.MIGRATIONS_DIR, file052), 'utf8').replace(/\r\n?/g, '\n');
  let reapply = null;
  try {
    await pool.query(sql052);
    await pool.query(sql052);
  } catch (error) {
    reapply = `${error.code ?? ''} ${error.message}`;
  }
  const cat2 = await catalog();
  const schemaClient = await pool.connect();
  let ensureSteps;
  try {
    ensureSteps = await ensureFinancePartiesSchema(schemaClient);
  } finally {
    schemaClient.release();
  }
  check(
    'P1b: 052 dosyasi ayni veritabanina IKI KEZ daha dogrudan uygulanir: hata yok, katalog (sutun, kisit, indeks, tetikleyici, islev) DEGISMEZ; ensureFinancePartiesSchema hicbir adim uygulamaz (no-op)',
    reapply === null && ['cols', 'cons', 'idx', 'trg', 'fn'].every((part) => same(cat[part], cat2[part])) && ensureSteps.length === 0,
    { reapply, ensureSteps },
  );

  const S0 = await mkManaged('P Sema Sitesi', { 'S Blok': 1 });
  const s0 = S0.ids[0];
  const rawEntry = (over) => {
    const v = { kind: 'charge', amount_minor: 100, period: monthStart(0), entry_date: TODAY, due_date: TODAY, payer_party: 'both', ...over };
    const cols = Object.keys(v);
    return q(`INSERT INTO ledger_entries (site_code, apartment_id, ${cols.join(', ')}) VALUES ($1, $2, ${cols.map((_, i) => `$${i + 3}`).join(', ')}) RETURNING id`, [S0.code, s0, ...cols.map((c) => v[c])]);
  };
  const rawFail = async (over) => {
    try {
      await rawEntry(over);
      return null;
    } catch (error) {
      return `${error.code}:${error.message}`;
    }
  };
  const badRows = [];
  for (const [label, over] of [['hesap both', { account_party: 'both' }], ['hesap bos metin', { account_party: '' }], ['bilinmeyen kaynak turu', { source_kind: 'excel' }], ['tursuz kaynak kimligi', { source_id: 5 }]]) {
    badRows.push([label, (await rawFail(over))?.slice(0, 5)]);
  }
  const tenantRow = Number((await rawEntry({ account_party: 'tenant', source_kind: 'opening', source_id: 9 })).rows[0].id);
  const legacyTenantRow = Number((await rawEntry({ payer_party: 'tenant' })).rows[0].id);
  legacyIds.push(legacyTenantRow);
  const reversalOf = (originalId, over = {}) => rawEntry({ kind: 'reversal', amount_minor: -100, reverses_entry_id: originalId, reversal_reason: 'qa', ...over });
  const rv1 = Number((await reversalOf(tenantRow)).rows[0].id);
  const rvWrong = await rawFail({ kind: 'reversal', amount_minor: -100, reverses_entry_id: legacyTenantRow, reversal_reason: 'qa', account_party: 'owner' });
  const rv2 = Number((await reversalOf(legacyTenantRow)).rows[0].id);
  const rvAccounts = (await q(`SELECT account_party FROM ledger_entries WHERE id = ANY($1)`, [[rv1, rv2]])).rows.map((r) => r.account_party);
  check(
    'P1c: satir kisitlari (DB): gecersiz hesap (both / bos), bilinmeyen kaynak turu, tursuz kaynak kimligi 23514; ters kaydin hesabi bossa ASILDAN doldurulur (yeni satir + 052 oncesi turetilmis satir -> kiraci); asildan farkli hesap P0001',
    badRows.every(([, code]) => code === '23514') && same(rvAccounts, ['tenant', 'tenant']) && /^P0001:.*keep the account/.test(rvWrong ?? ''),
    { badRows, rvAccounts, rvWrong },
  );

  // ============================================================================================================
  // P2. Ana site: 6 daire, her biri bir kural durumunu sinar; 052 oncesi satirlar A1'de
  // ============================================================================================================
  const M = await mkManaged('P Iki Hesap Sitesi', { 'A Blok': 6 });
  const [A1, A2, A3, A4, A5, A6] = M.ids;
  const base = P(M.code);
  for (const [id, party] of [[A1, 'both'], [A2, 'tenant'], [A3, 'owner'], [A4, 'both'], [A5, 'both'], [A6, 'tenant']]) await setResponsible(id, party);
  const OU = await resident(M, A1, 'owner', 'P Malik Bir');
  const TU = await resident(M, A1, 'tenant', 'P Kiraci Bir');
  const FU = await resident(M, A1, 'family_member', 'P Aile Bir');
  const ON = await resident(M, A2, 'owner', 'P Malik Iki');
  const TN = await resident(M, A2, 'tenant', 'P Kiraci Iki');
  const OO = await resident(M, A3, 'owner', 'P Malik Uc');
  const TO = await resident(M, A3, 'tenant', 'P Kiraci Uc');
  const OB = await resident(M, A4, 'owner', 'P Malik Dort');
  const RS = await resident(M, A4, 'resident', 'P Sakin Dort');
  const OM = await resident(M, A5, 'owner', 'P Malik Bes');
  const TM = await resident(M, A5, 'tenant', 'P Kiraci Bes', { moveIn: dayOf(-1, 15) }); // gecen ayin 15'inde tasindi
  const OX = await resident(M, A6, 'owner', 'P Malik Alti');
  const TX = await resident(M, A6, 'tenant', 'P Eski Kiraci Alti', { current: false, moveOut: dayOf(-1, 20) }); // gecen ayin 20'sinde cikti
  const legacy = async (aptId, kind, amount, payer, entry, due) => {
    const id = Number(
      (
        await q(
          `INSERT INTO ledger_entries (site_code, apartment_id, kind, amount_minor, period, entry_date, due_date, payer_party, method) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9) RETURNING id`,
          [M.code, aptId, kind, amount, `${entry.slice(0, 7)}-01`, entry, due, payer, kind === 'payment' ? 'cash' : null],
        )
      ).rows[0].id,
    );
    legacyIds.push(id);
    return id;
  };
  const Lt = await legacy(A1, 'charge', 7000, 'tenant', ago(75), ago(70));
  const Lo = await legacy(A1, 'charge', 3000, 'owner', ago(80), ago(75));
  const Lb = await legacy(A1, 'charge', 2000, 'both', ago(80), ago(75));
  const Lp = await legacy(A1, 'payment', -1000, 'tenant', ago(60), null);
  const acc0 = await account(M, A1);
  const accountOfItem = (body, id) => body?.items?.find((i) => i.id === id)?.account_party;
  check(
    'P2: 052 oncesi (hesapsiz) satirlar OKUMADA dogru hesapta: payer tenant -> kiraci, owner / both -> ev sahibi; hesap bakiyeleri ev sahibi 5000, kiraci 6000 (toplam 11000); defterde account_party NULL kalir (geri doldurma yok)',
    acc0.status === 200 && accountOfItem(acc0.body, Lt) === 'tenant' && accountOfItem(acc0.body, Lo) === 'owner' && accountOfItem(acc0.body, Lb) === 'owner' && accountOfItem(acc0.body, Lp) === 'tenant'
      && acc0.body.accounts.owner.balance_minor === 5000 && acc0.body.accounts.tenant.balance_minor === 6000 && acc0.body.balance_minor === 11000
      && (await q(`SELECT COUNT(*)::INT AS n FROM ledger_entries WHERE id = ANY($1) AND account_party IS NULL`, [[Lt, Lo, Lb, Lp]])).rows[0].n === 4,
    acc0.body?.accounts,
  );

  // ============================================================================================================
  // P3. "Kim oder" (charge_party) ve borc tarihindeki oturan
  // ============================================================================================================
  const aidat = await createDefinition(M, { name: 'P Aidat', amount_minor: 100000, start_period: ym(-1) });
  check('P3: aylik tanimda "kim oder" verilmezse occupant (dairede oturan); yanit charge_party tasir', aidat.status === 201 && aidat.body.charge_party === 'occupant', aidat.body);
  const run1 = await postDefinition(M, aidat.body.id, ym(-1));
  const run0 = await postDefinition(M, aidat.body.id, ym(0));
  const exp1 = { [A1]: 'tenant', [A2]: 'tenant', [A3]: 'owner', [A4]: 'owner', [A5]: 'owner', [A6]: 'tenant' };
  const exp0 = { [A1]: 'tenant', [A2]: 'tenant', [A3]: 'owner', [A4]: 'owner', [A5]: 'tenant', [A6]: 'owner' };
  const linesMatch = (pv, expected) => pv.body?.lines?.length === 6 && pv.body.lines.every((l) => l.account_party === expected[l.apartment_id]);
  const runMatches = async (post, expected) => {
    const accounts = await accountsOfRun(post.body?.run?.id ?? 0);
    return accounts.size === Object.keys(expected).length && [...accounts].every(([id, party]) => party === expected[id]);
  };
  check(
    'P3b: gecen ayin aidati (borc tarihi ayin 1i): sorumlu owner -> ev sahibi; tenant / both + o gun etkin kiraci -> kiraci; kiracisiz both -> ev sahibi; ayin 15inde tasinan kiraci o gun YOK -> ev sahibi; ayin 20sinde cikan kiraci o gun VAR -> kiraci; onizleme satiri = yazilan satir',
    run1.post.status === 201 && linesMatch(run1.pv, exp1) && (await runMatches(run1.post, exp1)),
    run1.pv.body?.lines?.map((l) => [l.apartment_id, l.account_party]),
  );
  check(
    'P3c: bu ayin aidati: ay ortasi tasinan kiraci artik kiraci hesabinda; kiracisi cikan daire ev sahibi hesabina doner',
    run0.post.status === 201 && linesMatch(run0.pv, exp0) && (await runMatches(run0.post, exp0)),
    run0.pv.body?.lines?.map((l) => [l.apartment_id, l.account_party]),
  );
  const cati = await postCharge(M, { name: 'P Cati Onarimi', distribution: 'equal', amount_minor: 60000, target: { type: 'site' }, due_date: dueNext });
  const asansor = await postCharge(M, { name: 'P Asansor Bakimi', distribution: 'equal', amount_minor: 48000, target: { type: 'apartments', apartment_ids: [A1, A2, A3, A5] }, due_date: dueNext, charge_party: 'occupant' });
  const catiAccounts = await accountsOfRun(cati.post.body?.run?.id ?? 0);
  const asansorAccounts = await accountsOfRun(asansor.post.body?.run?.id ?? 0);
  check(
    'P3d: ek borcta "kim oder" verilmezse EV SAHIBI (6 dairenin hepsi; tanim charge_party owner); occupant secilirse bugunku oturan: A1 / A2 / A5 kiraci, A3 ev sahibi',
    cati.post.status === 201 && cati.post.body.definition.charge_party === 'owner' && catiAccounts.size === 6 && [...catiAccounts.values()].every((p) => p === 'owner') && cati.pv.body.lines.every((l) => l.account_party === 'owner')
      && asansor.post.status === 201 && asansor.post.body.definition.charge_party === 'occupant' && asansorAccounts.get(A1) === 'tenant' && asansorAccounts.get(A2) === 'tenant' && asansorAccounts.get(A3) === 'owner' && asansorAccounts.get(A5) === 'tenant',
    { cati: [...catiAccounts], asansor: [...asansorAccounts] },
  );
  const demirbas = await createDefinition(M, { name: 'P Demirbas', amount_minor: 5000, start_period: ym(0), charge_party: 'owner' });
  const demirbasPv = await call('POST', `${base}/definitions/${demirbas.body.id}/preview`, MGR, { period: ym(0) });
  const badParty = await createDefinition(M, { name: 'P Gecersiz', amount_minor: 100, start_period: ym(0), charge_party: 'tenant' });
  const patched = await call('PATCH', `${base}/definitions/${aidat.body.id}`, MGR, { charge_party: 'owner' });
  const nextPv = await call('POST', `${base}/definitions/${aidat.body.id}/preview`, MGR, { period: ym(1) });
  const restored = await call('PATCH', `${base}/definitions/${aidat.body.id}`, MGR, { charge_party: 'occupant' });
  const dbCheck = await failCode(`UPDATE fee_definitions SET charge_party = 'tenant' WHERE id = $1`, [aidat.body.id]);
  check(
    'P3e: tanim charge_party owner -> tum satirlar ev sahibi; gecersiz deger (tenant) 400; BORCLANDIRILMIS tanimda "kim oder" degisebilir (yalniz sonraki borclandirma: onizleme hepsi ev sahibi), yazilmis satirlar degismez; DB CHECK 23514',
    demirbas.status === 201 && demirbas.body.charge_party === 'owner' && demirbasPv.body.lines.every((l) => l.account_party === 'owner') && badParty.status === 400
      && patched.status === 200 && patched.body.charge_party === 'owner' && nextPv.body.lines.length === 6 && nextPv.body.lines.every((l) => l.account_party === 'owner') && restored.body?.charge_party === 'occupant'
      && (await runMatches(run0.post, exp0)) && dbCheck === '23514',
    { patched: patched.body?.charge_party, badParty: badParty.status, dbCheck },
  );
  const su = await createDefinition(M, { name: 'P Su', amount_minor: 3000, start_period: ym(0), target: { type: 'apartments', apartment_ids: [A4] } });
  const suPv = await call('POST', `${base}/definitions/${su.body.id}/preview`, MGR, { period: ym(0) });
  const tmpTenant = await resident(M, A4, 'tenant', 'P Gecici Kiraci');
  const stale = await call('POST', `${base}/definitions/${su.body.id}/post`, MGR, { period: ym(0), expected_total_minor: suPv.body.total_minor, expected_apartment_count: suPv.body.apartment_count, expected_hash: suPv.body.preview_hash });
  const suPv2 = await call('POST', `${base}/definitions/${su.body.id}/preview`, MGR, { period: ym(0) });
  await q(`DELETE FROM apartment_residencies WHERE person_id = $1`, [tmpTenant.person]);
  await q(`UPDATE fee_definitions SET is_active = FALSE WHERE id = $1`, [su.body.id]);
  check(
    'P3f: onizleme ile onay arasinda daireye kiraci TASINIRSA satirin hesabi degisir -> 409 PREVIEW_STALE, hicbir sey yazilmaz; yeni onizleme kiraci hesabini gosterir',
    suPv.body.lines[0]?.account_party === 'owner' && stale.status === 409 && stale.body.code === 'PREVIEW_STALE' && suPv2.body.lines[0]?.account_party === 'tenant'
      && (await q(`SELECT COUNT(*)::INT AS n FROM ledger_entries WHERE definition_id = $1`, [su.body.id])).rows[0].n === 0,
    { stale: stale.body?.code, before: suPv.body.lines[0], after: suPv2.body.lines[0] },
  );
  const rcp = (aptId, chargeParty, onDate) => resolveChargeParty(pool, { siteCode: M.code, apartmentId: aptId, chargeParty, onDate });
  const foreignRcp = await errorOf(rcp(s0, 'occupant', TODAY));
  check(
    'P3g: resolveChargeParty (sozlesme 2.1): owner her zaman ev sahibi; occupant tarihe gore (tasinma gunu dahil, cikis gunu dahil); baska sitenin dairesi 404',
    (await rcp(A1, 'owner', TODAY)) === 'owner' && (await rcp(A1, 'occupant', TODAY)) === 'tenant' && (await rcp(A3, 'occupant', TODAY)) === 'owner'
      && (await rcp(A5, 'occupant', dayOf(-1, 14))) === 'owner' && (await rcp(A5, 'occupant', dayOf(-1, 15))) === 'tenant'
      && (await rcp(A6, 'occupant', dayOf(-1, 20))) === 'tenant' && (await rcp(A6, 'occupant', dayOf(-1, 21))) === 'owner' && foreignRcp?.status === 404,
    foreignRcp,
  );

  // ============================================================================================================
  // P4. Tahsilat hesabi ve hesap basina mahsup: iki hesap ASLA karismaz
  // ============================================================================================================
  // A1: kiraci = Lt 7000 + Lp -1000 + aidat x2 200000 + asansor 12000 (vadesi gelmemis) = 218000; ev sahibi = Lo 3000 + Lb 2000 + cati 10000 (vadesi gelmemis) = 15000
  const before = await account(M, A1);
  check(
    'P4: tahsilat oncesi A1: ev sahibi 15000 (vadesi gecen 5000), kiraci 218000 (vadesi gecen 206000); varsayilan tahsilat hesabi = vadesi EN ESKI acik borcu olan hesap (ev sahibi); kiraci sekmesi + guncel kiraci',
    before.body.accounts.owner.balance_minor === 15000 && before.body.accounts.owner.overdue_minor === 5000 && before.body.accounts.tenant.balance_minor === 218000 && before.body.accounts.tenant.overdue_minor === 206000
      && before.body.balance_minor === 233000 && before.body.overdue_minor === 211000 && before.body.default_payment_account === 'owner' && before.body.show_tenant_account === true && before.body.has_current_tenant === true,
    before.body,
  );
  const p1 = await payment(M, A1, 50000, { account_party: 'tenant' });
  const p2 = await payment(M, A1, 5000); // eski istemci: hesap yok
  const afterP2 = await account(M, A1);
  const p3 = await payment(M, A1, 20000, { account_party: 'owner', method: 'transfer' });
  check(
    'P4b: tahsilat SECILEN hesaba yazilir (kiraci 50000; yanitta hesap bakiyesi account_balance_minor 168000 + eski alan balance_minor 183000); hesap verilmeyen (eski istemci) tahsilat vadesi en eski acik borcun hesabina (ev sahibi); ardindan varsayilan kiraciya doner',
    p1.status === 201 && p1.body.entry.account_party === 'tenant' && p1.body.account_balance_minor === 168000 && p1.body.balance_minor === 183000
      && p2.status === 201 && p2.body.entry.account_party === 'owner' && afterP2.body.default_payment_account === 'tenant' && p3.status === 201 && p3.body.entry.account_party === 'owner',
    [p1.body?.entry?.account_party, p2.body?.entry?.account_party, afterP2.body?.default_payment_account, p3.body?.entry?.account_party],
  );
  const s1 = await account(M, A1);
  check(
    'P4c: hesaplar KARISMAZ: ev sahibi hesabinin fazlasi (alacak 10000) kiracinin borcunu (168000) kapatmaz; vadesi gecen = hesaplarin vadesi gecenlerinin toplami 156000 (karissaydi 136000); eski alan bakiye = iki hesabin toplami 158000',
    s1.body.accounts.owner.balance_minor === -10000 && s1.body.accounts.owner.overdue_minor === 0 && s1.body.accounts.tenant.balance_minor === 168000 && s1.body.accounts.tenant.overdue_minor === 156000
      && s1.body.balance_minor === 158000 && s1.body.overdue_minor === 156000,
    s1.body.accounts,
  );
  const sTenant = await account(M, A1, '?account_party=tenant');
  const sOwner = await account(M, A1, '?account_party=owner');
  const badQuery = await account(M, A1, '?account_party=both');
  check(
    'P4d: yonetici hesap ekstresi ?account_party= ile tek hesap: satirlar yalniz o hesabin (kiraci 6, ev sahibi 5), bakiye o hesabin (168000 / -10000); gecersiz deger 400 INVALID_QUERY',
    sTenant.body.items.length === 6 && sTenant.body.items.every((i) => i.account_party === 'tenant') && sTenant.body.balance_minor === 168000 && sTenant.body.account_party === 'tenant'
      && sOwner.body.items.length === 5 && sOwner.body.items.every((i) => i.account_party === 'owner') && sOwner.body.balance_minor === -10000 && badQuery.status === 400 && badQuery.body.code === 'INVALID_QUERY',
    [sTenant.body.items?.length, sOwner.body.items?.length, badQuery.status],
  );
  const balances = await call('GET', `${base}/balances?status=all&limit=50`, MGR);
  const balA1 = balances.body.items.find((i) => i.apartment_id === A1);
  const debtors = await call('GET', `${base}/balances?status=debtor&limit=50`, MGR);
  const creditors = await call('GET', `${base}/balances?status=credit&limit=50`, MGR);
  check(
    'P4e: bakiye listesi hesap bazinda: A1 borc 168000 + alacak 10000 (ayni dairede iki hesap) + hesap kirilimi; daire HEM borclu HEM alacakli listesinde; alacakli listesinde yalniz A1',
    balA1.debt_minor === 168000 && balA1.credit_minor === 10000 && balA1.balance_minor === 158000 && balA1.overdue_minor === 156000 && balA1.accounts.owner.balance_minor === -10000 && balA1.accounts.tenant.balance_minor === 168000
      && debtors.body.items.some((i) => i.apartment_id === A1) && creditors.body.items.length === 1 && creditors.body.items[0].apartment_id === A1,
    balA1,
  );
  const oracle = (
    await q(
      `WITH acc AS (SELECT l.apartment_id, ${ACC} AS p, SUM(l.amount_minor) AS b FROM ledger_entries l WHERE l.site_code = $1 GROUP BY 1, 2)
       SELECT COALESCE(SUM(GREATEST(b, 0)), 0)::TEXT AS debt, COALESCE(SUM(GREATEST(-b, 0)), 0)::TEXT AS credit, COALESCE(SUM(b), 0)::TEXT AS total FROM acc`,
      [M.code],
    )
  ).rows[0];
  const summary = await call('GET', `${base}/summary`, MGR);
  check(
    'P4f: ozet ve bakiye listesi toplamlari: borc / alacak = HESAP basina pozitif / negatif bakiyelerin toplami (SQL kahiniyle birebir); bakiye toplami = defter toplami',
    summary.body.debt_total_minor === Number(oracle.debt) && summary.body.credit_total_minor === Number(oracle.credit) && summary.body.balance_total_minor === Number(oracle.total) && summary.body.credit_total_minor === 10000
      && balances.body.totals.debt_minor === Number(oracle.debt) && balances.body.totals.credit_minor === Number(oracle.credit),
    { summary: summary.body, oracle },
  );
  const keyP1 = (await q(`SELECT idempotency_key FROM ledger_entries WHERE id = $1`, [p1.body.entry.id])).rows[0].idempotency_key;
  const replay = await payment(M, A1, 50000, { account_party: 'tenant', idempotency_key: keyP1 });
  const replayOld = await payment(M, A1, 50000, { idempotency_key: keyP1 });
  const conflict = await payment(M, A1, 50000, { account_party: 'owner', idempotency_key: keyP1 });
  const badAccount = await payment(M, A1, 1000, { account_party: 'both' });
  check(
    'P4g: ayni anahtar tekrari ayni kaydi dondurur (hesapsiz tekrar da: eski istemci); ayni anahtar + FARKLI hesap 409 IDEMPOTENCY_CONFLICT; gecersiz hesap 400; ikinci satir yazilmaz',
    replay.status === 200 && replay.body.entry.id === p1.body.entry.id && replayOld.status === 200 && replayOld.body.entry.id === p1.body.entry.id && conflict.status === 409 && conflict.body.code === 'IDEMPOTENCY_CONFLICT'
      && badAccount.status === 400 && (await q(`SELECT COUNT(*)::INT AS n FROM ledger_entries WHERE site_code = $1 AND kind = 'payment' AND apartment_id = $2`, [M.code, A1])).rows[0].n === 4,
    [replay.status, replayOld.status, conflict.status, badAccount.status],
  );
  const receiptOf = async (entryId) => (await q(`SELECT id, snapshot FROM receipts WHERE ledger_entry_id = $1 AND kind = 'collection' ORDER BY id DESC LIMIT 1`, [entryId])).rows[0] ?? null;
  const rc1 = await receiptOf(p1.body.entry.id);
  const rc2 = await receiptOf(p2.body.entry.id);
  const rc3 = await receiptOf(p3.body.entry.id);
  const auditP1 = (await q(`SELECT details FROM audit_log WHERE action = 'finance.payment.recorded' AND target_id = $1`, [String(p1.body.entry.id)])).rows[0]?.details;
  check(
    'P4h: makbuz odeyeni tahsilatin HESABINA gore: kiraci hesabi -> kiraci adi, ev sahibi hesabi -> malik adi; snapshot payer.account_party; denetim kaydinda account_party + source_kind manual (kod)',
    rc1?.snapshot?.payer?.name === 'P Kiraci Bir' && rc1.snapshot.payer.account_party === 'tenant' && rc2?.snapshot?.payer?.name === 'P Malik Bir' && rc2.snapshot.payer.account_party === 'owner'
      && rc3?.snapshot?.payer?.account_party === 'owner' && auditP1?.account_party === 'tenant' && auditP1?.source_kind === 'manual',
    [rc1?.snapshot?.payer, rc2?.snapshot?.payer, auditP1],
  );

  // ============================================================================================================
  // P5. Sakin gorunum matrisi + IDOR (durum: A1 ev sahibi -10000, kiraci 168000)
  // ============================================================================================================
  // A2: kiraci 212000, ev sahibi 10000 | A3: ev sahibi 222000, kiraci 0 | A4: ev sahibi 210000 | A5: ev sahibi 110000, kiraci 112000 | A6: ev sahibi 110000, kiraci 100000
  // Bagimsiz inceleme (F2.05 korunur): iliskisi belirtilmemis sakin, sorumlu malik / kiraci ve o kisi KAYITLIYKEN hicbir hesabi gormez (RA2); sorumlu tarafin
  // guncel kisisi yoksa (yedek) oturanin hesabini gorur (RA6: sorumlu kiraci, kiraci cikti -> ev sahibi hesabi).
  const RA2 = await resident(M, A2, 'resident', 'P Sakin Iki');
  const RA6 = await resident(M, A6, 'resident', 'P Sakin Alti');
  const matrix = [
    ['OU malik (both)', OU, A1, [['owner', 'own', -10000], ['tenant', 'read_only', 168000]]],
    ['TU kiraci (both)', TU, A1, [['tenant', 'own', 168000]]],
    ['FU aile uyesi', FU, A1, null],
    ['ON malik (sorumlu kiraci)', ON, A2, [['owner', 'own', 10000]]],
    ['TN kiraci (sorumlu kiraci)', TN, A2, [['tenant', 'own', 212000]]],
    ['OO malik (sorumlu malik)', OO, A3, [['owner', 'own', 222000]]],
    ['TO kiraci (sorumlu malik): kendi bos hesabi', TO, A3, [['tenant', 'own', 0]]],
    ['OB malik (both, kiracisiz): salt okunur bos kiraci hesabi', OB, A4, [['owner', 'own', 210000], ['tenant', 'read_only', 0]]],
    ['RS iliskisi belirtilmemis, kiraci yok -> ev sahibi', RS, A4, [['owner', 'own', 210000]]],
    ['OM malik (both, kiraci ay ortasi tasindi)', OM, A5, [['owner', 'own', 110000], ['tenant', 'read_only', 112000]]],
    ['TM ay ortasi tasinan kiraci', TM, A5, [['tenant', 'own', 112000]]],
    ['OX malik (sorumlu kiraci, kiraci cikti)', OX, A6, [['owner', 'own', 110000]]],
    ['TX cikmis kiraci', TX, A6, null],
    ['RA2 belirtilmemis (sorumlu kiraci, kiraci kayitli): GORMEZ', RA2, A2, null],
    ['RA6 belirtilmemis (sorumlu kiraci, kiraci cikti: yedek) -> ev sahibi', RA6, A6, [['owner', 'own', 110000]]],
  ];
  const matrixResults = [];
  for (const [label, who, aptId, expected] of matrix) {
    const item = await itemOf(who.user, aptId);
    const got = item ? item.accounts.map((a) => [a.account_party, a.role, a.balance_minor]) : null;
    const own = item?.accounts?.[0];
    const oldFields = item === null || (item.account_party === own.account_party && item.balance_minor === own.balance_minor && item.overdue_minor === own.overdue_minor && item.next_due_date === own.next_due_date && same(item.recent, own.recent));
    matrixResults.push([label, same(got, expected) && oldFields, got]);
  }
  const outsiderItems = await mine(OUTSIDER);
  check(
    `P5: sakin gorunum matrisi (${matrix.length} durum): her kisi YALNIZ kendi hesabini gorur (malik -> ev sahibi, kiraci -> kiraci, belirtilmemis -> kiraci varsa kiraci yoksa ev sahibi; belirtilmemis yalniz sorumlu both iken ya da sorumlu tarafin kisisi yokken); both dairede malik kiraci hesabini SALT OKUNUR gorur; aile uyesi / cikmis kiraci / ilgisiz gormez; eski alanlar (balance_minor, overdue_minor, next_due_date, recent) = kendi hesabi`,
    matrixResults.every(([, ok]) => ok) && outsiderItems.length === 0,
    matrixResults.filter(([, ok]) => !ok),
  );
  const ouItem = await itemOf(OU.user, A1);
  const tuItem = await itemOf(TU.user, A1);
  check(
    'P5b: hareket listeleri hesaba gore: kiraci yalniz kiraci hesabi satirlarini gorur (malikin tahsilatlarini GORMEZ); malikin kendi listesi yalniz ev sahibi hesabi, salt okunur gorunum yalniz kiraci hesabi; vadesi gecen kiraci 156000; kaynak kimligi sakine gitmez',
    tuItem.recent.length === 6 && tuItem.recent.every((r) => r.account_party === 'tenant') && !tuItem.recent.some((r) => r.id === p2.body.entry.id || r.id === p3.body.entry.id) && tuItem.overdue_minor === 156000
      && ouItem.recent.length === 5 && ouItem.recent.every((r) => r.account_party === 'owner') && viewOf(ouItem, 'tenant').recent.every((r) => r.account_party === 'tenant') && viewOf(ouItem, 'tenant').overdue_minor === 156000
      && [...tuItem.recent, ...ouItem.recent].every((r) => r.source_id === null),
    { tu: tuItem.recent.map((r) => [r.id, r.account_party]), ou: ouItem.recent.map((r) => [r.id, r.account_party]) },
  );
  const rpp = (aptId, who) => resolvePersonParty(pool, { siteCode: M.code, apartmentId: aptId, userCode: who });
  check(
    'P5c: resolvePersonParty (sozlesme 2.1): malik -> owner, kiraci -> tenant, belirtilmemis (kiracisiz daire) -> owner; aile uyesi / cikmis kiraci / ilgisiz -> null',
    (await rpp(A1, OU.user)) === 'owner' && (await rpp(A1, TU.user)) === 'tenant' && (await rpp(A4, RS.user)) === 'owner' && (await rpp(A1, FU.user)) === null && (await rpp(A6, TX.user)) === null && (await rpp(A1, OUTSIDER)) === null,
  );
  const myStatement = (user, aptId, extra = '') => call('GET', `/app/my-finance/apartments/${aptId}/statement?${range}${extra}`, user);
  const idor = [
    ['kiraci -> ev sahibi hesabi', (await myStatement(TU.user, A1, '&account_party=owner')).status, 404],
    ['kiraci -> baska daire', (await myStatement(TU.user, A2)).status, 404],
    ['malik (sorumlu kiraci) -> kiraci hesabi', (await myStatement(ON.user, A2, '&account_party=tenant')).status, 404],
    ['aile uyesi', (await myStatement(FU.user, A1)).status, 404],
    ['cikmis kiraci', (await myStatement(TX.user, A6)).status, 404],
    ['ilgisiz', (await myStatement(OUTSIDER, A1)).status, 404],
    ['gecersiz hesap', (await myStatement(TU.user, A1, '&account_party=both')).status, 400],
    ['belirtilmemis sakin (sorumlu kiraci, kiraci kayitli)', (await myStatement(RA2.user, A2)).status, 404],
    ['belirtilmemis sakin -> kiraci hesabi', (await myStatement(RA2.user, A2, '&account_party=tenant')).status, 404],
  ];
  const ouTenantSt = await myStatement(OU.user, A1, '&account_party=tenant');
  const ouOwnSt = await myStatement(OU.user, A1);
  const tuSt = await myStatement(TU.user, A1);
  check(
    'P5d: sakin ekstresi IDOR: kiraci ev sahibi hesabini / baska daireyi, sorumlu kiraci dairede malik kiraci hesabini, aile uyesi / cikmis kiraci / ilgisiz / sorumlu kisi kayitliyken belirtilmemis sakin HICBIRINI gormez (404); malik both dairede kiraci ekstresini salt okunur (role read_only, kapanis 168000), kendi ekstresi ev sahibi (-10000); kiraci kendi ekstresi 168000',
    idor.every(([, got, want]) => got === want) && ouTenantSt.status === 200 && ouTenantSt.body.role === 'read_only' && ouTenantSt.body.closing_balance_minor === 168000
      && ouOwnSt.body.role === 'own' && ouOwnSt.body.account_party === 'owner' && ouOwnSt.body.closing_balance_minor === -10000 && tuSt.body.closing_balance_minor === 168000 && tuSt.body.items.every((i) => i.account_party === 'tenant'),
    { idor: idor.filter(([, got, want]) => got !== want), ouTenant: [ouTenantSt.status, ouTenantSt.body?.role, ouTenantSt.body?.closing_balance_minor] },
  );
  const receiptIds = (body) => (body?.items ?? []).map((i) => i.id).sort((a, b) => a - b);
  const tuReceipts = await call('GET', '/app/my-finance/receipts', TU.user);
  const ouReceipts = await call('GET', '/app/my-finance/receipts', OU.user);
  const ouOwnerReceipts = await call('GET', '/app/my-finance/receipts?account_party=owner', OU.user);
  check(
    'P5e: sakin makbuzlari hesaba gore: kiraci yalniz kiraci hesabi tahsilatinin makbuzunu gorur; malik kendi + salt okunur kiraci hesabi makbuzlarini, ?account_party=owner ile yalniz kendi hesabini; kiraci malikin makbuzunu ACAMAZ (404), malik kiraci hesabi makbuzunu acar',
    same(receiptIds(tuReceipts.body), [Number(rc1.id)]) && same(receiptIds(ouReceipts.body), [Number(rc1.id), Number(rc2.id), Number(rc3.id)].sort((a, b) => a - b)) && same(receiptIds(ouOwnerReceipts.body), [Number(rc2.id), Number(rc3.id)].sort((a, b) => a - b))
      && (await call('GET', `/app/my-finance/receipts/${rc2.id}`, TU.user)).status === 404 && (await call('GET', `/app/my-finance/receipts/${rc1.id}`, OU.user)).status === 200
      && (await call('GET', `/app/my-finance/receipts/${rc1.id}`, TU.user)).status === 200 && (await call('GET', `/app/my-finance/receipts/${rc1.id}`, ON.user)).status === 404,
    { tu: receiptIds(tuReceipts.body), ou: receiptIds(ouReceipts.body), ouOwner: receiptIds(ouOwnerReceipts.body) },
  );
  const mgrMatrix = [
    ['yonetici', (await account(M, A1, '?account_party=tenant')).status, 200],
    ['super', (await account(M, A1, '?account_party=tenant', SUPER)).status, 200],
    ['kurul (okur)', (await account(M, A1, '?account_party=tenant', BOARD)).status, 200],
    ['baska site yoneticisi', (await account(M, A1, '?account_party=tenant', MGR2)).status, 403],
    ['ilgisiz', (await account(M, A1, '?account_party=tenant', OUTSIDER)).status, 403],
    ['sakin (malik)', (await account(M, A1, '?account_party=tenant', OU.user)).status, 403],
    ['baska sitenin dairesi bu site yolundan', (await account(M, s0, '?account_party=tenant')).status, 404],
  ];
  check('P5f: yonetici hesap ucu yetki matrisi: yonetici / super / kurul okur; baska site yoneticisi, ilgisiz, sakin 403; baska sitenin dairesi 404 (IDOR)', mgrMatrix.every(([, got, want]) => got === want), mgrMatrix);
  // P5g (ikinci inceleme). Kisisel veri disa aktarmasi YALNIZ kendi hesabi: both dairede malike salt okunur gorunen kiraci hesabi kiracinin verisidir;
  // malikin dosyasinda Borcum tek gorunum (ev sahibi) ve makbuzlarda yalniz ev sahibi hesabinin tahsilatlari bulunur (P5e: uygulamadaki makbuz listesi ikisini de gosterir).
  const { collectPersonalData } = await import('../src/modules/account_export_service.js');
  const exportOf = async (user) => (await collectPersonalData(user, { db: pool }))?.data ?? {};
  const ouExport = await exportOf(OU.user);
  const tuExport = await exportOf(TU.user);
  const ouStatement = (ouExport.finance_statements ?? []).find((s) => s.apartment_id === A1) ?? null;
  const exportReceiptIds = (data) => (data.receipts ?? []).map((r) => r.id).sort((a, b) => a - b);
  check(
    'P5g (ikinci inceleme): kisisel veri disa aktarmasi YALNIZ kendi hesabi: both dairede malikin dosyasinda Borcum tek gorunum (ev sahibi -10000, salt okunur kiraci hesabi YOK, hareketler ev sahibi hesabi) ve makbuzlarda yalniz ev sahibi hesabi tahsilatlari; kiracinin dosyasinda yalniz kendi makbuzu',
    ouStatement?.account_party === 'owner' && ouStatement.accounts?.length === 1 && ouStatement.accounts[0].account_party === 'owner' && ouStatement.balance_minor === -10000
      && ouStatement.recent.every((r) => r.account_party === 'owner')
      && same(exportReceiptIds(ouExport), [Number(rc2.id), Number(rc3.id)].sort((a, b) => a - b)) && same(exportReceiptIds(tuExport), [Number(rc1.id)]),
    { ou: ouStatement && { accounts: ouStatement.accounts?.map((a) => [a.account_party, a.role]), balance: ouStatement.balance_minor }, ouReceipts: exportReceiptIds(ouExport), tuReceipts: exportReceiptIds(tuExport) },
  );

  // ============================================================================================================
  // P6. Yaslandirma (M1 hesap basina), ekstre ve disa aktarma "Hesap" sutunu
  // ============================================================================================================
  const daysLate = (iso) => dayNo(TODAY) - dayNo(iso);
  const tenantBuckets = { not_due: 12000n };
  const addBucket = (bucket, amount) => {
    tenantBuckets[bucket] = (tenantBuckets[bucket] ?? 0n) + amount;
  };
  addBucket(bucketOfDaysLate(daysLate(monthStart(-1))), 56000n); // tahsilatlar (51000) once Lt'yi (7000) sonra gecen ayin aidatini (44000) kapatir
  addBucket(bucketOfDaysLate(daysLate(monthStart(0))), 100000n);
  const BUCKETS = ['not_due', 'd0_30', 'd31_60', 'd61_90', 'd91_180', 'd181_365', 'd366_plus'];
  const aging = await call('GET', `${base}/reports/aging?status=all`, MGR);
  const agA1 = aging.body.items.find((i) => i.apartment_id === A1);
  check(
    'P6: yaslandirma (M1 mahsubu) HESAP basina: kiraci hesabinda tahsilatlar en eski KIRACI borcundan duser (kalan 56000 + 100000, vadesi gelmemis 12000; kovalar gun sayisina gore); ev sahibi hesabinin fazlasi (10000) kiraci borcuna mahsup EDILMEZ (alacak); daire satiri = hesaplarin toplami (gecikmis 156000, alacak 10000)',
    agA1.accounts.owner.total_overdue_minor === 0 && agA1.accounts.owner.credit_minor === 10000 && agA1.accounts.tenant.total_overdue_minor === 156000 && agA1.accounts.tenant.credit_minor === 0
      && BUCKETS.every((b) => BigInt(agA1.accounts.tenant[`${b}_minor`]) === (tenantBuckets[b] ?? 0n)) && agA1.total_overdue_minor === 156000 && agA1.credit_minor === 10000 && agA1.account_party === null,
    { agA1, tenantBuckets: Object.fromEntries(Object.entries(tenantBuckets).map(([k, v]) => [k, String(v)])) },
  );
  const agTenant = await call('GET', `${base}/reports/aging?status=all&account_party=tenant`, MGR);
  const agTA1 = agTenant.body.items.find((i) => i.apartment_id === A1);
  check(
    'P6b: yaslandirma ?account_party=tenant yalniz kiraci hesaplari: A1 gecikmis 156000, alacak 0; toplam = kiraci hesaplarinin toplami',
    agTenant.status === 200 && agTenant.body.account_party === 'tenant' && agTA1.total_overdue_minor === 156000 && agTA1.credit_minor === 0 && agTA1.account_party === 'tenant'
      && agTenant.body.totals.total_overdue_minor === agTenant.body.items.reduce((sum, i) => sum + i.total_overdue_minor, 0),
    agTA1,
  );
  const mgrSt = (extra) => call('GET', `${base}/apartments/${A1}/statement?${range}${extra}`, MGR);
  const stAll = await mgrSt('');
  const stTenant = await mgrSt('&account_party=tenant');
  const stOwner = await mgrSt('&account_party=owner');
  check(
    'P6c: yonetici ekstresi hesap suzgeci: kiraci kapanis 168000, ev sahibi -10000; suzgecsiz (eski davranis) iki hesabin toplami 158000; satirlar hesabini tasir',
    stTenant.body.closing_balance_minor === 168000 && stTenant.body.items.every((i) => i.account_party === 'tenant') && stOwner.body.closing_balance_minor === -10000 && stOwner.body.items.every((i) => i.account_party === 'owner')
      && stAll.body.closing_balance_minor === 158000 && stAll.body.items.length === stTenant.body.items.length + stOwner.body.items.length,
    [stAll.body?.closing_balance_minor, stTenant.body?.closing_balance_minor, stOwner.body?.closing_balance_minor],
  );
  const colIndex = (env, k) => env.body.columns.findIndex((c) => c.key === k);
  const exAging = await call('GET', `${base}/exports/finance_aging?status=all`, MGR);
  const hesapAging = colIndex(exAging, 'hesap');
  const daireAging = colIndex(exAging, 'daire');
  const overdueAging = colIndex(exAging, 'toplam_gecikmis');
  const creditAging = colIndex(exAging, 'alacak');
  const rowsOfApt = (env, label, idx) => env.body.rows.filter((r) => r[idx] === label);
  const a1Rows = rowsOfApt(exAging, 'A Blok - Daire 1', daireAging);
  const a4Rows = rowsOfApt(exAging, 'A Blok - Daire 4', daireAging);
  check(
    'P6d: yaslandirma disa aktarmasi HESAP basina satir ve SON sutun "Hesap": A1 iki satir (Ev sahibi hesabi alacak 10000; Kiraci hesabi gecikmis 156000); hareketsiz kiraci hesabi satiri yazilmaz (A4 tek satir)',
    exAging.status === 200 && hesapAging === exAging.body.columns.length - 1 && a1Rows.length === 2
      && a1Rows.some((r) => r[hesapAging] === 'Ev sahibi hesabı' && r[creditAging] === 10000 && r[overdueAging] === 0) && a1Rows.some((r) => r[hesapAging] === 'Kiracı hesabı' && r[overdueAging] === 156000)
      && a4Rows.length === 1 && a4Rows[0][hesapAging] === 'Ev sahibi hesabı',
    { columns: exAging.body?.columns?.map((c) => c.key), a1Rows, a4Rows },
  );
  const exSt = await call('GET', `${base}/exports/finance_statement?apartment_id=${A1}&account_party=tenant&${range}`, MGR);
  const hesapSt = colIndex(exSt, 'hesap');
  const exReceipts = await call('GET', `${base}/exports/finance_receipts`, MGR);
  const hesapRc = colIndex(exReceipts, 'hesap');
  check(
    'P6e: ekstre disa aktarmasi (?account_party=tenant): Devreden dahil TUM satirlar "Kiracı hesabı"; makbuz disa aktarmasi son sutun "Hesap" (kiraci / ev sahibi tahsilatina gore)',
    exSt.status === 200 && hesapSt === exSt.body.columns.length - 1 && exSt.body.rows.length >= 2 && exSt.body.rows.every((r) => r[hesapSt] === 'Kiracı hesabı')
      && exReceipts.status === 200 && hesapRc === exReceipts.body.columns.length - 1 && exReceipts.body.rows.some((r) => r[hesapRc] === 'Kiracı hesabı') && exReceipts.body.rows.some((r) => r[hesapRc] === 'Ev sahibi hesabı'),
    { st: exSt.body?.rows?.map((r) => r[hesapSt]), rc: exReceipts.body?.rows?.map((r) => r[hesapRc]) },
  );
  // P6f (ikinci inceleme). Hesap suzgecli ekstrenin ACILIS bakiyesi de hesap basina: aralik basindan (70 gun once) onceki 052 oncesi satirlar
  // kiraci hesabinda 7000 (Lt), ev sahibi hesabinda 5000 (Lo + Lb); bir hesabin eski satiri digerinin acilisina girmez (SQL kahini).
  const midFrom = ago(70);
  const midRange = `from=${midFrom}&to=${TODAY}`;
  const openingOracle = { owner: 0, tenant: 0 };
  for (const row of (await q(`SELECT ${ACC} AS p, SUM(l.amount_minor)::TEXT AS s FROM ledger_entries l WHERE l.site_code = $1 AND l.apartment_id = $2 AND l.entry_date < $3::DATE GROUP BY 1`, [M.code, A1, midFrom])).rows) {
    openingOracle[row.p] = Number(row.s);
  }
  const midSt = (extra) => call('GET', `${base}/apartments/${A1}/statement?${midRange}${extra}`, MGR);
  const [midAll, midTenant, midOwner] = [await midSt(''), await midSt('&account_party=tenant'), await midSt('&account_party=owner')];
  const midExport = await call('GET', `${base}/exports/finance_statement?apartment_id=${A1}&account_party=tenant&${midRange}`, MGR);
  const devreden = midExport.body?.rows?.[0] ?? null;
  check(
    'P6f (ikinci inceleme): hesap suzgecli ekstrenin ACILIS bakiyesi hesap basina (kiraci 7000, ev sahibi 5000, suzgecsiz 12000; SQL kahini); kapanis hesabin bakiyesi (168000 / -10000 / 158000); disa aktarmanin Devreden satiri kiraci hesabinin acilisi',
    openingOracle.tenant === 7000 && openingOracle.owner === 5000
      && midTenant.body.opening_balance_minor === openingOracle.tenant && midOwner.body.opening_balance_minor === openingOracle.owner && midAll.body.opening_balance_minor === openingOracle.tenant + openingOracle.owner
      && midTenant.body.closing_balance_minor === 168000 && midOwner.body.closing_balance_minor === -10000 && midAll.body.closing_balance_minor === 158000
      && devreden?.[1] === 'Devreden' && devreden?.[9] === openingOracle.tenant,
    { openingOracle, opening: [midAll.body?.opening_balance_minor, midTenant.body?.opening_balance_minor, midOwner.body?.opening_balance_minor], devreden },
  );

  // ============================================================================================================
  // P4i. Duzeltme ve ters kayit hesabi korur; yanlis hesaba girilen tahsilat duzeltilir
  // ============================================================================================================
  const corrKey = key('corr');
  const corr = await call('POST', `${base}/entries/${p3.body.entry.id}/correct`, MGR, { amount_minor: 20000, entry_date: TODAY, method: 'transfer', account_party: 'tenant', idempotency_key: corrKey });
  const corrConflict = await call('POST', `${base}/entries/${p3.body.entry.id}/correct`, MGR, { amount_minor: 20000, entry_date: TODAY, method: 'transfer', account_party: 'owner', idempotency_key: corrKey });
  const s2 = await account(M, A1);
  check(
    'P4i: yanlis hesaba girilen tahsilat DUZELTILIR (account_party ile): ters kayit ASIL hesapta (ev sahibi), yeni tahsilat secilen hesapta (kiraci, makbuz odeyeni kiraci); ev sahibi 10000, kiraci 148000; ayni anahtar + farkli hesap 409',
    corr.status === 201 && corr.body.reversal.account_party === 'owner' && corr.body.entry.account_party === 'tenant' && corr.body.account_balance_minor === 148000
      && s2.body.accounts.owner.balance_minor === 10000 && s2.body.accounts.tenant.balance_minor === 148000 && corrConflict.status === 409 && corrConflict.body.code === 'IDEMPOTENCY_CONFLICT'
      && (await receiptOf(corr.body.entry.id))?.snapshot?.payer?.name === 'P Kiraci Bir',
    { corr: corr.body, accounts: s2.body.accounts },
  );
  const corr2 = await call('POST', `${base}/entries/${p1.body.entry.id}/correct`, MGR, { amount_minor: 45000, entry_date: TODAY, method: 'cash', idempotency_key: key('corr2') });
  const rev2 = await call('POST', `${base}/entries/${p2.body.entry.id}/reverse`, MGR, { reason: 'hatali giris', idempotency_key: key('rev2') });
  const s3 = await account(M, A1);
  check(
    'P4j: hesap verilmeyen duzeltme ASILIN hesabini korur (kiraci: ters kayit + yeni tahsilat kiraci); iptal (ters kayit) asilin hesabinda (ev sahibi); kiraci 153000, ev sahibi 15000',
    corr2.status === 201 && corr2.body.entry.account_party === 'tenant' && corr2.body.reversal.account_party === 'tenant' && rev2.status === 201 && rev2.body.entry.account_party === 'owner'
      && s3.body.accounts.tenant.balance_minor === 153000 && s3.body.accounts.owner.balance_minor === 15000,
    s3.body.accounts,
  );

  // ============================================================================================================
  // P4k (bagimsiz inceleme). Varsayilan tahsilat hesabi DIGER hesapken hesapsiz duzeltme (eski istemci) asilin hesabini korur;
  // duzeltme tekrari hesap bakiyesini de dondurur; borclu / alacakli listesi HESAP bazinda (toplami eksi ama bir hesabi borclu daire borcludur)
  // ============================================================================================================
  {
    const K = await mkManaged('P Inceleme Sitesi', { 'K Blok': 2 });
    const [K1, K2] = K.ids;
    const kBase = P(K.code);
    await setResponsible(K1, 'both');
    await setResponsible(K2, 'both');
    await resident(K, K1, 'owner', 'P Inceleme Malik');
    await resident(K, K1, 'tenant', 'P Inceleme Kiraci');
    await resident(K, K2, 'owner', 'P Inceleme Malik Iki');
    await resident(K, K2, 'tenant', 'P Inceleme Kiraci Iki');
    // K1: ev sahibi hesabinda vadesi ESKI borc (40 gun once) 30000; iki dairenin kiraci hesabinda vadesi yeni (5 gun once) borc 10000'er
    const kOwner = await postCharge(K, { name: 'P K Cati', distribution: 'equal', amount_minor: 30000, target: { type: 'apartments', apartment_ids: [K1] }, due_date: ago(40) });
    const kTenant = await postCharge(K, { name: 'P K Fark', distribution: 'equal', amount_minor: 20000, target: { type: 'apartments', apartment_ids: [K1, K2] }, due_date: ago(5), charge_party: 'occupant' });
    if (kOwner.post.status !== 201 || kTenant.post.status !== 201) throw new Error(`inceleme fiksturu: ${JSON.stringify([kOwner.post.body, kTenant.post.body])}`);
    const kBefore = await account(K, K1);
    const kPay = await payment(K, K1, 4000, { account_party: 'tenant' });
    const kFixBody = { amount_minor: 4500, entry_date: TODAY, method: 'cash', idempotency_key: key('kfix') };
    const kFix = await call('POST', `${kBase}/entries/${kPay.body.entry.id}/correct`, MGR, kFixBody);
    const kFixReplay = await call('POST', `${kBase}/entries/${kPay.body.entry.id}/correct`, MGR, kFixBody);
    const kAfter = await account(K, K1);
    check(
      'P4k: hesap verilmeyen duzeltme (eski istemci), varsayilan tahsilat hesabi EV SAHIBI iken bile asilin hesabinda kalir (kiraci: ters kayit + yeni tahsilat); hesaplar 30000 / 5500; ayni anahtarla tekrar AYNI kaydi ve hesap bakiyesini (account_balance_minor) dondurur',
      kBefore.body.default_payment_account === 'owner' && kPay.status === 201 && kPay.body.entry.account_party === 'tenant'
        && kFix.status === 201 && kFix.body.reversal.account_party === 'tenant' && kFix.body.entry.account_party === 'tenant' && kFix.body.account_balance_minor === 5500
        && kFixReplay.status === 200 && kFixReplay.body.entry.id === kFix.body.entry.id && kFixReplay.body.account_balance_minor === 5500
        && kAfter.body.accounts.owner.balance_minor === 30000 && kAfter.body.accounts.tenant.balance_minor === 5500,
      { before: kBefore.body?.default_payment_account, fix: kFix.body, replay: kFixReplay.body, accounts: kAfter.body?.accounts },
    );
    // K2: ev sahibi hesabina 50000 fazla odeme (alacak) + kiraci hesabinda 10000 borc: daire TOPLAMI -40000 ama kiraci hesabi BORCLU
    const kOver = await payment(K, K2, 50000, { account_party: 'owner' });
    const kDebtors = await call('GET', `${kBase}/balances?status=debtor&limit=50`, MGR);
    const kCredit = await call('GET', `${kBase}/balances?status=credit&limit=50`, MGR);
    const kSummary = await call('GET', `${kBase}/summary`, MGR);
    const k2Row = kDebtors.body.items?.find((i) => i.apartment_id === K2);
    check(
      'P4l: borclu listesi HESAP bazinda: toplami -40000 olan dairenin kiraci hesabi borclu (10000) -> borclu listesinde (alacakli listesinde de); ozet borclu daire sayisi 2, borc 30000 + 5500 + 10000 = 45500, alacak 50000 (hesaplar karismaz)',
      kOver.status === 201 && kOver.body.entry.account_party === 'owner' && k2Row?.balance_minor === -40000 && k2Row.debt_minor === 10000 && k2Row.credit_minor === 50000
        && kDebtors.body.items.length === 2 && kCredit.body.items.length === 1 && kCredit.body.items[0].apartment_id === K2
        && kSummary.body.debtor_count === 2 && kSummary.body.debt_total_minor === 45500 && kSummary.body.credit_total_minor === 50000 && kSummary.body.balance_total_minor === -4500,
      { k2Row, debtors: kDebtors.body.items?.map((i) => i.apartment_id), credit: kCredit.body.items?.map((i) => i.apartment_id), summary: kSummary.body },
    );
  }
  // P4m (ikinci inceleme). Ekstre penceresinin kiraci sekmesi (show_tenant_account): kiracisi cikmis ama kiraci hesabinda satiri kalan dairede (A6) sekme
  // VAR (yoksa kiracinin borcu ev sahibi hesabiyla karisik tek listede gorunurdu); guncel kiracili dairede (A3, kiraci hesabi bos) VAR; kiracisi hic
  // olmamis ve kiraci hesabi bos dairede (A4: gecici kiraci kaydi silindi) YOK.
  const tabState = {};
  for (const [label, aptId] of [['A3', A3], ['A4', A4], ['A6', A6]]) {
    const body = (await account(M, aptId)).body;
    tabState[label] = { show: body.show_tenant_account, current: body.has_current_tenant, tenantRows: body.accounts?.tenant?.entry_count };
  }
  check(
    'P4m (ikinci inceleme): kiraci sekmesi: kiracisi cikmis, kiraci hesabinda satiri olan daire (A6) VAR; guncel kiracili, kiraci hesabi bos daire (A3) VAR; kiracisi hic olmamis, kiraci hesabi bos daire (A4) YOK',
    tabState.A6.show === true && tabState.A6.current === false && tabState.A6.tenantRows > 0
      && tabState.A3.show === true && tabState.A3.current === true && tabState.A3.tenantRows === 0
      && tabState.A4.show === false && tabState.A4.current === false && tabState.A4.tenantRows === 0,
    tabState,
  );

  // ============================================================================================================
  // P7. Gecikme tazminati: ayni dairenin iki hesabi iki satir
  // ============================================================================================================
  const LF = await mkManaged('P Tazminat Sitesi', { 'T Blok': 2 });
  const [L1, L2] = LF.ids;
  const lfBase = P(LF.code);
  await setResponsible(L1, 'both');
  await setResponsible(L2, 'owner');
  const LO = await resident(LF, L1, 'owner', 'P Tazminat Malik');
  const LT = await resident(LF, L1, 'tenant', 'P Tazminat Kiraci');
  const LO2 = await resident(LF, L2, 'owner', 'P Tazminat Malik Iki');
  const lfAidat = await createDefinition(LF, { name: 'P T Aidat', amount_minor: 100000, start_period: ym(-2) });
  const lfDemirbas = await createDefinition(LF, { name: 'P T Demirbas', amount_minor: 50000, start_period: ym(-2), charge_party: 'owner' });
  for (const [definition, period] of [[lfAidat, ym(-2)], [lfDemirbas, ym(-2)], [lfAidat, ym(-1)]]) {
    const r = await postDefinition(LF, definition.body.id, period);
    if (r.post.status !== 201) throw new Error(`tazminat fiksturu borclandirilamadi: ${JSON.stringify(r.post.body)}`);
  }
  const lfPay = await payment(LF, L1, 100000, { account_party: 'tenant', entry_date: dayOf(-1, 5) });
  if (lfPay.status !== 201) throw new Error(`tazminat fiksturu tahsilati: ${JSON.stringify(lfPay.body)}`);
  for (const off of [-2, -1]) {
    const closed = await call('POST', `${lfBase}/periods/${ym(off)}/close`, MGR);
    if (closed.status !== 200) throw new Error(`donem kapatilamadi ${ym(off)}: ${JSON.stringify(closed.body)}`);
  }
  await call('PUT', '/admin/finance-legal-gate', SUPER, { legal_ok: true });
  const lfSettings = await call('GET', `${lfBase}/settings`, MGR);
  const lfEnable = await call('PUT', `${lfBase}/settings`, MGR, { expected_settings_version: lfSettings.body.settings_version, late_fee: { enabled: true, start_period: ym(-1), rate_bp: 200, method: 'daily_30', grace_days: 0 } });
  if (lfEnable.status !== 200) throw new Error(`tazminat acilamadi: ${JSON.stringify(lfEnable.body)}`);
  const lfPv = await call('POST', `${lfBase}/late-fee/preview`, MGR, { period: ym(-1) });
  const calcRowsOf = async (aptId, party) =>
    (
      await q(
        `SELECT l.id, l.kind, l.amount_minor::TEXT AS amount, l.entry_date::TEXT AS entry_date, l.due_date::TEXT AS due_date, l.late_fee_run_id, l.reverses_entry_id
         FROM ledger_entries l WHERE l.site_code = $1 AND l.apartment_id = $2 AND ${ACC} = $3 ORDER BY l.id`,
        [LF.code, aptId, party],
      )
    ).rows.map((r) => ({
      id: Number(r.id), kind: r.kind, amount: BigInt(r.amount), entryDay: dayNo(r.entry_date), dueDay: r.due_date === null ? null : dayNo(r.due_date), lateFee: r.late_fee_run_id !== null,
      reversesId: r.reverses_entry_id === null ? null : Number(r.reverses_entry_id),
    }));
  const lfWindow = { p1: dayNo(monthStart(-1)), p2: dayNo(monthStart(0)) - 1, graceDays: 0, rateBp: lfPv.body?.settings?.rate_bp ?? 200, divisor: 30 };
  const oracleLines = [];
  for (const [aptId, party] of [[L1, 'owner'], [L1, 'tenant'], [L2, 'owner'], [L2, 'tenant']]) {
    const o = lateFeeBruteForce(await calcRowsOf(aptId, party), lfWindow);
    if (o.fee > 0n) oracleLines.push({ aptId, party, fee: o.fee, base: o.base });
  }
  const pvLine = (aptId, party) => lfPv.body.lines.find((l) => l.apartment_id === aptId && l.account_party === party);
  check(
    'P7: gecikme tazminati onizlemesi (daire, HESAP) basina: ayni dairenin iki hesabi IKI satir (L1 ev sahibi + L1 kiraci) + L2 ev sahibi; her satir KENDI hesabinin mahsubuyla gun-gun kaba kuvvet kahinine BIREBIR (tutar + kurus-gun tabani); apartment_count = satir sayisi 3',
    lfPv.status === 200 && lfPv.body.can_post === true && oracleLines.length === 3 && lfPv.body.lines.length === 3 && lfPv.body.apartment_count === 3
      && oracleLines.every((o) => {
        const line = pvLine(o.aptId, o.party);
        return line && BigInt(line.amount_minor) === o.fee && BigInt(line.base_day_minor) === o.base;
      }),
    { lines: lfPv.body?.lines?.map((l) => [l.apartment_id, l.account_party, l.amount_minor]), oracle: oracleLines.map((o) => [o.aptId, o.party, String(o.fee)]), blockers: lfPv.body?.blockers },
  );
  const preFee = { L1: await sqlSums(LF, L1), L2: await sqlSums(LF, L2) };
  const lfPost = await call('POST', `${lfBase}/late-fee/post`, MGR, { period: ym(-1), excluded_apartment_ids: [], expected_total_minor: lfPv.body.total_minor, expected_apartment_count: lfPv.body.apartment_count, expected_hash: lfPv.body.preview_hash, idempotency_key: key('lf') });
  const runId = lfPost.body?.run?.id ?? 0;
  const feeRows = (await q(`SELECT l.id, l.apartment_id, l.account_party, l.amount_minor::TEXT AS a FROM ledger_entries l WHERE l.late_fee_run_id = $1 AND l.kind = 'charge' ORDER BY l.id`, [runId])).rows;
  const lineRows = (await q(`SELECT ln.apartment_id, ln.account_party, ln.ledger_entry_id, ln.amount_minor::TEXT AS a FROM late_fee_run_lines ln WHERE ln.run_id = $1 ORDER BY ln.ledger_entry_id`, [runId])).rows;
  const linesApi = await call('GET', `${lfBase}/late-fee/runs/${runId}/lines`, MGR);
  check(
    'P7b: onay: her satir KENDI hesabina tazminat kaydi yazar (3 defter satiri, account_party = satir hesabi); satir tablosunda ayni daire iki satir (anahtar run_id + ledger_entry_id), satir hesabi = defter satirinin hesabi; satir listesi account_party tasir',
    lfPost.status === 201 && feeRows.length === 3 && lineRows.length === 3 && lineRows.every((ln) => feeRows.some((f) => f.id === ln.ledger_entry_id && f.account_party === ln.account_party && f.a === ln.a))
      && lineRows.filter((ln) => Number(ln.apartment_id) === L1).map((ln) => ln.account_party).sort().join(',') === 'owner,tenant'
      && linesApi.status === 200 && linesApi.body.items.length === 3 && same(linesApi.body.items.map((i) => i.account_party).sort(), ['owner', 'owner', 'tenant']),
    { post: lfPost.body, feeRows, lineRows },
  );
  const feeOf = (aptId, party) => Number(feeRows.find((f) => Number(f.apartment_id) === aptId && f.account_party === party)?.id ?? 0);
  const feeTenant = feeOf(L1, 'tenant');
  const feeOwner = feeOf(L1, 'owner');
  const explain = (user, entryId) => call('GET', `/app/my-finance/entries/${entryId}/late-fee`, user);
  const ltItem = await itemOf(LT.user, L1);
  const loItem = await itemOf(LO.user, L1);
  const explainMatrix = [
    ['kiraci kendi tazminati', (await explain(LT.user, feeTenant)).status, 200],
    ['kiraci ev sahibi tazminati', (await explain(LT.user, feeOwner)).status, 404],
    ['malik kendi tazminati', (await explain(LO.user, feeOwner)).status, 200],
    ['malik salt okunur kiraci tazminati', (await explain(LO.user, feeTenant)).status, 200],
    ['baska dairenin maliki', (await explain(LO2.user, feeTenant)).status, 404],
  ];
  check(
    'P7c: sakin: kiraci kendi hesabindaki tazminati gorur ve aciklamasini acar; ev sahibi hesabi tazminati kiraciya gorunmez / 404; malik kendi tazminatini ve salt okunur kiraci tazminatini acar; baska dairenin maliki 404',
    ltItem.recent.some((r) => r.id === feeTenant) && !ltItem.recent.some((r) => r.id === feeOwner) && loItem.recent.some((r) => r.id === feeOwner) && viewOf(loItem, 'tenant').recent.some((r) => r.id === feeTenant)
      && explainMatrix.every(([, got, want]) => got === want),
    explainMatrix,
  );
  const lfVoid = await call('POST', `${lfBase}/late-fee/runs/${runId}/void`, MGR, { reason: 'deneme', idempotency_key: key('lfv') });
  const voidRows = (await q(`SELECT r.account_party AS ra, o.account_party AS oa FROM ledger_entries r JOIN ledger_entries o ON o.id = r.reverses_entry_id WHERE o.late_fee_run_id = $1`, [runId])).rows;
  const postVoid = { L1: await sqlSums(LF, L1), L2: await sqlSums(LF, L2) };
  check(
    'P7d: iptal (void): 3 ters kaydin her biri ASILIN hesabinda; hesap bakiyeleri tazminat oncesine doner',
    lfVoid.status === 201 && lfVoid.body.reversed_count === 3 && voidRows.length === 3 && voidRows.every((r) => r.ra === r.oa) && same(postVoid, preFee),
    { void: lfVoid.body, voidRows, preFee, postVoid },
  );

  // ============================================================================================================
  // P8. Borc hatirlatma: alici = hesabin sahibi (gercek kuyruk, sahte SMTP)
  // ============================================================================================================
  queue.reminderQueueHooks.sleep = async () => {};
  const R = await mkManaged('P Hatirlatma Sitesi', { 'H Blok': 5 });
  const [R1, R2, R3, R4, R5] = R.ids;
  const rBase = P(R.code);
  for (const [id, party] of [[R1, 'both'], [R2, 'tenant'], [R3, 'both'], [R4, 'both'], [R5, 'owner']]) await setResponsible(id, party);
  await resident(R, R1, 'owner', 'P H Malik Bir', { email: 'p.ro1@qa.example' });
  await resident(R, R1, 'tenant', 'P H Kiraci Bir', { email: 'p.rt1@qa.example' });
  await resident(R, R2, 'owner', 'P H Malik Iki', { email: 'p.ro2@qa.example' });
  await resident(R, R2, 'tenant', 'P H Kiraci Iki', { email: 'p.rt2@qa.example' });
  await resident(R, R3, 'owner', 'P H Malik Uc', { email: 'p.ro3@qa.example' });
  await resident(R, R3, 'tenant', 'P H Kiraci Uc', { email: 'p.rt3@qa.example' });
  const crmFamily = await addPerson(R.code, { name: 'P H Aile Dort', email: 'p.aile4@qa.example' });
  await q(`INSERT INTO apartment_residencies (site_code, apartment_id, person_id, relation, is_current, move_in_date, origin) VALUES ($1, $2, $3, 'family_member', TRUE, '2020-01-01', 'manual')`, [R.code, R4, crmFamily]);
  const accountCharge = (aptId, amount, account) =>
    q(`INSERT INTO ledger_entries (site_code, apartment_id, kind, amount_minor, period, entry_date, due_date, payer_party, account_party) VALUES ($1, $2, 'charge', $3, $4, $5, $6, 'both', $7)`, [R.code, aptId, amount, `${ago(45).slice(0, 7)}-01`, ago(45), ago(40), account]);
  await accountCharge(R1, 80000, 'tenant'); // both: borc kiraci hesabinda -> yalniz kiraci (malik salt okunur gorur, ALICI DEGIL)
  await accountCharge(R2, 90000, 'owner'); // sorumlu kiraci ama borc ev sahibi hesabinda -> yalniz malik
  await accountCharge(R3, 60000, 'owner'); // iki hesap borclu -> iki sahibe ayri ileti
  await accountCharge(R3, 70000, 'tenant');
  await accountCharge(R4, 50000, 'tenant'); // kiraci yok, yalniz aile uyesi -> alici yok
  // Bagimsiz inceleme (F2.05 korunur): sorumlu malik + malik kayitli: iliskisi belirtilmemis sakin (hane uyesi olabilir) hatirlatma ALMAZ, yalniz malik
  await resident(R, R5, 'owner', 'P H Malik Bes', { email: 'p.ro5@qa.example' });
  await resident(R, R5, 'resident', 'P H Sakin Bes', { email: 'p.rs5@qa.example' });
  await accountCharge(R5, 40000, 'owner');
  const rSettings = await call('GET', `${rBase}/settings`, MGR);
  const rEnable = await call('PUT', `${rBase}/settings`, MGR, { expected_settings_version: rSettings.body.settings_version, reminders: { enabled: true, min_overdue_minor: 5000, min_days_overdue: 5, min_interval_days: 14, max_consecutive: 3 } });
  if (rEnable.status !== 200) throw new Error(`hatirlatma acilamadi: ${JSON.stringify(rEnable.body)}`);
  const rPv = await call('POST', `${rBase}/reminders/preview`, MGR, { tone: 'friendly' });
  check(
    'P8: hatirlatma onizlemesi hesap basina: 5 kisi (R1 kiraci, R2 malik, R3 malik + kiraci, R5 malik), 4 daire, 5 hesap; kiracisiz dairenin kiraci hesabi "alici yok" (1); both dairede malik kiraci hesabi borcu icin ALICI DEGIL; sorumlu malik dairede belirtilmemis sakin ALICI DEGIL',
    rPv.status === 200 && rPv.body.person_count === 5 && rPv.body.apartment_count === 4 && rPv.body.account_count === 5 && rPv.body.excluded.no_recipient === 1 && rPv.body.can_send === true,
    rPv.body,
  );
  void queue.stopFinanceReminderQueue();
  mails.length = 0;
  const rSend = await call('POST', `${rBase}/reminders/send`, MGR, { tone: 'friendly', note: null, expected_hash: rPv.body.preview_hash, expected_apartment_count: rPv.body.apartment_count, expected_person_count: rPv.body.person_count, idempotency_key: key('rs') });
  queue.resumeFinanceReminderQueue();
  const rSummary = await queue.kickFinanceReminderQueue();
  const recipients = mails.map((m) => m.to).sort();
  const mailTo = (address) => mails.find((m) => m.to === address)?.text ?? '';
  check(
    'P8b: kuyruk iletileri YALNIZ hesap sahiplerine gonderir (R1 kiraci, R2 malik, R3 malik + kiraci, R5 malik); R1 maliki, R2 kiracisi ve R5 belirtilmemis sakini ALMAZ; her iletideki tutar alicinin HESABININ tutari (800 / 900 / 600 / 700 / 400 TL)',
    rSend.status === 201 && rSummary.sent === 5 && same(recipients, ['p.ro2@qa.example', 'p.ro3@qa.example', 'p.ro5@qa.example', 'p.rt1@qa.example', 'p.rt3@qa.example'])
      && /800,00 ₺/.test(mailTo('p.rt1@qa.example')) && /900,00 ₺/.test(mailTo('p.ro2@qa.example')) && /600,00 ₺/.test(mailTo('p.ro3@qa.example')) && !/700,00/.test(mailTo('p.ro3@qa.example')) && /700,00 ₺/.test(mailTo('p.rt3@qa.example'))
      && /400,00 ₺/.test(mailTo('p.ro5@qa.example')),
    { send: rSend.body, summary: rSummary, recipients },
  );
  const rPvAfter = await call('POST', `${rBase}/reminders/preview`, MGR, { tone: 'friendly' });
  check('P8c: gonderim sonrasi onizleme: hatirlatilan 5 hesap aralik nedeniyle hariç (interval 5), kalan alici yok', rPvAfter.body.excluded.interval === 5 && rPvAfter.body.person_count === 0, rPvAfter.body.excluded);
  // P8d (ikinci inceleme). Ardisik hatirlatma sayaci HESABIN son tahsilatina gore (siklik / sayac kaydi daire basina, temkinli): iki hatirlatmadan SONRA
  // odeme yapan kiraci hesabinin sayaci sifirlanir (ileti gider); hic odemeyen ev sahibi hesabi ardisik sinirda (2) elden takibe duser.
  {
    const C = await mkManaged('P Ardisik Sitesi', { 'C Blok': 1 });
    const [C1] = C.ids;
    const cBase = P(C.code);
    await setResponsible(C1, 'both');
    await resident(C, C1, 'owner', 'P Ardisik Malik', { email: 'p.co1@qa.example' });
    await resident(C, C1, 'tenant', 'P Ardisik Kiraci', { email: 'p.ct1@qa.example' });
    const cCharge = (amount, account) =>
      q(`INSERT INTO ledger_entries (site_code, apartment_id, kind, amount_minor, period, entry_date, due_date, payer_party, account_party) VALUES ($1, $2, 'charge', $3, $4, $5, $6, 'both', $7)`, [C.code, C1, amount, `${ago(105).slice(0, 7)}-01`, ago(105), ago(100), account]);
    await cCharge(80000, 'owner');
    await cCharge(90000, 'tenant');
    for (const daysBack of [60, 30]) {
      const run = Number(
        (
          await q(
            `INSERT INTO finance_reminder_runs (site_code, tone, params, apartment_count, person_count, with_amount_count, preview_hash, idempotency_key, request_fingerprint, run_on, status) VALUES ($1, 'friendly', '{}'::jsonb, 1, 1, 0, $2, $3, $2, $4::date, 'active') RETURNING id`,
            [C.code, 'c'.repeat(64), key('chist'), ago(daysBack)],
          )
        ).rows[0].id,
      );
      await q(`INSERT INTO finance_reminder_apartments (site_code, apartment_id, run_id, reminded_at) VALUES ($1, $2, $3, NOW() - make_interval(days => $4::int))`, [C.code, C1, run, daysBack]);
    }
    // kiraci hesabi son hatirlatmadan (30 gun once) SONRA kismi odedi (20 gun once): kiraci sayaci sifirlanir, gecikmis borc esigin ustunde kalir
    await q(`INSERT INTO ledger_entries (site_code, apartment_id, kind, amount_minor, period, entry_date, payer_party, method, account_party) VALUES ($1, $2, 'payment', -10000, $3, $4, 'both', 'cash', 'tenant')`, [C.code, C1, `${ago(20).slice(0, 7)}-01`, ago(20)]);
    const cSettings = await call('GET', `${cBase}/settings`, MGR);
    const cEnable = await call('PUT', `${cBase}/settings`, MGR, { expected_settings_version: cSettings.body.settings_version, reminders: { enabled: true, min_overdue_minor: 5000, min_days_overdue: 5, min_interval_days: 14, max_consecutive: 2 } });
    if (cEnable.status !== 200) throw new Error(`ardisik fiksturu: ${JSON.stringify(cEnable.body)}`);
    const cPv = await call('POST', `${cBase}/reminders/preview`, MGR, { tone: 'friendly' });
    check(
      'P8d (ikinci inceleme): ardisik hatirlatma sayaci HESABIN son tahsilatina gore: iki hatirlatmadan sonra odeme yapan kiraci hesabina ileti gider (1 kisi, 1 hesap); hic odemeyen ev sahibi hesabi ardisik sinirda (2) elden takipte (consecutive 1); onizleme elden takip ogesini HESABIYLA verir',
      cPv.status === 200 && cPv.body.person_count === 1 && cPv.body.account_count === 1 && cPv.body.excluded.consecutive === 1 && cPv.body.hand_follow_up_count === 1
        && same(cPv.body.hand_follow_up_accounts, [{ label: 'C Blok - Daire 1', account_party: 'owner' }]) && same(cPv.body.hand_follow_up_apartments, ['C Blok - Daire 1']),
      cPv.body,
    );
  }

  // ============================================================================================================
  // P9. ESZAMANLI tahsilat x borclandirma x ters kayit x duzeltme x CRM degisikligi
  // ============================================================================================================
  const X = await mkManaged('P Eszamanli Sitesi', { 'E Blok': 24 });
  const xBase = P(X.code);
  const xIndex = new Map(X.ids.map((id, i) => [id, i]));
  const baseResponsible = (i) => (i % 3 === 0 ? 'owner' : 'both');
  for (const [i, apt] of X.ids.entries()) {
    await setResponsible(apt, baseResponsible(i));
    await resident(X, apt, 'owner', `P Es Malik ${i + 1}`);
    if (i % 2 === 0) await resident(X, apt, 'tenant', `P Es Kiraci ${i + 1}`);
  }
  const occupantOf = (responsible, hasTenant) => (responsible === 'owner' ? 'owner' : hasTenant ? 'tenant' : 'owner');
  const expectedOld = (apt) => occupantOf(baseResponsible(xIndex.get(apt)), xIndex.get(apt) % 2 === 0);
  const xAidat = await createDefinition(X, { name: 'P Es Aidat', amount_minor: 10000, start_period: ym(0) });
  const seeds = [];
  for (const [i, apt] of X.ids.entries()) {
    const seeded = await payment(X, apt, 1000, { account_party: i % 2 === 0 ? 'tenant' : 'owner' });
    seeds.push(seeded.body.entry);
  }
  const rnd = mulberry32(20261021);
  const pick = (list) => list[Math.floor(rnd() * list.length)];
  const plannedPayments = (n) => Array.from({ length: n }, () => ({ apt: pick(X.ids), amount: 500 + Math.floor(rnd() * 2500), party: pick(['owner', 'tenant', null]), key: key('xp') }));
  const paymentCall = (p) => payment(X, p.apt, p.amount, { ...(p.party ? { account_party: p.party } : {}), idempotency_key: p.key });
  const xPv = await call('POST', `${xBase}/definitions/${xAidat.body.id}/preview`, MGR, { period: ym(0) });
  const ek1 = { name: 'P Es Bakim', distribution: 'equal', amount_minor: 24000, target: { type: 'site' }, due_date: dueNext, charge_party: 'occupant' };
  const ek2 = { name: 'P Es Cati', distribution: 'equal', amount_minor: 48000, target: { type: 'site' }, due_date: dueNext };
  const ek1Pv = await chargePreview(X, ek1);
  const ek2Pv = await chargePreview(X, ek2);
  const round1Payments = plannedPayments(24);
  const swaps = seeds.slice(6, 10).map((s) => ({ id: s.id, to: s.account_party === 'tenant' ? 'owner' : 'tenant' }));
  const deadlocksBeforeRound1 = hooks.deadlocks;
  const round1 = await Promise.all([
    call('POST', `${xBase}/definitions/${xAidat.body.id}/post`, MGR, { period: ym(0), expected_total_minor: xPv.body.total_minor, expected_apartment_count: xPv.body.apartment_count, expected_hash: xPv.body.preview_hash }),
    ...round1Payments.slice(0, 12).map(paymentCall),
    call('POST', `${xBase}/charges`, MGR, chargePostBody(ek1, ek1Pv)),
    ...seeds.slice(0, 6).map((s) => call('POST', `${xBase}/entries/${s.id}/reverse`, MGR, { reason: 'eszamanli', idempotency_key: key('xr') })),
    call('POST', `${xBase}/charges`, MGR, chargePostBody(ek2, ek2Pv)),
    ...swaps.map((s) => call('POST', `${xBase}/entries/${s.id}/correct`, MGR, { amount_minor: 900, entry_date: TODAY, method: 'cash', account_party: s.to, idempotency_key: key('xc') })),
    ...round1Payments.slice(12).map(paymentCall),
  ]);
  const round1Statuses = round1.map((r) => r.status);
  const [aidatRunId, ek1RunId, ek2RunId] = [round1[0], round1[13], round1[20]].map((r) => r.body?.run?.id ?? 0);
  const aidatAccounts = await accountsOfRun(aidatRunId);
  const ek1Accounts = await accountsOfRun(ek1RunId);
  const ek2Accounts = await accountsOfRun(ek2RunId);
  check(
    'P9: ESZAMANLI tur 1 (aidat borclandirma + 2 ek borc + 24 tahsilat (hesapli / hesapsiz) + 6 ters kayit + 4 hesap degistiren duzeltme = 37 istek): HEPSI 201, 40P01 YOK; borclandirma satirlari kurala gore (sorumlu malik -> ev sahibi, both + kiraci -> kiraci, kiracisiz -> ev sahibi; ek borc varsayilani ev sahibi)',
    round1Statuses.every((s) => s === 201) && hooks.deadlocks === deadlocksBeforeRound1
      && aidatAccounts.size === 24 && [...aidatAccounts].every(([apt, party]) => party === expectedOld(apt)) && ek1Accounts.size === 24 && [...ek1Accounts].every(([apt, party]) => party === expectedOld(apt))
      && ek2Accounts.size === 24 && [...ek2Accounts.values()].every((party) => party === 'owner'),
    { bad: round1Statuses.map((s, i) => [i, s, round1[i].body?.code]).filter(([, s]) => s !== 201), deadlocks: hooks.deadlocks - deadlocksBeforeRound1 },
  );
  const swapRows = (await q(`SELECT o.id AS original, r.account_party AS reversal_party, o.account_party AS original_party FROM ledger_entries r JOIN ledger_entries o ON o.id = r.reverses_entry_id WHERE o.id = ANY($1)`, [swaps.map((s) => s.id)])).rows;
  const swapNew = round1.slice(21, 25).map((r) => r.body?.entry?.account_party);
  check(
    'P9b: eszamanli duzeltmeler: ters kayit asilin hesabinda, yeni tahsilat istenen (diger) hesapta; eszamanli ters kayitlar asilin hesabinda',
    swapRows.length === 4 && swapRows.every((r) => r.reversal_party === r.original_party) && same(swapNew, swaps.map((s) => s.to))
      && round1.slice(14, 20).every((r, i) => r.body?.entry?.account_party === seeds[i].account_party),
    { swapRows, swapNew },
  );
  // tur 2: CRM degisiklikleri (kiraci cikar / tasinir, sorumlu degisir) tahsilat ve ek borc ile AYNI anda
  const ek3 = { name: 'P Es Boya', distribution: 'equal', amount_minor: 24000, target: { type: 'site' }, due_date: dueNext, charge_party: 'occupant' };
  const ek3Pv = await chargePreview(X, ek3);
  const moveOuts = X.ids.filter((_, i) => i % 2 === 0).slice(0, 4);
  const moveIns = X.ids.filter((_, i) => i % 2 === 1).slice(0, 4);
  const flips = X.ids.slice(12, 16);
  const responsibleNew = (apt) => {
    const r = baseResponsible(xIndex.get(apt));
    return flips.includes(apt) ? (r === 'owner' ? 'both' : 'owner') : r;
  };
  const tenantNew = (apt) => (xIndex.get(apt) % 2 === 0 && !moveOuts.includes(apt)) || moveIns.includes(apt);
  const expectedNew = (apt) => occupantOf(responsibleNew(apt), tenantNew(apt));
  const round2Payments = plannedPayments(16);
  const deadlocksBeforeRound2 = hooks.deadlocks;
  const round2 = await Promise.allSettled([
    ...round2Payments.slice(0, 8).map(paymentCall),
    call('POST', `${xBase}/charges`, MGR, chargePostBody(ek3, ek3Pv)),
    ...moveOuts.map((apt) => q(`UPDATE apartment_residencies SET is_current = FALSE, move_out_date = $2, updated_at = NOW() WHERE apartment_id = $1 AND relation = 'tenant' AND is_current = TRUE`, [apt, ago(1)])),
    ...moveIns.map(async (apt) => {
      const user = await mkUser(`P Es Yeni Kiraci ${xIndex.get(apt) + 1}`, 'apartment_owner');
      const person = await addPerson(X.code, { user });
      await q(`INSERT INTO apartment_residencies (site_code, apartment_id, person_id, relation, is_current, move_in_date, origin) VALUES ($1, $2, $3, 'tenant', TRUE, $4, 'manual')`, [X.code, apt, person, TODAY]);
    }),
    ...flips.map((apt) => q(`UPDATE apartments SET responsible_party = $2 WHERE id = $1`, [apt, responsibleNew(apt)])),
    ...round2Payments.slice(8).map(paymentCall),
  ]);
  const settledHttp = round2.filter((r) => r.status === 'fulfilled' && r.value && typeof r.value.status === 'number');
  const ek3Result = round2[8].status === 'fulfilled' ? round2[8].value : null;
  const ek3Ok = ek3Result && (ek3Result.status === 201 || (ek3Result.status === 409 && ek3Result.body.code === 'PREVIEW_STALE'));
  const ek3Accounts = ek3Result?.status === 201 ? await accountsOfRun(ek3Result.body.run.id) : new Map();
  check(
    'P9c: ESZAMANLI tur 2 (16 tahsilat + oturana ek borc + 4 kiraci cikisi + 4 kiraci girisi + 4 sorumlu degisimi): hata yok, tahsilatlar 201; ek borc 201 ya da (CRM onizlemeden sonra degistiyse) 409 PREVIEW_STALE; yazildiysa her satir dairenin ESKI ya da YENI durumunun hesabi; 40P01 YOK',
    round2.every((r) => r.status === 'fulfilled') && settledHttp.length === 17 && settledHttp.filter((r) => r.value !== ek3Result).every((r) => r.value.status === 201) && ek3Ok
      && [...ek3Accounts].every(([apt, party]) => party === expectedOld(apt) || party === expectedNew(apt)) && hooks.deadlocks === deadlocksBeforeRound2,
    { rejected: round2.filter((r) => r.status === 'rejected').map((r) => String(r.reason).slice(0, 200)), ek3: ek3Result && [ek3Result.status, ek3Result.body?.code], deadlocks: hooks.deadlocks - deadlocksBeforeRound2 },
  );
  const ek4 = await postCharge(X, { name: 'P Es Son', distribution: 'equal', amount_minor: 24000, target: { type: 'site' }, due_date: dueNext, charge_party: 'occupant' });
  const ek4Accounts = await accountsOfRun(ek4.post.body?.run?.id ?? 0);
  check(
    'P9d: CRM degisikliklerinden sonra oturana ek borc YENI duruma gore: cikan kiracinin dairesi ev sahibi, yeni tasinan kiraci (both) kiraci, sorumlusu malige donen daire ev sahibi',
    ek4.post.status === 201 && ek4Accounts.size === 24 && [...ek4Accounts].every(([apt, party]) => party === expectedNew(apt)),
    [...ek4Accounts].filter(([apt, party]) => party !== expectedNew(apt)),
  );
  const xPaymentsByKey = new Map((await q(`SELECT idempotency_key, account_party FROM ledger_entries WHERE site_code = $1 AND kind = 'payment' AND idempotency_key IS NOT NULL`, [X.code])).rows.map((r) => [r.idempotency_key, r.account_party]));
  const requested = [...round1Payments, ...round2Payments].filter((p) => p.party !== null);
  const xNulls = (await q(`SELECT COUNT(*)::INT AS n FROM ledger_entries WHERE site_code = $1 AND account_party IS NULL`, [X.code])).rows[0].n;
  const consistency = [];
  for (const apt of X.ids) {
    const sums = await sqlSums(X, apt);
    const api = await account(X, apt);
    if (api.body.accounts.owner.balance_minor !== sums.owner || api.body.accounts.tenant.balance_minor !== sums.tenant || api.body.balance_minor !== sums.owner + sums.tenant) consistency.push([apt, sums, api.body.accounts]);
  }
  check(
    'P9e: eszamanli turlardan sonra: hesap verilen her tahsilat istenen hesapta; sitede hesapsiz (NULL) yeni satir YOK; her dairenin hesap ekstresi bakiyeleri defterin hesap toplamlarina birebir',
    requested.every((p) => xPaymentsByKey.get(p.key) === p.party) && xNulls === 0 && consistency.length === 0,
    { wrong: requested.filter((p) => xPaymentsByKey.get(p.key) !== p.party).slice(0, 3), xNulls, consistency: consistency.slice(0, 3) },
  );

  // ============================================================================================================
  // P10. postPayment (sozlesme 2.1): kaynak izi, tekrar, cakisma, dogrulama
  // ============================================================================================================
  const actor = { user_code: MGR, role: 'site_manager' };
  const direct = (over = {}) =>
    withFinanceTransaction(M.code, (client) =>
      // K3 (P1-3): A3 ev sahibi hesabinda Aidat + Fon borcu birlikte acik olabilir; kisitsiz kayit reddedilirdi => hesap secimi (Isletme) acikca verilir
      postPayment(client, { siteCode: M.code, apartmentId: A3, accountParty: 'owner', amountMinor: 1500, paidOn: TODAY, method: 'transfer', description: null, sourceKind: 'bank_line', sourceId: 7001, idempotencyKey: 'p-bank-7001', fund: 'operating', actor, ...over }),
    );
  const first = await direct();
  const again = await direct();
  const conflictSource = await errorOf(direct({ sourceId: 7002 }));
  // ikinci inceleme: yalniz kaynak TURU farkli (ayni kimlik 7001): dekont 7001 ile banka satiri 7001 ayni tahsilat degildir
  const conflictKind = await errorOf(direct({ sourceKind: 'payment_notice' }));
  const conflictAccount = await errorOf(direct({ accountParty: 'tenant' }));
  const badKind = await errorOf(direct({ idempotencyKey: 'p-x-1', sourceKind: 'excel' }));
  const idOnly = await errorOf(direct({ idempotencyKey: 'p-x-2', sourceKind: null, sourceId: 5 }));
  const foreignApt = await errorOf(direct({ idempotencyKey: 'p-x-3', apartmentId: R1 }));
  const notice = await direct({ idempotencyKey: 'p-notice-1', accountParty: 'tenant', sourceKind: 'payment_notice', sourceId: 31, amountMinor: 2500 });
  const directRow = (await q(`SELECT account_party, source_kind, source_id::TEXT AS source_id FROM ledger_entries WHERE id = $1`, [first.entryId])).rows[0];
  const directAudit = (await q(`SELECT details FROM audit_log WHERE action = 'finance.payment.recorded' AND target_id = $1`, [String(first.entryId)])).rows[0]?.details;
  check(
    'P10: postPayment dogrudan: banka satiri kaynak izi (source_kind bank_line, source_id 7001) + hesap; makbuz ayni islemde; ayni anahtar tekrari AYNI kayit (replayed); ayni anahtar + farkli kaynak kimligi / kaynak turu / hesap 409; bilinmeyen kaynak turu / tursuz kimlik 400; baska sitenin dairesi 404; dekont kaynagi kiraci hesabina',
    first.replayed === false && first.accountParty === 'owner' && Number.isInteger(first.receiptId) && directRow.account_party === 'owner' && directRow.source_kind === 'bank_line' && directRow.source_id === '7001'
      && again.replayed === true && again.entryId === first.entryId && conflictSource?.code === 'IDEMPOTENCY_CONFLICT' && conflictKind?.code === 'IDEMPOTENCY_CONFLICT' && conflictAccount?.code === 'IDEMPOTENCY_CONFLICT'
      && badKind?.status === 400 && idOnly?.status === 400 && foreignApt?.status === 404 && notice.accountParty === 'tenant' && directAudit?.source_kind === 'bank_line' && directAudit?.account_party === 'owner',
    { first, again, conflictSource, conflictKind, conflictAccount, badKind, idOnly, foreignApt, directRow, directAudit },
  );
  const a3Account = await account(M, A3);
  const ooItem = await itemOf(OO.user, A3);
  const toItem = await itemOf(TO.user, A3);
  const bankForManager = a3Account.body.items.find((i) => i.id === first.entryId);
  const bankForResident = ooItem.recent.find((r) => r.id === first.entryId);
  check(
    'P10b: yonetici ekstresinde kaynak izi gorunur (bank_line / 7001); sakinde kaynak turu gorunur, kaynak KIMLIGI gizli (null); dekontla gelen kiraci tahsilati yalniz kiracinin hesabinda',
    bankForManager?.source_kind === 'bank_line' && bankForManager.source_id === 7001 && bankForResident?.source_kind === 'bank_line' && bankForResident.source_id === null
      && toItem.recent.some((r) => r.id === notice.entryId) && !ooItem.recent.some((r) => r.id === notice.entryId) && toItem.balance_minor === -2500,
    { bankForManager, bankForResident, to: toItem.balance_minor },
  );

  // ============================================================================================================
  // P11. Eski istemci uyumu: alanlar kaldirilmadi, yeni alanlar eklendi
  // ============================================================================================================
  const oldPay = await payment(M, A2, 1000);
  const accountAll = await account(M, A2);
  const balanceItem = (await call('GET', `${base}/balances?status=all&limit=50`, MGR)).body.items.find((i) => i.apartment_id === A2);
  const myItem = await itemOf(TN.user, A2);
  const hasKeys = (obj, keys) => obj && keys.every((k) => Object.prototype.hasOwnProperty.call(obj, k));
  check(
    'P11: eski istemci: tahsilat yaniti (entry, balance_minor, receipt, movement_id) + account_balance_minor; hesap ekstresi (apartment, currency, balance_minor, overdue_minor, items, next_before_id) + accounts / default_payment_account; bakiye satiri ve Borcum eski alanlari yerinde; eski istemcinin hesapsiz tahsilati borclu kiraci hesabina',
    oldPay.status === 201 && hasKeys(oldPay.body, ['entry', 'balance_minor', 'receipt', 'movement_id', 'account_balance_minor']) && oldPay.body.entry.account_party === 'tenant'
      && hasKeys(accountAll.body, ['apartment', 'currency', 'balance_minor', 'overdue_minor', 'items', 'next_before_id', 'account_party', 'accounts', 'show_tenant_account', 'has_current_tenant', 'default_payment_account'])
      && hasKeys(balanceItem, ['apartment_id', 'label', 'block_name', 'balance_minor', 'overdue_minor', 'owner_name', 'tenant_name', 'debt_minor', 'credit_minor', 'accounts'])
      && hasKeys(myItem, ['site_code', 'site_name', 'apartment_id', 'label', 'block_name', 'currency', 'balance_minor', 'overdue_minor', 'next_due_date', 'next_due_minor', 'payer_party', 'visible_from', 'offset_note', 'recent', 'account_party', 'accounts']),
    { pay: oldPay.body && Object.keys(oldPay.body), entry: oldPay.body?.entry?.account_party },
  );

  // ============================================================================================================
  // P12. Tum veritabani degismezleri
  // ============================================================================================================
  const invariants = (
    await q(
      `SELECT
         (SELECT COUNT(*) FROM ledger_entries r JOIN ledger_entries o ON o.id = r.reverses_entry_id
            WHERE COALESCE(r.account_party, CASE WHEN r.payer_party = 'tenant' THEN 'tenant' ELSE 'owner' END)
               <> COALESCE(o.account_party, CASE WHEN o.payer_party = 'tenant' THEN 'tenant' ELSE 'owner' END))::INT AS reversal_mismatch,
         (SELECT COUNT(*) FROM late_fee_run_lines ln JOIN ledger_entries l ON l.id = ln.ledger_entry_id
            WHERE ln.account_party <> COALESCE(l.account_party, CASE WHEN l.payer_party = 'tenant' THEN 'tenant' ELSE 'owner' END))::INT AS line_mismatch,
         (SELECT COUNT(*) FROM late_fee_run_lines ln WHERE ln.ledger_entry_id >= $1 AND ln.account_party IS NULL)::INT AS new_line_nulls,
         (SELECT COUNT(*) FROM ledger_entries WHERE id >= $1 AND account_party IS NULL AND NOT (id = ANY($2::BIGINT[])))::INT AS new_nulls`,
      [firstNewId, legacyIds],
    )
  ).rows[0];
  check(
    'P12: degismezler (tum veritabani): her ters kayit asilin hesabinda; her tazminat satiri defter satirinin hesabinda; bu bolumde yeni kodun yazdigi HICBIR satir hesapsiz degil (bilerek hesapsiz yazilan eski satirlar haric); bolum boyunca 40P01 = 0',
    invariants.reversal_mismatch === 0 && invariants.line_mismatch === 0 && invariants.new_line_nulls === 0 && invariants.new_nulls === 0 && hooks.deadlocks === deadlocksAtStart,
    { invariants, deadlocks: hooks.deadlocks - deadlocksAtStart },
  );
}
