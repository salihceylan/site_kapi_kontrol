// İş Takibi fotoğraf ekleri (047): SALT OKUNUR yardımcılar (talep ayrıntısındaki ek listesi, görünürlük kapsamı, indirme çözümlemesi).
//
// Ayrı dosya: work_tracking_service.js / work_tracking_resident.js bu dosyayı, work_attachments_service.js ise onları içe aktarır (döngü yok).
// Görünürlük = talebi görebilmek: sakin yalnız KENDİ talebi (+ modül açık); yönetici / süper / kurul sitenin tümü; görevli kendine atanmış / atanmamış / yetim
// atamalı talepler (work_tracking_common.staffScope). Her sorguda talep + site (ya da açan) bağı vardır (IDOR yok): ek talebe, talep siteye ait olmalı; aksi 404.

import { pool } from '../db.js';
import { MODULE_ON_SQL, staffScope, workItemNotFound } from './work_tracking_common.js';
import { ATTACHMENT_UPLOAD_TTL_MINUTES, attachmentNotFound, mapAttachment, parseAttachmentId } from './work_attachments_common.js';
import { parsePositiveId } from './people_common.js';

// uploaded_by_resident: yükleyen talebi AÇAN kişi mi (uploaded_by_kind 'resident' | 'management'; WA-SEC-1). Talep satırı alt sorguyla okunur (birincil anahtar).
export const ATTACHMENT_COLUMNS = `
  a.id, a.work_item_id, a.site_code, a.uploaded_by, a.file_name, a.mime_type, a.size_bytes, a.sha256, a.status, a.storage_key, a.created_at, a.ready_at,
  CASE WHEN a.uploaded_by IS NULL OR u.deleted_at IS NOT NULL THEN NULL ELSE u.full_name END AS uploaded_by_name,
  COALESCE(a.uploaded_by IS NOT NULL AND a.uploaded_by = (SELECT wc.created_by FROM work_items wc WHERE wc.id = a.work_item_id), FALSE) AS uploaded_by_resident
`;

export const ATTACHMENT_FROM = `
  FROM work_item_attachments a
  LEFT JOIN users u ON u.user_code = a.uploaded_by
`;

/**
 * ETKİN ek koşulu (talep sınırı, kotalar, ayrıntı listesi): hazır ya da süresi DOLMAMIŞ yükleme. Süresi dolan (2 saati aşan) `uploading` satırı bakım işi
 * silene dek de sayılmaz / listelenmez. `ttlParam`: süreyi (dakika) taşıyan parametre ($n).
 */
export const activeAttachmentSql = (alias, ttlParam) =>
  `(${alias}.status = 'ready' OR (${alias}.status = 'uploading' AND ${alias}.created_at >= NOW() - make_interval(mins => ${ttlParam}::INTEGER)))`;

/**
 * Kapsam koşulu (`w` takma adlı work_items için). Parametreleri `params`a ekler ve WHERE parçasını döndürür.
 * @param {{ kind: string, userCode: number|null, siteCode?: number }} scope kind: 'resident' | 'super' | 'manager' | 'staff' | 'board'
 */
export function itemScopeSql(scope, itemId, params) {
  params.push(itemId);
  const idParam = `$${params.length}`;
  if (scope.kind === 'resident') {
    // sakin okuma yolunun (work_tracking_resident RESIDENT_FROM) aynısı: kendi talebi + modül açık + site onaylı
    params.push(scope.userCode);
    return `w.id = ${idParam} AND w.created_by = $${params.length} AND ${MODULE_ON_SQL}
      AND EXISTS (SELECT 1 FROM sites sx WHERE sx.site_code = w.site_code AND sx.approval_status = 'approved')`;
  }
  params.push(scope.siteCode);
  let clause = `w.id = ${idParam} AND w.site_code = $${params.length}`;
  if (scope.kind === 'staff') {
    params.push(scope.userCode);
    clause += ` AND ${staffScope(`$${params.length}`)}`;
  }
  return clause;
}

/**
 * Talep ayrıntısı: hazır (ready) ekler + çağıranın KENDİ, süresi dolmamış tamamlanmamış (uploading) yüklemeleri; id sırasıyla. Tablo açılışta
 * (ensureWorkAttachmentsSchema) kurulur. `residentView`: sakin görünümü (kendi eklemediği fotoğrafta yükleyen adı 'Yönetim'; WA-SEC-1).
 */
export async function listAttachmentsForItem(db, itemId, userCode, { residentView = false } = {}) {
  const result = await db.query(
    `
      SELECT ${ATTACHMENT_COLUMNS} ${ATTACHMENT_FROM}
      WHERE a.work_item_id = $1 AND (a.status = 'ready' OR (a.uploaded_by = $2 AND ${activeAttachmentSql('a', '$3')}))
      ORDER BY a.id
    `,
    [itemId, userCode ?? null, ATTACHMENT_UPLOAD_TTL_MINUTES],
  );
  return (result.rows ?? []).map((row) => mapAttachment(row, { userCode, residentView }));
}

/** Tek ek satırı (yükleyen adıyla) ya da null. */
export async function loadAttachmentRow(db, attId) {
  const result = await db.query(`SELECT ${ATTACHMENT_COLUMNS} ${ATTACHMENT_FROM} WHERE a.id = $1 LIMIT 1`, [attId]);
  return result.rows?.[0] ?? null;
}

/**
 * Görünür talebe bağlı ek satırı (kilitsiz): talep kapsamda değilse ya da ek o talebe ait değilse null. `readyOnly`: yalnız hazır ekler.
 * @returns {Promise<object|null>}
 */
export async function loadVisibleAttachment(db, scope, itemId, attId, { readyOnly = false } = {}) {
  const params = [];
  const scopeSql = itemScopeSql(scope, itemId, params);
  params.push(attId);
  const attParam = `$${params.length}`;
  params.push(ATTACHMENT_UPLOAD_TTL_MINUTES);
  const result = await db.query(
    `
      SELECT ${ATTACHMENT_COLUMNS}, w.status AS item_status, w.site_code AS item_site_code,
             (a.created_at < NOW() - make_interval(mins => $${params.length}::INTEGER)) AS expired
      ${ATTACHMENT_FROM}
      INNER JOIN work_items w ON w.id = a.work_item_id
      WHERE ${scopeSql} AND a.id = ${attParam}${readyOnly ? ` AND a.status = 'ready'` : ''}
      LIMIT 1
    `,
    params,
  );
  return result.rows?.[0] ?? null;
}

/**
 * GET .../attachments/:attId/content çözümlemesi: görünür talep + HAZIR ek; aksi 404 (talep görünmüyorsa WORK_ITEM_NOT_FOUND, ek yok / hazır değilse
 * WORK_ATTACHMENT_NOT_FOUND; her ikisi de varlık sızdırmaz).
 * @returns {Promise<{ id: number, itemId: number, siteCode: number, storageKey: string, sizeBytes: number, fileName: string, mimeType: string }>}
 */
export async function resolveAttachmentDownload(scope, rawId, rawAttId, db = pool) {
  const itemId = parsePositiveId(rawId);
  if (itemId === null) {
    throw workItemNotFound();
  }
  const attId = parseAttachmentId(rawAttId);
  const row = await loadVisibleAttachment(db, scope, itemId, attId, { readyOnly: true });
  if (!row || !row.storage_key) {
    throw attachmentNotFound();
  }
  return {
    id: Number(row.id),
    itemId,
    siteCode: Number(row.site_code),
    storageKey: row.storage_key,
    sizeBytes: Number(row.size_bytes),
    fileName: row.file_name,
    mimeType: row.mime_type,
  };
}
