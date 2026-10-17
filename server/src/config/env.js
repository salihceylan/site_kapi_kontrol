// Ortam degiskenleri dogrulamasi (sirlari ASLA loglamaz; yalnizca uzunluk/ad bilgisi verir).

import { resolveTrustProxy } from '../security/trust_proxy.js';
import { pushEnvWarnings } from '../modules/push_config.js';

export const MIN_RECOMMENDED_JWT_SECRET_LENGTH = 32;

// Acikca "doldurulmamis" oldugu belli yer tutucu degerler (kucuk harfe cevrilip karsilastirilir).
const PLACEHOLDER_EXACT = new Set([
  'secret',
  'jwt_secret',
  'jwtsecret',
  'jwt-secret',
  'password',
  'changeme',
  'change_me',
  'change-me',
  'change_this_secret',
  'change-this-secret',
  'changethissecret',
  'your_secret',
  'your-secret',
  'yoursecret',
  'your_jwt_secret',
  'your-jwt-secret',
  'replace_me',
  'replace-me',
  'todo',
  'test',
  'example',
  'placeholder',
  'undefined',
  'null',
]);

const PLACEHOLDER_PATTERNS = [
  /^change[-_ ]?(me|this)([-_ ].*)?$/i,
  /^(your|my)[-_ ]?(jwt[-_ ]?)?(super[-_ ]?)?(secret|key)([-_ ].*)?$/i,
  /^replace[-_ ]?(me|with|this)([-_ ].*)?$/i,
  /^<[^>]*>$/, // <JWT_SECRET>
  /^\$\{[^}]*\}$/, // ${JWT_SECRET}
  /^(x{3,}|\*{3,}|0{6,}|1{6,})$/i,
];

export function isPlaceholderSecret(value) {
  const text = String(value ?? '').trim();
  if (!text) {
    return true;
  }
  const lowered = text.toLowerCase();
  if (PLACEHOLDER_EXACT.has(lowered)) {
    return true;
  }
  return PLACEHOLDER_PATTERNS.some((pattern) => pattern.test(text));
}

/**
 * JWT secret degerlendirmesi.
 * - bos / yer tutucu  -> ok:false (baslatma reddedilir)
 * - 32 karakterden kisa -> ok:true + warning (uretimde secret 20 karakter; sunucu ACILMALI)
 */
export function evaluateJwtSecret(secret) {
  if (isPlaceholderSecret(secret)) {
    return {
      ok: false,
      message:
        'JWT_SECRET tanimli degil veya yer tutucu bir deger. Guclu, rastgele bir secret tanimlayin.',
    };
  }
  const length = String(secret).length;
  if (length < MIN_RECOMMENDED_JWT_SECRET_LENGTH) {
    return {
      ok: true,
      warning:
        `JWT_SECRET ${length} karakter; en az ${MIN_RECOMMENDED_JWT_SECRET_LENGTH} karakter onerilir. ` +
        'Secret dondurulmeli: eskisi JWT_SECRET_PREVIOUS + JWT_SECRET_PREVIOUS_UNTIL ile gecis suresince dogrulamada kabul edilir ' +
        '(mevcut oturumlar o ana dek dusmez).',
    };
  }
  return { ok: true };
}

// Sır dönüşümü notu (uyarılarda): PREVIOUS'tan bir sırrı silmek, o sırla atılmış eski bağlantıları ve (henüz güncel tuza taşınmamış) bastırma
// kayıtlarını geçersiz kılar. Sunucu eski tuzla eşleşen bastırmayı yayın / kuyruk sırasında güncel tuza da yazar (sessiz geçiş), ama bunun için
// sırrın en az bir gönderim turu boyunca PREVIOUS'ta kalması gerekir.
const ANNOUNCEMENT_ROTATION_NOTE =
  "PREVIOUS'tan bir sir silinirse o sirla kayitli abonelikten cikma kayitlari (guncel tuza tasinmadiysa) ve eski baglantilar gecersiz olur; " +
  'PREVIOUS degerleri virgul iceremez (virgul ayirici), her sir bas/son bosluksuz en az 8 karakter olmalidir.';

function isSet(env, name) {
  return String(env[name] ?? '').trim().length > 0;
}

// jsonwebtoken "expiresIn" bicimi: sayi (saniye) veya "30d", "12h", "15m", "2 days" gibi.
export function isValidExpiresIn(value) {
  const text = String(value ?? '').trim();
  if (!text) {
    return false;
  }
  return /^\d+$/.test(text) || /^\d+\s*(ms|s|m|h|d|w|y|sec|secs|second|seconds|min|mins|minute|minutes|hr|hrs|hour|hours|day|days|week|weeks|year|years)$/i.test(text);
}

// ---- JWT omru / gecis / pv (S-C sertlestirme) ----------------------------------------------------

export const DEFAULT_JWT_EXPIRES_SECONDS = 30 * 24 * 60 * 60;
// Ust sinir: daha uzun JWT_EXPIRES_IN degerleri (canlida 365d) bu sureye KIRPILIR. Calinan bir oturumun (kayip telefon)
// gecerli kaldigi sureyi sinirlar; parola degisimi (pv) disinda sunucu tarafli iptal yoktur.
export const MAX_JWT_EXPIRES_SECONDS = 90 * 24 * 60 * 60;
// JWT_SECRET_PREVIOUS_UNTIL bu kadar ileriyse uyarilir (gecis penceresi kisa tutulmali).
export const MAX_PREVIOUS_SECRET_WINDOW_MS = 90 * 24 * 60 * 60 * 1000;

const DURATION_UNITS_SECONDS = new Map([
  ['ms', 0.001],
  ['s', 1], ['sec', 1], ['secs', 1], ['second', 1], ['seconds', 1],
  ['m', 60], ['min', 60], ['mins', 60], ['minute', 60], ['minutes', 60],
  ['h', 3600], ['hr', 3600], ['hrs', 3600], ['hour', 3600], ['hours', 3600],
  ['d', 86400], ['day', 86400], ['days', 86400],
  ['w', 604800], ['week', 604800], ['weeks', 604800],
  ['y', 31557600], ['year', 31557600], ['years', 31557600],
]);

/**
 * JWT_EXPIRES_IN -> saniye. Yalnizca rakam = SANIYE (jsonwebtoken'a ham dize verilseydi "3600" milisaniye sayilirdi:
 * 3,6 saniyelik token). Gecersiz/bos -> null.
 */
export function parseExpiresInSeconds(value) {
  const text = String(value ?? '').trim();
  if (!isValidExpiresIn(text)) {
    return null;
  }
  if (/^\d+$/.test(text)) {
    return Number(text);
  }
  const match = /^(\d+)\s*([a-z]+)$/i.exec(text);
  const factor = DURATION_UNITS_SECONDS.get(match[2].toLowerCase());
  return Math.floor(Number(match[1]) * factor);
}

/** Imzalamada kullanilacak omur (saniye): gecersiz -> 30 gun, 0 -> 30 gun, ust sinir 90 gun. */
export function resolveJwtExpiresSeconds(env = process.env) {
  const parsed = parseExpiresInSeconds(env?.JWT_EXPIRES_IN);
  if (parsed === null || parsed <= 0) {
    return DEFAULT_JWT_EXPIRES_SECONDS;
  }
  return Math.min(parsed, MAX_JWT_EXPIRES_SECONDS);
}

/**
 * pv (parola surumu) claim'i ZORUNLU mu? Varsayilan: HER ZAMAN zorunlu (NODE_ENV'den bagimsiz; canlida NODE_ENV tanimsiz
 * olabilir). Yalnizca acikca JWT_REQUIRE_PV=0 (false/no/off) ile kapatilir ve acilista uyari verilir. Zorunluyken pv'siz
 * token reddedilir: sir zayif/sizmis olsa bile sahte token uretmek icin hedef hesabin parola ozeti de bilinmelidir.
 * (pv 2026-10-02'den beri her girisle uretilir; daha eski pv'siz tokenlar bir kez yeniden giris ister.)
 */
const PV_DISABLED_VALUES = ['0', 'false', 'no', 'off'];
const PV_ENABLED_VALUES = ['1', 'true', 'yes', 'on'];

export function isPasswordVersionRequired(env = process.env) {
  const raw = String(env?.JWT_REQUIRE_PV ?? '').trim().toLowerCase();
  return !PV_DISABLED_VALUES.includes(raw);
}

/**
 * Sir dondurme gecisi: JWT_SECRET_PREVIOUS yalnizca DOGRULAMA icin ve yalnizca JWT_SECRET_PREVIOUS_UNTIL anina kadar
 * kabul edilir; yeni tokenlar her zaman JWT_SECRET ile imzalanir. UNTIL yoksa/gecersizse/gecmisse eski sir KULLANILMAZ
 * (suresiz kabul olmasin). Deger hicbir zaman donmez/loglanmaz; yalnizca durum.
 * @returns {{ secret: string|null, status: 'none'|'active'|'expired'|'missing_until'|'invalid_until'|'placeholder'|'same_as_current', untilMs: number|null }}
 */
export function resolvePreviousJwtSecret(env = process.env, nowMs = Date.now()) {
  const previous = String(env?.JWT_SECRET_PREVIOUS ?? '').trim();
  if (!previous) {
    return { secret: null, status: 'none', untilMs: null };
  }
  if (isPlaceholderSecret(previous) || previous.length < 16) {
    return { secret: null, status: 'placeholder', untilMs: null };
  }
  if (previous === String(env?.JWT_SECRET ?? '')) {
    return { secret: null, status: 'same_as_current', untilMs: null };
  }
  const untilText = String(env?.JWT_SECRET_PREVIOUS_UNTIL ?? '').trim();
  if (!untilText) {
    return { secret: null, status: 'missing_until', untilMs: null };
  }
  const untilMs = Date.parse(untilText);
  if (!Number.isFinite(untilMs)) {
    return { secret: null, status: 'invalid_until', untilMs: null };
  }
  if (untilMs <= nowMs) {
    return { secret: null, status: 'expired', untilMs };
  }
  return { secret: previous, status: 'active', untilMs };
}

function jwtHardeningWarnings(env, isProduction) {
  const warnings = [];
  const secretLength = String(env.JWT_SECRET ?? '').length;
  if (isProduction && secretLength > 0 && secretLength < MIN_RECOMMENDED_JWT_SECRET_LENGTH && !isPlaceholderSecret(env.JWT_SECRET)) {
    warnings.push(
      `GUVENLIK: uretimde JWT_SECRET en az ${MIN_RECOMMENDED_JWT_SECRET_LENGTH} karakter olmali. Sunucu (kapi erisimi kesilmesin diye) ` +
        'ACILDI; pv zorunlulugu sahte token uretimini zorlastirir ama sir dondurulmeli: yeni >=64 karakterlik rastgele sir JWT_SECRET\'a, ' +
        'eskisi JWT_SECRET_PREVIOUS\'a, bitis ani (ISO, en fazla 30-90 gun) JWT_SECRET_PREVIOUS_UNTIL\'e yazilir.',
    );
  }

  const previous = resolvePreviousJwtSecret(env);
  const previousMessages = {
    placeholder: 'JWT_SECRET_PREVIOUS yer tutucu ya da 16 karakterden kisa; YOK SAYILIYOR.',
    same_as_current: 'JWT_SECRET_PREVIOUS, JWT_SECRET ile ayni; YOK SAYILIYOR (gereksiz, kaldirin).',
    missing_until: 'JWT_SECRET_PREVIOUS tanimli ama JWT_SECRET_PREVIOUS_UNTIL yok; eski sir YOK SAYILIYOR (suresiz kabul edilmez).',
    invalid_until: 'JWT_SECRET_PREVIOUS_UNTIL gecersiz tarih (ornek: 2026-11-30T00:00:00+03:00); eski sir YOK SAYILIYOR.',
    expired: 'JWT_SECRET_PREVIOUS_UNTIL gecmiste; eski sir artik kabul edilmiyor. JWT_SECRET_PREVIOUS ve _UNTIL satirlarini kaldirin.',
  };
  if (previousMessages[previous.status]) {
    warnings.push(previousMessages[previous.status]);
  } else if (previous.status === 'active' && previous.untilMs - Date.now() > MAX_PREVIOUS_SECRET_WINDOW_MS) {
    warnings.push('JWT_SECRET_PREVIOUS_UNTIL 90 gunden ileride; gecis penceresini kisa tutun (eski sirla imzali tokenlar o zamana dek gecerli).');
  }

  const expiresSeconds = parseExpiresInSeconds(env.JWT_EXPIRES_IN);
  if (expiresSeconds !== null && expiresSeconds > MAX_JWT_EXPIRES_SECONDS) {
    warnings.push(
      `JWT_EXPIRES_IN ust siniri asiyor; tokenlar ${MAX_JWT_EXPIRES_SECONDS / 86400} gune kirpilarak uretiliyor. Oneri: JWT_EXPIRES_IN=30d.`,
    );
  } else if (expiresSeconds !== null && expiresSeconds > DEFAULT_JWT_EXPIRES_SECONDS) {
    warnings.push('JWT_EXPIRES_IN 30 gunden uzun; oneri: JWT_EXPIRES_IN=30d (kayip cihazdaki oturum daha kisa surede duser).');
  } else if (expiresSeconds === 0) {
    warnings.push('JWT_EXPIRES_IN=0 gecersiz; varsayilan 30 gun kullaniliyor.');
  }

  const requirePvRaw = String(env.JWT_REQUIRE_PV ?? '').trim().toLowerCase();
  if (requirePvRaw && !PV_ENABLED_VALUES.includes(requirePvRaw) && !PV_DISABLED_VALUES.includes(requirePvRaw)) {
    warnings.push('JWT_REQUIRE_PV gecersiz (1/0 beklenir); varsayilan kullaniliyor (pv ZORUNLU).');
  } else if (PV_DISABLED_VALUES.includes(requirePvRaw)) {
    warnings.push(
      'GUVENLIK: JWT_REQUIRE_PV=0: pv\'siz (parola surumsuz) tokenlar kabul ediliyor; sir zayif/sizmissa sahte token uretilebilir. ' +
        'Yalniz gecici bir uyumluluk icin kullanin ve kaldirin.',
    );
  }
  return warnings;
}

/**
 * Baslangic dogrulamasi. { errors: [...], warnings: [...] } doner.
 * errors bos degilse sunucu baslatilmamalidir; warnings yalnizca loglanir.
 */
export function validateEnv(env = process.env) {
  const errors = [];
  const warnings = [];

  const jwtCheck = evaluateJwtSecret(env.JWT_SECRET);
  if (!jwtCheck.ok) {
    errors.push(jwtCheck.message);
  } else if (jwtCheck.warning) {
    warnings.push(jwtCheck.warning);
  }

  if (isSet(env, 'JWT_EXPIRES_IN') && !isValidExpiresIn(env.JWT_EXPIRES_IN)) {
    warnings.push('JWT_EXPIRES_IN gecersiz bicimde (ornek: 30d, 12h); varsayilan 30 gun kullaniliyor.');
  }
  warnings.push(...jwtHardeningWarnings(env, String(env.NODE_ENV || '').trim() === 'production'));
  warnings.push(...resolveTrustProxy(env).warnings);
  if (String(env.NODE_ENV || '').trim() === 'production' && !isSet(env, 'LISTEN_HOST')) {
    warnings.push('LISTEN_HOST tanimli degil: API tum arayuzlerde dinliyor; nginx ayni makinedeyse LISTEN_HOST=127.0.0.1 onerilir.');
  }

  if (env.PORT !== undefined && String(env.PORT).trim() !== '') {
    const port = Number(env.PORT);
    if (!Number.isInteger(port) || port < 1 || port > 65535) {
      warnings.push('PORT gecersiz; varsayilan 8080 kullanilacak.');
    }
  }

  const missingDb = ['DB_HOST', 'DB_NAME', 'DB_USER', 'DB_PASSWORD'].filter((name) => !isSet(env, name));
  if (missingDb.length > 0) {
    warnings.push(`Veritabani ayarlari eksik: ${missingDb.join(', ')}.`);
  }

  const missingMqtt = ['MQTT_HOST', 'MQTT_USER', 'MQTT_PASSWORD'].filter((name) => !isSet(env, name));
  if (missingMqtt.length > 0) {
    warnings.push(`MQTT ayarlari eksik: ${missingMqtt.join(', ')}; cihaz komutlari calismayabilir.`);
  }

  const missingSmtp = ['SMTP_HOST', 'SMTP_USER', 'SMTP_PASSWORD'].filter((name) => !isSet(env, name));
  if (missingSmtp.length > 0) {
    warnings.push(`SMTP ayarlari eksik: ${missingSmtp.join(', ')}; e-posta gonderilemez.`);
  }

  // Duyuru e-postası: adres özetleri (bastırma listesi, adres başına sınır) ve abonelikten çık imzası bu sırdan türetilir.
  const isProduction = String(env.NODE_ENV || '').trim() === 'production';
  if (isSet(env, 'ANNOUNCEMENT_EMAIL_SECRET')) {
    const own = String(env.ANNOUNCEMENT_EMAIL_SECRET).trim();
    if (isPlaceholderSecret(own) || own.length < 16) {
      warnings.push(
        `ANNOUNCEMENT_EMAIL_SECRET yer tutucu ya da zayif bir deger (${own.length} karakter; en az 16 onerilir). ` +
          `8 karakterden kisaysa kullanilmaz ve JWT_SECRET'tan turetilir (duyuru yayini bozulmaz). ${ANNOUNCEMENT_ROTATION_NOTE}`,
      );
    }
  } else if (isProduction) {
    warnings.push(
      'ANNOUNCEMENT_EMAIL_SECRET tanimli degil: duyuru e-postasi adres ozetleri ve abonelikten cik imzasi JWT_SECRET\'tan turetiliyor. ' +
        'JWT_SECRET dondurulursa abonelikten cikma listesi ve eski baglantilar gecersiz olur; ozel bir ANNOUNCEMENT_EMAIL_SECRET tanimlayin ' +
        `(dondururken eskisini ANNOUNCEMENT_EMAIL_SECRET_PREVIOUS'a yazin). ${ANNOUNCEMENT_ROTATION_NOTE}`,
    );
  }
  if (isSet(env, 'ANNOUNCEMENT_EMAIL_SECRET_PREVIOUS')) {
    const previous = String(env.ANNOUNCEMENT_EMAIL_SECRET_PREVIOUS).split(',').map((entry) => entry.trim());
    const unusable = previous.filter((entry) => entry.length < 8).length;
    if (unusable > 0) {
      warnings.push(
        `ANNOUNCEMENT_EMAIL_SECRET_PREVIOUS icinde kullanilamayan ${unusable} girdi var (bos ya da 8 karakterden kisa); yok sayilir. ${ANNOUNCEMENT_ROTATION_NOTE}`,
      );
    }
  }

  // Duyuru gelen kutusu saklama penceresi (announcement_common.js inboxRetentionDays ile ayni kural): gecersiz deger SINIRSIZ sayilir.
  if (isSet(env, 'ANNOUNCEMENT_INBOX_RETENTION_DAYS')) {
    const retention = String(env.ANNOUNCEMENT_INBOX_RETENTION_DAYS).trim();
    if (!/^\d+$/.test(retention)) {
      warnings.push('ANNOUNCEMENT_INBOX_RETENTION_DAYS gecersiz (0 ya da pozitif tam sayi olmali); duyuru gelen kutusu SINIRSIZ gosterilir (eski duyurular kalir).');
    } else if (Number(retention) > 3650) {
      warnings.push('ANNOUNCEMENT_INBOX_RETENTION_DAYS 3650 gunden buyuk; 3650 olarak uygulanir.');
    }
  }

  if (!isSet(env, 'COMPANY_API_KEY')) {
    warnings.push('COMPANY_API_KEY tanimli degil; /api/company/* yalnizca super_user JWT ile calisir.');
  } else if (String(env.COMPANY_API_KEY).trim().length < 24) {
    warnings.push('COMPANY_API_KEY 24 karakterden kisa; daha uzun rastgele bir anahtar onerilir.');
  }

  if (!isSet(env, 'CORS_ORIGINS') && !isSet(env, 'PUBLIC_APP_URL') && !isSet(env, 'PUBLIC_BASE_URL')) {
    warnings.push('CORS allowlist bos (CORS_ORIGINS/PUBLIC_APP_URL/PUBLIC_BASE_URL); tarayici tabanli cross-origin istekler reddedilir.');
  }

  if (String(env.NODE_ENV || '').trim() !== 'production') {
    warnings.push('NODE_ENV=production degil (Express gelistirme varsayilanlari aktif); oneri: NODE_ENV=production. Hata yanitlari ortamdan bagimsiz guvenlidir.');
  }

  // Telefon bildirimi (Faz 3b-B): hizmet hesabi dosyasi depo icinde / izinleri acik / okunamiyor -> UYARI (sunucu yine acilir; dosya icerigi okunmaz).
  warnings.push(...pushEnvWarnings(env));

  return { errors, warnings };
}

/**
 * Sunucunun açılışta başlatılıp başlatılmayacağı. SERVER_SKIP_START=1 YALNIZ testler içindir (uygulama ağa / veritabanına açılmadan içe
 * aktarılır). dotenv .env dosyasını da yüklediği için değişken yanlışlıkla .env'e yazılmış olabilir: NODE_ENV=production iken YOK SAYILIR
 * (sunucu normal başlar) ve çağıran `error` mesajını yüksek sesle (console.error) loglar.
 * @returns {{ skip: boolean, error: string | null }}
 */
export function resolveServerStart(env = process.env) {
  const requested = String(env.SERVER_SKIP_START ?? '').trim() === '1';
  if (!requested) {
    return { skip: false, error: null };
  }
  if (String(env.NODE_ENV ?? '').trim() === 'production') {
    return {
      skip: false,
      error: 'SERVER_SKIP_START=1 production ortaminda YOK SAYILDI (yalniz testler icindir; .env dosyasindan kaldirin). Sunucu normal baslatiliyor.',
    };
  }
  return { skip: true, error: null };
}
