// Site başına hukuk onayı bayrağı (114) şeması + okuma (DB'siz): migration <-> site_legal_gate_schema.js aynı DDL (aynı sıra), mevcut siteler AÇIK kalır (DEFAULT TRUE ile eklenir),
// yeni siteler KAPALI başlar (varsayılan FALSE), self-healing, db.js bağlantısı, her şey yerindeyse ifade yok, readLegalOk kapalı-güvenli,
// hukuk kapısı çağrı noktaları site bazında (sistem geneli platform_settings okunmaz).
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { DEFAULT_MIGRATIONS_DIR, findUnsafeStatements } from '../scripts/migrate.js';
import { SITE_LEGAL_GATE_DDL, SITE_LEGAL_GATE_DDL_ORDER, ensureSiteLegalGateSchema, siteLegalGateTuning } from '../src/modules/site_legal_gate_schema.js';
import { readLegalOk } from '../src/modules/finance_settings.js';

siteLegalGateTuning.retryDelayMs = 1;
const here = path.dirname(fileURLToPath(import.meta.url));
const MIGRATION = readFileSync(path.join(DEFAULT_MIGRATIONS_DIR, '114_site_legal_gate.sql'), 'utf8').replace(/\r\n/g, '\n');
const read = (...parts) => readFileSync(path.join(here, '..', 'src', ...parts), 'utf8');
const DB_SOURCE = read('db.js');
const normalize = (text) => text.replace(/--.*$/gm, ' ').replace(/\s+/g, ' ').trim();

const makeClient = (row, calls = []) => ({
  query: async (text) => {
    const sql = normalize(text);
    calls.push(sql);
    return sql.startsWith('SELECT') ? { rows: [row] } : { rows: [] };
  },
});

describe('site_legal_gate_schema (114)', () => {
  it('migration, DDL ile ayni ifadeler ve ayni sirada; once DEFAULT TRUE (mevcut siteler ACIK), sonra DEFAULT FALSE (yeni siteler KAPALI); veri yeniden yazilmaz', () => {
    const actual = normalize(MIGRATION);
    let cursor = 0;
    for (const name of SITE_LEGAL_GATE_DDL_ORDER) {
      const statement = normalize(SITE_LEGAL_GATE_DDL[name]);
      const at = actual.indexOf(statement, cursor);
      assert.ok(at >= cursor, `sirasiz ya da eksik: ${name}`);
      cursor = at + statement.length;
    }
    assert.match(SITE_LEGAL_GATE_DDL.column, /ADD COLUMN IF NOT EXISTS legal_ok BOOLEAN NOT NULL DEFAULT TRUE/);
    assert.match(SITE_LEGAL_GATE_DDL.newSitesDefault, /ALTER COLUMN legal_ok SET DEFAULT FALSE/);
    assert.ok(!/\b(DROP|TRUNCATE)\b|\b(UPDATE|DELETE) /i.test(actual), 'ekleyici: veri guncelleme / silme yok');
    assert.equal(actual.match(/ALTER TABLE/g).length, SITE_LEGAL_GATE_DDL_ORDER.length);
    assert.deepEqual(findUnsafeStatements(MIGRATION), []);
  });

  it('db.js ensureSiteLegalGateSchema cagirir (kontrol izi 110 sonrasi, people backfill oncesi)', () => {
    assert.ok(DB_SOURCE.includes("import { ensureSiteLegalGateSchema } from './modules/site_legal_gate_schema.js'"));
    const call = DB_SOURCE.indexOf('await ensureSiteLegalGateSchema(client)');
    assert.ok(call > DB_SOURCE.indexOf('await ensureCheckMarkSchema(client)'));
    assert.ok(call < DB_SOURCE.indexOf('await runPeopleBackfill(client)'));
  });

  it('her sey yerindeyse tek katalog sorgusu (DDL ve kilit yok); sites yoksa hicbir sey', async () => {
    const calls = [];
    await ensureSiteLegalGateSchema(makeClient({ has_sites: true, has_column: true, column_default: 'false' }, calls));
    assert.equal(calls.length, 1);
    calls.length = 0;
    await ensureSiteLegalGateSchema(makeClient({ has_sites: false, has_column: false, column_default: null }, calls));
    assert.equal(calls.length, 1);
  });

  it('sutun yoksa iki adim sirayla (once TRUE ile ekle, sonra varsayilan FALSE); lock_timeout sifirlanir', async () => {
    const calls = [];
    await ensureSiteLegalGateSchema(makeClient({ has_sites: true, has_column: false, column_default: null }, calls));
    const alters = calls.filter((s) => s.startsWith('ALTER TABLE'));
    assert.deepEqual(alters, SITE_LEGAL_GATE_DDL_ORDER.map((name) => normalize(SITE_LEGAL_GATE_DDL[name])));
    assert.ok(calls.includes("SET lock_timeout = '2s'") && calls.at(-1) === 'RESET lock_timeout');
  });

  it('kendini onarir: sutun var ama varsayilan hala TRUE (sunucu iki adimin arasinda oldu) -> yalniz varsayilan FALSE yapilir, mevcut degerlere dokunulmaz', async () => {
    const calls = [];
    await ensureSiteLegalGateSchema(makeClient({ has_sites: true, has_column: true, column_default: 'true' }, calls));
    const alters = calls.filter((s) => s.startsWith('ALTER TABLE'));
    assert.deepEqual(alters, [normalize(SITE_LEGAL_GATE_DDL.newSitesDefault)]);
    assert.ok(!calls.some((s) => /^(UPDATE|DELETE)/i.test(s)));
  });

  it('kilitlenme (40P01/55P03) yeniden denenir; baska hata yukari firlatilir ve lock_timeout yine sifirlanir', async () => {
    let attempts = 0;
    const flaky = {
      query: async (text) => {
        const sql = normalize(text);
        if (sql.startsWith('SELECT')) return { rows: [{ has_sites: true, has_column: false, column_default: null }] };
        if (sql.startsWith('ALTER TABLE')) {
          attempts += 1;
          if (attempts < 3) throw Object.assign(new Error('kilit'), { code: '55P03' });
        }
        return { rows: [] };
      },
    };
    await ensureSiteLegalGateSchema(flaky);
    assert.equal(attempts, 4, '2 basarisiz + ilk adim + ikinci adim');

    const resets = [];
    const broken = {
      query: async (text) => {
        const sql = normalize(text);
        if (sql.startsWith('SELECT')) return { rows: [{ has_sites: true, has_column: false, column_default: null }] };
        if (sql.startsWith('RESET')) resets.push(sql);
        if (sql.startsWith('ALTER TABLE')) throw Object.assign(new Error('izin yok'), { code: '42501' });
        return { rows: [] };
      },
    };
    await assert.rejects(ensureSiteLegalGateSchema(broken), (e) => e.code === '42501');
    assert.equal(resets.length, 1);
  });
});

describe('site bazli hukuk kapisi (kod)', () => {
  it('readLegalOk kapali-guvenli: yalniz sites.legal_ok === true acik; satir yok / null / "true" metni / siteCode yok = kapali; sorgu site kodunu tasir', async () => {
    const make = (rows) => {
      const seen = [];
      return { seen, db: { query: async (text, params) => (seen.push([normalize(text), params]), { rows }) } };
    };
    const open = make([{ legal_ok: true }]);
    assert.equal(await readLegalOk(open.db, 42), true);
    assert.deepEqual(open.seen[0], ['SELECT legal_ok FROM sites WHERE site_code = $1', [42]]);
    for (const rows of [[], [{ legal_ok: false }], [{ legal_ok: null }], [{ legal_ok: 'true' }], [{}]]) {
      assert.equal(await readLegalOk(make(rows).db, 42), false, JSON.stringify(rows));
    }
  });

  it('gecikme tazminati ve hatirlatma engelleri sitenin bayragini okur; sistem geneli platform_settings anahtari hicbir finans modulunde okunmaz', () => {
    assert.match(read('modules', 'finance_late_fee.js'), /readLegalOk\(db, siteCode\)/);
    const reminders = read('modules', 'finance_reminders.js');
    assert.match(reminders, /readLegalOk\(db, siteCode\)/);
    assert.match(reminders, /readLegalOk\(client, siteCode\)/);
    assert.match(read('modules', 'finance_settings.js'), /readLegalOk\(client, siteCode\)/);
    for (const file of ['finance_settings.js', 'finance_late_fee.js', 'finance_reminders.js', 'finance_reminder_queue.js', 'finance_4b_routes.js']) {
      assert.doesNotMatch(read('modules', file).replace(/^\s*\/\/.*$/gm, ''), /finance\.legal_ok|LEGAL_OK_KEY|platform_settings/, file);
    }
  });

  it('super kullanici ucu: site basina, requireSuperUser, islem izi (finance.legal_gate.updated) site kodunu tasir; yeni site INSERT\'leri legal_ok yazmaz (varsayilan KAPALI)', () => {
    const routes = read('modules', 'finance_4b_routes.js');
    assert.match(routes, /put\('\/admin\/sites\/:siteCode\/finance-legal-gate', authRequired, requireSuperUser/);
    assert.match(routes, /get\('\/admin\/sites\/:siteCode\/finance-legal-gate', authRequired, requireSuperUser/);
    const settings = read('modules', 'finance_settings.js');
    assert.match(settings, /recordFinanceAudit\(client, actor, 'finance\.legal_gate\.updated', siteCode, siteCode, \{ enabled, previous:/);
    for (const file of [['services', 'site_service.js'], ['services', 'site_setup_core.js']]) {
      assert.doesNotMatch(read(...file), /legal_ok/, `${file.join('/')}: site olusturma bayragi acmaz`);
    }
  });
});
