// Kalıcı (DB tabanlı) deneme sınırları: auth_attempt_limits (migrations/085). Yeniden başlatmada / dağıtımda SIFIRLANMAZ.
//
// Neden: giriş koruması (security/login_guard.js) bilerek bellek içidir; her PM2 yeniden başlatması sayaçları sıfırlar ve kaynak (IP) değiştiren
// saldırgan hesap başına yavaş ama sürekli tahmin yapabilir. 4 haneli ilk PIN (9000 değer) ve 6 haneli e-posta / SMS kodu (1 milyon değer) için
// bu yetmez; burada HESAP / ADRES / TELEFON başına kalıcı bir sayaç tutulur. Yazma yükü (kimliksiz uçta DoS yüzeyi) şöyle sınırlanır: yalnız
// var olan "ilk PIN" hesaplarının (daire PIN'i) ve gerçekten KARŞILAŞTIRILAN yanlış kodların başarısızlığı yazılır; kilitliyken satıra yazılmaz.
//
// Anahtar: (scope, target). target = SHA-256 özeti (e-posta / telefon / hesap bu tabloda düz metin tutulmaz). PIN hedefi parola ÖZETİNİ de içerir:
// PIN yenilenince (yönetici sıfırlaması, parola sıfırlama, parola değişimi) özet değişir ve sayaç kendiliğinden sıfırdan başlar.
//
// Davranış (tek ifade, atomik; ON CONFLICT satır kilidi eşzamanlı istekleri sıraya dizer):
//   - Pencere (windowMinutes) içinde maxFailures yanlış -> kilit: baseLockMinutes; kilit biter bitmez sayaç sıfırdan başlar.
//   - Her yeni kilit bir öncekinin iki katı sürer (en çok maxLockMinutes); quietMinutes hatasız geçerse seviye sıfırlanır.
//   - Kilitliyken deneme SAYILMAZ ve satıra YAZILMAZ (blocked). Başarılı doğrulama satırı siler (resetAttempts).
//   - Kilit kararı karşılaştırmadan ÖNCE verilebilir (registerAttemptFailure "rezerve et"; doğruysa resetAttempts ile iade) -> paralel N istek
//     N tahmin yapamaz.

import crypto from 'node:crypto';
import { pool } from '../db.js';
import { PlatformError } from '../modules/errors.js';

const DAY_MINUTES = 24 * 60;

function freezePolicy(policy) {
  const { scope, maxFailures, windowMinutes, baseLockMinutes, maxLockMinutes, quietMinutes } = policy;
  const valid =
    typeof scope === 'string' &&
    scope.length > 0 &&
    scope.length <= 40 &&
    Number.isInteger(maxFailures) &&
    maxFailures >= 2 &&
    Number.isInteger(windowMinutes) &&
    windowMinutes >= 1 &&
    Number.isInteger(baseLockMinutes) &&
    baseLockMinutes >= 1 &&
    Number.isInteger(maxLockMinutes) &&
    maxLockMinutes >= baseLockMinutes &&
    Number.isInteger(quietMinutes) &&
    quietMinutes >= 1;
  if (!valid) {
    throw new Error(`Gecersiz deneme siniri ilkesi: ${scope}`);
  }
  return Object.freeze({ ...policy });
}

/**
 * İlkeler. Eşikler:
 *  - apartmentPin: 4 haneli ilk PIN. 5 yanlış -> 15 dk kilit (423); tekrarında 30 dk, 60 dk ... en çok 24 sa. Pencere 24 sa: yavaş (sınırın altında)
 *    tahmin de sayılır. 24 sa hatasız geçerse seviye sıfırlanır.
 *  - emailCode / smsCode: kod başına 5 deneme (kod geçersiz olur, yeni kod istenir) ZATEN kod tablolarında uygulanır; buradaki sayaç kodlar ARASI
 *    birikimlidir (yeni kod istemek sayacı sıfırlamaz): 24 saatte 15 yanlış -> 1 sa kilit, tekrarında 2 sa ... en çok 24 sa.
 */
export const ATTEMPT_POLICIES = Object.freeze({
  apartmentPin: freezePolicy({
    scope: 'apartment_pin',
    maxFailures: 5,
    windowMinutes: DAY_MINUTES,
    baseLockMinutes: 15,
    maxLockMinutes: DAY_MINUTES,
    quietMinutes: DAY_MINUTES,
  }),
  emailCode: freezePolicy({
    scope: 'email_code',
    maxFailures: 15,
    windowMinutes: DAY_MINUTES,
    baseLockMinutes: 60,
    maxLockMinutes: DAY_MINUTES,
    quietMinutes: DAY_MINUTES,
  }),
  smsCode: freezePolicy({
    scope: 'sms_code',
    maxFailures: 15,
    windowMinutes: DAY_MINUTES,
    baseLockMinutes: 60,
    maxLockMinutes: DAY_MINUTES,
    quietMinutes: DAY_MINUTES,
  }),
});

/** Hedef anahtarı: parçaların SHA-256 özeti (hex, 64). E-posta küçük harfe çevrilmiş olarak verilmelidir. */
export function attemptTarget(...parts) {
  return crypto
    .createHash('sha256')
    .update(parts.map((part) => String(part ?? '')).join('\u0000'))
    .digest('hex');
}

/** Daire PIN'i hedefi: hesap + o anki parola ÖZETİ (özet değişince sayaç sıfırlanır). */
export function apartmentPinTarget(userCode, passwordHash) {
  return attemptTarget('apartment_pin', Number(userCode), passwordHash);
}

export function emailCodeTarget(email) {
  return attemptTarget('email_code', String(email ?? '').trim().toLowerCase());
}

export function smsCodeTarget(phone) {
  return attemptTarget('sms_code', String(phone ?? '').trim());
}

// --- SQL --------------------------------------------------------------------------------------------------------------
// Parametreler: $1 scope, $2 target, $3 maxFailures, $4 windowMinutes, $5 baseLockMinutes, $6 maxLockMinutes, $7 quietMinutes.
// DO UPDATE içindeki sütun adları ESKİ satırı gösterir (l.*); aynı ifade parçaları her SET'te yeniden hesaplanır.
const WINDOW_EXPIRED = `l.window_started_at <= NOW() - ($4::int * INTERVAL '1 minute')`;
const NEXT_COUNT = `(CASE WHEN ${WINDOW_EXPIRED} THEN 1 ELSE l.fail_count + 1 END)`;
const TRIPS = `(${NEXT_COUNT} >= $3::int)`;
const QUIET = `(GREATEST(l.updated_at, COALESCE(l.locked_until, l.updated_at)) <= NOW() - ($7::int * INTERVAL '1 minute'))`;
const LEVEL = `(CASE WHEN ${QUIET} THEN 0 ELSE l.lock_level END)`;

/**
 * Bir başarısızlığı yazar (ya da karşılaştırmadan önce rezerve eder). Kilitli satırda güncelleme YAPILMAZ (0 satır döner).
 * RETURNING: fail_count, lock_level, locked_until, locked (BU ifade kilidi koydu mu), retry_after_seconds.
 */
export const SQL_REGISTER_FAILURE = `
INSERT INTO auth_attempt_limits AS l (scope, target, fail_count, window_started_at, locked_until, lock_level, updated_at)
VALUES ($1, $2, 1, NOW(), NULL, 0, NOW())
ON CONFLICT (scope, target) DO UPDATE SET
  fail_count = CASE WHEN ${TRIPS} THEN 0 ELSE ${NEXT_COUNT} END,
  window_started_at = CASE WHEN ${TRIPS} OR ${WINDOW_EXPIRED} THEN NOW() ELSE l.window_started_at END,
  lock_level = CASE WHEN ${TRIPS} THEN LEAST(${LEVEL} + 1, 20)::smallint ELSE ${LEVEL}::smallint END,
  locked_until = CASE WHEN ${TRIPS}
    THEN NOW() + (LEAST($5::float8 * power(2::float8, ${LEVEL}::float8), $6::float8) * INTERVAL '1 minute')
    ELSE NULL END,
  updated_at = NOW()
WHERE l.locked_until IS NULL OR l.locked_until <= NOW()
RETURNING l.fail_count, l.lock_level, l.locked_until,
  (l.locked_until IS NOT NULL AND l.locked_until > NOW()) AS locked,
  GREATEST(1, CEIL(EXTRACT(EPOCH FROM (l.locked_until - NOW()))))::int AS retry_after_seconds
`;

/** Salt okuma: satır KİLİTLİYSE kalan süre döner (satır yoksa / kilit bitmişse 0 satır). */
export const SQL_PEEK_LOCK = `
SELECT GREATEST(1, CEIL(EXTRACT(EPOCH FROM (locked_until - NOW()))))::int AS retry_after_seconds
FROM auth_attempt_limits
WHERE scope = $1 AND target = $2 AND locked_until IS NOT NULL AND locked_until > NOW()
`;

export const SQL_RESET_ATTEMPTS = `DELETE FROM auth_attempt_limits WHERE scope = $1 AND target = $2`;

/** Bakım: 30 gündür dokunulmamış ve kilidi bitmiş satırlar. */
export const SQL_PURGE_STALE_ATTEMPTS = `
DELETE FROM auth_attempt_limits
WHERE updated_at < NOW() - INTERVAL '30 days' AND (locked_until IS NULL OR locked_until < NOW())
`;

// --- İşlemler ---------------------------------------------------------------------------------------------------------

/**
 * Kilit olayı kancası (izleme / uyarı; test için değiştirilebilir). Yalnızca kilidi KOYAN çağrıda çalışır. Kişisel veri yok: anahtar zaten SHA-256 özetidir,
 * günlüğe yalnız ilk 10 karakteri yazılır (e-posta / telefon / hesap / parola yazılmaz).
 */
export const attemptLimitHooks = {
  onLock(event) {
    // eslint-disable-next-line no-console
    console.warn(`[attempt-limits] kilit kapsam=${event.scope} seviye=${event.level} sure_sn=${event.retryAfterSeconds} anahtar=${event.key}`);
  },
};

/**
 * Kilitli mi? (yazmaz). Kilitliyse { locked: true, retryAfterSeconds }.
 * @param {typeof ATTEMPT_POLICIES[keyof typeof ATTEMPT_POLICIES]} policy
 * @param {{ query: Function }} [db] havuz ya da işlem istemcisi
 */
export async function peekAttemptLock(policy, target, db = pool) {
  const result = await db.query(SQL_PEEK_LOCK, [policy.scope, target]);
  const row = result?.rows?.[0];
  if (!row) {
    return { locked: false, retryAfterSeconds: 0 };
  }
  return { locked: true, retryAfterSeconds: Math.max(1, Number(row.retry_after_seconds) || 1) };
}

/**
 * Bir başarısızlık yazar. Dönüş:
 *  - blocked: hedef ZATEN kilitliydi (hiçbir şey yazılmadı); retryAfterSeconds kalan süre (en az 1). Rezerve eden çağıran bu durumda
 *    karşılaştırma YAPMAMALIDIR (PIN girişi: 423).
 *  - locked: kilit şu an etkin (bu çağrı kilidi koydu YA DA zaten kilitliydi); retryAfterSeconds kalan süre.
 *  - failures: penceredeki yanlış sayısı (kilit koyunca 0).
 */
export async function registerAttemptFailure(policy, target, db = pool) {
  const result = await db.query(SQL_REGISTER_FAILURE, [
    policy.scope,
    target,
    policy.maxFailures,
    policy.windowMinutes,
    policy.baseLockMinutes,
    policy.maxLockMinutes,
    policy.quietMinutes,
  ]);
  const row = result?.rows?.[0];
  if (row) {
    const locked = row.locked === true;
    const retryAfterSeconds = locked ? Math.max(1, Number(row.retry_after_seconds) || 1) : 0;
    if (locked) {
      try {
        attemptLimitHooks.onLock({ scope: policy.scope, level: Number(row.lock_level) || 0, retryAfterSeconds, key: String(target).slice(0, 10) });
      } catch (_error) {
        // günlük hatası doğrulamayı etkilemez
      }
    }
    return { blocked: false, locked, retryAfterSeconds, failures: Number(row.fail_count) || 0 };
  }
  // Güncelleme yapılmadı: satır var ve kilitli (DO UPDATE ... WHERE). Kalan süre ayrıca okunur.
  const state = await peekAttemptLock(policy, target, db);
  return { blocked: true, locked: state.locked, retryAfterSeconds: state.locked ? state.retryAfterSeconds : 1, failures: null };
}

/** Başarılı doğrulama: sayaç ve seviye sıfırlanır (satır silinir). */
export async function resetAttempts(policy, target, db = pool) {
  await db.query(SQL_RESET_ATTEMPTS, [policy.scope, target]);
}

/** Bakım temizliği (services/maintenance_service.js). */
export async function purgeStaleAttemptLimits(db = pool) {
  const result = await db.query(SQL_PURGE_STALE_ATTEMPTS);
  return result?.rowCount ?? 0;
}

// --- Türkçe kullanıcı mesajları ------------------------------------------------------------------------------------------

/** Kalan süre metni: 45 saniye / 15 dakika / 24 saat. */
export function formatWaitTr(seconds) {
  const total = Math.max(1, Math.ceil(Number(seconds) || 1));
  if (total < 60) {
    return `${total} saniye`;
  }
  const minutes = Math.ceil(total / 60);
  if (minutes < 60) {
    return `${minutes} dakika`;
  }
  return `${Math.ceil(minutes / 60)} saat`;
}

/** 423 PIN_LOCKED gövdesi (POST /auth/login). */
export function pinLockedBody(retryAfterSeconds) {
  const seconds = Math.max(1, Math.ceil(Number(retryAfterSeconds) || 1));
  return {
    error:
      `Bu hesap için çok fazla hatalı PIN denemesi yapıldı. Güvenliğiniz için giriş geçici olarak kilitlendi. ` +
      `Lütfen ${formatWaitTr(seconds)} sonra tekrar deneyin ya da site yönetiminizden PIN'inizi yenilemesini isteyin.`,
    code: 'PIN_LOCKED',
    retry_after_seconds: seconds,
  };
}

/**
 * Kod doğrulama kilidi (423). kind: 'email' -> VERIFICATION_LOCKED, 'sms' -> SMS_CODE_LOCKED.
 * Gövdeye retry_after_seconds eklenir (PlatformError.extra); yanıtlayıcılar Retry-After başlığını da yazar.
 */
export function codeLockedError(kind, retryAfterSeconds) {
  const seconds = Math.max(1, Math.ceil(Number(retryAfterSeconds) || 1));
  return new PlatformError(
    423,
    kind === 'sms' ? 'SMS_CODE_LOCKED' : 'VERIFICATION_LOCKED',
    `Çok fazla hatalı doğrulama kodu denemesi yapıldı. Güvenliğiniz için kod doğrulama geçici olarak kapatıldı; ` +
      `lütfen ${formatWaitTr(seconds)} sonra yeni bir kod isteyerek tekrar deneyin.`,
    { retry_after_seconds: seconds },
  );
}
