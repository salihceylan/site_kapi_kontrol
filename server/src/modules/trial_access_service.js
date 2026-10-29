// Deneme erişim kodu hizmeti (P2-27, karar K10): demo site tanımı, kod üretimi / listeleme / iptal ve kodla oturum açma.
//
// GÜVENLİK
//  - Kodun kendisi saklanmaz: HMAC-SHA256 özeti + son 4 karakter. Üretilen kod YALNIZ üretim yanıtında bir kez görünür.
//  - Kullanım ATOMİKTİR: tek `UPDATE ... WHERE used_at IS NULL ...` (eşzamanlı ikinci kullanım 0 satır döner -> reddedilir); hesap
//    oluşturma aynı işlemdedir, başarısızlıkta işlem geri alınır ve kod yanmaz.
//  - Deneme hesabı gerçek bir users satırıdır: rol site_manager, e-posta `trial-<rastgele>@deneme.invalid`, parola özeti hiçbir
//    parolayla eşleşmez (parolayla giriş imkânsız). Tek bağı demo siteye yönetici bağıdır; erişim ilkesi auth_middleware.js'te
//    (trial_access_common.js evaluateTrialRequest) HER istekte uygulanır. Oturum 72 saattir: JWT süresi + veritabanı süresi.
//  - Süresi dolan / iptal edilen hesap kapatılır: kullanıcı pasife alınır, demo site yönetici bağı silinir (closeExpiredTrialAccounts).
import crypto from 'node:crypto';
import { pool } from '../db.js';
import { signAccessToken } from '../jwt.js';
import { mapUserRow } from '../utils/helpers.js';
import { actorFromAuthUser, recordAudit } from './audit_service.js';
import { PlatformError } from './errors.js';
import {
  DEMO_SITE_SETTING_KEY,
  TRIAL_CODE_DEFAULT_VALID_DAYS,
  TRIAL_CODE_MAX_VALID_DAYS,
  TRIAL_EMAIL_DOMAIN,
  TRIAL_MAX_ACTIVE_CODES,
  TRIAL_SESSION_HOURS,
  generateTrialCode,
  hashTrialCode,
  normalizeTrialCode,
  trialCodeHint,
} from './trial_access_common.js';

const NOTE_MAX = 200;
// eslint-disable-next-line no-control-regex
const CONTROL_RE = /[\u0000-\u001f\u007f-\u009f]/g;
const MAX_LIST = 100;

const err = {
  invalid: () => new PlatformError(401, 'TRIAL_CODE_INVALID', 'Deneme kodu geçersiz. Kodu kontrol edip tekrar deneyin.'),
  used: () => new PlatformError(401, 'TRIAL_CODE_USED', 'Bu deneme kodu daha önce kullanılmış. Her kod yalnızca bir kez kullanılabilir.'),
  expired: () => new PlatformError(401, 'TRIAL_CODE_EXPIRED', 'Bu deneme kodunun süresi dolmuş.'),
  revoked: () => new PlatformError(401, 'TRIAL_CODE_REVOKED', 'Bu deneme kodu iptal edilmiş.'),
  unavailable: () => new PlatformError(503, 'TRIAL_UNAVAILABLE', 'Deneme erişimi şu an açık değil. Lütfen daha sonra tekrar deneyin.'),
};

const positiveInt = (value) => {
  const n = Number(value);
  return Number.isSafeInteger(n) && n > 0 ? n : null;
};

const iso = (value) => {
  if (value === null || value === undefined) return null;
  const date = value instanceof Date ? value : new Date(value);
  return Number.isNaN(date.getTime()) ? null : date.toISOString();
};

/** Kodun durumu: active (kullanılabilir) | expired (kullanılmadan süresi doldu) | revoked (kullanılmadan iptal) | in_use (oturum sürüyor) | ended (oturum bitti / iptal). */
export function trialCodeStatus(row, now = Date.now()) {
  if (row.used_at) {
    const sessionEnd = new Date(row.session_expires_at).getTime();
    return row.revoked_at || !(sessionEnd > now) ? 'ended' : 'in_use';
  }
  if (row.revoked_at) return 'revoked';
  return new Date(row.expires_at).getTime() > now ? 'active' : 'expired';
}

export function mapTrialCodeRow(row, now = Date.now()) {
  return {
    id: Number(row.id),
    hint: row.code_hint,
    status: trialCodeStatus(row, now),
    note: row.note ?? null,
    site_code: Number(row.site_code),
    created_at: iso(row.created_at),
    created_by_name: row.created_by_name ?? null,
    expires_at: iso(row.expires_at),
    used_at: iso(row.used_at),
    session_expires_at: iso(row.session_expires_at),
    revoked_at: iso(row.revoked_at),
  };
}

function cleanNote(value) {
  if (value === undefined || value === null) return null;
  if (typeof value !== 'string') {
    throw new PlatformError(400, 'INVALID_BODY', 'Not metin olmalıdır.');
  }
  const text = value.replace(CONTROL_RE, ' ').replace(/\s+/g, ' ').trim();
  if (text.length > NOTE_MAX) {
    throw new PlatformError(400, 'INVALID_BODY', `Not en çok ${NOTE_MAX} karakter olabilir.`);
  }
  return text === '' ? null : text;
}

function cleanValidDays(value) {
  if (value === undefined || value === null || value === '') return TRIAL_CODE_DEFAULT_VALID_DAYS;
  const n = typeof value === 'number' ? value : Number(String(value).trim());
  if (!Number.isInteger(n) || n < 1 || n > TRIAL_CODE_MAX_VALID_DAYS) {
    throw new PlatformError(400, 'INVALID_BODY', `Geçerlilik 1 ile ${TRIAL_CODE_MAX_VALID_DAYS} gün arasında olmalıdır.`);
  }
  return n;
}

// ---------------------------------------------------------------------------
// Demo site
// ---------------------------------------------------------------------------

/** Güncel demo site kodu (yoksa null). */
export async function readDemoSiteCode(db = pool) {
  const result = await db.query(`SELECT value->>'site_code' AS site_code FROM platform_settings WHERE key = $1 LIMIT 1`, [DEMO_SITE_SETTING_KEY]);
  return positiveInt(result.rows?.[0]?.site_code);
}

/** Demo siteyi işaretler (enabled) ya da bu site demo ise işareti kaldırır. Aynı anda tek demo site vardır. */
export async function setDemoSite({ siteCode, enabled, actor, db = pool }) {
  const code = positiveInt(siteCode);
  if (code === null) throw new PlatformError(404, 'SITE_NOT_FOUND', 'Site bulunamadı.');
  if (typeof enabled !== 'boolean') {
    throw new PlatformError(400, 'INVALID_BODY', '"enabled" true ya da false olmalıdır.');
  }
  const site = await db.query(`SELECT site_code, name, approval_status FROM sites WHERE site_code = $1 LIMIT 1`, [code]);
  if (!site.rows?.[0]) throw new PlatformError(404, 'SITE_NOT_FOUND', 'Site bulunamadı.');
  const actorInfo = actorFromAuthUser(actor);
  if (enabled) {
    if (site.rows[0].approval_status !== 'approved') {
      throw new PlatformError(409, 'SITE_NOT_APPROVED', 'Yalnızca onaylı bir site demo site olarak işaretlenebilir.');
    }
    const previous = await readDemoSiteCode(db);
    await db.query(
      `INSERT INTO platform_settings (key, value, updated_at, updated_by)
       VALUES ($1, jsonb_build_object('site_code', $2::bigint), NOW(), $3)
       ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, updated_at = NOW(), updated_by = EXCLUDED.updated_by`,
      [DEMO_SITE_SETTING_KEY, code, actorInfo.userCode],
    );
    await recordAudit(db, {
      actor,
      action: 'trial_access.demo_site_set',
      siteCode: code,
      targetType: 'platform_settings',
      targetId: DEMO_SITE_SETTING_KEY,
      details: { previous_site_code: previous },
    });
  } else {
    const removed = await db.query(`DELETE FROM platform_settings WHERE key = $1 AND value->>'site_code' = $2 RETURNING key`, [DEMO_SITE_SETTING_KEY, String(code)]);
    if ((removed.rows?.length ?? 0) > 0) {
      await recordAudit(db, { actor, action: 'trial_access.demo_site_cleared', siteCode: code, targetType: 'platform_settings', targetId: DEMO_SITE_SETTING_KEY, details: {} });
    }
  }
  return { site_code: code, is_demo: (await readDemoSiteCode(db)) === code };
}

// ---------------------------------------------------------------------------
// Oturum hesaplarının kapatılması
// ---------------------------------------------------------------------------

/**
 * Süresi dolan ya da iptal edilen oturumların hesabını kapatır: kullanıcı pasife alınır (yalnız @deneme.invalid hesabı), demo
 * site yönetici bağı silinir, üyelik pasife alınır, kod satırı `closed_at` ile işaretlenir. Idempotent; kaç hesabın kapandığını döner.
 * Erişim zaten auth_middleware'de HER istekte süreye göre kesilir; bu adım yalnızca kalıntı yetkiyi temizler.
 */
export async function closeExpiredTrialAccounts(db = pool) {
  const result = await db.query(
    `
    WITH closing AS (
      UPDATE trial_access_codes
         SET closed_at = NOW()
       WHERE used_by IS NOT NULL
         AND closed_at IS NULL
         AND (session_expires_at <= NOW() OR revoked_at IS NOT NULL)
       RETURNING used_by, site_code
    ), deactivated AS (
      UPDATE users u
         SET is_active = FALSE, updated_at = NOW()
        FROM closing c
       WHERE u.user_code = c.used_by AND u.email LIKE $1 AND u.deleted_at IS NULL
       RETURNING u.user_code
    ), unlinked AS (
      DELETE FROM site_manager_sites s
       USING closing c
       WHERE s.manager_user_code = c.used_by AND s.site_code = c.site_code
       RETURNING s.manager_user_code
    ), memberships AS (
      UPDATE site_memberships m
         SET is_active = FALSE, updated_at = NOW()
        FROM closing c
       WHERE m.user_code = c.used_by AND m.site_code = c.site_code
       RETURNING m.user_code
    )
    SELECT (SELECT COUNT(*) FROM closing)::int AS closed
    `,
    [`%@${TRIAL_EMAIL_DOMAIN}`],
  );
  return Number(result.rows?.[0]?.closed ?? 0);
}

// ---------------------------------------------------------------------------
// Kod üretimi / listeleme / iptal (süper kullanıcı ve demo sitenin yöneticisi)
// ---------------------------------------------------------------------------

async function requireDemoSite(siteCode, db) {
  const code = positiveInt(siteCode);
  if (code === null) throw new PlatformError(404, 'SITE_NOT_FOUND', 'Site bulunamadı.');
  const demo = await readDemoSiteCode(db);
  if (demo !== code) {
    throw new PlatformError(409, 'NOT_DEMO_SITE', 'Bu site demo site olarak işaretli değil. Önce demo site olarak işaretleyin.');
  }
  return code;
}

/** Demo site görünümü: işaret durumu + kodlar (en yeni önce). Demo değilse kod listesi boş. */
export async function getTrialAccessView({ siteCode, db = pool }) {
  const code = positiveInt(siteCode);
  if (code === null) throw new PlatformError(404, 'SITE_NOT_FOUND', 'Site bulunamadı.');
  await closeExpiredTrialAccounts(db).catch(() => 0);
  const site = await db.query(`SELECT site_code FROM sites WHERE site_code = $1 LIMIT 1`, [code]);
  if (!site.rows?.[0]) throw new PlatformError(404, 'SITE_NOT_FOUND', 'Site bulunamadı.');
  const isDemo = (await readDemoSiteCode(db)) === code;
  let items = [];
  if (isDemo) {
    const rows = await db.query(
      `SELECT t.id, t.code_hint, t.site_code, t.created_at, t.expires_at, t.note, t.used_at, t.session_expires_at, t.revoked_at, u.full_name AS created_by_name
         FROM trial_access_codes t
         LEFT JOIN users u ON u.user_code = t.created_by
        WHERE t.site_code = $1
        ORDER BY t.id DESC
        LIMIT $2`,
      [code, MAX_LIST],
    );
    const now = Date.now();
    items = (rows.rows ?? []).map((row) => mapTrialCodeRow(row, now));
  }
  return { site_code: code, is_demo: isDemo, session_hours: TRIAL_SESSION_HOURS, max_active_codes: TRIAL_MAX_ACTIVE_CODES, items };
}

/** Yeni kod üretir. Düz kod YALNIZ bu dönüşte vardır. */
export async function createTrialCode({ siteCode, note, validDays, actor, db = pool }) {
  const code = await requireDemoSite(siteCode, db);
  const cleanedNote = cleanNote(note);
  const days = cleanValidDays(validDays);
  await closeExpiredTrialAccounts(db).catch(() => 0);
  const active = await db.query(`SELECT COUNT(*)::int AS n FROM trial_access_codes WHERE used_at IS NULL AND revoked_at IS NULL AND expires_at > NOW()`);
  if (Number(active.rows?.[0]?.n ?? 0) >= TRIAL_MAX_ACTIVE_CODES) {
    throw new PlatformError(409, 'TOO_MANY_ACTIVE_CODES', `Aynı anda en çok ${TRIAL_MAX_ACTIVE_CODES} kullanılmamış kod bulunabilir. Eski kodları iptal edin.`);
  }
  const actorInfo = actorFromAuthUser(actor);
  for (let attempt = 0; attempt < 5; attempt += 1) {
    const plain = generateTrialCode();
    const normalized = normalizeTrialCode(plain);
    const inserted = await db.query(
      `INSERT INTO trial_access_codes (code_hash, code_hint, site_code, created_by, expires_at, note)
       VALUES ($1, $2, $3, $4, NOW() + make_interval(days => $5), $6)
       ON CONFLICT (code_hash) DO NOTHING
       RETURNING id, code_hint, site_code, created_at, expires_at, note, used_at, session_expires_at, revoked_at`,
      [hashTrialCode(normalized), trialCodeHint(normalized), code, actorInfo.userCode, days, cleanedNote],
    );
    const row = inserted.rows?.[0];
    if (!row) continue;
    await recordAudit(db, {
      actor,
      action: 'trial_access.code_created',
      siteCode: code,
      targetType: 'trial_access_code',
      targetId: String(row.id),
      details: { valid_days: days, hint: row.code_hint, has_note: cleanedNote !== null },
    });
    return { code: plain, item: mapTrialCodeRow({ ...row, created_by_name: actor?.full_name ?? null }) };
  }
  throw new PlatformError(500, 'CODE_GENERATION_FAILED', 'Kod üretilemedi. Lütfen tekrar deneyin.');
}

/** Kodu iptal eder; kullanılmışsa süren oturum da biter. Idempotent. */
export async function revokeTrialCode({ siteCode, id, actor, db = pool }) {
  const code = positiveInt(siteCode);
  const codeId = positiveInt(id);
  if (code === null) throw new PlatformError(404, 'SITE_NOT_FOUND', 'Site bulunamadı.');
  if (codeId === null) throw new PlatformError(404, 'TRIAL_CODE_NOT_FOUND', 'Deneme kodu bulunamadı.');
  const updated = await db.query(
    `UPDATE trial_access_codes SET revoked_at = COALESCE(revoked_at, NOW())
      WHERE id = $1 AND site_code = $2
      RETURNING id, code_hint, site_code, created_at, expires_at, note, used_at, session_expires_at, revoked_at`,
    [codeId, code],
  );
  const row = updated.rows?.[0];
  if (!row) throw new PlatformError(404, 'TRIAL_CODE_NOT_FOUND', 'Deneme kodu bulunamadı.');
  await closeExpiredTrialAccounts(db).catch(() => 0);
  await recordAudit(db, {
    actor,
    action: 'trial_access.code_revoked',
    siteCode: code,
    targetType: 'trial_access_code',
    targetId: String(row.id),
    details: { was_used: Boolean(row.used_at) },
  });
  return { item: mapTrialCodeRow(row) };
}

// ---------------------------------------------------------------------------
// Kodla oturum açma
// ---------------------------------------------------------------------------

async function inTransaction(db, fn) {
  const client = typeof db.connect === 'function' ? await db.connect() : db;
  try {
    await client.query('BEGIN');
    const value = await fn(client);
    await client.query('COMMIT');
    return value;
  } catch (error) {
    await client.query('ROLLBACK').catch(() => {});
    throw error;
  } finally {
    if (client !== db) client.release();
  }
}

/** Kod neden kullanılamadı (talep atomik UPDATE ile 0 satır döndürdükten sonra): hata üretir. */
async function explainRejectedCode(client, hash) {
  const found = await client.query(`SELECT used_at, revoked_at, expires_at FROM trial_access_codes WHERE code_hash = $1 LIMIT 1`, [hash]);
  const row = found.rows?.[0];
  if (!row) throw err.invalid();
  if (row.used_at) throw err.used();
  if (row.revoked_at) throw err.revoked();
  if (new Date(row.expires_at).getTime() <= Date.now()) throw err.expired();
  throw err.unavailable(); // demo site değişmiş / kapatılmış
}

/**
 * Kodu kullanır: 72 saatlik deneme hesabını ve oturumunu üretir. Yanıt giriş yanıtıyla aynı biçimdedir (+ `trial`).
 * @returns {Promise<{ token: string, user: object, trial: { expires_at: string, session_hours: number, site_code: number, site_name: string } }>}
 */
export async function redeemTrialCode({ code, db = pool }) {
  const normalized = normalizeTrialCode(code);
  if (normalized === null) throw err.invalid();
  const hash = hashTrialCode(normalized);
  await closeExpiredTrialAccounts(db).catch(() => 0);

  const created = await inTransaction(db, async (client) => {
    // Demo site tanımlı değilse `site_code = NULL` hiçbir satırla eşleşmez: talep 0 satır döner ve aşağıda neden açıklanır
    // (geçersiz kod hep 401; geçerli kod için "deneme erişimi kapalı" 503).
    const demoSite = await readDemoSiteCode(client);
    const claim = await client.query(
      `UPDATE trial_access_codes
          SET used_at = NOW(), session_expires_at = NOW() + make_interval(hours => $2)
        WHERE code_hash = $1 AND used_at IS NULL AND revoked_at IS NULL AND expires_at > NOW() AND site_code = $3
        RETURNING id, site_code, session_expires_at`,
      [hash, TRIAL_SESSION_HOURS, demoSite],
    );
    const claimed = claim.rows?.[0];
    if (!claimed) await explainRejectedCode(client, hash);

    const site = await client.query(`SELECT site_code, name FROM sites WHERE site_code = $1 AND approval_status = 'approved' LIMIT 1`, [claimed.site_code]);
    if (!site.rows?.[0]) throw err.unavailable();

    const passwordHash = `!trial:${crypto.randomBytes(24).toString('hex')}`;
    const email = `trial-${crypto.randomBytes(8).toString('hex')}@${TRIAL_EMAIL_DOMAIN}`;
    const inserted = await client.query(
      `INSERT INTO users (full_name, email, role, is_active, email_verified, approval_status, password_hash)
       VALUES ($1, $2, 'site_manager', TRUE, TRUE, 'approved', $3)
       RETURNING user_code AS id, full_name, email, login_name, role, is_active, email_verified, approval_status, phone_number, created_at`,
      [`Deneme Kullanıcısı ${claimed.id}`, email, passwordHash],
    );
    const user = inserted.rows[0];
    await client.query(`INSERT INTO site_manager_sites (site_code, manager_user_code) VALUES ($1, $2) ON CONFLICT (site_code, manager_user_code) DO NOTHING`, [claimed.site_code, user.id]);
    await client.query(
      `INSERT INTO site_memberships (site_code, user_code, role, is_active) VALUES ($1, $2, 'SITE_ADMIN', TRUE)
       ON CONFLICT (site_code, user_code) DO UPDATE SET role = 'SITE_ADMIN', is_active = TRUE, updated_at = NOW()`,
      [claimed.site_code, user.id],
    );
    await client.query(`UPDATE trial_access_codes SET used_by = $1 WHERE id = $2`, [user.id, claimed.id]);
    await recordAudit(
      client,
      {
        actor: { id: user.id, full_name: user.full_name, role: user.role },
        action: 'trial_access.redeemed',
        siteCode: claimed.site_code,
        targetType: 'trial_access_code',
        targetId: String(claimed.id),
        details: { session_hours: TRIAL_SESSION_HOURS },
      },
      { inTransaction: true },
    );
    return { user, passwordHash, claimed, siteName: site.rows[0].name };
  });

  const expiresAt = new Date(created.claimed.session_expires_at);
  const secondsLeft = Math.max(1, Math.floor((expiresAt.getTime() - Date.now()) / 1000));
  const token = signAccessToken(created.user, { passwordHash: created.passwordHash, expiresInSeconds: secondsLeft });
  const trial = { siteCode: Number(created.claimed.site_code), expiresAt };
  return {
    token,
    user: mapUserRow({ ...created.user, must_change_password: false, trial }),
    trial: {
      expires_at: expiresAt.toISOString(),
      session_hours: TRIAL_SESSION_HOURS,
      site_code: Number(created.claimed.site_code),
      site_name: created.siteName,
    },
  };
}
