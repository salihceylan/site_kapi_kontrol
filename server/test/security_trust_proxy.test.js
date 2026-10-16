// S-C: trust proxy ve istemci IP'si (X-Forwarded-For sahteciliği hız sınırlarını atlatamaz).
import { describe, it, before, after } from 'node:test';
import assert from 'node:assert/strict';
import express from 'express';
import {
  CLOUDFLARE_TRUST_WARNING,
  DEFAULT_TRUST_PROXY,
  createTrustProxyMonitor,
  resolveTrustProxy,
} from '../src/security/trust_proxy.js';
import { expandIpv6, ipBucket, isPublicIp, normalizeIp } from '../src/security/client_ip.js';
import { clientIp, createRuleLimiter } from '../src/middlewares/rate_limiters.js';
import { isCloudflareIp } from '../src/security/cloudflare_ranges.js';
import { validateEnv } from '../src/config/env.js';

// Express'in gerçek req.ip hesaplaması (proxy-addr) ile, gerçek soket açmadan: eş adresi + başlık.
function reqIpWith(trustSetting, { remoteAddress, xff }) {
  const app = express();
  app.set('trust proxy', trustSetting);
  const req = Object.create(app.request);
  req.app = app;
  req.headers = xff === undefined ? {} : { 'x-forwarded-for': xff };
  req.connection = { remoteAddress };
  req.socket = req.connection;
  return req.ip;
}

describe('resolveTrustProxy', () => {
  it('varsayılan "loopback"; boş değer de varsayılan', () => {
    assert.equal(DEFAULT_TRUST_PROXY, 'loopback');
    assert.deepEqual(resolveTrustProxy({}), { value: 'loopback', warnings: [] });
    assert.equal(resolveTrustProxy({ TRUST_PROXY: '  ' }).value, 'loopback');
  });

  it('false/0/off -> vekil yok; true -> reddedilir (uyarı + loopback)', () => {
    for (const raw of ['false', '0', 'off', 'none']) {
      assert.equal(resolveTrustProxy({ TRUST_PROXY: raw }).value, false, raw);
    }
    const all = resolveTrustProxy({ TRUST_PROXY: 'true' });
    assert.equal(all.value, 'loopback');
    assert.equal(all.warnings.length, 1);
  });

  it('atlama sayısı kabul edilir ama uyarılır; aralık dışı reddedilir', () => {
    const one = resolveTrustProxy({ TRUST_PROXY: '1' });
    assert.equal(one.value, 1);
    assert.equal(one.warnings.length, 1);
    assert.equal(resolveTrustProxy({ TRUST_PROXY: '9' }).value, 'loopback');
  });

  it('ad / IP / CIDR listesi doğrulanır; geçersiz girdi -> loopback + uyarı', () => {
    assert.equal(resolveTrustProxy({ TRUST_PROXY: 'loopback' }).value, 'loopback');
    assert.deepEqual(resolveTrustProxy({ TRUST_PROXY: 'loopback, 10.0.0.0/8, fd00::/8' }).value, ['loopback', '10.0.0.0/8', 'fd00::/8']);
    assert.equal(resolveTrustProxy({ TRUST_PROXY: '127.0.0.1' }).value, '127.0.0.1');
    for (const bad of ['10.0.0.0/33', 'nginx', '999.1.1.1', 'loopback,abc']) {
      const result = resolveTrustProxy({ TRUST_PROXY: bad });
      assert.equal(result.value, 'loopback', bad);
      assert.equal(result.warnings.length, 1, bad);
    }
  });

  it('"cloudflare" takma adı yayımlanan aralıklara açılır; loopback’siz kullanımda uyarı', () => {
    const both = resolveTrustProxy({ TRUST_PROXY: 'loopback,cloudflare' });
    assert.ok(Array.isArray(both.value));
    assert.equal(both.value[0], 'loopback');
    assert.ok(both.value.includes('173.245.48.0/20'));
    assert.ok(both.value.includes('2606:4700::/32'));
    assert.deepEqual(both.warnings, []);
    assert.equal(resolveTrustProxy({ TRUST_PROXY: 'cloudflare' }).warnings.length, 1);
  });

  it('isPublicIp: loopback / özel / bağlantı-yerel / CGNAT / ULA genel değildir', () => {
    for (const ip of ['127.0.0.1', '::1', '10.0.0.1', '172.20.1.1', '192.168.0.10', '169.254.1.1', '100.64.1.1', 'fd00::1', 'fe80::1', '::ffff:10.0.0.1', '', 'x']) {
      assert.equal(isPublicIp(ip), false, ip);
    }
    for (const ip of ['198.51.100.7', '8.8.8.8', '2001:4860::8888', '::ffff:8.8.8.8']) {
      assert.equal(isPublicIp(ip), true, ip);
    }
  });

  it('isCloudflareIp', () => {
    assert.equal(isCloudflareIp('173.245.48.10'), true);
    assert.equal(isCloudflareIp('::ffff:104.16.1.1'), true);
    assert.equal(isCloudflareIp('2606:4700:10::6816:1'), true);
    assert.equal(isCloudflareIp('198.51.100.7'), false);
    assert.equal(isCloudflareIp(''), false);
  });

  it('validateEnv TRUST_PROXY uyarılarını taşır', () => {
    const { warnings } = validateEnv({ JWT_SECRET: 'k9Fz-test-only-long-secret-value-0123456789abcdef', TRUST_PROXY: 'true' });
    assert.ok(warnings.some((warning) => /TRUST_PROXY=true/.test(warning)));
  });
});

describe('req.ip: X-Forwarded-For sahteciliği', () => {
  it('ESKİ ayar (1): 8080’e doğrudan gelen saldırgan başlıkla istediği IP’yi req.ip yapabiliyordu', () => {
    assert.equal(reqIpWith(1, { remoteAddress: '203.0.113.9', xff: '1.2.3.4' }), '1.2.3.4');
  });

  it('YENİ ayar (loopback): doğrudan gelen istekte başlık YOK SAYILIR, req.ip gerçek eştir', () => {
    const trust = resolveTrustProxy({}).value;
    assert.equal(reqIpWith(trust, { remoteAddress: '203.0.113.9', xff: '1.2.3.4' }), '203.0.113.9');
    assert.equal(reqIpWith(trust, { remoteAddress: '::ffff:203.0.113.9', xff: '1.2.3.4' }), '::ffff:203.0.113.9');
  });

  it('nginx (127.0.0.1) üzerinden: istemcinin eklediği sahte değerler değil, nginx’in eklediği son halka', () => {
    const trust = resolveTrustProxy({}).value;
    // nginx: proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for -> "<istemcinin yazdığı>, <gerçek istemci>"
    assert.equal(reqIpWith(trust, { remoteAddress: '127.0.0.1', xff: '1.2.3.4, 198.51.100.7' }), '198.51.100.7');
    assert.equal(reqIpWith(trust, { remoteAddress: '::1', xff: '198.51.100.7' }), '198.51.100.7');
    assert.equal(reqIpWith(trust, { remoteAddress: '::ffff:127.0.0.1', xff: '198.51.100.7' }), '198.51.100.7');
    // İstemci "127.0.0.1" yazsa bile nginx gerçek adresi sona ekler: güvenilmeyen ilk halka gerçek istemcidir.
    assert.equal(reqIpWith(trust, { remoteAddress: '127.0.0.1', xff: '127.0.0.1, 198.51.100.7' }), '198.51.100.7');
  });

  it('loopback,cloudflare: Cloudflare -> nginx zincirinde gerçek istemci; kökene doğrudan gelen saldırgan IP uyduramaz', () => {
    const trust = resolveTrustProxy({ TRUST_PROXY: 'loopback,cloudflare' }).value;
    // istemci kendi sahte XFF'ini yollar; Cloudflare gerçek istemciyi ekler; nginx Cloudflare kenarını ekler.
    assert.equal(reqIpWith(trust, { remoteAddress: '127.0.0.1', xff: '1.2.3.4, 198.51.100.7, 173.245.48.10' }), '198.51.100.7');
    // Kökene (nginx) doğrudan bağlanan saldırgan: nginx onun gerçek adresini sona ekler -> güvenilmez, req.ip = saldırgan.
    assert.equal(reqIpWith(trust, { remoteAddress: '127.0.0.1', xff: '1.2.3.4, 173.245.48.10, 203.0.113.66' }), '203.0.113.66');
    // Varsayılan (loopback) ile aynı zincirde req.ip Cloudflare kenarı olur (tüm kullanıcılar ortak IP).
    assert.equal(reqIpWith(resolveTrustProxy({}).value, { remoteAddress: '127.0.0.1', xff: '198.51.100.7, 173.245.48.10' }), '173.245.48.10');
  });

  it('TRUST_PROXY=false: başlık hiçbir durumda kullanılmaz', () => {
    assert.equal(reqIpWith(false, { remoteAddress: '127.0.0.1', xff: '198.51.100.7' }), '127.0.0.1');
  });
});

describe('createTrustProxyMonitor: Cloudflare arkasında TRUST_PROXY eksikse tek seferlik açık uyarı', () => {
  it('req.ip Cloudflare kenar adresiyse TEK SEFER uyarır; istekleri değiştirmez; genel IP’de sessiz', () => {
    const lines = [];
    const monitor = createTrustProxyMonitor({ logger: { warn: (line) => lines.push(line) } });
    let nextCalls = 0;
    const next = () => {
      nextCalls += 1;
    };
    monitor({ ip: '198.51.100.7' }, {}, next);
    assert.equal(lines.length, 0);
    monitor({ ip: '172.67.10.20' }, {}, next);
    monitor({ ip: '104.21.3.4' }, {}, next);
    monitor({ ip: '::ffff:173.245.48.10' }, {}, next);
    assert.equal(nextCalls, 4);
    assert.equal(lines.length, 1);
    assert.equal(lines[0], CLOUDFLARE_TRUST_WARNING);
    assert.match(lines[0], /TRUST_PROXY=loopback,cloudflare gerekli: tum istekler Cloudflare adresiyle gorunuyor/);
    assert.equal(monitor.hasWarned(), true);
  });

  it('TRUST_PROXY=loopback,cloudflare ile zincir çözülünce req.ip gerçek istemcidir: uyarı yok', () => {
    const lines = [];
    const monitor = createTrustProxyMonitor({ logger: { warn: (line) => lines.push(line) } });
    const trust = resolveTrustProxy({ TRUST_PROXY: 'loopback,cloudflare' }).value;
    const ip = reqIpWith(trust, { remoteAddress: '127.0.0.1', xff: '198.51.100.7, 172.67.10.20' });
    monitor({ ip }, {}, () => {});
    assert.equal(ip, '198.51.100.7');
    assert.equal(lines.length, 0);
  });
});

describe('IP kovası (IPv6 /64) ve sınırlayıcı anahtarı', () => {
  it('normalizeIp / expandIpv6 / ipBucket', () => {
    assert.equal(normalizeIp('::ffff:198.51.100.7'), '198.51.100.7');
    assert.equal(normalizeIp('FE80::1%eth0'), 'fe80::1');
    assert.equal(normalizeIp('garbage'), '');
    assert.deepEqual(expandIpv6('2001:db8::1'), ['2001', 'db8', '0', '0', '0', '0', '0', '1']);
    assert.deepEqual(expandIpv6('64:ff9b::198.51.100.7'), ['64', 'ff9b', '0', '0', '0', '0', 'c633', '6407']);
    assert.equal(ipBucket('198.51.100.7'), '198.51.100.7');
    assert.equal(ipBucket('2001:db8:1:2:3:4:5:6'), '2001:db8:1:2::/64');
    assert.equal(ipBucket('2001:db8:1:2::ffff'), '2001:db8:1:2::/64');
    assert.equal(ipBucket('::1'), '0:0:0:0::/64');
    assert.equal(ipBucket(''), 'unknown');
  });

  it('aynı /64 içinde adres değiştiren IPv6 istemci aynı kovaya düşer (sınır atlatılamaz)', () => {
    const limiter = createRuleLimiter({ rules: [{ windowMs: 60_000, max: 3, key: (req) => `ip:${clientIp(req)}` }], message: 'x' });
    const results = [];
    for (let i = 1; i <= 5; i += 1) {
      const req = { ip: `2001:db8:abcd:12::${i.toString(16)}`, socket: {} };
      const res = { statusCode: 200, setHeader() {}, status(code) { this.statusCode = code; return this; }, json() { return this; } };
      let passed = false;
      limiter(req, res, () => {
        passed = true;
      });
      results.push(passed);
    }
    assert.deepEqual(results, [true, true, true, false, false]);
  });
});

describe('HTTP: gerçek Express + trust proxy (loopback)', () => {
  let server;
  let baseUrl;
  before(async () => {
    const app = express();
    app.set('trust proxy', resolveTrustProxy({}).value);
    app.get('/ip', (req, res) => res.json({ ip: req.ip, bucket: clientIp(req) }));
    await new Promise((resolve) => {
      server = app.listen(0, '127.0.0.1', resolve);
    });
    baseUrl = `http://127.0.0.1:${server.address().port}`;
  });
  after(() => new Promise((resolve) => {
    server.closeAllConnections?.();
    server.close(resolve);
  }));

  it('loopback eşten gelen X-Forwarded-For son halkası kullanılır; başlıksız istekte soket adresi', async () => {
    const withHeader = await (await fetch(`${baseUrl}/ip`, { headers: { 'X-Forwarded-For': '1.2.3.4, 198.51.100.7' } })).json();
    assert.equal(withHeader.ip, '198.51.100.7');
    const plain = await (await fetch(`${baseUrl}/ip`)).json();
    assert.match(plain.ip, /127\.0\.0\.1$/);
  });
});
