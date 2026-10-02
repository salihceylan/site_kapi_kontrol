import test from 'node:test';
import assert from 'node:assert/strict';
import {
  CLAIM_GUEST_PASS_SQL,
  GUEST_PASS_MAX_USES_LIMIT,
  GUEST_PASS_TITLE_MAX,
  RELEASE_GUEST_PASS_SQL,
  buildGuestPageCsp,
  escapeHtml,
  generateCspNonce,
  getGuestPassState,
  guestPageHeaders,
  isWellFormedGuestToken,
  normalizeGuestPassInput,
  renderGuestPassPage,
  renderInvalidGuestPassPage,
} from '../src/utils/guest_pass_utils.js';

const NOW = new Date('2026-06-01T12:00:00Z');

function makePass(overrides = {}) {
  return {
    id: 7,
    token: 'a'.repeat(48),
    title: 'Kurye',
    pass_type: 'single_use',
    is_active: true,
    max_uses: 1,
    used_count: 0,
    expires_at: new Date(NOW.getTime() + 30 * 60 * 1000),
    site_name: 'Yildiz Sitesi',
    door_name: 'Ana Kapi',
    ...overrides,
  };
}

test('escapeHtml: HTML ozel karakterlerini kacirir', () => {
  assert.equal(escapeHtml('<script>alert("x")</script>'), '&lt;script&gt;alert(&quot;x&quot;)&lt;/script&gt;');
  assert.equal(escapeHtml(`a&b'c\`d`), 'a&amp;b&#39;c&#96;d');
  assert.equal(escapeHtml(null), '');
  assert.equal(escapeHtml(undefined), '');
  assert.equal(escapeHtml(42), '42');
});

test('renderGuestPassPage: title/site_name/door_name/token kacirilir (XSS)', () => {
  const payload = '"><img src=x onerror=alert(1)><script>alert(2)</script>';
  const html = renderGuestPassPage({
    pass: makePass({
      title: payload,
      site_name: payload,
      door_name: payload,
      token: `tok${payload}`,
    }),
    nonce: 'NONCE123',
    now: NOW,
  });

  // Ham payload hicbir yerde bulunmamali
  assert.equal(html.includes('<img src=x'), false);
  assert.equal(html.includes('<script>alert(2)</script>'), false);
  assert.equal(html.includes('onerror=alert(1)>'), false);
  // Kacirilmis hali bulunmali
  assert.ok(html.includes('&lt;img src=x onerror=alert(1)&gt;'));
  assert.ok(html.includes('data-token="tok&quot;&gt;&lt;img'));

  // Yalnizca bizim nonce'lu <script> blogu var
  const scriptTags = html.match(/<script\b[^>]*>/g) || [];
  assert.equal(scriptTags.length, 1);
  assert.equal(scriptTags[0], '<script nonce="NONCE123">');
  const styleTags = html.match(/<style\b[^>]*>/g) || [];
  assert.deepEqual(styleTags, ['<style nonce="NONCE123">']);
});

test('renderGuestPassPage: inline olay isleyicisi yok, nonce kacirilir', () => {
  const html = renderGuestPassPage({ pass: makePass(), nonce: 'n"o', now: NOW });
  assert.equal(/\son[a-z]+\s*=/i.test(html.replace(/<script[\s\S]*?<\/script>/g, '')), false);
  assert.ok(html.includes('nonce="n&quot;o"'));
  assert.ok(html.includes('addEventListener'));
});

test('renderGuestPassPage: kullanilabilir/tukenmis/iptal/sure durumlari', () => {
  const usable = renderGuestPassPage({ pass: makePass(), nonce: 'n', now: NOW });
  assert.equal(/id="openBtn"[^>]*\sdisabled/.test(usable), false);
  assert.ok(usable.includes('data-single-use="1"'));
  assert.ok(usable.includes('Tek Kullanimlik'));
  assert.ok(usable.includes('Kalan Kullanim: <b>1</b> / 1'));

  const exhausted = renderGuestPassPage({ pass: makePass({ used_count: 1 }), nonce: 'n', now: NOW });
  assert.ok(/id="openBtn"[^>]*\sdisabled/.test(exhausted));
  assert.ok(exhausted.includes('Kullanim limiti dolmus.'));

  const revoked = renderGuestPassPage({ pass: makePass({ is_active: false }), nonce: 'n', now: NOW });
  assert.ok(/id="openBtn"[^>]*\sdisabled/.test(revoked));
  assert.ok(revoked.includes('Bu baglanti iptal edilmis.'));

  const expired = renderGuestPassPage({
    pass: makePass({ expires_at: new Date(NOW.getTime() - 1000) }),
    nonce: 'n',
    now: NOW,
  });
  assert.ok(/id="openBtn"[^>]*\sdisabled/.test(expired));
  assert.ok(expired.includes('Baglantinin gecerlilik suresi dolmus.'));

  const timed = renderGuestPassPage({
    pass: makePass({ pass_type: 'time_limited', max_uses: 5, used_count: 2 }),
    nonce: 'n',
    now: NOW,
  });
  assert.ok(timed.includes('data-single-use="0"'));
  assert.ok(timed.includes('Sureli Gecis'));
  assert.ok(timed.includes('Kalan Kullanim: <b>3</b> / 5'));
});

test('renderGuestPassPage: istemci betigi gecerli JavaScript ve token yalniz data-* uzerinden', () => {
  const html = renderGuestPassPage({ pass: makePass(), nonce: 'n', now: NOW });
  const match = html.match(/<script nonce="n">([\s\S]*)<\/script>/);
  assert.ok(match, 'script blogu bulunamadi');
  assert.doesNotThrow(() => new Function(match[1]));
  // Betik sunucu degiskeni enterpolasyonu icermez (token script icinde degil)
  assert.equal(match[1].includes('a'.repeat(48)), false);
  assert.ok(match[1].includes("getAttribute('data-token')"));
  // Sunucu/ag hata metni innerHTML ile yazilmaz
  assert.equal(match[1].includes('innerHTML'), false);
});

test('renderInvalidGuestPassPage: nonce\'lu stil ve sabit icerik', () => {
  const html = renderInvalidGuestPassPage({ nonce: 'abc' });
  assert.ok(html.includes('<style nonce="abc">'));
  assert.equal(/<script/i.test(html), false);
});

test('CSP basligi: nonce\'lu, unsafe-inline yok, framing/base/form kapali', () => {
  const nonce = generateCspNonce();
  assert.match(nonce, /^[A-Za-z0-9+/]{22}==$/);
  assert.notEqual(generateCspNonce(), generateCspNonce());

  const csp = buildGuestPageCsp(nonce);
  assert.ok(csp.includes("default-src 'none'"));
  assert.ok(csp.includes(`script-src 'nonce-${nonce}'`));
  assert.ok(csp.includes(`style-src 'nonce-${nonce}'`));
  assert.ok(csp.includes("connect-src 'self'"));
  assert.ok(csp.includes("frame-ancestors 'none'"));
  assert.ok(csp.includes("base-uri 'none'"));
  assert.ok(csp.includes("form-action 'none'"));
  assert.equal(csp.includes('unsafe-inline'), false);
  assert.equal(csp.includes('unsafe-eval'), false);

  const headers = guestPageHeaders(nonce);
  assert.equal(headers['Content-Security-Policy'], csp);
  assert.equal(headers['Cache-Control'], 'no-store');
  assert.equal(headers['Referrer-Policy'], 'no-referrer');
  assert.equal(headers['X-Content-Type-Options'], 'nosniff');
  assert.match(headers['Content-Type'], /^text\/html; charset=utf-8$/);
});

test('isWellFormedGuestToken', () => {
  assert.equal(isWellFormedGuestToken('a'.repeat(48)), true);
  assert.equal(isWellFormedGuestToken('A1_-'.repeat(8)), true);
  assert.equal(isWellFormedGuestToken('kisa'), false);
  assert.equal(isWellFormedGuestToken('a'.repeat(129)), false);
  assert.equal(isWellFormedGuestToken(`${'a'.repeat(20)}"><script>`), false);
  assert.equal(isWellFormedGuestToken(`${'a'.repeat(20)}/../x`), false);
  assert.equal(isWellFormedGuestToken(undefined), false);
  assert.equal(isWellFormedGuestToken(Number('12345678901234567')), false);
});

test('normalizeGuestPassInput: title temizlenir ve 80 karakterle sinirlanir', () => {
  const longTitle = `Merhaba\u0000\n\t${'x'.repeat(200)}`;
  const result = normalizeGuestPassInput({ door_id: 3, title: longTitle });
  assert.equal(result.ok, true);
  assert.ok(Array.from(result.value.title).length <= GUEST_PASS_TITLE_MAX);
  assert.equal(Array.from(result.value.title).some((ch) => ch.charCodeAt(0) < 32), false);
  assert.ok(result.value.title.startsWith('Merhaba x'));

  const empty = normalizeGuestPassInput({ door_id: 3, title: '   \n  ' });
  assert.equal(empty.value.title, 'Misafir / Kurye');
  const missing = normalizeGuestPassInput({ door_id: 3 });
  assert.equal(missing.value.title, 'Misafir / Kurye');

  // Emoji (vekil cifti) ortasindan bolunmez
  const emoji = normalizeGuestPassInput({ door_id: 3, title: '😀'.repeat(100) });
  assert.equal(Array.from(emoji.value.title).length, GUEST_PASS_TITLE_MAX);
});

test('normalizeGuestPassInput: pass_type allowlist', () => {
  assert.equal(normalizeGuestPassInput({ door_id: 1 }).value.passType, 'single_use');
  assert.equal(normalizeGuestPassInput({ door_id: 1, pass_type: 'time_limited' }).value.passType, 'time_limited');
  for (const bad of ['multi_use', 'admin', "single_use'; DROP TABLE", 'SINGLE_USE', 5, {}]) {
    const result = normalizeGuestPassInput({ door_id: 1, pass_type: bad });
    assert.equal(result.ok, false, `pass_type=${JSON.stringify(bad)} reddedilmeli`);
  }
});

test('normalizeGuestPassInput: max_uses <= 50, tek kullanimda 1', () => {
  assert.equal(normalizeGuestPassInput({ door_id: 1, pass_type: 'single_use', max_uses: 40 }).value.maxUses, 1);
  assert.equal(normalizeGuestPassInput({ door_id: 1, pass_type: 'time_limited', max_uses: 1000 }).value.maxUses, GUEST_PASS_MAX_USES_LIMIT);
  assert.equal(normalizeGuestPassInput({ door_id: 1, pass_type: 'time_limited', max_uses: -5 }).value.maxUses, 1);
  assert.equal(normalizeGuestPassInput({ door_id: 1, pass_type: 'time_limited', max_uses: 7.9 }).value.maxUses, 7);
  assert.equal(normalizeGuestPassInput({ door_id: 1, pass_type: 'time_limited' }).value.maxUses, 10);
  assert.equal(normalizeGuestPassInput({ door_id: 1, pass_type: 'time_limited', max_uses: null }).value.maxUses, 10);
  assert.equal(normalizeGuestPassInput({ door_id: 1, pass_type: 'time_limited', max_uses: 'abc' }).ok, false);
});

test('normalizeGuestPassInput: sure [5,1440] dk ve varsayilanlar (Flutter istemcisi null gonderir)', () => {
  assert.equal(normalizeGuestPassInput({ door_id: 1, pass_type: 'single_use', duration_minutes: null }).value.durationMinutes, 30);
  assert.equal(normalizeGuestPassInput({ door_id: 1, pass_type: 'time_limited', duration_minutes: null }).value.durationMinutes, 120);
  assert.equal(normalizeGuestPassInput({ door_id: 1, duration_minutes: 1 }).value.durationMinutes, 5);
  assert.equal(normalizeGuestPassInput({ door_id: 1, duration_minutes: 99999 }).value.durationMinutes, 1440);
  assert.equal(normalizeGuestPassInput({ door_id: 1, duration_minutes: '45' }).value.durationMinutes, 45);
  assert.equal(normalizeGuestPassInput({ door_id: 1, duration_minutes: 'abc' }).ok, false);
});

test('normalizeGuestPassInput: door_id dogrulamasi', () => {
  for (const bad of [undefined, null, 0, -1, 1.5, '1e2', 'abc', {}, []]) {
    assert.equal(normalizeGuestPassInput({ door_id: bad }).ok, false);
  }
  assert.equal(normalizeGuestPassInput(undefined).ok, false);
  assert.equal(normalizeGuestPassInput({ door_id: '12' }).value.doorId, 12);
});

test('getGuestPassState: oncelik iptal > sure > limit', () => {
  assert.equal(getGuestPassState(makePass(), NOW), 'ok');
  assert.equal(getGuestPassState(makePass({ is_active: false }), NOW), 'revoked');
  assert.equal(getGuestPassState(makePass({ expires_at: new Date(NOW.getTime() - 1) }), NOW), 'expired');
  assert.equal(getGuestPassState(makePass({ used_count: 1 }), NOW), 'exhausted');
  assert.equal(
    getGuestPassState(makePass({ is_active: false, used_count: 1, expires_at: new Date(0) }), NOW),
    'revoked',
  );
});

test('CLAIM_GUEST_PASS_SQL: atomik ve kosullu (tek UPDATE, kosullar WHERE icinde)', () => {
  const sql = CLAIM_GUEST_PASS_SQL.replace(/\s+/g, ' ').trim();
  assert.match(sql, /^UPDATE guest_passes SET used_count = used_count \+ 1 WHERE id = \$1 /);
  assert.ok(sql.includes('AND is_active = TRUE'));
  assert.ok(sql.includes('AND used_count < max_uses'));
  assert.ok(sql.includes('AND expires_at > NOW()'));
  assert.ok(sql.includes("pass_type <> 'single_use' OR used_count < 1"));
  assert.match(sql, /RETURNING .*used_count/);
  // Tek ifade: ayri SELECT yok, is_active'e dokunulmaz (iade iptali geri acmasin)
  assert.equal(/SELECT/i.test(sql), false);
  assert.equal(/SET[^W]*is_active/i.test(sql), false);
});

test('RELEASE_GUEST_PASS_SQL: sayac iade edilir, 0 altina inmez, is_active\'e dokunmaz', () => {
  const sql = RELEASE_GUEST_PASS_SQL.replace(/\s+/g, ' ').trim();
  assert.ok(sql.includes('used_count = GREATEST(used_count - 1, 0)'));
  assert.ok(sql.includes('AND used_count > 0'));
  assert.equal(/is_active/i.test(sql), false);
});
