// Duyuru e-posta kuyruğu: kalıcı (DB), sunucu yeniden başlarsa kaldığı yerden sürer.
//
// Sözleşme: docs/PLATFORM_DUYURU.md ("E-posta"). SMTP YAVAŞ / BAŞARISIZ varsayılır; yayın isteği gönderimi BEKLEMEZ (yayından sonra
// kuyruk tetiklenir, zamanlayıcı tikinde bekleyen varsa sürer).
//  - Tek çalışan: oturum düzeyi advisory kilit (announcement_lock.js); satır seçimi FOR UPDATE SKIP LOCKED ile ayrıca korunur.
//  - 20'lik gruplar, gruplar arası >= 150 ms. Kısa "talep" transaction'ı gönderimden ÖNCE email_attempts'ı artırır ve kilidi bırakır;
//    gönderim transaction DIŞINDADIR (yavaş SMTP satır kilidi / bağlantı tutmaz, "okundu" yazımını bekletmez); sonuç kısa bir UPDATE ile yazılır.
//  - Başarı -> 'sent'; hata -> deneme sayısı kalır ve satır 'pending' kalır, MAX_EMAIL_ATTEMPTS (3) denemede 'failed'. Son durumda `email` NULL.
//    Aynı çalıştırmada bir satır en çok BİR kez denenir (kesintideki SMTP'ye saniyeler içinde 3 deneme yakılmaz; yeniden deneme sonraki tikte).
//  - SMTP yapılandırılmamışsa bekleyen satırlar 'failed' olur (sessiz kayıp yok, istatistikte görünür).
//  - Çökme sonrası: gönderim sırasında süreç ölürse satır 'pending' ve denemesi artmış kalır; bir sonraki çalıştırma sürdürür (en az bir kez
//    gönderim). Denemesi tükenmiş artıklar 'failed' yapılır.
//  - Log'a e-posta adresi / başlık YAZILMAZ; yalnız sayılar ve hata kodları.

import { pool } from '../db.js';
import { isSmtpConfigured, sendAnnouncementEmail } from '../mailer.js';
import { MAX_EMAIL_ATTEMPTS } from './announcement_common.js';
import { acquireSessionLock } from './announcement_lock.js';

export const EMAIL_QUEUE_LOCK_KEY = 'announcement_email_queue';
export const EMAIL_BATCH_SIZE = 20;
export const EMAIL_BATCH_DELAY_MS = 150;
export const EMAIL_SEND_CONCURRENCY = 4;
export const EMAIL_MAX_RUN_MS = 15 * 60 * 1000;

/** Test / QA için değiştirilebilir bağımlılıklar (gerçek SMTP'ye bağlanmayan sahte taşıyıcı bile mailer düzeyinde kurulur). */
export const emailQueueHooks = {
  send: (message) => sendAnnouncementEmail(message),
  sleep: (ms) => new Promise((resolve) => setTimeout(resolve, ms)),
  now: () => Date.now(),
};

let activeRun = null;
let stopRequested = false;

/** Bekleyen e-posta var mı (kısmi indeks; hafif). */
export async function hasPendingEmails(db = pool) {
  const result = await db.query(`SELECT 1 FROM announcement_recipients WHERE email_status = 'pending' LIMIT 1`);
  return Boolean(result.rows?.[0]);
}

async function failExhaustedRows(db) {
  const result = await db.query(
    `
      UPDATE announcement_recipients
      SET email_status = 'failed', email = NULL
      WHERE email_status = 'pending' AND (email_attempts >= $1 OR email IS NULL)
    `,
    [MAX_EMAIL_ATTEMPTS],
  );
  return Number(result.rowCount ?? 0);
}

async function failAllPending(db) {
  const result = await db.query(
    `UPDATE announcement_recipients SET email_status = 'failed', email = NULL WHERE email_status = 'pending'`,
  );
  return Number(result.rowCount ?? 0);
}

/** Bir grup bekleyen satırı talep eder (FOR UPDATE SKIP LOCKED) ve denemelerini artırır; bu çalıştırmada denenenler hariç tutulur. */
async function claimBatch(batchSize, attempted) {
  const client = await pool.connect();
  let began = false;
  try {
    await client.query('BEGIN');
    began = true;
    const picked = await client.query(
      `
        SELECT r.announcement_id, r.person_id, r.email, r.email_attempts, a.title, a.body, a.importance, s.name AS site_name
        FROM announcement_recipients r
        INNER JOIN announcements a ON a.id = r.announcement_id
        INNER JOIN sites s ON s.site_code = a.site_code
        WHERE r.email_status = 'pending'
          AND r.email IS NOT NULL
          AND r.email_attempts < $1
          AND a.status = 'published'
          AND NOT EXISTS (
            SELECT 1 FROM unnest($2::BIGINT[], $3::BIGINT[]) AS done(aid, pid)
            WHERE done.aid = r.announcement_id AND done.pid = r.person_id
          )
        ORDER BY r.announcement_id, r.person_id
        LIMIT $4
        FOR UPDATE OF r SKIP LOCKED
      `,
      [MAX_EMAIL_ATTEMPTS, attempted.announcementIds, attempted.personIds, batchSize],
    );
    const rows = picked.rows ?? [];
    if (rows.length > 0) {
      await client.query(
        `
          UPDATE announcement_recipients r
          SET email_attempts = r.email_attempts + 1
          FROM unnest($1::BIGINT[], $2::BIGINT[]) AS v(aid, pid)
          WHERE r.announcement_id = v.aid AND r.person_id = v.pid
        `,
        [rows.map((row) => row.announcement_id), rows.map((row) => row.person_id)],
      );
    }
    await client.query('COMMIT');
    return rows.map((row) => ({ ...row, attempts: Number(row.email_attempts) + 1 }));
  } catch (error) {
    if (began) {
      try {
        await client.query('ROLLBACK');
      } catch (_rollbackError) {
        // bağlantı zaten kopmuş olabilir
      }
    }
    throw error;
  } finally {
    client.release();
  }
}

async function sendOne(row) {
  try {
    await emailQueueHooks.send({
      to: row.email,
      siteName: row.site_name,
      title: row.title,
      body: row.body,
      importance: row.importance,
    });
    return { row, ok: true, permanent: false, code: null };
  } catch (error) {
    return {
      row,
      ok: false,
      permanent: error?.code === 'INVALID_RECIPIENT',
      code: String(error?.code ?? error?.responseCode ?? 'SEND_FAILED'),
    };
  }
}

async function sendAll(rows, concurrency) {
  const results = new Array(rows.length);
  let cursor = 0;
  const worker = async () => {
    while (cursor < rows.length) {
      const index = cursor;
      cursor += 1;
      results[index] = await sendOne(rows[index]);
    }
  };
  await Promise.all(Array.from({ length: Math.min(concurrency, rows.length) }, worker));
  return results;
}

/** Sonuçları yazar: başarı 'sent'; kalıcı hata ya da denemesi tükenen 'failed'; geri kalan 'pending' kalır. email her son durumda NULL. */
async function finalizeBatch(results) {
  const aids = [];
  const pids = [];
  const states = [];
  for (const result of results) {
    if (result.ok) {
      aids.push(result.row.announcement_id);
      pids.push(result.row.person_id);
      states.push('sent');
    } else if (result.permanent || result.row.attempts >= MAX_EMAIL_ATTEMPTS) {
      aids.push(result.row.announcement_id);
      pids.push(result.row.person_id);
      states.push('failed');
    }
  }
  if (aids.length === 0) {
    return;
  }
  await pool.query(
    `
      UPDATE announcement_recipients r
      SET email_status = v.st, email = NULL
      FROM unnest($1::BIGINT[], $2::BIGINT[], $3::TEXT[]) AS v(aid, pid, st)
      WHERE r.announcement_id = v.aid AND r.person_id = v.pid AND r.email_status = 'pending'
    `,
    [aids, pids, states],
  );
}

/**
 * Kuyruğu bir kez boşaltmaya çalışır (tek çalışan kilidi alınamazsa { skipped: 'locked' }). Ağ/DB hatası yukarı fırlar
 * (kickEmailQueue yakalar ve loglar).
 * @returns {Promise<{ skipped?: string, smtp?: boolean, sent?: number, failed?: number, pendingRetry?: number, batches?: number }>}
 */
export async function runEmailQueue({
  batchSize = EMAIL_BATCH_SIZE,
  batchDelayMs = EMAIL_BATCH_DELAY_MS,
  maxRunMs = EMAIL_MAX_RUN_MS,
  concurrency = EMAIL_SEND_CONCURRENCY,
} = {}) {
  const lock = await acquireSessionLock(EMAIL_QUEUE_LOCK_KEY);
  if (!lock) {
    return { skipped: 'locked' };
  }
  const summary = { smtp: true, sent: 0, failed: 0, pendingRetry: 0, batches: 0 };
  try {
    summary.failed += await failExhaustedRows(pool);
    if (!isSmtpConfigured()) {
      summary.smtp = false;
      summary.failed += await failAllPending(pool);
      return summary;
    }
    const attempted = { announcementIds: [], personIds: [] };
    const startedAt = emailQueueHooks.now();
    while (!stopRequested && emailQueueHooks.now() - startedAt < maxRunMs) {
      const claimed = await claimBatch(batchSize, attempted);
      if (claimed.length === 0) {
        break;
      }
      summary.batches += 1;
      for (const row of claimed) {
        attempted.announcementIds.push(row.announcement_id);
        attempted.personIds.push(row.person_id);
      }
      const results = await sendAll(claimed, concurrency);
      await finalizeBatch(results);
      const codes = new Set();
      for (const result of results) {
        if (result.ok) {
          summary.sent += 1;
        } else if (result.permanent || result.row.attempts >= MAX_EMAIL_ATTEMPTS) {
          summary.failed += 1;
          codes.add(result.code);
        } else {
          summary.pendingRetry += 1;
          codes.add(result.code);
        }
      }
      if (codes.size > 0) {
        // eslint-disable-next-line no-console
        console.error(`[announcement-email] gonderim hatasi: kodlar=${[...codes].join(',')}`);
      }
      await emailQueueHooks.sleep(batchDelayMs);
    }
    return summary;
  } finally {
    await lock.release();
  }
}

/**
 * Kuyruğu arka planda başlatır (bekletmez). Çalışan bir tur varsa onu döndürür. Hata sunucuyu düşürmez; yalnız loglanır.
 * @returns {Promise<object>} turun özeti (beklemek isteyen test / QA içindir)
 */
export function kickEmailQueue(options = {}) {
  if (stopRequested) {
    return Promise.resolve({ skipped: 'stopping' });
  }
  if (activeRun) {
    return activeRun;
  }
  activeRun = runEmailQueue(options)
    .catch((error) => {
      // eslint-disable-next-line no-console
      console.error('[announcement-email] kuyruk turu basarisiz:', error?.code || error?.message || 'hata');
      return { error: String(error?.code || 'ERROR') };
    })
    .finally(() => {
      activeRun = null;
    });
  return activeRun;
}

/** Kapanış: yeni tur başlatmaz ve çalışan turun grup sonunda durmasını bekler. */
export function stopEmailQueue() {
  stopRequested = true;
  return activeRun ?? Promise.resolve(null);
}

/** Zamanlayıcı yeniden başladığında / testlerde durdurma işaretini sıfırlar. */
export function resumeEmailQueue() {
  stopRequested = false;
}
