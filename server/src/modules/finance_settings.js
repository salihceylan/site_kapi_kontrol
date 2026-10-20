// Finans Faz 4b ayarları (makbuz otomatik düzenleme, gecikme tazminatı, borç hatırlatma eşikleri) ve sistem düzeyindeki hukuk onayı bayrağı.
//
// Sözleşme: docs/PLATFORM_FINANS_4B.md "Ayarlar ucu". Satır tembel oluşur (okuma satır yoksa varsayılanları döner). Yazma `expected_settings_version` ister
// (uyuşmazlık 409 SETTINGS_STALE); her UPDATE sürümü bir artırır (DB tetikleyicisi). Audit yalnız DEĞİŞEN anahtar adlarını yazar, değerleri değil.
// KOORDİNATÖR KARARI (Q2): gecikme tazminatı ve borç hatırlatma site ayarında VARSAYILAN KAPALI ve ayrıca sistem düzeyinde
// `platform_settings` anahtarı `finance.legal_ok` (varsayılan kapalı) bayrağına bağlıdır: bayrak kapalıyken AÇILAMAZ.

import { pool } from '../db.js';
import { isSmtpConfigured } from '../mailer.js';
import { actorFromAuthUser } from './audit_service.js';
import {
  LATE_FEE_MAX_MONTHLY_BP,
  hasOwn,
  lateFeeAlreadyPosted,
  legalApprovalRequired,
  objectOf,
  present,
  settingsStale,
} from './finance_4b_common.js';
import {
  addMonths,
  assertPeriodNotTooOld,
  currentPeriod,
  invalidBody,
  parsePeriod,
  periodLabel,
} from './finance_common.js';
import { lockActorRow, recordFinanceAudit, withFinanceTransaction } from './finance_tx.js';
import { todayIso } from './people_common.js';
import { parseFlag } from './platform_config_service.js';
import { getRule } from './platform_rules.js';

export const LEGAL_OK_KEY = 'finance.legal_ok';

/**
 * Kurallar tablosu (G11; docs/PLATFORM_KURALLAR.md): aylık oran üst sınırı bu kuraldan okunur. Etkin üst sınır = min(kural, LATE_FEE_MAX_MONTHLY_BP):
 * kural kendi sınırına (0..500) zaten kırpılır, yasal sınır (KMK m.20, 500 bp) burada da korunur.
 */
export const LATE_FEE_MAX_RULE_KEY = 'finance.late_fee.monthly_bp_max';

/** Bugünün (İstanbul) etkin oran üst sınırı (baz puan). `db`: havuz ya da işlem istemcisi (kural satırları kısa önbellekte). */
export async function lateFeeMaxRateBp(db = pool, now = new Date()) {
  return Math.min(await getRule(db, LATE_FEE_MAX_RULE_KEY, { onDate: todayIso(now) }), LATE_FEE_MAX_MONTHLY_BP);
}
export const LATE_FEE_METHODS = Object.freeze(['daily_30', 'daily_actual']);

/** Satır yokken dönen varsayılanlar (sütun varsayılanlarıyla aynı). */
export const SETTINGS_DEFAULTS = Object.freeze({
  receipts_auto_issue: true,
  late_fee_enabled: false,
  late_fee_rate_bp: LATE_FEE_MAX_MONTHLY_BP,
  late_fee_method: 'daily_30',
  late_fee_grace_days: 0,
  late_fee_start_period: null,
  reminders_enabled: false,
  reminder_min_overdue_minor: 5000,
  reminder_min_days_overdue: 5,
  reminder_min_interval_days: 14,
  reminder_max_consecutive: 3,
  settings_version: 1,
});

const SETTINGS_COLUMNS = `
  receipts_auto_issue, late_fee_enabled, late_fee_rate_bp, late_fee_method, late_fee_grace_days,
  to_char(late_fee_start_period, 'YYYY-MM-DD') AS late_fee_start_period,
  reminders_enabled, reminder_min_overdue_minor::TEXT AS reminder_min_overdue_minor, reminder_min_days_overdue,
  reminder_min_interval_days, reminder_max_consecutive, settings_version
`;

function normalizeRow(row) {
  return {
    receipts_auto_issue: row.receipts_auto_issue === true,
    late_fee_enabled: row.late_fee_enabled === true,
    late_fee_rate_bp: Number(row.late_fee_rate_bp),
    late_fee_method: row.late_fee_method,
    late_fee_grace_days: Number(row.late_fee_grace_days),
    late_fee_start_period: row.late_fee_start_period ?? null,
    reminders_enabled: row.reminders_enabled === true,
    reminder_min_overdue_minor: Number(row.reminder_min_overdue_minor),
    reminder_min_days_overdue: Number(row.reminder_min_days_overdue),
    reminder_min_interval_days: Number(row.reminder_min_interval_days),
    reminder_max_consecutive: Number(row.reminder_max_consecutive),
    settings_version: Number(row.settings_version),
  };
}

/**
 * Etkin ayarlar (satır yoksa varsayılanlar). Gecikme tazminatı AÇIKKEN aylık oran kurallar tablosundaki üst sınıra kırpılır (önizleme, onay ve özet
 * kırpılmış oranla yapılır); KAPALIYKEN oran hiçbir hesaba girmediğinden kural okunmaz (ödeme / hatırlatma yolunda ek sorgu yok).
 */
export async function loadEffectiveSettings(db, siteCode) {
  const result = await db.query(`SELECT ${SETTINGS_COLUMNS} FROM finance_settings WHERE site_code = $1`, [siteCode]);
  const row = result.rows?.[0];
  const settings = row ? normalizeRow(row) : { ...SETTINGS_DEFAULTS };
  if (settings.late_fee_enabled) {
    settings.late_fee_rate_bp = Math.min(settings.late_fee_rate_bp, await lateFeeMaxRateBp(db));
  }
  return settings;
}

/** Sistem düzeyi hukuk onayı bayrağı (platform_settings finance.legal_ok); satır yok/geçersiz = KAPALI. */
export async function readLegalOk(db = pool) {
  const result = await db.query(`SELECT value FROM platform_settings WHERE key = $1`, [LEGAL_OK_KEY]);
  return parseFlag(result.rows?.[0]?.value);
}

/** Son aktif tazminat çalıştırması (varsa) ve sıradaki dönem. */
export async function loadLateFeeChainState(db, siteCode, settings) {
  const result = await db.query(
    `SELECT id, to_char(period, 'YYYY-MM-DD') AS period FROM late_fee_runs WHERE site_code = $1 AND status = 'active' ORDER BY period DESC LIMIT 1`,
    [siteCode],
  );
  const last = result.rows?.[0] ?? null;
  const nextPeriod = last ? addMonths(last.period, 1) : settings.late_fee_start_period;
  return { lastRunId: last ? Number(last.id) : null, lastPeriod: last?.period ?? null, nextPeriod: nextPeriod ?? null };
}

const label = (periodIso) => (periodIso === null || periodIso === undefined ? null : periodLabel(periodIso));

/** GET settings gövdesi. `maxRateBp`: etkin oran üst sınırı (kurallar tablosu; verilmezse yasal sınır); gösterilen oran bu sınıra kırpılır. */
export function settingsBody(settings, chain, { legalOk, smtpConfigured, maxRateBp = LATE_FEE_MAX_MONTHLY_BP }) {
  return {
    settings_version: settings.settings_version,
    legal_ok: legalOk,
    receipts: { auto_issue: settings.receipts_auto_issue },
    late_fee: {
      enabled: settings.late_fee_enabled,
      rate_bp: Math.min(settings.late_fee_rate_bp, maxRateBp),
      max_rate_bp: maxRateBp,
      method: settings.late_fee_method,
      grace_days: settings.late_fee_grace_days,
      start_period: label(settings.late_fee_start_period),
      next_period: label(chain.nextPeriod),
      voidable_run_id: chain.lastRunId,
    },
    reminders: {
      enabled: settings.reminders_enabled,
      min_overdue_minor: settings.reminder_min_overdue_minor,
      min_days_overdue: settings.reminder_min_days_overdue,
      min_interval_days: settings.reminder_min_interval_days,
      max_consecutive: settings.reminder_max_consecutive,
      smtp_configured: smtpConfigured,
    },
  };
}

export async function getSettings(siteCode, db = pool) {
  const settings = await loadEffectiveSettings(db, siteCode);
  const chain = await loadLateFeeChainState(db, siteCode, settings);
  const maxRateBp = await lateFeeMaxRateBp(db);
  return settingsBody(settings, chain, { legalOk: await readLegalOk(db), smtpConfigured: isSmtpConfigured(), maxRateBp });
}

// --- PUT ---------------------------------------------------------------------------------------------------------------------------------

const ROOT_KEYS = ['expected_settings_version', 'receipts', 'late_fee', 'reminders'];
const GROUP_KEYS = {
  receipts: ['auto_issue'],
  late_fee: ['enabled', 'rate_bp', 'method', 'grace_days', 'start_period'],
  reminders: ['enabled', 'min_overdue_minor', 'min_days_overdue', 'min_interval_days', 'max_consecutive'],
};

function boundedInt(value, label, min, max) {
  if (typeof value !== 'number' || !Number.isInteger(value) || value < min || value > max) {
    throw invalidBody(`${label} ${min} ile ${max} arasında bir tamsayı olmalıdır.`);
  }
  return value;
}

function boolean(value, label) {
  if (typeof value !== 'boolean') {
    throw invalidBody(`${label} geçersiz (evet veya hayır olmalıdır).`);
  }
  return value;
}

/** PUT gövdesi -> { expectedVersion, changes: { sütun: değer }, names: ['grup.alan'] }. */
export function parseSettingsPatch(body, now = new Date()) {
  const input = objectOf(body);
  for (const key of Object.keys(input)) {
    if (!ROOT_KEYS.includes(key)) {
      throw invalidBody('Bilinmeyen ayar alanı.');
    }
  }
  const expectedVersion = input.expected_settings_version;
  if (typeof expectedVersion !== 'number' || !Number.isInteger(expectedVersion) || expectedVersion < 1) {
    throw invalidBody('Ayar sürümü (expected_settings_version) zorunludur; ayarları yenileyin.');
  }
  const changes = {};
  const names = [];
  const take = (group, key, column, value) => {
    changes[column] = value;
    names.push(`${group}.${key}`);
  };
  for (const group of ['receipts', 'late_fee', 'reminders']) {
    if (!hasOwn(input, group)) {
      continue;
    }
    const part = input[group];
    if (!part || typeof part !== 'object' || Array.isArray(part)) {
      throw invalidBody('Ayar grubu geçersiz.');
    }
    for (const key of Object.keys(part)) {
      if (!GROUP_KEYS[group].includes(key)) {
        throw invalidBody('Bilinmeyen ayar alanı.');
      }
    }
    if (group === 'receipts' && hasOwn(part, 'auto_issue')) {
      take(group, 'auto_issue', 'receipts_auto_issue', boolean(part.auto_issue, 'Makbuz otomatik düzenleme'));
    }
    if (group === 'late_fee') {
      if (hasOwn(part, 'enabled')) take(group, 'enabled', 'late_fee_enabled', boolean(part.enabled, 'Gecikme tazminatı'));
      if (hasOwn(part, 'rate_bp')) take(group, 'rate_bp', 'late_fee_rate_bp', boundedInt(part.rate_bp, 'Aylık oran (baz puan)', 0, LATE_FEE_MAX_MONTHLY_BP));
      if (hasOwn(part, 'method')) {
        if (!LATE_FEE_METHODS.includes(part.method)) {
          throw invalidBody('Gün esası geçersiz (günlük/30 ya da gerçek gün).');
        }
        take(group, 'method', 'late_fee_method', part.method);
      }
      if (hasOwn(part, 'grace_days')) take(group, 'grace_days', 'late_fee_grace_days', boundedInt(part.grace_days, 'Ek gün', 0, 90));
      if (hasOwn(part, 'start_period')) {
        const period = parsePeriod(part.start_period, 'Başlangıç ayı');
        assertPeriodNotTooOld(period, 'Başlangıç ayı', now);
        if (period > addMonths(currentPeriod(now), 12)) {
          throw invalidBody('Başlangıç ayı en fazla 12 ay ileride olabilir.');
        }
        take(group, 'start_period', 'late_fee_start_period', period);
      }
    }
    if (group === 'reminders') {
      if (hasOwn(part, 'enabled')) take(group, 'enabled', 'reminders_enabled', boolean(part.enabled, 'Borç hatırlatma'));
      if (hasOwn(part, 'min_overdue_minor'))
        take(group, 'min_overdue_minor', 'reminder_min_overdue_minor', boundedInt(part.min_overdue_minor, 'En düşük borç (kuruş)', 100, 1000000000000));
      if (hasOwn(part, 'min_days_overdue')) take(group, 'min_days_overdue', 'reminder_min_days_overdue', boundedInt(part.min_days_overdue, 'En az gecikme günü', 1, 120));
      if (hasOwn(part, 'min_interval_days'))
        take(group, 'min_interval_days', 'reminder_min_interval_days', boundedInt(part.min_interval_days, 'Hatırlatmalar arası gün', 7, 90));
      if (hasOwn(part, 'max_consecutive')) take(group, 'max_consecutive', 'reminder_max_consecutive', boundedInt(part.max_consecutive, 'Ardışık hatırlatma sınırı', 1, 6));
    }
  }
  if (names.length === 0) {
    throw invalidBody('Güncellenecek bir ayar gönderilmedi.');
  }
  return { expectedVersion, changes, keys: names };
}

/** PUT settings -> güncel GET gövdesi. */
export async function updateSettings({ siteCode, body, actor, now = new Date() }) {
  const input = parseSettingsPatch(body, now);
  const actorInfo = actorFromAuthUser(actor);
  return withFinanceTransaction(siteCode, async (client) => {
    await lockActorRow(client, actorInfo);
    await client.query(`INSERT INTO finance_settings (site_code) VALUES ($1) ON CONFLICT (site_code) DO NOTHING`, [siteCode]);
    const current = normalizeRow((await client.query(`SELECT ${SETTINGS_COLUMNS} FROM finance_settings WHERE site_code = $1 FOR UPDATE`, [siteCode])).rows[0]);
    if (current.settings_version !== input.expectedVersion) {
      throw settingsStale({ settings_version: current.settings_version });
    }
    const next = { ...current, ...input.changes };
    const legalOk = await readLegalOk(client);
    // Hukuk onayı bayrağı kapalıyken tazminat / hatırlatma AÇILAMAZ (kapalıdan açığa geçiş).
    if (!legalOk && ((next.late_fee_enabled && !current.late_fee_enabled) || (next.reminders_enabled && !current.reminders_enabled))) {
      throw legalApprovalRequired();
    }
    if (next.late_fee_enabled && next.late_fee_start_period === null) {
      throw invalidBody('Gecikme tazminatını açmak için başlangıç ayını girin.');
    }
    // Oran üst sınırı kurallar tablosundan (yasal 500 ayrıştırmada ve DB CHECK'inde de korunur). Yalnız GÖNDERİLEN oran denetlenir: sınır sonradan
    // düşürüldüyse saklı yüksek oran başka alanların kaydını engellemez; hesapta zaten sınıra kırpılır (loadEffectiveSettings).
    const maxRateBp = await lateFeeMaxRateBp(client, now);
    if (hasOwn(input.changes, 'late_fee_rate_bp') && input.changes.late_fee_rate_bp > maxRateBp) {
      throw invalidBody(`Aylık oran (baz puan) 0 ile ${maxRateBp} arasında bir tamsayı olmalıdır.`);
    }
    if (hasOwn(input.changes, 'late_fee_start_period') && input.changes.late_fee_start_period !== current.late_fee_start_period) {
      const chain = await loadLateFeeChainState(client, siteCode, current);
      if (chain.lastRunId !== null) {
        throw lateFeeAlreadyPosted();
      }
    }
    const columns = Object.keys(input.changes);
    const setSql = columns.map((column, index) => `${column} = $${index + 3}${column === 'late_fee_start_period' ? '::DATE' : ''}`).join(', ');
    const values = columns.map((column) => (present(input.changes[column]) ? input.changes[column] : null));
    const updated = await client.query(
      `
        UPDATE finance_settings
        SET ${setSql}, settings_version = settings_version + 1, updated_by = $${columns.length + 3}, updated_at = NOW()
        WHERE site_code = $1 AND settings_version = $2
        RETURNING settings_version
      `,
      [siteCode, input.expectedVersion, ...values.map((v) => (typeof v === 'number' ? String(v) : v)), actorInfo.userCode],
    );
    if (!updated.rows?.[0]) {
      throw settingsStale();
    }
    await recordFinanceAudit(client, actor, 'finance.settings.updated', siteCode, siteCode, { fields: input.keys });
    const settings = await loadEffectiveSettings(client, siteCode);
    const chain = await loadLateFeeChainState(client, siteCode, settings);
    return settingsBody(settings, chain, { legalOk, smtpConfigured: isSmtpConfigured(), maxRateBp });
  });
}

/** Süper kullanıcı: sistem düzeyi hukuk onayı bayrağını yazar (audit: finance.legal_gate.updated, yalnız açık/kapalı). */
export async function setLegalGate({ enabled, actor }) {
  if (typeof enabled !== 'boolean') {
    throw invalidBody('Hukuk onayı değeri geçersiz (evet veya hayır olmalıdır).');
  }
  const actorInfo = actorFromAuthUser(actor);
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    if (actorInfo.userCode !== null) {
      await client.query('SELECT user_code FROM users WHERE user_code = $1 AND deleted_at IS NULL FOR KEY SHARE', [actorInfo.userCode]);
    }
    await client.query(
      `
        INSERT INTO platform_settings (key, value, updated_at, updated_by)
        VALUES ($1, $2::JSONB, NOW(), $3)
        ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, updated_at = NOW(), updated_by = EXCLUDED.updated_by
      `,
      [LEGAL_OK_KEY, JSON.stringify(enabled), actorInfo.userCode],
    );
    await recordFinanceAudit(client, actor, 'finance.legal_gate.updated', 0, LEGAL_OK_KEY, { enabled });
    await client.query('COMMIT');
    return { legal_ok: enabled };
  } catch (error) {
    await client.query('ROLLBACK').catch(() => {});
    throw error;
  } finally {
    client.release();
  }
}
