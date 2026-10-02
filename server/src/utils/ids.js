// Istekten gelen kimlik (id) degerlerini guvenli sekilde ayristirir.
// Number.isInteger(Number(x)) kalibi '1e3', '0x10', ' 12 ', 9007199254740993 gibi
// degerleri kabul edebiliyordu; burada yalnizca ondalik rakamlardan olusan,
// guvenli tamsayi araliginda (1..MAX) degerler kabul edilir.

export const INT32_MAX = 2147483647;

/**
 * @param {unknown} value  req.params / req.body / req.query degeri
 * @param {{ max?: number }} [options]  PostgreSQL INTEGER kolonlari icin max: INT32_MAX
 * @returns {number|null}  Gecerliyse pozitif guvenli tamsayi, degilse null
 */
export function parseId(value, { max = Number.MAX_SAFE_INTEGER } = {}) {
  let candidate;
  if (typeof value === 'number') {
    candidate = value;
  } else if (typeof value === 'string') {
    const text = value.trim();
    if (!/^\d{1,16}$/.test(text)) {
      return null;
    }
    candidate = Number(text);
  } else {
    return null;
  }

  if (!Number.isSafeInteger(candidate) || candidate <= 0 || candidate > max) {
    return null;
  }
  return candidate;
}

/**
 * Istege bagli id: alan hic gonderilmediyse (undefined/null/'') -> undefined,
 * gonderildi ama gecersizse -> null, gecerliyse -> sayi.
 */
export function parseOptionalId(value, options) {
  if (value === undefined || value === null || value === '') {
    return undefined;
  }
  return parseId(value, options);
}
