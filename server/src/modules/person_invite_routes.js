// Uygulamaya davet: kabul sayfası (kimliksiz, belirteçli) ve mevcut hesapla kabul/ret uçları (058).
//
//   GET  /auth/accept-invite?token=      CSP'li HTML sayfa (şifre sıfırlama sayfası kalıbı): site adı, salt okunur e-posta, ad, şifre x2, onay kutusu
//   POST /auth/accept-invite             { token, password, full_name?, accepted_documents? } -> yeni hesap açar ve kişiyi bağlar
//   GET  /app/invitations                çağıranın doğrulanmış e-postasıyla eşleşen bekleyen davetler
//   POST /app/invitations/:id/accept     mevcut hesapla kabul (rıza ve sahiplik uygulamada giriş yapan kişiden gelir)
//   POST /app/invitations/:id/decline
//
// Geçersiz / dolmuş / kullanılmış belirteç TEK tip 400 INVITE_INVALID (ayrım yapılmaz). Belirteç günlüklere girmez (request_logger "invite" desenini maskeler).

import express from 'express';
import { escapeHtml } from '../mailer.js';
import { authRequired } from '../middlewares/auth_middleware.js';
import { resetPasswordLimiter } from '../middlewares/rate_limiters.js';
import { respondError } from './route_helpers.js';
import { acceptInviteNewAccount, acceptMyInvitation, declineMyInvitation, getInviteSummary, listMyInvitations } from './person_invite_service.js';

export const personInviteRouter = express.Router();

const PAGE_CSP =
  "default-src 'none'; style-src 'unsafe-inline'; script-src 'unsafe-inline'; connect-src 'self'; form-action 'self'; base-uri 'none'; frame-ancestors 'none'";

function sendPage(res, status, html) {
  res.setHeader('Content-Security-Policy', PAGE_CSP);
  res.setHeader('Cache-Control', 'no-store');
  res.setHeader('Referrer-Policy', 'no-referrer');
  res.setHeader('X-Content-Type-Options', 'nosniff');
  return res.status(status).send(html);
}

const STYLE = `
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif; background: #0f172a; color: #f8fafc; display: flex; align-items: center; justify-content: center; min-height: 100vh; padding: 20px; }
  .card { background: #1e293b; border: 1px solid #334155; border-radius: 20px; padding: 32px 26px; max-width: 440px; width: 100%; }
  h2 { font-size: 21px; margin-bottom: 10px; }
  p { font-size: 14.5px; color: #94a3b8; line-height: 1.6; margin-bottom: 14px; }
  label { display: block; font-size: 13px; color: #cbd5e1; margin: 12px 0 6px; }
  input[type=text], input[type=password], input[type=email] { width: 100%; padding: 12px; border-radius: 10px; border: 1px solid #475569; background: #0f172a; color: #f8fafc; font-size: 15px; }
  input[readonly] { opacity: .7; }
  .row { display: flex; gap: 8px; align-items: flex-start; margin: 10px 0; font-size: 13px; color: #cbd5e1; }
  .row a { color: #93c5fd; }
  button { width: 100%; margin-top: 18px; padding: 14px; background: #3b82f6; color: #fff; font-weight: 600; border: 0; border-radius: 12px; font-size: 15px; cursor: pointer; }
  button:disabled { opacity: .6; }
  .alert { display: none; margin-top: 12px; padding: 10px 12px; border-radius: 10px; background: rgba(239,68,68,.15); border: 1px solid #ef4444; font-size: 13.5px; }
  .ok { display: none; }
`;

function shell(title, body) {
  return `<!DOCTYPE html><html lang="tr"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="referrer" content="no-referrer"><title>${escapeHtml(title)}</title><style>${STYLE}</style></head><body><div class="card">${body}</div></body></html>`;
}

function errorPage(message) {
  return shell('Davet', `<h2>Davet kullanılamıyor</h2><p>${escapeHtml(message)}</p>`);
}

function formPage(summary, token) {
  const docs = summary.documents
    .map((d) => `<a href="/legal/${encodeURIComponent(d.id)}" target="_blank" rel="noopener noreferrer">${escapeHtml(d.title)}</a>`)
    .join(', ');
  const consentRow = summary.documents.length > 0
    ? `<div class="row"><input type="checkbox" id="consent"><label for="consent" style="margin:0">${docs} metinlerini okudum, kabul ediyorum.</label></div>`
    : '';
  const data = escapeHtml(JSON.stringify({ token, documents: summary.documents.map((d) => ({ id: d.id, version: d.version })), enforced: summary.enforced }));
  return shell(
    'Uygulamaya Davet',
    `
    <div id="form-container" data-state="${data}">
      <h2>${escapeHtml(summary.site_name)} sitesine davetlisiniz</h2>
      <p>Hesabınızı oluşturmak için adınızı ve şifrenizi belirleyin.</p>
      <label for="email">E-posta</label><input type="email" id="email" value="${escapeHtml(summary.email)}" readonly>
      <label for="full_name">Ad soyad</label><input type="text" id="full_name" maxlength="100" value="${escapeHtml(summary.full_name)}" autocomplete="name">
      <label for="password">Şifre</label><input type="password" id="password" autocomplete="new-password">
      <label for="password_confirm">Şifre (tekrar)</label><input type="password" id="password_confirm" autocomplete="new-password">
      ${consentRow}
      <div class="alert" id="alert-box"></div>
      <button id="submit-btn" type="button">Hesabı oluştur</button>
    </div>
    <div class="ok" id="success-box" style="text-align: center;">
      <div style="width: 60px; height: 60px; background: rgba(16, 185, 129, 0.15); border: 2px solid #10b981; border-radius: 50%; display: flex; align-items: center; justify-content: center; margin: 0 auto 16px; font-size: 28px; color: #10b981;">✓</div>
      <h2 style="color: #10b981;">Hesabınız hazır!</h2>
      <p style="margin-bottom: 20px;">Artık e-postanız ve şifrenizle uygulamaya giriş yapabilirsiniz.</p>
      <a href="/" class="btn-submit" onclick="handleOpenApp(event)" style="display:inline-block; text-decoration: none; width: 100%; box-sizing: border-box; text-align: center; padding: 14px; background: #2563eb; color: #fff; border-radius: 12px; font-weight: 600;">Uygulamayı Aç</a>
      <div style="margin-top: 14px;"><a href="/" style="color: #60a5fa; font-size: 14px; text-decoration: none;">Web Giriş Ekranına Git &rarr;</a></div>
    </div>
    <script>
      function handleOpenApp(e) {
        var isMobile = /Android|iPhone|iPad|iPod/i.test(navigator.userAgent);
        if (isMobile) {
          if (e && e.preventDefault) e.preventDefault();
          var start = Date.now();
          window.location.href = 'sitekapi://door_control';
          setTimeout(function () {
            if (Date.now() - start < 2500) {
              window.location.href = '/';
            }
          }, 1500);
        }
      }
      (function () {
        var state = JSON.parse(document.getElementById('form-container').getAttribute('data-state'));
        var alertBox = document.getElementById('alert-box');
        var btn = document.getElementById('submit-btn');
        function fail(msg) { alertBox.textContent = msg; alertBox.style.display = 'block'; btn.disabled = false; }
        btn.addEventListener('click', async function () {
          alertBox.style.display = 'none';
          var pass = document.getElementById('password').value;
          if (Array.from(pass).length < 8) { return fail('Şifreniz en az 8 karakter olmalıdır.'); }
          if (pass !== document.getElementById('password_confirm').value) { return fail('Şifreler eşleşmiyor.'); }
          var consent = document.getElementById('consent');
          if (state.documents.length > 0 && state.enforced && !(consent && consent.checked)) { return fail('Devam etmek için metinleri onaylayın.'); }
          btn.disabled = true;
          try {
            var res = await fetch('/auth/accept-invite', {
              method: 'POST', headers: { 'Content-Type': 'application/json' },
              body: JSON.stringify({
                token: state.token, password: pass, full_name: document.getElementById('full_name').value,
                accepted_documents: consent && consent.checked ? state.documents : []
              })
            });
            var data = await res.json().catch(function () { return {}; });
            if (!res.ok) { return fail(data.error || 'Hesap oluşturulamadı.'); }
            document.getElementById('form-container').style.display = 'none';
            document.getElementById('success-box').style.display = 'block';
          } catch (e) { fail('Bağlantı hatası. Tekrar deneyin.'); }
        });
      })();
    </script>`,
  );
}

personInviteRouter.get('/auth/accept-invite', resetPasswordLimiter, async (req, res) => {
  const token = String(req.query.token || '').trim();
  try {
    const summary = await getInviteSummary(token);
    return sendPage(res, 200, formPage(summary, token));
  } catch (error) {
    if (error?.code === 'INVITE_INVALID') {
      return sendPage(res, 400, errorPage(error.message));
    }
    console.error('[accept-invite:get] hata:', error?.code || error?.message);
    return sendPage(res, 500, errorPage('İşlem sırasında bir hata oluştu. Daha sonra tekrar deneyin.'));
  }
});

personInviteRouter.post('/auth/accept-invite', resetPasswordLimiter, async (req, res) => {
  try {
    const body = req.body && typeof req.body === 'object' && !Array.isArray(req.body) ? req.body : {};
    res.setHeader('Cache-Control', 'no-store');
    return res.json(
      await acceptInviteNewAccount({
        token: String(body.token ?? '').trim(),
        password: body.password,
        fullName: body.full_name,
        acceptedDocuments: body.accepted_documents,
      }),
    );
  } catch (error) {
    return respondError(res, 'accept_invite', error, 'Hesap oluşturulamadı.');
  }
});

personInviteRouter.get('/app/invitations', authRequired, async (req, res) => {
  try {
    res.setHeader('Cache-Control', 'no-store');
    return res.json(await listMyInvitations(req.authUser));
  } catch (error) {
    return respondError(res, 'invitations_list', error, 'Davetler yüklenemedi.');
  }
});

personInviteRouter.post('/app/invitations/:invitationId/accept', authRequired, async (req, res) => {
  try {
    return res.json(await acceptMyInvitation({ authUser: req.authUser, invitationId: req.params.invitationId }));
  } catch (error) {
    return respondError(res, 'invitation_accept', error, 'Davet kabul edilemedi.');
  }
});

personInviteRouter.post('/app/invitations/:invitationId/decline', authRequired, async (req, res) => {
  try {
    return res.json(await declineMyInvitation({ authUser: req.authUser, invitationId: req.params.invitationId }));
  } catch (error) {
    return respondError(res, 'invitation_decline', error, 'Davet reddedilemedi.');
  }
});
