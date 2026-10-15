// Kisi kayitlari esitleme (H7): okuma uclari kilidi BEKLEMEZ (try-lock), kisa sureli bellek ici kisitlama, hata okumayi engellemez (DB'siz).
import { describe, it, beforeEach, afterEach, mock } from 'node:test';
import assert from 'node:assert/strict';
import { pool } from '../src/db.js';
import { SYNC_STEPS } from '../src/modules/people_sync_sql.js';
import { resetPeopleSyncThrottle, syncSitePeople, syncSitePeopleSafe, syncUserPeople, syncUserPeopleSafe } from '../src/modules/people_sync.js';

const SITE = 1000000001;
const norm = (text) => String(text).replace(/\s+/g, ' ').trim();

let log;
let lockResult;
let connectCalls;
let failSteps;

beforeEach(() => {
  log = [];
  lockResult = true;
  connectCalls = 0;
  failSteps = false;
  delete process.env.PEOPLE_SYNC_MIN_INTERVAL_MS;
  resetPeopleSyncThrottle();
  pool.connect = async () => {
    connectCalls += 1;
    return {
      async query(text, params) {
        const sql = norm(text);
        log.push({ sql, params });
        if (/^SELECT pg_try_advisory_xact_lock/.test(sql)) return { rows: [{ locked: lockResult }], rowCount: 1 };
        if (failSteps && /^WITH /.test(sql)) throw Object.assign(new Error('SECRET'), { code: 'XX000' });
        return { rows: [], rowCount: 0 };
      },
      release() {},
    };
  };
  mock.method(console, 'error', () => {});
});

afterEach(() => {
  delete pool.connect;
  delete process.env.PEOPLE_SYNC_MIN_INTERVAL_MS;
  resetPeopleSyncThrottle();
  mock.restoreAll();
});

describe('syncSitePeople (acik cagri) kilidi BEKLER', () => {
  it('pg_advisory_xact_lock (bloklayan) kullanir ve tum adimlari calistirir', async () => {
    await syncSitePeople(SITE);
    assert.match(log[1].sql, /^SELECT pg_advisory_xact_lock/);
    assert.equal(log[1].params[0], `people_sync:${SITE}`);
    assert.equal(log.length, 2 + SYNC_STEPS.length + 1);
  });

  it('gecersiz site kodu -> null (sorgu yok)', async () => {
    assert.equal(await syncSitePeople('abc'), null);
    assert.equal(log.length, 0);
  });
});

describe('H7: okuma uclari icin syncSitePeopleSafe', () => {
  it('try-lock kullanir: kilit meshgulse esitleme ATLANIR (adim yok, ROLLBACK, baglanti birakilir), hata firlatilmaz', async () => {
    lockResult = false;
    const result = await syncSitePeopleSafe(SITE);
    assert.deepEqual(result, { skipped: true, reason: 'busy' });
    assert.match(log[1].sql, /^SELECT pg_try_advisory_xact_lock/);
    assert.equal(log.some((q) => /^SELECT pg_advisory_xact_lock/.test(q.sql)), false, 'bloklayan kilit YOK');
    assert.equal(log.some((q) => /^WITH /.test(q.sql)), false, 'adim calismadi');
    assert.equal(log[log.length - 1].sql, 'ROLLBACK');
    assert.equal(log.some((q) => q.sql === 'COMMIT'), false);
  });

  it('kilit alinirsa tum adimlar calisir ve COMMIT edilir', async () => {
    await syncSitePeopleSafe(SITE);
    assert.equal(log.filter((q) => /^WITH /.test(q.sql)).length, SYNC_STEPS.filter((s) => /^\s*WITH /.test(s.sql)).length);
    assert.equal(log[log.length - 1].sql, 'COMMIT');
  });

  it('ayni site icin kisa sure icinde ikinci cagri ATLANIR (bellek ici kisitlama); kilit meshgul atlamasi kisitlamayi baslatmaz', async () => {
    await syncSitePeopleSafe(SITE);
    const first = log.length;
    assert.ok(first > 0);
    const second = await syncSitePeopleSafe(SITE);
    assert.deepEqual(second, { skipped: true, reason: 'throttled' });
    assert.equal(log.length, first, 'ikinci cagri hic sorgu calistirmadi');
    assert.equal(connectCalls, 1, 'havuz baglantisi bile alinmadi');

    resetPeopleSyncThrottle();
    log.length = 0;
    lockResult = false;
    await syncSitePeopleSafe(SITE);
    lockResult = true;
    log.length = 0;
    await syncSitePeopleSafe(SITE);
    assert.ok(log.some((q) => /^WITH /.test(q.sql)), 'meshgul atlamasindan sonra bir sonraki cagri esitler');
  });

  it('kisitlama site basinadir: baska site etkilenmez; kullanici esitlemesi ayri anahtar', async () => {
    await syncSitePeopleSafe(SITE);
    log.length = 0;
    await syncSitePeopleSafe(SITE + 1);
    assert.ok(log.length > 0);
    log.length = 0;
    await syncUserPeopleSafe(20004);
    assert.ok(log.length > 0);
    assert.equal(log[1].params[0], 'people_sync_user:20004');
    assert.match(log[1].sql, /^SELECT pg_try_advisory_xact_lock/);
  });

  it('PEOPLE_SYNC_MIN_INTERVAL_MS=0 kisitlamayi kapatir (testler/QA); sifirlama yardimcisi kisitlamayi temizler', async () => {
    process.env.PEOPLE_SYNC_MIN_INTERVAL_MS = '0';
    await syncSitePeopleSafe(SITE);
    log.length = 0;
    await syncSitePeopleSafe(SITE);
    assert.ok(log.length > 0, 'kisitlama kapali: tekrar esitler');
    delete process.env.PEOPLE_SYNC_MIN_INTERVAL_MS;
    await syncSitePeopleSafe(SITE);
    log.length = 0;
    resetPeopleSyncThrottle();
    await syncSitePeopleSafe(SITE);
    assert.ok(log.length > 0);
  });

  it('esitleme hatasi okumayi ENGELLEMEZ (null, loglanir, ROLLBACK) ve tekrar denemeler DB\'yi yormaz (kisitlama)', async () => {
    failSteps = true;
    const result = await syncSitePeopleSafe(SITE);
    assert.equal(result, null);
    assert.ok(log.some((q) => q.sql === 'ROLLBACK'));
    assert.ok(console.error.mock.calls.some((c) => String(c.arguments[0]).includes('[people] syncSitePeople')));
    log.length = 0;
    assert.deepEqual(await syncSitePeopleSafe(SITE), { skipped: true, reason: 'throttled' });
    assert.equal(log.length, 0);
  });

  it('havuz baglantisi alinamazsa da okuma engellenmez', async () => {
    pool.connect = async () => {
      throw new Error('baglanti havuzu dolu');
    };
    assert.equal(await syncSitePeopleSafe(SITE), null);
    assert.equal(await syncUserPeople('abc'), null);
  });
});
