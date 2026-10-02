// Misafir / kurye gecis linki: girdi dogrulama, durum siniflandirma, atomik tuketim SQL'i
// ve /guest/:token HTML sayfasinin (kacisli) uretimi. DB/MQTT'ye bagimli degildir.

import crypto from 'crypto';
import { parseId } from './ids.js';
import { sanitizeDisplayText } from './site_rules.js';

export const GUEST_PASS_TYPES = Object.freeze(['single_use', 'time_limited']);
export const GUEST_PASS_TITLE_MAX = 80;
export const GUEST_PASS_MAX_USES_LIMIT = 50;
export const GUEST_PASS_DEFAULT_TITLE = 'Misafir / Kurye';
export const GUEST_PASS_MIN_MINUTES = 5;
export const GUEST_PASS_MAX_MINUTES = 1440;

// Token'lar crypto.randomBytes(24).toString('hex') ile uretilir; eski/elle uretilmis
// kayitlara karsi esnek (yalniz URL-guvenli karakterler, 16..128 uzunluk).
const TOKEN_PATTERN = /^[A-Za-z0-9_-]{16,128}$/;

export function isWellFormedGuestToken(token) {
  return typeof token === 'string' && TOKEN_PATTERN.test(token);
}

export function escapeHtml(value) {
  return String(value ?? '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;')
    .replace(/`/g, '&#96;');
}

/**
 * POST /app/guest-passes govdesini dogrular/normalize eder.
 * @returns {{ ok: true, value: { doorId: number, title: string, passType: string,
 *             durationMinutes: number, maxUses: number } } | { ok: false, error: string }}
 */
export function normalizeGuestPassInput(body) {
  const source = body && typeof body === 'object' ? body : {};

  const doorId = parseId(source.door_id);
  if (doorId === null) {
    return { ok: false, error: 'Gecerli bir kapi secin.' };
  }

  const title = sanitizeDisplayText(source.title, GUEST_PASS_TITLE_MAX) || GUEST_PASS_DEFAULT_TITLE;

  const rawType = source.pass_type;
  const passType = rawType === undefined || rawType === null || String(rawType).trim() === ''
    ? 'single_use'
    : String(rawType).trim();
  if (!GUEST_PASS_TYPES.includes(passType)) {
    return { ok: false, error: 'Gecersiz gecis turu.' };
  }

  const defaultMinutes = passType === 'single_use' ? 30 : 120;
  let durationMinutes = defaultMinutes;
  const rawDuration = source.duration_minutes;
  if (rawDuration !== undefined && rawDuration !== null && String(rawDuration).trim() !== '' && Number(rawDuration) !== 0) {
    const parsed = Number(rawDuration);
    if (!Number.isFinite(parsed)) {
      return { ok: false, error: 'Gecersiz gecis suresi.' };
    }
    durationMinutes = Math.max(GUEST_PASS_MIN_MINUTES, Math.min(GUEST_PASS_MAX_MINUTES, Math.floor(parsed)));
  }

  let maxUses = 1;
  if (passType !== 'single_use') {
    maxUses = 10;
    const rawMaxUses = source.max_uses;
    if (rawMaxUses !== undefined && rawMaxUses !== null && String(rawMaxUses).trim() !== '' && Number(rawMaxUses) !== 0) {
      const parsed = Number(rawMaxUses);
      if (!Number.isFinite(parsed)) {
        return { ok: false, error: 'Gecersiz kullanim limiti.' };
      }
      maxUses = Math.max(1, Math.min(GUEST_PASS_MAX_USES_LIMIT, Math.floor(parsed)));
    }
  }

  return { ok: true, value: { doorId, title, passType, durationMinutes, maxUses } };
}

/**
 * Tek kullanimlik hak tuketimi ATOMIKTIR: kosullar UPDATE'in WHERE kisminda; satir donmezse
 * (iptal/sure dolmus/limit dolmus/baska istek kazandi) kapi acilmaz. is_active'e dokunulmaz,
 * boylece pulse basarisiz olunca sayac geri alinirken iptal edilmis bir link yeniden aktiflesmez.
 * Tukenmis link, used_count >= max_uses ile anlasilir.
 */
export const CLAIM_GUEST_PASS_SQL = `
  UPDATE guest_passes
  SET used_count = used_count + 1
  WHERE id = $1
    AND is_active = TRUE
    AND used_count < max_uses
    AND (pass_type <> 'single_use' OR used_count < 1)
    AND expires_at > NOW()
  RETURNING id, used_count, max_uses, pass_type, expires_at
`;

/** Pulse gonderilemediyse hak iade edilir. */
export const RELEASE_GUEST_PASS_SQL = `
  UPDATE guest_passes
  SET used_count = GREATEST(used_count - 1, 0)
  WHERE id = $1 AND used_count > 0
`;

/** @returns {'ok'|'revoked'|'expired'|'exhausted'} (oncelik: iptal > sure > limit) */
export function getGuestPassState(pass, now = new Date()) {
  if (!pass?.is_active) {
    return 'revoked';
  }
  if (new Date(pass.expires_at) < now) {
    return 'expired';
  }
  if (Number(pass.used_count) >= Number(pass.max_uses)) {
    return 'exhausted';
  }
  return 'ok';
}

export const GUEST_PASS_STATE_RESPONSES = Object.freeze({
  revoked: { status: 410, error: 'Bu gecis linki iptal edilmis.' },
  expired: { status: 410, error: 'Bu gecis linkinin suresi dolmus.' },
  exhausted: { status: 410, error: 'Bu tek kullanimlik gecis linki daha once kullanilmis.' },
});

// ---------------------------------------------------------------------------
// HTML sayfasi
// ---------------------------------------------------------------------------

export function generateCspNonce() {
  return crypto.randomBytes(16).toString('base64');
}

export function buildGuestPageCsp(nonce) {
  return [
    "default-src 'none'",
    `script-src 'nonce-${nonce}'`,
    `style-src 'nonce-${nonce}'`,
    "connect-src 'self'",
    "base-uri 'none'",
    "form-action 'none'",
    "frame-ancestors 'none'",
  ].join('; ');
}

export function guestPageHeaders(nonce) {
  return {
    'Content-Type': 'text/html; charset=utf-8',
    'Content-Security-Policy': buildGuestPageCsp(nonce),
    'Cache-Control': 'no-store',
    'Referrer-Policy': 'no-referrer',
    'X-Content-Type-Options': 'nosniff',
    'X-Robots-Tag': 'noindex, nofollow',
  };
}

export function renderInvalidGuestPassPage({ nonce }) {
  const safeNonce = escapeHtml(nonce);
  return `
        <!DOCTYPE html>
        <html lang="tr">
        <head>
          <meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1">
          <title>Gecersiz Gecis Linki</title>
          <style nonce="${safeNonce}">
            body{font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif;background:#f1f5f9;display:flex;align-items:center;justify-content:center;height:100vh;margin:0;padding:16px;}
            .card{background:#fff;border-radius:24px;padding:32px;text-align:center;box-shadow:0 10px 30px rgba(0,0,0,0.08);max-width:400px;width:100%;}
            h2{color:#e11d48;margin:0 0 8px;}
            p{color:#64748b;font-size:15px;line-height:1.5;}
          </style>
        </head>
        <body>
          <div class="card">
            <h2>⚠️ Gecersiz Link</h2>
            <p>Bu gecis baglantisi bulunamadi veya suresi dolmus.</p>
          </div>
        </body>
        </html>
      `;
}

// Istemci betigi: inline onclick yok (CSP nonce ile calisir), token data-* niteliginden okunur,
// sunucu/ag metinleri innerHTML yerine textContent ile yazilir.
const GUEST_PAGE_SCRIPT = `
        (function () {
          var btn = document.getElementById('openBtn');
          var msg = document.getElementById('statusMsg');
          if (!btn || !msg) { return; }
          var token = btn.getAttribute('data-token') || '';
          var singleUse = btn.getAttribute('data-single-use') === '1';
          var loading = false;

          function setButton(icon, label) {
            btn.textContent = '';
            var iconEl = document.createElement('span');
            iconEl.className = 'icon';
            iconEl.textContent = icon;
            var labelEl = document.createElement('span');
            labelEl.textContent = label;
            btn.appendChild(iconEl);
            btn.appendChild(labelEl);
          }

          function setMessage(className, text) {
            msg.textContent = '';
            if (!text) { return; }
            var el = document.createElement('span');
            el.className = className;
            el.textContent = text;
            msg.appendChild(el);
          }

          async function openDoor() {
            if (loading) { return; }
            loading = true;
            btn.disabled = true;
            setButton('\\u23F3', 'ACILIYOR...');
            setMessage('', '');

            try {
              var res = await fetch('/public/guest-pass/' + encodeURIComponent(token) + '/open', { method: 'POST' });
              var data = {};
              try { data = await res.json(); } catch (e) { data = {}; }
              if (res.ok) {
                setButton('\\u2705', 'ACILDI');
                setMessage('success', 'Kapi acildi, gecebilirsiniz!');
                setTimeout(function () {
                  if (singleUse) {
                    btn.disabled = true;
                  } else {
                    btn.disabled = false;
                    setButton('\\uD83D\\uDEAA', 'KAPIYI AC');
                    loading = false;
                  }
                }, 3000);
              } else {
                throw new Error(data.error || 'Islem basarisiz.');
              }
            } catch (err) {
              setButton('\\u274C', 'HATA');
              setMessage('error', (err && err.message) ? err.message : 'Islem basarisiz.');
              setTimeout(function () {
                btn.disabled = false;
                setButton('\\uD83D\\uDEAA', 'TEKRAR DENE');
                loading = false;
              }, 2500);
            }
          }

          btn.addEventListener('click', openDoor);
        })();
`;

/**
 * @param {{ pass: object, nonce: string, now?: Date }} input
 * pass: guest_passes satiri + site_name + door_name
 */
export function renderGuestPassPage({ pass, nonce, now = new Date() }) {
  const safeNonce = escapeHtml(nonce);
  const isExpired = new Date(pass.expires_at) < now;
  const maxUses = Number(pass.max_uses) || 0;
  const usedCount = Number(pass.used_count) || 0;
  const isExhausted = usedCount >= maxUses;
  const isRevoked = !pass.is_active;
  const isUsable = !isRevoked && !isExpired && !isExhausted;
  const isSingleUse = pass.pass_type === 'single_use';

  const siteName = escapeHtml(pass.site_name);
  const doorName = escapeHtml(pass.door_name);
  const title = escapeHtml(pass.title || 'Misafir');
  const token = escapeHtml(pass.token);

  return `
      <!DOCTYPE html>
      <html lang="tr">
      <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no">
        <title>${siteName} - ${doorName} Gecis</title>
        <style nonce="${safeNonce}">
          * { box-sizing: border-box; margin: 0; padding: 0; font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "Segoe UI", Roboto, sans-serif; }
          body { background: linear-gradient(145deg, #0f172a, #1e293b); min-height: 100vh; display: flex; align-items: center; justify-content: center; padding: 20px; color: #fff; }
          .pass-container { background: rgba(255, 255, 255, 0.08); backdrop-filter: blur(20px); border: 1px solid rgba(255, 255, 255, 0.15); border-radius: 28px; width: 100%; max-width: 420px; padding: 36px 24px; text-align: center; box-shadow: 0 20px 50px rgba(0,0,0,0.3); }
          .badge { display: inline-block; padding: 6px 14px; border-radius: 999px; background: rgba(59, 130, 246, 0.2); border: 1px solid rgba(59, 130, 246, 0.4); color: #93c5fd; font-size: 13px; font-weight: 600; margin-bottom: 20px; text-transform: uppercase; letter-spacing: 0.5px; }
          h1 { font-size: 24px; font-weight: 800; margin-bottom: 6px; color: #f8fafc; overflow-wrap: anywhere; }
          .door-title { font-size: 17px; color: #94a3b8; margin-bottom: 30px; overflow-wrap: anywhere; }
          .trigger-btn { width: 180px; height: 180px; border-radius: 50%; border: none; background: linear-gradient(135deg, #2563eb, #1d4ed8); color: #fff; font-size: 18px; font-weight: 700; cursor: pointer; box-shadow: 0 10px 30px rgba(37, 99, 235, 0.4), inset 0 2px 4px rgba(255, 255, 255, 0.3); transition: all 0.2s ease; display: inline-flex; flex-direction: column; align-items: center; justify-content: center; gap: 8px; margin: 10px 0 24px; }
          .trigger-btn:active { transform: scale(0.95); }
          .trigger-btn:disabled { background: #475569; box-shadow: none; cursor: not-allowed; opacity: 0.7; }
          .icon { font-size: 38px; }
          .status-msg { min-height: 28px; font-size: 15px; font-weight: 600; margin-top: 10px; }
          .success { color: #4ade80; }
          .error { color: #f87171; }
          .info-box { margin-top: 24px; padding: 12px; background: rgba(0,0,0,0.2); border-radius: 14px; font-size: 12px; color: #94a3b8; overflow-wrap: anywhere; }
        </style>
      </head>
      <body>
        <div class="pass-container">
          <div class="badge">${isSingleUse ? 'Tek Kullanimlik' : 'Sureli Gecis'}</div>
          <h1>${siteName}</h1>
          <div class="door-title">${doorName}</div>

          <button id="openBtn" type="button" class="trigger-btn" data-token="${token}" data-single-use="${isSingleUse ? '1' : '0'}" ${!isUsable ? 'disabled' : ''}>
            <span class="icon">🚪</span>
            <span>KAPIYI AC</span>
          </button>

          <div id="statusMsg" class="status-msg">
            ${isRevoked ? '<span class="error">Bu baglanti iptal edilmis.</span>' : ''}
            ${isExpired ? '<span class="error">Baglantinin gecerlilik suresi dolmus.</span>' : ''}
            ${isExhausted ? '<span class="error">Kullanim limiti dolmus.</span>' : ''}
          </div>

          <div class="info-box">
            Bu link <b>${title}</b> adina olusturulmustur.<br>
            Kalan Kullanim: <b>${Math.max(0, maxUses - usedCount)}</b> / ${maxUses}
          </div>
        </div>

        <script nonce="${safeNonce}">${GUEST_PAGE_SCRIPT}</script>
      </body>
      </html>
    `;
}
