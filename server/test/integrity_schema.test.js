// 077 butunluk sertlestirme (site_name_key + site adi tekillik indeksleri, OAuth / web push FK'si, users.must_change_password): sema <-> migration
// birebir esitligi, katalog kontrollu / lock_timeout'lu / yeniden denemeli ensure, db.js baglantisi (dev blok DISINDA) ve m2 sutunlarinin DUSURULMEMESI.
// DB gerektirmez. Gercek PostgreSQL dogrulamasi: scripts/qa_platform_pg.mjs (chain bolumu) ve deploy/remote_rehearse_schema.sh (ok077).
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { DEFAULT_MIGRATIONS_DIR, findUnsafeStatements, listMigrations } from '../scripts/migrate.js';
import {
  INTEGRITY_STEPS,
  ensureIntegritySchema,
  integrityMigrationBody,
  schemaTuning,
} from '../src/modules/integrity_schema.js';

schemaTuning.retryDelayMs = 1;
const here = path.dirname(fileURLToPath(import.meta.url));
const read = (rel) => readFileSync(path.join(here, '..', rel), 'utf8').replace(/\r\n/g, '\n');
const norm = (s) => s.replace(/\r\n/g, '\n').replace(/--.*$/gm, '').replace(/\s+/g, ' ').trim();
const MIGRATION = read('migrations/077_integrity_hardening.sql');
const DB_SOURCE = read('src/db.js');
const stepSql = (name) => INTEGRITY_STEPS.find((s) => s.name === name).sql;

const ALL_NAMES = INTEGRITY_STEPS.map((s) => s.name);
const OLD_INDEXES = ['idx_sites_unique_name', 'idx_site_applications_pending_unique_name'];

/** Sahte istemci: katalog sorgusu `present` kumesini dondurur, digerleri `sent`e yazilir. */
function mockClient(present, { failures = {} } = {}) {
  const sent = [];
  const listeners = new Map();
  const set = new Set(present);
  const client = {
    sent,
    listeners,
    async query(sql) {
      if (/FROM pg_indexes/.test(sql)) {
        const pick = (kind) => INTEGRITY_STEPS.filter((s) => s.kind === kind && set.has(s.name)).map((s) => s.name);
        return {
          rows: [{
            columns: pick('column'),
            functions: pick('function'),
            fks: [...pick('fk'), ...pick('check')],
            indexes: [...pick('index'), ...OLD_INDEXES.filter((n) => set.has(n))],
          }],
        };
      }
      sent.push(sql);
      for (const [needle, queue] of Object.entries(failures)) {
        if (sql.includes(needle) && queue.length > 0) throw queue.shift();
      }
      return { rows: [] };
    },
    on(event, fn) { listeners.set(event, fn); },
    removeListener(event) { listeners.delete(event); },
  };
  return client;
}
const ddl = (client) => client.sent.filter((q) => !/lock_timeout/.test(q));

async function captureErrors(fn) {
  const original = console.error;
  const lines = [];
  console.error = (...args) => lines.push(args.join(' '));
  try {
    await fn();
  } finally {
    console.error = original;
  }
  return lines;
}

describe('migration 077: butunluk sertlestirme', () => {
  it('077 var, 77. siradadir (ardisik) ve calistirici icin guvenli (ust duzey BEGIN/COMMIT, CONCURRENTLY yok)', () => {
    const list = listMigrations(DEFAULT_MIGRATIONS_DIR);
    const entry = list.find((m) => m.number === 77);
    assert.ok(entry, '077 numarali migration yok');
    assert.equal(entry.file, '077_integrity_hardening.sql');
    assert.equal(list[76], entry);
    assert.deepEqual(findUnsafeStatements(MIGRATION), []);
  });

  it('govde INTEGRITY_STEPS adimlarinin birlesimidir (db.js ile ayni DDL)', () => {
    assert.ok(norm(MIGRATION).includes(norm(integrityMigrationBody())));
  });

  it('sutun / tablo DUSURMEZ: DROP yalniz eski site adi indeksleri (yeni indeks varken); m2 sutunlari bu surumde DUSURULMEZ', () => {
    const sql = norm(MIGRATION);
    const drops = sql.match(/DROP\s+\w+(\s+IF EXISTS)?\s+\w+/gi) ?? [];
    assert.deepEqual(drops.sort(), [
      'DROP INDEX IF EXISTS idx_site_applications_pending_unique_name',
      'DROP INDEX IF EXISTS idx_sites_unique_name',
    ]);
    assert.doesNotMatch(sql, /DROP\s+(TABLE|COLUMN|CONSTRAINT)/i);
    assert.doesNotMatch(sql, /\bTRUNCATE\b/i);
    // yorumda bir SONRAKI surumde dusurulecegi belirtilir (kod artik kullanmaz; geri alma uyumlulugu)
    assert.match(MIGRATION, /gross_area_m2 \/ net_area_m2 sutunlari bu surumde DUSURULMEZ/);
    assert.match(MIGRATION, /SONRAKI surumde ayri bir migration/);
  });

  it('adim sirasi: sutun, CHECK, islev, FK, indeks (islev ve sites.approval_status indeksten ONCE; FK 076 / 063 tablolarindan SONRA)', () => {
    const order = ['column', 'check', 'function', 'fk', 'index'];
    const kinds = INTEGRITY_STEPS.map((s) => s.kind);
    assert.deepEqual(kinds, [...kinds].sort((a, b) => order.indexOf(a) - order.indexOf(b)));
    assert.deepEqual(ALL_NAMES, [
      'users.must_change_password',
      'sites.approval_status',
      'sites_approval_status_check',
      'site_name_key',
      'user_oauth_identities_user_code_fkey',
      'web_push_subscriptions_user_code_fkey',
      'uq_sites_name_key',
      'uq_site_applications_pending_name_key',
    ]);
    const migrations = listMigrations(DEFAULT_MIGRATIONS_DIR);
    assert.ok(migrations.find((m) => m.number === 63).sql.includes('web_push_subscriptions'));
    assert.ok(migrations.find((m) => m.number === 76).sql.includes('user_oauth_identities'));
  });

  it('users.must_change_password: katalog kontrollu ekleyici sutun (numarali migration zincirinde de bulunur)', () => {
    assert.equal(
      stepSql('users.must_change_password'),
      'ALTER TABLE users ADD COLUMN IF NOT EXISTS must_change_password BOOLEAN NOT NULL DEFAULT FALSE;',
    );
    const earlier = listMigrations(DEFAULT_MIGRATIONS_DIR).filter((m) => m.number < 77).map((m) => m.sql).join('\n');
    assert.doesNotMatch(earlier, /must_change_password/, '077 oncesi numarali migration\'da yoktu (bos DB zincirinde eksik kaliyordu)');
  });

  it('site_name_key: IMMUTABLE; NBSP + sekme -> bosluk, Turkce harf katlama, lower, btrim, bosluk daraltma; NULL -> bos', () => {
    const fn = stepSql('site_name_key');
    assert.match(fn, /CREATE OR REPLACE FUNCTION site_name_key\(t TEXT\) RETURNS TEXT/);
    assert.match(fn, /\bIMMUTABLE\b/);
    assert.match(fn, /COALESCE\(t, ''\)/);
    assert.match(fn, /chr\(160\)/);
    assert.match(fn, /chr\(9\)/);
    assert.match(fn, /translate\([^;]*'İIıŞşĞğÜüÖöÇç', 'iiissgguuoocc'\)/);
    assert.match(fn, /lower\(/);
    assert.match(fn, /btrim\(/);
    assert.match(fn, /regexp_replace\([^;]*'\\s\+', ' ', 'g'\)/);
    assert.equal(/\bSTRICT\b/i.test(fn), false, 'NULL icin bos dize (STRICT NULL dondururdu)');
    // translate kume uzunluklari esit (kayma = yanlis katlama)
    const [, from, to] = /translate\([^;]*?'([^']+)', '([^']+)'\)/.exec(fn);
    assert.equal([...from].length, [...to].length);
  });

  it('uq_sites_name_key ve uq_site_applications_pending_name_key: sozlesmedeki ifade ve kosul; eski adlar yalniz yenisi varken duser', () => {
    const sites = norm(stepSql('uq_sites_name_key'));
    assert.match(sites, /CREATE UNIQUE INDEX IF NOT EXISTS uq_sites_name_key ON sites \(site_name_key\(name\)\) WHERE approval_status IS DISTINCT FROM 'rejected'/);
    const apps = norm(stepSql('uq_site_applications_pending_name_key'));
    assert.match(apps, /CREATE UNIQUE INDEX IF NOT EXISTS uq_site_applications_pending_name_key ON site_applications \(site_name_key\(site_name\)\) WHERE status = 'pending'/);
    for (const [sql, oldName, newName] of [[sites, 'idx_sites_unique_name', 'uq_sites_name_key'], [apps, 'idx_site_applications_pending_unique_name', 'uq_site_applications_pending_name_key']]) {
      assert.match(sql, new RegExp(`IF to_regclass\\('public\\.${newName}'\\) IS NOT NULL THEN DROP INDEX IF EXISTS ${oldName};`));
      // mukerrer kontrolu KURMADAN ONCE; RAISE WARNING + sayac; kurulum yalniz mukerrer yoksa
      assert.ok(sql.indexOf('RAISE WARNING') < sql.indexOf('CREATE UNIQUE INDEX'));
      assert.match(sql, /IF dup_count = 0 THEN BEGIN CREATE UNIQUE INDEX/);
      assert.match(sql, /EXCEPTION WHEN unique_violation THEN RAISE WARNING/);
      assert.match(sql, /HAVING COUNT\(\*\) > 1/);
    }
    // tablo yoksa (kesik sablon) indeks kurulmaz, NOTICE verir
    assert.match(sites, /IF to_regclass\('public\.sites'\) IS NOT NULL THEN/);
    assert.match(sites, /RAISE NOTICE '077: sites henuz yok/);
    // sites.approval_status numarali migration'larda YOK: 077 ayni db.js ifadeleriyle ekler (bos DB zincirinde indeks kurulabilsin; zincir <-> ensureDbSchema esit)
    const earlier = listMigrations(DEFAULT_MIGRATIONS_DIR).filter((m) => m.number < 77).map((m) => m.sql).join('\n');
    assert.doesNotMatch(earlier, /sites[^;]*approval_status/);
    assert.equal(stepSql('sites.approval_status'), "ALTER TABLE sites ADD COLUMN IF NOT EXISTS approval_status TEXT NOT NULL DEFAULT 'approved';");
    assert.match(norm(stepSql('sites_approval_status_check')), /ADD CONSTRAINT sites_approval_status_check CHECK \(approval_status IN \('pending', 'approved', 'rejected'\)\)/);
    // db.js'teki tanimla ayni olmali
    assert.match(DB_SOURCE, /ADD COLUMN IF NOT EXISTS approval_status TEXT NOT NULL DEFAULT 'approved'/);
    assert.match(DB_SOURCE, /ADD CONSTRAINT sites_approval_status_check\s+CHECK \(approval_status IN \('pending', 'approved', 'rejected'\)\)/);
    // basvuru sutun adi semadan dogrulanir
    assert.match(listMigrations(DEFAULT_MIGRATIONS_DIR).find((m) => m.number === 33).sql, /CREATE TABLE IF NOT EXISTS site_applications \([\s\S]*?\n  site_name TEXT NOT NULL,/);
  });

  it('FK: user_oauth_identities (076) ve web_push_subscriptions (063) -> users(user_code) ON DELETE CASCADE; yetimler FK\'den ONCE silinir; users once kilitlenir', () => {
    for (const [name, table] of [['user_oauth_identities_user_code_fkey', 'user_oauth_identities'], ['web_push_subscriptions_user_code_fkey', 'web_push_subscriptions']]) {
      const sql = norm(stepSql(name));
      assert.match(sql, new RegExp(`IF NOT EXISTS \\( SELECT 1 FROM pg_constraint WHERE conname = '${name}' AND conrelid = '${table}'::regclass \\) THEN`));
      assert.match(sql, /LOCK TABLE users IN SHARE ROW EXCLUSIVE MODE;/);
      assert.match(sql, new RegExp(`DELETE FROM ${table} c WHERE NOT EXISTS \\(SELECT 1 FROM users p WHERE p\\.user_code = c\\.user_code\\);`));
      assert.match(sql, new RegExp(`ALTER TABLE ${table} ADD CONSTRAINT ${name} FOREIGN KEY \\(user_code\\) REFERENCES users\\(user_code\\) ON DELETE CASCADE;`));
      assert.ok(sql.indexOf('LOCK TABLE') < sql.indexOf('DELETE FROM') && sql.indexOf('DELETE FROM') < sql.indexOf('ADD CONSTRAINT'));
      assert.match(sql, /RAISE WARNING '077: % yetim /);
    }
  });
});

describe('ensureIntegritySchema (katalog kontrollu, lock_timeout, yeniden deneme)', () => {
  it('her sey varsa tek katalog sorgusu gonderilir; DDL ve lock_timeout YOK', async () => {
    const client = mockClient(ALL_NAMES);
    await ensureIntegritySchema(client);
    assert.deepEqual(client.sent, []);
  });

  it('eskiden kalan indeks varken (yenisi de var) yalniz ilgili indeks adimi calisir (eski dusurulur)', async () => {
    const client = mockClient([...ALL_NAMES, 'idx_sites_unique_name']);
    await ensureIntegritySchema(client);
    assert.equal(ddl(client).length, 1);
    assert.match(ddl(client)[0], /DROP INDEX IF EXISTS idx_sites_unique_name/);
  });

  it('yenisi yoksa (yalniz eski var) indeks adimi calisir; eksik adimlar sirayla, SET lock_timeout 2s ... RESET', async () => {
    const present = ALL_NAMES.filter((n) => n !== 'uq_sites_name_key');
    const client = mockClient([...present, 'idx_sites_unique_name']);
    const logged = await captureErrors(() => ensureIntegritySchema(client));
    assert.equal(client.sent[0], "SET lock_timeout = '2s'");
    assert.equal(client.sent.at(-1), 'RESET lock_timeout');
    assert.equal(ddl(client).length, 1);
    assert.match(ddl(client)[0], /uq_sites_name_key/);
    // sahte istemcide indeks kurulmadigindan (katalog degismez) acilista GORUNUR uyari
    assert.ok(logged.some((l) => /\[DB\] UYARI uq_sites_name_key yok/.test(l)), logged.join('\n'));
  });

  it('hicbiri yoksa tum adimlar sabit sirayla calisir', async () => {
    const client = mockClient([]);
    await captureErrors(() => ensureIntegritySchema(client));
    assert.deepEqual(ddl(client), INTEGRITY_STEPS.map((s) => s.sql));
  });

  it('40P01 / 55P03: artan beklemeyle yeniden dener; 6. denemede vazgecer (FK / indeks adimi acilisi DURDURMAZ, loglanir)', async () => {
    const deadlock = Object.assign(new Error('deadlock'), { code: '40P01' });
    const locked = Object.assign(new Error('lock'), { code: '55P03' });
    const retry = mockClient(ALL_NAMES.filter((n) => n !== 'web_push_subscriptions_user_code_fkey'), {
      failures: { web_push_subscriptions: [deadlock, locked] },
    });
    await ensureIntegritySchema(retry);
    assert.equal(ddl(retry).filter((q) => /web_push_subscriptions/.test(q)).length, 3, '2 hata + 1 basari');

    const always = Array.from({ length: 12 }, () => locked);
    const stuck = mockClient(ALL_NAMES.filter((n) => n !== 'web_push_subscriptions_user_code_fkey'), {
      failures: { web_push_subscriptions: always },
    });
    const logged = await captureErrors(() => ensureIntegritySchema(stuck));
    assert.equal(ddl(stuck).length, 6);
    assert.equal(stuck.sent.at(-1), 'RESET lock_timeout');
    assert.ok(logged.some((l) => /UYARI 077 fk web_push_subscriptions_user_code_fkey kurulamadi/.test(l)), logged.join('\n'));
  });

  it('islev / sutun adimi ONEMLIDIR: hata acilisi durdurur (uygulama koduna bagli); kilit yine sifirlanir', async () => {
    const boom = Object.assign(new Error('permission denied'), { code: '42501' });
    const client = mockClient(ALL_NAMES.filter((n) => n !== 'site_name_key'), { failures: { 'CREATE OR REPLACE FUNCTION': [boom] } });
    await assert.rejects(() => ensureIntegritySchema(client), /permission denied/);
    assert.equal(client.sent.at(-1), 'RESET lock_timeout');
    assert.equal(client.listeners.size, 0, 'bildirim dinleyicisi temizlenir');
  });

  it('RAISE WARNING bildirimleri (mukerrer site adi) acilista loglanir; NOTICE loglanmaz; dinleyici temizlenir', async () => {
    const client = mockClient(ALL_NAMES.filter((n) => n !== 'uq_sites_name_key'));
    const original = client.query.bind(client);
    client.query = async (sql, ...rest) => {
      if (/uq_sites_name_key/.test(sql) && /DO \$\$/.test(sql)) {
        const emit = client.listeners.get('notice');
        emit({ severity: 'WARNING', message: '077: uq_sites_name_key KURULMADI, mukerrer sites adi "ozgur sitesi" (2 kayit): site_code {1,2}' });
        emit({ severity: 'NOTICE', message: 'relation already exists, skipping' });
      }
      return original(sql, ...rest);
    };
    const logged = await captureErrors(() => ensureIntegritySchema(client));
    assert.ok(logged.some((l) => /KURULMADI, mukerrer sites adi "ozgur sitesi"/.test(l)), logged.join('\n'));
    assert.equal(logged.some((l) => /already exists/.test(l)), false);
    assert.equal(client.listeners.size, 0);
  });
});

describe('db.js baglantisi (kaynak koruma)', () => {
  it('ensureIntegritySchema dev blok DISINDA: ensureOAuthSchema (076) SONRASI, people_v1 aktarimindan ONCE; yalniz bir kez', () => {
    assert.equal(DB_SOURCE.split('await ensureIntegritySchema(client);').length - 1, 1);
    assert.match(DB_SOURCE, /import \{ ensureIntegritySchema \} from '\.\/modules\/integrity_schema\.js';/);
    const call = DB_SOURCE.indexOf('await ensureIntegritySchema(client);');
    assert.ok(call > DB_SOURCE.indexOf('await ensureOAuthSchema(client);'));
    assert.ok(call < DB_SOURCE.indexOf('await runPeopleBackfill(client)'));
    const blockEnd = DB_SOURCE.lastIndexOf('`);', DB_SOURCE.indexOf('await ensurePendingConsentsColumn(client);'));
    assert.ok(call > blockEnd, 'dev ensureDbSchema blogunun SONRASI');
  });

  it('eski site adi indeks kurulumu (tek cok-ifadeli, hatasi yutulan sorgu) ve ikinci must_change_password ALTER\'i kaldirildi', () => {
    assert.doesNotMatch(DB_SOURCE, /CREATE UNIQUE INDEX IF NOT EXISTS idx_sites_unique_name/);
    assert.doesNotMatch(DB_SOURCE, /CREATE UNIQUE INDEX IF NOT EXISTS idx_site_applications_pending_unique_name/);
    assert.doesNotMatch(DB_SOURCE, /unique site name index hatasi/);
    // yalniz dev blogun 203. satir civarindaki (users basinda) kopyasi kalir; katalog kontrolsuz ikinci kopya yok
    assert.equal(DB_SOURCE.match(/ADD COLUMN IF NOT EXISTS must_change_password/g).length, 1);
    assert.doesNotMatch(DB_SOURCE, /client\.query\('ALTER TABLE users ADD COLUMN IF NOT EXISTS must_change_password/);
  });

  it('apartments m2 sutunlari acilista DUSURULMEZ (031 ekleyici DDL\'i; deploy geri almasi eski kodu cokertirmez)', () => {
    assert.doesNotMatch(DB_SOURCE, /DROP\s+COLUMN[^;]*(gross_area_m2|net_area_m2)/i);
    assert.match(DB_SOURCE, /ALTER TABLE apartments ADD COLUMN IF NOT EXISTS gross_area_m2 NUMERIC\(8,2\);/);
    assert.match(DB_SOURCE, /ALTER TABLE apartments ADD COLUMN IF NOT EXISTS net_area_m2 NUMERIC\(8,2\);/);
    assert.doesNotMatch(DB_SOURCE, /DROP\s+COLUMN\s+IF\s+EXISTS\s+\w*area/i);
  });

  it('modul db.js\'i ICE AKTARMAZ (dongu yok) ve hicbir modulu ice aktarmaz', () => {
    const source = read('src/modules/integrity_schema.js');
    assert.doesNotMatch(source, /from '\.\.\/db\.js'/);
    assert.doesNotMatch(source, /^import /m);
  });
});
