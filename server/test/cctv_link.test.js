// Kamera (CCTV) baglantisi (072): sema <-> migration, katalog, sablon, SSRF korumasi, hizmet kurallari, uc listesi.
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { EventEmitter } from 'node:events';
import { Readable } from 'node:stream';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { DEFAULT_MIGRATIONS_DIR, findUnsafeStatements } from '../scripts/migrate.js';
import { CCTV_STEPS, cctvMigrationBody, ensureCctvSchema, schemaTuning } from '../src/modules/cctv_schema.js';
import { MODULE_CATALOG } from '../src/modules/catalog.js';
import {
  fetchSnapshot,
  isLocalHostname,
  isPublicIp,
  parseSnapshotUrl,
  resolvePublicAddress,
} from '../src/modules/cctv_snapshot.js';
import * as svc from '../src/modules/cctv_service.js';
import { cctvRouter } from '../src/modules/cctv_routes.js';
import { decryptSecret } from '../src/modules/device_integrations_service.js';

schemaTuning.retryDelayMs = 1;
process.env.JWT_SECRET ||= 'cctv-test-secret';
const here = path.dirname(fileURLToPath(import.meta.url));
const norm = (s) => s.replace(/\r\n/g, '\n').replace(/--.*$/gm, '').replace(/\s+/g, ' ').trim();
const MIGRATION = readFileSync(path.join(DEFAULT_MIGRATIONS_DIR, '072_cctv_link.sql'), 'utf8');
const DB_SOURCE = readFileSync(path.join(here, '..', 'src', 'db.js'), 'utf8');
const SERVER_SOURCE = readFileSync(path.join(here, '..', 'src', 'server.js'), 'utf8');

describe('cctv sema', () => {
  it('migration 072 govdesi adimlarin birlesimidir', () => {
    assert.ok(norm(MIGRATION).includes(norm(cctvMigrationBody())));
  });
  it('ekleyici ve idempotent: DROP/DELETE/UPDATE yok, hepsi IF NOT EXISTS korumali', () => {
    for (const step of CCTV_STEPS) {
      assert.doesNotMatch(step.sql, /\b(DROP|TRUNCATE|DELETE FROM|UPDATE)\b/i);
      assert.match(step.sql, /IF NOT EXISTS/);
    }
    assert.deepEqual(findUnsafeStatements(MIGRATION), []);
  });
  it('sira: tablolar, FK, indeks; iki tablo', () => {
    const kinds = CCTV_STEPS.map((s) => s.kind);
    assert.deepEqual(kinds, [...kinds].sort((a, b) => ['table', 'fk', 'index'].indexOf(a) - ['table', 'fk', 'index'].indexOf(b)));
    assert.deepEqual(CCTV_STEPS.filter((s) => s.kind === 'table').map((s) => s.name), ['cctv_cameras', 'cctv_camera_doors']);
  });
  it('db.js ensureCctvSchema cagirir; server.js router kaydeder (tek satir)', () => {
    assert.match(DB_SOURCE, /await ensureCctvSchema\(client\)/);
    assert.match(SERVER_SOURCE, /app\.use\(cctvRouter\)/);
  });
  it('her sey varsa hicbir DDL gonderilmez; eksikse yalniz eksikler calisir', async () => {
    const all = CCTV_STEPS.map((s) => s.name);
    const sent = [];
    const mk = (present) => ({
      async query(sql) {
        if (/unnest/.test(sql)) {
          return { rows: [{ tables: present.filter((n) => n.startsWith('cctv_') && !n.endsWith('_fkey')), fks: present.filter((n) => n.endsWith('_fkey')), indexes: present.filter((n) => n.startsWith('idx_')) }] };
        }
        sent.push(sql);
        return { rows: [] };
      },
    });
    await ensureCctvSchema(mk(all));
    assert.equal(sent.length, 0);
    await ensureCctvSchema(mk(all.filter((n) => n !== 'idx_cctv_camera_doors_door')));
    assert.equal(sent.filter((s) => /CREATE INDEX/.test(s)).length, 1);
  });
  it('modul katalogda var, kullanilabilir ve varsayilan KAPALI', () => {
    const entry = MODULE_CATALOG.find((m) => m.code === 'cctv_link');
    assert.ok(entry);
    assert.equal(entry.status, 'available');
    assert.equal(entry.defaultEnabled, false);
    assert.equal(entry.core, false);
  });
});

describe('cctv kayit baglanti sablonu', () => {
  const ok = 'https://nvr.example.com/playback?ch={channel}&from={start}&to={end}&cam={camera}';
  it('gecerli sablon aynen kabul edilir; bos / yok null', () => {
    assert.equal(svc.parseClipTemplate(ok), ok);
    assert.equal(svc.parseClipTemplate(''), null);
    assert.equal(svc.parseClipTemplate(undefined), null);
    assert.equal(svc.parseClipTemplate('https://192.168.1.20:8443/p?s={start_unix}&e={end_unix}'), 'https://192.168.1.20:8443/p?s={start_unix}&e={end_unix}');
  });
  it('https disi, kullanici bilgisi, bilinmeyen yer tutucu, adreste yer tutucu, bosluk reddedilir', () => {
    for (const bad of [
      'http://nvr.example.com/p?c={channel}',
      'ftp://nvr.example.com/p',
      'javascript:alert(1)',
      '//nvr.example.com/p',
      'https://user:pw@nvr.example.com/p',
      'https://nvr.example.com/p?x={secret}',
      'https://{camera}.example.com/p',
      'https://nvr.example.com:{channel}/p',
      'https://nvr.example.com/p?x={start',
      'https://nvr.example.com/p x',
    ]) {
      assert.throws(() => svc.parseClipTemplate(bad), { code: 'INVALID_FIELD' }, bad);
    }
    assert.throws(() => svc.parseClipTemplate(`https://a.example.com/${'x'.repeat(1001)}`), { code: 'INVALID_FIELD' });
  });
  it('olay zamani -30 sn / +30 sn ile doldurulur; degerler adres kodlamasindan gecer', () => {
    const filled = svc.fillClipTemplate(ok, { openedAt: '2026-10-22T12:00:00.000Z', channel: 'ch 1', cameraName: 'Giriş & Kapı' });
    assert.equal(filled.start, '2026-10-22T11:59:30.000Z');
    assert.equal(filled.end, '2026-10-22T12:00:30.000Z');
    assert.equal(
      filled.url,
      `https://nvr.example.com/playback?ch=ch%201&from=2026-10-22T11%3A59%3A30Z&to=2026-10-22T12%3A00%3A30Z&cam=${encodeURIComponent('Giriş & Kapı')}`,
    );
    const unix = svc.fillClipTemplate('https://h.example.com/p?s={start_unix}&e={end_unix}', { openedAt: new Date('2026-10-22T12:00:00Z') });
    assert.equal(unix.url, `https://h.example.com/p?s=${Date.parse('2026-10-22T11:59:30Z') / 1000}&e=${Date.parse('2026-10-22T12:00:30Z') / 1000}`);
  });
  it('kotu niyetli ad ana bilgisayari degistiremez', () => {
    const filled = svc.fillClipTemplate('https://nvr.example.com/p?c={camera}', { openedAt: new Date(), cameraName: '@evil.com/#' });
    assert.equal(new URL(filled.url).hostname, 'nvr.example.com');
    assert.throws(() => svc.fillClipTemplate(ok, { openedAt: 'bozuk' }), { code: 'INVALID_FIELD' });
  });
});

describe('cctv SSRF korumasi', () => {
  it('isPublicIp: ozel, yerel, link-local, yayin, eslenmis adresler engel; genel adres serbest', () => {
    for (const ip of ['127.0.0.1', '10.1.2.3', '172.16.0.1', '172.31.255.255', '192.168.1.1', '169.254.169.254', '100.64.0.1', '0.0.0.0', '224.0.0.1', '255.255.255.255', '198.18.0.1', '::1', '::', 'fe80::1', 'fc00::1', 'fd12:3456::1', '::ffff:127.0.0.1', '::ffff:10.0.0.1', '::ffff:8.8.8.8', 'ff02::1', '64:ff9b::7f00:1', '2002:7f00:1::', 'bozuk', '']) {
      assert.equal(isPublicIp(ip), false, ip);
    }
    for (const ip of ['8.8.8.8', '1.1.1.1', '93.184.216.34', '172.32.0.1', '2606:4700:4700::1111', '2001:4860:4860::8888']) {
      assert.equal(isPublicIp(ip), true, ip);
    }
  });
  it('isLocalHostname: localhost, tek etiketli ve yerel sonekler', () => {
    for (const host of ['localhost', 'camera', 'nvr.local', 'a.localhost', 'cam.internal', 'x.lan', '']) assert.equal(isLocalHostname(host), true, host);
    assert.equal(isLocalHostname('cam.example.com'), false);
  });
  it('parseSnapshotUrl: yalniz herkese acik https', () => {
    assert.ok(parseSnapshotUrl('https://cam.example.com/snap.jpg?token=1'));
    assert.ok(parseSnapshotUrl('https://8.8.8.8:8443/snap'));
    for (const bad of [
      'http://cam.example.com/snap.jpg',
      'https://localhost/snap',
      'https://127.0.0.1/snap',
      'https://2130706433/snap',
      'https://0x7f.0.0.1/snap',
      'https://[::1]/snap',
      'https://[::ffff:10.0.0.1]/snap',
      'https://10.0.0.5/snap',
      'https://192.168.1.10:8443/snap',
      'https://169.254.169.254/latest/meta-data',
      'https://user:pw@cam.example.com/snap',
      'https://intranet/snap',
      'file:///etc/passwd',
      'gopher://cam.example.com/',
      '',
      'bozuk',
    ]) {
      assert.equal(parseSnapshotUrl(bad), null, bad);
    }
  });
  it('kayit sirasinda yerel adres reddedilir (INVALID_FIELD)', () => {
    assert.equal(svc.parseSnapshotAddress('https://cam.example.com/snap.jpg'), 'https://cam.example.com/snap.jpg');
    assert.throws(() => svc.parseSnapshotAddress('https://192.168.1.10/snap'), { code: 'INVALID_FIELD' });
    assert.throws(() => svc.parseSnapshotAddress('http://cam.example.com/snap'), { code: 'INVALID_FIELD' });
  });
  it('resolvePublicAddress: tum adresler genel olmali (biri bile ozelse null)', async () => {
    const pub = async () => [{ address: '93.184.216.34', family: 4 }];
    const mixed = async () => [{ address: '93.184.216.34', family: 4 }, { address: '10.0.0.7', family: 4 }];
    const priv = async () => [{ address: '127.0.0.1', family: 4 }];
    const none = async () => [];
    assert.deepEqual(await resolvePublicAddress('cam.example.com', pub), { address: '93.184.216.34', family: 4 });
    assert.equal(await resolvePublicAddress('cam.example.com', mixed), null);
    assert.equal(await resolvePublicAddress('cam.example.com', priv), null);
    assert.equal(await resolvePublicAddress('cam.example.com', none), null);
    assert.deepEqual(await resolvePublicAddress('8.8.8.8', async () => assert.fail('IP icin ad cozumlemesi beklenmez')), { address: '8.8.8.8', family: 4 });
    assert.equal(await resolvePublicAddress('10.0.0.1', async () => assert.fail('IP icin ad cozumlemesi beklenmez')), null);
  });
});

const JPEG = Buffer.concat([Buffer.from([0xff, 0xd8, 0xff, 0xe0]), Buffer.alloc(64, 1)]);
const PNG = Buffer.concat([Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]), Buffer.alloc(32, 2)]);
const publicLookup = async () => [{ address: '93.184.216.34', family: 4 }];

/** Node'un https.request arayuzunu taklit eder; hicbir ag baglantisi yapilmaz. */
function fakeRequest({ status = 200, headers = { 'content-type': 'image/jpeg' }, chunks = [JPEG], hang = false, capture = {} } = {}) {
  return (options, callback) => {
    capture.options = options;
    capture.calls = (capture.calls ?? 0) + 1;
    const req = new EventEmitter();
    req.destroyed = false;
    req.destroy = () => {
      req.destroyed = true;
    };
    req.end = () => {
      if (hang) return;
      const res = Readable.from(chunks);
      res.statusCode = status;
      res.headers = headers;
      callback(res);
    };
    return req;
  };
}

describe('cctv anlik goruntu cekme', () => {
  it('basarili: JPEG ve PNG; baglanti dogrulanan adrese sabitlenir, Basic kimlik gonderilir, yonlendirme yok', async () => {
    const capture = {};
    const result = await fetchSnapshot('https://cam.example.com/snap.jpg?x=1', { username: 'admin', password: 'p@ss', lookup: publicLookup, request: fakeRequest({ capture }) });
    assert.equal(result.ok, true);
    assert.equal(result.contentType, 'image/jpeg');
    assert.deepEqual(result.body, JPEG);
    assert.equal(capture.options.protocol, 'https:');
    assert.equal(capture.options.hostname, 'cam.example.com');
    assert.equal(capture.options.path, '/snap.jpg?x=1');
    assert.equal(capture.options.agent, false);
    assert.equal(capture.options.headers.Authorization, `Basic ${Buffer.from('admin:p@ss').toString('base64')}`);
    const pinned = await new Promise((resolve) => capture.options.lookup('cam.example.com', {}, (_e, address, family) => resolve({ address, family })));
    assert.deepEqual(pinned, { address: '93.184.216.34', family: 4 });
    const pinnedAll = await new Promise((resolve) => capture.options.lookup('cam.example.com', { all: true }, (_e, list) => resolve(list)));
    assert.deepEqual(pinnedAll, [{ address: '93.184.216.34', family: 4 }]);
    const png = await fetchSnapshot('https://cam.example.com/s.png', { lookup: publicLookup, request: fakeRequest({ headers: { 'content-type': 'image/png; charset=binary' }, chunks: [PNG] }) });
    assert.equal(png.ok, true);
    assert.equal(png.contentType, 'image/png');
  });
  it('ozel adrese cozumlenen ad / yerel adres: HICBIR istek yapilmaz', async () => {
    const capture = {};
    const priv = await fetchSnapshot('https://cam.example.com/s.jpg', { lookup: async () => [{ address: '192.168.1.5', family: 4 }], request: fakeRequest({ capture }) });
    assert.deepEqual(priv, { ok: false, reason: 'blocked' });
    const mixed = await fetchSnapshot('https://cam.example.com/s.jpg', { lookup: async () => [{ address: '8.8.8.8', family: 4 }, { address: '127.0.0.1', family: 4 }], request: fakeRequest({ capture }) });
    assert.deepEqual(mixed, { ok: false, reason: 'blocked' });
    for (const url of ['https://127.0.0.1/s', 'https://localhost/s', 'http://cam.example.com/s', 'https://[::1]/s', 'https://169.254.169.254/x']) {
      assert.deepEqual(await fetchSnapshot(url, { lookup: publicLookup, request: fakeRequest({ capture }) }), { ok: false, reason: 'blocked' }, url);
    }
    assert.equal(capture.calls ?? 0, 0);
  });
  it('yonlendirme izlenmez; 200 disi durum, yanlis tur, sahte govde, buyuk govde ulasilamaz sayilir', async () => {
    const run = (req) => fetchSnapshot('https://cam.example.com/s', { lookup: publicLookup, request: req, maxBytes: 100 });
    assert.deepEqual(await run(fakeRequest({ status: 302, headers: { location: 'https://127.0.0.1/', 'content-type': 'image/jpeg' } })), { ok: false, reason: 'status' });
    assert.deepEqual(await run(fakeRequest({ status: 401 })), { ok: false, reason: 'status' });
    assert.deepEqual(await run(fakeRequest({ headers: { 'content-type': 'text/html' }, chunks: [Buffer.from('<script>')] })), { ok: false, reason: 'content_type' });
    assert.deepEqual(await run(fakeRequest({ headers: { 'content-type': 'image/svg+xml' }, chunks: [Buffer.from('<svg/>')] })), { ok: false, reason: 'content_type' });
    assert.deepEqual(await run(fakeRequest({ chunks: [Buffer.from('bu bir resim degil')] })), { ok: false, reason: 'content_type' });
    assert.deepEqual(await run(fakeRequest({ headers: { 'content-type': 'image/jpeg', 'content-length': '5000' } })), { ok: false, reason: 'too_large' });
    assert.deepEqual(await run(fakeRequest({ chunks: [JPEG, Buffer.alloc(80, 3)] })), { ok: false, reason: 'too_large' });
  });
  it('5 sn zaman asimi (kisaltilmis) ve ag hatasi', async () => {
    const slow = await fetchSnapshot('https://cam.example.com/s', { lookup: publicLookup, request: fakeRequest({ hang: true }), timeoutMs: 20 });
    assert.deepEqual(slow, { ok: false, reason: 'timeout' });
    const boom = await fetchSnapshot('https://cam.example.com/s', {
      lookup: publicLookup,
      request: () => {
        throw new Error('baglanti');
      },
    });
    assert.deepEqual(boom, { ok: false, reason: 'network' });
    const dnsFail = await fetchSnapshot('https://cam.example.com/s', {
      lookup: async () => {
        throw new Error('ENOTFOUND');
      },
      request: fakeRequest(),
    });
    assert.deepEqual(dnsFail, { ok: false, reason: 'network' });
  });
});

// --- Hizmet kurallari (sahte veritabani) ---------------------------------------------------------------------------

function fakeDb(handlers) {
  const log = [];
  return {
    log,
    audits: () => log.filter((e) => /INSERT INTO audit_log/.test(e.sql)).map((e) => ({ action: e.params[3], target: e.params[6], details: JSON.parse(e.params[7]) })),
    async query(sql, params = []) {
      log.push({ sql, params });
      if (/INSERT INTO audit_log/.test(sql)) return { rows: [] };
      for (const [pattern, reply] of handlers) {
        if (pattern.test(sql)) return typeof reply === 'function' ? reply(sql, params) : reply;
      }
      throw new Error(`beklenmeyen sorgu: ${sql.slice(0, 60)}`);
    },
  };
}

const ACTOR = { user_code: 7, full_name: 'Yonetici', role: 'site_manager' };
const NOW = new Date('2026-10-22T09:00:00Z');
const cameraRow = (extra = {}) => ({
  id: '5',
  name: 'Giris kamerasi',
  location: 'A blok girisi',
  kind: 'ip_camera',
  channel: '101',
  clip_url_template: 'https://nvr.example.com/p?ch={channel}&s={start}&e={end}',
  snapshot_url: 'https://cam.example.com/snap.jpg',
  username: 'admin',
  password_enc: 'v1:x:y:z',
  is_active: true,
  created_at: NOW,
  ...extra,
});

describe('cctv hizmet', () => {
  it('mapCamera: kimlik bilgisi ASLA donmez; sablon / adres yalniz yazma yetkisinde', () => {
    const row = cameraRow();
    const writer = svc.mapCamera(row, [{ door_id: '2', door_name: 'Ana kapi' }], true);
    const reader = svc.mapCamera(row, [], false);
    for (const out of [writer, reader]) {
      const json = JSON.stringify(out);
      assert.doesNotMatch(json, /password|admin|v1:x:y:z/);
      assert.equal(out.has_credentials, true);
      assert.equal('username' in out, false);
    }
    assert.equal(writer.clip_url_template, row.clip_url_template);
    assert.equal(writer.snapshot_url, row.snapshot_url);
    assert.equal('clip_url_template' in reader, false);
    assert.equal('snapshot_url' in reader, false);
    assert.deepEqual(writer.doors, [{ id: 2, name: 'Ana kapi' }]);
  });

  it('girdi: ad zorunlu, tur, kanal, kapi listesi, bilinmeyen alan yok sayilir', () => {
    assert.throws(() => svc.parseCameraInput({ name: '' }), { code: 'INVALID_FIELD' });
    assert.throws(() => svc.parseCameraInput({ kind: 'dome' }), { code: 'INVALID_FIELD' });
    assert.throws(() => svc.parseCameraInput({ channel: 'a b/c' }), { code: 'INVALID_FIELD' });
    assert.throws(() => svc.parseCameraInput({ door_ids: ['x'] }), { code: 'INVALID_FIELD' });
    assert.throws(() => svc.parseCameraInput({ door_ids: Array.from({ length: 21 }, (_, i) => i + 1) }), { code: 'INVALID_FIELD' });
    assert.throws(() => svc.parseCameraInput([]), { code: 'INVALID_BODY' });
    const ok = svc.parseCameraInput({ name: '  Giris   kamerasi ', kind: 'nvr_channel', channel: '101', door_ids: [1, '2', 2], is_admin: true });
    assert.deepEqual(ok, { name: 'Giris kamerasi', kind: 'nvr_channel', channel: '101', door_ids: [1, 2] });
  });

  it('createCamera: en az bir baglanti, parola icin kullanici adi, kapi bu sitede olmali; parola sifreli yazilir', async () => {
    const mk = () =>
      fakeDb([
        [/COUNT\(\*\)/, { rows: [{ n: 0 }] }],
        [/FROM site_doors WHERE site_code/, (_s, p) => ({ rows: p[1].filter((id) => id === 2).map((id) => ({ id })) })],
        [/INSERT INTO cctv_cameras/, { rows: [cameraRow()] }],
        [/DELETE FROM cctv_camera_doors/, { rows: [] }],
        [/INSERT INTO cctv_camera_doors/, { rows: [] }],
        [/FROM cctv_camera_doors cd JOIN site_doors/, { rows: [{ camera_id: '5', door_id: '2', door_name: 'Ana kapi' }] }],
      ]);
    await assert.rejects(svc.createCamera({ siteCode: 1, actor: ACTOR, userCode: 7, body: { name: 'K' } }, mk()), { code: 'INVALID_FIELD' });
    await assert.rejects(
      svc.createCamera({ siteCode: 1, actor: ACTOR, userCode: 7, body: { name: 'K', snapshot_url: 'https://cam.example.com/s.jpg', password: 'x' } }, mk()),
      (e) => e.code === 'INVALID_FIELD' && e.extra.field === 'username',
    );
    await assert.rejects(
      svc.createCamera({ siteCode: 1, actor: ACTOR, userCode: 7, body: { name: 'K', snapshot_url: 'https://cam.example.com/s.jpg', door_ids: [9] } }, mk()),
      (e) => e.code === 'INVALID_FIELD' && e.extra.field === 'door_ids',
    );
    const db = mk();
    const out = await svc.createCamera(
      { siteCode: 1, actor: ACTOR, userCode: 7, body: { name: 'Giris kamerasi', snapshot_url: 'https://cam.example.com/snap.jpg', username: 'admin', password: 'gizli-parola', door_ids: [2] } },
      db,
    );
    assert.equal(out.camera.id, 5);
    assert.doesNotMatch(JSON.stringify(out), /gizli-parola|"username"/);
    const insert = db.log.find((e) => /INSERT INTO cctv_cameras/.test(e.sql));
    assert.notEqual(insert.params[8], 'gizli-parola');
    assert.equal(decryptSecret(insert.params[8]), 'gizli-parola');
    assert.deepEqual(db.audits().map((a) => a.action), ['cctv.camera_created']);
    assert.doesNotMatch(JSON.stringify(db.audits()), /gizli-parola|snap\.jpg/);
  });

  it('createCamera: kamera siniri (50)', async () => {
    const db = fakeDb([[/COUNT\(\*\)/, { rows: [{ n: svc.LIMITS.cameras }] }]]);
    await assert.rejects(
      svc.createCamera({ siteCode: 1, actor: ACTOR, userCode: 7, body: { name: 'K', snapshot_url: 'https://cam.example.com/s.jpg' } }, db),
      { code: 'LIMIT_REACHED' },
    );
  });

  it('updateCamera: baska sitenin kamerasi 404; kimlik bilgisi temizlenir; son baglanti kaldirilamaz', async () => {
    const empty = fakeDb([[/FROM cctv_cameras WHERE id/, { rows: [] }]]);
    await assert.rejects(svc.updateCamera({ siteCode: 2, rawId: '5', actor: ACTOR, body: { name: 'X' } }, empty), { code: 'NOT_FOUND' });
    const handlers = (row) => [
      [/FROM cctv_cameras WHERE id/, { rows: [row] }],
      [/UPDATE cctv_cameras SET/, (_s, p) => ({ rows: [cameraRow({ username: p[8], password_enc: p[9] })] })],
      [/FROM cctv_camera_doors cd JOIN site_doors/, { rows: [] }],
    ];
    const db = fakeDb(handlers(cameraRow()));
    const out = await svc.updateCamera({ siteCode: 1, rawId: '5', actor: ACTOR, body: { clear_credentials: true } }, db);
    const update = db.log.find((e) => /UPDATE cctv_cameras SET/.test(e.sql));
    assert.equal(update.params[8], null);
    assert.equal(update.params[9], null);
    assert.equal(out.camera.has_credentials, false);
    await assert.rejects(
      svc.updateCamera({ siteCode: 1, rawId: '5', actor: ACTOR, body: { clip_url_template: null, snapshot_url: null } }, fakeDb(handlers(cameraRow()))),
      { code: 'INVALID_FIELD' },
    );
    const withAudit = fakeDb(handlers(cameraRow()));
    await svc.updateCamera({ siteCode: 1, rawId: '5', actor: ACTOR, body: { password: 'yeni-parola' } }, withAudit);
    assert.deepEqual(withAudit.audits()[0].details.fields, ['password']);
    assert.doesNotMatch(JSON.stringify(withAudit.audits()), /yeni-parola/);
  });

  it('deleteCamera: yalniz kendi sitesinde; denetim kaydi', async () => {
    const db = fakeDb([[/DELETE FROM cctv_cameras/, (_s, p) => ({ rows: p[1] === 1 ? [{ id: 5, name: 'K' }] : [] })]]);
    await assert.rejects(svc.deleteCamera({ siteCode: 2, rawId: '5', actor: ACTOR }, db), { code: 'NOT_FOUND' });
    assert.deepEqual(await svc.deleteCamera({ siteCode: 1, rawId: '5', actor: ACTOR }, db), { ok: true });
    assert.deepEqual(db.audits().map((a) => a.action), ['cctv.camera_deleted']);
  });

  it('getSnapshot: basarida goruntu + denetim; ulasilamazsa 424 ve yine denetim; adres yoksa 424', async () => {
    const found = (row) => fakeDb([[/FROM cctv_cameras WHERE id/, { rows: row ? [row] : [] }]]);
    let seen = null;
    const okFetcher = async (url, creds) => {
      seen = { url, creds };
      return { ok: true, contentType: 'image/jpeg', body: JPEG };
    };
    const { encryptSecret } = await import('../src/modules/device_integrations_service.js');
    const db = found(cameraRow({ password_enc: encryptSecret('kamera-parola') }));
    const out = await svc.getSnapshot({ siteCode: 1, rawId: '5', actor: ACTOR }, { db, fetcher: okFetcher });
    assert.equal(out.contentType, 'image/jpeg');
    assert.deepEqual(seen, { url: 'https://cam.example.com/snap.jpg', creds: { username: 'admin', password: 'kamera-parola' } });
    assert.deepEqual(db.audits().map((a) => [a.action, a.details.delivered]), [['cctv.snapshot_viewed', true]]);

    const failDb = found(cameraRow());
    await assert.rejects(
      svc.getSnapshot({ siteCode: 1, rawId: '5', actor: ACTOR }, { db: failDb, fetcher: async () => ({ ok: false, reason: 'blocked' }) }),
      (e) => e.statusCode === 424 && e.code === 'SNAPSHOT_UNAVAILABLE' && e.message === 'Bu kameraya sunucudan ulaşılamıyor; kayıt bağlantısını kullanın.',
    );
    assert.deepEqual(failDb.audits().map((a) => [a.action, a.details.delivered, a.details.reason]), [['cctv.snapshot_viewed', false, 'blocked']]);

    await assert.rejects(svc.getSnapshot({ siteCode: 1, rawId: '5', actor: ACTOR }, { db: found(cameraRow({ snapshot_url: null })), fetcher: okFetcher }), { code: 'SNAPSHOT_UNAVAILABLE' });
    await assert.rejects(svc.getSnapshot({ siteCode: 2, rawId: '5', actor: ACTOR }, { db: found(null), fetcher: okFetcher }), { code: 'NOT_FOUND' });
    await assert.rejects(svc.getSnapshot({ siteCode: 1, rawId: '5', actor: ACTOR }, { db: found(cameraRow({ is_active: false })), fetcher: okFetcher }), { code: 'CAMERA_INACTIVE' });
  });

  it('listEvents: olayin kapisina eslenmis aktif kameralar; kisi adi yalniz yazma yetkisinde; kapi gunlugu salt okunur', async () => {
    const mk = () =>
      fakeDb([
        [
          /FROM door_access_logs/,
          {
            rows: [
              { id: '90', door_id: '2', door_name: 'Ana kapi', user_name: 'Ayse Yilmaz', apartment_label: 'A-3', trigger_type: 'cloud_app', opened_at: NOW },
              { id: '89', door_id: null, door_name: 'Silinmis kapi', user_name: 'Can', apartment_label: null, trigger_type: 'qr_scanner', opened_at: NOW },
            ],
          },
        ],
        [/FROM cctv_camera_doors cd JOIN cctv_cameras c/, { rows: [{ door_id: '2', id: '5', name: 'Giris kamerasi', location: null, has_clip_link: true, has_snapshot: false }] }],
      ]);
    const writerDb = mk();
    const writer = await svc.listEvents(1, { canWrite: true }, { limit: '500' }, writerDb);
    assert.equal(writer.events[0].user_name, 'Ayse Yilmaz');
    assert.deepEqual(writer.events[0].cameras, [{ id: 5, name: 'Giris kamerasi', location: null, has_clip_link: true, has_snapshot: false }]);
    assert.deepEqual(writer.events[1].cameras, []);
    assert.deepEqual(writer.window_seconds, { before: 30, after: 30 });
    assert.equal(writerDb.log[0].params[2], svc.LIMITS.events);
    const reader = await svc.listEvents(1, { canWrite: false }, {}, mk());
    assert.equal(reader.events[0].user_name, null);
    assert.equal(reader.events[0].apartment_label, null);
    for (const entry of writerDb.log) assert.doesNotMatch(entry.sql, /\b(INSERT|UPDATE|DELETE)\b[^;]*door_access_logs/i);
    assert.equal(writerDb.audits().length, 0);
  });

  it('openClipLink: sablon doldurulur, denetim kaydi yazilir; eslenmemis kamera / baska site olayi 404', async () => {
    const mk = ({ logRows, cameraRows }) =>
      fakeDb([
        [/FROM door_access_logs/, { rows: logRows }],
        [/FROM cctv_cameras c JOIN cctv_camera_doors cd/, (_s, p) => ({ rows: Number(p[2]) === 2 ? cameraRows : [] })],
      ]);
    const log = [{ id: '90', door_id: '2', opened_at: new Date('2026-10-22T12:00:00Z') }];
    const cam = [{ id: '5', name: 'Giris', channel: '101', clip_url_template: 'https://nvr.example.com/p?ch={channel}&s={start}&e={end}' }];
    const db = mk({ logRows: log, cameraRows: cam });
    const out = await svc.openClipLink({ siteCode: 1, actor: ACTOR, body: { log_id: 90, camera_id: '5' } }, db);
    assert.equal(out.url, 'https://nvr.example.com/p?ch=101&s=2026-10-22T11%3A59%3A30Z&e=2026-10-22T12%3A00%3A30Z');
    assert.deepEqual(db.audits().map((a) => [a.action, a.target, a.details]), [['cctv.clip_opened', '5', { log_id: 90 }]]);
    assert.doesNotMatch(JSON.stringify(db.audits()), /nvr\.example\.com/);

    const noLog = mk({ logRows: [], cameraRows: cam });
    await assert.rejects(svc.openClipLink({ siteCode: 1, actor: ACTOR, body: { log_id: 91, camera_id: 5 } }, noLog), { code: 'NOT_FOUND' });
    assert.equal(noLog.audits().length, 0);
    const unlinked = mk({ logRows: [{ id: '90', door_id: '3', opened_at: NOW }], cameraRows: cam });
    await assert.rejects(svc.openClipLink({ siteCode: 1, actor: ACTOR, body: { log_id: 90, camera_id: 5 } }, unlinked), { code: 'NOT_FOUND' });
    assert.equal(unlinked.audits().length, 0);
    const noTemplate = mk({ logRows: log, cameraRows: [{ ...cam[0], clip_url_template: null }] });
    await assert.rejects(svc.openClipLink({ siteCode: 1, actor: ACTOR, body: { log_id: 90, camera_id: 5 } }, noTemplate), { code: 'NO_CLIP_LINK' });
    await assert.rejects(svc.openClipLink({ siteCode: 1, actor: ACTOR, body: { log_id: 'x', camera_id: 5 } }, db), { code: 'INVALID_FIELD' });
  });

  it('meta: KVKK notu, yer tutucular ve pencere', () => {
    const meta = svc.metaInfo();
    assert.match(meta.kvkk_note, /kişisel veridir/);
    assert.deepEqual(meta.placeholders, ['start', 'end', 'start_unix', 'end_unix', 'channel', 'camera']);
    assert.deepEqual(meta.clip_window_seconds, { before: 30, after: 30 });
  });
});

describe('cctv uclar', () => {
  const routes = cctvRouter.stack.filter((l) => l.route).map((l) => ({ path: l.route.path, methods: Object.keys(l.route.methods), handlers: l.route.stack.length }));
  const has = (method, p) => routes.some((r) => r.path === `/manager/sites/:siteCode/cctv${p}` && r.methods.includes(method));
  it('beklenen uclar kayitli; hepsi kimlik dogrulama + hiz siniri + isleyici (3 katman)', () => {
    for (const [method, p] of [
      ['get', '/meta'],
      ['get', '/doors'],
      ['get', '/cameras'],
      ['post', '/cameras'],
      ['patch', '/cameras/:id'],
      ['delete', '/cameras/:id'],
      ['get', '/cameras/:id/snapshot'],
      ['get', '/events'],
      ['post', '/clip-link'],
    ]) {
      assert.ok(has(method, p), `${method} ${p}`);
    }
    for (const r of routes) assert.equal(r.handlers, 3, r.path);
  });
  it('sakine acik uc yok: tum yollar /manager/sites altinda', () => {
    for (const r of routes) assert.match(r.path, /^\/manager\/sites\/:siteCode\/cctv/);
  });
});
