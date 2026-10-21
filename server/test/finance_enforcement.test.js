// F8 icra dökümü: hesap seçimi ayrıştırma + sahte veritabanıyla gruplama (DB'siz).
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { computeEnforcement, parseEnforcementAccounts } from '../src/modules/finance_enforcement.js';
import { EXPORT_KINDS } from '../src/modules/finance_export_tables.js';

const here = dirname(fileURLToPath(import.meta.url));

describe('F8 icra dökümü', () => {
  it('hesap seçimi: boş = tümü, geçerli liste tekrarsız, bozuk biçim reddedilir', () => {
    assert.equal(parseEnforcementAccounts(undefined), null);
    assert.equal(parseEnforcementAccounts(' '), null);
    assert.deepEqual(parseEnforcementAccounts('12:owner,15:tenant,12:owner'), [
      { apartmentId: 12, party: 'owner' },
      { apartmentId: 15, party: 'tenant' },
    ]);
    assert.throws(() => parseEnforcementAccounts('12:both'));
    assert.throws(() => parseEnforcementAccounts('x:owner'));
    const many = Array.from({ length: 201 }, (_, i) => `${i + 1}:owner`).join(',');
    assert.throws(() => parseEnforcementAccounts(many));
  });

  it('kalemler hesaba göre gruplanır; asıl alacak ve gecikme tazminatı ayrı toplanır; seçilmeyen hesap dışarıda', async () => {
    const rows = [
      { entry_id: '1', apartment_id: '5', account_party: 'owner', due: '2026-01-10', is_lf: false, amount: '10000', remaining: '10000', period: '2026-01-01', definition_name: 'Aidat', description: '', unit_label: '3', block_name: 'A' },
      { entry_id: '2', apartment_id: '5', account_party: 'owner', due: '2026-02-10', is_lf: true, amount: '500', remaining: '300', period: '2026-02-01', definition_name: null, description: null, unit_label: '3', block_name: 'A' },
      { entry_id: '3', apartment_id: '5', account_party: 'tenant', due: '2026-02-10', is_lf: false, amount: '700', remaining: '700', period: '2026-02-01', definition_name: 'Aidat', description: '', unit_label: '3', block_name: 'A' },
    ];
    const db = { query: async () => ({ rows }) };
    const all = await computeEnforcement(db, 1, '2026-03-01', null);
    assert.equal(all.length, 2);
    assert.equal(all[0].principal, 10000n);
    assert.equal(all[0].lateFee, 300n);
    assert.equal(all[0].items[1].name, 'Gecikme tazminatı');
    assert.equal(all[0].items[0].days_overdue, 50);
    const only = await computeEnforcement(db, 1, '2026-03-01', [{ apartmentId: 5, party: 'tenant' }]);
    assert.equal(only.length, 1);
    assert.equal(only[0].accountParty, 'tenant');
  });

  it('dışa aktarma türü kayıtlı ve uç yalnız yönetici', () => {
    assert.ok(EXPORT_KINDS.includes('finance_enforcement'));
    const routes = readFileSync(join(here, '..', 'src', 'modules', 'finance_4b_routes.js'), 'utf8');
    assert.match(routes, /reports\/enforcement`[^\n]*managerOnly: true/);
  });
});
