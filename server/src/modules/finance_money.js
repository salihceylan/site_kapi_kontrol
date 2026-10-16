// Aidat ve Finans (Faz 4a) para yardımcıları. Saf: DB/ağ bağımsız.
//
// Sözleşme: docs/PLATFORM_FINANS.md ("İlkeler" madde 1). PARA = TAMSAYI KURUŞ (`*_minor`, BIGINT); JSON'da tamsayı.
// HİÇBİR yerde kayan nokta ile para hesabı yapılmaz: ondalık sayı, toFixed, parseFloat ve Math.round bu dosyalarda KULLANILMAZ
// (kaynak koruma testi finance_*.js dosyalarını tarar). Toplama, bölme ve dağıtım BigInt ile yapılır; JSON'a yalnız güvenli
// tamsayı olarak çıkar.

export const CURRENCY = 'TRY';

/** Tek bir tutar (daire başı borç, tahsilat, toplam tutar) için üst sınır: 10^12 kuruş = 10 milyar TL. */
export const MAX_AMOUNT_MINOR = 1_000_000_000_000;

/** Tek bir borçlandırmanın toplamı için üst sınır (JSON güvenli tamsayı aralığının çok altında). */
export const MAX_RUN_TOTAL_MINOR = 100_000_000_000_000;

/** Gövdeden gelen kuruş değeri: yalnızca JSON TAMSAYI (metin, ondalık, NaN, sonsuz ve güvenli aralık dışı reddedilir). */
export function isMinorInteger(value) {
  return typeof value === 'number' && Number.isSafeInteger(value);
}

/**
 * Kuruş girdisini doğrular. Geçerliyse aynı sayıyı, değilse null döner (çağıran alan adıyla INVALID_BODY üretir).
 * Varsayılan aralık 1..MAX_AMOUNT_MINOR; sıfıra izin için { min: 0 }.
 */
export function parseMinor(value, { min = 1, max = MAX_AMOUNT_MINOR } = {}) {
  if (!isMinorInteger(value) || value < min || value > max) {
    return null;
  }
  return value;
}

const DIGITS = /^-?\d{1,30}$/;

/** number (güvenli tamsayı) | bigint | rakam metni (pg BIGINT/NUMERIC çıktısı) -> bigint. Başka her şey hata. */
export function toBigInt(value) {
  if (typeof value === 'bigint') {
    return value;
  }
  if (typeof value === 'number') {
    if (!Number.isSafeInteger(value)) {
      throw new RangeError('finance: tutar güvenli tamsayı değil');
    }
    return BigInt(value);
  }
  if (typeof value === 'string' && DIGITS.test(value.trim())) {
    return BigInt(value.trim());
  }
  throw new TypeError('finance: tutar tamsayı değil');
}

const SAFE_MAX = BigInt(Number.MAX_SAFE_INTEGER);
const SAFE_MIN = -SAFE_MAX;

/**
 * bigint | rakam metni | number -> JSON'a çıkacak tamsayı. Güvenli aralığın dışındaysa HATA fırlatır (tutar sessizce bozulmaz;
 * üst sınırlar nedeniyle pratikte ulaşılamaz).
 */
export function minorToNumber(value) {
  if (value === null || value === undefined) {
    return 0;
  }
  const big = toBigInt(value);
  if (big > SAFE_MAX || big < SAFE_MIN) {
    throw new RangeError('finance: tutar JSON güvenli aralığını aşıyor');
  }
  return Number(big);
}

/** Null korumalı varyant: null/undefined -> null. */
export function minorToNumberOrNull(value) {
  return value === null || value === undefined ? null : minorToNumber(value);
}

/** bigint dizisini toplar (boş dizi 0n). */
export function sumBig(values) {
  let total = 0n;
  for (const value of values) {
    total += value;
  }
  return total;
}

/** bigint dizisini SQL `bigint[]` parametresi için metin dizisine çevirir (pg dizi serileştirmesi metni güvenle kabul eder). */
export function bigintsToSqlArray(values) {
  return values.map((value) => value.toString());
}
