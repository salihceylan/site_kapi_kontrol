// Gecikme tazminatı oran üst sınırı kurallar tablosundan (G11; docs/PLATFORM_KURALLAR.md): etkin üst sınır = min(kural, yasal 500).
// Ayar yazımı kural üstü oranı reddeder (400); GET yanıtında max_rate_bp kuraldır ve oran sınıra kırpılır; tazminat AÇIKKEN loadEffectiveSettings oranı
// kırpar (hesap ve önizleme özeti kırpılmış oranla yapılır), KAPALIYKEN kural sorgusu yapılmaz (ödeme yolunda ek sorgu yok).
// Gerçek PostgreSQL: scripts/qa_platform_pg.mjs "platform_rules" (gecikme üst sınırı bölümü).
import { describe, it, before, after, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { pool } from '../src/db.js';
import { LATE_FEE_MAX_MONTHLY_BP } from '../src/modules/finance_4b_common.js';
import {
  LATE_FEE_MAX_RULE_KEY,
  SETTINGS_DEFAULTS,
  getSettings,
  lateFeeMaxRateBp,
  loadEffectiveSettings,
  settingsBody,
  updateSettings,
} from '../src/modules/finance_settings.js';
import { invalidateRuleCache } from '../src/modules/platform_rules.js';

const here = path.dirname(fileURLToPath(import.meta.url));
const SITE = 1000000001;
const NOW = new Date('2026-10-21T09:00:00Z');
const norm = (text) => String(text).replace(/\s+/g, ' ').trim();
const settingsRow = (overrides = {}) => ({
  receipts_auto_issue: true,
  late_fee_enabled: false,
  late_fee_rate_bp: 500,
  late_fee_method: 'daily_30',
  late_fee_grace_days: 0,
  late_fee_start_period: null,
  reminders_enabled: false,
  reminder_min_overdue_minor: '5000',
  reminder_min_days_overdue: 5,
  reminder_min_interval_days: 14,
  reminder_max_consecutive: 3,
  settings_version: 1,
  ...overrides,
});
const ruleRow = (value, validFrom = '2026-01-01', id = 1) => ({ id: String(id), site_code: null, value, inherit: false, valid_from: validFrom });

/** Katı sahte DB: tanınmayan SQL hata verir; çağrılar günlüğe yazılır. */
function fakeDb({ settings = null, rules = [], legalOk = true } = {}) {
  const log = [];
  const state = { settings: settings ? { ...settings } : null };
  const query = async (text, params = []) => {
    const sql = norm(text);
    log.push(sql);
    if (/^SELECT receipts_auto_issue, .* FROM finance_settings WHERE site_code = \$1( FOR UPDATE)?$/.test(sql)) return { rows: state.settings ? [state.settings] : [] };
    if (/FROM platform_rule_values WHERE rule_key = \$1/.test(sql)) {
      assert.equal(params[0], LATE_FEE_MAX_RULE_KEY);
      return { rows: rules };
    }
    if (/^SELECT id, to_char\(period, 'YYYY-MM-DD'\) AS period FROM late_fee_runs/.test(sql)) return { rows: [] };
    if (/^SELECT value FROM platform_settings WHERE key = \$1$/.test(sql)) return { rows: [{ value: legalOk }] };
    if (/^(BEGIN|COMMIT|ROLLBACK)$/.test(sql) || /^(SAVEPOINT|RELEASE SAVEPOINT|ROLLBACK TO SAVEPOINT) /.test(sql)) return { rows: [] };
    if (/^SELECT site_code FROM sites WHERE site_code = \$1 FOR KEY SHARE$/.test(sql)) return { rows: [{ site_code: String(SITE) }] };
    if (/^SELECT pg_advisory_xact_lock\(hashtext\(\$1\)\)$/.test(sql)) return { rows: [] };
    if (/^SELECT enabled FROM site_modules WHERE site_code = \$1 AND module_code = \$2 LIMIT 1$/.test(sql)) return { rows: [{ enabled: true }] };
    if (/^SELECT user_code FROM users WHERE user_code = \$1 AND deleted_at IS NULL FOR KEY SHARE$/.test(sql)) return { rows: [{ user_code: params[0] }] };
    if (/^INSERT INTO finance_settings \(site_code\) VALUES \(\$1\) ON CONFLICT \(site_code\) DO NOTHING$/.test(sql)) {
      state.settings ??= settingsRow();
      return { rows: [] };
    }
    if (/^UPDATE finance_settings SET /.test(sql)) {
      const columns = [...sql.matchAll(/(\w+) = \$(\d+)/g)].filter(([, column]) => !['site_code', 'settings_version', 'updated_by'].includes(column));
      for (const [, column, index] of columns) state.settings[column] = /^late_fee_rate_bp|grace|min_|max_/.test(column) && params[Number(index) - 1] !== null ? Number(params[Number(index) - 1]) : params[Number(index) - 1];
      state.settings.settings_version += 1;
      return { rows: [{ settings_version: state.settings.settings_version }] };
    }
    if (/^INSERT INTO audit_log/.test(sql)) return { rows: [] };
    throw new Error(`BEKLENMEYEN SQL (sahte DB katı): ${sql.slice(0, 160)}`);
  };
  return { log, state, query, connect: async () => ({ query, release() {} }) };
}

const ruleQueries = (log) => log.filter((sql) => /platform_rule_values/.test(sql)).length;

beforeEach(() => invalidateRuleCache());

describe('gecikme üst sınırı: kural + yasal sınır', () => {
  it('anahtar sözleşmedeki kural; kural satırı yoksa 500 (varsayılan = yasal sınır)', async () => {
    assert.equal(LATE_FEE_MAX_RULE_KEY, 'finance.late_fee.monthly_bp_max');
    assert.equal(await lateFeeMaxRateBp(fakeDb(), NOW), 500);
  });

  it('kural 400 -> 400; kural 900 yazılmış olsa bile 500 (yasal sınır aşılamaz); kaynakta ikinci kırpma da var', async () => {
    assert.equal(await lateFeeMaxRateBp(fakeDb({ rules: [ruleRow(400)] }), NOW), 400);
    invalidateRuleCache();
    assert.equal(await lateFeeMaxRateBp(fakeDb({ rules: [ruleRow(900)] }), NOW), 500);
    const source = readFileSync(path.join(here, '..', 'src', 'modules', 'finance_settings.js'), 'utf8');
    assert.match(source, /Math\.min\(await getRule\(db, LATE_FEE_MAX_RULE_KEY, \{ onDate: todayIso\(now\) \}\), LATE_FEE_MAX_MONTHLY_BP\)/);
    assert.equal(LATE_FEE_MAX_MONTHLY_BP, 500);
  });

  it('ileri tarihli satır bugünü etkilemez (tarih İstanbul bugünü)', async () => {
    const db = fakeDb({ rules: [ruleRow(300, '2026-10-22')] });
    assert.equal(await lateFeeMaxRateBp(db, NOW), 500);
  });
});

describe('settingsBody: max_rate_bp kuraldan, oran sınıra kırpılır', () => {
  it('maxRateBp verilmezse eski davranış (500); verilirse hem sınır hem gösterilen oran', () => {
    const chain = { nextPeriod: null, lastRunId: null };
    assert.equal(settingsBody(SETTINGS_DEFAULTS, chain, { legalOk: false, smtpConfigured: false }).late_fee.max_rate_bp, 500);
    const body = settingsBody({ ...SETTINGS_DEFAULTS, late_fee_rate_bp: 500 }, chain, { legalOk: true, smtpConfigured: true, maxRateBp: 400 });
    assert.equal(body.late_fee.max_rate_bp, 400);
    assert.equal(body.late_fee.rate_bp, 400);
    assert.equal(settingsBody({ ...SETTINGS_DEFAULTS, late_fee_rate_bp: 250 }, chain, { legalOk: true, smtpConfigured: true, maxRateBp: 400 }).late_fee.rate_bp, 250);
  });
});

describe('loadEffectiveSettings: tazminat açıkken kırpar, kapalıyken kural sorgusu yok', () => {
  it('açık + kural 300: oran 300 (hesap kırpılmış oranla yapılır)', async () => {
    const db = fakeDb({ settings: settingsRow({ late_fee_enabled: true, late_fee_start_period: '2026-09-01', late_fee_rate_bp: 500 }), rules: [ruleRow(300)] });
    const settings = await loadEffectiveSettings(db, SITE);
    assert.equal(settings.late_fee_rate_bp, 300);
    assert.equal(ruleQueries(db.log), 1);
  });

  it('açık + kural oranın üstünde: oran değişmez', async () => {
    const db = fakeDb({ settings: settingsRow({ late_fee_enabled: true, late_fee_start_period: '2026-09-01', late_fee_rate_bp: 250 }), rules: [ruleRow(400)] });
    assert.equal((await loadEffectiveSettings(db, SITE)).late_fee_rate_bp, 250);
  });

  it('kapalı (ya da satır yok): kural sorgusu YAPILMAZ, oran saklandığı gibi; varsayılan nesnesi değişmez (donmuş)', async () => {
    const off = fakeDb({ settings: settingsRow({ late_fee_rate_bp: 500 }), rules: [ruleRow(100)] });
    assert.equal((await loadEffectiveSettings(off, SITE)).late_fee_rate_bp, 500);
    assert.equal(ruleQueries(off.log), 0);
    const none = fakeDb({ rules: [ruleRow(100)] });
    const defaults = await loadEffectiveSettings(none, SITE);
    assert.equal(defaults.late_fee_rate_bp, 500);
    assert.equal(ruleQueries(none.log), 0);
    assert.equal(SETTINGS_DEFAULTS.late_fee_rate_bp, 500);
  });
});

describe('getSettings / updateSettings', () => {
  const MANAGER = { id: 20001, user_code: 20001, userCode: 20001, role: 'site_manager', full_name: 'Ayşe Yönetici' };
  let db;
  before(() => {
    pool.query = (text, params) => db.query(text, params);
    pool.connect = () => db.connect();
  });
  after(() => {
    delete pool.query;
    delete pool.connect;
  });

  it('GET: max_rate_bp kural değeri; saklanan 500 oran 400 olarak görünür (tazminat kapalıyken de)', async () => {
    db = fakeDb({ settings: settingsRow({ late_fee_rate_bp: 500 }), rules: [ruleRow(400)] });
    const body = await getSettings(SITE, db);
    assert.equal(body.late_fee.max_rate_bp, 400);
    assert.equal(body.late_fee.rate_bp, 400);
  });

  it('PUT: kural üstü oran 400 INVALID_BODY (yazılmaz); sınırdaki oran yazılır ve yanıt kural sınırını taşır', async () => {
    db = fakeDb({ settings: settingsRow({ late_fee_rate_bp: 300 }), rules: [ruleRow(400)] });
    await assert.rejects(
      updateSettings({ siteCode: SITE, body: { expected_settings_version: 1, late_fee: { rate_bp: 450 } }, actor: MANAGER, now: NOW }),
      (error) => error.statusCode === 400 && error.code === 'INVALID_BODY' && /0 ile 400/.test(error.message),
    );
    assert.equal(db.state.settings.late_fee_rate_bp, 300);
    assert.equal(db.log.some((sql) => /^UPDATE finance_settings/.test(sql)), false);
    const body = await updateSettings({ siteCode: SITE, body: { expected_settings_version: 1, late_fee: { rate_bp: 400 } }, actor: MANAGER, now: NOW });
    assert.equal(db.state.settings.late_fee_rate_bp, 400);
    assert.equal(body.late_fee.rate_bp, 400);
    assert.equal(body.late_fee.max_rate_bp, 400);
  });

  it('PUT: oran DEĞİŞMİYORSA (yalnız başka alan) kural üstü saklı oran işlemi engellemez; yasal 500 sınırı ayrıştırmada kalır', async () => {
    db = fakeDb({ settings: settingsRow({ late_fee_rate_bp: 500 }), rules: [ruleRow(400)] });
    const body = await updateSettings({ siteCode: SITE, body: { expected_settings_version: 1, receipts: { auto_issue: false } }, actor: MANAGER, now: NOW });
    assert.equal(body.receipts.auto_issue, false);
    assert.equal(body.late_fee.rate_bp, 400, 'gösterim kırpılmış');
    await assert.rejects(
      updateSettings({ siteCode: SITE, body: { expected_settings_version: 2, late_fee: { rate_bp: 501 } }, actor: MANAGER, now: NOW }),
      (error) => error.statusCode === 400 && /0 ile 500/.test(error.message),
    );
  });
});
