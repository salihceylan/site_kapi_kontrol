import bcrypt from 'bcryptjs';
import { pool } from '../db.js';
import { signAccessToken } from '../jwt.js';
import { sendIndividualVerificationEmail, sendJoinRequestNotificationEmail } from '../mailer.js';
import {
  currentPasswordLockedError,
  passwordChangeFailureTracker,
  passwordChangeThrottleKey,
} from '../middlewares/login_throttle.js';
import { mapUserRow, normalizeEmail } from '../utils/helpers.js';
import { PG_INT4_MAX, isValidEmail, parsePositiveId } from '../utils/validators.js';
import { rotateTokensForDevices, rotateTokensForSite } from './local_token_service.js';
import {
  SQL_BULK_APARTMENT_USERS,
  SQL_BULK_BLOCK_USERS,
  SQL_CLAIM_DEVICE_ATOMIC,
  SQL_CLAIM_VERIFICATION_ATTEMPT,
  SQL_CONSUME_VERIFICATION_CODE,
  SQL_SUPERSEDE_VERIFICATION_CODES,
  SQL_VERIFICATION_ISSUE_STATE,
  SQL_VERIFICATION_STATE,
  VERIFICATION_CODE_DIGITS,
  VERIFICATION_CODE_TTL_MINUTES,
  VERIFICATION_MAX_ATTEMPTS_PER_CODE,
  VERIFICATION_MAX_ATTEMPTS_PER_WINDOW,
  VERIFICATION_WINDOW_MINUTES,
  assertPrimaryAdminCandidate,
  canDeleteApartmentMember,
  classifyVerificationDenial,
  decideVerificationIssue,
  generateEmailVerificationCode,
  httpError,
  isLegacyResident,
  isValidVerificationCodeFormat,
  normalizeClaimDeviceInput,
  normalizeSetupSiteInput,
  overrideRevokesAccess,
  resolveToggleTarget,
  sanitizeUserCodeList,
  shouldPromoteToSiteManager,
  verificationDenialError,
} from './membership_rules.js';

const NAME_MAX_LENGTH = 80;
const PASSWORD_MAX_LENGTH = 128;
const NOTE_MAX_LENGTH = 500;

/**
 * Oturumdaki kullanıcı kodunu (user_code, int4) güvenle ayrıştırır.
 * Not: `users.id` (BIGSERIAL) ile `users.user_code` farklı kimliklerdir; sorgularda yalnızca user_code kullanılır.
 */
function parseUserCode(value) {
  return parsePositiveId(value, { max: PG_INT4_MAX });
}

function authUserCodeOf(authUser) {
  return parseUserCode(authUser?.userCode ?? authUser?.user_code ?? authUser?.id);
}

async function rollbackQuietly(client) {
  try {
    await client.query('ROLLBACK');
  } catch (_rollbackError) {
    // bağlantı zaten kopmuş olabilir; asıl hata yukarıda fırlatılır
  }
}

/**
 * E-posta doğrulama kodu üretir ve gönderir.
 * - E-posta başına advisory lock + bekleme süresi (30 sn) + saatlik tavan: kod/e-posta seli engellenir.
 * - Eski kodlar yeni kod üretilince geçersiz kılınır (tek geçerli kod).
 * - Mail hatası fırlatılmaz (kullanıcı "tekrar gönder" yapabilir); { sent, reason } döner.
 */
async function issueVerificationCode({ email, fullName }) {
  const client = await pool.connect();
  let code;
  try {
    await client.query('BEGIN');
    await client.query('SELECT pg_advisory_xact_lock(hashtext($1))', [`email_verify:${email}`]);

    const stateRes = await client.query(SQL_VERIFICATION_ISSUE_STATE, [email]);
    const state = stateRes.rows[0] || {};
    const decision = decideVerificationIssue({
      secondsSinceLast:
        state.seconds_since_last === null || state.seconds_since_last === undefined
          ? null
          : Number(state.seconds_since_last),
      codesLastHour: Number(state.codes_last_hour || 0),
    });
    if (!decision.allowed) {
      await client.query('ROLLBACK');
      return { sent: false, reason: decision.reason };
    }

    code = generateEmailVerificationCode();
    const codeHash = await bcrypt.hash(code, 10);

    await client.query(SQL_SUPERSEDE_VERIFICATION_CODES, [email]);
    await client.query(
      `INSERT INTO email_verifications (email, code_hash, attempt_count, is_verified) VALUES ($1, $2, 0, FALSE)`,
      [email, codeHash],
    );
    await client.query('COMMIT');
  } catch (error) {
    await rollbackQuietly(client);
    throw error;
  } finally {
    client.release();
  }

  try {
    await sendIndividualVerificationEmail({ to: email, fullName, code });
  } catch (mailError) {
    console.error('[Mail Gönderim Hatası]:', mailError?.message);
    // Mail sunucusu geçici hata verse bile kod üretilmiştir; kullanıcı 'Tekrar Kod Gönder' yapabilir.
    return { sent: false, reason: 'MAIL_FAILED' };
  }
  return { sent: true, reason: null };
}

/**
 * Yeni Bireysel Kullanıcı Kaydı (Self-Service)
 * - Ad, Soyad, E-posta, Şifre alır.
 * - E-posta doğrulanana kadar email_verified = FALSE kalır.
 * - 6 haneli (CSPRNG) kod üretip kullanıcının e-postasına gönderir.
 */
export async function registerIndividualUser({
  firstName,
  lastName,
  email,
  password,
}) {
  const cleanFirstName = String(firstName || '').trim();
  const cleanLastName = String(lastName || '').trim();
  const cleanEmail = normalizeEmail(email);
  const cleanPassword = String(password || '').trim();

  if (!cleanFirstName || !cleanLastName) {
    throw httpError(400, 'Ad ve soyad alanları zorunludur.');
  }
  if (cleanFirstName.length > NAME_MAX_LENGTH || cleanLastName.length > NAME_MAX_LENGTH) {
    throw httpError(400, `Ad ve soyad en fazla ${NAME_MAX_LENGTH} karakter olabilir.`);
  }
  if (!isValidEmail(cleanEmail)) {
    throw httpError(400, 'Geçerli bir e-posta adresi giriniz.');
  }
  if (cleanPassword.length < 6) {
    throw httpError(400, 'Şifre en az 6 karakter olmalıdır.');
  }
  if (cleanPassword.length > PASSWORD_MAX_LENGTH) {
    throw httpError(400, `Şifre en fazla ${PASSWORD_MAX_LENGTH} karakter olabilir.`);
  }

  const fullName = `${cleanFirstName} ${cleanLastName}`;
  const alreadyRegisteredError = () =>
    httpError(409, 'Bu e-posta adresiyle zaten kayıtlı ve doğrulanmış bir hesap bulunmaktadır.');

  // Mevcut kullanıcı kontrolü
  const existingRes = await pool.query(
    `SELECT user_code, email, email_verified, role FROM users WHERE LOWER(email) = LOWER($1) LIMIT 1`,
    [cleanEmail],
  );

  const passwordHash = await bcrypt.hash(cleanPassword, 10);

  if (existingRes.rowCount > 0) {
    const existing = existingRes.rows[0];
    if (existing.email_verified) {
      throw alreadyRegisteredError();
    }
    // Yalnızca self-servis (individual) doğrulanmamış hesaplar yeniden kaydedilebilir;
    // başka rolde bekleyen bir hesabın şifresi bu uçtan ezilemez. Aktiflik (is_active) durumuna dokunulmaz.
    if (existing.role !== 'individual') {
      throw alreadyRegisteredError();
    }
    await pool.query(
      `UPDATE users SET full_name = $1, password_hash = $2, updated_at = NOW() WHERE user_code = $3 AND email_verified = FALSE`,
      [fullName, passwordHash, existing.user_code],
    );
  } else {
    try {
      await pool.query(
        `
          INSERT INTO users (
            full_name,
            email,
            role,
            is_active,
            email_verified,
            approval_status,
            password_hash
          )
          VALUES ($1, $2, 'individual', TRUE, FALSE, 'approved', $3)
        `,
        [fullName, cleanEmail, passwordHash],
      );
    } catch (insertError) {
      // Eşzamanlı kayıt yarışı: aynı e-posta ile başka bir istek az önce ekledi.
      if (insertError?.code === '23505') {
        throw alreadyRegisteredError();
      }
      throw insertError;
    }
  }

  await issueVerificationCode({ email: cleanEmail, fullName });

  return {
    ok: true,
    message: `Kayıt başarılı. ${VERIFICATION_CODE_DIGITS} haneli doğrulama kodunuz e-posta adresinize gönderildi.`,
    email: cleanEmail,
    code_length: VERIFICATION_CODE_DIGITS,
  };
}

/**
 * E-posta Doğrulama Kodu Onaylama (6 haneli; geçiş için eski 4 haneli kodlar da <=10 dk kabul edilir)
 *
 * Güvenlik:
 * - Deneme hakkı ATOMİK alınır (UPDATE ... SET attempt_count = attempt_count + 1 ... RETURNING) ve
 *   karşılaştırmadan ÖNCE sayılır; paralel isteklerle sınır aşılamaz.
 * - Kod başına 5, e-posta başına pencere (30 dk) içinde toplam 10 deneme (yeni kod istemek sayacı sıfırlamaz).
 * - Kod 10 dk geçerlidir; yeni kod üretilince eskileri geçersizdir; doğru kod tek kullanımlıktır.
 * - Karşılaştırma bcrypt.compare ile yapılır (bcryptjs hash karşılaştırması sabit zamanlıdır).
 */
export async function verifyIndividualEmailCode({ email, code }) {
  const cleanEmail = normalizeEmail(email);
  const cleanCode = String(code ?? '').trim();

  if (!cleanEmail || !cleanCode) {
    throw httpError(400, 'E-posta ve doğrulama kodu zorunludur.');
  }
  if (!isValidEmail(cleanEmail)) {
    throw httpError(400, 'Geçerli bir e-posta adresi giriniz.');
  }
  if (!isValidVerificationCodeFormat(cleanCode)) {
    throw httpError(400, `Doğrulama kodu ${VERIFICATION_CODE_DIGITS} haneli sayı olmalıdır.`);
  }

  const client = await pool.connect();
  let committed = false;
  let user;
  try {
    await client.query('BEGIN');
    // Aynı e-posta için doğrulama istekleri sıraya girer (sayaç/pencere kontrolü yarışsız olur).
    await client.query('SELECT pg_advisory_xact_lock(hashtext($1))', [`email_verify:${cleanEmail}`]);

    const claim = await client.query(SQL_CLAIM_VERIFICATION_ATTEMPT, [
      cleanEmail,
      VERIFICATION_CODE_TTL_MINUTES,
      VERIFICATION_MAX_ATTEMPTS_PER_CODE,
      VERIFICATION_WINDOW_MINUTES,
      VERIFICATION_MAX_ATTEMPTS_PER_WINDOW,
    ]);

    if (claim.rowCount === 0) {
      const stateRes = await client.query(SQL_VERIFICATION_STATE, [
        cleanEmail,
        VERIFICATION_CODE_TTL_MINUTES,
        VERIFICATION_WINDOW_MINUTES,
      ]);
      const state = stateRes.rows[0] || {};
      const hasActiveCode = state.code_attempts !== null && state.code_attempts !== undefined;
      await client.query('COMMIT');
      committed = true;
      throw verificationDenialError(
        classifyVerificationDenial({
          hasActiveCode,
          codeAttempts: Number(state.code_attempts || 0),
          windowAttempts: Number(state.window_attempts || 0),
        }),
      );
    }

    const record = claim.rows[0];
    const isMatch = await bcrypt.compare(cleanCode, record.code_hash);
    if (!isMatch) {
      // Artırılan sayaç kalıcı olmalı: ROLLBACK değil COMMIT.
      await client.query('COMMIT');
      committed = true;
      throw httpError(400, `Girdiğiniz ${VERIFICATION_CODE_DIGITS} haneli kod hatalıdır.`);
    }

    // Kodu tek kullanımlık tüket (çift tüketim 0 satır döner)
    const consumed = await client.query(SQL_CONSUME_VERIFICATION_CODE, [record.id]);
    if (consumed.rowCount === 0) {
      throw httpError(400, 'Bu doğrulama kodu zaten kullanılmış. Lütfen yeni kod talep ediniz.');
    }
    // Aynı e-posta için varsa diğer açık kodları da kapat
    await client.query(SQL_SUPERSEDE_VERIFICATION_CODES, [cleanEmail]);

    // Kullanıcıyı email_verified = TRUE yap
    const userRes = await client.query(
      `
        UPDATE users
        SET email_verified = TRUE
        WHERE LOWER(email) = LOWER($1)
        RETURNING
          user_code AS id,
          user_code,
          full_name,
          email,
          login_name,
          role,
          is_active,
          email_verified,
          approval_status,
          phone_number,
          created_at,
          password_hash
      `,
      [cleanEmail],
    );
    if (userRes.rowCount === 0) {
      throw httpError(404, 'Kullanıcı hesabı bulunamadı.');
    }
    user = userRes.rows[0];

    // Bekleyen site yöneticisi davetleri var mı kontrol et (aynı işlem içinde: ya hep ya hiç)
    const pendingMgrInvRes = await client.query(
      `SELECT id, site_code FROM site_manager_invitations WHERE LOWER(email) = LOWER($1) AND status = 'PENDING' AND expires_at > NOW() FOR UPDATE`,
      [cleanEmail],
    );

    if (pendingMgrInvRes.rowCount > 0) {
      for (const inv of pendingMgrInvRes.rows) {
        await client.query(
          `INSERT INTO site_manager_sites (site_code, manager_user_code) VALUES ($1, $2) ON CONFLICT DO NOTHING`,
          [Number(inv.site_code), user.user_code],
        );
        await client.query(
          `INSERT INTO site_memberships (site_code, user_code, role, is_active) VALUES ($1, $2, 'SITE_ADMIN', TRUE)
           ON CONFLICT (site_code, user_code) DO UPDATE SET role = 'SITE_ADMIN', is_active = TRUE, updated_at = NOW()`,
          [Number(inv.site_code), user.user_code],
        );
        await client.query(
          `UPDATE site_manager_invitations SET status = 'ACCEPTED' WHERE id = $1 AND status = 'PENDING'`,
          [Number(inv.id)],
        );
      }
      // Kullanıcının rolünü site_manager yap
      if (user.role !== 'super_user') {
        await client.query(
          `UPDATE users SET role = 'site_manager' WHERE user_code = $1`,
          [user.user_code],
        );
        user.role = 'site_manager';
      }
    }

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

  // pv (parola sürümü) claim'i için güncel parola hash'i verilir; hash istemciye ASLA dönmez.
  const token = signAccessToken(user, { passwordHash: user.password_hash });
  delete user.password_hash;

  return {
    ok: true,
    message: 'E-posta adresiniz başarıyla doğrulandı. Hesabınız aktif!',
    token,
    user: mapUserRow(user),
  };
}

// Kullanıcı varlığından bağımsız tek yanıt (hesap/doğrulanmışlık sızdırılmaz).
const RESEND_GENERIC_MESSAGE =
  `İsteğiniz alındı. Doğrulanmamış bir hesap varsa yeni ${VERIFICATION_CODE_DIGITS} haneli doğrulama kodu e-posta adresinize gönderilecektir.`;

/**
 * E-posta Doğrulama Kodunu Tekrar Gönder
 * Yanıt kullanıcı varlığından / doğrulanmışlığından / bekleme süresinden bağımsızdır (enumeration kapalı).
 */
export async function resendIndividualVerificationCode({ email }) {
  const cleanEmail = normalizeEmail(email);
  if (!cleanEmail) {
    throw httpError(400, 'E-posta adresi gereklidir.');
  }
  if (!isValidEmail(cleanEmail)) {
    throw httpError(400, 'Geçerli bir e-posta adresi giriniz.');
  }

  const userRes = await pool.query(
    `SELECT user_code, full_name, email_verified FROM users WHERE LOWER(email) = LOWER($1) LIMIT 1`,
    [cleanEmail],
  );

  const user = userRes.rows[0];
  if (user && !user.email_verified) {
    // Yanıt süresi hesap varlığını ele vermesin diye gönderim arka planda yapılır.
    void issueVerificationCode({ email: cleanEmail, fullName: user.full_name }).catch((error) => {
      console.error('[Doğrulama Kodu] Yeniden gönderim hatası:', error?.code || error?.name || 'error');
    });
  }

  return {
    ok: true,
    message: RESEND_GENERIC_MESSAGE,
    code_length: VERIFICATION_CODE_DIGITS,
  };
}

/**
 * Cihaz Ambalaj Kutusundaki QR Kod / Seri No / UID ile Cihaz Sahiplenme
 *
 * Sahiplenme ATOMİKTİR: `UPDATE devices ... WHERE id = $ AND owner_user_id IS NULL RETURNING`
 * (0 satır -> başka biri sahiplenmiş -> 409). Kullanıcının rolü (individual/apartment_owner -> site_manager)
 * yalnızca sahiplenme anında yükseltilir; getMyClaimedDevices salt-okunurdur.
 */
export async function claimDevice({ userCode, deviceInput }) {
  const code = parseUserCode(userCode);
  if (code === null) {
    throw httpError(401, 'Kullanıcı oturumu gereklidir.');
  }

  // Kutu QR içeriğini normalize et: örn: "GD-C3-00861A0D5020" -> "00861A0D5020" veya "00:86:1A:0D:50:20" -> "00861A0D5020"
  const { rawInput, cleanUid } = normalizeClaimDeviceInput(deviceInput);

  const client = await pool.connect();
  let committed = false;
  try {
    await client.query('BEGIN');

    // Kullanıcıyı doğrula (yalnızca user_code ile; users.id ile karışmaz)
    const userRes = await client.query(
      `SELECT id, user_code, full_name, email, email_verified, role FROM users WHERE user_code = $1 LIMIT 1`,
      [code],
    );
    if (userRes.rowCount === 0) {
      throw httpError(404, 'Kullanıcı bulunamadı.');
    }
    const user = userRes.rows[0];
    if (!user.email_verified) {
      throw httpError(403, 'Cihaz sahiplenmek için önce e-posta adresinizi doğrulamanız gerekmektedir.');
    }

    // Cihazı veritabanında ara
    const devRes = await client.query(
      `SELECT id, device_uid, hardware_type, gate_name, site_code, owner_user_id, claimed_at,
              is_defective, defective_reason
       FROM devices
       WHERE UPPER(device_uid) = $1
          OR UPPER(device_uid) = $2
          OR UPPER(REPLACE(REPLACE(device_uid, ':', ''), '-', '')) = $1
       LIMIT 1`,
      [cleanUid, rawInput.toUpperCase()],
    );

    if (devRes.rowCount === 0) {
      throw httpError(
        404,
        'Bu cihaz şirket envanterinde kayıtlı değildir. Lütfen geçerli bir şirket cihazı karekodu okutunuz veya şirket yetkilisiyle iletişime geçiniz.',
      );
    }

    const deviceRow = devRes.rows[0];

    // Cihaz arızalı mı kontrol et
    if (deviceRow.is_defective) {
      const reasonText = deviceRow.defective_reason
        ? ` (${deviceRow.defective_reason})`
        : '';
      throw httpError(
        400,
        `Bu cihaz şirket envanterinde arızalı olarak işaretlenmiştir${reasonText}. Lütfen şirket yetkilisiyle iletişime geçiniz.`,
      );
    }

    const ownedByOther = () =>
      httpError(
        409,
        'Bu cihaz zaten başka bir kullanıcı hesabı tarafından sahiplenilmiş. Cihazı devralmak için mevcut sahibinin veya şirket yetkilisinin cihaz sahipliğini serbest bırakması gerekir.',
      );

    // Cihaz başka bir kullanıcı tarafından sahiplenilmiş mi?
    if (deviceRow.owner_user_id && String(deviceRow.owner_user_id) !== String(user.id)) {
      throw ownedByOther();
    }

    const promoteIfNeeded = async () => {
      if (shouldPromoteToSiteManager(user.role)) {
        await client.query(
          `UPDATE users SET role = 'site_manager' WHERE id = $1 AND role IN ('individual', 'apartment_owner')`,
          [user.id],
        );
        user.role = 'site_manager';
      }
    };

    // Zaten bu kullanıcıya ait (idempotent tekrar okutma)
    if (deviceRow.owner_user_id && String(deviceRow.owner_user_id) === String(user.id)) {
      await promoteIfNeeded();
      await client.query('COMMIT');
      committed = true;
      return {
        ok: true,
        role: user.role,
        already_owned: true,
        message: 'Bu cihaz zaten hesabınıza tanımlı.',
        device: deviceRow,
      };
    }

    // Cihazı bu kullanıcıya ata (Sahiplendir) — yalnızca sahibi YOKSA (atomik koşul)
    const updateRes = await client.query(SQL_CLAIM_DEVICE_ATOMIC, [user.id, user.user_code, deviceRow.id]);

    if (updateRes.rowCount === 0) {
      // Kontrol ile güncelleme arasında başka bir istek sahiplendi (veya cihaz arızalı işaretlendi).
      const recheck = await client.query(
        `SELECT owner_user_id, is_defective FROM devices WHERE id = $1 LIMIT 1`,
        [deviceRow.id],
      );
      const current = recheck.rows[0];
      if (current && current.owner_user_id && String(current.owner_user_id) === String(user.id)) {
        await promoteIfNeeded();
        await client.query('COMMIT');
        committed = true;
        return {
          ok: true,
          role: user.role,
          already_owned: true,
          message: 'Bu cihaz zaten hesabınıza tanımlı.',
          device: deviceRow,
        };
      }
      if (current?.is_defective) {
        throw httpError(400, 'Bu cihaz şirket envanterinde arızalı olarak işaretlenmiştir. Lütfen şirket yetkilisiyle iletişime geçiniz.');
      }
      throw ownedByOther();
    }

    // Cihaz ekleyen/sahiplenen kullanıcı artık Site Yöneticisidir (rol yükseltme yalnızca burada)
    await promoteIfNeeded();
    await client.query('COMMIT');
    committed = true;

    return {
      ok: true,
      role: user.role,
      message: `Cihaz (${deviceRow.device_uid}) başarıyla hesabınıza bağlandı! Artık bu cihaz ile site ve kapı kurulumu yapabilirsiniz.`,
      device: updateRes.rows[0] || deviceRow,
    };
  } catch (error) {
    if (!committed) {
      await rollbackQuietly(client);
    }
    throw error;
  } finally {
    client.release();
  }
}

/**
 * Kullanıcının Sahiplendiği Cihazları Listele
 * SALT-OKUNUR: rol yükseltme gibi yan etki yoktur (rol yalnızca claimDevice anında yükseltilir).
 */
export async function getMyClaimedDevices(userCode) {
  const code = parseUserCode(userCode);
  if (code === null) {
    return { ok: true, role: 'individual', devices: [] };
  }
  const userRes = await pool.query(
    `SELECT id, user_code, role FROM users WHERE user_code = $1 LIMIT 1`,
    [code],
  );
  if (userRes.rowCount === 0) {
    return { ok: true, role: 'individual', devices: [] };
  }
  const user = userRes.rows[0];

  const devicesRes = await pool.query(
    `SELECT id, device_uid, hardware_type, gate_name, site_code, owner_user_id, claimed_at, created_at
     FROM devices
     WHERE owner_user_id = $1 OR assigned_user_code = $2
     ORDER BY claimed_at DESC NULLS LAST, id DESC`,
    [user.id, user.user_code],
  );

  return {
    ok: true,
    role: user.role,
    devices: devicesRes.rows,
  };
}

/**
 * ÜYELİK SİSTEMİ AŞAMA 4: Dinamik Site, Blok ve Daire Kurulumu (Site Sahibi / SITE_OWNER)
 * Girdi sınırları: blok <=100, toplam daire <=5000, kapı <=100 (admin uçlarıyla aynı sabitler).
 */
export async function setupSiteWithClaimedDevice({
  userCode,
  name,
  city,
  district,
  address,
  blocks,
  doors,
  doorCount = 1,
  deviceUid,
}) {
  const code = parseUserCode(userCode);
  if (code === null) {
    throw httpError(401, 'Kullanıcı oturumu gereklidir.');
  }

  // Blok/kapı listelerini doğrula, sınırla ve normalize et (parseInt güvenli, üst sınırlı)
  const input = normalizeSetupSiteInput({ name, city, district, address, blocks, doors, doorCount });
  const {
    siteName,
    blocks: normalizedBlocks,
    doors: doorList,
    totalBlockCount,
    totalApartmentCount,
    totalDoorCount,
    blockApartmentCounts,
  } = input;

  const client = await pool.connect();
  let committed = false;
  try {
    await client.query('BEGIN');

    // Aynı kullanıcının eşzamanlı (çift dokunuş) kurulum istekleri sıraya girer.
    await client.query('SELECT pg_advisory_xact_lock(hashtext($1))', [`setup_site:${code}`]);

    // 1. Kullanıcıyı bul
    const userRes = await client.query(
      `SELECT id, user_code, role, full_name, email FROM users WHERE user_code = $1 LIMIT 1`,
      [code],
    );
    if (userRes.rowCount === 0) {
      throw httpError(404, 'Kullanıcı hesabı bulunamadı.');
    }
    const user = userRes.rows[0];

    // 1b. Cihaz sahipliği (site kurulmadan ÖNCE doğrulanır; cihaz satırı kilitlenir: eşzamanlı atama/sahiplenme
    // yarışı olmaz). Aşama 4 kuralı: "Cihazı ekleyen kişi Site Sahibi olur" -> cihaz sahiplenmemiş bireysel
    // kullanıcı site kuramaz; belirtilen cihaz kullanıcıya ait değilse site HİÇ kurulmaz (ROLLBACK, 4xx).
    // Zaten site yöneticisi olan kullanıcı ("Site Ekle", cihaz belirtmeden) ve süper kullanıcı cihazsız kurabilir.
    const targetDeviceUid = deviceUid ? String(deviceUid).trim().toUpperCase().slice(0, 64) : null;

    let devQuery;
    let devParams;
    if (targetDeviceUid) {
      devQuery = `SELECT * FROM devices WHERE UPPER(device_uid) = $1 AND (owner_user_id = $2 OR assigned_user_code = $3) LIMIT 1 FOR UPDATE`;
      devParams = [targetDeviceUid, user.id, user.user_code];
    } else {
      devQuery = `SELECT * FROM devices WHERE (owner_user_id = $1 OR assigned_user_code = $2) ORDER BY claimed_at DESC NULLS LAST LIMIT 1 FOR UPDATE`;
      devParams = [user.id, user.user_code];
    }

    const devRes = await client.query(devQuery, devParams);
    const dev = devRes.rowCount > 0 ? devRes.rows[0] : null;
    if (!dev && user.role !== 'super_user') {
      if (targetDeviceUid) {
        throw httpError(404, 'Belirtilen cihaz hesabınıza ait değil.');
      }
      if (shouldPromoteToSiteManager(user.role)) {
        throw httpError(400, 'Site kurmak için önce bir cihaz sahiplenmelisiniz.');
      }
    }

    // 2. Yeni Siteyi oluştur (Bireysel site sahibi için anında onaylı)
    const siteRes = await client.query(
      `
        INSERT INTO sites (
          name,
          address,
          city,
          district,
          block_count,
          apartment_count,
          door_count,
          block_apartment_counts,
          mqtt_site_id,
          approval_status,
          approved_at,
          feature_qr_enabled,
          feature_remote_open_enabled,
          feature_local_udp_enabled,
          feature_guest_pass_enabled,
          qr_entry_active
        )
        VALUES (
          $1, $2, $3, $4, $5, $6, $7, $8, generate_unique_mqtt_site_id(), 'approved', NOW(),
          TRUE, TRUE, TRUE, TRUE, TRUE
        )
        RETURNING
          site_code AS id,
          name,
          address,
          city,
          district,
          block_count,
          apartment_count,
          door_count,
          approval_status,
          approved_at,
          mqtt_site_id,
          created_at
      `,
      [
        siteName,
        input.address,
        input.city,
        input.district,
        totalBlockCount,
        totalApartmentCount,
        totalDoorCount,
        blockApartmentCounts,
      ],
    );
    const site = siteRes.rows[0];
    const siteCode = Number(site.id);

    // 3. Kullanıcıyı site yöneticisi olarak ekle
    await client.query(
      `
        INSERT INTO site_manager_sites (site_code, manager_user_code)
        VALUES ($1, $2)
        ON CONFLICT (site_code, manager_user_code) DO NOTHING
      `,
      [siteCode, user.user_code],
    );

    // 4. Kullanıcıyı SITE_OWNER rolüyle site_memberships tablosuna ekle
    await client.query(
      `
        INSERT INTO site_memberships (site_code, user_code, role, is_active)
        VALUES ($1, $2, 'SITE_OWNER', TRUE)
        ON CONFLICT (site_code, user_code)
        DO UPDATE SET role = 'SITE_OWNER', is_active = TRUE, updated_at = NOW()
      `,
      [siteCode, user.user_code],
    );

    // 5. Kullanıcının genel rolünü site_manager olarak güncelle
    if (user.role !== 'super_user') {
      await client.query(
        `UPDATE users SET role = 'site_manager' WHERE id = $1`,
        [user.id],
      );
    }

    // 6. Dinamik Blokları ve altındaki Daireleri optimize (bulk) oluştur
    const createdBlocks = [];
    for (const b of normalizedBlocks) {
      const blockRes = await client.query(
        `
          INSERT INTO site_blocks (site_code, block_name, sort_order)
          VALUES ($1, $2, $3)
          RETURNING id, site_code, block_name, sort_order
        `,
        [siteCode, b.name, b.sortOrder],
      );
      const blockRow = blockRes.rows[0];
      const blockId = Number(blockRow.id);

      // Bloğun tüm dairelerini PostgreSQL generate_series ile tek sorguda mikrosaniyeler içinde oluştur
      await client.query(
        `
          INSERT INTO apartments (site_code, block_id, unit_label, sort_order, is_active)
          SELECT $1, $2, ('Daire ' || s.i), s.i, TRUE
          FROM generate_series(1, $3::int) AS s(i)
        `,
        [siteCode, blockId, b.apartmentCount],
      );

      createdBlocks.push({
        ...blockRow,
        apartmentCount: b.apartmentCount,
      });
    }

    // 7. Kapıları oluştur
    const createdDoors = [];
    for (const d of doorList) {
      const doorRes = await client.query(
        `
          INSERT INTO site_doors (site_code, door_name, door_index, is_active)
          VALUES ($1, $2, $3, TRUE)
          RETURNING id, site_code, door_name, door_index, is_active
        `,
        [siteCode, d.name, d.doorIndex],
      );
      createdDoors.push(doorRes.rows[0]);
    }

    // 8. Cihazı bu siteye ve 1. kapıya ata (cihaz satırı 1b'de kilitlenmiş ve sahipliği doğrulanmıştır)
    let assignedDevice = null;
    if (dev) {
      // Cihazı bu siteye bağla
      await client.query(
        `UPDATE devices SET site_code = $1, gate_name = $2 WHERE id = $3`,
        [siteCode, createdDoors[0]?.door_name || 'Kapı 1', dev.id],
      );
      // 1. Kapıya bu cihazı bağla
      if (createdDoors.length > 0) {
        await client.query(
          `UPDATE site_doors SET assigned_device_id = $1 WHERE id = $2`,
          [dev.id, createdDoors[0].id],
        );
        createdDoors[0].assigned_device_id = dev.id;
      }
      assignedDevice = {
        id: dev.id,
        device_uid: dev.device_uid,
        hardware_type: dev.hardware_type,
      };
    }

    await client.query('COMMIT');
    committed = true;

    return {
      ok: true,
      message: `"${site.name}" sitesi, ${createdBlocks.length} blok ve ${totalApartmentCount} daire ile başarıyla kuruldu!`,
      site: {
        ...site,
        blocks: createdBlocks,
        doors: createdDoors,
        assignedDevice,
      },
    };
  } catch (error) {
    if (!committed) {
      await rollbackQuietly(client);
    }
    throw error;
  } finally {
    client.release();
  }
}

/**
 * Bireysel Kullanıcı: Site Katılım Başvurusu Oluşturma
 * Kontroller ve ekleme tek transaction içinde, (site, kullanıcı) bazlı advisory lock ile yapılır:
 * eşzamanlı çift istek ikinci bir PENDING kayıt oluşturamaz.
 */
export async function createJoinRequest({
  userCode,
  token,
  blockId,
  apartmentId,
  notes,
}) {
  const cleanToken = String(token || '').replace(/^SITE_JOIN:/i, '').trim().toUpperCase();
  if (!cleanToken || cleanToken.length > 128) {
    throw httpError(400, 'Geçersiz katılım tokeni.');
  }

  const uCode = parseUserCode(userCode);
  if (uCode === null) {
    throw httpError(401, 'Kullanıcı oturumu gereklidir.');
  }
  const aptId = parsePositiveId(apartmentId);
  if (aptId === null) {
    throw httpError(400, 'Geçerli bir daire seçiniz.');
  }
  const requestedBlockId =
    blockId === undefined || blockId === null || blockId === '' ? null : parsePositiveId(blockId);
  if (blockId !== undefined && blockId !== null && blockId !== '' && requestedBlockId === null) {
    throw httpError(400, 'Geçersiz blok seçimi.');
  }

  const cleanNotes = notes ? String(notes).trim().slice(0, NOTE_MAX_LENGTH) : null;

  const client = await pool.connect();
  let committed = false;
  let user;
  let siteCode;
  let siteName;
  let apt;
  let insertedRequest;
  try {
    await client.query('BEGIN');

    // Kullanıcıyı ve e-posta doğrulama durumunu kontrol et
    const userRes = await client.query(
      `SELECT user_code, full_name, email, email_verified, is_active FROM users WHERE user_code = $1 LIMIT 1`,
      [uCode],
    );
    if (userRes.rowCount === 0) {
      throw httpError(404, 'Kullanıcı hesabı bulunamadı.');
    }
    user = userRes.rows[0];
    if (!user.email_verified) {
      throw httpError(403, 'Siteye katılım başvurusu yapabilmek için e-posta adresinizi doğrulamanız gerekmektedir.');
    }

    // Tokenı ve siteyi doğrula
    const tokenRes = await client.query(
      `SELECT t.site_code, s.name AS site_name
       FROM site_join_tokens t
       JOIN sites s ON s.site_code = t.site_code
       WHERE UPPER(t.token) = $1 AND t.is_active = TRUE
       LIMIT 1`,
      [cleanToken],
    );
    if (tokenRes.rowCount === 0) {
      throw httpError(404, 'Bu site katılım QR kodu geçersiz veya iptal edilmiş.');
    }
    siteCode = Number(tokenRes.rows[0].site_code);
    siteName = tokenRes.rows[0].site_name;

    // Aynı (site, kullanıcı) için eşzamanlı başvurular sıraya girer
    await client.query('SELECT pg_advisory_xact_lock(hashtext($1))', [`join_request:${siteCode}:${uCode}`]);

    // Blok ve daireyi doğrula
    const aptRes = await client.query(
      `SELECT a.id, a.site_code, a.block_id, a.unit_label, b.block_name
       FROM apartments a
       LEFT JOIN site_blocks b ON b.id = a.block_id
       WHERE a.id = $1 AND a.site_code = $2 AND a.is_active = TRUE
       LIMIT 1`,
      [aptId, siteCode],
    );
    if (aptRes.rowCount === 0) {
      throw httpError(400, 'Seçilen daire bulunamadı veya bu siteye ait değil.');
    }
    apt = aptRes.rows[0];
    if (requestedBlockId !== null && Number(apt.block_id) !== requestedBlockId) {
      throw httpError(400, 'Seçilen daire belirtilen bloğa ait değil.');
    }

    // Kullanıcı zaten bu dairenin sakini mi?
    const existingMemberRes = await client.query(
      `SELECT role FROM apartment_memberships WHERE apartment_id = $1 AND user_code = $2 AND is_active = TRUE LIMIT 1`,
      [aptId, user.user_code],
    );
    if (existingMemberRes.rowCount > 0) {
      throw httpError(409, `Zaten bu dairenin aktif bir sakinisisiniz (${existingMemberRes.rows[0].role}).`);
    }

    // Kullanıcının bu site veya daire için bekleyen başvurusu var mı?
    const pendingReqRes = await client.query(
      `SELECT id, status FROM join_requests WHERE site_code = $1 AND user_code = $2 AND status = 'PENDING' LIMIT 1`,
      [siteCode, user.user_code],
    );
    if (pendingReqRes.rowCount > 0) {
      throw httpError(409, 'Bu site için zaten onay bekleyen bir katılım başvurunuz bulunmaktadır.');
    }

    const insertRes = await client.query(
      `
        INSERT INTO join_requests (
          site_code,
          block_id,
          apartment_id,
          user_code,
          status,
          notes
        )
        VALUES ($1, $2, $3, $4, 'PENDING', $5)
        RETURNING id, site_code, block_id, apartment_id, user_code, status, notes, created_at
      `,
      [siteCode, Number(apt.block_id), aptId, user.user_code, cleanNotes],
    );
    insertedRequest = insertRes.rows[0];

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

  // Site yöneticilerine arka planda bildirim e-postası gönder
  (async () => {
    try {
      const managersRes = await pool.query(
        `SELECT u.email, u.full_name
         FROM users u
         WHERE u.is_active = TRUE AND u.email IS NOT NULL AND u.email != '' AND u.user_code IN (
           SELECT manager_user_code FROM site_manager_sites WHERE site_code = $1
           UNION
           SELECT user_code FROM site_memberships WHERE site_code = $1 AND role IN ('SITE_OWNER', 'SITE_ADMIN') AND is_active = TRUE
         )`,
        [siteCode],
      );

      for (const mgr of managersRes.rows) {
        sendJoinRequestNotificationEmail({
          to: mgr.email,
          managerName: mgr.full_name,
          siteName,
          blockName: apt.block_name || '',
          unitLabel: apt.unit_label,
          applicantName: user.full_name,
          applicantEmail: user.email,
          notes: cleanNotes,
        }).catch((err) => {
          console.error(`[Mailer] Katılım bildirimi e-postası gönderilemedi (${mgr.email}):`, err.message);
        });
      }
    } catch (err) {
      console.error('[Mailer] Katılım bildirimi için yöneticiler sorgulanırken hata:', err.message);
    }
  })();

  return {
    ok: true,
    message: `"${siteName}" sitesi ${apt.block_name || ''} ${apt.unit_label} için katılım başvurunuz başarıyla oluşturuldu. Site yöneticisinin onayı bekleniyor.`,
    request: {
      id: Number(insertedRequest.id),
      siteCode,
      siteName,
      blockName: apt.block_name || '',
      unitLabel: apt.unit_label,
      status: 'PENDING',
      createdAt: insertedRequest.created_at,
    },
  };
}

/**
 * Bireysel Kullanıcı: Kendi katılım başvurularını listele
 */
export async function getMyJoinRequests(userCode) {
  const uCode = parseUserCode(userCode);
  if (uCode === null) {
    throw httpError(401, 'Kullanıcı oturumu gereklidir.');
  }
  const result = await pool.query(
    `
      SELECT
        jr.id,
        jr.site_code,
        s.name AS site_name,
        s.city,
        s.district,
        jr.block_id,
        b.block_name,
        jr.apartment_id,
        a.unit_label,
        jr.status,
        jr.notes,
        jr.rejection_reason,
        jr.created_at,
        jr.reviewed_at
      FROM join_requests jr
      JOIN sites s ON s.site_code = jr.site_code
      LEFT JOIN site_blocks b ON b.id = jr.block_id
      LEFT JOIN apartments a ON a.id = jr.apartment_id
      WHERE jr.user_code = $1
      ORDER BY jr.created_at DESC
    `,
    [uCode],
  );

  return {
    ok: true,
    requests: result.rows.map((r) => ({
      id: Number(r.id),
      siteCode: Number(r.site_code),
      siteName: r.site_name,
      city: r.city,
      district: r.district,
      blockId: r.block_id ? Number(r.block_id) : null,
      blockName: r.block_name,
      apartmentId: Number(r.apartment_id),
      unitLabel: r.unit_label,
      status: r.status,
      notes: r.notes,
      rejectionReason: r.rejection_reason,
      createdAt: r.created_at,
      reviewedAt: r.reviewed_at,
    })),
  };
}

/**
 * Site Yöneticisi: Sitedeki katılım başvurularını listele
 */
export async function getSiteJoinRequests({ siteCode, authUser, status }) {
  const parsedSiteCode = parsePositiveId(siteCode);
  if (parsedSiteCode === null) {
    throw httpError(400, 'Geçersiz site kimliği.');
  }

  // Yetki kontrolü: super_user veya o sitenin yöneticisi
  if (authUser.role !== 'super_user') {
    const isManagerRes = await pool.query(
      `SELECT 1 FROM site_manager_sites WHERE site_code = $1 AND manager_user_code = $2 LIMIT 1`,
      [parsedSiteCode, Number(authUser.id)],
    );
    if (isManagerRes.rowCount === 0) {
      const isOwnerRes = await pool.query(
        `SELECT 1 FROM site_memberships WHERE site_code = $1 AND user_code = $2 AND role IN ('SITE_OWNER', 'SITE_ADMIN') AND is_active = TRUE LIMIT 1`,
        [parsedSiteCode, Number(authUser.id)],
      );
      if (isOwnerRes.rowCount === 0) {
        throw httpError(403, 'Bu sitenin katılım taleplerini görme yetkiniz bulunmamaktadır.');
      }
    }
  }

  const queryStatus = status ? String(status).toUpperCase() : null;

  const result = await pool.query(
    `
      SELECT
        jr.id,
        jr.site_code,
        jr.user_code,
        u.full_name,
        u.email,
        u.phone_number,
        jr.block_id,
        b.block_name,
        jr.apartment_id,
        a.unit_label,
        jr.status,
        jr.notes,
        jr.rejection_reason,
        jr.created_at,
        jr.reviewed_at,
        reviewer.full_name AS reviewed_by_name
      FROM join_requests jr
      JOIN users u ON u.user_code = jr.user_code
      LEFT JOIN site_blocks b ON b.id = jr.block_id
      LEFT JOIN apartments a ON a.id = jr.apartment_id
      LEFT JOIN users reviewer ON reviewer.user_code = jr.reviewed_by_user_code
      WHERE jr.site_code = $1
        ${queryStatus ? 'AND jr.status = $2' : ''}
      ORDER BY
        CASE WHEN jr.status = 'PENDING' THEN 1 ELSE 2 END,
        jr.created_at DESC
    `,
    queryStatus ? [parsedSiteCode, queryStatus] : [parsedSiteCode],
  );

  return {
    ok: true,
    requests: result.rows.map((r) => ({
      id: Number(r.id),
      siteCode: Number(r.site_code),
      userCode: Number(r.user_code),
      fullName: r.full_name,
      email: r.email,
      phoneNumber: r.phone_number,
      blockId: r.block_id ? Number(r.block_id) : null,
      blockName: r.block_name,
      apartmentId: Number(r.apartment_id),
      unitLabel: r.unit_label,
      status: r.status,
      notes: r.notes,
      rejectionReason: r.rejection_reason,
      createdAt: r.created_at,
      reviewedAt: r.reviewed_at,
      reviewedByName: r.reviewed_by_name,
    })),
  };
}

/**
 * Site Yöneticisi: Katılım Başvurusunu Onayla
 */
export async function approveJoinRequest({ requestId, authUser }) {
  const reqId = parsePositiveId(requestId);
  if (reqId === null) {
    throw httpError(400, 'Geçersiz talep kimliği.');
  }
  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    // Talebi bul
    const reqRes = await client.query(
      `
        SELECT jr.*, s.name AS site_name, a.unit_label, b.block_name, u.full_name, u.email
        FROM join_requests jr
        JOIN sites s ON s.site_code = jr.site_code
        JOIN apartments a ON a.id = jr.apartment_id
        LEFT JOIN site_blocks b ON b.id = jr.block_id
        JOIN users u ON u.user_code = jr.user_code
        WHERE jr.id = $1
        FOR UPDATE OF jr
      `,
      [reqId],
    );
    if (reqRes.rowCount === 0) {
      throw httpError(404, 'Katılım talebi bulunamadı.');
    }
    const req = reqRes.rows[0];

    // Yetki kontrolü DURUM kontrolünden ÖNCE: başka sitenin yöneticisi talebin durumunu (409 metni) öğrenemesin.
    if (authUser.role !== 'super_user') {
      const isManagerRes = await client.query(
        `SELECT 1 FROM site_manager_sites WHERE site_code = $1 AND manager_user_code = $2 LIMIT 1`,
        [Number(req.site_code), Number(authUser.id)],
      );
      if (isManagerRes.rowCount === 0) {
        const isOwnerRes = await client.query(
          `SELECT 1 FROM site_memberships WHERE site_code = $1 AND user_code = $2 AND role IN ('SITE_OWNER', 'SITE_ADMIN') AND is_active = TRUE LIMIT 1`,
          [Number(req.site_code), Number(authUser.id)],
        );
        if (isOwnerRes.rowCount === 0) {
          throw httpError(403, 'Bu talebi onaylama yetkiniz bulunmamaktadır.');
        }
      }
    }

    if (req.status !== 'PENDING') {
      throw httpError(409, `Bu talep zaten "${req.status}" durumunda, tekrar işlem yapılamaz.`);
    }

    // Aynı dairede eşzamanlı onaylar çift APARTMENT_ADMIN üretmesin: daire satırını kilitle
    await client.query(`SELECT id FROM apartments WHERE id = $1 FOR UPDATE`, [Number(req.apartment_id)]);

    // Aşama 9 Hiyerarşisi: Dairede daha önce aktif APARTMENT_ADMIN var mı?
    const adminCheckRes = await client.query(
      `SELECT 1 FROM apartment_memberships WHERE apartment_id = $1 AND role = 'APARTMENT_ADMIN' AND is_active = TRUE LIMIT 1`,
      [Number(req.apartment_id)],
    );
    const assignedRole = adminCheckRes.rowCount === 0 ? 'APARTMENT_ADMIN' : 'FAMILY_MEMBER';

    // 1. Daire üyeliği oluştur / güncelle
    await client.query(
      `
        INSERT INTO apartment_memberships (apartment_id, user_code, role, is_active)
        VALUES ($1, $2, $3, TRUE)
        ON CONFLICT (apartment_id, user_code)
        DO UPDATE SET role = $3, is_active = TRUE, updated_at = NOW()
      `,
      [Number(req.apartment_id), Number(req.user_code), assignedRole],
    );

    // 2. Site üyeliği oluştur / güncelle (Rol: RESIDENT)
    await client.query(
      `
        INSERT INTO site_memberships (site_code, user_code, role, is_active)
        VALUES ($1, $2, 'RESIDENT', TRUE)
        ON CONFLICT (site_code, user_code)
        DO UPDATE SET is_active = TRUE, updated_at = NOW()
      `,
      [Number(req.site_code), Number(req.user_code)],
    );

    // 3. Geriye dönük uyumluluk: apartments tablosunda resident_user_code boşsa ilk sakin ata
    await client.query(
      `UPDATE apartments SET resident_user_code = $1 WHERE id = $2 AND resident_user_code IS NULL`,
      [Number(req.user_code), Number(req.apartment_id)],
    );

    // 4. Talebi APPROVED olarak işaretle
    const reviewerUserCode = Number(authUser.id);
    await client.query(
      `
        UPDATE join_requests
        SET status = 'APPROVED',
            reviewed_by_user_code = $1,
            reviewed_at = NOW(),
            updated_at = NOW()
        WHERE id = $2
      `,
      [reviewerUserCode, reqId],
    );

    await client.query('COMMIT');

    return {
      ok: true,
      message: `${req.full_name} sakini, "${req.block_name || ''} ${req.unit_label}" dairesine ${assignedRole === 'APARTMENT_ADMIN' ? 'Daire Yöneticisi' : 'Aile Üyesi'} olarak başarıyla onaylandı.`,
      assignedRole,
    };
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
}

/**
 * Site Yöneticisi: Katılım Başvurusunu Reddet
 */
export async function rejectJoinRequest({ requestId, authUser, reason }) {
  const reqId = parsePositiveId(requestId);
  if (reqId === null) {
    throw httpError(400, 'Geçersiz talep kimliği.');
  }
  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    const reqRes = await client.query(
      `SELECT * FROM join_requests WHERE id = $1 FOR UPDATE`,
      [reqId],
    );
    if (reqRes.rowCount === 0) {
      throw httpError(404, 'Katılım talebi bulunamadı.');
    }
    const req = reqRes.rows[0];

    // Yetki kontrolü DURUM kontrolünden ÖNCE: başka sitenin yöneticisi talebin durumunu (409 metni) öğrenemesin.
    if (authUser.role !== 'super_user') {
      const isManagerRes = await client.query(
        `SELECT 1 FROM site_manager_sites WHERE site_code = $1 AND manager_user_code = $2 LIMIT 1`,
        [Number(req.site_code), Number(authUser.id)],
      );
      if (isManagerRes.rowCount === 0) {
        const isOwnerRes = await client.query(
          `SELECT 1 FROM site_memberships WHERE site_code = $1 AND user_code = $2 AND role IN ('SITE_OWNER', 'SITE_ADMIN') AND is_active = TRUE LIMIT 1`,
          [Number(req.site_code), Number(authUser.id)],
        );
        if (isOwnerRes.rowCount === 0) {
          throw httpError(403, 'Bu talebi reddetme yetkiniz bulunmamaktadır.');
        }
      }
    }

    if (req.status !== 'PENDING') {
      throw httpError(409, `Bu talep zaten "${req.status}" durumunda, tekrar işlem yapılamaz.`);
    }

    const cleanReason = reason ? String(reason).trim().slice(0, 500) : 'Yönetici tarafından uygun görülmedi.';
    const reviewerUserCode = Number(authUser.id);

    await client.query(
      `
        UPDATE join_requests
        SET status = 'REJECTED',
            rejection_reason = $1,
            reviewed_by_user_code = $2,
            reviewed_at = NOW(),
            updated_at = NOW()
        WHERE id = $3
      `,
      [cleanReason, reviewerUserCode, reqId],
    );

    await client.query('COMMIT');

    return {
      ok: true,
      message: 'Katılım başvurusu reddedildi.',
    };
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
}

/**
 * Bireysel / Daire Sakini: Kendi Onaylı Dairelerini ve Daire Üyelerini Getir
 */
export async function getMyApartments(userCode) {
  const uCode = parseUserCode(userCode);
  if (uCode === null) {
    throw httpError(400, 'Geçersiz kullanıcı kodu.');
  }

  // Kullanıcının üyesi olduğu aktif daireler
  const aptsRes = await pool.query(
    `
      SELECT
        am.id AS membership_id,
        am.apartment_id,
        am.role AS apartment_role,
        am.created_at AS joined_at,
        a.unit_label,
        a.block_id,
        a.sort_order,
        b.block_name,
        s.site_code,
        s.name AS site_name,
        s.city,
        s.district
      FROM apartment_memberships am
      JOIN apartments a ON a.id = am.apartment_id
      LEFT JOIN site_blocks b ON b.id = a.block_id
      JOIN sites s ON s.site_code = a.site_code
      WHERE am.user_code = $1 AND am.is_active = TRUE AND a.is_active = TRUE
      ORDER BY s.name ASC, b.block_name ASC, a.sort_order ASC, a.id ASC
    `,
    [uCode],
  );

  const apartments = [];

  for (const aptRow of aptsRes.rows) {
    const aptId = Number(aptRow.apartment_id);

    // Dairedeki tüm aktif üyeleri getir
    const membersRes = await pool.query(
      `
        SELECT
          am.id AS membership_id,
          am.user_code,
          am.role,
          am.is_active,
          am.created_at AS joined_at,
          u.full_name,
          u.email,
          u.phone_number
        FROM apartment_memberships am
        JOIN users u ON u.user_code = am.user_code
        WHERE am.apartment_id = $1 AND am.is_active = TRUE
        ORDER BY (CASE WHEN am.role = 'APARTMENT_ADMIN' THEN 0 ELSE 1 END), am.created_at ASC
      `,
      [aptId],
    );

    apartments.push({
      apartment_id: aptId,
      unit_label: aptRow.unit_label,
      block_id: aptRow.block_id != null ? Number(aptRow.block_id) : null,
      block_name: aptRow.block_name || '',
      site_code: Number(aptRow.site_code),
      site_name: aptRow.site_name,
      city: aptRow.city || '',
      district: aptRow.district || '',
      apartment_role: aptRow.apartment_role,
      joined_at: aptRow.joined_at,
      members: membersRes.rows.map((m) => ({
        membership_id: Number(m.membership_id),
        user_code: Number(m.user_code),
        full_name: m.full_name,
        email: m.email,
        phone_number: m.phone_number || '',
        role: m.role,
        is_current_user: Number(m.user_code) === uCode,
        is_apartment_admin: m.role === 'APARTMENT_ADMIN',
        joined_at: m.joined_at,
      })),
    });
  }

  return {
    ok: true,
    apartments,
  };
}

/**
 * Daire yönetim yetkisi kontrolü
 * (super_user, site_manager_sites yöneticisi, site_memberships OWNER/ADMIN veya ilgili dairenin APARTMENT_ADMIN'i)
 */
export async function checkApartmentManagementAccess(authUser, apartmentId) {
  const aptId = parsePositiveId(apartmentId);
  if (aptId === null) {
    throw httpError(400, 'Geçersiz daire kimliği.');
  }

  const aptRes = await pool.query(
    `SELECT a.id, a.site_code, a.block_id, a.unit_label, a.resident_user_code, a.resident_pin_code
     FROM apartments a
     WHERE a.id = $1 LIMIT 1`,
    [aptId],
  );
  if (aptRes.rowCount === 0) {
    throw httpError(404, 'Daire bulunamadı.');
  }
  const apt = aptRes.rows[0];

  if (authUser?.role === 'super_user') {
    return { apt, isSuperUser: true, isSiteManager: true, isAptAdmin: true };
  }

  const userCode = authUserCodeOf(authUser);
  if (userCode === null) {
    throw httpError(403, 'Bu daireyi yönetme yetkiniz bulunmamaktadır.');
  }

  // 1. Site Yöneticisi mi? (site_manager_sites)
  const mgrRes = await pool.query(
    `SELECT 1 FROM site_manager_sites WHERE site_code = $1 AND manager_user_code = $2 LIMIT 1`,
    [apt.site_code, userCode],
  );
  if (mgrRes.rowCount > 0) {
    return { apt, isSuperUser: false, isSiteManager: true, isAptAdmin: false };
  }

  // 2. Site Sahibi veya Yöneticisi mi? (site_memberships)
  const siteMemRes = await pool.query(
    `SELECT 1 FROM site_memberships WHERE site_code = $1 AND user_code = $2 AND role IN ('SITE_OWNER', 'SITE_ADMIN') AND is_active = TRUE LIMIT 1`,
    [apt.site_code, userCode],
  );
  if (siteMemRes.rowCount > 0) {
    return { apt, isSuperUser: false, isSiteManager: true, isAptAdmin: false };
  }

  // 3. Daire Yöneticisi mi? (APARTMENT_ADMIN)
  const aptAdminRes = await pool.query(
    `SELECT 1 FROM apartment_memberships WHERE apartment_id = $1 AND user_code = $2 AND role = 'APARTMENT_ADMIN' AND is_active = TRUE LIMIT 1`,
    [aptId, userCode],
  );
  if (aptAdminRes.rowCount > 0) {
    return { apt, isSuperUser: false, isSiteManager: false, isAptAdmin: true };
  }
  // Eski (legacy) tekil sakin göstergesi: üyeliği açıkça PASİF yapılmış kişi yönetici sayılmaz.
  if (isLegacyResident(apt, userCode)) {
    const ownMembershipRes = await pool.query(
      `SELECT is_active FROM apartment_memberships WHERE apartment_id = $1 AND user_code = $2 LIMIT 1`,
      [aptId, userCode],
    );
    if (ownMembershipRes.rowCount === 0 || ownMembershipRes.rows[0].is_active === true) {
      return { apt, isSuperUser: false, isSiteManager: false, isAptAdmin: true };
    }
  }

  throw httpError(403, 'Bu daireyi yönetme yetkiniz bulunmamaktadır.');
}

/**
 * Üyelik/izin kaldırıldığında, kullanıcının sitede başka aktif daire üyeliği/sakinliği kalmadıysa
 * ona tanınmış manuel kapı izinlerini (door_access_overrides) temizler.
 * Kapsam YALNIZCA ilgili site + ilgili kullanıcıdır (başka kullanıcıların izinlerine dokunulmaz).
 */
async function cleanupDoorOverridesIfNoMembership(client, siteCode, userCode) {
  await client.query(
    `DELETE FROM door_access_overrides dao
     WHERE dao.site_code = $1
       AND dao.user_code = $2
       AND NOT EXISTS (
         SELECT 1
         FROM apartment_memberships am
         INNER JOIN apartments a ON a.id = am.apartment_id
         WHERE a.site_code = $1 AND am.user_code = $2 AND am.is_active = TRUE AND a.is_active = TRUE
       )
       AND NOT EXISTS (
         SELECT 1 FROM apartments a2
         WHERE a2.site_code = $1 AND a2.resident_user_code = $2 AND a2.is_active = TRUE
       )`,
    [siteCode, userCode],
  );
}

/**
 * Çıkarılan/silinen kişi dairenin yöneticisi (veya eski tekil sakin göstergesi) ise yönetici devri:
 * başka aktif APARTMENT_ADMIN varsa gösterge ona taşınır; yoksa en eski aktif üye APARTMENT_ADMIN olur;
 * kimse kalmadıysa gösterge temizlenir (eski sakin göstergesi erişimi sürdürmesin diye).
 */
async function handOverApartmentResident(client, apartmentId, removedUserCode, { keepPin = false } = {}) {
  const otherAdminRes = await client.query(
    `SELECT user_code FROM apartment_memberships
     WHERE apartment_id = $1 AND user_code <> $2 AND is_active = TRUE AND role = 'APARTMENT_ADMIN'
     ORDER BY created_at ASC, id ASC LIMIT 1`,
    [apartmentId, removedUserCode],
  );
  if (otherAdminRes.rowCount > 0) {
    await client.query(
      `UPDATE apartments SET resident_user_code = $1 WHERE id = $2`,
      [Number(otherAdminRes.rows[0].user_code), apartmentId],
    );
    return;
  }

  // Dairede kalan başka bir AKTİF üye varsa onu otomatik APARTMENT_ADMIN yap
  const remainingRes = await client.query(
    `SELECT user_code FROM apartment_memberships
     WHERE apartment_id = $1 AND user_code <> $2 AND is_active = TRUE
     ORDER BY created_at ASC, id ASC LIMIT 1`,
    [apartmentId, removedUserCode],
  );
  if (remainingRes.rowCount > 0) {
    const newAdminCode = Number(remainingRes.rows[0].user_code);
    await client.query(
      `UPDATE apartment_memberships SET role = 'APARTMENT_ADMIN', updated_at = NOW() WHERE apartment_id = $1 AND user_code = $2`,
      [apartmentId, newAdminCode],
    );
    await client.query(
      `UPDATE apartments SET resident_user_code = $1 WHERE id = $2`,
      [newAdminCode, apartmentId],
    );
  } else {
    // keepPin: geçici pasife alma (toggle) geri alınabilir olduğundan eski PIN göstergesi silinmez.
    await client.query(
      keepPin
        ? `UPDATE apartments SET resident_user_code = NULL WHERE id = $1`
        : `UPDATE apartments SET resident_user_code = NULL, resident_pin_code = NULL WHERE id = $1`,
      [apartmentId],
    );
  }
}

function parseTargetUserCode(value) {
  const parsed = parseUserCode(value);
  if (parsed === null) {
    throw httpError(400, 'Geçersiz kullanıcı kimliği.');
  }
  return parsed;
}

/**
 * Daire Üyesini Pasife Al / Çıkar
 * (Süper Kullanıcı, Site Yöneticisi veya Daire Yöneticisi)
 * Erişim kesilir: üyelik pasifleşir, eski sakin göstergesi devredilir, manuel kapı izinleri temizlenir
 * ve sitedeki cihazların yerel kontrol token'ı döndürülür.
 */
export async function removeApartmentMember({ apartmentId, targetUserCode, authUser }) {
  const { apt, isSuperUser, isSiteManager } = await checkApartmentManagementAccess(authUser, apartmentId);
  const tUserCode = parseTargetUserCode(targetUserCode);
  const reviewerUserCode = authUserCodeOf(authUser);

  // Daire yöneticisi kendisini çıkaramaz (süper kullanıcı veya site yöneticisi çıkarabilir)
  if (!isSuperUser && !isSiteManager && tUserCode === reviewerUserCode) {
    throw httpError(400, 'Daire yöneticisi kendi kendisini daireden çıkaramaz.');
  }

  const client = await pool.connect();
  let committed = false;
  try {
    await client.query('BEGIN');
    const aptLock = await client.query(
      `SELECT id, site_code, resident_user_code FROM apartments WHERE id = $1 FOR UPDATE`,
      [apt.id],
    );
    const aptRow = aptLock.rows[0] || apt;

    // Üyeliği pasife al (yalnızca bu dairedeki üyelik)
    const memUpdate = await client.query(
      `UPDATE apartment_memberships SET is_active = FALSE, updated_at = NOW()
       WHERE apartment_id = $1 AND user_code = $2
       RETURNING role`,
      [apt.id, tUserCode],
    );
    const legacy = isLegacyResident(aptRow, tUserCode);
    if (memUpdate.rowCount === 0 && !legacy) {
      throw httpError(404, 'Kullanıcı bu dairede kayıtlı değil.');
    }

    if (legacy || memUpdate.rows[0]?.role === 'APARTMENT_ADMIN') {
      await handOverApartmentResident(client, apt.id, tUserCode);
    }

    // Kapı istisnalarını temizle (yalnızca kişinin başka aktif üyeliği kalmadıysa)
    await cleanupDoorOverridesIfNoMembership(client, apt.site_code, tUserCode);

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

  await rotateTokensForSite({ siteCode: apt.site_code, reason: 'apartment_member_removed' });

  return {
    ok: true,
    message: 'Üye daireden başarıyla çıkarıldı.',
  };
}

// true/false (boolean, "true"/"false", 1/0) dışındaki değerler 400 döner; metin 'false' asla true sayılmaz.
function parseBooleanFlag(value, fieldName) {
  if (typeof value === 'boolean') {
    return value;
  }
  if (value === 'true' || value === 1 || value === '1') {
    return true;
  }
  if (value === 'false' || value === 0 || value === '0') {
    return false;
  }
  throw httpError(400, `${fieldName} alanı true/false olmalıdır.`);
}

/**
 * Daire Sakini Aktif / Pasif Durumunu Değiştir
 * (Süper Kullanıcı, Site Yöneticisi veya Daire Yöneticisi)
 *
 * YALNIZCA bu dairedeki üyeliği etkiler. Global hesap durumu (users.is_active) burada ASLA değişmez;
 * hesabı pasifleştirmek yalnızca süper kullanıcı rotasının işidir. Üyelik satırı yoksa 404.
 */
export async function toggleApartmentMemberStatus({ apartmentId, targetUserCode, isActive, authUser }) {
  const { apt, isSuperUser, isSiteManager } = await checkApartmentManagementAccess(authUser, apartmentId);
  const tUserCode = parseTargetUserCode(targetUserCode);
  const reviewerUserCode = authUserCodeOf(authUser);

  if (!isSuperUser && !isSiteManager && tUserCode === reviewerUserCode) {
    throw httpError(400, 'Daire yöneticisi kendi durumunu pasife alamaz.');
  }

  const activeBool = parseBooleanFlag(isActive, 'is_active');

  const client = await pool.connect();
  let committed = false;
  try {
    await client.query('BEGIN');
    const aptLock = await client.query(
      `SELECT id, site_code, resident_user_code FROM apartments WHERE id = $1 FOR UPDATE`,
      [apt.id],
    );
    const aptRow = aptLock.rows[0] || apt;

    // 1. apartment_memberships tablosunda güncelle (yalnız bu daire + bu kullanıcı)
    const memUpdate = await client.query(
      `UPDATE apartment_memberships
       SET is_active = $1, updated_at = NOW()
       WHERE apartment_id = $2 AND user_code = $3
       RETURNING role`,
      [activeBool, apt.id, tUserCode],
    );

    const legacy = isLegacyResident(aptRow, tUserCode);
    const target = resolveToggleTarget({
      membershipRowCount: memUpdate.rowCount,
      legacyResidentMatches: legacy,
    });
    if (target === 'NOT_FOUND') {
      throw httpError(404, 'Kullanıcı bu dairede kayıtlı değil.');
    }

    // 2. Eski (legacy) tekil sakin göstergesi (apartments.resident_user_code).
    //    - SAF legacy sakin (üyelik satırı yok): apartments tablosu senkronize edilir (eski davranış).
    //    - Aktif etme: gösterge bu kişiyse daire de aktif edilir (eski davranış).
    //    - Üyelik satırı OLAN aile reisi (onaylanan ilk sakin göstergeyi taşır) pasife alınırsa TÜM DAİRE
    //      pasifleşmez: yalnız üyelik pasif olur, gösterge devredilir (başka aktif yönetici / en eski aktif üye /
    //      kimse yoksa temizlenir); diğer aile üyeleri erişimini ve dairenin ağaçtaki görünürlüğünü korur.
    if (legacy) {
      if (activeBool || target === 'LEGACY_RESIDENT') {
        await client.query(
          `UPDATE apartments SET is_active = $1 WHERE id = $2`,
          [activeBool, apt.id],
        );
      } else {
        await handOverApartmentResident(client, apt.id, tUserCode, { keepPin: true });
      }
    }
    // Aktif etme: aile reisi yeniden aktifse ve gösterge boşsa geri konur (devir sonrası boş kalmışsa).
    if (activeBool && memUpdate.rows[0]?.role === 'APARTMENT_ADMIN') {
      await client.query(
        `UPDATE apartments SET resident_user_code = $1 WHERE id = $2 AND resident_user_code IS NULL`,
        [tUserCode, apt.id],
      );
    }

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

  if (!activeBool) {
    await rotateTokensForSite({ siteCode: apt.site_code, reason: 'apartment_member_deactivated' });
  }

  // Global hesap durumu (users.is_active) burada değişmez: hesap sistem yöneticisi tarafından pasife alınmışsa
  // üyelik aktif edilse bile giriş yapılamaz -> bunu başarı mesajında dürüstçe belirt (geriye uyumlu ek alan).
  let accountIsActive = true;
  if (activeBool) {
    const accountRes = await pool.query(`SELECT is_active FROM users WHERE user_code = $1 LIMIT 1`, [tUserCode]);
    accountIsActive = accountRes.rows?.[0]?.is_active !== false;
  }

  let message;
  if (!activeBool) {
    message = 'Daire sakini pasife alındı (erişimi durduruldu).';
  } else if (accountIsActive) {
    message = 'Daire sakini başarıyla aktif edildi.';
  } else {
    message = 'Daire üyeliği aktif edildi; ancak kullanıcının hesabı sistem yöneticisi tarafından pasife alınmış olduğundan giriş ve kapı erişimi hesap aktif edilene kadar kapalı kalır.';
  }

  return {
    ok: true,
    is_active: activeBool,
    account_is_active: accountIsActive,
    message,
  };
}

/**
 * Daire Sakinini Tamamen Sil
 * (Süper Kullanıcı ve Site Yöneticileri yetkilidir)
 */
export async function deleteApartmentMember({ apartmentId, targetUserCode, authUser }) {
  const { apt, isSuperUser, isSiteManager } = await checkApartmentManagementAccess(authUser, apartmentId);

  // Yöntem yorumundaki niyet: yalnızca süper kullanıcı ve site yöneticileri kalıcı silebilir
  // (daire yöneticisi için "Daireden Çıkar" ucu kullanılır).
  if (!canDeleteApartmentMember({ isSuperUser, isSiteManager })) {
    throw httpError(403, 'Sakini kalıcı olarak silme yetkisi yalnızca site yöneticilerine aittir.');
  }

  const tUserCode = parseTargetUserCode(targetUserCode);

  const client = await pool.connect();
  let committed = false;
  try {
    await client.query('BEGIN');
    const aptLock = await client.query(
      `SELECT id, site_code, resident_user_code FROM apartments WHERE id = $1 FOR UPDATE`,
      [apt.id],
    );
    const aptRow = aptLock.rows[0] || apt;

    // 1. Daire üyeliğini sil
    const delRes = await client.query(
      `DELETE FROM apartment_memberships WHERE apartment_id = $1 AND user_code = $2 RETURNING role`,
      [apt.id, tUserCode],
    );
    const legacy = isLegacyResident(aptRow, tUserCode);
    if (delRes.rowCount === 0 && !legacy) {
      throw httpError(404, 'Kullanıcı bu dairede kayıtlı değil.');
    }

    // 2. Kapı istisnalarını temizle (yalnızca kişinin başka aktif üyeliği kalmadıysa)
    await cleanupDoorOverridesIfNoMembership(client, apt.site_code, tUserCode);

    // 3. Silinen kişi dairenin yöneticisi / apartments.resident_user_code ise yönetici devri
    if (legacy || delRes.rows[0]?.role === 'APARTMENT_ADMIN') {
      await handOverApartmentResident(client, apt.id, tUserCode);
    }

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

  await rotateTokensForSite({ siteCode: apt.site_code, reason: 'apartment_member_deleted' });

  return {
    ok: true,
    message: 'Sakin daireden başarıyla silindi.',
  };
}

/**
 * Daire Sakininin Şifresini Değiştir (YALNIZCA kullanıcının kendi şifresi)
 *
 * Güvenlik kuralı: Yöneticiler daire sakinlerinin şifresini değiştiremez; kullanıcı kendi hesabında
 * `current_password` ile doğrulayarak değiştirir (PATCH /me ile aynı ilke).
 * Tasarım kararı (korundu): daire PIN'i/şifre politikası en az 4 karakterdir ve eski (legacy)
 * apartments.resident_pin_code alanı tasarım gereği düz metin tutulur.
 */
export async function changeApartmentMemberPassword({
  apartmentId,
  targetUserCode,
  newPassword,
  currentPassword,
  authUser,
}) {
  const aptId = parsePositiveId(apartmentId);
  if (aptId === null) {
    throw httpError(400, 'Geçersiz daire kimliği.');
  }
  const tUserCode = parseTargetUserCode(targetUserCode);
  const callerCode = authUserCodeOf(authUser);

  // Güvenlik kuralı: Yöneticiler daire sakinlerinin şifresini değiştiremez!
  // Kullanıcılar kendi şifrelerini kendi hesaplarına giriş yaparak profil bölümünden değiştirmelidir.
  if (callerCode === null || callerCode !== tUserCode) {
    throw httpError(
      403,
      'Güvenlik kuralı: Yöneticiler daire sakinlerinin şifresini değiştiremez. Kullanıcılar kendi şifrelerini hesaplarına giriş yaparak profil bölümünden değiştirmelidir.',
    );
  }

  const cleanPass = String(newPassword || '').trim();
  if (cleanPass.length < 4) {
    throw httpError(400, 'Şifre en az 4 karakter uzunluğunda olmalıdır.');
  }
  if (cleanPass.length > PASSWORD_MAX_LENGTH) {
    throw httpError(400, `Şifre en fazla ${PASSWORD_MAX_LENGTH} karakter olabilir.`);
  }

  // Giriş (login) parolayı trim eder; saklanan parolalar hep trim'lidir -> mevcut parola da trim edilir.
  const cleanCurrent = String(currentPassword || '').trim();
  if (!cleanCurrent) {
    throw httpError(400, 'Mevcut şifre zorunludur.');
  }

  // Daireyi yükle (eski kodda tanımsız `apt` değişkeni yüzünden bu uç hiç çalışmıyordu)
  const aptRes = await pool.query(
    `SELECT id, site_code, resident_user_code FROM apartments WHERE id = $1 LIMIT 1`,
    [aptId],
  );
  if (aptRes.rowCount === 0) {
    throw httpError(404, 'Daire bulunamadı.');
  }
  const apt = aptRes.rows[0];

  // Kullanıcının bu dairede kayıtlı olduğunu doğrula
  const memberCheck = await pool.query(
    `SELECT 1 FROM apartment_memberships WHERE apartment_id = $1 AND user_code = $2
     UNION
     SELECT 1 FROM apartments WHERE id = $1 AND resident_user_code = $2`,
    [apt.id, tUserCode],
  );
  if (memberCheck.rowCount === 0) {
    throw httpError(404, 'Kullanıcı bu daireye ait değil.');
  }

  // Mevcut şifre doğrulaması (401/403 değil 400: istemci oturumu kapatmasın).
  // PATCH /me ile AYNI hesap bazlı sayaç/kilit paylaşılır (5 hata -> 15 dk 429 CURRENT_PASSWORD_LOCKED):
  // iki uçtan hangisi kullanılırsa kullanılsın mevcut parola sınırsız denenemez.
  const throttleKey = passwordChangeThrottleKey(tUserCode);
  const lockState = passwordChangeFailureTracker.check(throttleKey);
  if (lockState.locked) {
    throw currentPasswordLockedError(lockState.retryAfterSeconds);
  }
  const hashRes = await pool.query(
    `SELECT password_hash FROM users WHERE user_code = $1 LIMIT 1`,
    [tUserCode],
  );
  if (hashRes.rowCount === 0) {
    throw httpError(404, 'Kullanıcı hesabı bulunamadı.');
  }
  const currentOk = await bcrypt.compare(cleanCurrent, hashRes.rows[0].password_hash);
  if (!currentOk) {
    const failure = passwordChangeFailureTracker.recordFailure(throttleKey);
    if (failure.locked) {
      throw currentPasswordLockedError(failure.retryAfterSeconds);
    }
    const invalidError = httpError(400, 'Mevcut şifre hatalı.');
    invalidError.code = 'CURRENT_PASSWORD_INVALID';
    throw invalidError;
  }
  passwordChangeFailureTracker.recordSuccess(throttleKey);

  const passwordHash = await bcrypt.hash(cleanPass, 10);

  // users tablosunu güncelle
  const updatedUserRes = await pool.query(
    `UPDATE users SET password_hash = $1, updated_at = NOW() WHERE user_code = $2
     RETURNING user_code AS id, email, role`,
    [passwordHash, tUserCode],
  );
  const updatedUser = updatedUserRes.rows[0];

  // Eğer legacy kolonu varsa apartments tablosunda da pin kodunu güncelle (tasarım gereği düz metin)
  if (isLegacyResident(apt, tUserCode)) {
    await pool.query(
      `UPDATE apartments SET resident_pin_code = $1 WHERE id = $2`,
      [cleanPass, apt.id],
    );
  }

  // Parola değişince (pv claim'i) eski token geçersiz olur; istemci oturumu kesilmesin diye yeni token döner (ek alan).
  const refreshedToken = updatedUser ? signAccessToken(updatedUser, { passwordHash }) : undefined;

  return {
    ok: true,
    message: 'Daire sakininin şifresi başarıyla güncellendi.',
    ...(refreshedToken ? { token: refreshedToken } : {}),
  };
}

/**
 * Aile Reisini Değiştir (Yeni Daire Yöneticisi / APARTMENT_ADMIN Ata)
 * (Süper Kullanıcı, Site Yöneticisi ve Daire Yöneticisi yetkilidir)
 * Pasif / çıkarılmış üye aile reisi yapılarak yeniden aktifleştirilemez (409).
 */
export async function setApartmentPrimaryAdmin({ apartmentId, targetUserCode, authUser }) {
  const { apt } = await checkApartmentManagementAccess(authUser, apartmentId);
  const tUserCode = parseTargetUserCode(targetUserCode);

  const client = await pool.connect();
  let committed = false;
  try {
    await client.query('BEGIN');
    const aptLock = await client.query(
      `SELECT id, site_code, resident_user_code FROM apartments WHERE id = $1 FOR UPDATE`,
      [apt.id],
    );
    const aptRow = aptLock.rows[0] || apt;

    // Kullanıcının bu dairede kayıtlı olduğunu doğrula
    const memberRes = await client.query(
      `SELECT role, is_active FROM apartment_memberships WHERE apartment_id = $1 AND user_code = $2`,
      [apt.id, tUserCode],
    );

    if (memberRes.rowCount === 0) {
      if (isLegacyResident(aptRow, tUserCode)) {
        await client.query('COMMIT');
        committed = true;
        return { ok: true, message: 'Bu kullanıcı zaten daire yöneticisidir.' };
      }
      throw httpError(404, 'Kullanıcı bu dairede kayıtlı değil.');
    }

    assertPrimaryAdminCandidate(memberRes.rows[0]);

    if (memberRes.rows[0].role === 'APARTMENT_ADMIN') {
      await client.query('COMMIT');
      committed = true;
      return { ok: true, message: 'Bu kullanıcı zaten dairenin Aile Reisidir (Daire Yöneticisi).' };
    }

    // 1. Mevcut tüm APARTMENT_ADMIN'leri FAMILY_MEMBER yap
    await client.query(
      `UPDATE apartment_memberships SET role = 'FAMILY_MEMBER', updated_at = NOW()
       WHERE apartment_id = $1 AND role = 'APARTMENT_ADMIN'`,
      [apt.id],
    );

    // 2. Hedef (aktif) kullanıcıyı APARTMENT_ADMIN yap
    await client.query(
      `UPDATE apartment_memberships SET role = 'APARTMENT_ADMIN', updated_at = NOW()
       WHERE apartment_id = $1 AND user_code = $2 AND is_active = TRUE`,
      [apt.id, tUserCode],
    );

    // 3. apartments.resident_user_code kolonunu güncelle
    await client.query(
      `UPDATE apartments SET resident_user_code = $1 WHERE id = $2`,
      [tUserCode, apt.id],
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

  return {
    ok: true,
    message: 'Aile Reisi (Daire Yöneticisi) başarıyla değiştirildi.',
  };
}

/**
 * ÜYELİK SİSTEMİ AŞAMA 11: Ek Kapı Yetkileri ve Toplu Yetkilendirme Servisi
 */

/**
 * Kapı yönetim yetkisi doğrulayıcı (Süper Kullanıcı, Site Yöneticisi veya Site Sahibi / Admini)
 */
export async function checkDoorManagementAccess(authUser, doorId) {
  const parsedDoorId = parsePositiveId(doorId);
  if (parsedDoorId === null) {
    throw httpError(400, 'Geçersiz kapı kimliği.');
  }

  const doorRes = await pool.query(
    `SELECT d.*, s.name AS site_name, sb.block_name
     FROM site_doors d
     JOIN sites s ON s.site_code = d.site_code
     LEFT JOIN site_blocks sb ON sb.id = d.block_id
     WHERE d.id = $1 LIMIT 1`,
    [parsedDoorId],
  );
  if (doorRes.rowCount === 0) {
    throw httpError(404, 'Kapı bulunamadı.');
  }
  const door = doorRes.rows[0];

  if (authUser?.role === 'super_user') {
    return door;
  }

  const userCode = authUserCodeOf(authUser);
  if (userCode === null) {
    throw httpError(403, 'Bu kapının yetkilerini yönetme yetkiniz bulunmamaktadır.');
  }

  // 1. site_manager_sites kontrolü
  const isManagerRes = await pool.query(
    `SELECT 1 FROM site_manager_sites WHERE site_code = $1 AND manager_user_code = $2 LIMIT 1`,
    [door.site_code, userCode],
  );
  if (isManagerRes.rowCount > 0) {
    return door;
  }

  // 2. site_memberships (SITE_OWNER veya SITE_ADMIN) kontrolü
  const isOwnerRes = await pool.query(
    `SELECT 1 FROM site_memberships WHERE site_code = $1 AND user_code = $2 AND role IN ('SITE_OWNER', 'SITE_ADMIN') AND is_active = TRUE LIMIT 1`,
    [door.site_code, userCode],
  );
  if (isOwnerRes.rowCount > 0) {
    return door;
  }

  throw httpError(403, 'Bu kapının yetkilerini yönetme yetkiniz bulunmamaktadır.');
}

/**
 * Belirli bir kapı için sitenin tüm blok, daire ve sakinlerini yetki durumuyla birlikte hiyerarşik listeler
 */
export async function getDoorPermissions({ doorId, authUser }) {
  const door = await checkDoorManagementAccess(authUser, doorId);
  const siteCode = Number(door.site_code);

  // 1. Sitenin tüm bloklarını çek
  const blocksRes = await pool.query(
    `SELECT id, site_code, block_name, sort_order
     FROM site_blocks
     WHERE site_code = $1
     ORDER BY sort_order ASC, id ASC`,
    [siteCode],
  );

  // 2. Sitedeki aktif daireleri ve sakinlerini çek
  const residentsRes = await pool.query(
    `SELECT
       a.id AS apartment_id,
       a.block_id,
       a.unit_label,
       a.sort_order AS apt_sort_order,
       u.user_code,
       u.full_name,
       u.email,
       COALESCE(am.role, 'APARTMENT_ADMIN') AS role
     FROM apartments a
     LEFT JOIN apartment_memberships am ON am.apartment_id = a.id AND am.is_active = TRUE
     LEFT JOIN users u ON u.user_code = COALESCE(am.user_code, a.resident_user_code)
     WHERE a.site_code = $1 AND a.is_active = TRUE AND u.user_code IS NOT NULL
     ORDER BY a.sort_order ASC, u.full_name ASC`,
    [siteCode],
  );

  // 3. Bu kapıya ait mevcut manuel yetki kayıtlarını (overrides) çek
  const overridesRes = await pool.query(
    `SELECT id, user_code, is_allowed, notes, updated_at
     FROM door_access_overrides
     WHERE door_id = $1`,
    [Number(door.id)],
  );
  const overrideMap = new Map();
  for (const row of overridesRes.rows) {
    overrideMap.set(Number(row.user_code), row);
  }

  // Daire sakinlerini grupla (blockId -> apartmentId -> residents)
  const aptResidentsMap = new Map(); // apartmentId -> list
  const aptInfoMap = new Map(); // apartmentId -> { id, block_id, unit_label, sort_order }

  for (const row of residentsRes.rows) {
    const aptId = Number(row.apartment_id);
    if (!aptInfoMap.has(aptId)) {
      aptInfoMap.set(aptId, {
        id: aptId,
        block_id: Number(row.block_id),
        unit_label: row.unit_label,
        sort_order: row.apt_sort_order,
      });
    }

    if (!aptResidentsMap.has(aptId)) {
      aptResidentsMap.set(aptId, []);
    }

    const uCode = Number(row.user_code);
    const override = overrideMap.get(uCode);

    let hasAccess = false;
    let accessSource = 'NO_ACCESS';

    if (override) {
      if (override.is_allowed === true) {
        hasAccess = true;
        accessSource = 'OVERRIDE_ALLOWED';
      } else {
        hasAccess = false;
        accessSource = 'OVERRIDE_DENIED';
      }
    } else {
      if (door.access_scope === 'SITE_COMMON') {
        hasAccess = true;
        accessSource = 'SITE_COMMON';
      } else if (door.access_scope === 'BLOCK' && door.block_id && Number(door.block_id) === Number(row.block_id)) {
        hasAccess = true;
        accessSource = 'BLOCK_DEFAULT';
      } else {
        hasAccess = false;
        accessSource = 'NO_ACCESS';
      }
    }

    aptResidentsMap.get(aptId).push({
      user_code: uCode,
      full_name: row.full_name,
      email: row.email,
      role: row.role,
      has_access: hasAccess,
      access_source: accessSource,
      override: override
        ? {
            id: Number(override.id),
            is_allowed: Boolean(override.is_allowed),
            notes: override.notes || null,
            updated_at: override.updated_at,
          }
        : null,
    });
  }

  // Blok bazlı ağacı oluştur
  let totalSiteResidents = 0;
  let totalSiteAuthorized = 0;

  const blocksTree = blocksRes.rows.map((blk) => {
    const blkId = Number(blk.id);
    const isDoorBlock = door.block_id ? Number(door.block_id) === blkId : false;

    // Bu bloğa ait daireleri filtrele
    const blkApartments = [];
    let blkResidentsCount = 0;
    let blkAuthorizedCount = 0;

    for (const [aptId, apt] of aptInfoMap.entries()) {
      if (apt.block_id === blkId) {
        const residents = aptResidentsMap.get(aptId) || [];
        blkResidentsCount += residents.length;
        const authorizedInApt = residents.filter((r) => r.has_access).length;
        blkAuthorizedCount += authorizedInApt;

        blkApartments.push({
          id: apt.id,
          unit_label: apt.unit_label,
          sort_order: apt.sort_order,
          residents,
          resident_count: residents.length,
          authorized_count: authorizedInApt,
        });
      }
    }

    totalSiteResidents += blkResidentsCount;
    totalSiteAuthorized += blkAuthorizedCount;

    return {
      id: blkId,
      block_name: blk.block_name,
      sort_order: blk.sort_order,
      is_door_block: isDoorBlock,
      total_residents: blkResidentsCount,
      authorized_count: blkAuthorizedCount,
      apartments: blkApartments,
    };
  });

  return {
    ok: true,
    door: {
      id: Number(door.id),
      site_code: siteCode,
      site_name: door.site_name,
      door_name: door.door_name,
      access_scope: door.access_scope,
      block_id: door.block_id ? Number(door.block_id) : null,
      block_name: door.block_name || null,
    },
    blocks: blocksTree,
    total_residents: totalSiteResidents,
    total_authorized: totalSiteAuthorized,
  };
}

/**
 * Tekil kullanıcı için kapı yetkisi tanımlar veya kaldırır (UPSERT / DELETE)
 * İzin kaldırma / reddetme / varsayılana döndürme erişimi daraltır: kapıdaki cihazın yerel kontrol
 * token'ı döndürülür (eski token ile yerel açma yapılamasın).
 */
export async function setDoorAccessOverride({
  doorId,
  userCode,
  isAllowed,
  notes = null,
  authUser,
}) {
  const door = await checkDoorManagementAccess(authUser, doorId);
  const targetUserCode = parseUserCode(userCode);
  if (targetUserCode === null) {
    throw httpError(400, 'Geçersiz kullanıcı kodu.');
  }
  const reviewerCode = authUserCodeOf(authUser);

  // isAllowed null veya undefined ise yetki sıfırlanır (varsayılana döner)
  if (isAllowed === null || isAllowed === undefined) {
    await pool.query(
      `DELETE FROM door_access_overrides WHERE door_id = $1 AND user_code = $2`,
      [Number(door.id), targetUserCode],
    );
    await rotateTokensForDevices({
      deviceIds: [door.assigned_device_id],
      reason: 'door_permission_reset',
    });
    return {
      ok: true,
      action: 'RESET',
      message: 'Kapı yetkisi varsayılan ayarlara döndürüldü.',
    };
  }

  const boolAllowed = parseBooleanFlag(isAllowed, 'isAllowed');
  const cleanNotes = notes ? String(notes).trim().slice(0, NOTE_MAX_LENGTH) : null;

  const targetRes = await pool.query(`SELECT 1 FROM users WHERE user_code = $1 LIMIT 1`, [targetUserCode]);
  if (targetRes.rowCount === 0) {
    throw httpError(404, 'Kullanıcı bulunamadı.');
  }

  const result = await pool.query(
    `INSERT INTO door_access_overrides (site_code, door_id, user_code, is_allowed, granted_by_user_code, notes, updated_at)
     VALUES ($1, $2, $3, $4, $5, $6, NOW())
     ON CONFLICT (door_id, user_code)
     DO UPDATE SET is_allowed = $4, granted_by_user_code = $5, notes = $6, updated_at = NOW()
     RETURNING id, site_code, door_id, user_code, is_allowed, notes, updated_at`,
    [Number(door.site_code), Number(door.id), targetUserCode, boolAllowed, reviewerCode, cleanNotes],
  );

  if (overrideRevokesAccess(boolAllowed)) {
    await rotateTokensForDevices({
      deviceIds: [door.assigned_device_id],
      reason: 'door_permission_denied',
    });
  }

  return {
    ok: true,
    action: boolAllowed ? 'GRANTED' : 'DENIED',
    override: result.rows[0],
    message: boolAllowed ? 'Ek kapı yetkisi başarıyla verildi.' : 'Kapı erişimi engellendi.',
  };
}

/**
 * Tüm bloğa, daireye veya kullanıcı listesine toplu yetki tanımlar veya kaldırır
 * blockId / apartmentId KAPININ SİTESİNE ait olmalıdır (başka sitenin sakinlerine yetki verilemez).
 */
export async function setBulkDoorAccessOverride({
  doorId,
  blockId = null,
  apartmentId = null,
  userCodes = null,
  isAllowed,
  notes = null,
  authUser,
}) {
  const door = await checkDoorManagementAccess(authUser, doorId);
  const reviewerCode = authUserCodeOf(authUser);
  const siteCode = Number(door.site_code);
  // 'false' gibi metinlerin sessizce true olmaması için katı ayrıştırma (null/undefined = varsayılana dön)
  const allowFlag = isAllowed === null || isAllowed === undefined
    ? null
    : parseBooleanFlag(isAllowed, 'isAllowed');

  let targetUserCodes = [];

  if (Array.isArray(userCodes) && userCodes.length > 0) {
    // Yalnızca gerçekten var olan kullanıcılar (FK hatasıyla 500 olmasın); int4 aralığı doğrulanır
    const candidates = sanitizeUserCodeList(userCodes);
    if (candidates.length > 0) {
      const existingRes = await pool.query(
        `SELECT user_code FROM users WHERE user_code = ANY($1::int[])`,
        [candidates],
      );
      targetUserCodes = existingRes.rows.map((r) => Number(r.user_code));
    }
  } else if (apartmentId) {
    const aptId = parsePositiveId(apartmentId);
    if (aptId === null) {
      throw httpError(400, 'Geçersiz daire kimliği.');
    }
    const aptRes = await pool.query(SQL_BULK_APARTMENT_USERS, [aptId, siteCode]);
    targetUserCodes = aptRes.rows.map((r) => Number(r.user_code));
  } else if (blockId) {
    const blkId = parsePositiveId(blockId);
    if (blkId === null) {
      throw httpError(400, 'Geçersiz blok kimliği.');
    }
    const blkRes = await pool.query(SQL_BULK_BLOCK_USERS, [blkId, siteCode]);
    targetUserCodes = blkRes.rows.map((r) => Number(r.user_code));
  } else {
    throw httpError(400, 'Toplu yetkilendirme için blok, daire veya kullanıcı listesi belirtilmelidir.');
  }

  if (targetUserCodes.length === 0) {
    return {
      ok: true,
      count: 0,
      message: 'Seçilen alanda aktif sakin bulunamadı.',
    };
  }

  const client = await pool.connect();
  let committed = false;
  try {
    await client.query('BEGIN');

    if (allowFlag === null) {
      await client.query(
        `DELETE FROM door_access_overrides
         WHERE door_id = $1 AND user_code = ANY($2::int[])`,
        [Number(door.id), targetUserCodes],
      );
    } else {
      const boolAllowed = allowFlag;
      const cleanNotes = notes ? String(notes).trim().slice(0, NOTE_MAX_LENGTH) : null;

      for (const uCode of targetUserCodes) {
        await client.query(
          `INSERT INTO door_access_overrides (site_code, door_id, user_code, is_allowed, granted_by_user_code, notes, updated_at)
           VALUES ($1, $2, $3, $4, $5, $6, NOW())
           ON CONFLICT (door_id, user_code)
           DO UPDATE SET is_allowed = $4, granted_by_user_code = $5, notes = $6, updated_at = NOW()`,
          [siteCode, Number(door.id), uCode, boolAllowed, reviewerCode, cleanNotes],
        );
      }
    }

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

  // Erişim daraltıldıysa (reddet / varsayılana dön) cihazın yerel kontrol token'ı döndürülür.
  if (overrideRevokesAccess(allowFlag)) {
    await rotateTokensForDevices({
      deviceIds: [door.assigned_device_id],
      reason: 'door_permission_bulk_revoked',
    });
  }

  const actionText = allowFlag === null
    ? 'varsayılan ayarlara döndürüldü'
    : (allowFlag ? 'ek yetki verildi' : 'erişim engellendi');

  return {
    ok: true,
    count: targetUserCodes.length,
    message: `${targetUserCodes.length} sakin için kapı yetkisi ${actionText}.`,
  };
}

/**
 * Site yönetim yetkisi kontrolü (super_user, site_manager_sites veya site_memberships OWNER/ADMIN)
 */
export async function checkSiteManagementAccess(authUser, siteCode) {
  const parsedSiteCode = parsePositiveId(siteCode);
  if (parsedSiteCode === null) {
    throw httpError(400, 'Geçersiz site kimliği.');
  }

  const siteRes = await pool.query(
    `SELECT site_code AS id, name, city, district, block_count, apartment_count, approval_status
     FROM sites
     WHERE site_code = $1
     LIMIT 1`,
    [parsedSiteCode],
  );
  if (siteRes.rowCount === 0) {
    throw httpError(404, 'Site bulunamadı.');
  }
  const site = siteRes.rows[0];

  if (authUser?.role === 'super_user') {
    return site;
  }

  const userCode = authUserCodeOf(authUser);
  if (userCode === null) {
    throw httpError(403, 'Bu sitenin sakinlerini görüntüleme yetkiniz bulunmamaktadır.');
  }

  // 1. site_manager_sites kontrolü
  const isManagerRes = await pool.query(
    `SELECT 1 FROM site_manager_sites WHERE site_code = $1 AND manager_user_code = $2 LIMIT 1`,
    [site.id, userCode],
  );
  if (isManagerRes.rowCount > 0) {
    return site;
  }

  // 2. site_memberships (SITE_OWNER veya SITE_ADMIN) kontrolü
  const isOwnerRes = await pool.query(
    `SELECT 1 FROM site_memberships WHERE site_code = $1 AND user_code = $2 AND role IN ('SITE_OWNER', 'SITE_ADMIN') AND is_active = TRUE LIMIT 1`,
    [site.id, userCode],
  );
  if (isOwnerRes.rowCount > 0) {
    return site;
  }

  throw httpError(403, 'Bu sitenin sakinlerini görüntüleme yetkiniz bulunmamaktadır.');
}

/**
 * Aşama 12: Sitenin tüm blok, daire ve sakinlerini hiyerarşik akordiyon ağacı olarak döndürür
 */
export async function getSiteResidentsTree({ siteCode, authUser }) {
  const site = await checkSiteManagementAccess(authUser, siteCode);
  const sCode = Number(site.id);

  // 1. Blokları çek
  const blocksRes = await pool.query(
    `SELECT id, site_code, block_name, sort_order
     FROM site_blocks
     WHERE site_code = $1
     ORDER BY sort_order ASC, id ASC`,
    [sCode],
  );

  // 2. Daireleri çek
  const aptsRes = await pool.query(
    `SELECT id, block_id, unit_label, sort_order, resident_pin_code
     FROM apartments
     WHERE site_code = $1 AND is_active = TRUE
     ORDER BY sort_order ASC, id ASC`,
    [sCode],
  );

  // 3. Sakinleri çek (yeni üyelikler)
  const membershipsRes = await pool.query(
    `SELECT
       am.apartment_id,
       am.user_code,
       am.role,
       am.created_at AS joined_at,
       u.full_name,
       u.email,
       u.phone_number,
       u.login_name,
       (am.is_active = TRUE AND u.is_active = TRUE) AS is_active,
       u.is_active AS account_is_active
     FROM apartment_memberships am
     INNER JOIN apartments a ON a.id = am.apartment_id
     INNER JOIN users u ON u.user_code = am.user_code
     WHERE a.site_code = $1
     ORDER BY (CASE WHEN am.role = 'APARTMENT_ADMIN' THEN 0 ELSE 1 END), am.created_at ASC`,
    [sCode],
  );

  // 4. Legacy sakinler (eski sistemde eklenip henüz yeni membership kaydı olmayanlar)
  const legacyRes = await pool.query(
    `SELECT
       a.id AS apartment_id,
       a.resident_user_code AS user_code,
       'APARTMENT_ADMIN' AS role,
       a.created_at AS joined_at,
       u.full_name,
       u.email,
       u.phone_number,
       u.login_name,
       (a.is_active = TRUE AND u.is_active = TRUE) AS is_active,
       u.is_active AS account_is_active
     FROM apartments a
     INNER JOIN users u ON u.user_code = a.resident_user_code
     WHERE a.site_code = $1 AND a.resident_user_code IS NOT NULL
       AND NOT EXISTS (
         SELECT 1 FROM apartment_memberships am
         WHERE am.apartment_id = a.id AND am.user_code = a.resident_user_code AND am.is_active = TRUE
       )`,
    [sCode],
  );

  // Daire -> sakinler haritası
  const aptResidentsMap = new Map();
  for (const r of [...membershipsRes.rows, ...legacyRes.rows]) {
    const aptId = Number(r.apartment_id);
    if (!aptResidentsMap.has(aptId)) {
      aptResidentsMap.set(aptId, []);
    }
    aptResidentsMap.get(aptId).push({
      user_code: Number(r.user_code),
      full_name: r.full_name,
      email: r.email || null,
      phone_number: r.phone_number || null,
      login_name: r.login_name || null,
      role: r.role,
      joined_at: r.joined_at,
      // is_active = üyelik VE hesap aktif; account_is_active = yalnız global hesap durumu (users.is_active)
      is_active: r.is_active !== false,
      account_is_active: r.account_is_active !== false,
    });
  }

  let totalSiteResidents = 0;
  let emptyApartmentsCount = 0;

  // Daireleri bloklara grupla
  const blockAptsMap = new Map();
  for (const apt of aptsRes.rows) {
    const bId = Number(apt.block_id);
    if (!blockAptsMap.has(bId)) {
      blockAptsMap.set(bId, []);
    }
    const aptId = Number(apt.id);
    const residents = aptResidentsMap.get(aptId) || [];
    if (residents.length === 0) {
      emptyApartmentsCount++;
    }
    totalSiteResidents += residents.length;

    blockAptsMap.get(bId).push({
      id: aptId,
      block_id: bId,
      unit_label: apt.unit_label,
      sort_order: apt.sort_order,
      resident_pin_code: apt.resident_pin_code || null,
      total_residents: residents.length,
      residents,
    });
  }

  const blocksTree = blocksRes.rows.map((blk) => {
    const bId = Number(blk.id);
    const apartments = blockAptsMap.get(bId) || [];
    const blkResidents = apartments.reduce((sum, a) => sum + a.total_residents, 0);

    return {
      id: bId,
      block_name: blk.block_name,
      sort_order: blk.sort_order,
      total_apartments: apartments.length,
      total_residents: blkResidents,
      apartments,
    };
  });

  return {
    ok: true,
    site: {
      id: sCode,
      name: site.name,
      city: site.city,
      district: site.district,
      total_blocks: blocksRes.rowCount,
      total_apartments: aptsRes.rowCount,
      total_residents: totalSiteResidents,
      empty_apartments_count: emptyApartmentsCount,
    },
    blocks: blocksTree,
  };
}





