// K17 (karar): "Borç mutlaka tahsil edilir; kiracı vermezse malik öder." Kiracı borcunun malike devri yalnız ÇIKIŞTA değil GECİKMEDE de yönetici önüne açıkça önerilir:
//  - listTransferCandidates: devredilebilir (vadesi gelmiş, ödenmemiş, tazminat olmayan) kalemi olan daireler; reason overdue (kiracı oturuyor) | exited (kiracı yok); can_transfer = malik kaydı var.
//  - tenantDebtOverdueAttention: yalnız overdue + malikli daireler sayılır (yönetici dikkat satırı `tenant_debt_overdue_transfer`).
// DB'siz, KATI sahte veritabanı (bilinmeyen SQL -> hata). Gerçek PostgreSQL: scripts/qa_finance_devir_iade.mjs (K17a-K17f).
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { CANDIDATE_LIMIT, listTransferCandidates, tenantDebtOverdueAttention } from '../src/modules/finance_liability_service.js';
import { attentionSourceKeys } from '../src/modules/attention_registry.js';

const norm = (text) => String(text).replace(/\s+/g, ' ').trim();
const ok = (rows = []) => ({ rows, rowCount: rows.length });
const NOW = new Date('2026-10-29T09:00:00Z'); // İstanbul 2026-10-29
const SITE = 1000000001;

const candidate = (id, extra = {}) => ({ apartment_id: String(id), unit_label: `Daire ${id}`, block_name: 'A Blok', tenant_present: true, has_owner: true, ...extra });
const charge = (id, amount, due, extra = {}) => ({
  apartment_id: extra.apartment_id ?? '1', id: String(id), kind: 'charge', amount_minor: String(amount), entry_date: due, due_date: due,
  reverses_entry_id: null, late_fee_run_id: null, source_kind: null, definition_name: 'Aidat', definition_id: null, fund: 'operating', def_charge_party: null, def_kind: null, ...extra,
});
const payment = (id, amount, date, extra = {}) => ({
  apartment_id: extra.apartment_id ?? '1', id: String(id), kind: 'payment', amount_minor: String(-amount), entry_date: date, due_date: null,
  reverses_entry_id: null, late_fee_run_id: null, source_kind: null, definition_name: null, definition_id: null, fund: null, def_charge_party: null, def_kind: null, ...extra,
});

// Aday sorgusu (M1 önsüzgeçli): `candidates` SQL'in ZATEN süzdüğü daireler (gerçek süzgeç gerçek PostgreSQL'de sınanır: scripts/qa_finance_devir_iade.mjs K17i-K17k);
// sahte veritabanı LIMIT $3'ü uygular (servis limit + 1 satır ister).
const CANDIDATE_QUERY =
  /^WITH items AS .* FROM rem WHERE rem\.account_party = 'tenant' AND rem\.due <= \$2::DATE AND NOT rem\.is_lf AND rem\.r > 0 GROUP BY rem\.apartment_id \) t INNER JOIN apartments a ON a\.id = t\.apartment_id AND a\.site_code = \$1 INNER JOIN site_blocks b ON b\.id = a\.block_id ORDER BY t\.remaining DESC, b\.sort_order, a\.sort_order, a\.id LIMIT \$3$/;

function fakeDb({ candidates, ledger, limit = CANDIDATE_LIMIT }) {
  const calls = [];
  return {
    calls,
    async query(text, params = []) {
      const sql = norm(text);
      calls.push({ sql, params });
      if (CANDIDATE_QUERY.test(sql)) {
        assert.deepEqual(params, [SITE, '2026-10-29', limit + 1]);
        return ok(candidates.slice(0, params[2]));
      }
      if (/WHERE l\.site_code = \$1 AND l\.apartment_id = ANY\(\$2::BIGINT\[\]\)/.test(sql)) {
        assert.equal(params[0], SITE);
        const ids = new Set(params[1].map(String));
        return ok(ledger.filter((row) => ids.has(String(row.apartment_id))));
      }
      throw new Error(`BEKLENMEYEN SQL: ${sql.slice(0, 160)}`);
    },
  };
}

describe('K17 aday listesi: gecikmede de malike devir önerilir', () => {
  it('kiracı OTURAN dairede vadesi geçmiş borç = overdue; kısmi ödeme M1 ile en eski kalemden düşer; tutar ve en eski vade doğru', async () => {
    const db = fakeDb({
      candidates: [candidate(1)],
      ledger: [charge(1, 100000, '2026-07-01'), charge(2, 100000, '2026-08-01'), charge(3, 100000, '2026-09-01'), payment(4, 150000, '2026-09-15')],
    });
    const result = await listTransferCandidates(SITE, NOW, db);
    assert.equal(result.count, 1);
    assert.equal(result.truncated, false);
    const [item] = result.items;
    assert.equal(item.reason, 'overdue');
    assert.equal(item.tenant_present, true);
    assert.equal(item.can_transfer, true);
    assert.equal(item.item_count, 2); // 1. kalem tamamen ödendi; 2. kalemde 50.000, 3. kalemde 100.000 kaldı
    assert.equal(item.total_minor, 150000);
    assert.equal(item.oldest_due_date, '2026-08-01');
    assert.equal(item.unit_label, 'Daire 1');
    assert.equal(result.total_minor, 150000);
    assert.equal(db.calls.length, 2, 'aday sorgusu + TEK toplu defter sorgusu (daire başına sorgu yok)');
  });

  it('kiracısı AYRILMIŞ daire = exited; vadesi GELECEK ve yalnız gecikme tazminatı olan daire aday değildir', async () => {
    const db = fakeDb({
      candidates: [candidate(1, { tenant_present: false }), candidate(2), candidate(3)],
      ledger: [
        charge(1, 50000, '2026-09-10', { apartment_id: '1' }),
        charge(2, 70000, '2026-12-01', { apartment_id: '2', entry_date: '2026-10-01' }), // vadesi gelecek
        charge(3, 4000, '2026-09-01', { apartment_id: '3', late_fee_run_id: '9', definition_name: 'Gecikme tazminatı' }), // tazminat devredilmez
      ],
    });
    const result = await listTransferCandidates(SITE, NOW, db);
    assert.deepEqual(result.items.map((i) => [i.apartment_id, i.reason, i.total_minor]), [[1, 'exited', 50000]]);
  });

  it('malik kaydı olmayan daire listelenir ama devredilemez (can_transfer=false); en büyük tutar önce', async () => {
    const db = fakeDb({
      candidates: [candidate(1, { has_owner: false }), candidate(2)],
      ledger: [charge(1, 90000, '2026-09-01', { apartment_id: '1' }), charge(2, 30000, '2026-09-01', { apartment_id: '2' })],
    });
    const result = await listTransferCandidates(SITE, NOW, db);
    assert.deepEqual(result.items.map((i) => [i.apartment_id, i.has_owner, i.can_transfer]), [[1, false, false], [2, true, true]]);
  });

  it('aday yok: tek sorgu, boş liste (defter sorgusu çalışmaz)', async () => {
    const db = fakeDb({ candidates: [], ledger: [] });
    const result = await listTransferCandidates(SITE, NOW, db);
    assert.deepEqual(result, { items: [], count: 0, total_minor: 0, truncated: false });
    assert.equal(db.calls.length, 1);
  });

  it(`üst sınır: ${CANDIDATE_LIMIT}'den fazla daire geldiyse yalnız ilk ${CANDIDATE_LIMIT} değerlendirilir ve truncated=true`, async () => {
    const candidates = Array.from({ length: CANDIDATE_LIMIT + 1 }, (_v, index) => candidate(index + 1));
    const db = fakeDb({ candidates, ledger: [] });
    const result = await listTransferCandidates(SITE, NOW, db);
    assert.equal(result.truncated, true);
    assert.equal(db.calls[1].params[1].length, CANDIDATE_LIMIT);
  });

  it('kesim SÜZGEÇTEN SONRA: SQL aday olabilecek daireleri seçer (kiracı hesabında M1 kalanı > 0, vadesi bugün ve öncesi, tazminat değil); "bakiyesi pozitif" kesimi yok', async () => {
    const db = fakeDb({ candidates: [candidate(1)], ledger: [charge(1, 50000, '2026-09-01')] });
    await listTransferCandidates(SITE, NOW, db);
    const sql = db.calls[0].sql;
    assert.ok(!/HAVING SUM\(l\.amount_minor\) > 0/.test(sql), 'eski kesim (aylık tahakkuktan sonra hemen her daire pozitif bakiyeli) geri gelmesin');
    assert.match(sql, /WITH items AS/, 'M1 CTE zinciri (finance_m1.m1Ctes: planLiabilityTransfer ile AYNI mahsup kuralı)');
    assert.equal(sql.split(`END) = 'tenant' AND NOT EXISTS (SELECT 1 FROM ledger_entries rv`).length - 1, 2, 'M1 yalnız kiracı hesabı satırlarında çalışır: borç ve ödeme CTE\'lerinin ikisinde de (ev sahibi hesabı taranmaz)');
    assert.ok(sql.indexOf('rem.r > 0') < sql.indexOf('LIMIT $3'), 'süzgeç LIMIT\'ten ÖNCE');
  });

  it('limit parametresi: LIMIT limit + 1 istenir; limit + 1 satır gelirse truncated=true ve yalnız ilk limit daire değerlendirilir', async () => {
    const candidates = [candidate(1), candidate(2), candidate(3)];
    const ledger = [1, 2, 3].map((id) => charge(id, id * 10000, '2026-09-01', { apartment_id: String(id) }));
    const db = fakeDb({ candidates, ledger, limit: 2 });
    const result = await listTransferCandidates(SITE, NOW, db, { limit: 2 });
    assert.equal(result.truncated, true);
    assert.deepEqual(db.calls[1].params[1], [1, 2]);
    assert.deepEqual(result.items.map((i) => i.apartment_id), [2, 1], 'değerlendirilen daireler büyük tutar önce sıralanır');
    // sınırın altında kalınca kesilmez
    const db2 = fakeDb({ candidates: [candidate(1), candidate(2)], ledger, limit: 2 });
    assert.equal((await listTransferCandidates(SITE, NOW, db2, { limit: 2 })).truncated, false);
    // geçersiz limit varsayılana döner (sorguya CANDIDATE_LIMIT + 1 gider)
    const db3 = fakeDb({ candidates: [], ledger: [] });
    await listTransferCandidates(SITE, NOW, db3, { limit: 0 });
    assert.equal(db3.calls[0].params[2], CANDIDATE_LIMIT + 1);
  });
});

describe('K17 yönetici dikkat satırı: tenant_debt_overdue_transfer', () => {
  it('kaynak finans modülüne kayıtlı (kiracı çıkışı kaynağı tenant_debt_pending_transfer ayrı kalır)', () => {
    const keys = attentionSourceKeys();
    assert.ok(keys.includes('tenant_debt_overdue_transfer'));
    assert.ok(keys.includes('tenant_debt_pending_transfer'));
  });

  it('yalnız kiracısı OTURAN ve malik kaydı olan daireler sayılır; ayrılmış kiracı ve malikisiz daire sayılmaz', async () => {
    const db = fakeDb({
      candidates: [candidate(1), candidate(2, { tenant_present: false }), candidate(3, { has_owner: false }), candidate(4)],
      ledger: [
        charge(1, 40000, '2026-09-01', { apartment_id: '1' }),
        charge(2, 99000, '2026-09-01', { apartment_id: '2' }),
        charge(3, 77000, '2026-09-01', { apartment_id: '3' }),
        charge(4, 60000, '2026-10-01', { apartment_id: '4' }),
      ],
    });
    assert.deepEqual(await tenantDebtOverdueAttention(db, SITE, NOW), { count: 2, total_minor: 100000 });
  });

  it('öneri yoksa count 0 (satır gösterilmez)', async () => {
    const db = fakeDb({ candidates: [], ledger: [] });
    assert.deepEqual(await tenantDebtOverdueAttention(db, SITE, NOW), { count: 0, total_minor: 0 });
  });

  it(`aday listesi kesildiyse (${CANDIDATE_LIMIT}'den fazla aday) sayı ve toplam "en az" değeridir: at_least=true; kesilmediyse alan hiç yok`, async () => {
    const many = Array.from({ length: CANDIDATE_LIMIT + 1 }, (_v, index) => candidate(index + 1));
    const manyLedger = many.slice(0, CANDIDATE_LIMIT).map((c) => charge(Number(c.apartment_id), 1000, '2026-09-01', { apartment_id: c.apartment_id }));
    assert.deepEqual(await tenantDebtOverdueAttention(fakeDb({ candidates: many, ledger: manyLedger }), SITE, NOW), { count: CANDIDATE_LIMIT, total_minor: CANDIDATE_LIMIT * 1000, at_least: true });
    const few = await tenantDebtOverdueAttention(fakeDb({ candidates: [candidate(1)], ledger: [charge(1, 1000, '2026-09-01')] }), SITE, NOW);
    assert.deepEqual(few, { count: 1, total_minor: 1000 });
    assert.ok(!('at_least' in few));
  });
});
