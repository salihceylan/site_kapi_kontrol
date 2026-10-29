// Plaka Tanıma A3 (121): şema <-> migration eşliği, sözleşme sürüm 2 (kara_liste), bildirim metinleri (Türkçe ek uyumu), kopukluk değerlendirmesi,
// sakin bildirimi / yönetici uyarısı (sahte db + sahte push), zamanlayıcı tur mantığı. DB'siz; gerçek SQL için plate_gates_pg.test.js (PLATE_GATES_PG_URL).
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { DEFAULT_MIGRATIONS_DIR, findUnsafeStatements } from '../scripts/migrate.js';
import { PLATE_ALERTS_DDL, PLATE_ALERTS_DDL_ORDER, ensurePlateAlertsSchema, plateAlertsTuning } from '../src/modules/plate_alerts_schema.js';
import {
  DECISION_KINDS,
  DECISION_TO_LEGACY,
  DEFAULT_SITE_SETTINGS,
  SETTING_RANGES,
  SUPPORTED_SCHEMA_VERSIONS,
  mergeSettings,
  parseEdgeEvent,
  parseSettingsInput,
  presenceTransition,
} from '../src/modules/plate_gates_common.js';
import { clockSuffix, locativeSuffix, lostAlertTexts, lostComponents, movementTexts } from '../src/modules/plate_alerts_common.js';
import { checkEdgeHealth, notifyResidentMovement } from '../src/modules/plate_notify.js';
import { pushDeviceHooks } from '../src/modules/push_devices.js';
import { runPlateHealthTick } from '../src/modules/plate_health_scheduler.js';
import { SITE_AUDIT_LABELS } from '../src/modules/site_audit_log_catalog.js';

plateAlertsTuning.retryDelayMs = 1;
const here = path.dirname(fileURLToPath(import.meta.url));
const MIGRATION = readFileSync(path.join(DEFAULT_MIGRATIONS_DIR, '121_plate_a3_alerts.sql'), 'utf8').replace(/\r\n/g, '\n');
const DB_SOURCE = readFileSync(path.join(here, '..', 'src', 'db.js'), 'utf8');
const normalize = (text) => text.replace(/--.*$/gm, ' ').replace(/\s+/g, ' ').trim();
const listOf = (items) => items.map((v) => `'${v}'`).join(', ');

describe('plate_alerts_schema (121)', () => {
  it('migration, DDL ile ayni ifadeler ve ayni sirada; tek DROP yalniz korumali CHECK genisletme', () => {
    const actual = normalize(MIGRATION);
    let cursor = 0;
    for (const name of PLATE_ALERTS_DDL_ORDER) {
      const statement = normalize(PLATE_ALERTS_DDL[name]);
      const at = actual.indexOf(statement, cursor);
      assert.ok(at >= cursor, `sirasiz ya da eksik: ${name}`);
      cursor = at + statement.length;
    }
    assert.equal((actual.match(/\bDROP\b/g) ?? []).length, 1);
    assert.ok(actual.includes("DROP CONSTRAINT IF EXISTS chk_plate_events_decision_kind"));
    assert.ok(!/\b(TRUNCATE)\b|; ?(DELETE|UPDATE) /i.test(actual));
    assert.deepEqual(findUnsafeStatements(MIGRATION), []);
  });

  it('karar turu CHECK listesi ve site ayari varsayilanlari sabitlerle ayni', () => {
    const sql = normalize(MIGRATION);
    assert.ok(sql.includes(`decision_kind IN (${listOf(DECISION_KINDS)})`));
    for (const field of ['inside_report_hours', 'inside_timeout_hours', 'alert_interval_minutes', 'resident_notify_max_age_minutes']) {
      assert.ok(sql.includes(`${field} INTEGER NOT NULL DEFAULT ${DEFAULT_SITE_SETTINGS[field]}`), field);
      const [min, max] = SETTING_RANGES[field];
      assert.ok(sql.includes(`${field} BETWEEN ${min} AND ${max}`), `${field} araligi`);
    }
    assert.ok(sql.includes('movement_enabled BOOLEAN NOT NULL DEFAULT FALSE'), 'sakin bildirimi varsayilan KAPALI');
  });

  it('db.js ensurePlateAlertsSchema cagirir (ensurePlateGatesSchema sonrasi)', () => {
    assert.ok(DB_SOURCE.includes("import { ensurePlateAlertsSchema } from './modules/plate_alerts_schema.js'"));
    assert.ok(DB_SOURCE.indexOf('await ensurePlateAlertsSchema(client)') > DB_SOURCE.indexOf('await ensurePlateGatesSchema(client)'));
  });

  it('her sey varsa tek katalog sorgusu; eksikse (ya da CHECK genislemediyse) tum ifadeler; ust tablo yoksa hicbir sey', async () => {
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
    const parents = ['sites', 'plate_events', 'plate_presence', 'plate_site_settings'];
    const tables = [...parents, 'plate_alert_state', 'plate_notify_prefs'];
    const columns = ['inside_report_hours', 'inside_timeout_hours', 'alert_interval_minutes', 'resident_notify_max_age_minutes'].map((c) => `plate_site_settings.${c}`);
    const full = make({ tables, indexes: ['idx_plate_presence_since'], columns, widened: true });
    await ensurePlateAlertsSchema(full);
    assert.equal(full.calls.length, 1);
    const notWidened = make({ tables, indexes: ['idx_plate_presence_since'], columns, widened: false });
    await ensurePlateAlertsSchema(notWidened);
    assert.equal(notWidened.calls.length, 1 + 1 + PLATE_ALERTS_DDL_ORDER.length + 1);
    assert.match(notWidened.calls.at(-1), /RESET lock_timeout/);
    const noParent = make({ tables: ['plate_events'], indexes: [], columns: [], widened: false });
    await ensurePlateAlertsSchema(noParent);
    assert.equal(noParent.calls.length, 1);
  });
});

describe('sozlesme surum 2: kara_liste karari ve yeni site ayari', () => {
  const NOW = Date.parse('2026-10-29T12:00:00Z');
  const base = { event_id: 'evt-0000001', camera_id: 7, plate: '34 abc 123', decision: 'kara_liste', seen_at: '2026-10-29T11:59:00Z' };

  it('kara_liste yalniz surum 2+ ile kabul edilir; surum 1 ve surumsuz istek reddedilir; 4 desteklenmez', () => {
    assert.deepEqual([...SUPPORTED_SCHEMA_VERSIONS], [1, 2, 3]);
    assert.equal(parseEdgeEvent({ ...base, schema_version: 2 }, NOW).decision, 'kara_liste');
    assert.equal(parseEdgeEvent({ ...base, schema_version: 3 }, NOW).decision, 'kara_liste');
    for (const bad of [{ schema_version: 1 }, {}]) assert.throws(() => parseEdgeEvent({ ...base, ...bad }, NOW), (e) => e.statusCode === 400, JSON.stringify(bad));
    assert.throws(() => parseEdgeEvent({ ...base, schema_version: 4 }, NOW), (e) => e.code === 'UNSUPPORTED_SCHEMA');
    assert.equal(parseEdgeEvent({ ...base, decision: 'red', schema_version: 1 }, NOW).decision, 'red', 'eski istemci calismaya devam eder');
  });

  it('kara_liste iceri almaz/dusurmez ve eski Olaylar akisinda DENIED', () => {
    for (const direction of ['giris', 'cikis']) assert.equal(presenceTransition({ direction, decision: 'kara_liste' }), 'none');
    assert.equal(DECISION_TO_LEGACY.kara_liste, 'DENIED');
  });

  it('site ayari: yeni alanlar araliklidir; zaman asimi rapor esiginden buyuk olmali', () => {
    assert.equal(parseSettingsInput({ inside_report_hours: 6, inside_timeout_hours: 48 }).inside_timeout_hours, 48);
    for (const bad of [{ inside_report_hours: 0 }, { inside_timeout_hours: 1 }, { alert_interval_minutes: 4 }, { resident_notify_max_age_minutes: 1441 }]) {
      assert.throws(() => parseSettingsInput(bad), (e) => e.statusCode === 400, JSON.stringify(bad));
    }
    assert.throws(() => mergeSettings({}, { inside_report_hours: 30 }), (e) => e.statusCode === 400, 'varsayilan zaman asimi 24 < rapor 30');
    assert.equal(mergeSettings({}, { inside_report_hours: 6, inside_timeout_hours: 12 }).inside_timeout_hours, 12);
  });

  it('denetim katalogu yeni eylemlere Turkce baslik verir', () => {
    assert.match(SITE_AUDIT_LABELS['plate.edge_disconnected'], /koptu/);
    assert.match(SITE_AUDIT_LABELS['plate.inside_timeout'], /zaman aşımı/);
  });
});

describe('bildirim metinleri', () => {
  it("Turkce bulunma eki okunusa gore: 18:32'de, 18:30'da, 18:05'te, 18:40'ta, 19:00'da, 18:00'de", () => {
    assert.equal(locativeSuffix(2), 'de');
    assert.equal(locativeSuffix(30), 'da');
    assert.equal(locativeSuffix(5), 'te');
    assert.equal(locativeSuffix(40), 'ta');
    assert.equal(clockSuffix(19, 0), 'da');
    assert.equal(clockSuffix(18, 0), 'de');
    assert.equal(clockSuffix(10, 0), 'da');
    assert.equal(clockSuffix(23, 0), 'te');
  });

  it('sakin bildirimi Istanbul saatiyle yazilir, plaka icermez', () => {
    const entry = movementTexts({ direction: 'giris', seenAt: new Date('2026-10-29T15:32:00Z') });
    assert.deepEqual(entry, { title: 'Aracınız giriş yaptı', body: "Aracınız 18:32'de giriş yaptı." });
    assert.equal(movementTexts({ direction: 'cikis', seenAt: new Date('2026-10-29T15:05:00Z') }).body, "Aracınız 18:05'te çıkış yaptı.");
  });

  it('kopukluk: hic haber vermemis bilesen uyari sebebi degil; kirmizi esik asilinca listelenir; metin uc adla sinirli', () => {
    const nowMs = Date.parse('2026-10-29T12:00:00Z');
    const lost = lostComponents({
      edgeClients: [{ name: 'Kulübe PC', last_seen_at: '2026-10-29T11:40:00Z' }, { name: 'Yeni PC', last_seen_at: null }, { name: 'Taze PC', last_seen_at: '2026-10-29T11:59:30Z' }],
      cameras: [
        { name: 'Giriş', reported_at: '2026-10-29T11:00:00Z', last_frame_at: '2026-10-29T11:50:00Z' },
        { name: 'Çıkış', reported_at: null, last_frame_at: null },
        { name: 'Taze', reported_at: '2026-10-29T11:59:00Z', last_frame_at: '2026-10-29T11:59:50Z' },
      ],
      critSeconds: 600,
      nowMs,
    });
    assert.deepEqual([lost.edge.map((x) => x.name), lost.cameras.map((x) => x.name), lost.any], [['Kulübe PC'], ['Giriş'], true]);
    assert.equal(lostComponents({ edgeClients: [], cameras: [], critSeconds: 600, nowMs }).any, false);
    const many = lostAlertTexts({ edge: [], cameras: ['a', 'b', 'c', 'd', 'e'].map((name) => ({ name })) });
    assert.match(many.body, /Kamera: a, b, c \+2/);
  });
});

/** query(sql, params) -> eslesen ilk yolun satirlari; yol islevse cagri sirasina gore deger doner. */
function fakeDb(routes) {
  const log = [];
  return {
    log,
    async query(sql, params) {
      log.push({ sql: String(sql), params });
      for (const [pattern, rows] of routes) {
        if (pattern.test(sql)) return { rows: typeof rows === 'function' ? rows(params) : rows };
      }
      return { rows: [] };
    },
  };
}

function capturePush(t) {
  const sent = [];
  const original = { available: pushDeviceHooks.available, client: pushDeviceHooks.client };
  pushDeviceHooks.available = () => true;
  pushDeviceHooks.client = () => ({ send: async (message) => (sent.push(message), { kind: 'ok' }) });
  t.after(() => Object.assign(pushDeviceHooks, original));
  return sent;
}

describe('sakin bildirimi ve yonetici uyarisi (sahte db + sahte push)', () => {
  const vehicle = { id: 1, person_id: 5, apartment_id: 9 };

  it('eski olay (site ayari yasi) ve tercihi kapali sakin icin gonderilmez; acik tercihte metin gider', async (t) => {
    const sent = capturePush(t);
    const stale = await notifyResidentMovement({ siteCode: 1, vehicle, direction: 'giris', seenAt: new Date(Date.now() - 3_600_000) }, fakeDb([]));
    assert.deepEqual(stale, { skipped: 'stale' });
    const closed = fakeDb([[/FROM site_people/, [{ user_code: 7 }]]]);
    assert.deepEqual(await notifyResidentMovement({ siteCode: 1, vehicle, direction: 'giris', seenAt: new Date() }, closed), { skipped: 'no_opt_in' });
    assert.equal(sent.length, 0);
    const open = fakeDb([[/FROM site_people/, [{ user_code: 7 }]], [/FROM plate_notify_prefs/, [{ user_code: 7 }]], [/FROM push_devices/, [{ fcm_token: 'T1' }]]]);
    const seenAt = new Date();
    const result = await notifyResidentMovement({ siteCode: 1, vehicle, direction: 'cikis', seenAt }, open);
    assert.equal(result.recipients, 1);
    assert.equal(result.fcm, 1);
    assert.equal(sent[0].notification.body, movementTexts({ direction: 'cikis', seenAt }).body);
    assert.equal(sent[0].data.type, 'plate_movement');
  });

  it('kopukluk uyarisi saatte en cok bir kez (sinirlayici atomik talep) ve yoneticilere gider', async (t) => {
    const sent = capturePush(t);
    let claims = 0;
    const db = fakeDb([
      [/FROM plate_edge_clients/, [{ name: 'Kulübe PC', last_seen_at: new Date(Date.now() - 3_600_000) }]],
      [/INSERT INTO plate_alert_state/, () => (claims++ === 0 ? [{ ok: 1 }] : [])],
      [/FROM users u/, [{ user_code: 3 }]],
      [/FROM push_devices/, [{ fcm_token: 'M1' }]],
    ]);
    assert.deepEqual(await checkEdgeHealth(db, 1), { lost: true, alerted: true });
    assert.deepEqual(await checkEdgeHealth(db, 1), { lost: true, alerted: false });
    assert.equal(sent.length, 1);
    assert.equal(sent[0].data.type, 'plate_edge_lost');
    const audits = db.log.filter((c) => /INSERT INTO audit_log/.test(c.sql));
    assert.equal(audits.length, 1);
    assert.equal(audits[0].params[3], 'plate.edge_disconnected');
    const healthy = fakeDb([[/FROM plate_edge_clients/, [{ name: 'PC', last_seen_at: new Date() }]]]);
    assert.deepEqual(await checkEdgeHealth(healthy, 1), { lost: false, alerted: false });
  });
});

describe('plate_health_scheduler: tur mantigi', () => {
  it('modulu kapali site atlanir, bir sitenin hatasi digerini durdurmaz; zaman asimi bakimi her turda calisir', async () => {
    const checked = [];
    const hooks = {
      listSites: async () => [1, 2, 3],
      moduleEnabled: async (site) => site !== 2,
      checkEdgeHealth: async (site) => {
        if (site === 1) throw new Error('bozuk');
        checked.push(site);
        return { lost: true, alerted: true };
      },
      expireStalePresence: async () => 4,
      housekeeping: async () => ({ snapshotsRemoved: 3, commandsExpired: 2 }),
    };
    const originalError = console.error;
    console.error = () => {};
    try {
      assert.deepEqual(await runPlateHealthTick({ hooks }), { sites: 2, alerted: 1, expired: 4, snapshotsRemoved: 3, commandsExpired: 2 });
      // Eski kanca takimi (housekeeping yok) ve bakim hatasi turu DUSURMEZ.
      const legacy = { ...hooks };
      delete legacy.housekeeping;
      assert.deepEqual(await runPlateHealthTick({ hooks: legacy }), { sites: 2, alerted: 1, expired: 4, snapshotsRemoved: 0, commandsExpired: 0 });
      const broken = await runPlateHealthTick({ hooks: { ...hooks, housekeeping: async () => { throw new Error('bozuk'); } } });
      assert.equal(broken.expired, 4);
      assert.equal(broken.snapshotsRemoved, 0);
    } finally {
      console.error = originalError;
    }
    assert.deepEqual(checked, [3, 3, 3]);
  });
});
