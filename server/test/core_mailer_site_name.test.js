import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { withSitesi } from '../src/mailer.js';

describe('withSitesi (e-posta konularında çift "Sitesi" olmasın)', () => {
  it('"Sitesi" ile bitmeyen ada ek ekler', () => {
    assert.equal(withSitesi('Mavi Park Evleri'), 'Mavi Park Evleri Sitesi');
    assert.equal(withSitesi('  Yıldız  '), 'Yıldız Sitesi');
  });

  it('zaten "Sitesi" veya "Site" ile biten adı değiştirmez', () => {
    assert.equal(withSitesi('Yeşilvadi Sitesi'), 'Yeşilvadi Sitesi');
    assert.equal(withSitesi('Güneş Site'), 'Güneş Site');
    assert.equal(withSitesi('Onay Bekleyen SİTESİ'.replace('SİTESİ', 'sitesi')), 'Onay Bekleyen sitesi');
  });

  it('boş/undefined değerde fırlatmaz', () => {
    assert.equal(withSitesi(undefined), ' Sitesi');
    assert.equal(withSitesi(null).trim(), 'Sitesi');
  });
});
