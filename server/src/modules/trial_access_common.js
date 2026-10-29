// Deneme erişim kodu (P2-27, karar K10): ortak sabitler, kod üretimi / özeti ve DENEME OTURUMU ERİŞİM İLKESİ (saf; veritabanı yok).
//
// Model: sahip (süper kullanıcı) ya da DEMO sitenin yöneticisi tek kullanımlık bir kod üretir; aday giriş ekranında kodu girer ve
// 72 saatlik, YALNIZ demo siteye kilitli bir oturum alır. Oturum gerçek bir kullanıcı satırıdır (rol site_manager, e-posta
// `trial-<rastgele>@deneme.invalid`, parola özeti hiçbir parolayla eşleşmez) ve yalnız demo sitede yönetici bağı taşır.
//
// Bu dosya auth_middleware.js tarafından da içe aktarılır: db.js / hizmet katmanını İÇE AKTARMAZ (döngü olmasın).
import crypto from 'node:crypto';
import { TRIAL_EMAIL_DOMAIN } from '../utils/reserved_email.js';

export { TRIAL_EMAIL_DOMAIN };
export const TRIAL_SESSION_HOURS = 72;
export const TRIAL_SESSION_MS = TRIAL_SESSION_HOURS * 60 * 60 * 1000;
/** Üretilen kodun kullanılabileceği süre (gün): varsayılan / üst sınır. Oturum süresi (72 saat) kullanım anından başlar. */
export const TRIAL_CODE_DEFAULT_VALID_DAYS = 14;
export const TRIAL_CODE_MAX_VALID_DAYS = 60;
/** Aynı anda bekleyen (kullanılmamış, süresi dolmamış, iptal edilmemiş) kod üst sınırı: kullanıcı kodu (5 haneli) havuzunu korur. */
export const TRIAL_MAX_ACTIVE_CODES = 100;
/** Demo site tanımı: platform_settings anahtarı, değer { site_code }. */
export const DEMO_SITE_SETTING_KEY = 'trial_access.demo_site';

/** Kod alfabesi: 31 karakter (0, 1, I, L, O yok: yazarken karışmaz). 12 karakter = ~59 bit. */
export const TRIAL_CODE_ALPHABET = '23456789ABCDEFGHJKMNPQRSTUVWXYZ';
export const TRIAL_CODE_LENGTH = 12;
const MAX_RAW_CODE_LENGTH = 40;

/** Rastgele kod (biçimli: XXXX-XXXX-XXXX). crypto.randomInt: önyargısız. `randomInt` testte yerine konabilir. */
export function generateTrialCode(randomInt = crypto.randomInt) {
  let out = '';
  for (let i = 0; i < TRIAL_CODE_LENGTH; i += 1) {
    out += TRIAL_CODE_ALPHABET[randomInt(0, TRIAL_CODE_ALPHABET.length)];
  }
  return formatTrialCode(out);
}

/**
 * Bu e-posta bir deneme hesabına mı ait? Alan adı ayrılmıştır (kayıt / davet / yönetici oluşturma reddeder), yani yalnız sistem üretir.
 * Kod satırı silinmiş (ör. demo site silindi, CASCADE) ama hesap kalmışsa bile hesap "deneme" olarak tanınır ve oturumu biter.
 */
export function isTrialAccountEmail(email) {
  return String(email ?? '').trim().toLowerCase().endsWith(`@${TRIAL_EMAIL_DOMAIN}`);
}

/** "ABCDEFGHJKMN" -> "ABCD-EFGH-JKMN". */
export function formatTrialCode(normalized) {
  return String(normalized).match(/.{1,4}/g)?.join('-') ?? '';
}

/**
 * Girilen kodu kanonik biçime çevirir: büyük harf, boşluk / tire atılır. Uzunluk ya da alfabe uymuyorsa null
 * (veritabanına hiç gidilmez).
 */
export function normalizeTrialCode(raw) {
  if (typeof raw !== 'string' || raw.length === 0 || raw.length > MAX_RAW_CODE_LENGTH) {
    return null;
  }
  const text = raw.toUpperCase().replace(/[\s-]/g, '');
  if (text.length !== TRIAL_CODE_LENGTH) {
    return null;
  }
  for (const char of text) {
    if (!TRIAL_CODE_ALPHABET.includes(char)) {
      return null;
    }
  }
  return text;
}

/** Kodun son 4 karakteri: yönetici listesinde tanımak için (kodun tamamı ASLA saklanmaz). */
export function trialCodeHint(normalized) {
  return String(normalized).slice(-4);
}

/**
 * Kod özeti: HMAC-SHA256 (anahtar TRIAL_CODE_PEPPER, yoksa JWT_SECRET). Kod yüksek entropili rastgele olduğundan hızlı bir özet
 * yeterlidir; anahtar, veritabanı sızsa bile çevrimdışı denemeyi anlamsız kılar. JWT_SECRET değişirse bekleyen kodlar geçersiz
 * olur (güvenli hata: yeni kod üretilir).
 */
export function hashTrialCode(normalized, pepper = process.env.TRIAL_CODE_PEPPER || process.env.JWT_SECRET || '') {
  if (!pepper) {
    throw new Error('Deneme kodu özeti için TRIAL_CODE_PEPPER ya da JWT_SECRET tanımlı olmalı.');
  }
  return crypto.createHmac('sha256', String(pepper)).update(`trial-access-code:v1:${normalized}`).digest('hex');
}

// ---------------------------------------------------------------------------
// Deneme oturumu erişim ilkesi
// ---------------------------------------------------------------------------

export const TRIAL_MESSAGES = Object.freeze({
  expired: 'Deneme süreniz doldu. Devam etmek için bizimle iletişime geçin.',
  revoked: 'Deneme erişiminiz sonlandırıldı.',
  scope: 'Deneme hesabı yalnızca demo sitede çalışır; bu siteye erişemezsiniz.',
  action: 'Bu işlem deneme hesabında kullanılamaz.',
  path: 'İstek adresi deneme hesabında kabul edilmiyor.',
});

const ALLOW = Object.freeze({ ok: true });
const deny = (status, code, message) => Object.freeze({ ok: false, status, code, message });
const DENY_ACTION = deny(403, 'TRIAL_ACTION_DENIED', TRIAL_MESSAGES.action);
const DENY_SCOPE = deny(403, 'TRIAL_SCOPE_DENIED', TRIAL_MESSAGES.scope);
const DENY_PATH = deny(403, 'TRIAL_PATH_DENIED', TRIAL_MESSAGES.path);
const END_EXPIRED = deny(401, 'TRIAL_EXPIRED', TRIAL_MESSAGES.expired);
const END_REVOKED = deny(401, 'TRIAL_REVOKED', TRIAL_MESSAGES.revoked);

const SEGMENT_RE = /^[a-z0-9_.-]+$/;

/**
 * İstek yolunu küçük harfli parçalara ayırır. Sorgu / parça atılır; yüzde kodlaması, noktalı virgül, ters eğik çizgi, boşluk,
 * ASCII dışı karakter, boş parça ("//"), "." ve ".." içeren yol null döner (Express ile aynı yöne çözülmeyebilecek her biçim
 * deneme oturumunda REDDEDİLİR; arama büyük/küçük harf duyarsızdır çünkü Express yönlendirmesi de öyledir).
 */
export function splitTrialPath(rawPath) {
  const text = String(rawPath ?? '');
  const pathOnly = text.split('?')[0].split('#')[0];
  if (!pathOnly.startsWith('/')) {
    return null;
  }
  const trimmed = pathOnly.length > 1 ? pathOnly.replace(/\/+$/, '') : pathOnly;
  if (trimmed === '/') {
    return [];
  }
  const parts = trimmed.slice(1).split('/').map((part) => part.toLowerCase());
  for (const part of parts) {
    if (part === '' || part === '.' || part === '..' || !SEGMENT_RE.test(part)) {
      return null;
    }
  }
  return parts;
}

const isRead = (method) => method === 'GET' || method === 'HEAD';

// Demo sitenin İÇİNDE bile deneme oturumuna kapalı alt ağaçlar (/manager/sites/<demo>/<ilk parça>/...):
//  - site yaşam döngüsü ve üyelik: yönetici davet / çıkarma, katılım belirteci ve istekleri, güvenlik ilkesi, silme onayları
//  - donanım ve dış bağlantı: kapı / cihaz / kamera / plaka (kamera adresine sunucudan istek gider)
//  - platform düzeyi talepler ve kendini çoğaltma: modül talebi, deneme kodu uçları
// Bunlar HER yöntemde kapalıdır (okuma dahil).
const SITE_DENIED_FIRST = new Set([
  'managers',
  'invitations',
  'join-token',
  'join-requests',
  'security-policy',
  'approve-deletion',
  'reject-deletion',
  'doors',
  'assignable-devices',
  'cameras',
  'cctv',
  'plate-recognition',
  'plate-events',
  'module-requests',
  'trial-access',
]);

// YALNIZ YAZMA yöntemleri kapalı olanlar (okuma açık; ekranlar demo veriyle açılır):
//  - drive (Drive hesabı bağlama / yükleme), access-cards (kart verme), card-payments (ödeme sağlayıcısı ayarı), modules (açma / kapama)
//  - staff-roles: e-postaya göre PLATFORMDAKİ herhangi bir hesabı bulup siteye rol verir ("bu e-posta kayıtlı mı / kim" yanıtı verir):
//    başka sitelerin kullanıcılarını sorgulamak için kullanılamasın.
//  - quote-requests (113, P2-8): kimliksiz dış firmaya AÇIK internet bağlantısı üretir (firma girişiyle yazma yapılır); misafir geçişi /
//    katılım belirteci gibi dış etkilidir, deneme oturumu oluşturamaz / onaylayamaz. Listeleme (belirteç / özet asla dönmez) açık kalır.
const SITE_READ_ONLY_FIRST = new Set(['drive', 'access-cards', 'card-payments', 'modules', 'staff-roles', 'quote-requests', 'messaging']);

// /manager/sites/<demo>/people/<id>/<alt>: hesap açma, parola / PIN üretme, davet gönderme (dış e-posta / SMS ve kullanıcı kodu tüketir).
const PERSON_DENIED_SUB = new Set(['password-reset', 'account', 'reset-pin', 'invitation']);

// /manager/sites/<demo>/imports/<tür>/<alt>: hesap üreten kayıt ve kullanıcı adı önerisi (bcrypt + kullanıcı kodu tüketir; adlar / e-postalar
// platform genelinde sorgulanır). imports/login-names/* da kapalı. preview / spec ve exports/* açık kalır.
const IMPORT_DENIED_SUB = new Set(['commit', 'accounts']);

function decideSiteSubtree(method, segs) {
  // segs: ['manager','sites',<kod>,<d>, ...rest]
  const first = segs[3];
  if (SITE_DENIED_FIRST.has(first)) {
    return DENY_ACTION;
  }
  if (SITE_READ_ONLY_FIRST.has(first) && !isRead(method)) {
    return DENY_ACTION;
  }
  if (first === 'people') {
    if (segs[4] === 'bulk-actions') {
      return DENY_ACTION; // toplu davet / şifre sıfırlama e-postası
    }
    if (PERSON_DENIED_SUB.has(segs[5])) {
      return DENY_ACTION;
    }
  }
  if (first === 'finance' && segs[4] === 'reminders' && segs[5] === 'send') {
    return DENY_ACTION; // borçlulara dış e-posta / SMS
  }
  if (first === 'imports' && (segs[4] === 'login-names' || IMPORT_DENIED_SUB.has(segs[5]))) {
    return DENY_ACTION; // login-names/check: platform genelinde "bu kullanıcı adı var mı" sorusu
  }
  return ALLOW;
}

// Oturum açan herkesin sakin tarafında kullandığı /app/* uçları kendi üyelikleriyle sınırlıdır (deneme hesabının tek bağı demo
// site). Yine de kapı komutu, misafir geçiş belirteci ve davet kabulü deneme oturumuna KAPALIDIR.
function decideApp(method, segs) {
  if (segs[1] === 'doors' && !isRead(method)) {
    return DENY_ACTION;
  }
  if (segs[1] === 'guest-passes' && !isRead(method)) {
    return DENY_ACTION;
  }
  if (segs[1] === 'invitations' && !isRead(method)) {
    return DENY_ACTION;
  }
  return ALLOW;
}

// Sakin / kimlik tarafındaki salt-okunur kendi-kapsamlı uçlar (/membership/*): yazma uçları (site kurma, cihaz sahiplenme, katılım,
// site başvurusu) kapalı. Panel açılışında istemcinin yaptığı okumalar çalışsın diye bunlar açık.
const MEMBERSHIP_READS = new Set(['my-apartments', 'my-devices', 'my-join-requests']);

/**
 * Deneme oturumunun bir isteği yapıp yapamayacağına karar verir (VARSAYILAN: RED).
 *
 * @param {object} input
 * @param {{ siteCode: number|string|null, expiresAt: Date|string|number|null, revokedAt?: Date|string|number|null }} input.trial
 * @param {number|string|null} input.demoSiteCode  platform_settings'teki GÜNCEL demo site (yoksa / değiştiyse oturum biter)
 * @param {number} [input.now]  ms
 * @param {string} input.method
 * @param {string} input.path   req.originalUrl
 * @returns {{ ok: true } | { ok: false, status: number, code: string, message: string }}
 */
export function evaluateTrialRequest({ trial, demoSiteCode, now = Date.now(), method, path }) {
  const expiresMs = trial?.expiresAt == null ? Number.NaN : new Date(trial.expiresAt).getTime();
  if (trial?.revokedAt) {
    return END_REVOKED;
  }
  if (!Number.isFinite(expiresMs) || expiresMs <= now) {
    return END_EXPIRED;
  }
  const trialSite = Number(trial.siteCode);
  const demoSite = Number(demoSiteCode);
  if (!Number.isSafeInteger(trialSite) || trialSite <= 0 || !Number.isSafeInteger(demoSite) || demoSite !== trialSite) {
    return END_REVOKED;
  }

  const verb = String(method ?? '').toUpperCase();
  const segs = splitTrialPath(path);
  if (segs === null) {
    return DENY_PATH;
  }
  const site = String(trialSite);
  const [a, b, c] = segs;

  if (a === 'me') {
    if (segs.length === 1) {
      return verb === 'GET' ? ALLOW : DENY_ACTION; // profil / parola / e-posta değişmez
    }
    if (segs.length === 2 && b === 'consents') {
      return verb === 'GET' || verb === 'POST' ? ALLOW : DENY_ACTION;
    }
    return DENY_ACTION; // hesap silme, veri dışa aktarma
  }

  if (a === 'app') {
    return decideApp(verb, segs);
  }

  if (a === 'manager') {
    if (b === 'sites') {
      if (segs.length === 2) {
        return isRead(verb) ? ALLOW : DENY_ACTION; // yeni site açılmaz
      }
      if (c !== site) {
        return DENY_SCOPE;
      }
      if (segs.length === 3) {
        return isRead(verb) ? ALLOW : DENY_ACTION; // site düzenleme / silme yok
      }
      return decideSiteSubtree(verb, segs);
    }
    if ((b === 'devices' || b === 'door-logs') && segs.length === 2) {
      return isRead(verb) ? ALLOW : DENY_ACTION; // yönetilen sitelerle sınırlı liste (yalnız demo site)
    }
    return DENY_ACTION; // /manager/{apartments,doors,devices/*,join-requests}: kaynak kimliğiyle çalışan eski uçlar
  }

  if (a === 'sites') {
    return b === site ? ALLOW : DENY_SCOPE; // sayaç saha uçları
  }

  if (a === 'membership') {
    if (isRead(verb) && segs.length === 2 && MEMBERSHIP_READS.has(b)) {
      return ALLOW;
    }
    if (isRead(verb) && b === 'site-applications' && c === 'mine' && segs.length === 3) {
      return ALLOW;
    }
    if (isRead(verb) && b === 'sites' && segs[3] === 'residents-tree' && segs.length === 4) {
      return c === site ? ALLOW : DENY_SCOPE;
    }
    return DENY_ACTION;
  }

  if (a === 'brand-theme' && b === 'mine' && segs.length === 2 && isRead(verb)) {
    return ALLOW;
  }

  // /admin/*, /companies/*, /brand-themes/*, /device/*, /auth/* ve tanınmayan her yol: kapalı.
  return DENY_ACTION;
}
