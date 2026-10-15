// Duyuru arka plan işleri (zamanlayıcı, e-posta kuyruğu) için süreçler arası TEK ÇALIŞAN kilidi.
//
// pg_try_advisory_lock OTURUM düzeyindedir: kilidi tutan bağlantı havuzdan ayrı tutulur ve iş bitince kilit açılıp bağlantı iade edilir
// (açma başarısız olursa bağlantı yok edilir; böylece kilit asla havuzda "asılı" kalmaz). Süreç ölürse bağlantı kopar ve kilit düşer.

import { pool } from '../db.js';

/**
 * @param {string} key kilit anahtarı (hashtext ile sayıya çevrilir)
 * @returns {Promise<{ release: () => Promise<void> } | null>} kilit başka yerdeyse null
 */
export async function acquireSessionLock(key) {
  const client = await pool.connect();
  const result = await client.query('SELECT pg_try_advisory_lock(hashtext($1)) AS locked', [key]).catch((error) => {
    client.release(true);
    throw error;
  });
  if (result.rows?.[0]?.locked !== true) {
    client.release();
    return null;
  }
  return {
    async release() {
      try {
        await client.query('SELECT pg_advisory_unlock(hashtext($1))', [key]);
        client.release();
      } catch (_error) {
        client.release(true);
      }
    },
  };
}
