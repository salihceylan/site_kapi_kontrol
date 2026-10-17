// Belgeler (Faz 3b-A) yönetici servisi (DB'siz, KATI sahte veritabanı + gerçek geçici dosya sistemi): yaşam döngüsü kuralları, KİLİT SIRASI, dosya silme sırası
// (satır işlemde, dosya COMMIT SONRASI: R11 F7), 40P01'de tek yeniden deneme, kota / sürüm sınırları. Gerçek PostgreSQL doğrulaması: qa_platform_pg.mjs "documents".
import { describe, it, before, after, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import { promises as fsp } from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { pool } from '../src/db.js';
import {
  addVersion,
  deleteDocument,
  deleteVersion,
  purgeDocument,
  restoreDocument,
  updateDocument,
  withDocumentTransaction,
} from '../src/modules/document_service.js';
import { documentLimits } from '../src/modules/document_common.js';
import { ensureSiteDir, pathForKey, resetStorageCheck } from '../src/modules/document_storage.js';

const SITE = 1000000001;
const ACTOR = { user_code: 20001, userCode: 20001, id: 20001, role: 'site_manager', full_name: 'Ayşe Yönetici' };
const limits = documentLimits({});
const KEY_1 = '1000000001/123e4567-e89b-42d3-a456-426614174001';
const KEY_2 = '1000000001/123e4567-e89b-42d3-a456-426614174002';
const norm = (text) => String(text).replace(/\s+/g, ' ').trim();
const ok = (rows = [], rowCount = rows.length) => ({ rows, rowCount });

let handlers;
let log;
let root;
let fail;

function installFakeDb() {
  const run = async (text, params) => {
    const sql = norm(text);
    log.push({ sql, params: params ?? [] });
    if (fail && fail.pattern.test(sql) && fail.times > 0) {
      fail.times -= 1;
      throw Object.assign(new Error('enjekte'), { code: fail.code });
    }
    for (const [pattern, fn] of handlers) {
      if (pattern.test(sql)) return typeof fn === 'function' ? fn(sql, params ?? []) : fn;
    }
    if (/^(BEGIN|COMMIT|ROLLBACK)$/.test(sql) || /^SELECT pg_advisory_xact_lock/.test(sql) || /^(SAVEPOINT|RELEASE SAVEPOINT|ROLLBACK TO SAVEPOINT) /.test(sql) || /^INSERT INTO audit_log/.test(sql)) return ok();
    if (/^SELECT site_code FROM sites WHERE site_code = \$1 FOR KEY SHARE$/.test(sql)) return ok([{ site_code: String(params[0]) }]);
    if (/^SELECT user_code FROM users WHERE user_code = \$1 AND deleted_at IS NULL FOR KEY SHARE$/.test(sql)) return ok([{ user_code: params[0] }]);
    throw new Error(`BEKLENMEYEN SQL (sahte DB katı): ${sql.slice(0, 240)}`);
  };
  pool.query = async (text, params) => run(text, params);
  pool.connect = async () => ({ query: (text, params) => run(text, params), release() {} });
}

const docRow = (over = {}) => ({
  id: '77', status: 'active', category: 'regulation', audience: 'residents', target_type: 'site', target_block_ids: [], target_apartment_ids: [],
  current_version_no: 2, deleted_at: null, ...over,
});
const lockDoc = (row) => [/^SELECT id, status, category, audience, target_type, target_block_ids, target_apartment_ids, current_version_no, deleted_at FROM documents WHERE id = \$1 AND site_code = \$2 FOR UPDATE$/, ok(row ? [row] : [])];
const summaryRow = (over = {}) => ({
  id: '77', title: 't', category: 'regulation', audience: 'residents', target_type: 'site', status: 'active', version_count: 2, download_count: '0',
  created_at: new Date(), updated_at: new Date(), deleted_at: null, days_until_purge: null, cv_version_no: 2, ...over,
});
const summaryQuery = [/^SELECT d\.id, d\.title, d\.category, d\.audience, d\.target_type, d\.status.* WHERE d\.id = \$1 AND d\.site_code = \$2 LIMIT 1$/, () => ok([summaryRow()])];
const sqlOrder = () => log.map((entry) => entry.sql);
const indexOf = (pattern) => sqlOrder().findIndex((sql) => pattern.test(sql));
const code = async (promise) => {
  try {
    await promise;
    return null;
  } catch (error) {
    return `${error.statusCode ?? ''}:${error.code ?? error.message}`;
  }
};

before(async () => {
  root = await fsp.mkdtemp(path.join(os.tmpdir(), 'doc-service-'));
  process.env.DOCUMENTS_DIR = root;
  process.env.DOCUMENTS_MIN_FREE_BYTES = '0';
  resetStorageCheck();
  await ensureSiteDir(root, SITE);
});

after(async () => {
  delete pool.query;
  delete pool.connect;
  delete process.env.DOCUMENTS_DIR;
  delete process.env.DOCUMENTS_MIN_FREE_BYTES;
  await fsp.rm(root, { recursive: true, force: true });
});

beforeEach(() => {
  handlers = [];
  log = [];
  fail = null;
  installFakeDb();
});

const writeStored = async (key, content = 'x') => fsp.writeFile(pathForKey(root, key), content);
const exists = (key) => fsp.stat(pathForKey(root, key)).then(() => true, () => false);

describe('kilit sırası ve geçici çakışma', () => {
  it('her yazma: BEGIN -> sites FOR KEY SHARE -> users FOR KEY SHARE (deleted_at IS NULL) -> documents FOR UPDATE -> ... -> COMMIT', async () => {
    handlers.push(lockDoc(docRow()), [/^UPDATE documents SET status = 'deleted'/, ok()], [/^SELECT COUNT\(\*\)::INTEGER AS n FROM announcement_attachments aa/, ok([{ n: 0 }])], summaryQuery);
    await deleteDocument({ siteCode: SITE, rawId: '77', actor: ACTOR, body: {}, limits });
    const order = sqlOrder();
    assert.equal(order[0], 'BEGIN');
    assert.ok(indexOf(/FROM sites WHERE site_code = \$1 FOR KEY SHARE/) < indexOf(/FROM users WHERE user_code = \$1 AND deleted_at IS NULL FOR KEY SHARE/));
    assert.ok(indexOf(/FROM users WHERE user_code = \$1 AND deleted_at IS NULL FOR KEY SHARE/) < indexOf(/FROM documents WHERE id = \$1 AND site_code = \$2 FOR UPDATE/));
    assert.ok(indexOf(/FROM documents WHERE id = \$1 AND site_code = \$2 FOR UPDATE/) < indexOf(/UPDATE documents SET status = 'deleted'/));
    assert.ok(order.includes('COMMIT'));
  });

  it("40P01 (deadlock) TEK SEFER baştan denenir; ikinci kez de olursa hata fırlar; başka hata yeniden denenmez", async () => {
    let calls = 0;
    const result = await withDocumentTransaction(SITE, async () => {
      calls += 1;
      if (calls === 1) throw Object.assign(new Error('deadlock'), { code: '40P01' });
      return 'tamam';
    });
    assert.equal(result, 'tamam');
    assert.equal(calls, 2);
    let always = 0;
    await assert.rejects(withDocumentTransaction(SITE, async () => { always += 1; throw Object.assign(new Error('deadlock'), { code: '40P01' }); }), { code: '40P01' });
    assert.equal(always, 2, 'tam iki deneme');
    let once = 0;
    await assert.rejects(withDocumentTransaction(SITE, async () => { once += 1; throw Object.assign(new Error('x'), { code: '23505' }); }), { code: '23505' });
    assert.equal(once, 1);
    assert.equal(sqlOrder().filter((sql) => sql === 'ROLLBACK').length, 4, 'her başarısız deneme geri alınır');
  });

  it('site yoksa 404 SITE_NOT_FOUND ve kullanıcı / belge kilidi ALINMAZ', async () => {
    handlers.push([/^SELECT site_code FROM sites WHERE site_code = \$1 FOR KEY SHARE$/, ok()]);
    assert.equal(await code(deleteDocument({ siteCode: SITE, rawId: '77', actor: ACTOR, body: {}, limits })), '404:SITE_NOT_FOUND');
    assert.ok(!sqlOrder().some((sql) => /FROM users|FROM documents/.test(sql)));
  });
});

describe('silme', () => {
  it('yayındaki duyuruya ekli belge onaysız silinemez (409 DOCUMENT_IN_USE + attachments_count); onayla silinir', async () => {
    handlers.push(lockDoc(docRow()), [/^SELECT COUNT\(\*\)::INTEGER AS n FROM announcement_attachments aa/, ok([{ n: 2 }])], [/^UPDATE documents SET status = 'deleted'/, ok()], summaryQuery);
    assert.equal(await code(deleteDocument({ siteCode: SITE, rawId: '77', actor: ACTOR, body: {}, limits })), '409:DOCUMENT_IN_USE');
    assert.ok(!sqlOrder().some((sql) => /^UPDATE documents SET status = 'deleted'/.test(sql)), 'reddedilince yazma yok');
    log.length = 0;
    const done = await deleteDocument({ siteCode: SITE, rawId: '77', actor: ACTOR, body: { confirm: true }, limits });
    assert.equal(done.document.id, 77);
    const update = log.find((entry) => /^UPDATE documents SET status = 'deleted'/.test(entry.sql));
    assert.deepEqual(update.params, [77, SITE, 20001], 'site_code ve silen kullanıcı');
    const audit = log.find((entry) => /^INSERT INTO audit_log/.test(entry.sql));
    assert.equal(audit.params[3], 'document.deleted');
    assert.equal(JSON.parse(audit.params[7]).attachments_count, 2);
  });

  it('zaten silinmiş 409; olmayan / başka sitenin belgesi 404; geçersiz kimlik 404', async () => {
    handlers.push(lockDoc(docRow({ status: 'deleted', deleted_at: new Date() })));
    assert.equal(await code(deleteDocument({ siteCode: SITE, rawId: '77', actor: ACTOR, body: {}, limits })), '409:INVALID_STATE');
    handlers = [lockDoc(null)];
    assert.equal(await code(deleteDocument({ siteCode: SITE, rawId: '78', actor: ACTOR, body: {}, limits })), '404:DOCUMENT_NOT_FOUND');
    assert.equal(await code(deleteDocument({ siteCode: SITE, rawId: 'abc', actor: ACTOR, body: {}, limits })), '404:DOCUMENT_NOT_FOUND');
    assert.equal(log.find((entry) => /FOR UPDATE$/.test(entry.sql) && /FROM documents/.test(entry.sql)).params[1], SITE, 'her sorguda site_code (IDOR yok)');
  });

  it('yüklemesi bitmemiş (pending) belge DELETE ile İPTAL edilir: dosyalar silinir, satır kalkar, audit yazılmaz', async () => {
    await writeStored(KEY_1);
    handlers.push(lockDoc(docRow({ status: 'pending', current_version_no: null })), [/^SELECT storage_key FROM document_versions WHERE document_id = \$1$/, ok([{ storage_key: KEY_1 }])], [/^DELETE FROM documents WHERE id = \$1$/, ok()]);
    const result = await deleteDocument({ siteCode: SITE, rawId: '77', actor: ACTOR, body: {}, limits });
    assert.deepEqual(result, { deleted: true, cancelled: true });
    assert.equal(await exists(KEY_1), false);
    assert.ok(!sqlOrder().some((sql) => /^INSERT INTO audit_log/.test(sql)));
  });
});

describe('geri alma ve kalıcı silme', () => {
  it('geri alma: yalnız silinmiş; saklama süresi dolmuşsa 404; ready sürüm yoksa 409; başarıda deleted_at / deleted_by temizlenir', async () => {
    handlers.push(lockDoc(docRow({ status: 'active' })));
    assert.equal(await code(restoreDocument({ siteCode: SITE, rawId: '77', actor: ACTOR, limits })), '409:INVALID_STATE');
    handlers = [lockDoc(docRow({ status: 'deleted', deleted_at: new Date() })), [/^SELECT \(deleted_at < NOW\(\) - make_interval\(days => \$2::INTEGER\)\) AS expired FROM documents WHERE id = \$1$/, ok([{ expired: true }])]];
    assert.equal(await code(restoreDocument({ siteCode: SITE, rawId: '77', actor: ACTOR, limits })), '404:DOCUMENT_NOT_FOUND');
    handlers = [
      lockDoc(docRow({ status: 'deleted', deleted_at: new Date() })),
      [/^SELECT \(deleted_at < NOW\(\)/, ok([{ expired: false }])],
      [/^SELECT 1 FROM document_versions WHERE document_id = \$1 AND version_no = \$2 AND status = 'ready' LIMIT 1$/, ok()],
    ];
    assert.equal(await code(restoreDocument({ siteCode: SITE, rawId: '77', actor: ACTOR, limits })), '409:INVALID_STATE');
    handlers = [
      lockDoc(docRow({ status: 'deleted', deleted_at: new Date() })),
      [/^SELECT \(deleted_at < NOW\(\)/, ok([{ expired: false }])],
      [/^SELECT 1 FROM document_versions WHERE document_id = \$1 AND version_no = \$2 AND status = 'ready' LIMIT 1$/, ok([{ x: 1 }])],
      [/^UPDATE documents SET status = 'active', deleted_at = NULL, deleted_by = NULL/, ok()],
      summaryQuery,
    ];
    const restored = await restoreDocument({ siteCode: SITE, rawId: '77', actor: ACTOR, limits });
    assert.equal(restored.document.id, 77);
    assert.equal(log.find((entry) => /^INSERT INTO audit_log/.test(entry.sql)).params[3], 'document.restored');
  });

  it('kalıcı silme: onay ister (400 CONFIRM_REQUIRED, DB\'ye gitmeden); yalnız silinmiş belge; satır işlemde silinir, dosyalar COMMIT\'ten SONRA silinir; audit yalnız sayı / boyut', async () => {
    assert.equal(await code(purgeDocument({ siteCode: SITE, rawId: '77', actor: ACTOR, body: {} })), '400:CONFIRM_REQUIRED');
    assert.equal(log.length, 0, 'onaysız istek DB\'ye hiç gitmez');
    handlers.push(lockDoc(docRow({ status: 'active' })));
    assert.equal(await code(purgeDocument({ siteCode: SITE, rawId: '77', actor: ACTOR, body: { confirm: true } })), '409:INVALID_STATE');
    await writeStored(KEY_1, 'bir');
    await writeStored(KEY_2, 'iki');
    let filesLeftAtRowDelete = -1;
    let filesLeftAtCommit = -1;
    handlers = [
      lockDoc(docRow({ status: 'deleted', deleted_at: new Date() })),
      [/^SELECT storage_key, size_bytes FROM document_versions WHERE document_id = \$1$/, ok([{ storage_key: KEY_1, size_bytes: '3' }, { storage_key: KEY_2, size_bytes: '3' }])],
      [
        /^DELETE FROM documents WHERE id = \$1$/,
        async () => {
          filesLeftAtRowDelete = [await exists(KEY_1), await exists(KEY_2)].filter(Boolean).length;
          return ok();
        },
      ],
      [
        /^COMMIT$/,
        async () => {
          filesLeftAtCommit = [await exists(KEY_1), await exists(KEY_2)].filter(Boolean).length;
          return ok();
        },
      ],
    ];
    const result = await purgeDocument({ siteCode: SITE, rawId: '77', actor: ACTOR, body: { confirm: true } });
    assert.deepEqual(result, { purged: true });
    assert.equal(filesLeftAtRowDelete, 2, 'satır silinirken dosyalar HENÜZ yerinde (işlem sonradan başarısız olabilir)');
    assert.equal(filesLeftAtCommit, 2, 'COMMIT anında da yerinde');
    assert.equal(await exists(KEY_1), false, 'COMMIT\'ten sonra silindi');
    assert.equal(await exists(KEY_2), false);
    const audit = log.find((entry) => /^INSERT INTO audit_log/.test(entry.sql));
    const details = JSON.parse(audit.params[7]);
    assert.equal(audit.params[3], 'document.purged');
    assert.deepEqual(Object.keys(details).sort(), ['audience', 'category', 'size_bytes', 'version_count']);
    assert.equal(details.version_count, 2);
    assert.equal(details.size_bytes, 6);
  });

  it('dosya silinemezse (ENOENT dışı hata) kalıcı silme YİNE başarılıdır: satır gitmiştir (COMMIT), dosya yetim kalır, günlüğe yalnız hata KODU yazılır (ad / yol yok)', async () => {
    const stuck = '1000000001/123e4567-e89b-42d3-a456-426614174099';
    await fsp.mkdir(pathForKey(root, stuck)); // dosya yerine dizin: unlink başarısız
    handlers.push(
      lockDoc(docRow({ status: 'deleted', deleted_at: new Date() })),
      [/^SELECT storage_key, size_bytes FROM document_versions WHERE document_id = \$1$/, ok([{ storage_key: stuck, size_bytes: '3' }])],
      [/^DELETE FROM documents WHERE id = \$1$/, ok()],
    );
    const lines = [];
    const realError = console.error;
    console.error = (...args) => lines.push(args.join(' '));
    let result;
    try {
      result = await purgeDocument({ siteCode: SITE, rawId: '77', actor: ACTOR, body: { confirm: true } });
    } finally {
      console.error = realError;
    }
    assert.deepEqual(result, { purged: true });
    assert.ok(sqlOrder().some((sql) => /^DELETE FROM documents/.test(sql)) && sqlOrder().includes('COMMIT') && !sqlOrder().includes('ROLLBACK'));
    assert.ok(lines.some((line) => /dosya silinemedi/.test(line) && /E[A-Z]+/.test(line)), lines.join('\n'));
    assert.ok(!lines.join('\n').includes('426614174099'), 'günlükte dosya adı yok');
    await fsp.rmdir(pathForKey(root, stuck));
  });

  it('R11 F7: COMMIT BAŞARISIZ olursa (bağlantı koptu vb.) DOSYALAR SİLİNMEZ ve işlem geri alınır — `ready` sürüm satırı dosyasız kalmaz', async () => {
    await writeStored(KEY_1, 'bir');
    handlers.push(
      lockDoc(docRow({ status: 'deleted', deleted_at: new Date() })),
      [/^SELECT storage_key, size_bytes FROM document_versions WHERE document_id = \$1$/, ok([{ storage_key: KEY_1, size_bytes: '3' }])],
      [/^DELETE FROM documents WHERE id = \$1$/, ok()],
    );
    fail = { pattern: /^COMMIT$/, times: 1, code: '57P01' };
    assert.equal(await code(purgeDocument({ siteCode: SITE, rawId: '77', actor: ACTOR, body: { confirm: true } })), ':57P01');
    assert.equal(await exists(KEY_1), true, 'dosya yerinde');
    assert.ok(sqlOrder().includes('ROLLBACK'));
  });
});

describe('sürümler', () => {
  const versionLock = [/^SELECT id, status, storage_key, size_bytes FROM document_versions WHERE document_id = \$1 AND version_no = \$2 FOR UPDATE$/];

  it('sürüm silme: olmayan 404; son ready sürüm 409; güncel silinirse en yüksek kalan ready güncel olur; dosya hemen silinir; version_count = kalan', async () => {
    handlers.push(lockDoc(docRow({ current_version_no: 3 })), [...versionLock, ok()]);
    assert.equal(await code(deleteVersion({ siteCode: SITE, rawId: '77', rawVersionNo: '9', actor: ACTOR, limits })), '404:DOCUMENT_VERSION_NOT_FOUND');
    handlers = [lockDoc(docRow({ current_version_no: 1 })), [...versionLock, ok([{ id: '1', status: 'ready', storage_key: KEY_1, size_bytes: '3' }])], [/^SELECT version_no FROM document_versions WHERE document_id = \$1 AND status = 'ready' AND version_no <> \$2 ORDER BY version_no DESC$/, ok()]];
    assert.equal(await code(deleteVersion({ siteCode: SITE, rawId: '77', rawVersionNo: '1', actor: ACTOR, limits })), '409:INVALID_STATE');
    await writeStored(KEY_1);
    handlers = [
      lockDoc(docRow({ current_version_no: 3 })),
      [...versionLock, ok([{ id: '3', status: 'ready', storage_key: KEY_1, size_bytes: '3' }])],
      [/^SELECT version_no FROM document_versions WHERE document_id = \$1 AND status = 'ready' AND version_no <> \$2 ORDER BY version_no DESC$/, ok([{ version_no: 2 }, { version_no: 1 }])],
      [/^DELETE FROM document_versions WHERE id = \$1$/, ok()],
      [/^UPDATE documents SET version_count = \$2, current_version_no = \$3, updated_at = NOW\(\) WHERE id = \$1$/, ok()],
      summaryQuery,
    ];
    await deleteVersion({ siteCode: SITE, rawId: '77', rawVersionNo: '3', actor: ACTOR, limits });
    assert.equal(await exists(KEY_1), false);
    const update = log.find((entry) => /^UPDATE documents SET version_count/.test(entry.sql));
    assert.deepEqual(update.params, [77, 2, 2], 'version_count = 2 kalan, güncel = 2');
    const audit = JSON.parse(log.find((entry) => /^INSERT INTO audit_log/.test(entry.sql)).params[7]);
    assert.deepEqual(audit, { version_no: 3, size_bytes: 3, was_current: true });
  });

  it('silinmiş belgenin sürümü silinemez (önce geri alınır): 409', async () => {
    handlers.push(lockDoc(docRow({ status: 'deleted', deleted_at: new Date() })));
    assert.equal(await code(deleteVersion({ siteCode: SITE, rawId: '77', rawVersionNo: '1', actor: ACTOR, limits })), '409:INVALID_STATE');
  });

  it('yeni sürüm: belge active olmalı (409); sürüm üst sınırı 20 (409 DOCUMENT_VERSION_LIMIT); kota (409); bekleyen sürüm varsa YENİLENİR (aynı numara, yeni anahtar, eski dosya silinir)', async () => {
    const body = { file: { name: 'sürüm.pdf', size: 1000 } };
    const capacity = [
      [/^SELECT \(SELECT COALESCE\(SUM\(size_bytes\), 0\)::BIGINT FROM document_versions/, () => ok([{ used_bytes: '0', document_count: 1 }])],
      [/^SELECT COUNT\(\*\)::INTEGER AS n FROM document_versions WHERE uploaded_by = \$1 AND status = 'uploading'/, ok([{ n: 0 }])],
    ];
    handlers.push([/^SELECT id, status FROM documents WHERE id = \$1 AND site_code = \$2 FOR UPDATE$/, ok([{ id: '77', status: 'pending' }])]);
    assert.equal(await code(addVersion({ siteCode: SITE, rawId: '77', actor: ACTOR, body, limits })), '409:INVALID_STATE');

    handlers = [
      [/^SELECT id, status FROM documents WHERE id = \$1 AND site_code = \$2 FOR UPDATE$/, ok([{ id: '77', status: 'active' }])],
      [/^SELECT id, version_no, storage_key FROM document_versions WHERE document_id = \$1 AND status = 'uploading'/, ok()],
      [/^SELECT COUNT\(\*\)::INTEGER AS n FROM document_versions WHERE document_id = \$1$/, ok([{ n: 20 }])],
      ...capacity,
    ];
    assert.equal(await code(addVersion({ siteCode: SITE, rawId: '77', actor: ACTOR, body, limits })), '409:DOCUMENT_VERSION_LIMIT');

    handlers = [
      [/^SELECT id, status FROM documents WHERE id = \$1 AND site_code = \$2 FOR UPDATE$/, ok([{ id: '77', status: 'active' }])],
      [/^SELECT id, version_no, storage_key FROM document_versions WHERE document_id = \$1 AND status = 'uploading'/, ok()],
      [/^SELECT COUNT\(\*\)::INTEGER AS n FROM document_versions WHERE document_id = \$1$/, ok([{ n: 2 }])],
      [/^SELECT \(SELECT COALESCE\(SUM\(size_bytes\), 0\)::BIGINT FROM document_versions/, ok([{ used_bytes: String(209715200 - 500), document_count: 1 }])],
    ];
    assert.equal(await code(addVersion({ siteCode: SITE, rawId: '77', actor: ACTOR, body, limits })), '409:DOCUMENT_QUOTA_EXCEEDED');

    // bekleyen sürüm yenileme: 20 sürüm dolu olsa bile bekleyeni yenilemek yeni satır eklemez
    await writeStored(KEY_2, 'eski bekleyen');
    const created = new Date('2026-10-17T10:00:00.000Z');
    handlers = [
      [/^SELECT id, status FROM documents WHERE id = \$1 AND site_code = \$2 FOR UPDATE$/, ok([{ id: '77', status: 'active' }])],
      [/^SELECT id, version_no, storage_key FROM document_versions WHERE document_id = \$1 AND status = 'uploading'/, ok([{ id: '600', version_no: 5, storage_key: KEY_2 }])],
      [/^SELECT COUNT\(\*\)::INTEGER AS n FROM document_versions WHERE document_id = \$1$/, ok([{ n: 20 }])],
      ...capacity,
      [/^UPDATE document_versions SET storage_key = \$2, display_name = \$3/, ok()],
      summaryQuery,
      [/^SELECT version_no, display_name, mime_type, declared_size_bytes, size_bytes, status, created_at FROM document_versions/, ok([{ version_no: 5, display_name: 'sürüm.pdf', mime_type: 'application/pdf', declared_size_bytes: '1000', size_bytes: '1000', status: 'uploading', created_at: created }])],
    ];
    const result = await addVersion({ siteCode: SITE, rawId: '77', actor: ACTOR, body, limits });
    assert.equal(result.version.version_no, 5);
    assert.equal(result.upload.path, `/manager/sites/${SITE}/documents/77/versions/5/content`);
    const update = log.find((entry) => /^UPDATE document_versions SET storage_key/.test(entry.sql));
    assert.notEqual(update.params[1], KEY_2, 'yeni anahtar');
    assert.match(update.params[1], /^1000000001\/[0-9a-f-]{36}$/);
    assert.equal(await exists(KEY_2), false, 'eski bekleyen dosya silindi');
    assert.ok(!sqlOrder().some((sql) => /^INSERT INTO document_versions/.test(sql)), 'yeni satır eklenmedi');
  });
});

describe('düzenleme', () => {
  it('sakinlere açık olmaktan çıkan belge: yayındaki duyuruya ekliyse onay ister (409 DOCUMENT_IN_USE); onayla taslak / zamanlanmış duyurulardan ÇIKARILIR; hedef site + boş diziye döner', async () => {
    handlers.push(
      lockDoc(docRow({ audience: 'residents', target_type: 'blocks', target_block_ids: ['5'] })),
      [/^SELECT COUNT\(\*\)::INTEGER AS n FROM announcement_attachments aa/, ok([{ n: 1 }])],
    );
    assert.equal(await code(updateDocument({ siteCode: SITE, rawId: '77', actor: ACTOR, body: { audience: 'board' }, limits })), '409:DOCUMENT_IN_USE');
    assert.ok(!sqlOrder().some((sql) => /^UPDATE documents SET/.test(sql)));
    log.length = 0;
    handlers = [
      lockDoc(docRow({ audience: 'residents', target_type: 'blocks', target_block_ids: ['5'] })),
      [/^SELECT COUNT\(\*\)::INTEGER AS n FROM announcement_attachments aa/, ok([{ n: 1 }])],
      [/^DELETE FROM announcement_attachments aa USING announcements a/, ok([{ announcement_id: '31' }, { announcement_id: '32' }])],
      [/^UPDATE documents SET /, ok()],
      [/^SELECT d\.id, d\.title, .* WHERE d\.id = \$1 AND d\.site_code = \$2 LIMIT 1$/, () => ok([summaryRow({ audience: 'board', description: null, target_block_ids: [], target_apartment_ids: [] })])],
      [/^SELECT v\.version_no, v\.display_name/, ok()],
      [/^SELECT a\.id, a\.status FROM announcement_attachments aa/, ok()],
    ];
    const result = await updateDocument({ siteCode: SITE, rawId: '77', actor: ACTOR, body: { audience: 'board', confirm: true }, limits });
    assert.equal(result.document.audience, 'board');
    const update = log.find((entry) => /^UPDATE documents SET /.test(entry.sql));
    assert.match(update.sql, /audience = \$3, target_type = \$4, target_block_ids = \$5::BIGINT\[\], target_apartment_ids = \$6::BIGINT\[\], updated_at = NOW\(\)/);
    assert.deepEqual(update.params.slice(2), ['board', 'site', [], []]);
    const audits = log.filter((entry) => /^INSERT INTO audit_log/.test(entry.sql)).map((entry) => entry.params[3]);
    assert.deepEqual(audits, ['document.updated', 'document.detached', 'document.detached']);
    const updatedDetails = JSON.parse(log.find((entry) => /^INSERT INTO audit_log/.test(entry.sql)).params[7]);
    assert.deepEqual(updatedDetails, { fields: ['audience', 'target'], audience: { from: 'residents', to: 'board' }, target_type: { from: 'blocks', to: 'site' } });
  });

  it('değişiklik yoksa UPDATE gitmez; başlık / açıklama DEĞERİ audit\'e girmez (yalnız alan adı); yalnız yayındaki belge düzenlenir', async () => {
    handlers.push(lockDoc(docRow({ status: 'deleted', deleted_at: new Date() })));
    assert.equal(await code(updateDocument({ siteCode: SITE, rawId: '77', actor: ACTOR, body: { title: 'Yeni' }, limits })), '409:INVALID_STATE');
    log.length = 0;
    handlers = [
      lockDoc(docRow()),
      [/^UPDATE documents SET /, ok()],
      summaryQuery,
      [/^SELECT v\.version_no/, ok()],
      [/^SELECT a\.id, a\.status FROM announcement_attachments aa/, ok()],
    ];
    handlers.push([/^SELECT d\.id, d\.title, .* WHERE d\.id = \$1 AND d\.site_code = \$2 LIMIT 1$/, ok([summaryRow()])]);
    await updateDocument({ siteCode: SITE, rawId: '77', actor: ACTOR, body: { title: 'GIZLI-BASLIK', description: 'GIZLI-ACIKLAMA' }, limits });
    const audit = log.find((entry) => /^INSERT INTO audit_log/.test(entry.sql));
    assert.deepEqual(JSON.parse(audit.params[7]), { fields: ['title', 'description'] });
    assert.ok(!JSON.stringify(log.filter((entry) => /audit_log/.test(entry.sql))).includes('GIZLI'));
    // kategori aynı + kitle aynı + hedef aynı -> alan yok -> UPDATE yok
    log.length = 0;
    handlers = [lockDoc(docRow())];
    await updateDocument({ siteCode: SITE, rawId: '77', actor: ACTOR, body: { category: 'regulation' }, limits }).catch(() => {});
    assert.ok(!sqlOrder().some((sql) => /^UPDATE documents SET/.test(sql)));
  });
});

describe('dosya silme COMMIT SONRASI (R11 F7)', () => {
  const versionLock = [/^SELECT id, status, storage_key, size_bytes FROM document_versions WHERE document_id = \$1 AND version_no = \$2 FOR UPDATE$/];
  const readyOthers = [/^SELECT version_no FROM document_versions WHERE document_id = \$1 AND status = 'ready' AND version_no <> \$2 ORDER BY version_no DESC$/, ok([{ version_no: 2 }])];

  it('sürüm silme: dosya satır silindikten ve COMMIT\'ten SONRA silinir; COMMIT başarısızsa dosya YERİNDE kalır (ready satır dosyasız kalmaz)', async () => {
    await writeStored(KEY_1);
    let atCommit = -1;
    handlers.push(
      lockDoc(docRow({ current_version_no: 3 })),
      [...versionLock, ok([{ id: '3', status: 'ready', storage_key: KEY_1, size_bytes: '3' }])],
      readyOthers,
      [/^DELETE FROM document_versions WHERE id = \$1$/, ok()],
      [/^UPDATE documents SET version_count/, ok()],
      [/^COMMIT$/, async () => { atCommit = (await exists(KEY_1)) ? 1 : 0; return ok(); }],
      summaryQuery,
    );
    await deleteVersion({ siteCode: SITE, rawId: '77', rawVersionNo: '3', actor: ACTOR, limits });
    assert.equal(atCommit, 1, 'COMMIT anında dosya henüz yerinde');
    assert.equal(await exists(KEY_1), false, 'COMMIT\'ten sonra silindi');

    await writeStored(KEY_1);
    log = [];
    handlers = [
      lockDoc(docRow({ current_version_no: 3 })),
      [...versionLock, ok([{ id: '3', status: 'ready', storage_key: KEY_1, size_bytes: '3' }])],
      readyOthers,
      [/^DELETE FROM document_versions WHERE id = \$1$/, ok()],
      [/^UPDATE documents SET version_count/, ok()],
    ];
    fail = { pattern: /^COMMIT$/, times: 1, code: '57P01' };
    assert.equal(await code(deleteVersion({ siteCode: SITE, rawId: '77', rawVersionNo: '3', actor: ACTOR, limits })), ':57P01');
    assert.equal(await exists(KEY_1), true, 'COMMIT başarısız: dosya silinmedi');
    assert.ok(sqlOrder().includes('ROLLBACK'));
  });

  it('bekleyen (uploading) sürümü silme ve pending belge iptali: dosya COMMIT sonrası; COMMIT başarısızsa yerinde', async () => {
    await writeStored(KEY_1);
    handlers.push(lockDoc(docRow({ current_version_no: 1 })), [...versionLock, ok([{ id: '4', status: 'uploading', storage_key: KEY_1, size_bytes: '0' }])], [/^DELETE FROM document_versions WHERE id = \$1$/, ok()], summaryQuery);
    fail = { pattern: /^COMMIT$/, times: 1, code: '57P01' };
    assert.equal(await code(deleteVersion({ siteCode: SITE, rawId: '77', rawVersionNo: '4', actor: ACTOR, limits })), ':57P01');
    assert.equal(await exists(KEY_1), true);
    fail = null;
    await deleteVersion({ siteCode: SITE, rawId: '77', rawVersionNo: '4', actor: ACTOR, limits });
    assert.equal(await exists(KEY_1), false);

    await writeStored(KEY_2);
    handlers = [lockDoc(docRow({ status: 'pending', current_version_no: null })), [/^SELECT storage_key FROM document_versions WHERE document_id = \$1$/, ok([{ storage_key: KEY_2 }])], [/^DELETE FROM documents WHERE id = \$1$/, ok()]];
    fail = { pattern: /^COMMIT$/, times: 1, code: '57P01' };
    assert.equal(await code(deleteDocument({ siteCode: SITE, rawId: '77', actor: ACTOR, body: {}, limits })), ':57P01');
    assert.equal(await exists(KEY_2), true, 'iptal işlemi geri alındı: dosya yerinde');
    fail = null;
    assert.deepEqual(await deleteDocument({ siteCode: SITE, rawId: '77', actor: ACTOR, body: {}, limits }), { deleted: true, cancelled: true });
    assert.equal(await exists(KEY_2), false);
  });

  it('40P01 ile başarısız olan deneme ertelenmiş silmelerini ATAR: dosya yeniden denemede de yerindedir, yalnız BAŞARILI denemeden sonra silinir', async () => {
    await writeStored(KEY_1);
    let attempts = 0;
    let presentDuringRetry = null;
    await withDocumentTransaction(SITE, async (_client, tx) => {
      attempts += 1;
      tx.deferUnlink([{ storage_key: KEY_1 }]);
      if (attempts === 1) throw Object.assign(new Error('deadlock'), { code: '40P01' });
      presentDuringRetry = await exists(KEY_1);
    });
    assert.equal(attempts, 2);
    assert.equal(presentDuringRetry, true, 'başarısız denemenin silmesi uygulanmadı');
    assert.equal(await exists(KEY_1), false, 'başarılı denemeden sonra silindi');
  });

  it('iş hatası (ör. 409) ertelenmiş silmeleri uygulamaz; olmayan dosya (ENOENT) sessizce yok sayılır', async () => {
    await writeStored(KEY_1);
    await assert.rejects(
      withDocumentTransaction(SITE, async (_client, tx) => {
        tx.deferUnlink([{ storage_key: KEY_1 }]);
        throw Object.assign(new Error('iş kuralı'), { code: 'INVALID_STATE' });
      }),
      { code: 'INVALID_STATE' },
    );
    assert.equal(await exists(KEY_1), true);
    await withDocumentTransaction(SITE, async (_client, tx) => {
      tx.deferUnlink([{ storage_key: KEY_1 }, { storage_key: KEY_2 }]); // KEY_2 hiç yazılmadı (ENOENT)
    });
    assert.equal(await exists(KEY_1), false);
  });

  it('onUnlinkFailure geri çağrısı silinemeyen her dosya için çağrılır; geri çağrı hata verse bile istek BAŞARILI kalır', async () => {
    const stuck = '1000000001/123e4567-e89b-42d3-a456-426614174098';
    await fsp.mkdir(pathForKey(root, stuck));
    const realError = console.error;
    console.error = () => {};
    let failures = 0;
    try {
      const result = await withDocumentTransaction(
        SITE,
        async (_client, tx) => {
          tx.deferUnlink([{ storage_key: stuck }]);
          return 'tamam';
        },
        { onUnlinkFailure: () => { failures += 1; throw new Error('geri çağrı hatası'); } },
      );
      assert.equal(result, 'tamam');
    } finally {
      console.error = realError;
    }
    assert.equal(failures, 1);
    await fsp.rmdir(pathForKey(root, stuck));
  });
});
