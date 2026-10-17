// Belgeler (Faz 3b-A) disk depolaması (DB'siz): kök çözümleme + öz-denetim, anahtar / yol güvenliği (traversal, symlink), yazılmaz-silinmez son adım,
// akış denetçisi (boyut, sha256, erken karar), güvenli okuma. Gerçek geçici dizinlerde çalışır.
import { describe, it, before, after } from 'node:test';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import { promises as fsp } from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { Readable } from 'node:stream';
import { pipeline } from 'node:stream/promises';
import {
  QUARANTINE_DIR,
  REPO_ROOT,
  STORAGE_KEY_PATTERN,
  UploadInspector,
  checkStorage,
  commitTempFile,
  ensureSiteDir,
  freeBytes,
  fsyncFile,
  listQuarantine,
  newStorageKey,
  openStoredFile,
  pathForKey,
  purgeQuarantine,
  quarantineStoredFile,
  removeStoredFile,
  resetStorageCheck,
  restoreFromQuarantine,
  resolveStorageRoot,
  tmpFilePath,
} from '../src/modules/document_storage.js';

let base;
before(async () => {
  base = await fsp.mkdtemp(path.join(os.tmpdir(), 'doc-storage-'));
});
after(async () => {
  await fsp.rm(base, { recursive: true, force: true });
});

const KEY = '1000000001/123e4567-e89b-42d3-a456-426614174000';

describe('kök dizin çözümleme ve öz-denetim', () => {
  it('DOCUMENTS_DIR (eski ad DOCUMENTS_STORAGE_DIR) önceliklidir; yoksa depo dışında ~/kapi-documents', () => {
    assert.equal(resolveStorageRoot({ DOCUMENTS_DIR: path.join(base, 'a') }).dir, path.join(base, 'a'));
    assert.equal(resolveStorageRoot({ DOCUMENTS_STORAGE_DIR: path.join(base, 'b') }).dir, path.join(base, 'b'));
    assert.equal(resolveStorageRoot({ DOCUMENTS_DIR: path.join(base, 'a'), DOCUMENTS_STORAGE_DIR: path.join(base, 'b') }).dir, path.join(base, 'a'));
    const fallback = resolveStorageRoot({});
    assert.equal(fallback.dir, path.join(os.homedir(), 'kapi-documents'));
    assert.equal(fallback.source, 'default');
    assert.ok(!fallback.dir.startsWith(REPO_ROOT), 'varsayılan konum depo dışındadır');
  });

  it('depo kökü İÇİNDEKİ dizin reddedilir (build/web servis eder, deploy server/ dizinini yedekler); dizin oluşturulmaz', async () => {
    resetStorageCheck();
    const inside = path.join(REPO_ROOT, 'build', 'web', 'kapi-documents-test-asla-olusmamali');
    const result = await checkStorage({ DOCUMENTS_DIR: inside }, { force: true });
    assert.equal(result.ok, false);
    assert.equal(result.reason, 'inside_repo');
    await assert.rejects(fsp.stat(inside), { code: 'ENOENT' });
  });

  it('geçerli dizin: oluşturulur (_tmp ve sites alt dizinleri), yazılır, statfs çalışır; ikinci çağrı önbellekten', async () => {
    resetStorageCheck();
    const root = path.join(base, 'ok-root');
    const result = await checkStorage({ DOCUMENTS_DIR: root }, { force: true });
    assert.equal(result.ok, true);
    assert.equal(result.root, root);
    assert.ok((await fsp.stat(path.join(root, '_tmp'))).isDirectory());
    assert.ok((await fsp.stat(path.join(root, 'sites'))).isDirectory());
    assert.deepEqual(await fsp.readdir(path.join(root, '_tmp')), [], 'probe dosyası bırakılmaz');
    if (process.platform !== 'win32') {
      assert.equal((await fsp.stat(root)).mode & 0o777, 0o700, 'dizin modu 0700');
    }
    assert.equal(typeof (await freeBytes(root)), 'number');
    assert.equal(await freeBytes(path.join(base, 'yok-boyle-dizin')), null);
    const again = await checkStorage({ DOCUMENTS_DIR: root });
    assert.equal(again.ok, true);
  });

  it('dosya olan yol ve (oluşturulabiliyorsa) symlink kök reddedilir; sunucu düşmez (sonuç nesnesi döner)', async () => {
    resetStorageCheck();
    const file = path.join(base, 'dosya-yol');
    await fsp.writeFile(file, 'x');
    const asFile = await checkStorage({ DOCUMENTS_DIR: file }, { force: true });
    assert.equal(asFile.ok, false);
    const target = path.join(base, 'gercek');
    await fsp.mkdir(target);
    const link = path.join(base, 'sembolik');
    let linked = true;
    try {
      await fsp.symlink(target, link, 'dir');
    } catch (_error) {
      linked = false; // Windows'ta ayrıcalık yok: atlanır
    }
    if (linked) {
      const result = await checkStorage({ DOCUMENTS_DIR: link }, { force: true });
      assert.equal(result.ok, false);
      assert.equal(result.reason, 'not_a_directory');
    }
    resetStorageCheck();
  });
});

describe('anahtar ve yol güvenliği', () => {
  it('newStorageKey: <10 haneli site>/<uuid>; regex ile doğrulanır; her çağrı benzersiz', () => {
    const a = newStorageKey(1000000001);
    const b = newStorageKey(1000000001);
    assert.match(a, STORAGE_KEY_PATTERN);
    assert.notEqual(a, b);
    assert.ok(a.startsWith('1000000001/'));
    assert.throws(() => newStorageKey('../x'));
    assert.throws(() => newStorageKey(12));
  });

  it('pathForKey: yalnız regex ile eşleşen anahtar yola çevrilir; traversal / mutlak / büyük harf / ek uzantı / boş REDDEDİLİR', () => {
    const root = path.join(base, 'k');
    assert.equal(pathForKey(root, KEY), path.join(root, 'sites', '1000000001', '123e4567-e89b-42d3-a456-426614174000'));
    for (const bad of [
      '../1000000001/123e4567-e89b-42d3-a456-426614174000',
      '1000000001/../../etc/passwd',
      '/etc/passwd',
      '1000000001/123e4567-e89b-42d3-a456-426614174000.pdf',
      '1000000001/123E4567-E89B-42D3-A456-426614174000',
      '100000001/123e4567-e89b-42d3-a456-426614174000',
      '1000000001\\123e4567-e89b-42d3-a456-426614174000',
      '1000000001/123e4567-e89b-42d3-a456-426614174000/',
      '',
      null,
      undefined,
      42,
    ]) {
      assert.throws(() => pathForKey(root, bad), /gecersiz depolama anahtari/, String(bad));
    }
  });

  it('tmpFilePath: _tmp altında <uuid>.part', () => {
    const file = tmpFilePath(path.join(base, 'k'));
    assert.match(path.relative(path.join(base, 'k'), file).replace(/\\/g, '/'), /^_tmp\/[0-9a-f-]{36}\.part$/);
  });
});

describe('yazılmaz-silinmez son adım ve güvenli okuma', () => {
  it('commitTempFile: tmp -> son yol (tmp kalkar); son yol VARSA ezilmez (EEXIST) ve tmp korunur', async () => {
    const root = path.join(base, 'c');
    await fsp.mkdir(path.join(root, '_tmp'), { recursive: true });
    await ensureSiteDir(root, 1000000001);
    const final = pathForKey(root, KEY);
    const first = tmpFilePath(root);
    await fsp.writeFile(first, 'ilk');
    await commitTempFile(first, final);
    assert.equal(await fsp.readFile(final, 'utf8'), 'ilk');
    await assert.rejects(fsp.stat(first), { code: 'ENOENT' });
    const second = tmpFilePath(root);
    await fsp.writeFile(second, 'ikinci');
    await assert.rejects(commitTempFile(second, final), { code: 'EEXIST' });
    assert.equal(await fsp.readFile(final, 'utf8'), 'ilk', 'mevcut dosya EZİLMEDİ');
    assert.equal(await fsp.readFile(second, 'utf8'), 'ikinci');
  });

  it('removeStoredFile: yoksa false (hata yok), varsa true; fsyncFile hata vermez', async () => {
    const root = path.join(base, 'r');
    await fsp.mkdir(path.join(root, '_tmp'), { recursive: true });
    await ensureSiteDir(root, 1000000001);
    assert.equal(await removeStoredFile(root, KEY), false);
    await fsp.writeFile(pathForKey(root, KEY), 'x');
    await fsyncFile(pathForKey(root, KEY));
    assert.equal(await removeStoredFile(root, KEY), true);
  });

  it('openStoredFile: boyut DB ile uyuşmazsa mismatch; yoksa missing; doğruysa tutamaç + boyut; yol anahtardan türer', async () => {
    const root = path.join(base, 'o');
    await fsp.mkdir(path.join(root, '_tmp'), { recursive: true });
    await ensureSiteDir(root, 1000000001);
    assert.deepEqual(await openStoredFile(root, KEY, 3), { error: 'missing' });
    assert.deepEqual(await openStoredFile(root, '../etc/passwd', 3), { error: 'missing' }, 'geçersiz anahtar asla dosya sistemine gitmez');
    await fsp.writeFile(pathForKey(root, KEY), 'abc');
    assert.deepEqual(await openStoredFile(root, KEY, 4), { error: 'mismatch' });
    const opened = await openStoredFile(root, KEY, 3);
    assert.equal(opened.size, 3);
    assert.equal((await opened.handle.readFile('utf8')), 'abc');
    await opened.handle.close();
  });

  it('openStoredFile: sembolik bağ düz dosya sayılmaz (oluşturulabiliyorsa)', async () => {
    const root = path.join(base, 's');
    await fsp.mkdir(path.join(root, '_tmp'), { recursive: true });
    await ensureSiteDir(root, 1000000001);
    const outside = path.join(base, 'disarida.txt');
    await fsp.writeFile(outside, 'abc');
    try {
      await fsp.symlink(outside, pathForKey(root, KEY), 'file');
    } catch (_error) {
      return; // Windows'ta ayrıcalık yok
    }
    const result = await openStoredFile(root, KEY, 3);
    assert.ok(result.error === 'mismatch' || result.error === 'missing', JSON.stringify(result.error));
  });
});

describe('akış denetçisi (UploadInspector)', () => {
  const run = async (chunks, options) => {
    const heads = [];
    const inspector = new UploadInspector({ declaredSize: options.declaredSize, onHead: (head) => { heads.push(head.toString('latin1')); options.onHead?.(head); } });
    const sink = [];
    try {
      await pipeline(Readable.from(chunks), inspector, async (source) => { for await (const part of source) sink.push(part); });
      return { inspector, heads, bytes: Buffer.concat(sink) };
    } catch (error) {
      return { code: error.code, heads };
    }
  };

  it('bayt sayar, sha256 hesaplar, ilk 16 baytta ERKEN karar ister; veri aynen geçer', async () => {
    const data = crypto.randomBytes(100_000);
    const parts = [data.subarray(0, 7), data.subarray(7, 40_000), data.subarray(40_000)];
    const result = await run(parts, { declaredSize: data.length });
    assert.equal(result.inspector.bytes, data.length);
    assert.equal(result.inspector.digest(), crypto.createHash('sha256').update(data).digest('hex'));
    assert.equal(result.heads.length, 1, 'tür kararı BİR kez');
    assert.equal(result.heads[0].length, 16);
    assert.deepEqual(result.bytes, data);
  });

  it('erken karar hata fırlatırsa akış kesilir (gövdenin kalanı okunmaz)', async () => {
    let produced = 0;
    function* generator() {
      for (let i = 0; i < 1000; i += 1) {
        produced += 1;
        yield Buffer.alloc(65536, 1);
      }
    }
    const result = await run(generator(), {
      declaredSize: 1000 * 65536,
      onHead: () => { throw Object.assign(new Error('x'), { code: 'DOCUMENT_TYPE_NOT_ALLOWED' }); },
    });
    assert.equal(result.code, 'DOCUMENT_TYPE_NOT_ALLOWED');
    assert.ok(produced < 20, `erken kesildi (üretilen parça: ${produced})`);
  });

  it('bildirilenden FAZLA bayt: anında 400 DOCUMENT_SIZE_MISMATCH; AZ bayt: akış sonunda aynı hata; 16 bayttan kısa dosyada karar akış sonunda', async () => {
    const over = await run([Buffer.alloc(50), Buffer.alloc(51)], { declaredSize: 100 });
    assert.equal(over.code, 'DOCUMENT_SIZE_MISMATCH');
    const under = await run([Buffer.alloc(99)], { declaredSize: 100 });
    assert.equal(under.code, 'DOCUMENT_SIZE_MISMATCH');
    const tiny = await run([Buffer.from('%PDF')], { declaredSize: 4 });
    assert.equal(tiny.heads.length, 1);
    assert.equal(tiny.heads[0], '%PDF');
  });
});

describe('yetim karantinası (R16 P2-4)', () => {
  const Q_KEY = '1000000003/123e4567-e89b-42d3-a456-426614174055';
  let root;
  before(async () => {
    root = await fsp.mkdtemp(path.join(base, 'q-'));
    await ensureSiteDir(root, 1000000003);
  });
  const live = () => pathForKey(root, Q_KEY);
  const exists = (file) => fsp.stat(file).then(() => true, () => false);

  it('quarantineStoredFile: dosya SİLİNMEZ, _orphans/<site>/<uuid> altına taşınır (içerik aynı, mtime = karantina anı); olmayan dosya false', async () => {
    await fsp.writeFile(live(), 'icerik');
    const old = new Date(Date.now() - 40 * 86400_000);
    await fsp.utimes(live(), old, old);
    const now = Date.now();
    assert.equal(await quarantineStoredFile(root, Q_KEY, now), true);
    const target = path.join(root, QUARANTINE_DIR, '1000000003', Q_KEY.split('/')[1]);
    assert.equal(await exists(live()), false);
    assert.equal(await fsp.readFile(target, 'utf8'), 'icerik');
    assert.ok(Math.abs((await fsp.stat(target)).mtimeMs - now) < 2000, 'mtime karantina anıdır (özgün 40 günlük damga atılır)');
    assert.equal(await quarantineStoredFile(root, Q_KEY, now), false, 'yerinde dosya yok');
    await assert.rejects(quarantineStoredFile(root, '../etc/passwd'), /gecersiz depolama anahtari/);
  });

  it('aynı anahtar ikinci kez karantinaya girerse .<zaman> eki alır (üzerine yazılmaz); listQuarantine ikisini de anahtarıyla döner', async () => {
    await fsp.writeFile(live(), 'ikinci');
    assert.equal(await quarantineStoredFile(root, Q_KEY, Date.now() + 5), true);
    const entries = (await listQuarantine(root)).filter((entry) => entry.key === Q_KEY);
    assert.equal(entries.length, 2);
    assert.deepEqual((await Promise.all(entries.map((entry) => fsp.readFile(entry.file, 'utf8')))).sort(), ['icerik', 'ikinci']);
    assert.ok(entries.every((entry) => entry.size > 0 && typeof entry.mtimeMs === 'number'));
  });

  it('listQuarantine: tanınmayan adlar / dizinler yok sayılır; karantina yoksa boş', async () => {
    await fsp.writeFile(path.join(root, QUARANTINE_DIR, '1000000003', 'README.txt'), 'x');
    await fsp.mkdir(path.join(root, QUARANTINE_DIR, 'ham-dizin'), { recursive: true });
    assert.equal((await listQuarantine(root)).filter((entry) => entry.key !== Q_KEY).length, 0);
    assert.deepEqual(await listQuarantine(path.join(base, 'yok-boyle-bir-kok')), []);
  });

  it('purgeQuarantine: yalnız N günden ESKİ dosyalar silinir (mtime), en çok limit; boşalan site dizini kalkar', async () => {
    const dir = path.join(root, QUARANTINE_DIR, '1000000009');
    await fsp.mkdir(dir, { recursive: true });
    const oldFile = path.join(dir, '123e4567-e89b-42d3-a456-426614174071');
    const freshFile = path.join(dir, '123e4567-e89b-42d3-a456-426614174072');
    await fsp.writeFile(oldFile, 'a');
    await fsp.writeFile(freshFile, 'b');
    const now = Date.now();
    await fsp.utimes(oldFile, new Date(now - 15 * 86400_000), new Date(now - 15 * 86400_000));
    await fsp.utimes(freshFile, new Date(now - 13 * 86400_000), new Date(now - 13 * 86400_000));
    const first = await purgeQuarantine(root, 14, now);
    assert.equal(first.purged, 1);
    assert.equal(await exists(oldFile), false);
    assert.equal(await exists(freshFile), true, '13 günlük dosya 14 günlük sürede korunur');
    const later = await purgeQuarantine(root, 14, now + 2 * 86400_000);
    assert.ok(later.purged >= 1);
    assert.equal(await exists(freshFile), false);
    assert.equal(await exists(dir), false, 'boşalan karantina site dizini kaldırıldı');
    const limited = await purgeQuarantine(root, 1, now + 400 * 86400_000, 1);
    assert.equal(limited.purged, 1, 'limit');
  });

  it('restoreFromQuarantine: yerine geri koyar; yerinde dosya VARSA dokunmaz', async () => {
    const restoreKey = '1000000003/123e4567-e89b-42d3-a456-426614174088';
    await fsp.writeFile(pathForKey(root, restoreKey), 'veri');
    await quarantineStoredFile(root, restoreKey);
    const entry = (await listQuarantine(root)).find((candidate) => candidate.key === restoreKey);
    assert.ok(entry);
    assert.equal(await restoreFromQuarantine(root, entry), true);
    assert.equal(await fsp.readFile(pathForKey(root, restoreKey), 'utf8'), 'veri');
    await fsp.writeFile(entry.file, 'baska');
    assert.equal(await restoreFromQuarantine(root, entry), false, 'yerinde dosya var: ezilmez');
    assert.equal(await fsp.readFile(pathForKey(root, restoreKey), 'utf8'), 'veri');
  });
});
