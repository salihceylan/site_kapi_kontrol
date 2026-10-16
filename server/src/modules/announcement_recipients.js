// Duyuru kitlesi (alıcı anlık görüntüsü) ve yayın öncesi kitle önizlemesi.
//
// Sözleşme: docs/PLATFORM_DUYURU.md ("Kitle (alıcı) kuralı", "E-posta"). Kitle CRM kişileridir (hesapsızlar dahil): hedef (aktif)
// dairelerdeki GÜNCEL ilişkilere sahip AKTİF site_people kişileri, kişi başına TEK satır. E-posta adresi Faz 2'nin "etkin iletişim
// e-postası" mantığıyla (people_service.js CONTACT_EMAIL_SQL) bulunur; dahili @ahbu.local adresi hiçbir zaman adres sayılmaz.
// Bu dosya yalnız verilen db/client üzerinde çalışır (transaction'ı ÇAĞIRAN yönetir).
//
// E-posta durumları TEK bir INSERT ... SELECT içinde pencere fonksiyonlarıyla hesaplanır (UPDATE ... FROM (SELECT ... ROW_NUMBER())
// kalıbı büyük sitede karesel plan üretiyordu): kişi başına durum -> aynı adres tek kez -> adres başına günlük sınır -> site günlük kotası.

import { HAS_ACCOUNT_SQL } from './people_common.js';
import { CONTACT_EMAIL_SQL, PERSON_FROM } from './people_service.js';
import { INTERNAL_EMAIL_SUFFIX } from './people_sync_sql.js';
import { emailHashSalt, emailHashSalts } from './announcement_email_security.js';
import { ANNOUNCEMENT_LOCK_CLASS, ANNOUNCEMENT_LOCK_JOBS } from './announcement_lock.js';
import {
  DEFAULT_EMAIL_DAILY_LIMIT,
  EMAIL_PER_PUBLISH_LIMIT,
  announcementLimits,
  emailLimitExceeded,
  invalidTarget,
  istanbulDayRange,
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
    if (Object.hasOwn(counts, status) && status !== 'requested') {
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

/**
 * YALNIZ ASCII küçük harf (announcement_email_security.js normalizeAddress ile birebir aynı): PostgreSQL `lower()` ASCII dışı harflerde (Türkçe
 * İ / ı...) veritabanı yerel ayarına göre JS `toLowerCase()`'ten AYRIŞIR; kanonik özetin iki tarafta aynı çıkması için dönüşüm sabittir.
 */
export const asciiLowerSql = (column) => `translate(${column}, 'ABCDEFGHIJKLMNOPQRSTUVWXYZ', 'abcdefghijklmnopqrstuvwxyz')`;

/** Ham iletişim e-postası -> teslim edilebilir adres (ASCII küçük harf) ya da NULL (dahili @ahbu.local / biçim hatalı / çok uzun). */
export const deliverableEmailSql = (column) => `(
  CASE
    WHEN ${column} IS NULL THEN NULL
    WHEN ${asciiLowerSql(`btrim(${column})`)} LIKE '%${INTERNAL_EMAIL_SUFFIX}' THEN NULL
    WHEN char_length(btrim(${column})) > 254 THEN NULL
    WHEN btrim(${column}) !~ ${SAFE_EMAIL_PATTERN} THEN NULL
    ELSE ${asciiLowerSql(`btrim(${column})`)}
  END
)`;

/** Adresin tuzlu özeti (announcement_email_security.js hashEmail ile birebir aynı): tuz parametresi $saltIndex. */
export const emailHashSql = (saltParam, column) =>
  `encode(sha256(convert_to(${saltParam}::TEXT || ':' || ${column}, 'UTF8')), 'hex')`;

/**
 * KANONİK adres (announcement_email_security.js canonicalAddress ile birebir aynı kural): `+etiket` atılır; gmail.com / googlemail.com için
 * noktalar silinir ve alan adı gmail.com olur. Girdi ZATEN küçük harfli ve kırpılmış tek `@`'li adres olmalıdır (deliverableEmailSql çıktısı).
 * Etiketten / noktalardan sonra yerel kısım boş kalacaksa dokunulmaz.
 */
export const canonicalEmailSql = (column) => {
  const local = `split_part(${column}, '@', 1)`;
  const domain = `split_part(${column}, '@', 2)`;
  const stripped = `(CASE WHEN position('+' IN ${local}) > 1 THEN left(${local}, position('+' IN ${local}) - 1) ELSE ${local} END)`;
  return `(CASE WHEN ${domain} IN ('gmail.com', 'googlemail.com') THEN COALESCE(NULLIF(replace(${stripped}, '.', ''), ''), ${stripped}) || '@gmail.com' ELSE ${stripped} || '@' || ${domain} END)`;
};

/**
 * Adres (küçük harfli, kırpılmış) bastırma listesinde mi: GÜNCEL ve ESKİ sırlarla ($saltsParam TEXT[]) hesaplanan kanonik özetlerden biri
 * listede varsa true. Sır dönüşümünden önce yapılmış abonelikten çıkışlar eski özetle kayıtlıdır; eski sırlar PREVIOUS listesindeyken geçerlidir.
 */
export const suppressedSql = (addressExpr, saltsParam) =>
  `EXISTS (SELECT 1 FROM unnest(${saltsParam}::TEXT[]) AS salts(salt) INNER JOIN announcement_email_suppressions sup ON sup.email_hash = ${emailHashSql('salts.salt', canonicalEmailSql(addressExpr))})`;

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

/**
 * Yayından ÖNCE (kilit almadan) e-posta alıcı sınırı ön denetimi: teslim edilecek TEKİL adres sayısı (tercihi kapalı ve bastırılmış
 * adresler hariç, adres başına/site günlük kotası öncesi). Yönetici yayınında > 1000 ise 400 ANNOUNCEMENT_EMAIL_LIMIT: reddedilen yayın
 * site kişi kilidini hiç tutmaz. Kesin denetim yine işlem içinde (snapshotRecipients) yapılır; bu yalnız erken ve ucuz bir kapıdır.
 * @returns {Promise<number>} teslim edilecek tekil adres sayısı
 */
export async function assertDeliverableAddressLimit(db, siteCode, target, importance) {
  const audience = audienceCtes(target);
  const saltIndex = audience.params.length + 2;
  const saltsParam = `$${saltIndex + 2}`;
  const result = await db.query(
    `
      WITH ${audience.sql},
      hashed AS (
        SELECT b.person_id, b.has_account, b.email_pref, b.email, ${emailHashSql(`$${saltIndex}`, canonicalEmailSql('b.email'))} AS email_hash
        FROM base b
      )
      SELECT COUNT(DISTINCT h.email_hash)::INTEGER AS n
      FROM hashed h
      WHERE h.email IS NOT NULL
        AND NOT ${suppressedSql('h.email', saltsParam)}
        AND NOT (h.has_account AND h.email_pref = FALSE AND $${saltIndex + 1}::TEXT = 'normal')
    `,
    [siteCode, ...audience.params, emailHashSalt(), importance, emailHashSalts()],
  );
  const deliverable = Number(result.rows?.[0]?.n ?? 0);
  if (deliverable > EMAIL_PER_PUBLISH_LIMIT) {
    throw emailLimitExceeded();
  }
  return deliverable;
}

/**
 * Sitenin bugün (İstanbul takvim günü) kuyruğa alınmış/gönderilmiş e-posta sayısı: pending (gönderimi süren dahil) + sent.
 * failed SAYILMAZ (gönderilemeyen e-posta kotayı tüketmez); 'none' (iptal edilen) sayılmaz.
 */
export async function emailUsageToday(db, siteCode, now = new Date()) {
  const result = await db.query(
    `
      SELECT COUNT(*)::INTEGER AS used
      FROM announcement_recipients r
      INNER JOIN announcements a ON a.id = r.announcement_id
      WHERE a.site_code = $1
        AND a.published_at >= $2::TIMESTAMPTZ
        AND r.email_status IN ('pending', 'sent')
    `,
    [siteCode, istanbulDayRange(now).start.toISOString()],
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
 * Yayın anı alıcı anlık görüntüsü (çağıranın transaction'ında, site kişi kilidi ve eşitleme sonrası), TEK INSERT ... SELECT:
 *  1) kişi başına tek satır: e-posta istenmediyse 'none'; adres yok -> 'no_address'; adres bastırma listesinde (alıcı e-postadaki bağlantıyla
 *     çıkmış) ya da hesabı olan ve tercihi kapalı ve duyuru 'normal' -> 'skipped_pref' (acil, KİŞİ tercihini yok sayar; bastırmayı sayMAZ)
 *  2) aynı adres tek kez: ilk kişi (person_id sırası) devam eder, diğerleri 'duplicate'
 *  3) adres başına günlük sınır (TÜM siteler genelinde; pending + sent sayılır, İstanbul günü): dolu adres 'capped'. Sayım, adres başına
 *     indeks yoklayan ilişkili alt sorgudur (idx_announcement_recipients_email_hash), yayın günü kontrolü satır başına birincil anahtar
 *     araması yapan skaler alt sorgudur: gruplayıp birleştirmek ya da announcements ile JOIN etmek planlayıcının yanlış tahminle iç kolu her
 *     satır için yeniden çalıştırdığı karesel bir plana (QA'da ~1 sn; announcements büyüdükçe daha kötü) yol açtı, bu biçim plan seçimine bağlı değil.
 *  4) site günlük kotası / tek yayın sınırı: kalan kotayı aşan adresler 'capped'; kalanlar 'pending' (+ adres ve tuzlu özet satıra yazılır)
 *  5) yönetici yayınında (enforceEmailLimit) teslim edilecek adres (pending + capped) > 1000 ise 400 ANNOUNCEMENT_EMAIL_LIMIT (işlem geri alınır)
 * Adres sayımının yarışsız olması için e-postalı yayınlar küresel bir işlem kilidiyle sıralanır (kilit sırası: site kişi kilidi -> küresel).
 * @returns {Promise<{ total: number, email: object }>}
 */
export async function snapshotRecipients(
  db,
  {
    announcementId,
    siteCode,
    target,
    importance,
    sendEmail,
    enforceEmailLimit,
    dailyLimit = emailDailyLimit(),
    perAddressLimit = announcementLimits().perAddressDaily,
    now = new Date(),
  },
) {
  const send = sendEmail === true;
  let allowance = 0;
  if (send) {
    await db.query('SELECT pg_advisory_xact_lock($1::int, $2::int)', [ANNOUNCEMENT_LOCK_CLASS, ANNOUNCEMENT_LOCK_JOBS.emailGlobal]);
    // Günlük kullanım, bu duyurunun satırları EKLENMEDEN önce okunur (e-postalı yayınlar küresel kilitle sıralıdır).
    const used = await emailUsageToday(db, siteCode, now);
    allowance = Math.max(0, Math.min(EMAIL_PER_PUBLISH_LIMIT, dailyLimit - used));
  }
  const audience = audienceCtes(target);
  const next = audience.params.length + 2;
  const [pAnnouncement, pSend, pImportance, pSalt, pDayStart, pPerAddress, pAllowance, pSalts] = [0, 1, 2, 3, 4, 5, 6, 7].map((i) => `$${next + i}`);
  const salts = send ? emailHashSalts() : [];
  // SESSİZ TUZ GEÇİŞİ (F3): bastırma yalnız ESKİ bir tuzla kayıtlıysa aynı kayıt GÜNCEL tuzla da eklenir (ON CONFLICT DO NOTHING); böylece
  // PREVIOUS listesinden sır silinse de bastırma kaybolmaz. Yalnız eski sır tanımlıysa çalışır (veri değiştiren CTE; INSERT'ten bağımsız yürür).
  const migrateCte =
    salts.length > 1
      ? `,
      migrated AS (
        INSERT INTO announcement_email_suppressions (email_hash)
        SELECT DISTINCT h.email_hash
        FROM hashed h
        WHERE ${pSend}::BOOLEAN AND h.email IS NOT NULL
          AND NOT EXISTS (SELECT 1 FROM announcement_email_suppressions cur WHERE cur.email_hash = h.email_hash)
          AND ${suppressedSql('h.email', pSalts)}
        ON CONFLICT (email_hash) DO NOTHING
        RETURNING 1
      )`
      : '';
  const insert = await db.query(
    `
      WITH ${audience.sql},
      hashed AS (
        SELECT
          b.person_id, b.has_account, b.email_pref, b.email,
          CASE WHEN b.email IS NULL OR NOT ${pSend}::BOOLEAN THEN NULL ELSE ${emailHashSql(pSalt, canonicalEmailSql('b.email'))} END AS email_hash
        FROM base b
      )${migrateCte},
      classified AS (
        SELECT
          h.person_id, h.email, h.email_hash,
          CASE
            WHEN NOT ${pSend}::BOOLEAN THEN 'none'
            WHEN h.email IS NULL THEN 'no_address'
            WHEN ${suppressedSql('h.email', pSalts)} THEN 'skipped_pref'
            WHEN h.has_account AND h.email_pref = FALSE AND ${pImportance}::TEXT = 'normal' THEN 'skipped_pref'
            ELSE 'eligible'
          END AS st
        FROM hashed h
      ),
      ranked AS (
        SELECT
          c.*,
          ROW_NUMBER() OVER (PARTITION BY CASE WHEN c.st = 'eligible' THEN c.email_hash END ORDER BY c.person_id) AS addr_rn
        FROM classified c
      ),
      firsts AS (
        SELECT
          k.person_id, k.email, k.email_hash, k.st, k.addr_rn,
          CASE
            WHEN k.st = 'eligible' AND k.addr_rn = 1 THEN (
              SELECT COUNT(*)
              FROM announcement_recipients r
              WHERE r.email_hash = k.email_hash
                AND r.email_status IN ('pending', 'sent')
                AND (SELECT an.published_at FROM announcements an WHERE an.id = r.announcement_id) >= ${pDayStart}::TIMESTAMPTZ
            ) < ${pPerAddress}::INTEGER
            ELSE FALSE
          END AS in_quota
        FROM ranked k
      ),
      numbered AS (
        SELECT f.*, ROW_NUMBER() OVER (PARTITION BY f.in_quota ORDER BY f.person_id) AS cap_rn
        FROM firsts f
      ),
      final AS (
        SELECT
          n.person_id, n.email, n.email_hash,
          CASE
            WHEN n.st <> 'eligible' THEN n.st
            WHEN n.addr_rn > 1 THEN 'duplicate'
            WHEN NOT n.in_quota THEN 'capped'
            WHEN n.cap_rn <= ${pAllowance}::INTEGER THEN 'pending'
            ELSE 'capped'
          END AS final_status
        FROM numbered n
      )
      INSERT INTO announcement_recipients (announcement_id, person_id, email, email_hash, email_status)
      SELECT
        ${pAnnouncement}::BIGINT,
        f.person_id,
        CASE WHEN f.final_status = 'pending' THEN f.email END,
        CASE WHEN f.final_status = 'pending' THEN f.email_hash END,
        f.final_status
      FROM final f
    `,
    [
      siteCode,
      ...audience.params,
      announcementId,
      send,
      importance,
      // Tuz yalnız e-posta gerektiğinde hesaplanır (e-postasız yayın sır eksik / kısa olsa bile bozulmaz)
      send ? emailHashSalt() : '',
      istanbulDayRange(now).start.toISOString(),
      perAddressLimit,
      allowance,
      salts,
    ],
  );
  const total = Number(insert.rowCount ?? 0);
  if (total === 0 || !send) {
    return { total, email: emptyEmailCounts() };
  }
  const email = emailCountsFromRows(await loadEmailStatusCounts(db, announcementId));
  if (enforceEmailLimit === true && email.pending + email.capped > EMAIL_PER_PUBLISH_LIMIT) {
    throw emailLimitExceeded();
  }
  return { total, email };
}
