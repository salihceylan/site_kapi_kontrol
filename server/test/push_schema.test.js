// Telefon bildirimi (Faz 3b-B) şeması ve bağlantıları (DB'siz): migration 041 <-> push_schema.js aynı DDL (aynı sıra), EKLEMELİ / idempotent, sözleşme
// B2 sütun / kısıt / indeks ayrıntıları, açılış 40P01 dersi (DDL dev blokta DEĞİL; katalog kontrolüyle yalnız EKSİKLER), kaynak bağlantıları (yayın
// işleminde outbox, zamanlayıcı / rota tetikleri, server.js, hesap silme ve dışa aktarma kancaları). Gerçek PG: scripts/qa_platform_pg.mjs "push".
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { DEFAULT_MIGRATIONS_DIR, findUnsafeStatements, listMigrations } from '../scripts/migrate.js';
import { PUSH_DDL, PUSH_DDL_ORDER, PUSH_PREFERENCE_COLUMNS, ensurePushSchema, pushSchemaTuning } from '../src/modules/push_schema.js';
import { deletePushDataForUser, exportPushDevices, PUSH_EXPORT_EXCLUDED_NOTE } from '../src/modules/push_devices.js';
import { EXPORT_EXCLUDED } from '../src/modules/account_export_service.js';

pushSchemaTuning.retryDelayMs = 1;

const here = path.dirname(fileURLToPath(import.meta.url));
const read = (relative) => readFileSync(path.join(here, '..', relative), 'utf8').replace(/\r\n/g, '\n');
const MIGRATION = readFileSync(path.join(DEFAULT_MIGRATIONS_DIR, '041_push.sql'), 'utf8').replace(/\r\n/g, '\n');
const DB_SOURCE = read('src/db.js');

function normalizeSql(text) {
  return text
    .replace(/\/\*[\s\S]*?\*\//g, ' ')
    .replace(/--.*$/gm, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

/** Migration metnini üst düzey ifadelere böler ($$ gövdelerindeki ';' sayılmaz). */
function splitStatements(sqlText) {
  const text = sqlText.replace(/--.*$/gm, ' ');
  const statements = [];
  let current = '';
  let inDollar = false;
  for (let i = 0; i < text.length; i += 1) {
    if (text.startsWith('$$', i)) {
      inDollar = !inDollar;
      current += '$$';
      i += 1;
      continue;
    }
    if (text[i] === ';' && !inDollar) {
      if (current.trim() !== '') statements.push(normalizeSql(current));
      current = '';
      continue;
    }
    current += text[i];
  }
  if (current.trim() !== '') statements.push(normalizeSql(current));
  return statements;
}

describe('migration 041: telefon bildirimi', () => {
  it('041 var, tek, çalıştırıcı için güvenli (üst düzey BEGIN/COMMIT yok)', () => {
    const list = listMigrations(DEFAULT_MIGRATIONS_DIR);
    const entries = list.filter((m) => m.number === 41);
    assert.equal(entries.length, 1);
    assert.equal(entries[0].file, '041_push.sql');
    assert.deepEqual(findUnsafeStatements(MIGRATION), []);
  });

  it('push_schema.js PUSH_DDL migration 041 ile AYNI ifadeleri taşır (yorum / boşluk dışında birebir, AYNI sırayla)', () => {
    const fromMigration = splitStatements(MIGRATION);
    assert.equal(fromMigration.length, PUSH_DDL_ORDER.length);
    assert.deepEqual(fromMigration, PUSH_DDL_ORDER.map((name) => normalizeSql(PUSH_DDL[name])));
    assert.deepEqual(Object.keys(PUSH_DDL), [...PUSH_DDL_ORDER]);
  });

  it('EKLEMELİ ve idempotent: yalnız CREATE ... IF NOT EXISTS, notification_preferences\'a ADD COLUMN IF NOT EXISTS ve katalog korumalı NOT VALID CHECK; announcements / users DDL\'e uğramaz', () => {
    const statements = splitStatements(MIGRATION);
    for (const statement of statements) {
      assert.match(statement, /^(CREATE (UNIQUE )?(TABLE|INDEX) IF NOT EXISTS |ALTER TABLE notification_preferences ADD COLUMN IF NOT EXISTS |DO \$\$ BEGIN IF NOT EXISTS )/, statement.slice(0, 80));
    }
    const sql = normalizeSql(MIGRATION);
    assert.ok(!/\b(DROP|TRUNCATE|UPDATE|DELETE FROM|INSERT INTO)\b/i.test(sql));
    assert.ok(!/ALTER TABLE (users|announcements|sites)\b/i.test(sql));
    assert.match(sql, /ADD CONSTRAINT chk_notification_preferences_push_quiet CHECK \(push_quiet_start BETWEEN 0 AND 1439 AND push_quiet_end BETWEEN 0 AND 1439 AND push_quiet_start <> push_quiet_end\) NOT VALID/);
  });

  it('B2 ayrıntıları: push_devices (FK CASCADE, UNIQUE (user_code, install_id), tekil fcm_token, uzunluklar) ve push_outbox (user_code FK YOK, CHECK\'ler, UNIQUE (announcement_id, user_code), kısmi indeksler)', () => {
    const devices = normalizeSql(PUSH_DDL.devicesTable);
    for (const fragment of [
      'user_code INTEGER NOT NULL REFERENCES users(user_code) ON DELETE CASCADE',
      'notifications_enabled BOOLEAN NOT NULL DEFAULT TRUE',
      'failure_count SMALLINT NOT NULL DEFAULT 0',
      'last_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW()',
      'last_success_at TIMESTAMPTZ',
      'UNIQUE (user_code, install_id)',
      "CHECK (platform IN ('android', 'ios'))",
      'CHECK (char_length(install_id) BETWEEN 16 AND 64)',
      'CHECK (char_length(fcm_token) BETWEEN 20 AND 2048)', // tekil btree satir siniri (~2704 bayt): sozlesmedeki 4096'dan bilincli sapma
      'CHECK (app_version IS NULL OR char_length(app_version) <= 32)',
    ]) {
      assert.ok(devices.includes(fragment), fragment);
    }
    assert.equal(normalizeSql(PUSH_DDL.devicesTokenIndex), 'CREATE UNIQUE INDEX IF NOT EXISTS uq_push_devices_token ON push_devices (fcm_token)');
    assert.match(PUSH_DDL.devicesUserEnabledIndex, /\(user_code\) WHERE notifications_enabled$/);
    assert.match(PUSH_DDL.devicesLastSeenIndex, /\(last_seen_at\)$/);

    const outbox = normalizeSql(PUSH_DDL.outboxTable);
    for (const fragment of [
      'site_code BIGINT NOT NULL REFERENCES sites(site_code) ON DELETE CASCADE',
      'announcement_id BIGINT NOT NULL REFERENCES announcements(id) ON DELETE CASCADE',
      'user_code INTEGER NOT NULL,',
      "status TEXT NOT NULL DEFAULT 'pending'",
      'attempts SMALLINT NOT NULL DEFAULT 0',
      'not_before TIMESTAMPTZ NOT NULL DEFAULT NOW()',
      'expires_at TIMESTAMPTZ NOT NULL',
      'claimed_at TIMESTAMPTZ',
      'sent_device_count SMALLINT NOT NULL DEFAULT 0',
      'UNIQUE (announcement_id, user_code)',
      "CHECK (kind IN ('announcement'))",
      "CHECK (importance IN ('normal', 'urgent'))",
      "CHECK (status IN ('pending', 'sent', 'failed', 'skipped', 'expired'))",
      "CHECK (skip_reason IS NULL OR skip_reason IN ('pref', 'withdrawn', 'capped', 'no_device', 'inactive'))",
    ]) {
      assert.ok(outbox.includes(fragment), fragment);
    }
    assert.doesNotMatch(outbox, /user_code INTEGER NOT NULL REFERENCES/, 'K15: outbox.user_code FK\'siz');
    assert.match(PUSH_DDL.outboxPendingIndex, /\(status, not_before\) WHERE status = 'pending'$/);
    assert.match(PUSH_DDL.outboxUserSentIndex, /\(user_code, sent_at\) WHERE status = 'sent'$/);
    assert.match(PUSH_DDL.outboxCreatedIndex, /\(created_at\)$/);
    // inceleme: hesap silmedeki DELETE ... WHERE user_code kilitler tutulurken tablo taramasın; site silme CASCADE / acil sayımı (site_code)
    assert.equal(normalizeSql(PUSH_DDL.outboxUserIndex), 'CREATE INDEX IF NOT EXISTS idx_push_outbox_user ON push_outbox (user_code)');
    assert.equal(normalizeSql(PUSH_DDL.outboxSiteIndex), 'CREATE INDEX IF NOT EXISTS idx_push_outbox_site ON push_outbox (site_code)');
    // 2. tur (Y5): site başına günlük acil sayımı için kısmi indeks
    assert.equal(
      normalizeSql(PUSH_DDL.outboxUrgentSiteIndex),
      "CREATE INDEX IF NOT EXISTS idx_push_outbox_urgent_site ON push_outbox (site_code, created_at) WHERE importance = 'urgent'",
    );
    assert.ok(PUSH_DDL_ORDER.indexOf('outboxSiteIndex') > PUSH_DDL_ORDER.indexOf('outboxTable') && PUSH_DDL_ORDER.indexOf('outboxSiteIndex') < PUSH_DDL_ORDER.indexOf('preferenceColumns'));
    const prefs = normalizeSql(PUSH_DDL.preferenceColumns);
    for (const fragment of [
      'ADD COLUMN IF NOT EXISTS push_show_preview BOOLEAN NOT NULL DEFAULT FALSE',
      'ADD COLUMN IF NOT EXISTS push_quiet_enabled BOOLEAN NOT NULL DEFAULT FALSE',
      'ADD COLUMN IF NOT EXISTS push_quiet_start SMALLINT NOT NULL DEFAULT 1380',
      'ADD COLUMN IF NOT EXISTS push_quiet_end SMALLINT NOT NULL DEFAULT 420',
    ]) {
      assert.ok(prefs.includes(fragment), fragment);
    }
    assert.deepEqual([...PUSH_PREFERENCE_COLUMNS], ['push_show_preview', 'push_quiet_enabled', 'push_quiet_start', 'push_quiet_end']);
  });

  it('AÇILIŞ 40P01 dersi: DDL db.js dev bloğunda DEĞİL; db.js yalnız ensurePushSchema(client) çağırır, 039 yardımcısından SONRA ve people_v1\'den ÖNCE', () => {
    const normalizedDb = normalizeSql(DB_SOURCE);
    for (const name of PUSH_DDL_ORDER) {
      assert.equal(normalizedDb.includes(normalizeSql(PUSH_DDL[name])), false, `${name} db.js içinde olmamalı`);
    }
    assert.doesNotMatch(DB_SOURCE, /CREATE TABLE IF NOT EXISTS push_(devices|outbox)\b/);
    assert.doesNotMatch(DB_SOURCE, /ADD COLUMN IF NOT EXISTS push_quiet/);
    assert.match(DB_SOURCE, /import \{ ensurePushSchema \} from '\.\/modules\/push_schema\.js';/);
    const calls = [...DB_SOURCE.matchAll(/await ensurePushSchema\(client\);/g)];
    assert.equal(calls.length, 1);
    assert.ok(calls[0].index > DB_SOURCE.indexOf('await ensureDocumentsSchema(client);'));
    assert.ok(calls[0].index < DB_SOURCE.indexOf('await runPeopleBackfill(client);'));
  });
});

describe('ensurePushSchema (katalog kontrollü)', () => {
  function fakeClient(state) {
    const log = [];
    return {
      log,
      async query(text, params) {
        const sql = normalizeSql(text);
        log.push(sql);
        if (/^SELECT ARRAY\(SELECT t FROM unnest/.test(sql)) return { rows: [state] };
        if (state.failOnce && sql.startsWith(state.failOnce.prefix)) {
          const code = state.failOnce.code;
          state.failOnce = null;
          throw Object.assign(new Error('kilit'), { code });
        }
        return { rows: [], params };
      },
    };
  }
  const allIndexes = ['uq_push_devices_token', 'idx_push_devices_user_enabled', 'idx_push_devices_last_seen', 'idx_push_outbox_pending', 'idx_push_outbox_user_sent', 'idx_push_outbox_created', 'idx_push_outbox_user', 'idx_push_outbox_site', 'idx_push_outbox_urgent_site'];
  const allTables = ['users', 'sites', 'announcements', 'notification_preferences', 'push_devices', 'push_outbox'];

  it('her şey varsa (normal açılış) TEK katalog sorgusu, hiçbir DDL / kilit yok', async () => {
    const client = fakeClient({ tables: allTables, indexes: allIndexes, preference_columns: 4, has_quiet_check: true });
    await ensurePushSchema(client);
    assert.equal(client.log.length, 1);
  });

  it('boş şemada sırayla tüm adımlar (lock_timeout 2 sn), sonra RESET; sütunlar yoksa CHECK sütunlardan SONRA', async () => {
    const client = fakeClient({ tables: ['users', 'sites', 'announcements', 'notification_preferences'], indexes: [], preference_columns: 0, has_quiet_check: false });
    await ensurePushSchema(client);
    assert.equal(client.log[1], "SET lock_timeout = '2s'");
    assert.deepEqual(client.log.slice(2, -1), PUSH_DDL_ORDER.map((name) => normalizeSql(PUSH_DDL[name])));
    assert.equal(client.log.at(-1), 'RESET lock_timeout');
  });

  it('yalnız eksikler: sütunlar var ama CHECK yoksa yalnız CHECK; bağımlı tablo yoksa (platform öncesi) outbox atlanır', async () => {
    let client = fakeClient({ tables: allTables, indexes: allIndexes, preference_columns: 4, has_quiet_check: false });
    await ensurePushSchema(client);
    assert.deepEqual(client.log.slice(2, -1), [normalizeSql(PUSH_DDL.preferenceQuietCheck)]);
    client = fakeClient({ tables: ['users', 'sites', 'notification_preferences'], indexes: [], preference_columns: 4, has_quiet_check: true });
    await ensurePushSchema(client);
    const ran = client.log.slice(2, -1);
    assert.ok(ran.includes(normalizeSql(PUSH_DDL.devicesTable)));
    assert.ok(!ran.includes(normalizeSql(PUSH_DDL.outboxTable)));
    assert.ok(!ran.some((sql) => /push_outbox/.test(sql)));
  });

  it('40P01 / 55P03 tek ifadede güvenle yeniden denenir', async () => {
    const client = fakeClient({ tables: allTables, indexes: allIndexes.slice(1), preference_columns: 4, has_quiet_check: true, failOnce: { prefix: 'CREATE UNIQUE INDEX', code: '55P03' } });
    await ensurePushSchema(client);
    assert.equal(client.log.filter((sql) => sql.startsWith('CREATE UNIQUE INDEX IF NOT EXISTS uq_push_devices_token')).length, 2);
  });
});

describe('kaynak bağlantıları', () => {
  it('yayın işleminde outbox: publishWithinTransaction içinde alıcı anlık görüntüsünden ve audit\'ten SONRA, return\'den önce (AYNI client)', () => {
    const source = read('src/modules/announcement_service.js');
    const start = source.indexOf('export async function publishWithinTransaction(');
    const end = source.indexOf('\n}\n', start);
    const body = source.slice(start, end);
    const enqueue = body.indexOf('await enqueueAnnouncementPush(client, { announcementId: id, siteCode, importance: row.importance });');
    assert.ok(enqueue > 0);
    assert.ok(enqueue > body.indexOf('await snapshotRecipients(client'));
    assert.ok(enqueue > body.indexOf("'announcement.published'"));
    assert.ok(enqueue < body.lastIndexOf('return { published: true'));
    assert.match(source, /import \{ enqueueAnnouncementPush \} from '\.\/push_outbox\.js';/);
  });

  it('zamanlayıcı tikinde hasPendingPush -> kickPushQueue; yayından sonra rota kancası kickPushQueue; kilit işi pushQueue = 5 (4 finans hatırlatmanın)', () => {
    const scheduler = read('src/modules/announcement_scheduler.js');
    assert.match(scheduler, /hasPendingPush: \(\) => hasPendingPush\(\),/);
    assert.match(scheduler, /if \(!stopped && \(await schedulerHooks\.hasPendingPush\(\)\)\) \{\s*void schedulerHooks\.kickPushQueue\(\);/);
    const routes = read('src/modules/announcement_routes.js');
    assert.match(routes, /kickPushQueue: \(\) => kickPushQueue\(\),/);
    assert.match(routes, /void Promise\.resolve\(announcementRouteHooks\.kickPushQueue\(\)\)\.catch\(\(\) => \{\}\);/);
    assert.match(read('src/modules/announcement_lock.js'), /pushQueue: 5,/);
  });

  it('server.js: yönlendirici SPA yedeğinden ÖNCE; işçi açılışta başlar, kapanışta durur; validateEnv push uyarılarını ekler', () => {
    const server = read('src/server.js');
    assert.ok(server.indexOf('app.use(pushRouter);') > 0);
    assert.ok(server.indexOf('app.use(pushRouter);') < server.indexOf("app.get('*'"));
    assert.ok(server.indexOf('startPushWorker();') > server.indexOf('await ensureDbSchema();'));
    assert.ok(server.indexOf('startPushWorker();') < server.indexOf('startAnnouncementScheduler();', server.indexOf('async function startServer')));
    assert.ok(server.indexOf('await stopPushWorker();') > server.indexOf('await stopAnnouncementScheduler();'));
    assert.ok(server.indexOf('await stopPushWorker();') < server.indexOf('await pool.end();'));
    assert.match(read('src/config/env.js'), /warnings\.push\(\.\.\.pushEnvWarnings\(env\)\);/);
  });

  it('hesap silme: notification_preferences silmesinden hemen sonra AYNI işlemde deletePushDataForUser(client, userCode)', () => {
    const source = read('src/modules/account_deletion_service.js');
    const prefs = source.indexOf("await client.query('DELETE FROM notification_preferences WHERE user_code = $1', [userCode]);");
    const push = source.indexOf('await deletePushDataForUser(client, userCode);');
    assert.ok(prefs > 0 && push > prefs && push < source.indexOf("await client.query('COMMIT');", prefs));
  });

  it('deletePushDataForUser: tablolar varsa push_devices + push_outbox (user_code) silinir; yoksa (to_regclass) atlanır', async () => {
    const run = (present) => {
      const log = [];
      const client = {
        async query(text, params) {
          const sql = normalizeSql(text);
          log.push({ sql, params });
          if (/^SELECT to_regclass/.test(sql)) return { rows: [{ has_devices: present, has_outbox: present }] };
          return { rows: [], rowCount: 3 };
        },
      };
      return { log, client };
    };
    const yes = run(true);
    assert.deepEqual(await deletePushDataForUser(yes.client, 12345), { devices: 3, outbox: 3 });
    assert.deepEqual(yes.log.slice(1).map((q) => [q.sql, q.params]), [
      ['DELETE FROM push_devices WHERE id IN (SELECT id FROM push_devices WHERE user_code = $1 ORDER BY id FOR UPDATE)', [12345]],
      ['DELETE FROM push_outbox WHERE id IN (SELECT id FROM push_outbox WHERE user_code = $1 ORDER BY id FOR UPDATE)', [12345]],
    ]);
    const no = run(false);
    assert.deepEqual(await deletePushDataForUser(no.client, 12345), { devices: 0, outbox: 0 });
    assert.equal(no.log.length, 1);
  });

  it('veri dışa aktarma: push_devices (platform, app_version, tarihler) — jeton / kurulum kimliği HARİÇ; excluded notu; tablo yoksa boş', async () => {
    const log = [];
    const client = {
      async query(text, params) {
        const sql = normalizeSql(text);
        log.push({ sql, params });
        if (/^SELECT to_regclass\('public\.push_devices'\) AS t$/.test(sql)) return { rows: [{ t: 'push_devices' }] };
        return { rows: [{ platform: 'ios', app_version: '1.0.0', notifications_enabled: true, created_at: new Date('2026-10-01T00:00:00Z'), last_seen_at: new Date('2026-10-17T00:00:00Z'), last_success_at: null, fcm_token: 'SIZMAMALI' }] };
      },
    };
    const rows = await exportPushDevices(client, 12345);
    assert.deepEqual(rows, [{ platform: 'ios', app_version: '1.0.0', notifications_enabled: true, created_at: '2026-10-01T00:00:00.000Z', last_seen_at: '2026-10-17T00:00:00.000Z', last_success_at: null }]);
    assert.doesNotMatch(log[1].sql, /fcm_token|install_id/);
    assert.deepEqual(log[1].params, [12345]);
    assert.ok(EXPORT_EXCLUDED.includes(PUSH_EXPORT_EXCLUDED_NOTE));
    assert.match(PUSH_EXPORT_EXCLUDED_NOTE, /jetonu.*dışarıda bırakılmıştır/);
    const empty = { async query() { return { rows: [{ t: null }] }; } };
    assert.deepEqual(await exportPushDevices(empty, 12345), []);
    const exportSource = read('src/modules/account_export_service.js');
    assert.match(exportSource, /push_devices: pushDevices,/);
  });
});
