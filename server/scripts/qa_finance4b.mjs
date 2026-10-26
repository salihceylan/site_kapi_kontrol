// Finans Faz 4b icin GERCEK PostgreSQL dogrulamasi (docs/PLATFORM_FINANS_4B.md). scripts/qa_platform_pg.mjs "finance4b" bolumu bu dosyayi cagirir:
//   QA_CONFIRM_DISPOSABLE_DB=yes QA_ONLY=finance4b DB_HOST=127.0.0.1 DB_PORT=... DB_USER=postgres node scripts/qa_platform_pg.mjs
// Her kontrol `check(ad, kosul, ek)`; sunucu, gercek authRequired + gercek JWT ile ayri bir kapida calisir (hiz sinirlayicilar devre disi; yetki katmanlari KALIR).
// NOT: dosya ASCII Turkce kullanir (diger QA bolumleriyle ayni); para hesabi BigInt ile yapilir.

import { createHash } from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';

export async function runFinance4bSection(ctx) {
  const { check, same, sleep, childEnv, installPoolHooks, finishChild, serverErrors } = ctx;
  await childEnv();
  process.env.DB_STATEMENT_TIMEOUT_MS = process.env.DB_STATEMENT_TIMEOUT_MS || '240000';
  process.env.FINANCE_RECEIPT_SECRET = 'qa-finance-receipt-secret-0123456789';
  const { pool, ensureDbSchema } = await import('../src/db.js');
  const q = (sql, params = []) => pool.query(sql, params);
  const hooks = installPoolHooks(pool);
  const http = await startHttp(pool);
  const { call, callRaw } = http;
  const { todayIso } = await import('../src/modules/people_common.js');
  const failCode = async (sql, params = []) => {
    try {
      await q(sql, params);
      return null;
    } catch (error) {
      return error.code ?? String(error.message);
    }
  };
  const failMessage = async (sql, params = []) => {
    try {
      await q(sql, params);
      return null;
    } catch (error) {
      return `${error.code}:${error.message}`;
    }
  };

  // --- tarih yardimcilari (gercek saat, Istanbul takvimi)
  const TODAY = todayIso();
  const dayNo = (iso) => Date.UTC(Number(iso.slice(0, 4)), Number(iso.slice(5, 7)) - 1, Number(iso.slice(8, 10))) / 86400000;
  const isoOf = (n) => new Date(n * 86400000).toISOString().slice(0, 10);
  const ago = (days) => isoOf(dayNo(TODAY) - days);
  const monthIndex = Number(TODAY.slice(0, 4)) * 12 + (Number(TODAY.slice(5, 7)) - 1);
  const monthStart = (offset) => {
    const index = monthIndex + offset;
    return `${String((index - (index % 12)) / 12).padStart(4, '0')}-${String((index % 12) + 1).padStart(2, '0')}-01`;
  };
  const ym = (offset) => monthStart(offset).slice(0, 7);
  const dayOf = (offset, day) => `${ym(offset)}-${String(day).padStart(2, '0')}`;

  // --- fabrikalar
  let nextUser = 41000;
  const mkUser = async (name, role = 'individual', options = {}) => {
    nextUser += 1;
    const code = nextUser;
    await q(
      `INSERT INTO users (user_code, full_name, email, role, password_hash, is_active, email_verified, approval_status, phone_number)
       VALUES ($1, $2, $3, $4, 'x', TRUE, $5, 'approved', $6)`,
      [code, name, options.email ?? `f4b${code}@qa.example`, role, options.verified ?? true, options.phone ?? null],
    );
    return code;
  };
  let nextSite = 1000000500;
  const mkSite = async (name, blocks, { approved = true } = {}) => {
    nextSite += 1;
    const code = nextSite;
    await q(`INSERT INTO sites (site_code, name, approval_status, approved_at) VALUES ($1, $2, $3, CASE WHEN $3 = 'approved' THEN NOW() END)`, [code, name, approved ? 'approved' : 'pending']);
    const apts = [];
    let order = 0;
    for (const [blockName, count] of Object.entries(blocks)) {
      order += 1;
      const blockId = Number((await q(`INSERT INTO site_blocks (site_code, block_name, sort_order) VALUES ($1, $2, $3) RETURNING id`, [code, blockName, order])).rows[0].id);
      for (let n = 1; n <= count; n += 1) {
        const id = Number((await q(`INSERT INTO apartments (site_code, block_id, unit_label, sort_order) VALUES ($1, $2, $3, $4) RETURNING id`, [code, blockId, `Daire ${n}`, n])).rows[0].id);
        apts.push({ id, block: blockName, blockId, n, label: `${blockName} - Daire ${n}` });
      }
    }
    return { code, apts, ids: apts.map((a) => a.id), apt: (label) => apts.find((a) => a.label === label) };
  };
  const link = {
    manager: (site, user) => q(`INSERT INTO site_manager_sites (site_code, manager_user_code) VALUES ($1, $2)`, [site, user]),
    member: (site, user, role) => q(`INSERT INTO site_memberships (site_code, user_code, role) VALUES ($1, $2, $3)`, [site, user, role]),
  };
  const addPerson = async (site, { user = null, name = null, email = null }) =>
    Number((await q(`INSERT INTO site_people (site_code, user_code, full_name, email) VALUES ($1, $2, $3, $4) RETURNING id`, [site, user, user === null ? name : null, email])).rows[0].id);
  // Varsayilan: uzun suredir oturan kisi (tasinma 2020-01-01). Sakin "Borcum" kapsami tasinma ayindan baslar (residentScopeSql);
  // tarih verilmezse kayit gunu esas alinir, bu yuzden eski aylari sinayan bolumler tarihli kisi kullanir. moveIn: null = tarihsiz kayit.
  const addResidency = (site, apartment, person, relation, { current = true, moveIn = '2020-01-01' } = {}) =>
    q(`INSERT INTO apartment_residencies (site_code, apartment_id, person_id, relation, is_current, move_in_date, origin) VALUES ($1, $2, $3, $4, $5, $6, 'manual')`, [site, apartment, person, relation, current, moveIn]);

  const P = (site) => `/manager/sites/${site}/finance`;
  let keyCounter = 0;
  const key = (label = 'k') => `f4b-${label}-${(keyCounter += 1)}-${Date.now()}`;

  const SUPER = await mkUser('F4B Super', 'super_user');
  const MGR = await mkUser('F4B Yonetici', 'site_manager');
  const MGR2 = await mkUser('F4B Baska Yonetici', 'site_manager');
  const BOARD = await mkUser('F4B Kurul', 'individual');
  const STAFF = await mkUser('F4B Gorevli', 'individual');
  const OUTSIDER = await mkUser('F4B Ilgisiz', 'individual');
  const RESIDENT = await mkUser('F4B Sakin', 'apartment_owner');
  const enableModule = (site) => call('PUT', `/manager/sites/${site}/modules/finance`, SUPER, { enabled: true });

  /** Yonetilen, finans modulu acik bir site kurar. */
  const mkManaged = async (name, blocks = { 'A Blok': 4 }) => {
    const site = await mkSite(name, blocks);
    await link.manager(site.code, MGR);
    await link.member(site.code, BOARD, 'BOARD_MEMBER');
    await link.member(site.code, STAFF, 'STAFF');
    const res = await enableModule(site.code);
    // Aidat ve Finans TEMEL modul (Kural 25): her sitede acik ve kapatilamaz / acilamaz (400 MODULE_NOT_TOGGLEABLE) - bu da "acik" demektir.
    if (res.status !== 200 && !(res.status === 400 && res.body?.code === 'MODULE_NOT_TOGGLEABLE')) throw new Error(`modul acilamadi: ${res.status} ${JSON.stringify(res.body)}`);
    return site;
  };
  const pay = (site, apartment, amount, over = {}) =>
    call('POST', `${P(site.code)}/payments`, MGR, { apartment_id: apartment, amount_minor: amount, entry_date: TODAY, method: 'cash', idempotency_key: key('pay'), ...over });
  const ledger = async (site, extra = '') => (await q(`SELECT * FROM ledger_entries WHERE site_code = $1 ${extra} ORDER BY id`, [site.code])).rows;

  // `ctx.skipSchema`: yalniz baska bir bolum (ornek: qa_platform_pg.mjs "parties") bu ortami kullanirken 040 sema denetimleri (A) atlanir.
  if (!ctx.skipSchema) {
    // ============================================================================================================
    // A. Sema (040): tablolar, kisitlar, degismezlik, FK davranislari, migration = ensureDbSchema
    // ============================================================================================================
    console.log('--- A. sema ---');
    const { FINANCE_4B_TABLES } = await import('../src/modules/finance_4b_schema.js');
    const present = (await q(`SELECT relname FROM pg_class WHERE relkind = 'r' AND relnamespace = 'public'::regnamespace AND relname = ANY($1)`, [FINANCE_4B_TABLES])).rows.map((r) => r.relname);
    check(`A1: ${FINANCE_4B_TABLES.length} yeni tablonun HEPSI var (ensureDbSchema ile)`, present.length === FINANCE_4B_TABLES.length, FINANCE_4B_TABLES.filter((t) => !present.includes(t)));
    const colInfo = (await q(`SELECT EXISTS (SELECT 1 FROM pg_attribute WHERE attrelid = 'ledger_entries'::regclass AND attname = 'late_fee_run_id' AND NOT attisdropped) AS led,
      EXISTS (SELECT 1 FROM pg_attribute WHERE attrelid = 'notification_preferences'::regclass AND attname = 'email_finance_reminders' AND NOT attisdropped) AS pref,
      (SELECT COUNT(*) FROM pg_constraint WHERE conrelid = 'ledger_entries'::regclass AND NOT convalidated)::int AS invalid`)).rows[0];
    check('A2: ledger_entries.late_fee_run_id + notification_preferences.email_finance_reminders eklendi; FK / CHECK DOGRULANMIS (NOT VALID kalmadi)', colInfo.led && colInfo.pref && colInfo.invalid === 0, colInfo);
    await ensureDbSchema(); // diger ajanlarin DDL'i dahil her sey bir kez kurulsun; olcut TEKRAR calistirmanin hicbir sey degistirmemesi
    const before = JSON.stringify((await q(`SELECT (SELECT COUNT(*) FROM pg_trigger WHERE NOT tgisinternal)::int AS t, (SELECT COUNT(*) FROM pg_indexes WHERE schemaname = 'public')::int AS i, (SELECT COUNT(*) FROM pg_constraint)::int AS c`)).rows[0]);
    const ensureStepsApplied = async () => {
      const client = await pool.connect();
      try {
        const { ensureFinance4bSchema } = await import('../src/modules/finance_4b_schema.js');
        return await ensureFinance4bSchema(client);
      } finally {
        client.release();
      }
    };
    await ensureDbSchema();
    await ensureDbSchema();
    const after = JSON.stringify((await q(`SELECT (SELECT COUNT(*) FROM pg_trigger WHERE NOT tgisinternal)::int AS t, (SELECT COUNT(*) FROM pg_indexes WHERE schemaname = 'public')::int AS i, (SELECT COUNT(*) FROM pg_constraint)::int AS c`)).rows[0]);
    check('A3: ensureDbSchema iki kez daha calisinca 040 semasi (tetikleyici, indeks, kisit sayisi) DEGISMEZ ve hicbir adim uygulanmaz', before === after && (await ensureStepsApplied()).length === 0, { before, after });

    // migration zinciri (040 dosyasi) = ensureDbSchema: ayri bir veritabaninda migrate.js ile kurulup katalog karsilastirilir
    const catalogDump = async (client) => {
      const T = [...FINANCE_4B_TABLES, 'ledger_entries', 'notification_preferences'];
      const out = {};
      out.cols = (await client.query(`SELECT table_name, column_name, data_type, is_nullable, column_default FROM information_schema.columns WHERE table_schema = 'public' AND table_name = ANY($1) ORDER BY 1, 2`, [T])).rows;
      out.cons = (await client.query(`SELECT conrelid::regclass::text AS t, conname, pg_get_constraintdef(oid) AS d, convalidated FROM pg_constraint WHERE conrelid::regclass::text = ANY($1) ORDER BY 1, 2`, [T])).rows;
      out.idx = (await client.query(`SELECT tablename, indexname, indexdef FROM pg_indexes WHERE schemaname = 'public' AND tablename = ANY($1) ORDER BY 1, 2`, [T])).rows;
      out.trg = (await client.query(`SELECT c.relname AS t, tg.tgname, regexp_replace(pg_get_triggerdef(tg.oid), '\\s+', ' ', 'g') AS d FROM pg_trigger tg JOIN pg_class c ON c.oid = tg.tgrelid WHERE NOT tg.tgisinternal AND c.relname = ANY($1) ORDER BY 1, 2`, [T])).rows;
      out.fn = (await client.query(`SELECT proname, regexp_replace(prosrc, '\\s+', ' ', 'g') AS s FROM pg_proc WHERE pronamespace = 'public'::regnamespace AND prosrc LIKE '%f4b:%' ORDER BY 1`)).rows;
      return out;
    };
    {
      const pg = (await import('pg')).default;
      const chainDb = `${process.env.DB_NAME}_chain`;
      const admin = new pg.Client({ ...ctx.connectConfig(process.env.QA_ADMIN_DB || 'postgres') });
      await admin.connect();
      await admin.query(`DROP DATABASE IF EXISTS "${chainDb}" WITH (FORCE)`);
      await admin.query(`CREATE DATABASE "${chainDb}"`);
      const migrated = ctx.runMigrate(chainDb, ctx.MIGRATIONS_DIR);
      const chainClient = new pg.Client({ ...ctx.connectConfig(chainDb) });
      await chainClient.connect();
      const chainDump = await catalogDump(chainClient);
      // 040 dosyasini AYNI veritabanina dogrudan IKI KEZ daha uygula (migrate kaydi atlanarak): idempotent olmali
      const file040 = fs.readdirSync(ctx.MIGRATIONS_DIR).find((name) => /^040_.+\.sql$/.test(name));
      const sql040 = fs.readFileSync(path.join(ctx.MIGRATIONS_DIR, file040), 'utf8');
      let reapplyError = null;
      try {
        await chainClient.query(sql040);
        await chainClient.query(sql040);
      } catch (error) {
        reapplyError = `${error.code ?? ''} ${error.message}`;
      }
      const reappliedDump = await catalogDump(chainClient);
      check('A4c: 040 migration dosyasi ayni veritabanina IKI KEZ daha dogrudan uygulanir: hata yok ve katalog (tablo, sutun, kisit, indeks, tetikleyici, islev) DEGISMEZ (idempotent)',
        reapplyError === null && ['cols', 'cons', 'idx', 'trg', 'fn'].every((part) => same(chainDump[part], reappliedDump[part])), reapplyError);
      const stepsAfterMigrate = await (async () => {
        const { ensureFinance4bSchema } = await import('../src/modules/finance_4b_schema.js');
        return ensureFinance4bSchema(chainClient);
      })();
      await chainClient.end();
      await admin.query(`DROP DATABASE IF EXISTS "${chainDb}" WITH (FORCE)`);
      await admin.end();
      const ensureClient = await pool.connect();
      const ensureDump = await catalogDump(ensureClient);
      ensureClient.release();
      const dumpOf = ensureDump;
      for (const part of ['cols', 'cons', 'idx', 'trg', 'fn']) {
        check(`A4: migrate zinciri (001..son, 040 dahil) = ensureDbSchema: ${part} (${dumpOf[part].length} nesne) birebir`, migrated && same(chainDump[part], dumpOf[part]), {
          migrated,
          onlyChain: chainDump[part].filter((r) => !dumpOf[part].some((x) => JSON.stringify(x) === JSON.stringify(r))).slice(0, 2),
          onlyEnsure: dumpOf[part].filter((r) => !chainDump[part].some((x) => JSON.stringify(x) === JSON.stringify(r))).slice(0, 2),
        });
      }
      check('A4b: migrate ile kurulmus veritabaninda ensureFinance4bSchema HICBIR adim uygulamaz (no-op)', migrated && stepsAfterMigrate.length === 0, stepsAfterMigrate);
    }

    // --- yardimci: A bolumu icin ortak site
    const sc = await mkManaged('F4B Sema', { 'A Blok': 3 });
    const [a1, a2, a3] = sc.ids;
    const insertPayment = async (over = {}) => {
      const v = { kind: 'payment', amount_minor: -1000, period: monthStart(0), entry_date: TODAY, payer_party: 'both', apartment_id: a1, method: 'cash', ...over };
      const cols = Object.keys(v);
      return (await q(`INSERT INTO ledger_entries (site_code, ${cols.join(', ')}) VALUES ($1, ${cols.map((_, i) => `$${i + 2}`).join(', ')}) RETURNING id`, [sc.code, ...cols.map((c) => v[c])])).rows[0].id;
    };
    const pay1 = Number(await insertPayment());
    const pay2 = Number(await insertPayment({ apartment_id: a2, amount_minor: -2500 }));

    // makbuz kisitlari / tetikleyicileri (DB duzeyi)
    const insertReceipt = (over = {}) => {
      const v = {
        receipt_year: 2026, receipt_no: 900, kind: 'collection', ledger_entry_id: pay1, cancels_receipt_id: null, apartment_id: a1, amount_minor: 1000, paid_on: TODAY, issued_on: TODAY,
        snapshot: '{}', snapshot_sha256: 'a'.repeat(64), verification_code: 'ABCDEF123456', ...over,
      };
      const cols = Object.keys(v);
      return failCode(`INSERT INTO receipts (site_code, ${cols.join(', ')}) VALUES ($1, ${cols.map((_, i) => `$${i + 2}`).join(', ')})`, [sc.code, ...cols.map((c) => v[c])]);
    };
    const badReceipts = [
      ['gecersiz tur', { kind: 'x' }], ['tutar 0', { amount_minor: 0 }], ['numara 0', { receipt_no: 0 }], ['yil 1999', { receipt_year: 1999 }],
      ['iptal makbuzu hedefsiz', { kind: 'cancellation', cancel_reason_code: 'issued_in_error' }], ['tahsilatta iptal nedeni', { cancel_reason_code: 'issued_in_error' }],
      ['gecersiz iptal nedeni', { kind: 'cancellation', cancels_receipt_id: 1, cancel_reason_code: 'x' }], ['kisa dogrulama kodu', { verification_code: 'ABC' }],
      ['kisa ozet', { snapshot_sha256: 'abc' }], ['snapshot dizi', { snapshot: '[]' }], ['201 karakter not', { kind: 'cancellation', cancels_receipt_id: 1, cancel_reason_code: 'issued_in_error', cancel_note: 'x'.repeat(201) }],
    ];
    const badReceiptResults = [];
    for (const [label, over] of badReceipts) badReceiptResults.push([label, await insertReceipt(over)]);
    check(`A5: receipts: ${badReceipts.length} gecersiz kombinasyonun HEPSI reddedilir (CHECK 23514 ya da once calisan tetikleyici P0001)`, badReceiptResults.every(([, code]) => code === '23514' || code === 'P0001') && badReceiptResults.filter(([, c]) => c === '23514').length >= 6, badReceiptResults);
    check('A5b: receipts tetikleyicisi: ODEMEYLE UYUSMAYAN tutar / baska daire / olmayan odeme P0001', (await insertReceipt({ amount_minor: 999 })) === 'P0001' && (await insertReceipt({ apartment_id: a2 })) === 'P0001' && (await insertReceipt({ ledger_entry_id: 999999999 })) === 'P0001' && (await insertReceipt({ paid_on: ago(1) })) === 'P0001');
    const goodReceipt = await insertReceipt();
    check('A5c: gecerli makbuz kabul; AYNI odemeye ikinci AKTIF makbuz P0001; ayni numara 23505', goodReceipt === null && (await insertReceipt({ receipt_no: 901 })) === 'P0001' && (await insertReceipt({ receipt_no: 900, ledger_entry_id: pay2, apartment_id: a2, amount_minor: 2500 })) === '23505');
    const rid = Number((await q(`SELECT id FROM receipts WHERE site_code = $1 AND receipt_no = 900`, [sc.code])).rows[0].id);
    check('A5d: iptal makbuzu hedefiyle uyusmali (baska odeme / tutar P0001); gecerli iptal kabul; AYNI makbuza ikinci iptal 23505; iptalden sonra yeni makbuz serbest',
      (await insertReceipt({ kind: 'cancellation', cancels_receipt_id: rid, cancel_reason_code: 'issued_in_error', receipt_no: 902, ledger_entry_id: pay2 })) === 'P0001'
        && (await insertReceipt({ kind: 'cancellation', cancels_receipt_id: rid, cancel_reason_code: 'issued_in_error', receipt_no: 902, amount_minor: 5 })) === 'P0001'
        && (await insertReceipt({ kind: 'cancellation', cancels_receipt_id: rid, cancel_reason_code: 'issued_in_error', receipt_no: 902 })) === null
        && (await insertReceipt({ kind: 'cancellation', cancels_receipt_id: rid, cancel_reason_code: 'issued_in_error', receipt_no: 903 })) === '23505'
        && (await insertReceipt({ receipt_no: 904 })) === null);
    await q(`INSERT INTO receipt_counters (site_code, receipt_year, last_no) VALUES ($1, 2026, 5)`, [sc.code]);
    const immutable = [
      await failMessage(`UPDATE receipts SET amount_minor = 5 WHERE id = $1`, [rid]),
      await failMessage(`DELETE FROM receipts WHERE id = $1`, [rid]),
      await failMessage(`UPDATE receipts SET issued_by = NULL, cancel_note = 'x' WHERE id = $1`, [rid]),
      await failMessage(`TRUNCATE receipts`),
      await failMessage(`TRUNCATE receipt_counters`),
      await failMessage(`UPDATE receipt_counters SET last_no = last_no + 2 WHERE site_code = $1`, [sc.code]),
      await failMessage(`DELETE FROM receipt_counters WHERE site_code = $1`, [sc.code]),
    ];
    check('A6: makbuz UPDATE / DELETE / TRUNCATE ve sayac atlama (+2) / silme tetikleyici hatasi verir', immutable.every((m) => m !== null), immutable);
    check('A6b: sayac yalniz +1 ilerler (UPDATE last_no = last_no + 1 gecer)', (await failMessage(`UPDATE receipt_counters SET last_no = last_no + 1 WHERE site_code = $1`, [sc.code])) === null);

    // kullanici silme: *_by NULL olur, belge KALIR
    const tmpUser = await mkUser('F4B Silinecek Kasiyer', 'site_manager');
    const tmpPay = Number(await insertPayment({ apartment_id: a3, amount_minor: -700, created_by: tmpUser }));
    await q(`INSERT INTO receipts (site_code, receipt_year, receipt_no, kind, ledger_entry_id, apartment_id, amount_minor, paid_on, issued_on, snapshot, snapshot_sha256, verification_code, issued_by)
             VALUES ($1, 2026, 950, 'collection', $2, $3, 700, $4, $4, '{}', $5, 'ABCDEF123456', $6)`, [sc.code, tmpPay, a3, TODAY, 'b'.repeat(64), tmpUser]);
    const userDel = await failCode(`DELETE FROM users WHERE user_code = $1`, [tmpUser]);
    const afterDel = (await q(`SELECT issued_by FROM receipts WHERE site_code = $1 AND receipt_no = 950`, [sc.code])).rows[0];
    check('A7: kullanici silme BOZULMAZ: receipts.issued_by NULL olur, makbuz satiri KALIR', userDel === null && afterDel && afterDel.issued_by === null, { userDel, afterDel });
    check('A7b: created_by -> NULL UPDATE\'i kullanici VARKEN reddedilir (istisna yalniz silinmis kullanici icin)', (await failMessage(`UPDATE receipts SET issued_by = NULL WHERE site_code = $1 AND receipt_no = 904`, [sc.code])) !== null);

    // site silme CASCADE (makbuz, sayac, tum 4b tablolari)
    const delSite = await mkManaged('F4B Silinecek Site', { 'A Blok': 2 });
    const dPay = Number((await q(`INSERT INTO ledger_entries (site_code, apartment_id, kind, amount_minor, period, entry_date, payer_party, method) VALUES ($1, $2, 'payment', -100, $3, $4, 'both', 'cash') RETURNING id`, [delSite.code, delSite.ids[0], monthStart(0), TODAY])).rows[0].id);
    await q(`INSERT INTO receipt_counters (site_code, receipt_year, last_no) VALUES ($1, 2026, 1)`, [delSite.code]);
    await q(`INSERT INTO receipts (site_code, receipt_year, receipt_no, kind, ledger_entry_id, apartment_id, amount_minor, paid_on, issued_on, snapshot, snapshot_sha256, verification_code) VALUES ($1, 2026, 1, 'collection', $2, $3, 100, $4, $4, '{}', $5, 'ABCDEF123456')`, [delSite.code, dPay, delSite.ids[0], TODAY, 'c'.repeat(64)]);
    const rcpt = Number((await q(`SELECT id FROM receipts WHERE site_code = $1`, [delSite.code])).rows[0].id);
    await q(`INSERT INTO receipt_print_events (site_code, receipt_id, copy_number) VALUES ($1, $2, 1)`, [delSite.code, rcpt]);
    const siteDel = await failCode(`DELETE FROM sites WHERE site_code = $1`, [delSite.code]);
    const leftovers = (await q(`SELECT (SELECT COUNT(*) FROM receipts WHERE site_code = $1)::int AS r, (SELECT COUNT(*) FROM receipt_counters WHERE site_code = $1)::int AS c, (SELECT COUNT(*) FROM receipt_print_events WHERE site_code = $1)::int AS p, (SELECT COUNT(*) FROM ledger_entries WHERE site_code = $1)::int AS l`, [delSite.code])).rows[0];
    check('A8: SITE SILININCE makbuz, sayac, basim olaylari ve defter CASCADE ile silinir (tetikleyici "site artik yok" istisnasi); kalinti yok', siteDel === null && Object.values(leftovers).every((n) => n === 0), { siteDel, leftovers });
  }

  const t = {
    check, same, sleep, q, call, callRaw, pool, hooks, ctx, serverErrors, TODAY, dayNo, isoOf, ago, monthStart, ym, dayOf, mkUser, mkSite, mkManaged, link, addPerson, addResidency,
    P, key, pay, ledger, failCode, failMessage, enableModule, users: { SUPER, MGR, MGR2, BOARD, STAFF, OUTSIDER, RESIDENT },
  };
  // Bolumler: QA_PART (ya da ctx.parts) verilmezse PART_NAMES; EXTRA_PARTS yalniz acikca istenince calisir (ornek: "parties").
  const parts = ctx.parts ?? (process.env.QA_PART || '').split(',').map((x) => x.trim()).filter(Boolean);
  const wants = (name) => (parts.length === 0 ? PART_NAMES.includes(name) : parts.includes(name));
  for (const name of [...PART_NAMES, ...Object.keys(EXTRA_PARTS)]) {
    if (!wants(name)) continue;
    const part = await import(EXTRA_PARTS[name] ?? `./qa_finance4b_${name}.mjs`);
    await part.default(t);
  }

  await http.close();
  await finishChild(pool);
}

// Bolum dosyalari: scripts/qa_finance4b_<ad>.mjs (varsayilan export async (t) => ...). QA_PART=receipts,accounts ile secilir.
const PART_NAMES = ['receipts', 'accounts', 'expenses', 'reports', 'late_fee', 'reminders', 'locks', 'review', 'r15', 'resident_scope'];
// Ayri bolum olarak kosulan, ayni ortami kullanan dosyalar (varsayilan kosuda YOK; ctx.parts / QA_PART ile): iki hesap (IP-1A) -> qa_platform_pg.mjs "parties".
// Iki kasa (Isletme / Yatirim ve Demirbas Fon, 080) -> qa_platform_pg.mjs "funds" (govde scripts/qa_finance_funds_section.mjs).
const EXTRA_PARTS = { parties: './qa_finance_parties_section.mjs', funds: './qa_finance_funds_section.mjs' };

/** Gercek authRequired + gercek JWT; hiz sinirlayicilar devre disi, requireSiteManager/requireSuperUser KALIR. */
async function startHttp(pool) {
  const express = (await import('express')).default;
  const { signAccessToken } = await import('../src/jwt.js');
  const { requireSiteManager, requireSuperUser } = await import('../src/middlewares/auth_middleware.js');
  const { financeRouter } = await import('../src/modules/finance_routes.js');
  const { finance4bRouter } = await import('../src/modules/finance_4b_routes.js');
  const { financeFundsRouter } = await import('../src/modules/finance_funds_routes.js');
  const { moduleRouter } = await import('../src/modules/module_routes.js');
  const { adminRouter } = await import('../src/routes/admin_routes.js');
  const keep = new Set([requireSiteManager, requireSuperUser]);
  for (const router of [financeRouter, finance4bRouter, financeFundsRouter, moduleRouter, adminRouter]) {
    for (const layer of router.stack) {
      if (!layer.route) continue;
      const stack = layer.route.stack;
      for (let i = 1; i < stack.length - 1; i += 1) {
        if (!keep.has(stack[i].handle)) stack[i].handle = (_req, _res, next) => next();
      }
    }
  }
  const app = express();
  app.use(express.json());
  app.use(financeRouter);
  app.use(finance4bRouter);
  app.use(financeFundsRouter);
  app.use(moduleRouter);
  app.use(adminRouter);
  const server = await new Promise((resolve) => {
    const s = app.listen(0, '127.0.0.1', () => resolve(s));
  });
  const base = `http://127.0.0.1:${server.address().port}`;
  const tokens = new Map();
  const tokenFor = async (userCode) => {
    if (!tokens.has(userCode)) {
      const row = (await pool.query(`SELECT user_code AS id, email, role, password_hash FROM users WHERE user_code = $1`, [userCode])).rows[0];
      tokens.set(userCode, signAccessToken({ id: row.id, email: row.email, role: row.role }, { passwordHash: row.password_hash }));
    }
    return tokens.get(userCode);
  };
  async function call(method, urlPath, userCode, body, rawBody) {
    const headers = { 'content-type': 'application/json' };
    if (userCode !== null) headers.authorization = `Bearer ${await tokenFor(userCode)}`;
    let response;
    try {
      response = await fetch(`${base}${urlPath}`, { method, headers, body: rawBody !== undefined ? rawBody : body === undefined ? undefined : JSON.stringify(body) });
    } catch (error) {
      throw new Error(`istek basarisiz: ${method} ${urlPath} (${error?.cause?.code || error?.cause?.message || error?.message})`);
    }
    let json = null;
    try {
      json = await response.json();
    } catch (_e) {
      // govdesiz yanit
    }
    return { status: response.status, body: json, headers: response.headers };
  }
  async function callRaw(method, urlPath, userCode, buffer, headers = {}) {
    const h = { ...headers };
    if (userCode !== null) h.authorization = `Bearer ${await tokenFor(userCode)}`;
    let response;
    try {
      response = await fetch(`${base}${urlPath}`, { method, headers: h, body: buffer });
    } catch (error) {
      throw new Error(`istek basarisiz: ${method} ${urlPath} (${error?.cause?.code || error?.cause?.message || error?.message})`);
    }
    const bytes = Buffer.from(await response.arrayBuffer());
    let json = null;
    try {
      json = JSON.parse(bytes.toString('utf8'));
    } catch (_e) {
      // ikili / govdesiz yanit
    }
    return { status: response.status, body: json, bytes, headers: response.headers };
  }
  return { call, callRaw, close: () => new Promise((resolve) => { server.closeAllConnections?.(); server.close(resolve); }) };
}

export const sha256 = (text) => createHash('sha256').update(text).digest('hex');
