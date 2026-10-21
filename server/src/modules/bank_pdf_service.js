// Banka PDF hesap ekstresi: metin katmanını sunucuda oku (pdf.js, worker_threads), satırlara ayrıştır (bank_pdf_parser.js). OCR YOK.
// PDF yalnız bellekte tutulur; diske yazılmaz, yanıttan sonra atılır. Aynı anda en çok 2 okuma, 30 sn süre sınırı, 80 sayfa, 5 MB.
// Sözleşme: docs/PLATFORM_FINANS_BANKA.md ("PDF ekstre").
import { Worker } from 'node:worker_threads';
import { PlatformError } from './errors.js';
import { today } from './finance_common.js';
import { PDF_MAX_LINES, parseBankPdf } from './bank_pdf_parser.js';

export const PDF_MAX_BYTES = 5 * 1024 * 1024;
const TIMEOUT_MS = 30_000;
const MAX_CONCURRENT = 2;
const MIN_TEXT_CHARS = 30; // altı: metin katmanı yok (taranmış resim) sayılır

export const SCANNED_MESSAGE = 'Bu PDF taranmış bir resim; metni okunamıyor. Bankanın Excel (xlsx) ya da CSV dökümünü yükleyin.';

const fail = (status, code, message) => new PlatformError(status, code, message);
let active = 0;

/** Bellekteki PDF -> sayfa metin ögeleri. Worker'ı süre sınırıyla çalıştırır; her durumda sonlandırır. */
export function readPdfPages(buffer) {
  const data = buffer.buffer.slice(buffer.byteOffset, buffer.byteOffset + buffer.byteLength);
  return new Promise((resolve, reject) => {
    let settled = false;
    const worker = new Worker(new URL('./bank_pdf_worker.js', import.meta.url), {
      workerData: { data },
      transferList: [data],
      resourceLimits: { maxOldGenerationSizeMb: 512 },
    });
    const finish = (fn, value) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      worker.terminate().catch(() => {});
      fn(value);
    };
    const timer = setTimeout(() => finish(reject, fail(422, 'BANK_PDF_TIMEOUT', 'PDF okunurken süre doldu. Daha kısa bir döneme ait ekstre ya da Excel/CSV dökümü yükleyin.')), TIMEOUT_MS);
    worker.once('message', (m) => {
      if (m?.ok) return finish(resolve, m.pages);
      const byCode = {
        PASSWORD: fail(422, 'BANK_PDF_ENCRYPTED', 'Bu PDF parola korumalı. Parolasız bir kopyasını ya da bankanın Excel/CSV dökümünü yükleyin.'),
        INVALID_PDF: fail(422, 'BANK_PDF_INVALID', 'Bu dosya geçerli bir PDF değil.'),
        TOO_MANY_PAGES: fail(422, 'BANK_PDF_TOO_LONG', 'PDF çok uzun (en çok 80 sayfa). Ekstreyi dönemlere bölün ya da Excel/CSV dökümü yükleyin.'),
        TOO_MANY_ITEMS: fail(422, 'BANK_PDF_TOO_LONG', 'PDF çok uzun. Ekstreyi dönemlere bölün ya da Excel/CSV dökümü yükleyin.'),
      };
      return finish(reject, byCode[m?.code] ?? fail(422, 'BANK_PDF_UNREADABLE', 'PDF okunamadı. Bankanın Excel (xlsx) ya da CSV dökümünü yükleyin.'));
    });
    worker.once('error', () => finish(reject, fail(503, 'BANK_PDF_UNAVAILABLE', 'PDF okuyucu şu anda çalışmıyor. Daha sonra tekrar deneyin ya da Excel/CSV yükleyin.')));
    worker.once('exit', () => finish(reject, fail(503, 'BANK_PDF_UNAVAILABLE', 'PDF okuyucu beklenmedik şekilde durdu. Daha sonra tekrar deneyin ya da Excel/CSV yükleyin.')));
  });
}

/** Yanıt gövdesi: Excel/CSV ayrıştırıcısının satır yapısı + güven işareti + okunamayan sayısı. */
export async function extractBankPdf(buffer, { now = new Date(), readPages = readPdfPages } = {}) {
  if (!Buffer.isBuffer(buffer) || buffer.length === 0) throw fail(400, 'INVALID_BODY', 'PDF dosyası gönderilmedi.');
  if (buffer.length > PDF_MAX_BYTES) throw fail(413, 'PAYLOAD_TOO_LARGE', 'PDF çok büyük. En çok 5 MB yüklenebilir.');
  if (!buffer.subarray(0, 1024).includes('%PDF-')) throw fail(422, 'BANK_PDF_INVALID', 'Bu dosya geçerli bir PDF değil.');
  if (active >= MAX_CONCURRENT) throw fail(429, 'BANK_PDF_BUSY', 'Şu anda başka PDF dosyaları okunuyor. Biraz sonra tekrar deneyin.');
  active += 1;
  let pages;
  try {
    pages = await readPages(buffer);
  } finally {
    active -= 1;
  }
  const parsed = parseBankPdf(pages, { todayIso: today(now) });
  if (parsed.charCount < MIN_TEXT_CHARS) throw fail(422, 'BANK_PDF_SCANNED', SCANNED_MESSAGE);
  if (parsed.lines.length === 0) {
    throw fail(422, 'BANK_PDF_NO_ROWS', 'PDF\'de okunabilen hareket satırı bulunamadı. Bankanın Excel (xlsx) ya da CSV dökümünü yükleyin.');
  }
  if (parsed.lines.length > PDF_MAX_LINES) {
    throw fail(422, 'BANK_PDF_TOO_MANY_LINES', `PDF'de ${parsed.lines.length} hareket var; bir seferde en çok ${PDF_MAX_LINES} yüklenebilir. Ekstreyi dönemlere bölün.`);
  }
  const low = parsed.lines.filter((l) => l.confidence === 'low').length;
  return {
    lines: parsed.lines,
    unreadable: parsed.unreadable,
    skipped: parsed.skipped,
    low_confidence: low,
    page_count: pages.length,
    mode: parsed.mode,
    statement: { from: parsed.statement.from, to: parsed.statement.to, account_iban: parsed.accountIban },
  };
}
