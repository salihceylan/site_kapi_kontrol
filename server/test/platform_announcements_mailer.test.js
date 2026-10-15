// Duyuru e-postası (DB'siz, SAHTE taşıyıcı): konu, düz metin + HTML, CRLF/HTML enjeksiyonu, alıcı doğrulama, SMTP yapılandırma denetimi.
import { describe, it, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert/strict';
import nodemailer from 'nodemailer';
import { buildAnnouncementEmail, isSmtpConfigured, sendAnnouncementEmail } from '../src/mailer.js';

const XSS = '<img src=x onerror=alert(1)>';
const input = (overrides = {}) => ({ to: 'sakin@example.com', siteName: 'Gül Sitesi', title: 'Su kesintisi', body: 'Yarın 10:00-14:00 arası su yok.', importance: 'normal', ...overrides });

describe('buildAnnouncementEmail', () => {
  it('konu "[Site Adı] Başlık"; acil duyuruda "ACİL: " öneki; alıcı döner', () => {
    assert.equal(buildAnnouncementEmail(input()).subject, '[Gül Sitesi] Su kesintisi');
    assert.equal(buildAnnouncementEmail(input({ importance: 'urgent' })).subject, 'ACİL: [Gül Sitesi] Su kesintisi');
    assert.equal(buildAnnouncementEmail(input()).to, 'sakin@example.com');
  });

  it('alt bilgi: "Bu e-posta {site adı} yönetimi tarafından gönderildi. Bildirim tercihlerinizi uygulamadan değiştirebilirsiniz." (düz metin ve HTML)', () => {
    const footer = 'Bu e-posta Gül Sitesi yönetimi tarafından gönderildi. Bildirim tercihlerinizi uygulamadan değiştirebilirsiniz.';
    const message = buildAnnouncementEmail(input());
    assert.ok(message.text.endsWith(footer));
    assert.ok(message.html.includes(footer));
  });

  it('başlık / site adı satır başı enjeksiyonuna (CRLF) karşı temizlenir: konuda CR/LF yok', () => {
    const message = buildAnnouncementEmail(input({ title: 'Konu\r\nBcc: kurban@example.com', siteName: 'Site\nCc: x@y.com' }));
    assert.doesNotMatch(message.subject, /[\r\n]/);
    assert.equal(message.subject, '[Site Cc: x@y.com] Konu Bcc: kurban@example.com');
    assert.doesNotMatch(message.text.split('\n\n')[1] ?? '', /[\r]/);
  });

  it('gövde düz yazıdır: HTML\'de kaçırılır, satır sonları <br /> ile korunur; düz metinde ham metin LF ile', () => {
    const message = buildAnnouncementEmail(input({ body: `Satır 1\r\n${XSS}\r\nSatır 3 & "tırnak"` }));
    assert.ok(message.html.includes('&lt;img src=x onerror=alert(1)&gt;'));
    assert.ok(!message.html.includes('<img'));
    assert.ok(message.html.includes('Satır 1<br />&lt;img'));
    assert.ok(message.html.includes('&amp; &quot;tırnak&quot;'));
    assert.ok(message.text.includes(`Satır 1\n${XSS}\nSatır 3 & "tırnak"`));
    assert.ok(!message.text.includes('\r'));
  });

  it('başlık HTML\'de kaçırılır (XSS); kontrol karakterleri atılır', () => {
    const message = buildAnnouncementEmail(input({ title: `${XSS}${String.fromCharCode(7)}` }));
    assert.ok(message.html.includes('&lt;img'));
    assert.ok(!message.html.includes('<img'));
    assert.ok(!message.html.includes(String.fromCharCode(7)));
  });

  it('acil duyuruda HTML ve düz metinde "ACİL DUYURU" başlığı; normalde yok', () => {
    assert.ok(buildAnnouncementEmail(input({ importance: 'urgent' })).text.startsWith('ACİL DUYURU'));
    assert.ok(buildAnnouncementEmail(input({ importance: 'urgent' })).html.includes('ACİL DUYURU'));
    assert.ok(!buildAnnouncementEmail(input()).text.includes('ACİL'));
  });

  it('alıcı doğrulama: virgüllü / boşluklu / açılı ayraçlı / çok uzun / boş adres INVALID_RECIPIENT (alıcı listesi enjeksiyonu yok)', () => {
    for (const to of ['a@b.com, c@d.com', 'a@b.com;c@d.com', 'ad <a@b.com>', 'a@b', 'a b@c.com', '', null, undefined, `${'x'.repeat(250)}@b.com`, 'a@b.com\r\nBcc: c@d.com']) {
      assert.throws(() => buildAnnouncementEmail(input({ to })), (error) => error.code === 'INVALID_RECIPIENT', String(to));
    }
    assert.equal(buildAnnouncementEmail(input({ to: '  Sakin@Example.com ' })).to, 'Sakin@Example.com');
  });
});

describe('isSmtpConfigured', () => {
  it('sunucu + kullanıcı + parola + gönderen (SMTP_FROM ya da SMTP_USER) gerekir', () => {
    assert.equal(isSmtpConfigured({}), false);
    assert.equal(isSmtpConfigured({ SMTP_HOST: 'h', SMTP_USER: 'u' }), false);
    assert.equal(isSmtpConfigured({ SMTP_HOST: 'h', SMTP_USER: 'u', SMTP_PASSWORD: 'p' }), true, 'SMTP_FROM yoksa SMTP_USER kullanılır');
    assert.equal(isSmtpConfigured({ SMTP_HOST: '  ', SMTP_USER: 'u', SMTP_PASSWORD: 'p' }), false);
    assert.equal(isSmtpConfigured({ SMTP_HOST: 'h', SMTP_USER: 'u', SMTP_PASSWORD: 'p', SMTP_FROM: 'AHBU <n@x.com>' }), true);
  });
});

describe('sendAnnouncementEmail (sahte taşıyıcı)', () => {
  const sent = [];
  const saved = {};
  const originalCreateTransport = nodemailer.createTransport;

  beforeEach(() => {
    sent.length = 0;
    for (const name of ['SMTP_HOST', 'SMTP_USER', 'SMTP_PASSWORD', 'SMTP_FROM', 'SMTP_PORT']) saved[name] = process.env[name];
    Object.assign(process.env, { SMTP_HOST: 'smtp.invalid', SMTP_USER: 'user@example.invalid', SMTP_PASSWORD: 'test-only', SMTP_FROM: 'Site Yönetimi <noreply@example.invalid>' });
    delete process.env.SMTP_PORT;
    nodemailer.createTransport = () => ({
      sendMail: async (message) => {
        sent.push(message);
      },
    });
  });

  afterEach(() => {
    nodemailer.createTransport = originalCreateTransport;
    for (const [name, value] of Object.entries(saved)) {
      if (value === undefined) delete process.env[name];
      else process.env[name] = value;
    }
  });

  it('SMTP_FROM ile tek ileti gönderir: from, to, subject, text, html; cc / bcc yok', async () => {
    await sendAnnouncementEmail(input({ title: `Başlık\r\nBcc: z@y.com` }));
    assert.equal(sent.length, 1);
    assert.equal(sent[0].from, 'Site Yönetimi <noreply@example.invalid>');
    assert.equal(sent[0].to, 'sakin@example.com');
    assert.equal(sent[0].subject, '[Gül Sitesi] Başlık Bcc: z@y.com');
    assert.ok(typeof sent[0].text === 'string' && typeof sent[0].html === 'string');
    assert.equal('bcc' in sent[0] || 'cc' in sent[0], false);
  });

  it('geçersiz alıcı taşıyıcıya ULAŞMADAN reddedilir; SMTP ortamı eksikse hata verir (kuyruk bunu başarısızlık sayar)', async () => {
    await assert.rejects(() => sendAnnouncementEmail(input({ to: 'a@b.com, c@d.com' })), (error) => error.code === 'INVALID_RECIPIENT');
    assert.equal(sent.length, 0);
    delete process.env.SMTP_HOST;
    await assert.rejects(() => sendAnnouncementEmail(input()), /SMTP_HOST/);
    assert.equal(sent.length, 0);
  });
});
