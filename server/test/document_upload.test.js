// Belgeler (Faz 3b-A) yükleme son adımı (DB'siz): commitUploadedFile — son yolda dosya varsa ASLA silinip ezilmez (R9 F2).
import { describe, it, before, after, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import { promises as fsp } from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { commitUploadedFile } from '../src/modules/document_upload.js';

const KEY = '1000000001/123e4567-e89b-42d3-a456-426614174000';

let dir;
let tmp;
let final;

before(async () => {
  dir = await fsp.mkdtemp(path.join(os.tmpdir(), 'doc-upload-'));
});
after(async () => {
  await fsp.rm(dir, { recursive: true, force: true });
});
beforeEach(async () => {
  await fsp.rm(dir, { recursive: true, force: true });
  await fsp.mkdir(path.join(dir, 'sites', '1000000001'), { recursive: true });
  await fsp.mkdir(path.join(dir, '_tmp'), { recursive: true });
  tmp = path.join(dir, '_tmp', 'yeni.part');
  final = path.join(dir, 'sites', KEY);
  await fsp.writeFile(tmp, 'YENI-ICERIK');
});

const exists = (file) => fsp.stat(file).then(() => true, () => false);
const stateOf = (row) => {
  const calls = [];
  const loadState = async (versionId) => {
    calls.push(versionId);
    return row;
  };
  return { loadState, calls };
};

describe('commitUploadedFile', () => {
  it('son yol boşsa: bağlanır, geçici dosya kaldırılır, DB durumuna HİÇ bakılmaz', async () => {
    const { loadState, calls } = stateOf(null);
    await commitUploadedFile({ tmp, final, versionId: 501, key: KEY, loadState });
    assert.equal(await fsp.readFile(final, 'utf8'), 'YENI-ICERIK');
    assert.equal(await exists(tmp), false);
    assert.deepEqual(calls, []);
  });

  it('son yolda dosya var + sürüm ready -> 409 UPLOAD_ALREADY_COMPLETED; hazır dosya DEĞİŞMEZ, geçici dosya çağırana bırakılır', async () => {
    await fsp.writeFile(final, 'HAZIR');
    const { loadState, calls } = stateOf({ status: 'ready', storage_key: KEY });
    await assert.rejects(commitUploadedFile({ tmp, final, versionId: 501, key: KEY, loadState }), { statusCode: 409, code: 'UPLOAD_ALREADY_COMPLETED' });
    assert.deepEqual(calls, [501]);
    assert.equal(await fsp.readFile(final, 'utf8'), 'HAZIR');
    assert.equal(await exists(tmp), true, 'geçici dosyayı çağıran temizler (finally)');
  });

  it('son yolda dosya var + sürüm uploading -> artık dosya ATOMİK (rename) değiştirilir; silme penceresi yok', async () => {
    await fsp.writeFile(final, 'ESKI-ARTIK');
    const { loadState } = stateOf({ status: 'uploading', storage_key: KEY });
    await commitUploadedFile({ tmp, final, versionId: 501, key: KEY, loadState });
    assert.equal(await fsp.readFile(final, 'utf8'), 'YENI-ICERIK');
    assert.equal(await exists(tmp), false);
  });

  it('son yolda dosya var ama sürüm satırı yok ya da depolama anahtarı başka -> 404 DOCUMENT_VERSION_NOT_FOUND; dosyaya dokunulmaz', async () => {
    for (const row of [null, { status: 'uploading', storage_key: '1000000001/aaaaaaaa-e89b-42d3-a456-426614174000' }, { status: 'ready', storage_key: 'baska' }]) {
      await fsp.writeFile(final, 'BASKASININ');
      const { loadState } = stateOf(row);
      await assert.rejects(commitUploadedFile({ tmp, final, versionId: 501, key: KEY, loadState }), { statusCode: 404, code: 'DOCUMENT_VERSION_NOT_FOUND' });
      assert.equal(await fsp.readFile(final, 'utf8'), 'BASKASININ');
    }
  });

  it('EEXIST dışındaki hata (ör. son dizin yok) olduğu gibi yükselir; DB\'ye bakılmaz', async () => {
    const { loadState, calls } = stateOf({ status: 'uploading', storage_key: KEY });
    const missing = path.join(dir, 'sites', 'yok-dizin', 'dosya');
    await assert.rejects(commitUploadedFile({ tmp, final: missing, versionId: 501, key: KEY, loadState }), (error) => error.code === 'ENOENT');
    assert.deepEqual(calls, []);
  });
});
