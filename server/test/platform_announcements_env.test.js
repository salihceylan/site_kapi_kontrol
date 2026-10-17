// Duyuru e-postası sırrı için açılış doğrulaması (E2): production'da tanımsızsa JWT_SECRET'tan türetme uyarısı, zayıf / yer tutucu değer uyarısı.
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { resolveServerStart, validateEnv } from '../src/config/env.js';

const here = path.dirname(fileURLToPath(import.meta.url));
const serverUrl = pathToFileURL(path.join(here, '..', 'src', 'server.js')).href;

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

describe('F3 sır dönüşümü uyarı metni', () => {
  it('tanımsız (production), zayıf sır ve kullanılamayan PREVIOUS uyarıları PREVIOUS\'tan sır silmenin bastırmayı kaybettireceğini ve değerlerin virgül içeremeyeceğini söyler', () => {
    const undefinedWarning = announcementWarnings({ ...base, NODE_ENV: 'production' })[0];
    const weakWarning = announcementWarnings({ ...base, ANNOUNCEMENT_EMAIL_SECRET: 'changeme' })[0];
    const previousWarning = announcementWarnings({ ...base, ANNOUNCEMENT_EMAIL_SECRET: 'rastgele-guclu-duyuru-sirri-0123456789', ANNOUNCEMENT_EMAIL_SECRET_PREVIOUS: 'eski-sir-0123456789, kisa' })[0];
    for (const warning of [undefinedWarning, weakWarning, previousWarning]) {
      assert.match(warning, /PREVIOUS'tan bir sir silinirse/);
      assert.match(warning, /abonelikten cikma kayitlari/);
      assert.match(warning, /eski baglantilar gecersiz/);
      assert.match(warning, /virgul iceremez/);
    }
    assert.match(previousWarning, /kullanilamayan 1 girdi/);
  });

  it('geçerli PREVIOUS (>= 8 karakter, kırpılmış) uyarı üretmez; yalnız boşluk / boş girdiler (sondaki virgül) sayılır', () => {
    assert.deepEqual(announcementWarnings({ ...base, ANNOUNCEMENT_EMAIL_SECRET: 'rastgele-guclu-duyuru-sirri-0123456789', ANNOUNCEMENT_EMAIL_SECRET_PREVIOUS: '  eski-sir-0123456789  ' }), []);
    const trailing = announcementWarnings({ ...base, ANNOUNCEMENT_EMAIL_SECRET: 'rastgele-guclu-duyuru-sirri-0123456789', ANNOUNCEMENT_EMAIL_SECRET_PREVIOUS: 'eski-sir-0123456789,' });
    assert.equal(trailing.length, 1);
    assert.match(trailing[0], /kullanilamayan 1 girdi/);
  });

  it('F4 validateEnv uzunluğu kırpılmış değerle ölçer (modülle aynı kural): "  abcdefghijklmnop  " (16) uyarı vermez, "  abcdefghijklmno  " (15) verir', () => {
    assert.deepEqual(announcementWarnings({ ...base, NODE_ENV: 'production', ANNOUNCEMENT_EMAIL_SECRET: '  abcdefghijklmnop  ' }), []);
    assert.equal(announcementWarnings({ ...base, NODE_ENV: 'production', ANNOUNCEMENT_EMAIL_SECRET: '  abcdefghijklmno  ' }).length, 1);
  });
});

describe('F5 SERVER_SKIP_START production\'da yok sayılır', () => {
  it('resolveServerStart: değişken yoksa / 1 değilse başlat; 1 ve production dışında atla; production\'da YOK SAY + yüksek sesli hata mesajı', () => {
    assert.deepEqual(resolveServerStart({}), { skip: false, error: null });
    assert.deepEqual(resolveServerStart({ SERVER_SKIP_START: '0' }), { skip: false, error: null });
    assert.deepEqual(resolveServerStart({ SERVER_SKIP_START: 'true' }), { skip: false, error: null }, 'yalnız tam "1"');
    assert.deepEqual(resolveServerStart({ SERVER_SKIP_START: '1', NODE_ENV: 'test' }), { skip: true, error: null });
    assert.deepEqual(resolveServerStart({ SERVER_SKIP_START: ' 1 ' }), { skip: true, error: null });
    const production = resolveServerStart({ SERVER_SKIP_START: '1', NODE_ENV: 'production' });
    assert.equal(production.skip, false);
    assert.match(production.error, /SERVER_SKIP_START=1 production ortaminda YOK SAYILDI/);
    assert.match(production.error, /\.env/);
    assert.equal(resolveServerStart({ SERVER_SKIP_START: '1', NODE_ENV: ' production ' }).skip, false);
    assert.deepEqual(resolveServerStart({ NODE_ENV: 'production' }), { skip: false, error: null }, 'istenmemişse üretimde sessiz');
  });

  it('server.js karar fonksiyonunu kullanır ve hatayı console.error ile yüksek sesle loglar (kaynak)', () => {
    const source = fs.readFileSync(new URL('../src/server.js', import.meta.url), 'utf8');
    assert.match(source, /import \{ resolveServerStart, validateEnv \} from '\.\/config\/env\.js';/);
    assert.match(source, /const startDecision = resolveServerStart\(process\.env\);/);
    assert.match(source, /if \(startDecision\.error\) \{\s*(?:\/\/[^\n]*\n\s*)?console\.error\(`\[ENV\] HATA: \$\{startDecision\.error\}`\);/);
    assert.match(source, /if \(!startDecision\.skip\) \{\s*startServer\(\);/);
    assert.doesNotMatch(source, /process\.env\.SERVER_SKIP_START/, 'karar tek yerde (resolveServerStart)');
  });

  it('GERÇEK server.js alt sürecinde: NODE_ENV=production + SERVER_SKIP_START=1 -> sunucu BAŞLATILMAYA çalışılır (yok sayıldı, stderr\'de ENV HATA) ve DB yokken kapanır (çıkış 1); NODE_ENV=test ile gerçekten atlanır', () => {
    const run = (nodeEnv) =>
      spawnSync(
        process.execPath,
        ['--input-type=module', '-e', `await import(${JSON.stringify(serverUrl)}); setTimeout(() => process.exit(0), 2500);`],
        {
          cwd: path.join(here, '..'),
          env: { ...process.env, NODE_ENV: nodeEnv, SERVER_SKIP_START: '1', JWT_SECRET: 'unit-test-secret-0123456789abcdef-env-child', DB_HOST: '127.0.0.1', DB_PORT: '1', DB_USER: 'x', DB_PASSWORD: 'x', DB_NAME: 'x', PORT: '0' },
          encoding: 'utf8',
          timeout: 30000,
        },
      );
    const production = run('production');
    assert.match(String(production.stderr), /\[ENV\] HATA: SERVER_SKIP_START=1 production ortaminda YOK SAYILDI/);
    assert.equal(production.status, 1, `production: sunucu başlatılmaya çalışıldı (DB yok -> çıkış 1): ${String(production.stderr).slice(0, 300)}`);
    assert.match(String(production.stderr), /Server startup failed|Gecersiz yapilandirma/);
    const test = run('test');
    assert.doesNotMatch(String(test.stderr), /SERVER_SKIP_START/);
    assert.equal(test.status, 0, 'test ortamında başlatma atlanır (DB bağlantısı denenmez)');
  });
});

describe('validateEnv: ANNOUNCEMENT_INBOX_RETENTION_DAYS', () => {
  const retentionWarnings = (value) =>
    validateEnv({ ...base, ...(value === undefined ? {} : { ANNOUNCEMENT_INBOX_RETENTION_DAYS: value }) }).warnings.filter((warning) => /ANNOUNCEMENT_INBOX_RETENTION_DAYS/.test(warning));

  it('tanımsız, 0 ve makul sayılar için uyarı yok; geçersiz değer (sınırsız olur) ve 3650 üstü UYARILIR', () => {
    for (const ok of [undefined, '0', '90', '3650']) assert.deepEqual(retentionWarnings(ok), [], String(ok));
    for (const bad of ['abc', '-1', '1.5']) {
      const warnings = retentionWarnings(bad);
      assert.equal(warnings.length, 1, bad);
      assert.match(warnings[0], /SINIRSIZ/);
    }
    assert.match(retentionWarnings('5000')[0], /3650/);
  });
});
