// Duyuru e-postası "abonelikten çık" (kimliksiz genel uç; yalnız imzalı belirteçle).
//
//   GET  /public/announcement-unsubscribe?t=<belirteç>   onay sayfası (hiçbir şey DEĞİŞTİRMEZ: e-posta tarayıcıları / güvenlik ağ geçitleri
//                                                         bağlantıyı ön yükler; GET çıkışı tetiklese yanlışlıkla herkes çıkardı)
//   POST /public/announcement-unsubscribe                çıkışı uygular. Belirteç sorgu dizesinde (`?t=`, RFC 8058 tek tıklama: gövde
//                                                         `List-Unsubscribe=One-Click`) ya da gövdede (`t`, onay sayfasındaki form) olabilir
//
// Belirteç = "<adres özeti>.<HMAC>" (announcement_email_security.js): adrese bağlı, süresiz, düz adres İÇERMEZ; sayfada adres gösterilmez.
// Çıkış `announcement_email_suppressions`'a yazılır: adres (KANONİK biçimiyle: +etiket / gmail noktaları önemsiz) sonraki duyurularda
// 'skipped_pref' olur (acil dahil; hesapsız alıcı için başka kanal yok). POST YALNIZ bastırma kaydını yazar (ve gönderimi başlamamış bekleyen
// e-postaları indeksle kapatır): kullanıcı / daire tablosu TARANMAZ ve bildirim tercihi UPDATE'i YOKTUR (geçerli belirteçle bile ucuz;
// yanlış hesabın tercihi kapanmaz). Uygulamadaki ayar bastırmayı GET /app/notification-preferences'ta HESAPLANAN etkin değerle yansıtır;
// geri alma: uygulamada tercih "açık" yapılır (announcement_inbox.js setNotificationPreferences, yalnız doğrulanmış hesap e-postası).
//
// HIZ SINIRI (E5): posta sağlayıcıları (Google / Yahoo vb.) tek tık POST'larını ortak IP havuzlarından gönderir; sıkı IP sınırı geçerli
// belirteçleri 429'a düşürüp çıkışı uygulatmazdı. Bu yüzden ÖNCE imza ucuzca doğrulanır:
//   - GEÇERSİZ belirteç: sıkı IP sınırı (GET 120/saat, POST 30/saat) - tarama / kaba kuvvet buradan kısıtlanır;
//   - GEÇERLİ belirteç: adres özeti başına makul sınır (işlem idempotent) + geniş bir IP üst sınırı (yazma yükünü sınırlar).
// Tüm yanıtlar (429 dahil) sıkı CSP + no-store ile gider.

import express from 'express';
import { pool } from '../db.js';
import { createRuleLimiter } from '../middlewares/rate_limiters.js';
import { verifyUnsubscribeToken } from './announcement_email_security.js';
import { HOUR_MS, ipKey } from './route_helpers.js';

export const announcementPublicRouter = express.Router();

const MESSAGE = 'Çok fazla istek. Biraz sonra tekrar deneyin.';
const digestKey = (req) => (req.unsubscribeDigest ? `d:${req.unsubscribeDigest}` : null);

/** GEÇERSİZ belirteçli GET: IP başına 120/saat. */
export const unsubscribeViewLimiter = createRuleLimiter({ rules: [{ windowMs: HOUR_MS, max: 120, key: ipKey }], message: MESSAGE });
/** GEÇERSİZ belirteçli POST: IP başına 30/saat. */
export const unsubscribeApplyLimiter = createRuleLimiter({ rules: [{ windowMs: HOUR_MS, max: 30, key: ipKey }], message: MESSAGE });
/** GEÇERLİ belirteçli GET: adres özeti başına 60/saat, IP başına 1800/saat. */
export const unsubscribeViewValidLimiter = createRuleLimiter({
  rules: [{ windowMs: HOUR_MS, max: 60, key: digestKey }, { windowMs: HOUR_MS, max: 1800, key: ipKey }],
  message: MESSAGE,
});
/** GEÇERLİ belirteçli POST: adres özeti başına 20/saat, IP başına 600/saat (posta sağlayıcı havuzları). */
export const unsubscribeApplyValidLimiter = createRuleLimiter({
  rules: [{ windowMs: HOUR_MS, max: 20, key: digestKey }, { windowMs: HOUR_MS, max: 600, key: ipKey }],
  message: MESSAGE,
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
    <p>Bu e-posta adresine bundan sonra site duyuru ve borç hatırlatma e-postaları gönderilmeyecek. Uygulamayı kullanıyorsanız duyurularınızı uygulamada görmeye devam edersiniz. Fikrinizi değiştirirseniz uygulamadaki Bildirim Tercihleri'nden e-posta bildirimlerini yeniden açabilirsiniz.</p>`,
);

const ERROR_PAGE = page(
  'İşlem tamamlanamadı',
  `    <h1>İşlem tamamlanamadı</h1>
    <p>Şu anda isteğiniz işlenemedi. Lütfen biraz sonra bağlantıyı yeniden açın.</p>`,
);

const RATE_PAGE = page(
  'Çok fazla istek',
  `    <h1>Çok fazla istek</h1>
    <p>Kısa sürede çok fazla istek gönderildi. Lütfen biraz sonra bağlantıyı yeniden açın.</p>`,
);

function confirmPage(token) {
  // Belirteç yalnız [0-9a-f], '.', base64url karakterlerinden oluşur (verifyUnsubscribeToken doğruladı): HTML'e güvenle girer.
  return page(
    'Abonelikten çık',
    `    <h1>Duyuru ve borç hatırlatma e-postalarından çıkmak istiyor musunuz?</h1>
    <p>Onaylarsanız bu e-posta adresine site yönetiminin duyuru ve borç hatırlatma e-postaları artık gönderilmeyecek (acil duyurular dahil).</p>
    <form method="post" action="/public/announcement-unsubscribe">
      <input type="hidden" name="t" value="${token}" />
      <button type="submit">Evet, abonelikten çık</button>
    </form>`,
  );
}

function setPageHeaders(res) {
  res.setHeader('Content-Security-Policy', PAGE_CSP);
  res.setHeader('Cache-Control', 'no-store');
  res.setHeader('X-Robots-Tag', 'noindex');
}

function sendPage(res, status, html) {
  setPageHeaders(res);
  return res.status(status).type('html').send(html);
}

// Bu yoldaki HER yanıt (hız sınırı 429'u ve beklenmeyen hata dahil) sayfa güvenlik başlıklarıyla gider.
announcementPublicRouter.use('/public/announcement-unsubscribe', (_req, res, next) => {
  setPageHeaders(res);
  next();
});

const tokenOf = (req) => {
  const fromQuery = typeof req.query?.t === 'string' ? req.query.t : null;
  const fromBody = req.body && typeof req.body === 'object' && typeof req.body.t === 'string' ? req.body.t : null;
  return fromQuery ?? fromBody;
};

/** Hız sınırlayıcıyı yanıt yazmadan çalıştırır: { passed, retryAfter }. (createRuleLimiter eşzamanlı çalışır.) */
function gate(limiter, req) {
  let passed = false;
  const headers = {};
  const probe = {
    setHeader(name, value) {
      headers[name] = value;
    },
    status() {
      return probe;
    },
    json() {
      return probe;
    },
  };
  limiter(req, probe, () => {
    passed = true;
  });
  return { passed, retryAfter: headers['Retry-After'] };
}

function tooMany(res, retryAfter) {
  if (retryAfter) {
    res.setHeader('Retry-After', retryAfter);
  }
  return sendPage(res, 429, RATE_PAGE);
}

/** İmzayı ucuzca doğrular; geçersizse SIKI IP sınırı, geçerliyse adres özeti başına sınır uygular. { digest } | { response } */
function admit(req, res, { invalidLimiter, validLimiter }) {
  const token = tokenOf(req);
  const digest = verifyUnsubscribeToken(token);
  if (digest === null) {
    const result = gate(invalidLimiter, req);
    return { response: result.passed ? sendPage(res, 400, INVALID_PAGE) : tooMany(res, result.retryAfter) };
  }
  req.unsubscribeDigest = digest;
  const result = gate(validLimiter, req);
  if (!result.passed) {
    return { response: tooMany(res, result.retryAfter) };
  }
  return { digest, token };
}

announcementPublicRouter.get('/public/announcement-unsubscribe', (req, res) => {
  const admitted = admit(req, res, { invalidLimiter: unsubscribeViewLimiter, validLimiter: unsubscribeViewValidLimiter });
  if (admitted.response) {
    return admitted.response;
  }
  return sendPage(res, 200, confirmPage(admitted.token));
});

announcementPublicRouter.post('/public/announcement-unsubscribe', async (req, res) => {
  const admitted = admit(req, res, { invalidLimiter: unsubscribeApplyLimiter, validLimiter: unsubscribeApplyValidLimiter });
  if (admitted.response) {
    return admitted.response;
  }
  const emailHash = admitted.digest;
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
