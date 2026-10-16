// Site yöneticisi olma (site başvurusu) servisi: bireysel kullanıcı site kurmak için BAŞVURU yapar, süper kullanıcı onaylar / reddeder.
//
// Sözleşme: docs/PLATFORM_SITE_BASVURUSU.md. Tablolar: site_applications, site_subscriptions, subscription_plans, platform_settings
// (migrations/033). Kalıp: modül talebi akışı (module_request_service.js).
//
// KİLİTLER ve SIRA (deadlock olmaması için hepsi AYNI sırada):
//  - başvuru oluşturma:  advisory `site_application:<kullanıcı>` -> (okumalar) -> INSERT. Kişi başına tek bekleyen başvuru ayrıca kısmi
//    tekil indeksle (uq_site_applications_pending) güvence altındadır.
//  - başvuru onayı:      (kilitsiz bakış: başvuran + cihaz kodu) -> advisory `site_application:<başvuran>` -> cihaz satırı FOR UPDATE ->
//    başvuran satırı FOR NO KEY UPDATE -> başvuru satırı FOR UPDATE -> yeni site satırları. Sıra CİHAZ -> KULLANICI -> BAŞVURU ve bu,
//    GERÇEK hesap silme akışıyla (DELETE /admin/users/:id: önce devices UPDATE, sonra site_manager_sites / üyelikler, EN SON users DELETE ->
//    başvuruda ON DELETE SET NULL) ile anlık kurulumun (cihaz FOR UPDATE -> UPDATE users) sırasıyla AYNIDIR: ters sıra deadlock'u olmaz.
//    Kullanıcı satırı başvuru satırından ÖNCE kilitlenir (silme de users'tan sonra başvuruya gider). FOR NO KEY UPDATE, FK denetimlerinin
//    (audit_log / site_applications -> users) KEY SHARE kilidiyle çakışmaz.
//  - iptal (başvuran):    kullanıcı satırı FOR NO KEY UPDATE -> başvuru satırı FOR UPDATE (aynı sıra; audit FK kilidi hesap silmeyle çakışmasın).
//  - ret (süper):         yalnız başvuru satırı FOR UPDATE (başvuran satırı kilitsiz okunur).
//  Aynı advisory anahtarı oluşturma ve onayda ortaktır: onay bitene dek aynı kişinin yeni başvurusu / rol okuması sıraya girer.
//
// GİZLİLİK: başvuran e-postası / telefonu yalnız süper kullanıcı yanıtındadır; audit `details` yalnız sayı ve bayrak taşır (not, gerekçe,
// e-posta YOK); e-posta adresleri log'a yazılmaz; e-posta gönderimi isteği BEKLETMEZ (fire-and-forget).

import { pool } from '../db.js';
import { sendSiteApplicationDecisionEmail, sendSiteApplicationNotificationEmail } from '../mailer.js';
import { normalizeSetupSiteInput, shouldPromoteToSiteManager } from '../services/membership_rules.js';
import { createSiteWithStructure, userHasOwnerLink } from '../services/site_setup_core.js';
import { actorFromAuthUser, recordAudit } from './audit_service.js';
import { PlatformError } from './errors.js';
import { resolveManagementTypeInput } from './management_types.js';
import {
  APPLICATION_DAILY_LIMIT,
  APPLICATION_NOTE_MAX,
  DECISION_NOTE_MAX,
  MINE_LIST_LIMIT,
  ONBOARDING_MODES,
  ONBOARDING_SETTING_KEY,
  applicantUnavailable,
  applicationNotFound,
  applicationNotPending,
  likePattern,
  mapApplicationRow,
  mapApprovedSite,
  normalizeDeviceUid,
  normalizeFreeText,
  onboardingModeOf,
  parseListLimit,
  parseOffset,
  parseSearch,
  parseStatusFilter,
  paymentNotAvailable,
  revalidateStoredStructure,
} from './site_application_common.js';

// ---------------------------------------------------------------------------
// Yardımcılar
// ---------------------------------------------------------------------------

function toPositiveInt(value, max = Number.MAX_SAFE_INTEGER) {
  const parsed = Number(value);
  return Number.isSafeInteger(parsed) && parsed > 0 && parsed <= max ? parsed : null;
}

const INT4_MAX = 2147483647;

/** Oluşturma ve onayda ORTAK advisory kilit anahtarı (kişi başına). */
export const applicationLockKey = (userCode) => `site_application:${userCode}`;

async function rollbackQuietly(client) {
  try {
    await client.query('ROLLBACK');
  } catch (_error) {
    // bağlantı zaten kopmuş olabilir; asıl hata yukarıda fırlatılır
  }
}

const alreadySiteManager = () =>
  new PlatformError(409, 'ALREADY_SITE_MANAGER', 'Zaten site yöneticisisiniz. Yeni site eklemek için Site Ekle seçeneğini kullanın.');
const forbiddenRole = () => new PlatformError(403, 'FORBIDDEN_ROLE', 'Bu işlem için yetkiniz yok.');

/**
 * Kim başvurabilir: bireysel / daire sahibi VE sahip bağı olmayan site yöneticisi (davetle yönetici olan, sitesi olmayan). Sahip bağı olan
 * site yöneticisi -> 409 ALREADY_SITE_MANAGER (Site Ekle'yi kullanır); süper kullanıcı ve diğer roller -> 403 FORBIDDEN_ROLE.
 * `hasOwnerLink`: site_manager için bağ durumu (DB'den; bilinmiyorsa verilmez = ön rol kontrolü, bağ ayrıca denetlenir).
 */
export function assertMayApply(role, { hasOwnerLink = false } = {}) {
  if (role === 'site_manager') {
    if (hasOwnerLink) {
      throw alreadySiteManager();
    }
    return;
  }
  if (!shouldPromoteToSiteManager(role)) {
    throw forbiddenRole();
  }
}

/**
 * Bu kullanıcı şu an anlık site kuramaz, site için BAŞVURMALI mı? Bireysel / daire sahibi ve sahip bağı olmayan site yöneticisi -> true;
 * sahip bağı olan yönetici, süper kullanıcı ve uygunsuz roller -> false. (GET mine yanıtındaki `requires_application`.)
 */
async function requiresApplication(db, userCode) {
  const roleResult = await db.query(`SELECT role FROM users WHERE user_code = $1 LIMIT 1`, [userCode]);
  const role = roleResult.rows?.[0]?.role;
  if (shouldPromoteToSiteManager(role)) {
    return true;
  }
  if (role === 'site_manager') {
    return !(await userHasOwnerLink(db, userCode));
  }
  return false;
}

/** normalizeSetupSiteInput 400 hatasını platform hata biçimine ({ error, code }) çevirir. */
function asPlatformValidationError(error) {
  if (error && error.expose === true && Number(error.statusCode) === 400 && typeof error.message === 'string') {
    return new PlatformError(400, 'INVALID_BODY', error.message);
  }
  return error;
}

// SELECT'ler. Başvuran görünümü `decision_source` / `decided_by` / başvuran bilgisi İÇERMEZ (gizlilik yapısal olarak sağlanır).
const APPLICANT_COLUMNS = `
  a.id, a.applicant_user_code, a.status, a.site_name, a.city, a.district, a.address, a.management_type,
  a.blocks, a.doors, a.block_count, a.apartment_count, a.door_count, a.device_uid, a.note, a.plan_code,
  a.payment_status, a.decided_at, a.decision_note, a.site_code, a.created_at
`;
const SELECT_APPLICANT_VIEW = `SELECT ${APPLICANT_COLUMNS} FROM site_applications a`;

// Süper kullanıcı görünümü: başvuran iletişimi, karar kaynağı / veren adı ve cihaz hâlâ başvuranın mı (kilitsiz anlık bakış; yalnız
// BEKLEYEN başvuruda anlamlıdır: onaylanmış başvuruda cihaz artık siteye bağlıdır, karar sonrası kayıtlarda her zaman false).
const SELECT_SUPER_VIEW = `
  SELECT
    ${APPLICANT_COLUMNS},
    a.decision_source,
    u.full_name AS applicant_name,
    u.email AS applicant_email,
    u.phone_number AS applicant_phone,
    u.role AS applicant_role,
    d.full_name AS decided_by_name,
    (
      a.status = 'pending'
      AND a.device_uid IS NOT NULL
      AND EXISTS (
        SELECT 1 FROM devices dv
        WHERE UPPER(dv.device_uid) = UPPER(a.device_uid)
          AND (dv.owner_user_id = u.id OR dv.assigned_user_code = a.applicant_user_code)
          AND dv.site_code IS NULL
      )
    ) AS device_available
  FROM site_applications a
  LEFT JOIN users u ON u.user_code = a.applicant_user_code
  LEFT JOIN users d ON d.user_code = a.decided_by
`;

async function loadApplicantView(applicationId, db = pool) {
  const result = await db.query(`${SELECT_APPLICANT_VIEW} WHERE a.id = $1 LIMIT 1`, [applicationId]);
  const row = result.rows?.[0];
  return row ? mapApplicationRow(row) : null;
}

async function loadSuperView(applicationId, db = pool) {
  const result = await db.query(`${SELECT_SUPER_VIEW} WHERE a.id = $1 LIMIT 1`, [applicationId]);
  const row = result.rows?.[0];
  return row ? mapApplicationRow(row, { forSuper: true }) : null;
}

/**
 * COMMIT SONRASI yeniden okuma: işlem zaten başarıyla işlendi; okuma hatası (bağlantı, zaman aşımı) 500'e çevrilmez. Hata yutulur
 * (yalnız kod loglanır) ve commit edilmiş verilerden hazırlanan asgari yanıt döner.
 */
async function reloadOr(loader, fallback) {
  try {
    const loaded = await loader();
    if (loaded) {
      return loaded;
    }
  } catch (error) {
    // eslint-disable-next-line no-console
    console.error('[site_application] sonuc yeniden okunamadi:', error?.code || 'hata');
  }
  return fallback();
}

// ---------------------------------------------------------------------------
// Bildirim (e-posta) — fire-and-forget; hata isteği bozmaz, adres log'a yazılmaz
// ---------------------------------------------------------------------------

function logMailFailure(label, error) {
  // SMTP hata iletileri alıcı adresini içerebilir: yalnız kod yazılır.
  // eslint-disable-next-line no-console
  console.error(`[site_application] ${label}:`, error?.code || error?.responseCode || 'hata');
}

/** Tüm AKTİF süper kullanıcılara yeni başvuru e-postası gönderir (her biri bağımsız). Başarılı gönderim sayısını döndürür. */
export async function notifySuperUsersOfApplication(application) {
  const result = await pool.query(
    `
      SELECT full_name, email
      FROM users
      WHERE role = 'super_user'
        AND is_active = TRUE
        AND email IS NOT NULL
        AND email <> ''
    `,
  );
  const recipients = result.rows ?? [];
  const outcomes = await Promise.allSettled(
    recipients.map((recipient) =>
      sendSiteApplicationNotificationEmail({
        to: recipient.email,
        fullName: recipient.full_name,
        siteName: application.site_name,
        applicantName: application.applicant_name,
        blockCount: application.block_count,
        apartmentCount: application.apartment_count,
        doorCount: application.door_count,
        note: application.note,
      }),
    ),
  );
  for (const outcome of outcomes) {
    if (outcome.status === 'rejected') {
      logMailFailure('bildirim e-postasi gonderilemedi', outcome.reason);
    }
  }
  return outcomes.filter((outcome) => outcome.status === 'fulfilled').length;
}

/** Başvurana karar e-postası (onay / ret). */
export async function notifyApplicantOfDecision(decision) {
  await sendSiteApplicationDecisionEmail(decision);
}

/** Test / entegrasyon kancaları: varsayılan gerçek e-posta gönderimidir. */
export const siteApplicationHooks = {
  notifyCreated: notifySuperUsersOfApplication,
  notifyDecided: notifyApplicantOfDecision,
};

function fireAndForget(label, hookName, payload) {
  Promise.resolve()
    .then(() => siteApplicationHooks[hookName](payload))
    .catch((error) => logMailFailure(label, error));
}

// ---------------------------------------------------------------------------
// Platform ayarı: site_onboarding
// ---------------------------------------------------------------------------

async function readOnboardingMode(db) {
  const result = await db.query(`SELECT value FROM platform_settings WHERE key = $1 LIMIT 1`, [ONBOARDING_SETTING_KEY]);
  return onboardingModeOf(result.rows?.[0]?.value);
}

function mapPlanRow(row) {
  return {
    code: row.code,
    name: row.name,
    is_active: row.is_active === true,
    price_minor: row.price_minor === null || row.price_minor === undefined ? null : Number(row.price_minor),
    currency: row.currency,
    billing_period: row.billing_period ?? null,
  };
}

/** GET /admin/platform-settings/site-onboarding: { mode, payment_available: false, plans }. */
export async function getSiteOnboardingSettings(db = pool) {
  const mode = await readOnboardingMode(db);
  const plans = await db.query(
    `
      SELECT code, name, is_active, price_minor, currency, billing_period
      FROM subscription_plans
      ORDER BY is_active DESC, code ASC
    `,
  );
  return { mode, payment_available: false, plans: (plans.rows ?? []).map(mapPlanRow) };
}

/**
 * PUT /admin/platform-settings/site-onboarding: yalnız `approval` kabul edilir; `payment` 409 PAYMENT_NOT_AVAILABLE (bugün seçilemez);
 * diğer değerler 400 INVALID_BODY. Audit `platform_settings.updated` (details: key, mode, previous_mode).
 */
export async function setSiteOnboardingMode({ mode, actor }) {
  const text = typeof mode === 'string' ? mode.trim() : '';
  if (!ONBOARDING_MODES.includes(text)) {
    throw new PlatformError(400, 'INVALID_BODY', 'mode approval olmalıdır.');
  }
  if (text === 'payment') {
    throw paymentNotAvailable();
  }
  const actorInfo = actorFromAuthUser(actor);

  const client = await pool.connect();
  let committed = false;
  try {
    await client.query('BEGIN');
    const previous = await client.query(`SELECT value FROM platform_settings WHERE key = $1 FOR UPDATE`, [ONBOARDING_SETTING_KEY]);
    const previousMode = previous.rows?.[0] ? onboardingModeOf(previous.rows[0].value) : null;
    await client.query(
      `
        INSERT INTO platform_settings (key, value, updated_at, updated_by)
        VALUES ($1, $2::jsonb, NOW(), $3)
        ON CONFLICT (key)
        DO UPDATE SET value = platform_settings.value || EXCLUDED.value, updated_at = NOW(), updated_by = EXCLUDED.updated_by
      `,
      [ONBOARDING_SETTING_KEY, JSON.stringify({ mode: text }), actorInfo.userCode],
    );
    await recordAudit(
      client,
      {
        actor: actorInfo,
        action: 'platform_settings.updated',
        targetType: 'platform_setting',
        targetId: ONBOARDING_SETTING_KEY,
        details: { key: ONBOARDING_SETTING_KEY, mode: text, previous_mode: previousMode },
      },
      { inTransaction: true },
    );
    await client.query('COMMIT');
    committed = true;
  } catch (error) {
    if (!committed) {
      await rollbackQuietly(client);
    }
    throw error;
  } finally {
    client.release();
  }
  return getSiteOnboardingSettings();
}

// ---------------------------------------------------------------------------
// Başvuran: oluştur / benim başvurularım / iptal
// ---------------------------------------------------------------------------

/**
 * POST /membership/site-applications. Hata sırası: yetki (rol) -> girdi doğrulaması (400) -> [transaction: taze rol, ödeme kipi, bekleyen
 * başvuru, günlük sınır, cihaz sahipliği]. Başvuruda cihaz KİLİTLENMEZ / AYRILMAZ (yalnız sahiplik doğrulanır).
 * @returns {Promise<object>} Application (başvuran görünümü)
 */
export async function createSiteApplication({ actor, body }) {
  const actorInfo = actorFromAuthUser(actor);
  const userCode = toPositiveInt(actorInfo.userCode, INT4_MAX);
  if (userCode === null) {
    throw new PlatformError(401, 'UNAUTHORIZED', 'Kullanıcı oturumu gereklidir.');
  }
  assertMayApply(actorInfo.role);
  if (actorInfo.role === 'site_manager') {
    // Sahip bağı olan yönetici başvuramaz (Site Ekle'yi kullanır): girdi doğrulamasından ÖNCE, salt-okunur ön kapı.
    assertMayApply(actorInfo.role, { hasOwnerLink: await userHasOwnerLink(pool, userCode) });
  }

  const source = body && typeof body === 'object' && !Array.isArray(body) ? body : {};
  const managementType = resolveManagementTypeInput(source.management_type ?? source.managementType);
  if (!managementType.ok) {
    throw new PlatformError(managementType.statusCode, managementType.code, managementType.error);
  }
  let input;
  try {
    input = normalizeSetupSiteInput({
      name: source.name,
      city: source.city,
      district: source.district,
      address: source.address,
      blocks: source.blocks,
      doors: source.doors,
      doorCount: source.doorCount,
    });
  } catch (error) {
    throw asPlatformValidationError(error);
  }
  const note = normalizeFreeText(source.note, 'Not', APPLICATION_NOTE_MAX);
  const deviceUid = normalizeDeviceUid(source.deviceUid ?? source.device_uid);

  const client = await pool.connect();
  let committed = false;
  let applicationId;
  let createdAt;
  let applicantName = actorInfo.name;
  try {
    await client.query('BEGIN');
    await client.query('SELECT pg_advisory_xact_lock(hashtext($1))', [applicationLockKey(userCode)]);

    // Taze rol (başka oturumda değişmiş / onaylanmış olabilir): oturum başındaki rol yerine bu transaction'da okunur.
    const userResult = await client.query(
      `SELECT id, user_code, role, full_name FROM users WHERE user_code = $1 LIMIT 1`,
      [userCode],
    );
    const user = userResult.rows?.[0];
    if (!user) {
      throw new PlatformError(404, 'USER_NOT_FOUND', 'Kullanıcı hesabı bulunamadı.');
    }
    assertMayApply(user.role, { hasOwnerLink: user.role === 'site_manager' ? await userHasOwnerLink(client, userCode) : false });
    applicantName = user.full_name ?? applicantName;

    if ((await readOnboardingMode(client)) === 'payment') {
      throw paymentNotAvailable();
    }

    const pendingResult = await client.query(
      `${SELECT_APPLICANT_VIEW} WHERE a.applicant_user_code = $1 AND a.status = 'pending' LIMIT 1`,
      [userCode],
    );
    if (pendingResult.rows?.[0]) {
      throw new PlatformError(409, 'APPLICATION_PENDING', 'Zaten inceleme bekleyen bir site başvurunuz var.', {
        application: mapApplicationRow(pendingResult.rows[0]),
      });
    }

    const dailyResult = await client.query(
      `
        SELECT COUNT(*)::INTEGER AS applied
        FROM site_applications
        WHERE applicant_user_code = $1 AND created_at > NOW() - INTERVAL '24 hours'
      `,
      [userCode],
    );
    if (Number(dailyResult.rows?.[0]?.applied ?? 0) >= APPLICATION_DAILY_LIMIT) {
      throw new PlatformError(
        409,
        'APPLICATION_DAILY_LIMIT',
        `Bugün en fazla ${APPLICATION_DAILY_LIMIT} başvuru yapabilirsiniz. Yarın tekrar deneyin.`,
      );
    }

    if (deviceUid !== null) {
      // Başvuruda cihaz KİLİTLENMEZ (FOR UPDATE yok): yalnız çağıranın cihazı olduğu doğrulanır; onayda yeniden doğrulanır.
      const deviceResult = await client.query(
        `SELECT id FROM devices WHERE UPPER(device_uid) = $1 AND (owner_user_id = $2 OR assigned_user_code = $3) LIMIT 1`,
        [deviceUid, user.id, user.user_code],
      );
      if (!deviceResult.rows?.[0]) {
        throw new PlatformError(404, 'DEVICE_NOT_FOUND', 'Belirtilen cihaz hesabınıza ait değil.');
      }
    }

    const insertResult = await client.query(
      `
        INSERT INTO site_applications (
          applicant_user_code, status, site_name, city, district, address, management_type,
          blocks, doors, block_count, apartment_count, door_count, device_uid, note, payment_status
        )
        VALUES ($1, 'pending', $2, $3, $4, $5, $6, $7::jsonb, $8::jsonb, $9, $10, $11, $12, $13, 'not_required')
        RETURNING id, created_at
      `,
      [
        userCode,
        input.siteName,
        input.city,
        input.district,
        input.address,
        managementType.value,
        JSON.stringify(input.blocks),
        JSON.stringify(input.doors),
        input.totalBlockCount,
        input.totalApartmentCount,
        input.totalDoorCount,
        deviceUid,
        note,
      ],
    );
    applicationId = toPositiveInt(insertResult.rows?.[0]?.id);
    createdAt = insertResult.rows?.[0]?.created_at ?? null;

    await recordAudit(
      client,
      {
        actor: actorInfo,
        action: 'site_application.created',
        targetType: 'site_application',
        targetId: String(applicationId),
        details: {
          block_count: input.totalBlockCount,
          apartment_count: input.totalApartmentCount,
          door_count: input.totalDoorCount,
          has_device: deviceUid !== null,
          has_note: note !== null,
        },
      },
      { inTransaction: true },
    );

    await client.query('COMMIT');
    committed = true;
  } catch (error) {
    if (!committed) {
      await rollbackQuietly(client);
    }
    if (error?.code === '23503') {
      // başvuran hesabı bu istekle eşzamanlı silindi (FK): sızdırmadan 404
      throw new PlatformError(404, 'USER_NOT_FOUND', 'Kullanıcı hesabı bulunamadı.');
    }
    if (error?.code === '23505') {
      // kısmi tekil indeks (advisory kilide rağmen çift bekleyen): bekleyen başvuru var
      const pending = await pool
        .query(`${SELECT_APPLICANT_VIEW} WHERE a.applicant_user_code = $1 AND a.status = 'pending' LIMIT 1`, [userCode])
        .catch(() => null);
      throw new PlatformError(
        409,
        'APPLICATION_PENDING',
        'Zaten inceleme bekleyen bir site başvurunuz var.',
        pending?.rows?.[0] ? { application: mapApplicationRow(pending.rows[0]) } : null,
      );
    }
    throw error;
  } finally {
    client.release();
  }

  // COMMIT edilmiş değerlerden asgari satır: yeniden okuma başarısız olsa da yanıt ve bildirim bundan hazırlanır (bildirim okumaya BAĞLI değil).
  const committedRow = {
    id: applicationId,
    applicant_user_code: userCode,
    status: 'pending',
    site_name: input.siteName,
    city: input.city,
    district: input.district,
    address: input.address,
    management_type: managementType.value,
    blocks: input.blocks,
    doors: input.doors,
    block_count: input.totalBlockCount,
    apartment_count: input.totalApartmentCount,
    door_count: input.totalDoorCount,
    device_uid: deviceUid,
    note,
    plan_code: null,
    payment_status: 'not_required',
    decided_at: null,
    decision_note: null,
    site_code: null,
    created_at: createdAt,
  };
  fireAndForget('bildirim basarisiz', 'notifyCreated', {
    id: applicationId,
    site_name: input.siteName,
    applicant_name: applicantName,
    block_count: input.totalBlockCount,
    apartment_count: input.totalApartmentCount,
    door_count: input.totalDoorCount,
    note,
  });
  return reloadOr(() => loadApplicantView(applicationId), () => mapApplicationRow(committedRow));
}

/**
 * GET /membership/site-applications/mine: { pending: Application|null, items: [son 10, yeniden eskiye], requires_application }. Yalnız çağıranın
 * kayıtları. `requires_application`: kullanıcı şu an anlık site kuramaz, başvurmalıdır (bekleyen başvurusu olsa da true kalır).
 */
export async function listMyApplications(userCode, db = pool) {
  const code = toPositiveInt(userCode, INT4_MAX);
  if (code === null) {
    return { pending: null, items: [], requires_application: false };
  }
  const items = await db.query(
    `${SELECT_APPLICANT_VIEW} WHERE a.applicant_user_code = $1 ORDER BY a.created_at DESC, a.id DESC LIMIT ${MINE_LIST_LIMIT}`,
    [code],
  );
  const pending = await db.query(
    `${SELECT_APPLICANT_VIEW} WHERE a.applicant_user_code = $1 AND a.status = 'pending' LIMIT 1`,
    [code],
  );
  return {
    pending: pending.rows?.[0] ? mapApplicationRow(pending.rows[0]) : null,
    items: (items.rows ?? []).map((row) => mapApplicationRow(row)),
    requires_application: await requiresApplication(db, code),
  };
}

/**
 * POST /membership/site-applications/:id/cancel — yalnız KENDİ bekleyen başvurusu. Başkasının / olmayan 404 APPLICATION_NOT_FOUND (IDOR);
 * bekleyen değilse 409 APPLICATION_NOT_PENDING.
 */
export async function cancelMyApplication({ applicationId, actor }) {
  const id = toPositiveInt(applicationId);
  const actorInfo = actorFromAuthUser(actor);
  const userCode = toPositiveInt(actorInfo.userCode, INT4_MAX);
  if (id === null || userCode === null) {
    throw applicationNotFound();
  }

  const client = await pool.connect();
  let committed = false;
  let cancelledRow;
  try {
    await client.query('BEGIN');
    // KİLİT SIRASI (onay ve hesap silme ile aynı): önce kullanıcı satırı, sonra başvuru satırı. Audit INSERT'i kullanıcı satırında
    // FK (KEY SHARE) kilidi ister; başvuru satırı elde tutulurken bunu beklemek, hesap silme (users -> başvuruda SET NULL) ile ters sıra
    // deadlock'u olurdu. FOR NO KEY UPDATE hesap silmeyi bekletir ama FK denetimleriyle çakışmaz.
    const owner = await client.query(`SELECT user_code FROM users WHERE user_code = $1 LIMIT 1 FOR NO KEY UPDATE`, [userCode]);
    if (!owner.rows?.[0]) {
      throw applicationNotFound();
    }
    const found = await client.query(
      `SELECT ${APPLICANT_COLUMNS} FROM site_applications a WHERE a.id = $1 AND a.applicant_user_code = $2 FOR UPDATE OF a`,
      [id, userCode],
    );
    const row = found.rows?.[0];
    if (!row) {
      throw applicationNotFound();
    }
    if (row.status !== 'pending') {
      throw applicationNotPending();
    }
    await client.query(
      `UPDATE site_applications SET status = 'cancelled', decided_at = NOW(), updated_at = NOW() WHERE id = $1`,
      [id],
    );
    await recordAudit(
      client,
      {
        actor: actorInfo,
        action: 'site_application.cancelled',
        targetType: 'site_application',
        targetId: String(id),
        details: {
          block_count: Number(row.block_count),
          apartment_count: Number(row.apartment_count),
          door_count: Number(row.door_count),
        },
      },
      { inTransaction: true },
    );
    await client.query('COMMIT');
    committed = true;
    cancelledRow = { ...row, status: 'cancelled', decided_at: new Date() };
  } catch (error) {
    if (!committed) {
      await rollbackQuietly(client);
    }
    throw error;
  } finally {
    client.release();
  }
  return reloadOr(() => loadApplicantView(id), () => mapApplicationRow(cancelledRow));
}

// ---------------------------------------------------------------------------
// Süper kullanıcı: listele / özet / ayrıntı
// ---------------------------------------------------------------------------

const ADMIN_FILTER_SQL = `
  ($1::TEXT IS NULL OR a.status = $1::TEXT)
  AND (
    $2::TEXT IS NULL
    OR a.site_name ILIKE $2::TEXT ESCAPE '!'
    OR a.city ILIKE $2::TEXT ESCAPE '!'
    OR u.full_name ILIKE $2::TEXT ESCAPE '!'
    OR u.email ILIKE $2::TEXT ESCAPE '!'
  )
`;

/** GET /admin/site-applications?status=&q=&limit=&offset= -> { items, total }. */
export async function listAdminApplications({ status, q, limit, offset } = {}, db = pool) {
  const filter = parseStatusFilter(status);
  const search = parseSearch(q);
  const pageSize = parseListLimit(limit);
  const skip = parseOffset(offset);
  const params = [filter === 'all' ? null : filter, search === null ? null : likePattern(search)];

  const result = await db.query(
    `
      ${SELECT_SUPER_VIEW}
      WHERE ${ADMIN_FILTER_SQL}
      ORDER BY a.created_at DESC, a.id DESC
      LIMIT $3 OFFSET $4
    `,
    [...params, pageSize, skip],
  );
  const countResult = await db.query(
    `
      SELECT COUNT(*)::INTEGER AS total
      FROM site_applications a
      LEFT JOIN users u ON u.user_code = a.applicant_user_code
      WHERE ${ADMIN_FILTER_SQL}
    `,
    params,
  );
  return {
    items: (result.rows ?? []).map((row) => mapApplicationRow(row, { forSuper: true })),
    total: Number(countResult.rows?.[0]?.total ?? 0),
  };
}

/**
 * GET /admin/site-applications/summary -> { pending } (çekmece rozeti; hafif). Başvuranı silinmiş (applicant NULL) bekleyen başvurular
 * ONAYLANAMAZ (APPLICANT_UNAVAILABLE) yalnız reddedilebilir; rozeti şişirmesin diye sayılmaz (liste yine gösterir).
 */
export async function getPendingSummary(db = pool) {
  const result = await db.query(
    `SELECT COUNT(*)::INTEGER AS pending FROM site_applications WHERE status = 'pending' AND applicant_user_code IS NOT NULL`,
  );
  return { pending: Number(result.rows?.[0]?.pending ?? 0) };
}

/** GET /admin/site-applications/:id -> Application (süper ek alanlarıyla). */
export async function getAdminApplication(applicationId, db = pool) {
  const id = toPositiveInt(applicationId);
  if (id === null) {
    throw applicationNotFound();
  }
  const application = await loadSuperView(id, db);
  if (!application) {
    throw applicationNotFound();
  }
  return application;
}

// ---------------------------------------------------------------------------
// Süper kullanıcı: onayla / reddet
// ---------------------------------------------------------------------------

/** Başvuran hâlâ kullanılabilir mi? (silinmiş / pasif / e-postası doğrulanmamış / abonelik onayı bekleyen-reddedilen hesap değil). */
export function isApplicantUnavailable(user) {
  return (
    !user ||
    user.is_active !== true ||
    user.email_verified === false ||
    user.approval_status === 'pending' ||
    user.approval_status === 'rejected'
  );
}

/**
 * POST /admin/site-applications/:id/approve — TEK transaction: başvuruyu kilitler, siteyi + bloklar/daireler/kapıları + yönetici üyeliğini
 * (ortak createSiteWithStructure) kurar, rolü site_manager yapar (süper değilse), cihaz hâlâ başvuranınsa 1. kapıya bağlar (değilse cihazsız),
 * site_subscriptions satırını (çekirdek) ekler, başvuruyu approved yapar ve audit yazar. Herhangi bir adım başarısızsa ROLLBACK (kalıntı yok).
 * @returns {Promise<{ application: object, site: object, device_attached: boolean }>}
 */
export async function approveSiteApplication({ applicationId, note, actor }) {
  const id = toPositiveInt(applicationId);
  if (id === null) {
    throw applicationNotFound();
  }
  const decisionNote = normalizeFreeText(note, 'Not', DECISION_NOTE_MAX);
  const actorInfo = actorFromAuthUser(actor);

  const client = await pool.connect();
  let committed = false;
  let created;
  let applicantMail;
  let siteName;
  let approvedRow;
  try {
    await client.query('BEGIN');

    // 0. Kilitsiz bakış: başvuran ve cihaz kodu (başvuru satırı değişmez alanlardır; kilit sırasını belirlemek için gerekir).
    const peek = await client.query(`SELECT applicant_user_code, device_uid FROM site_applications WHERE id = $1`, [id]);
    const peeked = peek.rows?.[0];
    if (!peeked) {
      throw applicationNotFound();
    }
    const applicantCode = toPositiveInt(peeked.applicant_user_code, INT4_MAX);
    if (applicantCode !== null) {
      // 1. Oluşturma ile ORTAK advisory kilit: onay bitene dek aynı kişinin yeni başvurusu / rol okuması sıraya girer.
      await client.query('SELECT pg_advisory_xact_lock(hashtext($1))', [applicationLockKey(applicantCode)]);
    }

    // 2. Cihaz satırı FOR UPDATE (varsa): sahiplik burada YENİDEN doğrulanır; artık başvuranın değilse (veya başka bir siteye bağlıysa)
    // site cihazsız kurulur. Sıra CİHAZ -> KULLANICI: gerçek hesap silme akışı ve anlık kurulumla aynı. Cihaz sorgusu başvuranın kimliğini
    // (users.id / user_code) gerektirdiğinden kullanıcı satırı burada KİLİTSİZ okunur; kilit bir sonraki adımdadır.
    let device = null;
    if (applicantCode !== null && peeked.device_uid) {
      const owner = await client.query(`SELECT id, user_code FROM users WHERE user_code = $1 LIMIT 1`, [applicantCode]);
      if (owner.rows?.[0]) {
        const deviceResult = await client.query(
          `SELECT * FROM devices WHERE UPPER(device_uid) = $1 AND (owner_user_id = $2 OR assigned_user_code = $3) AND site_code IS NULL LIMIT 1 FOR UPDATE`,
          [String(peeked.device_uid).toUpperCase(), owner.rows[0].id, owner.rows[0].user_code],
        );
        device = deviceResult.rows?.[0] ?? null;
      }
    }

    // 3. Başvuran satırı (FOR NO KEY UPDATE: rol güncellemesiyle aynı düzey, FK KEY SHARE kilitleriyle çakışmaz) — başvuru satırından ÖNCE
    // (hesap silme de users'tan sonra başvuru satırına gider). Taze kullanıcı durumu burada okunur.
    const userResult =
      applicantCode === null
        ? { rows: [] }
        : await client.query(
            `
              SELECT id, user_code, role, full_name, email, is_active, email_verified, approval_status
              FROM users
              WHERE user_code = $1
              LIMIT 1
              FOR NO KEY UPDATE
            `,
            [applicantCode],
          );
    const applicant = userResult.rows?.[0];

    // 4. Başvuru satırı FOR UPDATE: çift onay / onay x iptal yarışında ikinci istek burada bekler ve durumu yeniden görür.
    const found = await client.query(
      `
        SELECT ${APPLICANT_COLUMNS}, a.decision_source
        FROM site_applications a
        WHERE a.id = $1
        FOR UPDATE OF a
      `,
      [id],
    );
    const row = found.rows?.[0];
    if (!row) {
      throw applicationNotFound();
    }
    if (row.status !== 'pending') {
      throw applicationNotPending();
    }
    if (isApplicantUnavailable(applicant) || toPositiveInt(row.applicant_user_code, INT4_MAX) !== applicantCode) {
      throw applicantUnavailable();
    }
    // 5. Saklanan yapı TEKRAR doğrulanır (bozuk veri -> 422 APPLICATION_DATA_INVALID, hiçbir şey kurulmaz).
    const { input, managementType } = revalidateStoredStructure(row);

    // 6. Ortak site kurulumu (anlık kurulumla aynı işlev): site, sahip bağı ('owner'), bloklar / daireler / kapılar, cihaz, rol ve
    // abonelik satırı (source 'manual_approval' + application_id). Rolü zaten site_manager olan başvuranın rolü değişmez.
    created = await createSiteWithStructure(client, {
      user: applicant,
      input,
      managementType,
      device,
      subscription: { source: 'manual_approval', applicationId: id },
    });
    const siteCode = Number(created.site.id);

    // 7. Başvuru onaylandı.
    await client.query(
      `
        UPDATE site_applications
        SET status = 'approved', decision_source = 'super_user', decided_by = $2, decided_at = NOW(),
            decision_note = $3, site_code = $4, updated_at = NOW()
        WHERE id = $1
      `,
      [id, actorInfo.userCode, decisionNote, siteCode],
    );

    await recordAudit(
      client,
      {
        actor: actorInfo,
        action: 'site_application.approved',
        siteCode,
        targetType: 'site_application',
        targetId: String(id),
        details: {
          block_count: input.totalBlockCount,
          apartment_count: input.totalApartmentCount,
          door_count: input.totalDoorCount,
          device_attached: created.assignedDevice !== null,
        },
      },
      { inTransaction: true },
    );

    await client.query('COMMIT');
    committed = true;
    siteName = row.site_name;
    applicantMail = { to: applicant.email, fullName: applicant.full_name };
    approvedRow = {
      ...row,
      status: 'approved',
      decision_source: 'super_user',
      decided_at: new Date(),
      decision_note: decisionNote,
      site_code: siteCode,
      applicant_name: applicant.full_name,
      applicant_email: applicant.email,
      applicant_phone: null,
      applicant_role: applicant.role === 'super_user' ? 'super_user' : 'site_manager',
      decided_by_name: actorInfo.name,
      device_available: false,
    };
  } catch (error) {
    if (!committed) {
      await rollbackQuietly(client);
    }
    throw error;
  } finally {
    client.release();
  }

  const deviceAttached = created.assignedDevice !== null;
  if (applicantMail?.to) {
    fireAndForget('karar e-postasi basarisiz', 'notifyDecided', {
      to: applicantMail.to,
      fullName: applicantMail.fullName,
      siteName,
      approved: true,
      reason: null,
    });
  }
  return {
    application: await reloadOr(() => loadSuperView(id), () => mapApplicationRow(approvedRow, { forSuper: true })),
    site: mapApprovedSite(created, { deviceAttached }),
    device_attached: deviceAttached,
  };
}

/**
 * POST /admin/site-applications/:id/reject — başvuruyu reddeder (`reason` ≤ 300). Başvuran yeniden başvurabilir. Bekleyen değilse
 * 409 APPLICATION_NOT_PENDING. Audit `details` gerekçe metnini TAŞIMAZ (yalnız has_reason bayrağı).
 */
export async function rejectSiteApplication({ applicationId, reason, actor }) {
  const id = toPositiveInt(applicationId);
  if (id === null) {
    throw applicationNotFound();
  }
  const reasonText = normalizeFreeText(reason, 'Gerekçe', DECISION_NOTE_MAX);
  const actorInfo = actorFromAuthUser(actor);

  const client = await pool.connect();
  let committed = false;
  let applicantMail = null;
  let siteName;
  let rejectedRow;
  try {
    await client.query('BEGIN');
    const found = await client.query(
      `SELECT ${APPLICANT_COLUMNS}, a.decision_source FROM site_applications a WHERE a.id = $1 FOR UPDATE OF a`,
      [id],
    );
    const row = found.rows?.[0];
    if (!row) {
      throw applicationNotFound();
    }
    if (row.status !== 'pending') {
      throw applicationNotPending();
    }
    const applicantCode = toPositiveInt(row.applicant_user_code, INT4_MAX);
    if (applicantCode !== null) {
      const user = await client.query(`SELECT full_name, email FROM users WHERE user_code = $1 LIMIT 1`, [applicantCode]);
      if (user.rows?.[0]) {
        applicantMail = { to: user.rows[0].email, fullName: user.rows[0].full_name };
      }
    }
    await client.query(
      `
        UPDATE site_applications
        SET status = 'rejected', decision_source = 'super_user', decided_by = $2, decided_at = NOW(),
            decision_note = $3, updated_at = NOW()
        WHERE id = $1
      `,
      [id, actorInfo.userCode, reasonText],
    );
    await recordAudit(
      client,
      {
        actor: actorInfo,
        action: 'site_application.rejected',
        targetType: 'site_application',
        targetId: String(id),
        details: { has_reason: reasonText !== null },
      },
      { inTransaction: true },
    );
    await client.query('COMMIT');
    committed = true;
    siteName = row.site_name;
    rejectedRow = {
      ...row,
      status: 'rejected',
      decision_source: 'super_user',
      decided_at: new Date(),
      decision_note: reasonText,
      applicant_name: applicantMail?.fullName ?? null,
      applicant_email: applicantMail?.to ?? null,
      applicant_phone: null,
      applicant_role: null,
      decided_by_name: actorInfo.name,
      device_available: false,
    };
  } catch (error) {
    if (!committed) {
      await rollbackQuietly(client);
    }
    throw error;
  } finally {
    client.release();
  }

  if (applicantMail?.to) {
    fireAndForget('karar e-postasi basarisiz', 'notifyDecided', {
      to: applicantMail.to,
      fullName: applicantMail.fullName,
      siteName,
      approved: false,
      reason: reasonText,
    });
  }
  return reloadOr(() => loadSuperView(id), () => mapApplicationRow(rejectedRow, { forSuper: true }));
}
