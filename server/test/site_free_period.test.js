// Kampanya "şimdi abone olana 2 ay ücretsiz" (115) testi (DB'siz): migration <-> site_free_period_schema.js aynı DDL (aynı sıra), ekleyici / idempotent,
// db.js bağlantısı, yalnız eksik sütun için ALTER; saf yardımcılar (durum, gün sayısı, gövde doğrulaması, sıra) ve mapSiteRow alanları.
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { DEFAULT_MIGRATIONS_DIR, findUnsafeStatements } from '../scripts/migrate.js';
import {
  SITE_FREE_PERIOD_DDL,
  SITE_FREE_PERIOD_DDL_ORDER,
  ensureSiteFreePeriodSchema,
  siteFreePeriodTuning,
} from '../src/modules/site_free_period_schema.js';
import { freePeriodFields, freePeriodOrderError, isValidIsoDate, parseFreePeriodBody } from '../src/modules/site_free_period.js';
import { mapSiteRow } from '../src/utils/helpers.js';

siteFreePeriodTuning.retryDelayMs = 1;
const here = path.dirname(fileURLToPath(import.meta.url));
const MIGRATION = readFileSync(path.join(DEFAULT_MIGRATIONS_DIR, '115_site_free_period.sql'), 'utf8').replace(/\r\n/g, '\n');
const DB_SOURCE = readFileSync(path.join(here, '..', 'src', 'db.js'), 'utf8');
const normalize = (text) => text.replace(/--.*$/gm, ' ').replace(/\s+/g, ' ').trim();

describe('site_free_period_schema (115)', () => {
  it('migration, DDL ile ayni ifadeler ve ayni sirada; ekleyici ve idempotent; fiyat / sir yok', () => {
    const actual = normalize(MIGRATION);
    let cursor = 0;
    for (const name of SITE_FREE_PERIOD_DDL_ORDER) {
      const statement = normalize(SITE_FREE_PERIOD_DDL[name]);
      const at = actual.indexOf(statement, cursor);
      assert.ok(at >= cursor, `sirasiz ya da eksik: ${name}`);
      cursor = at + statement.length;
    }
    assert.ok(!/\b(DROP|TRUNCATE)\b|; ?(DELETE|UPDATE) /i.test(actual));
    for (const add of actual.match(/ADD COLUMN[^;]*/g)) assert.match(add, /ADD COLUMN IF NOT EXISTS/);
    assert.equal(actual.match(/ADD COLUMN/g).length, SITE_FREE_PERIOD_DDL_ORDER.length);
    assert.deepEqual(findUnsafeStatements(MIGRATION), []);
  });

  it('db.js ensureSiteFreePeriodSchema cagirir (ensureDriveHealthSchema sonrasi, ensureDbSchema blogu icinde)', () => {
    assert.ok(DB_SOURCE.includes("import { ensureSiteFreePeriodSchema } from './modules/site_free_period_schema.js'"));
    assert.ok(DB_SOURCE.indexOf('await ensureSiteFreePeriodSchema(client)') > DB_SOURCE.indexOf('await ensureDriveHealthSchema(client)'));
  });

  it('her sey varsa tek katalog sorgusu; sites yoksa hicbir sey; eksikse yalniz eksik sutun; lock_timeout sifirlanir', async () => {
    const calls = [];
    const make = (row) => ({
      query: async (text) => {
        calls.push(normalize(text));
        return { rows: [row] };
      },
    });
    await ensureSiteFreePeriodSchema(make({ has_table: true, columns: ['name', 'subscription_started_at', 'free_until'] }));
    assert.equal(calls.length, 1);

    calls.length = 0;
    await ensureSiteFreePeriodSchema(make({ has_table: false, columns: [] }));
    assert.equal(calls.length, 1);

    calls.length = 0;
    await ensureSiteFreePeriodSchema(make({ has_table: true, columns: ['name', 'subscription_started_at'] }));
    const alters = calls.filter((s) => s.startsWith('ALTER TABLE'));
    assert.equal(alters.length, 1);
    assert.match(alters[0], /free_until DATE/);
    assert.ok(calls.includes("SET lock_timeout = '2s'") && calls.includes('RESET lock_timeout'));
  });

  it('kilitlenme (40P01) yeniden denenir; baska hata yukari firlatilir ve lock_timeout yine sifirlanir', async () => {
    let attempts = 0;
    const calls = [];
    const flaky = {
      query: async (text) => {
        const sql = normalize(text);
        calls.push(sql);
        if (sql.startsWith('SELECT')) return { rows: [{ has_table: true, columns: [] }] };
        if (sql.startsWith('ALTER TABLE')) {
          attempts += 1;
          if (attempts < 3) throw Object.assign(new Error('deadlock'), { code: '40P01' });
        }
        return { rows: [] };
      },
    };
    await ensureSiteFreePeriodSchema(flaky);
    assert.equal(attempts, 4, '2 sutun: ilki 3 denemede, ikincisi 1 denemede');

    const broken = {
      query: async (text) => {
        const sql = normalize(text);
        if (sql.startsWith('SELECT')) return { rows: [{ has_table: true, columns: [] }] };
        if (sql.startsWith('ALTER TABLE')) throw Object.assign(new Error('boom'), { code: 'XX000' });
        calls.push(sql);
        return { rows: [] };
      },
    };
    calls.length = 0;
    await assert.rejects(() => ensureSiteFreePeriodSchema(broken), /boom/);
    assert.ok(calls.includes('RESET lock_timeout'));
  });
});

describe('site_free_period (saf yardimcilar)', () => {
  const at = (iso) => new Date(`${iso}T09:00:00+03:00`);

  it('freePeriodFields: tanimsiz -> none; gelecek / bugun -> active (kalan gun); gecmis -> ended', () => {
    const now = at('2026-10-29');
    assert.deepEqual(freePeriodFields({}, now), { subscription_started_at: null, free_until: null, free_period_state: 'none', free_period_days_left: null });
    assert.deepEqual(freePeriodFields({ subscription_started_at: '2026-10-29', free_until: '2026-12-29' }, now), {
      subscription_started_at: '2026-10-29',
      free_until: '2026-12-29',
      free_period_state: 'active',
      free_period_days_left: 61,
    });
    assert.equal(freePeriodFields({ free_until: '2026-10-29' }, now).free_period_state, 'active', 'son gun dahil ucretsiz');
    assert.equal(freePeriodFields({ free_until: '2026-10-29' }, now).free_period_days_left, 0);
    const ended = freePeriodFields({ subscription_started_at: '2026-06-01', free_until: '2026-10-28' }, now);
    assert.equal(ended.free_period_state, 'ended');
    assert.equal(ended.free_period_days_left, null);
    assert.equal(freePeriodFields({ free_until: 'bozuk' }, now).free_period_state, 'none');
  });

  it('freePeriodFields: Istanbul takvimi (gece yarisindan once/sonra) ve Date girdisi', () => {
    const lateNight = new Date('2026-10-29T21:30:00Z'); // Istanbul'da 30 Ekim 00:30
    assert.equal(freePeriodFields({ free_until: '2026-10-29' }, lateNight).free_period_state, 'ended');
    assert.equal(freePeriodFields({ free_until: new Date('2026-12-29T12:00:00Z') }, at('2026-10-29')).free_until, '2026-12-29');
  });

  it('isValidIsoDate: gercek takvim gunu, 2020-2100', () => {
    for (const ok of ['2026-12-29', '2028-02-29']) assert.equal(isValidIsoDate(ok), true, ok);
    for (const bad of ['2026-02-30', '2026-13-01', '29.12.2026', '2026-1-1', '2019-12-31', '2101-01-01', '', null, 20261229]) {
      assert.equal(isValidIsoDate(bad), false, String(bad));
    }
  });

  it('parseFreePeriodBody: yok -> undefined, null -> temizle, gecerli tarih; gecersiz -> hata', () => {
    assert.deepEqual(parseFreePeriodBody({}).value, { subscriptionStartedAt: undefined, freeUntil: undefined });
    assert.deepEqual(parseFreePeriodBody(undefined).value, { subscriptionStartedAt: undefined, freeUntil: undefined });
    assert.deepEqual(parseFreePeriodBody({ subscription_started_at: null, free_until: '2026-12-29' }).value, { subscriptionStartedAt: null, freeUntil: '2026-12-29' });
    assert.match(parseFreePeriodBody({ free_until: '2026-02-30' }).error, /Ücretsiz dönem sonu/);
    assert.match(parseFreePeriodBody({ subscription_started_at: 'dun' }).error, /Abonelik başlangıcı/);
    assert.match(parseFreePeriodBody({ free_until: 7 }).error, /Ücretsiz dönem sonu/);
  });

  it('freePeriodOrderError: bitis baslangictan once olamaz; eksik taraf denetlenmez', () => {
    assert.equal(freePeriodOrderError('2026-10-29', '2026-12-29'), null);
    assert.equal(freePeriodOrderError('2026-10-29', '2026-10-29'), null);
    assert.match(freePeriodOrderError('2026-10-29', '2026-10-28'), /önce olamaz/);
    assert.equal(freePeriodOrderError(null, '2026-10-28'), null);
    assert.equal(freePeriodOrderError('2026-10-29', null), null);
    assert.equal(freePeriodOrderError(undefined, undefined), null);
  });

  it('mapSiteRow ekleyici alanlari tasir (eski satirda none); mevcut alanlar degismez', () => {
    const base = { id: 5, name: 'Gül Sitesi', approval_status: 'approved' };
    const plain = mapSiteRow(base);
    assert.equal(plain.free_period_state, 'none');
    assert.equal(plain.free_until, null);
    assert.equal(plain.subscription_started_at, null);
    assert.equal(plain.id, 5);
    assert.equal(plain.name, 'Gül Sitesi');
    const far = mapSiteRow({ ...base, subscription_started_at: '2090-01-01', free_until: '2090-03-01' });
    assert.equal(far.free_period_state, 'active');
    assert.equal(far.free_until, '2090-03-01');
    const old = mapSiteRow({ ...base, subscription_started_at: '2021-01-01', free_until: '2021-03-01' });
    assert.equal(old.free_period_state, 'ended');
  });
});
