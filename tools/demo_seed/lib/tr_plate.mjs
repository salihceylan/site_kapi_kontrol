// Gercekci Turk plakasi uretimi (DB'siz, saf). add_vehicles.mjs ve testler kullanir.
//
// Bicim (uygulamanin plate_recognition_common.js TR_PLATE_RE kuralina uyar): <il kodu 01-81> <1-3 harf> <2-4 rakam>.
//   * 1 harf  + 4 rakam   (35 A 1234)      -- resmi plakada 4-5 rakam, uygulama en cok 4 rakam kabul eder
//   * 2 harf  + 3-4 rakam (35 AB 123, 35 AB 1234)
//   * 3 harf  + 2-3 rakam (35 ABC 12, 35 ABC 123)
//   * harf + rakam toplami en cok 6
// Harf kumesi: Turk plakalarinda Ç Ğ İ Ö Ş Ü ve Q W X YOKTUR; rakamlarla karisan I ve O da uretilmez
// => A B C D E F G H J K L M N P R S T U V Y Z (21 harf).
//
// Ozel serilerden (polis, resmi arac, diplomatik, konsolosluk, ticari taksi, gecici, yabanci ikamet, jandarma, sahil guvenlik...)
// KACINILIR: ozel arac gibi gorunmeyen plaka uretilmez. Gercek/taninmis plaka riskini azaltmak icin harf ve rakamlar rastgeledir;
// bilinen tarih/sayilar (1923, 1453, 1905...) ile tekrar / ardisik rakamlar elenir.

import { canonicalPlate } from './plate_text.mjs';

export const PLATE_LETTERS = 'ABCDEFGHJKLMNPRSTUVYZ';

/** [il kodu, agirlik]: site Izmir'de varsayilir (%65 35), kalani buyuk iller. */
export const PROVINCE_WEIGHTS = [
  ['35', 65],
  ['34', 8],
  ['06', 6],
  ['45', 5],
  ['09', 4],
  ['16', 3.5],
  ['07', 3],
  ['01', 2.5],
  ['48', 1.5],
  ['20', 1.5],
];

/** [[harf sayisi, rakam sayisi], agirlik] */
export const FORMAT_WEIGHTS = [
  [[3, 3], 36],
  [[2, 4], 28],
  [[2, 3], 14],
  [[3, 2], 8],
  [[1, 4], 14],
];

// Uygulamanin plaka dogrulamasi (server/src/modules/plate_recognition_common.js TR_PLATE_RE ile ayni).
export const TR_PLATE_RE = /^(0[1-9]|[1-7][0-9]|8[01])([A-Z]{1,3})([0-9]{2,4})$/;

const BANNED_TEXT = new Set([
  // siyasi / sakincali kisaltmalar ve bilinen kurum kodlari
  'AMK', 'PKK', 'AKP', 'CHP', 'MHP', 'HDP', 'FTO', 'FET', 'PYD', 'YPG', 'TSK', 'TEM', 'DHK', 'MIT', 'PTT', 'SEX', 'GMR', 'SGH',
  // ozel seri / resmi arac harfleri
  'CD', 'CC', 'CB', 'TC', 'AA', 'AAA',
]);
// 1 harf: B (uluslararasi kurulus), G (gecici), T (taksi/test), 2 harf: M? (yabanci ikamet MA-MZ);
// 3 harf: J?? (jandarma), S?? (Suriyeli ikamet, sahil guvenlik), T?? (Istanbul taksi), G?? (gecici gumruk).
const BANNED_SINGLE = new Set(['B', 'G', 'T']);
const BANNED_FIRST_2 = new Set(['M']);
const BANNED_FIRST_3 = new Set(['J', 'S', 'T', 'G']);

const FAMOUS_NUMBERS = new Set([
  '1071', '1299', '1453', '1881', '1903', '1905', '1907', '1919', '1923', '1938', '1912', '1914', '1920', '2023', '1234', '4321', '1010', '2020', '1919',
]);

function sameDigits(d) {
  return d.split('').every((c) => c === d[0]);
}
function sequential(d) {
  const diffs = new Set();
  for (let i = 1; i < d.length; i += 1) diffs.add(Number(d[i]) - Number(d[i - 1]));
  return d.length >= 3 && diffs.size === 1 && (diffs.has(1) || diffs.has(-1));
}

/** Rakam grubu kabul edilebilir mi? (ilk rakam 0 degil, tekrar/ardisik/ozel sayi degil) */
export function digitsAllowed(digits) {
  if (!/^[1-9][0-9]{1,3}$/.test(digits)) return false;
  if (sameDigits(digits) || sequential(digits)) return false;
  if (FAMOUS_NUMBERS.has(digits)) return false;
  if (/^(.)\1\1/.test(digits) || /(.)\1\1$/.test(digits)) return false; // 111x, x999
  return true;
}

/** Harf grubu kabul edilebilir mi? */
export function lettersAllowed(letters) {
  if (!new RegExp(`^[${PLATE_LETTERS}]{1,3}$`).test(letters)) return false;
  if (BANNED_TEXT.has(letters)) return false;
  if (letters.length === 1) return !BANNED_SINGLE.has(letters);
  if (letters.length === 2) return !BANNED_FIRST_2.has(letters[0]) && letters[0] !== letters[1];
  return !BANNED_FIRST_3.has(letters[0]) && !(letters[0] === letters[1] && letters[1] === letters[2]) && letters[0] !== letters[1] && letters[1] !== letters[2];
}

/** Bir plakanin (bosluksuz) sorunlarini listeler; bos liste = uygun. */
export function plateProblems(normalized) {
  const problems = [];
  const m = TR_PLATE_RE.exec(String(normalized ?? ''));
  if (!m) return ['biçim geçersiz (il 01-81 + 1-3 harf + 2-4 rakam)'];
  const [, , letters, digits] = m;
  if (/[IOQWX]/.test(letters)) problems.push('Q/W/X/I/O harfi');
  if (!lettersAllowed(letters)) problems.push(`harf grubu uygun degil (${letters})`);
  if (!digitsAllowed(digits)) problems.push(`rakam grubu uygun degil (${digits})`);
  const combos = { 1: [4], 2: [3, 4], 3: [2, 3] };
  if (!(combos[letters.length] ?? []).includes(digits.length)) problems.push(`harf/rakam sayisi uyumsuz (${letters.length}+${digits.length})`);
  if (letters.length + digits.length > 6) problems.push('harf+rakam > 6');
  return problems;
}

/** "35ABC123" -> "35 ABC 123" */
export function formatPlate(normalized) {
  const m = TR_PLATE_RE.exec(String(normalized ?? ''));
  return m ? `${m[1]} ${m[2]} ${m[3]}` : String(normalized ?? '');
}

/** Metni uygulamanin kurali ile normallestirir (bosluk/tire/nokta atilir, buyuk harf). Gecersizse null. */
export function normalizePlateText(text) {
  const plate = canonicalPlate(text);
  return TR_PLATE_RE.test(plate) ? plate : null;
}

/**
 * Tekil, gecerli, gercekci bir plaka uretir.
 * @param {{ weighted: Function, int: Function, pick: Function, next: Function }} rng util.makeRng() ciktisi
 * @param {Set<string>} taken bosluksuz kullanilmis plakalar (EKLENIR)
 * @returns {{ normalized: string, display: string, province: string, letters: string, digits: string }}
 */
export function generatePlate(rng, taken = new Set()) {
  for (let attempt = 0; attempt < 5000; attempt += 1) {
    const province = rng.weighted(PROVINCE_WEIGHTS);
    const [letterCount, digitCount] = rng.weighted(FORMAT_WEIGHTS);
    let letters = '';
    for (let i = 0; i < letterCount; i += 1) letters += PLATE_LETTERS[rng.int(0, PLATE_LETTERS.length - 1)];
    let digits = String(rng.int(1, 9));
    for (let i = 1; i < digitCount; i += 1) digits += String(rng.int(0, 9));
    if (!lettersAllowed(letters) || !digitsAllowed(digits)) continue;
    const normalized = `${province}${letters}${digits}`;
    if (taken.has(normalized) || plateProblems(normalized).length > 0) continue;
    taken.add(normalized);
    return { normalized, display: `${province} ${letters} ${digits}`, province, letters, digits };
  }
  throw new Error('Uygun plaka uretilemedi (5000 deneme).');
}
