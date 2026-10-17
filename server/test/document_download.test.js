// Belgeler (Faz 3b-A) indirme yanıtı (DB'siz): Content-Disposition kodlaması (Türkçe ad, tırnak, noktalı virgül), başlıkların TAMAMI, HEAD gövdesiz,
// Range yok sayılır (tam 200), eşzamanlılık sınırı + Retry-After, dosya kaybı / silme yarışı, istemci kopması. Gerçek HTTP + gerçek geçici dosya.
import { describe, it, before, after } from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import express from 'express';
import { promises as fsp } from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { activeDownloadCount, asciiFileName, contentDisposition, encodeRfc5987, fileMissingError, sendDocument } from '../src/modules/document_download.js';
import { documentNotFound } from '../src/modules/document_common.js';
import { ensureSiteDir, pathForKey } from '../src/modules/document_storage.js';
import { respondError } from '../src/modules/route_helpers.js';

const KEY = '1000000001/123e4567-e89b-42d3-a456-426614174000';
const CONTENT = Buffer.from('%PDF-1.4 icerik\n%%EOF\n');

let root;
let server;
let baseUrl;
const state = { limit: 32, missing: 'not_found', displayName: 'Toplantı Tutanağı.pdf', sizeBytes: CONTENT.length, key: KEY };

before(async () => {
  root = await fsp.mkdtemp(path.join(os.tmpdir(), 'doc-download-'));
  await ensureSiteDir(root, 1000000001);
  await fsp.writeFile(pathForKey(root, KEY), CONTENT);
  const app = express();
  app.use(async (req, res) => {
    try {
      await sendDocument(req, res, {
        root,
        limit: state.limit,
        version: { storageKey: state.key, sizeBytes: state.sizeBytes, displayName: state.displayName, mimeType: 'application/pdf' },
        onMissing: async () => (state.missing === 'not_found' ? documentNotFound() : fileMissingError('doc=1 v=1')),
      });
    } catch (error) {
      respondError(res, 'test', error, 'hata');
    }
  });
  server = http.createServer(app);
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  baseUrl = `http://127.0.0.1:${server.address().port}`;
});

after(async () => {
  server.closeAllConnections?.();
  await new Promise((resolve) => server.close(resolve));
  await fsp.rm(root, { recursive: true, force: true });
});

describe('Content-Disposition kodlaması (RFC 6266 / 5987)', () => {
  it('ASCII yedek: ç ğ ı ö ş ü (ve büyükleri) harf eşlemesi, diğer ASCII dışı _, " \\ ; atılır', () => {
    assert.equal(asciiFileName('Toplantı Tutanağı Çözüm Şirket Öğün Üst İş.pdf'), 'Toplanti Tutanagi Cozum Sirket Ogun Ust Is.pdf');
    assert.equal(asciiFileName('a"b\\c;d.pdf'), 'abcd.pdf');
    assert.equal(asciiFileName('emoji ' + String.fromCodePoint(0x1f600) + '.pdf'), 'emoji _.pdf', 'tek kod noktası tek _ olur');
    assert.equal(asciiFileName(''), 'belge');
    assert.equal(asciiFileName(String.fromCharCode(1, 2)), 'belge');
  });

  it("filename* yüzde-kodludur ('()* dahil); başlık injection mümkün değildir (CR/LF yok)", () => {
    assert.equal(encodeRfc5987("a b'c(d)*e.pdf"), 'a%20b%27c%28d%29%2Ae.pdf');
    assert.equal(encodeRfc5987('Tutanağı.pdf'), 'Tutana%C4%9F%C4%B1.pdf');
    const header = contentDisposition('Toplantı "Kararı"; 1.pdf\r\nSet-Cookie: x=1');
    assert.ok(header.startsWith('attachment; filename="'));
    assert.ok(!/[\r\n]/.test(header));
    assert.ok(header.includes("filename*=UTF-8''"));
    assert.ok(!header.includes('inline'));
  });
});

describe('indirme yanıtı', () => {
  it('200: kanonik Content-Type, Content-Length, attachment + filename*, nosniff, sandbox CSP, no-store, Pragma, Referrer-Policy, CORP; gövde aynen', async () => {
    const res = await fetch(`${baseUrl}/`);
    assert.equal(res.status, 200);
    assert.equal(res.headers.get('content-type'), 'application/pdf');
    assert.equal(res.headers.get('content-length'), String(CONTENT.length));
    assert.equal(res.headers.get('content-disposition'), `attachment; filename="Toplanti Tutanagi.pdf"; filename*=UTF-8''Toplant%C4%B1%20Tutana%C4%9F%C4%B1.pdf`);
    assert.equal(res.headers.get('x-content-type-options'), 'nosniff');
    assert.equal(res.headers.get('content-security-policy'), "default-src 'none'; sandbox");
    assert.equal(res.headers.get('cache-control'), 'private, no-store');
    assert.equal(res.headers.get('pragma'), 'no-cache');
    assert.equal(res.headers.get('referrer-policy'), 'no-referrer');
    assert.equal(res.headers.get('cross-origin-resource-policy'), 'same-site');
    assert.equal(res.headers.get('etag'), null);
    assert.deepEqual(Buffer.from(await res.arrayBuffer()), CONTENT);
    for (let i = 0; i < 50 && activeDownloadCount() > 0; i += 1) await new Promise((r) => setTimeout(r, 10));
    assert.equal(activeDownloadCount(), 0, 'sayaç geri döndü');
  });

  it('HEAD gövdesizdir ama başlıklar aynıdır; Range yok sayılır (tam 200, 206 DEĞİL)', async () => {
    const head = await fetch(`${baseUrl}/`, { method: 'HEAD' });
    assert.equal(head.status, 200);
    assert.equal(head.headers.get('content-length'), String(CONTENT.length));
    assert.equal((await head.arrayBuffer()).byteLength, 0);
    const ranged = await fetch(`${baseUrl}/`, { headers: { range: 'bytes=0-3' } });
    assert.equal(ranged.status, 200);
    assert.equal(ranged.headers.get('content-range'), null);
    assert.equal(ranged.headers.get('accept-ranges'), null);
    assert.deepEqual(Buffer.from(await ranged.arrayBuffer()), CONTENT);
  });

  it('dosya yok + satır da yok (silme x indirme yarışı): 404 DOCUMENT_NOT_FOUND; satır var ama dosya kayıp: 500 DOCUMENT_FILE_MISSING + errorId', async () => {
    state.key = '1000000001/00000000-0000-4000-8000-000000000000';
    state.missing = 'not_found';
    let res = await fetch(`${baseUrl}/`);
    assert.equal(res.status, 404);
    assert.equal((await res.json()).code, 'DOCUMENT_NOT_FOUND');
    state.missing = 'lost';
    res = await fetch(`${baseUrl}/`);
    assert.equal(res.status, 500);
    const body = await res.json();
    assert.equal(body.code, 'DOCUMENT_FILE_MISSING');
    assert.match(body.errorId, /^[0-9a-f]{12}$/);
    state.key = KEY;
  });

  it('boyut DB ile uyuşmazsa içerik sunulmaz (bütünlük alarmı)', async () => {
    state.sizeBytes = CONTENT.length + 1;
    state.missing = 'lost';
    const res = await fetch(`${baseUrl}/`);
    assert.equal(res.status, 500);
    assert.equal((await res.json()).code, 'DOCUMENT_FILE_MISSING');
    state.sizeBytes = CONTENT.length;
  });

  it('eşzamanlılık sınırı dolunca 503 DOWNLOAD_BUSY + Retry-After; sayaç sızmaz', async () => {
    state.limit = 0;
    const res = await fetch(`${baseUrl}/`);
    assert.equal(res.status, 503);
    assert.equal(res.headers.get('retry-after'), '5');
    assert.equal((await res.json()).code, 'DOWNLOAD_BUSY');
    state.limit = 32;
    assert.equal(activeDownloadCount(), 0);
  });

  it('istemci yarıda koparsa sayaç ve dosya tanıtıcısı sızmaz', async () => {
    const big = Buffer.alloc(8 * 1024 * 1024, 0x41);
    const bigKey = '1000000001/22222222-2222-4222-8222-222222222222';
    await fsp.writeFile(pathForKey(root, bigKey), big);
    state.key = bigKey;
    state.sizeBytes = big.length;
    await new Promise((resolve) => {
      const req = http.get(`${baseUrl}/`, (res) => {
        res.once('data', () => {
          req.destroy();
          resolve();
        });
      });
      req.on('error', () => {});
    });
    for (let i = 0; i < 50 && activeDownloadCount() > 0; i += 1) await new Promise((r) => setTimeout(r, 20));
    assert.equal(activeDownloadCount(), 0);
    await fsp.unlink(pathForKey(root, bigKey)); // tanıtıcı kapanmadıysa Windows'ta EBUSY verirdi
    state.key = KEY;
    state.sizeBytes = CONTENT.length;
  });
});
