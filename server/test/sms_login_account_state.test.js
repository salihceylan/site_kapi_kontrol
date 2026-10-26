// SMS ile giriş: silinmiş (kimliksizleştirilmiş) hesaba oturum / kod verilmez; must_change_password oturum yanıtına girer (POST /auth/login ile aynı tanım).
// DB'siz: sahte db.query SQL metnini okur ve `deleted_at IS NULL` süzgecini KENDİSİ uygular (süzgeç SQL'den kalkarsa test düşer).
import { describe, it, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { smsHooks } from '../src/modules/sms_provider.js';
import { hashCode, requestSmsCode, verifySmsCode } from '../src/modules/sms_login.js';
import { normalizePersonPhone } from '../src/modules/people_common.js';

const SECRET = 'sms-login-account-state-secret-0123456789abcdef0123456789';
const norm = (text) => String(text).replace(/\s+/g, ' ').trim();
const RAW_PHONE = '0532 111 22 33';
const PHONE = normalizePersonPhone(RAW_PHONE);

let savedSecret;
let savedProvider;
let sent;

beforeEach(() => {
  savedSecret = process.env.JWT_SECRET;
  process.env.JWT_SECRET = SECRET;
  savedProvider = smsHooks.provider;
  sent = [];
  smsHooks.provider = () => ({ name: 'test', send: async (phone, text) => sent.push({ phone, text }) });
});
afterEach(() => {
  smsHooks.provider = savedProvider;
  if (savedSecret === undefined) delete process.env.JWT_SECRET;
  else process.env.JWT_SECRET = savedSecret;
});

function userRow(extra = {}) {
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
    phone_number: '0532 111 22 33',
    created_at: new Date('2026-01-01T00:00:00Z'),
    password_hash: '$2a$04$abcdefghijklmnopqrstuuABCDEFGHIJKLMNOPQRSTUVWXYZ01234',
    deleted_at: null,
    must_change_password: false,
    pin_issued: false,
    ...extra,
  };
}

/** verifySmsCode için sahte db: kod satırı + kullanıcı SELECT'i (süzgeçleri SQL metnine bakarak uygular). */
function fakeDb(user, { log = [] } = {}) {
  const code = '123456';
  return {
    log,
    code,
    async query(text, params = []) {
      const sql = norm(text);
      log.push({ sql, params });
      if (/^UPDATE sms_login_codes SET attempts/.test(sql)) {
        return { rows: [{ id: 1, user_code: user.user_code, code_hash: hashCode(PHONE, code) }], rowCount: 1 };
      }
      if (/^UPDATE sms_login_codes SET consumed_at/.test(sql)) {
        return { rows: [{ id: 1 }], rowCount: 1 };
      }
      if (/^SELECT user_code AS id/.test(sql)) {
        if (/deleted_at IS NULL/.test(sql) && user.deleted_at) {
          return { rows: [], rowCount: 0 };
        }
        const flag = /must_change_password/.test(sql)
          ? { must_change_password: user.must_change_password === true || user.pin_issued === true }
          : {};
        const { must_change_password: _omit, pin_issued: _pin, deleted_at: _del, ...rest } = user;
        return { rows: [{ ...rest, ...flag }], rowCount: 1 };
      }
      if (/^SELECT user_code FROM users/.test(sql)) {
        if (/deleted_at IS NULL/.test(sql) && user.deleted_at) {
          return { rows: [], rowCount: 0 };
        }
        return { rows: [{ user_code: user.user_code }], rowCount: 1 };
      }
      if (/^SELECT COUNT\(\*\)/.test(sql)) {
        return { rows: [{ n: 0 }], rowCount: 1 };
      }
      return { rows: [], rowCount: 0 };
    },
  };
}

describe('SMS girişi: hesap durumu', () => {
  it('silinmiş hesap SMS koduyla oturum AÇAMAZ (kod doğru olsa bile 401 SMS_CODE_INVALID, jeton yok)', async () => {
    const db = fakeDb(userRow({ deleted_at: new Date('2026-02-01T00:00:00Z') }));
    await assert.rejects(
      () => verifySmsCode(RAW_PHONE, db.code, db),
      (error) => error.statusCode === 401 && error.code === 'SMS_CODE_INVALID',
    );
    const select = db.log.find((entry) => /^SELECT user_code AS id/.test(entry.sql));
    assert.match(select.sql, /FROM users WHERE user_code = \$1 AND deleted_at IS NULL/);
  });

  it('silinmiş hesap için kod İSTENİRSE SMS gönderilmez (kullanıcı varlığı yine sızmaz: yanıt aynı)', async () => {
    const db = fakeDb(userRow({ deleted_at: new Date('2026-02-01T00:00:00Z') }));
    const out = await requestSmsCode(RAW_PHONE, db);
    assert.equal(out.ok, true);
    assert.deepEqual(sent, [], 'silinmiş hesaba SMS gitmez');
    const lookup = db.log.find((entry) => /^SELECT user_code FROM users/.test(entry.sql));
    assert.match(lookup.sql, /deleted_at IS NULL/);
    const insert = db.log.find((entry) => /^INSERT INTO sms_login_codes/.test(entry.sql));
    assert.equal(insert.params[1], null, 'kod satırı kullanıcısız yazılır (doğrulamada reddedilir)');
  });

  it('etkin hesap için kod istenince SMS gider (silinmemiş hesap etkilenmez)', async () => {
    const db = fakeDb(userRow());
    await requestSmsCode(RAW_PHONE, db);
    assert.equal(sent.length, 1);
  });

  it('yönetimin verdiği geçici parola (users.must_change_password): bayrak oturum yanıtındaki kullanıcıya girer', async () => {
    const db = fakeDb(userRow({ must_change_password: true }));
    const out = await verifySmsCode(RAW_PHONE, db.code, db);
    assert.ok(out.token);
    assert.equal(out.user.id, 77);
    assert.equal(out.user.must_change_password, true);
    const select = db.log.find((entry) => /^SELECT user_code AS id/.test(entry.sql));
    assert.match(select.sql, /COALESCE\(users\.must_change_password, FALSE\) OR EXISTS \( SELECT 1 FROM apartments a WHERE a\.resident_user_code = users\.user_code AND a\.resident_pin_issued = TRUE \)\) AS must_change_password/);
  });

  it('dairede "PIN verildi" işaretli sakin hesabı da bayraklı sayılır; bayraksız hesapta false', async () => {
    const pin = await verifySmsCode(RAW_PHONE, '123456', fakeDb(userRow({ pin_issued: true })));
    assert.equal(pin.user.must_change_password, true);
    const plain = await verifySmsCode(RAW_PHONE, '123456', fakeDb(userRow()));
    assert.equal(plain.user.must_change_password, false);
  });

  it('pasif / doğrulanmamış / onaysız hesap eskisi gibi reddedilir', async () => {
    for (const extra of [{ is_active: false }, { email_verified: false }, { approval_status: 'pending' }]) {
      await assert.rejects(
        () => verifySmsCode(RAW_PHONE, '123456', fakeDb(userRow(extra))),
        (error) => error.code === 'SMS_CODE_INVALID',
        JSON.stringify(extra),
      );
    }
  });

  it('kaynak koruması: sms_login.js içindeki her users SELECT sorgusu silinmişi dışlar', () => {
    const source = norm(readFileSync(new URL('../src/modules/sms_login.js', import.meta.url), 'utf8'));
    const selects = source.match(/SELECT [^`]*? FROM users [^`]*?`/g) ?? [];
    assert.equal(selects.length, 2, 'telefon araması + oturum kullanıcısı');
    for (const select of selects) {
      assert.match(select, /deleted_at IS NULL/, select.slice(0, 80));
    }
  });
});
