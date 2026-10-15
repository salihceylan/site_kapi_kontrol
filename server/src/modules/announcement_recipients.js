// Duyuru kitlesi (alıcı anlık görüntüsü) ve yayın öncesi kitle önizlemesi.
//
// Sözleşme: docs/PLATFORM_DUYURU.md ("Kitle (alıcı) kuralı", "E-posta"). Kitle CRM kişileridir (hesapsızlar dahil): hedef (aktif)
// dairelerdeki GÜNCEL ilişkilere sahip AKTİF site_people kişileri, kişi başına TEK satır. E-posta adresi Faz 2'nin "etkin iletişim
// e-postası" mantığıyla (people_service.js CONTACT_EMAIL_SQL) bulunur; dahili @ahbu.local adresi hiçbir zaman adres sayılmaz.
// Bu dosya yalnız verilen db/client üzerinde çalışır (transaction'ı ÇAĞIRAN yönetir).

import { HAS_ACCOUNT_SQL } from './people_common.js';
import { CONTACT_EMAIL_SQL, PERSON_FROM } from './people_service.js';
import { INTERNAL_EMAIL_SUFFIX } from './people_sync_sql.js';
import {
  DEFAULT_EMAIL_DAILY_LIMIT,
  EMAIL_PER_PUBLISH_LIMIT,
  emailLimitExceeded,
  invalidTarget,
} from './announcement_common.js';

/** Site başına günlük e-posta sınırı (env ANNOUNCEMENT_EMAIL_MAX_PER_DAY_PER_SITE; geçersizse 500). */
export function emailDailyLimit(env = process.env) {
  const raw = env.ANNOUNCEMENT_EMAIL_MAX_PER_DAY_PER_SITE;
  if (raw === undefined || String(raw).trim() === '') {
    return DEFAULT_EMAIL_DAILY_LIMIT;
  }
  const parsed = Number(raw);
  return Number.isSafeInteger(parsed) && parsed >= 0 ? parsed : DEFAULT_EMAIL_DAILY_LIMIT;
}

export const emptyEmailCounts = () => ({
  requested: 0,
  sent: 0,
  failed: 0,
  no_address: 0,
  skipped_pref: 0,
  capped: 0,
  duplicate: 0,
  pending: 0,
});

/** email_status -> sayı satırlarından AnnouncementDetail.stats.email (requested = e-posta istenen alıcı sayısı: 'none' hariç). */
export function emailCountsFromRows(rows) {
  const counts = emptyEmailCounts();
  for (const row of rows ?? []) {
    const status = row.email_status;
    const n = Number(row.n ?? 0);
    if (status === 'none') {
      continue;
    }
    if (status in counts && status !== 'requested') {
      counts[status] += n;
      counts.requested += n;
    }
  }
  return counts;
}

/**
 * Hedefi uygulayan SQL parçası (daire takma adı `a`) ve parametreleri. Kimlikler $startIndex'ten itibaren numaralanır.
 * @returns {{ sql: string, params: unknown[] }}
 */
export function targetClause(target, startIndex) {
  if (target.type === 'blocks') {
    return { sql: `a.block_id = ANY($${startIndex}::BIGINT[])`, params: [target.blockIds] };
  }
  if (target.type === 'apartments') {
    return { sql: `a.id = ANY($${startIndex}::BIGINT[])`, params: [target.apartmentIds] };
  }
  return { sql: 'TRUE', params: [] };
}

const SAFE_EMAIL_PATTERN = `'^[^[:space:]@]+@[^[:space:]@]+[.][^[:space:]@]+$'`;

/** Ham iletişim e-postası -> teslim edilebilir adres (küçük harf) ya da NULL (dahili @ahbu.local / biçim hatalı / çok uzun). */
const deliverableEmailSql = (column) => `(
  CASE
    WHEN ${column} IS NULL THEN NULL
    WHEN lower(btrim(${column})) LIKE '%${INTERNAL_EMAIL_SUFFIX}' THEN NULL
    WHEN char_length(btrim(${column})) > 254 THEN NULL
    WHEN btrim(${column}) !~ ${SAFE_EMAIL_PATTERN} THEN NULL
    ELSE lower(btrim(${column}))
  END
)`;

/**
 * Kitle CTE'leri: $1 = site_code; hedef kimlikleri $2'den (hedef türüne göre). `base` (person_id, has_account, email_pref, email).
 * @returns {{ sql: string, params: unknown[] }} params $2'den başlar (site kodu çağıranın ilk parametresidir)
 */
function audienceCtes(target) {
  const clause = targetClause(target, 2);
  const sql = `
    audience AS (
      SELECT DISTINCT r.person_id
      FROM apartment_residencies r
      INNER JOIN apartments a ON a.id = r.apartment_id
      WHERE r.is_current = TRUE AND a.site_code = $1 AND a.is_active = TRUE AND ${clause.sql}
    ),
    contact AS (
      SELECT
        sp.id AS person_id,
        ${HAS_ACCOUNT_SQL} AS has_account,
        COALESCE(np.email_announcements, TRUE) AS email_pref,
        ${CONTACT_EMAIL_SQL} AS raw_email
      ${PERSON_FROM}
      INNER JOIN audience au ON au.person_id = sp.id
      LEFT JOIN notification_preferences np ON np.user_code = sp.user_code
      WHERE sp.site_code = $1 AND sp.is_active = TRUE
    ),
    base AS (
      SELECT person_id, has_account, email_pref, ${deliverableEmailSql('raw_email')} AS email
      FROM contact
    )
  `;
  return { sql, params: clause.params };
}

/** Hedefteki blok/daire kimliklerinin TAMAMI bu siteye ait olmalı (aksi 400 INVALID_TARGET). */
export async function assertTargetBelongsToSite(db, siteCode, target) {
  if (target.type === 'blocks') {
    const result = await db.query(
      `SELECT COUNT(*)::INTEGER AS n FROM site_blocks WHERE site_code = $1 AND id = ANY($2::BIGINT[])`,
      [siteCode, target.blockIds],
    );
    if (Number(result.rows?.[0]?.n ?? 0) !== target.blockIds.length) {
      throw invalidTarget('Seçilen bloklar bu siteye ait değil.');
    }
  } else if (target.type === 'apartments') {
    const result = await db.query(
      `SELECT COUNT(*)::INTEGER AS n FROM apartments WHERE site_code = $1 AND id = ANY($2::BIGINT[])`,
      [siteCode, target.apartmentIds],
    );
    if (Number(result.rows?.[0]?.n ?? 0) !== target.apartmentIds.length) {
      throw invalidTarget('Seçilen daireler bu siteye ait değil.');
    }
  }
}

/**
 * Yayın öncesi kitle önizlemesi (hiçbir şey yazmaz). people = ulaşılacak kişi, apartments = en az bir alıcısı olan hedef daire,
 * with_account = hesabı olan kişi, with_email = teslim edilebilir adresi olan kişi, without_email = people - with_email.
 */
export async function previewAudience(db, siteCode, target) {
  const audience = audienceCtes(target);
  const people = await db.query(
    `
      WITH ${audience.sql}
      SELECT
        COUNT(*)::INTEGER AS people,
        COUNT(*) FILTER (WHERE has_account)::INTEGER AS with_account,
        COUNT(*) FILTER (WHERE email IS NOT NULL)::INTEGER AS with_email
      FROM base
    `,
    [siteCode, ...audience.params],
  );
  const clause = targetClause(target, 2);
  const apartments = await db.query(
    `
      SELECT COUNT(DISTINCT r.apartment_id)::INTEGER AS apartments
      FROM apartment_residencies r
      INNER JOIN apartments a ON a.id = r.apartment_id
      INNER JOIN site_people sp ON sp.id = r.person_id AND sp.site_code = $1 AND sp.is_active = TRUE
      WHERE r.is_current = TRUE AND a.site_code = $1 AND a.is_active = TRUE AND ${clause.sql}
    `,
    [siteCode, ...clause.params],
  );
  const row = people.rows?.[0] ?? {};
  const total = Number(row.people ?? 0);
  const withEmail = Number(row.with_email ?? 0);
  return {
    people: total,
    apartments: Number(apartments.rows?.[0]?.apartments ?? 0),
    with_account: Number(row.with_account ?? 0),
    with_email: withEmail,
    without_email: total - withEmail,
  };
}

/** Sitenin bugün (İstanbul takvim günü) kuyruğa alınmış/gönderilmiş e-posta sayısı (pending + sent + failed). */
export async function emailUsageToday(db, siteCode) {
  const result = await db.query(
    `
      SELECT COUNT(*)::INTEGER AS used
      FROM announcement_recipients r
      INNER JOIN announcements a ON a.id = r.announcement_id
      WHERE a.site_code = $1
        AND a.published_at >= (date_trunc('day', NOW() AT TIME ZONE 'Europe/Istanbul') AT TIME ZONE 'Europe/Istanbul')
        AND r.email_status IN ('pending', 'sent', 'failed')
    `,
    [siteCode],
  );
  return Number(result.rows?.[0]?.used ?? 0);
}

export async function loadEmailStatusCounts(db, announcementId) {
  const result = await db.query(
    `SELECT email_status, COUNT(*)::INTEGER AS n FROM announcement_recipients WHERE announcement_id = $1 GROUP BY email_status`,
    [announcementId],
  );
  return result.rows ?? [];
}

/**
 * Yayın anı alıcı anlık görüntüsü (çağıranın transaction'ında, site kişi kilidi ve eşitleme sonrası).
 *  1) kişi başına tek satır: e-posta istenmediyse 'none'; adres yok -> 'no_address'; hesabı olan ve tercihi kapalı ve duyuru
 *     'normal' -> 'skipped_pref' (acil tercihi yok sayar); aksi 'pending' + adres satıra yazılır
 *  2) aynı adres tek kez: ilk kişi (person_id sırası) 'pending' kalır, diğerleri 'duplicate' olur
 *  3) yönetici yayınında (enforceEmailLimit) teslim edilecek adres > 1000 ise 400 ANNOUNCEMENT_EMAIL_LIMIT (transaction geri alınır)
 *  4) günlük site sınırı / tek yayın sınırı aşan 'pending' satırlar 'capped' olur (e-posta NULL)
 * @returns {Promise<{ total: number, email: object }>}
 */
export async function snapshotRecipients(
  db,
  { announcementId, siteCode, target, importance, sendEmail, enforceEmailLimit, dailyLimit = emailDailyLimit() },
) {
  // Günlük kullanım, bu duyurunun satırları EKLENMEDEN önce okunur (aynı site için yayınlar kişi kilidiyle sıralıdır).
  const used = sendEmail ? await emailUsageToday(db, siteCode) : 0;
  const audience = audienceCtes(target);
  const nextParam = audience.params.length + 2;
  const insert = await db.query(
    `
      WITH ${audience.sql}
      INSERT INTO announcement_recipients (announcement_id, person_id, email, email_status)
      SELECT
        $${nextParam}::BIGINT,
        b.person_id,
        CASE
          WHEN $${nextParam + 1}::BOOLEAN AND b.email IS NOT NULL
               AND NOT (b.has_account AND b.email_pref = FALSE AND $${nextParam + 2}::TEXT = 'normal') THEN b.email
        END,
        CASE
          WHEN NOT $${nextParam + 1}::BOOLEAN THEN 'none'
          WHEN b.email IS NULL THEN 'no_address'
          WHEN b.has_account AND b.email_pref = FALSE AND $${nextParam + 2}::TEXT = 'normal' THEN 'skipped_pref'
          ELSE 'pending'
        END
      FROM base b
    `,
    [siteCode, ...audience.params, announcementId, sendEmail === true, importance],
  );
  const total = Number(insert.rowCount ?? 0);
  if (total === 0 || sendEmail !== true) {
    return { total, email: emptyEmailCounts() };
  }

  await db.query(
    `
      UPDATE announcement_recipients r
      SET email_status = 'duplicate', email = NULL
      FROM (
        SELECT person_id, ROW_NUMBER() OVER (PARTITION BY email ORDER BY person_id) AS rn
        FROM announcement_recipients
        WHERE announcement_id = $1 AND email_status = 'pending'
      ) d
      WHERE r.announcement_id = $1 AND r.person_id = d.person_id AND d.rn > 1
    `,
    [announcementId],
  );
  const pendingResult = await db.query(
    `SELECT COUNT(*)::INTEGER AS n FROM announcement_recipients WHERE announcement_id = $1 AND email_status = 'pending'`,
    [announcementId],
  );
  const deliverable = Number(pendingResult.rows?.[0]?.n ?? 0);
  if (enforceEmailLimit === true && deliverable > EMAIL_PER_PUBLISH_LIMIT) {
    throw emailLimitExceeded();
  }
  const allowance = Math.max(0, Math.min(EMAIL_PER_PUBLISH_LIMIT, dailyLimit - used));
  if (deliverable > allowance) {
    await db.query(
      `
        UPDATE announcement_recipients r
        SET email_status = 'capped', email = NULL
        FROM (
          SELECT person_id, ROW_NUMBER() OVER (ORDER BY person_id) AS rn
          FROM announcement_recipients
          WHERE announcement_id = $1 AND email_status = 'pending'
        ) c
        WHERE r.announcement_id = $1 AND r.person_id = c.person_id AND c.rn > $2
      `,
      [announcementId, allowance],
    );
  }
  return { total, email: emailCountsFromRows(await loadEmailStatusCounts(db, announcementId)) };
}
