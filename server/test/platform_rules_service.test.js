// Kurallar tablosu servisi (DB'siz, sahte veritabanı): görünüm kurucu (platform / site / etkin / planlı; adlar yalnız süperde), yazma gövdesi ayrıştırma,
// yazma akışı (işlem ve kilit sırası, no-op, ısı payı çifti, audit ayrıntısı, katı audit, önbellek boşaltma, site / hesap yokluğu).
// Gerçek PostgreSQL: scripts/qa_platform_pg.mjs "platform_rules".
import { describe, it, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import { RULES, RULE_GROUPS, RULE_KEYS, getRule, invalidateRuleCache, ruleCacheSize } from '../src/modules/platform_rules.js';
import { buildRuleItem, listRules, parseRulesPatch, updateRules } from '../src/modules/platform_rules_service.js';

const TODAY = '2026-10-21';
const NOW = new Date('2026-10-21T09:00:00Z');
const SITE = 1000000001;
const LATE = RULES['finance.late_fee.monthly_bp_max'];
const FORECAST = RULES['forecast.default_increase_bp'];
const norm = (text) => String(text).replace(/\s+/g, ' ').trim();

let nextId = 100;
const dbRow = (key, value, validFrom, { site = null, inherit = false, note = null, by = 'Süper Kişi', id = ++nextId } = {}) => ({
  id: String(id),
  rule_key: key,
  site_code: site === null ? null : String(site),
  value,
  inherit,
  valid_from: validFrom,
  note,
  created_at: new Date(`${validFrom}T08:00:00Z`),
  created_by_name: by,
});

const expectError = async (promise, status, code) => {
  await assert.rejects(promise, (error) => {
    assert.equal(error.statusCode, status, `${error.code}: ${error.message}`);
    assert.equal(error.code, code);
    assert.equal(error.expose, true);
    return true;
  });
};
const expectSyncError = (fn, status, code) => {
  try {
    fn();
  } catch (error) {
    assert.equal(error.statusCode, status, `${error.code}: ${error.message}`);
    assert.equal(error.code, code);
    return error;
  }
  assert.fail('hata bekleniyordu');
};

describe('buildRuleItem (görünüm)', () => {
  it('satır yok: varsayılan; meta alanlar sözleşme adlarıyla; site null; planlı yok', () => {
    const item = buildRuleItem(LATE, [], { siteCode: null, onDate: TODAY, includeNames: true });
    assert.deepEqual(item, {
      key: 'finance.late_fee.monthly_bp_max',
      group: 'finance',
      label: LATE.label,
      description: LATE.description,
      type: 'int',
      unit: 'bp',
      nullable: false,
      min: 0,
      max: 500,
      default: 500,
      site_overridable: false,
      schedulable: false,
      editable: true,
      locked_reason: null,
      pair: null,
      legal_note: LATE.legalNote,
      platform: { value: 500, source: 'default', valid_from: null, note: null, updated_at: null, updated_by_name: null },
      site: null,
      effective: { value: 500, source: 'default', valid_from: null },
      scheduled: [],
    });
  });

  it('platform satırı + ileri tarihli satır: bugünkü değer, planlı listede; ad yalnız includeNames iken', () => {
    const rows = [dbRow('budget.objection_days', 10, '2026-03-01', { note: 'Kurul kararı' }), dbRow('budget.objection_days', 14, '2027-01-01')];
    const rule = RULES['budget.objection_days'];
    const item = buildRuleItem(rule, rows, { siteCode: null, onDate: TODAY, includeNames: true });
    assert.deepEqual(item.platform, { value: 10, source: 'platform', valid_from: '2026-03-01', note: 'Kurul kararı', updated_at: '2026-03-01T08:00:00.000Z', updated_by_name: 'Süper Kişi' });
    assert.deepEqual(item.effective, { value: 10, source: 'platform', valid_from: '2026-03-01' });
    assert.deepEqual(item.scheduled, [{ scope: 'platform', value: 14, inherit: false, valid_from: '2027-01-01', note: null }]);
    const hidden = buildRuleItem(rule, rows, { siteCode: null, onDate: TODAY, includeNames: false });
    assert.equal(hidden.platform.updated_by_name, null, 'yönetici görünümünde ad yok');
    assert.equal(hidden.platform.note, 'Kurul kararı');
  });

  it('site kapsamı: sitede değişebilen kuralda site değeri etkin; planlı site satırı "site" kapsamıyla; inherit satırı site değerini kaldırır', () => {
    const rows = [
      dbRow('forecast.default_increase_bp', 800, '2026-01-01'),
      dbRow('forecast.default_increase_bp', 1500, '2026-05-01', { site: SITE }),
      dbRow('forecast.default_increase_bp', null, '2027-01-01', { site: SITE, inherit: true }),
    ];
    const item = buildRuleItem(FORECAST, rows, { siteCode: SITE, onDate: TODAY, includeNames: true });
    assert.equal(item.platform.value, 800);
    assert.deepEqual(item.site, { value: 1500, valid_from: '2026-05-01', note: null, updated_at: '2026-05-01T08:00:00.000Z', updated_by_name: 'Süper Kişi' });
    assert.deepEqual(item.effective, { value: 1500, source: 'site', valid_from: '2026-05-01' });
    assert.deepEqual(item.scheduled, [{ scope: 'site', value: null, inherit: true, valid_from: '2027-01-01', note: null }]);
    const later = buildRuleItem(FORECAST, rows, { siteCode: SITE, onDate: '2027-01-01', includeNames: true });
    assert.equal(later.site, null);
    assert.deepEqual(later.effective, { value: 800, source: 'platform', valid_from: '2026-01-01' });
  });

  it('site kapsamında sitede DEĞİŞEMEYEN kural: site alanı null, etkin değer platformdan; site satırları planlıda da yok', () => {
    const rows = [dbRow('finance.late_fee.monthly_bp_max', 400, '2026-01-01'), dbRow('finance.late_fee.monthly_bp_max', 100, '2026-02-01', { site: SITE })];
    const item = buildRuleItem(LATE, rows, { siteCode: SITE, onDate: TODAY, includeNames: true });
    assert.equal(item.site, null);
    assert.equal(item.effective.value, 400);
    assert.equal(item.effective.source, 'platform');
  });
});

describe('parseRulesPatch (gövde)', () => {
  const parse = (body) => parseRulesPatch(body, { today: TODAY });
  const one = (change = { key: 'budget.objection_days', value: 10 }, extra = {}) => ({ changes: [change], ...extra });

  it('en küçük gövde: platform kapsamı, bugün geçerli, not yok; değişiklik kurala bağlanır', () => {
    const input = parse(one());
    assert.equal(input.siteCode, null);
    assert.equal(input.validFrom, TODAY);
    assert.equal(input.note, null);
    assert.deepEqual(input.changes.map((c) => [c.key, c.value, c.inherit, c.rule === RULES[c.key]]), [['budget.objection_days', 10, false, true]]);
  });

  it('valid_from: bugün..5 yıl sonrası; geçmiş, çok ileri, biçimsiz ya da gerçek olmayan tarih 400 INVALID_BODY', () => {
    assert.equal(parse(one(undefined, { valid_from: '2031-10-21' })).validFrom, '2031-10-21');
    assert.equal(parse(one(undefined, { valid_from: null })).validFrom, TODAY);
    for (const bad of ['2026-10-20', '2031-10-22', '2026-13-01', '2026-02-30', '21.10.2026', 20261021, '']) {
      expectSyncError(() => parse(one(undefined, { valid_from: bad })), 400, 'INVALID_BODY');
    }
  });

  it('not: tek satıra indirilir, kırpılır, boş -> null, 200 karakteri aşamaz, metin olmalı', () => {
    assert.equal(parse(one(undefined, { note: '  7579 sayılı\nKanun   gereği ' })).note, '7579 sayılı Kanun gereği');
    assert.equal(parse(one(undefined, { note: '   ' })).note, null);
    expectSyncError(() => parse(one(undefined, { note: 'x'.repeat(201) })), 400, 'INVALID_BODY');
    expectSyncError(() => parse(one(undefined, { note: 12 })), 400, 'INVALID_BODY');
  });

  it('yapı: nesne olmalı, bilinmeyen kök alan yok, değişiklik 1..20, site kodu pozitif tam sayı', () => {
    for (const bad of [null, [], 'x', {}, { changes: [] }, { changes: 'x' }, { changes: [{ key: 'budget.objection_days', value: 1 }], extra: 1 }, { ...one(), site_code: 'abc' }, { ...one(), site_code: -5 }, { ...one(), site_code: 0 }]) {
      expectSyncError(() => parse(bad), 400, 'INVALID_BODY');
    }
    const many = { changes: RULE_KEYS.slice(0, 14).concat(['x.a', 'x.b', 'x.c', 'x.d', 'x.e', 'x.f', 'x.g']).map((key) => ({ key, value: 1 })) };
    expectSyncError(() => parse(many), 400, 'INVALID_BODY');
    for (const bad of [{ changes: [null] }, { changes: [{ value: 1 }] }, { changes: [{ key: 5, value: 1 }] }, { changes: [{ key: 'budget.objection_days', value: 1, extra: true }] }]) {
      expectSyncError(() => parse(bad), 400, 'INVALID_BODY');
    }
    assert.equal(parse({ ...one({ key: 'forecast.default_increase_bp', value: 100 }), site_code: String(SITE) }).siteCode, SITE);
  });

  it('kural hataları TEK yanıtta toplanır: VALIDATION_FAILED + fields (Türkçe) + rule_codes; bilinmeyen ve yinelenen anahtar da', () => {
    const error = expectSyncError(
      () =>
        parse({
          changes: [
            { key: 'finance.late_fee.monthly_bp_max', value: 600 },
            { key: 'retention.enforce', value: true },
            { key: 'yok.boyle', value: 1 },
            { key: 'budget.objection_days', value: 9 },
            { key: 'budget.objection_days', value: 10 },
          ],
        }),
      400,
      'VALIDATION_FAILED',
    );
    assert.deepEqual(Object.keys(error.extra.fields).sort(), ['budget.objection_days', 'finance.late_fee.monthly_bp_max', 'retention.enforce', 'yok.boyle']);
    assert.deepEqual(error.extra.rule_codes, {
      'finance.late_fee.monthly_bp_max': 'RULE_VALUE_INVALID',
      'retention.enforce': 'RULE_LOCKED',
      'yok.boyle': 'RULE_UNKNOWN',
      'budget.objection_days': 'RULE_DUPLICATE',
    });
    for (const message of Object.values(error.extra.fields)) assert.ok(!/_/.test(message) && message.length > 5, message);
  });

  it('kapsam ve tarih kuralları: sitede değişemeyen kural site kapsamında, planlanamayan kural ileri tarihte reddedilir', () => {
    const site = expectSyncError(() => parse({ site_code: SITE, changes: [{ key: 'finance.late_fee.monthly_bp_max', value: 400 }] }), 400, 'VALIDATION_FAILED');
    assert.equal(site.extra.rule_codes['finance.late_fee.monthly_bp_max'], 'RULE_NOT_SITE_OVERRIDABLE');
    const future = expectSyncError(() => parse({ valid_from: '2027-01-01', changes: [{ key: 'finance.late_fee.monthly_bp_max', value: 400 }] }), 400, 'VALIDATION_FAILED');
    assert.equal(future.extra.rule_codes['finance.late_fee.monthly_bp_max'], 'RULE_NOT_SCHEDULABLE');
  });
});

// --- Yazma akışı: sahte veritabanı ----------------------------------------------------------------------------------------------------------

function fakeDb({ rows = [], sites = [SITE], users = [1], failAudit = false } = {}) {
  const state = { rows: [...rows], log: [], audits: [], committed: false, rolledBack: false };
  const handle = async (text, params = [], tx = false) => {
    const sql = norm(text);
    state.log.push({ sql, params, tx });
    if (/^(BEGIN|COMMIT|ROLLBACK)$/.test(sql)) {
      if (sql === 'COMMIT') state.committed = true;
      if (sql === 'ROLLBACK') state.rolledBack = true;
      return { rows: [] };
    }
    if (/^(SAVEPOINT|RELEASE SAVEPOINT|ROLLBACK TO SAVEPOINT) /.test(sql)) return { rows: [] };
    if (/^SELECT pg_advisory_xact_lock\(\$1::int, \$2::int\)$/.test(sql)) return { rows: [] };
    if (/^SELECT user_code FROM users WHERE user_code = \$1 AND deleted_at IS NULL FOR KEY SHARE$/.test(sql)) {
      return { rows: users.includes(Number(params[0])) ? [{ user_code: params[0] }] : [] };
    }
    if (/^SELECT site_code, name FROM sites WHERE site_code = \$1( FOR KEY SHARE)?$/.test(sql)) {
      return { rows: sites.includes(Number(params[0])) ? [{ site_code: String(params[0]), name: 'Gül Sitesi' }] : [] };
    }
    if (/FROM platform_rule_values v LEFT JOIN users u ON u\.user_code = v\.created_by WHERE v\.rule_key = ANY\(\$1::TEXT\[\]\) AND \(v\.site_code IS NULL OR v\.site_code = \$2\)/.test(sql)) {
      const [keys, site] = params;
      return { rows: state.rows.filter((r) => keys.includes(r.rule_key) && (r.site_code === null || (site !== null && Number(r.site_code) === Number(site)))) };
    }
    if (/^INSERT INTO platform_rule_values \(rule_key, site_code, value, inherit, valid_from, note, created_by\) VALUES \(\$1, \$2, \$3::JSONB, \$4, \$5::DATE, \$6, \$7\) RETURNING id$/.test(sql)) {
      const [key, site, value, inherit, validFrom, note] = params;
      const id = ++nextId;
      state.rows.push({ id: String(id), rule_key: key, site_code: site === null ? null : String(site), value: value === null ? null : JSON.parse(value), inherit, valid_from: validFrom, note, created_at: NOW, created_by_name: 'Süper Kişi' });
      return { rows: [{ id: String(id) }] };
    }
    if (/^INSERT INTO audit_log/.test(sql)) {
      if (failAudit) throw Object.assign(new Error('audit kapalı'), { code: '42P01' });
      state.audits.push({ action: params[3], siteCode: params[4], targetType: params[5], targetId: params[6], details: JSON.parse(params[7]) });
      return { rows: [] };
    }
    throw new Error(`BEKLENMEYEN SQL (sahte DB katı): ${sql.slice(0, 200)}`);
  };
  return {
    state,
    query: (text, params) => handle(text, params, false),
    connect: async () => ({ query: (text, params) => handle(text, params, true), release() {} }),
  };
}

const SUPER = { id: 1, user_code: 1, userCode: 1, role: 'super_user', full_name: 'Süper Kişi' };

describe('updateRules (yazma akışı)', () => {
  beforeEach(() => invalidateRuleCache());

  it('işlem sırası: BEGIN -> kurallar advisory kilidi -> işlemi yapan KEY SHARE -> satırları oku -> INSERT -> audit (SAVEPOINT) -> COMMIT; yanıt güncel görünüm + changed', async () => {
    const db = fakeDb({ rows: [dbRow('finance.late_fee.monthly_bp_max', 500, '2026-01-01')] });
    const result = await updateRules({ body: { changes: [{ key: 'finance.late_fee.monthly_bp_max', value: 400 }], note: 'Deneme' }, actor: SUPER, now: NOW }, db);
    const tx = db.state.log.filter((entry) => entry.tx).map((entry) => entry.sql);
    const at = (pattern) => tx.findIndex((sql) => pattern.test(sql));
    const order = [/^BEGIN$/, /^SELECT pg_advisory_xact_lock/, /^SELECT user_code FROM users/, /FROM platform_rule_values v/, /^INSERT INTO platform_rule_values/, /^SAVEPOINT/, /^INSERT INTO audit_log/, /^COMMIT$/].map(at);
    assert.ok(order.every((index, i) => index >= 0 && (i === 0 || index > order[i - 1])), JSON.stringify(tx));
    const lock = db.state.log.find((entry) => /pg_advisory_xact_lock/.test(entry.sql));
    assert.deepEqual(lock.params, [0x5052554c, 1]);
    const insert = db.state.log.find((entry) => /^INSERT INTO platform_rule_values/.test(entry.sql));
    assert.deepEqual(insert.params, ['finance.late_fee.monthly_bp_max', null, '400', false, TODAY, 'Deneme', 1]);
    assert.deepEqual(result.changed, ['finance.late_fee.monthly_bp_max']);
    assert.equal(result.can_edit, true);
    assert.equal(result.on_date, TODAY);
    assert.equal(result.items.find((item) => item.key === 'finance.late_fee.monthly_bp_max').effective.value, 400);
    assert.equal(result.items.length, RULE_KEYS.length);
    assert.deepEqual(result.groups, RULE_GROUPS);
  });

  it('audit: platform_rule.updated, hedef kural anahtarı, ayrıntı yalnız kapsam / tarih / eski ve yeni değer (not metni YOK)', async () => {
    const db = fakeDb({ rows: [dbRow('finance.late_fee.monthly_bp_max', 450, '2026-01-01')] });
    await updateRules({ body: { note: 'gizli not metni', changes: [{ key: 'finance.late_fee.monthly_bp_max', value: 400 }] }, actor: SUPER, now: NOW }, db);
    assert.deepEqual(db.state.audits, [
      { action: 'platform_rule.updated', siteCode: null, targetType: 'platform_rule', targetId: 'finance.late_fee.monthly_bp_max', details: { scope: 'platform', valid_from: TODAY, from: 450, to: 400, inherit: false } },
    ]);
    assert.equal(JSON.stringify(db.state.audits).includes('gizli'), false);
  });

  it('no-op: kapsamın o tarihteki değeriyle aynıysa satır ve audit YAZILMAZ; satır yokken "üst düzeye dön" de no-op', async () => {
    const db = fakeDb({ rows: [dbRow('budget.objection_days', 10, '2026-01-01')] });
    const result = await updateRules({ body: { changes: [{ key: 'budget.objection_days', value: 10 }, { key: 'budget.provisional_max_days', inherit: true }] }, actor: SUPER, now: NOW }, db);
    assert.deepEqual(result.changed, []);
    assert.equal(db.state.log.some((entry) => /^INSERT INTO platform_rule_values/.test(entry.sql)), false);
    assert.equal(db.state.audits.length, 0);
    assert.equal(db.state.committed, true);
  });

  it('ısı payı çifti: tek başına değişiklik toplamı bozarsa 400 (ROLLBACK, yazılmaz); ikisi birlikte 100 ise yazılır; sonraki planlı tarih de denetlenir', async () => {
    const single = fakeDb();
    await expectError(updateRules({ body: { changes: [{ key: 'heat.measured_share_pct', value: 60 }] }, actor: SUPER, now: NOW }, single), 400, 'VALIDATION_FAILED');
    assert.equal(single.state.rolledBack, true);
    assert.equal(single.state.committed, false);
    const both = fakeDb();
    const result = await updateRules({ body: { changes: [{ key: 'heat.measured_share_pct', value: 60 }, { key: 'heat.area_share_pct', value: 40 }] }, actor: SUPER, now: NOW }, both);
    assert.deepEqual(result.changed, ['heat.measured_share_pct', 'heat.area_share_pct']);
    const future = fakeDb({ rows: [dbRow('heat.area_share_pct', 35, '2027-01-01'), dbRow('heat.measured_share_pct', 65, '2027-01-01')] });
    await updateRules({ body: { changes: [{ key: 'heat.measured_share_pct', value: 60 }, { key: 'heat.area_share_pct', value: 40 }] }, actor: SUPER, now: NOW }, future);
    const broken = fakeDb({ rows: [dbRow('heat.area_share_pct', 35, '2027-01-01')] });
    const error = await updateRules({ body: { changes: [{ key: 'heat.measured_share_pct', value: 60 }, { key: 'heat.area_share_pct', value: 40 }] }, actor: SUPER, now: NOW }, broken).catch((e) => e);
    assert.equal(error.code, 'VALIDATION_FAILED');
    assert.match(Object.values(error.extra.fields).join(' '), /01\.01\.2027/);
  });

  it('site kapsamı: site yoksa 404 SITE_NOT_FOUND (site satırı KEY SHARE ile kilitlenir); varsa site satırı yazılır, audit site koduyla', async () => {
    const missing = fakeDb({ sites: [] });
    await expectError(updateRules({ body: { site_code: SITE, changes: [{ key: 'forecast.default_increase_bp', value: 1200 }] }, actor: SUPER, now: NOW }, missing), 404, 'SITE_NOT_FOUND');
    assert.equal(missing.state.rolledBack, true);
    const db = fakeDb();
    const result = await updateRules({ body: { site_code: SITE, changes: [{ key: 'forecast.default_increase_bp', value: 1200 }] }, actor: SUPER, now: NOW }, db);
    assert.ok(db.state.log.some((entry) => entry.tx && /^SELECT site_code, name FROM sites WHERE site_code = \$1 FOR KEY SHARE$/.test(entry.sql)));
    assert.equal(db.state.audits[0].siteCode, SITE);
    assert.equal(db.state.audits[0].details.scope, 'site');
    assert.deepEqual(result.site, { site_code: SITE, site_name: 'Gül Sitesi' });
    assert.equal(result.items.find((item) => item.key === 'forecast.default_increase_bp').effective.source, 'site');
  });

  it('silinmiş hesap 401 ACCOUNT_DELETED (yazılmaz); audit yazılamazsa değişiklik de GERİ ALINIR (her değişiklik denetim kaydında)', async () => {
    const deleted = fakeDb({ users: [] });
    await expectError(updateRules({ body: { changes: [{ key: 'budget.objection_days', value: 9 }] }, actor: SUPER, now: NOW }, deleted), 401, 'ACCOUNT_DELETED');
    const noAudit = fakeDb({ failAudit: true });
    await assert.rejects(updateRules({ body: { changes: [{ key: 'budget.objection_days', value: 9 }] }, actor: SUPER, now: NOW }, noAudit));
    assert.equal(noAudit.state.committed, false);
    assert.equal(noAudit.state.rolledBack, true);
  });

  it('COMMIT sonrası getRule önbelleği boşalır (yeni değer hemen okunur)', async () => {
    const db = fakeDb({ rows: [dbRow('finance.late_fee.monthly_bp_max', 500, '2026-01-01')] });
    const reader = { query: async (_text, params) => ({ rows: db.state.rows.filter((r) => r.rule_key === params[0] && r.site_code === null) }) };
    assert.equal(await getRule(reader, 'finance.late_fee.monthly_bp_max', { onDate: TODAY }), 500);
    assert.ok(ruleCacheSize() > 0);
    await updateRules({ body: { changes: [{ key: 'finance.late_fee.monthly_bp_max', value: 300 }] }, actor: SUPER, now: NOW }, db);
    assert.equal(ruleCacheSize(), 0);
    assert.equal(await getRule(reader, 'finance.late_fee.monthly_bp_max', { onDate: TODAY }), 300);
  });

  it('süresiz (null) değer SQL NULL olarak, "üst düzeye dön" inherit=TRUE ve değer NULL olarak yazılır', async () => {
    const db = fakeDb({ rows: [dbRow('retention.decision_book_days', 7300, '2026-01-01'), dbRow('forecast.default_increase_bp', 900, '2026-01-01', { site: SITE })] });
    await updateRules({ body: { changes: [{ key: 'retention.decision_book_days', value: null }] }, actor: SUPER, now: NOW }, db);
    await updateRules({ body: { site_code: SITE, changes: [{ key: 'forecast.default_increase_bp', inherit: true }] }, actor: SUPER, now: NOW }, db);
    const inserts = db.state.log.filter((entry) => /^INSERT INTO platform_rule_values/.test(entry.sql)).map((entry) => entry.params);
    assert.deepEqual(inserts, [
      ['retention.decision_book_days', null, null, false, TODAY, null, 1],
      ['forecast.default_increase_bp', SITE, null, true, TODAY, null, 1],
    ]);
  });
});

describe('listRules', () => {
  it('platform görünümü: site null, gruplar, 15 kural sırayla; site görünümü: site yoksa 404', async () => {
    const db = fakeDb();
    const body = await listRules(db, { siteCode: null, onDate: TODAY, includeNames: true, canEdit: true });
    assert.equal(body.site, null);
    assert.deepEqual(body.items.map((item) => item.key), [...RULE_KEYS]);
    await expectError(listRules(fakeDb({ sites: [] }), { siteCode: SITE, onDate: TODAY, includeNames: false, canEdit: false }), 404, 'SITE_NOT_FOUND');
    const site = await listRules(db, { siteCode: SITE, onDate: TODAY, includeNames: false, canEdit: false });
    assert.deepEqual(site.site, { site_code: SITE, site_name: 'Gül Sitesi' });
    assert.equal(site.can_edit, false);
  });
});
