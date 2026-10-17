// Borç hatırlatma e-posta kuyruğu (Faz 4b Ö6): duyuru kuyruğunun (announcement_email_queue.js) davranış eşdeğeri; ALICI TABLOSU ayrıdır (finance_reminder_items), bastırma
// listesi / adres özeti / abonelik belirteci ve "ANNC" kilit sınıfı ORTAKTIR; iş numarası announcement_lock.js'teki ANNOUNCEMENT_LOCK_JOBS.financeReminder'dır (tekillik testi: advisory_lock_unique).
//
// Sözleşme: docs/PLATFORM_FINANS_4B.md "Ö6". Kuyruk işçisi FİNANS satırı kilitlemez: yalnız kendi kuyruk satırı (FOR UPDATE SKIP LOCKED). Kısa "talep" transaction'ı gönderimden
// ÖNCE denemeyi artırır, satırı `email_claimed_at` ile işaretler ve kilidi bırakır; gönderim transaction DIŞINDADIR; sonuç kısa UPDATE ile yazılır. 20'lik gruplar, gruplar arası >= 150 ms,
// 3 deneme (1 / 5 dk geri çekilme), KALICI SMTP hatasında hemen 'failed', 10 dk'dan eski talep (süreç çökmüş) devralınır, son durumda `email` NULL.
// BAYAT BORÇ KORUMASI: talep ANINDA kişi hâlâ etkin mi, adres değişmedi mi, bastırılmadı mı, çalıştırma etkin mi, ilgili dairelerde gecikmiş borç eşiği hâlâ geçerli mi taze doğrulanır;
// değilse satır 'resolved' (adres NULL) olur ve ileti GİTMEZ. Tutar (varsa) o ANKİ değerdir. 24 saati geçen pending satır 'failed'. Gönderilmeyen satırın daire aralık kayıtları silinir.
// SMTP yapılandırılmamışsa bekleyen satırlar 'failed' (sessiz kayıp yok). Log'a adres / ad YAZILMAZ; yalnız sayılar ve hata kodları.

import { pool } from '../db.js';
import { isSmtpConfigured, sendPreparedEmail } from '../mailer.js';
import { EMAIL_CLAIM_STALE_MINUTES, EMAIL_RETRY_DELAYS_SECONDS, MAX_EMAIL_ATTEMPTS } from './announcement_common.js';
import { emailHashSalts, hashEmail, unsubscribeUrl } from './announcement_email_security.js';
import { ANNOUNCEMENT_LOCK_CLASS, ANNOUNCEMENT_LOCK_JOBS } from './announcement_lock.js';
import { deliverableEmailSql, suppressedSql } from './announcement_recipients.js';
import { buildFinanceReminderEmail } from './finance_reminder_mail.js';
import { dayNumber } from './finance_4b_common.js';
import { loadCandidateApartments, loadRecipientRows } from './finance_reminders.js';
import { readLegalOk } from './finance_settings.js';
import { recordFinanceAudit } from './finance_tx.js';
import { isPermanentSendError } from './announcement_email_queue.js';
import { ACCOUNT_KIND_SQL, HAS_ACCOUNT_SQL, todayIso } from './people_common.js';
import { CONTACT_EMAIL_SQL, PERSON_FROM } from './people_service.js';

export const FINANCE_REMINDER_LOCK_JOB = ANNOUNCEMENT_LOCK_JOBS.financeReminder;
/** Kapı nedeniyle iptal edilen satırların denetim kaydı için sistem aktörü (kullanıcı yok). */
const SYSTEM_ACTOR = Object.freeze({ full_name: 'Sistem', role: 'system' });
export const REMINDER_BATCH_SIZE = 20;
export const REMINDER_BATCH_DELAY_MS = 150;
export const REMINDER_SEND_CONCURRENCY = 4;
export const REMINDER_MAX_RUN_MS = 15 * 60 * 1000;
export const REMINDER_EXPIRY_HOURS = 24;
/** Adres özetleri gönderimden bu kadar gün sonra satırlardan silinir (7 günlük adres sınırı için 8 gün tutulur). */
export const REMINDER_HASH_RETENTION_DAYS = 8;

export const reminderQueueHooks = {
  send: (message) => sendPreparedEmail(message),
  sleep: (ms) => new Promise((resolve) => setTimeout(resolve, ms)),
  now: () => Date.now(),
};

let activeRun = null;
let stopRequested = false;

async function acquireLock() {
  const client = await pool.connect();
  const onError = (error) => {
    // eslint-disable-next-line no-console
    console.error('[finance-reminder-lock] baglanti hatasi (kilit duser):', error?.code || 'hata');
  };
  client.on('error', onError);
  const result = await client
    .query('SELECT pg_try_advisory_lock($1::int, $2::int) AS locked', [ANNOUNCEMENT_LOCK_CLASS, FINANCE_REMINDER_LOCK_JOB])
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
        await client.query('SELECT pg_advisory_unlock($1::int, $2::int)', [ANNOUNCEMENT_LOCK_CLASS, FINANCE_REMINDER_LOCK_JOB]);
        client.off('error', onError);
        client.release();
      } catch (_error) {
        client.release(true);
      }
    },
  };
}

/** İŞİ OLAN bekleyen hatırlatma satırı var mı (kısmi indeks; hafif). */
export async function hasPendingReminders(db = pool) {
  const result = await db.query(
    `
      SELECT 1
      FROM finance_reminder_items i
      INNER JOIN finance_reminder_runs r ON r.id = i.run_id AND r.status = 'active'
      WHERE i.email_status = 'pending'
        AND (i.email_next_at IS NULL OR i.email_next_at <= NOW())
        AND (i.email_claimed_at IS NULL OR i.email_claimed_at < NOW() - make_interval(mins => $1::INTEGER))
      LIMIT 1
    `,
    [EMAIL_CLAIM_STALE_MINUTES],
  );
  return Boolean(result.rows?.[0]);
}

// Gönderilmeyen satırların daire aralık kayıtlarını serbest bırakır. $1: etkilenen çalıştırma kimlikleri (kapsamlı; null = hepsi, yalnız nadir toplu yollarda).
const RELEASE_INTERVALS_SQL = `
  DELETE FROM finance_reminder_apartments fa
  USING finance_reminder_items gone
  WHERE gone.run_id = fa.run_id AND fa.apartment_id = ANY(gone.apartment_ids)
    AND ($1::BIGINT[] IS NULL OR fa.run_id = ANY($1::BIGINT[]))
    AND gone.email_status IN ('failed', 'resolved', 'skipped_pref', 'cancelled')
    AND NOT EXISTS (
      SELECT 1 FROM finance_reminder_items keep
      WHERE keep.run_id = fa.run_id AND keep.email_status IN ('sent', 'pending') AND fa.apartment_id = ANY(keep.apartment_ids)
    )
`;

/**
 * Kalıcı hatalı satırları kapatır: adresi olmayan, denemesi tükenmiş, 24 saati geçmiş ve etkin OLMAYAN (iptal edilmiş) çalıştırmanın pending satırları 'failed' olur
 * (adres ve özet NULL). Gönderilmeyen satırların daire aralık kayıtları silinir. Zamanlayıcı her tikte de çağırır.
 */
export async function failStaleReminderRows(db = pool) {
  // Çok satırlı UPDATE'ler satırları (run_id, person_id) SIRASIYLA kilitler (talep / sonuç / iptal yollarıyla aynı sıra: 40P01 olmasın).
  const result = await db.query(
    `
      WITH locked AS (
        SELECT i.run_id, i.person_id
        FROM finance_reminder_items i INNER JOIN finance_reminder_runs r ON r.id = i.run_id
        WHERE i.email_status = 'pending'
          AND (i.email_claimed_at IS NULL OR i.email_claimed_at < NOW() - make_interval(mins => $2::INTEGER))
          AND (
            i.email IS NULL OR i.email_attempts >= $1 OR r.status <> 'active' OR r.created_at < NOW() - make_interval(hours => $3::INTEGER)
          )
        ORDER BY i.run_id, i.person_id
        FOR UPDATE OF i
      )
      UPDATE finance_reminder_items i
      SET email_status = 'failed', email = NULL, email_hash = NULL, email_claimed_at = NULL, email_next_at = NULL
      FROM locked l WHERE i.run_id = l.run_id AND i.person_id = l.person_id
    `,
    [MAX_EMAIL_ATTEMPTS, EMAIL_CLAIM_STALE_MINUTES, REMINDER_EXPIRY_HOURS],
  );
  let total = Number(result.rowCount ?? 0);
  // Pasif / silinmiş kişiye ait bekleyen satırın DÜZ adresi kuyruk dönene kadar beklemesin (hesap silme sonrası; R10 P2-10): 'resolved', adres + özet NULL.
  const scrubbed = await db.query(
    `
      WITH locked AS (
        SELECT i.run_id, i.person_id
        FROM finance_reminder_items i INNER JOIN site_people sp ON sp.id = i.person_id
        WHERE i.email_status = 'pending' AND i.email_claimed_at IS NULL
          AND (
            sp.is_active = FALSE
            OR (sp.user_code IS NOT NULL AND EXISTS (SELECT 1 FROM users u WHERE u.user_code = sp.user_code AND u.deleted_at IS NOT NULL))
          )
        ORDER BY i.run_id, i.person_id
        FOR UPDATE OF i
      )
      UPDATE finance_reminder_items i
      SET email_status = 'resolved', email = NULL, email_hash = NULL, email_claimed_at = NULL, email_next_at = NULL
      FROM locked l WHERE i.run_id = l.run_id AND i.person_id = l.person_id
    `,
  );
  total += Number(scrubbed.rowCount ?? 0);
  if (total > 0) {
    await db.query(RELEASE_INTERVALS_SQL, [null]);
  }
  return total;
}

async function failAllPending(db) {
  const result = await db.query(
    `
      WITH locked AS (
        SELECT run_id, person_id FROM finance_reminder_items WHERE email_status = 'pending' ORDER BY run_id, person_id FOR UPDATE
      )
      UPDATE finance_reminder_items i SET email_status = 'failed', email = NULL, email_hash = NULL, email_claimed_at = NULL, email_next_at = NULL
      FROM locked l WHERE i.run_id = l.run_id AND i.person_id = l.person_id
    `,
  );
  if (Number(result.rowCount ?? 0) > 0) {
    await db.query(RELEASE_INTERVALS_SQL, [null]);
  }
  return Number(result.rowCount ?? 0);
}

/** Gönderilmiş satırların adres özetlerini (8 gün sonra) temizler: özet yalnız 7 günlük adres sınırı için gerekir. */
export async function purgeStaleReminderHashes(db = pool) {
  const result = await db.query(
    // Satırlar (run_id, person_id) SIRASIYLA kilitlenir (diğer çok satırlı güncelleme yollarıyla aynı sıra; R15 P2-7).
    `
      WITH locked AS (
        SELECT run_id, person_id FROM finance_reminder_items
        WHERE email_hash IS NOT NULL AND email_status <> 'pending' AND sent_at < NOW() - make_interval(days => $1::INTEGER)
        ORDER BY run_id, person_id
        FOR UPDATE
      )
      UPDATE finance_reminder_items i SET email_hash = NULL FROM locked l WHERE i.run_id = l.run_id AND i.person_id = l.person_id
    `,
    [REMINDER_HASH_RETENTION_DAYS],
  );
  return Number(result.rowCount ?? 0);
}

/**
 * Bir grup bekleyen satırı talep eder (FOR UPDATE SKIP LOCKED) ve taze doğrular. Dönüş: { picked, send } (send = gönderilecek satırlar + hesaplanmış daire bilgisi).
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
          i.run_id, i.person_id, i.apartment_ids, i.with_amount, i.email, i.email_hash, i.email_attempts,
          r.site_code, r.tone, r.note, r.params, s.name AS site_name,
          COALESCE((SELECT m.enabled FROM site_modules m WHERE m.site_code = r.site_code AND m.module_code = 'finance'), FALSE) AS module_on,
          COALESCE((SELECT fs.reminders_enabled FROM finance_settings fs WHERE fs.site_code = r.site_code), FALSE) AS reminders_on,
          pc.person_active, pc.has_account, pc.account_kind, pc.verified, pc.pref, pc.current_email,
          (
            EXISTS (SELECT 1 FROM announcement_email_suppressions sup WHERE sup.email_hash = i.email_hash)
            OR ${suppressedSql('i.email', '$6')}
          ) AS suppressed
        FROM finance_reminder_items i
        INNER JOIN finance_reminder_runs r ON r.id = i.run_id
        INNER JOIN sites s ON s.site_code = r.site_code
        INNER JOIN LATERAL (
          SELECT q.person_active, q.has_account, q.account_kind, q.verified, q.pref, ${deliverableEmailSql('q.raw_email')} AS current_email
          FROM (
            SELECT sp.is_active AS person_active, ${HAS_ACCOUNT_SQL} AS has_account, ${ACCOUNT_KIND_SQL} AS account_kind, COALESCE(u.email_verified, FALSE) AS verified,
                   COALESCE((SELECT np.email_finance_reminders FROM notification_preferences np WHERE np.user_code = sp.user_code), TRUE) AS pref, ${CONTACT_EMAIL_SQL} AS raw_email
            ${PERSON_FROM}
            WHERE sp.id = i.person_id AND sp.site_code = r.site_code
          ) q
        ) pc ON TRUE
        WHERE i.email_status = 'pending' AND i.email IS NOT NULL AND i.email_attempts < $1
          AND r.status = 'active' AND r.created_at >= NOW() - make_interval(hours => ${REMINDER_EXPIRY_HOURS})
          AND (i.email_claimed_at IS NULL OR i.email_claimed_at < NOW() - make_interval(mins => $5::INTEGER))
          AND (i.email_next_at IS NULL OR i.email_next_at <= NOW())
          AND NOT EXISTS (SELECT 1 FROM unnest($2::BIGINT[], $3::BIGINT[]) AS done(rid, pid) WHERE done.rid = i.run_id AND done.pid = i.person_id)
        ORDER BY i.run_id, i.person_id
        LIMIT $4
        FOR UPDATE OF i SKIP LOCKED
      `,
      [MAX_EMAIL_ATTEMPTS, attempted.runIds, attempted.personIds, batchSize, EMAIL_CLAIM_STALE_MINUTES, salts],
    );
    const rows = picked.rows ?? [];
    // GÖNDERİM ANI KAPILARI (çalıştırma oluşturulduktan sonra değişmiş olabilir): sistem hukuk onayı (finance.legal_ok), finans modülü, hatırlatma ayarı.
    // Kapalıysa satır GÖNDERİLMEZ: 'cancelled' (adres silinir) ve nedeni denetime (kod) yazılır.
    const legalOk = rows.length === 0 ? true : await readLegalOk(client);
    // Taze borç: site başına, ilgili dairelerin M1 gecikmiş borcu / en eski vadesi (bugün)
    const today = todayIso();
    const todayDay = dayNumber(today);
    const bySite = new Map();
    for (const row of rows) {
      const list = bySite.get(Number(row.site_code)) ?? [];
      list.push(...row.apartment_ids.map(Number));
      bySite.set(Number(row.site_code), list);
    }
    const fresh = new Map();
    const recipientsOf = new Map(); // `${site}:${person}` -> Set(daire): kişinin o dairede HÂLÂ güncel ve izinli (responsible_party) ilişkisi var
    for (const [siteCode, ids] of bySite) {
      const unique = [...new Set(ids)];
      for (const apartment of await loadCandidateApartments(client, siteCode, today, unique)) {
        fresh.set(apartment.id, apartment);
      }
      for (const recipient of await loadRecipientRows(client, siteCode, unique)) {
        const mapKey = `${siteCode}:${Number(recipient.person_id)}`;
        const set = recipientsOf.get(mapKey) ?? new Set();
        set.add(Number(recipient.apartment_id));
        recipientsOf.set(mapKey, set);
      }
    }
    const send = [];
    const resolved = { runIds: [], personIds: [], statuses: [] };
    const mark = (row, status) => {
      resolved.runIds.push(row.run_id);
      resolved.personIds.push(row.person_id);
      resolved.statuses.push(status);
    };
    const gateCancelled = new Map(); // `${run}|${neden}` -> sayı (denetim)
    const dropped = { runIds: [], apartmentIds: [] };
    for (const row of rows) {
      const minOverdue = BigInt(row.params?.min_overdue_minor ?? 0);
      const minDays = Number(row.params?.min_days_overdue ?? 0);
      const gate = !legalOk ? 'legal_gate' : row.module_on !== true ? 'module_disabled' : row.reminders_on !== true ? 'reminders_disabled' : null;
      if (gate !== null) {
        mark(row, 'cancelled');
        const gateKey = `${row.run_id}|${row.site_code}|${gate}`;
        gateCancelled.set(gateKey, (gateCancelled.get(gateKey) ?? 0) + 1);
        continue;
      }
      if (row.suppressed === true || (row.has_account === true && row.pref === false)) {
        mark(row, 'skipped_pref');
        continue;
      }
      if (row.person_active !== true || row.current_email === null || row.current_email !== row.email) {
        mark(row, 'resolved');
        continue;
      }
      const allowed = recipientsOf.get(`${Number(row.site_code)}:${Number(row.person_id)}`) ?? new Set();
      // daire hâlâ bu kişinin sorumluluğunda mı (ilişki güncel + responsible_party), muaf değil, borç eşiği ve gecikme günü hâlâ sağlanıyor mu
      const remaining = row.apartment_ids
        .map(Number)
        .filter((id) => allowed.has(id))
        .map((id) => fresh.get(id))
        .filter((apartment) => apartment && apartment.excluded !== true && apartment.overdue >= minOverdue && apartment.oldestDue !== null && todayDay - dayNumber(apartment.oldestDue) >= minDays);
      if (remaining.length === 0) {
        mark(row, 'resolved');
        continue;
      }
      send.push({ ...row, attempts: Number(row.email_attempts) + 1, apartments: remaining });
      // Gönderim anında DÜŞEN daireler (muaf / ilişkisi biten / eşiğin altına inen): kalem yalnız kalanları kapsar ve düşenlerin aralık kaydı serbest bırakılır
      // (hiç hatırlatılmamış daire 14 gün beklemesin, ardışık sayaç boşa artmasın; R15 P2-1).
      const keptIds = new Set(remaining.map((apartment) => apartment.id));
      for (const id of row.apartment_ids.map(Number)) {
        if (!keptIds.has(id)) {
          dropped.runIds.push(row.run_id);
          dropped.apartmentIds.push(id);
        }
      }
    }
    if (resolved.runIds.length > 0) {
      await client.query(
        `
          UPDATE finance_reminder_items i
          SET email_status = v.st, email = NULL, email_hash = NULL, email_claimed_at = NULL, email_next_at = NULL
          FROM unnest($1::BIGINT[], $2::BIGINT[], $3::TEXT[]) AS v(rid, pid, st)
          WHERE i.run_id = v.rid AND i.person_id = v.pid
        `,
        [resolved.runIds, resolved.personIds, resolved.statuses],
      );
      await client.query(RELEASE_INTERVALS_SQL, [[...new Set(resolved.runIds.map(String))]]);
    }
    for (const [gateKey, count] of gateCancelled) {
      const [runId, siteCode, gateCode] = gateKey.split('|');
      await recordFinanceAudit(client, SYSTEM_ACTOR, 'finance.reminder.cancelled', Number(siteCode), Number(runId), { cancelled_count: count, gate: gateCode });
    }
    if (send.length > 0) {
      await client.query(
        `
          UPDATE finance_reminder_items i
          SET email_attempts = i.email_attempts + 1, email_claimed_at = NOW(), email_next_at = NULL, apartment_ids = v.aps::BIGINT[]
          FROM unnest($1::BIGINT[], $2::BIGINT[], $3::TEXT[]) AS v(rid, pid, aps) WHERE i.run_id = v.rid AND i.person_id = v.pid
        `,
        [send.map((row) => row.run_id), send.map((row) => row.person_id), send.map((row) => `{${row.apartments.map((apartment) => apartment.id).join(',')}}`)],
      );
      if (dropped.runIds.length > 0) {
        // kalem artık düşen daireyi kapsamıyor (yukarıdaki UPDATE); aynı çalıştırmada o daireyi kapsayan başka gönderilmiş / bekleyen kalem yoksa aralık kaydı silinir
        await client.query(
          `
            DELETE FROM finance_reminder_apartments fa
            USING unnest($1::BIGINT[], $2::BIGINT[]) AS d(rid, aid)
            WHERE fa.run_id = d.rid AND fa.apartment_id = d.aid
              AND NOT EXISTS (
                SELECT 1 FROM finance_reminder_items keep
                WHERE keep.run_id = fa.run_id AND keep.email_status IN ('sent', 'pending') AND fa.apartment_id = ANY(keep.apartment_ids)
              )
          `,
          [dropped.runIds, dropped.apartmentIds],
        );
      }
    }
    await client.query('COMMIT');
    return { picked: rows.length, send };
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
    const message = buildFinanceReminderEmail({
      to: row.email,
      siteName: row.site_name,
      tone: row.tone,
      note: row.note,
      apartments: row.apartments.map((apartment) => ({ label: apartment.label, overdueMinor: apartment.overdue, oldestDue: apartment.oldestDue })),
      withAmount: row.with_amount === true && row.account_kind === 'registered' && row.verified === true,
      hasAccount: row.has_account === true,
      unsubscribeUrl: unsubscribeUrl(row.email_hash || hashEmail(row.email)),
    });
    await reminderQueueHooks.send(message);
    return { row, ok: true, permanent: false, code: null };
  } catch (error) {
    return { row, ok: false, permanent: isPermanentSendError(error), code: String(error?.code ?? error?.responseCode ?? 'SEND_FAILED') };
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

/** Sonuçları yazar (yalnız hâlâ 'pending' satırlar): başarı 'sent' (sent_at); kalıcı hata / tükenen deneme 'failed'; geçici hata 'pending' (geri çekilme). */
async function finalizeBatch(results) {
  const rids = [];
  const pids = [];
  const states = [];
  const delays = [];
  for (const result of results) {
    rids.push(result.row.run_id);
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
  if (rids.length === 0) {
    return;
  }
  // Satırlar (run_id, person_id) SIRASIYLA kilitlenir (iptal / bayat kapatma yollarıyla aynı sıra), sonra güncellenir.
  await pool.query(
    `
      WITH v AS (
        SELECT * FROM unnest($1::BIGINT[], $2::BIGINT[], $3::TEXT[], $4::INTEGER[]) AS t(rid, pid, st, delay)
      ),
      locked AS (
        SELECT i.run_id, i.person_id FROM finance_reminder_items i INNER JOIN v ON i.run_id = v.rid AND i.person_id = v.pid
        WHERE i.email_status = 'pending'
        ORDER BY i.run_id, i.person_id
        FOR UPDATE OF i
      )
      UPDATE finance_reminder_items i
      SET email_status = v.st,
          email = CASE WHEN v.st = 'pending' THEN i.email END,
          email_hash = CASE WHEN v.st = 'failed' THEN NULL ELSE i.email_hash END,
          sent_at = CASE WHEN v.st = 'sent' THEN NOW() ELSE i.sent_at END,
          email_claimed_at = NULL,
          email_next_at = CASE WHEN v.st = 'pending' THEN NOW() + make_interval(secs => v.delay::DOUBLE PRECISION) END
      FROM v INNER JOIN locked l ON l.run_id = v.rid AND l.person_id = v.pid
      WHERE i.run_id = l.run_id AND i.person_id = l.person_id AND i.email_status = 'pending'
    `,
    [rids, pids, states, delays],
  );
  if (states.includes('failed')) {
    await pool.query(RELEASE_INTERVALS_SQL, [[...new Set(rids.map(String))]]);
  }
}

/** Kuyruğu bir kez boşaltmaya çalışır (kilit alınamazsa { skipped: 'locked' }). */
export async function runFinanceReminderQueue({
  batchSize = REMINDER_BATCH_SIZE,
  batchDelayMs = REMINDER_BATCH_DELAY_MS,
  maxRunMs = REMINDER_MAX_RUN_MS,
  concurrency = REMINDER_SEND_CONCURRENCY,
} = {}) {
  const lock = await acquireLock();
  if (!lock) {
    return { skipped: 'locked' };
  }
  const summary = { smtp: true, sent: 0, failed: 0, pendingRetry: 0, dropped: 0, batches: 0 };
  try {
    summary.failed += await failStaleReminderRows(pool);
    if (!isSmtpConfigured()) {
      summary.smtp = false;
      summary.failed += await failAllPending(pool);
      return summary;
    }
    const attempted = { runIds: [], personIds: [] };
    const startedAt = reminderQueueHooks.now();
    while (!stopRequested && reminderQueueHooks.now() - startedAt < maxRunMs) {
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
        attempted.runIds.push(row.run_id);
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
        console.error(`[finance-reminder] gonderim hatasi: kodlar=${[...codes].join(',')}`);
      }
      await reminderQueueHooks.sleep(batchDelayMs);
    }
    return summary;
  } finally {
    await lock.release();
  }
}

/** Kuyruğu arka planda başlatır (bekletmez). Çalışan bir tur varsa onu döndürür. Hata sunucuyu düşürmez; yalnız loglanır. */
export function kickFinanceReminderQueue(options = {}) {
  if (stopRequested) {
    return Promise.resolve({ skipped: 'stopping' });
  }
  if (activeRun) {
    return activeRun;
  }
  activeRun = runFinanceReminderQueue(options)
    .catch((error) => {
      // eslint-disable-next-line no-console
      console.error('[finance-reminder] kuyruk turu basarisiz:', error?.code || error?.message || 'hata');
      return { error: String(error?.code || 'ERROR') };
    })
    .finally(() => {
      activeRun = null;
    });
  return activeRun;
}

export function stopFinanceReminderQueue() {
  stopRequested = true;
  return activeRun ?? Promise.resolve(null);
}

export function resumeFinanceReminderQueue() {
  stopRequested = false;
}

void dayNumber;
