// Bekleyen kayıt modeli: kullanıcı (users) satırı, e-posta sahipliği kanıtlanana (doğru kod) kadar OLUŞTURULMAZ.
// DB'siz: pool.query / pool.connect ve nodemailer sahte; beklenmeyen her SQL testi düşürür.
import { describe, it, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert/strict';
import bcrypt from 'bcryptjs';
import nodemailer from 'nodemailer';
import { pool } from '../src/db.js';

process.env.JWT_SECRET = process.env.JWT_SECRET || 'test-secret-for-pending-registration-0123456789abcdef';

const { registerIndividualUser, verifyIndividualEmailCode, resendIndividualVerificationCode } = await import(
  '../src/services/membership_service.js'
);

const flat = (text) => String(text).replace(/\s+/g, ' ').trim();
const PENDING_HASH = bcrypt.hashSync('abcdef12', 4);

const baseInput = { firstName: 'Ali', lastName: 'Veli', email: 'Ali@Example.com', password: 'abcdef12' };

function userRow(overrides = {}) {
  return {
    id: 77,
    user_code: 77,
    full_name: 'Ali Veli',
    email: 'ali@example.com',
    login_name: null,
    role: 'individual',
    is_active: true,
    email_verified: true,
    approval_status: 'approved',
    phone_number: null,
    created_at: new Date('2026-10-02T00:00:00Z'),
    password_hash: PENDING_HASH,
    ...overrides,
  };
}

async function waitFor(predicate, timeoutMs = 2000) {
  const start = Date.now();
  while (!predicate()) {
    if (Date.now() - start > timeoutMs) throw new Error('waitFor zaman asimi');
    await new Promise((resolve) => setTimeout(resolve, 10));
  }
}

describe('bekleyen kayıt: kayıt / doğrulama / yeniden gönderme', () => {
  const original = {
    query: pool.query,
    connect: pool.connect,
    createTransport: nodemailer.createTransport,
    consoleError: console.error,
  };
  const savedEnv = {};
  let log;
  let sent;
  let state;

  const queryOf = (re) => log.find((entry) => re.test(entry.sql));
  const has = (re) => log.some((entry) => re.test(entry.sql));
  const indexOf = (re) => log.findIndex((entry) => re.test(entry.sql));

  async function poolQuery(text, params = []) {
    const sql = flat(text);
    log.push({ via: 'pool', sql, params });
    if (/^SELECT user_code, email, email_verified, role FROM users/.test(sql)) {
      return { rows: state.existingUser ? [state.existingUser] : [], rowCount: state.existingUser ? 1 : 0 };
    }
    if (/^SELECT user_code, full_name, email_verified FROM users/.test(sql)) {
      return { rows: state.resendUser ? [state.resendUser] : [], rowCount: state.resendUser ? 1 : 0 };
    }
    if (/^INSERT INTO pending_registrations/.test(sql)) return { rows: [], rowCount: 1 };
    if (/^UPDATE users SET full_name/.test(sql)) return { rows: [], rowCount: 1 };
    if (/^SELECT full_name FROM pending_registrations/.test(sql)) {
      return {
        rows: state.pendingFound ? [{ full_name: state.pendingFound }] : [],
        rowCount: state.pendingFound ? 1 : 0,
      };
    }
    if (/^DELETE FROM email_verifications WHERE id = \$1/.test(sql)) return { rows: [], rowCount: 1 };
    if (/^UPDATE email_verifications SET is_verified = TRUE WHERE LOWER\(email\) = LOWER\(\$1\) AND is_verified = FALSE AND id < \$2/.test(sql)) {
      return { rows: [], rowCount: 1 };
    }
    throw new Error(`beklenmeyen pool sorgusu: ${sql}`);
  }

  async function clientQuery(text, params = []) {
    const sql = flat(text);
    log.push({ via: 'client', sql, params });
    if (sql === 'BEGIN' || sql === 'COMMIT' || sql === 'ROLLBACK') return { rows: [], rowCount: 0 };
    if (sql.startsWith('SELECT pg_advisory_xact_lock')) return { rows: [], rowCount: 1 };
    if (sql.includes('AS seconds_since_last')) return { rows: [state.issueState], rowCount: 1 };
    if (/^UPDATE email_verifications SET is_verified = TRUE WHERE LOWER\(email\)/.test(sql)) {
      return { rows: [], rowCount: 0 };
    }
    if (/^INSERT INTO email_verifications/.test(sql)) return { rows: [{ id: 501 }], rowCount: 1 };
    if (sql.includes('attempt_count = ev.attempt_count + 1')) {
      return { rows: state.claimRows, rowCount: state.claimRows.length };
    }
    if (/^UPDATE email_verifications SET is_verified = TRUE, verified_at = NOW\(\)/.test(sql)) {
      return { rows: [{ id: 700 }], rowCount: 1 };
    }
    if (/^UPDATE users SET email_verified = TRUE/.test(sql)) {
      return { rows: state.verifiedUserRows, rowCount: state.verifiedUserRows.length };
    }
    if (/^DELETE FROM pending_registrations/.test(sql)) {
      return { rows: state.pendingTaken, rowCount: state.pendingTaken.length };
    }
    if (/^INSERT INTO users/.test(sql)) {
      if (state.insertError) throw state.insertError;
      return { rows: state.insertedUserRows, rowCount: state.insertedUserRows.length };
    }
    if (sql.includes('FROM site_manager_invitations')) return { rows: [], rowCount: 0 };
    throw new Error(`beklenmeyen client sorgusu: ${sql}`);
  }

  beforeEach(() => {
    for (const name of ['SMTP_HOST', 'SMTP_USER', 'SMTP_PASSWORD', 'SMTP_FROM']) savedEnv[name] = process.env[name];
    process.env.SMTP_HOST = 'smtp.invalid';
    process.env.SMTP_USER = 'user@example.invalid';
    process.env.SMTP_PASSWORD = 'test-only';
    process.env.SMTP_FROM = 'AHBU <noreply@example.invalid>';

    log = [];
    sent = [];
    state = {
      existingUser: null,
      resendUser: null,
      pendingFound: null,
      mailFails: false,
      issueState: { seconds_since_last: null, codes_last_hour: 0 },
      claimRows: [],
      verifiedUserRows: [],
      pendingTaken: [],
      insertedUserRows: [],
      insertError: null,
    };
    pool.query = poolQuery;
    pool.connect = async () => ({ query: clientQuery, release() {} });
    nodemailer.createTransport = () => ({
      sendMail: async (message) => {
        if (state.mailFails) throw Object.assign(new Error('simulated smtp failure'), { code: 'ETIMEDOUT' });
        sent.push(message);
      },
    });
    console.error = () => {};
  });

  afterEach(() => {
    pool.query = original.query;
    pool.connect = original.connect;
    nodemailer.createTransport = original.createTransport;
    console.error = original.consoleError;
    for (const [name, value] of Object.entries(savedEnv)) {
      if (value === undefined) delete process.env[name];
      else process.env[name] = value;
    }
  });

  // ------------------------------------------------------------------ kayıt
  describe('registerIndividualUser', () => {
    it('yeni e-posta: users satırı OLUŞMAZ; bekleyen kayıt yazılır ve kod e-postayla gider', async () => {
      const result = await registerIndividualUser(baseInput);

      assert.equal(result.ok, true);
      assert.equal(result.email, 'ali@example.com');
      assert.equal(result.code_length, 6);
      assert.equal(result.expires_in_minutes, 30);
      assert.equal(has(/^INSERT INTO users/), false, 'doğrulama öncesi users satırı oluşturuldu');

      const upsert = queryOf(/^INSERT INTO pending_registrations/);
      assert.ok(upsert, 'bekleyen kayıt yazılmadı');
      assert.deepEqual(upsert.params.slice(0, 2), ['ali@example.com', 'Ali Veli']);
      assert.match(upsert.params[2], /^\$2[aby]\$/, 'parola bcrypt özeti olarak saklanmalı');
      assert.equal(await bcrypt.compare('abcdef12', upsert.params[2]), true);
      assert.equal(upsert.params[3], 501, 'upsert, kendi kod satırına (bayat gönderim koruması) bağlanmalı');

      assert.equal(sent.length, 1);
      assert.equal(sent[0].to, 'ali@example.com');
      assert.match(sent[0].text, /\b\d{6}\b/);
    });

    it('kod düz metin saklanmaz (bcrypt özeti); satır, e-posta gönderilmeden önce kalıcılaşır', async () => {
      await registerIndividualUser(baseInput);
      const insert = queryOf(/^INSERT INTO email_verifications/);
      assert.ok(insert);
      const code = sent[0].text.match(/\b(\d{6})\b/)[1];
      assert.notEqual(insert.params[1], code);
      assert.equal(await bcrypt.compare(code, insert.params[1]), true);
      assert.ok(indexOf(/^COMMIT$/) > indexOf(/^INSERT INTO email_verifications/));
    });

    it('e-posta gönderilemezse 503 EMAIL_DELIVERY_FAILED; üretilen kod satırı silinir; users satırı yok', async () => {
      state.mailFails = true;
      await assert.rejects(
        () => registerIndividualUser(baseInput),
        (error) =>
          error.statusCode === 503 &&
          error.code === 'EMAIL_DELIVERY_FAILED' &&
          error.expose === true &&
          /gönderilemiyor/.test(error.message) &&
          !/gönderildi/.test(error.message),
      );
      assert.deepEqual(queryOf(/^DELETE FROM email_verifications WHERE id = \$1/).params, [501]);
      assert.equal(has(/^INSERT INTO users/), false);
      assert.equal(has(/^INSERT INTO pending_registrations/), false, 'gönderilemeyen denemede bekleyen kayıt DEĞİŞMEMELİ');
    });

    it('e-posta başarıyla gidince sıra: ekle -> gönder -> kimlik bilgilerini yaz -> yalnızca ESKİ kodları kapat', async () => {
      const order = [];
      const baseCreate = nodemailer.createTransport;
      nodemailer.createTransport = (options) => {
        const transport = baseCreate(options);
        return {
          sendMail: async (message) => {
            order.push('send');
            return transport.sendMail(message);
          },
        };
      };
      const baseQuery = pool.query;
      pool.query = async (text, params) => {
        const sql = flat(text);
        if (/^INSERT INTO pending_registrations/.test(sql)) order.push('persist');
        if (/AND id < \$2/.test(sql)) order.push('supersede');
        return baseQuery(text, params);
      };

      await registerIndividualUser(baseInput);

      const supersede = queryOf(/AND id < \$2/);
      assert.deepEqual(supersede.params, ['ali@example.com', 501]);
      assert.deepEqual(order, ['send', 'persist', 'supersede']);
    });

    it('e-posta GİTMEZSE önceki geçerli kod iptal edilmez (geç ulaşan eski kod boşa çıkmaz)', async () => {
      state.mailFails = true;
      await assert.rejects(() => registerIndividualUser(baseInput), (error) => error.statusCode === 503);
      assert.equal(has(/AND id < \$2/), false, 'gönderim başarısızken eski kodlar kapatıldı');
      assert.equal(has(/^UPDATE email_verifications SET is_verified = TRUE WHERE LOWER\(email\)/), false);
    });

    it('reddedilen denemeler (bekleme / saatlik tavan) bekleyen kaydı ve eski hesabı DEĞİŞTİRMEZ', async () => {
      state.issueState = { seconds_since_last: 5, codes_last_hour: 1 };
      await assert.rejects(() => registerIndividualUser(baseInput), (error) => error.statusCode === 429);
      state.issueState = { seconds_since_last: 9999, codes_last_hour: 10 };
      await assert.rejects(() => registerIndividualUser(baseInput), (error) => error.statusCode === 429);
      state.existingUser = { user_code: 9, email: 'ali@example.com', email_verified: false, role: 'individual' };
      await assert.rejects(() => registerIndividualUser(baseInput), (error) => error.statusCode === 429);
      assert.equal(has(/^INSERT INTO pending_registrations/), false);
      assert.equal(has(/^UPDATE users SET full_name/), false);
    });

    it('SMTP hata günlüğünde alıcı e-posta adresi (kişisel veri) maskelenir', async () => {
      const logged = [];
      console.error = (...args) => logged.push(args);
      nodemailer.createTransport = () => ({
        sendMail: async () => {
          throw Object.assign(new Error('550 5.1.1 <ali@example.com>: Recipient address rejected'), {
            code: 'EENVELOPE',
            responseCode: 550,
          });
        },
      });
      await assert.rejects(() => registerIndividualUser(baseInput), (error) => error.statusCode === 503);
      const text = JSON.stringify(logged);
      assert.equal(text.includes('ali@example.com'), false, 'e-posta adresi günlüğe sızdı');
      assert.match(text, /EENVELOPE/);
      assert.match(text, /550/);
    });

    it('bekleme süresi içindeyse 429 ve kalan saniye söylenir; e-posta gönderilmez', async () => {
      state.issueState = { seconds_since_last: 10, codes_last_hour: 1 };
      await assert.rejects(
        () => registerIndividualUser(baseInput),
        (error) => error.statusCode === 429 && /20 saniye/.test(error.message),
      );
      assert.equal(sent.length, 0);
      assert.equal(has(/^INSERT INTO email_verifications/), false);
    });

    it('saatlik kod tavanı aşıldıysa 429; e-posta gönderilmez', async () => {
      state.issueState = { seconds_since_last: 9999, codes_last_hour: 10 };
      await assert.rejects(
        () => registerIndividualUser(baseInput),
        (error) => error.statusCode === 429,
      );
      assert.equal(sent.length, 0);
    });

    it('doğrulanmış hesap varsa 409; bekleyen kayıt yazılmaz, e-posta gitmez', async () => {
      state.existingUser = { user_code: 1, email: 'ali@example.com', email_verified: true, role: 'individual' };
      await assert.rejects(
        () => registerIndividualUser(baseInput),
        (error) => error.statusCode === 409,
      );
      assert.equal(has(/^INSERT INTO pending_registrations/), false);
      assert.equal(sent.length, 0);
    });

    it('eski doğrulanmamış bireysel hesap: UPDATE ile güncellenir, bekleyen kayıt yazılmaz, kod gider', async () => {
      state.existingUser = { user_code: 9, email: 'ali@example.com', email_verified: false, role: 'individual' };
      const result = await registerIndividualUser(baseInput);
      assert.equal(result.ok, true);
      const update = queryOf(/^UPDATE users SET full_name/);
      assert.ok(update);
      assert.deepEqual([update.params[0], update.params[2], update.params[3], update.params[4]], ['Ali Veli', 9, 'ali@example.com', 501]);
      assert.equal(has(/^INSERT INTO pending_registrations/), false);
      assert.equal(sent.length, 1);
    });
  });

  // ------------------------------------------------------------------ doğrulama
  describe('verifyIndividualEmailCode', () => {
    const CODE = '123456';

    beforeEach(() => {
      state.claimRows = [{ id: 700, code_hash: bcrypt.hashSync(CODE, 4), attempt_count: 1 }];
    });

    it('doğru kod: users satırı ŞİMDİ oluşturulur, bekleyen kayıt silinir, oturum belirteci döner', async () => {
      state.pendingTaken = [{ full_name: 'Ali Veli', password_hash: PENDING_HASH }];
      state.insertedUserRows = [userRow()];

      const result = await verifyIndividualEmailCode({ email: 'ali@example.com', code: CODE });

      assert.equal(result.ok, true);
      assert.ok(result.token);
      assert.equal(result.user.email, 'ali@example.com');
      assert.equal('password_hash' in result.user, false);

      const insert = queryOf(/^INSERT INTO users/);
      assert.ok(insert, 'users satırı oluşturulmadı');
      assert.match(insert.sql, /VALUES \(\$1, \$2, 'individual', TRUE, TRUE, 'approved', \$3\)/);
      assert.deepEqual(insert.params, ['Ali Veli', 'ali@example.com', PENDING_HASH]);
      assert.ok(
        indexOf(/^UPDATE email_verifications SET is_verified = TRUE, verified_at/) <
          indexOf(/^INSERT INTO users/),
        'kod tüketilmeden hesap açıldı',
      );
      assert.ok(has(/^DELETE FROM pending_registrations/));
      assert.ok(has(/^COMMIT$/));
    });

    it('users satırı zaten varsa (eski doğrulanmamış hesap) bekleyen kayda bakılmaz, satır oluşturulmaz', async () => {
      state.verifiedUserRows = [userRow()];
      const result = await verifyIndividualEmailCode({ email: 'ali@example.com', code: CODE });
      assert.equal(result.ok, true);
      assert.equal(has(/^DELETE FROM pending_registrations/), false);
      assert.equal(has(/^INSERT INTO users/), false);
    });

    it('ne users satırı ne bekleyen kayıt varsa 404 ve işlem GERİ ALINIR (kod tüketilmez)', async () => {
      await assert.rejects(
        () => verifyIndividualEmailCode({ email: 'ali@example.com', code: CODE }),
        (error) => error.statusCode === 404 && /yeniden kay/i.test(error.message),
      );
      assert.ok(has(/^ROLLBACK$/));
      assert.equal(has(/^COMMIT$/), false);
    });

    it('hesap açılırken aynı e-posta başka biri tarafından alınmışsa (23505) 409 ve geri alma', async () => {
      state.pendingTaken = [{ full_name: 'Ali Veli', password_hash: PENDING_HASH }];
      state.insertError = Object.assign(new Error('duplicate key value violates unique constraint'), {
        code: '23505',
      });
      await assert.rejects(
        () => verifyIndividualEmailCode({ email: 'ali@example.com', code: CODE }),
        (error) => error.statusCode === 409,
      );
      assert.ok(has(/^ROLLBACK$/));
    });

    it('yanlış kod: 400; deneme sayacı kalıcı (COMMIT); users / bekleyen kayıta dokunulmaz', async () => {
      await assert.rejects(
        () => verifyIndividualEmailCode({ email: 'ali@example.com', code: '654321' }),
        (error) => error.statusCode === 400,
      );
      assert.ok(has(/^COMMIT$/));
      assert.equal(has(/^INSERT INTO users/), false);
      assert.equal(has(/^DELETE FROM pending_registrations/), false);
    });
  });

  // ------------------------------------------------------------------ tekrar gönder
  describe('resendIndividualVerificationCode', () => {
    it('users yok ama bekleyen kayıt varsa kod yeniden gönderilir (ad bekleyen kayıttan)', async () => {
      state.pendingFound = 'Ali Veli';
      const response = await resendIndividualVerificationCode({ email: 'ali@example.com' });
      assert.equal(response.ok, true);
      await waitFor(() => sent.length === 1);
      assert.match(sent[0].text, /Ali Veli/);
    });

    it('ne hesap ne bekleyen kayıt varsa e-posta gitmez; yanıt aynıdır (enumeration yok)', async () => {
      const unknown = await resendIndividualVerificationCode({ email: 'yok@example.com' });
      state.pendingFound = 'Ali Veli';
      const known = await resendIndividualVerificationCode({ email: 'ali@example.com' });
      assert.deepEqual(unknown, known);
      await new Promise((resolve) => setTimeout(resolve, 50));
      assert.equal(sent.filter((message) => message.to === 'yok@example.com').length, 0);
    });
  });
});
