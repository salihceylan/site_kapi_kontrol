// Duyuru e-postası sırrı için açılış doğrulaması (E2): production'da tanımsızsa JWT_SECRET'tan türetme uyarısı, zayıf / yer tutucu değer uyarısı.
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { validateEnv } from '../src/config/env.js';

const base = { JWT_SECRET: 'k9Fz-test-only-long-secret-value-0123456789abcdef' };
const announcementWarnings = (env) => validateEnv(env).warnings.filter((warning) => /ANNOUNCEMENT_EMAIL_SECRET/.test(warning));

describe('validateEnv: ANNOUNCEMENT_EMAIL_SECRET', () => {
  it('production\'da tanımsızsa JWT_SECRET\'tan türetildiği ve döndürmenin bastırma listesini bozacağı UYARILIR (hata değil); PREVIOUS önerisi verilir', () => {
    const { errors } = validateEnv({ ...base, NODE_ENV: 'production' });
    assert.deepEqual(errors, []);
    const warnings = announcementWarnings({ ...base, NODE_ENV: 'production' });
    assert.equal(warnings.length, 1);
    assert.match(warnings[0], /JWT_SECRET'tan turetiliyor/);
    assert.match(warnings[0], /ANNOUNCEMENT_EMAIL_SECRET_PREVIOUS/);
    assert.match(warnings[0], /bastirma|abonelikten cikma listesi/i);
  });

  it('production dışında (geliştirme / test) tanımsız sır için uyarı yok', () => {
    assert.deepEqual(announcementWarnings({ ...base, NODE_ENV: 'development' }), []);
    assert.deepEqual(announcementWarnings({ ...base }), []);
  });

  it('güçlü sır (>= 16 karakter, yer tutucu değil): uyarı yok', () => {
    assert.deepEqual(announcementWarnings({ ...base, NODE_ENV: 'production', ANNOUNCEMENT_EMAIL_SECRET: 'rastgele-guclu-duyuru-sirri-0123456789' }), []);
  });

  it('yer tutucu ya da zayıf (< 16 karakter) sır UYARILIR; < 8 karakterse JWT_SECRET\'a düşüleceği söylenir; sırrın KENDİSİ mesajda yer almaz', () => {
    for (const secret of ['changeme', 'change-me-please-1234567890', 'abcdefg', '123456789012345', 'replace_me', 'xxxxxxxxxxxxxxxxxxxx']) {
      const warnings = announcementWarnings({ ...base, NODE_ENV: 'production', ANNOUNCEMENT_EMAIL_SECRET: secret });
      assert.equal(warnings.length, 1, secret);
      assert.match(warnings[0], /yer tutucu ya da zayif/);
      assert.match(warnings[0], /8 karakterden kisaysa/);
      assert.ok(!warnings[0].includes(secret), 'sır değeri mesaja yazılmaz');
    }
  });

  it('zayıf sır production dışında da uyarılır (yanlış değerle başlatma erken görülsün); boşluklardan oluşan değer tanımsız sayılır', () => {
    assert.equal(announcementWarnings({ ...base, ANNOUNCEMENT_EMAIL_SECRET: 'changeme' }).length, 1);
    assert.equal(announcementWarnings({ ...base, NODE_ENV: 'production', ANNOUNCEMENT_EMAIL_SECRET: '   ' }).length, 1);
    assert.match(announcementWarnings({ ...base, NODE_ENV: 'production', ANNOUNCEMENT_EMAIL_SECRET: '   ' })[0], /tanimli degil/);
  });
});
