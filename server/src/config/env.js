// Ortam degiskenleri dogrulamasi (sirlari ASLA loglamaz; yalnizca uzunluk/ad bilgisi verir).

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
        'Planli bir bakim penceresinde secret degistirilmeli (mevcut oturumlar gecersiz olur).',
    };
  }
  return { ok: true };
}

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
    warnings.push('JWT_EXPIRES_IN gecersiz bicimde (ornek: 30d, 12h); giris tokeni uretimi basarisiz olabilir.');
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

  return { errors, warnings };
}
