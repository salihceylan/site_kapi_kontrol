// Plaka metni normallestirme: server/src/modules/plate_recognition_common.js canonicalPlate() ile AYNI kural (bosluk / tire / nokta / alt cizgi atilir,
// buyuk harf, Turkce harfler ASCII'ye iner). Sunucu koduna bagimlilik olmasin diye burada tekrarlanir; testte sunucudaki islevle karsilastirilir.

const TR_LETTERS = { Ç: 'C', Ğ: 'G', İ: 'I', Ö: 'O', Ş: 'S', Ü: 'U' };

export function canonicalPlate(value) {
  if (typeof value !== 'string' || value.length > 24) return '';
  return value
    .replace(/[\s\-._]/g, '')
    .toUpperCase()
    .replace(/[ÇĞİÖŞÜ]/g, (ch) => TR_LETTERS[ch]);
}
