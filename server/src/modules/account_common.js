// Hesap silme ve kişisel veri dışa aktarma (satışa hazırlık, S-A): ortak sabitler, hata üreticileri ve küçük saf yardımcılar.
//
// Sözleşme: docs/PLATFORM_SATISA_HAZIRLIK.md §1.5 (veri dışa aktarma) ve §1.6 (hesap silme).
// Hata gövdesi: { error: "<Türkçe mesaj>", code: "<MAKINE_KODU>", ... } (PlatformError); 5xx'te { error, errorId }.
// GİZLİLİK: bu modüllerde e-posta, telefon, ad, parola ve belirteç ASLA log'a yazılmaz (yalnız hata kodu / errorId).

import { PlatformError } from './errors.js';
import { DELETED_EMAIL_DOMAIN } from '../utils/reserved_email.js';

/** Kimliksizleştirilmiş hesabın görünen adı (hesap satırı ve ad anlık görüntüleri). */
export const DELETED_USER_NAME = 'Silinmiş Kullanıcı';
// Alan adı doğrulama tarafıyla (utils/reserved_email.js: kayıt / davet / yönetici oluşturma bu alan adını REDDEDER) tek kaynaktan gelir.
export { DELETED_EMAIL_DOMAIN };
/**
 * Silinmiş hesabın e-postası: benzersiz (user_code) ve teslim edilemez (.invalid, RFC 2606). Aynı adresle yeniden kayıt serbest kalır.
 * `suffix` yalnız önceden alınmış bir satırla ÇAKIŞMA durumunda verilir (silme servisi rastgele bir sonek üretir; users.email UNIQUE -> 23505 olmaz).
 */
export const deletedEmailFor = (userCode, suffix = '') => {
  const tail = typeof suffix === 'string' && /^[a-z0-9]{1,32}$/.test(suffix) ? `-${suffix}` : '';
  return `deleted-${Number(userCode)}${tail}@${DELETED_EMAIL_DOMAIN}`;
};

/**
 * CRM (site yönetiminin kişi kaydı) hesap silinince KİŞİ ADINI saklar mı? true: ad (ve kişi satırındaki yönetici girişi telefon) yasal saklama
 * gerekçesiyle kalır; hesaptaki telefon / e-posta ASLA kopyalanmaz. false: ad da "Silinmiş Kullanıcı" olur. Hukuk (LEGAL) kararı bu tek sabitle değişir.
 */
export const CRM_KEEP_NAME = true;

/** Kimliksizleştirilen kişinin kapı geçiş kayıtlarındaki / misafir geçiş başlıklarındaki adın yerine yazılan değer. */
export const DELETED_GUEST_PASS_TITLE = 'Silinmiş kullanıcının geçişi';

// --- Dışa aktarma sınırları -------------------------------------------------------------------------------
/** Yanıt gövdesi üst sınırı (bayt); aşılırsa büyük bölümler kısaltılır ve `truncated: true` yazılır. */
export const EXPORT_MAX_BYTES = 5 * 1024 * 1024;
/** Kullanıcı başına 24 saatte en çok 3 dışa aktarma (başarılı parola doğrulamasından sonra). */
export const EXPORT_RATE_LIMIT = 3;
export const EXPORT_RATE_WINDOW_HOURS = 24;
/** Bölüm başına satır üst sınırları (en yeni kayıtlar). Aşılırsa bölüm kısaltılır, `truncated_sections` içinde belirtilir. */
export const EXPORT_ROW_LIMITS = Object.freeze({
  door_events: 5000,
  announcements_received: 300,
  site_applications: 100,
  guest_passes: 1000,
  join_requests: 200,
  qr_requests: 200,
  uploaded_documents: 500,
  work_items_created: 500,
  work_item_comments: 1000,
  reservations_made: 500,
  concierge_requests_made: 300,
  finance_reminders_received: 300,
  receipts: 200,
});

// --- Silme engelleri --------------------------------------------------------------------------------------
export const BLOCKER_SUPER_USER = 'SUPER_USER';
export const BLOCKER_LAST_SITE_MANAGER = 'LAST_SITE_MANAGER';

export const superUserBlocker = () => ({
  code: BLOCKER_SUPER_USER,
  message: 'Süper kullanıcı hesabı bu ekrandan silinemez. Hesabın kaldırılması için başka bir süper kullanıcıyla iletişime geçin.',
});

/** @param {{ site_code: number|string, name?: string|null }} site */
export const lastSiteManagerBlocker = (site) => ({
  code: BLOCKER_LAST_SITE_MANAGER,
  message: `${site?.name ? `"${String(site.name).slice(0, 120)}" sitesinde` : 'Bir sitede'} aktif üyeler varken tek yöneticisiniz. Önce siteye başka bir yönetici atayın veya siteyi kaldırın.`,
  site_id: Number(site.site_code),
});

// --- Hatalar ----------------------------------------------------------------------------------------------
export const confirmRequired = () => new PlatformError(400, 'CONFIRM_REQUIRED', 'Hesabı silmek için onay gereklidir.');
export const currentPasswordRequired = () =>
  new PlatformError(400, 'CURRENT_PASSWORD_REQUIRED', 'Devam etmek için mevcut parolanızı girmelisiniz.');
// 401/403 DEĞİL: istemci bunu oturum hatası sanıp çıkış yapmasın.
export const currentPasswordInvalid = () => new PlatformError(400, 'CURRENT_PASSWORD_INVALID', 'Mevcut parola hatalı.');
export const currentPasswordLocked = (retryAfterSeconds) =>
  new PlatformError(429, 'CURRENT_PASSWORD_LOCKED', 'Çok fazla hatalı mevcut parola denemesi. Biraz sonra tekrar deneyin.', {
    retry_after_seconds: Math.max(1, Math.ceil(Number(retryAfterSeconds) || 1)),
  });
/** Hesap zaten silinmiş: 401 (istemci oturumu kapatır). Çift gönderim yarışında kaybeden istek de bunu alır. */
export const accountDeleted = () => new PlatformError(401, 'ACCOUNT_DELETED', 'Bu hesap silinmiş.');
export const deleteBlocked = (blockers) =>
  new PlatformError(409, 'ACCOUNT_DELETE_BLOCKED', 'Hesabınız şu anda silinemez.', { blockers });
export const accountBusy = () =>
  new PlatformError(409, 'ACCOUNT_DELETE_BUSY', 'Hesap silme şu anda tamamlanamadı. Birkaç saniye sonra tekrar deneyin.');
/** Kısaltılamayan bölümler (kimlik, üyelikler vb.) tek başına sınırı aşıyor: dosya üretilemez (hak iade edilir). */
export const exportTooLarge = () =>
  new PlatformError(
    413,
    'EXPORT_TOO_LARGE',
    'Verileriniz tek bir dosyaya sığmayacak kadar büyük. Lütfen destek ekibiyle iletişime geçin.',
  );
export const exportRateLimited = (retryAfterSeconds) =>
  new PlatformError(
    429,
    'EXPORT_RATE_LIMITED',
    `Kişisel veri dışa aktarma sınırına ulaştınız (${EXPORT_RATE_WINDOW_HOURS} saatte en fazla ${EXPORT_RATE_LIMIT}). Daha sonra tekrar deneyin.`,
    { retry_after_seconds: Math.max(1, Math.ceil(Number(retryAfterSeconds) || 1)) },
  );

// --- Küçük saf yardımcılar --------------------------------------------------------------------------------
export const plainObject = (value) => (value && typeof value === 'object' && !Array.isArray(value) ? value : {});
export const bodyOf = (req) => plainObject(req?.body);

const INT32_MAX = 2147483647;

/** authUser nesnesinden kullanıcı kodu (pozitif INTEGER) ya da null. */
export function userCodeOf(authUser) {
  const candidate = Number(authUser?.user_code ?? authUser?.userCode ?? authUser?.id);
  return Number.isSafeInteger(candidate) && candidate > 0 && candidate <= INT32_MAX ? candidate : null;
}

/** "YYYYMMDD" (Europe/Istanbul takvimi). */
export function dateStamp(date = new Date()) {
  const parts = new Intl.DateTimeFormat('en-CA', { timeZone: 'Europe/Istanbul', year: 'numeric', month: '2-digit', day: '2-digit' }).format(date);
  return parts.replace(/-/g, '');
}

export const exportFileName = (userCode, date = new Date()) => `kisisel-veri-${Number(userCode)}-${dateStamp(date)}.json`;

/** Dahili daire hesabı (@ahbu.local) gerçek bir posta kutusu değildir: e-posta gönderilmez. */
export function isDeliverableEmail(value) {
  const text = String(value ?? '').trim();
  if (text.length === 0 || text.length > 254) {
    return false;
  }
  if (/@ahbu\.local$/i.test(text) || /@deleted\.invalid$/i.test(text)) {
    return false;
  }
  return /^[^\s@,;<>"()]+@[^\s@,;<>"()]+\.[^\s@,;<>"()]+$/.test(text);
}

/** Sayısal kimlik (pg BIGINT metni olabilir) -> Number; boş/null korunur. */
export function numOrNull(value) {
  if (value === null || value === undefined) {
    return null;
  }
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : null;
}

/** Sıralı iki sayı dizisinde `inner` bütünüyle `outer` içinde mi (yeniden okunan kapsam kilitlenen kapsamdan büyüdü mü?). */
export function isSubsetOf(inner, outer) {
  const set = new Set(outer.map(Number));
  return inner.every((value) => set.has(Number(value)));
}
