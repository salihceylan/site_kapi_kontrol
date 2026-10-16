// Genel "abonelikten çık" ucu GERÇEK server.js uygulaması üzerinden (çıplak router değil): gerçek ara katman zinciri (güvenlik başlıkları,
// CORS, istek logu + URL maskesi, JSON / urlencoded gövde, hata işleyicileri), gerçek rota kaydı sırası. Uygulama bir alt süreçte
// SERVER_SKIP_START=1 ile içe aktarılır (ağa açılmaz, DB'ye bağlanmaz), rastgele bir portta dinletilir ve istekler gerçek HTTP ile atılır.
import { describe, it, before } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const serverUrl = pathToFileURL(path.join(here, '..', 'src', 'server.js')).href;
const securityUrl = pathToFileURL(path.join(here, '..', 'src', 'modules', 'announcement_email_security.js')).href;

const CHILD = `
import { once } from 'node:events';
const lines = [];
const originalLog = console.log;
console.log = (...args) => { lines.push(args.join(' ')); };
console.warn = () => {};
console.error = () => {};
const { app } = await import(${JSON.stringify(serverUrl)});
const { hashEmail, signUnsubscribeToken } = await import(${JSON.stringify(securityUrl)});
const server = app.listen(0, '127.0.0.1');
await once(server, 'listening');
const base = 'http://127.0.0.1:' + server.address().port;
const token = signUnsubscribeToken(hashEmail('sakin@example.com'));
const pick = (res, text) => ({
  status: res.status,
  csp: res.headers.get('content-security-policy'),
  cache: res.headers.get('cache-control'),
  robots: res.headers.get('x-robots-tag'),
  nosniff: res.headers.get('x-content-type-options'),
  type: res.headers.get('content-type'),
  retryAfter: res.headers.get('retry-after'),
  poweredBy: res.headers.get('x-powered-by'),
  text,
});
const hit = async (method, path, form) => {
  const res = await fetch(base + path, {
    method,
    headers: form === undefined ? {} : { 'content-type': 'application/x-www-form-urlencoded' },
    body: form,
  });
  return pick(res, await res.text());
};
const out = {};
out.view = await hit('GET', '/public/announcement-unsubscribe?t=' + encodeURIComponent(token));
out.viewInvalid = await hit('GET', '/public/announcement-unsubscribe?t=bozuk');
out.postInvalid = await hit('POST', '/public/announcement-unsubscribe', 't=bozuk');
// gerçek urlencoded ayrıştırıcı + yönlendirici: geçerli belirteç gövdeden okunur, veritabanı yok -> 500 sayfası (400 olsaydı gövde okunmamış demekti)
out.postValidNoDb = await hit('POST', '/public/announcement-unsubscribe', 't=' + encodeURIComponent(token));
out.oneClickNoDb = await hit('POST', '/public/announcement-unsubscribe?t=' + encodeURIComponent(token), 'List-Unsubscribe=One-Click');
out.notFound = await hit('POST', '/public/announcement-unsubscribe/yok', 't=x');
for (let i = 0; i < 40; i += 1) {
  out.limited = await hit('POST', '/public/announcement-unsubscribe', 't=kotu' + i);
}
out.logs = lines.filter((line) => line.includes('/public/announcement-unsubscribe'));
out.token = token;
server.closeAllConnections?.();
server.close();
originalLog('RESULT:' + JSON.stringify(out));
process.exit(0);
`;

let result;

before(() => {
  const run = spawnSync(process.execPath, ['--input-type=module', '-e', CHILD], {
    cwd: path.join(here, '..'),
    env: {
      ...process.env,
      SERVER_SKIP_START: '1',
      NODE_ENV: 'test',
      JWT_SECRET: 'unit-test-secret-0123456789abcdef-server-app',
      DB_HOST: '127.0.0.1',
      DB_PORT: '1',
      DB_USER: 'x',
      DB_PASSWORD: 'x',
      DB_NAME: 'x',
      ANNOUNCEMENT_EMAIL_SECRET: '',
      ANNOUNCEMENT_EMAIL_SECRET_PREVIOUS: '',
    },
    encoding: 'utf8',
    timeout: 60000,
  });
  const line = String(run.stdout ?? '').split('\n').find((entry) => entry.startsWith('RESULT:'));
  assert.ok(line, `alt süreç sonuç üretmedi (çıkış ${run.status}): ${String(run.stderr).slice(0, 600)}`);
  result = JSON.parse(line.slice('RESULT:'.length));
});

describe('server.js uygulaması üzerinden genel abonelikten çık ucu', () => {
  it('SERVER_SKIP_START=1 ile içe aktarılan gerçek uygulamada rota KAYITLI: geçerli belirteç GET 200 onay sayfası; geçersiz 400; bilinmeyen alt yola POST 404 (notFoundHandler)', () => {
    assert.equal(result.view.status, 200);
    assert.match(result.view.text, /<form method="post" action="\/public\/announcement-unsubscribe">/);
    assert.equal(result.viewInvalid.status, 400);
    assert.match(result.viewInvalid.text, /Bağlantı geçersiz/);
    assert.equal(result.postInvalid.status, 400);
    assert.equal(result.notFound.status, 404);
  });

  it('gerçek ara katman zinciri sayfa başlıklarını BOZMAZ: sıkı CSP (default-src none, frame-ancestors none), no-store, noindex, HTML; global güvenlik başlıkları (nosniff) ve x-powered-by yok', () => {
    for (const key of ['view', 'viewInvalid', 'postInvalid']) {
      const response = result[key];
      assert.match(response.csp, /default-src 'none'/, key);
      assert.match(response.csp, /frame-ancestors 'none'/, key);
      assert.equal(response.cache, 'no-store', key);
      assert.equal(response.robots, 'noindex', key);
      assert.match(response.type, /text\/html/, key);
      assert.equal(response.nosniff, 'nosniff', `${key}: createSecurityHeaders çalışıyor`);
      assert.equal(response.poweredBy, null, key);
    }
  });

  it('gerçek express.urlencoded ayrıştırıcısı yönlendiriciden ÖNCE: form gövdesindeki belirteç okunur (geçerli belirteç + DB yok -> 500 işlem tamamlanamadı sayfası, 400 değil); tek tık (sorgu dizesi) de aynı', () => {
    assert.equal(result.postValidNoDb.status, 500);
    assert.match(result.postValidNoDb.text, /İşlem tamamlanamadı/);
    assert.match(result.postValidNoDb.csp, /default-src 'none'/);
    assert.equal(result.oneClickNoDb.status, 500);
    assert.doesNotMatch(result.postValidNoDb.text, /DB_|ECONNREFUSED|127\.0\.0\.1/, 'hata ayrıntısı sızmaz');
  });

  it('E5 429 yanıtı gerçek uygulamada da sayfadır: CSP + no-store + Retry-After + Türkçe HTML', () => {
    assert.equal(result.limited.status, 429);
    assert.match(result.limited.csp, /default-src 'none'/);
    assert.equal(result.limited.cache, 'no-store');
    assert.ok(Number(result.limited.retryAfter) > 0);
    assert.match(result.limited.text, /Çok fazla istek/);
    assert.match(result.limited.type, /text\/html/);
  });

  it('E7 istek logu: yol "/public/announcement-unsubscribe" olarak AYIRT EDİLEBİLİR, yalnız belirteç (?t=) maskelenir; belirteç loga yazılmaz', () => {
    const withToken = result.logs.filter((line) => line.includes('?t='));
    assert.ok(withToken.length >= 3, `istek logları: ${result.logs.length}`);
    assert.ok(withToken.every((line) => /\/public\/announcement-unsubscribe\?t=\*\*\* ->/.test(line)), withToken.join('\n'));
    assert.ok(result.logs.every((line) => !line.includes(result.token) && !line.includes(result.token.split('.')[0])));
  });
});
