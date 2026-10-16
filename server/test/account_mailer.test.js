// "Hesabınız silindi" e-postası (DB'siz, SMTP yok): sabit konu (kullanıcı verisi yok), HTML kaçışı, düz metinde tek satır ad, tarih, adres yalnız alıcıda.
import { describe, it, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert/strict';
import nodemailer from 'nodemailer';
import { ACCOUNT_DELETED_SUBJECT, sendAccountDeletedEmail } from '../src/mailer.js';

const XSS = '<img src=x onerror=alert(1)>';
const INJECT = 'Ada\r\nBcc: kurban@example.com\r\nSubject: x';

describe('hesap silindi e-postası', () => {
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
    process.env.SMTP_FROM = 'Platform <noreply@example.invalid>';
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

  it('konu SABİT ve ürün adını taşır (kullanıcı verisi içermez)', () => {
    assert.equal(ACCOUNT_DELETED_SUBJECT, 'Site ve Toplu Yaşam Yönetim Sistemi - Hesabınız Silindi');
    assert.equal(/AHBU/.test(ACCOUNT_DELETED_SUBJECT), false);
  });

  it('eski adrese tek ileti: alıcı, gönderen, sabit konu; metin ve HTML silme tarihini ve yeniden kayıt bilgisini içerir', async () => {
    await sendAccountDeletedEmail({ to: 'ada@example.com', fullName: 'Ada Lovelace', deletedAt: new Date('2026-10-16T10:30:00Z') });
    assert.equal(sent.length, 1);
    const { to, from, subject, text, html } = sent[0];
    assert.equal(to, 'ada@example.com');
    assert.equal(from, 'Platform <noreply@example.invalid>');
    assert.equal(subject, ACCOUNT_DELETED_SUBJECT);
    assert.ok(text.startsWith('Merhaba Ada Lovelace,'));
    assert.ok(/2026/.test(text) && /Ekim/.test(text), 'silme tarihi (İstanbul saati)');
    assert.ok(text.includes('yeniden kayıt'));
    assert.ok(text.includes('siz yapmadıysanız'));
    assert.ok(html.includes('Hesabınız Silindi'));
  });

  it('ad HTML\'de kaçırılır; satır sonu (CRLF) enjeksiyonu konuya / başlıklara giremez; düz metinde ad tek satır', async () => {
    await sendAccountDeletedEmail({ to: 'ada@example.com', fullName: XSS, deletedAt: new Date() });
    assert.equal(sent[0].html.includes('<img'), false);
    assert.ok(sent[0].html.includes('&lt;img src=x onerror=alert(1)&gt;'));

    sent.length = 0;
    await sendAccountDeletedEmail({ to: 'ada@example.com', fullName: INJECT, deletedAt: new Date() });
    const { subject, text } = sent[0];
    assert.equal(/[\r\n]/.test(subject), false);
    assert.equal(text.split('\n')[0].includes('Bcc:'), true, 'enjekte metin yalnız ilk (selamlama) satırında kalır');
    assert.equal(/\r/.test(text.split('\n')[0]), false);
    assert.equal(sent[0].headers, undefined);
  });

  it('ad yoksa "Kullanıcı"; e-posta adresi gövdede ve konuda GEÇMEZ (yalnız alıcı alanında)', async () => {
    await sendAccountDeletedEmail({ to: 'ada@example.com', fullName: '', deletedAt: new Date() });
    const { text, html, subject } = sent[0];
    assert.ok(text.startsWith('Merhaba Kullanıcı,'));
    for (const part of [text, html, subject]) {
      assert.equal(part.includes('ada@example.com'), false);
    }
  });

  it('SMTP_FROM yoksa gönderilemez (hata fırlatır; çağıran silmeyi geri almaz, yalnız kodla loglar)', async () => {
    delete process.env.SMTP_FROM;
    delete process.env.SMTP_USER;
    await assert.rejects(sendAccountDeletedEmail({ to: 'ada@example.com', fullName: 'Ada' }), /SMTP_FROM veya SMTP_USER/);
    assert.equal(sent.length, 0);
  });
});
