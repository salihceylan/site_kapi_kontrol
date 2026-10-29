// Teklif karsilastirma alanlari (098) + onayli teklif revizyonu / degismezlik (099) icin GERCEK PostgreSQL kosusu. `npm test` ICINDE DEGILDIR.
//
// Kullanim (BOS bir veritabani; once migration zinciri uygulanir ya da bu betik ensureQuoteSchema ile 098 + 099'u kurar):
//   DB_HOST=127.0.0.1 DB_PORT=55498 DB_NAME=eqq_test DB_USER=postgres DB_PASSWORD=x node scripts/migrate.js --apply --yes
//   DB_HOST=127.0.0.1 DB_PORT=55498 DB_NAME=eqq_test DB_USER=postgres DB_PASSWORD=x node scripts/qa_equipment_quotes_pg.mjs
// Cikis kodu 0 = hepsi PASS. Kendi test sitelerini olusturur ve sonda siler (site silme CASCADE'i de sinanir).
//
// Kapsam: ensure idempotansi (her sey varken DDL 0; eksikken yalniz eksikler; migration dosyalari tekrar calisir), CHECK / benzersizlik / bilesik FK,
// DEGISMEZLIK TETIKLEYICISI (kabul edilmis satir UPDATE / DELETE reddi; izinli gecisler: gider / sozlesme baglantisi bir kez, kabul geri alma, created_by SET NULL, site CASCADE),
// servis akislari (olustur / yerinde duzenle / revize / gecmis / kabul + onceki kayit onayi), es zamanli cift revizyon, IDOR (baska sitenin teklifi 404).
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
let failures = 0;
let total = 0;
function check(name, ok, extra) {
  total += 1;
  if (ok) {
    console.log(`PASS ${name}`);
  } else {
    failures += 1;
    console.log(`FAIL ${name}`, extra === undefined ? '' : JSON.stringify(extra));
  }
}

const { pool } = await import('../src/db.js');
const schema = await import('../src/modules/equipment_quote_schema.js');
const svc = await import('../src/modules/equipment_service.js');
const q = (sql, params = []) => pool.query(sql, params);

/** fn() hata firlatmali; hata kodu (PlatformError.code ya da pg SQLSTATE) beklenenle ayni olmali. */
async function failsWith(fn, code) {
  try {
    await fn();
    return { ok: false, got: 'no error' };
  } catch (error) {
    return { ok: error?.code === code, got: error?.code ?? error?.message };
  }
}

const stamp = Date.now();
const rnd = () => 700000 + Math.floor(Math.random() * 200000);
const makeSite = async (label) => {
  const r = await q(`INSERT INTO sites (name, mqtt_site_id) VALUES ($1, $2) RETURNING site_code`, [`QA Teklif ${label} ${stamp}`, rnd()]);
  return Number(r.rows[0].site_code);
};

// --- 0. Sema: kurulum + ensure idempotansi ----------------------------------------------------------------------------------------------------------------------
const cat = async () => {
  const r = await q(
    `SELECT
       ARRAY(SELECT attname::TEXT FROM pg_attribute WHERE attrelid = 'equipment_quotes'::regclass AND attnum > 0 AND NOT attisdropped) AS columns,
       ARRAY(SELECT conname::TEXT FROM pg_constraint WHERE conrelid = 'equipment_quotes'::regclass) AS constraints,
       ARRAY(SELECT indexname::TEXT FROM pg_indexes WHERE schemaname = 'public' AND tablename = 'equipment_quotes') AS indexes,
       ARRAY(SELECT tgname::TEXT FROM pg_trigger WHERE tgrelid = 'equipment_quotes'::regclass AND NOT tgisinternal) AS triggers,
       EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'trg_equipment_quotes_locked' AND prosrc LIKE '%eqq:1%') AS has_fn`,
  );
  return r.rows[0];
};
const countingClient = () => {
  const sent = [];
  return { sent, query: async (sql, params) => { if (!/to_regclass|^SET lock_timeout|^RESET lock_timeout/.test(sql)) sent.push(String(sql).trim().slice(0, 60)); return pool.query(sql, params); } };
};

await schema.ensureQuoteSchema({ query: (sql, params) => pool.query(sql, params) });
let c = await cat();
const wantColumns = [...schema.QUOTE_COLUMNS_098, ...schema.QUOTE_COLUMNS_099];
check('sema: 098 + 099 sutunlari var', wantColumns.every((x) => c.columns.includes(x)), c.columns);
check('sema: kisitlar (delivery, note, revision_no, revision_reason, previous_self, revision, site_id, previous_fkey)', ['chk_equipment_quotes_delivery', 'chk_equipment_quotes_note', 'chk_equipment_quotes_revision_no', 'chk_equipment_quotes_revision_reason', 'chk_equipment_quotes_previous_self', 'chk_equipment_quotes_revision', 'uq_equipment_quotes_site_id', 'equipment_quotes_previous_fkey'].every((x) => c.constraints.includes(x)), c.constraints);
check('sema: benzersiz previous_id dizini + isaretli islev + tetikleyici', c.indexes.includes('uq_equipment_quotes_previous') && c.has_fn && c.triggers.includes('trg_equipment_quotes_locked'), c);

const idle = countingClient();
await schema.ensureQuoteSchema(idle);
check('ensure: her sey varken hicbir DDL gonderilmez', idle.sent.length === 0, idle.sent);

for (const file of ['098_equipment_quote_compare.sql', '099_equipment_quote_revisions.sql']) {
  const sql = readFileSync(path.join(here, '..', 'migrations', file), 'utf8');
  let error = null;
  try {
    await q(sql);
  } catch (e) {
    error = e;
  }
  check(`migration ${file} tekrar calisir (idempotent)`, error === null, error?.message);
}

// Eksik kurulum simulasyonu: hepsini dusur, ensure yalniz eksikleri geri kurar.
await q('DROP TRIGGER IF EXISTS trg_equipment_quotes_locked ON equipment_quotes');
await q('DROP FUNCTION IF EXISTS trg_equipment_quotes_locked()');
await q('DROP INDEX IF EXISTS uq_equipment_quotes_previous');
await q(`ALTER TABLE equipment_quotes DROP CONSTRAINT IF EXISTS equipment_quotes_previous_fkey, DROP CONSTRAINT IF EXISTS uq_equipment_quotes_site_id,
  DROP CONSTRAINT IF EXISTS chk_equipment_quotes_revision, DROP CONSTRAINT IF EXISTS chk_equipment_quotes_previous_self, DROP CONSTRAINT IF EXISTS chk_equipment_quotes_revision_reason,
  DROP CONSTRAINT IF EXISTS chk_equipment_quotes_revision_no, DROP CONSTRAINT IF EXISTS chk_equipment_quotes_note, DROP CONSTRAINT IF EXISTS chk_equipment_quotes_delivery`);
await q(`ALTER TABLE equipment_quotes DROP COLUMN IF EXISTS revision_reason, DROP COLUMN IF EXISTS previous_id, DROP COLUMN IF EXISTS revision_no,
  DROP COLUMN IF EXISTS vat_included, DROP COLUMN IF EXISTS note, DROP COLUMN IF EXISTS delivery_days`);
c = await cat();
check('eski sema: 098 / 099 nesneleri yok (simulasyon)', !c.columns.includes('revision_no') && !c.columns.includes('delivery_days') && !c.has_fn && c.triggers.length === 0, c);
const repair = countingClient();
await schema.ensureQuoteSchema(repair);
c = await cat();
check('ensure: eksikleri kurar (sutun, kisit, dizin, islev, tetikleyici)', wantColumns.every((x) => c.columns.includes(x)) && c.has_fn && c.triggers.length === 1 && c.indexes.includes('uq_equipment_quotes_previous') && c.constraints.includes('equipment_quotes_previous_fkey'), c);
check('ensure: yalniz eksik adimlar calisti (en az bir ALTER, hata yok)', repair.sent.length >= 8, repair.sent);
const again = countingClient();
await schema.ensureQuoteSchema(again);
check('ensure: ikinci cagri yine hicbir DDL gondermez', again.sent.length === 0, again.sent);

// --- Tohum ----------------------------------------------------------------------------------------------------------------------------------------------------
const siteA = await makeSite('A');
const siteB = await makeSite('B');
const userRow = await q(`INSERT INTO users (full_name, email, role, password_hash) VALUES ($1, $2, 'site_manager', 'x') RETURNING user_code`, ['QA Yonetici', `qa-eqq-${stamp}@example.com`]);
const userCode = Number(userRow.rows[0].user_code);
const actor = { user_code: userCode, userCode, id: userCode, role: 'site_manager', full_name: 'QA Yonetici' };
const access = { canWrite: true, userCode };
await q(`INSERT INTO site_modules (site_code, module_code, enabled) VALUES ($1, 'contracts', TRUE), ($1, 'equipment', TRUE) ON CONFLICT (site_code, module_code) DO UPDATE SET enabled = TRUE`, [siteA]);
const vendor = await q(`INSERT INTO contract_vendors (site_code, name, category) VALUES ($1, 'QA Asansor A.S.', 'asansor') RETURNING id`, [siteA]);
const vendorId = Number(vendor.rows[0].id);
const future = '2099-12-31';
const row = async (id) => (await q(`SELECT * FROM equipment_quotes WHERE id = $1`, [id])).rows[0];
const mk = (extra = {}) => svc.createQuote({ siteCode: siteA, actor, access, body: { topic: 'Asansor bakimi', vendor_name: 'Yildiz', amount_kurus: 320000, ...extra } });

// --- 1. Kisitlar ----------------------------------------------------------------------------------------------------------------------------------------------
const base = (await mk({ valid_until: future, delivery_days: 14, note: 'Kontrol + kontak seti', vat_included: false })).quote;
check('olustur: karsilastirma alanlari kaydedilir ve okunur', base.delivery_days === 14 && base.note === 'Kontrol + kontak seti' && base.vat_included === false && base.revision_no === 1 && base.previous_id === null, base);
const legacy = (await mk({ vendor_name: 'Eski Firma', amount_kurus: 100 })).quote;
check('olustur: yeni alanlar opsiyonel (eski istemci govdesi)', legacy.delivery_days === null && legacy.note === null && legacy.vat_included === null, legacy);
let r = await failsWith(() => q(`UPDATE equipment_quotes SET delivery_days = -1 WHERE id = $1`, [legacy.id]), '23514');
check('CHECK: negatif teslim suresi reddedilir', r.ok, r);
r = await failsWith(() => q(`UPDATE equipment_quotes SET delivery_days = 1096 WHERE id = $1`, [legacy.id]), '23514');
check('CHECK: 1095 gunden uzun teslim suresi reddedilir', r.ok, r);
r = await failsWith(() => q(`UPDATE equipment_quotes SET note = '' WHERE id = $1`, [legacy.id]), '23514');
check('CHECK: bos not reddedilir (NULL kullanilir)', r.ok, r);
r = await failsWith(() => q(`UPDATE equipment_quotes SET revision_no = 2 WHERE id = $1`, [legacy.id]), '23514');
check('CHECK: revizyon cifti (revision_no > 1 icin previous_id + gerekce zorunlu)', r.ok, r);
r = await failsWith(() => q(`UPDATE equipment_quotes SET previous_id = id, revision_no = 2, revision_reason = 'xxx' WHERE id = $1`, [legacy.id]), '23514');
check('CHECK: kendine bagli surum reddedilir', r.ok, r);
r = await failsWith(() => svc.createQuote({ siteCode: siteA, actor, access, body: { topic: 'T', vendor_name: 'V', amount_kurus: 100, delivery_days: 1.5 } }), 'INVALID_FIELD');
check('dogrulama: teslim suresi tam sayi olmali', r.ok, r);
r = await failsWith(() => svc.createQuote({ siteCode: siteA, actor, access, body: { topic: 'T', vendor_name: 'V', amount_kurus: 100, vat_included: 'evet' } }), 'INVALID_FIELD');
check('dogrulama: KDV esasi boolean / null olmali', r.ok, r);
r = await failsWith(() => svc.createQuote({ siteCode: siteA, actor, access, body: { topic: 'T', vendor_name: 'V', amount_kurus: 100, note: 'x'.repeat(501) } }), 'INVALID_FIELD');
check('dogrulama: not en cok 500 karakter', r.ok, r);

// --- 2. Yerinde duzenleme (yalniz ACIK teklif) -----------------------------------------------------------------------------------------------------------------
const edited = (await svc.updateQuote({ siteCode: siteA, rawId: String(legacy.id), actor, body: { amount_kurus: 90000, delivery_days: 7, vat_included: true } })).quote;
check('duzenle: acik teklif yerinde guncellenir', edited.amount_kurus === 90000 && edited.delivery_days === 7 && edited.vat_included === true && edited.id === legacy.id, edited);
const noChange = await svc.updateQuote({ siteCode: siteA, rawId: String(legacy.id), actor, body: { amount_kurus: 90000 } });
check('duzenle: degisiklik yoksa yazilmaz', noChange.quote.amount_kurus === 90000);
const audit1 = await q(`SELECT details FROM audit_log WHERE action = 'quote.updated' AND target_id = $1 ORDER BY id DESC LIMIT 1`, [String(legacy.id)]);
check('denetim: eski ve yeni tutar yazilir', audit1.rows[0]?.details?.amount_before === 100 && audit1.rows[0]?.details?.amount_after === 90000, audit1.rows[0]?.details);

// --- 3. Kabul (sozlesmeye) + degismezlik tetikleyicisi ----------------------------------------------------------------------------------------------------------
const acceptBody = { as: 'contract', contract: { vendor_id: vendorId, start_date: '2026-11-01' } };
const accepted = (await svc.acceptQuote({ siteCode: siteA, rawId: String(base.id), actor, access, body: acceptBody })).quote;
check('kabul: teklif onaylandi ve sozlesme olustu', accepted.status === 'accepted' && accepted.contract_id !== null && accepted.accepted_as === 'contract', accepted);
const otherOpen = await row(legacy.id);
check('kabul: ayni konudaki diger acik teklif reddedildi', otherOpen.status === 'rejected', otherOpen.status);
r = await failsWith(() => svc.updateQuote({ siteCode: siteA, rawId: String(base.id), actor, body: { amount_kurus: 1 } }), 'QUOTE_LOCKED');
check('duzenle: onayli teklif 409 QUOTE_LOCKED', r.ok, r);
r = await failsWith(() => q(`UPDATE equipment_quotes SET amount_kurus = 1 WHERE id = $1`, [base.id]), 'P0001');
check('TETIKLEYICI: onayli satirin tutari SQL ile degistirilemez', r.ok, r);
r = await failsWith(() => q(`UPDATE equipment_quotes SET status = 'rejected' WHERE id = $1`, [base.id]), 'P0001');
check('TETIKLEYICI: onayli satir reddedilemez / durumu degistirilemez', r.ok, r);
r = await failsWith(() => q(`UPDATE equipment_quotes SET contract_id = NULL WHERE id = $1`, [base.id]), 'P0001');
check('TETIKLEYICI: kabulden sonra yazilan sozlesme baglantisi geri alinamaz', r.ok, r);
r = await failsWith(() => q(`DELETE FROM equipment_quotes WHERE id = $1`, [base.id]), 'P0001');
check('TETIKLEYICI: onayli satir silinemez', r.ok, r);
const snapshot = JSON.stringify(await row(base.id));

// Izinli gecisler (kabul akisinin kendi ifadeleri) ayri bir teklifle sinanir.
const probe = (await mk({ topic: 'Probe', vendor_name: 'P' })).quote;
await q(`UPDATE equipment_quotes SET status = 'accepted', accepted_as = 'expense', decided_at = NOW() WHERE id = $1 AND status = 'open'`, [probe.id]);
await q(`UPDATE equipment_quotes SET status = 'open', accepted_as = NULL, decided_at = NULL WHERE id = $1 AND expense_id IS NULL AND contract_id IS NULL`, [probe.id]);
check('izinli: gider / sozlesme olusmadiysa kabul geri alinir', (await row(probe.id)).status === 'open');
await q(`UPDATE equipment_quotes SET status = 'accepted', accepted_as = 'contract', decided_at = NOW() WHERE id = $1`, [probe.id]);
await q(`UPDATE equipment_quotes SET expense_id = NULL, contract_id = $2 WHERE id = $1`, [probe.id, accepted.contract_id]);
check('izinli: kabulden sonra baglanti bir kez yazilir', Number((await row(probe.id)).contract_id) === accepted.contract_id);
r = await failsWith(() => q(`UPDATE equipment_quotes SET status = 'open', accepted_as = NULL, decided_at = NULL WHERE id = $1`, [probe.id]), 'P0001');
check('TETIKLEYICI: baglanti varken kabul geri alinamaz', r.ok, r);
await q(`UPDATE equipment_quotes SET created_by = NULL WHERE id = $1`, [probe.id]);
check('izinli: created_by SET NULL (kullanici silme) onayli satirda sorun cikarmaz', (await row(probe.id)).created_by === null);
check('onayli satir tum bu denemelerde DEGISMEDI', JSON.stringify(await row(base.id)) === snapshot);

// --- 4. Revizyon (K14) ----------------------------------------------------------------------------------------------------------------------------------------
r = await failsWith(() => svc.reviseQuote({ siteCode: siteA, rawId: String(base.id), actor, access, body: { amount_kurus: 380000 } }), 'INVALID_FIELD');
check('revize: gerekce zorunlu', r.ok, r);
r = await failsWith(() => svc.reviseQuote({ siteCode: siteA, rawId: String(base.id), actor, access, body: { reason: 'ek parca' } }), 'NO_CHANGE');
check('revize: hicbir alan degismediyse 400 NO_CHANGE', r.ok, r);
r = await failsWith(() => svc.reviseQuote({ siteCode: siteA, rawId: String(legacy.id), actor, access, body: { reason: 'olmaz', amount_kurus: 5 } }), 'QUOTE_NOT_REVISABLE');
check('revize: reddedilmis ilk surum revize edilemez', r.ok, r);
const openOne = (await mk({ topic: 'Acik konu', vendor_name: 'Acik' })).quote;
r = await failsWith(() => svc.reviseQuote({ siteCode: siteA, rawId: String(openOne.id), actor, access, body: { reason: 'olmaz', amount_kurus: 5 } }), 'QUOTE_NOT_REVISABLE');
check('revize: onaysiz (acik) teklif revize edilemez (yerinde duzenlenir)', r.ok, r);
r = await failsWith(() => svc.reviseQuote({ siteCode: siteB, rawId: String(base.id), actor, access, body: { reason: 'baska site', amount_kurus: 5 } }), 'NOT_FOUND');
check('IDOR: baska sitenin teklifi revize edilemez (404)', r.ok, r);

const rev = (await svc.reviseQuote({ siteCode: siteA, rawId: String(base.id), actor, access, body: { reason: 'Ek parca ihtiyaci', amount_kurus: 380000, delivery_days: 21 } })).quote;
check('revize: yeni surum olustu (v2, onceki surume bagli, gerekce saklandi, ACIK)', rev.id !== base.id && rev.revision_no === 2 && rev.previous_id === base.id && rev.revision_reason === 'Ek parca ihtiyaci' && rev.status === 'open', rev);
check('revize: konu / firma / gonderilmeyen alanlar kopyalandi', rev.topic === base.topic && rev.vendor_name === base.vendor_name && rev.note === base.note && rev.vat_included === false && rev.delivery_days === 21 && rev.amount_kurus === 380000, rev);
check('revize: ONCEKI (onayli) surum hic degismedi', JSON.stringify(await row(base.id)) === snapshot);
r = await failsWith(() => svc.reviseQuote({ siteCode: siteA, rawId: String(base.id), actor, access, body: { reason: 'ikinci', amount_kurus: 1 } }), 'QUOTE_NOT_LATEST');
check('revize: onceki surumden ikinci revizyon 409 QUOTE_NOT_LATEST', r.ok, r);
r = await failsWith(() => svc.reviseQuote({ siteCode: siteA, rawId: String(rev.id), actor, access, body: { reason: 'bekleyen', amount_kurus: 1 } }), 'QUOTE_NOT_REVISABLE');
check('revize: bekleyen (acik) revizyon yeniden revize edilemez', r.ok, r);
const auditRev = await q(`SELECT details FROM audit_log WHERE action = 'quote.revised' AND target_id = $1`, [String(rev.id)]);
check('denetim: revizyon kaydi (from_id, revision_no, eski / yeni tutar), gerekce metni YOK', auditRev.rows[0]?.details?.from_id === base.id && auditRev.rows[0]?.details?.amount_before === 320000 && auditRev.rows[0]?.details?.amount_after === 380000 && !JSON.stringify(auditRev.rows[0]?.details).includes('Ek parca'), auditRev.rows[0]?.details);

const listing = (await svc.listQuotes(siteA, { topic: 'Asansor bakimi' })).items;
const head = listing.find((x) => x.id === rev.id);
check('liste: yalniz EN SON surum gorunur (v1 gizli), onayli surum bilgisi eklenir', listing.length === 2 && !listing.some((x) => x.id === base.id) && head?.approved_version?.id === base.id && head?.version_count === 2 && head?.revisable === false && head?.editable === true, listing.map((x) => x.id));
check('liste: bekleyen revizyon "en dusuk" yarisina girmez', head.lowest === false);
const hist = await svc.quoteHistory(siteA, String(base.id));
check('gecmis: tum surumler eskiden yeniye, zincirdeki herhangi bir kimlikle', hist.items.map((x) => x.id).join() === [base.id, rev.id].join() && hist.latest_id === rev.id && hist.approved_id === base.id, hist);
const histFromHead = await svc.quoteHistory(siteA, String(rev.id));
check('gecmis: son surumun kimligiyle de ayni zincir', histFromHead.items.length === 2);
r = await failsWith(() => svc.quoteHistory(siteB, String(base.id)), 'NOT_FOUND');
check('IDOR: baska sitenin gecmisi okunamaz (404)', r.ok, r);

// Kabul: onceki surum gider / sozlesme olmus => bilincli onay gerekir.
r = await failsWith(() => svc.acceptQuote({ siteCode: siteA, rawId: String(rev.id), actor, access, body: acceptBody }), 'PREVIOUS_VERSION_RECORDED');
check('kabul: onceki surum kayda donusmusse onaysiz kabul 409 PREVIOUS_VERSION_RECORDED', r.ok, r);
check('kabul reddi: revizyon hala ACIK ve degismedi', (await row(rev.id)).status === 'open');
const accRev = (await svc.acceptQuote({ siteCode: siteA, rawId: String(rev.id), actor, access, body: { ...acceptBody, acknowledge_previous: true } })).quote;
check('kabul: onayla birlikte revizyon kabul edildi (ayri sozlesme kaydi)', accRev.status === 'accepted' && accRev.contract_id !== null && accRev.contract_id !== accepted.contract_id, accRev);
check('kabul: onceki surum ve kaydi hala olduğu gibi', JSON.stringify(await row(base.id)) === snapshot);
const contractTitles = await q(`SELECT title FROM site_contracts WHERE id = ANY($1::BIGINT[]) ORDER BY id`, [[accepted.contract_id, accRev.contract_id]]);
check('kabul: revizyonun sozlesme basliginda revizyon notu var', /revizyon 2/.test(contractTitles.rows[1]?.title ?? ''), contractTitles.rows);
const listing2 = (await svc.listQuotes(siteA, { topic: 'Asansor bakimi' })).items;
check('liste: kabul edilen son surum revisable, zincir tek satir', listing2.filter((x) => x.vendor_name === 'Yildiz').length === 1 && listing2.find((x) => x.id === rev.id)?.revisable === true, listing2.map((x) => [x.id, x.status, x.revisable]));

// Reddedilmis revizyon yeniden revize edilebilir (onayli surumden turemis).
const rev3 = (await svc.reviseQuote({ siteCode: siteA, rawId: String(rev.id), actor, access, body: { reason: 'Ucuncu surum', amount_kurus: 390000 } })).quote;
check('revize: onayli v2 -> acik v3', rev3.revision_no === 3 && rev3.previous_id === rev.id && rev3.status === 'open', rev3);
await svc.rejectQuote({ siteCode: siteA, rawId: String(rev3.id), actor });
const listing3 = (await svc.listQuotes(siteA, { topic: 'Asansor bakimi' })).items;
const head3 = listing3.find((x) => x.id === rev3.id);
check('liste: reddedilen revizyonun basinda onayli surum (v2) gorunur, yeniden revize edilebilir', head3?.status === 'rejected' && head3?.approved_version?.id === rev.id && head3?.revisable === true, head3);
const rev4 = (await svc.reviseQuote({ siteCode: siteA, rawId: String(rev3.id), actor, access, body: { reason: 'Dorduncu surum', amount_kurus: 385000 } })).quote;
check('revize: reddedilmis revizyondan yeni surum (v4 -> v3)', rev4.revision_no === 4 && rev4.previous_id === rev3.id, rev4);
const hist4 = await svc.quoteHistory(siteA, String(base.id));
check('gecmis: 4 surum, siralama revision_no', hist4.items.map((x) => x.revision_no).join() === '1,2,3,4' && hist4.latest_id === rev4.id && hist4.approved_id === rev.id, hist4);
r = await failsWith(() => svc.updateQuote({ siteCode: siteA, rawId: String(rev4.id), actor, body: { vendor_name: 'Baska Firma' } }), 'INVALID_FIELD');
check('duzenle: bekleyen revizyonda firma degistirilemez', r.ok, r);
const editedRev = (await svc.updateQuote({ siteCode: siteA, rawId: String(rev4.id), actor, body: { valid_until: future, note: 'Garanti 1 yil' } })).quote;
check('duzenle: bekleyen revizyonun karsilastirma alanlari yerinde duzenlenir', editedRev.valid_until === future && editedRev.note === 'Garanti 1 yil' && editedRev.revision_no === 4, editedRev);

// Es zamanli cift revizyon: tam olarak biri basarili.
const concurrentBase = (await mk({ topic: 'Es zamanli', vendor_name: 'E' })).quote;
await svc.acceptQuote({ siteCode: siteA, rawId: String(concurrentBase.id), actor, access, body: acceptBody });
const results = await Promise.allSettled([
  svc.reviseQuote({ siteCode: siteA, rawId: String(concurrentBase.id), actor, access, body: { reason: 'Yaris bir', amount_kurus: 111 } }),
  svc.reviseQuote({ siteCode: siteA, rawId: String(concurrentBase.id), actor, access, body: { reason: 'Yaris iki', amount_kurus: 222 } }),
]);
const okCount = results.filter((x) => x.status === 'fulfilled').length;
const lateCodes = results.filter((x) => x.status === 'rejected').map((x) => x.reason?.code);
check('es zamanli: tek revizyon basarili, digeri QUOTE_NOT_LATEST', okCount === 1 && lateCodes.every((code) => code === 'QUOTE_NOT_LATEST'), { okCount, lateCodes });
const successors = await q(`SELECT COUNT(*)::INT AS n FROM equipment_quotes WHERE previous_id = $1`, [concurrentBase.id]);
check('es zamanli: bir surumun yalniz tek halefi', successors.rows[0].n === 1);
r = await failsWith(() => q(`INSERT INTO equipment_quotes (site_code, topic, vendor_name, amount_kurus, revision_no, previous_id, revision_reason) VALUES ($1, 'x', 'y', 1, 3, $2, 'zzz')`, [siteA, concurrentBase.id]), '23505');
check('benzersizlik: ayni surume ikinci halef eklenemez (SQL)', r.ok, r);
r = await failsWith(() => q(`INSERT INTO equipment_quotes (site_code, topic, vendor_name, amount_kurus, revision_no, previous_id, revision_reason) VALUES ($1, 'x', 'y', 1, 2, $2, 'zzz')`, [siteB, probe.id]), '23503');
check('bilesik FK: baska sitenin surumune baglanamaz (SQL)', r.ok, r);

// --- 5. Karsilastirma isaretleri (gercek satirlarla) ----------------------------------------------------------------------------------------------------------
const topic = 'Kamera sistemi';
await svc.createQuote({ siteCode: siteA, actor, access, body: { topic, vendor_name: 'A', amount_kurus: 500000, valid_until: future, delivery_days: 30, vat_included: false } });
await svc.createQuote({ siteCode: siteA, actor, access, body: { topic, vendor_name: 'B', amount_kurus: 450000, valid_until: future, delivery_days: 10, vat_included: false } });
await svc.createQuote({ siteCode: siteA, actor, access, body: { topic, vendor_name: 'C', amount_kurus: 400000, valid_until: '2000-01-01' } });
let kam = (await svc.listQuotes(siteA, { topic })).items;
const byVendor = (list, name) => list.find((x) => x.vendor_name === name);
check('isaret: en dusuk yalniz gecerli tekliflerden (suresi dolan C yarisa girmez), B en dusuk ve en hizli', byVendor(kam, 'B').lowest === true && byVendor(kam, 'B').fastest === true && byVendor(kam, 'A').lowest === false && byVendor(kam, 'C').lowest === false && byVendor(kam, 'C').expired === true, kam.map((x) => [x.vendor_name, x.lowest, x.fastest]));
await svc.createQuote({ siteCode: siteA, actor, access, body: { topic, vendor_name: 'D', amount_kurus: 300000, valid_until: future, vat_included: true } });
kam = (await svc.listQuotes(siteA, { topic })).items;
check('isaret: KDV esasi karisik => hicbir teklif "en dusuk" isaretlenmez, basis_mixed = true', kam.filter((x) => x.status === 'open' && !x.expired).every((x) => x.lowest === false && x.basis_mixed === true), kam.map((x) => [x.vendor_name, x.lowest, x.basis_mixed]));
const onlyRejected = (await svc.listQuotes(siteA, { status: 'rejected' })).items;
check('liste: durum suzgeci son surume uygulanir', onlyRejected.every((x) => x.status === 'rejected') && onlyRejected.length >= 1);

// --- 6. Site silme: onayli satirlar CASCADE ile silinir -----------------------------------------------------------------------------------------------------
const before = await q(`SELECT COUNT(*)::INT AS n FROM equipment_quotes WHERE site_code = $1 AND status = 'accepted'`, [siteA]);
await q(`DELETE FROM sites WHERE site_code = ANY($1::BIGINT[])`, [[siteA, siteB]]);
const after = await q(`SELECT COUNT(*)::INT AS n FROM equipment_quotes WHERE site_code = ANY($1::BIGINT[])`, [[siteA, siteB]]);
check('CASCADE: site silinince onayli ve revizyonlu teklifler de silinir (tetikleyici engellemez)', before.rows[0].n >= 3 && after.rows[0].n === 0, { before: before.rows[0].n, after: after.rows[0].n });
await q(`DELETE FROM users WHERE user_code = $1`, [userCode]).catch(() => {});

console.log(`\n${total - failures}/${total} PASS`);
await pool.end();
process.exit(failures === 0 ? 0 : 1);
