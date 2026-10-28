// Web push abonelik adresi izin listesi (guvenlik denetimi authz-modules-2 / auth-9): sunucu kayitli adrese kendi VAPID basligiyla POST eder;
// keyfi https adresi kor SSRF + sonsuz yanitla surec cokertme yoludur. Kural: YALNIZ https + bilinen tarayici bildirim servisi alan adi
// (WEB_PUSH_ALLOWED_HOSTS), varsayilan 443 kapisi, kullanici bilgisi/parca/ters bolu/bosluk YOK. Reddedilen adres 400 INVALID_BODY.
// Kapsam: saf dogrulama, saveSubscription (sahte veritabani), PUT /app/web-push/subscriptions (gercek HTTP) ve gonderimden once yeniden denetim.
import { describe, it, before, after, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import url from 'node:url';
import express from 'express';
import { pool } from '../src/db.js';
import { PlatformError } from '../src/modules/errors.js';
import { notifyChannelsRouter } from '../src/modules/notify_channels_routes.js';
import {
  WEB_PUSH_ALLOWED_HOSTS,
  isAllowedPushEndpoint,
  parseSubscription,
  saveSubscription,
  sendWebPushToUsers,
  webPushHooks,
} from '../src/modules/web_push.js';

const ENV_KEYS = ['WEB_PUSH_VAPID_PUBLIC', 'WEB_PUSH_VAPID_PRIVATE', 'WEB_PUSH_SUBJECT'];
const savedEnv = Object.fromEntries(ENV_KEYS.map((key) => [key, process.env[key]]));
const restoreEnv = () => {
  for (const key of ENV_KEYS) {
    if (savedEnv[key] === undefined) delete process.env[key];
    else process.env[key] = savedEnv[key];
  }
};
const enableWebPush = () => {
  process.env.WEB_PUSH_VAPID_PUBLIC = 'test-vapid-public-key';
  process.env.WEB_PUSH_VAPID_PRIVATE = 'test-vapid-private-key';
  process.env.WEB_PUSH_SUBJECT = 'mailto:test@example.com';
};

const KEYS = Object.freeze({ p256dh: 'A'.repeat(30), auth: 'B'.repeat(12) });
const USER = Object.freeze({ id: 48213, user_code: 48213, userCode: 48213, role: 'individual', full_name: 'Ayse', email: 'ayse@example.com' });
const norm = (text) => String(text).replace(/\s+/g, ' ').trim();
const isInvalidBody = (error) => error instanceof PlatformError && error.statusCode === 400 && error.code === 'INVALID_BODY';

const FCM = 'https://fcm.googleapis.com/fcm/send/dQw4w9WgXcQ:APA91bHun4MxP5egoKMwt2KZFBaFUH-1RYqx_ornek-belirtec';
const APPLE = 'https://web.push.apple.com/QGGpAbCdEf0123456789_-xyz';

/** [ad, adres]: tarayicilarin gercekte urettigi bicimler. */
const VALID = [
  ['FCM (fcm/send)', FCM],
  ['FCM (wp)', 'https://fcm.googleapis.com/wp/fAbCdEfGh123_-xyz'],
  ['Firefox', 'https://updates.push.services.mozilla.com/wpush/v2/gAAAAABnOrnekBelirtecDegeri0123456789_-'],
  ['Safari / iOS', APPLE],
  ['Windows (WNS, yol + sorgu)', 'https://wns2-par02p.notify.windows.com/w/?token=BQYAAAB%2bAbC%2fdef%3d'],
  ['Windows (WNS, kok yol + sorgu)', 'https://hk2.notify.windows.com/?token=AwYAAAD'],
  ['Apple joker: cok katmanli alt alan adi', 'https://a.b.push.apple.com/abc12345'],
  ['acik 443 kapisi', 'https://fcm.googleapis.com:443/fcm/send/abc12345'],
];

/** [ad, adres]: hepsi 400 olmali. */
const INVALID = [
  ['http (https degil)', 'http://fcm.googleapis.com/fcm/send/abc12345'],
  ['izin listesinde olmayan alan adi', 'https://attacker.example/collect'],
  ['rastgele push adi', 'https://push.example.com/abc123456'],
  ['alan adi sonek hilesi', 'https://fcm.googleapis.com.attacker.example/fcm/send/abc12345'],
  ['izinli adin alt alan adi (tam eslesme gerekir)', 'https://evil.fcm.googleapis.com/fcm/send/abc12345'],
  ['benzer alan adi', 'https://fcm-googleapis.com/fcm/send/abc12345'],
  ['kullanici adi + parola (userinfo)', 'https://user:pass@fcm.googleapis.com/fcm/send/abc12345'],
  ['yalniz kullanici adi (userinfo)', 'https://token@fcm.googleapis.com/fcm/send/abc12345'],
  ['userinfo hilesi: izinli ad kullanici adi, gercek ana makine saldirganin', 'https://fcm.googleapis.com@attacker.example/fcm/send/abc12345'],
  ['userinfo + kapi hilesi', 'https://fcm.googleapis.com:443@attacker.example/fcm/send/abc12345'],
  ['ters bolu hilesi 1', 'https://attacker.example\\@fcm.googleapis.com/fcm/send/abc12345'],
  ['ters bolu hilesi 2', 'https://fcm.googleapis.com\\.attacker.example/fcm/send/abc12345'],
  ['baska kapi', 'https://fcm.googleapis.com:8443/fcm/send/abc12345'],
  ['alan adi sonunda nokta', 'https://fcm.googleapis.com./fcm/send/abc12345'],
  ['Apple jokeri: apeks alan adi', 'https://push.apple.com/abc12345'],
  ['Apple jokeri: sonek hilesi', 'https://web.push.apple.com.attacker.example/abc12345'],
  ['Apple jokeri: yakin alan adi', 'https://webpush.apple.com/abc12345'],
  ['Windows jokeri: apeks alan adi', 'https://notify.windows.com/w/?token=abc12345'],
  ['Windows jokeri: sonek hilesi', 'https://notify.windows.com.attacker.example/w/?token=abc12345'],
  ['loopback IPv4', 'https://127.0.0.1/internal/path'],
  ['loopback IPv4 + kapi', 'https://127.0.0.1:8443/internal/path'],
  ['localhost', 'https://localhost/internal/path'],
  ['ozel ag adresi', 'https://10.0.0.5/admin/reset'],
  ['bulut metadata adresi', 'https://169.254.169.254/latest/meta-data/iam'],
  ['IPv6 loopback', 'https://[::1]/internal/path'],
  ['onluk IPv4 yazimi', 'https://2130706433/internal/path'],
  ['parca (#) iceren', 'https://fcm.googleapis.com/fcm/send/abc12345#attacker.example'],
  ['bosluk iceren', 'https://fcm.googleapis.com/fcm/send/abc 12345'],
  ['satir sonu iceren', 'https://fcm.googleapis.com/fcm/send/abc\n12345'],
  ['sekme iceren', 'https://fcm.googleapis.com/fcm/send/abc\t12345'],
  ['yol yok', 'https://fcm.googleapis.com'],
  ['ASCII disi benzer harf (Kiril o)', 'https://fcm.goоgleapis.com/fcm/send/abc12345'],
  ['javascript semasi', 'javascript:alert(1)//fcm.googleapis.com/'],
  ['semasiz', '//fcm.googleapis.com/fcm/send/abc12345'],
  ['bos', ''],
];

describe('izin listesi sabiti', () => {
  it('tek, degistirilemez liste; dort bilinen servisi icerir', () => {
    assert.ok(Array.isArray(WEB_PUSH_ALLOWED_HOSTS));
    assert.ok(Object.isFrozen(WEB_PUSH_ALLOWED_HOSTS));
    for (const host of ['fcm.googleapis.com', 'updates.push.services.mozilla.com', '*.push.apple.com', '*.notify.windows.com']) {
      assert.ok(WEB_PUSH_ALLOWED_HOSTS.includes(host), host);
    }
  });

  it('kullanici icerigi barindirabilen genis joker yok (*.googleapis.com, *.com ...)', () => {
    for (const entry of WEB_PUSH_ALLOWED_HOSTS) {
      if (!entry.startsWith('*.')) continue;
      assert.ok(entry.slice(2).split('.').length >= 3, `joker cok genis: ${entry}`);
    }
    assert.equal(isAllowedPushEndpoint('https://storage.googleapis.com/bucket/object'), false);
  });
});

describe('isAllowedPushEndpoint', () => {
  for (const [name, endpoint] of VALID) {
    it(`kabul: ${name}`, () => assert.equal(isAllowedPushEndpoint(endpoint), true));
  }
  for (const [name, endpoint] of INVALID) {
    it(`red: ${name}`, () => assert.equal(isAllowedPushEndpoint(endpoint), false));
  }

  it('alan adi buyuk/kucuk harf duyarsiz', () => {
    assert.equal(isAllowedPushEndpoint('https://FCM.GoogleAPIs.com/fcm/send/abc12345'), true);
  });

  it('uzunluk siniri: 1008 karakter kabul, 1009 red', () => {
    const base = 'https://fcm.googleapis.com/';
    assert.equal(isAllowedPushEndpoint(base + 'a'.repeat(1008 - base.length)), true);
    assert.equal(isAllowedPushEndpoint(base + 'a'.repeat(1009 - base.length)), false);
  });

  it('metin olmayan degerler red', () => {
    for (const value of [undefined, null, 123, {}, [], true, () => FCM]) assert.equal(isAllowedPushEndpoint(value), false);
  });
});

describe('ayristirici uyumu: web-push eski url.parse kullanir, dogrulama standart URL ile de uyumlu olmali', () => {
  // web-push-lib.js: `url.parse(endpoint)` -> hostname/port/path ile https.request. Kabul edilen her adreste BU ayristirici da
  // izinli ana makineyi, varsayilan kapiyi ve kullanici bilgisi OLMADIGINI gormeli (aksi halde istek baska bir ana makineye gider).
  const legacyParse = (endpoint) => {
    const previous = process.noDeprecation;
    process.noDeprecation = true; // DEP0169 uyarisi test ciktisini kirletmesin
    try {
      return url.parse(endpoint);
    } finally {
      process.noDeprecation = previous;
    }
  };

  const assertSafeForLibrary = (endpoint) => {
    const legacy = legacyParse(endpoint);
    const standard = new URL(endpoint);
    assert.equal(legacy.protocol, 'https:', endpoint);
    assert.equal(legacy.auth, null, endpoint);
    assert.ok(legacy.port === null || legacy.port === '443', endpoint);
    assert.equal(legacy.hostname, standard.hostname, endpoint);
    assert.equal(isAllowedPushEndpoint(`https://${legacy.hostname}/x`), true, `${endpoint} -> web-push ${legacy.hostname} adresine baglanir`);
  };

  it('gercek bicimli adreslerde iki ayristirici ayni izinli ana makineyi gorur', () => {
    for (const [, endpoint] of VALID) assertSafeForLibrary(endpoint);
  });

  it('hileli bicimlerin kombinasyonu: kabul edilen HER adres iki ayristiricida da guvenli, en az bir kabul var', () => {
    const schemes = ['https://', 'HTTPS://', 'https:/', 'https:///', 'https:\\\\', ' https://', 'https://\t'];
    const hosts = [
      'fcm.googleapis.com',
      'FCM.googleapis.com',
      'fcm.googleapis.com.',
      'web.push.apple.com',
      'wns2-par02p.notify.windows.com',
      'attacker.example',
      '127.0.0.1',
      'fcm.googleapis.com%2eattacker.example',
      'fcm.googleapis.com%00.attacker.example',
      'fcm.googleapis.com\u3002attacker.example',
      'fcm.googleapis.com\uff0eattacker.example',
    ];
    const seps = ['', '/', ':443/', ':8443/', '@attacker.example/', ':pw@attacker.example/', '\\', '\\@attacker.example/', '#', '#@attacker.example/', '?@attacker.example/', '/@attacker.example/', ' ', '\t/', '%2f', '/%2e%2e/', '//'];
    const tails = ['', 'x', 'abc12345', '?token=abc', '/@evil.example', '\\@evil.example'];
    let accepted = 0;
    for (const scheme of schemes) {
      for (const host of hosts) {
        for (const sep of seps) {
          for (const tail of tails) {
            const endpoint = scheme + host + sep + tail;
            if (!isAllowedPushEndpoint(endpoint)) continue;
            accepted += 1;
            assertSafeForLibrary(endpoint);
          }
        }
      }
    }
    assert.ok(accepted >= 10, `beklenenden az kabul: ${accepted}`);
  });
});

describe('parseSubscription', () => {
  for (const [name, endpoint] of VALID) {
    it(`kabul: ${name}`, () => {
      const parsed = parseSubscription({ endpoint, keys: KEYS });
      assert.deepEqual(parsed, { endpoint, p256dh: KEYS.p256dh, auth: KEYS.auth });
    });
  }
  for (const [name, endpoint] of INVALID) {
    it(`400 INVALID_BODY: ${name}`, () => {
      assert.throws(() => parseSubscription({ endpoint, keys: KEYS }), isInvalidBody);
    });
  }

  it('adres hic yoksa / metin degilse 400', () => {
    for (const body of [undefined, null, {}, { endpoint: 42, keys: KEYS }, { endpoint: ['x'], keys: KEYS }]) {
      assert.throws(() => parseSubscription(body), isInvalidBody);
    }
  });

  it('kenardaki bosluklar kesilir; ic bosluk reddedilir', () => {
    assert.equal(parseSubscription({ endpoint: `  ${FCM}\n`, keys: KEYS }).endpoint, FCM);
    assert.throws(() => parseSubscription({ endpoint: 'https://fcm.googleapis.com/fcm/send/ab cd12345', keys: KEYS }), isInvalidBody);
  });

  it('anahtar dogrulamasi korunur (p256dh / auth)', () => {
    assert.throws(() => parseSubscription({ endpoint: FCM, keys: { p256dh: 'kisa', auth: KEYS.auth } }), isInvalidBody);
    assert.throws(() => parseSubscription({ endpoint: FCM, keys: { p256dh: KEYS.p256dh, auth: 'x' } }), isInvalidBody);
    assert.throws(() => parseSubscription({ endpoint: FCM }), isInvalidBody);
  });
});

describe('saveSubscription (sahte veritabani)', () => {
  let queries;
  const db = {
    query: async (text, params = []) => {
      queries.push({ sql: norm(text), params });
      if (/^SELECT COUNT/.test(norm(text))) return { rows: [{ n: 0 }], rowCount: 1 };
      return { rows: [], rowCount: 1 };
    },
  };

  before(enableWebPush);
  after(restoreEnv);
  beforeEach(() => {
    queries = [];
  });

  it('izinli adres kaydedilir', async () => {
    assert.deepEqual(await saveSubscription(USER, { endpoint: FCM, keys: KEYS }, db), { ok: true });
    const insert = queries.find((q) => /^INSERT INTO web_push_subscriptions/.test(q.sql));
    assert.ok(insert, 'INSERT calismali');
    assert.deepEqual(insert.params, [48213, FCM, KEYS.p256dh, KEYS.auth]);
  });

  it('izin disi her adres 400 INVALID_BODY ile reddedilir ve veritabanina HIC dokunulmaz', async () => {
    for (const [name, endpoint] of INVALID) {
      await assert.rejects(saveSubscription(USER, { endpoint, keys: KEYS }, db), isInvalidBody, name);
    }
    assert.equal(queries.length, 0);
  });

  it('web push kapaliyken 503 (adres denetiminden once)', async () => {
    delete process.env.WEB_PUSH_VAPID_PUBLIC;
    try {
      await assert.rejects(
        saveSubscription(USER, { endpoint: FCM, keys: KEYS }, db),
        (error) => error instanceof PlatformError && error.statusCode === 503 && error.code === 'WEB_PUSH_UNAVAILABLE',
      );
    } finally {
      enableWebPush();
    }
    assert.equal(queries.length, 0);
  });
});

describe('PUT /app/web-push/subscriptions (gercek HTTP, sahte veritabani)', () => {
  const routeLayer = notifyChannelsRouter.stack.find((layer) => layer.route?.path === '/app/web-push/subscriptions' && layer.route.methods.put);
  const originalAuth = routeLayer.route.stack[0].handle;
  let server;
  let baseUrl;
  let queries;

  before(async () => {
    enableWebPush();
    // Yalniz kimlik katmani sahte; hiz siniri, govde ayristirici, saveSubscription ve hata eslemesi GERCEKTIR.
    routeLayer.route.stack[0].handle = (req, res, next) => {
      if (!req.headers['x-test-user']) return res.status(401).json({ error: 'Yetkisiz erisim.' });
      req.authUser = { ...USER };
      return next();
    };
    const app = express();
    app.use(express.json({ limit: '1mb' }));
    app.use(notifyChannelsRouter);
    await new Promise((resolve) => {
      server = app.listen(0, '127.0.0.1', resolve);
    });
    baseUrl = `http://127.0.0.1:${server.address().port}`;
  });

  after(async () => {
    routeLayer.route.stack[0].handle = originalAuth;
    server.closeAllConnections?.();
    await new Promise((resolve) => server.close(resolve));
    delete pool.query;
    restoreEnv();
  });

  beforeEach(() => {
    queries = [];
    pool.query = async (text, params = []) => {
      queries.push({ sql: norm(text), params });
      if (/^SELECT COUNT/.test(norm(text))) return { rows: [{ n: 0 }], rowCount: 1 };
      return { rows: [], rowCount: 1 };
    };
  });

  const put = async (body, { auth = true } = {}) => {
    const response = await fetch(`${baseUrl}/app/web-push/subscriptions`, {
      method: 'PUT',
      headers: { 'content-type': 'application/json', ...(auth ? { 'x-test-user': '1' } : {}) },
      body: JSON.stringify(body),
    });
    const text = await response.text();
    let json = null;
    try {
      json = JSON.parse(text);
    } catch (_error) {
      // JSON degil
    }
    return { status: response.status, json, text };
  };

  it('izinli adres: 200 { ok: true } ve satir yazilir', async () => {
    for (const [name, endpoint] of VALID.slice(0, 5)) {
      queries = [];
      const res = await put({ endpoint, keys: KEYS });
      assert.equal(res.status, 200, name);
      assert.deepEqual(res.json, { ok: true }, name);
      assert.ok(queries.some((q) => /^INSERT INTO web_push_subscriptions/.test(q.sql) && q.params[1] === endpoint), name);
    }
  });

  it('sahte alan adi / http / userinfo / ic ag adresi: 400 INVALID_BODY ve hicbir SQL calismaz', async () => {
    const samples = [
      'https://attacker.example/collect',
      'http://fcm.googleapis.com/fcm/send/abc12345',
      'https://user:pass@fcm.googleapis.com/fcm/send/abc12345',
      'https://fcm.googleapis.com@attacker.example/fcm/send/abc12345',
      'https://127.0.0.1:8443/internal/path',
      'https://169.254.169.254/latest/meta-data/iam',
      'https://localhost/x12345678',
      'https://fcm.googleapis.com.attacker.example/fcm/send/abc12345',
    ];
    for (const endpoint of samples) {
      const res = await put({ endpoint, keys: KEYS });
      assert.equal(res.status, 400, endpoint);
      assert.equal(res.json?.code, 'INVALID_BODY', endpoint);
      assert.match(String(res.json?.error), /geçersiz/, endpoint);
    }
    assert.equal(queries.length, 0);
  });

  it('kimliksiz istek 401 (adres denetimine ulasmaz)', async () => {
    const res = await put({ endpoint: FCM, keys: KEYS }, { auth: false });
    assert.equal(res.status, 401);
    assert.equal(queries.length, 0);
  });
});

describe('sendWebPushToUsers: gonderimden once yeniden denetim', () => {
  const row = (id, endpoint) => ({ id, endpoint, p256dh: KEYS.p256dh, auth: KEYS.auth });
  let originalSender;
  let senderCalls;
  let sent;
  let deleted;

  const makeDb = (rows) => ({
    query: async (text, params = []) => {
      const sql = norm(text);
      if (/^SELECT id, endpoint, p256dh, auth FROM web_push_subscriptions/.test(sql)) return { rows };
      if (/^DELETE FROM web_push_subscriptions WHERE id = ANY/.test(sql)) {
        deleted.push(params[0]);
        return { rowCount: params[0].length };
      }
      throw new Error(`SAHTE VERITABANI: tanimsiz SQL: ${sql}`);
    },
  });
  const installSender = (impl) => {
    webPushHooks.sender = async () => {
      senderCalls += 1;
      return { sendNotification: impl };
    };
  };

  before(() => {
    enableWebPush();
    originalSender = webPushHooks.sender;
  });
  after(() => {
    webPushHooks.sender = originalSender;
    restoreEnv();
  });
  beforeEach(() => {
    senderCalls = 0;
    sent = [];
    deleted = [];
  });

  it('izin disi (eski / elle eklenmis) kayitlara istek ATILMAZ ve satirlari silinir; izinli olanlara gonderilir', async () => {
    installSender(async (subscription) => {
      sent.push(subscription.endpoint);
      return { statusCode: 201 };
    });
    const db = makeDb([
      row(1, FCM),
      row(2, 'https://attacker.example/collect'),
      row(3, 'https://127.0.0.1:8443/internal'),
      row(4, APPLE),
      row(5, 'https://fcm.googleapis.com@attacker.example/fcm/send/abc12345'),
    ]);
    const count = await sendWebPushToUsers([48213], { title: 'Kargo geldi', body: 'Teslim alin.' }, db);
    assert.equal(count, 2);
    assert.deepEqual([...sent].sort(), [APPLE, FCM].sort());
    assert.deepEqual(deleted, [[2, 3, 5]]);
  });

  it('hepsi uygunsuzsa gonderici hic yuklenmez, sifir doner, satirlar silinir', async () => {
    installSender(async () => {
      throw new Error('cagrilmamali');
    });
    const db = makeDb([row(7, 'https://attacker.example/a'), row(8, 'http://fcm.googleapis.com/fcm/send/abc12345')]);
    assert.equal(await sendWebPushToUsers([48213], { title: 'x', body: 'y' }, db), 0);
    assert.equal(senderCalls, 0);
    assert.deepEqual(deleted, [[7, 8]]);
  });

  it('izinli adresin 410 yaniti satiri siler (onceki davranis korunur)', async () => {
    installSender(async () => {
      throw Object.assign(new Error('Gone'), { statusCode: 410 });
    });
    const db = makeDb([row(9, FCM)]);
    assert.equal(await sendWebPushToUsers([48213], { title: 'x', body: 'y' }, db), 0);
    assert.deepEqual(deleted, [[9]]);
  });

  it('abonelik yoksa ya da ozellik kapaliysa istek atilmaz', async () => {
    installSender(async () => ({ statusCode: 201 }));
    assert.equal(await sendWebPushToUsers([48213], { title: 'x', body: 'y' }, makeDb([])), 0);
    assert.equal(await sendWebPushToUsers([], { title: 'x', body: 'y' }, makeDb([row(1, FCM)])), 0);
    assert.equal(senderCalls, 0);
    delete process.env.WEB_PUSH_VAPID_PRIVATE;
    try {
      assert.equal(await sendWebPushToUsers([48213], { title: 'x', body: 'y' }, makeDb([row(1, FCM)])), 0);
    } finally {
      enableWebPush();
    }
    assert.equal(senderCalls, 0);
    assert.deepEqual(sent, []);
  });
});
