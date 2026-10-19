// Belgeler (Faz 3b-A): bakım işi — saatte bir, süreçler arası TEK çalışan (session advisory kilidi), hata sunucuyu düşürmez, günlükte yalnız sayılar/kodlar.
//
// Sözleşme: docs/PLATFORM_BELGELER.md A8. Turlar:
//  (1) 2 saati aşan `uploading` sürümleri ve `_tmp` dosyaları siler; sürümsüz `pending` belgeleri kaldırır. Bayat sürümde ÖNCE SATIR (`DELETE ... RETURNING`, süre koşulu
//      tekrar sınanır), satır silindiyse SONRA dosya: geç gelen PUT satırı `ready` yaptıysa dosyaya dokunulmaz (R16 P1-1).
//  (2) `deleted_at` + DOCUMENTS_RETENTION_DAYS geçen belgeleri KALICI siler: satır işlemde silinir, dosyalar COMMIT SONRASI `unlink` edilir (R11 F7); dosya silinemezse
//      satır gitmiştir, dosya yetim kalır (hata sayılır).
//  (3) Yetim dosya süpürmesi: diskte olup DB'de (document_versions ∪ expense_documents) olmayan ve 24 saatten eski dosyalar, tur başına en çok 200, `_orphans/` KARANTİNASINA
//      taşınır (SİLİNMEZ; DOCUMENTS_ORPHAN_QUARANTINE_DAYS, varsayılan 14 gün sonra silinir; R16 P2-4). DB'ye ulaşılamıyorsa HİÇ dokunmaz.
//  (4) Silinmiş siteler için `sites/<kod>` dizinleri 7 gün sonra silinir.
//  (5) Karantinada süresi dolan dosyalar silinir.
// (3) ve (4) DİSKTEN-GELEN işlemlerdir: depolama kimliği (document_integrity.js) eşleşmiyorsa ya da oran koruması tetiklenirse (yanlış/boş DB belirtisi) YAPILMAZ.
// Denetim kaydı: `actor: Sistem`, `details.auto: true`.

import { promises as fsp } from 'node:fs';
import path from 'node:path';
import { pool } from '../db.js';
import { recordAudit } from './audit_service.js';
import { documentLimits } from './document_common.js';
import { SYSTEM_ACTOR, purgeLockedDocument, withDocumentTransaction } from './document_service.js';
import { SITE_DIR_PATTERN, UUID_PATTERN, checkStorage, isInside, purgeQuarantine, quarantineStoredFile, removeStoredFile } from './document_storage.js';
import { ensureStorageIdentity, loadKnownKeys, orphanGuardTripped, siteDirGuardTripped, siteHasRecords } from './document_integrity.js';
import { ATTACHMENT_SUBTREE, ATTACHMENT_UPLOAD_TTL_MINUTES, attachmentLimits } from './work_attachments_common.js';

/** "DOCS" (0x444F4353): süreçler arası tek çalışan için session advisory kilidinin birinci anahtarı; ikincisi 1. */
export const MAINTENANCE_LOCK = Object.freeze([0x444f4353, 1]);

const HOUR_MS = 60 * 60 * 1000;
const DAY_MS = 24 * HOUR_MS;
const ORPHAN_MIN_AGE_MS = DAY_MS;
const SITE_DIR_MIN_AGE_MS = 7 * DAY_MS;
const TEMP_MAX_AGE_MS = 2 * HOUR_MS;
export const BATCH_LIMIT = 200;
const SCAN_ENTRY_CAP = 200_000;

const emptySummary = () => ({
  stale_uploads: 0,
  pending_documents: 0,
  temp_files: 0,
  purged_documents: 0,
  orphan_files: 0, // karantinaya alınan yetim dosya sayısı
  quarantine_purged: 0,
  site_dirs: 0,
  guard_trips: 0,
  identity_blocked: 0,
  // İş takibi fotoğraf ekleri (047; `work_attachments/` alt ağacı): bayat `uploading` satır + dosyası; DB'de satırı olmayan dosya (SİLİNİR, karantina yok); silinmiş site dizini.
  attachment_stale_uploads: 0,
  attachment_orphans: 0,
  attachment_site_dirs: 0,
  errors: 0,
});

async function safe(summary, label, work) {
  try {
    await work();
  } catch (error) {
    summary.errors += 1;
    // eslint-disable-next-line no-console
    console.error(`[documents] bakim adimi basarisiz (${label}):`, error?.code || error?.name || 'error');
  }
}

/** (1) bayat yüklemeler + sürümsüz pending belgeler. */
async function cleanStaleUploads(root, limits, summary, db) {
  const stale = await db.query(
    `
      SELECT id, document_id, storage_key
      FROM document_versions
      WHERE status = 'uploading' AND created_at < NOW() - make_interval(mins => $1::INTEGER)
      ORDER BY created_at
      LIMIT $2
    `,
    [limits.uploadTtlMinutes, BATCH_LIMIT],
  );
  for (const row of stale.rows ?? []) {
    try {
      // R16 P1-1: ÖNCE SATIR, sonra dosya. Seçim ile silme arasında geç gelen bir PUT satırı `ready` yapmış olabilir (completeUpload satırı FOR UPDATE ile kilitler ve
      // süreyi yeniden denetler): `status = 'uploading'` + süre koşulu DELETE'te TEKRAR sınanır; satır silinmediyse DOSYAYA DOKUNULMAZ (ready sürümün dosyası silinmez).
      const removed = await db.query(
        `DELETE FROM document_versions WHERE id = $1 AND status = 'uploading' AND created_at < NOW() - make_interval(mins => $2::INTEGER) RETURNING storage_key`,
        [row.id, limits.uploadTtlMinutes],
      );
      if (Number(removed.rowCount ?? removed.rows?.length ?? 0) === 0) continue;
      summary.stale_uploads += 1;
      await removeStoredFile(root, removed.rows?.[0]?.storage_key ?? row.storage_key);
    } catch (error) {
      summary.errors += 1;
      // eslint-disable-next-line no-console
      console.error('[documents] bayat yukleme temizlenemedi:', error?.code || 'error');
    }
  }
  const pending = await db.query(
    `
      DELETE FROM documents d
      WHERE d.status = 'pending' AND d.created_at < NOW() - make_interval(mins => $1::INTEGER)
        AND NOT EXISTS (SELECT 1 FROM document_versions v WHERE v.document_id = d.id)
    `,
    [limits.uploadTtlMinutes],
  );
  summary.pending_documents += Number(pending.rowCount ?? 0);
}

/** `_tmp` içinde 2 saatten eski kalıntılar. */
async function cleanTempFiles(root, summary, now) {
  const dir = path.join(root, '_tmp');
  let entries;
  try {
    entries = await fsp.readdir(dir, { withFileTypes: true });
  } catch (_error) {
    return;
  }
  for (const entry of entries.slice(0, SCAN_ENTRY_CAP)) {
    if (!entry.isFile() || !entry.name.endsWith('.part') || !UUID_PATTERN.test(entry.name.slice(0, -5))) continue;
    try {
      const full = path.join(dir, entry.name);
      const info = await fsp.lstat(full);
      if (now - info.mtimeMs > TEMP_MAX_AGE_MS) {
        await fsp.unlink(full);
        summary.temp_files += 1;
      }
    } catch (_error) {
      // dosya o arada kaldırılmış / kilitli olabilir
    }
  }
}

/** (2) saklama süresi dolan silinmiş belgeleri KALICI siler (satır başına kendi işlemi; kilitliyse atlanır). */
async function purgeExpired(limits, summary, db) {
  const expired = await db.query(
    `
      SELECT id, site_code
      FROM documents
      WHERE status = 'deleted' AND deleted_at < NOW() - make_interval(days => $1::INTEGER)
      ORDER BY deleted_at
      LIMIT 100
    `,
    [limits.retentionDays],
  );
  for (const row of expired.rows ?? []) {
    try {
      const purged = await withDocumentTransaction(
        Number(row.site_code),
        async (client, tx) => {
          const locked = await client.query(
            `SELECT id, category, audience FROM documents WHERE id = $1 AND status = 'deleted' AND deleted_at < NOW() - make_interval(days => $2::INTEGER) FOR UPDATE SKIP LOCKED`,
            [row.id, limits.retentionDays],
          );
          if (!locked.rows?.[0]) return false;
          // satır işlemde silinir, dosyalar COMMIT'ten SONRA (R11 F7); dosya silinemezse satır gitmiştir, dosya yetim süpürmesine kalır (errors sayılır)
          const removed = await purgeLockedDocument(client, Number(row.id), tx);
          await recordAudit(
            client,
            {
              actor: SYSTEM_ACTOR,
              action: 'document.purged',
              siteCode: Number(row.site_code),
              targetType: 'document',
              targetId: String(row.id),
              details: { auto: true, category: locked.rows[0].category, audience: locked.rows[0].audience, version_count: removed.versions, size_bytes: removed.bytes },
            },
            { inTransaction: true },
          );
          return true;
        },
        {
          onUnlinkFailure: () => {
            summary.errors += 1;
          },
        },
      );
      if (purged) summary.purged_documents += 1; // sayaç YALNIZ kesinleşen (COMMIT edilen) silmeler için
    } catch (error) {
      summary.errors += 1;
      // eslint-disable-next-line no-console
      console.error('[documents] sure dolan belge kalici silinemedi:', error?.code || 'error');
    }
  }
}

async function listSiteDirs(root, subtree = 'sites') {
  try {
    return (await fsp.readdir(path.join(root, subtree), { withFileTypes: true })).filter((entry) => entry.isDirectory() && SITE_DIR_PATTERN.test(entry.name));
  } catch (_error) {
    return [];
  }
}

// --- İş takibi fotoğraf ekleri (047): `work_attachments/<site>/<uuid>` alt ağacı --------------------------------------------------------------------
// Belge turlarının aynası, farklarla: (a) yetim dosya KARANTİNAYA ALINMAZ, silinir; bunun yerine yaş eşiği uzundur: WORK_ATTACHMENTS_ORPHAN_MIN_AGE_DAYS (30 gün;
// eski bir DB dökümü geri yüklenirse satırı kaybolmuş fotoğraflar bu sürede yerinde kalır ve fark edilebilir); (b) bilinen anahtar kümesi yalnız work_item_attachments'tır;
// (c) silinmiş site dizini oran koruması seyrek alt ağaca göredir (aşağıda). Tablo yoksa (047 kurulmamış) HİÇBİR adım çalışmaz (aksi hâlde her dosya yetim görünürdü).

/** Fotoğraf site dizini kaldırma koruması: kaldırılacak > 5 VE tüm fotoğraf site dizinlerinin %50'sinden fazlası ise dur; DB'de HİÇ site yoksa her zaman dur. */
export const ATTACHMENT_SITE_DIR_GUARD_MIN = 5;

/**
 * Seyrek alt ağaç (WA-SITEDIR-GUARD-SPARSE-SUBTREE): fotoğraf dizini yalnız fotoğraf eklenmiş sitelerde vardır; 3 dizinden 2'sinin silinmiş siteye ait olması
 * olağandır. Belgelerin ">= 2 ve > %50" kuralı burada gereksiz durdururdu: eşik > 5 dizin. Boş DB (siteCount 0) her zaman durdurur; depolama kimliği kapısı ayrıca geçerlidir.
 */
export function attachmentSiteDirGuardTripped({ removable, totalDirs, siteCount }) {
  if (removable <= 0) return false;
  if (siteCount === 0) return true;
  return removable > ATTACHMENT_SITE_DIR_GUARD_MIN && removable / Math.max(1, totalDirs) > 0.5;
}

async function attachmentsTablePresent(db) {
  const result = await db.query(`SELECT to_regclass('public.work_item_attachments') IS NOT NULL AS present`);
  return result.rows?.[0]?.present === true;
}

/** (1a) 2 saati aşan `uploading` ek kayıtları: ÖNCE SATIR (süre koşulu DELETE'te tekrar sınanır), silindiyse SONRA dosya (geç gelen PUT `ready` yaptıysa dokunulmaz). */
async function cleanStaleAttachmentUploads(root, summary, db) {
  if (!(await attachmentsTablePresent(db))) return;
  const stale = await db.query(
    `
      SELECT id, storage_key
      FROM work_item_attachments
      WHERE status = 'uploading' AND created_at < NOW() - make_interval(mins => $1::INTEGER)
      ORDER BY created_at
      LIMIT $2
    `,
    [ATTACHMENT_UPLOAD_TTL_MINUTES, BATCH_LIMIT],
  );
  for (const row of stale.rows ?? []) {
    try {
      const removed = await db.query(
        `DELETE FROM work_item_attachments WHERE id = $1 AND status = 'uploading' AND created_at < NOW() - make_interval(mins => $2::INTEGER) RETURNING storage_key`,
        [row.id, ATTACHMENT_UPLOAD_TTL_MINUTES],
      );
      if (Number(removed.rowCount ?? removed.rows?.length ?? 0) === 0) continue;
      summary.attachment_stale_uploads += 1;
      const key = removed.rows?.[0]?.storage_key ?? row.storage_key;
      if (key) await removeStoredFile(root, key, ATTACHMENT_SUBTREE);
    } catch (error) {
      summary.errors += 1;
      // eslint-disable-next-line no-console
      console.error('[work_tracking] bayat fotograf yuklemesi temizlenemedi:', error?.code || 'error');
    }
  }
}

/** Verilen anahtarlardan work_item_attachments'ta KAYITLI olanlar. Sorgu hatası fırlar: çağıran HİÇBİR dosya silmez. */
async function loadKnownAttachmentKeys(db, keys) {
  const known = new Set();
  if (keys.length === 0) return known;
  const rows = await db.query(`SELECT storage_key FROM work_item_attachments WHERE storage_key = ANY($1::TEXT[])`, [keys]);
  for (const row of rows.rows ?? []) known.add(row.storage_key);
  return known;
}

/**
 * (3a) `work_attachments/<site>/` altında DB'de satırı olmayan ve WORK_ATTACHMENTS_ORPHAN_MIN_AGE_DAYS'ten (30 gün) eski dosyalar SİLİNİR (tur başına <= 200; yalnız DB'de
 * var olan sitelerin dizinleri; silinmiş sitelerin dizinlerini (4a) ele alır). DB sorgusu başarısızsa hiçbiri silinmez. ORAN KORUMASI belgelerle aynı (yetim > 20 ve > %50 -> dur).
 */
async function sweepAttachmentOrphans(root, summary, db, now, env) {
  const minAgeMs = attachmentLimits(env).orphanMinAgeDays * DAY_MS;
  const siteDirs = await listSiteDirs(root, ATTACHMENT_SUBTREE);
  if (siteDirs.length === 0) return;
  if (!(await attachmentsTablePresent(db))) return;
  const alive = await existingSiteNames(db, siteDirs);
  const orphans = [];
  let scanned = 0;
  let seen = 0;
  for (const siteDir of siteDirs) {
    if (!alive.has(siteDir.name)) continue;
    if (seen >= SCAN_ENTRY_CAP) break;
    const dir = path.join(root, ATTACHMENT_SUBTREE, siteDir.name);
    let files;
    try {
      files = await fsp.readdir(dir, { withFileTypes: true });
    } catch (_error) {
      continue;
    }
    const candidates = [];
    for (const file of files) {
      seen += 1;
      if (!file.isFile() || !UUID_PATTERN.test(file.name)) continue;
      try {
        const info = await fsp.lstat(path.join(dir, file.name));
        if (info.isFile() && now - info.mtimeMs > minAgeMs) candidates.push(`${siteDir.name}/${file.name}`);
      } catch (_error) {
        // o arada kaldırılmış
      }
    }
    if (candidates.length === 0) continue;
    scanned += candidates.length;
    const known = await loadKnownAttachmentKeys(db, candidates);
    for (const key of candidates) {
      if (!known.has(key)) orphans.push(key);
    }
  }
  if (orphanGuardTripped({ orphans: orphans.length, scanned })) {
    summary.guard_trips += 1;
    // eslint-disable-next-line no-console
    console.error(`[work_tracking] ORAN KORUMASI: ${orphans.length}/${scanned} eski fotograf dosyasi yetim gorunuyor; yetim silme DURDURULDU (veritabani / DOCUMENTS_DIR eslesmesini kontrol edin)`);
    return;
  }
  let deleted = 0;
  for (const key of orphans) {
    if (deleted >= BATCH_LIMIT) break;
    try {
      if (await removeStoredFile(root, key, ATTACHMENT_SUBTREE)) {
        deleted += 1;
        summary.attachment_orphans += 1;
      }
    } catch (_error) {
      summary.errors += 1;
    }
  }
}

/** (4a) silinmiş siteler için `work_attachments/<kod>` dizinleri (7 gün sonra; kaydı kalmamış olmalı; seyrek alt ağaç oran koruması: attachmentSiteDirGuardTripped). */
async function removeDeletedAttachmentSiteDirs(root, summary, db, now) {
  const siteDirs = await listSiteDirs(root, ATTACHMENT_SUBTREE);
  if (siteDirs.length === 0) return;
  if (!(await attachmentsTablePresent(db))) return;
  const alive = await existingSiteNames(db, siteDirs);
  const base = path.join(root, ATTACHMENT_SUBTREE);
  const removable = [];
  for (const entry of siteDirs) {
    if (alive.has(entry.name)) continue;
    const full = path.join(base, entry.name);
    if (!isInside(full, base) || full === base) continue;
    try {
      if (!(await siteDirIsStale(full, now))) continue;
      const records = await db.query(`SELECT 1 FROM work_item_attachments WHERE site_code = $1 LIMIT 1`, [Number(entry.name)]);
      if (records.rows?.[0]) continue;
      removable.push(full);
    } catch (_error) {
      summary.errors += 1;
    }
  }
  if (removable.length === 0) return;
  const total = await db.query(`SELECT COUNT(*)::INTEGER AS n FROM sites`);
  const siteCount = Number(total.rows?.[0]?.n ?? 0);
  if (attachmentSiteDirGuardTripped({ removable: removable.length, totalDirs: siteDirs.length, siteCount })) {
    summary.guard_trips += 1;
    // eslint-disable-next-line no-console
    console.error(`[work_tracking] ORAN KORUMASI: ${removable.length}/${siteDirs.length} fotograf site dizini silinmis gorunuyor (DB'de ${siteCount} site); dizin silme DURDURULDU`);
    return;
  }
  for (const full of removable) {
    try {
      await fsp.rm(full, { recursive: true, force: true });
      summary.attachment_site_dirs += 1;
    } catch (_error) {
      summary.errors += 1;
    }
  }
}

/** Dizin adı -> DB'de var olan siteler (kümesi). */
async function existingSiteNames(db, siteDirs) {
  const existing = await db.query(`SELECT site_code FROM sites WHERE site_code = ANY($1::BIGINT[])`, [siteDirs.map((entry) => Number(entry.name))]);
  return new Set((existing.rows ?? []).map((row) => String(row.site_code)));
}

/**
 * (3) diskte olup DB'de olmayan dosyalar (24 saatten eski, tur başına <= 200) KARANTİNAYA alınır, silinmez. YALNIZ DB'de VAR OLAN sitelerin dizinleri taranır (silinmiş site dizinlerini (4) ele alır).
 * "Bilinen" = document_versions ∪ expense_documents (Faz 4b gider belgesi dikişi). DB sorgusu başarısızsa HİÇBİRİ taşınmaz. ORAN KORUMASI: yetim > 20 ve
 * taranan eski dosyaların %50'sinden fazlasıysa (yanlış/boş DB belirtisi) silme yapılmaz, uyarılır.
 */
async function sweepOrphans(root, summary, db, now) {
  const siteDirs = await listSiteDirs(root);
  if (siteDirs.length === 0) return;
  const alive = await existingSiteNames(db, siteDirs);
  const orphans = [];
  let scanned = 0;
  let seen = 0;
  for (const siteDir of siteDirs) {
    if (!alive.has(siteDir.name)) continue;
    if (seen >= SCAN_ENTRY_CAP) break;
    const dir = path.join(root, 'sites', siteDir.name);
    let files;
    try {
      files = await fsp.readdir(dir, { withFileTypes: true });
    } catch (_error) {
      continue;
    }
    const candidates = [];
    for (const file of files) {
      seen += 1;
      if (!file.isFile() || !UUID_PATTERN.test(file.name)) continue;
      try {
        const info = await fsp.lstat(path.join(dir, file.name));
        if (info.isFile() && now - info.mtimeMs > ORPHAN_MIN_AGE_MS) candidates.push(`${siteDir.name}/${file.name}`);
      } catch (_error) {
        // o arada kaldırılmış
      }
    }
    if (candidates.length === 0) continue;
    scanned += candidates.length;
    // DB'ye ulaşılamıyorsa (hata) HİÇBİR dosya silinmez: istisna dışarı fırlar.
    const known = await loadKnownKeys(db, candidates);
    for (const key of candidates) {
      if (!known.has(key)) orphans.push(key);
    }
  }
  if (orphanGuardTripped({ orphans: orphans.length, scanned })) {
    summary.guard_trips += 1;
    // eslint-disable-next-line no-console
    console.error(`[documents] ORAN KORUMASI: ${orphans.length}/${scanned} eski dosya yetim gorunuyor; yetim silme DURDURULDU (veritabani / DOCUMENTS_DIR eslesmesini kontrol edin)`);
    return;
  }
  let deleted = 0;
  for (const key of orphans) {
    if (deleted >= BATCH_LIMIT) break;
    try {
      if (await quarantineStoredFile(root, key, now)) {
        deleted += 1;
        summary.orphan_files += 1;
      }
    } catch (_error) {
      summary.errors += 1;
    }
  }
}

/** Dizin ve içindekilerin hepsi 7 günden eski mi (yakın zamanda yazılmış dosya varsa dokunulmaz). */
async function siteDirIsStale(full, now) {
  const info = await fsp.lstat(full);
  if (info.isSymbolicLink() || now - info.mtimeMs <= SITE_DIR_MIN_AGE_MS) return false;
  for (const child of await fsp.readdir(full, { withFileTypes: true })) {
    const childInfo = await fsp.lstat(path.join(full, child.name));
    if (now - childInfo.mtimeMs <= SITE_DIR_MIN_AGE_MS) return false;
  }
  return true;
}

/**
 * (4) silinmiş siteler için `sites/<kod>` dizinleri (7 gün sonra). Koruma: o siteye ait HİÇ kayıt (belge sürümü / gider belgesi) kalmamış olmalı;
 * DB'de hiç site yokken ya da dizinlerin yarısından fazlası "silinmiş" görünürken (>= 2) HİÇBİRİ silinmez (yanlış/boş DB belirtisi).
 */
async function removeDeletedSiteDirs(root, summary, db, now) {
  const siteDirs = await listSiteDirs(root);
  if (siteDirs.length === 0) return;
  const alive = await existingSiteNames(db, siteDirs);
  const removable = [];
  for (const entry of siteDirs) {
    if (alive.has(entry.name)) continue;
    const full = path.join(root, 'sites', entry.name);
    if (!isInside(full, path.join(root, 'sites')) || full === path.join(root, 'sites')) continue;
    try {
      if (!(await siteDirIsStale(full, now))) continue;
      if (await siteHasRecords(db, Number(entry.name))) continue;
      removable.push(full);
    } catch (_error) {
      summary.errors += 1;
    }
  }
  if (removable.length === 0) return;
  const total = await db.query(`SELECT COUNT(*)::INTEGER AS n FROM sites`);
  const siteCount = Number(total.rows?.[0]?.n ?? 0);
  if (siteDirGuardTripped({ removable: removable.length, totalDirs: siteDirs.length, siteCount })) {
    summary.guard_trips += 1;
    // eslint-disable-next-line no-console
    console.error(`[documents] ORAN KORUMASI: ${removable.length}/${siteDirs.length} site dizini silinmis gorunuyor (DB'de ${siteCount} site); dizin silme DURDURULDU`);
    return;
  }
  for (const full of removable) {
    try {
      await fsp.rm(full, { recursive: true, force: true });
      summary.site_dirs += 1;
    } catch (_error) {
      summary.errors += 1;
    }
  }
}

/**
 * Bakımı bir kez çalıştırır. Tek çalışan: session advisory kilidi alınamazsa { skipped: true }. DB/diske ulaşılamazsa hata yutulur (sayılara yazılır).
 * @param {{ now?: number, env?: object }} [options] now: ms (test için zaman enjeksiyonu)
 */
export async function runDocumentsMaintenanceOnce({ now = Date.now(), env = process.env } = {}) {
  const summary = emptySummary();
  let client;
  try {
    client = await pool.connect();
  } catch (_error) {
    return { skipped: true, reason: 'db', summary };
  }
  // Ödünç alınan bağlantıda 'error' dinleyicisi YOKTUR (pg Pool yalnız boştaki istemciyi dinler): bakım sırasında bağlantı kopsa dinleyicisiz 'error'
  // uncaughtException olup süreci düşürürdü (R11 F5; announcement_lock.js kalıbı). Oturum kilidi bağlantıyla birlikte düşer.
  const onClientError = (error) => {
    // eslint-disable-next-line no-console
    console.error('[documents] bakim baglanti hatasi (kilit duser):', error?.code || 'hata');
  };
  client.on('error', onClientError);
  // Kilidin durumu belirsizse (kilit sorgusu ya da açma başarısız) bağlantı havuza GERİ VERİLMEZ, yok edilir: oturum kilidi bağlantıyla düşer;
  // aksi halde kilidi tutan bağlantı havuzda asılı kalır ve sonraki turlar sonsuza dek "busy" görür.
  let destroyClient = false;
  try {
    let lock;
    try {
      lock = await client.query('SELECT pg_try_advisory_lock($1::int, $2::int) AS locked', MAINTENANCE_LOCK);
    } catch (error) {
      destroyClient = true;
      throw error;
    }
    if (lock.rows?.[0]?.locked !== true) {
      return { skipped: true, reason: 'busy', summary };
    }
    try {
      const limits = documentLimits(env);
      const storage = await checkStorage(env);
      if (storage.ok) {
        await safe(summary, 'stale_uploads', () => cleanStaleUploads(storage.root, limits, summary, client));
        await safe(summary, 'attachment_stale_uploads', () => cleanStaleAttachmentUploads(storage.root, summary, client));
        await safe(summary, 'temp_files', () => cleanTempFiles(storage.root, summary, now));
        await safe(summary, 'purge_expired', () => purgeExpired(limits, summary, client));
        // karantinada süresi dolanlar (zaman tabanlıdır, DB'ye bağlı değildir): kimlik denetiminden bağımsız çalışır
        await safe(summary, 'quarantine', async () => {
          const purged = await purgeQuarantine(storage.root, limits.orphanQuarantineDays, now);
          summary.quarantine_purged += purged.purged;
          summary.errors += purged.errors;
        });
        // DİSKTEN-GELEN silmeler (yetim süpürme, site dizini) yalnız depolama kimliği DB ile eşleşiyorsa çalışır (başka/boş/eski DB koruması)
        let identityOk = false;
        await safe(summary, 'identity', async () => {
          const identity = await ensureStorageIdentity(client, storage.root);
          identityOk = identity.ok;
          if (!identity.ok) {
            summary.identity_blocked = 1;
            // eslint-disable-next-line no-console
            console.error(`[documents] depolama kimligi DOGRULANAMADI (durum=${identity.state}); yetim dosya ve site dizini silme DURDURULDU. DOCUMENTS_DIR / veritabani eslesmesini kontrol edin; dogruysa: node scripts/documents_fsck.mjs --adopt-storage-id`);
          }
        });
        if (identityOk) {
          await safe(summary, 'orphans', () => sweepOrphans(storage.root, summary, client, now));
          await safe(summary, 'site_dirs', () => removeDeletedSiteDirs(storage.root, summary, client, now));
          // iş takibi fotoğraf ekleri (047): aynı kimlik kapısı, ayrı alt ağaç
          await safe(summary, 'attachment_orphans', () => sweepAttachmentOrphans(storage.root, summary, client, now, env));
          await safe(summary, 'attachment_site_dirs', () => removeDeletedAttachmentSiteDirs(storage.root, summary, client, now));
        }
      } else {
        // Dosya sistemi kullanılamıyorsa dosya gerektirmeyen turlar çalışmaz; yalnız sürümsüz pending belgeler DB'den kaldırılır.
        await safe(summary, 'pending_documents', async () => {
          const pending = await client.query(
            `DELETE FROM documents d WHERE d.status = 'pending' AND d.created_at < NOW() - make_interval(mins => $1::INTEGER) AND NOT EXISTS (SELECT 1 FROM document_versions v WHERE v.document_id = d.id)`,
            [limits.uploadTtlMinutes],
          );
          summary.pending_documents += Number(pending.rowCount ?? 0);
        });
      }
    } finally {
      try {
        await client.query('SELECT pg_advisory_unlock($1::int, $2::int)', MAINTENANCE_LOCK);
      } catch (_error) {
        destroyClient = true; // kilit açılamadı: bağlantıyı yok et (kilit oturumla birlikte düşer)
      }
    }
  } catch (error) {
    summary.errors += 1;
    // eslint-disable-next-line no-console
    console.error('[documents] bakim hatasi:', error?.code || error?.name || 'error');
  } finally {
    // yok edilen istemcide dinleyici KALIR (kapanışta geç gelen 'error' süreci düşürmesin); havuza dönen istemciden sökülür (birikmesin)
    if (!destroyClient) client.off('error', onClientError);
    client.release(destroyClient);
  }
  const touched = Object.entries(summary).filter(([, count]) => count > 0);
  if (touched.length > 0) {
    // eslint-disable-next-line no-console
    console.log(`[documents] bakim: ${touched.map(([key, count]) => `${key}=${count}`).join(' ')}`);
  }
  return { skipped: false, summary };
}

let timer = null;
let running = null;

function disabled(env = process.env) {
  return String(env.DOCUMENTS_MAINTENANCE_DISABLED ?? '').trim() === '1';
}

/** Açılışta çağrılır: saatte bir (+ açılıştan 2 dk sonra ilk tur); zamanlayıcı süreci açık tutmaz (unref). */
export function startDocumentsMaintenance({ intervalMs = HOUR_MS, firstDelayMs = 2 * 60 * 1000, env = process.env } = {}) {
  if (timer || disabled(env)) {
    return false;
  }
  // Açılış öz-denetimi: dizin yok / depo içinde / yazılamıyor ise ERROR günlüğü AÇILIŞTA görünür; uçlar 503 döner, sunucu düşmez.
  void checkStorage(env, { force: true }).catch(() => {});
  const tick = () => {
    running = runDocumentsMaintenanceOnce({ env })
      .catch(() => {})
      .finally(() => {
        running = null;
      });
  };
  const first = setTimeout(() => {
    tick();
    timer = setInterval(tick, intervalMs);
    timer.unref?.();
  }, firstDelayMs);
  first.unref?.();
  timer = first;
  return true;
}

/** Kapanışta: zamanlayıcıyı durdurur ve süren turu bekler. */
export async function stopDocumentsMaintenance() {
  if (timer) {
    clearTimeout(timer);
    clearInterval(timer);
    timer = null;
  }
  if (running) {
    await running.catch(() => {});
  }
}
