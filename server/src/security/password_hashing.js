// Parola özeti maliyeti (bcrypt) — TEK sabit.
//
// Neden tek sabit: girişte hesap yoksa (ya da özet kullanılamazsa) karşılaştırma aynı maliyetteki sahte bir özetle
// yapılır. Bazı hesaplar daha yüksek maliyetle (ör. 12) özetlenirse "yanlış parola" yanıt süresi (~270 ms) olmayan
// hesaptan (~70 ms) ayrışır ve hesap varlığı süreden anlaşılır. Bu yüzden yeni / değişen / sıfırlanan tüm parolalar ve
// tüm sahte özetler BCRYPT_COST ile üretilir. (Eskiden 12 ile özetlenmiş birkaç özet yerinde kalır; sahibi parolasını
// değiştirince BCRYPT_COST'a geçer.)

import crypto from 'node:crypto';
import bcrypt from 'bcryptjs';

export const BCRYPT_COST = 10;

/** Yeni parola özeti (BCRYPT_COST). */
export function hashPassword(plain) {
  return bcrypt.hash(String(plain), BCRYPT_COST);
}

let dummyHashPromise = null;

/**
 * Sahte parola özeti (BCRYPT_COST): hesap yokken / saklı özet kullanılamazken de gerçek bir karşılaştırma maliyeti ödenir (yanıt süresinden hesap
 * varlığı çıkarılamasın). ASENKRON üretilir (bcrypt.hash): eski `hashSync` olay döngüsünü ~70-100 ms kilitliyordu (DoS yüzeyi: login_guard / parola
 * koruyucusu tembel üretimi tam istek anında yapardı). Söz önbelleğe alınır: eşzamanlı çağıranlar TEK özeti bekler; üretim hata verirse önbellek
 * boşaltılır, bir sonraki çağrı yeniden dener. Özet rastgele tohumludur, hiçbir parola eşleşmez.
 * @returns {Promise<string>}
 */
export function getDummyPasswordHash() {
  if (dummyHashPromise === null) {
    const pending = bcrypt.hash(crypto.randomBytes(16).toString('hex'), BCRYPT_COST);
    dummyHashPromise = pending.catch((error) => {
      dummyHashPromise = null;
      throw error;
    });
  }
  return dummyHashPromise;
}

/** Özetin maliyeti ("$2a$10$..." -> 10); bcrypt biçiminde değilse null. */
export function bcryptCostOf(hash) {
  const match = /^\$2[abxy]\$(\d{2})\$/.exec(String(hash ?? ''));
  return match ? Number(match[1]) : null;
}
