// Kiraci her zaman daire admini (kullanici karari 2026-10-26; docs/PLATFORM_FINANS_KASALAR.md bolum 7, docs/PLATFORM_DAIRE_YONETIMI.md).
//
// Kural: dairede GUNCEL KIRACI varsa ve kiracinin hesabi + aktif daire uyeligi varsa daire admini (apartment_memberships.role = 'APARTMENT_ADMIN')
// kiracidir. Malik ve kiraci ayni dairede birlikte kayitlidir; malik admin kalamaz. Kiraci ayrilinca admin yeniden malik olur (mevcut kural).
//
// TEK UYGULAMA: bu dosyadaki SQL hem acilista/migration 081'de (TUM daireler) hem de calisma aninda (bir kisi ya da birkac daire: kiraci eklendi,
// hesap baglandi, toplu yukleme) kullanilir. Ifadeler `membership_service.applyApartmentPrimaryAdmin` ("Aile Reisini Degistir" kurali) ile AYNI veriyi
// yazar: mevcut tum adminler FAMILY_MEMBER, kiraci APARTMENT_ADMIN, eski sakin gostergesi (apartments.resident_user_code) kiraciya tasinir (gosterge
// BASKA kisiye geciyorsa onceki gostergenin iletisim e-postasi ve "PIN verildi" isareti temizlenir), adli kayda `admin_changed` satiri yazilir, acik yonetim
// devri kapanir ve kiraci icin `tenant_delegated` devri acilir. Kapi izinleri / MQTT / BLE / door_access_overrides'a DOKUNULMAZ (yalniz rol sutunu).
// Paritesi gercek PostgreSQL'de sinanir (scripts/qa_tenant_admin_section.mjs A16).
//
// Atlananlar (yetkiyi GENISLETMEZ, yalniz var olan erisimi kullanir):
//  - kiracinin hesabi yok / silinmis / pasif ya da bu dairede AKTIF uyeligi yok (pasife alinmis) -> admin degismez;
//  - kapi erisimi askiya alinmis kisi (apartment_access_suspensions, lifted_at IS NULL) -> admin yapilmaz;
//  - site yoneticisinin "Daire adminini degistir" kararina dayanan acik devir (source = 'manager'): acilista ve hesap baglama gibi dolayli yollarda
//    KORUNUR (guvenlik politikasi); yalniz kiraci YENI eklenirken (overrideManager) yeni kiraci icin devir yeniden kurulur.
//
// Bu dosya db.js'i ve baska yerel modulu ICE AKTARMAZ (db.js acilista kullanir; dongu olmasin). Calisma ani sarmalayicisi: apartment_tenant_admin.js.
//
// Parametreler (hepsi her ifadede aday alt sorgusu uzerinden kullanilir):
//   $1 BIGINT[]  daire kimlikleri (NULL = tum daireler)        $2 INTEGER  kiraci kullanici kodu suzgeci (NULL = hepsi)
//   $3 BOOLEAN   site yoneticisi devrini ez (calisma ani)      $4 TEXT     yol etiketi (denetim ayrintisinda `via`)
//   $5 INTEGER   islemi yapan kullanici kodu (NULL = sistem)   $6 TEXT     islemi yapanin adi
//   $7 TEXT      denetim rolu                                   $8 TEXT     adli kayit rolu (residency log actor_role)

const LABEL_SQL = `LEFT(NULLIF(btrim(CASE WHEN COALESCE(b.block_name, '') <> '' AND COALESCE(a.unit_label, '') <> '' THEN b.block_name || ' - ' || a.unit_label ELSE COALESCE(NULLIF(b.block_name, ''), a.unit_label, '') END), ''), 80)`;

/** Yetkili olmaya aday daireler. Sutunlar tum ifadelerce `c.` ile okunur. */
const CANDIDATES = `SELECT a.id AS apartment_id, a.site_code, ${LABEL_SQL} AS label,
    r.person_id AS tenant_person_id, r.move_in_date AS tenant_move_in, sp.user_code AS tenant_user_code, u.full_name AS tenant_name,
    (SELECT o.user_code FROM apartment_memberships o WHERE o.apartment_id = a.id AND o.role = 'APARTMENT_ADMIN' AND o.is_active = TRUE AND o.user_code <> sp.user_code ORDER BY o.created_at, o.id LIMIT 1) AS prev_admin_user_code,
    (SELECT orr.person_id FROM apartment_residencies orr WHERE orr.apartment_id = a.id AND orr.is_current = TRUE AND orr.relation = 'owner' LIMIT 1) AS owner_person_id,
    $4::TEXT AS via, $5::INTEGER AS actor_user_code, $6::TEXT AS actor_name, $7::TEXT AS audit_role, $8::TEXT AS log_role
  FROM apartments a
  LEFT JOIN site_blocks b ON b.id = a.block_id
  INNER JOIN apartment_residencies r ON r.apartment_id = a.id AND r.is_current = TRUE AND r.relation = 'tenant'
  INNER JOIN site_people sp ON sp.id = r.person_id AND sp.is_active = TRUE AND sp.user_code IS NOT NULL
  INNER JOIN users u ON u.user_code = sp.user_code AND u.deleted_at IS NULL AND u.is_active = TRUE
  INNER JOIN apartment_memberships tm ON tm.apartment_id = a.id AND tm.user_code = sp.user_code AND tm.is_active = TRUE
  WHERE a.is_active = TRUE
    AND ($1::BIGINT[] IS NULL OR a.id = ANY($1::BIGINT[]))
    AND ($2::INTEGER IS NULL OR sp.user_code = $2::INTEGER)
    AND (tm.role <> 'APARTMENT_ADMIN' OR EXISTS (
      SELECT 1 FROM apartment_memberships x WHERE x.apartment_id = a.id AND x.role = 'APARTMENT_ADMIN' AND x.is_active = TRUE AND x.user_code <> sp.user_code
    ))
    AND NOT EXISTS (
      SELECT 1 FROM apartment_access_suspensions s WHERE s.apartment_id = a.id AND s.user_code = sp.user_code AND s.lifted_at IS NULL
    )
    AND ($3::BOOLEAN OR NOT EXISTS (
      SELECT 1 FROM apartment_admin_delegations d WHERE d.apartment_id = a.id AND d.ended_at IS NULL AND d.source = 'manager'
    ))`;

/**
 * Ifade SIRASI BAGLAYICIDIR. 0. ifade YALNIZ KILITLER: aday daireleri id sirasiyla FOR UPDATE kilitler (eszamanli ikinci calistirma kilitte bekler);
 * sonraki her ifade YENI bir anlik goruntuyle aday kumesini yeniden hesaplar. Boylece bekleme sirasinda baska islem adayi cozdugunde cift denetim /
 * adli kayit satiri YAZILMAZ (READ COMMITTED'de kilit sonrasi diger tablolar ESKI goruntuyle yeniden degerlendirilirdi).
 * Aday kumesi `apartment_memberships` guncellemesine (son ifade) kadar degismez: once denetim / adli kayit / devir / bildirim, sonra gosterge, en son rol.
 * `TENANT_ADMIN_COUNT_INDEX` ifadesinin (denetim) satir sayisi = degisen daire sayisi.
 */
export const TENANT_ADMIN_COUNT_INDEX = 1;
export const TENANT_ADMIN_STATEMENTS = Object.freeze([
  // 0. kilit (aday daireler, id sirasiyla)
  `SELECT a.id FROM apartments a
WHERE a.id IN (SELECT c.apartment_id FROM (${CANDIDATES}) c)
ORDER BY a.id
FOR UPDATE OF a`,
  // 1. denetim kaydi (kisisel veri yok: yalniz kimlikler ve yol etiketi)
  `INSERT INTO audit_log (actor_user_code, actor_name, actor_role, action, site_code, target_type, target_id, details)
SELECT c.actor_user_code, c.actor_name, c.audit_role, 'apartment.admin_tenant_enforced', c.site_code, 'apartment', c.apartment_id::TEXT,
       jsonb_strip_nulls(jsonb_build_object('via', c.via, 'tenant_person_id', c.tenant_person_id, 'from_user_code', c.prev_admin_user_code, 'to_user_code', c.tenant_user_code))
FROM (${CANDIDATES}) c`,
  // 2. adli kayit (apartment_residency_log): admin_changed, membership_service.applyApartmentPrimaryAdmin ile ayni alanlar
  `INSERT INTO apartment_residency_log (
  site_code, apartment_id, apartment_label, event_type, reason_code, subject_name, subject_relation, subject_person_id,
  subject_user_code, period_start, period_end, actor_user_code, actor_name, actor_role, related
)
SELECT c.site_code, c.apartment_id, c.label, 'admin_changed', 'handover', LEFT(NULLIF(btrim(COALESCE(c.tenant_name, '')), ''), 120), 'tenant', c.tenant_person_id,
       c.tenant_user_code, c.tenant_move_in, NULL, c.actor_user_code, LEFT(NULLIF(btrim(COALESCE(c.actor_name, '')), ''), 120), c.log_role,
       jsonb_strip_nulls(jsonb_build_object('from_user_code', c.prev_admin_user_code, 'to_user_code', c.tenant_user_code))
FROM (${CANDIDATES}) c`,
  // 3. acik yonetim devri kapanir (recordDelegation ile ayni neden)
  `UPDATE apartment_admin_delegations d
SET state = 'ended', ended_at = NOW(), end_reason = 'replaced'
FROM (${CANDIDATES}) c
WHERE d.apartment_id = c.apartment_id AND d.ended_at IS NULL`,
  // 4. kiraci icin yeni devir
  `INSERT INTO apartment_admin_delegations (site_code, apartment_id, owner_person_id, admin_person_id, admin_user_code, source, state, created_by)
SELECT c.site_code, c.apartment_id, c.owner_person_id, c.tenant_person_id, c.tenant_user_code, 'tenant_delegated', 'active', c.actor_user_code
FROM (${CANDIDATES}) c`,
  // 5. uygulama ici bildirim (e-posta degil): yeni admin kiraciya ve onceki admine; islemi yapana yazilmaz
  `INSERT INTO apartment_notices (site_code, apartment_id, user_code, kind, message)
SELECT c.site_code, c.apartment_id, t.user_code, 'admin_tenant_enforced', t.message
FROM (${CANDIDATES}) c
CROSS JOIN LATERAL (VALUES
  (c.tenant_user_code, COALESCE(c.label, 'Daire') || ' dairesinde kiracı olduğunuz için daire yöneticisi artık sizsiniz.'),
  (c.prev_admin_user_code, COALESCE(c.label, 'Daire') || ' dairesinin yönetimi kiracıya geçti (kiracı daire yöneticisidir). Dairede kalmaya devam ediyorsunuz.')
) AS t(user_code, message)
WHERE t.user_code IS NOT NULL AND t.user_code IS DISTINCT FROM c.actor_user_code`,
  // 6. eski sakin gostergesi kiraciya tasinir (gosterge baska kisiye geciyorsa onceki gostergenin e-postasi ve PIN verildi isareti temizlenir)
  `UPDATE apartments a
SET resident_email = CASE WHEN a.resident_user_code IS DISTINCT FROM c.tenant_user_code THEN NULL ELSE a.resident_email END,
    resident_pin_issued = CASE WHEN a.resident_user_code IS DISTINCT FROM c.tenant_user_code THEN FALSE ELSE a.resident_pin_issued END,
    resident_pin_code = NULL,
    resident_user_code = c.tenant_user_code
FROM (${CANDIDATES}) c
WHERE a.id = c.apartment_id`,
  // 7. rol: mevcut tum adminler FAMILY_MEMBER, kiraci APARTMENT_ADMIN (SON ifade: aday kumesi bundan sonra bosalir)
  `UPDATE apartment_memberships m
SET role = CASE WHEN m.user_code = c.tenant_user_code THEN 'APARTMENT_ADMIN' ELSE 'FAMILY_MEMBER' END,
    updated_at = NOW()
FROM (${CANDIDATES}) c
WHERE m.apartment_id = c.apartment_id
  AND ((m.role = 'APARTMENT_ADMIN' AND m.user_code <> c.tenant_user_code)
       OR (m.user_code = c.tenant_user_code AND m.is_active = TRUE AND m.role <> 'APARTMENT_ADMIN'))`,
]);

/** Aday var mi (tek satir okuma). Calisma aninda ve acilista gereksiz kilit / yazma olmasin diye once bu calisir. */
export const TENANT_ADMIN_CHECK_SQL = `SELECT 1 FROM (${CANDIDATES}) c LIMIT 1`;

const literal = (value) => {
  if (value === null || value === undefined) return 'NULL';
  if (typeof value === 'boolean') return value ? 'TRUE' : 'FALSE';
  if (typeof value === 'number') return String(value);
  return `'${String(value).replace(/'/g, "''")}'`;
};

/** `$1..$8` yer tutucularini SQL degerleriyle degistirir (migration dosyasi ve acilis icin parametresiz metin). */
export function inlineTenantAdminParams(sql, values) {
  return sql.replace(/\$([1-8])\b/g, (_match, index) => literal(values[Number(index) - 1]));
}

/** Tum daireler, sistem adina, site yoneticisi devri KORUNUR. */
export const TENANT_ADMIN_BACKFILL_PARAMS = Object.freeze([null, null, false, 'backfill', null, 'Sistem', 'system', 'system']);

/** migrations/081 gövdesi (ifadeler ';' ile ayrilir) ve ensureDbSchema'nin her acilista (aday varsa) calistirdigi metin. */
export const TENANT_ADMIN_BACKFILL_SQL = `${TENANT_ADMIN_STATEMENTS.map((statement) => inlineTenantAdminParams(statement, TENANT_ADMIN_BACKFILL_PARAMS)).join(';\n\n')};\n`;

export const TENANT_ADMIN_BACKFILL_CHECK_SQL = inlineTenantAdminParams(TENANT_ADMIN_CHECK_SQL, TENANT_ADMIN_BACKFILL_PARAMS);

/**
 * Acilis adimi (db.js tek cagri): aday yoksa YALNIZ bir okuma yapar; varsa tum ifadeler tek ortuk islemde (parametresiz basit sorgu) calisir.
 * @returns {Promise<number>} degisen daire sayisi
 */
export async function ensureTenantAdminRule(client) {
  const found = await client.query(TENANT_ADMIN_BACKFILL_CHECK_SQL);
  if (!found.rows?.[0]) {
    return 0;
  }
  const results = await client.query(TENANT_ADMIN_BACKFILL_SQL);
  const counted = Array.isArray(results) ? results[TENANT_ADMIN_COUNT_INDEX] : results;
  return counted?.rowCount ?? 0;
}
