// İki hesap (İP-1A): borçlandırma önizlemesinde satırın hesabı ("kim öder" + dairenin sorumlusu + borç tarihindeki kiracı) ve planHash (KATI sahte DB).
// Gerçek PostgreSQL: scripts/qa_platform_pg.mjs "parties" (borçlandırma, ek borç, PREVIEW_STALE).
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { previewCharge } from '../src/modules/finance_service.js';

const norm = (text) => String(text).replace(/\s+/g, ' ').trim();
const ok = (rows = []) => ({ rows, rowCount: rows.length });

function fakeDb(apartments) {
  const calls = [];
  return {
    calls,
    async query(text, params = []) {
      const sql = norm(text);
      calls.push({ sql, params });
      if (/FROM apartments a INNER JOIN site_blocks b ON b\.id = a\.block_id WHERE a\.site_code = \$1 AND a\.is_active = TRUE/.test(sql)) return ok(apartments);
      if (/FROM fee_runs WHERE site_code = \$1 AND natural_key = \$2/.test(sql)) return ok();
      if (/FROM finance_period_closures WHERE site_code = \$1 AND period >= \$2::DATE/.test(sql)) return ok();
      // Tahakkuk dayanağı (K2): önizleme yanıtındaki decision_requirement için Karar Defteri modül durumu (kapalı)
      if (/^SELECT enabled FROM site_modules WHERE site_code = \$1 AND module_code = \$2 LIMIT 1$/.test(sql)) return ok([{ enabled: false }]);
      throw new Error(`BEKLENMEYEN SQL: ${sql.slice(0, 160)}`);
    },
  };
}

const apt = (id, responsible, hasTenant) => ({
  id: String(id), unit_label: `Daire ${id}`, block_name: 'A Blok', block_sort: 1, apt_sort: id, responsible_party: responsible, category: null,
  gross_x100: null, net_x100: null, land_share_numerator: null, land_share_denominator: null, has_tenant: hasTenant,
});
const NOW = new Date('2026-10-21T09:00:00Z');
const body = (extra = {}) => ({ name: 'Asansör yenileme', distribution: 'fixed', amount_minor: 1000, target: { type: 'site' }, ...extra });

describe('İP-1A ek borç önizlemesi: satır hesabı', () => {
  const apartments = [apt(1, 'owner', true), apt(2, 'tenant', true), apt(3, 'tenant', false), apt(4, 'both', true), apt(5, 'both', false)];

  it('varsayılan (ev sahibi): tüm satırlar ev sahibi hesabına; borç tarihi (bugün) kiracı denetimine parametre olarak gider', async () => {
    const db = fakeDb(apartments);
    const preview = await previewCharge({ siteCode: 1000000001, body: body(), now: NOW }, db);
    assert.deepEqual(preview.lines.map((l) => [l.apartment_id, l.account_party]), [[1, 'owner'], [2, 'owner'], [3, 'owner'], [4, 'owner'], [5, 'owner']]);
    const select = db.calls.find((c) => /FROM apartments a INNER JOIN site_blocks/.test(c.sql));
    assert.equal(select.params[4], '2026-10-21');
    assert.match(select.sql, /tr\.relation = 'tenant'/);
  });

  it('"dairede oturan": sorumlu owner -> ev sahibi; tenant / both -> kiracı varsa kiracı, yoksa ev sahibi', async () => {
    const preview = await previewCharge({ siteCode: 1000000001, body: body({ charge_party: 'occupant' }), now: NOW }, fakeDb(apartments));
    assert.deepEqual(preview.lines.map((l) => [l.apartment_id, l.account_party]), [[1, 'owner'], [2, 'tenant'], [3, 'owner'], [4, 'tenant'], [5, 'owner']]);
  });

  it('önizleme özeti hesabı içerir: aynı tutar ve daireler, farklı hesap -> farklı preview_hash', async () => {
    const owner = await previewCharge({ siteCode: 1000000001, body: body(), now: NOW }, fakeDb(apartments));
    const occupant = await previewCharge({ siteCode: 1000000001, body: body({ charge_party: 'occupant' }), now: NOW }, fakeDb(apartments));
    assert.equal(owner.total_minor, occupant.total_minor);
    assert.notEqual(owner.preview_hash, occupant.preview_hash);
  });
});
