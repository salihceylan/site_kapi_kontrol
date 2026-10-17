// Belgeler (Faz 3b-A) testleri için örnek dosya üreticileri (gerçek imzalı, küçük). Bu dosya test değildir; yalnız yardımcıdır.
import zlib from 'node:zlib';

const CRC_TABLE = (() => {
  const table = new Uint32Array(256);
  for (let n = 0; n < 256; n += 1) {
    let c = n;
    for (let k = 0; k < 8; k += 1) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    table[n] = c >>> 0;
  }
  return table;
})();

export function crc32(buffer) {
  let c = 0xffffffff;
  for (const byte of buffer) c = CRC_TABLE[(c ^ byte) & 0xff] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
}

/** Geçerli (kuyruğunda %%EOF olan) küçük PDF. `extra`: nesne alanına eklenen ham metin (ör. "/Launch"). */
export function makePdf({ extra = '', eof = true, padding = 0 } = {}) {
  const body = `%PDF-1.4\n1 0 obj\n<< /Type /Catalog /Pages 2 0 R ${extra} >>\nendobj\n2 0 obj\n<< /Type /Pages /Kids [] /Count 0 >>\nendobj\ntrailer\n<< /Root 1 0 R >>\n`;
  return Buffer.concat([Buffer.from(body, 'latin1'), Buffer.alloc(padding, 0x20), Buffer.from(eof ? '%%EOF\n' : '', 'latin1')]);
}

const chunk = (type, data) => {
  const length = Buffer.alloc(4);
  length.writeUInt32BE(data.length);
  const body = Buffer.concat([Buffer.from(type, 'latin1'), data]);
  const crc = Buffer.alloc(4);
  crc.writeUInt32BE(crc32(body));
  return Buffer.concat([length, body, crc]);
};

/** 1x1 PNG (IHDR + IDAT + IEND). */
export function makePng({ trailing = Buffer.alloc(0), iend = true } = {}) {
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(1, 0);
  ihdr.writeUInt32BE(1, 4);
  ihdr[8] = 8;
  ihdr[9] = 2;
  const idat = zlib.deflateSync(Buffer.from([0, 255, 0, 0]));
  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk('IHDR', ihdr),
    chunk('IDAT', idat),
    iend ? chunk('IEND', Buffer.alloc(0)) : Buffer.alloc(0),
    trailing,
  ]);
}

export function makeJpeg(size = 64) {
  return Buffer.concat([Buffer.from([0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10]), Buffer.from('JFIF\0', 'latin1'), Buffer.alloc(size, 0x11), Buffer.from([0xff, 0xd9])]);
}

/**
 * Basit ZIP yazıcı. entries: [{ name, data, method? (0 sakla | 8 deflate), flags? }]. `comment`: EOCD yorumu. `lieEntries`: EOCD girdi sayısını yalan söyler.
 */
export function makeZip(entries, { comment = '', eocdEntries = null } = {}) {
  const locals = [];
  const centrals = [];
  let offset = 0;
  for (const entry of entries) {
    const name = Buffer.from(entry.name, 'utf8');
    const data = Buffer.isBuffer(entry.data) ? entry.data : Buffer.from(entry.data ?? '', 'utf8');
    const method = entry.method ?? 0;
    const packed = method === 8 ? zlib.deflateRawSync(data) : data;
    const flags = entry.flags ?? 0x800;
    const local = Buffer.alloc(30);
    local.writeUInt32LE(0x04034b50, 0);
    local.writeUInt16LE(20, 4);
    local.writeUInt16LE(flags, 6);
    local.writeUInt16LE(method, 8);
    local.writeUInt32LE(crc32(data), 14);
    local.writeUInt32LE(packed.length, 18);
    local.writeUInt32LE(data.length, 22);
    local.writeUInt16LE(name.length, 26);
    const localBytes = Buffer.concat([local, name, packed]);
    const central = Buffer.alloc(46);
    central.writeUInt32LE(0x02014b50, 0);
    central.writeUInt16LE(20, 4);
    central.writeUInt16LE(20, 6);
    central.writeUInt16LE(flags, 8);
    central.writeUInt16LE(method, 10);
    central.writeUInt32LE(crc32(data), 16);
    central.writeUInt32LE(packed.length, 20);
    central.writeUInt32LE(entry.declaredUncompressed ?? data.length, 24);
    central.writeUInt16LE(name.length, 28);
    central.writeUInt32LE(offset, 42);
    locals.push(localBytes);
    centrals.push(Buffer.concat([central, name]));
    offset += localBytes.length;
  }
  const directory = Buffer.concat(centrals);
  const commentBytes = Buffer.from(comment, 'latin1');
  const eocd = Buffer.alloc(22);
  eocd.writeUInt32LE(0x06054b50, 0);
  eocd.writeUInt16LE(eocdEntries ?? entries.length, 8);
  eocd.writeUInt16LE(eocdEntries ?? entries.length, 10);
  eocd.writeUInt32LE(directory.length, 12);
  eocd.writeUInt32LE(offset, 16);
  eocd.writeUInt16LE(commentBytes.length, 20);
  return Buffer.concat([...locals, directory, eocd, commentBytes]);
}

const CONTENT_TYPES = (main = 'application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml', part = '/word/document.xml') =>
  `<?xml version="1.0"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Override PartName="${part}" ContentType="${main}"/></Types>`;

export function makeDocx({ extra = [], contentTypes, method = 8 } = {}) {
  return makeZip([
    { name: '[Content_Types].xml', data: contentTypes ?? CONTENT_TYPES(), method },
    { name: 'word/document.xml', data: '<w:document/>' },
    ...extra,
  ]);
}

export function makeXlsx({ extra = [], contentTypes, method = 8 } = {}) {
  return makeZip([
    { name: '[Content_Types].xml', data: contentTypes ?? CONTENT_TYPES('application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml', '/xl/workbook.xml') },
    { name: 'xl/workbook.xml', data: '<workbook/>', method },
    ...extra,
  ]);
}

export const MACRO_CONTENT_TYPES = CONTENT_TYPES('application/vnd.ms-word.document.macroEnabled.main+xml');

/** Eski OLE (doc/xls/ppt) imzası. */
export const OLE_BYTES = Buffer.concat([Buffer.from([0xd0, 0xcf, 0x11, 0xe0, 0xa1, 0xb1, 0x1a, 0xe1]), Buffer.alloc(512)]);
/** Windows çalıştırılabilir (MZ) başlığı. */
export const EXE_BYTES = Buffer.concat([Buffer.from('MZ', 'latin1'), Buffer.alloc(200, 0x90)]);
