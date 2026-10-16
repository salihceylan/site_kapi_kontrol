// Genel (kimliksiz) "abonelikten çık" uçları (DB'siz, gerçek HTTP): GET onay sayfası hiçbir şeyi DEĞİŞTİRMEZ, POST uygular (form gövdesi ya da
// RFC 8058 tek tıklama), imzasız / kurcalanmış belirteç 400, sıkı CSP, adres sayfada görünmez, IP hız sınırı.
import { describe, it, before, after, beforeEach, afterEach, mock } from 'node:test';
import assert from 'node:assert/strict';
import express from 'express';
import { pool } from '../src/db.js';
import {
  announcementPublicRouter,
  unsubscribeApplyLimiter,
  unsubscribeApplyValidLimiter,
  unsubscribeViewLimiter,
  unsubscribeViewValidLimiter,
} from '../src/modules/announcement_public_routes.js';
import { emailHashSalts, hashEmail, signUnsubscribeToken } from '../src/modules/announcement_email_security.js';

process.env.JWT_SECRET ||= 'unit-test-secret-0123456789abcdef';

const norm = (text) => String(text).replace(/\s+/g, ' ').trim();
const ADDRESS = 'sakin@example.com';
const hash = () => hashEmail(ADDRESS);
const token = () => signUnsubscribeToken(hash());

let server;
let baseUrl;
let log;
let failWrites;

before(async () => {
  const app = express();
  app.use(express.json());
  app.use(express.urlencoded({ extended: true }));
  app.use(announcementPublicRouter);
  await new Promise((resolve) => {
    server = app.listen(0, '127.0.0.1', resolve);
  });
  baseUrl = `http://127.0.0.1:${server.address().port}`;
});

after(async () => {
  server.closeAllConnections?.();
  await new Promise((resolve) => server.close(resolve));
  delete pool.query;
});

beforeEach(() => {
  log = [];
  failWrites = false;
  pool.query = async (text, params) => {
    const sql = norm(text);
    log.push({ sql, params: params ?? [] });
    if (failWrites) throw Object.assign(new Error('db kesildi'), { code: '57P01' });
    if (/^INSERT INTO announcement_email_suppressions/.test(sql)) return { rows: [], rowCount: 1 };
    if (/^UPDATE announcement_recipients/.test(sql)) return { rows: [], rowCount: 2 };
    if (/^INSERT INTO notification_preferences/.test(sql)) return { rows: [], rowCount: 1 };
    throw new Error(`BEKLENMEYEN SQL: ${sql.slice(0, 160)}`);
  };
  mock.method(console, 'error', () => {});
});

afterEach(() => {
  mock.restoreAll();
  unsubscribeViewLimiter.reset();
  unsubscribeApplyLimiter.reset();
  unsubscribeViewValidLimiter.reset();
  unsubscribeApplyValidLimiter.reset();
});

const get = async (path) => {
  const response = await fetch(`${baseUrl}${path}`);
  return { status: response.status, text: await response.text(), headers: response.headers };
};
const post = async (path, form) => {
  const response = await fetch(`${baseUrl}${path}`, {
    method: 'POST',
    headers: { 'content-type': 'application/x-www-form-urlencoded' },
    body: form,
  });
  return { status: response.status, text: await response.text(), headers: response.headers };
};

describe('GET /public/announcement-unsubscribe', () => {
  it('geçerli belirteç: 200 onay sayfası (form POST); VERİTABANINA HİÇ DOKUNMAZ (e-posta tarayıcı ön yüklemesi çıkışı tetiklemez); sayfada adres yok', async () => {
    const res = await get(`/public/announcement-unsubscribe?t=${encodeURIComponent(token())}`);
    assert.equal(res.status, 200);
    assert.match(res.text, /<form method="post" action="\/public\/announcement-unsubscribe">/);
    assert.ok(res.text.includes(`value="${token()}"`));
    assert.ok(!res.text.includes('sakin') && !res.text.includes('example.com'));
    assert.equal(log.length, 0);
  });

  it('sıkı güvenlik başlıkları: CSP default-src none + form-action self + frame-ancestors none, no-store, noindex; sayfa Türkçe', async () => {
    const res = await get(`/public/announcement-unsubscribe?t=${encodeURIComponent(token())}`);
    const csp = res.headers.get('content-security-policy');
    assert.match(csp, /default-src 'none'/);
    assert.match(csp, /form-action 'self'/);
    assert.match(csp, /frame-ancestors 'none'/);
    assert.match(csp, /base-uri 'none'/);
    assert.doesNotMatch(csp, /script-src/);
    assert.equal(res.headers.get('cache-control'), 'no-store');
    assert.equal(res.headers.get('x-robots-tag'), 'noindex');
    assert.match(res.headers.get('content-type'), /text\/html/);
    assert.match(res.text, /lang="tr"/);
    assert.doesNotMatch(res.text, /<script/i);
  });

  it('kurcalanmış / eksik / bozuk belirteç: 400 geçersiz bağlantı sayfası (DB yok); belirteç sayfaya YANSITILMAZ (enjeksiyon yok)', async () => {
    const [h, sig] = token().split('.');
    const flip = `${sig.slice(0, -1)}${sig.endsWith('A') ? 'B' : 'A'}`;
    for (const bad of [`${h}.${flip}`, h, '', 'abc', `${'0'.repeat(64)}.${sig}`, `"><script>alert(1)</script>`]) {
      const res = await get(`/public/announcement-unsubscribe?t=${encodeURIComponent(bad)}`);
      assert.equal(res.status, 400, bad.slice(0, 30));
      assert.match(res.text, /Bağlantı geçersiz/);
      assert.ok(!res.text.includes('alert(1)'));
    }
    assert.equal((await get('/public/announcement-unsubscribe')).status, 400);
    assert.equal((await get('/public/announcement-unsubscribe?t[]=a&t[]=b')).status, 400);
    assert.equal(log.length, 0);
  });
});

describe('POST /public/announcement-unsubscribe', () => {
  it('form gövdesiyle (onay sayfası): bastırma kaydı (özet; düz adres yok) + gönderimi başlamamış bekleyen e-postalar skipped_pref; 200 tamam sayfası', async () => {
    const res = await post('/public/announcement-unsubscribe', `t=${encodeURIComponent(token())}`);
    assert.equal(res.status, 200);
    assert.match(res.text, /Abonelikten çıkıldı/);
    assert.match(res.headers.get('content-security-policy'), /default-src 'none'/);
    assert.equal(log.length, 3);
    assert.match(log[0].sql, /^INSERT INTO announcement_email_suppressions \(email_hash\) VALUES \(\$1\) ON CONFLICT \(email_hash\) DO NOTHING$/);
    assert.deepEqual(log[0].params, [hash()]);
    assert.match(log[1].sql, /SET email_status = 'skipped_pref', email = NULL, email_hash = NULL, email_next_at = NULL WHERE email_hash = \$1 AND email_status = 'pending' AND email_claimed_at IS NULL$/);
    assert.deepEqual(log[1].params, [hash()]);
    assert.ok(!JSON.stringify(log).includes(ADDRESS), 'düz adres hiçbir sorguda yok');
  });

  it('RFC 8058 tek tıklama: belirteç sorgu dizesinde, gövde List-Unsubscribe=One-Click -> 200 ve aynı kayıtlar', async () => {
    const res = await post(`/public/announcement-unsubscribe?t=${encodeURIComponent(token())}`, 'List-Unsubscribe=One-Click');
    assert.equal(res.status, 200);
    assert.deepEqual(log[0].params, [hash()]);
    assert.equal(log.length, 3);
  });

  it('idempotent: ikinci POST de 200 (ON CONFLICT DO NOTHING); kurcalanmış / eksik belirteç 400 ve hiçbir yazma yapılmaz', async () => {
    assert.equal((await post('/public/announcement-unsubscribe', `t=${encodeURIComponent(token())}`)).status, 200);
    assert.equal((await post('/public/announcement-unsubscribe', `t=${encodeURIComponent(token())}`)).status, 200);
    log.length = 0;
    const [h, sig] = token().split('.');
    for (const bad of [`${h}.${sig.slice(0, -1)}${sig.endsWith('A') ? 'B' : 'A'}`, h, '', 'x']) {
      assert.equal((await post('/public/announcement-unsubscribe', `t=${encodeURIComponent(bad)}`)).status, 400);
    }
    assert.equal((await post('/public/announcement-unsubscribe', '')).status, 400);
    assert.equal(log.length, 0);
  });

  it('veritabanı hatası: 500 genel sayfa (ayrıntı sızmaz), yalnız hata kodu loglanır', async () => {
    failWrites = true;
    const res = await post('/public/announcement-unsubscribe', `t=${encodeURIComponent(token())}`);
    assert.equal(res.status, 500);
    assert.match(res.text, /işlenemedi/);
    assert.ok(!res.text.includes('db kesildi'));
    const logged = console.error.mock.calls.map((call) => call.arguments.join(' ')).join('\n');
    assert.match(logged, /57P01/);
    assert.ok(!logged.includes('@') && !logged.includes(hash()));
  });
});

describe('E4a hesap tercihi: abonelikten çıkış o adrese sahip hesapların e-posta bildirimini kapatır', () => {
  it('POST üçüncü sorgu: notification_preferences UPSERT (email_announcements = FALSE); adres özeti + güncel / eski tuzlar parametre; hesap e-postası ve dahili hesap iletişim adresi KANONİK özetle eşleşir', async () => {
    const res = await post('/public/announcement-unsubscribe', `t=${encodeURIComponent(token())}`);
    assert.equal(res.status, 200);
    const prefs = log[2];
    assert.match(prefs.sql, /^INSERT INTO notification_preferences \(user_code, email_announcements\) SELECT m\.user_code, FALSE FROM \(/);
    assert.match(prefs.sql, /ON CONFLICT \(user_code\) DO UPDATE SET email_announcements = FALSE, updated_at = NOW\(\)$/);
    assert.match(prefs.sql, /FROM users u WHERE u\.email IS NOT NULL AND u\.email NOT LIKE '%@ahbu\.local' AND \$1 = ANY \(ARRAY\( SELECT encode\(sha256\(convert_to\(s\.salt \|\| ':' \|\| \(CASE WHEN split_part\(lower\(btrim\(u\.email\)\), '@', 2\) IN \('gmail\.com', 'googlemail\.com'\)/);
    assert.match(prefs.sql, /UNION SELECT a\.resident_user_code FROM apartments a INNER JOIN users ru ON ru\.user_code = a\.resident_user_code WHERE a\.resident_email IS NOT NULL/);
    assert.deepEqual(prefs.params, [hash(), emailHashSalts()]);
    assert.ok(!JSON.stringify(prefs.params).includes(ADDRESS));
  });

  it('geçersiz / eksik belirteçte hiçbir tercih yazılmaz; veritabanı hatasında 500 (üçüncü sorgu dahil) ve yalnız kod loglanır', async () => {
    assert.equal((await post('/public/announcement-unsubscribe', 't=abc')).status, 400);
    assert.equal(log.length, 0);
    pool.query = async (text, params) => {
      log.push({ sql: norm(text), params });
      if (/^INSERT INTO notification_preferences/.test(norm(text))) throw Object.assign(new Error('x'), { code: '40001' });
      return { rows: [], rowCount: 1 };
    };
    const res = await post('/public/announcement-unsubscribe', `t=${encodeURIComponent(token())}`);
    assert.equal(res.status, 500);
    assert.match(console.error.mock.calls.map((call) => call.arguments.join(' ')).join('\n'), /kayit basarisiz: 40001/);
  });
});

describe('E5 hız sınırı: önce imza ucuzca doğrulanır; sıkı IP sınırı yalnız GEÇERSİZ belirteçlere', () => {
  const tokenFor = (n) => signUnsubscribeToken(hashEmail(`kisi${n}@example.com`));
  const form = (value) => `t=${encodeURIComponent(value)}`;

  it('posta sağlayıcı havuzu (tek IP, çok sayıda GEÇERLİ tek tık POST): hiçbiri 429 almaz (eski IP başına 30 sınırı çıkışları engellerdi)', async () => {
    for (let n = 0; n < 100; n += 1) {
      const res = await post(`/public/announcement-unsubscribe?t=${encodeURIComponent(tokenFor(n))}`, 'List-Unsubscribe=One-Click');
      assert.equal(res.status, 200, `geçerli POST ${n}`);
    }
  });

  it('GEÇERSİZ belirteç: POST IP başına 30/saat, GET 120/saat (sonra 429); geçerli belirteçler bu sayaçtan ETKİLENMEZ', async () => {
    for (let i = 0; i < 30; i += 1) assert.equal((await post('/public/announcement-unsubscribe', form(`kotu${i}`))).status, 400, `geçersiz post ${i}`);
    assert.equal((await post('/public/announcement-unsubscribe', form('kotu-son'))).status, 429);
    assert.equal((await post('/public/announcement-unsubscribe', form(tokenFor(1)))).status, 200, 'geçerli belirteç IP\'nin geçersiz sayacına takılmaz');
    for (let i = 0; i < 120; i += 1) assert.equal((await get(`/public/announcement-unsubscribe?t=kotu${i}`)).status, 400, `geçersiz get ${i}`);
    assert.equal((await get('/public/announcement-unsubscribe?t=kotu-son')).status, 429);
    assert.equal((await get(`/public/announcement-unsubscribe?t=${encodeURIComponent(tokenFor(2))}`)).status, 200);
  });

  it('GEÇERLİ belirteç: adres özeti başına POST 20/saat, GET 60/saat (idempotent işlem; kötüye kullanım sınırı); başka özet etkilenmez', async () => {
    const same = form(tokenFor(7));
    for (let i = 0; i < 20; i += 1) assert.equal((await post('/public/announcement-unsubscribe', same)).status, 200, `post ${i}`);
    assert.equal((await post('/public/announcement-unsubscribe', same)).status, 429);
    assert.equal((await post('/public/announcement-unsubscribe', form(tokenFor(8)))).status, 200);
    const view = `/public/announcement-unsubscribe?t=${encodeURIComponent(tokenFor(9))}`;
    for (let i = 0; i < 60; i += 1) assert.equal((await get(view)).status, 200, `get ${i}`);
    assert.equal((await get(view)).status, 429);
  });

  it('429 yanıtı da sayfadır: sıkı CSP + no-store + noindex + Retry-After, Türkçe HTML (JSON değil)', async () => {
    for (let i = 0; i < 31; i += 1) await post('/public/announcement-unsubscribe', form(`kotu${i}`));
    const limited = await post('/public/announcement-unsubscribe', form('kotu-x'));
    assert.equal(limited.status, 429);
    assert.match(limited.headers.get('content-security-policy'), /default-src 'none'/);
    assert.equal(limited.headers.get('cache-control'), 'no-store');
    assert.equal(limited.headers.get('x-robots-tag'), 'noindex');
    assert.ok(Number(limited.headers.get('retry-after')) > 0);
    assert.match(limited.headers.get('content-type'), /text\/html/);
    assert.match(limited.text, /Çok fazla istek/);
    assert.doesNotMatch(limited.text, /^\{/);
    // geçerli belirteçte de aynı: digest sınırı
    const same = form(tokenFor(3));
    for (let i = 0; i < 20; i += 1) await post('/public/announcement-unsubscribe', same);
    const validLimited = await post('/public/announcement-unsubscribe', same);
    assert.equal(validLimited.status, 429);
    assert.match(validLimited.headers.get('content-security-policy'), /frame-ancestors 'none'/);
    assert.equal(validLimited.headers.get('cache-control'), 'no-store');
  });

  it('imza kontrolü sınırdan ÖNCE ve veritabanından bağımsızdır: geçersiz belirteç hiçbir sorgu yapmaz, geçerli olmayan istek sayfa sınırına girmeden elenir', async () => {
    await post('/public/announcement-unsubscribe', form('kotu'));
    await get('/public/announcement-unsubscribe?t=kotu');
    assert.equal(log.length, 0);
  });
});
