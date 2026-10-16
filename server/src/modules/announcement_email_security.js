// Duyuru e-postası güvenliği: adres özeti (tuzlu SHA-256) ve "abonelikten çık" bağlantısının imzası.
//
//  - Adres düz metin olarak YALNIZ gönderilene kadar tutulur. Adres başına günlük sınır ve bastırma listesi adresin tuzlu özetiyle
//    (email_hash) çalışır; özet, sunucu sırrına bağlı olduğundan adres tahmin edilerek sözlükle çözülemez.
//  - Tuz ve imza anahtarı ANNOUNCEMENT_EMAIL_SECRET'tan, yoksa JWT_SECRET'tan TÜRETİLİR (iki ayrı etiketle; ham sır hiçbir yere yazılmaz,
//    loglanmaz). Sır değişirse eski özetler eşleşmez (bastırma listesi sıfırlanmış gibi olur): sırrı değiştirmeyin.
//  - SQL tarafı aynı özeti üretir: encode(sha256(convert_to(tuz || ':' || adres, 'UTF8')), 'hex') (bkz. announcement_recipients.js).

import crypto from 'node:crypto';

function baseSecret() {
  const secret = process.env.ANNOUNCEMENT_EMAIL_SECRET || process.env.JWT_SECRET;
  if (!secret || String(secret).length < 8) {
    throw new Error('ANNOUNCEMENT_EMAIL_SECRET veya JWT_SECRET tanimli degil.');
  }
  return String(secret);
}

const derive = (label) => crypto.createHmac('sha256', baseSecret()).update(label).digest();

/** SQL'e parametre olarak verilen tuz (hex). Sırdan türetilir; sırrın kendisi değildir. */
export function emailHashSalt() {
  return derive('announcement-email-hash-salt-v1').toString('hex');
}

export const normalizeAddress = (address) => String(address ?? '').trim().toLowerCase();

const HASH_PATTERN = /^[0-9a-f]{64}$/;
export const isEmailHash = (value) => typeof value === 'string' && HASH_PATTERN.test(value);

/** Adresin tuzlu özeti (küçük harfli adres üzerinden; SQL ifadesiyle birebir aynı). */
export function hashEmail(address) {
  return crypto.createHash('sha256').update(`${emailHashSalt()}:${normalizeAddress(address)}`, 'utf8').digest('hex');
}

const signature = (emailHash) => crypto.createHmac('sha256', derive('announcement-unsubscribe-v1')).update(`unsub:${emailHash}`).digest('base64url');

/** Abonelikten çık belirteci: "<adres özeti>.<HMAC>". Adrese bağlıdır, süresizdir; bağlantıda düz adres yoktur. */
export function signUnsubscribeToken(emailHash) {
  if (!isEmailHash(emailHash)) {
    throw new Error('gecersiz adres ozeti');
  }
  return `${emailHash}.${signature(emailHash)}`;
}

/** Belirteci doğrular (sabit süreli karşılaştırma); geçerliyse adres özetini, değilse null döner. */
export function verifyUnsubscribeToken(token) {
  if (typeof token !== 'string' || token.length > 200) {
    return null;
  }
  const [emailHash, sig, extra] = token.split('.');
  if (extra !== undefined || !isEmailHash(emailHash) || typeof sig !== 'string' || sig === '') {
    return null;
  }
  const expected = Buffer.from(signature(emailHash));
  const given = Buffer.from(sig);
  if (expected.length !== given.length || !crypto.timingSafeEqual(expected, given)) {
    return null;
  }
  return emailHash;
}

/** E-postadaki bağlantı için kök adres (parola sıfırlama bağlantısıyla aynı sıra). */
export function publicLinkBase(env = process.env) {
  return String(env.PUBLIC_APP_URL || env.PUBLIC_BASE_URL || 'https://api.gudeteknoloji.com.tr').replace(/\/+$/, '');
}

export const UNSUBSCRIBE_PATH = '/public/announcement-unsubscribe';

export function unsubscribeUrl(emailHash, env = process.env) {
  return `${publicLinkBase(env)}${UNSUBSCRIBE_PATH}?t=${encodeURIComponent(signUnsubscribeToken(emailHash))}`;
}
