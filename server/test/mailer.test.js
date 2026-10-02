import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import nodemailer from 'nodemailer';
import {
  formatIstanbulTime,
  sendIndividualVerificationEmail,
  sendJoinRequestNotificationEmail,
  sendPasswordResetEmail,
} from '../src/mailer.js';

describe('Mailer Tests', () => {
  it('sendJoinRequestNotificationEmail is a defined function', () => {
    assert.equal(typeof sendJoinRequestNotificationEmail, 'function');
  });

  it('sendPasswordResetEmail is a defined function', () => {
    assert.equal(typeof sendPasswordResetEmail, 'function');
  });

  it('rejects when SMTP environment variables are missing', async () => {
    const originalHost = process.env.SMTP_HOST;
    const originalFrom = process.env.SMTP_FROM;
    try {
      delete process.env.SMTP_FROM;
      delete process.env.SMTP_USER;
      await assert.rejects(
        () =>
          sendJoinRequestNotificationEmail({
            to: 'manager@example.com',
            managerName: 'Ali Yönetici',
            siteName: 'Güneş Sitesi',
            blockName: 'A Blok',
            unitLabel: '5',
            applicantName: 'Ahmet Yılmaz',
            applicantEmail: 'ahmet@example.com',
            notes: 'Yeni taşındım',
          }),
        /env degiskeni eksik/i,
      );
    } finally {
      if (originalHost) process.env.SMTP_HOST = originalHost;
      if (originalFrom) process.env.SMTP_FROM = originalFrom;
    }
  });
});

describe('Mailer: doğrulama e-postası (gecikmeye dayanıklı, istek saati ve süre belli)', () => {
  const saved = {};
  const originalCreateTransport = nodemailer.createTransport;

  function withSmtpEnv(run) {
    return async () => {
      for (const name of ['SMTP_HOST', 'SMTP_USER', 'SMTP_PASSWORD', 'SMTP_FROM', 'SMTP_PORT']) saved[name] = process.env[name];
      process.env.SMTP_HOST = 'smtp.invalid';
      process.env.SMTP_USER = 'user@example.invalid';
      process.env.SMTP_PASSWORD = 'test-only';
      process.env.SMTP_FROM = 'AHBU <noreply@example.invalid>';
      delete process.env.SMTP_PORT;
      const options = [];
      const messages = [];
      nodemailer.createTransport = (opts) => {
        options.push(opts);
        return { sendMail: async (message) => messages.push(message) };
      };
      try {
        await run({ options, messages });
      } finally {
        nodemailer.createTransport = originalCreateTransport;
        for (const [name, value] of Object.entries(saved)) {
          if (value === undefined) delete process.env[name];
          else process.env[name] = value;
        }
      }
    };
  }

  it('formatIstanbulTime: UTC zamanını İstanbul saatine (UTC+3) 24 saatlik biçimde çevirir', () => {
    assert.equal(formatIstanbulTime(new Date('2026-10-02T11:32:00Z')), '14:32');
    assert.equal(formatIstanbulTime(new Date('2026-10-02T21:05:00Z')), '00:05');
  });

  it('SMTP taşıyıcısı sınırlı zaman aşımlarıyla kurulur (askıda kalan bağlantı isteği bekletmez)', withSmtpEnv(async ({ options }) => {
    await sendIndividualVerificationEmail({ to: 'a@example.com', fullName: 'Ali', code: '123456', ttlMinutes: 30 });
    assert.equal(options.length, 1);
    for (const key of ['connectionTimeout', 'greetingTimeout', 'socketTimeout']) {
      assert.equal(typeof options[0][key], 'number', `${key} tanımlı değil`);
      assert.ok(options[0][key] > 0 && options[0][key] <= 30000, `${key} makul aralıkta değil`);
    }
  }));

  it('e-posta kodu, istek saatini ve geçerlilik süresini söyler; yalnızca en son kodun geçerli olduğunu belirtir', withSmtpEnv(async ({ messages }) => {
    await sendIndividualVerificationEmail({
      to: 'a@example.com',
      fullName: 'Ali <b>',
      code: '123456',
      ttlMinutes: 30,
      requestedAt: new Date('2026-10-02T11:32:00Z'),
    });
    const [message] = messages;
    assert.match(message.text, /123456/);
    for (const body of [message.text, message.html]) {
      assert.match(body, /14:32/);
      assert.match(body, /30 dakika/);
      assert.match(body, /en son/i);
    }
    assert.equal(message.html.includes('Ali <b>'), false, 'ad HTML için kaçırılmalı');
  }));
});

