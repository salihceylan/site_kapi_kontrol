// Kişi kayıtları (CRM) <-> erişim üyelikleri eşitleme SQL'i. DB bağlantısı İÇERMEZ (db.js'ten içe aktarılabilsin diye);
// yalnızca verilen bir `client` (transaction içinde) üzerinde çalışır.
//
// Sözleşme: docs/PLATFORM_KISILER.md ("Backfill people_v1" ve "syncSitePeople").
//  - Erişim yetkisinin tek kaynağı apartment_memberships kalır; burada HİÇBİR üyelik/kapı yetkisi satırı değiştirilmez.
//  - İstenen durum ("desired"): aktif daire + aktif apartment_memberships ve eski apartments.resident_user_code sakinleri.
//  - Tüm adımlar küme tabanlıdır (N+1 yok): bir siteyi eşitlemek sabit sayıda sorgudur.
//  - Her adım idempotenttir; ikinci çalıştırma satır değiştirmez.
//
// Parametreler: $1 = site_code (BIGINT, NULL = tüm siteler), $2 = user_code (INTEGER, NULL = tüm kullanıcılar).

const DESIRED_CTE = `
  desired AS (
    SELECT site_code, apartment_id, user_code, MIN(move_in) AS move_in, MAX(contact_email) AS contact_email
    FROM (
      SELECT a.site_code, a.id AS apartment_id, am.user_code, am.created_at::date AS move_in, NULL::text AS contact_email
      FROM apartment_memberships am
      INNER JOIN apartments a ON a.id = am.apartment_id
      WHERE am.is_active = TRUE
        AND a.is_active = TRUE
        AND ($1::BIGINT IS NULL OR a.site_code = $1::BIGINT)
        AND ($2::INTEGER IS NULL OR am.user_code = $2::INTEGER)
      UNION ALL
      SELECT a.site_code, a.id AS apartment_id, a.resident_user_code AS user_code, NULL::date AS move_in, a.resident_email AS contact_email
      FROM apartments a
      WHERE a.resident_user_code IS NOT NULL
        AND a.is_active = TRUE
        AND ($1::BIGINT IS NULL OR a.site_code = $1::BIGINT)
        AND ($2::INTEGER IS NULL OR a.resident_user_code = $2::INTEGER)
    ) src
    GROUP BY site_code, apartment_id, user_code
  )
`;

/** Dahili (daire hesabı) e-posta alanı: gerçek iletişim adresi değildir. */
export const INTERNAL_EMAIL_SUFFIX = '@ahbu.local';

/**
 * 1) Aynı e-postaya sahip hesapsız kişi varsa yinelenen kayıt açmak yerine o kişiye user_code bağlanır. Bağlanınca ad/telefon/e-posta
 * alanları BOŞALTILIR (hesaplı kişide okuma users'tan; hesap silinirse users BEFORE DELETE tetikleyicisi ad/telefonu yedekler).
 * Güvenlik: bağlama yalnız o sitede ZATEN erişimi (aktif üyelik / eski sakin göstergesi) olan hesaplarla yapılır (desired).
 * Elle girilmiş (origin='manual') ilişkiler bağlanınca korunur.
 */
const LINK_ACCOUNTLESS_SQL = `
  WITH ${DESIRED_CTE},
  candidates AS (
    SELECT DISTINCT d.site_code, d.user_code, lower(u.email) AS email
    FROM desired d
    INNER JOIN users u ON u.user_code = d.user_code
    WHERE u.email IS NOT NULL AND u.email NOT LIKE '%${INTERNAL_EMAIL_SUFFIX}'
  )
  UPDATE site_people sp
  SET user_code = c.user_code, full_name = NULL, phone = NULL, email = NULL, updated_at = NOW()
  FROM candidates c
  WHERE sp.site_code = c.site_code
    AND sp.user_code IS NULL
    AND sp.is_active = TRUE
    AND lower(sp.email) = c.email
    AND NOT EXISTS (
      SELECT 1 FROM site_people x WHERE x.site_code = c.site_code AND x.user_code = c.user_code
    )
`;

/** 2) Aktif erişimi olan her hesap için (site, kullanıcı) kişi kaydı; yoksa eklenir. Dahili hesapta iletişim e-postası saklanır. */
const INSERT_PEOPLE_SQL = `
  WITH ${DESIRED_CTE}
  INSERT INTO site_people (site_code, user_code, email)
  SELECT
    d.site_code,
    d.user_code,
    CASE WHEN u.email LIKE '%${INTERNAL_EMAIL_SUFFIX}' THEN MAX(d.contact_email) ELSE NULL END
  FROM desired d
  INNER JOIN users u ON u.user_code = d.user_code
  GROUP BY d.site_code, d.user_code, u.email
  ON CONFLICT (site_code, user_code) WHERE user_code IS NOT NULL DO NOTHING
`;

/** 3) Yeniden aktif erişim kazanan (taşınmış) kişi tekrar aktif olur. */
const REACTIVATE_PEOPLE_SQL = `
  WITH ${DESIRED_CTE}
  UPDATE site_people sp
  SET is_active = TRUE, updated_at = NOW()
  FROM (SELECT DISTINCT site_code, user_code FROM desired) d
  WHERE sp.site_code = d.site_code
    AND sp.user_code = d.user_code
    AND sp.is_active = FALSE
`;

/** 4) Eksik güncel ilişki kayıtları ('resident' = ilişki belirtilmemiş; tarih üyelik oluşturma gününden; kaynak 'sync'). */
const INSERT_RESIDENCIES_SQL = `
  WITH ${DESIRED_CTE}
  INSERT INTO apartment_residencies (site_code, apartment_id, person_id, relation, is_current, move_in_date, origin)
  SELECT d.site_code, d.apartment_id, sp.id, 'resident', TRUE, d.move_in, 'sync'
  FROM desired d
  INNER JOIN site_people sp ON sp.site_code = d.site_code AND sp.user_code = d.user_code
  ON CONFLICT (apartment_id, person_id) WHERE is_current DO NOTHING
`;

/**
 * 5) Otomatik bitirme: YALNIZ eşitleme kaynaklı (origin='sync') güncel ilişkiler ve YALNIZ destekleyen kayıt GERÇEKTEN kalmadıysa
 * (üyelik satırı silinmiş ve eski sakin göstergesi başka kişiye geçmiş/boşalmış). Pasif üyelik / askıya alınmış daire BİTİRMEZ
 * (geçici pasife alma taşınma değildir); elle girilmiş (origin='manual') ilişkiler yalnız açık "Taşındı"/pasifleştirmeyle biter.
 * Son ilişkisi biten kişi pasif olur (araçları da); hesapsız kişilere dokunulmaz. Sistem adına audit satırı yazılır.
 */
const END_UNBACKED_SQL = `
  WITH ended AS (
    UPDATE apartment_residencies r
    SET is_current = FALSE, move_out_date = CURRENT_DATE, updated_at = NOW()
    FROM site_people sp
    WHERE r.person_id = sp.id
      AND r.is_current = TRUE
      AND r.origin = 'sync'
      AND sp.user_code IS NOT NULL
      AND ($1::BIGINT IS NULL OR sp.site_code = $1::BIGINT)
      AND ($2::INTEGER IS NULL OR sp.user_code = $2::INTEGER)
      AND NOT EXISTS (
        SELECT 1 FROM apartment_memberships am WHERE am.apartment_id = r.apartment_id AND am.user_code = sp.user_code
      )
      AND NOT EXISTS (
        SELECT 1 FROM apartments a WHERE a.id = r.apartment_id AND a.resident_user_code = sp.user_code
      )
    RETURNING r.id, r.site_code, r.apartment_id, r.person_id, r.relation
  ),
  logged AS (
    INSERT INTO audit_log (actor_name, actor_role, action, site_code, target_type, target_id, details)
    SELECT
      'Sistem',
      'system',
      'residency.ended',
      e.site_code,
      'person',
      e.person_id::text,
      jsonb_build_object('residency_id', e.id, 'apartment_id', e.apartment_id, 'relation', e.relation, 'auto', TRUE)
    FROM ended e
    RETURNING id
  ),
  deactivated AS (
    UPDATE site_people sp
    SET is_active = FALSE, updated_at = NOW()
    WHERE sp.id IN (SELECT person_id FROM ended)
      AND sp.is_active = TRUE
      AND NOT EXISTS (
        SELECT 1 FROM apartment_residencies c
        WHERE c.person_id = sp.id AND c.is_current = TRUE AND c.id NOT IN (SELECT id FROM ended)
      )
    RETURNING sp.id, sp.site_code
  ),
  vehicles_off AS (
    UPDATE vehicles v
    SET is_active = FALSE
    WHERE v.person_id IN (SELECT id FROM deactivated) AND v.is_active = TRUE
    RETURNING v.id
  ),
  logged_people AS (
    INSERT INTO audit_log (actor_name, actor_role, action, site_code, target_type, target_id, details)
    SELECT 'Sistem', 'system', 'person.deactivated', d.site_code, 'person', d.id::text,
           jsonb_build_object('reason', 'residency_ended', 'auto', TRUE)
    FROM deactivated d
    RETURNING id
  )
  SELECT id FROM deactivated
`;

/**
 * 6) Yetim kişiler: hesabı silinmiş ve adı yedeklenmemiş (user_code NULL + full_name NULL) aktif kayıtlar "Silinmiş hesap"
 * hayaleti olarak kalmasın: pasifleştirilir, güncel ilişkileri ve araçları biter, Sistem adına audit yazılır.
 * (users BEFORE DELETE tetikleyicisi bunu silme anında yapar; bu adım tetikleyici öncesi/dışı kalıntıları toplar.)
 * Kullanıcıya özgü eşitlemede ($2 dolu) çalışmaz.
 */
const DEACTIVATE_ORPHANS_SQL = `
  WITH orphans AS (
    SELECT sp.id, sp.site_code
    FROM site_people sp
    WHERE sp.user_code IS NULL
      AND sp.full_name IS NULL
      AND sp.is_active = TRUE
      AND $2::INTEGER IS NULL
      AND ($1::BIGINT IS NULL OR sp.site_code = $1::BIGINT)
  ),
  ended AS (
    UPDATE apartment_residencies r
    SET is_current = FALSE, move_out_date = CURRENT_DATE, updated_at = NOW()
    FROM orphans o
    WHERE r.person_id = o.id AND r.is_current = TRUE
    RETURNING r.id, r.site_code, r.apartment_id, r.person_id, r.relation
  ),
  logged AS (
    INSERT INTO audit_log (actor_name, actor_role, action, site_code, target_type, target_id, details)
    SELECT
      'Sistem',
      'system',
      'residency.ended',
      e.site_code,
      'person',
      e.person_id::text,
      jsonb_build_object('residency_id', e.id, 'apartment_id', e.apartment_id, 'relation', e.relation, 'auto', TRUE, 'reason', 'account_deleted')
    FROM ended e
    RETURNING id
  ),
  vehicles_off AS (
    UPDATE vehicles v
    SET is_active = FALSE
    WHERE v.person_id IN (SELECT id FROM orphans) AND v.is_active = TRUE
    RETURNING v.id
  ),
  deactivated AS (
    UPDATE site_people sp
    SET is_active = FALSE, updated_at = NOW()
    FROM orphans o
    WHERE sp.id = o.id
    RETURNING sp.id, sp.site_code
  ),
  logged_people AS (
    INSERT INTO audit_log (actor_name, actor_role, action, site_code, target_type, target_id, details)
    SELECT 'Sistem', 'system', 'person.deactivated', d.site_code, 'person', d.id::text,
           jsonb_build_object('reason', 'account_deleted', 'auto', TRUE)
    FROM deactivated d
    RETURNING id
  )
  SELECT id FROM deactivated
`;

export const SYNC_STEPS = Object.freeze([
  { name: 'link_accountless', sql: LINK_ACCOUNTLESS_SQL },
  { name: 'insert_people', sql: INSERT_PEOPLE_SQL },
  { name: 'reactivate_people', sql: REACTIVATE_PEOPLE_SQL },
  { name: 'insert_residencies', sql: INSERT_RESIDENCIES_SQL },
  { name: 'end_unbacked', sql: END_UNBACKED_SQL },
  { name: 'deactivate_orphans', sql: DEACTIVATE_ORPHANS_SQL },
]);

/**
 * Eşitleme adımlarını verilen client üzerinde sırayla çalıştırır (transaction'ı ÇAĞIRAN yönetir).
 * @param {{ query: Function }} client
 * @param {{ siteCode?: number|null, userCode?: number|null }} [filters]
 * @returns {Promise<Record<string, number>>} adım başına etkilenen satır sayısı
 */
export async function runSyncSteps(client, { siteCode = null, userCode = null } = {}) {
  const counts = {};
  for (const step of SYNC_STEPS) {
    const result = await client.query(step.sql, [siteCode, userCode]);
    counts[step.name] = Number(result?.rowCount ?? 0);
  }
  return counts;
}
