// Daire sayısı azaltılırken DOLU daire koruması (site_service.syncSiteStructureCounts) - DB'siz, betiklenmiş bağlantıyla.
// Sözleşme: silinecek dairelerden biri dolu (aktif sakin / üyelik / askı kaydı / açık güvenlik talebi) ise HİÇBİR şey silinmez, işlem GERİ ALINIR ve
// 409 APARTMENT_OCCUPIED (hangi daireler ve neden) döner; boş dairelerin silinmesi (anlık görüntü + denetim yolu) AYNEN sürer.
import { describe, it, beforeEach, afterEach, mock } from 'node:test';
import assert from 'node:assert/strict';
import { pool } from '../src/db.js';
import { PlatformError } from '../src/modules/errors.js';
import { syncSiteStructureCounts } from '../src/services/site_service.js';
import { handleSiteMutationError } from '../src/utils/validators.js';

const SITE = 1000000556;
const norm = (text) => String(text).replace(/\s+/g, ' ').trim();
const ok = (rows = [], rowCount = rows.length) => ({ rows, rowCount });

let log;
let originalConnect;

/** 1 blok, `apartments` daire (id 101..); occupied: { id: { flag: true } } doluluk bayrakları. */
function scriptedPool({ apartments = 4, occupied = {} } = {}) {
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
        if (/^SELECT a\.id, a\.unit_label, b\.block_name, \(a\.resident_user_code IS NOT NULL\) AS has_legacy_resident/.test(sql)) {
          return ok(
            params[0].map((id) => ({
              id: String(id),
              unit_label: `Daire ${Number(id) - 100}`,
              block_name: 'A Blok',
              has_legacy_resident: false,
              has_residency: false,
              has_membership: false,
              has_suspension: false,
              has_safety_request: false,
              ...(occupied[id] ?? {}),
            })),
          );
        }
        if (/^SELECT 1 FROM ledger_entries/.test(sql)) return ok();
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

describe('syncSiteStructureCounts x dolu daire koruması', () => {
  for (const [flag, label] of [
    ['has_residency', 'güncel sakin kaydı'],
    ['has_membership', 'aktif üyelik'],
    ['has_legacy_resident', 'aktif sakin'],
    ['has_suspension', 'kapı erişimi askı kaydı'],
    ['has_safety_request', 'açık güvenlik talebi'],
  ]) {
    it(`silinecek daire dolu (${label}): 409 APARTMENT_OCCUPIED, daire adı + neden mesajda; DELETE ve COMMIT yok, ROLLBACK var`, async () => {
      const scripted = scriptedPool({ apartments: 4, occupied: { 104: { [flag]: true } } });
      await assert.rejects(run(3, scripted), (error) => {
        assert.ok(error instanceof PlatformError);
        assert.equal(error.statusCode, 409);
        assert.equal(error.code, 'APARTMENT_OCCUPIED');
        assert.match(error.message, /A Blok Daire 4/);
        assert.ok(error.message.includes(label), error.message);
        assert.deepEqual(error.extra.apartments, [{ id: 104, label: 'A Blok Daire 4', reasons: [label] }]);
        return true;
      });
      assert.deepEqual(scripted.deleted, []);
      assert.ok(sqls().includes('ROLLBACK'));
      assert.equal(sqls().includes('COMMIT'), false);
      assert.equal(sqls().some((s) => s.startsWith('DELETE FROM apartments') || s.startsWith('UPDATE sites SET')), false, 'hiçbir şey silinmez / güncellenmez');
    });
  }

  it('denetim silmeden ÖNCE ve yalnız silinecek adaylar için (id listesi); adaylar FOR UPDATE ile kilitlenir; tüm dolu daireler birlikte raporlanır', async () => {
    const scripted = scriptedPool({ apartments: 5, occupied: { 104: { has_membership: true }, 105: { has_residency: true, has_suspension: true } } });
    await assert.rejects(run(3, scripted), (error) => error.code === 'APARTMENT_OCCUPIED' && error.extra.apartments.length === 2 && /Daire 5 \(güncel sakin kaydı, kapı erişimi askı kaydı\)/.test(error.message));
    const check = log.find((e) => /has_legacy_resident/.test(e.sql));
    assert.deepEqual([...check.params[0]].sort(), [104, 105]);
    assert.match(check.sql, /FOR UPDATE OF a$/);
    // Kilit sırası (gerçek PG QA H3): finans yazmaları finans kilidini sonra daire satırlarını alır; denetim (FOR UPDATE) finans kilidinden SONRA gelmeli.
    const financeLockAt = log.findIndex((e) => /^SELECT pg_advisory_xact_lock/.test(e.sql) && e.params[0] === `finance_post:${SITE}`);
    assert.ok(financeLockAt >= 0, 'silinecek aday varken finans kilidi (denetimden önce) alınır');
    assert.ok(financeLockAt < log.indexOf(check), 'finans kilidi daire satırlarını FOR UPDATE ile kilitleyen denetimden ÖNCE');
    assert.equal(log.some((e) => /^DELETE FROM apartments/.test(e.sql)), false, 'dolu daire varken silme yok');
  });

  it('kilit sırası people_sync -> finance_post -> apartments (FOR UPDATE): finans kilidi, daire satırı kilidinden önce; boş daire silinirken de aynı sıra, finans kilidi TEK kez', async () => {
    const scripted = scriptedPool({ apartments: 4 });
    await run(3, scripted);
    const lockKeys = log.filter((e) => /^SELECT pg_advisory_xact_lock/.test(e.sql)).map((e) => e.params[0]);
    assert.equal(lockKeys[0], `people_sync:${SITE}`, 'önce kişi eşitleme kilidi');
    assert.equal(lockKeys.filter((key) => key === `finance_post:${SITE}`).length, 1, 'finans kilidi tek kez');
    const financeLockAt = log.findIndex((e) => /^SELECT pg_advisory_xact_lock/.test(e.sql) && e.params[0] === `finance_post:${SITE}`);
    const occupancyAt = log.findIndex((e) => /has_legacy_resident/.test(e.sql));
    assert.ok(financeLockAt > 0 && occupancyAt > financeLockAt, 'finans kilidi doluluk denetiminden (daire FOR UPDATE) önce');
    assert.ok(log.findIndex((e) => /^DELETE FROM apartments/.test(e.sql)) > occupancyAt);
  });

  it('dolu daire silinmeyecekse (üstteki boş daireler azaltılır) davranış AYNEN sürer: boş daire silinir, COMMIT edilir', async () => {
    const scripted = scriptedPool({ apartments: 4, occupied: { 101: { has_residency: true }, 102: { has_membership: true } } });
    await run(3, scripted);
    assert.deepEqual(scripted.deleted, ['104']);
    assert.ok(sqls().includes('COMMIT'));
    assert.equal(sqls().includes('ROLLBACK'), false);
  });

  it('daire azaltılmıyorsa (artırma / aynı sayı) doluluk denetimi sorgusu HİÇ çalışmaz', async () => {
    const scripted = scriptedPool({ apartments: 4, occupied: { 104: { has_residency: true } } });
    await run(4, scripted);
    assert.equal(log.some((e) => /has_legacy_resident/.test(e.sql)), false);
    assert.equal(log.some((e) => /^SELECT pg_advisory_xact_lock/.test(e.sql) && e.params[0] === `finance_post:${SITE}`), false, 'silinecek aday yoksa finans kilidine gelinmez');
    assert.ok(sqls().includes('COMMIT'));
  });

  it('handleSiteMutationError APARTMENT_OCCUPIED kodunu 409 gövdesinde taşır', () => {
    const res = { statusCode: 0, body: null, status(code) { this.statusCode = code; return this; }, json(body) { this.body = body; return this; } };
    handleSiteMutationError(new PlatformError(409, 'APARTMENT_OCCUPIED', 'Dolu daireler silinemez: A Blok Daire 4 (aktif üyelik).'), res, 'Genel hata');
    assert.equal(res.statusCode, 409);
    assert.equal(res.body.code, 'APARTMENT_OCCUPIED');
    assert.match(res.body.error, /A Blok Daire 4/);
  });
});
