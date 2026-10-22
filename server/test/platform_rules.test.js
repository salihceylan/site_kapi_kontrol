// Kurallar tablosu (G11; docs/PLATFORM_KURALLAR.md, sözleşme 2.2) — saf katman: kayıt defteri, çözüm sırası, kırpma, doğrulama, getRule önbelleği.
// Gerçek PostgreSQL: scripts/qa_platform_pg.mjs "platform_rules".
import { describe, it, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { LATE_FEE_MAX_MONTHLY_BP } from '../src/modules/finance_4b_common.js';
import {
  RULES,
  RULE_GROUPS,
  RULE_KEYS,
  RULE_ROWS_SQL,
  getRule,
  invalidateRuleCache,
  normalizeRuleValue,
  resolveRuleFromRows,
  ruleCacheSize,
  ruleCacheTuning,
  ruleOf,
  validateRuleChange,
} from '../src/modules/platform_rules.js';

const here = path.dirname(fileURLToPath(import.meta.url));
const LATE = RULES['finance.late_fee.monthly_bp_max'];
const FORECAST = RULES['forecast.default_increase_bp'];
const BOOK = RULES['retention.decision_book_days'];
const ENFORCE = RULES['retention.enforce'];
const SITE = 1000000001;
let nextRowId = 0;
/** pg satırı biçimi: BIGINT (id, site_code) METİN döner; değer JSONB'den çözülmüş JS değeri. */
const row = (value, validFrom, { site = null, inherit = false, id = ++nextRowId } = {}) => ({
  id: String(id),
  site_code: site === null ? null : String(site),
  value,
  inherit,
  valid_from: validFrom,
});

describe('kayıt defteri (sözleşme 2.2)', () => {
  it('16 anahtar, sözleşmedeki sırayla ve varsayılanlarla', () => {
    assert.deepEqual(
      RULE_KEYS.map((key) => [key, RULES[key].defaultValue]),
      [
        ['finance.late_fee.monthly_bp_max', 500],
        ['budget.provisional_max_days', 90],
        ['budget.objection_days', 7],
        ['heat.measured_share_pct', 70],
        ['heat.area_share_pct', 30],
        ['forecast.default_increase_bp', 0],
        ['retention.finance_days', 3650],
        ['retention.contact_after_moveout_days', 365],
        ['retention.door_logs_days', 365],
        ['retention.visitor_logs_days', 365],
        ['retention.work_photos_after_close_days', 730],
        ['retention.announcements_days', 1825],
        ['retention.audit_days', 1825],
        ['retention.residency_log_days', 3650],
        ['retention.decision_book_days', null],
        ['retention.enforce', false],
      ],
    );
  });

  it('her kural: grup, Türkçe ad ve açıklama, tür, birim, sınırlar (varsayılan sınır içinde), mevzuat notu alanı; nesneler donmuş', () => {
    const groups = new Set(RULE_GROUPS.map((group) => group.code));
    assert.deepEqual([...groups], ['finance', 'budget', 'heat', 'forecast', 'retention']);
    for (const key of RULE_KEYS) {
      const rule = RULES[key];
      assert.equal(rule.key, key);
      assert.ok(groups.has(rule.group), key);
      assert.equal(key.startsWith(`${rule.group}.`), true, `${key}: anahtar grubun önekiyle başlar`);
      assert.ok(rule.label.length >= 3 && rule.label.length <= 80, `${key}: ad`);
      assert.ok(rule.description.length >= 10 && rule.description.length <= 300, `${key}: açıklama`);
      assert.ok(['int', 'bool'].includes(rule.type), key);
      assert.ok(typeof rule.legalNote === 'string' && rule.legalNote.length > 0, `${key}: mevzuat notu`);
      assert.equal(typeof rule.siteOverridable, 'boolean');
      assert.equal(typeof rule.schedulable, 'boolean');
      assert.equal(typeof rule.editable, 'boolean');
      assert.equal(typeof rule.nullable, 'boolean');
      if (rule.type === 'int') {
        assert.ok(['bp', 'pct', 'days'].includes(rule.unit), key);
        assert.ok(Number.isInteger(rule.min) && Number.isInteger(rule.max) && rule.min <= rule.max, `${key}: sınır`);
        if (rule.defaultValue === null) {
          assert.equal(rule.nullable, true, `${key}: null varsayılan yalnız süresiz kuralda`);
        } else {
          assert.ok(rule.defaultValue >= rule.min && rule.defaultValue <= rule.max, `${key}: varsayılan sınır içinde`);
        }
      } else {
        assert.equal(rule.unit, null);
        assert.equal(typeof rule.defaultValue, 'boolean');
        assert.equal(rule.nullable, false);
      }
      assert.ok(Object.isFrozen(rule), `${key}: donmuş`);
    }
    assert.ok(Object.isFrozen(RULES));
    assert.ok(Object.isFrozen(RULE_KEYS));
    assert.equal(ruleOf('yok.boyle'), null);
    assert.equal(ruleOf('__proto__'), null);
    assert.equal(ruleOf('finance.late_fee.monthly_bp_max'), RULES['finance.late_fee.monthly_bp_max']);
  });

  it('gecikme üst sınırı: 0..500 bp (yasal sınır sabitiyle AYNI), yalnız platform, ileri tarihli planlanamaz, KMK m.20 notu', () => {
    const rule = RULES['finance.late_fee.monthly_bp_max'];
    assert.equal(rule.unit, 'bp');
    assert.equal(rule.min, 0);
    assert.equal(rule.max, LATE_FEE_MAX_MONTHLY_BP);
    assert.equal(rule.max, 500);
    assert.equal(rule.siteOverridable, false);
    assert.equal(rule.schedulable, false);
    assert.equal(rule.editable, true);
    assert.match(rule.legalNote, /KMK/);
    assert.match(rule.legalNote, /m\.20/);
    assert.match(rule.legalNote, /AVUKAT DOĞRULASIN/);
  });

  it('sitede değişebilen tek kural tahmin artışı; ısı payları çift (toplam 100); karar defteri süresiz (null); otomatik silme kilitli ve kapalı', () => {
    assert.deepEqual(RULE_KEYS.filter((key) => RULES[key].siteOverridable), ['forecast.default_increase_bp']);
    assert.deepEqual(RULES['heat.measured_share_pct'].pair, { key: 'heat.area_share_pct', sum: 100 });
    assert.deepEqual(RULES['heat.area_share_pct'].pair, { key: 'heat.measured_share_pct', sum: 100 });
    assert.equal(RULES['heat.measured_share_pct'].defaultValue + RULES['heat.area_share_pct'].defaultValue, 100);
    for (const key of RULE_KEYS.filter((k) => !k.startsWith('heat.'))) assert.equal(RULES[key].pair, null, key);
    assert.equal(RULES['retention.decision_book_days'].nullable, true);
    assert.equal(RULES['retention.decision_book_days'].defaultValue, null);
    const enforce = RULES['retention.enforce'];
    assert.equal(enforce.type, 'bool');
    assert.equal(enforce.defaultValue, false);
    assert.equal(enforce.editable, false);
    assert.match(enforce.lockedReason, /avukat/i);
    assert.deepEqual(RULE_KEYS.filter((key) => !RULES[key].editable), ['retention.enforce']);
    assert.deepEqual(RULE_KEYS.filter((key) => !RULES[key].schedulable), ['finance.late_fee.monthly_bp_max']);
    for (const key of RULE_KEYS.filter((k) => k.startsWith('retention.') && RULES[k].type === 'int')) assert.equal(RULES[key].unit, 'days', key);
  });

  it('saklama süreleri gerçeği söyler: kapı geçiş kayıtlarının BUGÜNKÜ bakım silmesi (maintenance_service) kapı kaydı ve otomatik silme açıklamasında yazılı', () => {
    // Bakım servisi kapı geçiş kayıtlarını bu kuraldan bağımsız olarak siler; ekran "1 yıl saklanır, otomatik silme kapalı" izlenimi vermemeli.
    const source = readFileSync(path.join(here, '..', 'src', 'services', 'maintenance_service.js'), 'utf8');
    const match = /DELETE FROM door_access_logs\s+WHERE opened_at < NOW\(\) - INTERVAL '(\d+) days'/.exec(source);
    assert.ok(match, 'bakım servisindeki kapı geçiş kaydı silmesi bulunamadı (açıklamayı ve bu testi birlikte güncelleyin)');
    const days = match[1];
    const doorLogs = RULES['retention.door_logs_days'];
    assert.match(doorLogs.description, new RegExp(`${days} gün sonra silinir`), doorLogs.description);
    assert.match(ENFORCE.description, new RegExp(`${days} günlük`), ENFORCE.description);
    for (const key of RULE_KEYS) assert.ok(RULES[key].description.length <= 300, `${key}: açıklama 300 karakteri aşmaz`);
  });
});

describe('çözüm sırası (site -> platform -> varsayılan) ve tarih', () => {
  const at = (rule, rows, options) => resolveRuleFromRows(rule, rows, { onDate: '2026-10-21', ...options });

  it('satır yoksa varsayılan; platform satırı varsa platform; sitede değişebilen kuralda site satırı platformu ezer', () => {
    assert.deepEqual(at(FORECAST, []), { value: 0, source: 'default', validFrom: null, rowId: null });
    const platform = row(500, '2026-01-01');
    assert.deepEqual(at(FORECAST, [platform]), { value: 500, source: 'platform', validFrom: '2026-01-01', rowId: Number(platform.id) });
    const site = row(1200, '2026-05-01', { site: SITE });
    assert.deepEqual(at(FORECAST, [platform, site], { siteCode: SITE }), { value: 1200, source: 'site', validFrom: '2026-05-01', rowId: Number(site.id) });
    // site kodu verilmezse (platform görünümü) site satırı yok sayılır
    assert.equal(at(FORECAST, [platform, site]).source, 'platform');
    // başka sitenin satırı yok sayılır
    assert.equal(at(FORECAST, [platform, site], { siteCode: SITE + 1 }).value, 500);
  });

  it('sitede DEĞİŞEMEYEN kuralda site satırı (doğrudan SQL ile yazılmış olsa da) yok sayılır', () => {
    const rows = [row(400, '2026-01-01'), row(100, '2026-02-01', { site: SITE })];
    assert.deepEqual(at(LATE, rows, { siteCode: SITE }), { value: 400, source: 'platform', validFrom: '2026-01-01', rowId: Number(rows[0].id) });
  });

  it('tarih: valid_from <= tarih olan en yeni satır; gelecek tarihli satır o güne dek yok sayılır; aynı günde büyük id kazanır', () => {
    const old = row(300, '2025-01-01');
    const current = row(450, '2026-03-01');
    const future = row(200, '2027-01-01');
    const rows = [future, current, old];
    assert.equal(at(LATE, rows).value, 450);
    assert.equal(at(LATE, rows, { onDate: '2026-02-28' }).value, 300);
    assert.equal(at(LATE, rows, { onDate: '2026-12-31' }).value, 450);
    assert.equal(at(LATE, rows, { onDate: '2027-01-01' }).value, 200);
    assert.equal(at(LATE, rows, { onDate: '2024-12-31' }).source, 'default');
    const first = row(100, '2026-10-21', { id: 70 });
    const second = row(250, '2026-10-21', { id: 71 });
    assert.equal(at(LATE, [second, first]).value, 250, 'aynı gün: sonraki kayıt');
    assert.equal(at(LATE, [first, second]).value, 250, 'girdi sırasından bağımsız');
  });

  it('inherit: site satırı "platforma dön", platform satırı "varsayılana dön" demektir (o tarihten itibaren)', () => {
    const rows = [row(800, '2026-01-01'), row(1500, '2026-02-01', { site: SITE }), row(null, '2026-06-01', { site: SITE, inherit: true })];
    assert.equal(at(FORECAST, rows, { siteCode: SITE, onDate: '2026-05-31' }).value, 1500);
    assert.deepEqual(at(FORECAST, rows, { siteCode: SITE, onDate: '2026-06-01' }), { value: 800, source: 'platform', validFrom: '2026-01-01', rowId: Number(rows[0].id) });
    const reset = [row(400, '2026-01-01'), row(null, '2026-09-01', { inherit: true })];
    assert.deepEqual(at(LATE, reset), { value: 500, source: 'default', validFrom: null, rowId: null });
    assert.equal(at(LATE, reset, { onDate: '2026-08-31' }).value, 400);
  });
});

describe('kırpma ve tür denetimi (getRule sonucu her zaman sınır içinde)', () => {
  it('tam sayı: sınır dışı değer sınıra kırpılır (yasal üst sınır aşılamaz)', () => {
    assert.equal(normalizeRuleValue(LATE, 900), 500);
    assert.equal(normalizeRuleValue(LATE, 501), 500);
    assert.equal(normalizeRuleValue(LATE, -20), 0);
    assert.equal(normalizeRuleValue(LATE, 350), 350);
    assert.equal(normalizeRuleValue(LATE, 1e20), 500);
    assert.equal(resolveRuleFromRows(LATE, [row(9999, '2026-01-01')], { onDate: '2026-10-21' }).value, 500);
  });

  it('tür uymayan / tam sayı olmayan değer ve izin verilmeyen null VARSAYILANA düşer; süresiz kuralda null geçerlidir', () => {
    for (const bad of ['450', 450.5, Number.NaN, Number.POSITIVE_INFINITY, true, {}, [], null, undefined]) {
      assert.equal(normalizeRuleValue(LATE, bad), 500, String(bad));
    }
    assert.equal(normalizeRuleValue(BOOK, null), null);
    assert.equal(normalizeRuleValue(BOOK, 100), 3650, 'süresiz kuralda sayı da sınıra kırpılır');
    assert.equal(normalizeRuleValue(BOOK, 'x'), null, 'süresiz kuralın varsayılanı null');
    assert.equal(normalizeRuleValue(ENFORCE, true), true);
    assert.equal(normalizeRuleValue(ENFORCE, 1), false);
    assert.equal(normalizeRuleValue(ENFORCE, 'true'), false);
    assert.equal(normalizeRuleValue(ENFORCE, null), false);
  });
});

describe('yazma doğrulaması (validateRuleChange: sınır dışı değer KIRPILMAZ, reddedilir)', () => {
  const ok = (rule, change, options) => {
    const result = validateRuleChange(rule, change, options);
    assert.equal(result.ok, true, JSON.stringify(result));
    return result;
  };
  const bad = (rule, change, code, options) => {
    const result = validateRuleChange(rule, change, options);
    assert.equal(result.ok, false, JSON.stringify(change));
    assert.equal(result.code, code, JSON.stringify(change));
    assert.ok(typeof result.message === 'string' && result.message.length > 10 && !/_/.test(result.message), result.message);
    return result;
  };

  it('tam sayı sınır içinde geçer; sınır dışı, ondalık, metin, null (süresiz değilse) reddedilir', () => {
    assert.deepEqual(ok(LATE, { value: 0 }), { ok: true, value: 0, inherit: false });
    assert.deepEqual(ok(LATE, { value: 500 }), { ok: true, value: 500, inherit: false });
    for (const value of [501, -1, 450.5, '450', null, true, [], {}, Number.NaN]) bad(LATE, { value }, 'RULE_VALUE_INVALID');
    assert.match(bad(LATE, { value: 501 }, 'RULE_VALUE_INVALID').message, /Gecikme tazminatı aylık üst sınırı/);
    bad(LATE, {}, 'RULE_VALUE_INVALID');
  });

  it('süresiz kural null kabul eder; sayı yine sınır içinde olmalı; bool kural yalnız boolean', () => {
    assert.deepEqual(ok(BOOK, { value: null }), { ok: true, value: null, inherit: false });
    assert.equal(ok(BOOK, { value: 3650 }).value, 3650);
    bad(BOOK, { value: 100 }, 'RULE_VALUE_INVALID');
    const days = RULES['retention.door_logs_days'];
    bad(days, { value: null }, 'RULE_VALUE_INVALID');
    assert.equal(ok(RULES['heat.measured_share_pct'], { value: 100 }).value, 100);
  });

  it('kilitli kural (otomatik silme) hiçbir değerle değiştirilemez', () => {
    bad(ENFORCE, { value: true }, 'RULE_LOCKED');
    bad(ENFORCE, { value: false }, 'RULE_LOCKED');
    bad(ENFORCE, { inherit: true }, 'RULE_LOCKED');
  });

  it('site kapsamı yalnız sitede değişebilen kuralda; ileri tarih yalnız planlanabilen kuralda', () => {
    assert.equal(ok(FORECAST, { value: 2500 }, { siteScoped: true }).value, 2500);
    bad(LATE, { value: 400 }, 'RULE_NOT_SITE_OVERRIDABLE', { siteScoped: true });
    bad(RULES['retention.finance_days'], { value: 3650 }, 'RULE_NOT_SITE_OVERRIDABLE', { siteScoped: true });
    bad(LATE, { value: 400 }, 'RULE_NOT_SCHEDULABLE', { future: true });
    assert.equal(ok(RULES['budget.objection_days'], { value: 10 }, { future: true }).value, 10);
  });

  it('inherit (üst düzeye dön): yalnız true ve değer OLMADAN', () => {
    assert.deepEqual(ok(FORECAST, { inherit: true }, { siteScoped: true }), { ok: true, value: null, inherit: true });
    assert.deepEqual(ok(LATE, { inherit: true }), { ok: true, value: null, inherit: true });
    bad(FORECAST, { inherit: true, value: 100 }, 'RULE_VALUE_INVALID', { siteScoped: true });
    bad(FORECAST, { inherit: false }, 'RULE_VALUE_INVALID', { siteScoped: true });
    bad(FORECAST, { inherit: 'evet' }, 'RULE_VALUE_INVALID', { siteScoped: true });
  });
});

describe('getRule: tek sorgu, kısa önbellek, yazma sonrası geçersiz', () => {
  const norm = (text) => String(text).replace(/\s+/g, ' ').trim();
  let clock;
  beforeEach(() => {
    invalidateRuleCache();
    clock = 1_000_000;
    ruleCacheTuning.clock = () => clock;
    ruleCacheTuning.ttlMs = 30_000;
  });
  const fakeDb = (rowsByKey = {}) => {
    const calls = [];
    return {
      calls,
      async query(text, params) {
        calls.push({ sql: norm(text), params });
        const [key, site] = params;
        const rows = (rowsByKey[key] ?? []).filter((r) => r.site_code === null || (site !== null && Number(r.site_code) === site));
        return { rows };
      },
    };
  };

  it('sorgu: yalnız o anahtarın platform + (verildiyse) site satırları, parametreli; varsayılan bugün (İstanbul)', async () => {
    const db = fakeDb({ 'finance.late_fee.monthly_bp_max': [row(400, '2026-01-01')] });
    assert.equal(await getRule(db, 'finance.late_fee.monthly_bp_max'), 400);
    assert.equal(db.calls.length, 1);
    assert.equal(db.calls[0].sql, norm(RULE_ROWS_SQL));
    assert.match(db.calls[0].sql, /FROM platform_rule_values WHERE rule_key = \$1 AND \(site_code IS NULL OR site_code = \$2\)/);
    assert.deepEqual(db.calls[0].params, ['finance.late_fee.monthly_bp_max', null], 'sitede değişemeyen kuralda site satırları istenmez');
  });

  it('ikinci çağrı DB\'ye gitmez (aynı anahtar ve site); farklı tarih aynı önbellekten çözülür; TTL dolunca yeniden okunur', async () => {
    const db = fakeDb({ 'budget.objection_days': [row(10, '2026-01-01'), row(14, '2027-01-01')] });
    assert.equal(await getRule(db, 'budget.objection_days', { onDate: '2026-10-21' }), 10);
    assert.equal(await getRule(db, 'budget.objection_days', { onDate: '2027-02-01' }), 14);
    assert.equal(db.calls.length, 1);
    clock += 29_999;
    await getRule(db, 'budget.objection_days', { onDate: '2026-10-21' });
    assert.equal(db.calls.length, 1, 'TTL dolmadı');
    clock += 2;
    await getRule(db, 'budget.objection_days', { onDate: '2026-10-21' });
    assert.equal(db.calls.length, 2, 'TTL doldu: yeniden okundu');
  });

  it('site kapsamı ayrı önbellek girdisi; site kodu sitede değişebilen kuralda parametre olur', async () => {
    const db = fakeDb({ 'forecast.default_increase_bp': [row(500, '2026-01-01'), row(1500, '2026-02-01', { site: SITE })] });
    assert.equal(await getRule(db, 'forecast.default_increase_bp', { onDate: '2026-10-21' }), 500);
    assert.equal(await getRule(db, 'forecast.default_increase_bp', { siteCode: SITE, onDate: '2026-10-21' }), 1500);
    assert.equal(await getRule(db, 'forecast.default_increase_bp', { siteCode: String(SITE), onDate: '2026-10-21' }), 1500, 'metin site kodu aynı girdi');
    assert.deepEqual(db.calls.map((c) => c.params), [['forecast.default_increase_bp', null], ['forecast.default_increase_bp', SITE]]);
    assert.equal(ruleCacheSize(), 2);
  });

  it('invalidateRuleCache sonrası DB\'den okunur; fresh: true önbelleği atlar', async () => {
    const data = { 'finance.late_fee.monthly_bp_max': [row(400, '2026-01-01')] };
    const db = fakeDb(data);
    assert.equal(await getRule(db, 'finance.late_fee.monthly_bp_max', { onDate: '2026-10-21' }), 400);
    data['finance.late_fee.monthly_bp_max'].push(row(300, '2026-10-21'));
    assert.equal(await getRule(db, 'finance.late_fee.monthly_bp_max', { onDate: '2026-10-21' }), 400, 'önbellekten (eski)');
    invalidateRuleCache();
    assert.equal(ruleCacheSize(), 0);
    assert.equal(await getRule(db, 'finance.late_fee.monthly_bp_max', { onDate: '2026-10-21' }), 300);
    data['finance.late_fee.monthly_bp_max'].push(row(200, '2026-10-21'));
    assert.equal(await getRule(db, 'finance.late_fee.monthly_bp_max', { onDate: '2026-10-21', fresh: true }), 200);
    assert.equal(db.calls.length, 3);
  });

  it('nesil yarışı: okuma sürerken önbellek boşaltılırsa eski satırlar önbelleğe GERİ KONMAZ', async () => {
    let release;
    const gate = new Promise((resolve) => {
      release = resolve;
    });
    const db = {
      calls: 0,
      async query() {
        this.calls += 1;
        if (this.calls === 1) await gate;
        return { rows: [row(this.calls === 1 ? 450 : 350, '2026-01-01')] };
      },
    };
    const pending = getRule(db, 'finance.late_fee.monthly_bp_max', { onDate: '2026-10-21' });
    invalidateRuleCache();
    release();
    assert.equal(await pending, 450, 'yarıştaki çağrı kendi okumasını döndürür');
    assert.equal(ruleCacheSize(), 0, 'ama önbelleğe yazmaz');
    assert.equal(await getRule(db, 'finance.late_fee.monthly_bp_max', { onDate: '2026-10-21' }), 350);
  });

  it('önbellek üst sınırı aşılınca temizlenir (bellek sınırsız büyümez); bilinmeyen anahtar programlama hatasıdır; DB satırı sınır dışıysa kırpılır', async () => {
    const db = fakeDb({ 'finance.late_fee.monthly_bp_max': [row(9000, '2026-01-01')] });
    assert.equal(await getRule(db, 'finance.late_fee.monthly_bp_max', { onDate: '2026-10-21' }), 500, '9000 -> yasal sınır 500');
    const saved = ruleCacheTuning.maxEntries;
    ruleCacheTuning.maxEntries = 2;
    try {
      for (let site = 1; site <= 3; site += 1) await getRule(fakeDb(), 'forecast.default_increase_bp', { siteCode: site, onDate: '2026-10-21' });
      assert.ok(ruleCacheSize() <= 2);
    } finally {
      ruleCacheTuning.maxEntries = saved;
    }
    await assert.rejects(getRule(db, 'yok.boyle'), /bilinmeyen kural/);
  });
});
