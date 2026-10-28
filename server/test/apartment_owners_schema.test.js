// Coklu malik (migration 104) sema testi (DB'siz): migration dosyasi <-> apartment_owners_schema.js adimlari ayni, ekleyici / idempotent, adim sirasi,
// ayni adli indeks, tetikleyici islev govdeleri (muhatapsiz daire olusamaz), acilis (ensure) davranisi sahte istemciyle, db.js baglantisi.
// Gercek PostgreSQL davranisi: scripts/qa_coklu_malik.mjs (yukseltme, garantiler, hizmetler).
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { DEFAULT_MIGRATIONS_DIR, blankSqlNoise, findUnsafeStatements, listMigrations } from '../scripts/migrate.js';
import {
  APARTMENT_OWNERS_CHECK,
  APARTMENT_OWNERS_FUNCTIONS,
  APARTMENT_OWNERS_INDEX,
  APARTMENT_OWNERS_MARKER,
  APARTMENT_OWNERS_STEPS,
  APARTMENT_OWNERS_TRIGGERS,
  HOLDER_BACKFILL_SQL,
  HOLDER_PENDING_SQL,
  apartmentOwnersMigrationBody,
  ensureApartmentOwnersSchema,
  schemaTuning,
} from '../src/modules/apartment_owners_schema.js';

const here = path.dirname(fileURLToPath(import.meta.url));
const read = (relative) => readFileSync(path.join(here, '..', relative), 'utf8').replace(/\r\n/g, '\n');
const MIGRATION = read('migrations/104_apartment_multi_owner.sql');
const DB_SOURCE = read('src/db.js');

const normalize = (text) =>
  text
    .replace(/\/\*[\s\S]*?\*\//g, ' ')
    .replace(/--.*$/gm, ' ')
    .replace(/\s+/g, ' ')
    .trim();

describe('migration 104: coklu malik', () => {
  it('104 var, kimligi dogru, calistirici icin guvenli (ust duzey BEGIN/COMMIT yok)', () => {
    const entry = listMigrations(DEFAULT_MIGRATIONS_DIR).find((m) => m.number === 104);
    assert.ok(entry, '104 numarali migration yok');
    assert.equal(entry.file, '104_apartment_multi_owner.sql');
    assert.deepEqual(findUnsafeStatements(MIGRATION), []);
  });

  it('dosya govdesi apartment_owners_schema.js adimlarinin BIREBIR birlesimidir (yorumlar ve bosluklar disinda)', () => {
    assert.equal(normalize(MIGRATION), normalize(apartmentOwnersMigrationBody()));
  });

  it('ILK ifade LOCK TABLE (yazanlar migration boyunca bekler); sonra kolon; sira baglayicidir', () => {
    const names = APARTMENT_OWNERS_STEPS.map((step) => step.name);
    assert.deepEqual(names, [
      'lock',
      'column',
      'beforeFunction',
      'afterFunction',
      'checkFunction',
      'beforeTrigger',
      'afterTrigger',
      'backfill',
      'checkTriggerInsert',
      'checkTriggerUpdate',
      'checkTriggerDelete',
      'indexSwap',
      'check',
      'closingBackfill',
    ]);
    assert.match(APARTMENT_OWNERS_STEPS[0].sql, /^LOCK TABLE apartment_residencies IN SHARE ROW EXCLUSIVE MODE;$/);
    // yedekleme, ertelenmis kisit tetikleyicileri kurulmadan ONCE (aksi halde eski malik satirlari hata verirdi); indeks degisimi sonra
    assert.ok(names.indexOf('backfill') < names.indexOf('checkTriggerInsert'));
    assert.ok(names.indexOf('beforeTrigger') < names.indexOf('backfill'), 'satir tetikleyicisi yedeklemeden once: arada eklenen ilk malik de muhatap olur');
    assert.ok(names.indexOf('checkTriggerDelete') < names.indexOf('indexSwap'));
    assert.ok(names.indexOf('indexSwap') < names.indexOf('check'));
    assert.equal(names.at(-1), 'closingBackfill');
  });

  it('ekleyici ve idempotent: tablo / sutun / indeks yaratimi IF NOT EXISTS, islevler OR REPLACE, tetikleyiciler ve kisit kosullu; veri silme yok', () => {
    const sql = normalize(blankSqlNoise(MIGRATION));
    assert.equal(/DELETE\s+FROM|TRUNCATE|DROP\s+(TABLE|COLUMN|FUNCTION|TRIGGER)/i.test(sql), false, 'silme / dusurme yok');
    const full = normalize(MIGRATION);
    assert.match(full, /ALTER TABLE apartment_residencies ADD COLUMN IF NOT EXISTS is_account_holder BOOLEAN NOT NULL DEFAULT FALSE;/);
    assert.deepEqual(full.match(/CREATE\s+FUNCTION/gi) ?? [], [], 'yalniz CREATE OR REPLACE FUNCTION');
    assert.equal((full.match(/CREATE OR REPLACE FUNCTION/g) ?? []).length, 3);
    for (const trigger of APARTMENT_OWNERS_TRIGGERS) {
      assert.match(full, new RegExp(`tgname = '${trigger}' AND tgrelid = 'apartment_residencies'::regclass AND NOT tgisinternal`), `${trigger} kosullu`);
    }
    assert.match(full, new RegExp(`conname = '${APARTMENT_OWNERS_CHECK}' AND conrelid = 'apartment_residencies'::regclass`));
    // veri yazan TEK ust duzey ifade yedeklemedir (bayrak disinda hicbir sutun, updated_at dahil)
    assert.equal((full.match(/UPDATE apartment_residencies r SET is_account_holder = TRUE/g) ?? []).length, 2, 'yedekleme iki kez (ara + kapanis), ayni ifade');
    assert.doesNotMatch(HOLDER_BACKFILL_SQL, /updated_at/);
  });

  it('yedekleme: yalniz "guncel malik var ama muhatap yok" dairede EN ESKI guncel malik; eski tek malik kayipsiz muhatap olur', () => {
    const backfill = normalize(HOLDER_BACKFILL_SQL);
    assert.match(backfill, /SELECT MIN\(o\.id\) FROM apartment_residencies o WHERE o\.apartment_id = r\.apartment_id AND o\.is_current AND o\.relation = 'owner'/);
    assert.match(backfill, /NOT EXISTS \( SELECT 1 FROM apartment_residencies h WHERE h\.apartment_id = r\.apartment_id AND h\.is_current AND h\.relation = 'owner' AND h\.is_account_holder \)/);
    assert.match(HOLDER_PENDING_SQL, /SELECT EXISTS \(/);
  });

  it('eski tekil indeks AYNI ADLA muhatap indeksine cevrilir: ad korunur (eski surum "IF NOT EXISTS" ile ayni adi bulur ve atlar)', () => {
    assert.equal(APARTMENT_OWNERS_INDEX, 'uq_apartment_residencies_owner');
    const swap = normalize(APARTMENT_OWNERS_STEPS.find((s) => s.name === 'indexSwap').sql);
    assert.match(swap, /indexdef NOT LIKE '%is_account_holder%' \) THEN DROP INDEX uq_apartment_residencies_owner;/);
    assert.match(swap, /CREATE UNIQUE INDEX uq_apartment_residencies_owner ON apartment_residencies \(apartment_id\) WHERE is_current AND relation = 'owner' AND is_account_holder;/);
    // 031 tarihsel DDL'i ve db.js'in eski ifadesi DEGISMEDI: ad var oldugundan atlanir (geri alma guvenli)
    assert.match(read('migrations/031_people_and_apartments.sql'), /CREATE UNIQUE INDEX IF NOT EXISTS uq_apartment_residencies_owner\s+ON apartment_residencies \(apartment_id\) WHERE is_current AND relation = 'owner';/);
    assert.match(DB_SOURCE, /CREATE UNIQUE INDEX IF NOT EXISTS uq_apartment_residencies_owner/);
  });

  it('CHECK: muhatap bayragi yalniz guncel malik kaydinda true olabilir', () => {
    const check = normalize(APARTMENT_OWNERS_STEPS.find((s) => s.name === 'check').sql);
    assert.match(check, /CHECK \(NOT is_account_holder OR \(is_current AND relation = 'owner'\)\)/);
  });
});

describe('tetikleyici islevleri (govde metni)', () => {
  const body = (name) => APARTMENT_OWNERS_STEPS.find((s) => s.name === name).sql;

  it('tum islevler surum isareti tasir (katalogda prosrc aranir) ve plpgsql', () => {
    for (const name of ['beforeFunction', 'afterFunction', 'checkFunction']) {
      assert.ok(body(name).includes(`-- ${APARTMENT_OWNERS_MARKER}`), name);
      assert.match(body(name), /LANGUAGE plpgsql;$/);
    }
    assert.equal(APARTMENT_OWNERS_FUNCTIONS.length, 3);
  });

  it('BEFORE: malik olmayan satirda bayrak kapanir; ilk malik muhatap olur; izinsiz ikinci malik 23505 / eski indeks adiyla reddedilir', () => {
    const sql = normalize(body('beforeFunction'));
    assert.match(sql, /IF NOT \(NEW\.is_current AND NEW\.relation = 'owner'\) THEN NEW\.is_account_holder := FALSE; RETURN NEW;/);
    assert.match(sql, /NEW\.is_account_holder := TRUE; RETURN NEW;/);
    assert.match(sql, /current_setting\('app\.multi_owner', TRUE\), ''\) <> 'on' THEN RAISE EXCEPTION 'apartment already has a current owner' USING ERRCODE = '23505', CONSTRAINT = 'uq_apartment_residencies_owner';/);
    // bayrak elle degistirilirken (muhatap degisimi) iyilestirme calismaz: yalniz eski ve yeni bayrak ikisi de FALSE iken
    assert.match(sql, /IF NOT NEW\.is_account_holder AND NOT OLD\.is_account_holder AND NOT EXISTS/);
  });

  it('AFTER: ayrilan muhatabin yerine EN ESKI baska guncel malik gecer; acik muhatap degisiminde (satir malik kaliyor) hicbir sey yapmaz; Sistem denetimi hata yutar', () => {
    const sql = normalize(body('afterFunction'));
    assert.match(sql, /IF OLD\.is_current AND OLD\.relation = 'owner' AND OLD\.is_account_holder AND NOT \(TG_OP = 'UPDATE' AND NEW\.is_current AND NEW\.relation = 'owner' AND NEW\.apartment_id = OLD\.apartment_id\) THEN/);
    assert.match(sql, /ORDER BY o\.id LIMIT 1 FOR UPDATE;/);
    assert.match(sql, /UPDATE apartment_residencies SET is_account_holder = TRUE, updated_at = NOW\(\) WHERE id = v_next;/);
    assert.match(sql, /INSERT INTO audit_log \(actor_name, actor_role, action, site_code, target_type, target_id, details\)/);
    assert.match(sql, /'Sistem', 'system', 'apartment\.account_holder_changed'/);
    assert.match(sql, /EXCEPTION WHEN OTHERS THEN NULL;/);
    // tetikleyici yalniz muhatap olan satirlar icin cagrilir
    assert.match(normalize(body('afterTrigger')), /WHEN \(OLD\.is_account_holder\)/);
  });

  it('ERTELENMIS kisit: guncel maliki olup muhatabi olmayan daire islem sonunda 23514 ile geri alinir; uc ayri tetikleyici, her biri yalniz malik satirlarinda', () => {
    const fn = normalize(body('checkFunction'));
    assert.match(fn, /USING ERRCODE = '23514', CONSTRAINT = 'chk_apartment_residencies_account_holder';/);
    for (const name of ['checkTriggerInsert', 'checkTriggerUpdate', 'checkTriggerDelete']) {
      const sql = normalize(body(name));
      assert.match(sql, /CREATE CONSTRAINT TRIGGER/, name);
      assert.match(sql, /DEFERRABLE INITIALLY DEFERRED FOR EACH ROW/, name);
      assert.match(sql, /WHEN \(/, name);
    }
    assert.match(normalize(body('checkTriggerUpdate')), /WHEN \(\(OLD\.is_current AND OLD\.relation = 'owner'\) OR \(NEW\.is_current AND NEW\.relation = 'owner'\)\)/);
  });
});

describe('ensureApartmentOwnersSchema (sahte istemci)', () => {
  const COMPLETE = {
    has_table: true,
    has_column: true,
    functions: [...APARTMENT_OWNERS_FUNCTIONS],
    triggers: [...APARTMENT_OWNERS_TRIGGERS],
    owner_index: 'CREATE UNIQUE INDEX uq_apartment_residencies_owner ON public.apartment_residencies USING btree (apartment_id) WHERE (is_current AND (relation = \'owner\'::text) AND is_account_holder)',
    has_check: true,
  };

  function fakeClient({ catalog = COMPLETE, pending = false, failOn = null } = {}) {
    const log = [];
    return {
      log,
      async query(text) {
        const sql = String(text).replace(/\s+/g, ' ').trim();
        log.push(sql);
        if (/^SELECT to_regclass\('public\.apartment_residencies'\)/.test(sql) || /^SELECT to_regclass/.test(sql)) return { rows: [catalog] };
        if (/^SELECT EXISTS \( SELECT 1 FROM apartment_residencies r/.test(sql)) return { rows: [{ pending }] };
        if (failOn && failOn.test(sql)) {
          const error = failOn.error ?? Object.assign(new Error('xx'), { code: '40P01' });
          if (failOn.remaining === undefined || failOn.remaining-- > 0) throw error;
        }
        return { rows: [], rowCount: 0 };
      },
    };
  }

  it('her sey kurulu ve yedekleme bekleyen yoksa: yalniz iki OKUMA, hicbir DDL / kilit', async () => {
    const client = fakeClient();
    const result = await ensureApartmentOwnersSchema(client);
    assert.deepEqual(result, { applied: false });
    assert.equal(client.log.length, 2);
    assert.equal(client.log.some((sql) => /^(BEGIN|LOCK|ALTER|CREATE|DO|UPDATE)/.test(sql)), false);
  });

  it('tablo yoksa hicbir sey yapmaz', async () => {
    const client = fakeClient({ catalog: { ...COMPLETE, has_table: false } });
    assert.deepEqual(await ensureApartmentOwnersSchema(client), { applied: false });
    assert.equal(client.log.length, 1);
  });

  for (const [label, patch] of [
    ['kolon eksik', { has_column: false }],
    ['islev eksik / eski surum', { functions: APARTMENT_OWNERS_FUNCTIONS.slice(1) }],
    ['tetikleyici eksik', { triggers: APARTMENT_OWNERS_TRIGGERS.slice(1) }],
    ['indeks hala eski tanimda', { owner_index: 'CREATE UNIQUE INDEX uq_apartment_residencies_owner ON public.apartment_residencies USING btree (apartment_id) WHERE (is_current AND (relation = \'owner\'::text))' }],
    ['indeks hic yok', { owner_index: null }],
    ['CHECK eksik', { has_check: false }],
  ]) {
    it(`${label}: TEK transaction'da kilit + tum adimlar sirayla + COMMIT`, async () => {
      const client = fakeClient({ catalog: { ...COMPLETE, ...patch } });
      assert.deepEqual(await ensureApartmentOwnersSchema(client), { applied: true });
      const writes = client.log.slice(client.log.findIndex((sql) => sql === 'BEGIN'));
      assert.equal(writes[0], 'BEGIN');
      assert.match(writes[1], /^SET LOCAL lock_timeout/);
      const steps = writes.slice(2, -1);
      assert.equal(steps.length, APARTMENT_OWNERS_STEPS.length);
      steps.forEach((sql, index) => assert.equal(sql, APARTMENT_OWNERS_STEPS[index].sql.replace(/\s+/g, ' ').trim()));
      assert.equal(writes.at(-1), 'COMMIT');
    });
  }

  it('her sey kurulu ama yedeklenmemis malik varsa (arada eklenen satir) yine uygulanir', async () => {
    const client = fakeClient({ pending: true });
    assert.deepEqual(await ensureApartmentOwnersSchema(client), { applied: true });
    assert.ok(client.log.includes('COMMIT'));
  });

  it('kilit / deadlock (40P01) gecici: ROLLBACK + yeniden deneme; en cok 6 deneme sonra hata yukari cikar', async () => {
    const saved = schemaTuning.retryDelayMs;
    schemaTuning.retryDelayMs = 0;
    try {
      const flaky = fakeClient({ catalog: { ...COMPLETE, has_check: false } });
      const original = flaky.query;
      let failures = 2;
      flaky.query = async (text) => {
        const sql = String(text).replace(/\s+/g, ' ').trim();
        if (/^LOCK TABLE/.test(sql) && failures-- > 0) {
          flaky.log.push(sql);
          throw Object.assign(new Error('deadlock'), { code: '40P01' });
        }
        return original(text);
      };
      assert.deepEqual(await ensureApartmentOwnersSchema(flaky), { applied: true });
      assert.equal(flaky.log.filter((sql) => sql === 'ROLLBACK').length, 2);
      assert.equal(flaky.log.filter((sql) => sql === 'COMMIT').length, 1);

      const stuck = fakeClient({ catalog: { ...COMPLETE, has_check: false } });
      const base = stuck.query;
      stuck.query = async (text) => {
        if (/^LOCK TABLE/.test(String(text).trim())) throw Object.assign(new Error('timeout'), { code: '55P03' });
        return base(text);
      };
      await assert.rejects(() => ensureApartmentOwnersSchema(stuck), (error) => error.code === '55P03');
      assert.equal(stuck.log.filter((sql) => sql === 'BEGIN').length, 6);
    } finally {
      schemaTuning.retryDelayMs = saved;
    }
  });

  it('kalici hata (ornegin 23505): ROLLBACK, COMMIT YOK, hata yukari cikar (tekrar denenmez)', async () => {
    const client = fakeClient({ catalog: { ...COMPLETE, has_check: false } });
    const base = client.query;
    client.query = async (text) => {
      if (/^ALTER TABLE apartment_residencies ADD COLUMN/.test(String(text).trim())) throw Object.assign(new Error('bozuk'), { code: 'XX000' });
      return base(text);
    };
    await assert.rejects(() => ensureApartmentOwnersSchema(client), (error) => error.code === 'XX000');
    assert.equal(client.log.filter((sql) => sql === 'BEGIN').length, 1);
    assert.ok(client.log.includes('ROLLBACK'));
    assert.equal(client.log.includes('COMMIT'), false);
  });
});

describe('db.js baglantisi', () => {
  it('ensureApartmentOwnersSchema import edilir ve ensureResidencyLogSchema\'dan SONRA, OAuth\'tan ONCE cagrilir (apartment_residencies hazir)', () => {
    assert.match(DB_SOURCE, /import \{ ensureApartmentOwnersSchema \} from '\.\/modules\/apartment_owners_schema\.js';/);
    const owners = DB_SOURCE.indexOf('await ensureApartmentOwnersSchema(client);');
    assert.ok(owners > DB_SOURCE.indexOf('await ensureResidencyLogSchema(client);'));
    assert.ok(owners < DB_SOURCE.indexOf('await ensureOAuthSchema(client);'));
    assert.ok(owners > DB_SOURCE.indexOf('CREATE TABLE IF NOT EXISTS apartment_residencies'), 'dev blok sonrasi');
  });

  it('apartment_owners_schema.js db.js\'i ICE AKTARMAZ (dongu olmasin)', () => {
    assert.doesNotMatch(read('src/modules/apartment_owners_schema.js'), /from '\.\.\/db\.js'|from '\.\/db\.js'/);
  });
});
