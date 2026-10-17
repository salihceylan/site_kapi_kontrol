// Telefon bildirimi (Faz 3b-B): outbox işçisi (FCM gönderimi), devre kesici, bakım ve yönetici durumu.
//
// Sözleşme: docs/PLATFORM_BELGELER.md B4 / B5 (e-posta kuyruğu kalıbı: announcement_email_queue.js).
//  - Tek çalışan: oturum düzeyi advisory kilit (announcement_lock.js, iki-int sınıf 0x414E4E43, iş pushQueue = 5); satır seçimi FOR UPDATE SKIP LOCKED.
//  - 100'lük gruplar, aralarında >= 200 ms, tur <= 10 dk. Kısa TALEP işlemi: kullanıcı başına kurallar uygulanır, gönderilecek satırların attempts'ı artar
//    (LEAST ile 10'da sınırlı: CHECK ihlali tüm talebi düşürmez) ve claimed_at yazılır (10 dk bayat talep yeniden alınır); gönderim işlem DIŞINDA,
//    eşzamanlılık 16; sonuç kısa UPDATE'lerle (işlemsiz; satırlar id sırasıyla kilitlenir, 40P01'de ifade bir kez yeniden denenir) yazılır.
//  - SAAT: bütün talep kararları (süre, sessiz saat, günlük sınırın İstanbul günü, erteleme zamanı) DB saatiyle (talep sorgusundaki NOW()) verilir;
//    uygunluk da DB NOW() ile denetlendiğinden uygulama / DB saat kayması pencere sonunda sıkı döngü üretmez. Ertelenen satır aynı turda yeniden
//    talep edilmez.
//  - Talep anı kuralları: denemesi tükenmiş (attempts >= 4; ör. çöken sürecin bayat talebi) -> failed; süresi geçmiş (ya da kalan ömrü < 1 sn) ->
//    expired; kullanıcı pasif / silinmiş -> skipped/inactive; duyuru artık yayında değil YA DA kullanıcı artık duyurunun alıcı kişisine bağlı değil
//    (taşındı / kişi kaydından ayrıldı) -> skipped/withdrawn; normal + push_announcements=false -> skipped/pref; normal + sessiz saat (İstanbul; gece
//    yarısını aşabilir) -> pending kalır, not_before = pencere sonu (deneme düşmez; 12 saatten uzunsa / geçerlilik sonunu aşarsa expired); normal +
//    günlük üst sınır (PUSH_MAX_PER_DAY_PER_USER, İstanbul günü, `sent` sayılır) -> skipped/capped (KALICI atlama); izinli cihaz yok ->
//    skipped/no_device. ACİL tercih / sessiz saat / üst sınırı YOK SAYAR (e-posta kuralı; site başına acil sınırı outbox yazımında, push_outbox.js).
//  - Sonuç: en az bir cihaza kabul -> sent (+sent_device_count; cihaz last_success_at); geçici hata -> pending + geri çekilme 60 / 300 / 1200 sn
//    (Retry-After daha uzunsa o), 4. denemede failed; ölü jeton cihaz satırını siler, yalnız ölü jeton kaldıysa skipped/no_device; diğer 4xx -> failed.
//    Aynı çalıştırmada bir satır en çok bir kez denenir. FCM ttl / apns-expiration = min(varsayılan, expires_at - şimdi).
//  - 429 (kota): tur Retry-After kadar (yoksa 60 sn, en çok 10 dk) DURAKLAR; 429'u alan ve gruptaki gönderilmemiş satırlar deneme İADESİYLE pending
//    kalır, not_before = şimdi + Retry-After (her satır ayrı deneme yakmaz).
//  - Ölü jeton korumaları (yanlış projenin hizmet hesabı / yanlış uç tüm cihazları sildiremez):
//    (a) süreç düzeyi (push_devices.js deadTokenGuard): hizmet hesabı yüklendikten sonra en az bir BAŞARILI gönderim görülmeden "ölü" sonuç cihaz
//        SİLDİRMEZ; satır deneme iadesiyle pending kalır (5 dk sonra), no_device sayılmaz; son başarıdan beri ölü sayısı >= 20 ve grupta başarı
//        yoksa MASS_DEAD + devre kesici;
//    (b) grup düzeyi: en az 20 gönderimin yarıdan fazlası ölü VE başarı oranı < %5 ise MASS_DEAD + devre kesici, silme yok. Başarıyla karışık gerçek
//        ölü jetonlar (eski kurulumlar) normal silinir (sonsuz 5 dk duraklama döngüsü olmaz).
//  - Cihazın failure_count'u yalnız cihaza özgü geçici hatada artar; APNs yapılandırma hatası, çıplak 404 / mesaj hatası (invalid) ve doğrulanmamış
//    ölü sonuç yalnız last_error_code yazar (yapılandırma hatası 30 günü aşsa da bakım sağlam cihazları "kalıcı hatalı" diye silmez).
//  - Devre kesici: art arda 5 kimlik doğrulama / 5xx / ağ hatasında tur durur, denenmemiş satırlar pending kalır (deneme DÜŞMEZ; talep iade edilir),
//    5 dk boyunca tur başlatılmaz; hata kodu en çok 10 dk'da bir loglanır. Kimlik doğrulama hatası (401/403) satırın suçu değildir: deneme iade edilir.
//    iOS APNs anahtarı yüklenmemişse (THIRD_PARTY_AUTH_ERROR) iOS gönderimleri 10 dk durur, last_error_code = APNS_AUTH.
//  - Kapanış (stopPushWorker): başlamamış gönderimler yapılmaz, talepleri hemen bırakılır (claimed_at NULL, deneme iadesi); süre dolduğunda hâlâ
//    sonuçlanmamış talepler de bırakılır (10 dk asılı kalmaz; "en az bir kez" teslim, collapse ile tekilleşir).
//  - Hizmet hesabı yüklenemiyorsa / PUSH_ENABLED kapalıysa tur HİÇ başlamaz. Bakım (cihaz temizliği) push kapalıyken de çalışır.
//  - GİZLİLİK: günlüğe yalnız sayılar ve hata kodları; kayıt jetonu, e-posta, ad, başlık YAZILMAZ.

import { pool } from '../db.js';
import { ANNOUNCEMENT_LOCK_JOBS, acquireSessionLock } from './announcement_lock.js';
import {
  DEVICE_FAILURE_DAYS,
  DEVICE_FAILURE_LIMIT,
  DEVICE_IDLE_DAYS,
  DEAD_UNCONFIRMED_RETRY_SECONDS,
  MASS_DEAD_MAX_SUCCESS_RATIO,
  MASS_DEAD_MIN_SENDS,
  MAX_PUSH_ATTEMPTS,
  PUSH_BATCH_DELAY_MS,
  PUSH_BATCH_SIZE,
  PUSH_CLAIM_STALE_MINUTES,
  PUSH_MAX_RUN_MS,
  PUSH_SEND_CONCURRENCY,
  RATE_LIMIT_DEFAULT_PAUSE_SECONDS,
  RATE_LIMIT_MAX_PAUSE_SECONDS,
  istanbulDayStartMs,
  quietDecision,
  retryDelaySeconds,
  retryOnDeadlock,
  sanitizeErrorCode,
} from './push_common.js';
import { pushMaxPerDay } from './push_config.js';
import { isPushAvailable, loadPushRuntime, pushRuntime } from './push_credentials.js';
import { applyDeviceOutcomes, mapLimited, recordDeliveryOutcome, resetDeadTokenGuard } from './push_devices.js';
import { fcmClientFor } from './push_fcm.js';
import { buildAnnouncementMessage } from './push_message.js';
import { runOutboxMaintenance } from './push_outbox.js';

export const PUSH_QUEUE_LOCK_JOB = ANNOUNCEMENT_LOCK_JOBS.pushQueue;
export const BREAKER_THRESHOLD = 5;
export const BREAKER_COOLDOWN_MS = 5 * 60 * 1000;
export const APNS_BLOCK_MS = 10 * 60 * 1000;
export const BREAKER_LOG_INTERVAL_MS = 10 * 60 * 1000;
/** Kimlik doğrulama hatası / devre kesici nedeniyle denenmeyen satır bu kadar sonra yeniden talep edilir (deneme düşmez). */
export const BREAKER_RETRY_SECONDS = 60;
export const MAINTENANCE_INTERVAL_MS = 60 * 60 * 1000;
export const MAINTENANCE_FIRST_DELAY_MS = 60 * 1000;
/** attempts sütununun CHECK üst sınırı (0-10): talep artışı bununla sınırlanır. */
const ATTEMPTS_CEILING = 10;

/** Test / QA için değiştirilebilir bağımlılıklar (sahte FCM istemcisi, saat, bekleme). */
export const pushQueueHooks = {
  client: () => fcmClientFor(pushRuntime().account),
  account: () => pushRuntime().account,
  available: () => isPushAvailable(),
  maxPerDay: () => pushMaxPerDay(),
  now: () => Date.now(),
  sleep: (ms) => new Promise((resolve) => setTimeout(resolve, ms)),
};

let activeRun = null;
let stopRequested = false;
/** Talep edilmiş ama sonucu henüz yazılmamış satırlar (kapanışta bırakılır). */
const inFlightClaims = new Set();
const breaker = { openUntil: 0, apnsBlockedUntil: 0, lastLogAt: {}, lastErrorCode: null };

/** Test yardımcısı: devre kesici / durdurma durumunu sıfırlar. */
export function resetPushQueueState() {
  stopRequested = false;
  inFlightClaims.clear();
  breaker.openUntil = 0;
  breaker.apnsBlockedUntil = 0;
  breaker.lastLogAt = {};
  breaker.lastErrorCode = null;
  resetDeadTokenGuard();
}

/** Son görülen hata kodu (yönetici durumu için; kod dışında bilgi yok). */
export function lastPushErrorCode() {
  return breaker.lastErrorCode;
}

/** Aynı türden (key) günlük satırı en çok 10 dk'da bir. */
function logRateLimited(key, message) {
  const now = pushQueueHooks.now();
  if (now - (breaker.lastLogAt[key] ?? -Infinity) >= BREAKER_LOG_INTERVAL_MS) {
    breaker.lastLogAt[key] = now;
    // eslint-disable-next-line no-console
    console.error(message);
  }
}

// ---------------------------------------------------------------------------------------------------------
// Talep
// ---------------------------------------------------------------------------------------------------------

const CLAIM_SQL = `
  SELECT
    o.id, o.announcement_id, o.site_code, o.user_code, o.importance, o.attempts,
    (o.expires_at <= NOW()) AS is_expired, o.expires_at,
    GREATEST(0, FLOOR(EXTRACT(EPOCH FROM (o.expires_at - NOW()))))::INTEGER AS ttl_left,
    (EXTRACT(EPOCH FROM NOW()) * 1000)::BIGINT AS db_now_ms,
    a.status AS announcement_status, a.title, s.name AS site_name,
    (u.user_code IS NOT NULL AND u.is_active = TRUE AND u.deleted_at IS NULL) AS user_live,
    EXISTS (
      SELECT 1
      FROM site_people sp
      INNER JOIN announcement_recipients r ON r.person_id = sp.id AND r.announcement_id = o.announcement_id
      WHERE sp.user_code = o.user_code
    ) AS still_recipient,
    np.push_announcements, np.push_show_preview, np.push_quiet_enabled, np.push_quiet_start, np.push_quiet_end
  FROM push_outbox o
  INNER JOIN announcements a ON a.id = o.announcement_id
  INNER JOIN sites s ON s.site_code = o.site_code
  LEFT JOIN users u ON u.user_code = o.user_code
  LEFT JOIN notification_preferences np ON np.user_code = o.user_code
  WHERE o.status = 'pending'
    AND o.not_before <= NOW()
    AND (o.claimed_at IS NULL OR o.claimed_at < NOW() - make_interval(mins => $2::INTEGER))
    AND NOT (o.id = ANY($3::BIGINT[]))
  ORDER BY o.not_before, o.id
  LIMIT $1
  FOR UPDATE OF o SKIP LOCKED
`;

/**
 * Bir grubu talep eder (tek kısa işlem): kuralları uygular, atlanan / süresi geçen / tükenmiş / ertelenen satırları yazar, gönderilecekleri talep eder.
 * @returns {Promise<{ picked: number, send: object[], skipped: number, expired: number, deferred: number, failed: number, deferredIds: number[] }>}
 */
async function claimBatch(batchSize, attempted) {
  const maxPerDay = pushQueueHooks.maxPerDay();
  const client = await pool.connect();
  let began = false;
  try {
    await client.query('BEGIN');
    began = true;
    const rows = (await client.query(CLAIM_SQL, [batchSize, PUSH_CLAIM_STALE_MINUTES, [...attempted]])).rows ?? [];
    const summary = { picked: rows.length, send: [], skipped: 0, expired: 0, deferred: 0, failed: 0, deferredIds: [] };
    if (rows.length === 0) {
      await client.query('COMMIT');
      began = false;
      return summary;
    }
    // Karar saati DB saatidir (uygunluk da NOW() ile denetlenir).
    const dbNowMs = Number(rows[0].db_now_ms);
    const nowMs = Number.isFinite(dbNowMs) ? dbNowMs : pushQueueHooks.now();
    const finals = { ids: [], statuses: [], reasons: [], codes: [] };
    const finish = (row, status, reason = null, code = null) => {
      finals.ids.push(row.id);
      finals.statuses.push(status);
      finals.reasons.push(reason);
      finals.codes.push(code);
      if (status === 'expired') summary.expired += 1;
      else if (status === 'failed') summary.failed += 1;
      else summary.skipped += 1;
    };
    const deferIds = [];
    const deferUntil = [];
    const candidates = [];
    for (const row of rows) {
      const urgent = row.importance === 'urgent';
      if (Number(row.attempts) >= MAX_PUSH_ATTEMPTS) {
        // zehirli / tükenmiş satır (ör. çöken sürecin 4. denemedeki bayat talebi): gönderilmez, kuyruğu tıkamaz
        finish(row, 'failed', null, 'MAX_ATTEMPTS');
      } else if (row.is_expired === true || Number(row.ttl_left) < 1) {
        finish(row, 'expired');
      } else if (row.user_live !== true) {
        finish(row, 'skipped', 'inactive');
      } else if (row.announcement_status !== 'published' || row.still_recipient !== true) {
        finish(row, 'skipped', 'withdrawn');
      } else if (!urgent && row.push_announcements === false) {
        finish(row, 'skipped', 'pref');
      } else {
        const quiet = urgent
          ? { defer: false }
          : quietDecision({
              nowMs,
              enabled: row.push_quiet_enabled === true,
              start: Number(row.push_quiet_start),
              end: Number(row.push_quiet_end),
              expiresAtMs: new Date(row.expires_at).getTime(),
            });
        if (quiet.expire) {
          finish(row, 'expired');
        } else if (quiet.defer) {
          deferIds.push(row.id);
          deferUntil.push(new Date(quiet.untilMs).toISOString());
          summary.deferred += 1;
          summary.deferredIds.push(Number(row.id));
        } else {
          candidates.push(row);
        }
      }
    }
    if (candidates.length > 0) {
      const userCodes = [...new Set(candidates.map((row) => Number(row.user_code)))];
      const normalUsers = [...new Set(candidates.filter((row) => row.importance !== 'urgent').map((row) => Number(row.user_code)))];
      const sentToday = new Map();
      if (normalUsers.length > 0) {
        const counts = await client.query(
          `
            SELECT user_code, COUNT(*)::INTEGER AS n
            FROM push_outbox
            WHERE status = 'sent' AND importance = 'normal' AND user_code = ANY($1::INTEGER[]) AND sent_at >= $2::TIMESTAMPTZ
            GROUP BY user_code
          `,
          [normalUsers, new Date(istanbulDayStartMs(nowMs)).toISOString()],
        );
        for (const entry of counts.rows ?? []) sentToday.set(Number(entry.user_code), Number(entry.n));
      }
      const devices = await client.query(
        `
          SELECT id, user_code, platform, fcm_token
          FROM push_devices
          WHERE user_code = ANY($1::INTEGER[]) AND notifications_enabled
          ORDER BY user_code, id
        `,
        [userCodes],
      );
      const devicesByUser = new Map();
      for (const device of devices.rows ?? []) {
        const key = Number(device.user_code);
        if (!devicesByUser.has(key)) devicesByUser.set(key, []);
        devicesByUser.get(key).push({ id: Number(device.id), platform: device.platform, token: device.fcm_token });
      }
      for (const row of candidates) {
        const userCode = Number(row.user_code);
        const userDevices = devicesByUser.get(userCode) ?? [];
        if (row.importance !== 'urgent' && (sentToday.get(userCode) ?? 0) >= maxPerDay) {
          // capped KALICI atlamadır (erteleme değil): bu duyurunun push'u bu kullanıcıya bir daha denenmez.
          finish(row, 'skipped', 'capped');
        } else if (userDevices.length === 0) {
          finish(row, 'skipped', 'no_device');
        } else {
          if (row.importance !== 'urgent') {
            // Aynı gruptaki sonraki satırlar için kota bu satır GÖNDERİLMİŞ sayılarak düşülür (sonuç bilinmeden). Gönderim başarısız olursa sınır
            // gereğinden erken dolabilir: o gruptaki sonraki satırlar da kalıcı olarak capped olur (fazla bildirim yerine eksik bildirim yönünde hata).
            sentToday.set(userCode, (sentToday.get(userCode) ?? 0) + 1);
          }
          summary.send.push({
            id: Number(row.id),
            announcementId: Number(row.announcement_id),
            siteCode: Number(row.site_code),
            userCode,
            importance: row.importance === 'urgent' ? 'urgent' : 'normal',
            attempts: Math.min(Number(row.attempts) + 1, ATTEMPTS_CEILING),
            ttlSeconds: Number(row.ttl_left),
            title: row.title,
            siteName: row.site_name,
            showPreview: row.push_show_preview === true,
            devices: userDevices,
          });
        }
      }
    }
    if (finals.ids.length > 0) {
      await client.query(
        `
          UPDATE push_outbox o
          SET status = v.st, skip_reason = v.reason, claimed_at = NULL, last_error_code = COALESCE(v.code, o.last_error_code)
          FROM unnest($1::BIGINT[], $2::TEXT[], $3::TEXT[], $4::TEXT[]) AS v(id, st, reason, code)
          WHERE o.id = v.id
        `,
        [finals.ids, finals.statuses, finals.reasons, finals.codes],
      );
    }
    if (deferIds.length > 0) {
      await client.query(
        `
          UPDATE push_outbox o
          SET not_before = v.at, claimed_at = NULL
          FROM unnest($1::BIGINT[], $2::TIMESTAMPTZ[]) AS v(id, at)
          WHERE o.id = v.id
        `,
        [deferIds, deferUntil],
      );
    }
    if (summary.send.length > 0) {
      await client.query(
        `UPDATE push_outbox SET attempts = LEAST(attempts + 1, ${ATTEMPTS_CEILING}), claimed_at = NOW() WHERE id = ANY($1::BIGINT[])`,
        [summary.send.map((row) => row.id)],
      );
    }
    await client.query('COMMIT');
    began = false;
    for (const row of summary.send) inFlightClaims.add(row.id);
    return summary;
  } finally {
    if (began) {
      try {
        await client.query('ROLLBACK');
      } catch (_rollbackError) {
        // bağlantı zaten kopmuş olabilir
      }
    }
    client.release();
  }
}

// ---------------------------------------------------------------------------------------------------------
// Gönderim ve sonuç
// ---------------------------------------------------------------------------------------------------------

/** Satırın suçu olmayan (deneme İADE edilen) sonuçlar ve satır başına bekleme (sn). */
const PARKED_KINDS = new Set(['auth', 'not_sent', 'apns_blocked', 'apns_auth', 'rate_limited', 'mass_dead', 'stopping', 'dead_unconfirmed']);
/** Gerçekten FCM'e gitmemiş sonuçlar (toplu ölü jeton oranının paydası değildir). */
const UNSENT_KINDS = new Set(['not_sent', 'apns_blocked', 'stopping', 'rate_limited_skip']);

/** Bir grubun tüm (satır x cihaz) gönderimleri; devre kesici / 429 / toplu ölü durumu `run` nesnesinde tutulur. */
async function deliverBatch(fcm, rows, concurrency, run) {
  const jobs = [];
  for (const row of rows) {
    for (const device of row.devices) jobs.push({ row, device });
  }
  const nowMs = pushQueueHooks.now();
  const outcomes = await mapLimited(jobs, concurrency, async ({ row, device }) => {
    if (stopRequested) {
      return { kind: 'stopping', code: 'STOPPING' };
    }
    if (run.tripped) {
      return { kind: 'not_sent', code: 'BREAKER' };
    }
    if (run.rateLimitSeconds > 0) {
      return { kind: 'rate_limited_skip', code: 'QUOTA_EXCEEDED' };
    }
    if (device.platform === 'ios' && breaker.apnsBlockedUntil > pushQueueHooks.now()) {
      return { kind: 'apns_blocked', code: 'APNS_AUTH' };
    }
    let result;
    try {
      result = await fcm.send(
        buildAnnouncementMessage({
          token: device.token,
          announcementId: row.announcementId,
          siteCode: row.siteCode,
          siteName: row.siteName,
          title: row.title,
          importance: row.importance,
          showPreview: row.showPreview,
          nowMs,
          ttlSeconds: row.ttlSeconds,
        }),
      );
    } catch (_error) {
      result = { kind: 'transient', code: 'SEND_FAILED', httpStatus: null };
    }
    if (result.kind === 'transient' && result.httpStatus === 429) {
      // Kota: tur duraklar (Retry-After, yoksa 60 sn, en çok 10 dk); bu ve kalan gönderimler deneme iadesiyle pending.
      const pause = Number(result.retryAfterSeconds);
      const seconds = Math.min(Math.max(Number.isFinite(pause) && pause > 0 ? Math.ceil(pause) : RATE_LIMIT_DEFAULT_PAUSE_SECONDS, 1), RATE_LIMIT_MAX_PAUSE_SECONDS);
      run.rateLimitSeconds = Math.max(run.rateLimitSeconds, seconds);
      result = { ...result, kind: 'rate_limited' };
    } else if (result.kind === 'ok') {
      run.consecutive = 0;
    } else if (result.kind === 'auth' || (result.kind === 'transient' && (result.httpStatus === null || result.httpStatus >= 500))) {
      run.consecutive += 1;
      if (run.consecutive >= BREAKER_THRESHOLD) {
        run.tripped = true;
      }
    } else if (result.kind === 'apns_auth') {
      breaker.apnsBlockedUntil = pushQueueHooks.now() + APNS_BLOCK_MS;
    }
    if (result.kind !== 'ok') {
      breaker.lastErrorCode = sanitizeErrorCode(result.code);
    }
    return result;
  });
  // Ölü jeton korumaları: yanlış proje / yanlış uç tüm cihazları "ölü" gösterebilir.
  const attemptedCount = outcomes.filter((outcome) => !UNSENT_KINDS.has(outcome.kind)).length;
  const deadCount = outcomes.filter((outcome) => outcome.kind === 'dead').length;
  const okCount = outcomes.filter((outcome) => outcome.kind === 'ok').length;
  const guard = recordDeliveryOutcome({ ok: okCount, dead: deadCount }, pushQueueHooks.account());
  // (b) grup: >= 20 gönderim, yarıdan fazlası ölü ve başarı oranı < %5 (başarıyla karışık gerçek ölü jetonlar normal silinir)
  const batchMass = attemptedCount >= MASS_DEAD_MIN_SENDS && deadCount * 2 > attemptedCount && okCount / attemptedCount < MASS_DEAD_MAX_SUCCESS_RATIO;
  // (a) süreç: son başarıdan beri >= 20 ölü ve bu grupta başarı yok
  const processMass = deadCount > 0 && okCount === 0 && guard.deadSinceSuccess >= MASS_DEAD_MIN_SENDS;
  if (batchMass || processMass) {
    run.massDead = true;
    run.tripped = true;
    breaker.lastErrorCode = 'MASS_DEAD';
    for (let i = 0; i < outcomes.length; i += 1) {
      if (outcomes[i].kind === 'dead') outcomes[i] = { ...outcomes[i], kind: 'mass_dead', code: 'MASS_DEAD' };
    }
  } else if (deadCount > 0 && !guard.successSeen) {
    // bu hizmet hesabıyla henüz başarı yok: ölü sonuç doğrulanmadı -> cihaz silinmez, satır deneme iadesiyle pending
    for (let i = 0; i < outcomes.length; i += 1) {
      if (outcomes[i].kind === 'dead') outcomes[i] = { ...outcomes[i], kind: 'dead_unconfirmed' };
    }
  }
  return jobs.map((job, index) => ({ ...job, outcome: outcomes[index] }));
}

/** Deneme iadeli (parked) bekleme süresi ve kodu: en uzun bekleme / en ağır neden kazanır. */
function parkedDelay(kind, run) {
  switch (kind) {
    case 'rate_limited':
    case 'rate_limited_skip':
      return { delay: run.rateLimitSeconds || RATE_LIMIT_DEFAULT_PAUSE_SECONDS, code: 'QUOTA_EXCEEDED', rank: 5 };
    case 'mass_dead':
      return { delay: Math.ceil(BREAKER_COOLDOWN_MS / 1000), code: 'MASS_DEAD', rank: 6 };
    case 'apns_auth':
    case 'apns_blocked':
      return { delay: Math.ceil(APNS_BLOCK_MS / 1000), code: 'APNS_AUTH', rank: 4 };
    case 'dead_unconfirmed':
      return { delay: DEAD_UNCONFIRMED_RETRY_SECONDS, code: null, rank: 3 };
    case 'stopping':
      return { delay: 0, code: 'STOPPING', rank: 1 };
    default:
      return { delay: BREAKER_RETRY_SECONDS, code: null, rank: 2 };
  }
}

/** Satır başına karar (sent / pending / failed / skipped:no_device) + cihaz sonuçları. */
function decide(rows, deliveries, run) {
  const byRow = new Map(rows.map((row) => [row.id, []]));
  for (const delivery of deliveries) byRow.get(delivery.row.id).push(delivery);
  const decisions = [];
  const devices = { successIds: [], failures: [], notes: [], dead: [] };
  for (const row of rows) {
    const list = byRow.get(row.id) ?? [];
    let ok = 0;
    let retryable = false;
    let invalid = false;
    let parked = null;
    let retryAfter = 0;
    let code = null;
    for (const { device, outcome } of list) {
      if (outcome.kind === 'ok') {
        ok += 1;
        devices.successIds.push(device.id);
      } else if (outcome.kind === 'dead') {
        devices.dead.push({ id: device.id, token: device.token });
        code = code ?? outcome.code;
      } else if (outcome.kind === 'transient') {
        retryable = true;
        retryAfter = Math.max(retryAfter, Number(outcome.retryAfterSeconds ?? 0));
        devices.failures.push({ id: device.id, code: outcome.code });
        code = outcome.code;
      } else if (outcome.kind === 'invalid') {
        // çıplak 404 / mesaj hatası: cihazın suçu değil -> failure_count artmaz (yalnız kod)
        invalid = true;
        devices.notes.push({ id: device.id, code: outcome.code });
        code = code ?? outcome.code;
      } else if (PARKED_KINDS.has(outcome.kind) || outcome.kind === 'rate_limited_skip') {
        if (outcome.kind === 'apns_auth') devices.notes.push({ id: device.id, code: 'APNS_AUTH' });
        if (outcome.kind === 'dead_unconfirmed') devices.notes.push({ id: device.id, code: outcome.code });
        const park = parkedDelay(outcome.kind, run);
        if (!parked || park.rank > parked.rank) {
          parked = { ...park, code: park.code ?? sanitizeErrorCode(outcome.code ?? 'BREAKER') };
        }
      }
    }
    if (ok > 0) {
      decisions.push({ id: row.id, status: 'sent', reason: null, refund: 0, delay: 0, devices: ok, code: null });
    } else if (retryable) {
      const failed = row.attempts >= MAX_PUSH_ATTEMPTS;
      decisions.push({
        id: row.id,
        status: failed ? 'failed' : 'pending',
        reason: null,
        refund: 0,
        delay: failed ? 0 : Math.max(retryDelaySeconds(row.attempts), Math.min(retryAfter, 3600)),
        devices: 0,
        code: sanitizeErrorCode(code ?? 'TRANSIENT'),
      });
    } else if (parked) {
      decisions.push({ id: row.id, status: 'pending', reason: null, refund: -1, delay: parked.delay, devices: 0, code: sanitizeErrorCode(parked.code) });
    } else if (invalid) {
      decisions.push({ id: row.id, status: 'failed', reason: null, refund: 0, delay: 0, devices: 0, code: sanitizeErrorCode(code ?? 'INVALID') });
    } else {
      // yalnız ölü jeton(lar): cihaz satırları silinir, bildirim gidecek cihaz kalmadı
      decisions.push({ id: row.id, status: 'skipped', reason: 'no_device', refund: 0, delay: 0, devices: 0, code: sanitizeErrorCode(code ?? 'UNREGISTERED') });
    }
  }
  return { decisions, devices };
}

/**
 * Sonuçları yazar (otomatik onaylı kısa ifade). Yalnız hâlâ pending satırlar (hesap silme bu arada silebilir). Satırlar id sırasıyla kilitlenir
 * (hesap silmedeki DELETE ile aynı sıra); 40P01'de ifade bir kez yeniden denenir.
 */
async function finalizeBatch(decisions) {
  if (decisions.length === 0) {
    return;
  }
  const params = [
    decisions.map((d) => d.id),
    decisions.map((d) => d.status),
    decisions.map((d) => d.reason),
    decisions.map((d) => d.refund),
    decisions.map((d) => d.delay),
    decisions.map((d) => d.devices),
    decisions.map((d) => d.code),
  ];
  await retryOnDeadlock(() =>
    pool.query(
      `
        UPDATE push_outbox o
        SET status = v.st,
            skip_reason = v.reason,
            attempts = GREATEST(0, o.attempts + v.refund),
            claimed_at = NULL,
            not_before = CASE WHEN v.st = 'pending' THEN NOW() + make_interval(secs => v.delay::DOUBLE PRECISION) ELSE o.not_before END,
            sent_device_count = v.devices,
            last_error_code = v.code,
            sent_at = CASE WHEN v.st = 'sent' THEN NOW() ELSE o.sent_at END
        FROM unnest($1::BIGINT[], $2::TEXT[], $3::TEXT[], $4::INTEGER[], $5::INTEGER[], $6::INTEGER[], $7::TEXT[])
          AS v(id, st, reason, refund, delay, devices, code)
        WHERE o.id = v.id AND o.status = 'pending'
          AND o.id IN (SELECT id FROM push_outbox WHERE id = ANY($1::BIGINT[]) ORDER BY id FOR UPDATE)
      `,
      params,
    ),
  );
  for (const decision of decisions) inFlightClaims.delete(decision.id);
}

/**
 * Kuyruğu bir kez boşaltmaya çalışır. Push hazır değilse { skipped: 'unavailable' }, devre kesici / 429 duraklaması sürüyorsa { skipped: 'breaker' },
 * kilit başka yerdeyse { skipped: 'locked' }. Ağ / DB hatası yukarı fırlar (kickPushQueue yakalar ve loglar).
 */
export async function runPushQueue({
  batchSize = PUSH_BATCH_SIZE,
  batchDelayMs = PUSH_BATCH_DELAY_MS,
  maxRunMs = PUSH_MAX_RUN_MS,
  concurrency = PUSH_SEND_CONCURRENCY,
} = {}) {
  if (!pushQueueHooks.available()) {
    return { skipped: 'unavailable' };
  }
  const fcm = pushQueueHooks.client();
  if (!fcm) {
    return { skipped: 'unavailable' };
  }
  if (breaker.openUntil > pushQueueHooks.now()) {
    return { skipped: 'breaker' };
  }
  const lock = await acquireSessionLock(PUSH_QUEUE_LOCK_JOB);
  if (!lock) {
    return { skipped: 'locked' };
  }
  const summary = { sent: 0, failed: 0, retry: 0, parked: 0, skipped: 0, expired: 0, deferred: 0, batches: 0, breaker: false, rateLimited: false, massDead: false };
  const run = { consecutive: 0, tripped: false, rateLimitSeconds: 0, massDead: false };
  try {
    const attempted = [];
    const startedAt = pushQueueHooks.now();
    while (!stopRequested && pushQueueHooks.now() - startedAt < maxRunMs) {
      const claimed = await claimBatch(batchSize, attempted);
      if (claimed.picked === 0) {
        break;
      }
      summary.skipped += claimed.skipped;
      summary.expired += claimed.expired;
      summary.deferred += claimed.deferred;
      summary.failed += claimed.failed;
      // ertelenen satır aynı turda yeniden talep edilmez (saat kayması / pencere sonunda sıkı döngü yok)
      for (const id of claimed.deferredIds) attempted.push(id);
      if (claimed.send.length === 0) {
        continue;
      }
      summary.batches += 1;
      for (const row of claimed.send) attempted.push(row.id);
      const deliveries = await deliverBatch(fcm, claimed.send, concurrency, run);
      const { decisions, devices } = decide(claimed.send, deliveries, run);
      await finalizeBatch(decisions);
      await applyDeviceOutcomes(devices);
      const codes = new Set();
      for (const decision of decisions) {
        if (decision.status === 'sent') summary.sent += 1;
        else if (decision.status === 'failed') summary.failed += 1;
        else if (decision.status === 'skipped') summary.skipped += 1;
        else if (decision.refund < 0) summary.parked += 1;
        else summary.retry += 1;
        if (decision.code && decision.status !== 'sent') codes.add(decision.code);
      }
      // 429 ve devre kesici AYNI grupta olabilir: openUntil = max(şimdi + RA, devre kesici ? şimdi + 5 dk : 0); iki bayrak ve iki günlük de yazılır.
      if (run.rateLimitSeconds > 0 || run.tripped) {
        const now = pushQueueHooks.now();
        if (run.rateLimitSeconds > 0) {
          summary.rateLimited = true;
          breaker.openUntil = Math.max(breaker.openUntil, now + run.rateLimitSeconds * 1000);
          logRateLimited('rate', `[push] FCM kotasi (429): tur ${run.rateLimitSeconds} sn duraklatildi`);
        }
        if (run.tripped) {
          summary.breaker = true;
          summary.massDead = run.massDead;
          breaker.openUntil = Math.max(breaker.openUntil, now + BREAKER_COOLDOWN_MS);
          logRateLimited(
            run.massDead ? 'mass_dead' : 'breaker',
            run.massDead
              ? '[push] devre kesici acildi: toplu olu jeton (MASS_DEAD; yanlis proje / uc?) - cihaz SILINMEDI'
              : `[push] devre kesici acildi (art arda ${BREAKER_THRESHOLD} kimlik/sunucu hatasi): son kod=${breaker.lastErrorCode ?? 'HATA'}`,
          );
        }
        break;
      }
      if (codes.size > 0) {
        // eslint-disable-next-line no-console
        console.error(`[push] gonderim hatasi: kodlar=${[...codes].join(',')}`);
      }
      await pushQueueHooks.sleep(batchDelayMs);
    }
    return summary;
  } finally {
    await lock.release();
  }
}

/** Kapanışta sonuçlanmamış talepleri bırakır (claimed_at NULL, deneme iadesi; satır hemen yeniden talep edilebilir). Asla fırlatmaz. */
export async function releaseInFlightClaims(db = pool) {
  if (inFlightClaims.size === 0) {
    return 0;
  }
  const ids = [...inFlightClaims];
  inFlightClaims.clear();
  try {
    const result = await db.query(
      `
        UPDATE push_outbox
        SET claimed_at = NULL, attempts = GREATEST(0, attempts - 1)
        WHERE id IN (SELECT id FROM push_outbox WHERE id = ANY($1::BIGINT[]) ORDER BY id FOR UPDATE)
          AND status = 'pending' AND claimed_at IS NOT NULL
      `,
      [ids],
    );
    return Number(result.rowCount ?? 0);
  } catch (error) {
    // eslint-disable-next-line no-console
    console.error('[push] kapanista talepler birakilamadi:', error?.code || error?.name || 'hata');
    return 0;
  }
}

/** Kuyruğu arka planda başlatır (bekletmez); çalışan tur varsa onu döndürür. Hata sunucuyu düşürmez, yalnız kod loglanır. */
export function kickPushQueue(options = {}) {
  if (stopRequested) {
    return Promise.resolve({ skipped: 'stopping' });
  }
  if (!pushQueueHooks.available()) {
    return Promise.resolve({ skipped: 'unavailable' });
  }
  if (activeRun) {
    return activeRun;
  }
  activeRun = runPushQueue(options)
    .catch((error) => {
      // eslint-disable-next-line no-console
      console.error('[push] kuyruk turu basarisiz:', error?.code || error?.name || 'hata');
      return { error: String(error?.code || 'ERROR') };
    })
    .finally(() => {
      activeRun = null;
    });
  return activeRun;
}

// ---------------------------------------------------------------------------------------------------------
// Bakım
// ---------------------------------------------------------------------------------------------------------

/**
 * Cihaz bakımı: 60 gün hareketsiz; kalıcı hatalı (>= 5 hata ve 30 gündür başarı yok); kimliksizleştirilmiş hesaba kalmış satırlar (hesap silme zaten aynı
 * işlemde siler; bu yalnız yarış kalıntısı süpürmesidir). Pasif (silinmemiş) hesabın cihazı KALIR: yeniden etkinleşebilir, gönderim talep anında atlanır.
 */
export async function runDeviceMaintenance(db = pool) {
  // sırasız (otomatik onaylı tek ifade): 40P01'de bir kez yeniden denenir
  const idle = await retryOnDeadlock(() => db.query(`DELETE FROM push_devices WHERE last_seen_at < NOW() - make_interval(days => $1::INTEGER)`, [DEVICE_IDLE_DAYS]));
  const failing = await retryOnDeadlock(() => db.query(
    `
      DELETE FROM push_devices
      WHERE failure_count >= $1 AND COALESCE(last_success_at, created_at) < NOW() - make_interval(days => $2::INTEGER)
    `,
    [DEVICE_FAILURE_LIMIT, DEVICE_FAILURE_DAYS],
  ));
  const orphaned = await retryOnDeadlock(() => db.query(
    `DELETE FROM push_devices d USING users u WHERE u.user_code = d.user_code AND u.deleted_at IS NOT NULL`,
  ));
  return { idle: Number(idle.rowCount ?? 0), failing: Number(failing.rowCount ?? 0), orphaned: Number(orphaned.rowCount ?? 0) };
}

/** Tek bakım turu (kuyruk ile aynı tek-çalışan kilidi; kilit başkasındaysa atlanır). Asla fırlatmaz. */
export async function runPushMaintenanceOnce() {
  let lock = null;
  try {
    lock = await acquireSessionLock(PUSH_QUEUE_LOCK_JOB);
    if (!lock) {
      return { skipped: 'locked' };
    }
    const outbox = await runOutboxMaintenance(pool);
    const devices = await runDeviceMaintenance(pool);
    return { outbox, devices };
  } catch (error) {
    // eslint-disable-next-line no-console
    console.error('[push] bakim basarisiz:', error?.code || error?.name || 'hata');
    return { error: String(error?.code || 'ERROR') };
  } finally {
    if (lock) {
      await lock.release().catch(() => {});
    }
  }
}

// ---------------------------------------------------------------------------------------------------------
// Başlat / durdur (server.js)
// ---------------------------------------------------------------------------------------------------------

let maintenanceTimer = null;
let maintenanceFirstTimer = null;
let maintenanceRun = null;

function isWorkerDisabled(env) {
  const value = (name) => String(env?.[name] ?? '').trim().toLowerCase();
  return ['1', 'true', 'yes'].includes(value('ANNOUNCEMENT_SCHEDULER_DISABLED')) || ['1', 'true', 'yes'].includes(value('PUSH_WORKER_DISABLED'));
}

function runMaintenanceInBackground() {
  if (stopRequested || maintenanceRun) {
    return;
  }
  maintenanceRun = runPushMaintenanceOnce().finally(() => {
    maintenanceRun = null;
  });
}

/**
 * Açılışta: hizmet hesabını BİR KEZ yükler (sır loglanmaz; yalnız durum), bakım zamanlayıcısını başlatır (unref'li). Kuyruk turları zamanlayıcı tikinde
 * (hasPendingPush) ve yayından sonra (kickPushQueue) tetiklenir. ANNOUNCEMENT_SCHEDULER_DISABLED=1 / PUSH_WORKER_DISABLED=1 (testler) ile bakım başlamaz.
 * @returns {{ enabled: boolean, configured: boolean } }
 */
export function startPushWorker({ env = process.env } = {}) {
  const state = loadPushRuntime(env);
  stopRequested = false;
  // eslint-disable-next-line no-console
  console.log(
    `[push] telefon bildirimi: ${state.enabled ? 'ACIK' : 'kapali'}; hizmet hesabi: ${
      state.configured ? `yuklendi (proje ${state.account.projectId})` : `yok (${state.error ?? 'HATA'})`
    }${state.enabled && !state.configured ? ' -> push KULLANILAMAZ (push_available:false)' : ''}`,
  );
  if (!isWorkerDisabled(env) && !maintenanceTimer) {
    maintenanceTimer = setInterval(runMaintenanceInBackground, MAINTENANCE_INTERVAL_MS);
    maintenanceTimer.unref?.();
    maintenanceFirstTimer = setTimeout(() => {
      maintenanceFirstTimer = null;
      runMaintenanceInBackground();
    }, MAINTENANCE_FIRST_DELAY_MS);
    maintenanceFirstTimer.unref?.();
  }
  return { enabled: state.enabled, configured: state.configured };
}

/**
 * Kapanış: yeni tur başlatmaz, çalışan turdaki başlamamış gönderimleri yapmaz (talepleri deneme iadesiyle hemen bırakılır), çalışan tur / bakımın
 * bitmesini en çok `timeoutMs` bekler, sonra hâlâ sonuçlanmamış talepleri bırakır.
 */
export async function stopPushWorker({ timeoutMs = 5000 } = {}) {
  stopRequested = true;
  if (maintenanceTimer) {
    clearInterval(maintenanceTimer);
    maintenanceTimer = null;
  }
  if (maintenanceFirstTimer) {
    clearTimeout(maintenanceFirstTimer);
    maintenanceFirstTimer = null;
  }
  const pending = [activeRun, maintenanceRun].filter(Boolean);
  if (pending.length > 0) {
    let timeout = null;
    try {
      await Promise.race([
        Promise.allSettled(pending),
        new Promise((resolve) => {
          timeout = setTimeout(resolve, timeoutMs);
        }),
      ]);
    } finally {
      clearTimeout(timeout);
    }
  }
  // Süre dolduğunda hâlâ sonuçlanmamış talepler 10 dk asılı kalmasın: bırakılır (deneme iadesi; en az bir kez teslim).
  await releaseInFlightClaims();
}

// ---------------------------------------------------------------------------------------------------------
// Yönetici durumu
// ---------------------------------------------------------------------------------------------------------

/**
 * GET /admin/push/status -> { enabled, configured, project_id, devices_total, pending, sent_24h, failed_24h, last_error_code, last_success_at }.
 * Jeton / sır / e-posta YOK. failed_24h: son 24 saatte oluşturulmuş ve `failed` olan satırlar.
 */
export async function getPushStatus(db = pool) {
  const state = pushRuntime();
  const row =
    (
      await db.query(
        `
          SELECT
            (SELECT COUNT(*)::INTEGER FROM push_devices) AS devices_total,
            (SELECT COUNT(*)::INTEGER FROM push_outbox WHERE status = 'pending') AS pending,
            (SELECT COUNT(*)::INTEGER FROM push_outbox WHERE status = 'sent' AND sent_at > NOW() - INTERVAL '24 hours') AS sent_24h,
            (SELECT COUNT(*)::INTEGER FROM push_outbox WHERE status = 'failed' AND created_at > NOW() - INTERVAL '24 hours') AS failed_24h,
            (SELECT last_error_code FROM push_outbox WHERE last_error_code IS NOT NULL ORDER BY id DESC LIMIT 1) AS last_outbox_error,
            (SELECT MAX(last_success_at) FROM push_devices) AS last_success_at
        `,
      )
    ).rows?.[0] ?? {};
  const lastSuccess = row.last_success_at ? new Date(row.last_success_at) : null;
  return {
    enabled: state.enabled === true,
    configured: state.configured === true,
    project_id: state.configured ? state.account.projectId : null,
    devices_total: Number(row.devices_total ?? 0),
    pending: Number(row.pending ?? 0),
    sent_24h: Number(row.sent_24h ?? 0),
    failed_24h: Number(row.failed_24h ?? 0),
    last_error_code: breaker.lastErrorCode ?? row.last_outbox_error ?? (state.configured ? null : state.error ?? null),
    last_success_at: lastSuccess && !Number.isNaN(lastSuccess.getTime()) ? lastSuccess.toISOString() : null,
  };
}
