// Banka PDF metin okuyucu (worker_threads içinde çalışır; bank_pdf_service.js başlatır). PDF yalnız bellekte okunur, diske yazılmaz.
// pdf.js (Mozilla, Apache-2.0) legacy yapısı Node'da kullanılır; yalnız METİN ögeleri çıkarılır (görüntü işleme ve OCR yok).
// Ayrı iş parçacığı: bozuk/çok büyük bir PDF olay döngüsünü kilitlemez; süre aşımında ana taraf worker'ı sonlandırır.
import { isMainThread, parentPort, workerData } from 'node:worker_threads';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const MAX_PAGES = 80;
const MAX_ITEMS = 200_000;

function failureCode(error) {
  const name = String(error?.name ?? '');
  if (name === 'PasswordException') return 'PASSWORD';
  if (error?.code === 'TOO_MANY_ITEMS') return 'TOO_MANY_ITEMS';
  if (name === 'InvalidPDFException' || name === 'FormatError' || name === 'MissingPDFException') return 'INVALID_PDF';
  return 'READ_FAILED';
}

/** pdf.js içe aktarılırken isteğe bağlı görselleştirme paketi (@napi-rs/canvas) yok uyarısı basar; metin okumada gerekmez, günlük kirlenmesin. */
async function loadPdfjs() {
  const { log, warn } = console;
  console.log = () => {};
  console.warn = () => {};
  try {
    return await import('pdfjs-dist/legacy/build/pdf.mjs');
  } finally {
    console.log = log;
    console.warn = warn;
  }
}

async function extract(data) {
  const pdfjs = await loadPdfjs();
  const root = path.dirname(fileURLToPath(import.meta.resolve('pdfjs-dist/package.json'))).split(path.sep).join('/');
  const doc = await pdfjs.getDocument({
    data: new Uint8Array(data),
    cMapUrl: `${root}/cmaps/`,
    cMapPacked: true,
    standardFontDataUrl: `${root}/standard_fonts/`,
    useSystemFonts: false,
    disableFontFace: true,
    isEvalSupported: false,
    verbosity: 0,
  }).promise;
  if (doc.numPages > MAX_PAGES) return { ok: false, code: 'TOO_MANY_PAGES', pages: doc.numPages };
  const pages = [];
  let total = 0;
  for (let p = 1; p <= doc.numPages; p += 1) {
    const page = await doc.getPage(p);
    const content = await page.getTextContent();
    const items = [];
    for (const it of content.items) {
      if (typeof it.str !== 'string' || it.str === '') continue;
      items.push({ str: it.str, x: it.transform[4], y: it.transform[5], w: it.width, h: it.height || Math.abs(it.transform[3]) });
    }
    total += items.length;
    if (total > MAX_ITEMS) throw Object.assign(new Error('çok fazla metin ögesi'), { code: 'TOO_MANY_ITEMS' });
    pages.push({ number: p, items });
  }
  return { ok: true, pages };
}

// Ana iş parçacığında (ör. import smoke testi) dosya yalnız yüklenir, hiçbir şey çalıştırmaz.
if (!isMainThread && parentPort) {
  try {
    parentPort.postMessage(await extract(workerData.data));
  } catch (error) {
    parentPort.postMessage({ ok: false, code: failureCode(error) });
  }
}
