// Duyuru e-postası güvenliği: adres özeti (tuzlu SHA-256, KANONİK adres üzerinden) ve "abonelikten çık" bağlantısının imzası.
//
//  - Adres düz metin olarak YALNIZ gönderilene kadar tutulur. Adres başına günlük sınır ve bastırma listesi adresin tuzlu özetiyle
//    (email_hash) çalışır; özet, sunucu sırrına bağlı olduğundan adres tahmin edilerek sözlükle çözülemez.
//  - KANONİK adres: küçük harf + kırpma; yerel kısımda `+etiket` atılır; gmail.com / googlemail.com için noktalar silinir ve alan adı
//    gmail.com olur. `a.li+haber@gmail.com` ile `ali@gmail.com` AYNI özeti verir (takma adla bastırma / günlük sınır dolanılamaz).
//    E-posta yine GERÇEK adrese gider; kanonik biçim yalnız özet ve imza için kullanılır. SQL tarafı (announcement_recipients.js
//    canonicalEmailSql) aynı kuralı uygular; ikisi birebir aynı olmalıdır.
//  - Tuz ve imza anahtarı ANNOUNCEMENT_EMAIL_SECRET'tan, yoksa (ya da 8 karakterden kısaysa) JWT_SECRET'tan TÜRETİLİR (iki ayrı etiketle; ham
//    sır hiçbir yere yazılmaz, loglanmaz). Kısa / geçersiz değer yayını BOZMAZ: JWT_SECRET'a düşülür ve bir kez uyarı loglanır.
//  - SIR DÖNÜŞÜMÜ: ANNOUNCEMENT_EMAIL_SECRET_PREVIOUS (virgülle ayrılmış eski sırlar) verilirse bastırma kontrolleri ve abonelik
//    belirteçleri eski sırlarla da denenir; YENİ özetler ve imzalar yalnız güncel sırla üretilir. JWT_SECRET döndürülürken (özel sır
//    tanımsızsa) eski JWT_SECRET değeri ANNOUNCEMENT_EMAIL_SECRET_PREVIOUS'a yazılmalıdır.
//  - SQL tarafı aynı özeti üretir: encode(sha256(convert_to(tuz || ':' || kanonik adres, 'UTF8')), 'hex') (bkz. announcement_recipients.js).

import crypto from 'node:crypto';

export const MIN_EMAIL_SECRET_LENGTH = 8;

const usable = (value) => typeof value === 'string' && value.length >= MIN_EMAIL_SECRET_LENGTH;

let warnedShortSecret = false;

/** Güncel sır: ANNOUNCEMENT_EMAIL_SECRET (geçerliyse), yoksa JWT_SECRET. İkisi de kullanılamazsa hata (yalnız e-posta yollarında çağrılır). */
function currentSecret(env = process.env) {
  const own = env.ANNOUNCEMENT_EMAIL_SECRET;
  if (usable(own)) {
    return own;
  }
  if (own !== undefined && String(own).trim() !== '' && !warnedShortSecret) {
    warnedShortSecret = true;
    // eslint-disable-next-line no-console
    console.warn(
      `[announcement-email] UYARI: ANNOUNCEMENT_EMAIL_SECRET ${MIN_EMAIL_SECRET_LENGTH} karakterden kisa; JWT_SECRET'tan turetiliyor (deger yazilmaz).`,
    );
  }
  if (usable(env.JWT_SECRET)) {
    return String(env.JWT_SECRET);
  }
  throw new Error('ANNOUNCEMENT_EMAIL_SECRET veya JWT_SECRET tanimli degil.');
}

/** Eski sırlar (ANNOUNCEMENT_EMAIL_SECRET_PREVIOUS, virgüllü): geçerli olanlar, tekrarsız, güncel sırdan farklı. */
function previousSecrets(env = process.env) {
  const current = currentSecret(env);
  const seen = new Set([current]);
  const out = [];
  for (const part of String(env.ANNOUNCEMENT_EMAIL_SECRET_PREVIOUS ?? '').split(',')) {
    const secret = part.trim();
    if (usable(secret) && !seen.has(secret)) {
      seen.add(secret);
      out.push(secret);
    }
  }
  return out;
}

const derive = (secret, label) => crypto.createHmac('sha256', secret).update(label).digest();
const saltOf = (secret) => derive(secret, 'announcement-email-hash-salt-v1').toString('hex');
const signingKeyOf = (secret) => derive(secret, 'announcement-unsubscribe-v1');

/** SQL'e parametre olarak verilen GÜNCEL tuz (hex). Sırdan türetilir; sırrın kendisi değildir. */
export function emailHashSalt() {
  return saltOf(currentSecret());
}

/** [güncel tuz, ...eski tuzlar]: bastırma kontrolleri bunların HEPSİYLE özet hesaplayıp arar. */
export function emailHashSalts() {
  return [saltOf(currentSecret()), ...previousSecrets().map(saltOf)];
}

export const normalizeAddress = (address) => String(address ?? '').trim().toLowerCase();

const GMAIL_DOMAINS = new Set(['gmail.com', 'googlemail.com']);

/**
 * Kanonik adres (özet ve imza için): küçük harf, `+etiket` atılır, gmail/googlemail için noktalar silinir ve alan adı gmail.com olur.
 * Yerel kısım etiketten / noktalardan sonra boş kalacaksa dokunulmaz (farklı adresler tek anahtara çökmesin). SQL ile birebir aynıdır.
 */
export function canonicalAddress(address) {
  const normalized = normalizeAddress(address);
  const at = normalized.indexOf('@');
  if (at <= 0 || at !== normalized.lastIndexOf('@') || at === normalized.length - 1) {
    return normalized;
  }
  let local = normalized.slice(0, at);
  let domain = normalized.slice(at + 1);
  const plus = local.indexOf('+');
  if (plus > 0) {
    local = local.slice(0, plus);
  }
  if (GMAIL_DOMAINS.has(domain)) {
    const undotted = local.replaceAll('.', '');
    if (undotted !== '') {
      local = undotted;
    }
    domain = 'gmail.com';
  }
  return `${local}@${domain}`;
}

const HASH_PATTERN = /^[0-9a-f]{64}$/;
export const isEmailHash = (value) => typeof value === 'string' && HASH_PATTERN.test(value);

const hashWithSalt = (salt, address) => crypto.createHash('sha256').update(`${salt}:${canonicalAddress(address)}`, 'utf8').digest('hex');

/** Adresin tuzlu özeti (GÜNCEL tuz; kanonik adres üzerinden; SQL ifadesiyle birebir aynı). */
export function hashEmail(address) {
  return hashWithSalt(emailHashSalt(), address);
}

/** Adresin güncel ve eski tuzlarla özetleri (kendi adresi için bastırmayı kaldırırken eski kayıtlar da silinsin). */
export function hashEmailAll(address) {
  return emailHashSalts().map((salt) => hashWithSalt(salt, address));
}

const signature = (key, emailHash) => crypto.createHmac('sha256', key).update(`unsub:${emailHash}`).digest('base64url');

/** Abonelikten çık belirteci: "<adres özeti>.<HMAC>". Adrese bağlıdır, süresizdir; bağlantıda düz adres yoktur. İmza GÜNCEL sırla atılır. */
export function signUnsubscribeToken(emailHash) {
  if (!isEmailHash(emailHash)) {
    throw new Error('gecersiz adres ozeti');
  }
  return `${emailHash}.${signature(signingKeyOf(currentSecret()), emailHash)}`;
}

/**
 * Belirteci doğrular (sabit süreli karşılaştırma; güncel sır, sonra eski sırlar denenir); geçerliyse adres özetini, değilse null döner.
 * Eski sırla atılmış (sır dönüşümünden önce gönderilmiş) bağlantılar ANNOUNCEMENT_EMAIL_SECRET_PREVIOUS'ta oldukları sürece geçerlidir.
 */
export function verifyUnsubscribeToken(token) {
  if (typeof token !== 'string' || token.length > 200) {
    return null;
  }
  const [emailHash, sig, extra] = token.split('.');
  if (extra !== undefined || !isEmailHash(emailHash) || typeof sig !== 'string' || sig === '') {
    return null;
  }
  const given = Buffer.from(sig);
  const keys = [signingKeyOf(currentSecret()), ...previousSecrets().map(signingKeyOf)];
  let valid = false;
  for (const key of keys) {
    const expected = Buffer.from(signature(key, emailHash));
    if (expected.length === given.length && crypto.timingSafeEqual(expected, given)) {
      valid = true;
    }
  }
  return valid ? emailHash : null;
}

/** E-postadaki bağlantı için kök adres (parola sıfırlama bağlantısıyla aynı sıra). */
export function publicLinkBase(env = process.env) {
  return String(env.PUBLIC_APP_URL || env.PUBLIC_BASE_URL || 'https://api.gudeteknoloji.com.tr').replace(/\/+$/, '');
}

export const UNSUBSCRIBE_PATH = '/public/announcement-unsubscribe';

export function unsubscribeUrl(emailHash, env = process.env) {
  return `${publicLinkBase(env)}${UNSUBSCRIBE_PATH}?t=${encodeURIComponent(signUnsubscribeToken(emailHash))}`;
}

/** Test yardımcısı: "kısa sır" uyarısının bir kez-log bayrağını sıfırlar. */
export function resetSecretWarnings() {
  warnedShortSecret = false;
}
