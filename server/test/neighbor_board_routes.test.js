import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { cleanText, normalizeNote, normalizePostInput, shortName } from '../src/modules/neighbor_board_routes.js';
import { MODULE_CATALOG } from '../src/modules/catalog.js';

describe('komsu panosu girdi kurallari', () => {
  it('baslik ve metin sinirlari', () => {
    assert.throws(() => normalizePostInput({ title: 'ab', body: 'metin' }), (e) => e.code === 'INVALID_FIELD' && e.extra.field === 'title');
    assert.throws(() => normalizePostInput({ title: 'Baslik', body: 'x'.repeat(2001) }), (e) => e.extra.field === 'body');
    const ok = normalizePostInput({ title: '  Kayip   kedi ', body: ' Gri kedi\r\nbulundu ' });
    assert.deepEqual(ok, { title: 'Kayip kedi', text: 'Gri kedi\nbulundu' });
  });

  it('gerekce zorunlu ve sinirli', () => {
    assert.throws(() => normalizeNote('  ', 'note', { required: true }), (e) => e.extra.field === 'note');
    assert.throws(() => normalizeNote('x'.repeat(201), 'reason'), (e) => e.extra.field === 'reason');
    assert.equal(normalizeNote(undefined, 'note'), '');
  });

  it('gorunmez karakterler atilir, ad kisaltilir', () => {
    assert.equal(cleanText('a​b'), 'ab');
    assert.equal(shortName('Ayşe Yılmaz'), 'Ayşe Y.');
    assert.equal(shortName(null), 'Silinmiş Kullanıcı');
  });

  it('modul katalogda varsayilan KAPALI', () => {
    const mod = MODULE_CATALOG.find((m) => m.code === 'neighbor_board');
    assert.ok(mod);
    assert.equal(mod.defaultEnabled, false);
    assert.equal(mod.core, false);
  });
});
