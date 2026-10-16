// Parola ilkesi (docs/PLATFORM_SATISA_HAZIRLIK.md §1.7) — YENİ / DEĞİŞEN / SIFIRLANAN parolalar için.
//
// - En az 8, en çok 128 karakter (Unicode kod noktası; emoji tek karakter) ve en çok 72 bayt (UTF-8; bcrypt sınırı).
//   İstemci (lib/ui/helpers/password_policy.dart) aynı birimleri kullanır.
// - E-posta, e-postanın @ öncesi kısmı, ad / soyad / ad soyad ya da kullanıcı adı ile AYNI olamaz (büyük/küçük harf,
//   Türkçe karakter ve boşluk farkı yok sayılır).
// - Küçük, yerleşik bir yaygın parola listesinde (TR + EN) ya da basit örüntülerde (tek karakter tekrarı, klavye/alfabe
//   dizisi, kısa parçanın tekrarı, doğum tarihi biçimli 8 rakam, "yaygın sözcük + kısa rakam/im eki") olamaz.
// İhlal: 400 { error, code: 'WEAK_PASSWORD', reason }. Parolanın kendisi hiçbir iletiye / günlüğe yazılmaz.
// GİRİŞTE UYGULANMAZ: mevcut kullanıcıların eski parolaları girişte çalışmaya devam eder.
//
// Bayt sınırı (bcrypt): bcrypt girdinin yalnızca ilk 72 BAYTINI (UTF-8) kullanır; daha uzun parolanın sonu özete girmez
// ('ş'.repeat(100) ile özetlenen parola 'ş'.repeat(36) ile de eşleşir). Bu yüzden yeni parola UTF-8'de en çok 72 bayt
// olabilir (aşarsa reason 'too_long'). Türkçe harfler (ş, ğ, ı, ö, ü, ç, İ) 2 bayttır. Girişte uygulanmaz.

export const PASSWORD_MIN_LENGTH = 8;
export const PASSWORD_MAX_LENGTH = 128;
export const PASSWORD_MAX_BYTES = 72;
export const WEAK_PASSWORD_CODE = 'WEAK_PASSWORD';

const MESSAGES = Object.freeze({
  required: 'Şifre zorunludur.',
  too_short: `Şifre çok kısa: en az ${PASSWORD_MIN_LENGTH} karakter olmalı. Birkaç sözcüğü art arda yazabilirsiniz.`,
  too_long:
    `Şifre çok uzun: en fazla ${PASSWORD_MAX_LENGTH} karakter ve ${PASSWORD_MAX_BYTES} bayt olabilir ` +
    '(Türkçe harfler 2 bayt sayılır; yaklaşık 36 Türkçe harf ya da 72 İngilizce harf). Daha kısa bir şifre seçin.',
  same_as_email: 'Şifre e-posta adresinizle aynı olamaz. Farklı bir şifre seçin.',
  same_as_name: 'Şifre adınızla ya da kullanıcı adınızla aynı olamaz. Farklı bir şifre seçin.',
  common: 'Bu şifre çok yaygın ve kolay tahmin edilir. Daha özgün bir şifre seçin.',
});

// Karşılaştırma katlaması: NFKC + küçük harf + Türkçe harfler ASCII karşılığına (ı/İ/I -> i, ş -> s, ğ -> g, ü -> u,
// ö -> o, ç -> c). Böylece "Fenerbahçe1907" ve "fenerbahce1907" aynı kabul edilir.
const TR_FOLD = new Map([
  ['ı', 'i'],
  ['ş', 's'],
  ['ğ', 'g'],
  ['ü', 'u'],
  ['ö', 'o'],
  ['ç', 'c'],
  ['â', 'a'],
  ['î', 'i'],
  ['û', 'u'],
]);

export function foldForComparison(value) {
  const text = String(value ?? '')
    .normalize('NFKC')
    .trim()
    .replace(/[İI]/g, 'i')
    .toLowerCase();
  let out = '';
  for (const ch of text) {
    out += TR_FOLD.get(ch) ?? ch;
  }
  // Birleşik nokta (U+0307) "i̇" ayrıştırmasından kalabilir.
  return out.replace(/̇/g, '');
}

function withoutSpaces(value) {
  return value.replace(/[\s._-]+/g, '');
}

// Yaygın parolalar (katlanmış biçim; ASCII). Uzunluğu 8'den kısa olanlar zaten uzunluk kuralına takılır, listede
// yalnızca 8+ karakterliler tutulur. Kaynak: yaygın sızıntı listelerinin üst sıraları + Türkiye'ye özgü örnekler
// (takımlar ve kuruluş yılları, şehirler ve plaka kodları, "sifre/parola" türevleri, sevgi ifadeleri, ürün adları).
const COMMON_PASSWORDS = new Set([
  // rakam
  '12345678', '123456789', '1234567890', '12345678910', '0123456789', '11111111', '00000000', '22222222',
  '12341234', '11223344', '12121212', '123123123', '123321123', '987654321', '87654321', '9876543210',
  '123654789', '147258369', '159753456', '741852963', '963852741', '147852369', '123456654321', '112233445566',
  '1234512345', '1122334455', '5555555555', '1231231234', '20202020', '19191919',
  // klavye / harf+rakam
  '1q2w3e4r', '1q2w3e4r5t', '1q2w3e4r5t6y', '1qaz2wsx', '1qaz2wsx3edc', 'q1w2e3r4', 'q1w2e3r4t5', 'qwerty12',
  'qwerty123', 'qwerty1234', 'qwertyuiop', 'qwertyui', 'qwe12345', 'qweasdzxc', 'qazwsxedc', 'zaq12wsx',
  'asdfghjk', 'asdfghjkl', 'asdf1234', 'zxcvbnm1', 'zxcvbnm123', '1234qwer', 'abcd1234', 'abc12345',
  'abcd12345', 'abcdefgh', 'a1234567', 'a12345678', '1234567a', '123456789a', '123456789q', 'aa123456',
  'aa12345678', 'a1b2c3d4', '1a2b3c4d', 'aaaaaaaa', 'qqqqqqqq',
  // İngilizce yaygın
  'password', 'password1', 'password12', 'password123', 'password1234', 'passw0rd', 'p@ssw0rd', 'p@ssword',
  'p@55w0rd', 'iloveyou', 'iloveyou1', 'admin123', 'admin1234', 'administrator', 'welcome1', 'welcome123',
  'letmein1', 'letmein123', 'changeme', 'changeme1', 'trustno1', 'sunshine', 'princess', 'football',
  'baseball', 'superman', 'starwars', 'whatever', 'computer', 'internet', 'michelle', 'jennifer',
  'liverpool', 'chelsea1', 'arsenal1', 'barcelona', 'realmadrid', 'pokemon1', 'minecraft', 'samsung1',
  'iphone12', 'google123', 'facebook', 'instagram', 'whatsapp', 'helloworld', 'hello123', 'lovelove',
  'freedom1', 'shadow12', 'michael1', 'charlie1', 'jordan23', 'monkey12', 'dragon12', 'master12',
  'default1', 'guest123', 'user1234', 'root1234', 'test1234', 'test12345', 'qwerty11',
  // Türkçe: şifre / parola türevleri
  'sifre123', 'sifre1234', 'sifre12345', 'sifresifre', 'sifrem123', 'sifremyok', 'parola123', 'parola1234',
  'parola12345', 'parolam123', 'yenisifre1', 'gizlisifre', 'deneme123', 'deneme1234', 'denemeler',
  'kullanici', 'kullanici1', 'yonetici', 'yonetici1', 'yonetici123', 'merhaba123', 'selamlar',
  // Türkçe: sevgi / din / milli
  'seniseviyorum', 'seviyorum', 'askim123', 'askimsin', 'canimsin', 'hayatim1', 'birtanem', 'kalbimsin',
  'bismillah', 'elhamdulillah', 'allahuekber', 'ataturk1881', 'ataturk1938', 'mustafakemal', 'turkiye123',
  'turkiye1923', 'cumhuriyet', 'cumhuriyet1923',
  // Türkçe: takımlar
  'galatasaray', 'galatasaray1905', 'cimbom1905', 'aslan1905', 'fenerbahce', 'fenerbahce1907', 'kanarya1907',
  'besiktas1903', 'kartal1903', 'carsi1903', 'trabzonspor', 'trabzonspor61', 'trabzonspor1967', 'bursaspor',
  'goztepe1925',
  // Türkçe: şehirler (+ plaka kodu)
  'istanbul', 'istanbul34', 'istanbul1453', 'ankara06', 'ankara123', 'izmir035', 'izmir3535', 'antalya07',
  'bursa016', 'trabzon61', 'diyarbakir', 'diyarbakir21', 'konya042', 'adana001',
  // Bu ürün / alan
  'apartman1', 'apartman123', 'site1234', 'site12345', 'daire123', 'daire1234', 'kapi1234', 'kapi12345',
  'kapikontrol', 'smartkeypass', 'ahbu1234', 'gudeteknoloji', 'yonetim123', 'aidat123',
]);

// Yaygın sözcükler: tek başına ya da yalnız rakam/im ekiyle ("sifre2024", "Password1!") reddedilir.
// Not: "abcdef" bilinçli olarak YOK (istemciden farklı): yalnız abcdef + 2 rakam gibi örnekler sunucuda kabul edilir.
const COMMON_BASES = new Set([
  'password', 'passw0rd', 'p@ssw0rd', 'qwerty', 'qwertyui', 'qwertyuiop', 'admin', 'administrator', 'welcome',
  'letmein', 'iloveyou', 'monkey', 'dragon', 'master', 'login', 'sunshine', 'football', 'abc', 'abcd',
  'abcdefgh', 'asdf', 'asdfgh', 'zxcvbnm', 'test', 'deneme', 'sifre', 'sifrem', 'parola', 'parolam', 'gizli',
  'merhaba', 'selam', 'askim', 'canim', 'hayatim', 'seniseviyorum', 'galatasaray', 'cimbom', 'fenerbahce',
  'besiktas', 'trabzon', 'trabzonspor', 'istanbul', 'ankara', 'izmir', 'turkiye', 'ataturk', 'kapi', 'site',
  'daire', 'apartman', 'yonetici', 'kullanici', 'ahbu', 'smartkeypass', 'gudeteknoloji',
]);

// Önde/sonda yalnız rakam ve im ("2024", "!", "123!") — en çok 6 karakter (istemciyle aynı).
const TRAILING_FILLER = /[0-9!._\-*@#$%+?,;:]{1,6}$/;
const LEADING_FILLER = /^[0-9!._\-*@#$%+?,;:]{1,4}/;
const TRAILING_SYMBOLS = /[!._\-*@#$%+?,;:]+$/;

const SEQUENCE_SOURCES = [
  '01234567890',
  'abcdefghijklmnopqrstuvwxyz',
  'qwertyuiopasdfghjklzxcvbnm',
  'qwertyuiopgusdfghjklsizxcvbnmoc', // Türkçe Q klavye (katlanmış)
  'qazwsxedcrfvtgbyhnujmikolp',
  '1qaz2wsx3edc4rfv5tgb6yhn7ujm8ik9ol0p',
  '1q2w3e4r5t6y7u8i9o0p',
];

function isSequence(folded) {
  for (const source of SEQUENCE_SOURCES) {
    if (source.includes(folded)) {
      return true;
    }
    const reversed = [...source].reverse().join('');
    if (reversed.includes(folded)) {
      return true;
    }
  }
  return false;
}

// "abcabcabc", "12121212", "20242024": 1-4 karakterlik parçanın tekrarı.
function isRepeatedChunk(folded) {
  const chars = [...folded];
  for (let size = 1; size <= 4; size += 1) {
    if (chars.length % size !== 0 || chars.length / size < 2) {
      continue;
    }
    const chunk = chars.slice(0, size).join('');
    if (chunk.repeat(chars.length / size) === folded) {
      return true;
    }
  }
  return false;
}

// 8 rakamlı doğum tarihi biçimleri: GGAAYYYY / YYYYAAGG (1900-2099).
function isDateLike(folded) {
  if (!/^\d{8}$/.test(folded)) {
    return false;
  }
  const validDay = (d) => d >= 1 && d <= 31;
  const validMonth = (m) => m >= 1 && m <= 12;
  const validYear = (y) => y >= 1900 && y <= 2099;
  const ddmmyyyy = [Number(folded.slice(0, 2)), Number(folded.slice(2, 4)), Number(folded.slice(4))];
  if (validDay(ddmmyyyy[0]) && validMonth(ddmmyyyy[1]) && validYear(ddmmyyyy[2])) {
    return true;
  }
  const yyyymmdd = [Number(folded.slice(0, 4)), Number(folded.slice(4, 6)), Number(folded.slice(6))];
  return validYear(yyyymmdd[0]) && validMonth(yyyymmdd[1]) && validDay(yyyymmdd[2]);
}

function isTrivialPattern(candidate) {
  if (candidate.length < 4) {
    return false;
  }
  return new Set(candidate).size <= 1 || isRepeatedChunk(candidate) || isSequence(candidate) || isDateLike(candidate);
}

/** Yaygın / tahmin edilmesi kolay parola mı? (girdi ham parola; katlama burada yapılır) */
export function isCommonPassword(password) {
  const folded = foldForComparison(password);
  if (!folded) {
    return false;
  }
  // Ayırıcısız biçim ("sifre-123" -> "sifre123") ve sondaki yalnız-im eki atılmış biçim ("12345678!" -> "12345678").
  const compact = withoutSpaces(folded);
  const noTrailingSymbols = compact.replace(TRAILING_SYMBOLS, '');
  for (const candidate of new Set([folded, compact, noTrailingSymbols])) {
    if (candidate && (COMMON_PASSWORDS.has(candidate) || COMMON_BASES.has(candidate) || isTrivialPattern(candidate))) {
      return true;
    }
  }
  // "Yaygın sözcük + kısa rakam/im eki" ("Sifre2024!", "2024parola"): kök listedeyse ya da 7+ karakterlik bir diziyse
  // ("abcdefg1"). Not: 6 karakterlik dizi + ek ("abcdef12") sunucuda kabul edilir (istemci daha katı).
  const base = compact.replace(TRAILING_FILLER, '').replace(LEADING_FILLER, '');
  if (base && base !== compact) {
    if (COMMON_BASES.has(base) || COMMON_PASSWORDS.has(base)) {
      return true;
    }
    if (base.length >= 7 && (isSequence(base) || new Set(base).size <= 1)) {
      return true;
    }
  }
  return false;
}

function identityCandidates({ email, fullName, firstName, lastName, loginName, names } = {}) {
  const emails = [];
  const others = [];
  const mail = foldForComparison(email);
  if (mail) {
    emails.push(mail);
    const at = mail.indexOf('@');
    if (at > 0) {
      emails.push(mail.slice(0, at));
    }
  }
  const nameList = [fullName, firstName, lastName, loginName, ...(Array.isArray(names) ? names : [])];
  if (firstName && lastName) {
    nameList.push(`${firstName} ${lastName}`);
  }
  for (const raw of nameList) {
    const folded = foldForComparison(raw);
    if (folded) {
      others.push(folded);
    }
  }
  return { emails, others };
}

/**
 * Parolayı ilkeye göre değerlendirir. Parola zaten çağıranın sunucuya yazacağı biçimde (çoğunlukla `trim()`lenmiş)
 * verilmelidir.
 * @param {string} password
 * @param {{ email?: string, fullName?: string, firstName?: string, lastName?: string, loginName?: string, names?: string[] }} [context]
 * @returns {{ ok: true } | { ok: false, reason: string, message: string }}
 */
export function evaluatePassword(password, context = {}) {
  const value = typeof password === 'string' ? password : String(password ?? '');
  if (!value) {
    return { ok: false, reason: 'required', message: MESSAGES.required };
  }
  const length = [...value].length;
  if (length < PASSWORD_MIN_LENGTH) {
    return { ok: false, reason: 'too_short', message: MESSAGES.too_short };
  }
  if (length > PASSWORD_MAX_LENGTH || Buffer.byteLength(value, 'utf8') > PASSWORD_MAX_BYTES) {
    return { ok: false, reason: 'too_long', message: MESSAGES.too_long };
  }

  const folded = foldForComparison(value);
  const compact = withoutSpaces(folded);
  const { emails, others } = identityCandidates(context);
  if (emails.some((candidate) => candidate === folded || withoutSpaces(candidate) === compact)) {
    return { ok: false, reason: 'same_as_email', message: MESSAGES.same_as_email };
  }
  if (others.some((candidate) => candidate === folded || withoutSpaces(candidate) === compact)) {
    return { ok: false, reason: 'same_as_name', message: MESSAGES.same_as_name };
  }
  if (isCommonPassword(value)) {
    return { ok: false, reason: 'common', message: MESSAGES.common };
  }
  return { ok: true };
}

/**
 * Rota yardımcısı: ilke ihlalinde 400 WEAK_PASSWORD yanıtını yazar ve `true` döner; geçerliyse `false`.
 *   if (rejectWeakPassword(res, password, { email })) return;
 */
export function rejectWeakPassword(res, password, context = {}) {
  const verdict = evaluatePassword(password, context);
  if (verdict.ok) {
    return false;
  }
  res.status(400).json({ error: verdict.message, code: WEAK_PASSWORD_CODE, reason: verdict.reason });
  return true;
}

/** Servis katmanı için: ilke ihlalinde fırlatılacak tipli hata (statusCode 400, code WEAK_PASSWORD, expose). */
export function assertStrongPassword(password, context = {}) {
  const verdict = evaluatePassword(password, context);
  if (verdict.ok) {
    return;
  }
  const error = new Error(verdict.message);
  error.statusCode = 400;
  error.expose = true;
  error.code = WEAK_PASSWORD_CODE;
  error.reason = verdict.reason;
  throw error;
}

// Testler için: liste boyutları (içerik dışarı verilmez).
export const __policyStats = Object.freeze({
  commonPasswords: COMMON_PASSWORDS.size,
  commonBases: COMMON_BASES.size,
});
