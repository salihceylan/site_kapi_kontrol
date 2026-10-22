// Daire sakini ADLI KAYDI: YAZMA tarafı (hook yardımcıları). Sözleşme: docs/PLATFORM_ADLI_KAYIT.md.
//
// Amaç: sakin ayrılığı / değişikliği olaylarını DEĞİŞTİRİLEMEZ bir kayda yazmak (apartment_residency_log, 075); YALNIZ adli bilgi amaçlıdır.
//  - Merkezi işlevlere (people_service closeResidency / insertResidency / updateResidency, apartment_mgmt_*, membership_service, eşitleme, hesap silme)
//    yalnız YAZMA kancası eklenir: AYNI transaction'da TEK bir INSERT ... SELECT. Kapı açma / MQTT / BLE / firmware mantığına DOKUNULMAZ.
//  - Kişi anlık görüntüsü: ad soyad, ilişki (malik/kiracı/aile/sakin), kişi ve kullanıcı kodu, dönem. İLETİŞİM BİLGİSİ (telefon, e-posta, TCKN) ve serbest not
//    YAZILMAZ. Kullanıcı/daire sütunları FK'sızdır: hesap silinse de kayıt kalır.
//  - Hata YUTULMAZ: log satırı değişikliğin kendisiyle aynı transaction'dadır; yazılamazsa değişiklik de geri alınır (kayıtsız taşınma olmaz).
// Bu dosya db.js, people_service ve membership_service'i İÇE AKTARMAZ (ikisi de bunu kullanır; döngü olmasın). Yalnız verilen `client` üzerinde çalışır.

import { RESIDENCY_ACTOR_ROLES, RESIDENCY_EVENT_TYPES, RESIDENCY_RELATIONS } from './residency_log_schema.js';

export { RESIDENCY_ACTOR_ROLES, RESIDENCY_EVENT_TYPES, RESIDENCY_RELATIONS };

/** Neden kodları (kod alanıdır; serbest metin DEĞİL). DB yalnız biçimi doğrular, bu liste belge ve istemci etiketleri içindir. */
export const RESIDENCY_REASON_CODES = Object.freeze([
  'moved_out',
  'handover',
  'mutual',
  'site_manager',
  'apartment_admin',
  'self',
  'consent',
  'suspension',
  'account_deleted',
  'bulk_import',
  'sync',
  'manual_add',
  'invite_accepted',
  'role_change',
  'admin_change',
  'owner_record',
  'owner_default',
]);

const REASON_RE = /^[a-z][a-z0-9_]{1,39}$/;
const RELATED_KEYS = Object.freeze([
  'residency_id',
  'person_id',
  'request_id',
  'delegation_id',
  'suspension_reason',
  'from_user_code',
  'to_user_code',
  'from_relation',
  'to_relation',
  'cause_residency_id',
  'auto',
]);
const CODE_VALUE_RE = /^[a-z0-9_]{1,40}$/;

/** Kapatma akışındaki `reason` (denetim nedeni) -> [olay türü, neden kodu]. Verilmeyen / bilinmeyen: site yöneticisinin "Taşındı" işlemi. */
const CLOSE_LOG_MAP = Object.freeze({
  person_deactivated: ['moved_out', 'site_manager'],
  family_removed_by_admin: ['member_removed', 'apartment_admin'],
  member_removal_consented: ['member_removed', 'consent'],
  tenant_exit: ['moved_out', 'handover'],
  tenant_left: ['member_left', 'self'],
  member_left: ['member_left', 'self'],
  disconnect_approved: ['link_cut_mutual', 'mutual'],
});

/** closeResidency(reason) -> { eventType, reasonCode } */
export function closeLogFor(reason) {
  const hit = reason ? CLOSE_LOG_MAP[reason] : undefined;
  return hit ? { eventType: hit[0], reasonCode: hit[1] } : { eventType: 'moved_out', reasonCode: 'moved_out' };
}

function positiveIntOrNull(value) {
  const parsed = Number(value);
  return Number.isSafeInteger(parsed) && parsed > 0 ? parsed : null;
}

/** authUser -> kayıt "kim" alanları. actor yoksa SİSTEM. `role` verilirse (bağlamdan bilinen rol) onu kullanır. */
export function actorForLog(actor, role = null) {
  if (!actor) {
    return { userCode: null, name: null, role: 'system' };
  }
  const userCode = positiveIntOrNull(actor.user_code ?? actor.userCode ?? actor.id);
  const rawName = actor.full_name ?? actor.fullName ?? actor.name;
  const name = typeof rawName === 'string' && rawName.trim() !== '' ? rawName.replace(/\s+/g, ' ').trim().slice(0, 120) : null;
  let resolved = role;
  if (!resolved || !RESIDENCY_ACTOR_ROLES.includes(resolved)) {
    if (actor.role === 'super_user') resolved = 'super_user';
    else if (actor.role === 'site_manager') resolved = 'site_manager';
    else if (actor.role === 'system') resolved = 'system';
    else resolved = 'resident';
  }
  // Süper kullanıcı hangi bağlamda olursa olsun süper kullanıcı olarak kaydedilir.
  if (actor.role === 'super_user') resolved = 'super_user';
  return { userCode, name: resolved === 'system' ? null : name, role: resolved };
}

/** `related` nesnesini beyaz listeyle süzer: yalnız sayısal kimlikler, boolean ve kısa kodlar (serbest metin sızmaz). */
export function sanitizeRelated(related) {
  const out = {};
  if (!related || typeof related !== 'object') {
    return out;
  }
  for (const key of RELATED_KEYS) {
    const value = related[key];
    if (value === undefined || value === null) continue;
    if (typeof value === 'number' && Number.isSafeInteger(value)) out[key] = value;
    else if (typeof value === 'boolean') out[key] = value;
    else if (typeof value === 'string' && CODE_VALUE_RE.test(value)) out[key] = value;
  }
  return out;
}

const dateOrNull = (value) => {
  if (value === null || value === undefined || value === '') return null;
  if (value instanceof Date) return Number.isNaN(value.getTime()) ? null : value.toISOString().slice(0, 10);
  return /^\d{4}-\d{2}-\d{2}/.test(String(value)) ? String(value).slice(0, 10) : null;
};

const INSERT_SQL = `
  INSERT INTO apartment_residency_log (
    site_code, apartment_id, apartment_label, event_type, reason_code, subject_name, subject_relation, subject_person_id,
    subject_user_code, period_start, period_end, actor_user_code, actor_name, actor_role, related
  )
  SELECT
    COALESCE($1::BIGINT, a.site_code),
    a.id,
    LEFT(NULLIF(btrim(CASE WHEN COALESCE(b.block_name, '') <> '' AND COALESCE(a.unit_label, '') <> '' THEN b.block_name || ' - ' || a.unit_label ELSE COALESCE(NULLIF(b.block_name, ''), a.unit_label, '') END), ''), 80),
    $3::TEXT,
    $4::TEXT,
    LEFT(NULLIF(btrim(COALESCE($11::TEXT, NULLIF(su.full_name, ''), sp.full_name, '')), ''), 120),
    CASE WHEN COALESCE($8::TEXT, r.relation) IN ('owner', 'tenant', 'family_member', 'resident') THEN COALESCE($8::TEXT, r.relation) END,
    COALESCE($6::BIGINT, r.person_id),
    COALESCE($7::INTEGER, sp.user_code),
    per.ps,
    CASE WHEN per.pe IS NULL OR per.ps IS NULL OR per.pe >= per.ps THEN per.pe ELSE per.ps END,
    $12::INTEGER,
    LEFT(NULLIF(btrim(COALESCE($13::TEXT, au.full_name, '')), ''), 120),
    $14::TEXT,
    $15::JSONB
  FROM (SELECT 1) one
  LEFT JOIN LATERAL (
    SELECT r0.id, r0.person_id, r0.apartment_id, r0.relation, r0.move_in_date, r0.move_out_date
    FROM apartment_residencies r0
    INNER JOIN site_people sp0 ON sp0.id = r0.person_id
    WHERE r0.id = $5::BIGINT
       OR ($5::BIGINT IS NULL AND $6::BIGINT IS NULL AND r0.apartment_id = $2::BIGINT AND sp0.user_code = $7::INTEGER AND r0.is_current)
       OR ($5::BIGINT IS NULL AND r0.person_id = $6::BIGINT AND r0.apartment_id = $2::BIGINT AND r0.is_current)
    ORDER BY r0.is_current DESC, r0.id DESC
    LIMIT 1
  ) r ON TRUE
  LEFT JOIN site_people sp ON sp.id = COALESCE($6::BIGINT, r.person_id)
  LEFT JOIN users su ON su.user_code = COALESCE($7::INTEGER, sp.user_code)
  LEFT JOIN apartments a ON a.id = COALESCE($2::BIGINT, r.apartment_id)
  LEFT JOIN site_blocks b ON b.id = a.block_id
  LEFT JOIN users au ON au.user_code = $12::INTEGER
  CROSS JOIN LATERAL (SELECT COALESCE($9::DATE, r.move_in_date) AS ps, COALESCE($10::DATE, r.move_out_date) AS pe) per
`;

/**
 * Tek olay satırı yazar (AYNI transaction'da; hata fırlatır).
 * @param {{ query: Function }} client
 * @param {object} event
 * @param {number|string|null} [event.siteCode] yoksa dairenin sitesi kullanılır (apartmentId zorunlu)
 * @param {string} event.eventType RESIDENCY_EVENT_TYPES'tan biri
 * @param {string} event.reasonCode kod ([a-z][a-z0-9_]{1,39})
 * @param {number|null} [event.apartmentId] daire (yoksa residencyId'den çözülür)
 * @param {number|null} [event.residencyId] ilişki kaydı (kişi, ilişki ve dönem buradan okunur)
 * @param {number|null} [event.personId] kişi kaydı
 * @param {number|null} [event.userCode] kullanıcı kodu (yoksa kişiden)
 * @param {string|null} [event.relation] malik|kiracı|aile|sakin (yoksa ilişki kaydından)
 * @param {string|null} [event.periodStart] YYYY-MM-DD (yoksa ilişki kaydından)
 * @param {string|null} [event.periodEnd] YYYY-MM-DD (yoksa ilişki kaydından)
 * @param {string|null} [event.subjectName] ad anlık görüntüsü (yoksa kullanıcıdan / kişiden)
 * @param {object|null} [event.actor] işlemi yapan (authUser); yoksa SİSTEM
 * @param {string|null} [event.actorRole] bağlamdan bilinen rol
 * @param {object|null} [event.related] olay bağı (beyaz liste)
 */
export async function logResidencyEvent(client, event) {
  const siteCode = positiveIntOrNull(event?.siteCode);
  if (siteCode === null && positiveIntOrNull(event?.apartmentId) === null) {
    throw new Error('adli kayit: siteCode ya da apartmentId zorunlu');
  }
  if (!RESIDENCY_EVENT_TYPES.includes(event.eventType)) {
    throw new Error(`adli kayit: gecersiz olay turu ${String(event.eventType)}`);
  }
  if (typeof event.reasonCode !== 'string' || !REASON_RE.test(event.reasonCode)) {
    throw new Error('adli kayit: gecersiz neden kodu');
  }
  const actor = actorForLog(event.actor ?? null, event.actorRole ?? null);
  const relation = RESIDENCY_RELATIONS.includes(event.relation) ? event.relation : null;
  await client.query(INSERT_SQL, [
    siteCode,
    positiveIntOrNull(event.apartmentId),
    event.eventType,
    event.reasonCode,
    positiveIntOrNull(event.residencyId),
    positiveIntOrNull(event.personId),
    positiveIntOrNull(event.userCode),
    relation,
    dateOrNull(event.periodStart),
    dateOrNull(event.periodEnd),
    typeof event.subjectName === 'string' && event.subjectName.trim() !== '' ? event.subjectName.replace(/\s+/g, ' ').trim().slice(0, 120) : null,
    actor.userCode,
    actor.name,
    actor.role,
    JSON.stringify(sanitizeRelated(event.related)),
  ]);
}

const BULK_INSERT_SQL = `
  INSERT INTO apartment_residency_log (
    site_code, apartment_id, apartment_label, event_type, reason_code, subject_name, subject_relation, subject_person_id,
    subject_user_code, period_start, period_end, actor_user_code, actor_name, actor_role, related
  )
  SELECT
    r.site_code,
    r.apartment_id,
    LEFT(NULLIF(btrim(CASE WHEN COALESCE(b.block_name, '') <> '' AND COALESCE(a.unit_label, '') <> '' THEN b.block_name || ' - ' || a.unit_label ELSE COALESCE(NULLIF(b.block_name, ''), a.unit_label, '') END), ''), 80),
    $2::TEXT,
    $3::TEXT,
    LEFT(NULLIF(btrim(COALESCE(NULLIF(u.full_name, ''), sp.full_name, '')), ''), 120),
    r.relation,
    r.person_id,
    sp.user_code,
    r.move_in_date,
    CASE WHEN r.move_out_date IS NULL OR r.move_in_date IS NULL OR r.move_out_date >= r.move_in_date THEN r.move_out_date ELSE r.move_in_date END,
    $4::INTEGER,
    LEFT(NULLIF(btrim(COALESCE(au.full_name, '')), ''), 120),
    $5::TEXT,
    CASE WHEN $2::TEXT = 'role_changed'
      THEN jsonb_build_object('residency_id', r.id, 'from_relation', 'resident', 'to_relation', r.relation)
      ELSE jsonb_build_object('residency_id', r.id) END
  FROM apartment_residencies r
  INNER JOIN site_people sp ON sp.id = r.person_id
  LEFT JOIN users u ON u.user_code = sp.user_code
  LEFT JOIN apartments a ON a.id = r.apartment_id
  LEFT JOIN site_blocks b ON b.id = a.block_id
  LEFT JOIN users au ON au.user_code = $4::INTEGER
  WHERE r.id = ANY($1::BIGINT[])
`;

/**
 * Toplu yükleme: eklenen / yükseltilen ilişkiler için kümesel satır (tek ifade, N+1 yok). Kişi, ilişki ve dönem ilişki kaydından okunur.
 * `role_changed` yalnız "sakin -> malik/kiracı/aile" yükseltmesi içindir (eski ilişki 'resident').
 */
export async function logResidenciesBulk(client, { ids, eventType, reasonCode = 'bulk_import', actorUserCode = null, actorRole = 'site_manager' }) {
  const list = (ids ?? []).map(positiveIntOrNull).filter((id) => id !== null);
  if (list.length === 0) {
    return;
  }
  if (!RESIDENCY_EVENT_TYPES.includes(eventType) || !REASON_RE.test(reasonCode) || !RESIDENCY_ACTOR_ROLES.includes(actorRole)) {
    throw new Error('adli kayit: gecersiz toplu olay');
  }
  await client.query(BULK_INSERT_SQL, [list, eventType, reasonCode, positiveIntOrNull(actorUserCode), actorRole]);
}

/** SQL parçası testleri için: yazma ifadeleri (iletişim sütunu içermemelidir). */
export const RESIDENCY_LOG_BULK_INSERT_SQL = BULK_INSERT_SQL;
export const RESIDENCY_LOG_INSERT_SQL = INSERT_SQL;
