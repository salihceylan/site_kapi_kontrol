// Hassas hesap işlemleri (hesap silme, veri dışa aktarma) için "mevcut parola" doğrulaması.
//
// PATCH /me ve daire sakini change-password ile AYNI hesap-bazlı izleyiciyi PAYLAŞIR (passwordChangeFailureTracker, anahtar `u:<user_code>`):
// bu uçlardan biriyle yapılan toplam 5 hatalı deneme 15 dk kilit (429 CURRENT_PASSWORD_LOCKED) üretir; bütçe ortaktır.
//
// FARK (yarış güvenliği): PATCH /me önce `check`, sonra (yavaş, asenkron) bcrypt karşılaştırması, EN SON `recordFailure` yapar. Çalınmış bir oturumla
// paralel gönderilen N istek karşılaştırmadan ÖNCE hepsi `check`'ten geçer ve N tahmin yapılabilir. Burada hata hakkı karşılaştırmadan ÖNCE
// (eşzamanlı, await yok) rezerve edilir; en çok `maxFailures` karşılaştırma çalışır, kalanlar 429 alır. Başarıda sayaç sıfırlanır. Sıralı kullanımda
// gözlenen davranış PATCH /me ile aynıdır (5. hatalı deneme 429, 6. istek karşılaştırmasız 429).
//
// Parola ASLA log'a yazılmaz. Silinmiş hesap için 401 ACCOUNT_DELETED (çift gönderim yarışında kaybeden istek yanıltıcı "parola hatalı" almasın).

import bcrypt from 'bcryptjs';
import { pool } from '../db.js';
import { passwordChangeFailureTracker, passwordChangeThrottleKey } from '../middlewares/login_throttle.js';
import { getDummyPasswordHash } from '../security/password_hashing.js';
import {
  accountDeleted,
  currentPasswordInvalid,
  currentPasswordLocked,
  currentPasswordRequired,
} from './account_common.js';

/** bcrypt yalnızca ilk 72 baytı kullanır; sınırsız uzunluktaki girdiyle CPU harcatılmasın diye üst sınır (parola ilkesi en çok 128). */
export const MAX_CURRENT_PASSWORD_LENGTH = 1024;

// Kullanıcı/hash yokken de bcrypt maliyeti ödenir (yanıt süresinden hesap durumu çıkarılamasın). Sahte özet ASENKRON ve tembel üretilir
// (içe aktarma maliyeti yok; olay döngüsü kilitlenmez): security/password_hashing.js getDummyPasswordHash (BCRYPT_COST, önbellekli söz).
const dummyPasswordHash = getDummyPasswordHash;

/** Test / QA için değiştirilebilir bağımlılıklar. */
export const passwordGuardDeps = {
  tracker: passwordChangeFailureTracker,
  loadUser: async (userCode) => {
    // Silinmiş (deleted_at dolu) hesap satırı HİÇ okunmaz: "yok" ile aynı (401 ACCOUNT_DELETED).
    const result = await pool.query('SELECT password_hash FROM users WHERE user_code = $1 AND deleted_at IS NULL LIMIT 1', [userCode]);
    return result.rows?.[0] ?? null;
  },
  compare: (plain, hash) => bcrypt.compare(plain, hash),
};

/**
 * Mevcut parolayı doğrular; başarısızlıkta PlatformError fırlatır.
 *  - 400 CURRENT_PASSWORD_REQUIRED: parola gönderilmedi / boş
 *  - 400 CURRENT_PASSWORD_INVALID : yanlış (sayaç ilerler)
 *  - 429 CURRENT_PASSWORD_LOCKED  : kilitli (retry_after_seconds + route Retry-After)
 *  - 401 ACCOUNT_DELETED          : hesap silinmiş / yok
 * @param {{ userCode: number, currentPassword: unknown }} input
 */
export async function verifyCurrentPassword({ userCode, currentPassword }, deps = passwordGuardDeps) {
  // Giriş (login) parolayı trim eder; saklanan parolalar hep trim'lidir -> mevcut parola da aynı şekilde trim edilir.
  if (currentPassword === undefined || currentPassword === null) {
    throw currentPasswordRequired();
  }
  const typeIsString = typeof currentPassword === 'string';
  const password = typeIsString ? currentPassword.trim() : '';
  if (typeIsString && password === '') {
    throw currentPasswordRequired();
  }

  const key = passwordChangeThrottleKey(userCode);
  const state = deps.tracker.check(key);
  if (state.locked) {
    throw currentPasswordLocked(state.retryAfterSeconds);
  }
  // Hata hakkını karşılaştırmadan ÖNCE rezerve et (paralel tahminleri keser); doğru parolada sıfırlanır.
  const reserved = deps.tracker.recordFailure(key);

  const user = await deps.loadUser(userCode);
  if (!user || user.deleted_at) {
    deps.tracker.recordSuccess(key);
    throw accountDeleted();
  }
  const storedHash = user.password_hash ? String(user.password_hash) : '';
  let matches = false;
  if (typeIsString && password.length <= MAX_CURRENT_PASSWORD_LENGTH) {
    matches = await deps.compare(password, storedHash || (await dummyPasswordHash()));
  }
  if (!storedHash || !matches) {
    if (reserved.locked) {
      throw currentPasswordLocked(reserved.retryAfterSeconds);
    }
    throw currentPasswordInvalid();
  }
  deps.tracker.recordSuccess(key);
}
