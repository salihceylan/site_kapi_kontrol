// İş Takibi (042) şeması (DB'siz): migration 042 <-> work_tracking_schema.js aynı DDL (aynı sıra), ekleyici / idempotent, sütun / kısıt / indeks ayrıntıları,
// AÇILIŞ 40P01 dersi (DDL dev ensureDbSchema bloğunda DEĞİL; katalog kontrolüyle yalnız EKSİKLER, kendi otomatik onaylı ifadeleriyle), yeniden deneme.
// Gerçek PostgreSQL doğrulaması: scripts/qa_platform_pg.mjs "work_tracking" (+ "chain" / "live" şema eşitliği).
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { DEFAULT_MIGRATIONS_DIR, findUnsafeStatements, listMigrations } from '../scripts/migrate.js';
import { WORK_TRACKING_DDL, WORK_TRACKING_DDL_ORDER, ensureWorkTrackingSchema, repairResidentCancelUnread, schemaTuning } from '../src/modules/work_tracking_schema.js';

schemaTuning.retryDelayMs = 1;

const here = path.dirname(fileURLToPath(import.meta.url));
const MIGRATION = readFileSync(path.join(DEFAULT_MIGRATIONS_DIR, '042_work_tracking.sql'), 'utf8').replace(/\r\n/g, '\n');
const DB_SOURCE = readFileSync(path.join(here, '..', 'src', 'db.js'), 'utf8').replace(/\r\n/g, '\n');

function normalizeSql(text) {
  return text.replace(/\/\*[\s\S]*?\*\//g, ' ').replace(/--.*$/gm, ' ').replace(/\s+/g, ' ').trim();
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

const sql = (name) => normalizeSql(WORK_TRACKING_DDL[name]);

describe('migration 042: iş takibi', () => {
  it('042 var, çalıştırıcı için güvenli (üst düzey BEGIN/COMMIT yok), numara yinelenmez', () => {
    const list = listMigrations(DEFAULT_MIGRATIONS_DIR);
    const entry = list.find((m) => m.number === 42);
    assert.ok(entry, '042 numaralı migration yok');
    assert.equal(entry.file, '042_work_tracking.sql');
    assert.equal(list.filter((m) => m.number === 42).length, 1);
    assert.deepEqual(findUnsafeStatements(MIGRATION), []);
  });

  it('WORK_TRACKING_DDL migration 042 ile AYNI ifadeleri taşır (yorumlar ve boşluklar dışında birebir, AYNI sırayla)', () => {
    const fromMigration = splitStatements(MIGRATION);
    assert.equal(fromMigration.length, 21);
    assert.deepEqual(fromMigration, WORK_TRACKING_DDL_ORDER.map((name) => normalizeSql(WORK_TRACKING_DDL[name])));
    assert.deepEqual(Object.keys(WORK_TRACKING_DDL), [...WORK_TRACKING_DDL_ORDER]);
  });

  it('EKLEMELİ ve idempotent: yalnız CREATE TABLE / INDEX IF NOT EXISTS ve katalog korumalı FK; DROP / UPDATE / DELETE / INSERT YOK, ALTER yalnız YENİ tablolarda', () => {
    for (const statement of splitStatements(MIGRATION)) {
      assert.match(
        statement,
        /^(CREATE (UNIQUE )?(TABLE|INDEX) IF NOT EXISTS |DO \$\$ BEGIN IF NOT EXISTS \( SELECT 1 FROM pg_constraint WHERE conname = '\w+_fkey' AND conrelid = '\w+'::regclass \) THEN ALTER TABLE \w+ ADD CONSTRAINT \w+_fkey FOREIGN KEY \(\w+\) REFERENCES \w+\(\w+\) ON DELETE (CASCADE|SET NULL); END IF; END \$\$$)/,
      );
    }
    const all = normalizeSql(MIGRATION);
    assert.ok(!/\b(DROP|TRUNCATE|UPDATE|DELETE FROM|INSERT INTO)\b/i.test(all));
    assert.equal((all.match(/ALTER TABLE (\w+)/g) ?? []).filter((entry) => !/ALTER TABLE (work_items|work_item_events)$/.test(entry)).length, 0);
    assert.equal((all.match(/ALTER TABLE/g) ?? []).length, 8);
  });

  it('AÇILIŞ 40P01 dersi: DDL dev blokta DEĞİL; db.js yalnız ensureWorkTrackingSchema(client) çağırır, push şemasından SONRA ve people_v1\'den ÖNCE', () => {
    const normalizedDb = normalizeSql(DB_SOURCE);
    for (const name of WORK_TRACKING_DDL_ORDER) {
      assert.equal(normalizedDb.includes(normalizeSql(WORK_TRACKING_DDL[name])), false, `${name} db.js içinde olmamalı`);
    }
    assert.equal(/CREATE TABLE IF NOT EXISTS work_item(s|_events)\b/.test(DB_SOURCE), false);
    assert.match(DB_SOURCE, /import \{ ensureWorkTrackingSchema \} from '\.\/modules\/work_tracking_schema\.js';/);
    const calls = [...DB_SOURCE.matchAll(/await ensureWorkTrackingSchema\(client\);/g)];
    assert.equal(calls.length, 1);
    assert.ok(calls[0].index > DB_SOURCE.indexOf('    `);\n\n    await ensurePendingConsentsColumn(client);'));
    assert.ok(calls[0].index > DB_SOURCE.indexOf('await ensurePushSchema(client);'));
    assert.ok(calls[0].index < DB_SOURCE.indexOf('await runPeopleBackfill(client);'));
  });
});

describe('şema ayrıntıları', () => {
  it('work_items: sütunlar, DB varsayılanları (yeni / normal), CHECK kümeleri, kapanma tutarlılığı', () => {
    const items = sql('itemsTable');
    for (const fragment of [
      'id BIGSERIAL PRIMARY KEY',
      "status TEXT NOT NULL DEFAULT 'yeni'",
      "priority TEXT NOT NULL DEFAULT 'normal'",
      'resident_urgent BOOLEAN NOT NULL DEFAULT FALSE',
      'due_date DATE',
      'requester_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW()',
      'resident_updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()',
      "category IN ('ariza', 'bakim', 'sikayet_oneri', 'diger')",
      "location_type IN ('ortak_alan', 'daire')",
      "status IN ('yeni', 'islemde', 'beklemede', 'cozuldu', 'kapandi', 'iptal')",
      "priority IN ('dusuk', 'normal', 'acil')",
      'char_length(title) BETWEEN 1 AND 120',
      'char_length(description) BETWEEN 1 AND 2000',
      "location_type = 'daire' OR apartment_id IS NULL",
      "(status IN ('kapandi', 'iptal')) = (closed_at IS NOT NULL)",
      'char_length(idempotency_key) <= 64',
    ]) {
      assert.ok(items.includes(fragment), fragment);
    }
  });

  it('work_item_events: değişmez günlük kısıtları (tür, görünürlük, aktör, yorum gövdesi), DB varsayılan görünürlük EN KISITLI (internal), sakin yalnız public', () => {
    const events = sql('eventsTable');
    for (const fragment of [
      "visibility TEXT NOT NULL DEFAULT 'internal'",
      "event_type IN ('created', 'status_changed', 'assigned', 'priority_changed', 'due_date_changed', 'comment')",
      "visibility IN ('public', 'internal')",
      "actor_kind IN ('resident', 'staff', 'manager')",
      "(event_type = 'comment') = (body IS NOT NULL)",
      'char_length(body) BETWEEN 1 AND 1000',
      "actor_kind <> 'resident' OR visibility = 'public'",
    ]) {
      assert.ok(events.includes(fragment), fragment);
    }
    assert.ok(!/ssn|name|phone|email/i.test(events), 'olaylarda ad / iletişim anlık görüntüsü YOK (yalnız kullanıcı kodu)');
  });

  it('indeksler: kısmi (açık talepler, FK sütunları), tekil idempotans x2, olay (talep, id)', () => {
    assert.equal(sql('itemsSiteStatusIndex'), 'CREATE INDEX IF NOT EXISTS idx_work_items_site_status ON work_items (site_code, status, id DESC)');
    assert.ok(sql('itemsSiteOpenIndex').endsWith("WHERE status NOT IN ('kapandi', 'iptal')"));
    assert.ok(sql('itemsMineIndex').endsWith('WHERE created_by IS NOT NULL') && sql('itemsMineIndex').includes('(created_by, site_code, id DESC)'));
    assert.ok(sql('itemsIdempotencyIndex').startsWith('CREATE UNIQUE INDEX') && sql('itemsIdempotencyIndex').includes('(site_code, created_by, idempotency_key) WHERE idempotency_key IS NOT NULL'));
    assert.ok(sql('eventsIdempotencyIndex').includes('(work_item_id, actor_user_code, idempotency_key) WHERE idempotency_key IS NOT NULL'));
    assert.equal(sql('eventsItemIndex'), 'CREATE INDEX IF NOT EXISTS idx_work_item_events_item ON work_item_events (work_item_id, id)');
  });
});

describe("yabancı anahtarlar (R11 F1): tablolar FK'SIZ, her FK ayrı katalog korumalı ifade", () => {
  const EXPECTED_FKS = [
    ['work_items', 'site_code', 'sites', 'site_code', 'CASCADE'],
    ['work_items', 'created_by', 'users', 'user_code', 'SET NULL'],
    ['work_items', 'assigned_to', 'users', 'user_code', 'SET NULL'],
    ['work_items', 'apartment_id', 'apartments', 'id', 'SET NULL'],
    ['work_items', 'block_id', 'site_blocks', 'id', 'SET NULL'],
    ['work_item_events', 'work_item_id', 'work_items', 'id', 'CASCADE'],
    ['work_item_events', 'site_code', 'sites', 'site_code', 'CASCADE'],
    ['work_item_events', 'actor_user_code', 'users', 'user_code', 'SET NULL'],
  ];
  const FK_STEPS = WORK_TRACKING_DDL_ORDER.filter((name) => name.endsWith('Fk'));

  it('hiçbir CREATE TABLE satır içi REFERENCES taşımaz', () => {
    for (const name of ['itemsTable', 'eventsTable']) assert.ok(!/REFERENCES/i.test(WORK_TRACKING_DDL[name]), name);
  });

  it('8 FK ifadesi: ifade başına TEK başvuru, ad <tablo>_<sütun>_fkey, katalog korumalı, beklenen üst tablo / ON DELETE; her tablonun FK\'leri tablodan HEMEN sonra, indekslerinden ÖNCE', () => {
    assert.equal(FK_STEPS.length, 8);
    const parsed = FK_STEPS.map((name) => {
      const text = sql(name);
      assert.equal((text.match(/REFERENCES/g) ?? []).length, 1);
      const match = /conname = '(\w+)' AND conrelid = '(\w+)'::regclass \) THEN ALTER TABLE (\w+) ADD CONSTRAINT (\w+) FOREIGN KEY \((\w+)\) REFERENCES (\w+)\((\w+)\) ON DELETE (CASCADE|SET NULL); END IF; END \$\$$/.exec(text);
      assert.ok(match, `${name}: biçim`);
      const [, guard, guardTable, table, constraint, column, parent, parentColumn, onDelete] = match;
      assert.equal(guard, constraint);
      assert.equal(guardTable, table);
      assert.equal(constraint, `${table}_${column}_fkey`);
      return [table, column, parent, parentColumn, onDelete];
    });
    assert.deepEqual(parsed, EXPECTED_FKS);
    const at = (name) => WORK_TRACKING_DDL_ORDER.indexOf(name);
    for (const fk of ['itemsSiteFk', 'itemsCreatedByFk', 'itemsAssignedToFk', 'itemsApartmentFk', 'itemsBlockFk']) assert.ok(at('itemsTable') < at(fk) && at(fk) < at('itemsSiteStatusIndex'), fk);
    for (const fk of ['eventsItemFk', 'eventsSiteFk', 'eventsActorFk']) assert.ok(at('eventsTable') < at(fk) && at(fk) < at('eventsItemIndex') && at('itemsTable') < at(fk), fk);
  });

  it('SICAK üst tablo kuralı: hiçbir ifade sites / users / apartments / site_blocks\'tan birden fazlasını başvurmaz', () => {
    for (const name of WORK_TRACKING_DDL_ORDER) {
      const hot = new Set([...sql(name).matchAll(/REFERENCES (sites|users|apartments|site_blocks)\(/g)].map((match) => match[1]));
      assert.ok(hot.size <= 1, name);
    }
  });
});

describe('ensureWorkTrackingSchema (katalog kontrolü + yeniden deneme)', () => {
  const ALL_INDEXES = WORK_TRACKING_DDL_ORDER.filter((n) => /Index$/.test(n)).map((n) => /INDEX IF NOT EXISTS (\w+)/.exec(sql(n))[1]);
  const ALL_FKS = [
    'work_items.work_items_site_code_fkey', 'work_items.work_items_created_by_fkey', 'work_items.work_items_assigned_to_fkey', 'work_items.work_items_apartment_id_fkey',
    'work_items.work_items_block_id_fkey', 'work_item_events.work_item_events_work_item_id_fkey', 'work_item_events.work_item_events_site_code_fkey',
    'work_item_events.work_item_events_actor_user_code_fkey',
  ];
  const ALL_TABLES = ['work_items', 'work_item_events', 'apartments', 'site_blocks'];

  function fakeClient({ tables, indexes, fks = [], failures = {}, repairNeeded = false, repairFails = null }) {
    const log = [];
    return {
      log,
      async query(text) {
        const statement = normalizeSql(text);
        log.push(statement);
        if (/^SELECT ARRAY/.test(statement)) return { rows: [{ tables, indexes, fks }] };
        if (/^SET lock_timeout|^RESET lock_timeout/.test(statement)) return { rows: [] };
        if (/^SELECT EXISTS \(SELECT 1 FROM work_items w WHERE/.test(statement)) {
          if (repairFails) throw Object.assign(new Error('enjekte'), { code: repairFails });
          return { rows: [{ needed: repairNeeded }] };
        }
        if (/^UPDATE work_items w SET requester_seen_at = w\.resident_updated_at/.test(statement)) return { rows: [], rowCount: 3 };
        const key = Object.keys(failures).find((needle) => statement.includes(needle));
        if (key && failures[key].length > 0) throw Object.assign(new Error('enjekte'), { code: failures[key].shift() });
        return { rows: [] };
      },
    };
  }
  const ddlOf = (client) => client.log.filter((statement) => /^(CREATE|DO)/.test(statement));

  it('11 indeks adı beklenen kümedir', () => {
    assert.equal(ALL_INDEXES.length, 11);
    assert.ok(ALL_INDEXES.every((name) => /^(idx|uq)_work_item/.test(name)), ALL_INDEXES.join());
  });

  it('her şey varsa (normal açılış) katalog sorgusu + RU-2 onarımının UCUZ EXISTS okuması gider: DDL yok, kilit ayarı yok, UPDATE YOK', async () => {
    const client = fakeClient({ tables: ALL_TABLES, indexes: ALL_INDEXES, fks: ALL_FKS });
    await ensureWorkTrackingSchema(client);
    assert.equal(client.log.length, 2);
    assert.match(client.log[0], /^SELECT ARRAY/);
    assert.match(client.log[1], /^SELECT EXISTS \(SELECT 1 FROM work_items w WHERE w\.status = 'iptal' AND w\.resident_updated_at > w\.requester_seen_at AND EXISTS \( SELECT 1 FROM work_item_events e WHERE e\.work_item_id = w\.id AND e\.event_type = 'status_changed' AND e\.actor_kind = 'resident' AND e\.to_value = 'iptal' \) \) AS needed$/);
    assert.equal(client.log.some((statement) => /^UPDATE/.test(statement)), false);
  });

  it('RU-2 onarımı: gerekiyorsa (EXISTS true) TEK UPDATE 2 sn kilit beklemesiyle (SET / RESET); tablolar yoksa onarım sorgusu HİÇ gitmez; hata açılışı durdurmaz', async () => {
    const needed = fakeClient({ tables: ALL_TABLES, indexes: ALL_INDEXES, fks: ALL_FKS, repairNeeded: true });
    await ensureWorkTrackingSchema(needed);
    assert.deepEqual(needed.log.slice(1).map((statement) => statement.split(' ').slice(0, 3).join(' ')), ['SELECT EXISTS (SELECT', "SET lock_timeout =", 'UPDATE work_items w', 'RESET lock_timeout']);
    assert.ok(needed.log[3].endsWith("e.actor_kind = 'resident' AND e.to_value = 'iptal' )"), needed.log[3]);
    assert.equal(await repairResidentCancelUnread(fakeClient({ tables: [], indexes: [], repairNeeded: true })), 3);
    const fresh = fakeClient({ tables: ['apartments', 'site_blocks'], indexes: [] });
    await ensureWorkTrackingSchema(fresh);
    assert.equal(fresh.log.some((statement) => /EXISTS \(SELECT 1 FROM work_items w|^UPDATE work_items w/.test(statement)), false, 'ilk kurulumda onarım yok');
    const realError = console.error;
    console.error = () => {};
    try {
      const broken = fakeClient({ tables: ALL_TABLES, indexes: ALL_INDEXES, fks: ALL_FKS, repairFails: '57014' });
      await ensureWorkTrackingSchema(broken);
      assert.equal(broken.log.length, 2, 'hata yutuldu, açılış sürdü');
    } finally {
      console.error = realError;
    }
  });

  it('hiçbiri yoksa: lock_timeout, her ifade TEK ayrı sorgu olarak SIRAYLA (tablo, FK\'leri, indeksleri), sonda RESET', async () => {
    const client = fakeClient({ tables: ['apartments', 'site_blocks'], indexes: [] });
    await ensureWorkTrackingSchema(client);
    assert.equal(client.log[1], "SET lock_timeout = '2s'");
    assert.equal(client.log[client.log.length - 1], 'RESET lock_timeout');
    assert.deepEqual(client.log.slice(2, -1), WORK_TRACKING_DDL_ORDER.map((name) => sql(name)));
  });

  it('yalnız eksik indeks / yalnız eksik FK varsa yalnız o ifade gider; tablo var ama hiç FK yoksa 8 FK sırayla tamamlanır', async () => {
    const missingIndex = fakeClient({ tables: ALL_TABLES, indexes: ALL_INDEXES.filter((n) => n !== 'idx_work_items_site_open'), fks: ALL_FKS });
    await ensureWorkTrackingSchema(missingIndex);
    assert.deepEqual(ddlOf(missingIndex), [sql('itemsSiteOpenIndex')]);
    const missingFk = fakeClient({ tables: ALL_TABLES, indexes: ALL_INDEXES, fks: ALL_FKS.filter((n) => n !== 'work_items.work_items_assigned_to_fkey') });
    await ensureWorkTrackingSchema(missingFk);
    assert.deepEqual(ddlOf(missingFk), [sql('itemsAssignedToFk')]);
    const noFks = fakeClient({ tables: ALL_TABLES, indexes: ALL_INDEXES, fks: [] });
    await ensureWorkTrackingSchema(noFks);
    assert.deepEqual(ddlOf(noFks), WORK_TRACKING_DDL_ORDER.filter((n) => n.endsWith('Fk')).map((n) => sql(n)));
  });

  it('üst tablo (apartments / site_blocks) henüz yoksa yalnız o FK\'ler atlanır, diğerleri kurulur', async () => {
    const client = fakeClient({ tables: [], indexes: [] });
    await ensureWorkTrackingSchema(client);
    const fkSent = ddlOf(client).filter((statement) => /^DO/.test(statement));
    assert.equal(fkSent.length, 6);
    assert.ok(!fkSent.some((statement) => /REFERENCES (apartments|site_blocks)/.test(statement)));
  });

  it('40P01 / 55P03 geçici çakışmada yeniden dener; 6 denemeyi aşarsa hatayı fırlatır (RESET yine çalışır); başka hata ANINDA fırlar', async () => {
    const missing = { tables: ALL_TABLES, indexes: ALL_INDEXES, fks: ALL_FKS.filter((n) => n !== 'work_items.work_items_site_code_fkey') };
    const retry = fakeClient({ ...missing, failures: { 'ADD CONSTRAINT work_items_site_code_fkey': ['40P01', '55P03', '40P01'] } });
    await ensureWorkTrackingSchema(retry);
    assert.equal(retry.log.filter((statement) => statement.includes('ADD CONSTRAINT work_items_site_code_fkey')).length, 4);
    const hopeless = fakeClient({ ...missing, failures: { 'ADD CONSTRAINT work_items_site_code_fkey': Array(10).fill('40P01') } });
    await assert.rejects(ensureWorkTrackingSchema(hopeless), { code: '40P01' });
    assert.equal(hopeless.log.filter((statement) => statement.includes('ADD CONSTRAINT work_items_site_code_fkey')).length, 6);
    assert.equal(hopeless.log[hopeless.log.length - 1], 'RESET lock_timeout');
    const fatal = fakeClient({ ...missing, failures: { 'ADD CONSTRAINT work_items_site_code_fkey': ['42501'] } });
    await assert.rejects(ensureWorkTrackingSchema(fatal), { code: '42501' });
    assert.equal(fatal.log.filter((statement) => statement.includes('ADD CONSTRAINT work_items_site_code_fkey')).length, 1);
  });
});
