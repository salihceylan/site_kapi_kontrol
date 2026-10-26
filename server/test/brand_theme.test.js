import test from 'node:test';
import assert from 'node:assert/strict';
import { contrast, onColorFor, themeFromRow, validateThemeBody } from '../src/modules/brand_theme_common.js';
import { BRAND_THEME_DDL, ensureBrandThemeSchema } from '../src/modules/brand_theme_schema.js';

const GOOD = { primary: '#0F172A', accent: '#1D4ED8', background: '#F8FAFC', surface: '#FFFFFF', text: '#0F172A' };

test('geçerli tema normalleşir (büyük harf, boşluk kırpma)', () => {
  const v = validateThemeBody({ display_name: '  Yıldız Yönetim ', colors: { ...GOOD, accent: '#1d4ed8 ' } });
  assert.equal(v.display_name, 'Yıldız Yönetim');
  assert.equal(v.colors.accent, '#1D4ED8');
  assert.equal(v.logo_data, undefined);
});

test('bozuk renk 400 INVALID_COLOR', () => {
  assert.throws(() => validateThemeBody({ colors: { ...GOOD, primary: 'red' } }), { code: 'INVALID_COLOR' });
  assert.throws(() => validateThemeBody({}), { code: 'INVALID_COLOR' });
});

test('düşük karşıtlık reddedilir', () => {
  assert.throws(() => validateThemeBody({ colors: { ...GOOD, text: '#E5E7EB' } }), { code: 'LOW_CONTRAST' });
  assert.throws(() => validateThemeBody({ colors: { ...GOOD, accent: '#E5E7EB' } }), { code: 'LOW_CONTRAST' });
});

test('ad sınırı ve logo biçimi', () => {
  assert.throws(() => validateThemeBody({ colors: GOOD, display_name: 'x'.repeat(41) }), { code: 'INVALID_NAME' });
  assert.throws(() => validateThemeBody({ colors: GOOD, logo_data: 'data:image/svg+xml;base64,AAAA' }), { code: 'INVALID_LOGO' });
  assert.equal(validateThemeBody({ colors: GOOD, logo_data: 'data:image/png;base64,iVBORw0KGgo=' }).logo_data, 'data:image/png;base64,iVBORw0KGgo=');
  assert.equal(validateThemeBody({ colors: GOOD, logo_data: null }).logo_data, null);
});

test('kontrast ve üstündeki yazı rengi', () => {
  assert.ok(contrast('#000000', '#FFFFFF') > 20.9);
  assert.equal(onColorFor('#0F172A'), '#FFFFFF');
  assert.equal(onColorFor('#FDE047'), '#0F172A');
});

test('themeFromRow: satır yoksa null, varsa on_primary hesaplanır', () => {
  assert.equal(themeFromRow(null, 'site'), null);
  const t = themeFromRow({ scope_type: 'site', scope_id: '5', color_primary: '#0F172A', color_accent: '#1D4ED8', color_background: '#F8FAFC', color_surface: '#FFFFFF', color_text: '#0F172A' }, 'site');
  assert.equal(t.scope_id, 5);
  assert.equal(t.on_primary, '#FFFFFF');
  assert.equal(t.logo_data, null);
});

test('şema: tablo varsa DDL gönderilmez, yoksa bir kez gönderilir', async () => {
  const run = async (present) => {
    const sent = [];
    await ensureBrandThemeSchema({
      async query(text) {
        sent.push(text);
        return /to_regclass/.test(text) ? { rows: [{ present }] } : { rows: [] };
      },
    });
    return sent;
  };
  assert.ok(!(await run(true)).some((s) => s.includes('CREATE TABLE')));
  assert.ok((await run(false)).includes(BRAND_THEME_DDL.table));
});

// --- Pasif firma: tema düzenleme ve miras kesilir ---------------------------------------------------------------------------------

const ROW = { scope_type: 'company', scope_id: '5', display_name: 'Yıldız', color_primary: '#0F172A', color_accent: '#1D4ED8', color_background: '#F8FAFC', color_surface: '#FFFFFF', color_text: '#0F172A', logo_data: null };

test('pasif firma: firma sahibi (süper değil) tema düzenleyemez (404); firma yoksa 404; süper pasif firmayı düzenler', async () => {
  const { pool } = await import('../src/db.js');
  const { getEditableTheme } = await import('../src/modules/brand_theme_service.js');
  const original = pool.query;
  const calls = [];
  try {
    pool.query = async (text, params) => {
      const sql = String(text).replace(/\s+/g, ' ').trim();
      calls.push(sql);
      if (/^SELECT 1 FROM management_companies WHERE id = \$1$/.test(sql)) return { rows: [{ '?column?': 1 }], rowCount: 1 }; // firma var (pasif de olsa)
      if (/FROM management_company_members m JOIN management_companies c ON c\.id = m\.company_id AND c\.is_active = TRUE/.test(sql)) return { rows: [], rowCount: 0 }; // pasif -> rol yok
      if (/FROM brand_themes WHERE scope_type = \$1 AND scope_id = \$2/.test(sql)) return { rows: [ROW], rowCount: 1 };
      throw new Error('beklenmeyen SQL: ' + sql);
    };
    await assert.rejects(getEditableTheme({ scopeType: 'company', scopeId: '5', user: { userCode: 77, role: 'site_manager' } }), (e) => e.statusCode === 404 && e.code === 'COMPANY_NOT_FOUND');
    const asSuper = await getEditableTheme({ scopeType: 'company', scopeId: '5', user: { userCode: 1, role: 'super_user' } });
    assert.equal(asSuper.can_edit, true);
    // aktif firma sahibi geçer
    pool.query = async (text) => {
      const sql = String(text).replace(/\s+/g, ' ').trim();
      if (/^SELECT 1 FROM management_companies WHERE id = \$1$/.test(sql)) return { rows: [{ x: 1 }], rowCount: 1 };
      if (/FROM management_company_members m JOIN management_companies c/.test(sql)) return { rows: [{ role: 'owner' }], rowCount: 1 };
      if (/FROM brand_themes/.test(sql)) return { rows: [ROW], rowCount: 1 };
      throw new Error('beklenmeyen SQL: ' + sql);
    };
    assert.equal((await getEditableTheme({ scopeType: 'company', scopeId: '5', user: { userCode: 77, role: 'site_manager' } })).can_edit, true);
  } finally {
    pool.query = original;
  }
});

test('pasif firmaya bağlı site: firma sahibi site temasını düzenleyemez (404 SITE_NOT_FOUND) ve firma teması siteye MİRAS kalmaz', async () => {
  const { pool } = await import('../src/db.js');
  const { getEditableTheme, resolveSiteTheme, themeForUser } = await import('../src/modules/brand_theme_service.js');
  const original = pool.query;
  const seen = [];
  try {
    pool.query = async (text) => {
      const sql = String(text).replace(/\s+/g, ' ').trim();
      seen.push(sql);
      if (/^SELECT 1 FROM sites WHERE site_code = \$1$/.test(sql)) return { rows: [{ x: 1 }], rowCount: 1 };
      // companyOfSite yalnız AKTİF firma döndürür: pasif -> boş
      if (/FROM management_company_sites cs JOIN management_companies c ON c\.id = cs\.company_id AND c\.is_active = TRUE/.test(sql)) return { rows: [], rowCount: 0 };
      if (/FROM brand_themes WHERE scope_type = \$1 AND scope_id = \$2/.test(sql)) return { rows: [], rowCount: 0 };
      if (/FROM site_memberships/.test(sql)) return { rows: [{ site_code: '9' }], rowCount: 1 };
      throw new Error('beklenmeyen SQL: ' + sql);
    };
    await assert.rejects(getEditableTheme({ scopeType: 'site', scopeId: '9', user: { userCode: 77, role: 'site_manager' } }), (e) => e.statusCode === 404 && e.code === 'SITE_NOT_FOUND');
    assert.equal(await resolveSiteTheme(pool, 9), null, 'pasif firmanın teması miras kalmaz');
    assert.deepEqual(await themeForUser({ userCode: 77, role: 'site_manager' }), { theme: null });
    assert.ok(seen.some((s) => /c\.is_active = TRUE/.test(s)));
  } finally {
    pool.query = original;
  }
});

test('themeForUser: firma üyeliği yalnız AKTİF firmada aranır (pasif firmanın teması üyesine uygulanmaz)', async () => {
  const { themeForUser } = await import('../src/modules/brand_theme_service.js');
  const sql = [];
  const db = {
    async query(text) {
      const s = String(text).replace(/\s+/g, ' ').trim();
      sql.push(s);
      if (/FROM site_memberships/.test(s)) return { rows: [], rowCount: 0 };
      return { rows: [], rowCount: 0 };
    },
  };
  assert.deepEqual(await themeForUser({ userCode: 77, role: 'site_manager' }, db), { theme: null });
  const member = sql.find((s) => /FROM management_company_members m/.test(s));
  assert.match(member, /JOIN management_companies c ON c\.id = m\.company_id AND c\.is_active = TRUE/);
});
