// Telefon bildirimi (Faz 3b-B) ortak sabitleri, hataları ve saf yardımcıları. Saf: DB / ağ bağımsız.
//
// Sözleşme: docs/PLATFORM_BELGELER.md Bölüm B (B2-B7). Hata gövdesi { error, code } (PlatformError); INVALID_BODY mesajları alan adıyla DEĞİL
// Türkçe etiketle yazılır. Saat hesapları Europe/Istanbul: Türkiye UTC+03:00 sabittir, yaz saati yoktur (announcement_common.istanbulDayRange
// ile AYNI varsayım).

import { PlatformError } from './errors.js';

export const PLATFORMS = Object.freeze(['android', 'ios']);
/** Kullanıcı başına en çok kayıtlı cihaz; fazlası en eski last_seen_at'tan düşer. */
export const MAX_DEVICES_PER_USER = 10;
/** Kurulum kimliği (uygulamanın kurulumda ürettiği UUID; çökme raporu install_id'sinden AYRI). 16-64 karakter, yalnız güvenli ASCII. */
export const INSTALL_ID_PATTERN = /^[A-Za-z0-9][A-Za-z0-9._:-]{15,63}$/;
export const TOKEN_MIN_LENGTH = 20;
/**
 * Sözleşme (B2/B3) 4096 diyordu; `fcm_token` üzerindeki TEKİL btree dizininin satır sınırı ~2704 bayttır (gerçek PG'de 2800 karakter 54000 verdi).
 * Gerçek FCM jetonları ~150-250 karakterdir: doğrulayıcı ve 041 CHECK'i 2048 (inceleme kararı; sözleşmeden bilinçli sapma).
 */
export const TOKEN_MAX_LENGTH = 2048;
/** FCM kayıt jetonu: boşluksuz yazdırılabilir ASCII (gerçek jetonlar [A-Za-z0-9_:-]). */
const TOKEN_PATTERN = /^[\x21-\x7e]+$/;
export const APP_VERSION_PATTERN = /^[0-9A-Za-z][0-9A-Za-z.+_-]{0,31}$/;

export const OUTBOX_STATUSES = Object.freeze(['pending', 'sent', 'failed', 'skipped', 'expired']);
export const SKIP_REASONS = Object.freeze(['pref', 'withdrawn', 'capped', 'no_device', 'inactive']);

/** Kuyruk: 4. başarısız denemede `failed`; denemeler arası geri çekilme 60 / 300 / 1200 sn. */
export const MAX_PUSH_ATTEMPTS = 4;
export const PUSH_RETRY_DELAYS_SECONDS = Object.freeze([60, 300, 1200]);
/** Talebi bu kadar eski satır (süreç çökmüş) yeniden talep edilir. */
export const PUSH_CLAIM_STALE_MINUTES = 10;
export const PUSH_BATCH_SIZE = 100;
export const PUSH_BATCH_DELAY_MS = 200;
export const PUSH_MAX_RUN_MS = 10 * 60 * 1000;
export const PUSH_SEND_CONCURRENCY = 16;
/**
 * Cihaz kaydı kullanıcı kilidi: İKİ-int advisory anahtar (PUSH_DEVICE_LOCK_CLASS, user_code), işlem düzeyi (pg_advisory_xact_lock). Sınıf 0x50555348 =
 * "PUSH" (ASCII). Duyuru arka plan kilitlerinin sınıfından (announcement_lock.js 0x414E4E43 "ANNC") ve tek-int / hashtext anahtar uzayından AYRIDIR;
 * kullanıcı girdisinden etkilenmez. Aynı kullanıcının eşzamanlı kayıtlarını sıraya sokar (10 cihaz sınırı yarışı); başka akış bu anahtarı ALMAZ.
 */
export const PUSH_DEVICE_LOCK_CLASS = 0x50555348;
/** Toplu ölü jeton koruması: bir grupta en az bu kadar gönderim varsa ve yarıdan fazlası "ölü" ise hiçbir cihaz silinmez, devre kesici açılır. */
export const MASS_DEAD_MIN_SENDS = 20;
/** 429 (kota): Retry-After yoksa bu kadar, varsa en çok RATE_LIMIT_MAX_PAUSE_SECONDS kadar tur duraklatılır. */
export const RATE_LIMIT_DEFAULT_PAUSE_SECONDS = 60;
export const RATE_LIMIT_MAX_PAUSE_SECONDS = 600;
/**
 * Grup düzeyi toplu ölü koşulunun başarı oranı eşiği: gerçek ölü jetonlar (eski kurulumlar) başarıyla karışık gelir; grupta başarı yoksa ya da oran
 * %5'in altındaysa toplu ölü sayılır, aksi halde normal silme sürer (sonsuz 5 dk duraklama döngüsü olmasın).
 */
export const MASS_DEAD_MAX_SUCCESS_RATIO = 0.05;
/** Doğrulanmamış (bu hizmet hesabıyla henüz başarı görülmeden alınan) ölü sonuçlu satır bu kadar sonra yeniden denenir (deneme düşmez). */
export const DEAD_UNCONFIRMED_RETRY_SECONDS = 300;

/** 40P01 (deadlock) alan otomatik onaylı tek ifade BİR KEZ yeniden denenir. */
export async function retryOnDeadlock(run) {
  try {
    return await run();
  } catch (error) {
    if (error?.code !== '40P01') throw error;
    return run();
  }
}
/** Sessiz saat ertelemesi bundan uzun sürecekse satır `expired` olur. */
export const QUIET_MAX_DEFER_MS = 12 * 60 * 60 * 1000;
/** Yayından itibaren geçerlilik (outbox expires_at) ve FCM ttl. */
export const EXPIRY_HOURS = Object.freeze({ normal: 24, urgent: 48 });
export const TTL_SECONDS = Object.freeze({ normal: 86400, urgent: 172800 });
/** Sessiz saat varsayılanı 23:00-07:00 (gün içi dakika). */
export const DEFAULT_QUIET_START = 1380;
export const DEFAULT_QUIET_END = 420;
/** Bakım: biten satırlar 14 gün, hareketsiz cihaz 60 gün; kalıcı hatalı cihaz (>= 5 hata, 30 gündür başarı yok). */
export const OUTBOX_RETENTION_DAYS = 14;
export const DEVICE_IDLE_DAYS = 60;
export const DEVICE_FAILURE_LIMIT = 5;
export const DEVICE_FAILURE_DAYS = 30;

// --- Hatalar ---------------------------------------------------------------------------------------------

export const pushUnavailable = () => new PlatformError(503, 'PUSH_UNAVAILABLE', 'Telefon bildirimi şu an kullanılamıyor.');
export const invalidPushField = (message) => new PlatformError(400, 'INVALID_BODY', message);
export const pushAccountDeleted = () => new PlatformError(401, 'ACCOUNT_DELETED', 'Bu hesap silinmiş.');

// --- Doğrulayıcılar --------------------------------------------------------------------------------------

export function parseInstallId(value) {
  return typeof value === 'string' && INSTALL_ID_PATTERN.test(value) ? value : null;
}

export function isValidToken(value) {
  return (
    typeof value === 'string' &&
    value.length >= TOKEN_MIN_LENGTH &&
    value.length <= TOKEN_MAX_LENGTH &&
    TOKEN_PATTERN.test(value)
  );
}

/**
 * PUT /app/push/devices gövdesi -> { installId, platform, token, appVersion (null = değişmez), notificationsEnabled (null = değişmez) }.
 * Mesajlar alan adı içermez; jeton değeri hiçbir hata mesajına girmez.
 */
export function parseDeviceInput(body) {
  const input = body && typeof body === 'object' && !Array.isArray(body) ? body : {};
  const installId = parseInstallId(input.install_id);
  if (installId === null) {
    throw invalidPushField('Kurulum kimliği geçersiz.');
  }
  if (typeof input.platform !== 'string' || !PLATFORMS.includes(input.platform)) {
    throw invalidPushField('Platform geçersiz (android veya ios olmalıdır).');
  }
  if (!isValidToken(input.token)) {
    throw invalidPushField('Bildirim jetonu geçersiz.');
  }
  let appVersion = null;
  if (input.app_version !== undefined && input.app_version !== null) {
    if (typeof input.app_version !== 'string' || !APP_VERSION_PATTERN.test(input.app_version)) {
      throw invalidPushField('Uygulama sürümü geçersiz.');
    }
    appVersion = input.app_version;
  }
  let notificationsEnabled = null;
  if (input.notifications_enabled !== undefined && input.notifications_enabled !== null) {
    if (typeof input.notifications_enabled !== 'boolean') {
      throw invalidPushField('Bildirim izni bilgisi geçersiz (açık veya kapalı olmalıdır).');
    }
    notificationsEnabled = input.notifications_enabled;
  }
  return { installId, platform: input.platform, token: input.token, appVersion, notificationsEnabled };
}

// --- Saat yardımcıları (Europe/Istanbul) -----------------------------------------------------------------

const ISTANBUL_OFFSET_MS = 3 * 60 * 60 * 1000;
const DAY_MS = 24 * 60 * 60 * 1000;
const MINUTE_MS = 60 * 1000;

/** "HH:MM" -> gün içi dakika (0-1439); geçersizse null. */
export function parseHhmm(value) {
  if (typeof value !== 'string') {
    return null;
  }
  const match = /^([01]\d|2[0-3]):([0-5]\d)$/.exec(value);
  return match ? Number(match[1]) * 60 + Number(match[2]) : null;
}

/** Gün içi dakika -> "HH:MM" (geçersiz değer varsayılana döner). */
export function formatHhmm(minutes, fallback = 0) {
  const value = Number.isInteger(Number(minutes)) && Number(minutes) >= 0 && Number(minutes) <= 1439 ? Number(minutes) : fallback;
  return `${String(Math.floor(value / 60)).padStart(2, '0')}:${String(value % 60).padStart(2, '0')}`;
}

/** Anın İstanbul gün içi dakikası. */
export function istanbulMinuteOfDay(nowMs) {
  return Math.floor((((nowMs + ISTANBUL_OFFSET_MS) % DAY_MS) + DAY_MS) % DAY_MS / MINUTE_MS);
}

/** Anın İstanbul takvim günü başlangıcı (ms). Günlük üst sınır bu andan itibaren sayılır. */
export function istanbulDayStartMs(nowMs) {
  return Math.floor((nowMs + ISTANBUL_OFFSET_MS) / DAY_MS) * DAY_MS - ISTANBUL_OFFSET_MS;
}

/** Sessiz pencere içinde mi? Pencere geceyi aşabilir (23:00-07:00): başlangıç dahil, bitiş hariç. start === end ise pencere yok. */
export function isInQuietWindow(minuteOfDay, start, end) {
  if (start === end) {
    return false;
  }
  return start < end ? minuteOfDay >= start && minuteOfDay < end : minuteOfDay >= start || minuteOfDay < end;
}

/** Pencere içindeki bir andan sonra pencerenin BİTTİĞİ ilk an (ms; dakika başı). */
export function quietWindowEndMs(nowMs, end) {
  const dayStart = istanbulDayStartMs(nowMs);
  let candidate = dayStart + end * MINUTE_MS;
  if (candidate <= nowMs) {
    candidate += DAY_MS;
  }
  return candidate;
}

/**
 * Normal duyuru için sessiz saat kararı: { defer: false } | { defer: true, untilMs } | { expire: true }.
 * Acil duyuru sessiz saatleri YOK SAYAR (çağıran hiç sormaz). 12 saatten uzun erteleme ya da geçerlilik sonunu aşan erteleme -> expire.
 */
export function quietDecision({ nowMs, enabled, start, end, expiresAtMs }) {
  if (enabled !== true || !isInQuietWindow(istanbulMinuteOfDay(nowMs), start, end)) {
    return { defer: false };
  }
  const untilMs = quietWindowEndMs(nowMs, end);
  if (untilMs - nowMs > QUIET_MAX_DEFER_MS || (Number.isFinite(expiresAtMs) && untilMs >= expiresAtMs)) {
    return { expire: true };
  }
  return { defer: true, untilMs };
}

/** attempts (1..) sonrası geri çekilme (sn). */
export function retryDelaySeconds(attempts) {
  const index = Math.min(Math.max(Number(attempts) || 1, 1), PUSH_RETRY_DELAYS_SECONDS.length) - 1;
  return PUSH_RETRY_DELAYS_SECONDS[index];
}

/** Hata kodu (günlük / DB): yalnız [A-Z0-9_], en çok 64 karakter. Yanıt gövdesinden metin taşınmaz. */
export function sanitizeErrorCode(value, fallback = 'ERROR') {
  const text = String(value ?? '')
    .toUpperCase()
    .replace(/[^A-Z0-9_]+/g, '_')
    .replace(/^_+|_+$/g, '')
    .slice(0, 64);
  return text === '' ? fallback : text;
}
