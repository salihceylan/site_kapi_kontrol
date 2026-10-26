-- 081: Kiracı her zaman daire admini (kullanıcı kararı 2026-10-26; docs/PLATFORM_DAIRE_YONETIMI.md, docs/PLATFORM_FINANS_KASALAR.md bölüm 7).
-- Kaynak: server/src/modules/apartment_tenant_admin_sql.js TENANT_ADMIN_BACKFILL_SQL (ensureDbSchema aynı metni, aday varsa, her açılışta uygular).
-- Dairede GÜNCEL KİRACI varsa, kiracının hesabı ve aktif daire üyeliği varsa ve kapı erişimi askıda değilse daire admini (APARTMENT_ADMIN) kiracı olur:
-- mevcut adminler FAMILY_MEMBER, eski sakin göstergesi kiracıya taşınır, adli kayda admin_changed, denetim kaydına apartment.admin_tenant_enforced,
-- kiracı için tenant_delegated devri ve uygulama içi bildirim yazılır. Site yöneticisinin "Daire adminini değiştir" kararı (devir kaynağı manager) KORUNUR.
-- Kapı izinleri / MQTT / door_access_overrides'a dokunulmaz. Idempotent: aday yoksa (kiracı zaten admin) hiçbir satır yazmaz.
SELECT a.id FROM apartments a
WHERE a.id IN (SELECT c.apartment_id FROM (SELECT a.id AS apartment_id, a.site_code, LEFT(NULLIF(btrim(CASE WHEN COALESCE(b.block_name, '') <> '' AND COALESCE(a.unit_label, '') <> '' THEN b.block_name || ' - ' || a.unit_label ELSE COALESCE(NULLIF(b.block_name, ''), a.unit_label, '') END), ''), 80) AS label,
    r.person_id AS tenant_person_id, r.move_in_date AS tenant_move_in, sp.user_code AS tenant_user_code, u.full_name AS tenant_name,
    (SELECT o.user_code FROM apartment_memberships o WHERE o.apartment_id = a.id AND o.role = 'APARTMENT_ADMIN' AND o.is_active = TRUE AND o.user_code <> sp.user_code ORDER BY o.created_at, o.id LIMIT 1) AS prev_admin_user_code,
    (SELECT orr.person_id FROM apartment_residencies orr WHERE orr.apartment_id = a.id AND orr.is_current = TRUE AND orr.relation = 'owner' LIMIT 1) AS owner_person_id,
    'backfill'::TEXT AS via, NULL::INTEGER AS actor_user_code, 'Sistem'::TEXT AS actor_name, 'system'::TEXT AS audit_role, 'system'::TEXT AS log_role
  FROM apartments a
  LEFT JOIN site_blocks b ON b.id = a.block_id
  INNER JOIN apartment_residencies r ON r.apartment_id = a.id AND r.is_current = TRUE AND r.relation = 'tenant'
  INNER JOIN site_people sp ON sp.id = r.person_id AND sp.is_active = TRUE AND sp.user_code IS NOT NULL
  INNER JOIN users u ON u.user_code = sp.user_code AND u.deleted_at IS NULL AND u.is_active = TRUE
  INNER JOIN apartment_memberships tm ON tm.apartment_id = a.id AND tm.user_code = sp.user_code AND tm.is_active = TRUE
  WHERE a.is_active = TRUE
    AND (NULL::BIGINT[] IS NULL OR a.id = ANY(NULL::BIGINT[]))
    AND (NULL::INTEGER IS NULL OR sp.user_code = NULL::INTEGER)
    AND (tm.role <> 'APARTMENT_ADMIN' OR EXISTS (
      SELECT 1 FROM apartment_memberships x WHERE x.apartment_id = a.id AND x.role = 'APARTMENT_ADMIN' AND x.is_active = TRUE AND x.user_code <> sp.user_code
    ))
    AND NOT EXISTS (
      SELECT 1 FROM apartment_access_suspensions s WHERE s.apartment_id = a.id AND s.user_code = sp.user_code AND s.lifted_at IS NULL
    )
    AND (FALSE::BOOLEAN OR NOT EXISTS (
      SELECT 1 FROM apartment_admin_delegations d WHERE d.apartment_id = a.id AND d.ended_at IS NULL AND d.source = 'manager'
    ))) c)
ORDER BY a.id
FOR UPDATE OF a;

INSERT INTO audit_log (actor_user_code, actor_name, actor_role, action, site_code, target_type, target_id, details)
SELECT c.actor_user_code, c.actor_name, c.audit_role, 'apartment.admin_tenant_enforced', c.site_code, 'apartment', c.apartment_id::TEXT,
       jsonb_strip_nulls(jsonb_build_object('via', c.via, 'tenant_person_id', c.tenant_person_id, 'from_user_code', c.prev_admin_user_code, 'to_user_code', c.tenant_user_code))
FROM (SELECT a.id AS apartment_id, a.site_code, LEFT(NULLIF(btrim(CASE WHEN COALESCE(b.block_name, '') <> '' AND COALESCE(a.unit_label, '') <> '' THEN b.block_name || ' - ' || a.unit_label ELSE COALESCE(NULLIF(b.block_name, ''), a.unit_label, '') END), ''), 80) AS label,
    r.person_id AS tenant_person_id, r.move_in_date AS tenant_move_in, sp.user_code AS tenant_user_code, u.full_name AS tenant_name,
    (SELECT o.user_code FROM apartment_memberships o WHERE o.apartment_id = a.id AND o.role = 'APARTMENT_ADMIN' AND o.is_active = TRUE AND o.user_code <> sp.user_code ORDER BY o.created_at, o.id LIMIT 1) AS prev_admin_user_code,
    (SELECT orr.person_id FROM apartment_residencies orr WHERE orr.apartment_id = a.id AND orr.is_current = TRUE AND orr.relation = 'owner' LIMIT 1) AS owner_person_id,
    'backfill'::TEXT AS via, NULL::INTEGER AS actor_user_code, 'Sistem'::TEXT AS actor_name, 'system'::TEXT AS audit_role, 'system'::TEXT AS log_role
  FROM apartments a
  LEFT JOIN site_blocks b ON b.id = a.block_id
  INNER JOIN apartment_residencies r ON r.apartment_id = a.id AND r.is_current = TRUE AND r.relation = 'tenant'
  INNER JOIN site_people sp ON sp.id = r.person_id AND sp.is_active = TRUE AND sp.user_code IS NOT NULL
  INNER JOIN users u ON u.user_code = sp.user_code AND u.deleted_at IS NULL AND u.is_active = TRUE
  INNER JOIN apartment_memberships tm ON tm.apartment_id = a.id AND tm.user_code = sp.user_code AND tm.is_active = TRUE
  WHERE a.is_active = TRUE
    AND (NULL::BIGINT[] IS NULL OR a.id = ANY(NULL::BIGINT[]))
    AND (NULL::INTEGER IS NULL OR sp.user_code = NULL::INTEGER)
    AND (tm.role <> 'APARTMENT_ADMIN' OR EXISTS (
      SELECT 1 FROM apartment_memberships x WHERE x.apartment_id = a.id AND x.role = 'APARTMENT_ADMIN' AND x.is_active = TRUE AND x.user_code <> sp.user_code
    ))
    AND NOT EXISTS (
      SELECT 1 FROM apartment_access_suspensions s WHERE s.apartment_id = a.id AND s.user_code = sp.user_code AND s.lifted_at IS NULL
    )
    AND (FALSE::BOOLEAN OR NOT EXISTS (
      SELECT 1 FROM apartment_admin_delegations d WHERE d.apartment_id = a.id AND d.ended_at IS NULL AND d.source = 'manager'
    ))) c;

INSERT INTO apartment_residency_log (
  site_code, apartment_id, apartment_label, event_type, reason_code, subject_name, subject_relation, subject_person_id,
  subject_user_code, period_start, period_end, actor_user_code, actor_name, actor_role, related
)
SELECT c.site_code, c.apartment_id, c.label, 'admin_changed', 'handover', LEFT(NULLIF(btrim(COALESCE(c.tenant_name, '')), ''), 120), 'tenant', c.tenant_person_id,
       c.tenant_user_code, c.tenant_move_in, NULL, c.actor_user_code, LEFT(NULLIF(btrim(COALESCE(c.actor_name, '')), ''), 120), c.log_role,
       jsonb_strip_nulls(jsonb_build_object('from_user_code', c.prev_admin_user_code, 'to_user_code', c.tenant_user_code))
FROM (SELECT a.id AS apartment_id, a.site_code, LEFT(NULLIF(btrim(CASE WHEN COALESCE(b.block_name, '') <> '' AND COALESCE(a.unit_label, '') <> '' THEN b.block_name || ' - ' || a.unit_label ELSE COALESCE(NULLIF(b.block_name, ''), a.unit_label, '') END), ''), 80) AS label,
    r.person_id AS tenant_person_id, r.move_in_date AS tenant_move_in, sp.user_code AS tenant_user_code, u.full_name AS tenant_name,
    (SELECT o.user_code FROM apartment_memberships o WHERE o.apartment_id = a.id AND o.role = 'APARTMENT_ADMIN' AND o.is_active = TRUE AND o.user_code <> sp.user_code ORDER BY o.created_at, o.id LIMIT 1) AS prev_admin_user_code,
    (SELECT orr.person_id FROM apartment_residencies orr WHERE orr.apartment_id = a.id AND orr.is_current = TRUE AND orr.relation = 'owner' LIMIT 1) AS owner_person_id,
    'backfill'::TEXT AS via, NULL::INTEGER AS actor_user_code, 'Sistem'::TEXT AS actor_name, 'system'::TEXT AS audit_role, 'system'::TEXT AS log_role
  FROM apartments a
  LEFT JOIN site_blocks b ON b.id = a.block_id
  INNER JOIN apartment_residencies r ON r.apartment_id = a.id AND r.is_current = TRUE AND r.relation = 'tenant'
  INNER JOIN site_people sp ON sp.id = r.person_id AND sp.is_active = TRUE AND sp.user_code IS NOT NULL
  INNER JOIN users u ON u.user_code = sp.user_code AND u.deleted_at IS NULL AND u.is_active = TRUE
  INNER JOIN apartment_memberships tm ON tm.apartment_id = a.id AND tm.user_code = sp.user_code AND tm.is_active = TRUE
  WHERE a.is_active = TRUE
    AND (NULL::BIGINT[] IS NULL OR a.id = ANY(NULL::BIGINT[]))
    AND (NULL::INTEGER IS NULL OR sp.user_code = NULL::INTEGER)
    AND (tm.role <> 'APARTMENT_ADMIN' OR EXISTS (
      SELECT 1 FROM apartment_memberships x WHERE x.apartment_id = a.id AND x.role = 'APARTMENT_ADMIN' AND x.is_active = TRUE AND x.user_code <> sp.user_code
    ))
    AND NOT EXISTS (
      SELECT 1 FROM apartment_access_suspensions s WHERE s.apartment_id = a.id AND s.user_code = sp.user_code AND s.lifted_at IS NULL
    )
    AND (FALSE::BOOLEAN OR NOT EXISTS (
      SELECT 1 FROM apartment_admin_delegations d WHERE d.apartment_id = a.id AND d.ended_at IS NULL AND d.source = 'manager'
    ))) c;

UPDATE apartment_admin_delegations d
SET state = 'ended', ended_at = NOW(), end_reason = 'replaced'
FROM (SELECT a.id AS apartment_id, a.site_code, LEFT(NULLIF(btrim(CASE WHEN COALESCE(b.block_name, '') <> '' AND COALESCE(a.unit_label, '') <> '' THEN b.block_name || ' - ' || a.unit_label ELSE COALESCE(NULLIF(b.block_name, ''), a.unit_label, '') END), ''), 80) AS label,
    r.person_id AS tenant_person_id, r.move_in_date AS tenant_move_in, sp.user_code AS tenant_user_code, u.full_name AS tenant_name,
    (SELECT o.user_code FROM apartment_memberships o WHERE o.apartment_id = a.id AND o.role = 'APARTMENT_ADMIN' AND o.is_active = TRUE AND o.user_code <> sp.user_code ORDER BY o.created_at, o.id LIMIT 1) AS prev_admin_user_code,
    (SELECT orr.person_id FROM apartment_residencies orr WHERE orr.apartment_id = a.id AND orr.is_current = TRUE AND orr.relation = 'owner' LIMIT 1) AS owner_person_id,
    'backfill'::TEXT AS via, NULL::INTEGER AS actor_user_code, 'Sistem'::TEXT AS actor_name, 'system'::TEXT AS audit_role, 'system'::TEXT AS log_role
  FROM apartments a
  LEFT JOIN site_blocks b ON b.id = a.block_id
  INNER JOIN apartment_residencies r ON r.apartment_id = a.id AND r.is_current = TRUE AND r.relation = 'tenant'
  INNER JOIN site_people sp ON sp.id = r.person_id AND sp.is_active = TRUE AND sp.user_code IS NOT NULL
  INNER JOIN users u ON u.user_code = sp.user_code AND u.deleted_at IS NULL AND u.is_active = TRUE
  INNER JOIN apartment_memberships tm ON tm.apartment_id = a.id AND tm.user_code = sp.user_code AND tm.is_active = TRUE
  WHERE a.is_active = TRUE
    AND (NULL::BIGINT[] IS NULL OR a.id = ANY(NULL::BIGINT[]))
    AND (NULL::INTEGER IS NULL OR sp.user_code = NULL::INTEGER)
    AND (tm.role <> 'APARTMENT_ADMIN' OR EXISTS (
      SELECT 1 FROM apartment_memberships x WHERE x.apartment_id = a.id AND x.role = 'APARTMENT_ADMIN' AND x.is_active = TRUE AND x.user_code <> sp.user_code
    ))
    AND NOT EXISTS (
      SELECT 1 FROM apartment_access_suspensions s WHERE s.apartment_id = a.id AND s.user_code = sp.user_code AND s.lifted_at IS NULL
    )
    AND (FALSE::BOOLEAN OR NOT EXISTS (
      SELECT 1 FROM apartment_admin_delegations d WHERE d.apartment_id = a.id AND d.ended_at IS NULL AND d.source = 'manager'
    ))) c
WHERE d.apartment_id = c.apartment_id AND d.ended_at IS NULL;

INSERT INTO apartment_admin_delegations (site_code, apartment_id, owner_person_id, admin_person_id, admin_user_code, source, state, created_by)
SELECT c.site_code, c.apartment_id, c.owner_person_id, c.tenant_person_id, c.tenant_user_code, 'tenant_delegated', 'active', c.actor_user_code
FROM (SELECT a.id AS apartment_id, a.site_code, LEFT(NULLIF(btrim(CASE WHEN COALESCE(b.block_name, '') <> '' AND COALESCE(a.unit_label, '') <> '' THEN b.block_name || ' - ' || a.unit_label ELSE COALESCE(NULLIF(b.block_name, ''), a.unit_label, '') END), ''), 80) AS label,
    r.person_id AS tenant_person_id, r.move_in_date AS tenant_move_in, sp.user_code AS tenant_user_code, u.full_name AS tenant_name,
    (SELECT o.user_code FROM apartment_memberships o WHERE o.apartment_id = a.id AND o.role = 'APARTMENT_ADMIN' AND o.is_active = TRUE AND o.user_code <> sp.user_code ORDER BY o.created_at, o.id LIMIT 1) AS prev_admin_user_code,
    (SELECT orr.person_id FROM apartment_residencies orr WHERE orr.apartment_id = a.id AND orr.is_current = TRUE AND orr.relation = 'owner' LIMIT 1) AS owner_person_id,
    'backfill'::TEXT AS via, NULL::INTEGER AS actor_user_code, 'Sistem'::TEXT AS actor_name, 'system'::TEXT AS audit_role, 'system'::TEXT AS log_role
  FROM apartments a
  LEFT JOIN site_blocks b ON b.id = a.block_id
  INNER JOIN apartment_residencies r ON r.apartment_id = a.id AND r.is_current = TRUE AND r.relation = 'tenant'
  INNER JOIN site_people sp ON sp.id = r.person_id AND sp.is_active = TRUE AND sp.user_code IS NOT NULL
  INNER JOIN users u ON u.user_code = sp.user_code AND u.deleted_at IS NULL AND u.is_active = TRUE
  INNER JOIN apartment_memberships tm ON tm.apartment_id = a.id AND tm.user_code = sp.user_code AND tm.is_active = TRUE
  WHERE a.is_active = TRUE
    AND (NULL::BIGINT[] IS NULL OR a.id = ANY(NULL::BIGINT[]))
    AND (NULL::INTEGER IS NULL OR sp.user_code = NULL::INTEGER)
    AND (tm.role <> 'APARTMENT_ADMIN' OR EXISTS (
      SELECT 1 FROM apartment_memberships x WHERE x.apartment_id = a.id AND x.role = 'APARTMENT_ADMIN' AND x.is_active = TRUE AND x.user_code <> sp.user_code
    ))
    AND NOT EXISTS (
      SELECT 1 FROM apartment_access_suspensions s WHERE s.apartment_id = a.id AND s.user_code = sp.user_code AND s.lifted_at IS NULL
    )
    AND (FALSE::BOOLEAN OR NOT EXISTS (
      SELECT 1 FROM apartment_admin_delegations d WHERE d.apartment_id = a.id AND d.ended_at IS NULL AND d.source = 'manager'
    ))) c;

INSERT INTO apartment_notices (site_code, apartment_id, user_code, kind, message)
SELECT c.site_code, c.apartment_id, t.user_code, 'admin_tenant_enforced', t.message
FROM (SELECT a.id AS apartment_id, a.site_code, LEFT(NULLIF(btrim(CASE WHEN COALESCE(b.block_name, '') <> '' AND COALESCE(a.unit_label, '') <> '' THEN b.block_name || ' - ' || a.unit_label ELSE COALESCE(NULLIF(b.block_name, ''), a.unit_label, '') END), ''), 80) AS label,
    r.person_id AS tenant_person_id, r.move_in_date AS tenant_move_in, sp.user_code AS tenant_user_code, u.full_name AS tenant_name,
    (SELECT o.user_code FROM apartment_memberships o WHERE o.apartment_id = a.id AND o.role = 'APARTMENT_ADMIN' AND o.is_active = TRUE AND o.user_code <> sp.user_code ORDER BY o.created_at, o.id LIMIT 1) AS prev_admin_user_code,
    (SELECT orr.person_id FROM apartment_residencies orr WHERE orr.apartment_id = a.id AND orr.is_current = TRUE AND orr.relation = 'owner' LIMIT 1) AS owner_person_id,
    'backfill'::TEXT AS via, NULL::INTEGER AS actor_user_code, 'Sistem'::TEXT AS actor_name, 'system'::TEXT AS audit_role, 'system'::TEXT AS log_role
  FROM apartments a
  LEFT JOIN site_blocks b ON b.id = a.block_id
  INNER JOIN apartment_residencies r ON r.apartment_id = a.id AND r.is_current = TRUE AND r.relation = 'tenant'
  INNER JOIN site_people sp ON sp.id = r.person_id AND sp.is_active = TRUE AND sp.user_code IS NOT NULL
  INNER JOIN users u ON u.user_code = sp.user_code AND u.deleted_at IS NULL AND u.is_active = TRUE
  INNER JOIN apartment_memberships tm ON tm.apartment_id = a.id AND tm.user_code = sp.user_code AND tm.is_active = TRUE
  WHERE a.is_active = TRUE
    AND (NULL::BIGINT[] IS NULL OR a.id = ANY(NULL::BIGINT[]))
    AND (NULL::INTEGER IS NULL OR sp.user_code = NULL::INTEGER)
    AND (tm.role <> 'APARTMENT_ADMIN' OR EXISTS (
      SELECT 1 FROM apartment_memberships x WHERE x.apartment_id = a.id AND x.role = 'APARTMENT_ADMIN' AND x.is_active = TRUE AND x.user_code <> sp.user_code
    ))
    AND NOT EXISTS (
      SELECT 1 FROM apartment_access_suspensions s WHERE s.apartment_id = a.id AND s.user_code = sp.user_code AND s.lifted_at IS NULL
    )
    AND (FALSE::BOOLEAN OR NOT EXISTS (
      SELECT 1 FROM apartment_admin_delegations d WHERE d.apartment_id = a.id AND d.ended_at IS NULL AND d.source = 'manager'
    ))) c
CROSS JOIN LATERAL (VALUES
  (c.tenant_user_code, COALESCE(c.label, 'Daire') || ' dairesinde kiracı olduğunuz için daire yöneticisi artık sizsiniz.'),
  (c.prev_admin_user_code, COALESCE(c.label, 'Daire') || ' dairesinin yönetimi kiracıya geçti (kiracı daire yöneticisidir). Dairede kalmaya devam ediyorsunuz.')
) AS t(user_code, message)
WHERE t.user_code IS NOT NULL AND t.user_code IS DISTINCT FROM c.actor_user_code;

UPDATE apartments a
SET resident_email = CASE WHEN a.resident_user_code IS DISTINCT FROM c.tenant_user_code THEN NULL ELSE a.resident_email END,
    resident_pin_issued = CASE WHEN a.resident_user_code IS DISTINCT FROM c.tenant_user_code THEN FALSE ELSE a.resident_pin_issued END,
    resident_pin_code = NULL,
    resident_user_code = c.tenant_user_code
FROM (SELECT a.id AS apartment_id, a.site_code, LEFT(NULLIF(btrim(CASE WHEN COALESCE(b.block_name, '') <> '' AND COALESCE(a.unit_label, '') <> '' THEN b.block_name || ' - ' || a.unit_label ELSE COALESCE(NULLIF(b.block_name, ''), a.unit_label, '') END), ''), 80) AS label,
    r.person_id AS tenant_person_id, r.move_in_date AS tenant_move_in, sp.user_code AS tenant_user_code, u.full_name AS tenant_name,
    (SELECT o.user_code FROM apartment_memberships o WHERE o.apartment_id = a.id AND o.role = 'APARTMENT_ADMIN' AND o.is_active = TRUE AND o.user_code <> sp.user_code ORDER BY o.created_at, o.id LIMIT 1) AS prev_admin_user_code,
    (SELECT orr.person_id FROM apartment_residencies orr WHERE orr.apartment_id = a.id AND orr.is_current = TRUE AND orr.relation = 'owner' LIMIT 1) AS owner_person_id,
    'backfill'::TEXT AS via, NULL::INTEGER AS actor_user_code, 'Sistem'::TEXT AS actor_name, 'system'::TEXT AS audit_role, 'system'::TEXT AS log_role
  FROM apartments a
  LEFT JOIN site_blocks b ON b.id = a.block_id
  INNER JOIN apartment_residencies r ON r.apartment_id = a.id AND r.is_current = TRUE AND r.relation = 'tenant'
  INNER JOIN site_people sp ON sp.id = r.person_id AND sp.is_active = TRUE AND sp.user_code IS NOT NULL
  INNER JOIN users u ON u.user_code = sp.user_code AND u.deleted_at IS NULL AND u.is_active = TRUE
  INNER JOIN apartment_memberships tm ON tm.apartment_id = a.id AND tm.user_code = sp.user_code AND tm.is_active = TRUE
  WHERE a.is_active = TRUE
    AND (NULL::BIGINT[] IS NULL OR a.id = ANY(NULL::BIGINT[]))
    AND (NULL::INTEGER IS NULL OR sp.user_code = NULL::INTEGER)
    AND (tm.role <> 'APARTMENT_ADMIN' OR EXISTS (
      SELECT 1 FROM apartment_memberships x WHERE x.apartment_id = a.id AND x.role = 'APARTMENT_ADMIN' AND x.is_active = TRUE AND x.user_code <> sp.user_code
    ))
    AND NOT EXISTS (
      SELECT 1 FROM apartment_access_suspensions s WHERE s.apartment_id = a.id AND s.user_code = sp.user_code AND s.lifted_at IS NULL
    )
    AND (FALSE::BOOLEAN OR NOT EXISTS (
      SELECT 1 FROM apartment_admin_delegations d WHERE d.apartment_id = a.id AND d.ended_at IS NULL AND d.source = 'manager'
    ))) c
WHERE a.id = c.apartment_id;

UPDATE apartment_memberships m
SET role = CASE WHEN m.user_code = c.tenant_user_code THEN 'APARTMENT_ADMIN' ELSE 'FAMILY_MEMBER' END,
    updated_at = NOW()
FROM (SELECT a.id AS apartment_id, a.site_code, LEFT(NULLIF(btrim(CASE WHEN COALESCE(b.block_name, '') <> '' AND COALESCE(a.unit_label, '') <> '' THEN b.block_name || ' - ' || a.unit_label ELSE COALESCE(NULLIF(b.block_name, ''), a.unit_label, '') END), ''), 80) AS label,
    r.person_id AS tenant_person_id, r.move_in_date AS tenant_move_in, sp.user_code AS tenant_user_code, u.full_name AS tenant_name,
    (SELECT o.user_code FROM apartment_memberships o WHERE o.apartment_id = a.id AND o.role = 'APARTMENT_ADMIN' AND o.is_active = TRUE AND o.user_code <> sp.user_code ORDER BY o.created_at, o.id LIMIT 1) AS prev_admin_user_code,
    (SELECT orr.person_id FROM apartment_residencies orr WHERE orr.apartment_id = a.id AND orr.is_current = TRUE AND orr.relation = 'owner' LIMIT 1) AS owner_person_id,
    'backfill'::TEXT AS via, NULL::INTEGER AS actor_user_code, 'Sistem'::TEXT AS actor_name, 'system'::TEXT AS audit_role, 'system'::TEXT AS log_role
  FROM apartments a
  LEFT JOIN site_blocks b ON b.id = a.block_id
  INNER JOIN apartment_residencies r ON r.apartment_id = a.id AND r.is_current = TRUE AND r.relation = 'tenant'
  INNER JOIN site_people sp ON sp.id = r.person_id AND sp.is_active = TRUE AND sp.user_code IS NOT NULL
  INNER JOIN users u ON u.user_code = sp.user_code AND u.deleted_at IS NULL AND u.is_active = TRUE
  INNER JOIN apartment_memberships tm ON tm.apartment_id = a.id AND tm.user_code = sp.user_code AND tm.is_active = TRUE
  WHERE a.is_active = TRUE
    AND (NULL::BIGINT[] IS NULL OR a.id = ANY(NULL::BIGINT[]))
    AND (NULL::INTEGER IS NULL OR sp.user_code = NULL::INTEGER)
    AND (tm.role <> 'APARTMENT_ADMIN' OR EXISTS (
      SELECT 1 FROM apartment_memberships x WHERE x.apartment_id = a.id AND x.role = 'APARTMENT_ADMIN' AND x.is_active = TRUE AND x.user_code <> sp.user_code
    ))
    AND NOT EXISTS (
      SELECT 1 FROM apartment_access_suspensions s WHERE s.apartment_id = a.id AND s.user_code = sp.user_code AND s.lifted_at IS NULL
    )
    AND (FALSE::BOOLEAN OR NOT EXISTS (
      SELECT 1 FROM apartment_admin_delegations d WHERE d.apartment_id = a.id AND d.ended_at IS NULL AND d.source = 'manager'
    ))) c
WHERE m.apartment_id = c.apartment_id
  AND ((m.role = 'APARTMENT_ADMIN' AND m.user_code <> c.tenant_user_code)
       OR (m.user_code = c.tenant_user_code AND m.is_active = TRUE AND m.role <> 'APARTMENT_ADMIN'));
