// Adli bilgi dokumu (CSV / PDF) olusturucular. Sozlesme: docs/PLATFORM_ADLI_KAYIT.md. Saf islevler: veritabani ve ag YOK.
//
//  - CSV: UTF-8 BOM + noktali virgul (Excel TR). Hucre basinda = + - @ TAB CR olan metne kesme isareti eklenir (CSV formul enjeksiyonu).
//  - PDF: bagimlilik YOK; standart Helvetica, Turkce harfler (Ğ ğ Ş ş İ ı) /Differences ile eslenir. Yalniz metin; sayfa bolme otomatik.
// Dokumde iletisim bilgisi (telefon, e-posta, TCKN) YOKTUR; yalniz kayit alanlari.

const PDF_ENCODE = new Map([
  ['Ğ', 0xd0],
  ['ğ', 0xf0],
  ['Ş', 0xde],
  ['ş', 0xfe],
  ['İ', 0xdd],
  ['ı', 0xfd],
]);

/** CSV hucresi: formul onekleri etkisizlestirilir, ayirici / tirnak / satir sonu varsa tirnaklanir. */
export function csvCell(value) {
  let text = value === null || value === undefined ? '' : String(value);
  if (/^[=+\-@\t\r]/.test(text)) {
    text = `'${text}`;
  }
  return /[;"\r\n]/.test(text) ? `"${text.replace(/"/g, '""')}"` : text;
}

/** @param {{ meta: [string, string][], columns: string[], rows: string[][] }} doc */
export function renderCsv(doc) {
  const lines = [];
  for (const [key, value] of doc.meta) {
    lines.push([csvCell(key), csvCell(value)].join(';'));
  }
  lines.push('');
  lines.push(doc.columns.map(csvCell).join(';'));
  for (const row of doc.rows) {
    lines.push(row.map(csvCell).join(';'));
  }
  return Buffer.concat([Buffer.from([0xef, 0xbb, 0xbf]), Buffer.from(`${lines.join('\r\n')}\r\n`, 'utf8')]);
}

function pdfBytes(text) {
  const bytes = [];
  for (const char of text) {
    const mapped = PDF_ENCODE.get(char);
    if (mapped !== undefined) {
      bytes.push(mapped);
      continue;
    }
    const code = char.codePointAt(0);
    // Latin-1 (WinAnsi ile ayni konumlar: ç Ç ö Ö ü Ü dahil); kalani '?'. Kontrol karakterleri bosluk.
    bytes.push(code >= 0x20 && code <= 0xff && !(code >= 0x7f && code <= 0x9f) ? code : code < 0x20 ? 0x20 : 0x3f);
  }
  return Buffer.from(bytes);
}

function pdfEscape(buffer) {
  const out = [];
  for (const byte of buffer) {
    if (byte === 0x28 || byte === 0x29 || byte === 0x5c) out.push(0x5c);
    out.push(byte);
  }
  return Buffer.from(out);
}

function wrapLine(text, width) {
  const words = String(text).split(/\s+/).filter(Boolean);
  const lines = [];
  let current = '';
  for (const word of words) {
    if (current && `${current} ${word}`.length > width) {
      lines.push(current);
      current = word;
    } else {
      current = current ? `${current} ${word}` : word;
    }
  }
  if (current) lines.push(current);
  return lines.length > 0 ? lines : [''];
}

/** @param {{ title: string, meta: [string, string][], columns: string[], rows: string[][], footer?: string }} doc */
export function renderPdf(doc) {
  const WIDTH = 108;
  const LINES_PER_PAGE = 62;
  const lines = [{ text: doc.title, size: 14 }, { text: '', size: 9 }];
  for (const [key, value] of doc.meta) {
    for (const [index, part] of wrapLine(`${key}: ${value}`, WIDTH).entries()) {
      lines.push({ text: index === 0 ? part : `    ${part}`, size: 9 });
    }
  }
  lines.push({ text: '', size: 9 });
  doc.rows.forEach((row, index) => {
    const head = `${index + 1}. ${row[0]}  |  ${row[1]}`;
    for (const [i, part] of wrapLine(head, WIDTH).entries()) lines.push({ text: i === 0 ? part : `    ${part}`, size: 9, bold: i === 0 });
    const detail = doc.columns
      .slice(2)
      .map((column, i) => (row[i + 2] ? `${column}: ${row[i + 2]}` : ''))
      .filter(Boolean)
      .join('; ');
    for (const part of wrapLine(detail, WIDTH - 4)) lines.push({ text: `    ${part}`, size: 9 });
  });
  if (doc.footer) {
    lines.push({ text: '', size: 9 });
    for (const part of wrapLine(doc.footer, WIDTH)) lines.push({ text: part, size: 8 });
  }

  const pages = [];
  for (let i = 0; i < lines.length; i += LINES_PER_PAGE) pages.push(lines.slice(i, i + LINES_PER_PAGE));
  if (pages.length === 0) pages.push([]);

  const objects = [];
  const add = (body) => {
    objects.push(body);
    return objects.length;
  };
  const catalogId = add(null);
  const pagesId = add(null);
  const regularId = add(Buffer.from('<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding 5 0 R >>'));
  const boldId = add(Buffer.from('<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold /Encoding 5 0 R >>'));
  add(
    Buffer.from(
      '<< /Type /Encoding /BaseEncoding /WinAnsiEncoding /Differences [208 /Gbreve 240 /gbreve 222 /Scedilla 254 /scedilla 221 /Idotaccent 253 /dotlessi] >>',
    ),
  );
  const pageIds = [];
  for (const page of pages) {
    const parts = [Buffer.from('BT\n')];
    let y = 800;
    for (const line of page) {
      parts.push(Buffer.from(`/${line.bold ? 'F2' : 'F1'} ${line.size} Tf 1 0 0 1 40 ${y} Tm (`));
      parts.push(pdfEscape(pdfBytes(line.text)));
      parts.push(Buffer.from(') Tj\n'));
      y -= line.size > 9 ? 18 : 12;
    }
    parts.push(Buffer.from('ET'));
    const content = Buffer.concat(parts);
    const contentId = add(Buffer.concat([Buffer.from(`<< /Length ${content.length} >>\nstream\n`), content, Buffer.from('\nendstream')]));
    pageIds.push(
      add(
        Buffer.from(
          `<< /Type /Page /Parent ${pagesId} 0 R /MediaBox [0 0 595 842] /Resources << /Font << /F1 ${regularId} 0 R /F2 ${boldId} 0 R >> >> /Contents ${contentId} 0 R >>`,
        ),
      ),
    );
  }
  objects[catalogId - 1] = Buffer.from(`<< /Type /Catalog /Pages ${pagesId} 0 R >>`);
  objects[pagesId - 1] = Buffer.from(`<< /Type /Pages /Count ${pageIds.length} /Kids [${pageIds.map((id) => `${id} 0 R`).join(' ')}] >>`);

  const chunks = [Buffer.from('%PDF-1.4\n')];
  const offsets = [];
  let length = chunks[0].length;
  objects.forEach((body, index) => {
    offsets.push(length);
    const chunk = Buffer.concat([Buffer.from(`${index + 1} 0 obj\n`), body, Buffer.from('\nendobj\n')]);
    chunks.push(chunk);
    length += chunk.length;
  });
  const xref = [`xref\n0 ${objects.length + 1}\n0000000000 65535 f \n`];
  for (const offset of offsets) xref.push(`${String(offset).padStart(10, '0')} 00000 n \n`);
  chunks.push(Buffer.from(`${xref.join('')}trailer\n<< /Size ${objects.length + 1} /Root ${catalogId} 0 R >>\nstartxref\n${length}\n%%EOF\n`));
  return Buffer.concat(chunks);
}
