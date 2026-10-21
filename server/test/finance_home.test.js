import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { attentionSourceKeys, collectAttention, registerAttentionSource } from '../src/modules/attention_registry.js';
import { chargeStatus, parseHomeMonth } from '../src/modules/finance_home.js';

describe('finance_home', () => {
  it('parseHomeMonth: bos = bu ay (Istanbul), gecersiz = 400', () => {
    assert.equal(parseHomeMonth({ month: '2026-08' }), '2026-08-01');
    assert.match(parseHomeMonth({}, new Date('2026-10-21T12:00:00Z')), /^2026-10-01$/);
    assert.throws(() => parseHomeMonth({ month: 'abc' }));
    assert.throws(() => parseHomeMonth({ month: '2026-13' }));
  });

  it('chargeStatus: durum matrisi', () => {
    assert.equal(chargeStatus(0, 0), 'setup');
    assert.equal(chargeStatus(3, 0), 'todo');
    assert.equal(chargeStatus(3, 1), 'partial');
    assert.equal(chargeStatus(3, 3), 'done');
  });

  it('attention kaydi: finans kaynagi kayitli; hata ve sifir sayac listeden duser', async () => {
    assert.ok(attentionSourceKeys().includes('unassigned_payments'));
    registerAttentionSource({ key: 't_ok', module: null, run: async () => ({ count: 2, total_minor: 500 }) });
    registerAttentionSource({ key: 't_zero', module: null, run: async () => ({ count: 0 }) });
    registerAttentionSource({ key: 't_null', module: null, run: async () => null });
    registerAttentionSource({ key: 't_err', module: null, run: async () => { throw new Error('x'); } });
    // finans kaynagi (module: finance) DB gerektirir; testte yalniz modulsuz kaynaklar sonuc verir.
    const items = (await collectAttention(1, { query: async () => ({ rows: [] }) })).filter((i) => i.key.startsWith('t_'));
    assert.deepEqual(items, [{ key: 't_ok', module: null, count: 2, total_minor: 500 }]);
  });
});
