// İş Takibi fotoğraf ekleri (047): yazma işlemleri (kayıt aç, yüklemeyi tamamla, sil) ve PUT hedef çözümlemesi.
//
// Sözleşme: docs/PLATFORM_IS_TAKIBI.md "Fotoğraf ekleri".
//  - KİLİT SIRASI (work_tracking_service ile aynı): sites FOR KEY SHARE -> users FOR KEY SHARE (silinmiş hesaba yazma yok) -> work_items_user:<kod> advisory
//    -> work_attachments_site:<site> advisory (ikisi de yalnız kayıt AÇARKEN: saatlik sayım + sakin kotası / site kotası) -> work_items (FOR UPDATE) ->
//    work_item_attachments (FOR UPDATE) -> work_item_events. Talep satırı FOR UPDATE ile kilitli olduğundan talep başına 4 sınırı eşzamanlı isteklerde de
//    KESİNDİR. Nadir 40P01'de işlem TEK SEFER baştan denenir.
//  - Kapsam: sakin yalnız KENDİ talebi (+ modül açık, + HÂLÂ aktif sakin); yönetici / süper sitenin tümü; görevli kendine atanmış / atanmamış / yetim atamalı
//    (work_tracking_common.staffScope); kurul hiç yazamaz (rota katmanı 403). Görünmeyen talep 404 WORK_ITEM_NOT_FOUND, yabancı ek 404 WORK_ATTACHMENT_NOT_FOUND.
//  - Kapalı (kapandi / iptal) talepte ekleme 409 INVALID_STATE; silme yalnız yönetici / süper (görevli / sakin 409). Silme: yükleyen ya da yönetici / süper.
//  - Dosya, satır işlemi KESİNLEŞTİKTEN sonra silinir (R11 F7 kalıbı): silinemezse günlüğe yalnız kod yazılır, satır gitmiştir, yetim süpürmesi temizler.
//  - Audit `details` yalnız kimlik / tür / boyut / etiket / içerik özeti (sha256) taşır: dosya adı ASLA yazılmaz. Olaylar: attachment_added (from = önce/sonra etiketi, to = ek no) /
//    attachment_removed (from = ek no) (public; sakin de görür). Etiket (096) yükleme kaydı açılırken verilir; etiketsiz kayıtlar eski kayıtlarla aynıdır.

import { pool } from '../db.js';
import { parsePositiveId } from './people_common.js';
import { TERMINAL_STATUSES, forbiddenRole, workItemNotFound } from './work_tracking_common.js';
import { audit, insertEvent, lockActiveUser, userLockKey, withWorkTransaction } from './work_tracking_service.js';
import { assertStillResident, siteOfOwnItem, userCodeOf } from './work_tracking_resident.js';
import {
  ATTACHMENTS_PER_USER_PER_HOUR,
  ATTACHMENT_SUBTREE,
  ATTACHMENT_UPLOAD_TTL_MINUTES,
  ATTACHMENT_USER_QUOTA_WINDOW_DAYS,
  MAX_ATTACHMENTS_PER_ITEM,
  attachmentForbidden,
  attachmentHourlyLimitReached,
  attachmentInvalidState,
  attachmentLimitReached,
  attachmentLimits,
  attachmentNotFound,
  attachmentQuotaExceeded,
  mapAttachment,
  parseAttachmentId,
  parseAttachmentInput,
} from './work_attachments_common.js';
import { activeAttachmentSql, itemScopeSql, loadAttachmentRow, loadVisibleAttachment } from './work_attachments_read.js';
import { uploadAlreadyCompleted, uploadExpired } from './document_common.js';
import { newStorageKey, removeStoredFile, resolveStorageRoot } from './document_storage.js';

// --- Kapsam ------------------------------------------------------------------------------------------------------

/** Sakin kapsamı (/app uçları): çağıranın kendi talepleri. */
export function residentScope(authUser) {
  return { kind: 'resident', userCode: userCodeOf(authUser), siteCode: null, canManage: false };
}

/** Yönetim kapsamı (/manager uçları; resolveWorkAccess sonucundan). */
export function managerScope(access) {
  return { kind: access.kind, userCode: access.userCode, siteCode: access.siteCode, canManage: access.canManage === true };
}

const actorKindOf = (scope) => (scope.kind === 'resident' ? 'resident' : scope.kind === 'staff' ? 'staff' : 'manager');

async function resolveSite(scope, itemId) {
  if (scope.kind === 'resident') {
    return siteOfOwnItem(scope.userCode, itemId);
  }
  return scope.siteCode;
}

/** Görünür talebi FOR UPDATE ile kilitleyip okur (kapsam kilit sorgusunun İÇİNDE: görünmeyen talep 404). */
async function lockVisibleItem(client, scope, itemId) {
  const params = [];
  const where = itemScopeSql(scope, itemId, params);
  const found = await client.query(`SELECT w.id, w.site_code, w.status FROM work_items w WHERE ${where} FOR UPDATE OF w`, params);
  const row = found.rows?.[0];
  if (!row) {
    throw workItemNotFound();
  }
  return row;
}

function parseItemId(rawId) {
  const id = parsePositiveId(rawId);
  if (id === null) {
    throw workItemNotFound();
  }
  return id;
}

/** Yanıt eki: sakin kapsamında SAKİN görünümüyle eşlenir (WA-SEC-1). */
async function attachmentResponse(attId, userCode, scope) {
  const row = await loadAttachmentRow(pool, attId);
  if (!row) {
    throw attachmentNotFound();
  }
  return { attachment: mapAttachment(row, { userCode, residentView: scope?.kind === 'resident' }) };
}

/** Site başına fotoğraf kotası sayımı için advisory kilit anahtarı (kullanıcı kilidinden SONRA, talep satırından ÖNCE alınır; ters sıra yok). */
export const siteAttachmentLockKey = (siteCode) => `work_attachments_site:${Number(siteCode)}`;

// --- POST .../attachments ------------------------------------------------------------------------------------------

/**
 * Yükleme kaydı açar (status uploading, storage_key sunucuda üretilir) -> 201 { attachment }. Sınırlar: talep başına 4 (ready + uploading, 409 LIMIT_REACHED),
 * kullanıcı başına saatte 30 kayıt (429), kapalı talep 409 INVALID_STATE, bayt kotaları (ready + süresi dolmamış uploading boyutları, gelen boyut dahil):
 *  - sakin kotası (R2-2; YALNIZ sakin kapsamı, görevli / yönetici / süper muaf): sakinin bu sitede SON 30 GÜNDE, KENDİ taleplerine (sakin olarak)
 *    açtığı kayıtlar WORK_ATTACHMENTS_USER_QUOTA_MB (200) -> 409 ATTACHMENT_QUOTA_EXCEEDED { quota: 'user', quota_bytes, used_bytes, window_days: 30 }.
 *    Kayan pencere sayesinde kapanan talepteki (silemediği) fotoğraflar sakini kalıcı olarak kilitlemez; aynı kişinin görevli olarak yükledikleri sayılmaz;
 *  - site kotası (herkes, pencere yok): sitenin toplamı WORK_ATTACHMENTS_SITE_QUOTA_MB (10240) -> 409 { quota: 'site', quota_bytes, used_bytes }.
 * Sakin toplamı kullanıcı kilidi, site toplamı site fotoğraf kilidi altında sayılır (yarışta aşılmaz). Pencere sorgusu (uploaded_by, created_at) kısmi
 * indeksini kullanır. Dosya içeriği ayrı PUT ile gelir (work_attachments_upload.js).
 */
export async function createAttachment({ scope, rawId, actor, body }) {
  const input = parseAttachmentInput(body);
  const itemId = parseItemId(rawId);
  const siteCode = await resolveSite(scope, itemId);
  const limits = attachmentLimits();
  const created = await withWorkTransaction(siteCode, async (client) => {
    const userCode = await lockActiveUser(client, actor);
    // saatlik sınır siteler arası: kullanıcı kilidi talep satırından ÖNCE (createWorkItem ile aynı yön: advisory -> satır)
    await client.query('SELECT pg_advisory_xact_lock(hashtext($1))', [userLockKey(userCode)]);
    // site kotası: aynı sitedeki eşzamanlı kayıtlar bu kilitte sıraya girer (yalnız bu akış alır; kullanıcı kilidinden SONRA)
    await client.query('SELECT pg_advisory_xact_lock(hashtext($1))', [siteAttachmentLockKey(siteCode)]);
    const item = await lockVisibleItem(client, scope, itemId);
    if (scope.kind === 'resident') {
      await assertStillResident(client, userCode, siteCode);
    }
    if (TERMINAL_STATUSES.includes(item.status)) {
      throw attachmentInvalidState();
    }
    const hourly = await client.query(
      `SELECT COUNT(*)::INTEGER AS n FROM work_item_attachments WHERE uploaded_by = $1 AND created_at > NOW() - INTERVAL '1 hour'`,
      [userCode],
    );
    if (Number(hourly.rows[0].n) >= ATTACHMENTS_PER_USER_PER_HOUR) {
      throw attachmentHourlyLimitReached();
    }
    // Talep sınırı ve kotalarda yalnız ETKİN kayıtlar sayılır: hazır ya da süresi DOLMAMIŞ yükleme (2 saati aşan `uploading` satırı bakım işi silene dek de
    // sayılmaz; sahibi o kayda PUT atarsa 410 UPLOAD_EXPIRED alır).
    const count = await client.query(
      `SELECT COUNT(*)::INTEGER AS n FROM work_item_attachments a WHERE a.work_item_id = $1 AND ${activeAttachmentSql('a', '$2')}`,
      [itemId, ATTACHMENT_UPLOAD_TTL_MINUTES],
    );
    if (Number(count.rows[0].n) >= MAX_ATTACHMENTS_PER_ITEM) {
      throw attachmentLimitReached();
    }
    if (scope.kind === 'resident') {
      // R2-2: yalnız sakin; kayan 30 günlük pencere (idx_work_item_attachments_uploaded_by: uploaded_by, created_at). Yalnız SAKİN olarak yüklenenler sayılır:
      // sakin kapsamı yalnız KENDİ talebine yükleyebildiğinden ölçüt "talebi açan = yükleyen"; aynı kişinin görevli / yönetici olarak başka taleplere
      // yüklediği fotoğraflar sakin penceresine girmez (çift rol, inceleme 4. tur). Talep satırı birincil anahtarla okunur.
      const mine = await client.query(
        `
          SELECT COALESCE(SUM(a.size_bytes), 0)::BIGINT AS used
          FROM work_item_attachments a
          WHERE a.uploaded_by = $2 AND a.created_at > NOW() - make_interval(days => $4::INTEGER) AND a.site_code = $1 AND ${activeAttachmentSql('a', '$3')}
            AND EXISTS (SELECT 1 FROM work_items w WHERE w.id = a.work_item_id AND w.created_by = a.uploaded_by)
        `,
        [siteCode, userCode, ATTACHMENT_UPLOAD_TTL_MINUTES, ATTACHMENT_USER_QUOTA_WINDOW_DAYS],
      );
      const used = Number(mine.rows?.[0]?.used ?? 0);
      if (used + input.sizeBytes > limits.userQuotaBytes) {
        throw attachmentQuotaExceeded('user', used, limits.userQuotaBytes);
      }
    }
    const site = await client.query(
      `SELECT COALESCE(SUM(a.size_bytes), 0)::BIGINT AS used FROM work_item_attachments a WHERE a.site_code = $1 AND ${activeAttachmentSql('a', '$2')}`,
      [siteCode, ATTACHMENT_UPLOAD_TTL_MINUTES],
    );
    const siteUsed = Number(site.rows?.[0]?.used ?? 0);
    if (siteUsed + input.sizeBytes > limits.siteQuotaBytes) {
      throw attachmentQuotaExceeded('site', siteUsed, limits.siteQuotaBytes);
    }
    // 096: "önce / sonra" etiketi yükleme kaydı açılırken verilir (yok = etiketsiz, eski kayıtlarla aynı).
    const inserted = await client.query(
      `
        INSERT INTO work_item_attachments (work_item_id, site_code, uploaded_by, file_name, mime_type, size_bytes, status, storage_key, phase)
        VALUES ($1, $2, $3, $4, $5, $6, 'uploading', $7, $8)
        RETURNING id
      `,
      [itemId, siteCode, userCode, input.fileName, input.mimeType, input.sizeBytes, newStorageKey(siteCode), input.phase ?? null],
    );
    return { attId: Number(inserted.rows[0].id), userCode };
  });
  return attachmentResponse(created.attId, created.userCode, scope);
}

// --- PUT .../attachments/:attId/content: hedef ve tamamlama -------------------------------------------------------

/**
 * PUT ön kontrolü (gövde okunmadan): görünür talep + o talebe ait, `uploading`, BU kullanıcının açtığı kayıt. Hazırsa 409 UPLOAD_ALREADY_COMPLETED; süresi
 * dolmuşsa 410 UPLOAD_EXPIRED; başkasının kaydı 404 (varlık sızmaz).
 * @returns {Promise<{ attId: number, itemId: number, siteCode: number, storageKey: string, sizeBytes: number, mimeType: string, fileName: string, phase: 'before'|'after'|null }>}
 */
export async function findAttachmentUploadTarget({ scope, rawId, rawAttId, userCode }, db = pool) {
  const itemId = parseItemId(rawId);
  const attId = parseAttachmentId(rawAttId);
  const row = await loadVisibleAttachment(db, scope, itemId, attId);
  if (!row || Number(row.uploaded_by) !== Number(userCode)) {
    throw attachmentNotFound();
  }
  if (row.status === 'ready') {
    throw uploadAlreadyCompleted();
  }
  if (row.expired === true) {
    throw uploadExpired();
  }
  if (TERMINAL_STATUSES.includes(row.item_status)) {
    throw attachmentInvalidState();
  }
  return {
    attId,
    itemId,
    siteCode: Number(row.site_code),
    storageKey: row.storage_key,
    sizeBytes: Number(row.size_bytes),
    mimeType: row.mime_type,
    fileName: row.file_name,
    phase: row.phase ?? null,
  };
}

/**
 * Dosya diskte (son yolda) ve doğrulandı: kaydı `ready` yapar (tek işlem) + `attachment_added` olayı (public) + audit; yönetim eklediyse sakinin okunmamış işareti
 * (resident_updated_at) güncellenir, sakin eklediyse güncellenmez. Satır artık yoksa / anahtarı başkaysa / hazırsa / süresi dolmuşsa / talep kapandıysa hata
 * fırlatır: çağıran son dosyayı siler.
 */
export async function completeAttachmentUpload({ scope, target, actor, sha256 }) {
  const userCode = await withWorkTransaction(target.siteCode, async (client) => {
    const actorCode = await lockActiveUser(client, actor);
    const item = await lockVisibleItem(client, scope, target.itemId);
    if (scope.kind === 'resident') {
      // kayıt açıldıktan sonra taşınan / pasifleşen sakin yüklemeyi tamamlayamaz (kayıt açma ve silme ile aynı kural)
      await assertStillResident(client, actorCode, target.siteCode);
    }
    if (TERMINAL_STATUSES.includes(item.status)) {
      throw attachmentInvalidState();
    }
    const found = await client.query(
      `
        SELECT id, status, storage_key, mime_type, size_bytes, (created_at < NOW() - make_interval(mins => $3::INTEGER)) AS expired
        FROM work_item_attachments WHERE id = $1 AND work_item_id = $2 FOR UPDATE
      `,
      [target.attId, target.itemId, ATTACHMENT_UPLOAD_TTL_MINUTES],
    );
    const row = found.rows?.[0];
    if (!row || row.storage_key !== target.storageKey) {
      throw attachmentNotFound();
    }
    if (row.status === 'ready') {
      throw uploadAlreadyCompleted();
    }
    // satır kilidi altında süre denetimi: bakım işinin silmek üzere olduğu bayat satır `ready` OLAMAZ (bakım DELETE'i aynı satırı kilitler; kim önce gelirse)
    if (row.expired === true) {
      throw uploadExpired();
    }
    await client.query(`UPDATE work_item_attachments SET status = 'ready', sha256 = $2, ready_at = NOW() WHERE id = $1`, [row.id, sha256]);
    const management = scope.kind !== 'resident';
    // Dosya kimliği izi (P2-7): olayda dosya = to (ek no), etiket = from (096; etiketsiz null); kayıt = olayın talebi. Denetim kaydında ayrıca içerik özeti (sha256).
    await insertEvent(client, {
      itemId: target.itemId,
      siteCode: target.siteCode,
      type: 'attachment_added',
      visibility: 'public',
      actorUserCode: actorCode,
      actorKind: actorKindOf(scope),
      from: target.phase ?? null,
      to: String(row.id),
    });
    await client.query(
      `UPDATE work_items SET updated_at = NOW()${management ? ', resident_updated_at = clock_timestamp()' : ''} WHERE id = $1 AND site_code = $2`,
      [target.itemId, target.siteCode],
    );
    await audit(client, actor, 'work_item.attachment_added', target.siteCode, target.itemId, {
      attachment_id: Number(row.id),
      mime_type: row.mime_type,
      size_bytes: Number(row.size_bytes),
      by: management ? 'management' : 'resident',
      phase: target.phase ?? null,
      sha256: sha256 ?? null,
    });
    return actorCode;
  });
  return attachmentResponse(target.attId, userCode, scope);
}

// --- DELETE .../attachments/:attId ----------------------------------------------------------------------------------

/**
 * Eki siler -> { deleted: true }. Yükleyen (sakin / görevli / yönetici) kendi eklediğini, yönetici / süper her eki siler; başkasınınki 403 FORBIDDEN_ROLE.
 * Kapalı (kapandi / iptal) talepte YALNIZ yönetici / süper silebilir (moderasyon / KVKK, WA-SEC-2); görevli ve sakin 409 INVALID_STATE.
 * Hazır ek silinince `attachment_removed` olayı (public) + audit; tamamlanmamış kayıt olaysız kalkar (audit yine yazılır).
 * Dosya COMMIT SONRASI silinir; silinemezse satır gitmiştir, yetim süpürmesi temizler.
 */
export async function deleteAttachment({ scope, rawId, rawAttId, actor }) {
  const itemId = parseItemId(rawId);
  const attId = parseAttachmentId(rawAttId);
  const siteCode = await resolveSite(scope, itemId);
  const removed = await withWorkTransaction(siteCode, async (client) => {
    const userCode = await lockActiveUser(client, actor);
    const item = await lockVisibleItem(client, scope, itemId);
    if (scope.kind === 'resident') {
      await assertStillResident(client, userCode, siteCode);
    }
    const found = await client.query(
      `SELECT id, uploaded_by, status, storage_key, mime_type, size_bytes FROM work_item_attachments WHERE id = $1 AND work_item_id = $2 FOR UPDATE`,
      [attId, itemId],
    );
    const row = found.rows?.[0];
    if (!row) {
      throw attachmentNotFound();
    }
    if (scope.kind === 'board') {
      throw forbiddenRole();
    }
    const own = row.uploaded_by !== null && Number(row.uploaded_by) === Number(userCode);
    if (!own && !scope.canManage) {
      throw attachmentForbidden();
    }
    const closedItem = TERMINAL_STATUSES.includes(item.status);
    if (closedItem && !scope.canManage) {
      throw attachmentInvalidState();
    }
    await client.query(`DELETE FROM work_item_attachments WHERE id = $1`, [attId]);
    if (row.status === 'ready') {
      await insertEvent(client, {
        itemId,
        siteCode,
        type: 'attachment_removed',
        visibility: 'public',
        actorUserCode: userCode,
        actorKind: actorKindOf(scope),
        from: String(attId),
      });
      await client.query(`UPDATE work_items SET updated_at = NOW() WHERE id = $1 AND site_code = $2`, [itemId, siteCode]);
    }
    await audit(client, actor, 'work_item.attachment_removed', siteCode, itemId, {
      attachment_id: attId,
      status: row.status,
      mime_type: row.mime_type,
      size_bytes: Number(row.size_bytes),
      by: scope.kind === 'resident' ? 'resident' : 'management',
      own,
      closed_item: closedItem,
    });
    return { storageKey: row.storage_key };
  });
  // İşlem KESİNLEŞTİ: dosya şimdi silinir (R11 F7). Hata isteği BAŞARISIZ yapmaz; günlüğe yalnız kod yazılır.
  if (removed.storageKey) {
    try {
      await removeStoredFile(resolveStorageRoot().dir, removed.storageKey, ATTACHMENT_SUBTREE);
    } catch (error) {
      // eslint-disable-next-line no-console
      console.error('[work_tracking] fotograf dosyasi silinemedi (DB kaydi silindi; dosya yetim kaldi, bakim supurur):', error?.code || error?.name || 'error');
    }
  }
  return { deleted: true };
}
