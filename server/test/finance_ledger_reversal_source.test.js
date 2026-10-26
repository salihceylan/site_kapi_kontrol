// Ters kayıt (finance_ledger_service.insertReversal) asılın kaynak izini (source_kind / source_id) KOPYALAR (DB'siz, sahte istemci).
// Neden: tek tek iptal edilen devir (opening) kaydının ters kaydı kaynaksız kalırsa raporlar (finance_reports / finance_home "borçlandırılan"
// süzgeci source_kind <> 'opening') asılı dışarıda, ters kaydı içeride sayar ve tahakkuku düşürür. Toplu devir geri alması (finance_opening) zaten aynı izi yazar.
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

process.env.JWT_SECRET ||= 'test-secret-test-secret-test-secret-123456';

const { insertReversal } = await import('../src/modules/finance_ledger_service.js');

const norm = (text) => String(text).replace(/\s+/g, ' ').trim();

function fakeClient() {
  const calls = [];
  return {
    calls,
    async query(text, params = []) {
      calls.push({ sql: norm(text), params });
      return { rows: [{ id: '4001' }], rowCount: 1 };
    },
  };
}

const original = (extra = {}) => ({
  id: '300',
  apartment_id: '11',
  kind: 'charge',
  amount_minor: '250000',
  due_date: '2026-10-05',
  definition_id: null,
  definition_name: 'Devir bakiyesi',
  run_id: null,
  payer_party: 'both',
  late_fee_run_id: null,
  account_party: 'owner',
  source_kind: null,
  source_id: null,
  ...extra,
});
const request = (orig) => ({ siteCode: 1000000001, original: orig, openPeriod: '2026-10-01', todayIsoDate: '2026-10-21', reason: 'Yanlış devir', key: 'rev-1', actorUserCode: 20001 });

describe('insertReversal: kaynak izi kopyalanır', () => {
  it('devir (opening) kaydının ters kaydı source_kind=opening ve aynı source_id ile yazılır', async () => {
    const client = fakeClient();
    const id = await insertReversal(client, request(original({ source_kind: 'opening', source_id: '12' })));
    assert.equal(id, 4001);
    const { sql, params } = client.calls[0];
    assert.match(sql, /account_party, source_kind, source_id \) VALUES/);
    assert.deepEqual(params.slice(-3), ['owner', 'opening', '12'], 'hesap, kaynak türü, kaynak kimliği');
    assert.equal(params[2], '-250000', 'karşı işaretli tutar');
    // yer tutucu sayısı = parametre sayısı
    const placeholders = new Set([...sql.matchAll(/\$(\d+)/g)].map((m) => Number(m[1])));
    assert.equal(Math.max(...placeholders), params.length);
  });

  it('dekont / banka / kart kaynaklı tahsilatın ters kaydı da izi taşır', async () => {
    for (const [kind, sourceId] of [['payment_notice', '55'], ['bank_line', '7001'], ['card', '9']]) {
      const client = fakeClient();
      await insertReversal(client, request(original({ kind: 'payment', amount_minor: '-125000', source_kind: kind, source_id: sourceId })));
      assert.deepEqual(client.calls[0].params.slice(-2), [kind, sourceId], kind);
    }
  });

  it('kaynaksız (elle) kayıtta ikisi de NULL; source_id yalnız source_kind varken yazılır (chk_ledger_entries_source)', async () => {
    const manual = fakeClient();
    await insertReversal(manual, request(original()));
    assert.deepEqual(manual.calls[0].params.slice(-2), [null, null]);
    const kindOnly = fakeClient();
    await insertReversal(kindOnly, request(original({ source_kind: 'manual', source_id: null })));
    assert.deepEqual(kindOnly.calls[0].params.slice(-2), ['manual', null]);
    // source_kind yok ama source_id dolu gelirse (bozuk satır) source_id YAZILMAZ: kısıt ihlali olmaz
    const orphanId = fakeClient();
    await insertReversal(orphanId, request(original({ source_kind: null, source_id: '3' })));
    assert.deepEqual(orphanId.calls[0].params.slice(-2), [null, null]);
  });

  it('sözleşme: devir kaynağı raporlarda süzgeçle dışlanır; ters kayıt aynı izi taşıdığı için asılla birlikte dışarıda kalır', () => {
    const reports = readFileSync(new URL('../src/modules/finance_reports.js', import.meta.url), 'utf8');
    const home = readFileSync(new URL('../src/modules/finance_home.js', import.meta.url), 'utf8');
    assert.match(reports, /source_kind IS DISTINCT FROM 'opening' AND \(kind = 'charge' OR \(kind = 'reversal' AND amount_minor < 0\)\)/);
    assert.match(home, /COALESCE\(source_kind, ''\) <> 'opening' AND \(kind = 'charge' OR \(kind = 'reversal' AND amount_minor < 0\)\)/);
  });
});
