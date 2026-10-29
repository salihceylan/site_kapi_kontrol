// Hesap silme sırasında bekleyen alacak iadesi talepleri (Dalga B, K4 kararı): bekleyen iade talebi hesap silmeyi ENGELLEMEZ; silmede talep İPTAL edilir (durum 'cancelled') ve
// işlem izine (audit_log) yazılır. Onaylı / reddedilmiş / geri alınmış talepler değişmez (defter eklemelidir). Yalnız silinen kullanıcının KENDİ açtığı talepler (requested_by_kind = 'resident').
//
// Hafif tutuldu (finance_refunds.js'nin ağır içe aktarmalarına bağlanmaz): hesap silme hizmeti bunu aynı işlem bağlantısında (client) çağırır. Tablo yoksa (eski şema) sessizce 0.
// Kilit sırası: kullanıcı satırı (silme adım 6) -> talep satırları; onay yolu da daire -> kullanıcı -> talep sırasındadır. Çekişmede silme zaten kilitlenme yeniden denemesine sahiptir.

import { recordAudit } from './audit_service.js';

const SYSTEM_ACTOR = Object.freeze({ name: 'Sistem', role: 'system' });

/** Denetim ve test için sabit neden kodu. */
export const REFUND_CANCEL_REASON_ACCOUNT_DELETED = 'account_deleted';

/**
 * @param {{ query: Function }} client açık işlemdeki bağlantı
 * @param {number} userCode silinen kullanıcı
 * @returns {Promise<number>} iptal edilen talep sayısı
 */
export async function cancelUserPendingRefunds(client, userCode) {
  const present = (await client.query(`SELECT to_regclass('public.finance_refunds') IS NOT NULL AS present`)).rows?.[0];
  if (present?.present !== true) {
    return 0;
  }
  const pending = await client.query(
    `
      SELECT id, site_code, apartment_id, amount_minor::TEXT AS amount_minor
      FROM finance_refunds
      WHERE requested_by = $1 AND requested_by_kind = 'resident' AND status = 'requested'
      ORDER BY id
      FOR UPDATE
    `,
    [userCode],
  );
  let cancelled = 0;
  for (const row of pending.rows ?? []) {
    const updated = await client.query(
      `UPDATE finance_refunds SET status = 'cancelled', resolved_by = $2, resolved_at = NOW() WHERE id = $1 AND status = 'requested'`,
      [row.id, userCode],
    );
    if ((updated.rowCount ?? 0) < 1) {
      continue;
    }
    cancelled += 1;
    // Denetim: yalnız tutar / kimlik / neden (not ve ad YOK).
    await recordAudit(
      client,
      {
        actor: SYSTEM_ACTOR,
        action: 'finance.refund.cancelled',
        siteCode: Number(row.site_code),
        targetType: 'finance',
        targetId: String(row.id),
        details: { apartment_id: Number(row.apartment_id), amount_minor: Number(row.amount_minor), reason: REFUND_CANCEL_REASON_ACCOUNT_DELETED },
      },
      { inTransaction: true },
    );
  }
  return cancelled;
}
