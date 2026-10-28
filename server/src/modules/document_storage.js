// Belgeler (Faz 3b-A): disk depolaması.
//
// Sözleşme: docs/PLATFORM_BELGELER.md A2/A3/A8. Düzen: <kök>/sites/<site_code>/<uuid> (uuid = crypto.randomUUID, uzantısız, SUNUCUYA ait), <kök>/_tmp/<uuid>.part (aynı
// dosya sistemi), <kök>/_orphans/<site_code>/<uuid> (yetim KARANTİNASI, N gün sonra silinir; yedeğe girmez) ve <kök>/.instance (depolama kimliği). Kullanıcı girdisi YOLA
// hiçbir biçimde girmez. Dosya modu 0600, dizin 0700, açış `wx`.
// `ready` bir sürümün dosyası BİR KEZ yazılır ve ASLA ezilmez (yedek artımlılığı): son adıma geçiş `link` (zaten varsa EEXIST) ile yapılır; yalnız hâlâ `uploading` olan
// sürümün başarısız önceki denemeden kalan artığı (DB durumu document_upload.js `commitUploadedFile` ile doğrulanarak) atomik `rename` ile değiştirilir.
//
// Kök dizin: ortam değişkeni DOCUMENTS_DIR (eski ad DOCUMENTS_STORAGE_DIR de kabul edilir); yoksa sunucu kökünün DIŞINDA ~/kapi-documents.
// Çözümlenmiş yol depo kökünün (Express `build/web`'i servis eder; deploy `server/`i yedekler/geri yükler) İÇİNDE olamaz.

import crypto from 'node:crypto';
import fs from 'node:fs';
import { promises as fsp } from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { Transform } from 'node:stream';
import { fileURLToPath } from 'node:url';
import { sizeMismatch } from './document_common.js';

const here = path.dirname(fileURLToPath(import.meta.url));
/** Depo kökü (server/src/modules -> üç üst). */
export const REPO_ROOT = path.resolve(here, '..', '..', '..');

export const STORAGE_KEY_PATTERN = /^\d{10}\/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const SITE_DIR_PATTERN = /^\d{10}$/;
/**
 * Kök altındaki alt ağaçlar: `sites` (belgeler; varsayılan) ve `work_attachments` (iş takibi fotoğrafları, 047). Aynı anahtar biçimi (<site>/<uuid>), aynı
 * güvenlik kuralları; ağaç ayrımı tablo düzeyindedir (belge yetim süpürmesi yalnız `sites/`e, ek süpürmesi yalnız `work_attachments/`a bakar).
 */
export const STORAGE_SUBTREES = Object.freeze(['sites', 'work_attachments', 'feedback_attachments']);

function subtreeDir(root, subtree) {
  if (!STORAGE_SUBTREES.includes(subtree)) {
    throw new Error('gecersiz depolama alt agaci');
  }
  return path.join(root, subtree);
}

const isInside = (child, parent) => {
  const relative = path.relative(parent, child);
  return relative === '' || (!relative.startsWith('..') && !path.isAbsolute(relative));
};

/** Yapılandırılmış kök (çözümlenmiş mutlak yol) ve kaynağı. */
export function resolveStorageRoot(env = process.env) {
  const configured = String(env.DOCUMENTS_DIR ?? env.DOCUMENTS_STORAGE_DIR ?? '').trim();
  if (configured !== '') {
    return { dir: path.resolve(configured), source: 'env' };
  }
  return { dir: path.join(os.homedir(), 'kapi-documents'), source: 'default' };
}

let checkCache = null;
let loggedFailure = null;
const CHECK_TTL_OK_MS = 30_000;
const CHECK_TTL_FAIL_MS = 5_000;

/** Test yardımcısı: önbelleği sıfırlar. */
export function resetStorageCheck() {
  checkCache = null;
  loggedFailure = null;
}

async function ensureDir(dir) {
  await fsp.mkdir(dir, { recursive: true, mode: 0o700 });
}

async function runCheck(env) {
  const { dir } = resolveStorageRoot(env);
  if (isInside(dir, REPO_ROOT)) {
    return { ok: false, reason: 'inside_repo', root: dir };
  }
  try {
    await ensureDir(dir);
    const info = await fsp.lstat(dir);
    if (info.isSymbolicLink() || !info.isDirectory()) {
      return { ok: false, reason: 'not_a_directory', root: dir };
    }
    const real = await fsp.realpath(dir);
    if (isInside(real, REPO_ROOT)) {
      return { ok: false, reason: 'inside_repo', root: dir };
    }
    await ensureDir(path.join(dir, '_tmp'));
    await ensureDir(path.join(dir, 'sites'));
    const probe = path.join(dir, '_tmp', `.probe-${crypto.randomUUID()}`);
    const handle = await fsp.open(probe, 'wx', 0o600);
    await handle.close();
    await fsp.unlink(probe);
    await fsp.statfs(dir);
    return { ok: true, root: dir };
  } catch (error) {
    return { ok: false, reason: `io_${error?.code || 'error'}`, root: dir };
  }
}

/**
 * Açılış öz-denetimi (önbellekli): dizin var, GERÇEK dizin (symlink değil), depo dışında, yazılır (`_tmp/.probe` oluştur-sil), `statfs` çalışır.
 * Başarısızlık sunucuyu DÜŞÜRMEZ: uçlar 503 DOCUMENT_STORAGE_NOT_CONFIGURED döner; ERROR günlüğü yalnız durum değişince yazılır.
 * @returns {Promise<{ ok: boolean, root: string, reason?: string }>}
 */
export async function checkStorage(env = process.env, { force = false } = {}) {
  const now = Date.now();
  if (!force && checkCache && now - checkCache.at < (checkCache.result.ok ? CHECK_TTL_OK_MS : CHECK_TTL_FAIL_MS)) {
    return checkCache.result;
  }
  const result = await runCheck(env);
  checkCache = { at: now, result };
  const marker = result.ok ? null : result.reason;
  if (marker !== loggedFailure) {
    loggedFailure = marker;
    if (!result.ok) {
      // eslint-disable-next-line no-console
      console.error(`[documents] depolama kullanilamiyor (neden=${result.reason}); yukleme/indirme 503 doner. DOCUMENTS_DIR'i kontrol edin.`);
    } else if (os.tmpdir() && isInside(result.root, os.tmpdir()) && String(env.NODE_ENV ?? '') === 'production') {
      // eslint-disable-next-line no-console
      console.warn('[documents] UYARI: DOCUMENTS_DIR gecici dizin altinda; yedeklenmez ve yeniden baslatmada silinebilir.');
    }
  }
  return result;
}

/** Boş alan (bayt): fs.statfs bavail * bsize. Okunamazsa null. */
export async function freeBytes(root) {
  try {
    const stats = await fsp.statfs(root);
    return Number(stats.bavail) * Number(stats.bsize);
  } catch (_error) {
    return null;
  }
}

// --- Anahtar ve yol ----------------------------------------------------------------------------------------------

export function newStorageKey(siteCode) {
  const site = String(Number(siteCode));
  if (!SITE_DIR_PATTERN.test(site)) {
    throw new Error('gecersiz site kodu (depolama anahtari)');
  }
  return `${site}/${crypto.randomUUID()}`;
}

/** Yol üretmeden ÖNCE regex ile doğrulanır; çözümlenen yol kök/<alt ağaç> önekini taşımalı (traversal yok). `subtree` varsayılan `sites` (belgeler). */
export function pathForKey(root, key, subtree = 'sites') {
  if (typeof key !== 'string' || !STORAGE_KEY_PATTERN.test(key)) {
    throw new Error('gecersiz depolama anahtari');
  }
  const base = subtreeDir(root, subtree);
  const full = path.resolve(base, key);
  if (!isInside(full, base) || full === base) {
    throw new Error('depolama yolu kok disina cikiyor');
  }
  return full;
}

export function tmpFilePath(root) {
  return path.join(root, '_tmp', `${crypto.randomUUID()}.part`);
}

export async function ensureSiteDir(root, siteCode, subtree = 'sites') {
  const site = String(Number(siteCode));
  if (!SITE_DIR_PATTERN.test(site)) {
    throw new Error('gecersiz site kodu (dizin)');
  }
  await ensureDir(path.join(subtreeDir(root, subtree), site));
}

/** Dosyayı siler; yoksa sessizce geçer. Başka bir hata fırlar (çağıran satırı bırakır, sonra yeniden dener). @returns {Promise<boolean>} silindi mi */
export async function removeStoredFile(root, key, subtree = 'sites') {
  try {
    await fsp.unlink(pathForKey(root, key, subtree));
    return true;
  } catch (error) {
    if (error?.code === 'ENOENT') return false;
    throw error;
  }
}

// --- Karantina (R16 P2-4) --------------------------------------------------------------------------------------------
// Yetim görünen dosya SİLİNMEZ: `<kök>/_orphans/<site>/<uuid>` altına `rename` ile alınır, mtime = karantina anı. N gün (DOCUMENTS_ORPHAN_QUARANTINE_DAYS, varsayılan 14) sonra
// bakım işi siler. Aynı DB'nin eski dökümü geri yüklenince satırı kaybolmuş ama dosyası duran belgeler böylece geri alınabilir (fsck --restore-quarantine). Karantina
// yedeğe GİRMEZ (yedek yalnız `sites/` + `.instance`).

export const QUARANTINE_DIR = '_orphans';
const QUARANTINE_NAME = /^([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})(?:\.\d{1,16})?$/;
const QUARANTINE_SCAN_CAP = 200_000;

/**
 * Dosyayı karantinaya alır (silmez). Yoksa false. Aynı ad karantinada varsa `.<zaman>` eki alır. Başka hata fırlar (çağıran sayar).
 * @returns {Promise<boolean>} taşındı mı
 */
export async function quarantineStoredFile(root, key, now = Date.now()) {
  const source = pathForKey(root, key);
  const [site, name] = key.split('/');
  try {
    await fsp.lstat(source);
  } catch (error) {
    if (error?.code === 'ENOENT') return false;
    throw error;
  }
  const dir = path.join(root, QUARANTINE_DIR, site);
  await ensureDir(dir);
  let target = path.join(dir, name);
  try {
    await fsp.lstat(target);
    target = `${target}.${now}`;
  } catch (error) {
    if (error?.code !== 'ENOENT') throw error;
  }
  try {
    await fsp.rename(source, target);
  } catch (error) {
    if (error?.code === 'ENOENT') return false;
    throw error;
  }
  try {
    const stamp = new Date(now);
    await fsp.utimes(target, stamp, stamp); // karantina damgası
  } catch (_error) {
    // damga atılamazsa mtime özgün kalır (en kötü ihtimalle daha erken silinir; yine de dosya bakım turunda süpürülürdü)
  }
  return true;
}

/** Karantinadaki dosyalar: [{ key, file, size, mtimeMs }] (key = `<site>/<uuid>`; `.zaman` eki atılır). Karantina yoksa boş. */
export async function listQuarantine(root) {
  const base = path.join(root, QUARANTINE_DIR);
  let sites;
  try {
    sites = await fsp.readdir(base, { withFileTypes: true });
  } catch (_error) {
    return [];
  }
  const entries = [];
  for (const site of sites) {
    if (!site.isDirectory() || !SITE_DIR_PATTERN.test(site.name)) continue;
    const dir = path.join(base, site.name);
    let files;
    try {
      files = await fsp.readdir(dir, { withFileTypes: true });
    } catch (_error) {
      continue;
    }
    for (const file of files) {
      const match = file.isFile() ? QUARANTINE_NAME.exec(file.name) : null;
      if (!match) continue;
      try {
        const full = path.join(dir, file.name);
        const info = await fsp.lstat(full);
        entries.push({ key: `${site.name}/${match[1]}`, file: full, size: info.size, mtimeMs: info.mtimeMs });
      } catch (_error) {
        // o arada kaldırılmış
      }
      if (entries.length >= QUARANTINE_SCAN_CAP) return entries;
    }
  }
  return entries;
}

/** `days` günden eski karantina dosyalarını siler (en çok `limit`); boşalan site dizinleri kaldırılır. @returns {Promise<{ purged: number, errors: number }>} */
export async function purgeQuarantine(root, days, now = Date.now(), limit = 200) {
  const cutoff = now - days * 24 * 60 * 60 * 1000;
  let purged = 0;
  let errors = 0;
  for (const entry of await listQuarantine(root)) {
    if (purged >= limit) break;
    if (entry.mtimeMs >= cutoff) continue;
    try {
      await fsp.unlink(entry.file);
      purged += 1;
    } catch (error) {
      if (error?.code !== 'ENOENT') errors += 1;
    }
  }
  if (purged > 0) {
    for (const site of await fsp.readdir(path.join(root, QUARANTINE_DIR)).catch(() => [])) {
      await fsp.rmdir(path.join(root, QUARANTINE_DIR, site)).catch(() => {}); // doluysa ENOTEMPTY: kalır
    }
  }
  return { purged, errors };
}

/** Karantinadaki dosyayı yerine geri koyar (yerinde dosya VARSA dokunmaz). @returns {Promise<boolean>} geri konuldu mu */
export async function restoreFromQuarantine(root, entry, now = Date.now()) {
  const destination = pathForKey(root, entry.key);
  try {
    await fsp.lstat(destination);
    return false;
  } catch (error) {
    if (error?.code !== 'ENOENT') throw error;
  }
  await ensureSiteDir(root, entry.key.split('/')[0]);
  await fsp.rename(entry.file, destination);
  try {
    const stamp = new Date(now);
    await fsp.utimes(destination, stamp, stamp);
  } catch (_error) {
    // önemsiz
  }
  return true;
}

export async function removeTempFile(file) {
  try {
    await fsp.unlink(file);
  } catch (_error) {
    // yoksa ya da silinemiyorsa bakım işi 2 saat sonra temizler
  }
}

/** Geçici dosyayı son yola taşır; son yol VARSA ezilmez (EEXIST fırlatır). `link` desteklenmezse COPYFILE_EXCL. */
export async function commitTempFile(tmp, final) {
  try {
    await fsp.link(tmp, final);
  } catch (error) {
    if (error?.code === 'EEXIST') throw error;
    await fsp.copyFile(tmp, final, fs.constants.COPYFILE_EXCL);
  }
  try {
    await fsp.chmod(final, 0o600);
  } catch (_error) {
    // Windows'ta anlamsız olabilir
  }
  await removeTempFile(tmp);
}

/** Geçici dosyayı diske zorla (fsync): ikinci bir tanıtıcıyla, yazma akışı kapandıktan sonra. */
export async function fsyncFile(file) {
  const handle = await fsp.open(file, 'r+');
  try {
    await handle.sync();
  } finally {
    await handle.close();
  }
}

// --- Yükleme alımı -------------------------------------------------------------------------------------------------

/**
 * Akış denetçisi: bayt sayar (bildirilen boyutu AŞARSA hemen 400 DOCUMENT_SIZE_MISMATCH), sha256 hesaplar ve ilk baytlar gelince `onHead(head)` ile
 * ERKEN tür kararı ister (hata fırlatırsa akış kesilir). Bellekte yalnız ilk 16 bayt tutulur.
 */
export class UploadInspector extends Transform {
  constructor({ declaredSize, onHead }) {
    super();
    this.declaredSize = declaredSize;
    this.onHead = onHead;
    this.bytes = 0;
    this.hash = crypto.createHash('sha256');
    this.head = Buffer.alloc(0);
    this.headChecked = false;
  }

  _checkHead() {
    if (this.headChecked) return;
    this.headChecked = true;
    this.onHead(this.head);
  }

  _transform(chunk, _encoding, callback) {
    try {
      this.bytes += chunk.length;
      if (this.bytes > this.declaredSize) {
        throw sizeMismatch();
      }
      this.hash.update(chunk);
      if (!this.headChecked) {
        this.head = Buffer.concat([this.head, chunk.subarray(0, 16 - this.head.length)]);
        if (this.head.length >= 16) this._checkHead();
      }
      callback(null, chunk);
    } catch (error) {
      callback(error);
    }
  }

  _flush(callback) {
    try {
      this._checkHead();
      if (this.bytes !== this.declaredSize) {
        throw sizeMismatch();
      }
      callback();
    } catch (error) {
      callback(error);
    }
  }

  digest() {
    return this.hash.digest('hex');
  }
}

// --- Güvenli okuma ---------------------------------------------------------------------------------------------------

/**
 * İndirme için dosyayı açar: yol anahtardan türetilir; `lstat` ile düz dosya (symlink değil) ve boyut = DB `size_bytes` doğrulanır; mümkünse
 * O_NOFOLLOW ile açılır. Yok / uyuşmaz -> { error: 'missing' }. `subtree` varsayılan `sites`.
 * @returns {Promise<{ handle: import('node:fs').promises.FileHandle, size: number } | { error: 'missing' | 'mismatch' }>}
 */
export async function openStoredFile(root, key, expectedSize, subtree = 'sites') {
  let full;
  try {
    full = pathForKey(root, key, subtree);
  } catch (_error) {
    return { error: 'missing' };
  }
  try {
    const before = await fsp.lstat(full);
    if (!before.isFile() || before.isSymbolicLink()) {
      return { error: 'mismatch' };
    }
    const noFollow = typeof fs.constants.O_NOFOLLOW === 'number' ? fs.constants.O_NOFOLLOW : 0;
    const handle = await fsp.open(full, fs.constants.O_RDONLY | noFollow);
    try {
      const info = await handle.stat();
      if (!info.isFile() || info.size !== Number(expectedSize)) {
        await handle.close();
        return { error: 'mismatch' };
      }
      return { handle, size: info.size };
    } catch (error) {
      await handle.close().catch(() => {});
      throw error;
    }
  } catch (error) {
    if (error?.code === 'ENOENT' || error?.code === 'ELOOP' || error?.code === 'ENOTDIR') {
      return { error: 'missing' };
    }
    throw error;
  }
}

export { SITE_DIR_PATTERN, UUID_PATTERN, isInside };
