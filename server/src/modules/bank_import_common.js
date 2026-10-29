// Banka dosyası ortak parçalar: sabitler, hata fabrikaları, gövde doğrulayıcıları (saf).
import { PlatformError } from './errors.js';
import { normalizeIban } from './bank_line_match.js';

export const MAX_LINES = 1500; // gövde genel 1 MB ayrıştırıcının altında kalsın diye (5 MB kapısı bu işte YOK)
export const MAX_AUTO_POST = 1000;
// Satır notları (bank_statement_lines.note): C-26 "tek tek gözden geçir" ile bekletilen güçlü eşleşme / K3 hesap (İşletme / Fon) seçimi gereken satır.
export const NOTE_REVIEW_EACH = 'REVIEW_EACH';
export const NOTE_FUND_CHOICE = 'FUND_CHOICE_REQUIRED';
export const DESCRIPTION_MAX = 200;
export const FORMATS = Object.freeze(['xlsx', 'csv', 'mt940']);
export const PROFILE_FORMATS = Object.freeze(['xlsx', 'csv']);
export const LINE_STATUSES = Object.freeze(['unmatched', 'suggested', 'posted', 'linked', 'classified', 'ignored', 'reverted']);
export const CLASSIFY_KINDS = Object.freeze(['expense', 'bank_fee', 'transfer', 'interest', 'other_income', 'ignore']);

export const invalid = (message) => new PlatformError(400, 'INVALID_BODY', message);
export const accountNotFound = () => new PlatformError(404, 'ACCOUNT_NOT_FOUND', 'Hesap bulunamadı.');
export const importNotFound = () => new PlatformError(404, 'BANK_IMPORT_NOT_FOUND', 'Yükleme bulunamadı.');
export const lineNotFound = () => new PlatformError(404, 'BANK_LINE_NOT_FOUND', 'Banka satırı bulunamadı.');
export const fileAlreadyImported = () => new PlatformError(409, 'FILE_ALREADY_IMPORTED', 'Bu dosya bu hesaba daha önce yüklenmiş.');
export const previewStale = () => new PlatformError(409, 'BANK_PREVIEW_STALE', 'Önizlemeden sonra durum değişti; önizlemeyi yenileyin.');
export const lineNotOpen = () => new PlatformError(409, 'BANK_LINE_NOT_OPEN', 'Bu satır artık işlenmeyi beklemiyor.');
export const hasClassified = () => new PlatformError(409, 'BANK_IMPORT_HAS_CLASSIFIED', 'Sınıflanmış satırlar var; önce bunları tek tek geri alın.');
export const alreadyReverted = () => new PlatformError(409, 'BANK_IMPORT_REVERTED', 'Bu yükleme zaten geri alınmış.');

const obj = (value) => (value && typeof value === 'object' && !Array.isArray(value) ? value : {});
const isoDate = (value, label) => {
  const s = String(value ?? '');
  const d = /^\d{4}-\d{2}-\d{2}$/.test(s) ? new Date(`${s}T00:00:00Z`) : null;
  if (!d || Number.isNaN(d.getTime()) || d.toISOString().slice(0, 10) !== s) throw invalid(`${label} geçersiz.`);
  return s;
};
const optText = (value, max) => {
  if (value === undefined || value === null) return null;
  const s = String(value).replace(/[\u0000-\u001f\u007f]/g, ' ').trim();
  return s ? s.slice(0, max) : null;
};
const minorOf = (value, label) => {
  if (typeof value !== 'number' || !Number.isSafeInteger(value) || Math.abs(value) > 1_000_000_000_000) throw invalid(`${label} kuruş cinsinden tamsayı olmalıdır.`);
  return value;
};

/** preview ve commit gövdesi. */
export function parseStatementBody(body, { commit = false, todayIso }) {
  const input = obj(body);
  const accountId = Number(input.account_id);
  if (!Number.isSafeInteger(accountId) || accountId <= 0) throw invalid('Hesap seçimi geçersiz.');
  if (!FORMATS.includes(input.format)) throw invalid('Dosya biçimi geçersiz.');
  const file = obj(input.file);
  const sha = String(file.sha256 ?? '').toLowerCase();
  if (!/^[0-9a-f]{64}$/.test(sha)) throw invalid('Dosya özeti (sha256) geçersiz.');
  const rawLines = input.lines;
  if (!Array.isArray(rawLines) || rawLines.length === 0) throw invalid('Dosyada satır yok.');
  if (rawLines.length > MAX_LINES) throw invalid(`Bir yüklemede en çok ${MAX_LINES} satır olabilir; dosyayı dönemlere bölün.`);
  const lines = rawLines.map((raw, index) => {
    const l = obj(raw);
    const n = index + 1;
    const valueDate = isoDate(l.value_date, `${n}. satır tarihi`);
    if (valueDate > todayIso) throw invalid(`${n}. satırın tarihi gelecekte.`);
    const amount = minorOf(l.amount_minor, `${n}. satır tutarı`);
    if (amount === 0) throw invalid(`${n}. satırın tutarı sıfır.`);
    return {
      n,
      value_date: valueDate,
      amount_minor: amount,
      description: optText(l.description, DESCRIPTION_MAX) ?? '',
      counterparty_name: optText(l.counterparty_name, 120),
      counterparty_iban: normalizeIban(l.counterparty_iban),
      bank_reference: optText(l.bank_reference, 60),
      confidence: ['low', 'medium', 'high'].includes(l.confidence) ? l.confidence : null,
      balance_after_minor: l.balance_after_minor === undefined || l.balance_after_minor === null ? null : minorOf(l.balance_after_minor, `${n}. satır bakiyesi`),
    };
  });
  const st = obj(input.statement);
  const result = {
    accountId,
    format: input.format,
    file: { name: optText(file.name, 200) ?? 'dosya', size: Number.isSafeInteger(file.size) && file.size >= 0 ? file.size : 0, sha256: sha },
    statement: {
      from: st.from ? isoDate(st.from, 'Ekstre başlangıcı') : null,
      to: st.to ? isoDate(st.to, 'Ekstre bitişi') : null,
      accountIban: normalizeIban(st.account_iban),
    },
    lines,
  };
  if (commit) {
    const key = String(input.idempotency_key ?? '');
    if (!/^[A-Za-z0-9_-]{8,64}$/.test(key)) throw invalid('İşlem anahtarı geçersiz.');
    const hash = String(input.expected_hash ?? '');
    if (!/^[0-9a-f]{64}$/.test(hash)) throw invalid('Önizleme özeti eksik; önce önizleyin.');
    result.idempotencyKey = key;
    result.expectedHash = hash;
    // C-26: açıkça true ise güçlü eşleşmeler yüklemede OTOMATİK işlenmez, tek tek onaya bırakılır (varsayılan false: eski davranış).
    result.reviewEach = parseReviewEach(input.review_each);
  }
  return result;
}

function parseReviewEach(value) {
  if (value === undefined || value === null || value === false) return false;
  if (value === true) return true;
  throw invalid('"Tek tek gözden geçir" seçeneği geçersiz.');
}

export function parseProfileBody(body) {
  const input = obj(body);
  if (!PROFILE_FORMATS.includes(input.format)) throw invalid('Profil biçimi geçersiz.');
  const signature = optText(input.header_signature, 400);
  if (!signature) throw invalid('Başlık imzası gerekli.');
  const mapping = obj(input.mapping);
  const options = obj(input.options);
  if (JSON.stringify(mapping).length > 2000 || JSON.stringify(options).length > 2000) throw invalid('Profil çok büyük.');
  return { format: input.format, signature, mapping, options };
}
