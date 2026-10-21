// İki hesap (İP-1A): sakin görünümleri (kendi hesabı, both dairede malike salt okunur kiracı hesabı, family_member yok) ve hesap başına kapsam zinciri (saf).
// Gerçek PostgreSQL: scripts/qa_platform_pg.mjs "parties" (görünürlük matrisi, IDOR) ve "finance4b" S bölümü (kapsam).
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { residentViewsOf, rowsOfView, viewSinceOf } from '../src/modules/finance_read_service.js';

const row = (overrides = {}) => ({
  relation: 'owner',
  responsible_party: 'owner',
  has_current_tenant: false,
  start_date: '2026-10-21',
  relation_created_at: '2026-10-21T08:00:00.000Z',
  previous: [],
  ...overrides,
});
const shape = (views) => views.map((v) => [v.account_party, v.role, v.visible_from]);

describe('residentViewsOf: kim hangi hesabı görür', () => {
  it('malik: kendi ev sahibi hesabı; sorumlu both ise kiracı hesabını SALT OKUNUR da görür', () => {
    assert.deepEqual(shape(residentViewsOf(row())), [['owner', 'own', '2026-10-01']]);
    assert.deepEqual(shape(residentViewsOf(row({ responsible_party: 'both' }))), [['owner', 'own', '2026-10-01'], ['tenant', 'read_only', '2026-10-01']]);
    assert.deepEqual(shape(residentViewsOf(row({ responsible_party: 'tenant' }))), [['owner', 'own', '2026-10-01']]);
  });

  it('kiracı yalnız kiracı hesabını görür (both dahil); aile üyesi hiçbir hesabı görmez', () => {
    for (const responsible of ['owner', 'tenant', 'both']) {
      assert.deepEqual(shape(residentViewsOf(row({ relation: 'tenant', responsible_party: responsible }))), [['tenant', 'own', '2026-10-01']], responsible);
      assert.deepEqual(residentViewsOf(row({ relation: 'family_member', responsible_party: responsible })), [], responsible);
    }
  });

  it('ilişkisi belirtilmemiş sakin (resident): dairede güncel kiracı varsa kiracı hesabı, yoksa ev sahibi hesabı; salt okunur görünüm YOK', () => {
    assert.deepEqual(shape(residentViewsOf(row({ relation: 'resident', has_current_tenant: true, responsible_party: 'both' }))), [['tenant', 'own', '2026-10-01']]);
    assert.deepEqual(shape(residentViewsOf(row({ relation: 'resident', has_current_tenant: false, responsible_party: 'both' }))), [['owner', 'own', '2026-10-01']]);
  });

  it('inceleme (F2.05 korunur): sorumlu malik / kiracı ve o tarafın güncel kişisi VARKEN belirtilmemiş sakin hiçbir hesabı görmez; kişi yoksa (yedek) oturanın hesabını görür', () => {
    for (const responsible of ['owner', 'tenant']) {
      for (const hasTenant of [true, false]) {
        assert.deepEqual(residentViewsOf(row({ relation: 'resident', responsible_party: responsible, has_current_tenant: hasTenant, has_responsible_person: true })), [], `${responsible}/${hasTenant}`);
      }
    }
    assert.deepEqual(shape(residentViewsOf(row({ relation: 'resident', responsible_party: 'owner', has_current_tenant: false, has_responsible_person: false }))), [['owner', 'own', '2026-10-01']]);
    assert.deepEqual(shape(residentViewsOf(row({ relation: 'resident', responsible_party: 'tenant', has_current_tenant: false, has_responsible_person: false }))), [['owner', 'own', '2026-10-01']]);
    // both dairede sorumlu kişi bilgisi önemsizdir (eski kural: malik + kiracı + belirtilmemiş sakin görür)
    assert.deepEqual(shape(residentViewsOf(row({ relation: 'resident', responsible_party: 'both', has_current_tenant: true, has_responsible_person: true }))), [['tenant', 'own', '2026-10-01']]);
    // malik / kiracı kendi hesabını sorumlu kişiden bağımsız görür
    assert.deepEqual(shape(residentViewsOf(row({ relation: 'tenant', responsible_party: 'owner', has_responsible_person: true }))), [['tenant', 'own', '2026-10-01']]);
    assert.deepEqual(shape(residentViewsOf(row({ relation: 'owner', responsible_party: 'tenant', has_responsible_person: true }))), [['owner', 'own', '2026-10-01']]);
  });

  it('kapsam zinciri hesap başına: kiracıyken satın alan malik eski kayıtlarını salt okunur kiracı hesabında görür; ev sahibi hesabında kapsam kendi malikliğiyle başlar', () => {
    const buyer = row({
      responsible_party: 'both',
      previous: [{ relation: 'tenant', start_date: '2026-07-05', created_at: '2026-07-05T08:00:00.000Z' }],
    });
    const views = residentViewsOf(buyer);
    assert.deepEqual(shape(views), [['owner', 'own', '2026-10-01'], ['tenant', 'read_only', '2026-07-01']]);
    assert.equal(views[0].relation_since_at, '2026-10-21T08:00:00.000Z');
    assert.equal(views[1].relation_since_at, '2026-07-05T08:00:00.000Z');
    // malik sorumlu dairede kiracılık dönemi hiçbir görünümü uzatmaz (salt okunur kiracı hesabı da yok)
    assert.deepEqual(shape(residentViewsOf({ ...buyer, responsible_party: 'owner' })), [['owner', 'own', '2026-10-01']]);
    // aynı hesaba düşen önceki ilişki (önceki malikliği) zinciri uzatır
    assert.deepEqual(shape(residentViewsOf(row({ previous: [{ relation: 'owner', start_date: '2025-03-10', created_at: '2025-03-10T08:00:00.000Z' }] }))), [['owner', 'own', '2025-03-01']]);
    // aile üyeliği zincire girmez (sorgu zaten dışlar; savunma)
    assert.deepEqual(shape(residentViewsOf(row({ previous: [{ relation: 'family_member', start_date: '2020-01-01', created_at: '2020-01-01T00:00:00.000Z' }] }))), [['owner', 'own', '2026-10-01']]);
  });

  it('viewSinceOf: okunamazsa bu ay (sınır kalkmaz); rowsOfView 052 öncesi satırı payer_party ile hesaba koyar', () => {
    assert.equal(viewSinceOf({ visible_from: '2026-07-01' }, '2026-10-21'), '2026-07-01');
    assert.equal(viewSinceOf({ visible_from: null }, '2026-10-21'), '2026-10-01');
    const rows = [{ id: 1, payer_party: 'both' }, { id: 2, payer_party: 'tenant' }, { id: 3, payer_party: 'owner', account_party: 'tenant' }];
    assert.deepEqual(rowsOfView(rows, { account_party: 'tenant' }).map((r) => r.id), [2, 3]);
    assert.deepEqual(rowsOfView(rows, { account_party: 'owner' }).map((r) => r.id), [1]);
  });
});
