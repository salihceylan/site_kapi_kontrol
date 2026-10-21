// TR IBAN yardımcıları (saf): normalleştirme, ISO 13616 mod-97 denetimi, gruplu gösterim ve maske.
// Banka adı tablosu YOKTUR (doğrulanamayan veri yazılmaz). Kopyalama boşluksuzdur.

/** Boşluk ve tireleri atar, büyük harfe çevirir. */
export function normalizeIban(value) {
  return String(value ?? '').replace(/[\s-]+/g, '').toUpperCase();
}

/** ISO 7064 mod 97-10 (parçalı, BigInt'siz). */
export function iban97(normalized) {
  const moved = normalized.slice(4) + normalized.slice(0, 4);
  let remainder = 0;
  for (const ch of moved) {
    const code = ch >= 'A' && ch <= 'Z' ? String(ch.charCodeAt(0) - 55) : ch;
    for (const digit of code) {
      remainder = (remainder * 10 + Number(digit)) % 97;
    }
  }
  return remainder;
}

/** Geçerli TR IBAN ise normalleştirilmiş değeri, değilse null döner. */
export function parseTrIban(value) {
  const normalized = normalizeIban(value);
  if (!/^TR[0-9]{24}$/.test(normalized)) return null;
  return iban97(normalized) === 1 ? normalized : null;
}

/** 4'lü gruplarla gösterim: 'TR33 0006 1005 ...'. */
export function formatIban(value) {
  return normalizeIban(value).replace(/(.{4})/g, '$1 ').trim();
}

/** Maske: 'TR** … 1234' (yalnız son 4 hane). */
export function maskIban(value) {
  const normalized = normalizeIban(value);
  return normalized.length < 8 ? 'TR** …' : `${normalized.slice(0, 2)}** … ${normalized.slice(-4)}`;
}
