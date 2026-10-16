// Duyuru e-posta kuyruğu: kalıcı (DB), sunucu yeniden başlarsa kaldığı yerden sürer.
//
// Sözleşme: docs/PLATFORM_DUYURU.md ("E-posta"). SMTP YAVAŞ / BAŞARISIZ varsayılır; yayın isteği gönderimi BEKLEMEZ (yayından sonra
// kuyruk tetiklenir, zamanlayıcı tikinde bekleyen varsa sürer).
//  - Tek çalışan: oturum düzeyi advisory kilit (announcement_lock.js, iki-int anahtar); satır seçimi FOR UPDATE SKIP LOCKED ile ayrıca korunur.
//  - 20'lik gruplar, gruplar arası >= 150 ms. Kısa "talep" transaction'ı gönderimden ÖNCE email_attempts'ı artırır, satırı
//    `email_claimed_at` ile işaretler ve kilidi bırakır; gönderim transaction DIŞINDADIR (yavaş SMTP satır kilidi / bağlantı tutmaz,
//    "okundu" yazımını bekletmez); sonuç kısa bir UPDATE ile yazılır.
//  - TALEP EDİLMİŞ (yoldaki) satır geri çekmede iptal EDİLMEZ (geri çekme yalnız email_claimed_at IS NULL satırları iptal eder); sonuç
//    yazımı bu satırı sent / failed yapar, istatistik ve günlük kota gerçeği yansıtır. Talebi 10 dk'dan eski satır (süreç çökmüş) yeniden
//    talep edilebilir; yayından kalkmış (geri çekilmiş) duyurunun bayat talepleri failed yapılır.
//  - Talep anında kişi hâlâ etkin ve adres hâlâ kişinin GÜNCEL iletişim adresiyse gönderilir; değilse satır 'none' (adres NULL); adres bu
//    arada bastırma listesine girdiyse 'skipped_pref'. Gönderimde kişinin hesabı olup olmadığına göre doğru altbilgi + abonelikten çık
//    bağlantısı (List-Unsubscribe) eklenir.
//  - Başarı -> 'sent'; geçici hata -> satır 'pending' kalır, `email_next_at` ile geri çekilme (1 dk, 5 dk) ve MAX_EMAIL_ATTEMPTS (3)
//    denemede 'failed'; KALICI SMTP hatası (alıcı reddi / 5xx) hemen 'failed'. Son durumda `email` NULL. Aynı çalıştırmada bir satır en
//    çok BİR kez denenir.
//  - SMTP yapılandırılmamışsa bekleyen satırlar 'failed' olur (sessiz kayıp yok, istatistikte görünür).
//  - Log'a e-posta adresi / başlık YAZILMAZ; yalnız sayılar ve hata kodları.

import { pool } from '../db.js';
import { isSmtpConfigured, sendAnnouncementEmail } from '../mailer.js';
import {
  EMAIL_CLAIM_STALE_MINUTES,
  EMAIL_RETRY_DELAYS_SECONDS,
  MAX_EMAIL_ATTEMPTS,
} from './announcement_common.js';
import { emailHashSalts, hashEmail, unsubscribeUrl } from './announcement_email_security.js';
import { ANNOUNCEMENT_LOCK_JOBS, acquireSessionLock } from './announcement_lock.js';
import { deliverableEmailSql, suppressedSql } from './announcement_recipients.js';
import { HAS_ACCOUNT_SQL } from './people_common.js';
import { CONTACT_EMAIL_SQL, PERSON_FROM } from './people_service.js';

export const EMAIL_QUEUE_LOCK_JOB = ANNOUNCEMENT_LOCK_JOBS.emailQueue;
export const EMAIL_BATCH_SIZE = 20;
export const EMAIL_BATCH_DELAY_MS = 150;
export const EMAIL_SEND_CONCURRENCY = 4;
export const EMAIL_MAX_RUN_MS = 15 * 60 * 1000;
/** Adres özetleri (email_hash) bu kadar gün sonra satırlardan silinir (günlük sayım yalnız bugünü kullanır). Bastırma listesi kalıcıdır. */
export const EMAIL_HASH_RETENTION_DAYS = 3;

/** Test / QA için değiştirilebilir bağımlılıklar (gerçek SMTP'ye bağlanmayan sahte taşıyıcı bile mailer düzeyinde kurulur). */
export const emailQueueHooks = {
  send: (message) => sendAnnouncementEmail(message),
  sleep: (ms) => new Promise((resolve) => setTimeout(resolve, ms)),
  now: () => Date.now(),
};

let activeRun = null;
let stopRequested = false;

/**
 * İŞİ OLAN bekleyen e-posta var mı (kısmi indeks; hafif): YAYINDAKİ duyurunun, geri çekilmesi dolmuş (email_next_at) ve başka işçinin taze
 * talebinde olmayan satırları. Yayından kalkmış (geri çekilmiş) duyurunun artık gönderilmeyecek satırları SAYILMAZ (bunları failStaleRows
 * kapatır): aksi halde kuyruk her tikte boşuna dönerdi.
 */
export async function hasPendingEmails(db = pool) {
  const result = await db.query(
    `
      SELECT 1
      FROM announcement_recipients r
      INNER JOIN announcements a ON a.id = r.announcement_id AND a.status = 'published'
      WHERE r.email_status = 'pending'
        AND (r.email_next_at IS NULL OR r.email_next_at <= NOW())
        AND (r.email_claimed_at IS NULL OR r.email_claimed_at < NOW() - make_interval(mins => $1::INTEGER))
      LIMIT 1
    `,
    [EMAIL_CLAIM_STALE_MINUTES],
  );
  return Boolean(result.rows?.[0]);
}

/**
 * Kalıcı hatalı satırları kapatır: adresi olmayan, denemesi tükenmiş (yoldaki gönderim olabilecek taze talepler hariç) ve YAYINDA OLMAYAN
 * (geri çekilmiş) duyurunun pending satırları (talep edilmemiş ya da bayat talepli; taze talep, işçi sonucu yazana dek dokunulmaz) 'failed'
 * olur (adres ve özet NULL). Zamanlayıcı her tikte de çağırır: kuyruk turu tetiklenmese bile sahipsiz satır düz adresle DB'de kalmaz.
 * @returns {Promise<number>} kapatılan satır sayısı
 */
export async function failStaleRows(db) {
  const exhausted = await db.query(
    `
      UPDATE announcement_recipients
      SET email_status = 'failed', email = NULL, email_claimed_at = NULL, email_next_at = NULL
      WHERE email_status = 'pending'
        AND (
          email IS NULL
          OR (email_attempts >= $1 AND (email_claimed_at IS NULL OR email_claimed_at < NOW() - make_interval(mins => $2::INTEGER)))
        )
    `,
    [MAX_EMAIL_ATTEMPTS, EMAIL_CLAIM_STALE_MINUTES],
  );
  const orphaned = await db.query(
    `
      UPDATE announcement_recipients r
      SET email_status = 'failed', email = NULL, email_hash = NULL, email_claimed_at = NULL, email_next_at = NULL
      FROM announcements a
      WHERE a.id = r.announcement_id AND a.status <> 'published'
        AND r.email_status = 'pending'
        AND (r.email_claimed_at IS NULL OR r.email_claimed_at < NOW() - make_interval(mins => $1::INTEGER))
    `,
    [EMAIL_CLAIM_STALE_MINUTES],
  );
  return Number(exhausted.rowCount ?? 0) + Number(orphaned.rowCount ?? 0);
}

async function failAllPending(db) {
  const result = await db.query(
    `UPDATE announcement_recipients SET email_status = 'failed', email = NULL, email_claimed_at = NULL, email_next_at = NULL WHERE email_status = 'pending'`,
  );
  return Number(result.rowCount ?? 0);
}

/** Eski adres özetlerini temizler (gizlilik: özet yalnız günlük sayım için gerekir). */
export async function purgeStaleEmailHashes(db = pool) {
  const result = await db.query(
    `
      UPDATE announcement_recipients r
      SET email_hash = NULL
      FROM announcements a
      WHERE a.id = r.announcement_id AND r.email_hash IS NOT NULL AND r.email_status <> 'pending'
        AND a.published_at < NOW() - make_interval(days => $1::INTEGER)
    `,
    [EMAIL_HASH_RETENTION_DAYS],
  );
  return Number(result.rowCount ?? 0);
}

/**
 * Bir grup bekleyen satırı talep eder (FOR UPDATE SKIP LOCKED): kişi artık etkin değilse / adres değiştiyse satırı 'none', adres bastırıldıysa
 * 'skipped_pref' yapar (adres NULL); gönderilecekleri `email_claimed_at` ile işaretleyip denemelerini artırır. Bu çalıştırmada denenenler hariç.
 * @returns {Promise<{ picked: number, send: object[] }>}
 */
async function claimBatch(batchSize, attempted) {
  const salts = emailHashSalts();
  const client = await pool.connect();
  let began = false;
  try {
    await client.query('BEGIN');
    began = true;
    const picked = await client.query(
      `
        SELECT
          r.announcement_id, r.person_id, r.email, r.email_hash, r.email_attempts,
          a.title, a.body, a.importance, s.name AS site_name,
          pc.person_active, pc.has_account, pc.current_email,
          (
            EXISTS (SELECT 1 FROM announcement_email_suppressions sup WHERE sup.email_hash = r.email_hash)
            OR ${suppressedSql('r.email', '$6')}
          ) AS suppressed
        FROM announcement_recipients r
        INNER JOIN announcements a ON a.id = r.announcement_id
        INNER JOIN sites s ON s.site_code = a.site_code
        INNER JOIN LATERAL (
          SELECT q.person_active, q.has_account, ${deliverableEmailSql('q.raw_email')} AS current_email
          FROM (
            SELECT sp.is_active AS person_active, ${HAS_ACCOUNT_SQL} AS has_account, ${CONTACT_EMAIL_SQL} AS raw_email
            ${PERSON_FROM}
            WHERE sp.id = r.person_id AND sp.site_code = a.site_code
          ) q
        ) pc ON TRUE
        WHERE r.email_status = 'pending'
          AND r.email IS NOT NULL
          AND r.email_attempts < $1
          AND a.status = 'published'
          AND (r.email_claimed_at IS NULL OR r.email_claimed_at < NOW() - make_interval(mins => $5::INTEGER))
          AND (r.email_next_at IS NULL OR r.email_next_at <= NOW())
          AND NOT EXISTS (
            SELECT 1 FROM unnest($2::BIGINT[], $3::BIGINT[]) AS done(aid, pid)
            WHERE done.aid = r.announcement_id AND done.pid = r.person_id
          )
        ORDER BY r.announcement_id, r.person_id
        LIMIT $4
        FOR UPDATE OF r SKIP LOCKED
      `,
      [MAX_EMAIL_ATTEMPTS, attempted.announcementIds, attempted.personIds, batchSize, EMAIL_CLAIM_STALE_MINUTES, salts],
    );
    const rows = picked.rows ?? [];
    const send = [];
    const skippedA = [];
    const skippedP = [];
    const skippedS = [];
    const migrateHashes = new Set();
    for (const row of rows) {
      if (row.suppressed === true) {
        skippedA.push(row.announcement_id);
        skippedP.push(row.person_id);
        skippedS.push('skipped_pref');
        if (salts.length > 1) {
          migrateHashes.add(hashEmail(row.email));
        }
      } else if (row.person_active !== true || row.current_email === null || row.current_email !== row.email) {
        skippedA.push(row.announcement_id);
        skippedP.push(row.person_id);
        skippedS.push('none');
      } else {
        send.push(row);
      }
    }
    if (migrateHashes.size > 0) {
      // Sessiz tuz geçişi (F3): bastırılmış adresin GÜNCEL tuzla özeti de listeye yazılır (eski sır PREVIOUS'tan silinse de bastırma kalır).
      await client.query(
        `INSERT INTO announcement_email_suppressions (email_hash) SELECT unnest($1::TEXT[]) ON CONFLICT (email_hash) DO NOTHING`,
        [[...migrateHashes]],
      );
    }
    if (skippedA.length > 0) {
      await client.query(
        `
          UPDATE announcement_recipients r
          SET email_status = v.st, email = NULL, email_hash = NULL, email_claimed_at = NULL, email_next_at = NULL
          FROM unnest($1::BIGINT[], $2::BIGINT[], $3::TEXT[]) AS v(aid, pid, st)
          WHERE r.announcement_id = v.aid AND r.person_id = v.pid
        `,
        [skippedA, skippedP, skippedS],
      );
    }
    if (send.length > 0) {
      await client.query(
        `
          UPDATE announcement_recipients r
          SET email_attempts = r.email_attempts + 1, email_claimed_at = NOW(), email_next_at = NULL
          FROM unnest($1::BIGINT[], $2::BIGINT[]) AS v(aid, pid)
          WHERE r.announcement_id = v.aid AND r.person_id = v.pid
        `,
        [send.map((row) => row.announcement_id), send.map((row) => row.person_id)],
      );
    }
    await client.query('COMMIT');
    return { picked: rows.length, send: send.map((row) => ({ ...row, attempts: Number(row.email_attempts) + 1 })) };
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

/** Kalıcı SMTP hatası mı (alıcı reddi / 5xx; kimlik doğrulama hatası yapılandırma sorunudur, kalıcı sayılmaz). */
export function isPermanentSendError(error) {
  if (error?.code === 'INVALID_RECIPIENT' || error?.code === 'EENVELOPE') {
    return true;
  }
  const responseCode = Number(error?.responseCode);
  return error?.code !== 'EAUTH' && Number.isFinite(responseCode) && responseCode >= 500 && responseCode < 600;
}

async function sendOne(row) {
  try {
    await emailQueueHooks.send({
      to: row.email,
      siteName: row.site_name,
      title: row.title,
      body: row.body,
      importance: row.importance,
      hasAccount: row.has_account === true,
      unsubscribeUrl: unsubscribeUrl(row.email_hash || hashEmail(row.email)),
    });
    return { row, ok: true, permanent: false, code: null };
  } catch (error) {
    return {
      row,
      ok: false,
      permanent: isPermanentSendError(error),
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

const retryDelaySeconds = (attempts) => EMAIL_RETRY_DELAYS_SECONDS[Math.min(Math.max(attempts, 1), EMAIL_RETRY_DELAYS_SECONDS.length) - 1];

/**
 * Sonuçları yazar: başarı 'sent'; kalıcı hata ya da denemesi tükenen 'failed'; geçici hata 'pending' (talep işareti kalkar, geri çekilme
 * başlar). Her son durumda email NULL (email_hash günlük sayım için kalır). Yalnız hâlâ 'pending' satırlar güncellenir.
 * E1: gönderim sürerken duyuru geri çekildiyse (artık 'published' değil) GEÇİCİ hatalı satır pending bırakılmaz (bir daha talep edilmez ve düz
 * adres DB'de sonsuza dek kalırdı): 'failed' yapılır, adres ve özet silinir. Başarılı gönderim (sent) etkilenmez.
 */
async function finalizeBatch(results) {
  const aids = [];
  const pids = [];
  const states = [];
  const delays = [];
  for (const result of results) {
    aids.push(result.row.announcement_id);
    pids.push(result.row.person_id);
    if (result.ok) {
      states.push('sent');
      delays.push(0);
    } else if (result.permanent || result.row.attempts >= MAX_EMAIL_ATTEMPTS) {
      states.push('failed');
      delays.push(0);
    } else {
      states.push('pending');
      delays.push(retryDelaySeconds(result.row.attempts));
    }
  }
  if (aids.length === 0) {
    return;
  }
  await pool.query(
    `
      UPDATE announcement_recipients r
      SET email_status = x.final_st,
          email = CASE WHEN x.final_st = 'pending' THEN r.email END,
          email_hash = CASE WHEN x.orphaned THEN NULL ELSE r.email_hash END,
          email_claimed_at = NULL,
          email_next_at = CASE WHEN x.final_st = 'pending' THEN NOW() + make_interval(secs => v.delay::DOUBLE PRECISION) END
      FROM unnest($1::BIGINT[], $2::BIGINT[], $3::TEXT[], $4::INTEGER[]) AS v(aid, pid, st, delay)
      INNER JOIN announcements a ON a.id = v.aid
      CROSS JOIN LATERAL (
        SELECT
          CASE WHEN v.st = 'pending' AND a.status <> 'published' THEN 'failed' ELSE v.st END AS final_st,
          (v.st = 'pending' AND a.status <> 'published') AS orphaned
      ) x
      WHERE r.announcement_id = v.aid AND r.person_id = v.pid AND r.email_status = 'pending'
    `,
    [aids, pids, states, delays],
  );
}

/**
 * Kuyruğu bir kez boşaltmaya çalışır (tek çalışan kilidi alınamazsa { skipped: 'locked' }). Ağ/DB hatası yukarı fırlar
 * (kickEmailQueue yakalar ve loglar).
 * @returns {Promise<{ skipped?: string, smtp?: boolean, sent?: number, failed?: number, pendingRetry?: number, dropped?: number, batches?: number }>}
 */
export async function runEmailQueue({
  batchSize = EMAIL_BATCH_SIZE,
  batchDelayMs = EMAIL_BATCH_DELAY_MS,
  maxRunMs = EMAIL_MAX_RUN_MS,
  concurrency = EMAIL_SEND_CONCURRENCY,
} = {}) {
  const lock = await acquireSessionLock(EMAIL_QUEUE_LOCK_JOB);
  if (!lock) {
    return { skipped: 'locked' };
  }
  const summary = { smtp: true, sent: 0, failed: 0, pendingRetry: 0, dropped: 0, batches: 0 };
  try {
    summary.failed += await failStaleRows(pool);
    if (!isSmtpConfigured()) {
      summary.smtp = false;
      summary.failed += await failAllPending(pool);
      return summary;
    }
    const attempted = { announcementIds: [], personIds: [] };
    const startedAt = emailQueueHooks.now();
    while (!stopRequested && emailQueueHooks.now() - startedAt < maxRunMs) {
      const claimed = await claimBatch(batchSize, attempted);
      if (claimed.picked === 0) {
        break;
      }
      summary.dropped += claimed.picked - claimed.send.length;
      if (claimed.send.length === 0) {
        continue;
      }
      summary.batches += 1;
      for (const row of claimed.send) {
        attempted.announcementIds.push(row.announcement_id);
        attempted.personIds.push(row.person_id);
      }
      const results = await sendAll(claimed.send, concurrency);
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
