// Toplu yükleme (Faz 2b) değer ayrıştırıcıları: TEK modül, saf (DB/ağ bağımsız), hiçbir girdi için özel hata FIRLATMAZ.
//
// Sözleşme: docs/PLATFORM_TOPLU_ISLEMLER.md ("Değer kuralları"). İstemci ayrıştırması yalnız kolaylıktır; sunucu HER hücreyi güvenilmez sayar ve burada
// yeniden doğrular. Her okuyucu `{ value, error?, warnings? }` döndürür: `error` bir satır-hata kodudur (REQUIRED hariç, çağıran üretir);
// `warnings` uyarı kodlarıdır. `value === null` hücre boş demektir (HİÇBİR ZAMAN mevcut değeri silmez).

import { isDroppedCodePoint, cleanText } from '../utils/safe_text.js';
import {
  foldText,
  normalizePersonEmail,
  normalizePersonName,
  normalizePersonPhone,
} from './people_common.js';
import { requireTrPlateEntry } from './plate_format.js';
import { INTERNAL_EMAIL_SUFFIX } from './people_sync_sql.js';
import { CELL_MAX_LENGTH, RELATION_WORDS, RESPONSIBLE_WORDS, foldHeader } from './bulk_import_spec.js';

export const MAX_PLATES_PER_CELL = 5;
export const FLOOR_MIN = -20;
export const FLOOR_MAX = 500;
export const LAND_SHARE_MAX = 1_000_000_000;

const lengthOf = (text) => Array.from(text).length;

// --- Metin ---------------------------------------------------------------------------------------------------

/** JSON hücre değeri -> ham metin (sayılar düz biçimde). Metin/sayı dışı -> null. */
export function cellToText(raw) {
  if (raw === null || raw === undefined) {
    return null;
  }
  if (typeof raw === 'string') {
    return raw;
  }
  if (typeof raw === 'number' && Number.isFinite(raw)) {
    if (Number.isInteger(raw)) {
      return String(raw);
    }
    const plain = String(raw);
    return /e/i.test(plain) ? raw.toFixed(10).replace(/0+$/, '').replace(/\.$/, '') : plain;
  }
  return null;
}

const TAB = 9;
const CR = 13;

/**
 * Ham metnin ilk "anlamlı" karakteri: görünmez/yön karakterleri, kontrol karakterleri ve boşluk atlanır; TAB ve CR atlanMAZ (formül öneki sayılır).
 * Sözleşme: kırpılmış metin `=`, `@`, TAB ya da CR ile başlıyorsa FORMULA_LIKE.
 */
export function leadingChar(text) {
  for (const ch of text) {
    const code = ch.codePointAt(0);
    if (code === TAB || code === CR) {
      return ch;
    }
    if (code === 0x20 || code === 0xa0 || isDroppedCodePoint(code)) {
      continue;
    }
    return ch;
  }
  return '';
}

function collapseSpaces(text) {
  return text.replace(/\s+/g, ' ').trim();
}

function collapseKeepingLines(text) {
  return text
    .split('\n')
    .map((line) => line.replace(/[^\S\n]+/g, ' ').trim())
    .join('\n')
    .replace(/\n{3,}/g, '\n\n')
    .trim();
}

/**
 * Metin hücresi: NFC, kontrol ve görünmez/yön karakterleri silinir, NBSP/ardışık boşluk tekile, kırpılır; boş = yok.
 * `=`, `@`, TAB, CR ile başlayan hücre FORMULA_LIKE; `forbidSigned` iken `+`/`-` ile başlayan da FORMULA_LIKE (ad, e-posta, blok, tip, plaka).
 * `max` kod noktası aşılırsa TOO_LONG. Sessiz "temizleme" YOK: kullanıcı neyin reddedildiğini görür.
 */
export function readText(raw, { max = CELL_MAX_LENGTH, forbidSigned = false, multiline = false } = {}) {
  const text = cellToText(raw);
  if (text === null) {
    return { value: null };
  }
  const lead = leadingChar(text);
  // Önce görünmezler atılır, SONRA NFC (atılan karakter birleşik harf dizisini bölmüş olabilir; sonuç idempotent kalır).
  const cleaned = (multiline ? collapseKeepingLines(cleanText(text, { multiline: true })) : collapseSpaces(cleanText(text))).normalize('NFC');
  if (cleaned === '') {
    return { value: null };
  }
  for (const ch of new Set([lead, cleaned[0]])) {
    if (ch === '=' || ch === '@' || ch === '\t' || ch === '\r' || (forbidSigned && (ch === '+' || ch === '-'))) {
      return { value: null, error: 'FORMULA_LIKE', lead: ch };
    }
  }
  if (lengthOf(cleaned) > max) {
    return { value: null, error: 'TOO_LONG', max };
  }
  return { value: cleaned };
}

/** Ad Soyad (2-100 karakter). */
export function readName(raw) {
  const text = readText(raw, { forbidSigned: true });
  if (text.error || text.value === null) {
    return text;
  }
  try {
    return { value: normalizePersonName(text.value, 'ad_soyad') };
  } catch (_error) {
    return { value: null, error: 'NAME_INVALID' };
  }
}

/** Telefon -> +90XXXXXXXXXX. Excel'in baştaki sıfırı attığı 10 haneli numara da kabul edilir. */
export function readPhone(raw) {
  const text = readText(raw);
  if (text.error || text.value === null) {
    return text;
  }
  try {
    return { value: normalizePersonPhone(text.value, 'telefon') };
  } catch (_error) {
    return { value: null, error: 'PHONE_INVALID' };
  }
}

/** E-posta (küçük harf). `@ahbu.local` EMAIL_INTERNAL. */
export function readEmail(raw) {
  const text = readText(raw, { forbidSigned: true });
  if (text.error || text.value === null) {
    return text;
  }
  let email;
  try {
    email = normalizePersonEmail(text.value, 'e_posta');
  } catch (_error) {
    return { value: null, error: 'EMAIL_INVALID' };
  }
  if (email !== null && email.endsWith(INTERNAL_EMAIL_SUFFIX)) {
    return { value: null, error: 'EMAIL_INTERNAL' };
  }
  return { value: email };
}

// --- Tam sayı yardımcıları -----------------------------------------------------------------------------------

// Türkçe binlik noktası: ilk grup 1-3 rakam, kalan her grup tam 3 rakam (["1","250"] -> 1.250). readLandShareInt kullanır.
const isThousandsGroups = (parts) =>
  parts.length >= 2 && /^[1-9]\d{0,2}$/.test(parts[0]) && parts.slice(1).every((part) => /^\d{3}$/.test(part));

/**
 * Arsa payı parçası (pay ya da payda): tam sayı. Metinde 3'lü binlik noktası kabul edilir (1.000 -> 1000). Aralık LAND_SHARE_INVALID.
 */
export function readLandShareInt(raw, { min }) {
  if (raw === null || raw === undefined) {
    return { value: null };
  }
  let number;
  if (typeof raw === 'number') {
    number = raw;
  } else {
    const text = readText(raw);
    if (text.error || text.value === null) {
      return text;
    }
    const source = text.value.replace(/\s/g, '');
    const pieces = source.split('.');
    if (/^\d+$/.test(source)) {
      number = Number(source);
    } else if (isThousandsGroups(pieces)) {
      number = Number(pieces.join(''));
    } else {
      return { value: null, error: 'LAND_SHARE_INVALID' };
    }
  }
  if (!Number.isInteger(number) || number < min || number > LAND_SHARE_MAX) {
    return { value: null, error: 'LAND_SHARE_INVALID' };
  }
  return { value: number };
}

/** Kat: tam sayı -20..500; zemin/giriş = 0, bodrum = -1 (N. bodrum = -N), "3. kat" = 3. */
export function readFloor(raw) {
  if (raw === null || raw === undefined) {
    return { value: null };
  }
  let value;
  if (typeof raw === 'number') {
    value = raw;
  } else {
    const text = readText(raw);
    if (text.error || text.value === null) {
      return text;
    }
    const folded = foldText(text.value).replace(/\s+/g, ' ').trim();
    let match;
    if (/^(?:zemin|giris)(?: kat)?$/.test(folded)) {
      value = 0;
    } else if (/^bodrum(?: kat)?$/.test(folded)) {
      value = -1;
    } else if ((match = /^([1-4])\s*\.?\s*bodrum(?: kat)?$/.exec(folded))) {
      value = -Number(match[1]);
    } else if ((match = /^(?:kat\s*)?([+-]?\d{1,3})\s*\.?\s*(?:kat)?$/.exec(folded))) {
      value = Number(match[1]);
    } else {
      return { value: null, error: 'FLOOR_INVALID' };
    }
  }
  if (!Number.isInteger(value) || value < FLOOR_MIN || value > FLOOR_MAX) {
    return { value: null, error: 'FLOOR_INVALID' };
  }
  return { value };
}

// --- Tarih ---------------------------------------------------------------------------------------------------

function addDaysIso(iso, days) {
  const [year, month, day] = iso.split('-').map(Number);
  const date = new Date(Date.UTC(year, month - 1, day + days));
  return `${String(date.getUTCFullYear()).padStart(4, '0')}-${String(date.getUTCMonth() + 1).padStart(2, '0')}-${String(date.getUTCDate()).padStart(2, '0')}`;
}

/**
 * Giriş tarihi: GG.AA.YYYY, G.A.YYYY, GG/AA/YYYY, GG-AA-YYYY, YYYY-AA-GG (ISO saat eki yok sayılır). 2 haneli yıl DATE_INVALID.
 * 1900..bugün+366 gün: gelecek tarih FUTURE_DATE (uyarı); ötesi DATE_RANGE.
 * @param {string} today Istanbul bugünü (YYYY-MM-DD)
 */
export function readDate(raw, today) {
  if (raw === null || raw === undefined) {
    return { value: null };
  }
  if (typeof raw === 'number') {
    return { value: null, error: 'DATE_INVALID' };
  }
  const text = readText(raw);
  if (text.error || text.value === null) {
    return text;
  }
  const source = text.value.replace(/[T ]\d{1,2}:\d{2}(?::\d{2}(?:\.\d+)?)?(?:Z|[+-]\d{2}:?\d{2})?$/i, '');
  let year;
  let month;
  let day;
  let match = /^(\d{4})-(\d{1,2})-(\d{1,2})$/.exec(source);
  if (match) {
    [, year, month, day] = match;
  } else {
    match = /^(\d{1,2})[./-](\d{1,2})[./-](\d{4})$/.exec(source);
    if (!match) {
      return { value: null, error: 'DATE_INVALID' };
    }
    [, day, month, year] = match;
  }
  const y = Number(year);
  const m = Number(month);
  const d = Number(day);
  const probe = new Date(Date.UTC(y, m - 1, d));
  if (y < 1000 || probe.getUTCFullYear() !== y || probe.getUTCMonth() !== m - 1 || probe.getUTCDate() !== d) {
    return { value: null, error: 'DATE_INVALID' };
  }
  const iso = `${year}-${String(m).padStart(2, '0')}-${String(d).padStart(2, '0')}`;
  if (y < 1900 || iso > addDaysIso(today, 366)) {
    return { value: null, error: 'DATE_RANGE' };
  }
  return { value: iso, warnings: iso > today ? ['FUTURE_DATE'] : [] };
}

// --- Enum'lar ------------------------------------------------------------------------------------------------

function wordMap(words) {
  const map = new Map();
  for (const [value, list] of Object.entries(words)) {
    for (const word of list) {
      map.set(foldHeader(word), value);
    }
  }
  return map;
}

const RELATION_MAP = wordMap(RELATION_WORDS);
const RESPONSIBLE_MAP = wordMap(RESPONSIBLE_WORDS);

/** İlişki sözcüğü -> owner | tenant | family_member | resident; boş -> null (görüş yok). Bilinmeyen RELATION_INVALID. */
export function readRelation(raw) {
  const text = readText(raw, { forbidSigned: true, max: 80 });
  if (text.error || text.value === null) {
    return text;
  }
  const relation = RELATION_MAP.get(foldHeader(text.value));
  return relation ? { value: relation } : { value: null, error: 'RELATION_INVALID' };
}

/** Borç sorumlusu: Malik / Kiracı / İkisi -> owner | tenant | both. */
export function readResponsible(raw) {
  const text = readText(raw, { forbidSigned: true, max: 80 });
  if (text.error || text.value === null) {
    return text;
  }
  const party = RESPONSIBLE_MAP.get(foldHeader(text.value));
  return party ? { value: party } : { value: null, error: 'RESPONSIBLE_INVALID' };
}

// --- Plaka ---------------------------------------------------------------------------------------------------

/**
 * Plaka hücresi: en çok 5 plaka; ayırıcı `,` `;` `/` `|` satır sonu. Geçerli plakalar (normalize, yinelenen atılır) ve geçersiz parçalar ayrı döner.
 * `=`/`@`/TAB/CR/`+`/`-` ile başlayan hücre FORMULA_LIKE; 5'ten fazla parça TOO_MANY_PLATES.
 */
export function readPlates(raw) {
  const text = cellToText(raw);
  if (text === null) {
    return { plates: [], invalid: [] };
  }
  const lead = leadingChar(text);
  const cleaned = collapseKeepingLines(cleanText(text, { multiline: true })).normalize('NFC');
  if (cleaned === '') {
    return { plates: [], invalid: [] };
  }
  for (const ch of new Set([lead, cleaned[0]])) {
    if (ch === '=' || ch === '@' || ch === '\t' || ch === '\r' || ch === '+' || ch === '-') {
      return { plates: [], invalid: [], error: 'FORMULA_LIKE', lead: ch };
    }
  }
  if (lengthOf(cleaned) > CELL_MAX_LENGTH) {
    return { plates: [], invalid: [], error: 'TOO_LONG', max: CELL_MAX_LENGTH };
  }
  const parts = cleaned
    .split(/[,;/|\n]/)
    .map((part) => collapseSpaces(part))
    .filter((part) => part !== '');
  if (parts.length > MAX_PLATES_PER_CELL) {
    return { plates: [], invalid: [], error: 'TOO_MANY_PLATES' };
  }
  const plates = [];
  const invalid = [];
  const seen = new Set();
  for (const part of parts) {
    try {
      // Türk plakası kuralı (createVehicle ile aynı): plate = "34ABC123", display = "34 ABC 123".
      const { plate, display } = requireTrPlateEntry(part);
      if (!seen.has(plate)) {
        seen.add(plate);
        plates.push({ plate, display });
      }
    } catch (_error) {
      invalid.push(Array.from(part).slice(0, 40).join(''));
    }
  }
  return { plates, invalid };
}

// --- Daire etiketi eşleşmesi ---------------------------------------------------------------------------------

function blockNorm(text) {
  return foldText(text).replace(/[._\-/,:;]+/g, ' ').replace(/\s+/g, ' ').trim();
}

function stripBlockWord(norm) {
  const tokens = norm.split(' ');
  if (tokens.length > 1 && tokens[0] === 'blok') {
    tokens.shift();
  } else if (tokens.length > 1 && tokens[tokens.length - 1] === 'blok') {
    tokens.pop();
  }
  return tokens.join(' ');
}

/**
 * Blok eşleşmesi: önce katlanmış TAM ad; yoksa baştaki/sondaki "blok" sözcüğü atılmış hâl ("A", "A Blok", "Blok A" aynı).
 * @param {{ id: number, name: string }[]} blocks
 * @returns {{ block?: object, error?: 'BLOCK_NOT_FOUND'|'BLOCK_AMBIGUOUS' }}
 */
export function matchBlock(input, blocks) {
  const wanted = blockNorm(input);
  if (wanted === '') {
    return { error: 'BLOCK_NOT_FOUND' };
  }
  const normalized = blocks.map((block) => ({ block, norm: blockNorm(block.name) }));
  const exact = normalized.filter((entry) => entry.norm === wanted);
  if (exact.length === 1) {
    return { block: exact[0].block };
  }
  if (exact.length > 1) {
    return { error: 'BLOCK_AMBIGUOUS' };
  }
  const stripped = stripBlockWord(wanted);
  const loose = normalized.filter((entry) => stripBlockWord(entry.norm) === stripped);
  if (loose.length === 1) {
    return { block: loose[0].block };
  }
  return { error: loose.length > 1 ? 'BLOCK_AMBIGUOUS' : 'BLOCK_NOT_FOUND' };
}

/**
 * Daire anahtarı: "5", "05", "Daire 5", "D5", "No: 5", "Daire No: 5" -> `n:5`; başka etiket -> `l:<katlanmış etiket>`.
 * Aynı fonksiyon veritabanındaki unit_label ("Daire N") için de çalışır.
 */
export function apartmentKey(text) {
  const norm = foldText(text).replace(/[.:#\-_/]+/g, ' ').replace(/\s+/g, ' ').trim();
  const match = /^(?:daire|kapi|apt|bagimsiz bolum|numara|nr|no|d)?\s*(?:no|numara|nr)?\s*(\d{1,6})$/.exec(norm);
  return match ? `n:${Number(match[1])}` : `l:${norm}`;
}

// --- Devir bakiyesi (F4): tutar, hesap, vade ----------------------------------------------------------------

export const MONEY_MAX_MINOR = 1_000_000_000_000;
export const ACCOUNT_WORDS = Object.freeze({
  owner: Object.freeze(['Ev sahibi', 'Malik', 'Mal sahibi']),
  tenant: Object.freeze(['Kiracı']),
});
const ACCOUNT_MAP = wordMap(ACCOUNT_WORDS);

/** Hesap sütunu: Ev sahibi / Malik / Mal sahibi -> owner, Kiracı -> tenant; boş -> null (çağıran owner varsayar). */
export function readAccount(raw) {
  const text = readText(raw, { forbidSigned: true, max: 80 });
  if (text.error || text.value === null) {
    return text;
  }
  const party = ACCOUNT_MAP.get(foldHeader(text.value));
  return party ? { value: party } : { value: null, error: 'ACCOUNT_INVALID' };
}

/** Tamsayı + ondalık basamak metninden kuruş (yarım yukarı; metin aritmetiği). Dönüş: { minor: bigint, rounded: boolean }. */
function minorFromParts(intPart, fraction) {
  const carry = fraction.length > 2 && fraction.charCodeAt(2) >= 53 ? 1n : 0n;
  return { minor: BigInt(intPart) * 100n + BigInt(fraction.slice(0, 2).padEnd(2, '0')) + carry, rounded: fraction.length > 2 };
}

/**
 * Sayısal hücre (xlsx sayı hücresi JSON'da number gelir) -> kuruş. Ondalık nokta KESİN ondalıktır: 123.456 TL = 12346 kuruş (metin yolundaki TR
 * binlik sezgisi — "123.456" = 123456 TL — YALNIZ metin hücrelerinde geçerlidir; sayıya uygulanınca tutar 1000 kat okunurdu). 2 haneye yuvarlanır;
 * gerçek bir 3. ondalık yüzünden yuvarlandıysa ROUNDED uyarısı verilir (kayan nokta gürültüsü — 0.30000000000000004 — uyarı üretmez).
 */
function readMoneyNumber(value) {
  const negative = value < 0;
  const abs = Math.abs(value);
  if (abs >= 1e21) {
    return { value: null, error: 'MONEY_RANGE' };
  }
  const plain = /e/i.test(String(abs)) ? abs.toFixed(10) : String(abs);
  const [intPart, fraction = ''] = plain.split('.');
  const { minor, rounded } = minorFromParts(intPart === '' ? '0' : intPart, fraction);
  if (minor >= BigInt(MONEY_MAX_MINOR)) {
    return { value: null, error: 'MONEY_RANGE' };
  }
  const warnings = rounded && Math.abs(abs * 100 - Math.round(abs * 100)) > 1e-6 ? ['ROUNDED'] : [];
  return { value: negative && minor !== 0n ? -Number(minor) : Number(minor), warnings };
}

/**
 * TL tutarı -> kuruş (tamsayı; metin aritmetiği, kayan nokta yok). '1.250,50', '1250.5', '₺ 1.250', '1250 TL' kabul edilir.
 * 2'den fazla ondalık yarım yukarı yuvarlanır (ROUNDED uyarısı). Eksi değer işaretiyle döner (çağıran karar verir). Aşırı büyük MONEY_RANGE.
 * Sayısal (number) hücre ayrı yoldan okunur (readMoneyNumber): nokta kesin ondalıktır, TR binlik sezgisi yalnız METİN hücrelerinde uygulanır.
 */
export function readMoney(raw) {
  if (typeof raw === 'number' && Number.isFinite(raw)) {
    return readMoneyNumber(raw);
  }
  const text = readText(raw, { max: 40 });
  if (text.error || text.value === null) {
    return text;
  }
  const invalid = { value: null, error: 'MONEY_INVALID' };
  let body = text.value.replace(/₺|TRY|TL/gi, '').replace(/[\s\u00a0]/g, '');
  let negative = false;
  if (/^\(.*\)$/.test(body)) {
    negative = true;
    body = body.slice(1, -1);
  }
  if (body.startsWith('-') || body.startsWith('−')) {
    negative = !negative;
    body = body.slice(1);
  } else if (body.startsWith('+')) {
    body = body.slice(1);
  }
  if (!/^[0-9.,]+$/.test(body) || !/[0-9]/.test(body)) {
    return invalid;
  }
  const lastDot = body.lastIndexOf('.');
  const lastComma = body.lastIndexOf(',');
  let intPart = body;
  let fraction = '';
  if (lastDot >= 0 && lastComma >= 0) {
    // karışık: son ayırıcı ondalık, diğeri binlik
    const at = Math.max(lastDot, lastComma);
    const thousands = lastDot > lastComma ? ',' : '.';
    intPart = body.slice(0, at);
    fraction = body.slice(at + 1);
    const pattern = thousands === '.' ? /^\d{1,3}(\.\d{3})*$/ : /^\d{1,3}(,\d{3})*$/;
    if (!pattern.test(intPart)) return invalid;
  } else if (lastDot >= 0 || lastComma >= 0) {
    const sep = lastComma >= 0 ? ',' : '.';
    const at = Math.max(lastDot, lastComma);
    const count = body.split(sep).length - 1;
    const after = body.slice(at + 1);
    if (count > 1 || after.length === 3) {
      // binlik ayırıcı (TR): 1.250 / 1.250.000
      if (!(sep === '.' ? /^\d{1,3}(\.\d{3})+$/ : /^\d{1,3}(,\d{3})+$/).test(body)) return invalid;
    } else {
      intPart = body.slice(0, at);
      fraction = after;
    }
  }
  intPart = intPart.replace(/[.,]/g, '');
  if (intPart === '') intPart = '0';
  if (!/^\d+$/.test(intPart) || (fraction !== '' && !/^\d+$/.test(fraction))) {
    return invalid;
  }
  const warnings = [];
  const { minor, rounded } = minorFromParts(intPart, fraction);
  if (rounded) warnings.push('ROUNDED');
  if (minor >= BigInt(MONEY_MAX_MINOR)) {
    return { value: null, error: 'MONEY_RANGE' };
  }
  return { value: negative ? -Number(minor) : Number(minor), warnings };
}

/** 'A-5' / 'A/5' gibi tek hücrelik daire kodu -> { block, number }; ayrıştırılamazsa value null. */
export function readApartmentCode(raw) {
  const text = readText(raw, { forbidSigned: true, max: 90 });
  if (text.error || text.value === null) {
    return { value: null };
  }
  const match = /^(.+?)\s*[-/]\s*([^-/\s]+)$/.exec(text.value);
  return match ? { value: { block: match[1].trim(), number: match[2].trim() } } : { value: null };
}
