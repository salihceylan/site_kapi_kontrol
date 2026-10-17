// Belgeler (Faz 3b-A): yönetici işlemleri (liste / ayrıntı / oluştur / sürüm / tamamla / düzenle / sil / geri al / kalıcı sil) ve indirme çözümlemesi.
//
// Sözleşme: docs/PLATFORM_BELGELER.md Bölüm A.
//  - KİLİT SIRASI (Faz 2/3 ile uyumlu): sites FOR KEY SHARE -> (people_sync advisory: yalnız sakin okuma eşitlemesinde, burada yok) -> users (FOR KEY SHARE,
//    `deleted_at IS NULL`: silinmiş hesaba yazma yok) -> documents_quota:<site> advisory (kota/sayı rezervasyonu; documents satırlarından ÖNCE) ->
//    documents (FOR UPDATE) -> document_versions -> announcement_attachments. Nadir 40P01'de işlem TEK SEFER baştan denenir.
//  - KOTA REZERVASYONU: sürüm satırı `uploading` + bildirilen boyutla EKLENİR ve kotaya o anda sayılır (aynı advisory kilidi altında hesaplanır);
//    yarışan iki yükleme son baytı aşamaz. Tamamlama kotayı DEĞİŞTİRMEZ (gerçek bayt = bildirilen bayt zorunlu).
//  - Her sorguda site_code vardır (IDOR yok). Audit `details` yalnız kimlik/sayı/alan adı taşır: başlık, açıklama, dosya adı, not ASLA yazılmaz.

import { pool } from '../db.js';
import { actorFromAuthUser, recordAudit } from './audit_service.js';
import { escapeLike, foldSql, foldText, apartmentLabel } from './people_common.js';
import { assertTargetBelongsToSite } from './announcement_recipients.js';
import {
  accountDeleted,
  confirmRequired,
  documentInUse,
  documentLimitReached,
  documentNotFound,
  idArray,
  invalidState,
  mapSummaryRow,
  parseCreateInput,
  parseListQuery,
  parsePatchInput,
  parseVersionInput,
  pendingLimitReached,
  quotaExceeded,
  siteNotFound,
  uploadAlreadyCompleted,
  uploadExpired,
  usageBody,
  versionLimitReached,
  versionNotFound,
  toIso,
  assertTargetMatchesAudience,
} from './document_common.js';
import { KIND_INFO, buildDisplayName, classifyDeclaredFile } from './document_validation.js';
import { newStorageKey, removeStoredFile, resolveStorageRoot } from './document_storage.js';

export const SYSTEM_ACTOR = Object.freeze({ full_name: 'Sistem', role: 'system' });

export const quotaLockKey = (siteCode) => `documents_quota:${Number(siteCode)}`;

// ---------------------------------------------------------------------------
// Transaction yardımcıları
// ---------------------------------------------------------------------------

/**
 * COMMIT SONRASI dosya silme (R11 F7). Dosya, DB işlemi İÇİNDE silinirse işlem sonradan başarısız olduğunda (COMMIT hatası, bağlantı kopması, 40P01 yeniden
 * deneme) `ready` sürüm satırı dosyasız kalırdı (VERİ KAYBI). Tersi zararsızdır: satır silindi ama dosya kaldıysa yetim dosyadır ve bakım süpürmesi / fsck bulur.
 * Bu yüzden `tx.deferUnlink(rows)` yalnız niyeti biriktirir; COMMIT başarılıysa silinir. Silme idempotenttir (ENOENT yok sayılır). Hata isteği BAŞARISIZ
 * yapmaz (DB durumu artık kesin): günlüğe yalnız hata kodu yazılır, `onUnlinkFailure` çağrılır.
 */
async function runDeferredUnlinks(rows, onUnlinkFailure) {
  if (rows.length === 0) return;
  let root;
  try {
    root = resolveStorageRoot().dir;
  } catch (error) {
    root = null;
    reportUnlinkFailure(error, onUnlinkFailure);
  }
  if (root === null) return;
  for (const row of rows) {
    try {
      await removeStoredFile(root, row.storage_key);
    } catch (error) {
      reportUnlinkFailure(error, onUnlinkFailure);
    }
  }
}

function reportUnlinkFailure(error, onUnlinkFailure) {
  // eslint-disable-next-line no-console
  console.error('[documents] dosya silinemedi (DB kaydi silindi; dosya yetim kaldi, bakim supurur):', error?.code || error?.name || 'error');
  try {
    onUnlinkFailure?.(error);
  } catch (_ignored) {
    // geri çağrı hatası silme akışını bozmasın
  }
}

async function runTransactionOnce(siteCode, work, options = {}) {
  const client = await pool.connect();
  let began = false;
  const deferred = [];
  const tx = {
    /** @param {Array<{ storage_key: string }>} rows COMMIT sonrası silinecek dosyalar */
    deferUnlink(rows) {
      for (const row of rows) deferred.push({ storage_key: row.storage_key });
    },
  };
  let result;
  try {
    await client.query('BEGIN');
    began = true;
    // 1) site satırı FOR KEY SHARE: site silme ile sıraya girer ama sıradan UPDATE sites'ı beklemez (duyuru servisiyle aynı gerekçe).
    const site = await client.query(`SELECT site_code FROM sites WHERE site_code = $1 FOR KEY SHARE`, [siteCode]);
    if (!site.rows?.[0]) {
      throw siteNotFound();
    }
    result = await work(client, tx);
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
  // İşlem KESİNLEŞTİ (bağlantı havuza iade edildi): dosyalar şimdi silinir.
  await runDeferredUnlinks(deferred, options.onUnlinkFailure);
  return result;
}

/**
 * Belge yazma transaction'ı. 40P01'de TEK SEFER baştan denenir; `work` yeniden çalışabilir olmalı (`work(client, tx)`; dosya silme `tx.deferUnlink` ile
 * COMMIT sonrasına ertelenir, başarısız bir denemenin ertelenmiş silmeleri ATILIR).
 * @param {{ onUnlinkFailure?: (error: Error) => void }} [options]
 */
export async function withDocumentTransaction(siteCode, work, options = {}) {
  try {
    return await runTransactionOnce(siteCode, work, options);
  } catch (error) {
    if (error?.code === '40P01') {
      return runTransactionOnce(siteCode, work, options);
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

async function audit(client, actor, action, siteCode, documentId, details) {
  await recordAudit(
    client,
    { actor, action, siteCode, targetType: 'document', targetId: String(documentId), details },
    { inTransaction: true },
  );
}

// ---------------------------------------------------------------------------
// Okuma: özet, liste, ayrıntı
// ---------------------------------------------------------------------------

/** DocumentSummary SELECT parçası. `daysParam`: saklama gün sayısı parametresinin numarası ($n); `extra`: ek sütunlar (", d.description ..."). */
const summarySelect = (daysParam, extra = '') => `
  SELECT
    d.id, d.title, d.category, d.audience, d.target_type, d.status, d.version_count, d.download_count,
    d.created_at, d.updated_at, d.deleted_at,
    CASE WHEN d.status = 'deleted' AND d.deleted_at IS NOT NULL
      THEN GREATEST(0, CEIL(EXTRACT(EPOCH FROM (d.deleted_at + make_interval(days => $${daysParam}::INTEGER) - NOW())) / 86400))::INTEGER
    END AS days_until_purge,
    cv.version_no AS cv_version_no, cv.display_name AS cv_display_name, cv.mime_type AS cv_mime_type,
    cv.size_bytes AS cv_size_bytes, cv.completed_at AS cv_completed_at,
    CASE d.target_type
      WHEN 'blocks' THEN ARRAY(SELECT b.block_name::TEXT FROM site_blocks b WHERE b.site_code = d.site_code AND b.id = ANY(d.target_block_ids) ORDER BY b.sort_order, b.id)
      WHEN 'apartments' THEN ARRAY(
        SELECT (b.block_name || ' - ' || a.unit_label)::TEXT FROM apartments a INNER JOIN site_blocks b ON b.id = a.block_id
        WHERE a.site_code = d.site_code AND a.id = ANY(d.target_apartment_ids) ORDER BY b.sort_order, a.sort_order, a.id
      )
      ELSE ARRAY[]::TEXT[]
    END AS target_labels,
    u.full_name AS uploaded_by_name${extra}
  FROM documents d
  LEFT JOIN document_versions cv ON cv.document_id = d.id AND cv.version_no = d.current_version_no AND cv.status = 'ready'
  LEFT JOIN users u ON u.user_code = cv.uploaded_by
`;

async function readUsage(db, siteCode, excludeVersionId = null) {
  const result = await db.query(
    `
      SELECT
        (SELECT COALESCE(SUM(size_bytes), 0)::BIGINT FROM document_versions WHERE site_code = $1 AND ($2::BIGINT IS NULL OR id <> $2::BIGINT)) AS used_bytes,
        (SELECT COUNT(*)::INTEGER FROM documents WHERE site_code = $1) AS document_count
    `,
    [siteCode, excludeVersionId],
  );
  return result.rows?.[0] ?? { used_bytes: 0, document_count: 0 };
}

/** Tek belge özeti (yok / başka sitenin kaydı -> null). */
export async function loadSummary(db, siteCode, id, limits, { canSeeUploader = true } = {}) {
  const result = await db.query(`${summarySelect(3)} WHERE d.id = $1 AND d.site_code = $2 LIMIT 1`, [id, siteCode, limits.retentionDays]);
  const row = result.rows?.[0];
  return row ? mapSummaryRow(row, { canSeeUploader }) : null;
}

/** Kurul üyesi yalnız yayındaki ve kurula/sakinlere açık belgeleri görür. */
const boardVisible = (row) => row.status === 'active' && (row.audience === 'board' || row.audience === 'residents');

function listWhere(siteCode, filters, { board }) {
  const params = [siteCode];
  const clauses = [`d.site_code = $1`, `d.status <> 'pending'`];
  const status = board ? 'active' : filters.status;
  if (status !== 'all') {
    params.push(status);
    clauses.push(`d.status = $${params.length}`);
  }
  if (board) {
    clauses.push(`d.audience IN ('board', 'residents')`);
  }
  if (filters.category) {
    params.push(filters.category);
    clauses.push(`d.category = $${params.length}`);
  }
  if (filters.audience) {
    params.push(filters.audience);
    clauses.push(`d.audience = $${params.length}`);
  }
  if (filters.q) {
    params.push(`%${escapeLike(foldText(filters.q))}%`);
    const term = `$${params.length}`;
    clauses.push(
      `(${foldSql('d.title')} LIKE ${term} ESCAPE '\\' OR ${foldSql('d.description')} LIKE ${term} ESCAPE '\\' OR ${foldSql('cv.display_name')} LIKE ${term} ESCAPE '\\')`,
    );
  }
  return { sql: clauses.join(' AND '), params };
}

/**
 * GET documents -> { items: [DocumentSummary], total, usage }. Kurul: yalnız yayındaki kurul/sakin belgeleri, yükleyen adı YOK.
 */
export async function listDocuments(siteCode, query, { kind, limits }, db = pool) {
  const filters = parseListQuery(query);
  const board = kind === 'board';
  const where = listWhere(siteCode, filters, { board });
  const fromJoins = `
    FROM documents d
    LEFT JOIN document_versions cv ON cv.document_id = d.id AND cv.version_no = d.current_version_no AND cv.status = 'ready'
  `;
  const count = await db.query(`SELECT COUNT(*)::INTEGER AS total ${fromJoins} WHERE ${where.sql}`, where.params);
  const daysIndex = where.params.length + 1;
  const page = await db.query(
    `
      ${summarySelect(daysIndex)}
      WHERE ${where.sql}
      ORDER BY d.id DESC
      LIMIT $${daysIndex + 1} OFFSET $${daysIndex + 2}
    `,
    [...where.params, limits.retentionDays, filters.limit, filters.offset],
  );
  const usage = await readUsage(db, siteCode);
  return {
    items: (page.rows ?? []).map((row) => mapSummaryRow(row, { canSeeUploader: !board })),
    total: Number(count.rows?.[0]?.total ?? 0),
    usage: usageBody(usage, limits),
  };
}

/** Hedefin okunur gösterimi (yalnız bu siteye ait kayıtlar): blok adları / daire etiketleri. Blok ve daire adları kişisel veri değildir. */
async function loadTargetView(db, siteCode, row) {
  if (row.target_type === 'blocks') {
    const result = await db.query(
      `SELECT id, block_name FROM site_blocks WHERE site_code = $1 AND id = ANY($2::BIGINT[]) ORDER BY sort_order, id`,
      [siteCode, idArray(row.target_block_ids)],
    );
    return { blocks: (result.rows ?? []).map((entry) => ({ id: Number(entry.id), name: entry.block_name })), apartments: [] };
  }
  if (row.target_type === 'apartments') {
    const result = await db.query(
      `
        SELECT a.id, b.block_name, a.unit_label
        FROM apartments a
        INNER JOIN site_blocks b ON b.id = a.block_id
        WHERE a.site_code = $1 AND a.id = ANY($2::BIGINT[])
        ORDER BY b.sort_order, a.sort_order, a.id
      `,
      [siteCode, idArray(row.target_apartment_ids)],
    );
    return { blocks: [], apartments: (result.rows ?? []).map((entry) => ({ id: Number(entry.id), label: apartmentLabel(entry.block_name, entry.unit_label) })) };
  }
  return { blocks: [], apartments: [] };
}

/**
 * GET documents/:id -> DocumentDetail. Kurul: görünürlük matrisi dışındaki belge 404; yükleyen adları ve ekli duyurular YOK.
 */
export async function getDocumentDetail(siteCode, rawId, { kind, limits }, db = pool) {
  const id = parseDocumentId(rawId);
  const board = kind === 'board';
  const found = await db.query(
    `${summarySelect(3, ', d.description, d.target_block_ids, d.target_apartment_ids')} WHERE d.id = $1 AND d.site_code = $2 LIMIT 1`,
    [id, siteCode, limits.retentionDays],
  );
  const row = found.rows?.[0];
  if (!row || (board && !boardVisible(row))) {
    throw documentNotFound();
  }
  const versions = await db.query(
    `
      SELECT v.version_no, v.display_name, v.mime_type, v.size_bytes, v.sha256, v.note, v.completed_at, u.full_name AS uploaded_by_name
      FROM document_versions v
      LEFT JOIN users u ON u.user_code = v.uploaded_by
      WHERE v.document_id = $1 AND v.site_code = $2 AND v.status = 'ready'
      ORDER BY v.version_no DESC
    `,
    [id, siteCode],
  );
  const view = await loadTargetView(db, siteCode, row);
  const detail = {
    ...mapSummaryRow(row, { canSeeUploader: !board }),
    description: row.description ?? null,
    target: {
      type: row.target_type,
      block_ids: idArray(row.target_block_ids),
      apartment_ids: idArray(row.target_apartment_ids),
      blocks: view.blocks,
      apartments: view.apartments,
      labels: mapLabels(row.target_labels),
    },
    versions: (versions.rows ?? []).map((entry) => {
      const version = {
        version_no: Number(entry.version_no),
        file_name: entry.display_name,
        mime_type: entry.mime_type,
        size_bytes: Number(entry.size_bytes),
        sha256: entry.sha256 ?? null,
        note: entry.note ?? null,
        completed_at: toIso(entry.completed_at),
        is_current: Number(entry.version_no) === Number(row.cv_version_no),
      };
      if (!board) version.uploaded_by_name = entry.uploaded_by_name ?? null;
      return version;
    }),
  };
  if (!board) {
    const attached = await db.query(
      `
        SELECT a.id, a.status
        FROM announcement_attachments aa
        INNER JOIN announcements a ON a.id = aa.announcement_id
        WHERE aa.document_id = $1 AND a.site_code = $2
        ORDER BY a.id DESC
        LIMIT 50
      `,
      [id, siteCode],
    );
    detail.attached_announcements = (attached.rows ?? []).map((entry) => ({ id: Number(entry.id), status: entry.status }));
  }
  return detail;
}

const mapLabels = (value) => (Array.isArray(value) ? value.map(String) : []);

function parseDocumentId(raw) {
  const parsed = typeof raw === 'number' ? raw : /^\d{1,16}$/.test(String(raw ?? '').trim()) ? Number(String(raw).trim()) : NaN;
  if (!Number.isSafeInteger(parsed) || parsed <= 0) {
    throw documentNotFound();
  }
  return parsed;
}

function parseVersionNo(raw) {
  const parsed = typeof raw === 'number' ? raw : /^\d{1,9}$/.test(String(raw ?? '').trim()) ? Number(String(raw).trim()) : NaN;
  if (!Number.isSafeInteger(parsed) || parsed <= 0 || parsed > 2147483647) {
    throw versionNotFound();
  }
  return parsed;
}

export { parseDocumentId, parseVersionNo };

// ---------------------------------------------------------------------------
// Yazma: oluştur, yeni sürüm
// ---------------------------------------------------------------------------

function uploadInfo({ siteCode, documentId, versionNo, size, createdAt }, limits) {
  const created = createdAt instanceof Date ? createdAt : new Date(createdAt);
  return {
    method: 'PUT',
    path: `/manager/sites/${siteCode}/documents/${documentId}/versions/${versionNo}/content`,
    content_type: 'application/octet-stream',
    size: Number(size),
    max_bytes: limits.maxFileBytes,
    expires_at: new Date(created.getTime() + limits.uploadTtlMinutes * 60000).toISOString(),
  };
}

const versionBody = (row) => ({
  version_no: Number(row.version_no),
  file_name: row.display_name,
  mime_type: row.mime_type,
  size_bytes: Number(row.status === 'ready' ? row.size_bytes : row.declared_size_bytes),
  status: row.status,
});

/** Kota + sayı + bekleyen sınırı (aynı advisory kilidi altında çağrılır). */
async function assertCapacity(client, { siteCode, userCode, size, limits, excludeVersionId = null, newDocument = false }) {
  const usage = await readUsage(client, siteCode, excludeVersionId);
  if (newDocument && Number(usage.document_count) >= limits.maxPerSite) {
    throw documentLimitReached(limits.maxPerSite);
  }
  if (Number(usage.used_bytes) + size > limits.siteQuotaBytes) {
    throw quotaExceeded(usage.used_bytes, limits.siteQuotaBytes);
  }
  const pending = await client.query(
    `
      SELECT COUNT(*)::INTEGER AS n
      FROM document_versions
      WHERE uploaded_by = $1 AND status = 'uploading'
        AND created_at > NOW() - make_interval(mins => $2::INTEGER)
        AND ($3::BIGINT IS NULL OR id <> $3::BIGINT)
    `,
    [userCode, limits.uploadTtlMinutes, excludeVersionId],
  );
  if (Number(pending.rows?.[0]?.n ?? 0) >= limits.pendingPerUser) {
    throw pendingLimitReached();
  }
}

/**
 * POST documents -> { document (status 'pending'), version, upload }. Aynı (site, yazar, idempotency_key) -> aynı kayıt (çift satır yok).
 * Dosya burada ALINMAZ: yalnız doğrulama + kota rezervasyonu; bayt akışı PUT .../content ile gelir.
 */
export async function createDocument({ siteCode, actor, body, limits }) {
  const input = parseCreateInput(body, limits);
  const declared = classifyDeclaredFile({ name: input.file.name, contentType: input.file.contentType }, limits);
  await assertTargetBelongsToSite(pool, siteCode, input.target);

  const created = await withDocumentTransaction(siteCode, async (client) => {
    const userCode = await lockActiveUser(client, actor);
    await client.query('SELECT pg_advisory_xact_lock(hashtext($1))', [quotaLockKey(siteCode)]);

    const existing = await client.query(
      `SELECT id FROM documents WHERE site_code = $1 AND created_by = $2 AND idempotency_key = $3 LIMIT 1`,
      [siteCode, userCode, input.idempotencyKey],
    );
    if (existing.rows?.[0]) {
      return { id: Number(existing.rows[0].id), replay: true };
    }
    await assertCapacity(client, { siteCode, userCode, size: input.file.size, limits, newDocument: true });
    const inserted = await client.query(
      `
        INSERT INTO documents (
          site_code, category, title, description, audience, target_type, target_block_ids, target_apartment_ids,
          status, next_version_no, idempotency_key, created_by
        )
        VALUES ($1, $2, $3, $4, $5, $6, $7::BIGINT[], $8::BIGINT[], 'pending', 2, $9, $10)
        RETURNING id
      `,
      [
        siteCode,
        input.category,
        input.title,
        input.description,
        input.audience,
        input.target.type,
        input.target.blockIds,
        input.target.apartmentIds,
        input.idempotencyKey,
        userCode,
      ],
    );
    const id = Number(inserted.rows[0].id);
    await client.query(
      `
        INSERT INTO document_versions (
          document_id, site_code, version_no, status, storage_key, display_name, mime_type,
          declared_size_bytes, size_bytes, note, uploaded_by
        )
        VALUES ($1, $2, 1, 'uploading', $3, $4, $5, $6, $6, $7, $8)
      `,
      [id, siteCode, newStorageKey(siteCode), declared.displayName, declared.mimeType, input.file.size, input.note, userCode],
    );
    return { id, replay: false };
  });
  return buildCreateResponse(siteCode, created.id, limits);
}

/** 201 gövdesi: belge (pending ya da yeniden oynatmada active), son sürüm ve (varsa) yükleme tanımı. */
async function buildCreateResponse(siteCode, documentId, limits, versionNo = null, db = pool) {
  const document = await loadSummary(db, siteCode, documentId, limits);
  if (!document) {
    throw documentNotFound();
  }
  const versionRow = await db.query(
    `
      SELECT version_no, display_name, mime_type, declared_size_bytes, size_bytes, status, created_at
      FROM document_versions
      WHERE document_id = $1 AND site_code = $2 AND ($3::INTEGER IS NULL OR version_no = $3::INTEGER)
      ORDER BY version_no DESC
      LIMIT 1
    `,
    [documentId, siteCode, versionNo],
  );
  const version = versionRow.rows?.[0];
  if (!version) {
    throw documentNotFound();
  }
  const upload =
    version.status === 'uploading'
      ? uploadInfo({ siteCode, documentId, versionNo: version.version_no, size: version.declared_size_bytes, createdAt: version.created_at }, limits)
      : null;
  return { document, version: versionBody(version), upload };
}

/**
 * POST documents/:id/versions -> { version, upload } (belge `active` olmalı). Aynı belgede bekleyen (uploading) sürüm varsa YENİLENİR
 * (aynı sürüm numarası, yeni anahtar; eski dosya silinir).
 */
export async function addVersion({ siteCode, rawId, actor, body, limits }) {
  const id = parseDocumentId(rawId);
  const input = parseVersionInput(body, limits);
  const declared = classifyDeclaredFile({ name: input.file.name, contentType: input.file.contentType }, limits);

  const result = await withDocumentTransaction(siteCode, async (client) => {
    const userCode = await lockActiveUser(client, actor);
    await client.query('SELECT pg_advisory_xact_lock(hashtext($1))', [quotaLockKey(siteCode)]);
    const doc = await client.query(`SELECT id, status FROM documents WHERE id = $1 AND site_code = $2 FOR UPDATE`, [id, siteCode]);
    const row = doc.rows?.[0];
    if (!row) {
      throw documentNotFound();
    }
    if (row.status !== 'active') {
      throw invalidState('Yeni sürüm yalnızca yayındaki belgeye eklenebilir.');
    }
    const pendingVersion = await client.query(
      `SELECT id, version_no, storage_key FROM document_versions WHERE document_id = $1 AND status = 'uploading' ORDER BY version_no DESC FOR UPDATE`,
      [id],
    );
    const replacing = pendingVersion.rows?.[0] ?? null;
    const counts = await client.query(`SELECT COUNT(*)::INTEGER AS n FROM document_versions WHERE document_id = $1`, [id]);
    if (!replacing && Number(counts.rows?.[0]?.n ?? 0) >= limits.maxVersions) {
      throw versionLimitReached(limits.maxVersions);
    }
    await assertCapacity(client, { siteCode, userCode, size: input.file.size, limits, excludeVersionId: replacing ? Number(replacing.id) : null });
    const key = newStorageKey(siteCode);
    let versionNo;
    let staleKey = null;
    if (replacing) {
      versionNo = Number(replacing.version_no);
      staleKey = replacing.storage_key;
      await client.query(
        `
          UPDATE document_versions
          SET storage_key = $2, display_name = $3, mime_type = $4, declared_size_bytes = $5, size_bytes = $5, note = $6,
              uploaded_by = $7, created_at = NOW()
          WHERE id = $1
        `,
        [replacing.id, key, declared.displayName, declared.mimeType, input.file.size, input.note, userCode],
      );
      // fazlalık bekleyen sürümler (olmaması gerekir) temizlenir
      for (const extra of (pendingVersion.rows ?? []).slice(1)) {
        await client.query(`DELETE FROM document_versions WHERE id = $1`, [extra.id]);
      }
    } else {
      const next = await client.query(`UPDATE documents SET next_version_no = next_version_no + 1 WHERE id = $1 RETURNING next_version_no`, [id]);
      versionNo = Number(next.rows[0].next_version_no) - 1;
      await client.query(
        `
          INSERT INTO document_versions (
            document_id, site_code, version_no, status, storage_key, display_name, mime_type,
            declared_size_bytes, size_bytes, note, uploaded_by
          )
          VALUES ($1, $2, $3, 'uploading', $4, $5, $6, $7, $7, $8, $9)
        `,
        [id, siteCode, versionNo, key, declared.displayName, declared.mimeType, input.file.size, input.note, userCode],
      );
    }
    return { versionNo, staleKey };
  });
  if (result.staleKey) {
    try {
      await removeStoredFile(resolveStorageRoot().dir, result.staleKey);
    } catch (_error) {
      // dosya silinemediyse bakım işi yetim olarak süpürür
    }
  }
  const body2 = await buildCreateResponse(siteCode, id, limits, result.versionNo);
  return { version: body2.version, upload: body2.upload };
}

// ---------------------------------------------------------------------------
// Yükleme tamamlama
// ---------------------------------------------------------------------------

/**
 * PUT .../content için ön kontrol: sürüm `uploading` olmalı, yükleyen bu kullanıcı (ya da süper). Tamamlanmışsa 409 UPLOAD_ALREADY_COMPLETED + belge.
 * @returns {Promise<{ versionId: number, documentId: number, storageKey: string, declaredSize: number, displayName: string, mimeType: string, declared: boolean, kind: string }>}
 */
export async function findUploadTarget({ siteCode, rawId, rawVersionNo, actor, limits }, db = pool) {
  const id = parseDocumentId(rawId);
  const versionNo = parseVersionNo(rawVersionNo);
  const found = await db.query(
    `
      SELECT d.id AS document_id, d.status AS document_status, v.id AS version_id, v.status AS version_status, v.storage_key,
             v.declared_size_bytes, v.display_name, v.mime_type, v.uploaded_by,
             (v.created_at < NOW() - make_interval(mins => $4::INTEGER)) AS expired
      FROM documents d
      INNER JOIN document_versions v ON v.document_id = d.id AND v.version_no = $3
      WHERE d.id = $1 AND d.site_code = $2
      LIMIT 1
    `,
    [id, siteCode, versionNo, limits.uploadTtlMinutes],
  );
  const row = found.rows?.[0];
  if (!row) {
    throw versionNotFound();
  }
  if (row.document_status === 'deleted') {
    throw invalidState('Silinmiş belgeye dosya yüklenemez.');
  }
  if (row.version_status === 'ready') {
    const document = await loadSummary(db, siteCode, id, limits);
    throw uploadAlreadyCompleted({ document });
  }
  const userCode = actorFromAuthUser(actor).userCode;
  const isSuper = actor?.role === 'super_user';
  if (!isSuper && Number(row.uploaded_by) !== Number(userCode)) {
    throw versionNotFound();
  }
  // Yükleme tanımının süresi (expires_at = created_at + TTL) SUNUCUDA uygulanır (R16 P1-1): bakım işi bayat satırı silerken geç gelen PUT'un satırı `ready` yapması engellenir.
  if (row.expired === true) {
    throw uploadExpired();
  }
  const kindKey = Object.keys(KIND_INFO).find((key) => KIND_INFO[key].mime === row.mime_type) ?? 'pdf';
  return {
    versionId: Number(row.version_id),
    documentId: id,
    versionNo,
    storageKey: row.storage_key,
    declaredSize: Number(row.declared_size_bytes),
    displayName: row.display_name,
    mimeType: row.mime_type,
    declared: String(row.display_name).includes('.'),
    kind: kindKey,
  };
}

/**
 * Dosya diskte (son yolda) ve doğrulandı: sürümü `ready` yapar (tek işlem). İlk sürümse belge `active` olur ve `current_version_no` ona geçer.
 * Sürüm satırı artık yoksa (yenilendi / bakım süpürdü) ya da belge silindiyse hata fırlatır: çağıran son dosyayı siler.
 * @returns {Promise<{ document: object, warnings: object[] }>}
 */
export async function completeUpload({ siteCode, target, actor, size, sha256, kind, limits }) {
  const info = KIND_INFO[kind];
  const completed = await withDocumentTransaction(siteCode, async (client) => {
    await lockActiveUser(client, actor);
    const doc = await client.query(
      `SELECT id, status, category, audience, target_type FROM documents WHERE id = $1 AND site_code = $2 FOR UPDATE`,
      [target.documentId, siteCode],
    );
    const row = doc.rows?.[0];
    if (!row) {
      throw documentNotFound();
    }
    if (row.status === 'deleted') {
      throw invalidState('Silinmiş belgeye dosya yüklenemez.');
    }
    const version = await client.query(
      `SELECT id, status, storage_key, version_no, display_name, (created_at < NOW() - make_interval(mins => $3::INTEGER)) AS expired FROM document_versions WHERE id = $1 AND document_id = $2 FOR UPDATE`,
      [target.versionId, target.documentId, limits.uploadTtlMinutes],
    );
    const vrow = version.rows?.[0];
    if (!vrow || vrow.storage_key !== target.storageKey) {
      throw versionNotFound();
    }
    if (vrow.status === 'ready') {
      throw uploadAlreadyCompleted();
    }
    // satır kilidi altında süre denetimi: bakım işinin silmek üzere olduğu bayat satır `ready` OLAMAZ (bakım DELETE'i aynı satırı kilitler; kim önce gelirse)
    if (vrow.expired === true) {
      throw uploadExpired();
    }
    const baseName = String(vrow.display_name).includes('.')
      ? vrow.display_name
      : buildDisplayName(vrow.display_name, info.ext);
    await client.query(
      `
        UPDATE document_versions
        SET status = 'ready', size_bytes = $2, sha256 = $3, mime_type = $4, display_name = $5, completed_at = NOW()
        WHERE id = $1
      `,
      [vrow.id, size, sha256, info.mime, baseName],
    );
    const first = row.status === 'pending';
    await client.query(
      `
        UPDATE documents
        SET version_count = version_count + 1, current_version_no = $2, status = 'active', updated_at = NOW()
        WHERE id = $1
      `,
      [target.documentId, vrow.version_no],
    );
    await audit(client, actor, first ? 'document.created' : 'document.version_added', siteCode, target.documentId, {
      category: row.category,
      audience: row.audience,
      target_type: row.target_type,
      version_no: Number(vrow.version_no),
      size_bytes: Number(size),
      mime_type: info.mime,
    });
    const duplicate = await client.query(
      `SELECT 1 FROM document_versions WHERE site_code = $1 AND sha256 = $2 AND status = 'ready' AND id <> $3 LIMIT 1`,
      [siteCode, sha256, vrow.id],
    );
    return { warnings: duplicate.rows?.[0] ? [{ code: 'DUPLICATE_CONTENT' }] : [] };
  });
  const document = await loadSummary(pool, siteCode, target.documentId, limits);
  return { document, warnings: completed.warnings };
}

// ---------------------------------------------------------------------------
// Düzenleme, silme, geri alma, kalıcı silme, sürüm silme
// ---------------------------------------------------------------------------

const sameIds = (a, b) => a.length === b.length && a.every((value, index) => value === b[index]);

async function lockDocument(client, siteCode, id) {
  const found = await client.query(
    `
      SELECT id, status, category, audience, target_type, target_block_ids, target_apartment_ids, current_version_no, deleted_at
      FROM documents
      WHERE id = $1 AND site_code = $2
      FOR UPDATE
    `,
    [id, siteCode],
  );
  const row = found.rows?.[0];
  if (!row) {
    throw documentNotFound();
  }
  return row;
}

async function publishedAttachmentCount(client, documentId) {
  const result = await client.query(
    `
      SELECT COUNT(*)::INTEGER AS n
      FROM announcement_attachments aa
      INNER JOIN announcements a ON a.id = aa.announcement_id
      WHERE aa.document_id = $1 AND a.status = 'published'
    `,
    [documentId],
  );
  return Number(result.rows?.[0]?.n ?? 0);
}

/** PATCH documents/:id (dosya değişmez). Kitle değişikliği ANINDA geçerlidir. */
export async function updateDocument({ siteCode, rawId, actor, body, limits }) {
  const id = parseDocumentId(rawId);
  const patch = parsePatchInput(body);
  if (patch.target) {
    await assertTargetBelongsToSite(pool, siteCode, patch.target);
  }
  await withDocumentTransaction(siteCode, async (client) => {
    await lockActiveUser(client, actor);
    const row = await lockDocument(client, siteCode, id);
    if (row.status !== 'active') {
      throw invalidState('Yalnızca yayındaki belge düzenlenebilir.');
    }
    const sets = [];
    const values = [id, siteCode];
    const fields = [];
    const setField = (column, value, cast = '') => {
      values.push(value);
      sets.push(`${column} = $${values.length}${cast}`);
    };
    if (patch.title !== undefined) {
      setField('title', patch.title);
      fields.push('title');
    }
    if (patch.description !== undefined) {
      setField('description', patch.description);
      fields.push('description');
    }
    if (patch.category !== undefined && patch.category !== row.category) {
      setField('category', patch.category);
      fields.push('category');
    }
    const nextAudience = patch.audience ?? row.audience;
    let nextTarget;
    if (patch.target) {
      nextTarget = assertTargetMatchesAudience(nextAudience, patch.target);
    } else if (nextAudience !== 'residents') {
      nextTarget = { type: 'site', blockIds: [], apartmentIds: [] };
    } else {
      nextTarget = { type: row.target_type, blockIds: idArray(row.target_block_ids), apartmentIds: idArray(row.target_apartment_ids) };
    }
    const audienceChanged = nextAudience !== row.audience;
    const targetChanged =
      nextTarget.type !== row.target_type ||
      !sameIds(nextTarget.blockIds, idArray(row.target_block_ids)) ||
      !sameIds(nextTarget.apartmentIds, idArray(row.target_apartment_ids));
    const changes = { audience: audienceChanged ? { from: row.audience, to: nextAudience } : null, target: targetChanged ? { from: row.target_type, to: nextTarget.type } : null };
    let detached = [];
    if (audienceChanged) {
      setField('audience', nextAudience);
      fields.push('audience');
      if (row.audience === 'residents') {
        // Sakinlere açık olmaktan çıkan belge duyuru eki olarak kalamaz: yayındaki bir duyuruya ekliyse onay gerekir; taslak/zamanlanmışlardan çıkarılır.
        // Yayındaki duyurudaki bağ kalır (geçmiş) AMA ek yolu (resolveAnnouncementAttachmentDownload / loadAttachments) `audience = 'residents'` ister:
        // kitle değiştiği an ek indirilemez ve `available:false` olur (yeni sürümü de sızmaz).
        const published = await publishedAttachmentCount(client, id);
        if (published > 0 && !patch.confirm) {
          throw documentInUse(published);
        }
        const removed = await client.query(
          `
            DELETE FROM announcement_attachments aa
            USING announcements a
            WHERE aa.document_id = $1 AND a.id = aa.announcement_id AND a.status IN ('draft', 'scheduled')
            RETURNING aa.announcement_id
          `,
          [id],
        );
        detached = (removed.rows ?? []).map((entry) => Number(entry.announcement_id));
      }
    }
    if (targetChanged || audienceChanged) {
      setField('target_type', nextTarget.type);
      setField('target_block_ids', nextTarget.blockIds, '::BIGINT[]');
      setField('target_apartment_ids', nextTarget.apartmentIds, '::BIGINT[]');
      if (targetChanged) fields.push('target');
    }
    if (fields.length === 0) {
      return;
    }
    sets.push('updated_at = NOW()');
    await client.query(`UPDATE documents SET ${sets.join(', ')} WHERE id = $1 AND site_code = $2`, values);
    const details = { fields };
    if (changes.audience) details.audience = changes.audience;
    if (changes.target) details.target_type = changes.target;
    // başlık / açıklama DEĞERİ yazılmaz; yalnız alan adı (fields)
    await audit(client, actor, 'document.updated', siteCode, id, details);
    for (const announcementId of detached) {
      await audit(client, actor, 'document.detached', siteCode, id, { announcement_id: announcementId, auto: true, count: 1 });
    }
  });
  const document = await getDocumentDetail(siteCode, id, { kind: 'manager', limits });
  return { document };
}

/**
 * DELETE documents/:id -> yumuşak silme (status 'deleted'). Yayındaki bir duyuruya ekliyse `confirm !== true` iken 409 DOCUMENT_IN_USE.
 * `pending` (yüklemesi tamamlanmamış) belge İPTAL edilir: sürümleri ve dosyaları hemen kaldırılır.
 */
export async function deleteDocument({ siteCode, rawId, actor, body, limits }) {
  const id = parseDocumentId(rawId);
  const confirm = body && typeof body === 'object' && body.confirm === true;
  const outcome = await withDocumentTransaction(siteCode, async (client, tx) => {
    await lockActiveUser(client, actor);
    const row = await lockDocument(client, siteCode, id);
    if (row.status === 'deleted') {
      throw invalidState('Belge zaten silinmiş.');
    }
    if (row.status === 'pending') {
      const versions = await client.query(`SELECT storage_key FROM document_versions WHERE document_id = $1`, [id]);
      await client.query(`DELETE FROM documents WHERE id = $1`, [id]);
      tx.deferUnlink(versions.rows ?? []); // dosyalar COMMIT'ten SONRA silinir (R11 F7)
      return { cancelled: true };
    }
    const attachments = await publishedAttachmentCount(client, id);
    if (attachments > 0 && !confirm) {
      throw documentInUse(attachments);
    }
    await client.query(
      `UPDATE documents SET status = 'deleted', deleted_at = NOW(), deleted_by = $3, updated_at = NOW() WHERE id = $1 AND site_code = $2`,
      [id, siteCode, actorFromAuthUser(actor).userCode],
    );
    await audit(client, actor, 'document.deleted', siteCode, id, {
      category: row.category,
      audience: row.audience,
      attachments_count: attachments,
    });
    return { cancelled: false };
  });
  if (outcome.cancelled) {
    return { deleted: true, cancelled: true };
  }
  const document = await loadSummary(pool, siteCode, id, limits);
  return { document };
}

/** POST documents/:id/restore (deleted -> active; saklama süresi dolmuşsa 404). */
export async function restoreDocument({ siteCode, rawId, actor, limits }) {
  const id = parseDocumentId(rawId);
  await withDocumentTransaction(siteCode, async (client) => {
    await lockActiveUser(client, actor);
    const row = await lockDocument(client, siteCode, id);
    if (row.status !== 'deleted') {
      throw invalidState('Yalnızca silinmiş belge geri alınabilir.');
    }
    const expired = await client.query(
      `SELECT (deleted_at < NOW() - make_interval(days => $2::INTEGER)) AS expired FROM documents WHERE id = $1`,
      [id, limits.retentionDays],
    );
    if (expired.rows?.[0]?.expired === true) {
      throw documentNotFound();
    }
    const current = await client.query(
      `SELECT 1 FROM document_versions WHERE document_id = $1 AND version_no = $2 AND status = 'ready' LIMIT 1`,
      [id, row.current_version_no],
    );
    if (!current.rows?.[0]) {
      throw invalidState('Belgenin geri alınabilecek bir sürümü yok.');
    }
    await client.query(
      `UPDATE documents SET status = 'active', deleted_at = NULL, deleted_by = NULL, updated_at = NOW() WHERE id = $1 AND site_code = $2`,
      [id, siteCode],
    );
    await audit(client, actor, 'document.restored', siteCode, id, { category: row.category, audience: row.audience });
  });
  const document = await loadSummary(pool, siteCode, id, limits);
  return { document };
}

/**
 * Bir belgeyi KALICI siler (çağıran satırı kilitlemiş olmalı): satır (sürümler ve duyuru ekleri CASCADE) işlem içinde silinir, dosyalar `tx.deferUnlink` ile
 * COMMIT'ten SONRA silinir (R11 F7: işlem sonradan başarısız olursa satır dosyasız kalmasın). Dosya silinemezse satır zaten gitmiştir; dosya yetim kalır ve
 * bakım süpürmesi / fsck bulur (günlükte hata kodu). Bakım işi de bunu kullanır.
 * @param {object} client işlem istemcisi
 * @param {number} id belge kimliği
 * @param {{ deferUnlink: (rows: Array<{ storage_key: string }>) => void }} tx `withDocumentTransaction` geri çağrısının ikinci argümanı
 * @returns {Promise<{ versions: number, bytes: number }>}
 */
export async function purgeLockedDocument(client, id, tx) {
  const versions = await client.query(`SELECT storage_key, size_bytes FROM document_versions WHERE document_id = $1`, [id]);
  const rows = versions.rows ?? [];
  await client.query(`DELETE FROM documents WHERE id = $1`, [id]);
  tx.deferUnlink(rows);
  return { versions: rows.length, bytes: rows.reduce((sum, row) => sum + Number(row.size_bytes ?? 0), 0) };
}

/** POST documents/:id/purge gövde { confirm: true } (yalnız `deleted`). */
export async function purgeDocument({ siteCode, rawId, actor, body }) {
  const id = parseDocumentId(rawId);
  if (!(body && typeof body === 'object' && body.confirm === true)) {
    throw confirmRequired();
  }
  await withDocumentTransaction(siteCode, async (client, tx) => {
    await lockActiveUser(client, actor);
    const row = await lockDocument(client, siteCode, id);
    if (row.status !== 'deleted') {
      throw invalidState('Yalnızca silinmiş belge kalıcı olarak silinebilir.');
    }
    const removed = await purgeLockedDocument(client, id, tx);
    await audit(client, actor, 'document.purged', siteCode, id, {
      category: row.category,
      audience: row.audience,
      version_count: removed.versions,
      size_bytes: removed.bytes,
    });
  });
  return { purged: true };
}

/** DELETE documents/:id/versions/:no — en az bir `ready` sürüm kalmalı; güncel silinirse en yüksek kalan `ready` güncel olur; dosya COMMIT'ten hemen sonra silinir. */
export async function deleteVersion({ siteCode, rawId, rawVersionNo, actor, limits }) {
  const id = parseDocumentId(rawId);
  const versionNo = parseVersionNo(rawVersionNo);
  await withDocumentTransaction(siteCode, async (client, tx) => {
    await lockActiveUser(client, actor);
    const row = await lockDocument(client, siteCode, id);
    if (row.status === 'deleted') {
      throw invalidState('Silinmiş belgenin sürümü silinemez; önce geri alın.');
    }
    const found = await client.query(
      `SELECT id, status, storage_key, size_bytes FROM document_versions WHERE document_id = $1 AND version_no = $2 FOR UPDATE`,
      [id, versionNo],
    );
    const version = found.rows?.[0];
    if (!version) {
      throw versionNotFound();
    }
    if (version.status === 'ready') {
      const ready = await client.query(`SELECT version_no FROM document_versions WHERE document_id = $1 AND status = 'ready' AND version_no <> $2 ORDER BY version_no DESC`, [id, versionNo]);
      const remaining = ready.rows ?? [];
      if (remaining.length === 0) {
        throw invalidState('Belgenin en az bir sürümü kalmalıdır; belgenin tamamını silmek için belgeyi silin.');
      }
      await client.query(`DELETE FROM document_versions WHERE id = $1`, [version.id]);
      tx.deferUnlink([version]); // COMMIT'ten SONRA (R11 F7)
      const nextCurrent = Number(row.current_version_no) === versionNo ? Number(remaining[0].version_no) : Number(row.current_version_no);
      await client.query(
        `UPDATE documents SET version_count = $2, current_version_no = $3, updated_at = NOW() WHERE id = $1`,
        [id, remaining.length, nextCurrent],
      );
      await audit(client, actor, 'document.version_deleted', siteCode, id, {
        version_no: versionNo,
        size_bytes: Number(version.size_bytes),
        was_current: Number(row.current_version_no) === versionNo,
      });
      return;
    }
    // bekleyen (uploading) sürüm: yüklemeyi iptal eder
    await client.query(`DELETE FROM document_versions WHERE id = $1`, [version.id]);
    tx.deferUnlink([version]); // COMMIT'ten SONRA (R11 F7)
  });
  const document = await loadSummary(pool, siteCode, id, limits);
  return { document };
}

// ---------------------------------------------------------------------------
// İndirme çözümlemesi (yönetici / süper / kurul)
// ---------------------------------------------------------------------------

/**
 * GET documents/:id/download?version= -> indirilecek sürüm. Yönetici/süper: her sürüm ve silinmiş belge; kurul: yalnız görünürlük matrisindeki
 * GÜNCEL sürüm. `pending` belge indirilemez.
 * @returns {Promise<{ documentId: number, versionNo: number, storageKey: string, sizeBytes: number, displayName: string, mimeType: string, versionId: number }>}
 */
export async function resolveManagerDownload({ siteCode, rawId, versionNo, kind }, db = pool) {
  const id = parseDocumentId(rawId);
  const found = await db.query(
    `
      SELECT d.id, d.status, d.audience, d.current_version_no,
             v.id AS version_id, v.version_no, v.storage_key, v.size_bytes, v.display_name, v.mime_type
      FROM documents d
      INNER JOIN document_versions v ON v.document_id = d.id AND v.status = 'ready' AND v.version_no = COALESCE($3::INTEGER, d.current_version_no)
      WHERE d.id = $1 AND d.site_code = $2 AND d.status <> 'pending'
      LIMIT 1
    `,
    [id, siteCode, versionNo],
  );
  const row = found.rows?.[0];
  if (!row) {
    throw versionNo === null ? documentNotFound() : versionNotFound();
  }
  if (kind === 'board') {
    if (!boardVisible(row) || Number(row.version_no) !== Number(row.current_version_no)) {
      throw documentNotFound();
    }
  }
  return {
    documentId: id,
    versionId: Number(row.version_id),
    versionNo: Number(row.version_no),
    storageKey: row.storage_key,
    sizeBytes: Number(row.size_bytes),
    displayName: row.display_name,
    mimeType: row.mime_type,
  };
}
