// Telefon bildirimi (Faz 3b-B): FCM HTTP v1 istemcisi — erişim jetonu (JWT-bearer, önbellek, süresine 5 dk kala tek-uçuş yenileme), gönderim ve
// hata eşleme tablosunun HER satırı. Sahte oauth2 + FCM sunucusu (node:http), crypto.generateKeyPairSync RSA anahtarı. Gerçek Google'a bağlanılmaz.
import { describe, it, before, after, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import jwt from 'jsonwebtoken';
import { parseServiceAccount } from '../src/modules/push_credentials.js';
import {
  FCM_SCOPE,
  TOKEN_REFRESH_MARGIN_MS,
  classifyFcmError,
  createFcmClient,
  parseRetryAfter,
} from '../src/modules/push_fcm.js';
import { TEST_CLIENT_EMAIL, TEST_PROJECT_ID, fcmError, serviceAccountJson, startFakeGoogle, testKeyPair } from './fixtures/push_fixtures.js';

let google;
let account;
let clock;
let hooks;

before(async () => {
  google = await startFakeGoogle();
  account = parseServiceAccount(JSON.stringify(serviceAccountJson()));
});

after(async () => {
  await google.close();
});

beforeEach(() => {
  google.state.token = null;
  google.state.send = null;
  google.state.tokenRequests.length = 0;
  google.state.sendRequests.length = 0;
  google.state.tokenCount = 0;
  google.state.sendCount = 0;
  google.state.delayMs = 0;
  clock = 1_800_000_000_000;
  hooks = { tokenUrl: google.tokenUrl, apiBase: google.apiBase, fetch: (url, init) => fetch(url, init), now: () => clock, timeoutMs: 2000 };
});

const message = (token = 'fcm-kayit-jetonu-0123456789-abcdef') => ({ token, notification: { title: 'T', body: 'B' }, data: { type: 'announcement' } });

describe('erişim jetonu', () => {
  it('JWT-bearer: grant_type + RS256 iddia (iss = client_email, scope = firebase.messaging, aud = token ucu, exp <= 1 saat)', async () => {
    const client = createFcmClient(account, hooks);
    const result = await client.send(message());
    assert.equal(result.kind, 'ok');
    assert.equal(google.state.tokenRequests.length, 1);
    const { body, headers } = google.state.tokenRequests[0];
    assert.equal(body.grant_type, 'urn:ietf:params:oauth:grant-type:jwt-bearer');
    assert.match(headers['content-type'], /application\/x-www-form-urlencoded/);
    const claims = jwt.verify(body.assertion, testKeyPair().publicKey, { algorithms: ['RS256'], clockTimestamp: clock / 1000 + 1 });
    assert.equal(claims.iss, TEST_CLIENT_EMAIL);
    assert.equal(claims.scope, FCM_SCOPE);
    assert.equal(claims.aud, google.tokenUrl);
    assert.ok(claims.exp - claims.iat <= 3600);
    const sent = google.state.sendRequests[0];
    assert.equal(sent.project, TEST_PROJECT_ID);
    assert.equal(sent.headers.authorization, `Bearer ${google.state.accessToken}-1`);
    assert.deepEqual(sent.body, { message: message() });
  });

  it('önbellek: ~55 dk boyunca TEK jeton isteği; süresine 5 dk kala yenilenir', async () => {
    const client = createFcmClient(account, hooks);
    for (let i = 0; i < 5; i += 1) assert.equal((await client.send(message())).kind, 'ok');
    assert.equal(google.state.tokenCount, 1);
    clock += 3599 * 1000 - TOKEN_REFRESH_MARGIN_MS - 1000; // 5 dk + 1 sn kala: hâlâ önbellekte
    await client.send(message());
    assert.equal(google.state.tokenCount, 1);
    clock += 2000; // 5 dk'dan az kaldı: yenilenir
    await client.send(message());
    assert.equal(google.state.tokenCount, 2);
    assert.equal(google.state.sendRequests.at(-1).headers.authorization, `Bearer ${google.state.accessToken}-2`);
  });

  it('tek-uçuş: eşzamanlı 20 gönderim TEK jeton isteği bekler', async () => {
    google.state.delayMs = 50;
    const client = createFcmClient(account, hooks);
    const results = await Promise.all(Array.from({ length: 20 }, (_, i) => client.send(message(`fcm-kayit-jetonu-eszamanli-${i}-xyz`))));
    assert.ok(results.every((r) => r.kind === 'ok'));
    assert.equal(google.state.tokenCount, 1);
  });

  it('jeton ucu hatası -> kind auth, kod yalnız HTTP + Google kısa kodu (açıklama / gövde yok); FCM\'e istek gitmez', async () => {
    google.state.token = () => ({ status: 400, json: { error: 'invalid_grant', error_description: 'Gizli aciklama: hesap silinmis GIZLI' } });
    const client = createFcmClient(account, hooks);
    const result = await client.send(message());
    assert.deepEqual([result.kind, result.code, result.httpStatus], ['auth', 'TOKEN_400_INVALID_GRANT', 400]);
    assert.equal(google.state.sendCount, 0);
    assert.doesNotMatch(JSON.stringify(result), /GIZLI|aciklama/);
  });

  it('jeton yanıtında access_token yoksa TOKEN_EMPTY; ağ hatası NETWORK', async () => {
    google.state.token = () => ({ status: 200, json: { expires_in: 3600 } });
    assert.equal((await createFcmClient(account, hooks).send(message())).code, 'TOKEN_EMPTY');
    const offline = createFcmClient(account, { ...hooks, tokenUrl: 'http://127.0.0.1:1/token' });
    assert.deepEqual([(await offline.send(message())).kind, (await offline.send(message())).code], ['auth', 'NETWORK']);
  });
});

describe('gönderim ve hata eşleme (B5 tablosu)', () => {
  const invalidTokenDetails = [{ '@type': 'type.googleapis.com/google.rpc.BadRequest', fieldViolations: [{ field: 'message.token', description: 'Invalid registration token' }] }];
  const table = [
    ['200 kabul', { status: 200, json: { name: 'projects/x/messages/1' } }, 'ok', null],
    ['404 UNREGISTERED', { status: 404, json: fcmError(404, 'NOT_FOUND', 'UNREGISTERED') }, 'dead', 'UNREGISTERED'],
    ['404 NOT_FOUND durumlu (errorCode yok)', { status: 404, json: { error: { code: 404, status: 'NOT_FOUND' } } }, 'dead', 'UNREGISTERED'],
    // inceleme: gövdesiz / kodsuz çıplak 404 (yanlış URL, vekil sunucu) cihaz SİLDİRMEZ
    ['404 gövdesiz (çıplak)', { status: 404, raw: '' }, 'invalid', 'HTTP_404'],
    ['404 kodsuz JSON', { status: 404, json: {} }, 'invalid', 'HTTP_404'],
    ['404 HTML', { status: 404, raw: '<html>Not Found</html>' }, 'invalid', 'HTTP_404'],
    ['400 INVALID_ARGUMENT (message.token)', { status: 400, json: fcmError(400, 'INVALID_ARGUMENT', 'INVALID_ARGUMENT', invalidTokenDetails) }, 'dead', 'INVALID_TOKEN'],
    ['403 SENDER_ID_MISMATCH', { status: 403, json: fcmError(403, 'PERMISSION_DENIED', 'SENDER_ID_MISMATCH') }, 'dead', 'SENDER_ID_MISMATCH'],
    ['401 THIRD_PARTY_AUTH_ERROR (APNs)', { status: 401, json: fcmError(401, 'UNAUTHENTICATED', 'THIRD_PARTY_AUTH_ERROR') }, 'apns_auth', 'APNS_AUTH'],
    ['429 QUOTA_EXCEEDED', { status: 429, json: fcmError(429, 'RESOURCE_EXHAUSTED', 'QUOTA_EXCEEDED'), headers: { 'retry-after': '120' } }, 'transient', 'QUOTA_EXCEEDED'],
    ['500 INTERNAL', { status: 500, json: fcmError(500, 'INTERNAL', 'INTERNAL') }, 'transient', 'INTERNAL'],
    ['503 UNAVAILABLE', { status: 503, json: fcmError(503, 'UNAVAILABLE', 'UNAVAILABLE') }, 'transient', 'UNAVAILABLE'],
    ['400 INVALID_ARGUMENT (mesaj alanı)', { status: 400, json: fcmError(400, 'INVALID_ARGUMENT', 'INVALID_ARGUMENT', [{ fieldViolations: [{ field: 'message.android.ttl' }] }]) }, 'invalid', 'INVALID_ARGUMENT'],
    ['413 diğer 4xx', { status: 413, raw: '<html>gizli</html>' }, 'invalid', 'HTTP_413'],
  ];
  for (const [name, answer, kind, code] of table) {
    it(`${name} -> ${kind}`, async () => {
      google.state.send = () => answer;
      const result = await createFcmClient(account, hooks).send(message());
      assert.equal(result.kind, kind);
      assert.equal(result.code, code);
      if (answer.headers?.['retry-after']) assert.equal(result.retryAfterSeconds, 120);
      assert.doesNotMatch(JSON.stringify(result), /Gizli|gizli/, 'yanıt metni taşınmaz');
    });
  }

  it('401 UNAUTHENTICATED / 403 PERMISSION_DENIED: erişim jetonu BİR KEZ yenilenir ve tek kez yeniden denenir; ikinci denemede başarı -> ok', async () => {
    google.state.send = ({ count }) => (count === 1 ? { status: 401, json: fcmError(401, 'UNAUTHENTICATED') } : { status: 200, json: {} });
    const client = createFcmClient(account, hooks);
    const result = await client.send(message());
    assert.equal(result.kind, 'ok');
    assert.equal(google.state.tokenCount, 2, 'jeton yenilendi');
    assert.equal(google.state.sendCount, 2);
    assert.equal(google.state.sendRequests[1].headers.authorization, `Bearer ${google.state.accessToken}-2`);
  });

  it('kimlik hatası sürerse auth döner (sonsuz döngü yok: en çok 2 gönderim, 2 jeton isteği)', async () => {
    google.state.send = () => ({ status: 403, json: fcmError(403, 'PERMISSION_DENIED') });
    const result = await createFcmClient(account, hooks).send(message());
    assert.deepEqual([result.kind, result.code], ['auth', 'PERMISSION_DENIED']);
    assert.equal(google.state.sendCount, 2);
    assert.equal(google.state.tokenCount, 2);
  });

  it('eşzamanlı 401\'ler tek yenileme paylaşır (tek-uçuş)', async () => {
    const client = createFcmClient(account, hooks);
    await client.send(message());
    google.state.send = ({ headers }) => (headers.authorization.endsWith('-1') ? { status: 401, json: fcmError(401, 'UNAUTHENTICATED') } : { status: 200, json: {} });
    google.state.delayMs = 20;
    const results = await Promise.all(Array.from({ length: 10 }, (_, i) => client.send(message(`fcm-kayit-jetonu-yenileme-${i}-xyz`))));
    assert.ok(results.every((r) => r.kind === 'ok'));
    assert.equal(google.state.tokenCount, 2);
  });

  it('yönlendirme İZLENMEZ (redirect: error): oauth ve FCM isteklerinde; 3xx yanıtı jeton / iddia başka adrese taşımaz', async () => {
    const inits = [];
    const spyHooks = { ...hooks, fetch: (url, init) => { inits.push(init); return fetch(url, init); } };
    const client = createFcmClient(account, spyHooks);
    assert.equal((await client.send(message())).kind, 'ok');
    assert.equal(inits.length, 2);
    assert.ok(inits.every((init) => init.redirect === 'error'));
    google.state.send = () => ({ status: 302, headers: { location: 'http://127.0.0.1:1/baska' }, raw: '' });
    const redirected = await client.send(message());
    assert.deepEqual([redirected.kind, redirected.code], ['transient', 'NETWORK'], 'yönlendirme ağ hatası sayılır, izlenmez');
  });

  it('zaman aşımı (AbortSignal.timeout) -> transient TIMEOUT', async () => {
    const client = createFcmClient(account, { ...hooks, timeoutMs: 150 });
    await client.getAccessToken();
    google.state.send = () => 'hang';
    const result = await client.send(message());
    assert.deepEqual([result.kind, result.code, result.httpStatus], ['transient', 'TIMEOUT', null]);
  });

  it('classifyFcmError ve Retry-After yardımcıları', () => {
    assert.equal(classifyFcmError(502, null).kind, 'transient');
    assert.equal(classifyFcmError(418, { error: 'metin' }).code, 'HTTP_418');
    assert.equal(parseRetryAfter('30', 0), 30);
    assert.equal(parseRetryAfter('999999', 0), 3600);
    assert.equal(parseRetryAfter(new Date(60_000).toUTCString(), 0), 60);
    assert.equal(parseRetryAfter('yarin', 0), null);
    assert.equal(parseRetryAfter(null, 0), null);
  });
});
