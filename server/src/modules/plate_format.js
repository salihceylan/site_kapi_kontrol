// Türkiye plaka biçimi: TEK kural (saf, DB/ağ bağımsız). Plaka yazan / değiştiren her uç bunu kullanır; istemcideki
// lib/ui/helpers/plate_input.dart aynı kuralı uygular (il kodu 01-81 + 1-3 harf + 2-4 rakam).
//
// Depolanan biçim: `plate` = boşluksuz büyük harf ("34ABC123"), `plate_display` = "34 ABC 123". Kayıtlı ESKİ plakalar bu kurala
// uymayabilir: okuma / liste / pasife alma onlara dokunmaz; yalnız YENİ yazılan ya da DEĞİŞTİRİLEN değer burada doğrulanır.

import { PlatformError } from './errors.js';

const TR_LETTERS = Object.freeze({ Ç: 'C', Ğ: 'G', İ: 'I', Ö: 'O', Ş: 'S', Ü: 'U' });

/** Türkiye plakası: il kodu 01-81 + 1-3 harf + 2-4 rakam (toplam 5-9 karakter). */
export const TR_PLATE_RE = /^(0[1-9]|[1-7][0-9]|8[01])([A-Z]{1,3})([0-9]{2,4})$/;

/** Geçersiz plakada dönen 400 PLATE_INVALID (istemcideki `kPlateInvalidMessage` ile aynı metin). */
export const plateInvalid = () => new PlatformError(400, 'PLATE_INVALID', 'Plaka biçimi geçersiz. Örnek: 34 ABC 123 (il kodu 01-81).');

/** Boşluk / tire / nokta atılır, büyük harf, Türkçe harfler ASCII'ye indirilir. Biçim DOĞRULANMAZ. Metin değilse ya da 24 karakterden uzunsa ''. */
export function canonicalPlate(value) {
  if (typeof value !== 'string' || value.length > 24) return '';
  return value
    .replace(/[\s\-._]/g, '')
    .toUpperCase()
    .replace(/[ÇĞİÖŞÜ]/g, (ch) => TR_LETTERS[ch]);
}

/** Geçerli TR plakası ("34ABC123") ya da null. */
export function normalizeTrPlate(value) {
  const plate = canonicalPlate(value);
  return TR_PLATE_RE.test(plate) ? plate : null;
}

/** Girdiyi doğrular; geçersizse 400 PLATE_INVALID. */
export function requireTrPlate(value) {
  const plate = normalizeTrPlate(value);
  if (!plate) throw plateInvalid();
  return plate;
}

/** "34ABC123" -> "34 ABC 123" (biçim geçersizse olduğu gibi). */
export function formatPlate(plate) {
  const match = TR_PLATE_RE.exec(String(plate ?? ''));
  return match ? `${match[1]} ${match[2]} ${match[3]}` : String(plate ?? '');
}

/** Geçerliyse { plate: "34ABC123", display: "34 ABC 123" }, değilse null (hem `plate` hem `plate_display` sütununa yazılacak çift). */
export function parseTrPlate(value) {
  const plate = normalizeTrPlate(value);
  return plate ? { plate, display: formatPlate(plate) } : null;
}

/** [parseTrPlate] gibi; geçersizse 400 PLATE_INVALID. */
export function requireTrPlateEntry(value) {
  const entry = parseTrPlate(value);
  if (!entry) throw plateInvalid();
  return entry;
}
