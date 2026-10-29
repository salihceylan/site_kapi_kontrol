// Plaka Tanıma A1 (120): şema <-> migration eşliği, CHECK listesi <-> sabit eşliği, saf kural mantığı (misafir kabulü, yön, içeride geçişi, rozet eşikleri),
// kenar istemci sözleşmesi doğrulayıcıları (sürüm, idempotent kimlik, ek alanlar yok sayılır) ve anahtar yardımcıları. DB'siz; gerçek SQL için plate_gates_pg.test.js.
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { DEFAULT_MIGRATIONS_DIR, findUnsafeStatements } from '../scripts/migrate.js';
import { PLATE_GATES_DDL, PLATE_GATES_DDL_ORDER, ensurePlateGatesSchema, plateGatesTuning } from '../src/modules/plate_gates_schema.js';
import {
  CAMERA_DIRECTIONS,
  DECISION_KINDS_V1,
  DEFAULT_SITE_SETTINGS,
  DIRECTION_MODES,
  GUEST_RULES,
  PRESENCE_KINDS,
  assertCameraDirections,
  edgeKeyFromHeaders,
  edgeKeyMatches,
  evaluateGuestAdmission,
  healthOf,
  mergeSettings,
  newEdgeSecret,
  parseEdgeEvent,
  parseEdgeKey,
  parseGateInput,
  parseHeartbeat,
  parseSyncQuery,
  presenceTransition,
  resolveDirection,
  revisionOf,
  worstBadge,
} from '../src/modules/plate_gates_common.js';

plateGatesTuning.retryDelayMs = 1;
const here = path.dirname(fileURLToPath(import.meta.url));
const MIGRATION = readFileSync(path.join(DEFAULT_MIGRATIONS_DIR, '120_plate_gates_edge.sql'), 'utf8').replace(/\r\n/g, '\n');
const DB_SOURCE = readFileSync(path.join(here, '..', 'src', 'db.js'), 'utf8');
const normalize = (text) => text.replace(/--.*$/gm, ' ').replace(/\s+/g, ' ').trim();
const listOf = (items) => items.map((v) => `'${v}'`).join(', ');

describe('plate_gates_schema (120)', () => {
  it('migration, DDL ile ayni ifadeler ve ayni sirada; ekleyici (DROP/DELETE/UPDATE yok)', () => {
    const actual = normalize(MIGRATION);
    let cursor = 0;
    for (const name of PLATE_GATES_DDL_ORDER) {
      const statement = normalize(PLATE_GATES_DDL[name]);
      const at = actual.indexOf(statement, cursor);
      assert.ok(at >= cursor, `sirasiz ya da eksik: ${name}`);
      cursor = at + statement.length;
    }
    assert.ok(!/\b(DROP|TRUNCATE)\b|; ?(DELETE|UPDATE) /i.test(actual));
    assert.deepEqual(findUnsafeStatements(MIGRATION), []);
  });

  it('CHECK listeleri sabitlerle ayni (yeni deger = tek migration + bir sabit satiri)', () => {
    const sql = normalize(MIGRATION);
    assert.ok(sql.includes(`direction_mode IN (${listOf(DIRECTION_MODES)})`));
    assert.ok(sql.includes(`CHECK (direction IN (${listOf(CAMERA_DIRECTIONS)}))`));
    assert.ok(sql.includes(`decision_kind IN (${listOf(DECISION_KINDS_V1)})`));
    assert.ok(sql.includes(`guest_rule IN (${listOf(GUEST_RULES)})`));
    assert.ok(sql.includes(`kind IN (${listOf(PRESENCE_KINDS)})`));
    assert.ok(sql.includes(`guest_rule TEXT NOT NULL DEFAULT '${DEFAULT_SITE_SETTINGS.guest_rule}'`));
    assert.ok(sql.includes(`heartbeat_warn_seconds INTEGER NOT NULL DEFAULT ${DEFAULT_SITE_SETTINGS.heartbeat_warn_seconds}`));
    assert.ok(sql.includes(`heartbeat_crit_seconds INTEGER NOT NULL DEFAULT ${DEFAULT_SITE_SETTINGS.heartbeat_crit_seconds}`));
  });

  it('db.js ensurePlateGatesSchema cagirir (ensureMessagingSchema sonrasi)', () => {
    assert.ok(DB_SOURCE.includes("import { ensurePlateGatesSchema } from './modules/plate_gates_schema.js'"));
    assert.ok(DB_SOURCE.indexOf('await ensurePlateGatesSchema(client)') > DB_SOURCE.indexOf('await ensureMessagingSchema(client)'));
  });

  it('her sey varsa tek katalog sorgusu; eksikse tum ifadeler sirayla; kilit zaman asimi sifirlanir; ust tablo yoksa hicbir sey', async () => {
    const make = (row) => {
      const calls = [];
      return {
        calls,
        async query(sql) {
          calls.push(String(sql).trim().slice(0, 30));
          return /unnest/.test(sql) ? { rows: [row] } : { rows: [] };
        },
      };
    };
    const tables = ['plate_gates', 'plate_gate_cameras', 'plate_edge_clients', 'plate_camera_status', 'plate_site_settings', 'plate_presence', 'sites', 'plate_events', 'apartments'];
    const indexes = ['uq_plate_gates_name', 'uq_plate_gate_cameras_camera', 'idx_plate_gate_cameras_gate', 'idx_plate_edge_clients_site', 'idx_plate_camera_status_site', 'uq_plate_presence_plate', 'idx_plate_presence_inside', 'idx_plate_presence_updated', 'uq_plate_events_client_event'];
    const columns = ['gate_id', 'direction', 'decision_kind', 'edge_client_id', 'client_event_id', 'schema_version', 'confidence', 'reason'].map((c) => `plate_events.${c}`).concat('apartments.parking_slots');
    const full = make({ tables, indexes, columns });
    await ensurePlateGatesSchema(full);
    assert.equal(full.calls.length, 1);
    const missing = make({ tables, indexes: [], columns: [] });
    await ensurePlateGatesSchema(missing);
    assert.equal(missing.calls.length, 1 + 1 + PLATE_GATES_DDL_ORDER.length + 1);
    assert.match(missing.calls[1], /SET lock_timeout/);
    assert.match(missing.calls.at(-1), /RESET lock_timeout/);
    const noParent = make({ tables: ['plate_gates'], indexes: [], columns: [] });
    await ensurePlateGatesSchema(noParent);
    assert.equal(noParent.calls.length, 1);
  });
});

describe('plate_gates_common: kural mantigi', () => {
  it('misafir kabulu: park yeri >= 1 ve kural (sahibin sozu: tum yerler bos); tek parametreyle degisir', () => {
    assert.deepEqual(evaluateGuestAdmission({ parkingSlots: 0, insideCount: 0 }), { allowed: false, reason: 'no_parking' });
    assert.equal(evaluateGuestAdmission({ parkingSlots: 1, insideCount: 0 }).allowed, true);
    assert.equal(evaluateGuestAdmission({ parkingSlots: 1, insideCount: 1 }).allowed, false);
    // 2 yerli dairede 1 arac iceride: varsayilan kuralda REDDEDILIR; "en az bir bos" kuralinda kabul edilir.
    assert.equal(evaluateGuestAdmission({ parkingSlots: 2, insideCount: 1 }).allowed, false);
    assert.equal(evaluateGuestAdmission({ parkingSlots: 2, insideCount: 1, rule: 'en_az_bir_bos' }).allowed, true);
    assert.equal(evaluateGuestAdmission({ parkingSlots: 2, insideCount: 2, rule: 'en_az_bir_bos' }).allowed, false);
    assert.equal(evaluateGuestAdmission({ parkingSlots: 2, insideCount: 1, rule: 'bilinmeyen' }).allowed, false, 'bilinmeyen kural en siki olana duser');
  });

  it('yon: kapi/kamera kesinse o; cift yonde bildirilen; yoksa icerideki durumdan', () => {
    assert.equal(resolveDirection({ gateMode: 'giris', cameraDirection: 'cikis', declared: 'cikis' }), 'giris');
    assert.equal(resolveDirection({ gateMode: 'cift', cameraDirection: 'cikis' }), 'cikis');
    assert.equal(resolveDirection({ gateMode: 'cift', cameraDirection: 'auto', declared: 'cikis' }), 'cikis');
    assert.equal(resolveDirection({ gateMode: 'cift', cameraDirection: 'auto', inside: true }), 'cikis');
    assert.equal(resolveDirection({ gateMode: null, inside: false }), 'giris');
  });

  it('iceride gecisi: giris yalniz acildi ile isaretler; cikis acildi/tanimsiz ile duser; red degistirmez', () => {
    assert.equal(presenceTransition({ direction: 'giris', decision: 'acildi' }), 'enter');
    assert.equal(presenceTransition({ direction: 'giris', decision: 'tanimsiz' }), 'none');
    assert.equal(presenceTransition({ direction: 'giris', decision: 'red' }), 'none');
    assert.equal(presenceTransition({ direction: 'cikis', decision: 'acildi' }), 'leave');
    assert.equal(presenceTransition({ direction: 'cikis', decision: 'tanimsiz' }), 'leave');
    assert.equal(presenceTransition({ direction: 'cikis', decision: 'red' }), 'none');
  });

  it('rozet: esikler site ayari (varsayilan 3 dk sari, 10 dk kirmizi); hic haber yoksa hic baglanmadi; kapi en kotu bilesen', () => {
    const th = { warn: DEFAULT_SITE_SETTINGS.heartbeat_warn_seconds, crit: DEFAULT_SITE_SETTINGS.heartbeat_crit_seconds };
    assert.deepEqual(healthOf(null, th), { state: 'hic_baglanmadi', color: 'gri' });
    assert.deepEqual(healthOf(179, th), { state: 'calisiyor', color: 'yesil' });
    assert.deepEqual(healthOf(180, th), { state: 'calisiyor', color: 'sari' });
    assert.deepEqual(healthOf(600, th), { state: 'koptu', color: 'kirmizi' });
    assert.deepEqual(healthOf(60, { warn: 30, crit: 90 }), { state: 'calisiyor', color: 'sari' });
    const green = healthOf(1, th);
    assert.equal(worstBadge([green, healthOf(300, th)]).color, 'sari');
    assert.equal(worstBadge([green, healthOf(900, th), healthOf(300, th)]).color, 'kirmizi');
    assert.equal(worstBadge([]).state, 'hic_baglanmadi');
    assert.throws(() => mergeSettings({}, { heartbeat_warn_seconds: 300, heartbeat_crit_seconds: 300 }), (e) => e.code === 'INVALID_BODY');
  });
});

describe('plate_gates_common: girdi ve sozlesme', () => {
  const NOW = Date.parse('2026-10-29T12:00:00Z');
  const base = { event_id: 'evt-0000001', camera_id: 7, plate: '34 abc 123', decision: 'acildi', seen_at: '2026-10-29T11:59:00Z' };

  it('olay: biçim normalize edilir, bilinmeyen ek alanlar yok sayilir, sürüm yoksa 1', () => {
    const e = parseEdgeEvent({ ...base, gelecekte_eklenen: 1, confidence: 91 }, NOW);
    assert.equal(e.plate, '34ABC123');
    assert.equal(e.schemaVersion, 1);
    assert.equal(e.confidence, 0.91);
    assert.equal(e.direction, null);
    assert.equal(e.reason, null);
  });

  it('olay: desteklenmeyen surum -> UNSUPPORTED_SCHEMA (supported listesiyle); gecersiz kimlik/karar/yon/zaman 400', () => {
    assert.throws(() => parseEdgeEvent({ ...base, schema_version: 4 }, NOW), (e) => e.code === 'UNSUPPORTED_SCHEMA' && e.extra.supported[0] === 1);
    for (const bad of [{ event_id: 'kisa' }, { decision: 'belki' }, { direction: 'yan' }, { camera_id: 0 }, { plate: 'XX' }, { seen_at: '2020-01-01T00:00:00Z' }, { seen_at: '2026-10-29T13:00:00Z' }]) {
      assert.throws(() => parseEdgeEvent({ ...base, ...bad }, NOW), (e) => e.statusCode === 400, JSON.stringify(bad));
    }
  });

  it('kalp atisi ve senkron sorgusu: kamera listesi tekillesir; updated_since ve bolum ozeti dogrulanir', () => {
    const beat = parseHeartbeat({ app_version: '1.0.0 beta!', queue_depth: 3, cameras: [{ camera_id: 1, last_frame_at: '2026-10-29T11:59:00Z' }, { camera_id: 1 }, { camera_id: 2 }] });
    assert.equal(beat.cameras.length, 2);
    assert.equal(beat.appVersion, '1.0.0beta');
    assert.throws(() => parseHeartbeat({ cameras: [{ camera_id: 1, last_frame_at: 'dun' }] }), (e) => e.statusCode === 400);
    const q = parseSyncQuery({ updated_since: '2026-10-29T11:00:00Z', vehicles_rev: 'abcdef0123456789', permits_rev: 'zz' }, NOW);
    assert.equal(q.since.toISOString(), '2026-10-29T11:00:00.000Z');
    assert.equal(q.vehiclesRev, 'abcdef0123456789');
    assert.equal(q.permitsRev, null);
    assert.equal(parseSyncQuery({ updated_since: '2020-01-01T00:00:00Z' }, NOW).since, null, 'cok eski since tam senkron sayilir');
    assert.equal(revisionOf([{ a: 1 }]), revisionOf([{ a: 1 }]));
    assert.notEqual(revisionOf([{ a: 1 }]), revisionOf([{ a: 2 }]));
  });

  it('kapi girdisi: sinir yok (cok kamera), yon uyumu denetlenir, kopya kamera reddedilir', () => {
    const many = Array.from({ length: 60 }, (_, i) => ({ camera_id: i + 1, direction: i % 2 ? 'cikis' : 'giris' }));
    const gate = parseGateInput({ name: ' Ana  Kapı ', cameras: many });
    assert.equal(gate.name, 'Ana Kapı');
    assert.equal(gate.direction_mode, 'cift');
    assert.equal(gate.cameras.length, 60);
    assert.throws(() => assertCameraDirections('giris', [{ camera_id: 1, direction: 'cikis' }]), (e) => e.code === 'CAMERA_DIRECTION_CONFLICT');
    assert.doesNotThrow(() => assertCameraDirections('giris', [{ camera_id: 1, direction: 'auto' }, { camera_id: 2, direction: 'giris' }]));
    assert.throws(() => parseGateInput({ name: 'x', cameras: [{ camera_id: 1 }, { camera_id: 1 }] }), (e) => e.statusCode === 400);
    assert.throws(() => parseGateInput({ name: 'x', direction_mode: 'capraz' }), (e) => e.statusCode === 400);
    assert.deepEqual(parseGateInput({ is_active: false }, { partial: true }), { is_active: false });
  });

  it('kenar istemci anahtari: <id>.<48 hex>; yalniz ozet saklanir ve dogrulanir; ustbilgi okuma', () => {
    const { secret, hash } = newEdgeSecret();
    assert.notEqual(secret, hash);
    assert.equal(hash.length, 64);
    assert.deepEqual(parseEdgeKey(`12.${secret}`), { id: 12, secret });
    assert.equal(parseEdgeKey(`12.${secret}x`), null);
    assert.equal(edgeKeyMatches(secret, hash), true);
    assert.equal(edgeKeyMatches(secret.replace(/./, (c) => (c === 'a' ? 'b' : 'a')), hash), false);
    assert.equal(edgeKeyFromHeaders({ authorization: 'Bearer 1.abc' }), '1.abc');
    assert.equal(edgeKeyFromHeaders({ 'x-edge-key': '2.def' }), '2.def');
  });
});
