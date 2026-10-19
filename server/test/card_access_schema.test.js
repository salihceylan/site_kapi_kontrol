// Kartlı Geçiş (046) şeması (DB'siz): migration 046 <-> card_access_schema.js aynı DDL (aynı sıra), ekleyici / idempotent, sütun / kısıt / indeks ayrıntıları,
// AÇILIŞ 40P01 dersi (DDL dev ensureDbSchema bloğunda DEĞİL; katalog kontrolüyle yalnız EKSİKLER, kendi otomatik onaylı ifadeleriyle), yeniden deneme.
// Gerçek PostgreSQL doğrulaması: scripts/qa_platform_pg.mjs "card_access" (+ "chain" / "live" şema eşitliği).
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { DEFAULT_MIGRATIONS_DIR, findUnsafeStatements, listMigrations } from '../scripts/migrate.js';
import { CARD_ACCESS_DDL, CARD_ACCESS_DDL_ORDER, ensureCardAccessSchema, schemaTuning } from '../src/modules/card_access_schema.js';

schemaTuning.retryDelayMs = 1;

const here = path.dirname(fileURLToPath(import.meta.url));
const MIGRATION = readFileSync(path.join(DEFAULT_MIGRATIONS_DIR, '046_access_cards.sql'), 'utf8').replace(/\r\n/g, '\n');
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

const sql = (name) => normalizeSql(CARD_ACCESS_DDL[name]);

describe('migration 046: kartlı geçiş', () => {
  it('046 var, çalıştırıcı için güvenli (üst düzey BEGIN/COMMIT yok), numara yinelenmez', () => {
    const list = listMigrations(DEFAULT_MIGRATIONS_DIR);
    const entry = list.find((m) => m.number === 46);
    assert.ok(entry, '046 numaralı migration yok');
    assert.equal(entry.file, '046_access_cards.sql');
    assert.equal(list.filter((m) => m.number === 46).length, 1);
    assert.deepEqual(findUnsafeStatements(MIGRATION), []);
  });

  it('CARD_ACCESS_DDL migration 046 ile AYNI ifadeleri taşır (yorumlar ve boşluklar dışında birebir, AYNI sırayla)', () => {
    const fromMigration = splitStatements(MIGRATION);
    assert.equal(fromMigration.length, 7);
    assert.deepEqual(fromMigration, CARD_ACCESS_DDL_ORDER.map((name) => normalizeSql(CARD_ACCESS_DDL[name])));
    assert.deepEqual(Object.keys(CARD_ACCESS_DDL), [...CARD_ACCESS_DDL_ORDER]);
  });

  it('EKLEMELİ ve idempotent: yalnız CREATE TABLE / INDEX IF NOT EXISTS ve katalog korumalı FK; DROP / UPDATE / DELETE / INSERT YOK, ALTER yalnız access_cards', () => {
    for (const statement of splitStatements(MIGRATION)) {
      assert.match(
        statement,
        /^(CREATE (UNIQUE )?(TABLE|INDEX) IF NOT EXISTS |DO \$\$ BEGIN IF NOT EXISTS \( SELECT 1 FROM pg_constraint WHERE conname = '\w+_fkey' AND conrelid = '\w+'::regclass \) THEN ALTER TABLE \w+ ADD CONSTRAINT \w+_fkey FOREIGN KEY \(\w+\) REFERENCES \w+\(\w+\) ON DELETE (CASCADE|SET NULL); END IF; END \$\$$)/,
      );
    }
    const all = normalizeSql(MIGRATION);
    assert.ok(!/\b(DROP|TRUNCATE|UPDATE|DELETE FROM|INSERT INTO|EXCLUDE|btree_gist)\b/i.test(all));
    assert.deepEqual([...new Set(all.match(/ALTER TABLE (\w+)/g) ?? [])], ['ALTER TABLE access_cards']);
    assert.equal((all.match(/ALTER TABLE/g) ?? []).length, 3);
    // mevcut tablolara sütun / indeks EKLENMEZ: her ifadenin hedefi access_cards
    for (const name of CARD_ACCESS_DDL_ORDER) {
      assert.match(sql(name), /(TABLE IF NOT EXISTS access_cards|ALTER TABLE access_cards|ON access_cards \()/, name);
    }
  });

  it("AÇILIŞ 40P01 dersi: DDL dev blokta DEĞİL; db.js yalnız ensureCardAccessSchema(client) çağırır, rezervasyon şemasından SONRA ve people_v1'den ÖNCE", () => {
    const normalizedDb = normalizeSql(DB_SOURCE);
    for (const name of CARD_ACCESS_DDL_ORDER) {
      assert.equal(normalizedDb.includes(sql(name)), false, `${name} db.js içinde olmamalı`);
    }
    assert.equal(/CREATE TABLE IF NOT EXISTS access_cards\b/.test(DB_SOURCE), false);
    assert.match(DB_SOURCE, /import \{ ensureCardAccessSchema \} from '\.\/modules\/card_access_schema\.js';/);
    const calls = [...DB_SOURCE.matchAll(/await ensureCardAccessSchema\(client\);/g)];
    assert.equal(calls.length, 1);
    assert.ok(calls[0].index > DB_SOURCE.indexOf('    `);\n\n    await ensurePendingConsentsColumn(client);'));
    assert.ok(calls[0].index > DB_SOURCE.indexOf('await ensureReservationSchema(client);'));
    assert.ok(calls[0].index < DB_SOURCE.indexOf('await runPeopleBackfill(client);'));
  });
});

describe('şema ayrıntıları', () => {
  it('access_cards: sütunlar, UID kısıtı (büyük harf / rakam 4-32), etiket 1-60, iptal tutarlılığı (is_active <-> revoked_at), varsayılan aktif', () => {
    const table = sql('cardsTable');
    for (const fragment of [
      'id BIGSERIAL PRIMARY KEY',
      'site_code BIGINT NOT NULL',
      'person_id BIGINT NOT NULL',
      'card_uid TEXT NOT NULL',
      'label TEXT,',
      'is_active BOOLEAN NOT NULL DEFAULT TRUE',
      'revoked_at TIMESTAMPTZ,',
      'created_by INTEGER,',
      'created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()',
      'updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()',
      "CONSTRAINT chk_access_cards_uid CHECK (card_uid ~ '^[A-Z0-9]{4,32}$')",
      'CONSTRAINT chk_access_cards_label_length CHECK (label IS NULL OR char_length(label) BETWEEN 1 AND 60)',
      'CONSTRAINT chk_access_cards_revoked CHECK (is_active = (revoked_at IS NULL))',
    ]) {
      assert.ok(table.includes(fragment), fragment);
    }
    assert.ok(!/REFERENCES/i.test(table), 'tablo FK\'sız oluşturulur (R11 F1)');
    assert.ok(!/user_code|device|mqtt/i.test(table), 'kart KİŞİYE (site_people) bağlıdır, kullanıcıya / cihaza değil');
  });

  it('indeksler: aktif kartlarda (site, uid) KISMİ TEKİL (iptal edilen UID yeniden verilebilir), kişi indeksi, site liste indeksi', () => {
    assert.equal(sql('cardsSiteUidActiveIndex'), 'CREATE UNIQUE INDEX IF NOT EXISTS uq_access_cards_site_uid_active ON access_cards (site_code, card_uid) WHERE is_active');
    assert.equal(sql('cardsPersonIndex'), 'CREATE INDEX IF NOT EXISTS idx_access_cards_person ON access_cards (person_id)');
    assert.equal(sql('cardsSiteIndex'), 'CREATE INDEX IF NOT EXISTS idx_access_cards_site ON access_cards (site_code, is_active, id DESC)');
  });
});

describe("yabancı anahtarlar (R11 F1): tablo FK'SIZ, her FK ayrı katalog korumalı ifade", () => {
  const EXPECTED_FKS = [
    ['access_cards', 'site_code', 'sites', 'site_code', 'CASCADE'],
    ['access_cards', 'person_id', 'site_people', 'id', 'CASCADE'],
    ['access_cards', 'created_by', 'users', 'user_code', 'SET NULL'],
  ];
  const FK_STEPS = CARD_ACCESS_DDL_ORDER.filter((name) => name.endsWith('Fk'));

  it("3 FK ifadesi: ifade başına TEK başvuru, ad <tablo>_<sütun>_fkey, katalog korumalı, beklenen üst tablo / ON DELETE; FK'ler tablodan HEMEN sonra, indekslerden ÖNCE", () => {
    assert.equal(FK_STEPS.length, 3);
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
    const at = (name) => CARD_ACCESS_DDL_ORDER.indexOf(name);
    const firstIndex = CARD_ACCESS_DDL_ORDER.findIndex((n) => /Index$/.test(n));
    for (const fk of FK_STEPS) assert.ok(at('cardsTable') < at(fk) && at(fk) < firstIndex, fk);
  });

  it('SICAK üst tablo kuralı: hiçbir ifade sites / users / site_people / apartments tablolarından birden fazlasını başvurmaz', () => {
    for (const name of CARD_ACCESS_DDL_ORDER) {
      const hot = new Set([...sql(name).matchAll(/REFERENCES (sites|users|site_people|apartments|site_blocks)\(/g)].map((match) => match[1]));
      assert.ok(hot.size <= 1, name);
    }
  });
});

describe('ensureCardAccessSchema (katalog kontrolü + yeniden deneme)', () => {
  const ALL_INDEXES = CARD_ACCESS_DDL_ORDER.filter((n) => /Index$/.test(n)).map((n) => /INDEX IF NOT EXISTS (\w+)/.exec(sql(n))[1]);
  const ALL_FKS = CARD_ACCESS_DDL_ORDER.filter((n) => n.endsWith('Fk')).map((n) => {
    const m = /conname = '(\w+)' AND conrelid = '(\w+)'::regclass/.exec(sql(n));
    return `${m[2]}.${m[1]}`;
  });
  const ALL_TABLES = ['access_cards', 'site_people'];

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

  it('3 indeks ve 3 FK adı beklenen kümedir', () => {
    assert.deepEqual(ALL_INDEXES, ['uq_access_cards_site_uid_active', 'idx_access_cards_person', 'idx_access_cards_site']);
    assert.deepEqual(ALL_FKS, ['access_cards.access_cards_site_code_fkey', 'access_cards.access_cards_person_id_fkey', 'access_cards.access_cards_created_by_fkey']);
  });

  it('her şey varsa (normal açılış) YALNIZ katalog sorgusu gider: DDL yok, kilit ayarı yok', async () => {
    const client = fakeClient({ tables: ALL_TABLES, indexes: ALL_INDEXES, fks: ALL_FKS });
    await ensureCardAccessSchema(client);
    assert.equal(client.log.length, 1);
    assert.match(client.log[0], /^SELECT ARRAY/);
  });

  it("hiçbiri yoksa: lock_timeout, 7 ifade TEK ayrı sorgu olarak SIRAYLA (tablo, 3 FK, 3 indeks), sonda RESET", async () => {
    const client = fakeClient({ tables: ['site_people'], indexes: [] });
    await ensureCardAccessSchema(client);
    assert.equal(client.log[1], "SET lock_timeout = '2s'");
    assert.equal(client.log[client.log.length - 1], 'RESET lock_timeout');
    assert.deepEqual(client.log.slice(2, -1), CARD_ACCESS_DDL_ORDER.map((name) => sql(name)));
  });

  it('yalnız eksik indeks / yalnız eksik FK varsa yalnız o ifade gider; tablo var ama hiç FK yoksa 3 FK sırayla tamamlanır', async () => {
    const missingIndex = fakeClient({ tables: ALL_TABLES, indexes: ALL_INDEXES.filter((n) => n !== 'idx_access_cards_person'), fks: ALL_FKS });
    await ensureCardAccessSchema(missingIndex);
    assert.deepEqual(ddlOf(missingIndex), [sql('cardsPersonIndex')]);
    const missingFk = fakeClient({ tables: ALL_TABLES, indexes: ALL_INDEXES, fks: ALL_FKS.filter((n) => n !== 'access_cards.access_cards_created_by_fkey') });
    await ensureCardAccessSchema(missingFk);
    assert.deepEqual(ddlOf(missingFk), [sql('cardsCreatedByFk')]);
    const noFks = fakeClient({ tables: ALL_TABLES, indexes: ALL_INDEXES, fks: [] });
    await ensureCardAccessSchema(noFks);
    assert.deepEqual(ddlOf(noFks), ['cardsSiteFk', 'cardsPersonFk', 'cardsCreatedByFk'].map((n) => sql(n)));
  });

  it("üst tablo (site_people) henüz yoksa yalnız o FK atlanır; tablo, diğer 2 FK ve 3 indeks kurulur", async () => {
    const client = fakeClient({ tables: [], indexes: [] });
    await ensureCardAccessSchema(client);
    const sent = ddlOf(client);
    assert.equal(sent.length, 6);
    const fkSent = sent.filter((statement) => /^DO/.test(statement));
    assert.equal(fkSent.length, 2);
    assert.ok(!fkSent.some((statement) => /REFERENCES site_people/.test(statement)));
  });

  it('40P01 / 55P03 geçici çakışmada yeniden dener; 6 denemeyi aşarsa hatayı fırlatır (RESET yine çalışır); başka hata ANINDA fırlar', async () => {
    const missing = { tables: ALL_TABLES, indexes: ALL_INDEXES, fks: ALL_FKS.filter((n) => n !== 'access_cards.access_cards_site_code_fkey') };
    const needle = 'ADD CONSTRAINT access_cards_site_code_fkey';
    const retry = fakeClient({ ...missing, failures: { [needle]: ['40P01', '55P03', '40P01'] } });
    await ensureCardAccessSchema(retry);
    assert.equal(retry.log.filter((statement) => statement.includes(needle)).length, 4);
    const hopeless = fakeClient({ ...missing, failures: { [needle]: Array(10).fill('40P01') } });
    await assert.rejects(ensureCardAccessSchema(hopeless), { code: '40P01' });
    assert.equal(hopeless.log.filter((statement) => statement.includes(needle)).length, 6);
    assert.equal(hopeless.log[hopeless.log.length - 1], 'RESET lock_timeout');
    const fatal = fakeClient({ ...missing, failures: { [needle]: ['42501'] } });
    await assert.rejects(ensureCardAccessSchema(fatal), { code: '42501' });
    assert.equal(fatal.log.filter((statement) => statement.includes(needle)).length, 1);
  });
});
