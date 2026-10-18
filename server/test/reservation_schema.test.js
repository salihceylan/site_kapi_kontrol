// Rezervasyon ve Konsiyerj (043) şeması (DB'siz): migration 043 <-> reservation_schema.js aynı DDL (aynı sıra), ekleyici / idempotent, sütun / kısıt / indeks ayrıntıları,
// AÇILIŞ 40P01 dersi (DDL dev ensureDbSchema bloğunda DEĞİL; katalog kontrolüyle yalnız EKSİKLER, kendi otomatik onaylı ifadeleriyle), yeniden deneme.
// Gerçek PostgreSQL doğrulaması: scripts/qa_platform_pg.mjs "reservation" (+ "chain" / "live" şema eşitliği).
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { DEFAULT_MIGRATIONS_DIR, findUnsafeStatements, listMigrations } from '../scripts/migrate.js';
import { RESERVATION_DDL, RESERVATION_DDL_ORDER, ensureReservationSchema, schemaTuning } from '../src/modules/reservation_schema.js';

schemaTuning.retryDelayMs = 1;

const here = path.dirname(fileURLToPath(import.meta.url));
const MIGRATION = readFileSync(path.join(DEFAULT_MIGRATIONS_DIR, '043_reservation.sql'), 'utf8').replace(/\r\n/g, '\n');
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

const sql = (name) => normalizeSql(RESERVATION_DDL[name]);
const TABLES = ['reservation_areas', 'reservations', 'concierge_requests'];

describe('migration 043: rezervasyon ve konsiyerj', () => {
  it('043 var, çalıştırıcı için güvenli (üst düzey BEGIN/COMMIT yok), numara yinelenmez', () => {
    const list = listMigrations(DEFAULT_MIGRATIONS_DIR);
    const entry = list.find((m) => m.number === 43);
    assert.ok(entry, '043 numaralı migration yok');
    assert.equal(entry.file, '043_reservation.sql');
    assert.equal(list.filter((m) => m.number === 43).length, 1);
    assert.deepEqual(findUnsafeStatements(MIGRATION), []);
  });

  it('RESERVATION_DDL migration 043 ile AYNI ifadeleri taşır (yorumlar ve boşluklar dışında birebir, AYNI sırayla)', () => {
    const fromMigration = splitStatements(MIGRATION);
    assert.equal(fromMigration.length, 28);
    assert.deepEqual(fromMigration, RESERVATION_DDL_ORDER.map((name) => normalizeSql(RESERVATION_DDL[name])));
    assert.deepEqual(Object.keys(RESERVATION_DDL), [...RESERVATION_DDL_ORDER]);
  });

  it('EKLEMELİ ve idempotent: yalnız CREATE TABLE / INDEX IF NOT EXISTS ve katalog korumalı FK; DROP / UPDATE / DELETE / INSERT / EXCLUDE YOK, ALTER yalnız YENİ tablolarda', () => {
    for (const statement of splitStatements(MIGRATION)) {
      assert.match(
        statement,
        /^(CREATE (UNIQUE )?(TABLE|INDEX) IF NOT EXISTS |DO \$\$ BEGIN IF NOT EXISTS \( SELECT 1 FROM pg_constraint WHERE conname = '\w+_fkey' AND conrelid = '\w+'::regclass \) THEN ALTER TABLE \w+ ADD CONSTRAINT \w+_fkey FOREIGN KEY \(\w+\) REFERENCES \w+\(\w+\) ON DELETE (CASCADE|SET NULL); END IF; END \$\$$)/,
      );
    }
    const all = normalizeSql(MIGRATION);
    assert.ok(!/\b(DROP|TRUNCATE|UPDATE|DELETE FROM|INSERT INTO|EXCLUDE|btree_gist)\b/i.test(all));
    assert.equal((all.match(/ALTER TABLE (\w+)/g) ?? []).filter((entry) => !/ALTER TABLE (reservation_areas|reservations|concierge_requests)$/.test(entry)).length, 0);
    assert.equal((all.match(/ALTER TABLE/g) ?? []).length, 11);
  });

  it("AÇILIŞ 40P01 dersi: DDL dev blokta DEĞİL; db.js yalnız ensureReservationSchema(client) çağırır, iş takibi şemasından SONRA ve people_v1'den ÖNCE", () => {
    const normalizedDb = normalizeSql(DB_SOURCE);
    for (const name of RESERVATION_DDL_ORDER) {
      assert.equal(normalizedDb.includes(normalizeSql(RESERVATION_DDL[name])), false, `${name} db.js içinde olmamalı`);
    }
    assert.equal(/CREATE TABLE IF NOT EXISTS (reservation_areas|reservations|concierge_requests)\b/.test(DB_SOURCE), false);
    assert.match(DB_SOURCE, /import \{ ensureReservationSchema \} from '\.\/modules\/reservation_schema\.js';/);
    const calls = [...DB_SOURCE.matchAll(/await ensureReservationSchema\(client\);/g)];
    assert.equal(calls.length, 1);
    assert.ok(calls[0].index > DB_SOURCE.indexOf('    `);\n\n    await ensurePendingConsentsColumn(client);'));
    assert.ok(calls[0].index > DB_SOURCE.indexOf('await ensureWorkTrackingSchema(client);'));
    assert.ok(calls[0].index < DB_SOURCE.indexOf('await runPeopleBackfill(client);'));
  });
});

describe('şema ayrıntıları', () => {
  it('reservation_areas: kapasite / dilim / dilim sayısı / gün / iptal süresi / limit / açık saat kısıtları, varsayılanlar', () => {
    const areas = sql('areasTable');
    for (const fragment of [
      'char_length(name) BETWEEN 1 AND 80',
      'capacity BETWEEN 1 AND 100',
      'slot_minutes BETWEEN 15 AND 480',
      'min_slots BETWEEN 1 AND 48 AND max_slots BETWEEN min_slots AND 48',
      'max_days_ahead BETWEEN 1 AND 180',
      "approval_mode IN ('otomatik', 'yonetici_onayli')",
      'cancel_cutoff_hours BETWEEN 0 AND 168',
      'per_user_daily_limit BETWEEN 1 AND 20 AND per_user_weekly_limit BETWEEN per_user_daily_limit AND 100',
      "jsonb_typeof(weekly_hours) = 'array' AND jsonb_array_length(weekly_hours) <= 21",
      "approval_mode TEXT NOT NULL DEFAULT 'otomatik'",
      'is_active BOOLEAN NOT NULL DEFAULT TRUE',
    ]) {
      assert.ok(areas.includes(fragment), fragment);
    }
    assert.equal(sql('areasNameIndex'), 'CREATE UNIQUE INDEX IF NOT EXISTS uq_reservation_areas_name ON reservation_areas (site_code, lower(name))');
  });

  it("reservations: durum kümesi, aralık, iptal tutarlılığı (durum <-> cancelled_at <-> tür), DB varsayılan durum EN KISITLI (beklemede), idempotans", () => {
    const reservations = sql('reservationsTable');
    for (const fragment of [
      "status TEXT NOT NULL DEFAULT 'beklemede'",
      "status IN ('beklemede', 'onaylandi', 'reddedildi', 'iptal')",
      'ends_at > starts_at',
      'slot_count BETWEEN 1 AND 48',
      "(status = 'iptal') = (cancelled_at IS NOT NULL) AND (status = 'iptal') = (cancelled_by_kind IS NOT NULL)",
      "cancelled_by_kind IN ('resident', 'management', 'system')",
      'char_length(note) <= 200',
      'char_length(decision_note) <= 300',
    ]) {
      assert.ok(reservations.includes(fragment), fragment);
    }
    assert.ok(sql('reservationsAreaIndex').endsWith("WHERE status IN ('beklemede', 'onaylandi')") && sql('reservationsAreaIndex').includes('(area_id, starts_at)'));
    assert.ok(sql('reservationsIdempotencyIndex').startsWith('CREATE UNIQUE INDEX') && sql('reservationsIdempotencyIndex').includes('(site_code, user_code, idempotency_key) WHERE idempotency_key IS NOT NULL'));
    assert.ok(!/EXCLUDE|btree_gist|price|amount|payment/i.test(reservations), 'kapasite uygulama kilidiyle; ücret / ödeme alanı YOK');
  });

  it('concierge_requests: kategori / durum kümeleri, diğer için not zorunlu, kapanış tutarlılığı, tekil idempotans', () => {
    const requests = sql('conciergeTable');
    for (const fragment of [
      "category IN ('paket_teslim', 'misafir_hazirlik', 'temizlik', 'tasima', 'diger')",
      "status IN ('yeni', 'hazirlaniyor', 'tamamlandi', 'iptal')",
      "category <> 'diger' OR note IS NOT NULL",
      'char_length(note) BETWEEN 1 AND 500',
      'char_length(staff_note) BETWEEN 1 AND 300',
      "(status IN ('tamamlandi', 'iptal')) = (closed_at IS NOT NULL)",
      "status TEXT NOT NULL DEFAULT 'yeni'",
    ]) {
      assert.ok(requests.includes(fragment), fragment);
    }
    assert.ok(sql('conciergeSiteOpenIndex').endsWith("WHERE status NOT IN ('tamamlandi', 'iptal')"));
    assert.ok(sql('conciergeIdempotencyIndex').includes('(site_code, user_code, idempotency_key) WHERE idempotency_key IS NOT NULL'));
  });
});

describe("yabancı anahtarlar (R11 F1): tablolar FK'SIZ, her FK ayrı katalog korumalı ifade", () => {
  const EXPECTED_FKS = [
    ['reservation_areas', 'site_code', 'sites', 'site_code', 'CASCADE'],
    ['reservation_areas', 'created_by', 'users', 'user_code', 'SET NULL'],
    ['reservations', 'site_code', 'sites', 'site_code', 'CASCADE'],
    ['reservations', 'area_id', 'reservation_areas', 'id', 'CASCADE'],
    ['reservations', 'user_code', 'users', 'user_code', 'SET NULL'],
    ['reservations', 'apartment_id', 'apartments', 'id', 'SET NULL'],
    ['reservations', 'decided_by', 'users', 'user_code', 'SET NULL'],
    ['concierge_requests', 'site_code', 'sites', 'site_code', 'CASCADE'],
    ['concierge_requests', 'user_code', 'users', 'user_code', 'SET NULL'],
    ['concierge_requests', 'apartment_id', 'apartments', 'id', 'SET NULL'],
    ['concierge_requests', 'staff_note_by', 'users', 'user_code', 'SET NULL'],
  ];
  const FK_STEPS = RESERVATION_DDL_ORDER.filter((name) => name.endsWith('Fk'));

  it('hiçbir CREATE TABLE satır içi REFERENCES taşımaz', () => {
    for (const name of ['areasTable', 'reservationsTable', 'conciergeTable']) assert.ok(!/REFERENCES/i.test(RESERVATION_DDL[name]), name);
  });

  it("11 FK ifadesi: ifade başına TEK başvuru, ad <tablo>_<sütun>_fkey, katalog korumalı, beklenen üst tablo / ON DELETE; her tablonun FK'leri tablodan HEMEN sonra, indekslerinden ÖNCE", () => {
    assert.equal(FK_STEPS.length, 11);
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
    const at = (name) => RESERVATION_DDL_ORDER.indexOf(name);
    const firstIndexOf = (prefix) => RESERVATION_DDL_ORDER.findIndex((n) => n.startsWith(prefix) && /Index$/.test(n));
    for (const [table, prefix] of [['areasTable', 'areas'], ['reservationsTable', 'reservations'], ['conciergeTable', 'concierge']]) {
      for (const fk of FK_STEPS.filter((n) => n.startsWith(prefix))) assert.ok(at(table) < at(fk) && at(fk) < firstIndexOf(prefix), fk);
    }
    assert.ok(at('areasTable') < at('reservationsAreaFk'));
  });

  it("SICAK üst tablo kuralı: hiçbir ifade sites / users / apartments'tan birden fazlasını başvurmaz", () => {
    for (const name of RESERVATION_DDL_ORDER) {
      const hot = new Set([...sql(name).matchAll(/REFERENCES (sites|users|apartments|site_blocks)\(/g)].map((match) => match[1]));
      assert.ok(hot.size <= 1, name);
    }
  });
});

describe('ensureReservationSchema (katalog kontrolü + yeniden deneme)', () => {
  const ALL_INDEXES = RESERVATION_DDL_ORDER.filter((n) => /Index$/.test(n)).map((n) => /INDEX IF NOT EXISTS (\w+)/.exec(sql(n))[1]);
  const ALL_FKS = FK_LIST();
  const ALL_TABLES = [...TABLES, 'apartments'];

  function FK_LIST() {
    return RESERVATION_DDL_ORDER.filter((n) => n.endsWith('Fk')).map((n) => {
      const m = /conname = '(\w+)' AND conrelid = '(\w+)'::regclass/.exec(sql(n));
      return `${m[2]}.${m[1]}`;
    });
  }

  function fakeClient({ tables, indexes, fks = [], failures = {} }) {
    const log = [];
    return {
      log,
      async query(text) {
        const statement = normalizeSql(text);
        log.push(statement);
        if (/^SELECT ARRAY/.test(statement)) return { rows: [{ tables, indexes, fks }] };
        if (/^SET lock_timeout|^RESET lock_timeout/.test(statement)) return { rows: [] };
        const key = Object.keys(failures).find((needle) => statement.includes(needle));
        if (key && failures[key].length > 0) throw Object.assign(new Error('enjekte'), { code: failures[key].shift() });
        return { rows: [] };
      },
    };
  }
  const ddlOf = (client) => client.log.filter((statement) => /^(CREATE|DO)/.test(statement));

  it('14 indeks adı beklenen kümedir', () => {
    assert.equal(ALL_INDEXES.length, 14);
    assert.ok(ALL_INDEXES.every((name) => /^(idx|uq)_(reservation|reservations|concierge)/.test(name)), ALL_INDEXES.join());
    assert.equal(ALL_FKS.length, 11);
  });

  it('her şey varsa (normal açılış) YALNIZ katalog sorgusu gider: DDL yok, kilit ayarı yok', async () => {
    const client = fakeClient({ tables: ALL_TABLES, indexes: ALL_INDEXES, fks: ALL_FKS });
    await ensureReservationSchema(client);
    assert.equal(client.log.length, 1);
    assert.match(client.log[0], /^SELECT ARRAY/);
  });

  it("hiçbiri yoksa: lock_timeout, her ifade TEK ayrı sorgu olarak SIRAYLA (tablo, FK'leri, indeksleri), sonda RESET", async () => {
    const client = fakeClient({ tables: ['apartments'], indexes: [] });
    await ensureReservationSchema(client);
    assert.equal(client.log[1], "SET lock_timeout = '2s'");
    assert.equal(client.log[client.log.length - 1], 'RESET lock_timeout');
    assert.deepEqual(client.log.slice(2, -1), RESERVATION_DDL_ORDER.map((name) => sql(name)));
  });

  it('yalnız eksik indeks / yalnız eksik FK varsa yalnız o ifade gider; tablolar var ama hiç FK yoksa 11 FK sırayla tamamlanır', async () => {
    const missingIndex = fakeClient({ tables: ALL_TABLES, indexes: ALL_INDEXES.filter((n) => n !== 'idx_reservations_area_active'), fks: ALL_FKS });
    await ensureReservationSchema(missingIndex);
    assert.deepEqual(ddlOf(missingIndex), [sql('reservationsAreaIndex')]);
    const missingFk = fakeClient({ tables: ALL_TABLES, indexes: ALL_INDEXES, fks: ALL_FKS.filter((n) => n !== 'reservations.reservations_decided_by_fkey') });
    await ensureReservationSchema(missingFk);
    assert.deepEqual(ddlOf(missingFk), [sql('reservationsDecidedByFk')]);
    const noFks = fakeClient({ tables: ALL_TABLES, indexes: ALL_INDEXES, fks: [] });
    await ensureReservationSchema(noFks);
    assert.deepEqual(ddlOf(noFks), RESERVATION_DDL_ORDER.filter((n) => n.endsWith('Fk')).map((n) => sql(n)));
  });

  it("üst tablo (apartments) henüz yoksa yalnız o FK'ler atlanır, diğerleri kurulur", async () => {
    const client = fakeClient({ tables: [], indexes: [] });
    await ensureReservationSchema(client);
    const fkSent = ddlOf(client).filter((statement) => /^DO/.test(statement));
    assert.equal(fkSent.length, 9);
    assert.ok(!fkSent.some((statement) => /REFERENCES apartments/.test(statement)));
  });

  it('40P01 / 55P03 geçici çakışmada yeniden dener; 6 denemeyi aşarsa hatayı fırlatır (RESET yine çalışır); başka hata ANINDA fırlar', async () => {
    const missing = { tables: ALL_TABLES, indexes: ALL_INDEXES, fks: ALL_FKS.filter((n) => n !== 'reservations.reservations_site_code_fkey') };
    const retry = fakeClient({ ...missing, failures: { 'ADD CONSTRAINT reservations_site_code_fkey': ['40P01', '55P03', '40P01'] } });
    await ensureReservationSchema(retry);
    assert.equal(retry.log.filter((statement) => statement.includes('ADD CONSTRAINT reservations_site_code_fkey')).length, 4);
    const hopeless = fakeClient({ ...missing, failures: { 'ADD CONSTRAINT reservations_site_code_fkey': Array(10).fill('40P01') } });
    await assert.rejects(ensureReservationSchema(hopeless), { code: '40P01' });
    assert.equal(hopeless.log.filter((statement) => statement.includes('ADD CONSTRAINT reservations_site_code_fkey')).length, 6);
    assert.equal(hopeless.log[hopeless.log.length - 1], 'RESET lock_timeout');
    const fatal = fakeClient({ ...missing, failures: { 'ADD CONSTRAINT reservations_site_code_fkey': ['42501'] } });
    await assert.rejects(ensureReservationSchema(fatal), { code: '42501' });
    assert.equal(fatal.log.filter((statement) => statement.includes('ADD CONSTRAINT reservations_site_code_fkey')).length, 1);
  });
});
