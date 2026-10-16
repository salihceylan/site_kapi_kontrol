// Hesap silme / veri dışa aktarma uçları (DB'siz): rota zinciri (authRequired + hız sınırı), yanıt şekilleri ve başlıklar, hata eşlemesi
// (Retry-After, 5xx'te errorId + kişisel veri sızmaması). Servisler SAHTE (createAccountRouter enjeksiyonu); gerçek PostgreSQL: scripts/qa_platform_pg.mjs "account".
import { describe, it, before, after, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert/strict';
import express from 'express';
import { authRequired } from '../src/middlewares/auth_middleware.js';
import {
  accountPreviewLimiter,
  accountRouter,
  accountWriteLimiter,
  createAccountRouter,
} from '../src/modules/account_routes.js';
import {
  accountDeleted,
  currentPasswordLocked,
  deleteBlocked,
  exportRateLimited,
  exportTooLarge,
  superUserBlocker,
} from '../src/modules/account_common.js';

const USER = { id: 12345, user_code: 12345, userCode: 12345, role: 'individual', full_name: 'Ada Lovelace', email: 'ada@example.com' };

let calls;
let behavior;
let server;
let baseUrl;
let errors;
let originalConsoleError;

function fakeServices() {
  return {
    preview: async (authUser) => {
      calls.push(['preview', authUser]);
      return behavior.preview(authUser);
    },
    remove: async (input) => {
      calls.push(['remove', input]);
      return behavior.remove(input);
    },
    exportData: async (input) => {
      calls.push(['export', input]);
      return behavior.exportData(input);
    },
  };
}

function patchAuth(router) {
  for (const layer of router.stack) {
    if (!layer.route) continue;
    layer.route.stack[0].handle = (req, _res, next) => {
      req.authUser = JSON.parse(decodeURIComponent(req.headers['x-test-user']));
      next();
    };
    // hız sınırlayıcılar rota testlerinde atlanır (ayrı testte doğrudan sınanır)
    layer.route.stack[1].handle = (_req, _res, next) => next();
  }
}

const post = (path, body, user = USER) =>
  fetch(`${baseUrl}${path}`, {
    method: 'POST',
    headers: { 'content-type': 'application/json', 'x-test-user': encodeURIComponent(JSON.stringify(user)) },
    body: body === undefined ? undefined : JSON.stringify(body),
  });

before(async () => {
  const router = createAccountRouter(fakeServices());
  patchAuth(router);
  const app = express();
  app.use(express.json());
  app.use(router);
  await new Promise((resolve) => {
    server = app.listen(0, '127.0.0.1', resolve);
  });
  baseUrl = `http://127.0.0.1:${server.address().port}`;
});

after(async () => {
  server.closeAllConnections?.();
  await new Promise((resolve) => server.close(resolve));
});

beforeEach(() => {
  calls = [];
  errors = [];
  behavior = {
    preview: async () => ({ can_delete: true, blockers: [], will_remove: ['a'], will_keep: ['b'] }),
    remove: async () => ({ deleted: true }),
    exportData: async () => ({ filename: 'kisisel-veri-12345-20261016.json', text: '{"format_version":1}', truncated: false }),
  };
  originalConsoleError = console.error;
  console.error = (...args) => {
    errors.push(args.map(String).join(' '));
  };
});

afterEach(() => {
  console.error = originalConsoleError;
});

describe('hesap uçları: rota zinciri', () => {
  it('üç POST ucu var; hepsi authRequired ile başlar ve hız sınırlayıcı taşır', () => {
    const routes = accountRouter.stack.filter((layer) => layer.route).map((layer) => ({ path: layer.route.path, methods: Object.keys(layer.route.methods), stack: layer.route.stack.map((entry) => entry.handle) }));
    assert.deepEqual(routes.map((route) => route.path).sort(), ['/me/account-deletion', '/me/account-deletion/preview', '/me/data-export']);
    for (const route of routes) {
      assert.deepEqual(route.methods, ['post'], route.path);
      assert.equal(route.stack[0], authRequired, `${route.path}: ilk katman authRequired`);
      assert.equal(route.stack.length, 3, `${route.path}: authRequired + hız sınırı + işleyici`);
    }
    const byPath = Object.fromEntries(routes.map((route) => [route.path, route.stack[1]]));
    assert.equal(byPath['/me/account-deletion/preview'], accountPreviewLimiter);
    assert.equal(byPath['/me/account-deletion'], accountWriteLimiter);
    assert.equal(byPath['/me/data-export'], accountWriteLimiter);
  });

  it('kimliksiz istek 401 (authRequired yamasız): hizmete ulaşmaz', async () => {
    const calls2 = [];
    const real = createAccountRouter({
      preview: async () => calls2.push('preview'),
      remove: async () => calls2.push('remove'),
      exportData: async () => calls2.push('export'),
    });
    const app = express();
    app.use(express.json());
    app.use(real);
    const unauth = await new Promise((resolve) => {
      const s = app.listen(0, '127.0.0.1', () => resolve(s));
    });
    try {
      const base = `http://127.0.0.1:${unauth.address().port}`;
      for (const path of ['/me/account-deletion/preview', '/me/account-deletion', '/me/data-export']) {
        const response = await fetch(`${base}${path}`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: '{}' });
        assert.equal(response.status, 401, path);
      }
      assert.deepEqual(calls2, []);
    } finally {
      unauth.closeAllConnections?.();
      await new Promise((resolve) => unauth.close(resolve));
    }
  });
});

describe('hesap uçları: yanıtlar', () => {
  it('önizleme: 200, gövde servisten aynen, no-store; servis kimlikli kullanıcıyı alır', async () => {
    const response = await post('/me/account-deletion/preview', {});
    assert.equal(response.status, 200);
    assert.equal(response.headers.get('cache-control'), 'no-store');
    assert.deepEqual(await response.json(), { can_delete: true, blockers: [], will_remove: ['a'], will_keep: ['b'] });
    assert.equal(calls[0][0], 'preview');
    assert.equal(calls[0][1].user_code, 12345);
  });

  it('silme: gövde servise iletilir ({current_password, confirm}); 200 { deleted: true }', async () => {
    const response = await post('/me/account-deletion', { current_password: 'x', confirm: true });
    assert.equal(response.status, 200);
    assert.deepEqual(await response.json(), { deleted: true });
    assert.deepEqual(calls[0][1].body, { current_password: 'x', confirm: true });
    assert.equal(calls[0][1].authUser.user_code, 12345);
  });

  it('silme: gövdesiz istek servise boş gövdeyle gider (çökmez)', async () => {
    const response = await post('/me/account-deletion', undefined);
    assert.equal(response.status, 200);
    assert.ok(calls[0][1].body === undefined || typeof calls[0][1].body === 'object');
  });

  it('engel: 409 { error, code: ACCOUNT_DELETE_BLOCKED, blockers }', async () => {
    behavior.remove = async () => {
      throw deleteBlocked([superUserBlocker()]);
    };
    const response = await post('/me/account-deletion', { current_password: 'x', confirm: true });
    assert.equal(response.status, 409);
    const body = await response.json();
    assert.equal(body.code, 'ACCOUNT_DELETE_BLOCKED');
    assert.equal(body.blockers[0].code, 'SUPER_USER');
    assert.ok(body.error.length > 5);
  });

  it('kilit: 429 + Retry-After başlığı + retry_after_seconds + CURRENT_PASSWORD_LOCKED', async () => {
    behavior.remove = async () => {
      throw currentPasswordLocked(90);
    };
    const response = await post('/me/account-deletion', { current_password: 'x', confirm: true });
    assert.equal(response.status, 429);
    assert.equal(response.headers.get('retry-after'), '90');
    const body = await response.json();
    assert.equal(body.code, 'CURRENT_PASSWORD_LOCKED');
    assert.equal(body.retry_after_seconds, 90);
  });

  it('silinmiş hesap: 401 ACCOUNT_DELETED', async () => {
    behavior.remove = async () => {
      throw accountDeleted();
    };
    const response = await post('/me/account-deletion', { current_password: 'x', confirm: true });
    assert.equal(response.status, 401);
    assert.equal((await response.json()).code, 'ACCOUNT_DELETED');
  });

  it('dışa aktarma: 200, application/json; charset=utf-8, no-store, attachment dosya adı, gövde AYNEN (yeniden biçimlendirilmez)', async () => {
    const response = await post('/me/data-export', { current_password: 'x' });
    assert.equal(response.status, 200);
    assert.equal(response.headers.get('content-type'), 'application/json; charset=utf-8');
    assert.equal(response.headers.get('cache-control'), 'no-store');
    assert.equal(response.headers.get('content-disposition'), 'attachment; filename="kisisel-veri-12345-20261016.json"');
    assert.equal(await response.text(), '{"format_version":1}');
    assert.deepEqual(calls[0][1].body, { current_password: 'x' });
  });

  it('dışa aktarma sınırı: 429 EXPORT_RATE_LIMITED + Retry-After', async () => {
    behavior.exportData = async () => {
      throw exportRateLimited(3600);
    };
    const response = await post('/me/data-export', { current_password: 'x' });
    assert.equal(response.status, 429);
    assert.equal(response.headers.get('retry-after'), '3600');
    const body = await response.json();
    assert.equal(body.code, 'EXPORT_RATE_LIMITED');
    assert.equal(body.retry_after_seconds, 3600);
    assert.equal(response.headers.get('content-disposition'), null, 'hata yanıtı dosya olarak indirilmez');
  });

  it('dışa aktarma çok büyük (kısaltılamaz): 413 EXPORT_TOO_LARGE { error, code }; dosya değil, errorId yok', async () => {
    behavior.exportData = async () => {
      throw exportTooLarge();
    };
    const response = await post('/me/data-export', { current_password: 'x' });
    assert.equal(response.status, 413);
    const body = await response.json();
    assert.equal(body.code, 'EXPORT_TOO_LARGE');
    assert.equal(typeof body.error, 'string');
    assert.equal('errorId' in body, false);
    assert.equal(response.headers.get('content-disposition'), null);
  });
});

describe('hesap uçları: beklenmeyen hatalar kişisel veri SIZDIRMAZ', () => {
  it('5xx: genel mesaj + errorId; hata iletisi (e-posta içerebilir) ne yanıta ne log\'a yazılır', async () => {
    const secret = 'duplicate key value violates unique constraint "users_email_key" Key (email)=(ada@example.com) already exists';
    behavior.remove = async () => {
      throw Object.assign(new Error(secret), { code: '23505', stack: `Error: ${secret}\n at x` });
    };
    const response = await post('/me/account-deletion', { current_password: 'Gizli-Parola-1', confirm: true });
    assert.equal(response.status, 500);
    const text = await response.text();
    const body = JSON.parse(text);
    assert.ok(body.errorId && /^[0-9a-f]{12}$/.test(body.errorId));
    assert.ok(body.error);
    assert.equal(text.includes('ada@example.com'), false);
    assert.equal(text.includes('users_email_key'), false);
    const logged = errors.join('\n');
    assert.ok(logged.includes(body.errorId));
    assert.ok(logged.includes('23505'), 'yalnız hata kodu loglanır');
    assert.equal(logged.includes('ada@example.com'), false);
    assert.equal(logged.includes('Gizli-Parola-1'), false);
    assert.equal(logged.includes('users_email_key'), false);
  });

  it('önizleme ve dışa aktarma 5xx de aynı şekilde', async () => {
    behavior.preview = async () => {
      throw new Error('boom ada@example.com');
    };
    behavior.exportData = async () => {
      throw new Error('boom 05551234567');
    };
    for (const [path, body] of [['/me/account-deletion/preview', {}], ['/me/data-export', { current_password: 'x' }]]) {
      const response = await post(path, body);
      assert.equal(response.status, 500, path);
      const text = await response.text();
      assert.ok(JSON.parse(text).errorId);
      assert.equal(/ada@example\.com|05551234567/.test(text), false);
    }
    assert.equal(/ada@example\.com|05551234567/.test(errors.join('\n')), false);
  });
});

describe('hesap uçları: hız sınırı (bellek içi)', () => {
  function run(limiter, user = 12345, ip = '10.0.0.1') {
    const headers = {};
    let status = null;
    let body = null;
    let passed = false;
    const req = { authUser: { user_code: user }, ip, socket: { remoteAddress: ip } };
    const res = {
      setHeader: (name, value) => {
        headers[name] = value;
      },
      status(code) {
        status = code;
        return this;
      },
      json(value) {
        body = value;
        return this;
      },
    };
    limiter(req, res, () => {
      passed = true;
    });
    return { passed, status, body, headers };
  }

  it('silme / dışa aktarma: kullanıcı başına saatte 20; aşılınca 429 + Retry-After + retry_after_seconds; başka kullanıcı etkilenmez', () => {
    accountWriteLimiter.reset();
    for (let i = 0; i < 20; i += 1) {
      assert.equal(run(accountWriteLimiter).passed, true, `istek ${i + 1}`);
    }
    const blocked = run(accountWriteLimiter);
    assert.equal(blocked.passed, false);
    assert.equal(blocked.status, 429);
    assert.ok(Number(blocked.headers['Retry-After']) >= 1);
    assert.ok(blocked.body.retry_after_seconds >= 1);
    assert.equal(run(accountWriteLimiter, 22222, '10.0.0.2').passed, true);
    accountWriteLimiter.reset();
  });

  it('önizleme: kullanıcı başına saatte 120', () => {
    accountPreviewLimiter.reset();
    for (let i = 0; i < 120; i += 1) {
      assert.equal(run(accountPreviewLimiter).passed, true);
    }
    assert.equal(run(accountPreviewLimiter).status, 429);
    accountPreviewLimiter.reset();
  });
});
