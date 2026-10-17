// Belgeler (Faz 3b-A): dosya türü / içerik doğrulaması ve dosya adı temizliği.
//
// Sözleşme: docs/PLATFORM_BELGELER.md A4. Tür kararı İÇERİK İMZASIYLA verilir; istemcinin bildirdiği Content-Type ve uzantı hiçbir güvenlik kararına girmez
// (uzantı yalnız imzayla UYUŞMASI gereken bir ipucudur). Dosya sunucuda ASLA çalıştırılmaz / ayrıştırılmaz: ZIP (DOCX/XLSX) AÇILMAZ, yalnız merkez dizini
// okunur (en çok 1 MiB); yalnız `[Content_Types].xml` ve `*.rels` girdileri SINIRLI çıktıyla şişirilir (makro / OLE / ActiveX içerik türü ve uzak şablon / dış nesne bağı denetimi). PDF'te etkin içerik taraması EN İYİ ÇABADIR (sıkıştırılmış nesne akışı ve şifreli içerik içindeki adları görmez); güvenlik sınırı DEĞİLDİR
// (bkz. sözleşme K3).

import zlib from 'node:zlib';
import {
  DISPLAY_NAME_MAX,
  INVISIBLE_RE,
  activeContent,
  contentMismatch,
  typeNotAllowed,
} from './document_common.js';

const DOCX_MIME = 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
const XLSX_MIME = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';

/** Kanonik tür tablosu: DB'ye yazılan MIME ve uzantı BU tablodan gelir (istemciden asla). */
export const KIND_INFO = Object.freeze({
  pdf: Object.freeze({ ext: 'pdf', mime: 'application/pdf', office: false }),
  jpg: Object.freeze({ ext: 'jpg', mime: 'image/jpeg', office: false }),
  png: Object.freeze({ ext: 'png', mime: 'image/png', office: false }),
  docx: Object.freeze({ ext: 'docx', mime: DOCX_MIME, office: true }),
  xlsx: Object.freeze({ ext: 'xlsx', mime: XLSX_MIME, office: true }),
});

export const ALLOWED_MIMES = Object.freeze(Object.values(KIND_INFO).map((info) => info.mime));

const EXTENSION_KINDS = new Map([
  ['pdf', 'pdf'],
  ['jpg', 'jpg'],
  ['jpeg', 'jpg'],
  ['jpe', 'jpg'],
  ['png', 'png'],
  ['docx', 'docx'],
  ['xlsx', 'xlsx'],
]);

/** Uzantı (küçük harf, noktasız) -> tür kodu ya da null. */
export function kindForExtension(ext) {
  return EXTENSION_KINDS.get(String(ext ?? '').toLowerCase()) ?? null;
}

export function kindForMime(mime) {
  const value = String(mime ?? '').toLowerCase();
  for (const [kind, info] of Object.entries(KIND_INFO)) {
    if (info.mime === value) return kind;
  }
  return null;
}

const officeAllowed = (kind, limits) => !KIND_INFO[kind].office || limits.allowOffice !== false;

// --- Dosya adı ---------------------------------------------------------------------------------------------------

const LINE_BREAKS_RE = new RegExp('[' + String.fromCharCode(9, 10, 13) + String.fromCodePoint(0x2028) + String.fromCodePoint(0x2029) + ']', 'g');
const RESERVED_NAMES = /^(con|prn|aux|nul|com[1-9]|lpt[1-9])$/i;
const BASE_MAX = 100;

/**
 * Görünen ad temizliği (yola ASLA girmez). Sıra: NFC -> görünmez/kontrol/yön karakterleri atılır -> `/` ve `\` ile bölünür, SON parça -> `< > : " | ? *` `_`
 * -> boşluklar tekleştirilir, baş/son boşluk ve son noktalar atılır -> son uzantı ayrılır (doğrulama için), kalan adın TÜM noktaları `_` (çift uzantı) ->
 * Windows ayrılmış adları `_` öneki -> 100 kod noktası -> boşsa `belge`.
 * @returns {{ base: string, ext: string }} ext: bildirilen uzantı (küçük harf, noktasız) ya da ''
 */
export function sanitizeFileName(raw) {
  // sekme / satır sonu boşluğa çevrilir (sözcükler yapışmasın); sonra görünmez ve kontrol karakterleri atılır
  let text = String(raw ?? '').normalize('NFC').replace(LINE_BREAKS_RE, ' ').replace(INVISIBLE_RE, '');
  const parts = text.split(/[\\/]+/);
  text = parts[parts.length - 1] ?? '';
  text = text.replace(/[<>:"|?*]/g, '_').replace(/\s+/gu, ' ').trim().replace(/[. ]+$/u, '');
  let ext = '';
  const dot = text.lastIndexOf('.');
  if (dot >= 0) {
    const candidate = text.slice(dot + 1);
    if (/^[A-Za-z0-9]{1,10}$/.test(candidate)) {
      ext = candidate.toLowerCase();
      text = text.slice(0, dot);
    }
  }
  let base = text.replace(/\./g, '_').replace(/\s+/gu, ' ').trim().replace(/[. ]+$/u, '');
  if (RESERVED_NAMES.test(base)) {
    base = `_${base}`;
  }
  base = Array.from(base).slice(0, BASE_MAX).join('').trim();
  if (base === '') {
    base = 'belge';
  }
  return { base, ext };
}

/** Görünen ad = taban + `.` + KANONİK uzantı (taban en çok 100 kod noktası: toplam 120'yi aşmaz). */
export function buildDisplayName(base, ext) {
  const name = ext ? `${base}.${ext}` : base;
  return Array.from(name).length > DISPLAY_NAME_MAX ? Array.from(name).slice(0, DISPLAY_NAME_MAX).join('') : name;
}

/**
 * Yükleme bildirimini sınıflar (içerik henüz yok).
 *  - Uzantı VARSA: izin listesinde olmalı (`rapor.exe` içerik ne olursa olsun 415 DOCUMENT_TYPE_NOT_ALLOWED).
 *  - Uzantı YOKSA: ad kabul edilir; geçici tür bildirilen Content-Type'tan (izinliyse) yoksa PDF yer tutucusudur ve tamamlanınca TANINAN tür yazılır.
 * @returns {{ base: string, kind: string, declared: boolean, displayName: string, mimeType: string }}
 */
export function classifyDeclaredFile({ name, contentType }, limits) {
  const { base, ext } = sanitizeFileName(name);
  if (ext) {
    const kind = kindForExtension(ext);
    if (kind === null || !officeAllowed(kind, limits)) {
      throw typeNotAllowed();
    }
    return { base, kind, declared: true, displayName: buildDisplayName(base, KIND_INFO[kind].ext), mimeType: KIND_INFO[kind].mime };
  }
  let kind = kindForMime(contentType);
  if (kind === null || !officeAllowed(kind, limits)) {
    kind = 'pdf';
  }
  return { base, kind, declared: false, displayName: buildDisplayName(base, ''), mimeType: KIND_INFO[kind].mime };
}

// --- İmza tanıma -------------------------------------------------------------------------------------------------

const PNG_SIGNATURE = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);

/**
 * İlk baytlardan ham tür: 'pdf' | 'jpg' | 'png' | 'zip' | null. (ZIP, DOCX/XLSX olup olmadığı merkez dizin incelemesiyle kesinleşir.)
 * Eski OLE (D0 CF 11 E0), MZ, RAR, 7z, HTML/SVG/XML, düz metin ... hepsi null.
 */
export function detectRawKind(head) {
  if (!Buffer.isBuffer(head)) return null;
  if (head.length >= 5 && head.latin1Slice(0, 5) === '%PDF-') return 'pdf';
  if (head.length >= 3 && head[0] === 0xff && head[1] === 0xd8 && head[2] === 0xff) return 'jpg';
  if (head.length >= 8 && head.subarray(0, 8).equals(PNG_SIGNATURE)) return 'png';
  if (head.length >= 4 && head[0] === 0x50 && head[1] === 0x4b && head[2] === 0x03 && head[3] === 0x04) return 'zip';
  return null;
}

/**
 * Akış sırasında ERKEN karar (ilk baytlar geldiğinde): tanınmayan / izinsiz -> 415 DOCUMENT_TYPE_NOT_ALLOWED; bildirilen türle uyuşmayan ->
 * 415 DOCUMENT_CONTENT_MISMATCH. `declared` false ise (adda uzantı yoktu) tür uyuşması aranmaz.
 */
export function assertHeadAcceptable(head, { expectedKind, declared }, limits) {
  const raw = detectRawKind(head);
  if (raw === null) {
    throw typeNotAllowed();
  }
  if (raw === 'zip') {
    if (limits.allowOffice === false) throw typeNotAllowed();
    if (declared && !KIND_INFO[expectedKind].office) throw contentMismatch();
    return raw;
  }
  if (declared && raw !== expectedKind) {
    throw contentMismatch();
  }
  return raw;
}

// --- Dosya içi denetimler (diskteki geçici dosya üzerinde) ---------------------------------------------------------

async function readAt(handle, position, length) {
  const buffer = Buffer.alloc(length);
  let total = 0;
  while (total < length) {
    const { bytesRead } = await handle.read(buffer, total, length - total, position + total);
    if (bytesRead === 0) break;
    total += bytesRead;
  }
  return total === length ? buffer : buffer.subarray(0, total);
}

// PDF etkin içerik adları (ham baytlarda, `#xx` ad kaçışları çözülerek): /Launch /JavaScript /JS (betik), /EmbeddedFile(s) /EF (gömülü dosya), /GoToE /GoToR (gömülü/uzak
// belgeye atlama), /RichMedia (Flash/3B), /XFA (betikli form), /SubmitForm /ImportData (form verisi gönderme/alma).
// `/URI` BİLEREK reddedilmez: Word/LibreOffice dışa aktarımındaki sıradan web/e-posta bağlantılarıdır (sözleşme A4 de listelemiyor); yalnız bir bağlantıyı açar, betik ya da dosya
// çalıştırmaz ve işletim sistemi/PDF görüntüleyici dış bağlantıyı açmadan önce sorar. Reddetmek meşru belgelerin büyük kısmını engellerdi.
// SINIR (K3): süzgeç YALNIZ ham baytlara bakar. Sıkıştırılmış nesne akışı (/ObjStm, PDF 1.5+) ve şifreli içerik içindeki sözlükleri GÖRMEZ; bu nedenle süzgeç bir
// GÜVENLİK SINIRI DEĞİL, EN İYİ ÇABA azaltımdır (asıl azaltımlar: dar tür izin listesi, yalnız doğrulanmış yönetici yükler, HEP attachment + nosniff + sandbox CSP, dosya sunucuda açılmaz).
const PDF_FORBIDDEN = /\/(?:Launch|JavaScript|JS|EmbeddedFiles?|EF|GoToE|GoToR|RichMedia|XFA|SubmitForm|ImportData)(?![A-Za-z0-9_])/;
const PDF_SCAN_CHUNK = 1 << 20;
const PDF_SCAN_OVERLAP = 64;

/** Ham PDF baytlarında etkin içerik adları (`#xx` ad kaçışları çözülerek). Parça sınırında kaçırmamak için 64 bayt örtüşme. EN İYİ ÇABA. */
export async function pdfHasActiveContent(handle, size) {
  const buffer = Buffer.allocUnsafe(PDF_SCAN_CHUNK + PDF_SCAN_OVERLAP);
  let position = 0;
  let carry = 0;
  while (position < size) {
    const want = Math.min(PDF_SCAN_CHUNK, size - position);
    const { bytesRead } = await handle.read(buffer, carry, want, position);
    if (bytesRead === 0) break;
    const filled = carry + bytesRead;
    const text = buffer.latin1Slice(0, filled).replace(/#([0-9A-Fa-f]{2})/g, (_match, hex) => String.fromCharCode(parseInt(hex, 16)));
    if (PDF_FORBIDDEN.test(text)) return true;
    carry = Math.min(PDF_SCAN_OVERLAP, filled);
    buffer.copy(buffer, 0, filled - carry, filled);
    position += bytesRead;
  }
  return false;
}

const EOCD_SIGNATURE = 0x06054b50;
const CENTRAL_SIGNATURE = 0x02014b50;
const LOCAL_SIGNATURE = 0x04034b50;
const MAX_ZIP_ENTRIES = 5000;
const MAX_CENTRAL_DIRECTORY_BYTES = 1 << 20;
const MAX_DECLARED_UNCOMPRESSED_BYTES = 2 ** 30; // 1 GiB: yalnız BİLDİRİLEN toplam (bomba şüphesi); dosya AÇILMAZ
const MAX_CONTENT_TYPES_BYTES = 1 << 20;

// OOXML etkin içerik denetimi İÇERİĞE (türe) dayanır, yalnız ad kalıbına değil (R16 P2-1: ad kalıpları kolayca atlatılır — örneğin OLE nesnesi `embeddings/` DIŞINDA
// bir ada konup `[Content_Types].xml`'de oleObject türüyle bildirilebilir). Üç katman:
//  1) merkez dizin adları (savunma derinliği): vbaProject / macrosheets / çalıştırılabilir uzantı / activeX/ / embeddings/ altında OLE-makro-eski ikili / xl/externalLinks/
//  2) `[Content_Types].xml` BOM'a göre UTF-8 / UTF-16 çözülür, XML karakter başvuruları (&#x6d; ...) açılır; vba / macro / oleObject / activeX içerik türleri reddedilir
//  3) TÜM `*.rels` girdileri (sınırlı sayı ve boyutla) şişirilir; her Relationship'in Type'ı ve TargetMode'u (karakter başvuruları açılmış) denetlenir
// Sınır (K3): bu BİR güvenlik sınırı değil, EN İYİ ÇABA azaltımıdır. document.xml / sayfa içeriğine (DDE alanları, formüller), sıkıştırılmış iç içe paketlere ve
// `xl/connections.xml` veri bağlantılarına bakılmaz.
//  - activeX/ altındaki her şey (ActiveX denetimleri: activeX1.xml + activeX1.bin)
//  - embeddings/ altındaki OLE paketi / makrolu / eski ikili girdiler (oleObject*.bin, *.xlsm/.docm/..., *.xls/.doc/.ppt). Modern grafik çalışma kitapları
//    (embeddings/*.xlsx) ve resimler MEŞRUDUR; `xl/printerSettings/*.bin` embeddings dışındadır ve zararsızdır (yazıcı ayarı).
const ACTIVEX_ENTRY = /(^|\/)activeX\//i;
const EMBEDDED_ACTIVE_ENTRY = /(^|\/)embeddings\/(?:.*\/)?[^/]*\.(?:bin|xlsm|docm|pptm|xlsb|xlam|dotm|xltm|ppsm|potm|xls|doc|ppt|ole|exe|dll|scr|msi|hta)$/i;
const EXTERNAL_LINK_ENTRY = /^xl\/externalLinks\//i;
const MACRO_ENTRY = /(^|\/)vbaProject(?:Signature)?\.bin$|^xl\/macrosheets\//i;
const EXECUTABLE_ENTRY = /\.(?:exe|dll|bat|cmd|js|vbs|ps1|sh|jar)$/i;

// [Content_Types].xml içerik türleri (karakter başvuruları açıldıktan sonra): makro / VBA, OLE nesnesi, ActiveX
const MACRO_CONTENT_TYPE = /vba|macro/i;
const EMBEDDED_CONTENT_TYPE = /oleobject|activex/i;

// İlişki türleri (Relationship/@Type), İÇ ya da DIŞ fark etmeksizin reddedilenler; bir kısmı yalnız UZAK hedefle reddedilir
const MACRO_REL_TYPE = /vbaProject|vbaData|macrosheet/i;
const EMBEDDED_REL_TYPE = /oleObject|activeX|\/control$|embeddedControl/i;
const REMOTE_ONLY_REL_TYPE = /attachedTemplate|subDocument|\/frame$|externalLink|mailMerge\w*Source/i;

const MAX_REL_ENTRIES = 1000;
const MAX_REL_COMPRESSED = 1 << 20;
const MAX_REL_UNCOMPRESSED = 4 << 20;
const MAX_REL_TOTAL_UNCOMPRESSED = 16 << 20;
const MAX_CONTENT_TYPES_COMPRESSED = 262144;

/** Küçük bir ZIP girdisini SINIRLI çıktıyla okur; sınırı aşan / okunamayan 415 DOCUMENT_CONTENT_MISMATCH. Dosyanın GERİSİ açılmaz. */
async function readBoundedEntry(handle, size, entry, { maxCompressed, maxUncompressed }) {
  if ((entry.method !== 0 && entry.method !== 8) || entry.compressedSize > maxCompressed || entry.uncompressedSize > maxUncompressed) {
    throw contentMismatch();
  }
  const local = await readAt(handle, entry.localOffset, 30);
  if (local.length !== 30 || local.readUInt32LE(0) !== LOCAL_SIGNATURE) throw contentMismatch();
  const dataStart = entry.localOffset + 30 + local.readUInt16LE(26) + local.readUInt16LE(28);
  if (dataStart + entry.compressedSize > size) throw contentMismatch();
  const packed = await readAt(handle, dataStart, entry.compressedSize);
  try {
    return entry.method === 0 ? packed : zlib.inflateRawSync(packed, { maxOutputLength: maxUncompressed });
  } catch (_error) {
    throw contentMismatch();
  }
}

/**
 * OPC XML parçasını (UTF-8 ya da UTF-16, BOM'lu / BOM'suz) metne çevirir. OPC yalnız UTF-8 / UTF-16 kabul eder: UTF-32, EBCDIC vb. kodlama bildirimleri ve
 * DOCTYPE / ENTITY (özel varlık tanımıyla süzgeç atlatma) REDDEDİLİR (415 DOCUMENT_CONTENT_MISMATCH).
 */
export function decodeOpcXml(buffer) {
  if (buffer.length >= 4 && ((buffer[0] === 0xff && buffer[1] === 0xfe && buffer[2] === 0 && buffer[3] === 0) || (buffer[0] === 0 && buffer[1] === 0 && buffer[2] === 0xfe && buffer[3] === 0xff))) {
    throw contentMismatch(); // UTF-32
  }
  let text;
  if (buffer.length >= 3 && buffer[0] === 0xef && buffer[1] === 0xbb && buffer[2] === 0xbf) {
    text = buffer.toString('utf8', 3);
  } else if (buffer.length >= 2 && buffer[0] === 0xff && buffer[1] === 0xfe) {
    text = buffer.toString('utf16le', 2, 2 + ((buffer.length - 2) & ~1));
  } else if (buffer.length >= 2 && buffer[0] === 0xfe && buffer[1] === 0xff) {
    text = Buffer.from(buffer.subarray(2, 2 + ((buffer.length - 2) & ~1))).swap16().toString('utf16le');
  } else if (buffer.length >= 2 && buffer[0] === 0x3c && buffer[1] === 0x00) {
    text = buffer.toString('utf16le', 0, buffer.length & ~1); // BOM'suz UTF-16LE ("<" 00)
  } else if (buffer.length >= 2 && buffer[0] === 0x00 && buffer[1] === 0x3c) {
    text = Buffer.from(buffer.subarray(0, buffer.length & ~1)).swap16().toString('utf16le'); // BOM'suz UTF-16BE (00 "<")
  } else {
    text = buffer.toString('utf8');
  }
  if (text.includes('\0')) throw contentMismatch(); // tanınmayan çok baytlı kodlama
  const declaration = /^\s*<\?xml\b[^>]*?\bencoding\s*=\s*["']([^"']+)["']/i.exec(text);
  if (declaration && !/^(?:utf-8|utf-16)$/i.test(declaration[1].trim())) throw contentMismatch();
  if (/<!(?:DOCTYPE|ENTITY)\b/i.test(text)) throw contentMismatch();
  return text;
}

/** XML önceden tanımlı varlıklar ve sayısal karakter başvuruları (&#69; &#x45;) açılır. */
export function decodeXmlEntities(value) {
  return value.replace(/&(?:#(\d{1,7})|#[xX]([0-9a-fA-F]{1,6})|(amp|lt|gt|quot|apos));/g, (_match, decimal, hex, named) => {
    if (named) return { amp: '&', lt: '<', gt: '>', quot: '"', apos: "'" }[named];
    const codePoint = decimal !== undefined ? Number.parseInt(decimal, 10) : Number.parseInt(hex, 16);
    return Number.isInteger(codePoint) && codePoint > 0 && codePoint <= 0x10ffff && !(codePoint >= 0xd800 && codePoint <= 0xdfff) ? String.fromCodePoint(codePoint) : '';
  });
}

/** `<ETİKET ...>` öğelerinin öznitelikleri (küçük harfli adlar, değerler varlıkları açılmış; ad alanı önekleri atılır). Biçimi bozuk etiket → 415. */
export function tagAttributes(text, tagName) {
  const tagStart = new RegExp(`<(?:[A-Za-z_][\\w.-]*:)?${tagName}(?=[\\s/>])`, 'g');
  const result = [];
  while (tagStart.exec(text) !== null) {
    let position = tagStart.lastIndex;
    const attributes = {};
    for (;;) {
      while (position < text.length && /\s/.test(text[position])) position += 1;
      if (position >= text.length) throw contentMismatch();
      if (text[position] === '>' || text.startsWith('/>', position)) break;
      const nameMatch = /[^\s=/>]+/y;
      nameMatch.lastIndex = position;
      const name = nameMatch.exec(text);
      if (!name) throw contentMismatch();
      position += name[0].length;
      while (position < text.length && /\s/.test(text[position])) position += 1;
      if (text[position] !== '=') throw contentMismatch();
      position += 1;
      while (position < text.length && /\s/.test(text[position])) position += 1;
      const quote = text[position];
      if (quote !== '"' && quote !== "'") throw contentMismatch();
      const end = text.indexOf(quote, position + 1);
      if (end < 0) throw contentMismatch();
      attributes[name[0].split(':').pop().toLowerCase()] = decodeXmlEntities(text.slice(position + 1, end));
      position = end + 1;
    }
    tagStart.lastIndex = position;
    result.push(attributes);
  }
  return result;
}

export const relationshipAttributes = (text) => tagAttributes(text, 'Relationship');

const remoteTarget = (attributes) =>
  String(attributes.targetmode ?? '').trim().toLowerCase() === 'external' || /^\s*(?:[a-z][a-z0-9+.-]*:|[\\/]{2})/i.test(String(attributes.target ?? ''));

/** Bir ilişkinin nedeni ('macro' | 'embedded' | 'external') ya da null. */
export function relationshipRisk(attributes) {
  const type = String(attributes.type ?? '');
  if (MACRO_REL_TYPE.test(type)) return 'macro';
  if (EMBEDDED_REL_TYPE.test(type)) return 'embedded';
  if (REMOTE_ONLY_REL_TYPE.test(type) && remoteTarget(attributes)) return 'external';
  return null;
}

function unsafeEntryName(name) {
  return name === '' || name.startsWith('/') || name.includes('\\') || name.includes('\0') || /(^|\/)\.\.(\/|$)/.test(name) || /^[A-Za-z]:/.test(name);
}

/**
 * OOXML (DOCX/XLSX) ZIP incelemesi: EOCD + merkez dizin; dosya AÇILMAZ. Karar İÇERİK türüne dayanır (R16 P2-1): merkez dizin adları (savunma derinliği), `[Content_Types].xml`
 * (BOM'a göre UTF-8 / UTF-16, karakter başvuruları açılmış) içerik türleri ve TÜM `*.rels` ilişkileri (sınırlı sayı / boyutla şişirilip Type + TargetMode denetlenir).
 * EN İYİ ÇABA: document.xml / sayfa içeriğine (DDE, formül) bakılmaz.
 * @returns {Promise<'docx'|'xlsx'>}
 */
export async function inspectOoxml(handle, size) {
  if (size < 22) throw contentMismatch();
  const tailLength = Math.min(size, 22 + 65535);
  const tail = await readAt(handle, size - tailLength, tailLength);
  let eocd = -1;
  for (let i = tail.length - 22; i >= 0; i -= 1) {
    if (tail.readUInt32LE(i) === EOCD_SIGNATURE && i + 22 + tail.readUInt16LE(i + 20) === tail.length) {
      eocd = i;
      break;
    }
  }
  if (eocd < 0) throw contentMismatch();
  const diskNo = tail.readUInt16LE(eocd + 4);
  const cdDisk = tail.readUInt16LE(eocd + 6);
  const entriesOnDisk = tail.readUInt16LE(eocd + 8);
  const entries = tail.readUInt16LE(eocd + 10);
  const cdSize = tail.readUInt32LE(eocd + 12);
  const cdOffset = tail.readUInt32LE(eocd + 16);
  if (diskNo !== 0 || cdDisk !== 0 || entriesOnDisk !== entries || entries === 0xffff || cdSize === 0xffffffff || cdOffset === 0xffffffff) {
    throw contentMismatch();
  }
  if (entries === 0 || entries > MAX_ZIP_ENTRIES || cdSize > MAX_CENTRAL_DIRECTORY_BYTES || cdOffset + cdSize > size) {
    throw contentMismatch();
  }
  const directory = await readAt(handle, cdOffset, cdSize);
  if (directory.length !== cdSize) throw contentMismatch();

  const names = new Map();
  let position = 0;
  let declaredTotal = 0;
  for (let i = 0; i < entries; i += 1) {
    if (position + 46 > directory.length || directory.readUInt32LE(position) !== CENTRAL_SIGNATURE) throw contentMismatch();
    const flags = directory.readUInt16LE(position + 8);
    const method = directory.readUInt16LE(position + 10);
    const compressedSize = directory.readUInt32LE(position + 20);
    const uncompressedSize = directory.readUInt32LE(position + 24);
    const nameLength = directory.readUInt16LE(position + 28);
    const extraLength = directory.readUInt16LE(position + 30);
    const commentLength = directory.readUInt16LE(position + 32);
    const localOffset = directory.readUInt32LE(position + 42);
    if (position + 46 + nameLength + extraLength + commentLength > directory.length) throw contentMismatch();
    if ((flags & 0x1) !== 0) throw contentMismatch(); // şifreli girdi
    const name = directory.toString((flags & 0x800) !== 0 ? 'utf8' : 'latin1', position + 46, position + 46 + nameLength);
    if (unsafeEntryName(name) || names.has(name)) throw contentMismatch();
    declaredTotal += uncompressedSize;
    if (declaredTotal > MAX_DECLARED_UNCOMPRESSED_BYTES) throw contentMismatch();
    names.set(name, { method, compressedSize, uncompressedSize, localOffset });
    position += 46 + nameLength + extraLength + commentLength;
  }

  // 1) merkez dizin adları (savunma derinliği)
  for (const name of names.keys()) {
    if (MACRO_ENTRY.test(name)) throw activeContent('macro');
    if (EXECUTABLE_ENTRY.test(name)) throw activeContent('executable');
    if (ACTIVEX_ENTRY.test(name) || EMBEDDED_ACTIVE_ENTRY.test(name)) throw activeContent('embedded');
    if (EXTERNAL_LINK_ENTRY.test(name)) throw activeContent('external');
  }
  const contentTypes = names.get('[Content_Types].xml');
  if (!contentTypes) throw contentMismatch();

  // 2) `[Content_Types].xml` (BOM'a göre UTF-8 / UTF-16): makro, OLE nesnesi, ActiveX içerik türleri. Küçük girdi, SINIRLI çıktıyla okunur.
  const contentTypesXml = decodeOpcXml(
    await readBoundedEntry(handle, size, contentTypes, { maxCompressed: MAX_CONTENT_TYPES_COMPRESSED, maxUncompressed: MAX_CONTENT_TYPES_BYTES }),
  );
  const declaredTypes = [...tagAttributes(contentTypesXml, 'Default'), ...tagAttributes(contentTypesXml, 'Override')].map((attributes) => String(attributes.contenttype ?? ''));
  if (/macroEnabled|vbaProject/i.test(decodeXmlEntities(contentTypesXml)) || declaredTypes.some((type) => MACRO_CONTENT_TYPE.test(type))) {
    throw activeContent('macro');
  }
  if (declaredTypes.some((type) => EMBEDDED_CONTENT_TYPE.test(type))) throw activeContent('embedded');

  // 3) TÜM `*.rels` girdileri (sınırlı sayı ve boyut): ilişki türü + hedef kipi (karakter başvuruları açılmış). Uzak şablon (attachedTemplate), dış nesne
  //    (oleObject, subDocument, frame, externalLink), makro / ActiveX ilişkileri reddedilir.
  let relationshipParts = 0;
  let relationshipBytes = 0;
  for (const [name, entry] of names) {
    if (!/\.rels$/i.test(name)) continue;
    relationshipParts += 1;
    if (relationshipParts > MAX_REL_ENTRIES) throw contentMismatch();
    const body = await readBoundedEntry(handle, size, entry, { maxCompressed: MAX_REL_COMPRESSED, maxUncompressed: MAX_REL_UNCOMPRESSED });
    relationshipBytes += body.length;
    if (relationshipBytes > MAX_REL_TOTAL_UNCOMPRESSED) throw contentMismatch();
    for (const attributes of relationshipAttributes(decodeOpcXml(body))) {
      const risk = relationshipRisk(attributes);
      if (risk) throw activeContent(risk);
    }
  }

  const hasWord = names.has('word/document.xml');
  const hasSheet = names.has('xl/workbook.xml');
  if (hasWord && hasSheet) throw contentMismatch();
  if (hasWord) return 'docx';
  if (hasSheet) return 'xlsx';
  throw typeNotAllowed(); // geçerli ZIP ama Word/Excel belgesi değil (pptx, jar, düz arşiv ...)
}

/**
 * Diske yazılmış geçici dosyayı doğrular ve KESİN türü döndürür.
 *  - pdf: son 2048 bayt içinde `%%EOF` (kesik dosya), etkin içerik adları yok
 *  - png: IHDR + dosya TAM `IEND` ile biter (sonuna eklenmiş veri yok)
 *  - jpg: (ek denetim yok)
 *  - zip: OOXML incelemesi; bildirilen tür (declared ise) ile uyuşmalı
 * @param {import('node:fs').promises.FileHandle} handle
 */
export async function validateStoredFile(handle, size, { expectedKind, declared }, limits) {
  const head = await readAt(handle, 0, Math.min(size, 16));
  const raw = assertHeadAcceptable(head, { expectedKind, declared }, limits);
  if (raw === 'pdf') {
    const tail = await readAt(handle, Math.max(0, size - 2048), Math.min(size, 2048));
    if (!tail.includes('%%EOF')) throw contentMismatch();
    if (await pdfHasActiveContent(handle, size)) throw activeContent();
    return 'pdf';
  }
  if (raw === 'png') {
    if (size < 33 || head.latin1Slice(12, 16) !== 'IHDR') throw contentMismatch();
    const tail = await readAt(handle, size - 12, 12);
    if (tail.latin1Slice(4, 8) !== 'IEND') throw contentMismatch();
    return 'png';
  }
  if (raw === 'jpg') {
    return 'jpg';
  }
  const kind = await inspectOoxml(handle, size);
  if (!officeAllowed(kind, limits)) throw typeNotAllowed();
  if (declared && kind !== expectedKind) throw contentMismatch();
  return kind;
}
