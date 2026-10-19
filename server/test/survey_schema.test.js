// Anket ve Oylama (044) şeması (DB'siz): migration 044 <-> survey_schema.js aynı DDL (aynı sıra), ekleyici / idempotent, sütun / kısıt / indeks ayrıntıları,
// AÇILIŞ 40P01 dersi (DDL dev ensureDbSchema bloğunda DEĞİL; katalog kontrolüyle yalnız EKSİKLER, kendi otomatik onaylı ifadeleriyle), yeniden deneme.
// Gerçek PostgreSQL doğrulaması: scripts/qa_platform_pg.mjs "survey" (+ "chain" / "live" şema eşitliği).
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { DEFAULT_MIGRATIONS_DIR, findUnsafeStatements, listMigrations } from '../scripts/migrate.js';
import { SURVEY_DDL, SURVEY_DDL_ORDER, ensureSurveySchema, schemaTuning } from '../src/modules/survey_schema.js';

schemaTuning.retryDelayMs = 1;

const here = path.dirname(fileURLToPath(import.meta.url));
const MIGRATION = readFileSync(path.join(DEFAULT_MIGRATIONS_DIR, '044_survey.sql'), 'utf8').replace(/\r\n/g, '\n');
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

const sql = (name) => normalizeSql(SURVEY_DDL[name]);

describe('migration 044: anket ve oylama', () => {
  it('044 var, çalıştırıcı için güvenli (üst düzey BEGIN/COMMIT yok), numara yinelenmez', () => {
    const list = listMigrations(DEFAULT_MIGRATIONS_DIR);
    const entry = list.find((m) => m.number === 44);
    assert.ok(entry, '044 numaralı migration yok');
    assert.equal(entry.file, '044_survey.sql');
    assert.equal(list.filter((m) => m.number === 44).length, 1);
    assert.deepEqual(findUnsafeStatements(MIGRATION), []);
  });

  it('SURVEY_DDL migration 044 ile AYNI ifadeleri taşır (yorumlar ve boşluklar dışında birebir, AYNI sırayla)', () => {
    const fromMigration = splitStatements(MIGRATION);
    assert.equal(fromMigration.length, 9);
    assert.deepEqual(fromMigration, SURVEY_DDL_ORDER.map((name) => normalizeSql(SURVEY_DDL[name])));
    assert.deepEqual(Object.keys(SURVEY_DDL), [...SURVEY_DDL_ORDER]);
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
    assert.equal((all.match(/ALTER TABLE (\w+)/g) ?? []).filter((entry) => !/ALTER TABLE (surveys|survey_votes)$/.test(entry)).length, 0);
    assert.equal((all.match(/ALTER TABLE/g) ?? []).length, 4);
  });

  it("AÇILIŞ 40P01 dersi: DDL dev blokta DEĞİL; db.js yalnız ensureSurveySchema(client) çağırır, rezervasyon şemasından SONRA ve people_v1'den ÖNCE", () => {
    const normalizedDb = normalizeSql(DB_SOURCE);
    for (const name of SURVEY_DDL_ORDER) {
      assert.equal(normalizedDb.includes(normalizeSql(SURVEY_DDL[name])), false, `${name} db.js içinde olmamalı`);
    }
    assert.equal(/CREATE TABLE IF NOT EXISTS survey(s|_votes)\b/.test(DB_SOURCE), false);
    assert.match(DB_SOURCE, /import \{ ensureSurveySchema \} from '\.\/modules\/survey_schema\.js';/);
    const calls = [...DB_SOURCE.matchAll(/await ensureSurveySchema\(client\);/g)];
    assert.equal(calls.length, 1);
    assert.ok(calls[0].index > DB_SOURCE.indexOf('await ensureReservationSchema(client);'));
    assert.ok(calls[0].index < DB_SOURCE.indexOf('await runPeopleBackfill(client);'));
  });
});

describe('şema ayrıntıları', () => {
  it('surveys: sütunlar, DB varsayılanları (draft / site / anonim), CHECK kümeleri, seçenek 2-10, kapanma tutarlılığı', () => {
    const surveys = sql('surveysTable');
    for (const fragment of [
      'id BIGSERIAL PRIMARY KEY',
      'site_code BIGINT NOT NULL',
      'options JSONB NOT NULL',
      "status TEXT NOT NULL DEFAULT 'draft'",
      "target_type TEXT NOT NULL DEFAULT 'site'",
      "target_block_ids BIGINT[] NOT NULL DEFAULT '{}'",
      "target_apartment_ids BIGINT[] NOT NULL DEFAULT '{}'",
      'anonymous BOOLEAN NOT NULL DEFAULT TRUE',
      'one_vote_per_apartment BOOLEAN NOT NULL DEFAULT FALSE',
      'closes_at TIMESTAMPTZ',
      'opened_at TIMESTAMPTZ',
      'closed_at TIMESTAMPTZ',
      'created_by INTEGER',
      'char_length(title) BETWEEN 1 AND 120',
      'char_length(question) BETWEEN 1 AND 1000',
      "jsonb_typeof(options) = 'array' AND jsonb_array_length(options) BETWEEN 2 AND 10",
      "status IN ('draft', 'open', 'closed')",
      "target_type IN ('site', 'blocks', 'apartments')",
      'cardinality(target_block_ids) <= 500 AND cardinality(target_apartment_ids) <= 500',
      "status = 'draft' OR opened_at IS NOT NULL",
      "(status = 'closed') = (closed_at IS NOT NULL)",
    ]) {
      assert.ok(surveys.includes(fragment), fragment);
    }
  });

  it('survey_votes: kullanıcı / daire isteğe bağlı (anonimleşme), seçenek 0-9, zaman varsayılan; ad / iletişim anlık görüntüsü YOK', () => {
    const votes = sql('votesTable');
    for (const fragment of ['survey_id BIGINT NOT NULL', 'user_code INTEGER', 'apartment_id BIGINT', 'option_index SMALLINT NOT NULL', 'voted_at TIMESTAMPTZ NOT NULL DEFAULT NOW()', 'option_index BETWEEN 0 AND 9']) {
      assert.ok(votes.includes(fragment), fragment);
    }
    assert.ok(!/user_code INTEGER NOT NULL/.test(votes), 'user_code NULL olabilmeli (hesap silinince anonimleşir)');
    assert.ok(!/name|phone|email/i.test(votes), 'oylarda ad / iletişim anlık görüntüsü YOK');
  });

  it('indeksler: (site, durum, id DESC); kısmi TEKİL (anket, kullanıcı) WHERE user_code IS NOT NULL; (anket, daire)', () => {
    assert.equal(sql('surveysSiteStatusIndex'), 'CREATE INDEX IF NOT EXISTS idx_surveys_site_status ON surveys (site_code, status, id DESC)');
    assert.equal(sql('votesUserUniqueIndex'), 'CREATE UNIQUE INDEX IF NOT EXISTS uq_survey_votes_user ON survey_votes (survey_id, user_code) WHERE user_code IS NOT NULL');
    assert.equal(sql('votesApartmentIndex'), 'CREATE INDEX IF NOT EXISTS idx_survey_votes_apartment ON survey_votes (survey_id, apartment_id)');
  });
});

describe("yabancı anahtarlar (R11 F1): tablolar FK'SIZ, her FK ayrı katalog korumalı ifade", () => {
  const EXPECTED_FKS = [
    ['surveys', 'site_code', 'sites', 'site_code', 'CASCADE'],
    ['surveys', 'created_by', 'users', 'user_code', 'SET NULL'],
    ['survey_votes', 'survey_id', 'surveys', 'id', 'CASCADE'],
    ['survey_votes', 'user_code', 'users', 'user_code', 'SET NULL'],
  ];
  const FK_STEPS = SURVEY_DDL_ORDER.filter((name) => name.endsWith('Fk'));

  it('hiçbir CREATE TABLE satır içi REFERENCES taşımaz; apartment_id bilinçli olarak FK\'sız', () => {
    for (const name of ['surveysTable', 'votesTable']) assert.ok(!/REFERENCES/i.test(SURVEY_DDL[name]), name);
    assert.ok(!FK_STEPS.some((name) => /\(apartment_id\)/.test(sql(name))));
  });

  it("4 FK ifadesi: ifade başına TEK başvuru, ad <tablo>_<sütun>_fkey, katalog korumalı, beklenen üst tablo / ON DELETE; her tablonun FK'leri tablodan HEMEN sonra, indekslerinden ÖNCE", () => {
    assert.equal(FK_STEPS.length, 4);
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
    const at = (name) => SURVEY_DDL_ORDER.indexOf(name);
    for (const fk of ['surveysSiteFk', 'surveysCreatedByFk']) assert.ok(at('surveysTable') < at(fk) && at(fk) < at('surveysSiteStatusIndex'), fk);
    for (const fk of ['votesSurveyFk', 'votesUserFk']) assert.ok(at('votesTable') < at(fk) && at(fk) < at('votesUserUniqueIndex') && at('surveysTable') < at(fk), fk);
  });

  it('SICAK üst tablo kuralı: hiçbir ifade sites / users\'tan birden fazlasını başvurmaz', () => {
    for (const name of SURVEY_DDL_ORDER) {
      const hot = new Set([...sql(name).matchAll(/REFERENCES (sites|users|apartments|site_blocks)\(/g)].map((match) => match[1]));
      assert.ok(hot.size <= 1, name);
    }
  });
});

describe('ensureSurveySchema (katalog kontrolü + yeniden deneme)', () => {
  const ALL_INDEXES = SURVEY_DDL_ORDER.filter((n) => /Index$/.test(n)).map((n) => /INDEX IF NOT EXISTS (\w+)/.exec(sql(n))[1]);
  const ALL_FKS = ['surveys.surveys_site_code_fkey', 'surveys.surveys_created_by_fkey', 'survey_votes.survey_votes_survey_id_fkey', 'survey_votes.survey_votes_user_code_fkey'];
  const ALL_TABLES = ['surveys', 'survey_votes'];

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

  it('3 indeks adı beklenen kümedir', () => {
    assert.deepEqual(ALL_INDEXES, ['idx_surveys_site_status', 'uq_survey_votes_user', 'idx_survey_votes_apartment']);
  });

  it('her şey varsa (normal açılış) YALNIZ katalog sorgusu gider: DDL yok, kilit ayarı yok', async () => {
    const client = fakeClient({ tables: ALL_TABLES, indexes: ALL_INDEXES, fks: ALL_FKS });
    await ensureSurveySchema(client);
    assert.equal(client.log.length, 1);
    assert.match(client.log[0], /^SELECT ARRAY/);
  });

  it("hiçbiri yoksa: lock_timeout, her ifade TEK ayrı sorgu olarak SIRAYLA (tablo, FK'leri, indeksleri), sonda RESET", async () => {
    const client = fakeClient({ tables: [], indexes: [] });
    await ensureSurveySchema(client);
    assert.equal(client.log[1], "SET lock_timeout = '2s'");
    assert.equal(client.log[client.log.length - 1], 'RESET lock_timeout');
    assert.deepEqual(client.log.slice(2, -1), SURVEY_DDL_ORDER.map((name) => sql(name)));
  });

  it('yalnız eksik indeks / yalnız eksik FK varsa yalnız o ifade gider; tablolar var ama hiç FK yoksa 4 FK sırayla tamamlanır', async () => {
    const missingIndex = fakeClient({ tables: ALL_TABLES, indexes: ALL_INDEXES.filter((n) => n !== 'uq_survey_votes_user'), fks: ALL_FKS });
    await ensureSurveySchema(missingIndex);
    assert.deepEqual(ddlOf(missingIndex), [sql('votesUserUniqueIndex')]);
    const missingFk = fakeClient({ tables: ALL_TABLES, indexes: ALL_INDEXES, fks: ALL_FKS.filter((n) => n !== 'survey_votes.survey_votes_user_code_fkey') });
    await ensureSurveySchema(missingFk);
    assert.deepEqual(ddlOf(missingFk), [sql('votesUserFk')]);
    const noFks = fakeClient({ tables: ALL_TABLES, indexes: ALL_INDEXES, fks: [] });
    await ensureSurveySchema(noFks);
    assert.deepEqual(ddlOf(noFks), SURVEY_DDL_ORDER.filter((n) => n.endsWith('Fk')).map((n) => sql(n)));
  });

  it('40P01 / 55P03 geçici çakışmada yeniden dener; 6 denemeyi aşarsa hatayı fırlatır (RESET yine çalışır); başka hata ANINDA fırlar', async () => {
    const missing = { tables: ALL_TABLES, indexes: ALL_INDEXES, fks: ALL_FKS.filter((n) => n !== 'surveys.surveys_site_code_fkey') };
    const retry = fakeClient({ ...missing, failures: { 'ADD CONSTRAINT surveys_site_code_fkey': ['40P01', '55P03', '40P01'] } });
    await ensureSurveySchema(retry);
    assert.equal(retry.log.filter((statement) => statement.includes('ADD CONSTRAINT surveys_site_code_fkey')).length, 4);
    const hopeless = fakeClient({ ...missing, failures: { 'ADD CONSTRAINT surveys_site_code_fkey': Array(10).fill('40P01') } });
    await assert.rejects(ensureSurveySchema(hopeless), { code: '40P01' });
    assert.equal(hopeless.log.filter((statement) => statement.includes('ADD CONSTRAINT surveys_site_code_fkey')).length, 6);
    assert.equal(hopeless.log[hopeless.log.length - 1], 'RESET lock_timeout');
    const fatal = fakeClient({ ...missing, failures: { 'ADD CONSTRAINT surveys_site_code_fkey': ['42501'] } });
    await assert.rejects(ensureSurveySchema(fatal), { code: '42501' });
    assert.equal(fatal.log.filter((statement) => statement.includes('ADD CONSTRAINT surveys_site_code_fkey')).length, 1);
  });
});
