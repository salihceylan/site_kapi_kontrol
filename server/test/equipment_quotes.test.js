// Teklifler (P2-9 K14 revizyon modeli + P2-10 karsilastirma alanlari), DB'siz sahte veritabani:
//  - girdi dogrulama (teslim suresi, KDV esasi, kapsam / not, tutar),
//  - surum zincirleri ve karsilastirma isaretleri (saf fonksiyonlar),
//  - SURUM OLUSTURMA ve ONCEKI SURUME BAG (reviseQuote): onayli satir degismez, yeni satir previous_id / revision_no / gerekce tasir, hatalar,
//  - yerinde duzenleme yalniz ACIK tekliflerde (onayli teklif QUOTE_LOCKED), gecmis, liste (yalniz en son surumler), kabulde onceki kayit onayi,
//  - rota kaydi (kaynak taramasi).
// Gercek SQL / tetikleyici / es zamanlilik: scripts/qa_equipment_quotes_pg.mjs (gercek PostgreSQL).
import { describe, it, beforeEach, after } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { pool } from '../src/db.js';
import * as svc from '../src/modules/equipment_service.js';

const here = path.dirname(fileURLToPath(import.meta.url));
const SITE = 1000000001;
const OTHER_SITE = 1000000002;
const actor = { user_code: 20001, userCode: 20001, id: 20001, role: 'site_manager', full_name: 'Yönetici' };
const access = { canWrite: true, userCode: 20001 };

let store;
const row = (over = {}) => {
  store.nextId += 1;
  const r = {
    id: store.nextId,
    site_code: SITE,
    topic: 'Asansör bakımı',
    vendor_name: 'Yıldız',
    amount_kurus: 320000,
    valid_until: null,
    document_note: null,
    equipment_id: null,
    status: 'open',
    accepted_as: null,
    expense_id: null,
    contract_id: null,
    decided_at: null,
    created_at: new Date('2026-10-01T08:00:00Z'),
    delivery_days: null,
    note: null,
    vat_included: null,
    revision_no: 1,
    previous_id: null,
    revision_reason: null,
    ...over,
  };
  store.quotes.push(r);
  return r;
};
const accepted = (over = {}) => row({ status: 'accepted', accepted_as: 'contract', contract_id: 501, decided_at: new Date('2026-10-02T08:00:00Z'), ...over });

function makeStore() {
  return { quotes: [], audits: [], log: [], nextId: 100, moduleEnabled: false, uniqueViolation: false };
}

const find = (id, site) => store.quotes.find((x) => x.id === Number(id) && x.site_code === Number(site));
const chainUp = (start, site) => {
  const out = [];
  let cur = find(start, site);
  for (let i = 0; cur && i < 100; i += 1) {
    out.push(cur);
    cur = cur.previous_id === null ? undefined : find(cur.previous_id, site);
  }
  return out;
};
const chainDown = (start, site) => {
  const out = [];
  let cur = find(start, site);
  for (let i = 0; cur && i < 100; i += 1) {
    out.push(cur);
    cur = store.quotes.find((x) => x.previous_id === cur.id && x.site_code === Number(site));
  }
  return out;
};

async function fakeQuery(text, params = []) {
  const sql = String(text).replace(/\s+/g, ' ').trim();
  store.log.push(sql);
  const ok = (rows = []) => ({ rows, rowCount: rows.length });
  if (/^(BEGIN|COMMIT|ROLLBACK)$/.test(sql) || /pg_advisory_xact_lock/.test(sql)) return ok();
  if (/^INSERT INTO audit_log/.test(sql)) {
    store.audits.push({ action: params[3], target_id: params[6], details: JSON.parse(params[7]) });
    return ok();
  }
  if (/^SELECT enabled FROM site_modules/.test(sql)) return ok([{ enabled: store.moduleEnabled }]);
  if (/FROM equipment_quotes q WHERE q\.id = \$1 AND q\.site_code = \$2/.test(sql)) {
    const found = find(params[0], params[1]);
    return ok(found ? [{ ...found }] : []);
  }
  if (/^SELECT id FROM equipment_quotes WHERE previous_id = \$1 AND site_code = \$2/.test(sql)) {
    const next = store.quotes.find((x) => x.previous_id === Number(params[0]) && x.site_code === Number(params[1]));
    return ok(next ? [{ id: next.id }] : []);
  }
  if (/^SELECT COUNT\(\*\)::INTEGER AS n FROM equipment_quotes/.test(sql)) return ok([{ n: store.countOverride ?? store.quotes.filter((x) => x.site_code === Number(params[0])).length }]);
  if (/^INSERT INTO equipment_quotes/.test(sql)) {
    if (store.uniqueViolation) throw Object.assign(new Error('duplicate key'), { code: '23505' });
    if (/revision_no, previous_id, revision_reason/.test(sql)) {
      const [site, topic, vendor, amount, validUntil, docNote, equipmentId, delivery, note, vat, revisionNo, previousId, reason, createdBy] = params;
      return ok([{ id: row({ site_code: site, topic, vendor_name: vendor, amount_kurus: amount, valid_until: validUntil, document_note: docNote, equipment_id: equipmentId, delivery_days: delivery, note, vat_included: vat, revision_no: revisionNo, previous_id: previousId, revision_reason: reason, created_by: createdBy }).id }]);
    }
    const [site, topic, vendor, amount, validUntil, docNote, equipmentId, createdBy, delivery, note, vat] = params;
    return ok([{ id: row({ site_code: site, topic, vendor_name: vendor, amount_kurus: amount, valid_until: validUntil, document_note: docNote, equipment_id: equipmentId, created_by: createdBy, delivery_days: delivery, note, vat_included: vat }).id }]);
  }
  if (/^UPDATE equipment_quotes SET .* WHERE id = \$1 AND site_code = \$2 AND status = 'open' RETURNING id/.test(sql)) {
    const target = find(params[0], params[1]);
    if (!target || target.status !== 'open') return ok();
    const sets = /SET (.+) WHERE id = \$1/.exec(sql)[1].split(', ');
    for (const set of sets) {
      const m = /^(\w+) = \$(\d+)/.exec(set);
      target[m[1]] = params[Number(m[2]) - 1];
    }
    return ok([{ id: target.id }]);
  }
  if (/^SELECT .* FROM equipment_quotes q WHERE q\.site_code = \$1 AND \(\$2::TEXT IS NULL/.test(sql)) {
    const topic = params[1];
    return ok(store.quotes.filter((x) => x.site_code === Number(params[0]) && (topic === null || x.topic.toLowerCase() === topic.toLowerCase())).map((x) => ({ ...x })));
  }
  if (/^WITH RECURSIVE up AS/.test(sql)) {
    const ids = new Set([...chainUp(params[0], params[1]), ...chainDown(params[0], params[1])].map((x) => x.id));
    return ok(store.quotes.filter((x) => ids.has(x.id)).sort((a, b) => a.revision_no - b.revision_no || a.id - b.id).map((x) => ({ ...x })));
  }
  if (/^WITH RECURSIVE anc AS/.test(sql)) {
    const hit = chainUp(params[0], params[1])
      .filter((x) => x.id !== Number(params[0]) && x.status === 'accepted' && (x.expense_id !== null || x.contract_id !== null))
      .sort((a, b) => b.revision_no - a.revision_no)[0];
    return ok(hit ? [{ id: hit.id, revision_no: hit.revision_no, expense_id: hit.expense_id, contract_id: hit.contract_id }] : []);
  }
  throw new Error(`Beklenmeyen SQL: ${sql.slice(0, 160)}`);
}

const installPool = () => {
  pool.query = async (text, params) => fakeQuery(text, params);
  pool.connect = async () => ({ query: async (text, params) => fakeQuery(text, params), release() {} });
};

beforeEach(() => {
  store = makeStore();
  installPool();
});
after(() => {
  delete pool.query;
  delete pool.connect;
});

const failsWith = async (fn, code, extra) => {
  await assert.rejects(fn, (error) => {
    assert.equal(error.code, code);
    if (extra) for (const [k, v] of Object.entries(extra)) assert.deepEqual(error.extra?.[k], v);
    return true;
  });
};
const statementsOf = (re) => store.log.filter((s) => re.test(s));

describe('teklif girdi dogrulama (098 alanlari)', () => {
  it('teslim suresi: 0..1095 tam sayi; bos = belirtilmedi', () => {
    assert.equal(svc.deliveryDays(undefined), null);
    assert.equal(svc.deliveryDays(null), null);
    assert.equal(svc.deliveryDays(''), null);
    assert.equal(svc.deliveryDays(0), 0);
    assert.equal(svc.deliveryDays(1095), 1095);
    for (const bad of [-1, 1096, 1.5, '7', Number.NaN, true]) {
      assert.throws(() => svc.deliveryDays(bad), { code: 'INVALID_FIELD' }, String(bad));
    }
    assert.throws(() => svc.deliveryDays(2000), (e) => e.extra?.field === 'delivery_days');
  });
  it('KDV esasi: true dahil, false haric, null belirtilmedi, undefined gonderilmedi', () => {
    assert.equal(svc.vatFlag(undefined), undefined);
    assert.equal(svc.vatFlag(null), null);
    assert.equal(svc.vatFlag(true), true);
    assert.equal(svc.vatFlag(false), false);
    for (const bad of ['true', 1, 0, 'dahil']) assert.throws(() => svc.vatFlag(bad), { code: 'INVALID_FIELD' }, String(bad));
  });
  it('olusturma alanlari: tutar zorunlu, digerleri opsiyonel; kapsam / not en cok 500', () => {
    const f = svc.parseQuoteFields({ amount_kurus: 125000, delivery_days: 14, note: '  Kontrol   ve  kontak seti ', vat_included: false, valid_until: '2026-12-31' });
    assert.deepEqual(f, { amount_kurus: 125000, valid_until: '2026-12-31', delivery_days: 14, note: 'Kontrol ve kontak seti', vat_included: false });
    assert.throws(() => svc.parseQuoteFields({}), { code: 'INVALID_FIELD' });
    assert.throws(() => svc.parseQuoteFields({ amount_kurus: 0 }), { code: 'INVALID_FIELD' });
    assert.throws(() => svc.parseQuoteFields({ amount_kurus: 100, note: 'x'.repeat(501) }), (e) => e.code === 'INVALID_FIELD' && e.extra?.field === 'note');
    assert.equal(svc.parseQuoteFields({ amount_kurus: 100, note: '   ' }).note, null);
    assert.throws(() => svc.parseQuoteFields({ amount_kurus: 100, valid_until: '2026-02-30' }), { code: 'INVALID_FIELD' });
  });
  it('kismi (duzenleme / revizyon): yalniz gonderilenler doner; null temizler; tutar temizlenemez', () => {
    assert.deepEqual(svc.parseQuoteFields({}, { partial: true }), {});
    assert.deepEqual(svc.parseQuoteFields({ delivery_days: null, vat_included: null, note: '' }, { partial: true }), { delivery_days: null, vat_included: null, note: null });
    assert.throws(() => svc.parseQuoteFields({ amount_kurus: null }, { partial: true }), { code: 'INVALID_FIELD' });
  });
  it('createQuote: yeni alanlar INSERT parametrelerine gider; eski istemci govdesi (yeni alan yok) NULL yazar', async () => {
    const full = await svc.createQuote({ siteCode: SITE, actor, access, body: { topic: 'Kamera', vendor_name: 'A', amount_kurus: 500000, delivery_days: 30, note: 'Garanti 2 yıl', vat_included: true } });
    assert.equal(full.quote.delivery_days, 30);
    assert.equal(full.quote.note, 'Garanti 2 yıl');
    assert.equal(full.quote.vat_included, true);
    assert.equal(full.quote.revision_no, 1);
    assert.equal(full.quote.previous_id, null);
    const legacy = await svc.createQuote({ siteCode: SITE, actor, access, body: { topic: 'Kamera', vendor_name: 'B', amount_kurus: 450000 } });
    assert.equal(legacy.quote.delivery_days, null);
    assert.equal(legacy.quote.note, null);
    assert.equal(legacy.quote.vat_included, null);
    await failsWith(() => svc.createQuote({ siteCode: SITE, actor, access, body: { topic: 'K', vendor_name: 'V', amount_kurus: 1, delivery_days: 9999 } }), 'INVALID_FIELD');
    assert.equal(statementsOf(/^INSERT INTO equipment_quotes/).length, 2, 'hatali govde veritabanina gitmez');
  });
});

describe('surum zincirleri ve karsilastirma isaretleri (saf)', () => {
  const mapped = (rows) => rows.map((r) => svc.mapQuote({ ...r, valid_until: r.valid_until }, '2026-10-28'));

  it('liste yalniz EN SON surumleri gosterir; basin onayli onceki surumu eklenir', () => {
    store = makeStore();
    const v1 = accepted({ amount_kurus: 320000 });
    const v2 = row({ revision_no: 2, previous_id: v1.id, revision_reason: 'Ek parça', amount_kurus: 380000 });
    const lone = row({ topic: 'Kamera', vendor_name: 'B' });
    const heads = svc.buildQuoteHeads(mapped(store.quotes));
    assert.deepEqual(heads.map((h) => h.id), [v2.id, lone.id]);
    const head = heads[0];
    assert.equal(head.version_count, 2);
    assert.equal(head.has_history, true);
    assert.equal(head.approved_version.id, v1.id);
    assert.equal(head.approved_version.amount_kurus, 320000);
    assert.equal(head.approved_version.contract_id, 501);
    assert.equal(head.editable, true);
    assert.equal(head.revisable, false);
    assert.equal(heads[1].approved_version, null);
    assert.equal(heads[1].has_history, false);
  });
  it('revisable: onayli son surum evet; acik hayir; ilk surum reddedilmis hayir; onayli bir surumden turemis reddedilmis revizyon evet', () => {
    store = makeStore();
    const a = accepted({ topic: 'A' });
    const open = row({ topic: 'B' });
    const rej = row({ topic: 'C', status: 'rejected' });
    const c1 = accepted({ topic: 'D' });
    const c2 = row({ topic: 'D', revision_no: 2, previous_id: c1.id, revision_reason: 'zam', status: 'rejected' });
    const by = Object.fromEntries(svc.buildQuoteHeads(mapped(store.quotes)).map((h) => [h.topic + h.revision_no, h]));
    assert.equal(by.A1.revisable, true);
    assert.equal(by.A1.editable, false);
    assert.equal(by.B1.revisable, false);
    assert.equal(by.B1.editable, true);
    assert.equal(by.C1.revisable, false);
    assert.equal(by.C1.editable, false);
    assert.equal(by.D2.revisable, true, 'onayli v1 -> reddedilmis v2: yeniden revize edilebilir');
    assert.equal(by.D2.approved_version.id, c1.id);
    assert.equal(a.id < open.id && rej.id < c1.id && c2.previous_id === c1.id, true);
  });
  it('uc basamakli zincir: onaysiz son surumun onayli atasi bulunur', () => {
    store = makeStore();
    const v1 = accepted();
    const v2 = row({ revision_no: 2, previous_id: v1.id, revision_reason: 'bir', status: 'rejected' });
    const v3 = row({ revision_no: 3, previous_id: v2.id, revision_reason: 'iki' });
    const heads = svc.buildQuoteHeads(mapped(store.quotes));
    assert.equal(heads.length, 1);
    assert.equal(heads[0].id, v3.id);
    assert.equal(heads[0].approved_version.id, v1.id);
    assert.equal(heads[0].version_count, 3);
  });

  const open = (over) => svc.mapQuote({ id: over.id, topic: 'Kamera', vendor_name: `F${over.id}`, amount_kurus: 100, status: 'open', valid_until: null, revision_no: 1, previous_id: null, ...over }, '2026-10-28');
  const flags = (list) => Object.fromEntries(svc.markComparison(list).map((q) => [q.id, [q.lowest, q.fastest, q.basis_mixed]]));

  it('en dusuk + en hizli: ayni KDV esasindaki acik ve gecerli tekliflerden', () => {
    const f = flags([open({ id: 1, amount_kurus: 500, delivery_days: 30, vat_included: false }), open({ id: 2, amount_kurus: 450, delivery_days: 10, vat_included: false }), open({ id: 3, amount_kurus: 400, valid_until: '2020-01-01', vat_included: false })]);
    assert.deepEqual(f[1], [false, false, false]);
    assert.deepEqual(f[2], [true, true, false]);
    assert.deepEqual(f[3], [false, false, false], 'suresi dolan teklif yarisa girmez');
  });
  it('KDV esasi karisik (dahil / haric / belirtilmedi) => hicbiri en dusuk degil, basis_mixed = true', () => {
    const f = flags([open({ id: 1, amount_kurus: 500, vat_included: false }), open({ id: 2, amount_kurus: 300, vat_included: true }), open({ id: 3, amount_kurus: 450, vat_included: null })]);
    for (const id of [1, 2, 3]) assert.deepEqual([f[id][0], f[id][2]], [false, true], String(id));
  });
  it('eski satirlar (hepsi belirtilmedi) eski davranisi korur; tek acik teklif de "en dusuk"', () => {
    const f = flags([open({ id: 1, amount_kurus: 500 }), open({ id: 2, amount_kurus: 450 })]);
    assert.equal(f[2][0], true);
    assert.equal(f[1][0], false);
    assert.equal(flags([open({ id: 9, amount_kurus: 10 })])[9][0], true);
  });
  it('en hizli yalniz en az iki tekliften teslim suresi girilmisse; bekleyen revizyon ve kapali teklifler yarisa girmez', () => {
    const one = flags([open({ id: 1, delivery_days: 5 }), open({ id: 2 })]);
    assert.equal(one[1][1], false);
    const f = flags([
      open({ id: 1, amount_kurus: 500, delivery_days: 20 }),
      open({ id: 2, amount_kurus: 600, delivery_days: 8 }),
      open({ id: 3, amount_kurus: 100, delivery_days: 1, revision_no: 2, previous_id: 77 }),
      open({ id: 4, amount_kurus: 50, status: 'accepted' }),
      open({ id: 5, amount_kurus: 40, status: 'rejected' }),
    ]);
    assert.deepEqual(f[2], [false, true, false]);
    assert.deepEqual(f[1], [true, false, false]);
    assert.deepEqual(f[3], [false, false, false], 'bekleyen revizyon rakip degildir');
    assert.deepEqual(f[4], [false, false, false]);
    assert.deepEqual(f[5], [false, false, false]);
  });
  it('konular birbirinden bagimsizdir', () => {
    const f = flags([open({ id: 1, topic: 'Kamera', amount_kurus: 5 }), open({ id: 2, topic: 'Asansör', amount_kurus: 9, vat_included: true })]);
    assert.equal(f[1][0], true);
    assert.equal(f[2][0], true);
  });
});

describe('surum olusturma ve onceki surume bag (K14)', () => {
  const revise = (id, body, site = SITE) => svc.reviseQuote({ siteCode: site, rawId: String(id), actor, access, body });

  it('onayli teklif: yeni surum satiri eklenir, onceki satira BAGLANIR, onceki satir degismez', async () => {
    const v1 = accepted({ valid_until: '2099-12-31', delivery_days: 14, note: 'Kontrol', vat_included: false });
    const snapshot = JSON.stringify(v1);
    const out = await revise(v1.id, { reason: 'Ek parça ihtiyacı', amount_kurus: 380000, delivery_days: 21 });
    const created = out.quote;
    assert.notEqual(created.id, v1.id);
    assert.equal(created.previous_id, v1.id);
    assert.equal(created.revision_no, 2);
    assert.equal(created.revision_reason, 'Ek parça ihtiyacı');
    assert.equal(created.status, 'open', 'yeni surum yeniden yonetici karari bekler');
    assert.equal(created.amount_kurus, 380000);
    assert.equal(created.delivery_days, 21);
    assert.equal(created.topic, v1.topic);
    assert.equal(created.vendor_name, v1.vendor_name);
    assert.equal(created.note, 'Kontrol', 'gonderilmeyen alan onceki surumden kopyalanir');
    assert.equal(created.vat_included, false);
    assert.equal(created.valid_until, '2099-12-31');
    assert.equal(JSON.stringify(v1), snapshot, 'onayli satir degismedi');
    assert.equal(v1.status, 'accepted');
    assert.equal(statementsOf(/^UPDATE equipment_quotes/).length, 0, 'onayli satira hicbir UPDATE gitmez');
    assert.deepEqual(statementsOf(/^(BEGIN|COMMIT|ROLLBACK)$/), ['BEGIN', 'COMMIT']);
  });
  it('degisen alanlar denetim kaydina eski / yeni tutarla yazilir; gerekce metni yazilmaz', async () => {
    const v1 = accepted();
    const out = await revise(v1.id, { reason: 'Gizli gerekçe metni', amount_kurus: 400000, note: 'Yeni kapsam' });
    const entry = store.audits.find((a) => a.action === 'quote.revised');
    assert.ok(entry);
    assert.equal(entry.target_id, String(out.quote.id));
    assert.deepEqual(entry.details.fields.sort(), ['amount_kurus', 'note']);
    assert.equal(entry.details.amount_before, 320000);
    assert.equal(entry.details.amount_after, 400000);
    assert.equal(entry.details.from_id, v1.id);
    assert.equal(entry.details.revision_no, 2);
    assert.ok(!JSON.stringify(entry.details).includes('gerekçe'));
    assert.ok(!JSON.stringify(entry.details).includes('Yeni kapsam'));
  });
  it('zincir: onayli v1 -> v2 (kabul) -> v3 baglari ve numaralari', async () => {
    const v1 = accepted();
    const v2 = (await revise(v1.id, { reason: 'ikinci', amount_kurus: 1 })).quote;
    const stored = find(v2.id, SITE);
    stored.status = 'accepted';
    stored.contract_id = 502;
    const v3 = (await revise(v2.id, { reason: 'üçüncü', amount_kurus: 2 })).quote;
    assert.deepEqual([v2.previous_id, v3.previous_id], [v1.id, v2.id]);
    assert.deepEqual([v2.revision_no, v3.revision_no], [2, 3]);
    const hist = await svc.quoteHistory(SITE, String(v1.id));
    assert.deepEqual(hist.items.map((x) => x.id), [v1.id, v2.id, v3.id]);
    assert.equal(hist.latest_id, v3.id);
    assert.equal(hist.approved_id, v2.id);
    assert.deepEqual((await svc.quoteHistory(SITE, String(v3.id))).items.map((x) => x.revision_no), [1, 2, 3]);
  });
  it('reddedilmis revizyon (onayli bir surumden turemis) yeniden revize edilebilir', async () => {
    const v1 = accepted();
    const v2 = row({ revision_no: 2, previous_id: v1.id, revision_reason: 'zam', status: 'rejected' });
    const v3 = (await revise(v2.id, { reason: 'indirimli', amount_kurus: 350000 })).quote;
    assert.equal(v3.previous_id, v2.id);
    assert.equal(v3.revision_no, 3);
  });
  it('gerekce zorunlu ve en az 3 karakter; hicbir alan degismediyse NO_CHANGE', async () => {
    const v1 = accepted();
    await failsWith(() => revise(v1.id, { amount_kurus: 1 }), 'INVALID_FIELD');
    await failsWith(() => revise(v1.id, { reason: 'ab', amount_kurus: 1 }), 'INVALID_FIELD');
    await failsWith(() => revise(v1.id, { reason: '   ', amount_kurus: 1 }), 'INVALID_FIELD');
    await failsWith(() => revise(v1.id, { reason: 'x'.repeat(301), amount_kurus: 1 }), 'INVALID_FIELD');
    await failsWith(() => revise(v1.id, { reason: 'ek parça' }), 'NO_CHANGE');
    await failsWith(() => revise(v1.id, { reason: 'ek parça', amount_kurus: 320000 }), 'NO_CHANGE');
    assert.equal(store.quotes.length, 1, 'hatali istekler satir eklemez');
  });
  it('revize edilemeyenler: acik teklif, ilk surum reddedilmis; onceki surum (halefi var) QUOTE_NOT_LATEST; bekleyen revizyon', async () => {
    const open = row();
    await failsWith(() => revise(open.id, { reason: 'olmaz', amount_kurus: 1 }), 'QUOTE_NOT_REVISABLE', { status: 'open' });
    const rejected = row({ status: 'rejected' });
    await failsWith(() => revise(rejected.id, { reason: 'olmaz', amount_kurus: 1 }), 'QUOTE_NOT_REVISABLE', { status: 'rejected' });
    const v1 = accepted();
    const v2 = (await revise(v1.id, { reason: 'ilk revizyon', amount_kurus: 1 })).quote;
    await failsWith(() => revise(v1.id, { reason: 'ikinci revizyon', amount_kurus: 2 }), 'QUOTE_NOT_LATEST', { latest_hint_id: v2.id });
    await failsWith(() => revise(v2.id, { reason: 'bekleyen', amount_kurus: 3 }), 'QUOTE_NOT_REVISABLE', { status: 'open' });
    assert.equal(store.quotes.filter((x) => x.previous_id !== null).length, 1, 'tek halef');
  });
  it('baska sitenin teklifi 404 NOT_FOUND (IDOR)', async () => {
    const v1 = accepted();
    await failsWith(() => revise(v1.id, { reason: 'başka site', amount_kurus: 1 }, OTHER_SITE), 'NOT_FOUND');
    await failsWith(() => svc.quoteHistory(OTHER_SITE, String(v1.id)), 'NOT_FOUND');
    await failsWith(() => svc.updateQuote({ siteCode: OTHER_SITE, rawId: String(row().id), actor, body: { amount_kurus: 1 } }), 'NOT_FOUND');
  });
  it('sinirlar: surum sayisi (50) ve site basina teklif sayisi', async () => {
    const top = accepted({ revision_no: 50, previous_id: 1, revision_reason: 'son' });
    await failsWith(() => revise(top.id, { reason: 'fazla', amount_kurus: 1 }), 'LIMIT_REACHED', { limit: 50 });
    const v1 = accepted();
    store.countOverride = 3000;
    await failsWith(() => revise(v1.id, { reason: 'dolu', amount_kurus: 1 }), 'LIMIT_REACHED', { limit: 3000 });
  });
  it('eszamanli yaris: benzersiz dizin ihlali (23505) QUOTE_NOT_LATEST olur ve ROLLBACK yapilir', async () => {
    const v1 = accepted();
    store.uniqueViolation = true;
    await failsWith(() => revise(v1.id, { reason: 'yaris', amount_kurus: 5 }), 'QUOTE_NOT_LATEST');
    assert.deepEqual(statementsOf(/^(BEGIN|COMMIT|ROLLBACK)$/), ['BEGIN', 'ROLLBACK']);
  });
  it('yerinde duzenleme yalniz ACIK tekliflerde; onayli ve reddedilmis QUOTE_LOCKED, satir degismez', async () => {
    const open = row({ amount_kurus: 100, delivery_days: null });
    const out = await svc.updateQuote({ siteCode: SITE, rawId: String(open.id), actor, body: { amount_kurus: 90, delivery_days: 7, vat_included: true, note: 'Pazarlık sonrası' } });
    assert.equal(out.quote.amount_kurus, 90);
    assert.equal(out.quote.delivery_days, 7);
    assert.equal(out.quote.vat_included, true);
    assert.equal(out.quote.note, 'Pazarlık sonrası');
    assert.equal(out.quote.id, open.id, 'yerinde: yeni satir yok');
    const entry = store.audits.find((a) => a.action === 'quote.updated');
    assert.equal(entry.details.amount_before, 100);
    assert.equal(entry.details.amount_after, 90);
    const v1 = accepted();
    const lockedSnapshot = JSON.stringify(v1);
    await failsWith(() => svc.updateQuote({ siteCode: SITE, rawId: String(v1.id), actor, body: { amount_kurus: 1 } }), 'QUOTE_LOCKED', { status: 'accepted' });
    const rejected = row({ status: 'rejected' });
    await failsWith(() => svc.updateQuote({ siteCode: SITE, rawId: String(rejected.id), actor, body: { amount_kurus: 1 } }), 'QUOTE_LOCKED', { status: 'rejected' });
    assert.equal(JSON.stringify(v1), lockedSnapshot);
  });
  it('duzenleme: degisiklik yoksa UPDATE / denetim yok; bekleyen revizyonda konu, firma, ekipman degismez', async () => {
    const open = row({ amount_kurus: 100 });
    await svc.updateQuote({ siteCode: SITE, rawId: String(open.id), actor, body: { amount_kurus: 100 } });
    assert.equal(statementsOf(/^UPDATE equipment_quotes/).length, 0);
    assert.equal(store.audits.length, 0);
    const v1 = accepted({ topic: 'Rev' });
    const rev = row({ topic: 'Rev', revision_no: 2, previous_id: v1.id, revision_reason: 'zam' });
    await failsWith(() => svc.updateQuote({ siteCode: SITE, rawId: String(rev.id), actor, body: { vendor_name: 'Başka' } }), 'INVALID_FIELD');
    await failsWith(() => svc.updateQuote({ siteCode: SITE, rawId: String(rev.id), actor, body: { topic: 'Başka konu' } }), 'INVALID_FIELD');
    const ok = await svc.updateQuote({ siteCode: SITE, rawId: String(rev.id), actor, body: { valid_until: '2099-01-01', vendor_name: rev.vendor_name } });
    assert.equal(ok.quote.valid_until, '2099-01-01');
    assert.equal(ok.quote.revision_no, 2);
  });
  it('liste: yalniz en son surumler; durum suzgeci son surume uygulanir; onceki surumler gizli', async () => {
    const v1 = accepted();
    const v2 = row({ revision_no: 2, previous_id: v1.id, revision_reason: 'zam', amount_kurus: 400000 });
    const other = row({ topic: 'Kamera', vendor_name: 'B', amount_kurus: 10 });
    const all = (await svc.listQuotes(SITE, {})).items;
    assert.deepEqual(all.map((x) => x.id).sort(), [v2.id, other.id].sort());
    const head = all.find((x) => x.id === v2.id);
    assert.equal(head.approved_version.id, v1.id);
    assert.equal(head.lowest, false, 'bekleyen revizyon en dusuk yarisinda degil');
    assert.equal(all.find((x) => x.id === other.id).lowest, true);
    assert.deepEqual((await svc.listQuotes(SITE, { status: 'accepted' })).items, []);
    assert.deepEqual((await svc.listQuotes(SITE, { status: 'open' })).items.map((x) => x.id).sort(), [v2.id, other.id].sort());
    assert.equal((await svc.listQuotes(SITE, { topic: 'kamera' })).items.length, 1);
  });
});

describe('kabulde onceki kayit onayi (cift sayim korumasi)', () => {
  const accept = (id, body) => svc.acceptQuote({ siteCode: SITE, rawId: String(id), actor, access, body });
  it('revizyon + onceki surum gider / sozlesmeye donusmus: onaysiz kabul 409 PREVIOUS_VERSION_RECORDED, satir degismez', async () => {
    const v1 = accepted({ contract_id: 501 });
    const v2 = row({ revision_no: 2, previous_id: v1.id, revision_reason: 'zam', amount_kurus: 400000 });
    await failsWith(() => accept(v2.id, { as: 'contract', contract: { vendor_id: 1, start_date: '2026-11-01' } }), 'PREVIOUS_VERSION_RECORDED', {
      previous_quote_id: v1.id,
      previous_revision_no: 1,
      previous_contract_id: 501,
      previous_expense_id: null,
    });
    assert.equal(v2.status, 'open');
    assert.equal(statementsOf(/^UPDATE equipment_quotes/).length, 0, 'claim bile denenmedi');
  });
  it('acknowledge_previous: true ise kapidan gecer (sonraki adim modul denetimi)', async () => {
    const v1 = accepted({ contract_id: null, expense_id: 77, accepted_as: 'expense' });
    const v2 = row({ revision_no: 2, previous_id: v1.id, revision_reason: 'zam' });
    store.moduleEnabled = false;
    // Finans temel (core) modul, hep acik; kapali olabilen modul Sozlesmeler: kapidan gecen istek sonraki adimda modul denetimine takilir.
    await failsWith(() => accept(v2.id, { as: 'contract', acknowledge_previous: true }), 'MODULE_DISABLED', { module: 'contracts' });
    await failsWith(() => accept(v2.id, { as: 'contract', acknowledge_previous: 'evet' }), 'PREVIOUS_VERSION_RECORDED', { previous_expense_id: 77 });
  });
  it('ilk surum teklifler ve kayda donusmemis onceki surum onay istemez', async () => {
    store.moduleEnabled = false;
    const plain = row();
    await failsWith(() => accept(plain.id, { as: 'contract' }), 'MODULE_DISABLED', { module: 'contracts' });
    const v1 = accepted({ contract_id: null, expense_id: null });
    const v2 = row({ revision_no: 2, previous_id: v1.id, revision_reason: 'zam' });
    await failsWith(() => accept(v2.id, { as: 'contract' }), 'MODULE_DISABLED', { module: 'contracts' });
  });
  it('suresi dolan teklif kabul edilemez, karara baglanmis teklif QUOTE_NOT_OPEN', async () => {
    const expired = row({ valid_until: '2020-01-01' });
    await failsWith(() => accept(expired.id, { as: 'contract' }), 'QUOTE_EXPIRED');
    const done = accepted();
    await failsWith(() => accept(done.id, { as: 'contract' }), 'QUOTE_NOT_OPEN');
  });
});

describe('teklif uclari (rota kaydi)', () => {
  const routes = readFileSync(path.join(here, '..', 'src', 'modules', 'equipment_routes.js'), 'utf8');
  it('gecmis (GET), duzenleme (PATCH) ve revizyon (POST, 201) kayitli; hepsi yazma / okuma hiz sinirlayicili yardimcilarla', () => {
    assert.match(routes, /read\('\/quotes\/:id\/history'/);
    assert.match(routes, /write\('patch', '\/quotes\/:id'/);
    assert.match(routes, /write\('post', '\/quotes\/:id\/revise'[\s\S]*?\),\s*201,\s*\);/);
    assert.match(routes, /svc\.reviseQuote\(/);
    assert.match(routes, /svc\.quoteHistory\(/);
    assert.match(routes, /svc\.updateQuote\(/);
  });
  it('sabit yollar parametreliden once; mevcut kabul / red uclari duruyor', () => {
    assert.ok(routes.indexOf("read('/quotes'") < routes.indexOf("read('/quotes/:id/history'"));
    assert.match(routes, /write\('post', '\/quotes\/:id\/reject'/);
    assert.match(routes, /write\('post', '\/quotes\/:id\/accept'/);
  });
});
