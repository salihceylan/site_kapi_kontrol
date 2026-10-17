// Duyuru arka plan işleri (zamanlayıcı, e-posta kuyruğu) için süreçler arası TEK ÇALIŞAN kilidi.
//
// pg_try_advisory_lock OTURUM düzeyindedir: kilidi tutan bağlantı havuzdan ayrı tutulur ve iş bitince kilit açılıp bağlantı iade edilir
// (açma başarısız olursa bağlantı yok edilir; böylece kilit asla havuzda "asılı" kalmaz). Süreç ölürse bağlantı kopar ve kilit düşer.
//
// ANAHTAR UZAYI: tek int4 `hashtext(...)` anahtarlar kullanıcı denetimli metinlerle (örn. `email_verify:${email}`) çakışabilir. Bu
// dosyadaki arka plan kilitleri İKİ-int biçimini (sınıf, iş) kullanır; bu, tek-bigint/tek-int anahtar uzayından ayrı bir uzaydır ve
// kullanıcı girdisinden etkilenmez. Mevcut `people_sync:<site>` kilitlerinin biçimi (Faz 2) DEĞİŞMEDİ.
//
// Boştaki (iş yürütmeyen) bağlantı kopunca pg istemcisi 'error' yayar; dinleyicisi olmayan istemcide bu süreci düşürürdü (uncaughtException).
// Kilit tutan istemciye hata dinleyicisi eklenir.

import { pool } from '../db.js';

export const ANNOUNCEMENT_LOCK_CLASS = 0x414e4e43; // 1095650883 = "ANNC" (ASCII)
// Aynı sınıfı kullanan HER iş burada, tekil numarayla (çakışan numara iki işi sessizce birbirine bekletir).
export const ANNOUNCEMENT_LOCK_JOBS = Object.freeze({
  scheduler: 1,
  emailQueue: 2,
  emailGlobal: 3,
  financeReminder: 4, // finans borç hatırlatma kuyruğu (finance_reminder_queue.js)
  pushQueue: 5, // telefon bildirimi kuyruğu + bakımı (Faz 3b-B, push_worker.js)
});

/**
 * @param {number} job ANNOUNCEMENT_LOCK_JOBS değerlerinden biri
 * @returns {Promise<{ release: () => Promise<void> } | null>} kilit başka yerdeyse null
 */
export async function acquireSessionLock(job) {
  const client = await pool.connect();
  const onError = (error) => {
    // eslint-disable-next-line no-console
    console.error('[announcement-lock] baglanti hatasi (kilit duser):', error?.code || 'hata');
  };
  client.on('error', onError);
  const result = await client
    .query('SELECT pg_try_advisory_lock($1::int, $2::int) AS locked', [ANNOUNCEMENT_LOCK_CLASS, job])
    .catch((error) => {
      client.release(true);
      throw error;
    });
  if (result.rows?.[0]?.locked !== true) {
    client.off('error', onError);
    client.release();
    return null;
  }
  return {
    async release() {
      try {
        await client.query('SELECT pg_advisory_unlock($1::int, $2::int)', [ANNOUNCEMENT_LOCK_CLASS, job]);
        client.off('error', onError);
        client.release();
      } catch (_error) {
        // bağlantı kopmuş olabilir: istemci yok edilir (oturum kilidi bağlantıyla birlikte düşer); dinleyici yok edilen istemcide kalır
        client.release(true);
      }
    },
  };
}
