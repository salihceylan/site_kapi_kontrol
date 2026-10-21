// Banka PDF ucu: kodla üretilmiş küçük PDF'ler pdf.js worker'ı üzerinden okunur (OCR yok). Gerçek banka PDF örneği yoktur.
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { PDF_MAX_BYTES, SCANNED_MESSAGE, extractBankPdf } from '../src/modules/bank_pdf_service.js';

/** En küçük geçerli PDF: sayfa başına metin parçaları [{ x, y, text, size }] (Helvetica, WinAnsi). Metin katmanı olmayan sayfa için boş dizi. */
function buildPdf(pages) {
  const objects = [];
  const add = (body) => objects.push(body);
  add('<< /Type /Catalog /Pages 2 0 R >>');
  add(`<< /Type /Pages /Kids [${pages.map((_, i) => `${4 + i * 2} 0 R`).join(' ')}] /Count ${pages.length} >>`);
  add('<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>');
  pages.forEach((texts, i) => {
    add(`<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Resources << /Font << /F1 3 0 R >> >> /Contents ${5 + i * 2} 0 R >>`);
    const stream = texts.map((t) => `BT /F1 ${t.size ?? 9} Tf ${t.x} ${t.y} Td (${t.text.replace(/[\\()]/g, '\\$&')}) Tj ET`).join('\n');
    add({ stream });
  });
  const chunks = [Buffer.from('%PDF-1.4\n', 'latin1')];
  const offsets = [];
  let pos = chunks[0].length;
  objects.forEach((o, i) => {
    offsets.push(pos);
    const text = typeof o === 'string' ? `${i + 1} 0 obj\n${o}\nendobj\n` : `${i + 1} 0 obj\n<< /Length ${Buffer.byteLength(o.stream, 'latin1')} >>\nstream\n${o.stream}\nendstream\nendobj\n`;
    const buf = Buffer.from(text, 'latin1');
    chunks.push(buf);
    pos += buf.length;
  });
  const xref = [`xref\n0 ${objects.length + 1}\n0000000000 65535 f \n`, ...offsets.map((o) => `${String(o).padStart(10, '0')} 00000 n \n`), `trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\nstartxref\n${pos}\n%%EOF\n`].join('');
  chunks.push(Buffer.from(xref, 'latin1'));
  return Buffer.concat(chunks);
}

const T = (x, y, text) => ({ x, y, text });
const statement = () => [
  [
    T(50, 800, 'HESAP EKSTRESI'),
    T(50, 780, 'IBAN: TR33 0006 1005 1978 6457 8413 26'),
    T(50, 740, 'Tarih'), T(130, 740, 'Aciklama'), T(380, 740, 'Borc'), T(440, 740, 'Alacak'), T(500, 740, 'Bakiye'),
    T(50, 720, '01.10.2026'), T(130, 720, 'Devir'), T(500, 720, '10.000,00'),
    T(50, 705, '05.10.2026'), T(130, 705, 'Gelen FAST A blok 5 Ahmet Yilmaz'), T(440, 705, '1.500,00'), T(500, 705, '11.500,00'),
    T(130, 694, 'ekim aidati'),
    T(50, 678, '07.10.2026'), T(130, 678, 'Elektrik faturasi'), T(380, 678, '250,50'), T(500, 678, '11.249,50'),
  ],
];

describe('extractBankPdf (gerçek pdf.js worker)', () => {
  it('kodla üretilmiş ekstreyi satırlara çevirir', async () => {
    const out = await extractBankPdf(buildPdf(statement()), { now: new Date('2026-10-21T10:00:00Z') });
    assert.equal(out.mode, 'header');
    assert.equal(out.page_count, 1);
    assert.equal(out.unreadable, 0);
    assert.deepEqual(out.lines.map((l) => [l.value_date, l.amount_minor, l.balance_after_minor, l.confidence]), [
      ['2026-10-05', 150000, 1150000, 'high'],
      ['2026-10-07', -25050, 1124950, 'high'],
    ]);
    assert.equal(out.lines[0].description, 'Gelen FAST A blok 5 Ahmet Yilmaz ekim aidati');
    assert.deepEqual(out.statement, { from: '2026-10-05', to: '2026-10-07', account_iban: 'TR330006100519786457841326' });
    // Excel/CSV satır yapısıyla aynı alanlar
    assert.deepEqual(Object.keys(out.lines[0]).sort(), ['amount_minor', 'balance_after_minor', 'bank_reference', 'confidence', 'counterparty_iban', 'counterparty_name', 'description', 'n', 'value_date']);
  });

  it('çok sayfalı PDF: bakiye zinciri sayfalar arasında sürer', async () => {
    const p1 = statement()[0];
    const p2 = [T(50, 700, '10.10.2026'), T(130, 700, 'EFT Gelen D12 kasim'), T(440, 700, '800,00'), T(500, 700, '12.049,50')];
    const out = await extractBankPdf(buildPdf([p1, p2]), { now: new Date('2026-10-21T10:00:00Z') });
    assert.equal(out.page_count, 2);
    assert.deepEqual(out.lines.map((l) => l.amount_minor), [150000, -25050, 80000]);
  });

  it('metin katmanı yok (taranmış resim gibi boş sayfa) -> 422 ve Türkçe ileti', async () => {
    await assert.rejects(extractBankPdf(buildPdf([[]])), (e) => e.statusCode === 422 && e.code === 'BANK_PDF_SCANNED' && e.message === SCANNED_MESSAGE);
    assert.equal(SCANNED_MESSAGE, 'Bu PDF taranmış bir resim; metni okunamıyor. Bankanın Excel (xlsx) ya da CSV dökümünü yükleyin.');
  });

  it('metin var ama hareket tablosu yok -> 422 BANK_PDF_NO_ROWS', async () => {
    const pdf = buildPdf([[T(50, 800, 'Bu bir ekstre degil, yalnizca duz bir metin sayfasidir ve tablo icermez.')]]);
    await assert.rejects(extractBankPdf(pdf), (e) => e.statusCode === 422 && e.code === 'BANK_PDF_NO_ROWS');
  });

  it('PDF olmayan dosya, bozuk PDF, boş gövde, büyük gövde', async () => {
    await assert.rejects(extractBankPdf(Buffer.from('MZ not a pdf')), (e) => e.code === 'BANK_PDF_INVALID');
    await assert.rejects(extractBankPdf(Buffer.from('%PDF-1.4\nbozuk icerik')), (e) => e.statusCode === 422 && /^BANK_PDF_/.test(e.code));
    await assert.rejects(extractBankPdf(Buffer.alloc(0)), (e) => e.statusCode === 400);
    await assert.rejects(extractBankPdf(Buffer.alloc(PDF_MAX_BYTES + 1)), (e) => e.statusCode === 413);
  });

  it('aynı anda en çok 2 okuma; fazlası 429', async () => {
    const gate = [];
    const slow = () => new Promise((resolve) => gate.push(resolve));
    const pdf = buildPdf(statement());
    const a = extractBankPdf(pdf, { readPages: slow });
    const b = extractBankPdf(pdf, { readPages: slow });
    await assert.rejects(extractBankPdf(pdf, { readPages: slow }), (e) => e.statusCode === 429 && e.code === 'BANK_PDF_BUSY');
    gate.forEach((release) => release([{ items: [] }]));
    await Promise.allSettled([a, b]);
    const after = await extractBankPdf(pdf, { now: new Date('2026-10-21T10:00:00Z') });
    assert.equal(after.lines.length, 2);
  });
});

describe('pdf-extract ucu bağlantısı (kaynak denetimi)', () => {
  const src = readFileSync(new URL('../src/modules/bank_import_routes.js', import.meta.url), 'utf8');
  it('gövde yalnız kimlik + hız sınırı + yetki denetiminden sonra okunur; diske yazılmaz', () => {
    const line = src.split('\n').find((l) => l.includes('/bank-imports/pdf-extract'));
    assert.ok(line);
    const order = ['authRequired', 'bankPdfLimiter', 'bankPdfGate', 'bankPdfBodyStep'].map((n) => line.indexOf(n));
    assert.ok(order.every((v, i) => v > 0 && (i === 0 || v > order[i - 1])), line);
    assert.ok(src.includes('resolveFinanceAccess(req, res, { write: true })'));
    assert.ok(src.includes('PDF_MAX_BYTES'));
    const svc = readFileSync(new URL('../src/modules/bank_pdf_service.js', import.meta.url), 'utf8') + readFileSync(new URL('../src/modules/bank_pdf_worker.js', import.meta.url), 'utf8');
    assert.ok(!/node:fs|writeFile|createWriteStream|tmpdir/.test(svc), 'PDF diske yazılmamalı');
  });
});
