// Kisi ve Daire Kayitlari (Faz 2a): migration 031 <-> db.js ayni DDL, ekleyici sema, people_v1 aktarimi ve esitleme SQL'i (DB'siz).
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { DEFAULT_MIGRATIONS_DIR, blankSqlNoise, findUnsafeStatements, listMigrations } from '../scripts/migrate.js';
import { PEOPLE_BACKFILL_CODE, runPeopleBackfill } from '../src/modules/people_backfill.js';
import { DEAD_INTERNAL_ACCOUNT_SQL, SYNC_STEPS, runSyncSteps, siteTiePredicate, siteTieSitesSql } from '../src/modules/people_sync_sql.js';
import { DEAD_INTERNAL_ACCOUNT_SQL as DEAD_INTERNAL_FROM_COMMON } from '../src/modules/people_common.js';

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

  it('db.js ensureDbSchema ayni DDL\'i icerir (yorumlar ve bosluklar disinda birebir; 078 sonrasi: m2 sutunlarini EKLEYEN iki satir HARIC); 030\'dan sonra gelir', () => {
    const normalizedDb = normalizeSql(DB_SOURCE);
    // 031 tarihsel hali degismez (uygulanmis migration); 078 m2 sutunlarini dusurdugunden db.js bu iki ADD COLUMN satirini artik tasimaz.
    const migration = normalizeSql(MIGRATION).replace(/ ALTER TABLE apartments ADD COLUMN IF NOT EXISTS (?:gross|net)_area_m2 NUMERIC\(8,2\);/g, '');
    assert.ok(migration.length > 2000);
    assert.ok(normalizedDb.includes(migration), 'migrations/031 (m2 satirlari haric) ile db.js ayni DDL degil');
    assert.doesNotMatch(normalizedDb, /ADD COLUMN IF NOT EXISTS (?:gross|net)_area_m2/, 'db.js m2 sutunlarini artik EKLEMEZ (078 dusurur)');
    const migration030 = normalizeSql(readFileSync(path.join(DEFAULT_MIGRATIONS_DIR, '030_module_requests.sql'), 'utf8'));
    assert.ok(normalizedDb.indexOf(migration030) < normalizedDb.indexOf(migration));
  });

  it('031 TARIHSEL olarak m2 sutunlarini ekler (degistirilmez); 078 onlari dusurur (zincir sonunda yok), db.js eklemez', () => {
    const sql = normalizeSql(MIGRATION);
    for (const column of ['gross_area_m2', 'net_area_m2']) {
      assert.match(sql, new RegExp(`ALTER TABLE apartments ADD COLUMN IF NOT EXISTS ${column} NUMERIC\\(8,2\\);`), column);
    }
    const drop = listMigrations(DEFAULT_MIGRATIONS_DIR).find((m) => m.number === 78);
    assert.ok(drop, '078 yok');
    assert.match(normalizeSql(drop.sql), /ALTER TABLE apartments DROP COLUMN IF EXISTS gross_area_m2, DROP COLUMN IF EXISTS net_area_m2;/);
    assert.doesNotMatch(normalizeSql(DB_SOURCE), /(?:gross|net)_area_m2/);
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

  it('S4/S11: tetikleyici kilit sirasini izler (apartments id sirasiyla FOR UPDATE, SONRA kisi/iliski/arac) ve YALNIZ aktif->pasif gecen kisiler icin audit yazar', () => {
    const fn = /CREATE OR REPLACE FUNCTION trg_users_preserve_site_people\(\) RETURNS trigger AS \$\$([\s\S]*?)\$\$ LANGUAGE plpgsql;/.exec(MIGRATION)?.[1];
    const body = fn.replace(/--.*$/gm, ' ').replace(/\s+/g, ' ');
    const lockAt = body.indexOf('PERFORM a.id FROM apartments a WHERE a.resident_user_code = OLD.user_code');
    assert.ok(lockAt >= 0, 'silinen kullanicinin daireleri once kilitlenir');
    assert.match(body, /ORDER BY a\.id FOR UPDATE;/);
    assert.match(body, /a\.id IN \(SELECT am\.apartment_id FROM apartment_memberships am WHERE am\.user_code = OLD\.user_code\)/);
    assert.match(body, /a\.id IN \( SELECT r\.apartment_id FROM apartment_residencies r INNER JOIN site_people sp ON sp\.id = r\.person_id WHERE sp\.user_code = OLD\.user_code AND r\.is_current \)/);
    const auditAt = body.indexOf('INSERT INTO audit_log');
    const updateAt = body.indexOf('UPDATE site_people SET');
    assert.ok(lockAt < auditAt && auditAt < updateAt, 'sira: daire kilidi -> audit (henuz aktif olanlar) -> guncellemeler');
    assert.match(body, /FROM site_people sp WHERE sp\.user_code = OLD\.user_code AND sp\.is_active;/, 'zaten pasif kisiler icin yeni audit satiri yazilmaz');
  });

  it('T3: admin kullanici silme adim 0 daire kilidi, tetikleyiciyle AYNI kumeyi kilitler (uyelik + sakin gostergesi + guncel CRM iliskisi, id sirasi, FOR UPDATE)', () => {
    const fn = /CREATE OR REPLACE FUNCTION trg_users_preserve_site_people\(\) RETURNS trigger AS \$\$([\s\S]*?)\$\$ LANGUAGE plpgsql;/.exec(MIGRATION)?.[1];
    const trigger = /PERFORM a\.id (FROM apartments a WHERE .*?ORDER BY a\.id FOR UPDATE;)/.exec(fn.replace(/--.*$/gm, ' ').replace(/\s+/g, ' '))?.[1];
    assert.ok(trigger, 'tetikleyici kilit sorgusu bulundu');
    const route = read('routes/admin_routes.js');
    const at = route.indexOf('// 0. Kilit sirasi (apartments');
    assert.ok(at >= 0, 'adim 0 yorumu bulundu');
    const routeSql = /`(SELECT a\.id FROM apartments a[\s\S]*?ORDER BY a\.id FOR UPDATE)`/.exec(route.slice(at))?.[1];
    assert.ok(routeSql, 'adim 0 kilit sorgusu bulundu');
    // $1 <-> OLD.user_code disinda iki sorgu BIREBIR ayni olmali (bosluk farklari haric)
    const flatRoute = routeSql.replace(/\$1/g, 'OLD.user_code').replace(/\s+/g, ' ').replace(/\( /g, '(').replace(/ \)/g, ')');
    const flatTrigger = trigger.replace(/;$/, '').replace(/\( /g, '(').replace(/ \)/g, ')');
    assert.equal(flatRoute.replace(/^SELECT a\.id /, ''), flatTrigger);
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
    const sql = allSql[1]; // desired kumesi (INSERT_PEOPLE ve ortak yardimci ayni tanimi kullanir)
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

  it('S1/H1: hesapsiz kisiyle ayni e-postaya sahip, bu sitede BAGI olan kullanici bulunursa user_code baglanir; ad/telefon/e-posta bosalir; bag tanimi ORTAK yardimci', () => {
    const sql = allSql[0];
    assert.match(sql, /^UPDATE site_people sp SET user_code = u\.user_code, full_name = NULL, phone = NULL, email = NULL, updated_at = NOW\(\) FROM users u WHERE/);
    assert.match(sql, /sp\.user_code IS NULL AND sp\.is_active = TRUE AND sp\.email IS NOT NULL AND lower\(u\.email\) = lower\(sp\.email\)/);
    assert.match(sql, /u\.email NOT LIKE '%@ahbu\.local'/, 'dahili daire hesabi e-postasi eslestirmeye girmez');
    // baglama YALNIZ ortak "sitede bag" tanimiyla yapilir (createPerson/addResidency da ayni yardimciyi kullanir)
    assert.ok(sql.includes(normalizeSql(siteTiePredicate('u.user_code', 'sp.site_code'))), 'LINK ortak siteTiePredicate kullanir');
    assert.match(sql, /NOT EXISTS \( SELECT 1 FROM site_people x WHERE x\.site_code = sp\.site_code AND x\.user_code = u\.user_code \)/);
  });

  it('T5: sync LINK pasif hesabi baglamaz (users.is_active ortak siteTiePredicate icinde, tek tanim); T6: kullanici bazli LINK sp.site_code\'u kullanicinin bag sitelerine siniriyor (siteTieSitesSql, indeks dostu)', () => {
    const sql = allSql[0];
    assert.ok(sql.includes('EXISTS (SELECT 1 FROM users tie_u WHERE tie_u.user_code = u.user_code AND tie_u.is_active = TRUE)'), 'pasif hesap baglanmaz');
    // T6: yalniz kullanici filtresi VARKEN ($2) site_code, kullanicinin bag sitelerinin kumesiyle sinirlanir (tum site_people taranmaz)
    const restriction = normalizeSql(`AND ($2::INTEGER IS NULL OR sp.site_code IN (${siteTieSitesSql('$2::INTEGER')}))`);
    assert.ok(sql.includes(restriction), 'kullanici bazli site siniri');
    assert.ok(sql.indexOf(restriction) < sql.indexOf('EXISTS (SELECT 1 FROM users tie_u'), 'site siniri, ortak yuklemden once');
    // kapsamli (site/kullanici) sorgu parametreleri degismedi: [$1 site, $2 kullanici]
    assert.equal(/\$3/.test(sql), false);
  });

  it('S1: siteTiePredicate YALNIZ aktif daire uyeligi ve resident_user_code gostergesidir; site_memberships (STAFF/BOARD_MEMBER/RESIDENT) ve yoneticilik bag degildir', () => {
    const predicate = normalizeSql(siteTiePredicate('X.user', 'Y.site'));
    assert.match(predicate, /EXISTS \(SELECT 1 FROM users tie_u WHERE tie_u\.user_code = X\.user AND tie_u\.is_active = TRUE\) AND Y\.site IN \(/, 'pasif hesap bag sayilmaz (T5)');
    assert.match(predicate, /SELECT tie_a\.site_code FROM apartment_memberships tie_am INNER JOIN apartments tie_a ON tie_a\.id = tie_am\.apartment_id WHERE tie_am\.user_code = X\.user AND tie_am\.is_active = TRUE AND tie_a\.is_active = TRUE UNION/);
    assert.match(predicate, /SELECT tie_r\.site_code FROM apartments tie_r WHERE tie_r\.resident_user_code = X\.user AND tie_r\.is_active = TRUE/);
    assert.equal(/site_memberships|site_manager_sites|role/i.test(predicate), false);
  });


  it('dahili (@ahbu.local) daire hesabinda iletisim e-postasi apartments.resident_email\'den kisi kaydina yazilir', () => {
    assert.match(allSql[1], /CASE WHEN u\.email LIKE '%@ahbu\.local' THEN MAX\(d\.contact_email\) ELSE NULL END/);
  });

  it('T4: PASIF dahili daire hesabina esitleme YENI kisi acmaz (CRM\'den hesaptan koparilip duzenlenen kisinin yerine hayalet satir dogmaz); tanim people_common ile ORTAK', () => {
    assert.ok(allSql[1].includes(`WHERE NOT ${DEAD_INTERNAL_ACCOUNT_SQL} GROUP BY`), 'INSERT adimi pasif dahili hesabi disarida birakir');
    assert.equal(DEAD_INTERNAL_ACCOUNT_SQL, "(u.user_code IS NOT NULL AND u.email LIKE '%@ahbu.local' AND u.is_active = FALSE)");
    assert.equal(DEAD_INTERNAL_ACCOUNT_SQL, DEAD_INTERNAL_FROM_COMMON, 'tek tanim: people_common ayni sabiti yeniden dis aktarir');
    // diger adimlar (kisi OLUSTURMAYAN) bu kosulu tasimaz: yalniz INSERT adimi
    for (const index of [0, 2, 3, 4, 5]) {
      assert.equal(allSql[index].includes('NOT (u.user_code IS NOT NULL AND u.email LIKE'), false, `adim ${index}`);
    }
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

  it('S2b: esitleme kaynakli otomatik pasiflestirme de kisiyi hesaptan KOPARIR: users\'taki ad/telefon/e-posta kopyalanir, user_code NULL', () => {
    const sql = allSql[4];
    assert.match(sql, /deactivated AS \( UPDATE site_people sp SET is_active = FALSE, full_name = COALESCE\(NULLIF\(u\.full_name, ''\), sp\.full_name\), phone = COALESCE\(NULLIF\(u\.phone_number, ''\), sp\.phone\)/);
    assert.match(sql, /WHEN u\.email LIKE '%@ahbu\.local' THEN COALESCE\( \(SELECT a\.resident_email FROM apartments a WHERE a\.resident_user_code = sp\.user_code AND a\.site_code = sp\.site_code ORDER BY a\.id LIMIT 1\), sp\.email \) ELSE u\.email END, user_code = NULL, updated_at = NOW\(\) FROM users u WHERE u\.user_code = sp\.user_code AND sp\.id IN \(SELECT person_id FROM ended\)/);
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
