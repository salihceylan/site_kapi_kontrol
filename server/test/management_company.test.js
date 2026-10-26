import test from 'node:test';
import assert from 'node:assert/strict';
import { applyTrialToNewSubscription, rateBp, sortSitesByCollection, userCodeOf } from '../src/modules/management_company_service.js';
import { MANAGEMENT_COMPANY_DDL, ensureManagementCompanySchema } from '../src/modules/management_company_schema.js';

test('rateBp baz puan, yarım yukarı; payda 0 ise null', () => {
  assert.equal(rateBp('0', '0'), null);
  assert.equal(rateBp('500', '1000'), 5000);
  assert.equal(rateBp('1', '3'), 3333);
  assert.equal(rateBp('2', '3'), 6667);
});

test('tablo en düşük tahsilat oranı üstte, oransız site sonda', () => {
  const rows = [
    { name: 'C', collection_rate_bp: null },
    { name: 'B', collection_rate_bp: 9000 },
    { name: 'A', collection_rate_bp: 4000 },
    { name: 'Ä', collection_rate_bp: 9000 },
  ];
  const sorted = sortSitesByCollection(rows);
  assert.equal(sorted[0].name, 'A');
  assert.equal(sorted[3].name, 'C');
});

test('userCodeOf kimlikten tamsayı çıkarır', () => {
  assert.equal(userCodeOf({ userCode: 12345 }), 12345);
  assert.equal(userCodeOf({ id: '12345' }), 12345);
  assert.equal(userCodeOf({}), null);
});

test('şema: eksik yoksa DDL gönderilmez (yalnız kilit süresi ve tohum)', async () => {
  const sent = [];
  const client = {
    async query(text) {
      sent.push(text);
      if (/to_regclass/.test(text)) return { rows: [{ companies: true, members: true, sites: true, trial_col: true }] };
      return { rows: [] };
    },
  };
  await ensureManagementCompanySchema(client);
  assert.ok(!sent.some((s) => s.includes('CREATE TABLE') || s.includes('ALTER TABLE')));
});

test('şema: eksikse tablolar ve sütun eklenir', async () => {
  const sent = [];
  const client = {
    async query(text) {
      sent.push(text);
      if (/to_regclass/.test(text)) return { rows: [{ companies: false, members: false, sites: false, trial_col: false }] };
      return { rows: [] };
    },
  };
  await ensureManagementCompanySchema(client);
  for (const key of ['companies', 'members', 'sites', 'trialColumn']) {
    assert.ok(sent.includes(MANAGEMENT_COMPANY_DDL[key]), key);
  }
});

test('deneme: ayar 60 gün ise abonelik trial olur; hata siteyi bozmaz', async () => {
  const sent = [];
  const ok = {
    async query(text, params) {
      sent.push([text, params]);
      if (/FROM platform_settings/.test(text)) return { rows: [{ value: { days: 60 } }] };
      return { rows: [] };
    },
  };
  await applyTrialToNewSubscription(ok, 1234567890);
  const update = sent.find(([t]) => /UPDATE site_subscriptions/.test(t));
  assert.deepEqual(update[1], [1234567890, 60]);

  const failing = {
    async query(text) {
      if (/FROM platform_settings/.test(text)) throw new Error('boom');
      return { rows: [] };
    },
  };
  await applyTrialToNewSubscription(failing, 1);
});

// --- Pasif firma (is_active = false): süper kullanıcı hariç firma erişimi kesilir (404) ---------------------------------------------

test('companyRoleOf: süper her zaman "super"; üye sorgusu firmayı AKTİF koşuluyla birleştirir (pasif firmada rol dönmez)', async () => {
  const { companyRoleOf } = await import('../src/modules/management_company_service.js');
  const asked = [];
  const db = {
    async query(text, params) {
      asked.push([String(text).replace(/\s+/g, ' ').trim(), params]);
      return { rows: [] };
    },
  };
  assert.equal(await companyRoleOf(db, 5, { role: 'super_user', id: 1 }), 'super');
  assert.equal(asked.length, 0, 'süper için sorgu yok');
  assert.equal(await companyRoleOf(db, 5, { userCode: 77 }), null, 'pasif firma / üye değil: rol yok');
  assert.match(asked[0][0], /JOIN management_companies c ON c\.id = m\.company_id AND c\.is_active = TRUE/);
  assert.deepEqual(asked[0][1], [5, 77]);
  assert.equal(await companyRoleOf(db, 5, {}), null, 'kimliksiz kullanıcı');
  const active = { async query() { return { rows: [{ role: 'owner' }] }; } };
  assert.equal(await companyRoleOf(active, 5, { userCode: 77 }), 'owner');
});

test('requireCompanyAccess: pasif firmada üye/sahip 404 COMPANY_NOT_FOUND (varlığı sızmaz); süper erişir', async () => {
  const { pool } = await import('../src/db.js');
  const { requireCompanyAccess } = await import('../src/modules/management_company_service.js');
  const original = pool.query;
  try {
    // pasif firma: üyelik satırı var ama JOIN is_active koşulu satırı eler -> boş
    pool.query = async () => ({ rows: [], rowCount: 0 });
    await assert.rejects(requireCompanyAccess(5, { userCode: 77 }), (e) => e.statusCode === 404 && e.code === 'COMPANY_NOT_FOUND');
    await assert.rejects(requireCompanyAccess(5, { userCode: 77 }, { needOwner: true }), (e) => e.statusCode === 404);
    assert.equal(await requireCompanyAccess(5, { role: 'super_user', id: 1 }, { needSuper: true }), 'super');
    pool.query = async () => ({ rows: [{ role: 'staff' }], rowCount: 1 });
    assert.equal(await requireCompanyAccess(5, { userCode: 77 }), 'staff');
    await assert.rejects(requireCompanyAccess(5, { userCode: 77 }, { needOwner: true }), (e) => e.statusCode === 403);
  } finally {
    pool.query = original;
  }
});
