// Ortak hata siniflari. CLI cikis kodunu bunlar belirler: KullanimHatasi -> 2, IslemHatasi -> 1.

/** Komut satiri hatali kullanildi (eksik / bilinmeyen secenek, eksik yol). Cikis kodu 2. */
export class KullanimHatasi extends Error {
  constructor(mesaj) {
    super(mesaj);
    this.name = 'KullanimHatasi';
  }
}

/** Islem reddedildi ya da basarisiz oldu (dogrulama, guvenlik korumasi, dosya hatasi). Cikis kodu 1. */
export class IslemHatasi extends Error {
  constructor(mesaj) {
    super(mesaj);
    this.name = 'IslemHatasi';
  }
}

/**
 * Kullanicidan gelen metni hata mesajinda guvenle gostermek icin: denetim karakterleri (terminal kacis dizileri dahil) '?' olur,
 * uzun metin kisaltilir, sonuc tirnak icinde dondurulur.
 */
export function guvenliMetin(deger, azami = 80) {
  // eslint-disable-next-line no-control-regex -- denetim karakterlerini (C0, DEL, C1) bilerek ayiklar
  const metin = String(deger ?? '').replace(/[\u0000-\u001f\u007f-\u009f]/g, '?');
  return JSON.stringify(metin.length > azami ? `${metin.slice(0, azami)}...` : metin);
}
