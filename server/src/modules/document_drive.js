// Dosya Deposu YALNIZ-DRIVE modeli (2026-10-29): belge dosyaları sitenin Google Drive'ında saklanır; sunucu diski yalnız anlık aktarım tamponudur.
//  - Drive bağlı olmayan site dosya YÜKLEYEMEZ (409 DRIVE_REQUIRED); eski sunucu belgeleri okunur kalır (server_copy = TRUE).
//  - Yeni sürüm: gövde geçici dosyaya alınır, doğrulanır, driveService.upload ile (SHA-256 doğrulamalı, kuyruklu) Drive'a gider; geçici dosya Drive kabulünden sonra silinir.
//  - Sürüm durumu (storage, document_common.storageState): 'drive' (Drive kaydı TEYİTLİ) | 'server' (eski sunucu kopyası, okunabilir) | 'transferring' (aktarılıyor, açılamaz).
// Sütunlar: document_versions.drive_file_id (drive_files.id), document_versions.server_copy (sunucu diskinde kopya var mı). Bkz. migrations/116.

import { pool } from '../db.js';
import { PlatformError } from './errors.js';

export const driveRequired = () =>
  new PlatformError(409, 'DRIVE_REQUIRED', "Dosya yüklemek için önce Google Drive'ı bağlayın.");
export const documentTransferring = () =>
  new PlatformError(409, 'DOCUMENT_TRANSFERRING', "Dosya Google Drive'a aktarılıyor. Aktarım bitince açılabilir.");

/** Sitenin Drive bağlantısı 'connected' değilse 409 DRIVE_REQUIRED. */
export async function assertDriveConnected(siteCode, db = pool) {
  const found = await db.query(`SELECT status FROM site_drive_connections WHERE site_code = $1`, [siteCode]);
  if (found.rows?.[0]?.status !== 'connected') {
    throw driveRequired();
  }
}
