// Kullanıcı metinlerinin (site / blok / kapı adı, adres, şehir, ilçe, not, gerekçe, arama) güvenli normalizasyonu. Saf: DB/ağ bağımsız.
//
// Neden: NUL (0x00) PostgreSQL metin sütununda 22021, tek başına (eşsiz) vekil karakter (surrogate) JSONB'de 22P05 hatası verir ve
// yön değiştiren / görünmez karakterler (ör. U+202E sağdan sola geçersiz kılma) arayüzde ve e-postada metni yanıltır. Bu hatalar 500
// üretmemeli ve bireysel kullanıcıdan süper kullanıcıya uzanan güven sınırını geçmemeli.
//
// Kaynakta Unicode kaçış dizisi KULLANILMAZ (araç zinciri bunları gerçek görünmez karaktere çevirebilir): kod noktaları sayıyla denetlenir.

const CHAR_TAB = 9;
const CHAR_LF = 10;
const CHAR_CR = 13;
const CHAR_DEL = 0x7f;
const CHAR_C1_LAST = 0x9f;
const CHAR_SOFT_HYPHEN = 0xad;
const CHAR_ARABIC_LETTER_MARK = 0x61c;
const CHAR_MONGOLIAN_VOWEL_SEPARATOR = 0x180e;
const CHAR_ZERO_WIDTH_FIRST = 0x200b; // 200B..200F: sıfır genişlik boşluğu, ZWNJ, ZWJ, LRM, RLM
const CHAR_ZWNJ = 0x200c;
const CHAR_ZWJ = 0x200d;
const CHAR_DIRECTION_MARK_LAST = 0x200f;
const CHAR_SEPARATOR_FIRST = 0x2028; // 2028..202E: satır / paragraf ayırıcı ve yön gömme / geçersiz kılma
const CHAR_BIDI_EMBEDDING_LAST = 0x202e;
const CHAR_WORD_JOINER_FIRST = 0x2060; // 2060..206F: kelime birleştirici, görünmez işleçler, eski biçimlendirme
const CHAR_FORMAT_LAST = 0x206f;
const CHAR_BOM = 0xfeff;
const CHAR_INTERLINEAR_FIRST = 0xfff9; // FFF9..FFFB: satırlar arası ek açıklama
const CHAR_INTERLINEAR_LAST = 0xfffb;
const CHAR_NONCHARACTER_FDD0 = 0xfdd0;
const CHAR_NONCHARACTER_FDEF = 0xfdef;
const CHAR_SURROGATE_FIRST = 0xd800;
const CHAR_SURROGATE_LAST = 0xdfff;
const CHAR_TAG_FIRST = 0xe0000;
const CHAR_TAG_LAST = 0xe007f;
const CODE_POINT_MAX = 0x10ffff;

/** Tek başına (eşsiz) vekil karakter: `for...of` bunları tek başlarına döndürür. */
export function isLoneSurrogate(code) {
  return code >= CHAR_SURROGATE_FIRST && code <= CHAR_SURROGATE_LAST;
}

/**
 * Atılacak kod noktası mı? C0/C1 kontrol karakterleri (`allowControls` verilenler hariç), DEL, eşsiz vekil, kalıcı olarak atanmamış
 * "noncharacter" değerler, yön / görünmez / biçimlendirme karakterleri. `keepJoiners`: ZWNJ ve ZWJ korunur (emoji dizileri için;
 * ad / adres alanlarında korunmaz).
 */
export function isDroppedCodePoint(code, { allowControls = [], keepJoiners = false } = {}) {
  if (code < 32) {
    return !allowControls.includes(code);
  }
  if (code >= CHAR_DEL && code <= CHAR_C1_LAST) {
    return true;
  }
  if (isLoneSurrogate(code) || code > CODE_POINT_MAX) {
    return true;
  }
  if (keepJoiners && (code === CHAR_ZWNJ || code === CHAR_ZWJ)) {
    return false;
  }
  return (
    code === CHAR_SOFT_HYPHEN ||
    code === CHAR_ARABIC_LETTER_MARK ||
    code === CHAR_MONGOLIAN_VOWEL_SEPARATOR ||
    (code >= CHAR_ZERO_WIDTH_FIRST && code <= CHAR_DIRECTION_MARK_LAST) ||
    (code >= CHAR_SEPARATOR_FIRST && code <= CHAR_BIDI_EMBEDDING_LAST) ||
    (code >= CHAR_WORD_JOINER_FIRST && code <= CHAR_FORMAT_LAST) ||
    code === CHAR_BOM ||
    (code >= CHAR_INTERLINEAR_FIRST && code <= CHAR_INTERLINEAR_LAST) ||
    (code >= CHAR_NONCHARACTER_FDD0 && code <= CHAR_NONCHARACTER_FDEF) ||
    (code & 0xfffe) === 0xfffe || // her düzlemdeki U+xFFFE / U+xFFFF
    (code >= CHAR_TAG_FIRST && code <= CHAR_TAG_LAST)
  );
}

/**
 * Metni güvenli hâle getirir (İDEMPOTENT: ikinci çağrı sonucu değiştirmez).
 *  - Eşsiz vekil, NUL ve diğer kontrol karakterleri, yön / görünmez karakterler atılır.
 *  - `multiline: false` (ad, şehir, ilçe): sekme ve satır sonları TEK boşluğa çevrilir.
 *  - `multiline: true` (adres): satır sonu LF olarak korunur (CRLF / CR -> LF), sekme boşluk olur.
 * Kırpma (trim) ÇAĞIRANIN işidir (önce sınırla sonra kırp: bkz. clipChars).
 */
export function cleanText(value, { multiline = false } = {}) {
  const text = String(value ?? '');
  let out = '';
  let previousWasCarriageReturn = false;
  for (const ch of text) {
    const code = ch.codePointAt(0);
    if (code === CHAR_CR) {
      out += multiline ? '\n' : ' ';
      previousWasCarriageReturn = true;
      continue;
    }
    if (code === CHAR_LF) {
      if (!previousWasCarriageReturn) {
        out += multiline ? '\n' : ' ';
      }
      previousWasCarriageReturn = false;
      continue;
    }
    previousWasCarriageReturn = false;
    if (code === CHAR_TAB) {
      out += ' ';
      continue;
    }
    if (isDroppedCodePoint(code)) {
      continue;
    }
    out += ch;
  }
  return out;
}

/**
 * En çok `max` KOD NOKTASI (vekil çiftleri bölünmez) tutar, SONRA kırpar. Böylece sınırda kalan boşluk saklanmaz ve
 * normalizasyon idempotent olur (kırp -> sınırla -> kırp).
 */
export function clipChars(text, max) {
  return Array.from(String(text)).slice(0, max).join('').trim();
}
