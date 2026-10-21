// Bagimsiz, kucuk PDF uretici (yalniz metin; A4; Helvetica + Turkce harf glifleri). Demo belgeler icindir.
// Turkce: Helvetica glif kumesinde Gbreve/gbreve/Idotaccent/dotlessi/Scedilla/scedilla vardir; 0x80-0x85 kodlarina atanir.

const SPECIAL = { Ğ: 0x80, ğ: 0x81, İ: 0x82, ı: 0x83, Ş: 0x84, ş: 0x85 };

function toBytes(text) {
  const out = [];
  for (const ch of String(text)) {
    if (SPECIAL[ch] !== undefined) out.push(SPECIAL[ch]);
    else {
      const code = ch.codePointAt(0);
      // ASCII + Latin-1 (ç ö ü Ç Ö Ü â vb.) ; digerleri '?'
      if (code < 0x100 && code >= 0x20) out.push(code);
      else if (ch === '\n' || ch === '\t') out.push(0x20);
      else out.push(0x3f);
    }
  }
  return out;
}

function escapeBytes(bytes) {
  let s = '';
  for (const b of bytes) {
    const c = String.fromCharCode(b);
    if (c === '(' || c === ')' || c === '\\') s += `\\${c}`;
    else s += c;
  }
  return s;
}

/** Kaba genislik olcusu (Helvetica ortalama ~0.52 em) ile satir kirma. */
export function wrapText(text, maxChars) {
  const words = String(text).split(/\s+/).filter(Boolean);
  const lines = [];
  let line = '';
  for (const w of words) {
    if ((line + ' ' + w).trim().length > maxChars) {
      if (line) lines.push(line);
      line = w;
    } else {
      line = (line + ' ' + w).trim();
    }
  }
  if (line) lines.push(line);
  return lines.length ? lines : [''];
}

/**
 * blocks: [{ text, size?, bold?, gapBefore?, indent? }] ; basliklar icin size buyuk.
 * Dondurur: Buffer (gecerli PDF).
 */
export function buildPdf({ blocks, footer = 'Demo veri - sahte belge' }) {
  const W = 595.28;
  const H = 841.89;
  const margin = 56;
  const usable = W - margin * 2;
  const pages = [];
  let current = [];
  let y = H - margin;
  const newPage = () => {
    pages.push(current);
    current = [];
    y = H - margin;
  };
  for (const block of blocks) {
    const size = block.size ?? 11;
    const lead = size * 1.45;
    const indent = block.indent ?? 0;
    const maxChars = Math.floor((usable - indent) / (size * 0.53));
    const lines = block.raw ? [block.text] : wrapText(block.text, maxChars);
    y -= block.gapBefore ?? 0;
    for (const line of lines) {
      if (y - lead < margin + 20) newPage();
      y -= lead;
      current.push({ x: margin + indent, y, size, bold: block.bold === true, text: line });
    }
  }
  pages.push(current);

  const objects = [];
  const add = (body) => {
    objects.push(body);
    return objects.length;
  };
  const catalogId = add('');
  const pagesId = add('');
  const encodingId = add('<< /Type /Encoding /BaseEncoding /WinAnsiEncoding /Differences [128 /Gbreve /gbreve /Idotaccent /dotlessi /Scedilla /scedilla] >>');
  const fontRegularId = add(`<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding ${encodingId} 0 R >>`);
  const fontBoldId = add(`<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold /Encoding ${encodingId} 0 R >>`);
  const pageIds = [];
  pages.forEach((items, pageIndex) => {
    const parts = [];
    for (const item of items) {
      parts.push(`BT /${item.bold ? 'F2' : 'F1'} ${item.size} Tf ${item.x.toFixed(2)} ${item.y.toFixed(2)} Td (${escapeBytes(toBytes(item.text))}) Tj ET`);
    }
    parts.push(`BT /F1 8 Tf ${margin} 30 Td (${escapeBytes(toBytes(`${footer} - sayfa ${pageIndex + 1}/${pages.length}`))}) Tj ET`);
    const stream = parts.join('\n');
    const contentId = add(`<< /Length ${stream.length} >>\nstream\n${stream}\nendstream`);
    const pageId = add(
      `<< /Type /Page /Parent ${pagesId} 0 R /MediaBox [0 0 ${W} ${H}] /Resources << /Font << /F1 ${fontRegularId} 0 R /F2 ${fontBoldId} 0 R >> >> /Contents ${contentId} 0 R >>`,
    );
    pageIds.push(pageId);
  });
  objects[catalogId - 1] = `<< /Type /Catalog /Pages ${pagesId} 0 R >>`;
  objects[pagesId - 1] = `<< /Type /Pages /Kids [${pageIds.map((id) => `${id} 0 R`).join(' ')}] /Count ${pageIds.length} >>`;

  let pdf = '%PDF-1.4\n';
  const offsets = [];
  objects.forEach((body, i) => {
    offsets.push(pdf.length);
    pdf += `${i + 1} 0 obj\n${body}\nendobj\n`;
  });
  const xref = pdf.length;
  pdf += `xref\n0 ${objects.length + 1}\n0000000000 65535 f \n`;
  for (const off of offsets) pdf += `${String(off).padStart(10, '0')} 00000 n \n`;
  pdf += `trailer\n<< /Size ${objects.length + 1} /Root ${catalogId} 0 R >>\nstartxref\n${xref}\n%%EOF\n`;
  return Buffer.from(pdf, 'latin1');
}
