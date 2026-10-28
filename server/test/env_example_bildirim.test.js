import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { getSmsProvider, isSmsEnabled } from '../src/modules/sms_provider.js';
import { hashCode } from '../src/modules/sms_login.js';
import { webPushConfig } from '../src/modules/web_push.js';

// server/.env.example ile kodun okudugu SMS girisi / tarayici bildirimi ayarlari ayni adlarla eslesmeli
// (P1-17: kod okuyordu ama ornek dosyada yoktu). Satir sonu CRLF olabilir (Windows checkout), bu yuzden degerler trim edilir.
const readText = (relativeUrl) => readFileSync(new URL(relativeUrl, import.meta.url), 'utf8');
const example = readText('../.env.example');
const sources = ['sms_provider.js', 'sms_login.js', 'web_push.js'].map((file) => readText(`../src/modules/${file}`)).join('\n');

const SMS_NAMES = ['SMS_PROVIDER', 'NETGSM_USERCODE', 'NETGSM_PASSWORD', 'NETGSM_HEADER', 'SMS_CODE_PEPPER'];
const WEB_PUSH_NAMES = ['WEB_PUSH_VAPID_PUBLIC', 'WEB_PUSH_VAPID_PRIVATE', 'WEB_PUSH_SUBJECT'];
const NAMES = [...SMS_NAMES, ...WEB_PUSH_NAMES];
// Ornek dosyada yalniz saglayici adi ve ornek iletisim adresi dolu olabilir; geri kalani (sirlar ve hesap bilgileri) BOS kalmali.
const MAY_HAVE_EXAMPLE_VALUE = new Set(['SMS_PROVIDER', 'WEB_PUSH_SUBJECT']);
// Testte gecici olarak degistirilen ortam degiskenleri (JWT_SECRET: SMS_CODE_PEPPER yokken yedek sir).
const MANAGED = [...NAMES, 'JWT_SECRET'];

/** "ADI=deger" ya da yorum satiri haline getirilmis "# ADI=deger" satirinin degeri; satir yoksa null. */
function exampleValue(name) {
  const match = new RegExp(`^#?[ \\t]*${name}=(.*)$`, 'm').exec(example);
  return match ? match[1].trim() : null;
}

/** Ornek dosyadaki degerlerle (bos olanlar dummy ile doldurularak) kurulan ortam. */
const filledEnv = () => Object.fromEntries(NAMES.map((name) => [name, exampleValue(name) || 'dolu-deger']));
const pick = (env, names) => Object.fromEntries(names.map((name) => [name, env[name]]));

/** process.env'i yalniz `values` ile kurar (MANAGED icindeki geri kalan ad silinir), sonra eski haline getirir. */
function withEnv(values, run) {
  const saved = Object.fromEntries(MANAGED.map((name) => [name, process.env[name]]));
  try {
    for (const name of MANAGED) {
      if (name in values) process.env[name] = values[name];
      else delete process.env[name];
    }
    return run();
  } finally {
    for (const [name, value] of Object.entries(saved)) {
      if (value === undefined) delete process.env[name];
      else process.env[name] = value;
    }
  }
}

test('.env.example SMS ve Web Push ayarlarinin sekiz adini listeler ve kod bu adlari okur', () => {
  assert.equal(NAMES.length, 8);
  for (const name of NAMES) {
    assert.notEqual(exampleValue(name), null, `${name} .env.example icinde yok`);
    assert.match(sources, new RegExp(`\\b${name}\\b`), `${name} kodda okunmuyor (ad degismis olabilir)`);
  }
});

test('.env.example gercek deger tasimaz: sirlar ve hesap bilgileri bos, iletisim adresi ornek alan adi', () => {
  for (const name of NAMES) {
    if (!MAY_HAVE_EXAMPLE_VALUE.has(name)) assert.equal(exampleValue(name), '', `${name} ornek dosyada bos olmali`);
  }
  assert.ok(['', 'netgsm'].includes(exampleValue('SMS_PROVIDER')));
  assert.match(exampleValue('WEB_PUSH_SUBJECT'), /^(|mailto:[^@\s]+@example\.(com|org|net)|https:\/\/([a-z0-9-]+\.)*example\.(com|org|net)(\/\S*)?)$/);
});

test('ornekteki adlar kodun okudugu adlardir: doldurulunca SMS ve tarayici bildirimi acilir, eksikse kapali kalir', () => {
  const env = filledEnv();
  assert.equal(isSmsEnabled({}), false);
  assert.equal(getSmsProvider(env)?.name, 'netgsm');
  for (const missing of ['NETGSM_USERCODE', 'NETGSM_PASSWORD', 'NETGSM_HEADER']) {
    assert.equal(isSmsEnabled({ ...env, [missing]: '' }), false, `${missing} bossa SMS kapali olmali`);
  }

  const webPush = pick(env, WEB_PUSH_NAMES);
  withEnv({}, () => assert.equal(webPushConfig().enabled, false));
  withEnv(webPush, () => assert.equal(webPushConfig().enabled, true));
  for (const missing of WEB_PUSH_NAMES) {
    withEnv({ ...webPush, [missing]: '' }, () => assert.equal(webPushConfig().enabled, false, `${missing} bossa tarayici bildirimi kapali olmali`));
  }
  withEnv({ ...webPush, WEB_PUSH_SUBJECT: 'destek@example.com' }, () => {
    assert.equal(webPushConfig().enabled, false, 'mailto: / https:// ile baslamayan iletisim adresi kabul edilmemeli');
  });
});

test('SMS_CODE_PEPPER giris kodu ozetini imzalar; tanimli degilse JWT_SECRET kullanilir', () => {
  const digest = (values) => withEnv(values, () => hashCode('+905551234567', '123456'));
  assert.equal(digest({ SMS_CODE_PEPPER: 'pepper-a' }), hashCode('+905551234567', '123456', 'pepper-a'));
  assert.notEqual(digest({ SMS_CODE_PEPPER: 'pepper-a' }), digest({ SMS_CODE_PEPPER: 'pepper-b' }));
  assert.equal(digest({ JWT_SECRET: 'jwt-gizli' }), hashCode('+905551234567', '123456', 'jwt-gizli'));
});
