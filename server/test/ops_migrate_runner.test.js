// scripts/migrate.js birim testleri.
// GERCEK VERITABANINA BAGLANMAZ: DB katmani sahte (fake) bir istemciyle
// enjekte edilir (main(argv, env, { openClient, confirm, log, logError })).
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {
  DEFAULT_MIGRATIONS_DIR,
  checksumOf,
  dbConfigFromEnv,
  describeTarget,
  findUnsafeStatements,
  listMigrations,
  main,
  normalizeSql,
  parseArgs,
  planMigrations,
} from '../scripts/migrate.js';

const FAKE_ENV = { DB_HOST: 'db.test', DB_PORT: '5432', DB_NAME: 'appdb', DB_USER: 'appuser', DB_PASSWORD: 'p@ss-secret' };

function makeMigrationDir(files) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'migrate-test-'));
  for (const [name, content] of Object.entries(files)) {
    fs.writeFileSync(path.join(dir, name), content, 'utf8');
  }
  return dir;
}

// Sahte pg istemcisi: yalnizca migrate.js'in kullandigi sorgu kaliplarini taniyor.
function makeFakeDb({ tablePresent = false, usersPresent = false, applied = [], failOn = null } = {}) {
  const state = {
    tablePresent,
    usersPresent,
    applied: applied.map((row) => ({ ...row })),
    calls: [],
    ended: false,
    inTx: false,
    stagedInserts: [],
    executedMigrationSql: [],
  };
  const client = {
    async query(sql, params = []) {
      const text = String(sql).replace(/\s+/g, ' ').trim();
      state.calls.push(text);
      if (/^SET lock_timeout/i.test(text) || /pg_advisory_lock/i.test(text)) return { rows: [] };
      if (/to_regclass/i.test(text)) {
        const name = String(params[0]);
        if (name === 'public.schema_migrations') return { rows: [{ present: state.tablePresent }] };
        if (name === 'public.users') return { rows: [{ present: state.usersPresent }] };
        return { rows: [{ present: false }] };
      }
      if (/^SELECT version, checksum/i.test(text)) return { rows: state.applied.map((row) => ({ ...row })) };
      if (/^CREATE TABLE IF NOT EXISTS schema_migrations/i.test(text)) {
        state.tablePresent = true;
        return { rows: [] };
      }
      if (text === 'BEGIN') {
        state.inTx = true;
        state.stagedInserts = [];
        return { rows: [] };
      }
      if (text === 'COMMIT') {
        state.inTx = false;
        state.applied.push(...state.stagedInserts);
        state.stagedInserts = [];
        return { rows: [] };
      }
      if (text === 'ROLLBACK') {
        state.inTx = false;
        state.stagedInserts = [];
        return { rows: [] };
      }
      if (/^INSERT INTO schema_migrations/i.test(text)) {
        const [version, checksum] = params;
        if (!state.applied.some((row) => row.version === version)) {
          state.stagedInserts.push({ version, checksum, applied_at: new Date() });
        }
        return { rows: [] };
      }
      // Geri kalan: migration SQL govdesi
      if (failOn && text.includes(failOn)) throw new Error('simulated failure');
      state.executedMigrationSql.push(text);
      return { rows: [] };
    },
    async end() {
      state.ended = true;
    },
  };
  return { state, client, openClient: async () => client };
}

function makeDeps(db, { confirmAnswer = true } = {}) {
  const logs = [];
  const errors = [];
  let confirmCalls = 0;
  return {
    logs,
    errors,
    confirmCalls: () => confirmCalls,
    deps: {
      openClient: db.openClient,
      log: (m) => logs.push(String(m)),
      logError: (m) => errors.push(String(m)),
      confirm: async () => {
        confirmCalls += 1;
        return confirmAnswer;
      },
    },
  };
}

const DIR_FILES = {
  '001_first.sql': 'CREATE TABLE users (id INT);\n',
  '002_second.sql': 'ALTER TABLE users ADD COLUMN a INT;\r\n',
  '003_third.sql': 'ALTER TABLE users ADD COLUMN b INT;\n',
};

describe('parseArgs', () => {
  it('modlari ve bayraklari ayristirir', () => {
    assert.equal(parseArgs(['--status']).opts.mode, 'status');
    const apply = parseArgs(['--apply', '--dry-run', '--yes']);
    assert.equal(apply.opts.mode, 'apply');
    assert.equal(apply.opts.dryRun, true);
    assert.equal(apply.opts.yes, true);
    const baseline = parseArgs(['--baseline', '25']);
    assert.equal(baseline.opts.mode, 'baseline');
    assert.equal(baseline.opts.baseline, 25);
    assert.deepEqual(baseline.errors, []);
  });

  it('hatali kullanimlari reddeder', () => {
    assert.ok(parseArgs(['--apply', '--status']).errors.length > 0);
    assert.ok(parseArgs(['--baseline']).errors.length > 0);
    assert.ok(parseArgs(['--baseline', 'abc']).errors.length > 0);
    assert.ok(parseArgs(['--baseline', '0']).errors.length > 0);
    assert.ok(parseArgs(['--status', '--dry-run']).errors.length > 0);
    assert.ok(parseArgs(['--bilinmeyen']).errors.length > 0);
  });
});

describe('checksum / normalizasyon', () => {
  it('BOM ve satir sonu farki checksum degistirmez', () => {
    const lf = 'SELECT 1;\nSELECT 2;\n';
    const crlfBom = String.fromCharCode(0xfeff) + 'SELECT 1;\r\nSELECT 2;\r\n';
    assert.equal(normalizeSql(crlfBom), lf);
    assert.equal(checksumOf(crlfBom), checksumOf(lf));
    assert.notEqual(checksumOf(lf), checksumOf('SELECT 1;\n'));
  });
});

describe('listMigrations', () => {
  it('gercek migrations klasoru: ardisik, sirali, tekrarsiz', () => {
    const list = listMigrations(DEFAULT_MIGRATIONS_DIR);
    assert.ok(list.length >= 25);
    for (let i = 0; i < list.length; i += 1) {
      assert.equal(list[i].number, i + 1, `numara boslugu: ${list[i].file}`);
      assert.match(list[i].checksum, /^[0-9a-f]{64}$/);
    }
  });

  it('gecersiz dosya adi ve tekrarlanan numara hata verir', () => {
    assert.throws(() => listMigrations(makeMigrationDir({ 'abc.sql': 'SELECT 1;' })), /Gecersiz migration dosya adi/);
    assert.throws(
      () => listMigrations(makeMigrationDir({ '001_a.sql': 'SELECT 1;', '001_b.sql': 'SELECT 2;' })),
      /Ayni numarali/,
    );
    assert.throws(() => listMigrations(path.join(os.tmpdir(), 'yok-boyle-bir-klasor-xyz')), /bulunamadi/);
  });

  it('sql olmayan dosyalari yok sayar', () => {
    const list = listMigrations(makeMigrationDir({ '001_a.sql': 'SELECT 1;', 'README.md': '# x' }));
    assert.equal(list.length, 1);
  });
});

describe('findUnsafeStatements', () => {
  it('DO $$ ... BEGIN ... END $$ bloklari ve yorum/metin icindeki BEGIN guvenlidir', () => {
    assert.deepEqual(findUnsafeStatements("DO $$ BEGIN PERFORM 1; END $$;"), []);
    assert.deepEqual(findUnsafeStatements("-- BEGIN;\nSELECT 'COMMIT;';"), []);
    assert.deepEqual(findUnsafeStatements('/* BEGIN; */ SELECT 1;'), []);
    assert.deepEqual(findUnsafeStatements("DO $fn$ BEGIN RAISE NOTICE 'COMMIT;'; END $fn$;"), []);
  });

  it('ust duzey BEGIN/COMMIT/CONCURRENTLY/VACUUM isaretlenir', () => {
    assert.equal(findUnsafeStatements('BEGIN;\nSELECT 1;\nCOMMIT;').length, 2);
    assert.equal(findUnsafeStatements('CREATE INDEX CONCURRENTLY i ON t(a);').length, 1);
    assert.equal(findUnsafeStatements('VACUUM t;').length, 1);
    assert.equal(findUnsafeStatements('START TRANSACTION;').length, 1);
  });

  it('depodaki tum migration dosyalari tek transaction icinde calistirilabilir', () => {
    for (const migration of listMigrations(DEFAULT_MIGRATIONS_DIR)) {
      assert.deepEqual(findUnsafeStatements(migration.sql), [], migration.file);
    }
  });
});

describe('planMigrations', () => {
  it('uygulanmis / bekleyen / degismis / bilinmeyen ayrimi', () => {
    const local = [
      { version: '001_a', number: 1, checksum: 'a' },
      { version: '002_b', number: 2, checksum: 'b' },
      { version: '003_c', number: 3, checksum: 'c' },
    ];
    const plan = planMigrations(local, [
      { version: '001_a', checksum: 'a' },
      { version: '002_b', checksum: 'DEGISMIS' },
      { version: '000_eski', checksum: 'z' },
    ]);
    assert.equal(plan.applied.length, 2);
    assert.deepEqual(plan.pending.map((m) => m.version), ['003_c']);
    assert.deepEqual(plan.changed.map((m) => m.version), ['002_b']);
    assert.deepEqual(plan.unknown.map((r) => r.version), ['000_eski']);
  });
});

describe('dbConfigFromEnv / describeTarget', () => {
  it('eksik degiskeni reddeder, parolayi yazdirmaz', () => {
    assert.throws(() => dbConfigFromEnv({}), /Eksik ortam degiskeni/);
    assert.throws(() => dbConfigFromEnv({ ...FAKE_ENV, DB_PORT: '99999' }), /DB_PORT/);
    const cfg = dbConfigFromEnv(FAKE_ENV);
    const target = describeTarget(cfg);
    assert.match(target, /db\.test:5432\/appdb/);
    assert.ok(!target.includes('p@ss-secret'));
  });
});

describe('main: hicbir sey kendiliginden calismaz', () => {
  it('argumansiz cagri yalnizca yardim basar, baglanti acmaz', async () => {
    const db = makeFakeDb();
    let opened = 0;
    const { deps, logs } = makeDeps(db);
    deps.openClient = async () => {
      opened += 1;
      return db.client;
    };
    const code = await main([], FAKE_ENV, deps);
    assert.equal(code, 2);
    assert.equal(opened, 0);
    assert.ok(logs.join('\n').includes('Kullanim'));
  });

  it('hatali argumanda baglanti acmaz', async () => {
    const db = makeFakeDb();
    let opened = 0;
    const { deps } = makeDeps(db);
    deps.openClient = async () => {
      opened += 1;
      return db.client;
    };
    assert.equal(await main(['--apply', '--status'], FAKE_ENV, deps), 2);
    assert.equal(opened, 0);
  });
});

describe('main --status', () => {
  it('salt okunur: tablo olusturmaz, migration calistirmaz', async () => {
    const dir = makeMigrationDir(DIR_FILES);
    const db = makeFakeDb({ usersPresent: true });
    const { deps, logs } = makeDeps(db);
    const code = await main(['--status', '--dir', dir], FAKE_ENV, deps);
    assert.equal(code, 0);
    assert.ok(!db.state.calls.some((c) => /CREATE TABLE/i.test(c)));
    assert.ok(!db.state.calls.includes('BEGIN'));
    assert.equal(db.state.executedMigrationSql.length, 0);
    assert.ok(logs.join('\n').includes('3 bekliyor'));
    assert.ok(db.state.ended);
  });
});

describe('main --apply', () => {
  it('bos veritabaninda bekleyen migration\'lari sirayla, her biri ayri transaction ile uygular', async () => {
    const dir = makeMigrationDir(DIR_FILES);
    const db = makeFakeDb({ usersPresent: false });
    const { deps } = makeDeps(db);
    const code = await main(['--apply', '--yes', '--dir', dir], FAKE_ENV, deps);
    assert.equal(code, 0);
    assert.equal(db.state.executedMigrationSql.length, 3);
    assert.match(db.state.executedMigrationSql[0], /CREATE TABLE users/);
    assert.deepEqual(db.state.applied.map((r) => r.version), ['001_first', '002_second', '003_third']);
    assert.equal(db.state.calls.filter((c) => c === 'BEGIN').length, 3);
    assert.equal(db.state.calls.filter((c) => c === 'COMMIT').length, 3);
    assert.ok(db.state.tablePresent);
    assert.ok(db.state.ended);
    // checksum kaydi dosya icerigiyle ayni
    const list = listMigrations(dir);
    assert.equal(db.state.applied[1].checksum, list[1].checksum);
  });

  it('schema_migrations bos + users tablosu var -> REDDEDER (baseline gerekir)', async () => {
    const dir = makeMigrationDir(DIR_FILES);
    const db = makeFakeDb({ usersPresent: true, tablePresent: false });
    const { deps, errors } = makeDeps(db);
    const code = await main(['--apply', '--yes', '--dir', dir], FAKE_ENV, deps);
    assert.equal(code, 3);
    assert.ok(errors.join('\n').includes('--baseline'));
    assert.ok(!db.state.calls.includes('BEGIN'));
    assert.ok(!db.state.calls.some((c) => /CREATE TABLE/i.test(c)));
    assert.equal(db.state.executedMigrationSql.length, 0);
  });

  it('--force koruyu asar', async () => {
    const dir = makeMigrationDir(DIR_FILES);
    const db = makeFakeDb({ usersPresent: true });
    const { deps } = makeDeps(db);
    const code = await main(['--apply', '--yes', '--force', '--dir', dir], FAKE_ENV, deps);
    assert.equal(code, 0);
    assert.equal(db.state.executedMigrationSql.length, 3);
  });

  it('kayitli migration\'lari tekrar calistirmaz; degismis checksum\'u uyarir', async () => {
    const dir = makeMigrationDir(DIR_FILES);
    const list = listMigrations(dir);
    const db = makeFakeDb({
      usersPresent: true,
      tablePresent: true,
      applied: [
        { version: list[0].version, checksum: list[0].checksum },
        { version: list[1].version, checksum: 'eski-checksum' },
      ],
    });
    const { deps, logs } = makeDeps(db);
    const code = await main(['--apply', '--yes', '--dir', dir], FAKE_ENV, deps);
    assert.equal(code, 0);
    assert.equal(db.state.executedMigrationSql.length, 1);
    assert.match(db.state.executedMigrationSql[0], /ADD COLUMN b/);
    assert.ok(logs.join('\n').includes('002_second uygulandiktan sonra degismis'));
  });

  it('hata olursa ROLLBACK eder, kaydi yazmaz ve sonrakileri calistirmaz', async () => {
    const dir = makeMigrationDir(DIR_FILES);
    const db = makeFakeDb({ usersPresent: false, failOn: 'ADD COLUMN a' });
    const { deps, errors } = makeDeps(db);
    const code = await main(['--apply', '--yes', '--dir', dir], FAKE_ENV, deps);
    assert.equal(code, 1);
    assert.deepEqual(db.state.applied.map((r) => r.version), ['001_first']);
    assert.ok(db.state.calls.includes('ROLLBACK'));
    assert.ok(!db.state.executedMigrationSql.some((c) => c.includes('ADD COLUMN b')));
    assert.ok(errors.join('\n').includes('002_second'));
    assert.ok(db.state.ended);
  });

  it('--dry-run hicbir sey calistirmaz / olusturmaz', async () => {
    const dir = makeMigrationDir(DIR_FILES);
    const db = makeFakeDb({ usersPresent: false });
    const { deps, confirmCalls } = makeDeps(db);
    const code = await main(['--apply', '--dry-run', '--dir', dir], FAKE_ENV, deps);
    assert.equal(code, 0);
    assert.ok(!db.state.calls.includes('BEGIN'));
    assert.ok(!db.state.calls.some((c) => /CREATE TABLE/i.test(c)));
    assert.equal(db.state.executedMigrationSql.length, 0);
    assert.equal(confirmCalls(), 0);
  });

  it('onay verilmezse hicbir sey uygulanmaz', async () => {
    const dir = makeMigrationDir(DIR_FILES);
    const db = makeFakeDb({ usersPresent: false });
    const { deps } = makeDeps(db, { confirmAnswer: false });
    const code = await main(['--apply', '--dir', dir], FAKE_ENV, deps);
    assert.equal(code, 3);
    assert.ok(!db.state.calls.includes('BEGIN'));
    assert.ok(!db.state.calls.some((c) => /CREATE TABLE/i.test(c)));
  });

  it('ust duzey BEGIN iceren migration calistirilmaz', async () => {
    const dir = makeMigrationDir({ '001_bad.sql': 'BEGIN;\nCREATE TABLE x(id INT);\nCOMMIT;\n' });
    const db = makeFakeDb({ usersPresent: false });
    const { deps, errors } = makeDeps(db);
    const code = await main(['--apply', '--yes', '--dir', dir], FAKE_ENV, deps);
    assert.equal(code, 1);
    assert.ok(errors.join('\n').includes('001_bad.sql'));
    assert.equal(db.state.executedMigrationSql.length, 0);
  });
});

describe('main --baseline', () => {
  it('<= numaralari SQL calistirmadan isaretler, kalanlari bekletir', async () => {
    const dir = makeMigrationDir(DIR_FILES);
    const db = makeFakeDb({ usersPresent: true });
    const { deps } = makeDeps(db);
    const code = await main(['--baseline', '2', '--yes', '--dir', dir], FAKE_ENV, deps);
    assert.equal(code, 0);
    assert.equal(db.state.executedMigrationSql.length, 0, 'baseline SQL calistirmamali');
    assert.deepEqual(db.state.applied.map((r) => r.version), ['001_first', '002_second']);
    assert.ok(db.state.tablePresent);
  });

  it('bos veritabaninda (users yok) reddeder; --force ile izin verir', async () => {
    const dir = makeMigrationDir(DIR_FILES);
    const refused = makeFakeDb({ usersPresent: false });
    const r1 = makeDeps(refused);
    assert.equal(await main(['--baseline', '2', '--yes', '--dir', dir], FAKE_ENV, r1.deps), 3);
    assert.equal(refused.state.applied.length, 0);
    assert.ok(!refused.state.calls.some((c) => /CREATE TABLE/i.test(c)));

    const forced = makeFakeDb({ usersPresent: false });
    const r2 = makeDeps(forced);
    assert.equal(await main(['--baseline', '2', '--yes', '--force', '--dir', dir], FAKE_ENV, r2.deps), 0);
    assert.equal(forced.state.applied.length, 2);
  });

  it('klasordeki en yuksek numaradan buyuk baseline reddedilir', async () => {
    const dir = makeMigrationDir(DIR_FILES);
    const db = makeFakeDb({ usersPresent: true });
    const { deps } = makeDeps(db);
    assert.equal(await main(['--baseline', '99', '--yes', '--dir', dir], FAKE_ENV, deps), 2);
    assert.equal(db.state.applied.length, 0);
  });

  it('baseline sonrasi --apply yalnizca kalanlari calistirir', async () => {
    const dir = makeMigrationDir(DIR_FILES);
    const db = makeFakeDb({ usersPresent: true });
    const first = makeDeps(db);
    assert.equal(await main(['--baseline', '2', '--yes', '--dir', dir], FAKE_ENV, first.deps), 0);
    const second = makeDeps(db);
    assert.equal(await main(['--apply', '--yes', '--dir', dir], FAKE_ENV, second.deps), 0);
    assert.equal(db.state.executedMigrationSql.length, 1);
    assert.match(db.state.executedMigrationSql[0], /ADD COLUMN b/);
    assert.equal(db.state.applied.length, 3);
  });
});
