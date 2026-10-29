// Dis firma teklif formu sayfasi (113, P2-8): kimlik gerektirmeyen, belirtec ile acilan TEK SAYFA (sunucu tarafinda uretilir; Flutter uygulamasindan bagimsizdir).
//
// Guvenlik: misafir gecis sayfasiyla (utils/guest_pass_utils.js) ayni katı CSP (default-src 'none'; betik ve stil yalniz nonce ile; form-action 'none'; cerceve yok),
// Referrer-Policy: no-referrer, no-store, noindex. Sunucudan gelen her deger (site adi, konu, beklenen firma, belirtec) HTML'e escapeHtml ile girer; istemci betigi
// sunucu / ag metinlerini innerHTML ile DEGIL textContent ile yazar. Betik inline olay islevi icermez; gonderim fetch ile POST /public/quote-forms/:token'dir.
// Bu dosya veritabanina ya da servislere bagimli degildir (saf uretim; test: equipment_quote_requests).

import { escapeHtml, generateCspNonce, guestPageHeaders } from '../utils/guest_pass_utils.js';

export { generateCspNonce };

/** Misafir sayfasiyla ayni basliklar: CSP (nonce), no-store, no-referrer, noindex. */
export const quoteFormPageHeaders = (nonce) => guestPageHeaders(nonce);

const trDate = (iso) => {
  try {
    return new Date(iso).toLocaleDateString('tr-TR', { timeZone: 'Europe/Istanbul', day: '2-digit', month: '2-digit', year: 'numeric' });
  } catch {
    return String(iso ?? '').slice(0, 10);
  }
};

const STYLE = `
  * { box-sizing: border-box; }
  body { margin: 0; padding: 20px 16px 40px; background: #f1f5f9; color: #0f172a; font: 16px/1.5 -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; }
  main { max-width: 520px; margin: 0 auto; background: #ffffff; border-radius: 20px; padding: 24px 20px; box-shadow: 0 8px 28px rgba(15, 23, 42, 0.08); }
  .badge { display: inline-block; margin: 0 0 12px; padding: 4px 12px; border-radius: 999px; background: #dbeafe; color: #1e3a8a; font-size: 13px; font-weight: 600; }
  h1 { margin: 0 0 4px; font-size: 22px; line-height: 1.25; overflow-wrap: anywhere; }
  h2 { margin: 0 0 8px; font-size: 20px; }
  .topic { margin: 0 0 12px; overflow-wrap: anywhere; }
  .hint { margin: 0 0 20px; color: #475569; font-size: 14px; }
  label { display: block; margin: 16px 0 6px; font-weight: 600; font-size: 15px; }
  .req { color: #475569; font-weight: 400; font-size: 13px; }
  input[type="text"], input[type="tel"], input[type="date"], textarea { width: 100%; padding: 12px; border: 1px solid #64748b; border-radius: 12px; background: #ffffff; color: #0f172a; font: inherit; }
  textarea { resize: vertical; }
  input:focus, textarea:focus, button:focus { outline: 3px solid #2563eb; outline-offset: 2px; }
  fieldset { margin: 16px 0 0; padding: 0; border: 0; }
  legend { padding: 0; margin: 0 0 4px; font-weight: 600; font-size: 15px; }
  .choice { display: flex; align-items: center; gap: 10px; margin: 0; padding: 8px 0; font-weight: 400; }
  .choice input { width: 20px; height: 20px; }
  button { display: block; width: 100%; margin-top: 24px; padding: 14px; border: 0; border-radius: 14px; background: #1d4ed8; color: #ffffff; font: inherit; font-weight: 700; cursor: pointer; }
  button:disabled { background: #64748b; cursor: not-allowed; }
  .status { min-height: 24px; margin-top: 16px; }
  .error { margin: 0; color: #b91c1c; font-weight: 600; }
  .ok { margin: 0 0 8px; color: #166534; font-weight: 600; }
  .muted { margin: 0; color: #475569; font-size: 14px; }
`;

const FORM_SCRIPT = String.raw`
(function () {
  var form = document.getElementById('quoteForm');
  if (!form) { return; }
  var token = form.getAttribute('data-token') || '';
  var statusEl = document.getElementById('status');
  var sendBtn = document.getElementById('send');
  var busy = false;

  function say(kind, text) {
    statusEl.textContent = '';
    if (!text) { return; }
    var el = document.createElement('p');
    el.className = kind;
    el.textContent = text;
    statusEl.appendChild(el);
  }

  function val(id) { return (document.getElementById(id).value || '').trim(); }

  // Tutar: "12.500,50", "12500,5", "12500.50", "12.500" -> kurus (tam sayi). Belirsizse null.
  function parseKurus(raw) {
    var t = String(raw || '').replace(/\s+/g, '').replace(/tl|₺/gi, '');
    if (!/^[0-9.,]+$/.test(t)) { return null; }
    var intPart = t;
    var frac = '';
    var comma = t.lastIndexOf(',');
    var dot = t.lastIndexOf('.');
    if (comma >= 0) {
      intPart = t.slice(0, comma);
      frac = t.slice(comma + 1);
    } else if (dot >= 0 && t.indexOf('.') === dot && t.length - dot - 1 <= 2) {
      intPart = t.slice(0, dot);
      frac = t.slice(dot + 1);
    }
    if (intPart.indexOf(',') >= 0 || frac.indexOf('.') >= 0 || frac.length > 2) { return null; }
    if (intPart.indexOf('.') >= 0) {
      if (!/^[0-9]{1,3}(\.[0-9]{3})+$/.test(intPart)) { return null; }
      intPart = intPart.replace(/\./g, '');
    }
    if (!/^[0-9]+$/.test(intPart) || (frac !== '' && !/^[0-9]+$/.test(frac))) { return null; }
    var kurus = Number(intPart) * 100 + Number((frac + '00').slice(0, 2));
    if (!isFinite(kurus) || kurus < 1 || kurus > 1000000000000) { return null; }
    return kurus;
  }

  function formatTl(kurus) {
    var lira = Math.floor(kurus / 100);
    var kr = kurus % 100;
    return String(lira).replace(/\B(?=(\d{3})+(?!\d))/g, '.') + ',' + (kr < 10 ? '0' : '') + kr + ' TL';
  }

  function showDone(kurus) {
    var main = document.getElementById('formArea');
    main.textContent = '';
    var h = document.createElement('h2');
    h.textContent = 'Teklifiniz iletildi';
    var a = document.createElement('p');
    a.className = 'ok';
    a.textContent = 'Gönderilen tutar: ' + formatTl(kurus);
    var b = document.createElement('p');
    b.className = 'muted';
    b.textContent = 'Site yönetimi teklifinizi inceleyecek. Bu bağlantı artık kullanılamaz; yeni bir teklif için yönetimden yeni bağlantı isteyin.';
    main.appendChild(h);
    main.appendChild(a);
    main.appendChild(b);
  }

  form.addEventListener('submit', function (event) {
    event.preventDefault();
    if (busy) { return; }
    var name = val('vendor_name');
    if (name === '') { say('error', 'Firma adını yazın.'); return; }
    var kurus = parseKurus(val('amount'));
    if (kurus === null) { say('error', 'Tutarı 12.500,00 gibi yazın (en az 0,01 TL).'); return; }
    var body = { vendor_name: name, amount_kurus: kurus };
    var contact = val('vendor_contact');
    var phone = val('vendor_phone');
    var validUntil = val('valid_until');
    var days = val('delivery_days');
    var note = val('note');
    if (contact !== '') { body.vendor_contact = contact; }
    if (phone !== '') { body.vendor_phone = phone; }
    if (validUntil !== '') { body.valid_until = validUntil; }
    if (days !== '') {
      if (!/^[0-9]{1,4}$/.test(days)) { say('error', 'Teslim süresini gün olarak tam sayı yazın.'); return; }
      body.delivery_days = Number(days);
    }
    if (note !== '') { body.note = note; }
    var vat = form.querySelector('input[name="vat"]:checked');
    if (vat && vat.value === 'included') { body.vat_included = true; }
    if (vat && vat.value === 'excluded') { body.vat_included = false; }

    busy = true;
    sendBtn.disabled = true;
    say('muted', 'Gönderiliyor...');
    fetch('/public/quote-forms/' + encodeURIComponent(token), {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body)
    }).then(function (res) {
      return res.json().catch(function () { return {}; }).then(function (data) { return { res: res, data: data }; });
    }).then(function (r) {
      if (r.res.status === 201) { showDone(kurus); return; }
      say('error', (r.data && r.data.error) ? r.data.error : 'Teklif gönderilemedi. Daha sonra tekrar deneyin.');
      if (r.res.status !== 410) { busy = false; sendBtn.disabled = false; }
    }).catch(function () {
      say('error', 'Sunucuya bağlanılamadı. İnternet bağlantınızı kontrol edip tekrar deneyin.');
      busy = false;
      sendBtn.disabled = false;
    });
  });
})();
`;

const shell = ({ nonce, title, body, script = '' }) => `<!DOCTYPE html>
<html lang="tr">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex, nofollow">
<title>${escapeHtml(title)}</title>
<style nonce="${escapeHtml(nonce)}">${STYLE}</style>
</head>
<body>
${body}
${script ? `<script nonce="${escapeHtml(nonce)}">${script}</script>` : ''}
</body>
</html>`;

/** Bağlantı kullanılamıyorsa gösterilen sayfa (bilinmeyen, kullanılmış, süresi dolmuş, iptal: ayırt edilmez). */
export function renderQuoteFormUnusablePage({ nonce, message = 'Bu form bağlantısı geçersiz, süresi dolmuş, iptal edilmiş ya da daha önce kullanılmış. Yeni bir bağlantı için site yönetimiyle iletişime geçin.' }) {
  return shell({
    nonce,
    title: 'Teklif formu kullanılamıyor',
    body: `<main><p class="badge">Teklif formu</p><h1>Bağlantı kullanılamıyor</h1><p class="topic">${escapeHtml(message)}</p></main>`,
  });
}

/** Teklif formu. form = { topic, site_name, vendor_hint, expires_at }; token yalniz gonderim adresi icin `data-token` niteligine yazilir. */
export function renderQuoteFormPage({ nonce, token, form }) {
  const site = escapeHtml(form.site_name || 'Site yönetimi');
  const topic = escapeHtml(form.topic);
  const hint = escapeHtml(form.vendor_hint ?? '');
  const until = escapeHtml(trDate(form.expires_at));
  const body = `<main id="formArea">
<p class="badge">Teklif formu</p>
<h1>${site}</h1>
<p class="topic">Konu: <strong>${topic}</strong></p>
<p class="hint">Bu bağlantı yalnızca bir kez kullanılabilir ve ${until} tarihine kadar geçerlidir. Gönderdiğiniz teklif site yönetiminin incelemesine düşer; yönetim onaylamadan hiçbir kayıt oluşmaz. Yazdığınız firma, yetkili ve telefon bilgileri yalnızca bu teklifi değerlendirmek için site yönetimine iletilir.</p>
<form id="quoteForm" novalidate data-token="${escapeHtml(token)}">
<label for="vendor_name">Firma adı <span class="req">(zorunlu)</span></label>
<input id="vendor_name" type="text" maxlength="120" required autocomplete="organization" value="${hint}">
<label for="vendor_contact">Yetkili kişi</label>
<input id="vendor_contact" type="text" maxlength="80" autocomplete="name">
<label for="vendor_phone">Telefon</label>
<input id="vendor_phone" type="tel" maxlength="32" autocomplete="tel" inputmode="tel">
<label for="amount">Teklif tutarı (TL) <span class="req">(zorunlu)</span></label>
<input id="amount" type="text" inputmode="decimal" placeholder="Örn. 12.500,00" required>
<fieldset>
<legend>KDV</legend>
<label class="choice"><input type="radio" name="vat" value="included"> KDV dahil</label>
<label class="choice"><input type="radio" name="vat" value="excluded"> KDV hariç</label>
<label class="choice"><input type="radio" name="vat" value="" checked> Belirtmek istemiyorum</label>
</fieldset>
<label for="valid_until">Teklifin geçerlilik tarihi</label>
<input id="valid_until" type="date">
<label for="delivery_days">Teslim süresi (gün)</label>
<input id="delivery_days" type="text" inputmode="numeric" maxlength="4">
<label for="note">Kapsam / not</label>
<textarea id="note" maxlength="500" rows="4"></textarea>
<div id="status" class="status" role="status" aria-live="polite"></div>
<button id="send" type="submit">Teklifi gönder</button>
</form>
<noscript><p class="error">Bu form JavaScript gerektirir. Lütfen tarayıcınızda JavaScript'i açın.</p></noscript>
</main>`;
  return shell({ nonce, title: `${form.site_name || 'Site yönetimi'} - Teklif formu`, body, script: FORM_SCRIPT });
}
