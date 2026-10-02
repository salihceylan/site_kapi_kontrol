import { describe, it, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert/strict';
import nodemailer from 'nodemailer';
import {
  escapeHtml,
  safeHttpUrl,
  sendApartmentCredentialsEmail,
  sendJoinRequestNotificationEmail,
  sendPasswordResetEmail,
  sendSiteManagerInvitationEmail,
  sendSuperUserSiteDeletionEmail,
  singleLine,
} from '../src/mailer.js';

const XSS = '<img src=x onerror=alert(1)>';

describe('mailer sablon kacirma (HTML-escape)', () => {
  const sent = [];
  const saved = {};
  const originalCreateTransport = nodemailer.createTransport;

  beforeEach(() => {
    sent.length = 0;
    for (const name of ['SMTP_HOST', 'SMTP_USER', 'SMTP_PASSWORD', 'SMTP_FROM', 'SMTP_PORT']) {
      saved[name] = process.env[name];
    }
    process.env.SMTP_HOST = 'smtp.invalid';
    process.env.SMTP_USER = 'user@example.invalid';
    process.env.SMTP_PASSWORD = 'test-only';
    process.env.SMTP_FROM = 'AHBU <noreply@example.invalid>';
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

  it('escapeHtml: tum HTML ozel karakterleri ve backtick kacirilir, kontrol karakterleri atilir', () => {
    assert.equal(escapeHtml(`<a href="x" onclick='y'>&\`</a>`), '&lt;a href=&quot;x&quot; onclick=&#39;y&#39;&gt;&amp;&#96;&lt;/a&gt;');
    assert.equal(escapeHtml('a\u0000b\u0008c'), 'abc');
    assert.equal(escapeHtml(null), '');
    assert.equal(escapeHtml(undefined), '');
    assert.equal(escapeHtml(42), '42');
  });

  it('singleLine: satir sonlari/kontrol karakterleri temizlenir (header injection)', () => {
    assert.equal(singleLine('Konu\r\nBcc: kurban@example.com'), 'Konu Bcc: kurban@example.com');
    assert.equal(singleLine('a b'), 'a b');
    assert.equal(singleLine('x'.repeat(500)).length, 200);
  });

  it('safeHttpUrl: yalnizca http/https', () => {
    assert.equal(safeHttpUrl('https://api.example.com/auth/reset-password?token=abc'), 'https://api.example.com/auth/reset-password?token=abc');
    assert.equal(safeHttpUrl('javascript:alert(1)'), '');
    assert.equal(safeHttpUrl('data:text/html,<script>alert(1)</script>'), '');
    assert.equal(safeHttpUrl('not a url'), '');
  });

  it('katilim bildirimi: kullanici kontrollu alanlar HTML te kacirilir, metin/konu cift kacirilmaz', async () => {
    await sendJoinRequestNotificationEmail({
      to: 'manager@example.com',
      managerName: XSS,
      siteName: `Site ${XSS}`,
      blockName: 'A&B Blok',
      unitLabel: '<5>',
      applicantName: XSS,
      applicantEmail: `x"${XSS}@example.com`,
      notes: `not ${XSS}`,
    });
    assert.equal(sent.length, 1);
    const { html, text, subject } = sent[0];
    assert.equal(html.includes('<img'), false, 'ham etiket HTML e girmemeli');
    assert.ok(html.includes('&lt;img src=x onerror=alert(1)&gt;'));
    assert.ok(html.includes('A&amp;B Blok Daire &lt;5&gt;'));
    // Duz metin ve konu HTML varlik kodu icermemeli (cift kacirma yok)
    assert.ok(text.includes('A&B Blok Daire <5>'));
    assert.equal(text.includes('&amp;'), false);
    assert.equal(subject.includes('&amp;'), false);
    assert.ok(subject.includes('A&B Blok Daire <5>'));
  });

  it('davet e-postasi: site/davet eden/kullanici adi kacirilir; konuda satir sonu yok', async () => {
    await sendSiteManagerInvitationEmail({
      to: 'yeni@example.com',
      fullName: XSS,
      siteName: `Site\r\nBcc: kurban@example.com ${XSS}`,
      inviterName: XSS,
      isExistingUser: false,
    });
    const { html, subject } = sent[0];
    assert.equal(html.includes('<img'), false);
    assert.equal(/[\r\n]/.test(subject), false);
  });

  it('silme dogrulama e-postasi: site adi ve ad kacirilir; konu tek satir', async () => {
    await sendSuperUserSiteDeletionEmail({ to: 'a@example.com', fullName: XSS, siteName: `S\r\n${XSS}`, code: '123456' });
    const { html, subject } = sent[0];
    assert.equal(html.includes('<img'), false);
    assert.equal(/[\r\n]/.test(subject), false);
  });

  it('daire giris bilgileri e-postasi: tum alanlar kacirilir', async () => {
    await sendApartmentCredentialsEmail({
      to: 'a@example.com',
      residentName: XSS,
      apartmentLabel: XSS,
      siteName: XSS,
      loginName: XSS,
      pinCode: XSS,
    });
    assert.equal(sent[0].html.includes('<img'), false);
  });

  it('sifre sifirlama: ad kacirilir; javascript: baglantisi href e girmez', async () => {
    await sendPasswordResetEmail({ to: 'a@example.com', fullName: XSS, resetUrl: 'javascript:alert(1)' });
    assert.equal(sent[0].html.includes('<img'), false);
    assert.equal(sent[0].html.includes('javascript:'), false);

    sent.length = 0;
    await sendPasswordResetEmail({
      to: 'a@example.com',
      fullName: 'Ali',
      resetUrl: 'https://api.example.com/auth/reset-password?token=abc&x="onmouseover="alert(1)',
    });
    assert.equal(sent[0].html.includes('"onmouseover'), false);
    assert.ok(sent[0].html.includes('https://api.example.com/auth/reset-password?token=abc'));
  });
});
