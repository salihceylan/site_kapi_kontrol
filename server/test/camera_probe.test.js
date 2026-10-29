// Kamera bağlantı "Sına"sı: yalnız genel adres denenir (SSRF), sonuçlar dürüst, denetim kaydı yazılır (DB'siz).
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import net from 'node:net';
import { EventEmitter } from 'node:events';

process.env.JWT_SECRET ||= 'test-secret-test-secret-test-secret-123456';

const { probeTcp } = await import('../src/modules/camera_probe.js');
const { probeTargetOf, testCamera } = await import('../src/modules/cctv_service.js');

const fakeSocket = (event) => {
  const socket = new EventEmitter();
  socket.setTimeout = () => {};
  socket.destroy = () => {};
  setImmediate(() => socket.emit(event));
  return socket;
};

describe('probeTcp', () => {
  it('yerel / özel adres sınanmaz ve bağlantı denenmez', async () => {
    let connected = false;
    for (const host of ['192.168.1.20', '127.0.0.1', '10.0.0.5', 'kamera.lan', 'localhost']) {
      const out = await probeTcp({ host, port: 80 }, { connect: () => { connected = true; return fakeSocket('connect'); } });
      assert.equal(out.ok, false);
      assert.equal(out.reason, 'not_testable');
    }
    assert.equal(connected, false);
  });

  it('ad çözümlenemezse unresolved', async () => {
    const out = await probeTcp({ host: 'yok.example.com', port: 80 }, { resolve: async () => { throw new Error('ENOTFOUND'); } });
    assert.deepEqual([out.ok, out.reason], [false, 'unresolved']);
  });

  it('bağlanır / reddedilir / zaman aşımı; ham hata metni sızmaz', async () => {
    const resolve = async () => ({ address: '203.0.113.7', family: 4 });
    assert.deepEqual(await probeTcp({ host: 'a.example.com', port: 554 }, { resolve, connect: () => fakeSocket('connect') }).then((o) => [o.ok, o.reason]), [true, 'connected']);
    const refused = await probeTcp({ host: 'a.example.com', port: 554 }, { resolve, connect: () => fakeSocket('error') });
    assert.deepEqual([refused.ok, refused.reason], [false, 'refused']);
    assert.equal(JSON.stringify(refused).includes('203.0.113.7'), false);
    const slow = await probeTcp({ host: 'a.example.com', port: 554 }, { resolve, connect: () => fakeSocket('timeout') });
    assert.deepEqual([slow.ok, slow.reason], [false, 'timeout']);
  });

  it('gerçek TCP: dinleyen yuvaya ulaşır (çözümleme enjekte)', async () => {
    const server = net.createServer((s) => s.destroy());
    await new Promise((r) => server.listen(0, '127.0.0.1', r));
    try {
      const out = await probeTcp({ host: 'x.example.com', port: server.address().port }, { resolve: async () => ({ address: '127.0.0.1', family: 4 }) });
      assert.equal(out.reason, 'connected');
    } finally {
      server.close();
    }
  });
});

describe('CCTV Sına', () => {
  const row = (extra) => ({ id: 5, name: 'Giriş', location: null, kind: 'ip_camera', channel: null, clip_url_template: null, snapshot_url: null, username: null, password_enc: null, is_active: true, created_at: new Date(), ...extra });

  it('hedef: önce anlık görüntü adresi, sonra şablonun ana bilgisayarı; yoksa null', () => {
    assert.deepEqual(probeTargetOf(row({ snapshot_url: 'https://cam.example.com:8443/snap.jpg' })), { host: 'cam.example.com', port: 8443 });
    assert.deepEqual(probeTargetOf(row({ clip_url_template: 'https://nvr.example.com/rec?s={start}&c={channel}' })), { host: 'nvr.example.com', port: 443 });
    assert.equal(probeTargetOf(row({})), null);
  });

  it('sınar ve denetim kaydı yazar; sonuç kimlik bilgisi içermez', async () => {
    const audits = [];
    const db = {
      async query(sql, params) {
        if (/FROM cctv_cameras/.test(sql)) return { rows: [row({ snapshot_url: 'https://cam.example.com/snap.jpg', username: 'admin', password_enc: 'v1:x:y:z' })] };
        if (/INSERT INTO audit_log/.test(sql)) audits.push(params);
        return { rows: [] };
      },
    };
    const out = await testCamera({ siteCode: 1, rawId: '5', actor: { userCode: 1, role: 'manager' } }, { db, probe: async () => ({ ok: false, reason: 'not_testable', message: 'yerel' }) });
    assert.deepEqual([out.ok, out.reason], [false, 'not_testable']);
    assert.equal(JSON.stringify(out).includes('admin'), false);
    assert.equal(audits.length, 1);
    assert.equal(audits[0][3], 'cctv.connection_tested');
  });

  it('pasif kamera 409, olmayan kamera 404, adressiz kamera 409', async () => {
    const make = (rows) => ({ async query() { return { rows }; } });
    const run = (rows) => testCamera({ siteCode: 1, rawId: '5', actor: null }, { db: make(rows), probe: async () => ({ ok: true, reason: 'connected', message: '' }) });
    await assert.rejects(run([]), (e) => e.statusCode === 404);
    await assert.rejects(run([row({ is_active: false, snapshot_url: 'https://cam.example.com/s.jpg' })]), (e) => e.code === 'CAMERA_INACTIVE');
    await assert.rejects(run([row({})]), (e) => e.code === 'NO_CONNECTION_INFO');
  });
});
