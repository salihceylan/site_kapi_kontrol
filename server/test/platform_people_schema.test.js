// Kisi ve Daire Kayitlari (Faz 2a): migration 031 <-> db.js ayni DDL, ekleyici sema, people_v1 aktarimi ve esitleme SQL'i (DB'siz).
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { DEFAULT_MIGRATIONS_DIR, blankSqlNoise, findUnsafeStatements, listMigrations } from '../scripts/migrate.js';
import { PEOPLE_BACKFILL_CODE, runPeopleBackfill } from '../src/modules/people_backfill.js';
import { SYNC_STEPS, runSyncSteps } from '../src/modules/people_sync_sql.js';

const here = path.dirname(fileURLToPath(import.meta.url));
const read = (relative) => readFileSync(path.join(here, '..', 'src', relative), 'utf8').replace(/\r\n/g, '\n');
const MIGRATION = readFileSync(path.join(DEFAULT_MIGRATIONS_DIR, '031_people_and_apartments.sql'), 'utf8').replace(/\r\n/g, '\n');
const DB_SOURCE = read('db.js');

function normalizeSql(text) {
  return text
    .replace(/\/\*[\s\S]*?\*\//g, ' ')
    .replace(/--.*$/gm, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

describe('migration 031: kisi ve daire kayitlari', () => {
  it('031 var, 31. siradadir (ardisik) ve calistirici icin guvenli (ust duzey BEGIN/COMMIT yok)', () => {
    const list = listMigrations(DEFAULT_MIGRATIONS_DIR);
    assert.ok(list.length >= 31, `en az 31 migration beklenir: ${list.length}`);
    const entry = list.find((m) => m.number === 31);
    assert.ok(entry, '031 numarali migration yok');
    assert.equal(entry.file, '031_people_and_apartments.sql');
    assert.equal(list[30], entry);
    assert.deepEqual(findUnsafeStatements(MIGRATION), []);
  });

  it('db.js ensureDbSchema ayni DDL\'i icerir (yorumlar ve bosluklar disinda birebir); 030\'dan sonra gelir', () => {
    const normalizedDb = normalizeSql(DB_SOURCE);
    const migration = normalizeSql(MIGRATION);
    assert.ok(migration.length > 2000);
    assert.ok(normalizedDb.includes(migration), 'migrations/031 ile db.js ayni DDL degil');
    const migration030 = normalizeSql(readFileSync(path.join(DEFAULT_MIGRATIONS_DIR, '030_module_requests.sql'), 'utf8'));
    assert.ok(normalizedDb.indexOf(migration030) < normalizedDb.indexOf(migration));
  });

  it('site_people: alanlar, FK davranislari ve kismi tekil indeksler (hesap ve hesapsiz e-posta)', () => {
    const sql = normalizeSql(MIGRATION);
    const table = /CREATE TABLE IF NOT EXISTS site_people \(([\s\S]*?)\);/.exec(sql)?.[1];
    assert.ok(table);
    assert.match(table, /site_code BIGINT NOT NULL REFERENCES sites\(site_code\) ON DELETE CASCADE/);
    assert.match(table, /user_code INTEGER REFERENCES users\(user_code\) ON DELETE SET NULL/);
    assert.match(table, /is_active BOOLEAN NOT NULL DEFAULT TRUE/);
    assert.match(table, /created_by INTEGER REFERENCES users\(user_code\) ON DELETE SET NULL/);
    assert.match(sql, /CREATE UNIQUE INDEX IF NOT EXISTS uq_site_people_user ON site_people \(site_code, user_code\) WHERE user_code IS NOT NULL/);
    assert.match(
      sql,
      /CREATE UNIQUE INDEX IF NOT EXISTS uq_site_people_email ON site_people \(site_code, lower\(email\)\) WHERE user_code IS NULL AND email IS NOT NULL AND is_active/,
    );
  });

  it('apartment_residencies: iliski CHECK, tek GUNCEL (kisi/daire), en cok bir guncel malik ve bir guncel kiraci', () => {
    const sql = normalizeSql(MIGRATION);
    const table = /CREATE TABLE IF NOT EXISTS apartment_residencies \(([\s\S]*?)\);/.exec(sql)?.[1];
    assert.ok(table);
    assert.match(table, /apartment_id BIGINT NOT NULL REFERENCES apartments\(id\) ON DELETE CASCADE/);
    assert.match(table, /person_id BIGINT NOT NULL REFERENCES site_people\(id\) ON DELETE CASCADE/);
    assert.match(table, /relation TEXT NOT NULL DEFAULT 'resident'/);
    assert.match(table, /CHECK \(relation IN \('owner', 'tenant', 'family_member', 'resident'\)\)/);
    assert.match(sql, /uq_apartment_residencies_current ON apartment_residencies \(apartment_id, person_id\) WHERE is_current/);
    assert.match(sql, /uq_apartment_residencies_owner ON apartment_residencies \(apartment_id\) WHERE is_current AND relation = 'owner'/);
    assert.match(sql, /uq_apartment_residencies_tenant ON apartment_residencies \(apartment_id\) WHERE is_current AND relation = 'tenant'/);
  });

  it('apartments: yeni kolonlar EKLEMELI (IF NOT EXISTS) ve kisitlar (sorumlu taraf, arsa payi, kategori uzunlugu)', () => {
    const sql = normalizeSql(MIGRATION);
    for (const column of [
      'floor INTEGER',
      'gross_area_m2 NUMERIC\\(8,2\\)',
      'net_area_m2 NUMERIC\\(8,2\\)',
      'land_share_numerator INTEGER',
      'land_share_denominator INTEGER',
      'category TEXT',
      "responsible_party TEXT NOT NULL DEFAULT 'both'",
    ]) {
      assert.match(sql, new RegExp(`ALTER TABLE apartments ADD COLUMN IF NOT EXISTS ${column}`), column);
    }
    assert.match(sql, /chk_apartments_responsible_party CHECK \(responsible_party IN \('owner', 'tenant', 'both'\)\)/);
    assert.match(sql, /chk_apartments_land_share CHECK \(/);
    assert.match(sql, /land_share_denominator > 0 AND land_share_numerator >= 0 AND land_share_numerator <= land_share_denominator/);
    assert.match(sql, /chk_apartments_category_length CHECK \(category IS NULL OR char_length\(category\) <= 40\)/);
    // her kisit kosullu (var olan kisit yeniden eklenmez): 3 daire kisiti + iliski kaynagi (origin) kisiti
    assert.equal((sql.match(/IF NOT EXISTS \( SELECT 1 FROM pg_constraint/g) || []).length, 4);
  });

  it('vehicles ve platform_backfills', () => {
    const sql = normalizeSql(MIGRATION);
    const vehicles = /CREATE TABLE IF NOT EXISTS vehicles \(([\s\S]*?)\);/.exec(sql)?.[1];
    assert.ok(vehicles);
    assert.match(vehicles, /person_id BIGINT REFERENCES site_people\(id\) ON DELETE SET NULL/);
    assert.match(vehicles, /plate TEXT NOT NULL/);
    assert.match(sql, /CREATE UNIQUE INDEX IF NOT EXISTS uq_vehicles_plate ON vehicles \(site_code, plate\) WHERE is_active/);
    assert.match(sql, /CREATE TABLE IF NOT EXISTS platform_backfills \( code TEXT PRIMARY KEY, done_at TIMESTAMPTZ NOT NULL DEFAULT NOW\(\) \)/);
  });

  it('ekleyici: silme/dusurme/veri yazma yok (tetikleyici fonksiyon govdesi haric); her CREATE ve ADD COLUMN IF NOT EXISTS ile', () => {
    // dolar-tirnakli govdeler (DO bloklari, tetikleyici fonksiyonu) bosaltilir: ust duzey ifadelerde veri yazan/silen yok
    const sql = normalizeSql(blankSqlNoise(MIGRATION));
    assert.equal(/DROP\s|TRUNCATE|DELETE\s+FROM|\bUPDATE\s+\w+\s+SET|\bINSERT\s+INTO/i.test(sql), false);
    const full = normalizeSql(MIGRATION);
    assert.deepEqual(full.match(/CREATE\s+(UNIQUE\s+)?(TABLE|INDEX)\s+(?!IF NOT EXISTS)/gi) || [], []);
    assert.deepEqual(full.match(/ADD\s+COLUMN\s+(?!IF NOT EXISTS)/gi) || [], []);
  });

  it('apartment_residencies.origin: eklemeli kolon (manual varsayilan) + CHECK (manual|sync), kosullu kisit', () => {
    const sql = normalizeSql(MIGRATION);
    assert.match(sql, /ALTER TABLE apartment_residencies ADD COLUMN IF NOT EXISTS origin TEXT NOT NULL DEFAULT 'manual'/);
    assert.match(sql, /conname = 'chk_apartment_residencies_origin' AND conrelid = 'apartment_residencies'::regclass/);
    assert.match(sql, /ADD CONSTRAINT chk_apartment_residencies_origin CHECK \(origin IN \('manual', 'sync'\)\)/);
  });

  it('users BEFORE DELETE tetikleyicisi (H2): ad/telefon yedegi, e-posta temizligi, pasif, iliski + arac bitisi; silmeyi ENGELLEMEZ', () => {
    const fn = /CREATE OR REPLACE FUNCTION trg_users_preserve_site_people\(\) RETURNS trigger AS \$\$([\s\S]*?)\$\$ LANGUAGE plpgsql;/.exec(MIGRATION)?.[1];
    assert.ok(fn, 'tetikleyici fonksiyonu yok');
    const body = fn.replace(/\s+/g, ' ');
    assert.match(body, /UPDATE site_people SET full_name = COALESCE\(full_name, NULLIF\(OLD\.full_name, ''\)\), phone = COALESCE\(phone, NULLIF\(OLD\.phone_number, ''\)\), email = NULL, is_active = FALSE/);
    assert.match(body, /WHERE user_code = OLD\.user_code/);
    assert.match(body, /UPDATE apartment_residencies r SET is_current = FALSE, move_out_date = COALESCE\(r\.move_out_date, CURRENT_DATE\)/);
    assert.match(body, /UPDATE vehicles v SET is_active = FALSE/);
    assert.match(body, /RETURN OLD;/, 'BEFORE DELETE: satir donduruldu (silme surer)');
    assert.equal(/RAISE\s|RETURN NULL/i.test(body), false, 'silmeyi engelleyen RAISE/RETURN NULL yok');
    // denetim yazimi hata yutan alt blokta (denetim sorunu silmeyi bozmaz)
    assert.match(body, /BEGIN INSERT INTO audit_log[\s\S]*EXCEPTION WHEN OTHERS THEN NULL; END;/);
    const sql = normalizeSql(MIGRATION);
    assert.match(sql, /tgname = 'trg_users_preserve_site_people' AND tgrelid = 'users'::regclass AND NOT tgisinternal/, 'kosullu olusturma (idempotent)');
    assert.match(sql, /CREATE TRIGGER trg_users_preserve_site_people BEFORE DELETE ON users FOR EACH ROW EXECUTE PROCEDURE trg_users_preserve_site_people\(\)/);
  });
});

describe('people_v1 aktarimi (ensureDbSchema)', () => {
  function fakeClient({ done = false, failOn = null } = {}) {
    const log = [];
    return {
      log,
      async query(text, params) {
        const sql = String(text).replace(/\s+/g, ' ').trim();
        log.push({ sql, params });
        if (failOn && failOn.test(sql)) {
          throw Object.assign(new Error('SECRET_DB_DETAIL'), { code: 'XX000' });
        }
        if (/^SELECT 1 FROM platform_backfills/.test(sql)) {
          return { rows: done ? [{ '?column?': 1 }] : [], rowCount: done ? 1 : 0 };
        }
        return { rows: [], rowCount: 2 };
      },
    };
  }

  it('db.js aktarimi savunmaci cagirir: hata sunucunun acilmasini ENGELLEMEZ (try/catch, loglanir)', () => {
    assert.match(DB_SOURCE, /import \{ runPeopleBackfill \} from '\.\/modules\/people_backfill\.js';/);
    assert.match(DB_SOURCE, /try \{\s*await runPeopleBackfill\(client\);\s*\} catch \(error\) \{/);
    assert.match(DB_SOURCE, /people_v1 aktarimi basarisiz \(sonraki acilista tekrar denenecek\)/);
    // DDL'den SONRA (ayni client, tablolar hazir)
    assert.ok(DB_SOURCE.indexOf('await runPeopleBackfill(client)') > DB_SOURCE.indexOf('CREATE TABLE IF NOT EXISTS platform_backfills'));
  });

  it('kayit yoksa: kilit -> kontrol -> TUM adimlar -> isaret AYNI transaction\'da -> COMMIT', async () => {
    const client = fakeClient();
    const result = await runPeopleBackfill(client);
    assert.equal(result.ran, true);
    assert.equal(PEOPLE_BACKFILL_CODE, 'people_v1');
    const sqls = client.log.map((e) => e.sql);
    assert.equal(sqls[0], 'BEGIN');
    assert.match(sqls[1], /^SELECT pg_advisory_xact_lock/);
    assert.match(sqls[2], /^SELECT 1 FROM platform_backfills WHERE code = \$1/);
    const stepSqls = SYNC_STEPS.map((step) => step.sql.replace(/\s+/g, ' ').trim());
    assert.deepEqual(
      sqls.filter((s) => stepSqls.includes(s)),
      stepSqls,
      'TUM esitleme adimlari sirayla calisti',
    );
    const marker = sqls.findIndex((s) => /^INSERT INTO platform_backfills/.test(s));
    const commit = sqls.indexOf('COMMIT');
    assert.ok(marker > 2 && commit > marker, 'isaret, aktarimla ayni transaction\'da ve COMMIT oncesinde');
    assert.deepEqual(client.log[marker].params, ['people_v1']);
    // tum siteler/kullanicilar: filtre parametreleri NULL
    for (const entry of client.log.filter((e) => stepSqls.includes(e.sql))) {
      assert.deepEqual(entry.params, [null, null]);
    }
  });

  it('kayit VARSA no-op: adimlar calismaz, COMMIT edilir (ikinci calistirma)', async () => {
    const client = fakeClient({ done: true });
    const result = await runPeopleBackfill(client);
    assert.deepEqual(result, { ran: false });
    const stepSqls = SYNC_STEPS.map((step) => step.sql.replace(/\s+/g, ' ').trim());
    assert.equal(client.log.some((e) => stepSqls.includes(e.sql)), false);
    assert.equal(client.log.some((e) => /^INSERT INTO platform_backfills/.test(e.sql)), false);
    assert.equal(client.log[client.log.length - 1].sql, 'COMMIT');
  });

  it('hata olursa ROLLBACK, isaret YAZILMAZ ve hata yeniden firlatilir (sonraki acilista tekrar denenir)', async () => {
    const client = fakeClient({ failOn: /^WITH desired AS[\s\S]*INSERT INTO apartment_residencies/ });
    await assert.rejects(() => runPeopleBackfill(client), (error) => error.code === 'XX000');
    const sqls = client.log.map((e) => e.sql);
    assert.ok(sqls.includes('ROLLBACK'));
    assert.equal(sqls.includes('COMMIT'), false);
    assert.equal(sqls.some((s) => /^INSERT INTO platform_backfills/.test(s)), false);
  });
});

describe('esitleme SQL\'i (people_sync_sql)', () => {
  const allSql = SYNC_STEPS.map((step) => step.sql.replace(/\s+/g, ' ').trim());

  it('6 adim, sabit sira; her adim ($1 site, $2 kullanici) parametreli', async () => {
    assert.deepEqual(SYNC_STEPS.map((s) => s.name), [
      'link_accountless',
      'insert_people',
      'reactivate_people',
      'insert_residencies',
      'end_unbacked',
      'deactivate_orphans',
    ]);
    const calls = [];
    const counts = await runSyncSteps({ query: async (sql, params) => (calls.push(params), { rowCount: 3 }) }, { siteCode: 1000000001 });
    assert.equal(calls.length, 6, 'bir siteyi esitlemek SABIT sayida sorgu (N+1 yok)');
    for (const params of calls) assert.deepEqual(params, [1000000001, null]);
    assert.deepEqual(Object.values(counts), [3, 3, 3, 3, 3, 3]);
  });

  it('erisim yetkisini DEGISTIRMEZ: apartment_memberships / site_memberships / kapi tablolarina yazmaz', () => {
    for (const sql of allSql) {
      assert.equal(/(INSERT INTO|UPDATE|DELETE FROM)\s+(apartment_memberships|site_memberships|door_access_overrides|site_doors|devices)\b/i.test(sql), false);
      assert.equal(/\bDELETE\s+FROM\b/i.test(sql), false, 'esitleme hicbir satir silmez');
    }
    // apartments yalnizca OKUNUR
    assert.equal(allSql.some((sql) => /UPDATE\s+apartments\b|INSERT INTO\s+apartments\b/i.test(sql)), false);
  });

  it('istenen durum: aktif daire + aktif uyelik ve eski resident_user_code sakini', () => {
    const sql = allSql[0];
    assert.match(sql, /FROM apartment_memberships am INNER JOIN apartments a ON a\.id = am\.apartment_id WHERE am\.is_active = TRUE AND a\.is_active = TRUE/);
    assert.match(sql, /FROM apartments a WHERE a\.resident_user_code IS NOT NULL AND a\.is_active = TRUE/);
    assert.match(sql, /am\.created_at::date AS move_in/);
  });

  it('idempotent yazimlar: ON CONFLICT DO NOTHING / yalniz degisen satirlar; esitleme iliskisi origin = sync', () => {
    assert.match(allSql[1], /ON CONFLICT \(site_code, user_code\) WHERE user_code IS NOT NULL DO NOTHING/);
    assert.match(allSql[3], /ON CONFLICT \(apartment_id, person_id\) WHERE is_current DO NOTHING/);
    assert.match(allSql[3], /\(site_code, apartment_id, person_id, relation, is_current, move_in_date, origin\) SELECT .*'resident', TRUE, d\.move_in, 'sync'/);
    assert.match(allSql[2], /sp\.is_active = FALSE/, 'yalniz pasif kisiler yeniden etkinlesir');
  });

  it('H4: otomatik bitirme YALNIZ origin=sync ve destekleyen uyelik/gosterge GERCEKTEN yoksa; pasif uyelik/pasif daire bitirmez', () => {
    const sql = allSql[4];
    assert.match(sql, /r\.is_current = TRUE AND r\.origin = 'sync' AND sp\.user_code IS NOT NULL/, 'yalniz esitleme kaynakli + HESAPLI kisi');
    assert.match(sql, /NOT EXISTS \( SELECT 1 FROM apartment_memberships am WHERE am\.apartment_id = r\.apartment_id AND am\.user_code = sp\.user_code \)/);
    assert.match(sql, /NOT EXISTS \( SELECT 1 FROM apartments a WHERE a\.id = r\.apartment_id AND a\.resident_user_code = sp\.user_code \)/);
    assert.equal(/am\.is_active|a\.is_active|desired/.test(sql), false, 'is_active=false (askiya alma) ve pasif daire iliskiyi BITIRMEZ');
    assert.equal(/WITH desired AS/.test(sql), false);
  });

  it('H1/H2: hesapsiz kisiyle ayni e-postaya sahip ERISIMI OLAN kullanici bulunursa user_code baglanir; ad/telefon/e-posta bosalir', () => {
    const sql = allSql[0];
    assert.match(sql, /UPDATE site_people sp SET user_code = c\.user_code, full_name = NULL, phone = NULL, email = NULL/);
    assert.match(sql, /sp\.user_code IS NULL AND sp\.is_active = TRUE AND lower\(sp\.email\) = c\.email/);
    assert.match(sql, /u\.email NOT LIKE '%@ahbu\.local'/, 'dahili daire hesabi e-postasi eslestirmeye girmez');
    // baglama yalniz bu sitede aktif erisimi olan hesaplarla (desired) yapilir: baska sitenin kullanicisi baglanmaz
    assert.match(sql, /FROM desired d INNER JOIN users u ON u\.user_code = d\.user_code/);
    assert.match(sql, /WHERE sp\.site_code = c\.site_code/);
  });

  it('dahili (@ahbu.local) daire hesabinda iletisim e-postasi apartments.resident_email\'den kisi kaydina yazilir', () => {
    assert.match(allSql[1], /CASE WHEN u\.email LIKE '%@ahbu\.local' THEN MAX\(d\.contact_email\) ELSE NULL END/);
  });

  it('otomatik biten iliski sistem adina audit yazar; son iliskisi biten kisi pasif olur (araclari da)', () => {
    const sql = allSql[4];
    assert.match(sql, /INSERT INTO audit_log \(actor_name, actor_role, action, site_code, target_type, target_id, details\)/);
    assert.match(sql, /'Sistem', 'system', 'residency\.ended'/);
    assert.match(sql, /jsonb_build_object\('residency_id', e\.id, 'apartment_id', e\.apartment_id, 'relation', e\.relation, 'auto', TRUE\)/);
    assert.match(sql, /UPDATE site_people sp SET is_active = FALSE/);
    assert.match(sql, /c\.id NOT IN \(SELECT id FROM ended\)/);
    assert.match(sql, /UPDATE vehicles v SET is_active = FALSE WHERE v\.person_id IN \(SELECT id FROM deactivated\)/);
    assert.match(sql, /'person\.deactivated'/);
  });

  it('H2: yetim kisi (user_code NULL + full_name NULL, aktif) pasiflesir, iliskileri ve araclari biter, Sistem audit; kullanici bazli esitlemede calismaz', () => {
    const sql = allSql[5];
    assert.match(sql, /WHERE sp\.user_code IS NULL AND sp\.full_name IS NULL AND sp\.is_active = TRUE AND \$2::INTEGER IS NULL/);
    assert.match(sql, /UPDATE apartment_residencies r SET is_current = FALSE/);
    assert.match(sql, /UPDATE vehicles v SET is_active = FALSE/);
    assert.match(sql, /UPDATE site_people sp SET is_active = FALSE/);
    assert.match(sql, /'Sistem', 'system', 'person\.deactivated'/);
    assert.match(sql, /'reason', 'account_deleted'/);
  });
});

describe('sunucu baglantisi', () => {
  it('server.js peopleRouter\'i kaydeder (moduleRequestRouter\'dan sonra, SPA statik servisinden once)', () => {
    const server = read('server.js');
    assert.match(server, /import \{ peopleRouter \} from '\.\/modules\/people_routes\.js';/);
    const mount = server.indexOf('app.use(peopleRouter);');
    assert.ok(mount > server.indexOf('app.use(moduleRequestRouter);'));
    assert.ok(mount < server.indexOf('webBuildPath, { maxAge'));
  });

  it('katalog: people cekirdek + available (hep acik)', () => {
    const catalog = read('modules/catalog.js');
    assert.match(catalog, /code: 'people',[\s\S]*?core: true,\s*status: MODULE_STATUS_AVAILABLE,/);
  });
});
