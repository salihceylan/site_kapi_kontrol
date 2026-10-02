import { generateNumericCode } from '../utils/helpers.js';
import { PG_INT4_MAX, SITE_LIMITS, parsePositiveId } from '../utils/validators.js';

/**
 * Üyelik servisinin SAF (DB'siz) kuralları, SQL metinleri ve girdi normalizasyonu.
 * membership_service.js bu modülü kullanır; birim testleri DB/MQTT'ye bağlanmadan bu modülü test eder.
 */

/**
 * Kullanıcıya gösterilebilir (expose=true) tipli hata üretir.
 * Route katmanı yalnızca bu tür hataların mesajını istemciye döner; beklenmeyen (DB vb.)
 * hatalar için genel mesaj kullanır.
 */
export function httpError(statusCode, message) {
  const err = new Error(message);
  err.statusCode = statusCode;
  err.expose = true;
  return err;
}

// ---------------------------------------------------------------------------
// E-posta doğrulama kodu
// ---------------------------------------------------------------------------

export const VERIFICATION_CODE_DIGITS = 6;
// 30 dk: e-posta teslimi gecikebilir (gecikmiş kod kullanılamaz hâle gelmesin). Kaba kuvvet; kod başına 5 ve
// pencere (30 dk) başına 10 deneme sınırıyla engellenir, yani süre uzunluğu tahmin riskini artırmaz.
export const VERIFICATION_CODE_TTL_MINUTES = 30;
export const VERIFICATION_MAX_ATTEMPTS_PER_CODE = 5;
// Pencere içi toplam deneme: tekrar kod isteyerek deneme sayacı sıfırlanamaz.
export const VERIFICATION_WINDOW_MINUTES = 30;
export const VERIFICATION_MAX_ATTEMPTS_PER_WINDOW = 10;
export const VERIFICATION_RESEND_COOLDOWN_SECONDS = 30;
export const VERIFICATION_MAX_CODES_PER_HOUR = 10;

export function generateEmailVerificationCode() {
  return generateNumericCode(VERIFICATION_CODE_DIGITS);
}

/**
 * Kod biçimi: 6 haneli (yeni) veya geçiş dönemi için 4 haneli (6 haneli koda geçiş öncesinde üretilmiş;
 * bu satırlar bakım servisi tarafından 2 gün içinde silinir).
 */
export function isValidVerificationCodeFormat(code) {
  return /^\d{6}$/.test(String(code ?? '')) || /^\d{4}$/.test(String(code ?? ''));
}

/**
 * Atomik deneme hakkı alınamadığında nedenini sınıflandırır.
 */
export function classifyVerificationDenial({ hasActiveCode, codeAttempts, windowAttempts }) {
  if (!hasActiveCode) {
    return 'NO_ACTIVE_CODE';
  }
  if (Number(codeAttempts) >= VERIFICATION_MAX_ATTEMPTS_PER_CODE) {
    return 'CODE_ATTEMPTS_EXCEEDED';
  }
  if (Number(windowAttempts) >= VERIFICATION_MAX_ATTEMPTS_PER_WINDOW) {
    return 'WINDOW_ATTEMPTS_EXCEEDED';
  }
  return 'UNKNOWN';
}

export function verificationDenialError(reason) {
  switch (reason) {
    case 'NO_ACTIVE_CODE':
      return httpError(404, 'Aktif bir doğrulama kodu bulunamadı. Lütfen yeni kod talep ediniz.');
    case 'CODE_ATTEMPTS_EXCEEDED':
      return httpError(429, 'Çok fazla hatalı deneme yapıldı. Güvenliğiniz için lütfen yeni bir kod isteyiniz.');
    case 'WINDOW_ATTEMPTS_EXCEEDED':
      return httpError(
        429,
        `Çok fazla hatalı deneme yapıldı. Lütfen ${VERIFICATION_WINDOW_MINUTES} dakika sonra tekrar deneyiniz.`,
      );
    default:
      return httpError(429, 'Doğrulama isteği şu an işlenemiyor. Lütfen biraz sonra tekrar deneyiniz.');
  }
}

/**
 * Yeni kod üretimine izin verilip verilmediğini belirler (e-posta başına bekleme + saatlik tavan).
 */
export function decideVerificationIssue({ secondsSinceLast, codesLastHour }) {
  if (Number(codesLastHour) >= VERIFICATION_MAX_CODES_PER_HOUR) {
    return { allowed: false, reason: 'HOURLY_CAP' };
  }
  if (
    secondsSinceLast !== null &&
    secondsSinceLast !== undefined &&
    Number(secondsSinceLast) < VERIFICATION_RESEND_COOLDOWN_SECONDS
  ) {
    // Kalan süre yukarı yuvarlanır (en az 1 sn): istemciye dürüst bir geri sayım verilir.
    const retryAfterSeconds = Math.max(
      1,
      Math.ceil(VERIFICATION_RESEND_COOLDOWN_SECONDS - Number(secondsSinceLast)),
    );
    return { allowed: false, reason: 'COOLDOWN', retryAfterSeconds };
  }
  return { allowed: true, reason: null };
}

/**
 * Kod üretimi/gönderimi başarısız olduğunda (`issueVerificationCode` sonucu) istemciye dönecek tipli hata.
 * Kural: kod gerçekten gönderilmediyse yanıt ASLA başarı gibi görünmez ("gönderildi" denmez).
 * - MAIL_FAILED  -> 503 EMAIL_DELIVERY_FAILED (e-posta sunucusu kodu iletemedi; kullanıcı sonra yeniden dener)
 * - COOLDOWN     -> 429 (kalan saniye söylenir)
 * - HOURLY_CAP   -> 429
 */
export function verificationIssueError(result) {
  const reason = result?.reason;
  if (reason === 'COOLDOWN') {
    const seconds = Math.max(1, Math.ceil(Number(result?.retryAfterSeconds) || VERIFICATION_RESEND_COOLDOWN_SECONDS));
    return httpError(429, `Yeni kod istemek için lütfen ${seconds} saniye bekleyiniz.`);
  }
  if (reason === 'HOURLY_CAP') {
    return httpError(429, 'Bu e-posta adresi için çok fazla kod istendi. Lütfen daha sonra tekrar deneyiniz.');
  }
  const err = httpError(
    503,
    'Doğrulama kodu şu anda e-posta ile gönderilemiyor. Lütfen birkaç dakika sonra tekrar deneyiniz.',
  );
  err.code = 'EMAIL_DELIVERY_FAILED';
  return err;
}

// ---------------------------------------------------------------------------
// Bekleyen kayıt (pending_registrations)
// ---------------------------------------------------------------------------
// Bireysel self-servis kayıtta `users` satırı, e-posta sahipliği doğru kodla kanıtlanana kadar OLUŞTURULMAZ.
// Ad ve parola ÖZETİ (bcrypt; düz metin asla) bu tabloda bekler; doğrulamada tek işlemde users'a taşınır.

// Kimlik bilgileri (ad + parola özeti) YALNIZCA kod e-postası gerçekten gönderildikten sonra yazılır; reddedilen
// (429) veya başarısız (503) bir deneme bekleyen kaydı asla değiştirmez. $4 = bu isteğin kod satırı id'si:
// daha YENİ bir açık kod varsa (bu istek bayatladı) hiçbir şey yazılmaz, yeni isteğin kimlik bilgileri ezilmez.
// E-posta (büyük/küçük harf duyarsız) başına tek kayıt: tekrar kayıt ad/parola özetini günceller.
export const SQL_UPSERT_PENDING_REGISTRATION = `
  INSERT INTO pending_registrations (email, full_name, password_hash)
  SELECT $1::text, $2::text, $3::text
  WHERE NOT EXISTS (
    SELECT 1 FROM email_verifications
    WHERE LOWER(email) = LOWER($1) AND is_verified = FALSE AND id > $4
  )
  ON CONFLICT ((LOWER(email)))
  DO UPDATE SET full_name = EXCLUDED.full_name,
                password_hash = EXCLUDED.password_hash,
                updated_at = NOW()
`;

// Geçiş: bu sürümden önce açılmış doğrulanmamış bireysel hesap için aynı kural (gönderim sonrası, bayat değilse).
// $1 ad, $2 parola özeti, $3 user_code, $4 e-posta, $5 bu isteğin kod satırı id'si.
export const SQL_UPDATE_UNVERIFIED_USER_CREDENTIALS = `
  UPDATE users
  SET full_name = $1, password_hash = $2, updated_at = NOW()
  WHERE user_code = $3 AND email_verified = FALSE
    AND NOT EXISTS (
      SELECT 1 FROM email_verifications
      WHERE LOWER(email) = LOWER($4) AND is_verified = FALSE AND id > $5
    )
`;

// Giriş denemesi: bekleyen kaydın doğru parolasına eski "e-posta doğrulanmadı" (403) yanıtını verebilmek için.
export const SQL_FIND_PENDING_LOGIN_HASH = `
  SELECT password_hash FROM pending_registrations WHERE LOWER(email) = LOWER($1) LIMIT 1
`;

// Atomik alma: iki eşzamanlı doğrulama aynı kaydı iki kez alamaz.
export const SQL_TAKE_PENDING_REGISTRATION = `
  DELETE FROM pending_registrations
  WHERE LOWER(email) = LOWER($1)
  RETURNING full_name, password_hash
`;

// "Tekrar gönder" için: yalnızca ad (parola özeti gereksiz yere okunmaz).
export const SQL_FIND_PENDING_REGISTRATION = `
  SELECT full_name FROM pending_registrations WHERE LOWER(email) = LOWER($1) LIMIT 1
`;

/**
 * Atomik deneme hakkı: increment-first. Tek UPDATE ile
 *  - en son geçerli (VERIFICATION_CODE_TTL_MINUTES içinde, kullanılmamış) kod satırı seçilir,
 *  - satır başına ve pencere içi toplam deneme sınırı kontrol edilir,
 *  - sayaç artırılır.
 * Satır dönmezse deneme hakkı yoktur (veya aktif kod yoktur). Karşılaştırma bundan SONRA yapılır;
 * paralel isteklerle sınırı aşmak mümkün değildir (e-posta başına advisory lock ile birlikte).
 */
export const SQL_CLAIM_VERIFICATION_ATTEMPT = `
  UPDATE email_verifications ev
  SET attempt_count = ev.attempt_count + 1
  WHERE ev.id = (
          SELECT id
          FROM email_verifications
          WHERE LOWER(email) = LOWER($1)
            AND is_verified = FALSE
            AND created_at > NOW() - make_interval(mins => $2::int)
          ORDER BY created_at DESC, id DESC
          LIMIT 1
        )
    AND ev.is_verified = FALSE
    AND ev.attempt_count < $3::int
    AND (
      SELECT COALESCE(SUM(w.attempt_count), 0)
      FROM email_verifications w
      WHERE LOWER(w.email) = LOWER($1)
        AND w.created_at > NOW() - make_interval(mins => $4::int)
    ) < $5::int
  RETURNING ev.id, ev.code_hash, ev.attempt_count
`;

export const SQL_VERIFICATION_STATE = `
  SELECT
    (
      SELECT attempt_count
      FROM email_verifications
      WHERE LOWER(email) = LOWER($1)
        AND is_verified = FALSE
        AND created_at > NOW() - make_interval(mins => $2::int)
      ORDER BY created_at DESC, id DESC
      LIMIT 1
    ) AS code_attempts,
    (
      SELECT COALESCE(SUM(attempt_count), 0)
      FROM email_verifications
      WHERE LOWER(email) = LOWER($1)
        AND created_at > NOW() - make_interval(mins => $3::int)
    ) AS window_attempts
`;

// Kod doğru ise tek kullanımlık tüketim (çift tüketim 0 satır döner).
export const SQL_CONSUME_VERIFICATION_CODE = `
  UPDATE email_verifications
  SET is_verified = TRUE, verified_at = NOW()
  WHERE id = $1 AND is_verified = FALSE
  RETURNING id
`;

// Yeni kod üretilince eski kodlar geçersiz kılınır (verified_at NULL kalır: "doğrulandı" değil "yerine geçildi").
export const SQL_SUPERSEDE_VERIFICATION_CODES = `
  UPDATE email_verifications
  SET is_verified = TRUE
  WHERE LOWER(email) = LOWER($1) AND is_verified = FALSE
`;

// Yeni kod BAŞARIYLA gönderildikten sonra YALNIZCA daha eski açık kodlar geçersiz kılınır (id < $2). Daha yeni bir
// kod (yavaş bir gönderimin ardından gelen yeni istek) asla iptal edilmez. Gönderim başarısız olursa bu çalışmaz:
// kullanıcının elindeki (belki geç ulaşan) önceki geçerli kod boşuna iptal edilmez.
export const SQL_SUPERSEDE_OLDER_VERIFICATION_CODES = `
  UPDATE email_verifications
  SET is_verified = TRUE
  WHERE LOWER(email) = LOWER($1) AND is_verified = FALSE AND id < $2
`;

export const SQL_VERIFICATION_ISSUE_STATE = `
  SELECT
    (
      SELECT EXTRACT(EPOCH FROM (NOW() - MAX(created_at)))
      FROM email_verifications
      WHERE LOWER(email) = LOWER($1)
    ) AS seconds_since_last,
    (
      SELECT COUNT(*)
      FROM email_verifications
      WHERE LOWER(email) = LOWER($1)
        AND created_at > NOW() - INTERVAL '1 hour'
    ) AS codes_last_hour
`;

// ---------------------------------------------------------------------------
// Cihaz sahiplenme (claim)
// ---------------------------------------------------------------------------

/**
 * Atomik sahiplenme: yalnızca sahibi olmayan (ve arızalı işaretli olmayan) cihaz bu koşulla güncellenir.
 * 0 satır dönerse başka biri sahiplenmiştir (409) — kontrol ile güncelleme arasında yarış olamaz.
 */
export const SQL_CLAIM_DEVICE_ATOMIC = `
  UPDATE devices
  SET owner_user_id = $1, assigned_user_code = $2, claimed_at = NOW()
  WHERE id = $3
    AND owner_user_id IS NULL
    AND COALESCE(is_defective, FALSE) = FALSE
  RETURNING id, device_uid, hardware_type, gate_name, site_code, owner_user_id, claimed_at, is_defective
`;

/**
 * Rol yükseltme yalnızca sahiplenme anında yapılır (getMyClaimedDevices artık salt-okunurdur).
 */
export function shouldPromoteToSiteManager(role) {
  return role === 'individual' || role === 'apartment_owner';
}

const CLAIM_INPUT_MAX_LENGTH = 256;

/**
 * Kutu QR içeriğini cihaz UID'sine normalize eder:
 * "GD-C3-00861A0D5020", "00:86:1A:0D:50:20", "https://x/device/00861A0D5020", "DEVICE:..." -> "00861A0D5020".
 */
export function normalizeClaimDeviceInput(deviceInput) {
  const rawInput = String(deviceInput ?? '').trim();
  if (!rawInput) {
    throw httpError(400, 'Cihaz QR kodu veya seri numarası boş olamaz.');
  }
  if (rawInput.length > CLAIM_INPUT_MAX_LENGTH) {
    throw httpError(400, 'Cihaz QR kodu veya seri numarası çok uzun.');
  }
  const cleanUid = rawInput
    .replace(/^https?:\/\/[^/]+\/(?:device\/)?/i, '')
    .replace(/^GD-[A-Z0-9]+-/i, '')
    .replace(/^DEVICE:/i, '')
    .replace(/[:-]/g, '')
    .trim()
    .toUpperCase();
  return { rawInput, cleanUid };
}

// ---------------------------------------------------------------------------
// Daire üyeliği
// ---------------------------------------------------------------------------

/**
 * Üyelik aktif/pasif güncellemesinin hedefini belirler.
 *  - Üyelik satırı güncellendiyse: MEMBERSHIP
 *  - Satır yok ama hedef eski (legacy) tekil sakin ise: LEGACY_RESIDENT (yalnız apartments senkronu)
 *  - Aksi halde: NOT_FOUND (404) — global users.is_active ASLA güncellenmez.
 */
export function resolveToggleTarget({ membershipRowCount, legacyResidentMatches }) {
  if (Number(membershipRowCount) > 0) {
    return 'MEMBERSHIP';
  }
  if (legacyResidentMatches) {
    return 'LEGACY_RESIDENT';
  }
  return 'NOT_FOUND';
}

export function isLegacyResident(apartmentRow, targetUserCode) {
  const resident = apartmentRow?.resident_user_code;
  return resident !== null && resident !== undefined && Number(resident) === Number(targetUserCode);
}

/**
 * Sakini kalıcı silme: yalnızca süper kullanıcı ve site yöneticileri (yöntem yorumundaki niyet).
 */
export function canDeleteApartmentMember({ isSuperUser, isSiteManager }) {
  return Boolean(isSuperUser || isSiteManager);
}

/**
 * Aile reisi atanacak üyenin durumu: pasif/çıkarılmış üye yeniden aktifleştirilemez (409).
 */
export function assertPrimaryAdminCandidate(memberRow) {
  if (!memberRow) {
    throw httpError(404, 'Kullanıcı bu dairede kayıtlı değil.');
  }
  if (memberRow.is_active === false) {
    throw httpError(
      409,
      'Bu üye pasif veya daireden çıkarılmış. Önce üyeliği yeniden etkinleştirmeniz gerekir.',
    );
  }
}

/**
 * Kapı izni değişikliği erişimi daraltıyor mu? (reddet veya varsayılana dön) -> cihaz token'ı döndürülmeli.
 */
export function overrideRevokesAccess(isAllowed) {
  return isAllowed === null || isAllowed === undefined || isAllowed === false || isAllowed === 'false';
}

/**
 * Toplu kapı izni: kullanıcı listesini güvenli int4 aralığında tekilleştirir.
 */
export const MAX_BULK_USER_CODES = 5000;

export function sanitizeUserCodeList(list) {
  if (!Array.isArray(list)) {
    return [];
  }
  const out = new Set();
  for (const item of list) {
    const parsed = parsePositiveId(item, { max: PG_INT4_MAX });
    if (parsed !== null) {
      out.add(parsed);
    }
    if (out.size >= MAX_BULK_USER_CODES) {
      break;
    }
  }
  return [...out];
}

// Toplu yetkilendirmede blok/daire kapının sitesine ait olmalıdır (site_code filtresi).
export const SQL_BULK_APARTMENT_USERS = `
  SELECT DISTINCT u.user_code
  FROM apartments a
  LEFT JOIN apartment_memberships am ON am.apartment_id = a.id AND am.is_active = TRUE
  LEFT JOIN users u ON u.user_code = COALESCE(am.user_code, a.resident_user_code)
  WHERE a.id = $1 AND a.site_code = $2 AND u.user_code IS NOT NULL
`;

export const SQL_BULK_BLOCK_USERS = `
  SELECT DISTINCT u.user_code
  FROM apartments a
  LEFT JOIN apartment_memberships am ON am.apartment_id = a.id AND am.is_active = TRUE
  LEFT JOIN users u ON u.user_code = COALESCE(am.user_code, a.resident_user_code)
  WHERE a.block_id = $1 AND a.site_code = $2 AND a.is_active = TRUE AND u.user_code IS NOT NULL
`;

// ---------------------------------------------------------------------------
// Site kurulumu girdi normalizasyonu
// ---------------------------------------------------------------------------

export const SETUP_NAME_MAX = 120;
export const SETUP_LABEL_MAX = 60;
export const SETUP_TEXT_MAX = 200;
export const SETUP_ADDRESS_MAX = 300;

/**
 * Sayısal alanı güvenle ayrıştırır: boş/tanımsız -> varsayılan; geçersiz/aralık dışı -> 400.
 * (Eski kod parseInt(...) || 10 ile "12abc" gibi girdileri sessizce kabul ediyordu.)
 */
export function parseBoundedInteger(value, { min, max, defaultValue, label }) {
  if (value === undefined || value === null || (typeof value === 'string' && value.trim() === '')) {
    return defaultValue;
  }
  const parsed = typeof value === 'number' ? value : (/^-?\d{1,9}$/.test(String(value).trim()) ? Number(String(value).trim()) : Number.NaN);
  if (!Number.isSafeInteger(parsed) || parsed < min || parsed > max) {
    throw httpError(400, `${label} ${min} ile ${max} arasında bir tamsayı olmalıdır.`);
  }
  return parsed;
}

function optionalText(value, maxLength) {
  if (value === undefined || value === null) {
    return null;
  }
  const text = String(value).trim().slice(0, maxLength);
  return text || null;
}

export function normalizeSetupSiteInput({
  name,
  city,
  district,
  address,
  blocks,
  doors,
  doorCount = 1,
}) {
  const siteName = String(name ?? '').trim();
  if (!siteName) {
    throw httpError(400, 'Site adı zorunludur.');
  }
  if (siteName.length > SETUP_NAME_MAX) {
    throw httpError(400, `Site adı en fazla ${SETUP_NAME_MAX} karakter olabilir.`);
  }

  // Bloklar
  let blockList = Array.isArray(blocks) ? blocks : [];
  if (blockList.length === 0) {
    blockList = [{ name: 'A Blok', apartmentCount: 10 }];
  }
  if (blockList.length > SITE_LIMITS.maxBlocks) {
    throw httpError(400, `En fazla ${SITE_LIMITS.maxBlocks} blok tanımlanabilir.`);
  }

  const seenBlockNames = new Set();
  const normalizedBlocks = blockList.map((raw, idx) => {
    const src = raw !== null && typeof raw === 'object' ? raw : {};
    const fallbackName = `Blok ${idx + 1}`;
    const bName = String(src.name ?? '').trim().slice(0, SETUP_LABEL_MAX) || fallbackName;
    const dedupeKey = bName.toLocaleLowerCase('tr-TR');
    if (seenBlockNames.has(dedupeKey)) {
      throw httpError(400, `"${bName}" blok adı birden fazla kez kullanılmış. Blok adları benzersiz olmalıdır.`);
    }
    seenBlockNames.add(dedupeKey);
    const apartmentCount = parseBoundedInteger(src.apartmentCount, {
      min: 1,
      max: SITE_LIMITS.maxApartments,
      defaultValue: 10,
      label: 'Blok başına daire sayısı',
    });
    return { name: bName, apartmentCount, sortOrder: idx + 1 };
  });

  const totalApartmentCount = normalizedBlocks.reduce((sum, b) => sum + b.apartmentCount, 0);
  if (totalApartmentCount > SITE_LIMITS.maxApartments) {
    throw httpError(400, `Toplam daire sayısı en fazla ${SITE_LIMITS.maxApartments} olabilir.`);
  }

  // Kapılar
  let doorList = [];
  if (Array.isArray(doors) && doors.length > 0) {
    if (doors.length > SITE_LIMITS.maxDoors) {
      throw httpError(400, `En fazla ${SITE_LIMITS.maxDoors} kapı tanımlanabilir.`);
    }
    doorList = doors.map((d, idx) => {
      const rawName = d !== null && typeof d === 'object' ? d.name : d;
      const dName = String(rawName ?? '').trim().slice(0, SETUP_LABEL_MAX);
      return { name: dName || `Kapı ${idx + 1}`, doorIndex: idx + 1 };
    });
  } else {
    const count = parseBoundedInteger(doorCount, {
      min: 1,
      max: SITE_LIMITS.maxDoors,
      defaultValue: 1,
      label: 'Kapı sayısı',
    });
    for (let i = 1; i <= count; i += 1) {
      doorList.push({ name: `Kapı ${i}`, doorIndex: i });
    }
  }

  return {
    siteName,
    city: optionalText(city, SETUP_TEXT_MAX),
    district: optionalText(district, SETUP_TEXT_MAX),
    address: optionalText(address, SETUP_ADDRESS_MAX),
    blocks: normalizedBlocks,
    doors: doorList,
    totalBlockCount: normalizedBlocks.length,
    totalApartmentCount,
    totalDoorCount: doorList.length,
    blockApartmentCounts: normalizedBlocks.map((b) => b.apartmentCount),
  };
}
