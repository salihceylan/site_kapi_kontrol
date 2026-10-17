// Telefon bildirimi (Faz 3b-B): hizmet hesabı yükleyici (geçerli / bozuk / eksik alan / izin), maskeleme (toJSON / inspect / String),
// çalışma durumu (configured:false iken sunucu açılır), ortam ayarları ve validateEnv uyarıları. DB / ağ yok.
import { describe, it, afterEach } from 'node:test';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import util from 'node:util';
import jwt from 'jsonwebtoken';
import {
  MAX_SERVICE_ACCOUNT_BYTES,
  ServiceAccountError,
  isPushAvailable,
  loadPushRuntime,
  loadServiceAccountFile,
  parseServiceAccount,
  pushRuntime,
  setPushRuntimeForTests,
} from '../src/modules/push_credentials.js';
import {
  DEFAULT_MAX_PER_DAY_PER_USER,
  DEFAULT_URGENT_MAX_PER_DAY_PER_SITE,
  isPushEnabled,
  pushEnvWarnings,
  pushMaxPerDay,
  pushUrgentMaxPerDayPerSite,
  serviceAccountFile,
} from '../src/modules/push_config.js';
import { validateEnv } from '../src/config/env.js';
import { TEST_CLIENT_EMAIL, TEST_PROJECT_ID, privateKeyFragment, serviceAccountJson, testKeyPair } from './fixtures/push_fixtures.js';

const tmpFiles = [];
function tmpJson(content, name = 'sa.json') {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'push-sa-'));
  const file = path.join(dir, name);
  fs.writeFileSync(file, typeof content === 'string' ? content : JSON.stringify(content));
  tmpFiles.push(dir);
  return file;
}

afterEach(() => {
  setPushRuntimeForTests(null);
  for (const dir of tmpFiles.splice(0)) fs.rmSync(dir, { recursive: true, force: true });
});

const rejectsWith = (fn, code) => assert.throws(fn, (error) => error instanceof ServiceAccountError && error.code === code);

describe('hizmet hesabı ayrıştırma ve doğrulama', () => {
  it('geçerli JSON: project_id açık, imzalı JWT iddiası (RS256, iss = client_email, scope, aud, exp <= 1 saat, kid)', () => {
    const account = parseServiceAccount(JSON.stringify(serviceAccountJson()));
    assert.equal(account.projectId, TEST_PROJECT_ID);
    const now = 1_800_000_000;
    const token = account.signAssertion({ audience: 'https://oauth2.example/token', scope: 'https://www.googleapis.com/auth/firebase.messaging', nowSeconds: now });
    const decoded = jwt.verify(token, testKeyPair().publicKey, { algorithms: ['RS256'], clockTimestamp: now + 5, complete: true });
    assert.equal(decoded.header.alg, 'RS256');
    assert.equal(decoded.header.kid, 'a1b2c3d4e5f60718293a4b5c6d7e8f9012345678');
    assert.equal(decoded.payload.iss, TEST_CLIENT_EMAIL);
    assert.equal(decoded.payload.aud, 'https://oauth2.example/token');
    assert.equal(decoded.payload.scope, 'https://www.googleapis.com/auth/firebase.messaging');
    assert.equal(decoded.payload.iat, now);
    assert.ok(decoded.payload.exp - decoded.payload.iat <= 3600);
    const capped = jwt.decode(account.signAssertion({ audience: 'a', scope: 's', nowSeconds: now, lifetimeSeconds: 99999 }));
    assert.equal(capped.exp - capped.iat, 3600, 'ömür 1 saati aşamaz');
  });

  it('bozuk JSON / dizi / yanlış tür / eksik ya da geçersiz alanlar -> yalnız KOD (içerik / dosya parçası yok)', () => {
    rejectsWith(() => parseServiceAccount('{bozuk "private_key": "-----BEGIN PRIVATE KEY-----gizli'), 'INVALID_JSON');
    rejectsWith(() => parseServiceAccount('[1,2]'), 'INVALID_JSON');
    rejectsWith(() => parseServiceAccount(''), 'INVALID_JSON');
    rejectsWith(() => parseServiceAccount(JSON.stringify(serviceAccountJson({ type: 'authorized_user' }))), 'INVALID_TYPE');
    rejectsWith(() => parseServiceAccount(JSON.stringify(serviceAccountJson({ project_id: undefined }))), 'INVALID_PROJECT_ID');
    rejectsWith(() => parseServiceAccount(JSON.stringify(serviceAccountJson({ project_id: 'A B' }))), 'INVALID_PROJECT_ID');
    rejectsWith(() => parseServiceAccount(JSON.stringify(serviceAccountJson({ client_email: 'eposta-degil' }))), 'INVALID_CLIENT_EMAIL');
    rejectsWith(() => parseServiceAccount(JSON.stringify(serviceAccountJson({ private_key: undefined }))), 'INVALID_PRIVATE_KEY');
    rejectsWith(() => parseServiceAccount(JSON.stringify(serviceAccountJson({ private_key: '-----BEGIN PRIVATE KEY-----\nAAAA\n-----END PRIVATE KEY-----\n' }))), 'INVALID_PRIVATE_KEY');
    const ec = crypto.generateKeyPairSync('ec', { namedCurve: 'P-256', privateKeyEncoding: { type: 'pkcs8', format: 'pem' }, publicKeyEncoding: { type: 'spki', format: 'pem' } });
    rejectsWith(() => parseServiceAccount(JSON.stringify(serviceAccountJson({ private_key: ec.privateKey }))), 'INVALID_PRIVATE_KEY');
    try {
      parseServiceAccount('{"private_key": "-----BEGIN PRIVATE KEY-----GIZLIPARCA" bozuk');
    } catch (error) {
      assert.doesNotMatch(String(error.message) + String(error.stack), /GIZLIPARCA|BEGIN PRIVATE/);
    }
  });

  it('maskeleme: JSON.stringify / util.inspect / String / Object.keys özel anahtarı ve client_email\'i GÖSTERMEZ; nesne dondurulmuş', () => {
    const account = parseServiceAccount(JSON.stringify(serviceAccountJson()));
    const outputs = [JSON.stringify(account), util.inspect(account, { depth: 10, showHidden: true }), String(account), `${account}`, Object.keys(account).join(','), JSON.stringify({ wrapper: account })];
    for (const text of outputs) {
      assert.ok(!text.includes(privateKeyFragment()), text.slice(0, 120));
      assert.ok(!text.includes(TEST_CLIENT_EMAIL), text.slice(0, 120));
      assert.ok(!text.includes('BEGIN PRIVATE KEY'));
    }
    assert.match(JSON.stringify(account), /siteyonetim-test1/);
    assert.ok(Object.isFrozen(account));
    assert.throws(() => {
      account.projectId = 'baska';
    }, TypeError);
  });
});

describe('dosya yükleyici ve çalışma durumu', () => {
  it('dosya okunamaz -> FILE_<kod>; çok büyük -> TOO_LARGE; geçerli dosya yüklenir', () => {
    rejectsWith(() => loadServiceAccountFile(path.join(os.tmpdir(), 'yok-boyle-bir-dosya-push.json')), 'FILE_ENOENT');
    rejectsWith(() => loadServiceAccountFile(tmpJson('x'.repeat(MAX_SERVICE_ACCOUNT_BYTES + 1))), 'TOO_LARGE');
    const account = loadServiceAccountFile(tmpJson(serviceAccountJson()));
    assert.equal(account.projectId, TEST_PROJECT_ID);
  });

  it('loadPushRuntime: PUSH_ENABLED kapalı ama dosya geçerliyse configured:true / available:false; açık + geçerli -> available', () => {
    const file = tmpJson(serviceAccountJson());
    let state = loadPushRuntime({ FCM_SERVICE_ACCOUNT_FILE: file });
    assert.deepEqual([state.enabled, state.configured, state.error], [false, true, null]);
    assert.equal(isPushAvailable(), false);
    state = loadPushRuntime({ FCM_SERVICE_ACCOUNT_FILE: file, PUSH_ENABLED: '1' });
    assert.deepEqual([state.enabled, state.configured], [true, true]);
    assert.equal(isPushAvailable(), true);
    assert.equal(pushRuntime(), state);
  });

  it('dosya yok / bozuk / tanımsız -> configured:false (sunucu AÇILIR: hata fırlatmaz), hata yalnız kod', () => {
    assert.deepEqual(
      [loadPushRuntime({ PUSH_ENABLED: '1' }).configured, pushRuntime().error, isPushAvailable()],
      [false, 'NOT_SET', false],
    );
    const broken = loadPushRuntime({ PUSH_ENABLED: '1', FCM_SERVICE_ACCOUNT_FILE: tmpJson('{bozuk') });
    assert.deepEqual([broken.configured, broken.error], [false, 'INVALID_JSON']);
    const missing = loadPushRuntime({ PUSH_ENABLED: '1', FCM_SERVICE_ACCOUNT_FILE: path.join(os.tmpdir(), 'yok-push-sa.json') });
    assert.deepEqual([missing.configured, missing.error], [false, 'FILE_ENOENT']);
    assert.equal(isPushAvailable(), false);
  });

  it('özel anahtar process.env\'e GİRMEZ (yalnız yol); çalışma durumu JSON / inspect çıktısında sır yok', () => {
    const file = tmpJson(serviceAccountJson());
    const env = { FCM_SERVICE_ACCOUNT_FILE: file, PUSH_ENABLED: '1' };
    const state = loadPushRuntime(env);
    assert.deepEqual(Object.keys(env).sort(), ['FCM_SERVICE_ACCOUNT_FILE', 'PUSH_ENABLED']);
    for (const value of Object.values(process.env)) {
      assert.ok(!String(value).includes(privateKeyFragment()));
    }
    for (const text of [JSON.stringify(state), util.inspect(state, { depth: 10 })]) {
      assert.ok(!text.includes(privateKeyFragment()));
      assert.ok(!text.includes(TEST_CLIENT_EMAIL));
    }
  });
});

describe('ortam ayarları ve açılış uyarıları (B6)', () => {
  it('PUSH_ENABLED yalnız açıkça 1/true/yes/on; PUSH_MAX_PER_DAY_PER_USER 1-1000 yoksa 8; FCM_SERVICE_ACCOUNT_FILE kırpılır', () => {
    for (const value of ['1', 'true', 'YES', ' on ']) assert.equal(isPushEnabled({ PUSH_ENABLED: value }), true, value);
    for (const value of [undefined, '', '0', 'false', 'evet', '2']) assert.equal(isPushEnabled({ PUSH_ENABLED: value }), false, String(value));
    assert.equal(pushMaxPerDay({}), DEFAULT_MAX_PER_DAY_PER_USER);
    assert.equal(DEFAULT_MAX_PER_DAY_PER_USER, 8);
    assert.equal(pushMaxPerDay({ PUSH_MAX_PER_DAY_PER_USER: '12' }), 12);
    for (const value of ['0', '-1', 'abc', '1001', '2.5']) assert.equal(pushMaxPerDay({ PUSH_MAX_PER_DAY_PER_USER: value }), 8, value);
    assert.equal(serviceAccountFile({ FCM_SERVICE_ACCOUNT_FILE: '  /etc/kapi/fcm.json ' }), '/etc/kapi/fcm.json');
    assert.equal(serviceAccountFile({}), null);
  });

  it('uyarılar: açık ama dosya yok; geçersiz değerler; dosya depo içinde; POSIX izinleri açık (mode & 077); okunamıyor. Dosya içeriği / yol yazdırılmaz', () => {
    // dosya (.json) ve bulunduğu dizin ayrı stat döner; dizin varsayılanı 0700
    const fakeFs = (mode, dirMode = 0o040700) => ({
      statSync: (p) => (String(p).endsWith('.json') ? { isFile: () => true, mode } : { isFile: () => false, isDirectory: () => true, mode: dirMode }),
    });
    const repoRoot = path.resolve('/srv/repo');
    assert.deepEqual(pushEnvWarnings({}, { fsImpl: fakeFs(0o100600), repoRoot, platform: 'linux' }), []);
    assert.match(pushEnvWarnings({ PUSH_ENABLED: '1' }, { repoRoot }).join('\n'), /FCM_SERVICE_ACCOUNT_FILE tanimli degil/);
    assert.match(pushEnvWarnings({ PUSH_ENABLED: 'belki' }, { repoRoot }).join('\n'), /PUSH_ENABLED gecersiz/);
    assert.match(pushEnvWarnings({ PUSH_MAX_PER_DAY_PER_USER: 'x' }, { repoRoot }).join('\n'), /PUSH_MAX_PER_DAY_PER_USER gecersiz/);
    assert.deepEqual(pushEnvWarnings({ PUSH_MAX_PER_DAY_PER_USER: '08' }, { repoRoot }), []);

    const inside = pushEnvWarnings({ FCM_SERVICE_ACCOUNT_FILE: '/srv/repo/server/fcm.json' }, { fsImpl: fakeFs(0o100600), repoRoot, platform: 'linux', cwd: '/' });
    assert.equal(inside.length, 1);
    assert.match(inside[0], /depo .*icinde/);
    const relative = pushEnvWarnings({ FCM_SERVICE_ACCOUNT_FILE: 'fcm.json' }, { fsImpl: fakeFs(0o100600), repoRoot, platform: 'linux', cwd: '/srv/repo/server' });
    assert.match(relative.join('\n'), /depo .*icinde/, 'göreli yol çalışma dizinine göre çözülür');
    assert.deepEqual(pushEnvWarnings({ FCM_SERVICE_ACCOUNT_FILE: '/etc/kapi/fcm.json' }, { fsImpl: fakeFs(0o100600), repoRoot, platform: 'linux' }), []);

    const open = pushEnvWarnings({ FCM_SERVICE_ACCOUNT_FILE: '/etc/kapi/fcm.json' }, { fsImpl: fakeFs(0o100644), repoRoot, platform: 'linux' });
    assert.equal(open.length, 1);
    assert.match(open[0], /izinleri cok acik \(644\).*chmod 600/);
    assert.match(pushEnvWarnings({ FCM_SERVICE_ACCOUNT_FILE: '/etc/kapi/fcm.json' }, { fsImpl: fakeFs(0o100640), repoRoot, platform: 'linux' }).join(''), /640/);
    assert.deepEqual(pushEnvWarnings({ FCM_SERVICE_ACCOUNT_FILE: 'C:/kapi/fcm.json' }, { fsImpl: fakeFs(0o100666), repoRoot, platform: 'win32' }), [], 'Windows\'ta mod denetimi yok');

    const failing = { statSync: () => { throw Object.assign(new Error('ENOENT: /etc/kapi/fcm.json'), { code: 'ENOENT' }); } };
    const unreadable = pushEnvWarnings({ FCM_SERVICE_ACCOUNT_FILE: '/etc/kapi/fcm.json' }, { fsImpl: failing, repoRoot, platform: 'linux' });
    assert.match(unreadable[0], /okunamiyor \(ENOENT\)/);
    for (const text of [...inside, ...open, ...unreadable]) assert.ok(!text.includes('/etc/kapi/fcm.json') && !text.includes('/srv/repo'), 'yapılandırılan yol yazdırılmaz');
  });

  it('inceleme: dizin izni uyarısı (diğerlerine açık ya da grupça yazılabilir dizin); 0700 / 0750 sessiz; Windows\'ta yok', () => {
    const repoRoot = path.resolve('/srv/repo');
    const fakeFs = (dirMode) => ({
      statSync: (p) => (String(p).endsWith('.json') ? { isFile: () => true, mode: 0o100600 } : { isFile: () => false, mode: dirMode }),
    });
    const env = { FCM_SERVICE_ACCOUNT_FILE: '/etc/kapi/fcm.json' };
    for (const dirMode of [0o040700, 0o040750]) assert.deepEqual(pushEnvWarnings(env, { fsImpl: fakeFs(dirMode), repoRoot, platform: 'linux' }), [], dirMode.toString(8));
    for (const dirMode of [0o040755, 0o040777, 0o040770, 0o040701]) {
      const warnings = pushEnvWarnings(env, { fsImpl: fakeFs(dirMode), repoRoot, platform: 'linux' });
      assert.equal(warnings.length, 1, dirMode.toString(8));
      assert.match(warnings[0], /dizininin izinleri cok acik/);
      assert.ok(!warnings[0].includes('/etc/kapi'));
    }
    assert.deepEqual(pushEnvWarnings(env, { fsImpl: fakeFs(0o040777), repoRoot, platform: 'win32' }), []);
  });

  it('inceleme: PUSH_URGENT_MAX_PER_DAY_PER_SITE (1-1000, varsayılan 3) + geçersiz değer uyarısı', () => {
    assert.equal(pushUrgentMaxPerDayPerSite({}), 3);
    assert.equal(DEFAULT_URGENT_MAX_PER_DAY_PER_SITE, 3);
    assert.equal(pushUrgentMaxPerDayPerSite({ PUSH_URGENT_MAX_PER_DAY_PER_SITE: '5' }), 5);
    for (const value of ['0', 'x', '1001']) assert.equal(pushUrgentMaxPerDayPerSite({ PUSH_URGENT_MAX_PER_DAY_PER_SITE: value }), 3, value);
    assert.match(pushEnvWarnings({ PUSH_URGENT_MAX_PER_DAY_PER_SITE: 'cok' }, { repoRoot: path.resolve('/srv/repo') }).join('\n'), /PUSH_URGENT_MAX_PER_DAY_PER_SITE gecersiz/);
  });

  it('inceleme: hizmet hesabı dosyasının boyutu / türü OKUMADAN ÖNCE denetlenir (dev dosya belleğe alınmaz)', () => {
    let reads = 0;
    const readFileSync = () => {
      reads += 1;
      return Buffer.from(JSON.stringify(serviceAccountJson()));
    };
    rejectsWith(() => loadServiceAccountFile('/x/sa.json', { statSync: () => ({ isFile: () => true, size: 10 * 1024 * 1024 * 1024 }), readFileSync }), 'TOO_LARGE');
    rejectsWith(() => loadServiceAccountFile('/x/sa.json', { statSync: () => ({ isFile: () => false, size: 0 }), readFileSync }), 'NOT_A_FILE');
    assert.equal(reads, 0, 'okuma yapılmadı');
    assert.equal(loadServiceAccountFile('/x/sa.json', { statSync: () => ({ isFile: () => true, size: 2000 }), readFileSync }).projectId, TEST_PROJECT_ID);
    assert.equal(reads, 1);
  });

  it('validateEnv push uyarılarını ekler; push değişkenleri yokken ek uyarı yok (sunucu yine başlar: errors boş kalır)', () => {
    const base = { JWT_SECRET: 'x'.repeat(64), NODE_ENV: 'production', LISTEN_HOST: '127.0.0.1' };
    const without = validateEnv(base);
    const withPush = validateEnv({ ...base, PUSH_ENABLED: '1' });
    assert.deepEqual(withPush.errors, without.errors);
    assert.equal(withPush.warnings.length, without.warnings.length + 1);
    assert.ok(withPush.warnings.some((warning) => /FCM_SERVICE_ACCOUNT_FILE tanimli degil/.test(warning)));
    assert.ok(!without.warnings.some((warning) => /PUSH|FCM/.test(warning)));
  });
});
