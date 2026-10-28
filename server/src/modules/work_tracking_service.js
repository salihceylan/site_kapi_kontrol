// İş Takibi: yönetim tarafı (yönetici / süper / görevli yazar; kurul salt okur) + iki tarafın ortak işlem altyapısı.
//
// Sözleşme: docs/PLATFORM_IS_TAKIBI.md.
//  - KİLİT SIRASI (documents ile aynı): sites FOR KEY SHARE -> users (FOR KEY SHARE, `deleted_at IS NULL`: silinmiş hesaba yazma yok) ->
//    work_items_site:<site> advisory (yalnız talep AÇARKEN: sınır sayımı) -> work_items (FOR UPDATE) -> equipment_items (FOR KEY SHARE; yalnız ekipman bağı yazılırken, 096)
//    -> work_item_events. Nadir 40P01'de işlem TEK SEFER baştan denenir.
//  - Her sorguda site_code vardır (IDOR yok). STAFF yalnız kendine atanmış VEYA atanmamış talepleri görür (aksi 404 WORK_ITEM_NOT_FOUND, varlık sızmaz).
//  - Kurul: salt okur, iç (internal) olayları ve sakin telefonunu / kullanıcı kodunu GÖRMEZ.
//  - Audit `details` yalnız kimlik / durum / sayı taşır: başlık, açıklama, yorum ASLA yazılmaz.

import { pool } from '../db.js';
import { actorFromAuthUser, recordAudit } from './audit_service.js';
import { escapeLike, foldSql, foldText, parsePositiveId } from './people_common.js';
import {
  ATTACHMENT_COUNT_SQL,
  STAFF_TRANSITIONS,
  STATUSES,
  TERMINAL_STATUSES,
  accountDeleted,
  commentLimitReached,
  forbiddenRole,
  idempotencyConflict,
  invalidAssignee,
  invalidEquipment,
  invalidTransition,
  itemClosed,
  mapEvent,
  mapManagerItem,
  parseCommentInput,
  parseListQuery,
  parsePatchInput,
  siteNotFound,
  staffScope,
  workItemLimits,
  workItemNotFound,
} from './work_tracking_common.js';
import { listAttachmentsForItem } from './work_attachments_read.js';
import { loadPhotoWarningsSafe } from './work_photo_checks.js';

export const siteLockKey = (siteCode) => `work_items_site:${Number(siteCode)}`;
/** Kullanıcı başına saatlik talep sınırı SİTELER ARASI sayıldığı için ayrı advisory kilidi (site kilidinden SONRA alınır; ters sıra yok). */
export const userLockKey = (userCode) => `work_items_user:${Number(userCode)}`;

// ---------------------------------------------------------------------------
// Transaction yardımcıları (resident tarafı da kullanır)
// ---------------------------------------------------------------------------

async function runTransactionOnce(siteCode, work) {
  const client = await pool.connect();
  let began = false;
  let result;
  try {
    await client.query('BEGIN');
    began = true;
    // sites FOR KEY SHARE: site silme ile sıraya girer ama sıradan UPDATE sites'ı beklemez.
    const site = await client.query(`SELECT site_code FROM sites WHERE site_code = $1 FOR KEY SHARE`, [siteCode]);
    if (!site.rows?.[0]) {
      throw siteNotFound();
    }
    result = await work(client);
    await client.query('COMMIT');
  } catch (error) {
    if (began) {
      try {
        await client.query('ROLLBACK');
      } catch (_rollbackError) {
        // bağlantı zaten kopmuş olabilir; asıl hata yukarıda fırlatılır
      }
    }
    throw error;
  } finally {
    client.release();
  }
  return result;
}

/** İş takibi yazma transaction'ı. 40P01'de TEK SEFER baştan denenir (`work` yeniden çalışabilir olmalı). */
export async function withWorkTransaction(siteCode, work) {
  try {
    return await runTransactionOnce(siteCode, work);
  } catch (error) {
    if (error?.code === '40P01') {
      return runTransactionOnce(siteCode, work);
    }
    throw error;
  }
}

/** Yazan kullanıcı hâlâ var ve silinmemiş olmalı: FOR KEY SHARE (hesap silme `UPDATE users` bunu bekler / bunu görür). */
export async function lockActiveUser(client, actor) {
  const userCode = actorFromAuthUser(actor).userCode;
  if (userCode === null || userCode === undefined) {
    throw accountDeleted();
  }
  const found = await client.query(`SELECT user_code FROM users WHERE user_code = $1 AND deleted_at IS NULL FOR KEY SHARE`, [userCode]);
  if (!found.rows?.[0]) {
    throw accountDeleted();
  }
  return userCode;
}

export async function audit(client, actor, action, siteCode, itemId, details) {
  await recordAudit(client, { actor, action, siteCode, targetType: 'work_item', targetId: String(itemId), details }, { inTransaction: true });
}

/** Değişmez günlüğe tek satır ekler. */
export async function insertEvent(client, e) {
  const inserted = await client.query(
    `
      INSERT INTO work_item_events (work_item_id, site_code, event_type, visibility, actor_user_code, actor_kind, from_value, to_value, body, idempotency_key)
      VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
      RETURNING id
    `,
    [e.itemId, e.siteCode, e.type, e.visibility, e.actorUserCode, e.actorKind, e.from ?? null, e.to ?? null, e.body ?? null, e.idempotencyKey ?? null],
  );
  return Number(inserted.rows[0].id);
}

// ---------------------------------------------------------------------------
// Okuma
// ---------------------------------------------------------------------------

const MANAGER_COLUMNS = `
  w.id, w.site_code, w.category, wc.label AS category_label, w.location_type, w.title, w.description, w.status, w.priority, w.resident_urgent,
  to_char(w.due_date, 'YYYY-MM-DD') AS due_date, w.created_at, w.updated_at, w.closed_at,
  w.created_by, w.assigned_to, w.apartment_id, w.block_id, b.block_name, a.unit_label,
  w.equipment_id, eq.name AS equipment_name, eq.kind AS equipment_kind, eq.is_active AS equipment_active,
  CASE WHEN w.created_by IS NULL OR ru.deleted_at IS NOT NULL THEN NULL ELSE ru.full_name END AS requester_name,
  CASE WHEN ru.deleted_at IS NULL THEN ru.phone_number END AS requester_phone,
  CASE WHEN au.deleted_at IS NOT NULL THEN NULL ELSE au.full_name END AS assignee_name,
  ${ATTACHMENT_COUNT_SQL}
`;

const MANAGER_FROM = `
  FROM work_items w
  LEFT JOIN work_categories wc ON wc.site_code = w.site_code AND wc.key = w.category
  LEFT JOIN apartments a ON a.id = w.apartment_id
  LEFT JOIN site_blocks b ON b.id = w.block_id
  LEFT JOIN users ru ON ru.user_code = w.created_by
  LEFT JOIN users au ON au.user_code = w.assigned_to
  LEFT JOIN equipment_items eq ON eq.id = w.equipment_id AND eq.site_code = w.site_code
`;

// Görevli kapsamı (staffScope) ve yetim atama kuralı (ASSIGNEE_ACTIVE_SQL) work_tracking_common.js'tedir (fotoğraf ekleri de aynı kapsamı kullanır).

/** GET .../work-items -> { items, next_before_id, counts }. Sıra id DESC; imleç saf anahtar-kümesi (`id < before_id`). */
export async function listWorkItems(siteCode, query, { kind, userCode }, db = pool) {
  const filters = parseListQuery(query);
  const params = [siteCode];
  const clauses = ['w.site_code = $1'];
  const scopeClauses = [];
  if (kind === 'staff') {
    params.push(userCode);
    scopeClauses.push(staffScope(`$${params.length}`));
  }
  const scopeParams = [...params];
  clauses.push(...scopeClauses);
  if (filters.statuses) {
    params.push(filters.statuses);
    clauses.push(`w.status = ANY($${params.length}::TEXT[])`);
  }
  if (filters.category) {
    params.push(filters.category);
    clauses.push(`w.category = $${params.length}`);
  }
  if (filters.priority) {
    params.push(filters.priority);
    clauses.push(`w.priority = $${params.length}`);
  }
  if (filters.assigned === 'none') {
    clauses.push('w.assigned_to IS NULL');
  } else if (filters.assigned !== null) {
    params.push(filters.assigned === 'me' ? userCode : filters.assigned);
    clauses.push(`w.assigned_to = $${params.length}`);
  }
  if (filters.beforeId !== null) {
    params.push(filters.beforeId);
    clauses.push(`w.id < $${params.length}`);
  }
  if (filters.q) {
    params.push(`%${escapeLike(foldText(filters.q))}%`);
    const term = `$${params.length}`;
    clauses.push(`(${foldSql('w.title')} LIKE ${term} ESCAPE '\\' OR ${foldSql('w.description')} LIKE ${term} ESCAPE '\\')`);
  }
  params.push(filters.limit + 1);
  const [rowsResult, countsResult] = await Promise.all([
    db.query(`SELECT ${MANAGER_COLUMNS} ${MANAGER_FROM} WHERE ${clauses.join(' AND ')} ORDER BY w.id DESC LIMIT $${params.length}`, params),
    db.query(
      `SELECT w.status, COUNT(*)::INTEGER AS n FROM work_items w WHERE w.site_code = $1${scopeClauses.length ? ` AND ${scopeClauses[0]}` : ''} GROUP BY w.status`,
      scopeParams,
    ),
  ]);
  const rows = rowsResult.rows ?? [];
  const hasMore = rows.length > filters.limit;
  const items = rows.slice(0, filters.limit).map((row) => mapManagerItem(row, { kind }));
  const counts = Object.fromEntries(STATUSES.map((status) => [status, 0]));
  for (const row of countsResult.rows ?? []) {
    if (row.status in counts) counts[row.status] = Number(row.n);
  }
  return { items, next_before_id: hasMore && items.length > 0 ? items[items.length - 1].id : null, counts };
}

async function loadManagerRow(db, siteCode, id, { kind, userCode }) {
  const params = [siteCode, id];
  let scope = '';
  if (kind === 'staff') {
    params.push(userCode);
    scope = ` AND ${staffScope('$3')}`;
  }
  const result = await db.query(`SELECT ${MANAGER_COLUMNS} ${MANAGER_FROM} WHERE w.site_code = $1 AND w.id = $2${scope} LIMIT 1`, params);
  return result.rows?.[0] ?? null;
}

/** Kurul yalnız `public` olayları görür; yönetici / görevli hepsini. En yeni 300 olay, eskiden yeniye. */
async function loadEvents(db, siteCode, itemId, { kind }) {
  const detailed = kind !== 'board';
  const result = await db.query(
    `
      SELECT e.id, e.event_type, e.visibility, e.actor_user_code, e.actor_kind, e.from_value, e.to_value, e.body, e.created_at,
             CASE WHEN u.deleted_at IS NOT NULL THEN NULL ELSE u.full_name END AS actor_name
      FROM work_item_events e
      LEFT JOIN users u ON u.user_code = e.actor_user_code
      WHERE e.work_item_id = $1 AND e.site_code = $2 ${detailed ? '' : `AND e.visibility = 'public'`}
      ORDER BY e.id DESC
      LIMIT 300
    `,
    [itemId, siteCode],
  );
  const rows = (result.rows ?? []).reverse();
  const codes = new Set();
  const equipmentIds = new Set();
  for (const row of rows) {
    if (row.event_type === 'assigned') {
      if (row.from_value) codes.add(Number(row.from_value));
      if (row.to_value) codes.add(Number(row.to_value));
    }
    if (row.event_type === 'equipment_changed') {
      if (row.from_value) equipmentIds.add(Number(row.from_value));
      if (row.to_value) equipmentIds.add(Number(row.to_value));
    }
  }
  const labels = new Map();
  if (detailed && codes.size > 0) {
    const names = await db.query(
      `SELECT user_code, CASE WHEN deleted_at IS NOT NULL THEN NULL ELSE full_name END AS full_name FROM users WHERE user_code = ANY($1::INTEGER[])`,
      [[...codes]],
    );
    for (const row of names.rows ?? []) {
      if (row.full_name) labels.set(String(row.user_code), row.full_name);
    }
  }
  // 096: ekipman değişikliği olaylarının adları (yalnız bu sitenin ekipmanı; iç olay olduğundan kurul / sakin görünümünde zaten gelmez).
  const equipmentLabels = new Map();
  if (detailed && equipmentIds.size > 0) {
    const names = await db.query(`SELECT id, name FROM equipment_items WHERE id = ANY($1::BIGINT[]) AND site_code = $2`, [[...equipmentIds], siteCode]);
    for (const row of names.rows ?? []) {
      if (row.name) equipmentLabels.set(String(row.id), row.name);
    }
  }
  return rows.map((row) => mapEvent(row, { detailed, labels, equipmentLabels }));
}

/** GET .../work-items/:id -> { item, events, next_statuses, attachments }. Görünmeyen / yok / başka site -> 404 WORK_ITEM_NOT_FOUND. */
export async function getWorkItemDetail(siteCode, rawId, access, db = pool) {
  const id = parsePositiveId(rawId);
  if (id === null) {
    throw workItemNotFound();
  }
  const row = await loadManagerRow(db, siteCode, id, access);
  if (!row) {
    throw workItemNotFound();
  }
  const events = await loadEvents(db, siteCode, id, access);
  // Fotoğraf ekleri (047): hazır olanlar + çağıranın kendi tamamlanmamış yüklemeleri.
  const attachments = await listAttachmentsForItem(db, id, access.userCode);
  // Fotoğraf yeniden kullanım uyarıları (100, P2-6): yalnız uyarı, asla engel; hazır fotoğraf yoksa sorgu gitmez. Hata ayrıntıyı bozmaz (uyarılar boş döner).
  const photoWarnings = await loadPhotoWarningsSafe(db, { siteCode, itemId: id, scope: access, hasReady: attachments.some((attachment) => attachment.status === 'ready') });
  return {
    item: mapManagerItem(row, { kind: access.kind }),
    events,
    next_statuses: access.kind === 'board' ? [] : [...(STAFF_TRANSITIONS[row.status] ?? [])],
    attachments,
    photo_warnings: photoWarnings,
  };
}

// ---------------------------------------------------------------------------
// Atanabilir kişiler
// ---------------------------------------------------------------------------

/** Sitenin AKTİF yöneticileri + görevlileri (hesabı silinmemiş, etkin). Parametre: $1 = site, isteğe bağlı $2 = tek kullanıcı. */
const ASSIGNABLE_SQL = (single) => `
  SELECT u.user_code, u.full_name, x.role
  FROM (
    SELECT manager_user_code AS user_code, 'manager' AS role FROM site_manager_sites WHERE site_code = $1
    UNION ALL
    SELECT user_code, CASE WHEN role = 'STAFF' THEN 'staff' ELSE 'manager' END FROM site_memberships
    WHERE site_code = $1 AND is_active = TRUE AND role IN ('SITE_OWNER', 'SITE_ADMIN', 'STAFF')
  ) x
  INNER JOIN users u ON u.user_code = x.user_code AND u.deleted_at IS NULL AND u.is_active = TRUE
  ${single ? 'WHERE x.user_code = $2' : ''}
`;

/** GET .../work-items/assignees -> { items: [{ user_code, name, role }] }. Görevli yalnız kendini görür. */
export async function listAssignees(siteCode, access, db = pool) {
  const result = await db.query(`${ASSIGNABLE_SQL(false)} ORDER BY u.full_name, u.user_code`, [siteCode]);
  const byUser = new Map();
  for (const row of result.rows ?? []) {
    const existing = byUser.get(Number(row.user_code));
    if (!existing || row.role === 'manager') {
      byUser.set(Number(row.user_code), { user_code: Number(row.user_code), name: row.full_name, role: row.role });
    }
  }
  let items = [...byUser.values()];
  if (access.kind === 'staff') {
    items = items.filter((item) => item.user_code === access.userCode);
  } else if (access.userCode !== null && !byUser.has(access.userCode)) {
    // süper kullanıcı kendine atayabilir
    const self = await db.query(`SELECT user_code, full_name FROM users WHERE user_code = $1 AND deleted_at IS NULL`, [access.userCode]);
    if (self.rows?.[0] && access.kind === 'super') {
      items.unshift({ user_code: access.userCode, name: self.rows[0].full_name, role: 'manager' });
    }
  }
  return { items };
}

// ---------------------------------------------------------------------------
// Yazma: PATCH (durum / öncelik / atama / hedef tarih) ve yorum
// ---------------------------------------------------------------------------

const actorKindOf = (kind) => (kind === 'staff' ? 'staff' : 'manager');

/**
 * PATCH .../work-items/:id -> getWorkItemDetail. Alan başına bir olay + bir audit satırı; değişiklik yoksa hiçbir şey yazılmaz (200, aynı gövde).
 * Kurallar: kapandi / iptal SONDUR (WORK_ITEM_CLOSED); geçişler STAFF_TRANSITIONS (INVALID_TRANSITION); görevli yalnız kendine atar / kendini bırakır
 * (başkasına atama 403 FORBIDDEN_ROLE); yönetici / süper sitenin aktif yöneticisi ya da görevlisine (süper: kendine de) atar (INVALID_ASSIGNEE).
 */
export async function updateWorkItem({ siteCode, rawId, actor, access, body }) {
  if (access.kind === 'board') {
    throw forbiddenRole();
  }
  const input = parsePatchInput(body);
  const id = parsePositiveId(rawId);
  if (id === null) {
    throw workItemNotFound();
  }
  await withWorkTransaction(siteCode, async (client) => {
    const userCode = await lockActiveUser(client, actor);
    // Görevli kapsamı (kendine atanmış / atanmamış / yetim atama) kilit sorgusunun İÇİNDE: görünmeyen talep 404.
    const found = await client.query(
      `SELECT w.id, w.status, w.priority, w.assigned_to, w.equipment_id, to_char(w.due_date, 'YYYY-MM-DD') AS due_date FROM work_items w
       WHERE w.id = $1 AND w.site_code = $2${access.kind === 'staff' ? ` AND ${staffScope('$3')}` : ''} FOR UPDATE OF w`,
      access.kind === 'staff' ? [id, siteCode, userCode] : [id, siteCode],
    );
    const row = found.rows?.[0];
    if (!row) {
      throw workItemNotFound();
    }
    const currentAssignee = row.assigned_to === null ? null : Number(row.assigned_to);
    const nextAssignee = input.assignedTo === 'me' ? userCode : input.assignedTo;
    const changes = {};
    if (input.status !== undefined && input.status !== row.status) changes.status = input.status;
    if (input.priority !== undefined && input.priority !== row.priority) changes.priority = input.priority;
    if ('assignedTo' in input && nextAssignee !== currentAssignee) changes.assignedTo = nextAssignee;
    if ('dueDate' in input && input.dueDate !== (row.due_date ?? null)) changes.dueDate = input.dueDate;
    const currentEquipment = row.equipment_id === null || row.equipment_id === undefined ? null : Number(row.equipment_id);
    if ('equipmentId' in input && input.equipmentId !== currentEquipment) changes.equipmentId = input.equipmentId;
    if (Object.keys(changes).length === 0) {
      return;
    }
    if (TERMINAL_STATUSES.includes(row.status)) {
      throw itemClosed();
    }
    if (changes.status !== undefined && !(STAFF_TRANSITIONS[row.status] ?? []).includes(changes.status)) {
      throw invalidTransition(row.status, changes.status);
    }
    if ('assignedTo' in changes) {
      await assertAssignable(client, { siteCode, access, userCode, currentAssignee, target: changes.assignedTo });
    }
    if ('equipmentId' in changes && changes.equipmentId !== null) {
      await assertEquipmentLinkable(client, siteCode, changes.equipmentId);
    }

    const sets = ['updated_at = NOW()'];
    const params = [id, siteCode];
    const push = (value) => {
      params.push(value);
      return `$${params.length}`;
    };
    if (changes.status !== undefined) {
      sets.push(`status = ${push(changes.status)}`);
      sets.push(TERMINAL_STATUSES.includes(changes.status) ? 'closed_at = NOW()' : 'closed_at = NULL');
      sets.push('resident_updated_at = clock_timestamp()');
    }
    if (changes.priority !== undefined) sets.push(`priority = ${push(changes.priority)}`);
    if ('assignedTo' in changes) sets.push(`assigned_to = ${push(changes.assignedTo)}`);
    if ('dueDate' in changes) {
      sets.push(`due_date = ${push(changes.dueDate)}::DATE`);
      sets.push('resident_updated_at = clock_timestamp()');
    }
    // Ekipman bağı (096) iç bir bilgidir: sakinin "okunmamış" işaretini TETİKLEMEZ (resident_updated_at dokunulmaz).
    if ('equipmentId' in changes) sets.push(`equipment_id = ${push(changes.equipmentId)}`);
    await client.query(`UPDATE work_items SET ${sets.join(', ')} WHERE id = $1 AND site_code = $2`, params);

    const base = { itemId: id, siteCode, actorUserCode: userCode, actorKind: actorKindOf(access.kind) };
    if (changes.status !== undefined) {
      await insertEvent(client, { ...base, type: 'status_changed', visibility: 'public', from: row.status, to: changes.status });
      await audit(client, actor, 'work_item.status_changed', siteCode, id, { from: row.status, to: changes.status });
    }
    if (changes.priority !== undefined) {
      await insertEvent(client, { ...base, type: 'priority_changed', visibility: 'internal', from: row.priority, to: changes.priority });
      await audit(client, actor, 'work_item.updated', siteCode, id, { field: 'priority', from: row.priority, to: changes.priority });
    }
    if ('assignedTo' in changes) {
      await insertEvent(client, {
        ...base,
        type: 'assigned',
        visibility: 'internal',
        from: currentAssignee === null ? null : String(currentAssignee),
        to: changes.assignedTo === null ? null : String(changes.assignedTo),
      });
      await audit(client, actor, 'work_item.assigned', siteCode, id, { from: currentAssignee, to: changes.assignedTo });
    }
    if ('dueDate' in changes) {
      await insertEvent(client, { ...base, type: 'due_date_changed', visibility: 'public', from: row.due_date ?? null, to: changes.dueDate });
      await audit(client, actor, 'work_item.updated', siteCode, id, { field: 'due_date' });
    }
    if ('equipmentId' in changes) {
      // İç olay (yalnız yönetim görür); değerler ekipman kimliği metnidir (ad okunurken çözülür). Denetim kaydı yalnız kimlik taşır.
      await insertEvent(client, {
        ...base,
        type: 'equipment_changed',
        visibility: 'internal',
        from: currentEquipment === null ? null : String(currentEquipment),
        to: changes.equipmentId === null ? null : String(changes.equipmentId),
      });
      await audit(client, actor, 'work_item.updated', siteCode, id, { field: 'equipment', from: currentEquipment, to: changes.equipmentId });
    }
  });
  return getWorkItemDetail(siteCode, id, access);
}

/**
 * Bağlanacak ekipman bu sitenin AKTİF ekipmanı olmalı (aksi 400 INVALID_EQUIPMENT; başka sitenin ekipmanı "yok" gibi yanıtlanır, varlık sızmaz). FOR KEY SHARE: ekipman
 * satırı bağ yazılırken silinemez / anahtarı değişemez (kilit sırası: ... work_items FOR UPDATE -> equipment_items FOR KEY SHARE -> work_item_events).
 */
async function assertEquipmentLinkable(client, siteCode, equipmentId) {
  const found = await client.query(`SELECT id, is_active FROM equipment_items WHERE id = $1 AND site_code = $2 FOR KEY SHARE`, [equipmentId, siteCode]);
  const equipment = found.rows?.[0];
  if (!equipment) {
    throw invalidEquipment('Ekipman bu siteye ait değil ya da bulunamadı.');
  }
  if (equipment.is_active !== true) {
    throw invalidEquipment('Pasif ekipman seçilemez. Önce Ekipman ve Bakım ekranından etkinleştirin.');
  }
}

async function assertAssignable(client, { siteCode, access, userCode, currentAssignee, target }) {
  if (access.kind === 'staff') {
    // görevli: kendini atar (üstlenir) ya da yalnız KENDİNE atanmış talebi bırakır (null); başkasına atayamaz
    const releasingOwn = target === null && currentAssignee === userCode;
    if (target !== userCode && !releasingOwn) {
      throw forbiddenRole();
    }
    return;
  }
  if (target === null) {
    return;
  }
  if (target === userCode && access.kind === 'super') {
    return;
  }
  // Atanan kullanıcı canlı-kullanıcı kilidiyle okunur (FOR KEY SHARE, deleted_at IS NULL): hesap silme ile yarışta silinmiş hesaba atama yazılmaz.
  const live = await client.query(`SELECT user_code FROM users WHERE user_code = $1 AND deleted_at IS NULL FOR KEY SHARE`, [target]);
  if (!live.rows?.[0]) {
    throw invalidAssignee('Talep yalnız sitenin yöneticisine ya da görevlisine atanabilir.');
  }
  const ok = await client.query(`${ASSIGNABLE_SQL(true)} LIMIT 1`, [siteCode, target]);
  if (!ok.rows?.[0]) {
    throw invalidAssignee('Talep yalnız sitenin yöneticisine ya da görevlisine atanabilir.');
  }
}

/**
 * POST .../work-items/:id/comments -> { event, replayed }. Aynı (talep, yazan, idempotency_key) -> aynı olay (çift satır yok; kapanmış talepte de tekrar oynatılır).
 * Kapandi / iptal talepte yorum YOK (409 WORK_ITEM_CLOSED). Kurul 403.
 */
export async function addWorkItemComment({ siteCode, rawId, actor, access, body }) {
  if (access.kind === 'board') {
    throw forbiddenRole();
  }
  const input = parseCommentInput(body);
  const id = parsePositiveId(rawId);
  if (id === null) {
    throw workItemNotFound();
  }
  const limits = workItemLimits();
  const created = await withWorkTransaction(siteCode, async (client) => {
    const userCode = await lockActiveUser(client, actor);
    const found = await client.query(
      `SELECT w.status FROM work_items w WHERE w.id = $1 AND w.site_code = $2${access.kind === 'staff' ? ` AND ${staffScope('$3')}` : ''} FOR UPDATE OF w`,
      access.kind === 'staff' ? [id, siteCode, userCode] : [id, siteCode],
    );
    const row = found.rows?.[0];
    if (!row) {
      throw workItemNotFound();
    }
    const replay = await client.query(
      `SELECT id, body, visibility FROM work_item_events WHERE work_item_id = $1 AND actor_user_code = $2 AND idempotency_key = $3 LIMIT 1`,
      [id, userCode, input.idempotencyKey],
    );
    if (replay.rows?.[0]) {
      // aynı anahtar FARKLI içerikle gelirse sessizce eski yorum dönmez
      if (replay.rows[0].body !== input.body || replay.rows[0].visibility !== input.visibility) {
        throw idempotencyConflict();
      }
      return { eventId: Number(replay.rows[0].id), replayed: true };
    }
    if (TERMINAL_STATUSES.includes(row.status)) {
      throw itemClosed();
    }
    // Yönetim yorumları sakin yorumlarından AYRI sayılır: sakin kendi sınırını doldursa da yönetim yazabilir.
    const count = await client.query(
      `SELECT COUNT(*)::INTEGER AS n FROM work_item_events WHERE work_item_id = $1 AND event_type = 'comment' AND actor_kind <> 'resident'`,
      [id],
    );
    if (Number(count.rows[0].n) >= limits.maxComments) {
      throw commentLimitReached(limits.maxComments);
    }
    const eventId = await insertEvent(client, {
      itemId: id,
      siteCode,
      type: 'comment',
      visibility: input.visibility,
      actorUserCode: userCode,
      actorKind: actorKindOf(access.kind),
      body: input.body,
      idempotencyKey: input.idempotencyKey,
    });
    await client.query(
      `UPDATE work_items SET updated_at = NOW()${input.visibility === 'public' ? ', resident_updated_at = clock_timestamp()' : ''} WHERE id = $1 AND site_code = $2`,
      [id, siteCode],
    );
    await audit(client, actor, 'work_item.commented', siteCode, id, { visibility: input.visibility });
    return { eventId, replayed: false };
  });
  const events = await loadEvents(pool, siteCode, id, access);
  return { event: events.find((event) => event.id === created.eventId) ?? null, replayed: created.replayed };
}

/**
 * Hesap silme (account_deletion_service, AYNI işlem): silinen kullanıcıya atanmış AÇIK talepler atamasız kalır ve her biri için iç (internal) bir "assigned" olayı yazılır
 * (kapandi / iptal talepler geçmiş olarak kalır). Satırlar id sırasıyla kilitlenir. Tablo yoksa atlanır. @returns bırakılan talep sayısı
 */
export async function releaseAssignedWorkItems(client, userCode) {
  const present = (await client.query(`SELECT to_regclass('public.work_items') IS NOT NULL AS present`)).rows?.[0];
  if (present?.present !== true) {
    return 0;
  }
  const released = await client.query(
    `
      UPDATE work_items SET assigned_to = NULL, updated_at = NOW()
      WHERE id IN (SELECT id FROM work_items WHERE assigned_to = $1 AND status NOT IN ('kapandi', 'iptal') ORDER BY id FOR UPDATE)
      RETURNING id, site_code
    `,
    [userCode],
  );
  for (const row of released.rows ?? []) {
    await client.query(
      `
        INSERT INTO work_item_events (work_item_id, site_code, event_type, visibility, actor_user_code, actor_kind, from_value, to_value)
        VALUES ($1, $2, 'assigned', 'internal', $3, 'staff', $4, NULL)
      `,
      [Number(row.id), Number(row.site_code), userCode, String(userCode)],
    );
  }
  return (released.rows ?? []).length;
}
