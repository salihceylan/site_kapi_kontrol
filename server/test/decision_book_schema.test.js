// Karar Defteri (050) şeması (DB'siz): migration 050 <-> decision_book_schema.js aynı DDL (aynı sıra), ekleyici / idempotent, sütun / kısıt / indeks ayrıntıları,
// değişmezlik tetikleyicisi (kesin satır UPDATE / DELETE yalnız FK SET NULL ve site silme istisnalarıyla), AÇILIŞ 40P01 dersi (DDL dev ensureDbSchema bloğunda DEĞİL;
// katalog kontrolüyle yalnız EKSİKLER, kendi otomatik onaylı ifadeleriyle), yeniden deneme.
// Gerçek PostgreSQL doğrulaması: scripts/qa_platform_pg.mjs "decision_book" (+ "chain" / "live" şema eşitliği).
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { DEFAULT_MIGRATIONS_DIR, findUnsafeStatements, listMigrations } from '../scripts/migrate.js';
import { DECISION_BOOK_DDL, DECISION_BOOK_DDL_ORDER, DECISION_BOOK_MARKER, ensureDecisionBookSchema, schemaTuning } from '../src/modules/decision_book_schema.js';

schemaTuning.retryDelayMs = 1;

const here = path.dirname(fileURLToPath(import.meta.url));
const MIGRATION = readFileSync(path.join(DEFAULT_MIGRATIONS_DIR, '050_decision_book.sql'), 'utf8').replace(/\r\n/g, '\n');
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

const sql = (name) => normalizeSql(DECISION_BOOK_DDL[name]);

describe('migration 050: karar defteri', () => {
  it('050 var, çalıştırıcı için güvenli (üst düzey BEGIN/COMMIT yok), numara yinelenmez', () => {
    const list = listMigrations(DEFAULT_MIGRATIONS_DIR);
    const entry = list.find((m) => m.number === 50);
    assert.ok(entry, '050 numaralı migration yok');
    assert.equal(entry.file, '050_decision_book.sql');
    assert.equal(list.filter((m) => m.number === 50).length, 1);
    assert.deepEqual(findUnsafeStatements(MIGRATION), []);
  });

  it('DECISION_BOOK_DDL migration 050 ile AYNI ifadeleri taşır (yorumlar ve boşluklar dışında birebir, AYNI sırayla): tablo, 4 FK, 5 indeks, 2 işlev, 2 tetikleyici', () => {
    const fromMigration = splitStatements(MIGRATION);
    assert.equal(fromMigration.length, 14);
    assert.deepEqual(fromMigration, DECISION_BOOK_DDL_ORDER.map((name) => normalizeSql(DECISION_BOOK_DDL[name])));
    assert.deepEqual(Object.keys(DECISION_BOOK_DDL), [...DECISION_BOOK_DDL_ORDER]);
  });

  it('işlev gövdeleri sürüm işaretini taşır (migration metninde de); migration noter uyarısını yorumda tekrarlar', () => {
    assert.equal(DECISION_BOOK_MARKER, 'dbk:1');
    for (const name of ['immutableFunction', 'truncateFunction']) {
      assert.ok(DECISION_BOOK_DDL[name].includes(`-- ${DECISION_BOOK_MARKER}`), name);
    }
    assert.equal((MIGRATION.match(/-- dbk:1/g) ?? []).length, 2);
    assert.match(MIGRATION, /noter onayli karar defterinin yerine gecmez/);
  });

  it('EKLEMELİ ve idempotent: CREATE TABLE / INDEX IF NOT EXISTS, CREATE OR REPLACE FUNCTION, katalog korumalı FK / tetikleyici; DROP / UPDATE / DELETE / INSERT YOK', () => {
    for (const statement of splitStatements(MIGRATION)) {
      assert.match(
        statement,
        /^(CREATE (UNIQUE )?(TABLE|INDEX) IF NOT EXISTS |CREATE OR REPLACE FUNCTION trg_board_decisions_\w+\(\) RETURNS trigger AS \$\$|DO \$\$ BEGIN IF NOT EXISTS \( SELECT 1 FROM pg_(constraint WHERE conname = '\w+_fkey'|trigger WHERE tgname = 'trg_board_decisions_\w+') AND (conrelid|tgrelid) = 'board_decisions'::regclass( AND NOT tgisinternal)? \) THEN (ALTER TABLE board_decisions ADD CONSTRAINT|CREATE TRIGGER) )/,
      );
    }
    const all = normalizeSql(MIGRATION);
    assert.ok(!/\b(DROP|UPDATE board_decisions|DELETE FROM|INSERT INTO)\b/i.test(all));
    assert.equal((all.match(/ALTER TABLE (\w+)/g) ?? []).filter((entry) => entry !== 'ALTER TABLE board_decisions').length, 0);
    assert.equal((all.match(/ALTER TABLE/g) ?? []).length, 4);
  });

  it("AÇILIŞ 40P01 dersi: DDL dev blokta DEĞİL; db.js yalnız ensureDecisionBookSchema(client) çağırır, 047 ensure'dan SONRA ve people_v1'den ÖNCE", () => {
    const normalizedDb = normalizeSql(DB_SOURCE);
    for (const name of DECISION_BOOK_DDL_ORDER) {
      assert.equal(normalizedDb.includes(normalizeSql(DECISION_BOOK_DDL[name])), false, `${name} db.js içinde olmamalı`);
    }
    assert.equal(/CREATE TABLE IF NOT EXISTS board_decisions\b/.test(DB_SOURCE), false);
    assert.match(DB_SOURCE, /import \{ ensureDecisionBookSchema \} from '\.\/modules\/decision_book_schema\.js';/);
    const calls = [...DB_SOURCE.matchAll(/await ensureDecisionBookSchema\(client\);/g)];
    assert.equal(calls.length, 1);
    assert.ok(calls[0].index > DB_SOURCE.indexOf('await ensureWorkAttachmentsSchema(client);'));
    assert.ok(calls[0].index < DB_SOURCE.indexOf('await runPeopleBackfill(client);'));
  });
});

describe('şema ayrıntıları', () => {
  it('board_decisions: sütunlar, CHECK kümeleri, kesin <-> numara + zaman tutarlılığı, yıl = toplantı yılı, varsayılanlar', () => {
    const table = sql('decisionsTable');
    for (const fragment of [
      'id BIGSERIAL PRIMARY KEY',
      'site_code BIGINT NOT NULL',
      'year INTEGER NOT NULL',
      'decision_no INTEGER,',
      'meeting_type TEXT NOT NULL',
      'meeting_date DATE NOT NULL',
      'title TEXT NOT NULL',
      'body TEXT NOT NULL',
      'attendees TEXT,',
      'vote_result TEXT NOT NULL',
      'votes_for INTEGER,',
      'votes_against INTEGER,',
      'votes_abstain INTEGER,',
      "visibility TEXT NOT NULL DEFAULT 'yonetim'",
      "status TEXT NOT NULL DEFAULT 'taslak'",
      'finalized_at TIMESTAMPTZ,',
      'finalized_by INTEGER,',
      'supersedes_id BIGINT,',
      'created_by INTEGER,',
      'created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()',
      'updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()',
      'CONSTRAINT uq_board_decisions_site_id UNIQUE (site_code, id)',
      "meeting_type IN ('yonetim_kurulu', 'genel_kurul', 'denetim_kurulu', 'diger')",
      "vote_result IN ('kabul', 'ret', 'ertelendi', 'bilgi')",
      "visibility IN ('yonetim', 'sakinler')",
      "status IN ('taslak', 'kesin')",
      'char_length(title) BETWEEN 1 AND 160',
      'char_length(body) BETWEEN 1 AND 10000',
      'attendees IS NULL OR char_length(attendees) BETWEEN 1 AND 2000',
      '(votes_for IS NULL OR votes_for >= 0) AND (votes_against IS NULL OR votes_against >= 0) AND (votes_abstain IS NULL OR votes_abstain >= 0)',
      'year BETWEEN 1900 AND 2200 AND year = EXTRACT(YEAR FROM meeting_date)',
      'decision_no IS NULL OR decision_no > 0',
      "(status = 'kesin') = (decision_no IS NOT NULL) AND (status = 'kesin') = (finalized_at IS NOT NULL)",
      'supersedes_id IS NULL OR supersedes_id <> id',
    ]) {
      assert.ok(table.includes(fragment), fragment);
    }
    assert.ok(!/REFERENCES/i.test(table), 'tablo FK taşımaz');
  });

  it('indeksler: (site, yıl, numara) TEKİL (yalnız numaralı), taslaklar, değiştirilen, kullanıcı FK sütunları', () => {
    assert.equal(sql('decisionsNumberIndex'), 'CREATE UNIQUE INDEX IF NOT EXISTS uq_board_decisions_number ON board_decisions (site_code, year, decision_no) WHERE decision_no IS NOT NULL');
    assert.equal(sql('decisionsDraftsIndex'), "CREATE INDEX IF NOT EXISTS idx_board_decisions_drafts ON board_decisions (site_code, year DESC, id DESC) WHERE status = 'taslak'");
    assert.equal(sql('decisionsSupersedesIndex'), 'CREATE INDEX IF NOT EXISTS idx_board_decisions_supersedes ON board_decisions (site_code, supersedes_id) WHERE supersedes_id IS NOT NULL');
    assert.equal(sql('decisionsCreatedByIndex'), 'CREATE INDEX IF NOT EXISTS idx_board_decisions_created_by ON board_decisions (created_by) WHERE created_by IS NOT NULL');
    assert.equal(sql('decisionsFinalizedByIndex'), 'CREATE INDEX IF NOT EXISTS idx_board_decisions_finalized_by ON board_decisions (finalized_by) WHERE finalized_by IS NOT NULL');
  });

  it('değişmezlik işlevi: taslak serbest; kesin DELETE yalnız site YOKSA; kesin UPDATE yalnız created_by / finalized_by NULL + kullanıcı YOK + başka sütun aynı; aksi hata', () => {
    const fn = sql('immutableFunction');
    assert.match(fn, /IF OLD\.status <> 'kesin' THEN IF TG_OP = 'DELETE' THEN RETURN OLD; END IF; RETURN NEW; END IF;/);
    assert.match(fn, /IF TG_OP = 'DELETE' THEN IF NOT EXISTS \(SELECT 1 FROM sites WHERE site_code = OLD\.site_code\) THEN RETURN OLD; END IF;/);
    assert.match(fn, /FOREACH col IN ARRAY ARRAY\['created_by', 'finalized_by'\] LOOP/);
    assert.match(fn, /NOT EXISTS \(SELECT 1 FROM users WHERE user_code = \(old_json ->> col\)::INTEGER\) AND \(new_json - col\) = \(old_json - col\) THEN RETURN NEW;/);
    assert.match(fn, /RAISE EXCEPTION 'final board decisions are immutable'; END; \$\$ LANGUAGE plpgsql$/);
    assert.match(sql('truncateFunction'), /RAISE EXCEPTION 'board decisions cannot be truncated';/);
  });

  it('tetikleyiciler: BEFORE UPDATE OR DELETE (satır) ve BEFORE TRUNCATE (ifade); ikisi de katalog korumalı', () => {
    assert.match(sql('immutableTrigger'), /CREATE TRIGGER trg_board_decisions_immutable BEFORE UPDATE OR DELETE ON board_decisions FOR EACH ROW EXECUTE PROCEDURE trg_board_decisions_immutable\(\);/);
    assert.match(sql('truncateTrigger'), /CREATE TRIGGER trg_board_decisions_no_truncate BEFORE TRUNCATE ON board_decisions FOR EACH STATEMENT EXECUTE PROCEDURE trg_board_decisions_block_truncate\(\);/);
  });
});

describe("yabancı anahtarlar (R11 F1): tablo FK'SIZ, her FK ayrı katalog korumalı ifade", () => {
  const FK_STEPS = DECISION_BOOK_DDL_ORDER.filter((name) => name.endsWith('Fk'));

  it("4 FK: site CASCADE; created_by / finalized_by users SET NULL; değiştirilen karar BİLEŞİK (site_code, supersedes_id) -> (site_code, id) NO ACTION; FK'ler tablodan hemen sonra", () => {
    assert.deepEqual(FK_STEPS, ['decisionsSiteFk', 'decisionsCreatedByFk', 'decisionsFinalizedByFk', 'decisionsSupersedesFk']);
    const parsed = FK_STEPS.map((name) => {
      const text = sql(name);
      assert.equal((text.match(/REFERENCES/g) ?? []).length, 1);
      const match = /conname = '(\w+)' AND conrelid = '(\w+)'::regclass \) THEN ALTER TABLE (\w+) ADD CONSTRAINT (\w+) FOREIGN KEY \(([\w, ]+)\) REFERENCES (\w+)\(([\w, ]+)\) ON DELETE (CASCADE|SET NULL|NO ACTION); END IF; END \$\$$/.exec(text);
      assert.ok(match, `${name}: biçim`);
      const [, guard, guardTable, table, constraint, columns, parent, parentColumns, onDelete] = match;
      assert.equal(guard, constraint);
      assert.equal(guardTable, table);
      return [constraint, columns, parent, parentColumns, onDelete];
    });
    assert.deepEqual(parsed, [
      ['board_decisions_site_code_fkey', 'site_code', 'sites', 'site_code', 'CASCADE'],
      ['board_decisions_created_by_fkey', 'created_by', 'users', 'user_code', 'SET NULL'],
      ['board_decisions_finalized_by_fkey', 'finalized_by', 'users', 'user_code', 'SET NULL'],
      ['board_decisions_supersedes_id_fkey', 'site_code, supersedes_id', 'board_decisions', 'site_code, id', 'NO ACTION'],
    ]);
    const at = (name) => DECISION_BOOK_DDL_ORDER.indexOf(name);
    for (const fk of FK_STEPS) assert.ok(at('decisionsTable') < at(fk) && at(fk) < at('decisionsNumberIndex'), fk);
  });

  it('SICAK üst tablo kuralı: hiçbir ifade sites / users / apartments tablolarından birden fazlasını başvurmaz', () => {
    for (const name of DECISION_BOOK_DDL_ORDER) {
      const hot = new Set([...sql(name).matchAll(/REFERENCES (sites|users|apartments)\(/g)].map((match) => match[1]));
      assert.ok(hot.size <= 1, name);
    }
  });
});

describe('ensureDecisionBookSchema (katalog kontrolü + yeniden deneme)', () => {
  const ALL_INDEXES = ['uq_board_decisions_number', 'idx_board_decisions_drafts', 'idx_board_decisions_supersedes', 'idx_board_decisions_created_by', 'idx_board_decisions_finalized_by'];
  const ALL_FKS = [
    'board_decisions.board_decisions_site_code_fkey',
    'board_decisions.board_decisions_created_by_fkey',
    'board_decisions.board_decisions_finalized_by_fkey',
    'board_decisions.board_decisions_supersedes_id_fkey',
  ];
  const ALL_FUNCTIONS = ['trg_board_decisions_immutable', 'trg_board_decisions_block_truncate'];
  const ALL_TRIGGERS = ['trg_board_decisions_immutable', 'trg_board_decisions_no_truncate'];
  const COMPLETE = { tables: ['board_decisions'], indexes: ALL_INDEXES, fks: ALL_FKS, functions: ALL_FUNCTIONS, triggers: ALL_TRIGGERS };

  function fakeClient({ tables = [], indexes = [], fks = [], functions = [], triggers = [], failures = {} }) {
    const log = [];
    const params = [];
    return {
      log,
      params,
      async query(text, values) {
        const statement = normalizeSql(text);
        log.push(statement);
        params.push(values);
        if (/^SELECT ARRAY/.test(statement)) return { rows: [{ tables, indexes, fks, functions, triggers }] };
        if (/^SET lock_timeout|^RESET lock_timeout/.test(statement)) return { rows: [] };
        const key = Object.keys(failures).find((needle) => statement.includes(needle));
        if (key && failures[key].length > 0) throw Object.assign(new Error('enjekte'), { code: failures[key].shift() });
        return { rows: [] };
      },
    };
  }
  const ddlOf = (client) => client.log.filter((statement) => /^(CREATE|DO)/.test(statement));

  it('katalog sorgusu indeks / FK / işlev / tetikleyici adlarını ve sürüm işaretini parametre olarak taşır', async () => {
    const client = fakeClient(COMPLETE);
    await ensureDecisionBookSchema(client);
    const [tables, indexes, fks, functions, triggers, marker] = client.params[0];
    assert.deepEqual(tables, ['board_decisions']);
    assert.deepEqual(indexes, ALL_INDEXES);
    assert.deepEqual(fks, ALL_FKS.map((entry) => entry.split('.')[1]));
    assert.deepEqual(functions, ALL_FUNCTIONS);
    assert.deepEqual(triggers, ALL_TRIGGERS);
    assert.equal(marker, DECISION_BOOK_MARKER);
    assert.match(client.log[0], /p\.prosrc LIKE '%' \|\| \$6 \|\| '%'/);
  });

  it('her şey varsa (normal açılış) YALNIZ katalog sorgusu gider: DDL yok, kilit ayarı yok', async () => {
    const client = fakeClient(COMPLETE);
    await ensureDecisionBookSchema(client);
    assert.equal(client.log.length, 1);
    assert.match(client.log[0], /^SELECT ARRAY/);
  });

  it('hiçbiri yoksa: lock_timeout, her ifade TEK ayrı sorgu olarak SIRAYLA (tablo, FK, indeks, işlev, tetikleyici), sonda RESET', async () => {
    const client = fakeClient({});
    await ensureDecisionBookSchema(client);
    assert.equal(client.log[1], "SET lock_timeout = '2s'");
    assert.equal(client.log[client.log.length - 1], 'RESET lock_timeout');
    assert.deepEqual(client.log.slice(2, -1), DECISION_BOOK_DDL_ORDER.map((name) => sql(name)));
  });

  it('yalnız eksik nesne gider: indeks / FK / eski işaretli işlev (yenilenir) / tetikleyici', async () => {
    const missingIndex = fakeClient({ ...COMPLETE, indexes: ALL_INDEXES.filter((n) => n !== 'idx_board_decisions_drafts') });
    await ensureDecisionBookSchema(missingIndex);
    assert.deepEqual(ddlOf(missingIndex), [sql('decisionsDraftsIndex')]);
    const missingFk = fakeClient({ ...COMPLETE, fks: ALL_FKS.filter((n) => !n.endsWith('supersedes_id_fkey')) });
    await ensureDecisionBookSchema(missingFk);
    assert.deepEqual(ddlOf(missingFk), [sql('decisionsSupersedesFk')]);
    const oldFunction = fakeClient({ ...COMPLETE, functions: ['trg_board_decisions_block_truncate'] });
    await ensureDecisionBookSchema(oldFunction);
    assert.deepEqual(ddlOf(oldFunction), [sql('immutableFunction')]);
    const missingTrigger = fakeClient({ ...COMPLETE, triggers: ['trg_board_decisions_immutable'] });
    await ensureDecisionBookSchema(missingTrigger);
    assert.deepEqual(ddlOf(missingTrigger), [sql('truncateTrigger')]);
  });

  it('40P01 / 55P03 geçici çakışmada yeniden dener; 6 denemeyi aşarsa hatayı fırlatır (RESET yine çalışır); başka hata ANINDA fırlar', async () => {
    const missing = { ...COMPLETE, fks: ALL_FKS.filter((n) => !n.endsWith('site_code_fkey')) };
    const needle = 'ADD CONSTRAINT board_decisions_site_code_fkey';
    const retry = fakeClient({ ...missing, failures: { [needle]: ['40P01', '55P03', '40P01'] } });
    await ensureDecisionBookSchema(retry);
    assert.equal(retry.log.filter((statement) => statement.includes(needle)).length, 4);
    const hopeless = fakeClient({ ...missing, failures: { [needle]: Array(10).fill('40P01') } });
    await assert.rejects(ensureDecisionBookSchema(hopeless), { code: '40P01' });
    assert.equal(hopeless.log.filter((statement) => statement.includes(needle)).length, 6);
    assert.equal(hopeless.log[hopeless.log.length - 1], 'RESET lock_timeout');
    const fatal = fakeClient({ ...missing, failures: { [needle]: ['42501'] } });
    await assert.rejects(ensureDecisionBookSchema(fatal), { code: '42501' });
    assert.equal(fatal.log.filter((statement) => statement.includes(needle)).length, 1);
  });
});
