// Aidat ve Finans (Faz 4a): daire azaltma (site_service.syncSiteStructureCounts) x mali kayıt - DB'siz, betiklenmiş bağlantıyla.
// Sözleşme: silinecek dairelerden birinin defter satırı varsa işlem GERİ ALINIR ve 409 APARTMENT_HAS_FINANCE döner; mali kaydı olmayan
// dairelerde davranış AYNEN kalır. handleSiteMutationError PlatformError kodunu taşır, eski hataların gövdesi değişmez.
import { describe, it, beforeEach, afterEach, mock } from 'node:test';
import assert from 'node:assert/strict';
import { pool } from '../src/db.js';
import { PlatformError } from '../src/modules/errors.js';
import { syncSiteStructureCounts } from '../src/services/site_service.js';
import { handleSiteMutationError } from '../src/utils/validators.js';

const SITE = 1000000555;
const norm = (text) => String(text).replace(/\s+/g, ' ').trim();
const ok = (rows = [], rowCount = rows.length) => ({ rows, rowCount });

let log;
let originalConnect;

/**
 * 1 blok, `apartments` daire (sort_order 1..n); finance: finans kaydı olan apartment id'leri.
 * Silme sırası: sort_order azalan (son daire önce).
 */
function scriptedPool({ apartments = 4, financeIds = [] } = {}) {
  const rows = Array.from({ length: apartments }, (_, i) => ({ id: String(100 + i + 1), site_code: String(SITE), block_id: '7', unit_label: `Daire ${i + 1}`, sort_order: i + 1, resident_user_code: null }));
  const deleted = [];
  return {
    deleted,
    client: {
      async query(text, params = []) {
        const sql = norm(text);
        log.push({ sql, params });
        if (/^(BEGIN|COMMIT|ROLLBACK)$/.test(sql)) return ok();
        if (/^SELECT pg_advisory_xact_lock/.test(sql)) return ok();
        if (/^SELECT id, site_code, block_name, sort_order, created_at FROM site_blocks/.test(sql)) return ok([{ id: '7', site_code: String(SITE), block_name: 'A Blok', sort_order: 1 }]);
        if (/FROM site_doors d/.test(sql)) return ok();
        if (/^UPDATE site_blocks SET block_name/.test(sql)) return ok([], 1);
        if (/FROM apartments a WHERE a\.block_id = \$1/.test(sql)) return ok(rows.filter((r) => !deleted.includes(r.id)));
        if (/^SELECT 1 FROM ledger_entries WHERE site_code = \$1 AND apartment_id = \$2 LIMIT 1$/.test(sql)) {
          return ok(financeIds.includes(Number(params[1])) ? [{ '?column?': 1 }] : []);
        }
        if (/^SAVEPOINT |^RELEASE SAVEPOINT |^ROLLBACK TO SAVEPOINT /.test(sql)) return ok();
        if (/^SELECT a\.id, a\.unit_label, a\.floor/.test(sql)) return ok();
        if (/^DELETE FROM apartments WHERE id = \$1$/.test(sql)) {
          deleted.push(String(params[0]));
          return ok([], 1);
        }
        if (/^UPDATE sites SET block_count/.test(sql)) return ok([], 1);
        throw new Error(`BEKLENMEYEN SQL: ${sql.slice(0, 160)}`);
      },
      release() {},
    },
  };
}

beforeEach(() => {
  log = [];
  originalConnect = pool.connect;
  mock.method(console, 'error', () => {});
});
afterEach(() => {
  pool.connect = originalConnect;
  mock.restoreAll();
});

const run = (count, scripted) => {
  pool.connect = async () => scripted.client;
  return syncSiteStructureCounts({ siteCode: SITE, blockCount: 1, apartmentCount: count, blockApartmentCounts: [count], doorCount: 0 });
};
const sqls = () => log.map((e) => e.sql);

describe('syncSiteStructureCounts x mali kayıt', () => {
  it('silinecek dairenin defter satırı varsa 409 APARTMENT_HAS_FINANCE; işlem GERİ ALINIR (ROLLBACK, DELETE yok, COMMIT yok)', async () => {
    const scripted = scriptedPool({ apartments: 4, financeIds: [104] });
    await assert.rejects(run(3, scripted), (error) => {
      assert.ok(error instanceof PlatformError);
      assert.equal(error.statusCode, 409);
      assert.equal(error.code, 'APARTMENT_HAS_FINANCE');
      assert.equal(error.message, 'Mali kaydı olan daire silinemez.');
      return true;
    });
    assert.deepEqual(scripted.deleted, []);
    assert.ok(sqls().includes('ROLLBACK'));
    assert.equal(sqls().includes('COMMIT'), false);
    assert.equal(sqls().some((s) => s.startsWith('DELETE FROM apartments')), false);
    assert.equal(sqls().some((s) => s.startsWith('UPDATE sites SET')), false, 'site sayıları güncellenmez');
  });

  it('kilit sırası: people_sync -> finance_post advisory kilidi -> mali kayıt denetimi -> DELETE', async () => {
    const scripted = scriptedPool({ apartments: 4, financeIds: [] });
    await run(3, scripted);
    const locks = log.filter((e) => /^SELECT pg_advisory_xact_lock/.test(e.sql)).map((e) => e.params[0]);
    assert.deepEqual(locks, [`people_sync:${SITE}`, `finance_post:${SITE}`]);
    const order = sqls();
    const financeLock = order.findIndex((s, i) => /^SELECT pg_advisory_xact_lock/.test(s) && log[i].params[0] === `finance_post:${SITE}`);
    const check = order.findIndex((s) => s.startsWith('SELECT 1 FROM ledger_entries'));
    const del = order.findIndex((s) => s.startsWith('DELETE FROM apartments'));
    assert.ok(financeLock > 0 && financeLock < check && check < del);
  });

  it('mali kaydı OLMAYAN dairelerin azaltılması AYNEN çalışır: son daire silinir, COMMIT edilir, site sayıları güncellenir', async () => {
    const scripted = scriptedPool({ apartments: 4, financeIds: [101, 102, 103] });
    await run(3, scripted);
    assert.deepEqual(scripted.deleted, ['104']);
    assert.ok(sqls().includes('COMMIT'));
    assert.equal(sqls().includes('ROLLBACK'), false);
    assert.ok(sqls().some((s) => s.startsWith('UPDATE sites SET block_count')));
  });

  it('finans kilidi ilk silmede YALNIZ bir kez alınır (iki daire silinirken de); her silinecek daire için ayrı denetim', async () => {
    const scripted = scriptedPool({ apartments: 4, financeIds: [] });
    await run(2, scripted);
    assert.deepEqual(scripted.deleted, ['104', '103']);
    assert.equal(log.filter((e) => /^SELECT pg_advisory_xact_lock/.test(e.sql) && e.params[0] === `finance_post:${SITE}`).length, 1);
    assert.equal(sqls().filter((s) => s.startsWith('SELECT 1 FROM ledger_entries')).length, 2);
  });

  it('ikinci silinecek dairede mali kayıt çıkarsa birincinin silinmesi de geri alınır (ROLLBACK; sahte DB silmeyi sayar ama COMMIT yoktur)', async () => {
    const scripted = scriptedPool({ apartments: 4, financeIds: [103] });
    await assert.rejects(run(2, scripted), (error) => error.code === 'APARTMENT_HAS_FINANCE');
    assert.ok(sqls().includes('ROLLBACK'));
    assert.equal(sqls().includes('COMMIT'), false);
  });

  it('daire azaltılmıyorsa (artırma / aynı sayı) finans kilidi ve denetimi HİÇ çalışmaz', async () => {
    const scripted = scriptedPool({ apartments: 4, financeIds: [101, 102, 103, 104] });
    await run(4, scripted);
    assert.equal(log.some((e) => /ledger_entries/.test(e.sql)), false);
    assert.equal(log.some((e) => /^SELECT pg_advisory_xact_lock/.test(e.sql) && e.params[0] === `finance_post:${SITE}`), false);
    assert.ok(sqls().includes('COMMIT'));
  });
});

describe('handleSiteMutationError: PlatformError kodu', () => {
  const respond = (error) => {
    const res = {
      statusCode: 0,
      body: null,
      status(code) {
        this.statusCode = code;
        return this;
      },
      json(body) {
        this.body = body;
        return this;
      },
    };
    handleSiteMutationError(error, res, 'Genel hata');
    return res;
  };

  it('APARTMENT_HAS_FINANCE: 409 { error, code }', () => {
    const res = respond(new PlatformError(409, 'APARTMENT_HAS_FINANCE', 'Mali kaydı olan daire silinemez.'));
    assert.equal(res.statusCode, 409);
    assert.deepEqual(res.body, { error: 'Mali kaydı olan daire silinemez.', code: 'APARTMENT_HAS_FINANCE' });
  });

  it('eski hataların gövdesi DEĞİŞMEZ: düz Error 400 { error }, kodlu sistem hatası maskelenir', () => {
    const plain = respond(new Error('Site adi en az 2 karakter olmali.'));
    assert.equal(plain.statusCode, 400);
    assert.deepEqual(plain.body, { error: 'Site adi en az 2 karakter olmali.' });
    const coded = respond(Object.assign(new Error('x'), { statusCode: 404 }));
    assert.deepEqual(coded.body, { error: 'x' });
    const database = respond(Object.assign(new Error('relation does not exist'), { code: '42P01' }));
    assert.equal(database.statusCode, 500);
    assert.equal(JSON.stringify(database.body).includes('42P01'), false);
  });
});
