// Malik bildirimlerinde borç tutarı gizliliği (kapanış; çoklu malikli daire / migration 104, docs/PLATFORM_COKLU_MALIK.md).
//
//  - Dairenin borcuyla ilgili bildirimlerde (kiracı borcunun malike devri, kiracı çıkışı) borç TUTARI yalnız HESAP MUHATABINA (is_account_holder) gider.
//  - Muhatap olmayan diğer maliklere tutarsız genel bir not gider ("dairenizle ilgili borç işlemi yapıldı, ayrıntılar hesap muhatabında"); diğer malik borç görmez.
//  - Muhatabın uygulama hesabı yoksa tutar KİMSEYE gitmez; hesabı olan diğer malikler yine yalnız genel notu alır.
//  - Dosya adı bilinçli olarak finance_ ile başlamaz: finans dosyalarında is_account_holder bayrağını yalnız 5 okuma dosyası kullanır (apartment_owners_rules testi).
//    Burası tahakkuk / tahsilat / defter YAZIMI değil, yalnız bildirim alıcısını seçer.
//  - Bildirim hatası çağıran işlemi ASLA bozmaz: notifyApartmentUsers kendi SAVEPOINT'ini kullanır ve hatayı yutar (0 döner).

import { notifyApartmentUsers } from './apartment_mgmt_core.js';

/** Muhatap OLMAYAN maliklere giden tutarsız genel not (tutar / kalem sayısı / kiracı bilgisi YOK). */
export const OWNER_DEBT_NOTE_FOR_OTHERS = 'Dairenizle ilgili bir borç işlemi yapıldı; ayrıntılar hesap muhatabında.';

/**
 * Dairenin güncel, etkin ve uygulama hesabı olan malikleri: HESAP MUHATABI (`holders`) ve DİĞER malikler (`others`).
 * @returns {Promise<{ holders: number[], others: number[] }>}
 */
export async function ownerNoticeTargets(db, apartmentId) {
  const result = await db.query(
    `
      SELECT sp.user_code, BOOL_OR(r.is_account_holder) AS is_account_holder
      FROM apartment_residencies r
      INNER JOIN site_people sp ON sp.id = r.person_id AND sp.is_active = TRUE AND sp.user_code IS NOT NULL
      WHERE r.apartment_id = $1 AND r.relation = 'owner' AND r.is_current = TRUE
      GROUP BY sp.user_code
      ORDER BY sp.user_code
    `,
    [apartmentId],
  );
  const holders = [];
  const others = [];
  for (const row of result.rows ?? []) {
    (row.is_account_holder === true ? holders : others).push(Number(row.user_code));
  }
  return { holders, others };
}

/**
 * Malik bildirimini yazar: muhataba `holderMessage` (tutar içerir), diğer maliklere `OWNER_DEBT_NOTE_FOR_OTHERS`. Yazılan bildirim sayısını döner.
 * @param {{ query: Function }} client  işlem istemcisi
 * @param {{ siteCode: number|string, apartmentId: number|string, kind: string, holderMessage: string }} entry
 * @returns {Promise<number>}
 */
export async function notifyOwnersWithPrivacy(client, { siteCode, apartmentId, kind, holderMessage }) {
  const { holders, others } = await ownerNoticeTargets(client, apartmentId);
  let notified = 0;
  if (holders.length > 0) {
    notified += await notifyApartmentUsers(client, { siteCode, apartmentId, userCodes: holders, kind, message: holderMessage });
  }
  if (others.length > 0) {
    notified += await notifyApartmentUsers(client, { siteCode, apartmentId, userCodes: others, kind, message: OWNER_DEBT_NOTE_FOR_OTHERS });
  }
  return notified;
}
