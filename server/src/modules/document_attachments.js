// Belgeler (Faz 3b-A): duyuruya belge eki (docs/PLATFORM_BELGELER.md A12).
//
// - Ek yalnız `draft` / `scheduled` duyuruda değişir (çağıran duyuru servisi durumu denetler; yayında `document_ids` PATCH'i 409 INVALID_STATE).
// - Eklenebilir belge: AYNI site, `active`, `audience = 'residents'` (yönetici/kurul belgesi eklenemez) ve `documents` modülü AÇIK; aksi 409 ATTACHMENT_NOT_ALLOWED.
//   YENİ eklenenler doğrulanır; zaten ekli olanlar (sonradan silinmiş olsa bile) listede kalabilir (`available: false`).
// - Kilit sırası: ... announcements satırı -> documents (FOR KEY SHARE, id sırasıyla) -> announcement_attachments. Audit: document.attached / detached.
// - E-postaya ek KONMAZ (kişisel veri SMTP'ye çıkmasın).

import { recordAudit } from './audit_service.js';
import { attachmentNotAllowed, invalidField } from './document_common.js';
import { assertDocumentsEnabled } from './document_access.js';
import { MODULE_ENABLED_SQL, myApartmentsCte, userInDocumentSiteSql } from './document_resident.js';
import { parsePositiveId } from './people_common.js';

export const MAX_ATTACHMENTS = 5;

/** Gövdedeki `document_ids` -> benzersiz pozitif kimlik dizisi (<= 5); yoksa undefined; geçersizse 400 INVALID_BODY. */
export function parseDocumentIds(value) {
  if (value === undefined) {
    return undefined;
  }
  if (value === null) {
    return [];
  }
  if (!Array.isArray(value)) {
    throw invalidField('Belge eki listesi geçersiz.');
  }
  const ids = [];
  for (const entry of value) {
    const id = parsePositiveId(entry);
    if (id === null) {
      throw invalidField('Belge eki kimliği geçersiz.');
    }
    if (!ids.includes(id)) ids.push(id);
  }
  if (ids.length > MAX_ATTACHMENTS) {
    throw invalidField(`Bir duyuruya en fazla ${MAX_ATTACHMENTS} belge eklenebilir.`);
  }
  return ids;
}

/**
 * Duyurunun ek listesini `documentIds` ile DEĞİŞTİRİR (transaction içinde; duyuru satırı çağıranca kilitli). Sıra = dizideki sıra.
 * @returns {Promise<{ attached: number, detached: number }>}
 */
export async function setAnnouncementAttachments(client, { siteCode, announcementId, documentIds, actor }) {
  const existing = await client.query(
    `SELECT document_id FROM announcement_attachments WHERE announcement_id = $1 ORDER BY position, document_id`,
    [announcementId],
  );
  const existingIds = (existing.rows ?? []).map((row) => Number(row.document_id));
  const added = documentIds.filter((id) => !existingIds.includes(id));
  const removed = existingIds.filter((id) => !documentIds.includes(id));
  if (added.length === 0 && removed.length === 0 && sameOrder(existingIds, documentIds)) {
    return { attached: 0, detached: 0 };
  }
  if (added.length > 0) {
    await assertDocumentsEnabled(siteCode, client);
    const locked = await client.query(
      `SELECT id, site_code, status, audience FROM documents WHERE id = ANY($1::BIGINT[]) ORDER BY id FOR KEY SHARE`,
      [[...added].sort((a, b) => a - b)],
    );
    const byId = new Map((locked.rows ?? []).map((row) => [Number(row.id), row]));
    for (const id of added) {
      const row = byId.get(id);
      if (!row || Number(row.site_code) !== Number(siteCode) || row.status !== 'active' || row.audience !== 'residents') {
        throw attachmentNotAllowed();
      }
    }
  }
  if (removed.length > 0) {
    await client.query(`DELETE FROM announcement_attachments WHERE announcement_id = $1 AND document_id = ANY($2::BIGINT[])`, [announcementId, removed]);
  }
  for (let index = 0; index < documentIds.length; index += 1) {
    await client.query(
      `
        INSERT INTO announcement_attachments (announcement_id, document_id, position)
        VALUES ($1, $2, $3)
        ON CONFLICT (announcement_id, document_id) DO UPDATE SET position = EXCLUDED.position
      `,
      [announcementId, documentIds[index], index],
    );
  }
  for (const id of added) {
    await auditAttachment(client, actor, 'document.attached', siteCode, id, announcementId);
  }
  for (const id of removed) {
    await auditAttachment(client, actor, 'document.detached', siteCode, id, announcementId);
  }
  return { attached: added.length, detached: removed.length };
}

const sameOrder = (a, b) => a.length === b.length && a.every((value, index) => value === b[index]);

async function auditAttachment(client, actor, action, siteCode, documentId, announcementId) {
  await recordAudit(
    client,
    { actor, action, siteCode, targetType: 'document', targetId: String(documentId), details: { announcement_id: announcementId, count: 1 } },
    { inTransaction: true },
  );
}

/** Duyuru -> ek sayısı (liste / özet). @returns {Promise<Map<number, number>>} */
export async function loadAttachmentCounts(db, announcementIds) {
  const ids = (announcementIds ?? []).map(Number).filter((id) => Number.isSafeInteger(id) && id > 0);
  const counts = new Map();
  if (ids.length === 0) {
    return counts;
  }
  const result = await db.query(
    `SELECT announcement_id, COUNT(*)::INTEGER AS n FROM announcement_attachments WHERE announcement_id = ANY($1::BIGINT[]) GROUP BY announcement_id`,
    [ids],
  );
  for (const row of result.rows ?? []) {
    counts.set(Number(row.announcement_id), Number(row.n));
  }
  return counts;
}

/**
 * Duyuru -> ek listesi [{ document_id, title, file_name, mime_type, size_bytes, available }].
 * `available=false`: belge silinmiş, modül kapalı ya da belgenin kitlesi artık `residents` değil (A7: kitle değişikliği ANINDA geçerlidir).
 * GÜVENLİ VARSAYILAN (sakin görünümü): `available=false` iken title / file_name / mime_type / size_bytes NULL döner (silinmiş ya da kitlesi daralmış belgenin adı, yeni
 * sürümünün dosya adı sakine sızmasın). Yönetici / kurul görünümü ad bilgisini görmeye devam etmek için `{ forManager: true }` verir.
 * @returns {Promise<Map<number, object[]>>}
 */
export async function loadAttachments(db, announcementIds, { forManager = false, userCode = null } = {}) {
  const ids = (announcementIds ?? []).map(Number).filter((id) => Number.isSafeInteger(id) && id > 0);
  const byAnnouncement = new Map();
  if (ids.length === 0) {
    return byAnnouncement;
  }
  // SAKİN görünümü (`userCode` verilmiş): kullanıcının belgenin sitesinde hâlâ aktif ilişkisi de şart (R16 P2-5); yönetici görünümünde ilişki aranmaz.
  const residentScope = !forManager && userCode !== null && userCode !== undefined;
  const params = residentScope ? [ids, userCode] : [ids];
  const result = await db.query(
    `
      ${residentScope ? `WITH ${myApartmentsCte('$2')}` : ''}
      SELECT aa.announcement_id, d.id AS document_id, d.title,
             cv.display_name, cv.mime_type, cv.size_bytes,
             (d.status = 'active' AND d.audience = 'residents' AND cv.version_no IS NOT NULL AND ${MODULE_ENABLED_SQL('d')}${residentScope ? ` AND ${userInDocumentSiteSql('d', '$2')}` : ''}) AS available
      FROM announcement_attachments aa
      INNER JOIN announcements a ON a.id = aa.announcement_id
      INNER JOIN documents d ON d.id = aa.document_id AND d.site_code = a.site_code
      LEFT JOIN document_versions cv ON cv.document_id = d.id AND cv.version_no = d.current_version_no AND cv.status = 'ready'
      WHERE aa.announcement_id = ANY($1::BIGINT[])
      ORDER BY aa.announcement_id, aa.position, aa.document_id
    `,
    params,
  );
  for (const row of result.rows ?? []) {
    const key = Number(row.announcement_id);
    if (!byAnnouncement.has(key)) byAnnouncement.set(key, []);
    const available = row.available === true;
    const visible = available || forManager === true;
    byAnnouncement.get(key).push({
      document_id: Number(row.document_id),
      title: visible ? row.title : null,
      file_name: visible ? (row.display_name ?? null) : null,
      mime_type: visible ? (row.mime_type ?? null) : null,
      size_bytes: visible && row.size_bytes !== null && row.size_bytes !== undefined ? Number(row.size_bytes) : null,
      available,
    });
  }
  return byAnnouncement;
}


/**
 * Duyuru listesi / ayrıntısı / gelen kutusu zenginleştirmesi: hata duyuruyu GETİRMEYİ engellemez (ek bilgisi boş döner; yalnız hata kodu günlüğe yazılır).
 * Ek sayısı ve ek listesi tek sorguyla, sayfadaki tüm duyurular için alınır.
 */
export async function loadAttachmentsSafe(db, announcementIds, options) {
  try {
    return await loadAttachments(db, announcementIds, options);
  } catch (error) {
    // eslint-disable-next-line no-console
    console.error('[documents] duyuru ekleri okunamadi:', error?.code || error?.name || 'error');
    return new Map();
  }
}

/** Liste için ek sayıları (hata duyuru listesini engellemez). */
export async function loadAttachmentCountsSafe(db, announcementIds) {
  try {
    return await loadAttachmentCounts(db, announcementIds);
  } catch (error) {
    // eslint-disable-next-line no-console
    console.error('[documents] duyuru ek sayilari okunamadi:', error?.code || error?.name || 'error');
    return new Map();
  }
}
