// Gider belgesi eki (Faz 4b Ö3): iki adımlı yükleme (üstveri POST + ham gövde PUT), indirme ve bağlantı kaldırma.
//
// Sözleşme: docs/PLATFORM_FINANS_4B.md "Dış bağımlılık arayüzleri" + "Ö3 Belgeler" ve docs/PLATFORM_BELGELER.md A2-A4, A8. Depolama katmanı finance_documents_adapter.js
// arkasındadır: katman yoksa tüm ek uçları 409 DOCUMENTS_NOT_AVAILABLE döner ve gider kaydı ekten bağımsız çalışır.
//  - Dosya türü YALNIZ PDF / JPEG / PNG (içerik imzası katmanda doğrulanır); en çok 5 etkin belge / gider; aynı dosya (sha256) aynı gidere iki kez bağlanmaz.
//  - Gider belgeleri KALICI SİLİNMEZ (KMK m.36): kaldırma yalnız bağlantıyı keser (`removed_*`); dosya diskte kalır.
//  - Belge eklemek / kaldırmak DÖNEMDEN bağımsızdır (kapalı ayın gideri de belgelenebilir); audit'lidir. Kota hesabı `expense_documents`'i de kapsar.
//  - DİKKAT (AÇILIŞ KOŞULU): BELGELER bakım işi / yetim dosya süpürmesi (document_maintenance + fsck) HENÜZ `expense_documents.storage_key`'i bilinen dosya saymıyor; süpürme
//    `document_versions` ile `expense_documents` BİRLEŞİMİNİ (UNION) bilmeden bu uçlar AÇILMAMALIDIR (aksi halde ready gider belgeleri yetim sanılıp silinir). Katman yokken
//    (bugün) ek uçları kapalıdır (409 DOCUMENTS_NOT_AVAILABLE). KOTA için de aynı koşul: BELGELER kotası (document_service.js) `expense_documents.size_bytes`'i saymaz; kota ve
//    süpürme bu tabloyu bilmeden dikiş açılmaz (finans tarafı kendi toplamını `siteUsageBytes` ile ayrıca sınar).
//  - Günlüğe dosya adı / ad yazılmaz; yalnız kimlikler.
// KİLİT SIRASI: yükleme akışı DB işlemi DIŞINDA yapılır; DB adımı sites KEY SHARE -> finance_post -> users -> belge satırı.

import { pool } from '../db.js';
import { PlatformError } from './errors.js';
import { actorFromAuthUser } from './audit_service.js';
import {
  EXPENSE_DOCUMENT_LIMIT_PER_EXPENSE,
  documentNotFound,
  expenseDocumentLimit,
  expenseNotFound,
  objectOf,
  present,
} from './finance_4b_common.js';
import {
  EXPENSE_DOCUMENT_MIME_TYPES,
  UPLOAD_WINDOW_MS,
  downloadHeaders,
  maxFileBytes,
  requireDocumentSeam,
  reserveStorageKey,
  sanitizeDocumentName,
  siteQuotaBytes,
  streamOf,
} from './finance_documents_adapter.js';
import { idempotencyConflict, invalidBody, normalizeFreeText, parseIdempotencyKey } from './finance_common.js';
import { minorToNumber } from './finance_money.js';
import { lockActorRow, recordFinanceAudit, withFinanceTransaction } from './finance_tx.js';
import { parsePositiveId, toIso } from './people_common.js';

export const DOCUMENT_KINDS = Object.freeze(['invoice', 'receipt', 'photo', 'other']);

const err = (status, code, message, extra) => new PlatformError(status, code, message, extra);
const quotaExceeded = () => err(409, 'DOCUMENT_QUOTA_EXCEEDED', 'Site belge alanı doldu. Eski belgeleri kalıcı olarak silin.');
const tooLarge = () => err(413, 'DOCUMENT_TOO_LARGE', 'Dosya çok büyük.');
const sizeMismatch = () => err(400, 'DOCUMENT_SIZE_MISMATCH', 'Dosya boyutu bildirilen boyutla uyuşmuyor.');
const lengthRequired = () => err(411, 'LENGTH_REQUIRED', 'İçerik uzunluğu (Content-Length) zorunludur.');
const alreadyCompleted = (document) => err(409, 'UPLOAD_ALREADY_COMPLETED', 'Bu yükleme zaten tamamlanmış.', { document });
const uploadExpired = () => err(409, 'UPLOAD_EXPIRED', 'Yükleme süresi doldu. Belgeyi yeniden ekleyin.');
const duplicateContent = () => err(409, 'DUPLICATE_DOCUMENT', 'Bu dosya bu gidere zaten eklenmiş.');

export function mapDocumentRow(row) {
  return {
    id: Number(row.id),
    expense_id: Number(row.expense_id),
    status: row.status,
    kind: row.kind,
    display_name: row.display_name,
    mime_type: row.mime_type,
    size_bytes: minorToNumber(row.size_bytes),
    sha256: row.sha256 ?? null,
    added_at: toIso(row.added_at),
    completed_at: toIso(row.completed_at),
  };
}

const DOCUMENT_SELECT = `
  SELECT d.id, d.expense_id, d.status, d.kind, d.display_name, d.mime_type, d.declared_size_bytes::TEXT AS declared_size_bytes, d.size_bytes::TEXT AS size_bytes, d.sha256, d.storage_key,
         d.added_by, d.added_at, d.completed_at, d.removed_at, d.idempotency_key
  FROM expense_documents d
`;

async function loadDocument(db, siteCode, expenseId, documentId) {
  const result = await db.query(`${DOCUMENT_SELECT} WHERE d.id = $1 AND d.expense_id = $2 AND d.site_code = $3`, [documentId, expenseId, siteCode]);
  return result.rows?.[0] ?? null;
}

/** Sitenin kullandığı alan: gider belgeleri (kaldırılanlar dahil: dosya diskte kalır) + (varsa) Belgeler modülü sürümleri. */
export async function siteUsageBytes(db, siteCode) {
  const expense = await db.query(`SELECT COALESCE(SUM(size_bytes), 0)::TEXT AS used FROM expense_documents WHERE site_code = $1`, [siteCode]);
  let used = BigInt(expense.rows[0].used);
  const versions = await db.query(`SELECT to_regclass('public.document_versions') IS NOT NULL AS present`);
  if (versions.rows[0].present === true) {
    const result = await db.query(`SELECT COALESCE(SUM(size_bytes), 0)::TEXT AS used FROM document_versions WHERE site_code = $1`, [siteCode]);
    used += BigInt(result.rows[0].used);
  }
  return used;
}

export function parseDocumentCreate(body, seam) {
  const input = objectOf(body);
  const file = objectOf(input.file);
  const size = file.size;
  if (typeof size !== 'number' || !Number.isSafeInteger(size) || size <= 0) {
    throw invalidBody('Dosya boyutu geçersiz.');
  }
  if (size > maxFileBytes(seam)) {
    throw tooLarge();
  }
  const { displayName, declaredMime } = sanitizeDocumentName(file.name);
  if (!DOCUMENT_KINDS.includes(input.kind)) {
    throw invalidBody('Belge türü geçersiz.');
  }
  const contentType = typeof file.content_type === 'string' ? file.content_type.trim().toLowerCase() : null;
  const guess = declaredMime ?? (EXPENSE_DOCUMENT_MIME_TYPES.includes(contentType) ? contentType : 'application/pdf');
  return { displayName, mime: guess, size, kind: input.kind, idempotencyKey: parseIdempotencyKey(input.idempotency_key, { required: true }) };
}

const uploadDescriptor = (siteCode, expenseId, document, seam) => ({
  method: 'PUT',
  path: `/manager/sites/${siteCode}/finance/expenses/${expenseId}/documents/${document.id}/content`,
  content_type: 'application/octet-stream',
  size: document.size_bytes,
  max_bytes: maxFileBytes(seam),
  expires_at: new Date(new Date(document.added_at).getTime() + UPLOAD_WINDOW_MS).toISOString(),
});

/** POST expenses/:id/documents -> { replayed, document, upload }. */
export async function createExpenseDocument({ siteCode, rawExpenseId, body, actor }) {
  const expenseId = parsePositiveId(rawExpenseId);
  if (expenseId === null) {
    throw expenseNotFound();
  }
  const seam = await requireDocumentSeam();
  const input = parseDocumentCreate(body, seam);
  const actorInfo = actorFromAuthUser(actor);
  return withFinanceTransaction(siteCode, async (client) => {
    await lockActorRow(client, actorInfo);
    const expense = await client.query(`SELECT id FROM expenses WHERE id = $1 AND site_code = $2 FOR KEY SHARE`, [expenseId, siteCode]);
    if (!expense.rows?.[0]) {
      throw expenseNotFound();
    }
    const existing = await client.query(`${DOCUMENT_SELECT} WHERE d.site_code = $1 AND d.expense_id = $2 AND d.idempotency_key = $3`, [siteCode, expenseId, input.idempotencyKey]);
    if (existing.rows?.[0]) {
      const row = existing.rows[0];
      if (row.display_name !== input.displayName || BigInt(row.declared_size_bytes) !== BigInt(input.size) || row.kind !== input.kind) {
        throw idempotencyConflict();
      }
      const document = mapDocumentRow(row);
      return { replayed: true, document, upload: row.status === 'uploading' ? uploadDescriptor(siteCode, expenseId, document, seam) : null };
    }
    const count = await client.query(`SELECT COUNT(*)::INTEGER AS n FROM expense_documents WHERE expense_id = $1 AND removed_at IS NULL`, [expenseId]);
    if (Number(count.rows[0].n) >= EXPENSE_DOCUMENT_LIMIT_PER_EXPENSE) {
      throw expenseDocumentLimit();
    }
    if ((await siteUsageBytes(client, siteCode)) + BigInt(input.size) > BigInt(siteQuotaBytes())) {
      throw quotaExceeded();
    }
    const inserted = await client.query(
      `
        INSERT INTO expense_documents (site_code, expense_id, storage_key, display_name, mime_type, declared_size_bytes, size_bytes, kind, idempotency_key, added_by)
        VALUES ($1, $2, $3, $4, $5, $6::BIGINT, $6::BIGINT, $7, $8, $9)
        RETURNING id
      `,
      [siteCode, expenseId, reserveStorageKey(siteCode), input.displayName, input.mime, String(input.size), input.kind, input.idempotencyKey, actorInfo.userCode],
    );
    const document = mapDocumentRow(await loadDocument(client, siteCode, expenseId, Number(inserted.rows[0].id)));
    return { replayed: false, document, upload: uploadDescriptor(siteCode, expenseId, document, seam) };
  });
}

/**
 * PUT expenses/:id/documents/:docId/content (ham gövde, Content-Length ZORUNLU ve = bildirilen boyut) -> { document }.
 * Akış DB işlemi dışında yapılır; sonra tek işlemde `uploading -> ready`. DB adımı başarısızsa yazılan dosya geri alınır.
 */
export async function uploadExpenseDocumentContent({ siteCode, rawExpenseId, rawDocumentId, req, actor }) {
  const expenseId = parsePositiveId(rawExpenseId);
  const documentId = parsePositiveId(rawDocumentId);
  if (expenseId === null) {
    throw expenseNotFound();
  }
  if (documentId === null) {
    throw documentNotFound();
  }
  const seam = await requireDocumentSeam();
  const actorInfo = actorFromAuthUser(actor);
  const row = await loadDocument(pool, siteCode, expenseId, documentId);
  if (!row || row.removed_at) {
    throw documentNotFound();
  }
  if (row.status !== 'uploading') {
    throw alreadyCompleted(mapDocumentRow(row));
  }
  if (actor?.role !== 'super_user' && Number(row.added_by) !== actorInfo.userCode) {
    throw documentNotFound();
  }
  if (Date.now() - new Date(row.added_at).getTime() > UPLOAD_WINDOW_MS) {
    throw uploadExpired();
  }
  const lengthHeader = req.headers?.['content-length'];
  if (lengthHeader === undefined || !/^\d+$/.test(String(lengthHeader))) {
    throw lengthRequired();
  }
  const declaredSize = Number(row.declared_size_bytes);
  if (Number(lengthHeader) !== declaredSize) {
    throw sizeMismatch();
  }
  const stored = await seam.storeUpload({
    siteCode,
    req,
    declaredSize,
    allowedMimeTypes: [...EXPENSE_DOCUMENT_MIME_TYPES],
    maxBytes: maxFileBytes(seam),
  });
  const cleanup = async () => {
    try {
      await seam.removeFile(siteCode, stored.storageKey);
    } catch (_error) {
      // Dosya silinemediyse yetim kalir. BELGELER yetim-dosya süpürmesi bunu toplar AMA süpürme `expense_documents.storage_key`'i de BILINEN dosya saymalidir
      // (document_versions UNION expense_documents); aksi halde HAZIR gider belgelerini de yetim sanip siler. Bu S-3b / BELGELER bakim isinin sorumlulugudur
      // (dikis acilmadan once sart; bkz. finance_documents_adapter.js basligi). Asil hata yukari firlatilir.
    }
  };
  try {
    if (!EXPENSE_DOCUMENT_MIME_TYPES.includes(stored.mimeType)) {
      throw err(415, 'DOCUMENT_TYPE_NOT_ALLOWED', 'Bu dosya türü desteklenmiyor. PDF, JPG veya PNG yükleyin.');
    }
    return await withFinanceTransaction(siteCode, async (client) => {
      await lockActorRow(client, actorInfo);
      const current = await client.query(`SELECT status, removed_at FROM expense_documents WHERE id = $1 AND expense_id = $2 AND site_code = $3 FOR UPDATE`, [documentId, expenseId, siteCode]);
      if (!current.rows?.[0] || current.rows[0].removed_at) {
        throw documentNotFound();
      }
      if (current.rows[0].status !== 'uploading') {
        throw alreadyCompleted(mapDocumentRow(await loadDocument(client, siteCode, expenseId, documentId)));
      }
      try {
        await client.query(
          `
            UPDATE expense_documents
            SET status = 'ready', storage_key = $4, size_bytes = $5::BIGINT, sha256 = $6, mime_type = $7, completed_at = NOW()
            WHERE id = $1 AND expense_id = $2 AND site_code = $3 AND status = 'uploading'
          `,
          [documentId, expenseId, siteCode, stored.storageKey, String(stored.sizeBytes), stored.sha256, stored.mimeType],
        );
      } catch (error) {
        if (error?.code === '23505') {
          throw duplicateContent();
        }
        throw error;
      }
      await recordFinanceAudit(client, actor, 'finance.expense.document_attached', siteCode, documentId, {
        expense_id: expenseId,
        kind: row.kind,
        size_bytes: stored.sizeBytes,
        mime_type: stored.mimeType,
      });
      return { document: mapDocumentRow(await loadDocument(client, siteCode, expenseId, documentId)) };
    });
  } catch (error) {
    await cleanup();
    throw error;
  }
}

/** GET expenses/:id/documents/:docId/download: A8 başlıklarıyla akış. Hata: PlatformError; akış başladıktan sonra hata bağlantıyı keser. */
export async function streamExpenseDocument({ siteCode, rawExpenseId, rawDocumentId, res, userCode = null }) {
  const expenseId = parsePositiveId(rawExpenseId);
  const documentId = parsePositiveId(rawDocumentId);
  if (expenseId === null) {
    throw expenseNotFound();
  }
  if (documentId === null) {
    throw documentNotFound();
  }
  const seam = await requireDocumentSeam();
  const row = await loadDocument(pool, siteCode, expenseId, documentId);
  if (!row || row.removed_at || row.status !== 'ready') {
    throw documentNotFound();
  }
  let opened;
  try {
    opened = await seam.openDownload(siteCode, row.storage_key, Number(row.size_bytes));
  } catch (error) {
    if (error instanceof PlatformError) {
      throw error;
    }
    // eslint-disable-next-line no-console
    console.error(`[finance] expense document file missing doc=${documentId}`);
    throw err(500, 'DOCUMENT_FILE_MISSING', 'Belge dosyasına ulaşılamadı. Yöneticiyle iletişime geçin.');
  }
  const stream = streamOf(opened);
  // eslint-disable-next-line no-console
  console.log(`[finance] expense document download doc=${documentId} user=${userCode ?? 'unknown'}`);
  res.status(200);
  for (const [name, value] of Object.entries(downloadHeaders({ mimeType: row.mime_type, sizeBytes: Number(row.size_bytes), displayName: row.display_name }))) {
    res.setHeader(name, value);
  }
  await new Promise((resolve) => {
    stream.on('error', () => {
      res.destroy();
      resolve();
    });
    res.on('close', () => {
      stream.destroy();
      resolve();
    });
    res.on('finish', resolve);
    stream.pipe(res);
  });
}

/** DELETE expenses/:id/documents/:docId { reason } -> { document }. Yalnız BAĞLANTIYI keser (KMK m.36: dosya diskte kalır). */
export async function removeExpenseDocument({ siteCode, rawExpenseId, rawDocumentId, body, actor }) {
  const expenseId = parsePositiveId(rawExpenseId);
  const documentId = parsePositiveId(rawDocumentId);
  if (expenseId === null) {
    throw expenseNotFound();
  }
  if (documentId === null) {
    throw documentNotFound();
  }
  const reason = normalizeFreeText(objectOf(body).reason, { label: 'Neden', max: 200, required: true });
  const actorInfo = actorFromAuthUser(actor);
  return withFinanceTransaction(siteCode, async (client) => {
    await lockActorRow(client, actorInfo);
    const row = await loadDocument(client, siteCode, expenseId, documentId);
    if (!row || row.removed_at) {
      throw documentNotFound();
    }
    await client.query(
      `UPDATE expense_documents SET removed_at = NOW(), removed_by = $4, removal_reason = $5 WHERE id = $1 AND expense_id = $2 AND site_code = $3 AND removed_at IS NULL`,
      [documentId, expenseId, siteCode, actorInfo.userCode, reason],
    );
    await recordFinanceAudit(client, actor, 'finance.expense.document_removed', siteCode, documentId, { expense_id: expenseId });
    return { document: mapDocumentRow(await loadDocument(client, siteCode, expenseId, documentId)) };
  });
}

void present;
