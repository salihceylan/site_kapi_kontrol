// Telefon bildirimi (Faz 3b-B) testleri için ortak yardımcılar: sahte hizmet hesabı (crypto.generateKeyPairSync RSA anahtarı) ve sahte
// OAuth2 + FCM HTTP v1 sunucusu (node:http). Gerçek Google'a / Firebase'e ASLA bağlanılmaz. Bu dosya test içermez.
import crypto from 'node:crypto';
import http from 'node:http';

let cachedKeys = null;

/** 2048 bit RSA anahtar çifti (süreç başına bir kez üretilir). */
export function testKeyPair() {
  if (!cachedKeys) {
    cachedKeys = crypto.generateKeyPairSync('rsa', {
      modulusLength: 2048,
      publicKeyEncoding: { type: 'spki', format: 'pem' },
      privateKeyEncoding: { type: 'pkcs8', format: 'pem' },
    });
  }
  return cachedKeys;
}

export const TEST_PROJECT_ID = 'siteyonetim-test1';
export const TEST_CLIENT_EMAIL = 'fcm-gonderici-gizli@siteyonetim-test1.iam.gserviceaccount.com';

/** Google konsolunun ürettiğine benzer hizmet hesabı JSON nesnesi. */
export function serviceAccountJson(overrides = {}) {
  return {
    type: 'service_account',
    project_id: TEST_PROJECT_ID,
    private_key_id: 'a1b2c3d4e5f60718293a4b5c6d7e8f9012345678',
    private_key: testKeyPair().privateKey,
    client_email: TEST_CLIENT_EMAIL,
    client_id: '123456789012345678901',
    auth_uri: 'https://accounts.google.com/o/oauth2/auth',
    token_uri: 'https://oauth2.googleapis.com/token',
    ...overrides,
  };
}

/** Özel anahtarın gövdesinden ayırt edici bir parça (sızıntı aramaları için). */
export function privateKeyFragment() {
  const body = testKeyPair().privateKey.split('\n').filter((line) => line && !line.startsWith('-----'));
  return body[3].slice(0, 40);
}

/**
 * Sahte OAuth2 (/token) + FCM (/v1/projects/:p/messages:send) sunucusu. `token` ve `send` işleyicileri her istekte çağrılır:
 * ({ body, headers, count }) => { status, json?, headers? } | 'hang'. Varsayılan: geçerli erişim jetonu ve 200.
 */
export async function startFakeGoogle() {
  const state = {
    tokenRequests: [],
    sendRequests: [],
    tokenCount: 0,
    sendCount: 0,
    accessToken: 'ya29.test-erisim-jetonu-GIZLI-0001',
    token: null,
    send: null,
    delayMs: 0,
  };
  const server = http.createServer((req, res) => {
    const chunks = [];
    req.on('data', (chunk) => chunks.push(chunk));
    req.on('end', async () => {
      const raw = Buffer.concat(chunks).toString('utf8');
      const reply = (answer) => {
        if (answer === 'hang') return; // yanıt yok: istemci zaman aşımı
        res.writeHead(answer.status ?? 200, { 'content-type': 'application/json', ...(answer.headers ?? {}) });
        res.end(answer.raw ?? JSON.stringify(answer.json ?? {}));
      };
      if (state.delayMs > 0) await new Promise((resolve) => setTimeout(resolve, state.delayMs));
      if (req.url === '/token') {
        state.tokenCount += 1;
        const body = Object.fromEntries(new URLSearchParams(raw));
        state.tokenRequests.push({ body, headers: req.headers });
        const answer = state.token
          ? await state.token({ body, headers: req.headers, count: state.tokenCount })
          : { status: 200, json: { access_token: `${state.accessToken}-${state.tokenCount}`, expires_in: 3599, token_type: 'Bearer' } };
        reply(answer);
        return;
      }
      const match = /^\/v1\/projects\/([^/]+)\/messages:send$/.exec(req.url);
      if (match && req.method === 'POST') {
        state.sendCount += 1;
        let body;
        try {
          body = JSON.parse(raw);
        } catch (_error) {
          body = null;
        }
        state.sendRequests.push({ project: decodeURIComponent(match[1]), body, headers: req.headers });
        const answer = state.send
          ? await state.send({ body, headers: req.headers, count: state.sendCount })
          : { status: 200, json: { name: `projects/${match[1]}/messages/0:${state.sendCount}` } };
        reply(answer);
        return;
      }
      res.writeHead(404, { 'content-type': 'application/json' });
      res.end('{}');
    });
  });
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  const base = `http://127.0.0.1:${server.address().port}`;
  return {
    state,
    base,
    tokenUrl: `${base}/token`,
    apiBase: base,
    async close() {
      server.closeAllConnections?.();
      await new Promise((resolve) => server.close(resolve));
    },
  };
}

/** FCM v1 hata gövdesi. */
export function fcmError(status, statusText, errorCode = null, extraDetails = []) {
  const details = [];
  if (errorCode) details.push({ '@type': 'type.googleapis.com/google.firebase.fcm.v1.FcmError', errorCode });
  details.push(...extraDetails);
  return { error: { code: status, message: `Gizli ayrinti metni ${statusText}`, status: statusText, details } };
}
