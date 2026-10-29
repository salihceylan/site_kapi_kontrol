// Hesap silme sırasında komşu panosu ilanları (064; kapanış kararı, KVKK): kullanıcının yazdığı İLANLAR silinir (başlık / gövde kişisel veri içerebilir) ve silme işlem izine
// (audit_log, site başına sayı) yazılır. İlanın şikâyet kayıtları (neighbor_post_reports) yabancı anahtar CASCADE ile birlikte gider. Kullanıcının BAŞKA ilanlara yaptığı
// şikâyetler (reporter_user_code) bu adımda değişmez (adli saklama, legal/account_deletion.md bölüm 3).
//
// Hesap satırı silinmez (tombstone), bu yüzden author_user_code FK SET NULL kendiliğinden çalışmaz: ilanlar AÇIKÇA silinir. Hesap silme hizmeti bunu aynı işlem
// bağlantısında (client) çağırır; kilit sırası: kullanıcı satırı (silme adım 6) -> ilan satırları (yalnız bu kullanıcının; başka işlemlerin tuttuğu paylaşılan satır yok).
// Tablo yoksa (064 öncesi şema) sessizce 0. Denetim kaydında ilan başlığı / gövdesi / yazan adı YOKTUR; yalnız sayı, durum dağılımı ve neden.

import { recordAudit } from './audit_service.js';

const SYSTEM_ACTOR = Object.freeze({ name: 'Sistem', role: 'system' });

/** Denetim ve test için sabit eylem adı ve neden kodu (site denetim kataloğunda `neighbor_board.` öneki "Site hizmetleri" kategorisindedir). */
export const NEIGHBOR_POSTS_DELETED_ACTION = 'neighbor_board.posts_deleted_account_closed';
export const NEIGHBOR_POSTS_DELETE_REASON = 'account_deleted';

/**
 * @param {{ query: Function }} client açık işlemdeki bağlantı
 * @param {number} userCode silinen kullanıcı
 * @returns {Promise<number>} silinen ilan sayısı
 */
export async function deleteUserNeighborPosts(client, userCode) {
  const present = (await client.query(`SELECT to_regclass('public.neighbor_posts') IS NOT NULL AS present`)).rows?.[0];
  if (present?.present !== true) {
    return 0;
  }
  const deleted = await client.query(`DELETE FROM neighbor_posts WHERE author_user_code = $1 RETURNING site_code, status`, [userCode]);
  const bySite = new Map();
  for (const row of deleted.rows ?? []) {
    const key = String(row.site_code);
    const entry = bySite.get(key) ?? { total: 0, statuses: {} };
    entry.total += 1;
    entry.statuses[row.status] = (entry.statuses[row.status] ?? 0) + 1;
    bySite.set(key, entry);
  }
  for (const [siteCode, entry] of [...bySite.entries()].sort((a, b) => Number(a[0]) - Number(b[0]))) {
    await recordAudit(
      client,
      {
        actor: SYSTEM_ACTOR,
        action: NEIGHBOR_POSTS_DELETED_ACTION,
        siteCode: Number(siteCode),
        targetType: 'neighbor_post',
        details: { count: entry.total, statuses: entry.statuses, reason: NEIGHBOR_POSTS_DELETE_REASON },
      },
      { inTransaction: true },
    );
  }
  return (deleted.rows ?? []).length;
}
