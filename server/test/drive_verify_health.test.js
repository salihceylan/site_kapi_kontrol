// Drive aktarım doğrulaması (P2-2), sağlık göstergesi (P2-17) ve kota akışı (P2-18) — DB'siz (sahte veritabanı + sahte Drive istemcisi).
// P2-2: Drive'ın bildirdiği SHA-256 bizim hesapladığımızla karşılaştırılır; uyuşmazsa kopya çöpe alınır, dosya sunucuda KUYRUĞA döner (silinmez) ve yöneticiye uyarı düşer.
// P2-17: getStatus().health = bağlantı / belirteç / son başarılı aktarım / bekleyen kuyruk / kota. P2-18: %90 kota uyarısı; "kuyruk dolu" ile "Google kotası dolu" ayrı kod + Türkçe mesaj.
// K6 korunur: hiçbir testte bekleyen dosya ya da geçici dosya silinmez. Gerçek Google ve gerçek PostgreSQL yok (kullanıcı denemesi / QA).
import { describe, it, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import { mkdtempSync, rmSync, existsSync } from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { createDriveService } from '../src/modules/drive_service.js';
import { DriveError, createDriveClient } from '../src/modules/drive_client.js';
import { PENDING_MAX_BYTES, buildDriveHealth, encryptToken, quotaInfo, verifyDriveCopy } from '../src/modules/drive_common.js';
import { runDriveHealthTick } from '../src/modules/drive_health_scheduler.js';

const SITE = 1000000001;
const KEY = 'k'.repeat(40);
const CONFIG = { configured: true, clientId: 'id', clientSecret: 's', redirectUri: 'https://x/cb', tokenKey: KEY };
const PDF = Buffer.from('%PDF-1.7 deneme');
const GB = 1024 ** 3;
const norm = (t) => String(t).replace(/\s+/g, ' ').trim();
const sha = (buf) => crypto.createHash('sha256').update(buf).digest('hex');
const QUERY = { kind: 'dekont', mime: 'application/pdf', date: '2026-10-20' };

let st;
let dir;
let calls;
let mode;
let drive;
let svc;

function makeDb() {
  return {
    async query(text, params = []) {
      const sql = norm(text);
      if (/^SELECT \* FROM site_drive_connections/.test(sql)) return { rows: st.conn ? [{ ...st.conn }] : [] };
      if (/^SELECT name FROM sites/.test(sql)) return { rows: [{ name: 'Güneş Sitesi' }] };
      if (/^UPDATE site_drive_connections SET status = 'error'/.test(sql)) { st.conn.status = 'error'; st.conn.last_error = params[1]; return { rows: [] }; }
      if (/^UPDATE site_drive_connections SET quota_limit_bytes/.test(sql)) {
        Object.assign(st.conn, { quota_limit_bytes: params[1], quota_used_bytes: params[2], health_checked_at: new Date(st.clock) });
        return { rows: [] };
      }
      if (/^UPDATE site_drive_connections SET token_expires_at/.test(sql)) { st.conn.token_expires_at = params[1]; return { rows: [] }; }
      if (/^INSERT INTO drive_files/.test(sql)) {
        const row = { id: st.nextId++, site_code: params[0], kind: params[1], folder_name: params[2], name: params[3], mime_type: params[4], size_bytes: params[5], sha256: params[6], status: 'pending', created_at: new Date(st.clock) };
        st.files.set(row.id, row);
        return { rows: [row] };
      }
      if (/^UPDATE drive_files SET status = 'stored'/.test(sql)) {
        const row = st.files.get(params[0]);
        Object.assign(row, { status: 'stored', drive_file_id: params[1], verify_method: params[2], stored_at: new Date(st.clock) });
        return { rows: [row] };
      }
      if (/^DELETE FROM drive_files/.test(sql)) { st.files.delete(params[0]); return { rows: [] }; }
      if (/^INSERT INTO drive_pending_uploads/.test(sql)) {
        st.pending.push({ file_id: params[0], site_code: params[1], storage_path: params[2], expires_at: params[3], last_error: params[4], error_kind: params[5], attempts: 0 });
        return { rows: [] };
      }
      if (/^SELECT COALESCE\(SUM\(f\.size_bytes\), 0\)::bigint AS bytes FROM drive_pending_uploads/.test(sql)) return { rows: [{ bytes: st.pendingBytes ?? 0 }] };
      if (/^SELECT COUNT\(\*\)::int AS n, COALESCE\(SUM/.test(sql)) {
        const ids = st.pending.map((p) => p.file_id);
        return {
          rows: [{
            n: ids.length,
            bytes: st.pendingBytes ?? ids.reduce((sum, id) => sum + st.files.get(id).size_bytes, 0),
            overdue: 0,
            oldest: ids.length ? st.files.get(ids[0]).created_at : null,
            integrity: st.pending.filter((p) => p.error_kind === 'integrity').length,
            quota_blocked: st.pending.filter((p) => p.error_kind === 'quota').length,
            max_attempts: Math.max(0, ...st.pending.map((p) => p.attempts)),
          }],
        };
      }
      if (/^SELECT COUNT\(\*\)::int AS n FROM drive_files/.test(sql)) return { rows: [{ n: [...st.files.values()].filter((f) => f.status === 'stored').length }] };
      if (/^SELECT MAX\(stored_at\) AS at FROM drive_files/.test(sql)) {
        const times = [...st.files.values()].filter((f) => f.status === 'stored').map((f) => f.stored_at);
        return { rows: [{ at: times.length ? times[times.length - 1] : null }] };
      }
      if (/^SELECT last_error FROM drive_pending_uploads/.test(sql)) {
        const withError = st.pending.filter((p) => p.last_error);
        return { rows: withError.length ? [{ last_error: withError[withError.length - 1].last_error }] : [] };
      }
      if (/^SELECT p\.\*, f\.name/.test(sql)) {
        return { rows: st.pending.map((p) => ({ ...p, name: st.files.get(p.file_id).name, folder_name: st.files.get(p.file_id).folder_name, mime_type: 'application/pdf', sha256: st.files.get(p.file_id).sha256, file_status: st.files.get(p.file_id).status })) };
      }
      if (/^UPDATE drive_pending_uploads SET attempts/.test(sql)) {
        const item = st.pending.find((p) => p.file_id === params[0]);
        Object.assign(item, { attempts: item.attempts + 1, last_error: params[2], error_kind: params[3] });
        return { rows: [] };
      }
      if (/^DELETE FROM drive_pending_uploads/.test(sql)) { st.pending = st.pending.filter((p) => p.file_id !== params[0]); return { rows: [] }; }
      if (/^SELECT COUNT\(\*\)::int AS n, COUNT\(\*\) FILTER \(WHERE expires_at/.test(sql)) return { rows: [{ n: st.pending.length, overdue: 0 }] };
      if (/^INSERT INTO audit_log/.test(sql)) { st.audits.push({ action: params[3], details: JSON.parse(params[7]) }); return { rows: [] }; }
      return { rows: [] };
    },
  };
}

function makeClient() {
  return {
    async refreshAccess() { return { accessToken: 'AT', expiresIn: 3600 }; },
    async ensureFolder(_t, name) { return `F-${name}`; },
    async uploadFile(_t, args) {
      calls.push(['upload', args.name]);
      if (mode.up === 'quota') throw new DriveError('quota', 'storageQuotaExceeded', 403);
      if (mode.up === 'down') throw new DriveError('transient', 'ağ');
      const id = `D-${args.name}`;
      drive.set(id, args.data);
      const sum = mode.sum === 'omit' ? null : mode.sum === 'bad' ? '0'.repeat(64) : sha(args.data);
      return { id, size: args.data.length, sha256: sum };
    },
    async getFileMeta(_t, id) {
      calls.push(['meta', id]);
      if (mode.meta === 'fail') throw new DriveError('transient', 'ağ');
      return { id, sha256: mode.meta === 'bad' ? '1'.repeat(64) : sha(drive.get(id)) };
    },
    async trashFile(_t, id) { calls.push(['trash', id]); },
    async aboutQuota() { return mode.quota; },
  };
}

const auditsOf = (action) => st.audits.filter((a) => a.action === action);

beforeEach(() => {
  dir = mkdtempSync(path.join(os.tmpdir(), 'drive-health-'));
  st = {
    conn: { site_code: SITE, status: 'connected', account_email: 'site@example.com', refresh_token_enc: encryptToken('R', KEY), root_folder_id: null, folder_ids: {} },
    files: new Map(), nextId: 1, pending: [], pendingBytes: null, audits: [], clock: new Date(2026, 9, 20, 12, 0, 0),
  };
  calls = [];
  drive = new Map();
  mode = { up: 'up', sum: 'ok', meta: 'ok', quota: { limit: 15 * GB, usage: 1 * GB } };
  svc = createDriveService({ db: makeDb(), client: makeClient(), config: CONFIG, pendingDir: dir, now: () => new Date(st.clock) });
});
afterEach(() => rmSync(dir, { recursive: true, force: true }));

describe('P2-2 aktarim dogrulamasi (SHA-256)', () => {
  it('saf kural: eslesme / uyusmazlik / sagalama toplami yok / teyitsiz', () => {
    const good = sha(PDF);
    assert.equal(verifyDriveCopy({ id: 'a', size: PDF.length, sha256: good.toUpperCase() }, good, PDF.length).state, 'sha256');
    assert.equal(verifyDriveCopy({ id: 'a', size: PDF.length, sha256: '0'.repeat(64) }, good, PDF.length).state, 'mismatch');
    assert.equal(verifyDriveCopy({ id: 'a', size: PDF.length, sha256: null }, good, PDF.length).state, 'size');
    assert.equal(verifyDriveCopy({ id: 'a', size: PDF.length + 1, sha256: good }, good, PDF.length).state, 'unconfirmed');
    assert.equal(verifyDriveCopy(null, good, PDF.length).state, 'unconfirmed');
  });

  it('eslesen SHA-256: kayit stored + verify_method sha256; kopya cope alinmaz', async () => {
    const out = await svc.upload({ siteCode: SITE, actor: {}, query: QUERY, data: PDF });
    assert.equal(out.file.status, 'stored');
    assert.equal(st.files.get(out.file.id).verify_method, 'sha256');
    assert.equal(calls.filter((c) => c[0] === 'trash').length, 0);
  });

  it('UYUSMAYAN SHA-256: dogrudan yuklemede dosya kuyruga doner (silinmez), bozuk Drive kopyasi cope alinir, yoneticiye uyari duser', async () => {
    mode.sum = 'bad';
    const out = await svc.upload({ siteCode: SITE, actor: {}, query: QUERY, data: PDF });
    assert.equal(out.file.status, 'pending', "'stored' yazilmadi");
    assert.equal(st.pending.length, 1);
    assert.equal(st.pending[0].error_kind, 'integrity');
    assert.match(st.pending[0].last_error, /SHA-256/);
    assert.ok(existsSync(st.pending[0].storage_path), 'sunucudaki asil kopya duruyor (K6)');
    assert.deepEqual(calls.filter((c) => c[0] === 'trash'), [['trash', `D-${out.file.name}`]], 'yalniz bu cagrinin olusturdugu bozuk kopya cope alindi');
    assert.equal(auditsOf('drive.integrity_mismatch').length, 1);
    const status = await svc.getStatus(SITE);
    assert.ok(status.warnings.some((w) => w.code === 'DRIVE_INTEGRITY_FAILED' && /silinmedi/.test(w.message)));
    assert.equal(status.health.state, 'warning');
    assert.equal(status.health.queue.integrity_failed_count, 1);
  });

  it('sagalama toplami yukleme yanitinda yoksa ust veriden sorulur: eslesirse sha256, sorulamazsa kimlik+boyut (size)', async () => {
    mode.sum = 'omit';
    const a = await svc.upload({ siteCode: SITE, actor: {}, query: QUERY, data: PDF });
    assert.equal(st.files.get(a.file.id).verify_method, 'sha256');
    assert.equal(calls.filter((c) => c[0] === 'meta').length, 1);
    mode.meta = 'fail';
    const b = await svc.upload({ siteCode: SITE, actor: {}, query: QUERY, data: PDF });
    assert.equal(b.file.status, 'stored', 'ust veri sorulamadi diye iyi dosya kuyruga atilmaz');
    assert.equal(st.files.get(b.file.id).verify_method, 'size');
    mode.meta = 'bad';
    const c = await svc.upload({ siteCode: SITE, actor: {}, query: QUERY, data: PDF });
    assert.equal(c.file.status, 'pending', 'ust veri uyusmuyorsa bozuk sayilir');
  });

  it('kuyruktaki dosya gonderimde uyusmazsa KUYRUKTA KALIR (deneme sayisi artar, gecici dosya durur); sonra dogru kopya gidince temizlenir', async () => {
    mode.up = 'down';
    const out = await svc.upload({ siteCode: SITE, actor: {}, query: QUERY, data: PDF });
    const temp = st.pending[0].storage_path;
    mode.up = 'up';
    mode.sum = 'bad';
    const first = await svc.flushPending(SITE, { force: true });
    assert.equal(first.sent, 0);
    assert.equal(first.waiting, 1);
    assert.equal(st.pending[0].attempts, 1);
    assert.equal(st.pending[0].error_kind, 'integrity');
    assert.equal(st.files.get(out.file.id).status, 'pending');
    assert.ok(existsSync(temp));
    mode.sum = 'ok';
    const second = await svc.flushPending(SITE, { force: true });
    assert.equal(second.sent, 1);
    assert.equal(st.pending.length, 0);
    assert.equal(st.files.get(out.file.id).verify_method, 'sha256');
    assert.ok(!existsSync(temp), 'gecici dosya YALNIZ dogrulanmis aktarimdan sonra silindi');
  });
});

describe('P2-18 kota akisi', () => {
  it('%90 ve ustu yonetici uyarisi (denetim kaydi + durum uyarisi); %89 uyari vermez; %100 "doldu"', async () => {
    mode.quota = { limit: 100 * GB, usage: 89 * GB };
    let out = await svc.checkHealth(SITE);
    assert.equal(out.checked, true);
    assert.equal(out.quota.percent, 89);
    assert.equal(auditsOf('drive.quota_near_full').length, 0);
    assert.deepEqual((await svc.getStatus(SITE)).warnings, []);

    mode.quota = { limit: 100 * GB, usage: 91 * GB };
    out = await svc.checkHealth(SITE);
    assert.equal(out.quota.state, 'near_full');
    assert.equal(auditsOf('drive.quota_near_full').length, 1);
    let status = await svc.getStatus(SITE);
    assert.deepEqual(status.warnings.map((w) => w.code), ['DRIVE_QUOTA_NEAR_FULL']);
    assert.match(status.warnings[0].message, /%91/);
    assert.match(status.warnings[0].message, /silinmez/);
    assert.equal(status.health.quota.percent, 91);

    st.clock = new Date(st.clock.getTime() + 2 * 60 * 60 * 1000);
    mode.quota = { limit: 100 * GB, usage: 100 * GB };
    await svc.checkHealth(SITE);
    status = await svc.getStatus(SITE);
    assert.deepEqual(status.warnings.map((w) => w.code), ['DRIVE_QUOTA_FULL']);
    assert.equal(auditsOf('drive.quota_full').length, 1);
  });

  it('sinirsiz hesap (limit yok) uyari vermez; kota okunamazsa (ag) kota bilinmiyor kalir, baglanti bozulmaz', async () => {
    mode.quota = { limit: null, usage: 3 * GB };
    await svc.checkHealth(SITE);
    const status = await svc.getStatus(SITE);
    assert.equal(status.health.quota.unlimited, true);
    assert.deepEqual(status.warnings, []);
    st.conn.status = 'connected';
    mode.quota = Promise.reject(new DriveError('transient', 'ag'));
    mode.quota.catch(() => {});
    const failed = await svc.checkHealth(SITE);
    assert.equal(failed.checked, false);
    assert.equal(st.conn.status, 'connected');
  });

  it('Google kotasi dolu: dosya reddedilmez, "Google Drive depolama alani dolu" nedeniyle bekler; kuyruk dolu uyarisindan AYRI kod', async () => {
    mode.up = 'quota';
    const out = await svc.upload({ siteCode: SITE, actor: {}, query: QUERY, data: PDF });
    assert.equal(out.file.status, 'pending');
    assert.equal(st.pending[0].error_kind, 'quota');
    assert.match(st.pending[0].last_error, /Google Drive depolama alanı dolu/);
    assert.equal(auditsOf('drive.quota_full').length, 1);
    const status = await svc.getStatus(SITE);
    const codes = status.warnings.map((w) => w.code);
    assert.ok(codes.includes('DRIVE_QUOTA_FULL') && !codes.includes('DRIVE_QUEUE_FULL'));
    assert.equal(status.health.queue.quota_blocked_count, 1);
    assert.match(status.health.queue.last_error, /Google Drive depolama alanı dolu/);
  });

  it('bekleme alani da doluysa: neden kota ise 503 DRIVE_QUOTA_FULL (Google hesabinda yer acin), neden baglanti ise 503 DRIVE_QUEUE_FULL; hicbiri dosya silmez', async () => {
    mode.up = 'down';
    const kept = await svc.upload({ siteCode: SITE, actor: {}, query: QUERY, data: PDF });
    const keptPath = st.pending[0].storage_path;
    st.pendingBytes = PENDING_MAX_BYTES;
    await assert.rejects(
      svc.upload({ siteCode: SITE, actor: {}, query: { ...QUERY, date: '2026-10-21' }, data: PDF }),
      (e) => e.code === 'DRIVE_QUEUE_FULL' && e.statusCode === 503,
    );
    mode.up = 'quota';
    await assert.rejects(
      svc.upload({ siteCode: SITE, actor: {}, query: { ...QUERY, date: '2026-10-22' }, data: PDF }),
      (e) => e.code === 'DRIVE_QUOTA_FULL' && e.statusCode === 503 && /Google hesabında yer açın/.test(e.message) && /silinmedi/.test(e.message),
    );
    assert.equal(st.files.get(kept.file.id).status, 'pending');
    assert.ok(existsSync(keptPath), 'bekleyen dosya silinmedi (K6)');
    assert.equal(st.pending.length, 1);
  });

  it('gonderimde Google kotasi dolu cikarsa tur durur (kalan dosyalar bos yere denenmez), hicbiri silinmez', async () => {
    mode.up = 'down';
    await svc.upload({ siteCode: SITE, actor: {}, query: QUERY, data: PDF });
    await svc.upload({ siteCode: SITE, actor: {}, query: { ...QUERY, date: '2026-10-21' }, data: PDF });
    calls.length = 0;
    mode.up = 'quota';
    const report = await svc.flushPending(SITE, { force: true });
    assert.equal(calls.filter((c) => c[0] === 'upload').length, 1, 'ilk dosyadan sonra durdu');
    assert.equal(report.sent, 0);
    assert.equal(report.waiting, 2);
    assert.equal(st.pending[0].error_kind, 'quota');
  });
});

describe('P2-17 saglik gostergesi', () => {
  it('bagli + saglikli: bagli hesap, belirtec, son basarili aktarim, bos kuyruk, kota', async () => {
    await svc.upload({ siteCode: SITE, actor: {}, query: QUERY, data: PDF });
    await svc.checkHealth(SITE);
    const { health, last_transfer_at: lastTransfer } = await svc.getStatus(SITE);
    assert.equal(health.state, 'ok');
    assert.equal(health.connection.status, 'connected');
    assert.equal(health.connection.account_email, 'site@example.com');
    assert.equal(health.token.state, 'valid');
    assert.ok(health.token.expires_at && health.token.checked_at);
    assert.deepEqual(health.last_transfer_at, lastTransfer);
    assert.ok(health.last_transfer_at);
    assert.equal(health.queue.pending_count, 0);
    assert.equal(health.quota.state, 'ok');
  });

  it('kopuk / izin geri alinmis / yapilandirma yok / bekleyen: durum ve Turkce mesaj', async () => {
    const at = new Date(2026, 9, 20, 12, 0, 0);
    assert.equal(buildDriveHealth({ configured: false, now: at }).state, 'not_configured');
    assert.equal(buildDriveHealth({ conn: { status: 'disconnected' }, now: at }).state, 'disconnected');
    const lost = buildDriveHealth({ conn: { status: 'error', last_error: 'x' }, now: at });
    assert.equal(lost.state, 'error');
    assert.equal(lost.token.state, 'invalid');
    assert.match(lost.message, /yeniden bağlayın/);
    const waiting = buildDriveHealth({ conn: { status: 'connected' }, now: at, queue: { pendingCount: 2 } });
    assert.equal(waiting.state, 'ok');
    assert.match(waiting.message, /2 dosya/);
    assert.equal(waiting.token.state, 'refreshable');
    assert.equal(quotaInfo().state, 'unknown');
    // uzun suredir bekleyen / dolmak uzere kota: dikkat gerektirir
    assert.equal(buildDriveHealth({ conn: { status: 'connected' }, now: at, queue: { overdueCount: 1 } }).state, 'warning');
    assert.equal(buildDriveHealth({ conn: { status: 'connected' }, now: at, quota: quotaInfo({ limitBytes: 100, usedBytes: 95, checkedAt: at }) }).state, 'warning');
  });

  it('izin geri alinmissa saglik denetimi baglantiyi error yapar ve yoneticiye uyari duser', async () => {
    const revoked = createDriveService({
      db: makeDb(),
      client: { ...makeClient(), async refreshAccess() { throw new DriveError('auth', 'invalid_grant', 400); } },
      config: CONFIG,
      pendingDir: dir,
      now: () => new Date(st.clock),
    });
    const out = await revoked.checkHealth(SITE);
    assert.equal(out.checked, false);
    assert.equal(st.conn.status, 'error');
    assert.equal(auditsOf('drive.connection_lost').length, 1);
    const status = await revoked.getStatus(SITE);
    assert.equal(status.health.state, 'error');
  });
});

describe('zamanlayici (arka plan tiki)', () => {
  const hooks = (sites, extra = {}) => {
    const log = [];
    return {
      log,
      configured: () => true,
      listSites: async () => sites,
      flush: async (siteCode) => { log.push(['flush', siteCode]); return { sent: 2 }; },
      checkHealth: async (siteCode) => { log.push(['health', siteCode]); return { checked: true }; },
      ...extra,
    };
  };

  it('yapilandirma yoksa hicbir sey yapmaz; vakti gelen bekleyen gonderilir, saglik denetimi yalniz vadesi gelen sitede; bir sitenin hatasi digerini durdurmaz', async () => {
    const off = hooks([{ siteCode: 1, dueFiles: true, healthDue: true }], { configured: () => false });
    assert.deepEqual(await runDriveHealthTick({ hooks: off }), { sites: 0, flushed: 0, checked: 0 });
    assert.deepEqual(off.log, []);

    const h = hooks(
      [{ siteCode: 1, dueFiles: false, healthDue: false }, { siteCode: 2, dueFiles: true, healthDue: true }, { siteCode: 3, dueFiles: true, healthDue: true }],
      { flush: async (siteCode) => { if (siteCode === 2) throw new Error('boom'); h.log.push(['flush', siteCode]); return { sent: 1 }; } },
    );
    const summary = await runDriveHealthTick({ hooks: h, nowMs: 1_000_000_000 });
    assert.deepEqual(h.log, [['health', 2], ['flush', 3], ['health', 3]], '2. sitenin gonderim hatasi saglik denetimini ve 3. siteyi durdurmaz');
    assert.deepEqual(summary, { sites: 3, flushed: 1, checked: 2 });
  });

  it('basarisiz saglik denetimi sonrasi ayni siteye 30 dk icinde yeniden gidilmez', async () => {
    const failing = hooks([{ siteCode: 9, dueFiles: false, healthDue: true }], { checkHealth: async (siteCode) => { failing.log.push(['health', siteCode]); return { checked: false }; } });
    await runDriveHealthTick({ hooks: failing, nowMs: 5_000_000_000 });
    await runDriveHealthTick({ hooks: failing, nowMs: 5_000_000_000 + 10 * 60 * 1000 });
    assert.equal(failing.log.length, 1);
    await runDriveHealthTick({ hooks: failing, nowMs: 5_000_000_000 + 31 * 60 * 1000 });
    assert.equal(failing.log.length, 2);
  });
});

describe('Drive istemcisi (Google cagrilari sarmalanmis; fetch sahte)', () => {
  const respond = (body, status = 200) => ({ ok: status < 400, status, text: async () => JSON.stringify(body), headers: new Map() });

  it('yukleme sha256Checksum ister ve kucuk harfle dondurur; getFileMeta, trashFile (PATCH trashed), aboutQuota', async () => {
    const seen = [];
    const fetchImpl = async (url, init) => {
      seen.push({ url: String(url), method: init?.method ?? 'GET', body: typeof init?.body === 'string' ? init.body : null });
      if (String(url).includes('/upload/')) return respond({ id: 'F1', size: '15', sha256Checksum: 'ABCDEF' });
      if (String(url).includes('/about')) return respond({ storageQuota: { limit: '16106127360', usage: '1073741824' } });
      return respond({ id: 'F1', size: '15', sha256Checksum: 'ABCDEF', trashed: false });
    };
    const client = createDriveClient({ config: CONFIG, fetchImpl });
    const up = await client.uploadFile('T', { name: 'a.pdf', mimeType: 'application/pdf', parentId: 'P', data: PDF });
    assert.deepEqual(up, { id: 'F1', size: 15, sha256: 'abcdef' });
    assert.match(seen[0].url, /fields=id,size,sha256Checksum/);
    assert.equal((await client.getFileMeta('T', 'F1')).sha256, 'abcdef');
    await client.trashFile('T', 'F1');
    const trash = seen.find((s) => s.method === 'PATCH');
    assert.equal(JSON.parse(trash.body).trashed, true);
    assert.deepEqual(await client.aboutQuota('T'), { limit: 16106127360, usage: 1073741824 });
    const unlimited = createDriveClient({ config: CONFIG, fetchImpl: async () => respond({ storageQuota: { usage: '5' } }) });
    assert.deepEqual(await unlimited.aboutQuota('T'), { limit: null, usage: 5 });
  });

  it('403 storageQuotaExceeded = quota (depolama dolu); rateLimitExceeded = rate_limit (gecici); yetki 403 = auth', async () => {
    const kindOf = async (status, message) => {
      const client = createDriveClient({ config: CONFIG, fetchImpl: async () => respond({ error: { errors: [{ reason: message }] } }, status) });
      try {
        await client.uploadFile('T', { name: 'a.pdf', mimeType: 'application/pdf', parentId: 'P', data: PDF });
      } catch (error) {
        return error.kind;
      }
      return null;
    };
    assert.equal(await kindOf(403, 'storageQuotaExceeded'), 'quota');
    assert.equal(await kindOf(403, 'rateLimitExceeded'), 'rate_limit');
    assert.equal(await kindOf(429, 'userRateLimitExceeded'), 'rate_limit');
    assert.equal(await kindOf(403, 'insufficientFilePermissions'), 'auth');
    assert.equal(await kindOf(500, 'backendError'), 'transient');
  });
});
