#!/usr/bin/env node
// Belgeler (Faz 3b-A) bütünlük denetimi: veritabanı <-> DOCUMENTS_DIR uyumu. Yedekten geri yüklemeden sonra ÇALIŞTIRILIR (docs/PLATFORM_BELGELER.md A2).
//
//   node scripts/documents_fsck.mjs [--report] [--verify-hash [--limit N]] [--fix-orphans [--force]] [--restore-quarantine] [--adopt-storage-id] [--json]
//
//   --report            (varsayılan, SALT OKUNUR) DB'de olup diskte olmayan (KRİTİK), diskte olup DB'de olmayan (yetim), boyut uyuşmazlığı, bayat `uploading`.
//                       Bilinen anahtarlar document_versions ∪ expense_documents (Faz 4b gider belgesi) kümesidir: gider belgesi dosyası yetim SAYILMAZ.
//   --verify-hash       `ready` kayıtların sha256'sını diskten yeniden hesaplayıp karşılaştırır (--limit N: en çok N dosya, yoksa hepsi).
//   --fix-orphans       24 saatten eski yetim dosyaları KARANTİNAYA alır (`_orphans/<site>/<uuid>`; SİLİNMEZ, DOCUMENTS_ORPHAN_QUARANTINE_DAYS gün sonra bakım işi siler;
//                       çalıştırma başına en çok 200). Başka hiçbir şeye dokunmaz. KORUMALAR (yanlış/boş DB'ye karşı):
//                       depolama kimliği (dizindeki .instance ↔ DB platform_settings 'documents.storage_id') eşleşmeli; yetim > 20 ve taranan eski dosyaların
//                       %50'sinden fazlasıysa silme YAPILMAZ (--force bu ORAN korumasını aşar, kimlik korumasını AŞMAZ); yalnız DB'de var olan sitelerin dizinleri.
//   --restore-quarantine  Karantinadaki dosyalardan DB'de kaydı (yeniden) görünenleri `sites/` altındaki yerine geri koyar (ör. eski bir DB dökümü geri yüklendikten sonra tam döküm
//                       alınınca). Yerinde dosya varsa dokunmaz. `--report` karantinayı HER ZAMAN gösterir; kaydı olanlar "geri alınabilir" diye işaretlenir.
//   --adopt-storage-id  Depolama kimliğini eşitler: dizinde var/DB'de yok -> DB'ye yaz; DB'de var/dizinde yok -> dizine yaz; ikisi de yoksa başlat. İkisi de var ve
//                       FARKLIYSA hata verir (elle karar). DOĞRU dizin / DB olduğundan EMİN olunca kullanın (ör. yeni sunucuya taşıma).
//   --json              Çıktı makine okunur (tek JSON nesnesi). Çıktıda dosya adı / başlık YOK: yalnız belge kimliği, sürüm numarası, depolama anahtarı.
//
// Çıkış kodu: 0 temiz, 1 yetim / uyarı (bayat yükleme, yetim dosya, korumanın silmeyi reddetmesi), 2 EKSİK dosya ya da boyut / hash uyuşmazlığı (veri kaybı şüphesi).
// Ortam: DB_* (.env) ve DOCUMENTS_DIR (sunucuyla AYNI).

import crypto from 'node:crypto';
import { createReadStream, promises as fsp } from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import { pool } from '../src/db.js';
import {
  SITE_DIR_PATTERN,
  UUID_PATTERN,
  listQuarantine,
  pathForKey,
  quarantineStoredFile,
  resolveStorageRoot,
  restoreFromQuarantine,
} from '../src/modules/document_storage.js';
import { adoptStorageIdentity, ensureStorageIdentity, expenseTableExists, inspectStorageIdentity, loadKnownKeys, orphanGuardTripped } from '../src/modules/document_integrity.js';

const DAY_MS = 24 * 60 * 60 * 1000;
const ORPHAN_MIN_AGE_MS = DAY_MS;
const FIX_LIMIT = 200;
const PAGE = 500;
const SAMPLE = 25;

async function sha256Of(file) {
  const hash = crypto.createHash('sha256');
  for await (const chunk of createReadStream(file)) hash.update(chunk);
  return hash.digest('hex');
}

/** Denetlenecek kayıt kaynakları: belge sürümleri ve (tablo varsa) gider belgeleri. */
const SOURCES = [
  {
    name: 'versions',
    sql: `SELECT v.id, v.document_id, v.version_no, v.status, v.storage_key, v.size_bytes, v.sha256, v.created_at
          FROM document_versions v WHERE v.id > $1 ORDER BY v.id LIMIT $2`,
    ref: (row) => ({ document_id: Number(row.document_id), version_no: Number(row.version_no), storage_key: row.storage_key }),
  },
  {
    name: 'expense_documents',
    sql: `SELECT d.id, d.status, d.storage_key, d.size_bytes, d.sha256, d.added_at AS created_at
          FROM expense_documents d WHERE d.id > $1 ORDER BY d.id LIMIT $2`,
    ref: (row) => ({ expense_document_id: Number(row.id), storage_key: row.storage_key }),
    optional: true,
  },
  {
    name: 'payment_notices',
    sql: `SELECT n.id, n.status, n.storage_key, n.size_bytes, n.sha256, n.submitted_at AS created_at
          FROM payment_notices n WHERE n.id > $1 AND n.storage_key IS NOT NULL AND (n.file_completed_at IS NOT NULL OR n.status = 'uploading') ORDER BY n.id LIMIT $2`,
    ref: (row) => ({ payment_notice_id: Number(row.id), storage_key: row.storage_key }),
    optional: 'payment_notices',
  },
];

/** İsteğe bağlı kaynak tablosu var mı (optional: true = gider belgeleri; metin = tablo adı). */
async function sourceTableExists(db, source) {
  if (source.optional === true) return expenseTableExists(db);
  const found = await db.query(`SELECT to_regclass('public.${source.optional}') IS NOT NULL AS present`);
  return found.rows?.[0]?.present === true;
}

/**
 * Denetimi çalıştırır ve sonuç nesnesini döndürür (çıktı yazmaz; test / QA doğrudan çağırır).
 * @param {{ verifyHash?: boolean, limit?: number|null, fixOrphans?: boolean, force?: boolean, restoreQuarantine?: boolean, adoptStorageId?: boolean, root?: string, now?: number, db?: object }} [options]
 */
export async function runFsck({
  verifyHash = false,
  limit = null,
  fixOrphans = false,
  force = false,
  restoreQuarantine = false,
  adoptStorageId = false,
  root = resolveStorageRoot().dir,
  now = Date.now(),
  db = pool,
} = {}) {
  const result = {
    root_exists: true,
    versions_checked: 0,
    expense_documents_checked: 0,
    payment_notices_checked: 0,
    missing: [],
    size_mismatch: [],
    hash_mismatch: [],
    hash_verified: 0,
    stale_uploading: [],
    orphans: [],
    orphans_removed: 0,
    orphans_skipped_deleted_sites: 0,
    quarantine: { files: 0, bytes: 0, oldest_age_days: null, restorable: [], restored: 0 },
    identity: null,
    guard_tripped: false,
    exit_code: 0,
  };
  try {
    await fsp.access(path.join(root, 'sites'));
  } catch (_error) {
    result.root_exists = false;
  }

  if (adoptStorageId) {
    result.identity = { adopted: await adoptStorageIdentity(db, root) };
  }

  // 0) karantina (yetim dosyalar silinmeden önce N gün burada bekler)
  const quarantineEntries = await listQuarantine(root);
  const quarantineKeys = new Set(quarantineEntries.map((entry) => entry.key));

  // karantina özeti + geri alınabilirler (kaydı DB'de olan karantina dosyaları)
  if (quarantineEntries.length > 0) {
    const stillKnown = await loadKnownKeys(db, [...quarantineKeys]);
    result.quarantine.files = quarantineEntries.length;
    result.quarantine.bytes = quarantineEntries.reduce((sum, entry) => sum + entry.size, 0);
    result.quarantine.oldest_age_days = Math.floor((now - Math.min(...quarantineEntries.map((entry) => entry.mtimeMs))) / DAY_MS);
    result.quarantine.restorable = quarantineEntries.filter((entry) => stillKnown.has(entry.key)).map((entry) => entry.key);
    if (restoreQuarantine) {
      const restoredKeys = new Set();
      for (const entry of quarantineEntries) {
        if (stillKnown.has(entry.key) && (await restoreFromQuarantine(root, entry, now))) {
          result.quarantine.restored += 1;
          restoredKeys.add(entry.key);
          quarantineKeys.delete(entry.key); // artık eksik değil: aşağıdaki DB -> disk denetimi geri konmuş dosyayı görür
        }
      }
      result.quarantine.restorable = result.quarantine.restorable.filter((key) => !restoredKeys.has(key));
    }
  }

  // 1) DB -> disk
  const knownKeys = new Set();
  for (const source of SOURCES) {
    if (source.optional && !(await sourceTableExists(db, source))) continue;
    let afterId = 0;
    for (;;) {
      const page = await db.query(source.sql, [afterId, PAGE]);
      const rows = page.rows ?? [];
      if (rows.length === 0) break;
      for (const row of rows) {
        afterId = Number(row.id);
        knownKeys.add(row.storage_key);
        if (source.name === 'versions') result.versions_checked += 1;
        else if (source.name === 'payment_notices') result.payment_notices_checked += 1;
        else result.expense_documents_checked += 1;
        const ref = source.ref(row);
        let full;
        try {
          full = pathForKey(root, row.storage_key);
        } catch (_error) {
          result.missing.push({ ...ref, reason: 'gecersiz_anahtar' });
          continue;
        }
        const info = await fsp.lstat(full).catch(() => null);
        if (row.status === 'uploading') {
          // yükleme sürerken dosya henüz yok olabilir; yalnız bayat olanlar raporlanır
          if (now - new Date(row.created_at).getTime() > 2 * 60 * 60 * 1000) result.stale_uploading.push(ref);
          continue;
        }
        if (!info || !info.isFile()) {
          result.missing.push({ ...ref, reason: 'dosya_yok', ...(quarantineKeys.has(row.storage_key) ? { in_quarantine: true } : {}) });
          continue;
        }
        if (info.size !== Number(row.size_bytes)) {
          result.size_mismatch.push({ ...ref, disk: info.size, db: Number(row.size_bytes) });
          continue;
        }
        if (verifyHash && row.sha256 && (limit === null || result.hash_verified < limit)) {
          result.hash_verified += 1;
          if ((await sha256Of(full)) !== row.sha256) result.hash_mismatch.push(ref);
        }
      }
    }
  }

  // 2) disk -> DB (yetim dosyalar). Bilinen = yukarıdaki kümeler (sayfalı okuma ile aynı anda yazılan satırlar için ayrıca DB'ye bakılır).
  const sitesDir = path.join(root, 'sites');
  const siteDirs = (await fsp.readdir(sitesDir, { withFileTypes: true }).catch(() => [])).filter((entry) => entry.isDirectory() && SITE_DIR_PATTERN.test(entry.name));
  const existing = siteDirs.length === 0 ? [] : (await db.query(`SELECT site_code FROM sites WHERE site_code = ANY($1::BIGINT[])`, [siteDirs.map((entry) => Number(entry.name))])).rows ?? [];
  const alive = new Set(existing.map((row) => String(row.site_code)));
  let oldScannedInLiveSites = 0;
  const removable = [];
  for (const siteDir of siteDirs) {
    const dir = path.join(sitesDir, siteDir.name);
    const siteAlive = alive.has(siteDir.name);
    const uncertain = [];
    for (const file of await fsp.readdir(dir, { withFileTypes: true }).catch(() => [])) {
      if (!file.isFile() || !UUID_PATTERN.test(file.name)) continue;
      const key = `${siteDir.name}/${file.name}`;
      const info = await fsp.lstat(path.join(dir, file.name)).catch(() => null);
      if (!info) continue;
      const old = now - info.mtimeMs > ORPHAN_MIN_AGE_MS;
      if (siteAlive && old) oldScannedInLiveSites += 1;
      if (knownKeys.has(key)) continue;
      uncertain.push({ key, info, old });
    }
    if (uncertain.length === 0) continue;
    // sayfalı okuma sırasında araya giren kayıtlar yetim sayılmasın: kalan adaylar bir kez daha DB'den doğrulanır
    const stillKnown = await loadKnownKeys(db, uncertain.map((entry) => entry.key));
    for (const entry of uncertain) {
      if (stillKnown.has(entry.key)) continue;
      result.orphans.push({ storage_key: entry.key, age_hours: Math.floor((now - entry.info.mtimeMs) / 3_600_000), size: entry.info.size, site_exists: siteAlive });
      if (entry.old && siteAlive) removable.push(entry.key);
      else if (entry.old) result.orphans_skipped_deleted_sites += 1;
    }
  }

  if (fixOrphans) {
    const identity = await ensureStorageIdentity(db, root);
    result.identity = { ...(result.identity ?? {}), ...identity };
    if (!identity.ok) {
      result.guard_tripped = true;
    } else if (!force && orphanGuardTripped({ orphans: removable.length, scanned: oldScannedInLiveSites })) {
      result.guard_tripped = true;
    } else {
      for (const key of removable) {
        if (result.orphans_removed >= FIX_LIMIT) break;
        if (await quarantineStoredFile(root, key, now)) result.orphans_removed += 1; // KARANTİNAYA alındı (silinmedi)
      }
    }
  } else if (!adoptStorageId) {
    result.identity = await inspectStorageIdentity(db, root).catch(() => null);
  }

  const critical = result.missing.length + result.size_mismatch.length + result.hash_mismatch.length;
  const remainingOrphans = result.orphans.length - result.orphans_removed;
  if (critical > 0 || !result.root_exists) {
    result.exit_code = 2;
  } else if (remainingOrphans > 0 || result.stale_uploading.length > 0 || result.guard_tripped) {
    result.exit_code = 1;
  }
  return result;
}

function parseArgs(argv) {
  const options = { verifyHash: false, limit: null, fixOrphans: false, force: false, restoreQuarantine: false, adoptStorageId: false, json: false };
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === '--report') continue;
    else if (arg === '--verify-hash') options.verifyHash = true;
    else if (arg === '--fix-orphans') options.fixOrphans = true;
    else if (arg === '--restore-quarantine') options.restoreQuarantine = true;
    else if (arg === '--force') options.force = true;
    else if (arg === '--adopt-storage-id') options.adoptStorageId = true;
    else if (arg === '--json') options.json = true;
    else if (arg === '--limit') {
      options.limit = Number(argv[(i += 1)]);
      if (!Number.isSafeInteger(options.limit) || options.limit < 1) throw new Error('--limit pozitif tamsayi olmali');
    } else {
      throw new Error(`bilinmeyen secenek: ${arg}`);
    }
  }
  return options;
}

function printHuman(result) {
  const out = (line) => console.log(line);
  out(`Belge bütünlük denetimi (kök dizin ${result.root_exists ? 'var' : 'YOK'})`);
  out(`  denetlenen sürüm / gider belgesi : ${result.versions_checked} / ${result.expense_documents_checked}`);
  out(`  denetlenen dekont bildirimi      : ${result.payment_notices_checked}`);
  out(`  denetlenen dekont bildirimi      : ${result.payment_notices_checked}`);
  out(`  EKSİK dosya (kritik)    : ${result.missing.length}`);
  out(`  boyut uyuşmazlığı       : ${result.size_mismatch.length}`);
  out(`  hash doğrulanan/yanlış  : ${result.hash_verified}/${result.hash_mismatch.length}`);
  out(`  bayat yükleme           : ${result.stale_uploading.length}`);
  out(`  yetim dosya             : ${result.orphans.length} (karantinaya alınan: ${result.orphans_removed}; silinmiş site dizinlerinde bekleyen: ${result.orphans_skipped_deleted_sites})`);
  const q = result.quarantine;
  out(`  karantina (_orphans)    : ${q.files} dosya, ${q.bytes} bayt${q.files > 0 ? `, en eski ${q.oldest_age_days} gün` : ''}; DB'de kaydı olan (geri alınabilir): ${q.restorable.length}; bu çalıştırmada geri konan: ${q.restored}`);
  if (result.identity) out(`  depolama kimliği        : ${JSON.stringify(result.identity)}`);
  if (result.guard_tripped) out('  KORUMA                  : yetim silme REDDEDİLDİ (kimlik uyuşmuyor ya da oran koruması); ayrıntı için kimliğe bakın');
  for (const [label, list] of [['EKSİK', result.missing], ['BOYUT', result.size_mismatch], ['HASH', result.hash_mismatch], ['BAYAT', result.stale_uploading], ['YETİM', result.orphans]]) {
    for (const item of list.slice(0, SAMPLE)) out(`  ${label}: ${JSON.stringify(item)}`);
    if (list.length > SAMPLE) out(`  ${label}: ... ve ${list.length - SAMPLE} kayıt daha`);
  }
  out(`çıkış kodu: ${result.exit_code}`);
}

const invokedDirectly = process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href;
if (invokedDirectly) {
  let options;
  try {
    options = parseArgs(process.argv.slice(2));
  } catch (error) {
    console.error(error.message);
    process.exit(64);
  }
  try {
    const result = await runFsck(options);
    if (options.json) console.log(JSON.stringify(result));
    else printHuman(result);
    await pool.end().catch(() => {});
    process.exit(result.exit_code);
  } catch (error) {
    console.error('fsck hatasi:', error?.code || error?.message);
    await pool.end().catch(() => {});
    process.exit(70);
  }
}
