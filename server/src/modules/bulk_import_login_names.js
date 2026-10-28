// Toplu yükleme: kullanıcı adı (giriş adı) ataması.
//
// Şablonda "Kullanıcı Adı" sütunu YOKTUR: yönetici Türkiye genelindeki sistemde hangi adların alındığını bilemez (ve BİLMEMELİDİR: başka sitelerin hesap adlarını
// sayamaz). Sistem her yeni hesap için Ad Soyad'dan bir ad üretir; ad BU SİTENİN yöneticisinin görebildiği bir hesapta (bulk_import_scope.js) ya da aynı yüklemedeki
// başka bir satırda alınmışsa `_2`, `_3` ... varyasyonları denenir. Yönetici önizleme tablosunda adı değiştirebilir (`giris_adi` hücresi); değişiklik ancak
// biçim + site içi kullanılabilirlik denetimini geçerse kabul edilir.
//
// İKİ KAPSAM (güvenlik denetimi 2026-10-28, authz-modules-1: «her site yöneticisi sistemdeki tüm kullanıcı adlarını sayabiliyordu»):
//   - ÖNİZLEME / ÖNERİ / TEK AD DENETİMİ (takenLoginNames, resolveLoginNames, suggestLoginName, checkLoginName): SİTE kapsamı. Başka sitedeki ad «boşta» görünür;
//     kapsam dışı ad ile hiç olmayan ad AYNI yanıtı verir (var/yok bilgisi sızmaz). Aynı sitedeki gerçek çakışma doğru raporlanır.
//   - YAZIM (claimLoginName): SİSTEM kapsamı. `users` tablosunda LOWER(login_name) sistem genelinde tekildir (giriş adı site bilmez; her site, her şehir) ve kopya
//     ASLA yazılmaz: önizlemede gösterilen ad başka sitede alınmışsa sıradaki boş ad verilir, fark yalnız onay sonucunda (`requested_login_name`) bildirilir.
//
// Bu modül hem önizleme/öneri (toplu çözümleme) hem yazım (tek ad alma) hem tek ad denetimi için AYNI üretim kuralını taşır. Uygulama içi
// benzersizlik asıl olarak veritabanındaki `idx_users_login_name_unique` ile garanti edilir; burada yapılan denetimler öngörü içindir.

import { LOGIN_NAME_MAX, LOGIN_NAME_MIN, LOGIN_NAME_PATTERN } from './people_common.js';
import { requireScopeSite, siteVisibleUserSql } from './bulk_import_scope.js';

/** Kullanıcı adı tabanı üst sınırı: LOGIN_NAME_MAX (40) - "_NNN" benzersizlik eki payı. */
export const LOGIN_NAME_BASE_MAX = 36;
/**
 * Bir taban için denenecek en çok varyasyon (taban, taban_2 ... taban_5000). Türkiye genelinde çok yaygın bir ad (örn. «mehmet.yilmaz») binlerce kez
 * alınmış olabilir; sınır buna göre geniştir (ek sorgu sayısı yine küçüktür: geç varyasyonlar 250'lik gruplarla sorgulanır).
 */
export const MAX_LOGIN_ATTEMPTS = 5000;
/** Toplu çözümlemede tek sorguda önden denetlenen varyasyon sayısı (ilk denemelerin neredeyse tamamı bunlarla biter). */
const PREFETCH_VARIANTS = 6;
/** Geç denemelerde bir tabanın bir sorguda denetlenen varyasyon sayısı: ilk 100 varyasyonda 25'lik, sonrasında 250'lik gruplar. */
const batchSpan = (attempt) => (attempt <= 100 ? 25 : 250);
const QUERY_CHUNK = 5000;

const TR_MAP = Object.freeze({
  ç: 'c', Ç: 'c', ğ: 'g', Ğ: 'g', ı: 'i', I: 'i', İ: 'i', ö: 'o', Ö: 'o', ş: 's', Ş: 's', ü: 'u', Ü: 'u',
});
const foldTurkish = (text) => text.replace(/[çÇğĞıIİöÖşŞüÜ]/g, (m) => TR_MAP[m] ?? m);

/**
 * Ad soyaddan kullanıcı adı tabanı: Türkçe harfler sadeleşir, küçük harf, [a-z0-9] dışındaki her öbek tek nokta, baş/son nokta atılır, en çok 36
 * karakter; boşsa [fallback]. (Eski `bulk_import_writer.slugifyLoginName`; yazıcı bunu yeniden dışa aktarır.)
 */
export function slugifyLoginName(fullName, fallback = 'kullanici') {
  if (!fullName || typeof fullName !== 'string') return fallback;
  let clean = foldTurkish(fullName).toLowerCase();
  clean = clean.replace(/[^a-z0-9]+/g, '.').replace(/^\.+|\.+$/g, '');
  if (clean.length > LOGIN_NAME_BASE_MAX) clean = clean.slice(0, LOGIN_NAME_BASE_MAX).replace(/\.+$/, '');
  return clean || fallback;
}

/**
 * Yöneticinin tabloya YAZDIĞI kullanıcı adı: kırpılır, Türkçe harfler sadeleşir, küçük harfe çevrilir, boşluk öbeği noktaya dönüşür; sonra sistemin
 * kullanıcı adı kuralı uygulanır (3-40 karakter, yalnız [a-z0-9._-]). Ad soyaddan üretilen tabandan FARKLI olarak `_` ve `-` korunur (önerilen
 * `ahmet.yilmaz_2` yazıldığı gibi kalsın).
 * @returns {{ value: string|null, error: null|'EMPTY'|'TOO_SHORT'|'TOO_LONG'|'CHARS' }} `value`: biçim hatası olsa da normalleştirilmiş metin
 */
export function normalizeTypedLoginName(raw) {
  if (raw === null || raw === undefined) return { value: null, error: 'EMPTY' };
  if (typeof raw !== 'string') return { value: null, error: 'CHARS' };
  const text = foldTurkish(raw.trim()).toLowerCase().replace(/\s+/g, '.');
  if (text === '') return { value: null, error: 'EMPTY' };
  if (text.length < LOGIN_NAME_MIN) return { value: text, error: 'TOO_SHORT' };
  if (text.length > LOGIN_NAME_MAX) return { value: text, error: 'TOO_LONG' };
  if (!LOGIN_NAME_PATTERN.test(text)) return { value: text, error: 'CHARS' };
  return { value: text, error: null };
}

/** Kullanıcıya gösterilen neden metinleri (denetim ucu ve önizleme). */
export function loginNameReason(code) {
  switch (code) {
    case 'EMPTY':
      return 'Kullanıcı adı boş olamaz.';
    case 'TOO_SHORT':
      return `Kullanıcı adı en az ${LOGIN_NAME_MIN} karakter olmalı.`;
    case 'TOO_LONG':
      return `Kullanıcı adı en çok ${LOGIN_NAME_MAX} karakter olabilir.`;
    case 'CHARS':
      return 'Kullanıcı adında yalnız harf, rakam, nokta (.), alt çizgi (_) ve tire (-) olabilir; boşluk ve @ kullanılamaz.';
    case 'TAKEN':
      return 'Bu kullanıcı adı bu sitede başka bir hesapta kayıtlı.';
    case 'IN_FILE':
      return 'Bu kullanıcı adı dosyada başka bir satırda kullanılıyor.';
    default:
      return 'Kullanıcı adı kullanılamıyor.';
  }
}

/**
 * [base] için [attempt]. varyasyon: 1 = taban, n>1 = `taban_n`. Toplam uzunluk 40'ı aşmasın diye taban gerekirse kısaltılır. Taban 3 karakterden kısaysa
 * (örn. "al") yalın taban geçersiz olacağından 1. deneme atlanır: `al_2` ilk adaydır (`null` döner).
 */
export function loginNameVariant(base, attempt) {
  if (attempt <= 1) return base.length >= LOGIN_NAME_MIN ? base : null;
  const suffix = `_${attempt}`;
  const room = LOGIN_NAME_MAX - suffix.length;
  const head = base.length > room ? base.slice(0, room).replace(/\.+$/, '') : base;
  return `${head}${suffix}`;
}

/**
 * ÖNİZLEME / DENETİM kapsamı: bu adayların hangileri [siteCode] sitesinin yöneticisinin görebildiği hesaplarda var (küçük harfli küme; kapsam: siteVisibleUserSql).
 * Başka sitedeki hesapların adları «yok» sayılır: bu işlev yöneticiye gösterilen HİÇBİR yanıtta sistem geneli bilgi sızdırmaz. Sistem geneli kesin denetim yalnız
 * yazım anındadır ([claimLoginName]).
 * @param {{ siteCode: number }} scope ZORUNLU; eksik / geçersizse TypeError (kapsamsız sorguya düşülmez)
 * @returns {Promise<Set<string>>}
 */
export async function takenLoginNames(db, names, { siteCode } = {}) {
  const site = requireScopeSite(siteCode);
  const taken = new Set();
  const unique = [...new Set(names.map((name) => String(name).toLowerCase()))];
  for (let index = 0; index < unique.length; index += QUERY_CHUNK) {
    const part = unique.slice(index, index + QUERY_CHUNK);
    const result = await db.query(
      `SELECT LOWER(u.login_name) AS name FROM users u WHERE LOWER(u.login_name) = ANY($1::TEXT[]) AND ${siteVisibleUserSql('u.user_code', '$2::BIGINT')}`,
      [part, site],
    );
    for (const row of result.rows) taken.add(row.name);
  }
  return taken;
}

/**
 * YAZIM kapsamı: bu adayların hangileri `users` tablosunda (sistem genelinde, başka siteler ve silinmiş hesaplar dahil) var. `idx_users_login_name_unique` ile AYNI
 * kapsam. SONUCU ASLA yöneticiye önizleme / denetim yanıtı olarak göstermeyin (sayım açığı): yalnız [claimLoginName] yazım anında kullanır.
 */
async function takenLoginNamesGlobal(db, names) {
  const taken = new Set();
  const unique = [...new Set(names.map((name) => String(name).toLowerCase()))];
  for (let index = 0; index < unique.length; index += QUERY_CHUNK) {
    const part = unique.slice(index, index + QUERY_CHUNK);
    const result = await db.query(`SELECT LOWER(login_name) AS name FROM users WHERE LOWER(login_name) = ANY($1::TEXT[])`, [part]);
    for (const row of result.rows) taken.add(row.name);
  }
  return taken;
}

/**
 * Toplu çözümleme: her istek için BU SİTEDE (siteVisibleUserSql kapsamı) ve bu toplu içinde BOŞTA olan ilk varyasyonu verir. Başka sitelerdeki adlar görünmez:
 * kesin (sistem geneli) ad yazım anında verilir ([claimLoginName]).
 * Sıra: [fixed] (yöneticinin seçtiği, plan aşamasında boşta doğrulanmış) adlar ÖNCE rezerve edilir (üretilen ad onlarla çakışmasın), sonra satır sırasıyla
 * üretilir. Sorgu sayısı satır sayısından bağımsız (önden 6 varyasyon: 5000 satır <= birkaç sorgu); yalnız çok çakışan adlar ek sorgu yapar.
 * @param {{ key: string, base: string, fixed?: boolean }[]} requests satır sırasıyla
 * @param {{ reserved?: Iterable<string>, siteCode: number }} options `reserved`: başka yerden rezerve edilmiş adlar (örn. aynı yüklemede başka kişilere ayrılmış);
 *   `siteCode`: ZORUNLU sorgu kapsamı (eksikse TypeError)
 * @returns {Promise<Map<string, string|null>>} key -> kullanıcı adı (null: [MAX_LOGIN_ATTEMPTS] içinde bulunamadı)
 */
export async function resolveLoginNames(db, requests, { reserved = [], siteCode } = {}) {
  const site = requireScopeSite(siteCode);
  const owner = new Map(); // küçük harfli ad -> sahibi (key); rezerveler sahibi '' olanlardır
  for (const name of reserved) owner.set(String(name).toLowerCase(), '');
  for (const request of requests) {
    if (request.fixed) owner.set(request.base.toLowerCase(), request.key);
  }
  const known = new Map(); // küçük harfli ad -> veritabanında var mı
  const check = async (names) => {
    const need = [...new Set(names.map((name) => name.toLowerCase()))].filter((name) => !known.has(name));
    if (need.length === 0) return;
    const taken = await takenLoginNames(db, need, { siteCode: site });
    for (const name of need) known.set(name, taken.has(name));
  };

  const prefetch = [];
  for (const request of requests) {
    for (let attempt = 1; attempt <= PREFETCH_VARIANTS; attempt += 1) {
      const name = loginNameVariant(request.base, attempt);
      if (name !== null) prefetch.push(name);
    }
  }
  await check(prefetch);

  const out = new Map();
  for (const request of requests) {
    let chosen = null;
    for (let attempt = 1; attempt <= MAX_LOGIN_ATTEMPTS && chosen === null; attempt += 1) {
      const name = loginNameVariant(request.base, attempt);
      if (name === null) continue;
      const low = name.toLowerCase();
      if (!known.has(low)) {
        // önden denetlenmemiş geç varyasyonlar bu tabanın sonraki LATE_BATCH denemesiyle birlikte sorgulanır
        const batch = [];
        for (let next = attempt; next < attempt + batchSpan(attempt) && next <= MAX_LOGIN_ATTEMPTS; next += 1) {
          const candidate = loginNameVariant(request.base, next);
          if (candidate !== null) batch.push(candidate);
        }
        await check(batch);
      }
      const held = owner.get(low);
      if (held !== undefined && held !== request.key) continue; // başka satıra/rezerveye ait
      if (known.get(low) === true) continue; // veritabanında var
      chosen = name;
    }
    if (chosen !== null) owner.set(chosen.toLowerCase(), request.key);
    out.set(request.key, chosen);
  }
  return out;
}

/** [base]'ten başlayarak [takenOf] (kapsamı çağıran belirler) ile boştaki ilk adı arar; ortak gövde: [claimLoginName] (sistem geneli), [suggestLoginName] (site). */
async function claimFrom(takenOf, base, { preferred = null, reserved = new Map(), key = null, skip = new Set() } = {}) {
  const blocked = (low) => {
    const held = reserved.get(low);
    return (held !== undefined && held !== key) || skip.has(low);
  };
  if (preferred) {
    const low = preferred.toLowerCase();
    if (!blocked(low) && !(await takenOf([low])).has(low)) return preferred;
  }
  for (let attempt = 1; attempt <= MAX_LOGIN_ATTEMPTS; attempt += batchSpan(attempt)) {
    const names = [];
    for (let next = attempt; next < attempt + batchSpan(attempt) && next <= MAX_LOGIN_ATTEMPTS; next += 1) {
      const name = loginNameVariant(base, next);
      if (name !== null) names.push(name);
    }
    const taken = await takenOf(names);
    for (const name of names) {
      const low = name.toLowerCase();
      if (!taken.has(low) && !blocked(low)) return name;
    }
  }
  return null;
}

/**
 * YAZIM anı (SİSTEM kapsamı): [base]'ten başlayarak boştaki ilk adı alır. [preferred] (önizlemede gösterilen ad) boştaysa ONU verir; başkası almışsa (yarış YA DA başka
 * sitede alınmış: önizleme yalnız bu siteyi görür) bir sonraki boş varyasyonu. [reserved]: küçük harfli ad -> sahip anahtarı (bu çalıştırmada başka kişilere ayrılmış adlar
 * çalınmaz; [key] kendi adıdır). [skip]: az önce 23505 ile reddedilen adlar. Aynı transaction içinde çağrılır; veritabanındaki UNIQUE dizin yine de son kapıdır (çağıran
 * 23505'te yeniden dener). SONUÇ yalnız onay sonucunda (nihai ad) yöneticiye gider; önizleme / denetim yanıtında kullanılmaz ([suggestLoginName] site kapsamlıdır).
 * @returns {Promise<string|null>}
 */
export async function claimLoginName(db, base, options = {}) {
  return claimFrom((names) => takenLoginNamesGlobal(db, names), base, options);
}

/**
 * ÖNERİ (SİTE kapsamı): [base]'ten başlayarak bu sitenin görebildiği hesaplarda boş olan ilk ad. Başka sitelerdeki adlar atlanmaz (sızmaz); bu yüzden öneri yazımda yine
 * başka bir sonekle verilebilir (onay sonucunda bildirilir).
 * @param {{ siteCode: number }} scope ZORUNLU
 * @returns {Promise<string|null>}
 */
export async function suggestLoginName(db, base, { siteCode } = {}) {
  const site = requireScopeSite(siteCode);
  return claimFrom((names) => takenLoginNames(db, names, { siteCode: site }), base);
}

/**
 * Tek ad denetimi (önizleme tablosunda yöneticinin yazdığı ad). Biçim + BU SİTEDE kullanılabilirlik; kullanılamıyorsa sebep ve [suggestion] (aynı tabandan ilk boş
 * varyasyon). Başka sitede kayıtlı ad «kullanılabilir» döner (yanıt var/yok bilgisini sızdırmaz); kesin ad yazım anında verilir.
 * @param {{ siteCode: number }} scope ZORUNLU
 * @returns {Promise<{ ok: boolean, login_name: string|null, code: string, message: string|null, suggestion: string|null }>}
 */
export async function checkLoginName(db, raw, { siteCode } = {}) {
  const site = requireScopeSite(siteCode);
  const typed = normalizeTypedLoginName(raw);
  if (typed.error) {
    return { ok: false, login_name: typed.value, code: typed.error, message: loginNameReason(typed.error), suggestion: null };
  }
  const taken = await takenLoginNames(db, [typed.value], { siteCode: site });
  if (taken.has(typed.value)) {
    const suggestion = await suggestLoginName(db, typed.value, { siteCode: site });
    return { ok: false, login_name: typed.value, code: 'TAKEN', message: loginNameReason('TAKEN'), suggestion };
  }
  return { ok: true, login_name: typed.value, code: 'OK', message: null, suggestion: null };
}
