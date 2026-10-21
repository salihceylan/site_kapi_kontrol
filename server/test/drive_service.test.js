// Site Drive deposu (D1) servisi (DB'siz, sahte veritabanı + sahte Drive istemcisi): bağlantı kapısı, klasör/dosya adı, çakışma eki, Drive'a gönderim,
// kopukken bekleme kuyruğu ve 100 MB sınırı, bekleyenlerin sonradan gönderimi, OAuth state tek kullanımlığı, belirtecin şifreli yazılması.
// Gerçek HTTP/Google ve gerçek PostgreSQL bu testte YOK (kullanıcı denemesi / QA).
import { describe, it, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, rmSync, existsSync } from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { createDriveService } from '../src/modules/drive_service.js';
import { DriveError } from '../src/modules/drive_client.js';
import { decryptToken } from '../src/modules/drive_common.js';

const SITE = 1000000001;
const KEY = 'k'.repeat(40);
const CONFIG = { configured: true, clientId: 'id', clientSecret: 's', redirectUri: 'https://x/cb', tokenKey: KEY };
const norm = (t) => String(t).replace(/\s+/g, ' ').trim();
const PDF = Buffer.from('%PDF-1.7 deneme');

let state;
let dir;
let clientCalls;
let clientMode;

function makeDb() {
  return {
    async query(text, params = []) {
      const sql = norm(text);
      state.log.push(sql);
      if (/^SELECT \* FROM site_drive_connections/.test(sql)) return { rows: state.conn ? [{ ...state.conn }] : [] };
      if (/^SELECT name FROM sites/.test(sql)) return { rows: [{ name: 'Güneş Sitesi' }] };
      if (/^UPDATE site_drive_connections SET root_folder_id = \$2/.test(sql)) { state.conn.root_folder_id = params[1]; return { rows: [] }; }
      if (/^UPDATE site_drive_connections SET folder_ids = folder_ids/.test(sql)) { Object.assign(state.conn.folder_ids, JSON.parse(params[1])); return { rows: [] }; }
      if (/^INSERT INTO drive_files/.test(sql)) {
        const key = `${params[2]}/${params[3]}`;
        if (state.names.has(key)) return { rows: [] };
        state.names.add(key);
        const row = { id: state.nextId++, site_code: params[0], kind: params[1], folder_name: params[2], name: params[3], mime_type: params[4], size_bytes: params[5], sha256: params[6], status: 'pending', created_at: new Date() };
        state.files.set(row.id, row);
        return { rows: [row] };
      }
      if (/^UPDATE drive_files SET status = 'stored'/.test(sql)) {
        const row = state.files.get(params[0]);
        row.status = 'stored';
        row.drive_file_id = params[1];
        return { rows: [row] };
      }
      if (/^DELETE FROM drive_files/.test(sql)) { state.files.delete(params[0]); return { rows: [] }; }
      if (/FROM drive_pending_uploads p JOIN drive_files f ON f.id = p.file_id WHERE p.site_code = \$1$/.test(sql) && /SUM/.test(sql)) {
        return { rows: [{ bytes: state.pendingBytes }] };
      }
      if (/^INSERT INTO drive_pending_uploads/.test(sql)) { state.pending.push({ file_id: params[0], site_code: params[1], storage_path: params[2], expires_at: params[3], attempts: 0 }); return { rows: [] }; }
      if (/^SELECT p\.\*, f\.name/.test(sql)) {
        return { rows: state.pending.map((p) => ({ ...p, name: state.files.get(p.file_id).name, folder_name: state.files.get(p.file_id).folder_name, mime_type: 'application/pdf' })) };
      }
      if (/^DELETE FROM drive_pending_uploads/.test(sql)) { state.pending = state.pending.filter((p) => p.file_id !== params[0]); return { rows: [] }; }
      if (/^SELECT COUNT\(\*\)::int AS n FROM drive_pending_uploads/.test(sql)) return { rows: [{ n: state.pending.length }] };
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
      return { rows: [] }; // last_ok güncellemeleri, denetim kaydı vb.
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
      return { id: `D-${args.name}`, size: args.data.length };
    },
  };
}

function connected() {
  return { site_code: SITE, status: 'connected', account_email: 'site@example.com', refresh_token_enc: 'v1:a:b:c', root_folder_id: null, folder_ids: {} };
}

let svc;
beforeEach(() => {
  dir = mkdtempSync(path.join(os.tmpdir(), 'drive-test-'));
  state = { log: [], conn: connected(), names: new Set(), files: new Map(), nextId: 1, pending: [], pendingBytes: 0, states: new Map() };
  clientCalls = [];
  clientMode = 'up';
  svc = createDriveService({ db: makeDb(), client: makeClient(), config: CONFIG, pendingDir: dir, now: () => new Date(2026, 9, 20, 12, 0, 0) });
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
