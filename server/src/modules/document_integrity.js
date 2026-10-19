// Belgeler (Faz 3b-A): depolama bütünlüğü yardımcıları — bakım işi (document_maintenance.js) ve scripts/documents_fsck.mjs ORTAK kullanır.
//
//  1) "Bilinen anahtar" kümesi: bir dosya YETİM sayılmadan önce hem document_versions.storage_key hem (varsa) expense_documents.storage_key (Faz 4b gider belgesi)
//     ile karşılaştırılır. Gider belgesi dikişi bağlandığında dosyaları aynı sites/<site>/<uuid> düzenine yazılır; yalnız document_versions'a bakılsa
//     24 saati geçen her gider belgesi yetim sanılıp silinirdi (KMK m.36 saklama yükümlülüğü). expense_documents tablosu henüz yoksa sessizce atlanır.
//  2) DEPOLAMA KİMLİĞİ: kök dizine (.instance) rastgele bir kimlik yazılır ve AYNI kimlik veritabanında saklanır (platform_settings 'documents.storage_id').
//     İkisi uyuşmuyorsa (başka/boş/eski bir DB bu dizine bakıyor, ya da dizin başka bir kurulumdan) DİSKTEN-GELEN silmeler (yetim süpürme, site dizini kaldırma,
//     fsck --fix-orphans) REDDEDİLİR ve günlüğe yazılır. DB'den-gelen silmeler (bayat yükleme, süresi dolan belge) kendi satırına bağlı olduğundan etkilenmez.
//  3) ORAN KORUMASI: bir turda var olan sitelerdeki (24 saatten eski) dosyaların %50'sinden fazlası ve 20'den fazlası yetim görünüyorsa silme yapılmaz, uyarılır.
//     Yetim sayısı normalde 0'a yakındır (çökme artıkları); toplu "yetim" görünmesi DB'nin yanlış/boş olduğunun belirtisidir.

import crypto from 'node:crypto';
import { promises as fsp } from 'node:fs';
import path from 'node:path';
import { SITE_DIR_PATTERN, STORAGE_SUBTREES, UUID_PATTERN } from './document_storage.js';

export const IDENTITY_FILE = '.instance';
export const IDENTITY_SETTING_KEY = 'documents.storage_id';
export const ORPHAN_GUARD_MIN = 20;
export const ORPHAN_GUARD_RATIO = 0.5;
/** Site dizini kaldırma korumasında: bir turda kaldırılacak dizin sayısı bunu aşar ve tüm site dizinlerinin yarısından fazlasıysa durdurulur. */
export const SITE_DIR_GUARD_MIN = 2;
const SAMPLE_SIZE = 20;
const IDENTITY_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;

// --- Bilinen anahtarlar --------------------------------------------------------------------------------------------------

/** `expense_documents` (Faz 4b) tablosu var mı? Yoksa gider belgesi dikişi henüz kurulmamıştır. */
export async function expenseTableExists(db) {
  const result = await db.query(`SELECT to_regclass('public.expense_documents') IS NOT NULL AS present`);
  return result.rows?.[0]?.present === true;
}

/**
 * Verilen anahtarlardan DB'de KAYITLI olanlar (document_versions ∪ expense_documents). Sorgu hatası fırlar: çağıran HİÇBİR dosya silmemelidir.
 * @returns {Promise<Set<string>>}
 */
export async function loadKnownKeys(db, keys) {
  const known = new Set();
  if (keys.length === 0) return known;
  const versions = await db.query(`SELECT storage_key FROM document_versions WHERE storage_key = ANY($1::TEXT[])`, [keys]);
  for (const row of versions.rows ?? []) known.add(row.storage_key);
  if (await expenseTableExists(db)) {
    const expenses = await db.query(`SELECT storage_key FROM expense_documents WHERE storage_key = ANY($1::TEXT[])`, [keys]);
    for (const row of expenses.rows ?? []) known.add(row.storage_key);
  }
  return known;
}

/** Bir siteye ait herhangi bir kayıt (belge sürümü ya da gider belgesi) var mı: varsa o site dizinine DOKUNULMAZ. */
export async function siteHasRecords(db, siteCode) {
  const versions = await db.query(`SELECT 1 FROM document_versions WHERE site_code = $1 LIMIT 1`, [siteCode]);
  if (versions.rows?.[0]) return true;
  if (await expenseTableExists(db)) {
    const expenses = await db.query(`SELECT 1 FROM expense_documents WHERE site_code = $1 LIMIT 1`, [siteCode]);
    if (expenses.rows?.[0]) return true;
  }
  return false;
}

// --- Oran koruması ---------------------------------------------------------------------------------------------------------

/** Yetim silme turu durdurulmalı mı: yetim > 20 VE yetim / taranan(24 saatten eski) > %50. */
export function orphanGuardTripped({ orphans, scanned }) {
  return orphans > ORPHAN_GUARD_MIN && orphans / Math.max(1, scanned) > ORPHAN_GUARD_RATIO;
}

/** Site dizini kaldırma turu durdurulmalı mı: kaldırılacak >= 2 VE tüm site dizinlerinin yarısından fazlası; ya da DB'de HİÇ site yokken dizin var. */
export function siteDirGuardTripped({ removable, totalDirs, siteCount }) {
  if (removable <= 0) return false;
  if (siteCount === 0) return true;
  return removable >= SITE_DIR_GUARD_MIN && removable / Math.max(1, totalDirs) > 0.5;
}

// --- Depolama kimliği -------------------------------------------------------------------------------------------------------

async function readIdentityFile(root) {
  try {
    const text = (await fsp.readFile(path.join(root, IDENTITY_FILE), 'utf8')).trim();
    return IDENTITY_PATTERN.test(text) ? text : 'invalid';
  } catch (error) {
    if (error?.code === 'ENOENT') return null;
    throw error;
  }
}

async function readIdentityDb(db) {
  const result = await db.query(`SELECT value FROM platform_settings WHERE key = $1 LIMIT 1`, [IDENTITY_SETTING_KEY]);
  const value = result.rows?.[0]?.value;
  const id = value && typeof value === 'object' ? value.id : null;
  return typeof id === 'string' && IDENTITY_PATTERN.test(id) ? id : null;
}

async function writeIdentityFile(root, id) {
  await fsp.writeFile(path.join(root, IDENTITY_FILE), `${id}\n`, { flag: 'wx', mode: 0o600 });
}

async function writeIdentityDb(db, id) {
  await db.query(`INSERT INTO platform_settings (key, value) VALUES ($1, $2::jsonb) ON CONFLICT (key) DO NOTHING`, [IDENTITY_SETTING_KEY, JSON.stringify({ id })]);
}

/**
 * Kökteki herhangi bir alt ağaçta (sites/ belgeler, work_attachments/ iş takibi fotoğrafları) uuid-adlı dosya var mı: yeni/boş dizinde kimlik güvenle başlatılabilir.
 * Fotoğraf ağacı da sayılır: yalnız fotoğraf barındıran bir dizine yanlış / boş DB bakarsa kimlik sessizce benimsenip fotoğraflar yetim sanılmasın.
 */
async function diskHasStoredFiles(root) {
  for (const subtree of STORAGE_SUBTREES) {
    let siteDirs;
    try {
      siteDirs = (await fsp.readdir(path.join(root, subtree), { withFileTypes: true })).filter((entry) => entry.isDirectory() && SITE_DIR_PATTERN.test(entry.name));
    } catch (_error) {
      continue;
    }
    for (const siteDir of siteDirs) {
      const files = await fsp.readdir(path.join(root, subtree, siteDir.name)).catch(() => []);
      if (files.some((name) => UUID_PATTERN.test(name))) return true;
    }
  }
  return false;
}

/** `work_item_attachments` (047) tablosu var mı? Yoksa fotoğraf örneklemesi yapılmaz. */
async function attachmentsTableExists(db) {
  const result = await db.query(`SELECT to_regclass('public.work_item_attachments') IS NOT NULL AS present`);
  return result.rows?.[0]?.present === true;
}

/**
 * DB'nin bildiği (ready) son sürümlerden / gider belgelerinden / iş takibi fotoğraflarından birkaçı diskte VAR mı: ilk kimlik başlatmada "bu DB bu dizinin DB'si mi"
 * örneklemesi. Fotoğraflar `work_attachments/` alt ağacında aranır.
 */
async function dbMatchesDisk(db, root) {
  const keys = [];
  const versions = await db.query(`SELECT storage_key FROM document_versions WHERE status = 'ready' ORDER BY id DESC LIMIT ${SAMPLE_SIZE}`);
  for (const row of versions.rows ?? []) keys.push(['sites', row.storage_key]);
  if (await expenseTableExists(db)) {
    const expenses = await db.query(`SELECT storage_key FROM expense_documents WHERE status = 'ready' ORDER BY id DESC LIMIT ${SAMPLE_SIZE}`);
    for (const row of expenses.rows ?? []) keys.push(['sites', row.storage_key]);
  }
  if (await attachmentsTableExists(db)) {
    const attachments = await db.query(`SELECT storage_key FROM work_item_attachments WHERE status = 'ready' ORDER BY id DESC LIMIT ${SAMPLE_SIZE}`);
    for (const row of attachments.rows ?? []) keys.push(['work_attachments', row.storage_key]);
  }
  for (const [subtree, key] of keys) {
    if (typeof key !== 'string' || !/^\d{10}\/[0-9a-f-]{36}$/.test(key)) continue;
    try {
      await fsp.lstat(path.join(root, subtree, key));
      return true;
    } catch (_error) {
      // yok
    }
  }
  return false;
}

/**
 * Depolama kimliğini doğrular (gerekirse güvenle başlatır).
 *  - dosya VAR + DB VAR: eşitse 'verified', değilse 'mismatch'
 *  - ikisi de YOK: dizinde dosya yoksa ya da DB'nin bildiği dosyalardan en az biri diskteyse kimlik üretilir ('initialized'); aksi 'unverified_state'
 *  - yalnız dosya VAR: dizinde (sites/ altında) hiç dosya yoksa DB'ye yazılır ('adopted_db'); varsa 'db_identity_missing' (yanlış/eski/boş DB şüphesi)
 *  - yalnız DB VAR: dizinde hiç dosya yoksa dosya yazılır ('adopted_file'); varsa 'file_identity_missing' (başka dizin şüphesi)
 *  - dosya bozuk: 'file_identity_invalid'
 * Hata (DB'ye ulaşılamıyor vb.) FIRLAR: çağıran silme yapmamalıdır.
 * @returns {Promise<{ ok: boolean, state: string }>}
 */
export async function ensureStorageIdentity(db, root) {
  const fileId = await readIdentityFile(root);
  if (fileId === 'invalid') return { ok: false, state: 'file_identity_invalid' };
  const dbId = await readIdentityDb(db);
  if (fileId && dbId) return fileId === dbId ? { ok: true, state: 'verified' } : { ok: false, state: 'mismatch' };
  if (!fileId && !dbId) {
    if ((await diskHasStoredFiles(root)) && !(await dbMatchesDisk(db, root))) return { ok: false, state: 'unverified_state' };
    return initializeIdentity(db, root);
  }
  const hasFiles = await diskHasStoredFiles(root);
  if (fileId) {
    if (hasFiles) return { ok: false, state: 'db_identity_missing' };
    await writeIdentityDb(db, fileId);
    return { ok: (await readIdentityDb(db)) === fileId, state: 'adopted_db' };
  }
  if (hasFiles) return { ok: false, state: 'file_identity_missing' };
  await writeIdentityFile(root, dbId).catch((error) => {
    if (error?.code !== 'EEXIST') throw error;
  });
  return { ok: (await readIdentityFile(root)) === dbId, state: 'adopted_file' };
}

async function initializeIdentity(db, root) {
  const id = crypto.randomUUID();
  await writeIdentityFile(root, id);
  await writeIdentityDb(db, id);
  const stored = await readIdentityDb(db);
  if (stored !== id) {
    // başka bir süreç aynı anda başka kimlik yazdı: bizimkini geri al, ikisi uyuşmaz -> reddedilir
    await fsp.rm(path.join(root, IDENTITY_FILE), { force: true });
    return { ok: false, state: 'race' };
  }
  return { ok: true, state: 'initialized' };
}

/**
 * Operatör işlemi (documents_fsck --adopt-storage-id): yalnız GÜVENLİ iki yönü yapar — dosya var/DB yok → DB'ye yaz; DB var/dosya yok → dosyaya yaz;
 * ikisi de yoksa başlatır. İkisi VAR ve FARKLIYSA fırlatır (elle karar gerekir).
 */
export async function adoptStorageIdentity(db, root) {
  const fileId = await readIdentityFile(root);
  if (fileId === 'invalid') throw new Error('dizindeki kimlik dosyasi bozuk; elle silip yeniden deneyin');
  const dbId = await readIdentityDb(db);
  if (fileId && dbId) {
    if (fileId !== dbId) throw new Error('dizin kimligi ile veritabani kimligi FARKLI; hangisinin dogru oldugunu elle belirleyin');
    return 'already';
  }
  if (fileId) {
    await writeIdentityDb(db, fileId);
    return 'adopted_db';
  }
  if (dbId) {
    await writeIdentityFile(root, dbId);
    return 'adopted_file';
  }
  return (await initializeIdentity(db, root)).state;
}

/** SALT OKUNUR durum (fsck --report): kimlik değeri yazdırılmaz; yalnız var/yok ve eşleşme. */
export async function inspectStorageIdentity(db, root) {
  const fileId = await readIdentityFile(root);
  const dbId = await readIdentityDb(db);
  return {
    file: fileId === 'invalid' ? 'invalid' : fileId ? 'present' : 'absent',
    db: dbId ? 'present' : 'absent',
    match: Boolean(fileId && fileId !== 'invalid' && dbId && fileId === dbId),
  };
}
