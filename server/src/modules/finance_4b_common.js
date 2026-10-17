// Finans Faz 4b ortak sabitler, hata fabrikaları ve küçük yardımcılar. Saf: DB/ağ bağımsız.
//
// Sözleşme: docs/PLATFORM_FINANS_4B.md. Hata gövdesi { error, code } (PlatformError). PARA tamsayı kuruştur (finance_money.js): bu dosyada kayan nokta yok.

import { createHash } from 'node:crypto';
import { PlatformError } from './errors.js';
import { canonicalJson, invalidBody, invalidQuery } from './finance_common.js';
import { parsePositiveId } from './people_common.js';

/** KMK 634 m.20/2: aylık %5 = 500 baz puan. Oran bu sabitin üstüne AYARLANAMAZ (sunucu sabiti). [AVUKAT DOĞRULASIN] */
export const LATE_FEE_MAX_MONTHLY_BP = 500;
export const LATE_FEE_NAME = 'Gecikme tazminatı';
export const ACCOUNT_LIMIT = 20;
export const CATEGORY_LIMIT = 100;
export const SUPPLIER_LIMIT = 2000;
export const EXPENSE_DOCUMENT_LIMIT_PER_EXPENSE = 5;
export const EXPORT_ROW_LIMIT = 20000;
export const STATEMENT_ROW_LIMIT = 5000;
export const LATE_FEE_EXCLUDED_LIMIT = 5000;

const conflict = (code, message, extra) => new PlatformError(409, code, message, extra);
const notFound = (code, message) => new PlatformError(404, code, message);

// --- Makbuz ----------------------------------------------------------------------------------------------------------------------------
export const receiptNotFound = () => notFound('RECEIPT_NOT_FOUND', 'Makbuz bulunamadı.');
export const paymentReversed = () => conflict('PAYMENT_REVERSED', 'Bu tahsilat iptal edilmiş; makbuz düzenlenemez.');
export const receiptAlreadyCancelled = () => conflict('RECEIPT_ALREADY_CANCELLED', 'Bu makbuz zaten iptal edilmiş.');
export const receiptNotCancellable = () => conflict('RECEIPT_NOT_CANCELLABLE', 'İptal makbuzu iptal edilemez.');

// --- Gecikme tazminatı ---------------------------------------------------------------------------------------------------------------
export const lateFeeDisabled = () => conflict('LATE_FEE_DISABLED', 'Gecikme tazminatı bu sitede kapalı. Ayarlardan açın.');
export const lateFeeNotConfigured = () =>
  conflict('LATE_FEE_NOT_CONFIGURED', 'Gecikme tazminatı için başlangıç ayı belirlenmemiş. Ayarlardan girin.');
export const lateFeePeriodNotClosed = () =>
  conflict('LATE_FEE_PERIOD_NOT_CLOSED', 'Tazminat hesaplanacak dönem önce kapatılmalıdır.');
export const lateFeePeriodNotEnded = () => conflict('LATE_FEE_PERIOD_NOT_ENDED', 'Tazminat hesaplanacak ay henüz bitmedi.');
export const lateFeePeriodNotNext = (expectedPeriod) =>
  conflict('LATE_FEE_PERIOD_NOT_NEXT', 'Tazminat aylar sırayla hesaplanır; sıradaki dönemi seçin.', { expected_period: expectedPeriod });
export const lateFeeAlreadyPosted = () => conflict('LATE_FEE_ALREADY_POSTED', 'Bu dönem için tazminat zaten hesaplanmış.');
export const lateFeeRunNotFound = () => notFound('LATE_FEE_RUN_NOT_FOUND', 'Tazminat çalıştırması bulunamadı.');
export const lateFeeRunNotVoidable = () =>
  conflict('LATE_FEE_RUN_NOT_VOIDABLE', 'Yalnızca son aktif tazminat çalıştırması iptal edilebilir.');
export const periodHasLateFeeRun = () =>
  conflict('PERIOD_HAS_LATE_FEE_RUN', 'Bu dönemin ardından hesaplanmış gecikme tazminatı var. Önce tazminat çalıştırmasını iptal edin.');
export const legalApprovalRequired = () =>
  conflict(
    'LEGAL_APPROVAL_REQUIRED',
    'Bu özellik hukuki onay tamamlanana dek etkinleştirilemez. Sistem yöneticisiyle iletişime geçin.',
  );

// --- Kasa / banka ----------------------------------------------------------------------------------------------------------------------
export const noAccount = () => conflict('NO_ACCOUNT', 'Önce bir kasa veya banka hesabı oluşturun.');
export const accountNotFound = () => notFound('ACCOUNT_NOT_FOUND', 'Hesap bulunamadı.');
export const accountInactive = () => conflict('ACCOUNT_INACTIVE', 'Hesap pasif; yeni hareket eklenemez.');
export const allAccountsInactive = () => conflict('ACCOUNT_INACTIVE', 'Bu tarihte açık olan kasa ve banka hesaplarının hepsi pasif. Tahsilat girmek için ilgili hesabı yeniden etkinleştirin.');
export const accountRequired = () => conflict('ACCOUNT_REQUIRED', 'Tahsilatın girileceği kasa veya banka hesabını seçin.');
export const accountLimitReached = () => conflict('ACCOUNT_LIMIT', `Bir sitede en çok ${ACCOUNT_LIMIT} hesap olabilir.`);
export const accountNameTaken = () => conflict('ACCOUNT_NAME_TAKEN', 'Bu adla bir hesap zaten var.');
export const beforeOpeningDate = () => conflict('BEFORE_OPENING_DATE', 'Tarih hesabın açılış tarihinden önce olamaz.');
export const transferNotFound = () => notFound('TRANSFER_NOT_FOUND', 'Aktarım bulunamadı.');
export const transferAlreadyVoided = () => conflict('TRANSFER_ALREADY_VOIDED', 'Bu aktarım zaten iptal edilmiş.');
export const reconciliationOrder = () =>
  conflict(
    'RECONCILIATION_ORDER',
    'Daha yeni tarihli bir mutabakatın düzeltmesi var; bu eski tarih için ayrıca düzeltme yazılamaz. Önce yeni tarihli mutabakatın düzeltmesini gözden geçirin ya da bu mutabakatı yalnızca kayıt olarak (düzeltmesiz) girin.',
  );
export const reconciliationStale = (extra) =>
  conflict('RECONCILIATION_STALE', 'Hesap bakiyesi siz bakarken değişti. Yeniden hesaplayıp tekrar deneyin.', extra);
export const periodHasUnassignedPayments = (extra) =>
  conflict(
    'PERIOD_HAS_UNASSIGNED_PAYMENTS',
    'Hesaba eşlenmemiş tahsilatlar var. Önce Kasa bölümünden tahsilatları hesaplara eşleyin.',
    extra,
  );

// --- Gider ------------------------------------------------------------------------------------------------------------------------------
export const expenseNotFound = () => notFound('EXPENSE_NOT_FOUND', 'Gider bulunamadı.');
export const expenseAlreadyVoided = () => conflict('EXPENSE_ALREADY_VOIDED', 'Bu gider zaten iptal edilmiş.');
export const duplicateExpense = (existingId) =>
  conflict('DUPLICATE_EXPENSE', 'Aynı gider kısa süre önce kaydedilmiş görünüyor. Giderleri kontrol edin.', { existing_expense_id: existingId });
export const duplicateDocumentNo = (existingId) =>
  conflict('DUPLICATE_DOCUMENT_NO', 'Bu tedarikçi için aynı belge numarasıyla bir gider zaten kayıtlı.', { existing_expense_id: existingId });
export const categoryNotFound = () => notFound('CATEGORY_NOT_FOUND', 'Kategori bulunamadı.');
export const categoryInactive = () => conflict('CATEGORY_INACTIVE', 'Kategori pasif; gider eklenemez.');
export const categoryNameTaken = () => conflict('CATEGORY_NAME_TAKEN', 'Bu adla bir kategori zaten var.');
export const categoryLimitReached = () => conflict('CATEGORY_LIMIT', `Bir sitede en çok ${CATEGORY_LIMIT} kategori olabilir.`);
export const supplierNotFound = () => notFound('SUPPLIER_NOT_FOUND', 'Tedarikçi bulunamadı.');
export const supplierNameTaken = () => conflict('SUPPLIER_NAME_TAKEN', 'Bu adla bir tedarikçi zaten var.');
export const supplierLimitReached = () => conflict('SUPPLIER_LIMIT', `Bir sitede en çok ${SUPPLIER_LIMIT} tedarikçi olabilir.`);
export const documentsNotAvailable = () =>
  conflict('DOCUMENTS_NOT_AVAILABLE', 'Belge ekleme bu sunucuda henüz kullanılamıyor. Gider belge olmadan kaydedilebilir.');
export const expenseDocumentLimit = () =>
  conflict('EXPENSE_DOCUMENT_LIMIT', `Bir gidere en çok ${EXPENSE_DOCUMENT_LIMIT_PER_EXPENSE} belge eklenebilir.`);
export const documentNotFound = () => notFound('DOCUMENT_NOT_FOUND', 'Belge bulunamadı.');

// --- Rapor / dışa aktarma -----------------------------------------------------------------------------------------------------------
export const statementTooLarge = () =>
  conflict('STATEMENT_TOO_LARGE', `Ekstre en çok ${STATEMENT_ROW_LIMIT} satır olabilir. Tarih aralığını daraltın.`);
export const reportBusy = () => {
  const error = new PlatformError(503, 'REPORT_BUSY', 'Rapor sunucusu meşgul. Biraz sonra tekrar deneyin.');
  error.retryAfterSeconds = 5;
  return error;
};
export const exportKindNotFound = () => new PlatformError(404, 'EXPORT_KIND_NOT_FOUND', 'Dışa aktarma türü bulunamadı.');
export const exportTooLarge = () =>
  new PlatformError(422, 'EXPORT_TOO_LARGE', 'Dışa aktarılacak satır sayısı çok fazla. Süzgeç kullanarak daraltın.');

// --- Hatırlatma ------------------------------------------------------------------------------------------------------------------------
export const remindersDisabled = () => conflict('REMINDERS_DISABLED', 'Borç hatırlatma bu sitede kapalı. Ayarlardan açın.');
export const reminderDailyLimit = () => conflict('REMINDER_DAILY_LIMIT', 'Bugün zaten bir hatırlatma gönderildi. Yarın tekrar deneyin.');
export const noReminderRecipients = () => conflict('NO_REMINDER_RECIPIENTS', 'Hatırlatma gönderilecek kişi bulunamadı.');
export const emailNotConfigured = () =>
  conflict('EMAIL_NOT_CONFIGURED', 'E-posta gönderimi bu sunucuda yapılandırılmamış; hatırlatma gönderilemez.');
export const reminderRunNotFound = () => notFound('REMINDER_RUN_NOT_FOUND', 'Hatırlatma çalıştırması bulunamadı.');
export const reminderRunNotCancellable = () => conflict('REMINDER_RUN_NOT_CANCELLABLE', 'Bu hatırlatma çalıştırması zaten iptal edilmiş.');

// --- Ayarlar ----------------------------------------------------------------------------------------------------------------------------
export const settingsStale = (extra) =>
  conflict('SETTINGS_STALE', 'Ayarlar siz bakarken değişti. Yenileyip tekrar deneyin.', extra);

// --- Gün sayıları (UTC takvim; yaz saati etkisi yok) -------------------------------------------------------------------------------------

const DAY_MS = 86400000;

/** 'YYYY-MM-DD' -> 1970-01-01'den beri gün sayısı (tamsayı). */
export function dayNumber(iso) {
  const [year, month, day] = [Number(iso.slice(0, 4)), Number(iso.slice(5, 7)), Number(iso.slice(8, 10))];
  return Date.UTC(year, month - 1, day) / DAY_MS;
}

/** Gün sayısı -> 'YYYY-MM-DD'. */
export function isoOfDay(number) {
  return new Date(number * DAY_MS).toISOString().slice(0, 10);
}

/** Ayın ilk günü 'YYYY-MM-01' -> ayın son günü 'YYYY-MM-DD'. */
export function lastDayOfMonth(periodIso) {
  const [year, month] = [Number(periodIso.slice(0, 4)), Number(periodIso.slice(5, 7))];
  return isoOfDay(Date.UTC(year, month, 1) / DAY_MS - 1);
}

/** Ayın gün sayısı (28..31). */
export function daysInMonth(periodIso) {
  return dayNumber(lastDayOfMonth(periodIso)) - dayNumber(periodIso) + 1;
}

export const sha256Hex = (text) => createHash('sha256').update(text).digest('hex');
export const fingerprintOf = (value) => sha256Hex(canonicalJson(value));

// --- Gövde / sorgu yardımcıları ---------------------------------------------------------------------------------------------------------

export const objectOf = (body) => (body && typeof body === 'object' && !Array.isArray(body) ? body : {});
export const present = (value) => value !== undefined && value !== null;
export const hasOwn = (object, key) => Object.prototype.hasOwnProperty.call(object, key);

/** Zorunlu pozitif kimlik (gövde). */
export function requireId(value, label) {
  const id = typeof value === 'number' || typeof value === 'string' ? parsePositiveId(String(value)) : null;
  if (id === null) {
    throw invalidBody(`${label} geçersiz.`);
  }
  return id;
}

/** İsteğe bağlı pozitif kimlik (gövde): yoksa null, geçersizse 400. */
export function optionalId(value, label) {
  return present(value) && value !== '' ? requireId(value, label) : null;
}

/** Sorgu parametresi kimliği: yoksa null; geçersizse 400 INVALID_QUERY. */
export function queryId(value) {
  if (value === undefined || value === null || String(value).trim() === '') {
    return null;
  }
  const id = parsePositiveId(String(value).trim());
  if (id === null) {
    throw invalidQuery();
  }
  return id;
}

/** 'YYYY-MM-DD' sorgu tarihi: yoksa null; geçersizse 400 INVALID_QUERY. */
export function queryDate(value) {
  if (value === undefined || value === null || String(value).trim() === '') {
    return null;
  }
  const text = String(value).trim();
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(text);
  if (!match) {
    throw invalidQuery();
  }
  const probe = new Date(Date.UTC(Number(match[1]), Number(match[2]) - 1, Number(match[3])));
  if (probe.getUTCFullYear() !== Number(match[1]) || probe.getUTCMonth() !== Number(match[2]) - 1 || probe.getUTCDate() !== Number(match[3])) {
    throw invalidQuery();
  }
  if (Number(match[1]) < 2000 || Number(match[1]) > 2100) {
    throw invalidQuery();
  }
  return text;
}

/** 'YYYY-MM' sorgu ayı: yoksa null; geçersizse 400 INVALID_QUERY. Çıktı 'YYYY-MM-01'. */
export function queryMonth(value) {
  if (value === undefined || value === null || String(value).trim() === '') {
    return null;
  }
  const match = /^(\d{4})-(\d{2})(?:-01)?$/.exec(String(value).trim());
  if (!match || Number(match[1]) < 2000 || Number(match[1]) > 2100 || Number(match[2]) < 1 || Number(match[2]) > 12) {
    throw invalidQuery();
  }
  return `${match[1]}-${match[2]}-01`;
}

/** Sorgu tamsayısı (alt/üst sınırlı). */
export function queryInt(value, { min, max, fallback }) {
  if (value === undefined || value === null || String(value).trim() === '') {
    return fallback;
  }
  const text = String(value).trim();
  if (!/^\d{1,9}$/.test(text)) {
    throw invalidQuery();
  }
  const parsed = Number(text);
  if (parsed < min) {
    throw invalidQuery();
  }
  return parsed > max ? max : parsed;
}

/** Sorgu enum'u: yoksa fallback; listede yoksa 400 INVALID_QUERY. */
export function queryEnum(value, allowed, fallback) {
  if (value === undefined || value === null || String(value).trim() === '') {
    return fallback;
  }
  const text = String(value).trim();
  if (!allowed.includes(text)) {
    throw invalidQuery();
  }
  return text;
}

/** Sorgu mantıksal değeri ('true'/'false'). */
export function queryBool(value, fallback = false) {
  if (value === undefined || value === null || String(value).trim() === '') {
    return fallback;
  }
  const text = String(value).trim();
  if (text !== 'true' && text !== 'false') {
    throw invalidQuery();
  }
  return text === 'true';
}

/** Türkçe ay adları (tazminat açıklaması, rapor etiketi). */
export const TURKISH_MONTHS = Object.freeze([
  'Ocak',
  'Şubat',
  'Mart',
  'Nisan',
  'Mayıs',
  'Haziran',
  'Temmuz',
  'Ağustos',
  'Eylül',
  'Ekim',
  'Kasım',
  'Aralık',
]);

/** 'YYYY-MM-01' -> 'Eylül 2026'. */
export const monthTitle = (periodIso) => `${TURKISH_MONTHS[Number(periodIso.slice(5, 7)) - 1]} ${periodIso.slice(0, 4)}`;

/** Kuruş (BigInt) -> Türkçe biçim '1.234,56' (kayan nokta YOK; yalnız e-posta / metin için). */
export function formatMinor(value) {
  const big = typeof value === 'bigint' ? value : BigInt(value);
  const negative = big < 0n;
  const abs = negative ? -big : big;
  const whole = (abs / 100n).toString();
  const cents = (abs % 100n).toString().padStart(2, '0');
  let grouped = '';
  for (let i = 0; i < whole.length; i += 1) {
    if (i > 0 && (whole.length - i) % 3 === 0) {
      grouped += '.';
    }
    grouped += whole[i];
  }
  return `${negative ? '-' : ''}${grouped},${cents}`;
}
