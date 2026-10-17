// Telefon bildirimi (Faz 3b-B): outbox yazımı (duyuru yayın işleminde), bekleyen satır kontrolü ve bakım silmeleri.
//
// Sözleşme: docs/PLATFORM_BELGELER.md B4 (e-posta kuyruğu kalıbı).
//  - Enqueue: duyuru yayın işleminde (publishWithinTransaction: elle yayın + zamanlayıcı), announcement_recipients eklendikten SONRA, AYNI işlemde tek
//    INSERT ... SELECT: alıcı kişilerden site_people.user_code dolu, kullanıcı aktif ve silinmemiş, en az bir notifications_enabled cihazı var,
//    `normal` ise COALESCE(push_announcements, TRUE). PUSH_ENABLED kapalıyken ya da hizmet hesabı yüklenemediyse HİÇ satır yazılmaz (ölü veri yok).
//    expires_at = yayın + 24 sa (normal) / 48 sa (urgent). UNIQUE (announcement_id, user_code) çift yayında çiftlemez (ON CONFLICT DO NOTHING).
//  - Site başına ACİL sınırı (PUSH_URGENT_MAX_PER_DAY_PER_SITE, varsayılan 3; e-postadaki siteDailyUrgentEmail ile aynı): sitenin İstanbul gününde outbox'a
//    acil olarak girmiş FARKLI duyuru sayısı sınırdaysa bu duyurunun satırları `normal` yazılır (tercih, sessiz saat ve kullanıcı sınırına tabi olur;
//    ele geçirilmiş / kötü niyetli bir yönetici gece herkese onlarca HIGH / time-sensitive bildirim gönderemez). Sayım yayın işleminin site kişi kilidi
//    (people_sync advisory) altındadır: aynı sitenin iki yayını sınırı birlikte aşamaz. Sayım kısmi (site_code, created_at) WHERE importance = 'urgent' indeksini kullanır.
//  - Kilit sırası: yayın işlemi zaten sites KEY SHARE -> people_sync advisory -> announcements -> recipients tutar; outbox EN SONA yazılır (users
//    satırı KİLİTLENMEZ: user_code'da FK yok, okuma kilitsiz). Outbox yazımının beklenmedik hatası duyuru yayınını BOZMAZ (SAVEPOINT; push ikincil
//    kanaldır, yoklama gerçeğin kaynağıdır - K8); 40P01 / 40001 ise işlem yeniden denensin diye yukarı fırlar.
//  - Bakım: süresi geçen pending -> expired; biten satırlar 14 gün sonra silinir; silinmiş / olmayan kullanıcının satırları silinir.

import { pool } from '../db.js';
import { EXPIRY_HOURS, OUTBOX_RETENTION_DAYS, PUSH_CLAIM_STALE_MINUTES, retryOnDeadlock } from './push_common.js';
import { pushUrgentMaxPerDayPerSite } from './push_config.js';
import { isPushAvailable } from './push_credentials.js';

const RETHROW_CODES = new Set(['40P01', '40001']);

export const ENQUEUE_ANNOUNCEMENT_SQL = `
  INSERT INTO push_outbox (kind, site_code, announcement_id, user_code, importance, expires_at)
  SELECT 'announcement', $2::BIGINT, $1::BIGINT, x.user_code, $3::TEXT, NOW() + make_interval(hours => $4::INTEGER)
  FROM (
    SELECT DISTINCT sp.user_code
    FROM announcement_recipients r
    INNER JOIN site_people sp ON sp.id = r.person_id AND sp.site_code = $2::BIGINT
    INNER JOIN users u ON u.user_code = sp.user_code AND u.is_active = TRUE AND u.deleted_at IS NULL
    LEFT JOIN notification_preferences np ON np.user_code = sp.user_code
    WHERE r.announcement_id = $1::BIGINT
      AND sp.user_code IS NOT NULL
      AND ($3::TEXT = 'urgent' OR COALESCE(np.push_announcements, TRUE))
      AND EXISTS (SELECT 1 FROM push_devices d WHERE d.user_code = sp.user_code AND d.notifications_enabled)
  ) x
  ON CONFLICT (announcement_id, user_code) DO NOTHING
`;

/** Sitenin İstanbul gününde outbox'a ACİL olarak girmiş farklı duyuru sayısı (bu duyuru hariç; DB saatine göre). */
export const URGENT_SITE_COUNT_SQL = `
  SELECT COUNT(DISTINCT announcement_id)::INTEGER AS n
  FROM push_outbox
  WHERE site_code = $1::BIGINT AND importance = 'urgent' AND announcement_id <> $2::BIGINT
    AND created_at >= (date_trunc('day', NOW() AT TIME ZONE 'Europe/Istanbul') AT TIME ZONE 'Europe/Istanbul')
`;

/** Test / QA için değiştirilebilir: outbox yazılsın mı (varsayılan: push gerçekten hazır) ve site başına günlük acil sınırı. */
export const pushOutboxHooks = {
  available: () => isPushAvailable(),
  urgentMaxPerSite: () => pushUrgentMaxPerDayPerSite(),
};

/**
 * Yayın işleminin İÇİNDE çağrılır (client = işlemin bağlantısı). Push kapalıysa sorgu bile göndermez.
 * @returns {Promise<number>} kuyruğa yazılan kullanıcı sayısı
 */
export async function enqueueAnnouncementPush(client, { announcementId, siteCode, importance }) {
  if (!pushOutboxHooks.available()) {
    return 0;
  }
  let level = importance === 'urgent' ? 'urgent' : 'normal';
  await client.query('SAVEPOINT push_outbox_enqueue');
  try {
    if (level === 'urgent') {
      const used = Number((await client.query(URGENT_SITE_COUNT_SQL, [siteCode, announcementId])).rows?.[0]?.n ?? 0);
      if (used >= pushOutboxHooks.urgentMaxPerSite()) {
        level = 'normal'; // site acil sınırı doldu: bu duyurunun push'u normal kurallara tabi
      }
    }
    const result = await client.query(ENQUEUE_ANNOUNCEMENT_SQL, [announcementId, siteCode, level, EXPIRY_HOURS[level]]);
    await client.query('RELEASE SAVEPOINT push_outbox_enqueue');
    return Number(result.rowCount ?? 0);
  } catch (error) {
    if (RETHROW_CODES.has(error?.code)) {
      throw error;
    }
    await client.query('ROLLBACK TO SAVEPOINT push_outbox_enqueue');
    await client.query('RELEASE SAVEPOINT push_outbox_enqueue');
    // eslint-disable-next-line no-console
    console.error(`[push] outbox yazilamadi (duyuru=${Number(announcementId)}); yayin surdu:`, error?.code || error?.name || 'hata');
    return 0;
  }
}

/**
 * İŞİ OLAN bekleyen satır var mı (kısmi indeks; hafif). Push hazır değilse sorgu yok (false).
 */
export async function hasPendingPush(db = pool) {
  if (!pushOutboxHooks.available()) {
    return false;
  }
  const result = await db.query(
    `
      SELECT 1
      FROM push_outbox
      WHERE status = 'pending' AND not_before <= NOW()
        AND (claimed_at IS NULL OR claimed_at < NOW() - make_interval(mins => $1::INTEGER))
      LIMIT 1
    `,
    [PUSH_CLAIM_STALE_MINUTES],
  );
  return Boolean(result.rows?.[0]);
}

/** Bakım (outbox): süresi geçen bekleyenler `expired`; 14 günden eski biten satırlar ve silinmiş / olmayan kullanıcının satırları silinir. */
export async function runOutboxMaintenance(db = pool) {
  // Bakım ifadeleri satırları SIRASIZ kilitler (otomatik onaylı tek ifade): 40P01'de bir kez yeniden denenir.
  const expired = await retryOnDeadlock(() => db.query(
    `
      UPDATE push_outbox
      SET status = 'expired', claimed_at = NULL
      WHERE status = 'pending' AND expires_at <= NOW()
        AND (claimed_at IS NULL OR claimed_at < NOW() - make_interval(mins => $1::INTEGER))
    `,
    [PUSH_CLAIM_STALE_MINUTES],
  ));
  const purged = await retryOnDeadlock(() => db.query(
    `DELETE FROM push_outbox WHERE status <> 'pending' AND created_at < NOW() - make_interval(days => $1::INTEGER)`,
    [OUTBOX_RETENTION_DAYS],
  ));
  // user_code'da FK yok (K15): hesap silme açıkça siler; burada kalıntılar (kalıcı silinen / kimliksizleştirilen hesap) süpürülür.
  const orphaned = await retryOnDeadlock(() => db.query(
    `
      DELETE FROM push_outbox o
      WHERE NOT EXISTS (SELECT 1 FROM users u WHERE u.user_code = o.user_code AND u.deleted_at IS NULL)
    `,
  ));
  return {
    expired: Number(expired.rowCount ?? 0),
    purged: Number(purged.rowCount ?? 0),
    orphaned: Number(orphaned.rowCount ?? 0),
  };
}
