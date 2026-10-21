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
