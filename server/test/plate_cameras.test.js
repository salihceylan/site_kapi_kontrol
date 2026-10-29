// Plaka Tanıma sözleşme sürüm 3 (122): şema <-> migration eşliği, kamera girdisi / RTSP adresi, komut kuyruğu (talep, sonuç, süre dolumu), görüntü karosu
// (yükleme + yönetici ucu yetkisi 403 + 304), kimlik bağlama + kapı komutu + kapı günlüğü, canlı akış kimliği, otomatik açma durumu, şifreli parola gidiş-dönüş.
// DB'siz (sahte havuz). Gerçek SQL için plate_gates_pg.test.js (PLATE_GATES_PG_URL).
import { describe, it, before, after, beforeEach, mock } from 'node:test';
import assert from 'node:assert/strict';
import express from 'express';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { DEFAULT_MIGRATIONS_DIR, findUnsafeStatements } from '../scripts/migrate.js';
import { pool } from '../src/db.js';
import { PLATE_CAMERAS_DDL, PLATE_CAMERAS_DDL_ORDER, ensurePlateCamerasSchema, plateCamerasTuning } from '../src/modules/plate_cameras_schema.js';
import {
  COMMAND_KINDS,
  COMMAND_STATUSES,
  DEFAULT_SITE_SETTINGS,
  GATE_COMMANDS,
  IDENTITY_KINDS,
  MAX_SNAPSHOT_BYTES,
  PROBE_STATUSES,
  SETTING_RANGES,
  SUPPORTED_SCHEMA_VERSIONS,
  mergeSettings,
  parseCommandResult,
  parseEdgeEvent,
  parseHeartbeat,
  parseSnapshotUpload,
  parseSyncQuery,
} from '../src/modules/plate_gates_common.js';
import {
  AUTO_OPEN_MESSAGES,
  BRANDS,
  BRAND_CODES,
  apartmentText,
  buildRtspUrl,
  computeAutoOpen,
  doorLogEntry,
  gateStateOf,
  liveIdentity,
  parseCameraBody,
  parseRtspUrl,
  resolveNewRtspUrl,
  retargetRtspUrl,
  shortPersonName,
} from '../src/modules/plate_cameras_common.js';
import { shortName } from '../src/modules/apartment_mgmt_rules.js';
import { CAMERA_BRANDS, decryptSecret, encryptSecret } from '../src/modules/device_integrations_service.js';
import { claimCommands, completeCommand, expireStaleCommands, mapCommand, pickTargetEdge } from '../src/modules/plate_edge_commands.js';
import {
  createCamera,
  getCamerasOverview,
  getLatestDiscovery,
  loadEdgeCameras,
  probeCamera,
  readSnapshot,
  runCamerasHousekeeping,
  startDiscovery,
  storeSnapshot,
  updateCamera,
} from '../src/modules/plate_cameras_service.js';
import { recordEdgeEvent, syncEdge } from '../src/modules/plate_edge_service.js';
import { listDecisions } from '../src/modules/plate_recognition_service.js';
import { plateRecognitionRouter } from '../src/modules/plate_recognition_routes.js';
import { plateEdgeRouter } from '../src/modules/plate_edge_routes.js';
import { SITE_AUDIT_LABELS } from '../src/modules/site_audit_log_catalog.js';

plateCamerasTuning.retryDelayMs = 1;
process.env.CAMERA_SECRET_KEY = 'plate-cameras-test-secret-0123456789abcdef';

const here = path.dirname(fileURLToPath(import.meta.url));
const MIGRATION = readFileSync(path.join(DEFAULT_MIGRATIONS_DIR, '122_plate_cameras_edge.sql'), 'utf8').replace(/\r\n/g, '\n');
const DB_SOURCE = readFileSync(path.join(here, '..', 'src', 'db.js'), 'utf8');
const normalize = (text) => text.replace(/--.*$/gm, ' ').replace(/\s+/g, ' ').trim();
const listOf = (items) => items.map((v) => `'${v}'`).join(', ');
const ok = (rows = []) => ({ rows, rowCount: rows.length });
const JPEG = Buffer.from([0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10, 0x4a, 0x46, 0x49, 0x46, 0xff, 0xd9]);

// --- Sahte havuz -------------------------------------------------------------------------------------------------------------------------

/** handlers: [[RegExp, (sql, params, state) => result]]; ilk eşleşen kazanır; BEGIN/COMMIT/kilit/denetim/SAVEPOINT varsayılan boş yanıt. */
function installFakePool(handlers, state = {}) {
  const log = [];
  const run = async (text, params = []) => {
    const sql = String(text).replace(/\s+/g, ' ').trim();
    log.push({ sql, params });
    for (const [re, fn] of handlers) if (re.test(sql)) return fn(sql, params, state);
    return ok();
  };
  pool.query = run;
  pool.connect = async () => ({ query: run, release() {} });
  return { log, state, find: (re) => log.filter((c) => re.test(c.sql)) };
}
const uninstallFakePool = () => {
  delete pool.query;
  delete pool.connect;
};

const siteSettingsRow = (over = {}) => [/FROM plate_site_settings WHERE site_code/, () => ok(over === null ? [] : [{ ...DEFAULT_SITE_SETTINGS, ...over }])];
const edgeRow = (over = {}) => ({ id: 5, name: 'Kulübe PC', last_seen_at: new Date(), recognition_ready: true, recognition_note: null, app_version: '0.3.0', schema_version: 3, ...over });
const edgeClients = (rows) => [/FROM plate_edge_clients WHERE site_code = \$1 AND is_active AND revoked_at IS NULL/, () => ok(rows)];
const CLIENT = Object.freeze({ id: 5, siteCode: 1000000001, name: 'Kulübe PC', siteName: 'Site' });
const SITE = 1000000001;
const MANAGER = Object.freeze({ id: 20001, user_code: 20001, role: 'site_manager', full_name: 'Yönetici' });

// --- Şema ---------------------------------------------------------------------------------------------------------------------------------

describe('plate_cameras_schema (122)', () => {
  it('migration, DDL ile ayni ifadeler ve ayni sirada; ekleyici (DROP/DELETE/UPDATE/TRUNCATE yok)', () => {
    const actual = normalize(MIGRATION);
    let cursor = 0;
    for (const name of PLATE_CAMERAS_DDL_ORDER) {
      const statement = normalize(PLATE_CAMERAS_DDL[name]);
      const at = actual.indexOf(statement, cursor);
      assert.ok(at >= cursor, `sirasiz ya da eksik: ${name}`);
      cursor = at + statement.length;
    }
    assert.ok(!/\b(DROP|TRUNCATE)\b|; ?(DELETE|UPDATE) /i.test(actual));
    assert.deepEqual(findUnsafeStatements(MIGRATION), []);
  });

  it('CHECK listeleri ve site ayari varsayilanlari / araliklari sabitlerle ayni', () => {
    const sql = normalize(MIGRATION);
    assert.ok(sql.includes(`kind IN (${listOf(COMMAND_KINDS)})`));
    assert.ok(sql.includes(`status IN (${listOf(COMMAND_STATUSES)})`));
    assert.ok(sql.includes(`probe_status IN (${listOf(PROBE_STATUSES)})`));
    assert.ok(sql.includes(`gate_command IN (${listOf(GATE_COMMANDS)})`));
    assert.ok(sql.includes(`identity_kind IN (${listOf(IDENTITY_KINDS)})`));
    for (const field of ['command_ttl_seconds', 'snapshot_interval_seconds', 'snapshot_idle_interval_seconds', 'snapshot_keep_minutes']) {
      assert.ok(sql.includes(`${field} INTEGER NOT NULL DEFAULT ${DEFAULT_SITE_SETTINGS[field]}`), field);
      const [min, max] = SETTING_RANGES[field];
      assert.ok(sql.includes(`${field} BETWEEN ${min} AND ${max}`), `${field} araligi`);
    }
  });

  it('marka listesi 065 CHECK + CAMERA_BRANDS ile ayni; sozlesme surum 3; kopyalar: shortName / audit etiketleri', () => {
    assert.deepEqual([...BRAND_CODES], [...CAMERA_BRANDS]);
    const base = normalize(readFileSync(path.join(DEFAULT_MIGRATIONS_DIR, '065_device_integrations.sql'), 'utf8'));
    assert.ok(base.includes(`brand IN (${listOf(BRAND_CODES)})`));
    assert.deepEqual([...SUPPORTED_SCHEMA_VERSIONS], [1, 2, 3]);
    for (const name of ['Ali Yılmaz', 'Ayşe', 'Mehmet Ali Öztürk', '  ', 'ışık İşçi']) assert.equal(shortPersonName(name) ?? '', shortName(name), name);
    for (const action of ['plate.camera_created', 'plate.camera_updated', 'plate.camera_probe_requested', 'plate.discovery_requested']) assert.ok(SITE_AUDIT_LABELS[action], action);
  });

  it('db.js ensurePlateCamerasSchema cagirir (ensurePlateAlertsSchema sonrasi)', () => {
    assert.ok(DB_SOURCE.includes("import { ensurePlateCamerasSchema } from './modules/plate_cameras_schema.js'"));
    assert.ok(DB_SOURCE.indexOf('await ensurePlateCamerasSchema(client)') > DB_SOURCE.indexOf('await ensurePlateAlertsSchema(client)'));
  });

  it('her sey varsa tek katalog sorgusu; eksikse tum ifadeler; ust tablo yoksa hicbir sey', async () => {
    const make = (row) => {
      const calls = [];
      return { calls, async query(sql) { calls.push(String(sql).trim().slice(0, 30)); return /unnest/.test(sql) ? { rows: [row] } : { rows: [] }; } };
    };
    const parents = ['sites', 'camera_devices', 'plate_events', 'plate_edge_clients', 'plate_site_settings'];
    const tables = [...parents, 'plate_edge_commands', 'plate_camera_snapshots', 'plate_snapshot_watch'];
    const indexes = ['idx_plate_edge_commands_open', 'idx_plate_edge_commands_site', 'idx_plate_camera_snapshots_site'];
    const columns = [
      'camera_devices.rtsp_url', 'camera_devices.probe_status', 'camera_devices.probe_message', 'camera_devices.probe_width', 'camera_devices.probe_height', 'camera_devices.probe_at',
      'plate_events.apartment_id', 'plate_events.person_id', 'plate_events.identity_kind', 'plate_events.gate_command',
      'plate_edge_clients.recognition_ready', 'plate_edge_clients.recognition_note',
      'plate_site_settings.command_ttl_seconds', 'plate_site_settings.snapshot_interval_seconds', 'plate_site_settings.snapshot_idle_interval_seconds', 'plate_site_settings.snapshot_keep_minutes',
    ];
    const full = make({ tables, indexes, columns });
    await ensurePlateCamerasSchema(full);
    assert.equal(full.calls.length, 1);
    const missing = make({ tables, indexes, columns: columns.slice(1) });
    await ensurePlateCamerasSchema(missing);
    assert.equal(missing.calls.length, 1 + 1 + PLATE_CAMERAS_DDL_ORDER.length + 1);
    assert.match(missing.calls.at(-1), /RESET lock_timeout/);
    const noParent = make({ tables: ['sites'], indexes: [], columns: [] });
    await ensurePlateCamerasSchema(noParent);
    assert.equal(noParent.calls.length, 1);
  });
});

// --- Saf yardımcılar -----------------------------------------------------------------------------------------------------------------------

describe('plate_cameras_common: kamera girdisi ve RTSP adresi', () => {
  it('RTSP adresindeki kimlik bilgisi ayrilir ve adres KIMLIKSIZ saklanir', () => {
    const parsed = parseRtspUrl('rtsp://admin:p%40ss@192.168.1.64:554/Streaming/Channels/101');
    assert.deepEqual([parsed.host, parsed.port, parsed.username, parsed.password], ['192.168.1.64', 554, 'admin', 'p@ss']);
    assert.equal(parsed.url, 'rtsp://192.168.1.64:554/Streaming/Channels/101');
    assert.throws(() => parseRtspUrl('http://192.168.1.64/x'), (e) => e.statusCode === 400);
    assert.throws(() => parseRtspUrl('rtsp://a b/x'), (e) => e.statusCode === 400);
    assert.throws(() => parseRtspUrl(`rtsp://10.0.0.1/${'x'.repeat(600)}`), (e) => e.statusCode === 400);
  });

  it('yeni kamera: adres > yol > marka sablonu > (ONVIF) bos; host/port RTSP adresinden turetilebilir', () => {
    const base = { name: 'Giriş', brand: 'hikvision', host: '192.168.1.64' };
    const hik = parseCameraBody(base);
    assert.equal(resolveNewRtspUrl({ ...hik, port: null }), 'rtsp://192.168.1.64/Streaming/Channels/101');
    assert.equal(resolveNewRtspUrl({ brand: 'tiandy', host: '10.0.0.7', port: 8554, rtspUrl: null, rtspPath: null }), 'rtsp://10.0.0.7:8554/1/1');
    const withPath = parseCameraBody({ ...base, rtsp_path: 'cam/ch2?x=1' });
    assert.equal(resolveNewRtspUrl({ ...withPath, port: null }), 'rtsp://192.168.1.64/cam/ch2?x=1');
    const onvif = parseCameraBody({ name: 'X', brand: 'onvif', host: '10.0.0.9' });
    assert.equal(resolveNewRtspUrl({ ...onvif, port: null }), null, 'ONVIF: kenar cozer');
    const fromUrl = parseCameraBody({ name: 'X', brand: 'onvif', rtsp_url: 'rtsp://u:p@10.0.0.9:8554/live' });
    assert.deepEqual([fromUrl.host, fromUrl.port, fromUrl.username, fromUrl.password, fromUrl.rtspUrl], ['10.0.0.9', 8554, 'u', 'p', 'rtsp://10.0.0.9:8554/live']);
    assert.deepEqual(BRANDS.map((b) => b.code), ['hikvision', 'tiandy', 'onvif']);
    assert.equal(buildRtspUrl({ host: 'h', port: 554, path: 'x' }), 'rtsp://h:554/x');
    assert.equal(retargetRtspUrl('rtsp://10.0.0.1:554/live', '10.0.0.2', 8554), 'rtsp://10.0.0.2:8554/live');
    assert.equal(retargetRtspUrl(null, 'h', 1), null);
  });

  it('dogrulama: ad/marka/adres zorunlu, gecersiz marka-port-yon-kapi 400; kismi guncellemede parola semantigi', () => {
    for (const bad of [{ name: '' }, { brand: 'sony' }, { host: '' }, { host: 'a b' }, { port: 70000 }, { direction: 'yan' }, { gate_id: 'x' }]) {
      assert.throws(() => parseCameraBody({ name: 'K', brand: 'onvif', host: '10.0.0.1', ...bad }), (e) => e.statusCode === 400, JSON.stringify(bad));
    }
    assert.throws(() => parseCameraBody({ name: 'K', brand: 'onvif' }), (e) => e.statusCode === 400, 'adres yok');
    assert.throws(() => parseCameraBody({}, { partial: true }), (e) => e.code === 'INVALID_BODY');
    assert.equal(parseCameraBody({ is_active: false }, { partial: true }).isActive, false);
    assert.equal(parseCameraBody({ name: 'Yeni' }, { partial: true }).password, undefined, 'parola gonderilmezse korunur');
    assert.equal(parseCameraBody({ password: '' }, { partial: true }).password, null, 'bos metin = sil');
    assert.equal(parseCameraBody({ gate_id: null }, { partial: true }).gateId, null, 'kapi bagini kaldir');
    assert.throws(() => parseCameraBody({ password: 'x'.repeat(121) }, { partial: true }), (e) => e.statusCode === 400, 'parola en cok 120 karakter');
  });
});

describe('plate_gates_common: sürüm 3 sözleşme alanları', () => {
  const NOW = Date.parse('2026-10-29T12:00:00Z');
  const base = { event_id: 'evt-0000001', camera_id: 7, plate: '34 abc 123', decision: 'acildi', seen_at: '2026-10-29T11:59:00Z' };

  it('olay v3 alanlari (apartment_id, kind, gate_command) yalniz surum 3 ile okunur; hatali deger olayi dusurmez', () => {
    const v3 = parseEdgeEvent({ ...base, schema_version: 3, apartment_id: 5, kind: 'resident', gate_command: 'accepted' }, NOW);
    assert.deepEqual([v3.apartmentHint, v3.identityKind, v3.gateCommand], [5, 'resident', 'accepted']);
    const old = parseEdgeEvent({ ...base, schema_version: 2, apartment_id: 5, kind: 'resident', gate_command: 'accepted' }, NOW);
    assert.deepEqual([old.apartmentHint, old.identityKind, old.gateCommand], [null, null, null]);
    const junk = parseEdgeEvent({ ...base, schema_version: 3, apartment_id: 'x', kind: 'hacker', gate_command: 'belki' }, NOW);
    assert.deepEqual([junk.apartmentHint, junk.identityKind, junk.gateCommand], [null, null, null]);
  });

  it('kalp atisi: tanima hazirligi yalniz v3; not temizlenir ve kirpilir', () => {
    const beat = parseHeartbeat({ schema_version: 3, recognition: { ready: false, note: `  kalibrasyon\u0007 modu ${'x'.repeat(200)}` } });
    assert.equal(beat.recognitionReady, false);
    assert.equal(beat.recognitionNote.length, 80);
    assert.ok(!beat.recognitionNote.includes('\u0007'));
    assert.equal(parseHeartbeat({ schema_version: 2, recognition: { ready: true } }).recognitionReady, null);
    assert.equal(parseHeartbeat({ schema_version: 3 }).recognitionReady, null);
    assert.equal(parseHeartbeat({ schema_version: 3, recognition: { ready: 'evet' } }).recognitionReady, null);
  });

  it('senkron sorgusu surumu doner; komut sonucu: keşif cihazlari temizlenir, probe rtsp_url kimliksiz olmali', () => {
    assert.equal(parseSyncQuery({ schema_version: '3' }).schemaVersion, 3);
    assert.equal(parseSyncQuery({}).schemaVersion, 1);
    const discovered = parseCommandResult(
      {
        schema_version: 3,
        status: 'done',
        result: {
          devices: [
            { ip: '192.168.1.64', ports: [554, 80, 99999, 'x'], name: 'Kamera\n1', model: 'DS-2CD', source: 'onvif+tarama', label: 'ONVIF kamera', rtsp_port: 554 },
            { ip: 'not-an-ip', ports: [554] },
            { ip: '192.168.1.65', source: 'garip' },
          ],
          summary: 'özet',
          onvif_count: 1,
          scan_count: 2,
          interfaces: ['192.168.1.10', 'x'],
        },
      },
      'discover',
    );
    assert.equal(discovered.result.devices.length, 2);
    assert.deepEqual(discovered.result.devices[0].ports, [554, 80]);
    assert.equal(discovered.result.devices[0].name, 'Kamera 1');
    assert.equal(discovered.result.devices[1].source, 'tarama');
    assert.deepEqual(discovered.result.interfaces, ['192.168.1.10']);
    const probe = parseCommandResult({ schema_version: 3, status: 'done', result: { ok: true, width: 1920, height: 1080, rtsp_url: 'rtsp://admin:pw@10.0.0.1/x' } }, 'probe');
    assert.equal(probe.result.rtsp_url, null, 'kimlik tasiyan adres REDDEDILIR (sir sizdirmaz)');
    const clean = parseCommandResult({ schema_version: 3, status: 'done', result: { ok: true, width: 640, height: 360, rtsp_url: 'rtsp://10.0.0.1:554/x' } }, 'probe');
    assert.equal(clean.result.rtsp_url, 'rtsp://10.0.0.1:554/x');
    assert.equal(parseCommandResult({ schema_version: 3, status: 'failed', message: 'hata' }, 'probe').result, null);
    assert.throws(() => parseCommandResult({ schema_version: 3, status: 'belki' }, 'probe'), (e) => e.statusCode === 400);
    assert.throws(() => parseCommandResult({ schema_version: 9, status: 'done' }, 'probe'), (e) => e.code === 'UNSUPPORTED_SCHEMA');
  });

  it('goruntu yukleme: JPEG imzasi + boyut siniri + zaman ustbilgisi kisiti; ayar iliskisi (bos < aktif aralik) 400', () => {
    const now = Date.parse('2026-10-29T12:00:00Z');
    const good = parseSnapshotUpload(JPEG, { 'x-captured-at': '2026-10-29T11:59:58Z', 'x-frame-width': '640', 'x-frame-height': '360' }, now);
    assert.deepEqual([good.width, good.height, good.byteSize, good.capturedAt.toISOString()], [640, 360, JPEG.length, '2026-10-29T11:59:58.000Z']);
    assert.equal(parseSnapshotUpload(JPEG, { 'x-captured-at': '2020-01-01T00:00:00Z' }, now).capturedAt.getTime(), now, 'cok eski zaman sunucu saatiyle degisir');
    assert.equal(parseSnapshotUpload(JPEG, { 'x-captured-at': '2026-10-29T13:00:00Z' }, now).capturedAt.getTime(), now, 'gelecek zaman sunucu saatiyle degisir');
    assert.throws(() => parseSnapshotUpload(Buffer.from('GIF89a'), {}, now), (e) => e.code === 'INVALID_SNAPSHOT');
    assert.throws(() => parseSnapshotUpload(null, {}, now), (e) => e.code === 'INVALID_SNAPSHOT');
    assert.throws(() => parseSnapshotUpload(Buffer.alloc(MAX_SNAPSHOT_BYTES + 1, 0xff), {}, now), (e) => e.statusCode === 413);
    assert.throws(() => mergeSettings({}, { snapshot_interval_seconds: 30, snapshot_idle_interval_seconds: 10 }), (e) => e.code === 'INVALID_BODY');
    assert.equal(mergeSettings({}, { snapshot_interval_seconds: 3, snapshot_idle_interval_seconds: 20 }).snapshot_idle_interval_seconds, 20);
  });
});

describe('plate_cameras_common: otomatik açma durumu, kimlik ve kapı durumu metinleri', () => {
  const edge = (over = {}) => ({ online: true, recognition_ready: true, ...over });

  it('Etkin yalniz: kenar cevrimici + model onayli + kapiya bagli etkin kamera; degilse nedenli satir', () => {
    assert.equal(computeAutoOpen({ edges: [edge()], boundActiveCameras: 2 }).state, 'active');
    const cases = [
      [{ edges: [], boundActiveCameras: 3 }, 'no_edge_client'],
      [{ edges: [edge({ online: false })], boundActiveCameras: 3 }, 'edge_offline'],
      [{ edges: [edge({ recognition_ready: false })], boundActiveCameras: 3 }, 'model_not_approved'],
      [{ edges: [edge({ recognition_ready: null })], boundActiveCameras: 3 }, 'model_unknown'],
      [{ edges: [edge()], boundActiveCameras: 0 }, 'no_camera'],
    ];
    for (const [input, reason] of cases) {
      const out = computeAutoOpen(input);
      assert.deepEqual([out.state, out.reason, out.message], ['inactive', reason, AUTO_OPEN_MESSAGES[reason]]);
    }
    assert.equal(computeAutoOpen({ edges: [edge({ online: false }), edge()], boundActiveCameras: 1 }).state, 'active', 'biri cevrimici ve onayli yeter');
    for (const text of Object.values(AUTO_OPEN_MESSAGES)) assert.ok(!/açıldı/i.test(text), 'kapi dili: acildi denmez');
  });

  it('canli akis kimligi: sakin "Ali Y." + daire, misafir yalniz daire, tanimsiz/yetkisiz null; kapi durumu komut dili', () => {
    assert.deepEqual(liveIdentity({ kind: 'resident', blockName: 'A', unitLabel: '5', fullName: 'Ali Yılmaz' }, true), { kind: 'resident', apartment_label: 'A - 5', person_label: 'Ali Y.' });
    assert.deepEqual(liveIdentity({ kind: 'guest', blockName: 'A', unitLabel: '5', fullName: 'Gizli Kisi' }, true), { kind: 'guest', apartment_label: 'A - 5', person_label: null });
    assert.equal(liveIdentity({ kind: null, blockName: 'A', unitLabel: '5' }, true), null, 'tanimsiz: yalniz plaka');
    assert.equal(liveIdentity({ kind: 'resident', blockName: 'A', unitLabel: '5', fullName: 'Ali Yılmaz' }, false), null, 'kurul / gorevli kisi goremez');
    assert.equal(apartmentText(null, null), null);
    assert.equal(gateStateOf({ gateCommand: 'accepted' }), 'triggered');
    assert.equal(gateStateOf({ gateCommand: 'failed', decisionKind: 'red' }), 'no_response');
    assert.equal(gateStateOf({ gateCommand: null, decisionKind: 'acildi' }), 'triggered', 'eski kayit: acildi = komut kabul edildi');
    assert.equal(gateStateOf({ gateCommand: null, decisionKind: 'kara_liste' }), null);
  });

  it('kapi gunlugu satiri: plaka + kisi, misafir, bilinmeyen; "acildi" yazilmaz', () => {
    assert.deepEqual(doorLogEntry({ plateText: '34 ABC 123', identityKind: 'resident', apartmentLabel: 'A - 5', personLabel: 'Ali Y.' }), { userName: '34 ABC 123 · Ali Y.', apartmentLabel: 'A - 5' });
    assert.equal(doorLogEntry({ plateText: '34 ABC 123', identityKind: 'resident', apartmentLabel: null, personLabel: null }).userName, '34 ABC 123 · Kayıtlı araç');
    assert.equal(doorLogEntry({ plateText: '34 ABC 123', identityKind: 'guest', apartmentLabel: 'A - 5', personLabel: 'Gizli' }).userName, '34 ABC 123 · Misafir');
    assert.deepEqual(doorLogEntry({ plateText: '06 XY 99', identityKind: null, apartmentLabel: null, personLabel: null }), { userName: '06 XY 99', apartmentLabel: null });
  });
});

// --- Komut kuyruğu -------------------------------------------------------------------------------------------------------------------------

describe('plate_edge_commands: hedef kenar, atomik talep, sonuç, süre dolumu', () => {
  beforeEach(() => mock.method(console, 'error', () => {}));
  after(() => {
    mock.restoreAll();
    uninstallFakePool();
  });

  it('hedef kenar: acik secim > tek kenar; hic yok 409 NO_EDGE_CLIENT; birden cok 400 EDGE_CLIENT_REQUIRED (liste ile); bilinmeyen 404', () => {
    const a = { id: 1, name: 'A', online: true };
    const b = { id: 2, name: 'B', online: false };
    assert.equal(pickTargetEdge([a], null), a);
    assert.equal(pickTargetEdge([a, b], 2), b);
    assert.throws(() => pickTargetEdge([], null), (e) => e.statusCode === 409 && e.code === 'NO_EDGE_CLIENT');
    assert.throws(() => pickTargetEdge([a, b], null), (e) => e.statusCode === 400 && e.code === 'EDGE_CLIENT_REQUIRED' && e.extra.clients.length === 2);
    assert.throws(() => pickTargetEdge([a], 9), (e) => e.statusCode === 404 && e.code === 'EDGE_CLIENT_NOT_FOUND');
  });

  it('talep: FOR UPDATE SKIP LOCKED + yalniz pending; probe yuku parolayi COZEREK uretir (DB de duz yok); kamerasi olmayan probe hemen failed', async () => {
    const secret = encryptSecret('Gizli123!');
    assert.ok(secret.startsWith('v1:') && !secret.includes('Gizli123'));
    const fake = installFakePool([
      siteSettingsRow(null),
      [/^UPDATE plate_edge_commands SET status = 'running'/, () => ok([
        { id: '9', kind: 'probe', payload: {}, camera_id: '11', created_at: new Date('2026-10-29T12:00:00Z') },
        { id: '8', kind: 'discover', payload: {}, camera_id: null, created_at: new Date('2026-10-29T11:59:00Z') },
        { id: '10', kind: 'probe', payload: {}, camera_id: '12', created_at: new Date('2026-10-29T12:01:00Z') },
      ])],
      [/FROM camera_devices WHERE id = \$1 AND site_code = \$2/, (_s, p) => ok(Number(p[0]) === 11 ? [{ id: 11, name: 'Giriş', brand: 'hikvision', host: '192.168.1.64', port: 554, rtsp_url: 'rtsp://192.168.1.64/x', username: 'admin', password_enc: secret, is_active: true }] : [])],
    ]);
    const out = await claimCommands(CLIENT);
    assert.deepEqual(out.map((c) => [c.id, c.kind]), [[8, 'discover'], [9, 'probe']], 'sirali; kamerasi olmayan 10 hic verilmez');
    assert.deepEqual(out[1].payload, { camera_id: 11, name: 'Giriş', brand: 'hikvision', host: '192.168.1.64', port: 554, rtsp_url: 'rtsp://192.168.1.64/x', username: 'admin', password: 'Gizli123!' });
    const claim = fake.find(/^UPDATE plate_edge_commands SET status = 'running'/)[0];
    assert.match(claim.sql, /FOR UPDATE SKIP LOCKED/);
    assert.match(claim.sql, /status = 'pending'/);
    assert.equal(fake.find(/^UPDATE plate_edge_commands SET status = 'failed'/).length, 1);
    assert.ok(fake.log.every((c) => !JSON.stringify(c.params).includes('Gizli123')), 'parola SQL parametresine duz yazilmaz');
    assert.match(fake.find(/^UPDATE plate_edge_commands SET status = 'expired'/)[0].sql, /created_at < NOW\(\) - make_interval/, 'talepten once suresi dolanlar kapanir');
  });

  it('sonuc: probe tamam -> kamera sinama sutunlari + rtsp_url (bossa) yazilir; ikinci bildirim duplicate; suresi dolmus 409 COMMAND_EXPIRED; talep edilmemis 409; baska kenarin komutu 404', async () => {
    const state = { status: 'running' };
    const fake = installFakePool([[/FROM plate_edge_commands WHERE id = \$1 AND site_code = \$2 AND edge_client_id = \$3 FOR UPDATE/, (_s, p, st) => ok(Number(p[0]) === 77 && Number(p[2]) === 5 ? [{ id: 77, kind: 'probe', status: st.status, camera_id: 11 }] : [])]], state);
    const body = { schema_version: 3, status: 'done', result: { ok: true, width: 1920, height: 1080, rtsp_url: 'rtsp://10.0.0.1:554/Streaming/Channels/101' } };
    assert.deepEqual(await completeCommand(CLIENT, '77', body), { ok: true, duplicate: false });
    const camera = fake.find(/^UPDATE camera_devices SET probe_status/)[0];
    assert.deepEqual(camera.params, [11, SITE, 'ok', null, 1920, 1080, 'rtsp://10.0.0.1:554/Streaming/Channels/101']);
    assert.match(camera.sql, /rtsp_url = COALESCE\(rtsp_url, \$7\)/);
    const done = fake.find(/^UPDATE plate_edge_commands SET status/)[0];
    assert.equal(done.params[1], 'done');
    assert.equal(JSON.parse(done.params[3]).width, 1920);
    // Ulasilamayan kamera: komut "done", kamera "failed" + mesaj
    fake.log.length = 0;
    await completeCommand(CLIENT, '77', { schema_version: 3, status: 'done', result: { ok: false, reason: 'baglanti_acilamadi', message: 'RTSP bağlantısı açılamadı' } });
    assert.deepEqual(fake.find(/^UPDATE camera_devices SET probe_status/)[0].params.slice(2, 6), ['failed', 'RTSP bağlantısı açılamadı', null, null]);
    // Istisna ile biten komut
    fake.log.length = 0;
    await completeCommand(CLIENT, '77', { schema_version: 3, status: 'failed', message: 'kenar hatasi' });
    assert.equal(fake.find(/^UPDATE camera_devices SET probe_status/)[0].params[2], 'failed');
    // Idempotent / suresi dolmus / talep edilmemis / sahipsiz
    state.status = 'done';
    fake.log.length = 0;
    assert.deepEqual(await completeCommand(CLIENT, '77', body), { ok: true, duplicate: true });
    assert.equal(fake.find(/^UPDATE/).length, 0, 'ikinci bildirim hicbir sey yazmaz');
    state.status = 'expired';
    await assert.rejects(() => completeCommand(CLIENT, '77', body), (e) => e.statusCode === 409 && e.code === 'COMMAND_EXPIRED');
    state.status = 'pending';
    await assert.rejects(() => completeCommand(CLIENT, '77', body), (e) => e.statusCode === 409 && e.code === 'COMMAND_NOT_RUNNING');
    await assert.rejects(() => completeCommand({ ...CLIENT, id: 6 }, '77', body), (e) => e.statusCode === 404);
    await assert.rejects(() => completeCommand(CLIENT, 'x', body), (e) => e.statusCode === 404);
  });

  it('keşif sonucu satira temizlenmis yazilir; süre dolumu bekleyen sinamali kamerayi "failed" yapar; komut gorunumu waiting_offline', async () => {
    const fake = installFakePool([
      [/FROM plate_edge_commands WHERE id/, () => ok([{ id: 5, kind: 'discover', status: 'running', camera_id: null }])],
      [/^UPDATE plate_edge_commands SET status = 'expired'/, () => ok([{ kind: 'probe', camera_id: '11' }, { kind: 'discover', camera_id: null }])],
    ]);
    await completeCommand(CLIENT, '5', { schema_version: 3, status: 'done', result: { devices: [{ ip: '10.0.0.4', ports: [554] }, { ip: 'x' }] } });
    assert.equal(JSON.parse(fake.find(/^UPDATE plate_edge_commands SET status/)[0].params[3]).devices.length, 1);
    assert.equal(await expireStaleCommands(pool, SITE, 600), 2);
    const failed = fake.find(/^UPDATE camera_devices SET probe_status = 'failed'/)[0];
    assert.deepEqual(failed.params[1], [11]);
    const edgeById = new Map([[5, { id: 5, name: 'PC', online: false, last_seen_at: null }]]);
    const view = mapCommand({ id: 1, kind: 'discover', status: 'pending', edge_client_id: 5, created_at: new Date('2026-10-29T12:00:00Z') }, { edgeById, ttlSeconds: 600 });
    assert.equal(view.waiting_offline, true);
    assert.equal(view.expires_at, '2026-10-29T12:10:00.000Z');
    assert.equal(mapCommand({ id: 1, kind: 'discover', status: 'running', edge_client_id: 5, created_at: new Date() }, { edgeById, ttlSeconds: 600 }).waiting_offline, false);
  });
});

// --- Kamera yönetimi -----------------------------------------------------------------------------------------------------------------------

describe('plate_cameras_service: ekle / değiştir / sına / keşif / görünüm', () => {
  after(uninstallFakePool);

  const cameraRow = (over = {}) => ({
    id: 11, name: 'Giriş', brand: 'hikvision', host: '192.168.1.64', port: null, rtsp_url: 'rtsp://192.168.1.64/Streaming/Channels/101', username: 'admin', has_password: true, is_active: true,
    last_event_at: null, probe_status: 'pending', probe_message: null, probe_width: null, probe_height: null, probe_at: null, gate_id: 3, gate_direction: 'giris', gate_name: 'Ana Kapı', gate_mode: 'cift',
    last_frame_at: new Date(), last_read_at: null, reported_at: new Date(), status_edge_id: 5, snapshot_at: new Date(), ...over,
  });
  const cameraSelect = (rows) => [/FROM camera_devices c LEFT JOIN plate_gate_cameras gc/, () => ok(rows)];

  it('ekle: parola SIFRELI yazilir ve yanitta HICBIR yerde donmez; marka sablonuyla RTSP adresi; kapi + yon baglanir; kenar varsa sinama komutu kuyruga girer', async () => {
    const fake = installFakePool([
      siteSettingsRow(null),
      edgeClients([edgeRow()]),
      [/^INSERT INTO camera_devices/, () => ok([{ id: 11 }])],
      [/^SELECT id, direction_mode FROM plate_gates/, () => ok([{ id: 3, direction_mode: 'cift' }])],
      [/^SELECT gate_id, direction FROM plate_gate_cameras/, () => ok([])],
      [/^INSERT INTO plate_edge_commands/, () => ok([{ id: 77, edge_client_id: 5, kind: 'probe', status: 'pending', camera_id: 11, created_at: new Date() }])],
      cameraSelect([cameraRow()]),
    ]);
    const out = await createCamera({ siteCode: SITE, authUser: MANAGER, body: { name: 'Giriş', brand: 'hikvision', host: '192.168.1.64', username: 'admin', password: 'Gizli123!', gate_id: 3, direction: 'giris' } });
    const insert = fake.find(/^INSERT INTO camera_devices/)[0];
    assert.equal(insert.params[8], 'rtsp://192.168.1.64/Streaming/Channels/101');
    assert.ok(insert.params[6].startsWith('v1:') && !insert.params[6].includes('Gizli123'), 'AES-256-GCM sifreli');
    assert.equal(decryptSecret(insert.params[6]), 'Gizli123!', 'gidis-donus');
    assert.match(insert.params[7], /^[a-f0-9]{64}$/, 'olay belirteci ozeti rastgele; duz hali tutulmaz');
    assert.deepEqual(fake.find(/^INSERT INTO plate_gate_cameras/)[0].params, [SITE, 3, 11, 'giris']);
    assert.equal(out.probe_command_id, 77);
    assert.equal(out.edge.id, 5);
    assert.equal(out.camera.has_password, true);
    assert.ok(!JSON.stringify(out).includes('Gizli123'), 'yanitta parola yok');
    assert.equal(fake.find(/INSERT INTO audit_log/).length, 1);
    assert.ok(!JSON.stringify(fake.find(/INSERT INTO audit_log/)[0].params).includes('Gizli123'), 'denetim kaydinda parola yok');
    assert.deepEqual(fake.find(/^UPDATE camera_devices SET probe_status = 'pending'/).length, 1);
  });

  it('ekle: kenar yoksa sinama komutu YOK (probe_command_id null, durust); kapi modu ile yon uyusmazligi 400; bilinmeyen kapi 404', async () => {
    installFakePool([
      siteSettingsRow(null),
      edgeClients([]),
      [/^INSERT INTO camera_devices/, () => ok([{ id: 12 }])],
      [/^SELECT id, direction_mode FROM plate_gates/, (_s, p) => ok(Number(p[0]) === 3 ? [{ id: 3, direction_mode: 'giris' }] : [])],
      [/^SELECT gate_id, direction FROM plate_gate_cameras/, () => ok([])],
      cameraSelect([cameraRow({ id: 12, probe_status: 'none' })]),
    ]);
    const out = await createCamera({ siteCode: SITE, authUser: MANAGER, body: { name: 'K', brand: 'onvif', host: '10.0.0.9' } });
    assert.equal(out.probe_command_id, null);
    assert.equal(out.edge, null);
    await assert.rejects(() => createCamera({ siteCode: SITE, authUser: MANAGER, body: { name: 'K', brand: 'onvif', host: '10.0.0.9', gate_id: 3, direction: 'cikis' } }), (e) => e.code === 'CAMERA_DIRECTION_CONFLICT');
    await assert.rejects(() => createCamera({ siteCode: SITE, authUser: MANAGER, body: { name: 'K', brand: 'onvif', host: '10.0.0.9', gate_id: 99 } }), (e) => e.code === 'GATE_NOT_FOUND');
  });

  it('degistir: parola gonderilmezse korunur, "" siler; adres degisince yeniden sinanir; pasif yapinca son kare silinir (KVKK) ve sinama yok', async () => {
    const fake = installFakePool([
      siteSettingsRow(null),
      edgeClients([edgeRow()]),
      [/FROM camera_devices WHERE id = \$1 AND site_code = \$2 FOR UPDATE/, () => ok([{ id: 11, brand: 'hikvision', host: '192.168.1.64', port: null, rtsp_url: 'rtsp://192.168.1.64/Streaming/Channels/101', is_active: true }])],
      [/^INSERT INTO plate_edge_commands/, () => ok([{ id: 78, edge_client_id: 5, kind: 'probe', status: 'pending', camera_id: 11, created_at: new Date() }])],
      cameraSelect([cameraRow()]),
    ]);
    let out = await updateCamera({ siteCode: SITE, rawId: '11', authUser: MANAGER, body: { name: 'Yeni ad' } });
    let update = fake.find(/^UPDATE camera_devices SET name/)[0];
    assert.ok(!/password_enc/.test(update.sql), 'parola alani gonderilmedi: dokunulmaz');
    assert.equal(out.probe_command_id, null, 'yalniz ad degisti: yeniden sinama gerekmez');
    fake.log.length = 0;
    out = await updateCamera({ siteCode: SITE, rawId: '11', authUser: MANAGER, body: { password: 'Yeni-Parola-9' } });
    update = fake.find(/^UPDATE camera_devices SET password_enc/)[0];
    assert.equal(decryptSecret(update.params[2]), 'Yeni-Parola-9');
    assert.equal(out.probe_command_id, 78);
    fake.log.length = 0;
    await updateCamera({ siteCode: SITE, rawId: '11', authUser: MANAGER, body: { password: '' } });
    assert.equal(fake.find(/^UPDATE camera_devices SET password_enc/)[0].params[2], null);
    fake.log.length = 0;
    await updateCamera({ siteCode: SITE, rawId: '11', authUser: MANAGER, body: { host: '192.168.1.99', port: 8554 } });
    assert.equal(fake.find(/^UPDATE camera_devices SET host/)[0].params.includes('rtsp://192.168.1.99:8554/Streaming/Channels/101'), true, 'adres degisince RTSP adresi yeni hedefe tasinir');
    fake.log.length = 0;
    const off = await updateCamera({ siteCode: SITE, rawId: '11', authUser: MANAGER, body: { is_active: false } });
    assert.equal(fake.find(/^DELETE FROM plate_camera_snapshots WHERE camera_id/).length, 1);
    assert.equal(off.probe_command_id, null);
    await assert.rejects(() => updateCamera({ siteCode: SITE, rawId: 'abc', authUser: MANAGER, body: { name: 'x' } }), (e) => e.statusCode === 404);
  });

  it('sina + keşif: kenar yoksa 409; ayni kenara acik komut varsa yenisi acilmaz (reused); cevrimdisi kenarda waiting_offline; son keşif durumu', async () => {
    const open = { id: 90, edge_client_id: 5, kind: 'discover', status: 'running', camera_id: null, created_at: new Date() };
    const handlers = (rows, openRow) => [
      siteSettingsRow(null),
      edgeClients(rows),
      [/^SELECT \* FROM plate_edge_commands\s+WHERE edge_client_id/, () => ok(openRow ? [openRow] : [])],
      [/^INSERT INTO plate_edge_commands/, () => ok([{ id: 91, edge_client_id: 5, kind: 'discover', status: 'pending', camera_id: null, created_at: new Date() }])],
      [/^SELECT \* FROM plate_edge_commands WHERE site_code/, () => ok([open])],
    ];
    installFakePool(handlers([], null));
    await assert.rejects(() => startDiscovery({ siteCode: SITE, authUser: MANAGER }), (e) => e.code === 'NO_EDGE_CLIENT');
    installFakePool(handlers([edgeRow()], open));
    const reused = await startDiscovery({ siteCode: SITE, authUser: MANAGER });
    assert.deepEqual([reused.reused, reused.command.id], [true, 90]);
    const fake = installFakePool(handlers([edgeRow({ last_seen_at: new Date(Date.now() - 3600_000) })], null));
    const fresh = await startDiscovery({ siteCode: SITE, authUser: MANAGER });
    assert.deepEqual([fresh.reused, fresh.command.id, fresh.command.status], [false, 91, 'pending']);
    assert.equal(fresh.command.waiting_offline, true, 'kenar PC cevrimdisi: durust');
    assert.equal(fresh.command.edge.online, false);
    assert.equal(fake.find(/INSERT INTO audit_log/).length, 1);
    installFakePool(handlers([edgeRow()], null));
    const latest = await getLatestDiscovery({ siteCode: SITE });
    assert.equal(latest.command.id, 90);
    assert.equal(latest.edge.id, 5);
    installFakePool([siteSettingsRow(null), edgeClients([edgeRow(), edgeRow({ id: 6, name: 'PC 2' })])]);
    await assert.rejects(() => startDiscovery({ siteCode: SITE, authUser: MANAGER, body: {} }), (e) => e.code === 'EDGE_CLIENT_REQUIRED');
    installFakePool([
      [/^SELECT id, is_active FROM camera_devices/, () => ok([{ id: 11, is_active: false }])],
    ]);
    await assert.rejects(() => probeCamera({ siteCode: SITE, rawId: '11', authUser: MANAGER }), (e) => e.code === 'CAMERA_INACTIVE');
  });

  it('görünüm: kamera satirlari rozet / yon / sinama / karo bilgisiyle; kenar + otomatik acma durumu; izleyen yalniz yazma yetkisinde isaretlenir; parola yok', async () => {
    const fake = installFakePool([
      siteSettingsRow(null),
      edgeClients([edgeRow({ recognition_ready: true })]),
      [/FROM plate_gates WHERE site_code = \$1 ORDER BY sort_order/, () => ok([{ id: 3, name: 'Ana Kapı', direction_mode: 'cift', is_active: true }])],
      cameraSelect([
        cameraRow(),
        cameraRow({ id: 12, name: 'Pasif', is_active: false, gate_id: null, gate_direction: null, snapshot_at: null, rtsp_url: null, probe_status: 'none', reported_at: null, last_frame_at: null }),
        cameraRow({ id: 13, name: 'Kopuk', last_frame_at: new Date(Date.now() - 1800_000), probe_status: 'failed', probe_message: 'RTSP bağlantısı açılamadı' }),
      ]),
    ]);
    const out = await getCamerasOverview({ siteCode: SITE, canWrite: true });
    assert.deepEqual(out.cameras.map((c) => [c.id, c.status.color]), [[11, 'yesil'], [12, 'gri'], [13, 'kirmizi']]);
    assert.deepEqual(out.cameras[0].gate, { id: 3, name: 'Ana Kapı', direction_mode: 'cift' });
    assert.equal(out.cameras[0].direction, 'giris');
    assert.equal(out.cameras[1].gate, null);
    assert.equal(out.cameras[1].managed, false);
    assert.equal(out.cameras[2].probe.message, 'RTSP bağlantısı açılamadı');
    assert.equal(out.cameras[0].snapshot.available, true);
    assert.equal(out.auto_open.state, 'active');
    assert.deepEqual(out.edge, { clients: out.edge.clients, online: true, count: 1 });
    assert.deepEqual(out.snapshot, { interval_seconds: 4, idle_interval_seconds: 15, keep_minutes: 30 });
    assert.deepEqual(out.brands.map((b) => b.code), ['hikvision', 'tiandy', 'onvif']);
    assert.equal(fake.find(/INSERT INTO plate_snapshot_watch/).length, 1);
    assert.ok(!/"password"\s*:/.test(JSON.stringify(out)), 'parola alani yanitta yok');
    fake.log.length = 0;
    await getCamerasOverview({ siteCode: SITE, canWrite: false });
    assert.equal(fake.find(/INSERT INTO plate_snapshot_watch/).length, 0, 'kurul / gorevli izleyen sayilmaz');
  });

  it('bakım: eski / pasif kare silinir, komutlar kapanir, eski komut kayitlari silinir', async () => {
    const fake = installFakePool([
      [/^DELETE FROM plate_camera_snapshots sn/, () => ({ rows: [], rowCount: 4 })],
      [/^UPDATE plate_edge_commands c SET status = 'expired'/, () => ok([{ kind: 'probe', camera_id: '11', site_code: String(SITE) }])],
      [/^DELETE FROM plate_edge_commands/, () => ({ rows: [], rowCount: 6 })],
    ]);
    assert.deepEqual(await runCamerasHousekeeping(pool), { snapshotsRemoved: 4, commandsExpired: 1, commandsRemoved: 6 });
    assert.match(fake.find(/^DELETE FROM plate_camera_snapshots/)[0].sql, /snapshot_keep_minutes/);
    assert.match(fake.find(/^DELETE FROM plate_camera_snapshots/)[0].sql, /c\.is_active/);
    assert.equal(fake.find(/^UPDATE camera_devices SET probe_status = 'failed'/).length, 1);
  });
});

// --- Görüntü karoları ------------------------------------------------------------------------------------------------------------

describe('plate_cameras_service: görüntü karoları (tek son kare, KVKK)', () => {
  after(uninstallFakePool);

  it('yukleme: son kare UPSERT (eski kare yeniyi ezmez); izleyen varsa kisa aralik; yoksa bosta araligi; pasif / baska site / JPEG degil reddedilir', async () => {
    const watched = { value: true };
    const fake = installFakePool([
      siteSettingsRow(null),
      [/^SELECT id, is_active FROM camera_devices WHERE id = \$1 AND site_code = \$2/, (_s, p) => ok(Number(p[0]) === 11 ? [{ id: 11, is_active: true }] : Number(p[0]) === 12 ? [{ id: 12, is_active: false }] : [])],
      [/FROM plate_snapshot_watch WHERE site_code/, () => ok(watched.value ? [{ x: 1 }] : [])],
    ]);
    const first = await storeSnapshot(CLIENT, '11', JPEG, { 'x-frame-width': '640', 'x-frame-height': '360' });
    assert.deepEqual(first, { ok: true, watched: true, next_seconds: 4 });
    const upsert = fake.find(/^INSERT INTO plate_camera_snapshots/)[0];
    assert.match(upsert.sql, /ON CONFLICT \(camera_id\) DO UPDATE/);
    assert.match(upsert.sql, /WHERE plate_camera_snapshots\.captured_at <= EXCLUDED\.captured_at/);
    assert.equal(upsert.params[1], SITE);
    assert.ok(Buffer.isBuffer(upsert.params[3]));
    watched.value = false;
    assert.deepEqual(await storeSnapshot(CLIENT, '11', JPEG, {}), { ok: true, watched: false, next_seconds: 15 });
    await assert.rejects(() => storeSnapshot(CLIENT, '12', JPEG, {}), (e) => e.code === 'CAMERA_INACTIVE');
    await assert.rejects(() => storeSnapshot(CLIENT, '99', JPEG, {}), (e) => e.code === 'CAMERA_NOT_FOUND');
    await assert.rejects(() => storeSnapshot(CLIENT, '11', Buffer.from('<html>'), {}), (e) => e.code === 'INVALID_SNAPSHOT');
    await assert.rejects(() => storeSnapshot(CLIENT, 'abc', JPEG, {}), (e) => e.statusCode === 404);
    assert.equal(fake.find(/DELETE FROM plate_camera_snapshots/).length, 0);
  });

  it('okuma: saklama suresi icinde + etkin kamera; yoksa 404 NO_SNAPSHOT; ETag = kare zamani', async () => {
    const captured = new Date('2026-10-29T12:00:00.000Z');
    const fake = installFakePool([siteSettingsRow({ snapshot_keep_minutes: 5 }), [/FROM plate_camera_snapshots sn INNER JOIN camera_devices c/, (_s, p) => ok(Number(p[0]) === 11 ? [{ jpeg: JPEG, captured_at: captured }] : [])]]);
    const got = await readSnapshot({ siteCode: SITE, rawId: '11' });
    assert.equal(got.etag, `"${captured.getTime()}"`);
    assert.deepEqual(fake.find(/FROM plate_camera_snapshots sn/)[0].params, [11, SITE, 5]);
    assert.match(fake.find(/FROM plate_camera_snapshots sn/)[0].sql, /c\.is_active/);
    await assert.rejects(() => readSnapshot({ siteCode: SITE, rawId: '12' }), (e) => e.statusCode === 404 && e.code === 'NO_SNAPSHOT');
  });
});

// --- HTTP: yönetici ucu yetkisi + kenar uçları ---------------------------------------------------------------------------------

describe('plate-recognition kamera uçları: yetki, görüntü 403 / 304, parola yok', () => {
  const SITE_1 = 1000000001;
  const SITE_2 = 1000000002;
  const mk = (id, role) => ({ id, user_code: id, userCode: id, role, full_name: `U${id}`, email: `u${id}@example.com` });
  const users = { mgrA: mk(20001, 'site_manager'), mgrB: mk(20002, 'site_manager'), resident: mk(20004, 'apartment_owner'), board: mk(20006, 'individual') };
  let server;
  let baseUrl;
  let fake;
  const hitPaths = ['/plate-recognition/cameras', '/plate-recognition/cameras/11/snapshot', '/plate-recognition/discovery', '/plate-recognition/cameras/11/probe'];

  function access() {
    return [
      [/^SELECT 1 FROM site_manager_sites WHERE site_code = \$1 AND manager_user_code = \$2 LIMIT 1$/, (_s, params) => {
        const [site, user] = params.map(Number);
        return ok((site === SITE_1 && user === 20001) || (site === SITE_2 && user === 20002) ? [{ x: 1 }] : []);
      }],
      [/FROM site_memberships WHERE site_code = \$1 AND user_code = \$2 AND role IN \('SITE_OWNER', 'SITE_ADMIN'\)/, () => ok([])],
      [/is_board_here/, (_s, params) => {
        const [site, user] = params.map(Number);
        return ok([{ is_board_here: site === SITE_1 && user === 20006, is_member_here: (site === SITE_1 && user === 20006) || user === 20004, has_other_role: user === 20002 || user === 20006 }]);
      }],
      [/FROM site_memberships WHERE site_code = \$1 AND user_code = \$2 AND role = 'STAFF'/, () => ok([])],
      [/^SELECT site_code FROM sites WHERE site_code = \$1 LIMIT 1$/, (_s, params) => ok([SITE_1, SITE_2].includes(Number(params[0])) ? [{ site_code: String(params[0]) }] : [])],
      [/^SELECT enabled FROM site_modules/, () => ok([{ enabled: true }])],
    ];
  }
  const captured = new Date('2026-10-29T12:00:00.000Z');
  const handlers = () => [
    ...access(),
    siteSettingsRow(null),
    edgeClients([edgeRow()]),
    [/FROM plate_gates WHERE site_code = \$1 ORDER BY sort_order/, () => ok([])],
    [/FROM camera_devices c LEFT JOIN plate_gate_cameras gc/, () => ok([{ id: 11, name: 'Giriş', brand: 'hikvision', host: '192.168.1.64', port: null, rtsp_url: 'rtsp://192.168.1.64/x', username: 'admin', has_password: true, is_active: true, probe_status: 'ok', probe_width: 1920, probe_height: 1080, gate_id: null, snapshot_at: captured, reported_at: new Date(), last_frame_at: new Date() }])],
    [/FROM plate_camera_snapshots sn INNER JOIN camera_devices c/, (_s, p) => ok(Number(p[0]) === 11 ? [{ jpeg: JPEG, captured_at: captured }] : [])],
  ];

  before(async () => {
    for (const suffix of ['/cameras', '/cameras/:id/snapshot', '/discovery', '/cameras/:id/probe']) {
      for (const layer of plateRecognitionRouter.stack.filter((l) => l.route && l.route.path.endsWith(`/plate-recognition${suffix}`))) {
        layer.route.stack[0].handle = (req, _res, next) => {
          req.authUser = JSON.parse(decodeURIComponent(req.headers['x-test-user']));
          next();
        };
      }
    }
    const app = express();
    app.use(express.json());
    app.use(plateRecognitionRouter);
    await new Promise((resolve) => {
      server = app.listen(0, '127.0.0.1', resolve);
    });
    baseUrl = `http://127.0.0.1:${server.address().port}`;
  });
  after(async () => {
    server.closeAllConnections?.();
    await new Promise((resolve) => server.close(resolve));
    uninstallFakePool();
  });
  beforeEach(() => {
    fake = installFakePool(handlers());
    mock.method(console, 'error', () => {});
  });

  const get = (user, suffix, headers = {}, site = SITE_1) =>
    fetch(`${baseUrl}/manager/sites/${site}${suffix}`, { headers: { 'x-test-user': encodeURIComponent(JSON.stringify(user)), ...headers } });

  it('goruntu: yonetici 200 + image/jpeg + ETag/X-Captured-At/no-store; If-None-Match 304; kurul / sakin / baska site 403; olmayan kare 404; kamera listesi kurula acik', async () => {
    const res = await get(users.mgrA, '/plate-recognition/cameras/11/snapshot');
    assert.equal(res.status, 200);
    assert.equal(res.headers.get('content-type'), 'image/jpeg');
    assert.equal(res.headers.get('cache-control'), 'no-store');
    assert.equal(res.headers.get('x-captured-at'), captured.toISOString());
    const etag = res.headers.get('etag');
    assert.equal(etag, `"${captured.getTime()}"`);
    assert.deepEqual(Buffer.from(await res.arrayBuffer()), JPEG);
    assert.equal((await get(users.mgrA, '/plate-recognition/cameras/11/snapshot', { 'if-none-match': etag })).status, 304);
    for (const [who, user] of [['kurul uyesi', users.board], ['sakin', users.resident], ['baska sitenin yoneticisi', users.mgrB]]) {
      const denied = await get(user, '/plate-recognition/cameras/11/snapshot');
      assert.equal(denied.status, 403, `${who}: goruntu YOK`);
      assert.ok(!(denied.headers.get('content-type') ?? '').includes('image'));
    }
    const missing = await get(users.mgrA, '/plate-recognition/cameras/99/snapshot');
    assert.equal(missing.status, 404);
    assert.equal((await missing.json()).code, 'NO_SNAPSHOT');
    fake.log.length = 0;
    const list = await get(users.board, '/plate-recognition/cameras');
    assert.equal(list.status, 200, 'kurul listeyi okur');
    const body = await list.json();
    assert.equal(body.cameras[0].has_password, true);
    assert.ok(!JSON.stringify(body).includes('Gizli'), 'parola yok');
    assert.equal(fake.find(/INSERT INTO plate_snapshot_watch/).length, 0, 'kurul izleyen sayilmaz');
    assert.equal((await get(users.resident, '/plate-recognition/cameras')).status, 403);
    assert.equal((await get(users.board, '/plate-recognition/discovery')).status, 200);
    const probe = await fetch(`${baseUrl}/manager/sites/${SITE_1}/plate-recognition/cameras/11/probe`, { method: 'POST', headers: { 'x-test-user': encodeURIComponent(JSON.stringify(users.board)), 'content-type': 'application/json' }, body: '{}' });
    assert.equal(probe.status, 403, 'kurul sinama komutu veremez');
    assert.ok(hitPaths.length > 0);
  });
});

describe('kenar uçları (/edge/plate/v1): komut + görüntü yolları kayıtlı; sözleşme dosyası v3', () => {
  it('uclar kayitli; goruntu yolu kimligi gövdeden ONCE dogrular (kimliksiz istek gövde okutmaz)', () => {
    const routes = plateEdgeRouter.stack.filter((l) => l.route).map((l) => `${Object.keys(l.route.methods)[0].toUpperCase()} ${l.route.path}`);
    for (const expected of ['GET /edge/plate/v1/commands', 'POST /edge/plate/v1/commands/:id/result', 'PUT /edge/plate/v1/cameras/:cameraId/snapshot']) assert.ok(routes.includes(expected), expected);
    const source = readFileSync(path.join(here, '..', 'src', 'modules', 'plate_edge_routes.js'), 'utf8');
    assert.ok(source.indexOf('authenticateEdge(edgeKeyFromHeaders(req.headers))') < source.indexOf('rawJpeg(req, res'), 'once kimlik, sonra govde');
  });

  it('sozlesme belgesi surum 3 ve v3 uclarini / alanlarini tanimlar', () => {
    const doc = readFileSync(path.join(here, '..', '..', 'docs', 'PLATFORM_PLAKA_KENAR_SOZLESMESI.md'), 'utf8');
    for (const needle of ['sürüm 3', '/commands', '/snapshot', 'gate_command', 'apartment_id', 'KVKK', 'discover', 'probe', 'trigger_type = \'plate\'', 'Kapı tetiklendi']) assert.ok(doc.includes(needle), needle);
  });
});

// --- Olay: kimlik bağlama + kapı komutu + kapı günlüğü ----------------------------------------------------------------------

describe('recordEdgeEvent (sürüm 3): kimlik bağlama, kapı komutu, SmartKeyPass kapı günlüğü', () => {
  after(uninstallFakePool);
  beforeEach(() => mock.method(console, 'error', () => {}));
  const NOW = Date.now();
  const body = (over = {}) => ({ schema_version: 3, event_id: 'evt-v3-000001', camera_id: 7, plate: '34 ABC 123', decision: 'acildi', seen_at: new Date(NOW - 5000).toISOString(), direction: 'giris', gate_command: 'accepted', ...over });

  function eventPool({ vehicle = { id: 1, apartment_id: 5, person_id: 9 }, permit = null, duplicate = false, hintApartment = null } = {}) {
    return installFakePool([
      [/FROM camera_devices c LEFT JOIN plate_gate_cameras gc/, () => ok([{ id: 7, gate_id: 3, camera_direction: 'giris' }])],
      [/^SELECT id, name, direction_mode, door_id FROM plate_gates/, () => ok([{ id: 3, name: 'Ana Kapı', direction_mode: 'cift', door_id: 40 }])],
      [/FROM plate_presence WHERE site_code = \$1 AND plate = \$2 FOR UPDATE/, () => ok([])],
      [/^SELECT id, apartment_id, person_id FROM vehicles/, () => ok(vehicle ? [vehicle] : [])],
      [/FROM plate_guest_permits WHERE site_code/, () => ok(permit ? [permit] : [])],
      [/^SELECT id FROM apartments WHERE id = \$1 AND site_code = \$2/, () => ok(hintApartment ? [{ id: hintApartment }] : [])],
      [/^INSERT INTO plate_events/, () => ok(duplicate ? [] : [{ id: 100 }])],
      [/^INSERT INTO plate_presence/, () => ok([{ id: 1 }])],
      [/^SELECT b\.block_name, a\.unit_label FROM apartments a/, () => ok([{ block_name: 'A', unit_label: '5' }])],
      [/FROM site_people sp LEFT JOIN users u/, () => ok([{ person_name: 'Ali Yılmaz' }])],
      [/FROM plate_site_settings WHERE site_code/, () => ok([])],
    ]);
  }
  const spy = () => {
    const calls = [];
    return { calls, fn: async (entry) => { calls.push(entry); return true; } };
  };

  it('kayitli arac: plate_events kimlik + kapi komutu sutunlari; kapi gunlugune "Plaka ile" satiri (kisi, daire, kapi, saat)', async () => {
    const fake = eventPool();
    const door = spy();
    const out = await recordEdgeEvent(CLIENT, body(), { writeDoorLog: door.fn });
    assert.deepEqual([out.ok, out.duplicate, out.direction, out.inside], [true, false, 'giris', true]);
    const insert = fake.find(/^INSERT INTO plate_events/)[0];
    assert.deepEqual(insert.params.slice(14), [5, 9, 'resident', 'accepted'], 'apartment_id, person_id, identity_kind, gate_command');
    assert.equal(insert.params.some((v) => v === 'Ali Yılmaz'), false, 'kisi adi satira KOPYALANMAZ');
    assert.equal(door.calls.length, 1);
    const entry = door.calls[0];
    assert.deepEqual(
      { siteCode: entry.siteCode, doorId: entry.doorId, doorName: entry.doorName, userName: entry.userName, apartmentLabel: entry.apartmentLabel, triggerType: entry.triggerType, userRole: entry.userRole },
      { siteCode: SITE, doorId: 40, doorName: 'Ana Kapı', userName: '34 ABC 123 · Ali Y.', apartmentLabel: 'A - 5', triggerType: 'plate', userRole: 'plate' },
    );
    assert.ok(!/açıldı/i.test(`${entry.userName} ${entry.doorName}`));
    assert.ok(entry.openedAt instanceof Date);
  });

  it('kapi komutu reddedildi / duplicate / red karari: kapi gunlugune YAZILMAZ; gate_command=failed saklanir', async () => {
    const door = spy();
    let fake = eventPool();
    await recordEdgeEvent(CLIENT, body({ gate_command: 'failed', reason: 'cihaz_yanit_vermedi', event_id: 'evt-v3-000002' }), { writeDoorLog: door.fn });
    assert.equal(fake.find(/^INSERT INTO plate_events/)[0].params[17], 'failed');
    eventPool({ duplicate: true });
    assert.deepEqual((await recordEdgeEvent(CLIENT, body({ event_id: 'evt-v3-000003' }), { writeDoorLog: door.fn })).duplicate, true);
    fake = eventPool();
    await recordEdgeEvent(CLIENT, body({ decision: 'red', gate_command: undefined, event_id: 'evt-v3-000004' }), { writeDoorLog: door.fn });
    await recordEdgeEvent(CLIENT, body({ decision: 'kara_liste', gate_command: undefined, event_id: 'evt-v3-000005' }), { writeDoorLog: door.fn });
    assert.equal(door.calls.length, 0);
    assert.ok(fake.find(/^INSERT INTO plate_events/).length === 2);
  });

  it('misafir izni: "34 ABC 123 · Misafir"; kenar ipucu yalniz sunucu hicbir sey bulamazsa ve daire bu siteye aitse kullanilir; surum 2 istemci v3 alani gonderemez', async () => {
    const door = spy();
    let fake = eventPool({ vehicle: null, permit: { id: 3, apartment_id: 6 } });
    await recordEdgeEvent(CLIENT, body({ event_id: 'evt-v3-000006' }), { writeDoorLog: door.fn });
    assert.deepEqual(fake.find(/^INSERT INTO plate_events/)[0].params.slice(14), [6, null, 'guest', 'accepted']);
    assert.equal(door.calls[0].userName, '34 ABC 123 · Misafir');
    fake = eventPool({ vehicle: null, permit: null, hintApartment: 8 });
    await recordEdgeEvent(CLIENT, body({ event_id: 'evt-v3-000007', apartment_id: 8, kind: 'resident' }), { writeDoorLog: door.fn });
    assert.deepEqual(fake.find(/^INSERT INTO plate_events/)[0].params.slice(14, 17), [8, null, 'resident'], 'ipucu dogrulandi (daire bu siteye ait)');
    fake = eventPool({ vehicle: null, permit: null, hintApartment: null });
    await recordEdgeEvent(CLIENT, body({ event_id: 'evt-v3-000008', apartment_id: 99, kind: 'resident' }), { writeDoorLog: door.fn });
    assert.deepEqual(fake.find(/^INSERT INTO plate_events/)[0].params.slice(14, 17), [null, null, null], 'baska sitenin dairesi ipucu olarak KABUL EDILMEZ');
    fake = eventPool({ vehicle: null, permit: null, hintApartment: 8 });
    await recordEdgeEvent(CLIENT, body({ event_id: 'evt-v3-000009', schema_version: 2, apartment_id: 8, kind: 'resident', gate_command: 'accepted' }), { writeDoorLog: door.fn });
    assert.deepEqual(fake.find(/^INSERT INTO plate_events/)[0].params.slice(14), [null, null, null, null], 'v2 istemcinin v3 alanlari yok sayilir');
  });

  it('kapi gunlugu yazilamazsa olay yine kaydolur ve yanit bozulmaz', async () => {
    eventPool();
    const out = await recordEdgeEvent(CLIENT, body({ event_id: 'evt-v3-000010' }), { writeDoorLog: async () => { throw new Error('gunluk bozuk'); } });
    assert.equal(out.ok, true);
  });
});

// --- Senkron + canlı akış -------------------------------------------------------------------------------------------------------------

describe('syncEdge (sürüm 3) ve canlı akış satırları', () => {
  after(uninstallFakePool);
  beforeEach(() => mock.method(console, 'error', () => {}));

  const syncPool = (cameraPassword = 'Kam-Parola-1') =>
    installFakePool([
      [/^SELECT NOW\(\) AS now/, () => ok([{ now: new Date('2026-10-29T12:00:00Z') }])],
      siteSettingsRow(null),
      [/FROM camera_devices c LEFT JOIN plate_gate_cameras gc ON gc\.camera_id = c\.id WHERE c\.site_code = \$1 AND c\.is_active AND c\.rtsp_url IS NOT NULL/, () => ok([
        { id: 11, name: 'Giriş', brand: 'hikvision', host: '192.168.1.64', port: null, rtsp_url: 'rtsp://192.168.1.64/Streaming/Channels/101', username: 'admin', password_enc: encryptSecret(cameraPassword), gate_id: 3, direction: 'giris' },
        { id: 12, name: 'Parolasiz', brand: 'onvif', host: '10.0.0.9', port: 8554, rtsp_url: 'rtsp://10.0.0.9:8554/live', username: null, password_enc: null, gate_id: null, direction: null },
      ])],
      [/FROM vehicles v/, () => ok([{ plate: '34ABC123', vehicle_id: 1, apartment_id: 5, block_name: 'A', unit_label: '5', person_name: 'Ali Yılmaz' }, { plate: '06XYZ99', vehicle_id: 2, apartment_id: null, block_name: null, unit_label: null, person_name: null }])],
      [/FROM plate_guest_permits p/, () => ok([{ id: 3, plate: '34MIS222', apartment_id: 5, block_name: 'A', unit_label: '5', valid_from: new Date('2026-10-29T10:00:00Z'), valid_until: new Date('2026-10-30T10:00:00Z') }])],
    ]);

  it('v3 istemci: kamera tanimlari (parola cozulmus) + kimlik etiketleri + goruntu araliklari; v2 istemciye kamera / parola inmez', async () => {
    syncPool();
    const v3 = await syncEdge(CLIENT, { schema_version: '3' });
    assert.deepEqual(v3.config.cameras[0], { camera_id: 11, name: 'Giriş', brand: 'hikvision', host: '192.168.1.64', port: null, rtsp_url: 'rtsp://192.168.1.64/Streaming/Channels/101', username: 'admin', password: 'Kam-Parola-1', gate_id: 3, direction: 'giris' });
    assert.equal(v3.config.cameras[1].password, null);
    assert.equal(v3.config.cameras[1].direction, null);
    assert.deepEqual([v3.config.settings.snapshot_interval_seconds, v3.config.settings.snapshot_idle_interval_seconds], [4, 15]);
    assert.deepEqual(v3.vehicles.items[0], { plate: '34ABC123', vehicle_id: 1, apartment_id: 5, apartment_label: 'A - 5', person_label: 'Ali Y.' });
    assert.deepEqual([v3.vehicles.items[1].apartment_label, v3.vehicles.items[1].person_label], [null, null]);
    assert.equal(v3.guest_permits.items[0].apartment_label, 'A - 5');
    assert.equal(v3.schema_version, 3);
    syncPool();
    const v2 = await syncEdge(CLIENT, { schema_version: '2' });
    assert.deepEqual(v2.config.cameras, []);
    assert.ok(!JSON.stringify(v2).includes('Kam-Parola-1'), 'sir gereksiz yere tasinmaz');
  });

  it('loadEdgeCameras: cozulemeyen parola null (kenar parolasiz dener, durust hata verir)', async () => {
    installFakePool([[/FROM camera_devices c LEFT JOIN plate_gate_cameras/, () => ok([{ id: 1, name: 'K', brand: 'onvif', host: 'h', port: null, rtsp_url: 'rtsp://h/x', username: 'u', password_enc: 'v1:bozuk:bozuk:bozuk', gate_id: null, direction: null }])]]);
    const cams = await loadEdgeCameras(pool, SITE);
    assert.equal(cams[0].password, null);
  });

  const feedRows = [
    { id: '12', plate: '34ABC123', decision: 'ALLOWED', decision_kind: 'acildi', gate_command: 'accepted', identity_kind: 'resident', block_name: 'A', unit_label: '5', person_name: 'Ali Yılmaz', direction: 'giris', reason: 'resident', confidence: '0.97', auto_action: 'none', decided_at: new Date(), seen_at: new Date(), device_name: 'Kamera 1', door_name: 'Ana Giriş' },
    { id: '11', plate: '06XYZ99', decision: 'DENIED', decision_kind: 'red', gate_command: 'failed', identity_kind: 'guest', block_name: 'B', unit_label: '2', person_name: 'Gizli Kisi', direction: 'cikis', reason: 'denied', confidence: null, auto_action: 'none', decided_at: new Date(), seen_at: new Date(), device_name: null, door_name: null },
    { id: '10', plate: '35DEF456', decision: 'UNKNOWN', decision_kind: 'tanimsiz', gate_command: null, identity_kind: null, block_name: null, unit_label: null, person_name: null, direction: null, reason: 'not_registered', confidence: null, auto_action: 'none', decided_at: new Date(), seen_at: null, device_name: null, door_name: null },
    { id: '9', plate: '16KLM777', decision: 'ALLOWED', decision_kind: 'acildi', gate_command: null, identity_kind: 'resident', block_name: 'A', unit_label: '1', person_name: 'Eski Kayit', direction: 'giris', reason: 'resident', confidence: null, auto_action: 'none', decided_at: new Date(), seen_at: new Date(), device_name: null, door_name: null },
  ];

  it('canli akis: yazma yetkisinde kimlik ("Ali Y." + daire) ve kapi durumu; misafirde kisi adi yok; tanimsizda yalniz plaka; eski kayitta acildi = tetiklendi', async () => {
    const fake = installFakePool([[/FROM plate_decisions d/, () => ok(feedRows)], [/FROM plate_presence WHERE site_code = \$1 AND inside/, () => ok([{ n: 3 }])]]);
    const out = await listDecisions(SITE, { live: '1' }, { canWrite: true });
    const [a, b, c, d] = out.events;
    assert.deepEqual(a.identity, { kind: 'resident', apartment_label: 'A - 5', person_label: 'Ali Y.' });
    assert.equal(a.gate_state, 'triggered');
    assert.deepEqual(b.identity, { kind: 'guest', apartment_label: 'B - 2', person_label: null });
    assert.equal(b.gate_state, 'no_response');
    assert.deepEqual([c.identity, c.gate_state], [null, null]);
    assert.equal(d.gate_state, 'triggered');
    assert.ok(!JSON.stringify(b).includes('Gizli'), 'misafirde kisi adi hic donmez');
    assert.match(fake.find(/FROM plate_decisions d/)[0].sql, /LEFT JOIN apartments aa ON aa\.id = e\.apartment_id AND aa\.site_code = d\.site_code/);
    const reader = await listDecisions(SITE, { live: '1' }, { canWrite: false });
    assert.ok(reader.events.every((e) => e.identity === null), 'kurul / gorevli kisi ve daire gormez');
    assert.deepEqual(reader.events.map((e) => e.gate_state), ['triggered', 'no_response', null, 'triggered'], 'kapi durumu kisisel veri degildir');
    assert.ok(!JSON.stringify(reader).includes('Ali'));
  });
});
