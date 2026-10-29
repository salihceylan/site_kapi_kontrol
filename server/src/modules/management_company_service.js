// Yönetim firması (Y1) + deneme süresi ve ortaklık payı (Y2). Sözleşme: docs/PLATFORM_YONETIM_FIRMASI.md.
// Para tamsayı kuruş. Pay dökümü yalnız BİLGİ amaçlıdır (fatura ya da ödeme üretmez). Fiyat depoda yok: süper kullanıcı girer.

import { pool } from '../db.js';
import { recordAudit } from './audit_service.js';
import { PlatformError } from './errors.js';

export const TRIAL_SETTING_KEY = 'subscription.trial_days';
export const TRIAL_DEFAULT_DAYS = 60;
export const TRIAL_MAX_DAYS = 365;
export const COMPANY_ROLES = Object.freeze(['owner', 'staff']);

const notFound = () => new PlatformError(404, 'COMPANY_NOT_FOUND', 'Yönetim firması bulunamadı.');
const forbidden = () => new PlatformError(403, 'FORBIDDEN_COMPANY', 'Bu işlem için firma sahibi yetkisi gerekir.');

export function userCodeOf(user) {
  const code = Number(user?.userCode ?? user?.user_code ?? user?.id);
  return Number.isInteger(code) ? code : null;
}

function isSuper(user) {
  return user?.role === 'super_user';
}

function intIn(value, min, max, code, message) {
  const n = typeof value === 'string' && /^\d{1,12}$/.test(value.trim()) ? Number(value.trim()) : value;
  if (!Number.isSafeInteger(n) || n < min || n > max) {
    throw new PlatformError(400, code, message);
  }
  return n;
}

function cleanName(value) {
  const name = typeof value === 'string' ? value.trim().replace(/\s+/g, ' ') : '';
  if (name.length < 2 || name.length > 120) {
    throw new PlatformError(400, 'INVALID_NAME', 'Firma adı 2-120 karakter olmalı.');
  }
  return name;
}

// --- Deneme süresi -----------------------------------------------------------------------------------------------------------

export async function getTrialDays(db = pool) {
  const res = await db.query('SELECT value FROM platform_settings WHERE key = $1', [TRIAL_SETTING_KEY]);
  const days = Number(res.rows[0]?.value?.days);
  return Number.isInteger(days) && days >= 0 && days <= TRIAL_MAX_DAYS ? days : TRIAL_DEFAULT_DAYS;
}

export async function setTrialDays({ days, actor }) {
  const value = intIn(days, 0, TRIAL_MAX_DAYS, 'INVALID_TRIAL_DAYS', `Deneme süresi 0-${TRIAL_MAX_DAYS} gün olmalı.`);
  await pool.query(
    `INSERT INTO platform_settings (key, value, updated_at, updated_by) VALUES ($1, $2::jsonb, NOW(), $3)
     ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, updated_at = NOW(), updated_by = EXCLUDED.updated_by`,
    [TRIAL_SETTING_KEY, JSON.stringify({ days: value }), userCodeOf(actor)],
  );
  await recordAudit(pool, { actor, action: 'subscription.trial_days_updated', targetType: 'platform_settings', targetId: TRIAL_SETTING_KEY, details: { days: value } });
  return { trial_days: value };
}

/**
 * Yeni açılan sitenin abonelik satırına deneme sürecini yazar (varsayılan 60 gün; 0 = deneme yok). Çağıranın transaction'ında çalışır;
 * hata siteyi açmayı ENGELLEMEZ (SAVEPOINT içinde yutulur).
 */
export async function applyTrialToNewSubscription(client, siteCode) {
  try {
    await client.query('SAVEPOINT trial_apply');
    const days = await getTrialDays(client);
    if (days > 0) {
      await client.query(
        `UPDATE site_subscriptions SET status = 'trial', trial_ends_at = NOW() + make_interval(days => $2), updated_at = NOW() WHERE site_code = $1`,
        [siteCode, days],
      );
    }
    await client.query('RELEASE SAVEPOINT trial_apply');
  } catch (error) {
    await client.query('ROLLBACK TO SAVEPOINT trial_apply').catch(() => {});
    console.error('[company] deneme süresi yazılamadı:', error?.code || error?.message);
  }
}

/** Süper kullanıcı: bir sitenin deneme bitişini ayarlar. { days } (bugünden) ya da { trial_ends_at: null } (denemeyi kaldırır). */
export async function setSiteTrial({ siteCode, body, actor }) {
  const sub = await pool.query('SELECT status FROM site_subscriptions WHERE site_code = $1', [siteCode]);
  if (sub.rowCount === 0) {
    throw new PlatformError(404, 'SUBSCRIPTION_NOT_FOUND', 'Bu sitenin abonelik kaydı yok (eski site).');
  }
  const b = body && typeof body === 'object' ? body : {};
  let res;
  if (b.trial_ends_at === null) {
    res = await pool.query(
      `UPDATE site_subscriptions SET trial_ends_at = NULL, status = CASE WHEN status = 'trial' THEN 'active' ELSE status END, updated_at = NOW()
       WHERE site_code = $1 RETURNING status, trial_ends_at`,
      [siteCode],
    );
  } else {
    const days = intIn(b.days, 1, TRIAL_MAX_DAYS, 'INVALID_TRIAL_DAYS', `Deneme süresi 1-${TRIAL_MAX_DAYS} gün olmalı.`);
    res = await pool.query(
      `UPDATE site_subscriptions SET trial_ends_at = NOW() + make_interval(days => $2),
         status = CASE WHEN status IN ('active', 'trial') THEN 'trial' ELSE status END, updated_at = NOW()
       WHERE site_code = $1 RETURNING status, trial_ends_at`,
      [siteCode, days],
    );
  }
  await recordAudit(pool, { actor, action: 'subscription.site_trial_updated', siteCode, targetType: 'site_subscription', targetId: String(siteCode), details: { days: b.days ?? null } });
  return { site_code: siteCode, status: res.rows[0].status, trial_ends_at: res.rows[0].trial_ends_at };
}

// --- Firma ve yetki ---------------------------------------------------------------------------------------------------------

/**
 * 'super' | 'owner' | 'staff' | null (üye değil YA DA firma PASİF). Pasif firma (is_active = false) yalnız süper kullanıcıya açıktır: üyelik satırı
 * kalsa bile firma sahibi / personeli için null döner (-> 404; firmanın varlığı sızdırılmaz, pasife alınan firma yetkisini sürdüremez).
 */
export async function companyRoleOf(db, companyId, user) {
  if (isSuper(user)) return 'super';
  const code = userCodeOf(user);
  if (code === null) return null;
  const res = await db.query(
    `SELECT m.role FROM management_company_members m
     JOIN management_companies c ON c.id = m.company_id AND c.is_active = TRUE
     WHERE m.company_id = $1 AND m.user_code = $2`,
    [companyId, code],
  );
  return res.rows[0]?.role ?? null;
}

/** Üye değilse 404 (firmanın varlığı sızdırılmaz); `needOwner` iken personel 403. Dönen: rol. */
export async function requireCompanyAccess(companyId, user, { needOwner = false, needSuper = false } = {}) {
  const role = await companyRoleOf(pool, companyId, user);
  if (role === null) throw notFound();
  if (needSuper && role !== 'super') throw forbidden();
  if (needOwner && role === 'staff') throw forbidden();
  return role;
}

const COMPANY_COLUMNS = 'c.id, c.name, c.partner_share_bp, c.is_active, c.created_at';

export async function listCompanies(user) {
  const res = isSuper(user)
    ? await pool.query(`SELECT ${COMPANY_COLUMNS}, 'super' AS my_role FROM management_companies c ORDER BY c.name`)
    : await pool.query(
        `SELECT ${COMPANY_COLUMNS}, m.role AS my_role FROM management_companies c
         JOIN management_company_members m ON m.company_id = c.id WHERE m.user_code = $1 AND c.is_active ORDER BY c.name`,
        [userCodeOf(user)],
      );
  return { companies: res.rows };
}

export async function getCompany(companyId, user) {
  const role = await requireCompanyAccess(companyId, user);
  const company = await pool.query(`SELECT ${COMPANY_COLUMNS} FROM management_companies c WHERE c.id = $1`, [companyId]);
  if (company.rowCount === 0) throw notFound();
  const members = await pool.query(
    `SELECT m.user_code, m.role, u.full_name, u.email FROM management_company_members m JOIN users u ON u.user_code = m.user_code
     WHERE m.company_id = $1 ORDER BY m.role DESC, u.full_name`,
    [companyId],
  );
  const sites = await pool.query(
    `SELECT cs.site_code, s.name, cs.monthly_fee_minor, sub.status AS subscription_status, sub.trial_ends_at
     FROM management_company_sites cs JOIN sites s ON s.site_code = cs.site_code
     LEFT JOIN site_subscriptions sub ON sub.site_code = cs.site_code WHERE cs.company_id = $1 ORDER BY s.name`,
    [companyId],
  );
  const showFee = role !== 'staff';
  return {
    company: { ...company.rows[0], my_role: role },
    members: members.rows,
    sites: sites.rows.map((r) => (showFee ? r : { ...r, monthly_fee_minor: undefined })),
  };
}

async function findUserByEmail(db, email) {
  const clean = typeof email === 'string' ? email.trim().toLowerCase() : '';
  if (!clean || clean.length > 200) throw new PlatformError(400, 'INVALID_EMAIL', 'E-posta adresi geçersiz.');
  const res = await db.query('SELECT user_code FROM users WHERE LOWER(email) = $1 AND is_active', [clean]);
  if (res.rowCount === 0) throw new PlatformError(404, 'USER_NOT_FOUND', 'Bu e-postayla kayıtlı kullanıcı bulunamadı. Kişi önce uygulamaya kayıt olmalı.');
  return res.rows[0].user_code;
}

/** Süper kullanıcı: firma + (varsa) sahip. Body: { name, partner_share_bp?, owner_email }. */
export async function createCompany({ body, actor }) {
  const b = body && typeof body === 'object' ? body : {};
  const name = cleanName(b.name);
  const share = b.partner_share_bp === undefined ? 0 : intIn(b.partner_share_bp, 0, 10000, 'INVALID_SHARE', 'Ortaklık payı 0-10000 baz puan (0-%100) olmalı.');
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const ownerCode = await findUserByEmail(client, b.owner_email);
    const created = await client.query(
      'INSERT INTO management_companies (name, partner_share_bp, created_by) VALUES ($1, $2, $3) RETURNING id',
      [name, share, userCodeOf(actor)],
    );
    const id = created.rows[0].id;
    await client.query(`INSERT INTO management_company_members (company_id, user_code, role) VALUES ($1, $2, 'owner')`, [id, ownerCode]);
    await recordAudit(client, { actor, action: 'management_company.created', targetType: 'management_company', targetId: String(id), details: { name, partner_share_bp: share, owner_user_code: ownerCode } }, { inTransaction: true });
    await client.query('COMMIT');
    return { id };
  } catch (error) {
    await client.query('ROLLBACK').catch(() => {});
    throw error;
  } finally {
    client.release();
  }
}

/** Süper kullanıcı: ad, ortaklık payı, aktiflik. */
export async function updateCompany({ companyId, body, actor }) {
  const b = body && typeof body === 'object' ? body : {};
  const sets = [];
  const params = [companyId];
  if (b.name !== undefined) { params.push(cleanName(b.name)); sets.push(`name = $${params.length}`); }
  if (b.partner_share_bp !== undefined) {
    params.push(intIn(b.partner_share_bp, 0, 10000, 'INVALID_SHARE', 'Ortaklık payı 0-10000 baz puan (0-%100) olmalı.'));
    sets.push(`partner_share_bp = $${params.length}`);
  }
  if (b.is_active !== undefined) {
    if (typeof b.is_active !== 'boolean') throw new PlatformError(400, 'INVALID_BODY', 'is_active true/false olmalı.');
    params.push(b.is_active);
    sets.push(`is_active = $${params.length}`);
  }
  if (sets.length === 0) throw new PlatformError(400, 'INVALID_BODY', 'Değiştirilecek alan yok.');
  const res = await pool.query(`UPDATE management_companies SET ${sets.join(', ')} WHERE id = $1 RETURNING id`, params);
  if (res.rowCount === 0) throw notFound();
  await recordAudit(pool, { actor, action: 'management_company.updated', targetType: 'management_company', targetId: String(companyId), details: { fields: Object.keys(b) } });
  return { id: companyId };
}

/** Firma sahibi personel ekler; süper kullanıcı sahip de ekleyebilir. Body: { email, role? }. */
export async function addMember({ companyId, body, actor }) {
  const role = await requireCompanyAccess(companyId, actor, { needOwner: true });
  const b = body && typeof body === 'object' ? body : {};
  const memberRole = b.role === undefined ? 'staff' : b.role;
  if (!COMPANY_ROLES.includes(memberRole)) throw new PlatformError(400, 'INVALID_ROLE', 'Rol owner ya da staff olmalı.');
  if (memberRole === 'owner' && role !== 'super') throw forbidden();
  const code = await findUserByEmail(pool, b.email);
  await pool.query(
    `INSERT INTO management_company_members (company_id, user_code, role) VALUES ($1, $2, $3)
     ON CONFLICT (company_id, user_code) DO UPDATE SET role = EXCLUDED.role WHERE management_company_members.role <> 'owner' OR $4`,
    [companyId, code, memberRole, role === 'super'],
  );
  await recordAudit(pool, { actor, action: 'management_company.member_added', targetType: 'management_company', targetId: String(companyId), details: { user_code: code, role: memberRole } });
  return { user_code: code, role: memberRole };
}

export async function removeMember({ companyId, userCode, actor }) {
  const role = await requireCompanyAccess(companyId, actor, { needOwner: true });
  const target = await pool.query('SELECT role FROM management_company_members WHERE company_id = $1 AND user_code = $2', [companyId, userCode]);
  if (target.rowCount === 0) throw new PlatformError(404, 'MEMBER_NOT_FOUND', 'Üye bulunamadı.');
  if (target.rows[0].role === 'owner') {
    if (role !== 'super') throw forbidden();
    const owners = await pool.query(`SELECT COUNT(*)::INT AS n FROM management_company_members WHERE company_id = $1 AND role = 'owner'`, [companyId]);
    if (owners.rows[0].n <= 1) throw new PlatformError(409, 'LAST_OWNER', 'Firmanın son sahibi çıkarılamaz.');
  }
  await pool.query('DELETE FROM management_company_members WHERE company_id = $1 AND user_code = $2', [companyId, userCode]);
  await recordAudit(pool, { actor, action: 'management_company.member_removed', targetType: 'management_company', targetId: String(companyId), details: { user_code: userCode } });
  return { removed: true };
}

/** Süper kullanıcı: siteyi firmaya bağlar (site başka firmadaysa 409) ve aylık bedeli (kuruş, bilgi amaçlı) yazar. */
export async function linkSite({ companyId, body, actor }) {
  const b = body && typeof body === 'object' ? body : {};
  const siteCode = intIn(b.site_code, 1, 9999999999, 'INVALID_SITE_CODE', 'Site kodu geçersiz.');
  const fee = b.monthly_fee_minor === undefined || b.monthly_fee_minor === null ? null : intIn(b.monthly_fee_minor, 0, 1000000000000, 'INVALID_FEE', 'Aylık bedel geçersiz.');
  const company = await pool.query('SELECT 1 FROM management_companies WHERE id = $1', [companyId]);
  if (company.rowCount === 0) throw notFound();
  const site = await pool.query('SELECT 1 FROM sites WHERE site_code = $1', [siteCode]);
  if (site.rowCount === 0) throw new PlatformError(404, 'SITE_NOT_FOUND', 'Site bulunamadı.');
  const res = await pool.query(
    `INSERT INTO management_company_sites (site_code, company_id, monthly_fee_minor) VALUES ($1, $2, $3)
     ON CONFLICT (site_code) DO UPDATE SET monthly_fee_minor = EXCLUDED.monthly_fee_minor WHERE management_company_sites.company_id = EXCLUDED.company_id
     RETURNING site_code`,
    [siteCode, companyId, fee],
  );
  if (res.rowCount === 0) throw new PlatformError(409, 'SITE_ALREADY_LINKED', 'Bu site başka bir firmaya bağlı.');
  await recordAudit(pool, { actor, action: 'management_company.site_linked', siteCode, targetType: 'management_company', targetId: String(companyId), details: { monthly_fee_minor: fee } });
  return { site_code: siteCode };
}

export async function unlinkSite({ companyId, siteCode, actor }) {
  const res = await pool.query('DELETE FROM management_company_sites WHERE company_id = $1 AND site_code = $2', [companyId, siteCode]);
  if (res.rowCount === 0) throw new PlatformError(404, 'SITE_NOT_LINKED', 'Site bu firmaya bağlı değil.');
  await recordAudit(pool, { actor, action: 'management_company.site_unlinked', siteCode, targetType: 'management_company', targetId: String(companyId), details: {} });
  return { removed: true };
}

// --- Tüm siteler tablosu -----------------------------------------------------------------------------------------------------

/** % (baz puan, yarım yukarı) = pay * 10000 / payda; payda <= 0 ise null. */
export function rateBp(numerator, denominator) {
  const n = BigInt(numerator);
  const d = BigInt(denominator);
  if (d <= 0n) return null;
  return Number((n * 20000n + d) / (d * 2n));
}

/** En düşük tahsilat oranı üstte; oranı olmayan (borçlandırma yok) sonda; eşitlikte ad. */
export function sortSitesByCollection(rows) {
  return [...rows].sort((a, b) => {
    const ra = a.collection_rate_bp;
    const rb = b.collection_rate_bp;
    if (ra === null && rb !== null) return 1;
    if (rb === null && ra !== null) return -1;
    if (ra !== rb && ra !== null) return ra - rb;
    return String(a.name).localeCompare(String(b.name), 'tr');
  });
}

/**
 * Firma sahibi: bağlı her site için dört sayı (daire sayısı, bu ay tahsilat oranı, açık borç toplamı, borçlu daire sayısı).
 * Bu ay oranı = bu ayın tahsilatı / bu ayın borçlandırması (gecikme tazminatı dahil). Finans modülü kapalı/boş sitede oran null, borç 0.
 */
export async function listAllSitesTable(companyId, user) {
  await requireCompanyAccess(companyId, user, { needOwner: true });
  const res = await pool.query(
    `
      WITH cs AS (SELECT cs.site_code FROM management_company_sites cs WHERE cs.company_id = $1),
      apt AS (SELECT a.site_code, COUNT(*)::INT AS n FROM apartments a JOIN cs ON cs.site_code = a.site_code WHERE a.is_active GROUP BY a.site_code),
      month_led AS (
        SELECT l.site_code,
          COALESCE(SUM(l.amount_minor) FILTER (WHERE COALESCE(l.source_kind, '') NOT IN ('refund', 'liability_transfer') AND (l.kind = 'charge' OR (l.kind = 'reversal' AND l.amount_minor < 0))), 0)::TEXT AS charged,
          (COALESCE(-SUM(l.amount_minor) FILTER (WHERE l.kind = 'payment' OR (l.kind = 'reversal' AND l.amount_minor > 0)), 0) - COALESCE(SUM(l.amount_minor) FILTER (WHERE l.source_kind = 'refund'), 0))::TEXT AS collected
        FROM ledger_entries l JOIN cs ON cs.site_code = l.site_code
        WHERE l.period = date_trunc('month', (NOW() AT TIME ZONE 'Europe/Istanbul'))::DATE GROUP BY l.site_code
      ),
      bal AS (
        SELECT b.site_code, COALESCE(SUM(b.bal) FILTER (WHERE b.bal > 0), 0)::TEXT AS debt, COUNT(*) FILTER (WHERE b.bal > 0)::INT AS debtors
        FROM (SELECT l.site_code, l.apartment_id, SUM(l.amount_minor) AS bal FROM ledger_entries l JOIN cs ON cs.site_code = l.site_code GROUP BY l.site_code, l.apartment_id) b
        GROUP BY b.site_code
      )
      SELECT s.site_code, s.name, COALESCE(apt.n, 0) AS apartment_count, COALESCE(m.charged, '0') AS charged, COALESCE(m.collected, '0') AS collected,
        COALESCE(bal.debt, '0') AS debt, COALESCE(bal.debtors, 0) AS debtor_count, sub.status AS subscription_status, sub.trial_ends_at
      FROM cs JOIN sites s ON s.site_code = cs.site_code
      LEFT JOIN apt ON apt.site_code = cs.site_code LEFT JOIN month_led m ON m.site_code = cs.site_code LEFT JOIN bal ON bal.site_code = cs.site_code
      LEFT JOIN site_subscriptions sub ON sub.site_code = cs.site_code
    `,
    [companyId],
  );
  const rows = res.rows.map((r) => ({
    site_code: r.site_code,
    name: r.name,
    apartment_count: r.apartment_count,
    collection_rate_bp: rateBp(r.collected, r.charged),
    open_debt_minor: Number(r.debt),
    debtor_count: r.debtor_count,
    subscription_status: r.subscription_status ?? null,
    trial_ends_at: r.trial_ends_at ?? null,
  }));
  return { sites: sortSitesByCollection(rows) };
}

// --- Aylık ortaklık payı dökümü (bilgi amaçlı) ----------------------------------------------------------------------------------

/**
 * Pay = aylık bedel * pay oranı. Deneme süresi o ay sonunda hâlâ sürüyorsa (trial_ends_at >= ayın son günü) pay 0 sayılır.
 * Bedeli girilmemiş site "bedel yok" olarak listelenir, toplama girmez. Fatura ya da ödeme ÜRETMEZ.
 */
export async function shareStatement(companyId, user, monthRaw) {
  await requireCompanyAccess(companyId, user, { needOwner: true });
  const now = new Date();
  const month = typeof monthRaw === 'string' && /^\d{4}-(0[1-9]|1[0-2])$/.test(monthRaw) ? monthRaw : `${now.getUTCFullYear()}-${String(now.getUTCMonth() + 1).padStart(2, '0')}`;
  const company = await pool.query('SELECT partner_share_bp FROM management_companies WHERE id = $1', [companyId]);
  if (company.rowCount === 0) throw notFound();
  const shareBp = company.rows[0].partner_share_bp;
  const res = await pool.query(
    `SELECT cs.site_code, s.name, cs.monthly_fee_minor,
       COALESCE(sub.trial_ends_at >= (date_trunc('month', $2::DATE) + INTERVAL '1 month - 1 day')::DATE, FALSE) AS in_trial
     FROM management_company_sites cs JOIN sites s ON s.site_code = cs.site_code
     LEFT JOIN site_subscriptions sub ON sub.site_code = cs.site_code WHERE cs.company_id = $1 ORDER BY s.name`,
    [companyId, `${month}-01`],
  );
  let total = 0n;
  const rows = res.rows.map((r) => {
    const fee = r.monthly_fee_minor === null ? null : BigInt(r.monthly_fee_minor);
    const share = fee === null || r.in_trial ? 0n : (fee * BigInt(shareBp) * 2n + 10000n) / 20000n;
    total += share;
    return { site_code: r.site_code, name: r.name, monthly_fee_minor: fee === null ? null : Number(fee), in_trial: r.in_trial, share_minor: Number(share) };
  });
  return { month, partner_share_bp: shareBp, informational: true, total_share_minor: Number(total), sites: rows };
}
