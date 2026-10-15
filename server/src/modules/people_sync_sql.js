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
 * PASİF dahili (@ahbu.local) daire hesabı: taşınan sakinin hesabı kapatıldı, giriş/kapı kapalı -> kişi kartında "hesapsız" davranır
 * (people_common: HAS_ACCOUNT_SQL / ACCOUNT_KIND_SQL / accountKindOf bunu kullanır) ve eşitleme ona YENİ kişi kaydı AÇMAZ: CRM'den hesaptan
 * koparılıp düzenlenmiş kişinin yerine, eski göstergeye bağlı ikinci ("hayalet") bir kişi satırı doğmasın. SQL ifadesi `users` tablosunu `u`
 * takma adıyla bekler.
 */
export const DEAD_INTERNAL_ACCOUNT_SQL = `(u.user_code IS NOT NULL AND u.email LIKE '%${INTERNAL_EMAIL_SUFFIX}' AND u.is_active = FALSE)`;

/**
 * "Sitede bağ" tanımının TEK kaynağı (eşitleme LINK adımı, createPerson/addResidency hesap bağlama, erişim verme ve "kişiyi hesaptan
 * kopar / aktif kalsın" kararları bunu kullanır). Kullanıcının bağı olan siteler: aktif dairede aktif apartment_memberships satırı VEYA o
 * dairede apartments.resident_user_code göstergesi (yukarıdaki `desired` kümesiyle AYNI). Yalnız site_memberships (STAFF / BOARD_MEMBER /
 * RESIDENT) ya da yöneticilik TEK BAŞINA bağ SAYILMAZ: yönetici başkasının hesabına ek rol vererek o hesabı "bağlı" yapıp kişi kaydına
 * bağlayamaz.
 * @param {string} userExpr kullanıcı kodu SQL ifadesi (ör. 'u.user_code', '$1::INTEGER')
 */
export function siteTieSitesSql(userExpr) {
  return `
      SELECT tie_a.site_code FROM apartment_memberships tie_am
      INNER JOIN apartments tie_a ON tie_a.id = tie_am.apartment_id
      WHERE tie_am.user_code = ${userExpr} AND tie_am.is_active = TRUE AND tie_a.is_active = TRUE
      UNION
      SELECT tie_r.site_code FROM apartments tie_r
      WHERE tie_r.resident_user_code = ${userExpr} AND tie_r.is_active = TRUE
    `;
}

/**
 * Kullanıcının bu sitede bağı var mı: hesap AKTİF (pasif hesap bağlanmaz / bağlı sayılmaz) ve site, siteTieSitesSql kümesinde.
 * @param {string} userExpr kullanıcı kodu SQL ifadesi (ör. 'u.user_code', '$1')
 * @param {string} siteExpr site kodu SQL ifadesi (ör. 'sp.site_code', '$2')
 */
export function siteTiePredicate(userExpr, siteExpr) {
  return `(
    EXISTS (SELECT 1 FROM users tie_u WHERE tie_u.user_code = ${userExpr} AND tie_u.is_active = TRUE)
    AND ${siteExpr} IN (${siteTieSitesSql(userExpr)})
  )`;
}

/**
 * 1) Aynı e-postaya sahip hesapsız kişi varsa yinelenen kayıt açmak yerine o kişiye user_code bağlanır. Bağlanınca ad/telefon/e-posta
 * alanları BOŞALTILIR (hesaplı kişide okuma users'tan; hesap silinirse users BEFORE DELETE tetikleyicisi ad/telefonu yedekler).
 * Güvenlik: bağlama yalnız o sitede ZATEN erişimi (aktif üyelik / eski sakin göstergesi) olan AKTİF hesaplarla yapılır (siteTiePredicate).
 * Kullanıcıya özgü eşitlemede ($2) site_code, kullanıcının bağı olan sitelerle sınırlanır: site_people tamamı taranmaz (indeks: uq_site_people_email).
 * Elle girilmiş (origin='manual') ilişkiler bağlanınca korunur.
 */
const LINK_ACCOUNTLESS_SQL = `
  UPDATE site_people sp
  SET user_code = u.user_code, full_name = NULL, phone = NULL, email = NULL, updated_at = NOW()
  FROM users u
  WHERE sp.user_code IS NULL
    AND sp.is_active = TRUE
    AND sp.email IS NOT NULL
    AND lower(u.email) = lower(sp.email)
    AND u.email NOT LIKE '%${INTERNAL_EMAIL_SUFFIX}'
    AND ($1::BIGINT IS NULL OR sp.site_code = $1::BIGINT)
    AND ($2::INTEGER IS NULL OR u.user_code = $2::INTEGER)
    AND ($2::INTEGER IS NULL OR sp.site_code IN (${siteTieSitesSql('$2::INTEGER')}))
    AND ${siteTiePredicate('u.user_code', 'sp.site_code')}
    AND NOT EXISTS (
      SELECT 1 FROM site_people x WHERE x.site_code = sp.site_code AND x.user_code = u.user_code
    )
`;

/**
 * 2) Aktif erişimi olan her hesap için (site, kullanıcı) kişi kaydı; yoksa eklenir. Dahili hesapta iletişim e-postası saklanır.
 * PASİF dahili daire hesabına (DEAD_INTERNAL_ACCOUNT_SQL) yeni kişi açılmaz; mevcut kişi kayıtları etkilenmez.
 */
const INSERT_PEOPLE_SQL = `
  WITH ${DESIRED_CTE}
  INSERT INTO site_people (site_code, user_code, email)
  SELECT
    d.site_code,
    d.user_code,
    CASE WHEN u.email LIKE '%${INTERNAL_EMAIL_SUFFIX}' THEN MAX(d.contact_email) ELSE NULL END
  FROM desired d
  INNER JOIN users u ON u.user_code = d.user_code
  WHERE NOT ${DEAD_INTERNAL_ACCOUNT_SQL}
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
 * Son ilişkisi biten kişi pasif olur (araçları da) ve hesaptan KOPARILIR: ad/telefon/e-posta o anki hâliyle kişi satırına yazılır,
 * user_code NULL olur (taşınan kişinin hesabını sonradan değiştirdiği bilgi bu sitede görünmesin). Hesapsız kişilere dokunulmaz.
 * Sistem adına audit satırı yazılır.
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
    SET is_active = FALSE,
        full_name = COALESCE(NULLIF(u.full_name, ''), sp.full_name),
        phone = COALESCE(NULLIF(u.phone_number, ''), sp.phone),
        email = CASE
          WHEN u.email LIKE '%${INTERNAL_EMAIL_SUFFIX}' THEN COALESCE(
            (SELECT a.resident_email FROM apartments a WHERE a.resident_user_code = sp.user_code AND a.site_code = sp.site_code ORDER BY a.id LIMIT 1),
            sp.email
          )
          ELSE u.email
        END,
        user_code = NULL,
        updated_at = NOW()
    FROM users u
    WHERE u.user_code = sp.user_code
      AND sp.id IN (SELECT person_id FROM ended)
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
