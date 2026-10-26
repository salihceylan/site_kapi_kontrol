// Daire sahipligi ve yonetimi: bir kisi daireden AYRILIRKEN / CIKARILIRKEN yonetim devri ve vekalet kayitlarinin kapatilmasi.
//
// BAGIMSIZ YAPRAK MODUL: hicbir yerel modulu ice aktarmaz (yalniz verilen transaction client'i uzerinde calisir). membership_service (daireden cikar /
// sil), apartment_mgmt_core (devir kaydi), apartment_mgmt_service (kiracilik sonu) ve people_service (closeResidency) AYNI kurali buradan kullanir;
// uyelik <-> daire yonetimi arasinda ice aktarma dongusu olusmaz.
//
// Neden gerekli: acik devir satiri (apartment_admin_delegations) resolveApartmentRoles'ta admin'i belirler. Devralan kisi daireden gittiginde satir
// kapanmazsa, yonetim giden kisiye "bagli" kalirdi (bkz. apartment_mgmt_rules.js: devir yalniz devralan guncel kiraciysa ve aktif uyeligi varsa uygulanir).

const REASON_MAX = 60;

/** Dairenin acik (bitmemis) yonetim devrini kapatir (idempotent). */
export async function endOpenDelegation(client, apartmentId, reason) {
  await client.query(
    `UPDATE apartment_admin_delegations SET state = 'ended', ended_at = NOW(), end_reason = $2 WHERE apartment_id = $1 AND ended_at IS NULL`,
    [apartmentId, String(reason).slice(0, REASON_MAX)],
  );
}

/**
 * Bir kisi bu daireden ayrilinca (cikarildi / silindi / kiracilik bitti):
 *  - o kisinin DEVRALAN oldugu acik yonetim devri kapanir (hesabi varsa user_code, hesapsizsa kisi kaydi ile eslesir),
 *  - o kisinin vekil OLDUGU ya da vekalet VERDIGI acik vekaletler iptal edilir (revoked_reason = reason).
 * Idempotent: eslesen satir yoksa hicbir sey yapmaz. Daire satirini cagiran kilitlemis olmalidir.
 *
 * ONEMLI (cagri sirasi): kisi kaydi (site_people) hesaptan koparilmadan ONCE cagrilmalidir (people_records.endResidenciesForMemberRemoval son iliskiyi
 * bitirince site_people.user_code'u NULL'lar; user_code ile kisi arayan alt sorgu o zaman bulamaz).
 *
 * @param {{ query: Function }} client acik transaction'daki baglanti
 * @param {{ siteCode: number|string, apartmentId: number|string, userCode?: number|string|null, personId?: number|string|null, reason: string }} params
 *   `personId`: hesapsiz kisi icin (userCode yok) site_people.id; verilmezse userCode ile bulunur.
 * @returns {Promise<{ delegationsClosed: number, proxiesRevoked: number }>}
 */
export async function closeDelegationsOnLeave(client, { siteCode, apartmentId, userCode = null, personId = null, reason }) {
  const user = userCode === undefined || userCode === null ? null : Number(userCode);
  const person = personId === undefined || personId === null ? null : Number(personId);
  if (user === null && person === null) {
    return { delegationsClosed: 0, proxiesRevoked: 0 };
  }
  const why = String(reason ?? 'member_left').slice(0, REASON_MAX);
  // Kisi kimlikleri: acik personId + (varsa) bu sitede user_code'a bagli kisi kayitlari.
  const personIdsSql = `(SELECT sp.id FROM site_people sp WHERE sp.site_code = $2::bigint AND sp.user_code = $3::int)`;

  const delegations = await client.query(
    `UPDATE apartment_admin_delegations
     SET state = 'ended', ended_at = NOW(), end_reason = $5::text
     WHERE apartment_id = $1::bigint AND ended_at IS NULL
       AND (admin_user_code = $3::int OR admin_person_id = $4::bigint OR admin_person_id IN ${personIdsSql})`,
    [apartmentId, siteCode, user, person, why],
  );
  const proxies = await client.query(
    `UPDATE apartment_proxies
     SET revoked_at = NOW(), revoked_reason = $5::text
     WHERE apartment_id = $1::bigint AND revoked_at IS NULL
       AND (proxy_person_id = $4::bigint OR owner_person_id = $4::bigint
            OR proxy_person_id IN ${personIdsSql} OR owner_person_id IN ${personIdsSql})`,
    [apartmentId, siteCode, user, person, why],
  );
  return { delegationsClosed: delegations?.rowCount ?? 0, proxiesRevoked: proxies?.rowCount ?? 0 };
}
