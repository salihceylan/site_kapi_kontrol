// Geçiş Kontrol (door_control) modülünün kapı açma yollarındaki koruması için saf yardımcılar.
// DB/ağ bağımsızdır (door_access_policy.js ve rotalar bunu kullanır).
//
// Sözleşme: kapıyı getiren SELECT'ler `module_door_control` (boolean) alanını üretir
// (`COALESCE(site_modules.enabled, TRUE)`). Alan YOKSA (eski testler/çağrılar) politika "açık" sayar;
// yalnızca AÇIKÇA `false` olan engeller.

import { DOOR_CONTROL_MODULE } from './catalog.js';

export const MODULE_DISABLED_CODE = 'MODULE_DISABLED';
export const MODULE_DISABLED_MESSAGE = 'Geçiş Kontrol modülü kapalı.';
export const MODULE_DISABLED_REASON = 'module_disabled';

/** Kapının sitesinde Geçiş Kontrol modülü AÇIKÇA kapalı mı? */
export function isDoorModuleDisabled(door) {
  return Boolean(door) && typeof door === 'object' && door.module_door_control === false;
}

/** 403 yanıt gövdesi: { error, code, module }. */
export function moduleDisabledBody() {
  return { error: MODULE_DISABLED_MESSAGE, code: MODULE_DISABLED_CODE, module: DOOR_CONTROL_MODULE };
}

/**
 * Hata nesnesinin (politika hatası) yanıta eklenecek `module` alanı. Yalnızca modül hatalarında vardır.
 * @returns {{ module: string } | {}}
 */
export function moduleFieldOf(error) {
  return typeof error?.module === 'string' && error.module ? { module: error.module } : {};
}

/**
 * Kapalı modül için kibar (HTML) bilgi sayfası: kapı açma düğmesi YOKTUR. Misafir bağlantısı (/guest/:token).
 * @param {{ nonce: string, siteName?: string|null, escapeHtml: (v: unknown) => string }} input
 */
export function renderModuleDisabledGuestPage({ nonce, siteName = null, escapeHtml }) {
  const safeNonce = escapeHtml(nonce);
  const site = siteName ? `<p class="site">${escapeHtml(siteName)}</p>` : '';
  return `<!DOCTYPE html>
<html lang="tr">
<head>
  <meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1">
  <title>Geçiş Şu Anda Kullanılamıyor</title>
  <style nonce="${safeNonce}">
    body{font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif;background:#f1f5f9;display:flex;align-items:center;justify-content:center;min-height:100vh;margin:0;padding:16px;box-sizing:border-box;}
    .card{background:#fff;border-radius:24px;padding:32px;text-align:center;box-shadow:0 10px 30px rgba(0,0,0,0.08);max-width:400px;width:100%;box-sizing:border-box;}
    h2{color:#0f172a;margin:0 0 8px;overflow-wrap:anywhere;}
    .site{color:#334155;font-weight:600;overflow-wrap:anywhere;}
    p{color:#64748b;font-size:15px;line-height:1.5;}
  </style>
</head>
<body>
  <div class="card">
    <h2>Geçiş şu anda kullanılamıyor</h2>
    ${site}
    <p>Bu sitede geçiş kontrolü yönetim tarafından geçici olarak kapatılmıştır. Lütfen site yönetimiyle iletişime geçin.</p>
  </div>
</body>
</html>`;
}
