// m² (alan) dağıtımı KALDIRILDI: daire alanı sistemde tutulmuyor (gross_area_m2 / net_area_m2 sütunları düşürüldü). DB'siz, sahte veritabanı.
//  - Yeni tanım / ek borç / dağıtım değişikliği 'area' isterse 400 AREA_DISTRIBUTION_REMOVED (hiç DB işlemi açılmaz).
//  - MEVCUT 'area' tanımının önizlemesi / borçlandırması 409 AREA_DISTRIBUTION_REMOVED (eskiden her daire area_missing: belirsiz tıkanma).
//  - Mevcut 'area' tanımı (borçlandırılmış olsa da) pasifleştirilebilir.
import { afterEach, beforeEach, describe, it } from 'node:test';
import assert from 'node:assert/strict';

process.env.JWT_SECRET ||= 'test-secret-test-secret-test-secret-123456';

const { pool } = await import('../src/db.js');
const { createDefinition, postCharge, postDefinition, previewCharge, previewDefinition, updateDefinition } = await import('../src/modules/finance_service.js');

const SITE = 1000000001;
const NOW = new Date('2026-10-16T09:00:00Z');
const MANAGER = { id: 20001, user_code: 20001, role: 'site_manager', full_name: 'Ayşe Yönetici' };
const norm = (text) => String(text).replace(/\s+/g, ' ').trim();
const ok = (rows = []) => ({ rows, rowCount: rows.length });

const areaRow = (extra = {}) => ({
  id: '7',
  name: 'Eski alan aidatı',
  kind: 'recurring',
  distribution: 'area',
  area_basis: 'gross',
  amount_minor: '500000',
  category_amounts: null,
  due_day: 5,
  start_period: '2026-01-01',
  end_period: null,
  target_type: 'site',
  target_block_ids: [],
  target_apartment_ids: [],
  is_active: true,
  created_at: new Date('2026-01-02T09:00:00Z'),
  updated_at: new Date('2026-01-02T09:00:00Z'),
  charge_party: null,
  created_by_name: 'Ayşe Yönetici',
  has_runs: true,
  last_posted_period: '2026-09-01',
  ...extra,
});

let originalQuery;
let originalConnect;
let log;
let definition;
let updateParams;

function install() {
  log = [];
  updateParams = null;
  definition = areaRow();
  const handlers = [
    [/^(BEGIN|COMMIT|ROLLBACK)$/, () => ok()],
    [/^(SAVEPOINT|RELEASE SAVEPOINT|ROLLBACK TO SAVEPOINT) /, () => ok()],
    [/pg_advisory_xact_lock/, () => ok()],
    [/^SELECT site_code FROM sites WHERE site_code = \$1 FOR KEY SHARE$/, () => ok([{ site_code: SITE }])],
    [/SELECT enabled FROM site_modules WHERE site_code = \$1 AND module_code = \$2/, () => ok([{ enabled: true }])],
    [/^SELECT user_code FROM users WHERE user_code = \$1 AND deleted_at IS NULL FOR KEY SHARE$/, (_s, p) => ok([{ user_code: p[0] }])],
    [/^SELECT id FROM fee_definitions WHERE id = \$1 AND site_code = \$2 FOR UPDATE$/, () => ok([{ id: '7' }])],
    [/FROM fee_definitions d LEFT JOIN users u ON u\.user_code = d\.created_by WHERE d\.id = \$1 AND d\.site_code = \$2/, () => ok([definition])],
    [/FROM fee_runs r INNER JOIN fee_definitions d ON d\.id = r\.definition_id/, () => ok([])],
    [
      /^UPDATE fee_definitions SET name = \$3/,
      (_s, p) => {
        updateParams = p;
        definition = { ...definition, name: p[2], distribution: p[4], area_basis: p[5], is_active: p[14] };
        return ok();
      },
    ],
    [/^INSERT INTO audit_log/, () => ok()],
  ];
  const query = async (text, params = []) => {
    const sql = norm(text);
    log.push({ sql, params });
    for (const [pattern, fn] of handlers) {
      if (pattern.test(sql)) return fn(sql, params);
    }
    throw new Error(`BEKLENMEYEN SQL: ${sql.slice(0, 220)}`);
  };
  originalQuery = pool.query;
  originalConnect = pool.connect;
  pool.query = query;
  pool.connect = async () => ({ query, release() {} });
  return query;
}

const rejectsArea = (status) => (error) => error.code === 'AREA_DISTRIBUTION_REMOVED' && error.statusCode === status;

describe('m² dağıtımı kaldırıldı (sunucu)', () => {
  beforeEach(() => {
    install();
  });
  afterEach(() => {
    pool.query = originalQuery;
    pool.connect = originalConnect;
  });

  it('yeni tanım: distribution=area 400 AREA_DISTRIBUTION_REMOVED; hiçbir DB işlemi açılmaz', async () => {
    const body = { name: 'Alan aidatı', kind: 'recurring', distribution: 'area', area_basis: 'gross', amount_minor: 500000, due_day: 5, start_period: '2026-10', target: { type: 'site' } };
    await assert.rejects(() => createDefinition({ siteCode: SITE, body, actor: MANAGER }), rejectsArea(400));
    assert.deepEqual(log, [], 'doğrulama DB\'den önce reddeder');
  });

  it('ek borç: önizleme ve onay distribution=area 400 AREA_DISTRIBUTION_REMOVED', async () => {
    const body = { name: 'Asansör', distribution: 'area', area_basis: 'net', amount_minor: 100000, target: { type: 'site' } };
    await assert.rejects(() => previewCharge({ siteCode: SITE, body, now: NOW }, pool), rejectsArea(400));
    await assert.rejects(
      () => postCharge({ siteCode: SITE, body: { ...body, expected_total_minor: 100000, expected_apartment_count: 5, expected_hash: 'a'.repeat(64), idempotency_key: 'ek-borc-anahtar-1' }, actor: MANAGER, now: NOW }),
      rejectsArea(400),
    );
    assert.deepEqual(log, []);
  });

  it('dağıtım değişikliği: PATCH distribution=area (alan esası ile ya da onsuz) 400 AREA_DISTRIBUTION_REMOVED', async () => {
    await assert.rejects(() => updateDefinition({ siteCode: SITE, rawId: '7', body: { distribution: 'area', area_basis: 'net' }, actor: MANAGER }), rejectsArea(400));
    await assert.rejects(() => updateDefinition({ siteCode: SITE, rawId: '7', body: { area_basis: 'net' }, actor: MANAGER }), rejectsArea(400));
    assert.deepEqual(log, []);
  });

  it('mevcut m² tanımının ÖNİZLEMESİ: 409 AREA_DISTRIBUTION_REMOVED (plan hesaplanmaz, daire sorgusu yok)', async () => {
    await assert.rejects(() => previewDefinition({ siteCode: SITE, rawId: '7', body: { period: '2026-10' }, now: NOW }, pool), rejectsArea(409));
    assert.equal(log.length, 1, 'yalnız tanım okunur');
    assert.equal(log.some((entry) => /FROM apartments a/.test(entry.sql)), false);
  });

  it('mevcut m² tanımının BORÇLANDIRMASI: 409 AREA_DISTRIBUTION_REMOVED; defter / çalıştırma satırı yazılmaz', async () => {
    const body = { period: '2026-10', expected_total_minor: 500000, expected_apartment_count: 5, expected_hash: 'a'.repeat(64), idempotency_key: 'borclandir-anahtar-1' };
    await assert.rejects(() => postDefinition({ siteCode: SITE, rawId: '7', body, actor: MANAGER, now: NOW }), rejectsArea(409));
    assert.equal(log.some((entry) => /^INSERT INTO (ledger_entries|fee_runs)/.test(entry.sql)), false);
    assert.equal(log.some((entry) => /FROM apartments a/.test(entry.sql)), false, 'plan hesaplanmadı');
    assert.equal(log.at(-1).sql, 'ROLLBACK');
  });

  it('PASİF m² tanımı hâlâ DEFINITION_INACTIVE verir (m² hatası pasifleştirilmiş tanımı örtmez)', async () => {
    definition = areaRow({ is_active: false });
    await assert.rejects(() => previewDefinition({ siteCode: SITE, rawId: '7', body: { period: '2026-10' }, now: NOW }, pool), (e) => e.code === 'DEFINITION_INACTIVE');
  });

  it('ÇIKIŞ: borçlandırılmış m² tanımı pasifleştirilebilir (is_active=false); dağıtım / alan esası değişmeden kalır', async () => {
    assert.equal(definition.has_runs, true);
    const out = await updateDefinition({ siteCode: SITE, rawId: '7', body: { is_active: false }, actor: MANAGER });
    assert.equal(out.is_active, false);
    assert.equal(out.distribution, 'area');
    // UPDATE parametreleri: [id, site, name, kind, distribution, area_basis, amount, categories, due_day, start, end, target..., is_active, charge_party]
    assert.equal(updateParams[4], 'area');
    assert.equal(updateParams[5], 'gross');
    assert.equal(updateParams[14], false);
  });

  it('borçlandırılmış m² tanımında dağıtım değiştirmek yine kilitli (DEFINITION_LOCKED); çıkış pasifleştirme + yeni tanım', async () => {
    await assert.rejects(
      () => updateDefinition({ siteCode: SITE, rawId: '7', body: { distribution: 'equal', amount_minor: 500000 }, actor: MANAGER }),
      (e) => e.code === 'DEFINITION_LOCKED',
    );
    assert.equal(updateParams, null);
  });

  it('borçlandırılmamış m² tanımı başka yönteme çevrilebilir (eşit)', async () => {
    definition = areaRow({ has_runs: false, last_posted_period: null });
    const out = await updateDefinition({ siteCode: SITE, rawId: '7', body: { distribution: 'equal', amount_minor: 500000 }, actor: MANAGER });
    assert.equal(out.distribution, 'equal');
    assert.equal(out.area_basis, null);
    assert.equal(updateParams[4], 'equal');
    assert.equal(updateParams[5], null);
  });
});
