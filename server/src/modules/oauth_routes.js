// Sosyal giris / kayit uclari (076): Google ile Giris / Kaydol ve iCloud (Apple) ile Giris / Kaydol.
//   Acik GET  /auth/oauth/status                   -> { google: { enabled, client_id }, apple: { enabled, client_id } }
//   Acik POST /auth/oauth/:provider                -> { ok, is_new_user, provider, token, user, device_token? }
//   Acik POST /auth/oauth/:provider/request-code   -> { ok, provider, email, code_length, expires_in_minutes, message }
//   Acik POST /auth/oauth/:provider/verify-code    -> { ok, is_new_user, provider, token, user, device_token? }
//   Acik POST /auth/oauth/:provider/start          -> { mode, provider, redirect_enabled, session_id?, auth_url? }
//   Acik GET/POST /auth/oauth/:provider/callback   -> HTML onay sayfasi (tarayici yonlendirmesi icin)
//   Acik GET  /auth/oauth/session/:sessionId       -> { status: 'pending' | 'completed' | 'error', ... }
import express from 'express';
import { createRuleLimiter } from '../middlewares/rate_limiters.js';
import { readDeviceToken } from '../security/login_device_token.js';
import { HOUR_MS, ipKey, respondError } from './route_helpers.js';
import {
  authenticateWithOAuth,
  completeOAuthWebCallback,
  oauthStatus,
  pollOAuthWebSession,
  requestOAuthEmailCode,
  startOAuthWebSession,
  verifyOAuthEmailCode,
} from './oauth_login.js';

export const oauthRouter = express.Router();

export const oauthVerifyLimiter = createRuleLimiter({
  rules: [{ windowMs: HOUR_MS, max: 60, key: ipKey }],
  message: 'Çok fazla sosyal giriş denemesi. Lütfen biraz sonra tekrar deneyin.',
  includeRetryBody: true,
});

export const oauthCodeRequestLimiter = createRuleLimiter({
  rules: [
    { windowMs: HOUR_MS, max: 20, key: ipKey },
    {
      windowMs: 15 * 60 * 1000,
      max: 5,
      key: (req) => {
        const email = typeof req.body?.email === 'string' ? req.body.email.trim().toLowerCase() : '';
        return email ? `email:${email}` : ipKey(req);
      },
    },
  ],
  message: 'Çok fazla doğrulama kodu talebi. Lütfen biraz sonra tekrar deneyin.',
  includeRetryBody: true,
});

const bodyOf = (req) => (req.body && typeof req.body === 'object' && !Array.isArray(req.body) ? req.body : {});

function handler({ context, fallback }, run) {
  return async (req, res) => {
    try {
      res.setHeader('Cache-Control', 'no-store');
      return res.status(200).json(await run(req));
    } catch (error) {
      if (error?.expose && Number.isInteger(error?.statusCode)) {
        return res.status(error.statusCode).json({
          error: error.message,
          ...(error.code ? { code: error.code } : {}),
        });
      }
      return respondError(res, context, error, fallback);
    }
  };
}

function handleProviderAuth(provider) {
  return handler(
    {
      context: `oauth_${provider}`,
      fallback: `${provider === 'apple' ? 'iCloud (Apple)' : 'Google'} ile giriş yapılamadı.`,
    },
    async (req) => {
      const body = bodyOf(req);
      const idToken = body.id_token ?? body.idToken ?? body.credential ?? '';
      return authenticateWithOAuth({
        provider,
        idToken: String(idToken),
        fullName: body.full_name ?? body.fullName ?? null,
        firstName: body.first_name ?? body.firstName ?? body.given_name ?? null,
        lastName: body.last_name ?? body.lastName ?? body.family_name ?? null,
        acceptedDocuments: body.accepted_documents ?? body.acceptedDocuments,
        rawDeviceToken: readDeviceToken(req),
      });
    },
  );
}

function handleProviderRequestCode(provider) {
  return handler(
    {
      context: `oauth_request_code_${provider}`,
      fallback: `${provider === 'apple' ? 'iCloud (Apple)' : 'Google'} doğrulama kodu gönderilemedi.`,
    },
    async (req) => {
      const body = bodyOf(req);
      return requestOAuthEmailCode({
        provider,
        email: body.email ?? '',
        fullName: body.full_name ?? body.fullName ?? null,
        firstName: body.first_name ?? body.firstName ?? body.given_name ?? null,
        lastName: body.last_name ?? body.lastName ?? body.family_name ?? null,
      });
    },
  );
}

function handleProviderVerifyCode(provider) {
  return handler(
    {
      context: `oauth_verify_code_${provider}`,
      fallback: `${provider === 'apple' ? 'iCloud (Apple)' : 'Google'} doğrulama kodu onaylanamadı.`,
    },
    async (req) => {
      const body = bodyOf(req);
      return verifyOAuthEmailCode({
        provider,
        email: body.email ?? '',
        code: body.code ?? '',
        fullName: body.full_name ?? body.fullName ?? null,
        firstName: body.first_name ?? body.firstName ?? body.given_name ?? null,
        lastName: body.last_name ?? body.lastName ?? body.family_name ?? null,
        acceptedDocuments: body.accepted_documents ?? body.acceptedDocuments,
        rawDeviceToken: readDeviceToken(req),
      });
    },
  );
}

function handleProviderStart(provider) {
  return handler(
    {
      context: `oauth_start_${provider}`,
      fallback: `${provider === 'apple' ? 'iCloud (Apple)' : 'Google'} girişi başlatılamadı.`,
    },
    async (req) => {
      const body = bodyOf(req);
      return startOAuthWebSession({
        provider,
        acceptedDocuments: body.accepted_documents ?? body.acceptedDocuments,
      });
    },
  );
}

function renderCallbackHtml({ title, message, ok }) {
  const color = ok ? '#10b981' : '#ef4444';
  return `<!DOCTYPE html>
<html lang="tr">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>${title}</title>
  <style>
    body { font-family: system-ui, -apple-system, sans-serif; background: #0f172a; color: #f8fafc; display: flex; align-items: center; justify-content: center; min-height: 100vh; margin: 0; padding: 16px; }
    .card { max-width: 400px; width: 100%; background: #1e293b; border: 1px solid #334155; border-radius: 16px; padding: 24px; text-align: center; }
    .badge { width: 48px; height: 48px; border-radius: 50%; background: ${color}22; color: ${color}; display: inline-flex; align-items: center; justify-content: center; font-size: 24px; font-weight: bold; margin-bottom: 12px; }
    h1 { font-size: 18px; margin: 0 0 8px; }
    p { font-size: 14px; color: #cbd5e1; margin: 0; line-height: 1.5; }
  </style>
</head>
<body>
  <div class="card">
    <div class="badge">${ok ? '✓' : '!'}</div>
    <h1>${title}</h1>
    <p>${message}</p>
  </div>
  <script>setTimeout(function(){ try { window.close(); } catch(e){} }, 1500);</script>
</body>
</html>`;
}

function handleProviderCallback(provider) {
  return async (req, res) => {
    res.setHeader('Cache-Control', 'no-store');
    const source = req.method === 'POST' ? bodyOf(req) : req.query || {};
    const state = source.state ?? '';
    const idToken = source.id_token ?? source.idToken ?? '';
    const userJson = source.user ?? null;
    const error = source.error ?? null;

    if (req.method === 'GET' && !idToken && !error) {
      // Hash fragment (#id_token=...) ile donen saglayicilar icin otomatik POST koprusu
      return res.status(200).send(`<!DOCTYPE html>
<html lang="tr"><head><meta charset="utf-8"><title>Yönlendiriliyor...</title></head>
<body style="background:#0f172a;color:#f8fafc;font-family:sans-serif;display:flex;align-items:center;justify-content:center;height:100vh;margin:0">
<p>Giriş doğrulanıyor, lütfen bekleyin...</p>
<script>
  (function() {
    var hash = window.location.hash ? window.location.hash.substring(1) : '';
    if (!hash) { document.body.innerHTML = '<p>Geçersiz yönlendirme.</p>'; return; }
    var params = new URLSearchParams(hash);
    var form = document.createElement('form');
    form.method = 'POST';
    form.action = window.location.pathname;
    params.forEach(function(val, key) {
      var input = document.createElement('input');
      input.type = 'hidden';
      input.name = key;
      input.value = val;
      form.appendChild(input);
    });
    document.body.appendChild(form);
    form.submit();
  })();
</script>
</body></html>`);
    }

    try {
      const out = await completeOAuthWebCallback({
        provider,
        state,
        idToken,
        userJson,
        error,
      });
      if (!out.ok) {
        return res.status(400).send(
          renderCallbackHtml({
            title: 'Giriş İptal Edildi',
            message: out.error || 'İşlem iptal edildi. Uygulamaya dönebilirsiniz.',
            ok: false,
          }),
        );
      }
      return res.status(200).send(
        renderCallbackHtml({
          title: 'Giriş Başarılı',
          message: 'Hesabınız doğrulandı. Bu pencereyi kapatıp uygulamaya dönebilirsiniz.',
          ok: true,
        }),
      );
    } catch (err) {
      return res.status(400).send(
        renderCallbackHtml({
          title: 'Doğrulama Başarısız',
          message: err?.message || 'Giriş tamamlanamadı. Lütfen uygulamadan tekrar deneyin.',
          ok: false,
        }),
      );
    }
  };
}

oauthRouter.get(
  '/auth/oauth/status',
  handler({ context: 'oauth_status', fallback: 'Sosyal giriş durumu alınamadı.' }, () => oauthStatus()),
);

oauthRouter.get(
  '/auth/oauth/session/:sessionId',
  handler({ context: 'oauth_session_poll', fallback: 'Oturum durumu alınamadı.' }, (req) =>
    pollOAuthWebSession(req.params.sessionId),
  ),
);

for (const provider of ['google', 'apple']) {
  oauthRouter.post(`/auth/oauth/${provider}`, oauthVerifyLimiter, handleProviderAuth(provider));
  oauthRouter.post(
    `/auth/oauth/${provider}/request-code`,
    oauthCodeRequestLimiter,
    handleProviderRequestCode(provider),
  );
  oauthRouter.post(
    `/auth/oauth/${provider}/verify-code`,
    oauthVerifyLimiter,
    handleProviderVerifyCode(provider),
  );
  oauthRouter.post(`/auth/oauth/${provider}/start`, oauthVerifyLimiter, handleProviderStart(provider));
  oauthRouter.get(`/auth/oauth/${provider}/callback`, handleProviderCallback(provider));
  oauthRouter.post(
    `/auth/oauth/${provider}/callback`,
    express.urlencoded({ extended: false }),
    handleProviderCallback(provider),
  );
}
