// Duyuru e-postası "abonelikten çık" (kimliksiz genel uç; yalnız imzalı belirteçle).
//
//   GET  /public/announcement-unsubscribe?t=<belirteç>   onay sayfası (hiçbir şey DEĞİŞTİRMEZ: e-posta tarayıcıları / güvenlik ağ geçitleri
//                                                         bağlantıyı ön yükler; GET çıkışı tetiklese yanlışlıkla herkes çıkardı)
//   POST /public/announcement-unsubscribe                çıkışı uygular. Belirteç sorgu dizesinde (`?t=`, RFC 8058 tek tıklama: gövde
//                                                         `List-Unsubscribe=One-Click`) ya da gövdede (`t`, onay sayfasındaki form) olabilir
//
// Belirteç = "<adres özeti>.<HMAC>" (announcement_email_security.js): adrese bağlı, süresiz, düz adres İÇERMEZ; sayfada adres gösterilmez.
// Çıkış `announcement_email_suppressions`'a yazılır: adres sonraki duyurularda 'skipped_pref' olur (acil dahil; hesapsız alıcı için başka
// kanal yok). Hesabı olan kullanıcının UYGULAMADAKİ duyurusu etkilenmez. IP başına sıkı hız sınırı; sayfa sıkı CSP ile servis edilir.

import express from 'express';
import { pool } from '../db.js';
import { createRuleLimiter } from '../middlewares/rate_limiters.js';
import { verifyUnsubscribeToken } from './announcement_email_security.js';
import { HOUR_MS, ipKey } from './route_helpers.js';

export const announcementPublicRouter = express.Router();

export const unsubscribeViewLimiter = createRuleLimiter({
  rules: [{ windowMs: HOUR_MS, max: 120, key: ipKey }],
  message: 'Çok fazla istek. Biraz sonra tekrar deneyin.',
});

export const unsubscribeApplyLimiter = createRuleLimiter({
  rules: [{ windowMs: HOUR_MS, max: 30, key: ipKey }],
  message: 'Çok fazla istek. Biraz sonra tekrar deneyin.',
});

const PAGE_CSP = "default-src 'none'; style-src 'unsafe-inline'; form-action 'self'; base-uri 'none'; frame-ancestors 'none'";

function page(title, bodyHtml) {
  return `<!DOCTYPE html>
<html lang="tr">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <meta name="robots" content="noindex" />
  <title>${title}</title>
  <style>
    body { font-family: Arial, sans-serif; background: #f3f4f6; color: #111827; margin: 0; padding: 24px; }
    .card { max-width: 480px; margin: 48px auto; background: #ffffff; border-radius: 12px; padding: 28px; box-shadow: 0 1px 6px rgba(0,0,0,0.08); }
    h1 { font-size: 20px; margin: 0 0 12px 0; }
    p { font-size: 15px; line-height: 1.6; margin: 0 0 16px 0; color: #374151; }
    button { background: #1d4ed8; color: #ffffff; border: 0; border-radius: 8px; padding: 12px 20px; font-size: 15px; cursor: pointer; }
  </style>
</head>
<body>
  <div class="card">
${bodyHtml}
  </div>
</body>
</html>`;
}

const INVALID_PAGE = page(
  'Bağlantı geçersiz',
  `    <h1>Bağlantı geçersiz</h1>
    <p>Bu abonelikten çıkma bağlantısı geçersiz ya da bozulmuş. E-postadaki bağlantıyı tam olarak açtığınızdan emin olun.</p>`,
);

const DONE_PAGE = page(
  'Abonelikten çıkıldı',
  `    <h1>Abonelikten çıkıldı</h1>
    <p>Bu e-posta adresine bundan sonra site duyuru e-postaları gönderilmeyecek. Uygulamayı kullanıyorsanız duyurularınızı uygulamada görmeye devam edersiniz.</p>`,
);

const ERROR_PAGE = page(
  'İşlem tamamlanamadı',
  `    <h1>İşlem tamamlanamadı</h1>
    <p>Şu anda isteğiniz işlenemedi. Lütfen biraz sonra bağlantıyı yeniden açın.</p>`,
);

function confirmPage(token) {
  // Belirteç yalnız [0-9a-f], '.', base64url karakterlerinden oluşur (verifyUnsubscribeToken doğruladı): HTML'e güvenle girer.
  return page(
    'Abonelikten çık',
    `    <h1>Duyuru e-postalarından çıkmak istiyor musunuz?</h1>
    <p>Onaylarsanız bu e-posta adresine site yönetiminin duyuru e-postaları artık gönderilmeyecek.</p>
    <form method="post" action="/public/announcement-unsubscribe">
      <input type="hidden" name="t" value="${token}" />
      <button type="submit">Evet, abonelikten çık</button>
    </form>`,
  );
}

function sendPage(res, status, html) {
  res.setHeader('Content-Security-Policy', PAGE_CSP);
  res.setHeader('Cache-Control', 'no-store');
  res.setHeader('X-Robots-Tag', 'noindex');
  return res.status(status).type('html').send(html);
}

const tokenOf = (req) => {
  const fromQuery = typeof req.query?.t === 'string' ? req.query.t : null;
  const fromBody = req.body && typeof req.body === 'object' && typeof req.body.t === 'string' ? req.body.t : null;
  return fromQuery ?? fromBody;
};

announcementPublicRouter.get('/public/announcement-unsubscribe', unsubscribeViewLimiter, (req, res) => {
  const token = tokenOf(req);
  if (verifyUnsubscribeToken(token) === null) {
    return sendPage(res, 400, INVALID_PAGE);
  }
  return sendPage(res, 200, confirmPage(token));
});

announcementPublicRouter.post('/public/announcement-unsubscribe', unsubscribeApplyLimiter, async (req, res) => {
  const emailHash = verifyUnsubscribeToken(tokenOf(req));
  if (emailHash === null) {
    return sendPage(res, 400, INVALID_PAGE);
  }
  try {
    await pool.query(
      `INSERT INTO announcement_email_suppressions (email_hash) VALUES ($1) ON CONFLICT (email_hash) DO NOTHING`,
      [emailHash],
    );
    // Henüz gönderimi başlamamış bekleyen e-postalar bu adres için iptal edilir (yoldakilere dokunulmaz; kuyruk talep anında da denetler).
    await pool.query(
      `
        UPDATE announcement_recipients
        SET email_status = 'skipped_pref', email = NULL, email_hash = NULL, email_next_at = NULL
        WHERE email_hash = $1 AND email_status = 'pending' AND email_claimed_at IS NULL
      `,
      [emailHash],
    );
    return sendPage(res, 200, DONE_PAGE);
  } catch (error) {
    // eslint-disable-next-line no-console
    console.error('[announcement-unsubscribe] kayit basarisiz:', error?.code || 'hata');
    return sendPage(res, 500, ERROR_PAGE);
  }
});
