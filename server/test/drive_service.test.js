// Site Drive deposu (D1) servisi (DB'siz, sahte veritabanı + sahte Drive istemcisi): bağlantı kapısı, klasör/dosya adı, çakışma eki, Drive'a gönderim,
// kopukken bekleme kuyruğu ve 100 MB sınırı, bekleyenlerin sonradan gönderimi, OAuth state tek kullanımlığı, belirtecin şifreli yazılması.
// K6 "silmeyi biz yapmayız": süre doldu diye silme YOK, kota dolunca yeni yükleme reddi + uyarı, geçici dosya yalnız Drive teyidinden sonra silinir.
// P1-11: dosya adına kayıt kimliği öneki (IS-123_...) ve Drive kaydının kaynak kayda bağlanması.
// Gerçek HTTP/Google ve gerçek PostgreSQL bu testte YOK (kullanıcı denemesi / QA).
import { describe, it, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, rmSync, existsSync, writeFileSync } from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { createDriveService } from '../src/modules/drive_service.js';
import { DriveError } from '../src/modules/drive_client.js';
import { PENDING_MAX_BYTES, PENDING_WARN_DAYS, decryptToken } from '../src/modules/drive_common.js';

const SITE = 1000000001;
const KEY = 'k'.repeat(40);
const CONFIG = { configured: true, clientId: 'id', clientSecret: 's', redirectUri: 'https://x/cb', tokenKey: KEY };
const norm = (t) => String(t).replace(/\s+/g, ' ').trim();
const PDF = Buffer.from('%PDF-1.7 deneme');
const DAY_MS = 24 * 60 * 60 * 1000;

let state;
let dir;
let clientCalls;
let clientMode;

function sumPendingBytes() {
  return state.pending.reduce((sum, p) => sum + Number(state.files.get(p.file_id)?.size_bytes ?? 0), 0);
}

function makeDb() {
  return {
    async query(text, params = []) {
      const sql = norm(text);
      state.log.push(sql);
      if (/^SELECT \* FROM site_drive_connections/.test(sql)) return { rows: state.conn ? [{ ...state.conn }] : [] };
      if (/^SELECT name FROM sites/.test(sql)) return { rows: [{ name: 'Güneş Sitesi' }] };
      if (/^UPDATE site_drive_connections SET status = 'disconnected'/.test(sql)) { state.conn.status = 'disconnected'; state.conn.refresh_token_enc = null; return { rows: [] }; }
      if (/^UPDATE site_drive_connections SET root_folder_id = \$2/.test(sql)) { state.conn.root_folder_id = params[1]; return { rows: [] }; }
      if (/^UPDATE site_drive_connections SET folder_ids = folder_ids/.test(sql)) { Object.assign(state.conn.folder_ids, JSON.parse(params[1])); return { rows: [] }; }
      if (/^INSERT INTO drive_files/.test(sql)) {
        const key = `${params[2]}/${params[3]}`;
        if (state.names.has(key)) return { rows: [] };
        state.names.add(key);
        const row = {
          id: state.nextId++, site_code: params[0], kind: params[1], folder_name: params[2], name: params[3], mime_type: params[4], size_bytes: params[5], sha256: params[6],
          status: 'pending', created_at: new Date(state.clock), source_type: params[8] ?? null, source_id: params[9] ?? null,
        };
        state.files.set(row.id, row);
        return { rows: [row] };
      }
      if (/^UPDATE drive_files SET status = 'stored'/.test(sql)) {
        const row = state.files.get(params[0]);
        row.status = 'stored';
        row.drive_file_id = params[1];
        return { rows: [row] };
      }
      if (/^DELETE FROM drive_files/.test(sql)) {
        const row = state.files.get(params[0]);
        // Korumalı silme (yeni açılmış, kuyruğa girmemiş satır): bekleyen kaydı olan ya da 'stored' satıra dokunmaz.
        if (/NOT EXISTS/.test(sql) && (!row || row.status !== 'pending' || state.pending.some((p) => p.file_id === params[0]))) return { rows: [] };
        if (row) state.names.delete(`${row.folder_name}/${row.name}`);
        state.files.delete(params[0]);
        return { rows: [] };
      }
      if (/^SELECT COUNT\(\*\)::int AS n, COALESCE\(SUM/.test(sql)) {
        // getStatus bekleyen özeti
        return {
          rows: [{
            n: state.pending.length,
            bytes: state.pendingBytes ?? sumPendingBytes(),
            overdue: state.pending.filter((p) => new Date(p.expires_at).getTime() < params[1].getTime()).length,
            oldest: state.pending.length ? state.files.get(state.pending[0].file_id).created_at : null,
          }],
        };
      }
      if (/FROM drive_pending_uploads p JOIN drive_files f ON f.id = p.file_id WHERE p.site_code = \$1$/.test(sql) && /SUM/.test(sql)) {
        return { rows: [{ bytes: state.pendingBytes ?? sumPendingBytes() }] };
      }
      if (/^SELECT COUNT\(\*\)::int AS n FROM drive_files WHERE site_code = \$1 AND status = 'stored'/.test(sql)) {
        return { rows: [{ n: [...state.files.values()].filter((f) => f.status === 'stored').length }] };
      }
      if (/^INSERT INTO drive_pending_uploads/.test(sql)) { state.pending.push({ file_id: params[0], site_code: params[1], storage_path: params[2], expires_at: params[3], attempts: 0, last_error: null }); return { rows: [] }; }
      if (/^SELECT p\.\*, f\.name/.test(sql)) {
        return {
          rows: state.pending.map((p) => {
            const file = state.files.get(p.file_id);
            return { ...p, name: file.name, folder_name: file.folder_name, mime_type: 'application/pdf', sha256: file.sha256, file_status: file.status };
          }),
        };
      }
      if (/^UPDATE drive_pending_uploads SET attempts/.test(sql)) {
        const item = state.pending.find((p) => p.file_id === params[0]);
        item.attempts += 1;
        item.last_error = params[2];
        return { rows: [] };
      }
      if (/^DELETE FROM drive_pending_uploads/.test(sql)) { state.pending = state.pending.filter((p) => p.file_id !== params[0]); return { rows: [] }; }
      if (/^SELECT COUNT\(\*\)::int AS n, COUNT\(\*\) FILTER \(WHERE expires_at/.test(sql)) {
        return { rows: [{ n: state.pending.length, overdue: state.pending.filter((p) => new Date(p.expires_at).getTime() < params[1].getTime()).length }] };
      }
      if (/^SELECT \* FROM drive_files WHERE site_code = \$1 AND source_type = \$3/.test(sql)) {
        const rows = [...state.files.values()].filter((f) => f.source_type === params[2] && f.source_id === params[3]).sort((a, b) => b.id - a.id);
        return { rows };
      }
      if (/^SELECT \* FROM drive_files WHERE site_code = \$1 ORDER BY id DESC/.test(sql)) return { rows: [...state.files.values()].sort((a, b) => b.id - a.id) };
      if (/^DELETE FROM drive_oauth_states WHERE expires_at/.test(sql)) return { rows: [] };
      if (/^INSERT INTO drive_oauth_states/.test(sql)) { state.states.set(params[0], { site_code: params[1], user_code: params[2], expires_at: params[3] }); return { rows: [] }; }
      if (/^DELETE FROM drive_oauth_states WHERE state_hash/.test(sql)) {
        const row = state.states.get(params[0]);
        state.states.delete(params[0]);
        return { rows: row ? [row] : [] };
      }
      if (/^INSERT INTO site_drive_connections/.test(sql)) {
        state.conn = { site_code: params[0], status: 'connected', account_email: params[1], refresh_token_enc: params[2], root_folder_id: params[3], folder_ids: JSON.parse(params[4]) };
        return { rows: [] };
      }
      if (/^INSERT INTO audit_log/.test(sql)) { state.audits.push({ action: params[3], site: params[4], details: JSON.parse(params[7]) }); return { rows: [] }; }
      return { rows: [] }; // last_ok güncellemeleri vb.
    },
  };
}

function makeClient() {
  return {
    authUrl: (s) => `https://accounts.example/auth?state=${s}`,
    async exchangeCode() { return { refreshToken: 'REFRESH-1', accessToken: 'AT', expiresIn: 3000, scope: 'https://www.googleapis.com/auth/drive.file' }; },
    async refreshAccess() { return { accessToken: 'AT2', expiresIn: 3000 }; },
    async accountEmail() { return 'site@example.com'; },
    async revoke() {},
    async ensureFolder(_t, name, parent) { clientCalls.push(['folder', name, parent]); return `F-${name}`; },
    async uploadFile(_t, args) {
      clientCalls.push(['upload', args.name, args.parentId]);
      if (clientMode === 'down') throw new DriveError('transient', 'ağ');
      if (clientMode === 'noid') return { size: args.data.length }; // 200 döndü ama dosya kimliği yok: teyitsiz
      if (clientMode === 'badsize') return { id: `D-${args.name}`, size: args.data.length + 1 }; // Drive farklı boyut bildirdi: teyitsiz
      return { id: `D-${args.name}`, size: args.data.length };
    },
  };
}

function connected() {
  return { site_code: SITE, status: 'connected', account_email: 'site@example.com', refresh_token_enc: 'v1:a:b:c', root_folder_id: null, folder_ids: {} };
}

const uploads = () => clientCalls.filter((c) => c[0] === 'upload');
const queueFullAudits = () => state.audits.filter((a) => a.action === 'drive.queue_full');

let svc;
beforeEach(() => {
  dir = mkdtempSync(path.join(os.tmpdir(), 'drive-test-'));
  state = { log: [], conn: connected(), names: new Set(), files: new Map(), nextId: 1, pending: [], pendingBytes: null, states: new Map(), audits: [], clock: new Date(2026, 9, 20, 12, 0, 0) };
  clientCalls = [];
  clientMode = 'up';
  svc = createDriveService({ db: makeDb(), client: makeClient(), config: CONFIG, pendingDir: dir, now: () => new Date(state.clock) });
  // Belirteç çözümü sahte: gerçek şifreli değer yerine geçerli biçim kullan.
  state.conn.refresh_token_enc = null;
});
afterEach(() => rmSync(dir, { recursive: true, force: true }));

async function withToken() {
  // completeConnect ile gerçek şifreli belirteç yaz, sonra bağlantı hazır olur.
  const started = await svc.startConnect(SITE, { userCode: 7 });
  const stateValue = new URL(started.url).searchParams.get('state');
  await svc.completeConnect({ code: 'c', state: stateValue });
}

/** Drive kopukken bir dosya yükler ve bekleme kuyruğuna girmesini sağlar; { file, tempPath } döner. */
async function uploadWhileDown(query = { kind: 'dekont', mime: 'application/pdf', date: '2026-10-20' }, data = PDF) {
  clientMode = 'down';
  const out = await svc.upload({ siteCode: SITE, actor: {}, query, data });
  assert.equal(out.file.status, 'pending');
  const item = state.pending.find((p) => p.file_id === out.file.id);
  assert.ok(item && existsSync(item.storage_path), 'bekleyen dosya diskte');
  return { file: out.file, tempPath: item.storage_path };
}

describe('drive_service baglanti', () => {
  it('yapilandirma yoksa Yakinda (503 DRIVE_NOT_CONFIGURED)', async () => {
    const off = createDriveService({ db: makeDb(), client: makeClient(), config: { configured: false } });
    await assert.rejects(off.startConnect(SITE, {}), (e) => e.code === 'DRIVE_NOT_CONFIGURED' && e.statusCode === 503 && /Yakında/.test(e.message));
  });

  it('state tek kullanimlik; belirtec sifreli yazilir', async () => {
    const started = await svc.startConnect(SITE, { userCode: 7 });
    const s = new URL(started.url).searchParams.get('state');
    await svc.completeConnect({ code: 'c', state: s });
    assert.equal(state.conn.status, 'connected');
    assert.ok(!state.conn.refresh_token_enc.includes('REFRESH-1'));
    assert.equal(decryptToken(state.conn.refresh_token_enc, KEY), 'REFRESH-1');
    await assert.rejects(svc.completeConnect({ code: 'c', state: s }), (e) => e.code === 'INVALID_OAUTH');
    await assert.rejects(svc.completeConnect({ code: 'c', state: 'yok' }), (e) => e.code === 'INVALID_OAUTH');
  });
});

describe('drive_service yukleme', () => {
  it('bagli degilse 409 DRIVE_NOT_CONNECTED', async () => {
    state.conn = null;
    await assert.rejects(svc.upload({ siteCode: SITE, actor: {}, query: { kind: 'gider', mime: 'application/pdf' }, data: PDF }), (e) => e.code === 'DRIVE_NOT_CONNECTED' && e.statusCode === 409);
  });

  it('dogrulama: tur, tarih, mime, icerik, bos, buyuk', async () => {
    await withToken();
    const base = { kind: 'gider', mime: 'application/pdf' };
    const run = (query, data = PDF) => svc.upload({ siteCode: SITE, actor: {}, query: { ...base, ...query }, data });
    await assert.rejects(run({ kind: 'x' }), (e) => e.code === 'INVALID_KIND');
    await assert.rejects(run({ date: '2026-13-01' }), (e) => e.code === 'INVALID_DATE');
    await assert.rejects(run({ mime: 'application/zip' }), (e) => e.code === 'UNSUPPORTED_TYPE');
    await assert.rejects(run({}, Buffer.from('MZ...')), (e) => e.code === 'CONTENT_MISMATCH');
    await assert.rejects(run({}, Buffer.alloc(0)), (e) => e.code === 'EMPTY_FILE');
    await assert.rejects(run({}, Buffer.concat([PDF, Buffer.alloc(11 * 1024 * 1024)])), (e) => e.code === 'FILE_TOO_LARGE');
  });

  it('Drive a gider: klasor GiderEkim_26, ad AB_D13_201026.pdf, ikinci dosya _2', async () => {
    await withToken();
    const q = { kind: 'gider', mime: 'application/pdf', date: '2026-10-20', block: 'A', apartment: '13' };
    const first = await svc.upload({ siteCode: SITE, actor: {}, query: q, data: PDF });
    assert.equal(first.file.status, 'stored');
    assert.equal(first.file.folder, 'GiderEkim_26');
    assert.equal(first.file.name, 'AB_D13_201026.pdf');
    assert.equal(first.file.source_type, null, 'kaynak verilmediyse bag yok (eski davranis)');
    const second = await svc.upload({ siteCode: SITE, actor: {}, query: q, data: PDF });
    assert.equal(second.file.name, 'AB_D13_201026_2.pdf');
    const folders = clientCalls.filter((c) => c[0] === 'folder').map((c) => c[1]);
    assert.deepEqual(folders, ['SmartKeyPass — Güneş Sitesi', 'GiderEkim_26'], 'klasorler bir kez olusturulur');
  });

  it('Drive kopukken bekleme kuyruguna girer, sonra gonderilir', async () => {
    await withToken();
    clientMode = 'down';
    const out = await svc.upload({ siteCode: SITE, actor: {}, query: { kind: 'dekont', mime: 'application/pdf', date: '2026-10-20' }, data: PDF });
    assert.equal(out.file.status, 'pending');
    assert.equal(state.pending.length, 1);
    assert.ok(existsSync(state.pending[0].storage_path));
    clientMode = 'up';
    const flushed = await svc.flushPending(SITE);
    assert.equal(flushed.sent, 1);
    assert.equal(state.pending.length, 0);
    assert.equal(state.files.get(out.file.id).status, 'stored');
  });

  it('bekleme alani doluysa 503 DRIVE_QUEUE_FULL ve kayit silinir', async () => {
    await withToken();
    clientMode = 'down';
    state.pendingBytes = 100 * 1024 * 1024;
    await assert.rejects(
      svc.upload({ siteCode: SITE, actor: {}, query: { kind: 'belge', mime: 'application/pdf' }, data: PDF }),
      (e) => e.code === 'DRIVE_QUEUE_FULL' && e.statusCode === 503,
    );
    assert.equal(state.files.size, 0);
  });
});

describe('drive_service K6: silmeyi biz yapmayiz', () => {
  it('kuyruk dolu: YENI yukleme reddedilir + yonetici uyarisi; bekleyen dosya ve gecici dosyasi yerinde kalir', async () => {
    await withToken();
    const existing = await uploadWhileDown({ kind: 'dekont', mime: 'application/pdf', date: '2026-10-20' });
    // Alan dolu: 10 baytlik boşluk, yeni dosya 15 bayt.
    state.pendingBytes = PENDING_MAX_BYTES - 10;
    const filesBefore = state.files.size;
    await assert.rejects(
      svc.upload({ siteCode: SITE, actor: { userCode: 7 }, query: { kind: 'belge', mime: 'application/pdf', date: '2026-10-21' }, data: PDF }),
      (e) => e.code === 'DRIVE_QUEUE_FULL' && e.statusCode === 503 && /silinmedi/.test(e.message),
    );
    // Mevcut dosyalara dokunulmadı.
    assert.equal(state.files.size, filesBefore, 'yalniz reddedilen yeni satir geri alinir, baska satir silinmez');
    assert.equal(state.files.get(existing.file.id).status, 'pending');
    assert.equal(state.pending.length, 1);
    assert.ok(existsSync(existing.tempPath), 'bekleyen gecici dosya silinmedi');
    // Yönetici uyarısı denetim kaydına düştü (saatte bir kez).
    assert.equal(queueFullAudits().length, 1);
    assert.equal(queueFullAudits()[0].site, SITE);
    assert.equal(queueFullAudits()[0].details.limit_bytes, PENDING_MAX_BYTES);
    await assert.rejects(
      svc.upload({ siteCode: SITE, actor: {}, query: { kind: 'belge', mime: 'application/pdf', date: '2026-10-22' }, data: PDF }),
      (e) => e.code === 'DRIVE_QUEUE_FULL',
    );
    assert.equal(queueFullAudits().length, 1, 'ayni saat icinde ikinci uyari kaydi yazilmaz');
    state.clock = new Date(state.clock.getTime() + 2 * 60 * 60 * 1000);
    await assert.rejects(svc.upload({ siteCode: SITE, actor: {}, query: { kind: 'belge', mime: 'application/pdf', date: '2026-10-23' }, data: PDF }), (e) => e.code === 'DRIVE_QUEUE_FULL');
    assert.equal(queueFullAudits().length, 2, 'saat gecince uyari yeniden yazilir');
  });

  it('kuyruk dolu olsa da Drive ayaktaysa yukleme dogrudan Drive a gider (kuyruk yalniz kopukken gerekir)', async () => {
    await withToken();
    state.pendingBytes = PENDING_MAX_BYTES;
    const out = await svc.upload({ siteCode: SITE, actor: {}, query: { kind: 'belge', mime: 'application/pdf' }, data: PDF });
    assert.equal(out.file.status, 'stored');
    assert.equal(queueFullAudits().length, 0);
  });

  it('durum yanitinda yonetici uyarilari: bekliyor, dolmak uzere, doldu', async () => {
    await withToken();
    let status = await svc.getStatus(SITE);
    assert.deepEqual(status.warnings, [], 'bekleyen yoksa uyari yok');
    assert.equal(status.pending_limit_bytes, PENDING_MAX_BYTES);
    await uploadWhileDown();
    status = await svc.getStatus(SITE);
    assert.equal(status.pending_count, 1);
    assert.deepEqual(status.warnings.map((w) => w.code), ['DRIVE_FILES_WAITING']);
    assert.match(status.warnings[0].message, /silinmez/i);
    state.pendingBytes = Math.floor(PENDING_MAX_BYTES * 0.85);
    status = await svc.getStatus(SITE);
    assert.deepEqual(status.warnings.map((w) => w.code), ['DRIVE_QUEUE_NEARLY_FULL', 'DRIVE_FILES_WAITING']);
    state.pendingBytes = PENDING_MAX_BYTES;
    status = await svc.getStatus(SITE);
    assert.equal(status.warnings[0].code, 'DRIVE_QUEUE_FULL');
    assert.match(status.warnings[0].message, /silinmez/i);
  });

  it('sure doldu diye HICBIR bekleyen dosya silinmez; uzun suredir bekleyen yalniz uyari verir, Drive gelince gider', async () => {
    await withToken();
    const waiting = await uploadWhileDown();
    state.clock = new Date(state.clock.getTime() + (PENDING_WARN_DAYS + 23) * DAY_MS); // 30 gün sonra
    const report = await svc.flushPending(SITE, { force: true });
    assert.equal(report.sent, 0);
    assert.equal(report.waiting, 1);
    assert.equal(report.overdue, 1);
    assert.equal(report.expired, 0, 'artik hicbir dosya sure doldu diye silinmez');
    assert.equal(state.files.get(waiting.file.id)?.status, 'pending', 'kayit duruyor');
    assert.ok(existsSync(waiting.tempPath), 'gecici dosya duruyor');
    assert.equal(state.audits.filter((a) => a.action === 'drive.pending_overdue').length, 1, 'yoneticiye uzun sure bekleme uyarisi');
    const status = await svc.getStatus(SITE);
    assert.equal(status.pending_overdue_count, 1);
    assert.deepEqual(status.warnings.map((w) => w.code), ['DRIVE_FILES_OVERDUE']);
    assert.ok(!state.log.some((sql) => /^DELETE FROM drive_files/.test(sql) && !/NOT EXISTS/.test(sql)), 'bekleyen kayitlara DELETE gonderilmedi');

    clientMode = 'up';
    const after = await svc.flushPending(SITE, { force: true });
    assert.equal(after.sent, 1);
    assert.equal(after.waiting, 0);
    assert.equal(state.files.get(waiting.file.id).status, 'stored');
    assert.ok(!existsSync(waiting.tempPath), 'gecici dosya Drive teyidinden SONRA silindi');
  });

  it('teyitsiz gecici dosya durur: Drive kimlik dondurmediyse ya da boyut tutmuyorsa dosya silinmez, sonra gonderilir', async () => {
    await withToken();
    const waiting = await uploadWhileDown();
    for (const mode of ['noid', 'badsize']) {
      clientMode = mode;
      const report = await svc.flushPending(SITE, { force: true });
      assert.equal(report.sent, 0, mode);
      assert.equal(report.waiting, 1, mode);
      assert.equal(state.files.get(waiting.file.id).status, 'pending', `${mode}: 'stored' yazilmadi`);
      assert.ok(existsSync(waiting.tempPath), `${mode}: gecici dosya duruyor`);
      assert.match(state.pending[0].last_error, /doğrulamadı/, mode);
    }
    clientMode = 'up';
    const report = await svc.flushPending(SITE, { force: true });
    assert.equal(report.sent, 1);
    assert.ok(!existsSync(waiting.tempPath), 'teyit sonrasi silindi');
    assert.equal(state.files.get(waiting.file.id).status, 'stored');
  });

  it('dogrudan yuklemede teyitsiz Drive yaniti basari sayilmaz: dosya reddedilmez, sunucuda bekler', async () => {
    await withToken();
    clientMode = 'noid';
    const out = await svc.upload({ siteCode: SITE, actor: {}, query: { kind: 'gider', mime: 'application/pdf', date: '2026-10-20' }, data: PDF });
    assert.equal(out.file.status, 'pending');
    assert.equal(state.pending.length, 1);
    assert.ok(existsSync(state.pending[0].storage_path));
  });

  it('bozulmus ya da kaybolmus gecici dosya Drive a gonderilmez ve silinmez (neden yazilir)', async () => {
    await withToken();
    const waiting = await uploadWhileDown();
    clientCalls.length = 0;
    clientMode = 'up';
    writeFileSync(waiting.tempPath, Buffer.from('%PDF-1.7 BOZUK'));
    let report = await svc.flushPending(SITE, { force: true });
    assert.equal(report.sent, 0);
    assert.equal(uploads().length, 0, 'bozuk icerik Drive a gonderilmedi');
    assert.match(state.pending[0].last_error, /bütünlüğü/);
    assert.equal(state.files.get(waiting.file.id).status, 'pending');
    rmSync(waiting.tempPath);
    report = await svc.flushPending(SITE, { force: true });
    assert.equal(report.sent, 0);
    assert.equal(report.waiting, 1, 'kayit duruyor (yonetici gorsun)');
    assert.match(state.pending[0].last_error, /bulunamadı/);
  });

  it("Drive teyidi 'stored' yazilmis ama bekleme satiri kalmis (yarida kesilmis tur): TEKRAR GONDERILMEZ, kalinti temizlenir", async () => {
    await withToken();
    const waiting = await uploadWhileDown();
    clientCalls.length = 0;
    clientMode = 'up';
    const row = state.files.get(waiting.file.id);
    row.status = 'stored';
    row.drive_file_id = 'D-onceki-tur';
    const report = await svc.flushPending(SITE, { force: true });
    assert.equal(report.sent, 0);
    assert.equal(uploads().length, 0, 'ikinci kez Drive a gonderilmedi');
    assert.equal(state.pending.length, 0);
    assert.ok(!existsSync(waiting.tempPath), 'teyit kayitli oldugundan gecici dosya temizlendi');
  });

  it('ayni anda iki gonderim ayni dosyayi iki kez yollamaz', async () => {
    await withToken();
    await uploadWhileDown();
    clientCalls.length = 0;
    clientMode = 'up';
    const [a, b] = await Promise.all([svc.flushPending(SITE, { force: true }), svc.flushPending(SITE, { force: true })]);
    assert.equal(a.sent + b.sent, 1);
    assert.equal(uploads().length, 1);
  });

  it('bagli degilken gonderim denenmez; bekleyen dosya dokunulmadan kalir (baglanti kesmek de silmez)', async () => {
    await withToken();
    const waiting = await uploadWhileDown();
    await svc.disconnect(SITE, {});
    clientCalls.length = 0;
    const report = await svc.flushPending(SITE, { force: true });
    assert.equal(report.sent, 0);
    assert.equal(uploads().length, 0);
    assert.equal(report.waiting, 1);
    assert.ok(existsSync(waiting.tempPath));
  });
});

describe('drive_service kaynak kayit baglantisi (P1-11)', () => {
  const q = { kind: 'gider', mime: 'application/pdf', date: '2026-10-20', block: 'A', apartment: '13' };

  it('ad onek kurali: IS-123_AB_D13_201026.pdf; Drive a giden ad ve kayit ayni; kayit kaynak tur+kimligi tasir', async () => {
    await withToken();
    const out = await svc.upload({ siteCode: SITE, actor: {}, query: q, data: PDF, source: { type: 'work_item', id: 123 } });
    assert.equal(out.file.name, 'IS-123_AB_D13_201026.pdf');
    assert.equal(out.file.source_type, 'work_item');
    assert.equal(out.file.source_id, 123);
    assert.equal(uploads().at(-1)[1], 'IS-123_AB_D13_201026.pdf', 'Drive daki ad onekli');
    const row = state.files.get(out.file.id);
    assert.equal(row.source_type, 'work_item');
    assert.equal(row.source_id, 123);
    assert.equal(row.folder_name, 'GiderEkim_26', 'klasor kaynaga gore degil dosya turune gore');
    // Aynı kayıt, aynı gün: çakışma eki sondadır.
    const second = await svc.upload({ siteCode: SITE, actor: {}, query: q, data: PDF, source: { type: 'work_item', id: 123 } });
    assert.equal(second.file.name, 'IS-123_AB_D13_201026_2.pdf');
    // Başka kayıt: ayrı ad, çakışma yok.
    const other = await svc.upload({ siteCode: SITE, actor: {}, query: q, data: PDF, source: { type: 'meter_reading', id: '77' } });
    assert.equal(other.file.name, 'OKM-77_AB_D13_201026.pdf');
    assert.equal(other.file.source_id, 77);
    // Daire/blok yoksa tür başlığı: Gider_201026 önekle.
    const bare = await svc.upload({ siteCode: SITE, actor: {}, query: { kind: 'gider', mime: 'application/pdf', date: '2026-10-20' }, data: PDF, source: { type: 'expense', id: 18 } });
    assert.equal(bare.file.name, 'GDR-18_Gider_201026.pdf');
  });

  it('kaynak yoksa ad ve kayit eskisi gibi (geriye donuk uyum)', async () => {
    await withToken();
    const out = await svc.upload({ siteCode: SITE, actor: {}, query: q, data: PDF });
    assert.equal(out.file.name, 'AB_D13_201026.pdf');
    assert.equal(state.files.get(out.file.id).source_type, null);
    assert.equal(state.files.get(out.file.id).source_id, null);
  });

  it('kaynak bagi HTTP sorgusundan alinmaz (query.source_type/source_id yok sayilir): dogrulanamayan kayda bag kurulamaz', async () => {
    await withToken();
    const out = await svc.upload({ siteCode: SITE, actor: {}, query: { ...q, source_type: 'work_item', source_id: '999' }, data: PDF });
    assert.equal(out.file.name, 'AB_D13_201026.pdf');
    assert.equal(out.file.source_type, null);
    assert.equal(state.files.get(out.file.id).source_id, null);
  });

  it('gecersiz kaynak (bilinmeyen tur, sifir/negatif/metin no) 400 INVALID_SOURCE; hicbir satir ya da dosya olusmaz', async () => {
    await withToken();
    for (const source of [{ type: 'x', id: 1 }, { type: 'work_item', id: 0 }, { type: 'work_item', id: -4 }, { type: 'work_item', id: '12abc' }, { type: 'work_item', id: 1.5 }, { type: 'work_item' }, {}]) {
      await assert.rejects(svc.upload({ siteCode: SITE, actor: {}, query: q, data: PDF, source }), (e) => e.code === 'INVALID_SOURCE' && e.statusCode === 400, JSON.stringify(source));
    }
    assert.equal(state.files.size, 0);
    assert.equal(uploads().length, 0);
  });

  it('kuyruga giren dosyanin da kaynagi ve oneki korunur; Drive e gonderilince ayni ad gider', async () => {
    await withToken();
    clientMode = 'down';
    const out = await svc.upload({ siteCode: SITE, actor: {}, query: q, data: PDF, source: { type: 'work_item', id: 9 } });
    assert.equal(out.file.status, 'pending');
    assert.equal(out.file.name, 'IS-9_AB_D13_201026.pdf');
    clientMode = 'up';
    await svc.flushPending(SITE, { force: true });
    assert.equal(uploads().at(-1)[1], 'IS-9_AB_D13_201026.pdf');
    assert.equal(state.files.get(out.file.id).source_id, 9);
  });

  it('liste kaynak kayda gore suzulur; yarim ya da gecersiz suzgec 400', async () => {
    await withToken();
    await svc.upload({ siteCode: SITE, actor: {}, query: q, data: PDF, source: { type: 'work_item', id: 5 } });
    await svc.upload({ siteCode: SITE, actor: {}, query: q, data: PDF, source: { type: 'work_item', id: 6 } });
    await svc.upload({ siteCode: SITE, actor: {}, query: q, data: PDF });
    assert.equal((await svc.list(SITE, 50)).files.length, 3);
    const linked = await svc.list(SITE, 50, { source_type: 'work_item', source_id: '5' });
    assert.deepEqual(linked.files.map((f) => f.name), ['IS-5_AB_D13_201026.pdf']);
    await assert.rejects(svc.list(SITE, 50, { source_type: 'work_item' }), (e) => e.code === 'INVALID_SOURCE');
    await assert.rejects(svc.list(SITE, 50, { source_type: 'zzz', source_id: '1' }), (e) => e.code === 'INVALID_SOURCE');
  });
});
