// Daire admini daireden ayrilirken (cikarilir, silinir, pasife alinir, tasinir, kiracilik biter) yonetimi devralacak kalan uyenin secimi.
//
// ONCELIK (kullanici karari 2026-10-26, "kiraci her zaman daire admini"): 1) guncel KIRACI, 2) guncel MALIK, 3) mevcut kural: en eski aktif uye.
// Kiraci/malik adayi: hesapli (uyeligi var), AKTIF uyelikli, hesabi silinmemis ve aktif, kisi kaydi aktif ve kapi erisimi ASKIDA OLMAYAN kisidir
// (askidaki kisi ust siraya yukselmez; en eski aktif uye kuralina duser). Boylece kiraci cikarilinca yonetim MALIGE doner, kiracinin aile uyesine
// gecmez; malik cikarilirken kiraci dairedeyse yonetim kiraciya gecer.
//
// TEK YARDIMCI: membership_service.handOverApartmentResident (daireden cikar, sakini sil, pasife al, CRM "Tasindi" = people_service.closeResidency ->
// revokeApartmentAccess) bu secimi kullanir. Bu dosya BAGIMSIZ YAPRAK moduldur (hicbir yerel modulu ice aktarmaz; membership_service dongusu olmasin).

/** Sirali kalan uye sorgusunun ORDER BY ifadesindeki sira: ilgili iliski turunde, uygun ise `rank`, degilse sonraki kural. */
function eligibleAs(relation) {
  return `EXISTS (
        SELECT 1 FROM apartment_residencies r
        INNER JOIN site_people sp ON sp.id = r.person_id AND sp.is_active = TRUE
        INNER JOIN users u ON u.user_code = sp.user_code AND u.deleted_at IS NULL AND u.is_active = TRUE
        WHERE r.apartment_id = apartment_memberships.apartment_id AND r.is_current = TRUE AND r.relation = '${relation}'
          AND sp.user_code = apartment_memberships.user_code
      )
      AND NOT EXISTS (
        SELECT 1 FROM apartment_access_suspensions s
        WHERE s.apartment_id = apartment_memberships.apartment_id AND s.user_code = apartment_memberships.user_code AND s.lifted_at IS NULL
      )`;
}

/**
 * $1 = daire, $2 = ayrilan kullanici kodu. En fazla bir satir (kullanici kodu). Sorgu `SELECT user_code FROM apartment_memberships WHERE apartment_id = $1
 * AND user_code <> $2 AND is_active = TRUE ORDER BY` ile baslar (eski "en eski aktif uye" sorgusunun oneki aynen; yalniz ORDER BY'a siralama eklendi).
 */
export const ADMIN_SUCCESSOR_SQL = `SELECT user_code FROM apartment_memberships
WHERE apartment_id = $1 AND user_code <> $2 AND is_active = TRUE
ORDER BY CASE
      WHEN ${eligibleAs('tenant')} THEN 0
      WHEN ${eligibleAs('owner')} THEN 1
      ELSE 2
    END, created_at ASC, id ASC
LIMIT 1`;

/**
 * Ayrilan kullanicidan sonra daire admini olacak aktif uyenin kullanici kodu; kimse yoksa null.
 * @param {{ query: Function }} client acik transaction'daki baglanti
 */
export async function pickAdminSuccessor(client, apartmentId, removedUserCode) {
  const result = await client.query(ADMIN_SUCCESSOR_SQL, [apartmentId, removedUserCode]);
  const row = result?.rows?.[0];
  return row === undefined || row === null ? null : Number(row.user_code);
}
