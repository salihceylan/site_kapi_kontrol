// F20: GET /api/company/devices/:deviceUid/runtime (gercek HTTP, sahte veritabani). Sirket araci "Cihaz testi" sayfasi
// bagli kartin genel IP'sini (WAN) bu uctan okur. Sozlesme: anahtarsiz 401, gecersiz kimlik 400, bilinmeyen cihaz 404;
// yanit YALNIZ { device_uid, public_ip, last_seen_at } (liste/kullanici/site/MQTT kimligi yok); hiz sinirlayici yetkiden once.
import { describe, it, before, after, beforeEach, afterEach, mock } from 'node:test';
import assert from 'node:assert/strict';
import express from 'express';
import '../src/utils/async_errors.js';
import { pool } from '../src/db.js';
import {
  companyAccessLimiter,
  companyDeviceRuntimeBody,
  companyRouter,
  readCompanyDeviceRuntime,
} from '../src/routes/company_routes.js';
import { createErrorHandler } from '../src/middlewares/error_handler.js';

const KEY = 'company-key-for-tests-0123456789abcdef'; // sahte test degeri
const UID = '00861A0D5020';
const SEEN = '2026-10-19T08:30:00.000Z';

describe('F20 sirket ucu: cihaz calisma ozeti (genel IP)', () => {
  let server;
  let baseUrl;
  let savedKey;
  let devices;
  let failDb;
  let queries;

  before(async () => {
    const app = express();
    app.set('env', 'test');
    app.use(express.json({ limit: '1mb' }));
    app.use(companyRouter);
    app.use(createErrorHandler({ logger: { error: () => {}, log: () => {}, warn: () => {} } }));
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
    savedKey = process.env.COMPANY_API_KEY;
    process.env.COMPANY_API_KEY = KEY;
    // Sahte devices + device_runtime_status: { uid: { public_ip, last_seen_at } | null (runtime satiri yok) }
    devices = {
      [UID]: { public_ip: '88.230.12.34', last_seen_at: new Date(SEEN) },
      A1B2C3D4E5F6: null,
    };
    failDb = false;
    queries = [];
    pool.query = async (text, params = []) => {
      const sql = String(text).replace(/\s+/g, ' ').trim();
      queries.push({ sql, params });
      if (!/^SELECT d\.device_uid, rs\.public_ip, rs\.last_seen_at FROM devices d LEFT JOIN device_runtime_status rs/.test(sql)) {
        throw new Error(`SAHTE VERITABANI: tanimsiz SQL: ${sql}`);
      }
      if (failDb) {
        throw Object.assign(new Error('SECRET_DB_DETAIL password=hunter2'), { code: '57P01' });
      }
      const uid = params[0];
      if (!(uid in devices)) return { rows: [], rowCount: 0 };
      const runtime = devices[uid];
      return {
        rows: [{
          device_uid: uid,
          public_ip: runtime?.public_ip ?? null,
          last_seen_at: runtime?.last_seen_at ?? null,
          // Sorgu bunlari secmese bile uc disari tasimamali (savunma): yanit yalniz uc alan.
          owner_user_id: 7,
          mqtt_password: 'gizli',
        }],
        rowCount: 1,
      };
    };
    mock.method(console, 'error', () => {});
  });

  afterEach(() => {
    mock.restoreAll();
    companyAccessLimiter.reset();
    if (savedKey === undefined) delete process.env.COMPANY_API_KEY;
    else process.env.COMPANY_API_KEY = savedKey;
  });

  const get = (uid, headers = { 'X-Company-Key': KEY }) => fetch(
    `${baseUrl}/api/company/devices/${encodeURIComponent(uid)}/runtime`,
    { headers },
  );

  it('anahtarsiz ve yanlis anahtarla 401; veritabanina hic gidilmez', async () => {
    const anonymous = await get(UID, {});
    assert.equal(anonymous.status, 401);
    const wrong = await get(UID, { 'X-Company-Key': 'yanlis' });
    assert.equal(wrong.status, 401);
    assert.equal(queries.length, 0);
  });

  it('COMPANY_API_KEY sunucuda tanimsizsa anahtar basligi islemez -> 401', async () => {
    delete process.env.COMPANY_API_KEY;
    const response = await get(UID);
    assert.equal(response.status, 401);
    assert.equal(queries.length, 0);
  });

  it('gecersiz cihaz kimligi -> 400 (veritabanina gidilmez)', async () => {
    for (const bad of ['XYZ', '00861A0D502', '00861A0D50201', 'G0861A0D5020', '../../etc/passwd', "00861A0D5020' OR 1=1"]) {
      const response = await get(bad);
      assert.equal(response.status, 400, `${bad} -> ${response.status}`);
      const body = await response.json();
      assert.match(body.error, /12 haneli hex/);
    }
    assert.equal(queries.length, 0);
  });

  it('bilinmeyen cihaz -> 404', async () => {
    const response = await get('FFFFFFFFFFFF');
    assert.equal(response.status, 404);
    assert.deepEqual(await response.json(), { error: 'Cihaz bulunamadi.' });
    assert.deepEqual(queries[0].params, ['FFFFFFFFFFFF']);
  });

  it('kayitli cihaz -> 200, yalniz device_uid/public_ip/last_seen_at; onbelleklenmez', async () => {
    const response = await get(UID);
    assert.equal(response.status, 200);
    assert.equal(response.headers.get('cache-control'), 'no-store');
    const body = await response.json();
    assert.deepEqual(body, { device_uid: UID, public_ip: '88.230.12.34', last_seen_at: SEEN });
    assert.deepEqual(Object.keys(body).sort(), ['device_uid', 'last_seen_at', 'public_ip']);
    // Tek sorgu, tek parametre (istenen kimlik); baska cihaz/liste sorgusu yok.
    assert.equal(queries.length, 1);
    assert.deepEqual(queries[0].params, [UID]);
    assert.match(queries[0].sql, /WHERE UPPER\(d\.device_uid\) = \$1/);
    assert.match(queries[0].sql, /LIMIT 1$/);
  });

  it('kucuk harf ve ":"/"-" ayiricili kimlik normallestirilir', async () => {
    for (const raw of ['00:86:1a:0d:50:20', '00-86-1A-0D-50-20', '00861a0d5020']) {
      const response = await get(raw);
      assert.equal(response.status, 200, raw);
      assert.equal((await response.json()).device_uid, UID);
    }
    assert.ok(queries.every((q) => q.params[0] === UID));
  });

  it('kayitli ama calisma satiri olmayan cihaz -> 200, public_ip/last_seen_at null', async () => {
    const response = await get('A1B2C3D4E5F6');
    assert.equal(response.status, 200);
    assert.deepEqual(await response.json(), { device_uid: 'A1B2C3D4E5F6', public_ip: null, last_seen_at: null });
  });

  it('veritabani hatasi -> 500 + errorId; ic ayrinti yanita sizmaz', async () => {
    failDb = true;
    const response = await get(UID);
    assert.equal(response.status, 500);
    const text = await response.text();
    assert.doesNotMatch(text, /SECRET_DB_DETAIL|hunter2|57P01/);
    const body = JSON.parse(text);
    assert.ok(body.errorId);
    assert.deepEqual(Object.keys(body).sort(), ['error', 'errorId']);
  });

  it('hiz sinirlayici yetkiden ONCE sayar (yanlis anahtar denemeleri de sinirlanir)', async () => {
    assert.equal(companyAccessLimiter.size(), 0);
    const response = await get(UID, { 'X-Company-Key': 'yanlis' });
    assert.equal(response.status, 401);
    assert.ok(companyAccessLimiter.size() >= 1);
  });
});

describe('F20 yardimcilar: companyDeviceRuntimeBody / readCompanyDeviceRuntime', () => {
  it('IPv4-mapped IPv6 onekini atar; gecerli IPv6 korunur', () => {
    assert.equal(companyDeviceRuntimeBody(UID, { public_ip: '::ffff:85.105.1.2' }).public_ip, '85.105.1.2');
    assert.equal(companyDeviceRuntimeBody(UID, { public_ip: '2a02:ff0:1::5' }).public_ip, '2a02:ff0:1::5');
  });

  it('gecersiz/bozuk kayitli deger null doner (ham metin disari tasinmaz)', () => {
    for (const raw of ['', '   ', 'abc', '1.2.3', '999.1.1.1', '<script>', null, undefined, 42]) {
      assert.equal(companyDeviceRuntimeBody(UID, { public_ip: raw }).public_ip, null, String(raw));
    }
  });

  it('Cloudflare kenar adresi kartin IP\'si olarak gosterilmez (TRUST_PROXY eksikse kaydedilen deger) -> null', () => {
    for (const edge of ['104.16.0.1', '172.64.1.1', '2606:4700::1']) {
      assert.equal(companyDeviceRuntimeBody(UID, { public_ip: edge }).public_ip, null, edge);
    }
  });

  it('last_seen_at Date/metin -> ISO; gecersiz -> null', () => {
    assert.equal(companyDeviceRuntimeBody(UID, { last_seen_at: new Date(SEEN) }).last_seen_at, SEEN);
    assert.equal(companyDeviceRuntimeBody(UID, { last_seen_at: SEEN }).last_seen_at, SEEN);
    assert.equal(companyDeviceRuntimeBody(UID, { last_seen_at: 'dun' }).last_seen_at, null);
    assert.equal(companyDeviceRuntimeBody(UID, {}).last_seen_at, null);
  });

  it('readCompanyDeviceRuntime: satir yoksa null, varsa yalniz uc alan; hata yutulmaz', async () => {
    const empty = { query: async () => ({ rows: [] }) };
    assert.equal(await readCompanyDeviceRuntime(empty, UID), null);

    const found = { query: async () => ({ rows: [{ device_uid: UID, public_ip: '88.230.12.34', last_seen_at: null, site_code: 'S1' }] }) };
    assert.deepEqual(await readCompanyDeviceRuntime(found, UID), { device_uid: UID, public_ip: '88.230.12.34', last_seen_at: null });

    const broken = { query: async () => { throw new Error('baglanti yok'); } };
    await assert.rejects(() => readCompanyDeviceRuntime(broken, UID), /baglanti yok/);
  });
});
