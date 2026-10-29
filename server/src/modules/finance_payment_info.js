// Ödeme bilgisi servisi (054; Dalga 2 / 2A): site kısa kodu (önek), kalıcı daire kodları, banka hesabı IBAN + alıcı adı sürümleri, sakine gösterilecek
// ödeme bilgisi. Sözleşme: docs/PLATFORM_FINANS_ODEME.md. Para tutarı DÖNMEZ (sakin ucu tutarsızdır; Öde sayfası /app/my-finance kalemini kullanır).
// Kurallar: IBAN yalnız 'bank' türü hesaba; değişiklik yeni sürüm satırıdır (yalnız eklemeli); denetim kaydı YALNIZ maskeli IBAN taşır; kurul IBAN'ı maskeli görür.

import { pool } from '../db.js';
import { PlatformError } from './errors.js';
import { actorFromAuthUser } from './audit_service.js';
import { accountNotFound, objectOf } from './finance_4b_common.js';
import { invalidBody } from './finance_common.js';
import { formatIban, maskIban, parseTrIban } from './finance_iban.js';
import { aptCode, formatRef, parsePrefix, periodLabel, suggestPrefix } from './finance_payment_ref.js';
import { enabledFinanceSites, loadVisibleAccounts } from './finance_read_service.js';
import { isOnlinePaymentAvailable } from './payment_connection_service.js';
import { lockActorRow, recordFinanceAudit, withFinanceTransaction } from './finance_tx.js';
import { parsePositiveId } from './people_common.js';
import { syncUserPeopleSafe } from './people_sync.js';

/** İstemci bu süre içinde IBAN değiştiyse sakine uyarı gösterir. */
export const CHANGE_WARNING_DAYS = 14;

const prefixTaken = (suggestions) =>
  new PlatformError(409, 'PREFIX_TAKEN', 'Bu önek başka bir sitede kullanılıyor. Başka bir önek seçin.', { suggestions });
const versionConflict = () =>
  new PlatformError(409, 'SETTINGS_VERSION_CONFLICT', 'Ayarlar siz bakarken değişti. Sayfayı yenileyip tekrar deneyin.');

const BANK_ACCOUNTS_SQL = `
  SELECT a.id, a.name, a.is_active, d.iban, d.payee_name, d.created_at
  FROM finance_accounts a
  LEFT JOIN LATERAL (
    SELECT iban, payee_name, created_at FROM finance_account_bank_details WHERE account_id = a.id ORDER BY id DESC LIMIT 1
  ) d ON TRUE
  WHERE a.site_code = $1 AND a.kind = 'bank'
  ORDER BY a.sort_order, a.id
`;

function bankView(row, full) {
  if (!row?.iban) return { iban: null, iban_display: null, payee_name: null, changed_at: null };
  return {
    iban: full ? row.iban : null,
    iban_display: full ? formatIban(row.iban) : maskIban(row.iban),
    payee_name: row.payee_name,
    changed_at: row.created_at ? new Date(row.created_at).toISOString() : null,
  };
}

async function takenPrefixes(db, exceptSiteCode) {
  const result = await db.query(`SELECT prefix FROM finance_site_ref_prefixes WHERE site_code <> $1`, [exceptSiteCode]);
  return new Set((result.rows ?? []).map((row) => row.prefix));
}

async function suggestionsFor(db, siteCode, siteName) {
  const taken = await takenPrefixes(db, siteCode);
  const out = [];
  for (let i = 0; i < 3; i += 1) {
    const next = suggestPrefix(siteName, new Set([...taken, ...out]));
    if (next) out.push(next);
  }
  return out;
}

/** GET payment-settings. `full`: yönetici/süper (IBAN açık); kurul maskeli görür. */
export async function getPaymentSettings(siteCode, { full = false, db = pool, now = new Date() } = {}) {
  const [site, settings, prefixes, accounts] = await Promise.all([
    db.query(`SELECT name FROM sites WHERE site_code = $1`, [siteCode]),
    db.query(`SELECT resident_account_id, notices_enabled, settings_version FROM finance_payment_settings WHERE site_code = $1`, [siteCode]),
    db.query(`SELECT prefix, is_current FROM finance_site_ref_prefixes WHERE site_code = $1 ORDER BY created_at, prefix`, [siteCode]),
    db.query(BANK_ACCOUNTS_SQL, [siteCode]),
  ]);
  const row = settings.rows?.[0] ?? null;
  const current = (prefixes.rows ?? []).find((p) => p.is_current)?.prefix ?? null;
  const aliases = (prefixes.rows ?? []).filter((p) => !p.is_current).map((p) => p.prefix);
  const bankAccounts = (accounts.rows ?? []).map((a) => ({
    id: Number(a.id),
    name: a.name,
    is_active: a.is_active === true,
    ...bankView(a, full),
  }));
  const resident = row?.resident_account_id ? bankAccounts.find((a) => a.id === Number(row.resident_account_id)) : null;
  return {
    prefix: current,
    aliases,
    suggested_prefix: current ? null : (await suggestionsFor(db, siteCode, site.rows?.[0]?.name ?? ''))[0] ?? null,
    resident_account: resident ? { id: resident.id, name: resident.name, iban_display: resident.iban_display, payee_name: resident.payee_name, changed_at: resident.changed_at } : null,
    bank_accounts: bankAccounts,
    notices_enabled: row?.notices_enabled === true,
    settings_version: row ? Number(row.settings_version) : 1,
    sample_reference: current ? formatRef({ prefix: current, code: 'A2', now }) : null,
  };
}

function parseSettingsBody(body) {
  const input = objectOf(body);
  const out = { fields: [] };
  if (input.prefix !== undefined) {
    const prefix = parsePrefix(input.prefix);
    if (prefix === null) throw invalidBody('Önek tam 3 harf olmalı (A-Z; Türkçe harfler karşılığına çevrilir).');
    out.prefix = prefix;
    out.fields.push('prefix');
  }
  if (input.resident_account_id !== undefined) {
    if (input.resident_account_id === null) {
      out.residentAccountId = null;
    } else {
      const id = parsePositiveId(input.resident_account_id);
      if (id === null) throw invalidBody('Banka hesabı geçersiz.');
      out.residentAccountId = id;
    }
    out.fields.push('resident_account_id');
  }
  if (input.notices_enabled !== undefined) {
    if (typeof input.notices_enabled !== 'boolean') throw invalidBody('Dekont yükleme anahtarı geçersiz.');
    out.noticesEnabled = input.notices_enabled;
    out.fields.push('notices_enabled');
  }
  if (out.fields.length === 0) throw invalidBody('Kaydedilecek bir alan gönderilmedi.');
  if (input.expected_settings_version !== undefined) {
    const v = Number(input.expected_settings_version);
    if (!Number.isInteger(v) || v < 1) throw invalidBody('Ayar sürümü geçersiz.');
    out.expectedVersion = v;
  }
  return out;
}

/** PUT payment-settings -> güncel ayar. Önek değişince eski önek takma ad kalır; çakışma 409 PREFIX_TAKEN, sürüm uyuşmazlığı 409. */
export async function putPaymentSettings({ siteCode, body, actor }) {
  const input = parseSettingsBody(body);
  const actorInfo = actorFromAuthUser(actor);
  try {
    await withFinanceTransaction(siteCode, async (client) => {
      await lockActorRow(client, actorInfo);
      const existing = await client.query(
        `SELECT settings_version, resident_account_id, notices_enabled FROM finance_payment_settings WHERE site_code = $1 FOR UPDATE`,
        [siteCode],
      );
      const row = existing.rows?.[0] ?? null;
      if (row && input.expectedVersion === undefined) throw invalidBody('Ayar sürümü (expected_settings_version) gerekli.');
      if (row && Number(row.settings_version) !== input.expectedVersion) throw versionConflict();
      if (input.prefix !== undefined) {
        await applyPrefix(client, siteCode, input.prefix, actorInfo.userCode);
      }
      if (input.residentAccountId !== undefined && input.residentAccountId !== null) {
        const account = await client.query(
          `
            SELECT a.id FROM finance_accounts a
            WHERE a.id = $2 AND a.site_code = $1 AND a.kind = 'bank' AND a.is_active = TRUE
              AND EXISTS (SELECT 1 FROM finance_account_bank_details d WHERE d.account_id = a.id)
          `,
          [siteCode, input.residentAccountId],
        );
        if (!account.rows?.[0]) {
          throw invalidBody('Sakinlere gösterilecek hesap bu sitenin, IBAN\'ı girilmiş, etkin bir banka hesabı olmalı.');
        }
      }
      const residentAccountId = input.residentAccountId !== undefined ? input.residentAccountId : row?.resident_account_id ?? null;
      const noticesEnabled = input.noticesEnabled !== undefined ? input.noticesEnabled : row?.notices_enabled === true;
      await client.query(
        `
          INSERT INTO finance_payment_settings (site_code, resident_account_id, notices_enabled, updated_by)
          VALUES ($1, $2, $3, $4)
          ON CONFLICT (site_code) DO UPDATE
            SET resident_account_id = EXCLUDED.resident_account_id, notices_enabled = EXCLUDED.notices_enabled, updated_by = EXCLUDED.updated_by,
                updated_at = NOW(), settings_version = finance_payment_settings.settings_version + 1
        `,
        [siteCode, residentAccountId, noticesEnabled, actorInfo.userCode],
      );
      await recordFinanceAudit(client, actor, 'finance.payment.settings_changed', siteCode, siteCode, { fields: input.fields });
    });
  } catch (error) {
    if (error?.code === '23505' && String(error?.constraint ?? '').includes('finance_site_ref_prefixes')) {
      const site = await pool.query(`SELECT name FROM sites WHERE site_code = $1`, [siteCode]);
      throw prefixTaken(await suggestionsFor(pool, siteCode, site.rows?.[0]?.name ?? ''));
    }
    throw error;
  }
  return getPaymentSettings(siteCode, { full: true });
}

async function applyPrefix(client, siteCode, prefix, userCode) {
  const current = await client.query(`SELECT prefix FROM finance_site_ref_prefixes WHERE site_code = $1 AND is_current FOR UPDATE`, [siteCode]);
  if (current.rows?.[0]?.prefix === prefix) return;
  const same = await client.query(`SELECT site_code FROM finance_site_ref_prefixes WHERE prefix = $1 FOR UPDATE`, [prefix]);
  if (same.rows?.[0] && Number(same.rows[0].site_code) !== Number(siteCode)) {
    const site = await client.query(`SELECT name FROM sites WHERE site_code = $1`, [siteCode]);
    throw prefixTaken(await suggestionsFor(client, siteCode, site.rows?.[0]?.name ?? ''));
  }
  if (current.rows?.[0]) {
    await client.query(`UPDATE finance_site_ref_prefixes SET is_current = FALSE, retired_at = NOW() WHERE site_code = $1 AND is_current`, [siteCode]);
  }
  if (same.rows?.[0]) {
    await client.query(`UPDATE finance_site_ref_prefixes SET is_current = TRUE, retired_at = NULL WHERE prefix = $1`, [prefix]);
  } else {
    await client.query(`INSERT INTO finance_site_ref_prefixes (prefix, site_code, created_by) VALUES ($1, $2, $3)`, [prefix, siteCode, userCode]);
  }
}

function parseBankBody(body) {
  const input = objectOf(body);
  const iban = parseTrIban(input.iban);
  if (iban === null) {
    throw new PlatformError(400, 'IBAN_INVALID', 'IBAN geçersiz. TR ile başlayan 26 haneli, sağlama basamağı doğru bir IBAN girin.');
  }
  const payee = typeof input.payee_name === 'string' ? input.payee_name.replace(/\s+/g, ' ').trim() : '';
  if (payee.length < 2 || payee.length > 70) throw invalidBody('Alıcı adı 2 ile 70 karakter arasında olmalı.');
  return { iban, payee };
}

/** PUT accounts/:id/bank-details -> { replayed, bank }. Aynı IBAN + alıcı adı tekrarı yeni sürüm yazmaz (200). */
export async function putBankDetails({ siteCode, rawId, body, actor }) {
  const id = parsePositiveId(rawId);
  if (id === null) throw accountNotFound();
  const { iban, payee } = parseBankBody(body);
  const actorInfo = actorFromAuthUser(actor);
  return withFinanceTransaction(siteCode, async (client) => {
    await lockActorRow(client, actorInfo);
    const account = await client.query(`SELECT id, kind FROM finance_accounts WHERE id = $1 AND site_code = $2 FOR KEY SHARE`, [id, siteCode]);
    if (!account.rows?.[0]) throw accountNotFound();
    if (account.rows[0].kind !== 'bank') throw invalidBody('IBAN yalnız banka hesabına girilebilir.');
    const last = await client.query(
      `SELECT iban, payee_name FROM finance_account_bank_details WHERE account_id = $1 ORDER BY id DESC LIMIT 1`,
      [id],
    );
    if (last.rows?.[0]?.iban === iban && last.rows[0].payee_name === payee) {
      return { replayed: true, bank: { account_id: id, iban_display: formatIban(iban), payee_name: payee } };
    }
    await client.query(
      `INSERT INTO finance_account_bank_details (site_code, account_id, iban, payee_name, created_by) VALUES ($1, $2, $3, $4, $5)`,
      [siteCode, id, iban, payee, actorInfo.userCode],
    );
    await recordFinanceAudit(client, actor, 'finance.payment.bank_details_changed', siteCode, id, {
      iban_masked: maskIban(iban),
      previous_masked: last.rows?.[0] ? maskIban(last.rows[0].iban) : null,
    });
    return { replayed: false, bank: { account_id: id, iban_display: formatIban(iban), payee_name: payee } };
  });
}

// --- Daire kodları ---------------------------------------------------------------------------------------------------------------------

const MISSING_CODES_SQL = `
  SELECT a.id, a.unit_label, b.block_name
  FROM apartments a
  INNER JOIN site_blocks b ON b.id = a.block_id
  LEFT JOIN finance_apartment_ref_codes c ON c.apartment_id = a.id
  WHERE a.site_code = $1 AND c.apartment_id IS NULL
  ORDER BY a.id
`;

/** Sitenin eksik daire kodlarını üretir (kalıcı; blok adı sonradan değişse de kod aynı kalır). Eksik yoksa yazma yapmaz. Üretilen sayıyı döner. */
export async function ensureApartmentCodes(siteCode, db = pool) {
  const probe = await db.query(MISSING_CODES_SQL, [siteCode]);
  if ((probe.rows ?? []).length === 0) return 0;
  return withFinanceTransaction(siteCode, async (client) => {
    const missing = (await client.query(MISSING_CODES_SQL, [siteCode])).rows ?? [];
    if (missing.length === 0) return 0;
    const blocks = await client.query(`SELECT COUNT(*)::INT AS n FROM site_blocks WHERE site_code = $1`, [siteCode]);
    const blockCount = Number(blocks.rows?.[0]?.n ?? 1);
    const used = new Set(((await client.query(`SELECT code FROM finance_apartment_ref_codes WHERE site_code = $1`, [siteCode])).rows ?? []).map((r) => r.code));
    const ids = [];
    const codes = [];
    for (const apt of missing) {
      let code = aptCode({ blockName: apt.block_name, unitLabel: apt.unit_label, blockCount, apartmentId: apt.id });
      if (used.has(code)) code = aptCode({ blockName: null, unitLabel: null, blockCount, apartmentId: apt.id });
      if (used.has(code)) continue;
      used.add(code);
      ids.push(Number(apt.id));
      codes.push(code);
    }
    if (ids.length === 0) return 0;
    const inserted = await client.query(
      `
        INSERT INTO finance_apartment_ref_codes (apartment_id, site_code, code)
        SELECT t.id, $1, t.code FROM unnest($2::BIGINT[], $3::TEXT[]) AS t(id, code)
        ON CONFLICT DO NOTHING
      `,
      [siteCode, ids, codes],
    );
    return inserted.rowCount ?? ids.length;
  });
}

/** GET payment-references -> daire başına kısa kod ve bu ayın kodu (yönetici listesi / Excel). */
export async function listPaymentReferences(siteCode, query = {}, { now = new Date() } = {}) {
  const prefixRow = await pool.query(`SELECT prefix FROM finance_site_ref_prefixes WHERE site_code = $1 AND is_current`, [siteCode]);
  const prefix = prefixRow.rows?.[0]?.prefix ?? null;
  if (prefix === null) return { prefix: null, period_label: periodLabel(now), items: [] };
  await ensureApartmentCodes(siteCode);
  const blockId = query.block_id === undefined ? null : parsePositiveId(query.block_id);
  if (query.block_id !== undefined && blockId === null) throw invalidBody('Blok geçersiz.');
  const result = await pool.query(
    `
      SELECT a.id, a.unit_label, b.id AS block_id, b.block_name, c.code
      FROM apartments a
      INNER JOIN site_blocks b ON b.id = a.block_id
      INNER JOIN finance_apartment_ref_codes c ON c.apartment_id = a.id
      WHERE a.site_code = $1 AND ($2::BIGINT IS NULL OR a.block_id = $2)
      ORDER BY b.sort_order, a.sort_order, a.id
    `,
    [siteCode, blockId],
  );
  return {
    prefix,
    period_label: periodLabel(now),
    items: (result.rows ?? []).map((r) => ({
      apartment_id: Number(r.id),
      block_id: Number(r.block_id),
      block_name: r.block_name,
      unit_label: r.unit_label,
      code: r.code,
      reference_short: formatRef({ prefix, code: r.code, withPeriod: false }),
      reference: formatRef({ prefix, code: r.code, now }),
    })),
  };
}

// --- Sakin -----------------------------------------------------------------------------------------------------------------------------

/**
 * GET /app/my-finance/payment-info: sakinin görebildiği (loadVisibleAccounts) ve `finance` modülü açık sitelerdeki daireler için ödeme bilgisi.
 * TUTAR DÖNMEZ. Ayar yoksa `configured: false`. IBAN, son iki sürüm farklıysa `details_changed_at` (istemci 14 gün uyarısı) taşır.
 */
export async function getMyPaymentInfo(authUser, { now = new Date(), db = pool } = {}) {
  const userCode = parsePositiveId(authUser?.user_code ?? authUser?.userCode ?? authUser?.id);
  if (userCode === null) return { items: [] };
  await syncUserPeopleSafe(userCode);
  const visible = await loadVisibleAccounts(db, userCode);
  const enabled = await enabledFinanceSites(db, [...new Set(visible.map((row) => Number(row.site_code)))]);
  const apartments = visible.filter((row) => enabled.has(Number(row.site_code)));
  const siteInfo = new Map();
  for (const siteCode of [...new Set(apartments.map((row) => Number(row.site_code)))]) {
    siteInfo.set(siteCode, await loadSiteInfo(db, siteCode));
  }
  const onlineBySite = new Map();
  for (const siteCode of siteInfo.keys()) onlineBySite.set(siteCode, await isOnlinePaymentAvailable(siteCode, db));
  const codeCache = new Map();
  const items = [];
  for (const apt of apartments) {
    const siteCode = Number(apt.site_code);
    const info = siteInfo.get(siteCode);
    const base = {
      site_code: siteCode,
      site_name: apt.site_name ?? null,
      apartment_id: Number(apt.apartment_id),
      configured: false,
      payee_name: null,
      iban: null,
      iban_display: null,
      reference: null,
      reference_short: null,
      period_label: periodLabel(now),
      details_changed_at: null,
      notices_enabled: info.noticesEnabled,
      card_payment: 'coming_soon',
      // "Online Öde": YALNIZ canlı mod + başarılı sınama + ETKİN sürücü varsa true (şimdilik hiçbir sağlayıcı etkin değil => hep false).
      online_payment_available: onlineBySite.get(siteCode) === true,
    };
    if (!info.prefix || !info.bank) {
      items.push(base);
      continue;
    }
    if (!codeCache.has(siteCode)) {
      await ensureApartmentCodes(siteCode, db);
      const rows = await db.query(`SELECT apartment_id, code FROM finance_apartment_ref_codes WHERE site_code = $1`, [siteCode]);
      codeCache.set(siteCode, new Map((rows.rows ?? []).map((r) => [Number(r.apartment_id), r.code])));
    }
    const code = codeCache.get(siteCode).get(Number(apt.apartment_id));
    if (!code) {
      items.push(base);
      continue;
    }
    items.push({
      ...base,
      configured: true,
      payee_name: info.bank.payee_name,
      iban: info.bank.iban,
      iban_display: formatIban(info.bank.iban),
      reference: formatRef({ prefix: info.prefix, code, now }),
      reference_short: formatRef({ prefix: info.prefix, code, withPeriod: false }),
      details_changed_at: info.bank.changed_at,
    });
  }
  return { items };
}

async function loadSiteInfo(db, siteCode) {
  const settings = await db.query(
    `
      SELECT s.resident_account_id, s.notices_enabled,
             (SELECT prefix FROM finance_site_ref_prefixes p WHERE p.site_code = s.site_code AND p.is_current) AS prefix
      FROM finance_payment_settings s WHERE s.site_code = $1
    `,
    [siteCode],
  );
  const row = settings.rows?.[0] ?? null;
  const out = { prefix: row?.prefix ?? null, noticesEnabled: row?.notices_enabled === true, bank: null };
  if (!row?.resident_account_id) return out;
  const versions = await db.query(
    `
      SELECT d.iban, d.payee_name, d.created_at
      FROM finance_account_bank_details d
      INNER JOIN finance_accounts a ON a.id = d.account_id AND a.site_code = $2 AND a.kind = 'bank' AND a.is_active = TRUE
      WHERE d.account_id = $1
      ORDER BY d.id DESC LIMIT 2
    `,
    [row.resident_account_id, siteCode],
  );
  const [latest, previous] = versions.rows ?? [];
  if (latest) {
    out.bank = {
      iban: latest.iban,
      payee_name: latest.payee_name,
      changed_at: previous && previous.iban !== latest.iban ? new Date(latest.created_at).toISOString() : null,
    };
  }
  return out;
}
